//! Read-only diagnostic report. Only aliases of this running ELF share a hash;
//! foreign files are always read again. No digest is persisted or authorizes execution.
use std::{collections::HashMap, fs::{self, File, Metadata, OpenOptions}, io, os::unix::fs::{MetadataExt, OpenOptionsExt}, path::Path, process::Command};
fn identity(m: &Metadata) -> String {
    format!("{}:{}:{}:{}:{}:{}:{}:{}:{}:{}:{}", m.dev(),m.ino(),m.len(),m.mode(),m.uid(),m.gid(),m.nlink(),m.mtime(),m.mtime_nsec(),m.ctime(),m.ctime_nsec())
}
fn first_lines(path: &str, operation: &str, count: &str) {
    // Fixed shell program, paths are positional arguments, never shell source.
    // The uncommon non-unified binary path retains its own version output.
    let _ = Command::new("/system/bin/sh").args(["-c", "\"$1\" \"$2\" 2>&1 | head -n \"$3\"", "tool-diagnostics", path, operation, count]).status();
}
pub fn run(args: &[String]) -> i32 {
    if args.len()%2!=0 || args.len()>16 || args.chunks(2).any(|p| !crate::multicall::APPLETS.contains(&p[0].as_str())) {
        eprintln!("tool-diagnostics: invalid applet/path pairs"); return 2;
    }
    let own=fs::metadata("/proc/self/exe").ok().map(|m|identity(&m));
    let mut hashes:HashMap<String,String>=HashMap::new();
    for pair in args.chunks(2) {
        let name=&pair[0];let path=&pair[1];
        println!("[{name}]");
        let opened=OpenOptions::new().read(true).custom_flags(2048).open(path);
        let same=opened.as_ref().ok().and_then(|f|f.metadata().ok()).is_some_and(|m| Some(identity(&m))==own)
            && Path::new(path).file_name().and_then(|n|n.to_str())==Some(name.as_str());
        if same {
            if let Some((_,version))=speedbackup_native_rs::APPLET_VERSIONS.iter().find(|(n,_)|*n==name) {
                println!("{name} {version} build={}",speedbackup_native_rs::BUILD_VERSION);
            }
        } else { first_lines(path,"--version","1"); }
        println!("path: {path}");
        let digest=(|| -> io::Result<String> {
            let mut file:File=opened?;let before=file.metadata()?;
            if !before.is_file(){return Err(io::Error::other("not a regular file"));}
            let key=identity(&before);
            let sha=match if same { hashes.get(&key) } else { None } {Some(s)=>s.clone(),None=>crate::speedscan::sha256_reader_hex(&mut file)?};
            if identity(&file.metadata()?)!=key || identity(&fs::metadata(path)?)!=key {return Err(io::Error::other("file changed during diagnostic hash"));}
            if same { hashes.insert(key,sha.clone()); }
            Ok(sha)
        })();
        match digest {Ok(sha)=>println!("sha256: {sha}"),Err(e)=>{println!("sha256: ");eprintln!("tool-diagnostics: {path}: {e}");}}
        if name=="cgfreezer" {first_lines(path,"backend-probe","2");}
        println!();
    }
    0
}
