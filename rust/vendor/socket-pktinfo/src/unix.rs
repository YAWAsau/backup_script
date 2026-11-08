use std::fmt::{Debug, Formatter};
use std::io::{Error, ErrorKind, IoSliceMut};
use std::mem::MaybeUninit;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::os::unix::io::{AsRawFd, RawFd};
use std::{io, mem, ptr};

use socket2::{Domain, Protocol, SockAddr, SockAddrStorage, Socket, Type};

use crate::PktInfo;

unsafe fn setsockopt<T>(
    socket: libc::c_int,
    level: libc::c_int,
    name: libc::c_int,
    value: T,
) -> io::Result<()>
where
    T: Copy,
{
    let value = &value as *const T as *const libc::c_void;
    if libc::setsockopt(
        socket,
        level,
        name,
        value,
        mem::size_of::<T>() as libc::socklen_t,
    ) == 0
    {
        Ok(())
    } else {
        Err(Error::last_os_error())
    }
}

//
pub struct PktInfoUdpSocket {
    socket: Socket,
    domain: Domain,
}

impl Debug for PktInfoUdpSocket {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        self.socket.fmt(f)
    }
}

impl AsRawFd for PktInfoUdpSocket {
    fn as_raw_fd(&self) -> RawFd {
        self.socket.as_raw_fd()
    }
}

impl PktInfoUdpSocket {
    pub fn new(domain: Domain) -> io::Result<PktInfoUdpSocket> {
        let socket = Socket::new(domain, Type::DGRAM, Some(Protocol::UDP))?;

        match domain {
            #[cfg(target_os = "freebsd")]
            Domain::IPV4 => unsafe {
                setsockopt(
                    socket.as_raw_fd(),
                    libc::IPPROTO_IP,
                    libc::IP_RECVDSTADDR,
                    1,
                )?;
                setsockopt(socket.as_raw_fd(), libc::IPPROTO_IP, libc::IP_RECVIF, 1)?;
            },
            #[cfg(not(target_os = "freebsd"))]
            Domain::IPV4 => unsafe {
                setsockopt(socket.as_raw_fd(), libc::IPPROTO_IP, libc::IP_PKTINFO, 1)?;
            },
            Domain::IPV6 => unsafe {
                setsockopt(
                    socket.as_raw_fd(),
                    libc::IPPROTO_IPV6,
                    libc::IPV6_RECVPKTINFO,
                    1,
                )?;
            },
            _ => return Err(Error::from(ErrorKind::Unsupported)),
        }

        Ok(PktInfoUdpSocket { socket, domain })
    }

    pub fn domain(&self) -> Domain {
        self.domain
    }
    pub fn set_reuse_address(&self, reuse: bool) -> io::Result<()> {
        self.socket.set_reuse_address(reuse)
    }

    pub fn set_reuse_port(&self, reuse: bool) -> io::Result<()> {
        self.socket.set_reuse_port(reuse)
    }

    pub fn join_multicast_v4(&self, addr: &Ipv4Addr, interface: &Ipv4Addr) -> io::Result<()> {
        self.socket.join_multicast_v4(addr, interface)
    }

    /// Drop membership in a multicast group for IPv4.
    pub fn leave_multicast_v4(&self, addr: &Ipv4Addr, interface: &Ipv4Addr) -> io::Result<()> {
        self.socket.leave_multicast_v4(addr, interface)
    }

    pub fn set_multicast_if_v4(&self, interface: &Ipv4Addr) -> io::Result<()> {
        self.socket.set_multicast_if_v4(interface)
    }

    pub fn set_multicast_loop_v4(&self, loop_v4: bool) -> io::Result<()> {
        self.socket.set_multicast_loop_v4(loop_v4)
    }

    pub fn set_multicast_ttl_v4(&self, ttl: u32) -> io::Result<()> {
        self.socket.set_multicast_ttl_v4(ttl)
    }

    pub fn join_multicast_v6(&self, addr: &Ipv6Addr, interface: u32) -> io::Result<()> {
        self.socket.join_multicast_v6(addr, interface)
    }

    /// Drop membership in a multicast group for IPv6.
    pub fn leave_multicast_v6(&self, addr: &Ipv6Addr, interface: u32) -> io::Result<()> {
        self.socket.leave_multicast_v6(addr, interface)
    }

    pub fn set_multicast_if_v6(&self, interface: u32) -> io::Result<()> {
        self.socket.set_multicast_if_v6(interface)
    }

    pub fn set_multicast_loop_v6(&self, loop_v6: bool) -> io::Result<()> {
        self.socket.set_multicast_loop_v6(loop_v6)
    }

    pub fn set_multicast_hops_v6(&self, hops: u32) -> io::Result<()> {
        self.socket.set_multicast_hops_v6(hops)
    }

    pub fn set_nonblocking(&self, reuse: bool) -> io::Result<()> {
        self.socket.set_nonblocking(reuse)
    }

    pub fn bind(&self, addr: &SockAddr) -> io::Result<()> {
        self.socket.bind(addr)
    }

    pub fn send(&self, buf: &[u8]) -> io::Result<usize> {
        self.socket.send(buf)
    }

    pub fn send_to(&self, buf: &[u8], addr: &SockAddr) -> io::Result<usize> {
        self.socket.send_to(buf, addr)
    }

    pub fn recv(&self, buf: &mut [u8]) -> io::Result<(usize, PktInfo)> {
        let mut addr_src = SockAddrStorage::zeroed();
        let mut msg_iov = IoSliceMut::new(buf);
        let mut cmsg = {
            let space = if self.domain == Domain::IPV4 {
                #[cfg(target_os = "freebsd")]
                unsafe {
                    libc::CMSG_SPACE(mem::size_of::<libc::in_addr>() as libc::c_uint) as usize
                        + libc::CMSG_SPACE(mem::size_of::<libc::sockaddr_dl>() as libc::c_uint)
                            as usize
                }
                #[cfg(not(target_os = "freebsd"))]
                unsafe {
                    libc::CMSG_SPACE(mem::size_of::<libc::in_pktinfo>() as libc::c_uint) as usize
                }
            } else {
                unsafe {
                    libc::CMSG_SPACE(mem::size_of::<libc::in6_pktinfo>() as libc::c_uint) as usize
                }
            };
            Vec::<u8>::with_capacity(space)
        };

        let mut mhdr = unsafe {
            let mut mhdr = MaybeUninit::<libc::msghdr>::zeroed();
            let p = mhdr.as_mut_ptr();
            (*p).msg_name = addr_src.view_as::<libc::c_void>();
            (*p).msg_namelen = mem::size_of::<libc::sockaddr_storage>() as libc::socklen_t;
            (*p).msg_iov = &mut msg_iov as *mut IoSliceMut as *mut libc::iovec;
            (*p).msg_iovlen = 1;
            (*p).msg_control = cmsg.as_mut_ptr() as *mut libc::c_void;
            (*p).msg_controllen = cmsg.capacity() as _;
            (*p).msg_flags = 0;
            mhdr.assume_init()
        };

        let bytes_recv =
            unsafe { libc::recvmsg(self.socket.as_raw_fd(), &mut mhdr as *mut libc::msghdr, 0) };
        if bytes_recv <= 0 {
            return Err(Error::last_os_error());
        }

        let len = addr_src.size_of();
        let addr_src = unsafe { SockAddr::new(addr_src, len) }.as_socket().unwrap();

        let mut header = if mhdr.msg_controllen > 0 {
            debug_assert!(!mhdr.msg_control.is_null());
            debug_assert!(cmsg.capacity() >= mhdr.msg_controllen as usize);

            Some(unsafe {
                libc::CMSG_FIRSTHDR(&mhdr as *const libc::msghdr)
                    .as_ref()
                    .unwrap()
            })
        } else {
            None
        };

        let (mut addr_dst, mut if_index) = (None, None);

        while let Some(h) = header {
            if addr_dst.is_some() && if_index.is_some() {
                break;
            }

            let p = unsafe { libc::CMSG_DATA(h) };

            match (h.cmsg_level, h.cmsg_type) {
                #[cfg(not(target_os = "freebsd"))]
                (libc::IPPROTO_IP, libc::IP_PKTINFO) => {
                    let pktinfo = unsafe { ptr::read_unaligned(p as *const libc::in_pktinfo) };
                    if_index = Some(pktinfo.ipi_ifindex as u64);
                    addr_dst = Some(IpAddr::V4(Ipv4Addr::from(u32::from_be(
                        pktinfo.ipi_addr.s_addr,
                    ))));
                }
                #[cfg(target_os = "freebsd")]
                (libc::IPPROTO_IP, libc::IP_RECVDSTADDR) => {
                    let in_addr = unsafe { ptr::read_unaligned(p as *const libc::in_addr) };
                    addr_dst = Some(IpAddr::V4(Ipv4Addr::from(in_addr.s_addr.to_ne_bytes())));
                }
                #[cfg(target_os = "freebsd")]
                (libc::IPPROTO_IP, libc::IP_RECVIF) => {
                    let sockaddr = unsafe { ptr::read_unaligned(p as *const libc::sockaddr_dl) };
                    if_index = Some(sockaddr.sdl_index as u64);
                }
                (libc::IPPROTO_IPV6, libc::IPV6_PKTINFO) => {
                    let pktinfo = unsafe { ptr::read_unaligned(p as *const libc::in6_pktinfo) };
                    if_index = Some(pktinfo.ipi6_ifindex as u64);
                    addr_dst = Some(IpAddr::V6(Ipv6Addr::from(pktinfo.ipi6_addr.s6_addr)));
                }
                _ => {}
            }

            header = unsafe {
                let p = libc::CMSG_NXTHDR(&mhdr as *const _, h as *const _);
                p.as_ref()
            };
        }

        match addr_dst {
            None => Err(Error::new(
                ErrorKind::NotFound,
                "Failed to read PKTINFO from socket",
            )),
            Some(addr_dst) => Ok((
                bytes_recv as _,
                PktInfo {
                    if_index: if_index.unwrap_or_default(),
                    addr_src,
                    addr_dst,
                },
            )),
        }
    }

    /// Creates a new independently owned std UdpSocket from this PktInfoUdpSocket.
    ///
    /// This is useful to mix and match functionality from this crate with stdlib or other crates.
    pub fn try_clone_std(&self) -> io::Result<std::net::UdpSocket> {
        Ok(self.socket.try_clone()?.into())
    }
}
