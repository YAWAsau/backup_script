//! Optional tar terminal progress. Archive bytes never pass through this code.
//! A distinct O_NONBLOCK tty description cannot alter inherited pipe/tty flags.
use speedbackup_native_rs::{close, kill, pidfd_open, poll, PollFd, POLLIN, O_CLOEXEC, O_NONBLOCK};
use std::collections::VecDeque;
use std::ffi::OsString;
use std::fs::{File, OpenOptions};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::os::fd::AsRawFd;
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicI32, Ordering};
use std::time::{Duration, Instant};

#[path = "tty_output.rs"]
mod tty_output;

const O_NOCTTY: i32 = 0o400;
const REFRESH_INTERVAL: Duration = Duration::from_millis(33);
const SPEED_WINDOW: Duration = Duration::from_millis(500);
const SIGNALS: [i32; 3] = [1, 2, 15];
static PENDING: AtomicI32 = AtomicI32::new(0);
extern "C" {
    fn signal(sig: i32, handler: usize) -> usize;
    fn prctl(option: i32, arg2: std::os::raw::c_ulong, arg3: std::os::raw::c_ulong,
             arg4: std::os::raw::c_ulong, arg5: std::os::raw::c_ulong) -> i32;
    fn getppid() -> i32;
    fn isatty(fd: i32) -> i32;
}
extern "C" fn on_signal(sig: i32) { PENDING.store(sig, Ordering::Relaxed); }

#[derive(Clone, Copy, Debug, PartialEq)]
enum Mode { Create, Extract }

// Detect standard create/extract invocations for optional display only. This is
// not tar's validator: every original argument still reaches tar unchanged.
fn mode(args: &[OsString]) -> Option<Mode> {
    let mut found = None;
    let mut operand = false;
    for arg in args {
        let b = arg.as_bytes();
        if operand { operand=false; continue; }
        if b == b"--" { break; }
        if b == b"--create" { found=Some(Mode::Create); continue; }
        if b == b"--extract" || b == b"--get" { found=Some(Mode::Extract); continue; }
        if [b"--file".as_slice(),b"--directory",b"--files-from",b"--exclude",b"--exclude-from",b"--transform",b"--use-compress-program",b"--mtime",b"--owner",b"--group",b"--format",b"--starting-file",b"--newer",b"--after-date",b"--info-script",b"--new-volume-script"].contains(&b) { operand=true; continue; }
        if b.starts_with(b"--") { continue; }
        if b.starts_with(b"-") {
            let mut i=1;
            while i<b.len() {
                match b[i] {
                    b'c' => found=Some(Mode::Create),
                    b'x' => found=Some(Mode::Extract),
                    b't' | b'd' | b'r' | b'u' | b'A' => return None,
                    b'f' | b'C' | b'T' | b'X' | b'I' | b'b' | b'g' | b'L' | b'V' | b'H' | b'K' | b'N' | b'F' => { operand=i+1==b.len(); break; }
                    _ => {}
                }
                i+=1;
            }
        }
    }
    found
}

fn io_bytes(data: &[u8], mode: Mode) -> Option<u64> {
    let key: &[u8] = if mode==Mode::Create { b"wchar:" } else { b"rchar:" };
    let row=data.split(|&c|c==b'\n').find(|r|r.starts_with(key))?;
    std::str::from_utf8(&row[key.len()..]).ok()?.trim().parse().ok()
}
fn sample(file: &mut File, mode: Mode) -> Option<u64> {
    file.seek(SeekFrom::Start(0)).ok()?;
    let mut buf=[0u8;2048];
    let n=file.read(&mut buf).ok()?;
    io_bytes(&buf[..n],mode)
}
fn status_code(s: ExitStatus) -> i32 { s.code().unwrap_or_else(||128+s.signal().unwrap_or(1)) }
fn direct(args: &[OsString]) -> i32 {
    let err=Command::new("tar").args(args).exec();
    eprintln!("tar: {}",err);
    if err.kind()==io::ErrorKind::NotFound {127} else {126}
}
fn positive_bytes(s: &str) -> Option<u64> {
    if s.is_empty() || s.len()>20 || !s.bytes().all(|c|c.is_ascii_digit()) {return None;}
    s.parse::<u64>().ok().filter(|&n|n>0)
}
fn plan_total(plan: &str, key: &str) -> Option<u64> {
    if key.is_empty() {return None;}
    let mut found=None;
    for line in plan.lines() {
        let f:Vec<_>=line.split('\t').collect();
        if f.len()<4 || format!("{}/{}",f[1],f[3])!=key {continue;}
        // Ambiguous or malformed matching rows disable the percentage hint.
        if found.is_some() || f.len()!=5 || !matches!(f[0],"DIR"|"APK") {return None;}
        found=Some(positive_bytes(f[4])?);
    }
    found
}
fn total_hint(mode: Mode) -> Option<u64> {
    if mode==Mode::Extract {
        return std::env::var("SPEEDBACKUP_TAR_PROGRESS_EXTRACT_TOTAL").ok().and_then(|s|positive_bytes(&s));
    }
    let key=std::env::var("SPEEDBACKUP_TAR_PROGRESS_KEY").unwrap_or_default();
    if key.is_empty() {return None;}
    // Reuse existing prescan metadata; never traverse or read source file data.
    let planned=(|| {
        let path=std::env::var_os("SPEEDBACKUP_TAR_PROGRESS_PLAN")?;
        let f=OpenOptions::new().read(true).custom_flags(O_NONBLOCK|O_CLOEXEC).open(path).ok()?;
        let m=f.metadata().ok()?;
        if !m.is_file() || m.len()>4*1024*1024 {return None;}
        let mut text=String::new();
        f.take(4*1024*1024+1).read_to_string(&mut text).ok()?;
        if text.len()>4*1024*1024 {return None;}
        plan_total(&text,&key)
    })();
    planned.or_else(||std::env::var("SPEEDBACKUP_TAR_PROGRESS_ORIGIN").ok().and_then(|s|positive_bytes(&s)))
}
// Average only measured bytes over the recent half second. Do not interpolate
// the processed-byte counter or percentage; stalled I/O settles to zero speed.
struct SpeedWindow { samples: VecDeque<(Duration, u64)> }
impl SpeedWindow {
    fn new() -> Self { Self { samples: VecDeque::from([(Duration::ZERO, 0)]) } }
    fn observe(&mut self, now: Duration, bytes: u64) -> (u64, f64) {
        if self.samples.back().map(|&(t,b)|now<=t || bytes<b).unwrap_or(false) {
            self.samples.clear();
        }
        self.samples.push_back((now, bytes));
        let cutoff=now.saturating_sub(SPEED_WINDOW);
        while self.samples.len()>2 && self.samples[1].0<=cutoff {self.samples.pop_front();}
        let (time, before)=self.samples[0];
        (bytes.saturating_sub(before),(now-time).as_secs_f64())
    }
}
fn progress_color(raw: &str) -> u8 {
    if raw.is_empty() || raw.len()>3 || !raw.bytes().all(|c|c.is_ascii_digit()) {return 51;}
    raw.parse().unwrap_or(51)
}
// Decimal units match the labels KB/MB/GB. Amount and rate choose units independently.
fn human_decimal(mut value: f64) -> String {
    const UNITS: [&str; 7] = ["B", "KB", "MB", "GB", "TB", "PB", "EB"];
    let mut unit = 0;
    // Promote on the displayed (two-decimal) boundary too: never show 1000 KB.
    while unit + 1 < UNITS.len() && (value * 100.0).round() >= 100_000.0 {
        value /= 1000.0;
        unit += 1;
    }
    // Keep two decimal places without left-padding the value or unit.
    format!("{:.2} {}", value, UNITS[unit])
}
fn frame(mode: Mode, bytes: u64, delta: u64, seconds: f64, total: Option<u64>, color: u8) -> String {
    let label=if mode==Mode::Create { "封裝" } else { "解包" };
    let percent=total.map(|t|{
        let tenths=((bytes as u128)*1000/(t as u128)).min(999);
        format!("約{:>2}.{}%",tenths/10,tenths%10)
    }).unwrap_or_default();
    // Preserve the shell prefix; write the compact frame before clearing its old tail.
    // Reset color in the same write to avoid a blank-frame flash.
    format!("\r\x1b[38;5;{}m -{}{} 已處理約{} {}/s\x1b[0m\x1b[K",color,label,percent,human_decimal(bytes as f64),human_decimal(delta as f64/seconds.max(0.001)))
}
// Exactly one nonblocking write: a full tty drops the frame. Never write_all,
// flush, tcdrain, retry EAGAIN, or change flags on stdout/stderr's description.
fn draw(tty: &mut File, bytes: &[u8]) -> bool { tty.write(bytes).is_ok() }

// Optional shell UI only. Open a separate description, never set O_NONBLOCK on
// inherited stdout: its flags may be shared by archive pipes or the terminal.
// Continue short writes/EAGAIN for 250ms; report 75 (none) or 76 (partial) on
// failure so the shell can record TTY_DROP and open its circuit breaker. This is
// not a tty atomic-message guarantee. Interactive prompts use blocking builtins.
pub(super) fn tty_write(stdout: bool) -> i32 {
    let path=if stdout { "/proc/self/fd/1" } else { "/dev/tty" };
    let tty=OpenOptions::new().write(true).custom_flags(O_NONBLOCK|O_CLOEXEC|O_NOCTTY).open(path)
        .and_then(|f| if unsafe {isatty(f.as_raw_fd())}==1 { Ok(f) }
                     else { Err(io::ErrorKind::NotConnected.into()) });
    let fd=tty.as_ref().map(|f|f.as_raw_fd()).unwrap_or(-1);
    tty_output::deliver(&mut io::stdin().lock(),tty,&mut io::stdout().lock(),tty_output::RETRY_LIMIT,
        |remaining| {
            let mut ready=PollFd{fd,events:0x0004,revents:0}; // POLLOUT
            let millis=remaining.as_nanos().div_ceil(1_000_000).min(i32::MAX as u128) as i32;
            let result=unsafe {poll(&mut ready,1,millis)};
            if result<0 { Err(io::Error::last_os_error()) }
            else if ready.revents & (0x0008|0x0010|0x0020)!=0 { // ERR/HUP/NVAL
                Err(io::ErrorKind::BrokenPipe.into())
            } else { Ok(()) }
        })
}

pub(super) fn run(args: &[OsString]) -> i32 {
    let mode=match mode(args) { Some(m)=>m, None=>return direct(args) };
    let mut tty=match OpenOptions::new().write(true).custom_flags(O_NONBLOCK|O_CLOEXEC|O_NOCTTY).open("/dev/tty") {
        Ok(f)=>f, Err(_)=>return direct(args),
    };
    let total=total_hint(mode);
    let color=progress_color(&std::env::var("SPEEDBACKUP_TAR_PROGRESS_COLOR").unwrap_or_default());
    let mut old=[0usize;3];
    for (i,sig) in SIGNALS.iter().enumerate() {
        old[i]=unsafe {signal(*sig,on_signal as *const () as usize)};
        if old[i]==usize::MAX {
            for j in 0..i { unsafe {signal(SIGNALS[j],old[j]);} }
            return direct(args);
        }
        // Background shells may intentionally ignore HUP/INT. Preserve that.
        if old[i]==1 { unsafe {signal(*sig,1);} }
    }
    let parent=std::process::id() as i32;
    let mut command=Command::new("tar");
    command.args(args).stdin(Stdio::inherit()).stdout(Stdio::inherit()).stderr(Stdio::inherit());
    unsafe {
        command.pre_exec(move || {
            for i in 0..SIGNALS.len() {signal(SIGNALS[i],old[i]);}
            signal(13,0); // Match the normal exec child SIGPIPE behavior.
            if prctl(1,9,0,0,0)!=0 {return Err(io::Error::last_os_error());}
            if getppid()!=parent {return Err(io::Error::from_raw_os_error(3));}
            Ok(())
        });
    }
    let mut child=match command.spawn() {
        Ok(c)=>c,
        Err(_)=>{
            for i in 0..SIGNALS.len() {unsafe {signal(SIGNALS[i],old[i]);}}
            return direct(args); // Display setup failure must not prevent tar.
        }
    };
    let pid=child.id() as i32;
    let pidfd=pidfd_open(pid).ok();
    // An open proc file is bound to this task, never a subsequently reused PID.
    let mut counters=File::open(format!("/proc/{}/io",pid)).ok();
    let start=Instant::now();
    let mut speed=SpeedWindow::new();
    let mut next=REFRESH_INTERVAL;
    let mut drawn=false;
    let rc=loop {
        let sig=PENDING.swap(0,Ordering::Relaxed);
        if sig!=0 {unsafe {kill(pid,sig);}} // Owned, unreaped child cannot reuse PID.
        match child.try_wait() {
            Ok(Some(status))=>break status_code(status),
            Ok(None)=>{},
            Err(e) if e.kind()==io::ErrorKind::Interrupted=>continue,
            Err(_)=>{let _=child.kill();let _=child.wait();break 125;},
        }
        let now=start.elapsed();
        if now>=next {
            if let Some(bytes)=counters.as_mut().and_then(|f|sample(f,mode)) {
                let (delta, seconds)=speed.observe(now,bytes);
                if bytes>0 {
                    let msg=frame(mode,bytes,delta,seconds,total,color);
                    drawn|=draw(&mut tty,msg.as_bytes());
                }
            }
            next=now+REFRESH_INTERVAL;
        }
        // Round UP: truncating the final fraction to zero spins until the next
        // frame, an avoidable cost that grows with the refresh frequency.
        let wait=next.saturating_sub(start.elapsed()).as_nanos().div_ceil(1_000_000).min(if pidfd.is_some(){1000}else{50}) as i32;
        if let Some(fd)=pidfd {
            let mut p=PollFd{fd,events:POLLIN,revents:0};
            unsafe {poll(&mut p,1,wait);}
        } else {
            std::thread::sleep(Duration::from_millis(wait as u64));
        }
    };
    if let Some(fd)=pidfd {unsafe {close(fd);}}
    if drawn {let _=draw(&mut tty,b"\r\x1b[2K");}
    rc
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::ffi::OsStringExt;
    fn args(s: &[&str])->Vec<OsString>{s.iter().map(OsString::from).collect()}
    #[test] fn progress_modes_and_operands() {
        assert_eq!(mode(&args(&["--warning=no-file-ignored","-cpf","-","-C","/x","data"])),Some(Mode::Create));
        assert_eq!(mode(&args(&["-xmpf","-","-C","/target"])),Some(Mode::Extract));
        assert_eq!(mode(&args(&["--create","--file","-x"])),Some(Mode::Create));
        assert_eq!(mode(&args(&["-tf","-c"])),None);
        assert_eq!(mode(&args(&["--version"])),None);
        assert_eq!(mode(&args(&["--exclude","-x","-cf","out"])),Some(Mode::Create));
        assert_eq!(mode(&args(&["-C","-x","--","-c"])),None);
        let mut a=args(&["-cf","-"]);a.push(OsString::from_vec(vec![0xff,b'x']));
        assert_eq!(mode(&a),Some(Mode::Create));
    }
    #[test] fn progress_counters_and_display() {
        let s=b"rchar: 2097152\nwchar: 1048576\nsyscr: 7\n";
        assert_eq!(io_bytes(s,Mode::Create),Some(1048576));
        assert_eq!(io_bytes(s,Mode::Extract),Some(2097152));
        assert_eq!(io_bytes(b"wchar: -1\n",Mode::Create),None);
        assert_eq!(io_bytes(b"wchar: 18446744073709551616\n",Mode::Create),None);
        let s=frame(Mode::Create,1048576,1048576,2.0,None,51);
        assert!(s.contains("1.05 MB")&&s.contains("524.29 KB/s")&&!s.contains('%'));
        assert!(s.len()<192);
    }
    #[test] fn progress_option_arguments_are_not_modes() {
        for letter in ["H","K","N","F"] {
            let opt=format!("-{}",letter);
            assert_eq!(mode(&args(&[&opt,"-x"])),None);
            assert_eq!(mode(&args(&["-c",&opt,"-x"])),Some(Mode::Create));
            assert_eq!(mode(&args(&["-x",&opt,"-c"])),Some(Mode::Extract));
            assert_eq!(mode(&args(&[&format!("-c{}-x",letter)])),Some(Mode::Create));
            assert_eq!(mode(&args(&[&format!("-x{}-c",letter)])),Some(Mode::Extract));
        }
        for opt in ["--format","--starting-file","--newer","--after-date","--info-script","--new-volume-script"] {
            assert_eq!(mode(&args(&[opt,"-x"])),None);
            assert_eq!(mode(&args(&["-c",opt,"-x"])),Some(Mode::Create));
            assert_eq!(mode(&args(&["-x",opt,"-c"])),Some(Mode::Extract));
            assert_eq!(mode(&args(&["-c",&format!("{}=-x",opt)])),Some(Mode::Create));
        }
    }
    #[test] fn progress_percentage_hints() {
        assert_eq!(plan_total("DIR\tQQ\tcom.qq\tuser\t8192\n","QQ/user"),Some(8192));
        assert_eq!(plan_total("DIR\tQQ\tcom.qq\tuser\t8192\nDIR\tQQ\tcom.qq\tuser\t8\n","QQ/user"),None);
        for v in ["", "0", "-1", "NaN", "18446744073709551616", "8192\textra"] {
            assert_eq!(plan_total(&format!("DIR\tQQ\tcom.qq\tuser\t{}\n",v),"QQ/user"),None);
        }
        assert!(frame(Mode::Create,4096,2048,1.0,Some(8192),51).contains("約50.0%"));
        assert!(frame(Mode::Extract,4096,2048,1.0,Some(8192),51).contains("解包約50.0%"));
        assert!(frame(Mode::Create,u64::MAX,0,1.0,Some(1),51).contains("約99.9%"));
        assert!(frame(Mode::Create,1,0,1.0,Some(u64::MAX),51).contains("約 0.0%"));
    }
    #[test] fn progress_speed_window_bursts_and_stalls() {
        let mut w=SpeedWindow::new();
        assert_eq!(w.observe(Duration::from_millis(100),100),(100,0.1));
        assert_eq!(w.observe(Duration::from_millis(300),300),(300,0.3));
        assert_eq!(w.observe(Duration::from_millis(600),600),(500,0.5));
        assert_eq!(w.observe(Duration::from_millis(1100),600),(0,0.5));
        assert_eq!(w.observe(Duration::from_millis(1200),50),(0,0.0));
        assert_eq!(w.observe(Duration::from_millis(1300),150),(100,0.1));
        for i in 40..300 {w.observe(Duration::from_millis(i*33),i*100);}
        assert!(w.samples.len()<=18);
    }
    #[test] fn restore_hint_is_separate_from_backup_plan() {
        std::env::set_var("SPEEDBACKUP_TAR_PROGRESS_KEY","stale-backup/data");
        std::env::set_var("SPEEDBACKUP_TAR_PROGRESS_ORIGIN","999999");
        for value in ["", "0", "-1", "1.5", "18446744073709551616"] {
            std::env::set_var("SPEEDBACKUP_TAR_PROGRESS_EXTRACT_TOTAL",value);
            assert_eq!(total_hint(Mode::Extract),None);
        }
        std::env::set_var("SPEEDBACKUP_TAR_PROGRESS_EXTRACT_TOTAL","8075816960");
        assert_eq!(total_hint(Mode::Extract),Some(8075816960));
        assert_eq!(total_hint(Mode::Create),Some(999999));
        for key in ["SPEEDBACKUP_TAR_PROGRESS_KEY","SPEEDBACKUP_TAR_PROGRESS_ORIGIN","SPEEDBACKUP_TAR_PROGRESS_EXTRACT_TOTAL"] {std::env::remove_var(key);}
    }
    #[test] fn progress_matches_shell_ui_and_rejects_invalid_colors() {
        assert_eq!(progress_color("213"),213);
        for value in ["", "-1", "256", "51\x1b[2J", "cyan"] {assert_eq!(progress_color(value),51);}
        let line=frame(Mode::Create,12345,4096,0.5,Some(100000),213);
        assert!(line.starts_with("\r\x1b[38;5;213m -封裝約12.3% 已處理約"));
        assert!(line.ends_with("\x1b[0m\x1b[K"));
        assert!(!line.contains("\x1b[2K") && !line.contains('\n'));
    }
}
