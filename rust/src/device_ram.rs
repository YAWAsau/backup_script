//! Optional vendor RAM facts. Isolate procfs reads from the startup process.
use std::{io::Read, process::{Command, Stdio}, time::Duration};

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


// Xiaomi /proc/mv: D carries an MR5 ID and nominal GB; U carries a UFS
// manufacturer ID, nominal GB, model and firmware. Preserve unknown IDs.
#[derive(Clone, Debug, PartialEq)]
pub struct MvFacts { pub ram: Option<(String,u32)>, pub flash: Option<String> }
fn hex_id(s:&str)->Option<u16> {
    let h=s.strip_prefix("0x").or_else(||s.strip_prefix("0X"))?;
    if h.is_empty() || h.len()>4 {return None;}
    u16::from_str_radix(h,16).ok()
}
pub fn parse_mv(text:&str)->Option<MvFacts> {
    if text.len()>2048 || text.contains('\0') {return None;}
    let mut result=MvFacts{ram:None,flash:None};
    let mut seen_d=false;let mut seen_u=false;
    for line in text.lines().filter(|l|!l.trim().is_empty()) {
        let f:Vec<_>=line.split_whitespace().collect();
        match f.first().copied() {
            Some("D:") => {
                if seen_d {return None;} seen_d=true;
                if f.len()!=3 {continue;}
                let Some(id)=hex_id(f[1]).filter(|id|*id<=255) else {continue;};
                let Some(gb)=f[2].parse::<u32>().ok().filter(|n|matches!(n,4|6|8|12|16|24|32|48|64)) else {continue;};
                let vendor=match id {1=>"Samsung".into(),6=>"SK hynix".into(),255=>"Micron".into(),
                    0x13=>"CXMT".into(),0x1a=>"UniIC".into(),0xe5=>"Dosilicon".into(),
                    _=>format!("未知 (ID:0x{id:02x})")};
                result.ram=Some((vendor,gb));
            },
            Some("U:") => {
                if seen_u {return None;} seen_u=true;
                if f.len()!=5 {continue;}
                let Some(id)=hex_id(f[1]) else {continue;};
                let Some(gb)=f[2].parse::<u32>().ok().filter(|n|matches!(n,32|64|128|256|512|1024|2048|4096)) else {continue;};
                if !f[3..].iter().all(|s|s.len()<=64 && s.bytes().all(|b|b.is_ascii_alphanumeric()||b"._-".contains(&b))) {continue;}
                let vendor=match id {0x01ad=>"SK hynix".into(),0x0198=>"KIOXIA/Toshiba".into(),
                    _=>format!("未知 (ID:0x{id:04x})")};
                result.flash=Some(format!("{vendor} {gb} GB {} {}",f[3],f[4]));
            },
            _=>return None,
        }
    }
    (result.ram.is_some()||result.flash.is_some()).then_some(result)
}
pub fn mv_fallback()->Option<MvFacts> {
    static RESULT:std::sync::OnceLock<Option<MvFacts>>=std::sync::OnceLock::new();
    RESULT.get_or_init(|| {
        let mut command=Command::new(std::env::current_exe().ok()?);
        command.args(["speedscan","ram-devinfo-read","mv"]);
        parse_mv(&collect(command,Duration::from_millis(300))?)
    }).clone()
}

// Private fixed-path child command: bounded bytes, no shell and no environment
// override for the procfs path. Only canonical parsed facts go to stdout.
pub fn reader(args: &[String]) -> i32 {
    let mv = matches!(args, [mode] if mode == "mv");
    if !args.is_empty() && !mv { return 2; }
    let read = || -> Option<String> {
        let f = std::fs::File::open(if mv {"/proc/mv"} else {"/proc/devinfo/ddr"}).ok()?;
        let mut bytes = Vec::new();
        f.take(2049).read_to_end(&mut bytes).ok()?;
        if bytes.len() > 2048 { return None; }
        String::from_utf8(bytes).ok()
    };
    let text=read();
    if mv {
        return match text.filter(|s|parse_mv(s).is_some()) {Some(s)=>{print!("{s}");0},None=>1};
    }
    match text.as_deref().and_then(parse) {
        Some((vendor, gb)) => { println!("Device manufacture: {vendor}|reported|{gb}G"); 0 }
        None => 1,
    }
}

fn collect(mut command: Command, budget: Duration) -> Option<String> {
    let mut child=super::command_lifecycle::OwnedChild::spawn(command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null())).ok()?;
    let status=super::command_lifecycle::wait_checked(&mut child,budget,||Ok(())).ok()?;
    if !status.success(){return None;}
    let mut bytes=Vec::new();child.stdout.take()?.take(2049).read_to_end(&mut bytes).ok()?;
    if bytes.len()>2048{return None;}
    String::from_utf8(bytes).ok()
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
    use std::time::Instant;
    #[test]
    fn mv_known_unknown_and_malformed() {
        for (id,vendor,model,ufs) in [("0x06","SK hynix","HN8T281EJKX158","0x01ad"),("0x8f","未知 (ID:0x8f)","HN8T281EJKX158","0x01ad"),("0xff","Micron","THGJFMT2E46BATVB","0x0198")] {
            let f=parse_mv(&format!("D: {id} 16\nU: {ufs} 512 {model} X002\n")).unwrap();
            assert_eq!(f.ram,Some((vendor.into(),16)));
            assert!(f.flash.unwrap().contains(model));
        }
        for raw in ["", "D: 0x8f 0", "D: 0x8f 16\nD: 0xff 16", "D: 0x100 16", "D: 0xff 16\0", "U: 0x0198 512 bad/model X002", "D: 0x8f 16\nother"] {assert!(parse_mv(raw).is_none(),"{raw}");}
        assert!(parse_mv(&"a".repeat(2049)).is_none());
        assert_eq!(parse_mv("D: 0x8f 16\nU: malformed").unwrap().ram,Some(("未知 (ID:0x8f)".into(),16)));
    }
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
        assert_eq!(merge("未知".into(),None,Some(("未知 (ID:0x8f)",16))),("未知 (ID:0x8f)".into(),Some(16)));
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
        command.args(["--exact", &format!("{}::sleeping_child", module_path!().split_once("::").unwrap().1), "--ignored"]);
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
            command.args(["--exact", &format!("{}::emit_child", module_path!().split_once("::").unwrap().1), "--ignored", "--nocapture"]);
            command.env("RAM_TEST_MODE",mode);
            let result=collect(command,Duration::from_secs(1));
            if mode == "ok" { assert_eq!(parse(&result.unwrap()),Some(("SK hynix",16))); }
            else { assert!(result.is_none()); }
        }
    }
}
