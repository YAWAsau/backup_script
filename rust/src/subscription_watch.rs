//! Cancellation for the dedicated, read-only SUBSCRIBE worker process.
//! POLLIN/RDHUP is intentionally ignored: clients half-close their request side.
use std::time::Instant;

fn should_exit(revents: i16, running: bool, deadline: Option<Instant>) -> bool {
    // Linux poll: ERR=8, HUP=16, NVAL=32. Full close/HUP also works while logd
    // blocks without producing an event. A request-side FIN alone is not HUP.
    revents & (8 | 16 | 32) != 0 || !running || deadline.is_some_and(|d| Instant::now() >= d)
}

#[cfg(unix)]
pub struct SubscriptionWatch {
    done: std::sync::Arc<std::sync::atomic::AtomicBool>,
    thread: Option<std::thread::JoinHandle<()>>,
}

#[cfg(unix)]
impl SubscriptionWatch {
    // Only call after fork, in the SUBSCRIBE worker. Exiting this process closes
    // its socket and liblog handles; it never owns any freeze/thaw operation.
    pub fn start(
        stream: &std::os::unix::net::UnixStream,
        running: &'static std::sync::atomic::AtomicBool,
        duration_ms: u64,
    ) -> std::io::Result<Self> {
        use std::os::fd::AsRawFd;
        use std::sync::{atomic::Ordering, Arc};
        use std::time::Duration;
        #[repr(C)]
        struct PollFd {
            fd: i32,
            events: i16,
            revents: i16,
        }
        extern "C" {
            fn poll(fds: *mut PollFd, count: usize, timeout: i32) -> i32;
            fn _exit(status: i32) -> !;
        }
        let peer = stream.try_clone()?;
        let done = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let stop = done.clone();
        let deadline = if duration_ms == 0 {
            None
        } else {
            Instant::now().checked_add(Duration::from_millis(duration_ms))
        };
        let thread = std::thread::Builder::new()
            .name("logd-peer-watch".into())
            .spawn(move || {
                let mut p = PollFd {
                    fd: peer.as_raw_fd(),
                    events: 0,
                    revents: 0,
                };
                while !stop.load(Ordering::Acquire) {
                    p.revents = 0;
                    let rc = unsafe { poll(&mut p, 1, 100) };
                    if stop.load(Ordering::Acquire) {
                        break;
                    }
                    if rc < 0 {
                        if std::io::Error::last_os_error().kind() == std::io::ErrorKind::Interrupted
                        {
                            continue;
                        }
                        // A broken cancellation monitor must not leave an unbounded subscriber.
                        unsafe {
                            _exit(74);
                        }
                    }
                    if should_exit(p.revents, running.load(Ordering::Relaxed), deadline) {
                        unsafe {
                            _exit(0);
                        }
                    }
                }
            })?;
        Ok(Self {
            done,
            thread: Some(thread),
        })
    }
}

#[cfg(unix)]
impl Drop for SubscriptionWatch {
    fn drop(&mut self) {
        self.done.store(true, std::sync::atomic::Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn request_half_close_is_not_cancellation() {
        assert!(!should_exit(0, true, None));
        assert!(!should_exit(1 | 0x2000, true, None)); // IN | RDHUP
    }
    #[test]
    fn full_close_and_errors_cancel_without_any_log_event() {
        for event in [8, 16, 32, 17, 0x2011] {
            assert!(should_exit(event, true, None));
        }
    }
    #[test]
    fn termination_and_deadline_cancel_blocked_reads() {
        assert!(should_exit(0, false, None));
        assert!(should_exit(0, true, Some(Instant::now())));
        assert!(!should_exit(
            0,
            true,
            Some(Instant::now() + std::time::Duration::from_secs(30))
        ));
    }
}
