//! Reclaim only immutable bootstrap binaries. Recovery state and mutex inodes are not garbage.
use std::{fs::{self,File,OpenOptions},io::{self,Read},os::{fd::AsRawFd,unix::fs::{MetadataExt,OpenOptionsExt}},path::Path,time::{Duration,SystemTime}};
unsafe extern "C" { fn flock(fd:i32,operation:i32)->i32; fn close(fd:i32)->i32; }
const ROOT:&str="/data/.speedbackup";
const LOCK:&str="/data/.speedbackup/cache.lock";
const GRACE:Duration=Duration::from_secs(600);
fn invalid()->io::Error {io::Error::other("cache identity or process visibility unavailable")}
fn private_dir(path:&Path)->io::Result<()> {
    let m=fs::symlink_metadata(path)?;
    if !m.is_dir()||m.uid()!=0||m.mode()&0o022!=0||path.canonicalize()?!=path{return Err(invalid());}Ok(())
}
fn limited(path:&Path,max:u64)->io::Result<Vec<u8>> {
    let mut b=Vec::new();File::open(path)?.take(max+1).read_to_end(&mut b)?;
    if b.len() as u64>max{return Err(invalid());}Ok(b)
}
fn contains(haystack:&[u8],path:&Path)->bool {let needle=path.as_os_str().as_encoded_bytes();haystack.windows(needle.len()).any(|x|x==needle)}
fn references()->io::Result<Vec<Vec<u8>>> {
    let mut refs=Vec::new();
    let mut ancestors=std::collections::HashSet::new();let mut pid=std::process::id();
    for _ in 0..64 {if pid==0||!ancestors.insert(pid){break;}
        let stat=fs::read_to_string(format!("/proc/{pid}/stat"))?;
        pid=stat.rsplit_once(") ").and_then(|(_,s)|s.split_whitespace().nth(1)).and_then(|s|s.parse().ok()).ok_or_else(invalid)?;
    }
    for entry in fs::read_dir("/proc")? {
        let entry=entry?;if !entry.file_name().as_encoded_bytes().iter().all(u8::is_ascii_digit){continue;}
        let p=entry.path();let m=match fs::metadata(&p){Ok(m)=>m,Err(e)if e.kind()==io::ErrorKind::NotFound=>continue,Err(e)=>return Err(e)};
        // Private bootstrap directories cannot be opened by non-root applications.
        if m.uid()!=0{
            // A native helper can drop UID after exec; still protect its executable.
            if let Ok(path)=fs::read_link(p.join("exe")){refs.push(path.as_os_str().as_encoded_bytes().to_vec());}
            continue;
        }
        let scan=(||->io::Result<()> {
            let cmd=limited(&p.join("cmdline"),1024*1024)?;
            if cmd.is_empty(){return Ok(());} // kernel thread/zombie
            // Ancestor shells are waiting for this invocation; other legacy shell
            // launchers must be positively classified before any cache is removed.
            if !ancestors.contains(&entry.file_name().to_string_lossy().parse::<u32>().unwrap_or(0)) {
                let args=cmd.split(|b|*b==0).filter(|a|!a.is_empty()).collect::<Vec<_>>();
                let shell=args.first().and_then(|a|std::str::from_utf8(a).ok()).and_then(|s|Path::new(s).file_name()).is_some_and(|s|matches!(s.to_str(),Some("sh"|"bash"|"mksh"|"ash"|"dash"|"zsh")));
                if shell&&args.iter().any(|a|*a==b"-c"){return Err(io::Error::other("unclassified shell launcher active"));}
                for (i,arg) in args.iter().enumerate().skip(1) {
                    if arg.ends_with(b".sh")||(shell&&i==1&&!arg.starts_with(b"-")) {
                        let name=std::str::from_utf8(arg).map_err(|_|invalid())?;
                        let path=if Path::new(name).is_absolute(){Path::new(name).to_path_buf()}else{fs::read_link(p.join("cwd"))?.join(name)};
                        let bytes=limited(&path,4*1024*1024)?;
                        if bytes.windows(11).any(|w|w==b"SpeedBackup"){return Err(io::Error::other("legacy/script launcher active"));}
                    }
                }
            }
            refs.push(cmd);refs.push(limited(&p.join("environ"),1024*1024)?);refs.push(limited(&p.join("maps"),16*1024*1024)?);
            for name in ["exe","cwd"] {refs.push(fs::read_link(p.join(name))?.as_os_str().as_encoded_bytes().to_vec());}
            for fd in fs::read_dir(p.join("fd"))? {
                match fs::read_link(fd?.path()){Ok(path)=>refs.push(path.as_os_str().as_encoded_bytes().to_vec()),Err(e)if e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e)}
            }
            Ok(())
        })();
        if let Err(e)=scan {if p.exists(){return Err(e);}}
    }
    Ok(refs)
}
fn binary_name(name:&str)->bool {name=="speednative"||name=="classes.dex"}
fn hash_name(name:&str)->bool {name.len()==64&&name.bytes().all(|b|b.is_ascii_hexdigit()&&!b.is_ascii_uppercase())}
fn old_enough(m:&fs::Metadata,now:SystemTime)->bool {m.modified().ok().and_then(|t|now.duration_since(t).ok()).is_some_and(|age|age>=GRACE)}
fn removable_file(path:&Path,now:SystemTime)->io::Result<bool> {
    let m=fs::symlink_metadata(path)?;
    Ok(m.is_file()&&m.uid()==0&&m.nlink()==1&&m.mode()&0o022==0&&old_enough(&m,now))
}
fn prune(base:&Path,current:&Path,refs:&[Vec<u8>],now:SystemTime)->io::Result<usize> {
    if !base.try_exists()?{return Ok(0);}private_dir(base)?;let mut removed=0;
    for entry in fs::read_dir(base)? {
        let entry=entry?;let path=entry.path();let name=entry.file_name();let Some(name)=name.to_str()else{continue};
        if current.starts_with(&path)||refs.iter().any(|r|contains(r,&path)){continue;}
        if hash_name(name) {
            let m=fs::symlink_metadata(&path)?;
            if !m.is_dir()||!old_enough(&m,now){continue;}private_dir(&path)?;
            let children=fs::read_dir(&path)?.collect::<Result<Vec<_>,_>>()?;
            // No recursive delete. Unknown files, partial writes, links, recovery state => retain.
            if children.iter().any(|e|!e.file_name().to_str().is_some_and(binary_name)){continue;}
            let mut safe=true;for child in &children {if !removable_file(&child.path(),now)?{safe=false;break;}}
            if !safe{continue;}
            for child in children {fs::remove_file(child.path())?;removed+=1;}
            fs::remove_dir(&path)?;
        } else if binary_name(name)&&removable_file(&path,now)? {
            fs::remove_file(&path)?;removed+=1;
        }
    }
    // Only retired roots are removed, and only if the OS confirms they are empty.
    if base!=Path::new("/data/.speedbackup/console_boot") && old_enough(&fs::symlink_metadata(base)?,now) {let _=fs::remove_dir(base);}
    Ok(removed)
}
pub(crate) fn on_start() {
    // The wrapper holds a shared lease from before cache creation through exec.
    // Release only our verified inherited descriptor, never an arbitrary caller FD.
    let mut leased=false;
    if std::env::var("SPEEDBACKUP_CACHE_LEASE_FD").ok().as_deref()==Some("9") {
        std::env::remove_var("SPEEDBACKUP_CACHE_LEASE_FD");
        if fs::read_link("/proc/self/fd/9").ok().as_deref()==Some(Path::new(LOCK)){unsafe{close(9);}leased=true;}
    }
    if !leased {eprintln!("RUNTIME_CACHE_CLEANUP retained reason=no-bootstrap-lease");return;}
    if let Err(e)=collect(){eprintln!("RUNTIME_CACHE_CLEANUP retained reason={e}");}
}
fn collect()->io::Result<()> {
    private_dir(Path::new(ROOT))?;
    let lock=OpenOptions::new().read(true).write(true).create(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK).open(LOCK)?;
    let m=lock.metadata()?;if !m.is_file()||m.uid()!=0||m.nlink()!=1||m.mode()&0o077!=0{return Err(invalid());}
    if unsafe{flock(lock.as_raw_fd(),2|4)}!=0{return Err(io::Error::other("another launcher/cleanup holds cache lease"));}
    let refs=references()?;let current=std::env::current_exe()?;let now=SystemTime::now();let mut removed=0;
    for base in ["/data/.speedbackup/console_boot","/data/.speedbackup_console_boot"] {removed+=prune(Path::new(base),&current,&refs,now)?;}
    let legacy_tmp=Path::new("/data/.speedbackup_tmp");
    if legacy_tmp.try_exists()? {
        private_dir(legacy_tmp)?;
        if old_enough(&fs::symlink_metadata(legacy_tmp)?,now) && !refs.iter().any(|r|contains(r,legacy_tmp)||r.windows(14).any(|s|s==b"com.xayah.dex.")) {
            // UidPolicyLock intentionally keeps its cross-version lock inode here.
            match fs::remove_dir(legacy_tmp) {Ok(())=>{},Err(e)if e.kind()==io::ErrorKind::DirectoryNotEmpty=>eprintln!("RUNTIME_CACHE_CLEANUP retained path=/data/.speedbackup_tmp reason=locks-or-recovery-state"),Err(e)=>return Err(e)}
        }
    }
    eprintln!("RUNTIME_CACHE_CLEANUP removedFiles={removed}");Ok(())
}

#[cfg(test)] mod tests {
    use super::*;use std::{path::PathBuf,os::unix::fs::{DirBuilderExt,PermissionsExt,symlink}};
    #[test] fn retains_current_referenced_unknown_and_symlink() {
        let root=PathBuf::from(format!("/data/local/tmp/sb-cache-test-{}",std::process::id()));
        fs::DirBuilder::new().mode(0o700).create(&root).unwrap();
        let now=SystemTime::now()+Duration::from_secs(700);
        for c in ['a','b','c','d','e'] {let p=root.join(c.to_string().repeat(64));fs::DirBuilder::new().mode(0o700).create(&p).unwrap();fs::write(p.join("speednative"),b"fixture").unwrap();fs::set_permissions(p.join("speednative"),fs::Permissions::from_mode(0o600)).unwrap();}
        let a=root.join("a".repeat(64));let b=root.join("b".repeat(64));let c=root.join("c".repeat(64));let d=root.join("d".repeat(64));let e=root.join("e".repeat(64));
        fs::write(c.join("pending-state"),b"preserve").unwrap();symlink(&a,d.join("classes.dex")).unwrap();
        assert_eq!(prune(&root,&a.join("speednative"),&[b.as_os_str().as_encoded_bytes().to_vec()],now).unwrap(),1);
        assert!(a.exists()&&b.exists()&&c.exists()&&d.exists()&&!e.exists());
        fs::remove_dir_all(root).unwrap();
    }
    #[test] fn recent_cache_is_retained() {
        let root=PathBuf::from(format!("/data/local/tmp/sb-cache-young-{}",std::process::id()));fs::DirBuilder::new().mode(0o700).create(&root).unwrap();
        let p=root.join("f".repeat(64));fs::DirBuilder::new().mode(0o700).create(&p).unwrap();
        assert_eq!(prune(&root,Path::new("/unrelated"),&[],SystemTime::now()).unwrap(),0);assert!(p.exists());fs::remove_dir_all(root).unwrap();
    }
}
