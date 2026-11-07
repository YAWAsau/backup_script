//! Conservative ancestor identity probe: inaccessible or changing processes never authorize.
use std::{fs,io,path::PathBuf};
use std::os::unix::{fs::MetadataExt,ffi::OsStrExt};
fn bad()->io::Error {io::Error::other("unverified terminal ancestry")}
fn termux(bytes:&[u8])->bool {bytes.windows(10).any(|v|v==b"com.termux")}
fn identity(root:&std::path::Path)->io::Result<(u32,u64,u32)> {
 let stat=fs::read_to_string(root.join("stat"))?;
 let tail=stat.rsplit_once(") ").ok_or_else(bad)?.1.split_whitespace().collect::<Vec<_>>();
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
fn probe(mut pid:u32)->io::Result<bool>{
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
  if verified{return Ok(true);}pid=before.0;
 }
 Ok(false)
}
pub(super) fn run(args:&[String])->i32{
 let safe=args.first().filter(|_|args.len()==1).and_then(|s|s.parse().ok()).and_then(|pid|probe(pid).ok()).unwrap_or(false);
 println!("{}",u8::from(safe));0
}

#[cfg(test)] mod tests {
 use super::*;
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
