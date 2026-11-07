use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::io::Read;
use std::path::Path;
use std::{fs, io};

fn bad() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "invalid remote facts")
}
// Same package grammar as _applist_home_last_filter's remote_changed_apps mode.
fn changed_package(s: &str) -> bool {
    let mut parts=s.split('.');
    let first=parts.next().unwrap_or("");
    if !first.as_bytes().first().is_some_and(u8::is_ascii_alphabetic)
        || !first.bytes().all(|b| b.is_ascii_alphanumeric() || b==b'_') { return false; }
    let rest:Vec<_>=parts.collect();
    !rest.is_empty() && rest.iter().all(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b==b'_'))
}
fn changed_home_key(line: &str) -> (bool, Option<&str>) {
    let mut s=line.trim_start_matches([' ', '\t']);
    let active=!s.starts_with(['#','＃']);
    if active {
        if let Some(rest)=s.strip_prefix("!play").or_else(|| s.strip_prefix("！play"))
            .filter(|r| r.starts_with([' ', '\t'])) {
            s=rest.trim_start_matches([' ', '\t']);
        } else if let Some(rest)=s.strip_prefix('!') {
            s=rest.trim_start_matches([' ', '\t']);
        }
        // The shipped Android AWK leaves a token for bare full-width ！.
        // Keep it during package extraction (not output rewriting), including "！ label pkg".
        s=s.trim_end_matches([' ', '\t']);
    }
    let pkg=s.split([' ', '\t']).filter(|p| !p.is_empty()).nth(1).filter(|p| changed_package(p));
    (active,pkg)
}
fn changed_apps_plan(args: &[String]) -> io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let text=read(&args[1])?;
    // split_terminator keeps real blank rows and includes a final unterminated row.
    // Android sort uses byte ordering; do not trim CR or whitespace before sorting/counting.
    let rows:BTreeSet<_>=text.split_terminator('\n').collect();
    let mut display=String::new();
    let mut normal=String::new(); let mut home=String::new(); let mut seen=HashSet::new();
    for raw in &rows {
        display.push_str(raw); display.push(' ');
        let line=raw.strip_suffix('\r').unwrap_or(raw);
        if line.is_empty() { continue; }
        let (active,pkg)=changed_home_key(line);
        let key=if active && pkg.is_some() { format!("A:{}",pkg.unwrap()) } else { format!("L:{line}") };
        if !seen.insert(key) { continue; }
        let output=if !args[2].is_empty() && pkg==Some(args[2].as_str()) { &mut home } else { &mut normal };
        output.push_str(line); output.push('\n');
    }
    normal.push_str(&home);
    let mut output=fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&args[3])?;
    // Bound the shell's direct read; large lists use buffered cat instead.
    let result=write!(output,"{}\t{}\n{}\n{}",rows.len(),u8::from(normal.len()<=512),display,normal);
    if result.is_err() { drop(output); let _=fs::remove_file(&args[3]); }
    result
}
fn read(path: &str) -> io::Result<String> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_file() || metadata.len() > 128 * 1024 * 1024 {
        return Err(bad());
    }
    let text = fs::read_to_string(path)?;
    if text.contains('\0') {
        return Err(bad());
    }
    Ok(text)
}
fn optional(path: &str) -> io::Result<String> {
    if path.is_empty() || !Path::new(path).exists() {
        Ok(String::new())
    } else {
        read(path)
    }
}
fn uint(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit())
}
fn sum<'a>(values: impl Iterator<Item = &'a str>) -> io::Result<String> {
    let mut total = vec![b'0'];
    for value in values {
        if !super::decimal_add_assign(&mut total, value.as_bytes()) {
            return Err(bad());
        }
    }
    String::from_utf8(total).map_err(|_| bad())
}
fn norm(s: &str) -> String {
    s.replace('\\', "/")
        .split('/')
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join("/")
}
fn attr(s: &str) -> bool {
    !s.is_empty()
        && s.bytes().all(|b| b"ADNHSR".contains(&b))
}
fn safe_rel(s: &str) -> bool {
    !s.is_empty() && !s.contains(['\t', '\r', '\n', '\0']) && !s.split('/').any(|part| part == "..")
}
fn entries(raw: &str, pref: &str) -> io::Result<Vec<(String, String, String)>> {
    let pref = norm(pref);
    let mut dir = String::new();
    let mut rows = Vec::new();
    let mut seen = BTreeMap::new();
    for line in raw.lines() {
        let diagnostic=line.contains("NT_STATUS")||line.contains("ERRSRV");
        if line.is_empty()
            || [
                "Try \"help\"",
                "dos charset",
                "Can't load",
                "WARNING:",
                "Domain=",
                "OS=",
                "directory_create_or_exist:",
            ]
            .iter()
            .any(|p| line.starts_with(p)) && !diagnostic
        {
            continue;
        }
        if line.starts_with('\\') {
            dir = norm(line);
            continue;
        }
        let fields: Vec<_> = line.split_ascii_whitespace().collect();
        if fields.len() >= 5
            && uint(fields[0])
            && fields[1..4] == ["blocks", "of", "size"]
            && uint(fields[4])
        {
            continue;
        }
        let table = (1..fields.len().saturating_sub(1))
            .rfind(|&i| attr(fields[i]) && uint(fields[i + 1]))
            .map(|i| {let end=fields[i].as_ptr() as usize-line.as_ptr() as usize;(line[..end].strip_prefix("  ").unwrap_or(&line[..end]).trim_end().to_owned(),fields[i],fields[i+1])});
        let found = if table.is_some(){table}else if line.contains('|') {
            let f: Vec<_> = line.split('|').collect();
            if f.len() == 3 && attr(f[1]) && uint(f[2]) {
                Some((f[0].to_owned(), f[1], f[2]))
            } else if f.len() == 3 && attr(f[0]) && uint(f[2]) {
                Some((f[1].to_owned(), f[0], f[2]))
            } else if f.len() == 3 && attr(f[2]) && uint(f[1]) {
                Some((f[0].to_owned(), f[2], f[1]))
            } else if matches!(f[0],"Disk"|"IPC"|"Printer") {None}
            else {return Err(bad());}
        }else{None};
        let Some((name, kind, bytes)) = found else {
            if diagnostic{return Err(bad());}
            continue;
        };
        if matches!(name.as_str(), "" | "." | "..") {
            continue;
        }
        let name = norm(&name);
        if matches!(name.as_str(), "" | "." | "..") {
            continue;
        }
        let full = if !dir.is_empty() && !name.starts_with(&(dir.clone() + "/")) {
            norm(&format!("{dir}/{name}"))
        } else {
            name
        };
        if !pref.is_empty() && full == pref {
            continue;
        }
        let rel = full
            .strip_prefix(&(pref.clone() + "/"))
            .filter(|_| !pref.is_empty())
            .unwrap_or(&full);
        if matches!(rel, "" | "." | "..") {
            continue;
        }
        if !safe_rel(rel) {
            return Err(bad());
        }
        let value=(kind.to_owned(),bytes.to_owned());
        if let Some(previous)=seen.get(rel){if previous!=&value{return Err(bad());}continue;}
        seen.insert(rel.to_owned(),value);
        rows.push((kind.to_owned(), bytes.to_owned(), rel.to_owned()));
    }
    Ok(rows)
}
fn context() -> io::Result<Vec<u8>> {
    let mut value = Vec::new();
    io::stdin().take(1024 * 1024 + 1).read_to_end(&mut value)?;
    if value.len() > 1024 * 1024 || value.is_empty() {
        return Err(bad());
    }
    Ok(value)
}
fn map(text: &str) -> io::Result<Vec<(&str, &str)>> {
    text.lines()
        .map(|line| {
            let f: Vec<_> = line.split('\t').collect();
            if f.len() != 2 || !safe_rel(f[0]) || !uint(f[1]) {
                return Err(bad());
            }
            Ok((f[0], f[1]))
        })
        .collect()
}
pub fn run(args: &[String]) -> io::Result<()> {
    match args[0].as_str() {
        "changed-apps-plan" if args.len()==4 => changed_apps_plan(args)?,
        "upload-dirs" if args.len() == 5 => {
            let text=read(&args[1])?;
            // mksh echo expands escapes and treats option-like top names specially.
            // Keep that rare legacy behavior in the original shell loops, after input validation.
            if text.contains('\\') || args[2].contains(['\\', '*', '?', '[', ']'])
                || args[3].contains('\\') || text.lines().any(|line| {
                line.trim_matches([' ', '\t']).strip_prefix(&format!("{}/",args[2]))
                    .unwrap_or(line.trim_matches([' ', '\t'])).starts_with('-')
            }) {
                println!("legacy");
                return Ok(());
            }
            let mut directories=BTreeSet::new();
            let mut tops=BTreeSet::new();
            let prefix=format!("{}/",args[2]);
            for line in text.split_inclusive('\n').filter(|line| line.ends_with('\n')) {
                let file=line.trim_end_matches('\n').trim_matches([' ', '\t']);
                let rel=file.strip_prefix(&prefix).unwrap_or(file);
                if rel.is_empty(){continue;}
                if !safe_rel(rel){return Err(bad());}
                if let Some((dir,_))=rel.rsplit_once('/') {
                    if !dir.is_empty() { directories.insert(format!("{}/{dir}",args[3])); }
                }
                let top=rel.split('/').next().unwrap_or("");
                if top!="wifi" { tops.insert(top.to_owned()); }
            }
            fs::write(&args[4],directories.into_iter().map(|d| format!("{d}\n")).collect::<String>())?;
            println!("{}",tops.len());
        }
        "smb-entries" if args.len()==2 => {
            let mut raw=String::new();io::stdin().take(128*1024*1024+1).read_to_string(&mut raw)?;
            if raw.len()>128*1024*1024||raw.contains('\0'){return Err(bad());}
            for (attr,size,name) in entries(&raw,&args[1])? {println!("{attr}\t{size}\t{name}");}
        }
        "smb-list" if args.len() == 3 => {
            let rows = entries(&read(&args[1])?, &args[2])?;
            for row in rows.iter().filter(|r| !r.0.contains('D')) {
                println!("{}", row.2);
            }
        }
        "smb-plan" if args.len() == 5 => {
            let rows = entries(&read(&args[1])?, &args[2])?;
            let files: Vec<_> = rows.iter().filter(|r| !r.0.contains('D')).collect();
            let total = sum(files.iter().map(|r| r.1.as_str()))?;
            let table: String = files
                .iter()
                .map(|r| format!("{}\t{}\n", r.2, r.1))
                .collect();
            fs::write(&args[3], &table)?;
            if args[4] != "-" {
                let base = &args[4];
                let marker = format!("{base}.ok");
                match fs::remove_file(&marker) {
                    Ok(()) => (),
                    Err(e) if e.kind() == io::ErrorKind::NotFound => (),
                    Err(e) => return Err(e),
                }
                let store = || -> io::Result<()> {
                    let ctx = context()?;
                    fs::write(format!("{base}.tsv"), &table)?;
                    fs::write(format!("{base}.context"), ctx)?;
                    fs::write(&marker, [])
                };
                if store().is_err() { let _ = fs::remove_file(&marker); }
            }
            println!("{total}\t{}", files.len());
        }
        "smb-snapshot" if args.len() == 3 => {
            let base = &args[1];
            fs::remove_file(format!("{base}.ok"))?;
            let ctx = context()?;
            if read(&format!("{base}.context"))?.as_bytes() != ctx {
                return Err(bad());
            }
            let text = read(&format!("{base}.tsv"))?;
            let rows = map(&text)?;
            let list: String = rows.iter().map(|r| format!("{}\n", r.0)).collect();
            fs::write(&args[2], list)?;
        }
        "upload-map" if args.len() == 6 => {
            let mut rows = BTreeMap::new();
            let root = &args[3];
            let normalize = |s: &str| {
                let s = s.trim_start_matches('/');
                s.strip_prefix(&(root.clone() + "/"))
                    .filter(|_| !root.is_empty())
                    .unwrap_or(s)
                    .to_owned()
            };
            for line in optional(&args[1])?.lines() {
                if !line.split_ascii_whitespace().any(|f|f=="WEBDAV_STREAM_DONE") || !line.split_ascii_whitespace().any(|f|f=="kind=ok") {
                    continue;
                }
                let kv = |key: &str| {
                    line.split_ascii_whitespace()
                        .find_map(|s| s.strip_prefix(&format!("{key}=")))
                        .unwrap_or("")
                };
                // Unstructured daemon logs cannot unambiguously encode whitespace paths.
                // Decline the fast accounting path; the caller obtains actual remote sizes.
                let fields=line.split_ascii_whitespace().collect::<Vec<_>>();
                if fields.iter().position(|f|f.starts_with("rel=")).is_some_and(|i|fields.get(i+1).is_none_or(|f|!f.starts_with("target="))){return Err(bad());}
                let rel = normalize(kv("rel"));
                let bytes = kv("sentBytes");
                if !rel.is_empty() && !rel.ends_with('/') && uint(bytes) {
                    if !safe_rel(&rel){return Err(bad());}
                    rows.insert(rel, bytes.to_owned());
                }
            }
            for line in optional(&args[2])?.lines() {
                if line.is_empty()
                    || line.starts_with('=')
                    || line.starts_with("SUMMARY\t")
                    || line.starts_with("SUMMARY ")
                {
                    continue;
                }
                let f: Vec<_> = if line.contains('\t'){line.split('\t').collect()}else{line.split_ascii_whitespace().collect()};
                if f.len() < 3 {
                    continue;
                }
                let rel = normalize(f[0]);
                let http = f[1].len() == 3 && f[1].starts_with("20") && uint(f[1]);
                if !rel.is_empty()
                    && !rel.ends_with('/')
                    && uint(f[2])
                    && (http || f.get(3) == Some(&"OK"))
                {
                    if !safe_rel(&rel){return Err(bad());}
                    rows.insert(rel, f[2].to_owned());
                }
            }
            fs::write(
                &args[4],
                rows.iter()
                    .map(|(r, b)| format!("{r}\t{b}\n"))
                    .collect::<String>(),
            )?;
            if rows.is_empty() {
                return Err(bad());
            }
            {
                let uploaded = sum(rows.values().map(String::as_str))?;
                let before = optional(&args[5])?;
                let mut merged = BTreeMap::new();
                for line in before.lines() {
                    let f: Vec<_> = line.split('\t').collect();
                    if f.len() >= 2 && !f[0].is_empty() && uint(f[1]) {
                        merged.insert(f[0], f[1]);
                    }
                }
                for (rel, bytes) in &rows {
                    merged.insert(rel.as_str(), bytes.as_str());
                }
                println!(
                    "{}\t{uploaded}\t{}",
                    rows.len(),
                    sum(merged.values().copied())?
                );
            }
        }
        "remote-list-filter" if args.len() == 5 => {
            let existing = read(&args[2])?;
            let known: HashSet<_> = existing.lines().collect();
            let mut needed = String::new();
            let mut matched = String::new();
            for line in read(&args[1])?.lines().filter(|s| !s.is_empty()) {
                if known.contains(line) {
                    matched.push_str(line);
                    matched.push('\n');
                } else {
                    needed.push_str(line);
                    needed.push('\n');
                }
            }
            fs::write(&args[3], needed)?;
            fs::write(&args[4], matched)?;
        }
        _ => return Err(bad()),
    }
    Ok(())
}

#[cfg(test)] mod selection_migration_tests {
 use super::*;
 #[test] fn dates_and_pipe_names_are_not_attributes(){
  let rows=entries("  Alpha D 0 Tue Nov 3 20:24:14 2026\n  A|B A 123 Sun Apr 2 10:00:00 2026\n","").unwrap();
  assert_eq!(rows,vec![("D".into(),"0".into(),"Alpha".into()),("A".into(),"123".into(),"A|B".into())]);
 }
 #[test] fn whitespace_in_names_is_preserved(){assert_eq!(entries("  A  B D 0 Tue Nov 3 20:24:14 2026\n","").unwrap()[0].2,"A  B");}
 #[test] fn disk_named_entry_is_not_a_share_banner(){assert_eq!(entries("Disk|D|0\n","").unwrap(),vec![("D".into(),"0".into(),"Disk".into())]);}
}

#[cfg(test)] mod review_regression_tests {
 use super::*;
 #[test] fn status_words_in_valid_filenames_are_not_errors() {
  let rows=entries("  NT_STATUS_OBJECT_NAME_NOT_FOUND D 0 Tue Nov 3 20:24:14 2026\n  ERRSRV-data A 12 Tue Nov 3 20:24:14 2026\n", "").unwrap();
  assert_eq!(rows.len(),2);
  assert!(entries("NT_STATUS_ACCESS_DENIED listing \\*\n", "").is_err());
  assert!(entries("WARNING: NT_STATUS_ACCESS_DENIED\n", "").is_err());
 }
 #[test] fn duplicate_rows_count_once_and_conflicting_facts_fail() {
  assert_eq!(entries("App.tar|A|12\nApp.tar|A|12\n", "").unwrap().len(),1);
  assert!(entries("App.tar|A|12\nApp.tar|A|13\n", "").is_err());
 }
}
