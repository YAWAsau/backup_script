// procwait.rs - faithful Rust port of c/procwait.c
// waitpid/pidfd based process waiter. Output markers, exit codes, and the
// "pidfd only, never fall back to polling for the `pid` subcommand" design
// are reproduced exactly against c/procwait.c.

use speedbackup_native_rs::{syscall, poll, c_strerror, PollFd, POLLIN, SYS_PIDFD_OPEN};
use std::ffi::CString;
use std::os::raw::{c_char, c_int};
use std::time::Instant;

const VERSION: &str = "1.1.1-r572-package-stable-wait-api28-r30-rust-r572";
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
        eprintln!("procwait: fork: {}", c_strerror(&std::io::Error::last_os_error()));
        return 1;
    }
    if child == 0 {
        unsafe {
            execvp(cstrings[0].as_ptr(), argv.as_ptr());
        }
        eprintln!("procwait: execvp: {}", c_strerror(&std::io::Error::last_os_error()));
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
        eprintln!("procwait: waitpid: {}", c_strerror(&std::io::Error::last_os_error()));
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
        eprintln!("procwait: pidfd_open: {}", c_strerror(&std::io::Error::last_os_error()));
        return 1;
    }

    let mut pfd = PollFd { fd, events: POLLIN, revents: 0 };
    loop {
        let result = unsafe { poll(&mut pfd as *mut PollFd, 1, -1) };
        if result > 0 {
            break;
        }
        if result < 0 && errno_now() == EINTR {
            continue;
        }
        eprintln!("procwait: poll: {}", c_strerror(&std::io::Error::last_os_error()));
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
fn read_cmdline_first(pid: i32) -> Option<String> {
    use std::io::Read as _;
    let mut f = std::fs::File::open(format!("/proc/{}/cmdline", pid)).ok()?;
    let mut raw = [0u8; 511]; // C cmd[512] reads cap-1 bytes once.
    let n = f.read(&mut raw).ok()?;
    if n == 0 { return None; }
    let end = raw[..n].iter().position(|&b| b == 0).unwrap_or(n);
    Some(String::from_utf8_lossy(&raw[..end]).into_owned())
}

fn append_pid_capped(out: &mut String, token: &str) {
    const CAP: usize = 2048;
    let used = out.as_bytes().len();
    if CAP <= used + 2 { return; }
    let frag = if used == 0 { token.to_string() } else { format!(",{}", token) };
    let room = CAP - used;
    if frag.as_bytes().len() >= room {
        let take = room - 1;
        out.push_str(&String::from_utf8_lossy(&frag.as_bytes()[..take]));
    } else { out.push_str(&frag); }
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
fn scan_package_pids(pkg: &str) -> Result<(String, usize), i32> {
    let mut out = String::new();
    let mut count = 0usize;
    let entries = match std::fs::read_dir("/proc") {
        Ok(v) => v,
        Err(e) => return Err(e.raw_os_error().unwrap_or(-1)),
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !numeric_name(&name) {
            continue;
        }
        let pid: i64 = match name.parse() {
            Ok(v) if v > 0 && v <= i32::MAX as i64 => v,
            _ => continue,
        };
        let cmd = match read_cmdline_first(pid as i32) {
            Some(v) => v,
            None => continue,
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
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !numeric_name(&name) {
            continue;
        }
        let meta = match std::fs::symlink_metadata(format!("/proc/{}", name)) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if meta.uid() != uid {
            continue;
        }
        count += 1;
        append_pid_capped(&mut out, &name);
    }
    Ok((out, count))
}

/// Faithful port of wait_scan_gone(): poll /proc every 20ms until the target
/// (package or uid) has had zero matching PIDs for `stable_ms` continuously,
/// or `timeout_ms` elapses first. Output markers match C exactly:
///   GONE kind=... target=... stableMs=... elapsedMs=...
///   TIMEOUT kind=... target=... count=... pids=... timeoutMs=... stableMs=... elapsedMs=...
///   PROCWAIT_SCAN_FAIL kind=... target=... errno=...
fn wait_scan_gone(kind: &str, target: &str, timeout_ms: i64, stable_ms: i64) -> i32 {
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
    loop {
        let (pids, count) = if kind == "uid" {
            match scan_uid_pids(uid) {
                Ok(v) => v,
                Err(e) => {
                    println!("PROCWAIT_SCAN_FAIL kind={} target={} errno={}", kind, target, e);
                    return 1;
                }
            }
        } else {
            match scan_package_pids(target) {
                Ok(v) => v,
                Err(e) => {
                    println!("PROCWAIT_SCAN_FAIL kind={} target={} errno={}", kind, target, e);
                    return 1;
                }
            }
        };
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
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
}

fn trim_c_strtol_prefix(s: &str) -> &str {
    s.trim_start_matches(|c: char| c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\u{000b}' || c == '\u{000c}')
}

fn parse_long_arg(text: Option<&String>, min_v: i64, max_v: i64, fallback: i64) -> i64 {
    let raw = match text { Some(v) if !v.is_empty() => v.as_str(), _ => return fallback };
    let left = trim_c_strtol_prefix(raw);
    if left.is_empty() { return fallback; }
    match left.parse::<i64>() {
        Ok(v) if v >= min_v && v <= max_v => v,
        _ => fallback,
    }
}

fn parse_pid_main_arg(s: &str) -> Option<i32> {
    let left = trim_c_strtol_prefix(s);
    if left.is_empty() { return None; }
    match left.parse::<i64>() {
        Ok(v) if v > 0 && v <= i32::MAX as i64 => Some(v as i32),
        _ => None,
    }
}

fn parse_uid_strtoul_like(s: &str) -> Option<u32> {
    let b = s.as_bytes();
    let mut i = 0usize;
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    if i >= b.len() { return None; }
    let neg = if b[i] == b'+' { i += 1; false } else if b[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut v: u128 = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add((b[i] - b'0') as u128);
        if v > u64::MAX as u128 { return None; }
        i += 1;
    }
    if i == start || i != b.len() { return None; }
    let u = v as u64;
    let final_u = if neg { 0u64.wrapping_sub(u) } else { u };
    Some(final_u as u32)
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
    let argv0 = args.get(0).map(|s| s.as_str()).unwrap_or("procwait");

    let rc = if args.len() == 2 && args[1] == "--version" {
        println!("procwait {}", VERSION);
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
        // args[2] (user id) is accepted for CLI compatibility but, like the C
        // reference, is not actually used to filter the /proc scan.
        let timeout_ms = parse_long_arg(args.get(4), 0, 600000, 700);
        let stable_ms = parse_long_arg(args.get(5), 0, 600000, 120);
        wait_scan_gone("pkg", &args[3], timeout_ms, stable_ms)
    } else if args.len() >= 3 && args[1] == "uid-gone" {
        let timeout_ms = parse_long_arg(args.get(3), 0, 600000, 700);
        let stable_ms = parse_long_arg(args.get(4), 0, 600000, 120);
        wait_scan_gone("uid", &args[2], timeout_ms, stable_ms)
    } else {
        print_help(argv0);
        2
    };
    std::process::exit(rc);
}
