//! Startup-only soft pressure policy; this is not a hard allocation bound.
//! DMB_DAEMON_SOFT_PRIVATE_BYTES accepts 256 MiB..32 GiB integer bytes.
//! Unset uses 5,333,333,332 bytes, the soft limit of an 8 GB budget (hard ceiling 8 GB): the daemon
//! must leave room for the player's machine, and retained sessions are being shrunk to fit.
use std::{ffi::OsStr, io};
pub(super) const DEFAULT: u64 = 5_333_333_332;
pub(super) fn startup() -> io::Result<u64> {
    if std::env::var_os("DMB_DAEMON_SOFT_PRIVATE_BYTES").is_none() {
        if let Some(budget) = std::env::var_os("DMB_DAEMON_MEMORY_BUDGET_GB") {
            return budget_soft(&budget);
        }
    }
    parse(std::env::var_os("DMB_DAEMON_SOFT_PRIVATE_BYTES").as_deref())
}
/// DMB_DAEMON_MEMORY_BUDGET_GB (default 8, so unset keeps `DEFAULT`/1.5x) is the whole daemon's private-memory budget across
/// every retained project: it becomes the hard ceiling (soft limit is two thirds of it). Above it the least recently used project
/// session is released whole.
fn budget_soft(value: &OsStr) -> io::Result<u64> {
    value.to_str().filter(|text| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()))
        .and_then(|text| text.parse::<u64>().ok())
        .filter(|gb| (1..=48).contains(gb))
        .map(|gb| gb * 1_000_000_000 / 3 * 2)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput,
            "DMB_DAEMON_MEMORY_BUDGET_GB must be an integer from 1 through 48"))
}
/// Ceiling above which the compact symbolic core, generation and link bindings
/// may be evicted. Below it pressure sheds only transient buffers, so the next
/// edit stays resident. DMB_DAEMON_HARD_PRIVATE_BYTES overrides; the default is
/// 1.5x the soft limit (measured: the full resident memo for DeepQuarry is about 6 GB private, of which about 2.3 GB is the compactable symbolic/classification stores that give edit hits) and an explicit value below the soft limit is rejected.
pub(super) fn hard(soft: u64) -> io::Result<u64> {
    match std::env::var_os("DMB_DAEMON_HARD_PRIVATE_BYTES") {
        None => Ok(soft.saturating_add(soft / 2)),
        Some(value) => parse(Some(&value)).and_then(|hard| {
            if hard >= soft {
                Ok(hard)
            } else {
                Err(io::Error::new(io::ErrorKind::InvalidInput,
                    "DMB_DAEMON_HARD_PRIVATE_BYTES must not be below the soft limit"))
            }
        }),
    }
}
fn parse(value: Option<&OsStr>) -> io::Result<u64> {
    let Some(value) = value else {
        return Ok(DEFAULT);
    };
    value.to_str().filter(|text| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()))
        .and_then(|text| text.parse::<u64>().ok())
        .filter(|value| (268_435_456..=34_359_738_368).contains(value))
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput,
            "DMB_DAEMON_SOFT_PRIVATE_BYTES must be integer bytes from 268435456 through 34359738368"))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn hard_ceiling_defaults_above_soft_limit() {
        if std::env::var_os("DMB_DAEMON_HARD_PRIVATE_BYTES").is_none() {
            assert_eq!(hard(DEFAULT).unwrap(), 7_999_999_998);
        }
    }
    #[test]
    fn budget_maps_to_hard_ceiling() {
        assert_eq!(budget_soft(OsStr::new("8")).unwrap(), DEFAULT);
        assert_eq!(budget_soft(OsStr::new("6")).unwrap() + budget_soft(OsStr::new("6")).unwrap() / 2, 6_000_000_000);
        for value in ["", "0", "49", "x", "-3"] {
            assert!(budget_soft(OsStr::new(value)).is_err());
        }
    }
    #[test]
    fn startup_policy_default_bounds_and_overflow() {
        assert_eq!(parse(None).unwrap(), DEFAULT);
        for value in [268_435_456, 2_000_000_000, 34_359_738_368] {
            assert_eq!(parse(Some(OsStr::new(&value.to_string()))).unwrap(), value);
        }
        for value in [
            "",
            "0",
            "-1",
            " 268435456",
            "268435455",
            "34359738369",
            "18446744073709551616",
        ] {
            assert!(parse(Some(OsStr::new(value))).is_err());
        }
    }
}
