//! Common read-only protocol probes, using the existing transport clients.
use std::{fs::{self,File,OpenOptions},io::{self,Read,Write},os::unix::fs::{DirBuilderExt,OpenOptionsExt},path::{Path,PathBuf},process::{Command,Stdio},time::{Duration,Instant}};
use serde_json::{json,Value};
pub(crate) struct Scratch(PathBuf);
impl Scratch {
    pub(crate) fn new()->io::Result<Self>{
        let mut random=[0u8;16];File::open("/dev/urandom")?.read_exact(&mut random)?;
        let path=PathBuf::from("/data/local/tmp").join(format!("sb-discovery-{}",random.iter().map(|b|format!("{b:02x}")).collect::<String>()));
        fs::DirBuilder::new().mode(0o700).create(&path)?;Ok(Self(path))
    }
    pub(crate) fn file(&self,name:&str,text:&str)->io::Result<PathBuf>{
        let path=self.0.join(name);let mut f=OpenOptions::new().write(true).create_new(true).mode(0o600).open(&path)?;f.write_all(text.as_bytes())?;Ok(path)
    }
}
impl Drop for Scratch {fn drop(&mut self){let _=fs::remove_dir_all(&self.0);}}
use super::command_lifecycle::{OwnedChild,wait_events,CancelEvent};
pub(crate) fn execute(command:Command,scratch:&Scratch,input:Option<&str>,cancel:Option<&CancelEvent>)->io::Result<(bool,String)>{execute_for(command,scratch,input,cancel,Duration::from_secs(12))}
fn execute_for(command:Command,scratch:&Scratch,input:Option<&str>,cancel:Option<&CancelEvent>,budget:Duration)->io::Result<(bool,String)>{
    execute_stream(command,scratch,input,cancel,budget,|_|Ok(()))
}
pub(crate) fn execute_stream(mut command:Command,scratch:&Scratch,input:Option<&str>,cancel:Option<&CancelEvent>,budget:Duration,mut publish:impl FnMut(&str)->io::Result<()>)->io::Result<(bool,String)>{
    super::command_lifecycle::parent_guard(&mut command);
    let output=scratch.file("output","")?;
    let file=OpenOptions::new().write(true).open(&output)?;
    command.stdout(file.try_clone()?).stderr(file).stdin(match input {Some(text)=>Stdio::from(File::open(scratch.file("input",text)?)?),None=>Stdio::null()});
    use std::os::fd::{FromRawFd,AsRawFd,OwnedFd};
    use std::os::unix::ffi::OsStrExt;
    let ino=unsafe{speedbackup_native_rs::inotify_init1(speedbackup_native_rs::O_CLOEXEC|speedbackup_native_rs::O_NONBLOCK)};
    if ino<0{return Err(io::Error::last_os_error());}
    let ino=unsafe{OwnedFd::from_raw_fd(ino)};
    let path=std::ffi::CString::new(output.as_os_str().as_bytes())?;
    if unsafe{speedbackup_native_rs::inotify_add_watch(ino.as_raw_fd(),path.as_ptr(),2|8)}<0{return Err(io::Error::last_os_error());}
    let mut events=vec![ino.as_raw_fd()];if let Some(c)=cancel{events.push(c.fd());}
    let mut reader=File::open(&output)?;let mut pending=String::new();
    let mut drain=||->io::Result<()>{
        let mut bytes=Vec::new();(&mut reader).take(131073).read_to_end(&mut bytes)?;
        pending.push_str(&String::from_utf8_lossy(&bytes));
        while let Some(end)=pending.find('\n'){publish(&pending[..end])?;pending.drain(..=end);}
        Ok(())
    };
    let mut child=OwnedChild::spawn(&mut command)?;
    let status=wait_events(&mut child,budget,&events,||{
        let mut buf=[0u8;4096];while unsafe{speedbackup_native_rs::read(ino.as_raw_fd(),buf.as_mut_ptr() as _,buf.len())}>0{}
        if cancel.is_some_and(|c|c.load(std::sync::atomic::Ordering::Acquire)){return Err(io::Error::new(io::ErrorKind::Interrupted,"搜尋已取消"));}
        if fs::metadata(&output)?.len()>131072{return Err(io::Error::other("伺服器回應過大，請手動設定地址"));}
        drain()?;
        Ok(())
    }).map_err(|e|if e.kind()==io::ErrorKind::TimedOut{io::Error::new(e.kind(),"連線逾時，請確認網路及伺服器")}else{e})?;
    drain()?;
    let mut text=String::new();File::open(output)?.take(131073).read_to_string(&mut text)?;
    if text.len()>131072{return Err(io::Error::other("伺服器回應過大，請手動設定地址"));}
    Ok((status.success(),text))
}


pub(crate) fn webdav_code(tools:&Path,scratch:&Scratch,body:&str,cancel:Option<&CancelEvent>)->io::Result<i64>{
    webdav_code_budget(tools,scratch,body,cancel,Duration::from_secs(12))
}
fn webdav_code_budget(tools:&Path,scratch:&Scratch,body:&str,cancel:Option<&CancelEvent>,budget:Duration)->io::Result<i64>{
    let mut cmd=Command::new("/system/bin/app_process");
    cmd.env("CLASSPATH",tools.join("classes.dex")).args(["/system/bin","com.xayah.dex.WebDavUtil","discoveryCheck"]);
    let(ok,text)=execute_for(cmd,scratch,Some(body),cancel,budget.min(Duration::from_secs(12)))?;
    if !ok{return Ok(0);}
    Ok(serde_json::from_str::<Value>(text.trim()).ok().and_then(|v|v["code"].as_i64()).unwrap_or(0))
}
pub(crate) fn smb_command(tools:&Path,scratch:&Scratch,host:&str,port:u16,user:&str,pass:&str,share:&str)->io::Result<Command>{
    let interfaces=if_addrs::get_if_addrs()?.iter().filter_map(|i|match &i.addr{if_addrs::IfAddr::V4(v)=>Some(format!("{}/{}",v.ip,v.netmask)),_=>None}).collect::<Vec<_>>().join(" ");
    let conf=scratch.file("smb.conf",&format!("[global]\nclient min protocol = SMB2_02\nclient max protocol = SMB3\ninterfaces = 127.0.0.1/8 {interfaces}\nbind interfaces only = no\ndisable netbios = yes\nname resolve order = host\n"))?;
    let mut cmd=Command::new(tools.join("smbclient"));cmd.args(["-t","3","-m","SMB3","-p",&port.to_string(),"-s"]).arg(conf);
    if user.is_empty(){cmd.arg("-N");}else{cmd.arg("-A").arg(scratch.file("auth",&format!("username = {user}\npassword = {pass}\n"))?);}
    let host=if host.contains(':'){format!("[{host}]")}else{host.to_owned()};
    if share.is_empty(){cmd.args(["-g","-L",&format!("//{host}")]);}else{cmd.arg(format!("//{host}/{share}")).args(["-c","pwd; exit"]);}
    Ok(cmd)
}
pub(crate) fn smb_failed(ok:bool,text:&str)->bool {
    if !ok{return true;}
    let lower=text.to_ascii_lowercase();
    ["nt_status","tree connect failed","session setup failed","logon_failure","access_denied","bad_network_name","object_name_not_found","object_path_not_found","errbadpath","does not exist","connection refused","unable to connect","no route to host","timed out","timeout","protocol negotiation failed"].iter().any(|s|lower.contains(s))
}
pub fn webdav_reason(code:i64,user:&str,pass:&str)->&'static str {
    match code {401=>if user.is_empty(){"account_missing"}else if pass.is_empty(){"password_missing"}else{"auth_failed"},403=>"access_denied",404=>"path_missing",405|501|422=>"protocol_error",429=>"rate_limited",500..=599=>"server_error",_=>"connection_failed"}
}
fn settings(conf:&Path)->io::Result<std::collections::BTreeMap<String,String>> {Ok(super::web_settings::parse_runtime(&super::runtime_conf::read(conf)?)?.into_iter().map(|f|(f.key,f.value)).collect())}
pub fn probe(conf:&Path,cancel:Option<&CancelEvent>)->Result<(),String>{probe_impl(conf,cancel,true)}
pub(crate) fn probe_saved(conf:&Path,cancel:Option<&CancelEvent>)->Result<(),String>{probe_impl(conf,cancel,false)}
fn probe_impl(conf:&Path,cancel:Option<&CancelEvent>,track:bool)->Result<(),String>{
    let run=||->io::Result<Result<(),String>>{
        let begin=Instant::now();
        let mut map=match settings(conf){Ok(v)=>v,Err(_)=>return Ok(Err("invalid_config".into()))};
        let protocol=map.get("remote_type").cloned().unwrap_or_default();
        if !matches!(protocol.as_str(),"smb"|"webdav"){return Ok(Err("invalid_config".into()));}
        let mut url=map.get(&format!("{protocol}_url")).cloned().unwrap_or_default();
        if track&&map.get("remote_address_mode").is_some_and(|m|m=="auto") {
            let identity=map.get(&format!("remote_{protocol}_identity")).cloned().unwrap_or_default();
            if identity.is_empty(){return Ok(Err("discovery_unconfigured".into()));}
            if protocol=="webdav"&&!super::applist_web::lan_discovery::valid_webdav_identity(&identity,&url){return Ok(Err("discovery_unconfigured".into()));}
            if protocol=="webdav" {match probe_saved(conf,cancel){
                Ok(())=>return Ok(Ok(())),
                Err(reason) if !matches!(reason.as_str(),"connection_failed"|"timeout")=>return Ok(Err(reason)),
                Err(_)=>{}
            }}
            // Run identity tracking in an owned helper so cancellation also bounds discovery.
            let scratch=Scratch::new()?;let mut cmd=Command::new(std::env::current_exe()?);
            cmd.args(["speedscan","remote-resolve",&identity,&url]).arg(conf).arg(&protocol).arg("--search");
            if !execute_for(cmd,&scratch,None,cancel,Duration::from_secs(18))?.0{return Ok(Err("discovery_failed".into()));}
            map=settings(conf)?;url=map.get(&format!("{protocol}_url")).cloned().unwrap_or_default();
        }
        let(host,port)=match super::remote_control::endpoint(&protocol,&url){Ok(v)=>v,Err(_)=>return Ok(Err("invalid_address".into()))};
        let user=map.get(&format!("{protocol}_remote_user")).map(String::as_str).unwrap_or("");
        let pass=map.get(&format!("{protocol}_remote_pass")).map(String::as_str).unwrap_or("");
        if [user,pass].iter().any(|s|s.len()>4096||s.chars().any(char::is_control)){return Ok(Err("invalid_config".into()));}
        let exe=std::env::current_exe()?;let tools=exe.parent().ok_or_else(||io::Error::other("tools"))?;
        if protocol=="webdav" {
            loop {
                let remaining=Duration::from_secs(if track{44}else{12}).saturating_sub(begin.elapsed());
                if remaining.is_zero(){return Ok(Err("timeout".into()));}
                let scratch=Scratch::new()?;
                let body=json!({"url":url,"user":user,"password":pass}).to_string();
                let code=webdav_code_budget(tools,&scratch,&body,cancel,remaining)?;
                if code==207{return Ok(Ok(()));}
                if code==404 {
                    let base=url.trim_end_matches('/');let rest=base.split_once("://").map(|v|v.1).unwrap_or("");
                    if rest.contains('/') {url=base.rsplit_once('/').unwrap().0.to_owned();continue;}
                }
                return Ok(Err(webdav_reason(code,user,pass).into()));
            }
        }
        let path=url.split_once("://").and_then(|(_,r)|r.split_once('/')).map(|(_,p)|p).unwrap_or("");
        let share=path.split('/').next().unwrap_or("");
        if share.is_empty(){return Ok(Err("share_required".into()));}
        if matches!(share,"."|"..")||share.chars().any(char::is_control)||share.contains(['\\','?','#']){return Ok(Err("invalid_address".into()));}
        let scratch=Scratch::new()?;
        let cmd=smb_command(tools,&scratch,&host,port,user,pass,share)?;
        let(ok,text)=execute(cmd,&scratch,None,cancel)?;
        if !smb_failed(ok,&text){return Ok(Ok(()));}
        let reason=super::remote_control::smb_reason(&text);
        Ok(Err(if reason=="auth_failed"{webdav_reason(401,user,pass)}else{reason}.into()))
    };
    match run(){Ok(result)=>result,Err(e)=>Err(match e.kind(){io::ErrorKind::TimedOut=>"timeout",io::ErrorKind::Interrupted=>"cancelled",_=>"local_error"}.into())}
}
pub fn command(args:&[String])->i32{
    if args.len()!=1{return 2;}
    match probe(Path::new(&args[0]),None){Ok(())=>{println!("ready");0},Err(reason)=>{let(a,b,c)=super::remote_control::smb_reason_class(&reason);println!("{reason}\n{a}\n{b}\n{c}");1}}
}
#[cfg(test)] mod tests {use super::*;#[test]fn auth_reasons(){assert_eq!(webdav_reason(401,"",""),"account_missing");assert_eq!(webdav_reason(401,"u",""),"password_missing");assert_eq!(webdav_reason(401,"u","p"),"auth_failed");assert_eq!(webdav_reason(403,"u","p"),"access_denied");assert_eq!(webdav_reason(503,"u","p"),"server_error");}}
