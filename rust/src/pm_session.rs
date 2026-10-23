use std::ffi::OsString;
use std::io::{self, Write};
use std::process::Command;
use std::time::Duration;

type Reply = (i32, Vec<u8>, bool);

fn execute(
    apks: &[String],
    create: Vec<String>,
    run: &mut impl FnMut(&str, &[String]) -> Reply,
    gate: &mut impl FnMut(&str) -> bool,
) -> (&'static str, String) {
    let reply = run("create", &create);
    let (outcome, session) = crate::pm_process::classify("create", reply.0, &reply.1, reply.2);
    if outcome != "created" {
        return ("precommit_failure", "-".into());
    }
    for (index, apk) in apks.iter().enumerate() {
        let args = vec![
            "install-write".into(),
            session.clone(),
            format!("part_{index}"),
            apk.clone(),
        ];
        let reply = run("write", &args);
        if reply.0 != 0 || !reply.2 {
            run("abandon", &["install-abandon".into(), session.clone()]);
            return ("precommit_failure", session);
        }
    }
    if !gate(&session) {
        run("abandon", &["install-abandon".into(), session.clone()]);
        return ("precommit_failure", session);
    }
    let reply = run("commit", &["install-commit".into(), session.clone()]);
    if reply.0 == crate::pm_process::NOT_STARTED {
        run("abandon", &["install-abandon".into(), session.clone()]);
        return ("precommit_failure", session);
    }
    let (outcome, _) = crate::pm_process::classify("commit", reply.0, &reply.1, reply.2);
    if outcome == "failure" {
        run("abandon", &["install-abandon".into(), session.clone()]);
    }
    (outcome, session)
}

fn commit_gate(session: &str) -> bool {
    let mut output = io::stdout().lock();
    if writeln!(output, "READY {session}")
        .and_then(|_| output.flush())
        .is_err()
    {
        return false;
    }
    drop(output);
    read_gate(0, session, Duration::from_secs(300))
}

fn read_gate(input: i32, session: &str, timeout: Duration) -> bool {
    #[repr(C)]
    struct PollFd {
        fd: i32,
        events: i16,
        revents: i16,
    }
    unsafe extern "C" {
        fn poll(fds: *mut PollFd, count: usize, timeout: i32) -> i32;
        fn read(fd: i32, buffer: *mut std::ffi::c_void, count: usize) -> isize;
    }
    let started = std::time::Instant::now();
    let mut line = Vec::new();
    while line.len() < 128 {
        let remaining = timeout.saturating_sub(started.elapsed()).as_millis();
        if remaining == 0 {
            return false;
        }
        let mut descriptor = PollFd {
            fd: input,
            events: 1,
            revents: 0,
        };
        if unsafe { poll(&mut descriptor, 1, remaining as i32) } <= 0 {
            return false;
        }
        let mut byte = 0u8;
        if unsafe { read(input, (&mut byte as *mut u8).cast(), 1) } != 1 {
            return false;
        }
        line.push(byte);
        if byte == b'\n' {
            return line == format!("COMMIT {session}\n").as_bytes();
        }
    }
    false
}

fn is_plain_pm_wrapper(contents: &[u8]) -> bool {
    contents == b"#!/system/bin/sh\ncmd package \"$@\"\n"
}

fn direct_package_command() -> bool {
    use std::io::Read;
    use std::os::unix::fs::PermissionsExt;
    let Ok(file) = std::fs::File::open("/system/bin/pm") else {
        return false;
    };
    let mut contents = Vec::new();
    if file.take(128).read_to_end(&mut contents).is_err() || !is_plain_pm_wrapper(&contents) {
        return false;
    }
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    for directory in std::env::split_paths(&path) {
        let candidate = directory.join("cmd");
        match std::fs::metadata(&candidate) {
            Ok(metadata) if metadata.is_file() && metadata.permissions().mode() & 0o111 != 0 => {
                return candidate == std::path::Path::new("/system/bin/cmd");
            }
            Ok(_) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(_) => return false,
        }
    }
    false
}

pub(crate) fn run(argv: Vec<OsString>) {
    if let Err(error) = crate::pm_process::seal_inherited_fds() {
        eprintln!("pm-session: inherited descriptors: {error}");
        std::process::exit(2);
    }
    let args: Vec<_> = argv.iter().map(|value| value.to_str()).collect();
    if args.len() < 7 || args.iter().any(|value| value.is_none()) {
        eprintln!("usage: --pm-session user play-uid play-data-dir classpath bypass-0-or-1 legacy-0-or-1 apk...");
        std::process::exit(2);
    }
    let args: Vec<&str> = args.into_iter().map(Option::unwrap).collect();
    let user = args[0].parse::<u32>().unwrap_or(u32::MAX);
    let uid = args[1].parse::<u32>().unwrap_or(0);
    if uid / 100000 != user
        || uid % 100000 < 10000
        || uid.to_string() != args[1]
        || user.to_string() != args[0]
        || !matches!(args[4], "0" | "1")
        || !matches!(args[5], "0" | "1")
        || args[2] != format!("/data/user/{user}/com.android.vending")
        || args[6..].iter().any(|path| {
            !std::path::Path::new(path).is_absolute() || !std::path::Path::new(path).is_file()
        })
    {
        eprintln!("pm-session: invalid identity or APK input");
        std::process::exit(2);
    }
    let mut create = vec![
        "install-create".into(),
        "-r".into(),
        "-t".into(),
        "--user".into(),
        user.to_string(),
        "-i".into(),
        "com.android.vending".into(),
    ];
    if args[4] == "1" {
        create.push("--bypass-low-target-sdk-block".into());
    }
    if args[5] == "1" {
        create.push("-l".into());
    }
    let apks: Vec<String> = args[6..].iter().map(|value| value.to_string()).collect();
    let split = apks.len() > 1;
    let direct = split && direct_package_command();
    if split {
        eprintln!("PM_SESSION route={}", if direct { "cmd-package" } else { "pm" });
    }
    let precommit_started = std::time::Instant::now();
    let mut runner = |stage: &str, command_args: &[String]| {
        let mut command = Command::new(if direct { "/system/bin/cmd" } else { "/system/bin/pm" });
        if direct {
            command.arg("package");
        }
        command.args(command_args);
        if matches!(stage, "create" | "commit") {
            if let Err(error) =
                crate::uidexec::prepare_pm_command(&mut command, uid, args[2], args[3])
            {
                eprintln!("PM_SESSION stage={stage} not_started=true error={error}");
                return (crate::pm_process::NOT_STARTED, Vec::new(), false);
            }
        }
        let started = std::time::Instant::now();
        let timeout = match stage {
            "create" | "write" => {
                Duration::from_secs(300).saturating_sub(precommit_started.elapsed())
            }
            "abandon" => Duration::from_secs(30),
            _ => Duration::from_secs(300),
        };
        if timeout.is_zero() {
            return (124, Vec::new(), false);
        }
        let reply = crate::pm_process::capture_command(command, timeout).unwrap_or_else(|error| {
            eprintln!("PM_SESSION stage={stage} not_started=true error={error}");
            (crate::pm_process::NOT_STARTED, Vec::new(), false)
        });
        eprintln!(
            "PM_SESSION stage={stage} rc={} complete={} ms={} output={}",
            reply.0,
            reply.2,
            started.elapsed().as_millis(),
            String::from_utf8_lossy(&reply.1)
        );
        reply
    };
    let (outcome, session) = execute(&apks, create, &mut runner, &mut commit_gate);
    let _ = writeln!(io::stdout().lock(), "RESULT {outcome} {session}");
    std::process::exit(match outcome {
        "success" => 0,
        "unknown" => 75,
        _ => 1,
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    use std::os::{fd::AsRawFd, unix::net::UnixStream};

    #[test]
    fn only_plain_pm_wrapper_can_bypass_shell() {
        assert!(is_plain_pm_wrapper(b"#!/system/bin/sh\ncmd package \"$@\"\n"));
        for contents in [
            &b"#!/system/bin/sh\ncmd package \"$@\"; echo extra\n"[..],
            &b"#!/system/bin/sh\nexec cmd package \"$@\"\n"[..],
            &b"#!/system/bin/sh\nCLASSPATH=/custom cmd package \"$@\"\n"[..],
            &b"#!/system/bin/sh\ncmd package \"$@\"\n# vendor hook\n"[..],
            &b"#!/system/bin/sh\r\ncmd package \"$@\"\r\n"[..],
            &b""[..],
        ] {
            assert!(!is_plain_pm_wrapper(contents));
        }
    }

    #[cfg(unix)]
    #[test]
    fn gate_requires_exact_complete_matching_approval() {
        for (request, expected) in [
            ("COMMIT 42\n", true),
            ("COMMIT 43\n", false),
            ("COMMIT 42", false),
            ("ABORT\n", false),
            ("", false),
            ("COMMIT 42 extra\n", false),
        ] {
            let (input, mut output) = UnixStream::pair().unwrap();
            output.write_all(request.as_bytes()).unwrap();
            drop(output);
            assert_eq!(
                read_gate(input.as_raw_fd(), "42", Duration::from_secs(1)),
                expected
            );
        }
        let (input, mut output) = UnixStream::pair().unwrap();
        output.write_all(&[b'x'; 129]).unwrap();
        assert!(!read_gate(input.as_raw_fd(), "42", Duration::from_secs(1)));
    }

    #[cfg(unix)]
    #[test]
    fn gate_timeout_does_not_approve_partial_or_empty_input() {
        for request in ["", "COMMIT 42"] {
            let (input, mut output) = UnixStream::pair().unwrap();
            output.write_all(request.as_bytes()).unwrap();
            assert!(!read_gate(
                input.as_raw_fd(),
                "42",
                Duration::from_millis(20)
            ));
        }
    }

    fn scenario(commit: Reply, write_fail: bool, approve: bool) -> (&'static str, Vec<String>) {
        let mut stages = Vec::new();
        let mut runner = |stage: &str, _: &[String]| {
            stages.push(stage.to_string());
            match stage {
                "create" => (0, b"Success: created install session [42]\n".to_vec(), true),
                "write" if write_fail => (1, Vec::new(), true),
                "commit" => commit.clone(),
                _ => (0, Vec::new(), true),
            }
        };
        let result = execute(
            &["/base.apk".into(), "/split.apk".into()],
            Vec::new(),
            &mut runner,
            &mut |_| approve,
        );
        (result.0, stages)
    }

    #[test]
    fn unknown_never_retries_or_abandons() {
        for reply in [
            (124, b"Success\n".to_vec(), false),
            (127, Vec::new(), true),
            (0, Vec::new(), true),
        ] {
            let (outcome, stages) = scenario(reply, false, true);
            assert_eq!(outcome, "unknown");
            assert_eq!(stages, ["create", "write", "write", "commit"]);
        }
    }

    #[test]
    fn definite_results_and_precommit_cleanup() {
        assert_eq!(
            scenario(
                (crate::pm_process::NOT_STARTED, Vec::new(), false),
                false,
                true
            ),
            (
                "precommit_failure",
                vec![
                    "create".into(),
                    "write".into(),
                    "write".into(),
                    "commit".into(),
                    "abandon".into()
                ]
            )
        );
        assert_eq!(
            scenario((0, b"Success\n".to_vec(), true), false, true).0,
            "success"
        );
        assert_eq!(
            scenario((1, b"Failure [denied]\n".to_vec(), true), false, true),
            (
                "failure",
                vec![
                    "create".into(),
                    "write".into(),
                    "write".into(),
                    "commit".into(),
                    "abandon".into()
                ]
            )
        );
        assert_eq!(
            scenario((0, Vec::new(), true), true, true).1,
            ["create", "write", "abandon"]
        );
        assert_eq!(
            scenario((0, Vec::new(), true), false, false).1,
            ["create", "write", "write", "abandon"]
        );
    }

    #[test]
    fn invalid_create_never_writes_or_commits() {
        for reply in [
            (1, b"Failure [denied]\n".to_vec(), true),
            (
                0,
                b"Success: created install session [42]\n".to_vec(),
                false,
            ),
            (0, b"noise [42]\n".to_vec(), true),
        ] {
            let mut calls = Vec::new();
            let outcome = execute(
                &["/base.apk".into()],
                Vec::new(),
                &mut |stage, _| {
                    calls.push(stage.to_string());
                    reply.clone()
                },
                &mut |_| panic!("gate must not be reached"),
            );
            assert_eq!(outcome.0, "precommit_failure");
            assert_eq!(calls, ["create"]);
        }
    }

    #[test]
    fn contradictory_or_truncated_commit_is_unknown() {
        for reply in [
            (0, b"Success\nFailure [bad]\n".to_vec(), true),
            (0, b"Success\n".to_vec(), false),
            (1, b"Failure [denied]\n".to_vec(), false),
            (137, b"Success\n".to_vec(), true),
        ] {
            let (outcome, calls) = scenario(reply, false, true);
            assert_eq!(outcome, "unknown");
            assert!(!calls.iter().any(|stage| stage == "abandon"));
        }
    }
}
