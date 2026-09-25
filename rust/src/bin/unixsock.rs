// unixsock.rs - faithful Rust port of c/unixsock.c
// Relays stdin -> unix/tcp socket -> stdout, with optional two-line response
// header capture (exact-length / chunked / raw-until-EOF body framing).
// Every exit-code decision and the EPIPE-on-stdout "consumer closed early is
// not an error" behavior is reproduced exactly against c/unixsock.c.

use speedbackup_native_rs::c_strerror;
use std::ffi::{CStr, CString};
use std::io::{self, BufReader, ErrorKind, Read, Write};
use std::net::{Shutdown, TcpStream};
use std::os::fd::FromRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::net::UnixStream;

const VERSION: &str = "unixsock 2.5.0-root-snapshot-v1-plain-lines-single-eof-api28-r30";
const HEADER_LINE_MAX: usize = 4096;
const COPY_BUFFER_SIZE: usize = 128 * 1024;
const UNIX_SUN_PATH_MAX: usize = 108;

#[repr(C)]
struct SockAddrUn {
    sun_family: u16,
    sun_path: [std::os::raw::c_char; UNIX_SUN_PATH_MAX],
}

#[repr(C)]
struct AddrInfo {
    ai_flags: i32,
    ai_family: i32,
    ai_socktype: i32,
    ai_protocol: i32,
    ai_addrlen: u32,
    // Bionic puts canonname before addr; glibc/musl put it after addr.
    // A Linux layout on Android reads the null canonname as a sockaddr.
    #[cfg(target_os = "android")]
    ai_canonname: *mut std::os::raw::c_char,
    ai_addr: *mut std::os::raw::c_void,
    #[cfg(not(target_os = "android"))]
    ai_canonname: *mut std::os::raw::c_char,
    ai_next: *mut AddrInfo,
}

extern "C" {
    fn open(path: *const std::os::raw::c_char, flags: i32, mode: u32) -> i32;
    fn write(fd: i32, buf: *const std::os::raw::c_void, count: usize) -> isize;
    fn fchmod(fd: i32, mode: u32) -> i32;
    fn getaddrinfo(node: *const std::os::raw::c_char, service: *const std::os::raw::c_char,
                   hints: *const AddrInfo, res: *mut *mut AddrInfo) -> i32;
    fn freeaddrinfo(res: *mut AddrInfo);
    fn gai_strerror(code: i32) -> *const std::os::raw::c_char;
    fn socket(domain: i32, ty: i32, protocol: i32) -> i32;
    fn connect(fd: i32, addr: *const std::os::raw::c_void, len: u32) -> i32;
    fn close(fd: i32) -> i32;
    fn fork() -> i32;
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
    fn signal(sig: i32, handler: usize) -> usize;
    fn _exit(status: i32) -> !;
}

const AF_UNSPEC: i32 = 0;
const AF_UNIX: i32 = 1;
const SOCK_STREAM: i32 = 1;
const SOCK_CLOEXEC: i32 = 0o2000000;
const IPPROTO_TCP: i32 = 6;
const SIGPIPE: i32 = 13;
const SIG_IGN: usize = 1;
const EINTR: i32 = 4;
const O_WRONLY: i32 = 0o1;
const O_CREAT: i32 = 0o100;
const O_TRUNC: i32 = 0o1000;
const O_NONBLOCK: i32 = 0o4000;
const O_CLOEXEC: i32 = 0o2000000;

enum Conn {
    Unix(UnixStream),
    Tcp(TcpStream),
}
impl Conn {
    fn shutdown(&self, how: Shutdown) -> io::Result<()> {
        match self {
            Conn::Unix(s) => s.shutdown(how),
            Conn::Tcp(s) => s.shutdown(how),
        }
    }
}
impl Read for Conn {
    fn read(&mut self, b: &mut [u8]) -> io::Result<usize> {
        match self {
            Conn::Unix(s) => s.read(b),
            Conn::Tcp(s) => s.read(b),
        }
    }
}
impl Write for Conn {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        match self {
            Conn::Unix(s) => s.write(b),
            Conn::Tcp(s) => s.write(b),
        }
    }
    fn flush(&mut self) -> io::Result<()> {
        match self {
            Conn::Unix(s) => s.flush(),
            Conn::Tcp(s) => s.flush(),
        }
    }
}

fn usage() {
    eprintln!(
        "{}\nUsage:\n  unixsock relay-unix <socketPath> [--header-file <path>]\n  unixsock relay-tcp <host> <port> [--header-file <path>]\n  unixsock root-args-unix <socketPath> <namespace> <command> <headerPath> [args...]\n  unixsock root-file-unix <socketPath> <namespace> <command> <headerPath> <bodyPath> [appstateUser appstateExtra]\n  unixsock capabilities\n\nstdin is copied to the socket. At stdin EOF the write side is half-closed,\nwhile the socket response continues to stdout. With --header-file, the first\ntwo newline-terminated response lines are written to that file and only the\nremaining binary body is written to stdout. The second header line may be\nan exact byte count, -1 (raw until EOF), or -2 (daemon chunk framing).\nWith --allow-plain-response and --header-file, a single-line plain\nresponse at EOF or a nonnumeric second response line is replayed to\nstdout and the header file receives the first line plus -1. Strict\nframed behavior is unchanged without --allow-plain-response.",
        VERSION
    );
}

fn parse_relay_args(args: &[String], start: usize) -> Result<(Option<String>, bool), i32> {
    let mut header_file = None;
    let mut allow_plain_response = false;
    let mut i = start;
    while i < args.len() {
        match args[i].as_str() {
            "--header-file" => {
                if i + 1 >= args.len() || args[i + 1].is_empty() {
                    return Err(2);
                }
                header_file = Some(args[i + 1].clone());
                i += 2;
            }
            "--allow-plain-response" => {
                allow_plain_response = true;
                i += 1;
            }
            _ => return Err(2),
        }
    }
    Ok((header_file, allow_plain_response))
}

/// Faithful port of read_header_line(): reads byte-by-byte up to '\n',
/// strips a trailing '\r', returns Ok(None) on clean-vs-protocol-error EOF
/// distinguished via the `Protocol` error kind (matches C's errno=EPROTO on
/// EOF-before-newline, vs Ok(None) semantics used only by the plain-response
/// fallback path which needs to distinguish "no second line at all").
fn read_header_line<R: Read>(r: &mut R) -> io::Result<Vec<u8>> {
    let mut buf = Vec::with_capacity(64);
    loop {
        if buf.len() + 1 >= HEADER_LINE_MAX {
            return Err(io::Error::from_raw_os_error(90)); // EMSGSIZE
        }
        let mut byte = [0u8; 1];
        match r.read(&mut byte) {
            Ok(0) => return Err(io::Error::new(ErrorKind::Other, "EPROTO")),
            Ok(_) => {}
            Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        }
        if byte[0] == b'\n' {
            if buf.last() == Some(&b'\r') { buf.pop(); }
            return Ok(buf);
        }
        buf.push(byte[0]);
    }
}

fn c_visible(bytes: &[u8]) -> &[u8] {
    &bytes[..bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len())]
}

fn c_visible_string(bytes: &[u8]) -> String {
    String::from_utf8_lossy(c_visible(bytes)).into_owned()
}

fn is_protocol_eof(e: &io::Error) -> bool {
    e.kind() == ErrorKind::Other && e.to_string() == "EPROTO"
}

fn write_all_fd_c(fd: i32, mut data: &[u8]) -> io::Result<()> {
    while !data.is_empty() {
        let n = unsafe { write(fd, data.as_ptr() as *const std::os::raw::c_void, data.len()) };
        if n > 0 {
            data = &data[n as usize..];
            continue;
        }
        if n < 0 && io::Error::last_os_error().raw_os_error() == Some(EINTR) { continue; }
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

fn write_response_header_file(path: &str, line1: &[u8], line2: &[u8]) -> io::Result<()> {
    // Mirror C open/fchmod/write_all/close exactly, including reporting a
    // close() errno if close itself fails.
    let cpath = CString::new(path).map_err(|_| io::Error::from_raw_os_error(22))?;
    let fd = unsafe { open(cpath.as_ptr(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600) };
    if fd < 0 { return Err(io::Error::last_os_error()); }
    let mut first_err: Option<io::Error> = None;
    if unsafe { fchmod(fd, 0o600) } != 0 {
        first_err = Some(io::Error::last_os_error());
    } else {
        for part in [line1, b"\n" as &[u8], line2, b"\n" as &[u8]] {
            if let Err(e) = write_all_fd_c(fd, part) { first_err = Some(e); break; }
        }
    }
    let close_rc = unsafe { close(fd) };
    if close_rc != 0 { return Err(io::Error::last_os_error()); }
    if let Some(e) = first_err { Err(e) } else { Ok(()) }
}

fn is_c_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c)
}

fn parse_body_mode_bytes(line: &[u8]) -> Option<i64> {
    // C strtoll() sees the NUL-terminated prefix even though the raw header
    // length (used for file/stdout replay) may contain embedded NUL bytes.
    let b = c_visible(line);
    if b.is_empty() { return None; }
    let mut i = 0usize;
    while i < b.len() && is_c_space(b[i]) { i += 1; }
    if i >= b.len() { return None; }
    let neg = if b[i] == b'+' { i += 1; false } else if b[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut v: u128 = 0;
    let limit = if neg { (i64::MAX as u128) + 1 } else { i64::MAX as u128 };
    while i < b.len() && b[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add((b[i] - b'0') as u128);
        if v > limit { return None; }
        i += 1;
    }
    if i == start || i != b.len() { return None; }
    let out = if neg {
        if v == (i64::MAX as u128) + 1 { i64::MIN } else { -(v as i64) }
    } else { v as i64 };
    if out < -2 { None } else { Some(out) }
}

fn parse_chunk_size_c_bytes(line: &[u8]) -> Option<u64> {
    let visible = c_visible(line);
    let mut b = visible;
    if let Some(pos) = visible.iter().position(|&x| x == b';') { b = &visible[..pos]; }
    let mut i = 0usize;
    while i < b.len() && is_c_space(b[i]) { i += 1; }
    if i >= b.len() { return None; }
    let neg = if b[i] == b'+' { i += 1; false } else if b[i] == b'-' { i += 1; true } else { false };
    let digits_start_before_prefix = i;
    // strtoull(..., base=16) recognizes 0x/0X only when a hex digit follows.
    if i + 2 < b.len() && b[i] == b'0' && (b[i + 1] == b'x' || b[i + 1] == b'X') && b[i + 2].is_ascii_hexdigit() {
        i += 2;
    }
    let start = i;
    let mut v: u128 = 0;
    while i < b.len() {
        let d = match b[i] {
            b'0'..=b'9' => (b[i] - b'0') as u128,
            b'a'..=b'f' => (b[i] - b'a' + 10) as u128,
            b'A'..=b'F' => (b[i] - b'A' + 10) as u128,
            _ => break,
        };
        v = v.saturating_mul(16).saturating_add(d);
        if v > u64::MAX as u128 { return None; }
        i += 1;
    }
    // If no digit followed an unrecognized "0x", C still consumes the
    // leading '0'. Our prefix gate above deliberately leaves i untouched in
    // that case, so this same digit loop handles it.
    if i == start {
        // The only possible conversion before an unrecognized prefix is its
        // leading zero; retry that exact C case.
        if digits_start_before_prefix < b.len() && b[digits_start_before_prefix] == b'0' {
            i = digits_start_before_prefix + 1;
            v = 0;
        } else {
            return None;
        }
    }
    if i != b.len() { return None; }
    let u = v as u64;
    Some(if neg { 0u64.wrapping_sub(u) } else { u })
}

/// Writes `buf` to stdout. On EPIPE (downstream consumer closed its end of
/// the pipe), this is NOT an error - matches C's write_stdout() which sets
/// consumer_closed and returns success so the caller can shut down the
/// socket and exit 0, exactly like closing `unixsock ... | head -n5` should.
fn write_stdout_tolerant<W: Write>(w: &mut W, buf: &[u8], consumer_closed: &mut bool) -> io::Result<()> {
    match w.write_all(buf) {
        Ok(()) => Ok(()),
        Err(ref e) if e.kind() == ErrorKind::BrokenPipe => {
            *consumer_closed = true;
            Ok(())
        }
        Err(e) => Err(e),
    }
}

fn copy_exact_response<R: Read, W: Write>(r: &mut R, w: &mut W, mut remaining: u64, consumer_closed: &mut bool) -> io::Result<()> {
    let mut buf = vec![0u8; COPY_BUFFER_SIZE];
    while remaining > 0 {
        let want = remaining.min(COPY_BUFFER_SIZE as u64) as usize;
        let n = match r.read(&mut buf[..want]) {
            Ok(0) => return Err(io::Error::new(ErrorKind::Other, "EPROTO")),
            Ok(n) => n,
            Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        };
        write_stdout_tolerant(w, &buf[..n], consumer_closed)?;
        if *consumer_closed {
            return Ok(());
        }
        remaining -= n as u64;
    }
    Ok(())
}

fn consume_crlf<R: Read>(r: &mut R) -> io::Result<()> {
    let mut pair = [0u8; 2];
    r.read_exact(&mut pair).map_err(|_| io::Error::new(ErrorKind::Other, "EPROTO"))?;
    if &pair != b"\r\n" {
        return Err(io::Error::new(ErrorKind::Other, "EPROTO"));
    }
    Ok(())
}

fn relay_daemon_chunks<R: Read, W: Write>(r: &mut R, w: &mut W, consumer_closed: &mut bool) -> io::Result<()> {
    loop {
        let line = read_header_line(r)?;
        let chunk_size = parse_chunk_size_c_bytes(&line).ok_or_else(|| io::Error::new(ErrorKind::Other, "EPROTO"))?;
        if chunk_size == 0 {
            let trailer = read_header_line(r)?;
            if !trailer.is_empty() {
                return Err(io::Error::new(ErrorKind::Other, "EPROTO"));
            }
            return Ok(());
        }
        copy_exact_response(r, w, chunk_size, consumer_closed)?;
        if *consumer_closed {
            return Ok(());
        }
        consume_crlf(r)?;
    }
}

fn copy_fd_to_stdout<R: Read, W: Write>(r: &mut R, w: &mut W, consumer_closed: &mut bool) -> io::Result<()> {
    let mut buf = vec![0u8; COPY_BUFFER_SIZE];
    loop {
        let n = match r.read(&mut buf) {
            Ok(0) => return Ok(()),
            Ok(n) => n,
            Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        };
        write_stdout_tolerant(w, &buf[..n], consumer_closed)?;
        if *consumer_closed {
            return Ok(());
        }
    }
}

fn connect_unix_socket(path: &str) -> io::Result<UnixStream> {
    if !path.starts_with('/') { return Err(io::Error::from_raw_os_error(22)); }
    let raw = path.as_bytes();
    if raw.len() >= UNIX_SUN_PATH_MAX { return Err(io::Error::from_raw_os_error(36)); }
    let fd = unsafe { socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0) };
    if fd < 0 { return Err(io::Error::last_os_error()); }
    let mut addr = SockAddrUn { sun_family: AF_UNIX as u16, sun_path: [0; UNIX_SUN_PATH_MAX] };
    for (i, &b) in raw.iter().enumerate() { addr.sun_path[i] = b as std::os::raw::c_char; }
    // offsetof(sockaddr_un, sun_path)==2 on Linux/Android; add NUL byte.
    let addr_len = (2 + raw.len() + 1) as u32;
    if unsafe { connect(fd, &addr as *const SockAddrUn as *const std::os::raw::c_void, addr_len) } != 0 {
        let e = io::Error::last_os_error();
        unsafe { close(fd); }
        return Err(e);
    }
    Ok(unsafe { UnixStream::from_raw_fd(fd) })
}

fn connect_tcp_socket(host: &str, port: &str) -> io::Result<TcpStream> {
    let chost = CString::new(host).map_err(|_| io::Error::from_raw_os_error(22))?;
    let cport = CString::new(port).map_err(|_| io::Error::from_raw_os_error(22))?;
    let hints = AddrInfo {
        ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
        ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_addr: std::ptr::null_mut(),
        ai_canonname: std::ptr::null_mut(), ai_next: std::ptr::null_mut(),
    };
    let mut result: *mut AddrInfo = std::ptr::null_mut();
    let rc = unsafe { getaddrinfo(chost.as_ptr(), cport.as_ptr(), &hints, &mut result) };
    if rc != 0 {
        let msg = unsafe {
            let p = gai_strerror(rc);
            if p.is_null() { "Unknown error".to_string() } else { CStr::from_ptr(p).to_string_lossy().into_owned() }
        };
        return Err(io::Error::new(ErrorKind::Other, format!("getaddrinfo: {} (EAI {})", msg, rc)));
    }

    let mut item = result;
    while !item.is_null() {
        let ai = unsafe { &*item };
        let fd = unsafe { socket(ai.ai_family, ai.ai_socktype | SOCK_CLOEXEC, ai.ai_protocol) };
        if fd >= 0 {
            if unsafe { connect(fd, ai.ai_addr as *const _, ai.ai_addrlen) } == 0 {
                unsafe { freeaddrinfo(result); }
                return Ok(unsafe { TcpStream::from_raw_fd(fd) });
            }
            // C closes the failed fd without restoring the previous errno.
            unsafe { close(fd); }
        }
        item = ai.ai_next;
    }
    unsafe { freeaddrinfo(result); }
    // Match the C caller's eventual strerror(errno): preserve whatever errno
    // remains after the last socket/connect/close/freeaddrinfo sequence.
    Err(io::Error::last_os_error())
}

fn copy_request_to_socket(conn: &mut Conn) -> i32 {
    let mut stdin = io::stdin().lock();
    let mut buf = vec![0u8; COPY_BUFFER_SIZE];
    loop {
        let n = match stdin.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => n,
            Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(_) => return -1,
        };
        let mut off = 0usize;
        while off < n {
            match conn.write(&buf[off..n]) {
                Ok(0) => return -1,
                Ok(w) => off += w,
                Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(_) => return -1,
            }
        }
    }
    0
}

fn write_plain_stdout_exact<W: Write>(w: &mut W, parts: &[&[u8]]) -> io::Result<()> {
    // Plain-response replay uses C write_all(), not the EPIPE-tolerant body
    // writer. Any stdout error makes response_result fail and final rc=5.
    for part in parts {
        let mut off = 0usize;
        while off < part.len() {
            match w.write(&part[off..]) {
                Ok(0) => return Err(io::Error::new(ErrorKind::WriteZero, "write zero")),
                Ok(n) => off += n,
                Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
                Err(e) => return Err(e),
            }
        }
    }
    Ok(())
}

// Shared framing implementation for streaming stdin and bounded argv calls.
// Keep response length/chunk validation and consumer-close handling identical.
fn relay_response(conn: Conn, header_file: Option<String>, allow_plain_response: bool) -> (i32, bool) {
    let mut reader = BufReader::with_capacity(COPY_BUFFER_SIZE, conn);
    let mut stdout = io::stdout().lock();
    let mut response_result = 0i32;
    let mut consumer_closed = false;
    let mut body_mode: i64 = -1;

    if let Some(hf) = header_file.as_ref() {
        match read_header_line(&mut reader) {
            Err(e) => {
                eprintln!("unixsock: invalid or incomplete response header: {}", describe_err(&e));
                response_result = -1;
            }
            Ok(line1) => match read_header_line(&mut reader) {
                Err(e) if allow_plain_response && is_protocol_eof(&e) => {
                    if let Err(werr) = write_response_header_file(hf, &line1, b"-1\n") {
                        eprintln!("unixsock: cannot write header file {}: {}", hf, c_strerror(&werr));
                        response_result = -1;
                    } else {
                        body_mode = -1;
                        if write_plain_stdout_exact(&mut stdout, &[&line1, b"\n"]).is_err() { response_result = -1; }
                    }
                }
                Err(e) => {
                    eprintln!("unixsock: invalid or incomplete response header: {}", describe_err(&e));
                    response_result = -1;
                }
                Ok(line2) => match parse_body_mode_bytes(&line2) {
                    Some(v) => {
                        body_mode = v;
                        if let Err(werr) = write_response_header_file(hf, &line1, &line2) {
                            eprintln!("unixsock: cannot write header file {}: {}", hf, c_strerror(&werr));
                            response_result = -1;
                        }
                    }
                    None if allow_plain_response => {
                        if let Err(werr) = write_response_header_file(hf, &line1, b"-1\n") {
                            eprintln!("unixsock: cannot write header file {}: {}", hf, c_strerror(&werr));
                            response_result = -1;
                        } else {
                            body_mode = -1;
                            if write_plain_stdout_exact(&mut stdout, &[&line1, b"\n", &line2, b"\n"]).is_err() { response_result = -1; }
                        }
                    }
                    None => {
                        eprintln!("unixsock: invalid response body mode: {}", c_visible_string(&line2));
                        response_result = -1;
                    }
                },
            },
        }
    }

    if response_result == 0 {
        let copy_result = if header_file.is_none() || body_mode == -1 {
            copy_fd_to_stdout(&mut reader, &mut stdout, &mut consumer_closed)
        } else if body_mode == -2 {
            relay_daemon_chunks(&mut reader, &mut stdout, &mut consumer_closed)
        } else {
            copy_exact_response(&mut reader, &mut stdout, body_mode as u64, &mut consumer_closed)
        };
        if consumer_closed {
            let _ = reader.get_ref().shutdown(Shutdown::Both);
        } else if let Err(e) = copy_result {
            eprintln!("unixsock: response copy failed: {}", describe_err(&e));
            response_result = -1;
        }
    }

    drop(reader);
    (response_result, consumer_closed)
}

const ROOT_BODY_MAX: u64 = 64 * 1024 * 1024;
const ROOT_CAPABILITIES: &str = "unixsock.root_request_framing.v1 unixsock.root_request_snapshot.v1";

fn root_request_header(namespace: &str, command: &str, size: u64, appstate: Option<(&str, &str)>) -> Result<Vec<u8>, i32> {
    if command.is_empty() || command.contains(['\n', '\r', '\0']) || size > ROOT_BODY_MAX {
        return Err(2);
    }
    match (namespace, appstate) {
        ("hiddenapi" | "notify" | "notification", None) =>
            Ok(format!("{}\n{}\n1\n{}\n", namespace, command, size).into_bytes()),
        ("appstate", Some((user, extra))) if user.parse::<i32>().is_ok_and(|id| id >= 0)
            && !extra.contains(['\n', '\r', '\0']) =>
            Ok(format!("appstate\n{}\n{}\nndjson\n{}\n1\n{}\n", command, user, extra, size).into_bytes()),
        _ => Err(2),
    }
}

fn root_args_request(namespace: &str, command: &str, args: &[String]) -> Result<Vec<u8>, i32> {
    let size = args.iter().try_fold(0u64, |total, arg| {
        total.checked_add(arg.len() as u64)?.checked_add(1)
    }).ok_or(2)?;
    let mut request = root_request_header(namespace, command, size, None)?;
    for arg in args {
        request.extend_from_slice(arg.as_bytes());
        request.push(b'\n');
    }
    Ok(request)
}

// RootDaemon reads a bounded, complete request before producing its reply.
// Build the request here instead of a shell body file, cat pipeline and writer fork.
fn root_request_connection(mut conn: Conn, parts: &[&[u8]], header_file: String) -> i32 {
    unsafe { signal(SIGPIPE, SIG_IGN); }
    for part in parts {
        if let Err(e) = conn.write_all(part) {
            eprintln!("unixsock: request copy failed: {}", describe_err(&e));
            return 4;
        }
    }
    finish_root_request(conn, header_file)
}

fn prepare_root_file(namespace: &str, command: &str, body_path: &str, appstate: Option<(&str, &str)>) -> Result<(Vec<u8>, Vec<u8>), i32> {
    // Every failure here is local (rc=2), before any daemon connection. The
    // request becomes immutable before sending, so appending to its source
    // cannot report a transport failure after a complete request was accepted.
    root_request_header(namespace, command, 0, appstate)?;
    // O_NONBLOCK also lets us reject a FIFO without waiting for a writer.
    let mut body = std::fs::OpenOptions::new().read(true).custom_flags(O_NONBLOCK)
        .open(body_path).map_err(|_| 2)?;
    let meta = body.metadata().map_err(|_| 2)?;
    if !meta.is_file() { return Err(2); }
    let size = meta.len();
    if size > ROOT_BODY_MAX { return Err(2); }
    let mut snapshot = Vec::new();
    // Reserve the extra byte explicitly: reading a full-sized valid request
    // must not double a 64 MiB allocation just to check for unexpected growth.
    snapshot.try_reserve_exact((size + 1) as usize).map_err(|_| 2)?;
    (&mut body).take(size + 1).read_to_end(&mut snapshot).map_err(|_| 2)?;
    let after = body.metadata().map_err(|_| 2)?;
    if snapshot.len() as u64 != size || after.len() != size || meta.modified().ok() != after.modified().ok() {
        return Err(2);
    }
    let header = root_request_header(namespace, command, snapshot.len() as u64, appstate)?;
    Ok((snapshot, header))
}

fn finish_root_request(conn: Conn, header_file: String) -> i32 {
    if let Err(e) = conn.shutdown(Shutdown::Write) {
        if !matches!(e.raw_os_error(), Some(107) | Some(32)) {
            eprintln!("unixsock: request shutdown failed: {}", describe_err(&e));
            return 4;
        }
    }
    let (response_result, _) = relay_response(conn, Some(header_file), false);
    if response_result == 0 { 0 } else { 5 }
}

/// C relay_connection() parity: SIGPIPE ignored, a real fork() writer child,
/// parent-only response handling, close-before-waitpid, and the same rc tree.
fn relay_connection(mut conn: Conn, header_file: Option<String>, allow_plain_response: bool) -> i32 {
    unsafe { signal(SIGPIPE, SIG_IGN); }
    let writer_pid = unsafe { fork() };
    if writer_pid < 0 {
        eprintln!("unixsock: fork: {}", c_strerror(&io::Error::last_os_error()));
        return 4;
    }
    if writer_pid == 0 {
        let mut result = copy_request_to_socket(&mut conn);
        if let Err(e) = conn.shutdown(Shutdown::Write) {
            let er = e.raw_os_error().unwrap_or(0);
            if er != 107 && er != 32 { result = -1; } // ENOTCONN / EPIPE tolerated
        }
        drop(conn);
        unsafe { _exit(if result == 0 { 0 } else { 4 }) }
    }

    let (response_result, consumer_closed) = relay_response(conn, header_file, allow_plain_response);
    let mut writer_status = 0i32;
    loop {
        let wr = unsafe { waitpid(writer_pid, &mut writer_status, 0) };
        if wr >= 0 { break; }
        if io::Error::last_os_error().raw_os_error() == Some(EINTR) { continue; }
        writer_status = -1;
        break;
    }

    if response_result != 0 { return 5; }
    if consumer_closed { return 0; }
    let exited_ok = writer_status != -1 && (writer_status & 0x7f) == 0 && ((writer_status >> 8) & 0xff) == 0;
    if !exited_ok {
        eprintln!("unixsock: request copy failed");
        return 4;
    }
    0
}

fn describe_err(e: &io::Error) -> String {
    if is_protocol_eof(e) { "Protocol error".to_string() } else { c_strerror(e) }
}

pub(crate) fn run() {
    let args: Vec<String> = match crate::multicall::args_os().map(|s| s.into_string()).collect() {
        Ok(args) => args,
        Err(_) => {
            eprintln!("unixsock: non-UTF-8 argument rejected before connecting");
            std::process::exit(2);
        }
    };
    if args.len() == 2 && (args[1] == "--version" || args[1] == "version") {
        println!("{}", VERSION);
        return;
    }
    if args.len() == 2 && matches!(args[1].as_str(), "capabilities" | "--capabilities") {
        println!("{}", ROOT_CAPABILITIES);
        return;
    }
    if args.len() < 3 {
        usage();
        std::process::exit(2);
    }

    let rc = if args[1] == "root-file-unix" {
        let shape_ok = (args.len() == 7 && args[3] != "appstate")
            || (args.len() == 9 && args[3] == "appstate");
        if !shape_ok || args[5].is_empty() {
            usage();
            2
        } else {
            let appstate = if args[3] == "appstate" { Some((args[7].as_str(), args[8].as_str())) } else { None };
            match prepare_root_file(&args[3], &args[4], &args[6], appstate) {
                Err(rc) => { eprintln!("unixsock: invalid or unreadable root request body (rc={})", rc); rc },
                Ok((body, header)) => match connect_unix_socket(&args[2]) {
                    Ok(s) => root_request_connection(Conn::Unix(s), &[&header, &body], args[5].clone()),
                    Err(e) => {
                        eprintln!("unixsock: connect failed: {}", c_strerror(&e));
                        3
                    },
                },
            }
        }
    } else if args[1] == "root-args-unix" {
        if args.len() < 6 || args[5].is_empty() {
            usage();
            2
        } else {
            match root_args_request(&args[3], &args[4], &args[6..]) {
                Err(rc) => rc,
                Ok(request) => match connect_unix_socket(&args[2]) {
                    Ok(s) => root_request_connection(Conn::Unix(s), &[&request], args[5].clone()),
                    Err(e) => {
                        eprintln!("unixsock: connect failed: {}", c_strerror(&e));
                        3
                    }
                },
            }
        }
    } else if args[1] == "relay-unix" || args[1] == "relay" {
        match parse_relay_args(&args, 3) {
            Err(rc) => {
                usage();
                rc
            }
            Ok((hf, allow)) => match connect_unix_socket(&args[2]) {
                Ok(s) => relay_connection(Conn::Unix(s), hf, allow),
                Err(e) => {
                    eprintln!("unixsock: connect failed: {}", c_strerror(&e));
                    3
                }
            },
        }
    } else if args[1] == "relay-tcp" {
        if args.len() < 4 {
            usage();
            2
        } else {
            match parse_relay_args(&args, 4) {
                Err(rc) => {
                    usage();
                    rc
                }
                Ok((hf, allow)) => match connect_tcp_socket(&args[2], &args[3]) {
                    Ok(s) => relay_connection(Conn::Tcp(s), hf, allow),
                    Err(e) => {
                        eprintln!("unixsock: connect failed: {}", c_strerror(&e));
                        3
                    }
                },
            }
        }
    } else {
        usage();
        2
    };
    std::process::exit(rc);
}

#[cfg(test)]
mod root_args_tests {
    use super::*;
    use std::os::unix::net::UnixListener;
    use std::process::{Command, Stdio};
    use std::sync::atomic::{AtomicUsize, Ordering};
    static SEQ: AtomicUsize = AtomicUsize::new(0);
    #[test]
    fn byte_framing_matches_shell_printf() {
        let args = vec!["0".into(), "中文😀".into(), "".into(), "line\nline\t".into()];
        let body = "0\n中文😀\n\nline\nline\t\n";
        let expected = format!("hiddenapi\nprobe\n1\n{}\n{}", body.len(), body);
        assert_eq!(root_args_request("hiddenapi", "probe", &args).unwrap(), expected.as_bytes());
        assert_eq!(root_args_request("notify", "status", &[]).unwrap(), b"notify\nstatus\n1\n0\n");
    }
    #[test]
    fn reject_control_headers() {
        assert!(root_args_request("hiddenapi\nnotify", "probe", &[]).is_err());
        assert!(root_args_request("hiddenapi", "probe\n1", &[]).is_err());
        assert!(root_args_request("appstate", "probe", &[]).is_err());
        assert!(root_request_header("hiddenapi", "", 0, None).is_err());
        assert!(root_request_header("hiddenapi", "probe", ROOT_BODY_MAX + 1, None).is_err());
        assert!(root_request_header("appstate", "probe", 0, Some(("0\n", ""))).is_err());
        assert!(root_request_header("appstate", "probe", 0, Some(("-1", ""))).is_err());
        assert!(root_request_header("appstate", "probe", 0, Some(("2147483648", ""))).is_err());
        assert!(root_request_header("appstate", "probe", 0, Some(("0", "a\rb"))).is_err());
        assert_eq!(root_request_header("appstate", "probe", 3, Some(("0", "中文"))).unwrap(),
                   "appstate\nprobe\n0\nndjson\n中文\n1\n3\n".as_bytes());
    }

    #[test]
    fn file_validation_precedes_connect() {
        let binary = match std::env::var("SPEEDBACKUP_TEST_NATIVE") { Ok(p) => p, Err(_) => return };
        let root = std::env::var("SPEEDBACKUP_TEST_DIR").unwrap();
        let prefix = format!("{}/validation_{}", root, std::process::id());
        let huge = format!("{prefix}.huge");
        let fifo = format!("{prefix}.fifo");
        std::fs::File::create(&huge).unwrap().set_len(ROOT_BODY_MAX + 1).unwrap();
        assert!(Command::new("/system/bin/mkfifo").arg(&fifo).status().unwrap().success());
        for (path, rc) in [(&huge, 2), (&fifo, 2), (&root, 2), (&prefix, 2)] {
            let out = Command::new(&binary).args(["unixsock", "root-file-unix", "/no/socket", "notify", "probe", "/no/header", path]).output().unwrap();
            assert_eq!(out.status.code(), Some(rc), "{path}");
        }
        for (namespace, command, rc) in [("unknown", "probe", 2), ("hiddenapi", "bad\ncommand", 2), ("hiddenapi", "probe", 3)] {
            let out = Command::new(&binary).args(["unixsock", "root-args-unix", "/no/socket", namespace, command, "/no/header"]).output().unwrap();
            assert_eq!(out.status.code(), Some(rc));
        }
        std::fs::remove_file(huge).unwrap();
        std::fs::remove_file(fifo).unwrap();
    }

    #[test]
    fn invalid_utf8_is_a_local_rejection() {
        use std::os::unix::ffi::OsStringExt;
        let binary = match std::env::var("SPEEDBACKUP_TEST_NATIVE") { Ok(p) => p, Err(_) => return };
        let bad = std::ffi::OsString::from_vec(vec![0xff, 0xfe]);
        let output = Command::new(&binary).args(["unixsock", "root-args-unix", "/no/socket", "notify", "probe", "/no/header"])
            .arg(&bad).output().unwrap();
        assert_eq!(output.status.code(), Some(2));
        assert!(output.stdout.is_empty());
        assert!(!String::from_utf8_lossy(&output.stderr).contains("panicked"));
        if let Ok(old) = std::env::var("SPEEDBACKUP_TEST_OLD_NATIVE") {
            let output = Command::new(old).args(["unixsock", "root-args-unix", "/no/socket", "notify", "probe", "/no/header"])
                .arg(bad).output().unwrap();
            assert!(!output.status.success());
            assert!(String::from_utf8_lossy(&output.stderr).contains("non-UTF-8 argument"));
            println!("old non-UTF8 status={:?}; new rejects with rc=2", output.status);
        }
    }

    #[test]
    fn snapshot_survives_source_changes_after_connect() {
        let binary = match std::env::var("SPEEDBACKUP_TEST_NATIVE") { Ok(p) => p, Err(_) => return };
        let root = std::env::var("SPEEDBACKUP_TEST_DIR").unwrap();
        let mut versions = vec![(binary, false)];
        if let Ok(old) = std::env::var("SPEEDBACKUP_TEST_OLD_NATIVE") { versions.push((old, true)); }
        for (binary, is_old) in versions {
            for truncate in [false, true] {
                let seq = SEQ.fetch_add(1, Ordering::Relaxed);
                let prefix = format!("{}/mut_{}_{}", root, std::process::id(), seq);
                let path = format!("{prefix}.body");
                let socket = format!("{prefix}.sock");
                let header = format!("{prefix}.header");
                // Exceeds a Unix socket send buffer, so the old file path
                // cannot finish copying before the server mutates the file.
                let body = vec![0x5au8; 8 * 1024 * 1024];
                std::fs::write(&path, &body).unwrap();
                let mut expected = root_request_header("notify", "probe", body.len() as u64, None).unwrap();
                expected.extend_from_slice(&body);
                let listener = UnixListener::bind(&socket).unwrap();
                let changed_path = path.clone();
                let server = std::thread::spawn(move || {
                    let (mut conn, _) = listener.accept().unwrap();
                    conn.set_read_timeout(Some(std::time::Duration::from_secs(20))).unwrap();
                    // accept() is the synchronization point: prepare_root_file
                    // has returned, and this runs before draining the socket.
                    if truncate {
                        std::fs::OpenOptions::new().write(true).open(&changed_path).unwrap().set_len(1).unwrap();
                    } else {
                        std::fs::OpenOptions::new().append(true).open(&changed_path).unwrap().write_all(b"appended").unwrap();
                    }
                    let mut request = Vec::new();
                    conn.read_to_end(&mut request).unwrap();
                    let _ = conn.write_all(b"RESULT 0 OK\n2\nok");
                    request
                });
                let output = Command::new(&binary).args(["unixsock", "root-file-unix", &socket, "notify", "probe", &header, &path])
                    .output().unwrap();
                let received = server.join().unwrap();
                println!("source mutation old={} truncate={} rc={:?} received={} full={}", is_old, truncate, output.status.code(), received.len(), expected.len());
                if is_old {
                    assert_eq!(output.status.code(), Some(4));
                    if !truncate { assert_eq!(received, expected, "old failure after complete delivery"); }
                } else {
                    assert!(output.status.success(), "{:?}", output.stderr);
                    assert_eq!(received, expected);
                    assert_eq!(output.stdout, b"ok");
                }
                std::fs::remove_file(path).unwrap();
                std::fs::remove_file(socket).unwrap();
                let _ = std::fs::remove_file(header);
            }
        }
    }

    #[test]
    fn resolver_error_preserves_gai_reason() {
        let err = connect_tcp_socket("127.0.0.1", "speedbackup-nonexistent-service").unwrap_err();
        let message = c_strerror(&err);
        assert!(message.contains("getaddrinfo:"), "{message}");
        assert!(message.contains("EAI"), "{message}");
        assert!(err.raw_os_error().is_none());
    }

    #[test]
    fn large_binary_file_and_appstate_frame() {
        let binary = match std::env::var("SPEEDBACKUP_TEST_NATIVE") { Ok(p) => p, Err(_) => return };
        let root = std::env::var("SPEEDBACKUP_TEST_DIR").unwrap();
        let body: Vec<u8> = (0..2 * 1024 * 1024).map(|i| (i % 256) as u8).collect();
        for namespace in ["notify", "appstate"] {
            let prefix = format!("{}/large_{}_{}", root, std::process::id(), namespace);
            let path = format!("{prefix}.body");
            let socket = format!("{prefix}.sock");
            let header = format!("{prefix}.header");
            std::fs::write(&path, &body).unwrap();
            let listener = UnixListener::bind(&socket).unwrap();
            let mut expected = root_request_header(namespace, "probe", body.len() as u64,
                if namespace == "appstate" { Some(("10", "中文/extra")) } else { None }).unwrap();
            expected.extend_from_slice(&body);
            let server = std::thread::spawn(move || {
                let (mut connection, _) = listener.accept().unwrap();
                connection.set_read_timeout(Some(std::time::Duration::from_secs(10))).unwrap();
                let mut request = Vec::new();
                connection.read_to_end(&mut request).unwrap();
                assert_eq!(request, expected);
                connection.write_all(b"RESULT 0 OK\n2\nok").unwrap();
            });
            let mut command = Command::new(&binary);
            command.args(["unixsock", "root-file-unix", &socket, namespace, "probe", &header, &path]);
            if namespace == "appstate" { command.args(["10", "中文/extra"]); }
            let output = command.output().unwrap();
            server.join().unwrap();
            assert!(output.status.success(), "{:?}", output.stderr);
            assert_eq!(output.stdout, b"ok");
            assert_eq!(std::fs::read(&header).unwrap(), b"RESULT 0 OK\n2\n");
            for p in [&path, &socket, &header] { std::fs::remove_file(p).unwrap(); }
        }
    }

    #[test]
    fn tcp_numeric_hostname_ipv6_and_refusal() {
        // Exercise libc's actual sockaddr output, rather than a copied layout.
        for (listen, host) in [("127.0.0.1:0", "127.0.0.1"),
                               ("127.0.0.1:0", "localhost"), ("[::1]:0", "::1")] {
            let listener = std::net::TcpListener::bind(listen).unwrap();
            let port = listener.local_addr().unwrap().port().to_string();
            let mut client = connect_tcp_socket(host, &port).unwrap();
            let (mut server, _) = listener.accept().unwrap();
            let timeout = Some(std::time::Duration::from_secs(3));
            client.set_read_timeout(timeout).unwrap();
            server.set_read_timeout(timeout).unwrap();
            client.write_all(b"request\0\xff").unwrap();
            client.shutdown(std::net::Shutdown::Write).unwrap();
            let mut request = Vec::new();
            server.read_to_end(&mut request).unwrap();
            assert_eq!(request, b"request\0\xff");
            server.write_all(b"response\0\xff").unwrap();
            drop(server);
            let mut response = Vec::new();
            client.read_to_end(&mut response).unwrap();
            assert_eq!(response, b"response\0\xff");
            drop(listener);
            assert_eq!(connect_tcp_socket(host, &port).unwrap_err().kind(), ErrorKind::ConnectionRefused);
        }
    }

    // End-to-end: run both CLI paths against the same fragmented fake daemon.
    // The environment is set only by the isolated Android test runner.
    #[test]
    fn real_socket_framing_and_failures() {
        let binary = match std::env::var("SPEEDBACKUP_TEST_NATIVE") { Ok(p) => p, Err(_) => return };
        let root = std::env::var("SPEEDBACKUP_TEST_DIR").unwrap();
        let args = vec!["0".into(), "中文😀".into(), "".into(), "line\nline\t".into()];
        let request = root_args_request("hiddenapi", "probe", &args).unwrap();
        let cases: Vec<(&str, Vec<u8>, bool)> = vec![
            ("exact", b"RESULT 0 OK\n5\na\0b\nc".to_vec(), true),
            ("empty", b"RESULT 0 OK\n0\n".to_vec(), true),
            ("app-error", b"RESULT 70 ERROR\n4\nfail".to_vec(), true),
            ("raw", b"RESULT 0 OK\n-1\nraw\0bytes".to_vec(), true),
            ("chunks", b"RESULT 0 OK\n-2\n3\r\na\0b\r\n2\r\ncd\r\n0\r\n\r\n".to_vec(), true),
            ("no-header", Vec::new(), false),
            ("short-header", b"RESULT 0 OK".to_vec(), false),
            ("bad-size", b"RESULT 0 OK\nnope\n".to_vec(), false),
            ("bad-negative", b"RESULT 0 OK\n-3\n".to_vec(), false),
            ("short-exact", b"RESULT 0 OK\n10\nshort".to_vec(), false),
            ("short-chunk", b"RESULT 0 OK\n-2\n10\nshort".to_vec(), false),
            ("no-chunk-end", b"RESULT 0 OK\n-2\n3\nabc".to_vec(), false),
            ("bad-chunk", b"RESULT 0 OK\n-2\nbad\n".to_vec(), false),
        ];
        for (name, response, success) in cases {
            let mut prior: Option<(i32, Vec<u8>, Vec<u8>)> = None;
            for route in ["relay", "args", "file"] {
                let seq = SEQ.fetch_add(1, Ordering::Relaxed);
                let socket = format!("{}/s_{}_{}", root, std::process::id(), seq);
                let header = format!("{}/h_{}_{}", root, std::process::id(), seq);
                let listener = UnixListener::bind(&socket).unwrap();
                let reply = response.clone();
                let wanted = request.clone();
                let server = std::thread::spawn(move || {
                    let (mut connection, _) = listener.accept().unwrap();
                    let mut got = Vec::new();
                    connection.read_to_end(&mut got).unwrap();
                    assert_eq!(got, wanted, "request bytes");
                    for piece in reply.chunks(3) {
                        if connection.write_all(piece).is_err() { break; }
                    }
                });
                let mut command = Command::new(&binary);
                command.arg("unixsock");
                let body_path = format!("{}/b_{}_{}", root, std::process::id(), seq);
                if route == "args" {
                    command.args(["root-args-unix", &socket, "hiddenapi", "probe", &header]).args(&args);
                } else if route == "file" {
                    std::fs::write(&body_path, "0\n中文😀\n\nline\nline\t\n").unwrap();
                    command.args(["root-file-unix", &socket, "hiddenapi", "probe", &header, &body_path]);
                } else {
                    command.args(["relay-unix", &socket, "--header-file", &header]);
                }
                let mut child = command.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().unwrap();
                let mut stdin = child.stdin.take().unwrap();
                if route == "relay" { stdin.write_all(&request).unwrap(); }
                drop(stdin);
                let out = child.wait_with_output().unwrap();
                server.join().unwrap();
                let status = out.status.code().unwrap();
                assert_eq!(status == 0, success, "{name}, route={route}, stderr={:?}", out.stderr);
                let actual = (status, out.stdout, std::fs::read(&header).unwrap_or_default());
                if let Some(ref before) = prior { assert_eq!(&actual, before, "response parity: {name}"); }
                prior = Some(actual);
                std::fs::remove_file(&socket).unwrap();
                let _ = std::fs::remove_file(&header);
                let _ = std::fs::remove_file(&body_path);
            }
        }
        let output = Command::new(&binary).args(["unixsock", "root-args-unix", "/no/such/socket", "hiddenapi", "probe", "/no/header"]).output().unwrap();
        assert_eq!(output.status.code(), Some(3));
    }
}
