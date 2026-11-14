//! One-shot selection transport. HTTP can select only a trusted manifest ID;
//! execution stays in the caller's original Shell dispatch table.
use super::*;

struct Menu { health: bool, health_local: bool, remote: BTreeMap<String,String>, preparing: bool, title: String, description: String, choices: BTreeMap<String,String>, info: Vec<(String,String,String)>, multi: bool, input: bool, config: Option<PathBuf>, settings: BTreeSet<String>, foreground: BTreeSet<String>, groups: BTreeMap<String,String>, page: String, resume: String, confirm: bool, power: bool, skip_after: bool }
impl Menu {
    fn parse(text: &str) -> io::Result<Self> {
        if text.len() > 128 * 1024 { return Err(err("menu limit")); }
        let mut lines=text.lines();
        let title=lines.next().filter(|s| !s.is_empty() && s.len()<1024).ok_or_else(||err("menu title"))?.to_string();
        let mut menu=Self {health:false,health_local:false,remote:BTreeMap::new(),preparing:false,title,description:String::new(),choices:BTreeMap::new(),info:Vec::new(),multi:false,input:false,config:None,settings:BTreeSet::new(),foreground:BTreeSet::new(),groups:BTreeMap::new(),page:"actions".into(),resume:String::new(),confirm:false,power:false,skip_after:false};
        for line in lines {
            if let Some(row)=line.strip_prefix("INFOID\t") {
                let parts:Vec<_>=row.splitn(3,'\t').collect();
                if parts.len()!=3 || parts.iter().any(|v|v.is_empty()) || !parts[0].bytes().all(|b|b.is_ascii_lowercase()||b==b'-'){return Err(err("info identity"));}
                // Unicode line separators keep multiline details inside one manifest record.
                menu.info.push((parts[0].into(),parts[1].into(),parts[2].replace('\u{2028}',"\n")));continue;
            }
            let fields:Vec<_>=line.splitn(3,'\t').collect();
            if fields.len()!=3 || fields[1].is_empty() || fields[2].is_empty() { return Err(err("menu row")); }
            match fields[0] {
                "HEALTH" if fields[1]=="mode" && matches!(fields[2],"backup"|"restore") => {menu.health=true;menu.health_local=fields[2]=="restore";},
                "REMOTE" if matches!(fields[2],"only"|"backup"|"setup") => {menu.remote.insert(fields[1].into(),fields[2].into());},
                "CHOICE" if (fields[1].len()<=4 && fields[1].bytes().all(|c|c.is_ascii_digit())) => {
                    if menu.choices.insert(fields[1].into(),fields[2].into()).is_some() {return Err(err("duplicate menu id"));}
                }
                "GROUP" if fields[2].len()<=80 => { if menu.groups.insert(fields[1].into(),fields[2].into()).is_some(){return Err(err("duplicate group"));} }
                "VIEW" if fields[1]=="page" && matches!(fields[2],"home"|"actions"|"settings") => menu.page=fields[2].into(),
                "VIEW" if fields[1]=="resume" && fields[2].bytes().all(|b|b.is_ascii_digit()) => menu.resume=fields[2].into(),
                "MODE" if fields[1]=="power-countdown" && fields[2]=="30" && !menu.power => menu.power=true,
                "MODE" if fields[1]=="skip-after" && fields[2]=="30" => menu.skip_after=true,
                "MODE" if fields[1]=="confirm" && fields[2]=="1" => menu.confirm=true,
                "SETTING" if fields[2]=="1" => { if !menu.settings.insert(fields[1].into()){return Err(err("duplicate setting id"));} }
                "UI" if fields[2]=="1" => { if !menu.foreground.insert(fields[1].into()){return Err(err("duplicate UI id"));} }
                "MODE" if fields[1]=="preparing" && fields[2]=="1" => menu.preparing=true,
                "MODE" if fields[1]=="input" && fields[2]=="1" && !menu.input => menu.input=true,
                "MODE" if fields[1]=="multi" && fields[2]=="1" && !menu.multi => menu.multi=true,
                "CONFIG" if matches!(fields[1],"backup"|"restore") && menu.config.is_none() => {
                    let p=PathBuf::from(fields[2]);let name=if fields[1]=="backup"{"backup_settings.conf"}else{"restore_settings.conf"};
                    if !p.is_absolute()||p.file_name().and_then(|v|v.to_str())!=Some(name){return Err(err("menu config path"));}menu.config=Some(p);
                }
                "DESCRIPTION" if fields[1]=="detail" && fields[2].len()<=4096 && menu.description.is_empty() => menu.description=fields[2].into(),
                "INFO" => menu.info.push((String::new(),fields[1].into(),fields[2].into())),
                _=>return Err(err("menu record")),
            }
        }
        if (menu.multi && menu.input) || menu.choices.is_empty() || menu.choices.len()>1000 || menu.info.len()>80 {return Err(err("menu count"));}
        if menu.preparing&&(menu.multi||menu.input||menu.power||menu.confirm||menu.skip_after||menu.config.is_some()||!menu.info.is_empty()||menu.choices.len()!=1||!menu.choices.contains_key("0")){return Err(err("preparation manifest"));}
        if menu.remote.keys().any(|id|!menu.choices.contains_key(id)){return Err(err("invalid remote id"));}
        if menu.settings.iter().any(|id|!menu.choices.contains_key(id)){return Err(err("invalid setting id"));}
        if menu.foreground.iter().any(|id| !menu.choices.contains_key(id)) {return Err(err("invalid UI id"));}
        if menu.groups.keys().any(|id| !menu.choices.contains_key(id)) {return Err(err("invalid group id"));}
        if menu.power && (menu.multi || menu.input || menu.confirm || menu.config.is_some() || !menu.info.is_empty() || !menu.foreground.is_empty() || !menu.groups.is_empty() || menu.choices.len()!=2 || !menu.choices.contains_key("0") || !menu.choices.contains_key("1")) {return Err(err("power countdown manifest"));}
        if menu.skip_after && (menu.power || menu.multi || menu.input || !menu.choices.contains_key("0")) {return Err(err("skip timeout manifest"));}
        // Compatibility for callers predating the explicit setup marker.
        for (id,label) in &menu.choices {
            if menu.health&&menu.foreground.contains(id)&&matches!(label.as_str(),"測試遠端連線"|"测试远端连接")&&menu.remote.get(id).is_some_and(|v|v=="only") {
                menu.remote.insert(id.clone(),"setup".into());
            }
        }
        Ok(menu)
    }
    fn selection(&self, value: &str) -> Option<String> {
        if !self.multi {return self.choices.contains_key(value).then(||value.to_string());}
        if value=="0" {return self.choices.contains_key(value).then(||value.to_string());}
        let mut selected=BTreeSet::new();
        for id in value.split(' ') {
            if id=="0" || !self.choices.contains_key(id) || !selected.insert(id) {return None;}
        }
        (!selected.is_empty()).then(||selected.into_iter().collect::<Vec<_>>().join(" "))
    }
    fn health_state(&self)->serde_json::Value {
        if self.health_local{return serde_json::json!({"protocol":"local","status":"local"});}
        match (self.config.as_ref(),std::env::var("SPEEDBACKUP_REMOTE_HEALTH_DIR")) {
            (Some(conf),Ok(dir))=>super::super::remote_health::snapshot(conf,Path::new(&dir)),
            _=>serde_json::json!({"protocol":"invalid","status":"offline"})
        }
    }
    fn allowed(&self,id:&str)->bool {
        if !self.health{return true;}
        let health=self.health_state();let local=health["protocol"]=="local";
        match self.remote.get(id).map(String::as_str){Some("setup")=>!local,Some("only")=>!local&&health["status"]=="ready",Some("backup")=>local||health["status"]=="ready",_=>true}
    }
    fn json(&self)->String {
        let health=self.health_state();let local=health["protocol"]=="local";
        let choices:Vec<_>=self.choices.iter().map(|(id,label)|serde_json::json!({"id":id,"label":label,"group":self.groups.get(id).map(String::as_str).unwrap_or(""),"setting":self.settings.contains(id),"remote":self.remote.get(id).map(String::as_str).unwrap_or(""),"hidden":self.health&&local&&self.remote.get(id).is_some_and(|v|matches!(v.as_str(),"only"|"setup")),"disabled":!self.allowed(id)})).collect();
        let info:Vec<_>=self.info.iter().map(|(id,key,value)|serde_json::json!({"id":id,"key":key,"value":value})).collect();
        serde_json::json!({"title":self.title,"choices":choices,"info":info,"multi":self.multi,"input":self.input,"confirm":self.confirm,"page":self.page,"resume":self.resume,"powerCountdown":self.power,"description":self.description,"healthEnabled":self.health,"healthLocal":self.health_local,"health":health}).to_string()
    }
}

// Only native elapsed time or an authenticated explicit choice can produce a
// positive receipt. Window close/transport loss/error never imply timeout.
fn power_result(result:&mut File,parent:&Path,meta:&fs::Metadata,task:&mut Option<ReturnTask>,send:bool)->io::Result<i32> {
    let visible=fs::symlink_metadata(parent)?;
    if (meta.dev(),meta.ino())!=(visible.dev(),visible.ino()){return Err(err("menu directory changed"));}
    if let Some(t)=task.take(){if !t.finish(false,false){return Ok(130);}}
    result.write_all(if send {b"1\n"} else {b"0\n"})?;result.sync_all()?;Ok(0)
}

fn same_menu_file(path:&Path,held:&fs::Metadata)->bool {
    fs::symlink_metadata(path).is_ok_and(|m|
        m.dev()==held.dev() && m.ino()==held.ino() && m.file_type()==held.file_type())
}

fn preparation_completion(state:&str,loaded:bool,elapsed:Duration)->Option<i32>{
    if !matches!(state,"ready"|"failed"){return None;}
    if loaded{return Some(if state=="ready"{0}else{65});}
    (elapsed>=Duration::from_secs(15)).then_some(65)
}
fn serve_menu(args:&[String])->io::Result<i32> {
    if args.len()!=3 || !matches!(args[2].as_str(),"--open"|"--return"|"--test") {return Err(err("menu-web INPUT OUTPUT --open|--return|--test"));}
    let input=Path::new(&args[0]); let output=Path::new(&args[1]);
    if !input.is_absolute() || !output.is_absolute() || input.parent()!=output.parent() {return Err(err("menu paths"));}
    let parent=input.parent().ok_or_else(||err("menu parent"))?;
    let dir=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_DIRECTORY_NATIVE).open(parent)?;
    let meta=dir.metadata()?;
    if meta.uid()!=0 || meta.mode()&0o777!=0o700 || parent.canonicalize()?!=parent {return Err(err("private menu directory required"));}
    let input_meta=fs::symlink_metadata(input)?;
    let menu=Menu::parse(&read(input)?.0)?;
    let mut config=menu.config.as_ref().map(|p|Session::new(p,false)).transpose()?;
    let mut result=OpenOptions::new().write(true).create_new(true).mode(0o600).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(output)?;
    let result_meta=result.metadata()?;
    let _lock=if menu.preparing{None}else{Some(editor_lock()?)};
    let token=random_hex()?;
    let listener=TcpListener::bind("127.0.0.1:0")?;listener.set_nonblocking(true)?;
    let host=listener.local_addr()?.to_string();let origin=format!("http://{host}");let url=format!("{origin}/#{token}");
    let mut _console_page=web_console::Page::register(&url,!menu.power && !menu.skip_after && !menu.preparing && !(menu.page=="settings" && std::env::var("SPEEDBACKUP_LANGUAGE_RETURN").as_deref()==Ok("1")))?;
    let mut task=if _console_page.is_some(){None}else{match args[2].as_str(){"--open"=>ReturnTask::capture(Some(&url)),"--return"=>ReturnTask::capture(None),_=>None}};
    if args[2]=="--open" && task.is_none() && _console_page.is_none() {return Err(err("無法安全啟動原生選單；請檢查啟動日誌後重試"));}
    if _console_page.is_none(){terminal_println!("正在開啟原生選單");}io::stdout().flush()?;
    if menu.preparing {fs::write(parent.join("opened"),b"1")?;}
    unsafe extern "C" {fn getppid()->i32;}
    let owner=unsafe{getppid()};let started=Instant::now();let mut last=started;
    let mut power_started:Option<Instant>=None;let mut power_alive=Instant::now();
    // A shell can outlive its run leader after update/cleanup. Parent PID alone
    // is not proof that this menu still has a valid destination for its result.
    let mut lifetime_check=Instant::now();
    let mut theme:Option<String>=None;let mut native_loaded=false;
    let mut completion_started:Option<Instant>=None;
    let mut health_stream:Option<TcpStream>=None;
    let discovery=lan_discovery::Discovery::default();
    let (tx,rx)=std::sync::mpsc::sync_channel(8);
    let request_wake=RequestWake::new()?;
    let active=std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    loop {
        if menu.preparing {
            if let Ok(state)=fs::read_to_string(parent.join("state")) {
                let elapsed=if matches!(state.as_str(),"ready"|"failed") {
                    completion_started.get_or_insert_with(Instant::now).elapsed()
                } else {Duration::ZERO};
                if let Some(rc)=preparation_completion(&state,native_loaded,elapsed) {
                    if !native_loaded{ui_error("preparation-handoff","native_load_ack_timeout");}
                    if let Some(page)=_console_page.as_mut(){page.return_to_menu();}return Ok(rc);
                }
            }
        }
        if task.as_mut().is_some_and(ReturnTask::externally_closed) {return Ok(130);}
        if lifetime_check.elapsed()>=Duration::from_millis(250) {
            lifetime_check=Instant::now();
            if !same_menu_file(parent,&meta) || !same_menu_file(input,&input_meta) || !same_menu_file(output,&result_meta) {
                // Do not navigate or signal another session. Dropping this menu
                // releases its own flock; Page::drop uses its unique page ID.
                ui_error("menu-lifetime","session_files_changed");return Ok(75);
            }
        }
        if unsafe{getppid()}!=owner || (_console_page.is_none() && (last.elapsed()>Duration::from_secs(900) || started.elapsed()>Duration::from_secs(3600))) {ui_error("menu-lifetime","owner_exit_or_timeout");if let Some(t)=task.take(){t.finish(false,false);}return Ok(75);}
        if menu.skip_after && started.elapsed()>=Duration::from_secs(30){return power_result(&mut result,parent,&meta,&mut task,false);}
        if menu.power {
            if let Some(start)=power_started {
                if power_alive.elapsed()>Duration::from_secs(6){if let Some(t)=task.take(){t.finish(false,false);}return Ok(130);}
                if start.elapsed()>=Duration::from_secs(30){return power_result(&mut result,parent,&meta,&mut task,true);}
            } else if started.elapsed()>Duration::from_secs(60){if let Some(t)=task.take(){t.finish(false,false);}return Ok(130);}
        }
        use std::sync::atomic::Ordering;
        match listener.accept() {
            Ok((mut stream,_))=>if active.load(Ordering::Relaxed)<8 {
                active.fetch_add(1,Ordering::Relaxed);let active=active.clone();let tx=tx.clone();
                let wake=request_wake.writer.clone();
                std::thread::spawn(move||{let req=request(&mut stream);let _=tx.send((stream,req));let _=wake.send(&[1]);active.fetch_sub(1,Ordering::Relaxed);});
            },
            Err(e) if e.kind()==io::ErrorKind::WouldBlock=>{},Err(e)=>return Err(e),
        }
        let (mut stream,req)=match rx.try_recv(){Ok(v)=>v,Err(std::sync::mpsc::TryRecvError::Empty)=>{request_wake.wait(&listener)?;continue;},Err(_)=>return Err(err("menu request channel closed"))};
        let req=match req{Ok(r)=>r,Err(_)=>{let _=respond(&mut stream,"400 Bad Request","text/plain","請求格式錯誤");continue;}};
        if req.headers.get("host")!=Some(&host) || req.headers.get("origin").is_some_and(|o|o!=&origin) || (req.path.starts_with("/api/") && req.headers.get("sec-fetch-site").is_some_and(|s|!matches!(s.as_str(),"same-origin"|"none"))) {
            let _=respond(&mut stream,"403 Forbidden","text/plain","來源不符");continue;
        }
        if req.headers.get("x-speedbackup-token")!=Some(&token) {let _=respond(&mut stream,"403 Forbidden","text/plain","憑證無效");continue;}
    if req.method=="GET" && req.path=="/api/session" && req.body.is_empty() {
        let _=respond(&mut stream,"200 OK","application/json",r#"{"protocol":1,"kind":"menu","native":true}"#);continue;
    }
        // native-open is emitted after NativeMenuPage.load has consumed its APIs.
        // An "opened" file only means listening, not that Android loaded the page.
        if menu.preparing&&req.method=="POST"&&req.path=="/api/diagnostic"&&req.body=="native-open"{native_loaded=true;}
        if appearance_request(&mut stream, &req) { continue; }
        if menu.health&&menu.config.is_some()&&req.path.starts_with("/api/discovery") {
            let result=(||->io::Result<()>{
                if req.method!="POST"{return Err(err("搜尋請求無效"));}
                if req.path=="/api/discovery-stop"{discovery.stop(&req.body);return respond(&mut stream,"200 OK","text/plain","");}
                if req.path=="/api/discovery-target-stop"{discovery.stop_target(&req.body);return respond(&mut stream,"200 OK","text/plain","");}
                // Verification proof and revision guard local commits, even if the LAN changes afterwards.
                if matches!(req.path.as_str(),"/api/discovery"|"/api/discovery-target")&&menu.health_state()["lanAvailable"]!=true{return Err(err("未連接區域網路"));}
                match req.path.as_str(){
                    "/api/discovery"=>discovery.start(stream.try_clone()?,&req.body),
                    "/api/discovery-target"=>discovery.target(stream.try_clone()?,req.body.clone()),
                    "/api/discovery-save"=>{
                        let value=serde_json::from_str(&req.body)?;
                        if !discovery.verified(&value){return Err(err("請先驗證連線，再儲存帳密"));}
                        web_connection::save(menu.config.as_ref().unwrap(),&req.body)?;
                        config=menu.config.as_ref().map(|p|Session::new(p,false)).transpose()?;
                        if let Ok(dir)=std::env::var("SPEEDBACKUP_REMOTE_HEALTH_DIR"){let _=super::super::remote_health::event(Path::new(&dir),"refresh");}
                        respond(&mut stream,"200 OK","text/plain","連線設定已儲存")
                    },
                    _=>Err(err("未知搜尋操作"))
                }
            })();
            if let Err(e)=result{let _=respond(&mut stream,"409 Conflict","text/plain",&e.to_string());}continue;
        }
        if menu.health&&req.path=="/api/connection-revision"&&req.method=="GET"{
            let result=menu.config.as_ref().ok_or_else(||err("缺少設定")).and_then(|p|Session::new(p,false)).and_then(|s|super::super::sha256_reader_hex(s.original.as_bytes()));
            match result{Ok(revision)=>{let _=respond(&mut stream,"200 OK","text/plain",&revision);},Err(e)=>{let _=respond(&mut stream,"409 Conflict","text/plain",&e.to_string());}}continue;
        }
        if req.path=="/api/language" && req.method=="POST" {
            config=menu.config.as_ref().map(|p|Session::new(p,false)).transpose()?;
        }
        if let Some(_ok)=language_request(&mut stream, &req, config.as_mut(), None) {
            continue;
        }
        if menu.health && req.path=="/api/remote-health" && req.method=="GET" {
            if let (Some(conf),Ok(dir))=(menu.config.clone(),std::env::var("SPEEDBACKUP_REMOTE_HEALTH_DIR")) {
                // One subscription per menu; replace old foreground stream.
                if let Some(old)=health_stream.take(){let _=old.shutdown(std::net::Shutdown::Both);}
                health_stream=stream.try_clone().ok();
                std::thread::spawn(move||{let _=super::super::remote_health::stream(stream,conf,PathBuf::from(dir));});continue;
            }
        }
        if menu.health && req.path=="/api/remote-refresh" && req.method=="POST" && req.body.is_empty() {
            if let Ok(dir)=std::env::var("SPEEDBACKUP_REMOTE_HEALTH_DIR"){let _=super::super::remote_health::event(Path::new(&dir),"refresh");}
            let _=respond(&mut stream,"200 OK","application/json",&menu.health_state().to_string());continue;
        }
        match (req.method.as_str(),req.path.as_str()) {
            ("GET","/api/licenses")=>{let _=respond(&mut stream,"200 OK","application/json",include_str!("open_source_licenses.json"));}
            ("POST","/api/countdown") if menu.power && req.body.is_empty()=>{
                if power_started.is_none(){power_started=Some(Instant::now());}power_alive=Instant::now();
                let remaining=30000u128.saturating_sub(power_started.unwrap().elapsed().as_millis());
                let _=respond(&mut stream,"200 OK","application/json",&format!("{{\"remainingMs\":{remaining}}}"));
            }
            ("GET","/api/menu")=>{let mut data=menu.json();data.pop();data.push_str(&format!(",\"preparing\":{},\"skipAfter\":{},\"managed\":{}}}",menu.preparing,menu.skip_after,_console_page.is_some()));let _=respond(&mut stream,"200 OK","application/json",&data);}
            ("GET","/api/theme")=>{
                if theme.is_none(){theme=Some(read_theme().unwrap_or_else(|_| "{}".into()));}
                let _=respond(&mut stream,"200 OK","application/json",theme.as_deref().unwrap());
            }
            ("POST","/api/input") if menu.input && req.headers.get("content-type").is_some_and(|v|v=="text/plain;charset=UTF-8") && req.body.len()<=2048 && !req.body.chars().any(|c|c.is_control())=>{
                let visible=fs::symlink_metadata(parent)?;
                if (meta.dev(),meta.ino())!=(visible.dev(),visible.ino()){return Err(err("menu directory changed"));}
                result.write_all(format!("{}\n",req.body).as_bytes())?;result.sync_all()?;
                let _=respond(&mut stream,"200 OK","text/plain","已確認輸入。");if let Some(t)=task.take(){if !t.finish(true,true){return Ok(130);}}return Ok(0);
            }
            ("POST","/api/choose") if !menu.input && req.headers.get("content-type").is_some_and(|v|v=="text/plain;charset=UTF-8") && menu.selection(&req.body).is_some()=>{
                if !menu.allowed(&req.body){let _=respond(&mut stream,"409 Conflict","text/plain","遠端尚未連線，請檢查設定或點選連線狀態重新驗證。");continue;}
                if menu.preparing {let _=respond(&mut stream,"200 OK","text/plain","已取消");if let Some(page)=_console_page.as_mut(){page.return_to_menu();}return Ok(130);}
                if menu.power {
                    let send=req.body=="1";let _=respond(&mut stream,"200 OK","text/plain",if send {"已確認，正在檢查是否可以送出關機請求。"} else {"已取消本次電腦關機。"});
                    return power_result(&mut result,parent,&meta,&mut task,send);
                }
                if menu.health {if let Ok(dir)=std::env::var("SPEEDBACKUP_REMOTE_HEALTH_DIR"){let _=super::super::remote_health::event(Path::new(&dir),"pause");}}
                let visible=fs::symlink_metadata(parent)?;
                if (meta.dev(),meta.ino())!=(visible.dev(),visible.ino()) {return Err(err("menu directory changed"));}
                // Receipt is created before serving; never accept a path or command from HTTP.
                result.write_all(format!("{}\n",menu.selection(&req.body).unwrap()).as_bytes())?;result.sync_all()?;
                let _=respond(&mut stream,"200 OK","text/plain","已選擇，正在執行。");
                let main_menu=!menu.info.is_empty();
                let leave=main_menu&&matches!(req.body.as_str(),"0");
                let background=!menu.foreground.contains(&req.body);
                if !background {if let Some(page)=_console_page.as_mut(){page.return_to_menu();}}
                // Returning from a submenu is a direct page handoff, not a log review.
                if !main_menu && !menu.skip_after && !menu.confirm && req.body=="0" {
                    if let Some(page)=_console_page.as_mut(){page.return_to_menu();}
                }
                if let Some(t)=task.take(){if !t.finish(!leave,background){return Ok(130);}}
                return Ok(0);
            }
            ("POST","/api/cancel") if req.body.is_empty()=>{if menu.info.is_empty()&&!menu.power&&!menu.skip_after&&!menu.input&&!menu.confirm{if let Some(page)=_console_page.as_mut(){page.return_to_menu();}}let _=respond(&mut stream,"200 OK","text/plain","已離開選單。");if let Some(t)=task.take(){t.finish(!menu.power&&menu.info.is_empty(),!menu.power&&!menu.foreground.contains("0"));}return Ok(130);}
            ("POST","/api/ping") if req.body.is_empty()=>{last=Instant::now();let _=respond(&mut stream,"200 OK","text/plain","OK");}
            _=>{let _=respond(&mut stream,"400 Bad Request","text/plain","無效選項");}
        }
    }
}
pub(super) fn run(args:&[String])->i32 {ui_event("menu-open","begin");match serve_menu(args){Ok(code)=>{ui_event("menu-close",&format!("rc={code}"));code},Err(e)=>{ui_error("open-menu", &e.to_string());65}}}

#[cfg(test)] mod preparation_handoff_tests {
    use super::*;
    #[test] fn local_keeps_backup_and_hides_remote_actions(){
        let menu=Menu::parse("Test\nHEALTH\tmode\trestore\nCHOICE\t1\tBackup\nCHOICE\t2\tUpload\nREMOTE\t1\tbackup\nREMOTE\t2\tonly\n").unwrap();
        assert!(menu.allowed("1"));assert!(!menu.allowed("2"));
        let model:serde_json::Value=serde_json::from_str(&menu.json()).unwrap();
        assert_eq!(model["choices"][0]["hidden"],false);
        assert_eq!(model["choices"][1]["hidden"],true);
    }
    #[test] fn missing_monitor_disables_remote_but_keeps_settings(){
        let menu=Menu::parse("Test\nHEALTH\tmode\tbackup\nCHOICE\t1\tBackup\nCHOICE\t2\tSettings\nREMOTE\t1\tbackup\n").unwrap();
        assert!(!menu.allowed("1"));assert!(menu.allowed("2"));
    }
    #[test] fn legacy_setup_marker_does_not_lock_network_settings() {
        let menu=Menu::parse("Test\nHEALTH\tmode\tbackup\nCHOICE\t5\t測試遠端連線\nREMOTE\t5\tonly\nUI\t5\t1\nCHOICE\t7\t刪除遠端已卸載應用\nREMOTE\t7\tonly\n").unwrap();
        assert!(menu.allowed("5"));assert!(!menu.allowed("7"));
        assert_eq!(menu.remote["5"],"setup");
    }
    #[test] fn disconnected_remote_keeps_setup_route_available(){
        let menu=Menu::parse("Test\nHEALTH\tmode\tbackup\nCHOICE\t1\tBackup\nCHOICE\t2\tNetwork setup\nREMOTE\t1\tbackup\nREMOTE\t2\tsetup\n").unwrap();
        assert!(!menu.allowed("1"));assert!(menu.allowed("2"));
        let local=Menu::parse("Test\nHEALTH\tmode\trestore\nCHOICE\t2\tNetwork setup\nREMOTE\t2\tsetup\n").unwrap();
        assert!(!local.allowed("2"));
    }
    #[test] fn fast_inventory_does_not_close_unloaded_page(){
        assert_eq!(preparation_completion("ready",false,Duration::from_millis(50)),None);
        assert_eq!(preparation_completion("ready",true,Duration::from_millis(80)),Some(0));
        assert_eq!(preparation_completion("failed",false,Duration::from_millis(50)),None);
        assert_eq!(preparation_completion("failed",true,Duration::from_millis(80)),Some(65));
    }
    #[test] fn missing_client_ack_is_bounded_and_not_success(){assert_eq!(preparation_completion("ready",false,Duration::from_secs(15)),Some(65));}
}
