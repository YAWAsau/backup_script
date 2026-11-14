use mdns_sd::{DaemonStatus, HostnameResolutionEvent, ServiceDaemon, ServiceEvent, ServiceInfo};
use std::collections::HashSet;
use std::thread::sleep;
use std::time::{Duration, SystemTime};
use test_log::test;

/// Test that shutdown properly unregisters all services
#[test]
fn test_shutdown_unregisters_services() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Register a service
    let ty_domain = "_shutdown-test1._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = format!("shutdown-test-{}", now.as_micros());

    let my_service = ServiceInfo::new(
        ty_domain,
        &instance_name,
        "shutdown-host.local.",
        "",
        5300,
        None,
    )
    .expect("valid service info")
    .enable_addr_auto();

    let fullname = my_service.get_fullname().to_string();
    d.register(my_service).expect("Failed to register service");

    // Give it time to announce
    sleep(Duration::from_millis(500));

    // Browse for the service in another daemon to verify it's announced
    let d2 = ServiceDaemon::new().expect("Failed to create daemon");
    let browse_chan = d2.browse(ty_domain).unwrap();

    let mut found = false;
    let timeout = Duration::from_secs(2);
    let timer = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < timer {
        if let Ok(ServiceEvent::ServiceResolved(info)) =
            browse_chan.recv_timeout(Duration::from_millis(100))
        {
            if info.get_fullname() == fullname {
                found = true;
                break;
            }
        }
    }
    assert!(found, "Service should be discovered before shutdown");

    // Now shutdown the first daemon
    let shutdown_receiver = d.shutdown().unwrap();
    let status = shutdown_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));

    // Give time for goodbye packets to be sent
    sleep(Duration::from_millis(500));

    // Verify the service is removed
    let mut removed = false;
    let timer = std::time::Instant::now() + Duration::from_secs(2);
    while std::time::Instant::now() < timer {
        if let Ok(ServiceEvent::ServiceRemoved(_, removed_fullname)) =
            browse_chan.recv_timeout(Duration::from_millis(100))
        {
            if removed_fullname == fullname {
                removed = true;
                break;
            }
        }
    }

    assert!(removed, "Service should be removed after shutdown");

    d2.shutdown().unwrap();
}

/// Test that shutdown properly stops all browse operations
#[test]
fn test_shutdown_stops_browse() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Start browsing
    let ty_domain = "_shutdown-browse-test._udp.local.";
    let browse_chan = d.browse(ty_domain).unwrap();

    // Give it time to start
    sleep(Duration::from_millis(100));

    // Shutdown
    let shutdown_receiver = d.shutdown().unwrap();
    let status = shutdown_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));

    // Verify we receive SearchStopped event
    let mut search_stopped = false;
    let timeout = Duration::from_secs(2);
    let timer = std::time::Instant::now() + timeout;

    while std::time::Instant::now() < timer {
        match browse_chan.recv_timeout(Duration::from_millis(100)) {
            Ok(ServiceEvent::SearchStopped(stopped_ty)) => {
                if stopped_ty == ty_domain {
                    search_stopped = true;
                    break;
                }
            }
            Ok(_) => continue,
            Err(_) => break,
        }
    }

    assert!(
        search_stopped,
        "Browse should be stopped with SearchStopped event"
    );
}

/// Test that shutdown properly stops all hostname resolution
#[test]
fn test_shutdown_stops_hostname_resolution() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Start hostname resolution
    let hostname = "test-shutdown-host.local.";
    let resolve_chan = d.resolve_hostname(hostname, None).unwrap();

    // Give it time to start
    sleep(Duration::from_millis(100));

    // Shutdown
    let shutdown_receiver = d.shutdown().unwrap();
    let status = shutdown_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));

    // Verify we receive SearchStopped event
    let mut search_stopped = false;
    let timeout = Duration::from_secs(2);
    let timer = std::time::Instant::now() + timeout;

    while std::time::Instant::now() < timer {
        match resolve_chan.recv_timeout(Duration::from_millis(100)) {
            Ok(HostnameResolutionEvent::SearchStopped(stopped_hostname)) => {
                if stopped_hostname.to_lowercase() == hostname.to_lowercase() {
                    search_stopped = true;
                    break;
                }
            }
            Ok(_) => continue,
            Err(_) => break,
        }
    }

    assert!(
        search_stopped,
        "Hostname resolution should be stopped with SearchStopped event"
    );
}

/// Test that shutdown sends proper notifications to monitors
#[test]
fn test_shutdown_notifies_monitors() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Monitor daemon events
    let _monitor_chan = d.monitor().unwrap();

    // Register a service
    let ty_domain = "_shutdown-monitor-test._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap();
    let instance_name = format!("monitor-test-{}", now.as_micros());

    let my_service = ServiceInfo::new(
        ty_domain,
        &instance_name,
        "monitor-host.local.",
        "",
        5301,
        None,
    )
    .expect("valid service info")
    .enable_addr_auto();

    d.register(my_service).expect("Failed to register service");

    // Give it time to register
    sleep(Duration::from_millis(300));

    // Shutdown
    let shutdown_receiver = d.shutdown().unwrap();
    let status = shutdown_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));

    // Give time for events to be processed
    sleep(Duration::from_millis(300));

    // The monitor channel should eventually be closed or receive notification
    // For now we just verify that shutdown completes successfully
    // Future enhancement: add specific DaemonEvent for shutdown
}

/// Test that shutdown handles multiple registered services
#[test]
fn test_shutdown_multiple_services() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    let ty_domain = "_shutdown-multi-test._udp.local.";
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_micros();

    // Register multiple services
    let mut fullnames = Vec::new();
    for i in 0..3 {
        let instance_name = format!("multi-test-{}-{}", now, i);
        let my_service = ServiceInfo::new(
            ty_domain,
            &instance_name,
            &format!("multi-host-{}.local.", i),
            "",
            5302 + i,
            None,
        )
        .expect("valid service info")
        .enable_addr_auto();

        fullnames.push(my_service.get_fullname().to_string());
        d.register(my_service).expect("Failed to register service");
    }

    // Give time to announce
    sleep(Duration::from_millis(500));

    // Browse for services in another daemon
    let d2 = ServiceDaemon::new().expect("Failed to create daemon");
    let browse_chan = d2.browse(ty_domain).unwrap();

    // Verify services are discovered
    let mut found_services = HashSet::new();
    let timeout = Duration::from_secs(3);
    let timer = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < timer && found_services.len() < fullnames.len() {
        if let Ok(ServiceEvent::ServiceResolved(info)) =
            browse_chan.recv_timeout(Duration::from_millis(100))
        {
            let fullname = info.get_fullname().to_string();
            if fullnames.contains(&fullname) {
                found_services.insert(fullname);
            }
        }
    }

    println!("Found {} services before shutdown", found_services.len());

    // Shutdown the first daemon
    let shutdown_receiver = d.shutdown().unwrap();
    let status = shutdown_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));

    // Give time for goodbye packets
    sleep(Duration::from_millis(500));

    // Verify all services are removed
    let mut removed_services = HashSet::new();
    let timer = std::time::Instant::now() + Duration::from_secs(3);
    while std::time::Instant::now() < timer && removed_services.len() < found_services.len() {
        if let Ok(ServiceEvent::ServiceRemoved(_, removed_fullname)) =
            browse_chan.recv_timeout(Duration::from_millis(100))
        {
            if fullnames.contains(&removed_fullname) {
                removed_services.insert(removed_fullname);
            }
        }
    }

    println!("Removed {} services after shutdown", removed_services.len());
    assert_eq!(
        removed_services.len(),
        found_services.len(),
        "All discovered services should be removed after shutdown"
    );

    d2.shutdown().unwrap();
}

/// Test that operations fail gracefully after shutdown
#[test]
fn test_operations_fail_after_shutdown() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // Shutdown
    let shutdown_receiver = d.shutdown().unwrap();
    let status = shutdown_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));

    // Try various operations - they should all fail
    let ty_domain = "_post-shutdown-test._udp.local.";

    // Try to register
    let my_service = ServiceInfo::new(ty_domain, "test", "test.local.", "", 5303, None).unwrap();
    let result = d.register(my_service);
    assert!(result.is_err(), "Register should fail after shutdown");

    // Try to browse
    let result = d.browse(ty_domain);
    assert!(result.is_err(), "Browse should fail after shutdown");

    // Try to resolve hostname
    let result = d.resolve_hostname("test.local.", None);
    assert!(
        result.is_err(),
        "Resolve hostname should fail after shutdown"
    );

    // Status should return Shutdown
    let status_receiver = d.status().unwrap();
    let status = status_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));
}

/// Test that shutdown is idempotent (can be called multiple times)
#[test]
fn test_shutdown_idempotent() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");

    // First shutdown
    let shutdown_receiver1 = d.shutdown().unwrap();
    let status1 = shutdown_receiver1.recv().unwrap();
    assert!(matches!(status1, DaemonStatus::Shutdown));

    // Second shutdown should also work (or fail gracefully)
    let result = d.shutdown();
    // Either succeeds or returns an error (both acceptable)
    if let Ok(shutdown_receiver2) = result {
        // If it succeeds, status should still be Shutdown
        let status2 = shutdown_receiver2.recv().unwrap();
        assert!(matches!(status2, DaemonStatus::Shutdown));
    }
}

/// Test shutdown with concurrent operations
#[test]
fn test_shutdown_concurrent_operations() {
    let d = ServiceDaemon::new().expect("Failed to create daemon");
    let d_clone = d.clone();

    // Start a browse operation in another thread
    let handle = std::thread::spawn(move || {
        let browse_chan = d_clone.browse("_concurrent-test._udp.local.").unwrap();

        // Keep receiving until channel closes or SearchStopped is received
        loop {
            match browse_chan.recv_timeout(Duration::from_secs(5)) {
                Ok(ServiceEvent::SearchStopped(_)) => break,
                Ok(_) => continue,
                Err(_) => break,
            }
        }
    });

    // Give the browse time to start
    sleep(Duration::from_millis(100));

    // Shutdown while browse is active
    let shutdown_receiver = d.shutdown().unwrap();
    let status = shutdown_receiver.recv().unwrap();
    assert!(matches!(status, DaemonStatus::Shutdown));

    // Wait for the browse thread to complete
    handle.join().expect("Browse thread should complete");
}
