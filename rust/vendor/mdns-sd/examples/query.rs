//! A mDNS query client.
//!
//! Run with:
//!
//!     cargo run --example query <service_type_without_domain>
//!
//! Example:
//!
//!     cargo run --example query _my-service._udp
//!
//! Note: there is no '.' at the end as the program adds ".local."
//! automatically.
//!
//! Keeps listening for new events.

use mdns_sd::{ServiceDaemon, ServiceEvent};

fn main() {
    env_logger::builder().format_timestamp_millis().init();

    let mut service_type = match std::env::args().nth(1) {
        Some(arg) => arg,
        None => {
            print_usage();
            return;
        }
    };
    service_type.push_str(".local.");

    // Showcase `verify` functionality for IPv4 addresses
    let should_verify = matches!(std::env::args().nth(2), Some(arg) if arg == "--verify");

    // Create a daemon
    let mdns = ServiceDaemon::new().expect("Failed to create daemon");

    // Browse for the service type
    let receiver = mdns.browse(&service_type).expect("Failed to browse");

    let now = std::time::Instant::now();
    while let Ok(event) = receiver.recv() {
        match event {
            ServiceEvent::ServiceResolved(info) => {
                println!(
                    "At {:?}: Resolved a new service: {}\n host: {}\n port: {}",
                    now.elapsed(),
                    info.fullname,
                    info.host,
                    info.port,
                );
                let mut found_ipv4 = false;
                for addr in info.addresses.iter() {
                    println!(" Address: {addr}");
                    if addr.is_ipv4() {
                        found_ipv4 = true;
                    }
                }
                for prop in info.txt_properties.iter() {
                    println!(" Property: {}", prop);
                }

                if should_verify && found_ipv4 {
                    println!("Will verify after 3 seconds...");
                    std::thread::sleep(std::time::Duration::from_secs(3));

                    let instance_fullname = info.fullname;
                    let timeout = std::time::Duration::from_secs(2);
                    if let Err(e) = mdns.verify(instance_fullname, timeout) {
                        println!("Verify failed: {}", e);
                    } else {
                        println!("Verify started");
                    }
                }
            }
            ServiceEvent::ServiceRemoved(service_type, fullname) => {
                println!(
                    "At {:?}: ** service removed **: {service_type}: {fullname}",
                    now.elapsed(),
                );
            }
            other_event => {
                println!("At {:?}: {:?}", now.elapsed(), other_event);
            }
        }
    }
}

fn print_usage() {
    println!("Usage: cargo run --example query <service_type_without_domain_postfix> [--verify]");
    println!("Example: ");
    println!("cargo run --example query _my-service._udp");
    println!();
    println!("Options:");
    println!("--verify: make the client attempt to verify IPv4 addresses of resolved services.");
    println!();
    println!("You can also do a meta-query per RFC 6763 to find which services are available:");
    println!("cargo run --example query _services._dns-sd._udp");
}
