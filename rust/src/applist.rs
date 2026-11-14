pub(super) const HOST_PACKAGE: &str = "io.github.yawasau.speedbackup.webview";

use std::collections::{BTreeMap, BTreeSet};
use std::fs::OpenOptions;
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;

fn package(value: &str) -> bool {
    value.len() <= 255 && value.contains('.') && value.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
        && value.split('.').all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'_'))
}

// PackageManager may expose dotless platform resource packages (android,
// oplus). Accept them only as installed facts, never as actionable app rows.
fn installed_package(value: &str) -> bool {
    package(value) || (value.len() <= 255 && value.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
        && value.bytes().all(|byte| byte.is_ascii_alphanumeric() || byte == b'_'))
}

fn comment(line: &str) -> bool {
    line.trim_start().starts_with(['#', '＃', '!', '！'])
}

fn read(path: &str) -> Result<String, String> {
    let mut file = OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK).open(path).map_err(|error| error.to_string())?;
    let metadata = file.metadata().map_err(|error| error.to_string())?;
    if !metadata.is_file() || metadata.len() > 16 * 1024 * 1024 { return Err("invalid input file".into()); }
    let mut bytes = Vec::new();
    Read::by_ref(&mut file).take(16 * 1024 * 1024 + 1).read_to_end(&mut bytes).map_err(|error| error.to_string())?;
    if bytes.len() > 16 * 1024 * 1024 || bytes.contains(&0) { return Err("oversize or NUL input".into()); }
    String::from_utf8(bytes).map_err(|_| "invalid UTF-8".into())
}

fn preload(pkg: &str) -> bool {
    ["com.oneplus.", "com.miui.", "com.xiaomi.", "com.oppo.", "com.flyme.", "com.meizu.", "com.coloros."].iter().any(|prefix| pkg.starts_with(prefix))
        || ["com.android.soundrecorder", "com.mfashiongallery.emag", "com.mi.health", "com.duokan.phone.remotecontroller", "com.android.calendar", "com.android.deskclock", "com.google.android.safetycore", "com.google.android.contactkeys", "com.google.android.apps.messaging", "com.google.android.calendar"].contains(&pkg)
}

fn configured_packages(value: &str) -> BTreeSet<&str> {
    value.lines().flat_map(|line| line.split_whitespace().take_while(|token| !comment(token)))
        .filter(|token| package(token)).collect()
}

fn safe_label(label: &str, pkg: &str) -> String {
    let source = if ["media", "log", "tools", "wifi", "communications"].contains(&label.to_ascii_lowercase().as_str()) { format!("app_{label}") } else { label.to_string() };
    let mut value = source.chars().map(|ch| if ch.is_whitespace() || ch.is_control() || "/\\:\"`$;|&()<>!*?[]{}'=#~^".contains(ch) { '_' } else { ch }).collect::<String>().replace("..", "__");
    if value.is_empty() || value == "." { value = if pkg.is_empty() { "app" } else { pkg }.to_string(); }
    value
}

// Legacy generated labels such as I'mPad are literal directory names. Keep
// their spelling and selection; only newly generated labels are normalized.
fn existing_label(label: &str, pkg: &str) -> bool {
    let checked = label.replace('\'', "_");
    !label.is_empty() && safe_label(&checked, pkg) == checked
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inventory() -> String {
        "#META\tinventoryBegin\t1\t0\n#META\tinstalled\tcom.test.app\n#META\tinstalled\tcom.android.system\n#META\tdefaultHome\t\t\tnone\n#META\tdefaultIme\t\t\tnone\nApp com.test.app user\n#META\tinventoryEnd\t0\t2\t1\n".into()
    }

    #[test]
    fn incomplete_module_scan_does_not_abort_or_silently_select() {
        let data=inventory().replace("com.test.app", "com.oplus.apprecover").replace("App com.oplus.apprecover user", "App com.oplus.apprecover system|xposed-unknown");
        let report=merge_report("",&data,"","","true","0").unwrap();
        assert!(report.text.contains("#App com.oplus.apprecover"));assert_eq!(report.count,0);
        let active=merge_report("App com.oplus.apprecover\n",&data,"","","true","0").unwrap();
        assert_eq!(active.count,1);assert!(active.text.starts_with("App "));
        let white=merge_report("",&data,"com.oplus.apprecover","","true","0").unwrap();assert_eq!(white.count,1);
        assert!(merge_report("",&data.replace("inventoryEnd","broken"),"","","true","0").is_err());
    }

    #[test]
    fn stale_default_roles_do_not_abort_valid_inventory() {
        for role in ["defaultHome", "defaultIme"] {
            let data = inventory().replace(&format!("{role}\t\t"), &format!("{role}\tcom.removed.app\t"));
            let report = merge_report("", &data, "", "", "true", "0").unwrap();
            assert_eq!(report.count, 1);
            assert!(report.home.is_empty() && report.ime.is_empty());
            assert!(!report.text.contains("com.removed.app"));
            let profile = data.replace("inventoryBegin\t1\t0", "inventoryBegin\t1\t999")
                .replace("inventoryEnd\t0", "inventoryEnd\t999");
            assert!(merge_report("", &profile, "", "", "true", "999").is_ok());
            let broken = data.replace("com.removed.app", "com.android.system");
            assert!(merge_report("", &broken, "", "", "true", "0").is_err());
        }
    }

    #[test]
    fn host_is_excluded_from_generated_and_existing_rows() {
        let inv = inventory().replace("#META\tinstalled\tcom.test.app\n", &format!("#META\tinstalled\t{}\n#META\tinstalled\tcom.test.app\n", HOST_PACKAGE))
            .replace("App com.test.app user", &format!("SpeedBackup {} user\nApp com.test.app user", HOST_PACKAGE))
            .replace("inventoryEnd\t0\t2\t1", "inventoryEnd\t0\t3\t2");
        for old in [String::new(), format!("SpeedBackup {}\n", HOST_PACKAGE), format!("#SpeedBackup {}\n", HOST_PACKAGE), format!("!SpeedBackup {}\n", HOST_PACKAGE)] {
            let report = merge_report(&old, &inv, HOST_PACKAGE, "", "true", "0").unwrap();
            assert!(!report.text.contains(HOST_PACKAGE));
            assert!(!report.events.contains(HOST_PACKAGE));
            assert_eq!(report.count, 1);
        }
    }
    #[test]
    fn legacy_apostrophe_label_keeps_name_and_selection() {
        for row in ["I'mPad com.test.app", "#I'mPad com.test.app", "!I'mPad com.test.app"] {
            let old=format!("# user note\n{row}\n");
            assert_eq!(merge(&old,&inventory(),"","","true","0").unwrap().0,old);
        }
        assert!(!existing_label("a$(id)","com.test.app"));
        assert!(!existing_label("../a","com.test.app"));
    }

    #[test]
    fn dotless_platform_inventory_does_not_relax_actionable_rows() {
        let data = inventory().replace("#META\tinstalled\tcom.test.app\n", "#META\tinstalled\toplus\n#META\tinstalled\tcom.test.app\n")
            .replace("inventoryEnd\t0\t2\t1", "inventoryEnd\t0\t3\t1");
        assert_eq!(merge("", &data, "", "", "true", "0").unwrap().0,
            merge("", &inventory(), "", "", "true", "0").unwrap().0);
        let selected = data.replace("App com.test.app user", "App oplus user");
        assert!(merge("", &selected, "", "", "true", "0").is_err());
        for bad in ["../oplus", "oplus/", "$oplus", "1oplus", "", "oplus..core"] {
            assert!(merge("", &data.replace("installed\toplus\n", &format!("installed\t{bad}\n")), "", "", "true", "0").is_err());
        }
    }

    #[test]
    fn vendor_names_require_namespace_boundary() {
        for pkg in ["com.example.opportunity", "com.example.miui", "com.miuihelper.app", "org.example.xiaomi.tool"] {
            assert!(!preload(pkg));
        }
        for pkg in ["com.miui.home", "com.oppo.camera", "com.android.calendar"] { assert!(preload(pkg)); }
    }

    #[test]
    fn configuration_comments_do_not_classify() {
        assert!(configured_packages("# disabled com.test.app\n＃ com.other.app\n! com.third.app").is_empty());
        assert_eq!(configured_packages("com.test.app # disabled com.other.app\n").len(), 1);
        let report = merge_report("", &inventory(), "", "# disabled com.test.app\ncom.other.active", "true", "0").unwrap();
        assert!(report.text.contains("App com.test.app"));
        let data = inventory().replace("com.test.app", "com.miui.fixture");
        let report = merge_report("", &data, "# disabled com.miui.fixture", "", "true", "0").unwrap();
        assert!(report.events.contains("PRELOAD"));
        assert!(!report.events.contains("PRELOAD_WL"));
    }

    #[test]
    fn system_outside_selected_preserved() {
        let (text, count, removed) = merge("System com.android.system\nGone com.gone.app\n", &inventory(), "", "", "true", "0").unwrap();
        assert!(text.contains("System com.android.system"));
        assert!(!text.contains("com.gone.app"));
        assert_eq!((count, removed), (2, 1));
    }

    #[test]
    fn prose_and_choices_preserved_but_missing_disabled_record_pruned() {
        let old = "#說明\n# 說明 com.gone.app\n\n＃舊 com.gone.app\n!停用 com.test.app\n";
        let report=merge_report(old, &inventory(), "", "", "true", "0").unwrap();
        // old_count counts unprefixed inputs; removed also reports disabled rows.
        // Shell validates numeric fields, not an active-minus-all-removed equation.
        assert_eq!((report.count,report.removed,report.old_count,report.added),(0,1,0,0));
        assert_eq!(merge(old, &inventory(), "", "", "true", "0").unwrap().0, "#說明\n# 說明 com.gone.app\n\n!停用 com.test.app\n");
    }

    #[test]
    fn framework_package_is_valid_inventory_member() {
        let data = inventory().replace("#META\tinstalled\tcom.android.system", "#META\tinstalled\tandroid");
        assert!(merge("", &data, "", "", "true", "0").is_ok());
    }

    #[test]
    fn malformed_inventories_fail() {
        let valid = inventory();
        for invalid in [valid.replace("inventoryEnd", "truncated"), valid.replace("\t2\t1", "\t3\t1"), valid.replace("\t1\t0", "\t1\t10"), valid.clone() + "noise\n", String::new(), valid.replace("App com.test.app user", "App com.missing.app user")] {
            assert!(merge("Old com.old.app\n", &invalid, "", "", "true", "0").is_err());
        }
    }

    #[test]
    fn invalid_old_rows_do_not_publish() {
        for old in ["bad\n", "Name com.test.app extra\n", "one com.test.app\ntwo com.test.app\n", "$(bad) com.test.app\n"] {
            assert!(merge(old, &inventory(), "", "", "true", "0").is_err());
        }
    }

    #[test]
    fn invalid_old_rows_identify_line_and_field_without_echoing_input() {
        for (row, reason) in [("bad", "兩個欄位"), ("Name invalid", "包名格式"), ("$(secret) com.test.app", "應用名稱")] {
            let error=merge(&format!("# note\n\n{row}\n"), &inventory(), "", "", "true", "0").unwrap_err();
            assert!(error.contains("第 3 行") && error.contains(reason), "{error}");
            assert!(!error.contains("secret"));
        }
    }

    #[test]
    fn same_label_different_packages_preserved() {
        let old = "Same com.test.app\nSame com.android.system\n";
        let (text, count, removed) = merge(old, &inventory(), "", "", "true", "0").unwrap();
        assert!(text.contains("Same_1 com.test.app\n"));
        assert!(text.contains("Same com.android.system\n"));
        assert_eq!((count, removed), (2, 0));
        assert_eq!(merge(&text, &inventory(), "", "", "true", "0").unwrap().0, text);
    }

    #[test]
    fn duplicate_exact_active_collapsed() {
        assert_eq!(merge("App com.test.app\nApp com.test.app\n", &inventory(), "", "", "true", "0").unwrap().1, 1);
    }

    #[test]
    fn commented_home_stays_disabled() {
        let data = inventory().replace("defaultHome\t\t", "defaultHome\tcom.test.app\t");
        let text = merge("#App com.test.app\nSystem com.android.system\n", &data, "", "com.test.app", "true", "0").unwrap().0;
        assert!(text.starts_with("#App com.test.app\n"));
        assert!(!text.lines().any(|l|l=="App com.test.app"));
    }

    #[test]
    fn blacklist_and_label_safety() {
        assert_eq!(merge("", &inventory(), "", "com.test.app", "true", "0").unwrap().1, 0);
        assert_eq!(merge("", &inventory(), "", "com.test.app", "false", "0").unwrap().1, 1);
        assert_eq!(safe_label("Media", "com.test.app"), "app_Media");
        assert_eq!(safe_label("a$(x)/..", "com.test.app"), "a__x____");
    }
}

#[cfg(test)]
pub fn merge(old: &str, inventory: &str, whitelist: &str, blacklist: &str, mode: &str, user: &str) -> Result<(String, usize, usize), String> {
    let result = merge_report(old, inventory, whitelist, blacklist, mode, user)?;
    Ok((result.text, result.count, result.removed))
}

struct MergeReport {
    text: String,
    count: usize,
    removed: usize,
    events: String,
    home: String,
    ime: String,
    quantity: usize,
    old_count: usize,
    added: usize,
    missing: String,
    blacklist_enabled: bool,
}

// Preserve selection/APK prefixes, but ensure package-distinct rows cannot share
// a backup directory. Reserve every existing label before allocating suffixes.
fn disambiguate_labels(text: &str, home: &str) -> String {
    let mut groups = BTreeMap::<String, BTreeMap<String, bool>>::new();
    let mut reserved = BTreeSet::new();
    for line in text.lines() {
        let fields: Vec<_> = line.split_whitespace().collect();
        if fields.len() != 2 || !package(fields[1]) { continue; }
        let label = fields[0].trim_start_matches(['#', '＃', '!', '！']);
        if !existing_label(label, fields[1]) { continue; }
        reserved.insert(label.to_string());
        let inactive = fields[0].starts_with(['#', '＃']);
        groups.entry(label.to_string()).or_default().entry(fields[1].to_string())
            .and_modify(|old| *old &= inactive).or_insert(inactive);
    }
    let mut replacements = BTreeMap::new();
    for (label, packages) in groups {
        let mut packages: Vec<_> = packages.into_iter().collect();
        packages.sort_by(|a, b| a.1.cmp(&b.1).then(a.0.cmp(&b.0)));
        for (pkg, _) in packages.into_iter().skip(1) {
            let mut suffix = 1;
            let replacement = loop {
                let candidate = format!("{label}_{suffix}");
                if reserved.insert(candidate.clone()) { break candidate; }
                suffix += 1;
            };
            replacements.insert((label.clone(), pkg), replacement);
        }
    }
    let mut result = String::new();
    for line in text.lines() {
        let fields: Vec<_> = line.split_whitespace().collect();
        if fields.len() == 2 {
            let label = fields[0].trim_start_matches(['#', '＃', '!', '！']);
            if let Some(replacement) = replacements.get(&(label.to_string(), fields[1].to_string())) {
                let offset = line.len() - line.trim_start().len() + fields[0].len() - label.len();
                result.push_str(&line[..offset]);
                result.push_str(replacement);
                result.push_str(&line[offset + label.len()..]);
                result.push('\n');
                continue;
            }
        }
        result.push_str(line);
        result.push('\n');
    }
    // Renaming may change lexical order; sort final active rows now so the
    // next generation is byte-stable, preserving comments and HOME-last.
    let mut comments = Vec::new();
    let mut active = Vec::new();
    let mut home_line = None;
    for line in result.lines() {
        if line.trim().is_empty() || comment(line) { comments.push(line); }
        else if line.split_whitespace().nth(1) == Some(home) { home_line = Some(line); }
        else { active.push(line); }
    }
    active.sort();
    comments.extend(active);
    if let Some(line) = home_line { comments.push(line); }
    comments.join("\n") + "\n"
}

fn merge_report(old: &str, inventory: &str, whitelist: &str, blacklist: &str, mode: &str, user: &str) -> Result<MergeReport, String> {
    if !matches!(mode, "true" | "false") || user.parse::<u32>().is_err() { return Err("invalid mode/user".into()); }
    let mut unknown = BTreeSet::new();
    let mut installed = BTreeSet::new();
    let mut selected = BTreeMap::new();
    let mut home = String::new();
    let mut ime = String::new();
    let mut begin = false;
    let mut end = false;
    for line in inventory.lines() {
        if end { return Err("trailing inventory data".into()); }
        let fields: Vec<_> = line.split('\t').collect();
        if fields.first() == Some(&"#META") {
            match fields.get(1).copied() {
                Some("inventoryBegin") if fields.len() == 4 && fields[2] == "1" && fields[3] == user && !begin => begin = true,
                Some("installed") if begin && fields.len() == 3 && installed_package(fields[2]) => {
                    if !installed.insert(fields[2].to_string()) { return Err("duplicate installed package".into()); }
                }
                Some("defaultHome") | Some("defaultIme") if begin && fields.len() == 5 => {
                    if !fields[2].is_empty() && !package(fields[2]) { return Err("invalid default package".into()); }
                    if fields[1] == "defaultHome" { home = fields[2].into(); } else { ime = fields[2].into(); }
                }
                Some("inventoryEnd") if begin && fields.len() == 5 && fields[2] == user => {
                    if fields[3].parse::<usize>().ok() != Some(installed.len()) || fields[4].parse::<usize>().ok() != Some(selected.len()) { return Err("inventory count mismatch".into()); }
                    end = true;
                }
                Some("xposedFramework" | "xposedModules" | "xposedModule") if begin => {}
                _ => return Err("invalid inventory frame".into()),
            }
        } else {
            let row: Vec<_> = line.split_whitespace().collect();
            if !begin || row.len() != 3 || !package(row[1]) || !installed.contains(row[1]) { return Err("invalid inventory row".into()); }
            if row[2].split('|').any(|flag|flag=="xposed-unknown"){unknown.insert(row[1].to_string());}
            let label = row[0].replace(['/', '\\', ':'], "_").replace("..", "__");
            if selected.insert(row[1].to_string(), (label, row[2].split('|').any(|flag| flag == "xposed"))).is_some() { return Err("duplicate selected package".into()); }
        }
    }
    if !begin || !end || installed.is_empty() { return Err("incomplete or empty inventory".into()); }
    // Per-user settings may retain an uninstalled IME or reference a HOME
    // belonging to another profile. These are optional role hints, not rows.
    // An installed default omitted by the producer is still corruption.
    for default in [&mut home, &mut ime] {
        if !default.is_empty() && !installed.contains(default.as_str()) {
            default.clear();
        } else if !default.is_empty() && !selected.contains_key(default.as_str()) {
            return Err("missing installed default package".into());
        }
    }
    let white = configured_packages(whitelist);
    let black = configured_packages(blacklist);
    let blacklist_enabled = !black.is_empty();
    let mut active = BTreeMap::<String, String>::new();
    let mut comments = Vec::new();
    let mut commented = BTreeSet::new();
    let mut labels = BTreeSet::new();
    let mut removed = 0;
    let mut missing = String::new();
    let mut events = String::new();
    let mut old_count = 0;
    for (index, line) in old.lines().enumerate() {
        if line.split_whitespace().last() == Some(HOST_PACKAGE) { continue; }
        if line.trim().is_empty() || comment(line) {
            if let Some(last) = line.split_whitespace().last() { if package(last) {
                let body=line.trim_start().trim_start_matches(['#','＃']).trim_start();
                if !line.trim_start().trim_start_matches(['#','＃']).starts_with(char::is_whitespace) && body.split_whitespace().count()==2 && !installed.contains(last) {removed+=1;missing.push_str(body);missing.push('\n');continue;}
                commented.insert(last.to_string());
            } }
            comments.push(line.to_string());
            continue;
        }
        let fields: Vec<_> = line.split_whitespace().collect();
        let line_number = index + 1;
        if fields.len() != 2 { return Err(format!("清單第 {line_number} 行：應為「應用名稱 包名」兩個欄位，實際有 {} 個欄位", fields.len())); }
        if !package(fields[1]) { return Err(format!("清單第 {line_number} 行：包名格式無效，請檢查第二個欄位")); }
        if !existing_label(fields[0], fields[1]) { return Err(format!("清單第 {line_number} 行：應用名稱含不支援的路徑或命令字元，請檢查第一個欄位")); }
        // Package names identify existing rows; display labels may be shared.
        labels.insert(fields[0].to_string());
        old_count += 1;
        if !installed.contains(fields[1]) { removed += 1; missing.push_str(line); missing.push('\n'); continue; }
        if let Some(previous) = active.insert(fields[1].into(), line.to_string()) {
            if previous != line { return Err(format!("清單第 {line_number} 行：同一包名出現不同名稱或選擇狀態，請移除重複項目")); }
        }
    }
    let mut candidates: Vec<_> = selected.into_iter().collect();
    candidates.sort_by(|left, right| left.1.0.cmp(&right.1.0).then(left.0.cmp(&right.0)));
    let mut quantity = 0;
    let mut added = 0;
    for (pkg, (label, xposed)) in candidates {
        if pkg == HOST_PACKAGE || pkg == "ice.message" || pkg == "com.topjohnwu.magisk" { continue; }
        let label = safe_label(&label, &pkg);
        quantity += 1;
        if active.contains_key(&pkg) {
            events.push_str(&format!("EXIST\t{label}\t{pkg}\n"));
            continue;
        }
        let force = pkg == home || pkg == ime;
        if commented.contains(&pkg) {
            events.push_str(&format!("EXIST_CMT\t{label}\t{pkg}\n"));
            continue;
        }
        let mut final_label = label.clone();
        let mut suffix = 1;
        while labels.contains(&final_label) {
            final_label = format!("{label}_{suffix}");
            suffix += 1;
        }
        labels.insert(final_label.clone());
        let kind = if pkg == home && pkg == ime { "HOME_IME" }
            else if pkg == home { "HOME" }
            else if pkg == ime { "IME" }
            else if black.contains(pkg.as_str()) { "BLACK" }
            else if preload(&pkg) && xposed { "PRELOAD_XP" }
            else if preload(&pkg) && white.contains(pkg.as_str()) { "PRELOAD_WL" }
            else if preload(&pkg) { "PRELOAD" }
            else if unknown.contains(&pkg) { "XPOSED_UNKNOWN" }
            else if xposed { "XPOSED" }
            else { "NORMAL" };
        events.push_str(&format!("{kind}\t{final_label}\t{pkg}\n"));
        if !force && black.contains(pkg.as_str()) && (mode == "true" || !blacklist_enabled) { continue; }
        let line = format!("{final_label} {pkg}");
        if !force && !white.contains(pkg.as_str()) && (unknown.contains(&pkg) || (!black.contains(pkg.as_str()) && preload(&pkg) && !xposed)) {
            comments.push(format!("#{line}"));
        } else { active.insert(pkg, line); added += 1; }
    }
    // Remove only an exact disabled shadow of an effective active row.
    // Other comments and genuinely conflicting rows remain untouched.
    comments.retain(|line| {
        let body=line.trim_start().strip_prefix(['#','＃']).map(str::trim_start);
        !body.is_some_and(|body| body.split_whitespace().last().and_then(|pkg|active.get(pkg)).is_some_and(|live|live==body))
    });
    let count = active.len();
    let home_line = active.remove(&home);
    let mut rows: Vec<_> = active.into_values().collect();
    rows.sort();
    comments.extend(rows);
    if let Some(line) = home_line { comments.push(line); }
    let mut text = comments.join("\n");
    text.push('\n');
    let text = disambiguate_labels(&text, &home);
    Ok(MergeReport { text, count, removed, events, home, ime, quantity, old_count, added, missing, blacklist_enabled })
}

pub fn run(args: &[String]) -> i32 {
    let result = (|| -> Result<(), String> {
        if args.len() != 7 && args.len() != 8 { return Err("expected OLD INVENTORY WHITELIST BLACKLIST MODE USER OUTPUT [REPORT_PREFIX]".into()); }
        let result = merge_report(&read(&args[0])?, &read(&args[1])?, &read(&args[2])?, &read(&args[3])?, &args[4], &args[5])?;
        if args.len() == 8 {
            for (suffix, data) in [(".events", &result.events), (".missing", &result.missing)] {
                let mut report = OpenOptions::new().write(true).create_new(true).mode(0o600).open(format!("{}{suffix}", args[7])).map_err(|error| error.to_string())?;
                report.write_all(data.as_bytes()).map_err(|error| error.to_string())?;
            }
        }
        let mut output = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&args[6]).map_err(|error| error.to_string())?;
        output.write_all(result.text.as_bytes()).and_then(|_| output.sync_all()).map_err(|error| error.to_string())?;
        if args.len() == 8 {
            println!("APPLIST_REPORT_1\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}", result.count, result.removed,
                if result.home.is_empty() { "-" } else { &result.home }, if result.ime.is_empty() { "-" } else { &result.ime }, result.quantity, result.old_count, result.added, usize::from(result.blacklist_enabled));
        } else { println!("APPLIST_OK\t{}\t{}", result.count, result.removed); }
        Ok(())
    })();
    match result { Ok(()) => 0, Err(error) => { eprintln!("APPLIST_ERROR {error}"); 65 } }
}
