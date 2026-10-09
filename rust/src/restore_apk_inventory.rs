//! A request-local APK inventory emitted by the existing payload-plan pass.
//! It is an optimization receipt, never a substitute for source verification.
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::Path;
#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;

pub const SCHEMA: &str = "#schema\tspeedbackup.restore_apk_inventory.v1";

pub fn begin(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn token(value: &str) -> bool {
    !value.is_empty() && !value.bytes().any(|b| matches!(b, 0 | b'\t' | b'\r' | b'\n'))
}

pub fn render(stage: &str, entries: &[(String, u64)]) -> io::Result<String> {
    if !token(stage) {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "stage is not TSV-safe"));
    }
    let mut items = entries.to_vec();
    items.sort_by(|a, b| a.0.cmp(&b.0));
    let mut bytes = 0u64;
    let mut main_count = 0usize;
    let mut nmsl = "";
    let mut last = None;
    for (name, size) in &items {
        // Android shell *.apk does not include dotfiles. Unsafe names keep the
        // legacy glob path instead of silently sanitizing an install filename.
        if !token(name) || name.contains('/') || name.starts_with('.') || !name.ends_with(".apk") || last == Some(name) {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid APK inventory name"));
        }
        bytes = bytes.checked_add(*size).ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "APK size overflow"))?;
        if name == "nmsl.apk" { nmsl = "nmsl.apk"; } else { main_count += 1; }
        last = Some(name);
    }
    let mut body = format!("{}\nOK\t{}\t{}\t{}\t{}\t{}\n", SCHEMA, stage, items.len(), main_count, bytes, nmsl);
    for (name, size) in &items {
        body.push_str(&format!("FILE\t{}\t{}\n", name, size));
    }
    Ok(body)
}

pub fn publish(path: &Path, stage: &str, entries: &[(String, u64)]) -> io::Result<()> {
    // The caller removes an old receipt before scanning, including on errors.
    let body = render(stage, entries)?;
    let temp = path.with_extension("tsv.tmp");
    let result = (|| {
        let mut options = OpenOptions::new();
        options.write(true).create(true).truncate(true);
        #[cfg(unix)]
        options.mode(0o600);
        let mut file = options.open(&temp)?;
        file.write_all(body.as_bytes())?;
        file.flush()?;
        fs::rename(&temp, path)
    })();
    if result.is_err() { let _ = fs::remove_file(&temp); }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sorted_names_totals_and_empty_tail() {
        let body = render("/private/stage space", &[("split two.apk".into(), 9), ("base.apk".into(), 4)]).unwrap();
        assert_eq!(body, format!("{}\nOK\t/private/stage space\t2\t2\t13\t\nFILE\tbase.apk\t4\nFILE\tsplit two.apk\t9\n", SCHEMA));
    }
    #[test]
    fn nmsl_is_not_a_main_split() {
        let body = render("/stage", &[("nmsl.apk".into(), 5), ("base.apk".into(), 8)]).unwrap();
        assert!(body.contains("OK\t/stage\t2\t1\t13\tnmsl.apk\n"));
        assert!(render("/empty", &[]).unwrap().contains("\t0\t0\t0\t\n"));
    }
    #[test]
    fn unsafe_or_ambiguous_names_fail_without_sanitizing() {
        for name in ["bad\n.apk", "bad\r.apk", "bad\t.apk", ".hidden.apk", "sub/base.apk", "bad\0.apk", "base.APK"] {
            assert!(render("/stage", &[(name.into(), 1)]).is_err(), "{}", name);
        }
        assert!(render("/bad\npath", &[]).is_err());
        assert!(render("/stage", &[("base.apk".into(), 1), ("base.apk".into(), 1)]).is_err());
        assert!(render("/stage", &[("a.apk".into(), u64::MAX), ("b.apk".into(), 1)]).is_err());
    }

    #[test]
    fn old_receipt_must_be_removed_or_caller_fails_closed() {
        let root = std::env::temp_dir().join(format!("sb-apk-inventory-test-{}-{}", std::process::id(), std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        fs::create_dir(&root).unwrap();
        let receipt = root.join("inventory.tsv");
        fs::write(&receipt, b"old receipt").unwrap();
        begin(&receipt).unwrap();
        assert!(!receipt.exists());
        begin(&receipt).unwrap();
        fs::create_dir(&receipt).unwrap();
        assert!(begin(&receipt).is_err());
        fs::remove_dir(&receipt).unwrap();
        fs::remove_dir(&root).unwrap();
    }
}
