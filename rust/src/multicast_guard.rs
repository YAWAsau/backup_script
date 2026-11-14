//! Android platform lease; no discovery logic lives in the Dex helper.
#[cfg(target_os = "android")]
pub struct MulticastGuard(std::process::Child);

#[cfg(target_os = "android")]
impl MulticastGuard {
    pub fn acquire() -> std::io::Result<Self> {
        use std::{io::{self, Read}, os::fd::AsRawFd, process::{Command, Stdio}, time::{Duration, Instant}};
        let dex = std::env::current_exe()?.parent()
            .ok_or_else(|| io::Error::other("missing executable parent"))?.join("classes.dex");
        let child = Command::new("/system/bin/app_process").current_dir("/").env("CLASSPATH", dex)
            .args(["/system/bin", "com.xayah.dex.MulticastGuard"])
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
        // Install cleanup before any fallible handshake operation.
        let mut guard = Self(child);
        let output = guard.0.stdout.as_mut().ok_or_else(|| io::Error::other("missing lease pipe"))?;
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() { return Err(io::Error::new(io::ErrorKind::TimedOut, "multicast lease timeout")); }
            let mut fd = speedbackup_native_rs::PollFd { fd: output.as_raw_fd(), events: speedbackup_native_rs::POLLIN, revents: 0 };
            let ready = unsafe { speedbackup_native_rs::poll(&mut fd, 1, remaining.as_millis().min(2000) as i32) };
            if ready < 0 {
                let error = io::Error::last_os_error();
                if error.kind() == io::ErrorKind::Interrupted { continue; }
                return Err(error);
            }
            if ready == 0 { continue; }
            let mut byte = [0];
            output.read_exact(&mut byte)?;
            if byte != [b'1'] { return Err(io::Error::other("multicast lease rejected")); }
            return Ok(guard);
        }
    }
}

#[cfg(target_os = "android")]
impl Drop for MulticastGuard {
    fn drop(&mut self) {
        // EOF requests normal release. If the VM stalls, death releases Binder's lease.
        drop(self.0.stdin.take());
        for _ in 0..10 {
            if matches!(self.0.try_wait(), Ok(Some(_))) { return; }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[cfg(not(target_os = "android"))]
pub struct MulticastGuard;
#[cfg(not(target_os = "android"))]
impl MulticastGuard {
    pub fn acquire() -> std::io::Result<Self> { Ok(Self) }
}
