use speedbackup_native_rs::*;
use std::ffi::CString;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::os::raw::{c_char, c_int, c_ulong, c_void};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::io::FromRawFd;
use std::os::unix::net::UnixStream;
use std::net::Shutdown;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use std::sync::atomic::{AtomicBool, Ordering};

use std::cell::RefCell;

#[derive(Clone, Copy)]
struct CgfreezerPrintSink {
    ptr: *mut (),
    write_bytes: unsafe fn(*mut (), &[u8]),
    write_fmt: for<'a> unsafe fn(*mut (), std::fmt::Arguments<'a>),
}

unsafe fn sink_write_bytes<W: Write>(ptr: *mut (), bytes: &[u8]) {
    let out = &mut *(ptr as *mut W);
    let _ = out.write_all(bytes);
    let _ = out.flush();
}

unsafe fn sink_write_fmt<W: Write>(ptr: *mut (), args: std::fmt::Arguments<'_>) {
    let out = &mut *(ptr as *mut W);
    let _ = out.write_fmt(args);
    let _ = out.write_all(b"\n");
    let _ = out.flush();
}

thread_local! {
    static CGFREEZER_PRINT_SINK: RefCell<Option<CgfreezerPrintSink>> = RefCell::new(None);
}

fn cgfreezer_write_bytes(bytes: &[u8]) {
    CGFREEZER_PRINT_SINK.with(|cell| {
        if let Some(sink) = *cell.borrow() {
            unsafe { (sink.write_bytes)(sink.ptr, bytes); }
        } else {
            let mut out = io::stdout().lock();
            let _ = out.write_all(bytes);
            let _ = out.flush();
        }
    });
}

fn cgfreezer_println(args: std::fmt::Arguments<'_>) {
    CGFREEZER_PRINT_SINK.with(|cell| {
        if let Some(sink) = *cell.borrow() {
            unsafe { (sink.write_fmt)(sink.ptr, args); }
        } else {
            let mut out = io::stdout().lock();
            let _ = out.write_fmt(args);
            let _ = out.write_all(b"\n");
            let _ = out.flush();
        }
    });
}

struct CgfreezerCurrentOutput;
impl Write for CgfreezerCurrentOutput {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        cgfreezer_write_bytes(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> io::Result<()> { Ok(()) }
}

macro_rules! println {
    ($($arg:tt)*) => {{
        cgfreezer_println(format_args!($($arg)*));
    }};
}

fn with_cgfreezer_output<T, W: Write, F: FnOnce() -> T>(out: &mut W, f: F) -> T {
    // Sink is installed only for the dynamic extent of this function, and the
    // daemon handles one worker command per stream before restoring the prior
    // sink. This avoids fd-level capture while sharing the CLI command logic.
    let sink = CgfreezerPrintSink {
        ptr: out as *mut W as *mut (),
        write_bytes: sink_write_bytes::<W>,
        write_fmt: sink_write_fmt::<W>,
    };
    CGFREEZER_PRINT_SINK.with(|cell| {
        let prev = cell.replace(Some(sink));
        let ret = f();
        cell.replace(prev);
        ret
    })
}

const VERSION: &str = "r485-backend-select-cache-api28-r28c-rust-r572";
const PROTOCOL: &str = "line-v9-backend-select-r485";
const MAX_TEXT: usize = 16384;
const MAX_PATH_LEN: usize = 2048;
const UNIX_SUN_PATH_MAX: usize = 108;
const MAX_KILL_TARGETS: usize = 512;
const MAX_UID_PATHS: usize = 128;
const MAX_UID_PIDS: usize = 512;
const MAX_DAEMON_CHILDREN: usize = 64;
const WNOHANG: c_int = 1;
const SIGTERM_DAEMON: c_int = 15;
const CAPS: &str = "check-root,backend-probe,scan,freeze,freeze-package-single-request-v1,kill-package-live-rescan-v1 rust-convergence-source-v1,pidfd-signal-optional-v1,thaw,thaw-uid-emergency-v1,binder-freeze,binder-info,subscribe-logd,pid-cache,uid-cache,cgroup-v2-events,cgroup-v2-uid-root-fallback,cgroup-v1-freezer,daemon-parent-control-v1,daemon-stats-v1,daemon-stats-detail-v1,last-error-v1,daemon-control-plain-lines-v2,kill-report-v2,batch-pid-list-v1,proc-snapshot-v1,pidfd-kill-v1,cgroup-kill-fastpath-v1,cgroup-wchan-confirm-v1,proc-wchan-v1,uid-wchan-v1,backend-select-cache-v1";

extern "C" { fn _exit(status: c_int) -> !; }
#[repr(C)]
struct SockAddrUn {
    sun_family: u16,
    sun_path: [c_char; UNIX_SUN_PATH_MAX],
}

extern "C" {
    fn open(path: *const c_char, flags: c_int, mode: c_int) -> c_int;
    fn close(fd: c_int) -> c_int;
    fn write(fd: c_int, buf: *const c_void, count: usize) -> isize;
    fn ioctl(fd: c_int, request: c_ulong, argp: *mut c_void) -> c_int;
    fn socket(domain: c_int, ty: c_int, protocol: c_int) -> c_int;
    fn bind(fd: c_int, addr: *const c_void, len: u32) -> c_int;
    fn listen(fd: c_int, backlog: c_int) -> c_int;
    fn accept4(fd: c_int, addr: *mut c_void, addrlen: *mut u32, flags: c_int) -> c_int;
}
const BINDER_O_RDWR: c_int = 0o2;
const BINDER_O_CLOEXEC: c_int = 0o2000000;
const C_O_WRONLY: c_int = 0o1;
const C_O_CLOEXEC: c_int = 0o2000000;
const C_AF_UNIX: c_int = 1;
const C_SOCK_STREAM: c_int = 1;
const C_SOCK_CLOEXEC: c_int = 0o2000000;

// _IOW('b', 14, struct binder_freeze_info)  where sizeof(binder_freeze_info)=12
const BINDER_FREEZE: c_ulong = 0x400c620e;
// _IOWR('b', 15, struct binder_frozen_status_info)  where sizeof(...)=12
const BINDER_GET_FROZEN_INFO: c_ulong = 0xc00c620f;
const ENOTTY: i32 = 25;
const EINVAL: i32 = 22;
const EAGAIN: i32 = 11;
const EINTR: i32 = 4;

#[repr(C)]
struct BinderFreezeInfo { pid: u32, enable: u32, timeout_ms: u32 }
#[repr(C)]
struct BinderFrozenStatusInfo { pid: u32, sync_recv: u32, async_recv: u32 }

#[derive(Clone)]
struct BinderStatus {
    supported: bool,
    ok: bool,
    err: i32,
    sync_recv: u32,
    async_recv: u32,
    device: &'static str,
}
impl Default for BinderStatus {
    fn default() -> Self { BinderStatus { supported: false, ok: false, err: 0, sync_recv: 0, async_recv: 0, device: "-" } }
}

/// Faithful port of open_binder_device(): tries /dev/binder then
/// /dev/binderfs/binder, returns the fd and which path worked.
fn open_binder_device() -> (c_int, &'static str) {
    for (path, name) in [("/dev/binder\0", "/dev/binder"), ("/dev/binderfs/binder\0", "/dev/binderfs/binder")] {
        let fd = unsafe { open(path.as_ptr() as *const std::os::raw::c_char, BINDER_O_RDWR | BINDER_O_CLOEXEC, 0) };
        if fd >= 0 { return (fd, name); }
    }
    (-1, "-")
}

fn errno_now() -> i32 { io::Error::last_os_error().raw_os_error().unwrap_or(0) }

/// Faithful port of binder_get_status(): BINDER_GET_FROZEN_INFO ioctl.
fn binder_get_status(pid: i32) -> BinderStatus {
    let mut st = BinderStatus::default();
    let (fd, dev) = open_binder_device();
    st.device = dev;
    if fd < 0 { st.err = errno_now(); return st; }
    let mut info = BinderFrozenStatusInfo { pid: pid as u32, sync_recv: 0, async_recv: 0 };
    let mut rc;
    loop {
        rc = unsafe { ioctl(fd, BINDER_GET_FROZEN_INFO, &mut info as *mut _ as *mut c_void) };
        if rc == 0 || errno_now() != EINTR { break; }
    }
    let err = if rc == 0 { 0 } else { errno_now() };
    st.err = err;
    st.supported = rc == 0 || (err != ENOTTY && err != EINVAL);
    st.ok = rc == 0;
    if rc == 0 { st.sync_recv = info.sync_recv; st.async_recv = info.async_recv; }
    unsafe { close(fd) };
    st
}

/// Faithful port of binder_freeze_set(): BINDER_FREEZE ioctl with up to 4
/// retries on EAGAIN (only while enabling), 40ms apart, then re-reads
/// status via binder_get_status() to fill in sync/async counts.
fn binder_freeze_set(pid: i32, enable: bool, timeout_ms: i64) -> BinderStatus {
    let mut st = BinderStatus::default();
    let (fd, dev) = open_binder_device();
    st.device = dev;
    if fd < 0 { st.err = errno_now(); return st; }
    let mut info = BinderFreezeInfo { pid: pid as u32, enable: if enable {1} else {0}, timeout_ms: if timeout_ms < 0 { 0 } else { timeout_ms as u32 } };
    let mut rc = -1;
    let mut last_errno = 0;
    for attempt in 0..4 {
        rc = unsafe { ioctl(fd, BINDER_FREEZE, &mut info as *mut _ as *mut c_void) };
        if rc == 0 { break; }
        last_errno = errno_now();
        if last_errno == EINTR { continue; }
        if enable && last_errno == EAGAIN && attempt < 3 {
            std::thread::sleep(Duration::from_millis(40));
            continue;
        }
        break;
    }
    st.err = if rc == 0 { 0 } else if last_errno != 0 { last_errno } else { errno_now() };
    st.supported = rc == 0 || (st.err != ENOTTY && st.err != EINVAL);
    st.ok = rc == 0;
    let after = binder_get_status(pid);
    if after.ok { st.sync_recv = after.sync_recv; st.async_recv = after.async_recv; st.supported = true; }
    unsafe { close(fd) };
    st
}

/// Faithful port of print_binder_fields().
fn binder_fields(prefix: &str, st: &BinderStatus) -> String {
    format!(
        " {p}binderSupported={} {p}binderOk={} {p}binderErrno={} {p}binderDevice={} {p}binderSyncRecv={} {p}binderAsyncRecv={}",
        st.supported, st.ok, st.err, shell_sanitize(st.device), st.sync_recv, st.async_recv, p = prefix
    )
}

fn usage() -> i32 {
    println!("CGFREEZER_USAGE commands=check-root,backend-probe,scan-package,freeze-pid,freeze-pid-list,freeze-package,kill-pid-list,kill-package,proc-snapshot,proc-wchan,uid-wchan,thaw-path,thaw-pid,thaw-uid,binder-info,watch-logd,daemon");
    64
}

fn unknown_usage(cmd: &str) -> i32 {
    println!("CGFREEZER_USAGE unknown={}", shell_sanitize(cmd));
    64
}

fn bounded_timeout_ms(v: i64, d: i64) -> i64 {
    if v < 100 || v > 5000 { d } else { v }
}

fn parse_i(s: Option<&String>, d: i32) -> i32 {
    s.map(|v| parse_int_arg_rs(v, d)).unwrap_or(d)
}
fn parse_ms(s: Option<&String>, d: i64) -> i64 {
    s.map(|v| parse_int_arg_rs(v, d as i32) as i64).unwrap_or(d)
}

fn read_file_c_bytes(path: &str, cap: usize) -> Option<Vec<u8>> {
    if cap == 0 { return None; }
    let mut f = File::open(path).ok()?;
    let mut buf = vec![0u8; cap.saturating_sub(1)];
    let n = match f.read(&mut buf) {
        Ok(n) => n,
        Err(_) => return None,
    };
    buf.truncate(n);
    while matches!(buf.last(), Some(b'\n' | b'\r' | b' ' | b'\t')) { buf.pop(); }
    Some(buf)
}

fn read_file_c(path: &str, cap: usize) -> Option<String> {
    read_file_c_bytes(path, cap).map(|buf| String::from_utf8_lossy(&buf).into_owned())
}

fn read_cmdline_c(pid: i32, cap: usize) -> Option<String> {
    let buf = read_file_c_bytes(&format!("/proc/{}/cmdline", pid), cap)?;
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    Some(String::from_utf8_lossy(&buf[..end]).into_owned())
}

fn parse_status_uid_c(pid: i32) -> i32 {
    let body = match read_file_c(&format!("/proc/{}/status", pid), 4096) { Some(v) => v, None => return -1 };
    for line in body.split('\n') {
        if let Some(rest) = line.strip_prefix("Uid:") {
            return atoi_prefix_i32(rest);
        }
    }
    -1
}


fn write_file_c(path: &str, value: &str) -> io::Result<()> {
    // Match C write_file(): open existing path O_WRONLY|O_CLOEXEC only
    // (no O_CREAT/O_TRUNC), perform exactly one write(), save errno before
    // close(), and treat any short write as failure.
    let cpath = CString::new(path).map_err(|_| io::Error::from_raw_os_error(EINVAL))?;
    let fd = unsafe { open(cpath.as_ptr(), C_O_WRONLY | C_O_CLOEXEC, 0) };
    if fd < 0 { return Err(io::Error::from_raw_os_error(errno_now())); }
    let bytes = value.as_bytes();
    let n = unsafe { write(fd, bytes.as_ptr() as *const c_void, bytes.len()) };
    let saved = errno_now();
    unsafe { close(fd); }
    if n != bytes.len() as isize {
        return Err(io::Error::from_raw_os_error(if saved != 0 { saved } else { 5 /* EIO */ }));
    }
    Ok(())
}

fn c_trim_start_ascii_space(s: &str) -> &str {
    s.trim_start_matches(|c: char| matches!(c, ' ' | '\t' | '\n' | '\r' | '\u{000b}' | '\u{000c}'))
}

fn parse_unified_path_rs(raw: &str, cg_cap: usize) -> Option<String> {
    if cg_cap == 0 { return None; }
    for line in raw.split('\n') {
        if let Some(mut path) = line.strip_prefix("0::") {
            path = path.trim_start_matches(|c: char| c == ' ' || c == '\t');
            let rel = if path.is_empty() {
                "/".to_string()
            } else if path.starts_with('/') {
                path.to_string()
            } else {
                format!("/{}", path)
            };
            return Some(c_truncate_bytes(&rel, cg_cap.saturating_sub(1)));
        }
    }
    None
}

fn c_truncate_bytes(s: &str, max_bytes: usize) -> String {
    if s.len() <= max_bytes { return s.to_string(); }
    let mut end = max_bytes;
    while end > 0 && !s.is_char_boundary(end) { end -= 1; }
    s[..end].to_string()
}

fn cg_v2_dir_for_pid_result(pid: i32) -> Result<PathBuf, i32> {
    let body = read_file_c(&format!("/proc/{}/cgroup", pid), 16_384).ok_or(-1)?;
    let cg = parse_unified_path_rs(&body, 1024).ok_or(-2)?;
    if cg == "/" { Ok(PathBuf::from("/sys/fs/cgroup")) }
    else { Ok(Path::new("/sys/fs/cgroup").join(cg.trim_start_matches('/'))) }
}

fn cg_v2_dir_for_pid(pid: i32) -> Option<PathBuf> {
    cg_v2_dir_for_pid_result(pid).ok()
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CgFreezeBackend { Unknown, V2, V1, None }
impl CgFreezeBackend {
    fn name(self) -> &'static str {
        match self { CgFreezeBackend::V2 => "v2", CgFreezeBackend::V1 => "v1", CgFreezeBackend::None => "none", CgFreezeBackend::Unknown => "unknown" }
    }
}

thread_local! {
    static G_FREEZE_BACKEND: RefCell<CgFreezeBackend> = RefCell::new(CgFreezeBackend::Unknown);
    static G_FREEZE_BACKEND_REASON: RefCell<String> = RefCell::new(String::new());
    static G_FREEZE_BACKEND_V1_MOUNT: RefCell<String> = RefCell::new(String::new());
    static G_FREEZE_BACKEND_PROBE_MS: RefCell<i64> = RefCell::new(0);
    static G_FREEZE_BACKEND_LOGGED: RefCell<bool> = RefCell::new(false);
}

/// Faithful port of cgfb_v2_global_available().
fn cgfb_v2_global_available() -> (bool, String) {
    let root_c = CString::new("/sys/fs/cgroup").unwrap();
    if unsafe { access(root_c.as_ptr(), R_OK) } != 0 {
        return (false, format!("v2_root_missing_errno_{}", errno_now()));
    }
    let c_c = CString::new("/sys/fs/cgroup/cgroup.controllers").unwrap();
    if unsafe { access(c_c.as_ptr(), R_OK) } != 0 {
        return (false, format!("v2_controllers_missing_errno_{}", errno_now()));
    }
    (true, "v2_controllers_readable".to_string())
}

/// Faithful port of cgfb_v2_pid_available().
fn cgfb_v2_pid_available(pid: i32) -> (bool, String, String) {
    let dir = match cg_v2_dir_for_pid_result(pid) {
        Ok(d) => d,
        Err(pr) => return (false, format!("v2_path_resolve_{}", pr), String::new()),
    };
    let path = dir.join("cgroup.freeze");
    let events_path = events_path_for_freeze(&path);
    let path_c = match CString::new(path.as_os_str().as_bytes()) { Ok(c) => c, Err(_) => return (false, "v2_path_resolve_-1".to_string(), String::new()) };
    if unsafe { access(path_c.as_ptr(), R_OK | W_OK) } != 0 {
        return (false, format!("v2_freeze_not_rw_errno_{}", errno_now()), String::new());
    }
    let events_c = match CString::new(events_path.as_os_str().as_bytes()) { Ok(c) => c, Err(_) => return (false, "v2_events_not_readable_errno_-1".to_string(), String::new()) };
    if unsafe { access(events_c.as_ptr(), R_OK) } != 0 {
        return (false, format!("v2_events_not_readable_errno_{}", errno_now()), String::new());
    }
    (true, "v2_pid_cgroup_freeze_rw".to_string(), path.to_string_lossy().into_owned())
}

/// Faithful port of cgfb_v1_global_available(): also performs the
/// mkdir_p(speedbackup_frozen) side effect exactly like C, since the probe
/// itself is what causes the dedicated group to exist ahead of first freeze.
fn cgfb_v1_global_available() -> (bool, String, String) {
    let mount = match find_v1_freezer_mount() {
        Some(m) => m,
        None => return (false, "v1_mount_missing".to_string(), String::new()),
    };
    let group_dir = format!("{}/speedbackup_frozen", mount);
    if mkdir_p(&group_dir, 0o755).is_err() {
        return (false, format!("v1_group_mkdir_errno_{}", errno_now()), String::new());
    }
    let group_procs = format!("{}/cgroup.procs", group_dir);
    let group_state = format!("{}/freezer.state", group_dir);
    let gp_c = CString::new(group_procs).unwrap();
    if unsafe { access(gp_c.as_ptr(), W_OK) } != 0 {
        return (false, format!("v1_group_procs_not_writable_errno_{}", errno_now()), String::new());
    }
    let gs_c = CString::new(group_state).unwrap();
    if unsafe { access(gs_c.as_ptr(), W_OK | R_OK) } != 0 {
        return (false, format!("v1_group_state_not_rw_errno_{}", errno_now()), String::new());
    }
    (true, "v1_mount_group_rw".to_string(), mount)
}

/// Faithful port of cgfb_v1_pid_available().
fn cgfb_v1_pid_available(pid: i32) -> (bool, String, String) {
    let (ok, r1, mount) = cgfb_v1_global_available();
    if !ok { return (false, if r1.is_empty() { "v1_unavailable".to_string() } else { r1 }, String::new()); }
    if parse_v1_freezer_relpath(pid).is_none() {
        return (false, "v1_pid_no_freezer_controller".to_string(), String::new());
    }
    (true, "v1_pid_freezer_controller_rw".to_string(), mount)
}

/// Faithful port of cgfb_detect_global(): v2 first, then v1, else none.
fn cgfb_detect_global() -> (CgFreezeBackend, String, String) {
    let (v2_ok, r2) = cgfb_v2_global_available();
    if v2_ok { return (CgFreezeBackend::V2, r2, String::new()); }
    let (v1_ok, r1, v1_mount) = cgfb_v1_global_available();
    if v1_ok {
        return (CgFreezeBackend::V1, format!("v2_unavailable_{}_v1_{}", if r2.is_empty() { "unknown".to_string() } else { r2 }, if r1.is_empty() { "ok".to_string() } else { r1 }), v1_mount);
    }
    (CgFreezeBackend::None, format!("no_v2_{}_no_v1_{}", if r2.is_empty() { "unknown".to_string() } else { r2 }, if r1.is_empty() { "unknown".to_string() } else { r1 }), String::new())
}

/// Faithful port of cgfb_ensure_global(): detect once per process lifetime
/// (thread_local cache, matching C's static globals - safe because the
/// daemon is single-threaded), log CGFREEZER_BACKEND_SELECT exactly once.
fn cgfb_ensure_global(emit_log: bool) -> CgFreezeBackend {
    let cached = G_FREEZE_BACKEND.with(|c| *c.borrow());
    if cached != CgFreezeBackend::Unknown { return cached; }
    let start = Instant::now();
    let (b, reason, v1_mount) = cgfb_detect_global();
    G_FREEZE_BACKEND.with(|c| *c.borrow_mut() = b);
    G_FREEZE_BACKEND_REASON.with(|c| *c.borrow_mut() = if reason.is_empty() { "unknown".to_string() } else { reason.clone() });
    G_FREEZE_BACKEND_V1_MOUNT.with(|c| *c.borrow_mut() = if v1_mount.is_empty() { "-".to_string() } else { v1_mount.clone() });
    let elapsed = start.elapsed().as_millis() as i64;
    G_FREEZE_BACKEND_PROBE_MS.with(|c| *c.borrow_mut() = elapsed);
    let already_logged = G_FREEZE_BACKEND_LOGGED.with(|c| *c.borrow());
    if emit_log && !already_logged {
        let r = G_FREEZE_BACKEND_REASON.with(|c| c.borrow().clone());
        let vm = G_FREEZE_BACKEND_V1_MOUNT.with(|c| c.borrow().clone());
        println!("CGFREEZER_BACKEND_SELECT ok={} preferred={} reason={} v1Mount={} elapsedMs={} cache=true", b != CgFreezeBackend::None, b.name(), shell_sanitize(&r), shell_sanitize(&vm), elapsed);
        G_FREEZE_BACKEND_LOGGED.with(|c| *c.borrow_mut() = true);
    }
    b
}

/// Faithful port of cgfb_select_for_pid(): resolves the actual backend to
/// use for a specific pid, falling back v2->v1 (or logging a per-pid
/// unavailable event) rather than trusting the cached global preference
/// blindly for every pid.
fn cgfb_select_for_pid(pid: i32, emit_log: bool) -> CgFreezeBackend {
    let preferred = cgfb_ensure_global(emit_log);
    if preferred == CgFreezeBackend::V2 {
        let (v2_ok, v2_reason, _) = cgfb_v2_pid_available(pid);
        if v2_ok { return CgFreezeBackend::V2; }
        let (v1_ok, v1_reason, v1_mount) = cgfb_v1_pid_available(pid);
        if v1_ok {
            if emit_log {
                println!("CGFREEZER_BACKEND_SELECT ok=true preferred=v1 reason=v2_pid_unavailable_v1_fallback pid={} v2Reason={} v1Reason={} v1Mount={} cacheFallback=pid-local", pid, shell_sanitize(&v2_reason), shell_sanitize(&v1_reason), shell_sanitize(&v1_mount));
            }
            return CgFreezeBackend::V1;
        }
        if emit_log {
            println!("CGFREEZER_BACKEND_SELECT ok=false preferred=none reason=v2_pid_unavailable_no_v1 pid={} v2Reason={} v1Reason={}", pid, shell_sanitize(&v2_reason), shell_sanitize(&v1_reason));
        }
        return CgFreezeBackend::None;
    }
    if preferred == CgFreezeBackend::V1 {
        let (v1_ok, v1_reason, _) = cgfb_v1_pid_available(pid);
        if v1_ok { return CgFreezeBackend::V1; }
        if emit_log {
            println!("CGFREEZER_BACKEND_SELECT ok=false preferred=none reason=v1_pid_unavailable pid={} v1Reason={}", pid, shell_sanitize(&v1_reason));
        }
        return CgFreezeBackend::None;
    }
    CgFreezeBackend::None
}

/// Faithful port of cmd_backend_probe(): a one-shot, non-cached snapshot of
/// every backend-relevant fact, independent of the cgfb_ensure_global()
/// cache (which is why it recomputes preferred via cgfb_detect_global()
/// directly rather than reading the thread_local cache).
fn cmd_backend_probe() -> i32 {
    let st = Instant::now();
    let root_c = CString::new("/sys/fs/cgroup").unwrap();
    let v2_root = unsafe { access(root_c.as_ptr(), R_OK) } == 0;
    let cc_c = CString::new("/sys/fs/cgroup/cgroup.controllers").unwrap();
    let v2_controllers = unsafe { access(cc_c.as_ptr(), R_OK) } == 0;
    let controllers = if v2_controllers { read_file_c("/sys/fs/cgroup/cgroup.controllers", 4096).unwrap_or_default() } else { String::new() };
    let (v1_ok, _, v1_mount) = cgfb_v1_global_available();
    let (preferred, preferred_reason, _) = cgfb_detect_global();
    let (fd, binder_dev) = open_binder_device();
    let binder_ok = fd >= 0;
    if fd >= 0 { unsafe { close(fd) }; }
    let ck_c = CString::new("/sys/fs/cgroup/cgroup.kill").unwrap();
    let cgroup_kill_root = unsafe { access(ck_c.as_ptr(), W_OK) } == 0;
    println!(
        "CGFREEZER_BACKEND_PROBE ok=true preferred={} preferredReason={} v2Root={} v2ControllersReadable={} controllers={} v1Freezer={} v1Mount={} binderDevice={} binderPath={} cgroupKillRoot={} cgroupKillFastpath=exact-package-only elapsedMs={}",
        preferred.name(), shell_sanitize(&preferred_reason), v2_root, v2_controllers, shell_sanitize(&controllers),
        v1_ok, shell_sanitize(if v1_ok { &v1_mount } else { "-" }), binder_ok, shell_sanitize(binder_dev), cgroup_kill_root,
        monotonic_ms(&st)
    );
    0
}

fn normalize_freeze(v: &str) -> char {
    let t = c_trim_start_ascii_space(v);
    match t.chars().next() {
        Some('0') => '0',
        Some('1') => '1',
        _ => '-',
    }
}

/// Faithful port of parse_events_value(): scans cgroup.events lines of the
/// form "key value" for the requested key.
fn parse_events_value(events: &str, key: &str) -> char {
    for line in events.lines() {
        if let Some(rest) = line.strip_prefix(key) {
            if let Some(v) = rest.strip_prefix(' ') {
                match c_trim_start_ascii_space(v).chars().next() {
                    Some('0') => return '0',
                    Some('1') => return '1',
                    _ => return '-',
                }
            }
        }
    }
    '-'
}

fn events_path_for_freeze(freeze_path: &Path) -> PathBuf {
    freeze_path.parent().map(|p| p.join("cgroup.events")).unwrap_or_else(|| PathBuf::from("cgroup.events"))
}

/// Faithful port of wait_frozen(): polls cgroup.events "frozen" key every
/// 20ms until it equals `expected` or the deadline passes. Returns
/// (matched, last_frozen_char, elapsed_ms).
fn wait_frozen(freeze_path: &Path, expected: char, timeout_ms: i64) -> (bool, char, i64) {
    let events_path = events_path_for_freeze(freeze_path);
    let start = Instant::now();
    let deadline_ms = if timeout_ms < 1 { 1 } else { timeout_ms };
    let mut last_frozen = '-';
    loop {
        if let Some(ev) = read_file_c(&events_path.to_string_lossy(), MAX_TEXT) {
            let f = parse_events_value(&ev, "frozen");
            last_frozen = f;
            if f == expected { return (true, last_frozen, start.elapsed().as_millis() as i64); }
        }
        if start.elapsed().as_millis() as i64 >= deadline_ms { break; }
        std::thread::sleep(Duration::from_millis(20));
    }
    (false, last_frozen, start.elapsed().as_millis() as i64)
}

/// Faithful port of cmd_freeze_pid_v2(): resolves the pid's live cgroup.freeze
/// path, coordinates a binder freeze (BINDER_FREEZE ioctl) before the cgroup
/// write - with rollback if the cgroup write subsequently fails - then
/// verifies via cgroup.events "frozen" key, matching C's full safety
/// sequence rather than the previous bare fs::write with no binder
/// coordination and no events-file verification.
fn cmd_freeze_pid_v2(pid: i32, timeout_ms: i64) -> i32 {
    let st = Instant::now();
    let uid = parse_status_uid_c(pid);
    let cmd = read_cmdline_c(pid, 512).unwrap_or_default();
    let path = match cg_v2_dir_for_pid_result(pid) {
        Ok(dir) => dir.join("cgroup.freeze"),
        Err(pr) => {
            println!("CGFREEZER_FREEZE_DONE ok=false pid={} uid={} reason=path_resolve_{} elapsedMs={}", pid, uid, pr, monotonic_ms(&st));
            return 3;
        }
    };
    let events_path = events_path_for_freeze(&path);
    let before_freeze = normalize_freeze(&read_file_c(&path.to_string_lossy(), 64).unwrap_or_default());
    let before_frozen = parse_events_value(&read_file_c(&events_path.to_string_lossy(), MAX_TEXT).unwrap_or_default(), "frozen");
    let path_c = CString::new(path.as_os_str().as_bytes()).ok();
    let events_c = CString::new(events_path.as_os_str().as_bytes()).ok();
    let rw_ok = path_c.as_ref().map(|c| unsafe { access(c.as_ptr(), R_OK | W_OK) == 0 }).unwrap_or(false);
    let events_r_ok = events_c.as_ref().map(|c| unsafe { access(c.as_ptr(), R_OK) == 0 }).unwrap_or(false);
    if !rw_ok || !events_r_ok {
        println!("CGFREEZER_FREEZE_DONE ok=false pid={} uid={} path={} beforeFreeze={} beforeFrozen={} reason=not_rw_events elapsedMs={}",
            pid, uid, shell_sanitize(&path.to_string_lossy()), before_freeze, before_frozen, monotonic_ms(&st));
        return 4;
    }

    let already_frozen = before_freeze == '1' || before_frozen == '1';
    let binder_before = binder_get_status(pid);
    let binder_attempted = !already_frozen;
    let binder_freeze = if !already_frozen {
        binder_freeze_set(pid, true, if timeout_ms > 300 { timeout_ms } else { 300 })
    } else {
        binder_before.clone()
    };
    let binder_should_restore = binder_freeze.ok;

    if let Err(e) = write_file_c(&path.to_string_lossy(), "1\n") {
        if binder_should_restore { let _ = binder_freeze_set(pid, false, 0); }
        let write_err = e.raw_os_error().unwrap_or(-1);
        println!(
            "CGFREEZER_FREEZE_DONE ok=false pid={} uid={} path={} cmdline={} beforeFreeze={} beforeFrozen={} reason=write_errno_{} binderAttempted={} binderSkipped={}{}{}elapsedMs={}",
            pid, uid, shell_sanitize(&path.to_string_lossy()), shell_sanitize(&cmd), before_freeze, before_frozen, write_err,
            binder_attempted, if already_frozen { "already_frozen" } else { "false" },
            binder_fields("before", &binder_before), binder_fields("freeze", &binder_freeze), monotonic_ms(&st)
        );
        return 5;
    }

    let rb = normalize_freeze(&read_file_c(&path.to_string_lossy(), 64).unwrap_or_default());
    let (event_ok, last_frozen, wait_elapsed) = wait_frozen(&path, '1', timeout_ms);
    let ok = rb == '1' && event_ok;
    if !ok && binder_should_restore { let _ = binder_freeze_set(pid, false, 0); }
    let binder_barrier_ok = !binder_attempted || binder_freeze.ok || !binder_freeze.supported || binder_freeze.err == EAGAIN;
    println!(
        "CGFREEZER_FREEZE_DONE ok={} pid={} uid={} path={} cmdline={} beforeFreeze={} beforeFrozen={} readback={} eventOk={} frozen={} waitMs={} reason={} binderAttempted={} binderSkipped={}{}{} binderBarrierOk={} elapsedMs={}",
        ok, pid, uid, shell_sanitize(&path.to_string_lossy()), shell_sanitize(&cmd), before_freeze, before_frozen, rb, event_ok, last_frozen, wait_elapsed,
        if ok { "ok" } else { "verify_failed" }, binder_attempted, if already_frozen { "already_frozen" } else { "false" },
        binder_fields("before", &binder_before), binder_fields("freeze", &binder_freeze), binder_barrier_ok, monotonic_ms(&st)
    );
    if ok { 0 } else { 6 }
}

// Faithful port of find_v1_freezer_mount(): parses /proc/mounts for a
// "cgroup" fstype mount whose options list contains "freezer"; falls back
// to probing a few well-known mount points for read/write access.
extern "C" {
    fn mkdir(path: *const std::os::raw::c_char, mode: u32) -> c_int;
}
const ANDROID_EEXIST: i32 = 17;

/// Faithful port of mkdir_p(): creates each path component with an explicit
/// mode (0755 for every call site in this file), tolerating EEXIST. Unlike
/// fs::create_dir_all(), which creates directories at a mode derived from
/// the process umask, this always yields exactly `mode` regardless of the
/// caller's umask - matching what was actually verified on a real Android
/// device (a device-specific umask could otherwise leave the dedicated
/// freezer cgroup with different permissions than the C build produced).
fn mkdir_p(path: &str, mode: u32) -> io::Result<()> {
    if path.is_empty() { return Err(io::Error::new(io::ErrorKind::InvalidInput, "empty path")); }
    let trimmed = path.trim_end_matches('/');
    let bytes = trimmed.as_bytes();
    let mut component_end = 1usize; // skip a possible leading '/' exactly like C's `q = tmp + 1`
    while component_end < bytes.len() {
        if bytes[component_end] == b'/' {
            let partial = &trimmed[..component_end];
            let c = CString::new(partial).map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "nul in path"))?;
            let rc = unsafe { mkdir(c.as_ptr(), mode) };
            if rc != 0 {
                let e = errno_now();
                if e != ANDROID_EEXIST { return Err(io::Error::from_raw_os_error(e)); }
            }
        }
        component_end += 1;
    }
    let c = CString::new(trimmed).map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "nul in path"))?;
    let rc = unsafe { mkdir(c.as_ptr(), mode) };
    if rc != 0 {
        let e = errno_now();
        if e != ANDROID_EEXIST { return Err(io::Error::from_raw_os_error(e)); }
    }
    Ok(())
}

fn token_list_contains_c(list:&str, needle:&str)->bool{
    if needle.is_empty(){return false;}
    let b=list.as_bytes(); let n=needle.as_bytes(); let mut i=0usize;
    while i<b.len(){
        while i<b.len() && matches!(b[i],b','|b' '|b'\t'){i+=1;}
        if i+n.len()<=b.len() && &b[i..i+n.len()]==n {
            let j=i+n.len();
            if j==b.len() || matches!(b[j],b','|b' '|b'\t'|b'\n'|b'\r'){return true;}
        }
        while i<b.len() && !matches!(b[i],b','|b' '|b'\t'|b'\n'|b'\r'){i+=1;}
    }
    false
}

fn c_ascii_ws_fields(line:&str, max_fields:usize)->Vec<&str>{
    let b=line.as_bytes(); let mut out=Vec::new(); let mut i=0usize;
    while i<b.len() && out.len()<max_fields{
        while i<b.len() && matches!(b[i],b' '|b'\t'|b'\n'|b'\r'|0x0b|0x0c){i+=1;}
        if i>=b.len(){break;}
        let st=i;
        while i<b.len() && !matches!(b[i],b' '|b'\t'|b'\n'|b'\r'|0x0b|0x0c){i+=1;}
        if let Ok(v)=std::str::from_utf8(&b[st..i]){out.push(v);} else {break;}
    }
    out
}

fn find_v1_freezer_mount() -> Option<String> {
    // C read_file(..., MAX_TEXT) performs a single <=16383-byte read and
    // trims only trailing ASCII space/TAB/CR/LF before strtok_r("\\n").
    if let Some(mounts)=read_file_c("/proc/mounts",16_384){
        for line in mounts.split('\n'){
            let f=c_ascii_ws_fields(line,4);
            if f.len()==4 {
                // sscanf widths: src 255, mnt 2047, fstype 63, opts 1023.
                let src=c_truncate_bytes(f[0],255);
                let mnt=c_truncate_bytes(f[1],2047);
                let fstype=c_truncate_bytes(f[2],63);
                let opts=c_truncate_bytes(f[3],1023);
                let _=src;
                if fstype=="cgroup" && token_list_contains_c(&opts,"freezer"){return Some(mnt);}
            }
        }
    }
    for fb in ["/sys/fs/cgroup/freezer","/dev/freezer","/acct/freezer"]{
        // p1/p2 are char[MAX_PATH_LEN], so snprintf truncates to 2047 bytes.
        let p1=c_truncate_bytes(&format!("{}/cgroup.procs",fb),2047);
        let p2=c_truncate_bytes(&format!("{}/freezer.state",fb),2047);
        let w_ok=CString::new(p1).ok().map(|c|unsafe{access(c.as_ptr(),W_OK)==0}).unwrap_or(false);
        let r_ok=CString::new(p2).ok().map(|c|unsafe{access(c.as_ptr(),R_OK)==0}).unwrap_or(false);
        if w_ok||r_ok{return Some(fb.to_string());}
    }
    None
}

fn parse_v1_freezer_relpath(pid:i32)->Option<String>{
    let raw=read_file_c(&format!("/proc/{}/cgroup",pid),16_384)?;
    for line0 in raw.split('\n'){
        // C copies each logical line into tmp[2048] before parsing it.
        let line=c_truncate_bytes(line0,2047);
        let c1=match line.find(':'){Some(v)=>v,None=>continue};
        let rest=&line[c1+1..];
        let c2rel=match rest.find(':'){Some(v)=>v,None=>continue};
        let controllers=&rest[..c2rel];
        let rel=&rest[c2rel+1..];
        if token_list_contains_c(controllers,"freezer"){
            let val=if rel.is_empty(){"/".to_string()}else if rel.starts_with('/') {rel.to_string()} else {format!("/{}",rel)};
            // Actual callers use rel[1024].
            return Some(c_truncate_bytes(&val,1023));
        }
    }
    None
}
fn join_v1_path(mount: &str, rel: &str, leaf: &str) -> String {
    if rel.is_empty() || rel == "/" { format!("{}/{}", mount, leaf) } else { format!("{}{}/{}", mount, rel, leaf) }
}

fn normalize_v1_state(v: &str) -> char {
    let t = c_trim_start_ascii_space(v);
    if t.len() >= 6 && t[..6].eq_ignore_ascii_case("FROZEN") { '1' }
    else if t.len() >= 6 && t[..6].eq_ignore_ascii_case("THAWED") { '0' }
    else if t.len() >= 8 && t[..8].eq_ignore_ascii_case("FREEZING") { 'P' }
    else { '-' }
}

/// Faithful port of wait_v1_state(): polls freezer.state every 20ms.
fn wait_v1_state(state_path: &str, expected: char, timeout_ms: i64) -> (bool, char, i64) {
    let start = Instant::now();
    let deadline_ms = if timeout_ms < 1 { 1 } else { timeout_ms };
    let mut last = '-';
    loop {
        if let Some(buf) = read_file_c(state_path, 4096) {
            let s = normalize_v1_state(&buf);
            last = s;
            if s == expected { return (true, last, start.elapsed().as_millis() as i64); }
        }
        if start.elapsed().as_millis() as i64 >= deadline_ms { break; }
        std::thread::sleep(Duration::from_millis(20));
    }
    (false, last, start.elapsed().as_millis() as i64)
}

fn write_pid_to_procs(procs_path: &str, pid: i32) -> io::Result<()> {
    write_file_c(procs_path, &format!("{}\n", pid))
}

/// Faithful port of cmd_freeze_pid_v1(): unlike v2 (which freezes the
/// process's existing cgroup in place), v1 MOVES the target pid into a
/// dedicated "speedbackup_frozen" cgroup under the v1 freezer mount, then
/// freezes that dedicated cgroup - matching C exactly. The previous
/// implementation wrote FROZEN directly into the pid's own existing v1
/// freezer group in place, which is a different mechanism (it would freeze
/// every other process sharing that same v1 group too, not just the
/// target pid) - this is the single most safety-relevant v1 divergence
/// found in this port.
fn cmd_freeze_pid_v1(pid: i32, timeout_ms: i64) -> i32 {
    let st = Instant::now();
    let uid = parse_status_uid_c(pid);
    let cmd = read_cmdline_c(pid, 512).unwrap_or_default();
    let mount = match find_v1_freezer_mount() {
        Some(m) => m,
        None => {
            println!("CGFREEZER_FREEZE_V1_DONE ok=false pid={} uid={} backend=v1 reason=no_v1_mount elapsedMs={}", pid, uid, monotonic_ms(&st));
            return 10;
        }
    };
    let rel = match parse_v1_freezer_relpath(pid) {
        Some(r) => r,
        None => {
            println!("CGFREEZER_FREEZE_V1_DONE ok=false pid={} uid={} backend=v1 mount={} reason=no_freezer_controller elapsedMs={}", pid, uid, shell_sanitize(&mount), monotonic_ms(&st));
            return 11;
        }
    };
    let orig_procs = join_v1_path(&mount, &rel, "cgroup.procs");
    let orig_state = join_v1_path(&mount, &rel, "freezer.state");
    let group_dir = format!("{}/speedbackup_frozen", mount);
    let group_procs = format!("{}/cgroup.procs", group_dir);
    let group_state = format!("{}/freezer.state", group_dir);
    let before_freeze = normalize_v1_state(&read_file_c(&orig_state, 128).unwrap_or_default());
    if let Err(e) = mkdir_p(&group_dir, 0o755) {
        println!("CGFREEZER_FREEZE_V1_DONE ok=false pid={} uid={} backend=v1 mount={} reason=mkdir_errno_{} elapsedMs={}", pid, uid, shell_sanitize(&mount), e.raw_os_error().unwrap_or(-1), monotonic_ms(&st));
        return 12;
    }
    let _ = write_file_c(&group_state, "THAWED\n");
    if let Err(e) = write_pid_to_procs(&group_procs, pid) {
        println!("CGFREEZER_FREEZE_V1_DONE ok=false pid={} uid={} backend=v1 path={} groupProcs={} beforeFreeze={} beforeFrozen={} reason=move_errno_{} elapsedMs={}",
            pid, uid, shell_sanitize(&orig_procs), shell_sanitize(&group_procs), before_freeze, before_freeze, e.raw_os_error().unwrap_or(-1), monotonic_ms(&st));
        return 13;
    }
    if let Err(e) = write_file_c(&group_state, "FROZEN\n") {
        println!("CGFREEZER_FREEZE_V1_DONE ok=false pid={} uid={} backend=v1 path={} reason=state_errno_{} elapsedMs={}", pid, uid, shell_sanitize(&orig_procs), e.raw_os_error().unwrap_or(-1), monotonic_ms(&st));
        return 14;
    }
    let (ok, last, wait_ms) = wait_v1_state(&group_state, '1', timeout_ms);
    println!(
        "CGFREEZER_FREEZE_DONE ok={} backend=v1 pid={} uid={} path={} groupState={} cmdline={} beforeFreeze={} beforeFrozen={} readback={} eventOk={} frozen={} waitMs={} reason={} binderAttempted=false binderSkipped=v1_no_binder binderBarrierOk=true elapsedMs={}",
        ok, pid, uid, shell_sanitize(&orig_procs), shell_sanitize(&group_state), shell_sanitize(&cmd),
        before_freeze, before_freeze, last, ok, last, wait_ms, if ok { "ok_v1" } else { "v1_verify_failed" }, monotonic_ms(&st)
    );
    if ok { 0 } else { 15 }
}

/// Faithful port of cmd_thaw_pid_v1(): reverses the v1 "move to dedicated
/// cgroup" freeze by moving the pid back into its ORIGINAL cgroup.procs
/// (orig_procs), after first thawing the dedicated speedbackup_frozen group
/// so the move isn't blocked. If target=='1' (caller wants the pid to end
/// up frozen again after being moved back - used for a "restore original
/// membership but keep it frozen there" path), re-freezes the original
/// cgroup's freezer.state afterward. The previous implementation never
/// moved the pid anywhere - it just wrote THAWED in place, which does not
/// reverse the v1 freeze mechanism (the pid remains in the wrong,
/// unmanaged dedicated cgroup even after "thawing").
fn cmd_thaw_pid_v1(pid: i32, orig_procs: &str, target: char, _timeout_ms: i64) -> i32 {
    let st = Instant::now();
    if orig_procs.is_empty() || !orig_procs.contains("cgroup.procs") {
        println!("CGFREEZER_THAW_V1_DONE ok=false pid={} backend=v1 reason=bad_path elapsedMs={}", pid, monotonic_ms(&st));
        return 20;
    }
    let mount = match find_v1_freezer_mount() {
        Some(m) => m,
        None => {
            println!("CGFREEZER_THAW_V1_DONE ok=false pid={} backend=v1 path={} reason=no_v1_mount elapsedMs={}", pid, shell_sanitize(orig_procs), monotonic_ms(&st));
            return 21;
        }
    };
    let group_dir = format!("{}/speedbackup_frozen", mount);
    let group_state = format!("{}/freezer.state", group_dir);
    if target == '0' {
        let _ = write_file_c(&group_state, "THAWED\n");
        let _ = wait_v1_state(&group_state, '0', 1000);
    }
    let move_result = write_pid_to_procs(orig_procs, pid);
    let move_err = move_result.as_ref().err().and_then(|e| e.raw_os_error()).unwrap_or(0);
    if target == '1' {
        if let Some(slash) = orig_procs.rfind('/') {
            let orig_state = format!("{}/freezer.state", &orig_procs[..slash]);
            let _ = write_file_c(&orig_state, "FROZEN\n");
        }
    }
    let ok = move_result.is_ok();
    println!(
        "CGFREEZER_THAW_DONE ok={} backend=v1 pid={} path={} target={} readback={} eventOk={} frozen={} waitMs=0 cgroupOk={} binderAttempted=false binderSkipped=v1_no_binder reason={} binderRestoreOk=true elapsedMs={}{}",
        ok, pid, shell_sanitize(orig_procs), target, target, ok, target, ok,
        if ok { "ok_v1" } else { "move_errno" }, monotonic_ms(&st),
        if !ok { format!(" errno={}", move_err) } else { String::new() }
    );
    if ok { 0 } else { 22 }
}

/// Faithful port of cmd_thaw_path_internal(): dispatches to the v1 restore
/// path when the caller passed a pid AND the saved path is a v1
/// cgroup.procs file; otherwise writes target ('0'/'1') directly to a v2
/// cgroup.freeze-style path and verifies via cgroup.events, coordinating a
/// binder unfreeze when actually thawing (target=='0') with a known pid.
fn cmd_thaw_path_internal(pid: i32, path: &str, target: char, timeout_ms: i64, have_pid: bool) -> i32 {
    let st = Instant::now();
    if path.is_empty() || (target != '0' && target != '1') {
        println!("CGFREEZER_THAW_DONE ok=false reason=bad_args elapsedMs={}", monotonic_ms(&st));
        return 2;
    }
    if have_pid && path.contains("cgroup.procs") {
        return cmd_thaw_pid_v1(pid, path, target, timeout_ms);
    }
    let value = format!("{}\n", target);
    if let Err(e) = write_file_c(path, &value) {
        println!("CGFREEZER_THAW_DONE ok=false pid={} path={} target={} reason=write_errno_{} elapsedMs={}",
            if have_pid { pid } else { -1 }, shell_sanitize(path), target, e.raw_os_error().unwrap_or(-1), monotonic_ms(&st));
        return 3;
    }
    let rb = normalize_freeze(&read_file_c(path, 64).unwrap_or_default());
    let (event_ok, last_frozen, wait_elapsed) = wait_frozen(Path::new(path), target, timeout_ms);
    let cgroup_ok = rb == target && event_ok;
    let binder_attempted = have_pid && target == '0';
    let binder_skipped_originally_frozen = target == '1';
    let binder_thaw = if binder_attempted { binder_freeze_set(pid, false, 0) } else { BinderStatus::default() };
    let ok = cgroup_ok;
    println!(
        "CGFREEZER_THAW_DONE ok={} pid={} path={} target={} readback={} eventOk={} frozen={} waitMs={} cgroupOk={} binderAttempted={} binderSkipped={} reason={}{} binderRestoreOk={} elapsedMs={}",
        ok, if have_pid { pid } else { -1 }, shell_sanitize(path), target, rb, event_ok, last_frozen, wait_elapsed, cgroup_ok,
        binder_attempted, if binder_skipped_originally_frozen { "originally_frozen" } else { "false" },
        if ok { "ok" } else { "verify_failed" }, binder_fields("thaw", &binder_thaw),
        !binder_attempted || binder_thaw.ok || !binder_thaw.supported || binder_thaw.err == EINVAL, monotonic_ms(&st)
    );
    if ok { 0 } else { 4 }
}

fn is_app_uid_value(uid: i32) -> bool {
    if uid < 10000 { return false; }
    let appid = uid % 100000;
    (10000..99000).contains(&appid)
}

/// Faithful port of collect_uid_paths_and_pids(): a few guessed v2 uid
/// group paths, plus a full /proc scan collecting every pid with this
/// exact uid and its resolved cgroup.freeze path (deduplicated).
fn uid_path_add(paths: &mut Vec<String>, path: String) -> bool {
    if path.is_empty() || paths.len() >= MAX_UID_PATHS || paths.iter().any(|p| p == &path) { return false; }
    paths.push(path);
    true
}

fn uid_pid_add(pids: &mut Vec<i32>, pid: i32) -> bool {
    if pid <= 0 || pids.len() >= MAX_UID_PIDS || pids.iter().any(|p| *p == pid) { return false; }
    pids.push(pid);
    true
}

fn collect_uid_paths_and_pids(uid: i32) -> (Vec<String>, Vec<i32>) {
    let mut paths: Vec<String> = Vec::new();
    let mut pids: Vec<i32> = Vec::new();
    for root in ["/sys/fs/cgroup", "/sys/fs/cgroup/apps", "/sys/fs/cgroup/app", "/sys/fs/cgroup/system"] {
        let p = format!("{}/uid_{}/cgroup.freeze", root, uid);
        if let Ok(c) = CString::new(p.clone()) {
            if unsafe { access(c.as_ptr(), R_OK | W_OK) == 0 } { let _ = uid_path_add(&mut paths, p); }
        }
    }
    if let Ok(entries) = fs::read_dir("/proc") {
        for ent in entries.flatten() {
            let name = ent.file_name().to_string_lossy().into_owned();
            if !name.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) { continue; }
            let pid: i32 = match name.parse() { Ok(v) if v > 0 => v, _ => continue };
            if parse_status_uid_c(pid) != uid { continue; }
            let _ = uid_pid_add(&mut pids, pid);
            if let Some(dir) = cg_v2_dir_for_pid(pid) {
                let p = dir.join("cgroup.freeze");
                let p_s = p.to_string_lossy().into_owned();
                if let Ok(c) = CString::new(p_s.clone()) {
                    if unsafe { access(c.as_ptr(), R_OK | W_OK) == 0 } { let _ = uid_path_add(&mut paths, p_s); }
                }
            }
        }
    }
    (paths, pids)
}

/// Faithful port of cmd_thaw_uid(): an "emergency, thaw everything we can
/// find for this uid" sweep - every v2 cgroup.freeze path found, the v1
/// dedicated speedbackup_frozen group if present, and a binder-unfreeze
/// pass over every matching pid. The previous implementation only thawed
/// the exact per-pid cgroup dirs it happened to resolve at call time (via
/// cg_v2_dir_for_pid/cg_v1_freezer_dir_for_pid on currently-alive pids),
/// with no binder coordination and no is_app_uid_value validation.
fn cmd_thaw_uid(uid_u: u32, timeout: i64) -> i32 {
    let st = Instant::now();
    let uid = uid_u as i32;
    if !is_app_uid_value(uid) {
        println!("CGFREEZER_THAW_UID_DONE ok=false uid={} reason=non_app_uid elapsedMs={}", uid, monotonic_ms(&st));
        return 64;
    }
    let timeout_ms = if timeout < 100 || timeout > 5000 { 1500 } else { timeout };
    let (paths, pids) = collect_uid_paths_and_pids(uid);
    let v1_state = find_v1_freezer_mount().map(|m| format!("{}/speedbackup_frozen/freezer.state", m));

    println!("CGFREEZER_THAW_UID_BEGIN ok=true uid={} timeoutMs={} paths={} pids={} emergencyOnly=true", uid, timeout_ms, paths.len(), pids.len());
    let mut ok_paths = 0u64;
    let mut fail_paths = 0u64;
    for p in &paths {
        let wr = write_file_c(p, "0\n");
        let (ev, last, waited) = if wr.is_ok() { wait_frozen(Path::new(p), '0', timeout_ms) } else { (false, '-', 0) };
        if ev { ok_paths += 1; } else { fail_paths += 1; }
        println!("CGFREEZER_THAW_UID_PATH ok={} uid={} path={} writeRc={} frozen={} waitMs={} errno={}",
            ev, uid, shell_sanitize(p), if wr.is_ok() {0} else {1}, last, waited, wr.err().and_then(|e| e.raw_os_error()).unwrap_or(0));
    }
    let mut v1_ok = 0i32;
    if let Some(v1s) = &v1_state {
        let w_ok = CString::new(v1s.as_str()).ok().map(|c| unsafe { access(c.as_ptr(), W_OK) == 0 }).unwrap_or(false);
        if w_ok {
            let wr = write_file_c(v1s, "THAWED\n");
            let (ev, last, waited) = if wr.is_ok() { wait_v1_state(v1s, '0', timeout_ms) } else { (false, '-', 0) };
            v1_ok = if ev { 1 } else { -1 };
            println!("CGFREEZER_THAW_UID_V1 ok={} uid={} state={} readback={} waitMs={}", ev, uid, shell_sanitize(v1s), last, waited);
        }
    }
    let (mut binder_ok, mut binder_fail, mut binder_unsupported) = (0u64, 0u64, 0u64);
    for pid in &pids {
        let bs = binder_freeze_set(*pid, false, 0);
        if bs.ok { binder_ok += 1; }
        else if !bs.supported || bs.err == ENOTTY || bs.err == EINVAL || bs.err == 2 /*ENOENT*/ || bs.err == 3 /*ESRCH*/ { binder_unsupported += 1; }
        else { binder_fail += 1; }
    }
    let nothing_found = paths.is_empty() && v1_ok == 0 && pids.is_empty();
    let ok = fail_paths == 0 && binder_fail == 0 && v1_ok >= 0;
    println!(
        "CGFREEZER_THAW_UID_DONE ok={} uid={} paths={} okPaths={} failPaths={} pids={} binderOk={} binderUnsupported={} binderFail={} v1={} nothingFound={} emergencyOnly=true elapsedMs={}",
        ok, uid, paths.len(), ok_paths, fail_paths, pids.len(), binder_ok, binder_unsupported, binder_fail, v1_ok, nothing_found, monotonic_ms(&st)
    );
    if ok { 0 } else { 12 }
}

fn cmd_check_root() -> i32 {
    // Faithful port of cmd_check_root(): this checks whether the cgroup v2
    // unified hierarchy is mounted and readable, NOT whether the caller is
    // root (the previous implementation checked getuid()==0 - a completely
    // different, unrelated question - and printed uid=/gid=/version= fields
    // that don't exist in the C reference's output at all).
    let root = Path::new("/sys/fs/cgroup").is_dir();
    let controllers_path = "/sys/fs/cgroup/cgroup.controllers";
    let controllers_path_c = CString::new(controllers_path).unwrap();
    let controllers_readable = unsafe { access(controllers_path_c.as_ptr(), R_OK) == 0 };
    let controllers = if controllers_readable {
        read_file_c(controllers_path, 4096).unwrap_or_default()
    } else {
        String::new()
    };
    println!(
        "CGFREEZER_CHECK_ROOT ok={} root={} controllersReadable={} controllers={}",
        root, root, controllers_readable, shell_sanitize(&controllers)
    );
    if root { 0 } else { 2 }
}

/// Compatibility wrapper for daemon parent-control status/probe commands
/// that only need the cached preferred backend + a human reason string,
/// without the full one-shot cmd_backend_probe() diagnostic snapshot.
fn preferred_backend() -> (&'static str, String) {
    let b = cgfb_ensure_global(false);
    let r = G_FREEZE_BACKEND_REASON.with(|c| c.borrow().clone());
    (b.name(), if r.is_empty() { "unknown".to_string() } else { r })
}

fn v1_mount_hint() -> String {
    cgfb_ensure_global(false);
    G_FREEZE_BACKEND_V1_MOUNT.with(|c| c.borrow().clone())
}

/// Faithful port of scan_package()'s row format: pid=/uid=/process= only -
/// no state/wchan fields (those belong to proc-snapshot's different schema,
/// which the previous shared print_scan_rows() helper incorrectly merged
/// with this one).
#[derive(Clone, Default)]
struct ScanItem { pid: i32, uid: i32, process: String }

#[derive(Default)]
struct ScanPackageResult { rc: i32, count: i32, csv: String }

fn is_package_process_name(cmd: &str, pkg: &str) -> bool {
    !cmd.is_empty() && !pkg.is_empty() && (cmd == pkg || (cmd.starts_with(pkg) && cmd.as_bytes().get(pkg.len()) == Some(&b':')))
}

fn scan_package_collect(pkg: &str, user_id: i32, print_lines: bool) -> ScanPackageResult {
    let mut out = ScanPackageResult::default();
    let entries = match fs::read_dir("/proc") {
        Ok(e) => e,
        Err(_) => { out.rc = -1; return out; }
    };
    for ent in entries.flatten() {
        let name = ent.file_name().to_string_lossy().into_owned();
        if !name.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) { continue; }
        let pid: i32 = match name.parse() { Ok(v) if v > 0 => v, _ => continue };
        let uid = parse_status_uid_c(pid);
        if uid >= 0 && user_id_from_uid_rs(uid as u32) != user_id { continue; }
        let cmd = read_cmdline_c(pid, 512).unwrap_or_default();
        if !is_package_process_name(&cmd, pkg) { continue; }
        out.count += 1;
        if print_lines {
            println!("CGFREEZER_SCAN_PID pid={} uid={} process={}", pid, uid, shell_sanitize(&cmd));
        }
        // C scan_package(): append to csv only when strlen(csv)+64+strlen(cmd)<MAX_TEXT.
        if out.csv.len() + 64 + cmd.len() < MAX_TEXT {
            if !out.csv.is_empty() { out.csv.push(','); }
            out.csv.push_str(&format!("{}:{}:{}", pid, uid, cmd));
        }
    }
    out.rc = 0;
    out
}

fn atoi_prefix_i32(s: &str) -> i32 {
    let mut it = s.trim_start_matches(|c: char| c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\u{000b}' || c == '\u{000c}').chars().peekable();
    let mut sign = 1i64;
    if let Some(&c) = it.peek() {
        if c == '-' { sign = -1; it.next(); }
        else if c == '+' { it.next(); }
    }
    let mut seen = false;
    let mut val = 0i64;
    while let Some(&c) = it.peek() {
        if !c.is_ascii_digit() { break; }
        seen = true;
        val = val.saturating_mul(10).saturating_add((c as u8 - b'0') as i64);
        it.next();
    }
    if !seen { return 0; }
    let v = sign.saturating_mul(val);
    if v > i32::MAX as i64 { i32::MAX } else if v < i32::MIN as i64 { i32::MIN } else { v as i32 }
}

fn parse_scan_csv_item_rs(item: &str) -> Option<ScanItem> {
    let c1 = item.find(':')?;
    let c2_rel = item[c1 + 1..].find(':')?;
    let c2 = c1 + 1 + c2_rel;
    let pid = atoi_prefix_i32(&item[..c1]);
    let uid = atoi_prefix_i32(&item[c1 + 1..c2]);
    if pid <= 0 || uid < 0 { return None; }
    Some(ScanItem { pid, uid, process: item[c2 + 1..].to_string() })
}

fn cmd_scan_package(pkg: &str, user: i32) -> i32 {
    let st = Instant::now();
    if !is_valid_pkg_name(pkg) {
        println!("CGFREEZER_SCAN_DONE ok=false package={} reason=bad_package elapsedMs={}", shell_sanitize(pkg), monotonic_ms(&st));
        return 2;
    }
    let scan = scan_package_collect(pkg, user, true);
    println!("CGFREEZER_SCAN_DONE ok={} package={} user={} count={} pids={} elapsedMs={}", scan.rc == 0, shell_sanitize(pkg), user, scan.count, shell_sanitize(&scan.csv), monotonic_ms(&st));
    if scan.rc == 0 { 0 } else { 3 }
}

/// Faithful port of cmd_proc_snapshot(): a distinct row schema from
/// scan-package (CGFREEZER_PROC_SNAPSHOT_ENTRY with ppid/state/oomAdj/
/// frozen/cgroup fields), plus the is_valid_pkg_name + user<0 bad_args
/// gate the previous implementation didn't have at all.
fn cmd_proc_snapshot(pkg: &str, user: i32) -> i32 {
    let st = Instant::now();
    if !is_valid_pkg_name(pkg) || user < 0 {
        println!("CGFREEZER_PROC_SNAPSHOT_DONE ok=false package={} user={} rows=0 reason=bad_args elapsedMs={}", shell_sanitize(pkg), user, monotonic_ms(&st));
        return 64;
    }
    println!("CGFREEZER_PROC_SNAPSHOT_BEGIN ok=true package={} user={}", shell_sanitize(pkg), user);
    let mut rows = 0u64;
    let mut errors = 0u64;
    let entries = match fs::read_dir("/proc") {
        Ok(r) => r,
        Err(e) => {
            println!("CGFREEZER_PROC_SNAPSHOT_DONE ok=false package={} user={} rows=0 reason=proc_open_errno_{} elapsedMs={}", shell_sanitize(pkg), user, e.raw_os_error().unwrap_or(-1), monotonic_ms(&st));
            return 3;
        }
    };
    for ent in entries.flatten() {
        let name = ent.file_name().to_string_lossy().into_owned();
        if !name.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) { continue; }
        let pid: i32 = match name.parse() { Ok(v) if v > 0 => v, _ => continue };
        let uid = parse_status_uid_c(pid);
        if uid < 0 || user_id_from_uid_rs(uid as u32) != user { continue; }
        let process = match read_cmdline_c(pid, 512) { Some(v) => v, None => continue };
        if !is_package_process_name(&process, pkg) { continue; }
        let mut cg = match read_file_c(&format!("/proc/{}/cgroup", pid), 1024) { Some(v) => v, None => { errors += 1; "-".to_string() } };
        cg = cg.chars().map(|c| if c=='\n'||c=='\r'||c=='\t'||c==' ' { '|' } else { c }).collect();
        println!(
            "CGFREEZER_PROC_SNAPSHOT_ENTRY package={} user={} pid={} ppid=0 uid={} state={} oomAdj={} frozen=unknown process={} cgroup={}",
            shell_sanitize(pkg), user, pid, uid, proc_state_char_rs(pid), read_oom_score_adj_rs(pid), shell_sanitize(&process), shell_sanitize(&cg)
        );
        rows += 1;
    }
    println!("CGFREEZER_PROC_SNAPSHOT_DONE ok=true package={} user={} rows={} errors={} hash=0 elapsedMs={}", shell_sanitize(pkg), user, rows, errors, monotonic_ms(&st));
    0
}

/// Faithful port of cmd_freeze_pid()'s v2-then-v1 dispatch (via
/// cgfb_select_for_pid): tries v2 first (the modern default on current
/// Android), falls back to v1 if this specific pid's cgroup doesn't expose
/// a usable cgroup.freeze file, and reports no_freezer_backend if neither
/// resolves. The previous implementation always called the simpler
/// write_freeze() path with no binder coordination and guessed the backend
/// from the returned file name instead of actually selecting one.
fn cmd_freeze_pid(pid: i32, timeout: i64) -> i32 {
    match cgfb_select_for_pid(pid, true) {
        CgFreezeBackend::V2 => cmd_freeze_pid_v2(pid, timeout),
        CgFreezeBackend::V1 => cmd_freeze_pid_v1(pid, timeout),
        _ => {
            let st = Instant::now();
            let uid = parse_status_uid_c(pid);
            let preferred = G_FREEZE_BACKEND.with(|c| (*c.borrow()).name());
            let global_reason = G_FREEZE_BACKEND_REASON.with(|c| {
                let r = c.borrow().clone();
                if r.is_empty() { "unknown".to_string() } else { r }
            });
            println!("CGFREEZER_FREEZE_DONE ok=false pid={} uid={} backend=none reason=no_freezer_backend preferred={} globalReason={} elapsedMs={}",
                pid, uid, preferred, shell_sanitize(&global_reason), monotonic_ms(&st));
            30
        }
    }
}

fn cmd_freeze_pid_list(user: i32, target: &str, timeout_in: i64) -> i32 {
    let st = Instant::now();
    if target.is_empty() {
        println!("CGFREEZER_FREEZE_PID_LIST_DONE ok=false user={} checked=0 frozen=0 failed=0 skipped=0 reason=empty elapsedMs={}", user, monotonic_ms(&st));
        return 64;
    }
    let pids = read_pid_targets(target);
    let timeout = if timeout_in < 100 || timeout_in > 5000 { 1500 } else { timeout_in };
    println!("CGFREEZER_FREEZE_PID_LIST_BEGIN ok=true user={} timeoutMs={} pids={}", user, timeout, shell_sanitize(target));
    let mut checked = 0u64; let mut frozen = 0u64; let mut failed = 0u64; let mut skipped = 0u64;
    for pid in pids {
        let uid = parse_status_uid_c(pid);
        if pid <= 0 || uid < 0 || (user >= 0 && user_id_from_uid_rs(uid as u32) != user) {
            skipped += 1;
            println!("CGFREEZER_FREEZE_PID_LIST_ENTRY ok=false pid={} uid={} reason=skip_bad_pid_or_user", pid, uid);
            continue;
        }
        checked += 1;
        // Route through cmd_freeze_pid so the full v1/v2 dispatch, binder
        // coordination, and detailed CGFREEZER_FREEZE_DONE line (matching
        // C's cmd_freeze_pid_list, which calls cmd_freeze_pid per item)
        // all happen here too - the previous implementation called the
        // bare write_freeze() with none of that.
        let cmd = read_cmdline_c(pid, 512).unwrap_or_default();
        let rc = cmd_freeze_pid(pid, timeout);
        if rc == 0 { frozen += 1; } else { failed += 1; }
        println!("CGFREEZER_FREEZE_PID_LIST_ENTRY ok={} pid={} uid={} rc={} process={}", rc == 0, pid, uid, rc, shell_sanitize(&cmd));
    }
    let ok = frozen > 0 && failed == 0;
    println!("CGFREEZER_FREEZE_PID_LIST_DONE ok={} user={} checked={} frozen={} failed={} skipped={} reason={} batch=true elapsedMs={}", ok, user, checked, frozen, failed, skipped, if ok {"ok"} else if frozen > 0 {"partial"} else {"none"}, monotonic_ms(&st));
    if frozen > 0 { 0 } else { 11 }
}


/// Faithful port of capture_v1_restore_path(): resolves the pid's current
/// v1 cgroup.procs path (for later restoration) and its freezer.state
/// before-value, purely for freeze-package's before/after reporting -
/// independent of whether v1 or v2 ends up actually being used to freeze it.
fn capture_v1_restore_path(pid: i32) -> Option<(String, char)> {
    let mount = find_v1_freezer_mount()?;
    let rel = parse_v1_freezer_relpath(pid)?;
    let orig_procs = join_v1_path(&mount, &rel, "cgroup.procs");
    let state_path = join_v1_path(&mount, &rel, "freezer.state");
    let before = normalize_v1_state(&read_file_c(&state_path, 128).unwrap_or_default());
    Some((orig_procs, before))
}

/// Faithful port of cmd_freeze_package(): the previous implementation
/// printed a much shorter, differently-shaped BEGIN/ENTRY/DONE line set
/// (missing backend=/path=/beforeFreeze=/beforeFrozen=/alreadyFrozen=/
/// requestAtomic=/transactionalRollback= entirely) - this was never
/// actually diffed field-by-field against the C reference before, only
/// checked for "does it actually freeze the right pids", which it did, but
/// the log format itself was materially different.
fn cmd_freeze_package(pkg: &str, user_id: i32, timeout_in: i64) -> i32 {
    let start = Instant::now();
    if !is_valid_pkg_name(pkg) || user_id < 0 {
        println!("CGFREEZER_FREEZE_PKG_DONE ok=false package={} user={} reason=bad_args elapsedMs={}", shell_sanitize(pkg), user_id, monotonic_ms(&start));
        return 64;
    }
    let timeout_ms = if timeout_in < 100 || timeout_in > 5000 { 1500 } else { timeout_in };

    let scan = scan_package_collect(pkg, user_id, false);
    println!(
        "CGFREEZER_FREEZE_PKG_BEGIN ok={} package={} user={} timeoutMs={} scanned={} requestAtomic=true transactionalRollback=false pids={}",
        scan.rc == 0, shell_sanitize(pkg), user_id, timeout_ms, scan.count, shell_sanitize(&scan.csv)
    );
    if scan.rc != 0 {
        println!("CGFREEZER_FREEZE_PKG_DONE ok=false package={} user={} scanned=0 checked=0 frozen=0 failed=0 reason=scan_failed elapsedMs={}", shell_sanitize(pkg), user_id, monotonic_ms(&start));
        return 3;
    }
    if scan.count <= 0 {
        println!("CGFREEZER_FREEZE_PKG_DONE ok=false package={} user={} scanned=0 checked=0 frozen=0 failed=0 reason=no_alive_pid elapsedMs={}", shell_sanitize(pkg), user_id, monotonic_ms(&start));
        return 10;
    }

    let (mut checked, mut frozen, mut failed, mut already) = (0i64, 0i64, 0i64, 0i64);
    let freeze_items: Vec<String> = c_truncate_bytes(&scan.csv, MAX_TEXT.saturating_sub(1))
        .split(',')
        .filter(|v| !v.is_empty())
        .map(|v| v.to_string())
        .collect();
    for item in &freeze_items {
        let t = match parse_scan_csv_item_rs(item) {
            Some(v) => v,
            None => {
                failed += 1;
                println!("CGFREEZER_FREEZE_PKG_ENTRY ok=false package={} user={} reason=bad_scan_item item={}", shell_sanitize(pkg), user_id, shell_sanitize(item));
                continue;
            }
        };
        checked += 1;
        // Capture "before" state for both backends prior to freezing, purely
        // for reporting - matches C's v2_before_freeze/v2_before_frozen and
        // v1_capture/v1_before snapshots taken ahead of cmd_freeze_pid().
        let v2_path = cg_v2_dir_for_pid(t.pid).map(|d| d.join("cgroup.freeze"));
        let (mut v2_before_freeze, mut v2_before_frozen) = ('-', '-');
        if let Some(p) = &v2_path {
            if let Some(rb) = read_file_c(&p.to_string_lossy(), 64) { v2_before_freeze = normalize_freeze(&rb); }
            if let Some(ev) = read_file_c(&events_path_for_freeze(p).to_string_lossy(), MAX_TEXT) { v2_before_frozen = parse_events_value(&ev, "frozen"); }
        }
        let v1_capture = capture_v1_restore_path(t.pid);

        let rc = cmd_freeze_pid(t.pid, timeout_ms);
        if rc != 0 {
            failed += 1;
            println!("CGFREEZER_FREEZE_PKG_ENTRY ok=false package={} user={} pid={} uid={} process={} rc={} reason=freeze_failed", shell_sanitize(pkg), user_id, t.pid, t.uid, shell_sanitize(&t.process), rc);
            continue;
        }

        let mut backend = "unknown";
        let mut restore_path = "-".to_string();
        let (mut before_freeze, mut before_frozen) = ('-', '-');
        let mut v2_frozen = false;
        if let Some(p) = &v2_path {
            let rb = read_file_c(&p.to_string_lossy(), 64).unwrap_or_default();
            let ev = read_file_c(&events_path_for_freeze(p).to_string_lossy(), MAX_TEXT).unwrap_or_default();
            v2_frozen = normalize_freeze(&rb) == '1' && parse_events_value(&ev, "frozen") == '1';
        }
        if v2_frozen {
            backend = "v2";
            restore_path = v2_path.as_ref().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
            before_freeze = v2_before_freeze;
            before_frozen = v2_before_frozen;
        } else if let Some((orig_procs, v1_before)) = &v1_capture {
            backend = "v1";
            restore_path = orig_procs.clone();
            before_freeze = *v1_before;
            before_frozen = *v1_before;
        }
        if before_freeze == '1' || before_frozen == '1' { already += 1; }
        frozen += 1;
        println!(
            "CGFREEZER_FREEZE_PKG_ENTRY ok=true package={} user={} pid={} uid={} process={} backend={} path={} beforeFreeze={} beforeFrozen={} rc=0",
            shell_sanitize(pkg), user_id, t.pid, t.uid, shell_sanitize(&t.process), backend, shell_sanitize(&restore_path), before_freeze, before_frozen
        );
    }
    let ok = frozen > 0;
    println!(
        "CGFREEZER_FREEZE_PKG_DONE ok={} package={} user={} scanned={} checked={} frozen={} alreadyFrozen={} failed={} reason={} requestAtomic=true transactionalRollback=false elapsedMs={}",
        ok, shell_sanitize(pkg), user_id, scan.count, checked, frozen, already, failed,
        if ok { if failed > 0 { "partial" } else { "ok" } } else { "all_failed" },
        monotonic_ms(&start)
    );
    if ok { 0 } else { 11 }
}


const ESTALE: i32 = 116;

#[derive(Clone, Default)]
struct KillTarget { pid: i32, uid: i32, start_time: u64, process: String }

impl KillTarget {
    fn same_as(&self, other: &KillTarget) -> bool {
        self.pid == other.pid && self.uid == other.uid && self.start_time == other.start_time && self.process == other.process
    }
    fn fields(&self) -> String {
        format!(" pid={} uid={} process={} startTime={}", self.pid, self.uid, shell_sanitize(&self.process), self.start_time)
    }
}

/// Faithful port of read_proc_start_time(): field 22 of /proc/PID/stat
/// (starttime), counted from after the last ')' to survive process names
/// containing spaces/parens.
fn read_proc_start_time(pid: i32) -> Option<u64> {
    if pid <= 0 { return None; }
    let buf = read_file_c(&format!("/proc/{}/stat", pid), 4096)?;
    let rp = buf.rfind(')')?;
    let rest = &buf[rp + 1..];
    let mut field = 3;
    for tok in rest.split_whitespace() {
        if field == 22 { return tok.parse::<u64>().ok().filter(|v| *v > 0); }
        field += 1;
    }
    None
}

/// Faithful port of snapshot_package_target(): validates pid belongs to the
/// exact user_id (via uid), matches the package (via the already-fixed
/// pid_matches_pkg exact/colon-suffix logic), and captures its starttime -
/// the identity triple (pid, uid, start_time, process) used everywhere
/// below to detect pid-reuse between "we saw it" and "we signaled it".
fn snapshot_package_target_rc(pid: i32, pkg: &str, user_id: i32) -> Result<KillTarget, i32> {
    if pid <= 0 || !is_valid_pkg_name(pkg) || user_id < 0 { return Err(-1); }
    let uid = { let u=parse_status_uid_c(pid); if u < 0 { return Err(-2); } u };
    if user_id_from_uid_rs(uid as u32) != user_id { return Err(-3); }
    let process = read_cmdline_c(pid, 512).unwrap_or_default();
    if process.is_empty() || !(process == pkg || (process.starts_with(pkg) && process.as_bytes().get(pkg.len()) == Some(&b':'))) { return Err(-4); }
    let start_time = read_proc_start_time(pid).filter(|v| *v > 0).ok_or(-5)?;
    Ok(KillTarget { pid, uid, start_time, process })
}

fn snapshot_package_target(pid: i32, pkg: &str, user_id: i32) -> Option<KillTarget> {
    snapshot_package_target_rc(pid, pkg, user_id).ok()
}

#[derive(Clone, Default)]
struct TargetScan {
    targets: Vec<KillTarget>,
    overflow: i32,
    rc: i32,
}

/// Faithful port of collect_package_targets(): scans /proc once, captures at
/// most MAX_KILL_TARGETS exact package/user KillTarget rows, and records the
/// C overflow counter instead of letting the Vec grow without a bound. A
/// /proc open/read failure is represented as rc=-1 so kill-package can print
/// scan_failed exactly like c/cgfreezer.c.
fn collect_package_targets(pkg: &str, user_id: i32) -> TargetScan {
    let mut out = TargetScan::default();
    if !is_valid_pkg_name(pkg) || user_id < 0 { out.rc = -1; return out; }
    let entries = match fs::read_dir("/proc") {
        Ok(e) => e,
        Err(_) => { out.rc = -1; return out; }
    };
    for ent in entries.flatten() {
        let name = ent.file_name().to_string_lossy().into_owned();
        if !name.chars().next().map(|c| c.is_ascii_digit()).unwrap_or(false) { continue; }
        let pid: i32 = match name.parse() { Ok(v) if v > 0 => v, _ => continue };
        if let Some(t) = snapshot_package_target(pid, pkg, user_id) {
            if out.targets.len() < MAX_KILL_TARGETS {
                out.targets.push(t);
            } else {
                out.overflow += 1;
            }
        }
    }
    out.rc = 0;
    out
}

#[derive(Default)]
struct CgroupKillProbe {
    checked: i32, accepted: i32, rejected: i32, errors: i32, dirs: i32,
    contains_expected: bool, overflow: bool,
    reject_pid: i32, reject_uid: i32, reject_rc: i32,
    reason: String, reject_process: String,
}
impl CgroupKillProbe {
    fn new() -> Self { CgroupKillProbe { reject_pid: -1, reject_uid: -1, ..Default::default() } }
    fn note_reason(&mut self, reason: &str) { if self.reason.is_empty() { self.reason = reason.to_string(); } }
}

/// Faithful port of safe_unified_cgroup_relpath(): the relative cgroup path
/// parsed from /proc/PID/cgroup must be an absolute-looking path with no
/// ".." traversal and no embedded control characters, before it's used to
/// build a real filesystem path we're about to recurse into and write to.
fn safe_unified_cgroup_relpath(cg: &str) -> bool {
    if cg.is_empty() || !cg.starts_with('/') { return false; }
    if cg.contains("..") { return false; }
    if cg.contains('\n') || cg.contains('\r') || cg.contains('\t') { return false; }
    true
}

/// Faithful port of build_cgroup_dir_from_pid(): like cg_v2_dir_for_pid()
/// but additionally rejects an unsafe-looking relative path before
/// building the directory string - used only by the cgroup.kill fastpath,
/// which is about to recurse into and write to this path, so the extra
/// validation (absent from the plain freeze/thaw path resolution) matters
/// here specifically.
fn build_cgroup_dir_from_pid(pid: i32) -> Option<PathBuf> {
    if pid <= 0 { return None; }
    let body = read_file_c(&format!("/proc/{}/cgroup", pid), MAX_TEXT)?;
    let rel = parse_unified_path_rs(&body, 1024)?;
    if !safe_unified_cgroup_relpath(&rel) { return None; }
    let dir_s = if rel == "/" {
        "/sys/fs/cgroup".to_string()
    } else {
        format!("/sys/fs/cgroup{}", rel)
    };
    if dir_s.len() >= MAX_PATH_LEN { return None; }
    Some(PathBuf::from(dir_s))
}

/// Faithful port of validate_cgroup_procs_exact(): every numeric token in
/// this cgroup's own cgroup.procs file must resolve (via
/// snapshot_package_target) to a live process that is exactly this
/// package+user - a single foreign or stale pid anywhere aborts the whole
/// fastpath attempt.
fn validate_cgroup_procs_exact(dir: &str, pkg: &str, user_id: i32, expected_pid: i32, probe: &mut CgroupKillProbe) -> bool {
    let procs_path = format!("{}/cgroup.procs", dir);
    let buf = match read_file_c(&procs_path, MAX_TEXT) {
        Some(b) => b,
        None => { probe.errors += 1; probe.note_reason("read_procs_failed"); return false; }
    };
    if buf.len() >= MAX_TEXT - 2 { probe.overflow = true; probe.note_reason("procs_too_large"); return false; }
    for tok in buf.split(|c: char| c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        if tok.is_empty() { continue; }
        let pid: i64 = match tok.parse() { Ok(v) => v, Err(_) => continue };
        if pid <= 0 || pid > 4_194_304 { continue; }
        let pid = pid as i32;
        probe.checked += 1;
        if pid == expected_pid { probe.contains_expected = true; }
        match snapshot_package_target_rc(pid, pkg, user_id) {
            Ok(_) => { probe.accepted += 1; }
            Err(rc) => {
                probe.rejected += 1;
                probe.reject_pid = pid;
                probe.reject_uid = parse_status_uid_c(pid);
                probe.reject_rc = rc;
                probe.reject_process = read_cmdline_c(pid, 512).unwrap_or_default();
                probe.note_reason("foreign_or_stale_pid");
                return false;
            }
        }
        if probe.checked > MAX_KILL_TARGETS as i32 { probe.overflow = true; probe.note_reason("too_many_pids"); return false; }
    }
    true
}

/// Faithful port of validate_cgroup_tree_exact_recursive(): walks every
/// subdirectory of `dir` (skipping cgroup.* control files), depth-limited
/// to 16 and directory-count-limited to 256, requiring
/// validate_cgroup_procs_exact() to pass at every level - the whole
/// subtree, not just the target's own leaf cgroup, must contain nothing
/// but processes belonging to this exact package+user before the atomic
/// cgroup.kill write is considered safe.
fn validate_cgroup_tree_exact_recursive(dir: &str, pkg: &str, user_id: i32, expected_pid: i32, depth: i32, probe: &mut CgroupKillProbe) -> bool {
    if dir.is_empty() { return false; }
    if depth > 16 { probe.errors += 1; probe.note_reason("tree_too_deep"); return false; }
    probe.dirs += 1;
    if probe.dirs > 256 { probe.overflow = true; probe.note_reason("too_many_cgroups"); return false; }
    if !validate_cgroup_procs_exact(dir, pkg, user_id, expected_pid, probe) { return false; }

    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => { probe.errors += 1; probe.note_reason("opendir_failed"); return false; }
    };
    for ent in entries.flatten() {
        let name = ent.file_name().to_string_lossy().into_owned();
        if name == "." || name == ".." || name.starts_with("cgroup.") { continue; }
        let child = format!("{}/{}", dir, name);
        let is_dir = fs::metadata(&child).map(|m| m.is_dir()).unwrap_or(false);
        if !is_dir { continue; }
        if !validate_cgroup_tree_exact_recursive(&child, pkg, user_id, expected_pid, depth + 1, probe) { return false; }
    }
    true
}

/// Faithful port of try_cgroup_kill_fastpath(): only used when every single
/// process anywhere in the target's whole cgroup v2 subtree is exactly
/// this package+user (verified above), the target's identity still matches
/// right before the write, and the cgroup.kill file itself is writable.
/// Returns the "cgroup.kill" method string on success; any failure at any
/// gate silently returns None so the caller falls through to the per-pid
/// pidfd path, which is already safe on its own.
fn try_cgroup_kill_fastpath(expected: &KillTarget, pkg: &str, user_id: i32) -> Option<&'static str> {
    if expected.pid <= 0 { return None; }
    let dir = build_cgroup_dir_from_pid(expected.pid)?;
    let dir_s = dir.to_string_lossy().into_owned();
    if dir_s.len() + "/cgroup.kill".len() >= MAX_PATH_LEN { return None; }
    let kill_path = format!("{}/cgroup.kill", dir_s);
    let kill_c = CString::new(kill_path.clone()).ok()?;
    if unsafe { access(kill_c.as_ptr(), W_OK) } != 0 { return None; }

    let mut probe = CgroupKillProbe::new();
    if !validate_cgroup_tree_exact_recursive(&dir_s, pkg, user_id, expected.pid, 0, &mut probe) { return None; }
    if !probe.contains_expected || probe.checked <= 0 || probe.rejected > 0 || probe.errors > 0 || probe.overflow { return None; }

    let before_write = snapshot_package_target(expected.pid, pkg, user_id)?;
    if !before_write.same_as(expected) { return None; }

    if write_file_c(&kill_path, "1\n").is_err() { return None; }
    Some("cgroup.kill")
}

struct KillSignalResult { signaled: bool, disappeared: bool, identity_mismatch: bool, err: i32, method: &'static str }

/// Faithful port of signal_kill_target(): tries the cgroup.kill fastpath
/// first (only viable when every process anywhere in the target's whole
/// cgroup v2 subtree is exactly this package+user), falling back to the
/// per-pid pidfd path - which is already race-safe on its own - when the
/// fastpath's exhaustive validation doesn't pass. Re-snapshots the target
/// immediately before opening the pidfd and again before the kill()
/// fallback, rejecting as identity_mismatch if start_time/process changed
/// (pid was reused) rather than signaling a process that merely happens to
/// have the same pid number now.
fn signal_kill_target(expected: &KillTarget, pkg: &str, user_id: i32) -> KillSignalResult {
    if expected.pid <= 0 {
        return KillSignalResult { signaled: false, disappeared: false, identity_mismatch: false, err: EINVAL, method: "none" };
    }
    let current = snapshot_package_target(expected.pid, pkg, user_id);
    match &current {
        None => {
            let disappeared = !pid_alive(expected.pid);
            return KillSignalResult { signaled: false, disappeared, identity_mismatch: !disappeared, err: if disappeared { ESRCH } else { ESTALE }, method: "none" };
        }
        Some(c) if !c.same_as(expected) => {
            return KillSignalResult { signaled: false, disappeared: false, identity_mismatch: true, err: ESTALE, method: "none" };
        }
        _ => {}
    }

    if let Some(method) = try_cgroup_kill_fastpath(expected, pkg, user_id) {
        return KillSignalResult { signaled: true, disappeared: false, identity_mismatch: false, err: 0, method };
    }

    let pidfd = unsafe { syscall(SYS_PIDFD_OPEN, expected.pid as c_ulong, 0u64) };
    if pidfd >= 0 {
        let pidfd = pidfd as c_int;
        let after_open = snapshot_package_target(expected.pid, pkg, user_id);
        if after_open.as_ref().map(|c| !c.same_as(expected)).unwrap_or(true) {
            unsafe { close(pidfd) };
            let disappeared = !pid_alive(expected.pid);
            return KillSignalResult { signaled: false, disappeared, identity_mismatch: !disappeared, err: if disappeared { ESRCH } else { ESTALE }, method: "none" };
        }
        let prc = unsafe { syscall(SYS_PIDFD_SEND_SIGNAL as i64, pidfd as i64, 9i64 /*SIGKILL*/, 0i64, 0i64) };
        let e = errno_now();
        unsafe { close(pidfd) };
        if prc == 0 {
            return KillSignalResult { signaled: true, disappeared: false, identity_mismatch: false, err: 0, method: "pidfd" };
        }
        if e != ENOSYS && e != EINVAL && e != ENOTTY {
            return KillSignalResult { signaled: false, disappeared: e == ESRCH, identity_mismatch: false, err: e, method: "pidfd" };
        }
    }

    let before_kill = snapshot_package_target(expected.pid, pkg, user_id);
    match &before_kill {
        None => {
            let disappeared = !pid_alive(expected.pid);
            return KillSignalResult { signaled: false, disappeared, identity_mismatch: !disappeared, err: if disappeared { ESRCH } else { ESTALE }, method: "kill" };
        }
        Some(c) if !c.same_as(expected) => {
            return KillSignalResult { signaled: false, disappeared: false, identity_mismatch: true, err: ESTALE, method: "kill" };
        }
        _ => {}
    }
    let rc = unsafe { kill(expected.pid as c_int, 9 /*SIGKILL*/) };
    if rc == 0 {
        KillSignalResult { signaled: true, disappeared: false, identity_mismatch: false, err: 0, method: "kill" }
    } else {
        let e = errno_now();
        KillSignalResult { signaled: false, disappeared: e == ESRCH, identity_mismatch: false, err: e, method: "kill" }
    }
}

fn render_kill_target_pids(targets: &[KillTarget]) -> String {
    targets.iter().map(|t| t.pid.to_string()).collect::<Vec<_>>().join(",")
}
/// Faithful port of cmd_kill_package(): an event-pid-first optimization
/// (immediately signal a specific triggering pid, e.g. from a death
/// notification, before the general sweep), then up to max_passes rounds
/// of collect_package_targets()+signal_kill_target() - re-scanning /proc
/// each pass so respawned children get caught - stopping early once a pass
/// finds nothing left, and a final post-loop rescan to confirm nothing
/// survived. The previous implementation did a single kill() pass with no
/// starttime identity check and no re-scanning, so it could miss processes
/// that respawned during the kill window or accidentally signal a reused
/// pid.
fn cmd_kill_package(pkg: &str, user: i32, event_pid: i32, timeout_in: i64) -> i32 {
    let st = Instant::now();
    if !is_valid_pkg_name(pkg) || user < 0 || event_pid < -1 {
        println!("CGFREEZER_KILL_PKG_DONE ok=false package={} user={} eventPid={} reason=bad_args elapsedMs={}", shell_sanitize(pkg), user, event_pid, monotonic_ms(&st));
        return 64;
    }
    let timeout_ms = if timeout_in < 100 || timeout_in > 5000 { 800 } else { timeout_in };
    let deadline = st + Duration::from_millis(timeout_ms as u64);
    let mut max_passes = 1 + timeout_ms / 80;
    if max_passes < 2 { max_passes = 2; }
    if max_passes > 8 { max_passes = 8; } // MAX_KILL_PASSES

    let (mut scanned_total, mut checked, mut signaled, mut disappeared) = (0i64, 0i64, 0i64, 0i64);
    let (mut mismatched, mut failed, mut overflow_total, mut passes) = (0i64, 0i64, 0i64, 0i64);
    let mut event_valid = false;
    let mut event_signaled = false;
    let mut event_target = KillTarget::default();

    println!("CGFREEZER_KILL_PKG_BEGIN ok=true package={} user={} eventPid={} timeoutMs={} maxPasses={} liveRescan=true uidWideKill=false signal=9", shell_sanitize(pkg), user, event_pid, timeout_ms, max_passes);

    if event_pid > 0 {
        match snapshot_package_target_rc(event_pid, pkg, user) {
            Ok(t) => {
                event_target = t.clone();
                event_valid = true;
                checked += 1;
                let sr = signal_kill_target(&t, pkg, user);
                if sr.signaled { signaled += 1; event_signaled = true; }
                else if sr.disappeared { disappeared += 1; }
                else if sr.identity_mismatch { mismatched += 1; }
                else { failed += 1; }
                println!(
                    "CGFREEZER_KILL_PKG_ENTRY ok={} package={} user={} pass=0 source=event{} signal=9 method={} signaled={} disappeared={} identityMismatch={} errno={}",
                    sr.signaled || sr.disappeared, shell_sanitize(pkg), user, t.fields(), sr.method, sr.signaled, sr.disappeared, sr.identity_mismatch, sr.err
                );
                if sr.signaled { std::thread::sleep(Duration::from_millis(5)); }
            }
            Err(snapshot_rc) => {
                println!("CGFREEZER_KILL_PKG_EVENT_SKIP ok=true package={} user={} eventPid={} reason=not_exact_target snapshotRc={}", shell_sanitize(pkg), user, event_pid, snapshot_rc);
            }
        }
    }

    for pass in 1..=max_passes {
        if Instant::now() > deadline { break; }
        let scan = collect_package_targets(pkg, user);
        let targets = scan.targets;
        if scan.rc != 0 {
            failed += 1;
            println!("CGFREEZER_KILL_PKG_PASS ok=false package={} user={} pass={} reason=scan_failed rc={}", shell_sanitize(pkg), user, pass, scan.rc);
            break;
        }
        passes = pass;
        scanned_total += targets.len() as i64;
        overflow_total += scan.overflow as i64;
        println!("CGFREEZER_KILL_PKG_PASS ok=true package={} user={} pass={} count={} overflow={} pids={}", shell_sanitize(pkg), user, pass, targets.len(), scan.overflow, shell_sanitize(&render_kill_target_pids(&targets)));
        if targets.is_empty() && scan.overflow == 0 {
            break;
        }
        for t in &targets {
            if pass == 1 && event_valid && event_signaled && t.same_as(&event_target) {
                println!("CGFREEZER_KILL_PKG_ENTRY ok=true package={} user={} pass={} source=event-pending{} signal=9 method=event-first signaled=true disappeared=false identityMismatch=false errno=0", shell_sanitize(pkg), user, pass, t.fields());
                continue;
            }
            checked += 1;
            let sr = signal_kill_target(t, pkg, user);
            if sr.signaled { signaled += 1; }
            else if sr.disappeared { disappeared += 1; }
            else if sr.identity_mismatch { mismatched += 1; }
            else { failed += 1; }
            println!(
                "CGFREEZER_KILL_PKG_ENTRY ok={} package={} user={} pass={} source=scan{} signal=9 method={} signaled={} disappeared={} identityMismatch={} errno={}",
                sr.signaled || sr.disappeared, shell_sanitize(pkg), user, pass, t.fields(), sr.method, sr.signaled, sr.disappeared, sr.identity_mismatch, sr.err
            );
        }
        if Instant::now() < deadline { std::thread::sleep(Duration::from_millis(25)); }
    }

    let final_scan = collect_package_targets(pkg, user);
    let remain = final_scan.targets;
    let remain_overflow = final_scan.overflow;
    let ok = final_scan.rc == 0 && remain.is_empty() && remain_overflow == 0;
    let reason = if ok {
        if scanned_total == 0 && !event_valid { "no_alive_pid" } else { "ok" }
    } else if final_scan.rc != 0 { "final_scan_failed" } else { "remain_alive" };
    println!(
        "CGFREEZER_KILL_PKG_DONE ok={} package={} user={} eventPid={} eventValid={} eventSignaled={} scanned={} checked={} signaled={} disappeared={} mismatched={} failed={} overflow={} remain={} remainOverflow={} remainPids={} passes={} liveRescan=true uidWideKill=false pidIdentity=starttime reason={} elapsedMs={}",
        ok, shell_sanitize(pkg), user, event_pid, event_valid, event_signaled,
        scanned_total, checked, signaled, disappeared, mismatched, failed, overflow_total,
        remain.len(), remain_overflow, shell_sanitize(&render_kill_target_pids(&remain)), passes, reason, monotonic_ms(&st)
    );
    if ok { 0 } else { 12 }
}

const SYS_PIDFD_SEND_SIGNAL: c_ulong = 424;
const ESRCH: i32 = 3;
const ENOSYS: i32 = 38;

/// Faithful port of signal_pid_user_checked(): tries pidfd-based signaling
/// first (race-free - it targets the exact process instance the pidfd was
/// opened against, so if the pid is reused by an unrelated process in the
/// window between the uid check and the signal, pidfd_send_signal correctly
/// fails rather than hitting the wrong process), falling back to plain
/// kill(pid) only when pidfd isn't supported by the kernel. The previous
/// implementation always used plain kill(pid, sig), which has no such
/// protection against pid-reuse races.
/// Returns (rc, method, uid, errno). errno is captured explicitly at each
/// failure point rather than read from process-global errno afterward,
/// since intervening safe Rust calls (fs::read, etc.) can silently
/// overwrite the C-style errno the caller would otherwise try to inspect.
fn signal_pid_user_checked(pid: i32, user_id: i32, sig: i32) -> (i32, &'static str, i32, i32) {
    if pid <= 0 { return (-1, "none", -1, EINVAL); }
    let uid = parse_status_uid_c(pid);
    if uid < 0 { return (-1, "none", -1, ESRCH); }
    if user_id >= 0 && user_id_from_uid_rs(uid as u32) != user_id { return (-1, "none", uid, 1 /*EPERM*/) };
    let pidfd = unsafe { syscall(SYS_PIDFD_OPEN, pid as c_ulong, 0u64) };
    if pidfd >= 0 {
        let pidfd = pidfd as c_int;
        let prc = unsafe { syscall(SYS_PIDFD_SEND_SIGNAL as i64, pidfd as i64, sig as i64, 0i64, 0i64) };
        let e = errno_now();
        unsafe { close(pidfd) };
        if prc == 0 { return (0, "pidfd", uid, 0); }
        if e != ENOSYS && e != EINVAL && e != ENOTTY {
            return (-1, "pidfd", uid, e);
        }
    }
    let rc = unsafe { kill(pid as c_int, sig as c_int) };
    let e = if rc == 0 { 0 } else { errno_now() };
    (if rc == 0 { 0 } else { -1 }, "kill", uid, e)
}

fn cmd_kill_pid_list(user: i32, target: &str, sig: i32) -> i32 {
    let st = Instant::now();
    if target.is_empty() {
        println!("CGFREEZER_KILL_PID_LIST_DONE ok=false user={} checked=0 killed=0 failed=0 skipped=0 reason=empty elapsedMs={}", user, monotonic_ms(&st));
        return 64;
    }
    let pids = read_pid_targets(target);
    let sig = if sig <= 0 || sig > 64 { 9 /* SIGKILL */ } else { sig };
    println!("CGFREEZER_KILL_PID_LIST_BEGIN ok=true user={} signal={} pids={}", user, sig, shell_sanitize(target));
    let mut checked = 0u64; let mut killed = 0u64; let mut failed = 0u64; let mut skipped = 0u64;
    for pid in pids {
        let cmd = if pid > 0 { read_cmdline_c(pid, 512).unwrap_or_default() } else { String::new() };
        if pid <= 0 {
            skipped += 1;
            println!("CGFREEZER_KILL_PID_LIST_ENTRY ok=false pid={} uid=-1 method=none reason=bad_pid", pid);
            continue;
        }
        checked += 1;
        let (rc, method, uid, e) = signal_pid_user_checked(pid, user, sig);
        let ok = rc == 0 || e == ESRCH;
        if ok { killed += 1; } else { failed += 1; }
        println!("CGFREEZER_KILL_PID_LIST_ENTRY ok={} pid={} uid={} signal={} method={} errno={} process={}", ok, pid, uid, sig, method, e, shell_sanitize(&cmd));
    }
    let ok = killed > 0 && failed == 0;
    println!("CGFREEZER_KILL_PID_LIST_DONE ok={} user={} checked={} killed={} failed={} skipped={} reason={} pidfdOptional=true batch=true elapsedMs={}", ok, user, checked, killed, failed, skipped, if ok { "ok" } else if killed > 0 { "partial" } else { "none" }, monotonic_ms(&st));
    if killed > 0 { 0 } else { 12 }
}


fn uid_pids(uid: u32) -> Vec<i32> { list_pids().into_iter().filter(|p| parse_status_uid_c(*p) == uid as i32).collect() }

fn cmd_thaw_path(path: &str, target: &str, timeout: i64) -> i32 {
    let t = target.chars().next().unwrap_or('\0');
    cmd_thaw_path_internal(-1, path, t, timeout, false)
}

fn cmd_thaw_pid(pid: i32, orig: &str, target: &str, timeout: i64) -> i32 {
    let t = target.chars().next().unwrap_or('\0');
    cmd_thaw_path_internal(pid, orig, t, timeout, true)
}


fn parse_int_arg_rs(s: &str, fallback: i32) -> i32 {
    if s.is_empty() { return fallback; }
    // Match C parse_int_arg(): strtol accepts leading ASCII whitespace but
    // requires the remaining suffix to be empty. Rust parse() is stricter on
    // leading whitespace, so trim only the leading side and then require the
    // original trailing bytes to have no junk by parsing the left-trimmed token.
    let left = s.trim_start_matches(|c: char| c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\u{000b}' || c == '\u{000c}');
    if left.is_empty() { return fallback; }
    match left.parse::<i64>() {
        Ok(v) if v >= -2147483647 && v <= 2147483647 => v as i32,
        _ => fallback,
    }
}

fn read_pid_targets(target: &str) -> Vec<i32> {
    // C parity: callers copy pid_csv into char tmp[MAX_TEXT] with snprintf()
    // and iterate strtok_r(tmp, ","). Empty comma fields are skipped by
    // strtok_r; malformed non-empty fields are kept as -1 so caller emits
    // skip_bad_pid_or_user / bad_pid. No path/file fallback and no special
    // treatment for "-" or "none" in this generic parser.
    if target.is_empty() { return Vec::new(); }
    let tmp = c_truncate_bytes(target, MAX_TEXT.saturating_sub(1));
    tmp.split(',')
        .filter(|v| !v.is_empty())
        .map(|v| parse_int_arg_rs(v, -1))
        .collect()
}

#[derive(Default)]
struct WchanStats { checked: i32, frozen: i32, sigstop: i32, unknown: i32, mismatch: i32, skipped: i32 }

fn user_id_from_uid_rs(uid: u32) -> i32 { if uid >= 100000 { (uid / 100000) as i32 } else { 0 } }

fn read_oom_score_adj_rs(pid: i32) -> i32 {
    read_file_c(&format!("/proc/{}/oom_score_adj", pid), 64)
        .map(|s| parse_int_arg_rs(&s, 9999))
        .unwrap_or(9999)
}

fn proc_state_char_rs(pid: i32) -> char {
    let buf = match read_file_c(&format!("/proc/{}/stat", pid), 4096) { Some(v) => v, None => return '-' };
    let rp = match buf.rfind(')') { Some(v) => v, None => return '-' };
    let rest = &buf[rp + 1..];
    c_trim_start_ascii_space(rest).chars().next().unwrap_or('-')
}

fn read_proc_wchan_c(pid: i32) -> String {
    match read_file_c(&format!("/proc/{}/wchan", pid), 256) {
        Some(v) if !v.is_empty() => v,
        Some(_) => "-".to_string(),
        None => "-".to_string(),
    }
}

fn classify_wchan_freeze_kind(wchan: &str) -> &'static str {
    let w = wchan;
    if w.is_empty() || w == "-" || w == "0" { return "unknown"; }
    if w.contains("__refrigerator") || w.contains("refrigerator") { return "v1"; }
    if w.contains("do_freezer_trap") || w.contains("get_signal") { return "v2"; }
    if w.contains("do_signal_stop") { return "sigstop"; }
    "not-frozen"
}

fn wchan_kind_is_frozen(kind: &str) -> bool { kind == "v1" || kind == "v2" }
fn wchan_kind_is_stopped(kind: &str) -> bool { kind == "sigstop" }

fn normalize_wchan_expect(expect: &str) -> &'static str {
    match expect {
        "frozen" => "frozen",
        "thawed" => "thawed",
        "not-frozen" => "not-frozen",
        "any" | "-" | "" => "any",
        _ => "any",
    }
}

fn wchan_expect_ok(expect: &str, kind: &str) -> bool {
    match normalize_wchan_expect(expect) {
        "any" => true,
        "frozen" => wchan_kind_is_frozen(kind),
        "thawed" | "not-frozen" => !wchan_kind_is_frozen(kind) && !wchan_kind_is_stopped(kind),
        _ => true,
    }
}

fn write_wchan_entry<W: Write>(out: &mut W, origin: &str, user_id: i32, pid: i32, uid: i32, expect: &str, process: &str, stats: &mut WchanStats) {
    let wchan_raw = read_proc_wchan_c(pid);
    let wchan = if wchan_raw.is_empty() { "-".to_string() } else { wchan_raw };
    let kind = classify_wchan_freeze_kind(&wchan);
    stats.checked += 1;
    if wchan_kind_is_frozen(kind) { stats.frozen += 1; }
    if wchan_kind_is_stopped(kind) { stats.sigstop += 1; }
    if kind == "unknown" { stats.unknown += 1; }
    let matched = wchan_expect_ok(expect, kind);
    if !matched { stats.mismatch += 1; }
    let process_s = if process.is_empty() { "-" } else { process };
    let _ = writeln!(out,
        "CGFREEZER_WCHAN_ENTRY ok={} origin={} user={} pid={} uid={} state={} oomAdj={} expect={} match={} freezeKind={} wchan={} process={}",
        if matched { "true" } else { "false" },
        origin,
        user_id,
        pid,
        uid,
        proc_state_char_rs(pid),
        read_oom_score_adj_rs(pid),
        shell_sanitize(expect),
        if matched { "true" } else { "false" },
        kind,
        shell_sanitize(&wchan),
        shell_sanitize(process_s));
}

fn run_wchan_pid_list<W: Write>(out: &mut W, user: i32, target: &str, expect_arg: &str, st: &Instant) -> i32 {
    let expect = normalize_wchan_expect(expect_arg);
    if target.is_empty() || target == "-" || target == "none" {
        let ok = expect == "thawed" || expect == "not-frozen" || expect == "any";
        let _ = writeln!(out,
            "CGFREEZER_WCHAN_DONE ok={} origin=pid-list user={} checked=0 frozen=0 sigstop=0 unknown=0 mismatch=0 skipped=0 expect={} reason=no_pids elapsedMs={}",
            if ok { "true" } else { "false" }, user, expect, monotonic_ms(st));
        return if ok { 0 } else { 11 };
    }
    let _ = writeln!(out, "CGFREEZER_WCHAN_BEGIN ok=true origin=pid-list user={} expect={} pids={}", user, expect, shell_sanitize(target));
    let mut stats = WchanStats::default();
    for pid in read_pid_targets(target) {
        let uid = if pid > 0 { parse_status_uid_c(pid) } else { -1 };
        let process = if pid > 0 { read_cmdline_c(pid, 512).unwrap_or_default() } else { String::new() };
        if pid <= 0 || uid < 0 || (user >= 0 && user_id_from_uid_rs(uid as u32) != user) {
            stats.skipped += 1;
            let _ = writeln!(out,
                "CGFREEZER_WCHAN_ENTRY ok=false origin=pid-list user={} pid={} uid={} expect={} match=false freezeKind=unknown wchan=- process=- reason=skip_bad_pid_or_user",
                user, pid, uid, expect);
            continue;
        }
        write_wchan_entry(out, "pid-list", user, pid, uid, expect, &process, &mut stats);
    }
    let ok = if expect == "frozen" { stats.checked > 0 && stats.frozen > 0 && stats.mismatch == 0 }
        else if expect == "thawed" || expect == "not-frozen" { stats.mismatch == 0 }
        else { true };
    let _ = writeln!(out,
        "CGFREEZER_WCHAN_DONE ok={} origin=pid-list user={} checked={} frozen={} sigstop={} unknown={} mismatch={} skipped={} expect={} reason={} elapsedMs={}",
        if ok { "true" } else { "false" }, user, stats.checked, stats.frozen, stats.sigstop, stats.unknown, stats.mismatch, stats.skipped, expect, if ok { "ok" } else { "expect_mismatch" }, monotonic_ms(st));
    if ok { 0 } else { 12 }
}

fn run_wchan_uid<W: Write>(out: &mut W, uid_filter: i32, expect_arg: &str, st: &Instant) -> i32 {
    let expect = normalize_wchan_expect(expect_arg);
    if uid_filter < 0 {
        let _ = writeln!(out, "CGFREEZER_WCHAN_UID_DONE ok=false uid={} checked=0 frozen=0 sigstop=0 unknown=0 mismatch=0 skipped=0 expect={} reason=bad_uid elapsedMs={}", uid_filter, expect, monotonic_ms(st));
        return 64;
    }
    let uid_u = uid_filter as u32;
    let user_id = user_id_from_uid_rs(uid_u);
    let _ = writeln!(out, "CGFREEZER_WCHAN_BEGIN ok=true origin=uid uid={} user={} expect={}", uid_filter, user_id, expect);
    let mut stats = WchanStats::default();
    for pid in uid_pids(uid_u) {
        let process = read_cmdline_c(pid, 512).unwrap_or_default();
        write_wchan_entry(out, "uid", user_id, pid, uid_filter, expect, &process, &mut stats);
    }
    let ok = if expect == "frozen" { stats.checked > 0 && stats.frozen > 0 && stats.mismatch == 0 }
        else if expect == "thawed" || expect == "not-frozen" { stats.mismatch == 0 }
        else { true };
    let _ = writeln!(out,
        "CGFREEZER_WCHAN_UID_DONE ok={} uid={} user={} checked={} frozen={} sigstop={} unknown={} mismatch={} skipped={} expect={} reason={} elapsedMs={}",
        if ok { "true" } else { "false" }, uid_filter, user_id, stats.checked, stats.frozen, stats.sigstop, stats.unknown, stats.mismatch, stats.skipped, expect, if ok { "ok" } else { "expect_mismatch" }, monotonic_ms(st));
    if ok { 0 } else { 12 }
}

fn cmd_proc_wchan(user: i32, target: &str, expect: &str) -> i32 {
    let st = Instant::now();
    let mut out = io::stdout();
    run_wchan_pid_list(&mut out, user, target, expect, &st)
}

fn cmd_uid_wchan(uid: i32, expect: &str) -> i32 {
    let st = Instant::now();
    let mut out = io::stdout();
    run_wchan_uid(&mut out, uid, expect, &st)
}

fn cmd_binder_info(pid: i32) -> i32 {
    let st = Instant::now();
    let bs = binder_get_status(pid);
    println!("CGFREEZER_BINDER_INFO ok={} pid={}{} elapsedMs={}", bs.ok, pid, binder_fields("", &bs), monotonic_ms(&st));
    if bs.ok { 0 } else if bs.supported { 3 } else { 2 }
}

const RTLD_NOW: c_int = 2;
const SIGTERM_LOGD: c_int = 15;
const SIGINT_LOGD: c_int = 2;

static G_RUNNING: AtomicBool = AtomicBool::new(true);
extern "C" fn on_signal_logd(_sig: c_int) {
    G_RUNNING.store(false, Ordering::Relaxed);
}

extern "C" {
    fn dlopen(filename: *const std::os::raw::c_char, flag: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const std::os::raw::c_char) -> *mut c_void;
    fn dlclose(handle: *mut c_void) -> c_int;
    fn dlerror() -> *mut std::os::raw::c_char;
    fn signal(signum: c_int, handler: usize) -> usize;
}

const LOGGER_ENTRY_MAX_LEN: usize = 5120;
const LOG_ID_EVENTS: c_int = 2;
const MAX_CACHE_PIDS: usize = 256;

#[derive(Default)]
struct PidCache { pids: Vec<i32>, uid: i32 }
impl PidCache {
    fn new() -> Self { PidCache { pids: Vec::new(), uid: -1 } }
    fn contains(&self, pid: i32) -> bool { pid > 0 && self.pids.contains(&pid) }
    fn add(&mut self, pid: i32, uid: i32) {
        if pid <= 0 { return; }
        if !self.contains(pid) && self.pids.len() < MAX_CACHE_PIDS { self.pids.push(pid); }
        if uid > 0 { self.uid = uid; }
    }
    fn remove(&mut self, pid: i32) {
        if pid <= 0 { return; }
        if let Some(i) = self.pids.iter().position(|&p| p == pid) { self.pids.swap_remove(i); }
    }
}

#[derive(Default)]
struct ParsedEvent { tag: u32, ints: Vec<u32>, strings: Vec<String> }

/// Faithful port of decode_event_element(): Android's binary EventLog TLV
/// encoding. type 0=u32 int, 1=8-byte long (skipped, not needed here),
/// 2=4-byte-length-prefixed string, 3=1-byte count + nested elements,
/// 4=4-byte float (skipped). Depth-limited to 8 to match the C recursion
/// guard.
fn decode_event_element(p: &[u8], off: &mut usize, depth: i32, ev: &mut ParsedEvent) -> bool {
    if depth > 8 || *off >= p.len() { return false; }
    let ty = p[*off]; *off += 1;
    match ty {
        0 => {
            if *off + 4 > p.len() { return false; }
            let v = u32::from_le_bytes(p[*off..*off + 4].try_into().unwrap());
            *off += 4;
            if ev.ints.len() < 16 { ev.ints.push(v); }
            true
        }
        1 => { if *off + 8 > p.len() { return false; } *off += 8; true }
        2 => {
            if *off + 4 > p.len() { return false; }
            let len = u32::from_le_bytes(p[*off..*off + 4].try_into().unwrap()) as usize;
            *off += 4;
            if *off + len > p.len() { return false; }
            if ev.strings.len() < 8 {
                let copy = len.min(511);
                ev.strings.push(String::from_utf8_lossy(&p[*off..*off + copy]).into_owned());
            }
            *off += len;
            true
        }
        3 => {
            if *off >= p.len() { return false; }
            let count = p[*off]; *off += 1;
            for _ in 0..count { if !decode_event_element(p, off, depth + 1, ev) { return false; } }
            true
        }
        4 => { if *off + 4 > p.len() { return false; } *off += 4; true }
        _ => false,
    }
}

/// Faithful port of parse_event_payload(): tag(u32 LE) + one top-level
/// TLV element (almost always type 3 = list for am_proc_start/am_proc_died).
fn parse_event_payload(data: &[u8]) -> Option<ParsedEvent> {
    if data.len() < 5 { return None; }
    let tag = u32::from_le_bytes(data[0..4].try_into().unwrap());
    let mut ev = ParsedEvent { tag, ..Default::default() };
    let mut off = 4usize;
    if !decode_event_element(data, &mut off, 0, &mut ev) { return None; }
    Some(ev)
}

fn emit_logd_event(event_type: &str, tag: u32, user: i32, pid: i32, uid: i32, proc: &str, cache: &PidCache, reason: &str) {
    println!("CGFREEZER_LOGD_EVENT type={} tag={} user={} pid={} uid={} process={} cachePids={} cacheUid={} reason={}",
        shell_sanitize(event_type), tag, user, pid, uid, shell_sanitize(proc), cache.pids.len(), cache.uid, shell_sanitize(reason));
}

/// Faithful port of cmd_watch_logd(): watches the Android EventLog
/// (LOG_ID_EVENTS) via liblog.so's private android_logger_list_open/_read/
/// _free ABI (accessed through dlopen/dlsym since there is no public C
/// header for it), looking for am_proc_start (tag 30014) and am_proc_died
/// (tag 30011) entries matching this package+user, to track the live pid
/// set without polling /proc. This entire feature is Android-liblog
/// specific and CANNOT be exercised on a non-Android host - there is no
/// liblog.so, no logd, and no real EventLog here. Only the dlopen-failure
/// graceful-exit path (reason=dlopen_liblog_failed) has actually been run;
/// the binary TLV parsing and the tag 30014/30011 field-matching logic
/// were translated field-for-field from c/cgfreezer.c and must be verified
/// on a real device before being trusted.
fn cmd_watch_logd(pkg: &str, user_id: i32, duration_ms: i64) -> i32 {
    let start = Instant::now();
    if !is_valid_pkg_name(pkg) {
        println!("CGFREEZER_LOGD_WATCH_DONE ok=false reason=bad_package package={} elapsedMs=0", shell_sanitize(pkg));
        return 2;
    }

    let mut cache = PidCache::new();
    let initial = scan_package_collect(pkg, user_id, false);
    let initial_csv = initial.csv.clone();
    let initial_count = initial.count.max(0) as usize;
    for item in initial_csv.split(',').filter(|v| !v.is_empty()) {
        let mut parts = item.splitn(3, ':');
        let pid = parts.next().map(atoi_prefix_i32).unwrap_or(-1);
        let uid = parts.next().map(atoi_prefix_i32).unwrap_or(-1);
        if pid > 0 { cache.add(pid, uid); }
    }

    let liblog_name = CString::new("liblog.so").unwrap();
    let liblog = unsafe { dlopen(liblog_name.as_ptr(), RTLD_NOW) };
    if liblog.is_null() {
        let err = unsafe {
            let p = dlerror();
            if p.is_null() { "unknown".to_string() } else { std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned() }
        };
        println!("CGFREEZER_LOGD_WATCH_DONE ok=false reason=dlopen_liblog_failed error={} elapsedMs={}", shell_sanitize(&err), monotonic_ms(&start));
        return 3;
    }

    type FnLoggerListOpen = unsafe extern "C" fn(c_int, c_int, u32, i32) -> *mut c_void;
    type FnLoggerListRead = unsafe extern "C" fn(*mut c_void, *mut u8) -> c_int;
    type FnLoggerListFree = unsafe extern "C" fn(*mut c_void);

    let open_sym = CString::new("android_logger_list_open").unwrap();
    let read_sym = CString::new("android_logger_list_read").unwrap();
    let free_sym = CString::new("android_logger_list_free").unwrap();
    let logger_open_ptr = unsafe { dlsym(liblog, open_sym.as_ptr()) };
    let logger_read_ptr = unsafe { dlsym(liblog, read_sym.as_ptr()) };
    let logger_free_ptr = unsafe { dlsym(liblog, free_sym.as_ptr()) };
    if logger_open_ptr.is_null() || logger_read_ptr.is_null() || logger_free_ptr.is_null() {
        println!("CGFREEZER_LOGD_WATCH_DONE ok=false reason=dlsym_failed elapsedMs={}", monotonic_ms(&start));
        unsafe { dlclose(liblog) };
        return 4;
    }
    let logger_open: FnLoggerListOpen = unsafe { std::mem::transmute(logger_open_ptr) };
    let logger_read: FnLoggerListRead = unsafe { std::mem::transmute(logger_read_ptr) };
    let logger_free: FnLoggerListFree = unsafe { std::mem::transmute(logger_free_ptr) };

    unsafe {
        signal(SIGTERM_LOGD, on_signal_logd as usize);
        signal(SIGINT_LOGD, on_signal_logd as usize);
    }

    println!("CGFREEZER_LOGD_WATCH_START ok=true package={} user={} durationMs={} initialPids={} pids={}",
        shell_sanitize(pkg), user_id, duration_ms, initial_count, shell_sanitize(&initial_csv));

    let mut list = unsafe { logger_open(LOG_ID_EVENTS, 0, 0, 0) };
    if list.is_null() {
        println!("CGFREEZER_LOGD_WATCH_DONE ok=false reason=open_events_failed elapsedMs={}", monotonic_ms(&start));
        unsafe { dlclose(liblog) };
        return 5;
    }

    let deadline = if duration_ms > 0 { Some(start + Duration::from_millis(duration_ms as u64)) } else { None };
    let (mut events, mut matches, mut starts, mut deaths, mut reconnects) = (0i64, 0i64, 0i64, 0i64, 0i64);
    let mut buf = vec![0u8; LOGGER_ENTRY_MAX_LEN + 1];

    while G_RUNNING.load(Ordering::Relaxed) {
        if let Some(dl) = deadline { if Instant::now() >= dl { break; } }
        buf.fill(0);
        let ret = unsafe { logger_read(list, buf.as_mut_ptr()) };
        if ret == -(EINTR as i32) { continue; }
        if ret == -(EAGAIN as i32) || ret == 0 { std::thread::sleep(Duration::from_millis(50)); continue; }
        if ret < 0 {
            unsafe { logger_free(list); }
            list = std::ptr::null_mut();
            reconnects += 1;
            while G_RUNNING.load(Ordering::Relaxed) && list.is_null() {
                list = unsafe { logger_open(LOG_ID_EVENTS, 0, 0, 0) };
                if list.is_null() { std::thread::sleep(Duration::from_millis(250)); }
            }
            continue;
        }
        // struct logger_entry header: len(u16) hdr_size(u16) pid(i32) tid(u32)
        // sec(u32) nsec(u32) lid(u32) uid(u32) = 28 bytes on the ABI this
        // targets; payload begins at hdr_size (or the struct size if the
        // kernel reports something smaller, matching log_msg_payload()).
        if buf.len() < 4 { continue; }
        let mut hdr_size = u16::from_ne_bytes(buf[2..4].try_into().unwrap()) as usize;
        if hdr_size < 28 { hdr_size = 28; }
        if hdr_size >= buf.len() { continue; }
        let entry_len = u16::from_ne_bytes(buf[0..2].try_into().unwrap()) as usize;
        let payload_end = (hdr_size + entry_len).min(buf.len());
        if payload_end <= hdr_size { continue; }
        let payload = &buf[hdr_size..payload_end];

        let ev = match parse_event_payload(payload) { Some(e) => e, None => continue };
        events += 1;
        if ev.tag == 30014 && ev.strings.len() >= 1 && ev.ints.len() >= 3 {
            let event_user = ev.ints[0] as i32;
            let pid = ev.ints[1] as i32;
            let uid = ev.ints[2] as i32;
            let proc = &ev.strings[0];
            if event_user == user_id && pid > 0 && is_package_process_name(proc, pkg) {
                cache.add(pid, uid);
                matches += 1; starts += 1;
                emit_logd_event("am_proc_start", ev.tag, event_user, pid, uid, proc, &cache, "ok");
            }
            continue;
        }
        if ev.tag == 30011 && ev.ints.len() >= 2 {
            let pid = ev.ints[1] as i32;
            if cache.contains(pid) {
                cache.remove(pid);
                matches += 1; deaths += 1;
                emit_logd_event("am_proc_died", ev.tag, user_id, pid, -1, pkg, &cache, "known-pid");
            }
            continue;
        }
    }

    if !list.is_null() { unsafe { logger_free(list) }; }
    unsafe { dlclose(liblog) };
    println!(
        "CGFREEZER_LOGD_WATCH_DONE ok=true package={} user={} events={} matches={} starts={} deaths={} cachePids={} cacheUid={} reconnects={} elapsedMs={}",
        shell_sanitize(pkg), user_id, events, matches, starts, deaths, cache.pids.len(), cache.uid, reconnects, monotonic_ms(&start)
    );
    0
}


// Faithful port of the C daemon's per-class stat buckets: other/freeze/
// freezePkg/kill/thaw/scan/direct/control, matching g_stat_class_names[]
// and the daemon_note_command()/daemon_stat_note_start/done bookkeeping.
const CGSTAT_CLASSES: usize = 8;
const CGSTAT_NAMES: [&str; CGSTAT_CLASSES] = ["other","freeze","freezePkg","kill","thaw","scan","direct","control"];

#[derive(Clone, Default)]
struct StatClass { count: u64, completed: u64, failed: u64, min_ms: i64, max_ms: i64, last_ms: i64, total_ms: i64 }

#[derive(Clone)]
struct DaemonChild { pid: i32, class: usize, start: Instant }

struct DaemonStats {
    started: Instant, requests: u64, direct: u64, worker: u64,
    last_command: String, last_error: String,
    stat_freeze: u64, stat_freeze_pkg: u64, stat_kill_pkg: u64, stat_thaw: u64, stat_scan: u64,
    classes: [StatClass; CGSTAT_CLASSES],
    children: Vec<DaemonChild>,
}

impl DaemonStats {
    fn active_children(&self) -> usize { self.children.len() }
}

impl Default for DaemonStats {
    fn default() -> Self { Self {
        started: Instant::now(), requests: 0, direct: 0, worker: 0, last_command: "none".into(), last_error: "none".into(),
        stat_freeze: 0, stat_freeze_pkg: 0, stat_thaw: 0, stat_scan: 0, stat_kill_pkg: 0,
        classes: Default::default(),
        children: Vec::new(),
    } }
}

/// Faithful port of daemon_cmd_class(): maps a worker OR parent-direct
/// command name to one of the 8 stat buckets. Parent commands
/// (HELLO/CAPS/PING/STATUS/STATS/STATS_DETAIL/LAST_ERROR/BACKEND_PROBE) map
/// to class 7 "control" - the previous implementation only classified
/// worker commands and left every parent-direct command uncounted in
/// STATS_DETAIL's "control" row entirely.
fn daemon_cmd_class(cmd: &str) -> usize {
    match cmd {
        "FREEZE" | "FREEZE_PID_LIST" => 1,
        "FREEZE_PKG" => 2,
        "KILL_PKG" | "KILL_PID_LIST" => 3,
        c if c.starts_with("THAW") => 4,
        "SCAN" | "PROC_SNAPSHOT" | "WCHAN_PID_LIST" | "WCHAN_UID" | "SUBSCRIBE" => 5,
        "HELLO" | "CAPS" | "PING" | "STATUS" | "STATS" | "STATS_DETAIL" | "LAST_ERROR" | "BACKEND_PROBE" => 7,
        _ => 0,
    }
}

fn daemon_note_command(stats: &mut DaemonStats, cmd: &str) {
    match cmd {
        "FREEZE" | "FREEZE_PID_LIST" => stats.stat_freeze += 1,
        "FREEZE_PKG" => stats.stat_freeze_pkg += 1,
        "KILL_PKG" | "KILL_PID_LIST" => stats.stat_kill_pkg += 1,
        c if c.starts_with("THAW") => stats.stat_thaw += 1,
        "SCAN" | "PROC_SNAPSHOT" | "WCHAN_PID_LIST" | "WCHAN_UID" => stats.stat_scan += 1,
        _ => {}
    }
}

/// Faithful port of daemon_stat_note_start(): increments the class's
/// request count at the moment a command begins processing, separate from
/// daemon_stat_note_done()'s completed/failed/timing bookkeeping recorded
/// afterward. This two-phase split matters: a command that queries its own
/// stats (e.g. STATS_DETAIL) will see itself counted in `count` but not yet
/// in `completed`, since its own completion is recorded only after its
/// response body has already been built.
fn daemon_stat_note_start(stats: &mut DaemonStats, class: usize) {
    stats.classes[class].count += 1;
}

fn daemon_stat_note_done(stats: &mut DaemonStats, class: usize, elapsed_ms: i64, failed: bool) {
    let c = &mut stats.classes[class];
    let elapsed_ms = elapsed_ms.max(0);
    c.completed += 1;
    if failed { c.failed += 1; }
    c.total_ms += elapsed_ms;
    c.last_ms = elapsed_ms;
    if c.min_ms == 0 || elapsed_ms < c.min_ms { c.min_ms = elapsed_ms; }
    if elapsed_ms > c.max_ms { c.max_ms = elapsed_ms; }
}

fn daemon_child_add(stats: &mut DaemonStats, pid: i32, class: usize, start: Instant) {
    if pid <= 0 || stats.children.len() >= MAX_DAEMON_CHILDREN { return; }
    stats.children.push(DaemonChild { pid, class, start });
}

fn wifexited(status: c_int) -> bool { (status & 0x7f) == 0 }
fn wexitstatus(status: c_int) -> c_int { (status >> 8) & 0xff }

fn daemon_child_remove(stats: &mut DaemonStats, pid: i32, status: c_int) {
    if pid <= 0 { return; }
    if let Some(pos) = stats.children.iter().position(|c| c.pid == pid) {
        let child = stats.children.remove(pos);
        let failed = !(wifexited(status) && wexitstatus(status) == 0);
        daemon_stat_note_done(stats, child.class, child.start.elapsed().as_millis() as i64, failed);
    }
}

fn reap_children_nonblock(stats: &mut DaemonStats) {
    loop {
        let mut status: c_int = 0;
        let pid = unsafe { waitpid(-1, &mut status as *mut c_int, WNOHANG) };
        if pid <= 0 { break; }
        daemon_child_remove(stats, pid, status);
    }
}

fn daemon_stop_children_bounded(stats: &mut DaemonStats) {
    for child in &stats.children { unsafe { kill(child.pid, SIGTERM_DAEMON); } }
    let deadline = Instant::now() + Duration::from_millis(500);
    while stats.active_children() > 0 && Instant::now() < deadline {
        reap_children_nonblock(stats);
        std::thread::sleep(Duration::from_millis(10));
    }
    for child in &stats.children { unsafe { kill(child.pid, SIGKILL); } }
    let deadline = Instant::now() + Duration::from_millis(200);
    while stats.active_children() > 0 && Instant::now() < deadline {
        reap_children_nonblock(stats);
        std::thread::sleep(Duration::from_millis(10));
    }
    reap_children_nonblock(stats);
}

// r534: daemon worker commands share the same CLI cmd_* logic through
// with_cgfreezer_output(), an in-process writer sink. This deliberately avoids
// the rejected stdout-capture/dup2 pipe design while removing the previous
// daemon-vs-CLI split for FREEZE/THAW/KILL/CHECK/SCAN.

fn handle_worker_to<W: Write>(args: &[String], out: &mut W) -> i32 {
    with_cgfreezer_output(out, || {
        if args.is_empty() {
            println!("CGFREEZER_DAEMON_RESULT ok=false reason=empty");
            return 64;
        }
        match args.get(0).map(|s| s.as_str()) {
            Some("HELLO") => {
                println!("CGFREEZER_DAEMON_HELLO ok=true version={} pid={} protocol={} parentDirect=false", VERSION, std::process::id(), PROTOCOL);
                0
            }
            Some("CAPS") => {
                println!("CGFREEZER_DAEMON_CAPS ok=true version={} protocol={} caps={}", VERSION, PROTOCOL, CAPS);
                0
            }
            Some("BACKEND_PROBE") => cmd_backend_probe(),
            Some("CHECK") | Some("CHECK_ROOT") => cmd_check_root(),
            Some("SCAN") => {
                if args.len() < 3 {
                    println!("CGFREEZER_SCAN_DONE ok=false reason=bad_args");
                    64
                } else {
                    cmd_scan_package(args.get(1).map(String::as_str).unwrap_or(""), parse_i(args.get(2), 0))
                }
            }
            // Keep daemon worker dispatch strict to C handle_daemon_command_line().
            // FREEZE_PID_LIST/KILL_PID_LIST/PROC_SNAPSHOT are socket-client
            // helper command strings or stats classification names, not real
            // daemon parent-dispatched worker commands; unknown tokens must fall
            // through to C-compatible unknown_command handling.
            Some("FREEZE") => {
                if args.len() < 3 {
                    println!("CGFREEZER_FREEZE_DONE ok=false reason=bad_args");
                    64
                } else {
                    let pid = parse_i(args.get(1), -1);
                    let mut timeout = parse_ms(args.get(2), 1500);
                    if pid <= 0 {
                        println!("CGFREEZER_FREEZE_DONE ok=false reason=bad_pid pid={}", pid);
                        64
                    } else {
                        if timeout < 100 || timeout > 5000 { timeout = 1500; }
                        cmd_freeze_pid(pid, timeout)
                    }
                }
            }
            Some("FREEZE_PKG") => {
                if args.len() < 4 {
                    println!("CGFREEZER_FREEZE_PKG_DONE ok=false reason=bad_args");
                    64
                } else {
                    let user = parse_i(args.get(2), 0);
                    let mut timeout = parse_ms(args.get(3), 1500);
                    if timeout < 100 || timeout > 5000 { timeout = 1500; }
                    cmd_freeze_package(args.get(1).map(String::as_str).unwrap_or(""), user, timeout)
                }
            }
            Some("KILL_PKG") => {
                if args.len() < 5 {
                    println!("CGFREEZER_KILL_PKG_DONE ok=false reason=bad_args");
                    64
                } else {
                    let user = parse_i(args.get(2), 0);
                    let event_pid = parse_i(args.get(3), -1);
                    let mut timeout = parse_ms(args.get(4), 800);
                    if timeout < 100 || timeout > 5000 { timeout = 800; }
                    cmd_kill_package(args.get(1).map(String::as_str).unwrap_or(""), user, event_pid, timeout)
                }
            }
            Some("THAW") => {
                if args.len() < 4 {
                    println!("CGFREEZER_THAW_DONE ok=false reason=bad_args");
                    64
                } else {
                    let mut timeout = parse_ms(args.get(3), 1500);
                    if timeout < 100 || timeout > 5000 { timeout = 1500; }
                    cmd_thaw_path(
                        args.get(1).map(String::as_str).unwrap_or("-"),
                        args.get(2).map(String::as_str).unwrap_or("0"),
                        timeout,
                    )
                }
            }
            Some("THAW_PID") => {
                if args.len() < 5 {
                    println!("CGFREEZER_THAW_DONE ok=false reason=bad_args");
                    64
                } else {
                    let pid = parse_i(args.get(1), -1);
                    let mut timeout = parse_ms(args.get(4), 1500);
                    if pid <= 0 {
                        println!("CGFREEZER_THAW_DONE ok=false reason=bad_pid pid={}", pid);
                        64
                    } else {
                        if timeout < 100 || timeout > 5000 { timeout = 1500; }
                        cmd_thaw_pid(
                            pid,
                            args.get(2).map(String::as_str).unwrap_or("-"),
                            args.get(3).map(String::as_str).unwrap_or("0"),
                            timeout,
                        )
                    }
                }
            }
            Some("THAW_UID") => {
                if args.len() < 3 {
                    println!("CGFREEZER_THAW_UID_DONE ok=false reason=bad_args");
                    64
                } else {
                    let uid = parse_i(args.get(1), -1);
                    let mut timeout = parse_ms(args.get(2), 1500);
                    if timeout < 100 || timeout > 5000 { timeout = 1500; }
                    cmd_thaw_uid(uid as u32, timeout)
                }
            }
            Some("WCHAN_PID_LIST") => {
                if args.len() < 3 {
                    println!("CGFREEZER_WCHAN_DONE ok=false origin=pid-list reason=bad_args");
                    64
                } else {
                    let user = parse_i(args.get(1), -1);
                    let target = args.get(2).map(String::as_str).unwrap_or("-");
                    let expect = args.get(3).map(String::as_str).unwrap_or("any");
                    let st = Instant::now();
                    let mut out = CgfreezerCurrentOutput;
                    run_wchan_pid_list(&mut out, user, target, expect, &st)
                }
            }
            Some("WCHAN_UID") => {
                if args.len() < 2 {
                    println!("CGFREEZER_WCHAN_UID_DONE ok=false reason=bad_args");
                    64
                } else {
                    let uid = parse_i(args.get(1), -1);
                    let expect = args.get(2).map(String::as_str).unwrap_or("any");
                    let st = Instant::now();
                    let mut out = CgfreezerCurrentOutput;
                    run_wchan_uid(&mut out, uid, expect, &st)
                }
            }
            Some("BINDER_INFO") => {
                if args.len() < 2 {
                    println!("CGFREEZER_BINDER_INFO ok=false reason=bad_args");
                    64
                } else {
                    let pid = parse_i(args.get(1), -1);
                    if pid <= 0 {
                        println!("CGFREEZER_BINDER_INFO ok=false reason=bad_pid pid={}", pid);
                        64
                    } else {
                        cmd_binder_info(pid)
                    }
                }
            }
            Some("SUBSCRIBE") => {
                if args.len() < 4 {
                    println!("CGFREEZER_LOGD_WATCH_DONE ok=false reason=bad_args");
                    64
                } else {
                    let mut duration = parse_ms(args.get(3), 0);
                    if duration < 0 { duration = 0; }
                    cmd_watch_logd(
                        args.get(1).map(String::as_str).unwrap_or(""),
                        parse_i(args.get(2), 0),
                        duration,
                    )
                }
            }
            Some("EXIT") | Some("STOP") => {
                println!("CGFREEZER_DAEMON_EXIT ok=true pid={}", std::process::id());
                G_RUNNING.store(false, Ordering::Relaxed);
                0
            }
            _ => {
                println!("CGFREEZER_DAEMON_RESULT ok=false reason=unknown_command command={}", shell_sanitize(args.get(0).map(String::as_str).unwrap_or("")));
                64
            }
        }
    })
}

fn daemon_ascii_fields(line: &str, max_fields: usize) -> Vec<&str> {
    let b = line.as_bytes();
    let mut out = Vec::new();
    let mut i = 0usize;
    while i < b.len() && out.len() < max_fields {
        while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
        if i >= b.len() { break; }
        let st = i;
        while i < b.len() && !matches!(b[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
        match std::str::from_utf8(&b[st..i]) {
            Ok(v) => out.push(v),
            Err(_) => break,
        }
    }
    out
}

fn handle_parent(line: &str, stats: &DaemonStats, socket: &str) -> Option<(bool, String)> {
    let uptime = stats.started.elapsed().as_millis() as i64;
    // C handle_daemon_parent_command() tokenizes the line and matches only
    // argv[0]; trailing tokens do not force the command into worker dispatch.
    let cmd = daemon_ascii_fields(line, 1).into_iter().next()?;
    match cmd {
        "HELLO" => Some((false, format!("CGFREEZER_DAEMON_HELLO ok=true version={} pid={} protocol={} parentDirect=true\n", VERSION, std::process::id(), PROTOCOL))),
        "CAPS" => Some((false, format!("CGFREEZER_DAEMON_CAPS ok=true version={} protocol={} caps={} parentDirect=true\n", VERSION, PROTOCOL, CAPS))),
        "PING" => Some((false, format!("CGFREEZER_DAEMON_PONG ok=true version={} pid={} uptimeMs={} activeChildren={}\n", VERSION, std::process::id(), uptime, stats.active_children()))),
        "STATUS" => {
            let (pb, pr) = preferred_backend();
            let mut body = format!(
                "CGFREEZER_DAEMON_STATUS ok=true version={} pid={} protocol=plain-lines-r253 lineProtocol={} uptimeMs={} requests={} directRequests={} workerRequests={} activeChildren={} socket={} running=1 freeze={} freezePkg={} killPkg={} thaw={} scan={} lastCommand={} lastError={} backendPreferred={} backendReason={} backendProbeMs={} backendV1Mount={} hash=0 policy=facts-only\n",
                VERSION, std::process::id(), PROTOCOL, uptime, stats.requests, stats.direct, stats.worker, stats.active_children(),
                socket, stats.stat_freeze, stats.stat_freeze_pkg, stats.stat_kill_pkg, stats.stat_thaw, stats.stat_scan,
                stats.last_command, stats.last_error,
                pb, pr, G_FREEZE_BACKEND_PROBE_MS.with(|c| *c.borrow()), v1_mount_hint()
            );
            body.push_str("CGFREEZER_DAEMON_STATUS_END ok=true rows=1\n");
            Some((false, body))
        }
        "STATS" => {
            let mut body = format!("CGFREEZER_DAEMON_STATS ok=true version={} pid={} uptimeMs={} protocol=plain-lines-r253 hash=0 policy=facts-only\n", VERSION, std::process::id(), uptime);
            body.push_str(&format!(
                "CGFREEZER_DAEMON_STATS_ROW class=summary requests={} directRequests={} workerRequests={} activeChildren={} freeze={} freezePkg={} killPkg={} thaw={} scan={} lastCommand={}\n",
                stats.requests, stats.direct, stats.worker, stats.active_children(), stats.stat_freeze, stats.stat_freeze_pkg, stats.stat_kill_pkg, stats.stat_thaw, stats.stat_scan, stats.last_command
            ));
            body.push_str("CGFREEZER_DAEMON_STATS_END ok=true rows=1\n");
            Some((false, body))
        }
        "STATS_DETAIL" => {
            let mut body = format!("CGFREEZER_DAEMON_STATS_DETAIL ok=true version={} pid={} uptimeMs={} protocol=plain-lines-r253 hash=0 policy=facts-only\n", VERSION, std::process::id(), uptime);
            for i in 0..CGSTAT_CLASSES {
                let c = &stats.classes[i];
                let avg = if c.completed > 0 { c.total_ms / c.completed as i64 } else { 0 };
                // Faithful port: C's p95Ms field is literally maxMs duplicated
                // (see the dprintf call - both %ld args are g_stat_detail_max_ms[i]),
                // not a real percentile - kept identical rather than "improved".
                body.push_str(&format!(
                    "CGFREEZER_DAEMON_STATS_DETAIL_ROW class={} count={} completed={} failed={} minMs={} avgMs={} p95Ms={} maxMs={} lastMs={}\n",
                    CGSTAT_NAMES[i], c.count, c.completed, c.failed, c.min_ms, avg, c.max_ms, c.max_ms, c.last_ms
                ));
            }
            body.push_str(&format!("CGFREEZER_DAEMON_STATS_DETAIL_END ok=true rows={}\n", CGSTAT_CLASSES));
            Some((false, body))
        }
        "LAST_ERROR" => {
            let mut body = format!("CGFREEZER_DAEMON_LAST_ERROR ok=true version={} pid={} protocol=plain-lines-r253 lastError={} lastCommand={} hash=0 policy=facts-only\n", VERSION, std::process::id(), stats.last_error, stats.last_command);
            body.push_str("CGFREEZER_DAEMON_LAST_ERROR_END ok=true rows=1\n");
            Some((false, body))
        }
        "BACKEND_PROBE" => {
            let (p, r) = preferred_backend();
            let probe_ms = G_FREEZE_BACKEND_PROBE_MS.with(|c| *c.borrow());
            Some((false, format!("CGFREEZER_BACKEND_PROBE ok=true preferred={} preferredReason={} v1Mount={} cache=true elapsedMs={}\n", p, r, v1_mount_hint(), probe_ms)))
        }
        "EXIT" | "STOP" => Some((true, format!("CGFREEZER_DAEMON_EXIT ok=true version={} pid={} protocol={} parentDirect=true activeChildren={}\n", VERSION, std::process::id(), PROTOCOL, stats.active_children()))),
        _ => None,
    }
}



fn cmd_daemon(socket_path: &str) -> i32 {
    if socket_path.is_empty() || socket_path.as_bytes().len() >= UNIX_SUN_PATH_MAX {
        println!("CGFREEZER_DAEMON_START ok=false reason=bad_socket_path");
        return 2;
    }
    G_RUNNING.store(true, Ordering::Relaxed);
    unsafe {
        signal(SIGTERM_LOGD, on_signal_logd as usize);
        signal(SIGINT_LOGD, on_signal_logd as usize);
        signal(13 /* SIGPIPE */, 1usize /* SIG_IGN */);
    }

    // Match C cmd_daemon() exactly enough to preserve its public rc/reason
    // contract: socket() => rc 3, bind() => rc 4, listen() => rc 5, backlog 8.
    let listen_fd = unsafe { socket(C_AF_UNIX, C_SOCK_STREAM | C_SOCK_CLOEXEC, 0) };
    if listen_fd < 0 {
        println!("CGFREEZER_DAEMON_START ok=false reason=socket_errno_{}", errno_now());
        return 3;
    }
    let _ = fs::remove_file(socket_path); // C unlink() result is intentionally ignored.
    let mut addr = SockAddrUn { sun_family: C_AF_UNIX as u16, sun_path: [0; UNIX_SUN_PATH_MAX] };
    for (i, &b) in socket_path.as_bytes().iter().enumerate() {
        addr.sun_path[i] = b as c_char;
    }
    let bind_rc = unsafe {
        bind(
            listen_fd,
            &addr as *const SockAddrUn as *const c_void,
            std::mem::size_of::<SockAddrUn>() as u32,
        )
    };
    if bind_rc != 0 {
        let e = errno_now();
        unsafe { close(listen_fd); }
        println!("CGFREEZER_DAEMON_START ok=false reason=bind_errno_{} socket={}", e, shell_sanitize(socket_path));
        return 4;
    }
    let _ = fs::set_permissions(socket_path, fs::Permissions::from_mode(0o600));
    if unsafe { listen(listen_fd, 8) } != 0 {
        let e = errno_now();
        unsafe { close(listen_fd); }
        let _ = fs::remove_file(socket_path);
        println!("CGFREEZER_DAEMON_START ok=false reason=listen_errno_{} socket={}", e, shell_sanitize(socket_path));
        return 5;
    }

    let mut stats = DaemonStats::default();
    cgfb_ensure_global(true);
    let backend_probe_ms = G_FREEZE_BACKEND_PROBE_MS.with(|c| *c.borrow());
    let (backend_preferred, backend_reason) = preferred_backend();
    println!("CGFREEZER_DAEMON_START ok=true version={} pid={} socket={} protocol={} parentControl=true backendPreferred={} backendReason={} backendProbeMs={}",
        VERSION, std::process::id(), shell_sanitize(socket_path), PROTOCOL, backend_preferred, shell_sanitize(&backend_reason), backend_probe_ms);

    while G_RUNNING.load(Ordering::Relaxed) {
        reap_children_nonblock(&mut stats);
        let cfd = unsafe { accept4(listen_fd, std::ptr::null_mut(), std::ptr::null_mut(), C_SOCK_CLOEXEC) };
        if cfd < 0 {
            if errno_now() == EINTR { continue; }
            std::thread::sleep(Duration::from_millis(50));
            continue;
        }
        let mut stream = unsafe { UnixStream::from_raw_fd(cfd) };
        // C daemon framing is one raw read per accepted connection, capped at
        // sizeof(line)-1 == 4095 bytes. It does not wait for a newline.
        let mut raw = [0u8; 4095];
        let n = match stream.read(&mut raw) {
            Ok(n) => n,
            Err(_) => 0, // C performs one read only; EINTR is not retried here.
        };
        if n == 0 { continue; }
        let used = raw[..n].iter().position(|&b| b == 0).unwrap_or(n);
        let line = String::from_utf8_lossy(&raw[..used]).into_owned();
        stats.requests += 1;
        let cmd_name = daemon_ascii_fields(&line, 1).into_iter().next().unwrap_or("").to_string();
        if !cmd_name.is_empty() { stats.last_command = c_truncate_bytes(&cmd_name, 63); }
        let class = daemon_cmd_class(&cmd_name);
        daemon_stat_note_start(&mut stats, class);
        let cmd_start = Instant::now();
        if !cmd_name.is_empty() { daemon_note_command(&mut stats, &cmd_name); }
        if let Some((stop, resp)) = handle_parent(&line, &stats, socket_path) {
            stats.direct += 1;
            daemon_stat_note_done(&mut stats, class, monotonic_ms(&cmd_start) as i64, false);
            let _ = stream.write_all(resp.as_bytes());
            let _ = stream.flush();
            let _ = stream.shutdown(Shutdown::Write);
            if stop { G_RUNNING.store(false, Ordering::Relaxed); }
            continue;
        }
        let args: Vec<String> = daemon_ascii_fields(&line, 8).into_iter().map(str::to_owned).collect();
        let child = unsafe { fork() };
        if child == 0 {
            unsafe { close(listen_fd); }
            let rc = handle_worker_to(&args, &mut stream);
            let _ = stream.flush();
            unsafe { _exit(if rc == 0 { 0 } else { rc & 0xff }); }
        } else if child > 0 {
            stats.worker += 1;
            daemon_child_add(&mut stats, child, class, cmd_start);
            // Faithful port of the C daemon's unconditional close(cfd) at the
            // end of the accept loop body: after forking, the PARENT must
            // drop its own copy of the connection fd immediately, not wait
            // for the next loop iteration's `stream` rebinding to drop it.
            // Without this, both parent and child hold the same underlying
            // socket open; the kernel does not consider the connection
            // closed/EOF until *all* references are gone, so a client doing
            // a single recv() can get back a truncated read of whatever the
            // child had flushed by that point instead of the full response
            // followed by a clean EOF - this was reproduced with a real
            // FREEZE call over the daemon socket (client received only
            // "CGFREEZER_FREEZE_DONE ok=" with everything after it missing).
            drop(stream);
        } else {
            let e = errno_now();
            stats.last_error = format!("fork_errno_{} cmd={}", e, stats.last_command);
            let _ = writeln!(stream, "CGFREEZER_DAEMON_RESULT ok=false reason=fork_errno_{}", e);
            let _ = stream.flush();
            drop(stream);
        }
    }
    unsafe { close(listen_fd); }
    let _ = fs::remove_file(socket_path);
    daemon_stop_children_bounded(&mut stats);
    println!("CGFREEZER_DAEMON_DONE ok=true version={} socket={} requests={} directRequests={} workerRequests={} activeChildren={}", VERSION, shell_sanitize(socket_path), stats.requests, stats.direct, stats.worker, stats.active_children());
    0
}

fn main_rc(args: &[String]) -> i32 {
    if args.len() < 2 { return usage(); }
    if args.len() == 2 && (args[1] == "--version" || args[1] == "version") {
        println!("cgfreezer {}", VERSION);
        return 0;
    }
    match args[1].as_str() {
        "check-root" => cmd_check_root(),
        "backend-probe" => cmd_backend_probe(),
        "scan-package" => {
            if args.len() < 4 { return 64; }
            cmd_scan_package(args[2].as_str(), parse_i(args.get(3), 0))
        }
        "freeze-pid" => {
            if args.len() < 4 { return 64; }
            let pid = parse_i(args.get(2), -1);
            if pid <= 0 { return 64; }
            cmd_freeze_pid(pid, bounded_timeout_ms(parse_ms(args.get(3), 1500), 1500))
        }
        "freeze-package" => {
            if args.len() < 5 { return 64; }
            cmd_freeze_package(args[2].as_str(), parse_i(args.get(3), 0), parse_ms(args.get(4), 1500))
        }
        "freeze-pid-list" => {
            if args.len() < 5 { return 64; }
            cmd_freeze_pid_list(parse_i(args.get(2), 0), args[3].as_str(), parse_ms(args.get(4), 1500))
        }
        "kill-package" => {
            if args.len() < 6 { return 64; }
            cmd_kill_package(args[2].as_str(), parse_i(args.get(3), 0), parse_i(args.get(4), -1), parse_ms(args.get(5), 800))
        }
        "kill-pid-list" => {
            if args.len() < 5 { return 64; }
            cmd_kill_pid_list(parse_i(args.get(2), 0), args[3].as_str(), parse_i(args.get(4), SIGKILL))
        }
        "proc-snapshot" => {
            if args.len() < 4 { return 64; }
            cmd_proc_snapshot(args[2].as_str(), parse_i(args.get(3), 0))
        }
        "proc-wchan" => {
            if args.len() < 4 { return 64; }
            cmd_proc_wchan(parse_i(args.get(2), -1), args[3].as_str(), args.get(4).map(String::as_str).unwrap_or("any"))
        }
        "uid-wchan" => {
            if args.len() < 3 { return 64; }
            cmd_uid_wchan(parse_i(args.get(2), -1), args.get(3).map(String::as_str).unwrap_or("any"))
        }
        "thaw-path" => {
            if args.len() < 5 { return 64; }
            cmd_thaw_path(args[2].as_str(), args[3].as_str(), bounded_timeout_ms(parse_ms(args.get(4), 1500), 1500))
        }
        "thaw-pid" => {
            if args.len() < 6 { return 64; }
            let pid = parse_i(args.get(2), -1);
            if pid <= 0 { return 64; }
            cmd_thaw_pid(pid, args[3].as_str(), args[4].as_str(), bounded_timeout_ms(parse_ms(args.get(5), 1500), 1500))
        }
        "thaw-uid" => {
            if args.len() < 4 { return 64; }
            let uid = parse_i(args.get(2), -1);
            cmd_thaw_uid(uid as u32, parse_ms(args.get(3), 1500))
        }
        "binder-info" => {
            if args.len() < 3 { return 64; }
            let pid = parse_i(args.get(2), -1);
            if pid <= 0 { return 64; }
            cmd_binder_info(pid)
        }
        "watch-logd" => {
            if args.len() < 5 { return 64; }
            let duration = parse_ms(args.get(4), 0).max(0);
            cmd_watch_logd(args[2].as_str(), parse_i(args.get(3), 0), duration)
        }
        "daemon" => {
            if args.len() < 3 { return 64; }
            cmd_daemon(args[2].as_str())
        }
        other => unknown_usage(other),
    }
}

fn main() { std::process::exit(main_rc(&std::env::args().collect::<Vec<_>>())); }
