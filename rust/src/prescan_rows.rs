use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::path::Path;
use std::time::Instant;

pub struct ExactRow {
    pub kind: String,
    pub app: String,
    pub pkg: String,
    pub entry: String,
}

pub struct Plan {
    pub started: Instant,
    pub rows: Vec<ExactRow>,
    pub dir_map: HashMap<(String, String), u64>,
}

fn invalid() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "invalid prescan facts")
}

fn read(root: &Path, name: &str, optional: bool) -> io::Result<Vec<Vec<String>>> {
    let path = root.join(name);
    let metadata = match fs::symlink_metadata(&path) {
        Ok(value) => value,
        Err(error) if optional && error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };
    if !metadata.is_file() || metadata.len() > 64 * 1024 * 1024 {
        return Err(invalid());
    }
    let text = fs::read_to_string(path)?;
    if text.contains('\0') || text.contains('\r') {
        return Err(invalid());
    }
    Ok(text.lines().filter(|line| !line.is_empty())
        .map(|line| line.split('\t').map(str::to_owned).collect()).collect())
}

fn keyed(rows: Vec<Vec<String>>, width: usize, paired: bool) -> io::Result<HashMap<String, Vec<String>>> {
    let mut result = HashMap::new();
    for columns in rows {
        if columns.len() < width || columns[0].is_empty() {
            return Err(invalid());
        }
        let key = if paired { format!("{}\t{}", columns[0], columns[1]) } else { columns[0].clone() };
        if let Some(previous) = result.insert(key, columns.clone()) {
            if previous != columns { return Err(invalid()); }
        }
    }
    Ok(result)
}

fn decimal(value: &str) -> Option<u64> {
    if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) { return None; }
    value.parse().ok()
}

fn equal(left: &str, right: &str) -> bool {
    match (decimal(left), decimal(right)) {
        (Some(left), Some(right)) => left == right,
        _ => left == right,
    }
}

pub fn generate(mode: &str, root: &Path, backup: bool, user: bool, external: bool) -> io::Result<Plan> {
    let started = Instant::now();
    let remote = match mode { "local" => false, "remote" => true, _ => return Err(invalid()) };
    let first_full = remote && [".remote_firstfull_presize_active", ".remote_filelist_ok", ".remote_files"]
        .iter().all(|name| root.join(name).is_file());
    let selected = read(root, if remote { ".selected_apps.tsv" } else { ".local_selected_apps.tsv" }, false)?;
    let sizes = keyed(read(root, if remote { ".local_dir_sizes.tsv" } else { ".dir_sizes" }, false)?, 3, true)?;
    if selected.is_empty() || sizes.is_empty() { return Err(invalid()); }
    let summary = if first_full { HashMap::new() } else {
        keyed(read(root, if remote { ".remote_appdetails_summary.tsv" } else { ".local_appdetails_summary.tsv" }, false)?, if remote { 8 } else { 9 }, false)?
    };
    let exists = keyed(read(root, ".local_dir_exists.tsv", false)?, 2, true)?;
    let archives = if first_full { HashMap::new() } else {
        keyed(read(root, if remote { ".remote_payload_set.tsv" } else { ".local_archive_set.tsv" }, false)?, if remote { 1 } else { 2 }, !remote)?
    };
    let fast = if first_full { HashMap::new() } else {
        keyed(read(root, if remote { ".remote_fast_skip_ok" } else { ".local_fast_skip_ok" }, false)?, 1, false)?
    };
    let changed = if remote { keyed(read(root, ".listver_changed", true)?, 1, false)? } else { HashMap::new() };
    let fingerprints = keyed(read(root, ".dir_fingerprints", true)?, 3, true)?;
    let mut dir_map = HashMap::new();
    let mut counts = HashMap::<(String, String), usize>::new();
    for columns in read(root, ".dir_size_tar_input_map.tsv", true)? {
        if columns.len() != 4 { return Err(invalid()); }
        let bytes = decimal(&columns[3]).ok_or_else(invalid)?;
        let key = (columns[0].clone(), columns[1].clone());
        *counts.entry(key.clone()).or_default() += 1;
        dir_map.insert(key, bytes);
    }
    let has_archive = |app: &str, entry: &str| {
        if remote {
            archives.contains_key(&format!("{app}/{entry}.tar")) || archives.contains_key(&format!("{app}/{entry}.tar.zst"))
        } else { archives.contains_key(&format!("{app}\t{entry}")) }
    };
    let mut rows = Vec::new();
    let mut labels = HashSet::new();
    let mut packages = HashSet::new();
    for columns in selected {
        if columns.len() < 4 { return Err(invalid()); }
        let app = &columns[0];
        let pkg = &columns[1];
        if app.is_empty() || app.contains('/') || app.contains('\\') || pkg.is_empty()
            || !pkg.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'_' || byte == b'.')
            || !labels.insert(app.clone()) || !packages.insert(pkg.clone()) { return Err(invalid()); }
        if fast.contains_key(app) { continue; }
        let old = summary.get(app);
        let append = |rows: &mut Vec<ExactRow>, kind: &str, entry: &str| {
            rows.push(ExactRow { kind: kind.into(), app: app.clone(), pkg: pkg.clone(), entry: entry.into() });
        };
        if old.is_none_or(|old| old[2].is_empty() || columns[3].is_empty() || !equal(&old[2], &columns[3]))
            || !has_archive(app, "apk") || (remote && (changed.contains_key(app) || changed.contains_key(pkg))) {
            append(&mut rows, "APK", "apk");
        }
        if !backup || columns[2] == "1" || pkg == "bin.mt.plus" { continue; }
        let mut entries = Vec::new();
        if user { entries.extend([("user", 3, 9), ("user_de", 4, 10)]); }
        if user && old.is_none() {
            let special = match pkg.as_str() { "github.tornaco.android.thanos" => "thanox", "org.frknkrc44.hma_oss" => "hma", _ => "" };
            if !special.is_empty() && counts.get(&(pkg.clone(), special.into())) == Some(&1) {
                entries.push((special, usize::MAX, usize::MAX));
            }
        }
        if external { entries.extend([("data", 5, 11), ("obb", 6, 12), ("media", 7, 13)]); }
        for (entry, size_column, fingerprint_column) in entries {
            let key = format!("{pkg}\t{entry}");
            let tar_key = (pkg.clone(), entry.to_owned());
            if size_column == usize::MAX { append(&mut rows, "DIR", entry); continue; }
            if !exists.contains_key(&key) { continue; }
            let Some(current) = sizes.get(&key).and_then(|row| decimal(&row[2])) else { continue; };
            if current == 0 && counts.get(&tar_key) != Some(&1) { continue; }
            let fingerprint = fingerprints.get(&key).map(|row| row[2].as_str()).filter(|value| value.starts_with("stat-v1-"));
            let unchanged = old.is_some_and(|old| {
                old.get(size_column).and_then(|value| decimal(value)) == Some(current)
                    && fingerprint.is_some_and(|value| old.len() >= 14 && old[fingerprint_column] == value)
            });
            if !unchanged || !has_archive(app, entry) {
                if counts.get(&tar_key) != Some(&1) { return Err(invalid()); }
                append(&mut rows, "DIR", entry);
            }
        }
    }
    Ok(Plan { started, rows, dir_map })
}
