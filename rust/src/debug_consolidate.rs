//! Final-run diagnostic consolidation. Call only after producers have stopped.
//! Publish a durable replacement before removing any source; failures retain it.
use std::{fs::{self, OpenOptions}, io::{self, Write}, path::Path};

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

pub fn consolidate(root: &Path) -> io::Result<(usize, usize)> {
    if fs::symlink_metadata(root)?.file_type().is_symlink() || !root.is_dir() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput,"expected real run directory"));
    }
    let mut batches = std::collections::BTreeMap::<&str, Vec<(String, Vec<u8>)>>::new();
    let mut total = 0usize;
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let name = match entry.file_name().into_string() {Ok(n)=>n, Err(_)=>continue};
        let Some(out) = group(&name) else {continue};
        if !entry.file_type()?.is_file() {continue;}
        if entry.metadata()?.len()>16*1024*1024 {return Err(io::Error::other("detail too large; retained"));}
        let data=fs::read(entry.path())?;
        total=total.checked_add(data.len()).ok_or_else(||io::Error::other("size overflow"))?;
        if total>128*1024*1024 {return Err(io::Error::other("batch too large; retained"));}
        batches.entry(out).or_default().push((name,data));
    }
    let mut removed=0; let mut retained=0;
    for (out, mut entries) in batches {
        entries.sort_by(|a,b|a.0.cmp(&b.0));
        let dest=root.join(out);
        let previous=match fs::symlink_metadata(&dest) {
            Ok(m) if m.file_type().is_file() && m.len() <= 128*1024*1024 => fs::read(&dest)?,
            Ok(_) => return Err(io::Error::other("aggregate is not regular; sources retained")),
            Err(e) if e.kind()==io::ErrorKind::NotFound => Vec::new(),
            Err(e)=>return Err(e),
        };
        let temp=root.join(format!(".debug-merge-{}-{out}.tmp",std::process::id()));
        let mut f=OpenOptions::new().write(true).create_new(true).open(&temp)?;
        let result=(||->io::Result<()> {
            f.write_all(&previous)?;
            for (name,data) in &entries {
                writeln!(f,"\n===== SOURCE {} bytes={} =====",escaped(name),data.len())?;
                f.write_all(data)?;
                f.write_all(b"\n===== END SOURCE =====\n")?;
            }
            f.sync_all()?; drop(f);
            fs::rename(&temp,&dest)?;
            // On Android, persist the rename before unlinking the original facts.
            #[cfg(unix)] fs::File::open(root)?.sync_all()?;
            Ok(())
        })();
        if let Err(e)=result {let _=fs::remove_file(&temp);return Err(e);}
        for (name,data) in entries {
            let p=root.join(name);
            let unchanged=fs::symlink_metadata(&p).map(|m|m.file_type().is_file()).unwrap_or(false)
                && fs::read(&p).map(|v|v==data).unwrap_or(false);
            if unchanged && fs::remove_file(&p).is_ok() {removed+=1;} else {retained+=1;}
        }
    }
    Ok((removed,retained))
}
pub fn command(root: &str) -> i32 {
    let start=std::time::Instant::now();
    match consolidate(Path::new(root)) {
        Ok((merged,retained))=>{println!("DEBUG_CONSOLIDATE ok=1 merged={merged} retained={retained} elapsedMs={} schema=debug-consolidate-v1",start.elapsed().as_millis());0}
        Err(e)=>{eprintln!("DEBUG_CONSOLIDATE ok=0 originals=retained-or-already-published error={e}");1}
    }
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
}
