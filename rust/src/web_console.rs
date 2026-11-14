//! Root-owned job supervisor. The Android Activity is a disposable view, never
//! the owner of the worker or its output pipe. No HTTP endpoint executes commands.
use super::*;
use std::os::unix::net::{UnixListener,UnixStream};
use std::os::fd::{FromRawFd,IntoRawFd};
use std::os::unix::process::{CommandExt,ExitStatusExt};
use std::sync::{Arc,Mutex,Condvar,mpsc};
use std::collections::VecDeque;
use std::os::unix::fs::FileExt;
const BASE:&str="/data/.speedbackup/console";
const CAP:usize=8*1024*1024;
unsafe extern "C" {fn setsid()->i32;fn flock(fd:i32,op:i32)->i32;fn getuid()->u32;fn mkfifo(p:*const std::ffi::c_char,m:u32)->i32;fn getsockopt(fd:i32,l:i32,o:i32,v:*mut std::ffi::c_void,n:*mut u32)->i32;}
// Reuse the already-running root origin controller instead of spawning a JVM
// just to authorize a notification tap. The same foreground/user/display gate runs there.
fn notification_origin_gate()->io::Result<bool>{
    #[cfg(target_os="android")]
    use std::os::android::net::SocketAddrExt;
    #[cfg(target_os="linux")]
    use std::os::linux::net::SocketAddrExt;
    let owner=std::process::id().to_string();
    let name=std::env::var("SPEEDBACKUP_WEB_ORIGIN_SOCKET").map_err(|_|err("origin absent"))?;
    if name!=format!("sb-web-origin-{owner}-1005-1"){return Err(err("origin scope"));}
    let stat=fs::read_to_string("/proc/self/stat")?;
    let start=speedbackup_native_rs::proc_stat::starttime(&stat).ok_or_else(||err("origin identity"))?;
    let address=std::os::unix::net::SocketAddr::from_abstract_name(name.as_bytes())?;
    let mut socket=UnixStream::connect_addr(&address)?;
    socket.set_read_timeout(Some(Duration::from_secs(3)))?;
    socket.set_write_timeout(Some(Duration::from_secs(2)))?;
    if root_peer(&socket).is_none(){return Err(err("origin peer"));}
    writeln!(socket,"{owner}:{start} HOST_OPEN")?;
    let mut answer=String::new();socket.take(161).read_to_string(&mut answer)?;
    Ok(answer=="OK\n")
}
fn private(p:&Path)->io::Result<()> {
    let m=fs::symlink_metadata(p)?;
    if !m.is_dir()||m.uid()!=0||m.mode()&0o777!=0o700||p.canonicalize()?!=p{return Err(err("console private directory"));}Ok(())
}
pub(super) fn managed()->bool{std::env::var("SPEEDBACKUP_CONSOLE_DIR").ok().is_some_and(|p|p.starts_with(&format!("{BASE}/"))&&private(Path::new(&p)).is_ok())}
fn language_lock(dir:&Path)->io::Result<File> {
    private(dir)?;
    let file=OpenOptions::new().read(true).write(true).create(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(dir.join("language-lock"))?;
    if unsafe{flock(file.as_raw_fd(),2)}!=0{return Err(io::Error::last_os_error());}
    Ok(file)
}
pub(super) fn queue_language(dir:&Path,value:&str)->io::Result<()> {
    let _lock=language_lock(dir)?;
    if !matches!(value,"zh-Hant"|"zh-Hans"){return Err(err("invalid language"));}
    super::super::publish_file::publish_bytes_guarded(value.as_bytes(),&dir.join("pending-language"),Some(0o600),false,&mut ||private(dir)).map(|_|())
}
pub(super) fn pending_language()->io::Result<Option<(PathBuf,String,File)>> {
    if !managed(){return Ok(None);}
    let dir=PathBuf::from(std::env::var("SPEEDBACKUP_CONSOLE_DIR").unwrap());
    let lock=language_lock(&dir)?;let path=dir.join("pending-language");
    let m=match fs::symlink_metadata(&path){Ok(m)=>m,Err(e) if e.kind()==io::ErrorKind::NotFound=>return Ok(None),Err(e)=>return Err(e)};
    if !m.is_file()||m.uid()!=0||m.len()>7{return Err(err("invalid language marker"));}
    let (value,_)=read(&path)?;
    if !matches!(value.as_str(),"zh-Hant"|"zh-Hans"){return Err(err("invalid pending language"));}
    Ok(Some((path,value,lock)))
}
fn rpc_at(dir:&Path,line:&str,limit:usize)->io::Result<String>{
    private(dir)?;let mut s=UnixStream::connect(dir.join("control"))?;
    s.set_read_timeout(Some(Duration::from_secs(10)))?;s.set_write_timeout(Some(Duration::from_secs(2)))?;
    s.write_all(line.as_bytes())?;s.write_all(b"\n")?;s.shutdown(std::net::Shutdown::Write)?;
    let mut result=String::new();s.take(limit as u64+1).read_to_string(&mut result)?;
    if result=="ERROR command"{return Err(io::Error::new(io::ErrorKind::Unsupported,"legacy console command"));}
    if result.len()>limit||result.starts_with("ERROR"){return Err(err("console control failed"));}Ok(result)
}
pub(super) struct Page {dir:PathBuf,id:String,returning:bool}
impl Page {
    pub(super) fn register(url:&str,review_output:bool)->io::Result<Option<Self>>{
        if !managed(){return Ok(None);}
        let dir=PathBuf::from(std::env::var("SPEEDBACKUP_CONSOLE_DIR").unwrap());let id=random_hex()?;
        rpc_at(&dir,&format!("PAGE\t{id}\t{url}\t{}",if review_output {"review"}else{"direct"}),64)?;
        let mut f=OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(dir.join("page"))?;writeln!(f,"{id}\n{url}")?;
        Ok(Some(Self{dir,id,returning:false}))
    }
    pub(super) fn return_to_menu(&mut self){self.returning=true;}
}
impl Drop for Page{fn drop(&mut self){let _=rpc_at(&self.dir,&format!("DONE\t{}{}",self.id,if self.returning{"\treturn"}else{""}),64);}}
pub(super) fn icons(user:&str,packages:&[&str])->io::Result<String>{
    rpc_at(Path::new(&std::env::var("SPEEDBACKUP_CONSOLE_DIR").map_err(|_|err("console unavailable"))?),&format!("ICONS\t{user}\t{}",packages.join("\t")),6*1024*1024)
}
struct Ui { page:Option<(String,String)>, revision:u64, reopen:u64, attached:bool, stop:bool, held:bool, seen_page:bool, last_output:u64, handoff:Option<Instant>, notification_reopen:Option<(u64,Instant)>, ready_reopen:Option<u64> }
impl Ui {
    // Preserve only the existing pixels, never a dead editor URL. Reopen,
    // cancellation and worker completion always remain able to show the console.
    fn returning(&self)->bool{self.handoff.is_some_and(|t|t.elapsed()<Duration::from_secs(2))}
}
struct Output { bytes:VecDeque<u8>,end:u64,rc:Option<i32>,progress:String,revision:u64,stop_status:String,history_failed:bool }
enum ServerEvent { Connection(TcpStream), Changed }
struct Shared {dir:PathBuf,guard:Mutex<(bool,bool)>,guard_wake:Condvar,history_view:Mutex<Option<u64>>,history:Option<File>,output:Mutex<Output>,wake:Condvar,ui_signal:mpsc::SyncSender<()>,server_signal:mpsc::SyncSender<ServerEvent>,ui:Mutex<Ui>,worker:Mutex<Option<String>>,stopping:std::sync::atomic::AtomicBool}
fn append(s:&Shared,bytes:&[u8]){let mut o=s.output.lock().unwrap();if !o.history_failed {if let Some(file)=&s.history{if file.write_all_at(bytes,o.end).is_err(){o.history_failed=true;}}}o.end+=bytes.len() as u64;o.bytes.extend(bytes);let n=o.bytes.len().saturating_sub(CAP);o.bytes.drain(..n);s.wake.notify_all();}
impl Shared {
    fn sync_guard(&self){
        let output=self.output.lock().unwrap();let ui=self.ui.lock().unwrap();
        let next=(output.rc.is_none(),ui.attached);
        let mut guard=self.guard.lock().unwrap();
        if *guard!=next{*guard=next;self.guard_wake.notify_all();}
    }
}
fn drain(mut input:impl Read,s:Arc<Shared>){
    let mut b=[0;16384];let mut pending=Vec::new();
    loop {let n=match input.read(&mut b){Ok(0)=>break,Ok(n)=>n,Err(e) if e.kind()==io::ErrorKind::Interrupted=>continue,Err(_)=>break};
        pending.extend_from_slice(&b[..n]);
        loop {match std::str::from_utf8(&pending){
            Ok(_)=>{append(&s,&pending);pending.clear();break;},
            Err(e)=>{let valid=e.valid_up_to();if valid>0{append(&s,&pending[..valid]);pending.drain(..valid);}
                if let Some(n)=e.error_len(){append(&s,"�".as_bytes());pending.drain(..n);}else{break;}
            }
        }}
    }
    if !pending.is_empty(){append(&s,String::from_utf8_lossy(&pending).as_bytes());}
}
// Separate progress and log streams: a progress frame must never split a UTF-8
// sequence from stdout. CR frames replace this bounded snapshot, not log rows.
fn progress_snapshot(s:&Shared,line:&str){
    // Strip CSI controls for validation, including split terminal clear frames.
    let mut esc=0;let mut visible=String::new();
    for c in line.chars(){match esc {
        1=>{esc=if c=='['{2}else{0};},
        2=>{if ('@'..='~').contains(&c){esc=0;}},
        _=>{if c=='\x1b'{esc=1;}else if !c.is_control(){visible.push(c);}}
    }}
    if !visible.trim().is_empty()||["\x1b[2K","\x1b[0K","\x1b[K"].iter().any(|clear|line.contains(clear)){let mut o=s.output.lock().unwrap();if o.progress!=visible{o.progress=visible;o.revision+=1;s.wake.notify_all();}}
}
fn drain_progress(mut input:File,s:Arc<Shared>){let mut b=[0;16384];let mut pending=Vec::new();let mut line=String::new();loop{
    let n=match input.read(&mut b){Ok(0)=>break,Ok(n)=>n,Err(e)if e.kind()==io::ErrorKind::Interrupted=>continue,Err(_)=>break};pending.extend_from_slice(&b[..n]);
    let valid=match std::str::from_utf8(&pending){Ok(_)=>pending.len(),Err(e)=>e.valid_up_to()};
    for c in String::from_utf8_lossy(&pending[..valid]).chars(){if c=='\r'||c=='\n'{progress_snapshot(&s,&line);if c=='\n'&&!line.is_empty(){append(&s,format!("{line}\n").as_bytes());}line.clear();}else{line.push(c);if line.len()>4096{line.clear();}}}
    pending.drain(..valid);if pending.len()>4{pending.clear();}
    progress_snapshot(&s,&line);
}}
fn b64(b:&[u8])->String{const T:&[u8]=b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";let mut o=String::with_capacity(b.len().div_ceil(3)*4);for c in b.chunks(3){let a=c[0] as usize;let d=*c.get(1).unwrap_or(&0) as usize;let e=*c.get(2).unwrap_or(&0) as usize;o.push(T[a>>2]as char);o.push(T[((a&3)<<4)|(d>>4)]as char);o.push(if c.len()>1{T[((d&15)<<2)|(e>>6)]as char}else{'='});o.push(if c.len()>2{T[e&63]as char}else{'='});}o}
// Byte cursors address only the current session archive. At most 64 KiB / 100
// newline-delimited records per call, with UTF-8 boundaries and no shared seek.
fn history_page(s:&Shared,request:&str)->io::Result<String>{
    let (end,failed)={let o=s.output.lock().unwrap();(o.end,o.history_failed)};
    if failed{return Err(err("history storage unavailable"));}
    let file=s.history.as_ref().ok_or_else(||err("history unavailable"))?;
    let (back,cursor)=if request=="tail"{(true,end)}else if request=="head"{(false,0)}else{
        let (mode,value)=request.split_once('\t').ok_or_else(||err("history cursor"))?;
        if value.is_empty()||!value.bytes().all(|c|c.is_ascii_digit()){return Err(err("history cursor"));}
        let at=value.parse::<u64>().map_err(|_|err("history cursor"))?;
        if at>end{return Err(err("history cursor"));}
        (match mode{"before"=>true,"after"=>false,_=>return Err(err("history direction"))},at)
    };
    let mut from=if back{cursor.saturating_sub(65536)}else{cursor};
    let stop=if back{cursor}else{cursor.saturating_add(65536).min(end)};
    let mut bytes=vec![0u8;(stop-from)as usize];file.read_exact_at(&mut bytes,from)?;
    if back {
        let mut lines=0;let mut cut=0;
        for i in (0..bytes.len()).rev(){if bytes[i]==b'\n'{lines+=1;if lines>100{cut=i+1;break;}}}
        if cut==0&&from>0 {if let Some(i)=bytes.iter().position(|b|*b==b'\n'){if i+1<bytes.len(){cut=i+1;}}}
        while cut<bytes.len()&&(bytes[cut]&0xc0)==0x80{cut+=1;}
        from+=cut as u64;bytes.drain(..cut);
    }else{
        let mut lines=0;let mut keep=bytes.len();
        for (i,b) in bytes.iter().enumerate(){if *b==b'\n'{lines+=1;if lines==100{keep=i+1;break;}}}
        bytes.truncate(keep);
        if let Err(e)=std::str::from_utf8(&bytes){if stop<end&&e.error_len().is_none(){bytes.truncate(e.valid_up_to());}}
    }
    Ok(format!("{{\"from\":{from},\"next\":{},\"total\":{end},\"data\":{}}}",from+bytes.len()as u64,json(&b64(&bytes))))
}
fn url_valid(url:&str)->bool{let Some((host,token))=url.strip_prefix("http://127.0.0.1:").and_then(|s|s.split_once("/#"))else{return false};host.parse::<u16>().is_ok_and(|p|p>0)&&token.len()==64&&token.bytes().all(|b|b.is_ascii_hexdigit())}
fn root_peer(s:&UnixStream)->Option<u32>{let mut cred=[0u32;3];let mut len=12u32;if unsafe{getsockopt(s.as_raw_fd(),1,17,cred.as_mut_ptr().cast(),&mut len)==0}&&len==12&&cred[1]==0{Some(cred[0])}else{None}}
fn control(listener:UnixListener,state:Arc<Shared>,icons:mpsc::SyncSender<(String,Vec<String>,mpsc::SyncSender<String>)>){
    let active=Arc::new(std::sync::atomic::AtomicUsize::new(0));
    for c in listener.incoming(){let Ok(mut c)=c else{break};let Some(peer)=root_peer(&c)else{continue;};
        if active.load(std::sync::atomic::Ordering::Relaxed)>=8{continue;}
        active.fetch_add(1,std::sync::atomic::Ordering::Relaxed);
        let active=active.clone();let state=state.clone();let icons=icons.clone();
        std::thread::spawn(move||{control_request(&mut c,state,icons,peer);active.fetch_sub(1,std::sync::atomic::Ordering::Relaxed);});
    }
}
fn control_request(c:&mut UnixStream,state:Arc<Shared>,icons:mpsc::SyncSender<(String,Vec<String>,mpsc::SyncSender<String>)>,peer:u32){
        let _=c.set_read_timeout(Some(Duration::from_secs(2)));let _=c.set_write_timeout(Some(Duration::from_secs(2)));
        let mut text=String::new();if (&mut *c).take(32769).read_to_string(&mut text).is_err()||text.len()>32768{return;}
        let f:Vec<_>=text.trim_end_matches('\n').split('\t').collect();let mut answer="OK".to_string();
        match f.as_slice(){
            ["PAGE",id,url,policy] if matches!(*policy,"review"|"direct")&& id.len()==64&&id.bytes().all(|b|b.is_ascii_hexdigit())&&url_valid(url)=>{let mut o=state.output.lock().unwrap();let end=o.end;let mut u=state.ui.lock().unwrap();u.held=*policy=="review"&&!u.returning()&&u.seen_page&&end>u.last_output;u.handoff=None;u.seen_page=true;u.page=Some((id.to_string(),url.to_string()));u.revision+=1;o.revision+=1;state.wake.notify_all();}
            ["DONE",id] | ["DONE",id,"return"]=>{let mut o=state.output.lock().unwrap();let end=o.end;let mut u=state.ui.lock().unwrap();if u.page.as_ref().is_some_and(|p|p.0==*id){u.page=None;u.handoff=(f.len()==3).then(Instant::now);u.held=false;u.last_output=end;u.revision+=1;o.revision+=1;state.wake.notify_all();}}
            ["OPEN"]=>{let finished=state.output.lock().unwrap().rc.is_some();
                if !finished {
                    // Peer PID comes from SO_PEERCRED, not RPC text. The caller
                    // remains alive waiting for this synchronous reply.
                    if let (Ok(exe),Ok(stat))=(std::env::current_exe(),fs::read_to_string(format!("/proc/{peer}/stat"))){
                        if let (Some(parent),Some(start))=(exe.parent(),speedbackup_native_rs::proc_stat::starttime(&stat)){
                            match bounded_output(Command::new("/system/bin/app_process").env("CLASSPATH",parent.join("classes.dex")).args(["/system/bin","com.xayah.dex.AppListReturn","--rebind-origin",&peer.to_string(),&format!("{peer}:{start}")]),5) {
                                Ok((status,_))=>{eprintln!("CONSOLE_REBIND success={} exit={:?} signal={:?}",status.success(),status.code(),status.signal());if status.signal().is_some(){super::super::crash_diagnostics::capture_console();}},
                                Err(e)=>eprintln!("CONSOLE_REBIND helper_unavailable reason={e}"),
                            }
                        }
                    }
                }
                let mut u=state.ui.lock().unwrap();if finished{u.stop=true;answer="FINISHED".into();}else{u.attached=true;u.ready_reopen=None;u.revision+=1;u.reopen+=1;}
            }
            ["VIEW_STATUS"]=>{let finished=state.output.lock().unwrap().rc.is_some();let u=state.ui.lock().unwrap();answer=if finished{"FINISHED"}else if !u.attached{"FAILED"}else if u.ready_reopen==Some(u.reopen){"READY"}else{"PENDING"}.into();}
            ["PING"]=>{}
            ["ICONS",user,pkgs @ ..] if !pkgs.is_empty()&&pkgs.len()<=100&&user.len()<=5&&user.bytes().all(|b|b.is_ascii_digit())=>{
                let (tx,rx)=mpsc::sync_channel(1);
                if icons.try_send((user.to_string(),pkgs.iter().map(|p|p.to_string()).collect(),tx)).is_ok(){let _=state.ui_signal.try_send(());let _=state.server_signal.try_send(ServerEvent::Changed);answer=rx.recv_timeout(Duration::from_secs(8)).unwrap_or_else(|_|"ERROR icons timeout".into());}else{answer="ERROR icons busy".into();}
            }
            _=>answer="ERROR command".into(),
        }
        let _=state.ui_signal.try_send(());let _=state.server_signal.try_send(ServerEvent::Changed);
        state.sync_guard();
        let _=c.write_all(answer.as_bytes());
}
// One controller and Binder session per visible work session, not per page.
fn ui_worker(state:Arc<Shared>,url:String,icons:mpsc::Receiver<(String,Vec<String>,mpsc::SyncSender<String>)>,events:mpsc::Receiver<()>,mut origin_ready:bool){
    let mut task:Option<ReturnTask>=None;let mut seen=u64::MAX;let mut opened=u64::MAX;
    let mut displayed=String::new();let mut console_gap:Option<(u64,Instant)>=None;
    let mut pending:Option<(Instant,mpsc::SyncSender<String>)>=None;
    loop{
        let closed=task.as_mut().is_some_and(ReturnTask::externally_closed);
        if closed {eprintln!("CONSOLE_VIEW_DISCONNECTED reason=controller_closed");task=None;displayed.clear();let mut u=state.ui.lock().unwrap();if u.reopen==opened{u.attached=false;}}
        let (revision,reopen,wanted,attached,stop,returning)={let u=state.ui.lock().unwrap();(u.revision,u.reopen,u.page.as_ref().filter(|_|!u.held&&!state.stopping.load(std::sync::atomic::Ordering::SeqCst)).map(|p|p.1.clone()).unwrap_or_else(||url.clone()),u.attached,u.stop,u.returning())};
        if stop {if let Some(t)=task.take(){let _=t.finish(false,false);}break;}
        // DONE often immediately precedes PAGE. Avoid loading a disposable
        // console document during that tiny gap. Explicit editor returns keep
        // the old pixels until PAGE arrives, with a bounded failure fallback.
        // Actual work uses normal DONE and still appears after at most 30 ms.
        let gap=attached&&revision!=seen&&wanted==url&&displayed!=url&&task.is_some()&&opened==reopen;
        let finishing=state.output.lock().unwrap().rc.is_some()||state.stopping.load(std::sync::atomic::Ordering::SeqCst);
        let defer=if gap&&!finishing{let entry=console_gap.get_or_insert((revision,Instant::now()));if entry.0!=revision{*entry=(revision,Instant::now());}returning||entry.1.elapsed()<Duration::from_millis(30)}else{console_gap=None;false};
        if attached&&revision!=seen&&!defer {
            seen=revision;
            if task.is_some()&&wanted==displayed&&opened==reopen {
                eprintln!("CONSOLE_NAV reuse-same-page revision={revision}");
            }else{
                let start=Instant::now();
                let navigation=if opened==reopen{task.as_mut().map(|t|t.navigate(&wanted)).unwrap_or(Navigation::Retry)}else{Navigation::Retry};
                if {let u=state.ui.lock().unwrap();u.revision!=revision||u.reopen!=reopen} {
                    eprintln!("CONSOLE_NAV superseded revision={revision}");continue;
                }
                if navigation==Navigation::Closed{
                    eprintln!("CONSOLE_VIEW_DISCONNECTED reason=navigation_closed revision={revision}");
                    task=None;displayed.clear();let mut u=state.ui.lock().unwrap();if u.reopen==reopen{u.attached=false;}
                    if let Some((_,reply))=pending.take(){let _=reply.try_send("ERROR view disconnected".into());}
                    continue;
                }
                let fast=navigation==Navigation::Ready;
                if !fast {
                    if let Some((_,reply))=pending.take(){let _=reply.try_send("ERROR icon session changed".into());}
                    let notification=state.ui.lock().unwrap().notification_reopen.take().is_some_and(|(r,_)|r==reopen);
                    if notification&&!notification_origin_gate().unwrap_or(false){let mut u=state.ui.lock().unwrap();if u.reopen==reopen{u.attached=false;}continue;}
                    if !origin_ready{origin_ready=super::prepare_origin(&["0".into()])==0;}
                    if {let u=state.ui.lock().unwrap();u.revision!=revision||u.reopen!=reopen}{continue;}
                    if let Some(next)=if origin_ready{ReturnTask::capture_managed(&wanted,state.ui_signal.clone())}else{None}{task=Some(next);}else{super::super::crash_diagnostics::capture_console();let mut u=state.ui.lock().unwrap();if u.reopen==reopen{u.attached=false;}}
                }
                {let mut u=state.ui.lock().unwrap();if u.attached&&u.reopen==reopen{displayed=wanted;opened=reopen;u.ready_reopen=Some(reopen);}}
                eprintln!("CONSOLE_NAV mode={} elapsed_ms={} revision={revision} attached={}",if fast{"binder"}else{"launch"},start.elapsed().as_millis(),state.ui.lock().unwrap().attached);
            }
        }
        // Icon work never blocks navigation. Keep one in-flight batch until its
        // response is drained, even across fast page changes; never misroute it.
        if let Some((start,_))=pending.as_ref(){
            let result=task.as_mut().ok_or_else(||err("view disconnected")).and_then(ReturnTask::poll_icons);
            let value=match result{Ok(Some(v))=>Some(v),Err(_)=>Some("ERROR icons unavailable".into()),Ok(None)if start.elapsed()>=Duration::from_secs(8)=>{if let Some(t)=task.as_mut(){t.icons_disabled=true;}Some("ERROR icons timeout".into())},_=>None};
            if let Some(value)=value{if let Some((_,reply))=pending.take(){let _=reply.try_send(value);}}
        }
        while pending.is_none(){if let Ok((user,packages,reply))=icons.try_recv(){
            let refs:Vec<_>=packages.iter().map(String::as_str).collect();
            if attached&&task.as_mut().is_some_and(|t|t.begin_icons(&user,&refs).is_ok()){pending=Some((Instant::now(),reply));}
            else{let _=reply.try_send("ERROR icons unavailable".into());}
        }else{break;}}
        state.sync_guard();
        // Coalesced notifications cover control, controller stdout/EOF and job exit.
        // Only handoff and icon deadlines use timed waits; idle UI never polls.
        let timeout=if defer {
            Some(if returning {state.ui.lock().unwrap().handoff.map(|t|Duration::from_secs(2).saturating_sub(t.elapsed())).unwrap_or_default()}
                else {console_gap.map(|(_,t)|Duration::from_millis(30).saturating_sub(t.elapsed())).unwrap_or_default()})
        }
            else {pending.as_ref().map(|(start,_)|Duration::from_secs(8).saturating_sub(start.elapsed()))};
        if let Some(timeout)=timeout {let _=events.recv_timeout(timeout);} else if events.recv().is_err(){break;}
    }
}
fn http(mut stream:TcpStream,state:Arc<Shared>,host:String,token:String){
    let Ok(req)=request(&mut stream)else{return;};let origin=format!("http://{host}");
    if req.headers.get("host")!=Some(&host)||req.headers.get("origin").is_some_and(|o|o!=&origin)||req.headers.get("sec-fetch-site").is_some_and(|s|!matches!(s.as_str(),"same-origin"|"none")){let _=respond(&mut stream,"403 Forbidden","text/plain","來源不符");return;}
    if req.headers.get("x-speedbackup-token")!=Some(&token){let _=respond(&mut stream,"403 Forbidden","text/plain","憑證無效");return;}
    if req.method=="GET" && req.path=="/api/session" && req.body.is_empty() {
        let _=respond(&mut stream,"200 OK","application/json",r#"{"protocol":1,"kind":"console","native":true}"#);return;
    }
    if (req.method=="GET"&&req.path=="/api/guard")||(req.method=="POST"&&req.path=="/api/guard-wait"&&matches!(req.body.as_str(),"0"|"1")) {
        let mut guard=state.guard.lock().unwrap();
        if req.method=="POST"{guard=state.guard_wake.wait_timeout_while(guard,Duration::from_secs(12),|g|g.0&&g.1==(req.body=="1")).unwrap().0;}
        let (active,attached)=*guard;drop(guard);
        let _=respond_output(&mut stream,&format!("{{\"active\":{active},\"attached\":{attached},\"eventDriven\":true}}"));return;
    }
    if req.method=="POST"&&req.path=="/api/reopen" {
        // Only a deliberate notification tap can place our private ResumeActivity
        // in front. Retain original user/display and owner identity checks.
        let allowed=notification_origin_gate().unwrap_or(false);
        if !allowed {let _=respond(&mut stream,"403 Forbidden","text/plain","請由通知接回");return;}
        let output=state.output.lock().unwrap();
        if output.rc.is_some(){let _=respond(&mut stream,"409 Conflict","text/plain","工作已結束");return;}
        let mut ui=state.ui.lock().unwrap();
        if !ui.notification_reopen.is_some_and(|(_,t)|t.elapsed()<Duration::from_secs(1)) {
            ui.attached=true;ui.ready_reopen=None;ui.revision+=1;ui.reopen+=1;ui.notification_reopen=Some((ui.reopen,Instant::now()));
        }
        drop(ui);drop(output);state.sync_guard();
        let _=state.ui_signal.try_send(());let _=state.server_signal.try_send(ServerEvent::Changed);
        let _=respond(&mut stream,"200 OK","text/plain","OK");return;
    }
    if appearance_request(&mut stream,&req)||language_request(&mut stream,&req,None,Some(&state.dir)).is_some(){return;}
    if req.method=="GET"&&req.path=="/api/theme"{let _=respond(&mut stream,"200 OK","application/json",&read_theme().unwrap_or_else(|_|"{}".into()));return;}
    if req.method=="POST"&&req.path=="/api/output" {
        let mut fields=req.body.split('\t');
        let Some(cursor)=fields.next().and_then(|s|s.parse::<u64>().ok())else{return;};
        let revision=match fields.next(){None=>None,Some(s)=>match s.parse::<u64>(){Ok(v)=>Some(v),Err(_)=>return}};
        if fields.next().is_some(){return;}
        let mut o=state.output.lock().unwrap();
        // Both output and UI/progress state participate in the predicate.
        // Writers hold this same mutex while changing state, preventing a
        // PAGE notification just before wait from being lost for 12 seconds.
        o=state.wake.wait_timeout_while(o,Duration::from_secs(12),|o|cursor==o.end&&o.rc.is_none()&&revision==Some(o.revision)).unwrap().0;
        let start=o.end-o.bytes.len()as u64;let from=cursor.max(start).min(o.end);let bytes:Vec<_>=o.bytes.iter().skip((from-start)as usize).take(65536).copied().collect();
        let pending={let u=state.ui.lock().unwrap();if u.held&&o.stop_status!="stopping"{u.page.as_ref().map(|p|p.0.clone()).unwrap_or_default()}else{String::new()}};
        let revision=o.revision;let body=format!("{{\"stopStatus\":{},\"revision\":{revision},\"pending\":{},\"from\":{from},\"next\":{},\"data\":{},\"progress\":{},\"rc\":{}}}",json(&o.stop_status),json(&pending),from+bytes.len()as u64,json(&b64(&bytes)),json(&o.progress),o.rc.map(|r|r.to_string()).unwrap_or_else(||"null".into()));drop(o);let _=respond_output(&mut stream,&body);
    }else if req.method=="GET"&&req.path=="/api/history-view"{
        let value=state.history_view.lock().unwrap().map(|v|v.to_string()).unwrap_or_else(||"live".into());
        let _=respond(&mut stream,"200 OK","text/plain",&value);
    }else if req.method=="POST"&&req.path=="/api/history-view"{
        let value=if req.body=="live"{Some(None)}else{req.body.parse::<u64>().ok().filter(|v|*v<=state.output.lock().unwrap().end).map(Some)};
        if let Some(value)=value{*state.history_view.lock().unwrap()=value;let _=respond(&mut stream,"200 OK","text/plain","OK");}
        else{let _=respond(&mut stream,"400 Bad Request","text/plain","日誌位置無效");}
    }else if req.method=="POST"&&req.path=="/api/history"{
        match history_page(&state,&req.body){
            Ok(body)=>{let _=respond(&mut stream,"200 OK","application/json",&body);},
            Err(e)=>{let _=respond(&mut stream,"400 Bad Request","text/plain",&format!("無法讀取較早日誌：{e}"));}
        }
    }else if req.method=="POST"&&req.path=="/api/continue"{
        let mut o=state.output.lock().unwrap();let mut u=state.ui.lock().unwrap();
        if !state.stopping.load(std::sync::atomic::Ordering::SeqCst)&&u.held&&u.page.as_ref().is_some_and(|p|p.0==req.body){u.held=false;u.revision+=1;o.revision+=1;state.wake.notify_all();drop(u);drop(o);let _=respond(&mut stream,"200 OK","text/plain","OK");}
        else{let _=respond(&mut stream,"409 Conflict","text/plain","操作畫面已更新，請重試。");}
    }else if req.method=="POST"&&req.path=="/api/stop"&&req.body=="stop-current-job"{
        let expected=state.worker.lock().unwrap().clone();
        if state.output.lock().unwrap().rc.is_some()||expected.is_none()||state.stopping.swap(true,std::sync::atomic::Ordering::SeqCst){let _=respond(&mut stream,"409 Conflict","text/plain","工作已結束或正在停止。");return;}
        let expected=expected.unwrap();
        {let mut o=state.output.lock().unwrap();o.stop_status="stopping".into();o.revision+=1;let mut u=state.ui.lock().unwrap();u.revision+=1;state.wake.notify_all();}
        let st=state.clone();std::thread::spawn(move||{
            append(&st,"正在停止目前工作，等待正常收尾；逾時才會強制終止。\n".as_bytes());
            let rc=super::super::restore_safety::lock_cancel(&["/data/.backup_lock".into(),expected],Duration::from_secs(20));
            ui_event("console-stop-result",&format!("rc={rc}"));
            let (status,message)=match rc{0=>("graceful","工作已正常中斷並退出；收尾結果請查看日誌。\n"),10=>("forced","正常停止逾時，已強制終止；下次啟動會進行中斷清理。\n"),_=>("failed","停止未完成或無法核對工作身分，請查看日誌；可重試停止。\n")};
            append(&st,message.as_bytes());
            let mut o=st.output.lock().unwrap();o.stop_status=status.into();o.revision+=1;st.stopping.store(false,std::sync::atomic::Ordering::SeqCst);st.wake.notify_all();let _=st.ui_signal.try_send(());
        });
        let _=respond(&mut stream,"202 Accepted","text/plain","已要求停止，正在正常收尾；最長等待 20 秒後才強制終止。");
    }else if req.method=="POST"&&req.path=="/api/close"&&req.body.is_empty(){
        if state.output.lock().unwrap().rc.is_none(){let _=respond_inner(&mut stream,"409 Conflict","text/plain","工作仍在執行，關閉畫面不會中止作業。");}
        else {let _=respond(&mut stream,"200 OK","text/plain","已結束");state.ui.lock().unwrap().stop=true;}
    }else{let _=respond(&mut stream,"400 Bad Request","text/plain","無效請求");}
    state.sync_guard();
    let _=state.ui_signal.try_send(());let _=state.server_signal.try_send(ServerEvent::Changed);
}
// Called only after the worker finished, while still holding the service flock.
// Keep the lock inode and diagnostic log; never recursively remove the session.
fn cleanup_session_files(dir:&Path)->io::Result<()> {
    private(dir)?;
    let mut failure=None;
    for name in ["ready","control","session","page","progress","guard-active","pending-language"] {
        if let Err(e)=fs::remove_file(dir.join(name)){if e.kind()!=io::ErrorKind::NotFound{failure=Some(e);}}
    }
    match failure{Some(e)=>Err(e),None=>Ok(())}
}
fn service(dir:&Path,entry:&Path,args:&[String])->io::Result<i32>{
    super::super::restore_safety::app_data_namespace()?;
    private(dir)?;
    let lock=OpenOptions::new().read(true).write(true).create(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(dir.join("lock"))?;
    if unsafe{flock(lock.as_raw_fd(),2|4)}!=0{return Err(err("job already active"));}
    match fs::remove_file(dir.join("pending-language")){Ok(())=>{},Err(e)if e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e)}
    let diagnostic=dir.join("webui-errors.log");
    match fs::remove_file(&diagnostic){Ok(())=>{},Err(e)if e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e)}
    OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(&diagnostic)?;
    std::env::set_var("SPEEDBACKUP_UI_ERROR_LOG",&diagnostic);
    ui_event("console-service","start");
    let _=fs::remove_file(dir.join("ready"));
    let _=fs::remove_file(dir.join("control"));let listener=UnixListener::bind(dir.join("control"))?;
    let port=TcpListener::bind("127.0.0.1:0")?;let host=port.local_addr()?.to_string();let token=random_hex()?;
    let url=format!("http://{host}/#{token}");
    let mut session=OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(dir.join("session"))?;
    writeln!(session,"{url}")?;
    let owner=std::process::id().to_string();std::env::set_var("SPEEDBACKUP_WEB_OWNER_PID",&owner);std::env::set_var("SPEEDBACKUP_WEB_ORIGIN_SOCKET",format!("sb-web-origin-{owner}-1005-1"));
    // Capture while the launching process is still waiting, preserving its ancestry.
    // A headless start may continue without a view; later OPEN requires a verified invoker.
    std::env::set_var("SPEEDBACKUP_CONSOLE_DIR",dir);
    std::env::set_var("SPEEDBACKUP_CONSOLE_URL",&url);
    // Bind only menu start.sh entries, never a single-app/action wrapper.
    // The wrapper's declared mode distinguishes backup and restore even after a directory rename.
    std::env::remove_var("SPEEDBACKUP_SHORTCUT_ENTRY");std::env::remove_var("SPEEDBACKUP_SHORTCUT_MODE");
    std::env::set_var("SPEEDBACKUP_SHORTCUT_BACKEND",std::env::current_exe()?);
    if entry.file_name().and_then(|s|s.to_str())==Some("start.sh") {
        if let (Ok(path),Ok(source))=(fs::canonicalize(entry),fs::read_to_string(entry)) {
            let mode=source.lines().find_map(|line|match line.trim(){
                "export SPEEDBACKUP_ENTRY_MODE=\"0\""=>Some("0"),
                "export SPEEDBACKUP_ENTRY_MODE=\"2\""=>Some("2"),_=>None});
            if let Some(mode)=mode {std::env::set_var("SPEEDBACKUP_SHORTCUT_ENTRY",path);std::env::set_var("SPEEDBACKUP_SHORTCUT_MODE",mode);}
        }
    }
    fs::write(dir.join("guard-active"),b"active\n")?;
    let _crash_monitor=super::super::crash_diagnostics::monitor().map_err(|e|eprintln!("CRASH_MONITOR unavailable: {e}")).ok();
    let origin_ready=super::prepare_origin(&["1".into()])==0;
    // Session-owned full output, separate from the bounded live RAM tail. Replace
    // only this private session's archive, never truncate an existing hardlink.
    let archive=dir.join("output.log");
    match fs::remove_file(&archive){Ok(())=>{},Err(e)if e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e)}
    let history=OpenOptions::new().read(true).write(true).create_new(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(archive)?;
    let (ui_signal,ui_events)=mpsc::sync_channel(1);
    let (server_signal,server_events)=mpsc::sync_channel(16);
    let state=Arc::new(Shared{dir:dir.to_path_buf(),guard:Mutex::new((true,true)),guard_wake:Condvar::new(),history_view:Mutex::new(None),history:Some(history),output:Mutex::new(Output{bytes:VecDeque::new(),end:0,rc:None,progress:String::new(),revision:0,stop_status:String::new(),history_failed:false}),wake:Condvar::new(),ui_signal,server_signal,ui:Mutex::new(Ui{page:None,revision:0,reopen:0,attached:true,stop:false,held:false,seen_page:false,last_output:0,handoff:None,notification_reopen:None,ready_reopen:None}),worker:Mutex::new(None),stopping:std::sync::atomic::AtomicBool::new(false)});
    let (itx,irx)=mpsc::sync_channel(2);let st=state.clone();std::thread::spawn(move||control(listener,st,itx));
    let st=state.clone();let (ui_done_tx,ui_done)=mpsc::sync_channel(1);let ui_thread=std::thread::spawn(move||{ui_worker(st,url,irx,ui_events,origin_ready);let _=ui_done_tx.send(());});
    let progress=dir.join("progress");let _=fs::remove_file(&progress);let path=std::ffi::CString::new(progress.as_os_str().as_encoded_bytes()).map_err(|_|err("fifo path"))?;
    if unsafe{mkfifo(path.as_ptr().cast(),0o600)}!=0{return Err(io::Error::last_os_error());}
    let fifo=OpenOptions::new().read(true).write(true).open(&progress)?;let st=state.clone();std::thread::spawn(move||drain_progress(fifo,st));
    let (reader,writer)=UnixStream::pair()?;let out=unsafe{File::from_raw_fd(writer.into_raw_fd())};
    let mut cmd=Command::new("/system/bin/sh");cmd.arg(entry).args(args).env("SPEEDBACKUP_NATIVE_EXE",std::env::current_exe()?).env("SPEEDBACKUP_DEBUG_SESSION",&random_hex()?[..32]).env("SPEEDBACKUP_CONSOLE_DIR",dir).env("SPEEDBACKUP_WEB_PROGRESS_FIFO",&progress).env("SPEEDBACKUP_CONSOLE_OWNER",&owner).stdin(Stdio::null()).stdout(out.try_clone()?).stderr(out);
    unsafe{cmd.pre_exec(||{
        unsafe extern "C"{fn signal(sig:i32,handler:usize)->usize;}
        if signal(2,0)==usize::MAX{return Err(io::Error::last_os_error());}
        if setsid()<0{return Err(io::Error::last_os_error());}Ok(())
    });}
    let mut child=cmd.spawn()?;drop(cmd);let st=state.clone();let (read_done_tx,read_done)=mpsc::sync_channel(1);let read_thread=std::thread::spawn(move||{drain(reader,st);let _=read_done_tx.send(());});
    if let (Ok(stat),Ok(boot))=(fs::read_to_string(format!("/proc/{}/stat",child.id())),fs::read_to_string("/proc/sys/kernel/random/boot_id")){
        if let Some(start)=speedbackup_native_rs::proc_stat::starttime(&stat) {*state.worker.lock().unwrap()=Some(format!("{}:{start}:{}",child.id(),boot.trim()));}
    }
    let guard_marker=dir.join("guard-active");
    let st=state.clone();std::thread::spawn(move||{let rc=child.wait().map(|s|s.code().unwrap_or_else(||128+s.signal().unwrap_or(1))).unwrap_or(1);if read_done.recv_timeout(Duration::from_secs(2)).is_ok(){let _=read_thread.join();}let _=fs::remove_file(&guard_marker);let mut o=st.output.lock().unwrap();o.rc=Some(rc);st.wake.notify_all();drop(o);let mut u=st.ui.lock().unwrap();u.page=None;u.revision+=1;drop(u);st.sync_guard();let _=st.ui_signal.try_send(());let _=st.server_signal.try_send(ServerEvent::Changed);});
    if let Err(e)=fs::write(dir.join("ready"),format!("{}\n",std::process::id())){eprintln!("CONSOLE_READY_WRITE {e}; worker remains active");}
    let accepts=state.server_signal.clone();
    std::thread::spawn(move||loop{
        match port.accept(){
            Ok((stream,_))=>if accepts.send(ServerEvent::Connection(stream)).is_err(){break;},
            Err(error) if error.kind()==io::ErrorKind::Interrupted=>continue,
            Err(error)=>{eprintln!("CONSOLE_ACCEPT {error}; worker remains active");std::thread::sleep(Duration::from_secs(1));}
        }
    });
    let active=Arc::new(std::sync::atomic::AtomicUsize::new(0));let mut finished=None;
    loop {
        let timeout=if state.output.lock().unwrap().rc.is_some(){
            let start=finished.get_or_insert_with(Instant::now);
            let left=Duration::from_secs(1800).saturating_sub(start.elapsed());
            if left.is_zero()||state.ui.lock().unwrap().stop{break;}Some(left)
        }else{None};
        let event=if let Some(timeout)=timeout{server_events.recv_timeout(timeout).ok()}else{server_events.recv().ok()};
        if let Some(ServerEvent::Connection(stream))=event{
            use std::sync::atomic::Ordering;
            if active.load(Ordering::Relaxed)>=8{continue;}
            active.fetch_add(1,Ordering::Relaxed);let a=active.clone();let st=state.clone();let h=host.clone();let t=token.clone();
            std::thread::spawn(move||{http(stream,st,h,t);a.fetch_sub(1,Ordering::Relaxed);});
        }
    }
    state.ui.lock().unwrap().stop=true;let _=state.ui_signal.try_send(());
    if ui_done.recv_timeout(Duration::from_secs(2)).is_ok(){let _=ui_thread.join();}
    cleanup_session_files(dir)?;Ok(0)
}
// This endpoint exists in legacy supervisors too. It only closes a FINISHED
// worker; a live worker returns 409 without any mutation. Never use /api/stop.
fn close_finished_at(dir:&Path)->io::Result<bool>{
    private(dir)?;
    let mut url=String::new();open(&dir.join("session"))?.take(4097).read_to_string(&mut url)?;
    let url=url.trim();if !url_valid(url){return Err(err("console session URL"));}
    let (host,token)=url.strip_prefix("http://").unwrap().split_once("/#").unwrap();
    let address=host.parse::<std::net::SocketAddr>().map_err(|_|err("console address"))?;
    let mut socket=TcpStream::connect_timeout(&address,Duration::from_secs(2))?;
    socket.set_read_timeout(Some(Duration::from_secs(3)))?;socket.set_write_timeout(Some(Duration::from_secs(2)))?;
    write!(socket,"POST /api/close HTTP/1.1\r\nHost: {host}\r\nX-SpeedBackup-Token: {token}\r\nContent-Length: 0\r\n\r\n")?;
    // Consume the bounded reply before closing: reading only the status line
    // can reset the connection while the supervisor is still writing its body.
    read_close_reply(&mut socket)
}
fn read_close_reply(reader:&mut impl Read)->io::Result<bool>{
    let mut reply=Vec::new();
    while !reply.ends_with(b"\r\n\r\n"){
        if reply.len()>=8192{return Err(err("console reply too large"));}
        let mut byte=[0];reader.read_exact(&mut byte)?;reply.push(byte[0]);
    }
    let head=std::str::from_utf8(&reply).map_err(|_|err("console reply encoding"))?;
    let lengths:Vec<_>=head.split("\r\n").filter_map(|line|line.split_once(':')).filter(|(key,_)|key.eq_ignore_ascii_case("content-length")).collect();
    let size=if lengths.len()==1{lengths[0].1.trim().parse::<usize>().ok()}else{None}.ok_or_else(||err("console reply length"))?;
    if size>8192-reply.len(){return Err(err("console reply too large"));}
    let start=reply.len();reply.resize(start+size,0);reader.read_exact(&mut reply[start..])?;
    close_reply(&reply)
}
// Read-only long wait replies are abandoned when the native page closes.
// Keep the event, but never classify a mutating response this way.
fn respond_output(stream:&mut TcpStream,body:&str)->io::Result<()>{
    let result=respond_inner(stream,"200 OK","application/json",body);
    if let Err(e)=&result{
        if matches!(e.kind(),io::ErrorKind::BrokenPipe|io::ErrorKind::ConnectionReset|io::ErrorKind::ConnectionAborted){
            ui_event("output-peer-closed",&format!("kind={:?} errno={:?}",e.kind(),e.raw_os_error()));
        }else{ui_transport_error("output-write",&format!("kind={:?} errno={:?}",e.kind(),e.raw_os_error()));}
    }
    result
}
fn close_reply(reply:&[u8])->io::Result<bool>{
    if reply.len()>8192{return Err(err("console reply too large"));}
    let text=std::str::from_utf8(reply).map_err(|_|err("console reply encoding"))?;
    let (head,body)=text.split_once("\r\n\r\n").ok_or_else(||err("console reply incomplete"))?;
    let mut lines=head.split("\r\n");let status=lines.next().unwrap_or("");
    let lengths:Vec<_>=lines.filter_map(|l|l.split_once(':')).filter(|(k,_)|k.eq_ignore_ascii_case("content-length")).collect();
    if lengths.len()!=1||lengths[0].1.trim().parse::<usize>().ok()!=Some(body.len()){return Err(err("console reply length"));}
    match status{"HTTP/1.1 200 OK"=>Ok(true),"HTTP/1.1 409 Conflict"=>Ok(false),_=>Err(err("console state unavailable"))}
}
fn wait_closed(dir:&Path)->io::Result<()>{
    let deadline=Instant::now()+Duration::from_secs(6);
    while dir.join("control").exists()&&Instant::now()<deadline{std::thread::sleep(Duration::from_millis(50));}
    if dir.join("control").exists(){return Err(err("previous session is closing; retry shortly"));}Ok(())
}
fn reconnect(dir:&Path)->io::Result<bool>{
    let mut finished=if rpc_at(&dir,"PING",64).is_ok(){
        match close_finished_at(dir){
            Ok(value)=>value,
            Err(e) if matches!(e.kind(),io::ErrorKind::ConnectionReset|io::ErrorKind::ConnectionAborted|io::ErrorKind::BrokenPipe|io::ErrorKind::ConnectionRefused)=>{
                // User may close the finished page between PING and the close query.
                // Wait for shutdown; the flock below still forbids duplicate workers.
                wait_closed(dir)?;true
            },
            Err(e)=>return Err(e),
        }
    }else{false};
    if finished{wait_closed(&dir)?;}
    if let Ok(answer)=rpc_at(&dir,"OPEN",64){
        if answer=="OK"{
            let deadline=Instant::now()+Duration::from_secs(140);let mut failures=0;
            loop {match rpc_at(&dir,"VIEW_STATUS",64) {
                Ok(status) if status=="READY"=>{super::terminal_notice("已接回現有工作；未重新執行工作。");return Ok(true);},
                Ok(status) if status=="FAILED"=>return Err(err(&format!("現有工作仍保留，但畫面未能開啟。\n服務日誌：{}\n崩潰日誌：{}（背景收集中；若無權限，原因記於 status.log）\n除錯包：/data/speed_debug/（尚未進入腳本時可能未產生）\n請提供上述日誌，再從原入口重試。",dir.join("service.log").display(),dir.join("crashes").display()))),
                Ok(status) if status=="PENDING"=>{failures=0;},
                Ok(status) if status=="FINISHED"=>{super::terminal_notice("原工作已結束；未重新啟動工作。");return Ok(true);},
                // Old supervisors have no readiness acknowledgement. Never call
                // their early OPEN acknowledgement a successful attachment.
                Err(e) if e.kind()==io::ErrorKind::Unsupported=>{super::terminal_notice("已向舊版工作送出接回要求，尚無畫面完成確認；若未開啟請從原終端重試，勿重複啟動備份。");return Ok(true);},
                _=>{failures+=1;if failures>=3||!dir.join("control").exists(){return Err(err(&format!("接回控制連線中斷，無法確認工作狀態；未重新啟動工作，請檢查 {}。",dir.join("service.log").display())));}},
            }
            if Instant::now()>=deadline{return Err(err(&format!("接回畫面尚未完成確認，等待已逾時；未重新啟動工作，請檢查 {}。",dir.join("service.log").display())));}
            std::thread::sleep(Duration::from_millis(100));}
        }
        if answer!="FINISHED"{return Err(err("unexpected console reopen response"));}
        finished=true;wait_closed(&dir)?;
    }
    // A reachable control socket is not the only evidence of a live worker:
    // never create a second namespace when its supervisor still owns the flock.
    let lock_path=dir.join("lock");
    if lock_path.exists(){
        let lock=OpenOptions::new().read(true).write(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK).open(lock_path)?;
        let m=lock.metadata()?;
        if !m.is_file()||m.uid()!=0||m.nlink()!=1||m.mode()&0o077!=0{return Err(err("console lock identity"));}
        let deadline=Instant::now()+Duration::from_millis(500);
        while unsafe{flock(lock.as_raw_fd(),2|4)}!=0{
            if !finished||Instant::now()>=deadline{return Err(err("舊工作仍持有執行鎖，但接回控制連線失敗；工作已保留，未啟動第二份工作。"));}
            std::thread::sleep(Duration::from_millis(10));
        }
    }
    Ok(false)
}
fn caller_diagnostics(dir:&Path)->io::Result<()> {
    let path=dir.join("caller-errors.log");
    let file=OpenOptions::new().append(true).create(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_NONBLOCK).open(&path)?;
    let m=file.metadata()?;
    if !m.is_file()||m.uid()!=0||m.nlink()!=1||m.mode()&0o077!=0 {return Err(err("caller diagnostic identity"));}
    std::env::set_var("SPEEDBACKUP_UI_ERROR_LOG",path);
    Ok(())
}
fn start(entry:&Path,args:&[String])->io::Result<i32>{
    // Report the real rejection to shortcut/terminal callers before detaching.
    // The service checks again in its own namespace before spawning the worker.
    super::super::restore_safety::app_data_namespace()?;
    if unsafe{getuid()}!=0{return Err(err("root required"));}let entry=entry.canonicalize()?;if !entry.is_file(){return Err(err("entry file"));}
    crate::runtime_cache::on_start();
    // Old jobs own their original immutable binaries and paths. Never move them.
    let legacy=Path::new("/data/.speedbackup_console/active");
    if legacy.exists(){private(legacy)?;caller_diagnostics(legacy)?;if reconnect(legacy)?{return Ok(0);}}
    let root=Path::new("/data/.speedbackup");
    if !root.exists(){use std::os::unix::fs::DirBuilderExt;fs::DirBuilder::new().mode(0o711).create(root)?;}
    let root_file=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE | speedbackup_native_rs::O_DIRECTORY_NATIVE).open(root)?;
    let m=root_file.metadata()?;
    if !m.is_dir()||m.uid()!=0||root.canonicalize()?!=root{return Err(err("runtime root identity"));}
    if m.mode()&0o777!=0o711 {use std::os::unix::fs::PermissionsExt;root_file.set_permissions(fs::Permissions::from_mode(0o711))?;}
    let base=Path::new(BASE);if !base.exists(){use std::os::unix::fs::DirBuilderExt;fs::DirBuilder::new().mode(0o700).create(base)?;}private(base)?;
    // One active job across entries, matching the existing global backup lock.
    let dir=base.join("active");if !dir.exists(){use std::os::unix::fs::DirBuilderExt;fs::DirBuilder::new().mode(0o700).create(&dir)?;}private(&dir)?;
    // An existing job owns its own native/Dex/embedded host version. Do not
    // upgrade its host APK with the new caller before reopening that job.
    caller_diagnostics(&dir)?;
    if reconnect(&dir)? { return Ok(0); }
    let logfile=OpenOptions::new().write(true).create(true).append(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(dir.join("service.log"))?;
    let mut cmd=Command::new(std::env::current_exe()?);cmd.args(["speedscan","console-service"]).arg(&dir).arg(&entry).args(args).stdin(Stdio::null()).stdout(logfile.try_clone()?).stderr(logfile);
    unsafe{cmd.pre_exec(||{
        unsafe extern "C"{fn signal(sig:i32,handler:usize)->usize;}
        if signal(2,0)==usize::MAX{return Err(io::Error::last_os_error());}
        if setsid()<0{return Err(io::Error::last_os_error());}Ok(())
    });}
    let mut child=cmd.spawn()?;let deadline=Instant::now()+Duration::from_secs(20);
    while Instant::now()<deadline {if dir.join("ready").exists()&&rpc_at(&dir,"PING",64).is_ok(){super::terminal_notice("工作已由獨立服務啟動，可在原生 APK 查看；關閉 APK 不會中止工作。");return Ok(0);}if let Some(rc)=child.try_wait()?{return Err(err(&format!("console startup failed: {rc}")));}std::thread::sleep(Duration::from_millis(100));}
    Err(err("console start pending; do not start a second job"))
}
pub(super) fn run(args:&[String])->i32{let result=match args{[mode,entry,tail @ ..]if mode=="start"=>start(Path::new(entry),tail),[mode,dir,entry,tail @ ..]if mode=="service"=>service(Path::new(dir),Path::new(entry),tail),_=>Err(err("console arguments"))};match result{Ok(rc)=>rc,Err(e)=>{ui_error("console",&e.to_string());65}}}

#[cfg(test)]
mod notification_tests {
    use super::*;
    #[test]
    fn close_probe_requires_complete_bounded_response(){
        assert!(!close_reply(b"HTTP/1.1 409 Conflict\r\nContent-Length: 4\r\n\r\nlive").unwrap());
        assert!(close_reply(b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ndone").unwrap());
        assert!(close_reply(b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ndo").is_err());
        assert!(close_reply(b"HTTP/1.1 200 OK\r\n").is_err());
    }
    #[test]
    fn close_probe_reads_framed_body_without_waiting_for_eof(){
        let (mut reader,mut writer)=UnixStream::pair().unwrap();
        reader.set_read_timeout(Some(Duration::from_millis(200))).unwrap();
        writer.write_all(b"HTTP/1.1 409 Conflict\r\nContent-Length: 4\r\n\r\nlive").unwrap();
        assert!(!read_close_reply(&mut reader).unwrap()); // Writer deliberately remains open.
    }
    #[test]
    fn coalesced_controller_events_drain_all_queued_lines(){
        let(tx,rx)=mpsc::sync_channel(3);
        tx.send("NAV_OK old".into()).unwrap();tx.send("WINDOW_CLOSED".into()).unwrap();
        assert!(controller_closed(&rx));
        assert!(!controller_closed(&rx));
        drop(tx);assert!(controller_closed(&rx));
    }
    #[test]
    fn guard_wait_wakes_on_detach_and_completion(){
        let s=state();let (tx,rx)=mpsc::sync_channel(1);let st=s.clone();
        let worker=std::thread::spawn(move||{tx.send(post(&st,"guard-wait","1")).unwrap();});
        assert!(rx.recv_timeout(Duration::from_millis(50)).is_err());
        s.ui.lock().unwrap().attached=false;s.sync_guard();
        assert!(rx.recv_timeout(Duration::from_secs(1)).unwrap().contains("\"attached\":false"));worker.join().unwrap();
        s.output.lock().unwrap().rc=Some(0);s.sync_guard();
        assert!(post(&s,"guard-wait","0").contains("\"active\":false"));
    }
    fn state()->Arc<Shared>{let (ui_signal,_)=mpsc::sync_channel(1);let (server_signal,_)=mpsc::sync_channel(16);Arc::new(Shared{dir:PathBuf::new(),guard:Mutex::new((true,true)),guard_wake:Condvar::new(),history_view:Mutex::new(None),history:None,output:Mutex::new(Output{bytes:VecDeque::new(),end:0,rc:None,progress:String::new(),revision:0,stop_status:String::new(),history_failed:false}),wake:Condvar::new(),ui_signal,server_signal,ui:Mutex::new(Ui{page:None,revision:0,reopen:0,attached:true,stop:false,held:false,seen_page:true,last_output:0,handoff:None,notification_reopen:None,ready_reopen:None}),worker:Mutex::new(None),stopping:std::sync::atomic::AtomicBool::new(false)})}
    fn rpc(s:&Arc<Shared>,line:&str)->String{
        let (mut a,mut b)=UnixStream::pair().unwrap();a.write_all(format!("{line}\n").as_bytes()).unwrap();a.shutdown(std::net::Shutdown::Write).unwrap();
        let(tx,_rx)=mpsc::sync_channel(2);control_request(&mut b,s.clone(),tx,0);drop(b);let mut result=String::new();a.read_to_string(&mut result).unwrap();result
    }
    fn post(s:&Arc<Shared>,path:&str,body:&str)->String{
        let l=TcpListener::bind("127.0.0.1:0").unwrap();let host=l.local_addr().unwrap().to_string();let st=s.clone();let h=host.clone();
        let t=std::thread::spawn(move||{http(l.accept().unwrap().0,st,h,"test-token".into());});
        let mut c=TcpStream::connect(&host).unwrap();c.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        write!(c,"POST /api/{path} HTTP/1.1\r\nHost: {host}\r\nX-SpeedBackup-Token: test-token\r\nContent-Length: {}\r\n\r\n{body}",body.len()).unwrap();
        let mut reply=String::new();c.read_to_string(&mut reply).unwrap();t.join().unwrap();reply
    }
    #[test]
    fn history_invalid_utf8_and_incomplete_tail_always_advance(){
        let path=PathBuf::from(format!("/data/local/tmp/sb-history-{}",random_hex().unwrap()));
        let mut s=state();
        Arc::get_mut(&mut s).unwrap().history=Some(OpenOptions::new().read(true).write(true).create_new(true).mode(0o600).open(&path).unwrap());
        append(&s,b"a\xffb\n");
        let first=history_page(&s,"head").unwrap();assert!(first.contains("\"next\":4"));assert!(first.contains(&b64(b"a\xffb\n")));
        append(&s,&[0xe4,0xb8]);
        let tail=history_page(&s,"after\t4").unwrap();assert!(tail.contains("\"next\":6"));
        fs::remove_file(path).unwrap();
    }
    #[test]
    fn readiness_is_distinct_from_request_and_completion(){
        let s=state();assert_eq!(rpc(&s,"VIEW_STATUS"),"PENDING");
        {let mut u=s.ui.lock().unwrap();u.ready_reopen=Some(u.reopen);}
        assert_eq!(rpc(&s,"VIEW_STATUS"),"READY");
        rpc(&s,"OPEN");assert_eq!(rpc(&s,"VIEW_STATUS"),"PENDING");
        {let mut u=s.ui.lock().unwrap();u.attached=false;}
        assert_eq!(rpc(&s,"VIEW_STATUS"),"FAILED");
        s.output.lock().unwrap().rc=Some(0);
        assert_eq!(rpc(&s,"VIEW_STATUS"),"FINISHED");
        assert_eq!(rpc(&s,"unknown"),"ERROR command");
    }
    #[test]
    fn editor_return_handoff_is_scoped_and_bounded(){
        let s=state();let id="a".repeat(64);let next="b".repeat(64);
        let page=|id:&str|format!("PAGE\t{id}\thttp://127.0.0.1:1234/#{}\treview","c".repeat(64));
        rpc(&s,&page(&id));rpc(&s,&format!("DONE\t{next}\treturn"));
        assert!(s.ui.lock().unwrap().handoff.is_none());
        rpc(&s,&format!("DONE\t{id}\treturn"));
        {let u=s.ui.lock().unwrap();assert!(u.returning());assert!(u.page.is_none());}
        append(&s,b"editor saved\n");rpc(&s,&page(&next));
        {let u=s.ui.lock().unwrap();assert!(!u.held);assert!(u.handoff.is_none());}
        // Normal work is never treated as a return: retain its output review.
        rpc(&s,&format!("DONE\t{next}"));append(&s,b"actual work\n");rpc(&s,&page(&id));
        assert!(s.ui.lock().unwrap().held);
        rpc(&s,&format!("DONE\t{id}\treturn"));
        s.ui.lock().unwrap().handoff=Some(Instant::now()-Duration::from_secs(3));
        assert!(!s.ui.lock().unwrap().returning());
        append(&s,b"fallback diagnostic\n");rpc(&s,&page(&next));
        assert!(s.ui.lock().unwrap().held);
    }
    #[test]
    fn explicit_progress_erase_clears_snapshot() {
        let s=state();
        progress_snapshot(&s,"封裝約95.1% 127 MB/s");
        let revision=s.output.lock().unwrap().revision;
        progress_snapshot(&s,"");
        assert_eq!(s.output.lock().unwrap().revision,revision);
        progress_snapshot(&s,"\x1b[2");
        assert_eq!(s.output.lock().unwrap().revision,revision);
        progress_snapshot(&s,"\x1b[2K");
        assert!(s.output.lock().unwrap().progress.is_empty());
        assert_eq!(s.output.lock().unwrap().revision,revision+1);
        progress_snapshot(&s,"封裝約1.0% 10 MB/s\x1b[K");
        assert_eq!(s.output.lock().unwrap().progress,"封裝約1.0% 10 MB/s");
        progress_snapshot(&s,"\x1b[K");
        assert!(s.output.lock().unwrap().progress.is_empty());
    }
    #[test]
    fn page_before_poll_and_progress_are_not_lost(){
        let s=state();append(&s,b"x");let id="a".repeat(64);rpc(&s,&format!("PAGE\t{id}\thttp://127.0.0.1:1234/#{}\treview","b".repeat(64)));
        let start=Instant::now();let r=post(&s,"output","1\t0");assert!(start.elapsed()<Duration::from_secs(1));assert!(r.contains(&format!("\"pending\":\"{id}\"")));assert!(r.contains("\"revision\":1"));
        // Old callers without a state cursor must get an immediate snapshot too.
        assert!(post(&s,"output","1").contains(&id));
        assert!(post(&s,"continue",&id).contains("200 OK"));assert!(post(&s,"output","1\t1").contains("\"pending\":\"\""));
        rpc(&s,&format!("DONE\t{id}"));assert!(post(&s,"output","1\t2").contains("\"revision\":3"));
        progress_snapshot(&s,"120 MB/s");let r=post(&s,"output","1\t3");assert!(r.contains("120 MB/s"));assert!(r.contains("\"revision\":4"));
    }
    #[test]
    fn idle_poll_blocks_then_page_wakes_without_new_log(){
        let s=state();append(&s,b"x");let st=s.clone();let(tx,rx)=mpsc::channel();
        let t=std::thread::spawn(move||{tx.send(post(&st,"output","1\t0")).unwrap();});
        assert!(rx.recv_timeout(Duration::from_millis(100)).is_err());
        let id="a".repeat(64);rpc(&s,&format!("PAGE\t{id}\thttp://127.0.0.1:1234/#{}\treview","b".repeat(64)));
        assert!(rx.recv_timeout(Duration::from_secs(1)).unwrap().contains(&id));t.join().unwrap();
    }
}

#[cfg(test)]
mod session_cleanup_tests {
 use super::*;
 use std::os::unix::fs::{DirBuilderExt,symlink};
 #[test]fn removes_session_artifacts_preserves_lock_and_unrelated_files(){
  let base=PathBuf::from(format!("/data/local/tmp/sb-console-cleanup-{}",random_hex().unwrap()));fs::DirBuilder::new().mode(0o700).create(&base).unwrap();
  for n in ["lock","service.log","ready","control","session","page","progress","pending-language","unrelated"]{fs::write(base.join(n),b"keep").unwrap();}
  let before=fs::metadata(base.join("lock")).unwrap().ino();cleanup_session_files(&base).unwrap();
  for n in ["ready","control","session","page","progress","guard-active"]{assert!(!base.join(n).exists());}
  assert_eq!(fs::metadata(base.join("lock")).unwrap().ino(),before);for n in ["lock","service.log","unrelated"]{assert_eq!(fs::read(base.join(n)).unwrap(),b"keep");}
  symlink(base.join("unrelated"),base.join("session")).unwrap();cleanup_session_files(&base).unwrap();assert_eq!(fs::read(base.join("unrelated")).unwrap(),b"keep");
  fs::create_dir(base.join("page")).unwrap();assert!(cleanup_session_files(&base).is_err());assert!(base.join("page").is_dir());fs::remove_dir_all(base).unwrap();
 }
}

#[cfg(test)]
mod reconnect_lock_tests {
    use super::*;
    #[test]
    fn missing_socket_does_not_hide_live_supervisor_lock(){
        use std::os::unix::fs::DirBuilderExt;
        let dir=PathBuf::from(format!("/data/local/tmp/sb-reconnect-{}",random_hex().unwrap()));
        fs::DirBuilder::new().mode(0o700).create(&dir).unwrap();
        let file=OpenOptions::new().write(true).create_new(true).mode(0o600).open(dir.join("lock")).unwrap();
        assert_eq!(unsafe{flock(file.as_raw_fd(),2|4)},0);
        assert!(reconnect(&dir).is_err());
        drop(file);
        assert!(!reconnect(&dir).unwrap());
        fs::remove_file(dir.join("lock")).unwrap();fs::remove_dir(dir).unwrap();
    }
}
