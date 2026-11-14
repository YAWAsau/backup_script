// Copyright 2018 MaidSafe.net limited.
//
// This SAFE Network Software is licensed to you under the MIT license <LICENSE-MIT
// http://opensource.org/licenses/MIT> or the Modified BSD license <LICENSE-BSD
// https://opensource.org/licenses/BSD-3-Clause>, at your option. This file may not be copied,
// modified, or distributed except according to those terms. Please review the Licences for the
// specific language governing permissions and limitations relating to use of the SAFE Network
// Software.

#[cfg(not(windows))]
use libc::{sockaddr, sockaddr_in, sockaddr_in6, AF_INET, AF_INET6};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::ptr::NonNull;
#[cfg(windows)]
use windows_sys::Win32::Networking::WinSock::{
    AF_INET, AF_INET6, SOCKADDR as sockaddr, SOCKADDR_IN as sockaddr_in,
    SOCKADDR_IN6 as sockaddr_in6,
};

pub fn to_ipaddr(sockaddr: *const sockaddr) -> Option<IpAddr> {
    if sockaddr.is_null() {
        return None;
    }
    SockAddr::new(sockaddr)?.as_ipaddr()
}

// Wrapper around a sockaddr pointer. Guaranteed to not be null.
struct SockAddr {
    inner: NonNull<sockaddr>,
}

impl SockAddr {
    #[allow(clippy::new_ret_no_self)]
    fn new(sockaddr: *const sockaddr) -> Option<Self> {
        NonNull::new(sockaddr as *mut _).map(|inner| Self { inner })
    }

    #[cfg(not(windows))]
    fn as_ipaddr(&self) -> Option<IpAddr> {
        match self.sockaddr_in() {
            Some(SockAddrIn::In(sa)) => {
                let b = sa.sin_addr.s_addr.to_ne_bytes();
                Some(IpAddr::V4(Ipv4Addr::new(b[0], b[1], b[2], b[3])))
            }
            Some(SockAddrIn::In6(sa)) => {
                // Ignore all fe80:: addresses as these are link locals
                #[cfg(not(feature = "link-local"))]
                if sa.sin6_addr.s6_addr[0] == 0xfe && sa.sin6_addr.s6_addr[1] == 0x80 {
                    return None;
                }
                Some(IpAddr::V6(Ipv6Addr::from(sa.sin6_addr.s6_addr)))
            }
            None => None,
        }
    }

    #[cfg(windows)]
    fn as_ipaddr(&self) -> Option<IpAddr> {
        match self.sockaddr_in() {
            Some(SockAddrIn::In(sa)) => {
                let s_addr = unsafe { sa.sin_addr.S_un.S_addr };
                // Ignore all 169.254.x.x addresses as these are not active interfaces
                #[cfg(not(feature = "link-local"))]
                if s_addr & 65535 == 0xfea9 {
                    return None;
                }
                let b = s_addr.to_ne_bytes();
                Some(IpAddr::V4(Ipv4Addr::new(b[0], b[1], b[2], b[3])))
            }
            Some(SockAddrIn::In6(sa)) => {
                let s6_addr = unsafe { sa.sin6_addr.u.Byte };
                // Ignore all fe80:: addresses as these are link locals
                #[cfg(not(feature = "link-local"))]
                if s6_addr[0] == 0xfe && s6_addr[1] == 0x80 {
                    return None;
                }
                Some(IpAddr::V6(Ipv6Addr::from(s6_addr.clone())))
            }
            None => None,
        }
    }

    fn sockaddr_in(&self) -> Option<SockAddrIn> {
        const AF_INET_U32: u32 = AF_INET as u32;
        const AF_INET6_U32: u32 = AF_INET6 as u32;

        match self.sa_family() {
            AF_INET_U32 => Some(SockAddrIn::In(self.sa_in())),
            AF_INET6_U32 => Some(SockAddrIn::In6(self.sa_in6())),
            _ => None,
        }
    }

    #[allow(unsafe_code)]
    fn sa_family(&self) -> u32 {
        unsafe { u32::from(self.inner.as_ref().sa_family) }
    }

    #[allow(unsafe_code)]
    #[allow(clippy::cast_ptr_alignment)]
    fn sa_in(&self) -> sockaddr_in {
        unsafe { *(self.inner.as_ptr() as *const sockaddr_in) }
    }

    #[allow(unsafe_code)]
    #[allow(clippy::cast_ptr_alignment)]
    fn sa_in6(&self) -> sockaddr_in6 {
        unsafe { *(self.inner.as_ptr() as *const sockaddr_in6) }
    }
}

enum SockAddrIn {
    In(sockaddr_in),
    In6(sockaddr_in6),
}
