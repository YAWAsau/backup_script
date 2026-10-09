//! Owned-child supervision; no shell watchdog and no PID-reuse window.
use speedbackup_native_rs::{close, kill, pidfd_open, poll, PollFd, POLLIN, SIGKILL, SIGTERM};
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use std::sync::atomic::{AtomicI32, Ordering};
static CANCEL:AtomicI32=AtomicI32::new(0);
extern "C" fn cancelled(sig:i32){CANCEL.store(sig,Ordering::Relaxed);}
extern "C" {fn signal(sig:i32,handler:usize)->usize;}

fn trace_open() -> Option<File> {
    let path=std::env::var_os("SPEEDBACKUP_BOUNDED_LOG").filter(|p| !p.is_empty())?;
    match fs::OpenOptions::new().create(true).append(true).open(path) {
        Ok(f)=>Some(f),
        Err(e)=>{eprintln!("NATIVE_BOUNDED_LOG_FAILED stage=open error={}",e);None}
    }
}
fn trace(file:&mut Option<File>,line:String) {
    if let Some(f)=file {
        if let Err(e)=writeln!(f,"{}",line) {
            eprintln!("NATIVE_BOUNDED_LOG_FAILED stage=write error={}",e);
            *file=None;
        }
    }
}

pub fn bounded(args: &[String]) -> i32 {
    if args.len()<4 { return 2; }
    let ms=match args[0].parse::<u64>() { Ok(v) if v<=600_000=>v, _=>return 2 };
    // Recursive supervisors are not meaningful. Only this executable is launched.
    if matches!(args[3].as_str(),"bounded-run"|"facts-result") {return 2;}
    let output=match File::create(&args[2]) {Ok(f)=>f,Err(_)=>return 1};
    let exe=match std::env::current_exe(){Ok(p)=>p,Err(_)=>return 1};
    let start=Instant::now();
    for sig in [1,2,15]{unsafe{signal(sig,cancelled as *const () as usize);}}
    let mut child=match Command::new(exe).arg("speedscan").args(&args[3..])
        .stdin(Stdio::null()).stdout(output).stderr(Stdio::inherit()).spawn(){Ok(c)=>c,Err(_)=>return 1};
    let pid=child.id() as i32;
    let fd=if std::env::var("SPEEDBACKUP_NATIVE_WAIT_BACKEND").as_deref()==Ok("poll"){None}else{pidfd_open(pid).ok()};
    let backend=if fd.is_some(){"pidfd"}else{"waitpid"};
    let mut diagnostic=trace_open();
    trace(&mut diagnostic,format!("NATIVE_BOUNDED_BEGIN tag={} pid={} timeoutMs={} backend={}",args[1],pid,ms,backend));
    let mut timeout=false;let mut phase=0;let mut deadline=Duration::from_millis(ms);
    let rc=loop {
        let cancel=CANCEL.load(Ordering::Relaxed);
        match child.try_wait(){
            Ok(Some(s))=>break if cancel!=0{128+cancel}else if timeout{124}else{s.code().unwrap_or(128+s.signal().unwrap_or(0))},
            Err(e) if e.kind()==io::ErrorKind::Interrupted=>continue,
            Err(_)=>break 125,
            Ok(None)=>{}
        }
        let now=start.elapsed();
        if cancel!=0 && phase==0{deadline=now;}
        if now>=deadline {
            if phase==2 { eprintln!("NATIVE_BOUNDED_UNREAPED pid={} timeout=true signal={}",pid,cancel);break if cancel!=0{128+cancel}else{124}; }
            timeout=true;
            // Child has not been reaped. PID cannot be recycled before try_wait.
            unsafe {kill(pid,if phase==0{SIGTERM}else{SIGKILL});}
            phase+=1;deadline=now+Duration::from_millis(700);
        }
        let wait=deadline.saturating_sub(start.elapsed()).as_millis().min(if fd.is_some(){1000}else{10}) as i32;
        if let Some(fd)=fd {let mut p=PollFd{fd,events:POLLIN,revents:0};unsafe{poll(&mut p,1,wait.max(1));}}
        else {std::thread::sleep(Duration::from_millis(wait.max(1) as u64));}
    };
    if let Some(fd)=fd {unsafe{close(fd);}}
    let done=format!("NATIVE_BOUNDED_DONE tag={} pid={} rc={} elapsedMs={} backend={}",args[1],pid,rc,start.elapsed().as_millis(),backend);
    if rc!=0 {eprintln!("{}",done);}
    trace(&mut diagnostic,done);
    rc
}

fn regular(path:&Path)->io::Result<bool>{
    match fs::symlink_metadata(path){Ok(m) if m.file_type().is_file()=>Ok(true),Err(e) if e.kind()==io::ErrorKind::NotFound=>Ok(false),_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"regular file required"))}
}
fn remove(path:&Path)->io::Result<()>{if regular(path)?{fs::remove_file(path)?;}Ok(())}
fn preserve(src:&Path,dir:&Path,name:&str)->io::Result<String>{
    if !regular(src)? || fs::metadata(src)?.len()==0{return Ok("none".into());}
    let dst=dir.join(name);
    if dst.exists(){return Err(io::Error::new(io::ErrorKind::AlreadyExists,"detail exists"));}
    // create_new prevents following a concurrently introduced symlink.
    let mut out=fs::OpenOptions::new().write(true).create_new(true).open(&dst)?;
    io::copy(&mut File::open(src)?,&mut out)?;Ok(name.into())
}
fn result(args:&[String])->io::Result<()> {
    if args.len()!=9{return Err(io::Error::new(io::ErrorKind::InvalidInput,"arguments"));}
    let data=Path::new(&args[0]);let sum=Path::new(&args[1]);let dir=Path::new(&args[5]);let stem=&args[6];
    if !stem.starts_with("speedscan_") || stem.contains('/') || stem.contains('\\') || stem.contains("..") || !dir.is_dir() || data==sum{return Err(io::Error::new(io::ErrorKind::InvalidInput,"scope"));}
    // Only diagnostic files under the explicitly supplied scratch/log directories.
    let scratch=fs::canonicalize(&args[8])?;let logs=fs::canonicalize(dir)?;
    for p in [data,sum]{
        let parent=fs::canonicalize(p.parent().ok_or(io::ErrorKind::InvalidInput)?)?;
        if parent!=scratch&&parent!=logs{return Err(io::Error::new(io::ErrorKind::InvalidInput,"outside scope"));}
        let name=p.file_name().and_then(|s|s.to_str()).unwrap_or("");
        if !name.starts_with(stem)&&!name.starts_with(&format!(".{}",stem)){return Err(io::Error::new(io::ErrorKind::InvalidInput,"file name"));}
        regular(p)?;
    }
    let mut rows=0;
    if regular(data)? {for line in BufReader::new(File::open(data)?).split(b'\n'){if line?.starts_with(args[7].as_bytes()){rows+=1;}}}
    let mut summary=Vec::new();if regular(sum)?{File::open(sum)?.take(700).read_to_end(&mut summary)?;}
    let summary=String::from_utf8_lossy(&summary).replace(['\n','\r'],"|");
    let ok=args[2]=="0"&&regular(data)?&&fs::metadata(data)?.len()>0;
    let detail=if ok&&args[3]=="1" {format!("kept:{}",data.file_name().unwrap().to_string_lossy())}
        else if !ok&&args[4]=="1" {
            let a=preserve(data,dir,&format!("{}.error.tsv",stem))?;
            let b=preserve(sum,dir,&format!("{}.error.summary.txt",stem))?;
            format!("error:{},{}",a,b)
        }else if ok{"summary-only".into()}else{"none".into()};
    if !(ok&&args[3]=="1"){remove(data)?;remove(sum)?;}
    println!("status={}\nrows={}\ndetail={}\nsummary={}",if ok{"ok"}else{"fail"},rows,detail,summary);
    Ok(())
}
pub fn facts_result(args:&[String])->i32{match result(args){Ok(())=>0,Err(e)=>{eprintln!("FACTS_RESULT_FAILED {}",e);1}}}

pub fn prune_legacy(args:&[String])->i32 {
    if args.len()!=1 || args[0]!="/data/.speedbackup_tmp" {return 2;}
    let base=Path::new(&args[0]);
    if !base.exists(){return 0;}
    if fs::canonicalize(base).ok().as_deref()!=Some(base){return 1;}
    let entries=match fs::read_dir(base){Ok(e)=>e,Err(_)=>return 1};
    let mut removed=0;let mut retained=0;
    for e in entries.flatten(){
        let name=e.file_name();let name=name.to_string_lossy();let p=e.path();
        let kind=match e.file_type(){Ok(t)=>t,Err(_)=>continue};
        if !kind.is_dir() || kind.is_symlink(){continue;}
        let res=if let Some(raw)=name.strip_prefix(".smbclient_pids_") {
            let pid=match raw.parse::<u32>(){Ok(p) if p>1=>p,_=>{retained+=1;continue}};
            if Path::new(&format!("/proc/{}",pid)).exists(){retained+=1;continue;}
            fs::remove_dir_all(&p)
        }else if [".speedbackup_process_observer_batch_state",".speedbackup_uid_netblock_state",".speedbackup_wakeblock_state",".speedbackup_notify_state"].contains(&name.as_ref()){
            fs::remove_dir(&p)
        }else{continue};
        if res.is_ok(){removed+=1}else{retained+=1}
    }
    println!("TMPDIR_ROOT_NAMESPACE_PRUNE removed={} retained={} legacyOnly=1 backend=rust",removed,retained);0
}
