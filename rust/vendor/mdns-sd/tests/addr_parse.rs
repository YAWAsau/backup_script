use mdns_sd::AsIpAddrs;
use std::collections::HashSet;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

#[test]
fn test_addr_str() {
    assert_eq!(
        "127.0.0.1".as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());

            set
        })
    );

    let addr = "127.0.0.1".to_string();
    assert_eq!(
        addr.as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());

            set
        })
    );

    // verify that `&String` also works.
    assert_eq!(
        addr.as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());

            set
        })
    );

    assert_eq!(
        "127.0.0.1,127.0.0.2".as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());
            set.insert(Ipv4Addr::new(127, 0, 0, 2).into());

            set
        })
    );

    let addr = "2001:db8::1".to_string();
    assert_eq!(
        addr.as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1).into());

            set
        })
    );

    assert_eq!(
        "2001:db8::1,2001:db8::2".as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1).into());
            set.insert(Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 2).into());

            set
        })
    );

    // verify that an empty string parsed into an empty set.
    assert_eq!("".as_ip_addrs(), Ok(HashSet::new()));
}

#[test]
fn test_addr_slice() {
    assert_eq!(
        (&["127.0.0.1"][..]).as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());

            set
        })
    );

    assert_eq!(
        (&["127.0.0.1", "127.0.0.2"][..]).as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());
            set.insert(Ipv4Addr::new(127, 0, 0, 2).into());

            set
        })
    );

    assert_eq!(
        (&vec!["127.0.0.1", "127.0.0.2"][..]).as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());
            set.insert(Ipv4Addr::new(127, 0, 0, 2).into());

            set
        })
    );

    assert_eq!(
        (&vec!["2001:db8::1", "2001:db8::2"][..]).as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 1).into());
            set.insert(Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, 2).into());

            set
        })
    );
}

#[test]
fn test_addr_ip() {
    let ip: IpAddr = Ipv4Addr::new(127, 0, 0, 1).into();

    assert_eq!(
        ip.as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());

            set
        })
    );

    assert_eq!(
        ip.as_ip_addrs(),
        Ok({
            let mut set = HashSet::new();
            set.insert(Ipv4Addr::new(127, 0, 0, 1).into());

            set
        })
    );
}
