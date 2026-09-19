// uidexec.rs - faithful Rust port of c/uidexec.c
// Drops root privileges to a target uid/gid and execvp()s the requested
// command. Security-critical: every privilege-drop step in the C reference
// (setgroups restriction, setresgid/setresuid + post-verification, hardening,
// tmpdir setup, PATH fallback) is reproduced exactly, not simplified.

use speedbackup_native_rs::{c_strerror, execvp};
use std::env;
use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_ulong};
use std::os::unix::ffi::OsStrExt;

const VERSION: &str = "1.0.1-android28-r29-native-convergence-r572-rust-r572";

extern "C" {
    fn setgroups(size: usize, list: *const u32) -> c_int;
    fn setresgid(rgid: u32, egid: u32, sgid: u32) -> c_int;
    fn setresuid(ruid: u32, euid: u32, suid: u32) -> c_int;
    fn getresgid(rgid: *mut u32, egid: *mut u32, sgid: *mut u32) -> c_int;
    fn getresuid(ruid: *mut u32, euid: *mut u32, suid: *mut u32) -> c_int;
    fn umask(mask: u32) -> u32;
    fn prctl(option: c_int, arg2: c_ulong, arg3: c_ulong, arg4: c_ulong, arg5: c_ulong) -> c_int;
    fn mkdir(path: *const c_char, mode: u32) -> c_int;
    fn chown(path: *const c_char, owner: u32, group: u32) -> c_int;
    fn chmod(path: *const c_char, mode: u32) -> c_int;
    fn getuid() -> u32;
    fn getgid() -> u32;
    fn setenv(name: *const c_char, value: *const c_char, overwrite: c_int) -> c_int;
    fn unsetenv(name: *const c_char) -> c_int;
}

const PR_SET_DUMPABLE: c_int = 4;
const EEXIST: i32 = 17;

/// Matches C's debug_enabled(): any value that is non-null, non-empty, and
/// not literally "0" enables debug output. Deliberately NOT a whitelist.
fn debug_enabled() -> bool {
    match env::var_os("UIDEXEC_DEBUG") {
        Some(v) => { let b = v.as_os_str().as_bytes(); !b.is_empty() && b != b"0" },
        None => false,
    }
}

fn debug_log(msg: &str) {
    if debug_enabled() {
        eprintln!("{}", msg);
    }
}

fn die(msg: &str) -> ! {
    eprintln!("{}: {}", msg, c_strerror(&std::io::Error::last_os_error()));
    std::process::exit(1);
}

fn die_msg(msg: &str) -> ! {
    eprintln!("{}", msg);
    std::process::exit(1);
}

fn usage(prog: &str) {
    eprintln!(
        "usage:\n  {} <uid> <gid> <android_data_dir> -- <cmd> [args...]\n  {} <uid> <gid> <android_data_dir> <classpath> <cmd> [args...]  # legacy\n  {} <uid> <gid> <android_data_dir> --classpath <classpath> -- <cmd> [args...]",
        prog, prog, prog
    );
}

/// Faithful port of parse_long(): rejects negatives, requires the whole
/// string consumed, exits(2) on any parse failure exactly like the C version.
fn parse_long(s: Option<&String>, name: &str) -> u32 {
    let s = match s { Some(v) => v, None => { eprintln!("bad {}: (null)", name); std::process::exit(2); } };
    let b = s.as_bytes();
    let mut i = 0usize;
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    let neg = if i < b.len() && b[i] == b'+' { i += 1; false } else if i < b.len() && b[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut value: u128 = 0;
    let limit = if neg { (i64::MAX as u128) + 1 } else { i64::MAX as u128 };
    while i < b.len() && b[i].is_ascii_digit() {
        value = value.saturating_mul(10).saturating_add((b[i] - b'0') as u128);
        if value > limit { break; }
        i += 1;
    }
    let valid = i > start && i == b.len() && value <= limit;
    let signed = if valid && neg {
        if value == (i64::MAX as u128) + 1 { i64::MIN } else { -(value as i64) }
    } else if valid { value as i64 } else { -1 };
    if !valid || signed < 0 { eprintln!("bad {}: {}", name, s); std::process::exit(2); }
    signed as u32
}

fn cstr(s: &str) -> CString {
    // uidexec's inputs are always trusted local paths/ids; a NUL byte here
    // can only mean a malformed caller, matching C's implicit assumption
    // that argv strings have no embedded NUL (argv strings never do in C).
    CString::new(s).unwrap_or_else(|_| CString::new("").unwrap())
}

fn setenv_checked(name: &str, value: &str, overwrite: i32, die_name: Option<&str>) {
    let n = cstr(name); let v = cstr(value);
    if unsafe { setenv(n.as_ptr(), v.as_ptr(), overwrite) } != 0 {
        if let Some(msg) = die_name { die(msg); }
    }
}

fn unsetenv_ignored(name: &str) { let n = cstr(name); unsafe { unsetenv(n.as_ptr()); } }

fn make_tmpdir(android_data: &str, uid: u32, gid: u32) {
    let tmpdir = format!("{}/tmp", android_data);
    if tmpdir.len() >= 4096 {
        die_msg("TMPDIR path too long");
    }
    let c_tmpdir = cstr(&tmpdir);
    let rc = unsafe { mkdir(c_tmpdir.as_ptr(), 0o700) };
    if rc != 0 {
        let errno = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
        if errno != EEXIST {
            die("mkdir TMPDIR");
        }
    }
    // Best effort: uidexec normally starts as root, but do not make old
    // caller environments fail merely because ownership/mode cannot be
    // adjusted on a special directory.
    if unsafe { chown(c_tmpdir.as_ptr(), uid, gid) } != 0 && debug_enabled() {
        eprintln!("warn: chown TMPDIR failed: {}", c_strerror(&std::io::Error::last_os_error()));
    }
    if unsafe { chmod(c_tmpdir.as_ptr(), 0o700) } != 0 && debug_enabled() {
        eprintln!("warn: chmod TMPDIR failed: {}", c_strerror(&std::io::Error::last_os_error()));
    }
    setenv_checked("TMPDIR", &tmpdir, 1, Some("setenv TMPDIR"));
}

fn harden_process() {
    unsafe {
        umask(0o077);
        if prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0 {
            debug_log("warn: PR_SET_DUMPABLE failed");
        }
    }
}

/// Faithful port of drop_identity(): restrict supplementary groups to
/// exactly [gid], setresgid/setresuid to the target id on all three slots,
/// then read the IDs back and hard-fail on any mismatch. This is the core
/// safety net the C version relies on and the earlier Rust stub lacked.
fn drop_identity(uid: u32, gid: u32) {
    let groups = [gid];
    if unsafe { setgroups(1, groups.as_ptr()) } != 0 {
        die("setgroups");
    }
    if unsafe { setresgid(gid, gid, gid) } != 0 {
        die("setresgid");
    }
    if unsafe { setresuid(uid, uid, uid) } != 0 {
        die("setresuid");
    }

    let (mut ruid, mut euid, mut suid) = (u32::MAX, u32::MAX, u32::MAX);
    let (mut rgid, mut egid, mut sgid) = (u32::MAX, u32::MAX, u32::MAX);
    if unsafe { getresuid(&mut ruid, &mut euid, &mut suid) } != 0 {
        die("getresuid");
    }
    if unsafe { getresgid(&mut rgid, &mut egid, &mut sgid) } != 0 {
        die("getresgid");
    }
    if ruid != uid || euid != uid || suid != uid || rgid != gid || egid != gid || sgid != gid {
        eprintln!(
            "identity mismatch: uid={}/{}/{} expected={} gid={}/{}/{} expected={}",
            ruid, euid, suid, uid, rgid, egid, sgid, gid
        );
        std::process::exit(1);
    }
}

fn exec_command(cmd: &[String]) -> ! {
    let cstrings: Vec<CString> = cmd.iter().map(|a| cstr(a)).collect();
    let mut argv: Vec<*const c_char> = cstrings.iter().map(|c| c.as_ptr()).collect();
    argv.push(std::ptr::null());
    unsafe {
        execvp(cstrings[0].as_ptr(), argv.as_ptr());
    }
    die("execvp")
}

pub(crate) fn run() {
    let args: Vec<String> = crate::multicall::args().collect();
    let prog = args.get(0).map(|s| s.as_str()).unwrap_or("uidexec");

    if args.len() == 2 && (args[1] == "--version" || args[1] == "version") {
        println!("uidexec {}", VERSION);
        return;
    }
    if args.len() < 6 {
        usage(prog);
        std::process::exit(2);
    }

    let uid = parse_long(args.get(1), "uid");
    let gid = parse_long(args.get(2), "gid");
    let android_data = args[3].clone();
    if android_data.is_empty() {
        die_msg("bad android_data_dir");
    }

    let mut classpath: Option<String> = None;
    let cmd_index: usize;

    // Supported formats (matches C exactly):
    //   uidexec uid gid data -- cmd [args...]
    //   uidexec uid gid data --classpath cp -- cmd [args...]
    //   uidexec uid gid data --classpath cp cmd [args...]   (tolerated, no --)
    //   uidexec uid gid data classpath cmd [args...]        (legacy)
    if args[4] == "--" {
        cmd_index = 5;
    } else if args[4] == "--classpath" {
        if args.len() < 8 {
            usage(prog);
            std::process::exit(2);
        }
        classpath = Some(args[5].clone());
        cmd_index = if args[6] == "--" { 7 } else { 6 };
    } else {
        classpath = Some(args[4].clone());
        cmd_index = 5;
    }

    if cmd_index >= args.len() {
        usage(prog);
        std::process::exit(2);
    }

    harden_process();

    setenv_checked("ANDROID_DATA", &android_data, 1, Some("setenv ANDROID_DATA"));
    match &classpath {
        Some(cp) if !cp.is_empty() => setenv_checked("CLASSPATH", cp, 1, Some("setenv CLASSPATH")),
        _ => unsetenv_ignored("CLASSPATH"),
    }

    make_tmpdir(&android_data, uid, gid);

    // C calls setenv(..., overwrite=0) and intentionally ignores failure.
    setenv_checked(
        "PATH",
        "/system/bin:/system/xbin:/vendor/bin:/product/bin:/apex/com.android.runtime/bin",
        0,
        None,
    );

    drop_identity(uid, gid);

    if debug_enabled() {
        eprintln!("running as uid={} gid={}", unsafe { getuid() }, unsafe { getgid() });
    }

    exec_command(&args[cmd_index..]);
}
