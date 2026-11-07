//! One-shot selection transport. HTTP can select only a trusted manifest ID;
//! execution stays in the caller's original Shell dispatch table.
use super::*;

struct Menu { preparing: bool, title: String, description: String, choices: BTreeMap<String,String>, info: Vec<(String,String)>, multi: bool, input: bool, config: Option<PathBuf>, settings: BTreeSet<String>, foreground: BTreeSet<String>, groups: BTreeMap<String,String>, page: String, resume: String, confirm: bool, power: bool, skip_after: bool }
impl Menu {
    fn parse(text: &str) -> io::Result<Self> {
        if text.len() > 128 * 1024 { return Err(err("menu limit")); }
        let mut lines=text.lines();
        let title=lines.next().filter(|s| !s.is_empty() && s.len()<1024).ok_or_else(||err("menu title"))?.to_string();
        let mut menu=Self {preparing:false,title,description:String::new(),choices:BTreeMap::new(),info:Vec::new(),multi:false,input:false,config:None,settings:BTreeSet::new(),foreground:BTreeSet::new(),groups:BTreeMap::new(),page:"actions".into(),resume:String::new(),confirm:false,power:false,skip_after:false};
        for line in lines {
            let fields:Vec<_>=line.splitn(3,'\t').collect();
            if fields.len()!=3 || fields[1].is_empty() || fields[2].is_empty() { return Err(err("menu row")); }
            match fields[0] {
                "CHOICE" if (fields[1].len()<=4 && fields[1].bytes().all(|c|c.is_ascii_digit())) => {
                    if menu.choices.insert(fields[1].into(),fields[2].into()).is_some() {return Err(err("duplicate menu id"));}
                }
                "GROUP" if fields[2].len()<=80 => { if menu.groups.insert(fields[1].into(),fields[2].into()).is_some(){return Err(err("duplicate group"));} }
                "VIEW" if fields[1]=="page" && matches!(fields[2],"home"|"actions") => menu.page=fields[2].into(),
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
                "INFO" => menu.info.push((fields[1].into(),fields[2].into())),
                _=>return Err(err("menu record")),
            }
        }
        if (menu.multi && menu.input) || menu.choices.is_empty() || menu.choices.len()>1000 || menu.info.len()>80 {return Err(err("menu count"));}
        if menu.preparing&&(menu.multi||menu.input||menu.power||menu.confirm||menu.skip_after||menu.config.is_some()||!menu.info.is_empty()||menu.choices.len()!=1||!menu.choices.contains_key("0")){return Err(err("preparation manifest"));}
        if menu.settings.iter().any(|id|!menu.choices.contains_key(id)){return Err(err("invalid setting id"));}
        if menu.foreground.iter().any(|id| !menu.choices.contains_key(id)) {return Err(err("invalid UI id"));}
        if menu.groups.keys().any(|id| !menu.choices.contains_key(id)) {return Err(err("invalid group id"));}
        if menu.power && (menu.multi || menu.input || menu.confirm || menu.config.is_some() || !menu.info.is_empty() || !menu.foreground.is_empty() || !menu.groups.is_empty() || menu.choices.len()!=2 || !menu.choices.contains_key("0") || !menu.choices.contains_key("1")) {return Err(err("power countdown manifest"));}
        if menu.skip_after && (menu.power || menu.multi || menu.input || !menu.choices.contains_key("0")) {return Err(err("skip timeout manifest"));}
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
    fn json(&self)->String {
        let choices=self.choices.iter().map(|(id,label)|format!("{{\"id\":{},\"label\":{},\"group\":{},\"setting\":{}}}",json(id),json(label),json(self.groups.get(id).map(String::as_str).unwrap_or("")),self.settings.contains(id))).collect::<Vec<_>>().join(",");
        let info=self.info.iter().map(|(key,value)|format!("{{\"key\":{},\"value\":{}}}",json(key),json(value))).collect::<Vec<_>>().join(",");
        format!("{{\"title\":{},\"choices\":[{}],\"info\":[{}],\"multi\":{},\"input\":{},\"confirm\":{},\"page\":{},\"resume\":{},\"powerCountdown\":{}}}",json(&self.title),choices,info,self.multi,self.input,self.confirm,json(&self.page),json(&self.resume),self.power).trim_end_matches('}').to_string()+&format!(",\"description\":{}}}",json(&self.description))
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
    let mut _console_page=web_console::Page::register(&url,!menu.power && !menu.skip_after && !menu.preparing)?;
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
    let mut theme:Option<String>=None;
    let (tx,rx)=std::sync::mpsc::sync_channel(8);
    let active=std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    loop {
        if menu.preparing {
            match fs::read_to_string(parent.join("state")) {
                Ok(state) if state=="ready" => {if let Some(page)=_console_page.as_mut(){page.return_to_menu();}return Ok(0);},
                Ok(state) if state=="failed" => {if let Some(page)=_console_page.as_mut(){page.return_to_menu();}return Ok(65);},
                _=>{}
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
                std::thread::spawn(move||{let req=request(&mut stream);let _=tx.send((stream,req));active.fetch_sub(1,Ordering::Relaxed);});
            },
            Err(e) if e.kind()==io::ErrorKind::WouldBlock=>{},Err(e)=>return Err(e),
        }
        let (mut stream,req)=match rx.recv_timeout(Duration::from_millis(10)){Ok(v)=>v,Err(_)=>continue};
        let req=match req{Ok(r)=>r,Err(_)=>{let _=respond(&mut stream,"400 Bad Request","text/plain","請求格式錯誤");continue;}};
        if req.headers.get("host")!=Some(&host) || req.headers.get("origin").is_some_and(|o|o!=&origin) || (req.path.starts_with("/api/") && req.headers.get("sec-fetch-site").is_some_and(|s|!matches!(s.as_str(),"same-origin"|"none"))) {
            let _=respond(&mut stream,"403 Forbidden","text/plain","來源不符");continue;
        }
        if req.headers.get("x-speedbackup-token")!=Some(&token) {let _=respond(&mut stream,"403 Forbidden","text/plain","憑證無效");continue;}
    if req.method=="GET" && req.path=="/api/session" && req.body.is_empty() {
        let _=respond(&mut stream,"200 OK","application/json",r#"{"protocol":1,"kind":"menu","native":true}"#);continue;
    }
        if appearance_request(&mut stream, &req) { continue; }
        if language_request(&mut stream, &req, config.as_mut()) { continue; }
        match (req.method.as_str(),req.path.as_str()) {
            ("GET","/api/licenses")=>{let _=respond(&mut stream,"200 OK","application/json",include_str!("open_source_licenses.json"));}
            ("POST","/api/countdown") if menu.power && req.body.is_empty()=>{
                if power_started.is_none(){power_started=Some(Instant::now());}power_alive=Instant::now();
                let remaining=30000u128.saturating_sub(power_started.unwrap().elapsed().as_millis());
                let _=respond(&mut stream,"200 OK","application/json",&format!("{{\"remainingMs\":{remaining}}}"));
            }
            ("GET","/api/menu")=>{let mut data=menu.json();data.pop();data.push_str(&format!(",\"preparing\":{}}}",menu.preparing));let _=respond(&mut stream,"200 OK","application/json",&data);}
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
                if menu.preparing {let _=respond(&mut stream,"200 OK","text/plain","已取消");if let Some(page)=_console_page.as_mut(){page.return_to_menu();}return Ok(130);}
                if menu.power {
                    let send=req.body=="1";let _=respond(&mut stream,"200 OK","text/plain",if send {"已確認，正在檢查是否可以送出關機請求。"} else {"已取消本次電腦關機。"});
                    return power_result(&mut result,parent,&meta,&mut task,send);
                }
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
