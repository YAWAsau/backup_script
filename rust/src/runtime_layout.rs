//! Offline-only layout migration. Never merge, unlink files, or disturb processes.
use std::{
    collections::BTreeMap, ffi::CString,
    fs::{self, File, OpenOptions}, io::{self, Read},
    os::{fd::AsRawFd, unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt}},
    path::Path,
};
unsafe extern "C" {
    fn flock(fd: i32, operation: i32) -> i32;
}
const ROOT: &str = "/data/.speedbackup";
const LOCK: &str = "/data/.speedbackup/cache.lock";
fn defer() -> io::Error { io::Error::other("layout identity/process visibility ambiguous") }
fn same(a: &fs::Metadata, b: &fs::Metadata) -> bool {
    a.dev() == b.dev() && a.ino() == b.ino()
}
fn bounded(p: &Path, limit: u64) -> io::Result<Vec<u8>> {
    let mut b = Vec::new();
    File::open(p)?.take(limit + 1).read_to_end(&mut b)?;
    if b.len() as u64 > limit { return Err(defer()); }
    Ok(b)
}
fn directory(p: &Path, uid: u32, mode: Option<u32>) -> io::Result<File> {
    let m = fs::symlink_metadata(p)?;
    if !m.is_dir() || m.uid() != uid || m.mode() & 0o7022 != 0
        || mode.is_some_and(|v| m.mode() & 0o7777 != v)
        || p.canonicalize()? != p { return Err(defer()); }
    let f = OpenOptions::new().read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE
                      | speedbackup_native_rs::O_NONBLOCK).open(p)?;
    if !same(&m, &f.metadata()?) { return Err(defer()); }
    Ok(f)
}
fn recheck(p: &Path, f: &File) -> io::Result<()> {
    if !same(&fs::symlink_metadata(p)?, &f.metadata()?) { return Err(defer()); }
    Ok(())
}
#[derive(Clone, Copy, PartialEq, Eq)]
struct Identity { parent: u32, start: u64 }
fn identity(pid: u32) -> io::Result<Identity> {
    let b = bounded(Path::new(&format!("/proc/{pid}/stat")), 65536)?;
    let s = std::str::from_utf8(&b).map_err(|_| defer())?;
    let end = s.rfind(')').ok_or_else(defer)?;
    let fields: Vec<_> = s[end + 1..].split_whitespace().collect();
    Ok(Identity {
        parent: fields.get(1).ok_or_else(defer)?.parse().map_err(|_| defer())?,
        start: fields.get(19).ok_or_else(defer)?.parse().map_err(|_| defer())?,
    })
}
fn ancestors() -> io::Result<BTreeMap<u32, Identity>> {
    let mut result = BTreeMap::new();
    let mut pid = std::process::id();
    for _ in 0..128 {
        if pid == 0 { validate(&result)?; return Ok(result); }
        let id = identity(pid)?;
        if result.insert(pid, id).is_some() { return Err(defer()); }
        pid = id.parent;
    }
    Err(defer())
}
fn validate(ids: &BTreeMap<u32, Identity>) -> io::Result<()> {
    for (&pid, &id) in ids {
        if identity(pid)? != id { return Err(defer()); }
    }
    Ok(())
}
fn marked(b: &[u8]) -> bool {
    [b"/data/.speedbackup".as_slice(), b"/data/speed_debug", b"com.xayah.dex",
     b"speednative", b"speedscan"].iter()
        .any(|m| b.windows(m.len()).any(|w| w == *m))
}
fn check_bytes(b: &[u8]) -> io::Result<()> {
    if marked(b) { Err(io::Error::other("another project process is active")) } else { Ok(()) }
}
fn check_link(p: &Path) -> io::Result<()> {
    check_bytes(fs::read_link(p)?.as_os_str().as_encoded_bytes())
}
fn scan(ids: &BTreeMap<u32, Identity>) -> io::Result<()> {
    validate(ids)?;
    for e in fs::read_dir("/proc")? {
        let e = e?;
        let name = e.file_name();
        let Some(pid) = name.to_str().and_then(|s| s.parse::<u32>().ok()) else { continue };
        let p = e.path();
        let result = (|| -> io::Result<()> {
            let before = identity(pid)?;
            if let Some(id) = ids.get(&pid) {
                if *id != before { return Err(defer()); }
                return Ok(());
            }
            let m = fs::metadata(&p)?;
            // Also protect helpers that have dropped privileges. Any unreadable
            // existing process is ambiguous, rather than evidence of inactivity.
            let cmd = bounded(&p.join("cmdline"), 1024 * 1024)?;
            check_bytes(&cmd)?;
            if cmd.is_empty() {
                let stat = bounded(&p.join("stat"), 65536)?;
                let s = std::str::from_utf8(&stat).map_err(|_| defer())?;
                let end = s.rfind(')').ok_or_else(defer)?;
                let fields: Vec<_> = s[end + 1..].split_whitespace().collect();
                let flags: u64 = fields.get(6).ok_or_else(defer)?
                    .parse().map_err(|_| defer())?;
                // Positively identified kernel threads and zombies cannot launch jobs.
                if flags & 0x00200000 == 0 && fields.first() != Some(&"Z") {
                    return Err(defer());
                }
            } else {
                check_bytes(&bounded(&p.join("environ"), 1024 * 1024)?)?;
                check_bytes(&bounded(&p.join("maps"), 16 * 1024 * 1024)?)?;
                for n in ["exe", "cwd", "root"] { check_link(&p.join(n))?; }
                let exe = fs::read_link(p.join("exe"))?;
                let arg0 = cmd.split(|b| *b == 0).next().ok_or_else(defer)?;
                let shell = |b: &[u8]| {
                    let leaf = b.rsplit(|c| *c == b'/').next().unwrap_or(b);
                    matches!(leaf, b"sh" | b"bash" | b"mksh" | b"ash" | b"dash" |
                        b"zsh" | b"ksh" | b"fish" | b"busybox" | b"toybox")
                        || leaf.starts_with(b"-")
                };
                if m.uid() == 0 && (shell(arg0) || shell(exe.as_os_str().as_encoded_bytes())) {
                    return Err(io::Error::other("unknown root shell active"));
                }
                for fd in fs::read_dir(p.join("fd"))? { check_link(&fd?.path())?; }
            }
            if identity(pid)? != before { return Err(defer()); }
            Ok(())
        })();
        if let Err(err) = result {
            match fs::symlink_metadata(&p) {
                Err(e) if e.kind() == io::ErrorKind::NotFound => {},
                _ => return Err(err),
            }
        }
    }
    validate(ids)
}
// Parent descriptors pin the validated namespaces; the source descriptor also
// pins the original inode for post-rename chmod. No traversal of contents.
fn move_dir(from: &Path, to: &Path, debug: bool, uid: u32) -> io::Result<bool> {
    match fs::symlink_metadata(from) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(e) => return Err(e),
        Ok(_) => {},
    }
    let ap = from.parent().ok_or_else(defer)?;
    let bp = to.parent().ok_or_else(defer)?;
    let a = directory(ap, uid, None)?;
    let b = directory(bp, uid, None)?;
    let original = directory(from, uid, if debug { None } else { Some(0o700) })?;
    match fs::symlink_metadata(to) {
        Ok(_) => return Err(io::Error::other("destination exists; retaining legacy source")),
        Err(e) if e.kind() == io::ErrorKind::NotFound => {},
        Err(e) => return Err(e),
    }
    recheck(ap, &a)?; recheck(bp, &b)?; recheck(from, &original)?;
    let old = CString::new(from.file_name().ok_or_else(defer)?.as_encoded_bytes()).map_err(|_| defer())?;
    let new = CString::new(to.file_name().ok_or_else(defer)?.as_encoded_bytes()).map_err(|_| defer())?;
    if unsafe { speedbackup_native_rs::syscall(276, a.as_raw_fd(), old.as_ptr(), b.as_raw_fd(), new.as_ptr(), 1u32) } != 0 {
        return Err(io::Error::last_os_error());
    }
    if debug { original.set_permissions(fs::Permissions::from_mode(0o700))?; }
    recheck(to, &original)?;
    Ok(true)
}
fn collect() -> io::Result<()> {
    let root = directory(Path::new(ROOT), 0, Some(0o711))?;
    let data = directory(Path::new("/data"), 0, None)?;
    let lock = OpenOptions::new().read(true).write(true).create(true).mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE
                      | speedbackup_native_rs::O_NONBLOCK).open(LOCK)?;
    let m = lock.metadata()?;
    if !m.is_file() || m.uid() != 0 || m.nlink() != 1 || m.mode() & 0o7777 != 0o600 {
        return Err(defer());
    }
    if unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
        return Err(io::Error::other("cache lease busy"));
    }
    recheck(Path::new(LOCK), &lock)?;
    let ids = ancestors()?;
    scan(&ids)?;
    scan(&ids)?;
    recheck(Path::new(ROOT), &root)?;
    recheck(Path::new("/data"), &data)?;
    recheck(Path::new(LOCK), &lock)?;
    for (old, child, debug) in [
        ("/data/speed_debug", "debug", true),
        ("/data/.speedbackup-fileops", "fileops", false),
    ] {
        if let Err(e) = move_dir(Path::new(old), &Path::new(ROOT).join(child), debug, 0) {
            eprintln!("RUNTIME_LAYOUT defer path={old} reason={e}");
        }
    }
    let oldtmp = Path::new("/data/.speedbackup_tmp");
    match fs::symlink_metadata(oldtmp) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e),
        Ok(_) => {},
    }
    let legacy = directory(oldtmp, 0, Some(0o700))?;
    let source = oldtmp.join(".uid_policy_locks");
    match fs::symlink_metadata(&source) {
        Ok(_) => {
            let tmp = Path::new(ROOT).join("tmp");
            match fs::DirBuilder::new().mode(0o700).create(&tmp) {
                Ok(()) => {},
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {},
                Err(e) => return Err(e),
            }
            let _tmp = directory(&tmp, 0, Some(0o700))?;
            move_dir(&source, &tmp.join(".uid_policy_locks"), false, 0)?;
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => {},
        Err(e) => return Err(e),
    }
    recheck(oldtmp, &legacy)?;
    // rmdir is the only deletion operation: unknown contents always survive.
    match fs::remove_dir(oldtmp) {
        Ok(()) => {},
        Err(e) if e.kind() == io::ErrorKind::DirectoryNotEmpty => {},
        Err(e) => return Err(e),
    }
    // lock remains held until this function returns.
    Ok(())
}
pub(crate) fn on_start() {
    if ["/data/speed_debug", "/data/.speedbackup-fileops", "/data/.speedbackup_tmp"].iter().all(|p| matches!(fs::symlink_metadata(p),Err(e) if e.kind()==io::ErrorKind::NotFound)) { return; }
    if let Err(e) = collect() { eprintln!("RUNTIME_LAYOUT defer reason={e}"); }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{path::PathBuf, os::unix::fs::symlink, sync::atomic::{AtomicU64, Ordering}};
    static NEXT: AtomicU64 = AtomicU64::new(0);
    struct Fixture { root: PathBuf, uid: u32 }
    impl Fixture {
        fn new() -> Self {
            let root = std::env::temp_dir().canonicalize().unwrap().join(format!(
                "runtime-layout-{}-{}", std::process::id(), NEXT.fetch_add(1, Ordering::Relaxed)));
            fs::DirBuilder::new().mode(0o700).create(&root).unwrap();
            let uid = fs::metadata(&root).unwrap().uid();
            Self { root, uid }
        }
        fn dir(&self, name: &str) -> PathBuf {
            let p = self.root.join(name);
            fs::DirBuilder::new().mode(0o700).create(&p).unwrap(); p
        }
        fn run(&self, a: &Path, b: &Path) -> io::Result<bool> { move_dir(a, b, false, self.uid) }
    }
    impl Drop for Fixture {
        fn drop(&mut self) {
            // Test fixtures only; production migration never recursively deletes.
            fs::remove_dir_all(&self.root).unwrap();
        }
    }
    #[test] fn inode_preserved() {
        let f = Fixture::new(); let a = f.dir("old"); let b = f.root.join("new");
        let file = File::create(a.join("mutex")).unwrap();
        let dir = fs::metadata(&a).unwrap(); let inode = file.metadata().unwrap();
        assert!(f.run(&a, &b).unwrap());
        assert!(same(&dir, &fs::metadata(&b).unwrap()));
        assert!(same(&inode, &fs::metadata(b.join("mutex")).unwrap()));
    }
    #[test] fn collision_retains_both() {
        let f = Fixture::new(); let a = f.dir("old"); let b = f.dir("new");
        let ma = fs::metadata(&a).unwrap(); let mb = fs::metadata(&b).unwrap();
        assert!(f.run(&a, &b).is_err());
        assert!(same(&ma, &fs::metadata(a).unwrap()));
        assert!(same(&mb, &fs::metadata(b).unwrap()));
    }
    #[test] fn symlink_rejected() {
        let f = Fixture::new(); let real = f.dir("real"); let a = f.root.join("old");
        symlink(&real, &a).unwrap();
        assert!(f.run(&a, &f.root.join("new")).is_err()); assert!(real.exists());
    }
    #[test] fn unsafe_mode_rejected() {
        let f = Fixture::new(); let a = f.dir("old");
        fs::set_permissions(&a, fs::Permissions::from_mode(0o777)).unwrap();
        assert!(f.run(&a, &f.root.join("new")).is_err()); assert!(a.exists());
    }
    #[test] fn unknown_contents_retained() {
        let f = Fixture::new(); let a = f.dir("old"); let b = f.root.join("new");
        fs::create_dir(a.join("unknown")).unwrap();
        fs::write(a.join("unknown/recovery"), b"do not discard").unwrap();
        symlink("missing", a.join("unknown/link")).unwrap();
        assert!(f.run(&a, &b).unwrap());
        assert_eq!(fs::read(b.join("unknown/recovery")).unwrap(), b"do not discard");
        assert_eq!(fs::read_link(b.join("unknown/link")).unwrap(), Path::new("missing"));
    }
}
