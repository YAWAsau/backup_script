//! Final-run diagnostic consolidation. Call only after producers have stopped.
//! Publish a durable replacement before removing any source; failures retain it.
use std::{fs::{self, File, OpenOptions}, io::{self, BufRead, BufReader, Read, Seek, SeekFrom, Write}, path::Path};

fn group(name: &str) -> Option<&'static str> {
    for (prefix, suffix, output) in [
        ("process_observer_foreground_foreground_state_pkg_active_", ".txt", "process_observer_foreground_foreground_state_pkg_active_details.log"),
        ("process_observer_foreground_pkg_process_pids_", ".txt", "process_observer_foreground_pkg_process_pids_details.log"),
        ("process_observer_foreground_cgroup_freezer_start_", ".txt", "process_observer_foreground_cgroup_freezer_start_details.log"),
        ("package_install_snapshot_cgroup_freezer_", ".txt", "package_install_snapshot_cgroup_freezer_details.log"),
        ("package_restriction_snapshot_cgroup_freezer_", ".txt", "package_restriction_snapshot_cgroup_freezer_details.log"),
        ("uid_live_state_cgroup_freezer_", ".txt", "uid_live_state_cgroup_freezer_details.log"),
        ("cgroup_wchan_", ".txt", "cgroup_wchan_details.log"),
        ("cgroup_freezer_daemon_", ".txt", "cgroup_freezer_daemon_details.log"),
        ("uid_netblock_", ".log", "uid_netblock_details.log"),
        ("process_observer_top_action_", ".txt", "process_observer_top_action_details.log"),
    ] {
        if name != output && name.starts_with(prefix) && name.ends_with(suffix) { return Some(output); }
    }
    if let Some(rest) = name.strip_prefix("restore_source_") {
        for (suffix, out) in [(".source", "restore_source_results.log"),
            (".verify", "restore_source_verify.log"), (".diff.tsv", "restore_source_diffs.log")] {
            if let Some(id) = rest.strip_suffix(suffix) {
                let parts: Vec<_> = id.split('_').collect();
                if parts.len() == 2 && parts.iter().all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit())) {
                    return Some(out);
                }
            }
        }
    }
    if name.starts_with("restore_payload_plan_") && name.ends_with(".tsv") { return Some("restore_payload_plans.log"); }
    if name.starts_with("process_observer_foreground_") && name.ends_with(".txt") { return Some("process_observer_foreground_probes.log"); }
    None
}
fn escaped(s: &str) -> String {
    s.bytes().map(|b| if b.is_ascii_alphanumeric() || b"._-".contains(&b) { (b as char).to_string() } else {format!("%{b:02X}")}).collect()
}

const IO_CHUNK: usize = 512 * 1024;
const IO_BUDGET: usize = 2 * 1024 * 1024;
const DETAIL_LIMIT: u64 = 16 * 1024 * 1024;
const TOTAL_LIMIT: u64 = 128 * 1024 * 1024;
const HEADER_LIMIT: u64 = 4096;
const FOOTER: &[u8] = b"\n===== END SOURCE =====\n";

#[derive(Clone, Copy)]
struct Record { offset: u64, len: u64 }

// No persistent offset sidecar: index the committed file once per invocation.
// This preserves recovery after rename succeeded but directory fsync failed.
fn published_sources(file: &mut File, size: u64) -> io::Result<std::collections::BTreeMap<String, Record>> {
    file.seek(SeekFrom::Start(0))?;
    let mut reader = BufReader::with_capacity(IO_CHUNK, file);
    let mut published = std::collections::BTreeMap::new();
    let mut since_yield = 0u64;
    let invalid = || io::Error::new(io::ErrorKind::InvalidData,
        "invalid aggregate framing; sources retained");
    while reader.stream_position()? < size {
        let mut prefix = [0u8; 14];
        reader.read_exact(&mut prefix)?;
        if &prefix != b"\n===== SOURCE " { return Err(invalid()); }
        let mut header = Vec::new();
        (&mut reader).take(HEADER_LIMIT).read_until(b'\n', &mut header)?;
        if header.last() != Some(&b'\n') { return Err(invalid()); }
        let header = std::str::from_utf8(&header[..header.len()-1]).map_err(|_| invalid())?;
        let (name, length) = header.strip_suffix(" =====").ok_or_else(invalid)?
            .rsplit_once(" bytes=").ok_or_else(invalid)?;
        if name.is_empty() || length.is_empty() || !length.bytes().all(|b| b.is_ascii_digit()) {
            return Err(invalid());
        }
        let len = length.parse::<u64>().map_err(|_| invalid())?;
        let offset = reader.stream_position()?;
        let end = offset.checked_add(len).ok_or_else(invalid)?;
        if end.checked_add(FOOTER.len() as u64).ok_or_else(invalid)? > size { return Err(invalid()); }
        // Preserve read-ahead for small records instead of refilling 512 KiB
        // for every header. Large payloads are skipped without allocating them.
        reader.seek_relative(len as i64)?;
        let mut footer = [0u8; 24];
        // Keep framing byte-for-byte compatible with debug-consolidate-v1.
        reader.read_exact(&mut footer[..FOOTER.len()])?;
        if &footer[..FOOTER.len()] != FOOTER { return Err(invalid()); }
        published.insert(name.to_owned(), Record { offset, len });
        since_yield += len + header.len() as u64 + FOOTER.len() as u64 + 14;
        if since_yield >= IO_BUDGET as u64 {
            since_yield = 0;
            std::thread::yield_now();
        }
    }
    if reader.stream_position()? != size { return Err(invalid()); }
    Ok(published)
}

fn regular(path: &Path) -> io::Result<File> {
    if !fs::symlink_metadata(path)?.file_type().is_file() {
        return Err(io::Error::other("expected regular file; source retained"));
    }
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(target_os="android")]
    { use std::os::unix::fs::OpenOptionsExt; options.custom_flags(0o400000 | 0o4000); } // O_NOFOLLOW | O_NONBLOCK
    #[cfg(target_os="linux")]
    { use std::os::unix::fs::OpenOptionsExt; options.custom_flags(0o400000 | 0o4000); }
    let file = options.open(path)?;
    if !file.metadata()?.is_file() { return Err(io::Error::other("file changed type; retained")); }
    Ok(file)
}

// Two reusable blocks for exact byte comparison. No whole-file payload allocation.
// Yield after each 2 MiB of I/O; this is cooperative scheduling, not a time limit.
struct Blocks { left: Vec<u8>, right: Vec<u8>, used: usize }
impl Blocks {
    fn new() -> Self { Self { left: vec![0; IO_CHUNK], right: vec![0; IO_CHUNK], used: 0 } }
    fn account(&mut self, bytes: usize) {
        self.used += bytes;
        if self.used >= IO_BUDGET { self.used = 0; std::thread::yield_now(); }
    }
    fn copy(&mut self, source: &mut File, dest: &mut File, mut len: u64) -> io::Result<()> {
        while len > 0 {
            let n = len.min(IO_CHUNK as u64) as usize;
            source.read_exact(&mut self.left[..n])?;
            dest.write_all(&self.left[..n])?;
            len -= n as u64;
            self.account(n * 2);
        }
        Ok(())
    }
    fn same(&mut self, source: &mut File, published: &mut File, record: Record) -> io::Result<bool> {
        if source.metadata()?.len() != record.len { return Ok(false); }
        source.seek(SeekFrom::Start(0))?;
        published.seek(SeekFrom::Start(record.offset))?;
        let mut left = record.len;
        while left > 0 {
            let n = left.min(IO_CHUNK as u64) as usize;
            source.read_exact(&mut self.left[..n])?;
            published.read_exact(&mut self.right[..n])?;
            let equal = self.left[..n] == self.right[..n];
            self.account(n * 2);
            if !equal { return Ok(false); }
            left -= n as u64;
        }
        Ok(source.metadata()?.len() == record.len)
    }
}

pub fn consolidate(root: &Path) -> io::Result<(usize, usize)> {
    if fs::symlink_metadata(root)?.file_type().is_symlink() || !root.is_dir() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput,"expected real run directory"));
    }
    // Retain only paths/lengths, not up to 128 MiB of source contents.
    let mut batches = std::collections::BTreeMap::<&str, Vec<(String, u64)>>::new();
    let mut total = 0u64;
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let name = match entry.file_name().into_string() {Ok(n)=>n, Err(_)=>continue};
        let Some(out) = group(&name) else {continue};
        if !entry.file_type()?.is_file() {continue;}
        let len = entry.metadata()?.len();
        if len > DETAIL_LIMIT { return Err(io::Error::other("detail too large; retained")); }
        total = total.checked_add(len).ok_or_else(||io::Error::other("size overflow"))?;
        if total > TOTAL_LIMIT { return Err(io::Error::other("batch too large; retained")); }
        batches.entry(out).or_default().push((name,len));
    }
    let mut blocks = Blocks::new();
    let mut removed = 0; let mut retained = 0;
    for (out, mut entries) in batches {
        entries.sort_by(|a,b|a.0.cmp(&b.0));
        let dest = root.join(out);
        let mut previous = match fs::symlink_metadata(&dest) {
            Ok(m) if m.file_type().is_file() && m.len() <= TOTAL_LIMIT => Some(regular(&dest)?),
            Ok(_) => return Err(io::Error::other("aggregate is not regular or too large; sources retained")),
            Err(e) if e.kind()==io::ErrorKind::NotFound => None,
            Err(e)=>return Err(e),
        };
        let previous_size = match previous.as_ref() { Some(f)=>f.metadata()?.len(), None=>0 };
        if previous_size > TOTAL_LIMIT { return Err(io::Error::other("aggregate grew; sources retained")); }
        let published = match previous.as_mut() {
            Some(f)=>published_sources(f, previous_size)?, None=>std::collections::BTreeMap::new(),
        };
        let temp = root.join(format!(".debug-merge-{}-{out}.tmp",std::process::id()));
        let mut f = OpenOptions::new().write(true).create_new(true).open(&temp)?;
        let mut snapshots = Vec::new();
        let result = (||->io::Result<()> {
            if let Some(old) = previous.as_mut() {
                old.seek(SeekFrom::Start(0))?;
                blocks.copy(old, &mut f, previous_size)?;
            }
            for (name, len) in &entries {
                let mut source = regular(&root.join(name))?;
                if source.metadata()?.len() != *len { return Err(io::Error::other("source changed; retained")); }
                let key = escaped(name);
                if let (Some(old), Some(record)) = (previous.as_mut(), published.get(&key)) {
                    if blocks.same(&mut source, old, *record)? {
                        snapshots.push((name.clone(), *record));
                        continue;
                    }
                }
                writeln!(f,"\n===== SOURCE {key} bytes={len} =====")?;
                let record = Record { offset: f.stream_position()?, len: *len };
                source.seek(SeekFrom::Start(0))?;
                blocks.copy(&mut source, &mut f, *len)?;
                if source.metadata()?.len() != *len { return Err(io::Error::other("source changed; retained")); }
                f.write_all(FOOTER)?;
                snapshots.push((name.clone(), record));
            }
            f.sync_all()?;
            Ok(())
        })();
        drop(f); drop(previous);
        if let Err(e) = result { let _ = fs::remove_file(&temp); return Err(e); }
        if let Err(e) = fs::rename(&temp,&dest) { let _ = fs::remove_file(&temp); return Err(e); }
        // A directory fsync failure leaves sources intact. Retry indexes the
        // already-published bytes and deduplicates them before trying cleanup.
        #[cfg(unix)] File::open(root)?.sync_all()?;
        let mut committed = regular(&dest)?;
        for (name, record) in snapshots {
            let path = root.join(name);
            let unchanged = regular(&path).and_then(|mut source| {
                if !blocks.same(&mut source, &mut committed, record)? { return Ok(false); }
                let now = fs::symlink_metadata(&path)?;
                if !now.file_type().is_file() { return Ok(false); }
                #[cfg(unix)] {
                    use std::os::unix::fs::MetadataExt;
                    let before = source.metadata()?;
                    if now.dev()!=before.dev() || now.ino()!=before.ino() { return Ok(false); }
                }
                Ok(now.len()==record.len)
            }).unwrap_or(false);
            if unchanged && fs::remove_file(&path).is_ok() {removed+=1;} else {retained+=1;}
        }
    }
    Ok((removed,retained))
}
pub fn command(root: &str) -> i32 {
    let start=std::time::Instant::now();
    match consolidate(Path::new(root)).and_then(|(merged, retained)|
        prune_zstd_banners(Path::new(root)).map(|banners| (merged, retained, banners))) {
        Ok((merged,retained,banners))=>{println!("DEBUG_CONSOLIDATE ok=1 merged={merged} retained={retained} zstdBannersRemoved={banners} elapsedMs={} schema=debug-consolidate-v1 ioChunkBytes=524288 ioBudgetBytes=2097152 strategy=stream-offset-index",start.elapsed().as_millis());0}
        Err(e)=>{eprintln!("DEBUG_CONSOLIDATE ok=0 originals=retained-or-already-published error={e}");1}
    }
}

fn zstd_banner(line: &[u8]) -> bool {
    let line = line.strip_suffix(b"\n").unwrap_or(line);
    let line = line.strip_suffix(b"\r").unwrap_or(line);
    let version = line.strip_prefix(b"*** Zstandard CLI (64-bit) v")
        .or_else(|| line.strip_prefix(b"*** Zstandard CLI (32-bit) v"))
        .and_then(|s| s.strip_suffix(b", by Yann Collet ***"));
    version.map(|v| !v.is_empty() && v.len() <= 64
        && v[0].is_ascii_digit() && v.iter().all(|b| b.is_ascii_alphanumeric() || b"._-+".contains(b)))
        .unwrap_or(false)
}

// Run only in final consolidation after all writers stop. Keep verbose zstd
// parameters/statistics/errors during transfer, with no filter process in the
// data pipeline. Tool identity remains in tools_version.log. Bounded chunks
// preserve all non-banner bytes, including long lines, CRLF and binary data.
pub fn prune_zstd_banners(root: &Path) -> io::Result<usize> {
    use std::os::unix::fs::MetadataExt;
    if fs::symlink_metadata(root)?.file_type().is_symlink() || !root.is_dir() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "expected real run directory"));
    }
    let mut removed = 0;
    for name in ["compress.log", "extract.log", "checksum.log"] {
        let path = root.join(name);
        let source = match regular(&path) {
            Ok(file) => file,
            Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
            Err(e) => return Err(e),
        };
        let before = source.metadata()?;
        if before.len() > TOTAL_LIMIT { continue; }
        let temp = root.join(format!(".debug-banner-{}-{name}.tmp", std::process::id()));
        let mut dest = OpenOptions::new().write(true).create_new(true).open(&temp)?;
        let result = (|| -> io::Result<usize> {
            let mut reader = BufReader::with_capacity(IO_CHUNK, source);
            let mut chunk = Vec::with_capacity(4096);
            let mut continued = false;
            let mut count = 0;
            let mut since_yield = 0;
            let mut bytes = 0u64;
            loop {
                chunk.clear();
                let n = (&mut reader).take(4096).read_until(b'\n', &mut chunk)?;
                if n == 0 { break; }
                bytes += n as u64;
                if bytes > before.len() { return Err(io::Error::other("log grew; original retained")); }
                if !continued && zstd_banner(&chunk) { count += 1; }
                else { dest.write_all(&chunk)?; }
                continued = chunk.last() != Some(&b'\n');
                since_yield += n;
                if since_yield >= IO_BUDGET { since_yield = 0; std::thread::yield_now(); }
            }
            let after = fs::symlink_metadata(&path)?;
            if bytes != before.len() || !after.file_type().is_file()
                || after.ino() != before.ino() || after.dev() != before.dev()
                || after.len() != before.len() || after.modified()? != before.modified()? {
                return Err(io::Error::other("log changed; original retained"));
            }
            if count > 0 {
                dest.set_permissions(before.permissions())?;
                dest.sync_all()?;
            }
            Ok(count)
        })();
        drop(dest);
        let count = match result {
            Ok(n) => n,
            Err(e) => { let _ = fs::remove_file(&temp); return Err(e); }
        };
        if count == 0 { fs::remove_file(&temp)?; continue; }
        if let Err(e) = fs::rename(&temp, &path) { let _ = fs::remove_file(&temp); return Err(e); }
        File::open(root)?.sync_all()?;
        removed += count;
    }
    Ok(removed)
}

#[cfg(test)] mod tests {
    use super::*;
    fn root(label:&str)->std::path::PathBuf {
        let p=std::env::temp_dir().join(format!("sb-merge-{}-{label}-{}",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
        fs::create_dir(&p).unwrap();p
    }
    #[test] fn preserves_bytes_and_appends() {
        let p=root("bytes");let raw=b"no newline\0\xff";
        fs::write(p.join("restore_source_1_1.source"),raw).unwrap();
        fs::write(p.join("restore_source_1_1.diff.tsv"),b"").unwrap();
        assert_eq!(consolidate(&p).unwrap(),(2,0));
        let first=fs::read(p.join("restore_source_results.log")).unwrap();assert!(first.windows(raw.len()).any(|s|s==raw));
        fs::write(p.join("restore_source_1_2.source"),b"second").unwrap();
        assert_eq!(consolidate(&p).unwrap(),(1,0));assert!(fs::read(p.join("restore_source_results.log")).unwrap().starts_with(&first));
        assert_eq!(consolidate(&p).unwrap(),(0,0));fs::remove_dir_all(p).unwrap();
    }
    #[test] fn collision_preserves_original() {
        let p=root("failure");fs::create_dir(p.join("restore_source_results.log")).unwrap();
        fs::write(p.join("restore_source_1_1.source"),b"keep").unwrap();
        assert!(consolidate(&p).is_err());assert_eq!(fs::read(p.join("restore_source_1_1.source")).unwrap(),b"keep");fs::remove_dir_all(p).unwrap();
    }
    #[cfg(unix)] #[test] fn skips_symlink_and_unknown() {
        let p=root("links");fs::write(p.join("unknown"),b"keep").unwrap();
        std::os::unix::fs::symlink(p.join("unknown"),p.join("restore_source_1_1.source")).unwrap();
        assert_eq!(consolidate(&p).unwrap(),(0,0));assert!(p.join("unknown").exists());fs::remove_dir_all(p).unwrap();
    }
    #[test] fn banners_only_and_idempotent() {
        let p=root("banners");
        let banner=b"*** Zstandard CLI (64-bit) v1.6.0, by Yann Collet ***\r\n";
        let keep=b"Note: 8 physical core(s) detected\r\nerror: keep version mismatch\n\0\xffno newline";
        let mut input=banner.to_vec();input.extend_from_slice(keep);
        fs::write(p.join("compress.log"),input).unwrap();
        fs::write(p.join("tools_version.log"),banner).unwrap();
        assert_eq!(prune_zstd_banners(&p).unwrap(),1);
        assert_eq!(fs::read(p.join("compress.log")).unwrap(),keep);
        assert_eq!(fs::read(p.join("tools_version.log")).unwrap(),banner);
        assert_eq!(prune_zstd_banners(&p).unwrap(),0);
        fs::remove_dir_all(p).unwrap();
    }
    #[test] fn embedded_banner_on_long_line_is_not_removed() {
        let p=root("long");let mut input=vec![b'x';4096];
        input.extend_from_slice(b"*** Zstandard CLI (64-bit) v1.6.0, by Yann Collet ***\n");
        fs::write(p.join("extract.log"),&input).unwrap();
        assert_eq!(prune_zstd_banners(&p).unwrap(),0);
        assert_eq!(fs::read(p.join("extract.log")).unwrap(),input);
        fs::remove_dir_all(p).unwrap();
    }
}
