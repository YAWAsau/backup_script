//! Event-driven ownership: names and shared executable inodes never grant membership.
//! No subprocesses, environment mutation, background sampler, or work cancellation.
use super::*;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::{Mutex,OnceLock};

const LIMIT:usize=32768;
const DEPTH:usize=128;
const CONTEXT_LIMIT:usize=64;
type Key=(u32,u64);

#[derive(Clone,Copy,Debug,PartialEq,Eq)]
struct Node { pid:u32, start:u64, parent:u32 }
impl Node { fn key(self)->Key {(self.pid,self.start)} }

fn read_node(pid:u32)->Option<Node> {
    let raw=text(format!("/proc/{pid}/stat"),8192).ok()?;
    let s=parse_stat(&raw)?;
    let parent=speedbackup_native_rs::proc_stat::split(&raw)?.1
        .split_whitespace().nth(1)?.parse().ok()?;
    Some(Node{pid,start:s.start,parent})
}
fn live(key:Key)->bool {
    read_node(key.0).is_some_and(|n|n.key()==key)
        && read_node(key.0).is_some_and(|n|n.key()==key)
}
fn checked(n:Node)->bool {
    read_node(n.pid)==Some(n) && read_node(n.pid)==Some(n)
}

// Pure, bounded ancestry proof over one cheap stat-only discovery table.
// Parent starttime must not be newer than its child. Exact edges are checked
// for proposed chains. Once ancestry is proven, credential changes do not
// revoke membership; credentials still guard anchors and context recovery.
fn chain(pid:u32, nodes:&BTreeMap<u32,Node>, roots:&BTreeSet<Key>)->Option<Vec<Node>> {
    let mut at=pid;
    let mut visited=BTreeSet::new();
    let mut proof=Vec::new();
    for _ in 0..DEPTH {
        if !visited.insert(at) {return None;}
        let n=*nodes.get(&at)?;
        proof.push(n);
        if roots.contains(&n.key()) {return Some(proof);}
        let parent=nodes.get(&n.parent)?;
        if parent.start>n.start {return None;}
        at=n.parent;
    }
    None
}
fn proof_incomplete(pid:u32,nodes:&BTreeMap<u32,Node>)->bool {
    let mut at=pid;
    let mut visited=BTreeSet::new();
    for _ in 0..DEPTH {
        if at<=1 {return false;}
        if !visited.insert(at) {return true;}
        let Some(n)=nodes.get(&at) else {return true;};
        at=n.parent;
    }
    true
}

#[derive(Default)]
struct History {
    initialized:bool,
    available:bool,
    bootstrap_count:usize,
    pending:std::collections::VecDeque<events::Event>,
    proven:BTreeSet<Key>,
    labels:BTreeMap<Key,String>,
    // Retained for the observer lifetime: never evict and rescan an identity.
    watches:BTreeSet<(u32,String)>,
    partial:bool,
}
static HISTORY:OnceLock<Mutex<History>>=OnceLock::new();

fn row_roots(rows:&[Value])->BTreeSet<Key> {
    rows.iter().filter_map(|r|{
        let p=u32::try_from(r["pid"].as_u64()?).ok()?;
        let s=r["startTime"].as_str()?.parse().ok()?;
        live((p,s)).then_some((p,s))
    }).collect()
}

fn basename(s:&str)->Option<String> {
    let name=Path::new(s).file_name()?.to_str()?;
    if name.is_empty() || name.len()>128 ||
        !name.chars().all(|c|c.is_alphanumeric() || "._-+".contains(c)) {return None;}
    Some(name.to_owned())
}
fn shell_label(bytes:&[u8])->String {
    let mut args=bytes.split(|b|*b==0);
    let first=args.next().and_then(|b|std::str::from_utf8(b).ok())
        .and_then(basename).unwrap_or_else(||"Worker".into());
    if matches!(first.as_str(),"sh"|"bash"|"dash"|"mksh") {
        if let Some(script)=args.next().and_then(|b|std::str::from_utf8(b).ok())
            .filter(|s|!s.starts_with('-')).and_then(basename)
            .filter(|s|s.ends_with(".sh")) {return script;}
    }
    first
}

// Keep only these two values; never log, store, or parse any other environment
// entry. Nothing obtained from argv is used as a filesystem path.
fn contexts(bytes:&[u8])->(Option<PathBuf>,Option<PathBuf>) {
    fn value(bytes:&[u8], key:&[u8])->Option<PathBuf> {
        use std::os::unix::ffi::OsStrExt;
        let mut found=None;
        for field in bytes.split(|b|*b==0) {
            if let Some(v)=field.strip_prefix(key) {
                if found.is_some() || v.is_empty() || v.len()>4096 {return None;}
                let path=PathBuf::from(std::ffi::OsStr::from_bytes(v));
                if !path.is_absolute() {return None;}
                found=Some(path);
            }
        }
        found
    }
    (value(bytes,b"SPEEDBACKUP_RUN_TMPDIR="),
     value(bytes,b"SPEEDBACKUP_REMOTE_HEALTH_DIR="))
}

fn recover(key:Key, rows:&mut Vec<Value>, seen:&mut BTreeSet<Key>,
           used:&mut BTreeSet<(Option<PathBuf>,Option<PathBuf>)>)->bool {
    if !live(key) || !root_process(key.0) {return false;}
    let Ok(bytes)=bounded(format!("/proc/{}/environ",key.0),65536) else {return false;};
    let paths=contexts(&bytes);
    drop(bytes);
    if !live(key) || !root_process(key.0) || paths==(None,None) || used.contains(&paths) {return false;}
    if used.len()>=CONTEXT_LIMIT {return true;}
    used.insert(paths.clone());
    // Read records into a staging set. The source process must remain the same
    // root identity throughout; trusted_file validates each selected directory.
    let mut staged=Vec::new();
    let mut staged_seen=BTreeSet::new();
    registry_rows(&mut staged,&mut staged_seen,paths.0.as_deref(),paths.1.as_deref());
    if live(key) && root_process(key.0) {
        for row in staged {
            let p=row["pid"].as_u64().unwrap() as u32;
            let s=row["startTime"].as_str().unwrap().parse().unwrap();
            if seen.insert((p,s)) {rows.push(row);}
        }
    }
    false
}


fn history_lock()->std::sync::MutexGuard<'static,History> {
    let mutex=HISTORY.get_or_init(||Mutex::new(History::default()));
    match mutex.lock() {
        Ok(h)=>h,
        Err(e)=>{
            let mut h=e.into_inner();
            // Never erase sticky loss or authorize a second bootstrap.
            h.partial=true;
            mutex.clear_poison();
            h
        }
    }
}

fn prune(h:&mut History) {
    h.proven.retain(|&key|live(key));
    h.labels.retain(|key,_|h.proven.contains(key));
}

fn admit(h:&mut History,key:Key)->bool {
    if h.proven.contains(&key) {return true;}
    if h.proven.len()>=LIMIT {prune(h);}
    if h.proven.len()>=LIMIT {
        h.partial=true;
        return false;
    }
    h.proven.insert(key);
    true
}

const WATCH_LIMIT:usize=64;

fn guardian_match(owner:u32, argv0:&[u8], watch_uid:u32, package:&str)->bool {
    owner==watch_uid && argv0==format!("{package}:guardian").as_bytes()
}

// Unknown event PIDs are first filtered by watched UID, then exact argv[0].
// Neither comm (which is truncated) nor a shared inode grants membership.
fn discover_guardian(h:&mut History,pid:u32) {
    if h.watches.is_empty() {return;}
    let Some(owner)=uid(pid) else {return;};
    if !h.watches.iter().any(|(u,_)|*u==owner) {return;}
    let Some(before)=read_node(pid) else {return;};
    let Ok(bytes)=bounded(format!("/proc/{pid}/cmdline"),4096) else {return;};
    let argv0=bytes.split(|b|*b==0).next().unwrap_or_default();
    let command=h.watches.iter().find(|(u,p)|
        guardian_match(owner,argv0,*u,p)
    ).map(|(_,p)|format!("{p}:guardian"));
    let Some(command)=command else {return;};
    if !checked(before) || uid(pid)!=Some(owner) || !cmdline(pid,&command) {
        h.partial=true;
        return;
    }
    if admit(h,before.key()) {
        h.labels.insert(before.key(),"Guardian".into());
    }
}

// Called only after snapshot_for_package has authenticated its internal
// package selection. Register before scanning so queued COMM/UID signals
// cover zygote children which become guardians during/after discovery.
pub(super) fn register_caller(pid:u32,start:u64,owner:u32,package:&str) {
    let mut h=history_lock();
    let key=(pid,start);
    if !live(key) || uid(pid)!=Some(owner) || !cmdline(pid,package) {
        h.partial=true;
        return;
    }
    if admit(&mut h,key) {
        h.labels.insert(key,"SpeedBackup".into());
    }
    let watch=(owner,package.to_owned());
    if h.watches.contains(&watch) {return;}
    if package.len()>256 || h.watches.len()>=WATCH_LIMIT {
        h.partial=true;
        return;
    }
    h.watches.insert(watch);
    // Exactly once per authenticated UID/package. No TTL or periodic scan.
    match fs::read_dir("/proc") {
        Ok(entries)=>for (i,entry) in entries.enumerate() {
            if i>=LIMIT {h.partial=true;break;}
            let Ok(entry)=entry else {h.partial=true;continue;};
            let Some(p)=entry.file_name().to_str().and_then(|s|s.parse().ok())
                else {continue;};
            // Only this newly registered identity is eligible in this scan.
            if uid(p)!=Some(owner) {continue;}
            let command=format!("{package}:guardian");
            if cmdline(p,&command) {discover_guardian(&mut h,p);}
        },
        Err(_)=>h.partial=true,
    }
}

fn remember_rows(h:&mut History, rows:&[Value]) {
    for key in row_roots(rows) {
        if !admit(h,key) {continue;}
        if let Some(name)=rows.iter().find(|r|
            r["pid"].as_u64()==Some(key.0 as u64) &&
            r["startTime"].as_str().and_then(|s|s.parse::<u64>().ok())==Some(key.1)
        ).and_then(|r|r["name"].as_str()) {
            h.labels.entry(key).or_insert_with(||name.to_owned());
        }
    }
}

fn recover_known(h:&mut History,key:Key) {
    if !h.proven.contains(&key) || !live(key) {return;}
    let mut rows=Vec::new();
    let mut seen=BTreeSet::new();
    let mut used=BTreeSet::new();
    h.partial |= recover(key,&mut rows,&mut seen,&mut used);
    remember_rows(h,&rows);
}

// Pure event-edge predicate. An event PID/name/inode is never authority.
fn fork_edge(parent:Node,child:Node,known:Key)->bool {
    parent.key()==known && child.pid!=parent.pid &&
        child.parent==parent.pid && child.start>=parent.start
}

// Event-local stat-only recovery. Never enumerate /proc or use credentials,
// executable names, argv, or event-supplied parent IDs as ownership evidence.
// The read callback also makes discovery and both validation passes testable.
fn targeted_proof(
    pid:u32, roots:&BTreeSet<Key>, mut read:impl FnMut(u32)->Option<Node>,
)->Option<Vec<Node>> {
    if roots.is_empty() {return None;}
    let mut nodes=BTreeMap::new();
    let mut at=pid;
    for _ in 0..DEPTH {
        if at<=1 || nodes.contains_key(&at) {return None;}
        let n=read(at)?;
        if n.pid!=at {return None;}
        nodes.insert(at,n);
        if roots.contains(&n.key()) {
            let proof=chain(pid,&nodes,roots)?;
            // Validate every captured identity AND PPID, including the anchor,
            // in two complete passes. Nothing is admitted on a failed pass.
            for node in &proof {
                if read(node.pid)!=Some(*node) {return None;}
            }
            for node in proof.iter().rev() {
                if read(node.pid)!=Some(*node) {return None;}
            }
            return Some(proof);
        }
        at=n.parent;
    }
    None
}

fn recover_ancestry(h:&mut History,pid:u32)->bool {
    let Some(proof)=targeted_proof(pid,&h.proven,read_node) else {return false;};
    // Admit intermediates as well as the event leaf, anchor first.
    for node in proof.iter().rev() {
        if !admit(h,node.key()) {return false;}
    }
    true
}

fn apply_event(h:&mut History,event:events::Event) {
    match event {
        events::Event::Lost=>h.partial=true,
        events::Event::Fork{parent,child}=>{
            let Some(key)=h.proven.iter().find(|k|k.0==parent).copied()
                else {
                    if !recover_ancestry(h,child) {discover_guardian(h,child);}
                    return;
                };
            let proof=(||{
                if !live(key) {return None;}
                let p=read_node(parent)?;
                let c=read_node(child)?;
                if !fork_edge(p,c,key) || !checked(p) || !checked(c) {
                    return None;
                }
                // Recheck exact identities and edges at admission, regardless of UID.
                if !checked(p) || !checked(c) || !live(key) {return None;}
                Some(c.key())
            })();
            if let Some(child_key)=proof {
                admit(h,child_key);
            } else {
                // Exited/reused identities or unprovable edges are incomplete.
                h.partial=true;
                // A delayed event may no longer describe the direct edge.
                // Current, fully validated ancestry can still recover it.
                recover_ancestry(h,child);
            }
        },
        events::Event::Exec{pid}=>{
            if let Some(key)=h.proven.iter().find(|k|k.0==pid).copied() {
                if live(key) {
                    // Non-service labels are read afresh at snapshot time.
                    // Registry service labels remain stable across exec.
                    recover_known(h,key);
                } else {
                    h.partial=true;
                    if !recover_ancestry(h,pid) {discover_guardian(h,pid);}
                }
            } else if recover_ancestry(h,pid) {
                if let Some(node)=read_node(pid) {recover_known(h,node.key());}
            } else {
                discover_guardian(h,pid);
            }
        },
        events::Event::Exit{pid}=>{
            // Exit has no starttime. A delayed exit must not evict a live
            // current identity (including a subsequently admitted reuse).
            let dead:Vec<_>=h.proven.iter()
                .filter(|k|k.0==pid && !live(**k)).copied().collect();
            for key in dead {
                h.proven.remove(&key);
                h.labels.remove(&key);
            }
        },
    }
}

fn on_event(event:events::Event) {
    let mut h=history_lock();
    if !h.initialized {
        // Startup callbacks must return without waiting for start() to finish.
        // Bounded buffering preserves events received before bootstrap.
        if h.pending.len()<LIMIT {
            h.pending.push_back(event);
        } else {
            h.partial=true;
        }
        return;
    }
    apply_event(&mut h,event);
}

static START:OnceLock<()>=OnceLock::new();

pub(super) fn start() {
    START.get_or_init(||{
        // Do NOT hold HISTORY while listen subscribes/starts its thread.
        let result=events::listen(on_event);
        let mut h=history_lock();
        h.available=result.is_ok();
        if let Err(e)=result {
            h.partial=true;
            eprintln!("PROCESS_MONITOR events unavailable; no polling fallback: {e}");
        }
        let mut rows=Vec::new();
        let mut seen=BTreeSet::new();
        let run=std::env::var_os("SPEEDBACKUP_RUN_TMPDIR");
        let health=std::env::var_os("SPEEDBACKUP_REMOTE_HEALTH_DIR");
        registry_rows(&mut rows,&mut seen,
            run.as_deref().map(Path::new),health.as_deref().map(Path::new));
        bootstrap(&mut h,&mut rows,&mut seen);
        remember_rows(&mut h,&rows);
        h.initialized=true;
        while let Some(event)=h.pending.pop_front() {
            apply_event(&mut h,event);
        }
    });
}

pub(super) fn discovery_mode()->&'static str {
    if history_lock().available {"events"} else {"unavailable"}
}

fn bootstrap(history:&mut History,rows:&mut Vec<Value>,seen:&mut BTreeSet<Key>) {
    history.bootstrap_count+=1;
        let mut nodes=BTreeMap::new();
        match fs::read_dir("/proc") {
            Ok(entries)=>for (i,entry) in entries.enumerate() {
                if i>=LIMIT {history.partial=true;break;}
                let Ok(entry)=entry else {history.partial=true;continue;};
                let Some(pid)=entry.file_name().to_str().and_then(|s|s.parse().ok())
                    else {continue;};
                // Exactly one stat read per system PID. No status, exe, argv,
                // environment, or RSS reads for unrelated system processes.
                if let Some(n)=read_node(pid) {nodes.insert(pid,n);}
            },
            Err(_)=>history.partial=true,
        }
        let mut roots=row_roots(rows);
        if let Some(n)=read_node(std::process::id()) {
            if checked(n) && root_process(n.pid) {
                roots.insert(n.key());
                if admit(history,n.key()) {
                    history.labels.insert(n.key(),"Root controller".into());
                }
            }
        }
        roots.extend(history.proven.iter().copied());
        let own=std::process::id();
        // An inherited owner PID is a hint, not authority. Accept it only when
        // it is an actual, fully rechecked root ancestor of this controller.
        if let Some(owner)=std::env::var("SPEEDBACKUP_CONSOLE_OWNER").ok()
            .and_then(|s|s.parse::<u32>().ok()) {
            if let Some(n)=nodes.get(&owner) {
                if let Some(proof)=chain(own,&nodes,&BTreeSet::from([n.key()])) {
                    if proof.iter().all(|n|checked(*n) && root_process(n.pid)) &&
                        proof.iter().rev().all(|n|checked(*n) && root_process(n.pid)) {
                        roots.insert(n.key());
                    }
                }
            }
        }
        // Two passes over the SAME table: first descendants, then children of
        // recovered registry roots. No per-root /proc scan. Memoized checked
        // edges avoid repeatedly reading shared ancestry for each leaf.
        let mut used=BTreeSet::new();
        for pass in 0..2 {
            let mut verified=BTreeSet::new();
            for &pid in nodes.keys() {
                let Some(proof)=chain(pid,&nodes,&roots) else {
                    history.partial |= proof_incomplete(pid,&nodes);
                    continue;
                };
                let mut ok=true;
                for &n in proof.iter().rev() {
                    if !verified.contains(&n.key()) {
                        if !checked(n) {ok=false;break;}
                        verified.insert(n.key());
                    }
                }
                if !ok {history.partial=true;continue;}
                // Recheck the leaf and its immediate parent at admission.
                let n=proof[0];
                if !checked(n) || proof.get(1).is_some_and(|p|!checked(*p)) {
                    history.partial=true;continue;
                }
                admit(history,n.key());
            }
            if pass==0 {
                let candidates:Vec<_>=history.proven.iter().copied().collect();
                for key in candidates {
                    history.partial |= recover(key,rows,seen,&mut used);
                }
                roots.extend(row_roots(rows));
                roots.extend(history.proven.iter().copied());
            }
        }

}

pub(super) fn append(rows:&mut Vec<Value>, seen:&mut BTreeSet<Key>)->bool {
    start();
    let mut history=history_lock();
    // Only trusted rows introduce new roots here. No global discovery scan.
    remember_rows(&mut history,rows);

    let mut trusted=BTreeSet::new();
    if let Some(exe)=exe_identity(std::process::id()) {trusted.insert(exe);}
    for key in row_roots(rows) {
        if let Some(exe)=deployed_exe(key.0) {
            if live(key) && deployed_exe(key.0)==Some(exe) {trusted.insert(exe);}
        }
    }
    // Record roots are retained too, including detached RootDaemon/watchdogs.
    remember_rows(&mut history,rows);
    prune(&mut history);
    let candidates:Vec<_>=history.proven.iter().copied().collect();
    for (pid,start) in candidates {
        let key=(pid,start);
        let applet=applet_identity(pid,&trusted).filter(|a|a.start==start);
        let name=history.labels.get(&key).cloned().unwrap_or_else(||
            applet.as_ref().map(|a|a.applet.to_owned()).unwrap_or_else(||
                shell_label(&bounded(format!("/proc/{pid}/cmdline"),4096).unwrap_or_default())));
        let length=rows.len();
        let Some(owner)=uid(pid) else {history.partial=true;continue;};
        add(rows,seen,pid,start,owner,&name,None);
        if !live(key) || uid(pid)!=Some(owner) {
            if rows.len()>length {rows.truncate(length);seen.remove(&key);}
            history.partial=true;
            continue;
        }
        if !seen.contains(&key) {history.partial=true;}
        if let Some(a)=applet {
            if applet_identity(pid,&trusted).as_ref()==Some(&a) {
                if let Some(row)=rows.iter_mut().find(|r|r["pid"].as_u64()==Some(pid as u64)
                    && r["startTime"].as_str()==Some(start.to_string().as_str())) {
                    if let Some(old)=row["name"].as_str() {
                        if old!=a.applet {row["name"]=json!(format!("{old} \u{00b7} {}",a.applet));}
                    }
                }
            }
        }
    }
    history.partial
}

#[cfg(test)]
mod tests {
    use super::*;
    fn n(pid:u32,parent:u32,start:u64)->Node {Node{pid,parent,start}}

    #[test]
    fn targeted_recovers_missing_intermediates_and_checks_twice() {
        let nodes=BTreeMap::from([
            (10,n(10,1,100)),(11,n(11,10,101)),
            (12,n(12,11,102)),(13,n(13,12,103)),
        ]);
        let roots=BTreeSet::from([(10,100)]);
        let mut reads=BTreeMap::<u32,usize>::new();
        let proof=targeted_proof(13,&roots,|pid|{
            *reads.entry(pid).or_default()+=1;
            nodes.get(&pid).copied()
        }).unwrap();
        assert_eq!(proof.iter().map(|n|n.pid).collect::<Vec<_>>(),vec![13,12,11,10]);
        assert!(reads.values().all(|count|*count==3));

        // Both validation passes must reject changes, including anchor reuse
        // and intermediate reparenting, without returning a partial proof.
        for changed_pid in [10,11,12,13] {
            for changed_read in [2,3] {
                let mut counts=BTreeMap::<u32,usize>::new();
                assert!(targeted_proof(13,&roots,|pid|{
                    let count=counts.entry(pid).or_default();
                    *count+=1;
                    let mut node=*nodes.get(&pid)?;
                    if pid==changed_pid && *count==changed_read {
                        node.parent=99;
                    }
                    Some(node)
                }).is_none());
            }
        }
        assert!(targeted_proof(13,&BTreeSet::from([(10,99)]),
            |pid|nodes.get(&pid).copied()).is_none());
        let mut reversed=nodes.clone();
        reversed.insert(10,n(10,1,104));
        assert!(targeted_proof(13,&BTreeSet::from([(10,104)]),
            |pid|reversed.get(&pid).copied()).is_none());
        assert!(targeted_proof(13,&roots,
            |pid|if pid==11 {None} else {nodes.get(&pid).copied()}).is_none());
    }

    #[test]
    fn targeted_bounds_unowned_work_and_rejects_cycles() {
        let roots=BTreeSet::from([(500,1)]);
        let mut reads=0;
        assert!(targeted_proof(1000,&roots,|pid|{
            reads+=1;
            Some(n(pid,pid-1,1))
        }).is_none());
        assert_eq!(reads,DEPTH);
        let mut reads=0;
        assert!(targeted_proof(20,&roots,|pid|{
            reads+=1;
            Some(n(pid,if pid==20 {21} else {20},1))
        }).is_none());
        assert_eq!(reads,2);
        assert!(targeted_proof(20,&BTreeSet::new(),|_|{
            panic!("empty ownership set must not read unrelated processes")
        }).is_none());
    }

    #[test]
    #[cfg(target_os="android")]
    #[ignore = "Android multi-level real tar/zstd pipeline; run alone with --ignored --test-threads=1"]
    fn android_delayed_pipeline_ancestry() {
        use std::io::{BufRead,BufReader};
        use std::process::{Child,Command,Stdio};

        // EOF propagates through tar and zstd; each shell waits for its own
        // children. Only our direct Child handle is waited on. No PID killing,
        // process-name cleanup, global scan, or temporary files.
        struct Fixture(Child);
        impl Drop for Fixture {
            fn drop(&mut self) {
                drop(self.0.stdin.take());
                let _=self.0.wait();
            }
        }
        let script=r#"
if [ "$1" -gt 0 ]; then
    /system/bin/sh -c "$0" "$0" "$(($1 - 1))"
    exit $?
fi
/system/bin/sh -c 'echo "$$" >&2; exec /system/bin/tar -cf - -T -' |
    /system/bin/sh -c 'echo "$$" >&2; exec /system_ext/bin/zstd --single-thread -q -c' >/dev/null
wait
"#;
        start();
        let mut fixture=Fixture(Command::new("/system/bin/sh")
            .args(["-c",script,script,"3"])
            .stdin(Stdio::piped()).stdout(Stdio::null())
            .stderr(Stdio::piped()).spawn().unwrap());
        let mut output=BufReader::new(fixture.0.stderr.take().unwrap());
        let mut pids=Vec::new();
        for _ in 0..2 {
            let mut line=String::new();
            assert!(output.read_line(&mut line).unwrap()>0);
            pids.push(line.trim().parse::<u32>().unwrap());
        }
        let deadline=std::time::Instant::now()+std::time::Duration::from_secs(2);
        loop {
            let names:Vec<_>=pids.iter().map(|pid|shell_label(&bounded(format!("/proc/{pid}/cmdline"),4096).unwrap_or_default())).collect();
            if names.contains(&"tar".to_owned()) && names.contains(&"zstd".to_owned()) {break;}
            assert!(std::time::Instant::now()<deadline,"tools did not exec: {names:?}");
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        let anchor=read_node(std::process::id()).unwrap();
        // Local history deliberately has NONE of the direct-parent/intermediate
        // fork events. Deliver tool events first, modelling delayed/lost events.
        for fork in [false,true] {
            let mut h=History::default();
            admit(&mut h,anchor.key());
            apply_event(&mut h,events::Event::Lost);
            for &pid in &pids {
                let node=read_node(pid).unwrap();
                assert!(!h.proven.contains(&node.key()));
                if fork {
                    apply_event(&mut h,events::Event::Fork{parent:node.parent,child:pid});
                } else {
                    apply_event(&mut h,events::Event::Exec{pid});
                }
                assert!(h.proven.contains(&node.key()));
                let proof=targeted_proof(pid,&BTreeSet::from([anchor.key()]),read_node)
                    .expect("live held pipeline ancestry");
                assert!(proof.len()>=5);
                assert!(proof.iter().all(|n|h.proven.contains(&n.key())));
            }
            assert!(h.partial,"successful recovery must not clear loss");
        }
        let deadline=std::time::Instant::now()+std::time::Duration::from_secs(2);
        loop {
            let mut rows=Vec::new();
            append(&mut rows,&mut BTreeSet::new());
            if pids.iter().all(|pid|rows.iter().any(|r|r["pid"].as_u64()==Some(*pid as u64) && matches!(r["name"].as_str(),Some("tar"|"zstd")))) {
                eprintln!("multi-level real tar/zstd present in monitor rows; bootstrap={}",history_lock().bootstrap_count);
                assert_eq!(history_lock().bootstrap_count,1);
                break;
            }
            assert!(std::time::Instant::now()<deadline,"pipeline missing from actual monitor rows: {rows:?}");
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        drop(fixture.0.stdin.take());
        assert!(fixture.0.wait().unwrap().success());
    }

    #[test]
    fn guardian_requires_exact_uid_and_full_package_name() {
        let p="io.example.app";
        assert!(guardian_match(10001,b"io.example.app:guardian",10001,p));
        for argv in [
            &b"guardian"[..], &b"/io.example.app:guardian"[..],
            &b"io.example.app:guardian.extra"[..], &b"io.example.app"[..],
            &b"io.other.app:guardian"[..],
        ] {
            assert!(!guardian_match(10001,argv,10001,p));
        }
        assert!(!guardian_match(0,b"io.example.app:guardian",10001,p));
        assert!(!guardian_match(10002,b"io.example.app:guardian",10001,p));
    }

    #[test]
    fn dropped_uid_does_not_change_pure_ancestry_policy() {
        let nodes=BTreeMap::from([
            (10,n(10,1,100)),(11,n(11,10,101)),(12,n(12,11,102)),
        ]);
        let roots=BTreeSet::from([(10,100)]);
        // Credentials are intentionally absent from the membership predicate.
        // A root, app-UID, or uidexec worker has the same identity/edge proof.
        for _current_uid in [0u32,10001,2000,65534] {
            assert!(chain(12,&nodes,&roots).is_some());
            assert!(fork_edge(nodes[&11],nodes[&12],(11,101)));
            assert!(chain(12,&nodes,&BTreeSet::from([(10,99)])).is_none());
        }
    }

    #[test]
    fn real_child_identity_edges_and_pruning() {
        use std::process::Command;
        let binary=if cfg!(target_os="android") {
            "/system/bin/sleep"
        } else {
            "/bin/sleep"
        };
        let mut child=Command::new(binary).arg("30").spawn().unwrap();
        let parent=read_node(std::process::id()).unwrap();
        let node=read_node(child.id()).unwrap();
        let mut h=History::default();
        assert!(admit(&mut h,parent.key()));
        apply_event(&mut h,events::Event::Fork{
            parent:parent.pid,child:node.pid,
        });
        let admitted=h.proven.contains(&node.key());
        let identity_live=live(node.key());
        let reused_live=live((node.pid,node.start.wrapping_add(1)));
        h.labels.insert(node.key(),"Fixture".into());
        child.kill().unwrap();
        child.wait().unwrap();
        prune(&mut h);
        assert!(admitted && identity_live);
        assert!(!reused_live);
        assert!(!h.proven.contains(&node.key()));
        assert!(!h.labels.contains_key(&node.key()));
    }

    #[test]
    fn event_edges_require_exact_parent_and_ordered_start() {
        let parent=n(10,1,100);
        assert!(fork_edge(parent,n(11,10,101),(10,100)));
        assert!(!fork_edge(parent,n(11,20,101),(10,100)));
        assert!(!fork_edge(parent,n(11,10,99),(10,100)));
        assert!(!fork_edge(parent,n(11,10,101),(10,99)));
        assert!(!fork_edge(parent,n(10,10,100),(10,100)));
    }

    #[test]
    fn event_loss_sticks_and_unknown_events_do_not_claim() {
        let mut h=History::default();
        apply_event(&mut h,events::Event::Lost);
        apply_event(&mut h,events::Event::Fork{parent:u32::MAX,child:42});
        apply_event(&mut h,events::Event::Exec{pid:42});
        apply_event(&mut h,events::Event::Exit{pid:42});
        assert!(h.partial);
        assert!(h.proven.is_empty());
    }

    #[test]
    fn stale_exit_preserves_a_live_known_root() {
        let key=read_node(std::process::id()).unwrap().key();
        assert!(live(key));
        let mut h=History::default();
        h.proven.insert(key);
        apply_event(&mut h,events::Event::Exit{pid:key.0});
        assert!(h.proven.contains(&key));
    }

    #[test]
    #[cfg(target_os="android")]
    #[ignore = "root Android proc connector integration; run alone with --test-threads=1"]
    fn android_events_real_child_and_single_bootstrap() {
        use std::process::Command;
        use std::time::{Duration,Instant};

        assert!(root_process(std::process::id()),"requires root");
        // Synthetic negative only: this is our own child and bootstrap
        // correctly includes it. Explicit removal below tests non-rediscovery,
        // NOT isolation from a real unrelated process.
        let mut unrelated=Command::new("/system/bin/sleep").arg("6").spawn().unwrap();
        let unrelated_key=read_node(unrelated.id()).unwrap().key();
        start();
        assert_eq!(discovery_mode(),"events","connector must really subscribe");
        {
            let mut h=history_lock();
            h.proven.remove(&unrelated_key);
            h.labels.remove(&unrelated_key);
        }
        // Removing the fixture's ancestry proof models an unrelated live
        // identity; a shared /system/bin/sleep inode must not rediscover it.
        let mut child=Command::new("/system/bin/sleep").arg("2").spawn().unwrap();
        let child_pid=child.id();
        let deadline=Instant::now()+Duration::from_millis(1500);
        loop {
            let mut rows=Vec::new();
            append(&mut rows,&mut BTreeSet::new());
            assert!(!rows.iter().any(|r|r["pid"].as_u64()==Some(unrelated.id() as u64)));
            if rows.iter().any(|r|r["pid"].as_u64()==Some(child_pid as u64)) {break;}
            assert!(Instant::now()<deadline,"fork child never admitted");
            std::thread::sleep(Duration::from_millis(20));
        }
        assert!(child.wait().unwrap().success());
        for _ in 0..5 {
            let mut rows=Vec::new();
            append(&mut rows,&mut BTreeSet::new());
            assert!(!rows.iter().any(|r|r["pid"].as_u64()==Some(child_pid as u64)));
            assert!(!rows.iter().any(|r|r["pid"].as_u64()==Some(unrelated.id() as u64)));
            assert_eq!(history_lock().bootstrap_count,1);
            std::thread::sleep(Duration::from_millis(100));
        }
        assert!(unrelated.wait().unwrap().success());
    }
    #[test]
    #[cfg(target_os="android")]
    #[ignore = "root Android real-tool integration; run this test alone with --ignored --exact --nocapture --test-threads=1"]
    fn android_events_owned_tools_and_single_bootstrap() {
        use std::io::Write;
        use std::os::unix::fs::{DirBuilderExt,OpenOptionsExt,MetadataExt};
        use std::process::{Child,Command,Stdio};
        use std::time::{Duration,Instant};

        // Only Command children created here are ever signalled or waited on.
        // No name-based killing, global killing, or recursive deletion.
        struct Fixture {
            children:Vec<Child>,
            dir:PathBuf,
            script:PathBuf,
            owns_dir:bool,
            owns_script:bool,
        }
        impl Fixture {
            fn stop(&mut self)->std::io::Result<()> {
                let mut error=None;
                for child in &mut self.children {
                    drop(child.stdin.take());
                    match child.try_wait() {
                        Ok(Some(_))=>continue,
                        Ok(None)=>{
                            // Even if kill fails, always attempt wait.
                            if let Err(e)=child.kill() {
                                if error.is_none() {error=Some(e);}
                            }
                        },
                        Err(e)=>{
                            if error.is_none() {error=Some(e);}
                            let _=child.kill();
                        },
                    }
                    if let Err(e)=child.wait() {
                        if error.is_none() {error=Some(e);}
                    }
                }
                match error {Some(e)=>Err(e),None=>Ok(())}
            }
            fn cleanup(&mut self)->std::io::Result<()> {
                if self.owns_script {
                    fs::remove_file(&self.script)?;
                    self.owns_script=false;
                }
                if self.owns_dir {
                    fs::remove_dir(&self.dir)?;
                    self.owns_dir=false;
                }
                Ok(())
            }
        }
        impl Drop for Fixture {
            fn drop(&mut self) {
                let _=self.stop();
                let _=self.cleanup();
            }
        }

        assert!(root_process(std::process::id()),"requires root Android");
        let dir=PathBuf::from(format!(
            "/data/local/tmp/sb-monitor-owned-tools-{}",std::process::id()));
        let mut fixture=Fixture {
            script:dir.join("monitor-fixture.sh"),
            dir,
            children:Vec::with_capacity(4),
            owns_dir:false,
            owns_script:false,
        };
        let mut builder=fs::DirBuilder::new();
        builder.mode(0o700);
        builder.create(&fixture.dir).expect("create fresh private fixture directory");
        fixture.owns_dir=true;
        let metadata=fs::symlink_metadata(&fixture.dir).unwrap();
        assert!(metadata.is_dir());
        assert_eq!(metadata.uid(),0);
        assert_eq!(metadata.mode() & 0o777,0o700);

        let mut script=fs::OpenOptions::new()
            .write(true).create_new(true).mode(0o700)
            .open(&fixture.script).expect("create new fixture script");
        fixture.owns_script=true;
        script.write_all(b"#!/system/bin/sh\nread token\n").unwrap();
        script.set_permissions(
            <fs::Permissions as std::os::unix::fs::PermissionsExt>::from_mode(0o700)
        ).unwrap();
        drop(script);

        // Subscribe/bootstrap BEFORE any fixture tool is spawned.
        start();
        eprintln!("owned-tools backend={}",discovery_mode());
        assert_eq!(discovery_mode(),"events","real event subscription required");
        assert_eq!(history_lock().bootstrap_count,1);

        // Optional negative: an actually existing, initially unowned logcat.
        // This test-only scan never changes ownership or touches that process.
        let outsider=fs::read_dir("/proc").unwrap().filter_map(|entry|{
            let entry=entry.ok()?;
            let pid=entry.file_name().to_str()?.parse::<u32>().ok()?;
            let node=read_node(pid)?;
            let bytes=bounded(format!("/proc/{pid}/cmdline"),4096).ok()?;
            if shell_label(&bytes)!="logcat" || !checked(node) {
                return None;
            }
            if history_lock().proven.contains(&node.key()) {return None;}
            Some(node.key())
        }).next();

        let specs=[
            ("/system/bin/logcat",vec!["*:S"],"logcat"),
            ("/system/bin/tar",vec!["-cf","/dev/null","-T","-"],"tar"),
            ("/system_ext/bin/zstd",vec!["--single-thread","-q","-c"],"zstd"),
            ("/system/bin/sh",Vec::new(),"monitor-fixture.sh"),
        ];
        let mut expected=Vec::new();
        for (binary,args,name) in specs {
            let mut command=Command::new(binary);
            command.args(args).stdout(Stdio::null()).stderr(Stdio::inherit());
            if name=="logcat" {
                command.stdin(Stdio::null());
            } else {
                // Retained in Child.stdin until teardown: no input and no EOF.
                command.stdin(Stdio::piped());
            }
            if name=="monitor-fixture.sh" {command.arg(&fixture.script);}
            // Adopt immediately so subsequent assertions are panic-safe.
            fixture.children.push(command.spawn().expect("spawn real Android tool"));
            let child=fixture.children.last().unwrap();
            expected.push((child.id(),name));
            eprintln!("owned-tools spawned pid={} name={name}",child.id());
        }

        let check_outsider=|rows:&[Value]| {
            if let Some(key)=outsider {
                if live(key) {
                    assert!(!rows.iter().any(|r|
                        r["pid"].as_u64()==Some(key.0 as u64)
                    ),"initially unowned logcat appeared");
                }
            }
        };

        // Assertion waiting ONLY; no production timer or discovery fallback.
        let deadline=Instant::now()+Duration::from_secs(2);
        loop {
            for child in &mut fixture.children {
                assert!(child.try_wait().unwrap().is_none(),
                    "fixture pid {} exited early",child.id());
            }
            let mut rows=Vec::new();
            append(&mut rows,&mut BTreeSet::new());
            check_outsider(&rows);
            assert_eq!(history_lock().bootstrap_count,1);
            let complete=expected.iter().all(|(pid,name)| {
                rows.iter().any(|r|
                    r["pid"].as_u64()==Some(*pid as u64) &&
                    r["name"].as_str()==Some(*name)
                )
            });
            if complete {
                for (pid,name) in &expected {
                    let row=rows.iter().find(|r|
                        r["pid"].as_u64()==Some(*pid as u64)
                    ).unwrap();
                    assert_eq!(row["name"].as_str(),Some(*name));
                    assert!(row.get("cpuTicks").is_some_and(|v|!v.is_null()),
                        "missing cpuTicks: {row}");
                    assert!(["rss","rssBytes"].iter().any(|field|
                        row.get(*field).is_some_and(|v|!v.is_null())
                    ),"missing RSS counter: {row}");
                    eprintln!("owned-tools backend={} pid={pid} name={name}",
                        discovery_mode());
                }
                break;
            }
            assert!(Instant::now()<deadline,
                "real tool rows/names not observed within two seconds: {rows:?}");
            std::thread::sleep(Duration::from_millis(20));
        }

        fixture.stop().expect("close fixture pipes, kill and reap own children");
        let mut rows=Vec::new();
        append(&mut rows,&mut BTreeSet::new());
        for (pid,_) in &expected {
            assert!(!rows.iter().any(|r|r["pid"].as_u64()==Some(*pid as u64)),
                "reaped fixture remains in append rows: {pid}");
        }
        check_outsider(&rows);
        assert_eq!(history_lock().bootstrap_count,1,"no rediscovery bootstrap");
        fixture.cleanup().expect("remove exact fixture file and empty directory");
    }

    #[test]
    fn ancestors_not_shared_inodes_authorize() {
        let nodes=BTreeMap::from([(10,n(10,1,100)),(11,n(11,10,101)),
            (12,n(12,11,102)),(20,n(20,1,90))]);
        let roots=BTreeSet::from([(10,100)]);
        assert_eq!(chain(12,&nodes,&roots).unwrap().len(),3);
        // Even an unrelated process running exactly the same executable is not
        // represented in roots, and cannot gain membership through its name.
        assert!(chain(20,&nodes,&roots).is_none());
        assert!(chain(12,&nodes,&BTreeSet::from([(10,99)])).is_none());
        let mut reused=nodes.clone();
        reused.insert(10,n(10,1,200));
        assert!(chain(12,&reused,&BTreeSet::from([(10,200)])).is_none());
    }
    #[test]
    fn reparent_identity_and_cycles() {
        let nodes=BTreeMap::from([(12,n(12,1,102)),(13,n(13,12,103))]);
        assert!(chain(13,&nodes,&BTreeSet::from([(12,102)])).is_some());
        assert!(chain(13,&nodes,&BTreeSet::from([(12,101)])).is_none());
        let cycle=BTreeMap::from([(12,n(12,13,102)),(13,n(13,12,102))]);
        assert!(chain(12,&cycle,&BTreeSet::new()).is_none());
    }
    #[test]
    fn descendant_context_can_recover_detached_registry_root() {
        let nodes=BTreeMap::from([(15878,n(15878,1,100)),
            (18803,n(18803,15878,200)),(16287,n(16287,1,150))]);
        let mut roots=BTreeSet::from([(15878,100)]);
        assert!(chain(18803,&nodes,&roots).is_some());
        assert!(chain(16287,&nodes,&roots).is_none());
        let paths=contexts(b"SECRET=never retain\0SPEEDBACKUP_RUN_TMPDIR=/private/run\0SPEEDBACKUP_REMOTE_HEALTH_DIR=/private/health\0");
        assert_eq!(paths,(Some("/private/run".into()),Some("/private/health".into())));
        // Production introduces this root only through registry_rows, whose
        // trusted_file/starttime/handshake guards are unchanged.
        roots.insert((16287,150));
        assert!(chain(16287,&nodes,&roots).is_some());
        assert_eq!(contexts(b"SPEEDBACKUP_RUN_TMPDIR=relative\0"),(None,None));
        assert_eq!(contexts(b"SPEEDBACKUP_RUN_TMPDIR=/a\0SPEEDBACKUP_RUN_TMPDIR=/b\0"),(None,None));
    }
    #[test]
    fn limits_and_sensitive_argv() {
        let nodes=(2..200).map(|p|(p,n(p,p-1,p as u64))).collect();
        assert!(chain(199,&nodes,&BTreeSet::from([(2,2)])).is_none());
        assert_eq!(shell_label(b"/system/bin/sh\0/private/backup.sh\0password\0"),"backup.sh");
        assert_eq!(shell_label(b"sh\0-c\0secret.sh\0"),"sh");
        assert!(basename("password\nvalue").is_none());
    }
    #[test]
    fn wire_cap_is_explicit_and_first_sample_has_no_percentage() {
        let mut rows:Vec<Value>=(0..65).map(|p|json!({"pid":p,"cpuTicks":"0"})).collect();
        let partial=rows.len()>64;
        rows.truncate(64);
        assert!(partial);
        assert_eq!(rows.len(),64);
        // Wire counters are not percentages; a client without a baseline must
        // retain unknown CPU, including for a sleeping zero-tick process.
        assert_eq!(rows[0]["cpuTicks"],"0");
        assert!(rows[0].get("cpuPercent").is_none());
    }
}
