//! Registers a mDNS service.
//!
//! Run with:
//!
//! cargo run --example register <service_type> <instance_name> <hostname> [options]
//!
//! Example:
//!
//! cargo run --example register _my-hello._udp instance1 host1
//!
//! Options:
//! "--unregister": automatically unregister after 2 seconds.
//! "--disable-ipv6": not to use IPv6 interfaces.
//! "--logfile": write debug log to a file instead of stderr.
//!
//! For example: to see the debug log, set the RUST_LOG environment variable and write a logfile:
//!
//! RUST_LOG=mdns_sd=debug cargo run --example register _my-hello._udp instance1 host1 --logfile

use mdns_sd::{DaemonEvent, IfKind, ServiceDaemon, ServiceInfo};
use std::{env, fs::File, thread, time::Duration, time::SystemTime, time::UNIX_EPOCH};

fn main() {
    // Simple command line options.
    let args: Vec<String> = env::args().collect();
    let mut should_unreg = false;
    let mut disable_ipv6 = false;
    let mut use_logfile = false;
    let mut include_apple_p2p = false;

    for arg in args.iter() {
        if arg.as_str() == "--unregister" {
            should_unreg = true;
        } else if arg.as_str() == "--disable-ipv6" {
            disable_ipv6 = true;
        } else if arg.as_str() == "--logfile" {
            use_logfile = true;
        } else if arg.as_str() == "--include-apple-p2p" {
            include_apple_p2p = true;
        }
    }

    // setup env_logger
    let mut builder = env_logger::Builder::from_default_env();
    if use_logfile {
        let now = SystemTime::now();
        let duration = now
            .duration_since(UNIX_EPOCH)
            .expect("Time went backwards: failed to get UNIX timestamp");
        let log_filename = format!("mdns-register-{}.log", duration.as_secs());
        let file = File::create(&log_filename).unwrap();
        builder.target(env_logger::Target::Pipe(Box::new(file)));
        println!("Logging to file: {}\n", log_filename);
    }

    // more precise timestamp.
    builder.format_timestamp_millis().init();

    // Create a new mDNS daemon.
    let mdns = ServiceDaemon::new().expect("Could not create service daemon");

    if disable_ipv6 {
        mdns.disable_interface(IfKind::IPv6).unwrap();
    }

    if include_apple_p2p {
        mdns.include_apple_p2p(true).unwrap();
    }

    let service_type = match args.get(1) {
        Some(arg) => format!("{}.local.", arg),
        None => {
            print_usage();
            return;
        }
    };
    let instance_name = match args.get(2) {
        Some(arg) => arg,
        None => {
            print_usage();
            return;
        }
    };
    let hostname = match args.get(3) {
        Some(arg) => arg,
        None => {
            print_usage();
            return;
        }
    };

    // With `enable_addr_auto()`, we can give empty addrs and let the lib find them.
    // If the caller knows specific addrs to use, then assign the addrs here.
    let my_addrs = "";
    let service_hostname = format!("{}.local.", hostname);
    let port = 3456;

    // The key string in TXT properties is case insensitive. Only the first
    // (key, val) pair will take effect.
    let properties = [("PATH", "one"), ("Path", "two"), ("PaTh", "three")];

    // Register a service.
    let service_info = ServiceInfo::new(
        &service_type,
        instance_name,
        &service_hostname,
        my_addrs,
        port,
        &properties[..],
    )
    .expect("valid service info")
    .enable_addr_auto();

    // Optionally, we can monitor the daemon events.
    let monitor = mdns.monitor().expect("Failed to monitor the daemon");
    let service_fullname = service_info.get_fullname().to_string();
    mdns.register(service_info)
        .expect("Failed to register mDNS service");

    println!("Registered service {}.{}", instance_name, service_type);

    if should_unreg {
        let wait_in_secs = 2;
        println!("Sleeping {} seconds before unregister", wait_in_secs);
        thread::sleep(Duration::from_secs(wait_in_secs));

        let receiver = mdns.unregister(&service_fullname).unwrap();
        while let Ok(event) = receiver.recv() {
            println!("unregister result: {:?}", event);
        }
    } else {
        // Monitor the daemon events.
        while let Ok(event) = monitor.recv() {
            println!("Daemon event: {:?}", event);
            if let DaemonEvent::Error(e) = event {
                println!("Failed: {}", e);
                break;
            }
        }
    }
}

fn print_usage() {
    println!("Usage:");
    println!("cargo run --example register <service_type> <instance_name> <hostname> [options]");
    println!("\nOptions:\n");
    println!("--unregister: automatically unregister after 2 seconds");
    println!("--disable-ipv6: not to use IPv6 interfaces.");
    println!("--logfile: write debug log to a file instead of stderr. The logfile is named 'mdns-register-<timestamp>.log'.");
    println!("--include-apple-p2p: include Apple p2p interfaces (e.g., awdl, llw) for mDNS.");
    println!();
    println!("For example:");
    println!("cargo run --example register _my-hello._udp instance1 host1");
    println!();
    println!("To see the debug log, set the RUST_LOG environment variable and write a logfile:");
    println!("RUST_LOG=mdns_sd=debug cargo run --example register _my-hello._udp instance1 host1 --logfile");
}
