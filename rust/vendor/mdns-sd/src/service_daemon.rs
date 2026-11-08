//! Service daemon for mDNS Service Discovery.

// How DNS-based Service Discovery works in a nutshell:
//
// (excerpt from RFC 6763)
// .... that a particular service instance can be
//    described using a DNS SRV [RFC2782] and DNS TXT [RFC1035] record.
//    The SRV record has a name of the form "<Instance>.<Service>.<Domain>"
//    and gives the target host and port where the service instance can be
//    reached.  The DNS TXT record of the same name gives additional
//    information about this instance, in a structured form using key/value
//    pairs, described in Section 6.  A client discovers the list of
//    available instances of a given service type using a query for a DNS
//    PTR [RFC1035] record with a name of the form "<Service>.<Domain>",
//    which returns a set of zero or more names, which are the names of the
//    aforementioned DNS SRV/TXT record pairs.
//
// Some naming conventions in this source code:
//
// `ty_domain` refers to service type together with domain name, i.e. <service>.<domain>.
// Every <service> consists of two labels: service itself and "_udp." or "_tcp".
// See RFC 6763 section 7 Service Names.
//     for example: `_my-service._udp.local.`
//
// `fullname` refers to a full Service Instance Name, i.e. <instance>.<service>.<domain>
//     for example: `my_home._my-service._udp.local.`
//
// In mDNS and DNS, the basic data structure is "Resource Record" (RR), where
// in Service Discovery, the basic data structure is "Service Info". One Service Info
// corresponds to a set of DNS Resource Records.
#[cfg(feature = "logging")]
use crate::log::{debug, error, trace};
use crate::{
    dns_cache::{DnsCache, IpType},
    dns_parser::{
        ip_address_rr_type, max_pkt_absolute, DnsAddress, DnsEntryExt, DnsIncoming, DnsNSec,
        DnsOutgoing, DnsPointer, DnsQuestion, DnsRecordBox, DnsRecordExt, DnsSrv, DnsTxt,
        InterfaceId, RRType, ScopedIp, CLASS_CACHE_FLUSH, CLASS_IN, FLAGS_AA, FLAGS_QR_QUERY,
        FLAGS_QR_RESPONSE, MAX_PKT_ABSOLUTE_IPV6, MAX_PKT_DEFAULT,
    },
    error::{e_fmt, Error, Result},
    service_info::{
        valid_ip_on_intf, DnsRegistry, MyIntf, Probe, ServiceInfo, ServiceStatus,
        MULTICAST_RATE_LIMIT_MILLIS,
    },
    Receiver, ResolvedService, TxtProperties,
};
use flume::{bounded, Sender, TrySendError};
use if_addrs::{IfAddr, Interface};
use mio::{event::Source, net::UdpSocket as MioUdpSocket, Interest, Poll, Registry, Token, Waker};
use socket2::Domain;
use socket_pktinfo::PktInfoUdpSocket;
use std::{
    cmp::{self, Reverse},
    collections::{BinaryHeap, HashMap, HashSet},
    fmt, io,
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, SocketAddrV4, SocketAddrV6},
    str,
    sync::Arc,
    thread,
    time::{Duration, Instant, SystemTime},
    vec,
};

/// The default max length of the service name without domain, not including the
/// leading underscore (`_`). It is set to 15 per
/// [RFC 6763 section 7.2](https://www.rfc-editor.org/rfc/rfc6763#section-7.2).
pub const SERVICE_NAME_LEN_MAX_DEFAULT: u8 = 15;

/// The default interval for checking IP changes automatically.
pub const IP_CHECK_INTERVAL_IN_SECS_DEFAULT: u32 = 5;

/// The default time out for [ServiceDaemon::verify] is 10 seconds, per
/// [RFC 6762 section 10.4](https://datatracker.ietf.org/doc/html/rfc6762#section-10.4)
pub const VERIFY_TIMEOUT_DEFAULT: Duration = Duration::from_secs(10);

/// The smallest value accepted by [`ServiceDaemon::set_max_packet_size`].
pub(crate) const MIN_MAX_PACKET_SIZE: usize = 512;

/// The mDNS port number per RFC 6762.
pub const MDNS_PORT: u16 = 5353;

const GROUP_ADDR_V4: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 251);
const GROUP_ADDR_V6: Ipv6Addr = Ipv6Addr::new(0xff02, 0, 0, 0, 0, 0, 0, 0xfb);
/// Capacity of event channels returned by `browse`, `browse_cache`, and `resolve_hostname`.
///
/// flume does not preallocate, so unused capacity has no cost. If a receiver falls too far
/// behind and the channel fills, the subscription is closed (see those APIs).
const EVENT_CHANNEL_CAPACITY: usize = 1000;

/// The first fast-path follow-up resolve query fires this soon after an
/// instance is found via PTR. Subsequent tries back off exponentially
/// (200ms, 400ms, 800ms, 1600ms), see `exec_command_resolve`.
const RESOLVE_RETRY_BASE_MILLIS: u64 = 200;

/// Max number of fast-path resolve tries before the browse retransmission
/// cycle takes over re-querying (see `query_unresolved_instances`).
const RESOLVE_MAX_TRY: u16 = 4;

/// RFC 6762 §8.3: the two unsolicited announcements are sent "one second apart".
/// We schedule the second one strictly wider than the §6 multicast rate-limit
/// window ([`MULTICAST_RATE_LIMIT_MILLIS`]) so that scheduling skew — the few
/// millis between capturing this base time and actually stamping the records as
/// multicast — can never make the rate limit throttle the second announcement
/// away. A small random jitter is added on top (see `ANNOUNCE_SECOND_JITTER_MILLIS`)
/// to de-synchronize announcements across hosts and services.
const ANNOUNCE_SECOND_DELAY_MILLIS: u64 = MULTICAST_RATE_LIMIT_MILLIS + 100;

/// Upper bound (exclusive) of the random jitter added to the second announcement
/// delay. Kept small so the spacing stays close to the RFC's "one second".
const ANNOUNCE_SECOND_JITTER_MILLIS: u64 = 50;

// The §8.3 announcement spacing MUST stay strictly wider than the §6 rate-limit
// window, or the rate limit throttles the second announcement away (leaving only
// one unsolicited response). Enforced at compile time so the two can't drift.
#[allow(clippy::assertions_on_constants)]
const _: () = assert!(ANNOUNCE_SECOND_DELAY_MILLIS > MULTICAST_RATE_LIMIT_MILLIS);

/// RFC 6762 §6:
/// In any case where there may be multiple responses, such as queries
/// where the answer is a member of a shared resource record set, each
/// responder SHOULD delay its response by a random amount of time
/// selected with uniform random distribution in the range 20-120 ms.
///
/// 20ms suggested in the RFC is a bit too long for min. Use 10ms instead.
const SHARED_RESPONSE_DELAY_MIN_MILLIS: u64 = 10;

/// 120ms suggested in the RFC is too long for max, use 50ms instead.
const SHARED_RESPONSE_DELAY_MAX_MILLIS: u64 = 50;

/// RFC 6762 §5.2: to avoid accidental synchronization when multiple clients
/// begin querying at exactly the same moment (e.g. because of some common
/// external trigger event), a querier SHOULD delay the first query of a
/// continuous-monitoring series by a randomly chosen amount in the range
/// 20-120 ms.
///
/// Like the responder delay above, we use a shorter 10-50 ms window.
const INITIAL_QUERY_DELAY_MIN_MILLIS: u64 = 10;
const INITIAL_QUERY_DELAY_MAX_MILLIS: u64 = 50;

/// The smallest gap between the wall clock and `Instant` that is taken as the
/// system having slept. Smaller gaps are left alone: they are within the
/// drift between the two clocks, and too short to matter for record TTLs.
const SLEEP_DETECTION_THRESHOLD: Duration = Duration::from_secs(2);

/// Response status code for the service `unregister` call.
#[derive(Debug)]
pub enum UnregisterStatus {
    /// Unregister was successful.
    OK,
    /// The service was not found in the registration.
    NotFound,
}

/// Status code for the service daemon.
#[derive(Debug, PartialEq, Clone, Eq)]
#[non_exhaustive]
pub enum DaemonStatus {
    /// The daemon is running as normal.
    Running,

    /// The daemon has been shutdown.
    Shutdown,
}

/// Different counters included in the metrics.
/// Currently all counters are for outgoing packets.
#[derive(Hash, Eq, PartialEq)]
enum Counter {
    Register,
    RegisterResend,
    Unregister,
    UnregisterResend,
    Browse,
    ResolveHostname,
    Respond,
    CacheRefreshPTR,
    CacheRefreshSrvTxt,
    CacheRefreshAddr,
    KnownAnswerSuppression,
    CachedPTR,
    CachedSRV,
    CachedAddr,
    CachedTxt,
    CachedNSec,
    CachedSubtype,
    DnsRegistryProbe,
    DnsRegistryActive,
    DnsRegistryTimer,
    DnsRegistryNameChange,
    Timer,
}

impl fmt::Display for Counter {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Self::Register => write!(f, "register"),
            Self::RegisterResend => write!(f, "register-resend"),
            Self::Unregister => write!(f, "unregister"),
            Self::UnregisterResend => write!(f, "unregister-resend"),
            Self::Browse => write!(f, "browse"),
            Self::ResolveHostname => write!(f, "resolve-hostname"),
            Self::Respond => write!(f, "respond"),
            Self::CacheRefreshPTR => write!(f, "cache-refresh-ptr"),
            Self::CacheRefreshSrvTxt => write!(f, "cache-refresh-srv-txt"),
            Self::CacheRefreshAddr => write!(f, "cache-refresh-addr"),
            Self::KnownAnswerSuppression => write!(f, "known-answer-suppression"),
            Self::CachedPTR => write!(f, "cached-ptr"),
            Self::CachedSRV => write!(f, "cached-srv"),
            Self::CachedAddr => write!(f, "cached-addr"),
            Self::CachedTxt => write!(f, "cached-txt"),
            Self::CachedNSec => write!(f, "cached-nsec"),
            Self::CachedSubtype => write!(f, "cached-subtype"),
            Self::DnsRegistryProbe => write!(f, "dns-registry-probe"),
            Self::DnsRegistryActive => write!(f, "dns-registry-active"),
            Self::DnsRegistryTimer => write!(f, "dns-registry-timer"),
            Self::DnsRegistryNameChange => write!(f, "dns-registry-name-change"),
            Self::Timer => write!(f, "timer"),
        }
    }
}

#[derive(Debug)]
enum InternalError {
    IntfAddrInvalid(Interface),
}

impl fmt::Display for InternalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            InternalError::IntfAddrInvalid(iface) => write!(f, "interface addr invalid: {iface:?}"),
        }
    }
}

type MyResult<T> = core::result::Result<T, InternalError>;

/// A wrapper around UDP socket used by the mDNS daemon.
///
/// We do this because `mio` does not support PKTINFO and
/// does not provide a way to implement `Source` trait directly and safely.
struct MyUdpSocket {
    /// The underlying socket that supports control messages like
    /// `IP_PKTINFO` for IPv4 and `IPV6_PKTINFO` for IPv6.
    pktinfo: PktInfoUdpSocket,

    /// The mio UDP socket that is a clone of `pktinfo` and
    /// is used for event polling.
    mio: MioUdpSocket,
}

impl MyUdpSocket {
    pub fn new(pktinfo: PktInfoUdpSocket) -> io::Result<Self> {
        let std_sock = pktinfo.try_clone_std()?;
        let mio = MioUdpSocket::from_std(std_sock);

        Ok(Self { pktinfo, mio })
    }
}

/// Implements the mio `Source` trait so that we can use `MyUdpSocket` with `Poll`.
impl Source for MyUdpSocket {
    fn register(
        &mut self,
        registry: &Registry,
        token: Token,
        interests: Interest,
    ) -> io::Result<()> {
        self.mio.register(registry, token, interests)
    }

    fn reregister(
        &mut self,
        registry: &Registry,
        token: Token,
        interests: Interest,
    ) -> io::Result<()> {
        self.mio.reregister(registry, token, interests)
    }

    fn deregister(&mut self, registry: &Registry) -> std::io::Result<()> {
        self.mio.deregister(registry)
    }
}

/// The metrics is a HashMap of (name_key, i64_value).
/// The main purpose is to help monitoring the mDNS packet traffic.
pub type Metrics = HashMap<String, i64>;

const IPV4_SOCK_EVENT_KEY: usize = 4; // Pick a key just to indicate IPv4.
const IPV6_SOCK_EVENT_KEY: usize = 6; // Pick a key just to indicate IPv6.
/// Token for the single `mio::Waker` registered with the daemon `Poll`.
/// Distinct from the IPv4 and IPv6 socket tokens.
const WAKER_EVENT_KEY: usize = usize::MAX - 1;

/// A daemon thread for mDNS
///
/// This struct provides a handle and an API to the daemon. It is cloneable.
#[derive(Clone)]
pub struct ServiceDaemon {
    /// Sender handle of the channel to the daemon.
    sender: Sender<Command>,

    /// Wakes the daemon `Poll` after a command is queued.
    ///
    /// Cloned handles share this one `Waker`. mio allows only one `Waker`
    /// per `Poll`, and the daemon thread keeps its own `Arc` clone so the
    /// registration stays alive for the life of the event loop.
    waker: Arc<Waker>,
}

/// Enqueue `cmd`, then wake the poller.
///
/// The wake is not a command count: mio may coalesce many `wake` calls into
/// one event. A failed enqueue does not wake. If `wake` fails after a
/// successful enqueue, the command stays queued and this returns the wake
/// error rather than pretending the command was never accepted.
fn enqueue_and_wake(sender: &Sender<Command>, waker: &Waker, cmd: Command) -> Result<()> {
    sender.try_send(cmd).map_err(|e| match e {
        TrySendError::Full(_) => Error::Again,
        TrySendError::Disconnected(_) => Error::DaemonShutdown,
    })?;

    waker
        .wake()
        .map_err(|e| e_fmt!("failed to wake daemon: {e}"))?;

    Ok(())
}

impl ServiceDaemon {
    /// Creates a new daemon and spawns a thread to run the daemon.
    ///
    /// Creates a new mDNS service daemon using the default port (5353).
    ///
    /// For development/testing with custom ports, use [`ServiceDaemon::new_with_port`].
    ///
    /// # Errors
    ///
    /// Returns [`Error::Msg`] if the daemon cannot be initialized. This wraps an
    /// underlying OS-level failure.
    ///
    /// Note that this constructor does not open the mDNS multicast sockets — those
    /// are opened lazily by the daemon thread once it starts, so platform issues
    /// such as "multicast not permitted" are surfaced later via [`DaemonEvent`] from
    /// [`monitor`](Self::monitor) rather than here.
    pub fn new() -> Result<Self> {
        Self::new_with_port(MDNS_PORT)
    }

    /// Creates a new mDNS service daemon using a custom port.
    ///
    /// # Arguments
    ///
    /// * `port` - The UDP port to bind for mDNS communication.
    ///   - In production, this should be `MDNS_PORT` (5353) per RFC 6762.
    ///   - For development/testing, you can use a non-standard port (e.g., 5454)
    ///     to avoid conflicts with system mDNS services.
    ///   - Both publisher and browser must use the same port to communicate.
    ///
    /// # Example
    ///
    /// ```no_run
    /// use mdns_sd::ServiceDaemon;
    ///
    /// // Use standard mDNS port (production)
    /// let daemon = ServiceDaemon::new_with_port(5353)?;
    ///
    /// // Use custom port for development (avoids macOS Bonjour conflict)
    /// let daemon_dev = ServiceDaemon::new_with_port(5454)?;
    /// # Ok::<(), mdns_sd::Error>(())
    /// ```
    ///
    /// # Errors
    ///
    /// See [`new`](Self::new) for the set of OS-level failures that may surface
    /// here. Note that `port` is *not* validated against the kernel until the
    /// daemon thread tries to bind the mDNS sockets, so an unusable `port`
    /// (e.g., already in use, requires elevated privileges) will not be
    /// reported by this constructor — listen for such failures via
    /// [`monitor`](Self::monitor).
    pub fn new_with_port(port: u16) -> Result<Self> {
        let poller = Poll::new().map_err(|e| e_fmt!("failed to create mio Poll: {e}"))?;
        // Created before the thread starts so a registration failure is
        // reported here, and so a command queued during startup is already
        // visible to the first `poll`.
        let waker = Arc::new(
            Waker::new(poller.registry(), Token(WAKER_EVENT_KEY))
                .map_err(|e| e_fmt!("failed to create mio Waker: {e}"))?,
        );

        let (sender, receiver) = bounded(100);

        let cmd_sender = sender.clone();
        let thread_waker = waker.clone();
        thread::Builder::new()
            .name("mDNS_daemon".to_string())
            .spawn(move || Self::daemon_thread(thread_waker, poller, receiver, port, cmd_sender))
            .map_err(|e| e_fmt!("thread builder failed to spawn: {}", e))?;

        Ok(Self { sender, waker })
    }

    /// Enqueues `cmd`, then wakes the daemon poller.
    ///
    /// Wakeups are coalesced, so the command queue is what gets processed.
    /// `wake` runs only after a successful enqueue. A later `wake` error does
    /// not mean the command was rejected: it is already queued and can still
    /// run on the next poll.
    fn send_cmd(&self, cmd: Command) -> Result<()> {
        enqueue_and_wake(&self.sender, &self.waker, cmd)
    }

    /// Starts browsing for a specific service type.
    ///
    /// `service_type` must end with a valid mDNS domain: '._tcp.local.' or '._udp.local.'
    ///
    /// Returns a channel `Receiver` to receive events about the service. The caller
    /// can call `.recv_async().await` on this receiver to handle events in an
    /// async environment or call `.recv()` in a sync environment.
    ///
    /// When a new instance is found, the daemon automatically tries to resolve, i.e.
    /// finding more details, i.e. SRV records and TXT records.
    ///
    /// The subscription ends if the event channel is full (e.g. the receiver
    /// falls too far behind).
    ///
    /// # Errors
    ///
    /// Returns [`Error::Msg`] if `service_type` does not end with
    /// `._tcp.local.` or `._udp.local.`.
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn browse(&self, service_type: &str) -> Result<Receiver<ServiceEvent>> {
        check_domain_suffix(service_type)?;

        let (resp_s, resp_r) = bounded(EVENT_CHANNEL_CAPACITY);
        self.send_cmd(Command::Browse(service_type.to_string(), 1, false, resp_s))?;
        Ok(resp_r)
    }

    /// Preforms a "cache-only" browse.
    ///
    /// `service_type` must end with a valid mDNS domain: '._tcp.local.' or '._udp.local.'
    ///
    /// The functionality is identical to 'browse', but the service events are based solely on the contents
    /// of the daemon's cache. No actual mDNS query is sent to the network.
    ///
    /// See [accept_unsolicited](Self::accept_unsolicited) if you want to do cache-only browsing.
    ///
    /// The subscription ends if the event channel is full (e.g. the receiver
    /// falls too far behind).
    ///
    /// # Errors
    ///
    /// Same error conditions as [`browse`](Self::browse).
    pub fn browse_cache(&self, service_type: &str) -> Result<Receiver<ServiceEvent>> {
        check_domain_suffix(service_type)?;

        let (resp_s, resp_r) = bounded(EVENT_CHANNEL_CAPACITY);
        self.send_cmd(Command::Browse(service_type.to_string(), 1, true, resp_s))?;
        Ok(resp_r)
    }

    /// Stops searching for a specific service type.
    ///
    /// # Errors
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn stop_browse(&self, ty_domain: &str) -> Result<()> {
        self.send_cmd(Command::StopBrowse(ty_domain.to_string()))
    }

    /// Starts querying for the ip addresses of a hostname.
    ///
    /// Returns a channel `Receiver` to receive events about the hostname.
    /// The caller can call `.recv_async().await` on this receiver to handle events in an
    /// async environment or call `.recv()` in a sync environment.
    ///
    /// The `timeout` is specified in milliseconds.
    ///
    /// The subscription ends if the event channel is full (e.g. the receiver
    /// falls too far behind).
    ///
    /// # Errors
    ///
    /// Returns [`Error::Msg`] if:
    ///
    /// - `hostname` does not end with `.local.`;
    /// - `hostname` is exactly `.local.` (the label before `.local.` is empty);
    /// - `hostname` is longer than 255 bytes.
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn resolve_hostname(
        &self,
        hostname: &str,
        timeout: Option<u64>,
    ) -> Result<Receiver<HostnameResolutionEvent>> {
        check_hostname(hostname)?;
        let (resp_s, resp_r) = bounded(EVENT_CHANNEL_CAPACITY);
        self.send_cmd(Command::ResolveHostname(
            hostname.to_string(),
            1,
            resp_s,
            timeout,
        ))?;
        Ok(resp_r)
    }

    /// Stops querying for the ip addresses of a hostname.
    ///
    /// # Errors
    ///
    /// Same error conditions as [`stop_browse`](Self::stop_browse).
    pub fn stop_resolve_hostname(&self, hostname: &str) -> Result<()> {
        self.send_cmd(Command::StopResolveHostname(hostname.to_string()))
    }

    /// Registers a service provided by this host.
    ///
    /// If `service_info` has no addresses yet and its `addr_auto` is enabled,
    /// this method will automatically fill in addresses from the host.
    ///
    /// To re-announce a service with an updated `service_info`, just call
    /// this `register` function again. No need to call `unregister` first.
    ///
    /// # Errors
    ///
    /// Returns [`Error::Msg`] if the [`ServiceInfo`] is malformed, for example:
    ///
    /// - the fullname does not end with `._tcp.local.` or `._udp.local.`;
    /// - the hostname does not end with `.local.`, is exactly `.local.`, or
    ///   is longer than 255 bytes.
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn register(&self, service_info: ServiceInfo) -> Result<()> {
        check_service_name(service_info.get_fullname())?;
        check_hostname(service_info.get_hostname())?;

        self.send_cmd(Command::Register(service_info.into()))
    }

    /// Unregisters a service. This is a graceful shutdown of a service.
    ///
    /// Returns a channel receiver that is used to receive the status code
    /// of the unregister.
    ///
    /// # Errors
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn unregister(&self, fullname: &str) -> Result<Receiver<UnregisterStatus>> {
        let (resp_s, resp_r) = bounded(1);
        self.send_cmd(Command::Unregister(fullname.to_lowercase(), resp_s))?;
        Ok(resp_r)
    }

    /// Starts to monitor events from the daemon.
    ///
    /// Returns a channel [`Receiver`] of [`DaemonEvent`].
    ///
    /// # Errors
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn monitor(&self) -> Result<Receiver<DaemonEvent>> {
        let (resp_s, resp_r) = bounded(100);
        self.send_cmd(Command::Monitor(resp_s))?;
        Ok(resp_r)
    }

    /// Shuts down the daemon thread and returns a channel to receive the status.
    ///
    /// # Errors
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn shutdown(&self) -> Result<Receiver<DaemonStatus>> {
        let (resp_s, resp_r) = bounded(1);
        self.send_cmd(Command::Exit(resp_s))?;
        Ok(resp_r)
    }

    /// Returns the status of the daemon.
    ///
    /// # Errors
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn status(&self) -> Result<Receiver<DaemonStatus>> {
        let (resp_s, resp_r) = bounded(1);

        if self.sender.is_disconnected() {
            resp_s
                .send(DaemonStatus::Shutdown)
                .map_err(|e| e_fmt!("failed to send daemon status to the client: {}", e))?;
        } else {
            self.send_cmd(Command::GetStatus(resp_s))?;
        }

        Ok(resp_r)
    }

    /// Returns a channel receiver for the metrics, e.g. input/output counters.
    ///
    /// The metrics returned is a snapshot. Hence the caller should call
    /// this method repeatedly if they want to monitor the metrics continuously.
    ///
    /// # Errors
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn get_metrics(&self) -> Result<Receiver<Metrics>> {
        let (resp_s, resp_r) = bounded(1);
        self.send_cmd(Command::GetMetrics(resp_s))?;
        Ok(resp_r)
    }

    /// Change the max length allowed for a service name.
    ///
    /// As RFC 6763 defines a length max for a service name, a user should not call
    /// this method unless they have to. See [`SERVICE_NAME_LEN_MAX_DEFAULT`].
    ///
    /// `len_max` is capped at an internal limit, which is currently 30.
    ///
    /// # Errors
    ///
    /// Returns [`Error::Msg`] if `len_max` exceeds the internal cap (30).
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn set_service_name_len_max(&self, len_max: u8) -> Result<()> {
        const SERVICE_NAME_LEN_MAX_LIMIT: u8 = 30; // Double the default length max.

        if len_max > SERVICE_NAME_LEN_MAX_LIMIT {
            return Err(Error::Msg(format!(
                "service name length max {len_max} is too large"
            )));
        }

        self.send_cmd(Command::SetOption(DaemonOption::ServiceNameLenMax(len_max)))
    }

    /// Change the max byte size of a packet this daemon generates on the interfaces
    /// matching `if_kind`. Use `IfKind::All` to change it on every interface. Messages
    /// that don't fit are split across multiple packets. A single record that doesn't
    /// fit in a packet is sent alone in a packet of up to 8952 bytes over IPv6 or 8972
    /// bytes over IPv4, per RFC 6762 section 17.
    ///
    /// The default is `MAX_PKT_DEFAULT` (1452 bytes), small enough to fit in one
    /// Ethernet frame over either IPv4 or IPv6.
    ///
    /// `size` must be in the range `512..=8952`. The minimum of 512 bytes is the classic
    /// UDP DNS message size of RFC 1035. The maximum of 8952 bytes follows from RFC 6762
    /// section 17, which caps an mDNS packet at 9000 bytes: we subtract the
    /// bigger of the two IP headers so that a generated packet is legal over either
    /// IP version.
    pub fn set_max_packet_size(&self, if_kind: impl IntoIfKindVec, size: usize) -> Result<()> {
        if size < MIN_MAX_PACKET_SIZE {
            return Err(Error::Msg(format!(
                "max packet size {size} is too small, must be at least {MIN_MAX_PACKET_SIZE}"
            )));
        }

        if size > MAX_PKT_ABSOLUTE_IPV6 {
            return Err(Error::Msg(format!(
                "max packet size {size} is too big, must be at most {MAX_PKT_ABSOLUTE_IPV6}"
            )));
        }

        let if_kind_vec = if_kind.into_vec();
        self.send_cmd(Command::SetOption(DaemonOption::MaxPacketSize(
            if_kind_vec.kinds,
            size,
        )))
    }

    /// Change the interval for checking IP changes automatically.
    ///
    /// Setting the interval to 0 disables the IP check.
    ///
    /// See [`IP_CHECK_INTERVAL_IN_SECS_DEFAULT`] for the default interval.
    pub fn set_ip_check_interval(&self, interval_in_secs: u32) -> Result<()> {
        let interval_in_millis = interval_in_secs as u64 * 1000;
        self.send_cmd(Command::SetOption(DaemonOption::IpCheckInterval(
            interval_in_millis,
        )))
    }

    /// Get the current interval in seconds for checking IP changes automatically.
    pub fn get_ip_check_interval(&self) -> Result<u32> {
        let (resp_s, resp_r) = bounded(1);
        self.send_cmd(Command::GetOption(resp_s))?;

        let option = resp_r
            .recv_timeout(Duration::from_secs(10))
            .map_err(|e| e_fmt!("failed to receive ip check interval: {}", e))?;
        let ip_check_interval_in_secs = option.ip_check_interval / 1000;
        Ok(ip_check_interval_in_secs as u32)
    }

    /// Include interfaces that match `if_kind` for this service daemon.
    ///
    /// For example:
    /// ```ignore
    ///     daemon.enable_interface("en0")?;
    /// ```
    pub fn enable_interface(&self, if_kind: impl IntoIfKindVec) -> Result<()> {
        let if_kind_vec = if_kind.into_vec();
        self.send_cmd(Command::SetOption(DaemonOption::EnableInterface(
            if_kind_vec.kinds,
        )))
    }

    /// Ignore/exclude interfaces that match `if_kind` for this daemon.
    ///
    /// For example:
    /// ```ignore
    ///     daemon.disable_interface(IfKind::IPv6)?;
    /// ```
    pub fn disable_interface(&self, if_kind: impl IntoIfKindVec) -> Result<()> {
        let if_kind_vec = if_kind.into_vec();
        self.send_cmd(Command::SetOption(DaemonOption::DisableInterface(
            if_kind_vec.kinds,
        )))
    }

    /// If `accept` is true, accept and cache all responses, even if there is no active querier
    /// for a given service type. This is useful / necessary when doing cache-only browsing. See
    /// [browse_cache](Self::browse_cache).
    ///
    /// If `accept` is false (default), accept only responses matching queries that we have initiated.
    ///
    /// For example:
    /// ```ignore
    ///     daemon.accept_unsolicited(true)?;
    /// ```
    pub fn accept_unsolicited(&self, accept: bool) -> Result<()> {
        self.send_cmd(Command::SetOption(DaemonOption::AcceptUnsolicited(accept)))
    }

    /// Include or exclude Apple P2P interfaces, e.g. "awdl0", "llw0".
    /// By default, they are excluded.
    pub fn include_apple_p2p(&self, include: bool) -> Result<()> {
        self.send_cmd(Command::SetOption(DaemonOption::IncludeAppleP2P(include)))
    }

    #[cfg(test)]
    pub fn test_down_interface(&self, ifname: &str) -> Result<()> {
        self.send_cmd(Command::SetOption(DaemonOption::TestDownInterface(
            ifname.to_string(),
        )))
    }

    #[cfg(test)]
    pub fn test_up_interface(&self, ifname: &str) -> Result<()> {
        self.send_cmd(Command::SetOption(DaemonOption::TestUpInterface(
            ifname.to_string(),
        )))
    }

    /// Enable or disable the loopback for locally sent multicast packets in IPv4.
    ///
    /// By default, multicast loop is enabled for IPv4. When disabled, a querier will not
    /// receive announcements from a responder on the same host.
    ///
    /// Reference: <https://learn.microsoft.com/en-us/windows/win32/winsock/ip-multicast-2>
    ///
    /// "The Winsock version of the IP_MULTICAST_LOOP option is semantically different than
    /// the UNIX version of the IP_MULTICAST_LOOP option:
    ///
    /// In Winsock, the IP_MULTICAST_LOOP option applies only to the receive path.
    /// In the UNIX version, the IP_MULTICAST_LOOP option applies to the send path."
    ///
    /// Which means, in order NOT to receive localhost announcements, you want to call
    /// this API on the querier side on Windows, but on the responder side on Unix.
    pub fn set_multicast_loop_v4(&self, on: bool) -> Result<()> {
        self.send_cmd(Command::SetOption(DaemonOption::MulticastLoopV4(on)))
    }

    /// Enable or disable the loopback for locally sent multicast packets in IPv6.
    ///
    /// By default, multicast loop is enabled for IPv6. When disabled, a querier will not
    /// receive announcements from a responder on the same host.
    ///
    /// Reference: <https://learn.microsoft.com/en-us/windows/win32/winsock/ip-multicast-2>
    ///
    /// "The Winsock version of the IP_MULTICAST_LOOP option is semantically different than
    /// the UNIX version of the IP_MULTICAST_LOOP option:
    ///
    /// In Winsock, the IP_MULTICAST_LOOP option applies only to the receive path.
    /// In the UNIX version, the IP_MULTICAST_LOOP option applies to the send path."
    ///
    /// Which means, in order NOT to receive localhost announcements, you want to call
    /// this API on the querier side on Windows, but on the responder side on Unix.
    pub fn set_multicast_loop_v6(&self, on: bool) -> Result<()> {
        self.send_cmd(Command::SetOption(DaemonOption::MulticastLoopV6(on)))
    }

    /// Proactively confirms whether a service instance still valid.
    ///
    /// This call will issue queries for a service instance's SRV record and Address records.
    ///
    /// For `timeout`, most users should use [VERIFY_TIMEOUT_DEFAULT]
    /// unless there is a reason not to follow RFC.
    ///
    /// If no response is received within `timeout`, the current resource
    /// records will be flushed, and if needed, `ServiceRemoved` event will be
    /// sent to active queriers.
    ///
    /// Reference: [RFC 6762](https://datatracker.ietf.org/doc/html/rfc6762#section-10.4)
    ///
    /// # Errors
    ///
    /// Returns [`Error::Again`] if the daemon's command queue is full.
    ///
    /// Returns [`Error::DaemonShutdown`] if the daemon thread has already exited.
    pub fn verify(&self, instance_fullname: String, timeout: Duration) -> Result<()> {
        self.send_cmd(Command::Verify(instance_fullname, timeout))
    }

    fn daemon_thread(
        waker: Arc<Waker>,
        poller: Poll,
        receiver: Receiver<Command>,
        port: u16,
        cmd_sender: Sender<Command>,
    ) {
        let mut zc = Zeroconf::new(waker, poller, port, cmd_sender);

        if let Some(cmd) = zc.run(receiver) {
            match cmd {
                Command::Exit(resp_s) => {
                    // It is guaranteed that the receiver already dropped,
                    // i.e. the daemon command channel closed.
                    if let Err(e) = resp_s.send(DaemonStatus::Shutdown) {
                        debug!("exit: failed to send response of shutdown: {}", e);
                    }
                }
                _ => {
                    debug!("Unexpected command: {:?}", cmd);
                }
            }
        }
    }
}

/// Creates a new UDP socket that uses `intf` to send and recv multicast.
fn _new_socket_bind(intf: &Interface, should_loop: bool) -> Result<MyUdpSocket> {
    // Use the same socket for receiving and sending multicast packets.
    // Such socket has to bind to INADDR_ANY or IN6ADDR_ANY.
    let intf_ip = &intf.ip();
    match intf_ip {
        IpAddr::V4(ip) => {
            let addr = SocketAddrV4::new(Ipv4Addr::new(0, 0, 0, 0), MDNS_PORT);
            let sock = new_socket(addr.into(), true)?;

            // Join mDNS group to receive packets.
            sock.join_multicast_v4(&GROUP_ADDR_V4, ip)
                .map_err(|e| e_fmt!("join multicast group on addr {}: {}", intf_ip, e))?;

            // Set IP_MULTICAST_IF to send packets.
            sock.set_multicast_if_v4(ip)
                .map_err(|e| e_fmt!("set multicast_if on addr {}: {}", ip, e))?;

            // Per RFC 6762 section 11:
            // "All Multicast DNS responses (including responses sent via unicast) SHOULD
            // be sent with IP TTL set to 255."
            // Here we set the TTL to 255 for multicast as we don't support unicast yet.
            sock.set_multicast_ttl_v4(255)
                .map_err(|e| e_fmt!("set set_multicast_ttl_v4 on addr {}: {}", ip, e))?;

            if !should_loop {
                sock.set_multicast_loop_v4(false)
                    .map_err(|e| e_fmt!("failed to set multicast loop v4 for {ip}: {e}"))?;
            }

            // Test if we can send packets successfully.
            let multicast_addr = SocketAddrV4::new(GROUP_ADDR_V4, MDNS_PORT).into();
            let test_packets = DnsOutgoing::new(0).to_data_on_wire(MAX_PKT_DEFAULT, true);
            for packet in test_packets {
                sock.send_to(&packet, &multicast_addr)
                    .map_err(|e| e_fmt!("send multicast packet on addr {}: {}", ip, e))?;
            }
            MyUdpSocket::new(sock)
                .map_err(|e| e_fmt!("failed to create MySocket for interface {}: {e}", intf.name))
        }
        IpAddr::V6(ip) => {
            let addr = SocketAddrV6::new(Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 0), MDNS_PORT, 0, 0);
            let sock = new_socket(addr.into(), true)?;

            let if_index = intf.index.unwrap_or(0);

            // Join mDNS group to receive packets.
            sock.join_multicast_v6(&GROUP_ADDR_V6, if_index)
                .map_err(|e| e_fmt!("join multicast group on addr {}: {}", ip, e))?;

            // Set IPV6_MULTICAST_IF to send packets.
            sock.set_multicast_if_v6(if_index)
                .map_err(|e| e_fmt!("set multicast_if on addr {}: {}", ip, e))?;

            // We are not sending multicast packets to test this socket as there might
            // be many IPv6 interfaces on a host and could cause such send error:
            // "No buffer space available (os error 55)".

            MyUdpSocket::new(sock)
                .map_err(|e| e_fmt!("failed to create MySocket for interface {}: {e}", intf.name))
        }
    }
}

/// Creates a new UDP socket to bind to `port` with REUSEPORT option.
/// `non_block` indicates whether to set O_NONBLOCK for the socket.
fn new_socket(addr: SocketAddr, non_block: bool) -> Result<PktInfoUdpSocket> {
    let domain = match addr {
        SocketAddr::V4(_) => socket2::Domain::IPV4,
        SocketAddr::V6(_) => socket2::Domain::IPV6,
    };

    let fd = PktInfoUdpSocket::new(domain).map_err(|e| e_fmt!("create socket failed: {}", e))?;

    fd.set_reuse_address(true)
        .map_err(|e| e_fmt!("set ReuseAddr failed: {}", e))?;
    #[cfg(unix)]
    if let Err(e) = fd.set_reuse_port(true) {
        debug!(
            "SO_REUSEPORT is not supported, continuing without it: {}",
            e
        );
    }

    if non_block {
        fd.set_nonblocking(true)
            .map_err(|e| e_fmt!("set O_NONBLOCK: {}", e))?;
    }

    fd.bind(&addr.into())
        .map_err(|e| e_fmt!("socket bind to {} failed: {}", &addr, e))?;

    trace!("new socket bind to {}", addr);
    Ok(fd)
}

/// Specify when to run `command` for the next time.
struct ReRun {
    next_time: Instant,
    command: Command,
}

/// A query response deferred per RFC 6762 §6 (shared response).
struct DelayedResponse {
    /// When to send `out`.
    next_time: Instant,
    out: DnsOutgoing,
    if_index: u32,
    is_ipv4: bool,
}

/// Specify kinds of interfaces. It is used to enable or to disable interfaces in the daemon.
///
/// Note that for ergonomic reasons, `From<&str>` and `From<IpAddr>` are implemented.
#[derive(Debug, Clone)]
#[non_exhaustive]
pub enum IfKind {
    /// All interfaces.
    All,

    /// All IPv4 interfaces.
    IPv4,

    /// All IPv6 interfaces.
    IPv6,

    /// By the interface name, for example "en0"
    Name(String),

    /// By an IPv4 or IPv6 address.
    /// This is used to look up the interface. The semantics is to identify an interface of
    /// IPv4 or IPv6, not a specific address on the interface.
    Addr(IpAddr),

    /// 127.0.0.1 (or anything in 127.0.0.0/8), enabled by default.
    ///
    /// Loopback interfaces are required by some use cases (e.g., OSCQuery) for publishing.
    LoopbackV4,

    /// ::1/128, enabled by default.
    LoopbackV6,

    /// By interface index, IPv4 only.
    IndexV4(u32),

    /// By interface index, IPv6 only.
    IndexV6(u32),

    /// By a user-supplied predicate function.
    Predicate(IfPredicate),
}

impl IfKind {
    /// Checks if `intf` matches with this interface kind.
    pub(crate) fn matches(&self, intf: &Interface) -> bool {
        match self {
            Self::All => true,
            Self::IPv4 => intf.ip().is_ipv4(),
            Self::IPv6 => intf.ip().is_ipv6(),
            Self::Name(ifname) => ifname == &intf.name,
            Self::Addr(addr) => addr == &intf.ip(),
            Self::LoopbackV4 => intf.is_loopback() && intf.ip().is_ipv4(),
            Self::LoopbackV6 => intf.is_loopback() && intf.ip().is_ipv6(),
            Self::IndexV4(idx) => intf.index == Some(*idx) && intf.ip().is_ipv4(),
            Self::IndexV6(idx) => intf.index == Some(*idx) && intf.ip().is_ipv6(),
            Self::Predicate(p) => p.matches(intf),
        }
    }
}

/// The first use case of specifying an interface was to
/// use an interface name. Hence adding this for ergonomic reasons.
impl From<&str> for IfKind {
    fn from(val: &str) -> Self {
        Self::Name(val.to_string())
    }
}

impl From<&String> for IfKind {
    fn from(val: &String) -> Self {
        Self::Name(val.to_string())
    }
}

/// Still for ergonomic reasons.
impl From<IpAddr> for IfKind {
    fn from(val: IpAddr) -> Self {
        Self::Addr(val)
    }
}

/// A list of `IfKind` that can be used to match interfaces.
pub struct IfKindVec {
    kinds: Vec<IfKind>,
}

/// A trait that converts a type into a Vec of `IfKind`.
pub trait IntoIfKindVec {
    fn into_vec(self) -> IfKindVec;
}

impl<T: Into<IfKind>> IntoIfKindVec for T {
    fn into_vec(self) -> IfKindVec {
        let if_kind: IfKind = self.into();
        IfKindVec {
            kinds: vec![if_kind],
        }
    }
}

impl<T: Into<IfKind>> IntoIfKindVec for Vec<T> {
    fn into_vec(self) -> IfKindVec {
        let kinds: Vec<IfKind> = self.into_iter().map(|x| x.into()).collect();
        IfKindVec { kinds }
    }
}

/// A predicate function for matching against interfaces.
#[derive(Clone)]
pub struct IfPredicate(std::sync::Arc<dyn Fn(&Interface) -> bool + Send + Sync>);

impl IfPredicate {
    /// Creates a predicate from a closure that decides whether an interface
    /// matches.
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use mdns_sd::IfPredicate;
    /// // Match any interface that doesn't look like a virtual bridge
    /// IfPredicate::new(|intf| !intf.name.starts_with("virbr"));
    /// ```
    pub fn new(predicate: impl Fn(&Interface) -> bool + Send + Sync + 'static) -> Self {
        Self(std::sync::Arc::new(predicate))
    }

    pub(crate) fn matches(&self, intf: &Interface) -> bool {
        self.0(intf)
    }
}

impl std::fmt::Debug for IfPredicate {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "IfPredicate(...)")
    }
}

/// Selection of interfaces.
struct IfSelection {
    /// The interfaces to be selected.
    if_kind: IfKind,

    /// Whether the `if_kind` should be enabled or not.
    selected: bool,
}

/// Selection of the max packet size of interfaces.
struct MaxPacketSizeSelection {
    /// The interfaces to be selected.
    if_kind: IfKind,

    /// Max byte size of a packet generated for the selected interfaces.
    max_packet_size: usize,
}

/// A struct holding the state. It was inspired by `zeroconf` package in Python.
struct Zeroconf {
    /// The mDNS port number to use for socket binding.
    /// Typically MDNS_PORT (5353), but can be customized for development/testing.
    port: u16,

    /// Local interfaces keyed by interface index.
    my_intfs: HashMap<u32, MyIntf>,

    /// A common socket for IPv4 interfaces. It's None if IPv4 is disabled in OS kernel.
    ipv4_sock: Option<MyUdpSocket>,

    /// A common socket for IPv6 interfaces. It's None if IPv6 is disabled in OS kernel.
    ipv6_sock: Option<MyUdpSocket>,

    /// Local registered services， keyed by service full names.
    my_services: HashMap<String, ServiceInfo>,

    /// Received DNS records.
    cache: DnsCache,

    /// Registered service records, keyed by interface index.
    dns_registry_map: HashMap<u32, DnsRegistry>,

    /// Active "Browse" commands.
    service_queriers: HashMap<String, Sender<ServiceEvent>>, // <ty_domain, channel::sender>

    /// Active "ResolveHostname" commands.
    ///
    /// The timestamps are set at the future timestamp when the command should timeout.
    /// `hostname` is case-insensitive and stored in lowercase.
    hostname_resolvers: HashMap<String, (Sender<HostnameResolutionEvent>, Option<Instant>)>, // <hostname, (channel::sender, timeout)>

    /// All repeating transmissions.
    retransmissions: Vec<ReRun>,

    /// Query responses deferred per RFC 6762 §6.
    delayed_responses: Vec<DelayedResponse>,

    counters: Metrics,

    /// Waits for incoming packets.
    poller: Poll,

    /// Channels to notify events.
    monitors: Vec<Sender<DaemonEvent>>,

    /// Options
    service_name_len_max: u8,

    /// Interval in millis to check IP address changes.
    ip_check_interval: u64,

    /// When to run the next IP check. `None` when IP checks are disabled.
    next_ip_check: Option<Instant>,

    /// All max packet size selections called to the daemon, in call order.
    /// For an interface matched by more than one, the last one wins.
    max_packet_sizes: Vec<MaxPacketSizeSelection>,

    /// All interface selections called to the daemon.
    if_selections: Vec<IfSelection>,

    /// Timestamps marking where we need another iteration of the run loop,
    /// to react to events like retransmissions, cache refreshes, interface IP address changes, etc.
    ///
    /// When the run loop goes through a single iteration, it will
    /// set its timeout to the earliest timer in this list.
    timers: BinaryHeap<Reverse<Instant>>,

    status: DaemonStatus,

    /// Service instances that are pending for resolving SRV and TXT.
    pending_resolves: HashSet<String>,

    /// Service instances that are already resolved.
    resolved: HashSet<String>,

    multicast_loop_v4: bool,

    multicast_loop_v6: bool,

    accept_unsolicited: bool,

    include_apple_p2p: bool,

    cmd_sender: Sender<Command>,

    /// Same `Waker` the public handles use. Kept here so it outlives those
    /// handles and stays registered for the whole event loop.
    waker: Arc<Waker>,

    #[cfg(test)]
    test_down_interfaces: HashSet<String>,
}

/// Joins the IPv4 mDNS group on the interface that has `ip`.
///
/// The kernel picks the interface by address, so interfaces sharing an address
/// (e.g. the `bridge1NN` and `vmenetN` pairs of VMs on macOS) share one membership.
/// Joining it again fails with `AddrInUse`, which only means this socket already
/// holds it, so that is treated as success.
fn join_multicast_v4(my_sock: &PktInfoUdpSocket, ip: &Ipv4Addr) -> io::Result<()> {
    match my_sock.join_multicast_v4(&GROUP_ADDR_V4, ip) {
        Err(e) if e.kind() == io::ErrorKind::AddrInUse => {
            debug!("multicast group V4 already joined on addr {ip}");
            Ok(())
        }
        result => result,
    }
}

/// Join the multicast group for the given interface.
fn join_multicast_group(my_sock: &PktInfoUdpSocket, intf: &Interface) -> Result<()> {
    let intf_ip = &intf.ip();
    match intf_ip {
        IpAddr::V4(ip) => {
            // Join mDNS group to receive packets.
            debug!("join multicast group V4 on {} addr {ip}", intf.name);
            join_multicast_v4(my_sock, ip)
                .map_err(|e| e_fmt!("PKT join multicast group on addr {}: {}", intf_ip, e))?;
        }
        IpAddr::V6(ip) => {
            let if_index = intf.index.unwrap_or(0);
            // Join mDNS group to receive packets.
            debug!(
                "join multicast group V6 on {} addr {ip} with index {if_index}",
                intf.name
            );
            my_sock
                .join_multicast_v6(&GROUP_ADDR_V6, if_index)
                .map_err(|e| e_fmt!("PKT join multicast group on addr {}: {}", ip, e))?;
        }
    }
    Ok(())
}

/// Records the address of `intf` in `my_intfs`, joining the multicast group first
/// if its interface does not hold the membership yet.
///
/// The membership is per interface and per IP version, and is held as long as the
/// interface has a recorded address of that version, as only a successful join
/// records the first one. Joining again for another address would fail
/// (`AddrInUse` on most platforms, `WSAEINVAL` on Windows), so that is skipped.
///
/// Returns `false`, recording nothing, if the address is already recorded or the
/// join fails. A failed address is then retried by the next IP check.
fn add_intf_addr(
    my_intfs: &mut HashMap<u32, MyIntf>,
    sock: &PktInfoUdpSocket,
    intf: &Interface,
) -> bool {
    let if_index = intf.index.unwrap_or(0);
    let my_intf = my_intfs.get(&if_index);

    if my_intf.is_some_and(|v| v.addrs.contains(&intf.addr)) {
        trace!("address {} on {} already exists", intf.ip(), intf.name);
        return false;
    }

    let has_membership = my_intf.is_some_and(|v| {
        if intf.ip().is_ipv4() {
            v.next_ifaddr_v4().is_some()
        } else {
            v.next_ifaddr_v6().is_some()
        }
    });

    if !has_membership {
        if let Err(e) = join_multicast_group(sock, intf) {
            debug!("failed to join multicast on {}: {e}. Skipped.", intf.name);
            return false;
        }
    }

    my_intfs
        .entry(if_index)
        .and_modify(|v| {
            v.addrs.insert(intf.addr.clone());
        })
        .or_insert_with(|| MyIntf {
            name: intf.name.clone(),
            index: if_index,
            addrs: HashSet::from([intf.addr.clone()]),
            max_packet_size_v4: MAX_PKT_DEFAULT,
            max_packet_size_v6: MAX_PKT_DEFAULT,
        });

    true
}

/// Creates a socket for sending and receiving multicast packets on `addr`.
/// Works for both IPv4 and IPv6.
///
/// Failing to set the multicast TTL is only logged, since the socket still
/// works with the OS default.
fn new_multicast_socket(addr: SocketAddr) -> Result<MyUdpSocket> {
    let sock = new_socket(addr, true)?;

    // Per RFC 6762 section 11:
    // "All Multicast DNS responses (including responses sent via unicast) SHOULD
    // be sent with IP TTL set to 255."
    // Here we set the TTL to 255 for multicast as we don't support unicast yet.
    let ttl_result = match addr {
        SocketAddr::V4(_) => sock.set_multicast_ttl_v4(255),
        SocketAddr::V6(_) => sock.set_multicast_hops_v6(255),
    };
    if let Err(e) = ttl_result {
        debug!("failed to set multicast TTL on {addr}: {e}");
    }

    // This clones the socket.
    MyUdpSocket::new(sock).map_err(|e| e_fmt!("create MyUdpSocket for {}: {}", addr, e))
}

impl Zeroconf {
    fn new(waker: Arc<Waker>, poller: Poll, port: u16, cmd_sender: Sender<Command>) -> Self {
        // Get interfaces.
        let my_ifaddrs = my_ip_interfaces(true);

        // Create a socket for every IP addr.
        // Note: it is possible that `my_ifaddrs` contains the same IP addr with different interface names,
        // or the same interface name with different IP addrs.
        let mut my_intfs = HashMap::new();
        let mut dns_registry_map = HashMap::new();

        // Use the same socket for receiving and sending multicast packets.
        // Such socket has to bind to INADDR_ANY or IN6ADDR_ANY.
        let addr = SocketAddrV4::new(Ipv4Addr::new(0, 0, 0, 0), port);
        let ipv4_sock = new_multicast_socket(addr.into());
        if let Err(e) = &ipv4_sock {
            debug!("failed to set up IPv4 socket: {e}");
        }
        let ipv4_sock = ipv4_sock.ok();

        let addr = SocketAddrV6::new(Ipv6Addr::new(0, 0, 0, 0, 0, 0, 0, 0), port, 0, 0);
        let ipv6_sock = new_multicast_socket(addr.into());
        if let Err(e) = &ipv6_sock {
            debug!("failed to set up IPv6 socket: {e}");
        }
        let ipv6_sock = ipv6_sock.ok();

        // Configure sockets to join multicast groups.
        for intf in my_ifaddrs {
            let sock_opt = if intf.ip().is_ipv4() {
                &ipv4_sock
            } else {
                &ipv6_sock
            };
            let Some(sock) = sock_opt else {
                debug!(
                    "no socket available for interface {} with addr {}. Skipped.",
                    intf.name,
                    intf.ip()
                );
                continue;
            };

            if add_intf_addr(&mut my_intfs, &sock.pktinfo, &intf) {
                dns_registry_map
                    .entry(intf.index.unwrap_or(0))
                    .or_insert_with(DnsRegistry::new);
            }
        }

        let monitors = Vec::new();
        let service_name_len_max = SERVICE_NAME_LEN_MAX_DEFAULT;
        let ip_check_interval = IP_CHECK_INTERVAL_IN_SECS_DEFAULT as u64 * 1000;

        let timers = BinaryHeap::new();

        // Enable everything, including loopback interfaces.
        let if_selections = vec![];

        let status = DaemonStatus::Running;

        Self {
            port,
            my_intfs,
            ipv4_sock,
            ipv6_sock,
            my_services: HashMap::new(),
            cache: DnsCache::new(),
            dns_registry_map,
            hostname_resolvers: HashMap::new(),
            service_queriers: HashMap::new(),
            retransmissions: Vec::new(),
            delayed_responses: Vec::new(),
            counters: HashMap::new(),
            poller,
            monitors,
            service_name_len_max,
            ip_check_interval,
            next_ip_check: None,
            max_packet_sizes: Vec::new(),
            if_selections,
            timers,
            status,
            pending_resolves: HashSet::new(),
            resolved: HashSet::new(),
            multicast_loop_v4: true,
            multicast_loop_v6: true,
            accept_unsolicited: false,
            include_apple_p2p: false,
            cmd_sender,
            waker,

            #[cfg(test)]
            test_down_interfaces: HashSet::new(),
        }
    }

    /// Send a command into the daemon channel and wake the poll loop.
    ///
    /// Callers inside the command-drain loop would observe the command on
    /// the next `try_recv`, but this also runs after that drain (for example
    /// while sending a delayed response). Skipping the wake would leave the
    /// command queued until some later socket event or timer.
    fn send_cmd_to_self(&self, cmd: Command) -> Result<()> {
        enqueue_and_wake(&self.cmd_sender, &self.waker, cmd)
    }

    fn clear_service_retransmissions(&mut self, ty_domain: &str) {
        self.retransmissions
            .retain(|r| !matches!(&r.command, Command::Browse(t, _, _, _) if t == ty_domain));
    }

    fn clear_hostname_retransmissions(&mut self, hostname: &str) {
        let key = hostname.to_lowercase();
        self.retransmissions.retain(|r| {
            !matches!(
                &r.command,
                Command::ResolveHostname(h, _, _, _) if h.to_lowercase() == key
            )
        });
    }

    fn remove_service_subscription(&mut self, ty_domain: &str) -> Option<Sender<ServiceEvent>> {
        let sender = self.service_queriers.remove(ty_domain);
        self.clear_service_retransmissions(ty_domain);
        sender
    }

    fn remove_hostname_subscription(
        &mut self,
        hostname: &str,
    ) -> Option<(Sender<HostnameResolutionEvent>, Option<Instant>)> {
        let key = hostname.to_lowercase();
        let entry = self.hostname_resolvers.remove(&key);
        self.clear_hostname_retransmissions(&key);
        entry
    }

    fn service_live(&self, ty_domain: &str, sender: &Sender<ServiceEvent>) -> bool {
        self.service_queriers
            .get(ty_domain)
            .is_some_and(|s| s.same_channel(sender))
    }

    fn hostname_live(&self, hostname: &str, sender: &Sender<HostnameResolutionEvent>) -> bool {
        self.hostname_resolvers
            .get(&hostname.to_lowercase())
            .is_some_and(|(s, _)| s.same_channel(sender))
    }

    fn push_service(&mut self, ty_domain: &str, event: ServiceEvent) {
        let Some(sender) = self.service_queriers.get(ty_domain).cloned() else {
            return;
        };
        match sender.try_send(event) {
            Ok(()) => {}
            Err(TrySendError::Full(_)) => {
                debug!(
                    "subscription closed: event channel full for service type {}",
                    ty_domain
                );
                self.remove_service_subscription(ty_domain);
            }
            Err(TrySendError::Disconnected(_)) => {
                self.remove_service_subscription(ty_domain);
            }
        }
    }

    fn push_hostname(&mut self, hostname: &str, event: HostnameResolutionEvent) {
        let key = hostname.to_lowercase();
        let Some((sender, _)) = self.hostname_resolvers.get(&key).cloned() else {
            return;
        };
        match sender.try_send(event) {
            Ok(()) => {}
            Err(TrySendError::Full(_)) => {
                debug!(
                    "subscription closed: event channel full for hostname {}",
                    hostname
                );
                self.remove_hostname_subscription(&key);
            }
            Err(TrySendError::Disconnected(_)) => {
                self.remove_hostname_subscription(&key);
            }
        }
    }

    fn expire_hostname_resolvers(&mut self, now: Instant) {
        let expired: Vec<String> = self
            .hostname_resolvers
            .iter()
            .filter(|(_, (_, timeout))| timeout.map(|t| now >= t).unwrap_or(false))
            .map(|(hostname, _)| hostname.clone())
            .collect();
        for hostname in expired {
            trace!("hostname resolver timeout for {}", hostname);
            if let Some((sender, _)) = self.remove_hostname_subscription(&hostname) {
                let _ = sender.try_send(HostnameResolutionEvent::SearchTimeout(hostname.clone()));
                let _ = sender.try_send(HostnameResolutionEvent::SearchStopped(hostname));
            }
        }
    }

    /// Clean up all resources before shutdown.
    ///
    /// This method:
    /// 1. Unregisters all registered services (sends goodbye packets)
    /// 2. Stops all active browse operations
    /// 3. Stops all active hostname resolution operations
    /// 4. Clears all retransmissions
    /// 5. Drops all pending delayed responses
    fn cleanup(&mut self) {
        debug!("Starting cleanup for shutdown");

        // 1. Unregister all services - send goodbye packets
        let service_names: Vec<String> = self.my_services.keys().cloned().collect();
        for fullname in service_names {
            if let Some(info) = self.my_services.get(&fullname) {
                debug!("Unregistering service during shutdown: {}", fullname);

                for intf in self.my_intfs.values() {
                    if let Some(sock) = self.ipv4_sock.as_ref() {
                        self.unregister_service(info, intf, &sock.pktinfo);
                    }

                    if let Some(sock) = self.ipv6_sock.as_ref() {
                        self.unregister_service(info, intf, &sock.pktinfo);
                    }
                }
            }
        }
        self.my_services.clear();

        // 2. Stop all browse operations
        let browse_types: Vec<String> = self.service_queriers.keys().cloned().collect();
        for ty_domain in browse_types {
            debug!("Stopping browse during shutdown: {}", ty_domain);
            if let Some(sender) = self.service_queriers.remove(&ty_domain) {
                // Notify the client
                if let Err(e) = sender.try_send(ServiceEvent::SearchStopped(ty_domain.clone())) {
                    debug!("Failed to send SearchStopped during shutdown: {}", e);
                }
            }
        }

        // 3. Stop all hostname resolution operations
        let hostnames: Vec<String> = self.hostname_resolvers.keys().cloned().collect();
        for hostname in hostnames {
            debug!("Stopping hostname resolution during shutdown: {}", hostname);
            if let Some((sender, _timeout)) = self.hostname_resolvers.remove(&hostname) {
                // Notify the client
                if let Err(e) =
                    sender.try_send(HostnameResolutionEvent::SearchStopped(hostname.clone()))
                {
                    debug!(
                        "Failed to send HostnameResolutionEvent::SearchStopped during shutdown: {}",
                        e
                    );
                }
            }
        }

        // 4. Clear all retransmissions
        self.retransmissions.clear();

        // 5. Drop any pending delayed responses
        self.delayed_responses.clear();

        debug!("Cleanup completed");
    }

    /// The main event loop of the daemon thread
    ///
    /// In each round, it will:
    /// 1. select the listening sockets with a timeout.
    /// 2. process the incoming packets if any.
    /// 3. try_recv on its channel and execute commands.
    /// 4. announce its registered services.
    /// 5. process retransmissions if any.
    fn run(&mut self, receiver: Receiver<Command>) -> Option<Command> {
        // The `Waker` is already registered with this poller.
        if let Some(sock) = self.ipv4_sock.as_mut() {
            if let Err(e) = self.poller.registry().register(
                sock,
                mio::Token(IPV4_SOCK_EVENT_KEY),
                mio::Interest::READABLE,
            ) {
                debug!("failed to register ipv4 socket: {}", e);
                return None;
            }
        }

        if let Some(sock) = self.ipv6_sock.as_mut() {
            if let Err(e) = self.poller.registry().register(
                sock,
                mio::Token(IPV6_SOCK_EVENT_KEY),
                mio::Interest::READABLE,
            ) {
                debug!("failed to register ipv6 socket: {}", e);
                return None;
            }
        }

        // Setup timer for IP checks.
        self.schedule_ip_check(Instant::now());

        // Both clocks as of the previous iteration, to detect system sleep.
        let mut last_now = Instant::now();
        let mut last_wall_now = SystemTime::now();

        // Start the run loop.

        let mut events = mio::Events::with_capacity(1024);
        loop {
            let now = Instant::now();

            let earliest_timer = self.peek_earliest_timer();
            let timeout = earliest_timer.map(|timer| {
                // If `timer` already passed, set `timeout` to be 1ms.
                timer
                    .saturating_duration_since(now)
                    .max(Duration::from_millis(1))
            });

            // Process incoming packets, command events and optional timeout.
            events.clear();
            match self.poller.poll(&mut events, timeout) {
                Ok(_) => self.handle_poller_events(&events),
                Err(e) => debug!("failed to select from sockets: {}", e),
            }

            let now = Instant::now();

            // Count the time the system slept toward the cached records' TTLs.
            let wall_now = SystemTime::now();
            if let Some(slept) = slept_duration(
                now.saturating_duration_since(last_now),
                wall_now.duration_since(last_wall_now).ok(),
            ) {
                debug!("system slept for about {:?}: aging cached records", slept);
                self.cache.age_records(slept);
            }
            last_now = now;
            last_wall_now = wall_now;

            // Remove the timers if already passed.
            self.pop_timers_till(now);

            // Remove hostname resolvers with expired timeouts.
            self.expire_hostname_resolvers(now);

            // process commands from the command channel
            while let Ok(command) = receiver.try_recv() {
                if matches!(command, Command::Exit(_)) {
                    debug!("Exit command received, performing cleanup");
                    self.cleanup();
                    self.status = DaemonStatus::Shutdown;
                    return Some(command);
                }
                self.exec_command(command, false);
            }

            // check for repeated commands and run them if their time is up.
            let mut i = 0;
            while i < self.retransmissions.len() {
                if now >= self.retransmissions[i].next_time {
                    let rerun = self.retransmissions.remove(i);
                    self.exec_command(rerun.command, true);
                } else {
                    i += 1;
                }
            }

            // Send delayed responses whose time is up (RFC 6762 §6).
            let mut i = 0;
            while i < self.delayed_responses.len() {
                if now >= self.delayed_responses[i].next_time {
                    let resp = self.delayed_responses.remove(i);
                    self.send_delayed_response(resp);
                } else {
                    i += 1;
                }
            }

            // Refresh cached service records with active queriers
            self.refresh_active_services();

            // Refresh cached A/AAAA records with active queriers
            let mut query_count = 0;
            for hostname in self.hostname_resolvers.keys() {
                for (hostname, ip_addr) in
                    self.cache.refresh_due_hostname_resolutions(hostname).iter()
                {
                    self.send_query(hostname, ip_address_rr_type(&ip_addr.to_ip_addr()));
                    query_count += 1;
                }
            }

            self.increase_counter(Counter::CacheRefreshAddr, query_count);

            // check and evict expired records in our cache
            let now = Instant::now();

            // Notify service listeners about the expired records.
            let expired_services = self.cache.evict_expired_services(now);
            if !expired_services.is_empty() {
                debug!(
                    "run: send {} service removal to listeners",
                    expired_services.len()
                );
                self.notify_service_removal(expired_services);
            }

            // Notify hostname listeners about the expired records.
            let expired_addrs = self.cache.evict_expired_addr(now);
            for (hostname, addrs) in expired_addrs {
                self.push_hostname(
                    &hostname,
                    HostnameResolutionEvent::AddressesRemoved(hostname.clone(), addrs),
                );
                let instances = self.cache.get_instances_on_host(&hostname);
                let instance_set: HashSet<String> = instances.into_iter().collect();
                self.resolve_updated_instances(&instance_set);
            }

            // Send out probing queries.
            self.probing_handler();

            // check IP changes if next_ip_check is reached.
            if self.next_ip_check.is_some_and(|t| now >= t) {
                self.schedule_ip_check(now);
                self.check_ip_changes();
            }
        }
    }

    fn process_set_option(&mut self, daemon_opt: DaemonOption) {
        match daemon_opt {
            DaemonOption::ServiceNameLenMax(length) => self.service_name_len_max = length,
            DaemonOption::IpCheckInterval(interval) => {
                self.ip_check_interval = interval;
                self.schedule_ip_check(Instant::now());
            }
            DaemonOption::MaxPacketSize(if_kind, size) => self.set_max_packet_size(if_kind, size),
            DaemonOption::EnableInterface(if_kind) => self.enable_interface(if_kind),
            DaemonOption::DisableInterface(if_kind) => self.disable_interface(if_kind),
            DaemonOption::MulticastLoopV4(on) => self.set_multicast_loop_v4(on),
            DaemonOption::MulticastLoopV6(on) => self.set_multicast_loop_v6(on),
            DaemonOption::AcceptUnsolicited(accept) => self.set_accept_unsolicited(accept),
            DaemonOption::IncludeAppleP2P(enable) => self.set_apple_p2p(enable),
            #[cfg(test)]
            DaemonOption::TestDownInterface(ifname) => {
                self.test_down_interfaces.insert(ifname);
            }
            #[cfg(test)]
            DaemonOption::TestUpInterface(ifname) => {
                self.test_down_interfaces.remove(&ifname);
            }
        }
    }

    fn enable_interface(&mut self, kinds: Vec<IfKind>) {
        debug!("enable_interface: {:?}", kinds);
        let interfaces = my_ip_interfaces_inner(true, self.include_apple_p2p);

        for if_kind in kinds {
            self.if_selections.push(IfSelection {
                if_kind: resolve_addr_to_index(if_kind, &interfaces),
                selected: true,
            });
        }

        self.apply_intf_selections(interfaces);
    }

    fn disable_interface(&mut self, kinds: Vec<IfKind>) {
        debug!("disable_interface: {:?}", kinds);
        let interfaces = my_ip_interfaces_inner(true, self.include_apple_p2p);

        for if_kind in kinds {
            self.if_selections.push(IfSelection {
                if_kind: resolve_addr_to_index(if_kind, &interfaces),
                selected: false,
            });
        }

        self.apply_intf_selections(interfaces);
    }

    fn set_max_packet_size(&mut self, kinds: Vec<IfKind>, size: usize) {
        debug!("set_max_packet_size: {:?} {}", kinds, size);
        let interfaces = my_ip_interfaces_inner(true, self.include_apple_p2p);

        for if_kind in kinds {
            self.max_packet_sizes.push(MaxPacketSizeSelection {
                if_kind: resolve_addr_to_index(if_kind, &interfaces),
                max_packet_size: size,
            });
        }

        self.apply_max_packet_sizes(&interfaces);
    }

    /// Resolve all max packet size selections against `interfaces` and store the
    /// outcome in every interface in `my_intfs`.
    fn apply_max_packet_sizes(&mut self, interfaces: &[Interface]) {
        for (if_index, my_intf) in self.my_intfs.iter_mut() {
            let v4 = resolve_max_packet_size(&self.max_packet_sizes, interfaces, *if_index, true);
            let v6 = resolve_max_packet_size(&self.max_packet_sizes, interfaces, *if_index, false);

            if my_intf.max_packet_size_v4 != v4 || my_intf.max_packet_size_v6 != v6 {
                debug!(
                    "interface {}: max packet size v4 {} -> {v4}, v6 {} -> {v6}",
                    my_intf.name, my_intf.max_packet_size_v4, my_intf.max_packet_size_v6
                );
                my_intf.max_packet_size_v4 = v4;
                my_intf.max_packet_size_v6 = v6;
            }
        }
    }

    fn set_multicast_loop_v4(&mut self, on: bool) {
        let Some(sock) = self.ipv4_sock.as_mut() else {
            return;
        };
        self.multicast_loop_v4 = on;
        sock.pktinfo
            .set_multicast_loop_v4(on)
            .map_err(|e| e_fmt!("failed to set multicast loop v4: {}", e))
            .unwrap();
    }

    fn set_multicast_loop_v6(&mut self, on: bool) {
        let Some(sock) = self.ipv6_sock.as_mut() else {
            return;
        };
        self.multicast_loop_v6 = on;
        sock.pktinfo
            .set_multicast_loop_v6(on)
            .map_err(|e| e_fmt!("failed to set multicast loop v6: {}", e))
            .unwrap();
    }

    fn set_accept_unsolicited(&mut self, accept: bool) {
        self.accept_unsolicited = accept;
    }

    fn set_apple_p2p(&mut self, include: bool) {
        if self.include_apple_p2p != include {
            self.include_apple_p2p = include;
            self.apply_intf_selections(my_ip_interfaces_inner(true, self.include_apple_p2p));
        }
    }

    fn notify_monitors(&mut self, event: DaemonEvent) {
        // Only retain the monitors that are still connected.
        self.monitors.retain(|sender| {
            if let Err(e) = sender.try_send(event.clone()) {
                debug!("notify_monitors: try_send: {}", e);
                if matches!(e, TrySendError::Disconnected(_)) {
                    return false; // This monitor is dropped.
                }
            }
            true
        });
    }

    /// Remove `addr` in my services that enabled `addr_auto`.
    fn del_addr_in_my_services(&mut self, addr: &IpAddr) {
        for service_info in self.my_services.values_mut() {
            if service_info.is_addr_auto() {
                service_info.remove_ipaddr(addr);
            }
        }
    }

    /// Schedules the next IP check one `ip_check_interval` after `now`, or
    /// disables it if the interval is 0.
    fn schedule_ip_check(&mut self, now: Instant) {
        self.next_ip_check = (self.ip_check_interval > 0)
            .then(|| now + Duration::from_millis(self.ip_check_interval));
        if let Some(t) = self.next_ip_check {
            self.add_timer(t);
        }
    }

    fn add_timer(&mut self, next_time: Instant) {
        self.timers.push(Reverse(next_time));
    }

    fn peek_earliest_timer(&self) -> Option<Instant> {
        self.timers.peek().map(|Reverse(v)| *v)
    }

    fn _pop_earliest_timer(&mut self) -> Option<Instant> {
        self.timers.pop().map(|Reverse(v)| v)
    }

    /// Pop all timers that are already passed till `now`.
    fn pop_timers_till(&mut self, now: Instant) {
        while let Some(Reverse(v)) = self.timers.peek() {
            if *v > now {
                break;
            }
            self.timers.pop();
        }
    }

    /// Apply all selections to `interfaces` and return the selected addresses.
    fn selected_intfs(&self, interfaces: Vec<Interface>) -> HashSet<Interface> {
        let intf_count = interfaces.len();
        let mut intf_selections = vec![true; intf_count];

        // apply if_selections
        for selection in self.if_selections.iter() {
            // Mark the interfaces for this selection.
            for i in 0..intf_count {
                if selection.if_kind.matches(&interfaces[i]) {
                    intf_selections[i] = selection.selected;
                }
            }
        }

        let mut selected_addrs = HashSet::new();
        for i in 0..intf_count {
            if intf_selections[i] {
                selected_addrs.insert(interfaces[i].clone());
            }
        }

        selected_addrs
    }

    /// Apply all selections to `interfaces`.
    ///
    /// For any interface, add it if selected but not bound yet,
    /// delete it if not selected but still bound.
    fn apply_intf_selections(&mut self, interfaces: Vec<Interface>) {
        // By default, we enable all interfaces.
        let intf_count = interfaces.len();
        let mut intf_selections = vec![true; intf_count];

        // apply if_selections
        for selection in self.if_selections.iter() {
            // Mark the interfaces for this selection.
            for i in 0..intf_count {
                if selection.if_kind.matches(&interfaces[i]) {
                    intf_selections[i] = selection.selected;
                }
            }
        }

        // Update `my_intfs` based on the selections.
        for (idx, intf) in interfaces.iter().enumerate() {
            if intf_selections[idx] {
                // Add the interface
                self.add_interface(intf, &interfaces);
            } else {
                // Remove the interface
                self.del_interface_addr(intf);
            }
        }

        // An interface that lost an address may now match a different selection.
        // (`add_interface` already resolved the ones that gained one.)
        self.apply_max_packet_sizes(&interfaces);
    }

    fn del_ip(&mut self, ip: IpAddr) {
        self.del_addr_in_my_services(&ip);
        self.notify_monitors(DaemonEvent::IpDel(ip));
    }

    /// Check for IP changes and update [my_intfs] as needed.
    fn check_ip_changes(&mut self) {
        // Get the current interfaces.
        let my_ifaddrs = my_ip_interfaces_inner(true, self.include_apple_p2p);

        #[cfg(test)]
        let my_ifaddrs: Vec<_> = my_ifaddrs
            .into_iter()
            .filter(|intf| !self.test_down_interfaces.contains(&intf.name))
            .collect();

        let ifaddrs_map: HashMap<u32, Vec<&IfAddr>> =
            my_ifaddrs.iter().fold(HashMap::new(), |mut acc, intf| {
                let if_index = intf.index.unwrap_or(0);
                acc.entry(if_index).or_default().push(&intf.addr);
                acc
            });

        let mut deleted_intfs = Vec::new();
        let mut deleted_ips = Vec::new();

        for (if_index, my_intf) in self.my_intfs.iter_mut() {
            let mut last_ipv4 = None;
            let mut last_ipv6 = None;

            if let Some(current_addrs) = ifaddrs_map.get(if_index) {
                my_intf.addrs.retain(|addr| {
                    if current_addrs.contains(&addr) {
                        true
                    } else {
                        match addr.ip() {
                            IpAddr::V4(ipv4) => last_ipv4 = Some(ipv4),
                            IpAddr::V6(ipv6) => last_ipv6 = Some(ipv6),
                        }
                        deleted_ips.push(addr.ip());
                        false
                    }
                });
                if my_intf.addrs.is_empty() {
                    deleted_intfs.push((*if_index, last_ipv4, last_ipv6))
                }
            } else {
                // If it does not exist, remove the interface.
                debug!(
                    "check_ip_changes: interface {} ({}) no longer exists, removing",
                    my_intf.name, if_index
                );
                for addr in my_intf.addrs.iter() {
                    match addr.ip() {
                        IpAddr::V4(ipv4) => last_ipv4 = Some(ipv4),
                        IpAddr::V6(ipv6) => last_ipv6 = Some(ipv6),
                    }
                    deleted_ips.push(addr.ip())
                }
                deleted_intfs.push((*if_index, last_ipv4, last_ipv6));
            }
        }

        if !deleted_ips.is_empty() || !deleted_intfs.is_empty() {
            debug!(
                "check_ip_changes: {} deleted ips {} deleted intfs",
                deleted_ips.len(),
                deleted_intfs.len()
            );
        }

        for (if_index, last_ipv4, last_ipv6) in deleted_intfs {
            let Some(my_intf) = self.my_intfs.remove(&if_index) else {
                continue;
            };

            if let Some(ipv4) = last_ipv4 {
                if self.intfs_with_ip(&IpAddr::V4(ipv4)).next().is_some() {
                    // Leaving by address would drop the membership the other interface uses.
                    debug!("keep multicast for {ipv4}: still used by another interface");
                } else if let Some(sock) = self.ipv4_sock.as_mut() {
                    debug!("leave multicast for {ipv4}");
                    if let Err(e) = sock.pktinfo.leave_multicast_v4(&GROUP_ADDR_V4, &ipv4) {
                        debug!("leave multicast group for addr {ipv4}: {e}");
                    }
                }
            }

            if let Some(ipv6) = last_ipv6 {
                debug!("leave multicast for {ipv6}");
                if let Some(sock) = self.ipv6_sock.as_mut() {
                    if let Err(e) = sock
                        .pktinfo
                        .leave_multicast_v6(&GROUP_ADDR_V6, my_intf.index)
                    {
                        debug!("leave multicast group for IPv6: {ipv6}: {e}");
                    }
                }
            }

            // Remove cache records for this interface.
            let intf_id = InterfaceId {
                name: my_intf.name.to_string(),
                index: my_intf.index,
            };
            let result = self.cache.remove_records_on_intf(intf_id);
            self.notify_service_removal(result.removed_instances);
            self.resolve_updated_instances(&result.modified_instances);
        }

        // Handled after the removals above, so that `my_intfs` shows which of
        // these addresses are still on another interface.
        deleted_ips.sort();
        deleted_ips.dedup();
        for ip in deleted_ips {
            if self.intfs_with_ip(&ip).next().is_none() {
                self.del_ip(ip);
                continue;
            }

            // The address is still on another interface. The removed interface may
            // have been the one holding the shared IPv4 membership, which the kernel
            // drops with it, so join again (a no-op if the membership survived).
            if let (IpAddr::V4(ipv4), Some(sock)) = (ip, self.ipv4_sock.as_ref()) {
                if let Err(e) = join_multicast_v4(&sock.pktinfo, &ipv4) {
                    debug!("check_ip_changes: rejoin multicast group on addr {ipv4}: {e}");
                }
            }
        }

        // Add newly found interfaces only if in our selections.
        self.apply_intf_selections(my_ifaddrs);
    }

    /// Remove an interface address when it was down, disabled or removed from the system.
    /// If no more addresses on the interface, remove the interface as well.
    fn del_interface_addr(&mut self, intf: &Interface) {
        let if_index = intf.index.unwrap_or(0);
        debug!(
            "del_interface_addr: {} ({if_index}) addr {}",
            intf.name,
            intf.ip()
        );

        // Another interface with the same address still serves it, and shares its
        // IPv4 membership, e.g. the `bridge1NN` and `vmenetN` pairs of VMs on macOS.
        let shared = self.intfs_with_ip(&intf.ip()).any(|i| i != if_index);

        let Some(my_intf) = self.my_intfs.get_mut(&if_index) else {
            debug!("del_interface_addr: interface {} not found", intf.name);
            return;
        };

        let mut ip_removed = false;

        if my_intf.addrs.remove(&intf.addr) {
            ip_removed = true;

            match intf.addr.ip() {
                IpAddr::V4(ipv4) => {
                    if shared {
                        debug!("keep multicast for {ipv4}: still used by another interface");
                    } else if my_intf.next_ifaddr_v4().is_none() {
                        if let Some(sock) = self.ipv4_sock.as_mut() {
                            if let Err(e) = sock.pktinfo.leave_multicast_v4(&GROUP_ADDR_V4, &ipv4) {
                                debug!("leave multicast group for addr {ipv4}: {e}");
                            } else {
                                debug!("leave multicast for {ipv4}");
                            }
                        }
                    }
                }

                IpAddr::V6(ipv6) => {
                    if my_intf.next_ifaddr_v6().is_none() {
                        if let Some(sock) = self.ipv6_sock.as_mut() {
                            if let Err(e) =
                                sock.pktinfo.leave_multicast_v6(&GROUP_ADDR_V6, if_index)
                            {
                                debug!("leave multicast group for addr {ipv6}: {e}");
                            }
                        }
                    }
                }
            }

            if my_intf.addrs.is_empty() {
                // If no more addresses, remove the interface.
                debug!("del_interface_addr: removing interface {}", intf.name);
                self.my_intfs.remove(&if_index);
                self.dns_registry_map.remove(&if_index);
                self.cache
                    .remove_addrs_on_disabled_intf(if_index, IpType::BOTH);
            } else {
                // Interface still has addresses of the other IP version.
                // Remove cached address records for the disabled IP version
                // only if no more addresses of that version remain.
                let is_v4 = intf.addr.ip().is_ipv4();
                let version_gone = if is_v4 {
                    my_intf.next_ifaddr_v4().is_none()
                } else {
                    my_intf.next_ifaddr_v6().is_none()
                };
                if version_gone {
                    let ip_type = if is_v4 { IpType::V4 } else { IpType::V6 };
                    self.cache.remove_addrs_on_disabled_intf(if_index, ip_type);
                }
            }
        }

        if ip_removed && !shared {
            // Notify the monitors.
            self.notify_monitors(DaemonEvent::IpDel(intf.ip()));
            // Remove the interface from my services that enabled `addr_auto`.
            self.del_addr_in_my_services(&intf.ip());
        }
    }

    /// Indexes of the interfaces in `my_intfs` that have `ip`.
    fn intfs_with_ip<'a>(&'a self, ip: &'a IpAddr) -> impl Iterator<Item = u32> + 'a {
        self.my_intfs
            .values()
            .filter(move |my_intf| my_intf.addrs.iter().any(|addr| addr.ip() == *ip))
            .map(|my_intf| my_intf.index)
    }

    /// Adds the address of `intf` and brings our services up on it.
    ///
    /// Note: this `interface` type only contains one address.
    ///
    /// Does nothing if the address is already known, or if joining the multicast
    /// group fails (see `add_intf_addr`). Otherwise, for each `addr_auto` service, it adds
    /// the address (when supported) and announces the service, marking it as
    /// probing when it cannot be announced yet. It then re-sends the active
    /// browse queries on the new interface and notifies monitors with
    /// `DaemonEvent::IpAdd`.
    ///
    /// `interfaces` is the full list the caller is applying, needed to resolve the
    /// max packet size of the interface before we send anything on it.
    fn add_interface(&mut self, intf: &Interface, interfaces: &[Interface]) {
        let sock_opt = if intf.ip().is_ipv4() {
            &self.ipv4_sock
        } else {
            &self.ipv6_sock
        };

        let Some(sock) = sock_opt else {
            debug!(
                "add_interface: no socket available for interface {} with addr {}. Skipped.",
                intf.name,
                intf.ip()
            );
            return;
        };

        if !add_intf_addr(&mut self.my_intfs, &sock.pktinfo, intf) {
            return;
        }

        let if_index = intf.index.unwrap_or(0);

        debug!("add new interface {}: {}", intf.name, intf.ip());

        // Resolve before announcing, so the first packet out already honors it.
        let v4 = resolve_max_packet_size(&self.max_packet_sizes, interfaces, if_index, true);
        let v6 = resolve_max_packet_size(&self.max_packet_sizes, interfaces, if_index, false);
        if let Some(my_intf) = self.my_intfs.get_mut(&if_index) {
            my_intf.max_packet_size_v4 = v4;
            my_intf.max_packet_size_v6 = v6;
        }

        let Some(my_intf) = self.my_intfs.get(&if_index) else {
            debug!("add_interface: cannot find if_index {if_index}");
            return;
        };

        let dns_registry = match self.dns_registry_map.get_mut(&if_index) {
            Some(registry) => registry,
            None => self
                .dns_registry_map
                .entry(if_index)
                .or_insert_with(DnsRegistry::new),
        };

        for service_info in self.my_services.values_mut() {
            if service_info.is_addr_auto() {
                if !service_info.insert_ipaddr(intf) {
                    // Skip an unsupported address. Should not try to announce it.
                    // Otherwise could demote an already announced service into probing.
                    continue;
                }

                if let Ok(true) = announce_service_on_intf(
                    dns_registry,
                    service_info,
                    my_intf,
                    &sock.pktinfo,
                    self.port,
                ) {
                    debug!(
                        "Announce service {} on {}",
                        service_info.get_fullname(),
                        intf.ip()
                    );
                    service_info.set_status(if_index, ServiceStatus::Announced);
                } else {
                    for timer in dns_registry.new_timers.drain(..) {
                        self.timers.push(Reverse(timer));
                    }
                    service_info.set_status(if_index, ServiceStatus::Probing);
                }
            }
        }

        // Send browse queries on the new interface without known answers.
        // This avoids known-answer suppression (RFC 6762 Section 7.1) that
        // would cause the responder to suppress its response, preventing
        // address records from being attributed to the new interface.
        if let Some(my_intf) = self.my_intfs.get(&if_index) {
            for ty in self.service_queriers.keys() {
                self.send_query_on_intf(ty, RRType::PTR, my_intf);
            }
        }

        // Notify the monitors.
        self.notify_monitors(DaemonEvent::IpAdd(intf.ip()));
    }

    /// Registers a service.
    ///
    /// RFC 6762 section 8.3.
    /// ...the Multicast DNS responder MUST send
    ///    an unsolicited Multicast DNS response containing, in the Answer
    ///    Section, all of its newly registered resource records
    ///
    /// Zeroconf will then respond to requests for information about this service.
    fn register_service(&mut self, mut info: ServiceInfo) {
        // Check the service name length.
        if let Err(e) = check_service_name_length(info.get_type(), self.service_name_len_max) {
            error!("check_service_name_length: {}", e);
            self.notify_monitors(DaemonEvent::Error(e));
            return;
        }

        if info.is_addr_auto() {
            let selected_intfs =
                self.selected_intfs(my_ip_interfaces_inner(true, self.include_apple_p2p));
            for intf in selected_intfs {
                info.insert_ipaddr(&intf);
            }
        }

        debug!("register service {:?}", info);

        let outgoing_addrs = self.send_unsolicited_response(&mut info);
        if !outgoing_addrs.is_empty() {
            self.notify_monitors(DaemonEvent::Announce(
                info.get_fullname().to_string(),
                format!("{:?}", outgoing_addrs),
            ));
        }

        // The key has to be lower case letter as DNS record name is case insensitive.
        // The info will have the original name.
        let service_fullname = info.get_fullname().to_lowercase();
        self.my_services.insert(service_fullname, info);
    }

    /// Sends out announcement of `info` on every valid interface.
    /// Returns the list of interface IPs that sent out the announcement.
    fn send_unsolicited_response(&mut self, info: &mut ServiceInfo) -> Vec<IpAddr> {
        let mut outgoing_addrs = Vec::new();
        let mut outgoing_intfs = HashSet::new();

        let mut invalid_intf_addrs = HashSet::new();

        for (if_index, intf) in self.my_intfs.iter() {
            let dns_registry = match self.dns_registry_map.get_mut(if_index) {
                Some(registry) => registry,
                None => self
                    .dns_registry_map
                    .entry(*if_index)
                    .or_insert_with(DnsRegistry::new),
            };

            let mut announced = false;

            // IPv4
            if let Some(sock) = self.ipv4_sock.as_mut() {
                match announce_service_on_intf(dns_registry, info, intf, &sock.pktinfo, self.port) {
                    Ok(true) => {
                        for addr in intf.addrs.iter().filter(|a| a.ip().is_ipv4()) {
                            outgoing_addrs.push(addr.ip());
                        }
                        outgoing_intfs.insert(intf.index);

                        debug!(
                            "Announce service IPv4 {} on {}",
                            info.get_fullname(),
                            intf.name
                        );
                        announced = true;
                    }
                    Ok(false) => {}
                    Err(InternalError::IntfAddrInvalid(intf_addr)) => {
                        invalid_intf_addrs.insert(intf_addr);
                    }
                }
            }

            if let Some(sock) = self.ipv6_sock.as_mut() {
                match announce_service_on_intf(dns_registry, info, intf, &sock.pktinfo, self.port) {
                    Ok(true) => {
                        for addr in intf.addrs.iter().filter(|a| a.ip().is_ipv6()) {
                            outgoing_addrs.push(addr.ip());
                        }
                        outgoing_intfs.insert(intf.index);

                        debug!(
                            "Announce service IPv6 {} on {}",
                            info.get_fullname(),
                            intf.name
                        );
                        announced = true;
                    }
                    Ok(false) => {}
                    Err(InternalError::IntfAddrInvalid(intf_addr)) => {
                        invalid_intf_addrs.insert(intf_addr);
                    }
                }
            }

            if announced {
                info.set_status(intf.index, ServiceStatus::Announced);
            } else {
                for timer in dns_registry.new_timers.drain(..) {
                    self.timers.push(Reverse(timer));
                }
                info.set_status(*if_index, ServiceStatus::Probing);
            }
        }

        if !invalid_intf_addrs.is_empty() {
            let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addrs));
        }

        // RFC 6762 section 8.3.
        // ..The Multicast DNS responder MUST send at least two unsolicited
        //    responses, one second apart.
        let next_time = Instant::now()
            + Duration::from_millis(
                ANNOUNCE_SECOND_DELAY_MILLIS + fastrand::u64(0..ANNOUNCE_SECOND_JITTER_MILLIS),
            );
        for if_index in outgoing_intfs {
            self.add_retransmission(
                next_time,
                Command::RegisterResend(info.get_fullname().to_string(), if_index),
            );
        }

        outgoing_addrs
    }

    /// Send probings or finish them if expired. Notify waiting services.
    fn probing_handler(&mut self) {
        let now = Instant::now();
        let mut invalid_intf_addrs = HashSet::new();

        for (if_index, intf) in self.my_intfs.iter() {
            let Some(dns_registry) = self.dns_registry_map.get_mut(if_index) else {
                continue;
            };

            let (out, expired_probes) = check_probing(dns_registry, &mut self.timers, now);

            // send probing.
            if !out.questions().is_empty() {
                trace!("sending out probing of questions: {:?}", out.questions());
                if let Some(sock) = self.ipv4_sock.as_mut() {
                    if let Err(InternalError::IntfAddrInvalid(intf_addr)) =
                        send_dns_outgoing(&out, intf, &sock.pktinfo, self.port, None, None)
                    {
                        invalid_intf_addrs.insert(intf_addr);
                    }
                }
                if let Some(sock) = self.ipv6_sock.as_mut() {
                    if let Err(InternalError::IntfAddrInvalid(intf_addr)) =
                        send_dns_outgoing(&out, intf, &sock.pktinfo, self.port, None, None)
                    {
                        invalid_intf_addrs.insert(intf_addr);
                    }
                }
            }

            // For finished probes, wake up services that are waiting for the probes.
            let waiting_services =
                handle_expired_probes(expired_probes, &intf.name, dns_registry, &mut self.monitors);

            for service_name in waiting_services {
                // service names are lowercase
                if let Some(info) = self.my_services.get_mut(&service_name.to_lowercase()) {
                    if info.get_status(*if_index) == ServiceStatus::Announced {
                        debug!("service {} already announced", info.get_fullname());
                        continue;
                    }

                    let announced_v4 = if let Some(sock) = self.ipv4_sock.as_mut() {
                        match announce_service_on_intf(
                            dns_registry,
                            info,
                            intf,
                            &sock.pktinfo,
                            self.port,
                        ) {
                            Ok(announced) => announced,
                            Err(InternalError::IntfAddrInvalid(intf_addr)) => {
                                invalid_intf_addrs.insert(intf_addr);
                                false
                            }
                        }
                    } else {
                        false
                    };
                    let announced_v6 = if let Some(sock) = self.ipv6_sock.as_mut() {
                        match announce_service_on_intf(
                            dns_registry,
                            info,
                            intf,
                            &sock.pktinfo,
                            self.port,
                        ) {
                            Ok(announced) => announced,
                            Err(InternalError::IntfAddrInvalid(intf_addr)) => {
                                invalid_intf_addrs.insert(intf_addr);
                                false
                            }
                        }
                    } else {
                        false
                    };

                    if announced_v4 || announced_v6 {
                        let next_time = now
                            + Duration::from_millis(
                                ANNOUNCE_SECOND_DELAY_MILLIS
                                    + fastrand::u64(0..ANNOUNCE_SECOND_JITTER_MILLIS),
                            );
                        let command =
                            Command::RegisterResend(info.get_fullname().to_string(), *if_index);
                        self.retransmissions.push(ReRun { next_time, command });
                        self.timers.push(Reverse(next_time));

                        let fullname = dns_registry.resolve_name(&service_name).to_string();

                        let hostname = dns_registry.resolve_name(info.get_hostname());

                        debug!("wake up: announce service {} on {}", fullname, intf.name);
                        notify_monitors(
                            &mut self.monitors,
                            DaemonEvent::Announce(fullname, format!("{}:{}", hostname, intf.name)),
                        );

                        info.set_status(*if_index, ServiceStatus::Announced);
                    }
                }
            }
        }

        if !invalid_intf_addrs.is_empty() {
            let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addrs));
        }
    }

    fn unregister_service(
        &self,
        info: &ServiceInfo,
        intf: &MyIntf,
        sock: &PktInfoUdpSocket,
    ) -> Vec<u8> {
        let is_ipv4 = sock.domain() == Domain::IPV4;

        // Goodbye records must carry the names peers actually cached: if
        // probing renamed a record on this interface, withdraw the renamed
        // name, not the original one from `ServiceInfo`.
        let (fullname, hostname) = match self.dns_registry_map.get(&intf.index) {
            Some(dns_registry) => (
                dns_registry.resolve_name(info.get_fullname()),
                dns_registry.resolve_name(info.get_hostname()),
            ),
            None => (info.get_fullname(), info.get_hostname()),
        };

        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
        out.add_answer_record(DnsPointer::new(
            info.get_type(),
            RRType::PTR,
            CLASS_IN,
            0,
            fullname.to_string(),
        ));

        if let Some(sub) = info.get_subtype() {
            trace!("Adding subdomain {}", sub);
            out.add_answer_record(DnsPointer::new(
                sub,
                RRType::PTR,
                CLASS_IN,
                0,
                fullname.to_string(),
            ));
        }

        out.add_answer_record(DnsSrv::new(
            fullname,
            CLASS_IN | CLASS_CACHE_FLUSH,
            0,
            info.get_priority(),
            info.get_weight(),
            info.get_port(),
            hostname.to_string(),
        ));
        out.add_answer_record(DnsTxt::new(
            fullname,
            CLASS_IN | CLASS_CACHE_FLUSH,
            0,
            info.generate_txt(),
        ));

        let if_addrs = if is_ipv4 {
            info.get_addrs_on_my_intf_v4(intf)
        } else {
            info.get_addrs_on_my_intf_v6(intf)
        };

        if if_addrs.is_empty() {
            return vec![];
        }

        for address in if_addrs {
            out.add_answer_record(DnsAddress::new(
                hostname,
                ip_address_rr_type(&address),
                CLASS_IN | CLASS_CACHE_FLUSH,
                0,
                address,
                intf.into(),
            ));
        }

        // Only (at most) one packet is expected to be sent out.
        let sent_vec = match send_dns_outgoing(&out, intf, sock, self.port, None, None) {
            Ok(sent_vec) => sent_vec,
            Err(InternalError::IntfAddrInvalid(intf_addr)) => {
                let invalid_intf_addrs = HashSet::from([intf_addr]);
                let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addrs));
                vec![]
            }
        };
        sent_vec.into_iter().next().unwrap_or_default()
    }

    /// Binds a channel `listener` to querying mDNS hostnames.
    ///
    /// If there is already a `listener`, it will be updated, i.e. overwritten.
    fn add_hostname_resolver(
        &mut self,
        hostname: String,
        listener: Sender<HostnameResolutionEvent>,
        timeout: Option<u64>,
    ) {
        let real_timeout = timeout.map(|t| Instant::now() + Duration::from_millis(t));
        self.hostname_resolvers
            .insert(hostname.to_lowercase(), (listener, real_timeout));
        if let Some(t) = real_timeout {
            self.add_timer(t);
        }
    }

    /// Sends a multicast query for `name` with `qtype`.
    fn send_query(&self, name: &str, qtype: RRType) {
        self.send_query_vec(&[(name, qtype)]);
    }

    /// Sends a query on a specific interface without known answers.
    ///
    /// Used when a new interface is added so the responder won't suppress
    /// its response due to known-answer suppression (RFC 6762 Section 7.1).
    fn send_query_on_intf(&self, name: &str, qtype: RRType, intf: &MyIntf) {
        let mut out = DnsOutgoing::new(FLAGS_QR_QUERY);
        out.add_question(name, qtype);

        let mut invalid_intf_addrs = HashSet::new();
        if let Some(sock) = self.ipv4_sock.as_ref() {
            if let Err(InternalError::IntfAddrInvalid(intf_addr)) =
                send_dns_outgoing(&out, intf, &sock.pktinfo, self.port, None, None)
            {
                invalid_intf_addrs.insert(intf_addr);
            }
        }
        if let Some(sock) = self.ipv6_sock.as_ref() {
            if let Err(InternalError::IntfAddrInvalid(intf_addr)) =
                send_dns_outgoing(&out, intf, &sock.pktinfo, self.port, None, None)
            {
                invalid_intf_addrs.insert(intf_addr);
            }
        }
        if !invalid_intf_addrs.is_empty() {
            let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addrs));
        }
    }

    /// Sends out a list of `questions` (i.e. DNS questions) via multicast.
    fn send_query_vec(&self, questions: &[(&str, RRType)]) {
        let mut out = DnsOutgoing::new(FLAGS_QR_QUERY);
        let now = Instant::now();

        for (name, qtype) in questions {
            out.add_question(name, *qtype);

            for record in self.cache.get_known_answers(name, *qtype, now) {
                /*
                RFC 6762 section 7.1: https://datatracker.ietf.org/doc/html/rfc6762#section-7.1
                ...
                    When a Multicast DNS querier sends a query to which it already knows
                    some answers, it populates the Answer Section of the DNS query
                    message with those answers.
                 */
                trace!("add known answer: {:?}", record.record);
                let mut new_record = record.record.clone();
                new_record.get_record_mut().update_ttl(now);
                out.add_answer_box(new_record);
            }
        }

        let mut invalid_intf_addrs = HashSet::new();
        for intf in self.my_intfs.values() {
            if let Some(sock) = self.ipv4_sock.as_ref() {
                if let Err(InternalError::IntfAddrInvalid(intf_addr)) =
                    send_dns_outgoing(&out, intf, &sock.pktinfo, self.port, None, None)
                {
                    invalid_intf_addrs.insert(intf_addr);
                }
            }
            if let Some(sock) = self.ipv6_sock.as_ref() {
                if let Err(InternalError::IntfAddrInvalid(intf_addr)) =
                    send_dns_outgoing(&out, intf, &sock.pktinfo, self.port, None, None)
                {
                    invalid_intf_addrs.insert(intf_addr);
                }
            }
        }

        if !invalid_intf_addrs.is_empty() {
            let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addrs));
        }
    }

    /// Reads one UDP datagram from the socket of `intf`.
    ///
    /// Returns false if failed to receive a packet,
    /// otherwise returns true.
    fn handle_read(&mut self, event_key: usize) -> bool {
        let is_ipv4 = event_key == IPV4_SOCK_EVENT_KEY;
        let sock_opt = match event_key {
            IPV4_SOCK_EVENT_KEY => &mut self.ipv4_sock,
            IPV6_SOCK_EVENT_KEY => &mut self.ipv6_sock,
            _ => {
                debug!("handle_read: unknown token {}", event_key);
                return false;
            }
        };
        let Some(sock) = sock_opt.as_mut() else {
            debug!("handle_read: socket not available for token {}", event_key);
            return false;
        };
        // The buffer is one byte bigger than the biggest legal message, so that an
        // over-sized datagram can be told apart from a legal one that happens to be
        // exactly at the limit.
        let max_size = max_pkt_absolute(is_ipv4);
        let mut buf = vec![0u8; max_size + 1];

        // Read the next mDNS UDP datagram.
        let (sz, pktinfo) = match sock.pktinfo.recv(&mut buf) {
            Ok(sz) => sz,
            Err(e) => {
                if e.kind() != std::io::ErrorKind::WouldBlock {
                    debug!("listening socket read failed: {}", e);
                }
                return false;
            }
        };

        // RFC 6762 section 17 caps an mDNS packet at 9000 bytes including the IP and
        // UDP headers. A datagram over that arrives truncated, and decoding a
        // truncated message does not fail cleanly: names run into whatever bytes
        // follow, yielding bogus records or confusing parse errors. Drop it instead.
        //
        // On Windows, `recv` fails with WSAEMSGSIZE for such a datagram instead of
        // truncating it, so it is dropped by the error branch above. Either way it
        // is never decoded.
        if sz > max_size {
            debug!(
                "handle_read: dropping over-sized datagram of at least {} bytes (max {})",
                sz, max_size
            );
            return true; // We still read something.
        }

        // Find the interface that received the packet.
        let pkt_if_index = pktinfo.if_index as u32;
        let Some(my_intf) = self.my_intfs.get(&pkt_if_index) else {
            debug!(
                "handle_read: no interface found for pktinfo if_index: {}",
                pktinfo.if_index
            );
            return true; // We still return true to indicate that we read something.
        };

        // Drop packets for an IP version that has been disabled on this interface.
        // This is needed because some times the socket layer may still receive packets
        // for an IP version even after we left the multicast group for that IP version.
        // We want to drop such packets to avoid unnecessary processing.
        let is_ipv4 = event_key == IPV4_SOCK_EVENT_KEY;
        if (is_ipv4 && my_intf.next_ifaddr_v4().is_none())
            || (!is_ipv4 && my_intf.next_ifaddr_v6().is_none())
        {
            debug!(
                "handle_read: dropping {} packet on intf {} (disabled)",
                if is_ipv4 { "IPv4" } else { "IPv6" },
                my_intf.name
            );
            return true;
        }

        buf.truncate(sz); // reduce potential processing errors

        match DnsIncoming::new(buf, my_intf.into()) {
            Ok(msg) => {
                debug!(
                    "handle_read: {} bytes from {} on if_index {}: {} ({} questions {} answers {} authorities {} additionals)",
                    sz,
                    pktinfo.addr_src,
                    pkt_if_index,
                    if msg.is_query() { "query" } else { "response" },
                    msg.questions().len(),
                    msg.answers().len(),
                    msg.authorities().len(),
                    msg.additionals().len(),
                );
                if msg.is_query() {
                    let querier_addr = pktinfo.addr_src;
                    self.handle_query(msg, pkt_if_index, querier_addr);
                } else if msg.is_response() {
                    self.handle_response(msg, pkt_if_index);
                } else {
                    debug!("Invalid message: not query and not response");
                }
            }
            Err(e) => debug!("Invalid incoming DNS message: {}", e),
        }

        true
    }

    /// Returns true, if sent query. Returns false if SRV already exists.
    fn query_unresolved(&mut self, instance: &str) -> bool {
        if !valid_instance_name(instance) {
            trace!("instance name {} not valid", instance);
            return false;
        }

        if let Some(records) = self.cache.get_srv(instance) {
            for record in records {
                if let Some(srv) = record.record.any().downcast_ref::<DnsSrv>() {
                    if self.cache.get_addr(srv.host()).is_none() {
                        debug!(
                            "query_unresolved: SRV record found for instance: {}, host: {}, sending address query",
                            instance,
                            srv.host()
                        );
                        self.send_query_vec(&[(srv.host(), RRType::A), (srv.host(), RRType::AAAA)]);
                        return true;
                    }
                }
            }
        } else {
            debug!(
                "query_unresolved: SRV record not found for instance: {}, sending SRV+TXT query",
                instance
            );
            // Query SRV and TXT explicitly rather than RRType::ANY. RFC 6762 §6.5 makes
            // ANY legal, but SRV+TXT is what Bonjour's DNSServiceResolve and Avahi send,
            // so it is the path every responder is actually exercised on; it also lets
            // known-answer suppression apply (`get_known_answers` has no ANY case).
            self.send_query_vec(&[(instance, RRType::SRV), (instance, RRType::TXT)]);
            return true;
        }

        false
    }

    /// Re-issues follow-up queries (SRV / address) for every instance of
    /// `ty_domain` that has been found via PTR but is not yet resolved.
    ///
    /// This is meant to be driven by the browse retransmission cycle so a
    /// pending instance keeps being queried for as long as the browse is
    /// active.
    fn query_unresolved_instances(&mut self, ty_domain: &str) {
        let now = Instant::now();
        let mut instances = Vec::new();
        if let Some(records) = self.cache.get_ptr(ty_domain) {
            for record in records.iter().filter(|r| !r.record.expires_soon(now)) {
                if let Some(ptr) = record.record.any().downcast_ref::<DnsPointer>() {
                    instances.push(ptr.alias().to_string());
                }
            }
        }

        for instance in instances {
            if !self.resolved.contains(&instance) {
                self.query_unresolved(&instance);
            }
        }
    }

    /// Checks if `ty_domain` has records in the cache. If yes, sends the
    /// cached records via `sender`.
    fn query_cache_for_service(
        &mut self,
        ty_domain: &str,
        sender: &Sender<ServiceEvent>,
        now: Instant,
    ) {
        let aliases: Vec<String> = self
            .cache
            .get_ptr(ty_domain)
            .map(|records| {
                records
                    .iter()
                    .filter(|r| !r.record.expires_soon(now))
                    .filter_map(|r| {
                        r.record
                            .any()
                            .downcast_ref::<DnsPointer>()
                            .map(|p| p.alias().to_string())
                    })
                    .collect()
            })
            .unwrap_or_default();

        for alias in aliases {
            let resolved_event = match self.resolve_service_from_cache(ty_domain, &alias) {
                Ok(resolved_service) if resolved_service.is_valid() => {
                    debug!("Resolved service from cache: {}", alias);
                    Some(ServiceEvent::ServiceResolved(Box::new(resolved_service)))
                }
                Ok(resolved_service) => {
                    debug!(
                        "query_cache_for_service: not valid: {} (host_empty={}, addrs_empty={})",
                        alias,
                        resolved_service.get_hostname().is_empty(),
                        resolved_service.get_addresses().is_empty(),
                    );
                    None
                }
                Err(err) => {
                    debug!("Error while resolving service from cache: {}", err);
                    continue;
                }
            };

            self.push_service(
                ty_domain,
                ServiceEvent::ServiceFound(ty_domain.to_string(), alias.clone()),
            );
            if !self.service_live(ty_domain, sender) {
                return;
            }
            debug!("sent service found {}", alias);

            if let Some(event) = resolved_event {
                self.push_service(ty_domain, event);
                if !self.service_live(ty_domain, sender) {
                    return;
                }
                debug!("sent service resolved: {}", alias);
                self.pending_resolves.remove(&alias);
                self.resolved.insert(alias);
            } else {
                self.add_pending_resolve(alias);
            }
        }
    }

    /// Checks if `hostname` has records in the cache. If yes, sends the
    /// cached records via `sender`.
    fn query_cache_for_hostname(
        &mut self,
        hostname: &str,
        sender: Sender<HostnameResolutionEvent>,
    ) {
        let addresses_map = self.cache.get_addresses_for_host(hostname);
        for (name, addresses) in addresses_map {
            self.push_hostname(
                hostname,
                HostnameResolutionEvent::AddressesFound(name, addresses),
            );
            if !self.hostname_live(hostname, &sender) {
                return;
            }
            trace!("sent hostname addresses found");
        }
    }

    fn add_pending_resolve(&mut self, instance: String) {
        if !self.pending_resolves.contains(&instance) {
            let next_time = Instant::now() + Duration::from_millis(RESOLVE_RETRY_BASE_MILLIS);
            self.add_retransmission(next_time, Command::Resolve(instance.clone(), 1));
            self.pending_resolves.insert(instance);
        }
    }

    /// Creates a `ResolvedService` from the cache.
    fn resolve_service_from_cache(
        &self,
        ty_domain: &str,
        fullname: &str,
    ) -> Result<ResolvedService> {
        let now = Instant::now();
        let mut resolved_service = ResolvedService {
            ty_domain: ty_domain.to_string(),
            sub_ty_domain: None,
            fullname: fullname.to_string(),
            host: String::new(),
            port: 0,
            addresses: HashSet::new(),
            txt_properties: TxtProperties::new(),
        };

        // Be sure setting `subtype` if available even when querying for the parent domain.
        if let Some(subtype) = self.cache.get_subtype(fullname) {
            trace!(
                "ty_domain: {} found subtype {} for instance: {}",
                ty_domain,
                subtype,
                fullname
            );
            if resolved_service.sub_ty_domain.is_none() {
                resolved_service.sub_ty_domain = Some(subtype.to_string());
            }
        }

        // resolve SRV record
        if let Some(records) = self.cache.get_srv(fullname) {
            if let Some(answer) = records.iter().find(|r| !r.record.expires_soon(now)) {
                if let Some(dns_srv) = answer.record.any().downcast_ref::<DnsSrv>() {
                    resolved_service.host = dns_srv.host().to_string();
                    resolved_service.port = dns_srv.port();
                }
            }
        }

        // resolve TXT record
        if let Some(records) = self.cache.get_txt(fullname) {
            if let Some(record) = records.iter().find(|r| !r.record.expires_soon(now)) {
                if let Some(dns_txt) = record.record.any().downcast_ref::<DnsTxt>() {
                    resolved_service.txt_properties = dns_txt.text().into();
                }
            }
        }

        // resolve A and AAAA records
        if let Some(records) = self.cache.get_addr(&resolved_service.host) {
            for answer in records.iter() {
                if let Some(dns_a) = answer.record.any().downcast_ref::<DnsAddress>() {
                    if dns_a.expires_soon(now) {
                        trace!(
                            "Addr expired or expires soon: {}",
                            dns_a.address().to_ip_addr()
                        );
                    } else {
                        let scoped = dns_a.address();
                        if let ScopedIp::V4(v4) = &scoped {
                            // Merge interface_ids if this V4 addr already exists.
                            // Linear scan by IP since Eq/Hash include interface_ids.
                            let existing = resolved_service
                                .addresses
                                .iter()
                                .find(|a| a.to_ip_addr() == IpAddr::V4(*v4.addr()))
                                .cloned();
                            if let Some(mut existing) = existing {
                                resolved_service.addresses.remove(&existing);
                                if let ScopedIp::V4(existing_v4) = &mut existing {
                                    for id in v4.interface_ids() {
                                        existing_v4.add_interface_id(id.clone());
                                    }
                                }
                                resolved_service.addresses.insert(existing);
                            } else {
                                resolved_service.addresses.insert(scoped);
                            }
                        } else {
                            resolved_service.addresses.insert(scoped);
                        }
                    }
                }
            }
        }

        Ok(resolved_service)
    }

    fn handle_poller_events(&mut self, events: &mio::Events) {
        for ev in events.iter() {
            trace!("event received with key {:?}", ev.token());
            if ev.token().0 == WAKER_EVENT_KEY {
                // Nothing to read. Wakeups coalesce, and the command queue
                // is drained after this function returns.
                continue;
            }

            // Read until no more packets available.
            while self.handle_read(ev.token().0) {}

            // we continue to monitor this socket.
            if ev.token().0 == IPV4_SOCK_EVENT_KEY {
                // Re-register the IPv4 socket for reading.
                if let Some(sock) = self.ipv4_sock.as_mut() {
                    if let Err(e) =
                        self.poller
                            .registry()
                            .reregister(sock, ev.token(), mio::Interest::READABLE)
                    {
                        debug!("modify poller for IPv4 socket: {}", e);
                    }
                }
            } else if ev.token().0 == IPV6_SOCK_EVENT_KEY {
                // Re-register the IPv6 socket for reading.
                if let Some(sock) = self.ipv6_sock.as_mut() {
                    if let Err(e) =
                        self.poller
                            .registry()
                            .reregister(sock, ev.token(), mio::Interest::READABLE)
                    {
                        debug!("modify poller for IPv6 socket: {}", e);
                    }
                }
            }
        }
    }

    /// Deal with incoming response packets.  All answers
    /// are held in the cache, and listeners are notified.
    fn handle_response(&mut self, mut msg: DnsIncoming, if_index: u32) {
        let now = Instant::now();

        // remove records that are expired.
        let mut removed_ptrs = Vec::new();
        let mut record_predicate = |record: &DnsRecordBox| {
            if !record.get_record().is_expired(now) {
                return true;
            }

            debug!("record is expired, removing it from cache.");
            if self.cache.remove(record) {
                // for PTR records, send event to listeners
                if let Some(dns_ptr) = record.any().downcast_ref::<DnsPointer>() {
                    removed_ptrs
                        .push((dns_ptr.get_name().to_string(), dns_ptr.alias().to_string()));
                }
            }
            false
        };
        msg.answers_mut().retain(&mut record_predicate);
        msg.authorities_mut().retain(&mut record_predicate);
        msg.additionals_mut().retain(&mut record_predicate);
        for (name, alias) in removed_ptrs {
            self.push_service(&name, ServiceEvent::ServiceRemoved(name.clone(), alias));
        }

        // check possible conflicts and handle them.
        self.conflict_handler(&msg, if_index);

        // check if the message is for us.
        let mut is_for_us = true; // assume it is for us.

        // If there are any PTR records in the answers, there should be
        // at least one PTR for us. Otherwise, the message is not for us.
        // If there are no PTR records at all, assume this message is for us.
        for answer in msg.answers() {
            if answer.get_type() == RRType::PTR {
                if self.service_queriers.contains_key(answer.get_name()) {
                    is_for_us = true;
                    break; // OK to break: at least one PTR for us.
                } else {
                    is_for_us = false;
                }
            } else if answer.get_type() == RRType::A || answer.get_type() == RRType::AAAA {
                // If there is a hostname querier for this address, then it is for us.
                let answer_lowercase = answer.get_name().to_lowercase();
                if self.hostname_resolvers.contains_key(&answer_lowercase) {
                    is_for_us = true;
                    break; // OK to break: at least one hostname for us.
                }
            }
        }

        // if we explicitily want to accept unsolicited responses, we should consider all messages as for us.
        if self.accept_unsolicited {
            is_for_us = true;
        }

        /// Represents a DNS record change that involves one service instance.
        struct InstanceChange {
            ty: RRType,   // The type of DNS record for the instance.
            name: String, // The name of the record.
        }

        // Go through all answers to get the new and updated records.
        // For new PTR records, send out ServiceFound immediately. For others,
        // collect them into `changes`.
        //
        // Note: we don't try to identify the update instances based on
        // each record immediately as the answers are likely related to each
        // other.
        let mut changes = Vec::new();
        let mut timers = Vec::new();
        let mut found = Vec::new();
        let Some(my_intf) = self.my_intfs.get(&if_index) else {
            return;
        };
        for record in msg.all_records() {
            match self
                .cache
                .add_or_update(my_intf, record, &mut timers, is_for_us)
            {
                Some((dns_record, true)) => {
                    timers.push(dns_record.record.get_record().get_expire_time());
                    timers.push(dns_record.record.get_record().get_refresh_time());

                    let ty = dns_record.record.get_type();
                    let name = dns_record.record.get_name();

                    // Positive dump: a new record was accepted into the cache.
                    // Counterpart to the "skipping record" debug line in the parser.
                    debug!("cache: new record: {:?}", dns_record.record);

                    // Only process PTR that does not expire soon (i.e. TTL > 1).
                    if ty == RRType::PTR && dns_record.record.get_record().get_ttl() > 1 {
                        if self.service_queriers.contains_key(name) {
                            timers.push(dns_record.record.get_record().get_refresh_time());
                        }

                        // send ServiceFound
                        if let Some(dns_ptr) = dns_record.record.any().downcast_ref::<DnsPointer>()
                        {
                            debug!("calling listener with service found: {name}");
                            found.push((
                                name.to_string(),
                                ServiceEvent::ServiceFound(
                                    name.to_string(),
                                    dns_ptr.alias().to_string(),
                                ),
                            ));
                            changes.push(InstanceChange {
                                ty,
                                name: dns_ptr.alias().to_string(),
                            });
                        }
                    } else {
                        changes.push(InstanceChange {
                            ty,
                            name: name.to_string(),
                        });
                    }
                }
                Some((dns_record, false)) => {
                    timers.push(dns_record.record.get_record().get_expire_time());
                    timers.push(dns_record.record.get_record().get_refresh_time());
                }
                _ => {}
            }
        }
        for (ty_domain, event) in found {
            self.push_service(&ty_domain, event);
        }

        // Add timers for the new records.
        for t in timers {
            self.add_timer(t);
        }

        // Go through remaining changes to see if any hostname resolutions were found or updated.
        for change in changes
            .iter()
            .filter(|change| change.ty == RRType::A || change.ty == RRType::AAAA)
        {
            let addr_map = self.cache.get_addresses_for_host(&change.name);
            for (name, addresses) in addr_map {
                self.push_hostname(
                    &change.name,
                    HostnameResolutionEvent::AddressesFound(name, addresses),
                );
            }
        }

        // Identify the instances that need to be "resolved".
        let mut updated_instances = HashSet::new();
        for update in changes {
            match update.ty {
                RRType::PTR | RRType::SRV | RRType::TXT => {
                    updated_instances.insert(update.name);
                }
                RRType::A | RRType::AAAA => {
                    let instances = self.cache.get_instances_on_host(&update.name);
                    updated_instances.extend(instances);
                }
                _ => {}
            }
        }

        self.resolve_updated_instances(&updated_instances);
    }

    fn conflict_handler(&mut self, msg: &DnsIncoming, if_index: u32) {
        let Some(my_intf) = self.my_intfs.get(&if_index) else {
            debug!("handle_response: no intf found for index {if_index}");
            return;
        };

        let Some(dns_registry) = self.dns_registry_map.get_mut(&if_index) else {
            return;
        };

        for answer in msg.answers().iter() {
            let mut new_records = Vec::new();

            let name = answer.get_name();
            let Some(probe) = dns_registry.probing.get_mut(name) else {
                continue;
            };

            // check against possible multicast forwarding
            if answer.get_type() == RRType::A || answer.get_type() == RRType::AAAA {
                if let Some(answer_addr) = answer.any().downcast_ref::<DnsAddress>() {
                    if answer_addr.interface_id.index != if_index {
                        debug!(
                            "conflict handler: answer addr {:?} not in the subnet of intf {}",
                            answer_addr, my_intf.name
                        );
                        continue;
                    }
                }

                // double check if any other address record matches rrdata,
                // as there could be multiple addresses for the same name.
                let any_match = probe.records.iter().any(|r| {
                    r.get_type() == answer.get_type()
                        && r.get_class() == answer.get_class()
                        && r.rrdata_match(answer.as_ref())
                });
                if any_match {
                    continue; // no conflict for this answer.
                }
            }

            probe.records.retain(|record| {
                if record.get_type() == answer.get_type()
                    && record.get_class() == answer.get_class()
                    && !record.rrdata_match(answer.as_ref())
                {
                    debug!(
                        "found conflict name: '{name}' record: {}: {} PEER: {}",
                        record.get_type(),
                        record.rdata_print(),
                        answer.rdata_print()
                    );

                    // create a new name for this record
                    // then remove the old record in probing.
                    let mut new_record = record.clone();
                    let new_name = match record.get_type() {
                        RRType::A => hostname_change(name),
                        RRType::AAAA => hostname_change(name),
                        _ => name_change(name),
                    };
                    new_record.get_record_mut().set_new_name(new_name);
                    new_records.push(new_record);
                    return false; // old record is dropped from the probe.
                }

                true
            });

            // ?????
            // if probe.records.is_empty() {
            //     dns_registry.probing.remove(name);
            // }

            // Probing again with the new names.
            let create_time = Instant::now() + Duration::from_millis(fastrand::u64(0..250));

            let waiting_services = probe.waiting_services.clone();

            for record in new_records {
                if dns_registry.update_hostname(name, record.get_name(), create_time) {
                    self.timers.push(Reverse(create_time));
                }

                // remember the name changes (note: `name` might not be the original, it could be already changed once.)
                dns_registry.name_changes.insert(
                    record.get_record().get_original_name().to_string(),
                    record.get_name().to_string(),
                );

                let new_probe = match dns_registry.probing.get_mut(record.get_name()) {
                    Some(p) => p,
                    None => {
                        let new_probe = dns_registry
                            .probing
                            .entry(record.get_name().to_string())
                            .or_insert_with(|| {
                                debug!("conflict handler: new probe of {}", record.get_name());
                                Probe::new(create_time)
                            });
                        self.timers.push(Reverse(new_probe.next_send));
                        new_probe
                    }
                };

                debug!(
                    "insert record with new name '{}' {} into probe",
                    record.get_name(),
                    record.get_type()
                );
                new_probe.insert_record(record);

                new_probe.waiting_services.extend(waiting_services.clone());
            }
        }
    }

    /// Resolve the updated (including new) instances.
    ///
    /// Note: it is possible that more than 1 PTR pointing to the same
    /// instance. For example, a regular service type PTR and a sub-type
    /// service type PTR can both point to the same service instance.
    /// This loop automatically handles the sub-type PTRs.
    fn resolve_updated_instances(&mut self, updated_instances: &HashSet<String>) {
        if updated_instances.is_empty() {
            return;
        }

        let mut resolved: HashSet<String> = HashSet::new();
        let mut unresolved: HashSet<String> = HashSet::new();
        let mut removed_instances = HashMap::new();
        let mut deliver = Vec::new();

        let now = Instant::now();

        for (ty_domain, records) in self.cache.all_ptr().iter() {
            if !self.service_queriers.contains_key(ty_domain) {
                // No need to resolve if not in our queries.
                continue;
            }

            for ptr in records.iter().filter(|r| !r.record.expires_soon(now)) {
                let Some(dns_ptr) = ptr.record.any().downcast_ref::<DnsPointer>() else {
                    continue;
                };

                let instance = dns_ptr.alias();
                if !updated_instances.contains(instance) {
                    continue;
                }

                let Ok(resolved_service) = self.resolve_service_from_cache(ty_domain, instance)
                else {
                    continue;
                };

                debug!("resolve_updated_instances: from cache: {instance}");
                if resolved_service.is_valid() {
                    debug!(
                        "resolved '{}' -> host '{}' port {} addrs {:?}",
                        instance,
                        resolved_service.host,
                        resolved_service.port,
                        resolved_service.addresses,
                    );
                    resolved.insert(instance.to_string());
                    deliver.push((
                        ty_domain.to_string(),
                        ServiceEvent::ServiceResolved(Box::new(resolved_service)),
                    ));
                } else {
                    debug!(
                        "resolve_updated_instances: not valid: {instance} (host_empty={}, addrs_empty={})",
                        resolved_service.get_hostname().is_empty(),
                        resolved_service.get_addresses().is_empty(),
                    );
                    if self.resolved.remove(dns_ptr.alias()) {
                        removed_instances
                            .entry(ty_domain.to_string())
                            .or_insert_with(HashSet::new)
                            .insert(instance.to_string());
                    }
                    unresolved.insert(instance.to_string());
                }
            }
        }

        for (ty_domain, event) in deliver {
            self.push_service(&ty_domain, event);
        }

        for instance in resolved.drain() {
            self.pending_resolves.remove(&instance);
            self.resolved.insert(instance);
        }

        for instance in unresolved.drain() {
            self.add_pending_resolve(instance);
        }

        if !removed_instances.is_empty() {
            debug!(
                "resolve_updated_instances: removed {}",
                removed_instances.len()
            );
            self.notify_service_removal(removed_instances);
        }
    }

    /// Handle incoming query packets, figure out whether and what to respond.
    fn handle_query(&mut self, msg: DnsIncoming, if_index: u32, querier_addr: SocketAddr) {
        let querier_ip = querier_addr.ip();
        let is_ipv4 = querier_ip.is_ipv4();

        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
        let mut delayed = false;
        let legacy_querier = self.is_legacy_querier(querier_addr);

        // Special meta-query "_services._dns-sd._udp.<Domain>".
        // See https://datatracker.ietf.org/doc/html/rfc6763#section-9
        const META_QUERY: &str = "_services._dns-sd._udp.local.";

        let Some(dns_registry) = self.dns_registry_map.get_mut(&if_index) else {
            debug!("missing dns registry for intf {}", if_index);
            return;
        };

        let Some(intf) = self.my_intfs.get(&if_index) else {
            debug!("handle_query: no intf found for index {if_index}");
            return;
        };

        for question in msg.questions().iter() {
            let qtype = question.entry_type();
            let q_name = question.entry_name();

            if qtype == RRType::PTR {
                // PTR answers are shared records: defer the response unless this
                // is a legacy-unicast (source port differs from ours) or probe-defense
                // (records in the Authority Section) query.
                if !legacy_querier && msg.num_authorities() == 0 {
                    delayed = true;
                }
                for service in self.my_services.values() {
                    if service.get_status(if_index) != ServiceStatus::Announced {
                        continue;
                    }

                    if service.matches_type_or_subtype(q_name) {
                        out.add_answer_with_additionals(&msg, service, intf, dns_registry, is_ipv4);
                    } else if q_name == META_QUERY {
                        let ttl = service.get_other_ttl();
                        let alias = service.get_type().to_string();
                        let ptr = DnsPointer::new(q_name, RRType::PTR, CLASS_IN, ttl, alias);
                        if !out.add_answer(&msg, ptr) {
                            trace!("answer was not added for meta-query {:?}", question);
                        }
                    }
                }
            } else {
                // Simultaneous Probe Tiebreaking (RFC 6762 section 8.2)
                if qtype == RRType::ANY && msg.num_authorities() > 0 {
                    if let Some(probe) = dns_registry.probing.get_mut(q_name) {
                        probe.tiebreaking(&msg, q_name);
                    }
                }

                if matches!(
                    qtype,
                    RRType::A | RRType::AAAA | RRType::ANY | RRType::SVCB | RRType::HTTPS
                ) {
                    answer_hostname_question(
                        &self.my_services,
                        intf,
                        question,
                        dns_registry,
                        &mut out,
                        &msg,
                    );
                }

                let query_name = q_name.to_lowercase();
                let service_opt = self
                    .my_services
                    .iter()
                    .find(|(k, _v)| dns_registry.resolve_name(k.as_str()) == query_name)
                    .map(|(_, v)| v);

                let Some(service) = service_opt else {
                    continue;
                };

                if service.get_status(if_index) != ServiceStatus::Announced {
                    continue;
                }

                let intf_addrs = if is_ipv4 {
                    service.get_addrs_on_my_intf_v4(intf)
                } else {
                    service.get_addrs_on_my_intf_v6(intf)
                };
                if intf_addrs.is_empty() {
                    debug!(
                        "Cannot find valid addrs for TYPE_SRV response on intf {:?}",
                        intf
                    );
                    continue;
                }

                add_answer_of_service(
                    &mut out,
                    &msg,
                    question.entry_name(),
                    service,
                    qtype,
                    intf_addrs,
                );
            }
        }

        // Defer PTR responses (RFC 6762 §6).
        if delayed && out.answers_count() > 0 {
            out.set_id(msg.id());
            self.increase_counter(Counter::KnownAnswerSuppression, out.known_answer_count());
            let delay =
                fastrand::u64(SHARED_RESPONSE_DELAY_MIN_MILLIS..SHARED_RESPONSE_DELAY_MAX_MILLIS);
            let next_time = Instant::now() + Duration::from_millis(delay);
            self.delayed_responses.push(DelayedResponse {
                next_time,
                out,
                if_index,
                is_ipv4,
            });
            self.add_timer(next_time);
            return;
        }

        if out.answers_count() > 0 {
            self.send_response(&mut out, &msg, if_index, querier_addr);
        }

        self.increase_counter(Counter::KnownAnswerSuppression, out.known_answer_count());
    }

    fn is_legacy_querier(&self, addr: SocketAddr) -> bool {
        addr.port() != self.port
    }

    fn send_response(
        &mut self,
        out: &mut DnsOutgoing,
        msg: &DnsIncoming,
        if_index: u32,
        querier_addr: SocketAddr,
    ) {
        let querier_ip = querier_addr.ip();
        let is_ipv4 = querier_ip.is_ipv4();
        let sock_opt = if is_ipv4 {
            &self.ipv4_sock
        } else {
            &self.ipv6_sock
        };
        let Some(sock) = sock_opt.as_ref() else {
            debug!("send_response: socket not available for intf {if_index}");
            return;
        };
        let Some(intf) = self.my_intfs.get(&if_index) else {
            debug!("send_response: no intf found for index {if_index}");
            return;
        };

        out.set_id(msg.id());

        // Pick a source IfAddr on `intf` whose subnet contains the querier's IP.
        // It's OK if it's None, `send_dns_outgoing` will then pick one address.
        let matched_source = intf
            .addrs
            .iter()
            .find(|if_addr| valid_ip_on_intf(&querier_ip, if_addr));

        // RFC 6762 §6.7 (Legacy Unicast Responses): if the querier's source
        // port differs from ours, it's a one-shot legacy querier (e.g. Android's
        // getaddrinfo, iOS resolver fallback). The response MUST be unicast
        // back to the querier's source IP and port; multicast replies will
        // never reach the querier's ephemeral socket. Legacy unicast
        // responses must also echo the question section, clear the
        // cache-flush bit (legacy resolvers don't understand it), and cap
        // record TTLs to 10 seconds (see update_records_for_legacy_unicast).
        let unicast_dest = if self.is_legacy_querier(querier_addr) {
            Some(querier_addr)
        } else {
            None
        };

        if unicast_dest.is_some() {
            for q in msg.questions() {
                out.add_question(q.entry_name(), q.entry_type());
            }
            out.update_records_for_legacy_unicast();
            out.set_multicast(false);
        } else if msg.num_authorities() == 0 {
            // RFC 6762 §6: a record MUST NOT be multicast on an interface
            // more than once per second. Two exceptions skip the limit here:
            //   - Unicast responses (handled above).
            //   - Answering probe queries: a probe carries the proposed
            //     records in its Authority Section, and we MUST defend our
            //     records immediately so the prober detects the conflict.
            if let Some(dns_registry) = self.dns_registry_map.get_mut(&if_index) {
                dns_registry.apply_multicast_rate_limit(out, Instant::now(), is_ipv4);
            }
        }

        if out.answers_count() > 0 {
            debug!("sending response on intf {}", intf.name);
            if let Err(InternalError::IntfAddrInvalid(intf_addr)) = send_dns_outgoing(
                out,
                intf,
                &sock.pktinfo,
                self.port,
                matched_source,
                unicast_dest,
            ) {
                let invalid_intf_addr = HashSet::from([intf_addr]);
                let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addr));
            }

            let if_name = intf.name.clone();

            self.increase_counter(Counter::Respond, 1);
            self.notify_monitors(DaemonEvent::Respond(if_name));
        }
    }

    /// Multicasts a PTR query response that was deferred per RFC 6762 §6.
    ///
    /// Re-resolves the socket and interface from `if_index`, so it is safe to
    /// call from the timer loop after the borrows taken while building the
    /// response are gone. The original querier is no longer known, so the
    /// response is always a plain multicast (no unicast destination, no
    /// source-address preference); the §6 once-per-second multicast rate limit
    /// still applies.
    fn send_delayed_response(&mut self, resp: DelayedResponse) {
        let DelayedResponse {
            mut out,
            if_index,
            is_ipv4,
            ..
        } = resp;

        let sock_opt = if is_ipv4 {
            &self.ipv4_sock
        } else {
            &self.ipv6_sock
        };
        let Some(sock) = sock_opt.as_ref() else {
            debug!("send_delayed_response: socket not available for intf {if_index}");
            return;
        };

        if let Some(dns_registry) = self.dns_registry_map.get_mut(&if_index) {
            dns_registry.apply_multicast_rate_limit(&mut out, Instant::now(), is_ipv4);
        }
        if out.answers_count() == 0 {
            return;
        }

        let Some(intf) = self.my_intfs.get(&if_index) else {
            debug!("send_delayed_response: no intf found for index {if_index}");
            return;
        };

        let if_name = intf.name.clone();
        debug!("sending delayed response on intf {}", if_name);
        let send_result = send_dns_outgoing(&out, intf, &sock.pktinfo, self.port, None, None);

        if let Err(InternalError::IntfAddrInvalid(intf_addr)) = send_result {
            let invalid_intf_addr = HashSet::from([intf_addr]);
            let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addr));
        }

        self.increase_counter(Counter::Respond, 1);
        self.notify_monitors(DaemonEvent::Respond(if_name));
    }

    /// Increases the value of `counter` by `count`.
    fn increase_counter(&mut self, counter: Counter, count: i64) {
        let key = counter.to_string();
        match self.counters.get_mut(&key) {
            Some(v) => *v += count,
            None => {
                self.counters.insert(key, count);
            }
        }
    }

    /// Sets the value of `counter` to `count`.
    fn set_counter(&mut self, counter: Counter, count: i64) {
        let key = counter.to_string();
        self.counters.insert(key, count);
    }

    fn add_retransmission(&mut self, next_time: Instant, command: Command) {
        self.retransmissions.push(ReRun { next_time, command });
        self.add_timer(next_time);
    }

    /// Sends service removal event to listeners for expired service records.
    /// `expired`: map of service type domain to set of instance names.
    fn notify_service_removal(&mut self, expired: HashMap<String, HashSet<String>>) {
        let domains: Vec<String> = self.service_queriers.keys().cloned().collect();
        for ty_domain in domains {
            if let Some(instances) = expired.get(&ty_domain) {
                for instance_name in instances {
                    let event = ServiceEvent::ServiceRemoved(
                        ty_domain.to_string(),
                        instance_name.to_string(),
                    );
                    self.push_service(&ty_domain, event);
                    if self.service_queriers.contains_key(&ty_domain) {
                        debug!("notify_service_removal: sent ServiceRemoved to listener of {ty_domain}: {instance_name}");
                    }
                }
            }
        }
    }

    /// The entry point that executes all commands received by the daemon.
    ///
    /// `repeating`: whether this is a retransmission.
    fn exec_command(&mut self, command: Command, repeating: bool) {
        trace!("exec_command: {:?} repeating: {}", command, repeating);
        match command {
            Command::Browse(ty, next_delay, cache_only, listener) => {
                self.exec_command_browse(repeating, ty, next_delay, cache_only, listener);
            }

            Command::ResolveHostname(hostname, next_delay, listener, timeout) => {
                self.exec_command_resolve_hostname(
                    repeating, hostname, next_delay, listener, timeout,
                );
            }

            Command::Register(service_info) => {
                self.register_service(*service_info);
                self.increase_counter(Counter::Register, 1);
            }

            Command::RegisterResend(fullname, intf) => {
                trace!("register-resend service: {fullname} on {}", intf);
                if let Err(InternalError::IntfAddrInvalid(intf_addr)) =
                    self.exec_command_register_resend(fullname, intf)
                {
                    let invalid_intf_addr = HashSet::from([intf_addr]);
                    let _ = self.send_cmd_to_self(Command::InvalidIntfAddrs(invalid_intf_addr));
                }
            }

            Command::Unregister(fullname, resp_s) => {
                trace!("unregister service {} repeat {}", fullname, repeating);
                self.exec_command_unregister(repeating, fullname, resp_s);
            }

            Command::UnregisterResend(packet, if_index, is_ipv4) => {
                self.exec_command_unregister_resend(packet, if_index, is_ipv4);
            }

            Command::StopBrowse(ty_domain) => self.exec_command_stop_browse(ty_domain),

            Command::StopResolveHostname(hostname) => {
                self.exec_command_stop_resolve_hostname(hostname.to_lowercase())
            }

            Command::Resolve(instance, try_count) => self.exec_command_resolve(instance, try_count),

            Command::GetMetrics(resp_s) => self.exec_command_get_metrics(resp_s),

            Command::GetStatus(resp_s) => match resp_s.send(self.status.clone()) {
                Ok(()) => trace!("Sent status to the client"),
                Err(e) => debug!("Failed to send status: {}", e),
            },

            Command::Monitor(resp_s) => {
                self.monitors.push(resp_s);
            }

            Command::SetOption(daemon_opt) => {
                self.process_set_option(daemon_opt);
            }

            Command::GetOption(resp_s) => {
                let val = DaemonOptionVal {
                    _service_name_len_max: self.service_name_len_max,
                    ip_check_interval: self.ip_check_interval,
                };
                if let Err(e) = resp_s.send(val) {
                    debug!("Failed to send options: {}", e);
                }
            }

            Command::Verify(instance_fullname, timeout) => {
                self.exec_command_verify(instance_fullname, timeout, repeating);
            }

            Command::InvalidIntfAddrs(invalid_intf_addrs) => {
                for intf_addr in invalid_intf_addrs {
                    self.del_interface_addr(&intf_addr);
                }

                self.check_ip_changes();
            }

            _ => {
                debug!("unexpected command: {:?}", command);
            }
        }
    }

    fn exec_command_get_metrics(&mut self, resp_s: Sender<HashMap<String, i64>>) {
        self.set_counter(Counter::CachedPTR, self.cache.ptr_count() as i64);
        self.set_counter(Counter::CachedSRV, self.cache.srv_count() as i64);
        self.set_counter(Counter::CachedAddr, self.cache.addr_count() as i64);
        self.set_counter(Counter::CachedTxt, self.cache.txt_count() as i64);
        self.set_counter(Counter::CachedNSec, self.cache.nsec_count() as i64);
        self.set_counter(Counter::CachedSubtype, self.cache.subtype_count() as i64);
        self.set_counter(Counter::Timer, self.timers.len() as i64);

        let dns_registry_probe_count: usize = self
            .dns_registry_map
            .values()
            .map(|r| r.probing.len())
            .sum();
        self.set_counter(Counter::DnsRegistryProbe, dns_registry_probe_count as i64);

        let dns_registry_active_count: usize = self
            .dns_registry_map
            .values()
            .map(|r| r.active.values().map(|a| a.len()).sum::<usize>())
            .sum();
        self.set_counter(Counter::DnsRegistryActive, dns_registry_active_count as i64);

        let dns_registry_timer_count: usize = self
            .dns_registry_map
            .values()
            .map(|r| r.new_timers.len())
            .sum();
        self.set_counter(Counter::DnsRegistryTimer, dns_registry_timer_count as i64);

        let dns_registry_name_change_count: usize = self
            .dns_registry_map
            .values()
            .map(|r| r.name_changes.len())
            .sum();
        self.set_counter(
            Counter::DnsRegistryNameChange,
            dns_registry_name_change_count as i64,
        );

        // Send the metrics to the client.
        if let Err(e) = resp_s.send(self.counters.clone()) {
            debug!("Failed to send metrics: {}", e);
        }
    }

    fn exec_command_browse(
        &mut self,
        repeating: bool,
        ty: String,
        next_delay: u32,
        cache_only: bool,
        listener: Sender<ServiceEvent>,
    ) {
        let pretty_addrs: Vec<String> = self
            .my_intfs
            .iter()
            .map(|(if_index, itf)| format!("{} ({if_index})", itf.name))
            .collect();

        let started = ServiceEvent::SearchStarted(format!(
            "{ty} on {} interfaces [{}]",
            pretty_addrs.len(),
            pretty_addrs.join(", ")
        ));
        if !repeating {
            if let Err(e) = listener.try_send(started) {
                debug!(
                    "Failed to send SearchStarted({})(repeating:{}): {}",
                    ty, repeating, e
                );
                return;
            }
            self.clear_service_retransmissions(&ty);
            // Binds a `listener` to querying mDNS domain type `ty`.
            //
            // If there is already a `listener`, it will be updated, i.e. overwritten.
            self.service_queriers.insert(ty.clone(), listener.clone());
            let now = Instant::now();
            self.query_cache_for_service(&ty, &listener, now);
            if !self.service_live(&ty, &listener) {
                return;
            }
        } else {
            if !self.service_live(&ty, &listener) {
                return;
            }
            self.push_service(&ty, started);
            if !self.service_live(&ty, &listener) {
                return;
            }
        }

        let now = Instant::now();
        if cache_only {
            // If cache_only is true, we do not send a query.
            self.push_service(&ty, ServiceEvent::SearchStopped(ty.clone()));
            return;
        }

        if !repeating {
            // RFC 6762 §5.2: delay the first query by a random jitter.
            let jitter =
                fastrand::u64(INITIAL_QUERY_DELAY_MIN_MILLIS..INITIAL_QUERY_DELAY_MAX_MILLIS);
            self.add_retransmission(
                now + Duration::from_millis(jitter),
                Command::Browse(ty, 1, cache_only, listener),
            );
            return;
        }

        self.send_query(&ty, RRType::PTR);

        self.query_unresolved_instances(&ty);

        self.increase_counter(Counter::Browse, 1);

        let next_time = now + Duration::from_millis((next_delay * 1000) as u64);
        let max_delay = 60 * 60;
        let delay = cmp::min(next_delay * 2, max_delay);
        self.add_retransmission(next_time, Command::Browse(ty, delay, cache_only, listener));
    }

    fn exec_command_resolve_hostname(
        &mut self,
        repeating: bool,
        hostname: String,
        next_delay: u32,
        listener: Sender<HostnameResolutionEvent>,
        timeout: Option<u64>,
    ) {
        let addr_list: Vec<_> = self.my_intfs.iter().collect();
        let started = HostnameResolutionEvent::SearchStarted(format!(
            "{} on addrs {:?}",
            hostname, addr_list
        ));
        if !repeating {
            if let Err(e) = listener.try_send(started) {
                debug!(
                    "Failed to send ResolveStarted({})(repeating:{}): {}",
                    hostname, repeating, e
                );
                return;
            }
            self.clear_hostname_retransmissions(&hostname);
            self.add_hostname_resolver(hostname.to_owned(), listener.clone(), timeout);
            // if we already have the records in our cache, just send them
            self.query_cache_for_hostname(&hostname, listener.clone());
            if !self.hostname_live(&hostname, &listener) {
                return;
            }
        } else {
            if !self.hostname_live(&hostname, &listener) {
                return;
            }
            self.push_hostname(&hostname, started);
            if !self.hostname_live(&hostname, &listener) {
                return;
            }
        }
        let now = Instant::now();
        if !repeating {
            // RFC 6762 §5.2: delay the first query by a random jitter.
            let jitter =
                fastrand::u64(INITIAL_QUERY_DELAY_MIN_MILLIS..INITIAL_QUERY_DELAY_MAX_MILLIS);
            self.add_retransmission(
                now + Duration::from_millis(jitter),
                Command::ResolveHostname(hostname, 1, listener, None),
            );
            return;
        }

        self.send_query_vec(&[(&hostname, RRType::A), (&hostname, RRType::AAAA)]);
        self.increase_counter(Counter::ResolveHostname, 1);

        let next_time = now + Duration::from_millis(u64::from(next_delay) * 1000);
        let max_delay = 60 * 60;
        let delay = cmp::min(next_delay * 2, max_delay);

        // Only add retransmission if it does not exceed the hostname resolver timeout, if any.
        if self
            .hostname_resolvers
            .get(&hostname.to_lowercase())
            .and_then(|(_sender, timeout)| *timeout)
            .map(|timeout| next_time < timeout)
            .unwrap_or(true)
        {
            self.add_retransmission(
                next_time,
                Command::ResolveHostname(hostname, delay, listener, None),
            );
        }
    }

    fn exec_command_resolve(&mut self, instance: String, try_count: u16) {
        let pending_query = self.query_unresolved(&instance);
        if pending_query && try_count < RESOLVE_MAX_TRY {
            // Note that if the current try already succeeds, the next retransmission
            // will be no-op as the cache has been updated.
            //
            // Back off exponentially
            let next_delay = RESOLVE_RETRY_BASE_MILLIS << try_count;
            let next_time = Instant::now() + Duration::from_millis(next_delay);
            self.add_retransmission(next_time, Command::Resolve(instance, try_count + 1));
        } else {
            // This fast-path retry chain is ending.
            self.pending_resolves.remove(&instance);
        }
    }

    fn exec_command_unregister(
        &mut self,
        repeating: bool,
        fullname: String,
        resp_s: Sender<UnregisterStatus>,
    ) {
        let response = match self.my_services.remove_entry(&fullname) {
            None => {
                debug!("unregister: cannot find such service {}", fullname);
                UnregisterStatus::NotFound
            }
            Some((_k, info)) => {
                let mut timers = Vec::new();

                for (if_index, intf) in self.my_intfs.iter() {
                    if let Some(sock) = self.ipv4_sock.as_ref() {
                        let packet = self.unregister_service(&info, intf, &sock.pktinfo);
                        // repeat for one time just in case some peers miss the message
                        if !repeating && !packet.is_empty() {
                            let next_time = Instant::now() + Duration::from_millis(120);
                            self.retransmissions.push(ReRun {
                                next_time,
                                command: Command::UnregisterResend(packet, *if_index, true),
                            });
                            timers.push(next_time);
                        }
                    }

                    // ipv6
                    if let Some(sock) = self.ipv6_sock.as_ref() {
                        let packet = self.unregister_service(&info, intf, &sock.pktinfo);
                        if !repeating && !packet.is_empty() {
                            let next_time = Instant::now() + Duration::from_millis(120);
                            self.retransmissions.push(ReRun {
                                next_time,
                                command: Command::UnregisterResend(packet, *if_index, false),
                            });
                            timers.push(next_time);
                        }
                    }
                }

                for t in timers {
                    self.add_timer(t);
                }

                self.increase_counter(Counter::Unregister, 1);
                UnregisterStatus::OK
            }
        };
        if let Err(e) = resp_s.send(response) {
            debug!("unregister: failed to send response: {}", e);
        }
    }

    fn exec_command_unregister_resend(&mut self, packet: Vec<u8>, if_index: u32, is_ipv4: bool) {
        let Some(intf) = self.my_intfs.get(&if_index) else {
            return;
        };
        let sock_opt = if is_ipv4 {
            &self.ipv4_sock
        } else {
            &self.ipv6_sock
        };
        let Some(sock) = sock_opt else {
            return;
        };

        let if_addr = if is_ipv4 {
            match intf.next_ifaddr_v4() {
                Some(addr) => addr,
                None => return,
            }
        } else {
            match intf.next_ifaddr_v6() {
                Some(addr) => addr,
                None => return,
            }
        };

        debug!("UnregisterResend from {:?}", if_addr);
        multicast_on_intf(
            &packet[..],
            &intf.name,
            intf.index,
            if_addr,
            &sock.pktinfo,
            self.port,
        );

        self.increase_counter(Counter::UnregisterResend, 1);
    }

    fn exec_command_stop_browse(&mut self, ty_domain: String) {
        match self.remove_service_subscription(&ty_domain) {
            None => debug!("StopBrowse: cannot find querier for {}", ty_domain),
            Some(sender) => {
                // Remove cache entries.
                self.cache.remove_service_type(&ty_domain);

                trace!("StopBrowse: removed queryer for {}", ty_domain);
                match sender.try_send(ServiceEvent::SearchStopped(ty_domain)) {
                    Ok(()) => trace!("Sent SearchStopped to the listener"),
                    Err(e) => debug!("Failed to send SearchStopped: {}", e),
                }
            }
        }
    }

    fn exec_command_stop_resolve_hostname(&mut self, hostname: String) {
        if let Some((sender, _timeout)) = self.remove_hostname_subscription(&hostname) {
            trace!("StopResolve: removed queryer for {}", hostname);
            match sender.try_send(HostnameResolutionEvent::SearchStopped(hostname)) {
                Ok(()) => trace!("Sent SearchStopped to the listener"),
                Err(e) => debug!("Failed to send SearchStopped: {}", e),
            }
        }
    }

    fn exec_command_register_resend(&mut self, fullname: String, if_index: u32) -> MyResult<()> {
        let Some(info) = self.my_services.get_mut(&fullname) else {
            trace!("announce: cannot find such service {}", fullname);
            return Ok(());
        };

        let Some(dns_registry) = self.dns_registry_map.get_mut(&if_index) else {
            return Ok(());
        };

        let Some(intf) = self.my_intfs.get(&if_index) else {
            return Ok(());
        };

        let announced_v4 = if let Some(sock) = self.ipv4_sock.as_ref() {
            announce_service_on_intf(dns_registry, info, intf, &sock.pktinfo, self.port)?
        } else {
            false
        };
        let announced_v6 = if let Some(sock) = self.ipv6_sock.as_ref() {
            announce_service_on_intf(dns_registry, info, intf, &sock.pktinfo, self.port)?
        } else {
            false
        };

        if announced_v4 || announced_v6 {
            let hostname = dns_registry.resolve_name(info.get_hostname());
            let service_name = dns_registry.resolve_name(&fullname).to_string();

            debug!("resend: announce service {service_name} on {}", intf.name);

            notify_monitors(
                &mut self.monitors,
                DaemonEvent::Announce(service_name, format!("{}:{}", hostname, intf.name)),
            );
            info.set_status(if_index, ServiceStatus::Announced);
        } else {
            debug!("register-resend should not fail");
        }

        self.increase_counter(Counter::RegisterResend, 1);
        Ok(())
    }

    fn exec_command_verify(&mut self, instance: String, timeout: Duration, repeating: bool) {
        /*
        RFC 6762 section 10.4:
        ...
        When the cache receives this hint that it should reconfirm some
        record, it MUST issue two or more queries for the resource record in
        dispute.  If no response is received within ten seconds, then, even
        though its TTL may indicate that it is not yet due to expire, that
        record SHOULD be promptly flushed from the cache.
        */
        let now = Instant::now();
        let expire_at = if repeating {
            None
        } else {
            Some(now + Duration::from_millis(timeout.as_millis() as u64))
        };

        // send query for the resource records.
        let record_vec = self.cache.service_verify_queries(&instance, expire_at);

        if !record_vec.is_empty() {
            let query_vec: Vec<(&str, RRType)> = record_vec
                .iter()
                .map(|(record, rr_type)| (record.as_str(), *rr_type))
                .collect();
            self.send_query_vec(&query_vec);

            if let Some(new_expire) = expire_at {
                self.add_timer(new_expire); // ensure a check for the new expire time.

                // schedule a resend 1 second later
                self.add_retransmission(
                    now + Duration::from_millis(1000),
                    Command::Verify(instance, timeout),
                );
            }
        }
    }

    /// Refresh cached service records with active queriers
    fn refresh_active_services(&mut self) {
        let mut query_ptr_count = 0;
        let mut query_srv_count = 0;
        let mut new_timers = HashSet::new();
        let mut query_addr_count = 0;

        for ty_domain in self.service_queriers.keys() {
            let refreshed_timers = self.cache.refresh_due_ptr(ty_domain);
            if !refreshed_timers.is_empty() {
                trace!("sending refresh query for PTR: {}", ty_domain);
                self.send_query(ty_domain, RRType::PTR);
                query_ptr_count += 1;
                new_timers.extend(refreshed_timers);
            }

            let (instances, timers) = self.cache.refresh_due_srv_txt(ty_domain);
            for (instance, types) in instances {
                trace!("sending refresh query for: {}", instance);
                let query_vec = types
                    .into_iter()
                    .map(|ty| (instance.as_str(), ty))
                    .collect::<Vec<_>>();
                self.send_query_vec(&query_vec);
                query_srv_count += 1;
            }
            new_timers.extend(timers);
            let (hostnames, timers) = self.cache.refresh_due_hosts(ty_domain);
            for hostname in hostnames.iter() {
                trace!("sending refresh queries for A and AAAA:  {}", hostname);
                self.send_query_vec(&[(hostname, RRType::A), (hostname, RRType::AAAA)]);
                query_addr_count += 2;
            }
            new_timers.extend(timers);
        }

        for timer in new_timers {
            self.add_timer(timer);
        }

        self.increase_counter(Counter::CacheRefreshPTR, query_ptr_count);
        self.increase_counter(Counter::CacheRefreshSrvTxt, query_srv_count);
        self.increase_counter(Counter::CacheRefreshAddr, query_addr_count);
    }
}

/// Adds one or more answers of a service for incoming msg and RR entry name.
fn add_answer_of_service(
    out: &mut DnsOutgoing,
    msg: &DnsIncoming,
    entry_name: &str,
    service: &ServiceInfo,
    qtype: RRType,
    intf_addrs: Vec<IpAddr>,
) {
    if qtype == RRType::SRV || qtype == RRType::ANY {
        out.add_answer(
            msg,
            DnsSrv::new(
                entry_name,
                CLASS_IN | CLASS_CACHE_FLUSH,
                service.get_host_ttl(),
                service.get_priority(),
                service.get_weight(),
                service.get_port(),
                service.get_hostname().to_string(),
            ),
        );
    }

    if qtype == RRType::TXT || qtype == RRType::ANY {
        out.add_answer(
            msg,
            DnsTxt::new(
                entry_name,
                CLASS_IN | CLASS_CACHE_FLUSH,
                service.get_other_ttl(),
                service.generate_txt(),
            ),
        );
    }

    if qtype == RRType::SRV {
        for address in intf_addrs {
            out.add_additional_answer(DnsAddress::new(
                service.get_hostname(),
                ip_address_rr_type(&address),
                CLASS_IN | CLASS_CACHE_FLUSH,
                service.get_host_ttl(),
                address,
                InterfaceId::default(),
            ));
        }
    }
}

/// Answers a query for a hostname we own: A/AAAA (address records), SVCB/HTTPS
/// (service-binding records), or ANY.
///
/// Adds the A/AAAA records held on `intf` for every announced service whose
/// hostname matches the question. If the queried address family is absent, adds
/// NSEC (negative) answer instead. SVCB/HTTPS always get the NSEC answer.
fn answer_hostname_question(
    services: &HashMap<String, ServiceInfo>,
    intf: &MyIntf,
    question: &DnsQuestion,
    dns_registry: &DnsRegistry,
    out: &mut DnsOutgoing,
    msg: &DnsIncoming,
) {
    let if_index = intf.index;
    let qtype = question.entry_type();
    let mut hostname = None;
    let mut host_ttl = u32::MAX;
    let mut has_ipv4 = false;
    let mut has_ipv6 = false;
    for service in services.values() {
        if service.get_status(if_index) != ServiceStatus::Announced {
            continue;
        }

        let service_hostname = dns_registry.resolve_name(service.get_hostname());

        if service_hostname.to_lowercase() == question.entry_name().to_lowercase() {
            let ipv4 = service.get_addrs_on_my_intf_v4(intf);
            let ipv6 = service.get_addrs_on_my_intf_v6(intf);
            if ipv4.is_empty() && ipv6.is_empty() {
                continue;
            }
            hostname = Some(service_hostname);
            host_ttl = host_ttl.min(service.get_host_ttl());
            has_ipv4 |= !ipv4.is_empty();
            has_ipv6 |= !ipv6.is_empty();
            // Pick addresses based on the question type, not the
            // socket family. RFC 6762 doesn't require A queries
            // to come over IPv4 transport — Android's getaddrinfo
            // routinely sends both A and AAAA queries over its
            // preferred IPv6 mDNS socket and expects A records
            // to be answered with v4 addresses.
            let mut intf_addrs: Vec<IpAddr> = Vec::new();
            if qtype == RRType::A || qtype == RRType::ANY {
                intf_addrs.extend(ipv4);
            }
            if qtype == RRType::AAAA || qtype == RRType::ANY {
                intf_addrs.extend(ipv6);
            }
            for address in intf_addrs {
                out.add_answer(
                    msg,
                    DnsAddress::new(
                        service_hostname,
                        ip_address_rr_type(&address),
                        CLASS_IN | CLASS_CACHE_FLUSH,
                        service.get_host_ttl(),
                        address,
                        intf.into(),
                    ),
                );
            }
        }
    }
    let missing = match qtype {
        RRType::A => !has_ipv4,
        RRType::AAAA => !has_ipv6,
        RRType::SVCB | RRType::HTTPS => true,
        _ => false,
    };
    if let Some(hostname) = hostname.filter(|_| missing) {
        // RFC 6762 section 6.1: explicitly deny absent records
        // only for a hostname we own on this interface. Combine
        // all announced services sharing the hostname, so one
        // registration cannot deny another's address family.
        let bitmap = if has_ipv6 {
            vec![if has_ipv4 { 0x40 } else { 0 }, 0, 0, 0x08]
        } else {
            vec![0x40]
        };
        out.add_answer(
            msg,
            DnsNSec::new(
                hostname,
                CLASS_IN | CLASS_CACHE_FLUSH,
                host_ttl,
                hostname.to_string(),
                bitmap,
            ),
        );
    }
}

/// All possible events sent to the client from the daemon
/// regarding service discovery.
#[derive(Clone, Debug)]
#[non_exhaustive]
pub enum ServiceEvent {
    /// Started searching for a service type.
    SearchStarted(String),

    /// Found a specific (service_type, fullname).
    ServiceFound(String, String),

    /// Resolved a service instance in a ResolvedService struct.
    ServiceResolved(Box<ResolvedService>),

    /// A service instance (service_type, fullname) was removed.
    ServiceRemoved(String, String),

    /// Stopped searching for a service type.
    SearchStopped(String),
}

/// All possible events sent to the client from the daemon
/// regarding host resolution.
#[derive(Clone, Debug)]
#[non_exhaustive]
pub enum HostnameResolutionEvent {
    /// Started searching for the ip address of a hostname.
    SearchStarted(String),
    /// One or more addresses for a hostname has been found.
    AddressesFound(String, HashSet<ScopedIp>),
    /// One or more addresses for a hostname has been removed.
    AddressesRemoved(String, HashSet<ScopedIp>),
    /// The search for the ip address of a hostname has timed out.
    SearchTimeout(String),
    /// Stopped searching for the ip address of a hostname.
    SearchStopped(String),
}

/// Some notable events from the daemon besides [`ServiceEvent`].
/// These events are expected to happen infrequently.
#[derive(Clone, Debug)]
#[non_exhaustive]
pub enum DaemonEvent {
    /// Daemon unsolicitly announced a service from an interface.
    Announce(String, String),

    /// Daemon encountered an error.
    Error(Error),

    /// Daemon detected a new IP address from the host.
    IpAdd(IpAddr),

    /// Daemon detected a IP address removed from the host.
    IpDel(IpAddr),

    /// Daemon resolved a name conflict by changing one of its names.
    /// see [DnsNameChange] for more details.
    NameChange(DnsNameChange),

    /// Send out a multicast response via an interface.
    Respond(String),
}

/// Represents a name change due to a name conflict resolution.
/// See [RFC 6762 section 9](https://datatracker.ietf.org/doc/html/rfc6762#section-9)
#[derive(Clone, Debug)]
pub struct DnsNameChange {
    /// The original name set in `ServiceInfo` by the user.
    pub original: String,

    /// A new name is created by appending a suffix after the original name.
    ///
    /// - for a service instance name, the suffix is `(N)`, where N starts at 2.
    /// - for a host name, the suffix is `-N`, where N starts at 2.
    ///
    /// For example:
    ///
    /// - Service name `foo._service-type._udp` becomes `foo (2)._service-type._udp`
    /// - Host name `foo.local.` becomes `foo-2.local.`
    pub new_name: String,

    /// The resource record type
    pub rr_type: RRType,

    /// The interface where the name conflict and its change happened.
    pub intf_name: String,
}

/// Commands supported by the daemon
#[derive(Debug)]
enum Command {
    /// Browsing for a service type (ty_domain, next_time_delay_in_seconds, channel::sender)
    Browse(String, u32, bool, Sender<ServiceEvent>),

    /// Resolve a hostname to IP addresses.
    ResolveHostname(String, u32, Sender<HostnameResolutionEvent>, Option<u64>), // (hostname, next_time_delay_in_seconds, sender, timeout_in_milliseconds)

    /// Register a service
    Register(Box<ServiceInfo>),

    /// Unregister a service
    Unregister(String, Sender<UnregisterStatus>), // (fullname)

    /// Announce again a service to local network
    RegisterResend(String, u32), // (fullname)

    /// Resend unregister packet.
    UnregisterResend(Vec<u8>, u32, bool), // (packet content, if_index, is_ipv4)

    /// Stop browsing a service type
    StopBrowse(String), // (ty_domain)

    /// Stop resolving a hostname
    StopResolveHostname(String), // (hostname)

    /// Send query to resolve a service instance.
    /// This is used when a PTR record exists but SRV & TXT records are missing.
    Resolve(String, u16), // (service_instance_fullname, try_count)

    /// Read the current values of the counters
    GetMetrics(Sender<Metrics>),

    /// Get the current status of the daemon.
    GetStatus(Sender<DaemonStatus>),

    /// Monitor noticeable events in the daemon.
    Monitor(Sender<DaemonEvent>),

    SetOption(DaemonOption),

    GetOption(Sender<DaemonOptionVal>),

    /// Proactively confirm a DNS resource record.
    ///
    /// The intention is to check if a service name or IP address still valid
    /// before its TTL expires.
    Verify(String, Duration),

    /// Invalidate some interface addresses.
    InvalidIntfAddrs(HashSet<Interface>),

    Exit(Sender<DaemonStatus>),
}

impl fmt::Display for Command {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Browse(_, _, _, _) => write!(f, "Command Browse"),
            Self::ResolveHostname(_, _, _, _) => write!(f, "Command ResolveHostname"),
            Self::Exit(_) => write!(f, "Command Exit"),
            Self::GetStatus(_) => write!(f, "Command GetStatus"),
            Self::GetMetrics(_) => write!(f, "Command GetMetrics"),
            Self::Monitor(_) => write!(f, "Command Monitor"),
            Self::Register(_) => write!(f, "Command Register"),
            Self::RegisterResend(_, _) => write!(f, "Command RegisterResend"),
            Self::SetOption(_) => write!(f, "Command SetOption"),
            Self::GetOption(_) => write!(f, "Command GetOption"),
            Self::StopBrowse(_) => write!(f, "Command StopBrowse"),
            Self::StopResolveHostname(_) => write!(f, "Command StopResolveHostname"),
            Self::Unregister(_, _) => write!(f, "Command Unregister"),
            Self::UnregisterResend(_, _, _) => write!(f, "Command UnregisterResend"),
            Self::Resolve(_, _) => write!(f, "Command Resolve"),
            Self::Verify(_, _) => write!(f, "Command VerifyResource"),
            Self::InvalidIntfAddrs(_) => write!(f, "Command InvalidIntfAddrs"),
        }
    }
}

struct DaemonOptionVal {
    _service_name_len_max: u8,
    ip_check_interval: u64,
}

#[derive(Debug)]
enum DaemonOption {
    ServiceNameLenMax(u8),
    IpCheckInterval(u64),
    MaxPacketSize(Vec<IfKind>, usize),
    EnableInterface(Vec<IfKind>),
    DisableInterface(Vec<IfKind>),
    MulticastLoopV4(bool),
    MulticastLoopV6(bool),
    AcceptUnsolicited(bool),
    IncludeAppleP2P(bool),
    #[cfg(test)]
    TestDownInterface(String),
    #[cfg(test)]
    TestUpInterface(String),
}

/// The length of Service Domain name supported in this lib.
const DOMAIN_LEN: usize = "._tcp.local.".len();

/// Returns how long the system slept, given how far `Instant` and the wall
/// clock moved over the same period, or `None` if it did not sleep.
fn slept_duration(instant_elapsed: Duration, wall_elapsed: Option<Duration>) -> Option<Duration> {
    let gap = wall_elapsed?.checked_sub(instant_elapsed)?;
    (gap > SLEEP_DETECTION_THRESHOLD).then_some(gap)
}

/// Validate the length of "service_name" in a "_<service_name>.<domain_name>." string.
fn check_service_name_length(ty_domain: &str, limit: u8) -> Result<()> {
    if ty_domain.len() <= DOMAIN_LEN + 1 {
        // service name cannot be empty or only '_'.
        return Err(e_fmt!("Service type name cannot be empty: {}", ty_domain));
    }

    let service_name_len = ty_domain.len() - DOMAIN_LEN - 1; // exclude the leading `_`
    if service_name_len > limit as usize {
        return Err(e_fmt!("Service name length must be <= {} bytes", limit));
    }
    Ok(())
}

/// Checks if `name` ends with a valid domain: '._tcp.local.' or '._udp.local.'
fn check_domain_suffix(name: &str) -> Result<()> {
    if !(name.ends_with("._tcp.local.") || name.ends_with("._udp.local.")) {
        return Err(e_fmt!(
            "mDNS service {} must end with '._tcp.local.' or '._udp.local.'",
            name
        ));
    }

    Ok(())
}

/// Validate the service name in a fully qualified name.
///
/// A Full Name = <Instance>.<Service>.<Domain>
/// The only `<Domain>` supported are "._tcp.local." and "._udp.local.".
///
/// Note: this function does not check for the length of the service name.
/// Instead, `register_service` method will check the length.
fn check_service_name(fullname: &str) -> Result<()> {
    check_domain_suffix(fullname)?;

    let remaining: Vec<&str> = fullname[..fullname.len() - DOMAIN_LEN].split('.').collect();
    let name = remaining.last().ok_or_else(|| e_fmt!("No service name"))?;

    if &name[0..1] != "_" {
        return Err(e_fmt!("Service name must start with '_'"));
    }

    let name = &name[1..];

    if name.contains("--") {
        return Err(e_fmt!("Service name must not contain '--'"));
    }

    if name.starts_with('-') || name.ends_with('-') {
        return Err(e_fmt!("Service name (%s) may not start or end with '-'"));
    }

    let ascii_count = name.chars().filter(|c| c.is_ascii_alphabetic()).count();
    if ascii_count < 1 {
        return Err(e_fmt!(
            "Service name must contain at least one letter (eg: 'A-Za-z')"
        ));
    }

    Ok(())
}

/// Validate a hostname.
fn check_hostname(hostname: &str) -> Result<()> {
    if !hostname.ends_with(".local.") {
        return Err(e_fmt!("Hostname must end with '.local.': {hostname}"));
    }

    if hostname == ".local." {
        return Err(e_fmt!(
            "The part of the hostname before '.local.' cannot be empty"
        ));
    }

    if hostname.len() > 255 {
        return Err(e_fmt!("Hostname length must be <= 255 bytes"));
    }

    Ok(())
}

/// Returns valid network interfaces in the host system.
/// Operational down interfaces are excluded.
/// Loopback interfaces are excluded if `with_loopback` is false.
fn my_ip_interfaces(with_loopback: bool) -> Vec<Interface> {
    my_ip_interfaces_inner(with_loopback, false)
}

fn my_ip_interfaces_inner(with_loopback: bool, with_apple_p2p: bool) -> Vec<Interface> {
    if_addrs::get_if_addrs()
        .unwrap_or_default()
        .into_iter()
        .filter(|i| {
            i.is_oper_up()
                && !i.is_p2p()
                && (!i.is_loopback() || with_loopback)
                && (with_apple_p2p || !is_apple_p2p_by_name(&i.name))
        })
        .collect()
}

/// Checks if the interface name indicates it's an Apple peer-to-peer interface,
/// which should be ignored by default.
fn is_apple_p2p_by_name(name: &str) -> bool {
    let p2p_prefixes = ["awdl", "llw"];
    p2p_prefixes.iter().any(|prefix| name.starts_with(prefix))
}

/// How to encode and where to send outgoing messages on one interface.
#[derive(Clone, Copy, Debug)]
struct SendConfig {
    /// The mDNS port to send to.
    port: u16,

    /// Max byte size of a generated packet.
    /// See [`ServiceDaemon::set_max_packet_size`].
    max_packet_size: usize,

    /// Whether the packets go out over IPv4, which decides their absolute
    /// ceiling: see [`max_pkt_absolute`].
    is_ipv4: bool,
}

/// Send an outgoing mDNS query or response, and returns the packet bytes.
/// Returns empty vec if no valid interface address is found.
fn send_dns_outgoing(
    out: &DnsOutgoing,
    my_intf: &MyIntf,
    sock: &PktInfoUdpSocket,
    port: u16,
    source: Option<&IfAddr>,
    unicast_dest: Option<SocketAddr>,
) -> MyResult<Vec<Vec<u8>>> {
    let if_name = &my_intf.name;

    let if_addr = match source {
        Some(addr) => addr,
        None => {
            if sock.domain() == Domain::IPV4 {
                match my_intf.next_ifaddr_v4() {
                    Some(addr) => addr,
                    None => return Ok(vec![]),
                }
            } else {
                match my_intf.next_ifaddr_v6() {
                    Some(addr) => addr,
                    None => return Ok(vec![]),
                }
            }
        }
    };

    // The limits are per address family, so read them off the address we send from.
    let is_ipv4 = if_addr.ip().is_ipv4();
    let config = SendConfig {
        port,
        max_packet_size: my_intf.max_packet_size(is_ipv4),
        is_ipv4,
    };

    send_dns_outgoing_impl(
        out,
        if_name,
        my_intf.index,
        if_addr,
        sock,
        config,
        unicast_dest,
    )
}

/// Send an outgoing mDNS query or response, and returns the packet bytes.
fn send_dns_outgoing_impl(
    out: &DnsOutgoing,
    if_name: &str,
    if_index: u32,
    if_addr: &IfAddr,
    sock: &PktInfoUdpSocket,
    config: SendConfig,
    unicast_dest: Option<SocketAddr>,
) -> MyResult<Vec<Vec<u8>>> {
    let qtype = if out.is_query() {
        "query"
    } else {
        if out.answers_count() == 0 && out.additionals().is_empty() {
            return Ok(vec![]); // no need to send empty response
        }
        "response"
    };
    trace!(
        "send {}: {} questions {} answers {} authorities {} additional",
        qtype,
        out.questions().len(),
        out.answers_count(),
        out.authorities().len(),
        out.additionals().len()
    );

    match if_addr.ip() {
        IpAddr::V4(ipv4) => {
            if let Err(e) = sock.set_multicast_if_v4(&ipv4) {
                debug!(
                    "send_dns_outgoing: failed to set multicast interface for IPv4 {}: {}",
                    ipv4, e
                );
                // cannot send without a valid interface
                if e.kind() == std::io::ErrorKind::AddrNotAvailable {
                    let intf_addr = Interface {
                        name: if_name.to_string(),
                        addr: if_addr.clone(),
                        index: Some(if_index),
                        oper_status: if_addrs::IfOperStatus::Down,
                        is_p2p: false,
                        #[cfg(windows)]
                        adapter_name: String::new(),
                    };
                    return Err(InternalError::IntfAddrInvalid(intf_addr));
                }
                return Ok(vec![]); // non-fatal other failure
            }
        }
        IpAddr::V6(ipv6) => {
            if let Err(e) = sock.set_multicast_if_v6(if_index) {
                debug!(
                    "send_dns_outgoing: failed to set multicast interface for IPv6 {}: {}",
                    ipv6, e
                );
                // cannot send without a valid interface
                if e.kind() == std::io::ErrorKind::AddrNotAvailable {
                    let intf_addr = Interface {
                        name: if_name.to_string(),
                        addr: if_addr.clone(),
                        index: Some(if_index),
                        oper_status: if_addrs::IfOperStatus::Down,
                        is_p2p: false,
                        #[cfg(windows)]
                        adapter_name: String::new(),
                    };
                    return Err(InternalError::IntfAddrInvalid(intf_addr));
                }
                return Ok(vec![]); // non-fatal other failure
            }
        }
    }

    let packet_list = out.to_data_on_wire(config.max_packet_size, config.is_ipv4);
    for packet in packet_list.iter() {
        match unicast_dest {
            Some(dest) => unicast_on_intf(packet, if_name, dest, sock),
            None => multicast_on_intf(packet, if_name, if_index, if_addr, sock, config.port),
        }
    }
    Ok(packet_list)
}

/// Sends a unicast packet directly to `dest` (used for RFC 6762 §6.7
/// legacy unicast responses).
fn unicast_on_intf(packet: &[u8], if_name: &str, dest: SocketAddr, socket: &PktInfoUdpSocket) {
    let max_size = max_pkt_absolute(dest.is_ipv4());
    if packet.len() > max_size {
        debug!("Drop over-sized packet ({} > {max_size})", packet.len());
        return;
    }

    let sock_addr = dest.into();
    match socket.send_to(packet, &sock_addr) {
        Ok(sz) => trace!(
            "sent unicast {} bytes on interface {} to {}",
            sz,
            if_name,
            dest
        ),
        Err(e) => trace!(
            "Failed to send unicast to {} via {:?}: {}",
            dest,
            if_name,
            e
        ),
    }
}

/// Sends a multicast packet, and returns the packet bytes.
fn multicast_on_intf(
    packet: &[u8],
    if_name: &str,
    if_index: u32,
    if_addr: &IfAddr,
    socket: &PktInfoUdpSocket,
    port: u16,
) {
    let max_size = max_pkt_absolute(if_addr.ip().is_ipv4());
    if packet.len() > max_size {
        debug!("Drop over-sized packet ({} > {max_size})", packet.len());
        return;
    }

    let addr: SocketAddr = match if_addr {
        if_addrs::IfAddr::V4(_) => SocketAddrV4::new(GROUP_ADDR_V4, port).into(),
        if_addrs::IfAddr::V6(_) => {
            let mut sock = SocketAddrV6::new(GROUP_ADDR_V6, port, 0, 0);
            sock.set_scope_id(if_index); // Choose iface for multicast
            sock.into()
        }
    };

    // Sends out `packet` to `addr` on the socket.
    let sock_addr = addr.into();
    match socket.send_to(packet, &sock_addr) {
        Ok(sz) => trace!(
            "sent out {} bytes on interface {} (idx {}) addr {}",
            sz,
            if_name,
            if_index,
            if_addr.ip()
        ),
        Err(e) => trace!("Failed to send to {} via {:?}: {}", addr, if_name, e),
    }
}

/// Returns true if `name` is a valid instance name of format:
/// <instance>.<service_type>.<_udp|_tcp>.local.
/// Note: <instance> could contain '.' as well.
fn valid_instance_name(name: &str) -> bool {
    name.split('.').count() >= 5
}

fn notify_monitors(monitors: &mut Vec<Sender<DaemonEvent>>, event: DaemonEvent) {
    monitors.retain(|sender| {
        if let Err(e) = sender.try_send(event.clone()) {
            debug!("notify_monitors: try_send: {}", e);
            if matches!(e, TrySendError::Disconnected(_)) {
                return false; // This monitor is dropped.
            }
        }
        true
    });
}

/// Check if all unique records passed "probing", and if yes, create a packet
/// to announce the service.
fn prepare_announce(
    info: &ServiceInfo,
    intf: &MyIntf,
    dns_registry: &mut DnsRegistry,
    is_ipv4: bool,
) -> Option<DnsOutgoing> {
    let intf_addrs = if is_ipv4 {
        info.get_addrs_on_my_intf_v4(intf)
    } else {
        info.get_addrs_on_my_intf_v6(intf)
    };

    if intf_addrs.is_empty() {
        debug!(
            "prepare_announce (ipv4: {is_ipv4}): no valid addrs on interface {}",
            intf.name
        );
        return None;
    }

    // check if we changed our name due to conflicts.
    let service_fullname = dns_registry.resolve_name(info.get_fullname());

    debug!(
        "prepare to announce service {service_fullname} on {:?}",
        intf_addrs
    );

    let mut probing_count = 0;
    let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
    let create_time = Instant::now() + Duration::from_millis(fastrand::u64(0..250));

    out.add_answer_record(DnsPointer::new(
        info.get_type(),
        RRType::PTR,
        CLASS_IN,
        info.get_other_ttl(),
        service_fullname.to_string(),
    ));

    if let Some(sub) = info.get_subtype() {
        trace!("Adding subdomain {}", sub);
        out.add_answer_record(DnsPointer::new(
            sub,
            RRType::PTR,
            CLASS_IN,
            info.get_other_ttl(),
            service_fullname.to_string(),
        ));
    }

    // SRV records.
    let hostname = dns_registry.resolve_name(info.get_hostname()).to_string();

    let mut srv = DnsSrv::new(
        info.get_fullname(),
        CLASS_IN | CLASS_CACHE_FLUSH,
        info.get_host_ttl(),
        info.get_priority(),
        info.get_weight(),
        info.get_port(),
        hostname,
    );

    if let Some(new_name) = dns_registry.name_changes.get(info.get_fullname()) {
        srv.get_record_mut().set_new_name(new_name.to_string());
    }

    if !info.requires_probe()
        || dns_registry.is_probing_done(&srv, info.get_fullname(), create_time)
    {
        out.add_answer_record(srv);
    } else {
        probing_count += 1;
    }

    // TXT records.

    let mut txt = DnsTxt::new(
        info.get_fullname(),
        CLASS_IN | CLASS_CACHE_FLUSH,
        info.get_other_ttl(),
        info.generate_txt(),
    );

    if let Some(new_name) = dns_registry.name_changes.get(info.get_fullname()) {
        txt.get_record_mut().set_new_name(new_name.to_string());
    }

    if !info.requires_probe()
        || dns_registry.is_probing_done(&txt, info.get_fullname(), create_time)
    {
        out.add_answer_record(txt);
    } else {
        probing_count += 1;
    }

    // Address records. (A and AAAA)

    let hostname = info.get_hostname();
    for address in intf_addrs {
        let mut dns_addr = DnsAddress::new(
            hostname,
            ip_address_rr_type(&address),
            CLASS_IN | CLASS_CACHE_FLUSH,
            info.get_host_ttl(),
            address,
            intf.into(),
        );

        if let Some(new_name) = dns_registry.name_changes.get(hostname) {
            dns_addr.get_record_mut().set_new_name(new_name.to_string());
        }

        if !info.requires_probe()
            || dns_registry.is_probing_done(&dns_addr, info.get_fullname(), create_time)
        {
            out.add_answer_record(dns_addr);
        } else {
            probing_count += 1;
        }
    }

    if probing_count > 0 {
        return None;
    }

    Some(out)
}

/// Send an unsolicited response for owned service via `intf` and `sock`.
/// Returns true if sent out successfully for IPv4 or IPv6.
fn announce_service_on_intf(
    dns_registry: &mut DnsRegistry,
    info: &ServiceInfo,
    intf: &MyIntf,
    sock: &PktInfoUdpSocket,
    port: u16,
) -> MyResult<bool> {
    let is_ipv4 = sock.domain() == Domain::IPV4;
    if let Some(mut out) = prepare_announce(info, intf, dns_registry, is_ipv4) {
        // RFC 6762 §6: a record MUST NOT be multicast on an interface more than
        // once per second. Announcements are unsolicited multicast responses.
        dns_registry.apply_multicast_rate_limit(&mut out, Instant::now(), is_ipv4);
        if out.answers_count() > 0 {
            let _ = send_dns_outgoing(&out, intf, sock, port, None, None)?;
        }
        return Ok(true);
    }

    Ok(false)
}

/// Returns a new name based on the `original` to avoid conflicts.
/// If the name already contains a number in parentheses, increments that number.
///
/// Examples:
/// - `foo.local.` becomes `foo (2).local.`
/// - `foo (2).local.` becomes `foo (3).local.`
/// - `foo (9)` becomes `foo (10)`
fn name_change(original: &str) -> String {
    let mut parts: Vec<_> = original.split('.').collect();
    let Some(first_part) = parts.get_mut(0) else {
        return format!("{original} (2)");
    };

    let mut new_name = format!("{first_part} (2)");

    // check if there is already has `(<num>)` suffix.
    if let Some(paren_pos) = first_part.rfind(" (") {
        // Check if there's a closing parenthesis
        if let Some(end_paren) = first_part[paren_pos..].find(')') {
            let absolute_end_pos = paren_pos + end_paren;
            // Only process if the closing parenthesis is the last character
            if absolute_end_pos == first_part.len() - 1 {
                let num_start = paren_pos + 2; // Skip " ("
                                               // Try to parse the number between parentheses
                if let Ok(number) = first_part[num_start..absolute_end_pos].parse::<u32>() {
                    let base_name = &first_part[..paren_pos];
                    new_name = format!("{} ({})", base_name, number + 1)
                }
            }
        }
    }

    *first_part = &new_name;
    parts.join(".")
}

/// Returns a new name based on the `original` to avoid conflicts.
/// If the name already contains a hyphenated number, increments that number.
///
/// Examples:
/// - `foo.local.` becomes `foo-2.local.`
/// - `foo-2.local.` becomes `foo-3.local.`
/// - `foo` becomes `foo-2`
fn hostname_change(original: &str) -> String {
    let mut parts: Vec<_> = original.split('.').collect();
    let Some(first_part) = parts.get_mut(0) else {
        return format!("{original}-2");
    };

    let mut new_name = format!("{first_part}-2");

    // check if there is already a `-<num>` suffix
    if let Some(hyphen_pos) = first_part.rfind('-') {
        // Try to parse everything after the hyphen as a number
        if let Ok(number) = first_part[hyphen_pos + 1..].parse::<u32>() {
            let base_name = &first_part[..hyphen_pos];
            new_name = format!("{}-{}", base_name, number + 1);
        }
    }

    *first_part = &new_name;
    parts.join(".")
}

/// Check probes in a registry and returns: a probing packet to send out, and a list of probe names
/// that are finished.
fn check_probing(
    dns_registry: &mut DnsRegistry,
    timers: &mut BinaryHeap<Reverse<Instant>>,
    now: Instant,
) -> (DnsOutgoing, Vec<String>) {
    let mut expired_probes = Vec::new();
    let mut out = DnsOutgoing::new(FLAGS_QR_QUERY);

    for (name, probe) in dns_registry.probing.iter_mut() {
        if now >= probe.next_send {
            if probe.expired(now) {
                // move the record to active
                expired_probes.push(name.clone());
            } else {
                out.add_question(name, RRType::ANY);

                /*
                RFC 6762 section 8.2: https://datatracker.ietf.org/doc/html/rfc6762#section-8.2
                ...
                for tiebreaking to work correctly in all
                cases, the Authority Section must contain *all* the records and
                proposed rdata being probed for uniqueness.
                    */
                for record in probe.records.iter() {
                    out.add_authority(record.clone());
                }

                probe.update_next_send(now);

                // add timer
                timers.push(Reverse(probe.next_send));
            }
        }
    }

    (out, expired_probes)
}

/// Process expired probes on an interface and return a list of services
/// that are waiting for the probe to finish.
///
/// `DnsNameChange` events are sent to the monitors.
fn handle_expired_probes(
    expired_probes: Vec<String>,
    intf_name: &str,
    dns_registry: &mut DnsRegistry,
    monitors: &mut Vec<Sender<DaemonEvent>>,
) -> HashSet<String> {
    let mut waiting_services = HashSet::new();

    for name in expired_probes {
        let Some(probe) = dns_registry.probing.remove(&name) else {
            continue;
        };

        // send notifications about name changes
        for record in probe.records.iter() {
            if let Some(new_name) = record.get_record().get_new_name() {
                dns_registry
                    .name_changes
                    .insert(name.clone(), new_name.to_string());

                let event = DnsNameChange {
                    original: record.get_record().get_original_name().to_string(),
                    new_name: new_name.to_string(),
                    rr_type: record.get_type(),
                    intf_name: intf_name.to_string(),
                };
                debug!("Name change event: {:?}", event);
                notify_monitors(monitors, DaemonEvent::NameChange(event));
            }
        }

        // move RR from probe to active.
        debug!(
            "probe of '{name}' finished: move {} records to active. ({} waiting services)",
            probe.records.len(),
            probe.waiting_services.len(),
        );

        // Move records to active and plan to wake up services if records are not empty.
        if !probe.records.is_empty() {
            match dns_registry.active.get_mut(&name) {
                Some(records) => {
                    records.extend(probe.records);
                }
                None => {
                    dns_registry.active.insert(name, probe.records);
                }
            }

            waiting_services.extend(probe.waiting_services);
        }
    }

    waiting_services
}

/// Returns the max packet size to use on the interface `if_index` for the given
/// address family, i.e. the size of the last selection matching it, or
/// [`MAX_PKT_DEFAULT`] if none does.
///
/// A selection matches an address, so it applies as soon as any address of the
/// interface in that family matches. That keeps the two families independent:
/// e.g. [`IfKind::IPv4`] leaves the IPv6 side of the interface alone.
fn resolve_max_packet_size(
    selections: &[MaxPacketSizeSelection],
    interfaces: &[Interface],
    if_index: u32,
    is_ipv4: bool,
) -> usize {
    let mut size = MAX_PKT_DEFAULT;

    for selection in selections {
        let matched = interfaces.iter().any(|intf| {
            intf.index.unwrap_or(0) == if_index
                && intf.ip().is_ipv4() == is_ipv4
                && selection.if_kind.matches(intf)
        });
        if matched {
            size = selection.max_packet_size;
        }
    }

    size
}

/// Resolves `IfKind::Addr(ip)` to `IndexV4(if_index)` or `IndexV6(if_index)`.
fn resolve_addr_to_index(if_kind: IfKind, interfaces: &[Interface]) -> IfKind {
    if let IfKind::Addr(addr) = &if_kind {
        if let Some(intf) = interfaces.iter().find(|intf| &intf.ip() == addr) {
            let if_index = intf.index.unwrap_or(0);
            return if addr.is_ipv4() {
                IfKind::IndexV4(if_index)
            } else {
                IfKind::IndexV6(if_index)
            };
        }
    }
    if_kind
}

#[cfg(test)]
mod tests {
    use super::{
        _new_socket_bind, check_domain_suffix, check_service_name_length, hostname_change,
        my_ip_interfaces, name_change, resolve_max_packet_size, send_dns_outgoing_impl,
        valid_instance_name, valid_ip_on_intf, DaemonEvent, HostnameResolutionEvent, IfKind,
        MaxPacketSizeSelection, MyIntf, SendConfig, ServiceDaemon, ServiceEvent, ServiceInfo,
        GROUP_ADDR_V4, INITIAL_QUERY_DELAY_MAX_MILLIS, INITIAL_QUERY_DELAY_MIN_MILLIS,
        MAX_PKT_ABSOLUTE_IPV6, MAX_PKT_DEFAULT, MDNS_PORT, MIN_MAX_PACKET_SIZE, RESOLVE_MAX_TRY,
        SHARED_RESPONSE_DELAY_MAX_MILLIS, SHARED_RESPONSE_DELAY_MIN_MILLIS,
    };
    use crate::{
        dns_parser::{
            DnsAddress, DnsEntryExt, DnsIncoming, DnsOutgoing, DnsPointer, DnsSrv, InterfaceId,
            RRType, ScopedIp, CLASS_IN, FLAGS_AA, FLAGS_QR_QUERY, FLAGS_QR_RESPONSE,
            LEGACY_UNICAST_MAX_TTL,
        },
        service_daemon::{add_answer_of_service, check_hostname},
    };
    use if_addrs::{IfAddr, Ifv4Addr, Ifv6Addr, Interface};
    use std::{
        collections::HashSet,
        net::{IpAddr, Ipv4Addr, Ipv6Addr, UdpSocket},
        thread,
        time::{Duration, Instant, SystemTime},
    };
    use test_log::test;

    /// Builds an interface address for the max packet size tests below.
    fn test_interface(name: &str, index: u32, addr: IfAddr) -> Interface {
        Interface {
            name: name.to_string(),
            addr,
            index: Some(index),
            oper_status: if_addrs::IfOperStatus::Up,
            is_p2p: false,
            #[cfg(windows)]
            adapter_name: String::new(),
        }
    }

    fn test_ifaddr_v4(ip: Ipv4Addr) -> IfAddr {
        IfAddr::V4(Ifv4Addr {
            ip,
            netmask: Ipv4Addr::new(255, 255, 255, 0),
            broadcast: None,
            prefixlen: 24,
        })
    }

    fn test_ifaddr_v6(ip: Ipv6Addr) -> IfAddr {
        IfAddr::V6(Ifv6Addr {
            ip,
            netmask: Ipv6Addr::from(u128::MAX << 64),
            broadcast: None,
            prefixlen: 64,
        })
    }

    /// Builds a daemon on a private port. `Zeroconf::new` joins the mDNS group on
    /// every host interface, loopback included.
    fn new_test_zeroconf() -> super::Zeroconf {
        let (daemon, _receiver) = new_test_zeroconf_with_receiver();
        daemon
    }

    /// Same setup as [`new_test_zeroconf`], plus the command receiver.
    fn new_test_zeroconf_with_receiver() -> (super::Zeroconf, flume::Receiver<super::Command>) {
        let port = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0))
            .unwrap()
            .local_addr()
            .unwrap()
            .port();
        let (sender, receiver) = flume::bounded(100);
        let poller = mio::Poll::new().unwrap();
        let waker = std::sync::Arc::new(
            mio::Waker::new(poller.registry(), mio::Token(super::WAKER_EVENT_KEY)).unwrap(),
        );
        (super::Zeroconf::new(waker, poller, port, sender), receiver)
    }

    fn recv_status(receiver: &flume::Receiver<super::DaemonStatus>) -> super::DaemonStatus {
        receiver
            .recv_timeout(Duration::from_secs(2))
            .expect("daemon command was not processed within 2s")
    }

    /// Submit `status` until it is accepted or the deadline passes.
    /// `Error::Again` is retried because the command channel is bounded.
    fn status_until_accepted(daemon: &ServiceDaemon) -> flume::Receiver<super::DaemonStatus> {
        let deadline = Instant::now() + Duration::from_secs(2);
        loop {
            match daemon.status() {
                Ok(receiver) => return receiver,
                Err(crate::Error::Again) if Instant::now() < deadline => thread::yield_now(),
                Err(e) => panic!("status command was not accepted: {}", e),
            }
        }
    }

    #[test]
    fn test_waker_wakes_sleeping_daemon() {
        let daemon = ServiceDaemon::new().unwrap();
        // The first response means the thread has already run a loop iteration
        // and returned to `poll` before the second command is submitted.
        let first = status_until_accepted(&daemon);
        assert_eq!(recv_status(&first), super::DaemonStatus::Running);

        let second = status_until_accepted(&daemon);
        assert_eq!(recv_status(&second), super::DaemonStatus::Running);

        let shutdown = daemon.shutdown().unwrap();
        assert_eq!(recv_status(&shutdown), super::DaemonStatus::Shutdown);
    }

    #[test]
    fn test_command_submitted_immediately_after_construction() {
        let daemon = ServiceDaemon::new().unwrap();
        let status = daemon.status().expect("enqueue during startup");
        assert_eq!(recv_status(&status), super::DaemonStatus::Running);
        let shutdown = daemon.shutdown().unwrap();
        assert_eq!(recv_status(&shutdown), super::DaemonStatus::Shutdown);
    }

    #[test]
    fn test_concurrent_commands_from_cloned_handles() {
        let daemon = ServiceDaemon::new().unwrap();
        let mut handles = Vec::new();
        for _ in 0..4 {
            let daemon = daemon.clone();
            handles.push(thread::spawn(move || {
                let mut statuses = Vec::new();
                for _ in 0..20 {
                    let receiver = status_until_accepted(&daemon);
                    statuses.push(recv_status(&receiver));
                }
                statuses
            }));
        }

        for handle in handles {
            let statuses = handle.join().expect("status thread");
            assert_eq!(statuses.len(), 20);
            assert!(statuses.iter().all(|s| *s == super::DaemonStatus::Running));
        }

        let shutdown = daemon.shutdown().unwrap();
        assert_eq!(recv_status(&shutdown), super::DaemonStatus::Shutdown);
    }

    #[test]
    fn test_send_cmd_to_self_wakes_poll_and_queues_every_command() {
        let (mut daemon, receiver) = new_test_zeroconf_with_receiver();
        for i in 0..5 {
            daemon
                .send_cmd_to_self(super::Command::StopBrowse(format!("svc{i}._udp.local.")))
                .unwrap();
        }

        let started = Instant::now();
        let mut events = mio::Events::with_capacity(16);
        daemon
            .poller
            .poll(&mut events, Some(Duration::from_secs(2)))
            .unwrap();
        assert!(
            started.elapsed() < Duration::from_millis(500),
            "poll waited on a timer instead of the waker"
        );
        assert!(
            events
                .iter()
                .any(|ev| ev.token().0 == super::WAKER_EVENT_KEY),
            "expected a waker event"
        );

        let mut queued = 0;
        while receiver.try_recv().is_ok() {
            queued += 1;
        }
        assert_eq!(queued, 5, "coalesced wakeups must not drop queued commands");
    }

    #[test]
    fn test_command_channel_full_and_disconnected() {
        let poller = mio::Poll::new().unwrap();
        let waker = std::sync::Arc::new(
            mio::Waker::new(poller.registry(), mio::Token(super::WAKER_EVENT_KEY)).unwrap(),
        );
        let (sender, receiver) = flume::bounded(1);
        let daemon = ServiceDaemon {
            sender,
            waker: waker.clone(),
        };

        daemon
            .send_cmd(super::Command::StopBrowse("_full._udp.local.".to_string()))
            .unwrap();
        assert_eq!(
            daemon
                .send_cmd(super::Command::StopBrowse("_full._udp.local.".to_string()))
                .unwrap_err(),
            crate::Error::Again
        );

        drop(receiver);
        assert_eq!(
            daemon
                .send_cmd(super::Command::StopBrowse(
                    "_closed._udp.local.".to_string()
                ))
                .unwrap_err(),
            crate::Error::DaemonShutdown
        );
        // Keep the poller alive for the waker registration above.
        drop(poller);
    }

    #[test]
    fn test_dropped_clone_does_not_stop_waking_remaining_handle() {
        let daemon = ServiceDaemon::new().unwrap();
        let remaining = daemon.clone();
        drop(daemon);

        let status = status_until_accepted(&remaining);
        assert_eq!(recv_status(&status), super::DaemonStatus::Running);

        let shutdown = remaining.shutdown().unwrap();
        assert_eq!(recv_status(&shutdown), super::DaemonStatus::Shutdown);
    }

    /// Whether the daemon's IPv4 socket still holds the mDNS membership for `ip`.
    ///
    /// Joining again is the probe: it fails with `AddrInUse` only while the
    /// membership exists.
    ///
    /// Not on Windows, which reports a repeated join as `WSAEINVAL`, not as
    /// `AddrInUse`.
    #[cfg(not(windows))]
    fn holds_ipv4_membership(daemon: &super::Zeroconf, ip: &Ipv4Addr) -> bool {
        let sock = daemon.ipv4_sock.as_ref().expect("no IPv4 socket");
        match sock.pktinfo.join_multicast_v4(&super::GROUP_ADDR_V4, ip) {
            Ok(()) => {
                // Not a member: leave again, so the probe changes nothing.
                let _ = sock.pktinfo.leave_multicast_v4(&super::GROUP_ADDR_V4, ip);
                false
            }
            Err(e) if e.kind() == std::io::ErrorKind::AddrInUse => true,
            Err(e) => panic!("unexpected join error on {}: {}", ip, e),
        }
    }

    /// A second interface on 127.0.0.1, standing in for the macOS pairs that share
    /// one IPv4 address (like the `bridge1NN` interfaces of VMs and containers).
    #[cfg(not(windows))]
    fn loopback_alias() -> Interface {
        test_interface("mdns-sd-alias", 65_535, test_ifaddr_v4(Ipv4Addr::LOCALHOST))
    }

    #[test]
    #[cfg(not(windows))]
    fn test_interface_sharing_an_ipv4_address_is_recorded() {
        let mut daemon = new_test_zeroconf();
        assert!(
            holds_ipv4_membership(&daemon, &Ipv4Addr::LOCALHOST),
            "precondition: the daemon joined the group on loopback at startup"
        );

        let alias = loopback_alias();
        daemon.add_interface(&alias, std::slice::from_ref(&alias));

        // Joining 127.0.0.1 again fails with `AddrInUse`. Leaving the interface
        // out would make every IP check retry the join, forever.
        assert!(
            daemon.my_intfs.contains_key(&65_535),
            "an interface sharing an already-joined IPv4 address must be recorded"
        );
    }

    /// Records `addrs` for a made-up interface, as if it had joined the mDNS group
    /// on each IP version in there. Nothing on the host has these addresses, so
    /// joining on them fails.
    fn add_fake_intf(daemon: &mut super::Zeroconf, index: u32, addrs: &[IfAddr]) {
        daemon.my_intfs.insert(
            index,
            MyIntf {
                name: "mdns-sd-fake".to_string(),
                index,
                addrs: addrs.iter().cloned().collect(),
                max_packet_size_v4: MAX_PKT_DEFAULT,
                max_packet_size_v6: MAX_PKT_DEFAULT,
            },
        );
    }

    #[test]
    fn test_second_address_reuses_interface_membership() {
        let mut daemon = new_test_zeroconf();
        let index = 65_534;
        add_fake_intf(
            &mut daemon,
            index,
            &[
                test_ifaddr_v4(Ipv4Addr::new(192, 0, 2, 1)),
                test_ifaddr_v6("2001:db8::1".parse().unwrap()),
            ],
        );

        // The interface already holds both memberships, so no join is attempted
        // (one would fail here), and the addresses are recorded.
        let second_v4 = test_interface(
            "mdns-sd-fake",
            index,
            test_ifaddr_v4(Ipv4Addr::new(192, 0, 2, 2)),
        );
        let second_v6 = test_interface(
            "mdns-sd-fake",
            index,
            test_ifaddr_v6("2001:db8::2".parse().unwrap()),
        );
        for intf in [second_v4, second_v6] {
            daemon.add_interface(&intf, std::slice::from_ref(&intf));
            assert!(
                daemon.my_intfs[&index].addrs.contains(&intf.addr),
                "{} must be recorded under the existing membership",
                intf.ip()
            );
        }
    }

    #[test]
    fn test_failed_join_does_not_record_address() {
        let mut daemon = new_test_zeroconf();
        let (monitor, events) = flume::bounded(10);
        daemon.monitors.push(monitor);
        let index = 65_534;

        // A new interface: nothing is recorded for it.
        let v4 = test_interface(
            "mdns-sd-fake",
            index,
            test_ifaddr_v4(Ipv4Addr::new(192, 0, 2, 1)),
        );
        daemon.add_interface(&v4, std::slice::from_ref(&v4));
        assert!(!daemon.my_intfs.contains_key(&index));

        // A known interface without an IPv4 membership: the IPv4 address is left
        // out, so the next IP check tries to join again.
        add_fake_intf(
            &mut daemon,
            index,
            &[test_ifaddr_v6("2001:db8::1".parse().unwrap())],
        );
        daemon.add_interface(&v4, std::slice::from_ref(&v4));
        assert!(!daemon.my_intfs[&index].addrs.contains(&v4.addr));

        let events: Vec<_> = events.try_iter().collect();
        assert!(
            !events.iter().any(|e| matches!(e, DaemonEvent::IpAdd(_))),
            "a failed join must not be reported as IpAdd: {:?}",
            events
        );
    }

    #[test]
    fn test_slept_duration() {
        use super::{slept_duration, SLEEP_DETECTION_THRESHOLD};
        let secs = Duration::from_secs;

        // Both clocks moved together: no sleep.
        assert_eq!(slept_duration(secs(60), Some(secs(60))), None);

        // A gap within the threshold is drift between the clocks, not sleep.
        let drift = secs(60) + SLEEP_DETECTION_THRESHOLD;
        assert_eq!(slept_duration(secs(60), Some(drift)), None);

        // The wall clock moved an hour further than `Instant`.
        assert_eq!(slept_duration(secs(5), Some(secs(3605))), Some(secs(3600)));

        // The wall clock moved less than `Instant`, or went backwards.
        assert_eq!(slept_duration(secs(60), Some(secs(10))), None);
        assert_eq!(slept_duration(secs(60), None), None);
    }

    /// Setting the IP check interval at runtime takes effect right away:
    /// 0 disables the check, and a nonzero interval schedules the next one
    /// from now, even when the check was disabled before.
    #[test]
    fn test_set_ip_check_interval_reschedules_the_check() {
        let mut daemon = new_test_zeroconf();
        daemon.schedule_ip_check(Instant::now());
        assert!(
            daemon.next_ip_check.is_some(),
            "precondition: the default interval schedules a check"
        );

        // Disabling must cancel the check, not schedule one for `now` that
        // would then repeat on every run loop iteration.
        daemon.process_set_option(super::DaemonOption::IpCheckInterval(0));
        assert_eq!(daemon.next_ip_check, None);

        let before = Instant::now();
        daemon.process_set_option(super::DaemonOption::IpCheckInterval(30_000));
        let next = daemon
            .next_ip_check
            .expect("a nonzero interval must re-enable the check");
        assert!(next >= before + Duration::from_secs(30));
        assert!(next <= Instant::now() + Duration::from_secs(30));
    }

    #[test]
    #[cfg(not(windows))]
    fn test_removing_one_of_two_interfaces_sharing_an_ipv4_address_keeps_the_membership() {
        let mut daemon = new_test_zeroconf();
        let alias = loopback_alias();
        // Recorded directly, so this tests the teardown alone.
        daemon.my_intfs.insert(
            65_535,
            super::MyIntf {
                name: alias.name.clone(),
                index: 65_535,
                addrs: HashSet::from([alias.addr.clone()]),
                max_packet_size_v4: super::MAX_PKT_DEFAULT,
                max_packet_size_v6: super::MAX_PKT_DEFAULT,
            },
        );

        daemon.del_interface_addr(&alias);

        assert!(
            holds_ipv4_membership(&daemon, &Ipv4Addr::LOCALHOST),
            "leaving by address would drop the membership the other interface still uses"
        );
    }

    #[test]
    fn test_excluded_address_preserves_announced_service() {
        use crate::service_info::ServiceStatus;

        for ipv4_service in [true, false] {
            let (mut daemon, _receiver) = new_test_zeroconf_with_receiver();
            let loopback = my_ip_interfaces(true)
                .into_iter()
                .find(|intf| intf.ip() == IpAddr::V4(Ipv4Addr::LOCALHOST))
                .unwrap();
            let index = loopback.index.unwrap();
            // Registration and announcements use only loopback and a private
            // port. Injected addresses below never change host configuration.
            daemon.my_intfs.retain(|key, _| *key == index);
            daemon.dns_registry_map.retain(|key, _| *key == index);
            let mut service = ServiceInfo::new(
                "_address-change._tcp.local.",
                "address-change",
                "address-change.local.",
                "",
                8080,
                None,
            )
            .unwrap()
            .enable_addr_auto();
            service.set_interfaces(vec![if ipv4_service {
                IfKind::IPv4
            } else {
                IfKind::IPv6
            }]);
            let fullname = service.get_fullname().to_lowercase();
            daemon.register_service(service);
            assert_eq!(
                daemon.my_services[&fullname].get_status(index),
                ServiceStatus::Probing
            );
            assert!(!daemon.dns_registry_map[&index].probing.is_empty());
            // Finish real registration probes without waiting for wall-clock timers.
            for probe in daemon
                .dns_registry_map
                .get_mut(&index)
                .unwrap()
                .probing
                .values_mut()
            {
                probe.start_time = Instant::now() - Duration::from_millis(1000);
                probe.next_send = probe.start_time;
            }
            daemon.probing_handler();
            assert_eq!(
                daemon.my_services[&fullname].get_status(index),
                ServiceStatus::Announced
            );
            assert!(!daemon.dns_registry_map[&index].active.is_empty());
            let addresses = daemon.my_services[&fullname].get_addresses().clone();

            let new_addr = test_interface(
                &loopback.name,
                index,
                if ipv4_service {
                    test_ifaddr_v6("2001:db8::1234".parse().unwrap())
                } else {
                    test_ifaddr_v4(Ipv4Addr::new(192, 0, 2, 123))
                },
            );
            daemon.add_interface(&new_addr, std::slice::from_ref(&new_addr));
            assert!(daemon.my_intfs[&index].addrs.contains(&new_addr.addr));
            assert_eq!(daemon.my_services[&fullname].get_addresses(), &addresses);
            assert!(daemon.dns_registry_map[&index].probing.is_empty());
            assert_eq!(
                daemon.my_services[&fullname].get_status(index),
                ServiceStatus::Announced,
                "an excluded address must not leave the service waiting for nonexistent probes"
            );
        }
    }

    #[test]
    fn test_resolve_max_packet_size() {
        // en0 is dual-stack, en1 is IPv4 only.
        let interfaces = vec![
            test_interface("en0", 1, test_ifaddr_v4(Ipv4Addr::new(192, 168, 1, 2))),
            test_interface(
                "en0",
                1,
                test_ifaddr_v6(Ipv6Addr::new(0xfe80, 0, 0, 0, 0, 0, 0, 1)),
            ),
            test_interface("en1", 2, test_ifaddr_v4(Ipv4Addr::new(10, 0, 0, 2))),
        ];

        let resolve = |selections: &[MaxPacketSizeSelection], if_index, is_ipv4| {
            resolve_max_packet_size(selections, &interfaces, if_index, is_ipv4)
        };

        // No selection: every interface keeps the default.
        assert_eq!(resolve(&[], 1, true), MAX_PKT_DEFAULT);
        assert_eq!(resolve(&[], 1, false), MAX_PKT_DEFAULT);

        // A selection by name applies to the interface it matches, both families.
        let by_name = vec![MaxPacketSizeSelection {
            if_kind: IfKind::Name("en0".to_string()),
            max_packet_size: 8000,
        }];
        assert_eq!(resolve(&by_name, 1, true), 8000);
        assert_eq!(resolve(&by_name, 1, false), 8000);
        assert_eq!(resolve(&by_name, 2, true), MAX_PKT_DEFAULT);

        // For an interface matched more than once, the last selection wins.
        let overlapping = vec![
            MaxPacketSizeSelection {
                if_kind: IfKind::All,
                max_packet_size: 8000,
            },
            MaxPacketSizeSelection {
                if_kind: IfKind::Name("en1".to_string()),
                max_packet_size: 4000,
            },
        ];
        assert_eq!(resolve(&overlapping, 1, true), 8000);
        assert_eq!(resolve(&overlapping, 1, false), 8000);
        assert_eq!(resolve(&overlapping, 2, true), 4000);

        // A selection of one address family leaves the other one alone.
        let v4_only = vec![MaxPacketSizeSelection {
            if_kind: IfKind::IPv4,
            max_packet_size: 8000,
        }];
        assert_eq!(resolve(&v4_only, 1, true), 8000);
        assert_eq!(resolve(&v4_only, 1, false), MAX_PKT_DEFAULT);

        let v6_only = vec![MaxPacketSizeSelection {
            if_kind: IfKind::IPv6,
            max_packet_size: 8000,
        }];
        assert_eq!(resolve(&v6_only, 1, false), 8000);
        assert_eq!(resolve(&v6_only, 1, true), MAX_PKT_DEFAULT);
        // en1 has no IPv6 address, so the IPv6 selection cannot reach it.
        assert_eq!(resolve(&v6_only, 2, true), MAX_PKT_DEFAULT);
        assert_eq!(resolve(&v6_only, 2, false), MAX_PKT_DEFAULT);

        // Same for an index selection, which names a family too.
        let by_index_v4 = vec![MaxPacketSizeSelection {
            if_kind: IfKind::IndexV4(1),
            max_packet_size: 8000,
        }];
        assert_eq!(resolve(&by_index_v4, 1, true), 8000);
        assert_eq!(resolve(&by_index_v4, 1, false), MAX_PKT_DEFAULT);
    }

    /// A size outside [`MIN_MAX_PACKET_SIZE`]..=[`MAX_PKT_ABSOLUTE_IPV6`] is rejected
    /// rather than clamped, so what reaches the encoder is always legal.
    #[test]
    fn test_set_max_packet_size_range() {
        let daemon = ServiceDaemon::new().unwrap();

        assert!(daemon
            .set_max_packet_size(IfKind::All, MIN_MAX_PACKET_SIZE - 1)
            .is_err());
        assert!(daemon
            .set_max_packet_size(IfKind::All, MAX_PKT_ABSOLUTE_IPV6 + 1)
            .is_err());

        // Both ends of the range are accepted.
        assert!(daemon
            .set_max_packet_size(IfKind::All, MIN_MAX_PACKET_SIZE)
            .is_ok());
        assert!(daemon
            .set_max_packet_size(IfKind::All, MAX_PKT_ABSOLUTE_IPV6)
            .is_ok());

        daemon.shutdown().unwrap();
    }

    #[test]
    fn test_response_source_ifaddr_match() {
        // When an interface has multiple IPs on unrelated subnets,
        // handle_query should pick the IfAddr whose subnet contains the querier,
        // and fall back to None if none match.
        let ifaddr_a = IfAddr::V4(Ifv4Addr {
            ip: Ipv4Addr::new(192, 168, 1, 148),
            netmask: Ipv4Addr::new(255, 255, 255, 0),
            broadcast: None,
            prefixlen: 24,
        });
        let ifaddr_b = IfAddr::V4(Ifv4Addr {
            ip: Ipv4Addr::new(10, 238, 0, 51),
            netmask: Ipv4Addr::new(255, 255, 255, 0),
            broadcast: None,
            prefixlen: 24,
        });

        let intf = MyIntf {
            name: "dummy0".to_string(),
            index: 1,
            addrs: HashSet::from([ifaddr_a.clone(), ifaddr_b.clone()]),
            max_packet_size_v4: MAX_PKT_DEFAULT,
            max_packet_size_v6: MAX_PKT_DEFAULT,
        };

        let pick = |querier: IpAddr| -> Option<IfAddr> {
            intf.addrs
                .iter()
                .find(|a| valid_ip_on_intf(&querier, a))
                .cloned()
        };

        assert_eq!(
            pick(IpAddr::V4(Ipv4Addr::new(192, 168, 1, 2))),
            Some(ifaddr_a)
        );
        assert_eq!(
            pick(IpAddr::V4(Ipv4Addr::new(10, 238, 0, 99))),
            Some(ifaddr_b)
        );
        // Querier not on any local subnet: fall back to None.
        assert_eq!(pick(IpAddr::V4(Ipv4Addr::new(172, 16, 0, 1))), None);
    }

    #[test]
    fn test_instance_name() {
        assert!(valid_instance_name("my-laser._printer._tcp.local."));
        assert!(valid_instance_name("my-laser.._printer._tcp.local."));
        assert!(!valid_instance_name("_printer._tcp.local."));
    }

    #[test]
    fn test_custom_port_shared_response_is_delayed() {
        let mut daemon = new_test_zeroconf();
        let address = IpAddr::V4(Ipv4Addr::LOCALHOST);
        let index = daemon
            .my_intfs
            .values()
            .find(|intf| intf.addrs.iter().any(|addr| addr.ip() == address))
            .unwrap()
            .index;
        let mut service = ServiceInfo::new(
            "_custom-query._udp.local.",
            "instance",
            "custom-query.local.",
            address,
            8080,
            None,
        )
        .unwrap();
        service.set_status(index, crate::service_info::ServiceStatus::Announced);
        daemon
            .my_services
            .insert(service.get_fullname().to_lowercase(), service);
        let mut query = DnsOutgoing::new(FLAGS_QR_QUERY);
        query.add_question("_custom-query._udp.local.", RRType::PTR);
        let interface = InterfaceId {
            name: "test".to_string(),
            index,
        };
        let packet = query
            .to_data_on_wire(MAX_PKT_DEFAULT, address.is_ipv4())
            .remove(0);
        let query = DnsIncoming::new(packet, interface).unwrap();
        daemon.handle_query(query, index, (address, daemon.port).into());
        assert_eq!(daemon.delayed_responses.len(), 1);
        assert_eq!(daemon.delayed_responses[0].out.answers_count(), 1);
    }

    #[test]
    fn test_custom_port_response_preserves_multicast_records() {
        let mut daemon = new_test_zeroconf();
        let address = IpAddr::V4(Ipv4Addr::LOCALHOST);
        let index = daemon
            .my_intfs
            .values()
            .find(|intf| intf.addrs.iter().any(|addr| addr.ip() == address))
            .unwrap()
            .index;
        let interface = InterfaceId {
            name: "test".to_string(),
            index,
        };
        let mut query = DnsOutgoing::new(FLAGS_QR_QUERY);
        query.add_question("custom-query.local.", RRType::A);
        let packet = query
            .to_data_on_wire(MAX_PKT_DEFAULT, address.is_ipv4())
            .remove(0);
        let query = DnsIncoming::new(packet, interface.clone()).unwrap();
        let mut response = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
        response.add_answer_record(DnsAddress::new(
            "custom-query.local.",
            RRType::A,
            CLASS_IN | super::CLASS_CACHE_FLUSH,
            120,
            address,
            interface.clone(),
        ));
        daemon.send_response(&mut response, &query, index, (address, daemon.port).into());
        let packet = response
            .to_data_on_wire(MAX_PKT_DEFAULT, address.is_ipv4())
            .remove(0);
        let response = DnsIncoming::new(packet, interface).unwrap();
        assert!(response.questions().is_empty());
        assert_eq!(response.answers()[0].get_record().get_ttl(), 120);
        assert!(response.answers()[0].get_record().is_unique());
    }

    #[test]
    fn test_legacy_unicast_response() {
        // RFC 6762 §6.7: a query whose UDP source port is not 5353 (a
        // "legacy" / "one-shot" querier, e.g. Android's getaddrinfo) must
        // get its response via unicast, sent back to the querier's source
        // address, with the question echoed and the cache-flush bit cleared.
        //
        // This test sends such a query from an ephemeral port and asserts
        // the response arrives on that same socket. The socket is not joined
        // to the mDNS multicast group, so a multicast-only reply would never
        // reach it — simply receiving the response proves it was unicast.

        let intf_ip = match my_ip_interfaces(false)
            .into_iter()
            .find_map(|intf| match intf.ip() {
                IpAddr::V4(ip) => Some(ip),
                IpAddr::V6(_) => None,
            }) {
            Some(ip) => ip,
            None => {
                println!("No IPv4 interface available; skipping test.");
                return;
            }
        };

        // Register a service with a unique hostname on this host.
        let daemon = ServiceDaemon::new().expect("Failed to create daemon");
        let unique = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_micros();
        let hostname = format!("legacy-unicast-test-{unique}.local.");
        let service_info = ServiceInfo::new(
            "_legacy-uni._udp.local.",
            "test_instance",
            &hostname,
            &[IpAddr::V4(intf_ip)] as &[IpAddr],
            5353, // arbitrary; the test only resolves the hostname
            None,
        )
        .expect("invalid service info");
        daemon.register(service_info).expect("register service");

        // A one-shot querier: ephemeral source port, not 5353. Binding to
        // `intf_ip` directs the multicast query out that interface, which is
        // one the daemon is listening on.
        let querier = UdpSocket::bind((intf_ip, 0)).expect("bind querier socket");
        querier
            .set_multicast_loop_v4(true)
            .expect("enable multicast loopback");
        querier
            .set_read_timeout(Some(Duration::from_millis(500)))
            .expect("set read timeout");
        assert_ne!(
            querier.local_addr().unwrap().port(),
            MDNS_PORT,
            "querier must use an ephemeral (non-5353) source port"
        );

        // Build a one-question A-record query for our hostname, carrying a
        // distinctive non-zero id that the legacy unicast response must echo.
        // `set_multicast(false)` makes the query serialize with that id on the
        // wire rather than 0.
        const QUERY_ID: u16 = 0x4a17;
        let mut query = DnsOutgoing::new(FLAGS_QR_QUERY);
        query.set_id(QUERY_ID);
        query.set_multicast(false);
        query.add_question(&hostname, RRType::A);
        let query_packet = query
            .to_data_on_wire(MAX_PKT_DEFAULT, true)
            .pop()
            .expect("query serialized to one packet");

        let if_id = InterfaceId {
            name: "test".to_string(),
            index: 0,
        };

        // The service is announced asynchronously after register(), so retry
        // the query until our answer comes back or the deadline passes.
        let deadline = Instant::now() + Duration::from_secs(8);
        let mut response = None;
        'outer: while Instant::now() < deadline {
            querier
                .send_to(&query_packet, (GROUP_ADDR_V4, MDNS_PORT))
                .expect("send query");

            // Drain whatever has arrived; on read timeout the loop ends and
            // we re-send the query.
            let mut buf = [0u8; 1500];
            while let Ok((len, from)) = querier.recv_from(&mut buf) {
                let Ok(msg) = DnsIncoming::new(buf[..len].to_vec(), if_id.clone()) else {
                    continue;
                };
                if msg.is_response()
                    && msg
                        .answers()
                        .iter()
                        .any(|a| a.get_name().eq_ignore_ascii_case(&hostname))
                {
                    response = Some((msg, from));
                    break 'outer;
                }
            }
        }

        let (msg, from) = response.expect(
            "expected a unicast response to the legacy query; \
             a multicast-only reply would never reach this un-joined socket",
        );

        // The reply came back to our ephemeral socket, from the mDNS port.
        assert_eq!(
            from.port(),
            MDNS_PORT,
            "response should originate from the mDNS port"
        );

        // RFC 6762 §6.7: the response header must echo the querier's id.
        assert_eq!(
            msg.id(),
            QUERY_ID,
            "legacy unicast response must echo the query id"
        );

        // RFC 6762 §6.7: the original question must be echoed.
        assert!(
            msg.questions()
                .iter()
                .any(|q| q.entry_name().eq_ignore_ascii_case(&hostname)),
            "legacy unicast response must echo the question section"
        );

        // RFC 6762 §6.7 / §10.2: the answer must be the A record we asked
        // for, with the cache-flush bit cleared.
        let answer = msg
            .answers()
            .iter()
            .find(|a| a.get_name().eq_ignore_ascii_case(&hostname))
            .expect("response contains an answer for our hostname");
        assert_eq!(
            answer.get_type(),
            RRType::A,
            "an A query should be answered with an A record"
        );
        assert!(
            !answer.get_cache_flush(),
            "legacy unicast responses must clear the cache-flush bit"
        );

        assert!(
            answer.get_record().get_ttl() <= LEGACY_UNICAST_MAX_TTL,
            "legacy unicast response TTL {} exceeds the {}s cap",
            answer.get_record().get_ttl(),
            LEGACY_UNICAST_MAX_TTL
        );

        daemon.shutdown().unwrap();
    }

    #[test]
    fn test_shared_response_delay_bounds() {
        // A shared-record (PTR) response is delayed by a uniform-random amount.
        // We deviate from the RFC 6762 §6 suggested 20-120 ms window and use a
        // shorter 10-50 ms delay (`MAX` is the exclusive upper bound, so the
        // actual delay is 10..=49 ms).
        assert_eq!(SHARED_RESPONSE_DELAY_MIN_MILLIS, 10);
        assert_eq!(SHARED_RESPONSE_DELAY_MAX_MILLIS, 50);
        for _ in 0..10_000 {
            let d =
                fastrand::u64(SHARED_RESPONSE_DELAY_MIN_MILLIS..SHARED_RESPONSE_DELAY_MAX_MILLIS);
            assert!(
                (SHARED_RESPONSE_DELAY_MIN_MILLIS..SHARED_RESPONSE_DELAY_MAX_MILLIS).contains(&d),
                "delay {} ms is outside the configured {}-{} ms range",
                d,
                SHARED_RESPONSE_DELAY_MIN_MILLIS,
                SHARED_RESPONSE_DELAY_MAX_MILLIS
            );
        }
    }

    #[test]
    fn test_initial_query_delayed() {
        // RFC 6762 §5.2: a querier delays the first query of a continuous
        // monitoring series by a random amount (we use a 10-50 ms window).
        // Start a browse and observe, on a socket joined to the mDNS group, the
        // daemon's first PTR query for our (unique) service type. Assert it
        // arrives no sooner than ~10 ms after `browse()` — i.e. it is not sent
        // immediately.
        use socket2::{Domain, Protocol, Socket, Type};

        let (intf, intf_ip) = match my_ip_interfaces(false)
            .into_iter()
            .find_map(|intf| match intf.ip() {
                IpAddr::V4(ip) if !ip.is_loopback() => Some((intf, ip)),
                _ => None,
            }) {
            Some(pair) => pair,
            None => {
                println!("No IPv4 interface available; skipping test.");
                return;
            }
        };
        let interface_id = InterfaceId::from(&intf);

        // A receiver socket joined to the mDNS group on this interface. The
        // daemon loops back its multicast by default, so its outgoing query is
        // delivered here on the same host.
        let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP)).unwrap();
        sock.set_reuse_address(true).unwrap();
        #[cfg(unix)]
        sock.set_reuse_port(true).unwrap();
        sock.bind(&std::net::SocketAddr::from((Ipv4Addr::UNSPECIFIED, MDNS_PORT)).into())
            .unwrap();
        sock.join_multicast_v4(&GROUP_ADDR_V4, &intf_ip).unwrap();
        sock.set_read_timeout(Some(Duration::from_millis(200)))
            .unwrap();
        let sock: UdpSocket = sock.into();

        // Unique service type, kept within the RFC 6763 §7.2 15-byte label limit.
        let unique = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_micros()
            % 1_000_000_000;
        let service_type = format!("_qd{unique}._udp.local.");

        let daemon = ServiceDaemon::new().expect("Failed to create daemon");

        let sent_at = Instant::now();
        let _browse = daemon.browse(&service_type).expect("browse");

        // Read packets until we see our own PTR query or time out. The 10-50 ms
        // jitter plus command/scheduling latency comfortably fits in 2 s.
        let deadline = Instant::now() + Duration::from_secs(2);
        let mut buf = [0u8; 2048];
        let mut measured = None;
        while Instant::now() < deadline {
            let n = match sock.recv_from(&mut buf) {
                Ok((n, _)) => n,
                Err(_) => continue, // read timeout; keep polling until the deadline
            };
            let Ok(msg) = DnsIncoming::new(buf[..n].to_vec(), interface_id.clone()) else {
                continue;
            };
            if msg.is_query()
                && msg
                    .questions()
                    .iter()
                    .any(|q| q.entry_name() == service_type)
            {
                measured = Some(sent_at.elapsed());
                break;
            }
        }

        daemon.shutdown().unwrap();

        let elapsed = measured.expect("expected the daemon to send a PTR query for our browse");
        let tolerance = Duration::from_millis(2);
        assert!(
            elapsed + tolerance >= Duration::from_millis(INITIAL_QUERY_DELAY_MIN_MILLIS),
            "first browse query was sent after only {:?}; the first query of a series must be \
             delayed (10-50 ms window), not sent immediately",
            elapsed
        );

        // Upper bound: the query must fall within the jitter window. Allow
        // generous slack above INITIAL_QUERY_DELAY_MAX_MILLIS for command
        // handoff, event-loop wakeup, and loopback latency, while still catching
        // a regression to a much larger delay (e.g. the RFC's 120 ms window).
        let scheduling_slack = Duration::from_millis(50);
        assert!(
            elapsed <= Duration::from_millis(INITIAL_QUERY_DELAY_MAX_MILLIS) + scheduling_slack,
            "first browse query was sent after {:?}, beyond the {}-{} ms jitter window (plus slack)",
            elapsed,
            INITIAL_QUERY_DELAY_MIN_MILLIS,
            INITIAL_QUERY_DELAY_MAX_MILLIS
        );
    }

    #[test]
    fn test_shared_ptr_response_delayed() {
        // RFC 6762 §6: a PTR (shared record set) response sent by multicast is
        // delayed by a uniform-random amount (we use a 10-50 ms window). Register
        // a service, then as a proper multicast querier (source port 5353) send a
        // PTR query and assert the daemon emits its response no sooner than ~10 ms
        // after the query. (A legacy unicast querier gets an *immediate* response
        // instead; see `test_legacy_unicast_response`.)
        use socket2::{Domain, Protocol, Socket, Type};

        let intf_ip = match my_ip_interfaces(false)
            .into_iter()
            .find_map(|intf| match intf.ip() {
                IpAddr::V4(ip) if !ip.is_loopback() => Some(ip),
                _ => None,
            }) {
            Some(ip) => ip,
            None => {
                println!("No IPv4 interface available; skipping test.");
                return;
            }
        };

        let daemon = ServiceDaemon::new().expect("Failed to create daemon");
        let monitor = daemon.monitor().expect("monitor daemon events");

        // Keep the service name (the `_sd…` label) within the 15-byte limit
        // that RFC 6763 §7.2 imposes, while staying unique per run.
        let unique = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_micros()
            % 1_000_000_000;
        let service_type = format!("_sd{unique}._udp.local.");
        let hostname = format!("sd{unique}.local.");
        let service_info = ServiceInfo::new(
            &service_type,
            "test_instance",
            &hostname,
            &[IpAddr::V4(intf_ip)] as &[IpAddr],
            5353,
            None,
        )
        .expect("invalid service info");
        daemon.register(service_info).expect("register service");

        // A proper multicast querier: source port 5353 so the daemon takes the
        // shared-record (delayed) path rather than the legacy-unicast one. We only
        // *send* on this socket; the response is observed through the monitor.
        let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP)).unwrap();
        sock.set_reuse_address(true).unwrap();
        #[cfg(unix)]
        sock.set_reuse_port(true).unwrap();
        sock.bind(&std::net::SocketAddr::from((Ipv4Addr::UNSPECIFIED, MDNS_PORT)).into())
            .unwrap();
        sock.set_multicast_if_v4(&intf_ip).unwrap();
        // Loop the query back to the daemon's socket on this same host.
        sock.set_multicast_loop_v4(true).unwrap();
        let sock: UdpSocket = sock.into();

        // Build the PTR query for our service type.
        let mut query = DnsOutgoing::new(FLAGS_QR_QUERY);
        query.add_question(&service_type, RRType::PTR);
        let query_packet = query
            .to_data_on_wire(MAX_PKT_DEFAULT, true)
            .pop()
            .expect("one packet");

        // Wait for the initial announcements and the §6 rate-limit window (1s) to
        // pass, so our query elicits a fresh (delayed) response instead of being
        // suppressed by the rate limiter.
        std::thread::sleep(Duration::from_secs(3));

        // Retry until the daemon emits a Respond for our query. A query landing
        // inside the 1 s multicast rate-limit window is rate-limited to an empty
        // response (no send, no event), so we simply re-query on the next pass.
        let deadline = Instant::now() + Duration::from_secs(8);
        let mut measured = None;
        while Instant::now() < deadline {
            // Drop any Respond events queued earlier so we time only the response
            // to the query we are about to send.
            while monitor.try_recv().is_ok() {}

            let sent_at = Instant::now();
            sock.send_to(&query_packet, (GROUP_ADDR_V4, MDNS_PORT))
                .expect("send query");

            // The delay window is 10-50 ms; 700 ms comfortably covers it plus any
            // scheduling slack. Ignore unrelated events; on timeout, re-query.
            let attempt_deadline = sent_at + Duration::from_millis(700);
            loop {
                let remaining = attempt_deadline.saturating_duration_since(Instant::now());
                if remaining.is_zero() {
                    break;
                }
                match monitor.recv_timeout(remaining) {
                    Ok(DaemonEvent::Respond(_)) => {
                        measured = Some(sent_at.elapsed());
                        break;
                    }
                    Ok(_) => continue, // some other daemon event; keep waiting
                    Err(_) => break,   // timed out; re-query
                }
            }
            if measured.is_some() {
                break;
            }
        }

        let elapsed =
            measured.expect("expected the daemon to respond to our PTR query within the deadline");
        assert!(
            elapsed >= Duration::from_millis(8),
            "PTR response was sent after only {:?}; a shared-record response must be \
             delayed (10-50 ms window), not sent immediately",
            elapsed
        );
        assert!(
            elapsed <= Duration::from_millis(600),
            "PTR response was sent after {:?}; expected within the 10-50 ms delay window",
            elapsed
        );

        daemon.shutdown().unwrap();
    }

    #[test]
    fn test_check_service_name_length() {
        let result = check_service_name_length("_tcp", 100);
        assert!(result.is_err());
        if let Err(e) = result {
            println!("{}", e);
        }
    }

    #[test]
    fn test_check_hostname() {
        // valid hostnames
        for hostname in &[
            "my_host.local.",
            &("A".repeat(255 - ".local.".len()) + ".local."),
        ] {
            let result = check_hostname(hostname);
            assert!(result.is_ok());
        }

        // erroneous hostnames
        for hostname in &[
            "my_host.local",
            ".local.",
            &("A".repeat(256 - ".local.".len()) + ".local."),
        ] {
            let result = check_hostname(hostname);
            assert!(result.is_err());
            if let Err(e) = result {
                println!("{}", e);
            }
        }
    }

    #[test]
    fn test_check_domain_suffix() {
        assert!(check_domain_suffix("_missing_dot._tcp.local").is_err());
        assert!(check_domain_suffix("_missing_bar.tcp.local.").is_err());
        assert!(check_domain_suffix("_mis_spell._tpp.local.").is_err());
        assert!(check_domain_suffix("_mis_spell._upp.local.").is_err());
        assert!(check_domain_suffix("_has_dot._tcp.local.").is_ok());
        assert!(check_domain_suffix("_goodname._udp.local.").is_ok());
    }

    #[test]
    fn test_service_with_temporarily_invalidated_ptr() {
        // Create a daemon
        let d = ServiceDaemon::new().expect("Failed to create daemon");

        let service = "_test_inval_ptr._udp.local.";
        let host_name = "my_host_tmp_invalidated_ptr.local.";
        let intfs: Vec<_> = my_ip_interfaces(false);
        let intf_ips: Vec<_> = intfs.iter().map(|intf| intf.ip()).collect();
        let port = 5201;
        let my_service =
            ServiceInfo::new(service, "my_instance", host_name, &intf_ips[..], port, None)
                .expect("invalid service info")
                .enable_addr_auto();
        let result = d.register(my_service.clone());
        assert!(result.is_ok());

        // Browse for a service
        let browse_chan = d.browse(service).unwrap();
        let timeout = Duration::from_secs(2);
        let mut resolved = false;

        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            match event {
                ServiceEvent::ServiceResolved(info) => {
                    resolved = true;
                    println!("Resolved a service of {}", info.fullname);
                    break;
                }
                e => {
                    println!("Received event {:?}", e);
                }
            }
        }

        assert!(resolved);

        println!("Stopping browse of {}", service);
        // Pause browsing so restarting will cause a new immediate query.
        // Unregistering will not work here, it will invalidate all the records.
        d.stop_browse(service).unwrap();

        // Ensure the search is stopped.
        // Reduces the chance of receiving an answer adding the ptr back to the
        // cache causing the later browse to return directly from the cache.
        // (which invalidates what this test is trying to test for.)
        let mut stopped = false;
        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            match event {
                ServiceEvent::SearchStopped(_) => {
                    stopped = true;
                    println!("Stopped browsing service");
                    break;
                }
                // Other `ServiceResolved` messages may be received
                // here as they come from different interfaces.
                // That's fine for this test.
                e => {
                    println!("Received event {:?}", e);
                }
            }
        }

        assert!(stopped);

        // Invalidate the ptr from the service to the host.
        let invalidate_ptr_packet = DnsPointer::new(
            my_service.get_type(),
            RRType::PTR,
            CLASS_IN,
            0,
            my_service.get_fullname().to_string(),
        );

        let mut packet_buffer = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
        packet_buffer.add_additional_answer(invalidate_ptr_packet);

        for intf in intfs {
            let sock = _new_socket_bind(&intf, true).unwrap();
            send_dns_outgoing_impl(
                &packet_buffer,
                &intf.name,
                intf.index.unwrap_or(0),
                &intf.addr,
                &sock.pktinfo,
                SendConfig {
                    port: MDNS_PORT,
                    max_packet_size: MAX_PKT_DEFAULT,
                    is_ipv4: intf.addr.ip().is_ipv4(),
                },
                None,
            )
            .unwrap();
        }

        println!(
            "Sent PTR record invalidation. Starting second browse for {}",
            service
        );

        // Restart the browse to force the sender to re-send the announcements.
        let browse_chan = d.browse(service).unwrap();

        resolved = false;
        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            match event {
                ServiceEvent::ServiceResolved(info) => {
                    resolved = true;
                    println!("Resolved a service of {}", info.fullname);
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
    fn test_expired_srv() {
        // construct service info
        let service_type = "_expired-srv._udp.local.";
        let instance = "test_instance";
        let host_name = "expired_srv_host.local.";
        let mut my_service = ServiceInfo::new(service_type, instance, host_name, "", 5023, None)
            .unwrap()
            .enable_addr_auto();
        // let fullname = my_service.get_fullname().to_string();

        // set SRV to expire soon.
        let new_ttl = 3; // for testing only.
        my_service._set_host_ttl(new_ttl);

        // register my service
        let mdns_server = ServiceDaemon::new().expect("Failed to create mdns server");
        let result = mdns_server.register(my_service);
        assert!(result.is_ok());

        let mdns_client = ServiceDaemon::new().expect("Failed to create mdns client");
        let browse_chan = mdns_client.browse(service_type).unwrap();
        let timeout = Duration::from_secs(2);
        let mut resolved = false;

        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(info) = event {
                resolved = true;
                println!("Resolved a service of {}", info.fullname);
                break;
            }
        }

        assert!(resolved);

        // Exit the server so that no more responses.
        mdns_server.shutdown().unwrap();

        // SRV record in the client cache will expire.
        let expire_timeout = Duration::from_secs(new_ttl as u64);
        while let Ok(event) = browse_chan.recv_timeout(expire_timeout) {
            if let ServiceEvent::ServiceRemoved(service_type, full_name) = event {
                println!("Service removed: {}: {}", service_type, full_name);
                break;
            }
        }
    }

    #[test]
    fn test_hostname_resolution_address_removed() {
        // Create a mDNS server
        let server = ServiceDaemon::new().expect("Failed to create server");
        let hostname = "addr_remove_host._tcp.local.";
        let service_ip_addr: ScopedIp = my_ip_interfaces(false)
            .iter()
            .find(|iface| iface.ip().is_ipv4())
            .map(|iface| iface.into())
            .unwrap();

        let mut my_service = ServiceInfo::new(
            "_host_res_test._tcp.local.",
            "my_instance",
            hostname,
            service_ip_addr.to_ip_addr(),
            1234,
            None,
        )
        .expect("invalid service info");

        // Set a short TTL for addresses for testing.
        let addr_ttl = 2;
        my_service._set_host_ttl(addr_ttl); // Expire soon

        server.register(my_service).unwrap();

        // Create a mDNS client for resolving the hostname.
        let client = ServiceDaemon::new().expect("Failed to create client");
        let event_receiver = client.resolve_hostname(hostname, None).unwrap();

        // Bound the wait so the test fails instead of hanging when the
        // address is never resolved (e.g. multicast blocked on the interface).
        let resolve_timeout = Duration::from_secs(5);
        let resolved = loop {
            match event_receiver.recv_timeout(resolve_timeout) {
                Ok(HostnameResolutionEvent::AddressesFound(found_hostname, addresses)) => {
                    assert_eq!(found_hostname, hostname);
                    assert!(addresses.contains(&service_ip_addr));
                    println!("address found: {:?}", addresses);
                    break true;
                }
                Ok(HostnameResolutionEvent::SearchStopped(_)) => break false,
                Ok(_event) => {}
                Err(_) => break false,
            }
        };

        assert!(resolved);

        // Shutdown the server so no more responses / refreshes for addresses.
        server.shutdown().unwrap();

        // Wait till hostname address record expires, with 1 second grace period.
        let timeout = Duration::from_secs(addr_ttl as u64 + 1);
        let removed = loop {
            match event_receiver.recv_timeout(timeout) {
                Ok(HostnameResolutionEvent::AddressesRemoved(removed_host, addresses)) => {
                    assert_eq!(removed_host, hostname);
                    assert!(addresses.contains(&service_ip_addr));

                    println!(
                        "address removed: hostname: {} addresses: {:?}",
                        hostname, addresses
                    );
                    break true;
                }
                Ok(_event) => {}
                Err(_) => {
                    break false;
                }
            }
        };

        assert!(removed);

        client.shutdown().unwrap();
    }

    #[test]
    fn test_refresh_ptr() {
        // construct service info
        let service_type = "_refresh-ptr._udp.local.";
        let instance = "test_instance";
        let host_name = "refresh_ptr_host.local.";
        let service_ip_addr = my_ip_interfaces(false)
            .iter()
            .find(|iface| iface.ip().is_ipv4())
            .map(|iface| iface.ip())
            .unwrap();

        let mut my_service = ServiceInfo::new(
            service_type,
            instance,
            host_name,
            service_ip_addr,
            5023,
            None,
        )
        .unwrap();

        let new_ttl = 3; // for testing only.
        my_service._set_other_ttl(new_ttl);

        // register my service
        let mdns_server = ServiceDaemon::new().expect("Failed to create mdns server");
        let result = mdns_server.register(my_service);
        assert!(result.is_ok());

        let mdns_client = ServiceDaemon::new().expect("Failed to create mdns client");
        let browse_chan = mdns_client.browse(service_type).unwrap();
        let timeout = Duration::from_millis(1500); // Give at least 1 second for the service probing.
        let mut resolved = false;

        // resolve the service first.
        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(info) = event {
                resolved = true;
                println!("Resolved a service of {}", info.fullname);
                break;
            }
        }

        assert!(resolved);

        // wait over 80% of TTL, and refresh PTR should be sent out.
        let timeout = Duration::from_millis(new_ttl as u64 * 1000 * 90 / 100);
        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            println!("event: {:?}", event);
        }

        // verify refresh counter.
        let metrics_chan = mdns_client.get_metrics().unwrap();
        let metrics = metrics_chan.recv_timeout(timeout).unwrap();
        let ptr_refresh_counter = metrics["cache-refresh-ptr"];
        assert_eq!(ptr_refresh_counter, 1);
        let srvtxt_refresh_counter = metrics["cache-refresh-srv-txt"];
        assert_eq!(srvtxt_refresh_counter, 1);

        // Exit the server so that no more responses.
        mdns_server.shutdown().unwrap();
        mdns_client.shutdown().unwrap();
    }

    #[test]
    fn test_name_change() {
        assert_eq!(name_change("foo.local."), "foo (2).local.");
        assert_eq!(name_change("foo (2).local."), "foo (3).local.");
        assert_eq!(name_change("foo (9).local."), "foo (10).local.");
        assert_eq!(name_change("foo"), "foo (2)");
        assert_eq!(name_change("foo (2)"), "foo (3)");
        assert_eq!(name_change(""), " (2)");

        // Additional edge cases
        assert_eq!(name_change("foo (abc)"), "foo (abc) (2)"); // Invalid number
        assert_eq!(name_change("foo (2"), "foo (2 (2)"); // Missing closing parenthesis
        assert_eq!(name_change("foo (2) extra"), "foo (2) extra (2)"); // Extra text after number
    }

    #[test]
    fn test_hostname_change() {
        assert_eq!(hostname_change("foo.local."), "foo-2.local.");
        assert_eq!(hostname_change("foo"), "foo-2");
        assert_eq!(hostname_change("foo-2.local."), "foo-3.local.");
        assert_eq!(hostname_change("foo-9"), "foo-10");
        assert_eq!(hostname_change("test-42.domain."), "test-43.domain.");
    }

    #[test]
    fn test_add_answer_txt_ttl() {
        // construct a simple service info
        let service_type = "_test_add_answer._udp.local.";
        let instance = "test_instance";
        let host_name = "add_answer_host.local.";
        let service_intf = my_ip_interfaces(false)
            .into_iter()
            .find(|iface| iface.ip().is_ipv4())
            .unwrap();
        let service_ip_addr = service_intf.ip();
        let my_service = ServiceInfo::new(
            service_type,
            instance,
            host_name,
            service_ip_addr,
            5023,
            None,
        )
        .unwrap();

        // construct a DnsOutgoing message
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);

        // Construct a dummy DnsIncoming message
        let mut dummy_data = out.to_data_on_wire(MAX_PKT_DEFAULT, true);
        let interface_id = InterfaceId::from(&service_intf);
        let incoming = DnsIncoming::new(dummy_data.pop().unwrap(), interface_id).unwrap();

        // Add an answer of TXT type for the service.
        let if_addrs = vec![service_intf.ip()];
        add_answer_of_service(
            &mut out,
            &incoming,
            instance,
            &my_service,
            RRType::TXT,
            if_addrs,
        );

        // Check if the answer was added correctly
        assert!(
            out.answers_count() > 0,
            "No answers added to the outgoing message"
        );

        // Check if the first answer is of type TXT
        let answer = out._answers().first().unwrap();
        assert_eq!(answer.get_type(), RRType::TXT);

        // Check TTL is set properly for the TXT record
        assert_eq!(answer.get_record().get_ttl(), my_service.get_other_ttl());
    }

    #[test]
    fn test_interface_flip() {
        // start a server
        let ty_domain = "_intf-flip._udp.local.";
        let host_name = "intf_flip.local.";
        let now = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap();
        let instance_name = now.as_micros().to_string(); // Create a unique name.
        let port = 5200;

        // Get a single IPv4 address
        let (ip_addr1, intf_name) = my_ip_interfaces(false)
            .iter()
            .find(|iface| iface.ip().is_ipv4())
            .map(|iface| (iface.ip(), iface.name.clone()))
            .unwrap();

        println!("Using interface {} with IP {}", intf_name, ip_addr1);

        // Register the service.
        let service1 = ServiceInfo::new(ty_domain, &instance_name, host_name, ip_addr1, port, None)
            .expect("valid service info");
        let server1 = ServiceDaemon::new().expect("failed to start server");
        server1
            .register(service1)
            .expect("Failed to register service1");

        // wait for the service announced.
        std::thread::sleep(Duration::from_secs(2));

        // start a client
        let client = ServiceDaemon::new().expect("failed to start client");

        let receiver = client.browse(ty_domain).unwrap();

        let timeout = Duration::from_secs(3);
        let mut got_data = false;

        while let Ok(event) = receiver.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(_) = event {
                println!("Received ServiceResolved event");
                got_data = true;
                break;
            }
        }

        assert!(got_data, "Should receive ServiceResolved event");

        // Set a short IP check interval to detect interface changes quickly.
        client.set_ip_check_interval(1).unwrap();

        // Now shutdown the interface and expect the client to lose the service.
        println!("Shutting down interface {}", intf_name);
        client.test_down_interface(&intf_name).unwrap();

        let mut got_removed = false;

        while let Ok(event) = receiver.recv_timeout(timeout) {
            if let ServiceEvent::ServiceRemoved(ty_domain, instance) = event {
                got_removed = true;
                println!("removed: {ty_domain} : {instance}");
                break;
            }
        }
        assert!(got_removed, "Should receive ServiceRemoved event");

        println!("Bringing up interface {}", intf_name);
        client.test_up_interface(&intf_name).unwrap();
        let mut got_data = false;
        while let Ok(event) = receiver.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(resolved) = event {
                got_data = true;
                println!("Received ServiceResolved: {:?}", resolved);
                break;
            }
        }
        assert!(
            got_data,
            "Should receive ServiceResolved event after interface is back up"
        );

        server1.shutdown().unwrap();
        client.shutdown().unwrap();
    }

    #[test]
    fn test_cache_only() {
        // construct service info
        let service_type = "_cache_only._udp.local.";
        let instance = "test_instance";
        let host_name = "cache_only_host.local.";
        let service_ip_addr = my_ip_interfaces(false)
            .iter()
            .find(|iface| iface.ip().is_ipv4())
            .map(|iface| iface.ip())
            .unwrap();

        let mut my_service = ServiceInfo::new(
            service_type,
            instance,
            host_name,
            service_ip_addr,
            5023,
            None,
        )
        .unwrap();

        let new_ttl = 3; // for testing only.
        my_service._set_other_ttl(new_ttl);

        let mdns_client = ServiceDaemon::new().expect("Failed to create mdns client");

        // make a single browse request to record that we are interested in the service.  This ensures that
        // subsequent announcements are cached.
        let browse_chan = mdns_client.browse_cache(service_type).unwrap();
        std::thread::sleep(Duration::from_secs(2));

        // register my service
        let mdns_server = ServiceDaemon::new().expect("Failed to create mdns server");
        let result = mdns_server.register(my_service);
        assert!(result.is_ok());

        let timeout = Duration::from_millis(1500); // Give at least 1 second for the service probing.
        let mut resolved = false;

        // resolve the service.
        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(info) = event {
                resolved = true;
                println!("Resolved a service of {}", info.get_fullname());
                break;
            }
        }

        assert!(resolved);

        // Exit the server so that no more responses.
        mdns_server.shutdown().unwrap();
        mdns_client.shutdown().unwrap();
    }

    #[test]
    fn test_cache_only_unsolicited() {
        let service_type = "_c_unsolicit._udp.local.";
        let instance = "test_instance";
        let host_name = "c_unsolicit_host.local.";
        let service_ip_addr = my_ip_interfaces(false)
            .iter()
            .find(|iface| iface.ip().is_ipv4())
            .map(|iface| iface.ip())
            .unwrap();

        let my_service = ServiceInfo::new(
            service_type,
            instance,
            host_name,
            service_ip_addr,
            5023,
            None,
        )
        .unwrap();

        // register my service
        let mdns_server = ServiceDaemon::new().expect("Failed to create mdns server");
        let result = mdns_server.register(my_service);
        assert!(result.is_ok());

        let mdns_client = ServiceDaemon::new().expect("Failed to create mdns client");
        mdns_client.accept_unsolicited(true).unwrap();

        // Wait a bit for the service announcements to go out, before calling browse_cache.  This ensures
        // that the announcements are treated as unsolicited
        std::thread::sleep(Duration::from_secs(2));
        let browse_chan = mdns_client.browse_cache(service_type).unwrap();
        let timeout = Duration::from_millis(1500); // Give at least 1 second for the service probing.
        let mut resolved = false;

        // resolve the service.
        while let Ok(event) = browse_chan.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(info) = event {
                resolved = true;
                println!("Resolved a service of {}", info.get_fullname());
                break;
            }
        }

        assert!(resolved);

        // Exit the server so that no more responses.
        mdns_server.shutdown().unwrap();
        mdns_client.shutdown().unwrap();
    }

    #[test]
    fn test_custom_port_isolation() {
        // This test verifies:
        // 1. Daemons on a custom port can communicate with each other
        // 2. Daemons on different ports are isolated (no cross-talk)

        let service_type = "_custom_port._udp.local.";
        let instance_custom = "custom_port_instance";
        let instance_default = "default_port_instance";
        let host_name = "custom_port_host.local.";

        let service_ip_addr = my_ip_interfaces(false)
            .iter()
            .find(|iface| iface.ip().is_ipv4())
            .map(|iface| iface.ip())
            .expect("Test requires an IPv4 interface");

        // Create service info for custom port (5454)
        let service_custom = ServiceInfo::new(
            service_type,
            instance_custom,
            host_name,
            service_ip_addr,
            8080,
            None,
        )
        .unwrap();

        // Create service info for default port (5353)
        let service_default = ServiceInfo::new(
            service_type,
            instance_default,
            host_name,
            service_ip_addr,
            8081,
            None,
        )
        .unwrap();

        // Create two daemons on custom port 5454
        let custom_port = 5454u16;
        let server_custom =
            ServiceDaemon::new_with_port(custom_port).expect("Failed to create custom port server");
        let client_custom =
            ServiceDaemon::new_with_port(custom_port).expect("Failed to create custom port client");

        // Create daemon on default port (5353)
        let server_default = ServiceDaemon::new().expect("Failed to create default port server");

        // Register service on custom port
        server_custom
            .register(service_custom.clone())
            .expect("Failed to register custom port service");

        // Register service on default port
        server_default
            .register(service_default.clone())
            .expect("Failed to register default port service");

        // Browse from custom port client
        let browse_custom = client_custom
            .browse(service_type)
            .expect("Failed to browse on custom port");

        let timeout = Duration::from_secs(3);
        let mut found_custom = false;
        let mut found_default_on_custom = false;

        // Custom port client should find the custom port service
        while let Ok(event) = browse_custom.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(info) = event {
                println!(
                    "Custom port client resolved: {} on port {}",
                    info.get_fullname(),
                    info.get_port()
                );
                if info.get_fullname().starts_with(instance_custom) {
                    found_custom = true;
                    assert_eq!(info.get_port(), 8080);
                }
                if info.get_fullname().starts_with(instance_default) {
                    found_default_on_custom = true;
                }
            }
        }

        assert!(
            found_custom,
            "Custom port client should find service on custom port"
        );
        assert!(
            !found_default_on_custom,
            "Custom port client should NOT find service on default port"
        );

        // Now verify the default port daemon can find its own services
        // but not the custom port services
        let client_default = ServiceDaemon::new().expect("Failed to create default port client");
        let browse_default = client_default
            .browse(service_type)
            .expect("Failed to browse on default port");

        let mut found_default = false;
        let mut found_custom_on_default = false;

        while let Ok(event) = browse_default.recv_timeout(timeout) {
            if let ServiceEvent::ServiceResolved(info) = event {
                println!(
                    "Default port client resolved: {} on port {}",
                    info.get_fullname(),
                    info.get_port()
                );
                if info.get_fullname().starts_with(instance_default) {
                    found_default = true;
                    assert_eq!(info.get_port(), 8081);
                }
                if info.get_fullname().starts_with(instance_custom) {
                    found_custom_on_default = true;
                }
            }
        }

        assert!(
            found_default,
            "Default port client should find service on default port"
        );
        assert!(
            !found_custom_on_default,
            "Default port client should NOT find service on custom port"
        );

        // Cleanup
        server_custom.shutdown().unwrap();
        client_custom.shutdown().unwrap();
        server_default.shutdown().unwrap();
        client_default.shutdown().unwrap();
    }

    /// Regression test for such issue: an instance that is found (via PTR) but
    /// whose SRV/address answers are lost during the initial resolve attempts
    /// must not be stranded. As long as the browse is active, the daemon must
    /// keep re-querying for it.
    #[test]
    fn test_unresolved_instance_not_stranded() {
        use socket2::{Domain, Protocol, Socket, Type};
        use std::net::SocketAddrV4;

        // Pick the first IPv4 interface, like the other multicast tests.
        let intf_ip = match my_ip_interfaces(false)
            .into_iter()
            .find_map(|intf| match intf.ip() {
                IpAddr::V4(ip) if !ip.is_loopback() => Some(ip),
                _ => None,
            }) {
            Some(ip) => ip,
            None => {
                println!("No non-loopback IPv4 interface available; skipping test.");
                return;
            }
        };

        let unique = SystemTime::now()
            .duration_since(SystemTime::UNIX_EPOCH)
            .unwrap()
            .as_micros();
        let ty_domain = format!("_strandtest{unique}._udp.local.");
        let instance = format!("inst.{ty_domain}");
        // The SRV target is a distinct hostname, which is the case that needs a
        // separate address query.
        let host = format!("strandhost{unique}.local.");
        let port = 1234u16;
        let ttl = 4500u32;

        let if_id = InterfaceId {
            name: "test".to_string(),
            index: 0,
        };

        // Build our hand-rolled responder socket: bound to the mDNS port,
        // joined to the group, with loopback on so it exchanges packets with
        // the in-process daemon.
        let sock = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))
            .expect("create responder socket");
        sock.set_reuse_address(true).expect("set reuse_address");
        #[cfg(unix)]
        let _ = sock.set_reuse_port(true);
        sock.bind(&SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, MDNS_PORT).into())
            .expect("bind responder socket");
        sock.join_multicast_v4(&GROUP_ADDR_V4, &intf_ip)
            .expect("join multicast group");
        sock.set_multicast_if_v4(&intf_ip)
            .expect("set multicast_if");
        sock.set_multicast_loop_v4(true).expect("enable loopback");
        sock.set_read_timeout(Some(Duration::from_millis(100)))
            .expect("set read timeout");
        let responder: UdpSocket = sock.into();

        // A response carrying PTR + SRV, but deliberately no address record.
        let announce_packets = || {
            let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
            out.add_answer_record(DnsPointer::new(
                &ty_domain,
                RRType::PTR,
                CLASS_IN,
                ttl,
                instance.clone(),
            ));
            out.add_answer_record(DnsSrv::new(
                &instance,
                CLASS_IN,
                ttl,
                0,
                0,
                port,
                host.clone(),
            ));
            out.to_data_on_wire(MAX_PKT_DEFAULT, true)
        };

        // A response carrying just the withheld address record.
        let addr_packets = || {
            let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
            out.add_answer_record(DnsAddress::new(
                &host,
                RRType::A,
                CLASS_IN,
                ttl,
                IpAddr::V4(intf_ip),
                if_id.clone(),
            ));
            out.to_data_on_wire(MAX_PKT_DEFAULT, true)
        };

        let send_all = |packets: Vec<Vec<u8>>| {
            for packet in packets {
                let _ = responder.send_to(&packet, (GROUP_ADDR_V4, MDNS_PORT));
            }
        };

        // Start the browse, then announce (unsolicited) to seed the cache.
        let daemon = ServiceDaemon::new().expect("create daemon");
        let browse_rx = daemon.browse(&ty_domain).expect("start browse");
        send_all(announce_packets());

        // The number of address-query packets we must see before we start
        // answering. We withhold past the fast-path budget (`RESOLVE_MAX_TRY`
        // tries in `exec_command_resolve`) so that resolution can only come
        // from the browse retransmission cycle. The buggy code went silent
        // once the fast path was exhausted and never resolved the instance.
        let answer_after = RESOLVE_MAX_TRY as i32;
        let mut addr_query_count = 0;
        let mut resolved = false;
        let mut buf = [0u8; 2048];
        let deadline = Instant::now() + Duration::from_secs(20);

        while Instant::now() < deadline {
            // Drive the responder: react to whatever queries have arrived.
            while let Ok((len, from)) = responder.recv_from(&mut buf) {
                // The daemon sends each query on every interface (loopback
                // included) and on Linux this socket receives all copies. Count
                // only the copy sent on the interface we joined, so one daemon
                // query counts exactly once.
                if from.ip() != IpAddr::V4(intf_ip) {
                    continue;
                }
                let Ok(msg) = DnsIncoming::new(buf[..len].to_vec(), if_id.clone()) else {
                    continue;
                };
                if msg.is_response() {
                    continue;
                }

                let mut saw_addr_query = false;
                let mut saw_service_query = false;
                for q in msg.questions() {
                    let qname = q.entry_name();
                    if qname.eq_ignore_ascii_case(&host)
                        && matches!(q.entry_type(), RRType::A | RRType::AAAA)
                    {
                        saw_addr_query = true;
                    } else if qname.eq_ignore_ascii_case(&ty_domain)
                        || qname.eq_ignore_ascii_case(&instance)
                    {
                        saw_service_query = true;
                    }
                }

                // Keep the PTR/SRV fresh if the daemon asks for them.
                if saw_service_query {
                    send_all(announce_packets());
                }

                // Count address queries as one per packet (the daemon batches
                // A and AAAA into a single query). Only answer once the buggy
                // give-up window is behind us.
                if saw_addr_query {
                    addr_query_count += 1;
                    if addr_query_count > answer_after {
                        send_all(addr_packets());
                    }
                }
            }

            // Has the daemon resolved the instance yet?
            while let Ok(event) = browse_rx.try_recv() {
                if let ServiceEvent::ServiceResolved(info) = event {
                    if info.get_fullname().eq_ignore_ascii_case(&instance) {
                        resolved = true;
                    }
                }
            }

            if resolved {
                break;
            }
        }

        daemon.shutdown().unwrap();

        assert!(
            addr_query_count > answer_after,
            "daemon stopped querying for the address after {} tries; \
             an unresolved instance must keep being queried while the browse is active",
            addr_query_count
        );
        assert!(
            resolved,
            "instance was found but never resolved even though its address was \
             eventually answered"
        );
    }
    fn negative_answer_test_daemon() -> (super::Zeroconf, u32) {
        let (mut daemon, _receiver) = new_test_zeroconf_with_receiver();
        let index = my_ip_interfaces(true)
            .iter()
            .find(|intf| intf.ip() == IpAddr::V4(Ipv4Addr::LOCALHOST))
            .unwrap()
            .index
            .unwrap();
        // Only loopback and a private port are used for test announcements.
        daemon.my_intfs.retain(|key, _| *key == index);
        daemon.dns_registry_map.retain(|key, _| *key == index);
        (daemon, index)
    }

    fn register_negative_answer_test_service(
        daemon: &mut super::Zeroconf,
        index: u32,
        instance: &str,
        address: IpAddr,
    ) -> String {
        let service = ServiceInfo::new(
            "_negative-test._tcp.local.",
            instance,
            "negative.local.",
            address,
            8080,
            None,
        )
        .unwrap();
        let fullname = service.get_fullname().to_lowercase();
        daemon.register_service(service);
        // Complete actual registration probes deterministically.
        for probe in daemon
            .dns_registry_map
            .get_mut(&index)
            .unwrap()
            .probing
            .values_mut()
        {
            probe.start_time = Instant::now() - Duration::from_millis(1000);
            probe.next_send = probe.start_time;
        }
        daemon.probing_handler();
        assert_eq!(
            daemon.my_services[&fullname].get_status(index),
            crate::service_info::ServiceStatus::Announced
        );
        fullname
    }

    fn query_negative_answer_test_daemon(
        daemon: &mut super::Zeroconf,
        index: u32,
        name: &str,
        types: &[RRType],
    ) -> Option<DnsIncoming> {
        let querier = UdpSocket::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        querier
            .set_read_timeout(Some(Duration::from_millis(100)))
            .unwrap();
        let mut out = DnsOutgoing::new(FLAGS_QR_QUERY);
        for ty in types {
            out.add_question(name, *ty);
        }
        let interface = InterfaceId {
            name: "loopback-test".to_string(),
            index,
        };
        let packets = out.to_data_on_wire(MAX_PKT_DEFAULT, true);
        let incoming = DnsIncoming::new(packets[0].clone(), interface.clone()).unwrap();
        daemon.handle_query(incoming, index, querier.local_addr().unwrap());
        let mut data = [0; 4096];
        match querier.recv_from(&mut data) {
            Ok((length, _)) => Some(DnsIncoming::new(data[..length].to_vec(), interface).unwrap()),
            Err(error)
                if matches!(
                    error.kind(),
                    std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                ) =>
            {
                None
            }
            Err(error) => panic!("receiving test response: {}", error),
        }
    }

    #[test]
    fn test_negative_hostname_answers() {
        use super::DnsNSec;
        use crate::dns_parser::DnsRecordExt;

        for (address, present, absent) in [
            (IpAddr::V4(Ipv4Addr::LOCALHOST), RRType::A, RRType::AAAA),
            (IpAddr::V6(Ipv6Addr::LOCALHOST), RRType::AAAA, RRType::A),
        ] {
            let (mut daemon, index) = negative_answer_test_daemon();
            let fullname =
                register_negative_answer_test_service(&mut daemon, index, "single", address);
            for ty in [absent, RRType::SVCB, RRType::HTTPS] {
                let reply =
                    query_negative_answer_test_daemon(&mut daemon, index, "NEGATIVE.local.", &[ty])
                        .unwrap();
                assert_eq!(reply.answers().len(), 1);
                let nsec = reply.answers()[0].any().downcast_ref::<DnsNSec>().unwrap();
                assert_eq!(nsec._types(), vec![present as u16]);
                assert_eq!(nsec.get_name(), "negative.local.");
                assert!(nsec.get_record().get_ttl() <= LEGACY_UNICAST_MAX_TTL);
            }
            for ty in [present, RRType::ANY] {
                let reply =
                    query_negative_answer_test_daemon(&mut daemon, index, "negative.local.", &[ty])
                        .unwrap();
                assert!(reply
                    .answers()
                    .iter()
                    .any(|record| record.get_type() == present));
                assert!(reply
                    .answers()
                    .iter()
                    .all(|record| record.get_type() != RRType::NSEC));
            }
            let mixed = query_negative_answer_test_daemon(
                &mut daemon,
                index,
                "negative.local.",
                &[RRType::HTTPS, RRType::AAAA, RRType::A],
            )
            .unwrap();
            assert!(mixed
                .answers()
                .iter()
                .any(|record| record.get_type() == present));
            assert!(mixed
                .answers()
                .iter()
                .any(|record| record.get_type() == RRType::NSEC));
            assert!(query_negative_answer_test_daemon(
                &mut daemon,
                index,
                "unowned.local.",
                &[absent]
            )
            .is_none());
            daemon
                .my_services
                .get_mut(&fullname)
                .unwrap()
                .set_status(index, crate::service_info::ServiceStatus::Probing);
            assert!(query_negative_answer_test_daemon(
                &mut daemon,
                index,
                "negative.local.",
                &[absent]
            )
            .is_none());
        }
    }

    #[test]
    fn test_negative_hostname_answers_combine_registrations_on_one_interface() {
        let (mut daemon, index) = negative_answer_test_daemon();
        register_negative_answer_test_service(
            &mut daemon,
            index,
            "ipv4",
            IpAddr::V4(Ipv4Addr::LOCALHOST),
        );
        let ipv6 = register_negative_answer_test_service(
            &mut daemon,
            index,
            "ipv6",
            IpAddr::V6(Ipv6Addr::LOCALHOST),
        );
        for ty in [RRType::A, RRType::AAAA] {
            let reply =
                query_negative_answer_test_daemon(&mut daemon, index, "negative.local.", &[ty])
                    .unwrap();
            assert!(reply.answers().iter().any(|record| record.get_type() == ty));
            assert!(reply
                .answers()
                .iter()
                .all(|record| record.get_type() != RRType::NSEC));
        }
        let reply = query_negative_answer_test_daemon(
            &mut daemon,
            index,
            "negative.local.",
            &[RRType::HTTPS],
        )
        .unwrap();
        assert_eq!(reply.answers().len(), 1);
        assert_eq!(
            reply.answers()[0]
                .any()
                .downcast_ref::<super::DnsNSec>()
                .unwrap()
                ._types(),
            [1, 28]
        );
        // An address on another interface cannot prevent a negative answer here.
        daemon
            .my_services
            .get_mut(&ipv6)
            .unwrap()
            .remove_ipaddr(&IpAddr::V6(Ipv6Addr::LOCALHOST));
        daemon
            .my_services
            .get_mut(&ipv6)
            .unwrap()
            .insert_ipaddr(&test_interface(
                "other",
                index + 1,
                test_ifaddr_v6("2001:db8::1".parse().unwrap()),
            ));
        let reply = query_negative_answer_test_daemon(
            &mut daemon,
            index,
            "negative.local.",
            &[RRType::AAAA],
        )
        .unwrap();
        assert_eq!(
            reply.answers()[0]
                .any()
                .downcast_ref::<super::DnsNSec>()
                .unwrap()
                ._types(),
            [1]
        );
    }

    #[test]
    fn test_backpressure_terminates_subscription() {
        let mut zc = new_test_zeroconf();
        let ty = "_blocked._tcp.local.";
        let (sender, receiver) = flume::bounded(10);
        zc.service_queriers.insert(ty.to_string(), sender.clone());
        zc.add_retransmission(
            Instant::now() + Duration::from_secs(60),
            super::Command::Browse(ty.to_string(), 1, false, sender.clone()),
        );
        for i in 0..10 {
            sender
                .try_send(ServiceEvent::ServiceFound(ty.to_string(), format!("i{i}")))
                .unwrap();
        }
        zc.push_service(
            ty,
            ServiceEvent::ServiceResolved(Box::new(crate::ResolvedService {
                ty_domain: ty.to_string(),
                sub_ty_domain: None,
                fullname: "x._blocked._tcp.local.".to_string(),
                host: "x.local.".to_string(),
                port: 80,
                addresses: HashSet::new(),
                txt_properties: crate::TxtProperties::new(),
            })),
        );
        assert!(!zc.service_queriers.contains_key(ty));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::Browse(t, _, _, _) if t == ty
        )));
        assert_eq!(receiver.len(), 10);
        zc.push_service(
            ty,
            ServiceEvent::ServiceRemoved(ty.to_string(), "x._blocked._tcp.local.".to_string()),
        );
        for i in 0..10 {
            match receiver.try_recv().unwrap() {
                ServiceEvent::ServiceFound(_, name) => assert_eq!(name, format!("i{i}")),
                e => panic!("reordered event: {:?}", e),
            }
        }
        assert!(matches!(
            receiver.try_recv(),
            Err(flume::TryRecvError::Empty)
        ));
        drop(sender);
        assert!(matches!(
            receiver.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));

        let hostname = "blocked.local.";
        let (hsender, hreceiver) = flume::bounded(10);
        zc.hostname_resolvers
            .insert(hostname.to_string(), (hsender.clone(), None));
        for i in 0..10 {
            hsender
                .try_send(HostnameResolutionEvent::SearchStarted(format!("{i}")))
                .unwrap();
        }
        zc.push_hostname(
            hostname,
            HostnameResolutionEvent::AddressesFound(hostname.to_string(), HashSet::new()),
        );
        assert!(!zc.hostname_resolvers.contains_key(hostname));
        zc.push_hostname(
            hostname,
            HostnameResolutionEvent::AddressesRemoved(hostname.to_string(), HashSet::new()),
        );
        assert_eq!(hreceiver.len(), 10);
        drop(hsender);
        while hreceiver.try_recv().is_ok() {}
        assert!(matches!(
            hreceiver.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));
    }

    #[test]
    fn test_stale_retransmission_no_revive() {
        let mut zc = new_test_zeroconf();
        let ty = "_stale._tcp.local.";
        let (old_sender, old_receiver) = flume::bounded(10);
        zc.service_queriers
            .insert(ty.to_string(), old_sender.clone());
        for i in 0..10 {
            old_sender
                .try_send(ServiceEvent::ServiceFound(ty.to_string(), format!("i{i}")))
                .unwrap();
        }
        zc.push_service(
            ty,
            ServiceEvent::ServiceFound(ty.to_string(), "overflow".to_string()),
        );
        assert!(!zc.service_queriers.contains_key(ty));
        let (new_sender, new_receiver) = flume::bounded(10);
        zc.service_queriers
            .insert(ty.to_string(), new_sender.clone());
        let retrans_before = zc.retransmissions.len();
        zc.exec_command_browse(true, ty.to_string(), 1, false, old_sender.clone());
        assert!(zc
            .service_queriers
            .get(ty)
            .unwrap()
            .same_channel(&new_sender));
        assert_eq!(new_receiver.len(), 0);
        assert_eq!(zc.retransmissions.len(), retrans_before);
        drop(old_sender);
        while old_receiver.try_recv().is_ok() {}
        assert!(matches!(
            old_receiver.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));
    }

    #[test]
    fn test_cache_replay_overflow_terminates() {
        let mut zc = new_test_zeroconf();
        zc.accept_unsolicited = true;
        let ty = "_replay._tcp.local.";
        let index = my_ip_interfaces(true)
            .into_iter()
            .find(|intf| intf.ip() == IpAddr::V4(Ipv4Addr::LOCALHOST))
            .unwrap()
            .index
            .unwrap();
        let interface_id = InterfaceId {
            name: "test".to_string(),
            index,
        };
        let mut out = DnsOutgoing::new(FLAGS_QR_RESPONSE | FLAGS_AA);
        for i in 0..12 {
            out.add_answer_record(DnsPointer::new(
                ty,
                RRType::PTR,
                CLASS_IN,
                120,
                format!("i{i}._replay._tcp.local."),
            ));
        }
        for packet in out.to_data_on_wire(MAX_PKT_DEFAULT, true) {
            let msg = DnsIncoming::new(packet, interface_id.clone()).unwrap();
            zc.handle_response(msg, index);
        }
        assert_eq!(zc.cache.get_ptr(ty).map(|v| v.len()).unwrap_or(0), 12);
        let (sender, receiver) = flume::bounded(10);
        zc.exec_command_browse(false, ty.to_string(), 1, false, sender);
        assert!(!zc.service_queriers.contains_key(ty));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::Browse(t, _, _, _) if t == ty
        )));
        assert_eq!(receiver.len(), 10);
        match receiver.try_recv().unwrap() {
            ServiceEvent::SearchStarted(_) => {}
            e => panic!("expected SearchStarted first: {:?}", e),
        }
    }

    #[test]
    fn test_retransmission_overflow_terminates() {
        let mut zc = new_test_zeroconf();
        let ty = "_retr._tcp.local.";
        let (sender, receiver) = flume::bounded(10);
        zc.service_queriers.insert(ty.to_string(), sender.clone());
        for i in 0..10 {
            sender
                .try_send(ServiceEvent::ServiceFound(ty.to_string(), format!("i{i}")))
                .unwrap();
        }
        let retrans_before = zc.retransmissions.len();
        zc.exec_command_browse(true, ty.to_string(), 1, false, sender.clone());
        assert!(!zc.service_queriers.contains_key(ty));
        assert_eq!(zc.retransmissions.len(), retrans_before);
        assert_eq!(receiver.len(), 10);

        let hostname = "retr.local.";
        let (hsender, hreceiver) = flume::bounded(10);
        zc.hostname_resolvers
            .insert(hostname.to_string(), (hsender.clone(), None));
        for i in 0..10 {
            hsender
                .try_send(HostnameResolutionEvent::SearchStarted(format!("{i}")))
                .unwrap();
        }
        let retrans_before = zc.retransmissions.len();
        zc.exec_command_resolve_hostname(true, hostname.to_string(), 1, hsender.clone(), None);
        assert!(!zc.hostname_resolvers.contains_key(hostname));
        assert_eq!(zc.retransmissions.len(), retrans_before);
        assert_eq!(hreceiver.len(), 10);
    }

    #[test]
    fn test_hostname_timeout_releases_ownership() {
        let mut zc = new_test_zeroconf();
        let hostname = "timeout.local.";
        let (sender, receiver) = flume::bounded(10);
        zc.hostname_resolvers.insert(
            hostname.to_string(),
            (
                sender.clone(),
                Some(Instant::now() - Duration::from_secs(1)),
            ),
        );
        zc.add_retransmission(
            Instant::now() + Duration::from_secs(60),
            super::Command::ResolveHostname(hostname.to_string(), 1, sender.clone(), None),
        );
        zc.expire_hostname_resolvers(Instant::now());
        assert!(!zc.hostname_resolvers.contains_key(hostname));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::ResolveHostname(h, _, _, _) if h == hostname
        )));
        drop(sender);
        let mut saw_timeout = false;
        let mut saw_stopped = false;
        while let Ok(event) = receiver.try_recv() {
            match event {
                HostnameResolutionEvent::SearchTimeout(_) => saw_timeout = true,
                HostnameResolutionEvent::SearchStopped(_) => saw_stopped = true,
                e => panic!("unexpected event: {:?}", e),
            }
        }
        assert!(saw_timeout && saw_stopped);
        assert!(matches!(
            receiver.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));
    }

    #[test]
    fn test_hostname_timeout_full_releases_ownership() {
        let mut zc = new_test_zeroconf();
        let hostname = "timeout-full.local.";
        let (sender, receiver) = flume::bounded(10);
        zc.hostname_resolvers.insert(
            hostname.to_string(),
            (
                sender.clone(),
                Some(Instant::now() - Duration::from_secs(1)),
            ),
        );
        for i in 0..10 {
            sender
                .try_send(HostnameResolutionEvent::SearchStarted(format!("{i}")))
                .unwrap();
        }
        zc.expire_hostname_resolvers(Instant::now());
        assert!(!zc.hostname_resolvers.contains_key(hostname));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::ResolveHostname(h, _, _, _) if h == hostname
        )));
        assert_eq!(receiver.len(), 10);
        drop(sender);
        while receiver.try_recv().is_ok() {}
        assert!(matches!(
            receiver.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));
    }

    #[test]
    fn test_stop_and_resubscribe_after_stall() {
        let mut zc = new_test_zeroconf();
        let ty = "_restall._tcp.local.";
        let (sender, receiver) = flume::bounded(10);
        zc.service_queriers.insert(ty.to_string(), sender.clone());
        zc.add_retransmission(
            Instant::now() + Duration::from_secs(60),
            super::Command::Browse(ty.to_string(), 1, false, sender.clone()),
        );
        for i in 0..10 {
            let _ = sender.try_send(ServiceEvent::ServiceFound(ty.to_string(), format!("i{i}")));
        }
        zc.exec_command_stop_browse(ty.to_string());
        assert!(!zc.service_queriers.contains_key(ty));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::Browse(t, _, _, _) if t == ty
        )));
        drop(sender);
        while receiver.try_recv().is_ok() {}
        assert!(matches!(
            receiver.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));
        let (sender2, receiver2) = flume::bounded(10);
        zc.service_queriers.insert(ty.to_string(), sender2);
        zc.push_service(
            ty,
            ServiceEvent::ServiceFound(ty.to_string(), "new".to_string()),
        );
        match receiver2.try_recv().unwrap() {
            ServiceEvent::ServiceFound(t, name) => {
                assert_eq!(t, ty);
                assert_eq!(name, "new");
            }
            e => panic!("unexpected event: {:?}", e),
        }

        let hostname = "restall.local.";
        let (hsender, hreceiver) = flume::bounded(10);
        zc.hostname_resolvers
            .insert(hostname.to_string(), (hsender.clone(), None));
        zc.add_retransmission(
            Instant::now() + Duration::from_secs(60),
            super::Command::ResolveHostname(hostname.to_string(), 1, hsender.clone(), None),
        );
        for i in 0..10 {
            let _ = hsender.try_send(HostnameResolutionEvent::SearchStarted(format!("{i}")));
        }
        zc.exec_command_stop_resolve_hostname(hostname.to_string());
        assert!(!zc.hostname_resolvers.contains_key(hostname));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::ResolveHostname(h, _, _, _) if h == hostname
        )));
        drop(hsender);
        while hreceiver.try_recv().is_ok() {}
        assert!(matches!(
            hreceiver.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));
    }

    #[test]
    fn test_cleanup_full_listeners() {
        let mut zc = new_test_zeroconf();
        let ty = "_cleanup._tcp.local.";
        let (sender, _receiver) = flume::bounded(10);
        zc.service_queriers.insert(ty.to_string(), sender.clone());
        for i in 0..10 {
            sender
                .try_send(ServiceEvent::ServiceFound(ty.to_string(), format!("i{i}")))
                .unwrap();
        }
        let hostname = "cleanup.local.";
        let (hsender, _) = flume::bounded(10);
        zc.hostname_resolvers
            .insert(hostname.to_string(), (hsender.clone(), None));
        for i in 0..10 {
            let _ = hsender.try_send(HostnameResolutionEvent::SearchStarted(format!("{i}")));
        }
        zc.cleanup();
        assert!(zc.service_queriers.is_empty());
        assert!(zc.hostname_resolvers.is_empty());
        assert!(zc.retransmissions.is_empty());
    }

    #[test]
    fn test_replace_browse_releases_old_generation() {
        let mut zc = new_test_zeroconf();
        let ty = "_replace._tcp.local.";
        let (sender_a, receiver_a) = flume::bounded(10);
        let probe_a = sender_a.clone();
        zc.exec_command_browse(false, ty.to_string(), 1, false, sender_a);
        assert!(zc.service_queriers.get(ty).unwrap().same_channel(&probe_a));
        assert!(zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::Browse(t, _, _, s) if t == ty && s.same_channel(&probe_a)
        )));

        let (sender_b, receiver_b) = flume::bounded(10);
        let probe_b = sender_b.clone();
        zc.exec_command_browse(false, ty.to_string(), 1, false, sender_b);
        assert!(zc.service_queriers.get(ty).unwrap().same_channel(&probe_b));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::Browse(t, _, _, s) if t == ty && s.same_channel(&probe_a)
        )));
        drop(probe_a);
        while receiver_a.try_recv().is_ok() {}
        assert!(matches!(
            receiver_a.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));

        zc.exec_command_browse(true, ty.to_string(), 1, false, probe_b.clone());
        assert!(zc.service_queriers.get(ty).unwrap().same_channel(&probe_b));
        assert!(matches!(
            receiver_b.try_recv(),
            Ok(ServiceEvent::SearchStarted(_))
        ));
    }

    #[test]
    fn test_replace_hostname_releases_old_generation() {
        let mut zc = new_test_zeroconf();
        let hostname = "replace.local.";
        let (sender_a, receiver_a) = flume::bounded(10);
        let probe_a = sender_a.clone();
        zc.exec_command_resolve_hostname(false, hostname.to_string(), 1, sender_a, None);
        assert!(zc
            .hostname_resolvers
            .get(hostname)
            .unwrap()
            .0
            .same_channel(&probe_a));

        let (sender_b, receiver_b) = flume::bounded(10);
        let probe_b = sender_b.clone();
        zc.exec_command_resolve_hostname(false, hostname.to_string(), 1, sender_b, None);
        assert!(zc
            .hostname_resolvers
            .get(hostname)
            .unwrap()
            .0
            .same_channel(&probe_b));
        assert!(!zc.retransmissions.iter().any(|r| matches!(
            &r.command,
            super::Command::ResolveHostname(h, _, s, _) if h == hostname && s.same_channel(&probe_a)
        )));
        drop(probe_a);
        while receiver_a.try_recv().is_ok() {}
        assert!(matches!(
            receiver_a.try_recv(),
            Err(flume::TryRecvError::Disconnected)
        ));

        zc.exec_command_resolve_hostname(true, hostname.to_string(), 1, probe_b.clone(), None);
        assert!(zc
            .hostname_resolvers
            .get(hostname)
            .unwrap()
            .0
            .same_channel(&probe_b));
        assert!(matches!(
            receiver_b.try_recv(),
            Ok(HostnameResolutionEvent::SearchStarted(_))
        ));
    }
}
