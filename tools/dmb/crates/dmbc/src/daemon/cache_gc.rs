//! Keeps the shared cache directory inside a byte budget, least recently used segments first.
//!
//! `DMB_CACHE_BUDGET_GB` (default 32, `0` disables) bounds `dm_cache::Cache::default_root()`. The daemon runs one pass shortly
//! after it starts and one every six hours while it lives; leaves modified within `DMB_CACHE_MIN_AGE_MINUTES` (default 120) are
//! never deleted. Why it exists and why recency is trustworthy: `dm-cache/src/store_budget.rs`. Every request opens the index of
//! every segment in the directory, so the budget bounds that memory and open time as well as the disk.
use std::{
    io,
    time::{Duration, Instant, SystemTime},
};

const DEFAULT_BUDGET_GB: u64 = 32;
const DEFAULT_MIN_AGE_MINUTES: u64 = 120;
const FIRST_PASS_DELAY: Duration = Duration::from_secs(120);
const PASS_INTERVAL: Duration = Duration::from_secs(6 * 3600);

/// Budget in bytes; None when disabled. An unparseable value keeps the default (and says so).
pub(super) fn budget_bytes(value: Option<&str>) -> Option<u64> {
    match value {
        None | Some("") => Some(DEFAULT_BUDGET_GB * 1_000_000_000),
        Some(text) => match text.parse::<u64>() {
            Ok(0) => None,
            Ok(gb) => Some(gb.saturating_mul(1_000_000_000)),
            Err(_) => {
                eprintln!("dmbd cache budget: DMB_CACHE_BUDGET_GB={text:?} is not a whole number of GB; using {DEFAULT_BUDGET_GB}");
                Some(DEFAULT_BUDGET_GB * 1_000_000_000)
            }
        },
    }
}

fn min_age(value: Option<&str>) -> Duration {
    Duration::from_secs(60 * value.and_then(|text| text.parse::<u64>().ok()).unwrap_or(DEFAULT_MIN_AGE_MINUTES))
}

/// One pass; returns a log line. Never panics the daemon: every failure is reported and the next pass retries.
pub(super) fn run_once(budget: u64, min_age: Duration) -> String {
    let started = Instant::now();
    let outcome = dm_cache::Cache::default_root()
        .and_then(|root| dm_cache::Cache::open(root, dm_cache::Limits::default()))
        .and_then(|cache| cache.evict_to_budget(SystemTime::now(), budget, min_age));
    match outcome {
        Ok(report) => format!(
            "dmbd cache budget: {:.1} GB -> {:.1} GB of {:.1} GB, deleted {} of {} leaves ({:.1} GB), deferred {}, protected {}, {:.2}s",
            report.total_before as f64 / 1e9,
            report.total_after as f64 / 1e9,
            budget as f64 / 1e9,
            report.deleted,
            report.leaves,
            report.deleted_bytes as f64 / 1e9,
            report.deferred,
            report.protected,
            started.elapsed().as_secs_f64()
        ),
        Err(error) => format!("dmbd cache budget: pass skipped: {error}"),
    }
}

/// Start the background pass thread (once per daemon). Returns Ok(()) without a thread when the budget is disabled.
pub(super) fn spawn() -> io::Result<()> {
    let Some(budget) = budget_bytes(std::env::var("DMB_CACHE_BUDGET_GB").ok().as_deref()) else {
        eprintln!("dmbd cache budget: disabled (DMB_CACHE_BUDGET_GB=0)");
        return Ok(());
    };
    let min_age = min_age(std::env::var("DMB_CACHE_MIN_AGE_MINUTES").ok().as_deref());
    std::thread::Builder::new().name("dmbd-cache-budget".into()).spawn(move || {
        std::thread::sleep(FIRST_PASS_DELAY);
        loop {
            eprintln!("{}", run_once(budget, min_age));
            std::thread::sleep(PASS_INTERVAL);
        }
    })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budget_parses_zero_as_disabled_and_garbage_as_the_default() {
        assert_eq!(budget_bytes(None), Some(32_000_000_000));
        assert_eq!(budget_bytes(Some("")), Some(32_000_000_000));
        assert_eq!(budget_bytes(Some("8")), Some(8_000_000_000));
        assert_eq!(budget_bytes(Some("0")), None);
        assert_eq!(budget_bytes(Some("lots")), Some(32_000_000_000));
        assert_eq!(min_age(None), Duration::from_secs(7200));
        assert_eq!(min_age(Some("5")), Duration::from_secs(300));
    }
}
