//! Per-run root-private SHA cache. Every call reopens and checks the target.
use std::{
    fs::{self, File, Metadata, OpenOptions},
    io::{self, Read, Write},
    os::{
        fd::AsRawFd,
        unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    },
    path::Path,
};
const NOFOLLOW: i32 = speedbackup_native_rs::O_NOFOLLOW_NATIVE;
extern "C" {
    fn flock(fd: i32, op: i32) -> i32;
    fn geteuid() -> u32;
}
fn bad() -> io::Error {
    io::Error::new(io::ErrorKind::Other, "unsafe or changed SHA-cache input")
}
fn private_dir(p: &Path) -> io::Result<()> {
    let m = fs::symlink_metadata(p)?;
    if !m.is_dir() || m.uid() != 0 || m.mode() & 0o777 != 0o700 || fs::canonicalize(p)? != p {
        return Err(bad());
    }
    Ok(())
}
fn record(p: &Path) -> io::Result<File> {
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(NOFOLLOW | 2048)
        .open(p)?;
    let m = f.metadata()?;
    if !m.is_file() || m.uid() != 0 || m.mode() & 0o777 != 0o600 || m.nlink() != 1 {
        return Err(bad());
    }
    Ok(f)
}
fn identity(m: &Metadata) -> String {
    format!(
        "{}:{}:{}:{}:{}:{}:{}:{}:{}:{}:{}",
        m.dev(),
        m.ino(),
        m.len(),
        m.uid(),
        m.gid(),
        m.mode(),
        m.nlink(),
        m.mtime(),
        m.mtime_nsec(),
        m.ctime(),
        m.ctime_nsec()
    )
}
fn execute(a: &[String]) -> io::Result<&'static str> {
    if a.len() != 4
        || unsafe { geteuid() } != 0
        || a[2].len() != 64
        || !a[2]
            .bytes()
            .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
    {
        return Err(bad());
    }
    let root = Path::new(&a[0]);
    private_dir(root)?;
    let owner: u32 = a[3].parse().map_err(|_| bad())?;
    if owner <= 1 {
        return Err(bad());
    }
    let stat = fs::read_to_string(format!("/proc/{owner}/stat"))?;
    let start = stat
        .rsplit_once(") ")
        .and_then(|(_, s)| s.split_whitespace().nth(19))
        .ok_or_else(bad)?;
    let run = format!(
        "{}:{}:{}",
        fs::read_to_string("/proc/sys/kernel/random/boot_id")?.trim(),
        owner,
        start
    );
    let dir = root.join(".smb-sha-cache");
    match fs::create_dir(&dir) {
        Ok(()) => fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))?,
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(e),
    }
    private_dir(&dir)?;
    let lock = record(&dir.join("lock"))?;
    let deadline = std::time::Instant::now() + std::time::Duration::from_millis(250);
    while unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
        if std::time::Instant::now() >= deadline {
            return Err(io::Error::new(
                io::ErrorKind::WouldBlock,
                "SHA cache lock busy",
            ));
        }
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
    let path = Path::new(&a[1]);
    if !path.is_absolute() || fs::canonicalize(path)? != path {
        return Err(bad());
    }
    let mut input = OpenOptions::new()
        .read(true)
        .custom_flags(NOFOLLOW | 2048)
        .open(path)?;
    let before = input.metadata()?;
    if !before.is_file() {
        return Err(bad());
    }
    let parent = fs::metadata(path.parent().ok_or_else(bad)?)?;
    // Writable/shared targets still receive a full hash, never a cache hit.
    let cacheable = before.uid() == 0
        && before.mode() & 0o022 == 0
        && parent.uid() == 0
        && parent.mode() & 0o022 == 0
        && (before.ctime_nsec() != 0 || before.mtime_nsec() != 0);
    let fingerprint = identity(&before);
    let key = format!("SBSHA1\n{}\n{}\n{}\n{}\n", run, a[1], a[2], fingerprint);
    let cache = dir.join("verified");
    let mut saved = record(&cache)?;
    let mut previous = Vec::new();
    (&mut saved).take(4097).read_to_end(&mut previous)?;
    let hit = cacheable && previous == key.as_bytes();
    if !hit {
        let hash = crate::speedscan::sha256_reader_hex(&mut input)?;
        if hash != a[2] {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "SHA-256 mismatch",
            ));
        }
    }
    if identity(&input.metadata()?) != fingerprint
        || identity(&fs::symlink_metadata(path)?) != fingerprint
    {
        return Err(bad());
    }
    if !hit && cacheable {
        // Under the lock; interrupted/truncated writes are cache misses, never hits.
        use std::io::{Seek, SeekFrom};
        saved.set_len(0)?;
        saved.seek(SeekFrom::Start(0))?;
        saved.write_all(key.as_bytes())?;
    }
    Ok(if hit { "HIT" } else { "VERIFIED" })
}
pub fn run(a: &[String]) -> i32 {
    match execute(a) {
        Ok(s) => {
            println!("{s}");
            0
        }
        Err(e) => {
            eprintln!("TOOL_SHA_CACHE_REJECT {e}");
            1
        }
    }
}
