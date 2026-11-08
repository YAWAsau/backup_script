# mdns-sd

[![Build](https://github.com/keepsimple1/mdns-sd/actions/workflows/build.yml/badge.svg)](https://github.com/keepsimple1/mdns-sd/actions)
[![Cargo](https://img.shields.io/crates/v/mdns-sd.svg)](https://crates.io/crates/mdns-sd)
[![docs.rs](https://img.shields.io/docsrs/mdns-sd)](https://docs.rs/mdns-sd/latest/mdns_sd/)
[![Rust version: 1.71+](https://img.shields.io/badge/rust%20version-1.71+-orange)](https://blog.rust-lang.org/2023/07/13/Rust-1.71.0/)

This is a small implementation of mDNS (Multicast DNS) based service discovery in safe Rust, with a small set of dependencies. Some highlights:

- supports both the client (querier) and the server (responder) uses.
- supports macOS, Linux and Windows.
- supports IPv4 and IPv6.
- works with both sync and async code.
- no dependency on any async runtimes.

## Approach

We are not using async/.await internally, instead we create a new thread to run a mDNS daemon.

The API interacts with the daemon via [`flume`](https://crates.io/crates/flume) channels that work easily with both sync and async code. For more details, please see the [documentation](https://docs.rs/mdns-sd).

## Compatibility and Limitations

This implementation is based on the following RFCs:
- mDNS:   [RFC 6762](https://tools.ietf.org/html/rfc6762)
- DNS-SD: [RFC 6763](https://tools.ietf.org/html/rfc6763)
- DNS:    [RFC 1035](https://tools.ietf.org/html/rfc1035)

This is still beta software. We focus on the common use cases at hand. And we tested with some existing common tools (e.g. `Avahi` on Linux, `dns-sd` on MacOS, and `Bonjour` library on iOS) to verify the basic compatibility.

The following table shows how much this implementation is compliant with RFCs regarding major features:

| Feature | RFC section | Compliance | Notes |
| ------- | ----------- | ---------- | ----- |
| One-Shot Multicast DNS Queries (i.e. Legacy Unicast Responses) | RFC 6762 [section 5.1][ref1] [section 6.7][ref9] | ✅ | Reply unicast to the querier when the source port is not 5353, regardless of whether the query was multicast or unicast |
| Randomized Initial Query Delay | RFC 6762 [section 5.2][ref12] | ✅ | jitter the first query of a continuous-monitoring series by a random delay to avoid synchronization across queriers. ℹ️ we use a shorter 10-50 ms window instead of the RFC's 20-120 ms |
| Unicast Responses | RFC 6762 [section 5.4][ref2] | ❌ |
| Multicast Rate Limiting | RFC 6762 [section 6][ref13] | ✅ | a given record is not re-multicast on an interface until at least one second has elapsed. ℹ️ probe queries and legacy unicast responses (§6.7) are exempt per the RFC; the separate 250 ms probe-query interval is not yet implemented |
| Response Delay for Shared Records | RFC 6762 [section 6][ref13] | ✅ | delay responses to shared (e.g. PTR) queries by a random amount to allow aggregation and reduce collisions. ℹ️ we use a shorter window than the RFC's 20-120 ms |
| Known-Answer Suppression | RFC 6762 [section 7.1][ref3] | ✅ |
| Multipacket Known Answer Suppression querier | RFC 6762 [section 7.2][ref4] | ✅ |
| Multipacket Known Answer Suppression responder | RFC 6762 [section 7.2][ref4] | ❌ | because we don't support Unicast yet. |
| Probing | RFC 6762 [section 8.1][ref5] | ✅ |
| Simultaneous Probe Tiebreaking | RFC 6762 [section 8.2][ref6] | ✅ |
| Conflict Resolution | RFC 6762 [section 9][ref7] | ✅ | see `DnsNameChange` type |
| Goodbye Packets | RFC 6762 [section 10.1][ref10] | ✅ |
| Announcements to Flush Outdated Cache Entries | RFC 6762 [section 10.2][ref11] | ✅ | i.e. `cache-flush` bit |
| Cache Flush on Failure Indication | RFC 6762 [section 10.4][ref8] | ✅ | API: `ServiceDaemon::verify()` |
| Outgoing packet size | RFC 6762 [section 17][ref14] | ✅ | By default, outgoing packet max size is 1452 bytes, i.e. the Ethernet MTU. API: `ServiceDaemon::set_max_packet_size()` |

[ref1]: https://datatracker.ietf.org/doc/html/rfc6762#section-5.1
[ref2]: https://datatracker.ietf.org/doc/html/rfc6762#section-5.4
[ref3]: https://datatracker.ietf.org/doc/html/rfc6762#section-7.1
[ref4]: https://datatracker.ietf.org/doc/html/rfc6762#section-7.2
[ref5]: https://datatracker.ietf.org/doc/html/rfc6762#section-8.1
[ref6]: https://datatracker.ietf.org/doc/html/rfc6762#section-8.2
[ref7]: https://datatracker.ietf.org/doc/html/rfc6762#section-9
[ref8]: https://datatracker.ietf.org/doc/html/rfc6762#section-10.4
[ref9]: https://datatracker.ietf.org/doc/html/rfc6762#section-6.7
[ref10]: https://datatracker.ietf.org/doc/html/rfc6762#section-10.1
[ref11]: https://datatracker.ietf.org/doc/html/rfc6762#section-10.2
[ref12]: https://datatracker.ietf.org/doc/html/rfc6762#section-5.2
[ref13]: https://datatracker.ietf.org/doc/html/rfc6762#section-6
[ref14]: https://datatracker.ietf.org/doc/html/rfc6762#section-17

## License

Licensed under either of

 * Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
 * MIT license ([LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT)

at your option.

## Contribution

Contributions are welcome! Please open an issue in GitHub if any questions.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in the work by you, as defined in the above license(s), shall be
dual licensed as above, without any additional terms or conditions.
