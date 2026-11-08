//! Flatten session diagnostics while retaining exact per-operation bytes in indexed spans.
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    fs::{self},
    io::{self, Read},
    path::Path,
};
pub(super) const LIMIT: usize = 256 * 1024 * 1024;
const INDEX: &str = "session_index.json";
const SNAPSHOTS: &str = "session_snapshots.log";
type Files = BTreeMap<String, Vec<u8>>;
type Runs = BTreeMap<String, Files>;
fn bad() -> io::Error {
    io::Error::other("invalid or oversized diagnostic session")
}
fn safe(s: &str) -> bool {
    !s.is_empty()
        && !s.starts_with('/')
        && !s.contains('\\')
        && !s.contains('\0')
        && s.split('/').all(|p| !p.is_empty() && p != "." && p != "..")
}
fn number(b: &[u8]) -> io::Result<usize> {
    let s = std::str::from_utf8(b)
        .map_err(|_| bad())?
        .trim_matches(|c| c == '\0' || c == ' ');
    usize::from_str_radix(if s.is_empty() { "0" } else { s }, 8).map_err(|_| bad())
}
fn string(b: &[u8]) -> io::Result<String> {
    String::from_utf8(b.split(|b| *b == 0).next().unwrap_or_default().to_vec()).map_err(|_| bad())
}
fn read_tar(path: &Path) -> io::Result<Files> {
    use std::os::unix::fs::OpenOptionsExt;
    let mut r = fs::OpenOptions::new()
        .read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(path)?;
    if r.metadata()?.len() > LIMIT as u64 {
        return Err(bad());
    }
    let mut files = Files::new();
    let mut long = None;
    let mut total = 0usize;
    loop {
        let mut h = [0u8; 512];
        r.read_exact(&mut h)?;
        if h.iter().all(|b| *b == 0) {
            if long.is_some() {
                return Err(bad());
            }
            r.read_exact(&mut h)?;
            if h.iter().any(|b| *b != 0) {
                return Err(bad());
            }
            let mut tail = Vec::new();
            r.take(LIMIT as u64).read_to_end(&mut tail)?;
            if tail.iter().any(|b| *b != 0) {
                return Err(bad());
            }
            break;
        }
        let checksum: usize = h
            .iter()
            .enumerate()
            .map(|(i, b)| {
                if (148..156).contains(&i) {
                    32
                } else {
                    *b as usize
                }
            })
            .sum();
        if number(&h[148..156])? != checksum {
            return Err(bad());
        }
        let size = number(&h[124..136])?;
        total = total.checked_add(size).ok_or_else(bad)?;
        if total > LIMIT || files.len() > 8192 {
            return Err(bad());
        }
        let mut body = vec![0; size];
        r.read_exact(&mut body)?;
        let mut pad = vec![0; (512 - size % 512) % 512];
        r.read_exact(&mut pad)?;
        if h[156] == b'L' {
            long = Some(string(&body)?);
            continue;
        }
        let mut name = long.take().unwrap_or(string(&h[..100])?);
        if &h[257..263] == b"ustar\0" && h[345] != 0 {
            name = format!("{}/{}", string(&h[345..500])?, name);
        }
        let name = name.trim_end_matches('/').to_owned();
        if !safe(&name) {
            return Err(bad());
        }
        match h[156] {
            0 | b'0' => {
                if files.insert(name, body).is_some() {
                    return Err(bad());
                }
            }
            b'5' if size == 0 => {}
            _ => return Err(bad()),
        }
    }
    Ok(files)
}

fn previous(archive: &Path) -> io::Result<(String, Runs, Vec<String>)> {
    let raw = read_tar(archive)?;
    let root = raw
        .keys()
        .next()
        .and_then(|s| s.split_once('/'))
        .map(|p| p.0.to_owned())
        .ok_or_else(bad)?;
    let mut runs = Runs::new();
    let mut order = Vec::new();
    let mut recovered = 0usize;
    if let Some(index) = raw.get(&format!("{root}/{INDEX}")) {
        let index: Value = serde_json::from_slice(index).map_err(|_| bad())?;
        let spans = index["spans"].as_array().ok_or_else(bad)?;
        if index["schema"].as_u64() != Some(1) || spans.len() > 8192 {
            return Err(bad());
        }
        for s in spans {
            let run = s["run"].as_str().ok_or_else(bad)?;
            let name = s["name"].as_str().ok_or_else(bad)?;
            let storage = s["storage"].as_str().ok_or_else(bad)?;
            let offset =
                usize::try_from(s["offset"].as_u64().ok_or_else(bad)?).map_err(|_| bad())?;
            let len = usize::try_from(s["len"].as_u64().ok_or_else(bad)?).map_err(|_| bad())?;
            if !safe(run) || run.contains('/') || !safe(name) || !safe(storage) {
                return Err(bad());
            }
            let bytes = raw.get(&format!("{root}/{}", storage)).ok_or_else(bad)?;
            let end = offset.checked_add(len).ok_or_else(bad)?;
            recovered = recovered.checked_add(len).ok_or_else(bad)?;
            if recovered > LIMIT {
                return Err(bad());
            }
            let value = bytes.get(offset..end).ok_or_else(bad)?.to_vec();
            if !runs.contains_key(run) {
                order.push(run.to_owned());
            }
            if runs
                .entry(run.to_owned())
                .or_default()
                .insert(name.to_owned(), value)
                .is_some()
            {
                return Err(bad());
            }
        }
    } else {
        // Import archives from the preceding multiple-run layout without extraction.
        for (name, body) in raw {
            let (run, name) = name.split_once('/').ok_or_else(bad)?;
            if !runs.contains_key(run) {
                order.push(run.to_owned());
            }
            runs.entry(run.into())
                .or_default()
                .insert(name.into(), body);
        }
    }
    Ok((root, runs, order))
}
fn read_run(dir: &Path, base: &Path, files: &mut Files, total: &mut usize) -> io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let m = entry.file_type()?;
        if m.is_dir() {
            read_run(&entry.path(), base, files, total)?;
        } else if m.is_file() {
            let path = entry.path();
            let name = path
                .strip_prefix(base)
                .map_err(|_| bad())?
                .to_str()
                .ok_or_else(bad)?
                .to_owned();
            if !safe(&name) || name == INDEX || name == SNAPSHOTS {
                return Err(bad());
            }
            use std::os::unix::fs::OpenOptionsExt;
            let mut f = fs::OpenOptions::new()
                .read(true)
                .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
                .open(path)?;
            let mut bytes = Vec::new();
            (&mut f)
                .take((LIMIT.saturating_sub(*total) + 1) as u64)
                .read_to_end(&mut bytes)?;
            *total = total.checked_add(bytes.len()).ok_or_else(bad)?;
            if *total > LIMIT || files.len() >= 8192 {
                return Err(bad());
            }
            files.insert(name, bytes);
        } else {
            return Err(bad());
        }
    }
    Ok(())
}
pub fn prepare(old: Option<&Path>, run: &Path, out: &Path) -> io::Result<String> {
    let id = run.file_name().and_then(|s| s.to_str()).ok_or_else(bad)?;
    if !safe(id) || id.contains('/') {
        return Err(bad());
    }
    let (root, mut runs, mut order) = if let Some(old) = old {
        previous(old)?
    } else {
        (id.to_owned(), Runs::new(), Vec::new())
    };
    let mut current = Files::new();
    read_run(run, run, &mut current, &mut 0)?;
    runs.insert(id.to_owned(), current); // Snapshot/final/retry replaces this operation, never duplicates it.
    if runs
        .values()
        .flat_map(|f| f.values())
        .map(|b| b.len())
        .sum::<usize>()
        > LIMIT
    {
        return Err(bad());
    }
    let mut merged = Files::new();
    let mut spans = Vec::<Value>::new();
    // Preserve publication order across retries and wall-clock changes.
    order.retain(|r| r != id);
    order.push(id.to_owned());
    for run in order {
        let files = runs.remove(&run).ok_or_else(bad)?;
        for (name, body) in files {
            // JSON remains a valid latest snapshot; older versions are indexed in one text log.
            let storage = if name.ends_with(".json") {
                SNAPSHOTS.to_owned()
            } else {
                name.clone()
            };
            let target = merged.entry(storage.clone()).or_default();
            let marker = format!(
                "\n# ===== operation={run} file={name} bytes={} =====\n",
                body.len()
            );
            target.extend_from_slice(marker.as_bytes());
            let offset = target.len();
            target.extend_from_slice(&body);
            spans.push(
                json!({"run":run,"name":name,"storage":storage,"offset":offset,"len":body.len()}),
            );
            if name.ends_with(".json") {
                merged.insert(name, body);
            }
        }
    }
    if spans.len() > 8192 {
        return Err(bad());
    }
    merged.insert(
        INDEX.into(),
        serde_json::to_vec(&json!({"schema":1,"spans":spans})).map_err(|_| bad())?,
    );
    if merged.values().map(|b| b.len()).sum::<usize>() > LIMIT {
        return Err(bad());
    }
    // Reject file/directory conflicts before writing any merged output.
    for name in merged.keys() {
        for (i, _) in name.match_indices('/') {
            if merged.contains_key(&name[..i]) {
                return Err(bad());
            }
        }
    }
    let dest = out.join(&root);
    fs::create_dir(&dest)?;
    for (name, bytes) in merged {
        let path = dest.join(name);
        fs::create_dir_all(path.parent().ok_or_else(bad)?)?;
        fs::write(path, bytes)?;
    }
    Ok(root)
}
