//! Read-only UFS display facts. Never infer device revision from a PN or UFSHCI.
use std::fs;
use std::path::Path;

fn version(raw: &str) -> Option<&'static str> {
    let raw = raw.trim();
    let hex = raw.strip_prefix("0x").or_else(|| raw.strip_prefix("0X"))?;
    match u16::from_str_radix(hex, 16).ok()? {
        0x0100 => Some("1.0"), 0x0110 => Some("1.1"),
        0x0200 => Some("2.0"), 0x0210 => Some("2.1"), 0x0220 => Some("2.2"),
        0x0300 => Some("3.0"), 0x0310 => Some("3.1"),
        0x0400 => Some("4.0"), 0x0410 => Some("4.1"), _ => None,
    }
}

fn clean(raw: &[u8]) -> String {
    let text: String = raw.iter().filter(|b| b.is_ascii_graphic() || **b == b' ')
        .map(|b| *b as char).collect();
    text.split_ascii_whitespace().collect::<Vec<_>>().join(" ")
}

fn manufacture_date(raw: &str) -> Option<String> {
    // wManufactureDate is BCD 0xMMYY (Microsoft UFS_DEVICE_DESCRIPTOR / JEDEC).
    let raw = raw.trim();
    let value = u16::from_str_radix(raw.strip_prefix("0x").or_else(|| raw.strip_prefix("0X"))?, 16).ok()?;
    let n = [(value >> 12) & 15, (value >> 8) & 15, (value >> 4) & 15, value & 15];
    if n.iter().any(|v| *v > 9) { return None; }
    let month = n[0] * 10 + n[1];
    if !(1..=12).contains(&month) { return None; }
    Some(format!("20{}{}-{month:02}", n[2], n[3]))
}

fn facts(sys: &Path, proc: &Path) -> (String, String, Option<String>) {
    let mut kind = if sys.join("block/sda/size").is_file() { "UFS" } else { "eMMC" }.to_owned();
    let disk = sys.join("class/block/sda/device");
    let fields: Vec<String> = ["vendor", "model", "rev"].iter()
        .filter_map(|key| fs::read(disk.join(key)).ok()).map(|v| clean(&v))
        .filter(|v| !v.is_empty()).collect();
    let mut model = fields.join(" ");
    if model.is_empty() {
        if let Ok(scsi) = fs::read_to_string(proc.join("scsi/scsi")) {
            if let Some(line) = scsi.lines().find(|s| s.contains("Vendor:")) {
                if let Some((_, tail)) = line.split_once("Vendor:") {
                    model = clean(tail.replace("Model:", " ").replace("Rev:", " ").as_bytes());
                }
            }
        }
    }
    if model.is_empty() {
        if let Ok(inquiry) = fs::read(disk.join("inquiry")) {
            // SPC standard INQUIRY has 8-byte vendor, 16-byte model, 4-byte revision.
            if inquiry.len() >= 36 {
                model = [8..16, 16..32, 32..36].iter()
                    .map(|r| clean(&inquiry[r.clone()])).filter(|s| !s.is_empty())
                    .collect::<Vec<_>>().join(" ");
            }
        }
    }
    if model.is_empty() { model = "unknown".to_owned(); }
    let mut manufactured = None;
    if kind == "UFS" {
        if let Ok(disk) = fs::canonicalize(disk) {
            for parent in disk.ancestors().take_while(|p| p.starts_with(sys)) {
                let descriptor = parent.join("device_descriptor");
                if descriptor.is_dir() {
                    if let Ok(raw) = fs::read_to_string(descriptor.join("specification_version")) {
                        if let Some(v) = version(&raw) { kind.push_str(v); }
                    }
                    manufactured = fs::read_to_string(descriptor.join("manufacturing_date")).ok()
                        .and_then(|raw| manufacture_date(&raw));
                    break;
                }
            }
        }
    }
    (kind, model, manufactured)
}

pub fn run(args: &[String]) -> i32 {
    let (sys, proc) = match args {
        [] => (Path::new("/sys"), Path::new("/proc")),
        [sys, proc] => (Path::new(sys), Path::new(proc)),
        _ => return 2,
    };
    let (kind, model, manufactured) = facts(sys, proc);
    println!("{kind}\t{model}\t{}", manufactured.unwrap_or_default());
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reported_versions_only() {
        assert_eq!(version("0x0410\n"), Some("4.1"));
        assert_eq!(version(" 0X400 "), Some("4.0"));
        assert_eq!(version("0x0310"), Some("3.1"));
        for s in ["1500", "4.1", "0x0500", "0x0000", "", "0x0410 junk"] {
            assert_eq!(version(s), None, "{s}");
        }
    }
    #[test]
    fn removes_binary_header_and_preserves_text() {
        assert_eq!(clean(b"\x06\x02\x1f\x02SAMSUNG   KLUFG4NHHB-F0G1 1500\0"),
            "SAMSUNG KLUFG4NHHB-F0G1 1500");
    }
    #[test]
    fn bcd_dates_reject_invalid_nibbles_and_months() {
        assert_eq!(manufacture_date("0x1222\n"), Some("2022-12".into()));
        assert_eq!(manufacture_date("0x0810"), Some("2010-08".into()));
        assert_eq!(manufacture_date("0X125"), Some("2025-01".into()));
        for raw in ["0x0000", "0x1325", "0x012A", "1222", "", "0xFFFF"] {
            assert_eq!(manufacture_date(raw), None, "{raw}");
        }
    }
    #[test]
    fn device_and_fallback() {
        let temp = std::env::temp_dir().join(format!("sb-flash-unit-{}", std::process::id()));
        let sys = temp.join("sys");
        let proc = temp.join("proc");
        let controller = sys.join("devices/platform/controller");
        let disk = controller.join("host/target/disk");
        fs::create_dir_all(&disk).unwrap();
        fs::create_dir_all(sys.join("block/sda")).unwrap();
        fs::write(sys.join("block/sda/size"), "1024").unwrap();
        fs::create_dir_all(sys.join("class/block/sda")).unwrap();
        std::os::unix::fs::symlink(&disk, sys.join("class/block/sda/device")).unwrap();
        fs::write(disk.join("vendor"), "SAMSUNG \n").unwrap();
        fs::write(disk.join("model"), "KLUFG4NHHB-F0G1 \n").unwrap();
        fs::write(disk.join("rev"), "1500\n").unwrap();
        fs::create_dir_all(controller.join("device_descriptor")).unwrap();
        let spec = controller.join("device_descriptor/specification_version");
        fs::write(&spec, "0x0410\n").unwrap();
        fs::write(controller.join("device_descriptor/manufacturing_date"), "0x0125").unwrap();
        assert_eq!(facts(&sys, &proc), ("UFS4.1".into(), "SAMSUNG KLUFG4NHHB-F0G1 1500".into(), Some("2025-01".into())));
        fs::write(&spec, "0x0999\n").unwrap();
        assert_eq!(facts(&sys, &proc).0, "UFS");
        fs::remove_file(&spec).unwrap();
        assert_eq!(facts(&sys, &proc).0, "UFS");
        for field in ["vendor", "model", "rev"] { fs::remove_file(disk.join(field)).unwrap(); }
        let mut inquiry = vec![6, 2, 31, 2, 0, 0, 0, 0];
        inquiry.extend_from_slice(b"SAMSUNG KLUFG4NHHB-F0G1 1500");
        fs::write(disk.join("inquiry"), inquiry).unwrap();
        assert_eq!(facts(&sys, &proc).1, "SAMSUNG KLUFG4NHHB-F0G1 1500");
        fs::remove_file(sys.join("block/sda/size")).unwrap();
        assert_eq!(facts(&sys, &proc).0, "eMMC");
        fs::remove_dir_all(temp).unwrap();
    }
}
