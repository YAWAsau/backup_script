// Copyright 2018 MaidSafe.net limited.
//
// This SAFE Network Software is licensed to you under the MIT license <LICENSE-MIT
// http://opensource.org/licenses/MIT> or the Modified BSD license <LICENSE-BSD
// https://opensource.org/licenses/BSD-3-Clause>, at your option. This file may not be copied,
// modified, or distributed except according to those terms. Please review the Licences for the
// specific language governing permissions and limitations relating to use of the SAFE Network
// Software.

use std::ffi::{c_void, CStr};

use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender};
use std::time::Duration;
use std::{io, ptr};
use windows_sys::Win32::Foundation::{ERROR_BUFFER_OVERFLOW, ERROR_SUCCESS, HANDLE};
use windows_sys::Win32::NetworkManagement::IpHelper::{
    CancelMibChangeNotify2, GetAdaptersAddresses, NotifyIpInterfaceChange, GAA_FLAG_INCLUDE_PREFIX,
    GAA_FLAG_SKIP_ANYCAST, GAA_FLAG_SKIP_DNS_SERVER, GAA_FLAG_SKIP_MULTICAST,
    IP_ADAPTER_ADDRESSES_LH, IP_ADAPTER_PREFIX_XP, IP_ADAPTER_UNICAST_ADDRESS_LH,
    MIB_IPINTERFACE_ROW, MIB_NOTIFICATION_TYPE,
};
use windows_sys::Win32::Networking::WinSock::AF_UNSPEC;
use windows_sys::Win32::System::Memory::{
    GetProcessHeap, HeapAlloc, HeapFree, HEAP_NONE, HEAP_ZERO_MEMORY,
};

use crate::IfOperStatus;

#[repr(transparent)]
pub struct IpAdapterAddresses(*const IP_ADAPTER_ADDRESSES_LH);

impl IpAdapterAddresses {
    #[allow(unsafe_code)]
    pub fn name(&self) -> String {
        let len = (0..)
            .take_while(|&i| unsafe { *(*self.0).FriendlyName.offset(i) } != 0)
            .count();
        let slice = unsafe { std::slice::from_raw_parts((*self.0).FriendlyName, len) };
        String::from_utf16_lossy(slice)
    }

    #[allow(unsafe_code)]
    pub fn adapter_name(&self) -> String {
        unsafe { CStr::from_ptr((*self.0).AdapterName as _) }
            .to_string_lossy()
            .into_owned()
    }

    pub fn ipv4_index(&self) -> Option<u32> {
        let if_index = unsafe { (*self.0).Anonymous1.Anonymous.IfIndex };
        if if_index == 0 {
            None
        } else {
            Some(if_index)
        }
    }

    pub fn ipv6_index(&self) -> Option<u32> {
        let if_index = unsafe { (*self.0).Ipv6IfIndex };
        if if_index == 0 {
            None
        } else {
            Some(if_index)
        }
    }

    pub fn prefixes(&self) -> PrefixesIterator<'_> {
        PrefixesIterator {
            _head: unsafe { &*self.0 },
            next: unsafe { (*self.0).FirstPrefix },
        }
    }

    pub fn unicast_addresses(&self) -> UnicastAddressesIterator<'_> {
        UnicastAddressesIterator {
            _head: unsafe { &*self.0 },
            next: unsafe { (*self.0).FirstUnicastAddress },
        }
    }

    pub fn oper_status(&self) -> IfOperStatus {
        unsafe { (*self.0).OperStatus.into() }
    }

    /// Returns true if the interface is a point-to-point interface.
    pub fn is_p2p(&self) -> bool {
        let if_type = unsafe { (*self.0).IfType };

        if_type == 23 /* IF_TYPE_PPP */
            || if_type == 131 /* IF_TYPE_TUNNEL */
    }
}

pub struct IfAddrs {
    inner: IpAdapterAddresses,
}

impl IfAddrs {
    #[allow(unsafe_code)]
    pub fn new() -> io::Result<Self> {
        let mut buffersize = 15000;
        let mut ifaddrs: *mut IP_ADAPTER_ADDRESSES_LH;

        loop {
            unsafe {
                ifaddrs = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, buffersize as _)
                    as *mut IP_ADAPTER_ADDRESSES_LH;
                if ifaddrs.is_null() {
                    panic!("Failed to allocate buffer in get_if_addrs()");
                }

                let retcode = GetAdaptersAddresses(
                    0,
                    GAA_FLAG_SKIP_ANYCAST
                        | GAA_FLAG_SKIP_MULTICAST
                        | GAA_FLAG_SKIP_DNS_SERVER
                        | GAA_FLAG_INCLUDE_PREFIX,
                    ptr::null_mut(),
                    ifaddrs,
                    &mut buffersize,
                );

                match retcode {
                    ERROR_SUCCESS => break,
                    ERROR_BUFFER_OVERFLOW => {
                        HeapFree(GetProcessHeap(), HEAP_NONE, ifaddrs as _);
                        buffersize *= 2;
                        continue;
                    }
                    _ => {
                        HeapFree(GetProcessHeap(), HEAP_NONE, ifaddrs as _);
                        return Err(io::Error::last_os_error());
                    }
                }
            }
        }

        Ok(Self {
            inner: IpAdapterAddresses(ifaddrs),
        })
    }

    pub fn iter(&self) -> IfAddrsIterator<'_> {
        IfAddrsIterator {
            _head: self,
            next: self.inner.0,
        }
    }
}

impl Drop for IfAddrs {
    #[allow(unsafe_code)]
    fn drop(&mut self) {
        unsafe {
            HeapFree(GetProcessHeap(), HEAP_NONE, self.inner.0 as _);
        }
    }
}

pub struct IfAddrsIterator<'a> {
    _head: &'a IfAddrs,
    next: *const IP_ADAPTER_ADDRESSES_LH,
}

impl<'a> Iterator for IfAddrsIterator<'a> {
    type Item = IpAdapterAddresses;

    #[allow(unsafe_code)]
    fn next(&mut self) -> Option<Self::Item> {
        if self.next.is_null() {
            return None;
        };

        Some(unsafe {
            let result = &*self.next;
            self.next = (*self.next).Next;

            IpAdapterAddresses(result)
        })
    }
}

pub struct PrefixesIterator<'a> {
    _head: &'a IP_ADAPTER_ADDRESSES_LH,
    next: *const IP_ADAPTER_PREFIX_XP,
}

impl<'a> Iterator for PrefixesIterator<'a> {
    type Item = &'a IP_ADAPTER_PREFIX_XP;

    #[allow(unsafe_code)]
    fn next(&mut self) -> Option<Self::Item> {
        if self.next.is_null() {
            return None;
        };

        Some(unsafe {
            let result = &*self.next;
            self.next = (*self.next).Next;

            result
        })
    }
}

pub struct UnicastAddressesIterator<'a> {
    _head: &'a IP_ADAPTER_ADDRESSES_LH,
    next: *const IP_ADAPTER_UNICAST_ADDRESS_LH,
}

impl<'a> Iterator for UnicastAddressesIterator<'a> {
    type Item = &'a IP_ADAPTER_UNICAST_ADDRESS_LH;

    #[allow(unsafe_code)]
    fn next(&mut self) -> Option<Self::Item> {
        if self.next.is_null() {
            return None;
        };

        Some(unsafe {
            let result = &*self.next;
            self.next = (*self.next).Next;

            result
        })
    }
}

pub struct WindowsIfChangeNotifier {
    handle: HANDLE,
    // maintain constant memory address for callback fn
    tx: *mut Sender<()>,
    rx: Receiver<()>,
}

impl WindowsIfChangeNotifier {
    pub fn new() -> io::Result<Self> {
        let (tx, rx) = channel();
        let mut ret = Self {
            handle: std::ptr::null_mut(),
            tx: Box::into_raw(Box::new(tx)),
            rx,
        };
        let stat = unsafe {
            // Notes on the function used here and alternatives that were
            // considered:
            //
            // NotifyAddrChange works pretty well, but only for IPv4, and the
            // API itself is a little awkward, requiring overlapped IO
            //
            // NotifyRouteChange2 doesn't catch interfaces going away (e.g.
            // unplugging ethernet, going into airplane mode)
            //
            // WlanRegisterNotification is only for WiFi
            //
            // Monitoring changes to MSFT_NetAdapter is possible, but requires
            // WMI/COM, which is undesirable
            //
            // NotifyIpInterfaceChange produces several spurious messages
            // (mostly related to WiFi speed, it seems), but they aren't too
            // frequent (at most, I've seen a batch of 3 every 10 seconds), so
            // don't pose a performance concern
            NotifyIpInterfaceChange(
                AF_UNSPEC,
                Some(if_change_callback),
                ret.tx as *const c_void,
                false,
                &mut ret.handle,
            )
        };
        if stat != 0 {
            Err(io::Error::from_raw_os_error(stat as i32))
        } else {
            Ok(ret)
        }
    }

    pub fn wait(&self, timeout: Option<Duration>) -> io::Result<()> {
        if let Some(timeout) = timeout {
            self.rx.recv_timeout(timeout)
        } else {
            self.rx.recv().map_err(RecvTimeoutError::from)
        }
        .map_err(|_| io::Error::new(io::ErrorKind::WouldBlock, "Timed out"))
    }
}

impl Drop for WindowsIfChangeNotifier {
    fn drop(&mut self) {
        if !self.handle.is_null() {
            unsafe { CancelMibChangeNotify2(self.handle) };
        }
        unsafe { drop(Box::from_raw(self.tx)) };
    }
}

unsafe extern "system" fn if_change_callback(
    ctx: *const c_void,
    _row: *const MIB_IPINTERFACE_ROW,
    _notificationtype: MIB_NOTIFICATION_TYPE,
) {
    if let Some(tx) = (ctx as *const Sender<()>).as_ref() {
        tx.send(()).ok();
    };

    // note: `row` not used, as for all changes that we care for (interface
    // add/remove), all the member values are 0, so it's useless.
}
