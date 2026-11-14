//! Session-owned remote health. Events invalidate immediately; only the matching
//! generation's authenticated protocol probe can turn the status green.
use serde_json::{json, Value};
use speedbackup_native_rs::{
    inotify_add_watch, inotify_init1, poll, read, PollFd, O_CLOEXEC, O_NONBLOCK, POLLIN,
};
use std::{
    collections::BTreeMap,
    ffi::CString,
    fs::{self, OpenOptions},
    io::{self, BufRead, BufReader, Read, Write},
    net::TcpStream,
    os::{
        fd::{AsRawFd, FromRawFd, OwnedFd},
        unix::{
            fs::{MetadataExt, OpenOptionsExt},
            net::{UnixDatagram, UnixListener, UnixStream},
        },
    },
    path::{Path, PathBuf},
};
struct WifiWatcher(super::command_lifecycle::OwnedChild);
impl WifiWatcher {
    fn start(dir: &Path) -> io::Result<Self> {
        use std::process::{Command,Stdio};
        let dex=std::env::current_exe()?.parent().ok_or_else(||error("executable parent"))?.join("classes.dex");
        let child=super::command_lifecycle::OwnedChild::spawn(Command::new("/system/bin/app_process").env("CLASSPATH",dex)
            .args(["/system/bin","com.xayah.dex.WifiConnectionWatch"]).arg(dir)
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()))?;
        Ok(Self(child))
    }
}
impl Drop for WifiWatcher {
    fn drop(&mut self) {
        drop(self.0.stdin.take());
        // OwnedChild kills/reaps without blocking on a stuck vendor driver.
    }
}
fn wifi_snapshot(dir: &Path, alive: bool) -> Value {
    if !alive {return json!({"available":false});}
    fs::read(dir.join("wifi.json")).ok().filter(|b|b.len()<=4096)
        .and_then(|b|serde_json::from_slice::<Value>(&b).ok()).filter(Value::is_object)
        .unwrap_or(json!({"available":false}))
}
fn error(s: &str) -> io::Error {
    io::Error::other(s)
}
fn private(dir: &Path) -> io::Result<()> {
    let m = fs::symlink_metadata(dir)?;
    if !m.is_dir() || m.uid() != unsafe { getuid() } || m.mode() & 0o777 != 0o700 {
        return Err(error("health directory"));
    }
    Ok(())
}
unsafe extern "C" {
    fn getuid() -> u32;
    fn getppid() -> i32;
    fn prctl(
        option: i32,
        a: std::os::raw::c_ulong,
        b: std::os::raw::c_ulong,
        c: std::os::raw::c_ulong,
        d: std::os::raw::c_ulong,
    ) -> i32;
    fn socket(d: i32, t: i32, p: i32) -> i32;
    fn bind(fd: i32, a: *const std::ffi::c_void, n: u32) -> i32;
    fn recv(fd: i32, b: *mut std::ffi::c_void, n: usize, f: i32) -> isize;
}
fn fd(n: i32) -> io::Result<OwnedFd> {
    if n < 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(unsafe { OwnedFd::from_raw_fd(n) })
    }
}
fn ino(paths: &[&Path]) -> io::Result<OwnedFd> {
    let f = fd(unsafe { inotify_init1(O_CLOEXEC | O_NONBLOCK) })?;
    for p in paths {
        let c = CString::new(p.as_os_str().as_encoded_bytes())?;
        if unsafe { inotify_add_watch(f.as_raw_fd(), c.as_ptr(), 0x00000fc8) } < 0 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(f)
}
fn network() -> io::Result<OwnedFd> {
    let f = fd(unsafe { socket(16, 3 | O_CLOEXEC | O_NONBLOCK, 0) })?;
    #[repr(C)]
    struct Addr {
        family: u16,
        pad: u16,
        pid: u32,
        groups: u32,
    }
    let a = Addr {
        family: 16,
        pad: 0,
        pid: 0,
        groups: 1 | 0x10 | 0x40 | 0x100 | 0x400,
    };
    if unsafe { bind(f.as_raw_fd(), &a as *const _ as *const std::ffi::c_void, 12) } < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(f)
}
fn identity(pid: u32) -> String {
    fs::read_to_string(format!("/proc/{pid}/stat"))
        .ok()
        .and_then(|s| {
            speedbackup_native_rs::proc_stat::split(&s).map(|(_, v)| {
                if v.starts_with("Z ") {
                    String::new()
                } else {
                    v.split_whitespace().nth(19).unwrap_or("").to_owned()
                }
            })
        })
        .unwrap_or_default()
}
fn connection(conf: &Path) -> io::Result<(String, String, bool)> {
    let fields = super::web_settings::parse_runtime(&super::runtime_conf::read(conf)?)?;
    let map: BTreeMap<_, _> = fields.into_iter().map(|f| (f.key, f.value)).collect();
    let protocol = map.get("remote_type").cloned().unwrap_or_default();
    let keys = [
        "remote_type",
        "remote_address_mode",
        "remote_smb_identity",
        "remote_webdav_identity",
        "smb_url",
        "smb_remote_user",
        "smb_remote_pass",
        "webdav_url",
        "webdav_remote_user",
        "webdav_remote_pass",
    ];
    let relevant: Vec<_> = keys.iter().map(|k| (*k, map.get(*k))).collect();
    let key = super::sha256_reader_hex(serde_json::to_vec(&relevant)?.as_slice())?;
    Ok((
        key,
        if protocol.is_empty() {
            "local".into()
        } else {
            protocol
        },
        map.get("remote_address_mode").is_some_and(|v|v=="auto"),
    ))
}
fn usable_lan(name: &str, up: bool, loopback: bool, p2p: bool) -> bool {
    up && !loopback && !p2p && !["rmnet","r_rmnet","ccmni","pdp","wwan","clat","v4-","dummy","ifb","tun","gre","erspan","ip_vti","ip6_vti","sit","ip6tnl","ip6gre","veth","p2p","wifi-aware"].iter().any(|prefix|name.starts_with(prefix))
}
fn local_network_available() -> bool {
    if_addrs::get_if_addrs().is_ok_and(|interfaces| interfaces.iter().any(|i|
        usable_lan(&i.name,i.is_oper_up(),i.is_loopback(),i.is_p2p) && !i.ip().is_unspecified()))
}
// Shared metadata can identify VPN and OEM tether interfaces that interface-name
// heuristics cannot. Complete metadata is authoritative; otherwise retain the
// interface fallback so unavailable vendor APIs cannot disable working routes.
fn metadata_has_local_path(wifi:&Value)->bool {
    wifi["sharing"].as_array().is_some_and(|v|!v.is_empty()) ||
    wifi["links"].as_array().is_some_and(|v|v.iter().any(|link|link["kind"].as_str().is_some_and(|k|k!="cellular")))
}
fn available_network(dir:&Path)->bool { network_from_metadata(&wifi_snapshot(dir,true)) }
fn network_from_metadata(wifi:&Value)->bool {
    if wifi["networkKnown"]==true && wifi["sharingKnown"]==true {metadata_has_local_path(&wifi)}
    else {local_network_available() || metadata_has_local_path(&wifi)}
}
fn display_reason<'a>(reason:&'a str,wifi:&Value)->&'a str {
    let only_cellular=wifi["networkKnown"]==true && wifi["sharingKnown"]==true && !metadata_has_local_path(wifi) &&
        wifi["links"].as_array().is_some_and(|v|!v.is_empty()&&v.iter().all(|link|link["kind"]=="cellular"));
    if reason=="no_lan"&&only_cellular {"no_lan_cellular"} else {reason}
}
fn target_requires_lan(conf:&Path)->bool {
    let Ok(text)=super::runtime_conf::read(conf) else{return false;};
    let Ok(fields)=super::web_settings::parse_runtime(&text) else{return false;};
    let get=|key:&str|fields.iter().find(|f|f.key==key).map(|f|f.value.as_str()).unwrap_or("");
    if get("remote_address_mode")=="auto"{return true;}
    let protocol=get("remote_type");
    let Ok((host,_))=super::remote_control::endpoint(protocol,get(if protocol=="smb"{"smb_url"}else{"webdav_url"})) else{return false;};
    host_requires_lan(&host)
}
fn host_requires_lan(host:&str)->bool {
    match host.parse::<std::net::IpAddr>() {
        Ok(std::net::IpAddr::V4(ip))=>ip.is_private()||ip.is_link_local(),
        Ok(std::net::IpAddr::V6(ip))=>ip.is_unique_local()||ip.is_unicast_link_local(),
        Err(_)=>host.to_ascii_lowercase().ends_with(".local"),
    }
}
fn next_check(protocol: &str) -> (&'static str, &'static str, bool) {
    if protocol=="local" {("local","",false)}else {("checking","",true)}
}
fn connection_check(protocol:&str,conf:&Path,lan:bool)->(&'static str,&'static str,bool){
    if protocol!="local"&&target_requires_lan(conf)&&!lan{("offline","no_lan",false)}
    else{next_check(protocol)}
}
fn route_key(conf: &Path) -> Option<String> {
    let fields = super::web_settings::parse_runtime(&super::runtime_conf::read(conf).ok()?).ok()?;
    let get = |key: &str| {
        fields
            .iter()
            .find(|f| f.key == key)
            .map(|f| f.value.as_str())
            .unwrap_or("")
    };
    let protocol = get("remote_type");
    let url = get(if protocol == "smb" {
        "smb_url"
    } else {
        "webdav_url"
    });
    let (host, _) = super::remote_control::endpoint(protocol, url).ok()?;
    // Numeric endpoints need no DNS request. Hostnames invalidate conservatively.
    host.parse::<std::net::IpAddr>().ok()?;
    use std::process::{Command,Stdio};
    let mut child=super::command_lifecycle::OwnedChild::spawn(Command::new("/system/bin/ip")
        .args(["route","get",&host]).stdout(Stdio::piped()).stderr(Stdio::null())).ok()?;
    let status=super::command_lifecycle::wait_checked(&mut child,std::time::Duration::from_secs(1),||Ok(())).ok()?;
    if !status.success(){return None;}
    let mut text=String::new();child.stdout.take()?.take(4097).read_to_string(&mut text).ok()?;
    if text.len()>4096{return None;}
    let parts: Vec<_> = text.split_whitespace().collect();
    Some(
        parts
            .windows(2)
            .filter(|v| matches!(v[0], "dev" | "src" | "via" | "table"))
            .map(|v| format!("{}={}", v[0], v[1]))
            .collect::<Vec<_>>()
            .join("|"),
    )
}

fn atomic(dir: &Path, v: &Value) -> io::Result<()> {
    let serialized=v.to_string();
    if fs::read_to_string(dir.join("state")).ok().as_deref() == Some(serialized.as_str()) {
        return Ok(());
    }
    let p = dir.join("state.new");
    let mut f = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(&p)?;
    f.write_all(serialized.as_bytes())?;
    fs::rename(p, dir.join("state"))
}
fn safe_reason(reason: &str) -> &str {
    match reason {
        "account_missing"|"password_missing"|"discovery_unconfigured"|"no_lan"|"auth_failed"|"account_unavailable"|"access_denied"|"share_missing"|"share_required"|"path_missing"|"timeout"|"protocol_error"|"server_error"|"rate_limited"|"discovery_failed"|"invalid_address"|"invalid_config"|"local_error"|"monitor_stopped"|"config_changed"|"connection_failed" => reason,
        _ => "connection_failed",
    }
}
fn probe_reason(reason:&str,lan:bool)->&str {
    if !lan&&matches!(reason,"connection_failed"|"timeout"|"discovery_failed"){"no_lan"}else{safe_reason(reason)}
}
fn network_display(wifi:&Value,route:Option<&str>,ready:bool)->Value {
    let interface=route.and_then(|r|r.split('|').find_map(|v|v.strip_prefix("dev="))).unwrap_or("");
    let sharing=wifi["sharing"].as_array().map(Vec::as_slice).unwrap_or(&[]);
    let links=wifi["links"].as_array().map(Vec::as_slice).unwrap_or(&[]);
    let kind=sharing.iter().chain(links).find(|v|v["interface"]==interface).and_then(|v|v["kind"].as_str()).unwrap_or("");
    let label=|kind:&str|match kind{"usb_tether"=>"USB 網路分享","hotspot"=>"Wi-Fi 熱點分享","ethernet"=>"有線網路","wifi"=>"Wi-Fi","cellular"=>"行動網路","vpn"=>"VPN","bluetooth_tether"=>"藍牙網路分享","ethernet_tether"=>"乙太網路分享","tether"=>"網路分享",_=>"網路"};
    let mut rows=Vec::new();let mut detail=Vec::new();
    if !kind.is_empty(){rows.push(json!({"label":"連線","caption":label(kind)}));}
    else if ready {rows.push(json!({"label":"連線","caption":if interface.is_empty(){"網路（類型未提供）"}else{"網路介面"}}));}
    let mut shared=std::collections::BTreeSet::new();
    for link in sharing {if let Some(kind)=link["kind"].as_str(){shared.insert(format!("{}中",label(kind)));}}
    detail.extend(shared);
    // AP signal strength cannot be inferred from the phone's upstream Wi-Fi RSSI.
    if wifi["connected"]==true&&(kind=="wifi"||(interface.is_empty()&&sharing.is_empty())) {
        let frequency=wifi["frequencyMhz"].as_i64().unwrap_or(0);
        let band=match frequency{2400..=2500=>"2.4 GHz",4900..=5924=>"5 GHz",5925..=7125=>"6 GHz",_=>"無法取得"};
        let rssi=wifi["rssiDbm"].as_i64();
        let signal=match rssi{Some(-50..=0)=>"非常好",Some(-60..=-51)=>"很好",Some(-67..=-61)=>"良好",Some(-75..=-68)=>"偏弱",Some(-85..=-76)=>"差",Some(_)=>"非常差",None=>"無法取得"};
        let width=wifi["linkWidthMhz"].as_str().filter(|s|!s.is_empty()).map(|w|format!("{w} MHz"))
            .or_else(||wifi["widthMhz"].as_str().filter(|s|!s.is_empty()).map(|w|format!("{w} MHz（AP）"))).unwrap_or("無法取得".into());
        for(name,value)in[("頻段",band.to_owned()),("頻率",if frequency>0{format!("{frequency} MHz")}else{"無法取得".into()}),("訊號",rssi.map(|r|format!("{r} dBm {signal}")).unwrap_or_else(||signal.into())),("頻寬",width)]{rows.push(json!({"label":name,"caption":value}));}
        let rate=wifi["linkSpeedMbps"].as_u64().filter(|n|*n>0).map(|n|format!("{n} Mbps")).unwrap_or_else(||"無法取得".into());
        rows.push(json!({"label":"連線速率","caption":rate}));
        let standard=match wifi["wifiStandard"].as_i64(){Some(1)=>"802.11a/b/g",Some(4)=>"Wi-Fi 4",Some(5)=>"Wi-Fi 5",Some(6)=>"Wi-Fi 6",Some(7)=>"802.11ad",Some(8)=>"Wi-Fi 7",_=>"無法取得"};
        let caption=if standard=="無法取得"{"Wi-Fi"}else{standard};
        if let Some(row)=rows.iter_mut().find(|row|row["label"]=="連線"){row["caption"]=json!(caption);}else{rows.insert(0,json!({"label":"連線","caption":caption}));}
        if rssi.is_some_and(|r|r< -67){detail.push("訊號偏弱，傳輸速度可能受限".into());}
    }
    if detail.is_empty()&&!ready&&kind.is_empty()&&wifi["available"]!=true {detail.push("連線方式資訊無法取得".into());}
    json!({"rows":rows,"detail":detail.join("；"),"interface":interface,"kind":kind})
}
pub fn snapshot(conf: &Path, dir: &Path) -> Value {
    let (key, protocol, auto_discovery) = connection(conf).unwrap_or_else(|_| (String::new(), "invalid".into(), false));
    let state = fs::read(dir.join("state"))
        .ok()
        .and_then(|s| serde_json::from_slice::<Value>(&s).ok())
        .unwrap_or(json!({}));
    let pid = state["pid"].as_u64().unwrap_or(0) as u32;
    let alive = pid > 0
        && !identity(pid).is_empty()
        && identity(pid) == state["start"].as_str().unwrap_or("");
    let wifi=wifi_snapshot(dir,alive);
    let lan=network_from_metadata(&wifi);
    let no_lan=protocol!="local"&&target_requires_lan(conf)&&!lan;
    let status = if no_lan {"offline"} else if protocol == "local" {
        "local"
    } else if alive && state["key"] == key {
        state["status"]
            .as_str()
            .filter(|s| matches!(*s, "ready" | "checking" | "offline"))
            .unwrap_or("offline")
    } else {
        "offline"
    };
    let reason=if no_lan {"no_lan"} else if status!="offline" {""} else if protocol=="invalid" {"invalid_config"}
        else if !alive && state["key"]==key && state["status"]=="offline" && state["reason"]=="timeout" {"timeout"}
        else if !alive {"monitor_stopped"} else if state["key"]!=key {"config_changed"}
        else {safe_reason(state["reason"].as_str().unwrap_or("connection_failed"))};
    let reason=display_reason(reason,&wifi);
    let network=network_display(&wifi,state["route"].as_str(),status=="ready");
    json!({"autoDiscovery":auto_discovery,"lanAvailable":alive&&lan,"protocol":protocol,"status":status,"reason":reason,"network":network,"wifi":wifi,"daemons":super::daemon_health::snapshot(dir,alive),"generation":state["generation"].as_u64().unwrap_or(0)})
}
pub fn event(dir: &Path, message: &str) -> io::Result<()> {
    private(dir)?;
    let s = UnixDatagram::unbound()?;
    s.set_nonblocking(true)?;
    s.send_to(message.as_bytes(), dir.join("control"))?;
    Ok(())
}
struct ProbeWorker(std::sync::Arc<super::command_lifecycle::CancelEvent>);
impl Drop for ProbeWorker {fn drop(&mut self){self.0.store(true,std::sync::atomic::Ordering::Release);}}
fn begin_probe(conf:&Path,dir:&Path,generation:u64)->io::Result<ProbeWorker>{
    let cancel=std::sync::Arc::new(super::command_lifecycle::CancelEvent::new()?);
    let flag=cancel.clone();let conf=conf.to_owned();let dir=dir.to_owned();
    std::thread::Builder::new().name("remote-probe".into()).spawn(move||{
        let result=super::remote_probe::probe(&conf,Some(&flag));
        let(status,reason)=match result{Ok(())=>("ready",String::new()),Err(reason)=>("offline",reason)};
        // Completion cannot be dropped on a full control queue. A bounded blocking
        // send is event driven and the owner continues draining while probes run.
        if let Ok(socket)=UnixDatagram::unbound(){
            let _=socket.set_write_timeout(Some(std::time::Duration::from_secs(2)));
            let _=socket.send_to(format!("result {generation} {status} {reason}").as_bytes(),dir.join("control"));
        }
    })?;
    Ok(ProbeWorker(cancel))
}
fn watch(conf: &Path, dir: &Path, owner: u32) -> io::Result<()> {
    private(dir)?;
    // The shell execs this worker directly: parent death is an event even on
    // Android kernels predating pidfd_open. Close the setup race explicitly.
    if unsafe { getppid() } as u32 != owner {
        return Err(error("health owner changed"));
    }
    if unsafe { prctl(1, 15, 0, 0, 0) } != 0 {
        return Err(io::Error::last_os_error());
    }
    if unsafe { getppid() } as u32 != owner {
        return Err(error("health owner changed"));
    }
    let subscribers = UnixListener::bind(dir.join("events"))?;
    subscribers.set_nonblocking(true)?;
    let mut clients: Vec<UnixStream> = Vec::new();
    let mut last_event = String::new();
    let control = UnixDatagram::bind(dir.join("control"))?;
    control.set_nonblocking(true)?;
    let changes = ino(&[conf.parent().ok_or_else(|| error("conf parent"))?, dir])?;
    let net = network()?;
    let mut wifi=WifiWatcher::start(dir).ok();
    super::daemon_health::register_process("wifi_watcher",wifi.as_ref().map(|w|w.0.id()).unwrap_or(0))?;
    if let Ok(pid)=std::env::var("SPEEDBACKUP_CONSOLE_OWNER").unwrap_or_default().parse::<u32>() {super::daemon_health::register_process("console",pid)?;}
    super::daemon_health::register_process("remote_health",std::process::id())?;
    let _daemons=super::daemon_health::start(dir)?;
    let ownerfd = speedbackup_native_rs::pidfd_open(owner as i32)
        .ok()
        .map(|n| unsafe { OwnedFd::from_raw_fd(n) });
    let pid = std::process::id();
    let start = identity(pid);
    let (mut key, mut protocol, _) = connection(conf)?;
    let mut generation = 1u64;
    let mut busy = false;
    let mut active_generation=None;
    let mut worker:Option<ProbeWorker>=None;
    let mut pending = false;
    let mut paused = false;
    let mut route = route_key(conf);
    let mut probe_deadline: Option<std::time::Instant> = None;
    let mut lan = available_network(dir);
    let (initial_status, initial_reason, initial_probe)=connection_check(&protocol,conf,lan);
    let mut reason = initial_reason.to_string();
    let mut status = initial_status;
    let publish = |key: &str, protocol: &str, status: &str, generation: u64, reason: &str, route: Option<&str>| {
        atomic(
            dir,
            &json!({"key":key,"protocol":protocol,"status":status,"reason":if status=="offline"{safe_reason(reason)}else{""},"generation":generation,"pid":pid,"start":start,"route":route}),
        )
    };
    publish(&key, &protocol, status, generation, &reason,route.as_deref())?;
    if initial_probe {
        worker=Some(begin_probe(conf,dir,generation)?);
        active_generation=Some(generation);
        busy = true;
        probe_deadline = Some(std::time::Instant::now() + std::time::Duration::from_secs(60));
    }
    loop {
        let update = snapshot(conf, dir).to_string() + "\n";
        if update != last_event {
            clients.retain_mut(|c| c.write_all(update.as_bytes()).is_ok());
            last_event = update;
        }
        let mut fds = vec![
            PollFd {
                fd: control.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            },
            PollFd {
                fd: changes.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            },
            PollFd {
                fd: net.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            },
        ];
        fds.push(PollFd {
            fd: subscribers.as_raw_fd(),
            events: POLLIN,
            revents: 0,
        });
        if let Some(f) = &ownerfd {
            fds.push(PollFd {
                fd: f.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            });
        }
        let owner_index=if ownerfd.is_some(){Some(4)}else{None};
        let wifi_index=wifi.as_ref().and_then(|w|w.0.stdout.as_ref()).map(|out|{
            let index=fds.len();fds.push(PollFd{fd:out.as_raw_fd(),events:POLLIN,revents:0});index
        });
        let timeout = probe_deadline
            .map(|d| {
                d.saturating_duration_since(std::time::Instant::now())
                    .as_millis()
                    .min(i32::MAX as u128) as i32
            })
            .unwrap_or(-1);
        let rc = unsafe { poll(fds.as_mut_ptr(), fds.len() as _, timeout) };
        if rc == 0 {
            // A probe started before a LAN/config change must not overwrite its cause.
            let (s,r)=if protocol=="local" {("local","")} else if target_requires_lan(conf)&&!available_network(dir) {("offline","no_lan")} else {("offline","timeout")};
            publish(&key, &protocol, s, generation + 1, r,route.as_deref())?;
            return Err(error("health probe deadline"));
        }
        if rc < 0 {
            if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(io::Error::last_os_error());
        }
        if owner_index.is_some_and(|i|fds[i].revents != 0) {
            return Ok(());
        }
        if wifi_index.is_some_and(|i|fds[i].revents != 0) {
            wifi=None;let _=fs::remove_file(dir.join("wifi.json"));
        }
        let mut invalidate = false;
        let mut failure = false;
        if fds[1].revents != 0 {
            let mut b = [0u8; 65536];
            while unsafe { read(changes.as_raw_fd(), b.as_mut_ptr() as _, b.len()) } > 0 {}
            if !dir.is_dir() {
                return Ok(());
            }
            let (k, p, _) = connection(conf).unwrap_or_else(|_| (String::new(), "invalid".into(), false));
            let current_lan=available_network(dir);
            if current_lan!=lan {lan=current_lan;invalidate=true;}
            if k != key || p != protocol {
                key = k;
                protocol = p;
                route = route_key(conf);
                invalidate = true;
            }
        }
        if fds[2].revents != 0 {
            let previous_lan=lan;
            lan=available_network(dir);
            let previous_route = route.clone();
            let mut network_event = false;
            let mut b = [0u8; 65536];
            loop {
                let n = unsafe { recv(net.as_raw_fd(), b.as_mut_ptr() as _, b.len(), 0x40) };
                if n < 0 {
                    if io::Error::last_os_error().raw_os_error() == Some(105) {
                        network_event = true;
                    }
                    break;
                }
                if n == 0 {
                    return Err(error("netlink EOF"));
                }
                network_event = true;
            }
            route = route_key(conf);
            if network_event && (lan != previous_lan || route.is_none() || route != previous_route) {
                invalidate = true;
            }
        }
        if invalidate {
            if busy {probe_deadline=Some(std::time::Instant::now()+std::time::Duration::from_secs(5));}
            if let Some(worker)=&worker{worker.0.store(true,std::sync::atomic::Ordering::Release);}
            generation += 1;
            let (s,r,p)=connection_check(&protocol,conf,lan);status=s;reason=r.into();pending=p;
            publish(&key, &protocol, status, generation, &reason,route.as_deref())?;
        }
        if fds[0].revents != 0 {
            let mut b = [0u8; 256];
            while let Ok(n) = control.recv(&mut b) {
                let msg = std::str::from_utf8(&b[..n]).unwrap_or("");
                let parts: Vec<_> = msg.split_whitespace().collect();
                match parts.as_slice() {
                    ["stop"] => return Ok(()),
                    ["pause"] => {
                        paused = true;
                        if let Some(worker)=&worker{worker.0.store(true,std::sync::atomic::Ordering::Release);}
                    }
                    ["resume"] => {
                        let _=fs::write(dir.join("daemon-refresh"),b"refresh");
                        paused = false;
                        generation += 1;
                        lan=available_network(dir);
                        let (s,r,p)=connection_check(&protocol,conf,lan);status=s;reason=r.into();pending=p;
                    }
                    ["refresh"] if !busy && !paused => {
                        let _=fs::write(dir.join("daemon-refresh"),b"refresh");
                        generation += 1;
                        lan=available_network(dir);
                        let (s,r,p)=connection_check(&protocol,conf,lan);status=s;reason=r.into();pending=p;
                    }
                    ["failure", details @ ..] if details.len()<=1 => {
                        if let Some(worker)=&worker{worker.0.store(true,std::sync::atomic::Ordering::Release);}
                        if busy{probe_deadline=Some(std::time::Instant::now()+std::time::Duration::from_secs(5));}
                        lan=available_network(dir);
                        reason=probe_reason(details.first().copied().unwrap_or("connection_failed"),lan||!target_requires_lan(conf)).to_string();
                        generation += 1;
                        status = "offline";
                        pending = false;
                        failure = true;
                    }
                    ["result", g, s, details @ ..] if details.len()<=1 => {
                        if g.parse::<u64>().ok()!=active_generation {continue;}
                        busy = false;
                        active_generation=None;
                        worker=None;
                        probe_deadline = None;
                        if !paused && g.parse::<u64>().ok() == Some(generation)
                            && matches!(*s, "ready" | "offline")
                        {
                            lan=available_network(dir);
                            reason=probe_reason(details.first().copied().unwrap_or("connection_failed"),lan||!target_requires_lan(conf)).to_string();
                            status = if protocol == "local" {
                                "local"
                            } else if *s == "ready" {
                                "ready"
                            } else {
                                "offline"
                            };
                            publish(&key, &protocol, status, generation, &reason,route.as_deref())?;
                        }
                    }
                    _ => {}
                }
            }
        }
        if pending && !busy && !failure && !paused {
            pending = false;
            busy = true;
            probe_deadline = Some(std::time::Instant::now() + std::time::Duration::from_secs(60));
            worker=Some(begin_probe(conf,dir,generation)?);
            active_generation=Some(generation);
        }
        publish(&key, &protocol, status, generation, &reason,route.as_deref())?;
        if fds[3].revents != 0 {
            clients.retain(|c| {
                let mut p = PollFd { fd: c.as_raw_fd(), events: POLLIN, revents: 0 };
                (unsafe { poll(&mut p, 1, 0) }) == 0
            });
            while let Ok((mut c, _)) = subscribers.accept() {
                c.set_write_timeout(Some(std::time::Duration::from_millis(200)))?;
                if clients.len() < 8 && c.write_all((snapshot(conf,dir).to_string()+"\n").as_bytes()).is_ok() {
                    clients.push(c);
                }
            }
        }
    }
}
pub fn stream(mut tcp: TcpStream, conf: PathBuf, dir: PathBuf) -> io::Result<()> {
    let mut events = UnixStream::connect(dir.join("events"))?;
    tcp.set_write_timeout(Some(std::time::Duration::from_secs(3)))?;
    tcp.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")?;
    loop {
        let mut fds = [
            PollFd {
                fd: events.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            },
            PollFd {
                fd: tcp.as_raw_fd(),
                events: POLLIN,
                revents: 0,
            },
        ];
        if unsafe { poll(fds.as_mut_ptr(), 2, -1) } < 0 {
            if io::Error::last_os_error().kind() == io::ErrorKind::Interrupted {
                continue;
            }
            return Err(io::Error::last_os_error());
        }
        if fds[1].revents != 0 {
            return Ok(());
        }
        let mut b = [0u8; 4096];
        let n = events.read(&mut b)?;
        if n == 0 {
            let mut last=snapshot(&conf,&dir);
            last["lanAvailable"]=json!(false);
            if last["status"]!="local" {
                last["status"]=json!("offline");
                if last["reason"].as_str().unwrap_or("").is_empty(){last["reason"]=json!("monitor_stopped");}
            }
            writeln!(tcp, "{}", last)?;
            return Ok(());
        }
        tcp.write_all(&b[..n])?;
        tcp.flush()?;
    }
}
fn network_events(dir: &Path) -> io::Result<()> {
    let events = UnixStream::connect(dir.join("events"))?;
    let mut previous=String::new();
    for line in BufReader::new(events).lines() {
        let value:Value=serde_json::from_str(&line?)?;
        let current=json!([value["protocol"],value["status"],value["generation"]]).to_string();
        if current!=previous {println!("NETLINK_OVERRUN");io::stdout().flush()?;previous=current;}
    }
    Err(error("health event stream closed"))
}
pub fn command(args: &[String]) -> i32 {
    let run = || -> io::Result<i32> {
        match args.first().map(String::as_str) {
            Some("watch") if args.len() == 4 => {
                watch(
                    Path::new(&args[1]),
                    Path::new(&args[2]),
                    args[3].parse().map_err(|_| error("owner"))?,
                )?;
                Ok(0)
            }
            Some("network-events") if args.len() == 2 => {
                network_events(Path::new(&args[1]))?;
                Ok(0)
            }
            Some("event") if args.len() == 3 => {
                event(Path::new(&args[1]), &args[2])?;
                Ok(0)
            }
            Some("ready") if args.len() == 3 => Ok(
                if snapshot(Path::new(&args[1]), Path::new(&args[2]))["status"] == "ready" {
                    0
                } else {
                    1
                },
            ),
            _ => Err(error("remote-health arguments")),
        }
    };
    match run() {
        Ok(rc) => rc,
        Err(e) => {
            eprintln!("REMOTE_HEALTH_ERROR {e}");
            1
        }
    }
}

#[cfg(test)] mod reason_tests {
    #[test] fn state_publish_rejects_symlink_and_preserves_target(){
        use std::{fs,os::unix::fs::symlink};
        let dir=std::env::temp_dir().join(format!("sb-review-state-{}",std::process::id()));
        fs::create_dir(&dir).unwrap();
        let target=dir.join("target");fs::write(&target,b"untouched").unwrap();
        symlink(&target,dir.join("state.new")).unwrap();
        assert!(super::atomic(&dir,&serde_json::json!({"status":"ready"})).is_err());
        assert_eq!(fs::read(&target).unwrap(),b"untouched");
        fs::remove_file(dir.join("state.new")).unwrap();
        super::atomic(&dir,&serde_json::json!({"status":"ready"})).unwrap();
        assert_eq!(fs::read_to_string(dir.join("state")).unwrap(),"{\"status\":\"ready\"}");
        fs::remove_dir_all(dir).unwrap();
    }
    #[test] fn known_network_metadata_overrides_stale_interfaces(){
        let mut v=serde_json::json!({"networkKnown":true,"sharingKnown":true,"links":[{"kind":"cellular"}],"sharing":[]});
        assert!(!super::network_from_metadata(&v));
        assert_eq!(super::display_reason("no_lan",&v),"no_lan_cellular");
        v["networkKnown"]=serde_json::json!(false);assert_eq!(super::display_reason("no_lan",&v),"no_lan");
        v["networkKnown"]=serde_json::json!(true);
        for kind in ["wifi","ethernet","vpn"]{v["links"]=serde_json::json!([{"kind":kind}]);assert!(super::network_from_metadata(&v));}
        v["links"]=serde_json::json!([]);assert!(!super::network_from_metadata(&v));
        for kind in ["hotspot","usb_tether"]{v["sharing"]=serde_json::json!([{"kind":kind}]);assert!(super::network_from_metadata(&v));}
    }
    #[test] fn local_targets_do_not_include_internet_or_loopback(){
        for host in ["192.168.1.2","10.0.0.1","172.16.0.1","169.254.1.2","fd00::1","fe80::1","nas.local"]{assert!(super::host_requires_lan(host),"{host}");}
        for host in ["127.0.0.1","::1","8.8.8.8","example.com","2001:4860:4860::8888"]{assert!(!super::host_requires_lan(host),"{host}");}
    }
    #[test] fn missing_lan_metadata_never_blocks_protocol_probe() {
        assert_eq!(super::next_check("smb"),("checking","",true));
        assert_eq!(super::next_check("webdav"),("checking","",true));
        assert_eq!(super::next_check("local"),("local","",false));
        assert_eq!(super::next_check("smb"),("checking","",true));
        assert!(super::usable_lan("eth0",true,false,false));
        assert!(super::usable_lan("wlan0",true,false,false));
        assert!(!super::usable_lan("wlan0",false,false,false));
        assert!(!super::usable_lan("rmnet_data0",true,false,false));
        assert!(!super::usable_lan("lo",true,true,false));
        // Android reports IFF_RUNNING for these even with Wi-Fi disabled.
        assert!(!super::usable_lan("dummy0",true,false,false));
        assert!(!super::usable_lan("r_rmnet_data0",true,false,false));
        assert!(!super::usable_lan("wifi-aware0",true,false,false));
    }
    #[test] fn wifi_standard_uses_reported_connection_not_band() {
        for (standard,expected) in [(0,"無法取得"),(1,"802.11a/b/g"),(4,"Wi-Fi 4"),(5,"Wi-Fi 5"),(6,"Wi-Fi 6"),(7,"802.11ad"),(8,"Wi-Fi 7"),(99,"無法取得")] {
            let metadata=serde_json::json!({"connected":true,"wifiStandard":standard,"frequencyMhz":6135,"links":[{"interface":"wlan0","kind":"wifi"}]});
            let display=super::network_display(&metadata,Some("dev=wlan0"),true);
            assert_eq!(display["rows"].as_array().unwrap().len(),6);
            assert_eq!(display["rows"][0]["caption"],if expected=="無法取得"{"Wi-Fi"}else{expected});
        }
    }
    #[test] fn wifi_link_rate_is_reported_not_estimated() {
        for (rate,expected) in [(5764,"5764 Mbps"),(0,"無法取得"),(-1,"無法取得")] {
            let wifi=serde_json::json!({"connected":true,"linkSpeedMbps":rate});
            let view=super::network_display(&wifi,None,true);
            assert_eq!(view["rows"].as_array().unwrap().last().unwrap()["caption"],expected);
            let offline=super::network_display(&serde_json::json!({"connected":false,"linkSpeedMbps":rate}),None,false);
            assert!(!offline["rows"].as_array().unwrap().iter().any(|r|r["label"]=="連線速率"));
        }
    }
    #[test] fn tether_route_wins_over_upstream_wifi() {
        let metadata=serde_json::json!({"available":true,"connected":true,"frequencyMhz":6135,"rssiDbm":-55,"links":[{"interface":"wlan0","kind":"wifi"}],"sharing":[{"interface":"vendor_usb42","kind":"usb_tether"},{"interface":"oem_ap7","kind":"hotspot"}]});
        let usb=super::network_display(&metadata,Some("dev=vendor_usb42|src=192.168.42.129"),true);
        assert_eq!(usb["kind"],"usb_tether");assert_eq!(usb["rows"].as_array().unwrap().len(),1);
        assert!(usb["detail"].as_str().unwrap().contains("USB 網路分享中"));
        let hotspot=super::network_display(&metadata,Some("dev=oem_ap7"),true);
        assert_eq!(hotspot["kind"],"hotspot");assert_eq!(hotspot["rows"].as_array().unwrap().len(),1);
        let wifi=super::network_display(&metadata,Some("dev=wlan0"),true);
        assert_eq!(wifi["rows"][3]["caption"],"-55 dBm 很好");
        let unknown=super::network_display(&serde_json::json!({}),Some("dev=custom0"),true);
        assert_eq!(unknown["detail"],"");
        assert_eq!(super::probe_reason("auth_failed",false),"auth_failed");
        assert_eq!(super::probe_reason("connection_failed",false),"no_lan");
    }
    #[test] fn discovery_failure_reports_missing_network_without_overriding_auth() {
        let cellular=serde_json::json!({"networkKnown":true,"sharingKnown":true,"sharing":[],"links":[{"kind":"cellular"}]});
        assert!(!super::metadata_has_local_path(&cellular));
        assert_eq!(super::display_reason(super::probe_reason("discovery_failed",false),&cellular),"no_lan_cellular");
        assert_eq!(super::probe_reason("discovery_failed",true),"discovery_failed");
        for reason in ["auth_failed","access_denied","account_missing","invalid_address","discovery_unconfigured"] {
            assert_eq!(super::probe_reason(reason,false),reason);
        }
        for kind in ["wifi","ethernet","vpn","network"] {
            let v=serde_json::json!({"networkKnown":true,"sharingKnown":true,"sharing":[],"links":[{"kind":kind}]});
            assert!(super::metadata_has_local_path(&v));
            assert_eq!(super::display_reason("no_lan",&v),"no_lan");
        }
        for kind in ["usb_tether","hotspot","bluetooth_tether","ethernet_tether","tether"] {
            let mut v=cellular.clone();v["sharing"]=serde_json::json!([{"kind":kind}]);
            assert!(super::metadata_has_local_path(&v));
        }
        assert_eq!(super::display_reason("no_lan",&serde_json::json!({})),"no_lan");
        assert_eq!(super::next_check("webdav"),("checking","",true));
    }
    #[test] fn reasons_are_fixed_codes_not_server_text() {
        assert_eq!(super::safe_reason("auth_failed"),"auth_failed");
        assert_eq!(super::safe_reason("password=private\nserver reply"),"connection_failed");
    }
}
