//! Publish generated regular files without truncating an existing FUSE inode.
//! Attributes are adjusted only on a fresh staging inode, never on user trees.
use std::{fs::{self, File, OpenOptions}, io::{self, Read, Seek, SeekFrom, Write},
    os::{fd::{IntoRawFd, AsRawFd}, unix::{fs::{MetadataExt, OpenOptionsExt}, ffi::OsStrExt}}, path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering}};
extern "C" { fn close(fd: i32) -> i32;
    fn fchown(fd:i32, uid:u32, gid:u32)->i32;
    fn fchmod(fd:i32, mode:u32)->i32;
    fn fgetxattr(fd:i32, name:*const i8, value:*mut std::ffi::c_void, size:usize)->isize;
    fn fremovexattr(fd:i32, name:*const i8)->i32;
    fn fsetxattr(fd:i32, name:*const i8, value:*const std::ffi::c_void, size:usize, flags:i32)->i32; }
fn checked_close(file: File) -> io::Result<()> {
    // Never retry close: an error can still release the descriptor.
    if unsafe { close(file.into_raw_fd()) } == 0 { Ok(()) }
    else { Err(io::Error::last_os_error()) }
}
struct Stage { path: PathBuf, identity: (u64,u64), armed: bool }
impl Stage {
    fn matches(&self) -> bool { fs::symlink_metadata(&self.path).map(|m|m.is_file() && (m.dev(),m.ino())==self.identity).unwrap_or(false) }
}
impl Drop for Stage { fn drop(&mut self) { if self.armed && self.matches() {let _ = fs::remove_file(&self.path);} } }
fn regular(path: &Path) -> io::Result<()> {
    if fs::symlink_metadata(path)?.is_file() { Ok(()) }
    else { Err(io::Error::other("regular file required; symlink rejected")) }
}
fn stamp(m: &fs::Metadata) -> (u64,u64,u64,i64,i64,i64,i64) {
    (m.dev(),m.ino(),m.len(),m.mtime(),m.mtime_nsec(),m.ctime(),m.ctime_nsec())
}
// Android arm64 layout checked against the NDK headers during the build.
#[repr(C)]
struct FsStat { kind:i64, block_size:i64, blocks:u64, free:u64, available:u64,
    files:u64, free_files:u64, fsid:[i32;2], name_len:i64, fragment_size:i64,
    flags:i64, spare:[i64;4] }
const _: () = assert!(std::mem::size_of::<FsStat>() == 120);
extern "C" { fn statfs(path:*const i8, result:*mut FsStat)->i32; }
fn auto_preserve(destination:&Path)->io::Result<bool> {
    let parent=destination.parent().filter(|p|!p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    let name=std::ffi::CString::new(parent.as_os_str().as_bytes())?;
    let mut info=std::mem::MaybeUninit::<FsStat>::uninit();
    if unsafe {statfs(name.as_ptr().cast(),info.as_mut_ptr())}!=0 {return Err(io::Error::last_os_error());}
    let kind=unsafe {info.assume_init()}.kind as u64;
    match kind {
        0x65735546|0x5dca2df5=>Ok(false), // FUSE, sdcardfs; esdfs remains unverified
        0xef53|0xf2f52010|0x01021994|0x794c7630=>Ok(true), // ext4, f2fs, tmpfs, overlayfs
        _=>{eprintln!("PUBLISH_FS_NATURAL magic={kind:x}");Ok(false)},
    }
}
fn attribute(file:&File, name:&[u8]) -> io::Result<Option<Vec<u8>>> {
    let mut value=vec![0u8;65536];
    let n=unsafe {fgetxattr(file.as_raw_fd(),name.as_ptr().cast(),value.as_mut_ptr().cast(),value.len())};
    if n<0 {let e=io::Error::last_os_error();return match e.raw_os_error() {Some(61)|Some(95)=>Ok(None),_=>Err(e)};}
    value.truncate(n as usize); Ok(Some(value))
}
fn preserve_stage(old:&File, stage:&File, mode:u32) -> io::Result<()> {
    let m=old.metadata()?;
    if unsafe {fchown(stage.as_raw_fd(),m.uid(),m.gid())}!=0 {return Err(io::Error::last_os_error());}
    // Preserve the access ACL and SELinux label of the existing ordinary file.
    for name in [b"system.posix_acl_access\0".as_slice(),b"security.selinux\0".as_slice()] {
        if let Some(value)=attribute(old,name)? {
            if attribute(stage,name)?.as_ref()!=Some(&value) && unsafe {fsetxattr(stage.as_raw_fd(),name.as_ptr().cast(),value.as_ptr().cast(),value.len(),0)}!=0 {
                return Err(io::Error::last_os_error());
            }
        } else if name==b"system.posix_acl_access\0" && attribute(stage,name)?.is_some() {
            if unsafe {fremovexattr(stage.as_raw_fd(),name.as_ptr().cast())}!=0 {return Err(io::Error::last_os_error());}
        }
    }
    if unsafe {fchmod(stage.as_raw_fd(),mode)}!=0 {return Err(io::Error::last_os_error());}
    Ok(())
}
pub fn publish(source: &Path, destination: &Path, mode: Option<u32>, preserve: bool, owner:Option<(u32,u32)>) -> io::Result<u64> {
    regular(source)?;
    // Linux/Android O_NOFOLLOW | O_NONBLOCK avoids racing into a symlink or FIFO.
    let mut input=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|0x800).open(source)?;
    if !input.metadata()?.is_file() {return Err(io::Error::other("source is not regular"));}
    let before=stamp(&input.metadata()?);
    match fs::symlink_metadata(destination) {
        Ok(m) if m.is_file() && ((m.dev(),m.ino()) != (before.0,before.1) || owner.is_some()) => (),
        Ok(_) => return Err(io::Error::other("destination must be a different regular file")),
        Err(e) if e.kind()==io::ErrorKind::NotFound => (),
        Err(e) => return Err(e),
    }
    let old = if preserve {
        match OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|0x800).open(destination) {
            Ok(f) if f.metadata()?.is_file()=>Some(f),
            Ok(_)=>return Err(io::Error::other("old destination is not regular")),
            Err(e) if e.kind()==io::ErrorKind::NotFound=>None,
            Err(e)=>return Err(e),
        }
    } else {None};
    let mode=match (mode,old.as_ref()) { (Some(m),_)=>m, (None,Some(f))=>f.metadata()?.mode()&0o777, _=>0o644 };
    let parent=destination.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
    static SEQ: AtomicU64=AtomicU64::new(0);
    let mut created=None;
    for _ in 0..64 {
        let name=format!(".speedbackup-publish-{}-{}",std::process::id(),SEQ.fetch_add(1,Ordering::Relaxed));
        let path=parent.join(name);
        match OpenOptions::new().write(true).create_new(true).mode(mode).open(&path) {
            Ok(f)=>{let m=f.metadata()?;created=Some((Stage{path,identity:(m.dev(),m.ino()),armed:true},f));break;},
            Err(e) if e.kind()==io::ErrorKind::AlreadyExists=>continue,
            Err(e)=>return Err(e),
        }
    }
    let (mut stage,mut output)=created.ok_or_else(||io::Error::other("stage names exhausted"))?;
    let mut buffer=[0u8;65536];
    let mut total=0;
    loop { let n=input.read(&mut buffer)?; if n==0 {break;} output.write_all(&buffer[..n])?;total+=n as u64; }
    if let Some(old)=old.as_ref() {preserve_stage(old,&output,mode)?;}
    else if preserve {
        // A new generated file addressed through the raw emulated-storage tree
        // inherits its immediate parent's uid/gid, not another user's Download.
        let resolved=fs::canonicalize(parent)?;
        if let Ok(rel)=resolved.strip_prefix("/data/media") {
            if rel.components().next().map(|c|c.as_os_str().to_string_lossy().chars().all(|v|v.is_ascii_digit())).unwrap_or(false) {
                let m=fs::metadata(&resolved)?;
                if unsafe {fchown(output.as_raw_fd(),m.uid(),m.gid())}!=0 {return Err(io::Error::last_os_error());}
            }
        }
    }
    if let Some((uid,gid))=owner {
        if unsafe {fchown(output.as_raw_fd(),uid,gid)}!=0 {return Err(io::Error::last_os_error());}
        if unsafe {fchmod(output.as_raw_fd(),mode)}!=0 {return Err(io::Error::last_os_error());}
    }
    output.sync_all()?;
    checked_close(output)?;
    // Verify using the visible destination filesystem before publishing.
    input.seek(SeekFrom::Start(0))?;
    let mut verify=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|0x800).open(&stage.path)?;
    let vm=verify.metadata()?;
    if !vm.is_file() || (vm.dev(),vm.ino())!=stage.identity {return Err(io::Error::other("stage replaced"));}
    let mut other=[0u8;65536];
    loop {
        let n=input.read(&mut buffer)?;
        if n==0 {break;}
        verify.read_exact(&mut other[..n])?;
        if buffer[..n]!=other[..n] {return Err(io::Error::other("stage mismatch"));}
    }
    if verify.read(&mut other[..1])?!=0 {return Err(io::Error::other("stage longer than expected"));}
    checked_close(verify)?;
    let after=stamp(&input.metadata()?);
    if after!=before || total!=before.2 {return Err(io::Error::other(format!("source changed before={before:?} after={after:?} read={total}")));}
    checked_close(input)?;
    // Never permit mv-style directory semantics or replace a symlink.
    match fs::symlink_metadata(destination) {
        Ok(m) if m.is_file() && (owner.is_none() || stamp(&m)==before)=>(),
        Ok(_)=>return Err(io::Error::other("destination changed type")),
        Err(e) if e.kind()==io::ErrorKind::NotFound=>(),
        Err(e)=>return Err(e),
    }
    if !stage.matches() {return Err(io::Error::other("stage replaced before rename"));}
    fs::rename(&stage.path,destination)?;
    stage.armed=false;
    // Atomic visibility, not a claim of parent-directory crash durability.
    Ok(total)
}
pub fn run(args: &[String]) -> i32 {
    let started=std::time::Instant::now();
    if !(2..=4).contains(&args.len()) {eprintln!("Usage: publish-file SOURCE DESTINATION [auto|0600|0644|0700|0755] [preserve|detect]");return 2;}
    let mode=match args.get(2).map(String::as_str) {
        None|Some("auto")=>None, Some("0644")=>Some(0o644), Some("0600")=>Some(0o600), Some("0700")=>Some(0o700), Some("0755")=>Some(0o755),
        _=>{eprintln!("PUBLISH_FAIL: unsupported mode");return 2;}
    };
    let preserve=match args.get(3).map(String::as_str) {None=>false,Some("preserve")=>true,Some("detect")=>match auto_preserve(Path::new(&args[1])) {Ok(v)=>v,Err(e)=>{eprintln!("PUBLISH_FAIL: {e}");return 1;}},_=>return 2};
    match publish(Path::new(&args[0]),Path::new(&args[1]),mode,preserve,None) {
        Ok(n)=>{if std::env::var_os("SPEEDBACKUP_PUBLISH_TIMING").is_some(){eprintln!("PUBLISH_TIMING bytes={n} elapsedUs={}",started.elapsed().as_micros());} println!("PUBLISH_OK bytes={n}");0},
        Err(e)=>{eprintln!("PUBLISH_FAIL: {e}");1},
    }
}
// Retain the legacy owner of four generated app lists without chowning the
// existing inode. Derived filesystems keep their natural ownership policy.
pub fn align_owner(args:&[String])->i32 {
    let result=(||->io::Result<()> {
        if args.len()!=2 {return Err(io::Error::other("Usage: generated-list-owner FILE REFERENCE_DIRECTORY"));}
        let path=Path::new(&args[0]);regular(path)?;
        if !auto_preserve(path)? {eprintln!("GENERATED_LIST_OWNER_SKIP policy=natural path={}",path.display());return Ok(());}
        let reference=fs::symlink_metadata(&args[1])?;
        if !reference.is_dir() {return Err(io::Error::other("owner reference must be a directory"));}
        let old=fs::symlink_metadata(path)?;
        let owner=(reference.uid(),reference.gid());
        if (old.uid(),old.gid())!=owner {publish(path,path,None,true,Some(owner))?;}
        Ok(())
    })();
    match result {Ok(())=>0,Err(e)=>{eprintln!("GENERATED_LIST_OWNER_FAIL: {e}");1}}
}
