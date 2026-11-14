//! Entry points for the fuzz targets under `fuzz/`.
//!
//! This module is not part of the public API. It exists because `dns_parser` is
//! private to the crate, and a fuzz target is a separate crate that could not
//! otherwise call it. Keeping thin wrappers here, rather than making that module
//! public, keeps the exposed surface small and deliberate. Targets that need to
//! reach further in (`dns_cache`, say) should add a wrapper here too.

use crate::dns_parser::{DnsIncoming, InterfaceId};

/// The interface a fuzzed packet is attributed to.
///
/// Records are cached per interface, so the value matters for targets that reach
/// the cache; for parsing alone any fixed value will do.
fn fuzz_interface_id() -> InterfaceId {
    InterfaceId {
        name: "fuzz0".to_string(),
        index: 1,
    }
}

/// Parses one raw packet, the way `ServiceDaemon` parses bytes read off a UDP
/// socket, and checks the invariants that hold for any packet that parses.
///
/// Malformed input is expected and is not a finding: the target is looking for
/// panics, hangs, and broken invariants, not for parse errors.
pub fn parse_packet(data: &[u8]) {
    let msg = match DnsIncoming::new(data.to_vec(), fuzz_interface_id()) {
        Ok(msg) => msg,
        Err(e) => {
            // Render the error as it formats slices of the raw packet,
            // so it is worth fuzzing in its own right.
            let _ = e.to_string();
            return;
        }
    };

    assert_eq!(
        msg.questions().len(),
        msg.num_questions() as usize,
        "parsed question count must match the header"
    );

    // Records, unlike questions, may be skipped individually: a record whose
    // rdata does not parse is dropped and the rest of the packet is kept. So
    // these counts are upper bounds, not equalities.
    //
    // The answer section is not checked here only because `DnsIncoming` exposes
    // no `num_answers()` getter.
    assert!(
        msg.authorities().len() <= msg.num_authorities() as usize,
        "parsed more authorities than the header declared"
    );
    assert!(
        msg.additionals().len() <= msg.num_additionals() as usize,
        "parsed more additionals than the header declared"
    );

    // A message is exactly one of a query or a response.
    assert!(
        msg.is_query() != msg.is_response(),
        "a message must be either a query or a response"
    );

    // Walk the records, so the fuzzer reaches the accessors and the `Debug`
    // impls of the record trait objects rather than stopping at the parse loop.
    // `Debug` for `DnsIncoming` slices the raw packet, so exercise it directly.
    let _ = format!("{msg:?}");
    for record in msg.all_records() {
        let _ = format!("{record:?}");
    }
}
