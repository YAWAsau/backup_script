//! App-only permission repair and process-lifetime directory leases.
//! The flock serializes lease changes only; the shell's PID/start/boot identity
//! owns the directory until release or verified process death.
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

struct StopProcess {
    pid: u32,
    token: String,
    fd: File,
    resume: bool,
}
impl StopProcess {
    fn signal(&self, signal: i32) -> io::Result<()> {
        // pidfd pins the process, including across PID reuse. No numeric-PID fallback.
        let rc = unsafe {
            speedbackup_native_rs::syscall(
                424 as std::os::raw::c_long,
                self.fd.as_raw_fd(),
                signal,
                std::ptr::null::<c_void>(),
                0u32,
            )
        };
        if rc == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
    fn exited(&self) -> io::Result<bool> {
        let mut p = speedbackup_native_rs::PollFd {
            fd: self.fd.as_raw_fd(),
            events: 1,
            revents: 0,
        };
        let rc = unsafe { speedbackup_native_rs::poll(&mut p, 1, 0) };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(p.revents & 1 != 0)
    }
}
impl Drop for StopProcess {
    fn drop(&mut self) {
        // A failed scan must not leave processes frozen by this controller.
        if self.resume {
            let _ = self.signal(18);
        }
    }
}
fn process_parent_state(pid: u32) -> io::Result<(u32, char)> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let tail = stat.rsplit_once(") ").ok_or(io::ErrorKind::InvalidData)?.1;
    let mut fields = tail.split_whitespace();
    let state = fields
        .next()
        .and_then(|x| x.chars().next())
        .ok_or(io::ErrorKind::InvalidData)?;
    let parent = fields
        .next()
        .ok_or(io::ErrorKind::InvalidData)?
        .parse()
        .map_err(|_| io::ErrorKind::InvalidData)?;
    Ok((parent, state))
}
fn stop_process(pid: u32, token: &str) -> io::Result<StopProcess> {
    let fd = speedbackup_native_rs::pidfd_open(pid as i32)?;
    let mut p = StopProcess {
        pid,
        token: token.into(),
        fd: unsafe { File::from_raw_fd(fd) },
        resume: false,
    };
    if identity(pid)? != token {
        return Err(io::ErrorKind::PermissionDenied.into());
    }
    let state = process_parent_state(pid)?.1;
    if state != 'T' && state != 't' && !p.exited()? {
        p.resume = true;
        p.signal(19)?;
    }
    let start = Instant::now();
    while !p.exited()? {
        if matches!(process_parent_state(pid)?.1, 'T' | 't') {
            break;
        }
        if start.elapsed().as_millis() > 1000 {
            return Err(io::ErrorKind::TimedOut.into());
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    Ok(p)
}

/// Stop only the lease snapshot selected by the user, never a replacement owner.
pub fn lock_stop(args: &[String]) -> i32 {
    if args.len() != 2 {
        return 2;
    }
    let result = (|| -> io::Result<usize> {
        let path = Path::new(&args[0]);
        let expected = &args[1];
        let _guard = guard(path)?;
        let meta = fs::symlink_metadata(path)?;
        if !meta.is_dir() || meta.file_type().is_symlink() {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        if fs::read_to_string(path.join("owner"))?.trim() != expected {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        let pid_raw = match fs::read_to_string(path.join("pid")) {
            Ok(value) => value,
            Err(e) if e.kind() == io::ErrorKind::NotFound => expected
                .split(':')
                .next()
                .ok_or(io::ErrorKind::InvalidData)?
                .to_owned(),
            Err(e) => return Err(e),
        };
        let pid: u32 = pid_raw
            .trim()
            .parse()
            .map_err(|_| io::ErrorKind::InvalidData)?;
        if pid <= 1 || pid > i32::MAX as u32 || identity(pid)? != *expected {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        // Never terminate this controller, or a parent whose death could kill it.
        let mut ancestor = std::process::id();
        for _ in 0..256 {
            if ancestor == pid {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            if ancestor <= 1 {
                break;
            }
            ancestor = process_parent_state(ancestor)?.0;
        }
        let mut processes = vec![stop_process(pid, expected)?];
        let started = Instant::now();
        loop {
            let before = processes.len();
            for entry in fs::read_dir("/proc")? {
                let entry = entry?;
                let child = match entry.file_name().to_string_lossy().parse::<u32>() {
                    Ok(p) if p > 1 => p,
                    _ => continue,
                };
                if processes.iter().any(|p| p.pid == child) {
                    continue;
                }
                let (parent, _) = match process_parent_state(child) {
                    Ok(v) => v,
                    Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(e),
                };
                if !processes.iter().any(|p| {
                    p.pid == parent && identity(parent).ok().as_deref() == Some(p.token.as_str())
                }) {
                    continue;
                }
                let token = match identity(child) {
                    Ok(t) => t,
                    Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(e),
                };
                match stop_process(child, &token) {
                    Ok(p) => processes.push(p),
                    Err(e)
                        if e.raw_os_error() == Some(3) || e.kind() == io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e),
                }
            }
            if processes.len() == before {
                break;
            }
            if processes.len() > 4096 || started.elapsed().as_secs() >= 8 {
                return Err(io::ErrorKind::TimedOut.into());
            }
        }
        // Frozen parents cannot create new workers. Kill children before their owner.
        for p in processes.iter().rev() {
            if !p.exited()? {
                p.signal(9)?;
            }
        }
        let deadline = Instant::now();
        loop {
            let mut pending = false;
            for p in &processes {
                if !p.exited()? {
                    pending = true;
                }
            }
            if !pending {
                break;
            }
            if deadline.elapsed().as_secs() >= 5 {
                return Err(io::ErrorKind::TimedOut.into());
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        if fs::read_to_string(path.join("owner"))?.trim() != expected {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        remove_owned(path)?;
        Ok(processes.len())
    })();
    match result {
        Ok(count) => {
            println!("LOCK_STOP_OK processes={count}");
            0
        }
        Err(e) => {
            eprintln!("LOCK_STOP_REFUSED_OR_INCOMPLETE error={e}");
            1
        }
    }
}

extern "C" {
    fn lchown(path: *const c_char, uid: u32, gid: u32) -> c_int;
    fn lgetxattr(
        path: *const c_char,
        name: *const c_char,
        value: *mut c_void,
        size: usize,
    ) -> isize;
    fn lsetxattr(
        path: *const c_char,
        name: *const c_char,
        value: *const c_void,
        size: usize,
        flags: c_int,
    ) -> c_int;
    fn flock(fd: c_int, op: c_int) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
}

#[derive(Default)]
struct Repair {
    visited: u64,
    excluded: u64,
    owners: u64,
    labels: u64,
    errors: u64,
    fallback_count: u64,
    fallback: Vec<PathBuf>,
}

fn flush_fallback(out: &mut Repair) {
    if out.fallback.is_empty() {
        return;
    }
    if !matches!(Command::new("/system/bin/restorecon").arg("-F").args(&out.fallback).status(), Ok(s) if s.success())
    {
        out.errors += 1;
    }
    out.fallback.clear();
}

fn repair(
    path: &Path,
    root: bool,
    uid: u32,
    gid: u32,
    context: Option<&CString>,
    allow_fallback: bool,
    out: &mut Repair,
) {
    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(_) => {
            out.errors += 1;
            return;
        }
    };
    let cpath = match CString::new(path.as_os_str().as_bytes()) {
        Ok(p) => p,
        Err(_) => {
            out.errors += 1;
            return;
        }
    };
    out.visited += 1;
    let link = meta.file_type().is_symlink();
    if meta.uid() != uid || meta.gid() != gid {
        if unsafe { lchown(cpath.as_ptr(), uid, gid) } != 0 {
            out.errors += 1;
        } else {
            out.owners += 1;
            // chown can clear special permission bits. Preserve extracted mode.
            if !link
                && meta.mode() & 0o6000 != 0
                && fs::set_permissions(path, fs::Permissions::from_mode(meta.mode() & 0o7777))
                    .is_err()
            {
                out.errors += 1;
            }
        }
    }
    let mut label_ok = false;
    if let Some(ctx) = context {
        let attr = b"security.selinux\0";
        let mut current = [0u8; 4096];
        let n = unsafe {
            lgetxattr(
                cpath.as_ptr(),
                attr.as_ptr().cast(),
                current.as_mut_ptr().cast(),
                current.len(),
            )
        };
        if n >= 0
            && current[..n as usize]
                .strip_suffix(&[0])
                .unwrap_or(&current[..n as usize])
                == ctx.as_bytes()
        {
            label_ok = true;
        } else if unsafe {
            lsetxattr(
                cpath.as_ptr(),
                attr.as_ptr().cast(),
                ctx.as_bytes_with_nul().as_ptr().cast(),
                ctx.as_bytes_with_nul().len(),
                0,
            )
        } == 0
        {
            out.labels += 1;
            label_ok = true;
        }
    }
    if !label_ok {
        if allow_fallback {
            out.fallback.push(path.to_path_buf());
            out.fallback_count += 1;
            if out.fallback.len() == 64 {
                flush_fallback(out);
            }
        } else {
            out.errors += 1;
        }
    }
    if meta.is_dir() && !link {
        match fs::read_dir(path) {
            Ok(entries) => {
                for entry in entries {
                    match entry {
                        Ok(e) => {
                            if root && (e.file_name() == "cache" || e.file_name() == "code_cache") {
                                out.excluded += 1;
                                continue;
                            }
                            repair(&e.path(), false, uid, gid, context, allow_fallback, out);
                        }
                        Err(_) => out.errors += 1,
                    }
                }
            }
            Err(_) => out.errors += 1,
        }
    }
}

pub fn permissions(args: &[String]) -> i32 {
    if args.len() != 4 {
        return 2;
    }
    let (u, g) = match args[0].split_once(':') {
        Some(v) => v,
        None => return 2,
    };
    let (uid, gid) = match (u.parse::<u32>(), g.parse::<u32>()) {
        (Ok(u), Ok(g)) if u != u32::MAX && g != u32::MAX => (u, g),
        _ => return 2,
    };
    let root = Path::new(&args[1]);
    if !matches!(fs::symlink_metadata(root), Ok(m) if m.is_dir() && !m.file_type().is_symlink()) {
        return 2;
    }
    let fallback = match args[3].as_str() {
        "1" => true,
        "0" => false,
        _ => return 2,
    };
    let ctx = if args[2].is_empty() || args[2] == "?" {
        None
    } else {
        match CString::new(args[2].as_bytes()) {
            Ok(c) => Some(c),
            Err(_) => return 2,
        }
    };
    let mut out = Repair::default();
    let started = Instant::now();
    repair(root, true, uid, gid, ctx.as_ref(), fallback, &mut out);
    // Non-recursive batches visit exactly the already-selected nodes: cache trees
    // cannot be revisited by a recursive restorecon fallback.
    flush_fallback(&mut out);
    println!("APP_PERMISSIONS_V1 visited={} excluded={} owners={} labels={} fallback={} errors={} elapsedMs={} policy=no-follow,skip-top-cache", out.visited, out.excluded, out.owners, out.labels, out.fallback_count, out.errors, started.elapsed().as_millis());
    if out.errors == 0 {
        0
    } else {
        1
    }
}

fn identity(pid: u32) -> io::Result<String> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let tail = stat.rsplit_once(") ").ok_or(io::ErrorKind::InvalidData)?.1;
    let start = tail
        .split_whitespace()
        .nth(19)
        .ok_or(io::ErrorKind::InvalidData)?;
    let boot = fs::read_to_string("/proc/sys/kernel/random/boot_id")?;
    Ok(format!("{}:{}:{}", pid, start, boot.trim()))
}
fn guard(path: &Path) -> io::Result<File> {
    let mut name = path.as_os_str().to_os_string();
    name.push(".guard");
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(name)?;
    let meta = f.metadata()?;
    if !meta.is_file() || meta.uid() != 0 || meta.nlink() != 1 {
        return Err(io::ErrorKind::PermissionDenied.into());
    }
    if unsafe { flock(f.as_raw_fd(), 2 | 4) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(f)
}
fn remove_owned(path: &Path) -> io::Result<()> {
    for name in ["owner", "pid"] {
        match fs::remove_file(path.join(name)) {
            Ok(()) => (),
            Err(e) if e.kind() == io::ErrorKind::NotFound => (),
            Err(e) => return Err(e),
        }
    }
    fs::remove_dir(path)
}
fn acquire(path: &Path, pid: u32) -> io::Result<String> {
    let token = identity(pid)?;
    let _guard = guard(path)?;
    if path.exists() {
        let meta = fs::symlink_metadata(path)?;
        if !meta.is_dir() || meta.file_type().is_symlink() {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        let old_raw = match fs::read_to_string(path.join("pid")) {
            Ok(value) => value,
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                // Old releases could die between mkdir/owner/pid. Never age out a
                // live owner; only remove a trusted incomplete lease under flock.
                if meta.uid() != 0 {
                    return Err(io::ErrorKind::PermissionDenied.into());
                }
                match fs::read_to_string(path.join("owner")) {
                    Ok(owner) => {
                        let old = owner
                            .trim()
                            .split(':')
                            .next()
                            .and_then(|x| x.parse::<u32>().ok())
                            .filter(|x| *x > 1 && *x <= i32::MAX as u32)
                            .ok_or(io::ErrorKind::InvalidData)?;
                        if identity(old)
                            .map(|live| live == owner.trim())
                            .unwrap_or(true)
                        {
                            // A missing process is distinguishable from unreadable /proc.
                            if unsafe { kill(old as i32, 0) } == 0
                                || io::Error::last_os_error().raw_os_error() != Some(3)
                            {
                                return Err(io::ErrorKind::AlreadyExists.into());
                            }
                        }
                    }
                    Err(e) if e.kind() == io::ErrorKind::NotFound => (),
                    Err(e) => return Err(e),
                }
                // Refuse unknown contents instead of recursive deletion.
                for entry in fs::read_dir(path)? {
                    if entry?.file_name() != "owner" {
                        return Err(io::ErrorKind::InvalidData.into());
                    }
                }
                remove_owned(path)?;
                return publish_lease(path, pid, &token);
            }
            Err(e) => return Err(e),
        };
        let old = old_raw
            .trim()
            .parse::<u32>()
            .map_err(|_| io::ErrorKind::InvalidData)?;
        if old <= 1 || old > i32::MAX as u32 {
            return Err(io::ErrorKind::InvalidData.into());
        }
        let recorded = fs::read_to_string(path.join("owner")).ok();
        if let Some(ref value) = recorded {
            let fields: Vec<_> = value.trim().split(':').collect();
            if fields.len() != 3
                || fields[0].parse::<u32>().ok() != Some(old)
                || fields[1].parse::<u64>().is_err()
                || fields[2].len() != 36
                || !fields[2]
                    .bytes()
                    .all(|b| b.is_ascii_hexdigit() || b == b'-')
            {
                return Err(io::ErrorKind::InvalidData.into());
            }
        }
        if let Ok(live) = identity(old) {
            if recorded.as_ref().map(|x| x.trim() == live).unwrap_or(true) {
                return Err(io::ErrorKind::AlreadyExists.into());
            }
        } else if unsafe { kill(old as i32, 0) } == 0
            || io::Error::last_os_error().raw_os_error() == Some(1)
        {
            return Err(io::ErrorKind::AlreadyExists.into());
        }
        remove_owned(path)?;
    }
    publish_lease(path, pid, &token)
}

fn publish_lease(path: &Path, pid: u32, token: &str) -> io::Result<String> {
    let parent = path.parent().ok_or(io::ErrorKind::InvalidInput)?;
    let nonce = fs::read_to_string("/proc/sys/kernel/random/uuid")?;
    let stage = parent.join(format!(".backup-lease-{}", nonce.trim()));
    fs::DirBuilder::new().mode(0o700).create(&stage)?;
    let result = (|| -> io::Result<String> {
        for (name, value) in [("owner", token.to_owned()), ("pid", pid.to_string())] {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(stage.join(name))?;
            file.write_all(value.as_bytes())?;
            file.sync_all()?;
        }
        File::open(&stage)?.sync_all()?;
        // All participants hold the same flock. No visible half-written lease.
        fs::rename(&stage, path)?;
        File::open(parent)?.sync_all()?;
        Ok(token.to_owned())
    })();
    if stage.exists() {
        let _ = remove_owned(&stage);
    }
    result
}
pub fn lock(args: &[String], release: bool) -> i32 {
    if args.len() != 2 {
        return 2;
    }
    let path = Path::new(&args[0]);
    if release {
        let result = (|| -> io::Result<()> {
            let _guard = guard(path)?;
            if !path.exists() {
                return Ok(());
            }
            let m = fs::symlink_metadata(path)?;
            if !m.is_dir() || m.file_type().is_symlink() {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            if fs::read_to_string(path.join("owner"))?.trim() != args[1] {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            remove_owned(path)
        })();
        return if result.is_ok() { 0 } else { 1 };
    }
    let pid = match args[1].parse::<u32>() {
        Ok(p) if p > 1 && p <= i32::MAX as u32 => p,
        _ => return 2,
    };
    match acquire(path, pid) {
        Ok(token) => {
            println!("{token}");
            0
        }
        Err(_) => {
            eprintln!("LOCK_BUSY_OR_UNVERIFIED");
            1
        }
    }
}
