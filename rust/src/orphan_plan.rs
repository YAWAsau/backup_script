//! Read-only orphan decisions from explicit, fresh inputs. Never deletes files.
use std::collections::{BTreeSet, HashSet};
use std::fs;
use std::io;
use std::path::Path;

fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}

fn component(name: &str) -> bool {
    !name.is_empty()
        && name != "."
        && name != ".."
        && !name
            .chars()
            .any(|c| c.is_control() || "/\\\";!".contains(c))
}

fn app(name: &str) -> bool {
    component(name) && !name.starts_with('.') && !matches!(name, "tools" | "wifi" | "Media" | "log")
}

pub fn package(name: &str) -> bool {
    !name.is_empty()
        && name.split('.').all(|part| {
            !part.is_empty() && part.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
        })
}

pub fn roots(text: &str, mode: &str, subdir: &str) -> io::Result<BTreeSet<String>> {
    if !component(subdir) {
        return Err(invalid("unsafe backup root"));
    }
    let mut names = BTreeSet::new();
    for line in text.lines().filter(|line| !line.is_empty()) {
        match mode {
            "webdav" => {
                let row: Vec<_> = line.split('\t').collect();
                if row.len() != 3 || !matches!(row[0], "DIR" | "FILE" | "BUNDLE") {
                    return Err(invalid("invalid typed root row"));
                }
                if !component(row[1]) || row[2] != format!("{}/{}", subdir, row[1]) {
                    return Err(invalid("root row outside selected backup"));
                }
                if row[0] == "DIR" && app(row[1]) {
                    names.insert(row[1].to_owned());
                }
            }
            "smb" => {
                let parts: Vec<_> = line.split('/').collect();
                if parts.iter().any(|p| !component(p)) {
                    return Err(invalid("unsafe relative file row"));
                }
                // A payload proves an app directory exists; root infra is ignored.
                if parts.len() == 2
                    && app(parts[0])
                    && matches!(
                        parts[1],
                        "apk.tar"
                            | "apk.tar.zst"
                            | "user.tar"
                            | "user.tar.zst"
                            | "user_de.tar"
                            | "user_de.tar.zst"
                            | "data.tar"
                            | "data.tar.zst"
                            | "obb.tar"
                            | "obb.tar.zst"
                            | "hma.tar"
                            | "hma.tar.zst"
                            | "thanox.tar"
                            | "thanox.tar.zst"
                    )
                {
                    names.insert(parts[0].to_owned());
                }
            }
            _ => return Err(invalid("unknown roots format")),
        }
    }
    Ok(names)
}

pub fn installed(text: &str) -> io::Result<HashSet<String>> {
    let mut set = HashSet::new();
    for line in text.lines().filter(|line| !line.is_empty()) {
        if !package(line) {
            return Err(invalid("invalid installed package row"));
        }
        set.insert(line.to_owned());
    }
    if set.is_empty() {
        return Err(invalid("empty installed snapshot"));
    }
    Ok(set)
}

pub fn run(
    roots_file: &Path,
    mode: &str,
    subdir: &str,
    bundle: &Path,
    installed_file: &Path,
    prefix: &str,
    metadata_package: impl Fn(&str) -> Option<String>,
) -> io::Result<String> {
    let names = roots(&fs::read_to_string(roots_file)?, mode, subdir)?;
    let installed = installed(&fs::read_to_string(installed_file)?)?;
    if !bundle.is_dir() {
        return Err(invalid("missing metadata bundle"));
    }
    let mut candidates = String::from("app\tpackage\treason\n");
    let mut decisions = String::from("app\tpackage\tdecision\n");
    let (mut checked, mut orphan, mut unknown) = (0, 0, 0);
    for name in &names {
        let directory = bundle.join(name);
        let file = directory.join("app_details.json");
        // Do not follow untrusted bundle symlinks outside its staging root.
        let ordinary = fs::symlink_metadata(&directory)
            .map(|m| m.is_dir())
            .unwrap_or(false)
            && fs::symlink_metadata(&file)
                .map(|m| m.is_file())
                .unwrap_or(false);
        let pkg = if ordinary {
            fs::read_to_string(&file)
                .ok()
                .and_then(|body| metadata_package(&body))
                .filter(|p| package(p))
        } else {
            None
        };
        match pkg {
            Some(pkg) => {
                checked += 1;
                if installed.contains(&pkg) {
                    decisions.push_str(&format!("{name}\t{pkg}\tinstalled\n"));
                } else {
                    orphan += 1;
                    candidates.push_str(&format!("{name}\t{pkg}\tpackage_not_installed\n"));
                    decisions.push_str(&format!("{name}\t{pkg}\torphan\n"));
                }
            }
            None => {
                unknown += 1;
                decisions.push_str(&format!("{name}\t-\tmetadata_unavailable_or_invalid\n"));
            }
        }
    }
    // Callers use unique prefixes and must require success plus every output.
    fs::write(format!("{prefix}.candidates.tsv"), candidates)?;
    fs::write(format!("{prefix}.decisions.tsv"), decisions)?;
    fs::write(format!("{prefix}.stats"), format!("remoteApps\t{}\nchecked\t{checked}\norphans\t{orphan}\nunknown\t{unknown}\ninstalledPkgs\t{}\n", names.len(), installed.len()))?;
    Ok(format!("REMOTE_ORPHAN_PLAN\tOK\tremoteApps={}\tchecked={checked}\torphans={orphan}\tunknown={unknown}\tinstalledPkgs={}\tschema=speedbackup.remote_orphan_plan.v1", names.len(), installed.len()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn typed_roots_preserve_names_and_ignore_infra() {
        let names = roots("DIR\tHideThanox\tBackup_zstd_0/HideThanox\nDIR\tApp t 名稱\tBackup_zstd_0/App t 名稱\nDIR\twifi\tBackup_zstd_0/wifi\nBUNDLE\tapp_details_bundle.tar.zst\tBackup_zstd_0/app_details_bundle.tar.zst\n", "webdav", "Backup_zstd_0").unwrap();
        assert_eq!(
            names.into_iter().collect::<Vec<_>>(),
            ["App t 名稱", "HideThanox"]
        );
    }

    #[test]
    fn roots_reject_mismatched_or_unsafe_rows() {
        for row in [
            "DIR\tApp\tOther/App",
            "DIR\t..\tBackup/..",
            "DIR\tApp\tBackup/App\textra",
            "UNKNOWN\tApp\tBackup/App",
        ] {
            assert!(roots(row, "webdav", "Backup").is_err());
        }
    }

    #[test]
    fn installed_snapshot_is_required_and_exact() {
        for input in [
            "",
            "package:com.example",
            "com.example\t10001",
            "com..example",
            "error: denied",
        ] {
            assert!(installed(input).is_err());
        }
        let set = installed("android\ncom.example\ncom.example\n").unwrap();
        assert_eq!(set.len(), 2);
        assert!(!set.contains("com.example.extra"));
    }

    #[test]
    fn smb_requires_payload_and_safe_relative_paths() {
        assert_eq!(
            roots(
                "HideThanox/apk.tar.zst\nOther/readme.txt\nappList.txt\n",
                "smb",
                "Backup"
            )
            .unwrap()
            .len(),
            1
        );
        assert!(roots("../Other/apk.tar.zst", "smb", "Backup").is_err());
    }

    #[test]
    fn complete_plan_unknowns_and_output_failures() {
        let temp = std::env::temp_dir().join(format!("sb-orphan-test-{}", std::process::id()));
        fs::create_dir_all(&temp).unwrap();
        let bundle = temp.join("bundle");
        for (name, pkg) in [
            ("Present", "com.present"),
            ("HideThanox", "com.absent"),
            ("Another t", "com.other"),
            ("Bad", "bad json"),
        ] {
            fs::create_dir_all(bundle.join(name)).unwrap();
            fs::write(bundle.join(name).join("app_details.json"), pkg).unwrap();
        }
        let input = temp.join("roots");
        fs::write(
            &input,
            ["Present", "HideThanox", "Another t", "Bad", "Missing"]
                .map(|a| format!("DIR\t{a}\tBackup/{a}\n"))
                .join(""),
        )
        .unwrap();
        let snapshot = temp.join("installed");
        fs::write(&snapshot, "com.present\n").unwrap();
        let prefix = temp.join("plan").to_string_lossy().into_owned();
        let parse = |body: &str| package(body).then(|| body.to_owned());
        let summary = run(
            &input, "webdav", "Backup", &bundle, &snapshot, &prefix, parse,
        )
        .unwrap();
        assert!(summary.contains("checked=3\torphans=2\tunknown=2"));
        let list = fs::read_to_string(format!("{prefix}.candidates.tsv")).unwrap();
        assert!(list.contains("HideThanox\tcom.absent\t"));
        assert!(list.contains("Another t\tcom.other\t"));
        assert!(!list.contains("com.present"));
        assert!(run(
            &input,
            "webdav",
            "Backup",
            &bundle,
            &snapshot,
            &format!("{prefix}/missing"),
            parse
        )
        .is_err());
        fs::write(&snapshot, "").unwrap();
        assert!(run(&input, "webdav", "Backup", &bundle, &snapshot, &prefix, parse).is_err());
        fs::remove_dir_all(temp).unwrap();
    }
}
