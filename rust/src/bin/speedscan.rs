#[path = "../tar_source.rs"]
mod tar_source;
#[path = "../backup_run.rs"]
mod backup_run;
#[path = "../payload_stats.rs"]
mod payload_stats;
use speedbackup_native_rs::*;
#[path = "../tar_input.rs"]
mod tar_input;
#[path = "../restore_manifest.rs"]
mod restore_manifest;
#[path = "../orphan_plan.rs"]
mod orphan_plan;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::env;
use std::ffi::CString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, BufRead, BufReader, BufWriter, Write, Read};
use std::os::raw::{c_char, c_int, c_uint, c_ulong};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::thread;
use std::time::Instant;

const VERSION: &str = "r713-api28-r29-symlink-owner-202607232022";

struct DirTar {
    idx: usize,
    root: PathBuf,
    external: bool,
    math: tar_input::Accumulator,
    valid: bool,
}
impl DirTar {
    fn add(&mut self, path: &Path, meta: &fs::Metadata) {
        let rel = match path.strip_prefix(&self.root) { Ok(p) => p, Err(_) => return };
        self.add_relative(rel, None, meta);
    }
    fn add_file(&mut self, dir: &Path, name: &[u8], meta: &fs::Metadata) {
        if self.root.parent() == Some(dir) && self.root.file_name().map(|n| n.as_bytes()) == Some(name) {
            self.add_relative(Path::new(""), None, meta);
        } else if let Ok(rel) = dir.strip_prefix(&self.root) {
            self.add_relative(rel, Some(name), meta);
        }
    }
    fn add_relative(&mut self, rel: &Path, leaf: Option<&[u8]>, meta: &fs::Metadata) {
        use std::os::unix::fs::FileTypeExt;
        let root = match self.root.file_name() { Some(n) => n.as_bytes(), None => { self.valid = false; return; } };
        let mut member = root.to_vec();
        if !rel.as_os_str().is_empty() { member.push(b'/'); member.extend_from_slice(rel.as_os_str().as_bytes()); }
        if let Some(name) = leaf { member.push(b'/'); member.extend_from_slice(name); }
        if tar_input::excluded(&member, root, self.external) { return; }
        let ft = meta.file_type();
        if ft.is_socket() { return; }
        if ft.is_dir() { member.push(b'/'); }
        let kind = if ft.is_file() { b'f' } else if ft.is_dir() { b'd' } else if ft.is_symlink() { b'l' } else { b'p' };
        self.math.add(&member, kind, meta.len(), meta.dev(), meta.ino(), meta.nlink());
    }
}

fn dir_tar_add(accs: &mut [DirTar], path: &Path, meta: &fs::Metadata) {
    for acc in accs { acc.add(path, meta); }
}

fn dir_tar_error(accs: &mut [DirTar], path: &Path) {
    for acc in accs { if path.starts_with(&acc.root) || acc.root.starts_with(path) { acc.valid = false; } }
}

#[cfg(test)]
mod fused_traversal_tests {
    use super::*;
    #[test]
    fn gross_cache_and_tar_share_the_walk() {
        let root = env::temp_dir().join(format!("r694-fused-{}", std::process::id()));
        fs::create_dir_all(root.join("cache")).unwrap();
        fs::create_dir_all(root.join("sub")).unwrap();
        fs::write(root.join("normal"), vec![0; 10001]).unwrap();
        fs::write(root.join("cache/skip"), vec![0; 5000]).unwrap();
        fs::write(root.join("sub/file"), vec![0; 513]).unwrap();
        fs::hard_link(root.join("normal"), root.join("hard")).unwrap();
        std::os::unix::fs::symlink("normal", root.join("sym")).unwrap();
        let targets = vec![(0, root.clone()), (1, root.join("cache"))];
        let mut tar = vec![DirTar {
            idx: 0,
            root: root.clone(),
            external: false,
            math: tar_input::Accumulator::default(),
            valid: true,
        }];
        let (values, stats) = scan_root_for_targets(&root, &targets, &mut tar);
        assert_eq!(values, vec![(0, 25515), (1, 5000)]);
        assert_eq!(stats.files, 4);
        assert_eq!(stats.file_metadata_calls, 4);
        assert_eq!(stats.legacy_fallback_roots, 0);
        assert!(tar[0].valid);
        assert_eq!(tar_input::finish(tar[0].math.bytes), 20480);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn appdetails_seed_index_required_meta_matches_bundle_contract() {
        assert!(appdetails_required_meta_ok(
            r#"{"Meta":{"PackageName":"com.example","apk_version":7}}"#
        ));
        assert!(appdetails_required_meta_ok(
            r#"{"App":{"PackageName":"com.example","apk_version":"7","app_state":{}}}"#
        ));
        assert!(!appdetails_required_meta_ok(
            r#"{"PackageName":"com.example","apk_version":7}"#
        ));
        assert!(!appdetails_required_meta_ok(
            r#"{"Meta":{"PackageName":"com.example"}}"#
        ));
        assert!(!appdetails_required_meta_ok(
            r#"{"Meta":{"apk_version":7}}"#
        ));
        assert!(!appdetails_required_meta_ok(
            r#"{"A":{"PackageName":"com.example"},"B":{"apk_version":7}}"#
        ));
        // jq's contract checks non-null, not truthiness, type or nonempty text.
        assert!(appdetails_required_meta_ok(
            r#"{"Meta":{"PackageName":"","apk_version":false}}"#
        ));
        assert!(appdetails_required_meta_ok(
            r#"{"Meta":{"PackageName":{},"apk_version":[]}}"#
        ));
    }

    #[test]
    fn appdetails_seed_index_rejects_invalid_document_and_nested_fragments() {
        assert!(!appdetails_required_meta_ok(
            "\u{00a0}{\"Meta\":{\"PackageName\":\"p\",\"apk_version\":7}}"
        ));
        for body in [
            r#"{"Meta":{"PackageName":"p","apk_version":7}"#,
            r#"{"Meta":{"PackageName":"p","apk_version":7}} GARBAGE"#,
            r#"{"Meta":{"PackageName":"p","apk_version":7},}"#,
            r#"{"Meta":{"PackageName":"p","apk_version":7},"bad":[1,]}"#,
            r#"{"Meta":{"A":{"PackageName":"p"},"B":{"apk_version":7}}}"#,
            r#"{"Meta":{"PackageName":null,"apk_version":null,"nested":{"PackageName":"p","apk_version":7}}}"#,
        ] {
            assert!(
                !appdetails_required_meta_ok(body),
                "accepted invalid metadata: {body}"
            );
        }
    }

    #[test]
    fn appdetails_seed_index_decodes_keys_and_uses_last_duplicate() {
        assert!(appdetails_required_meta_ok(
            r#"{"Meta":{"Package\u004eame":"p","apk_version":7}}"#
        ));
        assert!(!appdetails_required_meta_ok(
            r#"{"Meta":{"PackageName":"p","Package\u004eame":null,"apk_version":7}}"#
        ));
        assert!(appdetails_required_meta_ok(
            r#"{"Meta":{"PackageName":null,"PackageName":"p","apk_version":7}}"#
        ));
        assert!(!appdetails_required_meta_ok(
            r#"{"Meta":{"PackageName":"p","apk_version":7},"Meta":null}"#
        ));
        assert!(!appdetails_required_meta_ok(
            r#"{"應用":{"PackageName":"p","apk_version":7},"\u61c9\u7528":null}"#
        ));
    }

    #[test]
    fn appdetails_seed_index_drops_invalid_files_and_preserves_valid_seed() {
        let root = env::temp_dir().join(format!("r698-meta-{}", std::process::id()));
        for (app, body) in [
            ("Valid", r#"{"Meta":{"PackageName":"p","apk_version":7}}"#),
            (
                "Truncated",
                r#"{"Meta":{"PackageName":"p","apk_version":7}"#,
            ),
            (
                "Nested",
                r#"{"Meta":{"A":{"PackageName":"p"},"B":{"apk_version":7}}}"#,
            ),
        ] {
            fs::create_dir_all(root.join(app)).unwrap();
            fs::write(root.join(app).join("app_details.json"), body).unwrap();
        }
        let seed = root.join("seed.lst");
        let prefix = root.join("index");
        let args = vec![
            "speedscan".into(),
            "appdetails-seed-index".into(),
            root.to_string_lossy().into_owned(),
            seed.to_string_lossy().into_owned(),
            prefix.to_string_lossy().into_owned(),
        ];
        assert_eq!(cmd_appdetails_seed_index(&args), 0);
        assert_eq!(fs::read_to_string(&seed).unwrap(), "Valid\n");
        assert!(root.join("Valid/app_details.json").is_file());
        assert!(!root.join("Truncated/app_details.json").exists());
        assert!(!root.join("Nested/app_details.json").exists());
        assert!(fs::read_to_string(root.join("index.stats"))
            .unwrap()
            .starts_with("3\t1\t2\t3\t"));
        fs::remove_file(root.join("Valid/app_details.json")).unwrap();
        assert_eq!(cmd_appdetails_seed_index(&args), 5);
        assert_eq!(fs::read_to_string(&seed).unwrap(), "");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn appdetails_seed_expansion_allows_only_complete_payload_growth() {
        assert!(appdetails_seed_expansion_allowed(119, 119, 9, 0, 0, 0));
        assert!(!appdetails_seed_expansion_allowed(118, 119, 9, 0, 0, 0));
        assert!(!appdetails_seed_expansion_allowed(119, 119, 9, 1, 0, 0));
        assert!(!appdetails_seed_expansion_allowed(119, 119, 9, 0, 1, 0));
        assert!(!appdetails_seed_expansion_allowed(119, 119, 9, 0, 0, 1));
        assert!(!appdetails_seed_expansion_allowed(119, 119, 0, 0, 0, 0));
    }
}

fn usage() {
    eprintln!("speedscan {}", VERSION);
    eprintln!("usage:");
    eprintln!("  speedscan dir-size PATH");
    eprintln!("  speedscan dir-size-map MANIFEST");
    eprintln!("  speedscan dir-size-manifest PKG_LIST OUT_MANIFEST OUT_EXISTS BACKUP_MODE BACKUP_OBB BACKUP_USER ANDROID_ROOT USER_ROOT USER_DE_ROOT");
    eprintln!("  speedscan tsv-decimal-sum FILE COLUMN");
    eprintln!("  speedscan file-list ROOT");
    eprintln!("  speedscan list-total-size LIST");
    eprintln!("  speedscan batch-stat LIST");
    eprintln!("  speedscan batch-exists LIST");
    eprintln!("  speedscan batch-chmod MODE LIST");
    eprintln!("  speedscan batch-chown UID GID LIST");
    eprintln!("  speedscan tree-chown UID GID ROOT");
    eprintln!("  speedscan tree-fixup UID GID ROOT [DIR_MODE|-] [FILE_MODE|-]");
    eprintln!("  speedscan has-files ROOT");
    eprintln!("  speedscan manifest ROOT OUT");
    eprintln!("  speedscan scan-summary ROOT [MANIFEST_OUT|-]");
    eprintln!("  speedscan path-audit ROOT LIST");
    eprintln!("  speedscan label-audit ROOT [MAX_ROWS]");
    eprintln!("  speedscan facts ROOT [FACTS_OUT|-]");
    eprintln!("  speedscan restore-facts ROOT [FACTS_OUT|-]");
    eprintln!("  speedscan appdetails-index ROOT OUT [MAXDEPTH] [MINDEPTH]");
    eprintln!("  speedscan file-list-abs-filter ROOT OUT SKIP_APPDETAILS [EXCLUDE_PREFIX]");
    eprintln!("  speedscan selected-list APPLIST BLACKLIST OUT BLACKLIST_MODE");
    eprintln!("  speedscan apk-size-map PKG_APK_PATHS OUT");
    eprintln!("  speedscan backup-prescan-exact-input EXACT_ROWS DIR_TAR_MAP PKG_APK_PATHS DETAILS_OUT STATS_OUT");
    eprintln!("  speedscan backup-prescan-summary SELECTED DIRSIZES APKMAP RSKIP LSKIP OUT REMOTE_STREAM REMOTE_TYPE");
    eprintln!("  speedscan backup-root-index ROOT OUT [MAXDEPTH]");
    eprintln!("  speedscan storage-summary PATH");
    eprintln!("  speedscan checksum-list ROOT OUT");
    eprintln!("  speedscan manifest-verify ROOT MANIFEST");
    eprintln!("  speedscan run-tmpdir-facts BASE OUT [PREFIX]");
    eprintln!("  speedscan zst-file-facts FILE");
    eprintln!("  speedscan tree-pack-plan ROOT OUT [EXCLUDE_FILE|-] [MAX_ROWS|-]");
    eprintln!("  speedscan entry-size-facts ROOT OUT [EXCLUDE_FILE|-] [MAX_ROWS|-]");
    eprintln!("  speedscan changed-entry-facts MANIFEST OUT");
    eprintln!("  speedscan local-fastskip-join SELECTED SUMMARY STATE DIRSIZES EXISTS ARCHIVES BLACKSET OUT DIAG STATS BACKUP_MODE BACKUP_OBB BACKUP_USER BLACKLIST_MODE");
    eprintln!("  speedscan local-fastskip-presize-plan SELECTED SUMMARY STATE EXISTS ARCHIVES BLACKSET OUT_MANIFEST OUT_STATS OUT_DIAG BACKUP_MODE BACKUP_OBB BACKUP_USER BLACKLIST_MODE ANDROID_ROOT USER_ROOT USER_DE_ROOT");
    eprintln!("  speedscan local-fastskip-presize-plan-v4 SELECTED SUMMARY STATE BLACKSET BACKUP_ROOT OUT_EXISTS OUT_ARCHIVES OUT_MANIFEST OUT_STATS OUT_DIAG OUT_TINY BACKUP_MODE BACKUP_OBB BACKUP_USER BLACKLIST_MODE ANDROID_ROOT USER_ROOT USER_DE_ROOT");
    eprintln!("  speedscan local-fastskip-presize-bundle-v1 RAW_APPLIST PKG_VER_MAP APPDETAILS_ROOT CURRENT_APPSTATE_TSV|- BLACKSET BACKUP_ROOT OUT_SELECTED OUT_SUMMARY OUT_STATE OUT_EXISTS OUT_ARCHIVES OUT_MANIFEST OUT_STATS OUT_DIAG OUT_TINY BACKUP_MODE BACKUP_OBB BACKUP_USER BLACKLIST_MODE ANDROID_ROOT USER_ROOT USER_DE_ROOT");
    eprintln!("  speedscan remote-fastskip-presize-bundle-v1 RAW_APPLIST PKG_VER_MAP APPDETAILS_ROOT CURRENT_APPSTATE_TSV|- BLACKSET REMOTE_PAYLOAD_RELS OUT_PAYLOAD_SET OUT_SELECTED OUT_SUMMARY OUT_STATE OUT_EXISTS OUT_ARCHIVES OUT_MANIFEST OUT_STATS OUT_DIAG OUT_TINY BACKUP_MODE BACKUP_OBB BACKUP_USER BLACKLIST_MODE ANDROID_ROOT USER_ROOT USER_DE_ROOT");
    eprintln!("  speedscan backup-entry-presence-map SELECTED OUT BACKUP_MODE BACKUP_OBB BACKUP_USER ANDROID_ROOT USER_ROOT USER_DE_ROOT");
    eprintln!("  speedscan payload-archive-set PAYLOAD_SET OUT");
    eprintln!("  speedscan remote-stream-local-read-plan SELECTED DIRSIZES OUT BACKUP_MODE BACKUP_OBB BACKUP_USER ANDROID_ROOT USER_ROOT USER_DE_ROOT\n  speedscan remote-stream-local-read-plan-v2 SELECTED DIRSIZES EXISTS OUT BACKUP_MODE BACKUP_OBB BACKUP_USER\n  speedscan remote-stream-local-read-final-plan SELECTED DIRSIZES EXISTS REMOTE_SUMMARY PAYLOAD_SET OUT STATS BACKUP_MODE BACKUP_OBB BACKUP_USER");
    eprintln!("  speedscan selected-apps-map RAW_APPLIST PKG_VER_MAP OUT");
    eprintln!("  speedscan appdetails-summary-map ROOT OUT");
    eprintln!("  speedscan appstate-match-map ROOT CURRENT_APPSTATE_TSV OUT");
    eprintln!("  speedscan stream-entry-perf-stage PERF PENDING REMOTE_TYPE RB COMP RC ORIGIN SOURCE_PATH PKG LABEL ENTRY");
    eprintln!("  speedscan stream-entry-perf-finalize PENDING WEBDAV_INFO");
    eprintln!("  speedscan restore-tree-verify ROOT MANIFEST");
    eprintln!("  speedscan restore-tree-manifest-bytes ROOT MANIFEST");
    eprintln!("  speedscan restore-tree-verify-bytes ROOT MANIFEST");
    eprintln!("  speedscan app-media-index ROOT OUT [MAXDEPTH|-] [MAX_ROWS|-] [EXCLUDE_FILE|-]");
    eprintln!("  speedscan appdetails-bundle-audit ROOT REMOTE_FILES|- SEED_APPS|- SEED_STATE SEED_COUNT OUT_PREFIX [ALLOW_SHRINK]");
    eprintln!("  speedscan appdetails-health-batch APP_LIST ROOT OUT_PREFIX [LABEL_SUFFIX]");
    eprintln!("  speedscan appdetails-bundle-manifest ROOT OUT_PREFIX");
    eprintln!("  speedscan appdetails-seed-index ROOT SEED_OUT OUT_PREFIX");
    eprintln!("  speedscan remote-manifest-plan REMOTE_FILES|- BUNDLE_ROOT|- INSTALLED_PACKAGES|- OUT_PREFIX");
    eprintln!("  speedscan restore-payload-plan APP_DIR APP_DETAILS|- OUT_PREFIX");
    eprintln!("  speedscan manifest-diff-cache-index SELECTED REMOTE_SUMMARY DIRSIZES PAYLOAD_SET CHANGED OUT_PREFIX BACKUP_MODE BACKUP_OBB BACKUP_USER");
    eprintln!("  speedscan capabilities");
}


fn next_c_line_lossy<R: BufRead>(br: &mut R, buf: &mut Vec<u8>) -> Option<String> {
    buf.clear();
    match br.read_until(b'\n', buf) {
        Ok(0) => None,
        Ok(_) => {
            while matches!(buf.last(), Some(b'\n' | b'\r')) { buf.pop(); }
            Some(String::from_utf8_lossy(buf).into_owned())
        }
        Err(_) => None,
    }
}

fn scan(root: &Path) -> ScanResult {
    let mut res = ScanResult::default();
    let mut noop = |_: &Path, _: &fs::Metadata, _: usize, _: &mut ScanResult| Ok(());
    let _ = walk_no_follow(root, root, 0, None, &mut res, &mut noop);
    res
}
fn cmd_dir_size(path: &str) -> i32 { if path.is_empty() { return 2; } println!("{}", scan(Path::new(path)).bytes); 0 }
fn path_nested_collapse_safe(ancestor: &Path, target: &Path) -> bool {
    if ancestor == target { return true; }
    if !target.starts_with(ancestor) { return false; }
    // If the ancestor itself is a symlink, an independent scan of a deeper
    // target can traverse through it while a no-follow scan of the ancestor
    // cannot. Keep that deeper target independent as well.
    match fs::symlink_metadata(ancestor) {
        Ok(m) if m.file_type().is_symlink() => return false,
        Ok(_) => {},
        Err(_) => return false,
    }
    // Do not collapse across a symlink component. Independent dir-size on a
    // nested target can reach through a symlink in an ancestor path while a
    // no-follow walk of the parent intentionally cannot. Keeping such rows as
    // separate scan roots preserves the previous semantics.
    let rel = match target.strip_prefix(ancestor) { Ok(v) => v, Err(_) => return false };
    let mut cur = ancestor.to_path_buf();
    for comp in rel.components() {
        cur.push(comp.as_os_str());
        match fs::symlink_metadata(&cur) {
            Ok(m) if m.file_type().is_symlink() => return false,
            Ok(_) => {},
            Err(_) => return false,
        }
    }
    true
}

#[derive(Default, Clone, Copy)]
struct DirSizeScanStats {
    files: u64,
    bytes: u64,
    target_checks: u64,
    direct_root_targets: u64,
    nested_targets: u64,
    route_dir_lookups: u64,
    nested_target_activations: u64,
    file_metadata_calls: u64,
    file_path_builds_avoided: u64,
    dir_entries: u64,
    legacy_fallback_roots: u64,
}

#[derive(Clone, Debug)]
struct DirSizeRootGroup {
    root: PathBuf,
    targets: Vec<(usize, PathBuf)>,
    estimate_bytes: u64,
}

#[derive(Clone, Debug)]
struct DirSizeRootStat {
    root: String,
    targets: usize,
    estimate_bytes: u64,
    dispatch_index: usize,
    files: u64,
    bytes: u64,
    target_checks: u64,
    route_dir_lookups: u64,
    file_path_builds_avoided: u64,
    elapsed_ms: u128,
}

fn dir_size_stat_token(s: &str) -> String {
    let mut out = String::new();
    for ch in s.chars().take(360) {
        match ch {
            '\t' | '\n' | '\r' | ' ' => out.push('_'),
            '=' => out.push_str("%3D"),
            _ => out.push(ch),
        }
    }
    if out.is_empty() { "-".to_string() } else { out }
}

fn scan_root_for_targets_legacy(root: &Path, targets: &[(usize, PathBuf)]) -> (Vec<(usize, u64)>, DirSizeScanStats) {
    let mut totals = vec![0u64; targets.len()];
    let mut stats = DirSizeScanStats::default();
    stats.legacy_fallback_roots = 1;
    let mut res = ScanResult::default();
    let mut f = |p: &Path, m: &fs::Metadata, _: usize, _: &mut ScanResult| {
        if m.is_file() {
            let len = m.len();
            stats.files = stats.files.wrapping_add(1);
            stats.bytes = stats.bytes.wrapping_add(len);
            stats.file_metadata_calls = stats.file_metadata_calls.wrapping_add(1);
            for (slot, (_, target)) in targets.iter().enumerate() {
                stats.target_checks = stats.target_checks.wrapping_add(1);
                if p.starts_with(target) { totals[slot] = totals[slot].wrapping_add(len); }
            }
        }
        Ok(())
    };
    let _ = walk_no_follow(root, root, 0, None, &mut res, &mut f);
    (targets.iter().enumerate().map(|(slot, (idx, _))| (*idx, totals[slot])).collect(), stats)
}

fn scan_dirsize_tree_r685(
    dir: &Path,
    active_slots: &[usize],
    target_dirs: &HashMap<PathBuf, Vec<usize>>,
    target_files: &HashMap<PathBuf, HashMap<Vec<u8>, Vec<usize>>>,
    totals: &mut [u64],
    stats: &mut DirSizeScanStats,
    tar: &mut [DirTar],
) {
    let rd = match fs::read_dir(dir) { Ok(v) => v, Err(_) => { dir_tar_error(tar, dir); return; } };
    let dir_len = dir.as_os_str().as_bytes().len();
    for item in rd {
        let entry = match item { Ok(v) => v, Err(_) => { dir_tar_error(tar, dir); continue; } };
        stats.dir_entries = stats.dir_entries.wrapping_add(1);
        let name = entry.file_name();
        if dir_len + 1 + name.as_os_str().as_bytes().len() + 1 > PATH_MAX_SAFE { dir_tar_error(tar, dir); continue; }
        let ft = match entry.file_type() { Ok(v) => v, Err(_) => { dir_tar_error(tar, dir); continue; } };
        if !ft.is_file() {
            let child = entry.path();
            match entry.metadata() { Ok(m) => dir_tar_add(tar, &child, &m), Err(_) => dir_tar_error(tar, &child) }
        }
        if ft.is_symlink() { continue; }
        if ft.is_file() {
            // DirEntry::metadata() is no-follow for a symlink DirEntry on Unix; file_type()
            // above also rejects symlinks before this call.  Avoid constructing a full
            // PathBuf for the common file case: 318k files on the r684 reference run.
            let meta = match entry.metadata() { Ok(v) => v, Err(_) => { dir_tar_error(tar, dir); continue; } };
            for acc in tar.iter_mut() { acc.add_file(dir, name.as_os_str().as_bytes(), &meta); }
            let len = meta.len();
            stats.files = stats.files.wrapping_add(1);
            stats.bytes = stats.bytes.wrapping_add(len);
            stats.file_metadata_calls = stats.file_metadata_calls.wrapping_add(1);
            stats.file_path_builds_avoided = stats.file_path_builds_avoided.wrapping_add(1);
            for slot in active_slots {
                totals[*slot] = totals[*slot].wrapping_add(len);
            }
            // Preserve legacy starts_with semantics for the rare case where a
            // collapsed nested target is itself a regular file.  Lookups are
            // keyed by parent directory + file name so the common file path
            // still avoids constructing a full PathBuf.
            if let Some(by_name) = target_files.get(dir) {
                if let Some(add) = by_name.get(name.as_os_str().as_bytes()) {
                    for slot in add { totals[*slot] = totals[*slot].wrapping_add(len); }
                    stats.nested_target_activations = stats.nested_target_activations.wrapping_add(add.len() as u64);
                }
            }
            continue;
        }
        if !ft.is_dir() { continue; }
        let child = entry.path();
        stats.route_dir_lookups = stats.route_dir_lookups.wrapping_add(1);
        if let Some(add) = target_dirs.get(&child) {
            let mut next_active = Vec::with_capacity(active_slots.len() + add.len());
            next_active.extend_from_slice(active_slots);
            for slot in add {
                if !next_active.contains(slot) { next_active.push(*slot); }
            }
            stats.nested_target_activations = stats.nested_target_activations.wrapping_add(add.len() as u64);
            scan_dirsize_tree_r685(&child, &next_active, target_dirs, target_files, totals, stats, tar);
        } else {
            scan_dirsize_tree_r685(&child, active_slots, target_dirs, target_files, totals, stats, tar);
        }
    }
}

fn scan_root_for_targets(root: &Path, targets: &[(usize, PathBuf)], tar: &mut [DirTar]) -> (Vec<(usize, u64)>, DirSizeScanStats) {
    // r685: route nested targets when entering directories instead of testing every
    // file path against every cache/code_cache target.  The direct root slot stays
    // active for the whole walk; a nested slot becomes active exactly when its
    // directory is entered. This also avoids constructing full paths for files.
    let mut totals = vec![0u64; targets.len()];
    let mut direct_root_slots: Vec<usize> = Vec::new();
    let mut target_dirs: HashMap<PathBuf, Vec<usize>> = HashMap::new();
    let mut target_files: HashMap<PathBuf, HashMap<Vec<u8>, Vec<usize>>> = HashMap::new();
    for (slot, (_, target)) in targets.iter().enumerate() {
        if target.as_path() == root {
            direct_root_slots.push(slot);
            continue;
        }
        match fs::symlink_metadata(target) {
            Ok(m) if m.is_file() => {
                if let (Some(parent), Some(name)) = (target.parent(), target.file_name()) {
                    target_files.entry(parent.to_path_buf()).or_default()
                        .entry(name.as_bytes().to_vec()).or_default().push(slot);
                }
            }
            Ok(m) if m.is_dir() => { target_dirs.entry(target.clone()).or_default().push(slot); }
            _ => {},
        }
    }
    // Every collapsed root is itself a manifest target. Keep a conservative parity
    // fallback for malformed/legacy manifests rather than changing output semantics.
    if direct_root_slots.is_empty() { dir_tar_error(tar, root); return scan_root_for_targets_legacy(root, targets); }
    let mut stats = DirSizeScanStats::default();
    stats.direct_root_targets = direct_root_slots.len() as u64;
    stats.nested_targets = targets.len().saturating_sub(direct_root_slots.len()) as u64;
    let root_meta = match fs::symlink_metadata(root) {
        Ok(v) => v,
        Err(_) => { dir_tar_error(tar, root); return (targets.iter().map(|(idx, _)| (*idx, 0)).collect(), stats); }
    };
    dir_tar_add(tar, root, &root_meta);
    if root_meta.file_type().is_symlink() {
        return (targets.iter().map(|(idx, _)| (*idx, 0)).collect(), stats);
    }
    if root_meta.is_file() {
        let len = root_meta.len();
        stats.files = 1;
        stats.bytes = len;
        stats.file_metadata_calls = 1;
        for slot in &direct_root_slots { totals[*slot] = totals[*slot].wrapping_add(len); }
    } else if root_meta.is_dir() {
        scan_dirsize_tree_r685(root, &direct_root_slots, &target_dirs, &target_files, &mut totals, &mut stats, tar);
    }
    (targets.iter().enumerate().map(|(slot, (idx, _))| (*idx, totals[slot])).collect(), stats)
}

fn dir_size_auto_workers(scan_roots: usize) -> usize {
    // r668: worker policy is based only on actual top-level scan roots after
    // nested-target collapse. Auxiliary cache/code_cache rows must not inflate
    // concurrency. An explicit SPEEDSCAN_DIRSIZE_WORKERS still overrides this.
    if scan_roots >= 600 { 16 }
    else if scan_roots >= 300 { 12 }
    else { 8 }
}

fn dir_size_root_priority(root: &Path, target_count: usize) -> u64 {
    let s = root.to_string_lossy();
    let class = if s.contains("/data/user/0/") || s.contains("/data/data/") { 600u64 }
        else if s.contains("/storage/emulated/") && s.contains("/Android/data/") { 500u64 }
        else if s.contains("/storage/emulated/") && s.contains("/Android/media/") { 450u64 }
        else if s.contains("/data/user_de/0/") { 400u64 }
        else if s.contains("/storage/emulated/") && s.contains("/Android/obb/") { 350u64 }
        else { 100u64 };
    class.saturating_add((target_count as u64).min(99))
}

fn load_dir_size_hints(path: Option<&str>) -> HashMap<(String, String), u64> {
    let mut out = HashMap::new();
    let p = match path { Some(v) if !v.is_empty() => v, _ => return out };
    for r in read_tsv_rows(p) {
        if r.len() < 8 { continue; }
        let pkg = r[1].clone();
        for (entry, col) in [("user",3usize),("user_de",4usize),("data",5usize),("obb",6usize),("media",7usize)] {
            let raw = r.get(col).map(|v| v.as_str()).unwrap_or("");
            if raw.is_empty() || raw == "null" || !raw.bytes().all(|b| b.is_ascii_digit()) { continue; }
            if let Ok(v) = raw.parse::<u64>() { out.insert((pkg.clone(), entry.to_string()), v); }
        }
    }
    out
}

fn dir_size_group_estimate(group: &(PathBuf, Vec<(usize, PathBuf)>), rows: &[(String,String,String)], hints: &HashMap<(String,String),u64>) -> u64 {
    let mut estimate = 0u64;
    for (idx, target) in &group.1 {
        if target.as_path() != group.0.as_path() { continue; }
        if let Some(row) = rows.get(*idx) {
            if let Some(v) = hints.get(&(row.0.clone(), row.1.clone())) { estimate = estimate.max(*v); }
        }
    }
    estimate
}

fn cmd_dir_size_map(manifest: &str) -> i32 {
    let command_start = Instant::now();
    if manifest.is_empty() { return 2; }
    let f = match File::open(manifest) { Ok(f) => f, Err(e) => { eprintln!("speedscan: open manifest failed: {}: {}", manifest, c_strerror(&e)); return 3; } };
    let mut rc = 0;
    let mut br = BufReader::new(f);
    let mut line_buf = Vec::<u8>::new();
    let mut rows: Vec<(String, String, String)> = Vec::new();
    while let Some(line) = next_c_line_lossy(&mut br, &mut line_buf) {
        if line.is_empty() { continue; }
        let mut cols = line.splitn(3, '\t');
        let pkg = match cols.next() { Some(v) => v, None => { rc = 4; continue; } };
        let typ = match cols.next() { Some(v) => v, None => { rc = 4; continue; } };
        let path = match cols.next() { Some(v) => v, None => { rc = 4; continue; } };
        rows.push((pkg.to_owned(), typ.to_owned(), path.to_owned()));
    }
    if rows.is_empty() { return rc; }

    let mut raw_groups: Vec<(PathBuf, Vec<(usize, PathBuf)>)> = Vec::new();
    for (idx, row) in rows.iter().enumerate() {
        let target = PathBuf::from(&row.2);
        let mut best: Option<usize> = None;
        let mut best_depth = usize::MAX;
        for (gidx, (root, _)) in raw_groups.iter().enumerate() {
            if path_nested_collapse_safe(root, &target) {
                let depth = root.components().count();
                if depth < best_depth { best = Some(gidx); best_depth = depth; }
            }
        }
        if let Some(gidx) = best {
            raw_groups[gidx].1.push((idx, target));
            continue;
        }
        let mut targets = vec![(idx, target.clone())];
        let mut keep = Vec::with_capacity(raw_groups.len() + 1);
        for (old_root, old_targets) in raw_groups.drain(..) {
            if path_nested_collapse_safe(&target, &old_root) { targets.extend(old_targets); }
            else { keep.push((old_root, old_targets)); }
        }
        keep.push((target, targets));
        raw_groups = keep;
    }

    let hint_file = env::var("SPEEDSCAN_DIRSIZE_HINTS_FILE").ok().filter(|v| !v.is_empty());
    let hints = load_dir_size_hints(hint_file.as_deref());
    let hint_rows = hints.len();
    let mut root_groups: Vec<DirSizeRootGroup> = raw_groups.into_iter().map(|g| {
        let estimate_bytes = dir_size_group_estimate(&g, &rows, &hints);
        DirSizeRootGroup { root: g.0, targets: g.1, estimate_bytes }
    }).collect();
    let hinted_roots = root_groups.iter().filter(|g| g.estimate_bytes > 0).count();

    let requested_env = env::var("SPEEDSCAN_DIRSIZE_WORKERS").ok().and_then(|v| v.parse::<usize>().ok()).filter(|v| *v > 0);
    let policy_env = env::var("SPEEDSCAN_DIRSIZE_WORKER_POLICY").ok().filter(|v| !v.is_empty());
    let scan_roots = root_groups.len();
    let requested = requested_env.unwrap_or_else(|| dir_size_auto_workers(scan_roots));
    let workers = requested.clamp(1, 24).min(scan_roots.max(1));
    let worker_policy = policy_env.as_deref().unwrap_or_else(|| if requested_env.is_some() { "env" } else { "auto-r668-scanroots" });
    root_groups.sort_by(|a, b| {
        b.estimate_bytes.cmp(&a.estimate_bytes)
            .then_with(|| dir_size_root_priority(&b.root, b.targets.len()).cmp(&dir_size_root_priority(&a.root, a.targets.len())))
            .then_with(|| a.root.cmp(&b.root))
    });
    let schedule_policy = if hinted_roots > 0 { "old-size-lpt-r685" } else { "class-fallback-r685" };
    let plan_elapsed_ms = command_start.elapsed().as_millis();
    let stats_path = env::var("SPEEDSCAN_DIRSIZE_STATS_FILE").ok().filter(|v| !v.is_empty());
    let shared_groups = Arc::new(root_groups);
    let next = Arc::new(AtomicUsize::new(0));
    let results = Arc::new(Mutex::new(vec![0u64; rows.len()]));
    let tar_results = Arc::new(Mutex::new(vec![None; rows.len()]));
    let shared_rows = Arc::new(rows.clone());
    let scan_stats = Arc::new(Mutex::new(DirSizeScanStats::default()));
    let root_stats = Arc::new(Mutex::new(Vec::<DirSizeRootStat>::new()));
    let scan_start = Instant::now();
    let mut handles = Vec::with_capacity(workers);
    for _ in 0..workers {
        let groups_ref = Arc::clone(&shared_groups);
        let next_ref = Arc::clone(&next);
        let results_ref = Arc::clone(&results);
        let tar_results_ref = Arc::clone(&tar_results);
        let rows_ref = Arc::clone(&shared_rows);
        let stats_ref = Arc::clone(&scan_stats);
        let root_stats_ref = Arc::clone(&root_stats);
        handles.push(thread::spawn(move || {
            loop {
                let gidx = next_ref.fetch_add(1, Ordering::Relaxed);
                if gidx >= groups_ref.len() { break; }
                let group = &groups_ref[gidx];
                let root_start = Instant::now();
                let mut tar: Vec<DirTar> = group.targets.iter().filter_map(|(idx, root)| {
                    let entry = rows_ref[*idx].1.as_str();
                    if !matches!(entry, "user" | "user_de" | "data" | "obb" | "media") { return None; }
                    Some(DirTar { idx: *idx, root: root.clone(), external: matches!(entry, "data" | "obb" | "media"), math: tar_input::Accumulator::default(), valid: true })
                }).collect();
                let (vals, stats) = scan_root_for_targets(&group.root, &group.targets, &mut tar);
                if let Ok(mut out) = tar_results_ref.lock() {
                    for acc in tar { if acc.valid && acc.math.bytes > 0 { out[acc.idx] = Some(tar_input::finish(acc.math.bytes)); } }
                }
                let root_elapsed_ms = root_start.elapsed().as_millis();
                if let Ok(mut out) = results_ref.lock() { for (idx, bytes) in vals { out[idx] = bytes; } }
                if let Ok(mut total) = stats_ref.lock() {
                    total.files = total.files.wrapping_add(stats.files);
                    total.bytes = total.bytes.wrapping_add(stats.bytes);
                    total.target_checks = total.target_checks.wrapping_add(stats.target_checks);
                    total.direct_root_targets = total.direct_root_targets.wrapping_add(stats.direct_root_targets);
                    total.nested_targets = total.nested_targets.wrapping_add(stats.nested_targets);
                    total.route_dir_lookups = total.route_dir_lookups.wrapping_add(stats.route_dir_lookups);
                    total.nested_target_activations = total.nested_target_activations.wrapping_add(stats.nested_target_activations);
                    total.file_metadata_calls = total.file_metadata_calls.wrapping_add(stats.file_metadata_calls);
                    total.file_path_builds_avoided = total.file_path_builds_avoided.wrapping_add(stats.file_path_builds_avoided);
                    total.dir_entries = total.dir_entries.wrapping_add(stats.dir_entries);
                    total.legacy_fallback_roots = total.legacy_fallback_roots.wrapping_add(stats.legacy_fallback_roots);
                }
                if let Ok(mut roots) = root_stats_ref.lock() {
                    roots.push(DirSizeRootStat {
                        root: group.root.to_string_lossy().to_string(), targets: group.targets.len(), estimate_bytes: group.estimate_bytes,
                        dispatch_index: gidx, files: stats.files, bytes: stats.bytes, target_checks: stats.target_checks,
                        route_dir_lookups: stats.route_dir_lookups, file_path_builds_avoided: stats.file_path_builds_avoided, elapsed_ms: root_elapsed_ms,
                    });
                }
            }
        }));
    }
    for h in handles { if h.join().is_err() { return 5; } }
    let elapsed_ms = scan_start.elapsed().as_millis();
    let final_stats = match scan_stats.lock() { Ok(v) => *v, Err(_) => DirSizeScanStats::default() };
    let mut root_stats_vec = match root_stats.lock() { Ok(v) => v.clone(), Err(_) => Vec::new() };
    root_stats_vec.sort_by(|a, b| b.elapsed_ms.cmp(&a.elapsed_ms).then_with(|| b.bytes.cmp(&a.bytes)).then_with(|| a.root.cmp(&b.root)));
    let root_stats_path = env::var("SPEEDSCAN_DIRSIZE_ROOT_STATS_FILE").ok().filter(|v| !v.is_empty());
    if let Some(path) = &root_stats_path {
        if let Ok(mut rf) = File::create(path) {
            let _ = writeln!(rf, "root\ttargets\testimateBytes\tdispatchIndex\tfiles\tbytes\ttargetChecks\trouteDirLookups\tfilePathBuildsAvoided\telapsedMs");
            for r in &root_stats_vec {
                let _ = writeln!(rf, "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", tsv_sanitize(&r.root), r.targets, r.estimate_bytes, r.dispatch_index, r.files, r.bytes, r.target_checks, r.route_dir_lookups, r.file_path_builds_avoided, r.elapsed_ms);
            }
        }
    }
    let output_start = Instant::now();
    if let Ok(path) = env::var("SPEEDSCAN_DIRSIZE_TAR_INPUT_MAP_FILE") {
        let publish = || -> io::Result<()> {
            let tmp = format!("{}.part", path);
            let mut out = BufWriter::new(File::create(&tmp)?);
            let values = tar_results.lock().map_err(|_| io::Error::other("tar results poisoned"))?;
            for (idx, row) in rows.iter().enumerate() {
                if let Some(bytes) = values[idx] { writeln!(out, "{}\t{}\t{}\t{}", row.0, row.1, row.2, bytes)?; }
            }
            out.flush()?;
            drop(out);
            fs::rename(tmp, &path)
        };
        if publish().is_err() { return 6; }
    }
    {
        let stdout = io::stdout();
        let mut bw = BufWriter::new(stdout.lock());
        let out = match results.lock() { Ok(v) => v, Err(_) => return 5 };
        for (idx, row) in rows.iter().enumerate() {
            if writeln!(bw, "{}\t{}\t{}", row.0, row.1, out[idx]).is_err() { return 6; }
        }
        if bw.flush().is_err() { return 6; }
    }
    let output_elapsed_ms = output_start.elapsed().as_millis();
    let total_elapsed_ms = command_start.elapsed().as_millis();
    if let Some(stats_path) = stats_path {
        if let Ok(mut sf) = File::create(&stats_path) {
            let _ = writeln!(sf, "manifestRows\t{}", rows.len());
            let _ = writeln!(sf, "outputRows\t{}", rows.len());
            let _ = writeln!(sf, "scanRoots\t{}", scan_roots);
            let _ = writeln!(sf, "nestedCollapsed\t{}", rows.len().saturating_sub(scan_roots));
            let _ = writeln!(sf, "workers\t{}", workers);
            let _ = writeln!(sf, "requestedWorkers\t{}", requested);
            let _ = writeln!(sf, "workerPolicy\t{}", worker_policy);
            let _ = writeln!(sf, "schedulePolicy\t{}", schedule_policy);
            let _ = writeln!(sf, "hintRows\t{}", hint_rows);
            let _ = writeln!(sf, "hintedRoots\t{}", hinted_roots);
            let _ = writeln!(sf, "files\t{}", final_stats.files);
            let _ = writeln!(sf, "bytes\t{}", final_stats.bytes);
            let _ = writeln!(sf, "targetChecks\t{}", final_stats.target_checks);
            let _ = writeln!(sf, "directRootTargets\t{}", final_stats.direct_root_targets);
            let _ = writeln!(sf, "nestedTargets\t{}", final_stats.nested_targets);
            let _ = writeln!(sf, "routeDirLookups\t{}", final_stats.route_dir_lookups);
            let _ = writeln!(sf, "nestedTargetActivations\t{}", final_stats.nested_target_activations);
            let _ = writeln!(sf, "fileMetadataCalls\t{}", final_stats.file_metadata_calls);
            let _ = writeln!(sf, "filePathBuildsAvoided\t{}", final_stats.file_path_builds_avoided);
            let _ = writeln!(sf, "dirEntries\t{}", final_stats.dir_entries);
            let _ = writeln!(sf, "legacyFallbackRoots\t{}", final_stats.legacy_fallback_roots);
            if let Some(path) = &root_stats_path { let _ = writeln!(sf, "rootStatsFile\t{}", path); }
            for (idx, r) in root_stats_vec.iter().take(8).enumerate() {
                let _ = writeln!(sf, "rootTop{}\telapsedMs={};files={};bytes={};targetChecks={};routeDirLookups={};targets={};estimateBytes={};dispatchIndex={};root={}", idx + 1, r.elapsed_ms, r.files, r.bytes, r.target_checks, r.route_dir_lookups, r.targets, r.estimate_bytes, r.dispatch_index, dir_size_stat_token(&r.root));
            }
            let _ = writeln!(sf, "planElapsedMs\t{}", plan_elapsed_ms);
            let _ = writeln!(sf, "elapsedMs\t{}", elapsed_ms);
            let _ = writeln!(sf, "outputElapsedMs\t{}", output_elapsed_ms);
            let _ = writeln!(sf, "totalElapsedMs\t{}", total_elapsed_ms);
            let _ = writeln!(sf, "mode\tr685-dirsize-route-schedule");
        }
    }
    rc
}

fn decimal_add_assign(sum: &mut Vec<u8>, raw: &[u8]) -> bool {
    if raw.is_empty() || raw.iter().any(|b| !b.is_ascii_digit()) { return false; }
    let first = raw.iter().position(|b| *b != b'0').unwrap_or(raw.len().saturating_sub(1));
    let n = &raw[first..];
    let mut i = sum.len() as isize - 1;
    let mut j = n.len() as isize - 1;
    let mut carry = 0u8;
    let max_len = sum.len().max(n.len()) + 1;
    let mut rev = Vec::with_capacity(max_len);
    while i >= 0 || j >= 0 || carry != 0 {
        let a = if i >= 0 { sum[i as usize] - b'0' } else { 0 };
        let b = if j >= 0 { n[j as usize] - b'0' } else { 0 };
        let v = a + b + carry;
        rev.push(b'0' + (v % 10));
        carry = v / 10;
        i -= 1; j -= 1;
    }
    while i >= 0 { rev.push(sum[i as usize]); i -= 1; }
    while j >= 0 { rev.push(n[j as usize]); j -= 1; }
    rev.reverse();
    *sum = rev;
    true
}

fn cmd_tsv_decimal_sum(file: &str, column_s: &str) -> i32 {
    if file.is_empty() || column_s.is_empty() { return 2; }
    let column = match column_s.parse::<usize>() { Ok(v) if v > 0 => v, _ => return 2 };
    let f = match File::open(file) { Ok(v) => v, Err(e) => { eprintln!("speedscan: tsv-decimal-sum open failed: {}: {}", file, c_strerror(&e)); return 3; } };
    let mut br = BufReader::new(f);
    let mut line_buf = Vec::<u8>::new();
    let mut sum = vec![b'0'];
    while let Some(line) = next_c_line_lossy(&mut br, &mut line_buf) {
        let field = match line.split('\t').nth(column - 1) { Some(v) => v, None => continue };
        let _ = decimal_add_assign(&mut sum, field.as_bytes());
    }
    println!("{}", String::from_utf8_lossy(&sum));
    0
}

fn cmd_file_list(root_s: &str) -> i32 {
    if root_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    let mut res = ScanResult::default();
    let mut f = |p: &Path, m: &fs::Metadata, _: usize, _: &mut ScanResult| {
        if m.is_file() { println!("{}\t{}", rel_path(root, p), m.len()); }
        Ok(())
    };
    walk_no_follow(root, root, 0, None, &mut res, &mut f).map(|_| 0).unwrap_or(1)
}
fn cmd_list_total_size(list: &str) -> i32 {
    if list.is_empty() { return 2; }
    let mut total = 0u64;
    match read_lines(Path::new(list)) {
        Ok(lines) => { for l in lines { if let Ok(m) = fs::symlink_metadata(&l) { if m.is_file() { total = total.wrapping_add(m.len()); } } } },
        Err(e) => { eprintln!("speedscan: open list failed: {}: {}", list, c_strerror(&e)); return 3; }
    }
    println!("{}", total); 0
}
fn cmd_batch_stat(list: &str) -> i32 {
    if list.is_empty() { return 2; }
    // Faithful port: row is path/exists/type/mode/uid/gid/size/mtime/errno/
    // dev/ino/nlink (12 fields) - the previous implementation dropped the
    // errno placeholder and the dev/ino/nlink fields entirely.
    let lines = match read_lines(Path::new(list)) { Ok(v) => v, Err(e) => { eprintln!("speedscan: open list failed: {}: {}", list, c_strerror(&e)); return 3 } };
    let mut rc = 0;
    for p in lines { if p.is_empty() { continue; }
        match fs::symlink_metadata(&p) {
            Ok(m) => println!("{}\t1\t{}\t{:04o}\t{}\t{}\t{}\t{}\t0\t{}\t{}\t{}", p, stat_kind(&m), mode_octal(&m), m.uid(), m.gid(), m.len(), m.mtime(), m.dev(), m.ino(), m.nlink()),
            Err(e) => { println!("{}\t0\tmissing\t0000\t0\t0\t0\t0\t{}\t0\t0\t0", p, e.raw_os_error().unwrap_or(-1)); rc = 1; }
        }
    }
    rc
}
fn cmd_batch_exists(list: &str) -> i32 {
    if list.is_empty() { return 2; }
    let lines = match read_lines(Path::new(list)) {
        Ok(v) => v,
        Err(e) => { eprintln!("speedscan: open list failed: {}: {}", list, c_strerror(&e)); return 3; }
    };
    let mut rc = 0;
    for p in lines {
        if p.is_empty() { continue; }
        let exists = fs::symlink_metadata(&p).is_ok();
        println!("{}\t{}", p, if exists { 1 } else { 0 });
        if !exists { rc = 1; }
    }
    rc
}

extern "C" { fn chmod(path: *const c_char, mode: c_uint) -> c_int; }

fn errno_text(errno: i32) -> String { c_strerror(&std::io::Error::from_raw_os_error(errno)) }

fn path_len_c_join_ok(parent: &Path, name: &std::ffi::OsStr) -> bool {
    let blen = parent.as_os_str().as_bytes().len();
    let nlen = name.as_bytes().len();
    blen + 1 + nlen + 1 <= PATH_MAX_SAFE
}

fn path_len_c_join_root_rel_ok(root: &str, rel: &str) -> bool {
    let blen = root.as_bytes().len();
    let nlen = rel.as_bytes().len();
    blen + 1 + nlen + 1 <= PATH_MAX_SAFE
}

fn c_join_root_rel(root: &str, rel: &str) -> PathBuf {
    // C join_path() concatenates bytes; an absolute-looking `rel` does NOT
    // replace the root. The length check is intentionally done separately
    // with C's conservative +1 separator allowance.
    let mut s = String::with_capacity(root.len() + rel.len() + 1);
    s.push_str(root);
    if !root.ends_with('/') { s.push('/'); }
    s.push_str(rel);
    PathBuf::from(s)
}

fn validate_root_dir_for_speedscan(root_s: &str) -> Result<(), std::io::Error> {
    let meta = fs::symlink_metadata(root_s)?;
    if meta.is_dir() { Ok(()) } else { Err(std::io::Error::from_raw_os_error(0)) }
}

fn chmod_direct(path: &Path, mode: u32) -> Result<(), i32> {
    let c = match cstring_path(path) { Ok(v) => v, Err(_) => return Err(22) };
    let rc = unsafe { chmod(c.as_ptr(), mode as c_uint) };
    if rc == 0 { Ok(()) } else { Err(std::io::Error::last_os_error().raw_os_error().unwrap_or(-1)) }
}

fn lchown_direct(path: &Path, uid: u32, gid: u32) -> Result<(), i32> {
    lchown_path(path, uid, gid).map_err(|e| e.raw_os_error().unwrap_or(-1))
}

fn cmd_batch_chmod(mode_s: &str, list: &str) -> i32 {
    let mode = match parse_octal_mode_strict(mode_s) { Some(v) => v, None => return 2 };
    if list.is_empty() { return 2; }
    let lines = match read_lines(Path::new(list)) {
        Ok(v) => v,
        Err(e) => { eprintln!("speedscan: open list failed: {}: {}", list, c_strerror(&e)); return 3; }
    };
    let mut rc = 0;
    for p in lines {
        if p.is_empty() { continue; }
        let path = Path::new(&p);
        let before = match fs::symlink_metadata(path) {
            Ok(m) => m,
            Err(e) => {
                let errno = e.raw_os_error().unwrap_or(-1);
                println!("{}\t0\tchmod\t0000\t{:04o}\t{}\t{}", p, mode & 0o7777, errno, errno_text(errno));
                rc = 1;
                continue;
            }
        };
        if let Err(errno) = chmod_direct(path, mode) {
            println!("{}\t0\tchmod\t{:04o}\t{:04o}\t{}\t{}", p, mode_octal(&before), mode & 0o7777, errno, errno_text(errno));
            rc = 1;
            continue;
        }
        let after = match fs::symlink_metadata(path) {
            Ok(m) => m,
            Err(e) => {
                let errno = e.raw_os_error().unwrap_or(-1);
                println!("{}\t0\tchmod\t{:04o}\t{:04o}\t{}\t{}", p, mode_octal(&before), mode & 0o7777, errno, errno_text(errno));
                rc = 1;
                continue;
            }
        };
        println!("{}\t1\tchmod\t{:04o}\t{:04o}\t0\tOK", p, mode_octal(&before), mode_octal(&after));
    }
    rc
}
fn cmd_batch_chown(uid_s: &str, gid_s: &str, list: &str) -> i32 {
    let uid = match parse_uint_id_strict(uid_s) { Some(v) => v, None => return 2 };
    let gid = match parse_uint_id_strict(gid_s) { Some(v) => v, None => return 2 };
    if list.is_empty() { return 2; }
    let lines = match read_lines(Path::new(list)) {
        Ok(v) => v,
        Err(e) => { eprintln!("speedscan: open list failed: {}: {}", list, c_strerror(&e)); return 3; }
    };
    let mut rc = 0;
    for p in lines {
        if p.is_empty() { continue; }
        let path = Path::new(&p);
        let before = match fs::symlink_metadata(path) {
            Ok(m) => m,
            Err(e) => {
                let errno = e.raw_os_error().unwrap_or(-1);
                println!("{}\t0\tchown\t0\t0\t{}\t{}\t{}\t{}", p, uid, gid, errno, errno_text(errno));
                rc = 1;
                continue;
            }
        };
        if let Err(errno) = lchown_direct(path, uid, gid) {
            println!("{}\t0\tchown\t{}\t{}\t{}\t{}\t{}\t{}", p, before.uid(), before.gid(), uid, gid, errno, errno_text(errno));
            rc = 1;
            continue;
        }
        let after = match fs::symlink_metadata(path) {
            Ok(m) => m,
            Err(e) => {
                let errno = e.raw_os_error().unwrap_or(-1);
                println!("{}\t0\tchown\t{}\t{}\t{}\t{}\t{}\t{}", p, before.uid(), before.gid(), uid, gid, errno, errno_text(errno));
                rc = 1;
                continue;
            }
        };
        println!("{}\t1\tchown\t{}\t{}\t{}\t{}\t0\tOK", p, before.uid(), before.gid(), after.uid(), after.gid());
    }
    rc
}

fn tree_chown_walk_rs(path: &Path, uid: u32, gid: u32, changed: &mut u64, errors: &mut u64) -> i32 {
    if path.as_os_str().is_empty() { return 2; }
    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(_) => { *errors += 1; return 1; }
    };
    let mut rc = 0;
    if lchown_direct(path, uid, gid).is_err() { *errors += 1; rc = 1; } else { *changed += 1; }
    if !meta.file_type().is_dir() { return rc; }
    let rd = match fs::read_dir(path) {
        Ok(r) => r,
        Err(_) => { *errors += 1; return 1; }
    };
    for ent in rd {
        match ent {
            Ok(ent) => {
                let name = ent.file_name();
                if !path_len_c_join_ok(path, &name) { *errors += 1; rc = 1; continue; }
                if tree_chown_walk_rs(&ent.path(), uid, gid, changed, errors) != 0 { rc = 1; }
            }
            Err(_) => { /* C readdir() loop does not inspect errno after NULL. */ }
        }
    }
    rc
}

fn cmd_tree_chown(uid_s: &str, gid_s: &str, root_s: &str) -> i32 {
    let uid = match parse_uint_id_strict(uid_s) { Some(v) => v, None => return 2 };
    let gid = match parse_uint_id_strict(gid_s) { Some(v) => v, None => return 2 };
    if root_s.is_empty() { return 2; }
    let mut changed = 0u64;
    let mut errors = 0u64;
    let rc = tree_chown_walk_rs(Path::new(root_s), uid, gid, &mut changed, &mut errors);
    println!("TREE_CHOWN_SUMMARY changed={}\terrors={}\thash=0\tpolicy=facts-only", changed, errors);
    rc
}

/// Faithful port of parse_uint_id(): strtoul(s, &end, 10) with
/// complete suffix consumption. This intentionally follows C semantics,
/// including leading C whitespace, optional +/- sign, and uid_t truncation
/// after unsigned-long parsing; it must not be a stricter Rust digit-only
/// parser because that rejects argv C would accept.
fn parse_uint_id_strict(s: &str) -> Option<u32> {
    let b = s.as_bytes();
    let mut i = 0usize;
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    if i >= b.len() { return None; }
    let neg = if b[i] == b'+' { i += 1; false } else if b[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut v: u128 = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add((b[i] - b'0') as u128);
        if v > u64::MAX as u128 { return None; }
        i += 1;
    }
    if i == start || i != b.len() { return None; }
    let u = v as u64;
    let final_u = if neg { 0u64.wrapping_sub(u) } else { u };
    Some(final_u as u32)
}

/// Faithful port of parse_octal_mode(): strtol(s, &end, 8), complete
/// suffix consumption, C leading whitespace and optional sign accepted,
/// final value must be 0..=07777.
fn parse_octal_mode_strict(s: &str) -> Option<u32> {
    let b = s.as_bytes();
    let mut i = 0usize;
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    if i >= b.len() { return None; }
    let neg = if b[i] == b'+' { i += 1; false } else if b[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut v: i128 = 0;
    while i < b.len() && (b'0'..=b'7').contains(&b[i]) {
        v = v.saturating_mul(8).saturating_add((b[i] - b'0') as i128);
        if v > i64::MAX as i128 { return None; }
        i += 1;
    }
    if i == start || i != b.len() { return None; }
    if neg { v = -v; }
    if v < 0 || v > 0o7777 { return None; }
    Some(v as u32)
}

/// Faithful port of parse_optional_mode(): "-"/"none"/empty means disabled
/// (Ok(None)); anything else must be a valid strict octal mode or the
/// whole command is rejected (Err).
fn parse_optional_mode_strict(s: &str) -> Result<Option<u32>, ()> {
    if s.is_empty() || s == "-" || s == "none" { return Ok(None); }
    parse_octal_mode_strict(s).map(Some).ok_or(())
}


fn parse_c_strtoull_prefix(s: &str) -> u64 {
    let b = s.as_bytes();
    let mut i = 0usize;
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    if i >= b.len() { return 0; }
    let neg = if b[i] == b'+' { i += 1; false } else if b[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut v: u128 = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add((b[i] - b'0') as u128);
        if v > u64::MAX as u128 { return u64::MAX; }
        i += 1;
    }
    if i == start { return 0; }
    let u = v as u64;
    if neg { 0u64.wrapping_sub(u) } else { u }
}

fn parse_c_strtoll_prefix(s: &str) -> i64 {
    let b = s.as_bytes();
    let mut i = 0usize;
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    if i >= b.len() { return 0; }
    let neg = if b[i] == b'+' { i += 1; false } else if b[i] == b'-' { i += 1; true } else { false };
    let start = i;
    let mut v: u128 = 0;
    let limit = if neg { (i64::MAX as u128) + 1 } else { i64::MAX as u128 };
    while i < b.len() && b[i].is_ascii_digit() {
        v = v.saturating_mul(10).saturating_add((b[i] - b'0') as u128);
        if v > limit { return if neg { i64::MIN } else { i64::MAX }; }
        i += 1;
    }
    if i == start { return 0; }
    if neg {
        if v == (i64::MAX as u128) + 1 { i64::MIN } else { -(v as i64) }
    } else {
        v as i64
    }
}

fn parse_u64_strict_default(s: &str, fallback: u64) -> u64 {
    speedbackup_native_rs::parse_u64_default(Some(s), fallback)
}

#[derive(Default)]
struct FixupResultRs {
    visited: u64,
    chown_changed: u64,
    chown_skipped: u64,
    chmod_changed: u64,
    chmod_skipped: u64,
    type_skipped: u64,
    symlink_skipped: u64,
    symlink_owner_changed: u64,
    symlink_owner_skipped: u64,
    errors: u64,
    chown_ms: u128,
    chmod_ms: u128,
}

fn tree_fixup_walk_rs(path: &Path, uid: u32, gid: u32, do_dir_mode: bool, dir_mode: u32, do_file_mode: bool, file_mode: u32, res: &mut FixupResultRs) -> i32 {
    if path.as_os_str().is_empty() { return 2; }
    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(_) => { res.errors += 1; return 1; }
    };
    let mut rc = 0;
    res.visited += 1;
    let is_symlink = meta.file_type().is_symlink();
    if meta.uid() != uid || meta.gid() != gid {
        let op_start = Instant::now();
        if lchown_direct(path, uid, gid).is_err() {
            res.errors += 1;
            rc = 1;
        } else {
            res.chown_changed += 1;
            if is_symlink { res.symlink_owner_changed += 1; }
        }
        res.chown_ms += op_start.elapsed().as_millis();
    } else {
        res.chown_skipped += 1;
        if is_symlink { res.symlink_owner_skipped += 1; }
    }
    // r713: lchown updates the link inode itself, including dangling links.
    // Still skip chmod and traversal: never follow the link to its target.
    if is_symlink {
        res.symlink_skipped += 1;
        return rc;
    }
    let cur_mode = meta.permissions().mode() & 0o7777;
    if meta.file_type().is_dir() && do_dir_mode {
        if cur_mode != (dir_mode & 0o7777) {
            let op_start = Instant::now();
            if chmod_direct(path, dir_mode & 0o7777).is_err() { res.errors += 1; rc = 1; } else { res.chmod_changed += 1; }
            res.chmod_ms += op_start.elapsed().as_millis();
        } else { res.chmod_skipped += 1; }
    } else if meta.file_type().is_file() && do_file_mode {
        if cur_mode != (file_mode & 0o7777) {
            let op_start = Instant::now();
            if chmod_direct(path, file_mode & 0o7777).is_err() { res.errors += 1; rc = 1; } else { res.chmod_changed += 1; }
            res.chmod_ms += op_start.elapsed().as_millis();
        } else { res.chmod_skipped += 1; }
    } else {
        res.type_skipped += 1;
    }
    if !meta.file_type().is_dir() { return rc; }
    let rd = match fs::read_dir(path) {
        Ok(r) => r,
        Err(_) => { res.errors += 1; return 1; }
    };
    for ent in rd {
        match ent {
            Ok(ent) => {
                let name = ent.file_name();
                if !path_len_c_join_ok(path, &name) { res.errors += 1; rc = 1; continue; }
                if tree_fixup_walk_rs(&ent.path(), uid, gid, do_dir_mode, dir_mode, do_file_mode, file_mode, res) != 0 { rc = 1; }
            }
            Err(_) => { /* C readdir() loop does not inspect errno after NULL. */ }
        }
    }
    rc
}

fn cmd_tree_fixup(uid_s: &str, gid_s: &str, root_s: &str, dir_mode_s: &str, file_mode_s: &str) -> i32 {
    let uid = match parse_uint_id_strict(uid_s) { Some(v) => v, None => return 2 };
    let gid = match parse_uint_id_strict(gid_s) { Some(v) => v, None => return 2 };
    if root_s.is_empty() { return 2; }
    let dm = match parse_optional_mode_strict(dir_mode_s) { Ok(v) => v, Err(()) => return 2 };
    let fm = match parse_optional_mode_strict(file_mode_s) { Ok(v) => v, Err(()) => return 2 };
    let start = Instant::now();
    let mut res = FixupResultRs::default();
    let rc = tree_fixup_walk_rs(Path::new(root_s), uid, gid, dm.is_some(), dm.unwrap_or(0), fm.is_some(), fm.unwrap_or(0), &mut res);
    println!(
        "TREE_FIXUP_SUMMARY visited={}\tchownChanged={}\tchownSkipped={}\tchmodChanged={}\tchmodSkipped={}\ttypeSkipped={}\tsymlinkSkipped={}\tmetadataNoop={}\tskipped={}\terrors={}\tchownMs={}\tchmodMs={}\tdirMode={}\tfileMode={}\thash=0\tpolicy=no-symlink-follow\telapsedMs={}\tsymlinkOwnerChanged={}\tsymlinkOwnerSkipped={}\tsymlinkPolicy=lchown-link-only",
        res.visited, res.chown_changed, res.chown_skipped, res.chmod_changed, res.chmod_skipped, res.type_skipped, res.symlink_skipped,
        res.chown_skipped + res.chmod_skipped, res.symlink_skipped, res.errors, res.chown_ms, res.chmod_ms,
        if dm.is_some() { dir_mode_s } else { "-" }, if fm.is_some() { file_mode_s } else { "-" },
        start.elapsed().as_millis(), res.symlink_owner_changed, res.symlink_owner_skipped
    );
    rc
}

fn has_files_walk_rs(path: &Path) -> bool {
    if path.as_os_str().is_empty() { return false; }
    let meta = match fs::symlink_metadata(path) { Ok(m) => m, Err(_) => return false };
    if meta.is_file() { return true; }
    if !meta.is_dir() { return false; }
    let rd = match fs::read_dir(path) { Ok(r) => r, Err(_) => return false };
    for ent in rd {
        let ent = match ent { Ok(v) => v, Err(_) => continue };
        let name = ent.file_name();
        if !path_len_c_join_ok(path, &name) { continue; }
        if has_files_walk_rs(&ent.path()) { return true; }
    }
    false
}
fn cmd_has_files(root_s: &str) -> i32 {
    let hit = has_files_walk_rs(Path::new(root_s));
    println!("{}", if hit {1} else {0});
    if hit {0} else {1}
}
fn write_manifest(root_s: &str, out_s: &str) -> i32 {
    if root_s.is_empty() || out_s.is_empty() { return 2; }
    let root=Path::new(root_s); let mut out=match File::create(out_s){Ok(f)=>f,Err(e)=>{eprintln!("speedscan: open manifest output failed: {}: {}",out_s,c_strerror(&e));return 3}}; let mut res=ScanResult::default();
    let mut f = |p:&Path,m:&fs::Metadata,depth:usize,_:&mut ScanResult| { if depth>0 { let _ = writeln!(out,"{}\t{}\t{:04o}\t{}\t{}\t{}\t{}", rel_path(root,p), stat_kind(m), mode_octal(m), m.uid(), m.gid(), m.len(), m.mtime()); } Ok(()) };
    let _=walk_no_follow(root,root,0,None,&mut res,&mut f); if res.errors==0 {0}else{1}
}
/// Faithful port of cmd_facts()/facts_walk(): a distinct row schema from
/// scan-summary (FACT_ROW-prefixed, with dev/ino/nlink) - the previous
/// implementation reused cmd_scan_summary's plain 7-field manifest row
/// format for the optional output file, which is wrong for anything
/// downstream that expects the real FACT_ROW shape.
fn cmd_facts(root_s:&str, facts_out: Option<&str>) -> i32 {
    if root_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    let start = Instant::now();
    let top_meta = match fs::symlink_metadata(root) {
        Ok(m) => m,
        Err(e) => {
            println!("FACTS_SUMMARY ok=false root={} exists=0 type=missing bytes=0 files=0 dirs=0 hasFiles=0 maxMtime=0 errors=1 hash=0 reason=stat_errno_{} elapsedMs={}", root_s, e.raw_os_error().unwrap_or(-1), start.elapsed().as_millis());
            return 1;
        }
    };
    let mut maybe_out: Option<File> = None;
    if let Some(p) = facts_out.filter(|p| !p.is_empty() && *p != "-") {
        match File::create(p) {
            Ok(f) => maybe_out = Some(f),
            Err(e) => { eprintln!("speedscan: open facts output failed: {}: {}", p, c_strerror(&e)); return 3; }
        }
    }
    let mut res = ScanResult::default();
    let mut f = |p: &Path, m: &fs::Metadata, _depth: usize, _: &mut ScanResult| {
        if let Some(out) = maybe_out.as_mut() {
            let rel = rel_path(root, p);
            if !rel.is_empty() {
                let _ = writeln!(out, "FACT_ROW\t{}\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
                    rel, stat_kind(m), mode_octal(m), m.uid(), m.gid(), m.len(), m.mtime(), m.dev(), m.ino(), m.nlink());
            }
        }
        Ok(())
    };
    let _ = walk_no_follow(root, root, 0, None, &mut res, &mut f);
    let rc = if res.errors == 0 { 0 } else { 1 };
    println!(
        "FACTS_SUMMARY ok={} root={} exists=1 type={} bytes={} files={} dirs={} hasFiles={} maxMtime={} errors={} hash=0 policy=facts-only elapsedMs={}",
        rc == 0, root_s, stat_kind(&top_meta), res.bytes, res.files, res.dirs,
        if res.files > 0 { 1 } else { 0 }, res.max_mtime, res.errors, start.elapsed().as_millis()
    );
    rc
}
fn cmd_scan_summary(root_s:&str, manifest_out: Option<&str>, label:&str) -> i32 {
    if root_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    let start=Instant::now();
    let meta=match fs::symlink_metadata(root){Ok(m)=>m,Err(e)=>{println!("{}_SUMMARY ok=false root={} exists=0 type=missing bytes=0 files=0 dirs=0 hasFiles=0 maxMtime=0 errors=1 hash=0 reason=stat_errno_{} elapsedMs={}", label, root_s, e.raw_os_error().unwrap_or(-1), start.elapsed().as_millis());return 1}};
    let mut maybe_out: Option<File> = None;
    if let Some(p) = manifest_out {
        if !p.is_empty() && p != "-" {
            match File::create(p) {
                Ok(f) => maybe_out = Some(f),
                Err(e) => { eprintln!("speedscan: open scan-summary manifest failed: {}: {}", p, c_strerror(&e)); return 3; }
            }
        }
    }
    let mut res=ScanResult::default();
    let mut f = |p:&Path,m:&fs::Metadata,depth:usize,_:&mut ScanResult| { if depth>0 { if let Some(out)=maybe_out.as_mut(){ let _=writeln!(out,"{}\t{}\t{:04o}\t{}\t{}\t{}\t{}", rel_path(root,p), stat_kind(m), mode_octal(m), m.uid(), m.gid(), m.len(), m.mtime()); } } Ok(()) };
    let _=walk_no_follow(root,root,0,None,&mut res,&mut f);
    let rc=if res.errors==0{0}else{1};
    println!("{}_SUMMARY ok={} root={} exists=1 type={} bytes={} files={} dirs={} hasFiles={} maxMtime={} errors={} hash=0 policy=facts-only elapsedMs={}", label, if rc==0 {"true"}else{"false"}, root_s, stat_kind(&meta), res.bytes, res.files, res.dirs, if res.files>0 {1}else{0}, res.max_mtime, res.errors, start.elapsed().as_millis());
    rc
}
fn cmd_path_audit(root_s:&str, list:&str) -> i32 {
    let start=Instant::now();
    if root_s.is_empty() || list.is_empty() { return 2; }
    let root=match fs::canonicalize(root_s){Ok(p)=>p,Err(_)=>{println!("PATH_AUDIT_SUMMARY ok=false root={} rows=0 bad=0 escaped=0 mountCross=0 hash=0 reason=root_invalid elapsedMs={}",root_s,start.elapsed().as_millis());return 3}};
    let root_meta = match fs::symlink_metadata(&root) { Ok(m) if m.is_dir() => m, _ => { println!("PATH_AUDIT_SUMMARY ok=false root={} rows=0 bad=0 escaped=0 mountCross=0 hash=0 reason=root_invalid elapsedMs={}",root_s,start.elapsed().as_millis()); return 3; } };
    let lines = match read_lines(Path::new(list)) { Ok(v) => v, Err(e) => { eprintln!("speedscan: open path-audit list failed: {}: {}", list, c_strerror(&e)); return 4; } };
    let root_dev=root_meta.dev(); let mut rows=0; let mut bad=0; let mut escaped=0; let mut missing=0; let mut mount_cross=0;
    for p in lines { if p.is_empty(){continue;} rows+=1; let meta=fs::symlink_metadata(&p); match meta { Ok(m)=>{ let real=fs::canonicalize(&p); let (esc, real_s, err) = match real { Ok(r) => { let e = !r.starts_with(&root); (e, r.to_string_lossy().into_owned(), 0) }, Err(e) => (true, String::new(), e.raw_os_error().unwrap_or(-1)) }; let cross=m.dev()!=root_dev; if esc{escaped+=1;bad+=1;} if cross{mount_cross+=1;} println!("{}\t1\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", p, stat_kind(&m), mode_octal(&m), m.uid(), m.gid(), m.dev(), m.ino(), if esc{1}else{0}, if cross{1}else{0}, err, if real_s.is_empty(){"-".to_string()}else{real_s}); }, Err(e)=>{bad+=1;missing+=1;escaped+=1;println!("{}\t0\tmissing\t0000\t0\t0\t0\t0\t1\t0\t{}\t-",p,e.raw_os_error().unwrap_or(-1));} } }
    println!("PATH_AUDIT_SUMMARY ok={} root={} rows={} bad={} escaped={} missing={} mountCross={} hash=0 policy=facts-only elapsedMs={}", if bad==0{"true"}else{"false"}, root.to_string_lossy(), rows,bad,escaped,missing,mount_cross,start.elapsed().as_millis()); if bad==0{0}else{1}
}
extern "C" {
    fn lgetxattr(path: *const c_char, name: *const c_char, value: *mut std::os::raw::c_void, size: usize) -> isize;
    fn llistxattr(path: *const c_char, list: *mut std::os::raw::c_char, size: usize) -> isize;
}

fn read_selinux_label(path: &Path) -> Result<String, i32> {
    let c = match CString::new(path.as_os_str().as_bytes()) { Ok(v) => v, Err(_) => return Err(22) };
    let name = CString::new("security.selinux").unwrap();
    let mut buf = vec![0u8; 256];
    let n = unsafe { lgetxattr(c.as_ptr(), name.as_ptr(), buf.as_mut_ptr() as *mut std::os::raw::c_void, buf.len() - 1) };
    if n < 0 {
        return Err(std::io::Error::last_os_error().raw_os_error().unwrap_or(-1));
    }
    let n = (n as usize).min(buf.len() - 1);
    Ok(String::from_utf8_lossy(&buf[..n]).into_owned())
}

fn count_xattrs_lite(path: &Path) -> Result<i64, i32> {
    let c = match CString::new(path.as_os_str().as_bytes()) { Ok(v) => v, Err(_) => return Err(22) };
    let need = unsafe { llistxattr(c.as_ptr(), std::ptr::null_mut(), 0) };
    if need < 0 {
        return Err(std::io::Error::last_os_error().raw_os_error().unwrap_or(-1));
    }
    if need == 0 { return Ok(0); }
    let cap = (need as usize).min(65536);
    let mut buf = vec![0 as c_char; cap];
    let n = unsafe { llistxattr(c.as_ptr(), buf.as_mut_ptr(), cap) };
    if n < 0 {
        return Err(std::io::Error::last_os_error().raw_os_error().unwrap_or(-1));
    }
    let bytes: &[u8] = unsafe { std::slice::from_raw_parts(buf.as_ptr() as *const u8, n as usize) };
    let mut count = 0i64;
    let mut i = 0usize;
    while i < bytes.len() {
        let end = bytes[i..].iter().position(|&b| b == 0).map(|p| i + p).unwrap_or(bytes.len());
        if end > i { count += 1; }
        i = end + 1;
    }
    Ok(count)
}

fn label_audit_print_row(root: &Path, path: &Path, meta: Option<&fs::Metadata>, missing_label: &mut u64, xattr_errors: &mut u64) {
    let rel = path.strip_prefix(root).map(|p| p.to_string_lossy().trim_start_matches('/').to_string()).unwrap_or_default();
    match meta {
        None => {
            println!("LABEL_AUDIT_ROW\t{}\t0\tmissing\t0000\t0\t0\t0\t0\t-\t-\t0\t0", tsv_sanitize(&rel));
        }
        Some(m) => {
            let (label, label_err) = match read_selinux_label(path) {
                Ok(l) => (l, 0),
                Err(e) => { *missing_label += 1; ("-".to_string(), e) }
            };
            let (xattr_count, xattr_err) = match count_xattrs_lite(path) {
                Ok(n) => (n, 0),
                Err(e) => { *xattr_errors += 1; (-1, e) }
            };
            println!(
                "LABEL_AUDIT_ROW\t{}\t1\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
                tsv_sanitize(&rel), stat_kind(m), mode_octal(m), m.uid(), m.gid(), m.len(), m.mtime(),
                tsv_sanitize(&label), xattr_count, label_err, xattr_err
            );
        }
    }
}

fn label_audit_walk(root: &Path, path: &Path, rows: &mut u64, errors: &mut u64, missing_label: &mut u64, xattr_errors: &mut u64, truncated: &mut u64, max_rows: u64) -> i32 {
    if max_rows > 0 && *rows >= max_rows { *truncated = 1; return 0; }
    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) => {
            let rel = path.strip_prefix(root).map(|p| p.to_string_lossy().trim_start_matches('/').to_string()).unwrap_or_else(|_| path.to_string_lossy().into_owned());
            let eno = e.raw_os_error().unwrap_or(-1);
            println!("LABEL_AUDIT_ROW\t{}\t0\tmissing\t0000\t0\t0\t0\t0\t-\t-\t0\t{}", tsv_sanitize(&rel), eno);
            *errors = (*errors).wrapping_add(1);
            *rows = (*rows).wrapping_add(1);
            return 1;
        }
    };
    label_audit_print_row(root, path, Some(&meta), missing_label, xattr_errors);
    *rows += 1;
    if !meta.is_dir() { return 0; }
    let mut rc = 0;
    let rd = match fs::read_dir(path) { Ok(r) => r, Err(_) => { *errors += 1; return 1; } };
    for ent in rd {
        if max_rows > 0 && *rows >= max_rows { *truncated = 1; break; }
        match ent {
            Ok(ent) => {
                if !path_len_c_join_ok(path, ent.file_name().as_os_str()) { *errors = (*errors).wrapping_add(1); rc = 1; continue; }
                if label_audit_walk(root, &ent.path(), rows, errors, missing_label, xattr_errors, truncated, max_rows) != 0 { rc = 1; }
            }
            Err(_) => { /* C readdir() loop does not inspect errno after NULL. */ }
        }
    }
    rc
}

fn cmd_label_audit(root_s: &str, max_rows_s: Option<&str>) -> i32 {
    let start = Instant::now();
    let max_rows: u64 = match max_rows_s {
        Some(s) if !s.is_empty() => {
            let v = parse_u64_strict_default(s, 0);
            if v > 0 { v } else { 4096 }
        },
        _ => 4096,
    };
    let root = Path::new(root_s);
    if root_s.is_empty() {
        let errno = std::io::Error::last_os_error().raw_os_error().unwrap_or(0);
        println!(
            "LABEL_AUDIT_SUMMARY ok=false root={} rows=0 errors=1 missingLabel=0 xattrErrors=0 truncated=0 maxRows={} hash=0 reason=stat_errno_{} elapsedMs={}",
            tsv_sanitize(root_s), max_rows, errno, start.elapsed().as_millis()
        );
        return 1;
    }
    if let Err(e) = fs::symlink_metadata(root) {
        let errno = e.raw_os_error().unwrap_or(-1);
        println!(
            "LABEL_AUDIT_SUMMARY ok=false root={} rows=0 errors=1 missingLabel=0 xattrErrors=0 truncated=0 maxRows={} hash=0 reason=stat_errno_{} elapsedMs={}",
            tsv_sanitize(root_s), max_rows, errno, start.elapsed().as_millis()
        );
        return 1;
    }
    let mut rows: u64 = 0;
    let mut errors: u64 = 0;
    let mut missing_label: u64 = 0;
    let mut xattr_errors: u64 = 0;
    let mut truncated: u64 = 0;
    let rc = label_audit_walk(root, root, &mut rows, &mut errors, &mut missing_label, &mut xattr_errors, &mut truncated, max_rows);
    println!(
        "LABEL_AUDIT_SUMMARY ok={} root={} rows={} errors={} missingLabel={} xattrErrors={} truncated={} maxRows={} hash=0 policy=facts-only elapsedMs={}",
        if rc == 0 && errors == 0 { "true" } else { "false" },
        tsv_sanitize(root_s), rows, errors, missing_label, xattr_errors, truncated, max_rows, start.elapsed().as_millis()
    );
    if rc == 0 && errors == 0 { 0 } else { 1 }
}

fn parse_atoi_like(s: Option<&str>, fallback: i32) -> i32 {
    let raw = match s { Some(v) if !v.is_empty() => v.as_bytes(), _ => return fallback };
    let mut i = 0usize;
    while i < raw.len() && matches!(raw[i], b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c) { i += 1; }
    if i >= raw.len() { return 0; }
    let neg = if raw[i] == b'+' { i += 1; false } else if raw[i] == b'-' { i += 1; true } else { false };
    let mut v: i64 = 0;
    while i < raw.len() && raw[i].is_ascii_digit() { v = v.saturating_mul(10).saturating_add((raw[i]-b'0') as i64); i += 1; }
    if neg { -(v as i32) } else { v as i32 }
}

fn cmd_appdetails_index(root_s:&str,out_s:&str,maxdepth_s:Option<&str>,mindepth_s:Option<&str>)->i32{
    let start=Instant::now();
    if root_s.is_empty() || out_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    let mut max=parse_atoi_like(maxdepth_s,2);
    if max < 0 { max = 2; }
    if max > 64 { max = 64; }
    let mut min=parse_atoi_like(mindepth_s,0);
    if min < 0 { min = 0; }
    if min > max { min = max; }
    match fs::symlink_metadata(root) { Ok(m) if m.is_dir() => {}, Ok(_) => { let e=std::io::Error::last_os_error(); eprintln!("speedscan: appdetails-index root invalid: {}: {}", root_s, c_strerror(&e)); return 3; }, Err(e) => { eprintln!("speedscan: appdetails-index root invalid: {}: {}", root_s, c_strerror(&e)); return 3; } }
    let mut out=match File::create(out_s){Ok(f)=>f,Err(e)=>{eprintln!("speedscan: appdetails-index open output failed: {}: {}", out_s, c_strerror(&e)); return 4}};
    let mut rows=0u64;
    let mut res=ScanResult::default();
    let max_u=max as usize; let min_u=min as usize;
    let mut f=|p:&Path,m:&fs::Metadata,depth:usize,_:&mut ScanResult|{
        if depth>=min_u && depth<=max_u && m.is_file() && p.file_name().map(|n|n=="app_details.json").unwrap_or(false){
            let parent=p.parent().and_then(|x|x.file_name()).map(|x|x.to_string_lossy().into_owned()).unwrap_or_default();
            let app = if parent.is_empty() { "-".to_string() } else { parent };
            let _ = writeln!(out,"{}\t{}\t{}\t{}",app,p.to_string_lossy(),m.len(),m.mtime());
            rows+=1;
        }
        Ok(())
    };
    let _=walk_no_follow(root,root,0,Some(max_u),&mut res,&mut f);
    println!("APPDETAILS_INDEX ok={} root={} out={} rows={} errors={} maxdepth={} mindepth={} elapsedMs={} policy=facts-only", if res.errors==0{"true"}else{"partial"},root_s,out_s,rows,res.errors,max,min,start.elapsed().as_millis());
    0
}
fn cmd_file_list_abs_filter(root_s:&str,out_s:&str,skip_appdetails:&str,exclude_prefix:Option<&str>)->i32{
    let start=Instant::now();
    if root_s.is_empty() || out_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    match fs::symlink_metadata(root) { Ok(m) if m.is_dir() => {}, _ => return 3 }
    let mut out=match File::create(out_s){Ok(f)=>f,Err(_)=>return 4};
    let skip = skip_appdetails=="1";
    let prefix=exclude_prefix.filter(|s| *s!="-").unwrap_or("");
    let mut res=ScanResult::default();
    let mut rows=0u64;
    let mut f=|p:&Path,m:&fs::Metadata,_:usize,_:&mut ScanResult|{
        if m.is_dir() {
            if !prefix.is_empty() && has_prefix_path(p,prefix) { return Err(std::io::Error::new(std::io::ErrorKind::Other, "skip-subtree")); }
            return Ok(());
        }
        if m.is_file(){
            if skip {
                let bn = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
                if bn == "app_details.json" { return Ok(()); }
            }
            if !prefix.is_empty() && has_prefix_path(p,prefix){return Ok(());}
            let _ = writeln!(out,"{}",p.to_string_lossy());
            rows+=1;
        }
        Ok(())
    };
    let _=walk_no_follow(root,root,0,None,&mut res,&mut f);
    let errors = res.errors;
    println!("FILE_LIST_ABS_FILTER ok={} root={} out={} rows={} errors={} skipAppDetails={} elapsedMs={} policy=facts-only",if errors==0{"true"}else{"partial"},root_s,out_s,rows,errors,if skip{1}else{0},start.elapsed().as_millis());
    0
}
fn cmd_selected_list(applist:&str,blacklist:&str,out_s:&str,blacklist_mode:&str)->i32{
    let start=Instant::now();
    // C parity: argc guarantees non-null pointers; empty string arguments are
    // passed through to fopen(), not rejected here. Open input first, then
    // output, then load blacklist, then stream getline() rows.
    let input_f = match File::open(applist) { Ok(f) => f, Err(_) => return 3 };
    let mut out=match File::create(out_s){Ok(f)=>f,Err(_)=>return 4};
    let black=load_set(blacklist);
    let full = blacklist_mode == "1" || blacklist_mode == "true";
    let mut rows=0; let mut excluded=0;
    let mut br = BufReader::new(input_f);
    let mut line_buf = Vec::<u8>::new();
    while let Some(l) = next_c_line_lossy(&mut br, &mut line_buf){
        if let Some((name,pkg,mut nodata))=parse_app_line(&l){
            let hit=black.contains(&pkg);
            if hit && full { let _=writeln!(out,"EXCLUDED\t{}\t{}",tsv_sanitize(&name),tsv_sanitize(&pkg)); excluded+=1; continue; }
            if hit{nodata=true;}
            let safe=safe_name_for_backup(&name,&pkg);
            let _=writeln!(out,"APP\t{}\t{}\t{}",tsv_sanitize(&safe),tsv_sanitize(&pkg),if nodata{1}else{0});
            rows+=1;
        }
    }
    println!("SELECTED_LIST ok=true out={} rows={} excluded={} elapsedMs={} policy=facts-only",out_s,rows,excluded,start.elapsed().as_millis());0
}
fn cmd_apk_size_map(input:&str,out_s:&str)->i32{
    let start=Instant::now();
    // C parity: fopen(input), fopen(output), then getline() stream.
    let input_f = match File::open(input) { Ok(f) => f, Err(_) => return 3 };
    let mut out=match File::create(out_s){Ok(f)=>f,Err(_)=>return 4};
    let mut rows=0; let mut ok=0;
    let mut br = BufReader::new(input_f);
    let mut line_buf = Vec::<u8>::new();
    while let Some(l) = next_c_line_lossy(&mut br, &mut line_buf){
        if l.is_empty(){continue;}
        let mut cols=l.split('\t');
        let pkg=match cols.next(){Some(v)=>v,None=>continue};
        let path=match cols.next(){Some(v)=>v,None=>continue};
        if !path.ends_with(".apk"){continue;}
        rows+=1;
        if let Ok(m)=fs::symlink_metadata(path){ if m.is_file(){ let _=writeln!(out,"{}\t{}",pkg,m.len()); ok+=1; } }
    }
    println!("APK_SIZE_MAP ok=true in={} out={} rows={} ok={} elapsedMs={} policy=facts-only",input,out_s,rows,ok,start.elapsed().as_millis());0
}
#[derive(Clone)]
struct PrescanApkTarMember {
    name: Vec<u8>,
    size: u64,
    dev: u64,
    ino: u64,
    nlink: u64,
}

fn prescan_apk_tar_input_bytes(members: &mut Vec<PrescanApkTarMember>) -> Option<u64> {
    if members.is_empty() { return None; }
    members.sort_by(|a,b| a.name.cmp(&b.name));
    members.dedup_by(|a,b| a.name == b.name);
    let mut acc = tar_input::Accumulator::default();
    for m in members.iter() {
        acc.add(&m.name, b'f', m.size, m.dev, m.ino, m.nlink);
    }
    Some(tar_input::finish(acc.bytes))
}

// r696: single-process exact-input reducer.  The shell still decides WHICH archive
// entries are changed; Rust performs all lookup/stat/math in one pass so the hot
// path has no per-entry awk/stat/decimal helper forks.
// exact_rows: KIND<TAB>app<TAB>pkg<TAB>entry<TAB>currentSize
// dir_tar_map: pkg<TAB>entry<TAB>path<TAB>tarInputBytes
// pkg_apk_paths: pkg<TAB>absolute.apk
fn cmd_backup_prescan_exact_input(exact_rows_s:&str, dir_tar_map_s:&str, pkg_apk_paths_s:&str, details_s:&str, stats_s:&str) -> i32 {
    let start = Instant::now();
    if exact_rows_s.is_empty() || dir_tar_map_s.is_empty() || details_s.is_empty() || stats_s.is_empty() { return 2; }

    #[derive(Clone)]
    struct ExactRow { kind:String, app:String, pkg:String, entry:String }
    let mut rows = Vec::<ExactRow>::new();
    let mut need_apk = HashSet::<String>::new();
    let rf = match File::open(exact_rows_s) { Ok(v)=>v, Err(e)=>{eprintln!("speedscan: exact-input rows open failed: {}: {}", exact_rows_s, c_strerror(&e)); return 3;} };
    let mut br = BufReader::new(rf);
    let mut buf = Vec::<u8>::new();
    while let Some(line)=next_c_line_lossy(&mut br,&mut buf) {
        if line.is_empty(){continue;}
        let mut c=line.splitn(5,'\t');
        let kind=match c.next(){Some(v)=>v,None=>continue};
        let app=match c.next(){Some(v)=>v,None=>continue};
        let pkg=match c.next(){Some(v)=>v,None=>continue};
        let entry=match c.next(){Some(v)=>v,None=>continue};
        let _cur=c.next();
        if kind!="APK" && kind!="DIR" { continue; }
        if kind=="APK" { need_apk.insert(pkg.to_string()); }
        rows.push(ExactRow{kind:kind.to_string(),app:app.to_string(),pkg:pkg.to_string(),entry:entry.to_string()});
    }

    let mut dir_map = HashMap::<(String,String),u64>::new();
    if rows.iter().any(|r| r.kind=="DIR") {
        let df=match File::open(dir_tar_map_s){Ok(v)=>v,Err(e)=>{eprintln!("speedscan: exact-input dir map open failed: {}: {}",dir_tar_map_s,c_strerror(&e));return 4;}};
        let mut br=BufReader::new(df); let mut buf=Vec::<u8>::new();
        while let Some(line)=next_c_line_lossy(&mut br,&mut buf){
            if line.is_empty(){continue;}
            let mut c=line.splitn(4,'\t');
            let pkg=match c.next(){Some(v)=>v,None=>continue};
            let entry=match c.next(){Some(v)=>v,None=>continue};
            let _path=match c.next(){Some(v)=>v,None=>continue};
            let bytes=match c.next().and_then(|v|v.parse::<u64>().ok()){Some(v)=>v,None=>continue};
            dir_map.insert((pkg.to_string(),entry.to_string()),bytes);
        }
    }

    let mut apk_groups = HashMap::<String,Vec<PrescanApkTarMember>>::new();
    let mut apk_files=0usize;
    if !need_apk.is_empty() {
        let af=match File::open(pkg_apk_paths_s){Ok(v)=>v,Err(e)=>{eprintln!("speedscan: exact-input apk map open failed: {}: {}",pkg_apk_paths_s,c_strerror(&e));return 5;}};
        let mut br=BufReader::new(af); let mut buf=Vec::<u8>::new();
        while let Some(line)=next_c_line_lossy(&mut br,&mut buf){
            if line.is_empty(){continue;}
            let mut c=line.splitn(3,'\t');
            let pkg=match c.next(){Some(v)=>v,None=>continue};
            let path=match c.next(){Some(v)=>v,None=>continue};
            if !need_apk.contains(pkg) || !path.ends_with(".apk") { continue; }
            let meta=match fs::metadata(path){Ok(v)=>v,Err(_)=>continue};
            if !meta.is_file(){continue;}
            let name=match Path::new(path).file_name(){Some(v)=>v.as_bytes().to_vec(),None=>continue};
            apk_groups.entry(pkg.to_string()).or_default().push(PrescanApkTarMember{name,size:meta.len(),dev:meta.dev(),ino:meta.ino(),nlink:meta.nlink()});
            apk_files+=1;
        }
    }
    let mut apk_tar = HashMap::<String,u64>::new();
    for pkg in need_apk.iter(){
        let members=match apk_groups.get_mut(pkg){Some(v)=>v,None=>{eprintln!("speedscan: exact-input apk package has no files: {}",pkg);return 6;}};
        let bytes=match prescan_apk_tar_input_bytes(members){Some(v)=>v,None=>return 6};
        apk_tar.insert(pkg.clone(),bytes);
    }

    let details_f=match File::create(details_s){Ok(v)=>v,Err(e)=>{eprintln!("speedscan: exact-input details create failed: {}: {}",details_s,c_strerror(&e));return 10;}};
    let mut details=BufWriter::new(details_f);
    let mut total:u64=0;
    let mut cache_keys=String::from("|");
    let mut dir_rows=0usize;
    let mut apk_rows=0usize;
    for r in rows.iter(){
        let bytes=if r.kind=="APK" {
            apk_rows+=1;
            match apk_tar.get(&r.pkg){Some(v)=>*v,None=>{eprintln!("speedscan: exact-input missing apk bytes: {}",r.pkg);return 7;}}
        } else {
            dir_rows+=1;
            match dir_map.get(&(r.pkg.clone(),r.entry.clone())){Some(v)=>*v,None=>{eprintln!("speedscan: exact-input missing dir bytes: {} {}",r.pkg,r.entry);return 8;}}
        };
        total=match total.checked_add(bytes){Some(v)=>v,None=>{eprintln!("speedscan: exact-input total overflow");return 9;}};
        // Preserve r694 cache semantics for every exact entry (APK and DIR):
        // once exact-input accounting has already covered it, the optional pre-pack
        // debug tree-plan must not re-scan the same entry.
        cache_keys.push_str(&r.pkg);
        cache_keys.push(':');
        cache_keys.push_str(&r.entry);
        cache_keys.push('|');
        if writeln!(details,"{}\t{}\t{}\t{}\t{}",r.kind,tsv_sanitize(&r.app),tsv_sanitize(&r.pkg),tsv_sanitize(&r.entry),bytes).is_err(){return 10;}
    }
    if details.flush().is_err(){return 10;}
    let elapsed=start.elapsed().as_millis();
    let stats_f=match File::create(stats_s){Ok(v)=>v,Err(e)=>{eprintln!("speedscan: exact-input stats create failed: {}: {}",stats_s,c_strerror(&e));return 10;}};
    let mut stats=BufWriter::new(stats_f);
    let _=writeln!(stats,"bytes\t{}",total);
    let _=writeln!(stats,"archives\t{}",rows.len());
    let _=writeln!(stats,"apkRows\t{}",apk_rows);
    let _=writeln!(stats,"apkPackages\t{}",need_apk.len());
    let _=writeln!(stats,"apkFiles\t{}",apk_files);
    let _=writeln!(stats,"dirRows\t{}",dir_rows);
    let _=writeln!(stats,"cacheKeys\t{}",cache_keys);
    let _=writeln!(stats,"elapsedMs\t{}",elapsed);
    if stats.flush().is_err(){return 10;}
    println!("BACKUP_PRESCAN_EXACT_INPUT_BATCH ok=true bytes={} archives={} apkRows={} apkPackages={} apkFiles={} dirRows={} elapsedMs={} mode=r696 schema=speedscan.backup_prescan_exact_input_batch.v1",total,rows.len(),apk_rows,need_apk.len(),apk_files,dir_rows,elapsed);
    0
}

#[cfg(test)]
mod exact_input_batch_tests {
    use super::*;
    #[test]
    fn apk_tar_math_matches_gnu_record_rounding() {
        let mut members=vec![
            PrescanApkTarMember{name:b"base.apk".to_vec(),size:513,dev:1,ino:1,nlink:1},
            PrescanApkTarMember{name:b"split_config.arm64_v8a.apk".to_vec(),size:1,dev:1,ino:2,nlink:1},
        ];
        assert_eq!(prescan_apk_tar_input_bytes(&mut members),Some(10240));
    }
    #[test]
    fn apk_hardlink_is_counted_once_like_gnu_tar() {
        let mut members=vec![
            PrescanApkTarMember{name:b"base.apk".to_vec(),size:513,dev:7,ino:9,nlink:2},
            PrescanApkTarMember{name:b"split.apk".to_vec(),size:513,dev:7,ino:9,nlink:2},
        ];
        assert_eq!(prescan_apk_tar_input_bytes(&mut members),Some(10240));
    }
}

#[derive(Default)]
struct AppSumEntry { name: String, nodata: bool, apk: u64, appdata: u64, external: u64, cache: u64 }

// Faithful port of read_selected_for_summary()/add_dirsize_to_summary()/
// add_apk_to_summary()/cmd_backup_prescan_summary(). Fixes three real
// divergences from the previous implementation:
//   1. mediaMapped/cacheMapped were hardcoded to 1 instead of counting how
//      many "__speedbackup_custom_media__" rows actually matched the
//      required "media_" prefix (partialMedia was hardcoded to 0 to match).
//   2. Per-app dirsize type matching used a loose "contains(\"cache\")"
//      check and defaulted every unrecognized type string to "external";
//      C only recognizes user/user_de (appdata), data/obb/media (external,
//      exact match), and *_exclude_cache/*_exclude_code_cache (cache) -
//      anything else is silently ignored, not added anywhere.
//   3. The "bin.mt.plus" package (and any nodata app) has appdata/external/
//      cache force-zeroed before totals are computed - the previous
//      implementation only handled the nodata case.
fn cmd_backup_prescan_summary(selected:&str,dirsizes:&str,apkmap:&str,rskip:&str,lskip:&str,out_s:&str,remote_stream:&str,remote_type:&str)->i32{
    let start=Instant::now();
    let mut app_count=0u64;
    let mut excluded=0u64;
    let mut per: HashMap<String, AppSumEntry> = HashMap::new();
    // read_selected_for_summary(): split only the first three TABs.  The nd
    // field retains any remaining TAB bytes, so "1\textra" is not nodata.
    for l in read_lines(Path::new(selected)).unwrap_or_default() {
        let mut it=l.splitn(4,'\t');
        let kind=match it.next(){Some(v)=>v,None=>continue};
        let name=match it.next(){Some(v)=>v,None=>continue};
        let pkg=match it.next(){Some(v)=>v,None=>continue};
        if kind=="EXCLUDED" { excluded=excluded.wrapping_add(1); continue; }
        let nd=match it.next(){Some(v)=>v,None=>continue};
        if kind=="APP" {
            let e=per.entry(pkg.to_string()).or_insert_with(AppSumEntry::default);
            if e.name.is_empty(){e.name=name.to_string();}
            e.nodata=nd=="1";
            app_count=app_count.wrapping_add(1);
        }
    }
    let mut media_total=0u64;
    let mut media_cache=0u64;
    let mut media_mapped=0u64;
    let mut cache_mapped=0u64;
    // add_dirsize_to_summary(): first two TABs only; size retains the suffix.
    if dirsizes!="-" {
        for l in read_lines(Path::new(dirsizes)).unwrap_or_default() {
            let mut it=l.splitn(3,'\t');
            let pkg=match it.next(){Some(v)=>v,None=>continue};
            let typ=match it.next(){Some(v)=>v,None=>continue};
            let szs=match it.next(){Some(v)=>v,None=>continue};
            let sz=parse_u64_strict_default(szs,0);
            if pkg=="__speedbackup_custom_media__" {
                if typ.starts_with("media_") {
                    if typ.contains("_exclude_cache") {
                        media_cache=media_cache.wrapping_add(sz);
                        cache_mapped=cache_mapped.wrapping_add(1);
                    } else {
                        media_total=media_total.wrapping_add(sz);
                        media_mapped=media_mapped.wrapping_add(1);
                    }
                }
                continue;
            }
            let e=match per.get_mut(pkg){Some(v)=>v,None=>continue};
            if typ=="user"||typ=="user_de"{e.appdata=e.appdata.wrapping_add(sz);}
            else if typ=="data"||typ=="obb"||typ=="media"{e.external=e.external.wrapping_add(sz);}
            else if typ.contains("_exclude_cache")||typ.contains("_exclude_code_cache"){e.cache=e.cache.wrapping_add(sz);}
        }
    }
    // add_apk_to_summary(): first TAB only; the entire suffix is parsed.
    if apkmap!="-" {
        for l in read_lines(Path::new(apkmap)).unwrap_or_default() {
            let mut it=l.splitn(2,'\t');
            let pkg=match it.next(){Some(v)=>v,None=>continue};
            let szs=match it.next(){Some(v)=>v,None=>continue};
            if let Some(v)=per.get_mut(pkg){v.apk=v.apk.wrapping_add(parse_u64_strict_default(szs,0));}
        }
    }
    let rs=if rskip!="-"{load_set(rskip)}else{HashSet::new()};
    let ls=if lskip!="-"{load_set(lskip)}else{HashSet::new()};
    let remote_on=!remote_type.is_empty()&&remote_type!="-";
    let rstream=remote_stream=="1";
    let (mut apk,mut appdata,mut ext,mut cache_total,mut remote_skip,mut local_skip)=(0u64,0u64,0u64,0u64,0u64,0u64);
    let mut total=0u64;
    for (pkg,e) in per.iter_mut(){
        if e.nodata||pkg=="bin.mt.plus"{e.appdata=0;e.external=0;e.cache=0;}
        let raw=e.apk.wrapping_add(e.appdata).wrapping_add(e.external);
        let eff=if raw>e.cache{raw.wrapping_sub(e.cache)}else{0};
        apk=apk.wrapping_add(e.apk);
        appdata=appdata.wrapping_add(e.appdata);
        ext=ext.wrapping_add(e.external);
        cache_total=cache_total.wrapping_add(e.cache);
        total=total.wrapping_add(eff);
        if rstream&&remote_on&&rs.contains(&e.name){remote_skip=remote_skip.wrapping_add(eff);}
        else if !remote_on&&!rstream&&ls.contains(&e.name){local_skip=local_skip.wrapping_add(eff);}
    }
    total=total.wrapping_add(media_total);
    cache_total=cache_total.wrapping_add(media_cache);
    total=if total>media_cache{total.wrapping_sub(media_cache)}else{0};
    let skip_sum=remote_skip.wrapping_add(local_skip);
    let expected=if skip_sum<total{total.wrapping_sub(skip_sum)}else{0};
    let partial_media:i32=if media_mapped>0{0}else{1};
    let body=format!(
        "apps\t{}\nexcludedApps\t{}\napk\t{}\nappData\t{}\nexternal\t{}\nmediaCustom\t{}\nexcludedCache\t{}\ntotal\t{}\nremoteSkip\t{}\nlocalSkip\t{}\nexpected\t{}\npartialMedia\t{}\nmediaMapped\t{}\ncacheMapped\t{}\n",
        app_count,excluded,apk,appdata,ext,media_total,cache_total,total,remote_skip,local_skip,expected,partial_media,media_mapped,cache_mapped
    );
    let mut out=match File::create(out_s){Ok(f)=>f,Err(_)=>return 4};
    let _ = out.write_all(body.as_bytes());
    println!("BACKUP_PRESCAN_SUMMARY_NATIVE ok=true out={} apps={} total={} expected={} elapsedMs={} policy=facts-only",out_s,app_count,total,expected,start.elapsed().as_millis());
    0
}
fn cmd_backup_root_index(root_s:&str,out_s:&str,maxdepth_s:Option<&str>)->i32{
    let start=Instant::now();
    if root_s.is_empty() || out_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    let mut max_i=parse_atoi_like(maxdepth_s,3); if max_i<1{max_i=1;} if max_i>16{max_i=16;} let max=max_i as usize;
    if validate_root_dir_for_speedscan(root_s).is_err() { return 3; }
    let mut out=match File::create(out_s){Ok(f)=>f,Err(_)=>return 4};
    let mut res=ScanResult::default();
    let mut rows=0u64;
    let mut f=|p:&Path,m:&fs::Metadata,depth:usize,_:&mut ScanResult|{
        if depth>0{
            let name=p.file_name().map(|n|n.to_string_lossy().into_owned()).unwrap_or_default();
            let kind = if m.is_dir() && name.starts_with("Backup_") { "backup_dir" }
                else if m.is_dir() { "dir" }
                else if m.is_file() && name=="app_details.json" { "app_details_json" }
                else if m.is_file() && (name.contains(".tar")||name.contains(".zst")) { "tar_payload" }
                else if m.is_file() && matches!(name.as_str(), "start.sh"|"recover.sh"|"backup.sh"|"upload.sh") { "sidecar_script" }
                else { "other" };
            let _ = writeln!(out,"{}\t{}\t{}\t{}\t{}\t{}",kind,p.to_string_lossy(),name,depth,m.mtime(),if m.is_file(){m.len()}else{0});
            rows+=1;
        }
        Ok(())
    };
    let _=walk_no_follow(root,root,0,Some(max),&mut res,&mut f);
    println!("BACKUP_ROOT_INDEX ok={} root={} out={} rows={} errors={} maxdepth={} elapsedMs={} policy=facts-only",if res.errors==0{"true"}else{"partial"},root_s,out_s,rows,res.errors,max,start.elapsed().as_millis());
    0
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct StatVfs {
    f_bsize: c_ulong,
    f_frsize: c_ulong,
    f_blocks: c_ulong,
    f_bfree: c_ulong,
    f_bavail: c_ulong,
    f_files: c_ulong,
    f_ffree: c_ulong,
    f_favail: c_ulong,
    f_fsid: c_ulong,
    f_flag: c_ulong,
    f_namemax: c_ulong,
    #[cfg(target_pointer_width = "64")]
    __f_reserved: [u32; 6],
}

extern "C" { fn statvfs(path: *const c_char, buf: *mut StatVfs) -> c_int; }

fn sanitize_tsv_spaces_rs(s: &str) -> String {
    // speedscan.c sanitize_tsv(): unlike print_tsv_sanitized(), this replaces
    // TAB/CR/LF with a literal space.
    s.chars().map(|c| if c == '\t' || c == '\n' || c == '\r' { ' ' } else { c }).collect()
}

fn c_string_cap_lossy(bytes: &[u8], payload_cap: usize) -> String {
    let mut end = bytes.len().min(payload_cap);
    if let Some(nul) = bytes[..end].iter().position(|&b| b == 0) { end = nul; }
    String::from_utf8_lossy(&bytes[..end]).into_owned()
}

fn mountinfo_unescape_bytes(input: &[u8], payload_cap: usize) -> Vec<u8> {
    let mut out = Vec::<u8>::with_capacity(input.len().min(payload_cap));
    let mut i = 0usize;
    while i < input.len() && out.len() < payload_cap {
        if input[i] == b'\\' && i + 3 < input.len()
            && (b'0'..=b'7').contains(&input[i+1])
            && (b'0'..=b'7').contains(&input[i+2])
            && (b'0'..=b'7').contains(&input[i+3]) {
            let v = (input[i+1] - b'0') * 64 + (input[i+2] - b'0') * 8 + (input[i+3] - b'0');
            out.push(v);
            i += 4;
        } else {
            out.push(input[i]);
            i += 1;
        }
    }
    out
}


fn path_prefix_match_rs(path: &str, mp: &str) -> bool {
    if path.is_empty() || mp.is_empty() { return false; }
    if mp == "/" { return true; }
    if !path.starts_with(mp) { return false; }
    path.len() == mp.len() || path.as_bytes().get(mp.len()) == Some(&b'/')
}

fn human_bytes_rs(bytes: u64) -> String {
    const UNITS: [&str; 7] = ["B", "K", "M", "G", "T", "P", "E"];
    if bytes < 1024 { return format!("{}B", bytes); }
    let mut v = bytes as f64;
    let mut u = 0usize;
    while v >= 1024.0 && u < UNITS.len() - 1 { v /= 1024.0; u += 1; }
    format!("{:.1}{}", v, UNITS[u])
}

fn mountinfo_fgets_chunks(body: &[u8]) -> Vec<&[u8]> {
    // C fgets(line[8192]): at most 8191 bytes per call, and a long physical
    // line is deliberately exposed as multiple iterations.
    let mut out = Vec::new();
    let mut pos = 0usize;
    while pos < body.len() {
        let lim = (pos + 8191).min(body.len());
        let end = match body[pos..lim].iter().position(|&b| b == b'\n') {
            Some(k) => pos + k + 1,
            None => lim,
        };
        if end == pos { break; }
        out.push(&body[pos..end]);
        pos = end;
    }
    out
}

fn mountinfo_lookup_rs(target: &str) -> (String, String, String) {
    let target_real = fs::canonicalize(target).ok()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|| target.to_string());
    let mut best_len = 0usize;
    let mut best_fs = String::from("unknown");
    let mut best_mp = String::new();
    let mut best_src = String::new();
    let body = match fs::read("/proc/self/mountinfo") { Ok(v) => v, Err(_) => return (best_fs, best_mp, best_src) };
    for line in mountinfo_fgets_chunks(&body) {
        // strtok_r(copy, " \n", ...), max 256 fields. Tabs and CR are NOT delimiters.
        let mut fields: Vec<&[u8]> = Vec::with_capacity(32);
        let mut i = 0usize;
        while i < line.len() && fields.len() < 256 {
            while i < line.len() && (line[i] == b' ' || line[i] == b'\n') { i += 1; }
            if i >= line.len() { break; }
            let st = i;
            while i < line.len() && line[i] != b' ' && line[i] != b'\n' { i += 1; }
            fields.push(&line[st..i]);
        }
        if fields.len() < 10 || fields.len() <= 4 { continue; }
        let sep = match fields.iter().position(|v| *v == b"-") { Some(v) => v, None => continue };
        if sep + 2 >= fields.len() { continue; }
        let dec_mp_b = mountinfo_unescape_bytes(fields[4], PATH_MAX_SAFE - 1);
        let dec_mp = c_string_cap_lossy(&dec_mp_b, PATH_MAX_SAFE - 1);
        if !path_prefix_match_rs(&target_real, &dec_mp) && !path_prefix_match_rs(target, &dec_mp) { continue; }
        let ml = dec_mp.as_bytes().len();
        if ml < best_len { continue; }
        best_len = ml;
        let fs_s = c_string_cap_lossy(fields[sep + 1], 127);
        let dec_src_b = mountinfo_unescape_bytes(fields[sep + 2], PATH_MAX_SAFE - 1);
        let src_s = c_string_cap_lossy(&dec_src_b, PATH_MAX_SAFE - 1);
        best_fs = sanitize_tsv_spaces_rs(&fs_s);
        best_mp = sanitize_tsv_spaces_rs(&dec_mp);
        best_src = sanitize_tsv_spaces_rs(&src_s);
    }
    (best_fs, best_mp, best_src)
}
fn cmd_storage_summary(path_s: &str) -> i32 {
    if path_s.is_empty() { return 2; }
    let c_path = match CString::new(Path::new(path_s).as_os_str().as_bytes()) {
        Ok(v) => v,
        Err(_) => { eprintln!("storage-summary: statvfs failed path={} errno={}", path_s, 22); return 1; }
    };
    let mut vfs = StatVfs::default();
    let rc = unsafe { statvfs(c_path.as_ptr(), &mut vfs as *mut StatVfs) };
    if rc != 0 {
        let errno = std::io::Error::last_os_error().raw_os_error().unwrap_or(-1);
        eprintln!("storage-summary: statvfs failed path={} errno={}", path_s, errno);
        return 1;
    }
    let bsize = if vfs.f_frsize != 0 { vfs.f_frsize as u64 } else { vfs.f_bsize as u64 };
    let total = (vfs.f_blocks as u64).wrapping_mul(bsize);
    let freeb = (vfs.f_bfree as u64).wrapping_mul(bsize);
    let avail = (vfs.f_bavail as u64).wrapping_mul(bsize);
    let used = total.saturating_sub(freeb);
    let denom = used.wrapping_add(avail);
    let use_pct = if denom > 0 { used.wrapping_mul(100).wrapping_add(denom - 1) / denom } else { 0 };
    let target_raw = c_string_cap_lossy(path_s.as_bytes(), PATH_MAX_SAFE - 1);
    let target = sanitize_tsv_spaces_rs(&target_raw);
    let real_raw = fs::canonicalize(path_s).ok()
        .map(|p| c_string_cap_lossy(p.as_os_str().as_bytes(), PATH_MAX_SAFE - 1))
        .unwrap_or_else(|| target_raw.clone());
    let real = sanitize_tsv_spaces_rs(&real_raw);
    let (fs_type, mount_point, source) = mountinfo_lookup_rs(path_s);
    println!("#schema\tspeedbackup.storage_summary.v1");
    println!("#fields\tstatus\ttarget\trealpath\ttotalBytes\tusedBytes\tavailBytes\tusePct\tfsType\tmountPoint\tsource\ttotalHuman\tusedHuman\tavailHuman");
    println!("OK\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        target, real, total, used, avail, use_pct, fs_type, mount_point, source,
        human_bytes_rs(total), human_bytes_rs(used), human_bytes_rs(avail));
    0
}
fn checksum_list_walk_rs(out: &mut File, root_s: &str, path: &Path, root_len: usize, rows: &mut u64, errors: &mut u64) -> i32 {
    let m = match fs::symlink_metadata(path) {
        Ok(v) => v,
        Err(_) => { *errors = (*errors).wrapping_add(1); return 1; }
    };
    if m.is_file() {
        let raw = path.as_os_str().as_bytes();
        let mut rel = if root_len <= raw.len() { &raw[root_len..] } else { &[][..] };
        if rel.first() == Some(&b'/') { rel = &rel[1..]; }
        let rel_s = String::from_utf8_lossy(rel);
        let (h, ok) = match fnv1a64_file(path) { Ok(v) => (v, true), Err(_) => (0, false) };
        let _ = writeln!(out, "{}\t{}\t{}\t{:016x}\t{}", rel_s, m.len(), m.mtime(), h, if ok { "OK" } else { "READ_ERROR" });
        *rows = (*rows).wrapping_add(1);
        if !ok { *errors = (*errors).wrapping_add(1); return 1; }
        return 0;
    }
    if !m.is_dir() { return 0; }
    let rd = match fs::read_dir(path) {
        Ok(v) => v,
        Err(_) => { *errors = (*errors).wrapping_add(1); return 1; }
    };
    let mut rc = 0;
    for ent in rd {
        let ent = match ent { Ok(v) => v, Err(_) => continue };
        if !path_len_c_join_ok(path, ent.file_name().as_os_str()) {
            *errors = (*errors).wrapping_add(1);
            rc = 1;
            continue;
        }
        if checksum_list_walk_rs(out, root_s, &ent.path(), root_len, rows, errors) != 0 { rc = 1; }
    }
    let _ = root_s;
    rc
}

fn cmd_checksum_list(root_s:&str,out_s:&str)->i32{
    if root_s.is_empty() || out_s.is_empty() { return 2; }
    let mut out=match File::create(out_s){
        Ok(f)=>f,
        Err(e)=>{ eprintln!("speedscan: checksum-list open failed: {}: {}", out_s, c_strerror(&e)); return 3; }
    };
    let _=writeln!(out,"#schema\tspeedbackup.checksum_list.v1\n#fields\trel\tbytes\tmtime\tfnv64\tstatus");
    let mut root_len = root_s.as_bytes().len();
    let rb = root_s.as_bytes();
    while root_len > 1 && rb[root_len - 1] == b'/' { root_len -= 1; }
    let mut rows=0u64;
    let mut errors=0u64;
    let rc=checksum_list_walk_rs(&mut out, root_s, Path::new(root_s), root_len, &mut rows, &mut errors);
    let _=writeln!(out,"#summary\trows={}\terrors={}\trc={}",rows,errors,rc);
    rc
}
fn cmd_manifest_verify(root_s:&str,manifest:&str,prefix_restore:bool)->i32{
    let restore_start = Instant::now();
    if prefix_restore { println!("#schema\tspeedbackup.restore_tree_verify.v1"); }
    let finish_restore = |rc:i32| { if prefix_restore { println!("#restore_tree_verify\trc={}\telapsedMs={}\tpolicy=facts-only", rc, restore_start.elapsed().as_millis()); } rc };
    if root_s.is_empty() || manifest.is_empty() { return finish_restore(2); }
    let lines = match read_lines(Path::new(manifest)) {
        Ok(v) => v,
        Err(e) => { eprintln!("speedscan: manifest-verify open failed: {}: {}", manifest, c_strerror(&e)); return finish_restore(3); }
    };
    println!("#schema\tspeedbackup.manifest_verify.v1");
    println!("#fields\tstatus\trel\texpectedSize\tactualSize\texpectedMtime\tactualMtime\treason");
    let mut rows=0u64;let mut ok=0u64;let mut missing=0u64;let mut changed=0u64;let mut bad=0u64;
    for l in lines{
        let line=trim_line(l);
        if line.is_empty()||line.starts_with('#'){continue;}
        let c:Vec<&str>=line.split('\t').collect();
        if c.len()<7{bad+=1;continue;}
        if !path_len_c_join_root_rel_ok(root_s, c[0]) { bad+=1; continue; }
        rows+=1;
        let p=c_join_root_rel(root_s, c[0]);
        let exp_size=parse_c_strtoull_prefix(c[5]);
        let exp_mtime=parse_c_strtoll_prefix(c[6]);
        match fs::symlink_metadata(&p){
            Ok(m)=>{
                if m.len()!=exp_size||m.mtime()!=exp_mtime{
                    changed+=1;
                    println!("CHANGED\t{}\t{}\t{}\t{}\t{}\tsize_or_mtime",c[0],exp_size,m.len(),exp_mtime,m.mtime());
                }else{
                    ok+=1;
                    println!("OK\t{}\t{}\t{}\t{}\t{}\tOK",c[0],exp_size,m.len(),exp_mtime,m.mtime());
                }
            },
            Err(e)=>{
                missing+=1;
                println!("MISSING\t{}\t{}\t0\t{}\t0\tstat_errno_{}",c[0],exp_size,exp_mtime,e.raw_os_error().unwrap_or(-1));
            }
        }
    }
    let rc=if missing+changed+bad==0{0}else{1};
    println!("#summary\trows={}\tok={}\tmissing={}\tchanged={}\tbad={}\trc={}",rows,ok,missing,changed,bad,rc);
    finish_restore(rc)
}
fn cmd_run_tmpdir_facts(base:&str,out_s:&str,prefix:Option<&str>)->i32{
    if base.is_empty() || out_s.is_empty() { return 2; }
    let pref=match prefix { Some(p) if !p.is_empty()=>p, _=>".speedbackup_run_" };
    let rd=match fs::read_dir(base){Ok(v)=>v,Err(e)=>{eprintln!("speedscan: run-tmpdir-facts open base failed: {}: {}",base,c_strerror(&e));return 3;}};
    let mut out=match File::create(out_s){Ok(f)=>f,Err(e)=>{eprintln!("speedscan: run-tmpdir-facts open out failed: {}: {}",out_s,c_strerror(&e));return 4;}};
    let _=writeln!(out,"#schema\tspeedbackup.run_tmpdir_facts.v1\n#fields\tname\tpath\ttype\tmode\tuid\tgid\tbytes\tmtime\tageSec");
    let now=(wall_ms()/1000)as i64;let mut rows=0;let mut errors=0;
    for e in rd.flatten(){
        let name=e.file_name().to_string_lossy().into_owned();
        if !name.starts_with(pref){continue;}
        if !path_len_c_join_ok(Path::new(base), e.file_name().as_os_str()) { errors+=1; continue; }
        let path=e.path();
        match fs::symlink_metadata(&path){Ok(m)=>{let age=now-m.mtime();let _=writeln!(out,"{}\t{}\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}",name,path.to_string_lossy(),stat_kind(&m),mode_octal(&m),m.uid(),m.gid(),m.len(),m.mtime(),age);rows+=1},Err(_)=>errors+=1}
    }
    let _=writeln!(out,"#summary\trows={}\terrors={}",rows,errors);if errors==0{0}else{1}
}
fn cmd_zst_file_facts(path_s:&str)->i32{if path_s.is_empty(){return 2;}println!("#schema\tspeedbackup.zst_file_facts.v1");println!("#fields\tpath\texists\tregular\tbytes\tmtime\tzstdMagic");let mut magic=0;match fs::metadata(path_s){Ok(m)=>{if let Ok(mut f)=File::open(path_s){let mut h=[0u8;4];if f.read_exact(&mut h).is_ok()&&h==[0x28,0xb5,0x2f,0xfd]{magic=1;}}println!("{}\t1\t{}\t{}\t{}\t{}",path_s,if m.is_file(){1}else{0},m.len(),m.mtime(),magic);if m.is_file()&&magic==1{0}else{1}},Err(_)=>{println!("{}\t0\t0\t0\t0\t0",path_s);1}}}
/// Faithful port of skip_rel_prefix(): strips leading '/' characters, then
/// a single leading "./" if present.
fn skip_rel_prefix(s: &str) -> &str {
    let s = s.trim_start_matches('/');
    s.strip_prefix("./").unwrap_or(s)
}

/// Faithful port of exclude_match_one(): a pattern matches `rel` either
/// exactly, or as a directory prefix (rel starts with pattern + '/'). A
/// trailing "/*" on the pattern is accepted but doesn't change the
/// semantics - the C reference treats "dir" and "dir/*" identically. The
/// previous implementation used a plain HashSet exact-match, which silently
/// failed to exclude anything under an excluded directory.
fn exclude_match_one(rel: &str, pattern: &str) -> bool {
    if rel.is_empty() { return false; }
    let p = skip_rel_prefix(pattern).trim_start_matches(' ');
    if p.is_empty() { return false; }
    let mut p = p.trim_end_matches('/');
    if let Some(stripped) = p.strip_suffix("/*") { p = stripped; }
    if p.is_empty() { return false; }
    if rel == p { return true; }
    rel.starts_with(p) && rel.as_bytes().get(p.len()) == Some(&b'/')
}

fn pack_plan_excluded<'a, I: IntoIterator<Item = &'a String>>(excludes: I, rel: &str) -> bool {
    if rel.is_empty() { return false; }
    excludes.into_iter().any(|pat| exclude_match_one(rel, pat))
}
#[derive(Default)]
struct PackPlanResult { rows:u64, packable:u64, excluded:u64, files:u64, dirs:u64, links:u64, specials:u64, bytes:u64, blocks512:u64, errors:u64, truncated:u64, max_mtime:u64 }

fn pack_plan_note_type_rs(res: &mut PackPlanResult, m: &fs::Metadata) {
    let mt = m.mtime() as u64;
    if mt > res.max_mtime { res.max_mtime = mt; }
    if m.blocks() > 0 { res.blocks512 = res.blocks512.wrapping_add(m.blocks()); }
    if m.is_file() { res.files = res.files.wrapping_add(1); res.bytes = res.bytes.wrapping_add(m.len()); }
    else if m.file_type().is_dir() { res.dirs = res.dirs.wrapping_add(1); }
    else if m.file_type().is_symlink() { res.links = res.links.wrapping_add(1); }
    else { res.specials = res.specials.wrapping_add(1); }
}

fn pack_plan_emit_row_rs(out: &mut File, rel: &str, m: Option<&fs::Metadata>, packable: bool, reason: &str, res: &mut PackPlanResult, max_rows: u64) -> bool {
    if max_rows > 0 && res.rows >= max_rows { res.truncated = 1; return false; }
    let (kind,mode,uid,gid,bytes,blocks,mtime,dev,ino,nlink) = match m {
        Some(v) => (stat_kind(v), mode_octal(v), v.uid(), v.gid(), v.len(), v.blocks(), v.mtime(), v.dev(), v.ino(), v.nlink()),
        None => ("missing",0,0,0,0,0,0,0,0,0),
    };
    let _ = writeln!(out,"PACK_PLAN_ROW\t{}\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        tsv_sanitize(rel),kind,mode,uid,gid,bytes,blocks,mtime,dev,ino,nlink,if packable{1}else{0},tsv_sanitize(reason));
    res.rows = res.rows.wrapping_add(1);
    if packable { res.packable = res.packable.wrapping_add(1); } else { res.excluded = res.excluded.wrapping_add(1); }
    true
}

fn pack_plan_walk_rs(out:&mut File, root:&Path, path:&Path, excludes:&HashSet<String>, res:&mut PackPlanResult, max_rows:u64)->i32 {
    let m = match fs::symlink_metadata(path) {
        Ok(v)=>v,
        Err(_)=>{
            res.errors = res.errors.wrapping_add(1);
            let rel=rel_path(root,path);
            if !rel.is_empty() { let _=pack_plan_emit_row_rs(out,&rel,None,false,"stat-error",res,max_rows); }
            return 1;
        }
    };
    let rel=rel_path(root,path);
    let excluded=pack_plan_excluded(excludes.iter(),&rel);
    if !rel.is_empty() {
        pack_plan_note_type_rs(res,&m);
        if excluded {
            let _=pack_plan_emit_row_rs(out,&rel,Some(&m),false,"exclude",res,max_rows);
            return 0;
        }
        if !pack_plan_emit_row_rs(out,&rel,Some(&m),true,"OK",res,max_rows) { return 0; }
    }
    if !m.file_type().is_dir() { return 0; }
    let rd=match fs::read_dir(path) { Ok(v)=>v, Err(_)=>{res.errors=res.errors.wrapping_add(1); return 1;} };
    let mut rc=0;
    for ent in rd {
        let ent=match ent { Ok(v)=>v, Err(_)=>continue };
        if !path_len_c_join_ok(path,ent.file_name().as_os_str()) { res.errors=res.errors.wrapping_add(1); rc=1; continue; }
        if pack_plan_walk_rs(out,root,&ent.path(),excludes,res,max_rows)!=0 { rc=1; }
        if res.truncated!=0 { break; }
    }
    rc
}

fn cmd_tree_pack_plan(root_s:&str,out_s:&str,exclude:&str,max_rows_s:Option<&str>)->i32{
    let start=Instant::now();
    if root_s.is_empty() || out_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    if let Err(e) = validate_root_dir_for_speedscan(root_s) {
        eprintln!("speedscan: tree-pack-plan root invalid: {}: {}", root_s, c_strerror(&e));
        return 3;
    }
    let mut out=match File::create(out_s){
        Ok(f)=>f,
        Err(e)=>{ eprintln!("speedscan: tree-pack-plan open output failed: {}: {}", out_s, c_strerror(&e)); return 4; }
    };
    let max_rows=parse_u64_default(max_rows_s,0);
    let ex=load_set(exclude);
    let _=writeln!(out,"#schema\tspeedbackup.tree_pack_plan.v1");
    let _=writeln!(out,"#fields\trel\ttype\tmode\tuid\tgid\tbytes\tblocks512\tmtime\tdev\tino\tnlink\tpackable\treason");
    let mut res = PackPlanResult::default();
    let walk_rc=pack_plan_walk_rs(&mut out,root,root,&ex,&mut res,max_rows);
    let _=writeln!(out,"#summary\trows={}\tpackable={}\texcluded={}\tfiles={}\tdirs={}\tlinks={}\tspecials={}\tbytes={}\tblocks512={}\tmaxMtime={}\terrors={}\ttruncated={}\trc={}",res.rows,res.packable,res.excluded,res.files,res.dirs,res.links,res.specials,res.bytes,res.blocks512,res.max_mtime,res.errors,res.truncated,walk_rc);
    println!("TREE_PACK_PLAN ok={} root={} out={} rows={} packable={} excluded={} files={} dirs={} links={} specials={} bytes={} blocks512={} maxMtime={} errors={} truncated={} elapsedMs={} policy=facts-only schema=speedbackup.tree_pack_plan.v1",if walk_rc==0&&res.errors==0{"true"}else{"partial"},tsv_sanitize(root_s),tsv_sanitize(out_s),res.rows,res.packable,res.excluded,res.files,res.dirs,res.links,res.specials,res.bytes,res.blocks512,res.max_mtime,res.errors,res.truncated,start.elapsed().as_millis());
    if walk_rc==0 && res.errors==0 { 0 } else { 1 }
}

#[derive(Default)]
struct AppMediaResultRs { rows:u64,files:u64,dirs:u64,links:u64,specials:u64,bytes:u64,blocks512:u64,errors:u64,truncated:u64,max_mtime:u64 }

fn app_media_emit_row_rs(out:&mut File, rel:&str, m:&fs::Metadata, depth:usize, res:&mut AppMediaResultRs, max_rows:u64)->bool {
    if rel.is_empty() { return true; }
    if max_rows>0 && res.rows>=max_rows { res.truncated=1; return false; }
    let _=writeln!(out,"APP_MEDIA_INDEX_ROW\t{}\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}",tsv_sanitize(rel),stat_kind(m),mode_octal(m),m.uid(),m.gid(),m.len(),m.blocks(),m.mtime(),depth);
    res.rows=res.rows.wrapping_add(1);
    let mt=m.mtime() as u64; if mt>res.max_mtime{res.max_mtime=mt;}
    if m.blocks()>0{res.blocks512=res.blocks512.wrapping_add(m.blocks());}
    if m.is_file(){res.files=res.files.wrapping_add(1);res.bytes=res.bytes.wrapping_add(m.len());}
    else if m.file_type().is_dir(){res.dirs=res.dirs.wrapping_add(1);}
    else if m.file_type().is_symlink(){res.links=res.links.wrapping_add(1);}
    else{res.specials=res.specials.wrapping_add(1);}
    true
}

fn app_media_walk_rs(out:&mut File, root:&Path, path:&Path, depth:usize, maxdepth:usize, excludes:&HashSet<String>, res:&mut AppMediaResultRs, max_rows:u64)->i32 {
    let m=match fs::symlink_metadata(path){Ok(v)=>v,Err(_)=>{res.errors=res.errors.wrapping_add(1);return 1;}};
    let rel=rel_path(root,path);
    if !rel.is_empty(){
        if pack_plan_excluded(excludes.iter(),&rel){return 0;}
        if !app_media_emit_row_rs(out,&rel,&m,depth,res,max_rows){return 0;}
    }
    if !m.file_type().is_dir() || depth>=maxdepth || res.truncated!=0{return 0;}
    let rd=match fs::read_dir(path){Ok(v)=>v,Err(_)=>{res.errors=res.errors.wrapping_add(1);return 1;}};
    let mut rc=0;
    for ent in rd{
        let ent=match ent{Ok(v)=>v,Err(_)=>continue};
        if !path_len_c_join_ok(path,ent.file_name().as_os_str()){res.errors=res.errors.wrapping_add(1);rc=1;continue;}
        if app_media_walk_rs(out,root,&ent.path(),depth+1,maxdepth,excludes,res,max_rows)!=0{rc=1;}
        if res.truncated!=0{break;}
    }
    rc
}

fn cmd_app_media_index(root_s:&str,out_s:&str,maxdepth_s:Option<&str>,maxrows_s:Option<&str>,exclude:&str)->i32{
    let start=Instant::now();
    if root_s.is_empty() || out_s.is_empty() { return 2; }
    let root = Path::new(root_s);
    if let Err(e) = validate_root_dir_for_speedscan(root_s) {
        eprintln!("speedscan: app-media-index root invalid: {}: {}", root_s, c_strerror(&e));
        return 3;
    }
    let maxd=(parse_u64_default(maxdepth_s,3) as i32).clamp(1,32) as usize;
    let maxr=parse_u64_default(maxrows_s,20000);
    let mut out=match File::create(out_s){
        Ok(f)=>f,
        Err(e)=>{ eprintln!("speedscan: app-media-index open output failed: {}: {}", out_s, c_strerror(&e)); return 4; }
    };
    let ex=load_set(exclude);
    let _=writeln!(out,"#schema\tspeedbackup.app_media_index.v1\n#fields\trel\ttype\tmode\tuid\tgid\tbytes\tblocks512\tmtime\tdepth");
    let mut res=AppMediaResultRs::default();
    let walk_rc=app_media_walk_rs(&mut out,root,root,0,maxd,&ex,&mut res,maxr);
    let _=writeln!(out,"#summary\trows={}\tfiles={}\tdirs={}\tlinks={}\tspecials={}\tbytes={}\tblocks512={}\tmaxMtime={}\terrors={}\ttruncated={}\tmaxDepth={}\trc={}",res.rows,res.files,res.dirs,res.links,res.specials,res.bytes,res.blocks512,res.max_mtime,res.errors,res.truncated,maxd,walk_rc);
    println!("APP_MEDIA_INDEX ok={} root={} out={} rows={} files={} dirs={} links={} specials={} bytes={} blocks512={} maxMtime={} errors={} truncated={} maxDepth={} elapsedMs={} policy=facts-only schema=speedbackup.app_media_index.v1",if walk_rc==0&&res.errors==0{"true"}else{"partial"},tsv_sanitize(root_s),tsv_sanitize(out_s),res.rows,res.files,res.dirs,res.links,res.specials,res.bytes,res.blocks512,res.max_mtime,res.errors,res.truncated,maxd,start.elapsed().as_millis());
    if walk_rc==0 && res.errors==0 { 0 } else { 1 }
}


#[derive(Default, Clone)]
struct EntryFactsRs { rows:u64, files:u64, dirs:u64, links:u64, specials:u64, bytes:u64, blocks512:u64, errors:u64, truncated:u64, max_mtime:u64 }

fn entry_facts_emit_row(out:&mut File, prefix:&str, rel:&str, m:&fs::Metadata, res:&mut EntryFactsRs, max_rows:u64)->bool {
    if max_rows>0 && res.rows>=max_rows { res.truncated=1; return false; }
    let _=writeln!(out,"{}\t{}\t{}\t{:04o}\t{}\t{}\t{}\t{}\t{}\t{}",prefix,tsv_sanitize(rel),stat_kind(m),mode_octal(m),m.uid(),m.gid(),m.len(),m.blocks(),m.mtime(),m.ino());
    res.rows=res.rows.wrapping_add(1);
    let mt=m.mtime() as u64; if mt>res.max_mtime{res.max_mtime=mt;}
    if m.blocks()>0{res.blocks512=res.blocks512.wrapping_add(m.blocks());}
    if m.is_file(){res.files=res.files.wrapping_add(1);res.bytes=res.bytes.wrapping_add(m.len());}
    else if m.file_type().is_dir(){res.dirs=res.dirs.wrapping_add(1);}
    else if m.file_type().is_symlink(){res.links=res.links.wrapping_add(1);}
    else{res.specials=res.specials.wrapping_add(1);}
    true
}

fn entry_facts_walk(out:&mut File, root:&Path, path:&Path, excludes:&HashSet<String>, res:&mut EntryFactsRs, max_rows:u64)->i32 {
    let m=match fs::symlink_metadata(path){Ok(v)=>v,Err(_)=>{res.errors=res.errors.wrapping_add(1);return 1;}};
    let rel=rel_path(root,path);
    if !rel.is_empty(){
        if pack_plan_excluded(excludes.iter(),&rel){return 0;}
        if !entry_facts_emit_row(out,"ENTRY_SIZE_ROW",&rel,&m,res,max_rows){return 0;}
    }
    if !m.file_type().is_dir() || res.truncated!=0{return 0;}
    let rd=match fs::read_dir(path){Ok(v)=>v,Err(_)=>{res.errors=res.errors.wrapping_add(1);return 1;}};
    let mut rc=0;
    for ent in rd{
        let ent=match ent{Ok(v)=>v,Err(_)=>continue};
        if !path_len_c_join_ok(path,ent.file_name().as_os_str()){res.errors=res.errors.wrapping_add(1);rc=1;continue;}
        if entry_facts_walk(out,root,&ent.path(),excludes,res,max_rows)!=0{rc=1;}
        if res.truncated!=0{break;}
    }
    rc
}

fn cmd_entry_size_facts(root_s:&str,out_s:&str,exclude:&str,max_rows_s:Option<&str>)->i32{
    let start=Instant::now();
    if root_s.is_empty() || out_s.is_empty(){return 2;}
    let root=Path::new(root_s);
    if let Err(e)=validate_root_dir_for_speedscan(root_s){eprintln!("speedscan: entry-size-facts root invalid: {}: {}",root_s,c_strerror(&e));return 3;}
    let mut out=match File::create(out_s){Ok(f)=>f,Err(e)=>{eprintln!("speedscan: entry-size-facts open output failed: {}: {}",out_s,c_strerror(&e));return 4;}};
    let max_rows=parse_u64_default(max_rows_s,0);
    let ex=load_set(exclude);
    let _=writeln!(out,"#schema\tspeedbackup.entry_size_facts.v1");
    let _=writeln!(out,"#fields\trel\ttype\tmode\tuid\tgid\tbytes\tblocks512\tmtime\tino");
    let mut res=EntryFactsRs::default();
    let rc=entry_facts_walk(&mut out,root,root,&ex,&mut res,max_rows);
    let _=writeln!(out,"#summary\trows={}\tfiles={}\tdirs={}\tlinks={}\tspecials={}\tbytes={}\tblocks512={}\tmaxMtime={}\terrors={}\ttruncated={}\trc={}",res.rows,res.files,res.dirs,res.links,res.specials,res.bytes,res.blocks512,res.max_mtime,res.errors,res.truncated,rc);
    println!("ENTRY_SIZE_FACTS ok={} root={} out={} rows={} files={} dirs={} links={} specials={} bytes={} blocks512={} maxMtime={} errors={} truncated={} elapsedMs={} policy=facts-only schema=speedbackup.entry_size_facts.v1",if rc==0&&res.errors==0{"true"}else{"partial"},tsv_sanitize(root_s),tsv_sanitize(out_s),res.rows,res.files,res.dirs,res.links,res.specials,res.bytes,res.blocks512,res.max_mtime,res.errors,res.truncated,start.elapsed().as_millis());
    if rc==0&&res.errors==0{0}else{1}
}

fn scan_entry_summary(root:&Path)->EntryFactsRs{
    let mut res=EntryFactsRs::default();
    let mut f=|_p:&Path,m:&fs::Metadata,_depth:usize,_scan:&mut ScanResult|{
        let mt=m.mtime() as u64; if mt>res.max_mtime{res.max_mtime=mt;}
        if m.blocks()>0{res.blocks512=res.blocks512.wrapping_add(m.blocks());}
        if m.is_file(){res.files=res.files.wrapping_add(1);res.bytes=res.bytes.wrapping_add(m.len());}
        else if m.file_type().is_dir(){res.dirs=res.dirs.wrapping_add(1);}
        else if m.file_type().is_symlink(){res.links=res.links.wrapping_add(1);}
        else{res.specials=res.specials.wrapping_add(1);}
        Ok(())
    };
    let mut scan_res=ScanResult::default();
    let _=walk_no_follow(root,root,0,None,&mut scan_res,&mut f);
    res.errors=scan_res.errors;
    res.rows=res.files+res.dirs+res.links+res.specials;
    res
}

fn cmd_changed_entry_facts(manifest:&str,out_s:&str)->i32{
    let start=Instant::now();
    if manifest.is_empty() || out_s.is_empty(){return 2;}
    let f=match File::open(manifest){Ok(v)=>v,Err(e)=>{eprintln!("speedscan: changed-entry-facts open manifest failed: {}: {}",manifest,c_strerror(&e));return 3;}};
    let mut out=match File::create(out_s){Ok(v)=>v,Err(e)=>{eprintln!("speedscan: changed-entry-facts open output failed: {}: {}",out_s,c_strerror(&e));return 4;}};
    let _=writeln!(out,"#schema\tspeedbackup.changed_entry_facts.v1");
    let _=writeln!(out,"#fields\tapp\tpkg\tentry\tpath\texists\tfiles\tdirs\tlinks\tspecials\tbytes\tblocks512\tmaxMtime\terrors\toriginBytes\tarchiveRel");
    let mut rows=0u64; let mut exists_rows=0u64; let mut total_bytes=0u64; let mut total_files=0u64; let mut errors=0u64;
    let mut br=BufReader::new(f); let mut buf=Vec::<u8>::new();
    while let Some(l)=next_c_line_lossy(&mut br,&mut buf){
        let t=l.trim(); if t.is_empty() || t.starts_with('#'){continue;}
        let parts:Vec<&str>=t.split('\t').collect(); if parts.len()<4{continue;}
        let app=parts[0]; let pkg=parts[1]; let entry=parts[2]; let path_s=parts[3];
        let origin=parts.get(4).copied().unwrap_or("0"); let archive=parts.get(5).copied().unwrap_or("");
        rows+=1;
        let path=Path::new(path_s);
        if fs::symlink_metadata(path).map(|m|m.is_dir()).unwrap_or(false){
            let r=scan_entry_summary(path); exists_rows+=1; total_bytes=total_bytes.wrapping_add(r.bytes); total_files=total_files.wrapping_add(r.files); errors=errors.wrapping_add(r.errors);
            let _=writeln!(out,"CHANGED_ENTRY_FACT\t{}\t{}\t{}\t{}\t1\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),tsv_sanitize(entry),tsv_sanitize(path_s),r.files,r.dirs,r.links,r.specials,r.bytes,r.blocks512,r.max_mtime,r.errors,tsv_sanitize(origin),tsv_sanitize(archive));
        }else{
            let _=writeln!(out,"CHANGED_ENTRY_FACT\t{}\t{}\t{}\t{}\t0\t0\t0\t0\t0\t0\t0\t0\t0\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),tsv_sanitize(entry),tsv_sanitize(path_s),tsv_sanitize(origin),tsv_sanitize(archive));
        }
    }
    let _=writeln!(out,"#summary\trows={}\texists={}\tfiles={}\tbytes={}\terrors={}",rows,exists_rows,total_files,total_bytes,errors);
    println!("CHANGED_ENTRY_FACTS ok={} manifest={} out={} rows={} exists={} files={} bytes={} errors={} elapsedMs={} policy=facts-only schema=speedbackup.changed_entry_facts.v1",if errors==0{"true"}else{"partial"},tsv_sanitize(manifest),tsv_sanitize(out_s),rows,exists_rows,total_files,total_bytes,errors,start.elapsed().as_millis());
    0
}

fn read_tsv_rows(path:&str)->Vec<Vec<String>>{
    let f=match File::open(path){Ok(v)=>v,Err(_)=>return Vec::new()};
    let mut br=BufReader::new(f); let mut buf=Vec::<u8>::new(); let mut out=Vec::new();
    while let Some(l)=next_c_line_lossy(&mut br,&mut buf){ if l.is_empty(){continue;} out.push(l.split('\t').map(|s|s.to_string()).collect()); }
    out
}
fn write_fast_miss(out:&mut File, app:&str,pkg:&str,reason:&str,entry:&str,cur:&str,old:&str, miss_count:&mut u64, miss_apps:&mut HashSet<String>){
    let _=writeln!(out,"{}\t{}\t{}\t{}\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),reason,tsv_sanitize(entry),tsv_sanitize(cur),tsv_sanitize(old));
    *miss_count+=1;
    miss_apps.insert(pkg.to_string());
}

fn cmd_local_fastskip_join(args:&[String])->i32{
    if args.len()<16{return 2;}
    let selected=&args[2]; let summary=&args[3]; let state=&args[4]; let dirsizes=&args[5]; let exists=&args[6]; let archives=&args[7]; let blackset=&args[8]; let out_s=&args[9]; let diag_s=&args[10]; let stats_s=&args[11];
    let backup_mode=&args[12]; let backup_obb=&args[13]; let backup_user=&args[14]; let blacklist_mode=&args[15];
    let mut out=match File::create(out_s){Ok(v)=>v,Err(_)=>return 4}; let mut diag=match File::create(diag_s){Ok(v)=>v,Err(_)=>return 4};
    let sel=read_tsv_rows(selected); let mut meta:HashSet<String>=HashSet::new(); let mut rver:HashMap<String,String>=HashMap::new(); let mut rsize:HashMap<(String,String),String>=HashMap::new(); let mut state_valid:HashMap<String,String>=HashMap::new();
    for r in read_tsv_rows(summary){ if r.len()>=9{ let app=r[0].clone(); meta.insert(app.clone()); rver.insert(app.to_string(),r[2].clone()); rsize.insert((app.to_string(),"user".into()),r[3].clone()); rsize.insert((app.to_string(),"user_de".into()),r[4].clone()); rsize.insert((app.to_string(),"data".into()),r[5].clone()); rsize.insert((app.to_string(),"obb".into()),r[6].clone()); rsize.insert((app.to_string(),"media".into()),r[7].clone()); state_valid.insert(app,r[8].clone()); } }
    let mut st_old:HashMap<String,String>=HashMap::new(); let mut st_cur:HashMap<String,String>=HashMap::new(); let mut st_match:HashMap<String,String>=HashMap::new(); let mut nstate=0u64; for r in read_tsv_rows(state){ if r.len()>=5{st_old.insert(r[0].clone(),r[2].clone());st_cur.insert(r[0].clone(),r[3].clone());st_match.insert(r[0].clone(),r[4].clone());nstate+=1;} }
    let mut lsize:HashMap<(String,String),String>=HashMap::new(); for r in read_tsv_rows(dirsizes){ if r.len()>=3{lsize.insert((r[0].clone(),r[1].clone()),r[2].clone());} }
    let mut dexists:HashSet<(String,String)>=HashSet::new(); let mut nexists=0u64; for r in read_tsv_rows(exists){ if r.len()>=2{dexists.insert((r[0].clone(),r[1].clone()));nexists+=1;} }
    let mut arch:HashSet<(String,String)>=HashSet::new(); let mut narch=0u64; for r in read_tsv_rows(archives){ if r.len()>=2{arch.insert((r[0].clone(),r[1].clone()));narch+=1;} }
    let mut black:HashSet<String>=HashSet::new(); for r in read_tsv_rows(blackset){ if r.len()>=1{black.insert(r[0].clone());} }
    let mut fast=0u64; let mut misses=0u64; let mut miss_apps:HashSet<String>=HashSet::new();
    for r in sel.iter(){ if r.len()<4{continue;} let app=&r[0]; let pkg=&r[1]; let mut nodata=r[2].as_str()=="1"; let cv=&r[3]; let mut ok=true;
        if black.contains(pkg){ if blacklist_mode=="true"{write_fast_miss(&mut diag,app,pkg,"blacklist_full_skip","","","",&mut misses,&mut miss_apps);continue;} nodata=true; }
        if !meta.contains(app){write_fast_miss(&mut diag,app,pkg,"local_json_missing","","","",&mut misses,&mut miss_apps);continue;}
        if !arch.contains(&(app.to_string(),"apk".to_string())){write_fast_miss(&mut diag,app,pkg,"apk_archive_missing","","","",&mut misses,&mut miss_apps);continue;}
        let rv=rver.get(app).cloned().unwrap_or_default(); if cv.is_empty(){write_fast_miss(&mut diag,app,pkg,"current_version_missing","","",&rv,&mut misses,&mut miss_apps);continue;} if rv.is_empty() || rv!=*cv{write_fast_miss(&mut diag,app,pkg,"apk_version_mismatch","",cv,&rv,&mut misses,&mut miss_apps);continue;}
        if backup_mode=="true" && !nodata && backup_user=="true" && pkg!="bin.mt.plus"{
            if state_valid.get(app).map(|s|s.as_str())!=Some("1") || st_old.get(app).map(|s|s.as_str())!=Some("1"){write_fast_miss(&mut diag,app,pkg,"appstate_old_invalid","","","",&mut misses,&mut miss_apps);continue;}
            if st_cur.get(app).map(|s|s.as_str())!=Some("1"){write_fast_miss(&mut diag,app,pkg,"appstate_current_missing","","","",&mut misses,&mut miss_apps);continue;}
            if st_match.get(app).map(|s|s.as_str())!=Some("1"){write_fast_miss(&mut diag,app,pkg,"appstate_mismatch","","","",&mut misses,&mut miss_apps);continue;}
        }
        let check_entry=|entry:&str, diag:&mut File, misses:&mut u64, miss_apps:&mut HashSet<String>| -> bool { let fs_key=(pkg.to_string(),entry.to_string()); let app_key=(app.to_string(),entry.to_string()); if !dexists.contains(&fs_key){return true;} let cur=match lsize.get(&fs_key){Some(v)=>v.clone(),None=>{write_fast_miss(diag,app,pkg,"local_size_missing",entry,"",rsize.get(&app_key).map(|s|s.as_str()).unwrap_or(""),misses,miss_apps);return false;}}; if !cur.chars().all(|c|c.is_ascii_digit()){write_fast_miss(diag,app,pkg,"local_size_invalid",entry,&cur,rsize.get(&app_key).map(|s|s.as_str()).unwrap_or(""),misses,miss_apps);return false;} if cur.len()<4{return true;} let old=rsize.get(&app_key).cloned().unwrap_or_default(); if old.is_empty() || old=="null" || old!=cur{write_fast_miss(diag,app,pkg,"size_mismatch",entry,&cur,&old,misses,miss_apps);return false;} if !arch.contains(&app_key){write_fast_miss(diag,app,pkg,"archive_missing",entry,&cur,&old,misses,miss_apps);return false;} true };
        if backup_mode=="true" && !nodata && pkg!="bin.mt.plus"{ if backup_obb=="true"{ if !check_entry("data",&mut diag,&mut misses,&mut miss_apps){ok=false;} if !check_entry("obb",&mut diag,&mut misses,&mut miss_apps){ok=false;} if !check_entry("media",&mut diag,&mut misses,&mut miss_apps){ok=false;} } if backup_user=="true"{ if !check_entry("user",&mut diag,&mut misses,&mut miss_apps){ok=false;} if !check_entry("user_de",&mut diag,&mut misses,&mut miss_apps){ok=false;} } }
        if ok{let _=writeln!(out,"{}",app); fast+=1;}
    }
    let mut stats=match File::create(stats_s){Ok(v)=>v,Err(_)=>return 4}; let _=writeln!(stats,"{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",sel.len(),meta.len(),nstate,nexists,narch,fast,miss_apps.len(),misses); 0
}



fn full_dirsize_enabled_entries(backup_mode: &str, backup_obb: &str, backup_user: &str) -> Vec<&'static str> {
    let mut v: Vec<&'static str> = Vec::new();
    if backup_mode != "true" { return v; }
    // Preserve the historical full-manifest shell order exactly.
    if backup_user == "true" { v.push("user"); v.push("user_de"); }
    if backup_obb == "true" { v.push("data"); v.push("obb"); v.push("media"); }
    v
}

fn cmd_dir_size_manifest(args: &[String]) -> i32 {
    if args.len() < 11 { return 2; }
    let start = Instant::now();
    let pkg_list=&args[2]; let out_manifest=&args[3]; let out_exists=&args[4];
    let backup_mode=&args[5]; let backup_obb=&args[6]; let backup_user=&args[7];
    let android_root=&args[8]; let user_root=&args[9]; let user_de_root=&args[10];
    let f=match File::open(pkg_list){Ok(v)=>v,Err(_)=>return 3};
    let mut manifest=match File::create(out_manifest){Ok(v)=>v,Err(_)=>return 4};
    let mut exists=match File::create(out_exists){Ok(v)=>v,Err(_)=>return 4};
    let mut br=BufReader::new(f); let mut buf=Vec::<u8>::new();
    let mut packages=0u64; let mut primary_rows=0u64; let mut auxiliary_rows=0u64;
    while let Some(line)=next_c_line_lossy(&mut br,&mut buf){
        let pkg=line.trim();
        if pkg.is_empty() { continue; }
        packages+=1;
        for entry in full_dirsize_enabled_entries(backup_mode,backup_obb,backup_user) {
            let path=path_for_backup_entry(entry,android_root,user_root,user_de_root,pkg);
            if path.is_empty() { continue; }
            if !fs::metadata(Path::new(path.as_str())).map(|m|m.is_dir()).unwrap_or(false) { continue; }
            let _=writeln!(exists,"{}\t{}",tsv_sanitize(pkg),entry);
            let (n,a)=write_presize_manifest_entry(&mut manifest,pkg,entry,&path);
            primary_rows+=n.saturating_sub(a); auxiliary_rows+=a;
        }
    }
    let manifest_rows=primary_rows+auxiliary_rows;
    println!("DIR_SIZE_MANIFEST packages={} primaryRows={} auxiliaryRows={} manifestRows={} existsRows={} elapsedMs={} mode=r674 schema=speedscan.dir_size_manifest.v1",packages,primary_rows,auxiliary_rows,manifest_rows,primary_rows,start.elapsed().as_millis());
    0
}

fn cmd_backup_entry_presence_map(args: &[String]) -> i32 {
    if args.len() < 10 { return 2; }
    let selected=&args[2]; let out_s=&args[3]; let backup_mode=&args[4]; let backup_obb=&args[5]; let backup_user=&args[6];
    let android_root=&args[7]; let user_root=&args[8]; let user_de_root=&args[9];
    let rows=read_tsv_rows(selected);
    let mut found:Vec<(String,String)>=Vec::new();
    for r in rows.iter() {
        if r.len()<3 { continue; }
        let pkg=&r[1]; let nodata=r[2].as_str()=="1";
        for entry in presize_enabled_entries(backup_mode,backup_obb,backup_user,nodata,pkg) {
            let p=path_for_backup_entry(entry,android_root,user_root,user_de_root,pkg);
            if p.is_empty() { continue; }
            if fs::metadata(Path::new(p.as_str())).map(|m|m.is_dir()).unwrap_or(false) {
                found.push((pkg.clone(),entry.to_string()));
            }
        }
    }
    found.sort(); found.dedup();
    let mut out=match File::create(out_s){Ok(v)=>v,Err(_)=>return 4};
    for (pkg,entry) in found.iter(){ let _=writeln!(out,"{}\t{}",tsv_sanitize(pkg),entry); }
    println!("BACKUP_ENTRY_PRESENCE_MAP selected={} rows={} mode=r668 schema=speedscan.backup_entry_presence_map.v1",rows.len(),found.len());
    0
}

fn cmd_payload_archive_set(args: &[String]) -> i32 {
    if args.len() < 4 { return 2; }
    let input=&args[2]; let out_s=&args[3];
    let f=match File::open(input){Ok(v)=>v,Err(_)=>return 3};
    let mut br=BufReader::new(f); let mut buf=Vec::<u8>::new(); let mut rows:Vec<(String,String)>=Vec::new();
    while let Some(line)=next_c_line_lossy(&mut br,&mut buf){
        let rel=line.split('\t').next().unwrap_or("").trim(); if rel.is_empty(){continue;}
        let mut parts=rel.split('/'); let app=parts.next().unwrap_or(""); if app.is_empty(){continue;}
        let tail=rel.rsplit('/').next().unwrap_or("");
        let entry=tail.strip_suffix(".tar.zst").or_else(||tail.strip_suffix(".tar")).unwrap_or(tail);
        if matches!(entry,"apk"|"data"|"obb"|"media"|"user"|"user_de") { rows.push((app.to_string(),entry.to_string())); }
    }
    rows.sort(); rows.dedup();
    let mut out=match File::create(out_s){Ok(v)=>v,Err(_)=>return 4};
    for (app,entry) in rows.iter(){ let _=writeln!(out,"{}\t{}",tsv_sanitize(app),entry); }
    println!("PAYLOAD_ARCHIVE_SET rows={} mode=r668 schema=speedscan.payload_archive_set.v1",rows.len());
    0
}

fn path_for_backup_entry(entry: &str, android_root: &str, user_root: &str, user_de_root: &str, pkg: &str) -> String {
    match entry {
        "user" => Path::new(user_root).join(pkg).to_string_lossy().into_owned(),
        "user_de" => Path::new(user_de_root).join(pkg).to_string_lossy().into_owned(),
        "data" | "obb" | "media" => Path::new(android_root).join(entry).join(pkg).to_string_lossy().into_owned(),
        _ => String::new(),
    }
}

fn presize_enabled_entries(backup_mode: &str, backup_obb: &str, backup_user: &str, nodata: bool, pkg: &str) -> Vec<&'static str> {
    let mut v: Vec<&'static str> = Vec::new();
    if backup_mode != "true" || nodata || pkg == "bin.mt.plus" { return v; }
    if backup_obb == "true" {
        v.push("data");
        v.push("obb");
        v.push("media");
    }
    if backup_user == "true" {
        v.push("user");
        v.push("user_de");
    }
    v
}

fn write_presize_manifest_entry(out:&mut File,pkg:&str,entry:&str,path:&str)->(u64,u64){
    let _=writeln!(out,"{}\t{}\t{}",tsv_sanitize(pkg),entry,tsv_sanitize(path));
    let mut aux=0u64;
    let base=Path::new(path);
    let mut maybe_add=|suffix:&str,child:&str|{
        let p=base.join(child);
        if fs::metadata(&p).map(|m|m.is_dir()).unwrap_or(false){
            let typ=format!("{}_exclude_{}",entry,suffix);
            let ps=p.to_string_lossy();
            let _=writeln!(out,"{}\t{}\t{}",tsv_sanitize(pkg),typ,tsv_sanitize(ps.as_ref()));
            aux+=1;
        }
    };
    match entry {
        "user"|"user_de"=>{ maybe_add("cache","cache"); maybe_add("code_cache","code_cache"); }
        "data"|"obb"|"media"=>maybe_add("cache","cache"),
        _=>{}
    }
    (1+aux,aux)
}

fn write_presize_existing_entries(
    out: &mut File,
    diag: &mut File,
    dexists: &HashSet<(String, String)>,
    app: &str,
    pkg: &str,
    nodata: bool,
    reason: &str,
    backup_mode: &str,
    backup_obb: &str,
    backup_user: &str,
    android_root: &str,
    user_root: &str,
    user_de_root: &str,
) -> (u64,u64) {
    let mut rows = 0u64; let mut aux_rows=0u64;
    for entry in presize_enabled_entries(backup_mode, backup_obb, backup_user, nodata, pkg) {
        if !dexists.contains(&(pkg.to_string(), entry.to_string())) { continue; }
        let path = path_for_backup_entry(entry, android_root, user_root, user_de_root, pkg);
        if path.is_empty() { continue; }
        let (n,a)=write_presize_manifest_entry(out,pkg,entry,&path); rows+=n; aux_rows+=a;
    }
    if rows > 0 {
        let _ = writeln!(diag, "{}\t{}\t{}\tpresize_full_dirsize_rows={}\tauxiliary_rows={}", tsv_sanitize(app), tsv_sanitize(pkg), reason, rows, aux_rows);
    }
    (rows,aux_rows)
}


#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TinyDirProbe { Tiny(u64), NotTiny, Unknown }

fn tiny_dir_probe(path: &Path, limit: u64, max_nodes: usize) -> TinyDirProbe {
    let mut stack = vec![path.to_path_buf()];
    let mut total = 0u64;
    let mut nodes = 0usize;
    while let Some(p) = stack.pop() {
        let meta = match fs::symlink_metadata(&p) { Ok(v) => v, Err(_) => return TinyDirProbe::Unknown };
        nodes = nodes.saturating_add(1);
        if nodes > max_nodes { return TinyDirProbe::Unknown; }
        let ft = meta.file_type();
        if ft.is_symlink() { continue; }
        if ft.is_file() {
            total = total.saturating_add(meta.len());
            if total >= limit { return TinyDirProbe::NotTiny; }
            continue;
        }
        if ft.is_dir() {
            let rd = match fs::read_dir(&p) { Ok(v) => v, Err(_) => return TinyDirProbe::Unknown };
            for ent in rd {
                match ent { Ok(v) => stack.push(v.path()), Err(_) => return TinyDirProbe::Unknown }
            }
        }
    }
    TinyDirProbe::Tiny(total)
}

fn archive_exists_local(backup_root: &str, app: &str, entry: &str) -> bool {
    let base = Path::new(backup_root).join(app);
    fs::metadata(base.join(format!("{}.tar", entry))).is_ok()
        || fs::metadata(base.join(format!("{}.tar.zst", entry))).is_ok()
}

fn rewrite_presize_stats_v4(path: &str, scan_manifest_rows: u64, scan_primary_rows: u64, scan_aux_rows: u64,
                            tiny_rows: u64, tiny_primary_rows: u64, tiny_aux_rows: u64,
                            presence_ms: u128, archive_ms: u128, planner_ms: u128, tiny_ms: u128, total_ms: u128, mode_value: &str) -> bool {
    let mut rows: Vec<(String,String)> = Vec::new();
    for r in read_tsv_rows(path) {
        if r.len() >= 2 { rows.push((r[0].clone(), r[1].clone())); }
    }
    let mut set = |key: &str, value: String| {
        if let Some(row) = rows.iter_mut().find(|r| r.0 == key) { row.1 = value; }
        else { rows.push((key.to_string(), value)); }
    };
    set("manifestRows", scan_manifest_rows.to_string());
    set("primaryRows", scan_primary_rows.to_string());
    set("auxiliaryRows", scan_aux_rows.to_string());
    set("tinyRows", tiny_rows.to_string());
    set("tinyPrimaryRows", tiny_primary_rows.to_string());
    set("tinyAuxiliaryRows", tiny_aux_rows.to_string());
    set("presenceElapsedMs", presence_ms.to_string());
    set("archiveElapsedMs", archive_ms.to_string());
    set("plannerElapsedMs", planner_ms.to_string());
    set("tinyProbeElapsedMs", tiny_ms.to_string());
    set("totalElapsedMs", total_ms.to_string());
    set("mode", mode_value.to_string());
    let mut out = match File::create(path) { Ok(v) => v, Err(_) => return false };
    for (k,v) in rows { if writeln!(out, "{}\t{}", k, v).is_err() { return false; } }
    true
}

fn run_fastskip_presize_plan_v4_after_facts(
    selected: &str,
    summary: &str,
    state: &str,
    blackset: &str,
    out_exists: &str,
    out_archives: &str,
    out_manifest: &str,
    out_stats: &str,
    out_diag: &str,
    out_tiny: &str,
    backup_mode: &str,
    backup_obb: &str,
    backup_user: &str,
    blacklist_mode: &str,
    android_root: &str,
    user_root: &str,
    user_de_root: &str,
    selected_rows: &[Vec<String>],
    live: &[(String,String)],
    presence_ms: u128,
    archive_ms: u128,
    total_start: Instant,
    mode_value: &str,
    schema: &str,
    log_prefix: &str,
) -> i32 {
    let planner_start=Instant::now();
    let v3_args=vec![
        "speedscan".to_string(), "local-fastskip-presize-plan".to_string(), selected.to_string(), summary.to_string(), state.to_string(),
        out_exists.to_string(), out_archives.to_string(), blackset.to_string(), out_manifest.to_string(), out_stats.to_string(), out_diag.to_string(),
        backup_mode.to_string(), backup_obb.to_string(), backup_user.to_string(), blacklist_mode.to_string(), android_root.to_string(), user_root.to_string(), user_de_root.to_string()
    ];
    let rc=cmd_local_fastskip_presize_plan(&v3_args);
    let planner_ms=planner_start.elapsed().as_millis();
    if rc != 0 { return rc; }

    let tiny_start=Instant::now();
    let mut old_sizes: HashMap<(String,String),String> = HashMap::new();
    for r in read_tsv_rows(summary) {
        if r.len() >= 8 {
            let app=r[0].clone();
            old_sizes.insert((app.clone(),"user".to_string()),r[3].clone());
            old_sizes.insert((app.clone(),"user_de".to_string()),r[4].clone());
            old_sizes.insert((app.clone(),"data".to_string()),r[5].clone());
            old_sizes.insert((app.clone(),"obb".to_string()),r[6].clone());
            old_sizes.insert((app,"media".to_string()),r[7].clone());
        }
    }
    let old_missing_apps: HashSet<String> = read_tsv_rows(out_diag).into_iter()
        .filter(|r| r.len() >= 3 && r[2] == "old_size_missing")
        .map(|r| r[0].clone()).collect();
    let live_set: HashSet<(String,String)> = live.iter().cloned().collect();
    let mut tiny_primary: HashMap<(String,String),u64> = HashMap::new();
    let mut tiny_all: Vec<(String,String,u64)> = Vec::new();
    for r in selected_rows {
        if r.len() < 3 { continue; }
        let app=&r[0]; let pkg=&r[1]; let nodata=r[2].as_str()=="1";
        if !old_missing_apps.contains(app) { continue; }
        for entry in presize_enabled_entries(backup_mode,backup_obb,backup_user,nodata,pkg) {
            if !live_set.contains(&(pkg.clone(),entry.to_string())) { continue; }
            let old=old_sizes.get(&(app.clone(),entry.to_string())).cloned().unwrap_or_default();
            if !(old.is_empty() || old=="null") { continue; }
            let path=path_for_backup_entry(entry,android_root,user_root,user_de_root,pkg);
            let size=match tiny_dir_probe(Path::new(&path),1000,4096) { TinyDirProbe::Tiny(v) => v, _ => continue };
            tiny_primary.insert((pkg.clone(),entry.to_string()),size);
            tiny_all.push((pkg.clone(),entry.to_string(),size));
            let base=Path::new(&path);
            for (suffix,child) in [("cache","cache"),("code_cache","code_cache")] {
                if suffix=="code_cache" && !(entry=="user" || entry=="user_de") { continue; }
                let child_path=base.join(child);
                if !fs::metadata(&child_path).map(|m|m.is_dir()).unwrap_or(false) { continue; }
                if let TinyDirProbe::Tiny(v)=tiny_dir_probe(&child_path,1000,4096) {
                    tiny_all.push((pkg.clone(),format!("{}_exclude_{}",entry,suffix),v));
                }
            }
        }
    }
    tiny_all.sort_by(|a,b| (&a.0,&a.1).cmp(&(&b.0,&b.1))); tiny_all.dedup_by(|a,b| a.0==b.0 && a.1==b.1);
    let mut tiny_file=match File::create(out_tiny){Ok(v)=>v,Err(_)=>return 4};
    for (pkg,entry,size) in &tiny_all { let _=writeln!(tiny_file,"{}\t{}\t{}",tsv_sanitize(pkg),entry,size); }
    drop(tiny_file);

    let manifest_rows=read_tsv_rows(out_manifest);
    let tmp_manifest=format!("{}.r686tmp",out_manifest);
    let mut mf=match File::create(&tmp_manifest){Ok(v)=>v,Err(_)=>return 4};
    let mut scan_rows=0u64; let mut scan_primary=0u64; let mut scan_aux=0u64;
    for r in manifest_rows {
        if r.len()<3 { continue; }
        let pkg=&r[0]; let typ=&r[1];
        let mut drop_row=false;
        for (key_pkg,key_entry) in tiny_primary.keys() {
            if pkg==key_pkg && (typ==key_entry || typ==&format!("{}_exclude_cache",key_entry) || typ==&format!("{}_exclude_code_cache",key_entry)) { drop_row=true; break; }
        }
        if drop_row { continue; }
        let _=writeln!(mf,"{}\t{}\t{}",r[0],r[1],r[2]);
        scan_rows+=1;
        if typ.contains("_exclude_cache") || typ.contains("_exclude_code_cache") { scan_aux+=1; } else { scan_primary+=1; }
    }
    drop(mf);
    if fs::rename(&tmp_manifest,out_manifest).is_err() { let _=fs::remove_file(&tmp_manifest); return 4; }
    let tiny_primary_rows=tiny_primary.len() as u64;
    let tiny_rows=tiny_all.len() as u64;
    let tiny_aux_rows=tiny_rows.saturating_sub(tiny_primary_rows);
    let tiny_ms=tiny_start.elapsed().as_millis();
    let total_ms=total_start.elapsed().as_millis();
    if !rewrite_presize_stats_v4(out_stats,scan_rows,scan_primary,scan_aux,tiny_rows,tiny_primary_rows,tiny_aux_rows,presence_ms,archive_ms,planner_ms,tiny_ms,total_ms,mode_value) { return 4; }
    println!("{}\tOK\tselected={}\tliveRows={}\tarchiveRows={}\tscanRows={}\tscanPrimaryRows={}\tscanAuxiliaryRows={}\ttinyRows={}\ttinyPrimaryRows={}\ttinyAuxiliaryRows={}\tpresenceElapsedMs={}\tarchiveElapsedMs={}\tplannerElapsedMs={}\ttinyProbeElapsedMs={}\ttotalElapsedMs={}\tmode={}\tschema={}",
        log_prefix,selected_rows.len(),live.len(),read_tsv_rows(out_archives).len(),scan_rows,scan_primary,scan_aux,tiny_rows,tiny_primary_rows,tiny_aux_rows,presence_ms,archive_ms,planner_ms,tiny_ms,total_ms,mode_value,schema);
    0
}

fn cmd_local_fastskip_presize_plan_v4(args: &[String]) -> i32 {
    if args.len() < 20 { return 2; }
    let total_start = Instant::now();
    let selected=&args[2]; let summary=&args[3]; let state=&args[4]; let blackset=&args[5]; let backup_root=&args[6];
    let out_exists=&args[7]; let out_archives=&args[8]; let out_manifest=&args[9]; let out_stats=&args[10]; let out_diag=&args[11]; let out_tiny=&args[12];
    let backup_mode=&args[13]; let backup_obb=&args[14]; let backup_user=&args[15]; let blacklist_mode=&args[16];
    let android_root=&args[17]; let user_root=&args[18]; let user_de_root=&args[19];

    let selected_rows = read_tsv_rows(selected);
    let presence_start = Instant::now();
    let mut live: Vec<(String,String)> = Vec::new();
    for r in &selected_rows {
        if r.len() < 3 { continue; }
        let pkg=&r[1]; let nodata=r[2].as_str()=="1";
        for entry in presize_enabled_entries(backup_mode,backup_obb,backup_user,nodata,pkg) {
            let p=path_for_backup_entry(entry,android_root,user_root,user_de_root,pkg);
            if !p.is_empty() && fs::metadata(Path::new(&p)).map(|m|m.is_dir()).unwrap_or(false) {
                live.push((pkg.clone(),entry.to_string()));
            }
        }
    }
    live.sort(); live.dedup();
    let mut exists_file=match File::create(out_exists){Ok(v)=>v,Err(_)=>return 4};
    for (pkg,entry) in &live { let _=writeln!(exists_file,"{}\t{}",tsv_sanitize(pkg),entry); }
    drop(exists_file);
    let presence_ms=presence_start.elapsed().as_millis();

    let archive_start=Instant::now();
    let mut archives: Vec<(String,String)> = Vec::new();
    for r in &selected_rows {
        if r.len() < 2 { continue; }
        let app=&r[0];
        for entry in ["apk","data","obb","media","user","user_de"] {
            if archive_exists_local(backup_root,app,entry) { archives.push((app.clone(),entry.to_string())); }
        }
    }
    archives.sort(); archives.dedup();
    let mut archive_file=match File::create(out_archives){Ok(v)=>v,Err(_)=>return 4};
    for (app,entry) in &archives { let _=writeln!(archive_file,"{}\t{}",tsv_sanitize(app),entry); }
    drop(archive_file);
    let archive_ms=archive_start.elapsed().as_millis();

    run_fastskip_presize_plan_v4_after_facts(
        selected,summary,state,blackset,out_exists,out_archives,out_manifest,out_stats,out_diag,out_tiny,
        backup_mode,backup_obb,backup_user,blacklist_mode,android_root,user_root,user_de_root,
        &selected_rows,&live,presence_ms,archive_ms,total_start,
        "r675-local-fastskip-presize-plan-v4","speedscan.local_fastskip_presize_plan_v4.v1","LOCAL_FASTSKIP_PRESIZE_PLAN_V4"
    )
}

fn cmd_local_fastskip_presize_plan(args: &[String]) -> i32 {
    if args.len() < 18 { return 2; }
    let selected=&args[2]; let summary=&args[3]; let state=&args[4]; let exists=&args[5]; let archives=&args[6]; let blackset=&args[7];
    let out_manifest=&args[8]; let out_stats=&args[9]; let out_diag=&args[10];
    let backup_mode=&args[11]; let backup_obb=&args[12]; let backup_user=&args[13]; let blacklist_mode=&args[14];
    let android_root=&args[15]; let user_root=&args[16]; let user_de_root=&args[17];
    let mut out=match File::create(out_manifest){Ok(v)=>v,Err(_)=>return 4};
    let mut stats=match File::create(out_stats){Ok(v)=>v,Err(_)=>return 4};
    let mut diag=match File::create(out_diag){Ok(v)=>v,Err(_)=>return 4};
    let sel=read_tsv_rows(selected);
    let mut meta:HashSet<String>=HashSet::new();
    let mut rver:HashMap<String,String>=HashMap::new();
    let mut rsize:HashMap<(String,String),String>=HashMap::new();
    let mut state_valid:HashMap<String,String>=HashMap::new();
    for r in read_tsv_rows(summary){
        if r.len()>=9{
            let app=r[0].clone();
            meta.insert(app.clone());
            rver.insert(app.to_string(),r[2].clone());
            rsize.insert((app.to_string(),"user".into()),r[3].clone());
            rsize.insert((app.to_string(),"user_de".into()),r[4].clone());
            rsize.insert((app.to_string(),"data".into()),r[5].clone());
            rsize.insert((app.to_string(),"obb".into()),r[6].clone());
            rsize.insert((app.to_string(),"media".into()),r[7].clone());
            state_valid.insert(app,r[8].clone());
        }
    }
    let mut st_old:HashMap<String,String>=HashMap::new(); let mut st_cur:HashMap<String,String>=HashMap::new(); let mut st_match:HashMap<String,String>=HashMap::new();
    for r in read_tsv_rows(state){ if r.len()>=5{st_old.insert(r[0].clone(),r[2].clone());st_cur.insert(r[0].clone(),r[3].clone());st_match.insert(r[0].clone(),r[4].clone());} }
    let mut dexists:HashSet<(String,String)>=HashSet::new(); for r in read_tsv_rows(exists){ if r.len()>=2{dexists.insert((r[0].clone(),r[1].clone()));} }
    let mut arch:HashSet<(String,String)>=HashSet::new(); for r in read_tsv_rows(archives){ if r.len()>=2{arch.insert((r[0].clone(),r[1].clone()));} }
    let mut black:HashSet<String>=HashSet::new(); for r in read_tsv_rows(blackset){ if !r.is_empty(){black.insert(r[0].clone());} }
    let mut candidates=0u64; let mut manifest_rows=0u64; let mut auxiliary_rows=0u64; let mut primary_rows=0u64; let mut non_size_miss=0u64; let mut first_full=0u64; let mut full_dirsize_rows=0u64; let mut compare_rows=0u64;
    for r in sel.iter(){
        if r.len()<4{continue;}
        let app=&r[0]; let pkg=&r[1]; let mut nodata=r[2].as_str()=="1"; let cv=&r[3];
        if black.contains(pkg){
            if blacklist_mode=="true"{ let _=writeln!(diag,"{}\t{}\tblacklist_full_skip",tsv_sanitize(app),tsv_sanitize(pkg)); non_size_miss+=1; continue; }
            nodata=true;
        }
        if !meta.contains(app){
            let _=writeln!(diag,"{}\t{}\tlocal_json_missing",tsv_sanitize(app),tsv_sanitize(pkg));
            first_full+=1; non_size_miss+=1;
            let (n,a)=write_presize_existing_entries(&mut out,&mut diag,&dexists,app,pkg,nodata,"local_json_missing",backup_mode,backup_obb,backup_user,android_root,user_root,user_de_root);
            manifest_rows+=n; auxiliary_rows+=a; primary_rows+=n-a; full_dirsize_rows+=n;
            continue;
        }
        if !arch.contains(&(app.to_string(),"apk".to_string())){
            let _=writeln!(diag,"{}\t{}\tapk_archive_missing",tsv_sanitize(app),tsv_sanitize(pkg));
            first_full+=1; non_size_miss+=1;
            let (n,a)=write_presize_existing_entries(&mut out,&mut diag,&dexists,app,pkg,nodata,"apk_archive_missing",backup_mode,backup_obb,backup_user,android_root,user_root,user_de_root);
            manifest_rows+=n; auxiliary_rows+=a; primary_rows+=n-a; full_dirsize_rows+=n;
            continue;
        }
        let rv=rver.get(app).cloned().unwrap_or_default();
        if cv.is_empty(){
            let _=writeln!(diag,"{}\t{}\tcurrent_version_missing",tsv_sanitize(app),tsv_sanitize(pkg));
            non_size_miss+=1;
            let (n,a)=write_presize_existing_entries(&mut out,&mut diag,&dexists,app,pkg,nodata,"current_version_missing",backup_mode,backup_obb,backup_user,android_root,user_root,user_de_root);
            manifest_rows+=n; auxiliary_rows+=a; primary_rows+=n-a; full_dirsize_rows+=n;
            continue;
        }
        if rv.is_empty() || rv!=*cv{
            let _=writeln!(diag,"{}\t{}\tapk_version_mismatch",tsv_sanitize(app),tsv_sanitize(pkg));
            non_size_miss+=1;
            let (n,a)=write_presize_existing_entries(&mut out,&mut diag,&dexists,app,pkg,nodata,"apk_version_mismatch",backup_mode,backup_obb,backup_user,android_root,user_root,user_de_root);
            manifest_rows+=n; auxiliary_rows+=a; primary_rows+=n-a; full_dirsize_rows+=n;
            continue;
        }
        if backup_mode=="true" && !nodata && backup_user=="true" && pkg!="bin.mt.plus"{
            let fail_reason = if state_valid.get(app).map(|s|s.as_str())!=Some("1") || st_old.get(app).map(|s|s.as_str())!=Some("1") {
                Some("appstate_old_invalid")
            } else if st_cur.get(app).map(|s|s.as_str())!=Some("1") {
                Some("appstate_current_missing")
            } else if st_match.get(app).map(|s|s.as_str())!=Some("1") {
                Some("appstate_mismatch")
            } else { None };
            if let Some(reason)=fail_reason{
                let _=writeln!(diag,"{}\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),reason);
                non_size_miss+=1;
                let (n,a)=write_presize_existing_entries(&mut out,&mut diag,&dexists,app,pkg,nodata,reason,backup_mode,backup_obb,backup_user,android_root,user_root,user_de_root);
                manifest_rows+=n; auxiliary_rows+=a; primary_rows+=n-a; full_dirsize_rows+=n;
                continue;
            }
        }
        let entries=presize_enabled_entries(backup_mode,backup_obb,backup_user,nodata,pkg);
        let mut forced_reason: Option<&'static str> = None;
        for entry in entries.iter(){
            let fs_key=(pkg.to_string(),(*entry).to_string());
            if !dexists.contains(&fs_key){continue;}
            let app_key=(app.to_string(),(*entry).to_string());
            let old=rsize.get(&app_key).cloned().unwrap_or_default();
            if old.is_empty() || old=="null"{ forced_reason=Some("old_size_missing"); break; }
            if !arch.contains(&app_key){ forced_reason=Some("archive_missing"); break; }
        }
        if let Some(reason)=forced_reason{
            let _=writeln!(diag,"{}\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),reason);
            non_size_miss+=1;
            let (n,a)=write_presize_existing_entries(&mut out,&mut diag,&dexists,app,pkg,nodata,reason,backup_mode,backup_obb,backup_user,android_root,user_root,user_de_root);
            manifest_rows+=n; auxiliary_rows+=a; primary_rows+=n-a; full_dirsize_rows+=n;
            continue;
        }
        candidates+=1;
        for entry in entries.iter(){
            let fs_key=(pkg.to_string(),(*entry).to_string());
            if !dexists.contains(&fs_key){continue;}
            let path=path_for_backup_entry(entry,android_root,user_root,user_de_root,pkg);
            if path.is_empty(){continue;}
            let (n,a)=write_presize_manifest_entry(&mut out,pkg,entry,&path);
            manifest_rows+=n; auxiliary_rows+=a; primary_rows+=1; compare_rows+=1;
        }
    }
    let plan_mode = if first_full > 0 && candidates == 0 { "first-full-keep-full-dirsize" } else if full_dirsize_rows > 0 { "mixed-baseline-safe-dirsize" } else { "two-phase-incremental-safe" };
    let _=writeln!(stats,"selected\t{}",sel.len());
    let _=writeln!(stats,"candidates\t{}",candidates);
    let _=writeln!(stats,"manifestRows\t{}",manifest_rows);
    let _=writeln!(stats,"primaryRows\t{}",primary_rows);
    let _=writeln!(stats,"auxiliaryRows\t{}",auxiliary_rows);
    let _=writeln!(stats,"firstFull\t{}",first_full);
    let _=writeln!(stats,"nonSizeMiss\t{}",non_size_miss);
    let _=writeln!(stats,"fullDirsizeRows\t{}",full_dirsize_rows);
    let _=writeln!(stats,"compareRows\t{}",compare_rows);
    let _=writeln!(stats,"planMode\t{}",plan_mode);
    let _=writeln!(stats,"mode\tr668-local-fastskip-presize-plan-v3");
    println!("LOCAL_FASTSKIP_PRESIZE_PLAN selected={} candidates={} manifestRows={} primaryRows={} auxiliaryRows={} firstFull={} nonSizeMiss={} fullDirsizeRows={} compareRows={} planMode={} mode=r668 schema=speedscan.local_fastskip_presize_plan_v3.v1",sel.len(),candidates,manifest_rows,primary_rows,auxiliary_rows,first_full,non_size_miss,full_dirsize_rows,compare_rows,plan_mode);
    0
}

fn cmd_remote_stream_local_read_plan(args:&[String])->i32{
    if args.len()<11{return 2;}
    let selected=&args[2]; let dirsizes=&args[3]; let out_s=&args[4]; let backup_mode=&args[5]; let backup_obb=&args[6]; let backup_user=&args[7];
    let android_root=&args[8]; let user_root=&args[9]; let user_de_root=&args[10];
    let sel=read_tsv_rows(selected); let mut out=match File::create(out_s){Ok(v)=>v,Err(_)=>return 4};
    let mut lsize:HashMap<(String,String),String>=HashMap::new(); for r in read_tsv_rows(dirsizes){if r.len()>=3{lsize.insert((r[0].clone(),r[1].clone()),r[2].clone());}}
    let mut rows=0u64;
    for r in sel.iter(){
        if r.len()<3{continue;}
        let app=&r[0]; let pkg=&r[1]; let nodata=r[2].as_str()=="1";
        if backup_mode!="true" || nodata || pkg=="bin.mt.plus"{continue;}
        let mut add_entry=|entry:&str, base:&str, sub:&str|{
            let path=Path::new(base).join(sub).join(pkg);
            if !path.is_dir(){return;}
            let key=(pkg.to_string(),entry.to_string());
            let cur=lsize.get(&key).cloned().unwrap_or_default();
            // Same small-data rule as tools.sh when a trustworthy size is available.
            // A missing/invalid prescan row is kept conservatively because Backup_data()
            // can fall back to calc_dir_size(); uncertainty must delay release, never make
            // it happen before a later local read.
            if !cur.is_empty() && cur.chars().all(|c|c.is_ascii_digit()) && cur.len()<4{return;}
            let reason=if cur.is_empty(){"local_size_missing"}
                else if cur.chars().all(|c|c.is_ascii_digit()){"local_entry_possible"}
                else{"local_size_uncertain"};
            let _=writeln!(out,"{}\t{}\t{}\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),entry,reason,cur);
            rows=rows.wrapping_add(1);
        };
        if backup_obb=="true"{
            add_entry("data",android_root,"data");
            add_entry("obb",android_root,"obb");
            add_entry("media",android_root,"media");
        }
        if backup_user=="true"{
            add_entry("user",user_root,"");
            add_entry("user_de",user_de_root,"");
        }
    }
    0
}


fn cmd_remote_stream_local_read_plan_v2(args:&[String])->i32{
    if args.len()<9{return 2;}
    let selected=&args[2]; let dirsizes=&args[3]; let exists=&args[4]; let out_s=&args[5];
    let backup_mode=&args[6]; let backup_obb=&args[7]; let backup_user=&args[8];
    let sel=read_tsv_rows(selected); let mut out=match File::create(out_s){Ok(v)=>v,Err(_)=>return 4};
    let mut lsize:HashMap<(String,String),String>=HashMap::new();
    for r in read_tsv_rows(dirsizes){if r.len()>=3{lsize.insert((r[0].clone(),r[1].clone()),r[2].clone());}}
    let mut dexists:HashSet<(String,String)>=HashSet::new();
    for r in read_tsv_rows(exists){if r.len()>=2 && !r[0].is_empty() && !r[1].is_empty(){dexists.insert((r[0].clone(),r[1].clone()));}}
    for r in sel.iter(){
        if r.len()<3{continue;}
        let app=&r[0]; let pkg=&r[1]; let nodata=r[2].as_str()=="1";
        if backup_mode!="true" || nodata || pkg=="bin.mt.plus"{continue;}
        let mut add_entry=|entry:&str|{
            let key=(pkg.to_string(),entry.to_string());
            if !dexists.contains(&key){return;}
            let cur=lsize.get(&key).cloned().unwrap_or_default();
            if !cur.is_empty() && cur.chars().all(|c|c.is_ascii_digit()) && cur.len()<4{return;}
            let reason=if cur.is_empty(){"local_size_missing"}
                else if cur.chars().all(|c|c.is_ascii_digit()){"local_entry_possible"}
                else{"local_size_uncertain"};
            let _=writeln!(out,"{}\t{}\t{}\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),entry,reason,cur);
        };
        if backup_obb=="true"{add_entry("data");add_entry("obb");add_entry("media");}
        if backup_user=="true"{add_entry("user");add_entry("user_de");}
    }
    0
}


fn cmd_remote_stream_local_read_final_plan(args:&[String])->i32{
    if args.len()<12{return 2;}
    let selected=&args[2]; let dirsizes=&args[3]; let exists=&args[4]; let summary=&args[5]; let payloadset=&args[6];
    let out_s=&args[7]; let stats_s=&args[8]; let backup_mode=&args[9]; let backup_obb=&args[10]; let backup_user=&args[11];
    let sel=read_tsv_rows(selected);
    let mut lsize:HashMap<(String,String),String>=HashMap::new();
    for r in read_tsv_rows(dirsizes){if r.len()>=3{lsize.insert((r[0].clone(),r[1].clone()),r[2].clone());}}
    let mut dexists:HashSet<(String,String)>=HashSet::new();
    for r in read_tsv_rows(exists){if r.len()>=2 && !r[0].is_empty() && !r[1].is_empty(){dexists.insert((r[0].clone(),r[1].clone()));}}
    let mut rsize:HashMap<(String,String),String>=HashMap::new();
    for r in read_tsv_rows(summary){
        if r.len()>=8{
            let app=r[0].clone();
            rsize.insert((app.to_string(),"user".into()),r[3].clone());
            rsize.insert((app.to_string(),"user_de".into()),r[4].clone());
            rsize.insert((app.to_string(),"data".into()),r[5].clone());
            rsize.insert((app.to_string(),"obb".into()),r[6].clone());
            rsize.insert((app.to_string(),"media".into()),r[7].clone());
        }
    }
    let payload:HashSet<String>=read_tsv_rows(payloadset).into_iter().filter_map(|r|r.get(0).cloned()).collect();
    let mut out=match File::create(out_s){Ok(v)=>v,Err(_)=>return 4};
    let mut stats=match File::create(stats_s){Ok(v)=>v,Err(_)=>return 4};
    let mut actual_entries=0u64; let mut final_apps=0u64; let mut skipped_unchanged=0u64; let mut skipped_small=0u64;
    let mut payload_missing=0u64; let mut remote_size_missing=0u64; let mut local_size_uncertain=0u64; let mut size_mismatch=0u64;
    for r in sel.iter(){
        if r.len()<3{continue;}
        let app=&r[0]; let pkg=&r[1]; let nodata=r[2].as_str()=="1";
        if backup_mode!="true" || nodata || pkg=="bin.mt.plus"{continue;}
        let mut final_row:Option<(String,String,String,String)>=None;
        let mut consider=|entry:&str|{
            let key=(pkg.to_string(),entry.to_string());
            if !dexists.contains(&key){return;}
            let cur=lsize.get(&key).cloned().unwrap_or_default();
            // Preserve r602/r650 small-entry semantics exactly: a trustworthy 0..999-byte
            // current size cannot justify holding app guards for a later local read.
            if !cur.is_empty() && cur.chars().all(|c|c.is_ascii_digit()) && cur.len()<4{skipped_small=skipped_small.wrapping_add(1);return;}
            let old=rsize.get(&(app.to_string(),entry.to_string())).cloned().unwrap_or_default();
            let payload_ok=payload.contains(&format!("{}/{}.tar.zst",app,entry)) || payload.contains(&format!("{}/{}.tar",app,entry));
            let cur_valid=!cur.is_empty() && cur.chars().all(|c|c.is_ascii_digit());
            let unchanged=cur_valid && !old.is_empty() && old!="null" && old.as_str()==cur.as_str() && payload_ok;
            if unchanged{skipped_unchanged=skipped_unchanged.wrapping_add(1);return;}
            let reason=if !payload_ok{payload_missing=payload_missing.wrapping_add(1);"remote_payload_missing"}
                else if old.is_empty() || old=="null"{remote_size_missing=remote_size_missing.wrapping_add(1);"remote_size_missing"}
                else if !cur_valid{local_size_uncertain=local_size_uncertain.wrapping_add(1);"local_size_uncertain"}
                else{size_mismatch=size_mismatch.wrapping_add(1);"size_mismatch"};
            actual_entries=actual_entries.wrapping_add(1);
            // Only the last actual local-read entry matters to tools.sh release arming.
            // Emitting one row per app avoids rebuilding a 200+ row shell cache.
            final_row=Some((entry.to_string(),reason.to_string(),cur,old));
        };
        if backup_obb=="true"{consider("data");consider("obb");consider("media");}
        if backup_user=="true"{consider("user");consider("user_de");}
        if let Some((entry,reason,cur,old))=final_row{
            let _=writeln!(out,"{}\t{}\t{}\t{}\t{}\t{}",tsv_sanitize(app),tsv_sanitize(pkg),entry,reason,cur,old);
            final_apps=final_apps.wrapping_add(1);
        }
    }
    let _=writeln!(stats,"{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",sel.len(),actual_entries,final_apps,skipped_unchanged,skipped_small,payload_missing,remote_size_missing,local_size_uncertain,size_mismatch);
    println!("REMOTE_STREAM_LOCAL_READ_FINAL_PLAN selected={} actualEntries={} finalApps={} skippedUnchanged={} skippedSmall={} payloadMissing={} remoteSizeMissing={} localSizeUncertain={} sizeMismatch={} mode=r669 schema=speedscan.remote_stream_local_read_final_plan.v1",sel.len(),actual_entries,final_apps,skipped_unchanged,skipped_small,payload_missing,remote_size_missing,local_size_uncertain,size_mismatch);
    0
}

#[derive(Clone, Debug)]
struct StreamPerfContext {
    rb: String,
    comp: String,
    rc: String,
    origin: String,
    tar_ms: String,
    zstd_ms: String,
    source_path: String,
    pkg: String,
    label: String,
    entry: String,
}

#[derive(Default, Clone, Debug)]
struct WebDavPerfRs {
    body_ms: Option<u64>,
    done_ms: Option<u64>,
    sent: String,
    speed: String,
    http: String,
    tag: String,
    server: String,
    rc: String,
}

fn stream_log_kv(s: &str) -> String {
    let mut out = String::new();
    for ch in s.chars().take(700) {
        match ch {
            '\t' | '\n' | '\r' | ' ' => out.push('_'),
            '=' => out.push_str("％3D"),
            _ => out.push(ch),
        }
    }
    out
}

fn stream_default_entry(rb: &str) -> String {
    let tail = rb.rsplit('/').next().unwrap_or(rb);
    tail.trim_end_matches(".tar.zst").trim_end_matches(".tar").to_string()
}

fn stream_archive_tail(rb: &str, comp: &str) -> String {
    if rb.ends_with(".tar") || rb.ends_with(".tar.zst") {
        rb.to_string()
    } else if comp.eq_ignore_ascii_case("tar") {
        format!("{}.tar", rb)
    } else {
        format!("{}.tar.zst", rb)
    }
}

fn stream_rel_matches(rel: &str, rb: &str, tail: &str) -> bool {
    rel == rb || rel == tail || rel.ends_with(tail)
}

fn stream_kv(line: &str, key: &str) -> String {
    for part in line.split_whitespace() {
        if let Some((k, v)) = part.split_once('=') {
            if k == key { return v.to_string(); }
        }
    }
    String::new()
}

fn stream_is_uint(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit())
}

fn stream_parse_u64(s: &str) -> Option<u64> {
    if stream_is_uint(s) { s.parse::<u64>().ok() } else { None }
}

fn stream_ratio(sent: &str, origin: &str) -> String {
    let s = match stream_parse_u64(sent) { Some(v) if v > 0 => v, _ => return "na".to_string() };
    let o = match stream_parse_u64(origin) { Some(v) if v > 0 => v, _ => return "na".to_string() };
    format!("{:.4}", (s as f64) / (o as f64))
}

fn read_stream_child_perf(perf: &str) -> (String, String) {
    let mut tar_ms = "na".to_string();
    let mut zstd_ms = "na".to_string();
    if perf.is_empty() || perf == "-" { return (tar_ms, zstd_ms); }
    let f = match File::open(perf) { Ok(v) => v, Err(_) => return (tar_ms, zstd_ms) };
    let mut br = BufReader::new(f);
    let mut buf = Vec::new();
    while let Some(line) = next_c_line_lossy(&mut br, &mut buf) {
        let cols: Vec<&str> = line.split('\t').collect();
        if cols.len() >= 7 && cols[0] == "child" {
            // tools.sh writes: child<TAB>cmd<TAB>tag<TAB>startMs<TAB>endMs<TAB>elapsedMs<TAB>rc
            // r590 accidentally read column 4 (endMs), producing epoch-like tarWallMs/zstdWallMs.
            // Use column 5, the actual elapsed wall time, while preserving the existing output schema.
            if cols[1] == "tar" { tar_ms = cols[5].to_string(); }
            if cols[1] == "zstd" { zstd_ms = cols[5].to_string(); }
        }
    }
    (tar_ms, zstd_ms)
}

fn stream_context_from_row(cols: &[String]) -> Option<StreamPerfContext> {
    if cols.len() < 10 { return None; }
    Some(StreamPerfContext {
        rb: cols[0].clone(),
        comp: cols[1].clone(),
        rc: cols[2].clone(),
        origin: cols[3].clone(),
        tar_ms: cols[4].clone(),
        zstd_ms: cols[5].clone(),
        source_path: cols[6].clone(),
        pkg: cols[7].clone(),
        label: cols[8].clone(),
        entry: cols[9].clone(),
    })
}

fn stream_context_row(ctx: &StreamPerfContext) -> String {
    format!("{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
        tsv_sanitize(&ctx.rb), tsv_sanitize(&ctx.comp), tsv_sanitize(&ctx.rc), tsv_sanitize(&ctx.origin),
        tsv_sanitize(&ctx.tar_ms), tsv_sanitize(&ctx.zstd_ms), tsv_sanitize(&ctx.source_path),
        tsv_sanitize(&ctx.pkg), tsv_sanitize(&ctx.label), tsv_sanitize(&ctx.entry))
}

fn load_webdav_perf(info: &str, rb: &str, comp: &str, rc: &str) -> Option<WebDavPerfRs> {
    if info.is_empty() || info == "-" { return None; }
    let f = File::open(info).ok()?;
    let tail = stream_archive_tail(rb, comp);
    let mut perf = WebDavPerfRs { rc: rc.to_string(), ..WebDavPerfRs::default() };
    let mut br = BufReader::new(f);
    let mut buf = Vec::new();
    while let Some(line) = next_c_line_lossy(&mut br, &mut buf) {
        if !(line.starts_with("WEBDAV_STREAM_BODY_DONE ") || line.starts_with("WEBDAV_STREAM_DONE ") || line.starts_with("WEBDAV_STREAM_FAIL ")) { continue; }
        let rel = stream_kv(&line, "rel");
        if !stream_rel_matches(&rel, rb, &tail) { continue; }
        if line.starts_with("WEBDAV_STREAM_BODY_DONE ") {
            perf.body_ms = stream_parse_u64(&stream_kv(&line, "elapsedMs"));
            perf.sent = stream_kv(&line, "sentBytes");
            let server = stream_kv(&line, "server");
            if !server.is_empty() { perf.server = server; }
            let tag = stream_kv(&line, "tag");
            if !tag.is_empty() { perf.tag = tag; }
        } else if line.starts_with("WEBDAV_STREAM_DONE ") || line.starts_with("WEBDAV_STREAM_FAIL ") {
            perf.done_ms = stream_parse_u64(&stream_kv(&line, "elapsedMs"));
            perf.speed = stream_kv(&line, "speedKiBps");
            perf.http = stream_kv(&line, "http");
            let server = stream_kv(&line, "server");
            if !server.is_empty() { perf.server = server; }
            let tag = stream_kv(&line, "tag");
            if !tag.is_empty() { perf.tag = tag; }
        }
    }
    if perf.body_ms.is_some() && perf.done_ms.is_some() { Some(perf) } else { None }
}

fn emit_stream_entry_perf(ctx: &StreamPerfContext, info: Option<WebDavPerfRs>, resolved: &str) -> bool {
    let mut entry = ctx.entry.clone();
    if entry.is_empty() { entry = stream_default_entry(&ctx.rb); }
    match info {
        Some(w) => {
            let body = w.body_ms.unwrap_or(0);
            let done = w.done_ms.unwrap_or(body);
            let post_body = done.saturating_sub(body);
            let sent = if w.sent.is_empty() { "0".to_string() } else { w.sent };
            let speed = if w.speed.is_empty() { "0".to_string() } else { w.speed };
            let http = if w.http.is_empty() { "0".to_string() } else { w.http };
            let tag = if w.tag.is_empty() { "na".to_string() } else { w.tag };
            let ratio = stream_ratio(&sent, &ctx.origin);
            let server = if w.server.is_empty() { "unknown".to_string() } else { w.server };
            let remote_success = match http.parse::<u16>() { Ok(v) if (200..=299).contains(&v) => "1", _ => "0" };
            let response_confirmed = match http.parse::<u16>() { Ok(v) if v > 0 => "1", _ => "0" };
            println!("STREAM_ENTRY_PERF app={} package={} entry={} sourcePath={} originBytes={} sentBytes={} compressionRatio={} bodyMs={} postBodyMs={} postBodySemantics=server_processing_plus_optional_publish_until_terminal_result remoteSuccess={} responseConfirmed={} successRule=http_2xx_only server={} tarWallMs={} zstdWallMs={} wireKiBps={} http={} dexTag={} dexRc={} pipelineRc={} comp={} archiveRel={} mode=r600 overlap=1 resolved={} resolver=rust",
                stream_log_kv(&ctx.label), stream_log_kv(&ctx.pkg), stream_log_kv(&entry), stream_log_kv(&ctx.source_path),
                ctx.origin, sent, ratio, body, post_body, remote_success, response_confirmed, stream_log_kv(&server), ctx.tar_ms, ctx.zstd_ms, speed, http, stream_log_kv(&tag), stream_log_kv(&w.rc), ctx.rc, stream_log_kv(&ctx.comp), stream_log_kv(&ctx.rb), resolved);
            true
        }
        None => {
            println!("STREAM_ENTRY_PERF_UNRESOLVED app={} package={} entry={} sourcePath={} originBytes={} tarWallMs={} zstdWallMs={} pipelineRc={} comp={} archiveRel={} reason=webdav_info_not_found mode=r600 resolver=rust",
                stream_log_kv(&ctx.label), stream_log_kv(&ctx.pkg), stream_log_kv(&entry), stream_log_kv(&ctx.source_path),
                ctx.origin, ctx.tar_ms, ctx.zstd_ms, ctx.rc, stream_log_kv(&ctx.comp), stream_log_kv(&ctx.rb));
            false
        }
    }
}

fn cmd_stream_entry_perf_stage(args: &[String]) -> i32 {
    if args.len() < 13 { return 2; }
    let perf = &args[2];
    let pending = &args[3];
    let remote_type = &args[4];
    let (tar_ms, zstd_ms) = read_stream_child_perf(perf);
    let mut entry = args.get(12).cloned().unwrap_or_default();
    if entry.is_empty() { entry = stream_default_entry(&args[5]); }
    let ctx = StreamPerfContext {
        rb: args[5].clone(),
        comp: args[6].clone(),
        rc: args[7].clone(),
        origin: args[8].clone(),
        tar_ms,
        zstd_ms,
        source_path: args[9].clone(),
        pkg: args[10].clone(),
        label: args[11].clone(),
        entry,
    };
    if remote_type == "webdav" {
        let mut out = match OpenOptions::new().create(true).append(true).open(pending) {
            Ok(v) => v,
            Err(e) => { eprintln!("speedscan: stream-entry-perf-stage pending open failed: {}: {}", pending, c_strerror(&e)); return 4; }
        };
        let _ = writeln!(out, "{}", stream_context_row(&ctx));
        println!("STREAM_ENTRY_PERF_PENDING app={} package={} entry={} archiveRel={} reason=defer_until_webdav_daemon_flush mode=r600 resolver=rust",
            stream_log_kv(&ctx.label), stream_log_kv(&ctx.pkg), stream_log_kv(&ctx.entry), stream_log_kv(&ctx.rb));
    } else {
        println!("STREAM_ENTRY_PERF app={} package={} entry={} sourcePath={} originBytes={} sentBytes=0 compressionRatio=na bodyMs=na postBodyMs=na postBodySemantics=not_webdav remoteSuccess=not_applicable responseConfirmed=not_applicable successRule=not_applicable tarWallMs={} zstdWallMs={} wireKiBps=0 http=0 dexTag=na dexRc=na pipelineRc={} comp={} archiveRel={} mode=r600 overlap=1 resolved=non_webdav resolver=rust",
            stream_log_kv(&ctx.label), stream_log_kv(&ctx.pkg), stream_log_kv(&ctx.entry), stream_log_kv(&ctx.source_path),
            ctx.origin, ctx.tar_ms, ctx.zstd_ms, ctx.rc, stream_log_kv(&ctx.comp), stream_log_kv(&ctx.rb));
    }
    0
}

fn cmd_stream_entry_perf_finalize(args: &[String]) -> i32 {
    if args.len() < 4 { return 2; }
    let pending = &args[2];
    let info = &args[3];
    let rows = read_tsv_rows(pending);
    let mut count = 0u64;
    let mut resolved = 0u64;
    for row in rows {
        let ctx = match stream_context_from_row(&row) { Some(v) => v, None => continue };
        count = count.wrapping_add(1);
        let w = load_webdav_perf(info, &ctx.rb, &ctx.comp, &ctx.rc);
        if emit_stream_entry_perf(&ctx, w, "final-flush") { resolved = resolved.wrapping_add(1); }
    }
    println!("STREAM_ENTRY_PERF_FINAL_FLUSH_DONE count={} resolved={} mode=r600 resolver=rust schema=speedbackup.stream_entry_perf_resolver.v1 semantics=post_body", count, resolved);
    0
}


fn read_first_trimmed(path_s: &str) -> String {
    if path_s.is_empty() || path_s == "-" { return String::new(); }
    match fs::read_to_string(path_s) {
        Ok(s) => s.lines().next().unwrap_or("").trim().to_string(),
        Err(_) => String::new(),
    }
}

fn load_line_set(path_s: &str) -> HashSet<String> {
    let mut out = HashSet::new();
    if path_s.is_empty() || path_s == "-" { return out; }
    if let Ok(lines) = read_lines(Path::new(path_s)) {
        for mut line in lines {
            while line.ends_with('\r') { line.pop(); }
            let v = line.trim();
            if !v.is_empty() { out.insert(v.to_string()); }
        }
    }
    out
}

fn appdetails_is_payload_tail(name: &str) -> bool {
    matches!(name,
        "apk.tar"|"apk.tar.zst"|"data.tar"|"data.tar.zst"|"user.tar"|"user.tar.zst"|
        "user_de.tar"|"user_de.tar.zst"|"obb.tar"|"obb.tar.zst"|"media.tar"|"media.tar.zst"|
        "thanox.tar"|"thanox.tar.zst"|"hma.tar"|"hma.tar.zst")
}

fn appdetails_remote_payload_apps(remote_files: &str) -> Option<(HashSet<String>, HashSet<String>)> {
    if remote_files.is_empty() || remote_files == "-" || !Path::new(remote_files).exists() { return None; }
    let mut apps = HashSet::new();
    let mut rels = HashSet::new();
    for mut line in read_lines(Path::new(remote_files)).unwrap_or_default() {
        while line.ends_with('\r') { line.pop(); }
        let p = line.trim();
        if p.is_empty() || !p.contains('/') { continue; }
        rels.insert(p.to_string());
        let mut it = p.split('/');
        let app = match it.next() { Some(v) => v, None => continue };
        let tail = match p.rsplit('/').next() { Some(v) => v, None => continue };
        if app.is_empty() || app == "." || app == ".." || app == "Media" || app == "wifi" || app == "tools" { continue; }
        if appdetails_is_payload_tail(tail) { apps.insert(app.to_string()); }
    }
    Some((apps, rels))
}

fn appdetails_stage_apps(root: &str) -> HashSet<String> {
    let mut out = HashSet::new();
    if root.is_empty() { return out; }
    let manifest = Path::new(root).join("manifest.tsv");
    if manifest.exists() {
        for row in read_tsv_rows(manifest.to_string_lossy().as_ref()) {
            if let Some(app) = row.get(0) { if !app.is_empty() { out.insert(app.clone()); } }
        }
        return out;
    }
    let rd = match fs::read_dir(root) { Ok(v) => v, Err(_) => return out };
    for e in rd.flatten() {
        let p = e.path();
        if !p.is_dir() { continue; }
        if p.join("app_details.json").is_file() {
            if let Some(n) = p.file_name() { out.insert(n.to_string_lossy().into_owned()); }
        }
    }
    out
}

fn write_set_file(path_s: &str, values: &HashSet<String>) {
    if path_s.is_empty() { return; }
    if let Ok(mut f) = File::create(path_s) {
        let mut v: Vec<String> = values.iter().cloned().collect();
        v.sort();
        for x in v { let _ = writeln!(f, "{}", tsv_sanitize(&x)); }
    }
}

fn set_missing(wanted: &HashSet<String>, known: &HashSet<String>) -> Vec<String> {
    let mut v: Vec<String> = wanted.iter().filter(|x| !known.contains(*x)).cloned().collect();
    v.sort();
    v
}

fn write_vec_file(path_s: &str, values: &[String]) {
    if path_s.is_empty() { return; }
    if let Ok(mut f) = File::create(path_s) {
        for x in values { let _ = writeln!(f, "{}", tsv_sanitize(x)); }
    }
}

fn json_string_value(body: &str, keys: &[&str]) -> Option<String> {
    for key in keys {
        let needle = format!("\"{}\"", key);
        let mut pos = 0usize;
        while let Some(rel) = body[pos..].find(&needle) {
            let kpos = pos + rel + needle.len();
            let rest = &body[kpos..];
            let cpos = match rest.find(':') { Some(v) => v, None => { pos = kpos; continue } };
            let mut i = kpos + cpos + 1;
            let b = body.as_bytes();
            while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
            if i >= b.len() || b[i] != b'\"' { pos = i; continue; }
            i += 1;
            let start = i;
            let mut esc = false;
            while i < b.len() {
                if esc { esc = false; i += 1; continue; }
                if b[i] == b'\\' { esc = true; i += 1; continue; }
                if b[i] == b'\"' { return Some(body[start..i].to_string()); }
                i += 1;
            }
            pos = kpos;
        }
    }
    None
}




fn json_find_object_after_key(body: &str, key: &str) -> Option<(usize, usize)> {
    let needle = format!("\"{}\"", key);
    let mut pos = 0usize;
    let bytes = body.as_bytes();
    while let Some(rel) = body[pos..].find(&needle) {
        let kpos = pos + rel + needle.len();
        let rest = &body[kpos..];
        let cpos = match rest.find(':') { Some(v) => v, None => return None };
        let mut i = kpos + cpos + 1;
        while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
        if i >= bytes.len() || bytes[i] != b'{' { pos = kpos; continue; }
        let start = i;
        let mut depth = 0i32;
        let mut in_str = false;
        let mut esc = false;
        while i < bytes.len() {
            let c = bytes[i];
            if in_str {
                if esc { esc = false; }
                else if c == b'\\' { esc = true; }
                else if c == b'\"' { in_str = false; }
            } else if c == b'\"' { in_str = true; }
            else if c == b'{' { depth += 1; }
            else if c == b'}' {
                depth -= 1;
                if depth == 0 { return Some((start, i + 1)); }
            }
            i += 1;
        }
        return None;
    }
    None
}

fn json_compact_no_ws(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_str = false;
    let mut esc = false;
    for ch in s.chars() {
        if in_str {
            out.push(ch);
            if esc { esc = false; }
            else if ch == '\\' { esc = true; }
            else if ch == '"' { in_str = false; }
        } else if ch == '"' {
            in_str = true;
            out.push(ch);
        } else if !matches!(ch, ' ' | '\t' | '\r' | '\n') {
            out.push(ch);
        }
    }
    out
}


fn json_value_range_at(body: &str, mut i: usize) -> Option<(usize, usize)> {
    let b = body.as_bytes();
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
    if i >= b.len() { return None; }
    match b[i] {
        b'"' => {
            let start = i;
            i += 1;
            let mut esc = false;
            while i < b.len() {
                if esc { esc = false; }
                else if b[i] == b'\\' { esc = true; }
                else if b[i] == b'"' { return Some((start, i + 1)); }
                i += 1;
            }
            None
        }
        b'{' | b'[' => {
            let start = i;
            let open = b[i];
            let close = if open == b'{' { b'}' } else { b']' };
            let mut depth = 0i32;
            let mut in_str = false;
            let mut esc = false;
            while i < b.len() {
                let c = b[i];
                if in_str {
                    if esc { esc = false; }
                    else if c == b'\\' { esc = true; }
                    else if c == b'"' { in_str = false; }
                } else if c == b'"' { in_str = true; }
                else if c == open { depth += 1; }
                else if c == close {
                    depth -= 1;
                    if depth == 0 { return Some((start, i + 1)); }
                }
                i += 1;
            }
            None
        }
        _ => {
            let start = i;
            while i < b.len() && !matches!(b[i], b',' | b'}' | b']' | b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
            if i > start { Some((start, i)) } else { None }
        }
    }
}

fn json_find_value_after_key(body: &str, key: &str) -> Option<(usize, usize)> {
    let needle = format!("\"{}\"", key);
    let mut pos = 0usize;
    while pos < body.len() {
        let rel = body[pos..].find(&needle)?;
        let kpos = pos + rel + needle.len();
        let rest = &body[kpos..];
        let cpos = match rest.find(':') { Some(v) => v, None => return None };
        let start = kpos + cpos + 1;
        if let Some(r) = json_value_range_at(body, start) { return Some(r); }
        pos = kpos;
    }
    None
}

fn json_raw_value_after_key(body: &str, key: &str) -> Option<String> {
    let (s, e) = json_find_value_after_key(body, key)?;
    Some(json_compact_no_ws(&body[s..e]))
}

fn json_array_items_raw(array_raw: &str) -> Vec<String> {
    let mut out = Vec::new();
    let b = array_raw.as_bytes();
    if b.first() != Some(&b'[') { return out; }
    let mut i = 1usize;
    loop {
        while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n' | b',') { i += 1; }
        if i >= b.len() || b[i] == b']' { break; }
        match json_value_range_at(array_raw, i) {
            Some((s, e)) => { out.push(json_compact_no_ws(&array_raw[s..e])); i = e; }
            None => break,
        }
    }
    out
}

fn json_object_entries_raw(obj_raw: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let b = obj_raw.as_bytes();
    if b.first() != Some(&b'{') { return out; }
    let mut i = 1usize;
    loop {
        while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n' | b',') { i += 1; }
        if i >= b.len() || b[i] == b'}' { break; }
        if b[i] != b'"' { break; }
        let key_start = i;
        i += 1;
        let mut esc = false;
        while i < b.len() {
            if esc { esc = false; }
            else if b[i] == b'\\' { esc = true; }
            else if b[i] == b'"' { break; }
            i += 1;
        }
        if i >= b.len() { break; }
        let key_raw = json_compact_no_ws(&obj_raw[key_start..i + 1]);
        i += 1;
        while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
        if i >= b.len() || b[i] != b':' { break; }
        i += 1;
        match json_value_range_at(obj_raw, i) {
            Some((s, e)) => { out.push((key_raw, json_compact_no_ws(&obj_raw[s..e]))); i = e; }
            None => break,
        }
    }
    out
}

fn json_object_ordered_pick(obj: &str, keys: &[&str]) -> String {
    let mut fields: Vec<String> = Vec::new();
    for k in keys {
        if let Some(v) = json_raw_value_after_key(obj, k) {
            if v != "null" { fields.push(format!("\"{}\":{}", k, v)); }
        }
    }
    format!("{{{}}}", fields.join(","))
}

fn appstate_compact_permission(obj: &str) -> String {
    json_object_ordered_pick(obj, &["name", "nameCn", "granted", "flags", "runtime", "development", "appOp", "appOpName", "appOpNameCn", "packageMode", "uidMode", "scope", "appOpMode", "appOpModeName", "appOpModeCn"])
}

fn appstate_compact_special(obj: &str) -> String {
    json_object_ordered_pick(obj, &["keyCn", "publicName", "publicNameCn", "manifestPermission", "manifestPermissionCn", "requested", "supported", "op", "packageMode", "uidMode", "scope", "mode", "modeName", "modeCn"])
}

fn appstate_compact_opobj(obj: &str) -> String {
    json_object_ordered_pick(obj, &["op", "publicName", "publicNameCn", "supported", "packageMode", "uidMode", "scope", "mode", "modeName", "modeCn"])
}

fn appstate_compact_array_objects(array_raw: &str, kind: &str) -> String {
    let mut items = Vec::new();
    for item in json_array_items_raw(array_raw) {
        if item.starts_with('{') {
            let c = match kind {
                "perm" => appstate_compact_permission(&item),
                "op" => appstate_compact_opobj(&item),
                _ => json_compact_no_ws(&item),
            };
            items.push(c);
        } else {
            items.push(json_compact_no_ws(&item));
        }
    }
    format!("[{}]", items.join(","))
}

fn appstate_compact_object_values(obj_raw: &str, kind: &str) -> String {
    let mut fields = Vec::new();
    for (key, val) in json_object_entries_raw(obj_raw) {
        let cv = if val.starts_with('{') {
            match kind {
                "special" => appstate_compact_special(&val),
                "op" => appstate_compact_opobj(&val),
                _ => json_compact_no_ws(&val),
            }
        } else if kind == "special" {
            "{}".to_string()
        } else {
            json_compact_no_ws(&val)
        };
        fields.push(format!("{}:{}", key, cv));
    }
    format!("{{{}}}", fields.join(","))
}

#[derive(Clone, Debug)]
struct AppStateMatchCanon {
    profile_no_ssaid: String,
    ssaid: String,
}

fn appstate_ssaid_for_match(s: &str) -> String {
    match json_raw_value_after_key(s, "ssaid") {
        Some(v) => {
            let c = json_compact_no_ws(&v);
            if c == "null" || c == "\"\"" { String::new() } else { c }
        },
        None => String::new(),
    }
}

fn appstate_compact_profile(s: &str) -> Option<AppStateMatchCanon> {
    if !appstate_persistable_obj(s) { return None; }
    let schema = json_raw_value_after_key(s, "schemaVersion").unwrap_or_else(|| "2".to_string());
    let record_type = json_raw_value_after_key(s, "recordType").unwrap_or_else(|| "\"snapshot\"".to_string());
    let user_id = json_raw_value_after_key(s, "userId").unwrap_or_else(|| "0".to_string());
    let package_name = json_raw_value_after_key(s, "packageName").unwrap_or_else(|| "null".to_string());
    // r642 canonical v4:
    // - installer/source attribution remains excluded from data fast-skip equality.
    // - SSAID is compared with preserve-old semantics: when the current snapshot cannot read
    //   SSAID and reports null, an existing backed-up non-null SSAID must not cause an
    //   infinite appstate_mismatch loop.  If current SSAID is readable and differs, it still
    //   forces a metadata refresh.
    let permissions = match json_raw_value_after_key(s, "permissions") {
        Some(v) if v.starts_with('[') => appstate_compact_array_objects(&v, "perm"),
        _ => "[]".to_string(),
    };
    let special_access = match json_raw_value_after_key(s, "specialAccess") {
        Some(v) if v.starts_with('{') => appstate_compact_object_values(&v, "special"),
        _ => "{}".to_string(),
    };
    let battery_settings = match json_raw_value_after_key(s, "batterySettings") {
        Some(v) if v.starts_with('{') => appstate_compact_object_values(&v, "op"),
        _ => "{}".to_string(),
    };
    let other_app_ops = match json_raw_value_after_key(s, "otherAppOps") {
        Some(v) if v.starts_with('[') => appstate_compact_array_objects(&v, "op"),
        _ => "[]".to_string(),
    };
    let profile_no_ssaid = format!("{{\"schemaVersion\":{},\"recordType\":{},\"userId\":{},\"packageName\":{},\"permissions\":{},\"specialAccess\":{},\"batterySettings\":{},\"otherAppOps\":{}}}",
        schema, record_type, user_id, package_name, permissions, special_access, battery_settings, other_app_ops);
    Some(AppStateMatchCanon { profile_no_ssaid, ssaid: appstate_ssaid_for_match(s) })
}

fn appstate_ssaid_match_for_fastskip(old_ssaid: &str, cur_ssaid: &str) -> bool {
    if cur_ssaid.is_empty() {
        true
    } else if old_ssaid.is_empty() {
        false
    } else {
        old_ssaid == cur_ssaid
    }
}

fn json_key_value_starts_with(obj: &str, key: &str, want: u8) -> bool {
    let needle = format!("\"{}\"", key);
    let bytes = obj.as_bytes();
    let pos = 0usize;
    while let Some(rel) = obj[pos..].find(&needle) {
        let kpos = pos + rel + needle.len();
        let rest = &obj[kpos..];
        let cpos = match rest.find(':') { Some(v) => v, None => return false };
        let mut i = kpos + cpos + 1;
        while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
        return i < bytes.len() && bytes[i] == want;
    }
    false
}

fn json_number_value_equals(obj: &str, key: &str, val: &str) -> bool {
    let needle = format!("\"{}\"", key);
    let bytes = obj.as_bytes();
    let pos = 0usize;
    while let Some(rel) = obj[pos..].find(&needle) {
        let kpos = pos + rel + needle.len();
        let rest = &obj[kpos..];
        let cpos = match rest.find(':') { Some(v) => v, None => return false };
        let mut i = kpos + cpos + 1;
        while i < bytes.len() && matches!(bytes[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
        let start = i;
        while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
        return i > start && &obj[start..i] == val;
    }
    false
}

fn appstate_persistable_obj(obj: &str) -> bool {
    json_string_value(obj, &["recordType"]).map(|s| s == "snapshot").unwrap_or(false)
        && json_number_value_equals(obj, "schemaVersion", "2")
        && json_string_value(obj, &["packageName"]).map(|s| !s.is_empty()).unwrap_or(false)
        && json_key_value_starts_with(obj, "permissions", b'[')
        && json_key_value_starts_with(obj, "specialAccess", b'{')
        && json_key_value_starts_with(obj, "otherAppOps", b'[')
        && json_key_value_starts_with(obj, "batterySettings", b'{')
}

fn appstate_obj_from_appdetails(body: &str) -> Option<String> {
    let (s, e) = json_find_object_after_key(body, "app_state")?;
    Some(body[s..e].to_string())
}

fn appstate_persistable_from_appdetails(body: &str) -> bool {
    match appstate_obj_from_appdetails(body) {
        Some(obj) => appstate_persistable_obj(&obj),
        None => false,
    }
}

fn json_size_in_object(obj: &str) -> Option<String> {
    for key in ["Size", "size"] {
        let needle = format!("\"{}\"", key);
        let k = match obj.find(&needle) { Some(v) => v + needle.len(), None => continue };
        let rest = &obj[k..];
        let cpos = match rest.find(':') { Some(v) => v, None => continue };
        let mut i = k + cpos + 1;
        let b = obj.as_bytes();
        while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
        if i >= b.len() { continue; }
        if b[i] == b'\"' {
            i += 1;
            let start = i;
            while i < b.len() && b[i].is_ascii_digit() { i += 1; }
            if i > start { return Some(obj[start..i].to_string()); }
        } else {
            let start = i;
            while i < b.len() && b[i].is_ascii_digit() { i += 1; }
            if i > start { return Some(obj[start..i].to_string()); }
        }
    }
    None
}

fn appdetails_entry_size(body: &str, entry: &str) -> Option<String> {
    let (s, e) = json_find_object_after_key(body, entry)?;
    json_size_in_object(&body[s..e])
}

fn json_skip_ws_bytes(b: &[u8], mut i: usize) -> usize {
    while i < b.len() && matches!(b[i], b' ' | b'\t' | b'\r' | b'\n') { i += 1; }
    i
}

fn json_parse_string_end_bytes(b: &[u8], mut i: usize) -> Option<usize> {
    if i >= b.len() || b[i] != b'\"' { return None; }
    i += 1;
    while i < b.len() {
        match b[i] {
            b'\"' => return Some(i + 1),
            b'\\' => {
                i += 1;
                if i >= b.len() { return None; }
                match b[i] {
                    b'\"' | b'\\' | b'/' | b'b' | b'f' | b'n' | b'r' | b't' => i += 1,
                    b'u' => {
                        i += 1;
                        for _ in 0..4 {
                            if i >= b.len() || !b[i].is_ascii_hexdigit() { return None; }
                            i += 1;
                        }
                    },
                    _ => return None,
                }
            },
            0x00..=0x1f => return None,
            _ => i += 1,
        }
    }
    None
}

fn json_parse_number_end_bytes(b: &[u8], mut i: usize) -> Option<usize> {
    if i < b.len() && b[i] == b'-' { i += 1; }
    if i >= b.len() { return None; }
    if b[i] == b'0' {
        i += 1;
    } else if b[i].is_ascii_digit() && b[i] != b'0' {
        while i < b.len() && b[i].is_ascii_digit() { i += 1; }
    } else {
        return None;
    }
    if i < b.len() && b[i] == b'.' {
        i += 1;
        let start = i;
        while i < b.len() && b[i].is_ascii_digit() { i += 1; }
        if i == start { return None; }
    }
    if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
        i += 1;
        if i < b.len() && (b[i] == b'+' || b[i] == b'-') { i += 1; }
        let start = i;
        while i < b.len() && b[i].is_ascii_digit() { i += 1; }
        if i == start { return None; }
    }
    Some(i)
}

fn json_parse_value_end_bytes(b: &[u8], mut i: usize, depth: u32) -> Option<usize> {
    if depth > 96 { return None; }
    i = json_skip_ws_bytes(b, i);
    if i >= b.len() { return None; }
    match b[i] {
        b'\"' => json_parse_string_end_bytes(b, i),
        b'{' => {
            i += 1;
            i = json_skip_ws_bytes(b, i);
            if i < b.len() && b[i] == b'}' { return Some(i + 1); }
            loop {
                i = json_skip_ws_bytes(b, i);
                i = json_parse_string_end_bytes(b, i)?;
                i = json_skip_ws_bytes(b, i);
                if i >= b.len() || b[i] != b':' { return None; }
                i += 1;
                i = json_parse_value_end_bytes(b, i, depth + 1)?;
                i = json_skip_ws_bytes(b, i);
                if i < b.len() && b[i] == b',' { i += 1; continue; }
                if i < b.len() && b[i] == b'}' { return Some(i + 1); }
                return None;
            }
        },
        b'[' => {
            i += 1;
            i = json_skip_ws_bytes(b, i);
            if i < b.len() && b[i] == b']' { return Some(i + 1); }
            loop {
                i = json_parse_value_end_bytes(b, i, depth + 1)?;
                i = json_skip_ws_bytes(b, i);
                if i < b.len() && b[i] == b',' { i += 1; continue; }
                if i < b.len() && b[i] == b']' { return Some(i + 1); }
                return None;
            }
        },
        b't' if b.get(i..i+4) == Some(&b"true"[..]) => Some(i + 4),
        b'f' if b.get(i..i+5) == Some(&b"false"[..]) => Some(i + 5),
        b'n' if b.get(i..i+4) == Some(&b"null"[..]) => Some(i + 4),
        b'-' | b'0'..=b'9' => json_parse_number_end_bytes(b, i),
        _ => None,
    }
}

fn json_document_parse_ok(body: &str) -> bool {
    let b = body.as_bytes();
    let i = json_skip_ws_bytes(b, 0);
    if i >= b.len() { return false; }
    let e = match json_parse_value_end_bytes(b, i, 0) { Some(v) => v, None => return false };
    json_skip_ws_bytes(b, e) == b.len()
}

fn json_raw_is_string(raw: &str) -> bool {
    let b = raw.as_bytes();
    match json_parse_string_end_bytes(b, 0) { Some(e) => json_skip_ws_bytes(b, e) == b.len(), None => false }
}

fn json_raw_is_number(raw: &str) -> bool {
    let b = raw.as_bytes();
    match json_parse_number_end_bytes(b, 0) { Some(e) => json_skip_ws_bytes(b, e) == b.len(), None => false }
}

fn json_raw_is_bool(raw: &str) -> bool { raw == "true" || raw == "false" }

fn json_unquote_simple(raw: &str) -> Option<String> {
    let b = raw.as_bytes();
    if b.first() != Some(&b'\"') || b.last() != Some(&b'\"') { return None; }
    let mut out = String::new();
    let mut i = 1usize;
    while i + 1 < b.len() {
        match b[i] {
            b'\"' => return None,
            b'\\' => {
                i += 1;
                if i + 1 > b.len() { return None; }
                match b[i] {
                    b'\"' => out.push('\"'),
                    b'\\' => out.push('\\'),
                    b'/' => out.push('/'),
                    b'b' => out.push('\u{0008}'),
                    b'f' => out.push('\u{000c}'),
                    b'n' => out.push('\n'),
                    b'r' => out.push('\r'),
                    b't' => out.push('\t'),
                    b'u' => {
                        if i + 4 >= b.len() { return None; }
                        let hex = std::str::from_utf8(&b[i+1..i+5]).ok()?;
                        let cp = u32::from_str_radix(hex, 16).ok()?;
                        if let Some(ch) = char::from_u32(cp) { out.push(ch); }
                        i += 4;
                    },
                    _ => return None,
                }
                i += 1;
            },
            c => { out.push(c as char); i += 1; },
        }
    }
    Some(out)
}

fn json_direct_raw(obj_raw: &str, key: &str) -> Option<String> {
    let want = format!("\"{}\"", key);
    for (k, v) in json_object_entries_raw(obj_raw) {
        if k == want { return Some(v); }
    }
    None
}

fn json_direct_has_nonnull(obj_raw: &str, key: &str) -> bool {
    json_direct_raw(obj_raw, key).map(|v| v != "null").unwrap_or(false)
}

fn json_direct_has_key(obj_raw: &str, key: &str) -> bool {
    json_direct_raw(obj_raw, key).is_some()
}

fn json_direct_string_value(obj_raw: &str, key: &str) -> Option<String> {
    json_direct_raw(obj_raw, key).and_then(|v| json_unquote_simple(&v))
}

fn json_top_object_values(body: &str) -> Vec<String> {
    let t = body.trim_start();
    if !t.starts_with('{') { return Vec::new(); }
    json_object_entries_raw(t).into_iter().map(|(_, v)| v).filter(|v| v.starts_with('{')).collect()
}

fn health_first_pkg(values: &[String]) -> String {
    for v in values {
        if json_direct_has_nonnull(v, "PackageName") {
            if let Some(pkg) = json_direct_string_value(v, "PackageName") { return pkg; }
        }
    }
    String::new()
}

fn health_first_apk_version(values: &[String]) -> String {
    for v in values {
        if json_direct_has_nonnull(v, "apk_version") {
            return match json_direct_raw(v, "apk_version") {
                Some(raw) if raw == "null" => String::new(),
                Some(raw) if raw.starts_with('\"') => json_unquote_simple(&raw).unwrap_or_default(),
                Some(raw) => raw,
                None => String::new(),
            };
        }
    }
    String::new()
}

fn health_state_objects(values: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    for v in values {
        if let Some(raw) = json_direct_raw(v, "app_state") {
            if raw != "null" { out.push(raw); }
        }
    }
    out
}

fn appstate_package_name_type_ok(st: &str) -> bool {
    match json_direct_raw(st, "packageName") {
        None => true,
        Some(v) if v == "null" => true,
        Some(v) => json_raw_is_string(&v),
    }
}

fn health_appstate_schema_ok(states: &[String]) -> bool {
    for st in states {
        if !st.starts_with('{') { return false; }
        if json_direct_raw(st, "schemaVersion").map(|v| v == "2").unwrap_or(false) != true { return false; }
        if json_direct_string_value(st, "recordType").map(|v| v == "snapshot").unwrap_or(false) != true { return false; }
        if !appstate_package_name_type_ok(st) { return false; }
        if !json_direct_raw(st, "permissions").map(|v| v.starts_with('[')).unwrap_or(false) { return false; }
        if !json_direct_raw(st, "specialAccess").map(|v| v.starts_with('{')).unwrap_or(false) { return false; }
        if !json_direct_raw(st, "otherAppOps").map(|v| v.starts_with('[')).unwrap_or(false) { return false; }
        if !json_direct_raw(st, "batterySettings").map(|v| v.starts_with('{')).unwrap_or(false) { return false; }
    }
    true
}

fn health_appstate_items_ok(states: &[String]) -> bool {
    for st in states {
        if let Some(perms) = json_direct_raw(st, "permissions") {
            for item in json_array_items_raw(&perms) {
                if !item.starts_with('{') { return false; }
                if !json_direct_raw(&item, "name").map(|v| json_raw_is_string(&v)).unwrap_or(false) { return false; }
                if !json_direct_raw(&item, "granted").map(|v| json_raw_is_bool(&v)).unwrap_or(false) { return false; }
                if !json_direct_raw(&item, "flags").map(|v| json_raw_is_number(&v)).unwrap_or(false) { return false; }
            }
        }
        if let Some(ops) = json_direct_raw(st, "otherAppOps") {
            for item in json_array_items_raw(&ops) {
                if !item.starts_with('{') { return false; }
                if !json_direct_raw(&item, "op").map(|v| json_raw_is_number(&v)).unwrap_or(false) { return false; }
                if !json_direct_raw(&item, "mode").map(|v| json_raw_is_number(&v)).unwrap_or(false) { return false; }
            }
        }
    }
    true
}

fn health_nullable_appstate_ok(states: &[String]) -> bool {
    for st in states {
        if !json_direct_has_key(st, "installer") || !json_direct_has_key(st, "ssaid") { return false; }
    }
    true
}

fn health_legacy_count(values: &[String]) -> usize {
    values.iter().filter(|v| {
        json_direct_has_nonnull(v, "permissions") ||
        json_direct_has_nonnull(v, "special_access") ||
        json_direct_has_nonnull(v, "battery_settings") ||
        json_direct_has_nonnull(v, "Ssaid")
    }).count()
}

fn appdetails_health_key_label(line: &str) -> (String, String) {
    let label = line.trim_end_matches('\r').to_string();
    let key = label.split(' ').next().unwrap_or("").to_string();
    (key, label)
}

fn cmd_appdetails_health_batch(args: &[String]) -> i32 {
    if args.len() < 5 { return 2; }
    let start = Instant::now();
    let list = Path::new(&args[2]);
    let root = Path::new(&args[3]);
    let out_prefix = &args[4];
    let suffix = args.get(5).map(|s| s.as_str()).unwrap_or("");
    let remote_mode = suffix.contains("遠端");
    if !list.is_file() || !root.is_dir() { return 3; }
    let summary_path = format!("{}.summary.tsv", out_prefix);
    let issues_path = format!("{}.issues", out_prefix);
    let hints_path = format!("{}.hints", out_prefix);
    let remote_drops_path = format!("{}.remote_drops", out_prefix);
    let stats_path = format!("{}.stats", out_prefix);
    let mut summary = match File::create(&summary_path) { Ok(v) => v, Err(_) => return 4 };
    let mut issues = match File::create(&issues_path) { Ok(v) => v, Err(_) => return 4 };
    let mut hints = match File::create(&hints_path) { Ok(v) => v, Err(_) => return 4 };
    let mut drops = match File::create(&remote_drops_path) { Ok(v) => v, Err(_) => return 4 };
    let mut total = 0u64;
    let mut ok = 0u64;
    let mut invalid = 0u64;
    let mut missing = 0u64;
    let mut hint_rows = 0u64;
    let mut issue_rows = 0u64;
    let mut summary_rows = 0u64;
    for line in read_lines(list).unwrap_or_default() {
        let raw = line.trim_end_matches('\r');
        if raw.trim().is_empty() { continue; }
        total = total.wrapping_add(1);
        let (key, label0) = appdetails_health_key_label(raw);
        let label = if suffix.is_empty() { label0.clone() } else { format!("{} {}", label0, suffix) };
        let jf = root.join(&key).join("app_details.json");
        if !fs::metadata(&jf).map(|m| m.is_file() && m.len() > 0).unwrap_or(false) {
            missing = missing.wrapping_add(1);
            if !remote_mode {
                issue_rows = issue_rows.wrapping_add(1);
                let _ = writeln!(issues, "{}: app_details.json 不存在或為空", tsv_sanitize(&label));
            }
            let _ = writeln!(drops, "{}: app_details.json 缺失或下載失敗 ({}/app_details.json)", tsv_sanitize(&label), tsv_sanitize(&key));
            continue;
        }
        let body = match fs::read_to_string(&jf) {
            Ok(v) => v,
            Err(e) => {
                invalid = invalid.wrapping_add(1);
                if !remote_mode {
                    issue_rows = issue_rows.wrapping_add(1);
                    let _ = writeln!(issues, "{}: json 格式損壞 (無法解析)", tsv_sanitize(&label));
                }
                let _ = writeln!(drops, "{}: app_details.json 無效/下載不完整 ({}/app_details.json)", tsv_sanitize(&label), tsv_sanitize(&key));
                let _ = writeln!(summary, "{}			0	0	0	false	false	false	read_error:{}", tsv_sanitize(&label0), tsv_sanitize(&c_strerror(&e)));
                summary_rows = summary_rows.wrapping_add(1);
                continue;
            }
        };
        if !json_document_parse_ok(&body) {
            invalid = invalid.wrapping_add(1);
            if !remote_mode {
                issue_rows = issue_rows.wrapping_add(1);
                let _ = writeln!(issues, "{}: json 格式損壞 (無法解析)", tsv_sanitize(&label));
            }
            let _ = writeln!(drops, "{}: app_details.json 無效/下載不完整 ({}/app_details.json)", tsv_sanitize(&label), tsv_sanitize(&key));
            let _ = writeln!(summary, "{}			0	0	0	false	false	false	parse_error", tsv_sanitize(&label0));
            summary_rows = summary_rows.wrapping_add(1);
            continue;
        }
        let values = json_top_object_values(&body);
        let pkg = health_first_pkg(&values);
        let ver = health_first_apk_version(&values);
        let states = health_state_objects(&values);
        let state_count = states.len();
        let legacy_count = health_legacy_count(&values);
        let ssaid_count = states.iter().filter(|st| json_direct_has_nonnull(st, "ssaid")).count();
        let schema_ok = health_appstate_schema_ok(&states);
        let items_ok = health_appstate_items_ok(&states);
        let nullable_ok = health_nullable_appstate_ok(&states);
        let mut issue = String::new();
        let mut hint = String::new();
        if pkg.is_empty() { issue.push_str(" 缺PackageName"); }
        if ver.is_empty() { issue.push_str(" 缺apk_version"); }
        if state_count > 0 {
            if !schema_ok { issue.push_str(" app_state schema/型態異常"); }
            if !items_ok { issue.push_str(" app_state項目型態異常"); }
            if !nullable_ok { issue.push_str(" app_state缺nullable標準欄位"); }
        } else if legacy_count > 0 {
            hint.push_str(" 舊版AppState格式（恢復時單次轉schema2）");
        } else if !issue.is_empty() {
            issue.push_str(" 缺app_state");
        } else {
            hint.push_str(" 精簡app_details未記錄AppState（非阻斷；重備後可補全權限狀態）");
        }
        if state_count > 0 && ssaid_count == 0 { hint.push_str(" SSAID無備份值"); }
        if !issue.is_empty() {
            issue_rows = issue_rows.wrapping_add(1);
            let _ = writeln!(issues, "{}:{}", tsv_sanitize(&label), issue);
        }
        if !hint.is_empty() {
            hint_rows = hint_rows.wrapping_add(1);
            let _ = writeln!(hints, "{}:{}", tsv_sanitize(&label), hint);
        }
        ok = ok.wrapping_add(1);
        let _ = writeln!(summary, "{}	{}	{}	{}	{}	{}	{}	{}	{}",
            tsv_sanitize(&label0), tsv_sanitize(&pkg), tsv_sanitize(&ver), state_count, legacy_count, ssaid_count,
            if schema_ok {"true"} else {"false"}, if items_ok {"true"} else {"false"}, if nullable_ok {"true"} else {"false"});
        summary_rows = summary_rows.wrapping_add(1);
    }
    if let Ok(mut st) = File::create(&stats_path) {
        let _ = writeln!(st, "total	{}", total);
        let _ = writeln!(st, "ok	{}", ok);
        let _ = writeln!(st, "invalid	{}", invalid);
        let _ = writeln!(st, "missing	{}", missing);
        let _ = writeln!(st, "issues	{}", issue_rows);
        let _ = writeln!(st, "hints	{}", hint_rows);
        let _ = writeln!(st, "rows	{}", summary_rows);
        let _ = writeln!(st, "elapsedMs	{}", start.elapsed().as_millis());
        let _ = writeln!(st, "schema	speedbackup.appdetails_health_batch.v1");
        let _ = writeln!(st, "mode	r657");
    }
    println!("APPDETAILS_HEALTH_BATCH	OK	total={}	ok={}	invalid={}	missing={}	issues={}	hints={}	rows={}	outPrefix={}	elapsedMs={}	mode=r660	schema=speedbackup.appdetails_health_batch.v1",
        total, ok, invalid, missing, issue_rows, hint_rows, summary_rows, tsv_sanitize(out_prefix), start.elapsed().as_millis());
    0
}


fn sha256_file_hex(path: &Path) -> std::io::Result<String> {
    const H0: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    const K: [u32; 64] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    ];
    let mut h = H0;
    let mut f = File::open(path)?;
    let mut total_len: u64 = 0;
    let mut pending: Vec<u8> = Vec::with_capacity(128);
    let mut buf = [0u8; 8192];
    let process_block = |block: &[u8], h: &mut [u32; 8]| {
        let mut w = [0u32; 64];
        for i in 0..16 {
            let j = i * 4;
            w[i] = u32::from_be_bytes([block[j], block[j+1], block[j+2], block[j+3]]);
        }
        for i in 16..64 {
            let s0 = w[i-15].rotate_right(7) ^ w[i-15].rotate_right(18) ^ (w[i-15] >> 3);
            let s1 = w[i-2].rotate_right(17) ^ w[i-2].rotate_right(19) ^ (w[i-2] >> 10);
            w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1);
        }
        let mut a=h[0]; let mut b=h[1]; let mut c=h[2]; let mut d=h[3];
        let mut e=h[4]; let mut f=h[5]; let mut g=h[6]; let mut hh=h[7];
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh.wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hh=g; g=f; f=e; e=d.wrapping_add(temp1); d=c; c=b; b=a; a=temp1.wrapping_add(temp2);
        }
        h[0]=h[0].wrapping_add(a); h[1]=h[1].wrapping_add(b); h[2]=h[2].wrapping_add(c); h[3]=h[3].wrapping_add(d);
        h[4]=h[4].wrapping_add(e); h[5]=h[5].wrapping_add(f); h[6]=h[6].wrapping_add(g); h[7]=h[7].wrapping_add(hh);
    };
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 { break; }
        total_len = total_len.wrapping_add(n as u64);
        pending.extend_from_slice(&buf[..n]);
        while pending.len() >= 64 {
            let block: Vec<u8> = pending.drain(..64).collect();
            process_block(&block, &mut h);
        }
    }
    let bit_len = total_len.wrapping_mul(8);
    pending.push(0x80);
    while (pending.len() % 64) != 56 { pending.push(0); }
    pending.extend_from_slice(&bit_len.to_be_bytes());
    for chunk in pending.chunks(64) { process_block(chunk, &mut h); }
    Ok(h.iter().map(|v| format!("{:08x}", v)).collect::<String>())
}

fn appdetails_meta_key(raw: &str) -> Vec<u16> {
    // Called only after document validation. UTF-16 also preserves escaped
    // surrogate code units, and normalizes literal/escaped duplicate JSON keys.
    let mut out = Vec::new();
    let mut chars = raw[1..raw.len() - 1].chars();
    while let Some(ch) = chars.next() {
        if ch != '\\' {
            out.extend(ch.encode_utf16(&mut [0; 2]).iter().copied());
            continue;
        }
        match chars.next().unwrap() {
            'u' => {
                let hex: String = chars.by_ref().take(4).collect();
                out.push(u16::from_str_radix(&hex, 16).unwrap());
            }
            'b' => out.push(8),
            'f' => out.push(12),
            'n' => out.push(10),
            'r' => out.push(13),
            't' => out.push(9),
            c => out.push(c as u16),
        }
    }
    out
}

fn appdetails_required_meta_ok(body: &str) -> bool {
    // Match the historical jq contract used by _remote_appdetails_json_ok:
    //   type=="object" and ([.[] | objects | select(.PackageName != null and .apk_version != null)] | length > 0)
    if !json_document_parse_ok(body) {
        return false;
    }
    let body = body.trim_start();
    if !body.starts_with('{') {
        return false;
    }
    let children: BTreeMap<_, _> = json_object_entries_raw(body)
        .into_iter()
        .map(|(k, v)| (appdetails_meta_key(&k), v))
        .collect();
    let package: Vec<u16> = "PackageName".encode_utf16().collect();
    let version: Vec<u16> = "apk_version".encode_utf16().collect();
    children.values().filter(|v| v.starts_with('{')).any(|obj| {
        let fields: BTreeMap<_, _> = json_object_entries_raw(obj)
            .into_iter()
            .map(|(k, v)| (appdetails_meta_key(&k), v))
            .collect();
        fields.get(&package).map(|v| v != "null").unwrap_or(false)
            && fields.get(&version).map(|v| v != "null").unwrap_or(false)
    })
}

fn cmd_appdetails_seed_index(args: &[String]) -> i32 {
    if args.len() < 5 {
        return 2;
    }
    let start = Instant::now();
    let root = Path::new(&args[2]);
    let seed_out = Path::new(&args[3]);
    let out_prefix = &args[4];
    if !root.is_dir() {
        return 3;
    }
    let diag_file = format!("{}.diag", out_prefix);
    let stats_file = format!("{}.stats", out_prefix);
    let mut dirs: Vec<(String, PathBuf)> = Vec::new();
    if let Ok(rd) = fs::read_dir(root) {
        for e in rd.flatten() {
            let dir = e.path();
            if !dir.is_dir() {
                continue;
            }
            let app = match dir.file_name() {
                Some(v) => v.to_string_lossy().into_owned(),
                None => continue,
            };
            let jf = dir.join("app_details.json");
            if jf.is_file() && fs::metadata(&jf).map(|m| m.len() > 0).unwrap_or(false) {
                dirs.push((app, jf));
            }
        }
    }
    dirs.sort_by(|a, b| a.0.cmp(&b.0));
    let seed_file = match File::create(seed_out) {
        Ok(v) => v,
        Err(_) => return 4,
    };
    let mut seed = BufWriter::new(seed_file);
    let mut diag = match File::create(&diag_file) {
        Ok(v) => BufWriter::new(v),
        Err(_) => return 4,
    };
    let mut total = 0u64;
    let mut ok = 0u64;
    let mut bad = 0u64;
    for (app, jf) in dirs.iter() {
        total = total.wrapping_add(1);
        let body = match fs::read_to_string(jf) {
            Ok(v) => v,
            Err(e) => {
                bad = bad.wrapping_add(1);
                let _ = writeln!(
                    diag,
                    "{}\tjson_unreadable\t{}\t{}",
                    tsv_sanitize(app),
                    tsv_sanitize(&jf.to_string_lossy()),
                    tsv_sanitize(&c_strerror(&e))
                );
                let _ = fs::remove_file(jf);
                continue;
            }
        };
        if appdetails_required_meta_ok(&body) {
            if writeln!(seed, "{}", app).is_err() {
                return 4;
            }
            ok = ok.wrapping_add(1);
        } else {
            bad = bad.wrapping_add(1);
            let _ = writeln!(
                diag,
                "{}\tmetadata_invalid\t{}",
                tsv_sanitize(app),
                tsv_sanitize(&jf.to_string_lossy())
            );
            let _ = fs::remove_file(jf);
        }
    }
    if seed.flush().is_err() || diag.flush().is_err() {
        return 4;
    }
    let elapsed = start.elapsed().as_millis();
    if let Ok(mut st) = File::create(&stats_file) {
        let _ = writeln!(
            st,
            "{}\t{}\t{}\t{}\t{}\t{}",
            total, ok, bad, total, elapsed, "speedbackup.appdetails_seed_index.v1"
        );
    }
    if ok == 0 {
        println!("APPDETAILS_SEED_INDEX\tEMPTY\ttotal={}\tok=0\tbad={}\telapsedMs={}\tmode=r698\tschema=speedbackup.appdetails_seed_index.v1", total, bad, elapsed);
        return 5;
    }
    println!("APPDETAILS_SEED_INDEX\tOK\ttotal={}\tok={}\tbad={}\telapsedMs={}\tmode=r698\tschema=speedbackup.appdetails_seed_index.v1", total, ok, bad, elapsed);
    0
}

fn cmd_appdetails_bundle_manifest(args: &[String]) -> i32 {
    if args.len() < 4 { return 2; }
    let start = Instant::now();
    let root = Path::new(&args[2]);
    let out_prefix = &args[3];
    if !root.is_dir() { return 3; }
    let manifest = root.join("manifest.tsv");
    let tmp_manifest = root.join(format!("manifest.tsv.part.{}", std::process::id()));
    let diag_file = format!("{}.diag", out_prefix);
    let stats_file = format!("{}.stats", out_prefix);
    let ok_file = format!("{}.ok", out_prefix);
    let mut dirs: Vec<(String, PathBuf)> = Vec::new();
    if let Ok(rd) = fs::read_dir(root) {
        for e in rd.flatten() {
            let dir = e.path();
            if !dir.is_dir() { continue; }
            let app = match dir.file_name() { Some(v) => v.to_string_lossy().into_owned(), None => continue };
            let jf = dir.join("app_details.json");
            if jf.is_file() && fs::metadata(&jf).map(|m| m.len() > 0).unwrap_or(false) {
                dirs.push((app, jf));
            }
        }
    }
    dirs.sort_by(|a,b| a.0.cmp(&b.0));
    let mut diag = match File::create(&diag_file) { Ok(v) => v, Err(_) => return 4 };
    let mut out = match File::create(&tmp_manifest) { Ok(v) => v, Err(_) => return 4 };
    let mut total = 0u64;
    let mut ok = 0u64;
    let mut bad = 0u64;
    let mut seen = 0u64;
    for (app, jf) in dirs.iter() {
        total = total.wrapping_add(1);
        seen = seen.wrapping_add(1);
        let meta = match fs::metadata(jf) {
            Ok(v) => v,
            Err(e) => { bad += 1; let _ = writeln!(diag, "{}\t\tmetadata_unreadable\t{}\t{}", tsv_sanitize(app), tsv_sanitize(&jf.to_string_lossy()), tsv_sanitize(&c_strerror(&e))); continue; }
        };
        let body = match fs::read_to_string(jf) {
            Ok(v) => v,
            Err(e) => { bad += 1; let _ = writeln!(diag, "{}\t\tjson_unreadable\t{}\t{}", tsv_sanitize(app), tsv_sanitize(&jf.to_string_lossy()), tsv_sanitize(&c_strerror(&e))); continue; }
        };
        let pkg = json_string_value(&body, &["PackageName", "packageName", "package", "pkg"]).unwrap_or_default();
        if pkg.is_empty() || !appdetails_required_meta_ok(&body) {
            bad += 1;
            let _ = writeln!(diag, "{}\t{}\tmetadata_invalid\t{}", tsv_sanitize(app), tsv_sanitize(&pkg), tsv_sanitize(&jf.to_string_lossy()));
            continue;
        }
        let sha = match sha256_file_hex(jf) {
            Ok(v) => v,
            Err(e) => { bad += 1; let _ = writeln!(diag, "{}\t{}\tsha256_failed\t{}\t{}", tsv_sanitize(app), tsv_sanitize(&pkg), tsv_sanitize(&jf.to_string_lossy()), tsv_sanitize(&c_strerror(&e))); continue; }
        };
        let _ = writeln!(out, "{}\t{}\t{}\t{}", tsv_sanitize(app), tsv_sanitize(&pkg), meta.len(), sha);
        ok = ok.wrapping_add(1);
    }
    drop(out);
    if let Ok(mut st) = File::create(&stats_file) {
        let _ = writeln!(st, "{}\t{}\t{}\t{}\t{}\t{}\t{}", total, ok, bad, seen, start.elapsed().as_millis(), "speedbackup.appdetails_bundle_manifest.v1", "r637");
    }
    if total == 0 || bad > 0 || ok != total {
        let _ = fs::remove_file(&tmp_manifest);
        println!("APPDETAILS_BUNDLE_MANIFEST\tBLOCK\ttotal={}\tok={}\tbad={}\tseen={}\telapsedMs={}\tmode=r637\tschema=speedbackup.appdetails_bundle_manifest.v1", total, ok, bad, seen, start.elapsed().as_millis());
        return if total == 0 { 5 } else { 6 };
    }
    if fs::rename(&tmp_manifest, &manifest).is_err() {
        let _ = fs::remove_file(&tmp_manifest);
        return 4;
    }
    if let Ok(mut f) = File::create(&ok_file) { let _ = writeln!(f, "{}", ok); }
    println!("APPDETAILS_BUNDLE_MANIFEST\tOK\ttotal={}\tok={}\tbad=0\tseen={}\tmanifest={}\telapsedMs={}\tmode=r637\tschema=speedbackup.appdetails_bundle_manifest.v1", total, ok, seen, tsv_sanitize(&manifest.to_string_lossy()), start.elapsed().as_millis());
    0
}

fn appdetails_seed_expansion_allowed(
    stage_len: usize,
    scoped_payload_len: usize,
    missing_seed_len: usize,
    missing_stage_len: usize,
    ignored_remote_count: usize,
    bad: u64,
) -> bool {
    missing_seed_len > 0
        && stage_len == scoped_payload_len
        && missing_stage_len == 0
        && ignored_remote_count == 0
        && bad == 0
}

fn cmd_appdetails_bundle_audit(args: &[String]) -> i32 {
    if args.len() < 8 { return 2; }
    let start = Instant::now();
    let root = &args[2];
    let remote_files = &args[3];
    let seed_list_path = &args[4];
    let seed_state_s = &args[5];
    let seed_count_s = &args[6];
    let out_prefix = &args[7];
    let allow_shrink = args.get(8).map(|s| s == "1" || s.eq_ignore_ascii_case("true")).unwrap_or(false);
    let stage = appdetails_stage_apps(root);
    let seed = load_line_set(seed_list_path);
    let seed_state = if Path::new(seed_state_s).exists() || seed_state_s == "-" { read_first_trimmed(seed_state_s) } else { seed_state_s.to_string() };
    let mut seed_count = parse_u64_strict_default(seed_count_s, seed.len() as u64);
    if Path::new(seed_count_s).exists() { seed_count = parse_u64_strict_default(&read_first_trimmed(seed_count_s), seed.len() as u64); }
    if seed_count == 0 && !seed.is_empty() { seed_count = seed.len() as u64; }
    let remote = appdetails_remote_payload_apps(remote_files);
    let (payload_opt, rels) = match remote {
        Some((apps, rels)) => (Some(apps), rels),
        None => (None, HashSet::new()),
    };
    let remote_payload_total_i: i64 = payload_opt.as_ref().map(|s| s.len() as i64).unwrap_or(-1);
    let seed_ok = seed_state == "ok" && seed_count > 0 && !seed.is_empty();
    let mut scope: HashSet<String> = stage.clone();
    if seed_ok {
        for app in seed.iter() { scope.insert(app.clone()); }
    }
    let mut scoped_payload: HashSet<String> = HashSet::new();
    let mut ignored_remote_payload: Vec<String> = Vec::new();
    if let Some(payload) = payload_opt.as_ref() {
        for app in payload.iter() {
            if scope.contains(app) { scoped_payload.insert(app.clone()); }
            else { ignored_remote_payload.push(app.clone()); }
        }
        ignored_remote_payload.sort();
    }
    let payload_count_i: i64 = if payload_opt.is_some() { scoped_payload.len() as i64 } else { -1 };
    let ignored_remote_count = ignored_remote_payload.len();
    let ignored_remote_sample = ignored_remote_payload.iter().take(8).map(|s| tsv_sanitize(s)).collect::<Vec<_>>().join(",");
    let remote_payload_file = format!("{}.remote_payload_apps.lst", out_prefix);
    let ignored_remote_file = format!("{}.ignored_remote_payload_apps.lst", out_prefix);
    let missing_seed_file = format!("{}.missing_seed.lst", out_prefix);
    let missing_stage_file = format!("{}.missing_stage.lst", out_prefix);
    let bad_log_file = format!("{}.bad.log", out_prefix);
    let stats_file = format!("{}.stats", out_prefix);
    if let Some(payload) = payload_opt.as_ref() { write_set_file(&remote_payload_file, payload); } else { let _ = File::create(&remote_payload_file); }
    write_vec_file(&ignored_remote_file, &ignored_remote_payload);

    let mut reason = "ok".to_string();
    let mut missing_seed: Vec<String> = Vec::new();
    let mut missing_stage: Vec<String> = Vec::new();
    let mut seedless_repair = false;
    let mut seed_expansion_candidate = false;
    if !allow_shrink {
        match payload_opt.as_ref() {
            Some(payload) if payload.is_empty() => {},
            None => {
                if !seed_ok || (stage.len() as u64) < seed_count {
                    reason = "remote_payload_unknown_and_seed_not_ok".to_string();
                }
            },
            Some(_payload) => {
                // r644: app_details bundle no-shrink is scoped to app payload folders that are
                // identifiable by current staged JSON and/or the previous seed list.  Extra
                // WebDAV/NAS roots (folder backups, WiFi/tools roots, stale foreign folders, or
                // already orphaned app dirs not present in JSON) are diagnostic-only and must not
                // block rebuilding the app list.  This matches the user-visible invariant: the
                // bundle must cover folders whose name matches app_details JSON, plus previous
                // seeded apps unless an explicit shrink policy is enabled.
                if !seed_ok {
                    if stage.is_empty() {
                        reason = "stage_app_set_missing".to_string();
                    } else {
                        seedless_repair = true;
                    }
                } else {
                    missing_seed = set_missing(&scoped_payload, &seed);
                    let mut required_stage: HashSet<String> = scoped_payload.clone();
                    for app in seed.iter() { required_stage.insert(app.clone()); }
                    missing_stage = set_missing(&required_stage, &stage);
                    // r695: a previous bundle seed is allowed to grow when the current staging set
                    // exactly covers the scoped remote payload, no remote payload was ignored, and
                    // every previously seeded/payload app is present in staging. Payload consistency
                    // is checked below before seedExpansion becomes final.
                    seed_expansion_candidate = appdetails_seed_expansion_allowed(
                        stage.len(), scoped_payload.len(), missing_seed.len(), missing_stage.len(), ignored_remote_count, 0
                    );
                    if !missing_seed.is_empty() && !seed_expansion_candidate { reason = "scoped_payload_not_covered_by_seed".to_string(); }
                    else if (stage.len() as u64) < seed_count { reason = "stage_count_lt_seed".to_string(); }
                    else if !missing_stage.is_empty() { reason = "seed_or_scoped_payload_not_covered_by_stage".to_string(); }
                }
            }
        }
    }
    write_vec_file(&missing_seed_file, &missing_seed);
    write_vec_file(&missing_stage_file, &missing_stage);

    let mut checked = 0u64;
    let mut bad = 0u64;
    let mut badlog = match File::create(&bad_log_file) { Ok(f) => f, Err(_) => return 4 };
    if !rels.is_empty() {
        if let Ok(rd) = fs::read_dir(root) {
            for e in rd.flatten() {
                let dir = e.path();
                if !dir.is_dir() { continue; }
                let app = match dir.file_name() { Some(v) => v.to_string_lossy().into_owned(), None => continue };
                let jf = dir.join("app_details.json");
                if !jf.is_file() { continue; }
                let body = match fs::read_to_string(&jf) { Ok(v) => v, Err(_) => continue };
                let pkg = json_string_value(&body, &["PackageName", "packageName", "package", "pkg"]).unwrap_or_else(|| "unknown".to_string());
                for entry in ["user","data","obb","media","user_de","thanox","hma"] {
                    let sz = match appdetails_entry_size(&body, entry) { Some(v) => v, None => continue };
                    if !sz.as_bytes().iter().all(|b| b.is_ascii_digit()) || sz.len() < 4 { continue; }
                    checked = checked.wrapping_add(1);
                    let relz = format!("{}/{}.tar.zst", app, entry);
                    let relt = format!("{}/{}.tar", app, entry);
                    if !(rels.contains(&relz) || rels.contains(&relt)) {
                        bad = bad.wrapping_add(1);
                        let _ = writeln!(badlog, "REMOTE_METADATA_PAYLOAD_STALE app={} package={} entry={} size={} rel={} reason=payload_missing mode=r645", tsv_sanitize(&app), tsv_sanitize(&pkg), tsv_sanitize(entry), tsv_sanitize(&sz), tsv_sanitize(&relz));
                    }
                }
            }
        }
    }
    if bad > 0 && reason == "ok" { reason = "payload_consistency_failed".to_string(); }
    let seed_expansion = seed_expansion_candidate && appdetails_seed_expansion_allowed(
        stage.len(), scoped_payload.len(), missing_seed.len(), missing_stage.len(), ignored_remote_count, bad
    );
    let seedless_tainted = seedless_repair && ignored_remote_count > 0;
    let status = if reason == "ok" { "OK" } else { "BLOCK" };
    let first_missing = missing_seed.first().or_else(|| missing_stage.first()).cloned().unwrap_or_default();
    if let Ok(mut st) = File::create(&stats_file) {
        let _ = writeln!(st, "stage\tseed\tremotePayloadApps\tremotePayloadTotal\tignoredRemotePayloadApps\tmissingSeed\tmissingStage\tchecked\tbad\treason\tfirstMissing\tallowShrink\tseedlessRepair\tseedlessTainted\tseedExpansion\tignoredRemotePayloadSample\telapsedMs");
        let _ = writeln!(st, "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", stage.len(), seed_count, payload_count_i, remote_payload_total_i, ignored_remote_count, missing_seed.len(), missing_stage.len(), checked, bad, reason, tsv_sanitize(&first_missing), if allow_shrink {1}else{0}, if seedless_repair {1}else{0}, if seedless_tainted {1}else{0}, if seed_expansion {1}else{0}, tsv_sanitize(&ignored_remote_sample), start.elapsed().as_millis());
    }
    println!("APPDETAILS_BUNDLE_AUDIT\t{}\tstage={}\tseed={}\tremotePayloadApps={}\tremotePayloadTotal={}\tignoredRemotePayloadApps={}\tignoredRemotePayloadList={}.ignored_remote_payload_apps.lst\tignoredRemotePayloadSample={}\tmissingSeed={}\tmissingStage={}\tchecked={}\tbad={}\treason={}\tfirstMissing={}\tallowShrink={}\tseedlessRepair={}\tseedlessTainted={}\tseedExpansion={}\telapsedMs={}\tmode=r695\tschema=speedbackup.appdetails_bundle_audit.v5",
        status, stage.len(), seed_count, payload_count_i, remote_payload_total_i, ignored_remote_count, tsv_sanitize(out_prefix), tsv_sanitize(&ignored_remote_sample), missing_seed.len(), missing_stage.len(), checked, bad, tsv_sanitize(&reason), tsv_sanitize(&first_missing), if allow_shrink {1}else{0}, if seedless_repair {1}else{0}, if seedless_tainted {1}else{0}, if seed_expansion {1}else{0}, start.elapsed().as_millis());
    if reason == "ok" { 0 } else { 5 }
}


fn load_installed_pkg_set(path_s: &str) -> HashSet<String> {
    let mut out = HashSet::new();
    if path_s.is_empty() || path_s == "-" || !Path::new(path_s).exists() { return out; }
    if let Ok(lines) = read_lines(Path::new(path_s)) {
        for mut line in lines {
            while line.ends_with('\r') { line.pop(); }
            let t = line.trim();
            if t.is_empty() || t.starts_with('#') { continue; }
            for col in t.split('\t') {
                let v = col.trim();
                if v.contains('.') && !v.contains('/') && !v.contains(' ') && !v.is_empty() {
                    out.insert(v.to_string());
                    break;
                }
            }
        }
    }
    out
}

fn appdetails_bundle_pkg_map(root: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    if root.is_empty() || root == "-" { return out; }
    let rd = match fs::read_dir(root) { Ok(v) => v, Err(_) => return out };
    for e in rd.flatten() {
        let dir = e.path();
        if !dir.is_dir() { continue; }
        let app = match dir.file_name() { Some(v) => v.to_string_lossy().into_owned(), None => continue };
        let jf = dir.join("app_details.json");
        if !jf.is_file() { continue; }
        let body = match fs::read_to_string(&jf) { Ok(v) => v, Err(_) => continue };
        if let Some(pkg) = json_string_value(&body, &["PackageName", "packageName", "package", "pkg"]) {
            out.insert(app, pkg);
        } else {
            out.insert(app, String::new());
        }
    }
    out
}


fn sanitize_app_folder_name(raw: &str, fallback: &str) -> String {
    let bad = "/\\ :\t\r\n\"`$;|&()<>!*?[]{}=#~^'";
    let mut out = String::new();
    for ch in raw.chars() {
        if bad.contains(ch) || ch.is_control() { out.push('_'); } else { out.push(ch); }
    }
    while out.contains("..") { out = out.replace("..", "__"); }
    if out.is_empty() || out == "." || out == ".." {
        let mut fb = String::new();
        for ch in fallback.chars() {
            if ch.is_ascii_alphanumeric() || ch == '.' || ch == '_' || ch == '-' { fb.push(ch); } else { fb.push('_'); }
        }
        while fb.contains("..") { fb = fb.replace("..", "__"); }
        out = fb;
    }
    if out.is_empty() || out == "." || out == ".." { "app".to_string() } else { out }
}

fn load_pkg_version_map(path_s: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    if path_s.is_empty() || path_s == "-" || !Path::new(path_s).exists() { return out; }
    for row in read_tsv_rows(path_s) {
        if row.len() >= 2 && !row[0].is_empty() { out.insert(row[0].clone(), row[1].clone()); }
    }
    out
}

fn cmd_selected_apps_map(args: &[String]) -> i32 {
    if args.len() < 5 { return 2; }
    let start = Instant::now();
    let raw_file = &args[2];
    let pkgver_file = &args[3];
    let out_s = &args[4];
    let versions = load_pkg_version_map(pkgver_file);
    let mut out = match File::create(out_s) { Ok(v) => v, Err(_) => return 4 };
    let f = match File::open(raw_file) { Ok(v) => v, Err(_) => return 3 };
    let mut br = BufReader::new(f);
    let mut buf = Vec::<u8>::new();
    let mut rows = 0u64;
    while let Some(line) = next_c_line_lossy(&mut br, &mut buf) {
        let l = line.trim().to_string();
        if l.is_empty() || l.starts_with('#') || l.starts_with('＃') { continue; }
        let mut parts = l.split_whitespace();
        let mut name = match parts.next() { Some(v) => v.to_string(), None => continue };
        let pkg = match parts.next() { Some(v) => v.to_string(), None => continue };
        let mut nodata = "0";
        if name.starts_with('!') || name.starts_with('！') {
            name = name.chars().skip(1).collect();
            nodata = "1";
        }
        let app = sanitize_app_folder_name(&name, &pkg);
        let ver = versions.get(&pkg).cloned().unwrap_or_default();
        let _ = writeln!(out, "{}\t{}\t{}\t{}", tsv_sanitize(&app), tsv_sanitize(&pkg), nodata, tsv_sanitize(&ver));
        rows += 1;
    }
    println!("SELECTED_APPS_MAP\tOK\trows={}\tout={}\telapsedMs={}\tmode=r631\tschema=speedbackup.selected_apps_map.v1", rows, tsv_sanitize(out_s), start.elapsed().as_millis());
    0
}

fn cmd_appdetails_summary_map(args: &[String]) -> i32 {
    if args.len() < 4 { return 2; }
    let start = Instant::now();
    let root = Path::new(&args[2]);
    let out_s = &args[3];
    let mut out = match File::create(out_s) { Ok(v) => v, Err(_) => return 4 };
    let mut rows = 0u64;
    if let Ok(rd) = fs::read_dir(root) {
        for e in rd.flatten() {
            let dir = e.path();
            if !dir.is_dir() { continue; }
            let app = match dir.file_name() { Some(v) => v.to_string_lossy().into_owned(), None => continue };
            let jf = dir.join("app_details.json");
            if !jf.is_file() { continue; }
            let body = match fs::read_to_string(&jf) { Ok(v) => v, Err(_) => continue };
            let pkg = json_string_value(&body, &["PackageName", "packageName", "package", "pkg"]).unwrap_or_default();
            let ver = json_string_value(&body, &["apk_version", "apkVersion", "versionCode", "version_code"]).unwrap_or_default();
            let sz_user = appdetails_entry_size(&body, "user").unwrap_or_default();
            let sz_user_de = appdetails_entry_size(&body, "user_de").unwrap_or_default();
            let sz_data = appdetails_entry_size(&body, "data").unwrap_or_default();
            let sz_obb = appdetails_entry_size(&body, "obb").unwrap_or_default();
            let sz_media = appdetails_entry_size(&body, "media").unwrap_or_default();
            let state_ok = if appstate_persistable_from_appdetails(&body) { "1" } else { "0" };
            let _ = writeln!(out, "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", tsv_sanitize(&app), tsv_sanitize(&pkg), tsv_sanitize(&ver), tsv_sanitize(&sz_user), tsv_sanitize(&sz_user_de), tsv_sanitize(&sz_data), tsv_sanitize(&sz_obb), tsv_sanitize(&sz_media), state_ok);
            rows += 1;
        }
    }
    println!("APPDETAILS_SUMMARY_MAP\tOK\trows={}\troot={}\tout={}\telapsedMs={}\tmode=r631\tschema=speedbackup.appdetails_summary_map.v1", rows, tsv_sanitize(&args[2]), tsv_sanitize(out_s), start.elapsed().as_millis());
    0
}

fn load_current_appstate_tsv(path_s: &str) -> HashMap<String, AppStateMatchCanon> {
    let mut out = HashMap::new();
    if path_s.is_empty() || path_s == "-" { return out; }
    let f = match File::open(path_s) { Ok(v) => v, Err(_) => return out };
    let mut br = BufReader::new(f);
    let mut buf = Vec::<u8>::new();
    while let Some(line) = next_c_line_lossy(&mut br, &mut buf) {
        if line.is_empty() { continue; }
        let mut sp = line.splitn(2, '\t');
        let pkg = sp.next().unwrap_or("").to_string();
        let body = sp.next().unwrap_or("").to_string();
        if pkg.is_empty() || body.is_empty() { continue; }
        if let Some(compact) = appstate_compact_profile(&body) {
            out.insert(pkg, compact);
        }
    }
    out
}

fn cmd_appstate_match_map(args: &[String]) -> i32 {
    if args.len() < 5 { return 2; }
    let start = Instant::now();
    let root = Path::new(&args[2]);
    let current = load_current_appstate_tsv(&args[3]);
    let out_s = &args[4];
    let mut out = match File::create(out_s) { Ok(v) => v, Err(_) => return 4 };
    let mut rows = 0u64;
    let mut matched = 0u64;
    let mut ssaid_current_null_accepted = 0u64;
    if let Ok(rd) = fs::read_dir(root) {
        for e in rd.flatten() {
            let dir = e.path();
            if !dir.is_dir() { continue; }
            let app = match dir.file_name() { Some(v) => v.to_string_lossy().into_owned(), None => continue };
            let jf = dir.join("app_details.json");
            if !jf.is_file() { continue; }
            let body = match fs::read_to_string(&jf) { Ok(v) => v, Err(_) => continue };
            let pkg = json_string_value(&body, &["PackageName", "packageName", "package", "pkg"]).unwrap_or_default();
            if pkg.is_empty() { continue; }
            let old_obj = appstate_obj_from_appdetails(&body).unwrap_or_default();
            let old_ok = appstate_persistable_obj(&old_obj);
            let cur_ok = current.contains_key(&pkg);
            let old_compact = appstate_compact_profile(&old_obj);
            let eq = if old_ok && cur_ok {
                match (old_compact.as_ref(), current.get(&pkg)) {
                    (Some(oldc), Some(curc)) => {
                        let ssaid_ok = appstate_ssaid_match_for_fastskip(&oldc.ssaid, &curc.ssaid);
                        if ssaid_ok && curc.ssaid.is_empty() && !oldc.ssaid.is_empty() {
                            ssaid_current_null_accepted = ssaid_current_null_accepted.wrapping_add(1);
                        }
                        !oldc.profile_no_ssaid.is_empty() && oldc.profile_no_ssaid == curc.profile_no_ssaid && ssaid_ok
                    },
                    _ => false,
                }
            } else { false };
            if eq { matched = matched.wrapping_add(1); }
            let _ = writeln!(out, "{}\t{}\t{}\t{}\t{}", tsv_sanitize(&app), tsv_sanitize(&pkg), if old_ok {"1"} else {"0"}, if cur_ok {"1"} else {"0"}, if eq {"1"} else {"0"});
            rows = rows.wrapping_add(1);
        }
    }
    println!("APPSTATE_MATCH_MAP\tOK\trows={}\tmatched={}\tcurrent={}\tout={}\telapsedMs={}\tmode=r642\tschema=speedbackup.appstate_match_map.v1\tcanonical=speedbackup.appstate_match_canonical_v4.v1\tssaidPolicy=preserve_old_when_current_null\tssaidCurrentNullAccepted={}", rows, matched, current.len(), tsv_sanitize(out_s), start.elapsed().as_millis(), ssaid_current_null_accepted);
    0
}


fn append_local_presize_bundle_stats(
    path_s: &str,
    selected_ms: u128,
    summary_ms: u128,
    appstate_ms: u128,
    presize_ms: u128,
    total_ms: u128,
) -> bool {
    let mut out = match OpenOptions::new().append(true).open(path_s) {
        Ok(v) => v,
        Err(_) => return false,
    };
    writeln!(out, "bundleSelectedElapsedMs\t{}", selected_ms).is_ok()
        && writeln!(out, "bundleSummaryElapsedMs\t{}", summary_ms).is_ok()
        && writeln!(out, "bundleAppstateElapsedMs\t{}", appstate_ms).is_ok()
        && writeln!(out, "bundlePresizeElapsedMs\t{}", presize_ms).is_ok()
        && writeln!(out, "bundleTotalElapsedMs\t{}", total_ms).is_ok()
        && writeln!(out, "bundleProcessStarts\t1").is_ok()
        && writeln!(out, "bundleSchema\tspeedscan.local_fastskip_presize_bundle_v1.v1").is_ok()
}

fn cmd_local_fastskip_presize_bundle_v1(args: &[String]) -> i32 {
    if args.len() < 24 { return 2; }
    let total_start = Instant::now();
    let raw_applist = &args[2];
    let pkg_ver = &args[3];
    let appdetails_root = &args[4];
    let current_appstate = &args[5];
    let blackset = &args[6];
    let backup_root = &args[7];
    let out_selected = &args[8];
    let out_summary = &args[9];
    let out_state = &args[10];
    let out_exists = &args[11];
    let out_archives = &args[12];
    let out_manifest = &args[13];
    let out_stats = &args[14];
    let out_diag = &args[15];
    let out_tiny = &args[16];
    let backup_mode = &args[17];
    let backup_obb = &args[18];
    let backup_user = &args[19];
    let blacklist_mode = &args[20];
    let android_root = &args[21];
    let user_root = &args[22];
    let user_de_root = &args[23];

    let selected_start = Instant::now();
    let selected_args = vec![
        args[0].clone(), "selected-apps-map".to_string(), raw_applist.to_string(), pkg_ver.to_string(), out_selected.to_string()
    ];
    let rc = cmd_selected_apps_map(&selected_args);
    let selected_ms = selected_start.elapsed().as_millis();
    if rc != 0 {
        println!("LOCAL_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=selected\trc={}\telapsedMs={}\tmode=r677\tschema=speedscan.local_fastskip_presize_bundle_v1.v1", rc, total_start.elapsed().as_millis());
        return rc;
    }

    let summary_start = Instant::now();
    let summary_args = vec![
        args[0].clone(), "appdetails-summary-map".to_string(), appdetails_root.to_string(), out_summary.to_string()
    ];
    let rc = cmd_appdetails_summary_map(&summary_args);
    let summary_ms = summary_start.elapsed().as_millis();
    if rc != 0 {
        println!("LOCAL_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=summary\trc={}\telapsedMs={}\tmode=r677\tschema=speedscan.local_fastskip_presize_bundle_v1.v1", rc, total_start.elapsed().as_millis());
        return rc;
    }

    let appstate_start = Instant::now();
    let rc = if current_appstate == "-" || current_appstate.is_empty() {
        match File::create(out_state) { Ok(_) => 0, Err(_) => 4 }
    } else {
        let state_args = vec![
            args[0].clone(), "appstate-match-map".to_string(), appdetails_root.to_string(), current_appstate.to_string(), out_state.to_string()
        ];
        cmd_appstate_match_map(&state_args)
    };
    let appstate_ms = appstate_start.elapsed().as_millis();
    if rc != 0 {
        println!("LOCAL_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=appstate\trc={}\telapsedMs={}\tmode=r677\tschema=speedscan.local_fastskip_presize_bundle_v1.v1", rc, total_start.elapsed().as_millis());
        return rc;
    }

    let presize_start = Instant::now();
    let presize_args = vec![
        args[0].clone(), "local-fastskip-presize-plan-v4".to_string(), out_selected.to_string(), out_summary.to_string(), out_state.to_string(),
        blackset.to_string(), backup_root.to_string(), out_exists.to_string(), out_archives.to_string(), out_manifest.to_string(), out_stats.to_string(),
        out_diag.to_string(), out_tiny.to_string(), backup_mode.to_string(), backup_obb.to_string(), backup_user.to_string(), blacklist_mode.to_string(),
        android_root.to_string(), user_root.to_string(), user_de_root.to_string()
    ];
    let rc = cmd_local_fastskip_presize_plan_v4(&presize_args);
    let presize_ms = presize_start.elapsed().as_millis();
    if rc != 0 {
        println!("LOCAL_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=presize\trc={}\telapsedMs={}\tmode=r677\tschema=speedscan.local_fastskip_presize_bundle_v1.v1", rc, total_start.elapsed().as_millis());
        return rc;
    }

    let total_ms = total_start.elapsed().as_millis();
    if !append_local_presize_bundle_stats(out_stats, selected_ms, summary_ms, appstate_ms, presize_ms, total_ms) {
        println!("LOCAL_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=stats_append\trc=4\telapsedMs={}\tmode=r677\tschema=speedscan.local_fastskip_presize_bundle_v1.v1", total_ms);
        return 4;
    }
    println!("LOCAL_FASTSKIP_PRESIZE_BUNDLE\tOK\tselectedElapsedMs={}\tsummaryElapsedMs={}\tappstateElapsedMs={}\tpresizeElapsedMs={}\ttotalElapsedMs={}\tprocessStarts=1\tmode=r677\tschema=speedscan.local_fastskip_presize_bundle_v1.v1",
        selected_ms, summary_ms, appstate_ms, presize_ms, total_ms);
    0
}

fn rewrite_remote_presize_diag(path_s: &str) -> bool {
    let rows = read_tsv_rows(path_s);
    let mut out = match File::create(path_s) { Ok(v) => v, Err(_) => return false };
    for mut r in rows {
        if r.len() >= 3 {
            r[2] = match r[2].as_str() {
                "local_json_missing" => "remote_json_missing".to_string(),
                "apk_archive_missing" => "remote_apk_missing".to_string(),
                "archive_missing" => "remote_payload_missing".to_string(),
                _ => r[2].clone(),
            };
        }
        if writeln!(out, "{}", r.join("\t")).is_err() { return false; }
    }
    true
}

fn append_remote_presize_bundle_stats(
    path_s: &str,
    selected_ms: u128,
    summary_ms: u128,
    appstate_ms: u128,
    presence_ms: u128,
    payload_ms: u128,
    presize_ms: u128,
    total_ms: u128,
) -> bool {
    let mut out = match OpenOptions::new().append(true).open(path_s) { Ok(v) => v, Err(_) => return false };
    writeln!(out, "bundleSelectedElapsedMs\t{}", selected_ms).is_ok()
        && writeln!(out, "bundleSummaryElapsedMs\t{}", summary_ms).is_ok()
        && writeln!(out, "bundleAppstateElapsedMs\t{}", appstate_ms).is_ok()
        && writeln!(out, "bundlePresenceElapsedMs\t{}", presence_ms).is_ok()
        && writeln!(out, "bundlePayloadElapsedMs\t{}", payload_ms).is_ok()
        && writeln!(out, "bundlePresizeElapsedMs\t{}", presize_ms).is_ok()
        && writeln!(out, "bundleTotalElapsedMs\t{}", total_ms).is_ok()
        && writeln!(out, "bundleProcessStarts\t1").is_ok()
        && writeln!(out, "bundleSchema\tspeedscan.remote_fastskip_presize_bundle_v1.v1").is_ok()
}

fn cmd_remote_fastskip_presize_bundle_v1(args: &[String]) -> i32 {
    if args.len() < 25 { return 2; }
    let total_start=Instant::now();
    let raw_applist=&args[2]; let pkg_ver=&args[3]; let appdetails_root=&args[4]; let current_appstate=&args[5]; let blackset=&args[6];
    let remote_payload_rels=&args[7]; let out_payload_set=&args[8]; let out_selected=&args[9]; let out_summary=&args[10]; let out_state=&args[11];
    let out_exists=&args[12]; let out_archives=&args[13]; let out_manifest=&args[14]; let out_stats=&args[15]; let out_diag=&args[16]; let out_tiny=&args[17];
    let backup_mode=&args[18]; let backup_obb=&args[19]; let backup_user=&args[20]; let blacklist_mode=&args[21];
    let android_root=&args[22]; let user_root=&args[23]; let user_de_root=&args[24];

    let selected_start=Instant::now();
    let selected_args=vec![args[0].clone(),"selected-apps-map".to_string(),raw_applist.to_string(),pkg_ver.to_string(),out_selected.to_string()];
    let rc=cmd_selected_apps_map(&selected_args); let selected_ms=selected_start.elapsed().as_millis();
    if rc!=0 { println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=selected\trc={}\telapsedMs={}\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",rc,total_start.elapsed().as_millis()); return rc; }

    let summary_start=Instant::now();
    let summary_args=vec![args[0].clone(),"appdetails-summary-map".to_string(),appdetails_root.to_string(),out_summary.to_string()];
    let rc=cmd_appdetails_summary_map(&summary_args); let summary_ms=summary_start.elapsed().as_millis();
    if rc!=0 { println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=summary\trc={}\telapsedMs={}\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",rc,total_start.elapsed().as_millis()); return rc; }

    let appstate_start=Instant::now();
    let rc=if current_appstate=="-" || current_appstate.is_empty() { match File::create(out_state){Ok(_)=>0,Err(_)=>4} } else {
        let state_args=vec![args[0].clone(),"appstate-match-map".to_string(),appdetails_root.to_string(),current_appstate.to_string(),out_state.to_string()];
        cmd_appstate_match_map(&state_args)
    };
    let appstate_ms=appstate_start.elapsed().as_millis();
    if rc!=0 { println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=appstate\trc={}\telapsedMs={}\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",rc,total_start.elapsed().as_millis()); return rc; }

    let presize_total_start=Instant::now();
    let presence_start=Instant::now();
    let presence_args=vec![args[0].clone(),"backup-entry-presence-map".to_string(),out_selected.to_string(),out_exists.to_string(),backup_mode.to_string(),backup_obb.to_string(),backup_user.to_string(),android_root.to_string(),user_root.to_string(),user_de_root.to_string()];
    let rc=cmd_backup_entry_presence_map(&presence_args); let presence_ms=presence_start.elapsed().as_millis();
    if rc!=0 { println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=presence\trc={}\telapsedMs={}\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",rc,total_start.elapsed().as_millis()); return rc; }

    let payload_start=Instant::now();
    if fs::copy(remote_payload_rels,out_payload_set).is_err() { println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=payload_copy\trc=4\telapsedMs={}\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",total_start.elapsed().as_millis()); return 4; }
    let archive_args=vec![args[0].clone(),"payload-archive-set".to_string(),out_payload_set.to_string(),out_archives.to_string()];
    let rc=cmd_payload_archive_set(&archive_args); let payload_ms=payload_start.elapsed().as_millis();
    if rc!=0 { println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=payload_archive\trc={}\telapsedMs={}\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",rc,total_start.elapsed().as_millis()); return rc; }

    let selected_rows=read_tsv_rows(out_selected);
    let mut live:Vec<(String,String)>=read_tsv_rows(out_exists).into_iter().filter(|r|r.len()>=2).map(|r|(r[0].clone(),r[1].clone())).collect();
    live.sort(); live.dedup();
    let presize_start=Instant::now();
    let rc=run_fastskip_presize_plan_v4_after_facts(
        out_selected,out_summary,out_state,blackset,out_exists,out_archives,out_manifest,out_stats,out_diag,out_tiny,
        backup_mode,backup_obb,backup_user,blacklist_mode,android_root,user_root,user_de_root,
        &selected_rows,&live,presence_ms,payload_ms,presize_total_start,
        "r686-remote-fastskip-presize-plan-v4","speedscan.remote_fastskip_presize_bundle_v1.v1","REMOTE_FASTSKIP_PRESIZE_PLAN_V4"
    );
    let presize_ms=presize_start.elapsed().as_millis();
    if rc!=0 { println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tFAIL\tstage=presize\trc={}\telapsedMs={}\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",rc,total_start.elapsed().as_millis()); return rc; }
    if !rewrite_remote_presize_diag(out_diag) { return 4; }
    let total_ms=total_start.elapsed().as_millis();
    if !append_remote_presize_bundle_stats(out_stats,selected_ms,summary_ms,appstate_ms,presence_ms,payload_ms,presize_ms,total_ms) { return 4; }
    println!("REMOTE_FASTSKIP_PRESIZE_BUNDLE\tOK\tselectedElapsedMs={}\tsummaryElapsedMs={}\tappstateElapsedMs={}\tpresenceElapsedMs={}\tpayloadElapsedMs={}\tpresizeElapsedMs={}\ttotalElapsedMs={}\tprocessStarts=1\tmode=r686\tschema=speedscan.remote_fastskip_presize_bundle_v1.v1",selected_ms,summary_ms,appstate_ms,presence_ms,payload_ms,presize_ms,total_ms);
    0
}

fn orphan_metadata_package(body: &str) -> Option<String> {
    if !appdetails_required_meta_ok(body) { return None; }
    let children: BTreeMap<_, _> = json_object_entries_raw(body.trim_start()).into_iter()
        .map(|(k, v)| (appdetails_meta_key(&k), v)).collect();
    let mut packages = HashSet::new();
    for child in children.values().filter(|v| v.starts_with('{')) {
        let fields: BTreeMap<_, _> = json_object_entries_raw(child).into_iter()
            .map(|(k, v)| (appdetails_meta_key(&k), v)).collect();
        if let Some(raw) = fields.get(&"PackageName".encode_utf16().collect::<Vec<_>>()) {
            let pkg = json_unquote_simple(raw)?;
            if !orphan_plan::package(&pkg) { return None; }
            packages.insert(pkg);
        }
    }
    if packages.len() == 1 { packages.into_iter().next() } else { None }
}

fn cmd_remote_orphan_plan(args: &[String]) -> i32 {
    if args.len() != 8 { return 2; }
    match orphan_plan::run(Path::new(&args[2]), &args[3], &args[4], Path::new(&args[5]),
        Path::new(&args[6]), &args[7], orphan_metadata_package) {
        Ok(summary) => { println!("{}", summary); 0 }
        Err(error) => { eprintln!("REMOTE_ORPHAN_PLAN\tFAIL\t{}", error); 4 }
    }
}

fn cmd_remote_manifest_plan(args: &[String]) -> i32 {
    if args.len() < 6 { return 2; }
    let start = Instant::now();
    let remote_files = &args[2];
    let bundle_root = &args[3];
    let installed_file = &args[4];
    let out_prefix = &args[5];
    let (remote_apps, remote_rels, remote_state) = match appdetails_remote_payload_apps(remote_files) {
        Some((apps, rels)) => (apps, rels, "ok".to_string()),
        None => (HashSet::new(), HashSet::new(), "unavailable".to_string()),
    };
    let bundle_map = appdetails_bundle_pkg_map(bundle_root);
    let bundle_apps: HashSet<String> = bundle_map.keys().cloned().collect();
    let installed = load_installed_pkg_set(installed_file);
    let mut folder_without_appdetails: Vec<String> = remote_apps.iter().filter(|a| !bundle_apps.contains(*a)).cloned().collect();
    folder_without_appdetails.sort();
    let mut orphan_rows: Vec<(String, String, String)> = Vec::new();
    if !installed.is_empty() {
        for app in bundle_apps.iter() {
            let pkg = bundle_map.get(app).cloned().unwrap_or_default();
            if pkg.is_empty() { continue; }
            if !installed.contains(&pkg) && remote_apps.contains(app) {
                orphan_rows.push((app.to_string(), pkg, "package_not_installed".to_string()));
            }
        }
        orphan_rows.sort_by(|a,b| a.0.cmp(&b.0));
    }
    write_set_file(&format!("{}.remote_apps.lst", out_prefix), &remote_apps);
    write_set_file(&format!("{}.remote_payload_rels.lst", out_prefix), &remote_rels);
    write_set_file(&format!("{}.bundle_apps.lst", out_prefix), &bundle_apps);
    write_vec_file(&format!("{}.folder_without_appdetails.lst", out_prefix), &folder_without_appdetails);
    if let Ok(mut f) = File::create(format!("{}.orphan_candidates.tsv", out_prefix)) {
        let _ = writeln!(f, "app\tpackage\treason");
        for (a,p,r) in orphan_rows.iter() {
            let _ = writeln!(f, "{}\t{}\t{}", tsv_sanitize(a), tsv_sanitize(p), tsv_sanitize(r));
        }
    }
    if let Ok(mut f) = File::create(format!("{}.stats", out_prefix)) {
        let _ = writeln!(f, "remoteApps\tremotePayloadRels\tbundleApps\tfolderWithoutAppdetails\torphanCandidates\tinstalledPkgs\tremoteState\telapsedMs");
        let _ = writeln!(f, "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", remote_apps.len(), remote_rels.len(), bundle_apps.len(), folder_without_appdetails.len(), orphan_rows.len(), installed.len(), remote_state, start.elapsed().as_millis());
    }
    println!("REMOTE_MANIFEST_PLAN\tOK\tremoteApps={}\tremotePayloadRels={}\tbundleApps={}\tfolderWithoutAppdetails={}\torphanCandidates={}\tinstalledPkgs={}\tremoteState={}\telapsedMs={}\tmode=r631\tschema=speedbackup.remote_manifest_plan.v1",
        remote_apps.len(), remote_rels.len(), bundle_apps.len(), folder_without_appdetails.len(), orphan_rows.len(), installed.len(), tsv_sanitize(&remote_state), start.elapsed().as_millis());
    0
}

fn cmd_restore_payload_plan(args: &[String]) -> i32 {
    if args.len() < 5 { return 2; }
    let start = Instant::now();
    let app_dir = Path::new(&args[2]);
    let appdetails = &args[3];
    let out_prefix = &args[4];
    let mut apk_count = 0u64;
    let mut split_count = 0u64;
    let mut base_present = false;
    let mut payloads: Vec<String> = Vec::new();
    if let Ok(rd) = fs::read_dir(app_dir) {
        for e in rd.flatten() {
            let p = e.path();
            if !p.is_file() { continue; }
            let name = match p.file_name() { Some(v) => v.to_string_lossy().into_owned(), None => continue };
            if name.ends_with(".apk") {
                apk_count = apk_count.wrapping_add(1);
                if name == "base.apk" || name == "nmsl.apk" { base_present = true; }
                if name.starts_with("split_") { split_count = split_count.wrapping_add(1); }
            }
            if appdetails_is_payload_tail(&name) { payloads.push(name); }
        }
    }
    payloads.sort();
    let apk_kind = if apk_count == 0 { "missing" } else if apk_count == 1 { "single" } else { "split" };
    let mut package = String::new();
    if !appdetails.is_empty() && appdetails != "-" {
        if let Ok(body) = fs::read_to_string(appdetails) {
            package = json_string_value(&body, &["PackageName", "packageName", "package", "pkg"]).unwrap_or_default();
        }
    }
    if let Ok(mut f) = File::create(format!("{}.payloads.tsv", out_prefix)) {
        let _ = writeln!(f, "name");
        for x in payloads.iter() { let _ = writeln!(f, "{}", tsv_sanitize(x)); }
    }
    if let Ok(mut f) = File::create(format!("{}.stats", out_prefix)) {
        let _ = writeln!(f, "package\tapkKind\tapkCount\tsplitCount\tbasePresent\tpayloadCount\telapsedMs");
        let _ = writeln!(f, "{}\t{}\t{}\t{}\t{}\t{}\t{}", tsv_sanitize(&package), apk_kind, apk_count, split_count, if base_present {1}else{0}, payloads.len(), start.elapsed().as_millis());
    }
    println!("RESTORE_PAYLOAD_PLAN\tOK\tpackage={}\tapkKind={}\tapkCount={}\tsplitCount={}\tbasePresent={}\tpayloadCount={}\telapsedMs={}\tmode=r631\tschema=speedbackup.restore_payload_plan_full.v1",
        tsv_sanitize(&package), apk_kind, apk_count, split_count, if base_present {1}else{0}, payloads.len(), start.elapsed().as_millis());
    if apk_count == 0 { 5 } else { 0 }
}

fn cmd_manifest_diff_cache_index(args: &[String]) -> i32 {
    if args.len() < 11 { return 2; }
    let start = Instant::now();
    let selected = &args[2];
    let remote_summary = &args[3];
    let dirsizes = &args[4];
    let payload_set = &args[5];
    let changed = &args[6];
    let out_prefix = &args[7];
    let backup_mode = &args[8];
    let backup_obb = &args[9];
    let backup_user = &args[10];
    let diff_out = format!("{}.diff.tsv", out_prefix);
    let fast_out = format!("{}.fast_skip_ok", out_prefix);
    let missing_out = format!("{}.payload_missing_map", out_prefix);
    let diag_out = format!("{}.diag.tsv", out_prefix);
    let stats_out = format!("{}.stats", out_prefix);
    let selected_rows = read_tsv_rows(selected);
    let remote_rows = read_tsv_rows(remote_summary);
    let dir_rows = read_tsv_rows(dirsizes);
    let payload_rows = read_tsv_rows(payload_set);
    let changed_set = load_line_set(changed);

    let mut r_app: HashSet<String> = HashSet::new();
    let mut rver: HashMap<String,String> = HashMap::new();
    let mut rsize: HashMap<(String,String),String> = HashMap::new();
    for r in remote_rows.iter() {
        if r.len() >= 8 {
            let app = r[0].clone();
            r_app.insert(app.clone());
            rver.insert(app.to_string(), r[2].clone());
            rsize.insert((app.to_string(), "user".into()), r[3].clone());
            rsize.insert((app.to_string(), "user_de".into()), r[4].clone());
            rsize.insert((app.to_string(), "data".into()), r[5].clone());
            rsize.insert((app.to_string(), "obb".into()), r[6].clone());
            rsize.insert((app.to_string(), "media".into()), r[7].clone());
        }
    }
    let mut lsize: HashMap<(String,String),String> = HashMap::new();
    for r in dir_rows.iter() { if r.len() >= 3 { lsize.insert((r[0].clone(), r[1].clone()), r[2].clone()); } }
    let payload: HashSet<String> = payload_rows.iter().filter_map(|r| r.get(0).cloned()).collect();
    let mut diff = match File::create(&diff_out) { Ok(v) => v, Err(_) => return 4 };
    let mut fast = match File::create(&fast_out) { Ok(v) => v, Err(_) => return 4 };
    let mut missing = match File::create(&missing_out) { Ok(v) => v, Err(_) => return 4 };
    let mut diag = match File::create(&diag_out) { Ok(v) => v, Err(_) => return 4 };
    let _ = writeln!(diff, "app\tpackage\tdecision\treason");
    let mut fast_count = 0u64;
    let mut miss_count = 0u64;
    let mut payload_missing = 0u64;
    for r in selected_rows.iter() {
        if r.len() < 4 { continue; }
        let app = &r[0]; let pkg = &r[1]; let nodata = r[2].as_str() == "1"; let cv = &r[3];
        let payload_ok = |entry: &str| -> bool { payload.contains(&format!("{}/{}.tar.zst", app, entry)) || payload.contains(&format!("{}/{}.tar", app, entry)) };
        let mut ok = true;
        let mut reason = "unchanged".to_string();
        if !r_app.contains(app) { ok = false; reason = "remote_json_missing".to_string(); }
        else if changed_set.contains(app) || changed_set.contains(pkg) { ok = false; reason = "changed_prescan".to_string(); }
        else {
            let rv = rver.get(app).cloned().unwrap_or_default();
            if cv.is_empty() { ok = false; reason = "current_version_missing".to_string(); }
            else if rv.is_empty() || rv != *cv { ok = false; reason = "apk_version_mismatch".to_string(); }
            else if !payload_ok("apk") { ok = false; reason = "apk_payload_missing".to_string(); }
        }
        let mut check_entry = |entry: &str, ok_ref: &mut bool, reason_ref: &mut String| {
            if !*ok_ref { return; }
            let key = (pkg.to_string(), entry.to_string());
            let cur = match lsize.get(&key) { Some(v) => v.clone(), None => return };
            if !cur.chars().all(|c| c.is_ascii_digit()) { *ok_ref = false; *reason_ref = format!("local_size_invalid_{}", entry); return; }
            if cur.len() < 4 { return; }
            let old = rsize.get(&(app.to_string(), entry.to_string())).cloned().unwrap_or_default();
            if old.is_empty() || old == "null" || old != cur { *ok_ref = false; *reason_ref = format!("size_mismatch_{}", entry); return; }
            if !payload_ok(entry) {
                let rel = format!("{}/{}.tar.zst", app, entry);
                let _ = writeln!(missing, "{}\t{}\t{}\t{}", tsv_sanitize(app), tsv_sanitize(pkg), entry, tsv_sanitize(&rel));
                payload_missing += 1;
                *ok_ref = false; *reason_ref = format!("payload_missing_{}", entry);
            }
        };
        if backup_mode == "true" && !nodata && pkg != "bin.mt.plus" {
            if backup_obb == "true" { check_entry("data", &mut ok, &mut reason); check_entry("obb", &mut ok, &mut reason); check_entry("media", &mut ok, &mut reason); }
            if backup_user == "true" { check_entry("user", &mut ok, &mut reason); check_entry("user_de", &mut ok, &mut reason); }
        }
        if ok {
            let _ = writeln!(fast, "{}", tsv_sanitize(app));
            let _ = writeln!(diff, "{}\t{}\tskip\t{}", tsv_sanitize(app), tsv_sanitize(pkg), reason);
            fast_count += 1;
        } else {
            let _ = writeln!(diff, "{}\t{}\tchanged\t{}", tsv_sanitize(app), tsv_sanitize(pkg), tsv_sanitize(&reason));
            let _ = writeln!(diag, "{}\t{}\t{}", tsv_sanitize(app), tsv_sanitize(pkg), tsv_sanitize(&reason));
            miss_count += 1;
        }
    }
    if let Ok(mut st) = File::create(&stats_out) {
        let _ = writeln!(st, "{}\t{}\t{}\t{}\t{}\t{}\t{}", selected_rows.len(), remote_rows.len(), dir_rows.len(), payload_rows.len(), fast_count, miss_count, payload_missing);
    }
    println!("MANIFEST_DIFF_CACHE_INDEX\tOK\tselected={}\tremote={}\tdirRows={}\tpayloadRows={}\tfastSkip={}\tmiss={}\tpayloadMissing={}\telapsedMs={}\tmode=r631\tschema=speedbackup.manifest_diff_cache_index.v2",
        selected_rows.len(), remote_rows.len(), dir_rows.len(), payload_rows.len(), fast_count, miss_count, payload_missing, start.elapsed().as_millis());
    0
}

fn argv_utf8_or_exit() -> Vec<String> {
    let mut out = Vec::new();
    for (idx, arg) in crate::multicall::args_os().enumerate() {
        match arg.into_string() {
            Ok(s) => out.push(s),
            Err(_) => {
                eprintln!("speedscan: argv[{}] contains non-UTF-8 bytes; refusing cleanly instead of panicking", idx);
                std::process::exit(2);
            }
        }
    }
    out
}

pub(crate) fn run(){let args:Vec<String>=argv_utf8_or_exit();let rc=match args.get(1).map(|s|s.as_str()){
Some("--version")|Some("version")=>{println!("speedscan {}",VERSION);0}
        Some("--capabilities") | Some("capabilities") => {
            println!("speedscan.backup_run_model.v1 speedscan.backup_plan_coverage.v1 speedscan.tree_fixup_symlink_owner.v1 speedscan.tar_source_manifest.v1 speedscan.restore_source_verify.v1 speedscan.payload_stats.v1 speedscan.restore_tree_audit_bytes.v1 speedscan.result_contract.v1 speedscan.remote_orphan_plan.v1 speedscan.restore_tree_manifest_bytes.v1 speedscan.appdetails_seed_index_strict_meta.v1 speedscan.appdetails_seed_index.v1 speedscan.backup_prescan_exact_input_batch.v1 speedscan.tar_input_hardlink_type_safe.v1 speedscan.dir_size_tar_input_map.v1 speedscan.tree_pack_plan.v1 speedscan.restore_tree_verify.v1 speedscan.app_media_index.v1 speedscan.posix_recursive_scan.v1 speedscan.dir_size_map_workers.v1 speedscan.dir_size_map_nested_singlepass.v1 speedscan.dir_size_map_v2.v1 speedscan.dir_size_map_profiler.v1 speedscan.dir_size_map_workers8_cap.v1 speedscan.dir_size_map_workers24_cap.v1 speedscan.tsv_decimal_sum.v1 speedscan.entry_size_facts.v1 speedscan.changed_entry_facts.v1 speedscan.local_fastskip_join.v1 speedscan.local_fastskip_join_stats_v2.v1 speedscan.local_fastskip_presize_plan.v1 speedscan.local_fastskip_presize_plan_v2.v1 speedscan.local_fastskip_presize_plan_v3.v1 speedscan.local_fastskip_presize_plan_v4.v1 speedscan.local_fastskip_presize_bundle_v1.v1 speedscan.remote_fastskip_presize_bundle_v1.v1 speedscan.backup_entry_presence_map.v1 speedscan.payload_archive_set.v1 speedscan.dir_size_manifest.v1 speedscan.dir_size_worker_scanroots.v1 speedscan.dir_size_map_route_trie.v1 speedscan.dir_size_map_hint_schedule.v1 speedscan.remote_stream_local_read_plan.v1 speedscan.remote_stream_local_read_plan.v2 speedscan.remote_stream_local_read_final_plan.v1 speedscan.stream_entry_perf_resolver.v1 speedscan.stream_entry_perf_child_elapsed.v1 speedscan.stream_entry_post_body_semantics.v1 speedscan.argv_non_utf8_clean_fail.v1 speedscan.appdetails_bundle_audit.v1 speedscan.appdetails_bundle_audit_seedless_stage_cover.v1 speedscan.appdetails_bundle_audit_scoped_cover.v1 speedscan.appdetails_bundle_audit_seedless_taint.v1 speedscan.appdetails_bundle_audit_seed_expansion.v1 speedscan.appdetails_bundle_manifest.v1 speedscan.appdetails_health_batch.v1 speedscan.remote_manifest_plan.v1 speedscan.restore_payload_plan.v1 speedscan.manifest_diff_cache_index.v1 speedscan.manifest_diff_cache_index.v2 speedscan.selected_apps_map.v1 speedscan.appdetails_summary_map.v1 speedscan.appstate_match_map.v1 speedscan.appstate_match_canonical_v2.v1 speedscan.appstate_match_canonical_v3.v1 speedscan.appstate_match_canonical_v4.v1 speedscan.remote_orphan_candidates.v1 speedscan.restore_payload_plan_full.v1 speedscan.full_convergence_stage4.v1 speedscan.full_convergence_stage5.v1 speedscan.rust_convergence_source.v1 speedscan.full_convergence_stage3.v1");
            0
        }
Some("dir-size") if args.len()>=3=>cmd_dir_size(&args[2]),
Some("dir-size-map") if args.len()>=3=>cmd_dir_size_map(&args[2]),
Some("dir-size-manifest") if args.len()>=11=>cmd_dir_size_manifest(&args),
Some("tsv-decimal-sum") if args.len()>=4=>cmd_tsv_decimal_sum(&args[2],&args[3]),
Some("file-list") if args.len()>=3=>cmd_file_list(&args[2]),
Some("list-total-size") if args.len()>=3=>cmd_list_total_size(&args[2]),
Some("batch-stat") if args.len()>=3=>cmd_batch_stat(&args[2]),
Some("batch-exists") if args.len()>=3=>cmd_batch_exists(&args[2]),
Some("batch-chmod") if args.len()>=4=>cmd_batch_chmod(&args[2],&args[3]),
Some("batch-chown") if args.len()>=5=>cmd_batch_chown(&args[2],&args[3],&args[4]),
Some("tree-chown") if args.len()>=5=>cmd_tree_chown(&args[2],&args[3],&args[4]),
Some("tree-fixup") if args.len()>=5=>cmd_tree_fixup(&args[2],&args[3],&args[4],args.get(5).map(|s|s.as_str()).unwrap_or("-"),args.get(6).map(|s|s.as_str()).unwrap_or("-")),
Some("has-files") if args.len()>=3=>cmd_has_files(&args[2]),
Some("manifest") if args.len()>=4=>write_manifest(&args[2],&args[3]),
Some("scan-summary") if args.len()>=3=>cmd_scan_summary(&args[2],args.get(3).map(|s|s.as_str()),"SCAN"),
Some("path-audit") if args.len()>=4=>cmd_path_audit(&args[2],&args[3]),
Some("label-audit") if args.len()>=3=>cmd_label_audit(&args[2],args.get(3).map(|s|s.as_str())),
Some("facts") if args.len()>=3=>cmd_facts(&args[2],args.get(3).map(|s|s.as_str())),
Some("restore-facts") if args.len()>=3=>cmd_facts(&args[2],args.get(3).map(|s|s.as_str())),
Some("appdetails-index") if args.len()>=4=>cmd_appdetails_index(&args[2],&args[3],args.get(4).map(|s|s.as_str()),args.get(5).map(|s|s.as_str())),
Some("file-list-abs-filter") if args.len()>=5=>cmd_file_list_abs_filter(&args[2],&args[3],&args[4],args.get(5).map(|s|s.as_str())),
Some("selected-list") if args.len()>=6=>cmd_selected_list(&args[2],&args[3],&args[4],&args[5]),
Some("apk-size-map") if args.len()>=4=>cmd_apk_size_map(&args[2],&args[3]),
Some("backup-prescan-exact-input") if args.len()>=7=>cmd_backup_prescan_exact_input(&args[2],&args[3],&args[4],&args[5],&args[6]),
Some("backup-prescan-summary") if args.len()>=10=>cmd_backup_prescan_summary(&args[2],&args[3],&args[4],&args[5],&args[6],&args[7],&args[8],&args[9]),
Some("backup-root-index") if args.len()>=4=>cmd_backup_root_index(&args[2],&args[3],args.get(4).map(|s|s.as_str())),
Some("storage-summary") if args.len()>=3=>cmd_storage_summary(&args[2]),
Some("checksum-list") if args.len()>=4=>cmd_checksum_list(&args[2],&args[3]),
Some("manifest-verify") if args.len()>=4=>cmd_manifest_verify(&args[2],&args[3],false),
Some("run-tmpdir-facts") if args.len()>=4=>cmd_run_tmpdir_facts(&args[2],&args[3],args.get(4).map(|s|s.as_str())),
Some("zst-file-facts") if args.len()>=3=>cmd_zst_file_facts(&args[2]),
Some("tree-pack-plan") if args.len()>=4=>cmd_tree_pack_plan(&args[2],&args[3],args.get(4).map(|s|s.as_str()).unwrap_or("-"),args.get(5).map(|s|s.as_str())),
Some("entry-size-facts") if args.len()>=4=>cmd_entry_size_facts(&args[2],&args[3],args.get(4).map(|s|s.as_str()).unwrap_or("-"),args.get(5).map(|s|s.as_str())),
Some("changed-entry-facts") if args.len()>=4=>cmd_changed_entry_facts(&args[2],&args[3]),
Some("local-fastskip-join") if args.len()>=16=>cmd_local_fastskip_join(&args),
Some("local-fastskip-presize-bundle-v1") if args.len()>=24=>cmd_local_fastskip_presize_bundle_v1(&args),
Some("remote-fastskip-presize-bundle-v1") if args.len()>=25=>cmd_remote_fastskip_presize_bundle_v1(&args),
Some("local-fastskip-presize-plan-v4") if args.len()>=20=>cmd_local_fastskip_presize_plan_v4(&args),
Some("local-fastskip-presize-plan") if args.len()>=18=>cmd_local_fastskip_presize_plan(&args),
Some("backup-entry-presence-map") if args.len()>=10=>cmd_backup_entry_presence_map(&args),
Some("payload-archive-set") if args.len()>=4=>cmd_payload_archive_set(&args),
Some("remote-stream-local-read-plan") if args.len()>=11=>cmd_remote_stream_local_read_plan(&args),
Some("remote-stream-local-read-plan-v2") if args.len()>=9=>cmd_remote_stream_local_read_plan_v2(&args),
Some("remote-stream-local-read-final-plan") if args.len()>=12=>cmd_remote_stream_local_read_final_plan(&args),
Some("stream-entry-perf-stage") if args.len()>=13=>cmd_stream_entry_perf_stage(&args),
Some("stream-entry-perf-finalize") if args.len()>=4=>cmd_stream_entry_perf_finalize(&args),
Some("restore-tree-verify") if args.len()>=4=>cmd_manifest_verify(&args[2],&args[3],true),
Some("restore-tree-manifest-bytes") if args.len()>=4=>restore_manifest::unix::command(&args[2],&args[3],false),
Some("restore-tree-verify-bytes") if args.len()>=4=>restore_manifest::unix::command(&args[2],&args[3],true),
Some("app-media-index") if args.len()>=4=>cmd_app_media_index(&args[2],&args[3],args.get(4).map(|s|s.as_str()),args.get(5).map(|s|s.as_str()),args.get(6).map(|s|s.as_str()).unwrap_or("-")),
Some("selected-apps-map") if args.len()>=5=>cmd_selected_apps_map(&args),
Some("appdetails-summary-map") if args.len()>=4=>cmd_appdetails_summary_map(&args),
	Some("appstate-match-map") if args.len()>=5=>cmd_appstate_match_map(&args),
Some("appdetails-bundle-audit") if args.len()>=8=>cmd_appdetails_bundle_audit(&args),
Some("appdetails-health-batch") if args.len()>=5=>cmd_appdetails_health_batch(&args),
Some("appdetails-bundle-manifest") if args.len()>=4=>cmd_appdetails_bundle_manifest(&args),
Some("appdetails-seed-index") if args.len()>=5=>cmd_appdetails_seed_index(&args),
Some("tar-source-manifest") if args.len() == 3 => tar_source::capture_command(&args[2]),
Some("restore-source-verify") if args.len() == 7 => tar_source::verify_command(&args[2], &args[3], &args[4], &args[5], &args[6]),
Some("backup-run-summary") => backup_run::command(&args),
Some("payload-stats" | "payload-metrics") => payload_stats::command(&args),
Some("restore-tree-audit-bytes") if args.len() == 4 => restore_manifest::unix::audit(&args[2], &args[3]),
Some("remote-orphan-plan") => cmd_remote_orphan_plan(&args),
Some("remote-manifest-plan") if args.len()>=6=>cmd_remote_manifest_plan(&args),
Some("restore-payload-plan") if args.len()>=5=>cmd_restore_payload_plan(&args),
Some("manifest-diff-cache-index") if args.len()>=11=>cmd_manifest_diff_cache_index(&args),
_=>{usage();2}};std::process::exit(rc)}
