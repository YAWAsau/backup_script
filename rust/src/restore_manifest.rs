//! Lossless, versioned restore snapshots. Legacy manifest commands remain unchanged.
use std::io::{self, BufRead, Write};

pub const HEADER: &str = "#schema\tspeedbackup.restore_tree_manifest_bytes.v1";

pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(DIGITS[(b >> 4) as usize] as char);
        out.push(DIGITS[(b & 15) as usize] as char);
    }
    out
}

pub fn unhex(text: &str) -> Option<Vec<u8>> {
    fn nibble(b: u8) -> Option<u8> {
        match b {
            b'0'..=b'9' => Some(b - b'0'),
            b'a'..=b'f' => Some(b - b'a' + 10),
            _ => None,
        }
    }
    if text.is_empty() || text.len() % 2 != 0 {
        return None;
    }
    let mut bytes = Vec::with_capacity(text.len() / 2);
    for pair in text.as_bytes().chunks_exact(2) {
        bytes.push(nibble(pair[0])? * 16 + nibble(pair[1])?);
    }
    // Never allow a manifest row to escape its root or contain C-string NUL.
    if bytes.contains(&0)
        || bytes
            .split(|b| *b == b'/')
            .any(|c| c.is_empty() || c == b"." || c == b"..")
    {
        return None;
    }
    Some(bytes)
}

#[derive(Debug, PartialEq)]
pub struct Facts {
    pub kind: u8,
    pub size: u64,
    pub mtime: i64,
}

pub fn row(out: &mut impl Write, path: &[u8], facts: &Facts) -> io::Result<()> {
    writeln!(
        out,
        "{}\t{}\t{}\t{}",
        hex(path),
        facts.kind as char,
        facts.size,
        facts.mtime
    )
}

/// Callback permits the same parser and comparison logic to be tested on every host.
pub fn verify(
    mut input: impl BufRead,
    out: &mut impl Write,
    mut stat: impl FnMut(&[u8]) -> io::Result<Facts>,
) -> io::Result<i32> {
    let mut first = String::new();
    input.read_line(&mut first)?;
    if first.trim_end_matches('\n') != HEADER {
        writeln!(out, "#restore_tree_verify\trc=2\treason=invalid_schema")?;
        return Ok(2);
    }
    writeln!(out, "#schema\tspeedbackup.restore_tree_verify_bytes.v1")?;
    writeln!(
        out,
        "#fields\tstatus\trelHex\texpectedSize\tactualSize\texpectedMtime\tactualMtime\treason"
    )?;
    let (mut rows, mut ok, mut missing, mut changed, mut bad) = (0, 0, 0, 0, 0);
    for line in input.lines() {
        let line = line?;
        let fields: Vec<_> = line.split('\t').collect();
        let parsed = (|| {
            if fields.len() != 4 || !matches!(fields[1], "f" | "d" | "l" | "p" | "s" | "b" | "c") {
                return None;
            }
            Some((
                unhex(fields[0])?,
                Facts {
                    kind: fields[1].as_bytes()[0],
                    size: fields[2].parse().ok()?,
                    mtime: fields[3].parse().ok()?,
                },
            ))
        })();
        let Some((path, expected)) = parsed else {
            bad += 1;
            continue;
        };
        rows += 1;
        match stat(&path) {
            Ok(actual) if actual == expected => {
                ok += 1;
            }
            Ok(actual) => {
                changed += 1;
                writeln!(
                    out,
                    "CHANGED\t{}\t{}\t{}\t{}\t{}\ttype_size_or_mtime",
                    fields[0], expected.size, actual.size, expected.mtime, actual.mtime
                )?;
            }
            Err(e) => {
                missing += 1;
                writeln!(
                    out,
                    "MISSING\t{}\t{}\t0\t{}\t0\tstat_errno_{}",
                    fields[0],
                    expected.size,
                    expected.mtime,
                    e.raw_os_error().unwrap_or(-1)
                )?;
            }
        }
    }
    let rc = i32::from(missing + changed + bad != 0);
    writeln!(
        out,
        "#summary\trows={rows}\tok={ok}\tmissing={missing}\tchanged={changed}\tbad={bad}\trc={rc}"
    )?;
    writeln!(
        out,
        "#restore_tree_verify\trc={rc}\tpolicy=facts-only\tpathEncoding=hex"
    )?;
    Ok(rc)
}

#[cfg(unix)]
pub mod unix {
    use super::*;
    use std::ffi::OsStr;
    use std::fs::{self, File, Metadata};
    use std::io::{BufReader, BufWriter};
    use std::os::unix::ffi::OsStrExt;
    use std::os::unix::fs::{FileTypeExt, MetadataExt};
    use std::path::Path;

    fn facts(meta: &Metadata) -> Facts {
        let t = meta.file_type();
        let kind = if t.is_file() {
            b'f'
        } else if t.is_dir() {
            b'd'
        } else if t.is_symlink() {
            b'l'
        } else if t.is_fifo() {
            b'p'
        } else if t.is_socket() {
            b's'
        } else if t.is_block_device() {
            b'b'
        } else {
            b'c'
        };
        Facts {
            kind,
            size: meta.len(),
            mtime: meta.mtime(),
        }
    }

    fn walk(root: &Path, dir: &Path, out: &mut impl Write) -> io::Result<()> {
        for entry in fs::read_dir(dir)? {
            let path = entry?.path();
            let meta = fs::symlink_metadata(&path)?;
            row(
                out,
                path.strip_prefix(root).unwrap().as_os_str().as_bytes(),
                &facts(&meta),
            )?;
            if meta.is_dir() {
                walk(root, &path, out)?;
            }
        }
        Ok(())
    }

    pub fn manifest(root: &Path, output: &Path) -> io::Result<()> {
        if !fs::symlink_metadata(root)?.is_dir() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "root is not directory",
            ));
        }
        let mut out = BufWriter::new(File::create(output)?);
        writeln!(out, "{HEADER}")?;
        walk(root, root, &mut out)?;
        out.flush()
    }

    pub fn check(root: &Path, manifest: &Path, out: &mut impl Write) -> io::Result<i32> {
        if !fs::symlink_metadata(root)?.is_dir() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "root is not directory",
            ));
        }
        verify(BufReader::new(File::open(manifest)?), out, |rel| {
            fs::symlink_metadata(root.join(OsStr::from_bytes(rel))).map(|m| facts(&m))
        })
    }

    /// One process, independent snapshot and re-stat passes; never self-comparison.
    pub fn audit(root: &str, path: &str) -> i32 {
        let started = std::time::Instant::now();
        let result = manifest(Path::new(root), Path::new(path));
        let snapshot_ms = started.elapsed().as_millis();
        let manifest_rc = if result.is_ok() { 0 } else { 3 };
        let mut out = io::BufWriter::new(io::stdout().lock());
        let rc = match result.and_then(|_| check(Path::new(root), Path::new(path), &mut out)) {
            Ok(rc) => rc,
            Err(e) => {
                eprintln!("restore audit: {e}");
                3
            }
        };
        let _ = writeln!(
            out,
            "SBRESULT\t1\trestore-tree-audit\t{}\t{}\t{}\t{}\t{}",
            if rc == 0 { "ok" } else { "failed" },
            rc,
            manifest_rc,
            snapshot_ms,
            started.elapsed().as_millis()
        );
        if out.flush().is_err() {
            return 3;
        }
        rc
    }

    pub fn command(root: &str, path: &str, checking: bool) -> i32 {
        let result = if checking {
            check(Path::new(root), Path::new(path), &mut io::stdout().lock())
        } else {
            manifest(Path::new(root), Path::new(path)).map(|_| 0)
        };
        match result {
            Ok(rc) => rc,
            Err(e) => {
                eprintln!("speedscan: restore manifest bytes: {e}");
                3
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn facts() -> Facts {
        Facts {
            kind: b'f',
            size: 123,
            mtime: 456,
        }
    }

    #[test]
    fn roundtrip_all_filename_bytes() {
        for b in 1..=255u8 {
            if b == b'/' {
                continue;
            }
            let p = vec![b'x', b, b'z'];
            assert_eq!(unhex(&hex(&p)), Some(p));
        }
        for p in [
            b"dir/new\nline.log".as_slice(),
            b"dir/tab\tname",
            b"dir/cr\rname",
            b"nonutf8\xff\xfe",
            "中文/檔名".as_bytes(),
            b"literal\\n%09",
        ] {
            assert_eq!(unhex(&hex(p)), Some(p.to_vec()));
        }
    }

    #[test]
    fn reject_malformed_and_escaping_paths() {
        for p in [
            b"/abs".as_slice(),
            b"../x",
            b"a/../b",
            b"a//b",
            b"./x",
            b"nul\0x",
        ] {
            assert!(unhex(&hex(p)).is_none());
        }
        for s in ["", "a", "zz", "FF"] {
            assert!(unhex(s).is_none());
        }
    }

    #[test]
    fn empty_tree_is_valid_but_missing_schema_is_not() {
        let mut out = Vec::new();
        assert_eq!(
            verify(format!("{HEADER}\n").as_bytes(), &mut out, |_| panic!()).unwrap(),
            0
        );
        assert!(String::from_utf8(out).unwrap().contains("rows=0\tok=0"));
        assert_eq!(verify(&b""[..], &mut Vec::new(), |_| panic!()).unwrap(), 2);
    }

    #[test]
    fn odd_names_do_not_split_rows() {
        let mut input = format!("{HEADER}\n").into_bytes();
        let names = [b"a\n.log".as_slice(), b"b\t.log", b"c\xff\r.log"];
        for p in names {
            row(&mut input, p, &facts()).unwrap();
        }
        let mut seen = Vec::new();
        let mut out = Vec::new();
        assert_eq!(
            verify(&input[..], &mut out, |p| {
                seen.push(p.to_vec());
                Ok(facts())
            })
            .unwrap(),
            0
        );
        assert_eq!(seen, names);
        assert!(String::from_utf8(out)
            .unwrap()
            .contains("rows=3\tok=3\tmissing=0\tchanged=0\tbad=0"));
    }

    #[test]
    fn genuine_missing_changed_and_bad_rows_still_fail() {
        let mut input = format!("{HEADER}\n").into_bytes();
        row(&mut input, b"missing", &facts()).unwrap();
        row(&mut input, b"changed", &facts()).unwrap();
        input.extend_from_slice(b"zz\tf\t12\t1\n");
        let mut out = Vec::new();
        assert_eq!(
            verify(&input[..], &mut out, |p| {
                if p == b"missing" {
                    Err(io::ErrorKind::NotFound.into())
                } else {
                    Ok(Facts {
                        size: 124,
                        ..facts()
                    })
                }
            })
            .unwrap(),
            1
        );
        assert!(String::from_utf8(out)
            .unwrap()
            .contains("missing=1\tchanged=1\tbad=1"));
    }

    #[cfg(unix)]
    #[test]
    fn actual_files_empty_odd_names_and_mutation() {
        use std::os::unix::ffi::OsStrExt;
        let base = std::env::temp_dir().join(format!("r702-manifest-{}", std::process::id()));
        let root = base.join("root");
        std::fs::create_dir_all(&root).unwrap();
        let manifest = base.join("manifest");
        unix::manifest(&root, &manifest).unwrap();
        assert_eq!(unix::check(&root, &manifest, &mut Vec::new()).unwrap(), 0);
        let path = root.join(std::ffi::OsStr::from_bytes(b"odd\n\t\xff.log"));
        std::fs::write(&path, b"abc").unwrap();
        std::os::unix::fs::symlink("absent", root.join("dangling")).unwrap();
        unix::manifest(&root, &manifest).unwrap();
        assert_eq!(unix::check(&root, &manifest, &mut Vec::new()).unwrap(), 0);
        std::fs::write(&path, b"changed").unwrap();
        assert_eq!(unix::check(&root, &manifest, &mut Vec::new()).unwrap(), 1);
        std::fs::remove_dir_all(base).unwrap();
    }
}
