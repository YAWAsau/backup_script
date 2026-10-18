//! Root-only, per-run file-operation transport. Existing engines retain all gates.
//! A single-threaded broker forks one isolated mutation worker at a time.
use std::os::raw::{c_int, c_void};
use std::{
    fs::{self, OpenOptions},
    io::{self, Read, Write},
    os::fd::AsRawFd,
    os::unix::{
        fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};
const MAX: usize = 65536;
const OUTPUT: usize = 1048576;
const MAX_RECEIPTS: usize = 16384;
struct SocketCleanup {
    path: std::path::PathBuf,
    dev: u64,
    ino: u64,
}
impl Drop for SocketCleanup {
    fn drop(&mut self) {
        if fs::symlink_metadata(&self.path)
            .map(|m| m.dev() == self.dev && m.ino() == self.ino)
            .unwrap_or(false)
        {
            let _ = fs::remove_file(&self.path);
        }
    }
}
static STOP: AtomicBool = AtomicBool::new(false);
#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}
extern "C" {
    fn poll(fds: *mut PollFd, count: usize, timeout: c_int) -> c_int;
    fn geteuid() -> u32;
    fn getppid() -> c_int;
    fn getpgrp() -> c_int;
    fn fork() -> c_int;
    fn _exit(rc: c_int) -> !;
    fn close(fd: c_int) -> c_int;
    fn dup2(a: c_int, b: c_int) -> c_int;
    fn setpgid(p: c_int, g: c_int) -> c_int;
    fn kill(p: c_int, s: c_int) -> c_int;
    fn waitpid(p: c_int, status: *mut c_int, flags: c_int) -> c_int;
    fn signal(s: c_int, h: usize) -> usize;
    fn prctl(
        option: c_int,
        a: std::os::raw::c_ulong,
        b: std::os::raw::c_ulong,
        c: std::os::raw::c_ulong,
        d: std::os::raw::c_ulong,
    ) -> c_int;
    fn getsockopt(fd: c_int, level: c_int, opt: c_int, value: *mut c_void, len: *mut u32) -> c_int;
    fn recv(fd: c_int, b: *mut c_void, n: usize, flags: c_int) -> isize;
    fn flock(fd: c_int, op: c_int) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
}
extern "C" fn stop(_: c_int) {
    STOP.store(true, Ordering::Relaxed);
}
extern "C" fn parent_died(_: c_int) {
    unsafe {
        kill(-getpgrp(), 9);
        _exit(125);
    }
}
fn bad() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, "file RPC rejected")
}
fn starttime(pid: i32) -> io::Result<String> {
    let text = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    text.rsplit_once(") ")
        .and_then(|(_, tail)| tail.split_whitespace().nth(19))
        .map(str::to_owned)
        .ok_or_else(bad)
}
fn root_peer(s: &UnixStream) -> bool {
    #[repr(C)]
    struct Cred {
        pid: i32,
        uid: u32,
        gid: u32,
    }
    let mut c = Cred {
        pid: 0,
        uid: u32::MAX,
        gid: 0,
    };
    let mut n = std::mem::size_of::<Cred>() as u32;
    unsafe {
        getsockopt(
            s.as_raw_fd(),
            1,
            17,
            &mut c as *mut _ as *mut c_void,
            &mut n,
        ) == 0
            && n as usize == std::mem::size_of::<Cred>()
            && c.uid == 0
    }
}
fn peer_gone(s: &UnixStream) -> bool {
    let mut b = 0u8;
    let r = unsafe { recv(s.as_raw_fd(), &mut b as *mut _ as *mut c_void, 1, 2 | 0x40) };
    r == 0
        || (r < 0
            && !matches!(
                io::Error::last_os_error().raw_os_error(),
                Some(11) | Some(4)
            ))
}
fn id_ok(s: &str) -> bool {
    s.len() == 32 && s.bytes().all(|c| c.is_ascii_hexdigit())
}
fn read_frame(s: &mut UnixStream) -> io::Result<Vec<String>> {
    // One bounded read deadline covers the entire frame, not each byte.
    let deadline = Instant::now() + Duration::from_millis(500);
    fn exact(s: &mut UnixStream, b: &mut [u8], deadline: Instant) -> io::Result<()> {
        let mut pos = 0;
        while pos < b.len() {
            let left = deadline
                .checked_duration_since(Instant::now())
                .ok_or_else(bad)?;
            s.set_read_timeout(Some(left))?;
            let n = s.read(&mut b[pos..])?;
            if n == 0 {
                return Err(bad());
            }
            pos += n;
        }
        Ok(())
    }
    let mut n = [0u8; 4];
    exact(s, &mut n, deadline)?;
    let n = u32::from_be_bytes(n) as usize;
    if n == 0 || n > MAX {
        return Err(bad());
    }
    let mut body = vec![0; n];
    exact(s, &mut body, deadline)?;
    let mut fields = Vec::new();
    let mut pos = 0;
    while pos < body.len() {
        if fields.len() >= 12 || body.len() - pos < 4 {
            return Err(bad());
        }
        let n = u32::from_be_bytes(body[pos..pos + 4].try_into().unwrap()) as usize;
        pos += 4;
        if n > 8192 || n > body.len() - pos {
            return Err(bad());
        }
        let f = std::str::from_utf8(&body[pos..pos + n]).map_err(|_| bad())?;
        if f.contains('\0') {
            return Err(bad());
        }
        fields.push(f.to_owned());
        pos += n;
    }
    Ok(fields)
}
fn send(s: &mut UnixStream, id: &str, state: &str, rc: i32, body: &[u8]) -> io::Result<()> {
    writeln!(s, "SBFILE1 {id} {state} {rc} {}", body.len())?;
    s.write_all(body)?;
    s.flush()
}
fn permitted(args: &[String]) -> bool {
    let count = match args.first().map(String::as_str) {
        Some("internal-tree-clear") | Some("internal-tree-clear-quiet") => 5,
        Some("app-permissions") => 5,
        Some("restore-package-maps") => 5,
        Some("external-tree-check")
        | Some("external-tree-clear")
        | Some("external-policy-fused")
        | Some("external-policy-repair") => 4,
        Some("selinux-restore-external") => 2,
        Some("selinux-restore") => 3,
        _ => return false,
    };
    args.len() == count
}
fn mutation_lease() -> io::Result<std::fs::File> {
    let dir = Path::new("/data/.speedbackup-fileops");
    use std::os::unix::fs::DirBuilderExt;
    match fs::DirBuilder::new().mode(0o700).create(dir) {
        Ok(()) => (),
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => (),
        Err(e) => return Err(e),
    }
    let m = fs::symlink_metadata(dir)?;
    if !m.is_dir() || m.uid() != 0 || m.mode() & 0o777 != 0o700 || fs::canonicalize(dir)? != dir {
        return Err(bad());
    }
    let f = OpenOptions::new()
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(dir.join("mutation.lock"))?;
    let m = f.metadata()?;
    if !m.is_file()
        || m.uid() != 0
        || m.nlink() != 1
        || m.mode() & 0o777 != 0o600
        || unsafe { flock(f.as_raw_fd(), 2 | 4) } != 0
    {
        return Err(bad());
    }
    Ok(f)
}
fn zombie(pid: i32) -> bool {
    fs::read_to_string(format!("/proc/{pid}/stat"))
        .ok()
        .and_then(|v| v.rsplit_once(") ").map(|(_, s)| s.starts_with("Z ")))
        .unwrap_or(false)
}
fn run_worker(
    s: &mut UnixStream,
    listener: &UnixListener,
    args: &[String],
    owner: i32,
    owner_start: &str,
    ms: u64,
    close_fds: &[c_int],
) -> io::Result<(i32, Vec<u8>)> {
    // Descendants retain this lease through exec. A killed broker cannot allow a
    // replacement broker to overlap a worker still blocked in kernel I/O.
    let lease = mutation_lease()?;
    let (mut reader, writer) = UnixStream::pair()?;
    reader.set_nonblocking(true)?;
    let parent = std::process::id() as i32;
    let pid = unsafe { fork() };
    if pid < 0 {
        return Err(io::Error::last_os_error());
    }
    if pid == 0 {
        unsafe {
            if setpgid(0, 0) != 0 {
                _exit(125);
            }
            for sig in [2, 15, 13] {
                signal(sig, 0);
            }
            for fd in close_fds {
                close(*fd);
            }
            if fcntl(lease.as_raw_fd(), 2, 0) < 0 {
                _exit(125);
            }
            signal(10, parent_died as *const () as usize);
            if prctl(1, 10, 0, 0, 0) != 0 || getppid() != parent {
                parent_died(10);
            }
            close(listener.as_raw_fd());
            close(s.as_raw_fd());
            close(reader.as_raw_fd());
            if dup2(writer.as_raw_fd(), 1) < 0 || dup2(writer.as_raw_fd(), 2) < 0 {
                _exit(125);
            }
        }
        drop(writer);
        let rc = super::speedscan::file_rpc_dispatch(args);
        let _ = io::stdout().flush();
        let _ = io::stderr().flush();
        unsafe {
            _exit(rc & 255);
        }
    }
    drop(writer);
    // Close the fork/setpgid race before any cancellation can target the group.
    unsafe {
        setpgid(pid, pid);
    }
    let deadline = Instant::now() + Duration::from_millis(ms);
    let mut output = Vec::new();
    let mut status = 0;
    let mut cancelled = false;
    let mut eof = false;
    let mut reported = false;
    let mut zombie_pipe_since: Option<Instant> = None;
    loop {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => {
                    eof = true;
                    break;
                }
                Ok(n) => {
                    if output.len() + n > OUTPUT {
                        cancelled = true;
                        break;
                    }
                    output.extend_from_slice(&buf[..n]);
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    cancelled = true;
                    eof = true;
                    break;
                }
            }
        }
        // Keep the leader unreaped until the output pipe closes. Its PID pins the
        // process-group identity while descendants might still hold the pipe.
        if eof && !cancelled {
            let r = unsafe { waitpid(pid, &mut status, 1) };
            if r == pid {
                break;
            }
            if r < 0 && io::Error::last_os_error().raw_os_error() != Some(4) {
                return Ok((125, output));
            }
        }
        if STOP.load(Ordering::Relaxed)
            || Instant::now() >= deadline
            || peer_gone(s)
            || starttime(owner).ok().as_deref() != Some(owner_start)
        {
            cancelled = true;
        }
        if !eof && zombie(pid) {
            // Recheck the pipe after observing exit: it may have closed between the
            // earlier nonblocking read and /proc inspection during normal completion.
            let mut byte = 0u8;
            let n = unsafe {
                recv(
                    reader.as_raw_fd(),
                    &mut byte as *mut _ as *mut c_void,
                    1,
                    2 | 0x40,
                )
            };
            if n == 0 {
                eof = true;
                continue;
            }
            if n < 0 && io::Error::last_os_error().raw_os_error() == Some(11) {
                let since = zombie_pipe_since.get_or_insert_with(Instant::now);
                if since.elapsed() >= Duration::from_millis(50) {
                    cancelled = true;
                }
            }
        }
        if cancelled {
            unsafe {
                kill(-pid, 9);
                kill(pid, 9);
            }
            let cancel_start = Instant::now();
            loop {
                let r = unsafe { waitpid(pid, &mut status, 1) };
                if r == pid {
                    break;
                }
                if r < 0 && io::Error::last_os_error().raw_os_error() != Some(4) {
                    break;
                }
                if !reported && cancel_start.elapsed() >= Duration::from_secs(5) {
                    // Wake the client without claiming completion or accepting more work.
                    // Keep the lease and wait; SIGKILL cannot force D-state I/O to finish.
                    let _ = s.shutdown(std::net::Shutdown::Both);
                    reported = true;
                }
                std::thread::sleep(Duration::from_millis(10));
            }
            return Ok((125, output));
        }
        let mut events = [
            PollFd {
                fd: if eof { -1 } else { reader.as_raw_fd() },
                events: 1,
                revents: 0,
            },
            PollFd {
                fd: s.as_raw_fd(),
                events: 0x2000,
                revents: 0,
            },
        ];
        unsafe {
            poll(events.as_mut_ptr(), events.len(), 20);
        }
    }
    let rc = if status & 127 == 0 {
        (status >> 8) & 255
    } else {
        125
    };
    Ok((rc, output))
}
fn serve(socket: &Path, owner: i32, owner_start: &str) -> io::Result<()> {
    if unsafe { geteuid() } != 0 || owner <= 1 || starttime(owner)?.as_str() != owner_start {
        return Err(bad());
    }
    let dir = socket.parent().ok_or_else(bad)?;
    let meta = fs::symlink_metadata(dir)?;
    if !meta.is_dir()
        || meta.uid() != 0
        || meta.mode() & 0o777 != 0o700
        || fs::canonicalize(dir)? != dir
    {
        return Err(bad());
    }
    if socket.as_os_str().len() >= 104
        || socket.file_name().and_then(|s| s.to_str()) != Some("fileops.sock")
    {
        return Err(bad());
    }
    let lock = OpenOptions::new()
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(dir.join("fileops.lock"))?;
    if lock.metadata()?.nlink() != 1 || unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
        return Err(bad());
    }
    // Fail closed on any existing socket; the owner may choose a fresh run directory.
    if fs::symlink_metadata(socket).is_ok() {
        return Err(bad());
    }
    let listener = UnixListener::bind(socket)?;
    let bound = fs::symlink_metadata(socket)?;
    let _cleanup = SocketCleanup {
        path: socket.to_owned(),
        dev: bound.dev(),
        ino: bound.ino(),
    };
    fs::set_permissions(socket, fs::Permissions::from_mode(0o600))?;
    listener.set_nonblocking(true)?;
    let receipts = dir.join("fileops-receipts");
    if !receipts.exists() {
        fs::create_dir(&receipts)?;
        fs::set_permissions(&receipts, fs::Permissions::from_mode(0o700))?;
    }
    let rm = fs::symlink_metadata(&receipts)?;
    if !rm.is_dir() || rm.uid() != 0 || rm.mode() & 0o777 != 0o700 {
        return Err(bad());
    }
    unsafe {
        signal(15, stop as *const () as usize);
        signal(2, stop as *const () as usize);
        signal(13, 1);
    }
    let mut accepted = 0usize;
    while !STOP.load(Ordering::Relaxed) && starttime(owner).ok().as_deref() == Some(owner_start) {
        let (mut s, _) = match listener.accept() {
            Ok(v) => v,
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                // Wake immediately on an incoming request, without 500 /proc reads per idle second.
                let mut ready = PollFd {
                    fd: listener.as_raw_fd(),
                    events: 1,
                    revents: 0,
                };
                if unsafe { poll(&mut ready, 1, 100) } < 0
                    && io::Error::last_os_error().raw_os_error() != Some(4)
                {
                    return Err(io::Error::last_os_error());
                }
                continue;
            }
            Err(e) => return Err(e),
        };
        if !root_peer(&s) {
            continue;
        }
        s.set_write_timeout(Some(Duration::from_secs(2)))?;
        let fields = match read_frame(&mut s) {
            Ok(v) => v,
            Err(_) => continue,
        };
        if fields.len() < 2 || fields[0] != "SBFILE1" || !id_ok(&fields[1]) {
            continue;
        }
        let id = &fields[1];
        if fields.len() == 3 && fields[2] == "HELLO" {
            let _ = send(
                &mut s,
                id,
                "hello",
                0,
                speedbackup_native_rs::BUILD_VERSION.as_bytes(),
            );
            continue;
        }
        let receipt = receipts.join(id);
        if fields.len() == 3 && fields[2] == "STATUS" {
            let body = (|| -> io::Result<Vec<u8>> {
                let f = OpenOptions::new()
                    .read(true)
                    .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
                    .open(&receipt)?;
                let m = f.metadata()?;
                if !m.is_file() || m.uid() != 0 || m.nlink() != 1 || m.len() > 128 {
                    return Err(bad());
                }
                let mut b = Vec::new();
                f.take(128).read_to_end(&mut b)?;
                Ok(b)
            })()
            .unwrap_or_else(|_| b"unknown".to_vec());
            let _ = send(&mut s, id, "status", 0, &body);
            continue;
        }
        if fields.len() < 5 || fields[2] != "RUN" || !permitted(&fields[4..]) {
            let _ = send(&mut s, id, "rejected", 2, b"");
            continue;
        }
        let ms = match fields[3].parse::<u64>() {
            Ok(n) if (100..=600000).contains(&n) => n,
            _ => {
                let _ = send(&mut s, id, "rejected", 2, b"");
                continue;
            }
        };
        if accepted >= MAX_RECEIPTS {
            let _ = send(&mut s, id, "rejected", 125, b"request limit");
            continue;
        }
        let mut record = match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&receipt)
        {
            Ok(f) => f,
            Err(_) => {
                let _ = send(&mut s, id, "rejected", 125, b"duplicate request");
                continue;
            }
        };
        accepted += 1;
        record.write_all(b"accepted\n")?;
        record.sync_data()?;
        if send(&mut s, id, "accepted", 0, b"").is_err() {
            record.write_all(b"not-started\n")?;
            continue;
        }
        let (state, rc, body) = match run_worker(
            &mut s,
            &listener,
            &fields[4..],
            owner,
            owner_start,
            ms,
            &[lock.as_raw_fd(), record.as_raw_fd()],
        ) {
            Ok((rc, body)) => ("done", rc, body),
            Err(_) => ("not-started", 124, Vec::new()),
        };
        writeln!(record, "{state} {rc}")?;
        record.sync_data()?;
        let _ = send(&mut s, id, state, rc, &body);
    }
    Ok(())
}
pub fn command(args: &[String]) -> i32 {
    if args.len() != 3 {
        return 2;
    }
    let owner = match args[1].parse() {
        Ok(p) => p,
        Err(_) => return 2,
    };
    match serve(Path::new(&args[0]), owner, &args[2]) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("FILE_RPC_FAILED {e}");
            1
        }
    }
}
