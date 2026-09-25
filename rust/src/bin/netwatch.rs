// netwatch.rs - faithful Rust port of c/netwatch.c
// Real rtnetlink (AF_NETLINK/NETLINK_ROUTE) event watcher: blocks in recv(),
// no timers, no polling, no wake locks - matching the C reference's explicit
// design goal (the previous Rust stub polled /proc/net/route every 750ms,
// which is exactly what this file must NOT do).

use speedbackup_native_rs::c_strerror;
use std::ffi::CString;
use std::io::Write;
use std::os::raw::{c_char, c_int, c_void};
use std::sync::atomic::{AtomicBool, Ordering};

const VERSION: &str = "1.2.1-android28-r30-native-convergence-r572-rust-r572";
const RECEIVE_BUFFER_SIZE: usize = 64 * 1024;

const AF_NETLINK: i32 = 16;
const AF_INET: u8 = 2;
const NETLINK_ROUTE: i32 = 0;
const SOCK_RAW: i32 = 3;
const SOCK_CLOEXEC: i32 = 0o2000000;
const SOL_SOCKET: i32 = 1;
const SO_RCVBUF: i32 = 8;
const RTMGRP_LINK: u32 = 1;
const RTMGRP_IPV4_IFADDR: u32 = 0x10;

const NLMSG_NOOP: u16 = 1;
const NLMSG_ERROR: u16 = 2;
const NLMSG_DONE: u16 = 3;
const NLMSG_OVERRUN: u16 = 4;
const RTM_NEWLINK: u16 = 16;
const RTM_DELLINK: u16 = 17;
const RTM_NEWADDR: u16 = 20;
const RTM_DELADDR: u16 = 21;

const IFLA_IFNAME: u16 = 3;
const IFA_ADDRESS: u16 = 1;
const IFA_LOCAL: u16 = 2;

const NLMSGHDR_LEN: usize = 16; // len(4) type(2) flags(2) seq(4) pid(4)
const IFINFOMSG_LEN: usize = 16; // family(1) pad(1) type(2) index(4) flags(4) change(4)
const IFADDRMSG_LEN: usize = 8; // family(1) prefixlen(1) flags(1) scope(1) index(4)
const RTATTR_HDR_LEN: usize = 4; // len(2) type(2)
const EINTR: i32 = 4;

static G_STOP: AtomicBool = AtomicBool::new(false);

#[repr(C)]
struct Sigaction {
    sa_handler: extern "C" fn(c_int),
    sa_mask: [u64; 16],
    sa_flags: c_int,
    sa_restorer: usize,
}

extern "C" fn handle_signal(_signo: c_int) {
    G_STOP.store(true, Ordering::SeqCst);
}

#[repr(C)]
struct SockaddrNl {
    nl_family: u16,
    nl_pad: u16,
    nl_pid: u32,
    nl_groups: u32,
}

extern "C" {
    fn sigaction(signum: c_int, act: *const Sigaction, oldact: *mut Sigaction) -> c_int;
    fn socket(domain: c_int, ty: c_int, protocol: c_int) -> c_int;
    fn bind(fd: c_int, addr: *const c_void, addrlen: u32) -> c_int;
    fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: *const c_void, optlen: u32) -> c_int;
    fn recv(fd: c_int, buf: *mut c_void, len: usize, flags: c_int) -> isize;
    fn close(fd: c_int) -> c_int;
    fn getpid() -> i32;
    fn if_indextoname(ifindex: u32, ifname: *mut c_char) -> *mut c_char;
    fn inet_ntop(af: c_int, src: *const c_void, dst: *mut c_char, size: u32) -> *const c_char;
}

const SIGINT: c_int = 2;
const SIGTERM: c_int = 15;
const SIGHUP: c_int = 1;

fn errno_now() -> i32 {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

fn install_signal_handlers() -> bool {
    let act = Sigaction { sa_handler: handle_signal, sa_mask: [0u64; 16], sa_flags: 0, sa_restorer: 0 };
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        if unsafe { sigaction(sig, &act as *const Sigaction, std::ptr::null_mut()) } != 0 {
            return false;
        }
    }
    true
}

fn message_type_name(t: u16) -> &'static str {
    match t {
        RTM_NEWLINK => "LINK_NEW",
        RTM_DELLINK => "LINK_DEL",
        RTM_NEWADDR => "ADDR_NEW",
        RTM_DELADDR => "ADDR_DEL",
        _ => "UNKNOWN",
    }
}

fn resolve_interface_name(index: u32) -> String {
    let mut buf = [0 as c_char; 16]; // IF_NAMESIZE
    let ptr = unsafe { if_indextoname(index, buf.as_mut_ptr()) };
    if ptr.is_null() {
        return format!("if{}", index);
    }
    let cstr = unsafe { std::ffi::CStr::from_ptr(buf.as_ptr()) };
    cstr.to_string_lossy().into_owned()
}

fn u16_at(b: &[u8], off: usize) -> u16 { u16::from_ne_bytes(b[off..off + 2].try_into().unwrap()) }

fn flush_stdout_line() {
    let _ = std::io::stdout().flush();
}

fn u32_at(b: &[u8], off: usize) -> u32 { u32::from_ne_bytes(b[off..off + 4].try_into().unwrap()) }
fn i32_at(b: &[u8], off: usize) -> i32 { i32::from_ne_bytes(b[off..off + 4].try_into().unwrap()) }

/// Walk an rtattr chain starting at `msg[attr_off..]`, bounded by `payload_len`
/// bytes, matching RTA_OK/RTA_NEXT semantics (4-byte aligned records).
fn walk_rtattrs(msg: &[u8], attr_off: usize, payload_len: usize) -> Vec<(u16, std::ops::Range<usize>)> {
    let mut out = Vec::new();
    let mut off = attr_off;
    let mut remaining = payload_len as isize;
    while remaining as usize >= RTATTR_HDR_LEN && off + RTATTR_HDR_LEN <= msg.len() {
        let rta_len = u16_at(msg, off) as usize;
        let rta_type = u16_at(msg, off + 2);
        if rta_len < RTATTR_HDR_LEN || rta_len as isize > remaining {
            break;
        }
        let data_start = off + RTATTR_HDR_LEN;
        let data_end = (off + rta_len).min(msg.len());
        out.push((rta_type, data_start..data_end));
        let aligned = (rta_len + 3) & !3;
        remaining -= aligned as isize;
        off += aligned;
    }
    out
}

fn print_link_event(msg: &[u8]) {
    if msg.len() < NLMSGHDR_LEN + IFINFOMSG_LEN {
        return;
    }
    let nlmsg_len = u32_at(msg, 0) as usize;
    let nlmsg_type = u16_at(msg, 4);
    let ifi_index = i32_at(msg, NLMSGHDR_LEN + 4);
    let ifi_flags = u32_at(msg, NLMSGHDR_LEN + 8);
    let ifi_change = u32_at(msg, NLMSGHDR_LEN + 12);

    let mut ifname = resolve_interface_name(ifi_index as u32);
    // IFLA_PAYLOAD(header) = nlmsg_len - NLMSG_SPACE(sizeof(ifinfomsg)) = nlmsg_len - 32
    let payload_len = nlmsg_len.saturating_sub(NLMSGHDR_LEN + IFINFOMSG_LEN);
    let attr_off = NLMSGHDR_LEN + IFINFOMSG_LEN;
    for (rta_type, range) in walk_rtattrs(msg, attr_off, payload_len) {
        if rta_type == IFLA_IFNAME {
            let raw = &msg[range];
            if !raw.is_empty() {
                let copy_len = raw.len().min(15); // IF_NAMESIZE - 1
                let copied = &raw[..copy_len];
                let end = copied.iter().position(|&b| b == 0).unwrap_or(copy_len);
                ifname = String::from_utf8_lossy(&copied[..end]).into_owned();
            }
            break;
        }
    }
    println!(
        "{} ifindex={} ifname={} flags=0x{:x} change=0x{:x}",
        message_type_name(nlmsg_type), ifi_index, ifname, ifi_flags, ifi_change
    );
    flush_stdout_line();
}

fn print_address_event(msg: &[u8]) {
    if msg.len() < NLMSGHDR_LEN + IFADDRMSG_LEN {
        return;
    }
    let nlmsg_len = u32_at(msg, 0) as usize;
    let nlmsg_type = u16_at(msg, 4);
    let ifa_family = msg[NLMSGHDR_LEN];
    let ifa_prefixlen = msg[NLMSGHDR_LEN + 1];
    let ifa_flags = msg[NLMSGHDR_LEN + 2];
    let ifa_scope = msg[NLMSGHDR_LEN + 3];
    let ifa_index = u32_at(msg, NLMSGHDR_LEN + 4);
    if ifa_family != AF_INET {
        return;
    }
    let ifname = resolve_interface_name(ifa_index);

    // IFA_PAYLOAD(header) = nlmsg_len - NLMSG_SPACE(sizeof(ifaddrmsg)) = nlmsg_len - 24
    let payload_len = nlmsg_len.saturating_sub(NLMSGHDR_LEN + IFADDRMSG_LEN);
    let attr_off = NLMSGHDR_LEN + IFADDRMSG_LEN;
    let mut candidate: Option<usize> = None;
    for (rta_type, range) in walk_rtattrs(msg, attr_off, payload_len) {
        if rta_type == IFA_LOCAL {
            candidate = Some(range.start);
            break;
        }
        if rta_type == IFA_ADDRESS && candidate.is_none() {
            candidate = Some(range.start);
        }
    }
    let mut address = String::from("-");
    if let Some(start) = candidate {
        // C passes RTA_DATA directly to inet_ntop without checking RTA_PAYLOAD
        // >=4. A short but RTA_OK attribute therefore still reads its aligned
        // backing bytes. Mirror that when the received message contains them.
        if start + 4 <= msg.len() {
            let mut out = [0 as c_char; 16]; // INET_ADDRSTRLEN
            let ptr = unsafe {
                inet_ntop(AF_INET as c_int, msg[start..start + 4].as_ptr() as *const c_void, out.as_mut_ptr(), out.len() as u32)
            };
            if !ptr.is_null() {
                address = unsafe { std::ffi::CStr::from_ptr(out.as_ptr()) }.to_string_lossy().into_owned();
            }
        }
    }
    println!(
        "{} ifindex={} ifname={} address={} prefixlen={} scope={} flags=0x{:x}",
        message_type_name(nlmsg_type), ifa_index, ifname, address, ifa_prefixlen, ifa_scope, ifa_flags
    );
    flush_stdout_line();
}

/// Faithful port of process_netlink_buffer(): iterate nlmsghdr records,
/// validating length fields exactly like the C bounds checks, and dispatch
/// by nlmsg_type. Returns Err(()) on malformed data / netlink error, matching
/// the C version's `return -1` (which causes the caller to close the socket
/// and exit 1).
fn process_netlink_buffer(buffer: &[u8], received_length: usize) -> Result<(), ()> {
    let mut remaining = received_length;
    let mut offset = 0usize;
    while remaining >= NLMSGHDR_LEN {
        let msg = &buffer[offset..];
        let message_length = u32_at(msg, 0) as usize;
        let aligned_length = (message_length + 3) & !3;
        if message_length < NLMSGHDR_LEN || message_length > remaining || aligned_length > remaining {
            eprintln!("netwatch: malformed netlink message");
            return Err(());
        }
        let nlmsg_type = u16_at(msg, 4);
        match nlmsg_type {
            NLMSG_NOOP | NLMSG_DONE => {}
            NLMSG_OVERRUN => { println!("NETLINK_OVERRUN"); flush_stdout_line(); },
            NLMSG_ERROR => {
                // NLMSG_PAYLOAD(header,0) = nlmsg_len - 16; nlmsgerr starts with a 4-byte error field.
                if message_length < NLMSGHDR_LEN + 20 { // sizeof(struct nlmsgerr)
                    eprintln!("netwatch: malformed NLMSG_ERROR");
                    return Err(());
                }
                let error = i32_at(msg, NLMSGHDR_LEN);
                if error != 0 {
                    eprintln!("netwatch: netlink error: {}", c_strerror(&std::io::Error::from_raw_os_error(-error)));
                    return Err(());
                }
            }
            RTM_NEWLINK | RTM_DELLINK => print_link_event(&msg[..message_length.max(NLMSGHDR_LEN)]),
            RTM_NEWADDR | RTM_DELADDR => print_address_event(&msg[..message_length.max(NLMSGHDR_LEN)]),
            _ => {}
        }
        remaining -= aligned_length;
        offset += aligned_length;
    }
    if remaining != 0 {
        eprintln!("netwatch: trailing bytes in netlink buffer");
        return Err(());
    }
    Ok(())
}

fn run_watcher() -> i32 {
    let socket_fd = unsafe { socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE) };
    if socket_fd < 0 {
        eprintln!("netwatch: socket: {}", c_strerror(&std::io::Error::last_os_error()));
        return 1;
    }

    let receive_buffer_bytes: i32 = 256 * 1024;
    unsafe {
        setsockopt(
            socket_fd, SOL_SOCKET, SO_RCVBUF,
            &receive_buffer_bytes as *const i32 as *const c_void,
            std::mem::size_of::<i32>() as u32,
        );
    }

    let local_address = SockaddrNl {
        nl_family: AF_NETLINK as u16,
        nl_pad: 0,
        nl_pid: unsafe { getpid() } as u32,
        nl_groups: RTMGRP_LINK | RTMGRP_IPV4_IFADDR,
    };
    let bind_rc = unsafe {
        bind(
            socket_fd,
            &local_address as *const SockaddrNl as *const c_void,
            std::mem::size_of::<SockaddrNl>() as u32,
        )
    };
    if bind_rc != 0 {
        eprintln!("netwatch: bind: {}", c_strerror(&std::io::Error::last_os_error()));
        unsafe { close(socket_fd) };
        return 1;
    }

    let mut buffer = vec![0u8; RECEIVE_BUFFER_SIZE];
    while !G_STOP.load(Ordering::SeqCst) {
        let received_length = unsafe { recv(socket_fd, buffer.as_mut_ptr() as *mut c_void, buffer.len(), 0) };
        if received_length < 0 {
            if errno_now() == EINTR {
                continue;
            }
            eprintln!("netwatch: recv: {}", c_strerror(&std::io::Error::last_os_error()));
            unsafe { close(socket_fd) };
            return 1;
        }
        if received_length == 0 {
            continue;
        }
        if process_netlink_buffer(&buffer, received_length as usize).is_err() {
            unsafe { close(socket_fd) };
            return 1;
        }
    }
    unsafe { close(socket_fd) };
    0
}

fn print_help(program_name: &str) {
    println!("用法: {} [--help|--version]", program_name);
    println!("監看 Linux/Android 介面與 IPv4 位址的 rtnetlink 事件。");
    println!("閒置時阻塞在 recv()，不使用定時器、輪詢或 WakeLock。");
}

pub(crate) fn run() {
    let _ = CString::new(""); // keep std::ffi::CString import used across builds

    let args: Vec<String> = crate::multicall::args().collect();
    let argv0 = args.get(0).map(|s| s.as_str()).unwrap_or("netwatch");

    if args.len() > 2 {
        print_help(argv0);
        std::process::exit(2);
    }
    if args.len() == 2 {
        if args[1] == "--version" {
            println!("netwatch {}", VERSION);
            std::process::exit(0);
        }
        if args[1] == "--help" || args[1] == "-h" {
            print_help(argv0);
            std::process::exit(0);
        }
        eprintln!("netwatch: 未知參數: {}", args[1]);
        print_help(argv0);
        std::process::exit(2);
    }

    if !install_signal_handlers() {
        eprintln!("netwatch: sigaction: {}", c_strerror(&std::io::Error::last_os_error()));
        std::process::exit(1);
    }
    std::process::exit(run_watcher());
}
