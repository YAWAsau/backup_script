use network_interface::{NetworkInterface, NetworkInterfaceConfig};
use socket2::{Domain, Protocol, SockAddr, Socket, Type};
use socket_pktinfo::PktInfoUdpSocket;
use std::io;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};

#[test]
fn ipv4_test() -> io::Result<()> {
    let mut interfaces = NetworkInterface::show().unwrap();
    interfaces.sort_by(|a, b| a.index.cmp(&b.index));

    let interface = interfaces
        .into_iter()
        .find(|n| {
            !n.addr.iter().any(|a| a.ip().is_loopback()) && n.addr.iter().any(|a| a.ip().is_ipv4())
        })
        .expect("Can't run test without any IPv4 network interfaces");

    let local_ip = match interface
        .addr
        .iter()
        .find(|a| a.ip().is_ipv4())
        .unwrap()
        .ip()
    {
        IpAddr::V4(ip) => ip,
        IpAddr::V6(_) => unreachable!(),
    };

    println!(
        "Testing using network interface index {}, ip {}",
        interface.index, local_ip
    );

    let port = 8000;
    let multicast_addr = Ipv4Addr::new(238, 10, 20, 31);
    let local_addr: SockAddr = SocketAddr::new(IpAddr::V4(local_ip), port).into();
    let broadcast_socket_addr: SockAddr = SocketAddr::new(Ipv4Addr::BROADCAST.into(), port).into();
    let multicast_socket_addr: SockAddr = SocketAddr::new(multicast_addr.into(), port).into();

    let mut buf = [0; 1024];
    let socket = PktInfoUdpSocket::new(Domain::IPV4)?;
    socket.set_reuse_address(true)?;
    socket.set_multicast_if_v4(&local_ip)?;
    socket.join_multicast_v4(&multicast_addr, &local_ip)?;
    socket.set_multicast_loop_v4(true)?;
    socket.set_multicast_ttl_v4(255)?;
    socket.bind(&SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), port).into())?;

    let std_udp_socket = socket.try_clone_std()?;
    assert!(
        std_udp_socket.local_addr()? == SocketAddr::new(IpAddr::V4(Ipv4Addr::UNSPECIFIED), port)
    );

    {
        let output_socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
        let data = "Hello";
        output_socket.send_to(data.as_bytes(), &local_addr)?;
    }

    let (_, info) = socket.recv(&mut buf)?;
    println!(
        "Unicast packet received on interface index {} from src {} with destination ip {}",
        info.if_index, info.addr_src, info.addr_dst,
    );

    {
        let output_socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
        output_socket.set_broadcast(true)?;
        let data = "Hello";
        output_socket.send_to(data.as_bytes(), &broadcast_socket_addr)?;
    }

    let (_, info) = socket.recv(&mut buf)?;
    println!(
        "Broadcast packet received on interface index {} from src {} with destination ip {}",
        info.if_index, info.addr_src, info.addr_dst,
    );

    {
        let output_socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
        output_socket.set_multicast_if_v4(&local_ip)?;
        output_socket.set_multicast_loop_v4(true)?;
        let data = "Hello";
        output_socket.send_to(data.as_bytes(), &multicast_socket_addr)?;
    }

    let (_, info) = socket.recv(&mut buf)?;
    println!(
        "Multicast packet received on interface index {} from src {} with destination ip {}",
        info.if_index, info.addr_src, info.addr_dst,
    );

    Ok(())
}
