//! Read the persisted source facts from the exact tar stream sent to extraction.
//! File names and link targets are hex encoded bytes, never shell text records.
use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Read, Write};
#[cfg(unix)]
use std::path::Path;

const HEADER: &str = "#schema\tspeedbackup.tar_source.v1";
fn bad(s: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, s)
}
fn hex(b: &[u8]) -> String {
    b.iter().map(|b| format!("{b:02x}")).collect()
}
fn bytes(s: &str) -> io::Result<Vec<u8>> {
    if s == "-" {
        return Ok(Vec::new());
    }
    if s.len() % 2 != 0 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(bad("invalid hex"));
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).map_err(|_| bad("invalid hex")))
        .collect()
}
fn encoded(b: &[u8]) -> String {
    if b.is_empty() {
        "-".into()
    } else {
        hex(b)
    }
}
fn cstr(b: &[u8]) -> Vec<u8> {
    b.split(|b| *b == 0).next().unwrap_or_default().to_vec()
}
fn number(b: &[u8]) -> io::Result<u64> {
    if b[0] & 0x80 != 0 {
        if b[0] & 0x40 != 0 {
            return Err(bad("negative tar number"));
        }
        return b.iter().enumerate().try_fold(0u64, |n, (i, v)| {
            n.checked_mul(256)
                .and_then(|n| n.checked_add(if i == 0 { (v & 0x7f) as u64 } else { *v as u64 }))
                .ok_or_else(|| bad("tar number overflow"))
        });
    }
    let t = std::str::from_utf8(b)
        .map_err(|_| bad("tar number"))?
        .trim_matches(|c| c == '\0' || c == ' ');
    if t.is_empty() {
        return Ok(0);
    }
    u64::from_str_radix(t, 8).map_err(|_| bad("tar octal"))
}
fn clean(b: &[u8]) -> io::Result<Vec<u8>> {
    if b.contains(&0) || b.starts_with(b"/") {
        return Err(bad("unsafe member path"));
    }
    let mut out = Vec::new();
    for part in b.split(|b| *b == b'/') {
        if part == b".." {
            return Err(bad("parent member path"));
        }
        if part.is_empty() || part == b"." {
            continue;
        }
        if !out.is_empty() {
            out.push(b'/');
        }
        out.extend_from_slice(part);
    }
    Ok(out)
}
#[derive(Clone, Debug)]
struct Member {
    path: Vec<u8>,
    kind: u8,
    size: u64,
    mode: u64,
    uid: u64,
    gid: u64,
    mtime: u64,
    link: Vec<u8>,
    major: u64,
    minor: u64,
}
impl Member {
    fn row(&self) -> String {
        format!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n",
            encoded(&self.path),
            self.kind as char,
            self.size,
            self.mode,
            self.uid,
            self.gid,
            self.mtime,
            encoded(&self.link),
            self.major,
            self.minor
        )
    }
    fn parse(line: &str) -> io::Result<Self> {
        let f: Vec<_> = line.split('\t').collect();
        if f.len() != 10 || f[1].len() != 1 {
            return Err(bad("manifest columns"));
        }
        let n = |i: usize| f[i].parse::<u64>().map_err(|_| bad("manifest number"));
        let path = bytes(f[0])?;
        if clean(&path)? != path {
            return Err(bad("noncanonical manifest path"));
        }
        let kind = f[1].as_bytes()[0];
        if !b"01234567".contains(&kind) {
            return Err(bad("manifest type"));
        }
        let link = bytes(f[7])?;
        if kind == b'1' && clean(&link)? != link {
            return Err(bad("unsafe hardlink"));
        }
        Ok(Self {
            path,
            kind,
            size: n(2)?,
            mode: n(3)?,
            uid: n(4)?,
            gid: n(5)?,
            mtime: n(6)?,
            link,
            major: n(8)?,
            minor: n(9)?,
        })
    }
}
fn pax(data: &[u8], values: &mut BTreeMap<Vec<u8>, Vec<u8>>) -> io::Result<()> {
    let mut pos = 0;
    while pos < data.len() {
        let space = data[pos..]
            .iter()
            .position(|b| *b == b' ')
            .ok_or_else(|| bad("pax length"))?
            + pos;
        let len = std::str::from_utf8(&data[pos..space])
            .ok()
            .and_then(|s| s.parse::<usize>().ok())
            .ok_or_else(|| bad("pax number"))?;
        let end = pos.checked_add(len).ok_or_else(|| bad("pax overflow"))?;
        if end > data.len() || end <= space + 2 || data[end - 1] != b'\n' {
            return Err(bad("pax record"));
        }
        let record = &data[space + 1..end - 1];
        let eq = record
            .iter()
            .position(|b| *b == b'=')
            .ok_or_else(|| bad("pax key"))?;
        values.insert(record[..eq].to_vec(), record[eq + 1..].to_vec());
        pos = end;
    }
    Ok(())
}

fn matches_source(
    m: &Member,
    a: &Member,
    hardlink_ok: bool,
    mode: bool,
    owner: Option<(u32, u32)>,
    mtime: bool,
) -> bool {
    // chown clears privilege bits on regular files; compare the permissions that
    // the restore policy preserves, rather than demanding obsolete set-id bits.
    let mode_mask = if owner.is_some() && a.kind == b'0' {
        0o1777
    } else {
        0o7777
    };
    let kind = if m.kind == b'1' {
        a.kind != b'5' && hardlink_ok
    } else if m.kind == b'7' {
        a.kind == b'0'
    } else {
        m.kind == a.kind
    };
    kind && (!matches!(m.kind, b'0' | b'7') || a.size == m.size)
        && (!mode || a.kind == b'2' || (a.mode & mode_mask) == (m.mode & mode_mask))
        && owner.is_none_or(|(u, g)| a.uid == u64::from(u) && a.gid == u64::from(g))
        && (!mtime || a.mtime == m.mtime)
        && (m.kind != b'2' || a.link == m.link)
        && (!matches!(m.kind, b'3' | b'4') || (a.major, a.minor) == (m.major, m.minor))
}
fn transfer(
    r: &mut impl Read,
    w: &mut impl Write,
    mut count: u64,
    capture: bool,
) -> io::Result<Vec<u8>> {
    if capture && count > 1024 * 1024 {
        return Err(bad("oversized extended header"));
    }
    let mut data = Vec::new();
    let mut buf = [0u8; 65536];
    while count > 0 {
        let n = count.min(buf.len() as u64) as usize;
        r.read_exact(&mut buf[..n])?;
        w.write_all(&buf[..n])?;
        if capture {
            data.extend_from_slice(&buf[..n]);
        }
        count -= n as u64;
    }
    Ok(data)
}
/// Returns unique final member facts and the count of unsupported metadata fields.
fn capture(
    r: &mut impl Read,
    w: &mut impl Write,
) -> io::Result<(BTreeMap<Vec<u8>, Member>, usize)> {
    let mut members = BTreeMap::new();
    let mut global = BTreeMap::new();
    let mut local = BTreeMap::new();
    let mut longname = None;
    let mut longlink = None;
    let mut limited = 0;
    loop {
        let mut h = [0u8; 512];
        r.read_exact(&mut h)?;
        if h.iter().all(|b| *b == 0) {
            w.write_all(&h)?;
            r.read_exact(&mut h)?;
            if h.iter().any(|b| *b != 0) {
                return Err(bad("missing second EOF block"));
            }
            w.write_all(&h)?;
            let mut b = [0u8; 65536];
            loop {
                let n = r.read(&mut b)?;
                if n == 0 {
                    break;
                }
                if b[..n].iter().any(|b| *b != 0) {
                    return Err(bad("nonzero trailing archive"));
                }
                w.write_all(&b[..n])?;
            }
            if !local.is_empty() || longname.is_some() || longlink.is_some() {
                return Err(bad("orphan extended header"));
            }
            w.flush()?;
            return Ok((members, limited));
        }
        let sum: u64 = h
            .iter()
            .enumerate()
            .map(|(i, b)| {
                if (148..156).contains(&i) {
                    32
                } else {
                    *b as u64
                }
            })
            .sum();
        if number(&h[148..156])? != sum {
            return Err(bad("tar checksum"));
        }
        let rawsize = number(&h[124..136])?;
        let kind = if h[156] == 0 { b'0' } else { h[156] };
        if matches!(kind, b'L' | b'K' | b'x' | b'g') {
            w.write_all(&h)?;
            let d = transfer(r, w, rawsize, true)?;
            transfer(r, w, (512 - rawsize % 512) % 512, false)?;
            match kind {
                b'L' => longname = Some(cstr(&d)),
                b'K' => longlink = Some(cstr(&d)),
                b'x' => pax(&d, &mut local)?,
                _ => pax(&d, &mut global)?,
            }
            continue;
        }
        if !b"01234567".contains(&kind) {
            return Err(bad("unsupported tar member type"));
        }
        let mut path = longname.take().unwrap_or_else(|| cstr(&h[..100]));
        if h[257..263] == *b"ustar\0" && h[345] != 0 {
            let mut p = cstr(&h[345..500]);
            p.push(b'/');
            p.extend_from_slice(&path);
            path = p;
        }
        let mut m = Member {
            path,
            kind,
            size: rawsize,
            mode: number(&h[100..108])?,
            uid: number(&h[108..116])?,
            gid: number(&h[116..124])?,
            mtime: number(&h[136..148])?,
            link: longlink.take().unwrap_or_else(|| cstr(&h[157..257])),
            major: number(&h[329..337])?,
            minor: number(&h[337..345])?,
        };
        let mut attrs = global.clone();
        attrs.append(&mut local);
        for (k, v) in attrs {
            match k.as_slice() {
                b"path" => m.path = v,
                b"linkpath" => m.link = v,
                b"size" | b"uid" | b"gid" | b"mtime" => {
                    let s = std::str::from_utf8(&v).map_err(|_| bad("pax numeric"))?;
                    let n = if k == b"mtime" {
                        s.split('.').next().unwrap_or("")
                    } else {
                        s
                    };
                    let n = n.parse().map_err(|_| bad("pax numeric"))?;
                    match k.as_slice() {
                        b"size" => m.size = n,
                        b"uid" => m.uid = n,
                        b"gid" => m.gid = n,
                        _ => m.mtime = n,
                    }
                }
                b"atime" | b"ctime" | b"uname" | b"gname" => {}
                _ => {
                    if k.starts_with(b"GNU.sparse") {
                        return Err(bad("unsupported sparse archive"));
                    }
                    limited += 1;
                }
            }
        }
        m.path = clean(&m.path)?;
        if kind == b'1' {
            m.link = clean(&m.link)?;
        }
        if m.path.is_empty() && kind != b'5' {
            return Err(bad("non-directory archive root"));
        }
        w.write_all(&h)?;
        transfer(r, w, m.size, false)?;
        transfer(r, w, (512 - m.size % 512) % 512, false)?;
        members.insert(m.path.clone(), m);
    }
}
pub fn capture_command(prefix: &str) -> i32 {
    let run = || -> io::Result<()> {
        let marker = format!("{prefix}.source");
        match fs::remove_file(&marker) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => return Err(e),
        }
        let (rows, limited) = capture(
            &mut io::stdin().lock(),
            &mut io::BufWriter::with_capacity(131072, io::stdout().lock()),
        )?;
        let mut out = io::BufWriter::new(fs::File::create(format!("{prefix}.manifest.tmp"))?);
        writeln!(out, "{HEADER}")?;
        for m in rows.values() {
            out.write_all(m.row().as_bytes())?;
        }
        out.flush()?;
        drop(out);
        fs::rename(
            format!("{prefix}.manifest.tmp"),
            format!("{prefix}.manifest"),
        )?;
        fs::write(
            marker,
            format!(
                "SBRESULT\t1\ttar-source\t{}\t{}\t{limited}\n",
                if limited == 0 { "ok" } else { "limited" },
                rows.len()
            ),
        )?;
        Ok(())
    };
    match run() {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("tar source: {e}");
            2
        }
    }
}

#[cfg(unix)]
pub fn verify_command(root: &str, prefix: &str, mode: &str, owner: &str, mtime: &str) -> i32 {
    use std::io::BufRead;
    use std::os::unix::{
        ffi::OsStrExt,
        fs::{FileTypeExt, MetadataExt},
    };
    let run = || -> io::Result<i32> {
        if !matches!(mode, "keep" | "ignore") || !matches!(mtime, "keep" | "ignore") {
            return Err(bad("verification policy"));
        }
        let uid = if owner == "ignore" {
            None
        } else {
            let f: Vec<_> = owner.split(':').collect();
            if f.len() != 2 {
                return Err(bad("owner policy"));
            }
            Some((
                f[0].parse::<u32>().map_err(|_| bad("uid"))?,
                f[1].parse::<u32>().map_err(|_| bad("gid"))?,
            ))
        };
        let marker = fs::read_to_string(format!("{prefix}.source"))?;
        let f: Vec<_> = marker.trim_end().split('\t').collect();
        if f.len() != 6
            || f[..3] != ["SBRESULT", "1", "tar-source"]
            || !matches!(f[3], "ok" | "limited")
        {
            return Err(bad("source receipt"));
        }
        let expected: usize = f[4].parse().map_err(|_| bad("source count"))?;
        let limited: u64 = f[5].parse().map_err(|_| bad("source limitations"))?;
        let mut lines = io::BufReader::new(fs::File::open(format!("{prefix}.manifest"))?).lines();
        if lines.next().transpose()?.as_deref() != Some(HEADER) {
            return Err(bad("manifest schema"));
        }
        let canonical_root = fs::canonicalize(Path::new(root))?;
        let root = canonical_root.as_path();
        if !fs::symlink_metadata(root)?.is_dir() {
            return Err(bad("root must be a real directory"));
        }
        let safe = |rel: &[u8]| -> io::Result<std::path::PathBuf> {
            let mut p = root.to_path_buf();
            let parts: Vec<_> = rel
                .split(|b| *b == b'/')
                .filter(|p| !p.is_empty())
                .collect();
            for (i, c) in parts.iter().enumerate() {
                p.push(std::ffi::OsStr::from_bytes(c));
                if i + 1 < parts.len() && !fs::symlink_metadata(&p)?.is_dir() {
                    return Err(bad("non-directory ancestor"));
                }
            }
            Ok(p)
        };
        let mut out = io::BufWriter::new(fs::File::create(format!("{prefix}.diff.tsv"))?);
        let (mut count, mut mismatch) = (0, 0);
        for line in lines {
            let m = Member::parse(&line?)?;
            count += 1;
            let check = || -> io::Result<bool> {
                let p = safe(&m.path)?;
                let a = fs::symlink_metadata(&p)?;
                let t = a.file_type();
                let kind = if a.is_file() {
                    b'0'
                } else if a.is_dir() {
                    b'5'
                } else if t.is_symlink() {
                    b'2'
                } else if t.is_char_device() {
                    b'3'
                } else if t.is_block_device() {
                    b'4'
                } else if t.is_fifo() {
                    b'6'
                } else {
                    b'?'
                };
                let hardlink_ok = if m.kind == b'1' {
                    let b = fs::symlink_metadata(safe(&m.link)?)?;
                    a.dev() == b.dev() && a.ino() == b.ino()
                } else {
                    true
                };
                let d = a.rdev();
                let actual = Member {
                    path: m.path.clone(),
                    kind,
                    size: a.len(),
                    mode: u64::from(a.mode()),
                    uid: u64::from(a.uid()),
                    gid: u64::from(a.gid()),
                    mtime: a.mtime() as u64,
                    link: if t.is_symlink() {
                        fs::read_link(&p)?.as_os_str().as_bytes().to_vec()
                    } else {
                        Vec::new()
                    },
                    major: ((d >> 8) & 0xfff) | ((d >> 32) & 0xfffff000),
                    minor: (d & 0xff) | ((d >> 12) & 0xffffff00),
                };
                Ok(matches_source(
                    &m,
                    &actual,
                    hardlink_ok,
                    mode == "keep",
                    uid,
                    mtime == "keep",
                ))
            };
            match check() {
                Ok(true) => {}
                Ok(false) => {
                    mismatch += 1;
                    writeln!(out, "{}\tmismatch", encoded(&m.path))?;
                }
                Err(e) => {
                    mismatch += 1;
                    writeln!(out, "{}\t{:?}", encoded(&m.path), e.kind())?;
                }
            }
        }
        if count != expected {
            return Err(bad("manifest count mismatch"));
        }
        out.flush()?;
        let state = if mismatch > 0 {
            "failed"
        } else if limited > 0 {
            "limited"
        } else {
            "ok"
        };
        let receipt=format!("SBRESULT\t1\trestore-source\t{state}\t{count}\t{mismatch}\t{limited}\tmode={mode}\towner={owner}\tmtime={mtime}\tscope=archive-members-no-content-hash\n");
        fs::write(format!("{prefix}.verify"), &receipt)?;
        print!("{receipt}");
        Ok(if mismatch > 0 { 1 } else { 0 })
    };
    match run() {
        Ok(rc) => rc,
        Err(e) => {
            eprintln!("restore source: {e}");
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn archive(name: &[u8], kind: u8, data: &[u8], link: &[u8]) -> Vec<u8> {
        let mut h = [0u8; 512];
        h[..name.len()].copy_from_slice(name);
        h[156] = kind;
        h[157..157 + link.len()].copy_from_slice(link);
        for (start, len, n) in [
            (100, 8, 0o755),
            (108, 8, 0),
            (116, 8, 0),
            (124, 12, data.len() as u64),
            (136, 12, 1),
        ] {
            let s = format!("{:0width$o}\0", n, width = len - 1);
            h[start..start + len].copy_from_slice(s.as_bytes());
        }
        h[148..156].fill(b' ');
        let sum: u64 = h.iter().map(|b| *b as u64).sum();
        h[148..156].copy_from_slice(format!("{sum:06o}\0 ").as_bytes());
        let mut out = h.to_vec();
        out.extend_from_slice(data);
        out.resize(512 + data.len().div_ceil(512) * 512, 0);
        out
    }
    #[test]
    fn lossless_names_links_and_forwarding() {
        let mut a = archive(b"./pkg/", b'5', b"", b"");
        a.extend(archive(b"pkg/a\n\t\xff", b'0', b"abc", b""));
        a.extend(archive(b"pkg/link", b'2', b"", b"a\n\t\xff"));
        a.extend(archive(b"pkg/hard", b'1', b"", b"pkg/a\n\t\xff"));
        a.resize(a.len() + 1024, 0);
        let mut out = Vec::new();
        let (rows, l) = capture(&mut a.as_slice(), &mut out).unwrap();
        assert_eq!(a, out);
        assert_eq!((rows.len(), l), (4, 0));
        for m in rows.values() {
            assert_eq!(
                Member::parse(m.row().trim_end_matches('\n')).unwrap().path,
                m.path
            );
        }
    }
    #[test]
    fn longname_and_longlink() {
        let name = vec![b'n'; 300];
        let link = vec![b'l'; 400];
        let mut a = archive(
            b"././@LongLink",
            b'L',
            &[name.clone(), vec![0]].concat(),
            b"",
        );
        a.extend(archive(
            b"././@LongLink",
            b'K',
            &[link.clone(), vec![0]].concat(),
            b"",
        ));
        a.extend(archive(b"short", b'2', b"", b"short"));
        a.resize(a.len() + 1024, 0);
        let (r, _) = capture(&mut a.as_slice(), &mut Vec::new()).unwrap();
        assert_eq!(r[&name].link, link);
    }
    #[test]
    fn truncation_checksum_escape_and_tail_rejected() {
        for mut a in [
            archive(b"../bad", b'0', b"", b""),
            archive(b"/bad", b'0', b"", b""),
        ] {
            a.resize(a.len() + 1024, 0);
            assert!(capture(&mut a.as_slice(), &mut Vec::new()).is_err());
        }
        let mut a = archive(b"x", b'0', b"hello", b"");
        assert!(capture(&mut a.as_slice(), &mut Vec::new()).is_err());
        a.resize(a.len() + 1024, 0);
        a[10] ^= 1;
        assert!(capture(&mut a.as_slice(), &mut Vec::new()).is_err());
    }
    #[test]
    fn base256_and_pax() {
        assert_eq!(number(&[0x80, 0, 1]).unwrap(), 1);
        let mut v = BTreeMap::new();
        pax(b"12 path=a/b\n", &mut v).unwrap();
        assert_eq!(v[b"path".as_slice()], b"a/b");
        assert!(pax(b"0 a=b\n", &mut v).is_err());
    }
    #[test]
    fn symlink_owner_is_required_without_weakening_target_or_type_checks() {
        let m = Member { path: b"link".to_vec(), kind: b'2', size: 0,
            mode: 0o777, uid: 10001, gid: 10001, mtime: 1,
            link: b"/old/target".to_vec(), major: 0, minor: 0 };
        let mut actual = m.clone();
        assert!(!matches_source(&m, &actual, true, true, Some((10002, 10002)), false));
        actual.uid = 10002; actual.gid = 10002;
        assert!(matches_source(&m, &actual, true, true, Some((10002, 10002)), false));
        actual.link = b"/wrong/target".to_vec();
        assert!(!matches_source(&m, &actual, true, true, Some((10002, 10002)), false));
        actual.link = m.link.clone(); actual.kind = b'0';
        assert!(!matches_source(&m, &actual, true, true, Some((10002, 10002)), false));
    }
    #[test]
    fn policy_and_source_mismatch() {
        let m = Member {
            path: b"x".to_vec(),
            kind: b'0',
            size: 17,
            mode: 0o640,
            uid: 99,
            gid: 99,
            mtime: 1,
            link: Vec::new(),
            major: 0,
            minor: 0,
        };
        let mut actual = m.clone();
        actual.uid = 42;
        actual.gid = 42;
        actual.mtime = 9;
        assert!(matches_source(
            &m,
            &actual,
            true,
            true,
            Some((42, 42)),
            false
        ));
        assert!(!matches_source(
            &m,
            &actual,
            true,
            true,
            Some((99, 99)),
            false
        ));
        assert!(!matches_source(&m, &actual, true, true, None, true));
        actual.size = 16;
        assert!(!matches_source(&m, &actual, true, false, None, false));
        actual.size = 17;
        actual.mode = 0o600;
        assert!(!matches_source(&m, &actual, true, true, None, false));
        assert!(matches_source(&m, &actual, true, false, None, false));
        let mut hard = m.clone();
        hard.kind = b'1';
        actual.kind = b'6';
        assert!(matches_source(&hard, &actual, true, false, None, false));
        assert!(!matches_source(&hard, &actual, false, false, None, false));
        hard.kind = b'2';
        hard.link = b"one".to_vec();
        actual.kind = b'2';
        actual.link = b"two".to_vec();
        assert!(!matches_source(&hard, &actual, true, false, None, false));
    }
}
