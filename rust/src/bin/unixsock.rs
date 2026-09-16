// unixsock.rs - faithful Rust port of c/unixsock.c
// Relays stdin -> unix/tcp socket -> stdout, with optional two-line response
// header capture (exact-length / chunked / raw-until-EOF body framing).
// Every exit-code decision and the EPIPE-on-stdout "consumer closed early is
// not an error" behavior is reproduced exactly against c/unixsock.c.

use std::env;
use speedbackup_native_rs::c_strerror;
use std::ffi::{CStr, CString};
use std::io::{self, BufReader, ErrorKind, Read, Write};
use std::net::{Shutdown, TcpStream};
use std::os::fd::FromRawFd;
use std::os::unix::net::UnixStream;

const VERSION: &str = "unixsock 2.3.1-plain-lines-single-eof-api28-r28c-convergence-r572-rust-r572";
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
    ai_addr: *mut std::os::raw::c_void,
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
        "{}\nUsage:\n  unixsock relay-unix <socketPath> [--header-file <path>]\n  unixsock relay-tcp <host> <port> [--header-file <path>]\n\nstdin is copied to the socket. At stdin EOF the write side is half-closed,\nwhile the socket response continues to stdout. With --header-file, the first\ntwo newline-terminated response lines are written to that file and only the\nremaining binary body is written to stdout. The second header line may be\nan exact byte count, -1 (raw until EOF), or -2 (daemon chunk framing).\nWith --allow-plain-response and --header-file, a single-line plain\nresponse at EOF or a nonnumeric second response line is replayed to\nstdout and the header file receives the first line plus -1. Strict\nframed behavior is unchanged without --allow-plain-response.",
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
        eprintln!("unixsock: getaddrinfo: {}", msg);
        return Err(io::Error::last_os_error());
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

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() == 2 && (args[1] == "--version" || args[1] == "version") {
        println!("{}", VERSION);
        return;
    }
    if args.len() < 3 {
        usage();
        std::process::exit(2);
    }

    let rc = if args[1] == "relay-unix" || args[1] == "relay" {
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
