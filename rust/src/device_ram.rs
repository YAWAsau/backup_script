//! Optional vendor RAM facts. Isolate procfs reads from the startup process.
use std::{io::Read, process::{Command, Stdio}, time::{Duration, Instant}};

pub fn merge(vendor: String, size: Option<u32>, extra: Option<(&str, u32)>) -> (String, Option<u32>) {
    match extra {
        Some((_, gb)) if size.is_some_and(|known| known != gb) => (vendor, size),
        Some((other, gb)) if vendor.starts_with("未知") => (other.to_owned(), size.or(Some(gb))),
        Some((other, gb)) if vendor == other => (vendor, size.or(Some(gb))),
        _ => (vendor, size), // Conflicting vendors must not form a mixed identity.
    }
}

pub fn parse(text: &str) -> Option<(&'static str, u32)> {
    if text.len() > 2048 || text.contains('\0') { return None; }
    let mut rows = text.lines().filter_map(|line| {
        let (key, value) = line.split_once(':')?;
        (key.trim() == "Device manufacture").then_some(value.trim())
    });
    let row = rows.next()?;
    if rows.next().is_some() { return None; }
    let fields: Vec<_> = row.split('|').map(str::trim).collect();
    if fields.len() != 3 || fields[1].is_empty()
        || !fields[1].bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-') { return None; }
    let vendor = match fields[0].to_ascii_lowercase().as_str() {
        "hynix" | "sk hynix" | "skhynix" => "SK hynix",
        "samsung" => "Samsung",
        "micron" => "Micron",
        "cxmt" => "CXMT",
        "uniic" => "UniIC",
        "dosilicon" => "Dosilicon",
        _ => return None,
    };
    let size = fields[2].strip_suffix("GB").or_else(|| fields[2].strip_suffix('G'))?;
    if size.is_empty() || !size.bytes().all(|b| b.is_ascii_digit()) { return None; }
    let gb = size.parse::<u32>().ok()?;
    if !matches!(gb, 4 | 6 | 8 | 12 | 16 | 24 | 32 | 48 | 64) { return None; }
    Some((vendor, gb))
}

// Private fixed-path child command: bounded bytes, no shell and no environment
// override for the procfs path. Only canonical parsed facts go to stdout.
pub fn reader(args: &[String]) -> i32 {
    if !args.is_empty() { return 2; }
    let read = || -> Option<String> {
        let f = std::fs::File::open("/proc/devinfo/ddr").ok()?;
        let mut bytes = Vec::new();
        f.take(2049).read_to_end(&mut bytes).ok()?;
        if bytes.len() > 2048 { return None; }
        String::from_utf8(bytes).ok()
    };
    match read().as_deref().and_then(parse) {
        Some((vendor, gb)) => { println!("Device manufacture: {vendor}|reported|{gb}G"); 0 }
        None => 1,
    }
}

fn collect(mut command: Command, budget: Duration) -> Option<String> {
    let mut child = command.stdin(Stdio::null()).stdout(Stdio::piped())
        .stderr(Stdio::null()).spawn().ok()?;
    let deadline = Instant::now() + budget;
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                if !status.success() { return None; }
                let mut bytes = Vec::new();
                child.stdout.take()?.take(2049).read_to_end(&mut bytes).ok()?;
                if bytes.len() > 2048 { return None; }
                return String::from_utf8(bytes).ok();
            }
            Ok(None) if Instant::now() < deadline => std::thread::sleep(Duration::from_millis(5)),
            _ => break,
        }
    }
    // Child has not been reaped, so its PID cannot be reused. Never block on
    // wait(): a broken driver can keep a task in uninterruptible kernel sleep.
    let _ = child.kill();
    let reap_deadline = Instant::now() + Duration::from_millis(100);
    while Instant::now() < reap_deadline {
        match child.try_wait() { Ok(None) => std::thread::sleep(Duration::from_millis(5)), _ => break }
    }
    None
}

pub fn fallback() -> Option<(&'static str, u32)> {
    static RESULT: std::sync::OnceLock<Option<(&'static str, u32)>> = std::sync::OnceLock::new();
    *RESULT.get_or_init(|| {
        let mut command = Command::new(std::env::current_exe().ok()?);
        command.args(["speedscan", "ram-devinfo-read"]);
        let text = collect(command, Duration::from_millis(300))?;
        parse(&text)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reported_fixture() {
        assert_eq!(parse("Device version:\t\tDDR5\nDevice manufacture:\t\tHynix|D1a|16G\n"), Some(("SK hynix",16)));
        assert_eq!(parse("Device manufacture: Samsung|rev1|12GB\r\n"), Some(("Samsung",12)));
    }
    #[test]
    fn malformed_rejected() {
        for text in ["", "Device version: DDR5", "Device manufacture: Unknown|D1a|16G",
            "Device manufacture: Hynix|D1a|16384", "Device manufacture: Hynix|D1a|0G",
            "Device manufacture: Hynix|D1a|16G+16G", "Device manufacture: Hynix|D1a|16G\0",
            "Device manufacture: Hynix|D1a|16G\nDevice manufacture: Samsung|X|16G"] {
            assert_eq!(parse(text), None, "{text:?}");
        }
        assert_eq!(parse(&"x".repeat(2049)),None);
    }
    #[test]
    fn primary_and_conflicts() {
        assert_eq!(merge("未知".into(),None,Some(("SK hynix",16))),("SK hynix".into(),Some(16)));
        assert_eq!(merge("Micron".into(),None,Some(("SK hynix",16))),("Micron".into(),None));
        assert_eq!(merge("SK hynix".into(),Some(12),Some(("SK hynix",16))),("SK hynix".into(),Some(12)));
        assert_eq!(merge("SK hynix".into(),None,Some(("SK hynix",16))),("SK hynix".into(),Some(16)));
        assert_eq!(merge("未知".into(),Some(12),Some(("SK hynix",16))),("未知".into(),Some(12)));
    }
    #[test] #[ignore]
    fn sleeping_child() { std::thread::sleep(Duration::from_secs(10)); }
    #[test]
    fn deadline_does_not_wait_for_reader() {
        let mut command=Command::new(std::env::current_exe().unwrap());
        command.args(["--exact","tests::sleeping_child","--ignored"]);
        let start=Instant::now();
        assert!(collect(command,Duration::from_millis(50)).is_none());
        assert!(start.elapsed()<Duration::from_secs(2));
    }
    #[test] #[ignore]
    fn emit_child() {
        match std::env::var("RAM_TEST_MODE").unwrap().as_str() {
            "ok" => println!("Device manufacture: Hynix|D1a|16G"),
            "large" => println!("{}", "x".repeat(2500)),
            "error" => std::process::exit(7),
            _ => unreachable!(),
        }
    }
    #[test]
    fn collect_success_error_and_oversize() {
        for mode in ["ok", "large", "error"] {
            let mut command=Command::new(std::env::current_exe().unwrap());
            command.args(["--exact","tests::emit_child","--ignored","--nocapture"]);
            command.env("RAM_TEST_MODE",mode);
            let result=collect(command,Duration::from_secs(1));
            if mode == "ok" { assert_eq!(parse(&result.unwrap()),Some(("SK hynix",16))); }
            else { assert!(result.is_none()); }
        }
    }
}
