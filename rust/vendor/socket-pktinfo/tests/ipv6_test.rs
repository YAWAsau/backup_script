use network_interface::{NetworkInterface, NetworkInterfaceConfig};
use socket2::{Domain, Protocol, SockAddr, Socket, Type};
use socket_pktinfo::PktInfoUdpSocket;
use std::io;
use std::net::{IpAddr, Ipv6Addr, SocketAddr, SocketAddrV6};
use std::str::FromStr;

#[test]
fn ipv6_test() -> io::Result<()> {
    let mut interfaces = NetworkInterface::show().unwrap();
    interfaces.sort_by(|a, b| a.index.cmp(&b.index));

    let interface = interfaces
        .into_iter()
        .find(|n| {
            !n.addr.iter().any(|a| a.ip().is_loopback()) && n.addr.iter().any(|a| a.ip().is_ipv6())
        })
        .expect("Can't run test without any IPv6 network interfaces");

    let local_ip = interface
        .addr
        .iter()
        .find(|a| a.ip().is_ipv6())
        .unwrap()
        .ip();

    println!(
        "Testing using network interface index {}, ip {}",
        interface.index, local_ip
    );

    let port = 8000;
    let multicast_addr = Ipv6Addr::from_str("ff12::1").unwrap();
    let IpAddr::V6(local_ipv6) = local_ip else {
        panic!("Expected IPv6");
    };
    let local_addr: SockAddr = SocketAddrV6::new(local_ipv6, port, 0, interface.index).into();
    let multicast_socket_addr: SockAddr = SocketAddr::new(multicast_addr.into(), port).into();

    let mut buf = [0; 8972];
    let socket = PktInfoUdpSocket::new(Domain::IPV6)?;
    socket.set_reuse_address(true)?;
    socket.join_multicast_v6(&multicast_addr, interface.index)?;
    socket.set_multicast_loop_v6(true)?;
    socket.set_multicast_hops_v6(255)?;
    socket.bind(&local_addr)?;

    let std_udp_socket = socket.try_clone_std()?;
    assert_eq!(
        std_udp_socket.local_addr()?,
        local_addr.as_socket().unwrap()
    );

    {
        let output_socket = Socket::new(Domain::IPV6, Type::DGRAM, Some(Protocol::UDP))?;
        let data = "Hello";
        output_socket.send_to(data.as_bytes(), &local_addr)?;
    }

    let (_, info) = socket.recv(&mut buf)?;
    println!(
        "Unicast packet received on interface index {} from src {} with destination ip {}",
        info.if_index, info.addr_src, info.addr_dst
    );

    {
        let output_socket = Socket::new(Domain::IPV6, Type::DGRAM, Some(Protocol::UDP))?;
        output_socket.set_multicast_if_v6(interface.index)?;
        output_socket.set_multicast_loop_v6(true)?;
        let data = "Hello";
        output_socket.send_to(data.as_bytes(), &multicast_socket_addr)?;
    }

    let (_, info) = socket.recv(&mut buf)?;
    println!(
        "Multicast packet received on interface index {} from src {} with destination ip {}",
        info.if_index, info.addr_src, info.addr_dst,
    );
    assert!(info.if_index != 0);

    Ok(())
}
