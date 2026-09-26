use std::{collections::BTreeMap, env, fs, path::PathBuf};

fn main() {
    let path = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap()).join("../versions.properties");
    println!("cargo:rerun-if-changed={}", path.display());
    let keys = ["build", "script", "dex", "cgfreezer", "eventwait", "filewatch", "netwatch", "procwait", "speedscan", "uidexec", "unixsock"];
    let raw = fs::read_to_string(&path).expect("FULL_SOURCE versions.properties is required");
    let mut versions = BTreeMap::new();
    for line in raw.lines().map(str::trim).filter(|s| !s.is_empty() && !s.starts_with('#')) {
        let (key, version) = line.split_once('=').expect("Invalid version entry");
        assert!(keys.contains(&key), "Unknown version component: {key}");
        assert!(version.len() == 4 && version.starts_with('v')
            && (b'1'..=b'9').contains(&version.as_bytes()[1])
            && version.as_bytes()[1..].iter().all(u8::is_ascii_digit), "Invalid component version: {key}={version}");
        assert!(versions.insert(key, version).is_none(), "Duplicate version component: {key}");
    }
    for key in keys {
        assert!(versions.contains_key(key), "Missing version component: {key}");
        println!("cargo:rustc-env=SPEEDBACKUP_{}_VERSION={}", key.to_ascii_uppercase(), versions[key]);
    }
    let package = format!("{}.0.0", &versions["build"][1..]);
    assert_eq!(env::var("CARGO_PKG_VERSION").unwrap(), package, "Run sync_version.ps1 before building");
}
