//! Session diagnostics: bounded snapshots and presentation-independent log records.
use std::{fs::{self,OpenOptions},io::{self,Read,Write,Seek,SeekFrom},os::unix::fs::{OpenOptionsExt,MetadataExt},path::Path,process::Command};
use serde_json::{json,Value};
fn regular(path:&Path)->io::Result<std::fs::File>{
    let f=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK).open(path)?;
    if !f.metadata()?.is_file(){return Err(io::Error::other("not a regular diagnostic file"));} Ok(f)
}
fn copy_tail(src:&Path,dst:&Path,limit:u64)->io::Result<()> {
    let mut input=regular(src)?;let n=input.metadata()?.len();input.seek(SeekFrom::Start(n.saturating_sub(limit)))?;
    let mut out=OpenOptions::new().write(true).create(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK).open(dst)?;
    let m=out.metadata()?;if !m.is_file()||m.nlink()!=1{return Err(io::Error::other("invalid diagnostic destination"));}
    out.set_len(0)?;io::copy(&mut input.take(limit),&mut out)?;Ok(())
}
fn snapshot_base(base:&Path,run:&Path,tag:&str,web:bool){
    if fs::symlink_metadata(base).map_or(true,|m|!m.is_dir()){return;}
    let mut items=vec![("service.log".to_string(),format!("console-{tag}-service.log")),("caller-errors.log".into(),format!("console-{tag}-caller-errors.log"))];
    if web{items.insert(0,("webui-errors.log".into(),"webui-console.log".into()));}
    for (src,dst) in items {
        let path=base.join(&src);if fs::symlink_metadata(&path).map_or(true,|m|!m.is_file()){continue;}
        if let Err(e)=copy_tail(&path,&run.join(dst),1048576){eprintln!("CONSOLE_DIAGNOSTIC_SNAPSHOT_FAILED {src}: {e}");}
    }
}
pub fn snapshot_command(args:&[String])->i32{
    if args.len()!=2{return 2;}
    let run=Path::new(&args[0]);
    if !run.starts_with("/data/speed_debug")||run.canonicalize().ok().as_deref()!=Some(run)||!run.is_dir(){return 2;}
    snapshot_base(Path::new("/data/.speedbackup/console/active"),run,"current",args[1]=="/data/.speedbackup/console/active");
    snapshot_base(Path::new("/data/.speedbackup_console/active"),run,"legacy",false);
    let crashes=run.join("crashes");
    if fs::create_dir_all(&crashes).is_ok()&&super::crash_diagnostics::run(&[crashes.to_string_lossy().into_owned()])!=0{eprintln!("CRASH_DIAGNOSTICS_UNAVAILABLE path={}",crashes.display());}
    let base=Path::new("/data/.speedbackup/console/active/crashes");
    if fs::symlink_metadata(base).is_ok_and(|m|m.is_dir()){
        if let Ok(entries)=fs::read_dir(base){for entry in entries.flatten(){
            let name=entry.file_name();let name=name.to_string_lossy();
            if name.ends_with(".log")&&entry.file_type().is_ok_and(|m|m.is_file()){
                if let Err(e)=copy_tail(&entry.path(),&run.join(format!("console-crash-{name}")),2097152){eprintln!("CONSOLE_CRASH_SNAPSHOT_FAILED {name}: {e}");}
            }
        }}
    }0
}
fn property(key:&str)->String{
    #[cfg(target_os="android")]{
        unsafe extern "C"{fn __system_property_get(name:*const std::ffi::c_char,value:*mut std::ffi::c_char)->i32;}
        let key=std::ffi::CString::new(key).unwrap();let mut value=[0u8;92];
        let n=unsafe{__system_property_get(key.as_ptr(),value.as_mut_ptr().cast())};
        if n>0&&(n as usize)<value.len(){return String::from_utf8_lossy(&value[..n as usize]).into_owned();}
    }let _=key;String::new()
}
fn output(program:&str,args:&[&str])->String{
    match Command::new(program).args(args).output(){Ok(o)=>{let _=io::stderr().write_all(&o.stderr);String::from_utf8_lossy(&o.stdout).trim_end_matches('\n').to_owned()},Err(e)=>{eprintln!("{program}: {e}");String::new()}}
}
pub fn init_command(args:&[String])->i32{
    if args.len()!=8{return 2;}
    // Keep date/id's platform-specific formatting (including supplementary groups and context).
    println!("time={}",output("date",&["+%Y-%m-%d %H:%M:%S"]));
    println!("pid={} shell_dollar_pid={}\nscript={}\nentry_script={}\nentry_mode={}\ntimelineMode=builtin-print\nprintMode={}\ntools_path={}\nshell={}",args[0],args[1],args[2],args[3],args[4],args[5],args[6],args[7]);
    println!("user={}",output("id",&[]));
    println!("android={} sdk={}",property("ro.build.version.release"),property("ro.build.version.sdk"));
    println!("device={} {}",property("ro.product.manufacturer"),property("ro.product.model"));0
}
fn strip_ansi(text:&str)->String{
    let b=text.as_bytes();let mut out=String::new();let mut start=0;let mut i=0;
    while i+1<b.len(){
        if b[i]==27&&b[i+1]==b'['{
            let mut j=i+2;while j<b.len()&&(b'0'..=b'?').contains(&b[j]){j+=1;}
            while j<b.len()&&(b' '..=b'/').contains(&b[j]){j+=1;}
            if j<b.len()&&(b'@'..=b'~').contains(&b[j]){out.push_str(&text[start..i]);i=j+1;start=i;continue;}
        }i+=1;
    }out.push_str(&text[start..]);out
}
fn whitespace(c:u8)->bool{matches!(c,b' '|b'\t'|b'\n'|b'\r'|11|12)}
fn explicit_level(line:&str)->Option<&'static str>{
    let b=line.as_bytes();
    for i in 0..b.len(){
        if i>0&&!whitespace(b[i-1])&&b[i-1]!=b'['{continue;}
        for (word,level) in [("ERROR","ERROR"),("WARN","WARN"),("INFO","INFO"),("DEBUG","DEBUG"),("FATAL","ERROR"),("VERBOSE","DEBUG"),("E","ERROR"),("W","WARN"),("I","INFO"),("D","DEBUG"),("V","DEBUG"),("F","ERROR")]{
            let end=i+word.len();if end>b.len(){continue;}
            if b[i..end].eq_ignore_ascii_case(word.as_bytes())&&(end==b.len()||whitespace(b[end])||matches!(b[end],b']'|b':'|b'/')){return Some(level);}
        }
    }None
}
fn take_utf16(text:&str,n:usize)->String{let mut used=0;text.chars().take_while(|c|{used+=c.len_utf16();used<=n}).collect()}
fn logcat_level(line:&str)->&'static str{let f=line.split_whitespace().collect::<Vec<_>>();if f.len()>=6&&f[2].parse::<u32>().is_ok()&&f[3].parse::<u32>().is_ok(){match f[4]{"V"=>"VERBOSE","D"=>"DEBUG","I"=>"INFO","W"=>"WARN","E"=>"ERROR","F"=>"FATAL",_=>"OTHER"}}else{"OTHER"}}
#[cfg(test)]
pub fn view(text:&str,level:&str,truncated:bool)->Value{view_format(text,level,truncated,false,false)}
pub fn view_file(name:&str,text:&str,level:&str,truncated:bool)->Value{view_format(text,level,truncated,name.contains("logcat-"),!name.contains("logcat-"))}
fn view_format(text:&str,level:&str,truncated:bool,logcat:bool,report:bool)->Value{
    let level=if report{"ALL"}else{level};
    let cleaned=strip_ansi(text).replace("\r\n","\n").replace('\r',"\n");
    let mut inherited="OTHER";let mut rows=Vec::new();let mut has_content=false;
    for line in cleaned.split('\n'){
        if (logcat||report)&&line.starts_with("# ===== operation=")&&line.ends_with(" indexed-blocks ====="){continue;}
        if !line.trim().is_empty(){has_content=true;}
        let actual=if report{"OTHER"}else if logcat{logcat_level(line)}else{explicit_level(line).unwrap_or_else(||if line.starts_with('\t')||line.starts_with("    ")||line.starts_with("Caused by:"){inherited}else{"OTHER"})};
        inherited=actual;if level=="ALL"||actual==level{rows.push((actual,line));}
    }
    let omitted=rows.len()>160;let start=rows.len().saturating_sub(160);let mut budget=60000;let mut records=Vec::new();
    for (actual,line) in &rows[start..]{let line=take_utf16(line,budget.min(8192));budget-=line.encode_utf16().count();if !line.is_empty(){records.push(json!({"level":actual,"text":line}));}}
    json!({"truncated":truncated,"limited":truncated||omitted,"empty":records.is_empty(),"fileEmpty":if logcat||report{!has_content}else{text.is_empty()},"records":records})
}
#[cfg(test)]
mod diagnostic_migration_tests {
    use super::*;
    #[test]
    fn levels_ansi_continuations_and_bounds(){
        let source="\x1b[31m[ERROR] failed\x1b[0m\n    at frame\nCaused by: x\nplain\n[DEBUG] detail\nWARN\ninfo: value\nV/ tag\r\n";
        let e=view(source,"ERROR",false);let rows=e["records"].as_array().unwrap();assert_eq!(rows.len(),3);assert_eq!(rows[0]["text"],"[ERROR] failed");
        let other=view(source,"OTHER",false);assert_eq!(other["records"][0]["text"],"plain");assert_eq!(other["records"].as_array().unwrap().len(),1);assert_eq!(view(source,"WARN",false)["records"][0]["text"],"WARN");
        assert_eq!(view(source,"DEBUG",false)["records"].as_array().unwrap().len(),2);
        assert_eq!(view("\x1b[broken","ALL",false)["records"][0]["text"],"roken");
        assert_eq!(view("","ALL",false)["empty"],true);
        let text=(0..200).map(|i|format!("[INFO] {i}\n")).collect::<String>();let v=view(&text,"INFO",false);
        assert_eq!(v["records"].as_array().unwrap().len(),160);assert_eq!(v["records"][0]["text"],"[INFO] 40");assert_eq!(v["limited"],true);
        let v=view(&format!("{}\n", "a".repeat(9000)).repeat(20),"ALL",true);
        let rows=v["records"].as_array().unwrap();assert_eq!(rows.iter().map(|v|v["text"].as_str().unwrap().len()).sum::<usize>(),60000);
    }
    #[test]
    #[ignore="isolated Android device test"]
    fn snapshot_limits_and_links(){
        let root=std::path::PathBuf::from(format!("/data/local/tmp/sb-diagnostic-snapshot-{}",std::process::id()));fs::create_dir(&root).unwrap();
        struct Cleanup(std::path::PathBuf);impl Drop for Cleanup{fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}
        let _cleanup=Cleanup(root.clone());let src=root.join("src");let dst=root.join("dst");fs::create_dir(&src).unwrap();fs::create_dir(&dst).unwrap();
        let data=vec![b'x';1048576+13];fs::write(src.join("service.log"),&data).unwrap();fs::write(src.join("webui-errors.log"),"web").unwrap();
        std::os::unix::fs::symlink(src.join("service.log"),src.join("caller-errors.log")).unwrap();
        snapshot_base(&src,&dst,"current",true);
        assert_eq!(fs::read(dst.join("console-current-service.log")).unwrap(),data[13..]);assert_eq!(fs::read_to_string(dst.join("webui-console.log")).unwrap(),"web");assert!(!dst.join("console-current-caller-errors.log").exists());
        fs::write(root.join("untouched"),"safe").unwrap();std::os::unix::fs::symlink(root.join("untouched"),dst.join("bad")).unwrap();
        let native_start=std::time::Instant::now();for _ in 0..10{snapshot_base(&src,&dst,"current",true);}let native_us=native_start.elapsed().as_micros();
        let shell_start=std::time::Instant::now();for _ in 0..10{assert!(Command::new("/system/bin/sh").args(["-c", "tail -c 1048576 \"$1/service.log\" > \"$2/console-current-service.log\"; tail -c 1048576 \"$1/webui-errors.log\" > \"$2/webui-console.log\"", "test",src.to_str().unwrap(),dst.to_str().unwrap()]).status().unwrap().success());}
        println!("SNAPSHOT_BENCH native_mean_us={} shell_mean_us={}",native_us/10,shell_start.elapsed().as_micros()/10);
        assert!(copy_tail(&src.join("service.log"),&dst.join("bad"),8).is_err());assert_eq!(fs::read_to_string(root.join("untouched")).unwrap(),"safe");
    }
}

pub fn sources()->io::Result<Value>{
    let base=Path::new("/data/speed_debug");if base.canonicalize()?!=base{return Err(io::Error::other("invalid diagnostic directory"));}
    let mut entries=Vec::new();
    for e in fs::read_dir("/data/speed_debug")?{let e=e?;let name=e.file_name().to_string_lossy().into_owned();
        if name.starts_with("speed_debug_")&&name.ends_with(".tar")&&e.file_type()?.is_file(){let m=e.metadata()?;entries.push((m.mtime(),name,m.len()));}}
    entries.sort_by(|a,b|b.0.cmp(&a.0).then(a.1.cmp(&b.1)));
    Ok(json!(entries.into_iter().map(|(time,name,size)|json!({"id":name,"label":name,"modified":time,"bytes":size})).collect::<Vec<_>>()))
}
pub fn source_path(name:&str)->io::Result<std::path::PathBuf>{
    if name.contains('/')||name.contains('\\')||!name.starts_with("speed_debug_")||!name.ends_with(".tar")||name.contains('\0'){return Err(io::Error::other("invalid diagnostic archive selection"));}
    let base=Path::new("/data/speed_debug");if base.canonicalize()?!=base{return Err(io::Error::other("invalid diagnostic directory"));}
    let path=base.join(name);let f=regular(&path)?;
    if f.metadata()?.nlink()!=1{return Err(io::Error::other("invalid diagnostic archive link"));}Ok(path)
}
struct HistoryCache{identity:(std::path::PathBuf,u64,u64,i64,i64,i64,i64),files:std::collections::BTreeMap<String,Vec<u8>>}
static HISTORY:std::sync::Mutex<Option<HistoryCache>>=std::sync::Mutex::new(None);
pub fn history_response(source:&str,selected:Option<&str>,level:&str)->io::Result<Value>{
    let path=source_path(source)?;let m=regular(&path)?.metadata()?;
    let identity=(path.clone(),m.ino(),m.len(),m.mtime(),m.mtime_nsec(),m.ctime(),m.ctime_nsec());
    let mut cache=HISTORY.lock().map_err(|_|io::Error::other("history cache unavailable"))?;
    if cache.as_ref().is_none_or(|c|c.identity!=identity){
        *cache=None;
        let files=super::debug_archive::history(&path)?;
        let after=regular(&path)?.metadata()?;
        if (after.ino(),after.len(),after.mtime(),after.mtime_nsec(),after.ctime(),after.ctime_nsec())!=(m.ino(),m.len(),m.mtime(),m.mtime_nsec(),m.ctime(),m.ctime_nsec()){return Err(io::Error::other("除錯包已更新，請重新整理"));}
        *cache=Some(HistoryCache{identity,files});
    }
    let files=&cache.as_ref().unwrap().files;
    let allowed=|name:&str|matches!(Path::new(name).extension().and_then(|e|e.to_str()),Some("log"|"txt"|"tsv"));
    if let Some(name)=selected{
        let bytes=files.get(name).filter(|_|allowed(name)).ok_or_else(||io::Error::other("invalid historical log selection"))?;
        let start=bytes.len().saturating_sub(65536);let text=String::from_utf8_lossy(&bytes[start..]);
        let text=if start>0{text.split_once('\n').map(|(_,s)|s).unwrap_or("")}else{&text};
        Ok(view_file(name,&super::crash_diagnostics::redact(text),level,start>0))
    }else{Ok(json!(files.keys().filter(|n|allowed(n)).collect::<Vec<_>>()))}
}

#[cfg(test)]
mod diagnostic_history_tests {
    use super::*;
    #[test]
    #[ignore="isolated Android device test"]
    fn indexed_history_and_invalidation(){
        let base=Path::new("/data/speed_debug");fs::create_dir_all(base).unwrap();let id=format!("history_test_{}",std::process::id());let run=base.join(&id);fs::create_dir(&run).unwrap();let archive=base.join(format!("speed_debug_{id}.tar"));
        struct Cleanup(std::path::PathBuf,std::path::PathBuf);impl Drop for Cleanup{fn drop(&mut self){let _=fs::remove_dir_all(&self.0);let _=fs::remove_file(&self.1);*HISTORY.lock().unwrap()=None;}}let _cleanup=Cleanup(run.clone(),archive.clone());
        fs::write(run.join("main.log"),"[ERROR] old\n[DEBUG] detail\n").unwrap();
        super::super::debug_archive::archive(Path::new("/data/.speedbackup/tools/tar"),&archive,&run,true,std::time::Duration::from_secs(5)).unwrap();
        let name=archive.file_name().unwrap().to_str().unwrap();let file=format!("{id}/main.log");
        let cold=std::time::Instant::now();assert_eq!(history_response(name,None,"ALL").unwrap(),json!([file]));let cold_us=cold.elapsed().as_micros();
        let warm=std::time::Instant::now();for _ in 0..20{history_response(name,Some(&file),"ERROR").unwrap();}println!("HISTORY_BENCH cold_us={cold_us} cached_mean_us={}",warm.elapsed().as_micros()/20);
        assert_eq!(history_response(name,Some(&file),"ERROR").unwrap()["records"][0]["text"],"[ERROR] old");
        assert!(history_response(name,Some("../main.log"),"ALL").is_err());
        fs::write(run.join("main.log"),"[INFO] changed\n").unwrap();
        super::super::debug_archive::archive(Path::new("/data/.speedbackup/tools/tar"),&archive,&run,true,std::time::Duration::from_secs(5)).unwrap();
        assert_eq!(history_response(name,Some(&file),"INFO").unwrap()["records"][0]["text"],"[INFO] changed");
        assert!(source_path("../../outside.tar").is_err());
    }
}

#[cfg(test)]
mod diagnostic_oracle_tests {
 #[test]
 fn java_regex_parity(){
 for (line,expected) in [
  ("ERROR","ERROR"),
  ("ERROR:","ERROR"),
  ("ERROR/","ERROR"),
  ("ERROR ","ERROR"),
  ("ERROR]","ERROR"),
  ("ERRORx","OTHER"),
  ("WARN","WARN"),
  ("WARN:","WARN"),
  ("WARN/","WARN"),
  ("WARN ","WARN"),
  ("WARN]","WARN"),
  ("WARNx","OTHER"),
  ("INFO","INFO"),
  ("INFO:","INFO"),
  ("INFO/","INFO"),
  ("INFO ","INFO"),
  ("INFO]","INFO"),
  ("INFOx","OTHER"),
  ("DEBUG","DEBUG"),
  ("DEBUG:","DEBUG"),
  ("DEBUG/","DEBUG"),
  ("DEBUG ","DEBUG"),
  ("DEBUG]","DEBUG"),
  ("DEBUGx","OTHER"),
  ("FATAL","ERROR"),
  ("FATAL:","ERROR"),
  ("FATAL/","ERROR"),
  ("FATAL ","ERROR"),
  ("FATAL]","ERROR"),
  ("FATALx","OTHER"),
  ("VERBOSE","DEBUG"),
  ("VERBOSE:","DEBUG"),
  ("VERBOSE/","DEBUG"),
  ("VERBOSE ","DEBUG"),
  ("VERBOSE]","DEBUG"),
  ("VERBOSEx","OTHER"),
  ("E","ERROR"),
  ("E:","ERROR"),
  ("E/","ERROR"),
  ("E ","ERROR"),
  ("E]","ERROR"),
  ("Ex","OTHER"),
  ("W","WARN"),
  ("W:","WARN"),
  ("W/","WARN"),
  ("W ","WARN"),
  ("W]","WARN"),
  ("Wx","OTHER"),
  ("I","INFO"),
  ("I:","INFO"),
  ("I/","INFO"),
  ("I ","INFO"),
  ("I]","INFO"),
  ("Ix","OTHER"),
  ("D","DEBUG"),
  ("D:","DEBUG"),
  ("D/","DEBUG"),
  ("D ","DEBUG"),
  ("D]","DEBUG"),
  ("Dx","OTHER"),
  ("V","DEBUG"),
  ("V:","DEBUG"),
  ("V/","DEBUG"),
  ("V ","DEBUG"),
  ("V]","DEBUG"),
  ("Vx","OTHER"),
  ("F","ERROR"),
  ("F:","ERROR"),
  ("F/","ERROR"),
  ("F ","ERROR"),
  ("F]","ERROR"),
  ("Fx","OTHER"),
  ("warn","WARN"),
  ("warn:","WARN"),
  ("warn/","WARN"),
  ("warn ","WARN"),
  ("warn]","WARN"),
  ("warnx","OTHER"),
  ("fatal","ERROR"),
  ("fatal:","ERROR"),
  ("fatal/","ERROR"),
  ("fatal ","ERROR"),
  ("fatal]","ERROR"),
  ("fatalx","OTHER"),
  ("xERROR failed","OTHER"),
  ("prefix [ERROR] issue","ERROR"),
  ("\tW","WARN"),
  (" WARN","OTHER"),
  ("x\nWARN","WARN"),
  ("plain","OTHER"),
  ("[E] x","ERROR"),
  ("warn: INFO x","WARN"),
] {assert_eq!(super::explicit_level(line).unwrap_or("OTHER"),expected,"{line:?}");}
 }
}
