//! One optional-UI writer per shell. Only the private FIFO description is shared
//! with the producer; the terminal always has a separate nonblocking open.
use speedbackup_native_rs::{pidfd_open, poll, PollFd, O_CLOEXEC, O_NONBLOCK};
use std::collections::VecDeque;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::fs::{FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

const CAPACITY: usize = 1024 * 1024;
const IDLE: Duration = Duration::from_millis(250);
const COOLDOWN: Duration = Duration::from_secs(2);
const POLLIN: i16 = 1;
const POLLOUT: i16 = 4;
const POLLFAIL: i16 = 8 | 16 | 32;
static STOP: AtomicBool = AtomicBool::new(false);
extern "C" {
    fn fcntl(fd: i32, command: i32, argument: i32) -> i32;
    fn ioctl(fd: i32, request: std::os::raw::c_ulong, argument: *mut std::os::raw::c_void) -> i32;
    fn isatty(fd: i32) -> i32;
    fn signal(sig: i32, handler: usize) -> usize;
    fn socket(domain: i32, ty: i32, protocol: i32) -> i32;
    fn connect(fd: i32, address: *const std::os::raw::c_void, length: u32) -> i32;
    fn getsockopt(fd: i32, level: i32, name: i32, value: *mut std::os::raw::c_void, length: *mut u32) -> i32;
}
extern "C" fn stop_signal(_: i32) { STOP.store(true, Ordering::Relaxed); }

fn process_start(pid: i32) -> Option<u64> {
    let text = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let tail = text.rsplit_once(')')?.1;
    let mut fields = tail.split_whitespace();
    if matches!(fields.next()?, "Z" | "X") { return None; }
    fields.nth(18)?.parse().ok()
}
fn uptime_ms() -> u64 {
    fs::read_to_string("/proc/uptime").ok().and_then(|s| {
        let value = s.split_whitespace().next()?;
        let (seconds, fraction) = value.split_once('.')?;
        let fraction = format!("{fraction}000");
        Some(seconds.parse::<u64>().ok()?.saturating_mul(1000)
             .saturating_add(fraction[..3].parse::<u64>().ok()?))
    }).unwrap_or(0)
}
fn fifo_matches(fd: i32, path: &str) -> bool {
    let expected = match fs::symlink_metadata(path) { Ok(m) if m.file_type().is_fifo() => m, _ => return false };
    let actual = match fs::metadata(format!("/proc/self/fd/{fd}")) { Ok(m) => m, _ => return false };
    actual.file_type().is_fifo() && actual.dev() == expected.dev() && actual.ino() == expected.ino()
}
pub(super) fn configure_fd(fd: i32, fifo: &str) -> i32 {
    if fd < 3 || !fifo_matches(fd, fifo) { return 2; }
    let flags = unsafe { fcntl(fd, 3, 0) }; // F_GETFL
    if flags < 0 || flags & 3 != 2 { return 2; } // Only the shell's O_RDWR FIFO.
    // Absorb short producer bursts even before the relay is scheduled. Kernels
    // may cap/deny this request; the existing finite pipe remains valid then.
    // Total buffering stays bounded: <=1MiB requested here +1MiB userspace.
    unsafe { fcntl(fd, 1031, CAPACITY as i32); } // F_SETPIPE_SZ
    if unsafe { fcntl(fd, 4, flags | O_NONBLOCK) } < 0 { 125 } else { 0 }
}
fn wait_fd(fd: i32, events: i16, timeout: Duration) -> io::Result<()> {
    let mut p = PollFd { fd, events, revents: 0 };
    let ms = timeout.as_nanos().div_ceil(1_000_000).min(i32::MAX as u128) as i32;
    let rc = unsafe { poll(&mut p, 1, ms) };
    if rc < 0 { return Err(io::Error::last_os_error()); }
    if p.revents & POLLFAIL != 0 { return Err(io::ErrorKind::BrokenPipe.into()); }
    Ok(())
}

/// Large display batches pay one helper process. PIPE_BUF-size writes are
/// atomic; a live slow consumer renews the idle deadline on each successful write.
pub(super) fn feed(fd: i32, fifo: &str, idle_ms: u64) -> i32 {
    fn drain_fail(rc: i32) -> i32 { let _ = io::copy(&mut io::stdin().lock(), &mut io::sink()); rc }
    if fd < 3 || !fifo_matches(fd, fifo) { return drain_fail(2); }
    let flags = unsafe { fcntl(fd, 3, 0) };
    if flags < 0 || flags & 3 != 2 || flags & O_NONBLOCK == 0 { return drain_fail(2); }
    let copy = unsafe { fcntl(fd, 1030, 3) }; // F_DUPFD_CLOEXEC; same private description.
    if copy < 0 { return drain_fail(125); }
    let mut output = unsafe { File::from_raw_fd(copy) };
    let mut input = io::stdin().lock();
    let mut buffer = [0u8; 4096];
    let limit = Duration::from_millis(idle_ms.clamp(1, 60_000));
    let mut total = 0usize;
    let mut failed = false;
    loop {
        let n = match input.read(&mut buffer) {
            Ok(0) => break, Ok(n) => n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => { failed = true; break; },
        };
        let mut offset = 0;
        let mut last = Instant::now();
        while offset < n {
            match output.write(&buffer[offset..n]) {
                Ok(0) => { failed = true; break; },
                Ok(wrote) => { offset += wrote; total += wrote; last = Instant::now(); },
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {},
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                    let remaining = limit.saturating_sub(last.elapsed());
                    if remaining.is_zero() { failed = true; break; }
                    match wait_fd(copy, POLLOUT, remaining) {
                        Ok(()) => {},
                        Err(e) if e.kind() == io::ErrorKind::Interrupted => {},
                        Err(_) => { failed = true; break; },
                    }
                },
                Err(_) => { failed = true; break; },
            }
        }
        if failed { break; }
    }
    if failed {
        // Drain finite shell batch input so its producer is not killed by SIGPIPE.
        let _ = io::copy(&mut input, &mut io::sink());
        if total == 0 { 75 } else { 76 }
    } else { 0 }
}

fn open_terminal() -> io::Result<File> {
    let open = |path| OpenOptions::new().write(true).custom_flags(O_NONBLOCK | O_CLOEXEC | 0o400).open(path);
    let stdout = open("/proc/self/fd/1")?;
    let control = open("/dev/tty")?;
    let mut stdout_dev = 0u32;
    let mut control_dev = 0u32;
    // TIOCGDEV resolves /dev/tty's actual device instead of its special 5:0 inode.
    if unsafe { isatty(stdout.as_raw_fd()) } != 1
        || unsafe { isatty(control.as_raw_fd()) } != 1
        || unsafe { ioctl(stdout.as_raw_fd(), 0x80045432, &mut stdout_dev as *mut _ as *mut _) } != 0
        || unsafe { ioctl(control.as_raw_fd(), 0x80045432, &mut control_dev as *mut _ as *mut _) } != 0
        || stdout_dev != control_dev {
        return Err(io::ErrorKind::NotConnected.into());
    }
    Ok(stdout)
}

struct Stats {
    path: PathBuf, pid: u32, start: u64, events: u64, bytes: u64,
    cooldown: Option<Instant>, cooldown_uptime: u64, last_write: Instant,
}
impl Stats {
    fn record_drop(&mut self, count: usize, open_breaker: bool) {
        if open_breaker && self.cooldown.map(|t| Instant::now() >= t).unwrap_or(true) {
            self.events = self.events.saturating_add(1);
            self.cooldown = Some(Instant::now() + COOLDOWN);
            self.cooldown_uptime = uptime_ms().saturating_add(2000);
        }
        self.bytes = self.bytes.saturating_add(count as u64);
    }
    fn cooling(&self) -> bool { self.cooldown.map(|t| Instant::now() < t).unwrap_or(false) }
    fn publish(&mut self, state: &str, queued: usize) -> io::Result<()> {
        let tmp = self.path.with_extension(format!("relay-{}", self.pid));
        let text = format!("v1 {} {} {} {} {} {} {} {}\n", self.pid, self.start,
                           state, queued, self.events, self.bytes, self.cooldown_uptime, uptime_ms());
        let result = (|| {
            let mut file = OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
            file.write_all(text.as_bytes())?;
            fs::rename(&tmp, &self.path)
        })();
        if result.is_err() { let _ = fs::remove_file(&tmp); }
        self.last_write = Instant::now();
        result
    }
}
struct Connection { stream: UnixStream, input: Vec<u8>, opened: Instant }
struct Barrier { stream: UnixStream, op: String, deadline: Instant, drop_before: u64 }
fn respond(mut stream: UnixStream, dropped: bool, op: &str) {
    // Replies are tiny. A dead/stalled control client cannot hold the relay.
    let _ = stream.write(format!("{} {op}\n", if dropped { "DROP" } else { "OK" }).as_bytes());
}
fn remaining(deadline: Instant) -> io::Result<Duration> {
    let duration = deadline.saturating_duration_since(Instant::now());
    if duration.is_zero() { Err(io::ErrorKind::TimedOut.into()) } else { Ok(duration) }
}
fn connect_control(path: &str, deadline: Instant) -> io::Result<UnixStream> {
    #[repr(C)]
    struct Address { family: u16, path: [u8; 108] }
    if path.is_empty() || path.len() >= 108 || path.as_bytes().contains(&0) { return Err(io::ErrorKind::InvalidInput.into()); }
    let fd = unsafe { socket(1, 1 | O_CLOEXEC | O_NONBLOCK, 0) }; // AF_UNIX, SOCK_STREAM
    if fd < 0 { return Err(io::Error::last_os_error()); }
    let stream = unsafe { UnixStream::from_raw_fd(fd) };
    let mut address = Address { family: 1, path: [0; 108] };
    address.path[..path.len()].copy_from_slice(path.as_bytes());
    loop {
        remaining(deadline)?;
        if unsafe { connect(fd, &address as *const _ as *const _, (2 + path.len() + 1) as u32) } == 0 { return Ok(stream); }
        let error = io::Error::last_os_error();
        match error.raw_os_error() {
            Some(106) => return Ok(stream), // EISCONN after interrupted connect.
            Some(4) => continue, // EINTR
            Some(11) => { // AF_UNIX backlog full: the nonblocking attempt was not queued.
                std::thread::sleep(remaining(deadline)?.min(Duration::from_millis(10)));
            },
            Some(115) | Some(114) => { // EINPROGRESS / EALREADY
                wait_fd(fd, POLLOUT, remaining(deadline)?)?;
                let mut status = 0i32;
                let mut length = std::mem::size_of_val(&status) as u32;
                if unsafe { getsockopt(fd, 1, 4, &mut status as *mut _ as *mut _, &mut length) } != 0 { return Err(io::Error::last_os_error()); }
                if status == 0 { return Ok(stream); }
                if status != 115 && status != 114 { return Err(io::Error::from_raw_os_error(status)); }
            },
            _ => return Err(error),
        }
    }
}
pub(super) fn barrier(socket: &str, op: &str, timeout_ms: u64) -> i32 {
    if !matches!(op, "pause" | "resume" | "flush" | "stop") { return 2; }
    let timeout_ms = timeout_ms.clamp(1, 120_000);
    // Includes connect, write, fragmented reply reads, and backlog-full retry.
    let deadline = Instant::now() + Duration::from_millis(timeout_ms + 1500);
    let response = (|| -> io::Result<Vec<u8>> {
        let mut stream = connect_control(socket, deadline)?;
        let message = format!("{op} {timeout_ms}\n");
        let mut offset = 0;
        while offset < message.len() {
            remaining(deadline)?;
            match stream.write(&message.as_bytes()[offset..]) {
                Ok(0) => return Err(io::ErrorKind::WriteZero.into()),
                Ok(n) => offset += n,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {},
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => wait_fd(stream.as_raw_fd(), POLLOUT, remaining(deadline)?)?,
                Err(e) => return Err(e),
            }
        }
        let mut response = Vec::new();
        let mut buffer = [0u8; 64];
        loop {
            remaining(deadline)?;
            match stream.read(&mut buffer) {
                Ok(0) => return if response.is_empty() { Err(io::ErrorKind::UnexpectedEof.into()) } else { Ok(response) },
                Ok(n) => {
                    response.extend_from_slice(&buffer[..n]);
                    if response.len() > 64 { return Err(io::ErrorKind::InvalidData.into()); }
                    if response.contains(&b'\n') { return Ok(response); }
                },
                Err(e) if e.kind() == io::ErrorKind::Interrupted => {},
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                    // A peer may close with the response still queued. Poll HUP
                    // is not fatal here: retry read to consume the final bytes.
                    let mut p = PollFd { fd: stream.as_raw_fd(), events: POLLIN, revents: 0 };
                    let ms = remaining(deadline)?.as_nanos().div_ceil(1_000_000).min(i32::MAX as u128) as i32;
                    let rc = unsafe { poll(&mut p, 1, ms) };
                    if rc < 0 && io::Error::last_os_error().kind() != io::ErrorKind::Interrupted { return Err(io::Error::last_os_error()); }
                },
                Err(e) => return Err(e),
            }
        }
    })();
    match response {
        Ok(bytes) if bytes == format!("OK {op}\n").as_bytes() => 0,
        Ok(bytes) if bytes == format!("DROP {op}\n").as_bytes() => 75,
        Err(e) if e.kind() == io::ErrorKind::TimedOut => 124,
        _ => 125,
    }
}

fn discard_snapshot(fifo: &mut File, stats: &mut Stats) -> io::Result<()> {
    let mut available = 0i32;
    if unsafe { ioctl(fifo.as_raw_fd(), 0x541b, &mut available as *mut _ as *mut _) } != 0 { return Err(io::Error::last_os_error()); } // FIONREAD
    let mut buffer = [0u8; 16384];
    // Drain exactly the bytes present at the cutoff. A concurrent background
    // producer cannot extend this bounded operation indefinitely.
    while available > 0 {
        let take = (available as usize).min(buffer.len());
        match fifo.read(&mut buffer[..take]) {
            Ok(0) => return Err(io::ErrorKind::UnexpectedEof.into()),
            Ok(n) => { available -= n as i32; stats.record_drop(n, true); },
            Err(e) if e.kind() == io::ErrorKind::Interrupted => {},
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

fn finish_parent_output(fifo: &mut File, tty: &mut File, queue: &mut VecDeque<u8>, stats: &mut Stats, paused: bool) {
    // The parent may exit before its Shell EXIT trap has been installed. Take
    // one FIFO snapshot: descendants retaining a writer cannot prolong shutdown
    // or add new output behind the parent's final messages indefinitely.
    let deadline = Instant::now() + IDLE;
    let mut pending = 0i32;
    let measured = unsafe { ioctl(fifo.as_raw_fd(), 0x541b, &mut pending as *mut _ as *mut _) } == 0;
    let mut remaining = if measured { pending.max(0) as usize } else { 0 };
    let mut buffer = [0u8; 16384];
    // A pause protects an already-visible mandatory prompt. Parent death must
    // never implicitly resume optional output behind that prompt.
    while !paused && !stats.cooling() && Instant::now() < deadline {
        if remaining > 0 && queue.len() < CAPACITY {
            let take = remaining.min(buffer.len()).min(CAPACITY - queue.len());
            match fifo.read(&mut buffer[..take]) {
                Ok(0) => break,
                Ok(n) => { remaining -= n; queue.extend(&buffer[..n]); },
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        if queue.is_empty() { break; }
        let (head, _) = queue.as_slices();
        match tty.write(head) {
            Ok(0) => break,
            Ok(n) => { queue.drain(..n); },
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                if wait_fd(tty.as_raw_fd(), POLLOUT, deadline.saturating_duration_since(Instant::now())).is_err() { break; }
            },
            Err(_) => break,
        }
    }
    let dropped = queue.len().saturating_add(remaining);
    if dropped > 0 { stats.record_drop(dropped, true); }
    queue.clear();
}

pub(super) fn run(fifo_path: &str, socket_path: &str, stats_path: &str, parent: i32, parent_start: u64) -> i32 {
    if parent <= 0 || parent_start == 0 || process_start(parent) != Some(parent_start) { return 2; }
    if fifo_path == socket_path || fifo_path == stats_path || socket_path == stats_path { return 2; }
    let parent_dir = Path::new(fifo_path).parent();
    if parent_dir.is_none() || Path::new(socket_path).parent() != parent_dir || Path::new(stats_path).parent() != parent_dir { return 2; }
    let fifo_meta = match fs::symlink_metadata(fifo_path) { Ok(m) if m.file_type().is_fifo() => m, _ => return 2 };
    let mut fifo = match OpenOptions::new().read(true).custom_flags(O_NONBLOCK | O_CLOEXEC).open(fifo_path) { Ok(f) => f, Err(_) => return 125 };
    let opened = match fifo.metadata() { Ok(m) => m, Err(_) => return 125 };
    if opened.ino() != fifo_meta.ino() || opened.dev() != fifo_meta.dev() || !opened.file_type().is_fifo() { return 2; }
    let mut tty = match open_terminal() { Ok(f) => f, Err(_) => return 125 };
    let listener = match UnixListener::bind(socket_path) { Ok(s) => s, Err(_) => return 125 };
    if listener.set_nonblocking(true).is_err() { let _ = fs::remove_file(socket_path); return 125; }
    let _ = fs::set_permissions(socket_path, fs::Permissions::from_mode(0o600));
    let parent_fd = pidfd_open(parent).ok().map(|fd| unsafe { File::from_raw_fd(fd) });
    if process_start(parent) != Some(parent_start) { let _ = fs::remove_file(socket_path); return 2; }
    STOP.store(false, Ordering::Relaxed);
    for sig in [1, 2, 15] { unsafe { signal(sig, stop_signal as *const () as usize); } }
    let pid = std::process::id();
    let mut stats = Stats { path: stats_path.into(), pid, start: process_start(pid as i32).unwrap_or(0),
        events: 0, bytes: 0, cooldown: None, cooldown_uptime: 0, last_write: Instant::now() };
    if stats.publish("ready", 0).is_err() { let _ = fs::remove_file(socket_path); return 125; }
    let mut queue = VecDeque::with_capacity(CAPACITY);
    let mut paused = false;
    let mut clients: Vec<Connection> = Vec::new();
    let mut active: Option<Barrier> = None;
    let mut last_progress = Instant::now();
    let mut parent_check = Instant::now();
    let mut buffer = [0u8; 16384];
    let mut state_dirty = false;
    let mut stopping = false;
    loop {
        if STOP.load(Ordering::Relaxed) {
            // Session-leader exit may deliver SIGHUP before pidfd readiness.
            // All graceful termination paths must honor the same finite drain.
            finish_parent_output(&mut fifo, &mut tty, &mut queue, &mut stats, paused);
            break;
        }
        if parent_check.elapsed() >= Duration::from_secs(1) {
            if process_start(parent) != Some(parent_start) {
                finish_parent_output(&mut fifo, &mut tty, &mut queue, &mut stats, paused);
                break;
            }
            parent_check = Instant::now();
        }
        // Accept a bounded number of small control requests; no data markers are
        // ever mixed into the raw FIFO payload.
        while clients.len() < 4 {
            match listener.accept() {
                Ok((stream, _)) => {
                    if stream.set_nonblocking(true).is_ok() {
                        clients.push(Connection { stream, input: Vec::new(), opened: Instant::now() });
                    }
                },
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        let mut index = 0;
        while index < clients.len() {
            let mut remove = false;
            let mut request = None;
            let client = &mut clients[index];
            let mut input = [0u8; 64];
            match client.stream.read(&mut input) {
                Ok(0) => remove = true,
                Ok(n) => {
                    client.input.extend_from_slice(&input[..n]);
                    if client.input.len() > 64 { remove = true; }
                    else if client.input.contains(&b'\n') { request = Some(String::from_utf8_lossy(&client.input).into_owned()); }
                },
                Err(e) if matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted) => {},
                Err(_) => remove = true,
            }
            if client.opened.elapsed() > Duration::from_secs(2) { remove = true; }
            if let Some(request) = request {
                let client = clients.swap_remove(index);
                let mut words = request.split_whitespace();
                let op = words.next().unwrap_or("");
                let timeout = words.next().and_then(|n| n.parse::<u64>().ok()).unwrap_or(0);
                if timeout == 0 || timeout > 120_000 || words.next().is_some()
                    || !matches!(op, "pause" | "resume" | "flush" | "stop") { continue; }
                if active.is_some() { continue; }
                if op == "resume" {
                    paused = false;
                    last_progress = Instant::now();
                    // The caller may immediately issue another must output.
                    // Publishing before ACK prevents it seeing stale "paused"
                    // and skipping the next required pause barrier.
                    let state = if stats.cooling() { "breaker" } else { "ready" };
                    if stats.publish(state, queue.len()).is_err() { stopping = true; continue; }
                    state_dirty = false;
                    respond(client.stream, false, op);
                } else if paused && op == "pause" {
                    respond(client.stream, false, op);
                } else {
                    active = Some(Barrier { stream: client.stream, op: op.into(),
                        deadline: Instant::now() + Duration::from_millis(timeout), drop_before: stats.bytes });
                }
                continue;
            }
            if remove { clients.swap_remove(index); } else { index += 1; }
        }
        if stopping { break; }

        let cooling = stats.cooling();
        let forced_drop = active.as_ref().map(|b| Instant::now() >= b.deadline || (paused && b.op != "pause")).unwrap_or(false);
        if forced_drop && !queue.is_empty() {
            stats.record_drop(queue.len(), true); queue.clear(); state_dirty = true;
        }
        let discard = cooling || forced_drop;
        // Do not consume more than the bounded queue. Full queue backpressure is
        // handled by the producer's nonblocking FIFO (bulk helper waits safely).
        let mut fifo_empty = false;
        if forced_drop {
            if discard_snapshot(&mut fifo, &mut stats).is_err() { break; }
            fifo_empty = true;
            state_dirty = true;
        }
        for _ in 0..if forced_drop { 0 } else { 16 } {
            let available = if discard { buffer.len() } else { (CAPACITY - queue.len()).min(buffer.len()) };
            if available == 0 { break; }
            match fifo.read(&mut buffer[..available]) {
                Ok(0) => { fifo_empty = true; break; },
                Ok(n) => {
                    if discard { stats.record_drop(n, true); state_dirty = true; }
                    else {
                        if queue.is_empty() { last_progress = Instant::now(); }
                        queue.extend(&buffer[..n]);
                    }
                },
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => { fifo_empty = true; break; },
                Err(_) => { stopping = true; break; },
            }
        }
        if !paused && !stats.cooling() && !queue.is_empty() {
            let (head, _) = queue.as_slices();
            match tty.write(head) {
                Ok(n) if n > 0 => { queue.drain(..n); last_progress = Instant::now(); },
                Err(e) if matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted) => {},
                _ => { last_progress = Instant::now() - IDLE; },
            }
            if !queue.is_empty() && last_progress.elapsed() >= IDLE {
                stats.record_drop(queue.len(), true); queue.clear(); state_dirty = true;
            }
        }
        if active.is_some() && (fifo_empty || forced_drop) && queue.is_empty() {
            let barrier = active.take().unwrap();
            paused |= barrier.op == "pause";
            stopping |= barrier.op == "stop";
            // Publish the paused state before acknowledging: a second shell
            // writer must see the barrier before it is allowed to resume.
            let state = if stopping { "stopping" } else if paused { "paused" } else if stats.cooling() { "breaker" } else { "ready" };
            if stats.publish(state, queue.len()).is_err() { break; }
            state_dirty = false;
            respond(barrier.stream, stats.bytes != barrier.drop_before, &barrier.op);
        }
        if stopping { break; }
        if state_dirty || stats.last_write.elapsed() >= Duration::from_secs(1) {
            let state = if paused { "paused" } else if stats.cooling() { "breaker" } else { "ready" };
            if stats.publish(state, queue.len()).is_err() { break; }
            state_dirty = false;
        }
        let mut fds = vec![PollFd { fd: listener.as_raw_fd(), events: POLLIN, revents: 0 }];
        if queue.len() < CAPACITY || stats.cooling() { fds.push(PollFd { fd: fifo.as_raw_fd(), events: POLLIN, revents: 0 }); }
        if !paused && !stats.cooling() && !queue.is_empty() { fds.push(PollFd { fd: tty.as_raw_fd(), events: POLLOUT, revents: 0 }); }
        for client in &clients { fds.push(PollFd { fd: client.stream.as_raw_fd(), events: POLLIN, revents: 0 }); }
        let parent_index = parent_fd.as_ref().map(|fd| { let index = fds.len(); fds.push(PollFd { fd: fd.as_raw_fd(), events: POLLIN, revents: 0 }); index });
        let mut wait = Duration::from_millis(1000);
        if !paused && !queue.is_empty() { wait = wait.min(IDLE.saturating_sub(last_progress.elapsed())); }
        if let Some(b) = &active { wait = wait.min(b.deadline.saturating_duration_since(Instant::now())); }
        if stats.cooling() { wait = wait.min(stats.cooldown.unwrap().saturating_duration_since(Instant::now())); }
        let ms = wait.as_nanos().div_ceil(1_000_000).min(1000) as i32;
        unsafe { poll(fds.as_mut_ptr(), fds.len() as _, ms); }
        if parent_index.map(|i| fds[i].revents != 0).unwrap_or(false) {
            finish_parent_output(&mut fifo, &mut tty, &mut queue, &mut stats, paused);
            break;
        }
    }
    if !queue.is_empty() { stats.record_drop(queue.len(), true); }
    let _ = stats.publish("stopped", 0);
    let _ = fs::remove_file(socket_path);
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn proc_start_identity_is_available_and_positive() {
        assert!(process_start(std::process::id() as i32).unwrap() > 0);
        assert!(process_start(-1).is_none());
    }
    #[test] fn inherited_standard_descriptors_cannot_be_reconfigured() {
        for fd in [0, 1, 2, -1] { assert_eq!(configure_fd(fd, "/dev/null"), 2); }
    }
    #[test] fn relay_fifo_identity_rejects_non_fifo_targets() {
        assert!(!fifo_matches(1, "/dev/null"));
    }
}
