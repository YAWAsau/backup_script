# Version 0.21.7 (2026-11-01)

This is a bugfix release.

## Bug fixes / improvements

- Fix a race where a renamed service could skip probing. (#506)
- Fix query classification when the daemon runs on a custom port. Queries from the
  daemon's own port were treated as legacy unicast queries because the check was
  hard-coded to port 5353. (#529)
- Wake the daemon with `mio::Waker` instead of a loopback UDP signal socket. Sending a
  command no longer depends on ephemeral ports or the local UDP stack, and can no
  longer report an error after the command was already queued. (#527)
- Resolve Clippy warnings, including unused variables when the `logging` feature is
  off. (#533)
- Modernize CI workflow. (#530)

## All changes

* `3beba87 2026-10-31` Modernize CI workflow (#530) (oriel haim)
* `0749b87 2026-10-29` test: skip operationally down interfaces in my_ip_interfaces() (#535) (keepsimple1)
* `a590a7a 2026-10-26` fix: resolve Clippy warnings (#533) (oriel haim)
* `5e55075 2026-10-24` fix: reset next_send when a host rename restarts an SRV probe (#506) (keepsimple1)
* `1b84730 2026-10-23` CI: move macOS tests to macos-15, run test binaries as root (#531) (keepsimple1)
* `a90c138 2026-10-23` Fix custom-port mDNS query classification (#529) (oriel haim)
* `36f92a4 2026-10-20` Wake the daemon poller with mio::Waker. (#527) (oriel haim)

# Version 0.21.6 (2026-10-18)

This is a bugfix release.

## Bug fixes

- Fix daemon deadlocks under event backpressure. Delivering events to `browse`,
  `browse_cache` and `resolve_hostname` receivers no longer blocks the daemon. If a
  receiver falls too far behind and its event channel fills (or the receiver is
  dropped), that subscription is closed and its pending queries are stopped. In this
  case the receiver gets no `SearchStopped` event: after the queued events, the channel
  is simply disconnected. Cached records are kept, so `browse_cache` still works. (#522)
- Do not record an interface address whose multicast join failed. Previously such an
  address was kept (and `IpAdd` was emitted), so the IP check never retried the join.
  Now the join is retried on the next IP check. (#523)

## All changes

* `9ca5b67 2026-10-16` fix: do not record an interface address whose multicast join failed (#523) (keepsimple1)
* `d0941f9 2026-10-16` Fix daemon deadlocks under event backpressure (#522) (oriel haim)

Thanks and welcome our new contributor @orielhaim !

# Version 0.21.5 (2026-10-04)

This is a bugfix release.

## Bug fixes

- Keep the daemon's timers on a monotonic clock. Previously, setting the system clock
  back stalled announcements, IP checks and other timers. (#516)
- Count system sleep toward cached record TTLs. After the system wakes, records whose
  TTL ran out during the sleep are removed and refreshed as usual, instead of being
  kept as if no time had passed. (#518)
- Apply `set_ip_check_interval` immediately. Setting the interval to 0 now disables
  the IP check, instead of re-running it in a busy loop. (#517)
- Interfaces sharing an IPv4 address (e.g. the bridge interfaces of VMs and containers
  on macOS) no longer retry the multicast join on every IP check. (#513)

## All changes

* `f76eedb 2026-10-04` refactor: remove the unused per-answer timestamp from DnsOutgoing (#519) (keepsimple1)
* `8222d6d 2026-10-04` fix: count system sleep toward cached record TTLs (#518) (keepsimple1)
* `6c50c9c 2026-10-03` fix: apply IP check interval changes immediately (#517) (keepsimple1)
* `cba4ab4 2026-10-03` fix: keep the daemon's timers on a monotonic clock (#516) (Jesper L. Nielsen)
* `37c8e24 2026-10-03` fix: interfaces sharing an IPv4 address no longer retry the multicast join (#513) (David Veszelovszki)
* `a44e673 2026-10-01` refactoring: extract duplicated code into new_multicast_socket (#515) (keepsimple1)

# Version 0.21.4 (2026-09-20)

This is a bugfix release with query-handling fixes and internal refactoring.

## Bug fixes / improvements

- Preserve supported questions and records when a message contains unknown question
  types, instead of dropping the whole message. (#508)
- Preserve service announcements after an excluded address changes, instead of
  demoting an already-announced service back to probing. (#507)
- Encode and send negative (NSEC) answers for absent hostname records, per
  [RFC 6762 section 6.1](https://datatracker.ietf.org/doc/html/rfc6762#section-6.1). (#509)
- Keep re-querying unresolved service instances while browsing. (#494)
- Refactor `handle_query` and `insert_ipaddr` for readability, with no behavior change. (#510, #511)

## All changes

* `0d2477b 2026-09-20` refactor: extract answer_hostname_question from handle_query (#511) (keepsimple1)
* `4d2ef74 2026-09-20` refactor: insert_ipaddr and handle_query (#510) (keepsimple1)
* `7f6a723 2026-09-19` fix: preserve supported questions when unknown types are present (#508) (Joey)
* `3ba9f03 2026-09-19` fix: preserve announcements after excluded address changes (#507) (Joey)
* `aeb8c71 2026-09-17` fix: encode and send negative answers for absent hostname records (#509) (Joey)
* `75d1941 2026-09-11` fix: keep re-querying unresolved instances while browsing (#494) (keepsimple1)

# Version 0.21.3 (2026-09-07)

This is a bugfix release that improves RFC 6762 section 6.7 compliance for legacy
unicast responses.

## Bug fixes / improvements

- Echo the querier's message id in legacy unicast responses, per
  [RFC 6762 section 6.7](https://datatracker.ietf.org/doc/html/rfc6762#section-6.7). (#498)
- Cap the resource record TTL to 10 seconds in legacy unicast responses, per
  [RFC 6762 section 6.7](https://datatracker.ietf.org/doc/html/rfc6762#section-6.7). (#504)
- Replace `assert` with `assert_eq` in tests where possible for clearer failure output. (#456)

## All changes

* `b61fee3 2026-09-07` fix: echo query id in legacy unicast responses (#498) (keepsimple1)
* `217ed5a 2026-09-07` test: replace assert with assert_eq where possible (#456) (CosminPerRam)
* `d8ab875 2026-09-07` fix: cap TTL to 10s in legacy unicast responses (#504) (keepsimple1)
* `0ec8df3 2026-09-07` fix clippy (keepsimple1)

# Version 0.21.2 (2026-09-05)

This is a bugfix release.

## Bug fixes / improvements

- Fix an out-of-bounds panic parsing a truncated HINFO record: `read_char_string` now
  checks that the length octet is present instead of indexing past the end of the packet.
  Found by fuzzing the packet parser. (#499, commit `c65dd3c`)
- Remove the raw packet dump from parse-failure messages, which is no longer needed for
  triage and can be troublesome when the packet is large. (#501, commit `30a22cf`)
- Remove the duplicated TXT decoding in `dns_parser`: it now uses the canonical
  `TxtProperty` in `service_info` instead of its own copy. (#500, commit `a6af4b5`)
- Add fuzzing support under `fuzz/` with a `parse_packet` target covering
  `DnsIncoming::new`, plus a fuzz build in CI. Publishing is unaffected: `cargo package`
  still excludes `fuzz/`. (#502, commit `3656343`)

## All changes

* `c65dd3c 2026-09-03` fix: out-of-bounds panic parsing a truncated HINFO record (#499) (keepsimple1)
* `a6af4b5 2026-09-03` refactoring: remove the duplicated TXT decoding in dns_parser (#500) (keepsimple1)
* `30a22cf 2026-09-04` fix: bound the raw packet dump in parse-failure messages (#501) (keepsimple1)
* `3656343 2026-09-04` tests: add fuzzing support with a packet parser target (#502) (keepsimple1)

# Version 0.21.1 (2026-08-30)

This is a bugfix release.

## Bug fixes / improvements

- Send goodbye (TTL=0) packets under conflict-resolved names. When probing renames a
  record due to a name conflict (RFC 6762 section 9), now the goodbye carries the updated
  names peers actually observed. (#495, commit `fe525a6`)
- Harden DNS name parsing (`read_name`) and name compression handling: skip only the
  malformed record instead of the whole packet. (#492, commit `5bf6b7c`)

## All changes

* `5bf6b7c 2026-08-30` refactoring: read_name and name compression (#492) (keepsimple1)
* `fe525a6 2026-08-26` fix: send goodbye packets under conflict-resolved names (#495) (dhavli)

Thanks and welcome our new contributor @dhavli !

# Version 0.21.0 (2026-08-10)

## Breaking changes

- The max outgoing packet size is now 1452 bytes (Ethernet MTU), down from 8972 bytes,
  per [RFC 6762 section 17](https://datatracker.ietf.org/doc/html/rfc6762#section-17).
  A record too big for one packet is still sent alone, in a packet of up to the RFC's
  9000-byte ceiling, so no record is dropped. Users that need to change the limit
  can call the new `ServiceDaemon::set_max_packet_size()`.

## New features

- Add `ServiceDaemon::set_max_packet_size()` to change the max byte size of outgoing
  packets on the interfaces matching a given `IfKind`, and export the new default as
  `MAX_PKT_DEFAULT`. (#487, commit `82711a8`)
- Re-export the receiver-side error types `RecvError`, `RecvTimeoutError` and
  `TryRecvError` from `flume`, so that a caller can name them without adding `flume`
  as a direct dependency. (#488, commit `20c0eac`)

## Bug fixes / improvements

- On the receive side, the IPv4 and IPv6 max packet sizes are now tracked separately
  (8972 and 8952 bytes) so that each stays within the RFC's 9000-byte limit including
  its own IP header. (#487, commit `82711a8`)

## All changes

* `6bf2bdb 2026-08-09` refactor: extract the code that does cache flush (#490) (keepsimple1)
* `20c0eac 2026-08-08` feat: re-export Receiver error types (#488) (#489) (keepsimple1)
* `82711a8 2026-08-07` feat: limit generated packet size per RFC 6762 section 17 (#487) (keepsimple1)

# Version 0.20.3 (2026-07-26)

This is a small bugfix release.

## Bug fixes / improvements

- Fix a panic when encoding a name that contains a label longer than 63 bytes. The packet write path now reports an error and skips the offending question or record, instead of asserting. (#484, commit `08362e3`)

## All changes

* `a574e93 2026-07-24` docs: add RFC 6762 compliance rows for v0.20.2 features (keepsimple1)
* `08362e3 2026-07-24` fix: Panic in write_utf8 (assert s.len() < 64) (#484) (keepsimple1)

# Version 0.20.2 (2026-07-16)

This is a feature and bugfix release focused on improved RFC 6762 compliance.

## New features

- Implement RFC 6762 section 6 multicast rate limiting: responses to the same record are rate-limited to no more than once per second on a given interface. (#476, commit `76f42bd`)
- Delay responses to PTR queries per RFC 6762 section 6, spreading responses over a random 10-50ms (instead of 20-120ms) window to reduce collisions. (#479, commit `a37e959`)
- Add a random jitter 10-50ms (instead of 20-120ms) before sending the initial query per RFC 6762 section 5.2. (#480, commit `7c55c75`)

## Bug fixes / improvements

- Space announcement retransmissions wider than the rate-limit window so that repeated announcements are not dropped. (#477, commit `6f39a46`)
- Avoid leaking empty cache entries for records that are not for us. (#481, commit `5cfa13a`)

## All changes

* `5cfa13a 2026-07-15` fix: avoid leaking empty cache entries for records not for us (#481) (keepsimple1)
* `7c55c75 2026-07-14` feat: add a jitter for initial query per RFC 6762 section 5.2 (#480) (keepsimple1)
* `a37e959 2026-07-12` feat: delay PTR query responses per RFC 6762 section 6 (#479) (keepsimple1)
* `6f39a46 2026-07-08` fix: space announcement retransmissions wider than the rate-limit window (#477) (keepsimple1)
* `76f42bd 2026-07-07` feat: Implement RFC 6762 section 6 multicast rate limiting (#476) (keepsimple1)

# Version 0.20.1 (2026-06-28)

This is a small feature and maintenance release.

## New features

- Add `IfKind::Predicate` and a new `IfPredicate` type, allowing interfaces to be selected with a custom predicate function (e.g. matching by interface name pattern). (#474, commit `fd72146`)

## Other changes

- chore(deps): update dependencies. (#454, commit `06bdad1`)

## All changes

* `fd72146 2026-06-22` Add `IfPredicate` for more flexible interface filtering (#474) (MAlba124)
* `06bdad1 2026-06-16` chore(deps): update (#454) (CosminPerRam)

Thanks and welcome our new contributor @MAlba124 !

# Version 0.20.0 (2026-05-24)

This release contains a small breaking change in the optional `serde` feature, hence the minor version bump.

## Breaking changes

- Remove `#[serde(untagged)]` from `ScopedIp`. The serialized form of `ScopedIp` now includes its enum variant tag (`V4` / `V6`), which improves compatibility with binary serde formats (e.g. MessagePack). Only affects users of the optional `serde` feature. (#472, commit `5fa4b92`)

## Other changes

- tests: remove explicit random port assignments.
- chore: remove an unused dev-dependency.

## All changes

* `fee8ab7 2026-05-24` remove unused dev-dependency (keepsimple1)
* `e745a2f 2026-05-23` tests: remove explicit port random assignments (#455) (CosminPerRam)
* `5fa4b92 2026-05-22` Remove untagged attribute from ScopedIp (#472) (Rascal)

# Version 0.19.2 (2026-05-17)

This is a bugfix and small-feature release.

## New features

- Support RFC 6762 legacy unicast responses: when a query arrives from a source port other than `5353`, the daemon now replies directly to the querier's address/port instead of multicasting. This enables interoperability with one-shot / legacy mDNS queriers. (#469, commit `933bdbe`)
- Added a new `Error::DaemonShutdown` variant, returned by `ServiceDaemon` methods after the daemon thread has exited (previously surfaced as a generic `Error::Msg`). The `Error` enum is `#[non_exhaustive]`, so this is additive. (commit `a457193`)

## Bug fixes / improvements

- Optimize outgoing DNS serialization to reduce allocations on the send path. (#467, commit `fb26d7f`)
- Replace a stray `println!` in `DnsHostInfo::write` with `debug!`, so the library no longer writes to stdout. (#465, commit `96008a4`)
- Expanded `# Errors` doc sections on the major `ServiceDaemon` APIs (`new`, `new_with_port`, `browse`, `stop_browse`, `resolve_hostname`, `stop_resolve_hostname`, `register`, `unregister`), documenting when `Error::Again` vs. `Error::DaemonShutdown` is returned. (#464, commit `a457193`)

## All changes

* `933bdbe 2026-05-15` Add support for RFC 6762 legacy unicast responses (#469) (Luqmaan)
* `fb26d7f 2026-04-30` Optimize dns outgoing serialization (#467) (Alexander)
* `a457193 2026-04-28` docs: add doc comments for error handling on major APIs (#464) (keepsimple1)
* `96008a4 2026-04-28` Replace println with debug log (#465) (Alexander)

Thanks and welcome our new contributors @luqs1 and @anti-social !

# Version 0.19.1 (2026-04-19)

This is a bugfix release.

## Bug fixes

- When responding to a query, pick a source IP that matches the querier's subnet, so responses are reachable on multi-homed hosts. (#460, commit `d210372`)
- Validate TXT property length in the `ServiceInfo` constructor, catching oversized properties at registration time instead of at send time. (#458, commit `cc81eec`)

## All changes

* `d210372 2026-04-18` fix: use a source IP matching the querier's subnet when responding (#460) (keepsimple1)
* `cc81eec 2026-04-12` fix: check TXT property length in ServiceInfo constructor (#458) (keepsimple1)

# Version 0.19.0 (2026-04-04)

## Breaking changes

- `ScopedIpV4` now carries `interface_ids` tracking which network interfaces discovered the address. The derived `Eq`/`Hash` now includes `interface_ids`, so two `ScopedIpV4` values with the same IP but different interface lists are no longer equal. (commits `43bd8f3`, `0661bf1`, `247447b`)

## New features

- New optional `serde` feature: adds `Serialize`/`Deserialize` on `InterfaceId`, `ScopedIpV4`, `ScopedIpV6`, `ScopedIp`, `TxtProperties`, `TxtProperty`, and `ResolvedService`. (commit `c2c2f75`)
- New public APIs: `ScopedIpV4::new()`, `ScopedIpV4::interface_ids()`, `InterfaceId::get_addrs()`.

## Bug fixes

- Avoid known-answer suppression when querying on a new interface, so address records are discovered promptly. (commit `468c5ee`)
- Track modified instances when removing records from an interface, so `ServiceResolved` events reflect updated addresses. (commit `7daa1d4`)

## All changes

* `3903f09 2026-04-04` refactoring: simplify handle_query (#452) (keepsimple1)
* `b6ddc18 2026-04-04` refactoring: move add_answer_with_additionals into struct DnsOutgoing (#451) (keepsimple1)
* `468c5ee 2026-04-03` fix: avoid known-answer suppression when querying on a new interface (#450) (keepsimple1)
* `7daa1d4 2026-04-01` fix: track modified_instances when removing records from an interface (#448) (keepsimple1)
* `247447b 2026-03-26` fix: ScopedIp considered Eq when interface_ids change (#446) (keepsimple1)
* `0661bf1 2026-03-24` refactoring: ScopedIpV4 to use multiple InterfaceIds (#444) (keepsimple1)
* `c2c2f75 2026-03-15` Serde Deserialize+Serialize implementation (#440) (Rascal)
* `43bd8f3 2026-03-13` add interface_id in ScopedIpV4 (#439) (keepsimple1)

Thanks and welcome our new contributor @Rascal !

# Verison 0.18.2 (2026-03-10)

- A bugfix: refresh of address records didn't work when hostname is not lowercase.

## All changes

* `ec1e733 2026-03-11` fix: Refresh of A and AAAA records (#441) (hrzlgnm)

# Version 0.18.1 (2026-02-28)

- A bugfix for `disable_interface` with an IPv4 address: clarified that the semantics is to disable IPv4 on the interface identified by the IPv4 address.
- Added new variants for `IfKind` enum:  `IndexIPV4(u32)` and `IndexIPV6(u32)`.

## All changes

* `7e04122 2026-02-28` fix(test): use all IPv4 interfaces in test_disable_interface_cache (#435) (keepsimple1)

# Version 0.18.0 (2026-02-15)

A few new features, documentation enhancements and breaking changes.

## Breaking changes
- Removed one default feature: `reuseport`. It is handled transparently now. (see commit `58bc8c5`)
- New feature: support `.` and `\` in instance names (see commit `3481b94`)
- New internal fix: proper cleanup on daemon shutdown (see commit `8d24304`)
- New internal fix: exclude point-to-point interfaces by default (e.g. tunnel interface) (see commit `85b6cd9`)

## All changes
* `b694333 2026-02-12` Added documentation about service name length (FelixSelter)
* `85b6cd9 2026-02-10` fix for macOS: exclude IFF_POINTTOPOINT interfaces and exclude Apple P2P interfaces by default (#425) (keepsimple1)
* `58bc8c5 2026-02-09` fix: invert reuseport feature (#430) (keepsimple1)
* `8d24304 2026-02-07` feat: add proper cleanup on daemon shutdown (#421) (Thibaut M.)
* `69418d6 2026-02-05` chore: update some comments (#429) (keepsimple1)
* `3481b94 2026-02-06` feat: implement RFC 6763 Section 4.3 escaping for instance names (#420) (Thibaut M.)
* `58c15b4 2026-01-27` fix: only add a scope in Display to unicast link local v6 addresses (#424) (hrzlgnm)
* `3f34136 2026-01-24` Return errors from send_dns_outgoing (#419) (keepsimple1)
* `0e323f6 2026-01-21` ci: update github action checkout (#422) (Thibaut M.)

Thanks and welcome new contributors: @thibaut-pascal, @FelixSelter

# Version 0.17.2 (2026-01-16)

## New features (non-breaking)

A new 'feature' literally: a default feature `reuseport` to control if SO_REUSEPORT should be used. Useful for old Linux kernels (before 3.9).

## All changes

* `466d373 2026-01-15` feat: add `reuseport` feature (#414) (Hanssen)
* `1770d01 2025-12-31` exmaples: add --verify option in the query example (#412) (keepsimple1)

Thanks and welcome our new contributor @Hanssen0 !

# Version 0.17.1 (2025-12-05)

## New features (non-breaking)

`ServiceDaemon::new_with_port(port: u16)` allows using a custom port for mainly development / testing purposes.

## All changes

* `9088f8b 2025-12-04` feat: use Self on impl return of itself for RRType (#409) (CosminPerRam)
* `91b3e66 2025-12-02` Add a custom port option (#408) (Kaido Kert)
* `3e7a582 2025-11-30` handle empty return from send_dns_outgoing (#407) (keepsimple1)

Thanks and welcome our new contributor @kaidokert !

# Version 0.17.0 (2025-11-06)

## Breaking changes

Loopback interfaces are enabled by default now. The main reason is that some user reported a failure of publishing services locally. I think this change probably only impacts very few.

## New features

A couple of new APIs are added for `ServiceInfo`: `set_interfaces` and `set_link_local_only` based on some real world use cases.

## All changes

* `6752eaf 2025-11-04` feat: service registration with granular iface/ip conditions (#398) (twizansk)
* `7293e7c 2025-11-02` Enable loopback interfaces by default (#397) (keepsimple1)
* `505bd71 2025-11-02` Fix clippy for tests and remove unnecessary tests (#403) (keepsimple1)

# Version 0.16.0 (2025-10-29)

A bugfix release. But we also bumped up rustc MSRV to 1.71.0, hence bumping our own minor version.

## All changes

* `6c01cf6 2025-10-27` Handle IPv6 disabled in kernel (#396) (keepsimple1)
* `b15c4c3 2025-10-23` log the interface name when joining multicast group (#394) (keepsimple1)
* `382521c 2025-10-15` refactoring only: make resolve_updated_instances easier to understand (#393) (keepsimple1)

# Version 0.15.1 (2025-09-06)

New feature: cache only browsing. Check out the new methods `browse_cache` and `accept_unsolicited`.

## All changes

* `3f6d6e9 2025-09-04` feat: support cache only browsing (#388) (twizansk)

Thanks and welcome our new contributor @twizansk !

# Version 0.15.0 (2025-08-31)

## Breaking changes

- `ServiceEvent::ServiceData` is merged back with `ServiceResolved` (i.e. replacing it). The end result is: we have a single `ServiceEvent::ServiceResolved(ResolvedService)` going forward.

Hence, a service is respresented by `ResolvedService` on the client side, and by `ServiceInfo` on the server side.

And `user_service_data()` is no longer needed and removed.

Sorry about the confusions but I think this helps for the long term. I think / hope the required code changes are minimal for most users.

## All changes

* `221e0be 2025-08-29` feat: impl AsIpAddrs for Box<dyn AsIpAddrs> (#387) (Jean-Gab)
* `f88fae1 2025-08-27` merge ServiceData with ServiceResolved (#386) (keepsimple1)

Thanks our new contributor @Jean-Gab, welcome!

# Version 0.14.1 (2025-8-19)

This is a bugfix release with only a doc comments change.

* `ec4fb9a 2025-08-18` doc: add a missing line in doc code example (#384) (keepsimple1)

# Version 0.14.0 (2025-8-10)

## Breaking changes

- `ServiceEvent::ServiceData` to support IPv6 with scope_id. It will deprecate `ServiceEvent::ServiceResolved`.

Users must call `ServiceDaemon.use_service_data` to use `ServiceData` instead of `ServiceResolved` event.

- `HostnameResolutionEvent::AddressesFound` uses the new `ScopedIp` instead of `IpAddr`.
- `ServiceEvent` is `non_exhaustive` now.

## Other hightlights

- Internal: define `MyUdpSocket` that uses PKTINFO. It also prepares for supporting unicast.
- Internal: define `MyIntf` to better handle multiple addresses on an interface.
- A few bugfixes.

* `123ecba 2025-08-08` rename HostIp to ScopedIp (#382) (keepsimple1)
* `0c9395f 2025-08-07` rename ServiceDetailed to ServiceData (#381) (keepsimple1)
* `52cc67c 2025-08-06` refactoring: define our own interface struct to allow multiple addresses (#380) (keepsimple1)
* `1b194de 2025-08-01` feat: Remove unneeded multicast send tracking (#377) (hrzlgnm)
* `8cb1a59 2025-07-30` refactoring only: move run into ZeroConf (#376) (keepsimple1)
* `2eddad3 2025-07-30` ServiceEvent: add non_exhaustive and fix clippy (#375) (keepsimple1)
* `0d6ba35 2025-07-28` bugfix: remove duplicated address record for IPv6 on a wrong interface (#373) (keepsimple1)
* `45b3cdd 2025-07-16` fix repetitive ServiceRemoved and Resolve again after interface up (#371) (keepsimple1)
* `eb90591 2025-07-13` Exclude interfaces that are operational down (#369) (keepsimple1)
* `1103ab2 2025-07-08` feat: new API to use ResolvedService instead of ServiceInfo for resolved service event (#362) (keepsimple1)

# Version 0.13.11 (2025-7-7)

This is a small bugfix release before we add potential breaking changes.

* `8b221d2 2025-06-22` derive `Clone` for `ServiceEvent` and `HostnameResolutionEvent` (#366) (Shadowcat650)

Welcome our new contributor @Shadowcat650 !

# Version 0.13.10 (2025-6-21)

This is a bugfix release.

* `14841ac 2025-06-21` add comments for setting TTL (#364) (keepsimple1)
* `3db5e1b 2025-06-17` bugfix: set multicast TTL to 255 (#361) (Sameer Puri)
* `22a2688 2025-05-20` doc: add a section for Conflict resolution (#359) (keepsimple1)
* `60888b7 2025-05-13` Refactoring only: extract parts of probing_handler into functions (#357) (keepsimple1)
* `db2f484 2025-05-11` bugfix: not to resolve records that expires soon (#353) (keepsimple1)

Welcome our new contributor @sameer !

# Version 0.13.9 (2025-04-22)

This is a bugfix release.

* `a734dd2 2025-05-02` bugfix: refresh TXT when needed (#354) (keepsimple1)
* `51c03c3 2025-05-01` bugfix: TXT records should use OTHER_TTL same as PTR (#355) (keepsimple1)
* `07750cb 2025-04-25` bugfix: only remove a service instance if all its SRV are gone (#350) (keepsimple1)

# Version 0.13.8 (2025-04-22)

This is a bugfix release that also prepares for adding InterfaceId in resolved service info.

* `2d49195 2025-04-22` bugfix: should keep A records for hostname queriers (#348) (keepsimple1)
* `fe08df1 2025-04-22` bump up version to 0.13.8 (#347) (keepsimple1)
* `f6c7e80 2025-04-22` feat: extend `DnsAddress` with an `InterfaceId` (#342) (hrzlgnm)
* `513372d 2025-04-20` remove address filter for multicast loopback (#346) (keepsimple1)

# Version 0.13.7 (2025-04-15)

This is a bugfix release that further reduces the memory footprint of DNS cache.

* `a6a0961 2025-04-15` optimization: remove cache entries when stop_browse (#344) (keepsimple1)

# Version 0.13.6 (2025-04-07)

This is a bugfix release that reduces / limits the memory footprint of the cached records and timers.

* `5fa1b31 2025-04-07` optimization: remove expired timers and skip DNS datagrams that are not for us (#338) (keepsimple1)
* `3e3aec9 2025-03-29` refactoring: make tiebreaking more modular (#336) (keepsimple1)

# Version 0.13.5 (2025-03-25)

This is a patch fix release as the previous release (0.13.4) was broken in service resolution.

* `e65757f 2025-03-26` bugfix: make `get_addr` method use lowercase hostname (#332) (Justus K)

Thanks @Stupremee for the fix and welcome!

# Version 0.13.4 (2025-03-24)

## Highlights

- New API for host IP check: `ServiceDaemon::set_ip_check_interval` and `ServiceDaemon::get_ip_check_interval`.
- Bugfixes.

## All changes

* `e64c0d4 2025-03-24` bugfix: hostname resolution should be case insensitive (#330) (keepsimple1)
* `5e4df27 2025-03-19` bugfix: when now equals next_ip_check (#328) (keepsimple1)
* `9538120 2025-03-12` examples: support logfile in the register example (#326) (keepsimple1)
* `8422690 2025-03-13` chore(deps): update fastrand and socket2 (#324) (CosminPerRam)
* `dd2d868 2025-03-07` feat: add boxed in DnsRecordExt to reduce Box::new usage (#323) (CosminPerRam)
* `3ea6cf1 2025-03-05` Detect IP changes: reduce the interval (#313) (keepsimple1)
* `7feabc9 2025-03-04` feat: handle DnsIncoming IPv4, 6 and String read parsing errors (#309) (CosminPerRam)

# Version 0.13.3 (2025-03-01)

## Highlights

* `TxtProperties`: Support `into_property_map_str`.
* For querier: a new struct `ResolvedService` that can be created from `ServiceInfo`.
* Support a service to publish using loopback interfaces via `enable_interface`.
* Bugfixes.

## All changes

* `3e6842f 2025-02-28` enable_interface: support loopback interface (#317) (keepsimple1)
* `7e77a5e 2025-02-26` fix: remove related addresses in the cache when disabling an interface (#316) (keepsimple1)
* `735fb22 2025-02-22` refactoring: move handle_poller_events into Zeroconf impl (#315) (keepsimple1)
* `e886787 2025-02-20` ci: add doc check and fail if there are any warnings (#310) (CosminPerRam)
* `9d92545 2025-02-18` refactoring: make e_fmt! available within the crate (#311) (keepsimple1)
* `4b671d4 2025-02-14` ResolvedService: a new plain struct for attributes of a service (#302) (keepsimple1)
* `349de66 2025-02-13` fix: include loopback addresses in filtering criteria (#306) (Minetake)
* `026a745 2025-02-09` refactoring: property length check (#305) (keepsimple1)
* `818f37c 2025-02-10` TXT record: docs to remind users of the maximum length of the attribute. (#304) (Lazy Panda)
* `fba8025 2025-02-09` TxtProperties: new method to get a HashMap of properties (#303) (keepsimple1)

# Version 0.13.2 (2025-02-02)

This is a bugfix release.

## All changes

* 4288190 check any match for address records in conflict handler (#294) (keepsimple1)
* b51f67d unit test: fix a timing issue (#292) (keepsimple1)
* 7afed98 bugfix: check data len for NSEC record (#291) (keepsimple1)

# Version 0.13.1 (2024-12-16)

This is a bugfix release. Fixed a bug where upper case service names failed to publish.

## All changes

* 71647a1 test: cover upper case in service name (#288) (keepsimple1)
* 6ff9b52 fix: service keys must be lowercase (#286) (Jesper L. Nielsen)

# Version 0.13.0 (2024-12-15)

There are no breaking changes in API. Bump the minor version due to the change of rustc version to Rust 1.70.0.

## Highlights

* Use `mio` instead of `polling` to poll sockets.
* New API `set_multicast_loop_v4` and `set_multicast_loop_v6` of `ServiceDaemon`.
* All logging are updated to be `debug` or `trace` levels only.

## All changes

* 489ef5a test: fix a flaky test (#283) (keepsimple1)
* 1ddae63 feat: new API to set multicast loop for ServiceDaemon (#281) (keepsimple1)
* fcd31f3 dependency: use mio to replace polling (#280) (keepsimple1)
* 99483b7 reduce logging levels (#277) (keepsimple1)

# Version 0.12.0 (2024-11-24)

There are no breaking changes in API. Bump the minor version due to new features and the change of rustc version.

## Highlights

* Support name probing and conflict resolution [RFC 6762](https://datatracker.ietf.org/doc/html/rfc6762#section-8)
* Support service liveness checking via `verify` API. [RFC 6762](https://datatracker.ietf.org/doc/html/rfc6762#section-10.4)
* rustc version changed to 1.65.0
* performance improvements and doc updates.

## All changes

* 7f6c5e9 perf: avoid cloning in filtering ptr (#272) (CosminPerRam)
* e185d6f refactoring: define an enum for DNS resource record types (#274) (keepsimple1)
* d117f4f refactoring: move exec_command into Zeroconf (#273) (keepsimple1)
* 39acd80 feat: replace remaining Box<dyn DnsRecordExt> with type (#271) (CosminPerRam)
* b50fe8c perf: optimize u8_slice_to_hex by replacing Vec with String (#270) (CosminPerRam)
* db545b1 doc: some spelling fixes (#269) (CosminPerRam)
* 7328f45 doc: add a table of RFC compliance details (#268) (keepsimple1)
* 1ade666 feat: verify to support Cache Flush on Failure Indication (#267) (keepsimple1)
* 8b63fd7 feat: support name probing and conflict resolution (#265) (keepsimple1)
* 429ecde dev-test: enhance test case for ipv4 only auto addr (#263) (keepsimple1)
* f902cf2 register service: apply interface selection for auto IP addr (#262) (keepsimple1)
* 0381e30 dns_cache: address record should only flush on the same network  (#261) (keepsimple1)

# Version 0.11.5 (2024-09-28)

This is a bugfix release.

## All changes

* 2829d8e tests: fix remove addr test (#258) (keepsimple1)
* 4f58e2f dns_parser: check against potential name compression loop (#257) (keepsimple1)

# Version 0.11.4 (2024-09-10)

Bugfixes. Added checks for corrupted RR data to prevent unnecessary panics. Thanks for new 
contributor @rise0chen !

Sorry that this release has a few merged small commits as I didn't know how to properly
merge in a PR that targets a fetaure branch used in another PR, instead of `main` branch.

## All changes

* e54485e add --verbose in CI test run (#254) (keepsimple1)
* f0c4c27 remove fastrand dependency from dev-test (#252) (keepsimple1)
* dff1596 Merge pull request #250 from keepsimple1/rdata-check (keepsimple1)
* 659e684 fix cargo clippy warning (keepsimple1)
* 90a2f12 Merge pull request #251 from rise0chen/rdata-check (keepsimple1)
* 6d51f55 Merge branch 'rdata-check' into rdata-check (keepsimple1)
* 1b2cf40 add a check for rr data len (keepsimple1)
* a5de799 feat: test random data (rise0chen)
* 40698a3 add test case and simplify DnsTxt::new (keepsimple1)
* fc489bd refactoring error log (keepsimple1)
* a3fad8e add a check for rr data len (keepsimple1)

# Version 0.11.3 (2024-08-23)

A release of bugfixes and refactorings.

## All changes

* 3292110 DnsTxt debug print: make its text field human-readable (#247) (keepsimple1) (2024-08-21)
* 5567c1f Send SearchStarted events with addrs as `ip (intf-name)`  (#245) (hrzlgnm) (2024-08-22)
* 9a91a53 cache flush: add the missing timer for updated expires (#244) (keepsimple1) (2024-08-19)
* c1d7efa Change intf_socks to a map of (Interface, Socket) (#242) (keepsimple1) (2024-08-18)
* 404100d refactor out a common method for DnsRecordExt (#241) (keepsimple1) (2024-08-18)
* f055c78 Refresh A and AAAA records of active `.browse` queriers (#240) (hrzlgnm) (2024-08-17)
* 0453030 Avoid redundant query, announcement and unregistration overhaul (#239) (hrzlgnm) (2024-08-16)

# Version 0.11.2 (2024-08-06)

Mostly a bugfix and refactoring release, with limited support added for:
- Known Answer Suppression (RFC 6762 section 7.1 and 7.2):
    - single packet for querier and responder,
    - multi-packet for querier.

## All changes

* 92eae74 add support for Known Answer Suppression part 2: multi-packet: querier side (#232) (keepsimple1)
* ada3486 fix test integration_success: respond count or known answer suppression count (#237) (keepsimple1)
* 8106d07 Skip link local addresses while checking for redundant announcements or query packets (#235) (hrzlgnm)
* b1a173a check data length in read_u16 (#234) (keepsimple1)
* d1c9157 Add sanity check for service type domain suffix in browse (#231) (keepsimple1)
* 736bec6 enable DEBUG logging for a failed test in CI (#229) (keepsimple1)
* fd00210 add logs in test to debug CI failure (#228) (keepsimple1)
* 5e0f1d3 add support for Known Answer Suppression part 1 (#227) (keepsimple1)
* 5ae18a6 refactoring: remove Send for DnsRecordBox (#226) (keepsimple1)
* d7d4867 fix integration_success test (#223) (keepsimple1)
* 6f34f1c move DnsCache into its own module (#221) (keepsimple1)
* bcdc2f9 add welcome to our new contributor (#220) (keepsimple1)

# Version 0.11.1 (2024-05-13)

## Highlights

- Start to honor cache flush bit.
- Improved cache refresh logic.
- Code refactorings.
- And a few bugfixes.

## All changes

* 098f2df move unit tests into integration test (#218)
* 80291ba refresh PTR records (#217)
* 5eb74b5 refactoring: extract details from exec_command into own functions (#215)
* 551ed4d Bugfix: AddressesRemoved missing actual addrs (#210)
* 3c924f4 Bugfix: cache flush properly (#211)
* ccdae2d Bugfix: logging feature cannot be disabled (#212)
* 626f9fa refresh SRV records and send out ServiceRemoved for expired SRV (#180)
* 06e2cf7 feat: merge match same arms (#209)
* bf5cea3 perf: in adding answers, use static dispatch instead of dynamic dispatch (#207)
* 19d2161 feat: extract match addr to type as a function (#205)
* 5bdcdd6 feat: remove clone derive from counter (#208)
* e7fc0e0 feat: replace box dns with declared type (#206)
* 5732665 feat: apply nursery lints (#202)
* 16cb5cd feat: honor cache flush (#201)

Welcome our new contributor: @lyager ! Thanks!

# Version 0.11.0 (2024-04-21)

## Breaking changes

* Now `ServiceDaemon::register()` requires `hostname` to end with ".local."

## New features

* Support resolving hostnames directly: `ServiceDaemon::resolve_hostname()`

## All changes

* example code: refactor the query output prints and the register hostname (#189)
* support multiple questions in send_query_vec (#194)
* CI: fix a test waiting for IPv6 addr (#195)
* Add support for resolving non-service hostnames (#192)
* zeroconf: use min heap for timers (#196)
* Fix flaky test (#198)
* enable logging for examples and add doc for logging (#199)

Welcome our new contributor: @oysteintveit-nordicsemi ! Thanks!

# Version 0.10.5 (2024-03-24)

## Notes

* Port 0 is now considered valid in ServiceInfo (#181)

## Changes

* reduce SearchStopped notification send error to warn (#178)
* refactoring: extract handle_poller_events() (#177)
* Do not consider port 0 as a missing info (#181)
* query TYPE_A and TYPE_AAAA via Command::Resolve (#185)
* bump socket2 version (#174)
* add NSEC record to debug resolve issue (#183)

Welcome our new contributors: @hrzlgnm and @irvingoujAtDevolution ! Thanks!

# Version 0.10.4 (2024-02-10)

This is a bug fix release.

## Changes

* Add sanity checks in DNS message decoding (#169)
* fine-tune MAX_MSG_ABSOLUTE (#170)

# Version 0.10.3 (2024-01-14)

This is a bug fix release.

## Changes

* netmask -> subnet (#164)

Welcome our new contributor @amfaber ! Thanks!

# Version 0.10.2 (2023-12-28)

This is a bug fix release.

## Changes

* use human-readable address in error log of send_packet (#155)
* query for unresolved instances only when needed (#157)
* Fix panic due to range out of bounds in txt record parsing (#159)
* Sanity check for empty service type name (#160)
* Added comment for updating service info by re-registering.

Welcome our new contributor @Raphiiko ! Thanks!

Happy new year 2024!

# Version 0.10.1 (2023-12-2)

This is a bug fix release.

## Changes

* update flume to 0.11 (#152)
* bugfix: signal event key is possible to overlap with socket poll ids (#153)

# Version 0.10.0 (2023-11-28)

## Breaking changes

* `ServiceDaemon::shutdown()` return type changed from `Result<()>` to `Result<Receiver<DaemonStatus>>` (#149)

## Other changes

* Related to the breaking change, a client can receive `DaemonStatus` to be sure the daemon is shutdown.
* A new enum `DaemonStatus` and a new API `ServiceDaemon::status()` are introduced.
* Updated CI in GitHub Actions: replace `actions-rs` with `dtolnay/rust-toolchain`.

# Version 0.9.3

This is a bugfix release.

* apply interface selections when IP addresses change (#142)
* Remove un-necessary panic (#144)
* Always include subtype info if exists (#146)

p.s. Happy Halloween!

# Version 0.9.2

The release includes a bugfix, thanks to @Mornix !

* fix PTR expiration from preventing later service resolution (#140)
* updated doc comments for `DnsCache::add_or_update`.

# Version 0.9.1

There are no breaking changes.

*  support interface selection (#137)

Added two new methods for `ServiceDaemon`: `enable_interface` and `disable_interface`, and some refactoring.

# Version 0.9.0

* Ssupports IPv6 (#130) (Thanks to @izissise)
* ServiceInfo: support get_addresses_v4 (#132)
* bugfix: set address type correctly (#134)

This is a breaking change, including:

- Trait `AsIpv4Addrs` changes to `AsIpAddrs` to support both IPv4 and IPv6.
- `ServiceInfo::new()` uses the new `AsIpAddrs` trait.
- `ServiceInfo::get_addresses()` returns both IPv4 and IPv6 addresses, while a new convenience method `get_addresses_v4` returns IPv4 only.

But in general, because the trait hides away details, the user code is likely keeping working without code changes.

Improvements:

* avoid redundant annoucement or query packets (#135)

# Version 0.8.1

* Remove env_logger in dev-dependencies and lower MSRV to 1.60.0. (#128)

# Version 0.8.0

No breaking changes in API. This release brings two potential user-visible changes:

* use UDP socket to signal the daemon for commands. (#125)

This change reduces CPU utilization of the daemon thread as well as its latency to
the user commands. Internally it uses local UDP sockets to signal the daemon.

* Added the link-local feature to if_addrs in Cargo.toml to enable link-local interfaces in Windows. (#126)

This change makes link-local interfaces visible to users in Windows where they didn't show up previously.

# Version 0.7.5

* Revert the changes in v0.7.4 and support link-local addrs alongside routable addrs. (#122)

# Version 0.7.4 (deprecated)

* Not to use link-local addrs if routable addrs exist (#117)

# Version 0.7.3

## Highlights

- Internal refactoring: always use DnsCache to resolve Servive Instances. When processing incoming packets,
we used to update the cache one record at a time and also build separate service info structs to resolve. Now we finish the cache updates first, and then resolve instances from the cache.

- Added env_logger for the examples code and enhanced the examples as well.

## What's Changed

* Support updating instances after they are resolved by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/104
* add optional "unregister" in example code by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/107
* Returns an error with logging for read_name invalid offset by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/109
* register example should keep running by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/110
* Refactoring DnsCache and how to resolve Service Instance by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/108
* add sanity check in reading a record data RDATA by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/111
* Enable logging for the examples by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/112
* register example: a simpler input for the service type by @keepsimple1 in https://github.com/keepsimple1/mdns-sd/pull/113


# Version 0.7.2

Highlights:

- Implemented `Display` trait for `TxtProperty`: print using
`key=value` format, where `value` is same as `.get_property_val_str()`.

- Implemented `Debug` trait for `TxtProperty`: print using
a struct format, where `value` prints as a string if it is UTF-8, or
prints as hex if it is not UTF-8.

# Version 0.7.1

Highlights:

- A bug fix: remove duplicated keys in TXT records received.

# Version 0.7.0

Breaking Changes:

- Allow non-standard max length for a service name. The check for
the length of a service name is moved to the daemon. If a service
name is too long, there will be an error log and an error event sent
to the monitors.

- `ServiceInfo.get_property_val()` returns `Option<Option<&[u8]>>`
instead of `Option<&str>`. Now a new `ServiceInfo.get_property_val_str()`
returns `Option<&str>`.

In other words, migrate to `get_property_val_str()` if you don't
want to worry about non-UTF8 values.

Highlights:

- Allow non-standard max length for a service name: A new method
`ServiceDaemon.set_service_name_len_max()` is added to support that.
Only use it when you really need to.
- Support non-UTF-8 value for TXT properties.
- Support `no value` for a TXT property, i.e. boolean keys.
- Added checks for ASCII keys in a TXT property.

# Version 0.6.1

Highlights:

- Fixs a bug: missing TXT records in received responses.

# Version 0.6.0

Breaking Changes:

- `ServiceInfo::new()` takes `IntoTxtProperties` trait instead of a
`HashMap` of properties. It is also backward-compatiable: the trait
is implemented for `HashMap` and `Option<HashMap>`.
- `ServiceInfo::get_properties()` returns `&TxtProperties` instead of
a `HashMap` of properties. It is also mostly backward-compatiable:
support `iter()`, `get()` methods.

Highlights:

- TXT properties' names are now case insensitive. And the original user input
order is kept.
- A new method `ServiceInfo::enable_addr_auto()`: automatically fill in IP
addresses for published services.
- Detect IP changes.
- A new `ServiceDaemon::monitor()` method to return a `Receiver` handle to
monitor the daemon events, such as IP changes.

# Version 0.5.10

- skip interfaces that failed to bind (#79) (re-apply fix in v0.5.6)

# Version 0.5.9

- Ignore duplicate keys (#74)
- update error msg for send_packet (#69)

# Version 0.5.8

- call check_service_name before sending the cmd to the daemon. (#60)
- Changed dependency on 'log' crate to be optional (#64)
- configure mDNS daemon thread a name (#66)
- log an error if socket read returns 0 and reset the socket (#67)

# Version 0.5.7

- Allow service names with trailing '.' (#56)
- query unresolved instances (#58)

# Verison 0.5.6

- handle join_multicast_v4 error gracefully (#53)

# Version 0.5.5

- track IPv4 interfaces with sockets to support multiple LANs (#48)

# Version 0.5.4

- Fix a bug in resolving multiple IPs for a host.
- Code reorg: separate modules out of lib.rs.
- Listening socket joins multicast on all interfaces.

# Version 0.5.3

- Support subtypes.
- Bind every valid IPv4 interface for outgoing sockets.
- Include Windows and macOS in GitHub Actions.

# Version 0.5.2

- Add support for Windows platform.

# Version 0.5.1

- Fix missing info in the license files.
- Add docs.rs badge.
- Make Error implement std::error::Error.

# Version 0.5.0

- Allow multiple formats for host_ipv4 to create ServiceInfo.
- A breaking change: change `ServiceInfo::new()` to return a `Result<>`.
- Update `nix` dependency to version 0.24.1.

# Version 0.4.3

- Fix a bug in stop-browse

# Version 0.4.2

- New feature: support meta-query `_services._dns-sd._udp` per RFC 6763.

# Version 0.4.1

- Update docs.

# Version 0.4.0

- Replace `crossbeam-channel` with `flume`.

# Version 0.3.0

- Add "get_metrics" in API.
- Fixed a bug in cache refresh.
- Fixed a bug in retransmission.

# Version 0.2.2

- Add the first example code. Thanks @lu-zero! (#5)

# Version 0.2.1

- mDNS daemon respond socket to be blocking for simpler send.

# Version 0.2.0

- Public API internally to use the unblocking try_send() to replace send().
- Add `Again` in Error type to support retry.

# Version 0.1.0

- Initial version
