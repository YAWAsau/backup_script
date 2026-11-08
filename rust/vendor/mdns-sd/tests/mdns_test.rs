use if_addrs::{IfAddr, Interface};
use mdns_sd::{
    DaemonEvent, DaemonStatus, HostnameResolutionEvent, IfKind, InterfaceId, IntoTxtProperties,
    RRType, ScopedIp, ServiceDaemon, ServiceEvent, ServiceInfo, TxtProperty, UnregisterStatus,
};
use std::collections::{HashMap, HashSet};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::thread::sleep;
use std::time::{Duration, SystemTime};
use test_log::test;

/// This test covers:
/// register(announce), browse(query), response, unregister, shutdown.
#[test]
fn integration_success() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service
    let ty_domain = "_mdns-sd-it._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.

    let all_interfaces = my_ip_interfaces();
    println!("all interfaces count: {}", all_interfaces.len());
    // as we send only once per interface and ip we need a count of unique addresses to verify number of sent unregisters later on
    let mut unique_intf_idx_ip_ver_set = HashSet::new();
    let mut non_idx_count = 0;
    for intf in all_interfaces.iter() {
        let ip_ver = match intf.addr {
            IfAddr::V4(_) => 4u8,
            IfAddr::V6(_) => 6u8,
        };

        // use the same approach as `IntfSock.multicast_send_tracker`
        if let Some(idx) = intf.index {
            if !unique_intf_idx_ip_ver_set.insert((idx, ip_ver)) {
                println!("index {idx} IP v{ip_ver} repeated on interface {}, likely multi-addr on the same interface", intf.name);
            }
        } else {
            non_idx_count += 1;
        }
    }
    let unique_intf_idx_ip_ver_count = unique_intf_idx_ip_ver_set.len() + non_idx_count;

    let ifaddrs_set: HashSet<_> = all_interfaces.iter().map(|intf| intf.ip()).collect();
    let my_ifaddrs: Vec<_> = ifaddrs_set.into_iter().collect();
    let my_addrs_count = my_ifaddrs.len();
    println!("My IP {} addr(s):", my_ifaddrs.len());
    for item in my_ifaddrs.iter() {
        println!("{}", item);
    }

    let host_name = "INTEGRATION_host.local.";
    let port = 5200;
    let mut properties = HashMap::new();
    properties.insert("property_1".to_string(), "test".to_string());
    properties.insert("property_2".to_string(), "1".to_string());
    properties.insert("property_3".to_string(), "1234".to_string());

    let my_service = ServiceInfo::new(
        ty_domain,
        &instance_name,
        host_name,
        &my_ifaddrs[..],
        port,
        Some(properties),
    )
    .expect("valid service info");
    let fullname = my_service.get_fullname().to_string();
    d.register(my_service)
        .expect("Failed to register our service");

    // Browse for a service
    let mut resolved_ips: HashSet<IpAddr> = HashSet::new();
    let mut addr_count = 0;

    let browse_chan = d.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::SearchStarted(ty_domain) => {
                println!("Search started for {}", ty_domain);
            }
            ServiceEvent::ServiceFound(_ty_domain, fullname) => {
                println!("Found a new service: {}", fullname);
            }
            ServiceEvent::ServiceResolved(info) => {
                let addrs: HashSet<_> = info
                    .get_addresses()
                    .iter()
                    .map(|a| a.to_ip_addr())
                    .collect();
                addr_count = addrs.len();

                println!(
                    "Resolved a new service: {} with {} addr(s)",
                    info.get_fullname(),
                    addrs.len()
                );
                for a in addrs.iter() {
                    println!("{}", a);
                }
                if info.get_fullname().contains(&instance_name) {
                    resolved_ips.extend(addrs);
                }
                let hostname = info.get_hostname();
                assert_eq!(hostname, host_name);

                let service_port = info.get_port();
                assert_eq!(service_port, port);

                let properties = info.get_properties();
                assert!(properties.get("property_1").is_some());
                assert!(properties.get("property_2").is_some());
                assert_eq!(properties.len(), 3);
                assert!(info.get_property("property_1").is_some());
                assert!(info.get_property("property_2").is_some());
                assert_eq!(info.get_property_val_str("property_1"), Some("test"));
                assert_eq!(info.get_property_val_str("property_2"), Some("1"));
                assert_eq!(
                    info.get_property_val("property_1").unwrap(),
                    Some("test".as_bytes())
                );
            }
            _ => {}
        }
    }

    // All addrs should have been resolved.
    assert_eq!(addr_count, my_addrs_count);

    // IP's can get resolved more than once if fx a cache-flush is asked from the sender of the
    // MDNS records, so we look at unique IP addresses to see if they match the number of the
    // network interfaces.
    assert_eq!(resolved_ips.len(), my_addrs_count);
    assert!(!resolved_ips.is_empty());

    // Unregister the service
    let receiver = d.unregister(&fullname).unwrap();
    let response = receiver.recv().unwrap();
    assert!(matches!(response, UnregisterStatus::OK));

    let mut remove_count = 0;
    let mut resolved = false;
    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceRemoved(_ty_domain, fullname) => {
                println!("Removed service: {}", fullname);
                if fullname.contains(&instance_name) {
                    remove_count += 1;
                }
                break;
            }
            ServiceEvent::ServiceResolved(info) if info.get_fullname() == fullname => {
                println!("Received a resolved service event after unregister");
                resolved = true;
            }
            _ => {}
        }
    }

    assert_eq!(remove_count, 1);
    assert!(
        !resolved,
        "Resolved event should not be received after unregister"
    );

    // Stop browsing the service.
    d.stop_browse(ty_domain).expect("Failed to stop browsing");

    let mut stopped_count = 0;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        if let ServiceEvent::SearchStopped(ty) = event {
            println!("Search stopped for {}", ty);
            stopped_count += 1;
            break;
        }
    }

    assert_eq!(stopped_count, 1);

    // Verify metrics.
    let metrics_receiver = d.get_metrics().unwrap();
    let metrics = metrics_receiver.recv().unwrap();
    println!("metrics: {:?}", metrics);
    assert_eq!(metrics["register"], 1);
    assert_eq!(metrics["unregister"], 1);
    assert!(metrics["register-resend"] >= 1);

    println!("unique interface set: {:?}", unique_intf_idx_ip_ver_set);
    assert_eq!(
        metrics["unregister-resend"],
        unique_intf_idx_ip_ver_count as i64
    );
    assert!(metrics["browse"] >= 2); // browse has been retransmitted.

    // respond has been sent for every browse, or they are suppressed by "known answer".
    let respond_count = metrics.get("respond").unwrap_or(&0);
    let known_answer_count = metrics.get("known-answer-suppression").unwrap_or(&0);
    assert!(*respond_count >= 2 || *known_answer_count > 0);

    // Test the special meta-query of "_services._dns-sd._udp.local."
    let service2_type = "_my-service2._udp.local.";
    let service2_instance = "instance2";
    let service2 = ServiceInfo::new(
        service2_type,
        service2_instance,
        host_name,
        &my_ifaddrs[..],
        port,
        None,
    )
    .expect("valid service info");
    d.register(service2)
        .expect("Failed to register the 2nd service");

    // Browse using the special meta-query.
    let meta_query = "_services._dns-sd._udp.local.";
    let browse_chan = d.browse(meta_query).unwrap();
    let timeout = Duration::from_secs(2);

    loop {
        match browse_chan.recv_timeout(timeout) {
            Ok(event) => match event {
                ServiceEvent::ServiceFound(ty_domain, fullname) => {
                    println!("Found a service of {}: {}", ty_domain, fullname);
                    // Among all services found, should have our 2nd service.
                    if fullname == service2_type {
                        break;
                    }
                }
                e => {
                    println!("Received event {:?}", e);
                    sleep(Duration::from_millis(100));
                }
            },
            Err(e) => {
                panic!("browse error: {}", e);
            }
        }
    }

    // Shutdown
    d.shutdown().unwrap();
}

#[test]
fn service_without_properties_with_alter_net_v4() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service without properties.
    let ty_domain = "_serv-no-prop._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let if_addrs: Vec<Interface> = my_ip_interfaces()
        .into_iter()
        .filter(|iface| iface.addr.ip().is_ipv4())
        .collect();
    let first_ip = if_addrs[0].ip();
    let alter_ip = ipv4_alter_net(&if_addrs);
    let host_ip = vec![first_ip, alter_ip];
    let host_name = "serv-no-prop-v4.local.";
    let port = 5201;
    let my_service = ServiceInfo::new(
        ty_domain,
        &instance_name,
        host_name,
        &host_ip[..],
        port,
        None,
    )
    .expect("valid service info");
    let fullname = my_service.get_fullname().to_string();
    d.register(my_service)
        .expect("Failed to register our service");
    println!("Registered service with host_ip: {:?}", host_ip);

    // Browse for a service
    let browse_chan = d.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    let timer = std::time::Instant::now() + timeout;
    let mut found = false;
    while std::time::Instant::now() < timer {
        match browse_chan.recv_timeout(timeout) {
            Ok(event) => match event {
                ServiceEvent::ServiceResolved(info) => {
                    println!(
                        "Resolved a service of {} addr(s): {:?}",
                        info.get_fullname(),
                        info.get_addresses()
                    );
                    // match only our service and not v6 one
                    if info.get_addresses_v4().is_empty() {
                        continue;
                    }
                    if fullname.as_str() == info.get_fullname() {
                        let addrs = info.get_addresses_v4();
                        assert_eq!(addrs.len(), 1); // first_ipv4 but no alter_ipv.
                        found = true;
                        break;
                    }
                }
                e => {
                    println!("Received event {:?}", e);
                }
            },
            Err(e) => {
                panic!("browse error: {}", e);
            }
        }
    }

    d.shutdown().unwrap();
    assert!(found);
}

#[test]
fn service_without_properties_with_alter_net_v6() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service without properties.
    let ty_domain = "_serv-no-prop._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let if_addrs: Vec<Interface> = my_ip_interfaces()
        .into_iter()
        .filter(|iface| iface.addr.ip().is_ipv6())
        .collect();
    let first_ip = if_addrs[0].ip();
    let alter_ip = ipv6_alter_net(&if_addrs);
    let host_ip = vec![first_ip, alter_ip];
    let host_name = "serv-no-prop-v6.local.";
    let port = 5201;
    let my_service = ServiceInfo::new(
        ty_domain,
        &instance_name,
        host_name,
        &host_ip[..],
        port,
        None,
    )
    .expect("valid service info");
    let fullname = my_service.get_fullname().to_string();
    d.register(my_service)
        .expect("Failed to register our service");
    println!("Registered service with host_ip: {:?}", host_ip);

    // Browse for a service
    let browse_chan = d.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    let timer = std::time::Instant::now() + timeout;
    let mut found = false;
    while std::time::Instant::now() < timer {
        match browse_chan.recv_timeout(timeout) {
            Ok(event) => match event {
                ServiceEvent::ServiceResolved(info) => {
                    println!(
                        "Resolved a service of {} addr(s): {:?}",
                        info.get_fullname(),
                        info.get_addresses()
                    );
                    // match only our service and not v4 one
                    if fullname.as_str() == info.get_fullname() {
                        let addrs: Vec<_> = info
                            .get_addresses()
                            .iter()
                            .filter(|a| a.is_ipv6())
                            .collect();
                        if addrs.is_empty() {
                            continue; // In case IPv4 addr received first.
                        }
                        assert_eq!(addrs.len(), 1); // first_ipv6 but no alter_ipv.
                        found = true;
                        break;
                    }
                }
                e => {
                    println!("Received event {:?}", e);
                }
            },
            Err(e) => {
                panic!("browse error: {}", e);
            }
        }
    }

    d.shutdown().unwrap();
    assert!(found);
}

#[test]
fn service_txt_properties_case_insensitive() {
    // Register a service with properties.
    let domain = "_serv-properties._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_name = "properties_host.local.";
    let port = 5201;
    let properties = [
        ("prop_CAP_CASE", "one"),
        ("prop_cap_case", "two"),
        ("prop_Cap_Lower", "three"),
    ];

    let my_service = ServiceInfo::new(domain, &instance_name, host_name, "", port, &properties[..])
        .expect("valid service info")
        .enable_addr_auto();
    let props = my_service.get_properties();
    assert_eq!(props.len(), 2);

    // Verify `get_property()` method is case insensitive and returns
    // the first property with the same key.
    let prop_cap_case = my_service.get_property("prop_CAP_CASE").unwrap();
    assert_eq!(prop_cap_case.val_str(), "one");
    assert_eq!(prop_cap_case.val(), Some("one".as_bytes()));

    // Verify the original property name is kept.
    let prop_mixed = my_service.get_property("prop_cap_lower").unwrap();
    assert_eq!(prop_mixed.key(), "prop_Cap_Lower");
}

#[test]
fn service_txt_properties_key_ascii() {
    let domain = "_mdns-ascii._tcp.local.";
    let instance = "test_service_info_key_ascii";
    let port = 5202;

    // Verify that a key must contain ASCII only. E.g. cannot have emojis.
    let properties = [("prop_ascii", "one"), ("prop_🤗", "hugging_face")];
    let my_service = ServiceInfo::new(domain, instance, "myhost", "", port, &properties[..]);
    assert!(my_service.is_err());
    if let Err(e) = my_service {
        let msg = format!("ERROR: {}", e);
        assert!(msg.contains("not ASCII"));
    }

    // Verify that a key cannot contain '='.
    let properties = [("prop_ascii", "one"), ("prop_=", "equal sign")];
    let my_service = ServiceInfo::new(domain, instance, "myhost", "", port, &properties[..]);
    assert!(my_service.is_err());
    if let Err(e) = my_service {
        let msg = format!("ERROR: {}", e);
        assert!(msg.contains('='));
    }

    // Verify that properly formatted keys are OK.
    let properties = [("prop_ascii", "one"), ("prop_2", "two")];
    let my_service = ServiceInfo::new(domain, instance, "myhost", "", port, &properties[..]);
    assert!(my_service.is_ok());
}

#[test]
fn test_txt_properties_into_hashmap_str() {
    // Test valid UTF-8 properties
    let properties = [("key1", "val1"), ("key2", "val2")].into_txt_properties();
    let property_map = properties.into_property_map_str();
    println!("property_map: {:?}", property_map);
    assert_eq!(property_map.len(), 2);
    assert_eq!(property_map.get("key1"), Some(&"val1".to_string()));
    assert_eq!(property_map.get("key2"), Some(&"val2".to_string()));

    // Test property with no value and property with invalid UTF-8
    let invalid_vec: Vec<u8> = vec![200, 200]; // Invalid UTF-8 bytes
    let prop1 = TxtProperty::from("key1");
    let prop2 = TxtProperty::from(("key2", invalid_vec.as_slice()));
    let properties = vec![prop1, prop2].into_txt_properties();
    let property_map = properties.into_property_map_str();

    // Property with no value should map to empty string
    // Property with invalid UTF-8 should be skipped
    assert_eq!(property_map.get("key1"), Some(&"".to_string()));
    assert_eq!(property_map.len(), 1);
}

#[test]
fn test_into_txt_properties() {
    // Verify (&str, String) tuple is supported.
    let properties = [("key1", String::from("val1"))];
    let txt_props = properties.into_txt_properties();
    assert_eq!(txt_props.get_property_val_str("key1").unwrap(), "val1");
    assert_eq!(
        txt_props.get_property_val("key1").unwrap(),
        Some("val1".as_bytes())
    );

    // Verify (String, String) tuple is supported.
    let properties = [(String::from("key2"), String::from("val2"))];
    let txt_props = properties.into_txt_properties();
    assert_eq!(txt_props.get_property_val_str("key2").unwrap(), "val2");
}

#[test]
fn test_info_as_resolved_service() {
    let sub_ty_domain = "_printer._sub._test._tcp.local.";
    let service_info = ServiceInfo::new(
        sub_ty_domain,
        "my_instance",
        "my_host.local.",
        "192.168.0.1",
        5200,
        None,
    )
    .unwrap();
    let resolved_service = service_info.as_resolved_service();
    assert!(resolved_service.is_valid());
    assert_eq!(resolved_service.sub_ty_domain.unwrap(), sub_ty_domain);
    assert_eq!(resolved_service.ty_domain, "_test._tcp.local.");

    let info_missing_addr = ServiceInfo::new(
        "_test._tcp.local.",
        "my_instance",
        "my_host.local.",
        "",
        5200,
        None,
    )
    .unwrap();
    let invalid_service = info_missing_addr.as_resolved_service();
    assert!(!invalid_service.is_valid());
    assert!(invalid_service.sub_ty_domain.is_none());
}

/// Test enabling an interface using its name, for example "en0".
/// Also tests an instance name with Upper Case.
#[test]
fn service_with_named_interface_only() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // First, disable all interfaces.
    d.disable_interface(IfKind::All).unwrap();

    // Register a service with a name len > 15.
    let my_ty_domain = "_named_intf_only._udp.local.";
    let host_name = "named_intf_host.local.";
    let host_ipv4 = "";
    let port = 5202;
    let my_service = ServiceInfo::new(
        my_ty_domain,
        "UpperCaseInstance",
        host_name,
        host_ipv4,
        port,
        None,
    )
    .expect("invalid service info")
    .enable_addr_auto();

    d.register(my_service).unwrap();

    // Browse for a service and verify all addresses are IPv4.
    let browse_chan = d.browse(my_ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                let addrs = info.get_addresses();
                resolved = true;
                println!(
                    "Resolved a service of {} addr(s): {:?}",
                    info.get_fullname(),
                    addrs
                );
                break;
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(!resolved);

    // Second, find an interface.
    let if_addrs: Vec<Interface> = my_ip_interfaces()
        .into_iter()
        .filter(|iface| iface.addr.ip().is_ipv4())
        .collect();
    let if_name = if_addrs[0].name.clone();

    // Enable the named interface.
    println!("Enable interface with name {}", if_name);
    d.enable_interface(&if_name).unwrap();

    // Browse again.
    let browse_chan = d.browse(my_ty_domain).unwrap();
    let timeout = Duration::from_secs(3);
    let mut resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                let addrs = info.get_addresses();
                resolved = true;
                println!(
                    "Resolved a service of {} addr(s): {:?}",
                    info.get_fullname(),
                    addrs
                );
                break;
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(resolved);

    d.shutdown().unwrap();
}

#[test]
fn service_with_ipv4_only() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Disable IPv6, so the daemon is IPv4 only now.
    d.disable_interface(IfKind::IPv6).unwrap();

    // Register a service with a name len > 15.
    let service_ipv4_only = "_test_ipv4_only._udp.local.";
    let host_name = "my_host_ipv4_only.local.";
    let host_ipv4 = "";
    let port = 5201;
    let my_service = ServiceInfo::new(
        service_ipv4_only,
        "my_instance",
        host_name,
        host_ipv4,
        port,
        None,
    )
    .expect("invalid service info")
    .enable_addr_auto();
    let result = d.register(my_service);
    assert!(result.is_ok());

    // Browse for a service and verify all addresses are IPv4.
    let browse_chan = d.browse(service_ipv4_only).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;

    // run till the timeout and collect the resolved addresses
    // from all enabled interfaces.
    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                let addrs = info.get_addresses();
                resolved = true;
                println!(
                    "Resolved a service of {} addr(s): {:?}",
                    info.get_fullname(),
                    addrs
                );
                assert!(!info.get_addresses().is_empty());
                for addr in info.get_addresses().iter() {
                    assert!(addr.is_ipv4());
                }
                // We don't break here, as there could be more addresses coming.
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(resolved);
    d.shutdown().unwrap();
}

#[test]
fn service_ipv6_link_local_only() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");
    let service_ipv6_intf = "_test_ipv6_intf._udp.local.";
    let host_name = "my_host_ipv6_intf.local.";
    let host_ipv4 = "";
    let port = 5201;
    let mut my_service = ServiceInfo::new(
        service_ipv6_intf,
        "my_instance",
        host_name,
        host_ipv4,
        port,
        None,
    )
    .expect("invalid service info")
    .enable_addr_auto();
    my_service.set_interfaces(vec![IfKind::IPv6]);
    my_service.set_link_local_only(true);
    let result = d.register(my_service);
    assert!(result.is_ok());

    // Browse for a services. Verify all addresses are link-local IPv6.
    let browse_chan = d.browse(service_ipv6_intf).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;

    // run till the timeout and collect the resolved addresses
    // from all enabled interfaces.
    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                let addrs = info.get_addresses();
                resolved = true;
                println!(
                    "Resolved a service of {} addr(s): {:?}",
                    info.get_fullname(),
                    addrs
                );
                assert!(!info.get_addresses().is_empty());
                for addr in info.get_addresses().iter() {
                    assert!(addr.is_ipv6());
                    assert!(
                        matches!(addr.to_ip_addr(), IpAddr::V6(ipv6) if (ipv6.segments()[0] & 0xffc0) == 0xfe80)
                    );
                }
                // We don't break here, as there could be more addresses coming.
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(resolved);
    d.shutdown().unwrap();
}

#[test]
fn test_disable_interface_cache() {
    // Create a server
    let server = ServiceDaemon::new().expect("Failed to create the server");

    // Register a service with one IPv4.
    let ty_domain = "_disable-intf._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string();
    let ipv4_list: Vec<_> = my_ip_interfaces()
        .iter()
        .map(|iface| iface.ip())
        .filter(|ip| ip.is_ipv4() && !ip.is_loopback())
        .collect();

    let host_name = "disabled_intf_host.local.";
    let port = 5201;
    let my_service = ServiceInfo::new(
        ty_domain,
        &instance_name,
        host_name,
        &ipv4_list[..],
        port,
        None,
    )
    .expect("Invalid service info");
    server
        .register(my_service)
        .expect("Failed to register our service");

    // Create a client
    let client = ServiceDaemon::new().expect("Failed to create the client");

    // Give it some time to cache mDNS records.
    sleep(Duration::from_secs(1));

    // Disable the interface for the client.
    println!("Disabling interface with IP: {:?}", ipv4_list);
    client.disable_interface(ipv4_list).unwrap();

    // Browse for the service.
    let handle = client.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(1);
    let mut resolved = false;

    // run till timeout and it should not resolve.
    while let Ok(event) = handle.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service of {} addr(s): {:?}",
                info.get_fullname(),
                info.get_addresses()
            );
            resolved = true;
            break;
        }
    }

    // We cannot resolve the service because the interface is disabled.
    assert!(!resolved);

    // Clean up.
    server.shutdown().unwrap();
    client.shutdown().unwrap();
}

#[test]
fn service_with_invalid_addr_v4() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service without properties.
    let ty_domain = "_invalid-addr._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let if_addrs: Vec<Interface> = my_ip_interfaces()
        .into_iter()
        .filter(|iface| iface.addr.ip().is_ipv4())
        .collect();
    let alter_ip = ipv4_alter_net(&if_addrs);
    let host_name = "invalid_ipv4_host.local.";
    let port = 5201;
    let my_service = ServiceInfo::new(ty_domain, &instance_name, host_name, alter_ip, port, None)
        .expect("valid service info");
    d.register(my_service)
        .expect("Failed to register our service");

    // Browse for a service
    let browse_chan = d.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;
    loop {
        match browse_chan.recv_timeout(timeout) {
            Ok(event) => match event {
                ServiceEvent::ServiceResolved(info) => {
                    println!(
                        "Resolved a service of {} addr(s): {:?}",
                        info.get_fullname(),
                        info.get_addresses()
                    );
                    resolved = true;
                    break;
                }
                e => {
                    println!("Received event {:?}", e);
                }
            },
            Err(e) => {
                println!("browse error: {}", e);
                break;
            }
        }
    }

    d.shutdown().unwrap();

    // We cannot resolve the service because the published address
    // is not valid in the LAN.
    assert!(!resolved);
}

#[test]
fn service_with_invalid_addr_v6() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service without properties.
    let ty_domain = "_invalid-addr._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let if_addrs: Vec<Interface> = my_ip_interfaces()
        .into_iter()
        .filter(|iface| iface.addr.ip().is_ipv6())
        .collect();
    let alter_ip = ipv6_alter_net(&if_addrs);
    let host_name = "my_host.local.";
    let port = 5201;
    let my_service = ServiceInfo::new(ty_domain, &instance_name, host_name, alter_ip, port, None)
        .expect("valid service info");
    d.register(my_service)
        .expect("Failed to register our service");

    // Browse for a service
    let browse_chan = d.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;
    loop {
        match browse_chan.recv_timeout(timeout) {
            Ok(event) => match event {
                ServiceEvent::ServiceResolved(info) => {
                    println!(
                        "Resolved a service of {} addr(s): {:?}",
                        info.get_fullname(),
                        info.get_addresses()
                    );
                    resolved = true;
                    break;
                }
                e => {
                    println!("Received event {:?}", e);
                }
            },
            Err(e) => {
                println!("browse error: {}", e);
                break;
            }
        }
    }

    d.shutdown().unwrap();

    // We cannot resolve the service because the published address
    // is not valid in the LAN.
    assert!(!resolved);
}

#[test]
fn service_with_loopback_addr() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    d.enable_interface(IfKind::LoopbackV4)
        .expect("Failed to enable loopback interface");

    // Define a unique service type and instance name.
    let ty_domain = "_test-loopback._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string();

    // Use a loopback address (127.0.0.1) for the service.
    let loopback_ip: IpAddr = "127.0.0.1".parse().unwrap();
    let host_name = "localhost.local.";
    let port = 5201;
    let my_service = ServiceInfo::new(
        ty_domain,
        &instance_name,
        host_name,
        loopback_ip,
        port,
        None,
    )
    .expect("valid service info");
    d.register(my_service)
        .expect("Failed to register our service");

    // Browse for the service.
    let browse_chan = d.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    let mut found_loopback = false;
    loop {
        match browse_chan.recv_timeout(timeout) {
            Ok(event) => match event {
                ServiceEvent::ServiceResolved(info) => {
                    println!(
                        "Resolved service {} with addresses: {:?}",
                        info.get_fullname(),
                        info.get_addresses()
                    );
                    // Check that at least one of the addresses is a loopback address.
                    if info.get_addresses().iter().any(|ip| ip.is_loopback()) {
                        found_loopback = true;
                    }
                    break;
                }
                e => {
                    println!("Received event {:?}", e);
                }
            },
            Err(e) => {
                println!("browse error: {}", e);
                break;
            }
        }
    }

    d.shutdown().unwrap();

    // Assert that the resolved service includes a loopback address.
    assert!(
        found_loopback,
        "The service should include a loopback address"
    );
}

#[test]
fn subtype() {
    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service with a subdomain
    let subtype_domain = "_directory._sub._test-subtype._tcp.local.";
    let ty_domain = "_test-subtype._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_ipv4 = my_ip_interfaces()[0].ip().to_string();
    let host_name = "subtype_host.local.";
    let port = 5201;
    let my_service = ServiceInfo::new(
        subtype_domain,
        &instance_name,
        host_name,
        host_ipv4,
        port,
        None,
    )
    .expect("valid service info");
    let fullname = my_service.get_fullname().to_string();
    d.register(my_service)
        .expect("Failed to register our service");

    // Browse for the service via ty_domain and subtype_domain
    for domain in [ty_domain, subtype_domain].iter() {
        let browse_chan = d.browse(domain).unwrap();
        let timeout = Duration::from_secs(2);
        loop {
            match browse_chan.recv_timeout(timeout) {
                Ok(event) => match event {
                    ServiceEvent::ServiceResolved(info) => {
                        println!(
                            "Resolved a service of {} subdomain {:?}",
                            info.get_fullname(),
                            info.get_subtype()
                        );
                        assert_eq!(fullname.as_str(), info.get_fullname());
                        assert_eq!(subtype_domain, info.get_subtype().as_ref().unwrap());
                        break;
                    }
                    e => {
                        println!("Received event {:?}", e);
                    }
                },
                Err(e) => {
                    panic!("browse error: {}", e);
                }
            }
        }
    }

    d.shutdown().unwrap();
}

/// Verify service name has to be valid.
#[test]
fn test_service_name_check() {
    // Create a daemon for the server.
    let server_daemon = ServiceDaemon::new().expect("Failed to create server daemon");
    let monitor = server_daemon.monitor().unwrap();
    // Register a service with a name len > 15.
    let service_name_too_long = "_service-name-too-long._udp.local.";
    let host_ipv4 = "";
    let host_name = "my_host.local.";
    let port = 5200;
    let mut my_service = ServiceInfo::new(
        service_name_too_long,
        "my_instance",
        host_name,
        host_ipv4,
        port,
        None,
    )
    .expect("valid service info")
    .enable_addr_auto();

    my_service.set_requires_probe(false);

    let result = server_daemon.register(my_service.clone());
    assert!(result.is_ok());

    // Verify that the daemon reported error.
    let event = monitor.recv_timeout(Duration::from_millis(500)).unwrap();
    assert!(matches!(event, DaemonEvent::Error(_)));
    if let DaemonEvent::Error(e) = event {
        println!("Daemon error: {}", e)
    }

    // Verify that we can increase the service name length max.
    server_daemon.set_service_name_len_max(30).unwrap();
    let result = server_daemon.register(my_service);
    assert!(result.is_ok());

    // Verify that the service was published successfully.
    let mut published = false;
    let publish_timeout = 1200;
    while let Ok(event) = monitor.recv_timeout(Duration::from_millis(publish_timeout)) {
        match event {
            DaemonEvent::Announce(_, _) => {
                published = true;
                break;
            }
            other => {
                println!("other daemon events: {:?}", other);
            }
        }
    }
    assert!(published);

    // Check for the internal upper limit of service name length max.
    let r = server_daemon.set_service_name_len_max(31);
    assert!(r.is_err());

    server_daemon.shutdown().unwrap();
}

#[test]
fn service_new_publish_after_browser() {
    let service_type = "_new-pub._udp.local.";
    let daemon = ServiceDaemon::new().expect("Failed to create a new daemon");

    // First, starts the browser.
    let receiver = daemon.browse(service_type).unwrap();

    sleep(Duration::from_millis(1000));

    let txt_properties = [("key1", "value1")];
    let service_info = ServiceInfo::new(
        "_new-pub._udp.local.",
        "test1",
        "my_host.local.",
        "",
        1234,
        &txt_properties[..],
    )
    .expect("valid service info")
    .enable_addr_auto();

    // Second, publish a service.
    let result = daemon.register(service_info);
    assert!(result.is_ok());

    let mut resolved = false;
    let timeout = Duration::from_secs(2);
    loop {
        match receiver.recv_timeout(timeout) {
            Ok(event) => match event {
                ServiceEvent::ServiceResolved(info) => {
                    println!(
                        "Resolved a service of {} addr(s): {:?} props: {:?}",
                        info.get_fullname(),
                        info.get_addresses(),
                        info.get_properties()
                    );
                    resolved = true;
                    break;
                }
                e => {
                    println!("Received event {:?}", e);
                }
            },
            Err(e) => {
                println!("browse error: {}", e);
                break;
            }
        }
    }

    assert!(resolved);
    daemon.shutdown().unwrap();
}

fn is_apple_p2p_by_name(name: &str) -> bool {
    let p2p_prefixes = ["awdl", "llw"];
    p2p_prefixes.iter().any(|prefix| name.starts_with(prefix))
}

fn my_ip_interfaces() -> Vec<Interface> {
    if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|i| {
            // Skip operationally down interfaces, as the daemon does.
            if !i.is_oper_up() || i.is_loopback() || i.is_p2p() || is_apple_p2p_by_name(&i.name) {
                None
            } else {
                match &i.addr {
                    IfAddr::V4(ifv4) =>
                    // Use a 'bind' to check if this is a valid IPv4 addr.
                    {
                        match std::net::UdpSocket::bind((ifv4.ip, 0)) {
                            Ok(_) => Some(i),
                            Err(e) => {
                                println!("failed to bind {}: {e}, skipped.", ifv4.ip);
                                None
                            }
                        }
                    }
                    IfAddr::V6(ifv6) =>
                    // Use a 'bind' to check if this is a valid IPv6 addr.
                    {
                        let mut sock = std::net::SocketAddrV6::new(ifv6.ip, 0, 0, 0);
                        if i.is_link_local() {
                            // Only link local IPv6 address requires to specify scope_id
                            sock.set_scope_id(i.index.unwrap_or(0));
                        }

                        match std::net::UdpSocket::bind(sock) {
                            Ok(_) => Some(i),
                            Err(e) => {
                                println!("failed to bind {}: {e}, skipped.", ifv6.ip);
                                None
                            }
                        }
                    }
                }
            }
        })
        .collect()
}

/// Returns a made-up IPv4 address "net.1.1.1", where
/// `net` is one higher than any of IPv4 addresses on the host.
///
/// The idea is that this made-up address does not belong to
/// the same network as any of the host addresses.
fn ipv4_alter_net(if_addrs: &[Interface]) -> IpAddr {
    let mut net_max = 0;
    for if_addr in if_addrs.iter() {
        match &if_addr.addr {
            IfAddr::V4(iface) => {
                let net = iface.ip.octets()[0];
                if net > net_max {
                    net_max = net;
                }
            }
            _ => panic!(),
        }
    }
    Ipv4Addr::new(net_max + 1, 1, 1, 1).into()
}

/// Returns a made-up IPv6 address "net:1:1:1:1:1:1:1", where
/// `net` is one higher than any of IPv6 addresses on the host.
///
/// The idea is that this made-up address does not belong to
/// the same network as any of the host addresses.
fn ipv6_alter_net(if_addrs: &[Interface]) -> IpAddr {
    let mut net_max = 0;
    for if_addr in if_addrs.iter() {
        match &if_addr.addr {
            IfAddr::V6(iface) => {
                let net = iface.ip.octets()[0];
                if net > net_max {
                    net_max = net;
                }
            }
            _ => panic!(),
        }
    }
    Ipv6Addr::new(net_max as u16 + 1, 1, 1, 1, 1, 1, 1, 1).into()
}

#[test]
fn test_shutdown() {
    let mdns = ServiceDaemon::new().unwrap();

    // Check the status.
    let receiver = mdns.status().unwrap();
    let status = receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Running));

    // Shutdown the daemon immediately.
    let receiver = mdns.shutdown().unwrap();
    let status = receiver.recv().unwrap();
    println!("daemon status: {:?}", status);

    // Try to register and it should fail.
    let service_type = "_mdns-sd-my-test._udp.local.";
    let instance_name = "my_instance";
    let ip = "192.168.1.12";
    let host_name = "192.168.1.12.local.";
    let port = 5200;
    let properties = [("property_1", "test"), ("property_2", "1234")];

    let my_service = ServiceInfo::new(
        service_type,
        instance_name,
        host_name,
        ip,
        port,
        &properties[..],
    )
    .unwrap();

    let result = mdns.register(my_service);
    assert!(result.is_err());

    // Check the status again.
    let receiver = mdns.status().unwrap();
    let status = receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));
}

#[test]
fn test_hostname_resolution() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");
    let hostname = "my_host._tcp.local.";
    let service_ip_addr: ScopedIp = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.into())
        .unwrap();

    let my_service = ServiceInfo::new(
        "_host_res_test._tcp.local.",
        "my_instance",
        hostname,
        &[service_ip_addr.to_ip_addr()] as &[IpAddr],
        1234,
        None,
    )
    .expect("invalid service info");
    d.register(my_service).unwrap();

    let event_receiver = d.resolve_hostname(hostname, Some(2000)).unwrap();
    let resolved = loop {
        match event_receiver.recv() {
            Ok(HostnameResolutionEvent::AddressesFound(found_hostname, addresses)) => {
                assert!(found_hostname == hostname);
                assert!(addresses.contains(&service_ip_addr));
                break true;
            }
            Ok(HostnameResolutionEvent::SearchStopped(_)) => break false,
            Ok(event) => println!("Received event {:?}", event),
            Err(_) => break false,
        }
    };

    assert!(resolved);
    d.shutdown().unwrap();
}

#[test]
fn test_hostname_resolution_case_insensitive() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");
    let hostname = "My_casE_HOST.local.";
    let service_ip_addr: ScopedIp = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.into())
        .unwrap();

    let my_service = ServiceInfo::new(
        "_host_case_test._tcp.local.",
        "my_instance",
        hostname,
        &[service_ip_addr.to_ip_addr()] as &[IpAddr],
        1234,
        None,
    )
    .expect("invalid service info");
    d.register(my_service).unwrap();

    // Verify that lowercase hostname resolves correctly.
    let hostname_lower = hostname.to_lowercase();
    let event_receiver = d.resolve_hostname(&hostname_lower, Some(2000)).unwrap();
    let resolved = loop {
        match event_receiver.recv() {
            Ok(HostnameResolutionEvent::AddressesFound(found_hostname, addresses)) => {
                assert!(found_hostname == hostname);
                assert!(addresses.contains(&service_ip_addr));
                break true;
            }
            Ok(HostnameResolutionEvent::SearchStopped(_)) => break false,
            Ok(_event) => {}
            Err(_) => break false,
        }
    };

    assert!(resolved);

    // Verify that any-case hostname resolves correctly.
    let hostname_other = "MY_CASe_hOST.local.";
    let event_receiver = d.resolve_hostname(hostname_other, Some(2000)).unwrap();
    let resolved = loop {
        match event_receiver.recv() {
            Ok(HostnameResolutionEvent::AddressesFound(found_hostname, addresses)) => {
                assert!(found_hostname == hostname);
                assert!(addresses.contains(&service_ip_addr));
                break true;
            }
            Ok(HostnameResolutionEvent::SearchStopped(_)) => break false,
            Ok(_event) => {}
            Err(_) => break false,
        }
    };
    assert!(resolved);

    d.shutdown().unwrap();
}

#[test]
fn hostname_resolution_timeout() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    let hostname = "nonexistent._tcp.local.";

    let before = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .expect("failed to get current UNIX time")
        .as_millis() as u64;
    let event_receiver = d.resolve_hostname(hostname, Some(2000)).unwrap();
    let resolved = loop {
        match event_receiver.recv() {
            Ok(HostnameResolutionEvent::AddressesFound(found_hostname, _addresses)) => {
                assert!(found_hostname == hostname);
                break true;
            }
            Ok(HostnameResolutionEvent::SearchTimeout(_)) => break false,
            Ok(event) => println!("Received event {:?}", event),
            Err(_) => break false,
        }
    };
    let after = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .expect("failed to get current UNIX time")
        .as_millis() as u64;

    assert!(!resolved);

    println!("Time spent resolving: {} ms", after - before);
    assert!(after - before >= 2000 - 5);
    assert!(after - before < 2000 + 1000);

    d.shutdown().unwrap();
}

#[test]
fn test_cache_flush_record() {
    // Create a daemon
    let server = ServiceDaemon::new().expect("Failed to create server");
    let service = "_test_cache_ptr._udp.local.";
    let host_name = "my_host_tmp_cache_flush.local.";

    // use a single IPv4 addr
    let mut service_ip_addr = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    let port = 5201;
    let properties = [("key", "value")];
    let mut my_service = ServiceInfo::new(
        service,
        "my_instance",
        host_name,
        service_ip_addr,
        port,
        &properties[..],
    )
    .expect("invalid service info");
    let result = server.register(my_service.clone());
    assert!(result.is_ok());

    // Browse for a service
    let client = ServiceDaemon::new().expect("Failed to create client");
    let browse_chan = client.browse(service).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                resolved = true;
                timed_println(format!("Resolved a service of {}", info.get_fullname()));
                timed_println(format!("JLN service: {:?}", info));
                break;
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(resolved);

    // Stop browsing for a moment.
    client.stop_browse(service).unwrap();
    sleep(Duration::from_secs(2)); // Let the cache record be surely older than 1 second.

    // Modify the IPv4 address for the service.
    if let IpAddr::V4(ipv4) = service_ip_addr {
        let bytes = ipv4.octets();
        service_ip_addr = IpAddr::V4(Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3] + 1));
    } else {
        panic!();
    }

    // Re-register the service to update the IPv4 addr.
    my_service = ServiceInfo::new(
        service,
        "my_instance",
        host_name,
        service_ip_addr,
        port,
        &properties[..],
    )
    .unwrap();
    let result = server.register(my_service);
    assert!(result.is_ok());

    timed_println(format!(
        "Re-registered with updated IPv4 addr: {}",
        service_ip_addr
    ));

    // Wait for the new registration sent out and cache flushed.
    sleep(Duration::from_secs(2));

    // Browse for the updated IPv4 address.
    let browse_chan = client.browse(service).unwrap();
    resolved = false;
    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                // Verify the address flushed and updated.
                let new_addrs = info.get_addresses();
                timed_println(format!("new address resolved: {:?}", new_addrs));
                if new_addrs.len() == 1 {
                    let first_addr = new_addrs.iter().next().unwrap();
                    assert_eq!(&first_addr.to_ip_addr(), &service_ip_addr);
                    resolved = true;
                    break;
                }
            }
            e => {
                timed_println(format!("Received event {:?}", e));
            }
        }
    }

    assert!(resolved);
    server.shutdown().unwrap();
    client.shutdown().unwrap();
}

#[test]
fn test_cache_flush_remove_one_addr() {
    // Create a daemon
    let server = ServiceDaemon::new().expect("Failed to create server");
    let service = "_remove_one_addr._udp.local.";
    let host_name = "remove_one_addr_host.local.";

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    // Make 2nd IPv4 address for the service.
    let ip_addr2 = match ip_addr1 {
        IpAddr::V4(ipv4) => {
            let bytes = ipv4.octets();
            IpAddr::V4(Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3] + 1))
        }
        _ => {
            panic!()
        }
    };

    let port = 5201;
    let mut my_service = ServiceInfo::new(
        service,
        "my_instance",
        host_name,
        &[ip_addr1, ip_addr2][..],
        port,
        None,
    )
    .expect("invalid service info");
    let result = server.register(my_service.clone());
    assert!(result.is_ok());

    // Browse for a service
    let client = ServiceDaemon::new().expect("Failed to create client");
    let browse_chan = client.browse(service).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                resolved = true;
                println!("Resolved a service of {}", info.get_fullname());
                break;
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(resolved);

    // Stop browsing for a moment.
    client.stop_browse(service).unwrap();
    sleep(Duration::from_secs(2)); // Wait 1 more second for the 2nd announcement

    // Re-register the service to have only 1 addr.
    my_service = ServiceInfo::new(service, "my_instance", host_name, ip_addr1, port, None).unwrap();
    let result = server.register(my_service.clone());
    assert!(result.is_ok());

    println!("Re-registered with updated IPv4 addr");

    // Wait for the new registration sent out and cache flushed.
    sleep(Duration::from_secs(2));

    // Browse for the updated IPv4 address.
    let browse_chan = client.browse(service).unwrap();
    resolved = false;
    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                // Verify the address flushed and updated.
                let new_addrs = info.get_addresses();
                if new_addrs.len() == 1 {
                    let first_addr = new_addrs.iter().next().unwrap();
                    assert_eq!(&first_addr.to_ip_addr(), &ip_addr1);
                    resolved = true;
                    break;
                }
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(resolved);
    server.shutdown().unwrap();
    client.shutdown().unwrap();
}

/// Test to verify that the cache flush of SRV records
/// do not remove the service instance.
#[test]
fn test_cache_flush_srv() {
    // Create a daemon
    let server = ServiceDaemon::new().expect("Failed to create server");
    let service = "_test_cache_srv._udp.local.";
    let old_host_name = "old_srv_host.local.";
    let new_host_name = "new_srv_host.local.";

    // Use a single IPv4 address
    let service_ip_addr = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    let port = 5201;
    let properties = [("key", "value")];
    let mut my_service = ServiceInfo::new(
        service,
        "my_instance",
        old_host_name,
        service_ip_addr,
        port,
        &properties[..],
    )
    .expect("invalid service info");
    let result = server.register(my_service.clone());
    assert!(result.is_ok());

    // Browse for the service
    let client = ServiceDaemon::new().expect("Failed to create client");
    let browse_chan = client.browse(service).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                resolved = true;
                assert_eq!(info.get_hostname(), old_host_name);
                break;
            }
            e => {
                println!("Received event {:?}", e);
            }
        }
    }

    assert!(resolved);

    sleep(Duration::from_secs(2)); // Let the cache record be older than 1 second

    // Re-register the service with a new host
    my_service = ServiceInfo::new(
        service,
        "my_instance",
        new_host_name,
        service_ip_addr,
        port,
        &properties[..],
    )
    .unwrap();
    let result = server.register(my_service);
    assert!(result.is_ok());

    println!("Re-registered with updated SRV host: {}", new_host_name);

    // Wait for the new registration to be sent out and cache flushed
    sleep(Duration::from_secs(2));

    // Browse for the updated SRV record
    let timeout = Duration::from_secs(2);
    let mut removed = false;
    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        println!("Received event {:?}", event);

        match event {
            ServiceEvent::ServiceRemoved(ty_domain, instance_name) => {
                // Verify the SRV host was flushed and updated
                assert_eq!(ty_domain, service);
                assert!(instance_name.starts_with("my_instance"));
                removed = true;
            }
            ServiceEvent::ServiceResolved(info) => {
                assert_eq!(info.get_hostname(), new_host_name);
                resolved = true;
            }
            _e => {}
        }
    }

    assert!(!removed);
    assert!(resolved);
    server.shutdown().unwrap();
    client.shutdown().unwrap();
}

#[test]
fn test_known_answer_suppression() {
    // Create a daemon
    let mdns_server = ServiceDaemon::new().expect("Failed to create mdns server");

    // Register a service
    let ty_domain = "_known-answer._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    let host_name = "known_answer_server.local.";
    let port = 5200;

    // Publish the service
    let my_service = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    mdns_server
        .register(my_service)
        .expect("Failed to register my service");

    // Browse the service
    let client = ServiceDaemon::new().expect("Failed to create mdns client");
    let browse_chan = client.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);
    let mut resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                resolved = true;
                println!("Resolved a service of {}", info.get_fullname());
                break;
            }
            other => {
                println!("Received event {:?}", other);
            }
        }
    }
    assert!(resolved);

    // Browse again to trigger Known Answer Suppression for sure.
    let browse_chan = client.browse(ty_domain).unwrap();
    resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            resolved = true;
            println!("Resolved a service of {}", info.get_fullname());
            break;
        }
    }
    assert!(resolved);

    // Give the server daemon chances to handle the browse query again.
    sleep(Duration::from_secs(1));

    // Verify Known Answer Suppression happened.
    let metrics_receiver = mdns_server.get_metrics().unwrap();
    let metrics = metrics_receiver.recv().unwrap();
    println!("metrics: {:?}", metrics);
    assert!(metrics["known-answer-suppression"] > 0);
}

#[test]
fn test_domain_suffix_in_browse() {
    let mdns_client = ServiceDaemon::new().expect("failed to create mDNS client");
    assert!(mdns_client.browse("_service-name._tcp.local").is_err());
    assert!(mdns_client.browse("_service-name._tcp.local.").is_ok());
    mdns_client.shutdown().unwrap();
}

#[test]
fn test_name_conflict_resolution() {
    // This test registers two services using the same names, but different IP addresses.
    let ty_domain = "_conflict-test._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_name = "conflict_host.local.";
    let port = 5200;

    // Register the first service.
    let server1 = ServiceDaemon::new().expect("failed to start server1");

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    // Publish the service on server1
    let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    server1
        .register(service1)
        .expect("Failed to register service1");

    // wait for the service announced.
    sleep(Duration::from_secs(1));

    // Register the second service.
    let server2 = ServiceDaemon::new().expect("failed to start server2");

    // Modify the IPv4 address for the service.
    let IpAddr::V4(ipv4) = ip_addr1 else {
        panic!();
    };
    let bytes = ipv4.octets();
    let ip_addr2 = IpAddr::V4(Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3] + 1));

    let service2 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr2, port, None)
        .expect("failed to create ServiceInfo for service2");
    server2
        .register(service2)
        .expect("failed to register service2");

    // Verify name change event for the second service, due to the name conflict.
    let server2_monitor = server2.monitor().unwrap();
    let timeout = Duration::from_secs(2);
    let mut name_changed = false;
    while let Ok(event) = server2_monitor.recv_timeout(timeout) {
        match event {
            DaemonEvent::NameChange(change) => {
                println!("server2 daemon event: {:?}", change);
                name_changed = true;
                break;
            }
            other => println!("server2 other event: {:?}", other),
        }
    }
    assert!(name_changed);

    // Verify both services are resolved.
    let client = ServiceDaemon::new().expect("failed to create mdns client");
    let receiver = client.browse(ty_domain).unwrap();

    let timeout = Duration::from_secs(3);
    let mut service_names = HashSet::new();

    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service: {} host {} IP {:?}",
                info.get_fullname(),
                info.get_hostname(),
                info.get_addresses_v4()
            );

            service_names.insert(info.get_fullname().to_string());

            // Find and verify name conflict resolution.
            if info.get_fullname().contains("(2)") {
                assert_eq!(info.get_hostname(), "conflict_host-2.local.");
            }

            // Stop the wait if both are resolved.
            if service_names.len() == 2 {
                break;
            }
        }
    }

    // Verify that we have resolve two services instead of one.
    assert_eq!(service_names.len(), 2);
}

#[test]
fn test_name_tiebreaking() {
    // This test registers two services using the same names, but different IP addresses,
    // same as `test_name_conflict_resolution`, the only difference being that two servers
    // do the probing at the same time. Hence tiebreaking. Server2 should win.

    let ty_domain = "_tiebreaking._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_name = "tiebreaking_host.local.";
    let port = 5200;

    // Register the first service.
    let server1 = ServiceDaemon::new().expect("failed to start server1");

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    // Publish the service on server1
    let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    server1
        .register(service1)
        .expect("Failed to register service1");

    // Register the second service immediately to trigger tiebreaking.
    let server2 = ServiceDaemon::new().expect("failed to start server2");

    // Modify the IPv4 address for the service.
    let IpAddr::V4(ipv4_2) = ip_addr1 else {
        panic!();
    };
    let bytes = ipv4_2.octets();
    let ip_addr2 = IpAddr::V4(Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3] + 1));

    let service2 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr2, port, None)
        .expect("failed to create ServiceInfo for service2");
    server2
        .register(service2)
        .expect("failed to register service2");

    // Verify name change event for the first service, per tiebreaking rules.
    // Timeout is set to 3 seconds for:
    // - Initial probing (750ms)
    // - 1 second wait after LOST the tiebreaking
    // - New probing (750ms)
    // Total: 2.5s + some margin => 3s
    let server1_monitor = server1.monitor().unwrap();
    let timeout = Duration::from_secs(3);
    let mut name_changed = false;

    while let Ok(event) = server1_monitor.recv_timeout(timeout) {
        match event {
            DaemonEvent::NameChange(change) => {
                println!("server1 daemon event: {:?}", change);
                name_changed = true;
                break;
            }
            other => println!("server1 other event: {:?}", other),
        }
    }
    assert!(name_changed);

    // Verify both services are resolved.
    let client = ServiceDaemon::new().expect("failed to create mdns client");
    let receiver = client.browse(ty_domain).unwrap();

    let timeout = Duration::from_secs(3);
    let mut resolved_services = vec![];

    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service: {} host {} IP {:?}",
                info.get_fullname(),
                info.get_hostname(),
                info.get_addresses_v4()
            );

            resolved_services.push(info);
            if resolved_services.len() == 2 {
                break;
            }
        }
    }

    // Verify that we have resolve two services instead of one.
    assert_eq!(resolved_services.len(), 2);

    // Verify that server2 (its ip_addr2) won the tiebreaking for the hostname.
    for resolved_service in resolved_services {
        if resolved_service.get_hostname() == host_name {
            let service_addr = resolved_service.get_addresses().iter().next().unwrap();
            assert_eq!(&service_addr.to_ip_addr(), &ip_addr2);
            println!("server2 won the tiebreaking");
        }
    }
}

#[test]
fn test_name_conflict_3() {
    // Similar to `test_name_conflict_resolution` but with 3 servers.
    let ty_domain = "_conflict-3._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_name = "conflict3_host.local.";
    let port = 5200;

    // Register the first service.
    let server1 = ServiceDaemon::new().expect("failed to start server1");

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    // Publish the service on server1
    let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    server1
        .register(service1)
        .expect("Failed to register service1");

    // wait for the service announced.
    sleep(Duration::from_secs(1));

    // Register the second service.
    let server2 = ServiceDaemon::new().expect("failed to start server2");

    // Modify the IPv4 address for the service.
    let IpAddr::V4(ipv4) = ip_addr1 else {
        panic!();
    };
    let bytes = ipv4.octets();
    let ip_addr2 = IpAddr::V4(Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3] + 1));

    let info2 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr2, port, None)
        .expect("failed to create ServiceInfo for service2");
    server2
        .register(info2)
        .expect("failed to register service2");

    // Verify name change event for the second service, due to the name conflict.
    let server2_monitor = server2.monitor().unwrap();
    let timeout = Duration::from_secs(2);
    let mut name_changed = false;
    while let Ok(event) = server2_monitor.recv_timeout(timeout) {
        match event {
            DaemonEvent::NameChange(change) => {
                println!("server2 daemon event: {:?}", change);
                name_changed = true;
            }
            other => println!("server2 other event: {:?}", other),
        }
    }
    assert!(name_changed);

    // Register the third service
    let server3 = ServiceDaemon::new().expect("failed to start server2");

    // Modify the IPv4 address for the service.
    let ip_addr3 = IpAddr::V4(Ipv4Addr::new(bytes[0], bytes[1], bytes[2], bytes[3] + 2));

    let info3 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr3, port, None)
        .expect("failed to create ServiceInfo for service2");

    server3
        .register(info3)
        .expect("failed to register service2");

    // Wait for the instance (SRV) rename. The host (A) rename usually comes
    // first, and browsing before the instance is renamed can see a duplicate.
    let server3_monitor = server3.monitor().unwrap();
    let timeout = Duration::from_secs(3);
    let mut instance_renamed = false;
    while let Ok(event) = server3_monitor.recv_timeout(timeout) {
        match event {
            DaemonEvent::NameChange(change) => {
                println!("server3 daemon event: {:?}", change);
                if change.rr_type == RRType::SRV {
                    instance_renamed = true;
                    break;
                }
            }
            other => println!("server3 other event: {:?}", other),
        }
    }
    assert!(instance_renamed);

    // Verify all services are resolved.
    let client = ServiceDaemon::new().expect("failed to create mdns client");
    let receiver = client.browse(ty_domain).unwrap();

    let timeout = Duration::from_secs(3);
    let mut service_names = HashSet::new();

    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service: {} host {} IP {:?}",
                info.get_fullname(),
                info.get_hostname(),
                info.get_addresses_v4()
            );

            service_names.insert(info.get_fullname().to_string());
            if service_names.len() >= 3 {
                break;
            }
        }
    }

    // Verify that we have resolve two services instead of one.
    assert_eq!(service_names.len(), 3);
}

#[test]
fn test_verify_srv() {
    // start a server
    let ty_domain = "_verify-srv._udp.local.";
    let host_name = "verify_srv.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let port = 5200;

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    // Register the service.
    let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    let fullname = service1.get_fullname().to_string();

    let server1 = ServiceDaemon::new().expect("failed to start server");
    server1
        .register(service1)
        .expect("Failed to register service1");

    // wait for the service announced.
    sleep(Duration::from_secs(1));

    // start a client
    let client = ServiceDaemon::new().expect("failed to start client");
    let receiver = client.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(2);

    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!("service resolved: {:?}", info);
            break;
        }
    }

    // kill the server without unregister (i.e. not-graceful-shutdown)
    server1.shutdown().unwrap();
    sleep(Duration::from_secs(1));

    // check `ServiceRemoved`
    client.verify(fullname, Duration::from_secs(3)).unwrap();
    let timeout = Duration::from_secs(4);
    let mut service_removal = false;

    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceRemoved(service_type, fullname) = event {
            service_removal = true;
            println!("service removed: {service_type} : {fullname}");
            break;
        }
    }

    assert!(service_removal);
}

#[test]
fn test_multicast_loop_v4() {
    let ty_domain = "_loop_v4._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_name = "loop_v4_host.local.";
    let port = 5200;

    // Register the first service.
    let server = ServiceDaemon::new().expect("failed to start server");
    server.set_multicast_loop_v4(false).unwrap();

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    // Publish the service on server
    let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    server
        .register(service1)
        .expect("Failed to register service1");

    // wait for the service announced.
    sleep(Duration::from_secs(1));

    // start a client i.e. querier.
    let mut resolved = false;
    let client = ServiceDaemon::new().expect("failed to create mdns client");

    // For Windows, IP_MULTICAST_LOOP option works only on the receive path.
    client.set_multicast_loop_v4(false).unwrap();

    let receiver = client.browse(ty_domain).unwrap();

    let timeout = Duration::from_secs(2);
    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service: {} host {} IP {:?}",
                info.get_fullname(),
                info.get_hostname(),
                info.get_addresses_v4()
            );
            resolved = true;
            break;
        }
    }

    assert!(!resolved);

    // enable loopback and try again.
    server.set_multicast_loop_v4(true).unwrap();
    client.set_multicast_loop_v4(true).unwrap();
    let receiver = client.browse(ty_domain).unwrap();

    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service: {} host {} IP {:?}",
                info.get_fullname(),
                info.get_hostname(),
                info.get_addresses_v4()
            );
            resolved = true;
            break;
        }
    }

    assert!(resolved);
}

#[test]
fn test_multicast_loop_v6() {
    let ty_domain = "_loop_v6._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_name = "loop_v6_host.local.";
    let port = 5200;

    // Register the first service.
    let server = ServiceDaemon::new().expect("failed to start server");
    server.set_multicast_loop_v6(false).unwrap();

    // Get a single IPv6 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv6())
        .map(|iface| iface.ip())
        .unwrap();

    // Publish the service on server
    let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    server
        .register(service1)
        .expect("Failed to register service1");

    // wait for the service announced.
    sleep(Duration::from_secs(1));

    // start a client i.e. querier.
    let mut resolved = false;
    let client = ServiceDaemon::new().expect("failed to create mdns client");

    // For Windows, IP_MULTICAST_LOOP option works only on the receive path.
    client.set_multicast_loop_v6(false).unwrap();

    let receiver = client.browse(ty_domain).unwrap();

    let timeout = Duration::from_secs(2);
    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service: {} host {} IP {:?}",
                info.get_fullname(),
                info.get_hostname(),
                info.get_addresses()
            );
            resolved = true;
            break;
        }
    }

    assert!(!resolved);

    // enable loopback and try again.
    server.set_multicast_loop_v6(true).unwrap();
    client.set_multicast_loop_v6(true).unwrap();

    let receiver = client.browse(ty_domain).unwrap();

    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!(
                "Resolved a service: {} host {} IP {:?}",
                info.get_fullname(),
                info.get_hostname(),
                info.get_addresses()
            );
            resolved = true;
            break;
        }
    }

    assert!(resolved);
}

#[test]
fn test_set_ip_check_interval() {
    // Create a daemon
    let server = ServiceDaemon::new().expect("Failed to create server");
    let service = "_ip_check._udp.local.";
    let host_name = "test_ip_check_host.local.";

    // use a single IPv4 addr
    let service_ip_addr = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    let port = 5201;
    let my_service = ServiceInfo::new(
        service,
        "my_instance",
        host_name,
        service_ip_addr,
        port,
        None,
    )
    .expect("invalid service info");
    let result = server.register(my_service.clone());
    assert!(result.is_ok());

    // Set the IP check interval.
    server.set_ip_check_interval(3).unwrap();
    let interval = server.get_ip_check_interval().unwrap();
    assert_eq!(interval, 3);

    server.set_ip_check_interval(u32::MAX).unwrap();
    let interval = server.get_ip_check_interval().unwrap();
    assert_eq!(interval, u32::MAX);

    server.set_ip_check_interval(0).unwrap();
    let interval = server.get_ip_check_interval().unwrap();
    assert_eq!(interval, 0);

    server.shutdown().unwrap();
}

#[test]
fn test_rfc6763_escaping() {
    // Test RFC 6763 Section 4.3: dots and backslashes must be escaped
    let instance_name = "My.Path\\Service";
    let service_type = "_rfc6763._tcp.local.";

    let service = ServiceInfo::new(
        service_type,
        instance_name,
        "rfc6763.local.",
        "",
        5555,
        None,
    )
    .expect("Failed to create service");

    // Verify escaping: dots become \. and backslashes become \\
    let fullname = service.get_fullname();
    println!("Escaping test: {}", fullname);
    assert!(
        fullname.contains("My\\.Path\\\\Service"),
        "Dots and backslashes should be escaped"
    );
}

#[test]
fn test_rfc6763_utf8_support() {
    // Test RFC 6763 Section 4.1.1: UTF-8 support including emojis
    // Also verify UTF-8 works with escaping (dots and backslashes)

    let service1 = ServiceInfo::new(
        "_utf8._tcp.local.",
        "mdns.lib 🌐",
        "test.local.",
        "",
        80,
        None,
    )
    .expect("Failed to create service with emojis");
    assert!(service1.get_fullname().contains("mdns\\.lib 🌐"));

    // UTF-8 + escaping: "Café €.v1\2024"
    let service2 = ServiceInfo::new(
        "_utf8escape._tcp.local.",
        "Café €.v1\\2024",
        "test.local.",
        "",
        80,
        None,
    )
    .expect("Failed to create service with UTF-8 and escapes");

    let fullname = service2.get_fullname();
    println!("UTF-8 + escaping fullname: {}", fullname);
    assert!(
        fullname.contains("Café €\\.v1\\\\2024"),
        "UTF-8 preserved, dots and backslashes escaped"
    );
}

#[test]
fn test_rfc6763_utf8_network_integration() {
    // Test that UTF-8 with dots and backslashes works end-to-end over the network
    // This service will be registered and browsed to verify full functionality

    // Create a daemon
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service with UTF-8, dots, and backslashes
    let ty_domain = "_utf8-network._tcp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_base = now.as_micros().to_string();

    // Instance name with UTF-8 characters (emoji, accents), dots, and backslashes
    let instance_name = format!("Café.Service\\{} 🌐", instance_base);

    let host_name = "utf8_network_host.local.";
    let port = 5203;

    let my_service = ServiceInfo::new(ty_domain, &instance_name, host_name, "", port, None)
        .expect("valid service info")
        .enable_addr_auto();

    let fullname = my_service.get_fullname().to_string();
    println!("Registered service fullname: {}", fullname);

    // Verify the fullname has proper escaping
    assert!(fullname.contains("Café\\.Service\\\\"));
    assert!(fullname.contains('🌐'));

    d.register(my_service)
        .expect("Failed to register our service");

    // Browse for the service
    let browse_chan = d.browse(ty_domain).unwrap();
    let timeout = Duration::from_secs(3);
    let mut resolved = false;

    while let Ok(event) = browse_chan.recv_timeout(timeout) {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                let resolved_fullname = info.get_fullname();
                println!("Resolved service: {}", resolved_fullname);

                // Compare by checking if the resolved fullname contains our instance base
                // and UTF-8 characters (network returns decoded names without escaping)
                if resolved_fullname.contains(&instance_base)
                    && resolved_fullname.contains("Café")
                    && resolved_fullname.contains('🌐')
                    && resolved_fullname.contains(ty_domain)
                {
                    resolved = true;
                    println!("Successfully found UTF-8 service over network!");

                    // Verify the service details
                    assert_eq!(info.get_port(), port);
                    assert!(!info.get_addresses().is_empty());

                    // Verify UTF-8 characters are preserved
                    assert!(resolved_fullname.contains("Café.Service"));
                    assert!(resolved_fullname.contains('🌐'));
                    break;
                }
            }
            ServiceEvent::SearchStarted(_) => {
                println!("Search started for {}", ty_domain);
            }
            ServiceEvent::ServiceFound(_, found_fullname) => {
                println!("Service found: {}", found_fullname);
            }
            _ => {}
        }
    }

    assert!(
        resolved,
        "UTF-8 service with dots and backslashes should be resolved over the network"
    );

    d.shutdown().unwrap();
}

#[test]
fn test_interface_id_get_addrs() {
    // Get actual interfaces from the OS to build a valid InterfaceId.
    let if_addrs = if_addrs::get_if_addrs().expect("failed to get interfaces");
    let first = if_addrs.first().expect("no interfaces found");
    let intf_id = InterfaceId::from(first);

    let addrs = intf_id.get_addrs();
    assert!(
        !addrs.is_empty(),
        "interface {} should have at least one address",
        intf_id.name
    );
    assert!(
        addrs.contains(&first.ip()),
        "get_addrs() should contain the address we constructed from: {}",
        first.ip()
    );
}

/// A helper function to include a timestamp for println.
fn timed_println(msg: String) {
    let now = SystemTime::now();
    let formatted_time = humantime::format_rfc3339(now);
    println!("[{}] {}", formatted_time, msg);
}

#[test]
fn test_goodbye_uses_conflict_resolved_name() {
    // When probing renames a service due to a conflict, unregistering it must
    // send the goodbye records under the renamed (cached-by-peers) name, so
    // that browsers drop the entry immediately instead of waiting out TTLs.
    let ty_domain = "_conflict-bye._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = now.as_micros().to_string(); // Create a unique name.
    let host_name = "conflict_bye_host.local.";
    let port = 5200;

    // Register the first service.
    let server1 = ServiceDaemon::new().expect("failed to start server1");

    // Get a single IPv4 address
    let ip_addr1 = my_ip_interfaces()
        .iter()
        .find(|iface| iface.ip().is_ipv4())
        .map(|iface| iface.ip())
        .unwrap();

    let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
        .expect("valid service info");
    server1
        .register(service1)
        .expect("Failed to register service1");

    // wait for the service announced.
    sleep(Duration::from_secs(1));

    // Register the second service with the same names to force a conflict.
    let server2 = ServiceDaemon::new().expect("failed to start server2");
    let server2_monitor = server2.monitor().unwrap();

    let IpAddr::V4(ipv4) = ip_addr1 else {
        panic!();
    };
    let bytes = ipv4.octets();
    let ip_addr2 = IpAddr::V4(Ipv4Addr::new(
        bytes[0],
        bytes[1],
        bytes[2],
        bytes[3] % 254 + 1,
    ));

    let service2 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr2, port, None)
        .expect("failed to create ServiceInfo for service2");
    let service2_fullname = service2.get_fullname().to_string();
    server2
        .register(service2)
        .expect("failed to register service2");

    // Wait for the conflict to be resolved by renaming service2.
    let timeout = Duration::from_secs(2);
    let mut renamed_instance = None;
    while let Ok(event) = server2_monitor.recv_timeout(timeout) {
        match event {
            DaemonEvent::NameChange(change) => {
                println!("server2 name change: {:?}", change);
                if change.rr_type == RRType::SRV {
                    renamed_instance = Some(change.new_name);
                    break;
                }
            }
            other => println!("server2 other event: {:?}", other),
        }
    }
    let renamed_instance = renamed_instance.expect("service2 was not renamed");

    // Browse until the renamed instance is resolved.
    let client = ServiceDaemon::new().expect("failed to create mdns client");
    let receiver = client.browse(ty_domain).unwrap();

    let timeout = Duration::from_secs(3);
    let mut resolved = false;
    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceResolved(info) = event {
            println!("Resolved a service: {}", info.get_fullname());
            if info.get_fullname() == renamed_instance {
                resolved = true;
                break;
            }
        }
    }
    assert!(resolved, "the renamed instance was not resolved");

    // Unregister service2 (by its original fullname) and verify the client
    // sees the renamed instance removed via the goodbye packets, well before
    // any record TTL could expire.
    let receiver2 = server2
        .unregister(&service2_fullname)
        .expect("failed to unregister service2");
    let status = receiver2.recv_timeout(Duration::from_secs(2)).unwrap();
    println!("unregister status: {:?}", status);

    let timeout = Duration::from_secs(5);
    let mut removed = false;
    while let Ok(event) = receiver.recv_timeout(timeout) {
        if let ServiceEvent::ServiceRemoved(_ty, fullname) = event {
            println!("Removed a service: {fullname}");
            if fullname == renamed_instance {
                removed = true;
                break;
            }
        }
    }
    assert!(removed, "no goodbye seen for the renamed instance");

    server1.shutdown().unwrap();
    server2.shutdown().unwrap();
    client.shutdown().unwrap();
}
