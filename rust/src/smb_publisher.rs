//! Per-run publisher connection. Uploads and producer-status gates stay in Shell.
//! A private FIFO feeds bounded commands to smbclient's opt-in framed mode.
use std::os::raw::{c_char, c_int, c_long};
use std::{
    ffi::CString,
    fs::{self, File, OpenOptions},
    io::{self, Read, Seek, SeekFrom, Write},
    os::{
        fd::{AsRawFd, FromRawFd},
        unix::{
            fs::{FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt},
            process::CommandExt,
        },
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{Duration, Instant},
};
const NOFOLLOW: i32 = speedbackup_native_rs::O_NOFOLLOW_NATIVE;
const NONBLOCK: i32 = 2048;
const MAX: usize = 1024 * 1024;
#[repr(C)]
struct PollFd {
    fd: c_int,
    events: i16,
    revents: i16,
}
extern "C" {
    fn syscall(n: c_long, ...) -> c_long;
    fn flock(fd: c_int, op: c_int) -> c_int;
    fn poll(p: *mut PollFd, n: usize, ms: c_int) -> c_int;
    fn mkfifo(p: *const c_char, mode: u32) -> c_int;
    fn dup2(a: c_int, b: c_int) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
    fn geteuid() -> u32;
    fn close(fd: c_int) -> c_int;
    fn inotify_init1(flags: c_int) -> c_int;
    fn inotify_add_watch(fd: c_int, p: *const c_char, mask: u32) -> c_int;
}
fn bad(s: &str) -> io::Error {
    io::Error::new(io::ErrorKind::Other, s)
}
fn start(pid: u32) -> io::Result<String> {
    speedbackup_native_rs::proc_stat::starttime(&fs::read_to_string(format!("/proc/{pid}/stat"))?)
        .map(str::to_owned)
        .ok_or_else(|| bad("process identity"))
}
fn pidfd(pid: u32, identity: &str) -> io::Result<File> {
    let fd = unsafe { syscall(434, pid, 0u32) } as i32;
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    let f = unsafe { File::from_raw_fd(fd) };
    if start(pid)? != identity {
        return Err(bad("process changed"));
    }
    Ok(f)
}
fn alive(s: &State) -> bool {
    pidfd(s.pid, &s.start)
        .map(|f| {
            let mut p = PollFd {
                fd: f.as_raw_fd(),
                events: 1,
                revents: 0,
            };
            unsafe { poll(&mut p, 1, 0) == 0 }
        })
        .unwrap_or(false)
}
fn kill(s: &State) {
    if let Ok(f) = pidfd(s.pid, &s.start) {
        unsafe {
            syscall(424, f.as_raw_fd(), 9i32, std::ptr::null::<u8>(), 0u32);
        }
    }
}
fn directory(p: &Path) -> io::Result<()> {
    let m = fs::symlink_metadata(p)?;
    if !m.is_dir() || m.uid() != 0 || m.mode() & 0o777 != 0o700 || fs::canonicalize(p)? != p {
        return Err(bad("private directory required"));
    }
    Ok(())
}
fn file(p: &Path, write: bool, create: bool) -> io::Result<File> {
    let f = OpenOptions::new()
        .read(true)
        .write(write)
        .create(create)
        .mode(0o600)
        .custom_flags(NOFOLLOW)
        .open(p)?;
    let m = f.metadata()?;
    if !m.is_file() || m.uid() != 0 || m.nlink() != 1 || m.mode() & 0o777 != 0o600 {
        return Err(bad("private file required"));
    }
    Ok(f)
}
fn save(p: &Path, b: &[u8]) -> io::Result<()> {
    let mut f = file(p, true, true)?;
    f.set_len(0)?;
    f.write_all(b)
}
fn read(p: &Path) -> io::Result<Vec<u8>> {
    let mut b = Vec::new();
    file(p, false, false)?
        .take((MAX + 1) as u64)
        .read_to_end(&mut b)?;
    if b.len() > MAX {
        return Err(bad("file limit"));
    }
    Ok(b)
}
fn registered_pid(d: &Path, pid: u32) -> bool {
    // Shell creates this non-secret PID marker using the caller's umask.
    // Its already-validated root-private parent prevents other readers; allow
    // 0644/0640 as well as 0600, but never a link or a non-root writable marker.
    let read_marker = || -> io::Result<Vec<u8>> {
        let f = OpenOptions::new().read(true).custom_flags(NOFOLLOW | NONBLOCK)
            .open(d.join("registered"))?;
        let m = f.metadata()?;
        if !m.is_file() || m.uid()!=0 || m.nlink()!=1 || m.mode() & 0o022 != 0 {
            return Err(bad("unsafe registration marker"));
        }
        let mut bytes=Vec::new();f.take((MAX+1) as u64).read_to_end(&mut bytes)?;
        if bytes.len()>MAX {return Err(bad("registration marker limit"));}
        Ok(bytes)
    };
    read_marker().is_ok_and(|bytes| bytes.split(|b| *b==b'\n').next().unwrap_or_default()==pid.to_string().as_bytes())
}
#[derive(Clone)]
struct State {
    pid: u32,
    start: String,
    seq: u64,
    token: String,
}
impl State {
    fn load(d: &Path) -> io::Result<Self> {
        let b = read(&d.join("state"))?;
        let t = std::str::from_utf8(&b).map_err(|_| bad("state encoding"))?;
        let a: Vec<_> = t.split_whitespace().collect();
        if a.len() != 4 || a[3].len() != 32 || !a[3].bytes().all(|x| x.is_ascii_hexdigit()) {
            return Err(bad("state format"));
        }
        Ok(Self {
            pid: a[0].parse().map_err(|_| bad("pid"))?,
            start: a[1].into(),
            seq: a[2].parse().map_err(|_| bad("seq"))?,
            token: a[3].into(),
        })
    }
    fn save(&self, d: &Path) -> io::Result<()> {
        save(
            &d.join("state"),
            format!("{} {} {} {}\n", self.pid, self.start, self.seq, self.token).as_bytes(),
        )
    }
}
fn safe(s: &str) -> bool {
    !s.bytes().any(|b| b == 0 || b";!\"`|<>\n\r".contains(&b))
}
fn fingerprint(p: &str, auth: bool) -> io::Result<String> {
    if p == "-" && !auth {
        return Ok("none".into());
    }
    if p == "-" && auth {
        return Ok("guest".into());
    }
    let path = Path::new(p);
    if p != "/dev/null" {
        let m = fs::symlink_metadata(path)?;
        if !m.is_file()
            || m.uid() != 0
            || (auth && m.mode() & 0o077 != 0)
            || fs::canonicalize(path)? != path
        {
            return Err(bad("config file rejected"));
        }
    }
    crate::speedscan::sha256_file_hex(path)
}
// common arguments: private directory, executable, share, authfile|- (guest), conf, port, owner PID
fn context(a: &[String]) -> io::Result<(Vec<u8>, u32, String)> {
    if a.len() != 7 || a.iter().any(|x| x.contains(['\0', '\n', '\r'])) {
        return Err(bad("arguments"));
    }
    let owner: u32 = a[6].parse().map_err(|_| bad("owner"))?;
    if owner <= 1 {
        return Err(bad("owner"));
    }
    let identity = start(owner)?;
    let _owner = pidfd(owner, &identity)?;
    let port: u16 = a[5].parse().map_err(|_| bad("port"))?;
    if port == 0 || !a[2].starts_with("//") {
        return Err(bad("target"));
    }
    let mut b = a.join("\0").into_bytes();
    for v in [
        identity.clone(),
        fingerprint(&a[3], true)?,
        fingerprint(&a[4], false)?,
    ] {
        b.push(0);
        b.extend_from_slice(v.as_bytes());
    }
    let m = fs::metadata(&a[1])?;
    b.extend_from_slice(
        format!(
            "\0{}:{}:{}:{}:{}",
            m.dev(),
            m.ino(),
            m.len(),
            m.mtime(),
            m.ctime()
        )
        .as_bytes(),
    );
    Ok((b, owner, identity))
}
fn command_frame(d: &Path, s: &mut State, cmd: &str, owner: &File) -> io::Result<(i32, Vec<u8>)> {
    if cmd.len() > 4000 || cmd.contains(['\n', '\r', '\0']) {
        return Err(bad("command limit"));
    }
    let out = d.join("output");
    let mut log = file(&out, false, false)?;
    let offset = log.metadata()?.len();
    if offset > 16 * MAX as u64 {
        return Err(bad("session output limit"));
    }
    log.seek(SeekFrom::Start(offset))?;
    let fd = unsafe { inotify_init1(NONBLOCK | 524288) };
    if fd < 0 {
        return Err(io::Error::last_os_error());
    }
    let watcher = unsafe { File::from_raw_fd(fd) };
    let path = CString::new(out.as_os_str().as_encoded_bytes()).map_err(|_| bad("path"))?;
    if unsafe { inotify_add_watch(fd, path.as_ptr(), 2 | 8 | 1024 | 2048) } < 0 {
        return Err(io::Error::last_os_error());
    }
    let worker = pidfd(s.pid, &s.start)?;
    let fifo = d.join("commands");
    let meta = fs::symlink_metadata(&fifo)?;
    if !meta.file_type().is_fifo() || meta.uid() != 0 || meta.mode() & 0o777 != 0o600 {
        return Err(bad("FIFO rejected"));
    }
    let mut pipe = OpenOptions::new()
        .write(true)
        .custom_flags(NOFOLLOW | NONBLOCK)
        .open(&fifo)?;
    let busy = d.join("busy");
    let mut mark = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(NOFOLLOW)
        .open(&busy)?;
    mark.write_all(if cmd.starts_with("ls ") || cmd == "pwd" {
        b"probe\n"
    } else {
        b"mutation\n"
    })?;
    let bytes = format!("{cmd}\n");
    if pipe.write(bytes.as_bytes())? != bytes.len() {
        return Err(bad("short command write"));
    }
    let seq = s.seq.checked_add(1).ok_or_else(|| bad("sequence"))?;
    let prefix = format!("\nSBRPC1:{}:{}:", s.token, seq).into_bytes();
    let deadline = Instant::now() + Duration::from_secs(300);
    let mut data = Vec::new();
    loop {
        let remaining = MAX.saturating_sub(data.len());
        if remaining == 0 {
            return Err(bad("response limit"));
        }
        let mut chunk = [0u8; 8192];
        let n = log.read(&mut chunk[..remaining.min(8192)])?;
        if n > 0 {
            data.extend_from_slice(&chunk[..n]);
            if let Some(pos) = data.windows(prefix.len()).position(|w| w == prefix) {
                let tail = &data[pos + prefix.len()..];
                if let Some(end) = tail.iter().position(|x| *x == b'\n') {
                    let rc = std::str::from_utf8(&tail[..end])
                        .map_err(|_| bad("status encoding"))?
                        .parse::<i32>()
                        .map_err(|_| bad("status"))?;
                    if end + 1 != tail.len() {
                        return Err(bad("trailing response"));
                    }
                    s.seq = seq;
                    // A received remote result remains authoritative if bookkeeping fails.
                    if s.save(d).and_then(|_| fs::remove_file(&busy)).is_err() {
                        kill(s);
                    }
                    data.truncate(pos);
                    return Ok((rc, data));
                }
            }
            continue;
        }
        let left = deadline
            .checked_duration_since(Instant::now())
            .ok_or_else(|| bad("response timeout"))?;
        let mut p = [
            PollFd {
                fd: watcher.as_raw_fd(),
                events: 1,
                revents: 0,
            },
            PollFd {
                fd: worker.as_raw_fd(),
                events: 1,
                revents: 0,
            },
            PollFd {
                fd: owner.as_raw_fd(),
                events: 1,
                revents: 0,
            },
        ];
        let r = unsafe {
            poll(
                p.as_mut_ptr(),
                3,
                left.as_millis().min(i32::MAX as u128) as i32,
            )
        };
        if r < 0 && io::Error::last_os_error().raw_os_error() == Some(4) {
            continue;
        }
        if r <= 0 || p[1].revents != 0 || p[2].revents != 0 {
            return Err(bad("publisher stopped or timed out"));
        }
        let mut ignored = [0u8; 4096];
        let mut w = &watcher;
        let _ = w.read(&mut ignored);
    }
}
fn begin(d: &Path, a: &[String], ctx: &[u8], owner: &File) -> io::Result<State> {
    for name in ["state", "output", "commands"] {
        let p = d.join(name);
        if let Ok(m) = fs::symlink_metadata(&p) {
            if m.file_type().is_symlink() || m.uid() != 0 {
                return Err(bad("stale session entry rejected"));
            }
            fs::remove_file(p)?;
        }
    }
    let p = CString::new(d.join("commands").as_os_str().as_encoded_bytes())
        .map_err(|_| bad("FIFO path"))?;
    if unsafe { mkfifo(p.as_ptr(), 0o600) } != 0 {
        return Err(io::Error::last_os_error());
    }
    let input = OpenOptions::new()
        .read(true)
        .write(true)
        .custom_flags(NOFOLLOW)
        .open(d.join("commands"))?;
    let output = file(&d.join("output"), true, true)?;
    let mut random = [0u8; 16];
    File::open("/dev/urandom")?.read_exact(&mut random)?;
    let token = random
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect::<String>();
    let mut c = Command::new(&a[1]);
    c.arg(&a[2]);
    if a[3] == "-" {
        c.arg("-N");
    } else {
        c.args(["-A", &a[3]]);
    }
    c.args([
        "-s", &a[4], "-p", &a[5], "-m", "SMB3", "-t", "30", "-D", "/",
    ])
    .env("SPEEDBACKUP_SMB_RPC_TOKEN", &token)
    .stdin(Stdio::from(input))
    .stdout(Stdio::from(output.try_clone()?))
    .stderr(Stdio::from(output));
    // Rust closes its own descriptors on exec, but inherited Shell descriptors
    // (including command substitutions and locks) may lack CLOEXEC.
    let inherited: Vec<i32> = fs::read_dir("/proc/self/fd")?
        .filter_map(Result::ok)
        .filter_map(|e| e.file_name().to_str().and_then(|n| n.parse::<i32>().ok()))
        .filter(|&fd| fd > 2 && fd != 198 && unsafe { fcntl(fd, 1, 0) } == 0)
        .collect();
    let ownerfd = owner.as_raw_fd();
    unsafe {
        c.pre_exec(move || {
            if dup2(ownerfd, 198) < 0 || fcntl(198, 2, 0) < 0 {
                return Err(io::Error::last_os_error());
            }
            for fd in &inherited {
                close(*fd);
            }
            Ok(())
        });
    }
    let mut child = c.spawn()?;
    let result = (|| {
        let mut state = State {
            pid: child.id(),
            start: start(child.id())?,
            seq: 0,
            token,
        };
        state.save(d)?;
        save(&d.join("context"), ctx)?;
        let (rc, _) = command_frame(d, &mut state, "pwd", owner)?;
        if rc != 0 {
            return Err(bad("publisher handshake"));
        }
        Ok(state)
    })();
    if result.is_err() {
        let _ = child.kill();
        let _ = child.wait();
    }
    result
}
fn execute(args: &[String], mutation_possible: &mut bool) -> io::Result<i32> {
    if unsafe { geteuid() } != 0 || args.len() < 8 {
        return Err(bad("root/common arguments required"));
    }
    let op = &args[0];
    let a = &args[1..8];
    if op == "stop" {
        let d = Path::new(&a[0]);
        if d.file_name().and_then(|x| x.to_str()) != Some(".smb-publisher") {
            return Err(bad("session name"));
        }
        directory(d.parent().ok_or_else(|| bad("parent"))?)?;
        if !d.exists() {
            return Ok(0);
        }
        directory(d)?;
        match State::load(d) {
            Ok(s) => kill(&s),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        return Ok(0);
    }
    let d = PathBuf::from(&a[0]);
    if d.file_name().and_then(|x| x.to_str()) != Some(".smb-publisher") {
        return Err(bad("session name"));
    }
    // A fresh session has no history to replay. Existing or inaccessible
    // session state must remain quarantined until checked under the lock.
    if matches!(fs::symlink_metadata(&d), Err(ref e) if e.kind()==io::ErrorKind::NotFound) {
        *mutation_possible = false;
    }
    directory(d.parent().ok_or_else(|| bad("parent"))?)?;
    match fs::create_dir(&d) {
        Ok(()) => fs::set_permissions(&d, fs::Permissions::from_mode(0o700))?,
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(e),
    }
    *mutation_possible = true;
    directory(&d)?;
    let lock = file(&d.join("lock"), true, true)?;
    let deadline = Instant::now() + Duration::from_secs(310);
    while unsafe { flock(lock.as_raw_fd(), 2 | 4) } != 0 {
        if Instant::now() >= deadline {
            return Err(bad("publisher busy"));
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    let prior = State::load(&d);
    // Check quarantine under the lock BEFORE fallible auth/config preflight.
    // An unreadable history or lock contention cannot prove a rename was absent.
    if prior.is_err() && fs::symlink_metadata(d.join("state")).is_ok() {
        return Err(bad("invalid publisher state"));
    }
    if fs::symlink_metadata(d.join("busy")).is_ok() {
        if let Ok(ref state) = prior {
            kill(state);
        }
        if read(&d.join("busy"))? != b"probe\n" {
            return Err(bad("ambiguous prior mutation; no replay"));
        }
        return Ok(78);
    }
    *mutation_possible = false;
    let (ctx, owner_id, owner_start) = context(a)?;
    let owner = pidfd(owner_id, &owner_start)?;
    if let Ok(ref state) = prior {
        if read(&d.join("context"))? != ctx {
            kill(state);
            return Err(bad("publisher context changed before current mutation"));
        }
    }
    // Warm operation never starts a process: Shell must register/protect it first.
    // 79 is a cold-registration request, emitted only before any SMB frame.
    if op == "commit-registered" {
        match &prior {
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(79),
            Ok(state) => {
                if !alive(state) { return Ok(78); }
                if !registered_pid(&d, state.pid) { return Ok(79); }
            }
            Err(_) => return Err(bad("invalid publisher state")),
        }
    }
    let mut state = if op == "ensure" {
        if args.len() != 8 {
            return Err(bad("ensure arguments"));
        }
        match prior {
            Ok(s) if alive(&s) => s,
            Ok(_) => return Ok(78),
            Err(_) if d.join("state").exists() => return Err(bad("invalid publisher state")),
            Err(_) => begin(&d, a, &ctx, &owner)?,
        }
    } else {
        prior?
    };
    if op == "ensure" {
        println!("{}", state.pid);
        return Ok(0);
    }
    if args.len() != 11 || !matches!(op.as_str(), "commit" | "commit-registered") {
        return Err(bad("operation"));
    }
    let dir = &args[8];
    let part = &args[9];
    let final_name = &args[10];
    if ![dir, part, final_name].iter().all(|x| safe(x))
        || !part.starts_with(".speedbackup_")
        || !part.ends_with(".part")
        || !part
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
        || final_name.is_empty()
    {
        return Err(bad("publish paths"));
    }
    let dir = dir.replace('/', "\\");
    let dir = dir.trim_matches('\\');
    let prefix = if dir.is_empty() {
        "\\".into()
    } else {
        format!("\\{dir}\\")
    };
    let source = format!("{prefix}{part}");
    let target = format!("{prefix}{final_name}");
    // A failed read-only probe permits a fresh one-shot attempt. Once the
    // rename frame is sent, no error can return the compatibility status 78.
    let listing = match command_frame(&d, &mut state, &format!("ls \"{source}\""), &owner) {
        Ok((0, output)) => output,
        _ => {
            kill(&state);
            return Ok(78);
        }
    };
    let cmd = format!("rename \"{source}\" \"{target}\" -f");
    *mutation_possible = true;
    match command_frame(&d, &mut state, &cmd, &owner) {
        Ok((rc, out)) => {
            io::stdout().write_all(&listing)?;
            io::stdout().write_all(&out)?;
            Ok(if rc == 0 { 0 } else { 1 })
        }
        Err(e) => {
            kill(&state);
            Err(e)
        }
    }
}
pub fn run(args: &[String]) -> i32 {
    let mut mutation_possible = true;
    match execute(args, &mut mutation_possible) {
        Ok(rc) => rc,
        Err(e) => {
            eprintln!("SMB_PUBLISHER_FAILED {e}");
            if !mutation_possible {
                78
            } else {
                1
            }
        }
    }
}
