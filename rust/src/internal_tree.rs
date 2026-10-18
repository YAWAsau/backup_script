// SPDX-License-Identifier: GPL-3.0-only
// Internal app roots only. Adapted from the v899 bounded external clear engine.
// A stopped app and stable tree remain required; never follow leaf symlinks.
use std::{ffi::CString,fs::{self,File,OpenOptions},io,os::{fd::{AsRawFd,FromRawFd},unix::{ffi::OsStrExt,fs::{MetadataExt,OpenOptionsExt}}},path::Path,sync::{Mutex,mpsc,atomic::{AtomicBool,Ordering}},time::Instant};
use std::os::raw::{c_char,c_int};
const FLAGS:i32=speedbackup_native_rs::O_NOFOLLOW_NATIVE|0x80000|0x800;
extern "C" {fn openat(fd:c_int,name:*const c_char,flags:c_int,...)->c_int;fn unlinkat(fd:c_int,name:*const c_char,flags:c_int)->c_int;}
#[repr(C)]
struct RLimit { current:std::os::raw::c_ulong, maximum:std::os::raw::c_ulong }
extern "C" {fn getrlimit(resource:c_int,limit:*mut RLimit)->c_int;}
fn fd_budget(max_depth:usize)->io::Result<()> {
 let mut limit=RLimit{current:0,maximum:0};
 if unsafe{getrlimit(7,&mut limit)}!=0{return Err(io::Error::last_os_error());}
 let open=fs::read_dir("/proc/self/fd")?.collect::<io::Result<Vec<_>>>()?.len();
 // Conservative bound: coordinator plus all eight workers at maximum depth,
 // one directory fd and one ReadDir per level, queue/active duplicates and slack.
 let required=open+9*2*(max_depth+2)+64;
 if (limit.current as u128)<required as u128{return Err(io::Error::other(format!("FD_BUDGET_REQUIRED required={required} available={}",limit.current)));}
 Ok(())
}
fn bad()->io::Error{io::Error::other("Unsafe or changed internal clear tree")}
#[derive(Debug)]
struct SiblingCancelled;
impl std::fmt::Display for SiblingCancelled {fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"Sibling cancelled")}}
impl std::error::Error for SiblingCancelled {}
fn cancelled()->io::Error{io::Error::other(SiblingCancelled)}
fn is_cancelled(e:&io::Error)->bool{e.get_ref().is_some_and(|x|x.is::<SiblingCancelled>())}
fn merge_error(old:&mut Option<io::Error>,new:io::Error){if old.as_ref().map_or(true,|e|is_cancelled(e) && !is_cancelled(&new)){*old=Some(new);}}
fn valid(m:&fs::Metadata,dev:u64)->io::Result<()> {
 valid_type(m.dev(),m.mode(),m.nlink(),dev)
}
fn valid_type(actual:u64,mode:u32,nlink:u64,dev:u64)->io::Result<()> {
 // Removing a name does not modify its hardlink siblings or symlink target.
 // Device nodes are unexpected in app data and fail the preflight.
 if (!matches!(mode&0o170000,0o040000|0o100000) && nlink!=1) || actual!=dev || !matches!(mode&0o170000,0o040000|0o100000|0o120000|0o010000|0o140000){return Err(bad());}Ok(())
}
fn open_child(parent:&File,name:&CString)->io::Result<File>{
 let fd=unsafe{openat(parent.as_raw_fd(),name.as_ptr(),FLAGS)};
 if fd<0{return Err(io::Error::last_os_error());}Ok(unsafe{File::from_raw_fd(fd)})
}

// Keep the entry checks identical while resolving relative to the pinned fd.
struct EntryStat { dev:u64, ino:u64, mode:u32, nlink:u64 }
impl EntryStat {
 fn dev(&self)->u64{self.dev} fn ino(&self)->u64{self.ino} fn mode(&self)->u32{self.mode}
 fn is_dir(&self)->bool{self.mode&0o170000==0o040000}
 fn valid(&self,dev:u64)->io::Result<()>{valid_type(self.dev,self.mode,self.nlink,dev)}
 fn matches(&self,m:&fs::Metadata)->bool{(self.dev,self.ino,self.mode,self.nlink)==(m.dev(),m.ino(),m.mode(),m.nlink())}
}
// Pinned NDK r30 bionic sys/stat.h, Android arm64 only. Other targets use std.
#[cfg(all(target_os="android",target_arch="aarch64"))]
#[repr(C)]
struct NativeStat { dev:u64, ino:u64, mode:u32, nlink:u32, uid:u32, gid:u32, rdev:u64, pad1:u64, size:i64, blksize:i32, pad2:i32, blocks:i64, times:[i64;6], unused:[u32;2] }
#[cfg(all(target_os="android",target_arch="aarch64"))]
const _: () = {
 assert!(std::mem::size_of::<NativeStat>()==128);assert!(std::mem::align_of::<NativeStat>()==8);
 assert!(std::mem::offset_of!(NativeStat,dev)==0);assert!(std::mem::offset_of!(NativeStat,ino)==8);
 assert!(std::mem::offset_of!(NativeStat,mode)==16);assert!(std::mem::offset_of!(NativeStat,nlink)==20);
};
#[cfg(all(target_os="android",target_arch="aarch64"))]
extern "C" {fn fstatat(fd:c_int,path:*const c_char,buf:*mut NativeStat,flags:c_int)->c_int;}
fn entry_stat(parent:&File,name:&CString)->io::Result<EntryStat>{
 #[cfg(all(target_os="android",target_arch="aarch64"))]
 {
  let mut m=std::mem::MaybeUninit::<NativeStat>::zeroed();
  // AT_SYMLINK_NOFOLLOW: the final component must never be followed.
  if unsafe{fstatat(parent.as_raw_fd(),name.as_ptr(),m.as_mut_ptr(),0x100)}!=0{return Err(io::Error::last_os_error());}
  let m=unsafe{m.assume_init()};Ok(EntryStat{dev:m.dev,ino:m.ino,mode:m.mode,nlink:m.nlink as u64})
 }
 #[cfg(not(all(target_os="android",target_arch="aarch64")))]
 {
  let path=Path::new(&format!("/proc/self/fd/{}",parent.as_raw_fd())).join(std::ffi::OsStr::from_bytes(name.as_bytes()));
  let m=fs::symlink_metadata(path)?;Ok(EntryStat{dev:m.dev(),ino:m.ino(),mode:m.mode(),nlink:m.nlink()})
 }
}

fn visit(parent:&File,name:&CString,dev:u64,depth:usize,failed:&AtomicBool)->io::Result<u64>{
 if failed.load(Ordering::Acquire){return Err(cancelled());}
 if depth>256{return Err(bad());}
 let entry=entry_stat(parent,name)?;entry.valid(dev)?;
 // unlinkat never follows a regular-file entry. No data fd is needed to delete it.
 if !entry.is_dir(){
  if unsafe{unlinkat(parent.as_raw_fd(),name.as_ptr(),0)}!=0{return Err(io::Error::last_os_error());}
  return Ok(1);
 }
 let f=open_child(parent,name)?;let m=f.metadata()?;valid(&m,dev)?;
 if entry.dev()!=m.dev() || entry.ino()!=m.ino(){return Err(bad());}let mut count=1;
 if m.is_dir(){
  for item in fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))? {
   let name=CString::new(item?.file_name().as_bytes()).map_err(|_|bad())?;
   count+=visit(&f,&name,dev,depth+1,failed)?;
  }
 }
 {
  // Refuse to remove a different inode than the one just examined/emptied.
  let now=entry_stat(parent,name)?;
  if now.dev()!=m.dev() || now.ino()!=m.ino() || now.mode()!=m.mode(){return Err(bad());}
  if unsafe{unlinkat(parent.as_raw_fd(),name.as_ptr(),if m.is_dir(){0x200}else{0})}!=0{return Err(io::Error::last_os_error());}
 }
 Ok(count)
}

type Heap=std::collections::BinaryHeap<std::cmp::Reverse<(u64,std::path::PathBuf)>>;
const MIN_HEAVY:u64=256;
// Read-only second preflight also builds exact subtree sizes. A pending sentinel
// keeps each directory alive until enumeration AND all descendants complete.
// Only the bounded queue/active recursion paths retain nodes; no full-tree index.
fn parallel_plan(root:&File,dev:u64)->io::Result<(u64,Heap,usize)>{
 use std::{collections::VecDeque,sync::{Arc,Condvar,atomic::{AtomicU64,AtomicUsize}}};
 struct Node { name:std::ffi::OsString,parent:Option<Arc<Node>>,count:AtomicU64,pending:AtomicUsize }
 impl Node {fn new(name:std::ffi::OsString,parent:Option<Arc<Node>>)->Self{Self{name,parent,count:AtomicU64::new(1),pending:AtomicUsize::new(1)}}}
 type Job=(File,Vec<CString>,usize,Arc<Node>);
 struct State {queue:VecDeque<Job>,active:usize,error:Option<io::Error>,heap:Heap}
 type Shared=(Mutex<State>,Condvar,AtomicUsize);
 fn complete(mut node:Arc<Node>,mut count:u64,shared:&Shared)->io::Result<()> {
  loop {
   node.count.fetch_add(count,Ordering::Relaxed);
   if node.pending.fetch_sub(1,Ordering::AcqRel)!=1{return Ok(());}
   // The last completion observes all preceding descendant count additions.
   count=node.count.load(Ordering::Acquire);
   {let mut state=shared.0.lock().map_err(|_|bad())?;
    // The final heavy threshold is always >= MIN_HEAVY. Smaller subtrees
    // still validate/count fully, but cannot need a retained planning path.
    if count>=MIN_HEAVY && (state.heap.len()<8224 || state.heap.peek().is_some_and(|x|count>(x.0).0)){
     // Ancestors store only one component each, not repeated full paths.
     // Materialize a path only for a retained heap entry.
     let mut parts=Vec::new();let mut ancestor=Some(node.as_ref());
     while let Some(n)=ancestor{parts.push(n.name.as_os_str());ancestor=n.parent.as_deref();}
     let path=parts.into_iter().rev().collect::<std::path::PathBuf>();
     state.heap.push(std::cmp::Reverse((count,path)));if state.heap.len()>8224{state.heap.pop();}
    }
   }
   match node.parent.clone(){Some(parent)=>node=parent,None=>return Ok(())}
  }
 }
 fn batch(f:&File,node:&Arc<Node>,depth:usize,names:Vec<CString>,dev:u64,shared:&Shared)->io::Result<()> {
  let mut state=shared.0.lock().map_err(|_|bad())?;
  if state.error.is_some(){return Err(cancelled());}
  if state.queue.len()<32 {
   let parent=f.try_clone()?;
   node.pending.fetch_add(names.len(),Ordering::Relaxed);
   state.queue.push_back((parent,names,depth,node.clone()));shared.1.notify_one();
  }else{
   node.pending.fetch_add(names.len(),Ordering::Relaxed);drop(state);
   for name in names{visit_plan(f,&name,depth,node,dev,shared)?;}
  }
  Ok(())
 }
 fn enumerate(f:&File,node:&Arc<Node>,depth:usize,dev:u64,shared:&Shared)->io::Result<()> {
  // Keep one child local. A single-child chain cannot run in parallel, and
  // handing every level to another worker only adds scheduler/condvar traffic.
  let mut local=None;let mut names=Vec::new();
  for entry in fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))? {
   let name=CString::new(entry?.file_name().as_bytes()).map_err(|_|bad())?;
   if local.is_none(){local=Some(name);continue;}
   if names.capacity()==0{names.reserve_exact(64);}names.push(name);
   // One pinned parent fd and queue operation per bounded batch, not per file.
   if names.len()==64{batch(f,node,depth+1,std::mem::take(&mut names),dev,shared)?;}
  }
  if !names.is_empty(){
   // Keep large batches cheap, but expose small independent branches when
   // workers would otherwise be idle. This is only a scheduling hint.
   let slots={let state=shared.0.lock().map_err(|_|bad())?;8usize.saturating_sub(state.active+state.queue.len()).max(1)};
   let size=names.len().div_ceil(slots);let mut tail=names.into_iter();
   loop{let group:Vec<_>=tail.by_ref().take(size).collect();if group.is_empty(){break;}batch(f,node,depth+1,group,dev,shared)?;}
  }
  if let Some(name)=local{
   node.pending.fetch_add(1,Ordering::Relaxed);
   visit_plan(f,&name,depth+1,node,dev,shared)?;
  }
  complete(node.clone(),0,shared)
 }
 fn visit_plan(parent:&File,name:&CString,depth:usize,node:&Arc<Node>,dev:u64,shared:&Shared)->io::Result<()> {
  if depth>256{return Err(bad());}
  shared.2.fetch_max(depth,Ordering::Relaxed);
  if shared.0.lock().map_err(|_|bad())?.error.is_some(){return Err(cancelled());}
  let path=Path::new(&format!("/proc/self/fd/{}",parent.as_raw_fd())).join(std::ffi::OsStr::from_bytes(name.as_bytes()));
  let m=fs::symlink_metadata(path)?;valid(&m,dev)?;
  if !m.is_dir(){return complete(node.clone(),1,shared);}
  let child=open_child(parent,name)?;let cm=child.metadata()?;valid(&cm,dev)?;
  if !cm.is_dir() || cm.ino()!=m.ino() || cm.dev()!=m.dev(){return Err(bad());}
  let child_node=Arc::new(Node::new(std::ffi::OsStr::from_bytes(name.as_bytes()).to_os_string(),Some(node.clone())));
  enumerate(&child,&child_node,depth,dev,shared)
 }
 let m=root.metadata()?;valid(&m,dev)?;if !m.is_dir(){return Err(bad());}
 let root_node=Arc::new(Node::new(std::ffi::OsString::new(),None));
 let shared=(Mutex::new(State{queue:VecDeque::new(),active:1,error:None,heap:Heap::new()}),Condvar::new(),AtomicUsize::new(0));
 std::thread::scope(|scope|->io::Result<(u64,Heap,usize)>{
  let mut handles=Vec::new();
  for _ in 0..7 {
   let shared=&shared;
   match std::thread::Builder::new().spawn_scoped(scope,move||{
    loop {
     let mut state=shared.0.lock().unwrap();
     while state.queue.is_empty() && state.active>0 && state.error.is_none(){state=shared.1.wait(state).unwrap();}
     if state.error.is_some() || (state.queue.is_empty() && state.active==0){break;}
     let job=state.queue.pop_front().unwrap();state.active+=1;drop(state);
     let result=job.1.iter().try_for_each(|name|visit_plan(&job.0,name,job.2,&job.3,dev,shared));
     let mut state=shared.0.lock().unwrap();state.active-=1;
     if let Err(e)=result{merge_error(&mut state.error,e);}shared.1.notify_all();
    }
   }){Ok(h)=>handles.push(h),Err(e)=>{shared.0.lock().unwrap().error=Some(e);break;}}
  }
  let result=enumerate(root,&root_node,0,dev,&shared);
  {let mut state=shared.0.lock().unwrap();state.active-=1;
   if let Err(e)=result{merge_error(&mut state.error,e);}shared.1.notify_all();}
  for h in handles{if h.join().is_err(){merge_error(&mut shared.0.lock().unwrap().error,bad());}}
  let mut state=shared.0.lock().unwrap();state.queue.clear();
  if let Some(e)=state.error.take(){return Err(e);}
  if root_node.pending.load(Ordering::Acquire)!=0{return Err(bad());}
  Ok((root_node.count.load(Ordering::Acquire),std::mem::take(&mut state.heap),shared.2.load(Ordering::Relaxed)))
 })
}

fn clear_scheduled(root:&File,dev:u64,heavy:&std::collections::HashSet<std::path::PathBuf>)->io::Result<u64>{
 type Job=(File,CString,usize);
 type Record=(std::path::PathBuf,u64);
 fn dispatch(f:&File,path:&Path,dev:u64,depth:usize,heavy:&std::collections::HashSet<std::path::PathBuf>,tx:&mpsc::SyncSender<Job>,failed:&AtomicBool,records:&mut Vec<Record>)->io::Result<()> {
  if failed.load(Ordering::Acquire){return Err(cancelled());}
  for e in fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))? {
   if failed.load(Ordering::Acquire){return Err(cancelled());}
   let e=e?;let name=CString::new(e.file_name().as_bytes()).map_err(|_|bad())?;
   let p=path.join(e.file_name());
   if heavy.contains(&p){let c=open_child(f,&name)?;let m=c.metadata()?;valid(&m,dev)?;
    if !m.is_dir() || depth+1>256{return Err(bad());}
    records.push((p.clone(),m.ino()));dispatch(&c,&p,dev,depth+1,heavy,tx,failed,records)?;
   }else{tx.send((f.try_clone()?,name,depth+1)).map_err(|_|bad())?;}
  }Ok(())
 }
 let(tx,rx)=mpsc::sync_channel::<Job>(32);let rx=Mutex::new(rx);let failed=AtomicBool::new(false);
 let mut records=Vec::new();
 let workers=8;
 let mut total=std::thread::scope(|scope|->io::Result<u64>{
  let mut handles=Vec::new();let mut failure=None;
  for _ in 0..workers{let rx=&rx;let failed=&failed;
   match std::thread::Builder::new().spawn_scoped(scope,move||->io::Result<u64>{
    let mut count=0;let mut error=None;
    loop{let job=rx.lock().map_err(|_|bad())?.recv();let Ok((f,name,depth))=job else{break;};
     if failed.load(Ordering::Acquire){continue;}
     match visit(&f,&name,dev,depth,failed){Ok(n)=>count+=n,Err(e)=>{failed.store(true,Ordering::Release);merge_error(&mut error,e);}}
    }match error{Some(e)=>Err(e),None=>Ok(count)}
   }){Ok(h)=>handles.push(h),Err(e)=>{failed.store(true,Ordering::Release);failure=Some(e);break;}}
  }
  if failure.is_none(){failure=dispatch(root,Path::new(""),dev,0,heavy,&tx,&failed,&mut records).err();}
  if failure.is_some(){failed.store(true,Ordering::Release);}drop(tx);let mut count=0;
  for h in handles{match h.join(){Ok(Ok(n))=>count+=n,Ok(Err(e))=>{merge_error(&mut failure,e);},Err(_)=>{merge_error(&mut failure,bad());}}}
  if let Some(e)=failure{Err(e)}else{Ok(count)}
 })?;
 // Every boundary job has completed. Heavy directories are now removed in
 // reverse preorder; each open is relative to the original pinned root.
 let identities:std::collections::HashMap<_,_>=records.iter().cloned().collect();
 for(path,ino) in records.iter().rev(){
  let mut parent=root.try_clone()?;let mut prefix=std::path::PathBuf::new();
  let components:Vec<_>=path.components().collect();
  for c in &components[..components.len()-1]{
   prefix.push(c.as_os_str());let name=CString::new(c.as_os_str().as_bytes()).map_err(|_|bad())?;
   parent=open_child(&parent,&name)?;let m=parent.metadata()?;valid(&m,dev)?;
   if !m.is_dir() || identities.get(&prefix)!=Some(&m.ino()){return Err(bad());}
  }
  let name=CString::new(path.file_name().ok_or_else(bad)?.as_bytes()).map_err(|_|bad())?;
  let f=open_child(&parent,&name)?;let m=f.metadata()?;
  if !m.is_dir() || m.dev()!=dev || m.ino()!=*ino{return Err(bad());}
  let entry_path=Path::new(&format!("/proc/self/fd/{}",parent.as_raw_fd())).join(std::ffi::OsStr::from_bytes(name.as_bytes()));
  let entry=fs::symlink_metadata(entry_path)?;
  if entry.dev()!=m.dev() || entry.ino()!=m.ino() || entry.mode()!=m.mode(){return Err(bad());}
  if unsafe{unlinkat(parent.as_raw_fd(),name.as_ptr(),0x200)}!=0{return Err(io::Error::last_os_error());}total+=1;
 }
 println!("INTERNAL_CLEAR_POOL_OK workers={workers} heavy={} removed={total}",records.len());Ok(total+1)
}

fn package_valid(name:&str)->bool {
 name.contains('.') && name.as_bytes().first().is_some_and(|b|b.is_ascii_alphabetic())
 && !name.ends_with('.') && !name.contains("..")
 && name.bytes().all(|b|b.is_ascii_alphanumeric() || b==b'.' || b==b'_')
}
fn no_mounts(root:&Path)->io::Result<()> {
 // mountinfo escapes space, tab, newline and backslash. App root components
 // contain none of these, so comparison of the escaped prefix is exact.
 let text=fs::read_to_string("/proc/self/mountinfo")?;
 for line in text.lines(){
  let mount=line.split_whitespace().nth(4).ok_or_else(bad)?;
  if Path::new(mount).starts_with(root){return Err(io::Error::other("INTERNAL_MOUNT_REFUSED"));}
 }Ok(())
}
fn run(args:&[String])->io::Result<()> {
 let start=Instant::now();if args.len()!=4{return Err(bad());}
 let uid=args[1].parse::<u32>().map_err(|_|bad())?;
 let kind=&args[2];let pkg=&args[3];
 // System/shared service UIDs are intentionally outside this app-only command.
 if uid%100000<10000 || uid%100000>=90000 || uid>i32::MAX as u32 || !matches!(kind.as_str(),"user"|"user_de") || !package_valid(pkg){return Err(bad());}
 let parent=std::path::PathBuf::from(format!("/data/{kind}/{}",uid/100000));
 let expected=parent.join(pkg);if args[0].as_bytes()!=expected.as_os_str().as_bytes(){return Err(bad());}
 let canonical_parent=fs::canonicalize(&parent)?;
 if canonical_parent!=parent && !(kind=="user" && uid/100000==0 && canonical_parent==Path::new("/data/data")){return Err(bad());}
 let root=canonical_parent.join(pkg);
 no_mounts(&root)?;no_mounts(&expected)?;
 let parent_fd=OpenOptions::new().read(true).custom_flags(FLAGS|speedbackup_native_rs::O_DIRECTORY_NATIVE).open(&canonical_parent)?;
 let parent_before=parent_fd.metadata()?;
 if fs::read_link(format!("/proc/self/fd/{}",parent_fd.as_raw_fd()))?!=canonical_parent{return Err(bad());}
 let name=CString::new(pkg.as_bytes()).map_err(|_|bad())?;
 let entry=match entry_stat(&parent_fd,&name){Ok(e)=>e,Err(e) if e.kind()==io::ErrorKind::NotFound=>{
  println!("INTERNAL_TREE_CLEAR_OK absent=true removed=0 workers=0");return Ok(());
 },Err(e)=>return Err(e)};
 if !entry.is_dir(){return Err(bad());}
 let f=open_child(&parent_fd,&name)?;let before=f.metadata()?;
 if !entry.matches(&before) || before.uid()!=uid || before.dev()!=parent_before.dev() || !before.is_dir(){return Err(bad());}
 let identity=|m:&fs::Metadata| (m.dev(),m.ino(),m.uid(),m.gid(),m.mode());
 let check_root=||->io::Result<()> {
  if fs::canonicalize(&parent)?!=canonical_parent || fs::read_link(format!("/proc/self/fd/{}",f.as_raw_fd()))?!=root{return Err(bad());}
  let p=fs::metadata(&canonical_parent)?;if p.dev()!=parent_before.dev() || p.ino()!=parent_before.ino(){return Err(bad());}
  let now=open_child(&parent_fd,&name)?.metadata()?;
  if identity(&now)!=identity(&before){return Err(bad());}Ok(())
 };
 check_root()?;
 let empty=fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))?.next().transpose()?.is_none();
 let (checked,heap,depth)=if empty{(1,Heap::new(),0)}else{parallel_plan(&f,before.dev())?};
 fd_budget(depth)?;check_root()?;no_mounts(&root)?;no_mounts(&expected)?;
 if !entry_stat(&f,&CString::new(".").unwrap())?.matches(&f.metadata()?){return Err(bad());}
 let threshold=(checked/32).max(MIN_HEAVY);
 let heavy=heap.into_iter().filter(|x|(x.0).0>=threshold).map(|x|(x.0).1).collect();
 let check_ms=start.elapsed().as_millis();
 let removed=if empty{1}else{clear_scheduled(&f,before.dev(),&heavy)?};
 if removed!=checked{return Err(bad());}
 check_root()?;no_mounts(&root)?;no_mounts(&expected)?;
 if fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))?.next().transpose()?.is_some(){return Err(bad());}
 println!("INTERNAL_TREE_CLEAR_OK checked={checked} removed={} checkMs={check_ms} clearMs={} elapsedMs={} workers={} rootPreserved=true",removed-1,start.elapsed().as_millis()-check_ms,start.elapsed().as_millis(),if empty{0}else{8});
 Ok(())
}
pub fn quiet_command(args:&[String])->i32 {
 if args.len()!=4 { return 64; }
 let uid=match args[1].parse::<u32>() { Ok(v)=>v, Err(_)=>return 64 };
 let pkg=&args[3];
 if pkg.is_empty() || !pkg.contains('.') || !pkg.bytes().all(|b| b.is_ascii_alphanumeric() || b==b'.' || b==b'_') { return 64; }
 let user=uid/100000;
 let begin=std::time::Instant::now();
 let before=crate::procwait::wait_scan_gone("pkg",pkg,1000,120,user);
 if before!=0 { eprintln!("INTERNAL_QUIET_FAILED phase=before rc={before}"); return before; }
 let pre_ms=begin.elapsed().as_millis();
 let rc=command(args);
 if rc!=0 { return rc; }
 let clear_ms=begin.elapsed().as_millis()-pre_ms;
 let after=crate::procwait::wait_scan_gone("pkg",pkg,1000,120,user);
 eprintln!("INTERNAL_QUIET_DONE rc={after} beforeMs={pre_ms} clearMs={clear_ms} afterMs={} stableMs=120",begin.elapsed().as_millis()-pre_ms-clear_ms);
 after
}
pub fn command(args:&[String])->i32 {
 match run(args){Ok(())=>0,Err(e)=>{eprintln!("INTERNAL_TREE_FAILED error={e} partialChangesPossible=true");1}}
}
