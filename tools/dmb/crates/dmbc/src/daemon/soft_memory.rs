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

// ---------------------------------------------------------------------------------------------------------------------
// Adaptive budget. A fixed 8 GB budget evicted retained sessions while gigabytes of RAM were free (one DeepQuarry session is
// about 10 GB private), and a fixed number says nothing about the player's machine. Unless the budget is set explicitly, the
// limits follow what the machine has: pressure means "available physical memory is running out", not "this process is big".
//   hard      available physical memory < reserve (default 8 GB, DMB_DAEMON_FREE_RESERVE_GB), or private >= ceiling
//   soft      available physical memory < reserve + SOFT_MARGIN, or private >= ceiling
//   emergency available physical memory < reserve / 2: even the newest session loses its shield
// A compile is admitted only while available memory covers its expected growth on top of the reserve (see `Shared::await_memory`).
// DMB_DAEMON_ADAPTIVE=0, or an explicit DMB_DAEMON_SOFT_PRIVATE_BYTES / DMB_DAEMON_HARD_PRIVATE_BYTES / DMB_DAEMON_MEMORY_BUDGET_GB,
// keeps the fixed limits above.
use std::sync::atomic::{AtomicU64, Ordering};

pub(super) const DEFAULT_RESERVE: u64 = 8_000_000_000;
pub(super) const SOFT_MARGIN: u64 = 4_000_000_000;
/// Private-bytes ceiling in adaptive mode: a runaway guard, never the working limit.
pub(super) const ADAPTIVE_CEILING: u64 = 40_000_000_000;
static RESERVE: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) struct Pressure {
    pub(super) soft: bool,
    pub(super) hard: bool,
    pub(super) emergency: bool,
}
pub(super) fn classify(available: u64, private: u64, reserve: u64) -> Pressure {
    let over_ceiling = private >= ADAPTIVE_CEILING;
    Pressure {
        soft: available < reserve.saturating_add(SOFT_MARGIN) || over_ceiling,
        hard: available < reserve || over_ceiling,
        emergency: available < reserve / 2,
    }
}
fn reserve_from(value: Option<&OsStr>) -> io::Result<u64> {
    let Some(value) = value else { return Ok(DEFAULT_RESERVE) };
    value.to_str().filter(|text| !text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()))
        .and_then(|text| text.parse::<u64>().ok())
        .filter(|gb| *gb <= 60)
        .map(|gb| gb * 1_000_000_000)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "DMB_DAEMON_FREE_RESERVE_GB must be an integer from 0 through 60"))
}
/// Turn the adaptive budget on when nothing sets an explicit one and the machine reports available memory. Returns the reserve.
pub(super) fn enable_adaptive() -> io::Result<Option<u64>> {
    let explicit = ["DMB_DAEMON_SOFT_PRIVATE_BYTES", "DMB_DAEMON_HARD_PRIVATE_BYTES", "DMB_DAEMON_MEMORY_BUDGET_GB"]
        .iter()
        .any(|name| std::env::var_os(name).is_some());
    if explicit || std::env::var_os("DMB_DAEMON_ADAPTIVE").is_some_and(|value| value == "0") || available().is_none() {
        return Ok(None);
    }
    let reserve = reserve_from(std::env::var_os("DMB_DAEMON_FREE_RESERVE_GB").as_deref())?;
    RESERVE.store(reserve.max(1), Ordering::Release);
    Ok(Some(reserve))
}
pub(super) fn available() -> Option<u64> {
    super::transport::available_physical_bytes()
}
/// The configured reserve while the adaptive budget is on.
pub(super) fn adaptive_reserve() -> Option<u64> {
    match RESERVE.load(Ordering::Acquire) {
        0 => None,
        reserve => Some(reserve),
    }
}
/// Current pressure under the adaptive budget; None when it is off or the machine will not say.
pub(super) fn adaptive_pressure(private: u64) -> Option<Pressure> {
    let reserve = adaptive_reserve()?;
    Some(classify(available()?, private, reserve))
}

#[cfg(test)]
mod adaptive_tests {
    use super::*;
    const GB: u64 = 1_000_000_000;
    #[test]
    fn pressure_follows_available_memory_not_process_size() {
        // A 12 GB daemon with 20 GB free is not under any pressure: the old fixed 8 GB budget evicted here.
        assert_eq!(classify(20 * GB, 12 * GB, 8 * GB), Pressure { soft: false, hard: false, emergency: false });
        assert_eq!(classify(11 * GB, 1 * GB, 8 * GB), Pressure { soft: true, hard: false, emergency: false });
        assert_eq!(classify(7 * GB, 1 * GB, 8 * GB), Pressure { soft: true, hard: true, emergency: false });
        assert_eq!(classify(3 * GB, 1 * GB, 8 * GB), Pressure { soft: true, hard: true, emergency: true });
        assert!(classify(50 * GB, ADAPTIVE_CEILING, 8 * GB).hard);
    }
    #[test]
    fn reserve_setting_is_validated() {
        assert_eq!(reserve_from(None).unwrap(), DEFAULT_RESERVE);
        assert_eq!(reserve_from(Some(OsStr::new("12"))).unwrap(), 12 * GB);
        for value in ["", "x", "-1", "61"] {
            assert!(reserve_from(Some(OsStr::new(value))).is_err());
        }
    }
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
