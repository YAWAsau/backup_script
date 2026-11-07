// Write-ahead recovery evidence for v2 mutations made by the run-owned daemon.
// This module never infers ownership from a UID-wide scan.
use super::*;
use std::io::{Seek,SeekFrom};

#[derive(Clone)]
struct Context { root: PathBuf, owner: i32, owner_start: u64, daemon: i32, daemon_start: u64 }
thread_local! { static CONTEXT: RefCell<Option<Context>> = const { RefCell::new(None) }; }
thread_local! { static RECOVERY_PENDING:RefCell<Vec<(i32,u64)>> = const { RefCell::new(Vec::new()) }; }
thread_local! { static RECOVERY_PATHS:RefCell<Vec<String>> = const { RefCell::new(Vec::new()) }; }
pub(super) fn queue_release_recovery(paths:Vec<String>) { RECOVERY_PATHS.with(|p|p.borrow_mut().extend(paths)); }
pub(super) fn queue_recovery(pid:i32,start:u64) { RECOVERY_PENDING.with(|p|p.borrow_mut().push((pid,start))); }
pub(super) fn recovery_pending() -> bool { RECOVERY_PENDING.with(|p| !p.borrow().is_empty()) || RECOVERY_PATHS.with(|p| !p.borrow().is_empty()) }
pub(super) fn drain_recovery() -> io::Result<()> {
    let paths=RECOVERY_PATHS.with(|p|std::mem::take(&mut *p.borrow_mut()));
    if !paths.is_empty() { recover_selected(None,false,Some(&paths))?; }
    let pending=RECOVERY_PENDING.with(|p|std::mem::take(&mut *p.borrow_mut()));
    for pair in pending { if pair.1==0 { return Err(invalid()); } recover(Some(pair),false)?; }
    Ok(())
}
struct Watch { record:Record, events:File, check:bool }
thread_local! { static WATCHES:RefCell<Vec<Watch>> = const { RefCell::new(Vec::new()) }; }
static WATCH_DIRTY:AtomicBool=AtomicBool::new(true);
pub(super) fn dirty() { WATCH_DIRTY.store(true,Ordering::Relaxed); }
pub(super) fn released_watch(path:&str) {
    WATCHES.with(|w|w.borrow_mut().retain(|v|v.record.path!=path));
}
thread_local! { static BLOCK_REASON: RefCell<Option<String>> = const { RefCell::new(None) }; }
static BLOCKED: AtomicBool = AtomicBool::new(false);
pub(super) fn blocked() -> bool { BLOCKED.load(Ordering::Relaxed) }
pub(super) fn block(reason: &str) {
    BLOCKED.store(true,Ordering::Relaxed);
    BLOCK_REASON.with(|r| { if r.borrow().is_none() { *r.borrow_mut()=Some(reason.to_owned()); } });
    retry_block_marker();
}
fn retry_block_marker() {
    if let Some(c)=context() {
        BLOCK_REASON.with(|r| {
            if let Err(e)=taint(&c,r.borrow().as_deref().unwrap_or("blocked"),None) {
                eprintln!("CGFREEZER_TAINT_WRITE_FAILED error={e} blocked=true retry=true");
            }
        });
    }
}
pub(super) fn owner_gone() -> bool { context().is_some_and(|c| !same_process(c.owner,c.owner_start)) }
pub(super) fn watch_pollfds() -> Vec<DaemonPollFd> {
    WATCHES.with(|w| w.borrow().iter().map(|v|DaemonPollFd{fd:v.events.as_raw_fd(),events:2|8,revents:0}).collect())
}
fn read_events(f:&mut File) -> io::Result<String> {
    f.seek(SeekFrom::Start(0))?;
    let mut s=String::new(); (&mut *f).take(4096).read_to_string(&mut s)?; Ok(s)
}
// Kernel poll notifications, not a periodic /proc or Shell scan. Only paths
// which this daemon changed from unfrozen are owned and eligible for refreeze.
pub(super) fn service_watches() -> io::Result<()> {
    let Some(c)=context() else { return Ok(()); };
    if blocked() { retry_block_marker(); return Ok(()); }
    if WATCH_DIRTY.swap(false,Ordering::Relaxed) {
        let mut watches=Vec::new();
        for path in lease_paths(&c.root.join(".cgroup_leases"))? {
            let r=match read_record(&path) { Ok(r)=>r,Err(e) if e.kind()==io::ErrorKind::NotFound=>continue,Err(e)=>return Err(e) };
            if r.stopping { continue; }
            if r.daemon!=c.daemon || r.daemon_start!=c.daemon_start { return Err(invalid()); }
            if watches.iter().any(|v:&Watch|v.record.path==r.path) { continue; }
            if retire_absent(&c,&r)? { continue; }
            let opened=(|| -> io::Result<(File,bool)> {
                let path=Path::new(&r.path);let m=fs::metadata(path)?;
                if m.dev()!=r.dev || m.ino()!=r.ino { return Err(invalid()); }
                let mut events=File::open(path.parent().ok_or_else(invalid)?.join("cgroup.events"))?;
                let text=read_events(&mut events)?;
                Ok((events,parse_events_value(&text,"frozen")!='1'))
            })();
            if let Some((events,check))=watch_result(&c,&r,"open",opened)? {
                watches.push(Watch{record:r,events,check});
            }
        }
        WATCHES.with(|w| *w.borrow_mut()=watches);
    }
    WATCHES.with(|list| -> io::Result<()> {
        for watch in list.borrow_mut().iter_mut() {
            let checked=(|| -> io::Result<()> {
            let mut fd=DaemonPollFd{fd:watch.events.as_raw_fd(),events:2|8,revents:0};
            let ready=unsafe{poll(&mut fd,1,0)};
            if ready<0 { return Err(io::Error::last_os_error()); }
            if !watch.check && ready==0 { return Ok(()); }
            if retire_absent(&c,&watch.record)? { return Ok(()); }
            watch.check=false;
            let text=read_events(&mut watch.events)?;
            if parse_events_value(&text,"frozen")=='1' { return Ok(()); }
            // An empty cgroup can report frozen=0 while its freeze request is
            // still 1. No task can run there; a later entrant inherits the hold.
            if read_file_c(&watch.record.path,64).as_deref().map(normalize_freeze)==Some('1') {
                if parse_events_value(&text,"populated")=='0'
                    || wait_frozen(Path::new(&watch.record.path),'1',1000).0 { return Ok(()); }
            }
            // Retain only the already-read event in memory until the freeze attempt.
            let observation=format!("pollRevents={}\nobservedEventsHex={}\n",fd.revents,hex(&text));
            let r=&watch.record;
            let m=fs::metadata(&r.path)?;
            if m.dev()!=r.dev || m.ino()!=r.ino || !same_process(r.pid,r.start)
                || parse_status_uid_c(r.pid)!=r.uid || read_cmdline_c(r.pid,512).as_deref()!=Some(r.process.as_str())
                || cg_v2_dir_for_pid(r.pid).map(|p|p.join("cgroup.freeze"))!=Some(PathBuf::from(&r.path)) { return Err(invalid()); }
            let pkg=r.process.split(':').next().ok_or_else(invalid)?;
            let identity=snapshot_package_target(r.pid,pkg,r.uid/100000).ok_or_else(invalid)?;
            queue_warning(r,Some(&observation));
            EXPECTED_FREEZE.with(|slot|*slot.borrow_mut()=Some(identity));
            let rc=cmd_freeze_pid_v2(r.pid,1000);
            EXPECTED_FREEZE.with(|slot|*slot.borrow_mut()=None);
            if rc!=0 { return Err(invalid()); }
            // Clear the notification generated by our own write after verifying it.
            let text=read_events(&mut watch.events)?;
            if parse_events_value(&text,"frozen")!='1' { return Err(invalid()); }
            Ok(())
            })();
            watch_result(&c,&watch.record,"service",checked)?;
        }
        Ok(())
    })
}

// A process/cgroup may disappear after the initial liveness check but before
// metadata, event reads or refreeze. Reconcile again at the failure boundary.
// Only a missing original path AND a gone/reused PID may retire the lease;
// permission, identity and live-target failures still stop the run.
fn watch_result<T>(c:&Context,r:&Record,stage:&str,result:io::Result<T>)->io::Result<Option<T>> {
    match result {
        Ok(value)=>Ok(Some(value)),
        Err(error)=>{
            if error.kind()==io::ErrorKind::Interrupted { dirty();return Ok(None); }
            let mut reconcile_error=None;
            for attempt in 0..3 {
                match retire_absent(c,r) {
                    Ok(true)=>return Ok(None),
                    Ok(false)=>{},
                    Err(e)=>{reconcile_error=Some(e);break;}
                }
                // kernfs deactivation can precede unlink. Only an exited target
                // gets this bounded (at most 20ms) failure-path grace period.
                if attempt==2 || (same_process(r.pid,r.start)
                    && !matches!(proc_state_char_rs(r.pid),'Z'|'X'|'x')) { break; }
                std::thread::sleep(Duration::from_millis(10));
            }
            let mut observation=format!("watchStage={}\nwatchErrorKind={:?}\nwatchErrno={}\nwatchErrorHex={}\n",stage,error.kind(),error.raw_os_error().unwrap_or(0),hex(&error.to_string()));
            if let Some(e)=&reconcile_error {
                observation.push_str(&format!("reconcileErrorKind={:?}\nreconcileErrno={}\nreconcileErrorHex={}\n",e.kind(),e.raw_os_error().unwrap_or(0),hex(&e.to_string())));
            }
            if let Err(e)=evidence_observed(c,"watch_failed",Some(r),Some(&observation),false,None) {
                eprintln!("CGFREEZER_WATCH_EVIDENCE_FAILED error={e}");
            }
            Err(reconcile_error.unwrap_or(error))
        }
    }
}

fn invalid() -> io::Error { io::Error::new(io::ErrorKind::InvalidData, "invalid_freezer_lease") }
pub(super) fn enabled() -> bool { context().is_some() }
fn context() -> Option<Context> { CONTEXT.with(|c| c.borrow().clone()) }
fn private_dir(p: &Path) -> io::Result<()> {
    let m = fs::symlink_metadata(p)?;
    if !m.is_dir() || m.uid() != 0 || m.mode() & 0o077 != 0 || fs::canonicalize(p)? != p { return Err(invalid()); }
    Ok(())
}
fn sync_dir(p: &Path) -> io::Result<()> { File::open(p)?.sync_all() }
fn lease_paths(dir:&Path) -> io::Result<Vec<PathBuf>> {
    fs::read_dir(dir)?.filter_map(|e| match e {
        Ok(e) if e.file_name().to_string_lossy().ends_with(".lease")=>Some(Ok(e.path())),
        Ok(_)=>None,Err(e)=>Some(Err(e))
    }).collect()
}
fn journal_lock(dir:&Path) -> io::Result<File> {
    let f=fs::OpenOptions::new().read(true).write(true).create(true).mode(0o600)
        .custom_flags(O_NOFOLLOW_NATIVE).open(dir.join(".lock"))?;
    let m=f.metadata()?;
    if !m.is_file() || m.uid()!=0 || m.mode()&0o077!=0 || m.nlink()!=1 { return Err(invalid()); }
    if unsafe{flock(f.as_raw_fd(),2)}!=0 { return Err(io::Error::last_os_error()); }
    Ok(f)
}
fn hex(s: &str) -> String { s.as_bytes().iter().map(|b| format!("{b:02x}")).collect() }
fn unhex(s: &str) -> io::Result<String> {
    if s.len() % 2 != 0 || s.len() > 8192 || !s.bytes().all(|b| b.is_ascii_hexdigit()) { return Err(invalid()); }
    let bytes: Result<Vec<u8>, _> = (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i+2],16)).collect();
    String::from_utf8(bytes.map_err(|_| invalid())?).map_err(|_| invalid())
}
#[derive(Clone)]
struct Record { pid: i32, uid: i32, start: u64, dev: u64, ino: u64, owner: i32, owner_start: u64,
    daemon: i32, daemon_start: u64, worker: i32, worker_start: u64, path: String, process: String, stopping:bool }
impl Record {
    fn text(&self) -> String { format!("2\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
        self.pid,self.uid,self.start,self.dev,self.ino,self.owner,self.owner_start,self.daemon,self.daemon_start,
        self.worker,self.worker_start,hex(&self.path),hex(&self.process),u8::from(self.stopping)) }
    fn parse(s: &str) -> io::Result<Self> {
        let a: Vec<_> = s.trim_end_matches('\n').split('\t').collect();
        if !((a.len()==14 && a[0]=="1") || (a.len()==15 && a[0]=="2" && matches!(a[14],"0"|"1"))) { return Err(invalid()); }
        let n = |i:usize| a[i].parse::<u64>().map_err(|_| invalid());
        let pid = |i:usize| -> io::Result<i32> { i32::try_from(n(i)?).ok().filter(|v| *v>1).ok_or_else(invalid) };
        let r = Self {pid:pid(1)?,uid:pid(2)?,start:n(3)?,dev:n(4)?,ino:n(5)?,owner:pid(6)?,owner_start:n(7)?,
            daemon:pid(8)?,daemon_start:n(9)?,worker:pid(10)?,worker_start:n(11)?,path:unhex(a[12])?,process:unhex(a[13])?,stopping:a.len()==15 && a[14]=="1"};
        if r.start==0 || r.owner_start==0 || r.daemon_start==0 || r.worker_start==0 || r.uid%100000<10000
            || !r.path.ends_with("/cgroup.freeze") || r.process.is_empty() { return Err(invalid()); }
        Ok(r)
    }
    fn key(&self) -> String { format!("{}-{}-{}-{}.lease",self.pid,self.start,self.dev,self.ino) }
}
fn read_record(p: &Path) -> io::Result<Record> {
    let f = fs::OpenOptions::new().read(true).custom_flags(O_NOFOLLOW_NATIVE).open(p)?;
    let m=f.metadata()?;
    if !m.is_file() || m.uid()!=0 || m.mode()&0o077!=0 || m.nlink()!=1 || m.len()>16384 { return Err(invalid()); }
    let mut s=String::new(); f.take(16385).read_to_string(&mut s)?;
    let r=Record::parse(&s)?;
    if p.file_name().and_then(|x|x.to_str())!=Some(r.key().as_str()) { return Err(invalid()); }
    Ok(r)
}
fn same_process(pid:i32,start:u64) -> bool { read_proc_start_time(pid)==Some(start) }
fn retire_absent(c:&Context,r:&Record) -> io::Result<bool> {
    match fs::symlink_metadata(&r.path) {
        Ok(_)=>return Ok(false),
        Err(e) if e.kind()==io::ErrorKind::NotFound=>{},
        Err(e)=>return Err(e)
    }
    let gone=match read_proc_start_time(r.pid) {
        Some(start)=>start!=r.start || matches!(proc_state_char_rs(r.pid),'Z'|'X'|'x'),
        None=>!Path::new(&format!("/proc/{}",r.pid)).exists()
    };
    if !gone { return Ok(false); }
    let dir=c.root.join(".cgroup_leases");let _lock=journal_lock(&dir)?;
    match fs::remove_file(dir.join(r.key())) {
        Ok(())=>sync_dir(&dir)?,
        Err(e) if e.kind()==io::ErrorKind::NotFound=>{},
        Err(e)=>return Err(e)
    }
    dirty();Ok(true)
}

pub(super) fn configure(socket: &str) -> io::Result<()> {
    let Ok(raw)=std::env::var("SPEEDBACKUP_FREEZER_OWNER_PID") else { return Ok(()); };
    let owner=raw.parse::<i32>().map_err(|_|invalid())?;
    let owner_start=read_proc_start_time(owner).ok_or_else(invalid)?;
    let root=Path::new(socket).parent().ok_or_else(invalid)?.to_path_buf(); private_dir(&root)?;
    let dir=root.join(".cgroup_leases");
    if !dir.exists() {
        use std::os::unix::fs::DirBuilderExt;
        fs::DirBuilder::new().mode(0o700).create(&dir)?; sync_dir(&root)?;
    }
    private_dir(&dir)?;
    let daemon=std::process::id() as i32;
    CONTEXT.with(|c| *c.borrow_mut()=Some(Context{root,owner,owner_start,daemon,
        daemon_start:read_proc_start_time(daemon).unwrap_or(0)}));
    recover(None, true)
}

pub(super) fn prepare(pid:i32,uid:i32,path:&Path) -> io::Result<()> {
    let Some(c)=context() else { return Ok(()); };
    if blocked() { return Err(invalid()); }
    if !same_process(c.owner,c.owner_start) { return Err(invalid()); }
    let m=fs::metadata(path)?;
    let worker=std::process::id() as i32;
    let r=Record{pid,uid,start:read_proc_start_time(pid).ok_or_else(invalid)?,dev:m.dev(),ino:m.ino(),
        owner:c.owner,owner_start:c.owner_start,daemon:c.daemon,daemon_start:c.daemon_start,
        worker,worker_start:read_proc_start_time(worker).ok_or_else(invalid)?,
        path:path.to_str().ok_or_else(invalid)?.to_owned(),process:read_cmdline_c(pid,512).ok_or_else(invalid)?,stopping:false};
    let dir=c.root.join(".cgroup_leases"); private_dir(&dir)?;
    let _lock=journal_lock(&dir)?;
    let file=dir.join(r.key());
    match read_record(&file) {
        Ok(old)=>{
            if old.stopping { return Err(invalid()); }
            // A verified owned group was thawed externally. This is a warning,
            // but changed identity/ownership remains a hard integrity failure.
            if old.pid!=r.pid || old.uid!=r.uid || old.start!=r.start || old.path!=r.path
                || old.dev!=r.dev || old.ino!=r.ino || old.process!=r.process
                || old.owner!=c.owner || old.owner_start!=c.owner_start || old.daemon!=c.daemon
                || old.daemon_start!=c.daemon_start {
                taint(&c,"lease_identity_changed",Some(&old))?;return Err(invalid());
            }
            queue_warning(&old,Some("detectionSource=prepare\n"));
            if old.worker==r.worker && old.worker_start==r.worker_start { return Ok(()); }
        }
        Err(e) if e.kind()==io::ErrorKind::NotFound=>{},
        Err(e)=>return Err(e)
    }
    persist_record(&dir,&r)
}

fn persist_record(dir:&Path,r:&Record) -> io::Result<()> {
    let text=r.text();Record::parse(&text)?;
    let file=dir.join(r.key());
    let tmp=dir.join(format!(".pending-{}-{}-{}",r.worker,r.worker_start,r.key()));
    // Pending names deliberately do not end in .lease; only complete atomic
    // records are visible to recovery. The lock serializes same-scope adoption.
    let tmp=tmp.with_extension("tmp");
    let mut f=fs::OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(O_NOFOLLOW_NATIVE).open(&tmp)?;
    f.write_all(text.as_bytes())?;f.sync_all()?;
    fs::rename(&tmp,&file)?;sync_dir(&dir)
}

// A live PID has one exact identity key. Avoid rescanning every other lease
// for each member of a multi-process app. A vanished PID still needs the
// bounded journal scan because its original start time is no longer readable.
fn release_candidates(dir:&Path,pid:i32,start:Option<u64>,control:&fs::Metadata) -> io::Result<Vec<PathBuf>> {
    if let Some(start)=start {
        let path=dir.join(format!("{}-{}-{}-{}.lease",pid,start,control.dev(),control.ino()));
        match fs::symlink_metadata(&path) {
            Ok(_)=>Ok(vec![path]),
            Err(e) if e.kind()==io::ErrorKind::NotFound=>Ok(Vec::new()),
            Err(e)=>Err(e)
        }
    } else { lease_paths(dir) }
}

// Called after a thaw attempt while the mutating worker still excludes the
// parent watcher. On crash, failed-worker recovery runs before any watch reload.
// Other PID records must remain as Binder evidence but stop watching the whole
// shared group as soon as intentional release begins.
fn finish_release(pid:i32,path:&str,remove_own:bool,disarm_group:bool) -> io::Result<()> {
    let Some(c)=context() else { return Ok(()); };
    let dir=c.root.join(".cgroup_leases");let _lock=journal_lock(&dir)?;
    let control=match fs::metadata(path) {
        Ok(m)=>m,
        Err(e) if e.kind()==io::ErrorKind::NotFound=>return Ok(()),
        Err(e)=>return Err(e)
    };let current_start=read_proc_start_time(pid);
    let candidates=if disarm_group {
        let suffix=format!("-{}-{}.lease",control.dev(),control.ino());
        lease_paths(&dir)?.into_iter().filter(|p|p.file_name().is_some_and(|n|n.to_string_lossy().ends_with(&suffix))).collect()
    } else { release_candidates(&dir,pid,current_start,&control)? };
    let mut remove=None;
    for file in candidates {
        let mut r=read_record(&file)?;
        if r.path!=path || r.dev!=control.dev() || r.ino!=control.ino() { continue; }
        let own=r.pid==pid && current_start.map(|s|s==r.start).unwrap_or(true);
        if own && remove_own { remove=Some(file);continue; }
        if disarm_group && !r.stopping {
            r.stopping=true;r.worker=std::process::id() as i32;
            r.worker_start=read_proc_start_time(r.worker).ok_or_else(invalid)?;
            persist_record(&dir,&r)?;
        }
    }
    // Commit every remaining Binder record's disarm before dropping ours.
    if let Some(file)=remove { fs::remove_file(file)?;sync_dir(&dir)?; }
    Ok(())
}
pub(super) fn begin_release(pid:i32,path:&str) -> io::Result<()> { finish_release(pid,path,false,true) }
pub(super) fn complete_release(pid:i32,path:&str) -> io::Result<()> { finish_release(pid,path,true,true) }
pub(super) fn released(pid:i32,path:&str) -> io::Result<()> { finish_release(pid,path,true,false) }

fn taint(c:&Context,reason:&str,record:Option<&Record>) -> io::Result<()> {
    taint_observed(c,reason,record,None)
}
fn taint_observed(c:&Context,reason:&str,record:Option<&Record>,observation:Option<&str>) -> io::Result<()> {
    evidence_observed(c,reason,record,observation,false,None)
}
struct PendingWarning { record:Record, observation:String, detected:u128, started:Instant }
thread_local! { static PENDING_WARNING:RefCell<Option<PendingWarning>> = const { RefCell::new(None) }; }
fn queue_warning(record:&Record,observation:Option<&str>) {
    PENDING_WARNING.with(|pending| {
        let mut pending=pending.borrow_mut();
        // Watch detection may be followed by prepare() for the same freeze call.
        // Preserve the first event; no file creation, proc snapshot or sync here.
        if pending.is_none() {
            *pending=Some(PendingWarning {record:record.clone(),observation:observation.unwrap_or("").to_owned(),
                detected:std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d|d.as_millis()).unwrap_or(0),started:Instant::now()});
        }
    });
}
pub(super) fn finish_warning(freeze_rc:i32)->io::Result<()> {
    let pending=PENDING_WARNING.with(|p|p.borrow_mut().take());
    if let Some(p)=pending {
        let c=context().ok_or_else(invalid)?;
        let observation=format!("{}snapshotPhase=after_refreeze_attempt\nrefreezeBeforeDiagnostic=true\nrefreezeResultRc={}\nrefreezeElapsedUs={}\n",p.observation,freeze_rc,p.started.elapsed().as_micros());
        evidence_observed(&c,"unexpected_thaw",Some(&p.record),Some(&observation),true,Some(p.detected))?;
    }
    Ok(())
}
fn evidence_observed(c:&Context,reason:&str,record:Option<&Record>,observation:Option<&str>,warning:bool,detected:Option<u128>) -> io::Result<()> {
    let unix_ms=detected.unwrap_or_else(||std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d|d.as_millis()).unwrap_or(0));
    let observed_uptime=read_file_c("/proc/uptime",128).unwrap_or_default();
    let p=c.root.join(if warning {".cgroup_freezer_warning"} else {".cgroup_freezer_tainted"});
    // First writer wins. Never overwrite the original trigger during cleanup.
    // Warning and fatal evidence are separate: a later hard failure must still
    // deny publication even if the first warning already exists.
    let mut f=match fs::OpenOptions::new().write(true).create_new(true).mode(0o600)
        .custom_flags(O_NOFOLLOW_NATIVE).open(&p) {
        Ok(f)=>f,
        Err(e) if e.kind()==io::ErrorKind::AlreadyExists=>{
            let m=fs::symlink_metadata(&p)?;
            if !m.is_file() || m.uid()!=0 || m.mode()&0o077!=0 || m.nlink()!=1 { return Err(invalid()); }
            return Ok(());
        }
        Err(e)=>return Err(e)
    };
    writeln!(f,"{}\nreason={reason}\nowner={}\ndaemon={}\nwriter={}",
        if warning {"native_freezer_warning"} else {"native_freezer_recovery"},c.owner,c.daemon,std::process::id())?;
    if let Some(r)=record {
        writeln!(f,"targetPid={}\ntargetStart={}\nuid={}\nprocessHex={}\ncontrolPathHex={}\nworker={}\nworkerStart={}",
            r.pid,r.start,r.uid,hex(&r.process),hex(&r.path),r.worker,r.worker_start)?;
    }
    // Preserve the pre-v989 durable minimal marker contract. Optional diagnostics
    // must not introduce new errors that can bypass the existing refreeze path.
    f.sync_all()?; sync_dir(&c.root)?;
    let mut diagnostic=format!("diagnosticVersion=2\ndetectedUnixMs={unix_ms}\nuptimeHex={}\n",hex(&observed_uptime));
    if let Some(observation)=observation { diagnostic.push_str(observation); }
    if let Some(r)=record {
        // Bounded snapshots, not attribution of which process wrote the control.
        let control=read_file_c(&r.path,64).unwrap_or_default();
        let events=read_file_c(&events_path_for_freeze(Path::new(&r.path)).to_string_lossy(),4096).unwrap_or_default();
        let current_path=cg_v2_dir_for_pid(r.pid).map(|p|p.join("cgroup.freeze").to_string_lossy().into_owned()).unwrap_or_default();
        let same_inode=fs::metadata(&r.path).map(|m|m.dev()==r.dev&&m.ino()==r.ino).unwrap_or(false);
        let status=read_file_c(&format!("/proc/{}/status",r.pid),4096).unwrap_or_default();
        let state=status.lines().find(|l|l.starts_with("State:")).unwrap_or("");
        diagnostic.push_str(&format!("snapshotControl={}\nsnapshotEventsHex={}\nsameProcess={}\nsameControlInode={}\ncurrentControlPathHex={}\ncurrentUid={}\nprocStateHex={}\n",
            normalize_freeze(&control),hex(&events),same_process(r.pid,r.start),same_inode,hex(&current_path),parse_status_uid_c(r.pid),hex(state)));
    }
    diagnostic.push_str("diagnosticComplete=1\n");
    append_diagnostic(&mut f,&diagnostic);
    Ok(())
}

// The durable failure marker already exists. ENOSPC/EIO on optional detail
// only reduces evidence; the caller must still attempt its normal refreeze.
fn append_diagnostic(f:&mut File,text:&str) {
    if let Err(e)=f.write_all(text.as_bytes()).and_then(|_|f.sync_all()) {
        eprintln!("CGFREEZER_DIAGNOSTIC_WRITE_FAILED error={e} evidenceRetained=true recoveryContinues=true");
    }
}

// Called only after the selected failed worker has been reaped, or while the
// lifetime daemon lock excludes the previous daemon during startup.
pub(super) fn recover(worker:Option<(i32,u64)>,startup:bool) -> io::Result<()> {
    recover_selected(worker,startup,None)
}
fn recover_selected(worker:Option<(i32,u64)>,startup:bool,paths:Option<&[String]>) -> io::Result<()> {
    let Some(c)=context() else { return Ok(()); };
    let dir=c.root.join(".cgroup_leases"); private_dir(&dir)?;
    // Freeze the recovery set before complete_release can rewrite sibling
    // records. A shared group must restore every owned Binder endpoint.
    let mut records=Vec::new();
    for p in lease_paths(&dir)? {
        match read_record(&p) {
            Ok(r)=>records.push((p,r)),
            Err(e) if e.kind()==io::ErrorKind::NotFound=>{},
            Err(e)=>return Err(e)
        }
    }
    let selected:Vec<_>=records.iter().filter(|(_,r)|paths.is_none_or(|p|p.contains(&r.path)) && worker.is_none_or(|(pid,start)|
        r.worker==pid && r.worker_start==start && r.daemon==c.daemon && r.daemon_start==c.daemon_start))
        .map(|(_,r)|(r.path.clone(),r.dev,r.ino)).collect();
    for (p,r) in records {
        if !selected.iter().any(|(path,dev,ino)|*path==r.path && *dev==r.dev && *ino==r.ino) { continue; }
        if startup && same_process(r.daemon,r.daemon_start) { return Err(invalid()); }
        let own_parent_recovery=!startup && worker.is_none()
            && r.worker==c.daemon && r.worker_start==c.daemon_start;
        if same_process(r.worker,r.worker_start) && !own_parent_recovery { return Err(invalid()); }
        // Invalidate output before recovery can allow the source to run.
        taint(&c,if startup {"startup_recovery"} else {"worker_recovery"},Some(&r))?;
        let path=Path::new(&r.path);
        let exists=same_process(r.pid,r.start);
        if exists && (parse_status_uid_c(r.pid)!=r.uid
            || read_cmdline_c(r.pid,512).as_deref()!=Some(r.process.as_str())) { return Err(invalid()); }
        let m=match fs::metadata(path) {
            Ok(m)=>m,
            Err(e) if e.kind()==io::ErrorKind::NotFound=>{
                if exists {
                    let b=binder_freeze_set(r.pid,false,0);
                    if b.supported && !b.ok && !matches!(b.err,EINVAL|2|3) { return Err(invalid()); }
                }
                fs::remove_file(&p)?;sync_dir(&dir)?;continue;
            },
            Err(e)=>return Err(e)
        };
        if m.dev()!=r.dev || m.ino()!=r.ino || !valid_thaw_control(&r.path,true) { return Err(invalid()); }
        let group=path.parent().ok_or_else(invalid)?;
        let members=fs::read_to_string(group.join("cgroup.procs"))?;
        let pkg=r.process.split(':').next().ok_or_else(invalid)?;
        for member in members.split_whitespace() {
            let pid=member.parse::<i32>().map_err(|_|invalid())?;
            if parse_status_uid_c(pid)!=r.uid || !is_package_process_name(&read_cmdline_c(pid,512).unwrap_or_default(),pkg) { return Err(invalid()); }
        }
        if fs::read_dir(group)?.any(|e|e.and_then(|x|x.file_type()).map(|t|t.is_dir()).unwrap_or(true)) { return Err(invalid()); }
        if cmd_thaw_path_internal(r.pid,&r.path,'0',1500,exists)!=0 { return Err(invalid()); }
        // The normal thaw path also removes this record when the PID survives.
        if p.exists() { fs::remove_file(p)?; sync_dir(&dir)?; }
    }
    Ok(())
}
