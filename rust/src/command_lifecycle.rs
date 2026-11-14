//! Owned-child supervision; no shell watchdog and no PID-reuse window.
use speedbackup_native_rs::{kill, pidfd_open, poll, PollFd, POLLIN, SIGKILL, SIGTERM};
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::process::ExitStatusExt;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use std::sync::atomic::{AtomicI32, Ordering};
static CANCEL:AtomicI32=AtomicI32::new(0);
static CANCEL_FD:AtomicI32=AtomicI32::new(-1);
extern "C" fn cancelled(sig:i32){
    CANCEL.store(sig,Ordering::Relaxed);
    let fd=CANCEL_FD.load(Ordering::Relaxed);if fd>=0{unsafe{write(fd,[1u8].as_ptr() as _,1);}}
}
struct SignalWake(std::os::unix::net::UnixStream,std::os::unix::net::UnixStream);
impl Drop for SignalWake{fn drop(&mut self){CANCEL_FD.store(-1,Ordering::Relaxed);}}
extern "C" {fn signal(sig:i32,handler:usize)->usize;fn write(fd:i32,buf:*const std::ffi::c_void,count:usize)->isize;}

/// Kill helpers when their spawning thread exits; close the pre-exec owner race.
pub fn parent_guard(command:&mut Command) {
    use std::os::unix::process::CommandExt;
    unsafe {command.pre_exec(||{
        unsafe extern "C" {fn getppid()->i32;fn prctl(option:i32,a:std::os::raw::c_ulong,b:std::os::raw::c_ulong,c:std::os::raw::c_ulong,d:std::os::raw::c_ulong)->i32;}
        let parent=getppid();
        if parent<=1||prctl(1,9,0,0,0)!=0||getppid()!=parent{return Err(io::Error::other("helper owner exited"));}
        Ok(())
    });}
}

/// Own the child until reaped; all early exits kill only this unreaped child.
struct Reaper {pending:std::sync::Mutex<Vec<std::process::Child>>,wake:std::os::unix::net::UnixStream}
fn reaper()->io::Result<std::sync::Arc<Reaper>> {
    use std::sync::{Arc,Mutex,OnceLock};
    static INSTANCE:OnceLock<Mutex<Option<Arc<Reaper>>>>=OnceLock::new();
    let mut slot=INSTANCE.get_or_init(||Mutex::new(None)).lock().unwrap();
    if let Some(value)=slot.as_ref(){return Ok(value.clone());}
    let(read,write)=std::os::unix::net::UnixStream::pair()?;
    read.set_nonblocking(true)?;write.set_nonblocking(true)?;
    let value=Arc::new(Reaper{pending:Mutex::new(Vec::new()),wake:write});
    let worker=value.clone();
    // Create the supervisor before any child: resource exhaustion cannot lose ownership.
    std::thread::Builder::new().name("child-reaper".into()).spawn(move||{
        use std::os::fd::{AsRawFd,FromRawFd,OwnedFd};
        let mut children:Vec<(std::process::Child,Option<OwnedFd>)>=Vec::new();
        loop {
            let pending=std::mem::take(&mut *worker.pending.lock().unwrap());
            for child in pending{
                let fd=pidfd_open(child.id() as i32).ok().map(|fd|unsafe{OwnedFd::from_raw_fd(fd)});
                children.push((child,fd));
            }
            children.retain_mut(|(child,_)|match child.try_wait(){Ok(Some(_))=>false,Err(e) if e.raw_os_error()==Some(10)=>false,_=>true});
            let mut fds=vec![PollFd{fd:read.as_raw_fd(),events:POLLIN,revents:0}];
            fds.extend(children.iter().filter_map(|(_,fd)|fd.as_ref().map(|fd|PollFd{fd:fd.as_raw_fd(),events:POLLIN,revents:0})));
            // Compatibility fallback is active only while a child lacks pidfd support.
            let timeout=if children.iter().any(|(_,fd)|fd.is_none()){10}else{-1};
            if unsafe{poll(fds.as_mut_ptr(),fds.len() as _,timeout)}<0&&io::Error::last_os_error().kind()!=io::ErrorKind::Interrupted{
                std::thread::sleep(Duration::from_millis(10));
            }
            let mut bytes=[0u8;256];while (&read).read(&mut bytes).is_ok_and(|n|n>0){}
        }
    })?;
    *slot=Some(value.clone());Ok(value)
}
pub struct OwnedChild {child:Option<std::process::Child>,reaper:std::sync::Arc<Reaper>}
impl OwnedChild {pub fn spawn(command:&mut Command)->io::Result<Self>{let reaper=reaper()?;Ok(Self{child:Some(command.spawn()?),reaper})}}
impl std::ops::Deref for OwnedChild {type Target=std::process::Child;fn deref(&self)->&Self::Target{self.child.as_ref().unwrap()}}
impl std::ops::DerefMut for OwnedChild {fn deref_mut(&mut self)->&mut Self::Target{self.child.as_mut().unwrap()}}
impl Drop for OwnedChild {
    fn drop(&mut self){if let Some(mut child)=self.child.take(){
        if matches!(child.try_wait(),Ok(Some(_))){return;}
        let _=child.kill();
        self.reaper.pending.lock().unwrap().push(child);
        let _=(&self.reaper.wake).write_all(&[1]);
    }}
}

/// Cancellation is both state and a pollable event, so idle helpers never tick.
pub struct CancelEvent {flag:std::sync::atomic::AtomicBool,read:std::os::unix::net::UnixStream,write:std::os::unix::net::UnixStream}
impl CancelEvent {
    pub fn new()->io::Result<Self>{let(read,write)=std::os::unix::net::UnixStream::pair()?;write.set_nonblocking(true)?;Ok(Self{flag:std::sync::atomic::AtomicBool::new(false),read,write})}
    pub fn store(&self,value:bool,order:Ordering){if value&&!self.flag.swap(true,order){let _=(&self.write).write_all(&[1]);}}
    pub fn fd(&self)->std::os::fd::RawFd {use std::os::fd::AsRawFd;self.read.as_raw_fd()}
}
impl std::ops::Deref for CancelEvent {type Target=std::sync::atomic::AtomicBool;fn deref(&self)->&Self::Target{&self.flag}}

pub fn wait_checked(child:&mut OwnedChild,timeout:Duration,check:impl FnMut()->io::Result<()>)->io::Result<std::process::ExitStatus>{wait_events(child,timeout,&[],check)}
/// Wait on child completion, cancellation/output events, or the absolute timeout.
/// Only old kernels without pidfd require bounded waitpid polling.
pub fn wait_events(child:&mut OwnedChild,timeout:Duration,events:&[std::os::fd::RawFd],mut check:impl FnMut()->io::Result<()>)->io::Result<std::process::ExitStatus>{
    use std::os::fd::{FromRawFd,AsRawFd,OwnedFd};
    let descriptor=if std::env::var("SPEEDBACKUP_NATIVE_WAIT_BACKEND").as_deref()==Ok("poll"){None}else{pidfd_open(child.id() as i32).ok().map(|f|unsafe{OwnedFd::from_raw_fd(f)})};
    let deadline=Instant::now()+timeout;
    loop {
        check()?;
        match child.try_wait(){Ok(Some(status))=>return Ok(status),Err(e) if e.kind()==io::ErrorKind::Interrupted=>continue,Err(e)=>return Err(e),_=>{}}
        let remaining=deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero(){return Err(io::Error::new(io::ErrorKind::TimedOut,"child timeout"));}
        let ms=remaining.as_millis().min(if descriptor.is_some(){i32::MAX as u128}else{10}).max(1) as i32;
        let mut fds=events.iter().map(|fd|PollFd{fd:*fd,events:POLLIN,revents:0}).collect::<Vec<_>>();
        if let Some(fd)=&descriptor{fds.push(PollFd{fd:fd.as_raw_fd(),events:POLLIN,revents:0});}
        let result=unsafe{poll(fds.as_mut_ptr(),fds.len() as _,ms)};
        if result<0 {let error=io::Error::last_os_error();if error.kind()!=io::ErrorKind::Interrupted{return Err(error);}}
        if fds.iter().any(|p|p.revents&0x20!=0){return Err(io::Error::other("invalid wait descriptor"));}
    }
}

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
    use std::os::fd::AsRawFd;
    let (read,write)=match std::os::unix::net::UnixStream::pair(){Ok(v)=>v,Err(_)=>return 125};
    if write.set_nonblocking(true).is_err(){return 125;}
    let wake=SignalWake(read,write);
    CANCEL.store(0,Ordering::Relaxed);CANCEL_FD.store(wake.1.as_raw_fd(),Ordering::Relaxed);
    for sig in [1,2,15]{unsafe{signal(sig,cancelled as *const () as usize);}}
    let mut child=match OwnedChild::spawn(Command::new(exe).arg("speedscan").args(&args[3..])
        .stdin(Stdio::null()).stdout(output).stderr(Stdio::inherit())){Ok(c)=>c,Err(_)=>return 1};
    let pid=child.id() as i32;
    let backend=if std::env::var("SPEEDBACKUP_NATIVE_WAIT_BACKEND").as_deref()==Ok("poll"){"waitpid"}else{"pidfd-or-waitpid"};
    let mut diagnostic=trace_open();
    trace(&mut diagnostic,format!("NATIVE_BOUNDED_BEGIN tag={} pid={} timeoutMs={} backend={}",args[1],pid,ms,backend));
    let result=wait_events(&mut child,Duration::from_millis(ms),&[wake.0.as_raw_fd()],||if CANCEL.load(Ordering::Relaxed)!=0{Err(io::Error::from(io::ErrorKind::Interrupted))}else{Ok(())});
    let rc=match result {
        Ok(status)=>status.code().unwrap_or(128+status.signal().unwrap_or(0)),
        Err(error)=>{
            // Preserve TERM grace, then KILL grace, and retain ownership throughout.
            unsafe{kill(pid,SIGTERM);}
            if wait_checked(&mut child,Duration::from_millis(700),||Ok(())).is_err(){
                unsafe{kill(pid,SIGKILL);}
                if wait_checked(&mut child,Duration::from_millis(700),||Ok(())).is_err(){eprintln!("NATIVE_BOUNDED_UNREAPED pid={pid}");}
            }
            let cancel=CANCEL.load(Ordering::Relaxed);
            if cancel!=0{128+cancel}else if error.kind()==io::ErrorKind::TimedOut{124}else{125}
        }
    };
    let done=format!("NATIVE_BOUNDED_DONE tag={} pid={} rc={} elapsedMs={} backend={}",args[1],pid,rc,start.elapsed().as_millis(),backend);
    if rc!=0 {eprintln!("{}",done);}
    trace(&mut diagnostic,done);
    rc
}

fn regular(path:&Path)->io::Result<bool>{
    match fs::symlink_metadata(path){Ok(m) if m.file_type().is_file()=>Ok(true),Err(e) if e.kind()==io::ErrorKind::NotFound=>Ok(false),_=>Err(io::Error::new(io::ErrorKind::InvalidInput,"regular file required"))}
}
fn read_regular(path:&Path)->io::Result<File>{
    let file=fs::OpenOptions::new().read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK | speedbackup_native_rs::O_CLOEXEC)
        .open(path)?;
    if !file.metadata()?.is_file(){return Err(io::Error::new(io::ErrorKind::InvalidInput,"regular file required"));}
    Ok(file)
}
fn remove(path:&Path)->io::Result<()>{if regular(path)?{fs::remove_file(path)?;}Ok(())}
fn preserve(src:&Path,dir:&Path,name:&str)->io::Result<String>{
    if !regular(src)? || fs::metadata(src)?.len()==0{return Ok("none".into());}
    let dst=dir.join(name);
    if dst.exists(){return Err(io::Error::new(io::ErrorKind::AlreadyExists,"detail exists"));}
    // create_new prevents following a concurrently introduced symlink.
    let mut out=fs::OpenOptions::new().write(true).create_new(true).open(&dst)?;
    io::copy(&mut read_regular(src)?,&mut out)?;Ok(name.into())
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
    if regular(data)? {for line in BufReader::new(read_regular(data)?).split(b'\n'){if line?.starts_with(args[7].as_bytes()){rows+=1;}}}
    let mut summary=Vec::new();if regular(sum)?{read_regular(sum)?.take(700).read_to_end(&mut summary)?;}
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
    if args.len()!=1 || args[0]!="/data/.speedbackup/tmp" {return 2;}
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

#[cfg(test)] mod lifecycle_tests {
    use super::*;
    #[test] fn completion_and_timeout(){
        let mut child=OwnedChild::spawn(Command::new("/system/bin/sh").args(["-c","exit 7"])).unwrap();
        assert_eq!(wait_checked(&mut child,Duration::from_secs(2),||Ok(())).unwrap().code(),Some(7));
        let mut child=OwnedChild::spawn(Command::new("/system/bin/sh").args(["-c","exec sleep 30"])).unwrap();
        let start=Instant::now();assert_eq!(wait_checked(&mut child,Duration::from_millis(50),||Ok(())).unwrap_err().kind(),io::ErrorKind::TimedOut);drop(child);assert!(start.elapsed()<Duration::from_secs(2));
    }
    #[test] fn cancellation_wakes_wait(){
        let cancel=std::sync::Arc::new(CancelEvent::new().unwrap());let flag=cancel.clone();
        let mut child=OwnedChild::spawn(Command::new("/system/bin/sh").args(["-c","exec sleep 30"])).unwrap();
        let writer=std::thread::spawn(move||{std::thread::sleep(Duration::from_millis(50));flag.store(true,Ordering::Release);});
        let start=Instant::now();let result=wait_events(&mut child,Duration::from_secs(30),&[cancel.fd()],||if cancel.load(Ordering::Acquire){Err(io::Error::from(io::ErrorKind::Interrupted))}else{Ok(())});
        assert_eq!(result.unwrap_err().kind(),io::ErrorKind::Interrupted);assert!(start.elapsed()<Duration::from_secs(2));writer.join().unwrap();
    }
}
