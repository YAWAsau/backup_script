//! Atomic signal-aware readiness wait. No timers or periodic wakeups.
use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use crate::PollFd;
#[cfg(target_os = "android")]
type SigSet = [u64; 1];
#[cfg(not(target_os = "android"))]
type SigSet = [u64; 16];
extern "C" {
    fn sigemptyset(set: *mut SigSet) -> i32;
    fn sigaddset(set: *mut SigSet, sig: i32) -> i32;
    fn sigprocmask(how: i32, set: *const SigSet, old: *mut SigSet) -> i32;
    fn ppoll(fds: *mut PollFd, n: usize, timeout: *const std::ffi::c_void, mask: *const SigSet) -> i32;
}
pub fn readable(fd: i32, stop: &AtomicBool) -> io::Result<bool> {
    let mut blocked: SigSet = Default::default();
    let mut old: SigSet = Default::default();
    unsafe {
        sigemptyset(&mut blocked);
        for sig in [1, 2, 15] { sigaddset(&mut blocked, sig); }
        if sigprocmask(0, &blocked, &mut old) != 0 { return Err(io::Error::last_os_error()); }
    }
    let result = loop {
        if stop.load(Ordering::SeqCst) { break Ok(false); }
        let mut p = PollFd { fd, events: crate::POLLIN, revents: 0 };
        let rc = unsafe { ppoll(&mut p, 1, std::ptr::null(), &old) };
        if rc > 0 { break Ok(true); }
        let e = io::Error::last_os_error();
        if e.kind() != io::ErrorKind::Interrupted { break Err(e); }
    };
    unsafe { sigprocmask(2, &old, std::ptr::null_mut()); }
    result.map(|ready| ready && !stop.load(Ordering::SeqCst))
}
