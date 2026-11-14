//! Flatten session diagnostics while retaining exact per-operation bytes in indexed spans.
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, HashMap},
    hash::{Hash, Hasher},
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
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK)
        .open(path)?;
    if !r.metadata()?.is_file(){return Err(bad());}
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
        let schema=index["schema"].as_u64().ok_or_else(bad)?;
        if !matches!(schema,1|2) || spans.len() > 8192 {
            return Err(bad());
        }
        for s in spans {
            let run = s["run"].as_str().ok_or_else(bad)?;
            let name = s["name"].as_str().ok_or_else(bad)?;
            let storage = s["storage"].as_str().ok_or_else(bad)?;
            let len = usize::try_from(s["len"].as_u64().ok_or_else(bad)?).map_err(|_| bad())?;
            if !safe(run) || run.contains('/') || !safe(name) || !safe(storage) {
                return Err(bad());
            }
            let bytes = raw.get(&format!("{root}/{}", storage)).ok_or_else(bad)?;
            recovered = recovered.checked_add(len).ok_or_else(bad)?;
            if recovered > LIMIT {
                return Err(bad());
            }
            let mut value=Vec::with_capacity(len);
            if schema==1 {
                let offset=usize::try_from(s["offset"].as_u64().ok_or_else(bad)?).map_err(|_|bad())?;
                let end=offset.checked_add(len).ok_or_else(bad)?;
                value.extend_from_slice(bytes.get(offset..end).ok_or_else(bad)?);
            } else {
                let segments=s["segments"].as_array().ok_or_else(bad)?;
                if segments.len()>131072{return Err(bad());}
                for segment in segments {
                    let offset=usize::try_from(segment[0].as_u64().ok_or_else(bad)?).map_err(|_|bad())?;
                    let count=usize::try_from(segment[1].as_u64().ok_or_else(bad)?).map_err(|_|bad())?;
                    if count==0 || value.len().checked_add(count).ok_or_else(bad)?>len{return Err(bad());}
                    let end=offset.checked_add(count).ok_or_else(bad)?;
                    value.extend_from_slice(bytes.get(offset..end).ok_or_else(bad)?);
                }
                if value.len()!=len{return Err(bad());}
            }
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
            return Err(io::Error::other(format!("unsupported diagnostic entry (symlink/socket/FIFO/device): {:?}",entry.path().strip_prefix(base).unwrap_or(&entry.path()))));
        }
    }
    Ok(())
}
// Split timestamp/header from the body, then bounded line-aligned blocks.
// Hashes are only a lookup accelerator: byte equality is mandatory on reuse.
fn chunks(body:&[u8])->impl Iterator<Item=&[u8]> {
    let mut remaining=body;let mut first=true;
    let text=std::str::from_utf8(body).is_ok();
    std::iter::from_fn(move||{
        if remaining.is_empty(){return None;}
        let max=remaining.len().min(4096);
        let mut end=if first {
            remaining[..max].iter().position(|b|*b==b'\n').map_or(max,|p|p+1)
        }else if max<remaining.len(){
            remaining[..max].iter().rposition(|b|*b==b'\n').map_or(max,|p|p+1)
        }else{max};
        if text {while end>0 && end<remaining.len() && remaining[end]&0xc0==0x80 {end-=1;}}
        first=false;let (chunk,rest)=remaining.split_at(end);remaining=rest;Some(chunk)
    })
}
type BlockTable=HashMap<u64,Vec<(usize,usize)>>;
fn block_hash(bytes:&[u8])->u64 {
    let mut hash=std::collections::hash_map::DefaultHasher::new();bytes.hash(&mut hash);hash.finish()
}
fn find_block(table:&BlockTable,target:&[u8],chunk:&[u8])->Option<(usize,usize)> {
    table.get(&block_hash(chunk))?.iter().copied().find(|&(offset,len)|len==chunk.len()&&target.get(offset..offset+len)==Some(chunk))
}
fn remember_block(table:&mut BlockTable,target:&[u8],offset:usize,len:usize)->bool {
    let chunk=&target[offset..offset+len];let candidates=table.entry(block_hash(chunk)).or_default();
    if candidates.iter().any(|&(o,n)|n==len&&target.get(o..o+n)==Some(chunk)){return false;}
    candidates.push((offset,len));true
}
fn remember_line(table:&mut BlockTable,target:&[u8],offset:usize,len:usize,budget:&mut usize) {
    if *budget>0 && remember_block(table,target,offset,len){*budget-=1;}
}
fn segment(parts:&mut Vec<[usize;2]>,offset:usize,len:usize) {
    if let Some(last)=parts.last_mut(){if last[0]+last[1]==offset {last[1]+=len;return;}}
    parts.push([offset,len]);
}
fn store_chunk(table:&mut BlockTable,target:&mut Vec<u8>,chunk:&[u8],parts:&mut Vec<[usize;2]>,line_budget:&mut usize,prior_end:usize)->usize {
    if let Some((offset,len))=find_block(table,target,chunk){segment(parts,offset,len);return len;}
    // Only changed text blocks need line-level matching. Unchanged blocks take
    // one lookup; binary/long-line data retain the bounded block fast path.
    let text=std::str::from_utf8(chunk).is_ok();
    let matches=if text {chunk.split_inclusive(|b|*b==b'\n').map(|line|find_block(table,target,line).filter(|(o,n)|o+n<=prior_end).map_or(0,|(_,n)|n)).sum::<usize>()}else{0};
    if matches>=128 {
        let mut reused=0;
        for line in chunk.split_inclusive(|b|*b==b'\n') {
            if let Some((offset,len))=find_block(table,target,line).filter(|(o,n)|o+n<=prior_end){segment(parts,offset,len);reused+=len;}
            else {let offset=target.len();target.extend_from_slice(line);remember_line(table,target,offset,line.len(),line_budget);segment(parts,offset,line.len());}
        }
        reused
    } else {
        let offset=target.len();target.extend_from_slice(chunk);remember_block(table,target,offset,chunk.len());segment(parts,offset,chunk.len());
        if text {let mut at=offset;for line in chunk.split_inclusive(|b|*b==b'\n'){remember_line(table,target,at,line.len(),line_budget);at+=line.len();}}
        0
    }
}
pub fn prepare(old: Option<&Path>, run: &Path, out: &Path) -> io::Result<String> {
    let id = run.file_name().and_then(|s| s.to_str()).ok_or_else(bad)?;
    if !safe(id) || id.contains('/') {
        return Err(bad());
    }
    let (root, mut runs, mut order) = if let Some(old) = old {
        previous(old).map_err(|e|io::Error::other(format!("read previous diagnostic archive: {e}")))?
    } else {
        (id.to_owned(), Runs::new(), Vec::new())
    };
    let mut current = Files::new();
    read_run(run, run, &mut current, &mut 0).map_err(|e|io::Error::other(format!("read current diagnostic run: {e}")))?;
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
    let mut blocks:HashMap<String,BlockTable>=HashMap::new();
    let mut line_budget=65536; // Bound optional fine-grained index memory across all logs.
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
            let table=blocks.entry(storage.clone()).or_default();
            let mut segments=Vec::new();let mut reused=0;
            let prior_end=target.len();
            let marker=format!("\n# ===== operation={run} file={name} bytes={} indexed-blocks =====\n",body.len());
            target.extend_from_slice(marker.as_bytes());
            for chunk in chunks(&body) {
                reused+=store_chunk(table,target,chunk,&mut segments,&mut line_budget,prior_end);
                if segments.len()>131072{return Err(io::Error::other("diagnostic segment limit exceeded"));}
            }
            if reused>0 {target.extend_from_slice(format!("\n# reused={reused} bytes; full operation order in {INDEX}\n").as_bytes());}
            spans.push(json!({"run":run,"name":name,"storage":storage,"len":body.len(),"segments":segments}));
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
        serde_json::to_vec(&json!({"schema":2,"encoding":"shared-blocks-v1","spans":spans})).map_err(|_| bad())?,
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

/// Decode indexed snapshots without extracting archive entries to the filesystem.
pub(super) fn history(archive:&Path)->io::Result<BTreeMap<String,Vec<u8>>>{
    let (_,mut runs,order)=previous(archive)?;let mut files=BTreeMap::new();
    for id in order{if let Some(run)=runs.remove(&id){for (name,body) in run{files.insert(format!("{id}/{name}"),body);}}}Ok(files)
}
