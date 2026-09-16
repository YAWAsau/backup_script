use speedbackup_native_rs::*;
use std::env;
use std::ffi::CString;
use std::fs::{self, File};
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::time::{Duration, Instant};

const VERSION: &str = "1.6.1-r572-pidfd-pipeline-convergence-api28-r28c-rust-r572";

fn usage(argv0: &str) {
    eprintln!("usage:");
    eprintln!("  {} --version", argv0);
    eprintln!("  {} capabilities", argv0);
    eprintln!("  {} pidfd-probe [PID]", argv0);
    eprintln!("  {} FIFO PID [FATAL_FILE|-] [TIMEOUT_MS] [TAG]", argv0);
    eprintln!("  {} file-created PATH TIMEOUT_MS [TAG]", argv0);
    eprintln!("  {} file-nonempty PATH TIMEOUT_MS [TAG]", argv0);
    eprintln!("  {} file-contains PATH PATTERN TIMEOUT_MS [TAG]", argv0);
    eprintln!("  {} socket-ready PATH TIMEOUT_MS [TAG]", argv0);
    eprintln!("  {} pid-exit PID TIMEOUT_MS [TAG]", argv0);
    eprintln!("  {} pid-or-file PID FATAL_FILE TIMEOUT_MS [TAG]", argv0);
    eprintln!("  {} pipeline-watch PID_LIST_FILE FATAL_FILE|- PROGRESS_FILE|- IDLE_MS TIMEOUT_MS [TAG] [--json|--tsv]", argv0);
    eprintln!("  {} pipeline-rate-watch PID_LIST_FILE FATAL_FILE|- PROGRESS_FILE|- IDLE_MS TIMEOUT_MS MIN_BPS WINDOW_MS [TAG] [--json|--tsv]", argv0);
    eprintln!("  {} file-size-stable PATH STABLE_MS TIMEOUT_MS [TAG]", argv0);
    eprintln!("  {} cleanup-owned RUN_ID TMPDIR", argv0);
}

fn parse_pid_arg_strict(s: &str) -> Option<i32> {
    // C main() uses strtol(): leading whitespace is accepted, but any
    // remaining suffix rejects the PID. Keep the same 1..4194304 gate.
    let left = s.trim_start_matches(|c: char| c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\u{000b}' || c == '\u{000c}');
    if left.is_empty() { return None; }
    let v = left.parse::<i64>().ok()?;
    if v > 0 && v <= 4_194_304 { Some(v as i32) } else { None }
}

fn pidfd_probe(pid: i32) -> i32 {
    match pidfd_open(pid) {
        Ok(fd) => { unsafe { close(fd) }; println!("pidfd-probe\t0\tpid={}\tbackend=pidfd_open", pid); 0 }
        Err(e) => { println!("pidfd-probe\t125\tpid={}\terrno={}", pid, e.raw_os_error().unwrap_or(-1)); 125 }
    }
}

/// Faithful port of wait_pid_or_file(): watches /proc/PID (exit detection)
/// and the fatal_file's parent dir + file via inotify, blocking in poll()
/// with a 1000ms safety-net tick. Exit codes match C exactly: 126=fatal-file
/// already/became non-empty, 0=pid-exit, 124=timeout. The previous
/// implementation used a 50ms sleep-poll loop and the wrong exit code/reason
/// (125/file-nonempty instead of 126/fatal-file) for the fatal-file path.
fn wait_pid_or_file(pid: i32, fatal_file: &str, timeout_ms: i64, tag: &str) -> i32 {
    let tag = if tag.is_empty() { "pid_or_file" } else { tag };
    let start = Instant::now();
    let has_fatal = !fatal_file.is_empty();

    if has_fatal && file_nonempty(Path::new(fatal_file)) {
        println!("fatal\t126\t{}\tfatal-file", tag);
        return 126;
    }
    if pid <= 0 {
        return 2;
    }
    if !pid_alive(pid) {
        println!("done\t0\t{}\tpid-exit", tag);
        return 0;
    }

    let ifd = unsafe { inotify_init1(IN_NONBLOCK | IN_CLOEXEC) };
    let mut wd_fatal_file: i32 = -1;
    if ifd >= 0 {
        if let Ok(pp) = CString::new(format!("/proc/{}", pid)) {
            unsafe { inotify_add_watch(ifd, pp.as_ptr(), IN_DELETE_SELF | IN_ATTRIB | IN_MOVE_SELF | IN_IGNORED) };
        }
        if has_fatal {
            if let Some(parent) = Path::new(fatal_file).parent().filter(|p| !p.as_os_str().is_empty()) {
                if let Ok(pc) = CString::new(parent.as_os_str().as_bytes()) {
                    unsafe {
                        inotify_add_watch(
                            ifd, pc.as_ptr(),
                            IN_CREATE | IN_MOVED_TO | IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF,
                        );
                    }
                }
            }
            if file_exists(Path::new(fatal_file)) {
                if let Ok(fc) = CString::new(fatal_file) {
                    wd_fatal_file = unsafe {
                        inotify_add_watch(ifd, fc.as_ptr(), IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF)
                    };
                }
            }
        }
    }
    let finish = |ifd: i32| { if ifd >= 0 { unsafe { close(ifd) }; } };

    loop {
        let now = start.elapsed().as_millis() as i64;
        let mut wait_ms: i64 = 1000;
        if has_fatal && file_nonempty(Path::new(fatal_file)) {
            finish(ifd);
            println!("fatal\t126\t{}\tfatal-file", tag);
            return 126;
        }
        if !pid_alive(pid) {
            finish(ifd);
            println!("done\t0\t{}\tpid-exit", tag);
            return 0;
        }
        if timeout_ms > 0 {
            if now >= timeout_ms {
                finish(ifd);
                println!("timeout\t124\t{}\ttimeout", tag);
                return 124;
            }
            if timeout_ms - now < wait_ms { wait_ms = timeout_ms - now; }
        }
        if ifd >= 0 {
            let mut pfd = PollFd { fd: ifd, events: POLLIN, revents: 0 };
            let prc = unsafe { poll(&mut pfd as *mut PollFd, 1, wait_ms.max(0) as i32) };
            if prc < 0 {
                let e = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
                if e == 4 { continue; } // EINTR
                finish(ifd);
                return 4;
            }
            if prc > 0 && pfd.revents & POLLIN != 0 {
                let mut evbuf = [0u8; 4096];
                unsafe { read(ifd, evbuf.as_mut_ptr() as *mut std::os::raw::c_void, evbuf.len()) };
                if has_fatal && wd_fatal_file < 0 && file_exists(Path::new(fatal_file)) {
                    if let Ok(fc) = CString::new(fatal_file) {
                        wd_fatal_file = unsafe {
                            inotify_add_watch(ifd, fc.as_ptr(), IN_CLOSE_WRITE | IN_MODIFY | IN_ATTRIB | IN_DELETE_SELF | IN_MOVE_SELF)
                        };
                    }
                }
            }
        } else {
            std::thread::sleep(Duration::from_millis(if wait_ms > 0 { wait_ms as u64 } else { 100 }));
        }
    }
}

/// Faithful port of wait_fifo_event(): opens the FIFO once with O_RDWR (a
/// classic trick that avoids the "open for read blocks until a writer
/// connects" FIFO semantics), then poll()s for POLLIN/POLLHUP/POLLERR and
/// reads incrementally until a newline or buffer-full. fatal-file uses
/// emit_fatal()'s rc=126 (the previous port used the wrong code, 125, which
/// collides with eventwait's own "idle" rc used elsewhere in this binary).
fn wait_fifo_event(fifo: &str, pid: i32, fatal_file: &str, timeout_ms: i64, tag: &str) -> i32 {
    if fifo.is_empty() || pid <= 0 {
        return 2;
    }
    let out_tag = if tag.is_empty() { "remote_stream_child" } else { tag };
    let fd = unsafe {
        let c = match CString::new(fifo) { Ok(v) => v, Err(_) => return 2 };
        open(c.as_ptr(), O_RDWR | O_NONBLOCK | O_CLOEXEC, 0)
    };
    if fd < 0 {
        eprintln!("eventwait: open fifo failed: {}: {}", fifo, c_strerror(&std::io::Error::last_os_error()));
        return 3;
    }
    let has_fatal = !fatal_file.is_empty() && fatal_file != "-";
    let start = Instant::now();
    let mut buf = vec![0u8; 4096];
    let mut used = 0usize;

    loop {
        let mut wait_ms: i64 = 100;
        if timeout_ms > 0 {
            let elapsed = start.elapsed().as_millis() as i64;
            if elapsed >= timeout_ms {
                unsafe { close(fd) };
                println!("timeout\t124\t{}\ttimeout", out_tag);
                return 124;
            }
            if timeout_ms - elapsed < wait_ms { wait_ms = timeout_ms - elapsed; }
        }
        if has_fatal && file_nonempty(Path::new(fatal_file)) {
            unsafe { close(fd) };
            println!("fatal\t126\t{}\tremote_stream_fatal_file", out_tag);
            return 126;
        }
        if !pid_alive(pid) && used == 0 {
            unsafe { close(fd) };
            println!("done\t0\t{}\tchild_gone_no_event", out_tag);
            return 0;
        }

        let mut pfd = PollFd { fd, events: POLLIN | POLLHUP | POLLERR, revents: 0 };
        let prc = unsafe { poll(&mut pfd as *mut PollFd, 1, wait_ms.max(0) as i32) };
        if prc < 0 {
            let e = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
            if e == 4 { continue; } // EINTR
            eprintln!("eventwait: poll failed: {}", c_strerror(&std::io::Error::last_os_error()));
            unsafe { close(fd) };
            return 4;
        }
        if prc == 0 {
            continue;
        }
        if pfd.revents & (POLLIN | POLLHUP | POLLERR) != 0 {
            loop {
                let n = unsafe { read(fd, buf[used..].as_mut_ptr() as *mut std::os::raw::c_void, buf.len() - 1 - used) };
                if n > 0 {
                    used += n as usize;
                    if let Some(pos) = buf[..used].iter().position(|&b| b == b'\n') {
                        let end = buf[..pos].iter().position(|&b| b == 0).unwrap_or(pos);
                        let _ = std::io::stdout().write_all(&buf[..end]);
                        let _ = std::io::stdout().write_all(b"\n");
                        unsafe { close(fd) };
                        return 0;
                    }
                    if used >= buf.len() - 2 {
                        let end = buf[..used].iter().position(|&b| b == 0).unwrap_or(used);
                        let _ = std::io::stdout().write_all(&buf[..end]);
                        let _ = std::io::stdout().write_all(b"\n");
                        unsafe { close(fd) };
                        return 0;
                    }
                    continue;
                }
                if n < 0 {
                    let e = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
                    if e == 11 || e == 4 { break; } // EAGAIN/EWOULDBLOCK/EINTR: no more data right now
                    eprintln!("eventwait: read failed: {}", c_strerror(&std::io::Error::last_os_error()));
                    unsafe { close(fd) };
                    return 5;
                }
                break; // n == 0
            }
        }
    }
}


struct PipelinePid { pid: i32 }

fn parse_pipeline_pid_chunk(mut line: &[u8]) -> Option<PipelinePid> {
    // c/eventwait.c parse_pid_line(): skip only leading space/tab; the
    // caller already gives at most one fgets(256) chunk (<=255 bytes).
    while matches!(line.first(), Some(b' ' | b'\t')) { line = &line[1..]; }
    if line.is_empty() || line[0] == b'#' { return None; }

    let mut buf = line[..line.len().min(255)].to_vec();
    while matches!(buf.last(), Some(b'\n' | b'\r' | b' ' | b'\t')) { buf.pop(); }
    if buf.is_empty() { return None; }

    // strsep("\t "): remember the last non-empty token.
    let mut last: Option<&[u8]> = None;
    let mut i = 0usize;
    while i <= buf.len() {
        let st = i;
        while i < buf.len() && buf[i] != b'\t' && buf[i] != b' ' { i += 1; }
        if i > st { last = Some(&buf[st..i]); }
        i += 1;
    }
    let tok = last?;
    let tok_str = std::str::from_utf8(tok).ok()?;
    let pid = parse_pid_arg_strict(tok_str)?;

    // C computes a label for diagnostics, but the current pipeline-watch
    // output does not print it. Keep the pid semantics without storing an
    // unused Rust field.
    Some(PipelinePid { pid })
}

/// Faithful port of fgets(line[256]) + parse_pid_line(). A physical line
/// longer than 255 bytes is intentionally split into multiple parse chunks,
/// exactly as C fgets() does; do not replace with read_to_string().lines().
fn load_pid_file(path: &str) -> Vec<PipelinePid> {
    let mut out = Vec::new();
    let mut f = match File::open(path) { Ok(v) => v, Err(_) => return out };
    let mut pending: Vec<u8> = Vec::with_capacity(255);
    let mut one = [0u8; 1];
    loop {
        let n = match f.read(&mut one) {
            Ok(n) => n,
            Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(_) => 0,
        };
        if n == 0 {
            if !pending.is_empty() {
                if let Some(ent) = parse_pipeline_pid_chunk(&pending) {
                    if !out.iter().any(|p: &PipelinePid| p.pid == ent.pid) { out.push(ent); }
                }
            }
            break;
        }
        pending.push(one[0]);
        if one[0] == b'\n' || pending.len() == 255 {
            if let Some(ent) = parse_pipeline_pid_chunk(&pending) {
                if !out.iter().any(|p: &PipelinePid| p.pid == ent.pid) { out.push(ent); }
            }
            pending.clear();
            if out.len() >= 160 { break; }
        }
    }
    out.truncate(160);
    out
}

/// Faithful port of discover_children_once(): one read() into char[4096], so
/// only the first 4095 bytes are considered. This bound is observable for a
/// process with a very large children list.
fn discover_children_once(pids: &mut Vec<PipelinePid>) {
    let initial = pids.len().min(160);
    for i in 0..initial {
        if pids.len() >= 160 { break; }
        let pid = pids[i].pid;
        let path = format!("/proc/{}/task/{}/children", pid, pid);
        let mut f = match File::open(&path) { Ok(v) => v, Err(_) => continue };
        let mut buf = [0u8; 4095];
        let n = loop {
            match f.read(&mut buf) {
                Ok(n) => break n,
                Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break 0,
            }
        };
        if n == 0 { continue; }
        for tok in buf[..n].split(|b| matches!(*b, b' ' | b'\t' | b'\n' | b'\r')) {
            if tok.is_empty() { continue; }
            let t = match std::str::from_utf8(tok) { Ok(v) => v, Err(_) => continue };
            if let Some(child) = parse_pid_arg_strict(t) {
                if pids.len() < 160 && !pids.iter().any(|p| p.pid == child) {
                    let mut label = format!("child{}", child);
                    if label.len() > 63 { label.truncate(63); }
                    pids.push(PipelinePid { pid: child });
                }
            }
        }
    }
}

/// Faithful port of stat_progress(): returns (size, nanosecond mtime stamp).
fn stat_progress(path: &str) -> Option<(i64, i64)> {
    if path.is_empty() || path == "-" { return None; }
    let m = fs::metadata(path).ok()?;
    let stamp = m.mtime() * 1_000_000_000 + m.mtime_nsec();
    Some((m.len() as i64, stamp))
}

/// Faithful port of sum_pipeline_cpu_ticks(): reads utime(field 14)+stime
/// (field 15) from /proc/PID/stat for every tracked pid, fields counted
/// starting after the last ')' (comm can contain spaces/parens).
fn c_atoll_prefix(bytes: &[u8]) -> i64 {
    let mut i = 0usize;
    while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    let neg = if i < bytes.len() && bytes[i] == b'-' { i += 1; true } else { if i < bytes.len() && bytes[i] == b'+' { i += 1; } false };
    let mut any = false;
    let mut v: i128 = 0;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        any = true;
        v = v.saturating_mul(10).saturating_add((bytes[i] - b'0') as i128);
        i += 1;
    }
    if !any { return 0; }
    if neg { (-v).clamp(i64::MIN as i128, i64::MAX as i128) as i64 }
    else { v.clamp(i64::MIN as i128, i64::MAX as i128) as i64 }
}

fn sum_pipeline_cpu_ticks(pids: &[PipelinePid]) -> i64 {
    let mut total: i64 = 0;
    for p in pids {
        if p.pid <= 0 { continue; }
        let mut f = match File::open(format!("/proc/{}/stat", p.pid)) { Ok(v) => v, Err(_) => continue };
        let mut buf = [0u8; 1023];
        let n = loop {
            match f.read(&mut buf) {
                Ok(n) => break n,
                Err(ref e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break 0,
            }
        };
        if n == 0 { continue; }
        let bytes = &buf[..n];
        let rp = match bytes.iter().rposition(|&b| b == b')') { Some(v) => v, None => continue };
        if rp + 2 > bytes.len() { continue; }
        let rest = &bytes[rp + 2..];
        let mut field = 3;
        let mut utime = 0i64;
        let mut stime = 0i64;
        for tok in rest.split(|&b| b == b' ') {
            if tok.is_empty() { continue; }
            if field == 14 { utime = c_atoll_prefix(tok); }
            if field == 15 { stime = c_atoll_prefix(tok); break; }
            field += 1;
        }
        total = total.wrapping_add(utime.wrapping_add(stime));
    }
    total
}

fn emit_pipeline_event(event: &str, rc: i32, tag: &str, reason: &str, pid_count: usize, alive: i32, extra: &str, json: bool) {
    let t = if tag.is_empty() { "pipeline_watch" } else { tag };
    let r = if reason.is_empty() { event } else { reason };
    if json {
        print!("{{\"event\":\"{}\",\"rc\":{},\"tag\":\"{}\",\"reason\":\"{}\",\"pidCount\":{},\"alive\":{}", event, rc, t, r, pid_count, alive);
        if !extra.is_empty() {
            // C prints the caller-provided fragment verbatim after a comma.
            // Preserve that byte-level behavior even though current callers
            // pass TAB-separated key=value text rather than strict JSON.
            print!(",{}", extra);
        }
        println!("}}");
    } else {
        print!("{}\t{}\t{}\t{}\tpidCount={}", event, rc, t, r, pid_count);
        if alive >= 0 { print!("\talive={}", alive); }
        if !extra.is_empty() { print!("\t{}", extra); }
        println!();
    }
}

/// Faithful port of wait_pipeline_watch(): polls every ~500ms (matching C;
/// this genuinely cannot be made event-driven since it must periodically
/// recheck N pids' liveness and cumulative CPU ticks). rc=125 ("idle") is a
/// DISTINCT outcome from rc=124 ("timeout") - the previous implementation
/// collapsed both into rc=124, which breaks any caller distinguishing
/// "genuinely stalled" from "overall deadline exceeded". CPU-tick tracking
/// (missing entirely from the previous implementation) is what lets this
/// tell "no progress but still burning CPU" apart from "truly stalled".
fn pipeline_watch(pid_file: &str, fatal_file: &str, progress_file: &str, idle_ms: i64, timeout_ms: i64, tag: &str, json: bool) -> i32 {
    let start = Instant::now();
    let fatal_enabled = !fatal_file.is_empty() && fatal_file != "-";
    let progress_enabled = !progress_file.is_empty() && progress_file != "-";
    let out_tag = if tag.is_empty() { "pipeline_watch" } else { tag };

    let mut pids = load_pid_file(pid_file);
    if pids.is_empty() { return 2; }
    if fatal_enabled && file_nonempty(Path::new(fatal_file)) {
        emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pids.len(), -1, "", json);
        return 126;
    }

    let mut last_size: i64 = -1;
    let mut last_stamp: i64 = -1;
    let mut progress_seen = false;
    let mut last_progress_ms: i64 = 0;
    let mut last_cpu_ticks: i64 = 0;
    if progress_enabled {
        if let Some((sz, stp)) = stat_progress(progress_file) {
            progress_seen = true;
            last_size = sz;
            last_stamp = stp;
            last_progress_ms = 0;
            last_cpu_ticks = sum_pipeline_cpu_ticks(&pids);
        }
    }

    loop {
        let now = start.elapsed().as_millis() as i64;
        let mut wait_ms: i64 = 500;
        discover_children_once(&mut pids);
        let alive = pids.iter().filter(|p| pid_alive(p.pid)).count() as i32;
        if fatal_enabled && file_nonempty(Path::new(fatal_file)) {
            emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pids.len(), alive, "", json);
            return 126;
        }
        if alive <= 0 {
            emit_pipeline_event("done", 0, out_tag, "pipeline-exit", pids.len(), -1, "", json);
            return 0;
        }
        if progress_enabled {
            if let Some((sz, stp)) = stat_progress(progress_file) {
                if !progress_seen || sz != last_size || stp != last_stamp {
                    progress_seen = true;
                    last_size = sz;
                    last_stamp = stp;
                    last_progress_ms = now;
                    last_cpu_ticks = sum_pipeline_cpu_ticks(&pids);
                }
            }
            if idle_ms > 0 && progress_seen && now - last_progress_ms >= idle_ms {
                let cpu_now = sum_pipeline_cpu_ticks(&pids);
                let extra = format!("idleMs={}\tcpuTicksDelta={}", now - last_progress_ms, cpu_now - last_cpu_ticks);
                let reason = if cpu_now > last_cpu_ticks { "no-progress-but-cpu-active" } else { "progress-idle" };
                emit_pipeline_event("idle", 125, out_tag, reason, pids.len(), alive, &extra, json);
                return 125;
            }
        }
        if timeout_ms > 0 {
            if now >= timeout_ms {
                emit_pipeline_event("timeout", 124, out_tag, "timeout", pids.len(), alive, "", json);
                return 124;
            }
            if timeout_ms - now < wait_ms { wait_ms = timeout_ms - now; }
        }
        if idle_ms > 0 && progress_seen {
            let remain = idle_ms - (now - last_progress_ms);
            if remain > 0 && remain < wait_ms { wait_ms = remain; }
        }
        std::thread::sleep(Duration::from_millis(if wait_ms > 0 { wait_ms as u64 } else { 100 }));
    }
}

/// Faithful port of wait_pipeline_rate_watch(): same as pipeline_watch but
/// additionally enforces a minimum bytes/sec over rolling `window_ms`
/// windows, reported as rc=125 reason="progress-rate-low" when violated.
fn pipeline_rate_watch(pid_file: &str, fatal_file: &str, progress_file: &str, idle_ms: i64, timeout_ms: i64, min_bps: i64, window_ms_in: i64, tag: &str, json: bool) -> i32 {
    let start = Instant::now();
    let fatal_enabled = !fatal_file.is_empty() && fatal_file != "-";
    let progress_enabled = !progress_file.is_empty() && progress_file != "-";
    let out_tag = if tag.is_empty() { "pipeline_rate_watch" } else { tag };
    let window_ms = if window_ms_in <= 0 { 30000 } else { window_ms_in };

    let mut pids = load_pid_file(pid_file);
    if pids.is_empty() { return 2; }
    if fatal_enabled && file_nonempty(Path::new(fatal_file)) {
        emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pids.len(), -1, "", json);
        return 126;
    }

    let mut last_size: i64 = -1;
    let mut window_size: i64 = -1;
    let mut last_stamp: i64 = -1;
    let mut progress_seen = false;
    let mut last_progress_ms: i64 = 0;
    let mut window_start_ms: i64 = 0;
    let mut last_cpu_ticks: i64 = 0;
    if progress_enabled {
        if let Some((sz, stp)) = stat_progress(progress_file) {
            progress_seen = true;
            last_size = sz;
            last_stamp = stp;
            last_progress_ms = 0;
            last_cpu_ticks = sum_pipeline_cpu_ticks(&pids);
            window_start_ms = 0;
            window_size = sz;
        }
    }

    loop {
        let now = start.elapsed().as_millis() as i64;
        let mut wait_ms: i64 = 500;
        discover_children_once(&mut pids);
        let alive = pids.iter().filter(|p| pid_alive(p.pid)).count() as i32;
        if fatal_enabled && file_nonempty(Path::new(fatal_file)) {
            emit_pipeline_event("fatal", 126, out_tag, "fatal-file", pids.len(), alive, "", json);
            return 126;
        }
        if alive <= 0 {
            emit_pipeline_event("done", 0, out_tag, "pipeline-exit", pids.len(), -1, "", json);
            return 0;
        }
        if progress_enabled {
            if let Some((sz, stp)) = stat_progress(progress_file) {
                if !progress_seen || sz != last_size || stp != last_stamp {
                    progress_seen = true;
                    last_size = sz;
                    last_stamp = stp;
                    last_progress_ms = now;
                    if window_size < 0 { window_size = sz; window_start_ms = now; }
                }
                if min_bps > 0 && progress_seen && now - window_start_ms >= window_ms {
                    let dt = now - window_start_ms;
                    let db = sz - window_size;
                    let bps = if dt > 0 { db * 1000 / dt } else { 0 };
                    if bps < min_bps {
                        let extra = format!("bytesPerSec={}\tminBytesPerSec={}\twindowMs={}", bps, min_bps, window_ms);
                        emit_pipeline_event("idle", 125, out_tag, "progress-rate-low", pids.len(), alive, &extra, json);
                        return 125;
                    }
                    window_start_ms = now;
                    window_size = sz;
                }
            }
            if idle_ms > 0 && progress_seen && now - last_progress_ms >= idle_ms {
                let cpu_now = sum_pipeline_cpu_ticks(&pids);
                let extra = format!("idleMs={}\tcpuTicksDelta={}", now - last_progress_ms, cpu_now - last_cpu_ticks);
                let reason = if cpu_now > last_cpu_ticks { "no-progress-but-cpu-active" } else { "progress-idle" };
                emit_pipeline_event("idle", 125, out_tag, reason, pids.len(), alive, &extra, json);
                return 125;
            }
        }
        if timeout_ms > 0 {
            if now >= timeout_ms {
                emit_pipeline_event("timeout", 124, out_tag, "timeout", pids.len(), alive, "", json);
                return 124;
            }
            if timeout_ms - now < wait_ms { wait_ms = timeout_ms - now; }
        }
        if idle_ms > 0 && progress_seen {
            let remain = idle_ms - (now - last_progress_ms);
            if remain > 0 && remain < wait_ms { wait_ms = remain; }
        }
        std::thread::sleep(Duration::from_millis(if wait_ms > 0 { wait_ms as u64 } else { 100 }));
    }
}

fn remove_tree_safe_c(path: &Path) -> i32 {
    let md = match fs::symlink_metadata(path) {
        Ok(v) => v,
        Err(e) => return if e.kind() == std::io::ErrorKind::NotFound { 0 } else { 1 },
    };
    if md.file_type().is_dir() {
        let rd = match fs::read_dir(path) { Ok(v) => v, Err(_) => return 1 };
        let mut rc = 0;
        for ent in rd {
            // C stops its readdir() loop on NULL and does not inspect errno.
            let ent = match ent { Ok(v) => v, Err(_) => break };
            let name = ent.file_name();
            if name.as_bytes() == b"." || name.as_bytes() == b".." { continue; }
            let mut child_bytes = path.as_os_str().as_bytes().to_vec();
            child_bytes.push(b'/');
            child_bytes.extend_from_slice(name.as_bytes());
            if child_bytes.len() >= PATH_MAX_SAFE { rc = 1; continue; }
            let child = path.join(&name);
            if remove_tree_safe_c(&child) != 0 { rc = 1; }
        }
        if fs::remove_dir(path).is_err() { rc = 1; }
        rc
    } else if fs::remove_file(path).is_ok() { 0 } else { 1 }
}

fn cleanup_owned(run_id: &str, tmpdir: &str) -> i32 {
    let prefix = "/data/local/tmp/.speedbackup_run_";
    if run_id.is_empty() || tmpdir.is_empty() { return 2; }
    if !tmpdir.starts_with(prefix) { println!("skip\t0\tcleanup-owned\tunsafe-path\tpath={}", tmpdir); return 0; }
    if tmpdir.contains("..") { println!("skip\t0\tcleanup-owned\tdotdot\tpath={}", tmpdir); return 0; }
    let owner_path = format!("{}/owner.pid", tmpdir);
    if owner_path.as_bytes().len() >= PATH_MAX_SAFE { return 2; }
    let mut owner_file = match File::open(&owner_path) {
        Ok(f) => f,
        Err(_) => { println!("skip\t0\tcleanup-owned\tno-owner\tpath={}", tmpdir); return 0; }
    };
    let mut owner_buf = [0u8; 127];
    let n = match owner_file.read(&mut owner_buf) { Ok(n) => n, Err(_) => 0 };
    drop(owner_file); // C closes owner.pid before parsing/removing the tree.
    if n == 0 { println!("skip\t0\tcleanup-owned\tempty-owner\tpath={}", tmpdir); return 0; }
    let end = owner_buf[..n].iter().position(|b| matches!(*b, b'\r'|b'\n'|b'\t'|b' ')).unwrap_or(n);
    let owner = String::from_utf8_lossy(&owner_buf[..end]).into_owned();
    // If the first byte is a delimiter C obtains owner_buf="" and reports
    // owner-mismatch (not empty-owner); only read() <= 0 is empty-owner.
    if owner != run_id { println!("skip\t0\tcleanup-owned\towner-mismatch\tpath={}\towner={}", tmpdir, owner); return 0; }
    let rc = remove_tree_safe_c(Path::new(tmpdir));
    if rc == 0 {
        println!("done\t0\tcleanup-owned\tremoved\tpath={}\towner={}", tmpdir, owner); 0
    } else {
        println!("fail\t1\tcleanup-owned\tremove-failed\tpath={}\towner={}", tmpdir, owner); 1
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let argv0 = args.get(0).map(|s| s.as_str()).unwrap_or("eventwait");
    let rc = match args.get(1).map(|s| s.as_str()) {
        Some("--version") if args.len() == 2 => { println!("eventwait {}", VERSION); 0 }
        Some("capabilities") | Some("--capabilities") if args.len() == 2 => { println!("eventwait.pidfd_open.v1 eventwait.pid_exit_pidfd.v1 eventwait.proc_inotify_fallback.v1 eventwait.poll_fallback.v1 eventwait.rust_convergence_source.v1"); 0 }
        Some("pidfd-probe") => {
            let probe_pid = if let Some(s) = args.get(2) {
                match parse_pid_arg_strict(s) { Some(v) => v, None => { std::process::exit(2); } }
            } else { std::process::id() as i32 };
            pidfd_probe(probe_pid)
        },
        Some("--help") | Some("-h") => { usage(argv0); 0 }
        Some("file-created") if args.len() >= 4 => wait_file_condition("file-created", Path::new(&args[2]), "", parse_eventwait_int(args.get(3).map(String::as_str), 0), args.get(4).map(|s|s.as_str()).unwrap_or("file_created")),
        Some("file-nonempty") if args.len() >= 4 => wait_file_condition("file-nonempty", Path::new(&args[2]), "", parse_eventwait_int(args.get(3).map(String::as_str), 0), args.get(4).map(|s|s.as_str()).unwrap_or("file_nonempty")),
        Some("file-contains") if args.len() >= 5 => wait_file_condition("file-contains", Path::new(&args[2]), &args[3], parse_eventwait_int(args.get(4).map(String::as_str), 0), args.get(5).map(|s|s.as_str()).unwrap_or("file_contains")),
        Some("socket-ready") if args.len() >= 4 => wait_file_condition("socket-ready", Path::new(&args[2]), "", parse_eventwait_int(args.get(3).map(String::as_str), 0), args.get(4).map(|s|s.as_str()).unwrap_or("socket_ready")),
        Some("file-size-stable") if args.len() >= 5 => wait_file_condition("file-size-stable", Path::new(&args[2]), &args[3], parse_eventwait_int(args.get(4).map(String::as_str), 0), args.get(5).map(|s|s.as_str()).unwrap_or("file_size_stable")),
        Some("pid-exit") if args.len() >= 4 => match parse_pid_arg_strict(&args[2]) {
            Some(pid) => wait_pid_exit_poll(pid, parse_eventwait_int(args.get(3).map(String::as_str), 0), args.get(4).map(|s|s.as_str()).unwrap_or("pid_exit")),
            None => 2,
        },
        Some("pid-or-file") if args.len() >= 5 => match parse_pid_arg_strict(&args[2]) {
            Some(pid) => wait_pid_or_file(pid, &args[3], parse_eventwait_int(args.get(4).map(String::as_str), 0), args.get(5).map(|s|s.as_str()).unwrap_or("pid_or_file")),
            None => 2,
        },
        Some("pipeline-watch") if args.len() >= 7 => {
            let mut tag = args.get(7).map(|s| s.as_str()).unwrap_or("pipeline_watch");
            let mut json = false;
            if args.get(7).map(|s| s == "--json").unwrap_or(false) { json = true; tag = "pipeline_watch"; }
            if args.get(8).map(|s| s == "--json").unwrap_or(false) { json = true; }
            pipeline_watch(&args[2], &args[3], &args[4], parse_eventwait_int(args.get(5).map(String::as_str), 0), parse_eventwait_int(args.get(6).map(String::as_str), 0), tag, json)
        }
        Some("pipeline-rate-watch") if args.len() >= 9 => {
            let mut tag = args.get(9).map(|s| s.as_str()).unwrap_or("pipeline_rate_watch");
            let mut json = false;
            if args.get(9).map(|s| s == "--json").unwrap_or(false) { json = true; tag = "pipeline_rate_watch"; }
            if args.get(10).map(|s| s == "--json").unwrap_or(false) { json = true; }
            pipeline_rate_watch(&args[2], &args[3], &args[4], parse_eventwait_int(args.get(5).map(String::as_str), 0), parse_eventwait_int(args.get(6).map(String::as_str), 0), parse_eventwait_int(args.get(7).map(String::as_str), 0), parse_eventwait_int(args.get(8).map(String::as_str), 30000), tag, json)
        }
        Some("cleanup-owned") if args.len() >= 4 => cleanup_owned(&args[2], &args[3]),
        // C main() returns 2 for recognized commands with too few argv before
        // falling back to the legacy FIFO form. Without this arm, e.g.
        // `pid-exit 123` could be misinterpreted as legacy wait on command
        // name `pid-exit`, which is not C behavior.
        Some("file-created") | Some("file-nonempty") | Some("file-contains") |
        Some("socket-ready") | Some("file-size-stable") | Some("pid-exit") |
        Some("pid-or-file") | Some("pipeline-watch") | Some("pipeline-rate-watch") |
        Some("cleanup-owned") => 2,
        Some(_) if args.len() >= 3 => match parse_pid_arg_strict(&args[2]) {
            Some(pid) => wait_fifo_event(&args[1], pid, args.get(3).map(|s|s.as_str()).unwrap_or("-"), parse_eventwait_int(args.get(4).map(String::as_str), 0), args.get(5).map(|s|s.as_str()).unwrap_or("remote_stream_child")),
            None => 2,
        },
        _ => { usage(argv0); 2 }
    };
    std::process::exit(rc);
}
