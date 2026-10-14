//! Startup-only soft pressure policy; this is not a hard allocation bound.
//! DMB_DAEMON_SOFT_PRIVATE_BYTES accepts 256 MiB..32 GiB integer bytes.
//! Unset uses 8,000,000,000 bytes: the retained DeepQuarry session is about 6 GB
//! private, so a lower default keeps the daemon in permanent soft pressure.
use std::{ffi::OsStr, io};
pub(super) const DEFAULT: u64 = 8_000_000_000;
pub(super) fn startup() -> io::Result<u64> {
    parse(std::env::var_os("DMB_DAEMON_SOFT_PRIVATE_BYTES").as_deref())
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
            assert_eq!(hard(DEFAULT).unwrap(), 12_000_000_000);
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
