//! Delivery for optional terminal text, kept separate from replaceable tar frames.
//! A tty has no atomic-message guarantee. Short writes must be continued, and a
//! deadline after partial progress must be reported rather than called success.
use std::io::{self, Read, Write};
use std::time::{Duration, Instant};

pub(super) const RETRY_LIMIT: Duration = Duration::from_millis(250);
pub(super) const DROPPED: i32 = 75;
pub(super) const PARTIAL: i32 = 76;

fn failure(written: usize) -> i32 { if written == 0 { DROPPED } else { PARTIAL } }

struct Counted<'a, W> { out: &'a mut W, written: usize }
impl<W: Write> Write for Counted<'_, W> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        let n = self.out.write(bytes)?;
        self.written = self.written.saturating_add(n);
        Ok(n)
    }
    fn flush(&mut self) -> io::Result<()> { self.out.flush() }
}

/// The budget covers all writes/retries of this message, after stdin is read.
/// `wait` waits for the separately opened nonblocking tty to become writable.
fn write_message<W, F>(out: &mut W, bytes: &[u8], limit: Duration, mut wait: F) -> i32
where W: Write, F: FnMut(Duration) -> io::Result<()> {
    let deadline = Instant::now() + limit;
    let mut written = 0;
    while written < bytes.len() {
        if Instant::now() >= deadline { return failure(written); }
        match out.write(&bytes[written..]) {
            Ok(0) => return failure(written),
            Ok(n) => written += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                let remaining = deadline.saturating_duration_since(Instant::now());
                if remaining.is_zero() { return failure(written); }
                match wait(remaining) {
                    Ok(()) => {},
                    Err(e) if e.kind() == io::ErrorKind::Interrupted => {},
                    Err(_) => return failure(written),
                }
            },
            Err(_) => return failure(written),
        }
    }
    0
}

/// Reopen failure is an ordinary blocking stdout fallback, including when fd 1
/// was redirected to a pipe/file. Read to EOF without the old silent 1 MiB cap.
pub(super) fn deliver<R, W, B, F>(input: &mut R, target: io::Result<W>, fallback: &mut B,
                                limit: Duration, wait: F) -> i32
where R: Read, W: Write, B: Write, F: FnMut(Duration) -> io::Result<()> {
    let mut out = match target {
        Ok(out) => out,
        Err(_) => {
            let mut counted = Counted { out: fallback, written: 0 };
            let result = io::copy(input, &mut counted).and_then(|_| counted.flush());
            return if result.is_ok() { 0 } else { failure(counted.written) };
        },
    };
    let mut bytes = Vec::new();
    if input.read_to_end(&mut bytes).is_err() { return DROPPED; }
    write_message(&mut out, &bytes, limit, wait)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

    enum Step { Bytes(usize), Again, Interrupted, Error, Zero }
    struct Writer { steps: VecDeque<Step>, bytes: Vec<u8>, blocked: bool }
    impl Writer {
        fn new(steps: Vec<Step>, blocked: bool) -> Self {
            Self { steps: steps.into(), bytes: vec![], blocked }
        }
    }
    impl Write for Writer {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            match self.steps.pop_front() {
                Some(Step::Again) => Err(io::ErrorKind::WouldBlock.into()),
                Some(Step::Interrupted) => Err(io::ErrorKind::Interrupted.into()),
                Some(Step::Error) => Err(io::ErrorKind::BrokenPipe.into()),
                Some(Step::Zero) => Ok(0),
                Some(Step::Bytes(n)) => {
                    let n = n.min(bytes.len()); self.bytes.extend_from_slice(&bytes[..n]); Ok(n)
                },
                None if self.blocked => Err(io::ErrorKind::WouldBlock.into()),
                None => { self.bytes.extend_from_slice(bytes); Ok(bytes.len()) },
            }
        }
        fn flush(&mut self) -> io::Result<()> { Ok(()) }
    }

    #[test]
    fn full_buffer_resumes_and_completes_whole_message_without_duplication() {
        let message = "完整選項一\n完整選項二\n離開\n".as_bytes();
        let mut writer = Writer::new(vec![Step::Again, Step::Bytes(5), Step::Again,
                                         Step::Bytes(1), Step::Interrupted], false);
        let mut waits = 0;
        let rc = write_message(&mut writer, message, RETRY_LIMIT, |_| { waits += 1; Ok(()) });
        assert_eq!(rc, 0);
        assert_eq!(writer.bytes, message);
        assert_eq!(waits, 2);
    }

    #[test]
    fn full_buffer_that_never_resumes_drops_zero_bytes_and_reports_it() {
        let mut writer = Writer::new(vec![], true);
        let start = Instant::now();
        let rc = write_message(&mut writer, b"whole message\n", Duration::from_millis(15),
                               |remaining| { std::thread::sleep(remaining); Ok(()) });
        assert_eq!(rc, DROPPED);
        assert!(writer.bytes.is_empty());
        assert!(start.elapsed() < Duration::from_secs(1));
    }

    #[test]
    fn partial_timeout_is_explicit_and_never_mistaken_for_success() {
        let mut writer = Writer::new(vec![Step::Bytes(4)], true);
        let rc = write_message(&mut writer, b"whole message\n", Duration::from_millis(15),
                               |remaining| { std::thread::sleep(remaining); Ok(()) });
        assert_eq!(rc, PARTIAL);
        assert_eq!(writer.bytes, b"whol");
    }

    #[test]
    fn reopen_failure_copies_stdin_to_stdout_without_old_megabyte_cap() {
        let bytes = vec![b'x'; 1024 * 1024 + 37];
        let mut stdout = Vec::new();
        let unavailable: io::Result<Vec<u8>> = Err(io::ErrorKind::NotFound.into());
        let rc = deliver(&mut bytes.as_slice(), unavailable, &mut stdout, RETRY_LIMIT,
                         |_| panic!("fallback must not poll the missing tty"));
        assert_eq!(rc, 0);
        assert_eq!(stdout, bytes);
    }

    #[test]
    fn successful_tty_delivery_does_not_silently_truncate_large_input() {
        let bytes = vec![b'y'; 1024 * 1024 + 37];
        let mut tty = Vec::new();
        let mut stdout = Vec::new();
        assert_eq!(deliver(&mut bytes.as_slice(), Ok(&mut tty), &mut stdout,
                           RETRY_LIMIT, |_| Ok(())), 0);
        assert_eq!(tty, bytes);
        assert!(stdout.is_empty());
    }

    #[test]
    fn fallback_partial_error_is_also_reported() {
        let mut stdout = Writer::new(vec![Step::Bytes(3), Step::Error], false);
        let unavailable: io::Result<Vec<u8>> = Err(io::ErrorKind::PermissionDenied.into());
        assert_eq!(deliver(&mut b"message".as_slice(), unavailable, &mut stdout,
                           RETRY_LIMIT, |_| Ok(())), PARTIAL);
        assert_eq!(stdout.bytes, b"mes");
    }

    #[test]
    fn fallback_flushes_non_newline_text_and_reports_flush_failure() {
        struct Buffered { flushed: bool }
        impl Write for Buffered {
            fn write(&mut self, bytes: &[u8]) -> io::Result<usize> { Ok(bytes.len()) }
            fn flush(&mut self) -> io::Result<()> {
                self.flushed = true;
                Err(io::ErrorKind::BrokenPipe.into())
            }
        }
        let mut stdout = Buffered { flushed: false };
        let unavailable: io::Result<Vec<u8>> = Err(io::ErrorKind::NotFound.into());
        assert_eq!(deliver(&mut b"prompt: ".as_slice(), unavailable, &mut stdout,
                           RETRY_LIMIT, |_| Ok(())), PARTIAL);
        assert!(stdout.flushed);
    }

    #[test]
    fn write_zero_and_hard_error_report_delivery_failure() {
        for first in [Step::Zero, Step::Error] {
            let mut writer = Writer::new(vec![first], false);
            assert_eq!(write_message(&mut writer, b"text", RETRY_LIMIT, |_| Ok(())), DROPPED);
        }
        let mut writer = Writer::new(vec![Step::Bytes(1), Step::Error], false);
        assert_eq!(write_message(&mut writer, b"text", RETRY_LIMIT, |_| Ok(())), PARTIAL);
    }
}
