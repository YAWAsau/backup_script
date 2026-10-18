// SPDX-License-Identifier: GPL-3.0-only
// External-storage metadata policy follows AOSP vold Utils.cpp and
// android_projectid_config.h. Run outside vold: ROM restorecon property bridges
// can wait forever for paths exceeding PROP_VALUE_MAX while holding its lock.
use std::{ffi::CString, fs::{self, File, OpenOptions}, io, os::fd::{AsRawFd, FromRawFd},
    os::unix::{ffi::OsStrExt, fs::{MetadataExt, OpenOptionsExt}}, path::Path};
use super::android_policy::{self, OwnerStats};
use std::time::Instant;
use std::os::raw::{c_char, c_int, c_ulong, c_void};
type Plan = std::sync::Mutex<std::collections::BinaryHeap<std::cmp::Reverse<(u64,std::path::PathBuf)>>>;
const NOFOLLOW: i32 = speedbackup_native_rs::O_NOFOLLOW_NATIVE;
const CLOEXEC: i32 = 0x80000;
const NONBLOCK: i32 = 0x800;
#[repr(C)]
#[derive(Default)]
struct Fsx { flags:u32, extsize:u32, nextents:u32, project:u32, cow:u32, pad:[u8;8] }
extern "C" {
    fn openat(fd:c_int, name:*const c_char, flags:c_int, ...) -> c_int;
    fn fchown(fd:c_int, uid:u32, gid:u32) -> c_int;
    fn fchmod(fd:c_int, mode:u32) -> c_int;
    fn ioctl(fd:c_int, request:c_ulong, argp:*mut c_void) -> c_int;
    fn fgetxattr(fd:c_int, name:*const c_char, value:*mut c_void, size:usize) -> isize;
    fn fsetxattr(fd:c_int, name:*const c_char, value:*const c_void, size:usize, flags:c_int) -> c_int;
}
fn check(rc:i32) -> io::Result<()> { if rc == 0 {Ok(())} else {Err(io::Error::last_os_error())} }
fn bad() -> io::Error { io::Error::new(io::ErrorKind::InvalidInput,"unsafe external metadata target") }
#[derive(Debug)]
struct SiblingCancelled;
impl std::fmt::Display for SiblingCancelled {fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{f.write_str("External sibling failed")}}
impl std::error::Error for SiblingCancelled {}
fn cancelled()->io::Error{io::Error::other(SiblingCancelled)}
fn is_cancelled(e:&io::Error)->bool{e.get_ref().is_some_and(|inner|inner.is::<SiblingCancelled>())}
fn acl_set(fd:i32, name:&[u8], acl:&[u8]) -> io::Result<()> {
    check(unsafe {fsetxattr(fd,name.as_ptr().cast(),acl.as_ptr().cast(),acl.len(),0)})
}
fn walk(file:File, dev:u64, uid:u32, gid:u32, project:u32, cache_project:u32,
        acl:&[u8], file_acl:&[u8], depth:usize, apply:bool, count:&mut u64, path:&Path, cancel:Option<&std::sync::atomic::AtomicBool>, collect:Option<&Plan>, descend:bool) -> io::Result<()> {
    if cancel.is_some_and(|c|c.load(std::sync::atomic::Ordering::Acquire)) {return Err(cancelled());}
    if depth > 256 {return Err(bad());}
    let m=file.metadata()?;
    let dir=m.is_dir();
    if m.dev()!=dev || (!dir && (!m.is_file() || m.nlink()!=1)) {return Err(bad());}
    *count+=1;
    let fd=file.as_raw_fd();
    let mut x=Fsx::default();
    check(unsafe {ioctl(fd,0x801c581f,(&mut x as *mut Fsx).cast())})?; // FS_IOC_FSGETXATTR
    if apply {
        check(unsafe {fchown(fd,uid,gid)})?;
        check(unsafe {fchmod(fd,if dir {0o2770} else {0o660})})?;
        x.project=project;
        if dir {x.flags|=0x200;} // FS_XFLAG_PROJINHERIT
        check(unsafe {ioctl(fd,0x401c5820,(&mut x as *mut Fsx).cast())})?; // FS_IOC_FSSETXATTR
        // vold owns the package-root access ACL (which may grant media_rw,
        // or be absent). Its default ACL is for descendants, not the root.
        if depth > 0 {acl_set(fd,b"system.posix_acl_access\0",if dir {acl} else {file_acl})?;}
        if dir {acl_set(fd,b"system.posix_acl_default\0",acl)?;}
    }
    let before_count=*count;
    if dir && descend {
        // Enumerate through the pinned directory and open children relative to it.
        // No child symlinks, FIFOs, devices or cross-device mounts are accepted.
        for e in fs::read_dir(format!("/proc/self/fd/{fd}"))? {
            let name=e?.file_name();
            let next=if depth==0 && name=="cache" {cache_project} else {project};
            let c=CString::new(name.as_bytes()).map_err(|_|bad())?;
            let child=unsafe {openat(fd,c.as_ptr(),NOFOLLOW|CLOEXEC|NONBLOCK)};
            if child<0 {return Err(io::Error::last_os_error());}
            let child_file=unsafe {File::from_raw_fd(child)};
            let child_path=if collect.is_some() {Some(path.join(&name))} else {None};
            walk(child_file,dev,uid,gid,next,cache_project,acl,file_acl,depth+1,apply,count,child_path.as_deref().unwrap_or(path),cancel,collect,true)?;

        }
    }
    if dir {if let Some(plan)=collect {
        let weight=*count-before_count+1;
        let mut heap=plan.lock().map_err(|_|bad())?;
        if heap.len()<8224 || heap.peek().is_some_and(|entry|weight>(entry.0).0) {
            heap.push(std::cmp::Reverse((weight,path.to_path_buf())));
            if heap.len()>8224 {heap.pop();}
        }
    }}
    Ok(())
}
// Reuse the preflight's bounded heavy plan. The coordinator applies only
// ancestors; workers get disjoint, fd-pinned boundary subtrees of <=~N/32 items.
fn apply_scheduled(root:File,dev:u64,uid:u32,gid:u32,project:u32,cache_project:u32,
 acl:&[u8],file_acl:&[u8],path:&Path,heavy:&std::collections::HashSet<std::path::PathBuf>)->io::Result<u64>{
 use std::sync::{mpsc,Mutex,atomic::{AtomicBool,Ordering}};
 type Job=(File,std::path::PathBuf,usize,u32);
 fn dispatch(file:File,path:&Path,depth:usize,project:u32,cache_project:u32,dev:u64,uid:u32,gid:u32,
  acl:&[u8],file_acl:&[u8],heavy:&std::collections::HashSet<std::path::PathBuf>,tx:&mpsc::SyncSender<Job>,failed:&AtomicBool,count:&mut u64)->io::Result<()> {
  if failed.load(Ordering::Acquire){return Err(cancelled());}
  if depth>256{return Err(bad());}
  if !heavy.contains(path){return tx.send((file,path.to_path_buf(),depth,project)).map_err(|_|bad());}
  // Retain this directory fd for enumeration after its metadata is complete.
  walk(file.try_clone()?,dev,uid,gid,project,cache_project,acl,file_acl,depth,true,count,path,Some(failed),None,false)?;
  let fd=file.as_raw_fd();
  for entry in fs::read_dir(format!("/proc/self/fd/{fd}"))? {
   let name=entry?.file_name();let c=CString::new(name.as_bytes()).map_err(|_|bad())?;
   let child=unsafe{openat(fd,c.as_ptr(),NOFOLLOW|CLOEXEC|NONBLOCK)};
   if child<0{return Err(io::Error::last_os_error());}
   let child=unsafe{File::from_raw_fd(child)};
   let next=if depth==0 && name=="cache"{cache_project}else{project};
   dispatch(child,&path.join(name),depth+1,next,cache_project,dev,uid,gid,acl,file_acl,heavy,tx,failed,count)?;
  }Ok(())
 }
 let(tx,rx)=mpsc::sync_channel::<Job>(32);let rx=Mutex::new(rx);let failed=AtomicBool::new(false);
 std::thread::scope(|scope|{
  let mut handles=Vec::new();let mut failure=None;
  for _ in 0..8 {
   let rx=&rx;let failed=&failed;
   match std::thread::Builder::new().spawn_scoped(scope,move||->io::Result<u64>{
    let mut count=0;let mut failure=None;
    loop {
     let item=rx.lock().map_err(|_|bad())?.recv();let Ok((file,path,depth,project))=item else{break;};
     if failed.load(Ordering::Acquire){continue;}
     if let Err(e)=walk(file,dev,uid,gid,project,cache_project,acl,file_acl,depth,true,&mut count,&path,Some(failed),None,true){failed.store(true,Ordering::Release);failure=Some(e);}
    }
    if let Some(e)=failure{Err(e)}else{Ok(count)}
   }) {Ok(handle)=>handles.push(handle),Err(e)=>{failed.store(true,Ordering::Release);failure=Some(e);break;}}
  }
  let mut count=0;
  if failure.is_none(){failure=dispatch(root,path,0,project,cache_project,dev,uid,gid,acl,file_acl,heavy,&tx,&failed,&mut count).err();}
  if failure.is_some(){failed.store(true,Ordering::Release);}drop(tx);
  for handle in handles {match handle.join(){
   Ok(Ok(n))=>count+=n,
   Ok(Err(e))=>{if failure.as_ref().map_or(true,|old|is_cancelled(old) && !is_cancelled(&e)){failure=Some(e);}},
   Err(_)=>{failure.get_or_insert_with(bad);}
  }}
  if let Some(e)=failure{Err(e)}else{Ok(count)}
 })
}
fn run(args:&[String], fused:bool) -> io::Result<()> {
    let start=Instant::now();
    if args.len()!=3 {return Err(bad());}
    let uid=args[1].parse::<u32>().map_err(|_|bad())?;
    if uid%100000<10000 || uid>i32::MAX as u32 {return Err(bad());}
    let kind=args[2].as_str();
    let (gid,base)=match kind {"data"=>(1078,20000),"obb"=>(1079,40000),_=>return Err(bad())};
    let root=Path::new(&args[0]);
    let parent=format!("/data/media/{}/Android/{kind}",uid/100000);
    if root.parent()!=Some(Path::new(&parent)) || fs::canonicalize(root)?!=root {return Err(bad());}
    let name=root.file_name().ok_or_else(bad)?.as_bytes();
    if !name.contains(&b'.') || !name.iter().all(|b|b.is_ascii_alphanumeric() || *b==b'.' || *b==b'_') {return Err(bad());}
    let open=|| OpenOptions::new().read(true).custom_flags(NOFOLLOW|CLOEXEC|NONBLOCK|speedbackup_native_rs::O_DIRECTORY_NATIVE).open(root);
    if fused {android_policy::external_prepare(&args[0])?;}
    let f=open()?;let before=f.metadata()?;let dev=before.dev();
    let mut acl=vec![0u8;4096];
    let n=unsafe {fgetxattr(f.as_raw_fd(),b"system.posix_acl_default\0".as_ptr().cast(),acl.as_mut_ptr().cast(),acl.len())};
    if n<0 {return Err(io::Error::last_os_error());}
    acl.truncate(n as usize);
    if acl.len()<4 || acl[..4]!=[2,0,0,0] || (acl.len()-4)%8!=0 {return Err(bad());}
    // The package root's default ACL was established by the short-path setup.
    if !acl[4..].chunks_exact(8).any(|e|e[..2]==[8,0] && e[2..4]==[7,0] && e[4..8]==uid.to_le_bytes()) {return Err(bad());}
    let project=uid-10000+base;
    let cache=if kind=="data" {uid-10000+30000} else {project};
    // Derive the FUSE 0660 regular-file ACL once for the whole tree.
    // Keep inherited groups, but remove execute from owner/mask/other.
    let mut file_acl=acl.clone();
    for entry in file_acl[4..].chunks_exact_mut(8) {
        let tag=u16::from_le_bytes([entry[0],entry[1]]);
        if matches!(tag,1|16|32) {
            let perm=u16::from_le_bytes([entry[2],entry[3]]) & 6;
            entry[2..4].copy_from_slice(&perm.to_le_bytes());
        }
    }
    let mut stats=OwnerStats::default();
    let plan=Plan::default();
    let mut checked=0;walk(f,dev,uid,gid,project,cache,&acl,&file_acl,0,false,&mut checked,root,None,if fused{Some(&plan)}else{None},true)?;
    let preflight_ms=start.elapsed().as_millis();
    let second=open()?;let after=second.metadata()?;
    if after.dev()!=dev || after.ino()!=before.ino() {return Err(bad());}
    let mut changed=0;
    if fused {
        let threshold=(checked/32).max(256);
        stats.external_heavy=plan.into_inner().map_err(|_|bad())?.into_iter()
            .filter(|entry|(entry.0).0>=threshold || (entry.0).1==root)
            .map(|entry|(entry.0).1).collect();
        changed=apply_scheduled(second,dev,uid,gid,project,cache,&acl,&file_acl,root,&stats.external_heavy)?;
        if changed!=checked {return Err(io::Error::other("External tree entry count changed"));}
        stats.visited=changed;
        println!("EXTERNAL_METADATA_POOL_OK workers=8 heavy={} changed={changed}",stats.external_heavy.len());
    } else {
        walk(second,dev,uid,gid,project,cache,&acl,&file_acl,0,true,&mut changed,root,None,None,true)?;
    }
    let repair_ms=start.elapsed().as_millis();
    println!("EXTERNAL_POLICY_OK checked={checked} changed={changed} uid={uid} backend=native-fd");
    if fused {
        // Catch package-root replacement before handing path-based work to libselinux.
        let current=open()?.metadata()?;
        if current.dev()!=dev || current.ino()!=before.ino() {return Err(bad());}
        android_policy::external_from_walk(root,&stats).map_err(|e| io::Error::new(e.kind(),format!("stage=selinux {e}")))?;
        println!("EXTERNAL_FUSED_OK checked={checked} changed={changed} preflightMs={preflight_ms} repairMs={repair_ms} elapsedMs={}",start.elapsed().as_millis());
    }
    Ok(())
}
pub fn command(args:&[String])->i32 {
    match run(args,false) {Ok(())=>0,Err(e)=>{eprintln!("EXTERNAL_POLICY_FAILED error={e} partialChangesPossible=true");1}}
}

pub fn fused_command(args:&[String])->i32 {match run(args,true) {Ok(())=>0,Err(e)=>{eprintln!("EXTERNAL_FUSED_FAILED error={e} partialChangesPossible=true");1}}}
