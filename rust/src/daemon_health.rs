//! Observe authenticated local daemon handshakes and lifecycle events; no timer pings.
use std::{fs,io::{self,Read,Write},os::{fd::{AsRawFd,FromRawFd,OwnedFd},unix::{fs::MetadataExt,net::UnixStream}},path::{Path,PathBuf},sync::{Arc,atomic::Ordering},time::Duration};
use serde_json::{json,Value};
use speedbackup_native_rs::{inotify_init1,inotify_add_watch,read,poll,PollFd,O_CLOEXEC,O_NONBLOCK,POLLIN};
use super::command_lifecycle::{CancelEvent,OwnedChild};
pub struct Watch(Arc<CancelEvent>);
impl Drop for Watch{fn drop(&mut self){self.0.store(true,Ordering::Release);}}
struct Death {fd:OwnedFd,pid:i32,_child:Option<OwnedChild>}
struct Daemon {dirty:bool,name:&'static str,record:bool,kind:&'static str,path:PathBuf,key:Option<(u64,u64)>,pid:Option<Death>,state:Value}
fn handshake(path:&Path,rust:bool)->io::Result<Death>{
    let mut stream=UnixStream::connect(path)?;
    stream.set_read_timeout(Some(Duration::from_millis(800)))?;stream.set_write_timeout(Some(Duration::from_millis(800)))?;
    #[repr(C)] struct Cred{pid:i32,uid:u32,gid:u32}
    unsafe extern "C"{fn getsockopt(fd:i32,level:i32,opt:i32,value:*mut std::ffi::c_void,len:*mut u32)->i32;}
    let mut cred=Cred{pid:0,uid:1,gid:1};let mut len=std::mem::size_of::<Cred>() as u32;
    if unsafe{getsockopt(stream.as_raw_fd(),1,17,&mut cred as *mut _ as _,&mut len)}!=0||len!=std::mem::size_of::<Cred>() as u32||cred.uid!=0||cred.pid<=1{return Err(io::Error::other("peer identity"));}
    // Open before the handshake so a death during reply cannot yield stale green.
    let pid=observe_pid(cred.pid)?;
    stream.write_all(if rust{b"PING\n"}else{b"ping\n"})?;stream.shutdown(std::net::Shutdown::Write)?;
    let mut bytes=Vec::new();stream.take(4097).read_to_end(&mut bytes)?;
    let text=String::from_utf8_lossy(&bytes);
    let valid=if rust{text.starts_with("CGFREEZER_DAEMON_PONG ok=true ")}else{text.starts_with("RESULT 0 OK\n")&&text.lines().last()==Some("PONG")};
    if bytes.len()>4096||!valid{return Err(io::Error::other("handshake"));}
    Ok(pid)
}
fn observe_pid(pid:i32)->io::Result<Death>{
    match speedbackup_native_rs::pidfd_open(pid) {
        Ok(fd)=>Ok(Death{fd:unsafe{OwnedFd::from_raw_fd(fd)},pid,_child:None}),
        Err(_)=>{
            // Existing eventwait provides the old-kernel compatibility backend.
            use std::process::{Command,Stdio};
            let mut command=Command::new(std::env::current_exe()?);
            command.args(["eventwait","pid-exit",&pid.to_string(),"0","daemon-health"]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
            super::command_lifecycle::parent_guard(&mut command);
            let mut child=OwnedChild::spawn(&mut command)?;
            let stdout=child.stdout.take().ok_or_else(||io::Error::other("process events"))?;
            Ok(Death{fd:stdout.into(),pid,_child:Some(child)})
        }
    }
}
fn identity(pid:i32)->Option<String>{
    let text=fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let rest=speedbackup_native_rs::proc_stat::split(&text)?.1;
    if rest.starts_with("Z "){return None;}
    rest.split_whitespace().nth(19).map(str::to_owned)
}
pub fn register_process(name:&str,pid:u32)->io::Result<()> {
    let Some(run)=std::env::var_os("SPEEDBACKUP_RUN_TMPDIR") else{return Ok(());};
    let start=identity(pid as i32).unwrap_or_default();
    super::publish_file::publish_bytes_guarded(format!("{pid} {start}\n").as_bytes(),&PathBuf::from(run).join(format!(".health-service-{name}")),Some(0o600),false,&mut||Ok(())).map(|_|())
}
fn record_handshake(path:&Path)->io::Result<Death>{
    let text=fs::read_to_string(path)?;let mut fields=text.split_whitespace();
    let pid:i32=fields.next().and_then(|s|s.parse().ok()).filter(|p|*p>1).ok_or_else(||io::Error::other("pid"))?;
    let start=fields.next().ok_or_else(||io::Error::other("start"))?;
    let death=observe_pid(pid)?;
    if identity(pid).as_deref()!=Some(start){return Err(io::Error::other("process exited"));}
    Ok(death)
}
fn aggregate(daemons:&[Daemon])->Value {
    let mut data=json!({});
    for kind in ["rust","dex","services"] {
        let mut components=Vec::new();let mut failures=Vec::new();let mut pending=false;
        for d in daemons.iter().filter(|d|d.kind==kind) {
            // Keep optional services visible, but do not let an inactive service
            // turn the existing Rust/Dex summary into a false failure.
            if d.record&&d.key.is_none(){
                components.push(json!({"name":d.name,"status":"idle","reason":"not_started","verification":"process"}));
                continue;
            }
            let status=d.state["status"].as_str().unwrap_or("checking");
            components.push(json!({"name":d.name,"status":status,"reason":d.state["reason"],"pid":d.pid.as_ref().map(|p|p.pid),"verification":if d.record{"process"}else{"handshake"}}));
            if status=="offline"{failures.push(json!({"name":d.name,"reason":d.state["reason"]}));}
            else if status!="ready"{pending=true;}
        }
        data[kind]=json!({"status":if !failures.is_empty(){"offline"}else if pending{"checking"}else{"ready"},"reason":if failures.is_empty(){""}else{"component_failed"},"components":components,"failures":failures});
    }
    data
}
fn publish(dir:&Path,daemons:&[Daemon])->io::Result<()> {
    let data=aggregate(daemons);
    let bytes=serde_json::to_vec(&data)?;
    super::publish_file::publish_bytes_guarded(&bytes,&dir.join("daemons.json"),Some(0o600),false,&mut||Ok(())).map(|_|())
}
pub fn start(dir:&Path)->io::Result<Watch>{
    let cancel=Arc::new(CancelEvent::new()?);let flag=cancel.clone();let dir=dir.to_owned();
    let endpoints=[("rust","cgfreezer","SPEEDBACKUP_CGROUP_FREEZER_SOCKET"),("dex","RootDaemon","SPEEDBACKUP_DEX_HEALTH_SOCKET")];
    let mut daemons=endpoints.into_iter().map(|(kind,name,env)|Daemon{dirty:true,name,record:false,kind,path:std::env::var_os(env).map(PathBuf::from).unwrap_or_default(),key:None,pid:None,state:json!({"status":"idle","reason":"not_started"})}).collect::<Vec<_>>();
    let run_dir=std::env::var_os("SPEEDBACKUP_RUN_TMPDIR");
    for (kind,name,tag) in [("rust","File broker","file_broker"),("rust","TTY relay","ui_relay"),("rust","netwatch","netwatch_native"),("rust","Console service","console"),("dex","WebDAV daemon","webdav_daemon"),("dex","Root watchdog","rootdex_watchdog"),("dex","WebDAV watchdog","webdav_watchdog"),("dex","Wi-Fi watcher","wifi_watcher"),("services","Health monitor","remote_health"),("services","Network event reader","netwatch_reader"),("services","SMB publisher","smbclient_publisher")] {
        let path=run_dir.as_ref().map(|r|PathBuf::from(r).join(format!(".health-service-{tag}"))).unwrap_or_default();
        daemons.push(Daemon{dirty:true,name,record:true,kind,path,key:None,pid:None,state:json!({"status":"idle","reason":"not_started"})});
    }
    std::thread::Builder::new().name("daemon-health-events".into()).spawn(move||{if let Err(error)=run(&dir,flag,daemons){
        eprintln!("DAEMON_HEALTH_FAILED {error}");
        let value=snapshot(&dir,false);
        let _=super::publish_file::publish_bytes_guarded(value.to_string().as_bytes(),&dir.join("daemons.json"),Some(0o600),false,&mut||Ok(()));
    }})?;
    Ok(Watch(cancel))
}
fn refresh_daemon(d:&mut Daemon) {
                let key=fs::symlink_metadata(&d.path).ok().map(|m|(m.dev(),m.ino()));
                if d.dirty||key!=d.key {d.dirty=false;d.key=key;d.pid=None;
                    d.state=if key.is_none(){if d.state["status"]=="ready"||d.state["status"]=="offline"{json!({"status":"offline","reason":"process_exited"})}else{json!({"status":"idle","reason":"not_started"})}}else{match if d.record{record_handshake(&d.path)}else{handshake(&d.path,d.kind=="rust")}{
                        Ok(pid)=>{d.pid=Some(pid);json!({"status":"ready","reason":""})},
                        Err(e)=>json!({"status":"offline","reason":if matches!(e.kind(),io::ErrorKind::WouldBlock|io::ErrorKind::TimedOut){"timeout"}else if d.record{"process_exited"}else{"handshake_failed"}}),
                    }};
                }
}
fn run(dir:&Path,cancel:Arc<CancelEvent>,mut daemons:Vec<Daemon>)->io::Result<()> {
    let fd=unsafe{inotify_init1(O_CLOEXEC|O_NONBLOCK)};if fd<0{return Err(io::Error::last_os_error());}let ino=unsafe{OwnedFd::from_raw_fd(fd)};
    let mut watches=Vec::new();
    for d in &daemons {if let Some(parent)=d.path.parent().filter(|p|!p.as_os_str().is_empty()){
        use std::os::unix::ffi::OsStrExt;
        let name=std::ffi::CString::new(parent.as_os_str().as_bytes())?;
        let wd=unsafe{inotify_add_watch(fd,name.as_ptr(),0x100|0x200|0x80|0x40|0x400|0x800|4|0x20000000)};
        if wd<0{return Err(io::Error::last_os_error());}
        watches.push((wd,d.path.file_name().unwrap().as_bytes().to_vec()));
    }}
    let dir_name=std::ffi::CString::new(dir.as_os_str().as_encoded_bytes())?;
    let refresh_watch=unsafe{inotify_add_watch(fd,dir_name.as_ptr(),0x100|0x80|8|0x20000000)};
    if refresh_watch<0{return Err(io::Error::last_os_error());}
    let mut refresh=true;
    loop {
        if cancel.load(Ordering::Acquire){return Ok(());}
        if refresh {
            for d in &mut daemons {
                refresh_daemon(d);
            }
            publish(dir,&daemons)?;refresh=false;
        }
        let mut fds=vec![PollFd{fd:ino.as_raw_fd(),events:POLLIN,revents:0},PollFd{fd:cancel.fd(),events:POLLIN,revents:0}];
        let mut indices=Vec::new();for(i,d)in daemons.iter().enumerate(){if let Some(pid)=&d.pid{indices.push((i,fds.len()));fds.push(PollFd{fd:pid.fd.as_raw_fd(),events:POLLIN,revents:0});}}
        if unsafe{poll(fds.as_mut_ptr(),fds.len() as _,-1)}<0{if io::Error::last_os_error().kind()==io::ErrorKind::Interrupted{continue;}return Err(io::Error::last_os_error());}
        if fds[1].revents!=0{return Ok(());}
        for(i,n)in indices{if fds[n].revents!=0{daemons[i].pid=None;daemons[i].state=json!({"status":"offline","reason":"process_exited"});refresh=true;}}
        if fds[0].revents!=0{
            let mut buf=[0u8;8192];loop{let n=unsafe{read(fd,buf.as_mut_ptr() as _,buf.len())};if n<0{let error=io::Error::last_os_error();if error.kind()==io::ErrorKind::Interrupted{continue;}if error.kind()==io::ErrorKind::WouldBlock{break;}return Err(error);}if n==0{return Err(io::Error::new(io::ErrorKind::UnexpectedEof,"inotify closed"));}let mut offset=0;
                while offset+16<=n as usize {let wd=i32::from_ne_bytes(buf[offset..offset+4].try_into().unwrap());let len=u32::from_ne_bytes(buf[offset+12..offset+16].try_into().unwrap()) as usize;
                    if offset+16+len>n as usize{break;}let name=&buf[offset+16..offset+16+len];let name=&name[..name.iter().position(|b|*b==0).unwrap_or(name.len())];
                    if wd==refresh_watch&&name==b"daemon-refresh"{for d in &mut daemons{d.dirty=true;}refresh=true;}
                    if wd<0{for d in &mut daemons{d.dirty=true;}refresh=true;}
                    else if watches.iter().any(|(watch,file)|*watch==wd&&file==name){
                        for d in &mut daemons{if d.path.file_name().is_some_and(|f|f.as_encoded_bytes()==name){d.dirty=true;}}
                        refresh=true;
                    }offset+=16+len;
                }
            }
        }
    }
}
pub fn snapshot(dir:&Path,alive:bool)->Value {
    let mut data:Value=fs::read(dir.join("daemons.json")).ok().and_then(|b|serde_json::from_slice(&b).ok()).unwrap_or_else(||json!({}));
    if !alive{for key in ["rust","dex","services"]{
        let mut components=data[key]["components"].as_array().cloned().unwrap_or_default();
        for component in &mut components{component["status"]=json!("unknown");component["reason"]=json!("monitor_stopped");component["pid"]=Value::Null;}
        data[key]=json!({"status":"offline","reason":"monitor_stopped","components":components,"failures":[{"name":"Health monitor","reason":"monitor_stopped"}]});
    }}
    data
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn monitor_failure_preserves_components_and_marks_all_groups_offline(){
        let dir=std::env::temp_dir().join(format!("sb-review-monitor-{}",std::process::id()));
        fs::create_dir(&dir).unwrap();
        let stale=json!({"services":{"status":"ready","components":[{"name":"SMB publisher","status":"ready","pid":123}]}});
        fs::write(dir.join("daemons.json"),stale.to_string()).unwrap();
        let failed=snapshot(&dir,false);
        for kind in ["rust","dex","services"]{assert_eq!(failed[kind]["status"],"offline");assert_eq!(failed[kind]["reason"],"monitor_stopped");}
        assert_eq!(failed["services"]["components"][0]["name"],"SMB publisher");
        assert_eq!(failed["services"]["components"][0]["status"],"unknown");
        assert!(failed["services"]["components"][0]["pid"].is_null());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test] fn inactive_optional_is_visible_without_failing_summary(){
        let d=Daemon{dirty:false,name:"File broker",record:true,kind:"rust",path:PathBuf::new(),key:None,pid:None,state:json!({"status":"offline","reason":"process_exited"})};
        let data=aggregate(&[d]);
        assert_eq!(data["rust"]["status"],"ready");
        assert_eq!(data["rust"]["components"][0]["status"],"idle");
        assert_eq!(data["rust"]["components"][0]["name"],"File broker");
        assert_eq!(data["rust"]["failures"],json!([]));
    }
    #[test] fn refresh_missing_core_cannot_keep_green(){
        let mut d=Daemon{dirty:true,name:"RootDaemon",record:false,kind:"dex",path:PathBuf::new(),key:Some((1,2)),pid:None,state:json!({"status":"ready","reason":""})};
        refresh_daemon(&mut d);
        assert_eq!(d.state["status"],"offline");assert_eq!(d.state["reason"],"process_exited");
    }
    #[test] #[ignore = "controlled Android integration fixture"]
    fn lifecycle_aggregate_android(){
        use std::{process::{Command,Stdio},thread,time::{Duration,Instant}};
        let base=PathBuf::from(format!("/data/local/tmp/sb-convergence-health-{}",std::process::id()));
        fs::create_dir_all(&base).unwrap();let dir=base.join("health");fs::create_dir_all(&dir).unwrap();
        std::env::set_var("SPEEDBACKUP_RUN_TMPDIR",&base);
        for (key,rust) in [("SPEEDBACKUP_CGROUP_FREEZER_SOCKET",true),("SPEEDBACKUP_DEX_HEALTH_SOCKET",false)] {
            let path=base.join(if rust{"rust.sock"}else{"dex.sock"});std::env::set_var(key,&path);
            let listener=std::os::unix::net::UnixListener::bind(path).unwrap();
            thread::spawn(move||for stream in listener.incoming(){let mut stream=stream.unwrap();let mut input=[0u8;32];let _=stream.read(&mut input);let _=stream.write_all(if rust{b"CGFREEZER_DAEMON_PONG ok=true pid=123\n"}else{b"RESULT 0 OK\n5\nPONG\n"});});
        }
        let spawn=||Command::new("/system/bin/sleep").arg("120").stdin(Stdio::null()).stdout(Stdio::null()).spawn().unwrap();
        let mut rust=spawn();let mut dex=spawn();
        register_process("ui_relay",rust.id()).unwrap();register_process("wifi_watcher",dex.id()).unwrap();
        let watch=start(&dir).unwrap();
        let wait=|kind:&str,status:&str,name:Option<&str>|{
            let until=Instant::now()+Duration::from_secs(4);
            loop {let data=snapshot(&dir,true);if data[kind]["status"]==status&&name.is_none_or(|name|data[kind]["failures"].as_array().is_some_and(|f|f.iter().any(|v|v["name"]==name))){break;}
                assert!(Instant::now()<until,"expected {kind} {status}: {data}");thread::sleep(Duration::from_millis(10));}
        };
        wait("rust","ready",None);wait("dex","ready",None);
        let data=snapshot(&dir,true);
        assert_eq!(["rust","dex","services"].iter().map(|k|data[k]["components"].as_array().unwrap().len()).sum::<usize>(),13);
        assert!(data["rust"]["components"].as_array().unwrap().iter().any(|v|v["name"]=="TTY relay"&&v["pid"]==rust.id()&&v["verification"]=="process"));
        let stopped=snapshot(&dir,false);
        for kind in ["rust","dex","services"]{for component in stopped[kind]["components"].as_array().unwrap(){assert_eq!(component["status"],"unknown");assert!(component["pid"].is_null());}}
        // A rename event must re-read even if dev/inode did not change.
        let record=base.join(".health-service-ui_relay");let moved=base.join("record-move");
        fs::write(&record,format!("{} invalid-start\n",rust.id())).unwrap();
        fs::rename(&record,&moved).unwrap();fs::rename(&moved,&record).unwrap();
        wait("rust","offline",Some("TTY relay"));
        register_process("ui_relay",rust.id()).unwrap();wait("rust","ready",None);
        rust.kill().unwrap();rust.wait().unwrap();wait("rust","offline",Some("TTY relay"));wait("dex","ready",None);
        rust=spawn();register_process("ui_relay",rust.id()).unwrap();wait("rust","ready",None);
        dex.kill().unwrap();dex.wait().unwrap();wait("dex","offline",Some("Wi-Fi watcher"));wait("rust","ready",None);
        fs::remove_file(base.join(".health-service-wifi_watcher")).unwrap();wait("dex","ready",None);
        fs::remove_file(base.join(".health-service-ui_relay")).unwrap();rust.kill().unwrap();rust.wait().unwrap();wait("rust","ready",None);
        let wrong=base.join(".health-service-webdav_daemon");fs::write(&wrong,format!("{} invalid-start\n",std::process::id())).unwrap();
        wait("dex","offline",Some("WebDAV daemon"));fs::remove_file(wrong).unwrap();wait("dex","ready",None);
        assert_eq!(snapshot(&dir,false)["rust"]["status"],"offline");
        drop(watch);thread::sleep(Duration::from_millis(50));fs::remove_dir_all(base).unwrap();
    }
    #[test] #[ignore = "controlled Android integration fixture"]
    fn fixture(){
        let path=std::env::var("SB_TEST_DAEMON_SOCKET").unwrap();assert!(path.starts_with("/data/local/tmp/sb-convergence-"));
        let rust=std::env::var("SB_TEST_DAEMON_KIND").unwrap()=="rust";
        let _=fs::remove_file(&path);let listener=std::os::unix::net::UnixListener::bind(path).unwrap();
        std::thread::spawn(move||for stream in listener.incoming(){let mut stream=stream.unwrap();let mut input=[0u8;32];let _=stream.read(&mut input);let _=stream.write_all(if rust{b"CGFREEZER_DAEMON_PONG ok=true pid=123\n"}else{b"RESULT 0 OK\n5\nPONG\n"});});
        let mut stop=String::new();let _=io::stdin().read_line(&mut stop);std::process::exit(0);
    }
}
