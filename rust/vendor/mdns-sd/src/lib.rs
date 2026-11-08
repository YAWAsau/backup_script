//! A small and safe library for Multicast DNS-SD (Service Discovery).
//!
//! This library creates one new thread to run a mDNS daemon, and exposes
//! its API that interacts with the daemon via a
//! [`flume`](https://crates.io/crates/flume) channel. The channel supports
//! both `recv()` and `recv_async()`.
//!
//! For example, a client querying (browsing) a service behaves like this:
//!```text
//!  Client       <channel>       mDNS daemon thread
//!    |                             | starts its run-loop.
//!    |       --- Browse -->        |
//!    |                             | detects services
//!    |                             | finds service instance A
//!    |       <-- Found A --        |
//!    |           ...               | resolves service A
//!    |       <-- Resolved A --     |
//!    |           ...               |
//!```
//! All commands in the public API are sent to the daemon using the unblocking `try_send()`
//! so that the caller can use it with both sync and async code, with no dependency on any
//! particular async runtimes.
//!
//! # Usage
//!
//! The user starts with creating a daemon by calling [`ServiceDaemon::new()`].
//! Then as a mDNS querier, the user would call [`browse`](`ServiceDaemon::browse`) to
//! search for services, and/or as a mDNS responder, call [`register`](`ServiceDaemon::register`)
//! to publish (i.e. announce) its own service. And, the daemon type can be cloned and passed
//! around between threads.
//!
//! The user can also call [`resolve_hostname`](`ServiceDaemon::resolve_hostname`) to
//! resolve a hostname to IP addresses using mDNS, regardless if the host publishes a service name.
//!
//! ## Example: a client querying for a service type.
//!
//! ```rust
//! use mdns_sd::{ServiceDaemon, ServiceEvent};
//!
//! // Create a daemon
//! let mdns = ServiceDaemon::new().expect("Failed to create daemon");
//!
//! // Browse for a service type.
//! let service_type = "_mdns-sd-my-test._udp.local.";
//! let receiver = mdns.browse(service_type).expect("Failed to browse");
//!
//! // Receive the browse events in sync or async. Here is
//! // an example of using a thread. Users can call `receiver.recv_async().await`
//! // if running in async environment.
//! std::thread::spawn(move || {
//!     while let Ok(event) = receiver.recv() {
//!         match event {
//!             ServiceEvent::ServiceResolved(resolved) => {
//!                 println!("Resolved a new service: {}", resolved.fullname);
//!             }
//!             other_event => {
//!                 println!("Received other event: {:?}", &other_event);
//!             }
//!         }
//!     }
//! });
//!
//! // Gracefully shutdown the daemon.
//! std::thread::sleep(std::time::Duration::from_secs(1));
//! mdns.shutdown().unwrap();
//! ```
//!
//! ## Example: a server publishs a service and responds to queries. Use `monitor()` to
//! receive events from the daemon, especially errors.
//!
//! ```rust
//! use mdns_sd::{ServiceDaemon, ServiceInfo};
//! use std::collections::HashMap;
//!
//! // Create a daemon
//! let mdns = ServiceDaemon::new().expect("Failed to create daemon");
//!
//! // Optional: setup a monitor channel to receive events, especially errors from the daemon.
//! let receiver = mdns.monitor().expect("Failed to monitor daemon");
//! std::thread::spawn(move || {
//!     while let Ok(event) = receiver.recv() {
//!         match event {
//!             mdns_sd::DaemonEvent::Error(error) => {
//!                 eprintln!("Daemon error: {error}");
//!             }
//!             _ => {}
//!         }
//!     }
//! });
//!
//! // Create a service info.
//! // Make sure that the service name: "mdns-sd-my-test" is not longer than the max length limit (15 by default).
//! let service_type = "_mdns-sd-my-test._udp.local.";
//! let instance_name = "my_instance";
//! let ip = "192.168.1.12";
//! let host_name = "192.168.1.12.local.";
//! let port = 5200;
//! let properties = [("property_1", "test"), ("property_2", "1234")];
//!
//! let my_service = ServiceInfo::new(
//!     service_type,
//!     instance_name,
//!     host_name,
//!     ip,
//!     port,
//!     &properties[..],
//! ).unwrap();
//!
//! // Register with the daemon, which publishes the service.
//! mdns.register(my_service).expect("Failed to register our service");
//!
//! // Gracefully shutdown the daemon
//! std::thread::sleep(std::time::Duration::from_secs(1));
//! mdns.shutdown().unwrap();
//! ```
//!
//! ## Conflict resolution
//!
//! When a service responder receives another DNS record with the same name as its own record, a conflict occurs.
//! The mDNS [RFC 6762 section 9](https://datatracker.ietf.org/doc/html/rfc6762#section-9) defines a conflict resolution
//! mechanism, which is implemented in this library. When an application wishes to be notified of conflict resolutions,
//! it follows the steps below:
//!
//! 1. The application calls [`ServiceDaemon::monitor()`] to monitor all events from the daemon service responder.
//! 2. When a conflict resolution causes a name change, the library sends an event to the application: [`DaemonEvent::NameChange`],
//!    which provides [`DnsNameChange`] with details.
//!
//! # Limitations
//!
//! This implementation is based on the following RFCs:
//! - mDNS:   [RFC 6762](https://tools.ietf.org/html/rfc6762)
//! - DNS-SD: [RFC 6763](https://tools.ietf.org/html/rfc6763)
//! - DNS:    [RFC 1035](https://tools.ietf.org/html/rfc1035)
//!
//! We focus on the common use cases at first, and currently have the following limitations:
//! - Only support multicast, not unicast send/recv.
//! - Only support 32-bit or bigger platforms, not 16-bit platforms.
//!
//! # Use logging in tests and examples
//!
//! Often times it is helpful to enable logging running tests or examples to examine the details.
//! For tests and examples, we use [`env_logger`](https://docs.rs/env_logger/latest/env_logger/)
//! as the logger and use [`test-log`](https://docs.rs/test-log/latest/test_log/) to enable logging for tests.
//! For instance you can show all test logs using:
//!
//! ```shell
//! RUST_LOG=debug cargo test integration_success -- --nocapture
//! ```
//!
//! We also enabled the logging for the examples. For instance you can do:
//!
//! ```shell
//! RUST_LOG=debug cargo run --example query _printer._tcp
//! ```
//!

#![forbid(unsafe_code)]
#![allow(clippy::single_component_path_imports)]

// log for logging (optional).
#[cfg(feature = "logging")]
use log;

#[cfg(not(feature = "logging"))]
#[macro_use]
mod log {
    // `format_args!` names every argument so values used only in log messages
    // stay live when the `logging` feature is off. `if false` drops the work.
    macro_rules! trace {
        ($($tt:tt)*) => {
            if false {
                let _ = ::std::format_args!($($tt)*);
            }
        };
    }
    macro_rules! debug {
        ($($tt:tt)*) => {
            if false {
                let _ = ::std::format_args!($($tt)*);
            }
        };
    }
    macro_rules! error {
        ($($tt:tt)*) => {
            if false {
                let _ = ::std::format_args!($($tt)*);
            }
        };
    }
}

mod dns_cache;
mod dns_parser;
mod error;
mod service_daemon;
mod service_info;

#[cfg(feature = "unstable-fuzz-api")]
#[doc(hidden)]
pub mod fuzz_api;

pub use dns_parser::{InterfaceId, RRType, ScopedIp, ScopedIpV4, ScopedIpV6, MAX_PKT_DEFAULT};
pub use error::{Error, Result};
pub use service_daemon::{
    DaemonEvent, DaemonStatus, DnsNameChange, HostnameResolutionEvent, IfKind, IfPredicate,
    Metrics, ServiceDaemon, ServiceEvent, UnregisterStatus, IP_CHECK_INTERVAL_IN_SECS_DEFAULT,
    MDNS_PORT, SERVICE_NAME_LEN_MAX_DEFAULT, VERIFY_TIMEOUT_DEFAULT,
};
pub use service_info::{
    AsIpAddrs, IntoTxtProperties, ResolvedService, ServiceInfo, TxtProperties, TxtProperty,
};

/// A handler to receive messages from [ServiceDaemon]. Re-export from `flume` crate.
pub use flume::Receiver;

/// Errors returned by the receiving methods of `Receiver`. Re-export from `flume` crate.
pub use flume::{RecvError, RecvTimeoutError, TryRecvError};
