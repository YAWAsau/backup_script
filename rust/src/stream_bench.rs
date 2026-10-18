//! Constant-memory diagnostic stream. Payload never touches local storage.
use std::fs::{self, File, OpenOptions};
use std::io::{self, IsTerminal, Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::time::{Duration, Instant};
use speedbackup_native_rs::{O_CLOEXEC, O_NONBLOCK};

fn frame(total: u64, expected: u64, speed: f64, generate: bool, color: u8) -> String {
    format!("\r\x1b[38;5;{color}m -{} {:.1}% | {:.1} MiB/s\x1b[0m\x1b[K",
        if generate { "上傳" } else { "下載" },
        total as f64 * 100.0 / expected as f64, speed)
}

struct Progress {
    tty: Option<File>,
    drawn: bool,
    last_draw: Instant,
    sample_at: Instant,
    sample_bytes: u64,
    speed: f64,
    color: u8,
}
impl Progress {
    fn new() -> Self {
        // Like tar progress: separate nonblocking tty, never alter payload fd flags.
        // With no terminal, stay quiet; the shell still prints the final summary.
        let tty = ["/dev/tty", "/proc/self/fd/2"].iter().find_map(|path| {
            OpenOptions::new().write(true).custom_flags(O_NONBLOCK | O_CLOEXEC | 0o400)
                .open(path).ok().filter(|f| f.is_terminal())
        });
        let now = Instant::now();
        Self { tty, drawn: false, last_draw: now, sample_at: now, sample_bytes: 0,
            speed: 0.0, color: std::env::var("SPEEDBACKUP_STREAM_BENCH_COLOR")
                .ok().and_then(|s| s.parse::<u8>().ok()).unwrap_or(51) }
    }
    fn update(&mut self, total: u64, expected: u64, generate: bool) {
        if self.tty.is_none() || self.last_draw.elapsed() < Duration::from_millis(100) { return; }
        let now = Instant::now();
        let elapsed = now.duration_since(self.sample_at);
        if elapsed >= Duration::from_millis(500) || self.speed == 0.0 {
            self.speed = (total - self.sample_bytes) as f64 / 1048576.0 / elapsed.as_secs_f64();
            self.sample_at = now;
            self.sample_bytes = total;
        }
        let line = frame(total, expected, self.speed, generate, self.color);
        // A slow/full terminal drops a replaceable frame instead of slowing transfer.
        if let Some(tty) = &mut self.tty {
            if let Ok(n) = tty.write(line.as_bytes()) { self.drawn |= n > 0; }
        }
        self.last_draw = now;
    }
}
impl Drop for Progress {
    fn drop(&mut self) {
        if self.drawn {
            if let Some(tty) = &mut self.tty { let _ = tty.write(b"\r\x1b[0m\x1b[2K"); }
        }
    }
}

fn transfer<R: Read, W: Write>(mut input: R, mut output: W, expected: u64, generate: bool) -> io::Result<u64> {
    let mut buf = vec![0u8; 256 * 1024];
    let mut total = 0u64;
    let mut progress = Progress::new();
    loop {
        if generate && total == expected { break; }
        let limit = if generate { (expected - total).min(buf.len() as u64) as usize } else { buf.len() };
        let n = match input.read(&mut buf[..limit]) {
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            other => other?,
        };
        if n == 0 { break; }
        total = total.checked_add(n as u64).ok_or_else(|| io::Error::other("byte counter overflow"))?;
        if total > expected { return Err(io::Error::other("received more than expected")); }
        output.write_all(&buf[..n])?;
        progress.update(total, expected, generate);
    }
    output.flush()?;
    if total != expected { return Err(io::Error::new(io::ErrorKind::UnexpectedEof, format!("expected {expected}, received {total}"))); }
    Ok(total)
}

pub fn run(args: &[String]) -> i32 {
    if args.len() != 3 || !matches!(args[0].as_str(), "generate" | "drain") {
        eprintln!("stream-bench generate|drain BYTES RECEIPT"); return 2;
    }
    let expected = match args[1].parse::<u64>() { Ok(n) if n > 0 => n, _ => return 2 };
    let start = Instant::now();
    let result = if args[0] == "generate" {
        File::open("/dev/urandom").and_then(|f| transfer(f, io::stdout().lock(), expected, true))
    } else {
        transfer(io::stdin().lock(), io::sink(), expected, false)
    };
    match result {
        Ok(bytes) => match fs::write(&args[2], format!("{bytes}\t{}\n", start.elapsed().as_millis())) {
            Ok(()) => 0, Err(e) => { eprintln!("stream-bench receipt: {e}"); 1 }
        },
        Err(e) => { eprintln!("stream-bench: {e}"); 1 }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn terminal_frames_replace_one_line_without_payload_or_newlines() {
        let up = frame(2684354560, 5368709120, 174.7, true, 213);
        assert_eq!(up, "\r\x1b[38;5;213m -上傳 50.0% | 174.7 MiB/s\x1b[0m\x1b[K");
        let down = frame(5368709120, 5368709120, 231.8, false, 51);
        assert!(down.contains("下載 100.0%"));
        assert!(!up.contains('\n') && !down.contains('\n'));
    }
    #[test]
    fn exact_short_extra_and_bounded_generation() {
        assert_eq!(transfer(&b"abc"[..], io::sink(), 3, false).unwrap(), 3);
        assert!(transfer(&b"ab"[..], io::sink(), 3, false).is_err());
        assert!(transfer(&b"abcd"[..], io::sink(), 3, false).is_err());
        let mut out = Vec::new();
        assert_eq!(transfer(&b"abcdef"[..], &mut out, 3, true).unwrap(), 3);
        assert_eq!(out, b"abc");
    }
    #[test]
    fn five_gib_does_not_wrap() {
        assert_eq!(transfer(io::repeat(0), io::sink(), 5 * 1024 * 1024 * 1024, true).unwrap(), 5368709120);
    }
    #[test]
    fn broken_consumer_is_failure() {
        struct Broken;
        impl Write for Broken {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> { Err(io::ErrorKind::BrokenPipe.into()) }
            fn flush(&mut self) -> io::Result<()> { Ok(()) }
        }
        assert!(transfer(&b"abc"[..], Broken, 3, true).is_err());
    }
}
