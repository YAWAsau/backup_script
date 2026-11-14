//! One bounded, credential-free discovery task per network and parameter set.
//! Subscribers may leave independently; results expire and never authorize I/O.
use super::*;
use std::{os::{fd::AsRawFd,unix::net::{UnixListener,UnixStream,SocketAddr}},io::{BufRead,BufReader},sync::Condvar};
#[cfg(target_os="android")] use std::os::android::net::SocketAddrExt;
#[cfg(target_os="linux")] use std::os::linux::net::SocketAddrExt;
use speedbackup_native_rs::{poll,PollFd,POLLIN};
unsafe extern "C" {fn geteuid()->u32;fn getsockopt(fd:i32,l:i32,o:i32,v:*mut std::ffi::c_void,n:*mut u32)->i32;fn setsid()->i32;}
const CACHE:Duration=Duration::from_secs(20);
#[derive(Default)] struct State {value:Option<Value>,version:u64,running:bool,finished:Option<Instant>,generation:u64}
#[derive(Default)] struct Job {state:Mutex<State>,wake:Condvar}
fn same_peer(socket:&UnixStream)->bool {
    let mut cred=[0u32;3];let mut len=12u32;
    unsafe{getsockopt(socket.as_raw_fd(),1,17,cred.as_mut_ptr() as _,&mut len)==0&&len==12&&cred[1]==geteuid()}
}
fn scope()->io::Result<String>{
    let mut interfaces=if_addrs::get_if_addrs()?.into_iter().filter(|i|i.is_oper_up()&&!i.is_loopback()).map(|i|format!("{}:{:?}",i.name,i.addr)).collect::<Vec<_>>();interfaces.sort();
    let value=format!("{}:{}:{:?}:{}:{}",env!("CARGO_PKG_VERSION"),unsafe{geteuid()},interfaces,
        std::fs::read_link("/proc/self/ns/net")?.display(),std::fs::read_to_string("/proc/net/route")?);
    super::super::super::sha256_reader_hex(value.as_bytes())
}
fn address(scope:&str)->io::Result<SocketAddr>{SocketAddr::from_abstract_name(format!("sb-discovery-v1-{scope}"))}
fn connect(key:&str)->io::Result<UnixStream>{
    let addr=address(key)?;
    let check=|s:UnixStream|if same_peer(&s){Ok(s)}else{Err(io::Error::new(io::ErrorKind::PermissionDenied,"搜尋服務身分不符"))};
    match UnixStream::connect_addr(&addr){Ok(s)=>return check(s),Err(e) if matches!(e.kind(),io::ErrorKind::ConnectionRefused|io::ErrorKind::NotFound)=>{},Err(e)=>return Err(e)}
    let mut child=std::process::Command::new(std::env::current_exe()?).args(["speedscan","discovery-broker",key])
        .stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).spawn()?;
    std::thread::spawn(move||{let _=child.wait();});
    // Only broker startup retries. Live subscriptions use poll + cancellation FD.
    let deadline=Instant::now()+Duration::from_secs(3);
    loop{match UnixStream::connect_addr(&addr){Ok(s)=>return check(s),Err(e)=>{if Instant::now()>=deadline{return Err(e);}std::thread::sleep(Duration::from_millis(25));}}}
}
pub(super) fn subscribe(parameters:&[String],fresh:bool,cancel:&CancelEvent,mut emit:impl FnMut(Value)->io::Result<()>)->io::Result<()> {
    subscribe_with_settle(parameters,fresh,cancel,false,&mut emit)
}
pub(super) fn subscribe_with_settle(parameters:&[String],fresh:bool,cancel:&CancelEvent,settle:bool,mut emit:impl FnMut(Value)->io::Result<()>)->io::Result<()> {
    if cancel.load(Ordering::Acquire){return Ok(());}
    let key=scope()?;let mut socket=connect(&key)?;socket.set_write_timeout(Some(Duration::from_secs(2)))?;
    writeln!(socket,"{}",json!({"parameters":parameters,"fresh":fresh}))?;
    socket.set_nonblocking(true)?;
    let mut bytes=Vec::new();let deadline=Instant::now()+Duration::from_secs(40);let mut completed=false;
    let mut recheck:Option<Instant>=None;let mut latest=None;
    loop{
        if cancel.load(Ordering::Acquire){return Ok(());}
        if recheck.is_some_and(|t|Instant::now()>=t){recheck=None;if let Some(value)=latest.take(){emit(value)?;}if cancel.load(Ordering::Acquire){return Ok(());}}
        let left=deadline.saturating_duration_since(Instant::now());if left.is_zero(){return Err(io::Error::new(io::ErrorKind::TimedOut,"搜尋逾時"));}
        let left=left.min(recheck.map(|t|t.saturating_duration_since(Instant::now())).unwrap_or(left));
        let mut fds=[PollFd{fd:socket.as_raw_fd(),events:POLLIN,revents:0},PollFd{fd:cancel.fd(),events:POLLIN,revents:0}];
        if unsafe{poll(fds.as_mut_ptr(),2,left.as_millis().min(i32::MAX as u128) as i32)}<0{let e=io::Error::last_os_error();if e.kind()==io::ErrorKind::Interrupted{continue;}return Err(e);}
        if cancel.load(Ordering::Acquire){return Ok(());}
        let mut chunk=[0u8;8192];
        loop{use std::io::Read;match socket.read(&mut chunk){
            Ok(0)=>return if completed{Ok(())}else{Err(io::Error::new(io::ErrorKind::UnexpectedEof,"搜尋服務提前斷線"))},
            Ok(n)=>{bytes.extend_from_slice(&chunk[..n]);if bytes.len()>1024*1024{return Err(io::Error::other("搜尋結果過大"));}
                while let Some(end)=bytes.iter().position(|b|*b==b'\n'){
                    let row:Value=serde_json::from_slice(&bytes[..end])?;bytes.drain(..=end);
                    completed=row["running"]==false;
                    if settle&&!completed {latest=Some(row.clone());recheck=Some(Instant::now()+Duration::from_millis(1250));}
                    emit(row)?;if completed{return Ok(());}
                }
            },Err(e) if e.kind()==io::ErrorKind::WouldBlock=>break,Err(e) if e.kind()==io::ErrorKind::Interrupted=>continue,Err(e)=>return Err(e)
        }}
    }
}
fn publish(job:&Job,mut value:Value){
    let mut s=job.state.lock().unwrap();s.version+=1;value["generation"]=json!(s.generation);s.running=value["running"]==true;
    if !s.running{s.finished=Some(Instant::now());}s.value=Some(value);job.wake.notify_all();
}
fn needs_start(s:&State,fresh:bool)->bool{!s.running&&(fresh||s.finished.is_none_or(|t|t.elapsed()>=CACHE))}
fn serve(mut socket:UnixStream,jobs:&Mutex<BTreeMap<Vec<String>,Arc<Job>>>,network:&str)->io::Result<()> {
    if !same_peer(&socket){return Err(io::Error::new(io::ErrorKind::PermissionDenied,"搜尋用戶身分不符"));}
    socket.set_read_timeout(Some(Duration::from_secs(2)))?;socket.set_write_timeout(Some(Duration::from_secs(2)))?;
    let mut request=String::new();use std::io::Read;
    BufReader::new((&socket).take(4097)).read_line(&mut request)?;
    if request.len()>4096||!request.ends_with('\n'){return Err(io::Error::other("搜尋請求無效"));}
    let request:Value=serde_json::from_str(&request)?;
    let parameters:Vec<String>=serde_json::from_value(request["parameters"].clone())?;
    let parameters=normalize(&parameters)?;
    if scope()?!=network{return Err(io::Error::other("網路已變更，請重新搜尋"));}
    let job={let mut jobs=jobs.lock().unwrap();jobs.retain(|_,j|{let s=j.state.lock().unwrap();s.running||Arc::strong_count(j)>1||s.finished.is_some_and(|t|t.elapsed()<CACHE)});
        if !jobs.contains_key(&parameters)&&jobs.len()>=4{return Err(io::Error::other("進行中的搜尋過多"));}
        let old=jobs.entry(parameters.clone()).or_default();
        let restart=needs_start(&old.state.lock().unwrap(),request["fresh"]==true);
        if restart {
            // Retain the completed generation for subscribers still draining it.
            // Refresh publishes a new job; it must not reset their completion.
            let generation=old.state.lock().unwrap().generation+1;
            *old=Arc::new(Job::default());
            old.state.lock().unwrap().generation=generation;
        }
        let job=old.clone();
        let mut s=job.state.lock().unwrap();
        if restart {
            s.running=true;s.finished=None;s.version+=1;
            s.value=Some(json!({"running":true,"endpoints":[],"generation":s.generation}));
            let worker=job.clone();let network=network.to_owned();
            if let Err(e)=std::thread::Builder::new().name("shared-discovery".into()).spawn(move||{
                let result=run_scan(&parameters,|value|{if scope()?!=network{return Err(io::Error::other("網路已變更，請重新搜尋"));}publish(&worker,value);Ok(())});
                if let Err(e)=result{let mut value=worker.state.lock().unwrap().value.clone().unwrap_or(json!({"endpoints":[]}));value["running"]=json!(false);value["error"]=json!(e.to_string());publish(&worker,value);}
            }){s.running=false;s.finished=None;s.value=None;return Err(e);}
        }
        drop(s);job
    };
    let mut version=0;
    loop{
        let mut s=job.state.lock().unwrap();
        while s.version==version{s=job.wake.wait(s).unwrap();}
        version=s.version;let value=s.value.clone().ok_or_else(||io::Error::other("搜尋未啟動"))?;let done=!s.running;drop(s);
        writeln!(socket,"{value}")?;if done{return Ok(());}
    }
}
pub fn command(args:&[String])->i32 {
    let run=||->io::Result<()>{
        if args.len()!=1||args[0]!=scope()?{return Err(io::Error::other("搜尋服務範圍無效"));}
        let listener=match UnixListener::bind_addr(&address(&args[0])?){Ok(l)=>l,Err(e) if e.kind()==io::ErrorKind::AddrInUse=>return Ok(()),Err(e)=>return Err(e)};
        unsafe{setsid();}listener.set_nonblocking(true)?;
        let jobs=Arc::new(Mutex::new(BTreeMap::new()));let clients=Arc::new(std::sync::atomic::AtomicUsize::new(0));
        loop{
            let mut fd=[PollFd{fd:listener.as_raw_fd(),events:POLLIN,revents:0}];let rc=unsafe{poll(fd.as_mut_ptr(),1,45000)};
            if rc<0{if io::Error::last_os_error().kind()==io::ErrorKind::Interrupted{continue;}return Err(io::Error::last_os_error());}
            if rc==0&&clients.load(Ordering::Acquire)==0{return Ok(());}
            loop{match listener.accept(){
                Ok((socket,_))=>{
                    if clients.load(Ordering::Acquire)>=16{drop(socket);continue;}
                    clients.fetch_add(1,Ordering::AcqRel);let clients=clients.clone();let jobs=jobs.clone();let key=args[0].clone();
                    std::thread::spawn(move||{let _=serve(socket,&jobs,&key);clients.fetch_sub(1,Ordering::AcqRel);});
                },Err(e) if e.kind()==io::ErrorKind::WouldBlock=>break,Err(e)=>return Err(e)
            }}
        }
    };match run(){Ok(())=>0,Err(e)=>{eprintln!("discovery broker: {e}");1}}
}
pub(super) fn normalize(parameters:&[String])->io::Result<Vec<String>> {
    if parameters.is_empty(){return Ok(Vec::new());}
    if parameters.len()!=3||parameters.iter().any(|s|s.len()>1024||s.chars().any(char::is_control)){return Err(io::Error::other("進階搜尋參數無效"));}
    let subnet=parameters[0].trim().to_owned();
    if subnet!="auto"&& !subnet.chars().all(|c|c.is_ascii_digit()||matches!(c,'.'|'/')){return Err(io::Error::other("網段須為內網 IPv4/CIDR"));}
    let mut ports=parameters[1].split(',').map(|p|p.trim().parse::<u16>().ok().filter(|p|*p>0).ok_or_else(||io::Error::other("連接埠無效"))).collect::<io::Result<Vec<_>>>()?;ports.sort();ports.dedup();
    let mut paths=parameters[2].split(',').map(str::trim).collect::<Vec<_>>();if paths.iter().any(|p|!p.starts_with('/')){return Err(io::Error::other("WebDAV 路徑須以 / 開頭"));}paths.sort();paths.dedup();
    Ok(vec![subnet,ports.iter().map(u16::to_string).collect::<Vec<_>>().join(","),paths.join(",")])
}
#[cfg(test)] mod tests {
    use super::*;
    #[test] fn subscribers_share_job_and_disconnect_independently(){
        let job=Arc::new(Job::default());job.state.lock().unwrap().generation=7;
        publish(&job,json!({"running":true,"endpoints":[]}));
        let jobs=Arc::new(Mutex::new(BTreeMap::from([(Vec::new(),job.clone())])));
        let mut clients=Vec::new();let mut workers=Vec::new();
        for _ in 0..2 {
            let(mut client,server)=UnixStream::pair().unwrap();client.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
            let shared=jobs.clone();let network=scope().unwrap();workers.push(std::thread::spawn(move||serve(server,&shared,&network)));
            writeln!(client,"{}",json!({"parameters":[],"fresh":true})).unwrap();
            let mut reader=BufReader::new(client);let mut line=String::new();reader.read_line(&mut line).unwrap();
            assert_eq!(serde_json::from_str::<Value>(&line).unwrap()["generation"],7);clients.push(reader);
        }
        drop(clients.remove(0));
        publish(&job,json!({"running":false,"endpoints":[{"url":"fixture"}]}));
        let mut line=String::new();clients[0].read_line(&mut line).unwrap();
        assert_eq!(serde_json::from_str::<Value>(&line).unwrap()["endpoints"][0]["url"],"fixture");
        for worker in workers {let _=worker.join().unwrap();}
        assert!(Arc::ptr_eq(jobs.lock().unwrap().get(&Vec::new()).unwrap(),&job));
        // A later non-refresh reader receives the completed cached generation.
        let(mut client,server)=UnixStream::pair().unwrap();client.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
        let shared=jobs.clone();let network=scope().unwrap();let worker=std::thread::spawn(move||serve(server,&shared,&network));
        writeln!(client,"{}",json!({"parameters":[],"fresh":false})).unwrap();
        let mut line=String::new();BufReader::new(client).read_line(&mut line).unwrap();
        let value:Value=serde_json::from_str(&line).unwrap();assert_eq!(value["generation"],7);assert_eq!(value["running"],false);
        worker.join().unwrap().unwrap();
    }
    #[test] fn refresh_joins_running_and_cache_expires(){let mut s=State::default();assert!(needs_start(&s,false));s.running=true;assert!(!needs_start(&s,true));s.running=false;s.finished=Some(Instant::now());assert!(!needs_start(&s,false));assert!(needs_start(&s,true));s.finished=Some(Instant::now()-CACHE);assert!(needs_start(&s,false));}
    #[test] fn custom_parameters_are_canonical(){assert_eq!(normalize(&["auto".into(),"443,80,443".into(),"/dav/,/".into()]).unwrap(),normalize(&["auto".into(),"80,443".into(),"/,/dav/".into()]).unwrap());assert!(normalize(&["example.com".into(),"80".into(),"/".into()]).is_err());}
}
