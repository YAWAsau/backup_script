//! Shared payload presence rules and bounded streaming transport. No Android APIs.
use std::{collections::HashSet, fs, io::{self, Read, Write}, path::Path};

fn lines(path: &str) -> io::Result<HashSet<String>> {
    if path == "-" { return Ok(HashSet::new()); }
    Ok(fs::read_to_string(path)?.lines().filter(|s| !s.is_empty()).map(str::to_owned).collect())
}
fn safe(rel: &str) -> bool {
    !rel.is_empty() && !rel.contains(['\0', '\n', '\r']) && rel.split('/').all(|s| !s.is_empty() && s != "." && s != "..")
}
fn present(mode: &str, rel: &str, remote: &HashSet<String>, receipts: &HashSet<String>, root: &Path) -> bool {
    match mode {
        "remote" | "restore" => remote.contains(rel),
        "local" => root.join(rel).is_file() || (receipts.contains(rel) && remote.contains(rel)),
        _ => false,
    }
}
pub fn frame(mut input: impl Read, mut output: impl Write) -> io::Result<()> {
    let mut buf = [0u8; 65536];
    loop {
        let n = match input.read(&mut buf) { Err(e) if e.kind() == io::ErrorKind::Interrupted => continue, other => other? };
        output.write_all(&(n as u32).to_be_bytes())?;
        if n == 0 { return output.flush(); }
        output.write_all(&buf[..n])?;
    }
}
pub fn run(args: &[String]) -> i32 {
    let result = (|| -> io::Result<i32> {
        let invalid = || io::Error::new(io::ErrorKind::InvalidInput, "invalid workflow arguments");
        match args.get(1).map(String::as_str) {
            Some("frame-stream") if args.len() == 2 => { frame(io::stdin().lock(), io::stdout().lock())?; Ok(0) }
            Some("payload-presence") if args.len() == 7 && args[2] == "any" => {
                // This operation is valid for streamed backup OR streamed restore.
                if args[3] != "1" && args[4] != "1" { return Ok(1); }
                let targets: Vec<_> = args[6].split('\n').collect();
                if targets.iter().any(|rel| !safe(rel)) { return Err(invalid()); }
                // A one-off lookup needs no index allocation. Batch verification below
                // still builds one shared set for all expected payloads.
                let remote = fs::read_to_string(&args[5])?;
                let found = remote.lines().any(|rel| targets.contains(&rel));
                Ok(if found { 0 } else { 1 })
            }
            Some("payload-presence") if args.len() == 9 => {
                let mode = args[2].as_str();
                if !matches!(mode, "local" | "remote" | "restore") || !matches!(args[8].as_str(), ".tar" | ".tar.zst") { return Err(invalid()); }
                let expected = fs::read_to_string(&args[3])?;
                let remote = lines(&args[4])?;
                let receipts = lines(&args[5])?;
                let root = Path::new(&args[6]);
                if args[7] != "v1" { return Err(invalid()); }
                let mut missing = String::new();
                for rel in expected.lines().filter(|s| !s.is_empty()) {
                    if !safe(rel) { return Err(invalid()); }
                    let a = format!("{rel}{}", if mode == "local" { ".tar.zst" } else { &args[8] });
                    let b = format!("{rel}.tar");
                    if !present(mode, &a, &remote, &receipts, root) && !present(mode, &b, &remote, &receipts, root) {
                        missing.push_str(&format!("{rel}{}", args[8])); missing.push('\n');
                    }
                }
                // No partial plan is published on malformed input or I/O failure.
                io::stdout().lock().write_all(missing.as_bytes())?;
                Ok(0)
            }
            _ => Err(invalid()),
        }
    })();
    match result { Ok(rc) => rc, Err(e) => { eprintln!("WORKFLOW_ERROR {}", e.kind()); 2 } }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn receipt_requires_remote_confirmation() {
        let r=HashSet::from(["A/user.tar".to_owned()]); let empty=HashSet::new();
        assert!(!present("local","A/user.tar",&r,&empty,Path::new("/nonexistent")));
        assert!(!present("local","A/user.tar",&empty,&r,Path::new("/nonexistent")));
        assert!(present("local","A/user.tar",&r,&r,Path::new("/nonexistent")));
        assert!(present("restore","A/user.tar",&r,&empty,Path::new("/nonexistent")));
    }
    #[test] fn rejects_escaping_paths() { for p in ["/a", "../a", "a//b", "a/./b", "a\nb", ""] { assert!(!safe(p)); } assert!(safe("中文 App/user")); }
    #[test] fn framing_is_bounded_and_preserves_bytes() {
        let data=vec![37u8;131073]; let mut encoded=vec![]; frame(&data[..],&mut encoded).unwrap();
        let mut stream=&encoded[..]; let mut decoded=vec![];
        loop { let mut len=[0;4];stream.read_exact(&mut len).unwrap();let n=u32::from_be_bytes(len) as usize;if n==0 {break;} assert!(n<=65536);let mut part=vec![0;n];stream.read_exact(&mut part).unwrap();decoded.extend(part); }
        assert!(stream.is_empty());assert_eq!(decoded,data);
    }
    #[test] fn framing_propagates_read_failure() {
        struct Fail; impl Read for Fail { fn read(&mut self,_:&mut[u8])->io::Result<usize>{Err(io::Error::other("test"))} }
        let mut output=vec![];assert!(frame(Fail,&mut output).is_err());assert!(output.is_empty());
    }
}
