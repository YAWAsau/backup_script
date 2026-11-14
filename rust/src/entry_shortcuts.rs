//! Root-owned pending restore entries; APK acknowledges only after durable private storage.
use std::{fs,io,path::{Path,PathBuf},os::unix::fs::{MetadataExt,PermissionsExt,OpenOptionsExt},io::Write};
const ROOT:&str="/data/.speedbackup/shortcuts";
// Read-only repair operations. Never source or execute the selected script.
pub fn path_command(args:&[String])->i32 {
    let result=(||->io::Result<String>{match args {
        [op,path,offset] if op=="browse" => super::applist_web::picker_listing(Path::new("/"),path,offset.parse().map_err(|_|io::Error::other("invalid offset"))?),
        [op,path,mode] if op=="validate" => validate_entry(path,mode),
        _=>Err(io::Error::other("invalid shortcut operation")),
    }})();
    match result {Ok(value)=>{println!("{value}");0},Err(e)=>{eprintln!("{e}");1}}
}
fn validate_entry(value:&str,mode:&str)->io::Result<String>{
    if !matches!(mode,"0"|"2")||!Path::new(value).is_absolute()||value.chars().any(|c|c.is_control())||value.len()>4096{return Err(io::Error::other("無效的捷徑路徑"));}
    let path=fs::canonicalize(value)?;
    if path.file_name().and_then(|s|s.to_str())!=Some("start.sh"){return Err(io::Error::other("請選擇 start.sh"));}
    let mut f=fs::OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK).open(&path)?;
    let m=f.metadata()?;
    if !m.is_file()||m.len()>1024*1024{return Err(io::Error::other("入口不是有效的一般檔案"));}
    let mut text=String::new();std::io::Read::read_to_string(&mut std::io::Read::take(&mut f,1024*1024+1),&mut text)?;
    if text.len()>1024*1024{return Err(io::Error::other("入口檔案過大"));}
    validate_mode(&text,mode)?;
    Ok(serde_json::json!({"path":path.to_str().ok_or_else(||io::Error::other("路徑編碼無效"))?,"mode":mode}).to_string())
}
fn validate_mode(text:&str,mode:&str)->io::Result<()> {
    let declarations:Vec<_>=text.lines().map(str::trim).filter(|s|s.starts_with("export SPEEDBACKUP_ENTRY_MODE=")).collect();
    let expected=format!("export SPEEDBACKUP_ENTRY_MODE=\"{mode}\"");
    if declarations.len()!=1||declarations[0]!=expected{return Err(io::Error::other("入口類型不符或無法識別：備份捷徑只能選備份入口，恢復捷徑只能選恢復入口"));}Ok(())
}
fn directory()->io::Result<PathBuf>{
    let p=PathBuf::from(ROOT);fs::create_dir_all(&p)?;
    let m=fs::symlink_metadata(&p)?;
    if !m.is_dir()||m.uid()!=0||m.file_type().is_symlink(){return Err(io::Error::other("unsafe shortcut registry"));}
    fs::set_permissions(&p,fs::Permissions::from_mode(0o700))?;Ok(p)
}
fn valid_id(id:&str)->bool{id.len()==64&&id.bytes().all(|b|b.is_ascii_hexdigit())}
fn restore_path(value:&str)->io::Result<String>{
    if value.contains(['\n','\r','\0'])||!Path::new(value).is_absolute(){return Err(io::Error::other("invalid entry path"));}
    let path=fs::canonicalize(value)?;
    if path.file_name().and_then(|s|s.to_str())!=Some("start.sh"){return Err(io::Error::other("not a menu entry"));}
    let m=fs::metadata(&path)?;
    if !m.is_file()||m.len()>1024*1024{return Err(io::Error::other("invalid entry"));}
    let text=fs::read_to_string(&path)?;
    if !text.lines().any(|l|l.trim()=="export SPEEDBACKUP_ENTRY_MODE=\"2\""){return Err(io::Error::other("not a restore entry"));}
    path.to_str().map(str::to_owned).ok_or_else(||io::Error::other("invalid path encoding"))
}
pub fn register(value:&str)->io::Result<()>{
    let value=restore_path(value)?;let root=directory()?;
    let id=super::sha256_reader_hex(value.as_bytes())?;
    let tmp=root.join(format!(".{id}.{}",std::process::id()));
    let result=(||{let mut f=fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&tmp)?;f.write_all(value.as_bytes())?;f.sync_all()?;fs::rename(&tmp,root.join(id))})();
    if result.is_err(){let _=fs::remove_file(tmp);}result
}
fn stale_missing(error:&io::Error,age:Option<std::time::Duration>)->bool{error.kind()==io::ErrorKind::NotFound&&age.is_some_and(|a|a.as_secs()>=30*86400)}
pub fn pending()->io::Result<String>{
    let root=directory()?;let mut entries=Vec::new();
    for entry in fs::read_dir(root)?.take(1024){let entry=entry?;let id=entry.file_name().to_string_lossy().into_owned();
        if !valid_id(&id){continue;}let m=fs::symlink_metadata(entry.path())?;
        if !m.is_file()||m.uid()!=0||m.len()>16384{continue;}
        match fs::read_to_string(entry.path()).and_then(|p|restore_path(&p)){
            Ok(path)=>entries.push(serde_json::json!({"id":id,"path":path,"mode":"2"})),
            Err(e)=>{
                // Removable storage may be temporarily absent. Expire only missing
                // entries after 30 days; never discard permission/read failures.
                if stale_missing(&e,m.modified().ok().and_then(|t|t.elapsed().ok())){let _=fs::remove_file(entry.path());}
            }
        }
    }Ok(serde_json::Value::Array(entries).to_string())
}
pub fn ack(id:&str)->io::Result<()>{if !valid_id(id){return Err(io::Error::other("invalid entry id"));}match fs::remove_file(directory()?.join(id)){Err(e)if e.kind()==io::ErrorKind::NotFound=>Ok(()),r=>r}}
pub fn run(args:&[String])->i32{if args.len()!=1{return 64;}match register(&args[0]){Ok(())=>0,Err(e)=>{eprintln!("RESTORE_SHORTCUT_PENDING_FAILED {e}");1}}}
#[cfg(test)]mod tests{use super::*;
#[test]fn expires_only_old_missing_entries(){let missing=io::Error::from(io::ErrorKind::NotFound);assert!(!stale_missing(&missing,Some(std::time::Duration::from_secs(60))));assert!(stale_missing(&missing,Some(std::time::Duration::from_secs(30*86400))));assert!(!stale_missing(&io::Error::from(io::ErrorKind::PermissionDenied),Some(std::time::Duration::from_secs(90*86400))));}
#[test]fn rejects_action_and_relative_paths(){assert!(restore_path("start.sh").is_err());assert!(restore_path("/tmp/a\n/start.sh").is_err());assert!(!valid_id("../entry"));assert!(valid_id(&"a".repeat(64)));}}
