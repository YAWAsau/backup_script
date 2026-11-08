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
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(path)?;
    let m = f.metadata()?;
    if !m.is_file() || m.nlink() != 1 {
        return Err(io::Error::other("invalid diagnostic lock"));
    }
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
    let _lock = lock(&parent.join(format!("{name}.lock")), timeout)?;
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
