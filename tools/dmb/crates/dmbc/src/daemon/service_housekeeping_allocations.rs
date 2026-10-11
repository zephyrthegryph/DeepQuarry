//! Cheap process-wide allocation observation; never traverses retained owners.
//!
//! Requested Rust bytes exclude allocator overhead, committed spare pages and
//! non-Rust allocations. They are not an attribution to the released session.
use std::fmt;

pub(super) struct RequestedLive(Option<u64>);

pub(super) fn requested_live() -> RequestedLive {
    #[cfg(feature = "allocation-counting")]
    let bytes = Some(dm_profile::CountingAllocator::live_requested_bytes());
    #[cfg(not(feature = "allocation-counting"))]
    let bytes = None;
    RequestedLive(bytes)
}

impl fmt::Display for RequestedLive {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.0 {
            Some(bytes) => bytes.fmt(formatter),
            None => formatter.write_str("null"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn absence_is_null_and_known_zero_is_not_absence() {
        assert_eq!(RequestedLive(None).to_string(), "null");
        assert_eq!(RequestedLive(Some(0)).to_string(), "0");
        assert_eq!(RequestedLive(Some(123)).to_string(), "123");
        #[cfg(not(feature = "allocation-counting"))]
        assert_eq!(requested_live().to_string(), "null");
    }
}
