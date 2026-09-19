use std::collections::HashSet;
use std::ffi::CString;
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::raw::{c_char, c_int, c_long, c_void};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const R550_MARKER: &str = "rust-native-v27-binary-version-marker-r550";
pub const PATH_MAX_SAFE: usize = 4096;

pub type CChar = c_char;

#[repr(C)]
#[derive(Clone, Copy)]
pub struct PollFd {
    pub fd: c_int,
    pub events: i16,
    pub revents: i16,
}

pub const POLLIN: i16 = 0x0001;
pub const POLLERR: i16 = 0x0008;
pub const POLLHUP: i16 = 0x0010;
pub const SIGTERM: c_int = 15;
pub const SIGKILL: c_int = 9;
pub const F_OK: c_int = 0;
pub const W_OK: c_int = 2;
pub const R_OK: c_int = 4;

#[cfg(target_arch = "aarch64")]
pub const SYS_PIDFD_OPEN: c_long = 434;
#[cfg(target_arch = "x86_64")]
pub const SYS_PIDFD_OPEN: c_long = 434;
#[cfg(not(any(target_arch = "aarch64", target_arch = "x86_64")))]
pub const SYS_PIDFD_OPEN: c_long = 434;

extern "C" {
    pub fn syscall(num: c_long, ...) -> c_long;
    pub fn close(fd: c_int) -> c_int;
    pub fn poll(fds: *mut PollFd, nfds: c_long, timeout: c_int) -> c_int;
    pub fn kill(pid: c_int, sig: c_int) -> c_int;
    pub fn fork() -> c_int;
    pub fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
    pub fn execvp(file: *const c_char, argv: *const *const c_char) -> c_int;
    pub fn lchown(path: *const c_char, owner: u32, group: u32) -> c_int;
    pub fn access(path: *const c_char, mode: c_int) -> c_int;
}

pub fn monotonic_ms(start: &Instant) -> u128 { start.elapsed().as_millis() }
pub fn wall_ms() -> u128 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis()
}

/// C parity for eventwait parse_int(): strtol base10, allow leading
/// whitespace, require full suffix consumption, accept 0..=86400000 only.
/// Invalid input returns the caller supplied fallback.
pub fn parse_eventwait_int(s: Option<&str>, fallback: i64) -> i64 {
    let raw = match s { Some(v) if !v.is_empty() => v, _ => return fallback };
    let left = raw.trim_start_matches(|c: char| c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\u{000b}' || c == '\u{000c}');
    if left.is_empty() { return fallback; }
    match left.parse::<i64>() {
        Ok(v) if (0..=86_400_000).contains(&v) => v,
        _ => fallback,
    }
}
/// Faithful port of strerror(errno): Rust's io::Error Display appends
/// "(os error N)" which C's strerror() never does; strip that suffix so
/// printed error text matches C exactly.
pub fn c_strerror(e: &std::io::Error) -> String {
    let s = e.to_string();
    if let Some(pos) = s.find(" (os error ") { s[..pos].to_string() } else { s }
}
pub fn parse_u64_default(s: Option<&str>, fallback: u64) -> u64 {
    let raw = match s { Some(v) if !v.is_empty() && v != "-" => v.as_bytes(), _ => return fallback };
    let mut i = 0usize;
    while i < raw.len() && matches!(raw[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    if i >= raw.len() { return fallback; }
    let neg = if raw[i] == b'+' { i += 1; false } else if raw[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut v: u128 = 0;
    while i < raw.len() && raw[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add((raw[i] - b'0') as u128);
        if v > u64::MAX as u128 { return fallback; }
        i += 1;
    }
    if i == start || i != raw.len() { return fallback; }
    let u = v as u64;
    if neg { 0u64.wrapping_sub(u) } else { u }
}

pub fn tsv_sanitize(s: &str) -> String {
    s.chars().map(|c| if c == '\t' || c == '\n' || c == '\r' { '_' } else { c }).collect()
}
pub fn shell_sanitize(s: &str) -> String {
    // cgfreezer.c sanitize_print() is byte-oriented and caps at 1800 input
    // bytes. Every non-printable/non-ASCII byte becomes one underscore, so a
    // multi-byte UTF-8 character intentionally expands to multiple '_'.
    if s.is_empty() { return "-".to_string(); }
    let mut out=String::new();
    for &c in s.as_bytes().iter().take(1800) {
        if c==b'\n'||c==b'\r'||c==b'\t'||c==b' ' { out.push('_'); }
        else if (0x21..=0x7e).contains(&c) { out.push(c as char); }
        else { out.push('_'); }
    }
    out
}
pub fn cstring_path(path: &Path) -> io::Result<CString> {
    CString::new(path.as_os_str().as_bytes()).map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "nul in path"))
}

pub fn file_exists(path: &Path) -> bool { fs::symlink_metadata(path).is_ok() }
pub fn file_nonempty(path: &Path) -> bool { fs::metadata(path).map(|m| m.len() > 0).unwrap_or(false) }
pub fn socket_ready(path: &Path) -> bool { fs::symlink_metadata(path).map(|m| m.file_type().is_socket()).unwrap_or(false) }
pub fn pid_alive(pid: i32) -> bool {
    if pid <= 0 { return false; }
    let rc = unsafe { kill(pid, 0) };
    rc == 0 || io::Error::last_os_error().raw_os_error() == Some(1)
}
pub fn pidfd_open(pid: i32) -> io::Result<c_int> {
    if pid <= 0 { return Err(io::Error::new(io::ErrorKind::InvalidInput, "bad pid")); }
    let fd = unsafe { syscall(SYS_PIDFD_OPEN, pid as c_int, 0 as c_int) } as c_int;
    if fd < 0 { Err(io::Error::last_os_error()) } else { Ok(fd) }
}

pub fn wait_pid_exit_pidfd(pid: i32, timeout_ms: i64, tag: &str) -> Option<i32> {
    let safe_tag = if tag.is_empty() { "pid_exit" } else { tag };
    let fd = match pidfd_open(pid) { Ok(fd) => fd, Err(_) => return None };
    let start = Instant::now();
    loop {
        let wait_ms = if timeout_ms > 0 {
            let elapsed = start.elapsed().as_millis() as i64;
            if elapsed >= timeout_ms {
                unsafe { close(fd) };
                println!("timeout\t124\t{}\tpidfd-timeout", safe_tag);
                return Some(124);
            }
            (timeout_ms - elapsed) as i32
        } else { -1 };
        let mut pfd = PollFd { fd, events: POLLIN, revents: 0 };
        let r = unsafe { poll(&mut pfd as *mut PollFd, 1, wait_ms) };
        if r > 0 {
            unsafe { close(fd) };
            println!("done\t0\t{}\tpid-exit-pidfd", safe_tag);
            return Some(0);
        }
        if r == 0 {
            unsafe { close(fd) };
            println!("timeout\t124\t{}\tpidfd-timeout", safe_tag);
            return Some(124);
        }
        let e = io::Error::last_os_error();
        if e.kind() == io::ErrorKind::Interrupted { continue; }
        unsafe { close(fd) };
        return None;
    }
}
pub fn wait_pid_exit_poll(pid: i32, timeout_ms: i64, tag: &str) -> i32 {
    let safe_tag = if tag.is_empty() { "pid_exit" } else { tag };
    if pid <= 0 { return 2; }
    if !pid_alive(pid) { println!("done\t0\t{}\tpid-exit", safe_tag); return 0; }
    if let Some(rc) = wait_pid_exit_pidfd(pid, timeout_ms, safe_tag) { return rc; }

    let start = Instant::now();
    let proc_path = format!("/proc/{}", pid);
    let mut ifd: c_int = -1;
    if let Ok(pc) = CString::new(proc_path) {
        let fd = unsafe { inotify_init1(IN_NONBLOCK | IN_CLOEXEC) };
        if fd >= 0 {
            ifd = fd;
            unsafe { inotify_add_watch(ifd, pc.as_ptr(), IN_DELETE_SELF | IN_ATTRIB | IN_MOVE_SELF | IN_IGNORED) };
        }
    }
    loop {
        let now = start.elapsed().as_millis() as i64;
        let mut wait_ms: i64 = 1000;
        if !pid_alive(pid) {
            if ifd >= 0 { unsafe { close(ifd) }; }
            println!("done\t0\t{}\tpid-exit", safe_tag);
            return 0;
        }
        if timeout_ms > 0 {
            if now >= timeout_ms {
                if ifd >= 0 { unsafe { close(ifd) }; }
                println!("timeout\t124\t{}\ttimeout", safe_tag);
                return 124;
            }
            if timeout_ms - now < wait_ms { wait_ms = timeout_ms - now; }
        }
        if ifd >= 0 {
            let mut pfd = PollFd { fd: ifd, events: POLLIN, revents: 0 };
            let prc = unsafe { poll(&mut pfd as *mut PollFd, 1, wait_ms as i32) };
            if prc < 0 {
                let e = io::Error::last_os_error();
                if e.kind() == io::ErrorKind::Interrupted { continue; }
                unsafe { close(ifd) };
                return 4;
            }
            if prc > 0 {
                let mut evbuf = [0u8; 1024];
                unsafe { read(ifd, evbuf.as_mut_ptr() as *mut c_void, evbuf.len()) };
            }
        } else {
            std::thread::sleep(Duration::from_millis(if wait_ms > 0 { wait_ms as u64 } else { 100 }));
        }
    }
}
pub fn file_contains(path: &Path, needle: &str) -> bool {
    if needle.is_empty() { return false; }
    let mut f = match File::open(path) { Ok(f) => f, Err(_) => return false };
    let n = needle.as_bytes();
    let keep = n.len().saturating_sub(1).min(511);
    let mut buf = [0u8; 4096];
    let mut tail_len = 0usize;
    loop {
        let room = 4095usize.saturating_sub(tail_len);
        let nr = match f.read(&mut buf[tail_len..tail_len + room]) { Ok(v) => v, Err(_) => return false };
        let total = tail_len + nr;
        // C writes a terminating NUL then calls strstr(), so embedded NUL bytes
        // terminate the searchable portion of this iteration.
        let searchable = buf[..total].iter().position(|&b| b == 0).unwrap_or(total);
        if n.len() <= searchable && buf[..searchable].windows(n.len()).any(|w| w == n) { return true; }
        if nr == 0 { break; }
        if keep > 0 {
            tail_len = total.min(keep);
            buf.copy_within(total - tail_len..total, 0);
        } else {
            tail_len = 0;
        }
    }
    false
}
pub const IN_NONBLOCK: c_int = 0o4000;
pub const IN_CLOEXEC: c_int = 0o2000000;
pub const IN_MODIFY: u32 = 0x0000_0002;
pub const IN_ATTRIB: u32 = 0x0000_0004;
pub const IN_CLOSE_WRITE: u32 = 0x0000_0008;
pub const IN_MOVED_TO: u32 = 0x0000_0080;
pub const IN_CREATE: u32 = 0x0000_0100;
pub const IN_DELETE_SELF: u32 = 0x0000_0400;
pub const IN_MOVE_SELF: u32 = 0x0000_0800;
pub const IN_IGNORED: u32 = 0x0000_8000;

pub const O_RDWR: c_int = 0o2;
pub const O_NONBLOCK: c_int = 0o4000;
pub const O_CLOEXEC: c_int = 0o2000000;

extern "C" {
    pub fn open(path: *const c_char, flags: c_int, mode: c_int) -> c_int;
}

extern "C" {
    pub fn inotify_init1(flags: c_int) -> c_int;
    pub fn inotify_add_watch(fd: c_int, path: *const c_char, mask: u32) -> c_int;
    pub fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
}

fn condition_met(kind: &str, path: &Path, arg: &str) -> bool {
    match kind {
        "file-created" => file_exists(path),
        "file-nonempty" => file_nonempty(path),
        "file-contains" => file_contains(path, arg),
        "socket-ready" => socket_ready(path),
        _ => false,
    }
}


fn eventwait_parent_for_watch(path: &Path) -> Option<PathBuf> {
    // C parent_dir_of()+basename_of() both use PATH_MAX-sized output buffers.
    // basename is only a gate; wait_path_condition() watches the parent path.
    let raw = path.as_os_str().as_bytes();
    if raw.is_empty() { return None; }
    let slash = raw.iter().rposition(|&b| b == b'/');
    let (parent_b, base_b): (&[u8], &[u8]) = match slash {
        None => (b"." as &[u8], raw),
        Some(0) => (b"/" as &[u8], &raw[1..]),
        Some(pos) => (&raw[..pos], &raw[pos + 1..]),
    };
    if parent_b.len() + 1 > PATH_MAX_SAFE || base_b.len() + 1 > PATH_MAX_SAFE { return None; }
    Some(PathBuf::from(std::ffi::OsStr::from_bytes(parent_b)))
}

/// Faithful port of wait_path_condition(): watches the parent directory (and,
/// once it exists, the target path itself) via inotify, blocking in poll()
/// with a 1000ms safety-net tick rather than a fixed-interval sleep loop.
/// This matters: the previous fixed 50ms sleep-poll implementation added up
/// to 50ms of latency to every check and woke the process 20x/second even
/// when idle, which is exactly the polling behavior eventwait exists to
/// avoid (see the r504/r509/r513/r528 rounds fixing the same class of issue
/// in the *-cmd-bounded wrappers this binary's callers rely on).
pub fn wait_file_condition(kind: &str, path: &Path, arg: &str, timeout_ms: i64, tag: &str) -> i32 {
    if path.as_os_str().is_empty() { return 2; }
    let tag = if tag.is_empty() { "eventwait" } else { tag };
    let start = Instant::now();
    let stable_ms = if kind == "file-size-stable" { parse_eventwait_int(Some(arg), 500) } else { 0 };
    let mut last_size: i64 = -1;
    // None == C's "last_change == 0" (not yet initialized); Some(ms) is
    // relative-to-start elapsed time, matching C's absolute monotonic
    // "last_change" field compared as `now - last_change`.
    let mut last_change_ms: Option<i64> = None;

    // Upfront check before touching inotify at all: if already satisfied,
    // report "immediate" (matches C's pre-watch condition_met() check),
    // distinct from "condition" which means it became true while watching.
    if kind != "file-size-stable" && condition_met(kind, path, arg) {
        println!("ready\t0\t{}\timmediate", tag);
        return 0;
    }
    if kind == "file-size-stable" {
        if let Ok(m) = fs::metadata(path) {
            last_size = m.len() as i64;
            last_change_ms = Some(0); // relative-to-start, matches C's last_change = start
            if stable_ms <= 0 {
                println!("ready\t0\t{}\tsize-stable", tag);
                return 0;
            }
        }
    }

    let parent_c = eventwait_parent_for_watch(path)
        .and_then(|parent| CString::new(parent.as_os_str().as_bytes()).ok());

    let mut ifd: c_int = -1;
    let mut wd_file: c_int = -1;
    if let Some(pc) = parent_c {
        let fd = unsafe { inotify_init1(IN_NONBLOCK | IN_CLOEXEC) };
        if fd >= 0 {
            ifd = fd;
            let dir_mask = IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE
                | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF;
            unsafe { inotify_add_watch(ifd, pc.as_ptr(), dir_mask) };
            if file_exists(path) {
                if let Ok(fc) = CString::new(path.as_os_str().as_bytes()) {
                    let file_mask = IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB
                        | IN_DELETE_SELF | IN_MOVE_SELF;
                    wd_file = unsafe { inotify_add_watch(ifd, fc.as_ptr(), file_mask) };
                }
            }
        }
    }

    let finish = |ifd: c_int| { if ifd >= 0 { unsafe { close(ifd) }; } };

    loop {
        let now = start.elapsed().as_millis() as i64;
        let mut wait_ms: i64 = 1000;
        if timeout_ms > 0 {
            let elapsed = now;
            if elapsed >= timeout_ms {
                finish(ifd);
                println!("timeout\t124\t{}\ttimeout", tag);
                return 124;
            }
            if timeout_ms - elapsed < wait_ms { wait_ms = timeout_ms - elapsed; }
        }

        if kind == "file-size-stable" {
            if let Ok(m) = fs::metadata(path) {
                let sz = m.len() as i64;
                if last_size != sz {
                    last_size = sz;
                    last_change_ms = Some(now);
                } else if let Some(lc) = last_change_ms {
                    if now - lc >= stable_ms {
                        finish(ifd);
                        println!("ready\t0\t{}\tsize-stable", tag);
                        return 0;
                    }
                }
            }
            if let Some(lc) = last_change_ms {
                let to_stable = stable_ms - (now - lc);
                if to_stable >= 0 && to_stable < wait_ms { wait_ms = to_stable + 1; }
            }
        } else if condition_met(kind, path, arg) {
            finish(ifd);
            println!("ready\t0\t{}\tcondition", tag);
            return 0;
        }

        if ifd >= 0 {
            let mut pfd = PollFd { fd: ifd, events: POLLIN, revents: 0 };
            let prc = unsafe { poll(&mut pfd as *mut PollFd, 1, wait_ms.max(0) as c_int) };
            if prc < 0 {
                let e = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
                if e == 4 { continue; } // EINTR
                finish(ifd);
                return 4;
            }
            if prc > 0 && pfd.revents & POLLIN != 0 {
                let mut evbuf = [0u8; 4096];
                unsafe { read(ifd, evbuf.as_mut_ptr() as *mut c_void, evbuf.len()) };
                if wd_file < 0 && file_exists(path) {
                    if let Ok(fc) = CString::new(path.as_os_str().as_bytes()) {
                        let file_mask = IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB
                            | IN_DELETE_SELF | IN_MOVE_SELF;
                        wd_file = unsafe { inotify_add_watch(ifd, fc.as_ptr(), file_mask) };
                    }
                }
            }
        } else {
            std::thread::sleep(Duration::from_millis(if wait_ms > 0 { wait_ms as u64 } else { 100 }));
        }
    }
}
pub fn trim_line(mut s: String) -> String {
    while s.ends_with('\n') || s.ends_with('\r') { s.pop(); }
    s
}
pub fn read_lines(path: &Path) -> io::Result<Vec<String>> {
    // C reference uses getline()/fgets(): byte oriented, CR/LF trimmed by
    // trim_line(), and invalid UTF-8 does not make the whole row disappear.
    // Keep the public String API but read raw bytes and decode lossily rather
    // than BufRead::lines(), which would skip/abort on non-UTF8 list rows.
    let f = File::open(path)?;
    let mut br = BufReader::new(f);
    let mut out = Vec::new();
    let mut buf = Vec::<u8>::new();
    loop {
        buf.clear();
        let n = br.read_until(b'\n', &mut buf)?;
        if n == 0 { break; }
        while matches!(buf.last(), Some(b'\n' | b'\r')) { buf.pop(); }
        out.push(String::from_utf8_lossy(&buf).into_owned());
    }
    Ok(out)
}
pub fn load_set(path: &str) -> HashSet<String> {
    // C load_set_file(): trim only CR/LF, preserve all other leading/trailing
    // whitespace, and skip lines whose very first byte is '#' or 0xef.
    let mut set = HashSet::new();
    if path.is_empty() || path == "-" { return set; }
    if let Ok(lines) = read_lines(Path::new(path)) {
        for l in lines {
            if l.is_empty() { continue; }
            let b0 = l.as_bytes()[0];
            if b0 == b'#' || b0 == 0xef { continue; }
            set.insert(l);
        }
    }
    set
}
#[derive(Default, Clone)]
pub struct ScanResult { pub bytes: u64, pub files: u64, pub dirs: u64, pub links: u64, pub specials: u64, pub errors: u64, pub max_mtime: u64, pub blocks512: u64, pub rows: u64, pub truncated: u64 }

pub fn stat_kind(meta: &fs::Metadata) -> &'static str {
    let ft = meta.file_type();
    if ft.is_file() { "file" }
    else if ft.is_dir() { "dir" }
    else if ft.is_symlink() { "link" }
    else if ft.is_char_device() { "char" }
    else if ft.is_block_device() { "block" }
    else if ft.is_fifo() { "fifo" }
    else if ft.is_socket() { "sock" }
    else { "other" }
}
pub fn mode_octal(meta: &fs::Metadata) -> u32 { meta.mode() & 0o7777 }
pub fn note_stat(res: &mut ScanResult, meta: &fs::Metadata) {
    // C casts st_mtime to uint64_t and uses ordinary unsigned arithmetic.
    let mtime = meta.mtime() as u64;
    if mtime > res.max_mtime { res.max_mtime = mtime; }
    let ft = meta.file_type();
    if ft.is_file() { res.bytes = res.bytes.wrapping_add(meta.len()); res.files = res.files.wrapping_add(1); res.blocks512 = res.blocks512.wrapping_add(meta.blocks()); }
    else if ft.is_dir() { res.dirs = res.dirs.wrapping_add(1); }
    else if ft.is_symlink() { res.links = res.links.wrapping_add(1); }
    else { res.specials = res.specials.wrapping_add(1); }
}
pub fn walk_no_follow<F>(root: &Path, path: &Path, depth: usize, max_depth: Option<usize>, res: &mut ScanResult, f: &mut F) -> io::Result<()>
where F: FnMut(&Path, &fs::Metadata, usize, &mut ScanResult) -> io::Result<()> {
    let meta = match fs::symlink_metadata(path) { Ok(m) => m, Err(e) => { res.errors += 1; return Err(e); } };
    note_stat(res, &meta);
    f(path, &meta, depth, res)?;
    if meta.file_type().is_dir() && max_depth.map(|m| depth < m).unwrap_or(true) {
        let rd = match fs::read_dir(path) { Ok(r) => r, Err(e) => { res.errors += 1; return Err(e); } };
        for ent in rd {
            match ent {
                Ok(ent) => {
                    // Every C recursive walker builds child in char child[PATH_MAX]
                    // through join_path(), including its deliberately conservative
                    // +1 separator allowance even when the parent ends in '/'.
                    let blen = path.as_os_str().as_bytes().len();
                    let nlen = ent.file_name().as_os_str().as_bytes().len();
                    if blen + 1 + nlen + 1 > PATH_MAX_SAFE { res.errors = res.errors.wrapping_add(1); continue; }
                    let _ = walk_no_follow(root, &ent.path(), depth + 1, max_depth, res, f);
                }
                // C's readdir() loop has no post-loop errno check; an iterator-level
                // entry error therefore must not create an extra counted error here.
                Err(_) => {}
            }
        }
    }
    let _ = root;
    Ok(())
}
pub fn rel_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root).unwrap_or(path).to_string_lossy().trim_start_matches('/').to_string()
}
pub fn ensure_parent(path: &Path) -> io::Result<()> {
    if let Some(p) = path.parent() { fs::create_dir_all(p)?; }
    Ok(())
}
pub fn write_file(path: &Path, body: &str) -> io::Result<()> {
    ensure_parent(path)?;
    let mut f = File::create(path)?;
    f.write_all(body.as_bytes())
}

pub fn lchown_path(path: &Path, uid: u32, gid: u32) -> io::Result<()> {
    let c = cstring_path(path)?;
    let rc = unsafe { lchown(c.as_ptr(), uid, gid) };
    if rc == 0 { Ok(()) } else { Err(io::Error::last_os_error()) }
}
pub fn has_prefix_path(path: &Path, prefix: &str) -> bool {
    if prefix.is_empty() || prefix == "-" { return false; }
    let b = path.as_os_str().as_bytes();
    let p = prefix.as_bytes();
    b.starts_with(p) && (b.len() == p.len() || b.get(p.len()) == Some(&b'/'))
}
pub fn fnv1a64_file(path: &Path) -> io::Result<u64> {
    let mut f = File::open(path)?;
    let mut h: u64 = 1469598103934665603;
    let mut buf = [0u8; 8192];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 { break; }
        for b in &buf[..n] { h ^= *b as u64; h = h.wrapping_mul(1099511628211); }
    }
    Ok(h)
}

pub fn proc_cmdline(pid: i32) -> String {
    let p = format!("/proc/{}/cmdline", pid);
    fs::read(p).map(|mut b| { for x in &mut b { if *x == 0 { *x = b' '; } }; String::from_utf8_lossy(&b).trim().to_string() }).unwrap_or_default()
}
/// Faithful port of what C's read_cmdline() actually returns: only the
/// bytes up to (not including) the first NUL in /proc/PID/cmdline. This
/// matters because is_package_process()/signal_kill_target() etc. in C
/// compare against ONLY argv[0] (which is all a genuine Android app
/// process's cmdline ever contains - Zygote never appends extra argv), not
/// the full space-joined argv vector. Using the joined proc_cmdline() for
/// matching purposes is a real bug: any process with more than one
/// NUL-separated cmdline segment would never match here even when argv[0]
/// is an exact match, which is exactly backwards from a "does this look
/// like our package" check.
pub fn proc_cmdline_argv0(pid: i32) -> String {
    let p = format!("/proc/{}/cmdline", pid);
    match fs::read(p) {
        Ok(b) => {
            let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
            String::from_utf8_lossy(&b[..end]).into_owned()
        }
        Err(_) => String::new(),
    }
}
pub fn proc_status_value(pid: i32, key: &str) -> Option<String> {
    let body = fs::read_to_string(format!("/proc/{}/status", pid)).ok()?;
    for line in body.lines() {
        if let Some(rest) = line.strip_prefix(key) { return Some(rest.trim_start_matches(':').trim().to_string()); }
    }
    None
}
pub fn proc_uid(pid: i32) -> Option<u32> {
    let v = proc_status_value(pid, "Uid")?;
    v.split_whitespace().next()?.parse().ok()
}

pub fn list_pids() -> Vec<i32> {
    let mut v = Vec::new();
    if let Ok(rd) = fs::read_dir("/proc") {
        for e in rd.flatten() {
            if let Ok(pid) = e.file_name().to_string_lossy().parse::<i32>() { v.push(pid); }
        }
    }
    v
}
pub fn is_valid_pkg_name(pkg: &str) -> bool {
    // Faithful port of is_valid_pkg_name()/is_pkg_char(): 3-128 chars,
    // only [a-zA-Z0-9._], and must contain at least one '.'.
    let len = pkg.len();
    if !(3..=128).contains(&len) { return false; }
    let mut dot = false;
    for c in pkg.chars() {
        if c == '.' { dot = true; }
        if !(c.is_ascii_alphanumeric() || c == '.' || c == '_') { return false; }
    }
    dot
}
pub fn pid_matches_pkg(pid: i32, pkg: &str, user: i32) -> bool {
    // Faithful port of is_package_process(): exact match, or a
    // "pkg:remainder" multi-process match (e.g. com.app:remote). The
    // previous implementation used cmd.contains(pkg), a substring match
    // that would false-positive on ANY process whose cmdline happens to
    // contain the package name anywhere - including totally unrelated
    // processes (log viewers, grep, shell scripts echoing the package
    // name, or a different package that happens to have this one as a
    // prefix/substring). For a tool whose job is "which PIDs get frozen
    // or killed", this is a real safety bug, not a cosmetic one.
    let cmd = proc_cmdline_argv0(pid);
    if cmd.is_empty() || pkg.is_empty() { return false; }
    let matches = cmd == pkg || (cmd.starts_with(pkg) && cmd.as_bytes().get(pkg.len()) == Some(&b':'));
    if !matches { return false; }
    if user >= 0 {
        if let Some(uid) = proc_uid(pid) {
            let appid = uid % 100000;
            let u = uid / 100000;
            if uid >= 10000 && (u as i32) != user { return false; }
            if appid < 10000 && uid >= 10000 { return false; }
        }
    }
    true
}



pub fn parse_app_line(line: &str) -> Option<(String, String, bool)> {
    // Faithful port of parse_app_line() in speedscan.c: format is
    // "name pkg" (first space separates name from pkg; the '!' or fullwidth
    // '！' prefix on name marks nodata). The previous implementation split
    // on '|' instead of space, which doesn't match the C reference format
    // at all and would silently drop every line of a real applist file.
    let s = line.trim_end_matches(['\n', '\r']);
    if s.is_empty() || s.starts_with('#') || s.as_bytes().first() == Some(&0xef) { return None; }
    let sp = s.find(' ')?;
    let mut name = &s[..sp];
    let mut rest = s[sp + 1..].trim_start_matches(' ');
    let pkg_end = rest.find(' ').unwrap_or(rest.len());
    let pkg = &rest[..pkg_end];
    let _ = &mut rest;
    if name.is_empty() || pkg.is_empty() { return None; }
    let mut no_data = false;
    if let Some(r) = name.strip_prefix('!') { no_data = true; name = r; }
    else if let Some(r) = name.strip_prefix('！') { no_data = true; name = r; }
    // C checks name/pkg emptiness before removing the nodata marker and does
    // not check name again afterwards. Thus a line like "! pkg" is valid and
    // leaves an empty name for safe_name_for_backup() to fall back to pkg.
    Some((name.to_string(), pkg.to_string(), no_data))
}
pub fn safe_name_for_backup(name: &str, pkg: &str) -> String {
    // C writes into char safe[PATH_MAX]: byte-wise replacement with at most
    // PATH_MAX-1 payload bytes. Keep valid UTF-8 char boundaries while applying
    // the same byte budget for normal Android app-name strings.
    const CAP: usize = PATH_MAX_SAFE;
    let src = if !name.is_empty() { name } else if !pkg.is_empty() { pkg } else { "app" };
    let mut s = String::new();
    for c in src.chars() {
        let out_c = if matches!(c, '\t'|'\n'|'\r'|'/'|'\\'|':'|'*'|'?'|'"'|'<'|'>'|'|') { '_' } else { c };
        let need = out_c.len_utf8();
        if s.len().saturating_add(need) >= CAP { break; }
        s.push(out_c);
    }
    if s.is_empty() {
        let fallback = if !pkg.is_empty() { pkg } else { "app" };
        let mut out = String::new();
        for c in fallback.chars() {
            if out.len().saturating_add(c.len_utf8()) >= CAP { break; }
            out.push(c);
        }
        out
    } else { s }
}


