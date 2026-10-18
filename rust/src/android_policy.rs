// SPDX-License-Identifier: GPL-3.0-only
// Rust adaptation of XayahSuSuSu/Android-DataBackup owner.cpp and selinux.cpp,
// commit fa0a0f74a1fcafa29018afa88a293880599cbce7. Modified 2026-10-12.
// Stable paths and a stopped app are required, as in the upstream contract.
use std::ffi::CString;
use std::collections::HashSet;
use std::fs;
use std::io;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::Instant;
#[path = "owner_policy.rs"]
mod owner_policy;

#[link(name = "dl")]
extern "C" {
    fn dlopen(name: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
}
extern "C" { fn __system_property_get(name: *const c_char, value: *mut c_char) -> c_int; }
extern "C" { fn lchown(path: *const c_char, uid: u32, gid: u32) -> c_int; }
type Restore = unsafe extern "C" fn(*const c_char, u32) -> c_int;
type RestorePkg = unsafe extern "C" fn(*const c_char, *const c_char, u32, u32) -> c_int;
fn device_api() -> i32 {
    let mut buf = [0u8; 92];
    let n = unsafe { __system_property_get(b"ro.build.version.sdk\0".as_ptr().cast(),buf.as_mut_ptr().cast()) };
    if n <= 0 || n as usize >= buf.len() { return -1; }
    std::str::from_utf8(&buf[..n as usize]).ok().and_then(|s|s.parse().ok()).unwrap_or(-1)
}

fn cpath(p: &Path) -> io::Result<CString> {
    CString::new(p.as_os_str().as_bytes()).map_err(|_| io::ErrorKind::InvalidInput.into())
}
fn root_path(text: &str) -> io::Result<PathBuf> {
    if text.is_empty() || text.as_bytes().contains(&0) { return Err(io::ErrorKind::InvalidInput.into()); }
    let text = text.trim_end_matches('/');
    let p = PathBuf::from(if text.is_empty() { "/" } else { text });
    if !fs::symlink_metadata(&p)?.file_type().is_dir() { return Err(io::ErrorKind::NotADirectory.into()); }
    Ok(p)
}
fn uid(text: &str) -> io::Result<u32> {
    text.parse::<u32>().ok().filter(|v| *v <= i32::MAX as u32)
        .ok_or_else(|| io::ErrorKind::InvalidInput.into())
}
#[derive(Default)]
pub(super) struct OwnerStats { pub(super) visited: u64, changed: u64, preserved: u64, xdev: u64, pub(super) partitions: Vec<Partition>, pub(super) plan_capped: bool, pub(super) external_heavy: HashSet<PathBuf> }
pub(super) struct Partition { pub(super) path: PathBuf, pub(super) count: u64, pub(super) leaves: usize, pub(super) children: Vec<usize> }
fn owners(root: &Path, target: u32, previous: u32, api: i32, collect_partitions: bool) -> io::Result<OwnerStats> {
    let dev = fs::symlink_metadata(root)?.dev();
    let root_gid = owner_policy::mapped(target,previous,previous,previous,true,false,api).1;
    let mut out = OwnerStats::default();
    enum Task { Visit(PathBuf, usize, bool, Option<usize>), Leave(u64, u64, Option<usize>, Option<usize>) }
    let mut ancestors = HashSet::new();
    let mut pending = vec![Task::Visit(root.to_path_buf(), 0usize, false, None)];
    let mut collect = collect_partitions;
    while let Some(task) = pending.pop() {
        let (p, depth, cache, parent) = match task {
            Task::Visit(p,d,c,parent) => (p,d,c,parent),
            Task::Leave(d,i,node,parent) => {
                ancestors.remove(&(d,i));
                if collect { if let (Some(node),Some(parent)) = (node,parent) {
                    out.partitions[parent].count += out.partitions[node].count;
                } }
                continue;
            }
        };
        let m = fs::symlink_metadata(&p)?;
        if m.dev() != dev { out.xdev += 1; continue; }
        let cache = cache || (depth == 1 && m.file_type().is_dir()
            && matches!(p.file_name().and_then(|n|n.to_str()),Some("cache" | "code_cache")));
        if m.file_type().is_dir() && !ancestors.insert((m.dev(), m.ino())) {
            return Err(io::Error::from_raw_os_error(40)); // ELOOP, matching FTS_DC.
        }
        out.visited += 1;
        let gid = owner_policy::mapped(target,previous,m.uid(),m.gid(),depth==0,cache,api).1;
        if depth == 0 {
            // Commit root ownership last: a failed walk must retain the source UID.
        } else if m.uid() == previous || m.uid() == target {
            if m.uid() != target || m.gid() != gid {
                if unsafe { lchown(cpath(&p)?.as_ptr(), target, gid) } != 0 { return Err(io::Error::last_os_error()); }
                out.changed += 1;
            }
        } else { out.preserved += 1; }
        let mut node = None;
        if collect {
            if m.file_type().is_dir() {
                if out.partitions.len() >= 4096 { collect = false; out.partitions.clear(); out.plan_capped = true; }
                else {
                    let id = out.partitions.len();
                    out.partitions.push(Partition { path: p.clone(), count: 1, leaves: 0, children: Vec::new() });
                    if let Some(parent) = parent { out.partitions[parent].children.push(id); }
                    node = Some(id);
                }
            } else if let Some(parent) = parent {
                out.partitions[parent].count += 1;
                out.partitions[parent].leaves += 1;
            }
        }
        if m.file_type().is_dir() {
            pending.push(Task::Leave(m.dev(),m.ino(),node,parent));
            for item in fs::read_dir(&p)? {
                let e = item?;
                pending.push(Task::Visit(e.path(), depth + 1, cache, node));
            }
        }
    }
    let m = fs::symlink_metadata(root)?;
    if m.uid() == previous || m.uid() == target {
        if m.uid() != target || m.gid() != root_gid {
            if unsafe { lchown(cpath(root)?.as_ptr(), target, root_gid) } != 0 { return Err(io::Error::last_os_error()); }
            out.changed += 1;
        }
    } else { out.preserved += 1; }
    Ok(out)
}

// Keep dlopen handles alive for the process lifetime, just like upstream.
// A standalone native executable can open the system library directly; it has
// no AndroidRuntime-held ELF requiring the upstream JNI/xDL namespace lookup.
fn symbol(name: &[u8]) -> io::Result<*mut c_void> {
    // Handles stay loaded for process lifetime; cache only successful lookups.
    static RESTORE: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
    static PACKAGE: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
    let cache = match name {
        b"selinux_android_restorecon\0" => Some(&RESTORE),
        b"selinux_android_restorecon_pkgdir\0" => Some(&PACKAGE),
        _ => None,
    };
    if let Some(value) = cache.and_then(|c| c.get()) { return Ok(*value as *mut c_void); }
    for lib in [b"libselinux.so\0".as_slice(), b"/system/lib64/libselinux.so\0".as_slice()] {
        let handle = unsafe { dlopen(lib.as_ptr().cast(), 2) };
        if !handle.is_null() {
            let found = unsafe { dlsym(handle, name.as_ptr().cast()) };
            if !found.is_null() { if let Some(c) = cache { let _ = c.set(found as usize); } return Ok(found); }
        }
    }
    Err(io::Error::new(io::ErrorKind::Unsupported, "system libselinux symbol unavailable; no legacy fallback"))
}
fn relabel(root: &Path, seinfo: Option<&str>, target: u32, flags: u32) -> io::Result<()> {
    let path = cpath(root)?;
    let rc = if let Some(info) = seinfo {
        if info.is_empty() { return Err(io::ErrorKind::InvalidInput.into()); }
        let info = CString::new(info).map_err(|_| io::ErrorKind::InvalidInput)?;
        let f: RestorePkg = unsafe { std::mem::transmute(symbol(b"selinux_android_restorecon_pkgdir\0")?) };
        unsafe { f(path.as_ptr(), info.as_ptr(), target, flags) }
    } else {
        let f: Restore = unsafe { std::mem::transmute(symbol(b"selinux_android_restorecon\0")?) };
        unsafe { f(path.as_ptr(), flags) }
    };
    if rc != 0 {
        let error = io::Error::last_os_error();
        return Err(if error.raw_os_error() == Some(0) {
            io::Error::other("SELinux relabel failed; system library did not retain errno")
        } else { error });
    }
    Ok(())
}
// Separate processes isolate libselinux's global state. Only app-permissions uses
// this path, after its ownership walk has validated a stable, stopped app tree.
// Small/flat trees stay serial. Directory accounting is capped at 4096 nodes;
// plans at 1024 partitions and 2048 direct leaves, then grouped into <=8 workers.
fn relabel_app(root: &Path, seinfo: Option<&str>, target: u32, stats: &OwnerStats) -> io::Result<(usize, &'static str, usize)> {
    if seinfo.is_none() { relabel(root, seinfo, target, 12)?; return Ok((1, "no_seinfo", 0)); }
    relabel_partitioned(root, seinfo, target, stats, 8)
}
fn relabel_partitioned(root: &Path, seinfo: Option<&str>, target: u32, stats: &OwnerStats, cap: usize) -> io::Result<(usize, &'static str, usize)> {
    let serial = |reason| { relabel(root, seinfo, target, 12)?; Ok((1, reason, 0)) };
    if stats.visited < 1024 || stats.xdev != 0 || stats.partitions.is_empty() {
        return serial(if stats.plan_capped { "directory_cap" }
            else if stats.xdev != 0 { "cross_device" } else { "small_tree" }); }
    let info = seinfo.unwrap_or_else(|| root.to_str().unwrap_or(""));
    // Reuse subtree sizes from the ownership walk, without another recursive scan.
    // Split the heaviest eligible subtree until partitions are reasonably balanced.
    let nodes = &stats.partitions;
    let mut frontier = vec![0usize];
    let mut split = Vec::new();
    let mut direct_leaves = 0usize;
    let goal = (stats.visited / cap as u64).max(512);
    loop {
        let candidate = frontier.iter().enumerate().filter(|(_, id)| {
            let n = &nodes[**id];
            n.count > goal && !n.children.is_empty()
                && frontier.len() - 1 + n.children.len() <= 1024
                && direct_leaves + n.leaves <= 2048
        }).max_by_key(|(_, id)| nodes[**id].count).map(|(pos, _)| pos);
        let Some(pos) = candidate else { break; };
        let id = frontier.swap_remove(pos);
        direct_leaves += nodes[id].leaves;
        split.push(id);
        frontier.extend(nodes[id].children.iter().copied());
    }
    if frontier.len() < 2 { return serial(if nodes[0].leaves > 2048 { "leaf_cap" }
        else if nodes[0].children.len() > 1024 { "partition_cap" } else { "unsplit_tree" }); }
    let accounted = frontier.iter().map(|id| nodes[*id].count).sum::<u64>()
        + split.iter().map(|id| nodes[*id].leaves as u64 + 1).sum::<u64>();
    if accounted != stats.visited { return serial("accounting_mismatch"); }
    // Worker dispatch requires UTF-8 argv. The serial walker accepts raw Unix names.
    // Check before any split-directory relabel or worker launch.
    if !root.is_absolute() { return serial("relative_root"); }
    if frontier.iter().any(|id| nodes[*id].path.to_str().is_none()) { return serial("nonutf_frontier"); }
    // Prepare every leaf task before changing labels. Keep split directories in
    // the parent, in ancestor-first order; their disjoint leaves join the workers.
    let mut tasks: Vec<(u64, u32, PathBuf)> = frontier.iter()
        .map(|id| (nodes[*id].count, 12, nodes[*id].path.clone())).collect();
    let mut parent_leaves = Vec::new();
    let mut leaf_count = 0usize;
    for id in &split {
        let before_leaves = leaf_count;
        let mut expected_dirs: HashSet<&Path> = nodes[*id].children.iter()
            .map(|child| nodes[*child].path.as_path()).collect();
        for entry in fs::read_dir(&nodes[*id].path)? {
            let path = entry?.path();
            let metadata = fs::symlink_metadata(&path)?;
            if metadata.file_type().is_dir() {
                if !expected_dirs.remove(path.as_path()) {
                    return serial("directory_set_mismatch");
                }
            } else {
                leaf_count += 1;
                if leaf_count > direct_leaves { return serial("leaf_count_mismatch"); }
                // Preserve v889's parent-before-workers ordering for aliases and
                // raw Unix names. They must not disable parallel directory tasks.
                if path.to_str().is_none() || metadata.nlink() > 1 { parent_leaves.push(path); }
                else { tasks.push((1, 8, path)); }
            }
        }
        if leaf_count - before_leaves != nodes[*id].leaves { return serial("leaf_count_mismatch"); }
        if !expected_dirs.is_empty() { return serial("directory_set_mismatch"); }
    }
    if leaf_count != direct_leaves {
        return serial("leaf_count_mismatch");
    }
    tasks.sort_by_key(|task| std::cmp::Reverse(task.0));
    let workers = frontier.len().min(cap);
    let mut groups: Vec<(u64, usize, Vec<(u32, PathBuf)>)> = (0..workers).map(|_| (0,info.len()+128,Vec::new())).collect();
    for (count, flags, path) in tasks {
        let bytes = path.as_os_str().as_bytes().len()+24;
        if let Some(group) = groups.iter_mut().filter(|g| g.1 + bytes <= 65536).min_by_key(|g| g.0) {
            group.0 += count;
            group.1 += bytes;
            group.2.push((flags, path));
        } else if flags == 8 { parent_leaves.push(path); }
        else { return serial("directory_argv_cap"); }
    }
    for id in &split { relabel(&nodes[*id].path, seinfo, target, 8)?; }
    for path in &parent_leaves { relabel(path, seinfo, target, 8)?; }
    let exe = std::env::current_exe()?;
    let mut children = Vec::new();
    let mut failure = None;
    for (_, _, tasks) in groups {
        let mut command = std::process::Command::new(&exe);
        command.arg("speedscan").arg(if seinfo.is_some() { "selinux-restore-plan-group" }
            else { "selinux-restore-generic-plan-group" }).arg(info).arg(target.to_string());
        for (flags, path) in tasks { command.arg(flags.to_string()).arg(path); }
        match command.stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null()).spawn() {
            Ok(child) => children.push(child),
            Err(e) => { failure = Some(e); break; }
        }
    }
    // Reap every started worker before returning, including partial spawn failure.
    for mut child in children {
        match child.wait() {
            Ok(status) if status.success() => {},
            Ok(status) => { failure.get_or_insert_with(|| io::Error::other(format!("SELinux worker failed: {status}"))); },
            Err(e) => { let _ = child.kill(); let _ = child.wait(); failure.get_or_insert(e); }
        }
    }
    if let Some(e) = failure { return Err(e); }
    Ok((workers, "none", parent_leaves.len()))
}


// Eight isolated processes consume a bounded pipe stream; total directory count,
// argv size and raw Unix names do not disable concurrency. A terminator is required
// so EOF after parent death is a failure, never a successful truncated plan.
struct ExternalPool<'a> {
 root:&'a Path,
 children:Vec<std::process::Child>,
 inputs:Vec<std::process::ChildStdin>,
 loads:Vec<u64>,
 sent:u64,
}
impl<'a> ExternalPool<'a> {
 fn start(&mut self)->io::Result<()> {
  if self.children.len()>=8{return Ok(());}
  let exe=std::env::current_exe()?;
  {
   let mut child=std::process::Command::new(&exe).arg("speedscan").arg("selinux-external-stream").arg(self.root)
    .stdin(std::process::Stdio::piped()).stdout(std::process::Stdio::null()).spawn()?;
   self.inputs.push(child.stdin.take().ok_or_else(||io::Error::other("Missing worker pipe"))?);
   self.children.push(child);self.loads.push(0);
  }Ok(())
 }
 fn add(&mut self, flags:u32,path:&Path)->io::Result<()> {
  use std::io::Write;
  self.start()?;
  let bytes=path.as_os_str().as_bytes();
  if bytes.is_empty() || bytes.len()>65536{return Err(io::ErrorKind::InvalidInput.into());}
  let index=self.loads.iter().enumerate().min_by_key(|(_,n)|*n).unwrap().0;
  let pipe=&mut self.inputs[index];
  let mut frame=Vec::with_capacity(bytes.len()+8);frame.extend_from_slice(&flags.to_le_bytes());frame.extend_from_slice(&(bytes.len() as u32).to_le_bytes());frame.extend_from_slice(bytes);pipe.write_all(&frame)?;
  self.loads[index]+=1;self.sent+=1;Ok(())
 }
 fn finish(&mut self)->io::Result<()> {
  use std::io::Write;
  let mut failure=None;
  for pipe in &mut self.inputs {if let Err(e)=pipe.write_all(&[0;8]){failure.get_or_insert(e);}}
  self.inputs.clear();
  for mut child in self.children.drain(..){
   match child.wait(){Ok(s) if s.success()=>{},Ok(s)=>{failure.get_or_insert_with(||io::Error::other(format!("SELinux worker failed: {s}")));},Err(e)=>{let _=child.kill();let _=child.wait();failure.get_or_insert(e);}}
  }
  if let Some(e)=failure{Err(e)}else{Ok(())}
 }
}
impl Drop for ExternalPool<'_> {
 fn drop(&mut self){
  // Error paths close input without a terminator. Reap all started workers,
  // including a partial spawn failure or an enumeration/write error.
  self.inputs.clear();
  for mut child in self.children.drain(..){if child.wait().is_err(){let _=child.kill();let _=child.wait();}}
 }
}
fn validate_external_entry(m:&fs::Metadata,dev:u64)->io::Result<()> {
 if m.dev()!=dev || (!m.is_dir() && (!m.is_file() || m.nlink()!=1)){return Err(io::Error::other("External tree changed or unsafe entry"));}Ok(())
}
fn external_stream(args:&[String])->io::Result<()> {
 use std::{io::Read,os::unix::ffi::OsStringExt};
 if args.len()!=1{return Err(io::ErrorKind::InvalidInput.into());}
 let root=external_root(&args[0])?;let dev=fs::symlink_metadata(&root)?.dev();
 let mut input=std::io::stdin().lock();let started=Instant::now();let mut tasks=0u64;
 loop{
  let mut header=[0u8;8];input.read_exact(&mut header)?;
  let flags=u32::from_le_bytes(header[..4].try_into().unwrap());
  let len=u32::from_le_bytes(header[4..].try_into().unwrap()) as usize;
  if flags==0 && len==0 {eprintln!("EXTERNAL_STREAM_WORKER_OK tasks={tasks} elapsedMs={}",started.elapsed().as_millis());return Ok(());}
  if !matches!(flags,8|12) || len==0 || len>65536{return Err(io::ErrorKind::InvalidInput.into());}
  let mut bytes=vec![0;len];input.read_exact(&mut bytes)?;
  let path=PathBuf::from(std::ffi::OsString::from_vec(bytes));
  if !path.starts_with(&root) || path==root || fs::canonicalize(&path)?!=path{return Err(io::ErrorKind::InvalidInput.into());}
  let m=fs::symlink_metadata(&path)?;validate_external_entry(&m,dev)?;
  if m.is_dir()!=(flags==12){return Err(io::Error::other("SELinux stream task type changed"));}
  relabel(&path,None,0,flags)?;tasks+=1;
 }
}
fn relabel_external_batched(root:&Path,stats:&OwnerStats)->io::Result<(usize,&'static str,usize)> {
 // For <=1024 entries, exec/file_contexts startup dominates the entire operation.
 if stats.visited<=1024 {relabel(root,None,0,12)?;return Ok((1,"small_tree_startup_cost",0));}
 fn dispatch(dir:&Path,dev:u64,depth:usize,heavy:&HashSet<PathBuf>,pool:&mut ExternalPool<'_>,parents:&mut u64)->io::Result<()> {
  if depth>256{return Err(io::ErrorKind::InvalidInput.into());}
  // Only heavy ancestors are serial, preserving the established parent-first policy.
  relabel(dir,None,0,8)?;*parents+=1;
  for entry in fs::read_dir(dir)? {
   let path=entry?.path();let m=fs::symlink_metadata(&path)?;validate_external_entry(&m,dev)?;
   if m.is_dir() && heavy.contains(&path){dispatch(&path,dev,depth+1,heavy,pool,parents)?;}
   else{pool.add(if m.is_dir(){12}else{8},&path)?;}
  }Ok(())
 }
 if !stats.external_heavy.contains(root){return Err(io::Error::other("External heavy root missing"));}
 let mut pool=ExternalPool{root,children:Vec::new(),inputs:Vec::new(),loads:Vec::new(),sent:0};let mut parents=0;
 dispatch(root,fs::symlink_metadata(root)?.dev(),0,&stats.external_heavy,&mut pool,&mut parents)?;
 let workers=pool.children.len();pool.finish()?;
 println!("EXTERNAL_STREAM_PLAN heavy={} parentDirs={parents} tasks={} workers={workers}",stats.external_heavy.len(),pool.sent);
 Ok((workers,"streaming",0))
}

// External trees must already have completed external-policy-repair. This walk
// only collects sizes: it never applies internal app ownership or seinfo rules.
fn external_partitions(root: &Path) -> io::Result<OwnerStats> {
    fn visit(p: &Path, dev: u64, depth: usize, out: &mut OwnerStats) -> io::Result<Option<usize>> {
        let m = fs::symlink_metadata(p)?;
        if m.dev() != dev || depth > 256 || (!m.is_dir() && (!m.is_file() || m.nlink() != 1)) {
            out.xdev += 1;
            return Ok(None);
        }
        out.visited += 1;
        if !m.is_dir() { return Ok(None); }
        if out.partitions.len() >= 4096 { out.plan_capped = true; return Ok(None); }
        let id = out.partitions.len();
        out.partitions.push(Partition { path: p.to_path_buf(), count: 1, leaves: 0, children: Vec::new() });
        for entry in fs::read_dir(p)? {
            let child = visit(&entry?.path(), dev, depth + 1, out)?;
            if out.plan_capped || out.xdev != 0 { return Ok(Some(id)); }
            if let Some(child) = child {
                out.partitions[id].children.push(child);
                out.partitions[id].count += out.partitions[child].count;
            } else {
                out.partitions[id].count += 1;
                out.partitions[id].leaves += 1;
            }
        }
        Ok(Some(id))
    }
    let mut out = OwnerStats::default();
    visit(root, fs::symlink_metadata(root)?.dev(), 0, &mut out)?;
    if out.plan_capped || out.xdev != 0 { out.partitions.clear(); }
    Ok(out)
}
fn external_root(text: &str) -> io::Result<PathBuf> {
    let root = root_path(text)?;
    let parts: Vec<&str> = text.split('/').collect();
    if parts.len() != 7 || parts[0] != "" || parts[1] != "data" || parts[2] != "media"
        || parts[3].parse::<u32>().ok().map(|v| v.to_string()).as_deref() != Some(parts[3]) || parts[4] != "Android"
        || !matches!(parts[5], "data" | "obb") || !parts[6].contains('.')
        || !parts[6].bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'_')
        || fs::canonicalize(&root)? != root {
        return Err(io::ErrorKind::InvalidInput.into());
    }
    Ok(root)
}
fn run(args: &[String], mode: &str) -> io::Result<()> {
    let start = Instant::now();
    match mode {
        "probe" => {
            symbol(b"selinux_android_restorecon\0")?;
            symbol(b"selinux_android_restorecon_pkgdir\0")?;
            println!("ANDROID_POLICY_PROBE_OK api={} restorecon=1 pkgdir=1", device_api());
        }
        "owner" | "permissions" => {
            if args.len() != if mode == "owner" {3} else {4} { return Err(io::ErrorKind::InvalidInput.into()); }
            let target = uid(&args[0])?;
            let previous = uid(&args[1])?;
            let root = root_path(&args[2])?;
            let api = device_api();
            if api < 0 { return Err(io::ErrorKind::Unsupported.into()); }
            // Resolve SELinux before modifying ownership to avoid avoidable partial changes.
            if mode == "permissions" {
                symbol(if args[3] == "-" { b"selinux_android_restorecon\0" } else { b"selinux_android_restorecon_pkgdir\0" })?;
            }
            let owner_start = Instant::now();
            let out = owners(&root, target, previous, api, mode == "permissions" && args[3] != "-")?;
            let owner_ms = owner_start.elapsed().as_millis();
            let label_start = Instant::now();
            let (workers, fallback, parent_leaves) = if mode == "permissions" { relabel_app(&root, if args[3] == "-" {None} else {Some(&args[3])}, target, &out)? } else { (0, "none", 0) };
            println!("ANDROID_APP_POLICY_OK visited={} changed={} preservedOtherUid={} xdev={} uid={} previousUid={} api={} elapsedMs={} ownerMs={} selinuxMs={} selinuxWorkers={} selinuxFallback={} selinuxParentLeaves={}",
                out.visited, out.changed, out.preserved, out.xdev, target, previous, api, start.elapsed().as_millis(), owner_ms, if mode == "permissions" { label_start.elapsed().as_millis() } else { 0 }, workers, fallback, parent_leaves);
        }
        "selinux-external" => {
            if args.len() != 1 && args.len() != 2 { return Err(io::ErrorKind::InvalidInput.into()); }
            let cap = if args.len() == 1 { 8 } else { match args[1].as_str() {
                "2" => 2, "4" => 4, "8" => 8, _ => return Err(io::ErrorKind::InvalidInput.into())
            } };
            let root = external_root(&args[0])?;
            symbol(b"selinux_android_restorecon\0")?;
            let stats = external_partitions(&root)?;
            let scan_ms = start.elapsed().as_millis();
            let (workers, fallback, parent_leaves) = relabel_partitioned(&root, None, 0, &stats, cap)?;
            println!("ANDROID_EXTERNAL_SELINUX_OK visited={} elapsedMs={} scanMs={} selinuxWorkers={} selinuxFallback={} selinuxParentLeaves={}",
                stats.visited, start.elapsed().as_millis(), scan_ms, workers, fallback, parent_leaves);
        }
        "selinux-plan-group" | "selinux-generic-plan-group" => {
            let generic = mode == "selinux-generic-plan-group";
            if args.len() < 4 || (args.len()-2) % 2 != 0 || args[0].is_empty()
                || (generic && args[1] != "0") || (!generic && args[0] == "-") {
                return Err(io::ErrorKind::InvalidInput.into());
            }
            let target = uid(&args[1])?;
            let scope = if generic { Some(external_root(&args[0])?) } else { None };
            // Validate the entire group before making any label change.
            let mut tasks = Vec::new();
            for pair in args[2..].chunks_exact(2) {
                let flags = match pair[0].as_str() {
                    "8" => 8, "12" => 12, _ => return Err(io::ErrorKind::InvalidInput.into())
                };
                let path = PathBuf::from(&pair[1]);
                if !path.is_absolute() || path.as_os_str().as_bytes().contains(&0) {
                    return Err(io::ErrorKind::InvalidInput.into());
                }
                if let Some(root) = &scope {
                    if !path.starts_with(root) || path == *root || fs::canonicalize(&path)? != path {
                        return Err(io::ErrorKind::InvalidInput.into());
                    }
                }
                let is_dir = fs::symlink_metadata(&path)?.file_type().is_dir();
                if is_dir != (flags == 12) { return Err(io::Error::other("SELinux task type changed")); }
                tasks.push((flags, path));
            }
            for (flags, path) in tasks {
                relabel(&path, if generic { None } else { Some(&args[0]) }, target, flags).map_err(|error|
                    io::Error::other(format!("SELinux task failed flags={flags} path={path:?}: {error}")))?;
            }
        }
        "external-stream" => {external_stream(args)?;}
        "selinux-group" => {
            if args.len() < 3 || args[0].is_empty() || args[0] == "-" { return Err(io::ErrorKind::InvalidInput.into()); }
            let target = uid(&args[1])?;
            for path in &args[2..] { relabel(&root_path(path)?, Some(&args[0]), target, 12)?; }
        }
        "selinux" => {
            if args.len() != 2 && args.len() != 4 { return Err(io::ErrorKind::InvalidInput.into()); }
            let flags = args[1].parse::<u32>().map_err(|_| io::ErrorKind::InvalidInput)?;
            if args[0].is_empty() { return Err(io::ErrorKind::InvalidInput.into()); }
            let (info, target) = if args.len() == 4 { (Some(args[2].as_str()), uid(&args[3])?) } else { (None, 0) };
            relabel(Path::new(&args[0]), info, target, flags)?;
            println!("ANDROID_SELINUX_OK elapsedMs={}",start.elapsed().as_millis());
        }
        _ => return Err(io::ErrorKind::InvalidInput.into()),
    }
    Ok(())
}
pub fn command(args: &[String], mode: &str) -> i32 {
    match run(args, mode) {
        Ok(()) => 0,
        Err(e) => { eprintln!("ANDROID_APP_POLICY_FAILED mode={mode} errno={} error={e} partialChangesPossible=true",e.raw_os_error().unwrap_or(0)); 1 }
    }
}

// Fused external entry: caller completed the fd-pinned validation/apply walk.
pub(super) fn external_prepare(text: &str) -> io::Result<()> {
    external_root(text)?;
    symbol(b"selinux_android_restorecon\0")?;
    Ok(())
}
pub(super) fn external_from_walk(root: &Path, stats: &OwnerStats) -> io::Result<()> {
    external_root(root.to_str().ok_or(io::ErrorKind::InvalidInput)?)?;
    let start = Instant::now();
    let (workers, fallback, leaves) = relabel_external_batched(root, stats)?;
    println!("EXTERNAL_FUSED_LABEL_OK visited={} selinuxMs={} workers={} fallback={} parentLeaves={}",stats.visited,start.elapsed().as_millis(),workers,fallback,leaves);
    Ok(())
}
