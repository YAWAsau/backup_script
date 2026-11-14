//! Define `ServiceInfo` to represent a service and its operations.

#[cfg(feature = "logging")]
use crate::log::{debug, trace};
use crate::{
    dns_parser::{DnsIncoming, DnsOutgoing, DnsRecordBox, DnsRecordExt, DnsSrv, RRType, ScopedIp},
    Error, IfKind, InterfaceId, Result,
};
use if_addrs::{IfAddr, Interface};
use std::net::Ipv6Addr;
use std::{
    cmp,
    collections::{HashMap, HashSet},
    fmt,
    net::{IpAddr, Ipv4Addr},
    str::FromStr,
    time::{Duration, Instant},
};

#[cfg(feature = "serde")]
use serde::{Deserialize, Serialize};

/// Default TTL values in seconds
const DNS_HOST_TTL: u32 = 120; // 2 minutes for host records (A, SRV etc) per RFC6762
const DNS_OTHER_TTL: u32 = 4500; // 75 minutes for non-host records (PTR, TXT etc) per RFC6762

/// Represents a network interface.
#[derive(Debug)]
pub(crate) struct MyIntf {
    /// The name of the interface.
    pub(crate) name: String,

    /// Unique index assigned by the OS. Used by IPv6 for its scope_id.
    pub(crate) index: u32,

    /// One interface can have multiple IPv4 addresses and/or multiple IPv6 addresses.
    pub(crate) addrs: HashSet<IfAddr>,

    /// Max byte size of a packet generated for the IPv4 addresses of this interface.
    pub(crate) max_packet_size_v4: usize,

    /// Same as `max_packet_size_v4`, for the IPv6 addresses of this interface.
    pub(crate) max_packet_size_v6: usize,
}

impl MyIntf {
    pub(crate) fn next_ifaddr_v4(&self) -> Option<&IfAddr> {
        self.addrs.iter().find(|a| a.ip().is_ipv4())
    }

    pub(crate) fn next_ifaddr_v6(&self) -> Option<&IfAddr> {
        self.addrs.iter().find(|a| a.ip().is_ipv6())
    }

    /// Max byte size of a packet generated for the given address family.
    pub(crate) fn max_packet_size(&self, is_ipv4: bool) -> usize {
        if is_ipv4 {
            self.max_packet_size_v4
        } else {
            self.max_packet_size_v6
        }
    }
}

impl From<&MyIntf> for InterfaceId {
    fn from(my_intf: &MyIntf) -> Self {
        InterfaceId {
            name: my_intf.name.clone(),
            index: my_intf.index,
        }
    }
}

/// Escapes dots and backslashes in a DNS instance name according to RFC 6763 Section 4.3.
/// - '.' becomes '\.'
/// - '\' becomes '\\'
///
/// Note: `\` itself needs to be escaped in the source code.
///
/// This is required when concatenating the three portions of a Service Instance Name
/// to ensure that literal dots in the instance name are not interpreted as label separators.
fn escape_instance_name(name: &str) -> String {
    let mut result = String::with_capacity(name.len() + 10); // Extra space for escapes

    for ch in name.chars() {
        match ch {
            '.' => {
                result.push('\\');
                result.push('.');
            }
            '\\' => {
                result.push('\\');
                result.push('\\');
            }
            _ => result.push(ch),
        }
    }

    result
}

/// Complete info about a Service Instance.
///
/// We can construct some PTR, one SRV and one TXT record from this info,
/// as well as A (IPv4 Address) and AAAA (IPv6 Address) records.
#[derive(Debug, Clone)]
pub struct ServiceInfo {
    /// Service type and domain: {service-type-name}.{domain}
    /// By default the service-type-name length must be <= 15.
    /// so "_abcdefghijklmno._udp.local." would be valid but "_abcdefghijklmnop._udp.local." is not
    ty_domain: String,

    /// See RFC6763 section 7.1 about "Subtypes":
    /// <https://datatracker.ietf.org/doc/html/rfc6763#section-7.1>
    sub_domain: Option<String>, // <subservice>._sub.<service>.<domain>

    fullname: String, // <instance>.<service>.<domain>
    server: String,   // fully qualified name for service host
    addresses: HashSet<IpAddr>,
    port: u16,
    host_ttl: u32,  // used for SRV and Address records
    other_ttl: u32, // used for PTR and TXT records
    priority: u16,
    weight: u16,
    txt_properties: TxtProperties,
    addr_auto: bool, // Let the system update addresses automatically.

    status: HashMap<u32, ServiceStatus>, // keyed by interface index.

    /// Whether we need to probe names before announcing this service.
    requires_probe: bool,

    /// If set, the service is only exposed on these interfaces
    supported_intfs: Vec<IfKind>,

    /// If true, only link-local addresses are published.
    is_link_local_only: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ServiceStatus {
    Probing,
    Announced,
    Unknown,
}

impl ServiceInfo {
    /// Creates a new service info.
    ///
    /// `ty_domain` is the service type and the domain label, for example "_my-service._udp.local.".
    /// By default the service type length must be <= 15 bytes
    ///
    /// `my_name` is the instance name, without the service type suffix.
    /// It allows dots (`.`) and backslashes (`\`).
    ///
    /// `host_name` is the "host" in the context of DNS. It is used as the "name"
    /// in the address records (i.e. TYPE_A and TYPE_AAAA records). It means that
    /// for the same hostname in the same local network, the service resolves in
    /// the same addresses. Be sure to check it if you see unexpected addresses resolved.
    ///
    /// `properties` can be `None` or key/value string pairs, in a type that
    /// implements [`IntoTxtProperties`] trait. It supports:
    /// - `HashMap<String, String>`
    /// - `Option<HashMap<String, String>>`
    /// - slice of tuple: `&[(K, V)]` where `K` and `V` are [`std::string::ToString`].
    ///
    /// Note: The maximum length of a single property string is `255`, Property that exceed the length are truncated.
    /// > `len(key + value) < u8::MAX`
    ///
    /// `ip` can be one or more IP addresses, in a type that implements
    /// [`AsIpAddrs`] trait. It supports:
    ///
    /// - Single IPv4: `"192.168.0.1"`
    /// - Single IPv6: `"2001:0db8::7334"`
    /// - Multiple IPv4 separated by comma: `"192.168.0.1,192.168.0.2"`
    /// - Multiple IPv6 separated by comma: `"2001:0db8::7334,2001:0db8::7335"`
    /// - A slice of IPv4: `&["192.168.0.1", "192.168.0.2"]`
    /// - A slice of IPv6: `&["2001:0db8::7334", "2001:0db8::7335"]`
    /// - A mix of IPv4 and IPv6: `"192.168.0.1,2001:0db8::7334"`
    /// - All the above formats with [IpAddr] or `String` instead of `&str`.
    ///
    /// The host TTL and other TTL are set to default values.
    pub fn new<Ip: AsIpAddrs, P: IntoTxtProperties>(
        ty_domain: &str,
        my_name: &str,
        host_name: &str,
        ip: Ip,
        port: u16,
        properties: P,
    ) -> Result<Self> {
        let (ty_domain, sub_domain) = split_sub_domain(ty_domain);

        let escaped_name = escape_instance_name(my_name);
        let fullname = format!("{escaped_name}.{ty_domain}");
        let ty_domain = ty_domain.to_string();
        let sub_domain = sub_domain.map(str::to_string);
        let server = normalize_hostname(host_name.to_string());
        let addresses = ip.as_ip_addrs()?;
        let txt_properties = properties.into_txt_properties();

        // RFC6763 section 6.4: https://www.rfc-editor.org/rfc/rfc6763#section-6.4
        // The characters of a key MUST be printable US-ASCII values (0x20-0x7E)
        // [RFC20], excluding '=' (0x3D).
        for prop in txt_properties.iter() {
            let key = prop.key();
            if !key.is_ascii() {
                return Err(Error::Msg(format!(
                    "TXT property key {} is not ASCII",
                    prop.key()
                )));
            }
            if key.contains('=') {
                return Err(Error::Msg(format!(
                    "TXT property key {} contains '='",
                    prop.key()
                )));
            }

            // RFC6763 section 6.1: each TXT record string is prefixed by a
            // single length byte, so it cannot exceed 255 bytes.
            let prop_len = key.len() + prop.val().map_or(0, |v| v.len() + 1);
            if prop_len > u8::MAX as usize {
                return Err(Error::Msg(format!(
                    "TXT property '{}' has length {} bytes, exceeding the 255-byte limit",
                    key, prop_len
                )));
            }
        }

        let this = Self {
            ty_domain,
            sub_domain,
            fullname,
            server,
            addresses,
            port,
            host_ttl: DNS_HOST_TTL,
            other_ttl: DNS_OTHER_TTL,
            priority: 0,
            weight: 0,
            txt_properties,
            addr_auto: false,
            status: HashMap::new(),
            requires_probe: true,
            is_link_local_only: false,
            supported_intfs: vec![IfKind::All],
        };

        Ok(this)
    }

    /// Indicates that the library should automatically
    /// update the addresses of this service, when IP
    /// address(es) are added or removed on the host.
    pub const fn enable_addr_auto(mut self) -> Self {
        self.addr_auto = true;
        self
    }

    /// Returns if the service's addresses will be updated
    /// automatically when the host IP addrs change.
    pub const fn is_addr_auto(&self) -> bool {
        self.addr_auto
    }

    /// Set whether this service info requires name probing for potential name conflicts.
    ///
    /// By default, it is true (i.e. requires probing) for every service info. You
    /// set it to `false` only when you are sure there are no conflicts, or for testing purposes.
    pub fn set_requires_probe(&mut self, enable: bool) {
        self.requires_probe = enable;
    }

    /// Set whether the service is restricted to link-local addresses.
    ///
    /// By default, it is false.
    pub fn set_link_local_only(&mut self, is_link_local_only: bool) {
        self.is_link_local_only = is_link_local_only;
    }

    /// Set the supported interfaces for this service.
    ///
    /// The service will be advertised on the provided interfaces only. When ips are auto-detected
    /// (via 'enable_addr_auto') only addresses on these interfaces will be considered.
    pub fn set_interfaces(&mut self, intfs: Vec<IfKind>) {
        self.supported_intfs = intfs;
    }

    /// Returns whether this service info requires name probing for potential name conflicts.
    ///
    /// By default, it returns true for every service info.
    pub const fn requires_probe(&self) -> bool {
        self.requires_probe
    }

    /// Returns the service type including the domain label.
    ///
    /// For example: "_my-service._udp.local.".
    #[inline]
    pub fn get_type(&self) -> &str {
        &self.ty_domain
    }

    /// Returns the service subtype including the domain label,
    /// if subtype has been defined.
    ///
    /// For example: "_printer._sub._http._tcp.local.".
    #[inline]
    pub const fn get_subtype(&self) -> &Option<String> {
        &self.sub_domain
    }

    /// Returns whether the service type or subtype matches the given name.
    pub(crate) fn matches_type_or_subtype(&self, name: &str) -> bool {
        name == self.get_type() || self.get_subtype().as_ref().is_some_and(|v| v == name)
    }

    /// Returns a reference of the service fullname.
    ///
    /// This is useful, for example, in unregister.
    #[inline]
    pub fn get_fullname(&self) -> &str {
        &self.fullname
    }

    /// Returns the properties from TXT records.
    #[inline]
    pub const fn get_properties(&self) -> &TxtProperties {
        &self.txt_properties
    }

    /// Returns a property for a given `key`, where `key` is
    /// case insensitive.
    ///
    /// Returns `None` if `key` does not exist.
    pub fn get_property(&self, key: &str) -> Option<&TxtProperty> {
        self.txt_properties.get(key)
    }

    /// Returns a property value for a given `key`, where `key` is
    /// case insensitive.
    ///
    /// Returns `None` if `key` does not exist.
    pub fn get_property_val(&self, key: &str) -> Option<Option<&[u8]>> {
        self.txt_properties.get_property_val(key)
    }

    /// Returns a property value string for a given `key`, where `key` is
    /// case insensitive.
    ///
    /// Returns `None` if `key` does not exist.
    pub fn get_property_val_str(&self, key: &str) -> Option<&str> {
        self.txt_properties.get_property_val_str(key)
    }

    /// Returns the service's hostname.
    #[inline]
    pub fn get_hostname(&self) -> &str {
        &self.server
    }

    /// Returns the service's port.
    #[inline]
    pub const fn get_port(&self) -> u16 {
        self.port
    }

    /// Returns the service's addresses
    #[inline]
    pub const fn get_addresses(&self) -> &HashSet<IpAddr> {
        &self.addresses
    }

    /// Returns the service's IPv4 addresses only.
    pub fn get_addresses_v4(&self) -> HashSet<&Ipv4Addr> {
        let mut ipv4_addresses = HashSet::new();

        for ip in &self.addresses {
            if let IpAddr::V4(ipv4) = ip {
                ipv4_addresses.insert(ipv4);
            }
        }

        ipv4_addresses
    }

    /// Returns the service's TTL used for SRV and Address records.
    #[inline]
    pub const fn get_host_ttl(&self) -> u32 {
        self.host_ttl
    }

    /// Returns the service's TTL used for PTR and TXT records.
    #[inline]
    pub const fn get_other_ttl(&self) -> u32 {
        self.other_ttl
    }

    /// Returns the service's priority used in SRV records.
    #[inline]
    pub const fn get_priority(&self) -> u16 {
        self.priority
    }

    /// Returns the service's weight used in SRV records.
    #[inline]
    pub const fn get_weight(&self) -> u16 {
        self.weight
    }

    /// Returns all addresses published
    pub(crate) fn get_addrs_on_my_intf_v4(&self, my_intf: &MyIntf) -> Vec<IpAddr> {
        self.addresses
            .iter()
            .filter(|a| a.is_ipv4() && my_intf.addrs.iter().any(|x| valid_ip_on_intf(a, x)))
            .copied()
            .collect()
    }

    pub(crate) fn get_addrs_on_my_intf_v6(&self, my_intf: &MyIntf) -> Vec<IpAddr> {
        self.addresses
            .iter()
            .filter(|a| a.is_ipv6() && my_intf.addrs.iter().any(|x| valid_ip_on_intf(a, x)))
            .copied()
            .collect()
    }

    /// Returns whether the service info is ready to be resolved.
    pub(crate) fn _is_ready(&self) -> bool {
        let some_missing = self.ty_domain.is_empty()
            || self.fullname.is_empty()
            || self.server.is_empty()
            || self.addresses.is_empty();
        !some_missing
    }

    /// Insert `addr` into service info addresses.
    ///
    /// Returns true if the address is supported, false otherwise.
    pub(crate) fn insert_ipaddr(&mut self, intf: &Interface) -> bool {
        if self.is_address_supported(intf) {
            self.addresses.insert(intf.addr.ip());
            true
        } else {
            trace!(
                "skipping unsupported address {} for service {}",
                intf.addr.ip(),
                self.fullname
            );
            false
        }
    }

    pub(crate) fn remove_ipaddr(&mut self, addr: &IpAddr) {
        self.addresses.remove(addr);
    }

    pub(crate) fn generate_txt(&self) -> Vec<u8> {
        encode_txt(self.get_properties().iter())
    }

    pub(crate) fn _set_port(&mut self, port: u16) {
        self.port = port;
    }

    pub(crate) fn _set_hostname(&mut self, hostname: String) {
        self.server = normalize_hostname(hostname);
    }

    /// Returns true if properties are updated.
    pub(crate) fn _set_properties_from_txt(&mut self, txt: &[u8]) -> bool {
        let properties = decode_txt_unique(txt);
        if self.txt_properties.properties != properties {
            self.txt_properties = TxtProperties { properties };
            true
        } else {
            false
        }
    }

    pub(crate) fn _set_subtype(&mut self, subtype: String) {
        self.sub_domain = Some(subtype);
    }

    /// host_ttl is for SRV and address records
    /// currently only used for testing.
    pub(crate) fn _set_host_ttl(&mut self, ttl: u32) {
        self.host_ttl = ttl;
    }

    /// other_ttl is for PTR and TXT records.
    pub(crate) fn _set_other_ttl(&mut self, ttl: u32) {
        self.other_ttl = ttl;
    }

    pub(crate) fn set_status(&mut self, if_index: u32, status: ServiceStatus) {
        match self.status.get_mut(&if_index) {
            Some(service_status) => {
                *service_status = status;
            }
            None => {
                self.status.entry(if_index).or_insert(status);
            }
        }
    }

    pub(crate) fn get_status(&self, intf: u32) -> ServiceStatus {
        self.status
            .get(&intf)
            .cloned()
            .unwrap_or(ServiceStatus::Unknown)
    }

    /// Consumes self and returns a resolved service, i.e. a lite version of `ServiceInfo`.
    pub fn as_resolved_service(self) -> ResolvedService {
        let addresses: HashSet<ScopedIp> = self.addresses.into_iter().map(|a| a.into()).collect();
        ResolvedService {
            ty_domain: self.ty_domain,
            sub_ty_domain: self.sub_domain,
            fullname: self.fullname,
            host: self.server,
            port: self.port,
            addresses,
            txt_properties: self.txt_properties,
        }
    }

    pub(crate) fn is_address_supported(&self, intf: &Interface) -> bool {
        let interface_supported = self.supported_intfs.iter().any(|i| i.matches(intf));
        let addr = intf.ip();
        let passes_link_local = !self.is_link_local_only
            || match &addr {
                IpAddr::V4(ipv4) => ipv4.is_link_local(),
                IpAddr::V6(ipv6) => is_unicast_link_local(ipv6),
            };
        debug!(
            "matching inserted address {} on intf {}: passes_link_local={}, interface_supported={}",
            addr, addr, passes_link_local, interface_supported
        );
        interface_supported && passes_link_local
    }
}

/// Removes potentially duplicated ".local." at the end of "hostname".
fn normalize_hostname(mut hostname: String) -> String {
    if hostname.ends_with(".local.local.") {
        let new_len = hostname.len() - "local.".len();
        hostname.truncate(new_len);
    }
    hostname
}

/// This trait allows for parsing an input into a set of one or multiple [`Ipv4Addr`].
pub trait AsIpAddrs {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>>;
}

impl<T: AsIpAddrs> AsIpAddrs for &T {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>> {
        (*self).as_ip_addrs()
    }
}

/// Supports one address or multiple addresses separated by `,`.
/// For example: "127.0.0.1,127.0.0.2".
///
/// If the string is empty, will return an empty set.
impl AsIpAddrs for &str {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>> {
        let mut addrs = HashSet::new();

        if !self.is_empty() {
            let iter = self.split(',').map(str::trim).map(IpAddr::from_str);
            for addr in iter {
                let addr = addr.map_err(|err| Error::ParseIpAddr(err.to_string()))?;
                addrs.insert(addr);
            }
        }

        Ok(addrs)
    }
}

impl AsIpAddrs for String {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>> {
        self.as_str().as_ip_addrs()
    }
}

/// Support slice. Example: &["127.0.0.1", "127.0.0.2"]
impl<I: AsIpAddrs> AsIpAddrs for &[I] {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>> {
        let mut addrs = HashSet::new();

        for result in self.iter().map(I::as_ip_addrs) {
            addrs.extend(result?);
        }

        Ok(addrs)
    }
}

/// Optimization for zero sized/empty values, as `()` will never take up any space or evaluate to
/// anything, helpful in contexts where we just want an empty value.
impl AsIpAddrs for () {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>> {
        Ok(HashSet::new())
    }
}

impl AsIpAddrs for std::net::IpAddr {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>> {
        let mut ips = HashSet::new();
        ips.insert(*self);

        Ok(ips)
    }
}

impl AsIpAddrs for Box<dyn AsIpAddrs> {
    fn as_ip_addrs(&self) -> Result<HashSet<IpAddr>> {
        self.as_ref().as_ip_addrs()
    }
}

/// Represents properties in a TXT record.
///
/// The key string of a property is case insensitive, and only
/// one [`TxtProperty`] is stored for the same key.
///
/// [RFC 6763](https://www.rfc-editor.org/rfc/rfc6763#section-6.4):
/// "A given key SHOULD NOT appear more than once in a TXT record."
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(Deserialize, Serialize))]
#[cfg_attr(feature = "serde", serde(transparent))]
pub struct TxtProperties {
    // Use `Vec` instead of `HashMap` to keep the order of insertions.
    properties: Vec<TxtProperty>,
}

impl Default for TxtProperties {
    fn default() -> Self {
        TxtProperties::new()
    }
}

impl TxtProperties {
    pub fn new() -> Self {
        TxtProperties {
            properties: Vec::new(),
        }
    }

    /// Returns an iterator for all properties.
    pub fn iter(&self) -> impl Iterator<Item = &TxtProperty> {
        self.properties.iter()
    }

    /// Returns the number of properties.
    pub fn len(&self) -> usize {
        self.properties.len()
    }

    /// Returns if the properties are empty.
    pub fn is_empty(&self) -> bool {
        self.properties.is_empty()
    }

    /// Returns a property for a given `key`, where `key` is
    /// case insensitive.
    pub fn get(&self, key: &str) -> Option<&TxtProperty> {
        let key = key.to_lowercase();
        self.properties
            .iter()
            .find(|&prop| prop.key.to_lowercase() == key)
    }

    /// Returns a property value for a given `key`, where `key` is
    /// case insensitive.
    ///
    /// Returns `None` if `key` does not exist.
    /// Returns `Some(Option<&u8>)` for its value.
    pub fn get_property_val(&self, key: &str) -> Option<Option<&[u8]>> {
        self.get(key).map(|x| x.val())
    }

    /// Returns a property value string for a given `key`, where `key` is
    /// case insensitive.
    ///
    /// Returns `None` if `key` does not exist.
    /// Returns `Some("")` if its value is `None` or is empty.
    pub fn get_property_val_str(&self, key: &str) -> Option<&str> {
        self.get(key).map(|x| x.val_str())
    }

    /// Consumes properties and returns a hashmap, where the keys are the properties keys.
    ///
    /// If a property value is empty, return an empty string (because RFC 6763 allows empty values).
    /// If a property value is non-empty but not valid UTF-8, skip the property and log a message.
    pub fn into_property_map_str(self) -> HashMap<String, String> {
        self.properties
            .into_iter()
            .filter_map(|property| {
                let val_string = property.val.map_or(Some(String::new()), |val| {
                    String::from_utf8(val)
                        .map_err(|e| {
                            debug!("Property value contains invalid UTF-8: {e}");
                        })
                        .ok()
                })?;
                Some((property.key, val_string))
            })
            .collect()
    }
}

impl fmt::Display for TxtProperties {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let delimiter = ", ";
        let props: Vec<String> = self.properties.iter().map(|p| p.to_string()).collect();
        write!(f, "({})", props.join(delimiter))
    }
}

impl From<&[u8]> for TxtProperties {
    fn from(txt: &[u8]) -> Self {
        let properties = decode_txt_unique(txt);
        TxtProperties { properties }
    }
}

/// Represents a property in a TXT record.
#[derive(Clone, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(Deserialize, Serialize))]
pub struct TxtProperty {
    /// The name of the property. The original cases are kept.
    key: String,

    /// RFC 6763 says values are bytes, not necessarily UTF-8.
    /// It is also possible that there is no value, in which case
    /// the key is a boolean key.
    #[cfg_attr(feature = "serde", serde(rename = "value"))]
    val: Option<Vec<u8>>,
}

impl TxtProperty {
    /// Returns the key of a property.
    pub fn key(&self) -> &str {
        &self.key
    }

    /// Returns the value of a property, which could be `None`.
    ///
    /// To obtain a `&str` of the value, use `val_str()` instead.
    pub fn val(&self) -> Option<&[u8]> {
        self.val.as_deref()
    }

    /// Returns the value of a property as str.
    pub fn val_str(&self) -> &str {
        self.val
            .as_ref()
            .map_or("", |v| std::str::from_utf8(&v[..]).unwrap_or_default())
    }
}

/// Supports constructing from a tuple.
impl<K, V> From<&(K, V)> for TxtProperty
where
    K: ToString,
    V: ToString,
{
    fn from(prop: &(K, V)) -> Self {
        Self {
            key: prop.0.to_string(),
            val: Some(prop.1.to_string().into_bytes()),
        }
    }
}

impl<K, V> From<(K, V)> for TxtProperty
where
    K: ToString,
    V: AsRef<[u8]>,
{
    fn from(prop: (K, V)) -> Self {
        Self {
            key: prop.0.to_string(),
            val: Some(prop.1.as_ref().into()),
        }
    }
}

/// Support a property that has no value.
impl From<&str> for TxtProperty {
    fn from(key: &str) -> Self {
        Self {
            key: key.to_string(),
            val: None,
        }
    }
}

impl fmt::Display for TxtProperty {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}={}", self.key, self.val_str())
    }
}

/// Mimic the default debug output for a struct, with a twist:
/// - If self.var is UTF-8, will output it as a string in double quotes.
/// - If self.var is not UTF-8, will output its bytes as in hex.
impl fmt::Debug for TxtProperty {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let val_string = self.val.as_ref().map_or_else(
            || "None".to_string(),
            |v| {
                std::str::from_utf8(&v[..]).map_or_else(
                    |_| format!("Some({})", u8_slice_to_hex(&v[..])),
                    |s| format!("Some(\"{s}\")"),
                )
            },
        );

        write!(
            f,
            "TxtProperty {{key: \"{}\", val: {}}}",
            self.key, val_string,
        )
    }
}

const HEX_TABLE: [char; 16] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
];

/// Create a hex string from `slice`, with a "0x" prefix.
///
/// For example, [1u8, 2u8] -> "0x0102"
fn u8_slice_to_hex(slice: &[u8]) -> String {
    let mut hex = String::with_capacity(slice.len() * 2 + 2);
    hex.push_str("0x");
    for b in slice {
        hex.push(HEX_TABLE[(b >> 4) as usize]);
        hex.push(HEX_TABLE[(b & 0x0F) as usize]);
    }
    hex
}

/// This trait allows for converting inputs into [`TxtProperties`].
pub trait IntoTxtProperties {
    fn into_txt_properties(self) -> TxtProperties;
}

impl IntoTxtProperties for HashMap<String, String> {
    fn into_txt_properties(mut self) -> TxtProperties {
        let properties = self
            .drain()
            .map(|(key, val)| TxtProperty {
                key,
                val: Some(val.into_bytes()),
            })
            .collect();
        TxtProperties { properties }
    }
}

/// Mainly for backward compatibility.
impl IntoTxtProperties for Option<HashMap<String, String>> {
    fn into_txt_properties(self) -> TxtProperties {
        self.map_or_else(
            || TxtProperties {
                properties: Vec::new(),
            },
            |h| h.into_txt_properties(),
        )
    }
}

/// Support Vec like `[("k1", "v1"), ("k2", "v2")]`.
impl<'a, T: 'a> IntoTxtProperties for &'a [T]
where
    TxtProperty: From<&'a T>,
{
    fn into_txt_properties(self) -> TxtProperties {
        let mut properties = Vec::new();
        let mut keys = HashSet::new();
        for t in self.iter() {
            let prop = TxtProperty::from(t);
            let key = prop.key.to_lowercase();
            if keys.insert(key) {
                // Only push a new entry if the key did not exist.
                //
                // RFC 6763: https://www.rfc-editor.org/rfc/rfc6763#section-6.4
                //
                // "If a client receives a TXT record containing the same key more than
                //    once, then the client MUST silently ignore all but the first
                //    occurrence of that attribute. "
                properties.push(prop);
            }
        }
        TxtProperties { properties }
    }
}

impl IntoTxtProperties for Vec<TxtProperty> {
    fn into_txt_properties(self) -> TxtProperties {
        TxtProperties { properties: self }
    }
}

// Convert from properties key/value pairs to DNS TXT record content
fn encode_txt<'a>(properties: impl Iterator<Item = &'a TxtProperty>) -> Vec<u8> {
    let mut bytes = Vec::new();
    for prop in properties {
        let mut s = prop.key.clone().into_bytes();
        if let Some(v) = &prop.val {
            s.extend(b"=");
            s.extend(v);
        }

        debug_assert!(
            s.len() <= u8::MAX as usize,
            "TXT property '{}' exceeds 255 bytes; should have been validated in ServiceInfo::new()",
            prop.key
        );
        s.truncate(u8::MAX as usize);
        let sz: u8 = s.len() as u8;

        // TXT uses (Length,Value) format for each property,
        // i.e. the first byte is the length.
        bytes.push(sz);
        bytes.extend(s);
    }
    if bytes.is_empty() {
        bytes.push(0);
    }
    bytes
}

// Convert from DNS TXT record content to key/value pairs
pub(crate) fn decode_txt(txt: &[u8]) -> Vec<TxtProperty> {
    let mut properties = Vec::new();
    let mut offset = 0;
    while offset < txt.len() {
        let length = txt[offset] as usize;
        if length == 0 {
            break; // reached the end
        }
        offset += 1; // move over the length byte

        let offset_end = offset + length;
        if offset_end > txt.len() {
            debug!("DNS TXT record contains invalid data: Size given for property would be out of range. (offset={}, length={}, offset_end={}, record length={})", offset, length, offset_end, txt.len());
            break; // Skipping the rest of the record content, as the size for this property would already be out of range.
        }
        let kv_bytes = &txt[offset..offset_end];

        // split key and val using the first `=`
        let (k, v) = kv_bytes.iter().position(|&x| x == b'=').map_or_else(
            || (kv_bytes.to_vec(), None),
            |idx| (kv_bytes[..idx].to_vec(), Some(kv_bytes[idx + 1..].to_vec())),
        );

        // Make sure the key can be stored in UTF-8.
        match String::from_utf8(k) {
            Ok(k_string) => {
                properties.push(TxtProperty {
                    key: k_string,
                    val: v,
                });
            }
            Err(e) => debug!("failed to convert to String from key: {}", e),
        }

        offset += length;
    }

    properties
}

fn decode_txt_unique(txt: &[u8]) -> Vec<TxtProperty> {
    let mut properties = decode_txt(txt);

    // Remove duplicated keys and retain only the first appearance
    // of each key.
    let mut keys = HashSet::new();
    properties.retain(|p| {
        let key = p.key().to_lowercase();
        keys.insert(key) // returns True if key is new.
    });
    properties
}

/// Returns true if `addr` is in the same network of `intf`.
pub(crate) fn valid_ip_on_intf(addr: &IpAddr, if_addr: &IfAddr) -> bool {
    match (addr, if_addr) {
        (IpAddr::V4(addr), IfAddr::V4(if_v4)) => {
            let netmask = u32::from(if_v4.netmask);
            let intf_net = u32::from(if_v4.ip) & netmask;
            let addr_net = u32::from(*addr) & netmask;
            addr_net == intf_net
        }
        (IpAddr::V6(addr), IfAddr::V6(if_v6)) => {
            let netmask = u128::from(if_v6.netmask);
            let intf_net = u128::from(if_v6.ip) & netmask;
            let addr_net = u128::from(*addr) & netmask;
            addr_net == intf_net
        }
        _ => false,
    }
}

/// A probing for a particular name.
#[derive(Debug)]
pub(crate) struct Probe {
    /// All records probing for the same name.
    pub(crate) records: Vec<DnsRecordBox>,

    /// The fullnames of services that are probing these records.
    /// These are the original service names, will not change per conflicts.
    pub(crate) waiting_services: HashSet<String>,

    /// The time (T) to send the first query .
    pub(crate) start_time: Instant,

    /// The time to send the next (including the first) query.
    pub(crate) next_send: Instant,
}

impl Probe {
    pub(crate) fn new(start_time: Instant) -> Self {
        // RFC 6762: https://datatracker.ietf.org/doc/html/rfc6762#section-8.1:
        //
        // "250 ms after the first query, the host should send a second; then,
        //   250 ms after that, a third.  If, by 250 ms after the third probe, no
        //   conflicting Multicast DNS responses have been received, the host may
        //   move to the next step, announcing. "
        let next_send = start_time;

        Self {
            records: Vec::new(),
            waiting_services: HashSet::new(),
            start_time,
            next_send,
        }
    }

    /// Add a new record with the same probing name in a sorted order.
    pub(crate) fn insert_record(&mut self, record: DnsRecordBox) {
        /*
        RFC 6762: https://datatracker.ietf.org/doc/html/rfc6762#section-8.2.1

        " The records are sorted using the same lexicographical order as
        described above, that is, if the record classes differ, the record
        with the lower class number comes first.  If the classes are the same
        but the rrtypes differ, the record with the lower rrtype number comes
        first."
         */
        let insert_position = self
            .records
            .binary_search_by(
                |existing| match existing.get_class().cmp(&record.get_class()) {
                    std::cmp::Ordering::Equal => existing.get_type().cmp(&record.get_type()),
                    other => other,
                },
            )
            .unwrap_or_else(|pos| pos);

        self.records.insert(insert_position, record);
    }

    /// Compares with `incoming` records. Postpone probe and retry if we yield.
    pub(crate) fn tiebreaking(&mut self, msg: &DnsIncoming, probe_name: &str) {
        let now = Instant::now();

        // Only do tiebreaking if probe already started.
        // This check also helps avoid redo tiebreaking if start time
        // was postponed.
        if self.start_time >= now {
            return;
        }

        let incoming: Vec<_> = msg
            .authorities()
            .iter()
            .filter(|r| r.get_name() == probe_name)
            .collect();
        /*
        RFC 6762 section 8.2: https://datatracker.ietf.org/doc/html/rfc6762#section-8.2
        ...
        if the host finds that its own data is lexicographically later, it
        simply ignores the other host's probe.  If the host finds that its
        own data is lexicographically earlier, then it defers to the winning
        host by waiting one second, and then begins probing for this record
        again.
        */
        let min_len = self.records.len().min(incoming.len());

        // Compare elements up to the length of the shorter vector
        let mut cmp_result = cmp::Ordering::Equal;
        for (i, incoming_record) in incoming.iter().enumerate().take(min_len) {
            match self.records[i].compare(incoming_record.as_ref()) {
                cmp::Ordering::Equal => continue,
                other => {
                    cmp_result = other;
                    break; // exit loop on first difference
                }
            }
        }

        if cmp_result == cmp::Ordering::Equal {
            // If all compared records are equal, compare the lengths of the records.
            cmp_result = self.records.len().cmp(&incoming.len());
        }

        match cmp_result {
            cmp::Ordering::Less => {
                debug!("tiebreaking '{probe_name}': LOST, will wait for one second",);
                self.start_time = now + Duration::from_millis(1000); // wait and restart.
                self.next_send = now + Duration::from_millis(1000);
            }
            ordering => {
                debug!("tiebreaking '{probe_name}': {:?}", ordering);
            }
        }
    }

    pub(crate) fn update_next_send(&mut self, now: Instant) {
        self.next_send = now + Duration::from_millis(250);
    }

    /// Returns whether this probe is finished.
    pub(crate) fn expired(&self, now: Instant) -> bool {
        // The 2nd query is T + 250ms, the 3rd query is T + 500ms,
        // The expire time is T + 750ms
        now >= self.start_time + Duration::from_millis(750)
    }
}

/// DNS records of all the registered services.
pub(crate) struct DnsRegistry {
    /// keyed by the name of all related DNS records.
    /*
     When a host is probing for a group of related records with the same
    name (e.g., the SRV and TXT record describing a DNS-SD service), only
    a single question need be placed in the Question Section, since query
    type "ANY" (255) is used, which will elicit answers for all records
    with that name.  However, for tiebreaking to work correctly in all
    cases, the Authority Section must contain *all* the records and
    proposed rdata being probed for uniqueness.
     */
    pub(crate) probing: HashMap<String, Probe>,

    /// Already done probing, or no need to probe.
    /// Keyed by DNS record name.
    pub(crate) active: HashMap<String, Vec<DnsRecordBox>>,

    /// timers of the newly added probes.
    pub(crate) new_timers: Vec<Instant>,

    /// Mapping from original names to new names.
    pub(crate) name_changes: HashMap<String, String>,

    /// RFC 6762 section 6: the last time (in millis) each record was multicast
    /// on this interface's IPv4 group, keyed by the record's identity
    /// (name + type + rdata). Used to enforce the per-record, per-interface
    /// one-second rate limit.
    ///
    /// IPv4 and IPv6 are tracked separately: a single interface (`if_index`)
    /// carries both address families, but they are distinct multicast groups
    /// (`224.0.0.251` and `ff02::fb`) reaching potentially different listeners,
    /// so sending a record on one group must not throttle it on the other.
    pub(crate) last_multicast_v4: HashMap<String, Instant>,

    /// Same as [`Self::last_multicast_v4`] but for this interface's IPv6 group.
    pub(crate) last_multicast_v6: HashMap<String, Instant>,
}

impl DnsRegistry {
    pub(crate) fn new() -> Self {
        Self {
            probing: HashMap::new(),
            active: HashMap::new(),
            new_timers: Vec::new(),
            name_changes: HashMap::new(),
            last_multicast_v4: HashMap::new(),
            last_multicast_v6: HashMap::new(),
        }
    }

    /// Enforces the RFC 6762 section 6 multicast rate limit on `out`.
    ///
    /// A responder MUST NOT multicast a record on a given interface until at
    /// least one second has elapsed since the last time that record was
    /// multicast on that particular interface.
    ///
    /// `is_ipv4` selects the per-family bucket: the IPv4 and IPv6 groups on one
    /// interface are throttled independently (see [`Self::last_multicast_v4`]).
    ///
    /// Drops from `out` any answer or additional record that was multicast within the
    /// last second, and records `now` as the last-multicast time for the records kept.
    ///
    /// This must NOT be applied to probe queries, legacy unicast responses, or
    /// goodbye packets, which are exempt from the rate limit.
    pub(crate) fn apply_multicast_rate_limit(
        &mut self,
        out: &mut DnsOutgoing,
        now: Instant,
        is_ipv4: bool,
    ) {
        let last_multicast = if is_ipv4 {
            &mut self.last_multicast_v4
        } else {
            &mut self.last_multicast_v6
        };

        // Prune stale entries so the map stays bounded across name changes;
        // any record older than the one-second window is irrelevant now.
        last_multicast.retain(|_, last| {
            now.saturating_duration_since(*last)
                < Duration::from_millis(MULTICAST_RATE_LIMIT_MILLIS)
        });

        out.retain_answers(|record| keep_after_rate_limit(last_multicast, record, now));

        // Only touch additionals if an answer survived.
        if out.answers_count() > 0 {
            out.retain_additionals(|record| keep_after_rate_limit(last_multicast, record, now));
        }
    }

    /// Returns the renamed name if a name change exists, otherwise returns the original name.
    pub(crate) fn resolve_name<'a>(&'a self, name: &'a str) -> &'a str {
        match self.name_changes.get(name) {
            Some(new_name) => new_name,
            None => name,
        }
    }

    pub(crate) fn is_probing_done<T>(
        &mut self,
        answer: &T,
        service_name: &str,
        start_time: Instant,
    ) -> bool
    where
        T: DnsRecordExt + Send + 'static,
    {
        if let Some(active_records) = self.active.get(answer.get_name()) {
            for record in active_records.iter() {
                if answer.matches(record.as_ref()) {
                    debug!(
                        "found active record {} {}",
                        answer.get_type(),
                        answer.get_name(),
                    );
                    return true;
                }
            }
        }

        let probe = self
            .probing
            .entry(answer.get_name().to_string())
            .or_insert_with(|| {
                debug!("new probe of {}", answer.get_name());
                Probe::new(start_time)
            });

        self.new_timers.push(probe.next_send);

        for record in probe.records.iter() {
            if answer.matches(record.as_ref()) {
                debug!(
                    "found existing record {} in probe of '{}'",
                    answer.get_type(),
                    answer.get_name(),
                );
                probe.waiting_services.insert(service_name.to_string());
                return false; // Found existing probe for the same record.
            }
        }

        debug!(
            "insert record {} into probe of {}",
            answer.get_type(),
            answer.get_name(),
        );
        probe.insert_record(answer.clone_box());
        probe.waiting_services.insert(service_name.to_string());

        false
    }

    /// check all records in "probing" and "active":
    /// if the record is SRV, and hostname is set to original, remove it.
    /// and create a new SRV with "host" set to "new_name" and put into "probing".
    ///
    /// Returns true if a probe was (re)started at `probe_time`, i.e. the caller
    /// needs a timer at `probe_time`.
    pub(crate) fn update_hostname(
        &mut self,
        original: &str,
        new_name: &str,
        probe_time: Instant,
    ) -> bool {
        let mut found_records = Vec::new();
        let mut new_timer_added = false;

        for probe in self.probing.values_mut() {
            probe.records.retain(|record| {
                if record.get_type() == RRType::SRV {
                    if let Some(srv) = record.any().downcast_ref::<DnsSrv>() {
                        if srv.host() == original {
                            let mut new_record = srv.clone();
                            new_record.set_host(new_name.to_string());
                            found_records.push(new_record);
                            return false;
                        }
                    }
                }
                true
            });
        }

        for records in self.active.values_mut() {
            records.retain(|record| {
                if record.get_type() == RRType::SRV {
                    if let Some(srv) = record.any().downcast_ref::<DnsSrv>() {
                        if srv.host() == original {
                            let mut new_record = srv.clone();
                            new_record.set_host(new_name.to_string());
                            found_records.push(new_record);
                            return false;
                        }
                    }
                }
                true
            });
        }

        for record in found_records {
            let probe = match self.probing.get_mut(record.get_name()) {
                Some(p) => {
                    // Restart this probe. `next_send` must be reset as well.
                    p.start_time = probe_time;
                    p.next_send = probe_time;
                    new_timer_added = true;
                    p
                }
                None => {
                    let new_probe = self
                        .probing
                        .entry(record.get_name().to_string())
                        .or_insert_with(|| Probe::new(probe_time));
                    new_timer_added = true;
                    new_probe
                }
            };

            debug!(
                "insert record {} with new hostname {new_name} into probe for: {}",
                record.get_type(),
                record.get_name()
            );
            probe.insert_record(record.boxed());
        }

        new_timer_added
    }
}

/// RFC 6762 section 6 per-record, per-interface multicast rate-limit window:
/// a record must not be re-multicast until at least this many millis have
/// elapsed since it was last multicast on that interface.
pub(crate) const MULTICAST_RATE_LIMIT_MILLIS: u64 = 1000;

/// Returns whether `record` may still be multicast under the RFC 6762 section 6
/// rate limit, updating `last_multicast` to `now` when it is kept.
fn keep_after_rate_limit(
    last_multicast: &mut HashMap<String, Instant>,
    record: &DnsRecordBox,
    now: Instant,
) -> bool {
    let key = rate_limit_key(record);
    match last_multicast.get(&key) {
        Some(last)
            if now.saturating_duration_since(*last)
                < Duration::from_millis(MULTICAST_RATE_LIMIT_MILLIS) =>
        {
            false
        }
        _ => {
            last_multicast.insert(key, now);
            true
        }
    }
}

/// Builds the identity key for a record used by the RFC 6762 section 6
/// multicast rate limit: name (case-insensitive) + type + rdata. TTL and the
/// cache-flush bit are intentionally excluded, so the same logical record maps
/// to a single key regardless of the TTL it is sent with.
fn rate_limit_key(record: &DnsRecordBox) -> String {
    format!(
        "{}-{}-{}",
        record.get_name().to_lowercase(),
        record.get_type(),
        record.rdata_print(),
    )
}

/// Returns a tuple of (service_type_domain, optional_sub_domain)
pub(crate) fn split_sub_domain(domain: &str) -> (&str, Option<&str>) {
    if let Some((_, ty_domain)) = domain.rsplit_once("._sub.") {
        (ty_domain, Some(domain))
    } else {
        (domain, None)
    }
}

/// Returns true if `addr` is a unicast link-local IPv6 address.
/// Replicates the logic from `std::net::Ipv6Addr::is_unicast_link_local()`, which is not
/// stable on the current mdns-sd Rust version (1.71.0).
///
/// https://github.com/rust-lang/rust/blob/9fc6b43126469e3858e2fe86cafb4f0fd5068869/library/core/src/net/ip_addr.rs#L1684
pub(crate) fn is_unicast_link_local(addr: &Ipv6Addr) -> bool {
    (addr.segments()[0] & 0xffc0) == 0xfe80
}

/// Represents a resolved service as a plain data struct.
/// This is from a client (i.e. querier) point of view.
#[derive(Clone, Debug)]
#[cfg_attr(feature = "serde", derive(Deserialize, Serialize))]
#[non_exhaustive]
pub struct ResolvedService {
    /// Service type and domain. For example, "_http._tcp.local."
    pub ty_domain: String,

    /// Optional service subtype and domain.
    ///
    /// See RFC6763 section 7.1 about "Subtypes":
    /// <https://datatracker.ietf.org/doc/html/rfc6763#section-7.1>
    /// For example, "_printer._sub._http._tcp.local."
    pub sub_ty_domain: Option<String>,

    /// Full name of the service. For example, "my-service._http._tcp.local."
    pub fullname: String,

    /// Host name of the service. For example, "my-server1.local."
    pub host: String,

    /// Port of the service. I.e. TCP or UDP port.
    pub port: u16,

    /// Addresses of the service. IPv4 or IPv6 addresses.
    pub addresses: HashSet<ScopedIp>,

    /// Properties of the service, decoded from TXT record.
    pub txt_properties: TxtProperties,
}

impl ResolvedService {
    /// Returns true if the service data is valid, i.e. ready to be used.
    pub fn is_valid(&self) -> bool {
        let some_missing = self.ty_domain.is_empty()
            || self.fullname.is_empty()
            || self.host.is_empty()
            || self.addresses.is_empty();
        !some_missing
    }

    #[inline]
    pub const fn get_subtype(&self) -> &Option<String> {
        &self.sub_ty_domain
    }

    #[inline]
    pub fn get_fullname(&self) -> &str {
        &self.fullname
    }

    #[inline]
    pub fn get_hostname(&self) -> &str {
        &self.host
    }

    #[inline]
    pub fn get_port(&self) -> u16 {
        self.port
    }

    #[inline]
    pub fn get_addresses(&self) -> &HashSet<ScopedIp> {
        &self.addresses
    }

    pub fn get_addresses_v4(&self) -> HashSet<Ipv4Addr> {
        self.addresses
            .iter()
            .filter_map(|ip| match ip {
                ScopedIp::V4(ipv4) => Some(*ipv4.addr()),
                _ => None,
            })
            .collect()
    }

    #[inline]
    pub fn get_properties(&self) -> &TxtProperties {
        &self.txt_properties
    }

    #[inline]
    pub fn get_property(&self, key: &str) -> Option<&TxtProperty> {
        self.txt_properties.get(key)
    }

    pub fn get_property_val(&self, key: &str) -> Option<Option<&[u8]>> {
        self.txt_properties.get_property_val(key)
    }

    pub fn get_property_val_str(&self, key: &str) -> Option<&str> {
        self.txt_properties.get_property_val_str(key)
    }
}

#[cfg(test)]
mod tests {
    use super::{
        decode_txt, encode_txt, u8_slice_to_hex, DnsRegistry, Instant, Probe, ServiceInfo,
        TxtProperty,
    };
    use crate::dns_parser::{
        DnsOutgoing, DnsPointer, DnsRecordExt, DnsSrv, RRType, CLASS_CACHE_FLUSH, CLASS_IN,
        FLAGS_QR_RESPONSE,
    };
    use crate::{IfKind, IfPredicate};
    use if_addrs::{IfAddr, IfOperStatus, Ifv4Addr, Ifv6Addr, Interface};
    use std::net::{Ipv4Addr, Ipv6Addr};
    use std::time::Duration;

    /// RFC 6762 section 6: the same record must not be multicast on an
    /// interface more than once per second, but is allowed again after a
    /// second has elapsed.
    #[test]
    fn test_multicast_rate_limit() {
        let mut registry = DnsRegistry::new();

        let build_out = || {
            let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
            out.add_answer_record(DnsPointer::new(
                "_test._tcp.local.",
                RRType::PTR,
                CLASS_IN,
                4500,
                "inst._test._tcp.local.".to_string(),
            ));
            out
        };

        let now = Instant::now();

        // First multicast at `now`: the record passes through.
        let mut out = build_out();
        registry.apply_multicast_rate_limit(&mut out, now, true);
        assert_eq!(out.answers_count(), 1);

        // Again 500ms later: the record is throttled (dropped).
        let mut out = build_out();
        registry.apply_multicast_rate_limit(&mut out, now + Duration::from_millis(500), true);
        assert_eq!(out.answers_count(), 0);

        // Exactly 1 second after the first send: allowed again.
        let mut out = build_out();
        registry.apply_multicast_rate_limit(&mut out, now + Duration::from_millis(1000), true);
        assert_eq!(out.answers_count(), 1);
    }

    /// A single interface carries both IPv4 and IPv6, but they are distinct
    /// multicast groups reaching different listeners, so the one-second limit
    /// is tracked per family: multicasting a record on IPv4 must NOT throttle
    /// the same record on IPv6 (and vice versa). Otherwise the shared PTR/SRV/
    /// TXT records would be stripped from whichever family is sent second.
    #[test]
    fn test_multicast_rate_limit_per_family() {
        let mut registry = DnsRegistry::new();

        let build_out = || {
            let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
            out.add_answer_record(DnsPointer::new(
                "_test._tcp.local.",
                RRType::PTR,
                CLASS_IN,
                4500,
                "inst._test._tcp.local.".to_string(),
            ));
            out
        };

        let now = Instant::now();

        // Multicast the record on IPv4: passes through.
        let mut out = build_out();
        registry.apply_multicast_rate_limit(&mut out, now, true);
        assert_eq!(out.answers_count(), 1);

        // The same record on IPv6 immediately after: must still pass, because
        // the IPv6 group has its own bucket.
        let mut out = build_out();
        registry.apply_multicast_rate_limit(&mut out, now, false);
        assert_eq!(out.answers_count(), 1);

        // A second IPv4 send within the window is still throttled, confirming
        // the IPv6 send did not reset (or get charged to) the IPv4 bucket.
        let mut out = build_out();
        registry.apply_multicast_rate_limit(&mut out, now + Duration::from_millis(500), true);
        assert_eq!(out.answers_count(), 0);

        // Likewise a second IPv6 send within the window is throttled.
        let mut out = build_out();
        registry.apply_multicast_rate_limit(&mut out, now + Duration::from_millis(500), false);
        assert_eq!(out.answers_count(), 0);
    }

    /// When every answer is throttled the packet is not sent, so any surviving
    /// additional record must NOT be stamped as multicast — otherwise a later
    /// answer for that same record would be wrongly throttled even though it was
    /// never put on the wire.
    #[test]
    fn test_multicast_rate_limit_additionals_not_stamped_without_answer() {
        let mut registry = DnsRegistry::new();

        let ptr_answer = || {
            DnsPointer::new(
                "_test._tcp.local.",
                RRType::PTR,
                CLASS_IN,
                4500,
                "inst._test._tcp.local.".to_string(),
            )
        };
        let extra = || {
            DnsPointer::new(
                "_other._tcp.local.",
                RRType::PTR,
                CLASS_IN,
                4500,
                "inst._other._tcp.local.".to_string(),
            )
        };

        let now = Instant::now();

        // Send the PTR answer once so it is throttled going forward.
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
        out.add_answer_record(ptr_answer());
        registry.apply_multicast_rate_limit(&mut out, now, true);
        assert_eq!(out.answers_count(), 1);

        // 100ms later: PTR answer is throttled, and `extra` rides along as an
        // additional. With no answer surviving, nothing is sent.
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
        out.add_answer_record(ptr_answer());
        out.add_additional_answer(extra());
        registry.apply_multicast_rate_limit(&mut out, now + Duration::from_millis(100), true);
        assert_eq!(out.answers_count(), 0);

        // 200ms later: `extra` is now requested as a real answer. It must pass,
        // because it was never actually multicast above (only carried as an
        // unsent additional), so the 1-second limit does not apply to it.
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE);
        out.add_answer_record(extra());
        registry.apply_multicast_rate_limit(&mut out, now + Duration::from_millis(200), true);
        assert_eq!(out.answers_count(), 1);
    }

    /// The restart must reset `next_send` too: after a lost tiebreak it is a
    /// second ahead, past `start_time + 750ms`, so the probe would otherwise
    /// expire without ever sending the renamed SRV.
    #[test]
    fn test_update_hostname_restarts_probe_send() {
        let mut registry = DnsRegistry::new();

        let instance = "inst._test._tcp.local.";
        let now = Instant::now();

        let mut probe = Probe::new(now);
        probe.insert_record(
            DnsSrv::new(
                instance,
                CLASS_IN | CLASS_CACHE_FLUSH,
                120,
                0,
                0,
                5200,
                "host.local.".to_string(),
            )
            .boxed(),
        );
        // As if this probe just lost a tiebreak.
        probe.start_time = now + Duration::from_millis(1000);
        probe.next_send = now + Duration::from_millis(1000);
        registry.probing.insert(instance.to_string(), probe);

        let probe_time = now + Duration::from_millis(100);
        assert!(registry.update_hostname("host.local.", "host-2.local.", probe_time));

        let probe = &registry.probing[instance];
        assert_eq!(probe.start_time, probe_time);
        assert_eq!(probe.next_send, probe_time);
        assert!(!probe.expired(probe.next_send));

        let srv = probe.records[0].any().downcast_ref::<DnsSrv>().unwrap();
        assert_eq!(srv.host(), "host-2.local.");
    }

    #[test]
    fn test_txt_encode_decode() {
        let properties = [
            TxtProperty::from(&("key1", "value1")),
            TxtProperty::from(&("key2", "value2")),
        ];

        // test encode
        let property_count = properties.len();
        let encoded = encode_txt(properties.iter());
        assert_eq!(
            encoded.len(),
            "key1=value1".len() + "key2=value2".len() + property_count
        );
        assert_eq!(encoded[0] as usize, "key1=value1".len());

        // test decode
        let decoded = decode_txt(&encoded);
        assert_eq!(properties, decoded[..]);

        // test empty value
        let properties = vec![TxtProperty::from(&("key3", ""))];
        let property_count = properties.len();
        let encoded = encode_txt(properties.iter());
        assert_eq!(encoded.len(), "key3=".len() + property_count);

        let decoded = decode_txt(&encoded);
        assert_eq!(properties, decoded);

        // test non-string value
        let binary_val: Vec<u8> = vec![123, 234, 0];
        let binary_len = binary_val.len();
        let properties = vec![TxtProperty::from(("key4", binary_val))];
        let property_count = properties.len();
        let encoded = encode_txt(properties.iter());
        assert_eq!(encoded.len(), "key4=".len() + binary_len + property_count);

        let decoded = decode_txt(&encoded);
        assert_eq!(properties, decoded);

        // test value that contains '='
        let properties = vec![TxtProperty::from(("key5", "val=5"))];
        let property_count = properties.len();
        let encoded = encode_txt(properties.iter());
        assert_eq!(
            encoded.len(),
            "key5=".len() + "val=5".len() + property_count
        );

        let decoded = decode_txt(&encoded);
        assert_eq!(properties, decoded);

        // test a property that has no value.
        let properties = vec![TxtProperty::from("key6")];
        let property_count = properties.len();
        let encoded = encode_txt(properties.iter());
        assert_eq!(encoded.len(), "key6".len() + property_count);
        let decoded = decode_txt(&encoded);
        assert_eq!(properties, decoded);

        // test property at the 255-byte limit.
        let properties = [TxtProperty::from(
            String::from_utf8(vec![0x30; 255]).unwrap().as_str(),
        )];
        let property_count = properties.len();
        let encoded = encode_txt(properties.iter());
        // `property_count` is added because each property has a length byte.
        assert_eq!(encoded.len(), 255 + property_count);
        let decoded = decode_txt(&encoded);
        assert_eq!(properties.to_vec(), decoded);
    }

    #[test]
    fn test_txt_property_exceeds_255_bytes() {
        let long_key = String::from_utf8(vec![0x30; 256]).unwrap();
        let result = ServiceInfo::new(
            "_test._tcp.local.",
            "test",
            "host",
            "",
            1234,
            &[(long_key.as_str(), "")][..],
        );
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("exceeding the 255-byte limit"));

        // A property exactly at 255 bytes should succeed.
        // key (250 bytes) + "=" (1 byte) + value (4 bytes) = 255 bytes.
        let key_at_limit = String::from_utf8(vec![0x30; 250]).unwrap();
        let result = ServiceInfo::new(
            "_test._tcp.local.",
            "test",
            "host",
            "",
            1234,
            &[(key_at_limit.as_str(), "abcd")][..],
        );
        assert!(result.is_ok());
    }

    #[test]
    fn test_set_properties_from_txt() {
        // Three duplicated keys.
        let properties = [
            TxtProperty::from(&("one", "1")),
            TxtProperty::from(&("ONE", "2")),
            TxtProperty::from(&("One", "3")),
        ];
        let encoded = encode_txt(properties.iter());

        // Simple decode does not remove duplicated keys.
        let decoded = decode_txt(&encoded);
        assert_eq!(decoded.len(), 3);

        // ServiceInfo removes duplicated keys and keeps only the first one.
        let mut service_info =
            ServiceInfo::new("_test._tcp", "prop_test", "localhost", "", 1234, None).unwrap();
        service_info._set_properties_from_txt(&encoded);
        assert_eq!(service_info.get_properties().len(), 1);

        // Verify the only one property.
        let prop = service_info.get_properties().iter().next().unwrap();
        assert_eq!(prop.key, "one");
        assert_eq!(prop.val_str(), "1");
    }

    #[test]
    fn test_u8_slice_to_hex() {
        let bytes = [0x01u8, 0x02u8, 0x03u8];
        let hex = u8_slice_to_hex(&bytes);
        assert_eq!(hex.as_str(), "0x010203");

        let slice = "abcdefghijklmnopqrstuvwxyz";
        let hex = u8_slice_to_hex(slice.as_bytes());
        assert_eq!(hex.len(), slice.len() * 2 + 2);
        assert_eq!(
            hex.as_str(),
            "0x6162636465666768696a6b6c6d6e6f707172737475767778797a"
        );
    }

    #[test]
    fn test_txt_property_debug() {
        // Test UTF-8 property value.
        let prop_1 = TxtProperty {
            key: "key1".to_string(),
            val: Some("val1".to_string().into()),
        };
        let prop_1_debug = format!("{:?}", prop_1);
        assert_eq!(
            prop_1_debug,
            "TxtProperty {key: \"key1\", val: Some(\"val1\")}"
        );

        // Test non-UTF-8 property value.
        let prop_2 = TxtProperty {
            key: "key2".to_string(),
            val: Some(vec![150u8, 151u8, 152u8]),
        };
        let prop_2_debug = format!("{:?}", prop_2);
        assert_eq!(
            prop_2_debug,
            "TxtProperty {key: \"key2\", val: Some(0x969798)}"
        );
    }

    #[test]
    fn test_txt_decode_property_size_out_of_bounds() {
        // Construct a TXT record with an invalid property length that would be out of bounds.
        let encoded: Vec<u8> = vec![
            0x0b, // Length 11
            b'k', b'e', b'y', b'1', b'=', b'v', b'a', b'l', b'u', b'e',
            b'1', // key1=value1 (Length 11)
            0x10, // Length 16 (Would be out of bounds)
            b'k', b'e', b'y', b'2', b'=', b'v', b'a', b'l', b'u', b'e',
            b'2', // key2=value2 (Length 11)
        ];
        // Decode the record content
        let decoded = decode_txt(&encoded);
        // We expect the out of bounds length for the second property to have caused the rest of the record content to be skipped.
        // Test that we only parsed the first property.
        assert_eq!(decoded.len(), 1);
        // Test that the key of the property we parsed is "key1"
        assert_eq!(decoded[0].key, "key1");
    }

    #[test]
    fn test_is_address_supported() {
        let mut service_info =
            ServiceInfo::new("_test._tcp", "prop_test", "testhost", "", 1234, None).unwrap();

        let intf_v6 = Interface {
            name: "foo".to_string(),
            index: Some(1),
            addr: IfAddr::V6(Ifv6Addr {
                ip: Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0x1234, 0, 0, 1),
                netmask: Ipv6Addr::new(0xffff, 0xffff, 0xffff, 0xffff, 0, 0, 0, 0),
                broadcast: None,
                prefixlen: 16,
            }),
            oper_status: IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        };

        let intf_v4 = Interface {
            name: "bar".to_string(),
            index: Some(1),
            addr: IfAddr::V4(Ifv4Addr {
                ip: Ipv4Addr::new(192, 1, 2, 3),
                netmask: Ipv4Addr::new(255, 255, 0, 0),
                broadcast: None,
                prefixlen: 16,
            }),
            oper_status: IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        };

        let intf_baz = Interface {
            name: "baz".to_string(),
            index: Some(1),
            addr: IfAddr::V6(Ifv6Addr {
                ip: Ipv6Addr::new(0x2003, 0xdb8, 0, 0, 0x1234, 0, 0, 1),
                netmask: Ipv6Addr::new(0xffff, 0xffff, 0xffff, 0xffff, 0, 0, 0, 0),
                broadcast: None,
                prefixlen: 16,
            }),
            oper_status: IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        };

        let intf_loopback_v4 = Interface {
            name: "foo".to_string(),
            index: Some(1),
            addr: IfAddr::V4(Ifv4Addr {
                ip: Ipv4Addr::new(127, 0, 0, 1),
                netmask: Ipv4Addr::new(255, 255, 255, 255),
                broadcast: None,
                prefixlen: 16,
            }),
            oper_status: IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        };

        let intf_loopback_v6 = Interface {
            name: "foo".to_string(),
            index: Some(1),
            addr: IfAddr::V6(Ifv6Addr {
                ip: Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 1),
                netmask: Ipv6Addr::new(
                    0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff, 0xffff,
                ),
                broadcast: None,
                prefixlen: 16,
            }),
            oper_status: IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        };

        let intf_link_local_v4 = Interface {
            name: "foo".to_string(),
            index: Some(1),
            addr: IfAddr::V4(Ifv4Addr {
                ip: Ipv4Addr::new(169, 254, 0, 1),
                netmask: Ipv4Addr::new(255, 255, 0, 0),
                broadcast: None,
                prefixlen: 16,
            }),
            oper_status: IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        };

        let intf_link_local_v6 = Interface {
            name: "foo".to_string(),
            index: Some(1),
            addr: IfAddr::V6(Ifv6Addr {
                ip: Ipv6Addr::new(0xfe80, 0, 0, 0, 0x1234, 0, 0, 1),
                netmask: Ipv6Addr::new(0xffff, 0xffff, 0xffff, 0xffff, 0, 0, 0, 0),
                broadcast: None,
                prefixlen: 16,
            }),
            oper_status: IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        };

        // supported addresses not specified
        assert!(service_info.is_address_supported(&intf_v6));

        // Interface not supported
        service_info.set_interfaces(vec![
            IfKind::Name("foo".to_string()),
            IfKind::Name("bar".to_string()),
        ]);
        assert!(!service_info.is_address_supported(&intf_baz));

        // link-local only
        service_info.set_link_local_only(true);
        assert!(!service_info.is_address_supported(&intf_v4));
        assert!(!service_info.is_address_supported(&intf_v6));
        assert!(service_info.is_address_supported(&intf_link_local_v4));
        assert!(service_info.is_address_supported(&intf_link_local_v6));
        service_info.set_link_local_only(false);

        // supported interfaces: IfKing::All
        service_info.set_interfaces(vec![IfKind::All]);
        assert!(service_info.is_address_supported(&intf_v6));
        assert!(service_info.is_address_supported(&intf_v4));

        // supported interfaces: IfKind::IPv6
        service_info.set_interfaces(vec![IfKind::IPv6]);
        assert!(service_info.is_address_supported(&intf_v6));
        assert!(!service_info.is_address_supported(&intf_v4));

        // supported interfaces: IfKind::IPv4
        service_info.set_interfaces(vec![IfKind::IPv4]);
        assert!(service_info.is_address_supported(&intf_v4));
        assert!(!service_info.is_address_supported(&intf_v6));

        // supported interfaces: IfKind::Addr
        service_info.set_interfaces(vec![IfKind::Addr(intf_v6.ip())]);
        assert!(service_info.is_address_supported(&intf_v6));
        assert!(!service_info.is_address_supported(&intf_v4));

        // supported interfaces: IfKind::LoopbackV4
        service_info.set_interfaces(vec![IfKind::LoopbackV4]);
        assert!(service_info.is_address_supported(&intf_loopback_v4));
        assert!(!service_info.is_address_supported(&intf_loopback_v6));

        // supported interfaces: IfKind::LoopbackV6
        service_info.set_interfaces(vec![IfKind::LoopbackV6]);
        assert!(!service_info.is_address_supported(&intf_loopback_v4));
        assert!(service_info.is_address_supported(&intf_loopback_v6));

        // supported interfaces: IPv4 and name = "foo"
        service_info.set_interfaces(vec![IfKind::Predicate(IfPredicate::new(|intf| {
            intf.ip().is_ipv4() && intf.name == "foo"
        }))]);
        assert!(service_info.is_address_supported(&intf_loopback_v4));
        assert!(!service_info.is_address_supported(&intf_v4));
        assert!(!service_info.is_address_supported(&intf_loopback_v6));
    }

    #[test]
    fn test_scoped_ip_set_detects_interface_id_change() {
        use crate::{InterfaceId, ScopedIp, ScopedIpV4};
        use std::collections::HashSet;

        let intf1 = InterfaceId {
            name: "en0".to_string(),
            index: 1,
        };
        let intf2 = InterfaceId {
            name: "en1".to_string(),
            index: 2,
        };
        let addr = Ipv4Addr::new(192, 168, 1, 100);

        let scoped_v4_one_intf = ScopedIpV4::new(addr, intf1);
        let mut scoped_v4_two_intfs = scoped_v4_one_intf.clone();
        scoped_v4_two_intfs.add_interface_id(intf2);

        assert_ne!(scoped_v4_one_intf, scoped_v4_two_intfs);

        let set_old: HashSet<ScopedIp> = HashSet::from([ScopedIp::V4(scoped_v4_one_intf)]);
        let set_new: HashSet<ScopedIp> = HashSet::from([ScopedIp::V4(scoped_v4_two_intfs)]);

        assert_ne!(set_old, set_new);
    }

    #[cfg(test)]
    #[cfg(feature = "serde")]
    mod serde {
        use super::{Ipv4Addr, Ipv6Addr};
        use crate::{ResolvedService, ScopedIp, TxtProperties};

        use std::collections::HashSet;
        use std::net::IpAddr;

        #[test]
        fn test_deserialize_serialize() -> Result<(), Box<dyn std::error::Error>> {
            let addresses = HashSet::from([
                ScopedIp::from(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1))),
                ScopedIp::from(IpAddr::V6(Ipv6Addr::new(
                    0xfe80, 0x2001, 0x0db8, 0x85a3, 0x0000, 0x8a2e, 0x0370, 0x7334,
                ))),
            ]);

            let service = ResolvedService {
                ty_domain: "_http._tcp.local.".to_owned(),
                sub_ty_domain: None,
                fullname: "example._http._tcp.local.".to_owned(),
                host: "example.local.".to_owned(),
                port: 1234,
                addresses,
                txt_properties: TxtProperties::new(),
            };

            let json = serde_json::to_value(&service)?;

            let parsed: ResolvedService = serde_json::from_value(json)?;

            assert!(compare(&service, &parsed));

            Ok(())
        }

        fn compare(service: &ResolvedService, other: &ResolvedService) -> bool {
            service.ty_domain == other.ty_domain
                && service.sub_ty_domain == other.sub_ty_domain
                && service.fullname == other.fullname
                && service.host == other.host
                && service.port == other.port
                && service.addresses == other.addresses
                && service.txt_properties == other.txt_properties
        }
    }
}
