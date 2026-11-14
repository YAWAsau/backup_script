//! Small library to allow cross-platform handling of IP_PKTINFO and IPV6_PKTINFO with socket2 crate.
//!
//! Primary use case for this crate is to determine if a UDP packet was sent to a unicast, broadcast or multicast IP address.
//!
//! Library implements a cross-platform wrapper [`crate::PktInfoUdpSocket`] around [`socket2::Socket`] which returns data extracted from
//! the IP_PKTINFO and IPV6_PKTINFO control messages. Compatible with Windows, Linux and macOS.
//!
//! # Examples
//!
//! ```no_run
//! use std::net::{Ipv4Addr, SocketAddrV4};
//! use socket2::{Domain, SockAddr};
//! use socket_pktinfo::PktInfoUdpSocket;
//!
//! # fn main() -> std::io::Result<()> {
//!
//! let mut buf = [0; 1024];
//! let mut socket = PktInfoUdpSocket::new(Domain::IPV4)?;
//! socket.bind(&SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 8000).into())?;
//!
//! match socket.recv(&mut buf) {//!
//!     Ok((bytes_received, info)) => {
//!         println!("{} bytes received on interface index {} from src {} with destination ip {}",
//!          bytes_received, info.if_index, info.addr_src, info.addr_dst);
//!     }
//!     Err(e) => {
//!         eprintln!("Error receiving packet - {}", e);
//!     }
//! }
//! # Ok(())
//! # }
//! ```

#![allow(clippy::unnecessary_cast)]

#[cfg(windows)]
mod win;
#[cfg(windows)]
pub use win::*;

#[cfg(not(windows))]
mod unix;
#[cfg(not(windows))]
pub use unix::*;

///
#[derive(Debug, Clone)]
pub struct PktInfo {
    /// Interface index
    pub if_index: u64,
    /// Source address
    pub addr_src: std::net::SocketAddr,
    /// Header destination address
    pub addr_dst: std::net::IpAddr,
}
