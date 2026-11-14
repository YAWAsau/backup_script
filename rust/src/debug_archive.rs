//! Transactional diagnostic archive publication. Never remove source logs here.
use std::{
    fs::{self, File, OpenOptions},
    io,
    os::unix::{
        fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
        io::AsRawFd,
    },
    path::Path,
    process::Command,
    sync::mpsc,
    time::Duration,
};
#[path = "debug_merge.rs"]
mod debug_merge;
unsafe extern "C" {
    fn flock(fd: i32, op: i32) -> i32;
}
fn lock(path: &Path, timeout: Duration) -> io::Result<File> {
    // Lock the stable directory inode instead of creating a sidecar per session.
    // All publications in this directory serialize; no lock file is left behind.
    let f = OpenOptions::new()
        .read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(path)?;
    let m = f.metadata()?;
    if !m.is_dir() {
        return Err(io::Error::other("invalid diagnostic lock"));
    }
    lock_file(f, timeout)
}
fn lock_file(f: File, timeout: Duration) -> io::Result<File> {
    let (tx, rx) = mpsc::sync_channel(0);
    // flock sleeps in the kernel. On timeout the receiver is dropped; a late
    // acquisition is dropped as well and can never perform an archive update.
    std::thread::spawn(move || {
        let result = loop {
            if unsafe { flock(f.as_raw_fd(), 2) } == 0 {
                break Ok(f);
            }
            let e = io::Error::last_os_error();
            if e.kind() != io::ErrorKind::Interrupted {
                break Err(e);
            }
        };
        let _ = tx.send(result);
    });
    rx.recv_timeout(timeout)
        .map_err(|_| io::Error::new(io::ErrorKind::TimedOut, "diagnostic archive lock timeout"))?
}
struct Temp(std::path::PathBuf);
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
pub fn archive(
    tar: &Path,
    archive: &Path,
    run: &Path,
    append: bool,
    timeout: Duration,
) -> io::Result<()> {
    let parent = archive
        .parent()
        .ok_or_else(|| io::Error::other("archive parent"))?;
    if !archive.is_absolute()
        || !run.is_absolute()
        || parent.canonicalize()? != parent
        || run.canonicalize()? != run
        || !fs::symlink_metadata(run)?.is_dir()
    {
        return Err(io::Error::other("invalid diagnostic paths"));
    }
    let name = archive
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| io::Error::other("archive name"))?;
    if !name.starts_with("speed_debug_") || !name.ends_with(".tar") {
        return Err(io::Error::other("invalid diagnostic archive name"));
    }
    let started = std::time::Instant::now();
    let _lock = lock(parent, timeout)?;
    // Respect an existing old-version sidecar without creating or unlinking it.
    // Unlinking a flock file can let waiters and new writers lock different inodes.
    let _legacy_lock = match OpenOptions::new().read(true).write(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(parent.join(format!("{name}.lock"))) {
        Ok(f) => {
            let m = f.metadata()?;
            if !m.is_file() || m.nlink() != 1 {
                return Err(io::Error::other("invalid legacy diagnostic lock"));
            }
            Some(lock_file(f, timeout.saturating_sub(started.elapsed()))?)
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e),
    };
    let old = match fs::symlink_metadata(archive) {
        Ok(m) => {
            if !m.is_file() || m.nlink() != 1 {
                return Err(io::Error::other("archive is not a regular file"));
            }
            Some(m)
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => None,
        Err(e) => return Err(e),
    };
    if !append && name.starts_with("speed_debug_session_") {
        return Err(io::Error::other("session archives require append mode"));
    }
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(io::Error::other)?
        .as_nanos();
    let suffix = format!("{}.{nonce}", std::process::id());
    let tmp_path = parent.join(format!(".{name}.{suffix}.tmp"));
    let out = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(&tmp_path)?;
    let tmp = Temp(tmp_path);
    drop(out);
    let staging_path = parent.join(format!(".{name}.{suffix}.merge"));
    // Create first, then own cleanup; never remove a pre-existing directory.
    fs::create_dir(&staging_path)?;
    struct Staging(std::path::PathBuf);
    impl Drop for Staging {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
    let staging = Staging(staging_path);
    fs::set_permissions(&staging.0, fs::Permissions::from_mode(0o700))?;
    let root = if append {
        Some(debug_merge::prepare(
            if old.is_some() { Some(archive) } else { None },
            run,
            &staging.0,
        )?)
    } else {
        None
    };
    let (source, member) = if let Some(root) = root {
        (staging.0.as_path(), std::ffi::OsString::from(root))
    } else {
        (
            run.parent().ok_or_else(|| io::Error::other("run parent"))?,
            run.file_name()
                .ok_or_else(|| io::Error::other("run name"))?
                .to_owned(),
        )
    };
    let status = Command::new(tar)
        .arg("-cf")
        .arg(&tmp.0)
        .arg("-C")
        .arg(source)
        .arg("--")
        .arg(member)
        .status()?;
    if !status.success() {
        return Err(io::Error::other("diagnostic tar failed"));
    }
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(&tmp.0)?;
    // Bound the final tar including headers, padding, index and duplicated JSON.
    // An oversized attempt leaves both the previous archive and source logs intact.
    if append && file.metadata()?.len() > debug_merge::LIMIT as u64 {
        return Err(io::Error::other("diagnostic archive exceeds session limit"));
    }
    if file.metadata()?.len() == 0 {
        return Err(io::Error::other("empty diagnostic archive"));
    }
    file.set_permissions(fs::Permissions::from_mode(
        old.as_ref().map_or(0o600, |m| m.mode() & 0o777),
    ))?;
    file.sync_all()?;
    fs::rename(&tmp.0, archive)?;
    File::open(parent)?.sync_all()?;
    Ok(())
}
pub fn command(args: &[String]) -> i32 {
    if args.len() != 4 || !matches!(args[3].as_str(), "append" | "replace") {
        return 2;
    }
    match archive(
        Path::new(&args[0]),
        Path::new(&args[1]),
        Path::new(&args[2]),
        args[3] == "append",
        Duration::from_secs(5),
    ) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("DEBUG_ARCHIVE_FAILED {e}");
            1
        }
    }
}

#[cfg(test)]
mod diagnostic_lock_tests {
    use super::*;
    #[test]
    #[ignore = "isolated Android device test"]
    fn directory_and_legacy_contention() {
        let root=std::path::PathBuf::from(format!("/data/local/tmp/sb-lock-unit-{}",std::process::id()));
        fs::create_dir(&root).unwrap();
        struct Cleanup(std::path::PathBuf);impl Drop for Cleanup{fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}
        let _cleanup=Cleanup(root.clone());let run=root.join("run");fs::create_dir(&run).unwrap();fs::write(run.join("main.log"),"hello\n").unwrap();
        let dest=root.join("speed_debug_test.tar");let tar=Path::new("/data/.speedbackup/tools/tar");
        archive(tar,&dest,&run,true,Duration::from_secs(5)).unwrap();let original=fs::read(&dest).unwrap();
        let held=lock(&root,Duration::from_secs(1)).unwrap();
        assert_eq!(archive(tar,&dest,&run,true,Duration::from_millis(100)).unwrap_err().kind(),io::ErrorKind::TimedOut);
        assert_eq!(fs::read(&dest).unwrap(),original);drop(held);
        let legacy=root.join("speed_debug_test.tar.lock");
        let held=lock_file(OpenOptions::new().read(true).write(true).create_new(true).open(&legacy).unwrap(),Duration::from_secs(1)).unwrap();
        assert_eq!(archive(tar,&dest,&run,true,Duration::from_millis(100)).unwrap_err().kind(),io::ErrorKind::TimedOut);
        assert_eq!(fs::read(&dest).unwrap(),original);drop(held);
        archive(tar,&dest,&run,true,Duration::from_secs(5)).unwrap();assert!(legacy.exists());
    }
}

/// Prune only while holding the same directory lock as publication.
pub fn prune_command(args:&[String])->i32 {
    if args.len()!=2{return 2;}
    let base=Path::new(&args[0]);
    if !base.is_absolute()||base.file_name().and_then(|s|s.to_str())!=Some("speed_debug")||base.canonicalize().ok().as_deref()!=Some(base){return 2;}
    let keep=if args[1].is_empty()||!args[1].bytes().all(|b|b.is_ascii_digit()){10}else{args[1].parse::<usize>().unwrap_or(usize::MAX)};
    let result=(||->io::Result<()>{
        let _guard=lock(base,Duration::from_secs(5))?;
        let mut entries=Vec::new();
        for e in fs::read_dir(base)?{
            let e=e?;let name=e.file_name();let n=name.to_string_lossy();
            if n.starts_with("speed_debug_")&&n.ends_with(".tar")&&e.file_type()?.is_file(){let m=e.metadata()?;entries.push((m.mtime(),m.mtime_nsec(),name,e.path()));}
        }
        entries.sort_by(|a,b|b.0.cmp(&a.0).then(b.1.cmp(&a.1)).then(a.2.cmp(&b.2)));
        for (_,_,name,path) in entries.into_iter().skip(keep){
            // An old writer may only use the sidecar. Do not delete its active archive.
            let old=OpenOptions::new().read(true).write(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(base.join(format!("{}.lock",name.to_string_lossy())));
            let _old_guard=match old {
                Ok(f)=>{let m=f.metadata()?;if !m.is_file()||m.nlink()!=1{continue;}if unsafe{flock(f.as_raw_fd(),2|4)}!=0{continue;}Some(f)},
                Err(e) if e.kind()==io::ErrorKind::NotFound=>None,
                Err(_)=>continue,
            };
            if fs::remove_file(&path).is_ok(){println!("{} {}", super::applist_web::terminal_text("[speed_debug] 已刪除舊除錯壓縮包:"),path.display());}
        }Ok(())
    })();
    match result{Ok(())=>0,Err(e)=>{eprintln!("DEBUG_PRUNE_FAILED {e}");1}}
}
#[cfg(test)]
mod diagnostic_prune_tests {
    use super::*;
    #[test]
    #[ignore="isolated Android device test"]
    fn keep_count_and_active_legacy(){
        let parent=std::path::PathBuf::from(format!("/data/local/tmp/sb-prune-{}",std::process::id()));fs::create_dir(&parent).unwrap();let base=parent.join("speed_debug");fs::create_dir(&base).unwrap();
        struct Cleanup(std::path::PathBuf);impl Drop for Cleanup{fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}let _cleanup=Cleanup(parent);
        for i in 0..12{fs::write(base.join(format!("speed_debug_{i:02}.tar")),"archive").unwrap();}
        fs::write(base.join("unrelated.tar"),"safe").unwrap();let args=vec![base.to_string_lossy().into_owned(),"10".into()];
        assert_eq!(prune_command(&args),0);assert_eq!(fs::read_dir(&base).unwrap().count(),11);
        let archive=fs::read_dir(&base).unwrap().flatten().find(|e|e.file_name().to_string_lossy().starts_with("speed_debug_")).unwrap().path();
        let sidecar=archive.with_extension("tar.lock");let file=OpenOptions::new().create_new(true).write(true).open(&sidecar).unwrap();let guard=lock_file(file,Duration::from_secs(1)).unwrap();
        assert_eq!(prune_command(&[args[0].clone(),"0".into()]),0);assert!(archive.exists());assert!(sidecar.exists());assert!(base.join("unrelated.tar").exists());drop(guard);
        assert_eq!(prune_command(&[args[0].clone(),"0".into()]),0);assert!(!archive.exists());assert!(sidecar.exists());
    }
}

pub(super) fn history(archive:&Path)->io::Result<std::collections::BTreeMap<String,Vec<u8>>>{debug_merge::history(archive)}
