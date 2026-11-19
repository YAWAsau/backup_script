//! Linux/Android process-connector transport, without ownership tracking.
//!
//! Call `listen` only AFTER the final service fork. Successful return means
//! subscription was acknowledged and a single blocking receiver was spawned.
//! This standalone sibling module is intentionally not wired into main.rs.
//!
//! No /proc access, polling, async runtime, or external dependencies.

#![cfg(any(target_os = "linux", target_os = "android"))]

use std::ffi::{c_int, c_long, c_void};
use std::io;
use std::mem::{size_of, zeroed};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Fork { parent: u32, child: u32 },
    Exec { pid: u32 },
    Exit { pid: u32 },
    Lost,
}

/// Parser output includes control replies so startup can validate the ACK.
/// `Error` carries the signed NLMSG_ERROR value; `Ack` the connector errno.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Parsed {
    Event(Event),
    Ack(u32),
    Error(i32),
}

const AF_NETLINK: c_int = 16;
const SOCK_DGRAM: c_int = 2;
const SOCK_CLOEXEC: c_int = 0x80000;
const NETLINK_CONNECTOR: c_int = 11;
const SOL_SOCKET: c_int = 1;
const SO_RCVTIMEO: c_int = 20;
const MSG_TRUNC: c_int = 0x20;
const EINTR: i32 = 4;
const ENOBUFS: i32 = 105;
const NLMSG_ERROR: u16 = 2;
const NLMSG_DONE: u16 = 3;
const NLMSG_OVERRUN: u16 = 4;
const SEQ: u32 = 1;
const REQUEST_ACK: u32 = 0;
const STAGING_LIMIT: usize = 4096;

#[repr(C)]
struct SockAddrNl {
    family: u16,
    pad: u16,
    pid: u32,
    groups: u32,
}
#[repr(C)]
struct IoVec {
    base: *mut c_void,
    len: usize,
}
#[repr(C)]
struct MsgHdr {
    name: *mut c_void,
    namelen: u32,
    iov: *mut IoVec,
    iovlen: usize,
    control: *mut c_void,
    controllen: usize,
    flags: c_int,
}
#[repr(C)]
struct TimeVal {
    sec: c_long,
    usec: c_long,
}

// libc is not a direct dependency. These are Linux/Android libc ABI calls.
// socklen_t is u32; timeval uses the native C long ABI.
unsafe extern "C" {
    fn socket(domain: c_int, kind: c_int, protocol: c_int) -> c_int;
    fn bind(fd: c_int, addr: *const c_void, len: u32) -> c_int;
    fn sendto(
        fd: c_int, buf: *const c_void, len: usize, flags: c_int,
        addr: *const c_void, addrlen: u32,
    ) -> isize;
    fn recvmsg(fd: c_int, msg: *mut MsgHdr, flags: c_int) -> isize;
    fn setsockopt(
        fd: c_int, level: c_int, option: c_int,
        value: *const c_void, len: u32,
    ) -> c_int;
    fn getpid() -> c_int;
}

fn u16_at(b: &[u8], n: usize) -> u16 {
    u16::from_ne_bytes([b[n], b[n + 1]])
}
fn u32_at(b: &[u8], n: usize) -> u32 {
    u32::from_ne_bytes([b[n], b[n + 1], b[n + 2], b[n + 3]])
}
fn put32(b: &mut [u8], n: usize, v: u32) {
    b[n..n + 4].copy_from_slice(&v.to_ne_bytes());
}
fn lost(out: &mut Vec<Parsed>) {
    out.push(Parsed::Event(Event::Lost));
}

/// Parse one recvmsg datagram. Sender metadata MUST come from recvmsg's
/// sockaddr_nl, never from nlmsg_pid inside the untrusted message bytes.
///
/// Wrong senders are ignored, including their truncation flags. A truncated
/// kernel datagram is discarded in its entirety and reported as Lost.
pub fn parse_datagram(
    bytes: &[u8], sender_pid: u32, sender_is_netlink: bool, truncated: bool,
) -> Vec<Parsed> {
    let mut out = Vec::new();
    if !sender_is_netlink || sender_pid != 0 {
        return out;
    }
    if truncated {
        lost(&mut out);
        return out;
    }

    let mut pos = 0;
    while pos < bytes.len() {
        let remaining = bytes.len() - pos;
        if remaining < 16 {
            lost(&mut out);
            break;
        }
        let h = &bytes[pos..];
        let len = u32_at(h, 0) as usize;
        if len < 16 || len > remaining {
            lost(&mut out);
            break;
        }
        let body = &h[16..len];
        match u16_at(h, 4) {
            NLMSG_ERROR => {
                // struct nlmsgerr = signed error + original nlmsghdr.
                if body.len() < 20 {
                    lost(&mut out);
                } else {
                    out.push(Parsed::Error(i32::from_ne_bytes(
                        body[..4].try_into().unwrap(),
                    )));
                }
            }
            NLMSG_OVERRUN => lost(&mut out),
            NLMSG_DONE => parse_connector(body, &mut out),
            _ => {}
        }
        if len == remaining {
            break; // Final message need not carry alignment padding.
        }
        let aligned = (len + 3) & !3;
        if aligned > remaining {
            lost(&mut out);
            break;
        }
        pos += aligned;
    }
    out
}

fn parse_connector(body: &[u8], out: &mut Vec<Parsed>) {
    // cn_msg: id(8), seq(4), ack(4), len(2), flags(2).
    if body.len() < 20 {
        lost(out);
        return;
    }
    if u32_at(body, 0) != 1 || u32_at(body, 4) != 1 {
        return;
    }
    let len = u16_at(body, 16) as usize;
    if len != body.len() - 20 || len < 16 {
        lost(out);
        return;
    }
    let ev = &body[20..];
    // what + cpu + timestamp is 16 bytes. Read only fields needed for
    // each event, NOT sizeof(struct proc_event), particularly for ACK.
    let what = u32_at(ev, 0);
    let required = match what {
        0 => 20,
        1 => 32,
        2 => 24,
        0x4 => 32,   // UID: process_pid, process_tgid, ruid, euid
        0x200 => 40, // COMM: process_pid, process_tgid, comm[16]
        0x8000_0000 => 32,
        _ => return,
    };
    if ev.len() < required {
        lost(out);
        return;
    }
    match what {
        0 => {
            // cn_proc replaces seq with a per-CPU counter; only ack
            // correlates the reply with the request's ack + 1.
            if u32_at(body, 12) == REQUEST_ACK + 1 {
                out.push(Parsed::Ack(u32_at(ev, 16)));
            }
        }
        1 => {
            let child_pid = u32_at(ev, 24);
            let child_tgid = u32_at(ev, 28);
            if child_pid == child_tgid {
                out.push(Parsed::Event(Event::Fork {
                    parent: u32_at(ev, 20),
                    child: child_tgid,
                }));
            }
        }
        2 => out.push(Parsed::Event(Event::Exec { pid: u32_at(ev, 20) })),
        0x4 | 0x200 => {
            // Zygote specializes without exec. These are refresh signals,
            // never name/credential authority. Ignore per-thread changes.
            if u32_at(ev, 16) == u32_at(ev, 20) {
                out.push(Parsed::Event(Event::Exec { pid: u32_at(ev, 20) }));
            }
        }
        0x8000_0000 => {
            if u32_at(ev, 16) == u32_at(ev, 20) {
                out.push(Parsed::Event(Event::Exit { pid: u32_at(ev, 20) }));
            }
        }
        _ => unreachable!(),
    }
}

fn retry_int(mut f: impl FnMut() -> c_int) -> io::Result<c_int> {
    loop {
        let rc = f();
        if rc >= 0 {
            return Ok(rc);
        }
        let err = io::Error::last_os_error();
        if err.raw_os_error() != Some(EINTR) {
            return Err(err);
        }
    }
}

fn timeout(fd: &OwnedFd, duration: Option<Duration>) -> io::Result<()> {
    let tv = match duration {
        None => TimeVal { sec: 0, usec: 0 },
        Some(d) => {
            // Round upwards; a zero timeval would disable the timeout.
            let micros = d.as_micros().max(1).min(2_000_000) as u64;
            TimeVal {
                sec: (micros / 1_000_000) as c_long,
                usec: (micros % 1_000_000) as c_long,
            }
        }
    };
    retry_int(|| unsafe {
        setsockopt(
            fd.as_raw_fd(), SOL_SOCKET, SO_RCVTIMEO,
            &tv as *const _ as *const c_void, size_of::<TimeVal>() as u32,
        )
    })?;
    Ok(())
}

fn receive(fd: &OwnedFd, buf: &mut [u8]) -> io::Result<Option<Vec<Parsed>>> {
    let mut addr: SockAddrNl = unsafe { zeroed() };
    let mut iov = IoVec { base: buf.as_mut_ptr().cast(), len: buf.len() };
    let mut msg = MsgHdr {
        name: &mut addr as *mut _ as *mut c_void,
        namelen: size_of::<SockAddrNl>() as u32,
        iov: &mut iov,
        iovlen: 1,
        control: std::ptr::null_mut(),
        controllen: 0,
        flags: 0,
    };
    let n = unsafe { recvmsg(fd.as_raw_fd(), &mut msg, 0) };
    if n < 0 {
        return Err(io::Error::last_os_error());
    }
    if n == 0 {
        return Ok(None);
    }
    let n = n as usize;
    Ok(Some(parse_datagram(
        &buf[..n.min(buf.len())],
        addr.pid,
        msg.namelen as usize >= size_of::<SockAddrNl>()
            && addr.family == AF_NETLINK as u16,
        msg.flags & MSG_TRUNC != 0 || n > buf.len(),
    )))
}

fn control_error(code: i32) -> io::Error {
    match code.checked_abs() {
        Some(n) if n != 0 => io::Error::from_raw_os_error(n),
        _ => io::Error::new(io::ErrorKind::InvalidData, "invalid netlink error"),
    }
}

/// Subscribe synchronously, validate the connector ACK, then spawn exactly
/// one blocking receiver. There is no receiver timeout after startup.
///
/// Startup has a two-second total ACK deadline. SO_RCVTIMEO bounds each
/// blocking receive by the remaining budget; this is not a polling loop.
/// Events received during the handshake are bounded and staged in order.
/// A full staging queue fails startup rather than silently dropping events.
fn listen_connector(handler: impl Fn(Event) + Send + 'static) -> io::Result<()> {
    let raw = retry_int(|| unsafe {
        socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_CONNECTOR)
    })?;
    let fd = unsafe { OwnedFd::from_raw_fd(raw) };
    let pid = unsafe { getpid() } as u32;
    let local = SockAddrNl {
        family: AF_NETLINK as u16, pad: 0, pid, groups: 1,
    };
    retry_int(|| unsafe {
        bind(
            fd.as_raw_fd(), &local as *const _ as *const c_void,
            size_of::<SockAddrNl>() as u32,
        )
    })?;

    let kernel = SockAddrNl {
        family: AF_NETLINK as u16, pad: 0, pid: 0, groups: 0,
    };
    let mut request = [0u8; 40];
    put32(&mut request, 0, 40);
    request[4..6].copy_from_slice(&NLMSG_DONE.to_ne_bytes());
    put32(&mut request, 8, SEQ);
    put32(&mut request, 12, pid);
    put32(&mut request, 16, 1); // CN_IDX_PROC
    put32(&mut request, 20, 1); // CN_VAL_PROC
    put32(&mut request, 24, SEQ);
    put32(&mut request, 28, REQUEST_ACK);
    request[32..34].copy_from_slice(&4u16.to_ne_bytes());
    put32(&mut request, 36, 1); // PROC_CN_MCAST_LISTEN

    timeout(&fd, Some(Duration::from_secs(2)))?;
    loop {
        let n = unsafe {
            sendto(
                fd.as_raw_fd(), request.as_ptr().cast(), request.len(), 0,
                &kernel as *const _ as *const c_void,
                size_of::<SockAddrNl>() as u32,
            )
        };
        if n == request.len() as isize {
            break;
        }
        if n >= 0 {
            return Err(io::Error::new(io::ErrorKind::WriteZero, "short subscription"));
        }
        let err = io::Error::last_os_error();
        if err.raw_os_error() != Some(EINTR) {
            return Err(err);
        }
    }

    let deadline = Instant::now() + Duration::from_secs(2);
    let mut staged = Vec::new();
    let mut buf = vec![0u8; 65536];
    let mut acknowledged = false;
    while !acknowledged {
        let remaining = deadline.checked_duration_since(Instant::now())
            .filter(|d| !d.is_zero())
            .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, "connector ACK deadline"))?;
        timeout(&fd, Some(remaining))?;
        let messages = match receive(&fd, &mut buf) {
            Ok(Some(v)) => v,
            Ok(None) => return Err(io::Error::new(
                io::ErrorKind::UnexpectedEof, "connector closed before ACK",
            )),
            Err(e) if e.raw_os_error() == Some(EINTR) => continue,
            Err(e) if e.raw_os_error() == Some(ENOBUFS) => {
                vec![Parsed::Event(Event::Lost)]
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock
                || e.kind() == io::ErrorKind::TimedOut =>
            {
                return Err(io::Error::new(io::ErrorKind::TimedOut, "connector ACK deadline"));
            }
            Err(e) => return Err(e),
        };
        for message in messages {
            match message {
                Parsed::Ack(0) => acknowledged = true,
                Parsed::Ack(errno) => return Err(if errno <= i32::MAX as u32 {
                    io::Error::from_raw_os_error(errno as i32)
                } else {
                    io::Error::new(io::ErrorKind::InvalidData, "invalid connector ACK errno")
                }),
                Parsed::Error(0) => {} // NOT a connector subscription ACK.
                Parsed::Error(code) => return Err(control_error(code)),
                Parsed::Event(event) => {
                    if staged.len() == STAGING_LIMIT {
                        return Err(io::Error::new(
                            io::ErrorKind::OutOfMemory, "connector startup queue full",
                        ));
                    }
                    staged.push(event);
                }
            }
        }
    }
    timeout(&fd, None)?;
    std::thread::Builder::new()
        .name("process-connector".into())
        .spawn(move || {
            // fd remains owned here, including during handler unwinding.
            for event in staged {
                handler(event);
            }
            loop {
                match receive(&fd, &mut buf) {
                    Ok(Some(messages)) => {
                        for message in messages {
                            match message {
                                Parsed::Event(event) => handler(event),
                                Parsed::Ack(0) | Parsed::Error(0) => {}
                                Parsed::Ack(_) | Parsed::Error(_) => {
                                    handler(Event::Lost);
                                    return;
                                }
                            }
                        }
                    }
                    Err(e) if e.raw_os_error() == Some(EINTR) => continue,
                    Err(e) if e.raw_os_error() == Some(ENOBUFS) => {
                        handler(Event::Lost);
                    }
                    Ok(None) | Err(_) => {
                        handler(Event::Lost);
                        return;
                    }
                }
            }
        })?;
    Ok(())
}


// Startup selection only: runtime loss never silently switches transports.
static BACKEND: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);

/// Selected transport, or "none" before successful startup.
/// This labels the transport, not a guarantee of continuing coverage after Lost.
pub fn backend_label() -> &'static str {
    match BACKEND.load(std::sync::atomic::Ordering::Acquire) {
        1 => "connector",
        2 => "perf",
        _ => "none",
    }
}

pub fn listen(handler: impl Fn(Event) + Send + 'static) -> io::Result<()> {
    let handler = std::sync::Arc::new(std::sync::Mutex::new(handler));
    let connector_handler = handler.clone();
    let selected = match listen_connector(move |event| {
        (connector_handler.lock().unwrap())(event);
    }) {
        Ok(()) => 1,
        Err(connector_error) => {
            super::perf::listen(move |event| {
                (handler.lock().unwrap())(event);
            }).map_err(|perf_error| io::Error::new(
                perf_error.kind(),
                format!("connector startup: {connector_error}; perf startup: {perf_error}"),
            ))?;
            2
        }
    };
    BACKEND.store(selected, std::sync::atomic::Ordering::Release);
    // Existing owned integration tests call this same startup path.
    #[cfg(test)]
    eprintln!("process monitor actual backend: {}", backend_label());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame(kind: u16, body: &[u8]) -> Vec<u8> {
        let mut b = vec![0; 16 + body.len()];
        let len = b.len() as u32;
        put32(&mut b, 0, len);
        b[4..6].copy_from_slice(&kind.to_ne_bytes());
        b[16..].copy_from_slice(body);
        b
    }

    fn event(what: u32, fields: &[u32]) -> Vec<u8> {
        let mut cn = vec![0; 36 + fields.len() * 4];
        put32(&mut cn, 0, 1);
        put32(&mut cn, 4, 1);
        put32(&mut cn, 8, SEQ);
        put32(&mut cn, 12, REQUEST_ACK + 1);
        let len = (cn.len() - 20) as u16;
        cn[16..18].copy_from_slice(&len.to_ne_bytes());
        put32(&mut cn, 20, what);
        for (i, field) in fields.iter().enumerate() {
            put32(&mut cn, 36 + 4 * i, *field);
        }
        frame(NLMSG_DONE, &cn)
    }

    fn parse(b: &[u8]) -> Vec<Parsed> {
        parse_datagram(b, 0, true, false)
    }

    #[test]
    fn minimal_ack_and_error_ack() {
        assert_eq!(parse(&event(0, &[0])), vec![Parsed::Ack(0)]);
        assert_eq!(parse(&event(0, &[13])), vec![Parsed::Ack(13)]);
        assert_eq!(parse(&event(0, &[])), vec![Parsed::Event(Event::Lost)]);
        let mut wrong = event(0, &[0]);
        put32(&mut wrong, 28, 99);
        assert!(parse(&wrong).is_empty());
    }

    #[test]
    fn ack_accepts_arbitrary_kernel_sequence() {
        // POCO's full proc_event ACK: cn len 40, nlmsg len 76, ack 1.
        for seq in [0, 1, 5760, u32::MAX] {
            let mut b = event(0, &[0, 0, 0, 0, 0, 0]);
            assert_eq!(b.len(), 76);
            assert_eq!(u16_at(&b, 32), 40);
            put32(&mut b, 24, seq);
            put32(&mut b, 28, 1);
            assert_eq!(parse(&b), vec![Parsed::Ack(0)]);
        }
    }

    #[test]
    fn ack_rejects_wrong_ack_even_with_matching_sequence() {
        for seq in [SEQ, 5760] {
            for ack in [0, 2, 99, u32::MAX] {
                let mut b = event(0, &[0, 0, 0, 0, 0, 0]);
                put32(&mut b, 24, seq);
                put32(&mut b, 28, ack);
                assert!(parse(&b).is_empty(), "seq={seq}, ack={ack}");
            }
        }
    }

    #[test]
    fn tgid_and_thread_filtering() {
        assert_eq!(
            parse(&event(1, &[101, 100, 200, 200])),
            vec![Parsed::Event(Event::Fork { parent: 100, child: 200 })]
        );
        assert!(parse(&event(1, &[101, 100, 201, 200])).is_empty());
        assert_eq!(
            parse(&event(2, &[201, 200])),
            vec![Parsed::Event(Event::Exec { pid: 200 })]
        );
        assert!(parse(&event(0x8000_0000, &[201, 200, 0, 0])).is_empty());
        assert_eq!(
            parse(&event(0x8000_0000, &[200, 200, 0, 0])),
            vec![Parsed::Event(Event::Exit { pid: 200 })]
        );
    }

    #[test]
    fn comm_and_uid_are_leader_refresh_signals() {
        for (what,mut fields) in [
            (0x4,vec![200,200,10001,10001]),
            (0x200,vec![200,200,0,0,0,0]),
        ] {
            assert_eq!(parse(&event(what,&fields)),
                vec![Parsed::Event(Event::Exec{pid:200})]);
            fields[0]=201;
            assert!(parse(&event(what,&fields)).is_empty());
            fields.truncate(2);
            assert_eq!(parse(&event(what,&fields)),
                vec![Parsed::Event(Event::Lost)]);
        }
    }

    #[test]
    fn sender_and_connector_id() {
        let mut b = event(2, &[4, 4]);
        assert!(parse_datagram(&b, 123, true, false).is_empty());
        assert!(parse_datagram(&b, 0, false, false).is_empty());
        assert!(parse_datagram(&b, 123, true, true).is_empty());
        put32(&mut b, 16, 2);
        assert!(parse(&b).is_empty());
        put32(&mut b, 16, 1);
        put32(&mut b, 20, 2);
        assert!(parse(&b).is_empty());
    }

    #[test]
    fn truncation_and_malformed_lengths() {
        let b = event(1, &[1, 1, 2, 2]);
        assert_eq!(
            parse_datagram(&b, 0, true, true),
            vec![Parsed::Event(Event::Lost)]
        );
        for n in 1..b.len() {
            assert!(parse(&b[..n]).contains(&Parsed::Event(Event::Lost)));
        }
        let mut bad = b.clone();
        put32(&mut bad, 0, 15);
        assert_eq!(parse(&bad), vec![Parsed::Event(Event::Lost)]);
        put32(&mut bad, 0, u32::MAX);
        assert_eq!(parse(&bad), vec![Parsed::Event(Event::Lost)]);
        let mut bad = b;
        bad[32..34].copy_from_slice(&u16::MAX.to_ne_bytes());
        assert_eq!(parse(&bad), vec![Parsed::Event(Event::Lost)]);
        assert_eq!(parse(&event(2, &[4])), vec![Parsed::Event(Event::Lost)]);
    }

    #[test]
    fn nlmsg_error_and_overrun() {
        let mut body = [0u8; 20];
        body[..4].copy_from_slice(&(-13i32).to_ne_bytes());
        assert_eq!(parse(&frame(NLMSG_ERROR, &body)), vec![Parsed::Error(-13)]);
        assert_eq!(
            parse(&frame(NLMSG_ERROR, &body[..4])),
            vec![Parsed::Event(Event::Lost)]
        );
        assert_eq!(
            parse(&frame(NLMSG_OVERRUN, &[])),
            vec![Parsed::Event(Event::Lost)]
        );
    }

    #[test]
    fn multiple_messages_alignment_and_order() {
        // Unknown message with an odd length, followed by aligned events.
        let mut b = frame(99, &[7]);
        b.resize((b.len() + 3) & !3, 0);
        b.extend(event(2, &[8, 8]));
        b.extend(event(0, &[0]));
        b.extend(event(0x8000_0000, &[8, 8, 0, 0]));
        assert_eq!(parse(&b), vec![
            Parsed::Event(Event::Exec { pid: 8 }),
            Parsed::Ack(0),
            Parsed::Event(Event::Exit { pid: 8 }),
        ]);
        // Parsing does not depend on the byte slice's address alignment.
        let mut unaligned = vec![0];
        unaligned.extend(&b);
        assert_eq!(parse(&unaligned[1..]), parse(&b));
    }
}
