//! Bounded, best-effort Android crash evidence. Never clears system buffers.
use std::{collections::{BTreeMap},fs::{self,OpenOptions},io::{self,Read},os::unix::fs::{OpenOptionsExt,MetadataExt},path::Path,process::{Command,Stdio},sync::mpsc,time::{Duration,SystemTime,Instant}};
const LIMIT:u64=262144;
fn related(text:&str)->bool {
    text.lines().any(|line|["Cmdline:","Cmd line:","Process:",">>>","ANR in "].iter().any(|marker|{
        let Some((_,value))=line.split_once(marker) else{return false;};
        let token=value.trim().split(|c:char|c.is_whitespace()||c==','||c=='<').next().unwrap_or("");
        token=="io.github.yawasau.speedbackup.webview"||token.starts_with("io.github.yawasau.speedbackup.webview:")||token.starts_with("com.xayah.dex.")||matches!(token.rsplit('/').next(),Some("speednative"|"speedscan"))
    }))
}
pub(crate) fn redact(text:&str)->String {text.lines().map(|line|{if line.contains("http://127.0.0.1:"){line.split_whitespace().map(|w|if w.contains("http://127.0.0.1:"){"[local-ui-url]"}else{w}).collect::<Vec<_>>().join(" ")}else{line.into()}}).collect::<Vec<_>>().join("\n")+"\n"}
fn pid_record(text:&str,pid:Option<u32>)->bool {
    pid.is_some_and(|pid|["pid: ","PID: "].iter().any(|prefix|text.match_indices(prefix).any(|(i,_)|text[i+prefix.len()..].chars().take_while(char::is_ascii_digit).collect::<String>().parse::<u32>().ok()==Some(pid))))
}
#[cfg(test)]
fn crash_groups(text:&str,pid:Option<u32>)->String {crash_groups_many(text,&pid.into_iter().collect::<Vec<_>>())}
fn crash_groups_many(text:&str,pids:&[u32])->String {
    // Separate events even when debuggerd/system_server reuses the same reporting PID.
    let mut groups=Vec::<Vec<(usize,&str)>>::new();let mut current=BTreeMap::<String,usize>::new();
    for (index,line) in text.lines().enumerate() {
        let f=line.split_whitespace().collect::<Vec<_>>();if f.len()<6||f[2].parse::<u32>().is_err()||f[3].parse::<u32>().is_err(){continue;}
        let tag=f[5].trim_end_matches(':');if tag!="AndroidRuntime"&&!tag.starts_with("DEBUG")&&tag!="ActivityManager"&&tag!="SpeedBackupNative"{continue;}
        let key=format!("{}:{}:{tag}",f[2],f[3]);
        if tag=="ActivityManager" {
            // Keep the ANR identity/reason, not unrelated later system_server errors.
            let message=line.split_once("ActivityManager").map(|(_,v)|v.trim_start_matches(':').trim()).unwrap_or("");
            if !["ANR in ","PID:","Reason:","Parent:","ErrorId:","Frozen:","Load:"].iter().any(|p|message.starts_with(p)) {
                current.remove(&key);continue;
            }
        }
        let identity_boundary=current.get(&key).is_some_and(|&g|["Cmdline:","Process:","pid: "].iter().any(|marker|line.contains(marker)&&groups[g].iter().any(|(_,old)|old.contains(marker))));
        let starts=identity_boundary||line.contains("*** *** ***")||line.contains("FATAL EXCEPTION:")||line.contains("ANR in ");
        if starts||!current.contains_key(&key){current.insert(key.clone(),groups.len());groups.push(Vec::new());}
        groups[*current.get(&key).unwrap()].push((index,line));
    }
    let mut selected=groups.into_iter().filter(|v|{let text=v.iter().map(|(_,l)|*l).collect::<Vec<_>>().join("\n");related(&text)||pids.iter().any(|p|pid_record(&text,Some(*p)))}).flatten().collect::<Vec<_>>();selected.sort_by_key(|(index,_)|*index);
    let selected=selected.into_iter().map(|(_,l)|l).collect::<Vec<_>>().join("\n");
    if selected.is_empty(){String::new()}else{redact(&selected)}
}
fn logcat_command(buffers:&[&str])->Command {
    let mut command=Command::new("/system/bin/logcat");
    for buffer in buffers {command.args(["-b",buffer]);}
    command.args(["-d","-v","threadtime","-t","2000","AndroidRuntime:E","DEBUG:F","DEBUG32:F","DEBUG64:F","ActivityManager:E","SpeedBackupNative:V","SpeedBackupGuard:V","*:S"]);
    command
}
fn bounded_logcat()->io::Result<(String,String)> {
    // logd applies the tail across merged buffers before tag filtering. Busy main/system
    // traffic must not push retained crash records outside the crash capture window.
    let mut text=String::new();let mut status=String::new();
    for (name,buffers) in [("crash",&["crash"][..]),("system-main",&["system","main"][..])] {
        match bounded_capture(&mut logcat_command(buffers)) {
            Ok((part,result))=>{text.push_str(&part);text.push('\n');status.push_str(&format!("buffer={name} {result}\n"));},
            Err(e)=>status.push_str(&format!("buffer={name} logcat_unavailable={e}\n")),
        }
    }
    Ok((text,status))
}
fn bounded_capture(command:&mut Command)->io::Result<(String,String)> {
    let mut child=super::command_lifecycle::OwnedChild::spawn(command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()))?;
    let stdout=child.stdout.take().ok_or_else(||io::Error::other("logcat stdout"))?;
    let stderr=child.stderr.take().ok_or_else(||io::Error::other("logcat stderr"))?;
    let(tx,rx)=mpsc::channel();std::thread::spawn(move||{let mut bytes=Vec::new();let result=stdout.take(2*1024*1024).read_to_end(&mut bytes);let _=tx.send((result,bytes));});
    let(etx,erx)=mpsc::channel();std::thread::spawn(move||{let mut bytes=Vec::new();let result=stderr.take(16384).read_to_end(&mut bytes);let _=etx.send((result,bytes));});
    let deadline=Instant::now()+Duration::from_secs(3);
    let (read,bytes)=rx.recv_timeout(Duration::from_secs(3)).map_err(|_|io::Error::new(io::ErrorKind::TimedOut,"logcat stdout timeout; capture incomplete"))?;read?;
    let result=match super::command_lifecycle::wait_checked(&mut child,deadline.saturating_duration_since(Instant::now()),||Ok(())) {
        Ok(exit)=>format!("logcat_exit={exit} inputBytes={} limitBytes=2097152 capped={} empty={} complete={}",bytes.len(),bytes.len()==2*1024*1024,bytes.is_empty(),exit.success()&&bytes.len()<2*1024*1024),
        Err(e) if e.kind()==io::ErrorKind::TimedOut=>format!("logcat_exit_timeout partial=true inputBytes={}",bytes.len()),
        Err(e)=>return Err(e),
    };
    let errors=match erx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
        Ok((Ok(_),bytes))=>format!("stderrBytes={} stderrCapped={} stderr={:?}",bytes.len(),bytes.len()==16384,redact(&String::from_utf8_lossy(&bytes)).trim()),
        Ok((Err(e),_))=>format!("stderr_unavailable={e}"),
        Err(_)=>"stderr_unavailable=timeout".into(),
    };
    Ok((String::from_utf8_lossy(&bytes).into_owned(),format!("{result} {errors}")))
}

fn write(dir:&Path,name:&str,bytes:&[u8])->io::Result<()> {
    let target=dir.join(name);
    super::publish_file::publish_bytes_guarded(bytes,&target,Some(0o600),false,&mut||Ok(())).map(|_|())
}
fn collect_from(dir:&Path,tombs:&Path,log:io::Result<(String,String)>,pids:&[u32])->io::Result<()> {
    let meta=fs::symlink_metadata(dir)?;
    if !meta.is_dir()||meta.uid()!=0||dir.canonicalize()?!=dir{return Err(io::Error::other("invalid crash output directory"));}
    let mut status=format!("collectedEpoch={}\nscope=SpeedBackup Java/native/ANR events in retained logcat windows; related text tombstones from last 24h\nnote=Interleaved ambiguous ANR continuation lines are omitted to avoid unrelated process data; prefer scoped ANR reports.\nlimits=logcat crash and system-main independently, each 2000 records/2MiB/3s; scan 64 tombstones; retain 4 x 256KiB\n",SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap_or_default().as_secs());
    match log {Ok((text,result))=>{let filtered=crash_groups_many(&text,pids);let own=text.lines().filter(|line|{let f=line.split_whitespace().collect::<Vec<_>>();f.len()>=6&&f[2].parse::<u32>().is_ok()&&f[3].parse::<u32>().is_ok()&&matches!(f[5].trim_end_matches(':'),"SpeedBackupNative"|"SpeedBackupGuard")}).collect::<Vec<_>>().join("\n");write(dir,"logcat-speedbackup.log",if own.is_empty(){String::new()}else{redact(&own)}.as_bytes())?;status.push_str(&format!("{result} selectedBytes={}\n",filtered.len()));write(dir,"logcat-crash.log",filtered.as_bytes())?;},Err(e)=>{status.push_str(&format!("logcat_unavailable={e}\n"));}}
    let mut candidates=Vec::new();
    match fs::read_dir(tombs){Ok(entries)=>{for e in entries.take(256).flatten(){let name=e.file_name();let name=name.to_string_lossy();if !name.starts_with("tombstone_")||!name[10..].bytes().all(|b|b.is_ascii_digit()){continue;}
        if let Ok(m)=e.metadata(){if m.is_file()&&m.modified().ok().and_then(|t|SystemTime::now().duration_since(t).ok()).is_some_and(|age|age<=Duration::from_secs(86400)){candidates.push((m.modified().unwrap(),e.path()));}}}},Err(e)=>status.push_str(&format!("tombstones_unavailable={e}\n"))}
    candidates.sort_by(|a,b|b.0.cmp(&a.0));let mut saved=0;let deadline=Instant::now()+Duration::from_secs(2);
    for (modified,path) in candidates.into_iter().take(64) {
        if Instant::now()>=deadline{status.push_str("tombstone_scan_time_limit\n");break;}
        let result=(||{let mut file=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK).open(&path)?;
            if !file.metadata()?.is_file(){return Err(io::Error::other("nonregular tombstone"));}let mut bytes=Vec::new();(&mut file).take(LIMIT).read_to_end(&mut bytes)?;Ok(bytes)})();
        match result {Ok(bytes)=>{let text=String::from_utf8_lossy(&bytes);if !related(&text)&&!(pids.iter().any(|p|pid_record(&text,Some(*p)))&&SystemTime::now().duration_since(modified).is_ok_and(|age|age<=Duration::from_secs(60))){continue;}let name=format!("native-tombstone-{saved}.log");write(dir,&name,redact(&text).as_bytes())?;saved+=1;status.push_str(&format!("saved={name} source={} bytes={} capped={}\n",path.display(),bytes.len(),bytes.len() as u64==LIMIT));if saved==4{break;}},Err(e)=>status.push_str(&format!("tombstone_read_failed={e}\n"))}
    }
    status.push_str(&format!("tombstonesSaved={saved}\n"));
    collect_anr(dir,Path::new("/data/anr"),&mut status);write(dir,"status.log",status.as_bytes())
}
// ANR files can contain multiple processes; retain only identified SpeedBackup sections.
fn anr_sections(text:&str)->String {
    let mut output=String::new();
    for section in text.split("----- pid ").skip(1) {
        let section=section.split("----- end ").next().unwrap_or(section);
        let identity=section.lines().find(|l|l.starts_with("Cmd line:"));
        if identity.is_some_and(|l|related(l)){output.push_str("----- pid ");output.push_str(section);output.push('\n');}
    }
    output
}
fn collect_anr(dir:&Path,source:&Path,status:&mut String) {
    let entries=match fs::read_dir(source){Ok(v)=>v,Err(e)=>{status.push_str(&format!("anr_unavailable={e}\n"));return;}};
    let mut candidates=entries.take(256).flatten().filter_map(|e|{let m=fs::symlink_metadata(e.path()).ok()?;let time=m.modified().ok()?;if !m.is_file()||!SystemTime::now().duration_since(time).is_ok_and(|age|age<=Duration::from_secs(86400)){return None;}Some((time,e.path()))}).collect::<Vec<_>>();
    candidates.sort_by(|a,b|b.0.cmp(&a.0));let mut saved=0;let deadline=Instant::now()+Duration::from_secs(2);
    for (_,path) in candidates.into_iter().take(64) {
        if Instant::now()>=deadline{status.push_str("anr_scan_time_limit\n");break;}
        let result=(||->io::Result<String>{let file=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK).open(path)?;if !file.metadata()?.is_file(){return Err(io::Error::other("nonregular ANR"));}let mut bytes=Vec::new();file.take(LIMIT).read_to_end(&mut bytes)?;Ok(anr_sections(&String::from_utf8_lossy(&bytes)))})();
        match result{Ok(text) if !text.is_empty()=>{let name=format!("anr-{saved}.log");match write(dir,&name,redact(&text).as_bytes()){Ok(())=>{saved+=1;if saved==4{break;}},Err(e)=>status.push_str(&format!("anr_write_failed={e}\n"))}},Err(e)=>status.push_str(&format!("anr_read_failed={e}\n")),_=>{}}
    }
    status.push_str(&format!("anrSaved={saved} limitBytes=262144 maxReports=4 scope=SpeedBackup\n"));
}
pub fn collect(dir:&Path)->io::Result<()> {collect_from(dir,Path::new("/data/tombstones"),bounded_logcat(),&[])}
pub fn run(args:&[String])->i32 {if args.len()!=1{return 2;}match collect(Path::new(&args[0])){Ok(())=>0,Err(e)=>{eprintln!("CRASH_DIAGNOSTICS unavailable: {e}");1}}}
#[derive(Default)]
struct CaptureState {running:bool,pending:bool,pids:Vec<u32>}
impl CaptureState {
    fn enqueue(&mut self,pid:Option<u32>)->bool {
        if let Some(pid)=pid {if !self.pids.contains(&pid){if self.pids.len()==32{self.pids.remove(0);}self.pids.push(pid);}}
        self.pending=true;
        if self.running{return false;}self.running=true;true
    }
}
static CAPTURE:std::sync::Mutex<CaptureState>=std::sync::Mutex::new(CaptureState{running:false,pending:false,pids:Vec::new()});
pub struct Monitor(std::process::Child);
impl Drop for Monitor {fn drop(&mut self){let _=self.0.kill();let _=self.0.wait();}}
pub fn monitor()->io::Result<Monitor> {
    use std::io::BufRead;
    let mut child=Command::new("/system/bin/logcat").args(["-b","crash","-b","system","-b","main","-v","threadtime","-T","1","AndroidRuntime:E","DEBUG:F","DEBUG32:F","DEBUG64:F","ActivityManager:E","SpeedBackupNative:V","SpeedBackupGuard:V","*:S"]).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
    let stdout=child.stdout.take().ok_or_else(||io::Error::other("crash monitor stdout"))?;
    std::thread::spawn(move||{let reader=io::BufReader::new(stdout);for line in reader.lines().map_while(Result::ok){if related(&line)&&!line.contains("SpeedBackupNative"){capture_console();}}});
    Ok(Monitor(child))
}
pub fn capture_console() {capture_process(None)}
pub fn capture_process(pid:Option<u32>) {
    if !CAPTURE.lock().unwrap().enqueue(pid){return;}
    std::thread::spawn(move||loop {
        std::thread::sleep(Duration::from_secs(2));
        let pids={let mut state=CAPTURE.lock().unwrap();state.pending=false;state.pids.clone()};
        let dir=Path::new("/data/.speedbackup/console/active/crashes");
        let result=fs::create_dir_all(dir).and_then(|_|collect_from(dir,Path::new("/data/tombstones"),bounded_logcat(),&pids));
        match result{Ok(())=>eprintln!("CRASH_DIAGNOSTICS path={}",dir.display()),Err(e)=>eprintln!("CRASH_DIAGNOSTICS unavailable: {e}")}
        let mut state=CAPTURE.lock().unwrap();
        if !state.pending {state.running=false;state.pids.clear();break;}
    });
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn crash_tail_is_independent_of_busy_other_buffers() {
        let crash=logcat_command(&["crash"]);let args=crash.get_args().map(|a|a.to_str().unwrap()).collect::<Vec<_>>();
        assert_eq!(&args[..2], &["-b","crash"]);assert!(!args.contains(&"main")&&!args.contains(&"system"));
        let other=logcat_command(&["system","main"]);let args=other.get_args().map(|a|a.to_str().unwrap()).collect::<Vec<_>>();assert!(!args.contains(&"crash"));
    }
    #[test] fn stderr_and_nonzero_are_not_silent_empty_success() {
        let (text,status)=bounded_capture(Command::new("/system/bin/sh").args(["-c","echo denied >&2; exit 1"])).unwrap();
        assert!(text.is_empty());assert!(status.contains("denied")&&status.contains("complete=false"));
    }
    #[test] fn burst_crashes_preserve_both_pids_and_during_capture_trigger() {
        let mut state=CaptureState::default();assert!(state.enqueue(Some(101)));assert!(!state.enqueue(Some(202)));
        assert_eq!(state.pids,vec![101,202]);state.pending=false;assert!(!state.enqueue(Some(303)));assert!(state.pending);
        let text="11-08 10:00:00.000 10 10 F DEBUG : pid: 101, tid: 101\n11-08 10:00:01.000 20 20 F DEBUG : pid: 202, tid: 202\n11-08 10:00:02.000 30 30 F DEBUG : pid: 404, tid: 404\n";
        let out=crash_groups_many(text,&state.pids);assert!(out.contains("pid: 101")&&out.contains("pid: 202"));assert!(!out.contains("pid: 404"));
    }
    #[test] fn bounded_tombstones_and_unavailable_sources() {
        use std::os::unix::fs::{symlink,PermissionsExt};
        let root=std::env::temp_dir().join(format!("sb-crash-test-{}-{}",std::process::id(),SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_nanos()));
        fs::create_dir_all(root.join("out")).unwrap();fs::create_dir(root.join("tombs")).unwrap();
        for i in 0..6 {fs::write(root.join(format!("tombs/tombstone_{i:02}")),format!("Cmdline: speednative\n{}", "trace\n".repeat(50000))).unwrap();}
        fs::write(root.join("tombs/tombstone_90"),"Cmdline: other.app\nprivate other-app trace").unwrap();
        fs::write(root.join("outside"),"Cmdline: speednative\nsymlink secret").unwrap();symlink(root.join("outside"),root.join("tombs/tombstone_99")).unwrap();
        collect_from(&root.join("out"),&root.join("tombs"),Err(io::Error::new(io::ErrorKind::PermissionDenied,"fixture denied")),&[]).unwrap();
        let files=fs::read_dir(root.join("out")).unwrap().map(|e|e.unwrap().path()).collect::<Vec<_>>();
        assert_eq!(files.iter().filter(|p|p.file_name().unwrap().to_string_lossy().starts_with("native-")).count(),4);
        for p in &files {let text=fs::read_to_string(p).unwrap();assert!(!text.contains("symlink secret")&&!text.contains("private other-app"));assert!(fs::metadata(p).unwrap().len()<=LIMIT+1024);assert_eq!(fs::metadata(p).unwrap().permissions().mode()&0o777,0o600);}
        assert!(fs::read_to_string(root.join("out/status.log")).unwrap().contains("fixture denied"));
        fs::create_dir(root.join("empty")).unwrap();collect_from(&root.join("empty"),&root.join("missing"),Ok((String::new(),"ok".into())),&[]).unwrap();
        assert!(fs::read_to_string(root.join("empty/status.log")).unwrap().contains("tombstones_unavailable"));
        fs::remove_dir_all(root).unwrap();
    }
    #[test] fn completed_output_survives_exit_timeout() {
        let (text,status)=bounded_capture(Command::new("/system/bin/sh").args(["-c","printf retained; exec 1>&-; exec sleep 30"])).unwrap();
        assert_eq!(text,"retained");assert!(status.contains("partial=true"));
    }
    #[test] fn stalled_log_reader_is_bounded() {
        let start=Instant::now();let result=bounded_capture(Command::new("/system/bin/sleep").arg("30"));
        assert_eq!(result.unwrap_err().kind(),io::ErrorKind::TimedOut);assert!(start.elapsed()<Duration::from_secs(5));
    }
    #[test] fn anonymous_runtime_matches_only_observed_pid() {
        assert!(!pid_record("Process: app, PID: 456",Some(45)));

        let text="11-08 10:00:00.000 101 101 F DEBUG : pid: 456, tid: 456, name: app_process\n11-08 10:00:00.001 101 101 F DEBUG : frame\n";
        assert!(crash_groups(text,None).is_empty());assert!(crash_groups(text,Some(456)).contains("frame"));assert!(crash_groups(text,Some(45)).is_empty());
    }
    #[test] fn selects_crash_pid_without_other_app() {
        let text="11-08 10:00:00.000 100 100 F DEBUG : Cmdline: com.xayah.dex.AppListReturn\n11-08 10:00:00.001 100 100 F DEBUG : backtrace frame\n11-08 10:00:00.002 200 200 E AndroidRuntime: Process: other.app, PID: 200\n11-08 10:00:00.003 200 200 E AndroidRuntime: secret\n";
        let out=crash_groups(text,None);assert!(out.contains("backtrace frame"));assert!(!out.contains("secret"));assert!(!out.contains("other.app"));
    }
    #[test] fn filters_unrelated_and_redacts_local_token() {assert!(!related("Cmdline: other.app"));assert!(!crash_groups("unframed other.app",None).contains("other.app"));assert!(!redact("Cmdline: app http://127.0.0.1:123/#secret").contains("secret"));}
    #[test] fn splits_reused_reporter_and_java_anr_events() {
        let text="11-08 10:00:00.000 100 100 F DEBUG : *** *** ***\n11-08 10:00:00.001 100 100 F DEBUG : Cmdline: speednative\n11-08 10:00:00.002 100 100 F DEBUG : ours\n11-08 10:00:01.000 100 100 F DEBUG : *** *** ***\n11-08 10:00:01.001 100 100 F DEBUG : Cmdline: other.app\n11-08 10:00:01.002 100 100 F DEBUG : secret\n11-08 10:00:02.000 200 201 E AndroidRuntime: FATAL EXCEPTION: main\n11-08 10:00:02.001 200 201 E AndroidRuntime: Process: io.github.yawasau.speedbackup.webview, PID: 200\n11-08 10:00:02.002 200 201 E AndroidRuntime: at our.frame\n11-08 10:00:03.000 300 301 E ActivityManager: ANR in io.github.yawasau.speedbackup.webview\n11-08 10:00:03.001 300 301 E ActivityManager: Reason: ours\n11-08 10:00:04.000 300 301 E ActivityManager: ANR in other.app\n11-08 10:00:04.001 300 301 E ActivityManager: Reason: secret\n";
        let text=format!("{text}11-08 10:00:05.000 300 301 E ActivityManager: ANR in io.github.yawasau.speedbackup.webview\n11-08 10:00:06.000 300 301 E ActivityManager: unrelated private error\n11-08 10:00:07.000 300 301 E ActivityManager: Reason: secret after unrelated\n");
        let out=crash_groups(&text,None);assert!(!out.contains("unrelated private"));assert!(out.contains("ours")&&out.contains("our.frame")&&out.contains("FATAL EXCEPTION")&&out.contains("ANR in io.github"));assert!(!out.contains("secret")&&!out.contains("other.app"));
    }
}
