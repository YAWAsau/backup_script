// filewatch.rs - faithful Rust port of c/filewatch.c
// Minimal inotify event waiter for Android/Linux.
// Ported 1:1 against c/filewatch.c behavior: same exit codes, same stdout/stderr
// formats, same event mask sets, same parent-disappeared detection.

use speedbackup_native_rs::{access, close, c_strerror, F_OK};
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::OsStrExt;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

const VERSION: &str = "1.0.1-android28-r30-native-convergence-r572-rust-r572";
const EVENT_BUFFER_SIZE: usize = 64 * 1024;

// inotify mask bits (Linux uapi/linux/inotify.h) - stable ABI, safe to hardcode.
const IN_MODIFY: u32 = 0x0000_0002;
const IN_ATTRIB: u32 = 0x0000_0004;
const IN_CLOSE_WRITE: u32 = 0x0000_0008;
const IN_MOVED_FROM: u32 = 0x0000_0040;
const IN_MOVED_TO: u32 = 0x0000_0080;
const IN_CREATE: u32 = 0x0000_0100;
const IN_DELETE: u32 = 0x0000_0200;
const IN_DELETE_SELF: u32 = 0x0000_0400;
const IN_MOVE_SELF: u32 = 0x0000_0800;
const IN_Q_OVERFLOW: u32 = 0x0000_4000;
const IN_IGNORED: u32 = 0x0000_8000;
const O_CLOEXEC: c_int = 0o2000000; // matches IN_CLOEXEC flag value for inotify_init1()
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;

static G_STOP: AtomicBool = AtomicBool::new(false);

#[repr(C)]
struct Sigaction {
    sa_handler: extern "C" fn(c_int),
    sa_mask: [u64; 16], // sigset_t oversized on purpose; kernel only reads sizeof(sigset_t) bytes.
    sa_flags: c_int,
    sa_restorer: usize,
}

extern "C" fn on_signal(_signo: c_int) {
    G_STOP.store(true, Ordering::SeqCst);
}

extern "C" {
    fn inotify_init1(flags: c_int) -> c_int;
    fn inotify_init() -> c_int;
    fn inotify_add_watch(fd: c_int, path: *const c_char, mask: u32) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, arg: c_int) -> c_int;
    fn read(fd: c_int, buf: *mut c_void, count: usize) -> isize;
    fn sigaction(signum: c_int, act: *const Sigaction, oldact: *mut Sigaction) -> c_int;
    fn __errno() -> *mut c_int;
}

#[cfg(target_os = "android")]
fn errno_now() -> c_int {
    unsafe { *__errno() }
}
#[cfg(not(target_os = "android"))]
fn errno_now() -> c_int {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

const EINTR: c_int = 4;
const ENOSYS: c_int = 38;
const EINVAL: c_int = 22;
const ENAMETOOLONG: c_int = 36;
const PATH_MAX: usize = 4096;
const NAME_MAX: usize = 255;
const SIGINT: c_int = 2;
const SIGTERM: c_int = 15;
const SIGHUP: c_int = 1;

fn install_signals() -> bool {
    let act = Sigaction {
        sa_handler: on_signal,
        sa_mask: [0u64; 16],
        sa_flags: 0,
        sa_restorer: 0,
    };
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        let rc = unsafe { sigaction(sig, &act as *const Sigaction, std::ptr::null_mut()) };
        if rc != 0 {
            return false;
        }
    }
    true
}

fn open_inotify() -> c_int {
    let fd = unsafe { inotify_init1(O_CLOEXEC) };
    if fd >= 0 {
        return fd;
    }
    let e = errno_now();
    if e != ENOSYS && e != EINVAL {
        return -1;
    }
    let fd2 = unsafe { inotify_init() };
    if fd2 >= 0 {
        unsafe {
            fcntl(fd2, F_SETFD, FD_CLOEXEC);
        }
    }
    fd2
}

fn event_name(mask: u32) -> &'static str {
    if mask & IN_CREATE != 0 { return "CREATE"; }
    if mask & IN_CLOSE_WRITE != 0 { return "CLOSE_WRITE"; }
    if mask & IN_MOVED_TO != 0 { return "MOVED_TO"; }
    if mask & IN_MOVED_FROM != 0 { return "MOVED_FROM"; }
    if mask & IN_DELETE != 0 { return "DELETE"; }
    if mask & IN_MODIFY != 0 { return "MODIFY"; }
    if mask & IN_ATTRIB != 0 { return "ATTRIB"; }
    if mask & IN_DELETE_SELF != 0 { return "DELETE_SELF"; }
    if mask & IN_MOVE_SELF != 0 { return "MOVE_SELF"; }
    if mask & IN_IGNORED != 0 { return "IGNORED"; }
    if mask & IN_Q_OVERFLOW != 0 { return "OVERFLOW"; }
    "OTHER"
}

/// Faithful port of split_parent_base(): splits `path` into (parent, base),
/// stripping trailing slashes first (keeping at least one char), matching
/// c/filewatch.c exactly including the "no slash -> parent=." and
/// "leading slash only -> parent=/" special cases.
fn split_parent_base(path: &str) -> Result<(String, String), c_int> {
    if path.is_empty() { return Err(EINVAL); }
    if path.as_bytes().len() >= PATH_MAX { return Err(ENAMETOOLONG); }
    let mut copy: Vec<u8> = path.as_bytes().to_vec();
    let mut length = copy.len();
    while length > 1 && copy[length - 1] == b'/' {
        length -= 1;
    }
    copy.truncate(length);
    let slash_pos = copy.iter().rposition(|&b| b == b'/');
    match slash_pos {
        None => {
            let base = String::from_utf8_lossy(&copy).into_owned();
            if base.as_bytes().len() > NAME_MAX { return Err(ENAMETOOLONG); }
            if base.is_empty() { return Err(EINVAL); }
            Ok((".".to_string(), base))
        }
        Some(0) => {
            let base = String::from_utf8_lossy(&copy[1..]).into_owned();
            if base.as_bytes().len() > NAME_MAX { return Err(ENAMETOOLONG); }
            if base.is_empty() { return Err(EINVAL); }
            Ok(("/".to_string(), base))
        }
        Some(pos) => {
            let parent = String::from_utf8_lossy(&copy[..pos]).into_owned();
            let base = String::from_utf8_lossy(&copy[pos + 1..]).into_owned();
            if parent.as_bytes().len() >= PATH_MAX || base.as_bytes().len() > NAME_MAX { return Err(ENAMETOOLONG); }
            if base.is_empty() { return Err(EINVAL); }
            Ok((parent, base))
        }
    }
}

fn path_exists(path: &str) -> bool {
    let c = match std::ffi::CString::new(path) {
        Ok(v) => v,
        Err(_) => return false,
    };
    unsafe { access(c.as_ptr(), F_OK) == 0 }
}

fn cstring_or_bail(path: &str) -> Option<std::ffi::CString> {
    std::ffi::CString::new(Path::new(path).as_os_str().as_bytes()).ok()
}

/// Faithful port of wait_exists(): 0 = target now exists, 1 = usage/IO error,
/// 2 = watched parent disappeared, 130 = stopped by signal.
fn wait_exists(path: &str) -> i32 {
    if path_exists(path) {
        println!("EXISTS path={}", path);
        return 0;
    }
    let (parent, base) = match split_parent_base(path) {
        Ok(v) => v,
        Err(errno) => {
            eprintln!("filewatch: split path: {}", c_strerror(&std::io::Error::from_raw_os_error(errno)));
            return 1;
        }
    };
    let fd = open_inotify();
    if fd < 0 {
        eprintln!("filewatch: inotify_init: {}", c_strerror(&std::io::Error::last_os_error()));
        return 1;
    }
    let parent_c = match cstring_or_bail(&parent) {
        Some(v) => v,
        None => { unsafe { close(fd) }; return 1; }
    };
    let mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_TO | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF;
    let wd = unsafe { inotify_add_watch(fd, parent_c.as_ptr(), mask) };
    if wd < 0 {
        eprintln!("filewatch: inotify_add_watch: {}", c_strerror(&std::io::Error::last_os_error()));
        unsafe { close(fd) };
        return 1;
    }
    // Re-check after the watch is armed to close the create-before-watch race,
    // exactly like the C version does.
    if path_exists(path) {
        println!("EXISTS path={}", path);
        unsafe { close(fd) };
        return 0;
    }

    let mut buffer = vec![0u8; EVENT_BUFFER_SIZE];
    loop {
        if G_STOP.load(Ordering::SeqCst) {
            unsafe { close(fd) };
            return 130;
        }
        let received = unsafe { read(fd, buffer.as_mut_ptr() as *mut c_void, buffer.len()) };
        if received < 0 {
            if errno_now() == EINTR { continue; }
            eprintln!("filewatch: read: {}", c_strerror(&std::io::Error::last_os_error()));
            unsafe { close(fd) };
            return 1;
        }
        let received = received as usize;
        let mut offset = 0usize;
        const HDR: usize = 16; // struct inotify_event header: wd,mask,cookie,len (4 x u32/i32)
        while offset + HDR <= received {
            let mask_val = u32::from_ne_bytes(buffer[offset + 4..offset + 8].try_into().unwrap());
            let len_val = u32::from_ne_bytes(buffer[offset + 12..offset + 16].try_into().unwrap()) as usize;
            let record_size = HDR + len_val;
            if record_size == 0 || offset + record_size > received {
                eprintln!("filewatch: malformed inotify event");
                unsafe { close(fd) };
                return 1;
            }
            if mask_val & (IN_DELETE_SELF | IN_MOVE_SELF | IN_IGNORED) != 0 {
                eprintln!("filewatch: watched parent disappeared");
                unsafe { close(fd) };
                return 2;
            }
            if len_val > 0 {
                let name_bytes = &buffer[offset + HDR..offset + HDR + len_val];
                let name_end = name_bytes.iter().position(|&b| b == 0).unwrap_or(len_val);
                let name = String::from_utf8_lossy(&name_bytes[..name_end]);
                if name == base && path_exists(path) {
                    println!("{} path={}", event_name(mask_val), path);
                    unsafe { close(fd) };
                    return 0;
                }
            }
            offset += record_size;
        }
    }
}

/// Faithful port of watch_path(): continuous or single-shot inotify watch on
/// `path` itself. 0 = event observed (once) / manual stop path unreachable in
/// once-mode, 1 = IO error, 2 = watch invalidated (IN_IGNORED), 130 = signal stop.
fn watch_path(path: &str, once: bool) -> i32 {
    let fd = open_inotify();
    if fd < 0 {
        eprintln!("filewatch: inotify_init: {}", c_strerror(&std::io::Error::last_os_error()));
        return 1;
    }
    let path_c = match cstring_or_bail(path) {
        Some(v) => v,
        None => { unsafe { close(fd) }; return 1; }
    };
    let mask = IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_DELETE
        | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF;
    let wd = unsafe { inotify_add_watch(fd, path_c.as_ptr(), mask) };
    if wd < 0 {
        eprintln!("filewatch: inotify_add_watch: {}", c_strerror(&std::io::Error::last_os_error()));
        unsafe { close(fd) };
        return 1;
    }

    let mut buffer = vec![0u8; EVENT_BUFFER_SIZE];
    loop {
        if G_STOP.load(Ordering::SeqCst) {
            unsafe { close(fd) };
            return 130;
        }
        let received = unsafe { read(fd, buffer.as_mut_ptr() as *mut c_void, buffer.len()) };
        if received < 0 {
            if errno_now() == EINTR { continue; }
            eprintln!("filewatch: read: {}", c_strerror(&std::io::Error::last_os_error()));
            unsafe { close(fd) };
            return 1;
        }
        let received = received as usize;
        let mut offset = 0usize;
        const HDR: usize = 16;
        while offset + HDR <= received {
            let mask_val = u32::from_ne_bytes(buffer[offset + 4..offset + 8].try_into().unwrap());
            let cookie_val = u32::from_ne_bytes(buffer[offset + 8..offset + 12].try_into().unwrap());
            let len_val = u32::from_ne_bytes(buffer[offset + 12..offset + 16].try_into().unwrap()) as usize;
            let record_size = HDR + len_val;
            if record_size == 0 || offset + record_size > received {
                eprintln!("filewatch: malformed inotify event");
                unsafe { close(fd) };
                return 1;
            }
            let name = if len_val > 0 {
                let name_bytes = &buffer[offset + HDR..offset + HDR + len_val];
                let name_end = name_bytes.iter().position(|&b| b == 0).unwrap_or(len_val);
                String::from_utf8_lossy(&name_bytes[..name_end]).into_owned()
            } else {
                "-".to_string()
            };
            println!("{} mask=0x{:x} cookie={} name={}", event_name(mask_val), mask_val, cookie_val, name);
            if once {
                unsafe { close(fd) };
                return 0;
            }
            if mask_val & IN_IGNORED != 0 {
                unsafe { close(fd) };
                return 2;
            }
            offset += record_size;
        }
    }
}

fn print_help(program: &str) {
    println!("用法:");
    println!("  {} --wait-exists PATH", program);
    println!("  {} --once PATH", program);
    println!("  {} PATH", program);
    println!();
    println!("--wait-exists：檔案已存在就立即成功，否則阻塞等待建立/移入。");
    println!("--once：等待指定檔案或目錄的第一個 inotify 事件後退出。");
    println!("無選項：持續輸出指定檔案或目錄的事件。");
}

pub(crate) fn run() {
    if !install_signals() {
        eprintln!("filewatch: sigaction: {}", c_strerror(&std::io::Error::last_os_error()));
        std::process::exit(1);
    }
    let args: Vec<String> = crate::multicall::args().collect();
    let argv0 = args.get(0).map(|s| s.as_str()).unwrap_or("filewatch");

    let rc = if args.len() == 2 && args[1] == "--version" {
        println!("filewatch {}", VERSION);
        0
    } else if args.len() == 2 && (args[1] == "--help" || args[1] == "-h") {
        print_help(argv0);
        0
    } else if args.len() == 3 && args[1] == "--wait-exists" {
        wait_exists(&args[2])
    } else if args.len() == 3 && args[1] == "--once" {
        watch_path(&args[2], true)
    } else if args.len() == 2 {
        watch_path(&args[1], false)
    } else {
        print_help(argv0);
        2
    };
    std::process::exit(rc);
}
