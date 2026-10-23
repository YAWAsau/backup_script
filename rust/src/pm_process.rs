use std::io::{self, Read};
use std::os::fd::AsRawFd;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const OUTPUT_LIMIT: usize = 1024 * 1024;
pub(crate) const NOT_STARTED: i32 = -1;

pub(crate) fn seal_inherited_fds() -> io::Result<()> {
    unsafe extern "C" {
        fn fcntl(fd: i32, command: i32, ...) -> i32;
    }
    for entry in std::fs::read_dir("/proc/self/fd")? {
        let entry = entry?;
        let Some(descriptor) = entry
            .file_name()
            .to_str()
            .and_then(|name| name.parse::<i32>().ok())
        else {
            continue;
        };
        if descriptor < 3 {
            continue;
        }
        let flags = unsafe { fcntl(descriptor, 1) };
        if flags < 0 || unsafe { fcntl(descriptor, 2, flags | 1) } < 0 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

#[repr(C)]
struct PollFd {
    fd: i32,
    events: i16,
    revents: i16,
}

pub(crate) fn classify(
    mode: &str,
    code: i32,
    output: &[u8],
    complete: bool,
) -> (&'static str, String) {
    if !complete {
        return ("unknown", "-".into());
    }
    let Ok(text) = std::str::from_utf8(output) else {
        return ("unknown", "-".into());
    };
    if mode == "create" {
        let mut session = None;
        if code == 0 {
            for line in text.lines() {
                if line.starts_with("Failure [") {
                    return ("unknown", "-".into());
                }
                if let Some(value) = line
                    .strip_prefix("Success: created install session [")
                    .and_then(|value| value.strip_suffix(']'))
                {
                    if !value.is_empty()
                        && value.bytes().all(|byte| byte.is_ascii_digit())
                        && value.parse::<u32>().is_ok()
                    {
                        if session.replace(value.to_string()).is_some() {
                            return ("unknown", "-".into());
                        }
                    }
                }
            }
        }
        if let Some(session) = session {
            return ("created", session);
        }
        return ("unknown", "-".into());
    }
    let success = text.lines().any(|line| line == "Success");
    let failure = text
        .lines()
        .any(|line| line.starts_with("Failure [") && line.ends_with(']'));
    match (code, success, failure) {
        (0, true, false) => ("success", "-".into()),
        (1, false, true) => ("failure", "-".into()),
        _ => ("unknown", "-".into()),
    }
}

pub(crate) fn capture_command(
    mut command: Command,
    timeout: Duration,
) -> io::Result<(i32, Vec<u8>, bool)> {
    command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    unsafe {
        command.pre_exec(|| {
            unsafe extern "C" {
                fn setpgid(pid: i32, group: i32) -> i32;
            }
            if setpgid(0, 0) != 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut child = command.spawn()?;
    let mut stdout = child.stdout.take().unwrap();
    unsafe extern "C" {
        fn fcntl(fd: i32, command: i32, ...) -> i32;
        fn kill(pid: i32, signal: i32) -> i32;
        fn poll(fds: *mut PollFd, count: usize, timeout: i32) -> i32;
    }
    let flags = unsafe { fcntl(stdout.as_raw_fd(), 3) };
    if flags < 0 || unsafe { fcntl(stdout.as_raw_fd(), 4, flags | 0x800) } < 0 {
        unsafe {
            kill(-(child.id() as i32), 9);
        }
        let _ = child.wait();
        return Ok((125, Vec::new(), false));
    }
    let start = Instant::now();
    let mut output = Vec::new();
    let mut status = None;
    let mut eof = false;
    let mut complete = true;
    let mut buffer = [0u8; 8192];
    loop {
        for _ in 0..32 {
            match stdout.read(&mut buffer) {
                Ok(0) => {
                    eof = true;
                    break;
                }
                Ok(size) => {
                    let keep = size.min(OUTPUT_LIMIT.saturating_sub(output.len()));
                    output.extend_from_slice(&buffer[..keep]);
                    if keep != size {
                        complete = false;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::WouldBlock => break,
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(_) => {
                    complete = false;
                    eof = true;
                    break;
                }
            }
        }
        if status.is_none() {
            match child.try_wait() {
                Ok(value) => status = value,
                Err(_) => {
                    unsafe {
                        kill(-(child.id() as i32), 9);
                    }
                    let _ = child.wait();
                    return Ok((125, output, false));
                }
            }
        }
        if let Some(status) = status {
            if eof {
                return Ok((status.code().unwrap_or(125), output, complete));
            }
        }
        if start.elapsed() >= timeout {
            unsafe {
                kill(-(child.id() as i32), 9);
            }
            let _ = child.wait();
            return Ok((124, output, false));
        }
        let remaining = timeout.saturating_sub(start.elapsed()).as_millis().max(1);
        let mut descriptor = PollFd {
            fd: if eof { -1 } else { stdout.as_raw_fd() },
            events: 1,
            revents: 0,
        };
        unsafe {
            poll(
                &mut descriptor,
                1,
                remaining.min(if eof { 1 } else { 100 }) as i32,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inherited_descriptors_are_closed_on_exec() {
        unsafe extern "C" {
            fn pipe(descriptors: *mut i32) -> i32;
            fn fcntl(descriptor: i32, command: i32, ...) -> i32;
            fn close(descriptor: i32) -> i32;
        }
        let mut descriptors = [-1; 2];
        assert_eq!(unsafe { pipe(descriptors.as_mut_ptr()) }, 0);
        seal_inherited_fds().unwrap();
        for descriptor in descriptors {
            assert_eq!(unsafe { fcntl(descriptor, 1) } & 1, 1);
            unsafe {
                close(descriptor);
            }
        }
    }

    #[test]
    fn capture_faults_never_confirm_commit() {
        for (script, timeout) in [
            ("echo Success; sleep 2", 30),
            ("sleep 2 & echo Success", 30),
            ("echo Success; kill -9 $$", 1000),
            ("head -c 1100000 /dev/zero; echo Success", 3000),
        ] {
            let mut command = Command::new("/system/bin/sh");
            command.args(["-c", script]);
            let (status, output, complete) =
                capture_command(command, Duration::from_millis(timeout)).unwrap();
            assert_eq!(classify("commit", status, &output, complete).0, "unknown");
        }
        assert!(capture_command(
            Command::new("/nonexistent/speedbackup-test"),
            Duration::from_secs(1)
        )
        .is_err());
    }

    #[test]
    fn capture_keeps_arguments_and_stdin_isolated() {
        let mut command = Command::new("/system/bin/sh");
        command.args([
            "-c",
            "[ \"$1\" = 'a b;*' ] && [ \"$2\" = '' ] && ! read value && echo Success",
            "_",
            "a b;*",
            "",
        ]);
        let (status, output, complete) = capture_command(command, Duration::from_secs(1)).unwrap();
        assert_eq!(classify("commit", status, &output, complete).0, "success");
    }

    #[test]
    fn commit_requires_consistent_terminal_evidence() {
        for (code, output, complete, expected) in [
            (0, "Success\n", true, "success"),
            (0, "Success\r\n", true, "success"),
            (1, "Failure [denied]\n", true, "failure"),
            (124, "Success\n", true, "unknown"),
            (0, "Success\nFailure [bad]\n", true, "unknown"),
            (0, "", true, "unknown"),
            (1, "Failure [bad]\n", false, "unknown"),
            (127, "Failure [bad]\n", true, "unknown"),
        ] {
            assert_eq!(
                classify("commit", code, output.as_bytes(), complete).0,
                expected
            );
        }
    }

    #[test]
    fn create_requires_success_and_valid_session() {
        assert_eq!(
            classify(
                "create",
                0,
                b"Success: created install session [42]\n",
                true
            ),
            ("created", "42".into())
        );
        for output in [
            b"error [42]".as_slice(),
            b"Success: created install session [4294967296]",
            b"Success: created install session []",
            b"Success: created install session [42]\nFailure [bad]",
            b"Success: created install session [42]\nSuccess: created install session [43]",
        ] {
            assert_eq!(classify("create", 0, output, true).0, "unknown");
        }
        assert_eq!(
            classify("create", 1, b"Success: created install session [42]", true).0,
            "unknown"
        );
    }
}
