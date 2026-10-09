//! One process for the three post-install cache mutations. Inputs are fresh
//! PackageManager facts; this operation never caches or discovers an Android UID.
//! Numeric maps deliberately retain the shell's in-place (not rename) writes.
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::Path;

#[derive(Debug, PartialEq, Eq)]
enum State {
    Same,
    Updated,
    Skipped,
    Error,
}
impl State {
    fn name(&self) -> &'static str {
        match self {
            Self::Same => "same",
            Self::Updated => "updated",
            Self::Skipped => "skipped",
            Self::Error => "error",
        }
    }
}

enum Snapshot {
    Data(Vec<u8>),
    Missing,
    Unreadable,
    NonRegular,
    Skipped,
}

fn digits(value: &[u8]) -> bool {
    !value.is_empty() && value.iter().all(u8::is_ascii_digit)
}

fn safe_package(value: &[u8]) -> bool {
    // Android package names fall in this domain. Other legacy inputs can have
    // awk -v escape/numeric-comparison semantics, so decline before mutation.
    matches!(value.first(), Some(b'a'..=b'z' | b'A'..=b'Z' | b'_'))
        && value.iter().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_'))
}

fn snapshot(path: &Path, enabled: bool) -> Snapshot {
    if !enabled {
        return Snapshot::Skipped;
    }
    match fs::metadata(path) {
        Ok(meta) if !meta.is_file() => Snapshot::NonRegular,
        Ok(_) => match fs::read(path) {
            Ok(data) => Snapshot::Data(data),
            Err(_) => Snapshot::Unreadable,
        },
        Err(e) if e.kind() == io::ErrorKind::NotFound => Snapshot::Missing,
        Err(_) => Snapshot::Unreadable,
    }
}

fn records(data: &[u8]) -> impl Iterator<Item = &[u8]> {
    // A terminating LF ends the last record; it does not add another one.
    let end = data.len() - usize::from(data.last() == Some(&b'\n'));
    data[..end].split(|b| *b == b'\n').take(if data.is_empty() { 0 } else { usize::MAX })
}

fn canonical_match(data: &[u8], package: &[u8], value: &[u8]) -> bool {
    if data.last() != Some(&b'\n') {
        return false;
    }
    let mut found = false;
    for row in records(data) {
        let Some(tab) = row.iter().position(|b| *b == b'\t') else { return false };
        let (key, rest) = (&row[..tab], &row[tab + 1..]);
        if key.is_empty()
            || !key.iter().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_'))
            || !digits(rest)
        {
            return false;
        }
        if key == package {
            if found || rest != value {
                return false;
            }
            found = true;
        }
    }
    found
}

fn numeric_body(data: &[u8], package: &[u8], value: &[u8]) -> Vec<u8> {
    let mut body = Vec::with_capacity(data.len() + package.len() + value.len() + 2);
    for row in records(data) {
        let key = row.split(|b| *b == b'\t').next().unwrap_or_default();
        if key != package {
            body.extend_from_slice(row);
            body.push(b'\n'); // awk print also terminates unterminated input.
        }
    }
    body.extend_from_slice(package);
    body.push(b'\t');
    body.extend_from_slice(value);
    body.push(b'\n');
    body
}

fn numeric_update(path: &Path, input: Snapshot, package: &[u8], value: &[u8]) -> State {
    let data = match input {
        Snapshot::Skipped => return State::Skipped,
        Snapshot::NonRegular | Snapshot::Unreadable => return State::Error,
        Snapshot::Missing => Vec::new(),
        Snapshot::Data(data) => data,
    };
    if canonical_match(&data, package, value) {
        return State::Same;
    }
    let body = numeric_body(&data, package, value);
    // Matches `cat temp > map`: preserve inode, mode, hard links and symlink
    // target; do not replace the directory entry with a newly owned file.
    match OpenOptions::new().write(true).create(true).truncate(true).open(path)
        .and_then(|mut file| file.write_all(&body))
    {
        Ok(()) => State::Updated,
        Err(_) => State::Error,
    }
}

fn installed_update(path: &Path, input: Snapshot, package: &[u8]) -> State {
    match input {
        Snapshot::Data(data) if records(&data).any(|row| row == package) => return State::Same,
        Snapshot::NonRegular | Snapshot::Skipped => return State::Error,
        _ => {}
    }
    // The old read loop's failure is best effort: a write-only regular list can
    // still accept the append. Deliberately do not insert a missing prior LF.
    match OpenOptions::new().append(true).create(true).open(path).and_then(|mut file| {
        file.write_all(package)?;
        file.write_all(b"\n")
    }) {
        Ok(()) => State::Updated,
        Err(_) => State::Error,
    }
}

fn apply(root: &Path, package: &str, uid: &str, version: &str) -> Result<[State; 3], ()> {
    if root.as_os_str().is_empty() || !safe_package(package.as_bytes()) {
        return Err(());
    }
    let paths = [root.join(".pkg_uid"), root.join(".pkg_ver"), root.join(".installed_pkgs")];
    let inputs = [snapshot(&paths[0], digits(uid.as_bytes())),
                  snapshot(&paths[1], digits(version.as_bytes())), snapshot(&paths[2], true)];
    // mksh/awk binary-string behavior is intentionally kept in the legacy path.
    // Examine all relevant inputs before changing even the first map.
    if inputs.iter().any(|input| matches!(input, Snapshot::Data(data) if data.contains(&0))) {
        return Err(());
    }
    let [uid_input, version_input, installed_input] = inputs;
    Ok([numeric_update(&paths[0], uid_input, package.as_bytes(), uid.as_bytes()),
        numeric_update(&paths[1], version_input, package.as_bytes(), version.as_bytes()),
        installed_update(&paths[2], installed_input, package.as_bytes())])
}

pub fn command(args: &[String]) -> i32 {
    if args.len() != 6 {
        eprintln!("speedscan restore-package-maps ROOT PACKAGE UID VERSION");
        return 2;
    }
    match apply(Path::new(&args[2]), &args[3], &args[4], &args[5]) {
        Err(()) => 125, // unsupported legacy bytes; no file has been changed
        Ok(states) => {
            println!("SBRESULT\t1\tpackage-maps\t{}\t{}\t{}",
                     states[0].name(), states[1].name(), states[2].name());
            for (name, state) in ["uid", "version", "installed"].iter().zip(&states) {
                if *state == State::Error {
                    eprintln!("RESTORE_PACKAGE_MAP_UPDATE_ERROR map={name} policy=best-effort");
                }
            }
            // The old caller individually ignored map errors. Always attempt
            // all three and preserve the successful install's return code.
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};
    static SEQ: AtomicUsize = AtomicUsize::new(0);
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
            let root = std::env::temp_dir().join(format!("sb-package-maps-{}-{stamp}-{}", std::process::id(), SEQ.fetch_add(1, Ordering::Relaxed)));
            fs::create_dir(&root).unwrap();
            Self(root)
        }
        fn put(&self, name: &str, body: &[u8]) { fs::write(self.0.join(name), body).unwrap(); }
        fn get(&self, name: &str) -> Vec<u8> { fs::read(self.0.join(name)).unwrap() }
    }
    impl Drop for Temp { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }

    #[test]
    fn numeric_rows_match_awk_print_and_dedup() {
        let cases: &[(&[u8], &[u8])] = &[
            (b"", b"app.test\t003\n"),
            (b"app.test\t1\nother\t2\napp.test\t4\n", b"other\t2\napp.test\t003\n"),
            (b"other\t2", b"other\t2\napp.test\t003\n"),
            (b"\nodd\n\tblank\tfield\n", b"\nodd\n\tblank\tfield\napp.test\t003\n"),
            (b"other\t2\r\napp.test\t4\r\n", b"other\t2\r\napp.test\t003\n"),
            (b"app.test\t3\textra", b"app.test\t003\n"),
            (b"prefix.app.test\t7\n", b"prefix.app.test\t7\napp.test\t003\n"),
        ];
        for (input, expected) in cases { assert_eq!(numeric_body(input, b"app.test", b"003"), *expected); }
    }

    #[test]
    fn exact_noop_requires_canonical_entire_file() {
        assert!(canonical_match(b"other\t0002\napp.test\t003\n", b"app.test", b"003"));
        for data in [&b"app.test\t003"[..], b"app.test\t3\n", b"app.test\t003\napp.test\t003\n",
                     b"app.test\t003\n\n", b"app.test\t003\ninvalid-key\t2\n", b"app.test\t003\nother\t1\t2\n"] {
            assert!(!canonical_match(data, b"app.test", b"003"));
        }
    }

    #[test]
    fn missing_files_and_invalid_numbers_keep_individual_contracts() {
        let t = Temp::new();
        assert_eq!(apply(&t.0, "app.test", "-1", ""), Ok([State::Skipped, State::Skipped, State::Updated]));
        assert!(!t.0.join(".pkg_uid").exists()); assert!(!t.0.join(".pkg_ver").exists());
        assert_eq!(t.get(".installed_pkgs"), b"app.test\n");
        assert_eq!(apply(&t.0, "app.test", "00042", "99999999999999999999999"), Ok([State::Updated, State::Updated, State::Same]));
        assert_eq!(t.get(".pkg_uid"), b"app.test\t00042\n");
    }

    #[test]
    fn installed_unterminated_and_duplicates_are_not_normalized() {
        for (input, expected) in [(&b"other"[..], &b"otherapp.test\n"[..]),
                                 (b"app.test", b"app.test"),
                                 (b"app.test\napp.test\n", b"app.test\napp.test\n"),
                                 (b"app.test\r\n", b"app.test\r\napp.test\n")] {
            let t = Temp::new(); t.put(".installed_pkgs", input);
            apply(&t.0, "app.test", "", "").unwrap();
            assert_eq!(t.get(".installed_pkgs"), expected);
        }
    }

    #[test]
    fn errors_are_independent_and_no_special_file_is_opened() {
        let t = Temp::new(); fs::create_dir(t.0.join(".pkg_uid")).unwrap();
        assert_eq!(apply(&t.0, "app.test", "5", "6"), Ok([State::Error, State::Updated, State::Updated]));
        assert_eq!(t.get(".pkg_ver"), b"app.test\t6\n");
        let missing = t.0.join("missing-parent");
        assert_eq!(apply(&missing, "app.test", "5", "6"), Ok([State::Error, State::Error, State::Error]));
    }

    #[test]
    fn unsupported_inputs_do_not_partially_update() {
        let t = Temp::new(); t.put(".pkg_uid", b"old\t1\n"); t.put(".pkg_ver", b"bad\0\n");
        assert_eq!(apply(&t.0, "app.test", "5", "6"), Err(()));
        assert_eq!(t.get(".pkg_uid"), b"old\t1\n");
        for pkg in ["", "123", "bad\\tkey", "a\nb", "a-b", "測試"] {
            assert_eq!(apply(&t.0, pkg, "5", "6"), Err(()));
        }
    }

    #[cfg(unix)]
    #[test]
    fn in_place_updates_preserve_inode_mode_and_symlink() {
        use std::os::unix::fs::{MetadataExt, PermissionsExt, symlink};
        let t = Temp::new(); t.put("uid.target", b"app.test\t1\n");
        let target = t.0.join("uid.target"); fs::set_permissions(&target, fs::Permissions::from_mode(0o640)).unwrap();
        symlink(&target, t.0.join(".pkg_uid")).unwrap();
        let old = fs::metadata(&target).unwrap();
        apply(&t.0, "app.test", "2", "3").unwrap();
        let new = fs::metadata(&target).unwrap();
        assert_eq!(old.ino(), new.ino()); assert_eq!(old.mode(), new.mode());
        assert!(fs::symlink_metadata(t.0.join(".pkg_uid")).unwrap().file_type().is_symlink());
        assert_eq!(t.get("uid.target"), b"app.test\t2\n");
        let stamp = new.modified().unwrap();
        assert_eq!(apply(&t.0, "app.test", "2", "3").unwrap()[0], State::Same);
        assert_eq!(fs::metadata(&target).unwrap().modified().unwrap(), stamp);
    }
}
