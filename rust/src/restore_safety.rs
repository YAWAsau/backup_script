//! Process-lifetime directory leases. App repair lives in android_policy.rs.
//! The flock serializes lease changes only; the shell's PID/start/boot identity
//! owns the directory until release or verified process death.
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::raw::{c_int, c_void};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::path::Path;
use std::time::Instant;

// Use su's own version identity, not installed packages or stale manager directories.
// Official su interfaces and Neo Backup's existing mount-master/nsenter recipes:
// https://github.com/tiann/KernelSU/blob/main/userspace/ksud/src/su.rs
// https://github.com/topjohnwu/Magisk/blob/master/docs/tools.md
// https://github.com/NeoApplications/Neo-Backup/blob/main/src/main/java/com/machiav3lli/backup/manager/handler/ShellHandler.kt
fn root_manager(version:&str)->(&'static str,&'static str) {
    let id=version.trim().to_ascii_lowercase();
    let ksu=id.contains("kernelsu")||id.contains("sukisu")||id.contains("bakasu");
    let apatch=id.contains("apatch")||id.contains("kernelpatch");
    let magisk=id.contains("magisk")||id.contains("kitsune");
    if ksu as u8+apatch as u8+magisk as u8!=1 {return ("unknown","未辨識");}
    if ksu {
        ("kernelsu",if id.contains("bakasu"){"BakaSU"}else if id.contains("resukisu"){"ReSukiSU"}else if id.contains("sukisu"){"SukiSU"}
        else if id.contains("kernelsu-next")||id.contains("kernelsu next"){"KernelSU-Next"}
        else {"KernelSU 相容實作（分支未辨識）"})
    } else if apatch {("apatch",if id.contains("apatch"){"APatch"}else{"KernelPatch 相容實作（管理器未辨識）"})}
    else {("magisk",if id.contains("kitsune"){"Kitsune Mask"}else{"Magisk 相容實作（分支未辨識）"})}
}
fn mount_help_for_version(version:&str)->String {
    let (kind,manager)=root_manager(version);
    let settings=match kind {
        "kernelsu"=>"KernelSU／Next／SukiSU／ReSukiSU／BakaSU：先在超級使用者頁允許 Root，再選擇 實際啟動腳本的 App（桌面捷徑為 SpeedBackup；手動執行則為 MT／終端）→ Root 設定檔 → 掛載命名空間 → 全域；若正在使用預設設定，先切換為自訂並儲存。",
        "magisk"=>"Magisk／Kitsune：設定 → 超級使用者 → 掛載命名空間模式 → 全域命名空間。此設定影響其他 Root 工作階段；也可只用下方指令啟動本次工作。",
        "apatch"=>"APatch／KernelPatch：先在超級使用者頁授權實際啟動腳本的 App。若 su 不支援 --mount-master，可在終端執行 su -c 'nsenter --mount=/proc/1/ns/mnt sh' 進入全域環境。",
        _=>"無法可靠辨識目前的 su；請先在 Root 管理器授權實際啟動腳本的 App。若 su 不支援 --mount-master，可使用 su -c 'nsenter --mount=/proc/1/ns/mnt sh'。",
    };
    format!("目前 su：{manager}。{settings} 操作：關閉舊終端／工作階段，重新開啟終端並執行 su --mount-master，再執行 /system/bin/sh '/實際路徑/start.sh'（替換為本次備份或恢復入口）。桌面捷徑可關閉啟動畫面後重新點選；已自動要求全域掛載。重試仍未通過檢查時不要繼續操作。")
}
fn su_version()->String {
    std::process::Command::new("/system/bin/timeout").args(["2","su","-v"])
        .stdin(std::process::Stdio::null()).stderr(std::process::Stdio::null()).output()
        .ok().filter(|o|o.status.success()).map(|o|String::from_utf8_lossy(&o.stdout).chars().filter(|c| !c.is_control()).take(256).collect()).unwrap_or_default()
}
fn mount_help()->String { let version=su_version(); let info=manager_details(&version); format!("{} {}",info,mount_help_for_version(&version)) }
pub fn root_manager_command(args:&[String])->i32 {
    if !args.is_empty() {return 64;}
    let version=su_version();let (kind,_)=root_manager(&version);
    let display=manager_details(&version);
    // Separate stable identity from user-facing version, no shell parsing heuristics.
    match writeln!(io::stdout().lock(),"{kind}\n{display}"){Ok(())=>0,Err(_)=>74}
}

// Read-only upstream ABI, pinned source references in README. Run in a short-lived
// subprocess: kernels can block the driver acquisition syscall with SIGSYS.
// Never infer a kernel branch from its numeric version, feature support or APK inventory.
fn bounded_output(program:&str,args:&[&str])->Option<String> {
    let out=std::process::Command::new("/system/bin/timeout").arg("2").arg(program).args(args)
        .stdin(std::process::Stdio::null()).stderr(std::process::Stdio::null()).output().ok()?;
    if !out.status.success() || out.stdout.len()>65536 {return None;}
    String::from_utf8(out.stdout).ok()
}
fn manager_package(output:&str,appid:u32)->Option<String> {
    let mut packages=std::collections::BTreeSet::new();
    for line in output.lines() {
        let mut parts=line.split_whitespace();
        let package=parts.next()?.strip_prefix("package:")?;
        let uid=parts.next()?.strip_prefix("uid:")?.parse::<u32>().ok()?;
        if uid!=appid || parts.next().is_some() || package.is_empty() || !package.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'.'||b==b'_') {return None;}
        packages.insert(package.to_owned());
    }
    if packages.len()==1 {packages.into_iter().next()}else{None}
}
fn package_name(package:&str)->&str {
    match package {
        "com.sukisu.ultra"=>"SukiSU Ultra",
        "com.rifsxd.ksunext"=>"KernelSU Next",
        // BakaSU retains ReSukiSU's applicationId: the package alone cannot split them.
        "com.resukisu.resukisu"=>"BakaSU／ReSukiSU",
        "me.weishu.kernelsu"=>"KernelSU",
        _=>"自訂管理器",
    }
}
fn manager_details(version:&str)->String {
    let (kind,name)=root_manager(version);
    let base=format!("{name}\nsu: {}",if version.is_empty(){"未取得"}else{version});
    if kind!="kernelsu" {return base;}
    let Some(exe)=std::env::current_exe().ok() else{return base;};
    let Some(raw)=bounded_output(&exe.to_string_lossy(),&["speedscan","root-manager-kernel-info"]) else{return base;};
    let mut lines=raw.lines();
    let Some(appid)=lines.next().and_then(|s|s.parse::<u32>().ok()).filter(|n| (10000..100000).contains(n)) else{return base;};
    let uid=appid.to_string();
    let package=bounded_output("/system/bin/cmd",&["package","list","packages","-U","--user","0","--uid",&uid])
        .and_then(|s|manager_package(&s,appid));
    let label=package.as_deref().map(package_name).unwrap_or(name);
    format!("{label}\nsu: {}",if version.is_empty(){"未取得"}else{version})
}
pub fn root_manager_kernel_command(args:&[String])->i32 {
    if !args.is_empty(){return 64;}
    #[cfg(all(target_os="android",target_arch="aarch64"))]
    {
        extern "C" {fn ioctl(fd:c_int,request:std::os::raw::c_ulong,argp:*mut c_void)->c_int;}
        // KSU_INSTALL_MAGIC*, same acquisition protocol used by upstream ksucalls.rs.
        // Invalid Linux reboot magic means this cannot reboot a non-KSU kernel.
        let mut fd:c_int=-1;
        unsafe {speedbackup_native_rs::syscall(142,0xDEADBEEFu32 as std::os::raw::c_ulong,0xCAFEBABEu32 as std::os::raw::c_ulong,0usize,&mut fd);}
        if fd<0 {return 69;}
        let driver=unsafe{File::from_raw_fd(fd)};
        let mut info=[0u32;4];
        let mut appid=u32::MAX;
        unsafe {
            if ioctl(driver.as_raw_fd(),0x80104b02u64,info.as_mut_ptr().cast())<0 && ioctl(driver.as_raw_fd(),0x80004b02u64,info.as_mut_ptr().cast())<0 {return 69;}
            if info[0]==0 || ioctl(driver.as_raw_fd(),0x80004b0au64,(&mut appid as *mut u32).cast())<0 {return 69;}
        }
        let mut full=[0u8;255];let mut tag=[0u8;32];
        let full_ok=unsafe{ioctl(driver.as_raw_fd(),0x80004b64u64,full.as_mut_ptr().cast())}>=0;
        let tag_ok=unsafe{ioctl(driver.as_raw_fd(),0x80004b63u64,tag.as_mut_ptr().cast())}>=0;
        let value=if full_ok{clean_kernel_string(&full)}else if tag_ok{clean_kernel_string(&tag)}else{String::new()};
        return match writeln!(io::stdout().lock(),"{appid}\n{value}"){Ok(())=>0,Err(_)=>74};
    }
    #[cfg(not(all(target_os="android",target_arch="aarch64")))]
    {69}
}
fn clean_kernel_string(data:&[u8])->String {
    let Some(end)=data.iter().position(|b|*b==0) else{return String::new();};
    let Ok(value)=std::str::from_utf8(&data[..end]) else{return String::new();};
    if value.chars().any(char::is_control){String::new()}else{value.to_owned()}
}

// Root credentials alone do not escape Android's app-data mount isolation.
// Check directory identity against init's view before any backup/restore work.
pub fn app_data_namespace() -> io::Result<()> {
    let check = || -> io::Result<()> {
        for path in ["/data/data", "/data/user", "/data/user_de"] {
            let local = fs::metadata(path).map_err(|e| io::Error::other(format!("無法讀取 {path}：{e}")))?;
            let global = fs::metadata(format!("/proc/1/root{path}")).map_err(|e| io::Error::other(format!("無法讀取全域 {path}：{e}")))?;
            if !local.is_dir() || !global.is_dir() || local.dev()!=global.dev() || local.ino()!=global.ino() {
                return Err(io::Error::other(format!("應用資料掛載環境不一致：{path}")));
            }
        }
        Ok(())
    };
    check().map_err(|e| io::Error::other(format!("警告：應用資料掛載環境被隔離或無法驗證。已禁止備份、恢復與後續操作，避免漏備份或寫入錯誤目錄；請使用全域掛載環境（su --mount-master）重新啟動。原因：{e} {}",mount_help())))
}

pub fn app_data_namespace_command(args: &[String]) -> i32 {
    if !args.is_empty() { return 64; }
    match app_data_namespace() {
        Ok(()) => { println!("STORAGE_NAMESPACE_OK appData=global"); 0 },
        Err(e) => { eprintln!("STORAGE_NAMESPACE_FAILED {e}"); 65 }
    }
}

struct StopProcess {
    pid: u32,
    token: String,
    fd: File,
    resume: bool,
}
impl StopProcess {
    fn signal(&self, signal: i32) -> io::Result<()> {
        // pidfd pins the process, including across PID reuse. No numeric-PID fallback.
        let rc = unsafe {
            speedbackup_native_rs::syscall(
                424 as std::os::raw::c_long,
                self.fd.as_raw_fd(),
                signal,
                std::ptr::null::<c_void>(),
                0u32,
            )
        };
        if rc == 0 {
            Ok(())
        } else {
            Err(io::Error::last_os_error())
        }
    }
    fn exited(&self) -> io::Result<bool> {
        let mut p = speedbackup_native_rs::PollFd {
            fd: self.fd.as_raw_fd(),
            events: 1,
            revents: 0,
        };
        let rc = unsafe { speedbackup_native_rs::poll(&mut p, 1, 0) };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(p.revents & 1 != 0)
    }
}
impl Drop for StopProcess {
    fn drop(&mut self) {
        // A failed scan must not leave processes frozen by this controller.
        if self.resume {
            let _ = self.signal(18);
        }
    }
}
fn process_parent_state(pid: u32) -> io::Result<(u32, char)> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let tail = speedbackup_native_rs::proc_stat::split(&stat).ok_or(io::ErrorKind::InvalidData)?.1;
    let mut fields = tail.split_whitespace();
    let state = fields
        .next()
        .and_then(|x| x.chars().next())
        .ok_or(io::ErrorKind::InvalidData)?;
    let parent = fields
        .next()
        .ok_or(io::ErrorKind::InvalidData)?
        .parse()
        .map_err(|_| io::ErrorKind::InvalidData)?;
    Ok((parent, state))
}
fn stop_process(pid: u32, token: &str) -> io::Result<StopProcess> {
    let fd = speedbackup_native_rs::pidfd_open(pid as i32)?;
    let mut p = StopProcess {
        pid,
        token: token.into(),
        fd: unsafe { File::from_raw_fd(fd) },
        resume: false,
    };
    match identity(pid) {
        Ok(live) if live == token => (),
        Err(_) if p.exited()? => return Ok(p),
        Err(e) => return Err(e),
        _ => return Err(io::ErrorKind::PermissionDenied.into()),
    }
    let state = match process_parent_state(pid) {
        Ok(v) => v.1,
        Err(_) if p.exited()? => return Ok(p),
        Err(e) => return Err(e),
    };
    if state != 'T' && state != 't' && !p.exited()? {
        p.resume = true;
        if let Err(e) = p.signal(19) {
            if !p.exited()? { return Err(e); }
        }
    }
    let start = Instant::now();
    while !p.exited()? {
        match process_parent_state(pid) {
            Ok((_, 'T' | 't')) => break,
            Ok(_) => (),
            Err(_) if p.exited()? => break,
            Err(e) => return Err(e),
        }
        if start.elapsed().as_millis() > 1000 {
            return Err(io::ErrorKind::TimedOut.into());
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    Ok(p)
}

// Legacy releases wrote only pid. Never invent an owner record for them.
// Snapshot a root-owned, non-writable lease and a verified script process before
// user confirmation, then recheck both inode and process identity at stop time.
fn legacy_lease(path:&Path)->io::Result<(u32,u64,u64)> {
    let m=fs::symlink_metadata(path)?;
    if !m.is_dir()||m.file_type().is_symlink()||m.uid()!=0||m.mode()&0o022!=0{return Err(io::ErrorKind::PermissionDenied.into());}
    for e in fs::read_dir(path)?{if e?.file_name()!="pid"{return Err(io::ErrorKind::PermissionDenied.into());}}
    let f=OpenOptions::new().read(true).custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(path.join("pid"))?;
    let p=f.metadata()?;
    if !p.is_file()||p.uid()!=0||p.nlink()!=1||p.mode()&0o022!=0||p.len()>64{return Err(io::ErrorKind::PermissionDenied.into());}
    let mut raw=String::new();f.take(65).read_to_string(&mut raw)?;
    let pid=raw.trim().parse::<u32>().ok().filter(|p|*p>1&&*p<=i32::MAX as u32).ok_or(io::ErrorKind::InvalidData)?;
    Ok((pid,m.dev(),m.ino()))
}
fn bounded_script_source(path: &Path, limit: u64) -> io::Result<String> {
    let file=OpenOptions::new().read(true)
        .custom_flags(speedbackup_native_rs::O_NONBLOCK | speedbackup_native_rs::O_NOFOLLOW_NATIVE).open(path)?;
    if !file.metadata()?.is_file(){return Err(io::ErrorKind::PermissionDenied.into());}
    let mut source=String::new();file.take(limit+1).read_to_string(&mut source)?;
    if source.len() as u64>limit{return Err(io::ErrorKind::InvalidData.into());}
    Ok(source)
}
fn legacy_entry_source_verified(script: &Path) -> io::Result<bool> {
    let source=bounded_script_source(script,131072)?;
    if source.contains("tools.sh")&&(source.contains("SpeedBackup")||source.contains("kill_Serve")){return Ok(true);}
    // Historical wrappers have no product marker: require their exact relative
    // source invocation plus the adjacent implementation's product/lease markers.
    // This only permits a confirmation snapshot, never automatic stop or cleanup.
    if !source.lines().any(|line|line.trim()==r#". "${0%/*}/tools/tools.sh" | tee "$logfile""#){return Ok(false);}
    let tools=script.parent().ok_or(io::ErrorKind::InvalidInput)?.join("tools/tools.sh");
    let body=bounded_script_source(&tools,1048576)?;
    Ok(body.contains("# SpeedBackup tools.sh")&&body.contains("kill_Serve()")&&body.contains("/data/.backup_lock"))
}
fn legacy_script_identity(pid:u32)->io::Result<String>{
    let token=identity(pid)?;
    if fs::metadata(format!("/proc/{pid}"))?.uid()!=0{return Err(io::ErrorKind::PermissionDenied.into());}
    let raw=fs::read(format!("/proc/{pid}/cmdline"))?;
    if raw.len()>65536{return Err(io::ErrorKind::InvalidData.into());}
    let args:Vec<_>=raw.split(|b|*b==0).filter(|s|!s.is_empty()).collect();
    let shell=args.first().and_then(|s|std::str::from_utf8(s).ok()).and_then(|s|Path::new(s).file_name()).and_then(|s|s.to_str()).unwrap_or("");
    if !matches!(shell,"sh"|"bash"|"mksh"){return Err(io::ErrorKind::PermissionDenied.into());}
    let script=std::str::from_utf8(args.get(1).ok_or(io::ErrorKind::InvalidData)?).map_err(|_|io::ErrorKind::InvalidData)?;
    if !matches!(Path::new(script).file_name().and_then(|s|s.to_str()),Some("start.sh"|"recover.sh")){return Err(io::ErrorKind::PermissionDenied.into());}
    let script=if Path::new(script).is_absolute(){Path::new(script).to_owned()}else{fs::read_link(format!("/proc/{pid}/cwd"))?.join(script)};
    if !legacy_entry_source_verified(&script)?{return Err(io::ErrorKind::PermissionDenied.into());}
    if identity(pid)?!=token{return Err(io::ErrorKind::PermissionDenied.into());}Ok(token)
}
pub fn lock_legacy_snapshot(args:&[String])->i32{
    if args.len()!=1{return 2;}
    let result=(||->io::Result<String>{let p=Path::new(&args[0]);let _g=guard(p)?;let(pid,dev,ino)=legacy_lease(p)?;let token=legacy_script_identity(pid)?;Ok(format!("legacy:{token}:{dev}:{ino}"))})();
    match result{Ok(s)=>{println!("{s}");0},Err(e)=>{eprintln!("LOCK_LEGACY_UNVERIFIED error={e}");1}}
}

/// Stop only the lease snapshot selected by the user, never a replacement owner.
pub fn lock_stop(args: &[String]) -> i32 { lock_stop_impl(args,None) }
fn lock_stop_impl(args: &[String], pinned_owner:Option<&StopProcess>) -> i32 {
    if args.len() != 2 {
        return 2;
    }
    let mut stage = "guard";
    let result = (|| -> io::Result<usize> {
        let path = Path::new(&args[0]);
        let legacy=args[1].strip_prefix("legacy:");
        let mut legacy_stamp=None;
        let legacy_token;
        let expected=if let Some(raw)=legacy{
            let parts:Vec<_>=raw.split(':').collect();
            if parts.len()!=5{return Err(io::ErrorKind::InvalidData.into());}
            legacy_token=parts[..3].join(":");
            legacy_stamp=Some((parts[3].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?,parts[4].parse::<u64>().map_err(|_|io::ErrorKind::InvalidData)?));
            &legacy_token
        }else{&args[1]};
        let _guard = guard(path)?;
        stage = "lease_directory";
        if let Some(owner)=pinned_owner {
            if owner.token!=*expected || owner.exited()? {return Err(io::ErrorKind::PermissionDenied.into());}
        }else{
            let meta = fs::symlink_metadata(path)?;
            if !meta.is_dir() || meta.file_type().is_symlink() {return Err(io::ErrorKind::PermissionDenied.into());}
            if let Some((dev,ino))=legacy_stamp{
                stage="legacy_owner_identity";
                let(pid,d,i)=legacy_lease(path)?;
                if (d,i)!=(dev,ino)||legacy_script_identity(pid)?!=*expected{return Err(io::ErrorKind::PermissionDenied.into());}
            }else{
                stage = "owner_record";
                if fs::read_to_string(path.join("owner"))?.trim() != expected {return Err(io::ErrorKind::PermissionDenied.into());}
            }
        }
        let pid_raw = if let Some(owner)=pinned_owner {owner.pid.to_string()}else{match fs::read_to_string(path.join("pid")) {
            Ok(value) => value,
            Err(e) if e.kind() == io::ErrorKind::NotFound => expected
                .split(':')
                .next()
                .ok_or(io::ErrorKind::InvalidData)?
                .to_owned(),
            Err(e) => return Err(e),
        }};
        let pid: u32 = pid_raw
            .trim()
            .parse()
            .map_err(|_| io::ErrorKind::InvalidData)?;
        stage = "owner_process_identity";
        if pid <= 1 || pid > i32::MAX as u32 || identity(pid)? != *expected {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        // Never terminate this controller, or a parent whose death could kill it.
        stage = "controller_ancestors";
        let mut ancestor = std::process::id();
        for _ in 0..256 {
            if ancestor == pid {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            if ancestor <= 1 {
                break;
            }
            ancestor = process_parent_state(ancestor)?.0;
        }
        stage = "freeze_owner";
        let mut processes = vec![stop_process(pid, expected)?];
        stage = "scan_freeze_descendants";
        let started = Instant::now();
        loop {
            let before = processes.len();
            for entry in fs::read_dir("/proc")? {
                let entry = entry?;
                let child = match entry.file_name().to_string_lossy().parse::<u32>() {
                    Ok(p) if p > 1 => p,
                    _ => continue,
                };
                if processes.iter().any(|p| p.pid == child) {
                    continue;
                }
                let (parent, _) = match process_parent_state(child) {
                    Ok(v) => v,
                    Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(e),
                };
                if !processes.iter().any(|p| {
                    p.pid == parent && identity(parent).ok().as_deref() == Some(p.token.as_str())
                }) {
                    continue;
                }
                let token = match identity(child) {
                    Ok(t) => t,
                    Err(e) if e.kind() == io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(e),
                };
                match stop_process(child, &token) {
                    Ok(p) => processes.push(p),
                    Err(e)
                        if e.raw_os_error() == Some(3) || e.kind() == io::ErrorKind::NotFound => {}
                    Err(e) => return Err(e),
                }
            }
            if processes.len() == before {
                break;
            }
            if processes.len() > 4096 || started.elapsed().as_secs() >= 8 {
                return Err(io::ErrorKind::TimedOut.into());
            }
        }
        // Frozen parents cannot create new workers. Kill children before their owner.
        stage = "kill_pinned_processes";
        for p in processes.iter().rev() {
            if !p.exited()? {
                if let Err(e) = p.signal(9) {
                    if !p.exited()? { return Err(e); }
                }
            }
        }
        stage = "wait_pidfd_exit";
        let deadline = Instant::now();
        loop {
            let mut pending = false;
            for p in &processes {
                if !p.exited()? {
                    pending = true;
                }
            }
            if !pending {
                break;
            }
            if deadline.elapsed().as_secs() >= 5 {
                return Err(io::ErrorKind::TimedOut.into());
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
        let legacy_matches=legacy_stamp.is_some_and(|(dev,ino)|legacy_lease(path).ok()==Some((pid,dev,ino)));
        if legacy_matches || (legacy_stamp.is_none()&&fs::read_to_string(path.join("owner")).ok().as_deref().map(str::trim)==Some(expected.as_str())) {
            stage = "remove_verified_lease";
            remove_owned(path)?;
        }else if pinned_owner.is_none(){return Err(io::ErrorKind::PermissionDenied.into());}
        Ok(processes.len())
    })();
    match result {
        Ok(count) => {
            println!("LOCK_STOP_OK processes={count}");
            0
        }
        Err(e) if e.raw_os_error() == Some(38) => {
            eprintln!("LOCK_STOP_UNSUPPORTED reason=pidfd_unavailable owner_preserved=true");
            3
        }
        Err(e) => {
            eprintln!("LOCK_STOP_REFUSED_OR_INCOMPLETE stage={stage} error={e}");
            1
        }
    }
}

/// Graceful Ctrl+C-style cancellation for the supervisor's isolated worker
/// process group. No kill(-pgid): every recipient is pinned by pidfd.
/// Return 0 for graceful exit, 10 for forced exit, 1 for refusal/incomplete.
pub fn lock_cancel(args:&[String],grace:std::time::Duration)->i32 {
    let result=(||->io::Result<i32>{
        if args.len()!=2{return Err(io::ErrorKind::InvalidInput.into());}
        let path=Path::new(&args[0]);let expected=&args[1];
        let lease=guard(path)?;
        let meta=fs::symlink_metadata(path)?;
        if !meta.is_dir()||meta.file_type().is_symlink()||fs::read_to_string(path.join("owner"))?.trim()!=expected{return Err(io::ErrorKind::PermissionDenied.into());}
        let pid:u32=expected.split(':').next().unwrap_or("").parse().map_err(|_|io::ErrorKind::InvalidData)?;
        if pid<=1||identity(pid)?!=*expected{return Err(io::ErrorKind::PermissionDenied.into());}
        fn group(pid:u32)->io::Result<u32>{
            speedbackup_native_rs::proc_stat::field(&fs::read_to_string(format!("/proc/{pid}/stat"))?,2).ok_or(io::ErrorKind::InvalidData)?.parse().map_err(|_|io::ErrorKind::InvalidData.into())
        }
        // console-service creates this private group via setsid before exec.
        if group(pid)?!=pid||group(std::process::id())?==pid{return Err(io::ErrorKind::PermissionDenied.into());}
        let mut ancestor=std::process::id();
        for _ in 0..256{if ancestor==pid{return Err(io::ErrorKind::PermissionDenied.into());}if ancestor<=1{break;}ancestor=process_parent_state(ancestor)?.0;}
        let mut processes=vec![stop_process(pid,expected)?];let started=Instant::now();
        // Freeze briefly while snapshotting so foreground commands cannot fork
        // past the interrupt. This is done only on explicit cancellation.
        loop{
            let before=processes.len();
            for entry in fs::read_dir("/proc")?{
                let entry=entry?;let Ok(child)=entry.file_name().to_string_lossy().parse::<u32>()else{continue;};
                if child<=1||processes.iter().any(|p|p.pid==child)||group(child).ok()!=Some(pid){continue;}
                let Ok(token)=identity(child)else{continue;};
                match stop_process(child,&token){Ok(p)=>processes.push(p),Err(e)if e.raw_os_error()==Some(3)||e.kind()==io::ErrorKind::NotFound=>{},Err(e)=>return Err(e)}
            }
            if before==processes.len(){break;}
            if processes.len()>4096||started.elapsed().as_secs()>=3{return Err(io::ErrorKind::TimedOut.into());}
        }
        // Cleanup needs to release this lease: never hold its flock while waiting.
        drop(lease);
        for p in processes.iter().rev(){if !p.exited()?{if let Err(e)=p.signal(2){if !p.exited()?{return Err(e);}}}}
        for p in processes.iter_mut().rev(){if p.resume{let _=p.signal(18);p.resume=false;}}
        fn wait_all(processes:&[StopProcess],timeout:std::time::Duration)->io::Result<bool>{
            let start=Instant::now();
            loop{
                let mut fds=Vec::new();
                for p in processes{if !p.exited()?{fds.push(speedbackup_native_rs::PollFd{fd:p.fd.as_raw_fd(),events:1,revents:0});}}
                if fds.is_empty(){return Ok(true);}
                let remaining=timeout.saturating_sub(start.elapsed());if remaining.is_zero(){return Ok(false);}
                let ms=remaining.as_millis().min(i32::MAX as u128).max(1) as i32;
                let rc=unsafe{speedbackup_native_rs::poll(fds.as_mut_ptr(),fds.len() as _,ms)};
                if rc<0{let e=io::Error::last_os_error();if e.kind()!=io::ErrorKind::Interrupted{return Err(e);}}
            }
        }
        if wait_all(&processes,grace)?{println!("LOCK_CANCEL_GRACEFUL processes={}",processes.len());return Ok(0);}
        println!("LOCK_CANCEL_ESCALATE grace_ms={}",grace.as_millis());
        if !processes[0].exited()?{
            // Revalidate the lease and rescan descendants, including helpers
            // created by cleanup or running in a different process group.
            if lock_stop(args)!=0{eprintln!("LOCK_CANCEL_ESCALATE_PINNED lease released or changed; rescan original pinned owner only");if !processes[0].exited()?{let _=lock_stop_impl(args,Some(&processes[0]));}}
        }
        // A parent can exit leaving an ignored-INT child. These are old pinned
        // recipients, never a new lease owner or a numeric PID fallback.
        for p in processes.iter().rev(){if !p.exited()?{if let Err(e)=p.signal(9){if !p.exited()?{return Err(e);}}}}
        if !wait_all(&processes,std::time::Duration::from_secs(5))?{return Err(io::ErrorKind::TimedOut.into());}
        println!("LOCK_CANCEL_FORCED");Ok(10)
    })();
    match result{Ok(rc)=>rc,Err(e)=>{eprintln!("LOCK_CANCEL_REFUSED_OR_INCOMPLETE {e}");1}}
}

extern "C" {
    fn flock(fd: c_int, op: c_int) -> c_int;
    fn kill(pid: c_int, sig: c_int) -> c_int;
}

fn identity(pid: u32) -> io::Result<String> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat"))?;
    let tail = speedbackup_native_rs::proc_stat::split(&stat).ok_or(io::ErrorKind::InvalidData)?.1;
    let start = tail
        .split_whitespace()
        .nth(19)
        .ok_or(io::ErrorKind::InvalidData)?;
    let boot = fs::read_to_string("/proc/sys/kernel/random/boot_id")?;
    Ok(format!("{}:{}:{}", pid, start, boot.trim()))
}
fn guard(path: &Path) -> io::Result<File> {
    let mut name = path.as_os_str().to_os_string();
    name.push(".guard");
    let f = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(speedbackup_native_rs::O_NOFOLLOW_NATIVE)
        .open(name)?;
    let meta = f.metadata()?;
    if !meta.is_file() || meta.uid() != 0 || meta.nlink() != 1 {
        return Err(io::ErrorKind::PermissionDenied.into());
    }
    if unsafe { flock(f.as_raw_fd(), 2 | 4) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(f)
}
fn remove_owned(path: &Path) -> io::Result<()> {
    for name in ["owner", "pid"] {
        match fs::remove_file(path.join(name)) {
            Ok(()) => (),
            Err(e) if e.kind() == io::ErrorKind::NotFound => (),
            Err(e) => return Err(e),
        }
    }
    fs::remove_dir(path)
}
fn acquire(path: &Path, pid: u32) -> io::Result<String> {
    let token = identity(pid)?;
    let _guard = guard(path)?;
    if path.exists() {
        let meta = fs::symlink_metadata(path)?;
        if !meta.is_dir() || meta.file_type().is_symlink() {
            return Err(io::ErrorKind::PermissionDenied.into());
        }
        let old_raw = match fs::read_to_string(path.join("pid")) {
            Ok(value) => value,
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                // Old releases could die between mkdir/owner/pid. Never age out a
                // live owner; only remove a trusted incomplete lease under flock.
                if meta.uid() != 0 {
                    return Err(io::ErrorKind::PermissionDenied.into());
                }
                match fs::read_to_string(path.join("owner")) {
                    Ok(owner) => {
                        let old = owner
                            .trim()
                            .split(':')
                            .next()
                            .and_then(|x| x.parse::<u32>().ok())
                            .filter(|x| *x > 1 && *x <= i32::MAX as u32)
                            .ok_or(io::ErrorKind::InvalidData)?;
                        if identity(old)
                            .map(|live| live == owner.trim())
                            .unwrap_or(true)
                        {
                            // A missing process is distinguishable from unreadable /proc.
                            if unsafe { kill(old as i32, 0) } == 0
                                || io::Error::last_os_error().raw_os_error() != Some(3)
                            {
                                return Err(io::ErrorKind::AlreadyExists.into());
                            }
                        }
                    }
                    Err(e) if e.kind() == io::ErrorKind::NotFound => (),
                    Err(e) => return Err(e),
                }
                // Refuse unknown contents instead of recursive deletion.
                for entry in fs::read_dir(path)? {
                    if entry?.file_name() != "owner" {
                        return Err(io::ErrorKind::InvalidData.into());
                    }
                }
                remove_owned(path)?;
                return publish_lease(path, pid, &token);
            }
            Err(e) => return Err(e),
        };
        let old = old_raw
            .trim()
            .parse::<u32>()
            .map_err(|_| io::ErrorKind::InvalidData)?;
        if old <= 1 || old > i32::MAX as u32 {
            return Err(io::ErrorKind::InvalidData.into());
        }
        let recorded = fs::read_to_string(path.join("owner")).ok();
        if let Some(ref value) = recorded {
            let fields: Vec<_> = value.trim().split(':').collect();
            if fields.len() != 3
                || fields[0].parse::<u32>().ok() != Some(old)
                || fields[1].parse::<u64>().is_err()
                || fields[2].len() != 36
                || !fields[2]
                    .bytes()
                    .all(|b| b.is_ascii_hexdigit() || b == b'-')
            {
                return Err(io::ErrorKind::InvalidData.into());
            }
        }
        if let Ok(live) = identity(old) {
            if recorded.as_ref().map(|x| x.trim() == live).unwrap_or(true) {
                return Err(io::ErrorKind::AlreadyExists.into());
            }
        } else if unsafe { kill(old as i32, 0) } == 0
            || io::Error::last_os_error().raw_os_error() == Some(1)
        {
            return Err(io::ErrorKind::AlreadyExists.into());
        }
        remove_owned(path)?;
    }
    publish_lease(path, pid, &token)
}

fn publish_lease(path: &Path, pid: u32, token: &str) -> io::Result<String> {
    let parent = path.parent().ok_or(io::ErrorKind::InvalidInput)?;
    let nonce = fs::read_to_string("/proc/sys/kernel/random/uuid")?;
    let stage = parent.join(format!(".backup-lease-{}", nonce.trim()));
    fs::DirBuilder::new().mode(0o700).create(&stage)?;
    let result = (|| -> io::Result<String> {
        for (name, value) in [("owner", token.to_owned()), ("pid", pid.to_string())] {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(stage.join(name))?;
            file.write_all(value.as_bytes())?;
            file.sync_all()?;
        }
        File::open(&stage)?.sync_all()?;
        // All participants hold the same flock. No visible half-written lease.
        fs::rename(&stage, path)?;
        File::open(parent)?.sync_all()?;
        Ok(token.to_owned())
    })();
    if stage.exists() {
        let _ = remove_owned(&stage);
    }
    result
}
pub fn lock(args: &[String], release: bool) -> i32 {
    if args.len() != 2 {
        return 2;
    }
    let path = Path::new(&args[0]);
    if release {
        let result = (|| -> io::Result<()> {
            let _guard = guard(path)?;
            if !path.exists() {
                return Ok(());
            }
            let m = fs::symlink_metadata(path)?;
            if !m.is_dir() || m.file_type().is_symlink() {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            if fs::read_to_string(path.join("owner"))?.trim() != args[1] {
                return Err(io::ErrorKind::PermissionDenied.into());
            }
            remove_owned(path)
        })();
        return if result.is_ok() { 0 } else { 1 };
    }
    let pid = match args[1].parse::<u32>() {
        Ok(p) if p > 1 && p <= i32::MAX as u32 => p,
        _ => return 2,
    };
    match acquire(path, pid) {
        Ok(token) => {
            println!("{token}");
            0
        }
        Err(_) => {
            eprintln!("LOCK_BUSY_OR_UNVERIFIED");
            1
        }
    }
}

#[cfg(test)]
mod cancellation_tests {
 use super::*;
 use std::process::{Command,Stdio,Child};
 use std::os::unix::process::CommandExt;
 use std::time::Duration;
 unsafe extern "C" {fn setsid()->i32;fn signal(sig:i32,handler:usize)->usize;}
 struct Fixture{path:std::path::PathBuf,child:Child}
 impl Drop for Fixture{fn drop(&mut self){let _=self.child.kill();let _=self.child.wait();let _=fs::remove_dir_all(&self.path);}}
 fn fixture(script:&str)->Fixture{
  let path=std::path::PathBuf::from(format!("/data/local/tmp/sb-cancel-test-{}",fs::read_to_string("/proc/sys/kernel/random/uuid").unwrap().trim()));
  fs::create_dir(&path).unwrap();
  let mut cmd=Command::new("/system/bin/sh");cmd.arg("-c").arg(script).current_dir(&path).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
  unsafe{cmd.pre_exec(||{signal(2,0);if setsid()<0{return Err(io::Error::last_os_error());}Ok(())});}
  let child=cmd.spawn().unwrap();let f=Fixture{path,child};let start=Instant::now();while !f.path.join("ready").exists(){assert!(start.elapsed()<Duration::from_secs(3));std::thread::sleep(Duration::from_millis(5));}f
 }
 #[test]fn sigint_runs_cleanup_without_grace_delay(){
  let mut f=fixture("trap 'trap \"\" INT; echo INT > signal; exit 130' INT; trap 'ec=$?; sleep 0.15; echo cleaned > cleanup; exit \"$ec\"' EXIT; echo ready > ready; while :; do sleep 30; done");
  let lock=f.path.join("lease");let token=acquire(&lock,f.child.id()).unwrap();let start=Instant::now();
  assert_eq!(lock_cancel(&[lock.to_string_lossy().into(),token],Duration::from_secs(2)),0);
  assert!(start.elapsed()<Duration::from_secs(2));assert_eq!(f.child.wait().unwrap().code(),Some(130));assert!(f.path.join("signal").exists());assert!(f.path.join("cleanup").exists());
 }
 #[test]fn ignored_sigint_escalates_and_wrong_owner_is_refused(){
  let mut f=fixture("trap '' INT; echo ready > ready; while :; do sleep 30; done");let lock=f.path.join("lease");let token=acquire(&lock,f.child.id()).unwrap();
  assert_eq!(lock_cancel(&[lock.to_string_lossy().into(),format!("{token}-wrong")],Duration::from_millis(100)),1);assert!(f.child.try_wait().unwrap().is_none());
  let start=Instant::now();assert_eq!(lock_cancel(&[lock.to_string_lossy().into(),token],Duration::from_millis(150)),10);assert!(start.elapsed()>=Duration::from_millis(150));assert!(start.elapsed()<Duration::from_secs(6));assert!(!f.child.wait().unwrap().success());assert!(!lock.exists());
 }
 #[test]fn production_shell_interrupt_and_exit_hooks_preserve_cancel_status(){
  let source=include_str!("../../tools/tools.sh");
  let interrupt=source.split("_speedbackup_on_interrupt() {").nth(1).unwrap().split("_speedbackup_install_interrupt_traps()").next().unwrap();
  let exit=source.split("    _speedbackup_exit_trap() {").nth(1).unwrap().split("    trap '_speedbackup_exit_trap' EXIT").next().unwrap();
  let mut script=String::new();
  for name in ["_speedbackup_background_finish_consume","_speedbackup_lock_cleanup","_speed_debug_disarm_if_run_gone","_speed_debug_log","echoRgb","_power_workers_snapshot","_speed_debug_pack","_speedbackup_run_tmpdir_final_cleanup","_speedbackup_background_finish_publish"]{script.push_str(&format!("{name}() {{ :; }}\n"));}
  script.push_str("_speedbackup_exit_code_normalize() { echo \"$1\"; }\n_speed_debug_stderr_target() { echo /dev/null; }\n_speedbackup_display_restore_after_debug_pack() { return 0; }\nremote_cleanup() { echo \"$REMOTE_TRIGGER\" > upload; }\n_power_complete_offer() { echo \"$_POWER_ELIGIBLE:$1\" > power; }\n_speedbackup_operation_finish() { echo \"$1\" > result; }\n_cleanup_tmp_files() { sleep 0.1; echo cleaned > cleanup; }\n");
  script.push_str(&format!("_speedbackup_on_interrupt() {{{interrupt}\n_speedbackup_exit_trap() {{{exit}\n"));
  script.push_str("REMOTE_TRIGGER=1; _POWER_ELIGIBLE=1; trap '_speedbackup_exit_trap' EXIT; trap '_speedbackup_on_interrupt' INT; echo ready > ready; while :; do sleep 30; done");
  let mut f=fixture(&script);let lease=f.path.join("lease");let token=acquire(&lease,f.child.id()).unwrap();assert_eq!(lock_cancel(&[lease.to_string_lossy().into(),token],Duration::from_secs(3)),0);
  assert_eq!(f.child.wait().unwrap().code(),Some(130));assert_eq!(fs::read_to_string(f.path.join("result")).unwrap().trim(),"130");assert_eq!(fs::read_to_string(f.path.join("upload")).unwrap().trim(),"0");assert_eq!(fs::read_to_string(f.path.join("power")).unwrap().trim(),"0:130");assert!(f.path.join("cleanup").exists());
 }
 #[test]fn removed_lease_does_not_prevent_forcing_pinned_worker(){
  let mut f=fixture("trap 'exit 130' INT; trap 'trap \"\" INT; sleep 30 & echo $! > cleanup_pid; echo cleaning > cleaning; wait' EXIT; echo ready > ready; while :; do sleep 30; done");
  let lease=f.path.join("lease");let token=acquire(&lease,f.child.id()).unwrap();let path=f.path.clone();let args=vec![lease.to_string_lossy().into_owned(),token];
  let t=std::thread::spawn(move||lock_cancel(&args,Duration::from_millis(300)));let start=Instant::now();while !path.join("cleaning").exists(){assert!(start.elapsed()<Duration::from_secs(2));std::thread::sleep(Duration::from_millis(5));}
  {let _g=guard(&lease).unwrap();remove_owned(&lease).unwrap();}
  let replacement=acquire(&lease,std::process::id()).unwrap();
  let cleanup_pid:u32=fs::read_to_string(path.join("cleanup_pid")).unwrap().trim().parse().unwrap();let fd=speedbackup_native_rs::pidfd_open(cleanup_pid as i32).unwrap();let pinned=StopProcess{pid:cleanup_pid,token:identity(cleanup_pid).unwrap(),fd:unsafe{File::from_raw_fd(fd)},resume:false};
  assert_eq!(t.join().unwrap(),10);assert!(!f.child.wait().unwrap().success());assert!(pinned.exited().unwrap());assert_eq!(fs::read_to_string(lease.join("owner")).unwrap(),replacement);
 }
 #[test]fn async_subshell_can_receive_sigint_and_cleanup(){
  let mut f=fixture("trap 'wait; exit 130' INT; (trap 'exit 130' INT; trap 'ec=$?; echo cleaned > child_cleanup; exit \"$ec\"' EXIT; echo ready > ready; while :; do sleep 30; done) & wait");
  let lease=f.path.join("lease");let token=acquire(&lease,f.child.id()).unwrap();assert_eq!(lock_cancel(&[lease.to_string_lossy().into(),token],Duration::from_secs(2)),0);let _=f.child.wait();assert!(f.path.join("child_cleanup").exists());
 }
 #[test]fn lease_guard_available_during_cleanup(){
  let mut f=fixture("trap 'exit 130' INT; trap 'ec=$?; echo cleaning > cleaning; while [ ! -f released ]; do sleep 0.02; done; echo cleaned > cleanup; exit \"$ec\"' EXIT; echo ready > ready; while :; do sleep 30; done");let lock=f.path.join("lease");let token=acquire(&lock,f.child.id()).unwrap();let path=f.path.clone();let args=vec![lock.to_string_lossy().into_owned(),token];
  let t=std::thread::spawn(move||lock_cancel(&args,Duration::from_secs(2)));let start=Instant::now();while !path.join("cleaning").exists(){assert!(start.elapsed()<Duration::from_secs(2));std::thread::sleep(Duration::from_millis(5));}
  {let _g=guard(&lock).expect("cleanup must be able to acquire lease");remove_owned(&lock).unwrap();}fs::write(path.join("released"),b"ok").unwrap();assert_eq!(t.join().unwrap(),0);assert_eq!(f.child.wait().unwrap().code(),Some(130));assert!(path.join("cleanup").exists());
 }
}

#[cfg(test)]
mod mount_guidance_tests {
    use super::*;
    #[test] fn authoritative_package_mapping() {
        assert_eq!(manager_package("package:com.sukisu.ultra uid:10234\n",10234).as_deref(),Some("com.sukisu.ultra"));
        for text in ["package:com.sukisu.ultra uid:10235", "package:com.sukisu.ultra uid:10234\npackage:other.app uid:10234", "garbage", ""] {assert!(manager_package(text,10234).is_none());}
        assert_eq!(package_name("com.resukisu.resukisu"),"BakaSU／ReSukiSU");
        assert_eq!(package_name("com.rifsxd.ksunext"),"KernelSU Next");
        assert_eq!(package_name("com.fake.sukisu"),"自訂管理器");
        assert_eq!(clean_kernel_string(b"v4.3-abc@main\0"),"v4.3-abc@main");
        for bytes in [b"unterminated".as_slice(),b"line\nbreak\0",b"\xff\0"] {assert!(clean_kernel_string(bytes).is_empty());}
    }
    #[test] fn su_identity_guidance() {
        for (v,kind,name) in [
            ("1.0:KernelSU","kernelsu","分支未辨識"),
            ("1.0:KernelSU-Next","kernelsu","KernelSU-Next"),
            ("SukiSU-Ultra:KernelSU","kernelsu","SukiSU"),
            ("ReSukiSU:KernelSU","kernelsu","ReSukiSU"),
            ("BakaSU:KernelSU","kernelsu","BakaSU"),
            ("28.0:MAGISKSU","magisk","Magisk"),
            ("Kitsune Mask:MAGISKSU","magisk","Kitsune"),
            ("APatch 11000","apatch","APatch"),
            ("KernelPatch 0.12","apatch","KernelPatch"),
            ("unknown","unknown","未辨識"),("","unknown","未辨識"),
            ("KernelSU MAGISKSU","unknown","未辨識")
        ] {
            assert_eq!(root_manager(v).0,kind);
            assert!(root_manager(v).1.contains(name));
            let text=mount_help_for_version(v);
            assert!(text.contains("/system/bin/sh"));
            assert!(text.contains("su --mount-master"));
        }
    }
}

#[cfg(test)]
mod legacy_entry_tests {
    use super::*;
    #[test]
    fn historical_wrapper_requires_adjacent_product_and_lease_markers() {
        let dir=std::env::temp_dir().join(format!("sb-legacy-source-{}",std::process::id()));
        fs::create_dir_all(dir.join("tools")).unwrap();
        let script=dir.join("start.sh");
        fs::write(&script,r#"#!/system/bin/sh
. "${0%/*}/tools/tools.sh" | tee "$logfile"
"#).unwrap();
        let tools=dir.join("tools/tools.sh");
        fs::write(&tools,"echo unrelated").unwrap();
        assert!(!legacy_entry_source_verified(&script).unwrap());
        fs::write(&tools,"# SpeedBackup tools.sh\nkill_Serve() { local LOCK_DIR=\"/data/.backup_lock\"; }\n").unwrap();
        assert!(legacy_entry_source_verified(&script).unwrap());
        fs::write(&script,"echo tools.sh").unwrap();
        assert!(!legacy_entry_source_verified(&script).unwrap());
        fs::remove_file(&tools).unwrap();
        std::os::unix::fs::symlink(&script,&tools).unwrap();
        assert!(bounded_script_source(&tools,1048576).is_err());
        fs::remove_file(&tools).unwrap();fs::remove_file(&script).unwrap();
        fs::remove_dir(dir.join("tools")).unwrap();fs::remove_dir(dir).unwrap();
    }
}
