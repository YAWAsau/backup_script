// procwait.rs - faithful Rust port of c/procwait.c
// waitpid/pidfd based process waiter. Output markers, exit codes, and the
// "pidfd only, never fall back to polling for the `pid` subcommand" design
// are reproduced exactly against c/procwait.c.

use speedbackup_native_rs::{c_strerror, poll, syscall, PollFd, POLLIN, SYS_PIDFD_OPEN};
use std::ffi::CString;
use std::os::raw::{c_char, c_int};
use std::time::Instant;

const VERSION: &str = speedbackup_native_rs::versions::PROCWAIT;
use speedbackup_native_rs::BUILD_VERSION;
const EINTR: i32 = 4;
const ESRCH: i32 = 3;
const ENOSYS: i32 = 38;
const EINVAL: i32 = 22;

extern "C" {
    fn fork() -> i32;
    fn execvp(file: *const c_char, argv: *const *const c_char) -> i32;
    fn waitpid(pid: i32, status: *mut c_int, options: c_int) -> i32;
    fn close(fd: c_int) -> c_int;
    fn _exit(status: c_int) -> !;
}

fn errno_now() -> i32 {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

/// Faithful port of wait_child(): fork+execvp+waitpid, printing the same
/// EXIT/SIGNAL/STATE markers and returning the same exit codes as C.
fn wait_child(command: &[String]) -> i32 {
    let cstrings: Vec<CString> = command
        .iter()
        .map(|a| CString::new(a.as_str()).unwrap_or_else(|_| CString::new("").unwrap()))
        .collect();
    let mut argv: Vec<*const c_char> = cstrings.iter().map(|c| c.as_ptr()).collect();
    argv.push(std::ptr::null());

    let child = unsafe { fork() };
    if child < 0 {
        eprintln!(
            "procwait: fork: {}",
            c_strerror(&std::io::Error::last_os_error())
        );
        return 1;
    }
    if child == 0 {
        unsafe {
            execvp(cstrings[0].as_ptr(), argv.as_ptr());
        }
        eprintln!(
            "procwait: execvp: {}",
            c_strerror(&std::io::Error::last_os_error())
        );
        unsafe { _exit(127) }
    }

    let mut status: c_int = 0;
    loop {
        let result = unsafe { waitpid(child, &mut status as *mut c_int, 0) };
        if result == child {
            break;
        }
        if result < 0 && errno_now() == EINTR {
            continue;
        }
        eprintln!(
            "procwait: waitpid: {}",
            c_strerror(&std::io::Error::last_os_error())
        );
        return 1;
    }

    // Linux wait status encoding: matches <sys/wait.h> WIFEXITED/WEXITSTATUS/
    // WIFSIGNALED/WTERMSIG bit layout exactly (stable kernel ABI).
    if status & 0x7f == 0 {
        let code = (status >> 8) & 0xff;
        println!("EXIT pid={} code={}", child, code);
        return code;
    }
    if ((status & 0x7f) + 1) as i8 >> 1 > 0 {
        let signo = status & 0x7f;
        println!("SIGNAL pid={} signal={}", child, signo);
        return 128 + signo;
    }
    println!("STATE pid={} status=0x{:x}", child, status);
    1
}

/// Faithful port of pidfd_open_compat()+wait_pidfd(): pidfd_open()+poll(),
/// with NO fallback to sleep/poll(/proc) style waiting on ENOSYS/EINVAL -
/// the C version deliberately errors out instead (exit 3), and this must
/// not silently degrade to polling.
fn wait_pidfd(pid: i32) -> i32 {
    if pid <= 0 {
        eprintln!("procwait: PID 必須大於 0");
        return 2;
    }
    let fd = unsafe { syscall(SYS_PIDFD_OPEN, pid, 0) } as i32;
    if fd < 0 {
        let e = errno_now();
        if e == ESRCH {
            println!("EXIT pid={} already-gone=1", pid);
            return 0;
        }
        if e == ENOSYS || e == EINVAL {
            eprintln!("procwait: 此核心不支援 pidfd_open；不使用輪詢 fallback");
            return 3;
        }
        eprintln!(
            "procwait: pidfd_open: {}",
            c_strerror(&std::io::Error::last_os_error())
        );
        return 1;
    }

    let mut pfd = PollFd {
        fd,
        events: POLLIN,
        revents: 0,
    };
    loop {
        let result = unsafe { poll(&mut pfd as *mut PollFd, 1, -1) };
        if result > 0 {
            break;
        }
        if result < 0 && errno_now() == EINTR {
            continue;
        }
        eprintln!(
            "procwait: poll: {}",
            c_strerror(&std::io::Error::last_os_error())
        );
        unsafe { close(fd) };
        return 1;
    }
    println!("EXIT pid={} pidfd=1 revents=0x{:x}", pid, pfd.revents);
    unsafe { close(fd) };
    0
}

fn numeric_name(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

/// Faithful port of read_cmdline_first(): reads /proc/PID/cmdline and returns
/// only the first NUL-terminated argv[0] field (matches C's early-break loop).
fn read_cmdline_first(pid: i32) -> std::io::Result<Option<String>> {
    use std::io::Read as _;
    let mut f = std::fs::File::open(format!("/proc/{}/cmdline", pid))?;
    let mut raw = Vec::new();
    let mut chunk = [0u8; 512];
    loop {
        let n = match f.read(&mut chunk) {
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            other => other?,
        };
        let end = chunk[..n].iter().position(|&b| b == 0);
        raw.extend_from_slice(&chunk[..end.unwrap_or(n)]);
        if raw.len() > 65536 {
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "argv0 exceeds limit"));
        }
        if end.is_some() || n == 0 { break; }
    }
    if raw.is_empty() { return Ok(None); }
    Ok(Some(String::from_utf8_lossy(&raw).into_owned()))
}

fn append_pid_capped(out: &mut String, token: &str) {
    const CAP: usize = 2048;
    let used = out.len();
    if CAP <= used + 2 {
        return;
    }
    let frag = if used == 0 {
        token.to_string()
    } else {
        format!(",{}", token)
    };
    let room = CAP - used;
    if frag.len() >= room {
        return; // Diagnostics may omit whole PIDs, never emit a truncated PID.
    } else {
        out.push_str(&frag);
    }
}

/// Faithful port of cmdline_matches_package(): cmd == pkg, or cmd starts with
/// "pkg:" (multi-process package convention, e.g. com.app:remote).
fn cmdline_matches_package(cmd: &str, pkg: &str) -> bool {
    if cmd.is_empty() || pkg.is_empty() {
        return false;
    }
    if let Some(rest) = cmd.strip_prefix(pkg) {
        rest.is_empty() || rest.starts_with(':')
    } else {
        false
    }
}

/// Faithful port of scan_package_pids(): walk /proc, match each numeric PID's
/// cmdline[0] against the package name. Returns (pids, count); pids is a
/// comma-joined list capped the same way the C 2048-byte buffer effectively is.
fn scan_package_pids(pkg: &str, user: u32) -> Result<(String, usize), i32> {
    let mut out = String::new();
    let mut count = 0usize;
    let entries = match std::fs::read_dir("/proc") {
        Ok(v) => v,
        Err(e) => return Err(e.raw_os_error().unwrap_or(-1)),
    };
    for entry in entries {
        let entry = entry.map_err(|e| e.raw_os_error().unwrap_or(-1))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if !numeric_name(&name) {
            continue;
        }
        let pid: i64 = match name.parse() {
            Ok(v) if v > 0 && v <= i32::MAX as i64 => v,
            _ => continue,
        };
        use std::os::unix::fs::MetadataExt;
        let meta = match std::fs::symlink_metadata(format!("/proc/{pid}")) {
            Ok(m) => m,
            Err(e) if matches!(e.raw_os_error(), Some(2) | Some(3)) => continue,
            Err(e) => return Err(e.raw_os_error().unwrap_or(-1)),
        };
        if meta.uid() / 100000 != user { continue; }
        let cmd = match read_cmdline_first(pid as i32) {
            Ok(Some(v)) => v,
            Ok(None) => continue,
            Err(e) if matches!(e.raw_os_error(), Some(2) | Some(3)) => continue,
            Err(e) => return Err(e.raw_os_error().unwrap_or(-1)),
        };
        if !cmdline_matches_package(&cmd, pkg) {
            continue;
        }
        count += 1;
        append_pid_capped(&mut out, &pid.to_string());
    }
    Ok((out, count))
}

/// Faithful port of scan_uid_pids(): walk /proc, lstat each numeric PID entry
/// and match st_uid. Uses symlink_metadata (lstat), matching C's lstat() call
/// (the /proc/PID entries are directories, not symlinks, but this mirrors the
/// exact syscall C uses rather than substituting a following stat()).
fn scan_uid_pids(uid: u32) -> Result<(String, usize), i32> {
    use std::os::unix::fs::MetadataExt;
    let mut out = String::new();
    let mut count = 0usize;
    let entries = match std::fs::read_dir("/proc") {
        Ok(v) => v,
        Err(e) => return Err(e.raw_os_error().unwrap_or(-1)),
    };
    for entry in entries {
        let entry = entry.map_err(|e| e.raw_os_error().unwrap_or(-1))?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if !numeric_name(&name) {
            continue;
        }
        let meta = match std::fs::symlink_metadata(format!("/proc/{}", name)) {
            Ok(v) => v,
            Err(e) if matches!(e.raw_os_error(), Some(2) | Some(3)) => continue,
            Err(e) => return Err(e.raw_os_error().unwrap_or(-1)),
        };
        if meta.uid() != uid {
            continue;
        }
        let stat = match std::fs::read_to_string(format!("/proc/{}/stat", name)) {
            Ok(v) => v,
            Err(e) if matches!(e.raw_os_error(), Some(2) | Some(3)) => continue,
            Err(e) => return Err(e.raw_os_error().unwrap_or(-1)),
        };
        let state = stat.rsplit_once(')').and_then(|(_, s)| s.split_whitespace().next()).ok_or(5)?;
        if matches!(state, "Z" | "X") { continue; }
        count += 1;
        append_pid_capped(&mut out, &name);
    }
    Ok((out, count))
}

// Keep package/UID re-scans: pidfds observe existing processes, not new ones.
// Schedule scan starts on a bounded cadence; scanning itself must not add a
// fresh 20ms sleep. The last scan still occurs after the full quiet interval.
#[derive(Default)]
struct ScanWaitStats { enabled: bool, scans: u64, scan_us: u128, wait_us: u128,
    pidfds: u64, wakes: u64, fallback: u64 }
impl Drop for ScanWaitStats {
    fn drop(&mut self) {
        if self.enabled {
            use std::io::Write;
            let _ = writeln!(std::io::stderr().lock(),"PROCWAIT_WAIT_STATS scans={} scanUs={} waitUs={} pidfdOpens={} eventWakes={} timerWaits={}",
            self.scans,self.scan_us,self.wait_us,self.pidfds,self.wakes,self.fallback); }
    }
}
struct ScanPidFd(i32);
impl Drop for ScanPidFd { fn drop(&mut self) { unsafe { close(self.0); } } }
fn scan_wait_until(pids: &str, deadline: Instant, stats: &mut ScanWaitStats) {
    let mut owned = Vec::new();
    for pid in pids.split(',').filter_map(|s|s.parse::<i32>().ok()).filter(|p|*p>0) {
        let fd=unsafe { syscall(SYS_PIDFD_OPEN,pid,0) } as i32;
        if fd>=0 { owned.push(ScanPidFd(fd)); stats.pidfds+=1; }
        else if errno_now()==ESRCH { return; } // Re-scan now, never infer empty.
    }
    let mut fds:Vec<PollFd>=owned.iter().map(|f|PollFd{fd:f.0,events:POLLIN,revents:0}).collect();
    if fds.is_empty() { stats.fallback+=1; }
    loop {
        let remaining=deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() { return; }
        let ms=((remaining.as_micros()+999)/1000).min(i32::MAX as u128) as i32;
        let rc=unsafe { poll(fds.as_mut_ptr(),fds.len() as _,ms) };
        if rc>0 { stats.wakes+=1; return; } // Exit/error/hangup all require re-scan.
        if rc==0 { return; }
        if errno_now()!=EINTR {
            // Kernel restrictions must never turn an observer failure into GONE.
            // Bounded timer fallback retains the same mandatory /proc re-scan.
            std::thread::sleep(deadline.saturating_duration_since(Instant::now()));
            stats.fallback+=1; return;
        }
    }
}

pub(crate) fn wait_scan_gone(kind: &str, target: &str, timeout_ms: i64, stable_ms: i64, user: u32) -> i32 {
    let timeout_ms = timeout_ms.max(0);
    let stable_ms = stable_ms.max(0);
    let start = Instant::now();
    let uid: u32 = if kind == "uid" {
        match parse_uid_strtoul_like(target) {
            Some(v) => v,
            None => return 2,
        }
    } else {
        0
    };
    let mut first_empty: Option<Instant> = None;
    let mut stats=ScanWaitStats{enabled:stable_ms>0 && std::env::var("SPEEDBACKUP_PROCWAIT_STATS").as_deref()==Ok("1"),..Default::default()};
    loop {
        let scan_start=Instant::now();
        let (pids, count) = if kind == "uid" {
            match scan_uid_pids(uid) {
                Ok(v) => v,
                Err(e) => {
                    println!(
                        "PROCWAIT_SCAN_FAIL kind={} target={} errno={}",
                        kind, target, e
                    );
                    return 1;
                }
            }
        } else {
            match scan_package_pids(target, user) {
                Ok(v) => v,
                Err(e) => {
                    println!(
                        "PROCWAIT_SCAN_FAIL kind={} target={} errno={}",
                        kind, target, e
                    );
                    return 1;
                }
            }
        };
        stats.scans+=1; stats.scan_us+=scan_start.elapsed().as_micros();
        if count == 0 {
            let fe = *first_empty.get_or_insert_with(Instant::now);
            if fe.elapsed().as_millis() as i64 >= stable_ms {
                println!(
                    "GONE kind={} target={} stableMs={} elapsedMs={}",
                    kind,
                    target,
                    stable_ms,
                    start.elapsed().as_millis()
                );
                return 0;
            }
        } else {
            first_empty = None;
        }
        if start.elapsed().as_millis() as i64 >= timeout_ms {
            println!(
                "TIMEOUT kind={} target={} count={} pids={} timeoutMs={} stableMs={} elapsedMs={}",
                kind,
                target,
                count,
                pids,
                timeout_ms,
                stable_ms,
                start.elapsed().as_millis()
            );
            return 124;
        }
        let mut deadline=(scan_start+std::time::Duration::from_millis(20))
            .min(start+std::time::Duration::from_millis(timeout_ms as u64));
        if let Some(fe)=first_empty {
            deadline=deadline.min(fe+std::time::Duration::from_millis(stable_ms as u64));
        }
        let waiting=Instant::now();
        // Even exit/error events or scans slower than 20ms must yield. Never
        // extend this floor beyond the operation timeout. Slow scans regain the
        // old 20ms rest instead of consuming almost the entire CPU slice. This changes only
        // re-scan scheduling, never the empty-process or stable-window test.
        let backoff_ms=if scan_start.elapsed()>=std::time::Duration::from_millis(20) {20} else {2};
        let floor=(waiting+std::time::Duration::from_millis(backoff_ms))
            .min(start+std::time::Duration::from_millis(timeout_ms as u64));
        deadline=deadline.max(floor);
        scan_wait_until(&pids,deadline,&mut stats);
        std::thread::sleep(floor.saturating_duration_since(Instant::now()));
        stats.wait_us+=waiting.elapsed().as_micros();
    }
}

fn trim_c_strtol_prefix(s: &str) -> &str {
    s.trim_start_matches([' ', '\t', '\r', '\n', '\u{000b}', '\u{000c}'])
}

fn parse_long_arg(text: Option<&String>, min_v: i64, max_v: i64, fallback: i64) -> i64 {
    let raw = match text {
        Some(v) if !v.is_empty() => v.as_str(),
        _ => return fallback,
    };
    let left = trim_c_strtol_prefix(raw);
    if left.is_empty() {
        return fallback;
    }
    match left.parse::<i64>() {
        Ok(v) if v >= min_v && v <= max_v => v,
        _ => fallback,
    }
}

fn parse_pid_main_arg(s: &str) -> Option<i32> {
    let left = trim_c_strtol_prefix(s);
    if left.is_empty() {
        return None;
    }
    match left.parse::<i64>() {
        Ok(v) if v > 0 && v <= i32::MAX as i64 => Some(v as i32),
        _ => None,
    }
}

fn parse_uid_strtoul_like(s: &str) -> Option<u32> {
    let b = s.as_bytes();
    let mut i = 0usize;
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) {
        i += 1;
    }
    if i >= b.len() {
        return None;
    }
    let neg = if b[i] == b'+' {
        i += 1;
        false
    } else if b[i] == b'-' {
        i += 1;
        true
    } else {
        false
    };
    let start = i;
    let mut v: u128 = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add((b[i] - b'0') as u128);
        if v > u64::MAX as u128 {
            return None;
        }
        i += 1;
    }
    if i == start || i != b.len() {
        return None;
    }
    let u = v as u64;
    let final_u = if neg { 0u64.wrapping_sub(u) } else { u };
    u32::try_from(final_u).ok()
}

fn print_help(program: &str) {
    println!(
        "用法:\n  {} run COMMAND [ARG...]\n  {} pid PID\n  {} pkg-gone USER_ID PACKAGE [TIMEOUT_MS] [STABLE_MS]\n  {} pkg-stable USER_ID PACKAGE [TIMEOUT_MS] [STABLE_MS]\n  {} uid-gone UID [TIMEOUT_MS] [STABLE_MS]\n",
        program, program, program, program, program
    );
    println!("run：啟動自己的子程序並以 waitpid() 阻塞等待。");
    println!("pid：以 pidfd_open()+poll() 等待任意 PID；核心不支援就報錯，");
    println!("     不回退成 sleep/pidof 輪詢。");
    println!("pkg-gone/pkg-stable：掃 /proc/cmdline 等 package 或 package:process 消失並穩定。");
    println!("uid-gone：掃 /proc/<pid> owner uid 消失並穩定。");
}

pub(crate) fn run() {
    let args: Vec<String> = crate::multicall::args().collect();
    let argv0 = args.first().map(|s| s.as_str()).unwrap_or("procwait");

    let rc = if args.len() == 2 && args[1] == "--version" {
        println!("procwait {VERSION} build={BUILD_VERSION}");
        0
    } else if args.len() == 2 && (args[1] == "--help" || args[1] == "-h") {
        print_help(argv0);
        0
    } else if args.len() >= 3 && args[1] == "run" {
        wait_child(&args[2..])
    } else if args.len() == 3 && args[1] == "pid" {
        match parse_pid_main_arg(&args[2]) {
            Some(v) => wait_pidfd(v),
            None => {
                eprintln!("procwait: 無效 PID");
                2
            }
        }
    } else if args.len() >= 4 && (args[1] == "pkg-gone" || args[1] == "pkg-stable") {
        let user = match args[2].parse::<u32>() {
            Ok(n) => n,
            Err(_) => std::process::exit(2),
        };
        let timeout_ms = parse_long_arg(args.get(4), 0, 600000, 700);
        let stable_ms = parse_long_arg(args.get(5), 0, 600000, 120);
        wait_scan_gone("pkg", &args[3], timeout_ms, stable_ms, user)
    } else if args.len() >= 3 && args[1] == "uid-gone" {
        let timeout_ms = parse_long_arg(args.get(3), 0, 600000, 700);
        let stable_ms = parse_long_arg(args.get(4), 0, 600000, 120);
        wait_scan_gone("uid", &args[2], timeout_ms, stable_ms, 0)
    } else {
        print_help(argv0);
        2
    };
    std::process::exit(rc);
}
