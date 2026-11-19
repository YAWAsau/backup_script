//! On-demand project-only counters; no subprocesses, pings or background sampler.
//! CPU percentage = delta(cpuTicks) / delta(totalTicks) * cpuCount * 100.
//! 100% means one fully occupied core. Discard deltas on pid/startTime changes,
//! counter regression, zero total delta or CPU-count changes. totalTicks excludes
//! guest/guest_nice (already included in user/nice). Counters are decimal strings.
//! sampleMs comes from Linux/Android boot-monotonic /proc/uptime, not wall time.
use std::{
    collections::BTreeSet,
    fs::{self, File, OpenOptions},
    io::{self, Read},
    os::{fd::AsRawFd, unix::{fs::{MetadataExt, OpenOptionsExt}, net::UnixStream}},
    path::Path,
};
use serde_json::{json, Value};
#[path = "process_monitor_owned.rs"]
mod owned;
#[path = "process_monitor_events.rs"]
mod events;
#[path = "process_monitor_perf.rs"]
mod perf;

// Call after the final service fork, before spawning any children.
pub(super) fn start_events() { owned::start(); }

const PACKAGE: &str = "io.github.yawasau.speedbackup.webview";
const SERVICES: &[(&str,&str)] = &[
    ("file_broker","File broker"), ("ui_relay","TTY relay"),
    ("netwatch_native","netwatch"), ("console","Console service"),
    ("webdav_daemon","WebDAV daemon"), ("rootdex_watchdog","Root watchdog"),
    ("webdav_watchdog","WebDAV watchdog"), ("wifi_watcher","Wi-Fi watcher"),
    ("remote_health","Health monitor"), ("netwatch_reader","Network event reader"),
    ("smbclient_publisher","SMB publisher"),
];
fn invalid() -> io::Error { io::Error::other("invalid process monitor input") }
fn bounded(path: impl AsRef<Path>, limit: usize) -> io::Result<Vec<u8>> {
    let mut bytes=Vec::new();
    File::open(path)?.take(limit as u64+1).read_to_end(&mut bytes)?;
    if bytes.len()>limit { return Err(invalid()); }
    Ok(bytes)
}
fn text(path: impl AsRef<Path>, limit: usize) -> io::Result<String> {
    String::from_utf8(bounded(path,limit)?).map_err(|_|invalid())
}
#[derive(Debug,PartialEq)]
struct Stat { start:u64, ticks:u64 }
fn parse_stat(s:&str) -> Option<Stat> {
    let rest=speedbackup_native_rs::proc_stat::split(s)?.1;
    let f:Vec<_>=rest.split_whitespace().collect();
    if matches!(*f.first()?, "Z"|"X"|"x") { return None; }
    Some(Stat{
        start:f.get(19)?.parse().ok()?,
        ticks:f.get(11)?.parse::<u64>().ok()?.checked_add(f.get(12)?.parse().ok()?)?,
    })
}
fn stat(pid:u32) -> Option<Stat> {
    parse_stat(&text(format!("/proc/{pid}/stat"),8192).ok()?)
}
fn same(a:&Stat,b:&Stat) -> bool { a.start==b.start }
fn rss(status:&str) -> Option<u64> {
    let mut fields=status.lines().find_map(|l|l.strip_prefix("VmRSS:"))?.split_whitespace();
    let kb=fields.next()?.parse::<u64>().ok()?;
    if fields.next()!=Some("kB") || fields.next().is_some() { return None; }
    kb.checked_mul(1024)
}
fn uid(pid:u32) -> Option<u32> {
    text(format!("/proc/{pid}/status"),65536).ok()?.lines()
        .find_map(|l|l.strip_prefix("Uid:"))?.split_whitespace().next()?.parse().ok()
}
fn cmdline(pid:u32, expected:&str) -> bool {
    bounded(format!("/proc/{pid}/cmdline"),4096).ok()
        .is_some_and(|b|b.split(|c|*c==0).next()==Some(expected.as_bytes()))
}
// Executable identity is for labels only; owned ancestry grants membership.
// Proven starttime identities survive reparenting.
type ExeIdentity = (u64,u64);

fn exe_identity(pid:u32) -> Option<ExeIdentity> {
    let m=fs::metadata(format!("/proc/{pid}/exe")).ok()?;
    m.is_file().then_some((m.dev(),m.ino()))
}
fn root_uids(status:&str) -> bool {
    let Some(line)=status.lines().find_map(|l|l.strip_prefix("Uid:")) else { return false; };
    let fields:Vec<_>=line.split_whitespace().collect();
    fields.len()==4 && fields.iter().all(|s|s.parse::<u32>()==Ok(0))
}
fn root_process(pid:u32) -> bool {
    text(format!("/proc/{pid}/status"),65536).ok()
        .is_some_and(|s|root_uids(&s))
}
fn selected_applet(bytes:&[u8]) -> Option<&'static str> {
    // Complete, bounded argv only. Payload bytes need not be UTF-8.
    if bytes.is_empty() || bytes.len()>4096 || bytes.last()!=Some(&0) { return None; }
    let mut args=bytes[..bytes.len()-1].split(|b|*b==0);
    let first=args.next()?;
    use std::os::unix::ffi::OsStrExt;
    let base=Path::new(std::ffi::OsStr::from_bytes(first)).file_name()
        .and_then(|s|s.to_str());
    if let Some(name)=base {
        if let Some(applet)=crate::multicall::APPLETS.iter().find(|a|**a==name) {
            return Some(*applet);
        }
    }
    let second=std::str::from_utf8(args.next()?).ok()?;
    crate::multicall::APPLETS.iter().copied().find(|a|*a==second)
}
#[derive(Clone,Debug,PartialEq,Eq)]
struct AppletIdentity {
    pid:u32,
    start:u64,
    exe:ExeIdentity,
    applet:&'static str,
}
fn applet_identity(pid:u32, trusted:&BTreeSet<ExeIdentity>) -> Option<AppletIdentity> {
    let before=stat(pid)?;
    if !root_process(pid) { return None; }
    let exe=exe_identity(pid)?;
    if !trusted.contains(&exe) { return None; }
    let applet=selected_applet(&bounded(format!("/proc/{pid}/cmdline"),4096).ok()?)?;
    let after=stat(pid)?;
    if !same(&before,&after) || !root_process(pid) || exe_identity(pid)!=Some(exe) {
        return None;
    }
    Some(AppletIdentity{pid,start:before.start,exe,applet})
}

// Only already verified live root rows may introduce another deployed inode.
// Restrict those anchors to the immutable bootstrap cache, never a basename or
// an arbitrary path from argv/environment. Self needs no pathname validation:
// its running inode remains authoritative across unlink/atomic replacement.
fn deployed_exe(pid:u32) -> Option<ExeIdentity> {
    let proc_exe=format!("/proc/{pid}/exe");
    let target=fs::read_link(&proc_exe).ok()?;
    if target.file_name()?.to_str()!=Some("speednative") { return None; }
    let bases=[
        Path::new("/data/.speedbackup/console_boot"),
        Path::new("/data/.speedbackup_console_boot"),
    ];
    if !bases.iter().any(|base|target.starts_with(base)) { return None; }
    // Reject symlink ancestors and writable cache directories. /data itself is
    // Android-owned; every directory beneath it must be root-owned and private
    // against writes by other users.
    for dir in target.parent()?.ancestors().take_while(|p|*p!=Path::new("/data")) {
        let m=fs::symlink_metadata(dir).ok()?;
        if !m.is_dir() || m.uid()!=0 || m.mode()&0o022!=0
            || dir.canonicalize().ok()?.as_path()!=dir { return None; }
    }
    let m=fs::metadata(&proc_exe).ok()?;
    if !m.is_file() || m.uid()!=0 || m.mode()&0o022!=0 || m.mode()&0o111==0 {
        return None;
    }
    // Check the pathname without following a final symlink and bind it back to
    // the executing inode. A retired/deleted service copy is not a new anchor.
    let disk=fs::symlink_metadata(&target).ok()?;
    if !disk.is_file() || disk.uid()!=0 || disk.mode()&0o022!=0
        || (disk.dev(),disk.ino())!=(m.dev(),m.ino()) { return None; }
    Some((m.dev(),m.ino()))
}
#[repr(C)]
struct Cred { pid:i32, uid:u32, gid:u32 }
unsafe extern "C" {
    fn getsockopt(fd:i32,level:i32,opt:i32,value:*mut std::ffi::c_void,len:*mut u32)->i32;
}
fn peer(stream:&UnixStream) -> io::Result<Cred> {
    let mut c=Cred{pid:0,uid:0,gid:0};
    let mut len=std::mem::size_of::<Cred>() as u32;
    // SOL_SOCKET / SO_PEERCRED are 1 / 17 on Linux and Android.
    if unsafe{getsockopt(stream.as_raw_fd(),1,17,&mut c as *mut _ as _,&mut len)}!=0
        || len!=std::mem::size_of::<Cred>() as u32 || c.pid<=1 {
        return Err(invalid());
    }
    Ok(c)
}

// Anchor the checked directory by fd, avoiding a path-swap between checking its
// ownership and opening the file. Android's /data and /data/local/tmp ancestors
// are system/shell-owned; the private run directory itself must be root-owned.
fn trusted_file(dir:&Path, name:&str, limit:usize, mode600:bool) -> io::Result<Vec<u8>> {
    if !dir.is_absolute() { return Err(invalid()); }
    let directory=OpenOptions::new().read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_DIRECTORY_NATIVE).open(dir)?;
    let dm=directory.metadata()?;
    if !dm.is_dir() || dm.uid()!=0 || dm.mode()&0o022!=0 { return Err(invalid()); }
    let file=OpenOptions::new().read(true)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE|speedbackup_native_rs::O_NONBLOCK)
        .open(format!("/proc/self/fd/{}/{}",directory.as_raw_fd(),name))?;
    let m=file.metadata()?;
    if !m.is_file() || m.uid()!=0 || m.len()>limit as u64
        || m.mode()&0o022!=0 || (mode600 && m.mode()&0o7777!=0o600) {
        return Err(invalid());
    }
    let mut bytes=Vec::new();
    file.take(limit as u64+1).read_to_end(&mut bytes)?;
    if bytes.len()>limit { return Err(invalid()); }
    Ok(bytes)
}
fn record(bytes:&[u8]) -> Option<(u32,u64)> {
    let mut f=std::str::from_utf8(bytes).ok()?.split_whitespace();
    let pid=f.next()?.parse().ok()?;
    let start=f.next()?.parse().ok()?;
    if pid<=1 || f.next().is_some() { return None; }
    Some((pid,start))
}
fn add(rows:&mut Vec<Value>, seen:&mut BTreeSet<(u32,u64)>, pid:u32,
       start:u64, owner:u32, name:&str, command:Option<&str>) {
    if seen.contains(&(pid,start)) { return; }
    let Some(before)=stat(pid) else { return; };
    if before.start!=start || uid(pid)!=Some(owner)
        || command.is_some_and(|c|!cmdline(pid,c)) { return; }
    let Some(memory)=text(format!("/proc/{pid}/status"),65536).ok().and_then(|s|rss(&s)) else { return; };
    let Some(after)=stat(pid) else { return; };
    if !same(&before,&after) || uid(pid)!=Some(owner)
        || command.is_some_and(|c|!cmdline(pid,c)) { return; }
    seen.insert((pid,start));
    rows.push(json!({"name":name,"pid":pid,"startTime":start.to_string(),
        "cpuTicks":after.ticks.to_string(),"rssBytes":memory.to_string()}));
}
fn cpu(s:&str) -> Option<(u64,usize)> {
    let mut lines=s.lines();
    let mut fields=lines.next()?.split_whitespace();
    if fields.next()!=Some("cpu") { return None; }
    let values=fields.map(str::parse::<u64>).collect::<Result<Vec<_>,_>>().ok()?;
    if values.len()<8 { return None; }
    let total=values[..8].iter().try_fold(0u64,|a,b|a.checked_add(*b))?;
    let count=lines.filter(|l|l.split_whitespace().next().is_some_and(|v|
        v.strip_prefix("cpu").is_some_and(|n|!n.is_empty()&&n.bytes().all(|c|c.is_ascii_digit())))).count();
    (count>0).then_some((total,count))
}
fn milliseconds(s:&str) -> Option<u64> {
    let first=s.split_whitespace().next()?;
    let (whole,fraction)=first.split_once('.')?;
    if fraction.is_empty() || !fraction.bytes().all(|c|c.is_ascii_digit()) { return None; }
    let mut ms=0u64;
    for c in fraction.bytes().chain(std::iter::repeat(b'0')).take(3) {
        ms=ms*10+(c-b'0') as u64;
    }
    whole.parse::<u64>().ok()?.checked_mul(1000)?.checked_add(ms)
}
fn registry_rows(rows:&mut Vec<Value>, seen:&mut BTreeSet<(u32,u64)>,
                 run:Option<&Path>, health:Option<&Path>) {
    if let Some(dir)=run {
        for &(tag,name) in SERVICES {
            let file=format!(".health-service-{tag}");
            // Read once to locate the PID, then bracket the authoritative read
            // with live identity checks. A replacement record is not accepted.
            let Ok(first)=trusted_file(Path::new(&dir),&file,128,true) else { continue; };
            let Some((p,start))=record(&first) else { continue; };
            let Some(before)=stat(p) else { continue; };
            let Ok(second)=trusted_file(Path::new(&dir),&file,128,true) else { continue; };
            let Some(after)=stat(p) else { continue; };
            if record(&second)!=Some((p,start)) || before.start!=start || !same(&before,&after) { continue; }
            add(rows,seen,p,start,0,name,None);
        }
    }
    if let Some(dir)=health {
        if let Ok(bytes)=trusted_file(Path::new(&dir),"daemons.json",65536,false) {
            if let Ok(data)=serde_json::from_slice::<Value>(&bytes) {
                // Only the two authenticated core endpoints, not arbitrary
                // metadata-supplied process names or stale service records.
                for (kind,name) in [("rust","cgfreezer"),("dex","RootDaemon")] {
                    if let Some(items)=data[kind]["components"].as_array() {
                        for item in items.iter().take(64) {
                            if item["name"]!=name || item["status"]!="ready" || item["verification"]!="handshake" { continue; }
                            let Some(p)=item["pid"].as_u64().and_then(|p|u32::try_from(p).ok()).filter(|p|*p>1) else { continue; };
                            let Some(start)=item["startTime"].as_str().and_then(|s|s.parse::<u64>().ok()) else { continue; };
                            add(rows,seen,p,start,0,name,None);
                        }
                    }
                }
            }
        }
    }
}
pub fn snapshot(stream:&UnixStream) -> io::Result<Value> {
    snapshot_for_package(stream,PACKAGE)
}
fn snapshot_for_package(stream:&UnixStream, package:&str) -> io::Result<Value> {
    let caller=peer(stream)?;
    let pid=caller.pid as u32;
    let identity=stat(pid).ok_or_else(invalid)?;
    if uid(pid)!=Some(caller.uid) || !cmdline(pid,package) { return Err(invalid()); }
    let (total,count)=cpu(&text("/proc/stat",262144)?).ok_or_else(invalid)?;
    let sample=milliseconds(&text("/proc/uptime",256)?).ok_or_else(invalid)?;
    let mut rows=Vec::new(); let mut seen=BTreeSet::new();
    add(&mut rows,&mut seen,pid,identity.start,caller.uid,"SpeedBackup",Some(package));
    if rows.is_empty() { return Err(invalid()); }
    // Only a fully validated peer may start the lazy observer or register a
    // package watch. package is internal, never a request parameter.
    start_events();
    owned::register_caller(pid,identity.start,caller.uid,package);
    let own=std::process::id();
    if uid(own)==Some(0) {
        if let Some(s)=stat(own) { add(&mut rows,&mut seen,own,s.start,0,"Root controller",None); }
    }
    let run=std::env::var_os("SPEEDBACKUP_RUN_TMPDIR");
    let health=std::env::var_os("SPEEDBACKUP_REMOTE_HEALTH_DIR");
    registry_rows(&mut rows,&mut seen,run.as_deref().map(Path::new),health.as_deref().map(Path::new));
    let discovery_partial=owned::append(&mut rows,&mut seen);
    let end=stat(pid).ok_or_else(invalid)?;
    if !same(&identity,&end) || uid(pid)!=Some(caller.uid) || !cmdline(pid,package) { return Err(invalid()); }
    // Deliberately use totalTicks/cpuCount rather than libc's platform-specific
    // sysconf selector. No assumed USER_HZ or fabricated ticksPerSecond.
    let partial=discovery_partial || rows.len()>64;
    rows.truncate(64);
    Ok(json!({"sampleMs":sample,"totalTicks":total.to_string(),"cpuCount":count,"partial":partial,"discoveryMode":owned::discovery_mode(),"eventBackend":events::backend_label(),
        "partialReason":if discovery_partial {
            Some("Event discovery unavailable, lost, bounded, or identity proof incomplete; no polling fallback. Verified ancestry scope.")
        } else {None},
        "processes":rows}))
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multicall_identity_selection_and_filtering() {
        for name in crate::multicall::APPLETS {
            assert_eq!(selected_applet(format!("/trusted/{name}\0--help\0").as_bytes()),Some(name));
            assert_eq!(selected_applet(format!("speednative\0{name}\0").as_bytes()),Some(name));
        }
        assert_eq!(selected_applet(b"uidexec\0speedscan\0"),Some("uidexec"));
        assert_eq!(selected_applet(b"speednative\0speedscan\0\xff\0"),Some("speedscan"));
        for bytes in [
            &b"speednative\0../speedscan\0"[..],
            &b"speednative\0speedscan-other\0"[..],
            &b"speednative\0--list\0"[..],
            &b"sh\0-c\0speedscan\0"[..],
            &b"speednative\0speedscan"[..],
            &b""[..],
        ] {
            assert_eq!(selected_applet(bytes),None);
        }
        assert_eq!(selected_applet(&vec![0;4097]),None);
        assert!(root_uids("Name:\ttest\nUid:\t0 0 0 0\n"));
        for status in ["Uid: 0", "Uid: 0 1 0 0", "Uid: 0 0 0 0 0", "Uid: x 0 0 0"] {
            assert!(!root_uids(status));
        }
        // A matching argv alone cannot authorize even this test executable.
        assert!(applet_identity(std::process::id(),&BTreeSet::new()).is_none());
    }
    #[test]
    #[ignore = "root-owned Android filesystem integration"]
    fn trusted_records_android(){
        use std::os::unix::fs::{PermissionsExt,symlink};
        let dir=std::path::PathBuf::from(format!("/data/local/tmp/sb-monitor-trust-{}",std::process::id()));
        fs::create_dir(&dir).unwrap();fs::set_permissions(&dir,fs::Permissions::from_mode(0o700)).unwrap();
        assert_eq!(fs::metadata(&dir).unwrap().uid(),0);
        let path=dir.join("record");fs::write(&path,b"42 900\n").unwrap();fs::set_permissions(&path,fs::Permissions::from_mode(0o600)).unwrap();
        assert_eq!(trusted_file(&dir,"record",128,true).unwrap(),b"42 900\n");
        symlink(&path,dir.join("link")).unwrap();assert!(trusted_file(&dir,"link",128,true).is_err());
        assert!(trusted_file(&dir,"record",2,true).is_err());
        fs::set_permissions(&path,fs::Permissions::from_mode(0o644)).unwrap();assert!(trusted_file(&dir,"record",128,true).is_err());
        fs::create_dir(dir.join("directory")).unwrap();assert!(trusted_file(&dir,"directory",128,true).is_err());
        fs::remove_dir_all(&dir).unwrap();
    }
    #[test]
    #[cfg(target_os="android")]
    #[ignore = "controlled Android overlay integration fixture"]
    fn overlay_fixture() {
        use std::{io::Write,os::android::net::SocketAddrExt,os::unix::net::{UnixListener,SocketAddr},time::{Instant,Duration}};
        let name=format!("sb-ui-{}","b".repeat(64));
        let listener=UnixListener::bind_addr(&SocketAddr::from_abstract_name(name).unwrap()).unwrap();
        listener.set_nonblocking(true).unwrap();
        let deadline=Instant::now()+Duration::from_secs(90);
        while Instant::now()<deadline {
            let (mut stream,_)=match listener.accept(){Ok(v)=>v,Err(e) if e.kind()==io::ErrorKind::WouldBlock=>{std::thread::sleep(Duration::from_millis(20));continue},Err(e)=>panic!("{e}")};
            stream.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
            let mut header=Vec::new();
            while !header.ends_with(b"\r\n\r\n")&&header.len()<8192 {let mut b=[0];if stream.read(&mut b).unwrap_or(0)!=1{break}header.push(b[0]);}
            let request=String::from_utf8_lossy(&header);
            assert!(request.starts_with("GET /api/process-monitor "));
            assert!(request.to_lowercase().contains(&format!("x-speedbackup-token: {}","b".repeat(64))));
            // Production entry still rejects the fixture package; only this
            // ignored integration test selects the explicitly installed probe.
            assert!(snapshot(&stream).is_err());
            let value=snapshot_for_package(&stream,"io.github.yawasau.speedbackup.webview.backprobe").unwrap();
            assert!(value["processes"].as_array().unwrap().len()<=64);
            assert!(value["partial"].is_boolean());
            assert!(value["processes"].as_array().unwrap().iter().all(|p|p["name"].as_str().is_some_and(|n|!n.is_empty() && !n.chars().any(char::is_control))));
            let body=value.to_string();
            write!(stream,"HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",body.len(),body).unwrap();
            println!("MONITOR_REAL_SAMPLE {}",value["sampleMs"]);
        }
    }
    fn fixture(state:&str,start:u64)->String {
        let mut f=vec!["0".to_owned();22];
        f[0]=state.into(); f[11]="123".into(); f[12]="7".into(); f[19]=start.to_string();
        format!("42 (name with ) parentheses) {}",f.join(" "))
    }
    #[test] fn stat_and_pid_reuse() {
        let a=parse_stat(&fixture("S",900)).unwrap();
        assert_eq!(a,Stat{start:900,ticks:130});
        assert!(same(&a,&parse_stat(&fixture("R",900)).unwrap()));
        assert!(!same(&a,&parse_stat(&fixture("S",901)).unwrap()));
        assert!(parse_stat(&fixture("Z",900)).is_none());
        assert!(parse_stat("42 (broken) S 0").is_none());
    }
    #[test] fn strict_records_and_memory() {
        assert_eq!(record(b"42 900\n"),Some((42,900)));
        assert_eq!(record(b"42 900 extra"),None);
        assert_eq!(record(b"0 900"),None);
        assert_eq!(rss("Name:\tx\nVmRSS:\t123 kB\n"),Some(125952));
        assert_eq!(rss("VmRSS: 123 MB"),None);
        assert_eq!(rss("Name: absent\n"),None);
    }
    #[test] fn cpu_excludes_guest_and_counts_online_rows() {
        assert_eq!(cpu("cpu 1 2 3 4 5 6 7 8 100 200\ncpu0 0\ncpu2 0\nintr 10\n"),Some((36,2)));
        assert_eq!(cpu("cpu 1 2\ncpu0 0\n"),None);
        assert_eq!(milliseconds("123.45 22.00\n"),Some(123450));
        assert_eq!(milliseconds("nan 0"),None);
    }
}
