//! Event-only perf metadata transport. No tracing configuration or discovery loop.
//! CPU hotplug or an untrustworthy hotplug channel emits Lost and stops:
//! coverage is explicitly partial thereafter, not silently assumed complete.
#![cfg(any(target_os = "linux", target_os = "android"))]

use super::events::Event;
use std::io;

#[cfg(not(any(target_arch = "aarch64", target_arch = "x86_64")))]
pub fn listen(_: impl Fn(Event) + Send + 'static) -> io::Result<()> {
    Err(io::Error::new(io::ErrorKind::Unsupported, "perf syscall ABI unsupported"))
}

#[cfg(any(target_arch = "aarch64", target_arch = "x86_64"))]
pub use supported::listen;

#[cfg(any(target_arch = "aarch64", target_arch = "x86_64"))]
mod supported {
    use super::*;
    use std::{
        ffi::{c_int, c_long, c_void},
        io::Read,
        mem::size_of,
        os::fd::{AsRawFd, FromRawFd, OwnedFd},
        sync::atomic::{AtomicU64, Ordering},
    };

    #[cfg(target_arch = "aarch64")]
    const SYS_PERF: c_long = 241;
    #[cfg(target_arch = "x86_64")]
    const SYS_PERF: c_long = 298;
    const CAP: usize = 16 * 1024 * 1024;

    #[repr(C)]
    struct PollFd { fd: c_int, events: i16, revents: i16 }
    #[repr(C)]
    struct Addr { family: u16, pad: u16, pid: u32, groups: u32 }

    unsafe extern "C" {
        fn syscall(number: c_long, ...) -> c_long;
        fn getpagesize() -> c_int;
        fn mmap(addr: *mut c_void, len: usize, prot: c_int, flags: c_int,
                fd: c_int, offset: i64) -> *mut c_void;
        fn munmap(addr: *mut c_void, len: usize) -> c_int;
        fn poll(fds: *mut PollFd, count: usize, timeout: c_int) -> c_int;
        fn socket(domain: c_int, kind: c_int, protocol: c_int) -> c_int;
        fn bind(fd: c_int, addr: *const c_void, len: u32) -> c_int;
        fn recvfrom(fd: c_int, buf: *mut c_void, len: usize, flags: c_int,
                    addr: *mut c_void, addrlen: *mut u32) -> isize;
    }

    fn invalid(s: &'static str) -> io::Error {
        io::Error::new(io::ErrorKind::InvalidData, s)
    }
    fn u32_at(b: &[u8], i: usize) -> u32 {
        u32::from_ne_bytes(b[i..i + 4].try_into().unwrap())
    }

    // Strictly bounded CPU IDs as well as count; reject duplicates and ambiguity.
    fn cpus(bytes: &[u8]) -> io::Result<Vec<u32>> {
        if bytes.len() > 4096 { return Err(invalid("CPU list too large")); }
        let s = std::str::from_utf8(bytes).map_err(|_| invalid("CPU list UTF-8"))?;
        let s = s.trim();
        let number = |s: &str| -> io::Result<usize> {
            if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
                return Err(invalid("CPU number"));
            }
            let n = s.parse::<usize>().map_err(|_| invalid("CPU number"))?;
            if n >= 256 { return Err(invalid("CPU cap exceeded")); }
            Ok(n)
        };
        let mut seen = [false; 256];
        for part in s.split(',') {
            let mut ends = part.split('-');
            let first = number(ends.next().unwrap())?;
            let last = match ends.next() { Some(v) => number(v)?, None => first };
            if ends.next().is_some() || last < first {
                return Err(invalid("CPU range"));
            }
            for slot in &mut seen[first..=last] {
                if *slot { return Err(invalid("duplicate CPU")); }
                *slot = true;
            }
        }
        Ok(seen.iter().enumerate().filter_map(|(n, yes)|
            yes.then_some(n as u32)).collect())
    }

    struct Mapping { base: *mut u8, len: usize }
    // Exclusive receiver ownership. Kernel/user synchronization is via metadata atomics.
    unsafe impl Send for Mapping {}
    impl Drop for Mapping {
        fn drop(&mut self) {
            unsafe { munmap(self.base.cast(), self.len); }
        }
    }
    struct Ring {
        map: Mapping,
        fd: OwnedFd,
        offset: usize,
        size: usize,
        tail: u64,
    }
    impl Ring {
        fn open(cpu: u32, page: usize) -> io::Result<Self> {
            // perf_event_attr v5, native-endian fields; all sampling fields zero.
            let mut attr = [0u8; 128];
            attr[0..4].copy_from_slice(&1u32.to_ne_bytes()); // SOFTWARE
            attr[4..8].copy_from_slice(&128u32.to_ne_bytes());
            attr[8..16].copy_from_slice(&9u64.to_ne_bytes()); // SW_DUMMY
            attr[40..48].copy_from_slice(
                &((1u64 << 13) | (1u64 << 9) | (1u64 << 24) | (1u64 << 14)).to_ne_bytes());
            attr[48..52].copy_from_slice(&1u32.to_ne_bytes()); // watermark=1 byte: metadata records must wake without sample events
            let raw = unsafe {
                syscall(SYS_PERF, attr.as_ptr(), -1 as c_int, cpu as c_int,
                        -1 as c_int, 8 as c_long)
            };
            if raw < 0 { return Err(io::Error::last_os_error()); }
            let fd = unsafe { OwnedFd::from_raw_fd(raw as c_int) };
            let len = page * 17;
            let base = unsafe {
                mmap(std::ptr::null_mut(), len, 1 | 2, 1, fd.as_raw_fd(), 0)
            };
            if base as isize == -1 { return Err(io::Error::last_os_error()); }
            let map = Mapping { base: base.cast(), len };
            // These ABI fields are immutable once mmap has completed.
            let offset = unsafe { map.base.add(1040).cast::<u64>().read_volatile() };
            let size = unsafe { map.base.add(1048).cast::<u64>().read_volatile() };
            let (offset, size) = layout(offset, size, page, len)?;
            let tail = unsafe {
                (&*map.base.add(1032).cast::<AtomicU64>()).load(Ordering::Relaxed)
            };
            Ok(Self { map, fd, offset, size, tail })
        }

        fn drain(&mut self, handler: &impl Fn(Event)) {
            let head = unsafe {
                (&*self.map.base.add(1024).cast::<AtomicU64>()).load(Ordering::Acquire)
            };
            // Never create a shared Rust slice of memory concurrently written by
            // the kernel. Only copy committed bytes, before releasing the tail.
            let base = unsafe { self.map.base.add(self.offset) };
            let size = self.size;
            consume(size, &mut self.tail, head, |off, out| {
                let start = (off & (size as u64 - 1)) as usize;
                for (i, byte) in out.iter_mut().enumerate() {
                    *byte = unsafe { base.add((start + i) & (size - 1)).read_volatile() };
                }
            }, handler);
            unsafe {
                (&*self.map.base.add(1032).cast::<AtomicU64>())
                    .store(self.tail, Ordering::Release);
            }
        }
    }

    fn layout(offset: u64, size: u64, page: usize, len: usize)
        -> io::Result<(usize, usize)>
    {
        let offset = usize::try_from(offset).map_err(|_| invalid("data offset"))?;
        let size = usize::try_from(size).map_err(|_| invalid("data size"))?;
        if offset < page || !size.is_power_of_two() || size < 8
            || offset.checked_add(size).filter(|end| *end <= len).is_none()
        {
            return Err(invalid("invalid perf mmap layout"));
        }
        Ok((offset, size))
    }

    fn record(b: &[u8]) -> Option<Event> {
        if b.len() < 8 { return Some(Event::Lost); }
        let declared = u16::from_ne_bytes([b[6], b[7]]) as usize;
        if declared != b.len() { return Some(Event::Lost); }
        // misc is intentionally not used: every leader COMM refreshes identity.
        let _misc = u16::from_ne_bytes([b[4], b[5]]);
        match u32_at(b, 0) {
            2 | 5 | 13 => Some(Event::Lost), // LOST, THROTTLE, LOST_SAMPLES
            7 | 4 => {
                if b.len() < 32 { return Some(Event::Lost); }
                let pid = u32_at(b, 8);
                if pid != u32_at(b, 16) { return None; }
                Some(if u32_at(b, 0) == 7 {
                    Event::Fork { parent: u32_at(b, 12), child: pid }
                } else { Event::Exit { pid } })
            }
            3 => {
                if b.len() < 17 || !b[16..].contains(&0) {
                    return Some(Event::Lost);
                }
                let pid = u32_at(b, 8);
                (pid == u32_at(b, 12)).then_some(Event::Exec { pid })
            }
            _ => None,
        }
    }

    fn consume(
        size: usize, tail: &mut u64, head: u64,
        mut copy: impl FnMut(u64, &mut [u8]), handler: &impl Fn(Event),
    ) {
        let available = head.checked_sub(*tail);
        if available.is_none() || available.unwrap() > size as u64 {
            handler(Event::Lost);
            *tail = head;
            return;
        }
        while *tail != head {
            let available = head - *tail;
            if available < 8 {
                handler(Event::Lost);
                *tail = head;
                break;
            }
            let mut header = [0u8; 8];
            copy(*tail, &mut header);
            let n = u16::from_ne_bytes([header[6], header[7]]) as usize;
            if n < 8 || n > size || n as u64 > available {
                handler(Event::Lost);
                *tail = head;
                break;
            }
            let mut bytes = vec![0; n];
            copy(*tail, &mut bytes);
            if let Some(event) = record(&bytes) { handler(event); }
            // n <= head-tail proves this addition cannot overflow.
            *tail += n as u64;
        }
    }

    fn hotplug_socket() -> io::Result<OwnedFd> {
        let raw = unsafe { socket(16, 2 | 0x80000, 15) };
        if raw < 0 { return Err(io::Error::last_os_error()); }
        let fd = unsafe { OwnedFd::from_raw_fd(raw) };
        let addr = Addr { family: 16, pad: 0, pid: 0, groups: 1 };
        if unsafe { bind(fd.as_raw_fd(), &addr as *const _ as *const c_void,
                         size_of::<Addr>() as u32) } < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(fd)
    }

    // True means coverage can no longer be trusted. Non-kernel senders ignored.
    fn hotplug(fd: &OwnedFd) -> io::Result<bool> {
        let mut bytes = [0u8; 8192];
        let mut addr = Addr { family: 0, pad: 0, pid: 0, groups: 0 };
        let mut len = size_of::<Addr>() as u32;
        let n = unsafe {
            recvfrom(fd.as_raw_fd(), bytes.as_mut_ptr().cast(), bytes.len(),
                     0x20 | 0x40, &mut addr as *mut _ as *mut c_void, &mut len)
        }; // MSG_TRUNC | MSG_DONTWAIT; only called on readiness.
        if n < 0 { return Err(io::Error::last_os_error()); }
        if len < size_of::<Addr>() as u32 || addr.family != 16 || addr.pid != 0 {
            return Ok(false);
        }
        if n == 0 || n as usize > bytes.len() { return Ok(true); }
        let b = &bytes[..n as usize];
        if b.last() != Some(&0) { return Ok(true); }
        let has = |field: &[u8]| b.split(|v| *v == 0).any(|v| v == field);
        Ok(has(b"SUBSYSTEM=cpu") && (has(b"ACTION=online") || has(b"ACTION=offline")))
    }

    pub fn listen(handler: impl Fn(Event) + Send + 'static) -> io::Result<()> {
        // Subscribe before taking the single online snapshot, so transitions
        // during setup remain queued and invalidate coverage in the receiver.
        let hot = hotplug_socket()?;
        let mut bytes = Vec::new();
        std::fs::File::open("/sys/devices/system/cpu/online")?
            .take(4097).read_to_end(&mut bytes)?;
        let cpus = cpus(&bytes)?;
        let page = unsafe { getpagesize() };
        if page < 4096 || !(page as usize).is_power_of_two() {
            return Err(invalid("page size"));
        }
        let page = page as usize;
        if page.checked_mul(17).and_then(|v| v.checked_mul(cpus.len()))
            .filter(|v| *v <= CAP).is_none()
        {
            return Err(invalid("perf mapping cap exceeded"));
        }
        let mut rings = Vec::new();
        for cpu in cpus { rings.push(Ring::open(cpu, page)?); }
        let mut fds: Vec<_> = rings.iter().map(|r|
            PollFd { fd: r.fd.as_raw_fd(), events: 1, revents: 0 }).collect();
        fds.push(PollFd { fd: hot.as_raw_fd(), events: 1, revents: 0 });
        std::thread::Builder::new().name("process-perf".into()).spawn(move || {
            loop {
                let rc = unsafe { poll(fds.as_mut_ptr(), fds.len(), -1) };
                if rc < 0 {
                    if io::Error::last_os_error().raw_os_error() == Some(4) { continue; }
                    handler(Event::Lost);
                    return;
                }
                if fds.iter().any(|p| p.revents & !1 != 0) {
                    handler(Event::Lost);
                    return;
                }
                if fds.last().unwrap().revents & 1 != 0 {
                    match hotplug(&hot) {
                        Ok(false) => {}
                        Err(e) if e.raw_os_error() == Some(4)
                            || e.kind() == io::ErrorKind::WouldBlock => {}
                        Ok(true) | Err(_) => {
                            handler(Event::Lost);
                            return;
                        }
                    }
                }
                for ring in &mut rings { ring.drain(&handler); }
            }
        })?;
        Ok(())
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use std::cell::RefCell;

        fn frame(kind: u32, n: usize) -> Vec<u8> {
            let mut b = vec![0; n];
            b[..4].copy_from_slice(&kind.to_ne_bytes());
            b[6..8].copy_from_slice(&(n as u16).to_ne_bytes());
            b
        }
        fn put(b: &mut [u8], n: usize, v: u32) {
            b[n..n + 4].copy_from_slice(&v.to_ne_bytes());
        }
        #[test]
        fn cpu_lists() {
            assert_eq!(cpus(b"0-3,5,7\n").unwrap(), vec![0,1,2,3,5,7]);
            assert_eq!(cpus(b"0-255").unwrap().len(), 256);
            for b in ["", "3-1", "0,0", "256", "0-256", "-1", "1-", "1--2", "1,"] {
                assert!(cpus(b.as_bytes()).is_err(), "{b}");
            }
        }
        #[test]
        fn metadata_layout() {
            assert_eq!(layout(4096, 65536, 4096, 69632).unwrap(), (4096,65536));
            for (offset, size) in [(0,65536), (4096,3), (4096,131072),
                                    (u64::MAX,65536), (4096,0)] {
                assert!(layout(offset, size, 4096, 69632).is_err());
            }
        }
        #[test]
        fn records_and_threads() {
            for kind in [4,7] {
                let mut b = frame(kind,32);
                put(&mut b,8,20); put(&mut b,12,10); put(&mut b,16,20);
                assert_eq!(record(&b), Some(if kind == 7 {
                    Event::Fork {parent:10,child:20}
                } else {Event::Exit {pid:20}}));
                for n in 0..32 { assert_eq!(record(&b[..n]),Some(Event::Lost)); }
                put(&mut b,16,21);
                assert_eq!(record(&b),None);
            }
            let mut b = frame(3,24);
            put(&mut b,8,20); put(&mut b,12,20);
            assert_eq!(record(&b),Some(Event::Exec {pid:20}));
            put(&mut b,12,21);
            assert_eq!(record(&b),None);
            b[16..].fill(1);
            assert_eq!(record(&b),Some(Event::Lost));
            for kind in [2,5,13] {
                assert_eq!(record(&frame(kind,8)),Some(Event::Lost));
            }
        }
        #[test]
        fn wrapped_ring_and_bad_lengths() {
            let events = RefCell::new(Vec::new());
            let handler = |e| events.borrow_mut().push(e);
            let b = frame(2,24);
            let mut ring = [0u8;32];
            for (i,v) in b.iter().enumerate() { ring[(28+i)%32] = *v; }
            let copy = |off:u64,out:&mut [u8]| {
                for (i,v) in out.iter_mut().enumerate() {
                    *v = ring[(off as usize+i)%32];
                }
            };
            let mut tail = 28;
            consume(32,&mut tail,52,copy,&handler);
            assert_eq!(tail,52);
            assert_eq!(*events.borrow(),vec![Event::Lost]);
            for (tail0,head) in [(0,33),(10,9),(0,7),(28,40)] {
                events.borrow_mut().clear();
                let mut tail = tail0;
                consume(32,&mut tail,head,copy,&handler);
                assert_eq!(tail,head);
                assert_eq!(*events.borrow(),vec![Event::Lost]);
            }
            for n in [0u16,7,33] {
                let mut h = [0u8;8];
                h[6..8].copy_from_slice(&n.to_ne_bytes());
                events.borrow_mut().clear();
                let mut tail = 0;
                consume(32,&mut tail,32,|_,out| out.copy_from_slice(&h),&handler);
                assert_eq!(*events.borrow(),vec![Event::Lost]);
            }
        }
    }
}
