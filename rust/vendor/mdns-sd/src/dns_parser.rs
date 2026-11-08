//! DNS parsing utility.
//!
//! [DnsIncoming] is the logic representation of an incoming DNS packet.
//! [DnsOutgoing] is the logic representation of an outgoing DNS message of one or more packets.
//! [DnsOutPacket] is the encoded one packet for [DnsOutgoing].

#[cfg(feature = "logging")]
use crate::log::{debug, trace};

use crate::error::{e_fmt, Error, Result};
use crate::service_info::{decode_txt, is_unicast_link_local, DnsRegistry, MyIntf, ServiceInfo};

use if_addrs::Interface;

#[cfg(feature = "serde")]
use serde::{Deserialize, Serialize};

use std::{
    any::Any,
    cmp,
    collections::HashMap,
    convert::TryInto,
    fmt,
    hash::Hash,
    net::{IpAddr, Ipv4Addr, Ipv6Addr},
    str,
    time::{Duration, Instant},
};

/// Represents a network interface identifier defined by the OS.
#[derive(Clone, Debug, Eq, Hash, PartialEq, Default)]
#[cfg_attr(feature = "serde", derive(Deserialize, Serialize))]
pub struct InterfaceId {
    /// Interface name, e.g. "en0", "wlan0", etc.
    pub name: String,

    /// Interface index assigned by the OS, e.g. 1, 2, etc.
    pub index: u32,
}

impl InterfaceId {
    /// Returns all IP addresses associated with this interface by querying the OS.
    pub fn get_addrs(&self) -> Vec<IpAddr> {
        if_addrs::get_if_addrs()
            .unwrap_or_default()
            .into_iter()
            .filter(|iface| iface.index == Some(self.index))
            .map(|iface| iface.ip())
            .collect()
    }
}

impl fmt::Display for InterfaceId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}('{}')", self.index, self.name)
    }
}

impl From<&Interface> for InterfaceId {
    fn from(interface: &Interface) -> Self {
        InterfaceId {
            name: interface.name.clone(),
            index: interface.index.unwrap_or_default(),
        }
    }
}

/// An IPv4 address with interface identifiers indicating which interfaces discovered it.
#[derive(Debug, Clone, Eq, PartialEq, Hash)]
#[cfg_attr(feature = "serde", derive(Deserialize, Serialize))]
pub struct ScopedIpV4 {
    addr: Ipv4Addr,
    /// The interfaces this address was discovered on.
    interface_ids: Vec<InterfaceId>,
}

impl ScopedIpV4 {
    /// Creates a new `ScopedIpV4` with a single interface identifier.
    pub fn new(addr: Ipv4Addr, interface_id: InterfaceId) -> Self {
        Self {
            addr,
            interface_ids: vec![interface_id],
        }
    }

    /// Returns the IPv4 address.
    pub const fn addr(&self) -> &Ipv4Addr {
        &self.addr
    }

    /// Returns the interfaces this address was discovered on.
    pub fn interface_ids(&self) -> &[InterfaceId] {
        &self.interface_ids
    }

    /// Adds an interface identifier if not already present.
    pub(crate) fn add_interface_id(&mut self, id: InterfaceId) {
        if !self.interface_ids.contains(&id) {
            self.interface_ids.push(id);
        }
    }
}

/// An IPv6 address with scope_id (interface identifier).
#[derive(Debug, Clone, Eq, PartialEq, Hash)]
#[cfg_attr(feature = "serde", derive(Deserialize, Serialize))]
pub struct ScopedIpV6 {
    addr: Ipv6Addr,
    scope_id: InterfaceId,
}

impl ScopedIpV6 {
    /// Returns the IPv6 address.
    pub const fn addr(&self) -> &Ipv6Addr {
        &self.addr
    }

    /// Returns the scope_id for this IPv6 address.
    pub const fn scope_id(&self) -> &InterfaceId {
        &self.scope_id
    }
}

/// An IP address, either IPv4 or IPv6, that supports scope_id for IPv6.
#[derive(Debug, Clone, Eq, PartialEq, Hash)]
#[cfg_attr(feature = "serde", derive(Deserialize, Serialize))]
#[non_exhaustive]
pub enum ScopedIp {
    V4(ScopedIpV4),
    V6(ScopedIpV6),
}

impl ScopedIp {
    pub const fn to_ip_addr(&self) -> IpAddr {
        match self {
            ScopedIp::V4(v4) => IpAddr::V4(v4.addr),
            ScopedIp::V6(v6) => IpAddr::V6(v6.addr),
        }
    }

    pub const fn is_ipv4(&self) -> bool {
        matches!(self, ScopedIp::V4(_))
    }

    pub const fn is_ipv6(&self) -> bool {
        matches!(self, ScopedIp::V6(_))
    }

    pub const fn is_loopback(&self) -> bool {
        match self {
            ScopedIp::V4(v4) => v4.addr.is_loopback(),
            ScopedIp::V6(v6) => v6.addr.is_loopback(),
        }
    }
}

impl From<IpAddr> for ScopedIp {
    fn from(ip: IpAddr) -> Self {
        match ip {
            IpAddr::V4(v4) => ScopedIp::V4(ScopedIpV4 {
                addr: v4,
                interface_ids: vec![],
            }),
            IpAddr::V6(v6) => ScopedIp::V6(ScopedIpV6 {
                addr: v6,
                scope_id: InterfaceId::default(),
            }),
        }
    }
}

impl From<&Interface> for ScopedIp {
    fn from(interface: &Interface) -> Self {
        match interface.ip() {
            IpAddr::V4(v4) => ScopedIp::V4(ScopedIpV4 {
                addr: v4,
                interface_ids: vec![InterfaceId::from(interface)],
            }),
            IpAddr::V6(v6) => ScopedIp::V6(ScopedIpV6 {
                addr: v6,
                scope_id: InterfaceId::from(interface),
            }),
        }
    }
}

impl fmt::Display for ScopedIp {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ScopedIp::V4(v4) => write!(f, "{}", v4.addr),
            ScopedIp::V6(v6) => {
                if v6.scope_id.index != 0 && is_unicast_link_local(&v6.addr) {
                    #[cfg(windows)]
                    {
                        write!(f, "{}%{}", v6.addr, v6.scope_id.index)
                    }
                    #[cfg(not(windows))]
                    {
                        write!(f, "{}%{}", v6.addr, v6.scope_id.name)
                    }
                } else {
                    write!(f, "{}", v6.addr)
                }
            }
        }
    }
}

/// DNS resource record types, stored as `u16`. Can do `as u16` when needed.
///
/// See [RFC 1035 section 3.2.2](https://datatracker.ietf.org/doc/html/rfc1035#section-3.2.2)
#[derive(Debug, PartialEq, Eq, Clone, Copy, PartialOrd, Ord)]
#[non_exhaustive]
#[repr(u16)]
pub enum RRType {
    /// DNS record type for IPv4 address
    A = 1,

    /// DNS record type for Canonical Name
    CNAME = 5,

    /// DNS record type for Pointer
    PTR = 12,

    /// DNS record type for Host Info
    HINFO = 13,

    /// DNS record type for Text (properties)
    TXT = 16,

    /// DNS record type for IPv6 address
    AAAA = 28,

    /// DNS record type for Service
    SRV = 33,

    /// DNS record type for Negative Responses
    NSEC = 47,

    /// DNS service binding record
    SVCB = 64,

    /// HTTPS service binding record
    HTTPS = 65,

    /// DNS record type for any records (wildcard)
    ANY = 255,
}

impl RRType {
    /// Converts `u16` into `RRType` if possible.
    pub const fn from_u16(value: u16) -> Option<Self> {
        match value {
            1 => Some(RRType::A),
            5 => Some(RRType::CNAME),
            12 => Some(RRType::PTR),
            13 => Some(RRType::HINFO),
            16 => Some(RRType::TXT),
            28 => Some(RRType::AAAA),
            33 => Some(RRType::SRV),
            47 => Some(RRType::NSEC),
            64 => Some(RRType::SVCB),
            65 => Some(RRType::HTTPS),
            255 => Some(RRType::ANY),
            _ => None,
        }
    }
}

impl fmt::Display for RRType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RRType::A => write!(f, "TYPE_A"),
            RRType::CNAME => write!(f, "TYPE_CNAME"),
            RRType::PTR => write!(f, "TYPE_PTR"),
            RRType::HINFO => write!(f, "TYPE_HINFO"),
            RRType::TXT => write!(f, "TYPE_TXT"),
            RRType::AAAA => write!(f, "TYPE_AAAA"),
            RRType::SRV => write!(f, "TYPE_SRV"),
            RRType::NSEC => write!(f, "TYPE_NSEC"),
            RRType::SVCB => write!(f, "TYPE_SVCB"),
            RRType::HTTPS => write!(f, "TYPE_HTTPS"),
            RRType::ANY => write!(f, "TYPE_ANY"),
        }
    }
}

/// The class value for the Internet.
pub const CLASS_IN: u16 = 1;
pub const CLASS_MASK: u16 = 0x7FFF;

/// Cache-flush bit: the most significant bit of the rrclass field of the resource record.  
pub const CLASS_CACHE_FLUSH: u16 = 0x8000;

/// RFC 6762 §6.7: The resource record TTL given in a legacy unicast response SHOULD NOT
/// be greater than ten seconds.
pub const LEGACY_UNICAST_MAX_TTL: u32 = 10;

/// Absolute max size of UDP datagram payload for an mDNS packet over IPv4.
///
/// RFC 6762 section 17:
/// "Even when fragmentation is used, a Multicast DNS packet, including IP and UDP
/// headers, MUST NOT exceed 9000 bytes."
///
/// It is calculated as: 9000 bytes - IPv4 header 20 bytes - UDP header 8 bytes.
pub(crate) const MAX_PKT_ABSOLUTE_IPV4: usize = 8972;

/// Absolute max size of UDP datagram payload for an mDNS packet over IPv6.
///
/// Same 9000-byte ceiling as [`MAX_PKT_ABSOLUTE_IPV4`], less the bigger IPv6 header:
/// 9000 bytes - IPv6 header 40 bytes - UDP header 8 bytes.
pub(crate) const MAX_PKT_ABSOLUTE_IPV6: usize = 8952;

/// Absolute max size of an mDNS packet for the given IP version.
pub(crate) const fn max_pkt_absolute(is_ipv4: bool) -> usize {
    if is_ipv4 {
        MAX_PKT_ABSOLUTE_IPV4
    } else {
        MAX_PKT_ABSOLUTE_IPV6
    }
}

/// Default max size of a generated (i.e. outgoing) packet.
///
/// Calculated as: 1500 bytes Ethernet MTU - IPv6 header 40 bytes - UDP header 8 bytes.
/// It is safe on both IPv4 and IPv6, at the cost of 20 unused bytes for IPv4.
///
/// The idea is to keep generated packets unfragmented at IP layer. See RFC 6762 section 17.
pub const MAX_PKT_DEFAULT: usize = 1452;

const MSG_HEADER_LEN: usize = 12;

/// Max size of a single DNS label, in bytes.
///
/// Reference: [RFC1035 section 2.3.4](https://datatracker.ietf.org/doc/html/rfc1035#section-2.3.4)
const MAX_LABEL_BYTES: usize = 63;

/// Max size of a whole domain name, in bytes.
///
/// Reference: [RFC1035 section 2.3.4](https://datatracker.ietf.org/doc/html/rfc1035#section-2.3.4)
const MAX_NAME_BYTES: usize = 255;

/// Why a question or a record could not be written into a packet.
///
/// In either case nothing is left behind in the packet: the caller rolls back
/// whatever was written and skips the item.
#[derive(Debug, PartialEq, Eq)]
pub enum WriteError {
    /// A label in a name is longer than [`MAX_LABEL_BYTES`].
    NameTooLong,

    /// The packet would exceed its max size with this record.
    PacketFull,
}

/// `crate::error::Result` shadows the std alias here, hence the full path.
type WriteResult = core::result::Result<(), WriteError>;

// Definitions for DNS message header "flags" field
//
// The "flags" field is 16-bit long, in this format:
// (RFC 1035 section 4.1.1)
//
//   0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
// |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE   |
//
pub const FLAGS_QR_MASK: u16 = 0x8000; // mask for query/response bit

/// Flag bit to indicate a query
pub const FLAGS_QR_QUERY: u16 = 0x0000;

/// Flag bit to indicate a response
pub const FLAGS_QR_RESPONSE: u16 = 0x8000;

/// Flag bit for Authoritative Answer
pub const FLAGS_AA: u16 = 0x0400;

/// mask for TC(Truncated) bit
///
/// 2024-08-10: currently this flag is only supported on the querier side,
///             not supported on the responder side. I.e. the responder only
///             handles the first packet and ignore this bit. Since the
///             additional packets have 0 questions, the processing of them
///             is no-op.
///             In practice, this means the responder supports Known-Answer
///             only with single packet, not multi-packet. The querier supports
///             both single packet and multi-packet.
pub const FLAGS_TC: u16 = 0x0200;

/// A convenience type alias for DNS record trait objects.
pub type DnsRecordBox = Box<dyn DnsRecordExt>;

impl Clone for DnsRecordBox {
    fn clone(&self) -> Self {
        self.clone_box()
    }
}

const U16_SIZE: usize = 2;

/// Returns `RRType` for a given IP address.
#[inline]
pub const fn ip_address_rr_type(address: &IpAddr) -> RRType {
    match address {
        IpAddr::V4(_) => RRType::A,
        IpAddr::V6(_) => RRType::AAAA,
    }
}

#[derive(Eq, PartialEq, Debug, Clone)]
pub struct DnsEntry {
    pub(crate) name: String, // always lower case.
    pub(crate) ty: RRType,
    class: u16,
    cache_flush: bool,
}

impl DnsEntry {
    const fn new(name: String, ty: RRType, class: u16) -> Self {
        Self {
            name,
            ty,
            class: class & CLASS_MASK,
            cache_flush: (class & CLASS_CACHE_FLUSH) != 0,
        }
    }
}

/// Common methods for all DNS entries:  questions and resource records.
pub trait DnsEntryExt: fmt::Debug {
    fn entry_name(&self) -> &str;

    fn entry_type(&self) -> RRType;
}

/// A DNS question entry
#[derive(Debug)]
pub struct DnsQuestion {
    pub(crate) entry: DnsEntry,
}

impl DnsEntryExt for DnsQuestion {
    fn entry_name(&self) -> &str {
        &self.entry.name
    }

    fn entry_type(&self) -> RRType {
        self.entry.ty
    }
}

/// A DNS Resource Record - like a DNS entry, but has a TTL.
/// RFC: https://www.rfc-editor.org/rfc/rfc1035#section-3.2.1
///      https://www.rfc-editor.org/rfc/rfc1035#section-4.1.3
#[derive(Debug, Clone)]
pub struct DnsRecord {
    pub(crate) entry: DnsEntry,
    ttl: u32, // in seconds, 0 means this record should not be cached
    /// When this record was created (received or registered).
    created: Instant,
    /// When this record expires.
    expires: Instant,

    /// Support re-query an instance before its PTR record expires.
    /// See https://datatracker.ietf.org/doc/html/rfc6762#section-5.2
    refresh: Instant,

    /// If conflict resolution decides to change the name, this is the new one.
    new_name: Option<String>,
}

impl DnsRecord {
    fn new(name: &str, ty: RRType, class: u16, ttl: u32) -> Self {
        let created = Instant::now();

        // From RFC 6762 section 5.2:
        // "... The querier should plan to issue a query at 80% of the record
        // lifetime, and then if no answer is received, at 85%, 90%, and 95%."
        let refresh = get_expiration_time(created, ttl, 80);

        let expires = get_expiration_time(created, ttl, 100);

        Self {
            entry: DnsEntry::new(name.to_string(), ty, class),
            ttl,
            created,
            expires,
            refresh,
            new_name: None,
        }
    }

    pub const fn get_ttl(&self) -> u32 {
        self.ttl
    }

    pub const fn get_expire_time(&self) -> Instant {
        self.expires
    }

    pub const fn get_refresh_time(&self) -> Instant {
        self.refresh
    }

    pub fn is_expired(&self, now: Instant) -> bool {
        now >= self.expires
    }

    /// Returns whether record expires in 1 second.
    ///
    /// This is useful because mDNS sets TTL to 1 (not 0) for expiring records.
    pub fn expires_soon(&self, now: Instant) -> bool {
        now + Duration::from_millis(1000) >= self.expires
    }

    pub fn refresh_due(&self, now: Instant) -> bool {
        now >= self.refresh
    }

    /// Returns whether `now` (in millis) has passed half of TTL.
    pub fn halflife_passed(&self, now: Instant) -> bool {
        let halflife = get_expiration_time(self.created, self.ttl, 50);
        now > halflife
    }

    pub fn is_unique(&self) -> bool {
        self.entry.cache_flush
    }

    /// Updates the refresh time to be the same as the expire time so that
    /// this record will not refresh again and will just expire.
    pub fn refresh_no_more(&mut self) {
        self.refresh = get_expiration_time(self.created, self.ttl, 100);
    }

    /// Returns if this record is due for refresh. If yes, `refresh` time is updated.
    pub fn refresh_maybe(&mut self, now: Instant) -> bool {
        if self.is_expired(now) || !self.refresh_due(now) {
            return false;
        }

        trace!(
            "{} qtype {} is due to refresh",
            self.entry.name,
            self.entry.ty
        );

        // From RFC 6762 section 5.2:
        // "... The querier should plan to issue a query at 80% of the record
        // lifetime, and then if no answer is received, at 85%, 90%, and 95%."
        //
        // If the answer is received in time, 'refresh' will be reset outside
        // this function, back to 80% of the new TTL.
        if self.refresh == get_expiration_time(self.created, self.ttl, 80) {
            self.refresh = get_expiration_time(self.created, self.ttl, 85);
        } else if self.refresh == get_expiration_time(self.created, self.ttl, 85) {
            self.refresh = get_expiration_time(self.created, self.ttl, 90);
        } else if self.refresh == get_expiration_time(self.created, self.ttl, 90) {
            self.refresh = get_expiration_time(self.created, self.ttl, 95);
        } else {
            self.refresh_no_more();
        }

        true
    }

    /// Return the absolute time for this record being created
    pub const fn get_created(&self) -> Instant {
        self.created
    }

    /// Set the expiration time
    fn set_expire(&mut self, expire_at: Instant) {
        self.expires = expire_at;
    }

    /// Moves this record's timestamps back by `elapsed`, as if `elapsed`
    /// more time had passed since it was created.
    ///
    /// If a timestamp cannot be moved back that far, the record is marked
    /// expired instead.
    fn age_by(&mut self, elapsed: Duration) {
        match (
            self.created.checked_sub(elapsed),
            self.expires.checked_sub(elapsed),
            self.refresh.checked_sub(elapsed),
        ) {
            (Some(created), Some(expires), Some(refresh)) => {
                self.created = created;
                self.expires = expires;
                self.refresh = refresh;
            }
            _ => {
                // `created` is in the past, so the record is expired now.
                self.expires = self.created;
                self.refresh = self.created;
            }
        }
    }

    fn reset_ttl(&mut self, other: &Self) {
        self.ttl = other.ttl;
        self.created = other.created;
        self.expires = get_expiration_time(self.created, self.ttl, 100);
        self.refresh = if self.ttl > 1 {
            get_expiration_time(self.created, self.ttl, 80)
        } else {
            // If TTL is 1, it means this record is expiring,
            // then we set refresh to the same time as expires.
            self.expires
        };
    }

    /// Modify TTL to reflect the remaining life time from `now`.
    pub fn update_ttl(&mut self, now: Instant) {
        let elapsed = now.saturating_duration_since(self.created);
        self.ttl = self.ttl.saturating_sub(elapsed.as_secs() as u32);
    }

    pub fn set_new_name(&mut self, new_name: String) {
        if new_name == self.entry.name {
            self.new_name = None;
        } else {
            self.new_name = Some(new_name);
        }
    }

    pub fn get_new_name(&self) -> Option<&str> {
        self.new_name.as_deref()
    }

    /// Return the new name if exists, otherwise the regular name in DnsEntry.
    pub(crate) fn get_name(&self) -> &str {
        self.new_name.as_deref().unwrap_or(&self.entry.name)
    }

    pub fn get_original_name(&self) -> &str {
        &self.entry.name
    }
}

impl PartialEq for DnsRecord {
    fn eq(&self, other: &Self) -> bool {
        self.entry == other.entry
    }
}

/// Common methods for DNS resource records.
pub trait DnsRecordExt: fmt::Debug {
    fn get_record(&self) -> &DnsRecord;
    fn get_record_mut(&mut self) -> &mut DnsRecord;
    /// Writes the rdata of this record into `packet`.
    fn write(&self, packet: &mut DnsOutPacket) -> WriteResult;
    fn any(&self) -> &dyn Any;

    /// Returns whether `other` record is considered the same except TTL.
    fn matches(&self, other: &dyn DnsRecordExt) -> bool;

    /// Returns whether `other` record has the same rdata.
    fn rrdata_match(&self, other: &dyn DnsRecordExt) -> bool;

    /// Returns the result based on a byte-level comparison of `rdata`.
    /// If `other` is not valid, returns `Greater`.
    fn compare_rdata(&self, other: &dyn DnsRecordExt) -> cmp::Ordering;

    /// Returns the result based on "lexicographically later" defined below.
    fn compare(&self, other: &dyn DnsRecordExt) -> cmp::Ordering {
        /*
        RFC 6762: https://datatracker.ietf.org/doc/html/rfc6762#section-8.2

        ... The determination of "lexicographically later" is performed by first
        comparing the record class (excluding the cache-flush bit described
        in Section 10.2), then the record type, then raw comparison of the
        binary content of the rdata without regard for meaning or structure.
        If the record classes differ, then the numerically greater class is
        considered "lexicographically later".  Otherwise, if the record types
        differ, then the numerically greater type is considered
        "lexicographically later".  If the rrtype and rrclass both match,
        then the rdata is compared. ...
        */
        match self.get_class().cmp(&other.get_class()) {
            cmp::Ordering::Equal => match self.get_type().cmp(&other.get_type()) {
                cmp::Ordering::Equal => self.compare_rdata(other),
                not_equal => not_equal,
            },
            not_equal => not_equal,
        }
    }

    /// Returns a human-readable string of rdata.
    fn rdata_print(&self) -> String;

    /// Returns the class only, excluding class_flush / unique bit.
    fn get_class(&self) -> u16 {
        self.get_record().entry.class
    }

    fn get_cache_flush(&self) -> bool {
        self.get_record().entry.cache_flush
    }

    /// Return the new name if exists, otherwise the regular name in DnsEntry.
    fn get_name(&self) -> &str {
        self.get_record().get_name()
    }

    fn get_type(&self) -> RRType {
        self.get_record().entry.ty
    }

    /// Resets TTL using `other` record.
    /// `self.refresh` and `self.expires` are also reset.
    fn reset_ttl(&mut self, other: &dyn DnsRecordExt) {
        self.get_record_mut().reset_ttl(other.get_record());
    }

    fn get_created(&self) -> Instant {
        self.get_record().get_created()
    }

    fn get_expire(&self) -> Instant {
        self.get_record().get_expire_time()
    }

    fn set_expire(&mut self, expire_at: Instant) {
        self.get_record_mut().set_expire(expire_at);
    }

    /// Set expire as `expire_at` if it is sooner than the current `expire`.
    fn set_expire_sooner(&mut self, expire_at: Instant) {
        if expire_at < self.get_expire() {
            self.get_record_mut().set_expire(expire_at);
        }
    }

    /// Ages the record by `elapsed`.
    fn age_by(&mut self, elapsed: Duration) {
        self.get_record_mut().age_by(elapsed);
    }

    /// Returns true if the record expires in 1 second from `now`.
    fn expires_soon(&self, now: Instant) -> bool {
        self.get_record().expires_soon(now)
    }

    /// Given `now`, if the record is due to refresh, this method updates the refresh time
    /// and returns the new refresh time. Otherwise, returns None.
    fn updated_refresh_time(&mut self, now: Instant) -> Option<Instant> {
        if self.get_record_mut().refresh_maybe(now) {
            Some(self.get_record().get_refresh_time())
        } else {
            None
        }
    }

    /// Returns true if another record has matched content,
    /// and if its TTL is at least half of this record's.
    fn suppressed_by_answer(&self, other: &dyn DnsRecordExt) -> bool {
        self.matches(other) && (other.get_record().ttl > self.get_record().ttl / 2)
    }

    /// Required by RFC 6762 Section 7.1: Known-Answer Suppression.
    fn suppressed_by(&self, msg: &DnsIncoming) -> bool {
        for answer in msg.answers.iter() {
            if self.suppressed_by_answer(answer.as_ref()) {
                return true;
            }
        }
        false
    }

    fn clone_box(&self) -> DnsRecordBox;

    fn boxed(self) -> DnsRecordBox;
}

/// Resource Record for IPv4 address or IPv6 address.
#[derive(Debug, Clone)]
pub(crate) struct DnsAddress {
    pub(crate) record: DnsRecord,
    address: IpAddr,
    pub(crate) interface_id: InterfaceId,
}

impl DnsAddress {
    pub fn new(
        name: &str,
        ty: RRType,
        class: u16,
        ttl: u32,
        address: IpAddr,
        interface_id: InterfaceId,
    ) -> Self {
        let record = DnsRecord::new(name, ty, class, ttl);
        Self {
            record,
            address,
            interface_id,
        }
    }

    pub fn address(&self) -> ScopedIp {
        match self.address {
            IpAddr::V4(v4) => ScopedIp::V4(ScopedIpV4 {
                addr: v4,
                interface_ids: vec![self.interface_id.clone()],
            }),
            IpAddr::V6(v6) => ScopedIp::V6(ScopedIpV6 {
                addr: v6,
                scope_id: self.interface_id.clone(),
            }),
        }
    }
}

impl DnsRecordExt for DnsAddress {
    fn get_record(&self) -> &DnsRecord {
        &self.record
    }

    fn get_record_mut(&mut self) -> &mut DnsRecord {
        &mut self.record
    }

    fn write(&self, packet: &mut DnsOutPacket) -> WriteResult {
        match self.address {
            IpAddr::V4(addr) => packet.write_bytes(addr.octets().as_ref()),
            IpAddr::V6(addr) => packet.write_bytes(addr.octets().as_ref()),
        };
        Ok(())
    }

    fn any(&self) -> &dyn Any {
        self
    }

    fn matches(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_a) = other.any().downcast_ref::<Self>() {
            return self.address == other_a.address
                && self.record.entry == other_a.record.entry
                && self.interface_id == other_a.interface_id;
        }
        false
    }

    fn rrdata_match(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_a) = other.any().downcast_ref::<Self>() {
            return self.address == other_a.address;
        }
        false
    }

    fn compare_rdata(&self, other: &dyn DnsRecordExt) -> cmp::Ordering {
        if let Some(other_a) = other.any().downcast_ref::<Self>() {
            self.address.cmp(&other_a.address)
        } else {
            cmp::Ordering::Greater
        }
    }

    fn rdata_print(&self) -> String {
        format!("{}", self.address)
    }

    fn clone_box(&self) -> DnsRecordBox {
        Box::new(self.clone())
    }

    fn boxed(self) -> DnsRecordBox {
        Box::new(self)
    }
}

/// Resource Record for a DNS pointer
#[derive(Debug, Clone)]
pub struct DnsPointer {
    record: DnsRecord,
    alias: String, // the full name of Service Instance
}

impl DnsPointer {
    pub fn new(name: &str, ty: RRType, class: u16, ttl: u32, alias: String) -> Self {
        let record = DnsRecord::new(name, ty, class, ttl);
        Self { record, alias }
    }

    pub fn alias(&self) -> &str {
        &self.alias
    }
}

impl DnsRecordExt for DnsPointer {
    fn get_record(&self) -> &DnsRecord {
        &self.record
    }

    fn get_record_mut(&mut self) -> &mut DnsRecord {
        &mut self.record
    }

    fn write(&self, packet: &mut DnsOutPacket) -> WriteResult {
        packet.write_name(&self.alias)
    }

    fn any(&self) -> &dyn Any {
        self
    }

    fn matches(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_ptr) = other.any().downcast_ref::<Self>() {
            return self.alias == other_ptr.alias && self.record.entry == other_ptr.record.entry;
        }
        false
    }

    fn rrdata_match(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_ptr) = other.any().downcast_ref::<Self>() {
            return self.alias == other_ptr.alias;
        }
        false
    }

    fn compare_rdata(&self, other: &dyn DnsRecordExt) -> cmp::Ordering {
        if let Some(other_ptr) = other.any().downcast_ref::<Self>() {
            self.alias.cmp(&other_ptr.alias)
        } else {
            cmp::Ordering::Greater
        }
    }

    fn rdata_print(&self) -> String {
        self.alias.clone()
    }

    fn clone_box(&self) -> DnsRecordBox {
        Box::new(self.clone())
    }

    fn boxed(self) -> DnsRecordBox {
        Box::new(self)
    }
}

/// Resource Record for a DNS service.
#[derive(Debug, Clone)]
pub struct DnsSrv {
    pub(crate) record: DnsRecord,
    pub(crate) priority: u16, // lower number means higher priority. Should be 0 in common cases.
    pub(crate) weight: u16,   // Should be 0 in common cases
    host: String,
    port: u16,
}

impl DnsSrv {
    pub fn new(
        name: &str,
        class: u16,
        ttl: u32,
        priority: u16,
        weight: u16,
        port: u16,
        host: String,
    ) -> Self {
        let record = DnsRecord::new(name, RRType::SRV, class, ttl);
        Self {
            record,
            priority,
            weight,
            host,
            port,
        }
    }

    pub fn host(&self) -> &str {
        &self.host
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn set_host(&mut self, host: String) {
        self.host = host;
    }
}

impl DnsRecordExt for DnsSrv {
    fn get_record(&self) -> &DnsRecord {
        &self.record
    }

    fn get_record_mut(&mut self) -> &mut DnsRecord {
        &mut self.record
    }

    fn write(&self, packet: &mut DnsOutPacket) -> WriteResult {
        packet.write_short(self.priority);
        packet.write_short(self.weight);
        packet.write_short(self.port);
        packet.write_name(&self.host)
    }

    fn any(&self) -> &dyn Any {
        self
    }

    fn matches(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_svc) = other.any().downcast_ref::<Self>() {
            return self.host == other_svc.host
                && self.port == other_svc.port
                && self.weight == other_svc.weight
                && self.priority == other_svc.priority
                && self.record.entry == other_svc.record.entry;
        }
        false
    }

    fn rrdata_match(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_srv) = other.any().downcast_ref::<Self>() {
            return self.host == other_srv.host
                && self.port == other_srv.port
                && self.weight == other_srv.weight
                && self.priority == other_srv.priority;
        }
        false
    }

    fn compare_rdata(&self, other: &dyn DnsRecordExt) -> cmp::Ordering {
        let Some(other_srv) = other.any().downcast_ref::<Self>() else {
            return cmp::Ordering::Greater;
        };

        // 1. compare `priority`
        match self
            .priority
            .to_be_bytes()
            .cmp(&other_srv.priority.to_be_bytes())
        {
            cmp::Ordering::Equal => {
                // 2. compare `weight`
                match self
                    .weight
                    .to_be_bytes()
                    .cmp(&other_srv.weight.to_be_bytes())
                {
                    cmp::Ordering::Equal => {
                        // 3. compare `port`.
                        match self.port.to_be_bytes().cmp(&other_srv.port.to_be_bytes()) {
                            cmp::Ordering::Equal => self.host.cmp(&other_srv.host),
                            not_equal => not_equal,
                        }
                    }
                    not_equal => not_equal,
                }
            }
            not_equal => not_equal,
        }
    }

    fn rdata_print(&self) -> String {
        format!(
            "priority: {}, weight: {}, port: {}, host: {}",
            self.priority, self.weight, self.port, self.host
        )
    }

    fn clone_box(&self) -> DnsRecordBox {
        Box::new(self.clone())
    }

    fn boxed(self) -> DnsRecordBox {
        Box::new(self)
    }
}

/// Resource Record for a DNS TXT record.
///
/// From [RFC 6763 section 6]:
///
/// The format of each constituent string within the DNS TXT record is a
/// single length byte, followed by 0-255 bytes of text data.
///
/// DNS-SD uses DNS TXT records to store arbitrary key/value pairs
///    conveying additional information about the named service.  Each
///    key/value pair is encoded as its own constituent string within the
///    DNS TXT record, in the form "key=value" (without the quotation
///    marks).  Everything up to the first '=' character is the key (Section
///    6.4).  Everything after the first '=' character to the end of the
///    string (including subsequent '=' characters, if any) is the value
#[derive(Clone)]
pub struct DnsTxt {
    pub(crate) record: DnsRecord,
    text: Vec<u8>,
}

impl DnsTxt {
    pub fn new(name: &str, class: u16, ttl: u32, text: Vec<u8>) -> Self {
        let record = DnsRecord::new(name, RRType::TXT, class, ttl);
        Self { record, text }
    }

    pub fn text(&self) -> &[u8] {
        &self.text
    }
}

impl DnsRecordExt for DnsTxt {
    fn get_record(&self) -> &DnsRecord {
        &self.record
    }

    fn get_record_mut(&mut self) -> &mut DnsRecord {
        &mut self.record
    }

    fn write(&self, packet: &mut DnsOutPacket) -> WriteResult {
        packet.write_bytes(&self.text);
        Ok(())
    }

    fn any(&self) -> &dyn Any {
        self
    }

    fn matches(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_txt) = other.any().downcast_ref::<Self>() {
            return self.text == other_txt.text && self.record.entry == other_txt.record.entry;
        }
        false
    }

    fn rrdata_match(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_txt) = other.any().downcast_ref::<Self>() {
            return self.text == other_txt.text;
        }
        false
    }

    fn compare_rdata(&self, other: &dyn DnsRecordExt) -> cmp::Ordering {
        if let Some(other_txt) = other.any().downcast_ref::<Self>() {
            self.text.cmp(&other_txt.text)
        } else {
            cmp::Ordering::Greater
        }
    }

    fn rdata_print(&self) -> String {
        format!("{:?}", decode_txt(&self.text))
    }

    fn clone_box(&self) -> DnsRecordBox {
        Box::new(self.clone())
    }

    fn boxed(self) -> DnsRecordBox {
        Box::new(self)
    }
}

impl fmt::Debug for DnsTxt {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let properties = decode_txt(&self.text);
        write!(
            f,
            "DnsTxt {{ record: {:?}, text: {:?} }}",
            self.record, properties
        )
    }
}

/// A DNS host information record
#[derive(Debug, Clone)]
struct DnsHostInfo {
    record: DnsRecord,
    cpu: String,
    os: String,
}

impl DnsHostInfo {
    fn new(name: &str, ty: RRType, class: u16, ttl: u32, cpu: String, os: String) -> Self {
        let record = DnsRecord::new(name, ty, class, ttl);
        Self { record, cpu, os }
    }
}

impl DnsRecordExt for DnsHostInfo {
    fn get_record(&self) -> &DnsRecord {
        &self.record
    }

    fn get_record_mut(&mut self) -> &mut DnsRecord {
        &mut self.record
    }

    fn write(&self, packet: &mut DnsOutPacket) -> WriteResult {
        debug!("Writing HInfo: cpu {} os {}", self.cpu, self.os);
        packet.write_bytes(self.cpu.as_bytes());
        packet.write_bytes(self.os.as_bytes());
        Ok(())
    }

    fn any(&self) -> &dyn Any {
        self
    }

    fn matches(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_hinfo) = other.any().downcast_ref::<Self>() {
            return self.cpu == other_hinfo.cpu
                && self.os == other_hinfo.os
                && self.record.entry == other_hinfo.record.entry;
        }
        false
    }

    fn rrdata_match(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_hinfo) = other.any().downcast_ref::<Self>() {
            return self.cpu == other_hinfo.cpu && self.os == other_hinfo.os;
        }
        false
    }

    fn compare_rdata(&self, other: &dyn DnsRecordExt) -> cmp::Ordering {
        if let Some(other_hinfo) = other.any().downcast_ref::<Self>() {
            match self.cpu.cmp(&other_hinfo.cpu) {
                cmp::Ordering::Equal => self.os.cmp(&other_hinfo.os),
                ordering => ordering,
            }
        } else {
            cmp::Ordering::Greater
        }
    }

    fn rdata_print(&self) -> String {
        format!("cpu: {}, os: {}", self.cpu, self.os)
    }

    fn clone_box(&self) -> DnsRecordBox {
        Box::new(self.clone())
    }

    fn boxed(self) -> DnsRecordBox {
        Box::new(self)
    }
}

/// Resource Record for negative responses
///
/// [RFC4034 section 4.1](https://datatracker.ietf.org/doc/html/rfc4034#section-4.1)
/// and
/// [RFC6762 section 6.1](https://datatracker.ietf.org/doc/html/rfc6762#section-6.1)
#[derive(Debug, Clone)]
pub struct DnsNSec {
    record: DnsRecord,
    next_domain: String,
    type_bitmap: Vec<u8>,
}

impl DnsNSec {
    pub fn new(
        name: &str,
        class: u16,
        ttl: u32,
        next_domain: String,
        type_bitmap: Vec<u8>,
    ) -> Self {
        let record = DnsRecord::new(name, RRType::NSEC, class, ttl);
        Self {
            record,
            next_domain,
            type_bitmap,
        }
    }

    /// Returns the types marked by `type_bitmap`
    pub fn _types(&self) -> Vec<u16> {
        // From RFC 4034: 4.1.2 The Type Bit Maps Field
        // https://datatracker.ietf.org/doc/html/rfc4034#section-4.1.2
        //
        // Each bitmap encodes the low-order 8 bits of RR types within the
        // window block, in network bit order.  The first bit is bit 0.  For
        // window block 0, bit 1 corresponds to RR type 1 (A), bit 2 corresponds
        // to RR type 2 (NS), and so forth.

        let mut bit_num = 0;
        let mut results = Vec::new();

        for byte in self.type_bitmap.iter() {
            let mut bit_mask: u8 = 0x80; // for bit 0 in network bit order

            // check every bit in this byte, one by one.
            for _ in 0..8 {
                if (byte & bit_mask) != 0 {
                    results.push(bit_num);
                }
                bit_num += 1;
                bit_mask >>= 1; // mask for the next bit
            }
        }
        results
    }
}

impl DnsRecordExt for DnsNSec {
    fn get_record(&self) -> &DnsRecord {
        &self.record
    }

    fn get_record_mut(&mut self) -> &mut DnsRecord {
        &mut self.record
    }

    fn write(&self, packet: &mut DnsOutPacket) -> WriteResult {
        packet.write_name(&self.next_domain)?;
        // The stored bitmap excludes the RFC 4034 window number and length.
        packet.write_bytes(&[0, self.type_bitmap.len() as u8]);
        packet.write_bytes(&self.type_bitmap);
        Ok(())
    }

    fn any(&self) -> &dyn Any {
        self
    }

    fn matches(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_record) = other.any().downcast_ref::<Self>() {
            return self.next_domain == other_record.next_domain
                && self.type_bitmap == other_record.type_bitmap
                && self.record.entry == other_record.record.entry;
        }
        false
    }

    fn rrdata_match(&self, other: &dyn DnsRecordExt) -> bool {
        if let Some(other_record) = other.any().downcast_ref::<Self>() {
            return self.next_domain == other_record.next_domain
                && self.type_bitmap == other_record.type_bitmap;
        }
        false
    }

    fn compare_rdata(&self, other: &dyn DnsRecordExt) -> cmp::Ordering {
        if let Some(other_nsec) = other.any().downcast_ref::<Self>() {
            match self.next_domain.cmp(&other_nsec.next_domain) {
                cmp::Ordering::Equal => self.type_bitmap.cmp(&other_nsec.type_bitmap),
                ordering => ordering,
            }
        } else {
            cmp::Ordering::Greater
        }
    }

    fn rdata_print(&self) -> String {
        format!(
            "next_domain: {}, type_bitmap len: {}",
            self.next_domain,
            self.type_bitmap.len()
        )
    }

    fn clone_box(&self) -> DnsRecordBox {
        Box::new(self.clone())
    }

    fn boxed(self) -> DnsRecordBox {
        Box::new(self)
    }
}

/// Which section of a DNS message an item belongs to.
#[derive(Clone, Copy, Debug)]
enum Section {
    Question,
    Answer,
    Authority,
    Additional,
}

/// A single packet for outgoing DNS message.
pub struct DnsOutPacket {
    /// All bytes in `data` is the actual packet on the wire.
    data: Vec<u8>,

    /// k: name, v: offset
    names: HashMap<String, u16>,

    /// Max byte size of `data`. i.e. the max packet size.
    max_size: usize,

    /// How many items `data` holds in each section, i.e. the header counts.
    question_count: u16,
    answer_count: u16,
    auth_count: u16,
    addi_count: u16,
}

impl DnsOutPacket {
    fn new(max_size: usize) -> Self {
        Self {
            data: vec![0; MSG_HEADER_LEN],
            names: HashMap::new(),
            max_size,
            question_count: 0,
            answer_count: 0,
            auth_count: 0,
            addi_count: 0,
        }
    }

    pub fn size(&self) -> usize {
        self.data.len()
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.data
    }

    /// True if nothing has been written into this packet yet.
    fn is_empty(&self) -> bool {
        self.question_count == 0
            && self.answer_count == 0
            && self.auth_count == 0
            && self.addi_count == 0
    }

    /// Counts one more item in `section`.
    fn bump(&mut self, section: Section) {
        match section {
            Section::Question => self.question_count += 1,
            Section::Answer => self.answer_count += 1,
            Section::Authority => self.auth_count += 1,
            Section::Additional => self.addi_count += 1,
        }
    }

    fn write_question(&mut self, question: &DnsQuestion) -> WriteResult {
        let start_size = self.size();

        self.write_name(&question.entry.name).map_err(|e| {
            self.rollback(start_size);
            e
        })?;
        self.write_short(question.entry.ty as u16);
        self.write_short(question.entry.class);

        if self.size() > self.max_size {
            self.rollback(start_size);
            return Err(WriteError::PacketFull);
        }

        Ok(())
    }

    /// Discards everything written since `start_size`, including the name
    /// compression offsets that point into the discarded bytes.
    fn rollback(&mut self, start_size: usize) {
        self.data.truncate(start_size);
        self.names
            .retain(|_, offset| (*offset as usize) < start_size);
    }

    /// Writes a record (answer, authoritative answer, additional).
    ///
    /// In error cases nothing is written to the packet.
    fn write_record(&mut self, record_ext: &dyn DnsRecordExt) -> WriteResult {
        let start_size = self.size();

        let record = record_ext.get_record();
        self.write_name(record.get_name())?;
        self.write_short(record.entry.ty as u16);
        if record.entry.cache_flush {
            // check "multicast"
            self.write_short(record.entry.class | CLASS_CACHE_FLUSH);
        } else {
            self.write_short(record.entry.class);
        }

        self.write_u32(record.ttl);

        // Placeholder for record size
        self.write_short(0);
        let record_offset = self.size();

        if let Err(e) = record_ext.write(self) {
            self.rollback(start_size);
            return Err(e);
        }

        self.set_short_at(record_offset - 2, (self.size() - record_offset) as u16);

        if self.size() > self.max_size {
            self.rollback(start_size);
            return Err(WriteError::PacketFull);
        }

        Ok(())
    }

    fn set_short_at(&mut self, index: usize, value: u16) {
        self.data[index..index + 2].copy_from_slice(&value.to_be_bytes());
    }

    /// Parses a DNS name that may contain escaped characters according to RFC 6763 Section 4.3.
    /// Returns a vector of labels where each label is the unescaped content.
    ///
    /// Escape sequences:
    /// - \\. becomes . (literal dot)
    /// - \\\\ becomes \\ (literal backslash)
    fn parse_escaped_name(name: &str) -> Vec<String> {
        let mut labels = Vec::new();
        let mut current_label = String::new();
        let mut chars = name.chars().peekable();

        while let Some(ch) = chars.next() {
            match ch {
                '\\' => {
                    // Backslash escape sequence
                    if let Some(&next_ch) = chars.peek() {
                        match next_ch {
                            '.' | '\\' => {
                                // \\. or \\\\ - consume the backslash and add the escaped char
                                chars.next();
                                current_label.push(next_ch);
                            }
                            _ => {
                                // Not a recognized escape - treat backslash literally
                                current_label.push(ch);
                            }
                        }
                    } else {
                        // Trailing backslash - add it literally
                        current_label.push(ch);
                    }
                }
                '.' => {
                    // Unescaped dot - label separator
                    if !current_label.is_empty() {
                        labels.push(current_label.clone());
                        current_label.clear();
                    }
                }
                _ => {
                    current_label.push(ch);
                }
            }
        }

        // Add the last label if not empty
        if !current_label.is_empty() {
            labels.push(current_label);
        }

        labels
    }

    // Write name to packet
    //
    // [RFC1035]
    // 4.1.4. Message compression
    //
    // In order to reduce the size of messages, the domain system utilizes a
    // compression scheme which eliminates the repetition of domain names in a
    // message.  In this scheme, an entire domain name or a list of labels at
    // the end of a domain name is replaced with a pointer to a prior occurrence
    // of the same name.
    // The pointer takes the form of a two octet sequence:
    //     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //     | 1  1|                OFFSET                   |
    //     +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    // The first two bits are ones.  This allows a pointer to be distinguished
    // from a label, since the label must begin with two zero bits because
    // labels are restricted to 63 octets or less.  (The 10 and 01 combinations
    // are reserved for future use.)  The OFFSET field specifies an offset from
    // the start of the message (i.e., the first octet of the ID field in the
    // domain header).  A zero offset specifies the first byte of the ID field,
    // etc.
    //
    // This function also handles RFC 6763 Section 4.3 escaping where dots and backslashes
    // in instance names are escaped (e.g., "My\\.Service" represents a single label "My.Service").
    // The actual name sent over the wire is the unescaped version.
    fn write_name(&mut self, name: &str) -> WriteResult {
        // Remove trailing dot if present
        let name_to_parse = name.strip_suffix('.').unwrap_or(name);

        // Parse the name considering escape sequences
        let labels = Self::parse_escaped_name(name_to_parse);

        if labels.is_empty() {
            self.write_byte(0);
            return Ok(());
        }

        // Validate before writing anything.
        if labels.iter().any(|label| label.len() > MAX_LABEL_BYTES) {
            return Err(WriteError::NameTooLong);
        }

        // Write each label
        for (i, label) in labels.iter().enumerate() {
            // Build the remaining name for compression (with dots as separators)
            let remaining: String = labels[i..].join(".");

            // Check if we can use compression for the remaining part
            const POINTER_MASK: u16 = 0xC000;
            if let Some(&offset) = self.names.get(&remaining) {
                let pointer = offset | POINTER_MASK;
                self.write_short(pointer);
                return Ok(());
            }

            // Store this position for potential future compression
            self.names.insert(remaining, self.size() as u16);

            // Write the label
            self.write_utf8(label)?;
        }

        // Write terminating zero byte
        self.write_byte(0);
        Ok(())
    }

    fn write_byte(&mut self, v: u8) {
        self.data.push(v);
    }

    fn write_bytes(&mut self, s: &[u8]) {
        self.data.extend(s);
    }

    /// Writes a single label. Nothing is written if the label is too long to
    /// be encoded.
    fn write_utf8(&mut self, s: &str) -> WriteResult {
        if s.len() > MAX_LABEL_BYTES {
            return Err(WriteError::NameTooLong);
        }
        self.write_byte(s.len() as u8);
        self.write_bytes(s.as_bytes());
        Ok(())
    }

    fn write_u32(&mut self, v: u32) {
        self.data.extend(&v.to_be_bytes());
    }

    fn write_short(&mut self, v: u16) {
        self.data.extend(&v.to_be_bytes());
    }

    /// Marks this finished packet as truncated, i.e. the message continues in
    /// the next packet.
    fn set_truncated(&mut self) {
        let flags = u16::from_be_bytes([self.data[2], self.data[3]]);
        self.set_short_at(2, flags | FLAGS_TC);
    }

    /// Writes the header fields and finish the packet.
    /// This function should be only called when finishing a packet.
    ///
    /// The header format is based on RFC 1035 section 4.1.1:
    /// https://datatracker.ietf.org/doc/html/rfc1035#section-4.1.1
    //
    //                                  1  1  1  1  1  1
    //    0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                      ID                       |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE   |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    QDCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    ANCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    NSCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //    |                    ARCOUNT                    |
    //    +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    //
    fn write_header(&mut self, id: u16, flags: u16) {
        self.set_short_at(0, id);
        self.set_short_at(2, flags);
        self.set_short_at(4, self.question_count);
        self.set_short_at(6, self.answer_count);
        self.set_short_at(8, self.auth_count);
        self.set_short_at(10, self.addi_count);
    }
}

/// Encodes a [`DnsOutgoing`] into one or more [`DnsOutPacket`], starting a new
/// packet whenever the current one runs out of room.
struct PacketBuilder<'a> {
    out: &'a DnsOutgoing,

    /// Max size of a packet that holds more than one record.
    max_size: usize,

    /// IP version these packets are bound for, which decides their absolute
    /// ceiling: see [`max_pkt_absolute`].
    is_ipv4: bool,

    finished: Vec<DnsOutPacket>,
    current: DnsOutPacket,
}

impl<'a> PacketBuilder<'a> {
    fn new(out: &'a DnsOutgoing, max_size: usize, is_ipv4: bool) -> Self {
        Self {
            out,
            max_size,
            is_ipv4,
            finished: Vec::new(),
            current: DnsOutPacket::new(max_size),
        }
    }

    /// Writes one question or record into the current packet, starting a new
    /// packet if it does not fit in the current one.
    ///
    /// An item that cannot be encoded at all is skipped, leaving the packet as
    /// it was. Sections are written in message order, so an item that spills
    /// never lands ahead of one already written.
    fn add<F>(&mut self, section: Section, write: F)
    where
        F: Fn(&mut DnsOutPacket) -> WriteResult,
    {
        match write(&mut self.current) {
            Ok(()) => {
                self.current.bump(section);
                return;
            }
            // The item can never be encoded: skip it.
            Err(WriteError::NameTooLong) => return,
            Err(WriteError::PacketFull) => {}
        }

        // Packet is full. Flush the current and create a new one.
        if !self.current.is_empty() {
            self.flush();

            match write(&mut self.current) {
                Ok(()) => {
                    self.current.bump(section);
                    return;
                }
                Err(WriteError::NameTooLong) => return,
                Err(WriteError::PacketFull) => {}
            }
        }

        // Packet is still full. A question such big is not legitimate.
        if matches!(section, Section::Question) {
            return;
        }

        // Packet is still full. We will send this single record.

        // RFC 6762 section 17:
        // "a record too large for one MTU-sized packet SHOULD be sent alone, in a
        // single IP datagram".
        self.current.max_size = max_pkt_absolute(self.is_ipv4);

        if write(&mut self.current).is_ok() {
            self.current.bump(section);
            self.flush();
        } else {
            // Too big even for the hard ceiling: skip the record and carry on.
            self.current.max_size = self.max_size;
            debug!(
                "Record too big for absolute max size, skipping: {:?}",
                section
            );
        }
    }

    /// Finishes the current packet and starts a new empty one.
    fn flush(&mut self) {
        self.current
            .write_header(self.out.wire_id(), self.out.flags);

        let next = DnsOutPacket::new(self.max_size);
        self.finished
            .push(std::mem::replace(&mut self.current, next));
    }

    fn finish(mut self) -> Vec<DnsOutPacket> {
        // Always produce at least one packet, even an empty one, but never leave a
        // trailing empty packet behind a full one.
        if !self.current.is_empty() || self.finished.is_empty() {
            self.flush();
        }

        let mut packets = self.finished;

        /*
        RFC 6762 section 7.2: https://datatracker.ietf.org/doc/html/rfc6762#section-7.2
        ...
            When a Multicast DNS querier sends a query to which it already knows some
            answers, it ... sets the TC (Truncated) bit in the header ... [so that the
            responder knows] to wait for the remaining known answers before responding.
         */
        if self.out.is_query() {
            if let Some((_last, rest)) = packets.split_last_mut() {
                for packet in rest {
                    packet.set_truncated();
                }
            }
        }

        packets
    }
}

/// Representation of one outgoing DNS message that could be sent in one or more packet(s).
#[derive(Debug)]
pub struct DnsOutgoing {
    flags: u16,
    id: u16,
    multicast: bool,
    questions: Vec<DnsQuestion>,
    answers: Vec<DnsRecordBox>,
    authorities: Vec<DnsRecordBox>,
    additionals: Vec<DnsRecordBox>,
    known_answer_count: i64, // for internal maintenance only
}

impl DnsOutgoing {
    pub fn new(flags: u16) -> Self {
        Self {
            flags,
            id: 0,
            multicast: true,
            questions: Vec::new(),
            answers: Vec::new(),
            authorities: Vec::new(),
            additionals: Vec::new(),
            known_answer_count: 0,
        }
    }

    pub fn questions(&self) -> &[DnsQuestion] {
        &self.questions
    }

    /// For testing purposes only.
    pub(crate) fn _answers(&self) -> &[DnsRecordBox] {
        &self.answers
    }

    pub fn answers_count(&self) -> usize {
        self.answers.len()
    }

    pub fn authorities(&self) -> &[DnsRecordBox] {
        &self.authorities
    }

    pub fn additionals(&self) -> &[DnsRecordBox] {
        &self.additionals
    }

    pub fn known_answer_count(&self) -> i64 {
        self.known_answer_count
    }

    pub fn set_id(&mut self, id: u16) {
        self.id = id;
    }

    /// Marks whether this message is destined for multicast (the default) or unicast.
    pub fn set_multicast(&mut self, multicast: bool) {
        self.multicast = multicast;
    }

    /// The id to put in the header, always 0 for multicast.
    const fn wire_id(&self) -> u16 {
        if self.multicast {
            0
        } else {
            // RFC 6762 §6.7: a legacy unicast response MUST echo the
            // querier's message id.
            self.id
        }
    }

    pub const fn is_query(&self) -> bool {
        (self.flags & FLAGS_QR_MASK) == FLAGS_QR_QUERY
    }

    // Adds an additional answer

    // From: RFC 6763, DNS-Based Service Discovery, February 2013

    // 12.  DNS Additional Record Generation

    //    DNS has an efficiency feature whereby a DNS server may place
    //    additional records in the additional section of the DNS message.
    //    These additional records are records that the client did not
    //    explicitly request, but the server has reasonable grounds to expect
    //    that the client might request them shortly, so including them can
    //    save the client from having to issue additional queries.

    //    This section recommends which additional records SHOULD be generated
    //    to improve network efficiency, for both Unicast and Multicast DNS-SD
    //    responses.

    // 12.1.  PTR Records

    //    When including a DNS-SD Service Instance Enumeration or Selective
    //    Instance Enumeration (subtype) PTR record in a response packet, the
    //    server/responder SHOULD include the following additional records:

    //    o  The SRV record(s) named in the PTR rdata.
    //    o  The TXT record(s) named in the PTR rdata.
    //    o  All address records (type "A" and "AAAA") named in the SRV rdata.

    // 12.2.  SRV Records

    //    When including an SRV record in a response packet, the
    //    server/responder SHOULD include the following additional records:

    //    o  All address records (type "A" and "AAAA") named in the SRV rdata.
    pub fn add_additional_answer(&mut self, answer: impl DnsRecordExt + 'static) {
        trace!("add_additional_answer: {:?}", answer);
        self.additionals.push(answer.boxed());
    }

    /// A workaround as Rust doesn't allow us to pass DnsRecordBox in as `impl DnsRecordExt`
    pub fn add_answer_box(&mut self, answer_box: DnsRecordBox) {
        self.answers.push(answer_box);
    }

    pub fn add_authority(&mut self, record: DnsRecordBox) {
        self.authorities.push(record);
    }

    /// Retains only the answers for which `keep` returns true.
    pub(crate) fn retain_answers<F>(&mut self, mut keep: F)
    where
        F: FnMut(&DnsRecordBox) -> bool,
    {
        self.answers.retain(|record| keep(record));
    }

    /// Retains only the additional records for which `keep` returns true.
    pub(crate) fn retain_additionals<F>(&mut self, mut keep: F)
    where
        F: FnMut(&DnsRecordBox) -> bool,
    {
        self.additionals.retain(|record| keep(record));
    }

    /// Returns true if `answer` is added to the outgoing msg.
    /// Returns false if `answer` was not added as it is suppressed by the incoming `msg`.
    pub fn add_answer(
        &mut self,
        msg: &DnsIncoming,
        answer: impl DnsRecordExt + Send + 'static,
    ) -> bool {
        trace!("Check for add_answer");
        if answer.suppressed_by(msg) {
            trace!("my answer is suppressed by incoming msg");
            self.known_answer_count += 1;
            return false;
        }

        self.add_answer_record(answer);
        true
    }

    /// Adds `answer` to the outgoing msg unconditionally. Its full TTL is
    /// written on the wire.
    pub fn add_answer_record(&mut self, answer: impl DnsRecordExt + Send + 'static) {
        trace!("add_answer push: {:?}", answer);
        self.answers.push(answer.boxed());
    }

    /// Adds a PTR answer for `service` along with recommended additional records
    /// (SRV, TXT, and address records) per [RFC 6763 Section 12.1].
    ///
    /// Resolves any name conflicts via `dns_registry` and selects addresses
    /// matching the given interface. Does nothing if no addresses are available
    /// on `intf` or if the PTR answer is suppressed by known-answer entries in `msg`.
    ///
    /// [RFC 6763 Section 12.1]: https://tools.ietf.org/html/rfc6763#section-12.1
    pub(crate) fn add_answer_with_additionals(
        &mut self,
        msg: &DnsIncoming,
        service: &ServiceInfo,
        intf: &MyIntf,
        dns_registry: &DnsRegistry,
        is_ipv4: bool,
    ) {
        let intf_addrs = if is_ipv4 {
            service.get_addrs_on_my_intf_v4(intf)
        } else {
            service.get_addrs_on_my_intf_v6(intf)
        };
        if intf_addrs.is_empty() {
            trace!("No addrs on LAN of intf {:?}", intf);
            return;
        }

        // check if we changed our name due to conflicts.
        let service_fullname = dns_registry.resolve_name(service.get_fullname());
        let hostname = dns_registry.resolve_name(service.get_hostname());

        let ptr_added = self.add_answer(
            msg,
            DnsPointer::new(
                service.get_type(),
                RRType::PTR,
                CLASS_IN,
                service.get_other_ttl(),
                service_fullname.to_string(),
            ),
        );

        if !ptr_added {
            trace!("answer was not added for msg {:?}", msg);
            return;
        }

        if let Some(sub) = service.get_subtype() {
            trace!("Adding subdomain {}", sub);
            self.add_additional_answer(DnsPointer::new(
                sub,
                RRType::PTR,
                CLASS_IN,
                service.get_other_ttl(),
                service_fullname.to_string(),
            ));
        }

        // Add recommended additional answers according to
        // https://tools.ietf.org/html/rfc6763#section-12.1.
        self.add_additional_answer(DnsSrv::new(
            service_fullname,
            CLASS_IN | CLASS_CACHE_FLUSH,
            service.get_host_ttl(),
            service.get_priority(),
            service.get_weight(),
            service.get_port(),
            hostname.to_string(),
        ));

        self.add_additional_answer(DnsTxt::new(
            service_fullname,
            CLASS_IN | CLASS_CACHE_FLUSH,
            service.get_other_ttl(),
            service.generate_txt(),
        ));

        for address in intf_addrs {
            self.add_additional_answer(DnsAddress::new(
                hostname,
                ip_address_rr_type(&address),
                CLASS_IN | CLASS_CACHE_FLUSH,
                service.get_host_ttl(),
                address,
                intf.into(),
            ));
        }
    }

    pub fn add_question(&mut self, name: &str, qtype: RRType) {
        let q = DnsQuestion {
            entry: DnsEntry::new(name.to_string(), qtype, CLASS_IN),
        };
        self.questions.push(q);
    }

    /// Adjust records so the message is a valid legacy unicast response:
    ///
    /// - Clear the cache-flush (unique) bit: a legacy resolver
    ///   doesn't know about it and may misinterpret responses where it is set.
    /// - Cap the TTL at [`LEGACY_UNICAST_MAX_TTL`] seconds: legacy resolvers
    ///   cache records without the mDNS cache-coherency mechanisms, so the true
    ///   (longer) TTL must not leak out to them.
    ///
    /// Refer to [RFC 6762 Section 6.7] for details.
    pub fn update_records_for_legacy_unicast(&mut self) {
        let update = |rec: &mut DnsRecordBox| {
            let record = rec.get_record_mut();
            record.entry.cache_flush = false;
            record.ttl = record.ttl.min(LEGACY_UNICAST_MAX_TTL);
        };
        for rec in &mut self.answers {
            update(rec);
        }
        for rec in &mut self.additionals {
            update(rec);
        }
        for rec in &mut self.authorities {
            update(rec);
        }
    }

    /// Returns a list of actual DNS packet data to be sent on the wire, each no
    /// bigger than `max_size`, over the IP version given by `is_ipv4`.
    ///
    /// Most callers want [`MAX_PKT_DEFAULT`] for `max_size`.
    pub fn to_data_on_wire(&self, max_size: usize, is_ipv4: bool) -> Vec<Vec<u8>> {
        let packet_list = self.to_packets(max_size, is_ipv4);
        packet_list.into_iter().map(|p| p.data).collect()
    }

    /// Encode self into one or more packets, each no bigger than `max_size`.
    ///
    /// Questions and records are written in message order and spill into a new
    /// packet whenever the current one is full, so none is dropped for lack of
    /// room. The one exception is a single record too big to fit in an otherwise
    /// empty packet: it is sent alone in an oversized packet, per RFC 6762
    /// section 17.
    ///
    /// `is_ipv4` tells which IP version the packets are bound for, and so how big
    /// that lone oversized packet may get: see [`max_pkt_absolute`]. A record too
    /// big even for that could not be sent at all, and is dropped.
    ///
    /// `max_size` must be no bigger than [`MAX_PKT_ABSOLUTE_IPV6`], the RFC 6762
    /// section 17 ceiling that is legal over either IP version;
    /// [`ServiceDaemon::set_max_packet_size`](crate::ServiceDaemon::set_max_packet_size)
    /// caps what it accepts. Most callers want [`MAX_PKT_DEFAULT`].
    pub fn to_packets(&self, max_size: usize, is_ipv4: bool) -> Vec<DnsOutPacket> {
        debug_assert!(
            max_size <= MAX_PKT_ABSOLUTE_IPV6,
            "max_size {} exceeds the RFC 6762 section 17 ceiling",
            max_size
        );
        let mut builder = PacketBuilder::new(self, max_size, is_ipv4);

        for question in self.questions.iter() {
            builder.add(Section::Question, |packet| packet.write_question(question));
        }

        for answer in self.answers.iter() {
            builder.add(Section::Answer, |packet| {
                packet.write_record(answer.as_ref())
            });
        }

        for auth in self.authorities.iter() {
            builder.add(Section::Authority, |packet| {
                packet.write_record(auth.as_ref())
            });
        }

        for addi in self.additionals.iter() {
            builder.add(Section::Additional, |packet| {
                packet.write_record(addi.as_ref())
            });
        }

        builder.finish()
    }
}

/// An incoming DNS message. It could be a query or a response.
pub struct DnsIncoming {
    offset: usize,
    data: Vec<u8>,
    questions: Vec<DnsQuestion>,
    answers: Vec<DnsRecordBox>,
    authorities: Vec<DnsRecordBox>,
    additional: Vec<DnsRecordBox>,
    id: u16,
    flags: u16,
    num_questions: u16,
    num_answers: u16,
    num_authorities: u16,
    num_additionals: u16,
    interface_id: InterfaceId,
}

/// Written by hand rather than derived, so we don't dump the raw packet unbounded.
impl fmt::Debug for DnsIncoming {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DnsIncoming")
            .field("offset", &self.offset)
            .field("questions", &self.questions)
            .field("answers", &self.answers)
            .field("authorities", &self.authorities)
            .field("additional", &self.additional)
            .field("id", &self.id)
            .field("flags", &self.flags)
            .field("num_questions", &self.num_questions)
            .field("num_answers", &self.num_answers)
            .field("num_authorities", &self.num_authorities)
            .field("num_additionals", &self.num_additionals)
            .field("interface_id", &self.interface_id)
            .finish()
    }
}

impl DnsIncoming {
    pub fn new(data: Vec<u8>, interface_id: InterfaceId) -> Result<Self> {
        let mut incoming = Self {
            offset: 0,
            data,
            questions: Vec::new(),
            answers: Vec::new(),
            authorities: Vec::new(),
            additional: Vec::new(),
            id: 0,
            flags: 0,
            num_questions: 0,
            num_answers: 0,
            num_authorities: 0,
            num_additionals: 0,
            interface_id,
        };

        /*
        RFC 1035 section 4.1: https://datatracker.ietf.org/doc/html/rfc1035#section-4.1
        ...
        All communications inside of the domain protocol are carried in a single
        format called a message.  The top level format of message is divided
        into 5 sections (some of which are empty in certain cases) shown below:

            +---------------------+
            |        Header       |
            +---------------------+
            |       Question      | the question for the name server
            +---------------------+
            |        Answer       | RRs answering the question
            +---------------------+
            |      Authority      | RRs pointing toward an authority
            +---------------------+
            |      Additional     | RRs holding additional information
            +---------------------+
         */
        if let Err(e) = incoming.read_sections() {
            return Err(Error::Msg(format!(
                "{e}; raw packet length: {}",
                incoming.data.len(),
            )));
        }

        Ok(incoming)
    }

    /// Reads the five message sections in order. Kept separate from `new` so a
    /// parse failure can be annotated with the raw packet bytes.
    fn read_sections(&mut self) -> Result<()> {
        self.read_header()?;
        self.read_questions()?;
        self.read_answers()?;
        self.read_authorities()?;
        self.read_additional()?;
        Ok(())
    }

    pub fn id(&self) -> u16 {
        self.id
    }

    pub fn questions(&self) -> &[DnsQuestion] {
        &self.questions
    }

    pub fn answers(&self) -> &[DnsRecordBox] {
        &self.answers
    }

    pub fn authorities(&self) -> &[DnsRecordBox] {
        &self.authorities
    }

    pub fn additionals(&self) -> &[DnsRecordBox] {
        &self.additional
    }

    pub fn answers_mut(&mut self) -> &mut Vec<DnsRecordBox> {
        &mut self.answers
    }

    pub fn authorities_mut(&mut self) -> &mut Vec<DnsRecordBox> {
        &mut self.authorities
    }

    pub fn additionals_mut(&mut self) -> &mut Vec<DnsRecordBox> {
        &mut self.additional
    }

    pub fn all_records(self) -> impl Iterator<Item = DnsRecordBox> {
        self.answers
            .into_iter()
            .chain(self.authorities)
            .chain(self.additional)
    }

    pub fn num_additionals(&self) -> u16 {
        self.num_additionals
    }

    pub fn num_authorities(&self) -> u16 {
        self.num_authorities
    }

    pub fn num_questions(&self) -> u16 {
        self.num_questions
    }

    pub const fn is_query(&self) -> bool {
        (self.flags & FLAGS_QR_MASK) == FLAGS_QR_QUERY
    }

    pub const fn is_response(&self) -> bool {
        (self.flags & FLAGS_QR_MASK) == FLAGS_QR_RESPONSE
    }

    fn read_header(&mut self) -> Result<()> {
        if self.data.len() < MSG_HEADER_LEN {
            return Err(e_fmt!(
                "DNS incoming: header is too short: {} bytes",
                self.data.len()
            ));
        }

        let data = &self.data[0..];
        self.id = u16_from_be_slice(&data[..2]);
        self.flags = u16_from_be_slice(&data[2..4]);
        self.num_questions = u16_from_be_slice(&data[4..6]);
        self.num_answers = u16_from_be_slice(&data[6..8]);
        self.num_authorities = u16_from_be_slice(&data[8..10]);
        self.num_additionals = u16_from_be_slice(&data[10..12]);

        self.offset = MSG_HEADER_LEN;

        trace!(
            "read_header: id {}, {} questions {} answers {} authorities {} additionals",
            self.id,
            self.num_questions,
            self.num_answers,
            self.num_authorities,
            self.num_additionals
        );
        Ok(())
    }

    fn read_questions(&mut self) -> Result<()> {
        trace!("read_questions: {}", self.num_questions);
        for i in 0..self.num_questions {
            let name = self.read_name()?;

            let data = &self.data[self.offset..];
            if data.len() < 4 {
                return Err(Error::Msg(format!(
                    "DNS incoming: question idx {} too short: {}",
                    i,
                    data.len()
                )));
            }
            let ty = u16_from_be_slice(&data[..2]);
            let class = u16_from_be_slice(&data[2..4]);
            self.offset += 4;

            let Some(rr_type) = RRType::from_u16(ty) else {
                // Skip unsupported question types instead of failing the whole message.
                debug!("DNS incoming: skipping question idx {i} qtype unknown: {ty}");
                continue;
            };

            self.questions.push(DnsQuestion {
                entry: DnsEntry::new(name, rr_type, class),
            });
        }
        Ok(())
    }

    fn read_answers(&mut self) -> Result<()> {
        self.answers = self.read_rr_records(self.num_answers)?;
        Ok(())
    }

    fn read_authorities(&mut self) -> Result<()> {
        self.authorities = self.read_rr_records(self.num_authorities)?;
        Ok(())
    }

    fn read_additional(&mut self) -> Result<()> {
        self.additional = self.read_rr_records(self.num_additionals)?;
        Ok(())
    }

    /// Decodes a sequence of RR records (in answers, authorities and additionals).
    fn read_rr_records(&mut self, count: u16) -> Result<Vec<DnsRecordBox>> {
        trace!("read_rr_records: {}", count);
        let mut rr_records = Vec::new();

        // RFC 1035: https://datatracker.ietf.org/doc/html/rfc1035#section-3.2.1
        //
        // All RRs have the same top level format shown below:
        //                               1  1  1  1  1  1
        // 0  1  2  3  4  5  6  7  8  9  0  1  2  3  4  5
        // +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        // |                                               |
        // /                                               /
        // /                      NAME                     /
        // |                                               |
        // +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        // |                      TYPE                     |
        // +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        // |                     CLASS                     |
        // +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        // |                      TTL                      |
        // |                                               |
        // +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
        // |                   RDLENGTH                    |
        // +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--|
        // /                     RDATA                     /
        // /                                               /
        // +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+

        // Muse have at least TYPE, CLASS, TTL, RDLENGTH fields: 10 bytes.
        const RR_HEADER_REMAIN: usize = 10;

        for _ in 0..count {
            let name = self.read_name()?;
            let slice = &self.data[self.offset..];

            if slice.len() < RR_HEADER_REMAIN {
                return Err(Error::Msg(format!(
                    "read_others: RR '{}' is too short after name: {} bytes",
                    name,
                    slice.len()
                )));
            }

            let ty = u16_from_be_slice(&slice[..2]);
            let class = u16_from_be_slice(&slice[2..4]);
            let mut ttl = u32_from_be_slice(&slice[4..8]);
            if ttl == 0 && self.is_response() {
                // RFC 6762 section 10.1:
                // "...Queriers receiving a Multicast DNS response with a TTL of zero SHOULD
                // NOT immediately delete the record from the cache, but instead record
                // a TTL of 1 and then delete the record one second later."
                // See https://datatracker.ietf.org/doc/html/rfc6762#section-10.1

                ttl = 1;
            }
            let rdata_len = u16_from_be_slice(&slice[8..10]) as usize;
            self.offset += RR_HEADER_REMAIN;
            let next_offset = self.offset + rdata_len;

            // Sanity check for RDATA length.
            if next_offset > self.data.len() {
                return Err(Error::Msg(format!(
                    "RR {name} RDATA length {rdata_len} is invalid: remain data len: {}",
                    self.data.len() - self.offset
                )));
            }

            // Decode the RDATA based on the record type. A single record with
            // malformed RDATA must not discard the whole message: skip just
            // that record and resume at the next one using RDLENGTH.
            match self.read_rdata(ty, class, ttl, rdata_len, &name) {
                Ok(Some(record)) => {
                    if self.offset == next_offset {
                        trace!("read_rr_records: {:?}", record);
                        rr_records.push(record);
                    } else {
                        debug!(
                            "skipping record '{}' (type {}): RDATA ended at {}, expected {}",
                            name, ty, self.offset, next_offset
                        );
                    }
                }
                Ok(None) => {
                    trace!("Unsupported DNS record type: {} name: {}", ty, name);
                }
                Err(e) => {
                    debug!(
                        "skipping record '{}' (type {}) with invalid RDATA: {}",
                        name, ty, e,
                    );
                }
            }

            // Re-anchor to the record boundary defined by RDLENGTH, regardless
            // of how the RDATA decoded, so the next record is read from the
            // correct offset.
            self.offset = next_offset;
        }

        Ok(rr_records)
    }

    /// Decodes the RDATA of a single record whose header fields have already
    /// been read, returning `None` for record types we do not parse.
    ///
    /// On success the read cursor is left at the end of the RDATA; the caller
    /// verifies that against RDLENGTH. Errors are per-record: the caller skips
    /// the offending record and continues with the rest of the message.
    fn read_rdata(
        &mut self,
        ty: u16,
        class: u16,
        ttl: u32,
        rdata_len: usize,
        name: &str,
    ) -> Result<Option<DnsRecordBox>> {
        let rec: Option<DnsRecordBox> = match RRType::from_u16(ty) {
            None => None,

            Some(rr_type) => match rr_type {
                RRType::CNAME | RRType::PTR => {
                    Some(DnsPointer::new(name, rr_type, class, ttl, self.read_name()?).boxed())
                }
                RRType::TXT => {
                    Some(DnsTxt::new(name, class, ttl, self.read_vec(rdata_len)?).boxed())
                }
                RRType::SRV => Some(
                    DnsSrv::new(
                        name,
                        class,
                        ttl,
                        self.read_u16()?,
                        self.read_u16()?,
                        self.read_u16()?,
                        self.read_name()?,
                    )
                    .boxed(),
                ),
                RRType::HINFO => Some(
                    DnsHostInfo::new(
                        name,
                        rr_type,
                        class,
                        ttl,
                        self.read_char_string()?,
                        self.read_char_string()?,
                    )
                    .boxed(),
                ),
                RRType::A => Some(
                    DnsAddress::new(
                        name,
                        rr_type,
                        class,
                        ttl,
                        self.read_ipv4()?.into(),
                        self.interface_id.clone(),
                    )
                    .boxed(),
                ),
                RRType::AAAA => Some(
                    DnsAddress::new(
                        name,
                        rr_type,
                        class,
                        ttl,
                        self.read_ipv6()?.into(),
                        self.interface_id.clone(),
                    )
                    .boxed(),
                ),
                RRType::NSEC => Some(
                    DnsNSec::new(
                        name,
                        class,
                        ttl,
                        self.read_name()?,
                        self.read_type_bitmap()?,
                    )
                    .boxed(),
                ),
                _ => None,
            },
        };

        Ok(rec)
    }

    fn read_char_string(&mut self) -> Result<String> {
        let Some(&length) = self.data.get(self.offset) else {
            return Err(e_fmt!(
                "read_char_string: no length byte at offset {}, data len {}",
                self.offset,
                self.data.len()
            ));
        };
        self.offset += 1;
        self.read_string(length as usize)
    }

    fn read_u16(&mut self) -> Result<u16> {
        let slice = &self.data[self.offset..];
        if slice.len() < U16_SIZE {
            return Err(Error::Msg(format!(
                "read_u16: slice len is only {}",
                slice.len()
            )));
        }
        let num = u16_from_be_slice(&slice[..U16_SIZE]);
        self.offset += U16_SIZE;
        Ok(num)
    }

    /// Reads the "Type Bit Map" block for a DNS NSEC record.
    fn read_type_bitmap(&mut self) -> Result<Vec<u8>> {
        // From RFC 6762: 6.1.  Negative Responses
        // https://datatracker.ietf.org/doc/html/rfc6762#section-6.1
        //   o The Type Bit Map block number is 0.
        //   o The Type Bit Map block length byte is a value in the range 1-32.
        //   o The Type Bit Map data is 1-32 bytes, as indicated by length
        //     byte.

        // Sanity check: at least 2 bytes to read.
        if self.data.len() < self.offset + 2 {
            return Err(Error::Msg(format!(
                "DnsIncoming is too short: {} at NSEC Type Bit Map offset {}",
                self.data.len(),
                self.offset
            )));
        }

        let block_num = self.data[self.offset];
        self.offset += 1;
        if block_num != 0 {
            return Err(Error::Msg(format!(
                "NSEC block number is not 0: {block_num}"
            )));
        }

        let block_len = self.data[self.offset] as usize;
        if !(1..=32).contains(&block_len) {
            return Err(Error::Msg(format!(
                "NSEC block length must be in the range 1-32: {block_len}"
            )));
        }
        self.offset += 1;

        let end = self.offset + block_len;
        if end > self.data.len() {
            return Err(Error::Msg(format!(
                "NSEC block overflow: {} over RData len {}",
                end,
                self.data.len()
            )));
        }
        let bitmap = self.data[self.offset..end].to_vec();
        self.offset += block_len;

        Ok(bitmap)
    }

    fn read_vec(&mut self, length: usize) -> Result<Vec<u8>> {
        if self.data.len() < self.offset + length {
            return Err(e_fmt!(
                "DNS Incoming: not enough data to read a chunk of data"
            ));
        }

        let v = self.data[self.offset..self.offset + length].to_vec();
        self.offset += length;
        Ok(v)
    }

    fn read_ipv4(&mut self) -> Result<Ipv4Addr> {
        if self.data.len() < self.offset + 4 {
            return Err(e_fmt!("DNS Incoming: not enough data to read an IPV4"));
        }

        let bytes: [u8; 4] = self.data[self.offset..self.offset + 4]
            .try_into()
            .map_err(|_| e_fmt!("DNS incoming: Not enough bytes for reading an IPV4"))?;
        self.offset += bytes.len();
        Ok(Ipv4Addr::from(bytes))
    }

    fn read_ipv6(&mut self) -> Result<Ipv6Addr> {
        if self.data.len() < self.offset + 16 {
            return Err(e_fmt!("DNS Incoming: not enough data to read an IPV6"));
        }

        let bytes: [u8; 16] = self.data[self.offset..self.offset + 16]
            .try_into()
            .map_err(|_| e_fmt!("DNS incoming: Not enough bytes for reading an IPV6"))?;
        self.offset += bytes.len();
        Ok(Ipv6Addr::from(bytes))
    }

    fn read_string(&mut self, length: usize) -> Result<String> {
        if self.data.len() < self.offset + length {
            return Err(e_fmt!("DNS Incoming: not enough data to read a string"));
        }

        let s = str::from_utf8(&self.data[self.offset..self.offset + length])
            .map_err(|e| Error::Msg(e.to_string()))?;
        self.offset += length;
        Ok(s.to_string())
    }

    /// Reads a domain name at the current location of `self.data`.
    ///
    /// See https://datatracker.ietf.org/doc/html/rfc1035#section-3.1 for
    /// domain name encoding.
    fn read_name(&mut self) -> Result<String> {
        let mut name = String::new();
        self.offset = self.read_labels(self.offset, &mut name)?;
        Ok(name)
    }

    /// Appends the labels encoded at `offset` to `name`, and returns the offset
    /// just past that encoding: past the terminating zero byte, or past the
    /// compression pointer that ended the name.
    ///
    /// A name is a sequence of labels, where each label is a length byte
    /// followed by that many bytes. The name ends either with a zero length
    /// byte, or with a "compression pointer" (top 2 bits set) that redirects
    /// to a name written earlier in the same packet.
    ///
    /// For example, a packet where the question name `_http._tcp.local.` is
    /// written out in full at offset 12, and the answer name
    /// `myprinter._http._tcp.local.` at offset 40 reuses it via compression:
    ///
    /// ```text
    ///  offset:  12   13..17    18   19..22   23   24..28    29
    ///          +----+---------+----+--------+----+---------+----+
    ///  bytes:  | 05 | "_http" | 04 | "_tcp" | 05 | "local" | 00 |
    ///          +----+---------+----+--------+----+---------+----+
    ///            ^len           ^len          ^len           ^ zero byte: end of name
    ///
    ///  offset:  40    41..49     50   51
    ///          +----+-------------+----+----+
    ///  bytes:  | 09 | "myprinter" | C0 | 0C |
    ///          +----+-------------+----+----+
    ///            ^len               ^ pointer: 0xC00C ^ 0xC000 = 12, jump back to offset 12
    /// ```
    ///
    /// Takes `&self` so that following a pointer cannot move the read cursor.
    fn read_labels(&self, mut offset: usize, name: &mut String) -> Result<usize> {
        let data = &self.data[..];

        // From RFC1035:
        // "...Domain names in messages are expressed in terms of a sequence of labels.
        // Each label is represented as a one octet length field followed by that
        // number of octets."
        //
        // "...The compression scheme allows a domain name in a message to be
        // represented as either:
        // - a sequence of labels ending in a zero octet
        // - a pointer
        // - a sequence of labels ending with a pointer"
        loop {
            if offset >= data.len() {
                return Err(Error::Msg(format!(
                    "read_labels: offset: {} data len {}",
                    offset,
                    data.len(),
                )));
            }
            let length = data[offset];

            // From RFC1035:
            // "...a domain name is terminated by a length byte of zero."
            if length == 0 {
                return Ok(offset + 1); // The end of the name.
            }

            // Check the first 2 bits for possible "Message compression".
            match length & 0xC0 {
                0x00 => {
                    // regular utf8 string with length
                    offset += 1;
                    let ending = offset + length as usize;

                    // Never read beyond the whole data length.
                    if ending > data.len() {
                        return Err(Error::Msg(format!(
                            "read_labels: ending {} exceeds data length {}",
                            ending,
                            data.len()
                        )));
                    }

                    let label = str::from_utf8(&data[offset..ending])
                        .map_err(|e| Error::Msg(format!("read_labels: from_utf8: {e}")))?;

                    // `MAX_NAME_BYTES` bounds a possible loop where pointer targets a label that
                    // is already part of the current name. For example:
                    //
                    //  offset:  12   13..17    18   19
                    //          +----+---------+----+----+
                    //  bytes:  | 05 | "_http" | C0 | 0C |
                    //          +----+---------+----+----+
                    //            ^len           ^pointer targets offset 12.
                    if name.len() + label.len() + 1 > MAX_NAME_BYTES {
                        return Err(Error::Msg(format!(
                            "read_labels: name exceeds {MAX_NAME_BYTES} bytes: {name}"
                        )));
                    }

                    *name += label;
                    *name += ".";
                    offset = ending;
                }
                0xC0 => {
                    // Message compression: a pointer marks the end of a domain name.
                    self.follow_pointer(offset, name)?;
                    return Ok(offset + U16_SIZE);
                }
                _ => {
                    return Err(Error::Msg(format!(
                        "Bad name with invalid length: 0x{:x} offset {}, data (so far): {:x?}",
                        length,
                        offset,
                        &data[..offset]
                    )));
                }
            };
        }
    }

    /// Follows the compression pointer at offset `at`, appending the labels it
    /// names to `name`.
    ///
    /// See https://datatracker.ietf.org/doc/html/rfc1035#section-4.1.4 for
    /// message compression.
    fn follow_pointer(&self, at: usize, name: &mut String) -> Result<()> {
        let data = &self.data[..];
        let mut pointer_at = at;

        // Resolve a run of pointers that target other pointers, so that the
        // recursive call below always lands on a label or on the end of a name.
        let target = loop {
            let slice = &data[pointer_at..];
            if slice.len() < U16_SIZE {
                return Err(Error::Msg(format!(
                    "follow_pointer: u16 slice len is only {}",
                    slice.len()
                )));
            }
            let target = (u16_from_be_slice(slice) ^ 0xC000) as usize;

            // RFC1035 section 4.1.4 compresses a name into "a pointer to a prior
            // occurrence", so a pointer always points strictly backwards.
            if target >= pointer_at {
                return Err(Error::Msg(format!(
                    "Invalid name compression: pointer {target} at offset {pointer_at} must point backwards"
                )));
            }

            if data[target] & 0xC0 != 0xC0 {
                break target;
            }

            // The target is itself a pointer, so follow it.
            pointer_at = target;
        };

        self.read_labels(target, name)?;
        Ok(())
    }
}

const fn u16_from_be_slice(bytes: &[u8]) -> u16 {
    let u8_array: [u8; 2] = [bytes[0], bytes[1]];
    u16::from_be_bytes(u8_array)
}

const fn u32_from_be_slice(s: &[u8]) -> u32 {
    let u8_array: [u8; 4] = [s[0], s[1], s[2], s[3]];
    u32::from_be_bytes(u8_array)
}

/// Returns the time at which this record will have expired by a certain
/// percentage of its TTL.
fn get_expiration_time(created: Instant, ttl: u32, percent: u32) -> Instant {
    // 'ttl' is in seconds, hence:
    // ttl * 1000 * (percent / 100) => ttl * percent * 10
    created + Duration::from_millis(ttl as u64 * percent as u64 * 10)
}

#[cfg(test)]
mod tests {
    use super::{
        u16_from_be_slice, DnsAddress, DnsHostInfo, DnsIncoming, DnsOutPacket, DnsOutgoing,
        DnsPointer, DnsTxt, RRType, CLASS_CACHE_FLUSH, CLASS_IN, FLAGS_QR_QUERY, FLAGS_QR_RESPONSE,
        FLAGS_TC, MAX_PKT_ABSOLUTE_IPV6, MAX_PKT_DEFAULT, MSG_HEADER_LEN,
    };
    use crate::InterfaceId;
    use std::collections::HashMap;
    use std::net::{IpAddr, Ipv4Addr};

    /// The `is_ipv4` argument of `to_packets`. IPv6 has the smaller of the two
    /// absolute ceilings, so it is the stricter one to encode for.
    const IPV6: bool = false;

    /// Found by fuzzing the packet parser.
    ///
    /// An HINFO record with RDLENGTH 0 placed at the very end of a message left
    /// `read_char_string` with no length octet to read, and it indexed one byte
    /// past the packet.
    #[test]
    fn test_hinfo_char_string_at_end_of_packet() {
        let mut data = Vec::new();

        // Header: one authority record, and a query (so the TTL is not rewritten).
        data.extend_from_slice(&0x0087u16.to_be_bytes()); // id
        data.extend_from_slice(&0x0084u16.to_be_bytes()); // flags: a query
        data.extend_from_slice(&0u16.to_be_bytes()); // 0 questions
        data.extend_from_slice(&0u16.to_be_bytes()); // 0 answers
        data.extend_from_slice(&1u16.to_be_bytes()); // 1 authorities
        data.extend_from_slice(&0u16.to_be_bytes()); // 0 additionals

        data.push(0); // name: root
        data.extend_from_slice(&(RRType::HINFO as u16).to_be_bytes());
        data.extend_from_slice(&CLASS_IN.to_be_bytes());
        data.extend_from_slice(&0u32.to_be_bytes()); // ttl

        // RDLENGTH is 0, so the record — and the message — end here, leaving
        // nothing for HINFO's two <character-string> fields.
        data.extend_from_slice(&0u16.to_be_bytes()); // rdlength

        assert_eq!(data.len(), 23);

        let parsed = DnsIncoming::new(data, test_interface_id())
            .expect("a truncated HINFO must be skipped, not fail the packet");

        // The record is dropped, and nothing is left behind.
        assert_eq!(parsed.authorities().len(), 0);
    }

    #[test]
    fn test_dns_outgoing_serialization_empty() {
        let out = DnsOutgoing::new(0);
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(packets[0].as_bytes(), &[0; 12]);
        let expected_names = HashMap::new();
        assert_eq!(&packets[0].names, &expected_names);
    }

    #[test]
    fn test_dns_outgoing_serialization_question() {
        let mut out = DnsOutgoing::new(0);
        out.add_question("123.test", RRType::A);
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(
            packets[0].as_bytes(),
            &[
                0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, // Header
                // Payload
                3, 49, 50, 51, 4, 116, 101, 115, 116, 0, 0, 1, 0, 1,
            ]
        );
        let mut expected_names = HashMap::new();
        expected_names.insert("123.test".to_string(), 12);
        expected_names.insert("test".to_string(), 16);
        assert_eq!(&packets[0].names, &expected_names);
    }

    #[test]
    fn test_dns_outgoing_serialization_question_with_authority() {
        let mut out = DnsOutgoing::new(0);
        out.add_question("123.test", RRType::ANY);
        out.add_authority(Box::new(DnsTxt::new(
            "124.test",
            CLASS_IN,
            0x00112233,
            b"help".to_vec(),
        )));
        out.add_authority(Box::new(DnsHostInfo::new(
            "124.test",
            RRType::CNAME,
            CLASS_IN,
            0x00112233,
            "arm".to_string(),
            "linux".to_string(),
        )));
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(
            packets[0].as_bytes(),
            &[
                0, 0, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, // Header
                // Payload
                3, 49, 50, 51, 4, 116, 101, 115, 116, 0, 0, 255, 0, 1, 3, 49, 50, 52, 192, 16, 0,
                16, 0, 1, 0, 17, 34, 51, 0, 4, 104, 101, 108, 112, 192, 26, 0, 5, 0, 1, 0, 17, 34,
                51, 0, 8, 97, 114, 109, 108, 105, 110, 117, 120,
            ]
        );
        let mut expected_names = HashMap::new();
        expected_names.insert("123.test".to_string(), 12);
        expected_names.insert("test".to_string(), 16);
        expected_names.insert("124.test".to_string(), 26);
        assert_eq!(&packets[0].names, &expected_names);
    }

    #[test]
    fn test_dns_outgoing_serialization_additional_answer() {
        let mut out = DnsOutgoing::new(0);
        out.add_additional_answer(DnsAddress::new(
            "test.local",
            RRType::A,
            CLASS_IN | CLASS_CACHE_FLUSH,
            0xdead_beef,
            IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)),
            InterfaceId::default(),
        ));
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(
            packets[0].as_bytes(),
            &[
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, // Header
                // Payload
                4, 116, 101, 115, 116, 5, 108, 111, 99, 97, 108, 0, 0, 1, 128, 1, 222, 173, 190,
                239, 0, 4, 127, 0, 0, 1,
            ]
        );
        let mut expected_names = HashMap::new();
        expected_names.insert("test.local".to_string(), 12);
        expected_names.insert("local".to_string(), 17);
        assert_eq!(&packets[0].names, &expected_names);
    }

    #[test]
    fn test_dns_outgoing_serialization_answer_at_time() {
        let mut out = DnsOutgoing::new(0);
        out.add_answer_record(DnsPointer::new(
            "test",
            RRType::PTR,
            CLASS_IN,
            0xaaaa5555,
            "test-service".to_string(),
        ));
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(
            packets[0].as_bytes(),
            &[
                0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, // Header
                // Payload
                4, 116, 101, 115, 116, 0, 0, 12, 0, 1, 170, 170, 85, 85, 0, 14, 12, 116, 101, 115,
                116, 45, 115, 101, 114, 118, 105, 99, 101, 0,
            ]
        );

        let mut out = DnsOutgoing::new(0);
        out.add_answer_record(DnsPointer::new(
            "test",
            RRType::CNAME,
            CLASS_IN,
            0xaaaa5555,
            "test-service.local".to_string(),
        ));
        out.add_answer_record(DnsPointer::new(
            "test",
            RRType::AAAA,
            CLASS_IN,
            0xffffffff,
            "test-service.local".to_string(),
        ));
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(
            packets[0].as_bytes(),
            &[
                0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, // Header
                // Payload
                4, 116, 101, 115, 116, 0, 0, 5, 0, 1, 170, 170, 85, 85, 0, 20, 12, 116, 101, 115,
                116, 45, 115, 101, 114, 118, 105, 99, 101, 5, 108, 111, 99, 97, 108, 0, 192, 12, 0,
                28, 0, 1, 255, 255, 255, 255, 0, 2, 192, 28,
            ]
        );
        let mut expected_names = HashMap::new();
        expected_names.insert("test".to_string(), 12);
        expected_names.insert("test-service.local".to_string(), 28);
        expected_names.insert("local".to_string(), 41);
        assert_eq!(&packets[0].names, &expected_names);
    }

    /// A question whose name has a label longer than 63 bytes cannot be
    /// encoded. It must be skipped, not panic. (Note the question count in the
    /// header must reflect the questions actually written.)
    #[test]
    fn test_dns_outgoing_question_label_too_long() {
        let long_label = "a".repeat(64);
        let mut out = DnsOutgoing::new(0);
        out.add_question(&format!("{long_label}.local"), RRType::PTR);
        out.add_question("123.test", RRType::A);

        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(
            packets[0].as_bytes(),
            &[
                0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, // Header: 1 question
                // Payload: only "123.test" made it in.
                3, 49, 50, 51, 4, 116, 101, 115, 116, 0, 0, 1, 0, 1,
            ]
        );

        // The rolled back name must not leave a stale compression offset behind.
        let mut expected_names = HashMap::new();
        expected_names.insert("123.test".to_string(), 12);
        expected_names.insert("test".to_string(), 16);
        assert_eq!(&packets[0].names, &expected_names);
    }

    /// A record whose rdata carries an unencodable name (here a PTR alias) is
    /// dropped as a whole, leaving the rest of the packet intact.
    #[test]
    fn test_dns_outgoing_record_label_too_long() {
        let long_label = "a".repeat(64);
        let mut out = DnsOutgoing::new(0);
        out.add_answer_record(DnsPointer::new(
            "_test._tcp.local.",
            RRType::PTR,
            CLASS_IN,
            0,
            format!("{long_label}._test._tcp.local."),
        ));
        out.add_answer_record(DnsPointer::new(
            "_test._tcp.local.",
            RRType::PTR,
            CLASS_IN,
            0,
            "ok._test._tcp.local.".to_string(),
        ));

        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);

        // Header answer count is 1: the first answer was dropped.
        assert_eq!(&packets[0].as_bytes()[6..8], &[0, 1]);

        // Re-parsing must succeed and yield only the good answer.
        let incoming = DnsIncoming::new(
            packets[0].as_bytes().to_vec(),
            InterfaceId {
                name: "test".to_string(),
                index: 1,
            },
        )
        .unwrap();
        assert_eq!(incoming.answers().len(), 1);
    }

    /// A name learned from the network can hold a label that ends with a
    /// backslash, which escapes the following label separator. Unescaping such
    /// a name on the way out merges two 63-byte labels into a 127-byte one.
    /// This used to panic the daemon thread. See issue #483.
    #[test]
    fn test_incoming_name_with_merged_labels_does_not_panic() {
        // A query with one question: "aa..a\" + "bb..b", 63 bytes each.
        let mut data: Vec<u8> = vec![0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0];
        data.push(63);
        data.extend(vec![b'a'; 62]);
        data.push(b'\\');
        data.push(63);
        data.extend(vec![b'b'; 63]);
        data.push(0);
        data.extend([0, 12, 0, 1]); // PTR, IN

        let incoming = DnsIncoming::new(
            data,
            InterfaceId {
                name: "test".to_string(),
                index: 1,
            },
        )
        .unwrap();
        let name = incoming.questions()[0].entry.name.clone();

        // The two labels merged: the trailing backslash escaped the separator.
        assert!(name.starts_with("aaa"));
        assert!(name.contains("\\.bbb"));

        // Re-emitting it must drop the question rather than panic.
        let mut out = DnsOutgoing::new(0);
        out.add_question(&name, RRType::PTR);
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 1);
        assert_eq!(packets[0].as_bytes(), &[0; MSG_HEADER_LEN]);
    }

    /// A pointer that points into the name currently being read is a loop:
    /// following it re-reads the same labels and arrives at the same pointer
    /// again. `read_name` must reject such a name instead of hanging.
    #[test]
    fn test_read_name_pointer_loop_is_rejected() {
        // A response with one PTR record. Its name starts at offset 12 and is
        // encoded as: label "local", label "_x", then a pointer back to 12,
        // i.e. to the "local" label of this very name.
        let mut data: Vec<u8> = vec![0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0];
        data.extend_from_slice(&[5, b'l', b'o', b'c', b'a', b'l']); // offset 12
        data.extend_from_slice(&[2, b'_', b'x']); // offset 18
        data.extend_from_slice(&[0xC0, 12]); // offset 21: pointer to 12
        data.extend_from_slice(&[0, 12, 0, 1]); // PTR, IN
        data.extend_from_slice(&[0, 0, 0, 120]); // TTL
        data.extend_from_slice(&[0, 2]); // RDLENGTH
        data.extend_from_slice(&[0xC0, 12]); // RDATA: pointer to 12

        assert!(DnsIncoming::new(data, test_interface_id()).is_err());
    }

    /// A legal name that follows a pointer backwards and then meets a second
    /// pointer whose target sits *after* the start of the name being read, yet
    /// still strictly *before* that second pointer's own position.
    ///
    /// Such a message probably never appears in reality, but it still has to parse.
    /// Reading the answer's name walks: 700 -> 640 -> 62-byte label -> 703 ->
    /// 702 -> zero byte, name complete.
    #[test]
    fn test_read_name_pointer_after_backward_jump() {
        /// Appends a question: one label of `label_len` 'a' bytes, PTR, IN.
        fn push_question(data: &mut Vec<u8>, label_len: usize) {
            data.push(label_len as u8);
            data.extend(vec![b'a'; label_len]);
            data.push(0); // end of the name
            data.extend_from_slice(&[0, 12]); // QTYPE: PTR
            data.extend_from_slice(&[0, 1]); // QCLASS: IN
        }

        let mut data: Vec<u8> = vec![
            0, 0, // ID
            0, 0, // flags: a query
            0, 11, // 11 questions
            0, 1, // 1 answer
            0, 0, 0, 0, // no authorities, no additionals
        ];

        // Questions #1 to #10, 66 bytes each: 12 + 660 = 672.
        for _ in 0..10 {
            push_question(&mut data, 60);
        }
        assert_eq!(data.len(), 672);

        // Question #11, 28 bytes, so that the answer record starts at 700.
        push_question(&mut data, 22);
        assert_eq!(data.len(), 700);

        // Plant the label length inside question #10's label.
        data[640] = 62;

        // The answer record.
        data.extend_from_slice(&[0xC2, 0x80]); // 700: name: pointer to 640
        data.extend_from_slice(&[0x00, 0xC2]); // 702: TYPE, unknown type 194
        data.extend_from_slice(&[0xBE, 0x01]); // 704: CLASS. 703..705 is a pointer to 702
        data.extend_from_slice(&[0, 0, 0, 120]); // TTL
        data.extend_from_slice(&[0, 0]); // RDLENGTH: no RDATA

        // Both pointers point backwards from where they are.
        assert_eq!(u16_from_be_slice(&data[700..702]) ^ 0xC000, 640);
        assert_eq!(u16_from_be_slice(&data[703..705]) ^ 0xC000, 702);

        let incoming = DnsIncoming::new(data, test_interface_id())
            .expect("a name whose pointers all point backwards must parse");
        assert_eq!(incoming.questions().len(), 11);

        // The answer's type is unknown to us, so the record itself is skipped.
        assert_eq!(incoming.answers().len(), 0);
    }

    /// Two pointers at offsets 23 and 25 that target each other (23 -> 25 ->
    /// 23). Both sit below offset 27, where the name starts.
    ///
    /// `follow_pointer` requires each target to be strictly below the
    /// pointer's *own* position. A cycle always contains at least one
    /// non-backward hop, so this rule breaks every cycle.
    #[test]
    fn test_read_name_mutual_pointers_are_rejected() {
        let mut data: Vec<u8> = vec![0, 0, 0x84, 0, 0, 0, 0, 2, 0, 0, 0, 0];

        // Answer #1: the root name, then an unknown type, so its RDATA is skipped.
        data.push(0); // 12: the root name
        data.extend_from_slice(&[0x00, 0xC2]); // 13: TYPE: unknown type 194
        data.extend_from_slice(&[0x00, 0x01]); // 15: CLASS: IN
        data.extend_from_slice(&[0, 0, 0, 120]); // 17: TTL
        data.extend_from_slice(&[0x00, 0x04]); // 21: RDLENGTH
        data.extend_from_slice(&[0xC0, 25]); // 23: RDATA: pointer to 25
        data.extend_from_slice(&[0xC0, 23]); // 25: RDATA: pointer to 23
        assert_eq!(data.len(), 27);

        // Answer #2, whose name points into that RDATA.
        data.extend_from_slice(&[0xC0, 23]); // 27: name: pointer to 23
        data.extend_from_slice(&[0x00, 0xC2, 0x00, 0x01]); // TYPE, CLASS
        data.extend_from_slice(&[0, 0, 0, 120]); // TTL
        data.extend_from_slice(&[0, 0]); // RDLENGTH: no RDATA

        // Every pointer targets an offset below the start of the name at 27.
        assert_eq!(u16_from_be_slice(&data[27..29]) ^ 0xC000, 23);
        assert_eq!(u16_from_be_slice(&data[23..25]) ^ 0xC000, 25);
        assert_eq!(u16_from_be_slice(&data[25..27]) ^ 0xC000, 23);

        assert!(DnsIncoming::new(data, test_interface_id()).is_err());
    }

    /// A label whose read carries the cursor onto a pointer that jumps back to
    /// that same label. Every pointer here points backwards from its own
    /// position, so no comparison of offsets rejects it: the cycle is broken
    /// only by the name growing past [`MAX_NAME_BYTES`].
    #[test]
    fn test_read_name_label_cycle_is_rejected() {
        let mut data: Vec<u8> = vec![0, 0, 0x84, 0, 0, 0, 0, 2, 0, 0, 0, 0];

        // Answer #1, again an unknown type so that its RDATA is skipped.
        data.push(0); // 12: the root name
        data.extend_from_slice(&[0x00, 0xC2]); // 13: TYPE: unknown type 194
        data.extend_from_slice(&[0x00, 0x01]); // 15: CLASS: IN
        data.extend_from_slice(&[0, 0, 0, 120]); // 17: TTL
        data.extend_from_slice(&[0x00, 0x07]); // 21: RDLENGTH
        data.push(0x04); // 23: RDATA: a label of 4 bytes, ending at 28
        data.extend_from_slice(b"aaaa"); // 24
        data.extend_from_slice(&[0xC0, 23]); // 28: RDATA: pointer to 23
        assert_eq!(data.len(), 30);

        // Answer #2, whose name enters the cycle.
        data.extend_from_slice(&[0xC0, 23]); // 30: name: pointer to 23
        data.extend_from_slice(&[0x00, 0xC2, 0x00, 0x01]); // TYPE, CLASS
        data.extend_from_slice(&[0, 0, 0, 120]); // TTL
        data.extend_from_slice(&[0, 0]); // RDLENGTH: no RDATA

        // Reading the label at 23 leaves the cursor on the pointer at 28, which
        // points backwards from 28 and lands back on the label.
        assert_eq!(u16_from_be_slice(&data[28..30]) ^ 0xC000, 23);
        assert_eq!(u16_from_be_slice(&data[30..32]) ^ 0xC000, 23);

        assert!(DnsIncoming::new(data, test_interface_id()).is_err());
    }

    /// A real `_miio._udp.local.` response captured behind an avahi mDNS
    /// reflector (see issue #468). It has 5 answers, one of which is an NSEC
    /// whose Next Domain Name is a compression pointer to its own offset (a
    /// self-reference, offset 121 -> 121). That one record is malformed, but
    /// the other four (PTR, A, SRV, TXT) are fine, and lenient parsers such as
    /// tcpdump decode the whole packet.
    ///
    /// The parser must skip only the malformed NSEC and keep the good records,
    /// rather than discarding the entire message.
    #[test]
    fn test_malformed_nsec_record_is_skipped() {
        let data: Vec<u8> = vec![
            0x00, 0x00, 0x84, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x05, 0x5f,
            0x6d, 0x69, 0x69, 0x6f, 0x04, 0x5f, 0x75, 0x64, 0x70, 0x05, 0x6c, 0x6f, 0x63, 0x61,
            0x6c, 0x00, 0x00, 0x0c, 0x00, 0x01, 0x00, 0x00, 0x00, 0x78, 0x00, 0x24, 0x21, 0x64,
            0x72, 0x65, 0x61, 0x6d, 0x65, 0x2d, 0x76, 0x61, 0x63, 0x75, 0x75, 0x6d, 0x2d, 0x70,
            0x32, 0x30, 0x32, 0x39, 0x5f, 0x6d, 0x69, 0x69, 0x6f, 0x34, 0x34, 0x37, 0x33, 0x30,
            0x35, 0x32, 0x34, 0x37, 0xc0, 0x0c, 0x21, 0x64, 0x72, 0x65, 0x61, 0x6d, 0x65, 0x2d,
            0x76, 0x61, 0x63, 0x75, 0x75, 0x6d, 0x2d, 0x70, 0x32, 0x30, 0x32, 0x39, 0x5f, 0x6d,
            0x69, 0x69, 0x6f, 0x34, 0x34, 0x37, 0x33, 0x30, 0x35, 0x32, 0x34, 0x37, 0x00, 0x00,
            0x2f, 0x80, 0x01, 0x00, 0x00, 0x00, 0x78, 0x00, 0x09, 0xc0, 0x79, 0x00, 0x05, 0x40,
            0x00, 0x00, 0x00, 0x00, 0xc0, 0x4c, 0x00, 0x01, 0x80, 0x01, 0x00, 0x00, 0x00, 0x78,
            0x00, 0x04, 0x0a, 0x2a, 0x02, 0x32, 0xc0, 0x28, 0x00, 0x21, 0x80, 0x01, 0x00, 0x00,
            0x00, 0x78, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0xd4, 0x31, 0xc0, 0x4c, 0xc0, 0x28,
            0x00, 0x10, 0x80, 0x01, 0x00, 0x00, 0x00, 0x78, 0x00, 0x0f, 0x0e, 0x70, 0x61, 0x74,
            0x68, 0x3d, 0x2f, 0x6d, 0x79, 0x64, 0x65, 0x76, 0x69, 0x63, 0x65,
        ];

        // The offending record: the NSEC's Next Domain Name at offset 121 is a
        // pointer to offset 121 (itself).
        assert_eq!(u16_from_be_slice(&data[121..123]) ^ 0xC000, 121);

        let incoming = DnsIncoming::new(data, test_interface_id())
            .expect("one malformed record must not fail the whole packet");

        // Four of the five records survive; only the NSEC is dropped.
        assert_eq!(incoming.answers().len(), 4);
        assert!(
            !incoming
                .answers()
                .iter()
                .any(|r| r.get_type() == RRType::NSEC),
            "the malformed NSEC record must be skipped"
        );
    }

    #[test]
    fn test_unknown_questions_preserve_supported_questions_and_answers() {
        // No enum variant is needed for future question types. Build the wire
        // questions explicitly so this also covers types the writer cannot emit.
        for unknown_type in [64u16, 65, 65400] {
            for unknown_index in 0..3 {
                let mut data = vec![0; 12];
                data[4..6].copy_from_slice(&3u16.to_be_bytes());
                data[6..8].copy_from_slice(&1u16.to_be_bytes());
                let mut known_types = [1u16, 28].iter().copied();
                for index in 0..3 {
                    data.extend_from_slice(b"\x05mixed\x05local\x00");
                    let ty = if index == unknown_index {
                        unknown_type
                    } else {
                        known_types.next().unwrap()
                    };
                    data.extend_from_slice(&ty.to_be_bytes());
                    data.extend_from_slice(&CLASS_IN.to_be_bytes());
                }
                // One known answer after the questions verifies parser alignment.
                data.extend_from_slice(
                    b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x78\x00\x04\xc0\x00\x02\x01",
                );
                let incoming = DnsIncoming::new(data, test_interface_id()).unwrap();
                let types: Vec<_> = incoming
                    .questions()
                    .iter()
                    .map(|q| q.entry.ty)
                    .filter(|ty| matches!(ty, RRType::A | RRType::AAAA))
                    .collect();
                assert_eq!(types, [RRType::A, RRType::AAAA]);
                if unknown_type == 65400 {
                    assert_eq!(incoming.questions().len(), 2);
                }
                assert_eq!(incoming.answers().len(), 1);
                assert_eq!(incoming.answers()[0].get_type(), RRType::A);
            }
        }
    }

    #[test]
    fn test_unknown_question_still_requires_complete_name_type_and_class() {
        let mut data = vec![0; 12];
        data[4..6].copy_from_slice(&1u16.to_be_bytes());
        data.extend_from_slice(b"\x05mixed\x05local\x00");
        data.extend_from_slice(&65400u16.to_be_bytes());
        data.extend_from_slice(&CLASS_IN.to_be_bytes());
        assert!(DnsIncoming::new(data.clone(), test_interface_id())
            .unwrap()
            .questions()
            .is_empty());
        for missing in 1..=4 {
            assert!(
                DnsIncoming::new(data[..data.len() - missing].to_vec(), test_interface_id())
                    .is_err()
            );
        }
    }

    fn test_interface_id() -> InterfaceId {
        InterfaceId {
            name: "test".to_string(),
            index: 1,
        }
    }

    /// The "flags" field of a finished packet.
    fn packet_flags(packet: &DnsOutPacket) -> u16 {
        let bytes = packet.as_bytes();
        u16::from_be_bytes([bytes[2], bytes[3]])
    }

    fn ptr_answer(index: usize) -> DnsPointer {
        DnsPointer::new(
            "_spill._tcp.local.",
            RRType::PTR,
            CLASS_IN,
            4500,
            format!("instance-{index:04}._spill._tcp.local."),
        )
    }

    /// Re-parses each packet and returns the total number of answers found, which
    /// checks the header counts against what each packet actually holds.
    fn parsed_answer_count(packets: &[DnsOutPacket]) -> usize {
        packets
            .iter()
            .map(|packet: &DnsOutPacket| {
                let parsed = DnsIncoming::new(packet.as_bytes().to_vec(), test_interface_id())
                    .expect("each packet must parse on its own");
                assert!(
                    !parsed.answers().is_empty(),
                    "a spilled packet must not be empty"
                );
                parsed.answers().len()
            })
            .sum()
    }

    /// A response too big for one packet spills into more packets. Every record
    /// must survive: before, records that did not fit were silently dropped.
    #[test]
    fn test_dns_outgoing_response_spills_into_packets() {
        const ANSWER_COUNT: usize = 100;

        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
        for i in 0..ANSWER_COUNT {
            out.add_answer_record(ptr_answer(i));
        }

        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert!(
            packets.len() > 1,
            "{} answers should not fit in one packet",
            ANSWER_COUNT
        );

        for packet in &packets {
            assert!(
                packet.size() <= MAX_PKT_DEFAULT,
                "packet of {} bytes exceeds the limit",
                packet.size()
            );

            // A multi-packet response is a series of independent responses: unlike
            // a query's known answers, it does not use the TC bit.
            assert_eq!(packet_flags(packet) & FLAGS_TC, 0);
        }

        assert_eq!(parsed_answer_count(&packets), ANSWER_COUNT);
    }

    /// RFC 6762 section 7.2: a querier sending known answers in more than one
    /// packet sets the TC bit in every packet but the last.
    #[test]
    fn test_dns_outgoing_query_truncation_bit() {
        let mut out = DnsOutgoing::new(FLAGS_QR_QUERY);
        out.add_question("_spill._tcp.local.", RRType::PTR);
        for i in 0..100 {
            out.add_answer_box(Box::new(ptr_answer(i)));
        }

        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert!(
            packets.len() > 1,
            "known answers should not fit in one packet"
        );

        let (last, rest) = packets.split_last().expect("at least one packet");
        for packet in rest {
            assert_ne!(
                packet_flags(packet) & FLAGS_TC,
                0,
                "a packet with more known answers to follow must set TC"
            );
        }
        assert_eq!(
            packet_flags(last) & FLAGS_TC,
            0,
            "the last packet must not set TC"
        );

        // The question goes in the first packet only, and no answer is lost.
        assert_eq!(packets[0].as_bytes()[4..6], 1u16.to_be_bytes());
        for packet in rest.iter().skip(1) {
            assert_eq!(packet.as_bytes()[4..6], [0, 0]);
        }
        assert_eq!(parsed_answer_count(&packets), 100);
    }

    /// RFC 6762 section 17: a record too large for one MTU-sized packet is sent
    /// alone in an oversized packet, rather than dropped. It must be alone, since
    /// a fragmented packet "MUST NOT contain more than one resource record".
    #[test]
    fn test_dns_outgoing_oversized_record_sent_alone() {
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
        out.add_answer_record(ptr_answer(0));
        out.add_answer_record(DnsTxt::new(
            "big._spill._tcp.local.",
            CLASS_IN,
            4500,
            vec![b'x'; 2000],
        ));
        out.add_answer_record(ptr_answer(1));

        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert_eq!(packets.len(), 3, "the big record needs a packet to itself");

        assert!(packets[0].size() <= MAX_PKT_DEFAULT);
        assert!(
            packets[1].size() > MAX_PKT_DEFAULT,
            "the oversized record must not be dropped"
        );
        // Still small enough that the send path will let it out.
        assert!(packets[1].size() <= MAX_PKT_ABSOLUTE_IPV6);
        assert!(packets[2].size() <= MAX_PKT_DEFAULT);

        // One record per packet here, the middle one being the big TXT.
        let parsed = DnsIncoming::new(packets[1].as_bytes().to_vec(), test_interface_id()).unwrap();
        assert_eq!(parsed.answers().len(), 1);
        assert_eq!(parsed.answers()[0].get_name(), "big._spill._tcp.local.");
        assert_eq!(parsed_answer_count(&packets), 3);
    }

    /// A record over the RFC 6762 section 17 ceiling could not go out on the wire
    /// even in a packet of its own, so it is dropped while its neighbors survive.
    #[test]
    fn test_dns_outgoing_record_over_absolute_ceiling_dropped() {
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
        out.add_answer_record(ptr_answer(0));
        out.add_answer_record(DnsTxt::new(
            "huge._spill._tcp.local.",
            CLASS_IN,
            4500,
            vec![b'x'; MAX_PKT_ABSOLUTE_IPV6],
        ));
        out.add_answer_record(ptr_answer(1));

        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        for packet in &packets {
            assert!(
                packet.size() <= MAX_PKT_ABSOLUTE_IPV6,
                "an unsendable packet must never be generated"
            );
        }
        assert_eq!(
            parsed_answer_count(&packets),
            2,
            "only the huge record is dropped"
        );
    }

    /// Authorities and additionals spill too, and stay in their own sections.
    #[test]
    fn test_dns_outgoing_all_sections_spill() {
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
        for i in 0..40 {
            out.add_answer_record(ptr_answer(i));
        }
        for i in 40..80 {
            out.add_authority(Box::new(ptr_answer(i)));
        }
        for i in 80..120 {
            out.add_additional_answer(ptr_answer(i));
        }

        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        assert!(packets.len() > 1);

        let mut answers = 0;
        let mut authorities = 0;
        let mut additionals = 0;
        for packet in &packets {
            assert!(packet.size() <= MAX_PKT_DEFAULT);
            let parsed = DnsIncoming::new(packet.as_bytes().to_vec(), test_interface_id()).unwrap();
            answers += parsed.answers().len();
            authorities += parsed.authorities().len();
            additionals += parsed.additionals().len();
        }

        assert_eq!(answers, 40);
        assert_eq!(authorities, 40);
        assert_eq!(additionals, 40);
    }
    #[test]
    fn test_nsec_encoding_round_trip() {
        use super::DnsRecordExt;

        for (bitmap, types) in [
            (vec![0x40], vec![1]),
            (vec![0, 0, 0, 8], vec![28]),
            (vec![0x40, 0, 0, 8], vec![1, 28]),
        ] {
            let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | super::FLAGS_AA);
            out.add_answer_record(super::DnsNSec::new(
                "negative.local.",
                CLASS_IN | super::CLASS_CACHE_FLUSH,
                120,
                "negative.local.".to_string(),
                bitmap.clone(),
            ));
            let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
            assert_eq!(packets.len(), 1);
            let data = packets[0].as_bytes().to_vec();
            // Owner name, RR header, compressed Next Domain Name, then window 0.
            let rdata_offset = 12 + 16 + 10;
            assert_eq!(
                &data[rdata_offset..rdata_offset + 4],
                &[0xc0, 0x0c, 0, bitmap.len() as u8]
            );
            assert_eq!(&data[rdata_offset + 4..], bitmap.as_slice());
            let incoming = DnsIncoming::new(data, test_interface_id()).unwrap();
            assert_eq!(incoming.answers().len(), 1);
            let record = incoming.answers()[0]
                .any()
                .downcast_ref::<super::DnsNSec>()
                .unwrap();
            assert_eq!(record.next_domain, "negative.local.");
            assert_eq!(record._types(), types);
            assert_eq!(record.get_record().get_ttl(), 120);
        }
    }

    #[test]
    fn test_service_binding_questions_round_trip() {
        let mut out = DnsOutgoing::new(FLAGS_QR_QUERY);
        for ty in [RRType::SVCB, RRType::HTTPS, RRType::AAAA, RRType::A] {
            out.add_question("binding.local.", ty);
        }
        let packets = out.to_packets(MAX_PKT_DEFAULT, IPV6);
        let incoming =
            DnsIncoming::new(packets[0].as_bytes().to_vec(), test_interface_id()).unwrap();
        let types: Vec<_> = incoming.questions().iter().map(|q| q.entry.ty).collect();
        assert_eq!(
            types,
            [RRType::SVCB, RRType::HTTPS, RRType::AAAA, RRType::A]
        );
    }
}
