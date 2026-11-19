//! Conservative ancestor identity probe: inaccessible or changing processes never authorize.
use std::{fs,io,path::PathBuf};
use std::os::unix::{fs::MetadataExt,ffi::OsStrExt};
fn bad()->io::Error {io::Error::other("unverified terminal ancestry")}
fn termux(bytes:&[u8])->bool {bytes.windows(10).any(|v|v==b"com.termux")}
fn identity(root:&std::path::Path)->io::Result<(u32,u64,u32)> {
 let stat=fs::read_to_string(root.join("stat"))?;
 let tail=speedbackup_native_rs::proc_stat::split(&stat).ok_or_else(bad)?.1.split_whitespace().collect::<Vec<_>>();
 let parent=tail.get(1).ok_or_else(bad)?.parse().map_err(|_|bad())?;
 let start=tail.get(19).ok_or_else(bad)?.parse().map_err(|_|bad())?;
 let status=fs::read_to_string(root.join("status"))?;
 let uid=status.lines().find_map(|l|l.strip_prefix("Uid:")).and_then(|l|l.split_whitespace().next()).ok_or_else(bad)?.parse().map_err(|_|bad())?;
 Ok((parent,start,uid))
}
// /proc resolves user 0's /data/user/0 alias to /data/data on many ROMs.
// This recognizes only the two known MT executable layouts; ownership and
// live executable inode checks below remain mandatory.
fn mtio_user(exe:&str)->Option<u32> {
 let fields=exe.split('/').collect::<Vec<_>>();
 match fields.as_slice() {
  ["","data","data",pkg,"files","mtio"] if matches!(*pkg,"bin.mt.plus"|"bin.mt.plus.canary")=>Some(0),
  ["","data","user",user,pkg,"files","mtio"] if matches!(*pkg,"bin.mt.plus"|"bin.mt.plus.canary")=>user.parse().ok(),
  _=>None,
 }
}
// A detached console remembers only a verified launch. Authenticate its answer
// by kernel peer PID, then require that exact live process in our ancestor walk.
fn console_origin()->Option<(u32,u64)> {
 let dir=std::env::var_os("SPEEDBACKUP_CONSOLE_DIR")?;
 console_origin_at(&PathBuf::from(dir).join("control"))
}
fn console_origin_at(path:&std::path::Path)->Option<(u32,u64)> {
 use std::{io::{Read,Write},net::Shutdown,os::{fd::AsRawFd,unix::net::UnixStream},time::Duration};
 let mut socket=UnixStream::connect(path).ok()?;
 socket.set_read_timeout(Some(Duration::from_secs(1))).ok()?;
 socket.set_write_timeout(Some(Duration::from_secs(1))).ok()?;
 unsafe extern "C" {fn getsockopt(fd:i32,l:i32,o:i32,v:*mut std::ffi::c_void,n:*mut u32)->i32;}
 let mut cred=[0u32;3];let mut len=12u32;
 if unsafe{getsockopt(socket.as_raw_fd(),1,17,cred.as_mut_ptr().cast(),&mut len)}!=0||len!=12||cred[1]!=0{return None;}
 let root=PathBuf::from(format!("/proc/{}",cred[0]));let before=identity(&root).ok()?;
 // The applet may run from the per-job copy; compare against the pinned
 // supervisor executable inherited by the worker, not that applet's inode.
 let executable=std::env::var_os("SPEEDBACKUP_NATIVE_EXE").map(PathBuf::from).or_else(||std::env::current_exe().ok())?;
 let own=fs::metadata(executable).ok()?;let peer=fs::metadata(root.join("exe")).ok()?;
 if own.uid()!=0||own.mode()&0o022!=0||own.dev()!=peer.dev()||own.ino()!=peer.ino(){return None;}
 socket.write_all(b"TERMINAL_HOST\n").ok()?;socket.shutdown(Shutdown::Write).ok()?;
 let mut answer=String::new();socket.take(8).read_to_string(&mut answer).ok()?;
 if answer!="1"||identity(&root).ok()?!=before{return None;}
 Some((cred[0],before.1))
}
pub(super) fn capture()->bool {probe(std::process::id(),None).unwrap_or(false)}
fn probe(mut pid:u32,console:Option<(u32,u64)>)->io::Result<bool>{
 if std::env::var_os("TERMUX_VERSION").is_some_and(|v|!v.is_empty()){return Ok(false);}
 for key in ["PREFIX","PATH","LD_LIBRARY_PATH","LD_PRELOAD","SPEEDBACKUP_CALLER_PATH"]{
  if std::env::var_os(key).is_some_and(|s|termux(s.as_os_str().as_bytes())){return Ok(false);}
 }
 for _ in 0..32 {
  if pid<=1 {return Ok(false);}
  let root=PathBuf::from(format!("/proc/{pid}"));let before=identity(&root)?;
  let comm=fs::read_to_string(root.join("comm"))?;
  if termux(comm.as_bytes()){return Ok(false);}
  for key in ["exe","cwd"]{if termux(fs::read_link(root.join(key))?.as_os_str().as_bytes()){return Ok(false);}}
  if termux(&fs::read(root.join("maps"))?){return Ok(false);}
  for (n,entry) in fs::read_dir(root.join("fd"))?.enumerate(){
   if n>=65536{return Err(bad());}let path=entry?.path();
   match fs::read_link(&path){
    Ok(p)=>if termux(p.as_os_str().as_bytes()){return Ok(false);},
    Err(e) if e.kind()==io::ErrorKind::NotFound=>match fs::symlink_metadata(path){Err(e)if e.kind()==io::ErrorKind::NotFound=>{},_=>return Err(bad())},
    Err(e)=>return Err(e)
   }
  }
  let command=fs::read(root.join("cmdline"))?;
  let package=command.split(|b|*b==0).next().and_then(|s|std::str::from_utf8(s).ok()).filter(|s|matches!(*s,"bin.mt.plus"|"bin.mt.plus.canary"));
  let mut verified=false;
  match package.unwrap_or(comm.trim_end_matches('\n')) {
   "mtio" if before.2==0=>{
    let exe=fs::read_link(root.join("exe"))?;let text=exe.to_str().ok_or_else(bad)?;
    let Some(user)=mtio_user(text) else{return Ok(false);};
    let dir=exe.parent().and_then(|p|p.parent()).ok_or_else(bad)?;
    let installed=fs::symlink_metadata(&exe)?;let app=fs::symlink_metadata(dir)?;let live=fs::metadata(root.join("exe"))?;
    verified=installed.is_file()&&app.is_dir()&&installed.ino()==live.ino()&&installed.dev()==live.dev()&&installed.uid()==app.uid()&&app.uid()>=10000&&app.uid()/100000==user;
   },
   "bin.mt.plus"|"bin.mt.plus.canary"=>{
    let dir=fs::symlink_metadata(format!("/data/user/{}/{}",before.2/100000,package.unwrap_or(comm.trim_end_matches('\n'))))?;
    verified=dir.is_dir()&&before.2>=10000&&dir.uid()==before.2;
   },_=>{}
  }
  if identity(&root)?!=before{return Err(bad());}
  if verified||console==Some((pid,before.1)){return Ok(true);}pid=before.0;
 }
 Ok(false)
}
pub(super) fn run(args:&[String])->i32{
 let safe=args.first().filter(|_|args.len()==1).and_then(|s|s.parse().ok()).and_then(|pid|probe(pid,console_origin()).ok()).unwrap_or(false);
 println!("{}",u8::from(safe));0
}

#[cfg(test)] mod tests {
 use super::*;
 #[test] fn console_child_probe() {
  let Some(path)=std::env::var_os("SB_TEST_CONSOLE_ORIGIN") else{return;};
  let origin=console_origin_at(std::path::Path::new(&path)).unwrap();
  let accepted=probe(std::process::id(),Some(origin)).unwrap();
  assert_eq!(accepted,std::env::var_os("TERMUX_VERSION").is_none());
  // A live endpoint alone must not authorize an unrelated ancestry walk.
  assert!(!probe(1,Some(origin)).unwrap());
  assert!(!probe(std::process::id(),Some((origin.0,origin.1+1))).unwrap());
 }
 #[test] #[ignore = "requires root on Android/Linux; run with --include-ignored"]
 fn detached_worker_uses_live_ancestor_but_termux_environment_stays_protected() {
  use std::{io::{Read,Write},os::unix::net::UnixListener,process::Command};
  let base=std::env::temp_dir().join(format!("sb-terminal-child-{}",std::process::id()));fs::create_dir_all(&base).unwrap();
  for termux in [false,true] {
   let path=base.join(if termux{"termux"}else{"mt"});let listener=UnixListener::bind(&path).unwrap();
   let thread=std::thread::spawn(move||{let (mut c,_)=listener.accept().unwrap();let mut request=String::new();c.read_to_string(&mut request).unwrap();assert_eq!(request,"TERMINAL_HOST\n");c.write_all(b"1").unwrap();});
   let mut cmd=Command::new(std::env::current_exe().unwrap());cmd.args(["--exact","speedscan::terminal_host::tests::console_child_probe","--nocapture"]).env("SB_TEST_CONSOLE_ORIGIN",&path);
   if termux {cmd.env("TERMUX_VERSION","test");}else{cmd.env_remove("TERMUX_VERSION");}
   let status=cmd.status().unwrap();thread.join().unwrap();assert!(status.success());fs::remove_file(path).unwrap();
  }
  fs::remove_dir(base).unwrap();
 }
 #[test] #[ignore = "requires root on Android/Linux; run with --include-ignored"]
 fn console_origin_authenticates_live_peer_and_exact_positive_reply() {
  use std::{io::{Read,Write},os::unix::net::UnixListener};
  let base=std::env::temp_dir().join(format!("sb-terminal-host-{}",std::process::id()));
  fs::create_dir_all(&base).unwrap();
  for (i,reply) in ["1","0","ERROR command","11",""].iter().enumerate() {
   let path=base.join(i.to_string());let listener=UnixListener::bind(&path).unwrap();
   let reply=reply.to_string();let positive=reply=="1";
   let thread=std::thread::spawn(move||{let (mut c,_)=listener.accept().unwrap();let mut request=String::new();c.read_to_string(&mut request).unwrap();assert_eq!(request,"TERMINAL_HOST\n");let _=c.write_all(reply.as_bytes());});
   let result=console_origin_at(&path);thread.join().unwrap();
   let id=identity(&PathBuf::from(format!("/proc/{}",std::process::id()))).unwrap();
   assert_eq!(result,positive.then_some((std::process::id(),id.1)));
   fs::remove_file(path).unwrap();
  }
  assert_eq!(console_origin_at(&base.join("missing")),None);
  fs::remove_dir(base).unwrap();
 }
 #[test] fn resolved_primary_user_mtio_and_secondary_user_paths() {
  assert_eq!(mtio_user("/data/data/bin.mt.plus/files/mtio"),Some(0));
  assert_eq!(mtio_user("/data/data/bin.mt.plus.canary/files/mtio"),Some(0));
  assert_eq!(mtio_user("/data/user/0/bin.mt.plus/files/mtio"),Some(0));
  assert_eq!(mtio_user("/data/user/10/bin.mt.plus/files/mtio"),Some(10));
 }
 #[test] fn other_executables_and_malformed_mtio_paths_are_rejected() {
  for path in ["/data/data/com.termux/files/mtio","/data/data/bin.mt.plus/files/mtio (deleted)","/data/data/bin.mt.plus/files/other","/data/user/x/bin.mt.plus/files/mtio","/data/user/0/bin.mt.plus/../files/mtio","data/data/bin.mt.plus/files/mtio"] {assert_eq!(mtio_user(path),None,"{path}");}
 }
}
