use std::fmt::{Debug, Formatter};
use std::io::{Error, ErrorKind};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::os::windows::io::{AsRawSocket, RawSocket};
use std::{io, mem, ptr};

use socket2::{Domain, Protocol, SockAddr, SockAddrStorage, Socket, Type};
use windows_sys::core::{PCSTR, PSTR};
use windows_sys::Win32::Networking::WinSock::{
    self, CMSGHDR, IN6_PKTINFO, IN_PKTINFO, IPPROTO_IP, IPPROTO_IPV6, IPV6_PKTINFO, IP_PKTINFO,
    LPFN_WSARECVMSG, LPWSAOVERLAPPED_COMPLETION_ROUTINE, SIO_GET_EXTENSION_FUNCTION_POINTER,
    SOCKET, WSABUF, WSAID_WSARECVMSG, WSAMSG,
};
use windows_sys::Win32::System::IO::OVERLAPPED;

use crate::PktInfo;

const CMSG_HEADER_SIZE: usize = mem::size_of::<CMSGHDR>();
const PKTINFOV4_DATA_SIZE: usize = mem::size_of::<IN_PKTINFO>();
const PKTINFOV6_DATA_SIZE: usize = mem::size_of::<IN6_PKTINFO>();
const CONTROL_PKTINFOV4_BUFFER_SIZE: usize = CMSG_HEADER_SIZE + PKTINFOV4_DATA_SIZE;
const CONTROL_PKTINFOV6_BUFFER_SIZE: usize = CMSG_HEADER_SIZE + PKTINFOV6_DATA_SIZE + 8;

unsafe fn setsockopt<T>(socket: RawSocket, opt: i32, val: i32, payload: T) -> io::Result<()>
where
    T: Copy,
{
    let payload = &payload as *const T as PCSTR;
    if WinSock::setsockopt(socket as _, opt, val, payload, mem::size_of::<T>() as i32) == 0 {
        Ok(())
    } else {
        Err(Error::from_raw_os_error(WinSock::WSAGetLastError()))
    }
}

type WSARecvMsgExtension = unsafe extern "system" fn(
    s: SOCKET,
    lpMsg: *mut WSAMSG,
    lpdwNumberOfBytesRecvd: *mut u32,
    lpOverlapped: *mut OVERLAPPED,
    lpCompletionRoutine: LPWSAOVERLAPPED_COMPLETION_ROUTINE,
) -> i32;

fn locate_wsarecvmsg(socket: RawSocket) -> io::Result<WSARecvMsgExtension> {
    let mut fn_pointer: usize = 0;
    let mut byte_len: u32 = 0;

    let r = unsafe {
        WinSock::WSAIoctl(
            socket as _,
            SIO_GET_EXTENSION_FUNCTION_POINTER,
            &WSAID_WSARECVMSG as *const _ as *mut _,
            mem::size_of_val(&WSAID_WSARECVMSG) as u32,
            &mut fn_pointer as *const _ as *mut _,
            mem::size_of_val(&fn_pointer) as u32,
            &mut byte_len,
            ptr::null_mut(),
            None,
        )
    };
    if r != 0 {
        return Err(Error::last_os_error());
    }

    if mem::size_of::<LPFN_WSARECVMSG>() != byte_len as _ {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            "Locating fn pointer to WSARecvMsg returned different expected bytes",
        ));
    }
    let cast_to_fn: LPFN_WSARECVMSG = unsafe { mem::transmute(fn_pointer) };

    match cast_to_fn {
        None => Err(io::Error::new(
            io::ErrorKind::Other,
            "WSARecvMsg extension not found",
        )),
        Some(extension) => Ok(extension),
    }
}

pub struct PktInfoUdpSocket {
    socket: Socket,
    domain: Domain,
    wsarecvmsg: WSARecvMsgExtension,
}

impl Debug for PktInfoUdpSocket {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        self.socket.fmt(f)
    }
}

impl AsRawSocket for PktInfoUdpSocket {
    fn as_raw_socket(&self) -> RawSocket {
        self.socket.as_raw_socket()
    }
}

impl PktInfoUdpSocket {
    pub fn new(domain: Domain) -> io::Result<PktInfoUdpSocket> {
        let socket = Socket::new(domain, Type::DGRAM, Some(Protocol::UDP))?;

        match domain {
            Domain::IPV4 => unsafe {
                setsockopt(socket.as_raw_socket(), IPPROTO_IP, IP_PKTINFO, true as i32)?;
            },
            Domain::IPV6 => unsafe {
                setsockopt(
                    socket.as_raw_socket(),
                    IPPROTO_IPV6,
                    IPV6_PKTINFO,
                    true as i32,
                )?;
            },
            _ => return Err(Error::from(ErrorKind::Unsupported)),
        }

        let wsarecvmsg: WSARecvMsgExtension = locate_wsarecvmsg(socket.as_raw_socket())?;

        Ok(PktInfoUdpSocket {
            socket,
            domain,
            wsarecvmsg,
        })
    }

    pub fn domain(&self) -> Domain {
        self.domain
    }
    pub fn set_reuse_address(&self, reuse: bool) -> io::Result<()> {
        self.socket.set_reuse_address(reuse)
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
        let mut data = WSABUF {
            buf: buf.as_mut_ptr() as PSTR,
            len: buf.len() as u32,
        };

        let mut control_buffer = [0; CONTROL_PKTINFOV6_BUFFER_SIZE]; // Allocate the largest possible buffer
        let control = WSABUF {
            buf: control_buffer.as_mut_ptr(),
            len: match self.domain {
                Domain::IPV4 => CONTROL_PKTINFOV4_BUFFER_SIZE as u32,
                Domain::IPV6 => CONTROL_PKTINFOV6_BUFFER_SIZE as u32,
                _ => unreachable!(),
            },
        };

        let mut addr = SockAddrStorage::zeroed();
        let mut wsa_msg = WSAMSG {
            name: &mut addr as *mut _ as *mut _,
            namelen: addr.size_of(),
            lpBuffers: &mut data,
            Control: control,
            dwBufferCount: 1,
            dwFlags: 0,
        };

        let mut read_bytes = 0;
        let error_code = {
            unsafe {
                (self.wsarecvmsg)(
                    self.socket.as_raw_socket() as _,
                    &mut wsa_msg,
                    &mut read_bytes,
                    ptr::null_mut(),
                    None,
                )
            }
        };

        if error_code != 0 {
            return Err(io::Error::last_os_error());
        }

        let len = addr.size_of();
        let addr_src = unsafe { SockAddr::new(addr, len) }.as_socket().unwrap();

        let mut info: Option<PktInfo> = None;

        if control.len as usize == CONTROL_PKTINFOV4_BUFFER_SIZE {
            let cmsg_header: CMSGHDR = unsafe { ptr::read_unaligned(control.buf as *const _) };
            if cmsg_header.cmsg_level == IPPROTO_IP && cmsg_header.cmsg_type == IP_PKTINFO {
                let interface_info: IN_PKTINFO =
                    unsafe { ptr::read_unaligned(control.buf.add(CMSG_HEADER_SIZE) as *const _) };

                let addr_dst = IpAddr::V4(unsafe {
                    Ipv4Addr::from(u32::from_be(interface_info.ipi_addr.S_un.S_addr))
                });

                info = Some(PktInfo {
                    if_index: interface_info.ipi_ifindex as u64,
                    addr_src,
                    addr_dst,
                })
            }
        } else if control.len as usize == CONTROL_PKTINFOV6_BUFFER_SIZE {
            let cmsg_header: CMSGHDR = unsafe { ptr::read_unaligned(control.buf as *const _) };
            if cmsg_header.cmsg_level == IPPROTO_IPV6 && cmsg_header.cmsg_type == IPV6_PKTINFO {
                let interface_info: IN6_PKTINFO =
                    unsafe { ptr::read_unaligned(control.buf.add(CMSG_HEADER_SIZE) as *const _) };

                let addr_dst =
                    IpAddr::V6(Ipv6Addr::from(unsafe { interface_info.ipi6_addr.u.Byte }));
                info = Some(PktInfo {
                    if_index: interface_info.ipi6_ifindex as u64,
                    addr_src,
                    addr_dst,
                })
            }
        }

        match info {
            None => Err(Error::new(
                ErrorKind::NotFound,
                "Failed to read PKTINFO from socket",
            )),
            Some(info) => Ok((read_bytes as usize, info)),
        }
    }

    /// Creates a new independently owned std UdpSocket from this PktInfoUdpSocket.
    ///
    /// This is useful to mix and match functionality from this crate with stdlib or other crates.
    pub fn try_clone_std(&self) -> io::Result<std::net::UdpSocket> {
        Ok(self.socket.try_clone()?.into())
    }
}
