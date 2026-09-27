//! App-only permission repair and process-lifetime directory leases.
//! The flock serializes lease changes only; the shell's PID/start/boot identity
//! owns the directory until release or verified process death.
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

extern "C" {
    fn lchown(path: *const c_char, uid: u32, gid: u32) -> c_int;
    fn lgetxattr(path: *const c_char, name: *const c_char, value: *mut c_void, size: usize) -> isize;
    fn lsetxattr(path: *const c_char, name: *const c_char, value: *const c_void, size: usize, flags: c_int) -> c_int;
    fn flock(fd: c_int, op: c_int) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
}

#[derive(Default)]
struct Repair {
    visited: u64, excluded: u64, owners: u64, labels: u64, errors: u64,
    fallback_count: u64,
    fallback: Vec<PathBuf>,
}

fn flush_fallback(out: &mut Repair) {
    if out.fallback.is_empty() { return; }
    if !matches!(Command::new("/system/bin/restorecon").arg("-F").args(&out.fallback).status(), Ok(s) if s.success()) { out.errors += 1; }
    out.fallback.clear();
}

fn repair(path: &Path, root: bool, uid: u32, gid: u32, context: Option<&CString>, allow_fallback: bool, out: &mut Repair) {
    let meta = match fs::symlink_metadata(path) { Ok(m) => m, Err(_) => { out.errors += 1; return; } };
    let cpath = match CString::new(path.as_os_str().as_bytes()) { Ok(p) => p, Err(_) => { out.errors += 1; return; } };
    out.visited += 1;
    let link = meta.file_type().is_symlink();
    if meta.uid() != uid || meta.gid() != gid {
        if unsafe { lchown(cpath.as_ptr(), uid, gid) } != 0 { out.errors += 1; }
        else {
            out.owners += 1;
            // chown can clear special permission bits. Preserve extracted mode.
            if !link && meta.mode() & 0o6000 != 0 && fs::set_permissions(path, fs::Permissions::from_mode(meta.mode() & 0o7777)).is_err() { out.errors += 1; }
        }
    }
    let mut label_ok = false;
    if let Some(ctx) = context {
        let attr = b"security.selinux\0";
        let mut current = [0u8; 4096];
        let n = unsafe { lgetxattr(cpath.as_ptr(), attr.as_ptr().cast(), current.as_mut_ptr().cast(), current.len()) };
        if n >= 0 && current[..n as usize].strip_suffix(&[0]).unwrap_or(&current[..n as usize]) == ctx.as_bytes() { label_ok = true; }
        else if unsafe { lsetxattr(cpath.as_ptr(), attr.as_ptr().cast(), ctx.as_bytes_with_nul().as_ptr().cast(), ctx.as_bytes_with_nul().len(), 0) } == 0 {
            out.labels += 1; label_ok = true;
        }
    }
    if !label_ok {
        if allow_fallback {
            out.fallback.push(path.to_path_buf()); out.fallback_count += 1;
            if out.fallback.len() == 64 { flush_fallback(out); }
        }
        else { out.errors += 1; }
    }
    if meta.is_dir() && !link {
        match fs::read_dir(path) {
            Ok(entries) => for entry in entries {
                match entry {
                    Ok(e) => {
                        if root && (e.file_name() == "cache" || e.file_name() == "code_cache") { out.excluded += 1; continue; }
                        repair(&e.path(), false, uid, gid, context, allow_fallback, out);
                    }
                    Err(_) => out.errors += 1,
                }
            },
            Err(_) => out.errors += 1,
        }
    }
}

pub fn permissions(args: &[String]) -> i32 {
    if args.len() != 4 { return 2; }
    let (u, g) = match args[0].split_once(':') { Some(v) => v, None => return 2 };
    let (uid, gid) = match (u.parse::<u32>(), g.parse::<u32>()) { (Ok(u), Ok(g)) if u != u32::MAX && g != u32::MAX => (u,g), _ => return 2 };
    let root = Path::new(&args[1]);
    if !matches!(fs::symlink_metadata(root), Ok(m) if m.is_dir() && !m.file_type().is_symlink()) { return 2; }
    let fallback = match args[3].as_str() { "1" => true, "0" => false, _ => return 2 };
    let ctx = if args[2].is_empty() || args[2] == "?" { None } else { match CString::new(args[2].as_bytes()) { Ok(c) => Some(c), Err(_) => return 2 } };
    let mut out = Repair::default();
    let started = Instant::now();
    repair(root, true, uid, gid, ctx.as_ref(), fallback, &mut out);
    // Non-recursive batches visit exactly the already-selected nodes: cache trees
    // cannot be revisited by a recursive restorecon fallback.
    flush_fallback(&mut out);
    println!("APP_PERMISSIONS_V1 visited={} excluded={} owners={} labels={} fallback={} errors={} elapsedMs={} policy=no-follow,skip-top-cache", out.visited, out.excluded, out.owners, out.labels, out.fallback_count, out.errors, started.elapsed().as_millis());
    if out.errors == 0 { 0 } else { 1 }
}

fn identity(pid: u32) -> io::Result<String> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let tail = stat.rsplit_once(") ").ok_or(io::ErrorKind::InvalidData)?.1;
    let start = tail.split_whitespace().nth(19).ok_or(io::ErrorKind::InvalidData)?;
    let boot = fs::read_to_string("/proc/sys/kernel/random/boot_id")?;
    Ok(format!("{}:{}:{}", pid, start, boot.trim()))
}
fn guard(path: &Path) -> io::Result<File> {
    let mut name = path.as_os_str().to_os_string(); name.push(".guard");
    let f = OpenOptions::new().read(true).write(true).create(true).mode(0o600).custom_flags(0x20000).open(name)?;
    if unsafe { flock(f.as_raw_fd(), 2 | 4) } != 0 { return Err(io::Error::last_os_error()); }
    Ok(f)
}
fn remove_owned(path: &Path) -> io::Result<()> {
    for name in ["owner", "pid"] { match fs::remove_file(path.join(name)) { Ok(()) => (), Err(e) if e.kind() == io::ErrorKind::NotFound => (), Err(e) => return Err(e) } }
    fs::remove_dir(path)
}
fn acquire(path: &Path, pid: u32) -> io::Result<String> {
    let token = identity(pid)?;
    let _guard = guard(path)?;
    if path.exists() {
        let meta = fs::symlink_metadata(path)?;
        if !meta.is_dir() || meta.file_type().is_symlink() { return Err(io::ErrorKind::PermissionDenied.into()); }
        let old = fs::read_to_string(path.join("pid"))?.trim().parse::<u32>().map_err(|_| io::ErrorKind::InvalidData)?;
        if old <= 1 || old > i32::MAX as u32 { return Err(io::ErrorKind::InvalidData.into()); }
        let recorded = fs::read_to_string(path.join("owner")).ok();
        if let Some(ref value) = recorded {
            let fields: Vec<_> = value.trim().split(':').collect();
            if fields.len() != 3 || fields[0].parse::<u32>().ok() != Some(old)
                || fields[1].parse::<u64>().is_err() || fields[2].len() != 36
                || !fields[2].bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
                return Err(io::ErrorKind::InvalidData.into());
            }
        }
        if let Ok(live) = identity(old) {
            if recorded.as_ref().map(|x| x.trim() == live).unwrap_or(true) { return Err(io::ErrorKind::AlreadyExists.into()); }
        } else if unsafe { kill(old as i32, 0) } == 0 || io::Error::last_os_error().raw_os_error() == Some(1) { return Err(io::ErrorKind::AlreadyExists.into()); }
        remove_owned(path)?;
    }
    fs::create_dir(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))?;
    fs::write(path.join("owner"), &token)?;
    fs::write(path.join("pid"), pid.to_string())?;
    Ok(token)
}
pub fn lock(args: &[String], release: bool) -> i32 {
    if args.len() != 2 { return 2; }
    let path = Path::new(&args[0]);
    if release {
        let result = (|| -> io::Result<()> {
            let _guard = guard(path)?;
            if !path.exists() { return Ok(()); }
            let m = fs::symlink_metadata(path)?;
            if !m.is_dir() || m.file_type().is_symlink() { return Err(io::ErrorKind::PermissionDenied.into()); }
            if fs::read_to_string(path.join("owner"))?.trim() != args[1] { return Err(io::ErrorKind::PermissionDenied.into()); }
            remove_owned(path)
        })();
        return if result.is_ok() { 0 } else { 1 };
    }
    let pid = match args[1].parse::<u32>() { Ok(p) if p > 1 && p <= i32::MAX as u32 => p, _ => return 2 };
    match acquire(path, pid) { Ok(token) => { println!("{token}"); 0 }, Err(_) => { eprintln!("LOCK_BUSY_OR_UNVERIFIED"); 1 } }
}
