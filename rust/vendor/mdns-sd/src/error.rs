use std::fmt;

/// A basic error type from this library.
#[derive(Clone, Debug, PartialEq, Eq)]
#[non_exhaustive]
pub enum Error {
    /// Like a classic `EAGAIN`. Returned by [`ServiceDaemon`](crate::ServiceDaemon)
    /// methods when the daemon's bounded command queue is temporarily full,
    /// so the command could not be enqueued. The caller can retry after a
    /// short delay.
    Again,

    /// The daemon thread has exited and its command channel is closed, so the
    /// command could not be delivered. Returned by [`ServiceDaemon`](crate::ServiceDaemon)
    /// methods after [`shutdown`](crate::ServiceDaemon::shutdown) has been
    /// called or after the daemon thread has terminated for another reason.
    /// Retrying will not help; callers should log and move on (or create a
    /// new [`ServiceDaemon`](crate::ServiceDaemon)).
    DaemonShutdown,

    /// A generic error message.
    Msg(String),

    /// Error during parsing of ip address
    ParseIpAddr(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Msg(s) => write!(f, "{s}"),
            Self::ParseIpAddr(s) => write!(f, "parsing of ip addr failed, reason: {s}"),
            Self::Again => write!(f, "try again"),
            Self::DaemonShutdown => write!(f, "daemon has shut down"),
        }
    }
}

impl std::error::Error for Error {}

/// One and only `Result` type from this library crate.
pub type Result<T> = core::result::Result<T, Error>;

/// A simple macro to report all kinds of errors.
macro_rules! e_fmt {
    ($($arg:tt)+) => {
        Error::Msg(format!($($arg)+))
    };
  }

pub(crate) use e_fmt;
