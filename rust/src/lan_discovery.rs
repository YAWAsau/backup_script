//! Bounded DNS-SD discovery owned by the authenticated editor, never by the APK.
#[path = "multicast_guard.rs"]
mod multicast_guard;
#[path = "discovery_target.rs"]
mod discovery_target;
#[path = "discovery_broker.rs"]
pub(crate) mod discovery_broker;
use mdns_sd::{ServiceDaemon, ServiceEvent};
use serde_json::{json, Value};
use std::{collections::BTreeMap, io::{self, Write}, net::{IpAddr,TcpStream},
    sync::{Arc,Mutex,atomic::{AtomicBool,Ordering},mpsc::{self,SyncSender}}, time::{Duration,Instant}};

const TYPES:[&str;3]=["_webdav._tcp.local.","_webdavs._tcp.local.","_smb._tcp.local."];
enum Event { WebDav(Value), Partial, Service(ServiceEvent), Candidate(std::net::Ipv4Addr,Option<String>), Shares(std::net::Ipv4Addr,Option<String>,Vec<String>), Stop }
use super::super::command_lifecycle::CancelEvent;
struct Run { id:String, cancel:CancelEvent, events:SyncSender<Event> }
struct TargetBusy(Arc<AtomicBool>);
impl Drop for TargetBusy {fn drop(&mut self){self.0.store(false,Ordering::Release);}}
#[derive(Default)]
pub struct Discovery { current:Arc<Mutex<Option<Arc<Run>>>>, wake:Arc<std::sync::Condvar>, cancelled:Mutex<std::collections::VecDeque<String>>, resolving:Arc<AtomicBool>, target_cancel:Mutex<Option<(String,Arc<CancelEvent>)>>, verified:Arc<Mutex<Option<(Value,Instant)>>> }
impl Discovery {
    pub fn verified(&self,request:&Value)->bool {
        self.verified.lock().unwrap().as_ref().is_some_and(|(proof,at)|at.elapsed()<Duration::from_secs(60)&&["protocol","url","identity","user","password"].iter().all(|key|proof[*key]==request[*key]))
    }
    pub fn target(&self,mut stream:TcpStream,body:String)->io::Result<()> {
        let request:Value=serde_json::from_str(&body).map_err(|_|io::Error::other("地址資料無效"))?;
        let id=request["requestId"].as_str().unwrap_or("").to_owned();
        if !id.is_empty()&&(id.len()!=32||!id.bytes().all(|b|b.is_ascii_hexdigit())){return Err(io::Error::other("探測識別無效"));}
        let cancelled=self.cancelled.lock().unwrap();
        if !id.is_empty()&&cancelled.contains(&id){return Err(io::Error::other("探測已取消"));}
        if self.resolving.swap(true,Ordering::AcqRel){return Err(io::Error::other("正在讀取地址，請稍候"));}
        let busy=TargetBusy(self.resolving.clone());
        *self.verified.lock().unwrap()=None;
        let verified=self.verified.clone();
        let cancel=Arc::new(CancelEvent::new()?);
        *self.target_cancel.lock().unwrap()=Some((id,cancel.clone()));
        drop(cancelled);
        std::thread::Builder::new().name("discovery-target".into()).spawn(move||{
            let _busy=busy;
            let value=match discovery_target::resolve(&body,Some(&cancel)){Ok(v)=>v,Err(e)=>json!({"error":e.to_string()})};
            if value["verified"]==true&&!cancel.load(Ordering::Acquire){*verified.lock().unwrap()=Some((request,Instant::now()));}
            let _=stream.set_write_timeout(Some(Duration::from_secs(2)));
            let _=super::respond(&mut stream,"200 OK","application/json",&value.to_string());
        })?;
        Ok(())
    }
    pub fn start(&self,mut stream:TcpStream,id:&str)->io::Result<()> {
        let request=if id.starts_with('{'){Some(serde_json::from_str::<Value>(id).map_err(|_|io::Error::other("搜尋請求無效"))?)}else{None};
        let fresh=request.as_ref().is_some_and(|r|r["fresh"]==true);
        let id=request.as_ref().and_then(|r|r["id"].as_str()).unwrap_or(id);
        if id.len()!=32 || !id.bytes().all(|b|b.is_ascii_hexdigit()) {return Err(io::Error::other("搜尋識別碼無效"));}
        let mut slot=self.current.lock().unwrap();
        if self.cancelled.lock().unwrap().iter().any(|v|v==id){return Err(io::Error::other("搜尋已取消"));}
        if let Some(old)=slot.as_ref(){old.cancel.store(true,Ordering::Release);let _=old.events.try_send(Event::Stop);}
        let waited=self.wake.wait_timeout_while(slot,Duration::from_secs(4),|slot|slot.is_some()).unwrap();slot=waited.0;
        if slot.is_some(){return Err(io::Error::other("搜尋仍在結束，請稍後重試"));}
        if self.cancelled.lock().unwrap().iter().any(|v|v==id){return Err(io::Error::other("搜尋已取消"));}
        stream.set_write_timeout(Some(Duration::from_secs(2)))?;
        write!(stream,"HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")?;
        let (tx,rx)=mpsc::sync_channel(64);
        let run=Arc::new(Run{id:id.into(),cancel:CancelEvent::new()?,events:tx});
        *slot=Some(run.clone());
        let current=self.current.clone();let wake=self.wake.clone();
        std::thread::spawn(move||{
            let result=scan(&mut stream,&run,rx,fresh);
            run.cancel.store(true,Ordering::Release);
            if result.is_err(){let _=line(&mut stream,&json!({"running":false,"error":"區域網路搜尋失敗；請確認網路或使用手動輸入。"}));}
            let mut slot=current.lock().unwrap();
            if slot.as_ref().is_some_and(|r|Arc::ptr_eq(r,&run)){*slot=None;wake.notify_all();}
        });
        Ok(())
    }
    pub fn stop_target(&self,id:&str){
        if id.len()!=32||!id.bytes().all(|b|b.is_ascii_hexdigit()){return;}
        let mut cancelled=self.cancelled.lock().unwrap();
        if cancelled.len()>=64{cancelled.pop_front();}cancelled.push_back(id.into());
        if let Some((active,cancel))=self.target_cancel.lock().unwrap().as_ref(){if active==id{cancel.store(true,Ordering::Release);}}
    }
    pub fn stop(&self,id:&str) {
        if id.len()!=32||!id.bytes().all(|b|b.is_ascii_hexdigit()){return;}
        let slot=self.current.lock().unwrap();
        let mut cancelled=self.cancelled.lock().unwrap();
        if cancelled.len()>=64{cancelled.pop_front();}cancelled.push_back(id.into());
        if let Some(run)=slot.as_ref().filter(|r|r.id==id) {
            run.cancel.store(true,Ordering::Release);let _=run.events.try_send(Event::Stop);
        }
    }
}
impl Drop for Discovery {
    fn drop(&mut self){if let Some((_,cancel))=self.target_cancel.lock().unwrap().take(){cancel.store(true,Ordering::Release);}if let Some(run)=self.current.lock().unwrap().as_ref(){run.cancel.store(true,Ordering::Release);let _=run.events.try_send(Event::Stop);}}
}
struct Daemon(ServiceDaemon);
impl Drop for Daemon {fn drop(&mut self){for _ in 0..4 {match self.0.shutdown(){Ok(done)=>{let _=done.recv_timeout(Duration::from_secs(2));break;},Err(_)=>std::thread::sleep(Duration::from_millis(25))}}}}
fn line(stream:&mut TcpStream,value:&Value)->io::Result<()> {let mut bytes=serde_json::to_vec(value)?;bytes.push(b'\n');stream.write_all(&bytes)}
fn snapshot(results:&BTreeMap<String,Vec<Value>>,running:bool)->Value {
    let mut rows=BTreeMap::new();
    for row in results.values().flatten(){if let Some(url)=row["url"].as_str(){if !rows.contains_key(url)||row["identity"].as_str().is_some_and(|s|!s.is_empty()){rows.insert(url,row);}}}
    // SpeedBackup's published root DAV mount and legacy /dav/ mount share storage.
    // Require its stable product identity AND the announced root on this authority;
    // never merge arbitrary DAV paths, ports, schemes, or SMB shares by host alone.
    let roots=rows.values().filter_map(|row|{
        let url=row["url"].as_str()?;let(scheme,host,path)=authority(url).ok()?;
        let id:Value=serde_json::from_str(row["identity"].as_str()?).ok()?;
        if path.is_empty()&&id["scheme"]==scheme&&stable_id(id["product"].as_str(),id["id"].as_str()).is_some(){Some((scheme,host))}else{None}
    }).collect::<Vec<_>>();
    let endpoints=rows.values().filter(|row|{
        let Some(url)=row["url"].as_str() else{return true};
        let Ok((scheme,host,path))=authority(url) else{return true};
        !(row["type"]=="WebDAV"&&matches!(path,"dav"|"dav/")&&row["identity"].as_str().unwrap_or("").is_empty()&&roots.iter().any(|(s,h)|*s==scheme&&same_authority(scheme,h,host)))
    }).take(256).collect::<Vec<_>>();
    json!({"running":running,"endpoints":endpoints})
}
fn scan(stream:&mut TcpStream,run:&Arc<Run>,rx:mpsc::Receiver<Event>,fresh:bool)->io::Result<()> {
    drop(rx);
    discovery_broker::subscribe(&[],fresh,&run.cancel,|value|line(stream,&value))?;
    if run.cancel.load(Ordering::Acquire){line(stream,&json!({"running":false}))?;}
    Ok(())
}
fn run_scan(parameters:&[String],mut emit:impl FnMut(Value)->io::Result<()>)->io::Result<()> {
    let(tx,rx)=mpsc::sync_channel(64);
    let run=Arc::new(Run{id:String::new(),cancel:CancelEvent::new()?,events:tx});
    let result=if parameters.is_empty(){discover(&run,rx,true,true,emit)}else{
        let mut results=BTreeMap::new();
        emit(snapshot(&results,true))?;
        webdav_probe(&run,parameters,Duration::from_secs(32),|row|{
            results.insert(row["url"].as_str().unwrap_or("").to_owned(),vec![row]);emit(snapshot(&results,true))
        }).and_then(|_|emit(snapshot(&results,false)))
    };
    run.cancel.store(true,Ordering::Release);
    result
}
fn discover(run:&Arc<Run>,rx:mpsc::Receiver<Event>,smb:bool,mdns:bool,mut emit:impl FnMut(Value)->io::Result<()>)->io::Result<()> {
    let deadline=Instant::now()+Duration::from_secs(15);
    let mut results=BTreeMap::new();
    emit(snapshot(&results,true))?;
    if run.cancel.load(Ordering::Acquire){return emit(snapshot(&results,false));}
    if smb {start_smb_probe(run,mdns);}
    if smb&&mdns {start_webdav_probe(run);}
    // Acquire before opening sockets; drop daemon before releasing the platform lease.
    let lease = if mdns { Some(multicast_guard::MulticastGuard::acquire()) } else { None };
    let lease_failed = lease.as_ref().is_some_and(|r| r.is_err());
    if lease_failed { eprintln!("Android multicast lease unavailable; discovery may be incomplete"); }
    let daemon=if mdns {match ServiceDaemon::new(){Ok(d)=>Some(Daemon(d)),Err(e)=>{if !smb{return Err(io::Error::other(e));}None}}}else{None};
    let mut partial=lease_failed||(mdns&&daemon.is_none());
    for kind in TYPES {
        if !smb && kind=="_smb._tcp.local." {continue;}
        let Some(daemon)=&daemon else {break};
        let receiver=match daemon.0.browse(kind){Ok(r)=>r,Err(e)=>{if !smb{return Err(io::Error::other(e));}partial=true;continue;}};
        let tx=run.events.clone();
        // The daemon owns these channels and closes them on shutdown. Sending is
        // bounded; dropping rx on every exit also releases a blocked forwarder.
        std::thread::spawn(move||{while let Ok(event)=receiver.recv(){if tx.send(Event::Service(event)).is_err(){break;}}});
    }
    let mut last=String::new();
    while !run.cancel.load(Ordering::Acquire) {
        let Some(remaining)=deadline.checked_duration_since(Instant::now()) else {break};
        match rx.recv_timeout(remaining) {
            Ok(Event::Service(ServiceEvent::ServiceResolved(info)))=>{
                if results.len()>=128&&!results.contains_key(&info.fullname){continue;}
                let protocol=match info.ty_domain.to_ascii_lowercase().as_str(){"_webdav._tcp.local."=>"http","_webdavs._tcp.local."=>"https","_smb._tcp.local."=>"smb",_=>continue};
                let name=if stable_id(info.get_property_val_str("product"),info.get_property_val_str("id")).is_some(){"SpeedBackup Server".to_owned()}else{info.fullname.strip_suffix(&info.ty_domain).unwrap_or(&info.fullname).trim_end_matches('.').chars().filter(|c|!c.is_control()).take(100).collect::<String>()};
                let path=info.get_property_val_str("path").unwrap_or("/");
                let rows=info.addresses.iter().take(16).filter_map(|address|{
                    let ip=address.to_ip_addr();let url=endpoint_url(protocol,ip,info.port,path)?;
                    Some(json!({"name":name,"type":if protocol=="smb"{"SMB"}else{"WebDAV"},"address":ip.to_string(),"url":url,"identity":if protocol=="smb" {String::new()} else {webdav_identity(protocol,&info.fullname,&info.host,info.get_property_val_str("product"),info.get_property_val_str("id"))}}))
                }).collect();
                results.insert(info.fullname,rows);
            }
            Ok(Event::Service(ServiceEvent::ServiceRemoved(_,name)))=>{results.remove(&name);}
            Ok(Event::Candidate(ip,guid))=>{
                if results.len()<128 {if let Some(url)=endpoint_url("smb",IpAddr::V4(ip),445,"/") {
                    results.insert(format!("tcp445:{ip}"),vec![json!({"name":format!("{} · {ip}",if guid.is_some(){"SMB 設備"}else{"SMB 候選"}),"type":"SMB","address":ip.to_string(),"url":url,"candidate":guid.is_none(),"identity":guid.map(|g|format!("smb:{g}")).unwrap_or_default()})]);
                }}
            }
            Ok(Event::Shares(ip,guid,urls))=>{
                let rows=urls.into_iter().map(|url|json!({"name":format!("SMB 設備 · {ip}"),"type":"SMB","address":ip.to_string(),"url":url,"identity":guid.as_ref().map(|g|format!("smb:{g}")).unwrap_or_default()})).collect();
                results.insert(format!("tcp445:{ip}"),rows);
            }
            Ok(Event::WebDav(row))=>{if results.len()<256 {if let Some(url)=row["url"].as_str(){results.insert(format!("webdav-scan:{url}"),vec![row]);}}}
            Ok(Event::Partial)=>{partial=true;},
            Ok(Event::Stop)|Err(_)=>break,
            _=>continue,
        }
        let state=snapshot(&results,true);let encoded=state.to_string();
        if encoded!=last {emit(state)?;last=encoded;}
    }
    let mut final_state=snapshot(&results,false);
    if partial {final_state["error"]=json!("部分搜尋未完成；已保留找到的服務，請重試或手動設定。");}
    emit(final_state)
}
// Anonymous HTTP discovery runs alongside DNS-SD and publishes each result immediately.
fn start_webdav_probe(run:&Arc<Run>){
    let run=run.clone();
    std::thread::spawn(move||{
        let parameters=["auto".into(),"80,443,8080,8081,8000,8443,8765,6065,5005,5006,5244".into(),"/,/dav/,/webdav/".into()];
        if let Err(error)=webdav_probe(&run,&parameters,Duration::from_secs(14),|row|run.events.send(Event::WebDav(row)).map_err(|_|io::Error::new(io::ErrorKind::Interrupted,"搜尋已結束"))){if !run.cancel.load(Ordering::Acquire){eprintln!("WebDAV discovery: {error}");let _=run.events.send(Event::Partial);}}
    });
}
fn webdav_probe(run:&Run,parameters:&[String],timeout:Duration,mut emit:impl FnMut(Value)->io::Result<()>)->io::Result<()> {
            let scratch=super::super::remote_probe::Scratch::new()?;
            let exe=std::env::current_exe()?;
            let mut cmd=std::process::Command::new("/system/bin/app_process");
            cmd.current_dir("/");
            cmd.env("CLASSPATH",exe.with_file_name("classes.dex"))
                .args(["/system/bin","com.xayah.dex.WebDavDiscoveryUtil","scanWebDavStream"])
                .args(parameters).args([if timeout.as_secs()>14{"30000"}else{"12000"},"96","0"]);
            let (_,output)=super::super::remote_probe::execute_stream(cmd,&scratch,None,Some(&run.cancel),timeout,|line|{
                let fields=line.split('\t').collect::<Vec<_>>();
                if fields.len()!=6{return Ok(());}
                let Ok((scheme,host,_))=authority(fields[0]) else{return Ok(());};
                if !matches!(scheme,"http"|"https"){return Ok(());}
                let Some((ip,_))=host.rsplit_once(':') else{return Ok(());};
                let Ok(ip)=ip.parse::<std::net::Ipv4Addr>() else{return Ok(());};
                if !ip.is_private()&&!ip.is_link_local(){return Ok(());}
                let label=match fields[1]{"confirmed"=>"WebDAV 服務","confirmed_auth_required"=>"WebDAV 服務（需要認證）","auth_unconfirmed"=>"WebDAV 候選（需要認證）","tls_unconfirmed"=>"WebDAV 候選（憑證待確認）",_=>return Ok(())};
                emit(json!({"name":format!("{label} · {ip}"),"type":"WebDAV","address":ip.to_string(),"url":fields[0],"identity":"","candidate":!fields[1].starts_with("confirmed"),"diagnostic":fields}))
            })?;
            if !output.lines().any(|line|matches!(line,"SPEEDBACKUP_DISCOVERY_DONE\t0"|"SPEEDBACKUP_DISCOVERY_DONE\t1")){return Err(io::Error::other("WebDAV 搜尋未完成，請重試或手動設定"));}
            Ok(())
}
pub fn discovery_command(args:&[String])->i32 {
    let run=||->io::Result<()>{
        let parameters=discovery_broker::normalize(args)?;
        let cancel=CancelEvent::new()?;
        discovery_broker::subscribe(&parameters,true,&cancel,|state|{
            if state["running"]==false {
                if let Some(error)=state["error"].as_str(){return Err(io::Error::other(error));}
                for row in state["endpoints"].as_array().into_iter().flatten(){
                    if let Some(fields)=row["diagnostic"].as_array(){println!("{}",fields.iter().map(|v|v.as_str().unwrap_or("")).collect::<Vec<_>>().join("\t"));}
                }
            } Ok(())
        })
    };match run(){Ok(())=>0,Err(e)=>{eprintln!("{e}");1}}
}
// Bounded fallback for Windows/NAS without DNS-SD announcements. Only TCP 445
// negotiates SMB2/3 without credentials. Unidentified endpoints remain candidates.
fn start_smb_probe(run:&Arc<Run>,enumerate:bool){
    let mut hosts=std::collections::BTreeSet::new();
    if let Ok(interfaces)=if_addrs::get_if_addrs(){
        for interface in interfaces {
            if interface.is_loopback()||interface.is_p2p||!interface.is_oper_up(){continue;}
            if let if_addrs::IfAddr::V4(v)=interface.addr {
                if !v.ip.is_private(){continue;}
                let own=u32::from(v.ip);let mask=u32::from(v.netmask)|0xffffff00;let network=own&mask;let broadcast=network|!mask;
                for n in network.saturating_add(1)..broadcast {if n!=own&&hosts.len()<512{hosts.insert(std::net::Ipv4Addr::from(n));}}
            }
        }
    }
    // One bounded anonymous enumerator: no saved credentials go to a scan target.
    // Authentication-required hosts remain selectable and resolve on explicit selection.
    let (share_tx,share_rx)=mpsc::sync_channel::<(std::net::Ipv4Addr,Option<String>)>(16);
    let share_run=run.clone();
    if enumerate {std::thread::spawn(move||{
        while !share_run.cancel.load(Ordering::Acquire) {
            let (ip,guid)=match share_rx.recv() {
                Ok(v)=>v,Err(_)=>break,
            };
            let body=json!({"protocol":"smb","url":format!("smb://{ip}:445/"),"user":"","password":""}).to_string();
            if let Ok(result)=discovery_target::resolve(&body,Some(&share_run.cancel)) {
                if let Some(urls)=result["urls"].as_array(){
                    let urls=urls.iter().filter_map(|v|v.as_str().map(str::to_owned)).collect();
                    if share_run.events.send(Event::Shares(ip,guid,urls)).is_err(){break;}
                }
            }
        }
    });}
    let hosts=hosts.into_iter().collect::<Vec<_>>();let run=run.clone();
    std::thread::spawn(move||super::super::tcp_scan::scan(&hosts,&[445],Duration::from_millis(180),32,&run.cancel,|ip,_,stream,_|{
        let guid=smb_guid(stream).ok();
        let _=run.events.send(Event::Candidate(ip,guid.clone()));
        let _=share_tx.try_send((ip,guid));
    }));
}

fn endpoint_url(protocol:&str,ip:IpAddr,port:u16,path:&str)->Option<String>{
    if !matches!(protocol,"smb"|"http"|"https")||port==0||ip.is_unspecified()||ip.is_loopback()||ip.is_multicast(){return None;}
    if matches!(ip,IpAddr::V6(v) if v.is_unicast_link_local())||matches!(ip,IpAddr::V4(v) if v.is_broadcast()){return None;}
    let path=if protocol=="smb"||path.is_empty(){"/"}else{path};
    if path.len()>2048||!path.starts_with('/')||path.starts_with("//")||path.chars().any(|c|c.is_control()||matches!(c,'?'|'#'|'\\')){return None;}
    let mut encoded=String::new();let bytes=path.as_bytes();let mut i=0;
    while i<bytes.len(){let b=bytes[i];if b==b'%' {
        if i+2>=bytes.len(){return None;}let n=u8::from_str_radix(std::str::from_utf8(&bytes[i+1..i+3]).ok()?,16).ok()?;
        if n<32||n==127{return None;}encoded.push_str(std::str::from_utf8(&bytes[i..i+3]).ok()?);i+=3;
    }else{if b.is_ascii_alphanumeric()||b"/-._~!$&'()*+,;=:@".contains(&b){encoded.push(b as char);}else{encoded.push_str(&format!("%{b:02X}"));}i+=1;}}
    let host=match ip {IpAddr::V4(v)=>v.to_string(),IpAddr::V6(v)=>format!("[{v}]")};
    Some(format!("{protocol}://{host}:{port}{encoded}"))
}

// Identity hint only: MS-SMB2 2.2.3/2.2.4. Authentication still belongs to the
// existing SMB client; ServerGuid is NOT a cryptographic server identity.
fn smb_guid(mut stream:TcpStream)->io::Result<String>{
    use std::io::Read;
    stream.set_read_timeout(Some(Duration::from_millis(600)))?;
    stream.set_write_timeout(Some(Duration::from_millis(600)))?;
    let mut random=[0u8;48];std::fs::File::open("/dev/urandom")?.read_exact(&mut random)?;
    let mut packet=vec![0u8;174];
    packet[..4].copy_from_slice(b"\xfeSMB");packet[4]=64;packet[14]=1;
    packet[64]=36;packet[66]=5;packet[68]=1;packet[72]=0x40;
    packet[76..92].copy_from_slice(&random[..16]);
    packet[92..96].copy_from_slice(&112u32.to_le_bytes());packet[96]=2;
    for(i,d)in [0x0202u16,0x0210,0x0300,0x0302,0x0311].iter().enumerate(){packet[100+i*2..102+i*2].copy_from_slice(&d.to_le_bytes());}
    // SHA-512 preauth context, then AES-128-CCM/GCM encryption context.
    packet[112]=1;packet[114]=38;packet[120]=1;packet[122]=32;packet[124]=1;
    packet[126..158].copy_from_slice(&random[16..]);
    packet[160]=2;packet[162]=6;packet[168]=2;packet[170]=1;packet[172]=2;
    let mut frame=(packet.len()as u32).to_be_bytes().to_vec();frame.extend(packet);stream.write_all(&frame)?;
    let deadline=Instant::now()+Duration::from_millis(600);
    let mut header=[0u8;4];read_until(&mut stream,&mut header,deadline)?;
    let size=u32::from_be_bytes(header)as usize;
    if header[0]!=0||!(128..=65536).contains(&size){return Err(io::Error::other("Invalid SMB frame"));}
    let mut body=vec![0u8;size];read_until(&mut stream,&mut body,deadline)?;
    parse_smb_guid(&body)
}
fn read_until(stream:&mut TcpStream,mut out:&mut[u8],deadline:Instant)->io::Result<()>{
    use std::io::Read;
    while !out.is_empty(){stream.set_read_timeout(Some(deadline.checked_duration_since(Instant::now()).filter(|d|!d.is_zero()).ok_or_else(||io::Error::other("SMB deadline"))?))?;
        let n=stream.read(out)?;if n==0{return Err(io::Error::other("Truncated SMB response"));}out=&mut out[n..];}
    Ok(())
}
fn parse_smb_guid(body:&[u8])->io::Result<String>{
    if body.len()<128||&body[..4]!=b"\xfeSMB"||body[4..6]!=64u16.to_le_bytes()||body[8..12]!=[0;4]||body[12..14]!=[0;2]||body[16]&1!=1||body[24..32]!=[0;8]||body[64..66]!=65u16.to_le_bytes()||!matches!(u16::from_le_bytes([body[68],body[69]]),0x0202|0x0210|0x0300|0x0302|0x0311)||body[72..88].iter().all(|b|*b==0){return Err(io::Error::other("Invalid SMB negotiation"));}
    Ok(body[72..88].iter().map(|b|format!("{b:02x}")).collect())
}

fn stable_id(product:Option<&str>,id:Option<&str>)->Option<String>{
    id.filter(|v|product==Some("SpeedBackup")&&(32..=64).contains(&v.len())&&v.bytes().all(|c|c.is_ascii_hexdigit())).map(str::to_ascii_lowercase)
}
fn webdav_identity(scheme:&str,service:&str,hostname:&str,product:Option<&str>,id:Option<&str>)->String{
    if let Some(id)=stable_id(product,id){json!({"product":"SpeedBackup","id":id,"scheme":scheme}).to_string()}
    else {json!({"service":service,"hostname":hostname,"scheme":scheme}).to_string()}
}
fn authority(url:&str)->io::Result<(&str,&str,&str)>{
    let(scheme,rest)=url.split_once("://").ok_or_else(||io::Error::other("地址格式無效"))?;
    let(at,path)=rest.split_once('/').map_or((rest,""),|(a,p)|(a,p));
    if !matches!(scheme,"smb"|"http"|"https")||at.is_empty()||at.contains('@')||url.len()>4096||url.chars().any(|c|c.is_control()||matches!(c,'?'|'#'|'\\')){return Err(io::Error::other("地址格式無效"));}
    Ok((scheme,at,path))
}
fn same_authority(scheme:&str,a:&str,b:&str)->bool{
    let default=match scheme {"https"=>":443","http"=>":80",_=>":445"};
    a.strip_suffix(default).unwrap_or(a).eq_ignore_ascii_case(b.strip_suffix(default).unwrap_or(b))
}
fn tracked_url(original:&str,candidate:&str)->io::Result<String>{
    let(scheme,old,path)=authority(original)?;let(next,at,_)=authority(candidate)?;
    if scheme!=next{return Err(io::Error::other("追蹤協定不符"));}
    if same_authority(scheme,old,at){return Ok(original.into());}
    Ok(format!("{scheme}://{at}/{path}"))
}
pub fn resolve_command(args:&[String])->i32{
    if !(matches!(args.len(),2|4)||(args.len()==5&&args[4]=="--search")) {eprintln!("remote-resolve requires identity, URL and optional conf/protocol");return 2;}
    let operation=||->io::Result<String>{
        let state=if args.len()>=4{Some(super::Session::new(std::path::Path::new(&args[2]),false)?)}else{None};
        let url=if args.len()==4&&args[3]=="webdav"&&valid_webdav_identity(&args[0],&args[1])&&super::super::remote_probe::probe_saved(std::path::Path::new(&args[2]),None).is_ok(){args[1].clone()}else{resolve(&args[0],&args[1])?};
        if let Some(state)=state {
            let output=super::super::web_settings::tracked_address(&state.original,&args[3],&args[0],&args[1],&url)?;
            state.save_text(&output)?;
        }
        Ok(url)
    };
    match operation(){Ok(url)=>{println!("{url}");0},Err(e)=>{eprintln!("{}{}{}", super::terminal_text("自動追蹤失敗："),e,super::terminal_text("；請重新搜尋並選定設備，或切換手動地址。"));1}}
}
fn identity_matches(candidate:&str,original:&str,parsed:Option<&Value>)->bool {
    candidate==original || parsed.is_some_and(|expected| serde_json::from_str::<Value>(candidate).is_ok_and(|actual| &actual==expected))
}
pub(crate) fn valid_webdav_identity(identity:&str,url:&str)->bool {
    let Ok((scheme,_,_))=authority(url) else{return false;};
    if identity.len()>1024||!matches!(scheme,"http"|"https"){return false;}
    let Ok(id)=serde_json::from_str::<Value>(identity) else{return false;};
    let stable=stable_id(id["product"].as_str(),id["id"].as_str()).is_some();
    let named=id["service"].as_str().is_some_and(|v|v.ends_with(if scheme=="https"{"._webdavs._tcp.local."}else{"._webdav._tcp.local."}))&&id["hostname"].as_str().is_some_and(|s|!s.is_empty());
    id["scheme"]==scheme&&(stable||named)
}
fn resolve(identity:&str,original:&str)->io::Result<String>{
    let(scheme,at,_)=authority(original)?;
    if identity.len()>1024{return Err(io::Error::other("設備識別無效"));}
    if let Some(guid)=identity.strip_prefix("smb:"){
        if scheme!="smb"||guid.len()!=32||!guid.bytes().all(|b|b.is_ascii_hexdigit()){return Err(io::Error::other("SMB 設備識別無效"));}
        // Fast path only accepts a matching GUID; a recycled IP is not trusted.
        let addr=at.parse::<std::net::SocketAddr>().or_else(|_|format!("{at}:445").parse());
        if let Ok(addr)=addr {if let Ok(stream)=TcpStream::connect_timeout(&addr,Duration::from_millis(180)) {if smb_guid(stream).is_ok_and(|v|v==guid){return Ok(original.into());}}}
    }else{
        if !valid_webdav_identity(identity,original){return Err(io::Error::other("服務識別無效"));}
    }
    let cancel=CancelEvent::new()?;
    let mut found=None;let mut settle=None;
    let parsed_identity=serde_json::from_str::<Value>(identity).ok();
    let result=discovery_broker::subscribe_with_settle(&[],true,&cancel,true,|state|{
        if let Some(rows)=state["endpoints"].as_array(){
            let mut candidates=rows.iter().filter(|r|r["identity"].as_str().is_some_and(|candidate| identity_matches(candidate,identity,parsed_identity.as_ref()))).filter_map(|r|r["url"].as_str()).collect::<Vec<_>>();
            // Briefly merge per-interface announcements before abandoning a saved
            // address; the same server may publish a separate service per NIC.
            let has_previous=candidates.iter().any(|url|authority(url).is_ok_and(|(_,host,_)|same_authority(scheme,host,at)));
            if scheme!="smb"&&!candidates.is_empty()&&!has_previous {
                if settle.is_none(){
                    settle=Some(Instant::now()+Duration::from_millis(1250));
                }
                if state["running"]==true&&settle.is_some_and(|until|Instant::now()<until){return Ok(());}
            }
            candidates.sort_by_key(|url|if authority(url).is_ok_and(|(_,host,_)|same_authority(scheme,host,at)){0}else if url.contains('['){2}else{1});
            for url in candidates {let(_,host,_)=authority(url)?;if let Ok(addr)=host.parse::<std::net::SocketAddr>(){if let Ok(stream)=TcpStream::connect_timeout(&addr,Duration::from_millis(180)){
                if let Some(guid)=identity.strip_prefix("smb:"){if !smb_guid(stream).is_ok_and(|v|v==guid){continue;}}
                found=Some(tracked_url(original,url)?);cancel.store(true,Ordering::Release);break;
            }}}
        }
        Ok(())
    });
    cancel.store(true,Ordering::Release);result?;
    found.ok_or_else(||io::Error::other("未找到原先選定的設備"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    #[test] fn discovery_aliases_require_known_root_identity(){
        let id=webdav_identity("http","instance","host",Some("SpeedBackup"),Some("0123456789abcdef0123456789abcdef"));
        let row=|url:&str,identity:&str|json!({"url":url,"identity":identity,"type":"WebDAV","name":"test"});
        let mut results=BTreeMap::new();
        results.insert("rows".into(),vec![row("http://192.168.1.2/",&id),row("http://192.168.1.2:80/dav/",""),row("http://192.168.1.2/webdav/",""),row("https://192.168.1.2/dav/",""),row("http://192.168.1.2:8080/dav/",""),row("http://192.168.1.3/dav/",""),row("smb://192.168.1.2/Backup","")]);
        let state=snapshot(&results,false);let urls=state["endpoints"].as_array().unwrap().iter().map(|r|r["url"].as_str().unwrap()).collect::<Vec<_>>();
        assert_eq!(urls.len(),6);assert!(!urls.contains(&"http://192.168.1.2:80/dav/"));assert!(urls.contains(&"http://192.168.1.2/webdav/"));
        results.get_mut("rows").unwrap()[0]["identity"]=json!("");
        assert_eq!(snapshot(&results,false)["endpoints"].as_array().unwrap().len(),7);
        results.get_mut("rows").unwrap()[0]["identity"]=json!(id);
        results.get_mut("rows").unwrap()[1]["identity"]=json!("independent-service");
        assert_eq!(snapshot(&results,false)["endpoints"].as_array().unwrap().len(),7);
    }
    #[test] fn verification_proof_cannot_save_another_target_or_expired_credentials(){
        let discovery=Discovery::default();
        let request=json!({"protocol":"webdav","url":"http://192.168.1.2/","identity":"","user":"fixture","password":"test"});
        assert!(!discovery.verified(&request));
        *discovery.verified.lock().unwrap()=Some((request.clone(),Instant::now()));assert!(discovery.verified(&request));
        for key in ["protocol","url","identity","user","password"] {let mut changed=request.clone();changed[key]=json!("different");assert!(!discovery.verified(&changed));}
        *discovery.verified.lock().unwrap()=Some((request.clone(),Instant::now()-Duration::from_secs(61)));assert!(!discovery.verified(&request));
    }
    fn pair()->(TcpStream,TcpStream){let listener=std::net::TcpListener::bind("127.0.0.1:0").unwrap();let client=TcpStream::connect(listener.local_addr().unwrap()).unwrap();let(server,_)=listener.accept().unwrap();client.set_read_timeout(Some(Duration::from_secs(5))).unwrap();(client,server)}
    #[test] fn identity_json_order_is_not_device_identity(){
        let original=r#"{"scheme":"http","product":"SpeedBackup","id":"abcd"}"#;
        let parsed=serde_json::from_str::<Value>(original).unwrap();
        assert!(identity_matches(r#"{"id":"abcd", "product":"SpeedBackup", "scheme":"http"}"#,original,Some(&parsed)));
        assert!(!identity_matches(r#"{"id":"other","product":"SpeedBackup","scheme":"http"}"#,original,Some(&parsed)));
        assert!(!identity_matches(r#"{"id":"abcd","product":"SpeedBackup","scheme":"https"}"#,original,Some(&parsed)));
        assert!(!identity_matches("broken",original,Some(&parsed)));
        assert!(!identity_matches("smb:b","smb:a",None));
        assert!(identity_matches("smb:a","smb:a",None));
    }
    #[test] fn target_cancel_before_request_is_remembered(){
        let discovery=Discovery::default();let id="c".repeat(32);discovery.stop_target(&id);
        let(_,server)=pair();let body=json!({"requestId":id,"protocol":"smb","url":"smb://192.168.0.1/Backup"}).to_string();
        assert!(discovery.target(server,body).is_err());assert!(!discovery.resolving.load(Ordering::Acquire));
    }
    #[test] fn cancellation_before_start_is_remembered(){
        let discovery=Discovery::default();let id="a".repeat(32);discovery.stop(&id);
        let(_,server)=pair();assert!(discovery.start(server,&id).is_err());
    }
    #[test] fn single_scan_cancels_and_releases_slot(){
        let discovery=Discovery::default();let id="b".repeat(32);let(mut client,server)=pair();
        discovery.start(server,&id).unwrap();let(mut second,other)=pair();discovery.start(other,&"c".repeat(32)).unwrap();
        discovery.stop(&"c".repeat(32));let mut body=String::new();client.read_to_string(&mut body).unwrap();
        assert!(body.contains("\"running\":false"),"{body}");
        let mut next=String::new();second.read_to_string(&mut next).unwrap();assert!(next.contains("\"running\":false"));
        assert!(discovery.current.lock().unwrap().is_none());
    }
    #[test] fn cancel_during_restart_wait_prevents_launch(){
        let discovery=Arc::new(Discovery::default());let(tx,_rx)=mpsc::sync_channel(1);
        let old=Arc::new(Run{id:"a".repeat(32),cancel:CancelEvent::new().unwrap(),events:tx});
        *discovery.current.lock().unwrap()=Some(old.clone());
        let(_,server)=pair();let other=discovery.clone();
        let worker=std::thread::spawn(move||other.start(server,&"b".repeat(32)));
        let deadline=Instant::now()+Duration::from_secs(2);
        while !old.cancel.load(Ordering::Acquire){assert!(Instant::now()<deadline);std::thread::sleep(Duration::from_millis(1));}
        discovery.stop(&"b".repeat(32));
        *discovery.current.lock().unwrap()=None;discovery.wake.notify_all();
        assert!(worker.join().unwrap().is_err());
        assert!(discovery.current.lock().unwrap().is_none());
    }
    #[test] fn smb_identity_rejects_truncated_error_and_non_smb(){
        let mut b=vec![0;128];b[..4].copy_from_slice(b"\xfeSMB");b[4]=64;b[16]=1;b[64]=65;b[68]=0x11;b[69]=3;b[72..88].fill(0x23);
        assert_eq!(parse_smb_guid(&b).unwrap(),"23".repeat(16));
        for size in 0..128{assert!(parse_smb_guid(&b[..size]).is_err());}
        let mut invalid=b.clone();invalid[8]=1;assert!(parse_smb_guid(&invalid).is_err());
        invalid=b.clone();invalid[0]=0;assert!(parse_smb_guid(&invalid).is_err());
        invalid=b.clone();invalid[72..88].fill(0);assert!(parse_smb_guid(&invalid).is_err());
    }
    #[test] fn persistent_server_id_survives_service_and_interface_rename(){
        let id="AB".repeat(16);
        assert_eq!(webdav_identity("http","old","old.local.",Some("SpeedBackup"),Some(&id)),webdav_identity("http","new","new.local.",Some("SpeedBackup"),Some(&id.to_lowercase())));
        assert_ne!(webdav_identity("http","one","old.local.",None,None),webdav_identity("http","two","new.local.",None,None));
        for invalid in ["short","!invalid",&"a".repeat(65)]{assert!(stable_id(Some("SpeedBackup"),Some(invalid)).is_none());}
        assert!(stable_id(Some("Other"),Some(&id)).is_none());
    }
    #[test] fn address_change_preserves_path_and_rejects_protocol_change(){
        assert_eq!(tracked_url("smb://192.168.1.8/share/child","smb://192.168.1.9:445/").unwrap(),"smb://192.168.1.9:445/share/child");
        assert_eq!(tracked_url("https://192.168.1.8:443/dav/a%20b","https://192.168.1.9:5006/").unwrap(),"https://192.168.1.9:5006/dav/a%20b");
        assert!(tracked_url("https://192.168.1.8/dav","http://192.168.1.9/").is_err());
        assert!(authority("http://user:secret@host/").is_err());
        for (a,b) in [("http://192.168.1.8/dav","http://192.168.1.8:80/"),("https://[fd12::1]/dav","https://[fd12::1]:443/"),("smb://192.168.1.8/share","smb://192.168.1.8:445/")] {assert_eq!(tracked_url(a,b).unwrap(),a);}
    }
    #[test] fn address_and_path_contract(){
        let ip="192.168.1.2".parse().unwrap();
        assert_eq!(endpoint_url("https",ip,5006,"/中文/a%20b"),Some("https://192.168.1.2:5006/%E4%B8%AD%E6%96%87/a%20b".into()));
        assert_eq!(endpoint_url("smb",ip,445,"/ignored"),Some("smb://192.168.1.2:445/".into()));
        assert_eq!(endpoint_url("http","fd12::1".parse().unwrap(),80,"/"),Some("http://[fd12::1]:80/".into()));
        for path in ["//evil/","http://evil/","/x\n","/x%0D","/%zz","/a?token=x","/x#y","/x\\y"]{assert!(endpoint_url("http",ip,80,path).is_none(),"{path}");}
        for addr in ["0.0.0.0","127.0.0.1","224.0.0.251","255.255.255.255","::1","fe80::1"]{assert!(endpoint_url("http",addr.parse().unwrap(),80,"/").is_none());}
    }
    #[test] #[ignore = "requires a live private LAN interface"]
    fn live_webdav_address_tracking() {
        let ip=if_addrs::get_if_addrs().unwrap().into_iter().find_map(|i|match i.addr{if_addrs::IfAddr::V4(v) if v.ip.is_private()=>Some(v.ip),_=>None}).unwrap();
        let listener=std::net::TcpListener::bind((ip,0)).unwrap();let port=listener.local_addr().unwrap().port();
        let publisher=Daemon(ServiceDaemon::new().unwrap());
        let info=mdns_sd::ServiceInfo::new("_webdav._tcp.local.","SB1105-Device-Test","sb1105-device-test.local.",IpAddr::V4(ip),port,[("path","/published/")].as_slice()).unwrap();
        publisher.0.register(info).unwrap();
        let identity=json!({"service":"SB1105-Device-Test._webdav._tcp.local.","hostname":"sb1105-device-test.local.","scheme":"http"}).to_string();
        let original=format!("http://192.0.2.1:{port}/private/a%20b/");
        let start=Instant::now();let next=resolve(&identity,&original).unwrap();
        assert_eq!(next,format!("http://{ip}:{port}/private/a%20b/"));
        eprintln!("webdav live changed address {:?}",start.elapsed());
        assert_eq!(resolve(&identity,&next).unwrap(),next);
    }

}
