// SPDX-License-Identifier: GPL-3.0-only
// Exact vold roots only. The stopped-app/stable-tree contract is unchanged.
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
fn bad()->io::Error{io::Error::other("Unsafe or changed external clear tree")}
#[derive(Debug)]
struct SiblingCancelled;
impl std::fmt::Display for SiblingCancelled {fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{write!(f,"Sibling cancelled")}}
impl std::error::Error for SiblingCancelled {}
fn cancelled()->io::Error{io::Error::other(SiblingCancelled)}
fn is_cancelled(e:&io::Error)->bool{e.get_ref().is_some_and(|x|x.is::<SiblingCancelled>())}
fn merge_error(old:&mut Option<io::Error>,new:io::Error){if old.as_ref().map_or(true,|e|is_cancelled(e) && !is_cancelled(&new)){*old=Some(new);}}
fn valid(m:&fs::Metadata,dev:u64)->io::Result<()> {
 if m.dev()!=dev || (!m.is_dir() && (!m.is_file() || m.nlink()!=1)){return Err(bad());}Ok(())
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
 fn valid(&self,dev:u64)->io::Result<()>{if self.dev!=dev || (!self.is_dir() && (self.mode&0o170000!=0o100000 || self.nlink!=1)){return Err(bad());}Ok(())}
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
fn scan(f:&File,dev:u64,depth:usize,path:&Path,heap:&mut Heap,collect:bool,max_depth:&mut usize)->io::Result<u64>{
 if depth>256{return Err(bad());} *max_depth=(*max_depth).max(depth);let m=f.metadata()?; valid(&m,dev)?;
 if !m.is_dir(){return Err(bad());}let mut n=1;
 for e in fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))? {
  let e=e?;let name=CString::new(e.file_name().as_bytes()).map_err(|_|bad())?;
  let m=fs::symlink_metadata(e.path())?;valid(&m,dev)?;
  if depth+1>256{return Err(bad());}*max_depth=(*max_depth).max(depth+1);
  if m.is_dir(){let c=open_child(f,&name)?;let cm=c.metadata()?;
   if cm.dev()!=m.dev() || cm.ino()!=m.ino(){return Err(bad());}
   n+=scan(&c,dev,depth+1,&path.join(e.file_name()),heap,collect,max_depth)?;
  }else{n+=1;}
 }
 if collect && (heap.len()<8224 || heap.peek().is_some_and(|x|n>(x.0).0)){
  heap.push(std::cmp::Reverse((n,path.to_path_buf())));if heap.len()>8224{heap.pop();}
 }Ok(n)
}

// Read-only preflight. Bounded work sharing reaches deep/skewed trees without
// keeping an unbounded list of paths or allowing mutation during validation.
fn parallel_check(root:&File,dev:u64)->io::Result<u64>{
 use std::collections::VecDeque;
 use std::sync::Condvar;
 type Job=(File,CString,usize);
 struct State { queue:VecDeque<Job>, active:usize, error:Option<io::Error>, count:u64 }
 fn visit_check(parent:&File,name:&CString,depth:usize,dev:u64,shared:&(Mutex<State>,Condvar))->io::Result<u64>{
  if depth>256{return Err(bad());}
  if shared.0.lock().map_err(|_|bad())?.error.is_some(){return Err(cancelled());}
  let path=Path::new(&format!("/proc/self/fd/{}",parent.as_raw_fd())).join(std::ffi::OsStr::from_bytes(name.as_bytes()));
  let m=fs::symlink_metadata(path)?;valid(&m,dev)?;
  if !m.is_dir(){return Ok(1);}
  let child=open_child(&parent,&name)?;let cm=child.metadata()?;valid(&cm,dev)?;
  if !cm.is_dir() || cm.ino()!=m.ino() || cm.dev()!=m.dev(){return Err(bad());}
  let mut count=1;
  for entry in fs::read_dir(format!("/proc/self/fd/{}",child.as_raw_fd()))? {
   let name=CString::new(entry?.file_name().as_bytes()).map_err(|_|bad())?;
   let mut state=shared.0.lock().map_err(|_|bad())?;
   if state.error.is_some(){return Err(cancelled());}
   if state.queue.len()<32 {state.queue.push_back((child.try_clone()?,name,depth+1));shared.1.notify_one();}
   else {drop(state);count+=visit_check(&child,&name,depth+1,dev,shared)?;}
  }Ok(count)
 }
 let m=root.metadata()?;valid(&m,dev)?;if !m.is_dir(){return Err(bad());}
 let shared=(Mutex::new(State{queue:VecDeque::new(),active:1,error:None,count:1}),Condvar::new());
 std::thread::scope(|scope|->io::Result<u64>{
  let mut handles=Vec::new();
  for _ in 0..7 {
   let shared=&shared;
   match std::thread::Builder::new().spawn_scoped(scope,move|| {
    loop {
     let mut state=shared.0.lock().unwrap();
     while state.queue.is_empty() && state.active>0 && state.error.is_none(){state=shared.1.wait(state).unwrap();}
     if state.error.is_some() || (state.queue.is_empty() && state.active==0){break;}
     let job=state.queue.pop_front().unwrap();state.active+=1;drop(state);
     let result=visit_check(&job.0,&job.1,job.2,dev,shared);
     let mut state=shared.0.lock().unwrap();state.active-=1;
     match result{Ok(n)=>state.count+=n,Err(e)=>merge_error(&mut state.error,e)}
     shared.1.notify_all();
    }
   }){Ok(h)=>handles.push(h),Err(e)=>{shared.0.lock().unwrap().error=Some(e);break;}}
  }
  let dispatched=(||->io::Result<u64>{
   let mut count=0;
   for entry in fs::read_dir(format!("/proc/self/fd/{}",root.as_raw_fd()))? {
    let name=CString::new(entry?.file_name().as_bytes()).map_err(|_|bad())?;
    let mut state=shared.0.lock().map_err(|_|bad())?;
    if state.error.is_some(){return Err(cancelled());}
    if state.queue.len()<32 {state.queue.push_back((root.try_clone()?,name,1));shared.1.notify_one();}
    else {drop(state);count+=visit_check(root,&name,1,dev,&shared)?;}
   }Ok(count)
  })();
  {let mut state=shared.0.lock().unwrap();state.active-=1;
   match dispatched{Ok(n)=>state.count+=n,Err(e)=>merge_error(&mut state.error,e)}shared.1.notify_all();}
  for h in handles{if h.join().is_err(){let mut state=shared.0.lock().unwrap();merge_error(&mut state.error,bad());}}
  let mut state=shared.0.lock().unwrap();state.queue.clear();
  match state.error.take(){Some(e)=>Err(e),None=>Ok(state.count)}
 })
}

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
 println!("EXTERNAL_CLEAR_POOL_OK workers={workers} heavy={} removed={total}",records.len());Ok(total+1)
}
fn run(args:&[String],clear:bool)->io::Result<()>{
 let start=Instant::now();if args.len()!=3{return Err(bad());}
 let uid=args[1].parse::<u32>().map_err(|_|bad())?;
 if uid%100000<10000 || uid>i32::MAX as u32 || !matches!(args[2].as_str(),"data"|"obb"){return Err(bad());}
 let root=Path::new(&args[0]);let parent=format!("/data/media/{}/Android/{}",uid/100000,args[2]);
 let name=root.file_name().ok_or_else(bad)?.as_bytes();
 if root.parent()!=Some(Path::new(&parent)) || !name.contains(&b'.') || !name.iter().all(|c|c.is_ascii_alphanumeric() || *c==b'.' || *c==b'_'){return Err(bad());}
 // canonicalize the existing ancestors even when the package root is absent.
 let mut ancestor=root;
 loop{match fs::symlink_metadata(ancestor){Ok(m)=>{if !m.is_dir() || fs::canonicalize(ancestor)?!=ancestor{return Err(bad());}break;},Err(e) if e.kind()==io::ErrorKind::NotFound=>{ancestor=ancestor.parent().ok_or_else(bad)?;},Err(e)=>return Err(e)}}
 let open=||OpenOptions::new().read(true).custom_flags(FLAGS|speedbackup_native_rs::O_DIRECTORY_NATIVE).open(root);
 let f=match open(){Ok(f)=>f,Err(e) if !clear && e.kind()==io::ErrorKind::NotFound=>{println!("EXTERNAL_TREE_CHECK_OK absent=true");return Ok(());},Err(e)=>return Err(e)};
 let before=f.metadata()?;if before.dev()!=fs::metadata(root.parent().ok_or_else(bad)?)?.dev(){return Err(bad());}
 if fs::read_link(format!("/proc/self/fd/{}",f.as_raw_fd()))?!=root{return Err(bad());}
 // An empty pinned root has no child work to parallelize. Errors must not be
 // mistaken for emptiness. Clear still rechecks budget, root identity/uid and
 // final emptiness below; nothing is deleted on this path.
 valid(&before,before.dev())?;
 let empty=fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))?.next().transpose()?.is_none();
 let mut heap=Heap::new();let mut max_depth=0;let (checked,check_workers)=if empty {(1,0)} else if clear {
  match parallel_plan(&f,before.dev()){
   Ok((n,h,d))=>{heap=h;max_depth=d;(n,8)},
   // A failed plan is discarded in full before retry; no deletion has begun.
   Err(e) if e.raw_os_error()==Some(24)=>{
    eprintln!("EXTERNAL_PLAN_RETRY reason=EMFILE workers=1");
    (scan(&f,before.dev(),0,Path::new(""),&mut heap,true,&mut max_depth)?,1)
   },Err(e)=>return Err(e)
  }
 } else {
  match parallel_check(&f,before.dev()) {
   Ok(n)=>(n,8),
   // All workers and queued fds have been reaped before this read-only retry.
   // Preserve the serial check's acceptance under scarce fd limits.
   Err(e) if e.raw_os_error()==Some(24)=>{
    eprintln!("EXTERNAL_CHECK_RETRY reason=EMFILE workers=1");
    (scan(&f,before.dev(),0,Path::new(""),&mut heap,false,&mut max_depth)?,1)
   },Err(e)=>return Err(e)
  }
 };
 let threshold=(checked/32).max(MIN_HEAVY);let heavy=heap.into_iter().filter(|x|(x.0).0>=threshold).map(|x|(x.0).1).collect();
 let check_ms=start.elapsed().as_millis();
 if clear{
  fd_budget(max_depth)?;
  if fs::read_link(format!("/proc/self/fd/{}",f.as_raw_fd()))?!=root{return Err(bad());}
  let now=open()?.metadata()?;if now.dev()!=before.dev() || now.ino()!=before.ino() || now.uid()!=uid{return Err(bad());}
  // Cross-check the native layout once before any deletion; fail closed.
  if checked>1 && !entry_stat(&f,&CString::new(".").unwrap())?.matches(&f.metadata()?){return Err(bad());}
  let clear_workers=if checked==1{0}else{8};
  let removed=if checked==1{println!("EXTERNAL_CLEAR_POOL_OK workers=0 heavy=0 removed=0");1}else{clear_scheduled(&f,before.dev(),&heavy)?};
  if removed!=checked{return Err(bad());}
  let after=open()?.metadata()?;if after.dev()!=before.dev() || after.ino()!=before.ino(){return Err(bad());}
  if fs::read_dir(format!("/proc/self/fd/{}",f.as_raw_fd()))?.next().is_some(){return Err(bad());}
  println!("EXTERNAL_TREE_CLEAR_OK checked={checked} removed={} checkMs={check_ms} clearMs={} elapsedMs={} workers={clear_workers} checkWorkers={check_workers}",removed-1,start.elapsed().as_millis()-check_ms,start.elapsed().as_millis());
 }else{println!("EXTERNAL_TREE_CHECK_OK checked={checked} elapsedMs={} workers={check_workers}",start.elapsed().as_millis());}
 Ok(())
}
pub fn command(args:&[String],clear:bool)->i32{match run(args,clear){Ok(())=>0,Err(e)=>{eprintln!("EXTERNAL_TREE_FAILED clear={clear} error={e} partialChangesPossible={clear}");1}}}

#[cfg(test)]
mod plan_tests {
 use super::*;
 #[test]
 fn parallel_plan_matches_serial_subtree_oracle(){
  let path=std::path::PathBuf::from(format!("/data/local/tmp/sb-plan897-unit-{}",std::process::id()));
  fs::create_dir(&path).unwrap();
  struct Cleanup(std::path::PathBuf);
  impl Drop for Cleanup{fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}
  let _cleanup=Cleanup(path.clone());
  // Many pruned empty directories, skew, deep ancestors, and boundary sizes.
  for i in 0..8300{fs::create_dir(path.join(format!("empty{i}"))).unwrap();}
  for (i,n) in [254,255,256,257,2048].iter().enumerate(){
   let p=path.join(format!("skew/nested/d{i}"));fs::create_dir_all(&p).unwrap();
   for j in 0..*n{fs::write(p.join(format!("f{j}")),b"x").unwrap();}
  }
  let deep=path.join(std::iter::repeat("d").take(128).collect::<Vec<_>>().join("/"));fs::create_dir_all(deep).unwrap();
  let root=File::open(&path).unwrap();let dev=root.metadata().unwrap().dev();
  let mut expected=Heap::new();let mut expected_depth=0;
  let expected_count=scan(&root,dev,0,Path::new(""),&mut expected,true,&mut expected_depth).unwrap();
  let threshold=(expected_count/32).max(256);
  let significant=|heap:Heap|->std::collections::BTreeSet<_>{heap.into_iter().filter(|x|(x.0).0>=threshold).collect()};
  let expected=significant(expected);
  for _ in 0..20{
   let (count,heap,depth)=parallel_plan(&root,dev).unwrap();
   assert_eq!(count,expected_count);assert_eq!(depth,expected_depth);assert_eq!(significant(heap),expected);
  }
  drop(root);
  fs::remove_dir_all(&path).unwrap();fs::create_dir(&path).unwrap();
  // Deterministic varied topology, repeated scheduling; compare every retained
  // directory count as well as total/depth, not merely the deletion result.
  let mut random=896u64;
  for shape in 0..10{
   let p=path.join(format!("random{shape}"));fs::create_dir(&p).unwrap();let mut dirs=vec![p.clone()];
   for i in 0..800{
    random=random.wrapping_mul(6364136223846793005).wrapping_add(1);
    let parent=&dirs[(random as usize)%dirs.len()];let child=parent.join(format!("n{i}"));
    if random&3==0{fs::write(child,b"x").unwrap();}else{fs::create_dir(&child).unwrap();dirs.push(child);}
   }
   let root=File::open(&p).unwrap();let dev=root.metadata().unwrap().dev();let mut heap=Heap::new();let mut depth=0;
   let count=scan(&root,dev,0,Path::new(""),&mut heap,true,&mut depth).unwrap();let expected:std::collections::BTreeSet<_>=heap.into_iter().filter(|x|(x.0).0>=MIN_HEAVY).collect();
   for _ in 0..100{let (n,h,d)=parallel_plan(&root,dev).unwrap();assert_eq!(n,count);assert_eq!(d,depth);assert_eq!(h.into_iter().collect::<std::collections::BTreeSet<_>>(),expected);}
  }
  // Relative fd operations can traverse names whose full path exceeds PATH_MAX.
  let p=path.join("long");fs::create_dir(&p).unwrap();let root=File::open(p).unwrap();let mut current=root.try_clone().unwrap();
  for _ in 0..24{
   let child=Path::new(&format!("/proc/self/fd/{}",current.as_raw_fd())).join("n".repeat(240));
   fs::create_dir(&child).unwrap();current=File::open(child).unwrap();
  }
  // Ensure long-path nodes qualify for retention rather than only exercising
  // traversal/counting below the planning threshold.
  for i in 0..256{fs::write(format!("/proc/self/fd/{}/f{i}",current.as_raw_fd()),b"x").unwrap();}
  drop(current);let dev=root.metadata().unwrap().dev();let mut expected=Heap::new();let mut expected_depth=0;
  let expected_count=scan(&root,dev,0,Path::new(""),&mut expected,true,&mut expected_depth).unwrap();
  let (count,heap,depth)=parallel_plan(&root,dev).unwrap();assert_eq!(count,expected_count);assert_eq!(depth,expected_depth);
  assert_eq!(heap.into_iter().collect::<std::collections::BTreeSet<_>>(),expected.into_iter().filter(|x|(x.0).0>=MIN_HEAVY).collect());
  // 8671 qualifying directories exceed the real 8224-entry heap capacity.
  // Shared descendants make this possible without millions of fixture files.
  let p=path.join("eviction");fs::create_dir(&p).unwrap();
  for branch in 0..34{
   let mut leaf=p.join(format!("d{branch}"));
   for _ in 1..255{leaf=leaf.join("n");}
   fs::create_dir_all(&leaf).unwrap();
   for i in 0..if branch==33{1024}else{256}{fs::write(leaf.join(format!("f{i}")),b"x").unwrap();}
  }
  let root=File::open(&p).unwrap();let dev=root.metadata().unwrap().dev();let mut expected=Heap::new();let mut expected_depth=0;
  let expected_count=scan(&root,dev,0,Path::new(""),&mut expected,true,&mut expected_depth).unwrap();
  let threshold=(expected_count/32).max(MIN_HEAVY);
  let significant=|heap:Heap|->std::collections::BTreeSet<_>{heap.into_iter().filter(|x|(x.0).0>=threshold).collect()};
  let (count,heap,depth)=parallel_plan(&root,dev).unwrap();
  assert_eq!(count,expected_count);assert_eq!(depth,expected_depth);assert_eq!(heap.len(),8224);
  let paths:std::collections::BTreeSet<_>=heap.iter().map(|x|(x.0).1.clone()).collect();
  assert!(paths.contains(Path::new("")));
  for p in &paths{if !p.as_os_str().is_empty(){assert!(paths.contains(p.parent().unwrap()));}}
  assert_eq!(significant(heap),significant(expected));
 }
}

#[cfg(test)]
mod fdstat_tests {
 use super::*;
 use std::os::unix::{ffi::OsStringExt,fs::PermissionsExt};
 #[test]
 fn fd_relative_stat_matches_std(){
  let p=std::path::PathBuf::from(format!("/data/local/tmp/sb-fdstat899-unit-{}",std::process::id()));fs::create_dir(&p).unwrap();
  struct Cleanup(std::path::PathBuf);impl Drop for Cleanup{fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}let _cleanup=Cleanup(p.clone());
  let root=File::open(&p).unwrap();
  fn compare(f:&File,name:&std::ffi::OsStr){
   let name=CString::new(name.as_bytes()).unwrap();let m=entry_stat(f,&name).unwrap();
   let path=Path::new(&format!("/proc/self/fd/{}",f.as_raw_fd())).join(std::ffi::OsStr::from_bytes(name.as_bytes()));let std=fs::symlink_metadata(path).unwrap();
   assert_eq!((m.dev,m.ino,m.mode,m.nlink as u64),(std.dev(),std.ino(),std.mode(),std.nlink()));assert_eq!(m.valid(std.dev()).is_ok(),valid(&std,std.dev()).is_ok());assert!(m.valid(std.dev()^1).is_err());
  }
  fs::create_dir(p.join("dir")).unwrap();fs::write(p.join("file"),b"x").unwrap();fs::hard_link(p.join("file"),p.join("hard")).unwrap();
  std::os::unix::fs::symlink("file",p.join("link")).unwrap();std::os::unix::fs::symlink("absent",p.join("broken")).unwrap();
  extern "C"{fn mkfifo(path:*const c_char,mode:u32)->c_int;}
  let fifo=CString::new(p.join("fifo").as_os_str().as_bytes()).unwrap();assert_eq!(unsafe{mkfifo(fifo.as_ptr(),0o600)},0);
  for name in ["dir","file","hard","link","broken","fifo"]{compare(&root,std::ffi::OsStr::new(name));}
  fs::set_permissions(p.join("file"),fs::Permissions::from_mode(0o6751)).unwrap();compare(&root,std::ffi::OsStr::new("file"));
  fs::set_permissions(p.join("dir"),fs::Permissions::from_mode(0o3770)).unwrap();compare(&root,std::ffi::OsStr::new("dir"));
  let large=File::create(p.join("large")).unwrap();large.set_len(1u64<<33).unwrap();compare(&root,std::ffi::OsStr::new("large"));
  let longest="x".repeat(255);fs::write(p.join(&longest),b"x").unwrap();compare(&root,std::ffi::OsStr::new(&longest));
  let too_long=CString::new("x".repeat(256)).unwrap();assert_eq!(entry_stat(&root,&too_long).err().unwrap().raw_os_error(),Some(36));
  let file=File::open(p.join("file")).unwrap();assert_eq!(entry_stat(&file,&CString::new("child").unwrap()).err().unwrap().raw_os_error(),Some(20));
  fs::create_dir(p.join("deleted")).unwrap();let deleted=File::open(p.join("deleted")).unwrap();fs::remove_dir(p.join("deleted")).unwrap();compare(&deleted,std::ffi::OsStr::new("."));
  for i in (1..=64).filter(|i|*i!=47){let name=std::ffi::OsString::from_vec(vec![b'n',i,0xff]);fs::write(p.join(&name),b"x").unwrap();compare(&root,&name);}
  let absent=CString::new("absent").unwrap();assert_eq!(entry_stat(&root,&absent).err().unwrap().raw_os_error(),Some(2));
  let mut current=root.try_clone().unwrap();
  for _ in 0..24{let n="n".repeat(240);let path=Path::new(&format!("/proc/self/fd/{}",current.as_raw_fd())).join(&n);fs::create_dir(&path).unwrap();compare(&current,std::ffi::OsStr::new(&n));current=File::open(path).unwrap();}
 }
}
