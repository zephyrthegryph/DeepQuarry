//! Explicit maintenance uses the same typed admission boundaries as reuse.
use std::{
    path::Path,
    time::{Duration, SystemTime},
};
fn validate(key: dm_cache::RecordKey, bytes: &[u8], _: &[(u64, &[u8])]) -> Result<(), String> {
    use dm_preprocess::regions::{
        DirectiveRecord, ExpansionRecord, DIRECTIVE_VERSION, EXPANSION_VERSION,
    };
    match key.stage {
        1 if key.version == EXPANSION_VERSION => {
            for entry in dm_cache::decode_variants(bytes)? {
                ExpansionRecord::from_bytes(entry)?;
            }
            Ok(())
        }
        2 if key.version == crate::lowering_memo::PROCEDURE_VERSION => {
            for entry in dm_cache::decode_variants(bytes)? {
                crate::lowering_memo_wire::validate(entry)?;
            }
            Ok(())
        }
        3 => crate::map_memo::MapMemo::validate_cache_payload(key.version, bytes),
        4 if key.version == DIRECTIVE_VERSION => {
            for entry in dm_cache::decode_variants(bytes)? {
                DirectiveRecord::from_bytes(entry)?;
            }
            Ok(())
        }
        8 if key.version == dm_preprocess::regions::FRAGMENT_VERSION => {
            for entry in dm_cache::decode_variants(bytes)? {
                dm_preprocess::regions::FragmentRecord::from_bytes(entry)?;
            }
            Ok(())
        }
        _ => Err("unsupported compiler memo stage/version".into()),
    }
}
pub fn run(project: &Path) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let cache = dm_cache::Cache::user_default(dm_cache::Limits::default())?;
    let now = SystemTime::now();
    let result = cache.evict_older_than(now, Duration::from_secs(14 * 86400), validate)?;
    let store = crate::publish::PairStore::open(crate::publish::default_store_path(project)?)?;
    let pairs = store.evict_to_budget(now, pair_max_age(), pair_budget_bytes())?;
    Ok(serde_json::json!({"cache":format!("{result:?}"),"outputs":format!("{pairs:?}")}))
}

const DEFAULT_PAIR_BUDGET_GB: u64 = 8;
const DEFAULT_PAIR_MAX_AGE_DAYS: u64 = 7;
/// Byte cap of one published-pair store (`DMB_PAIR_BUDGET_GB`, default 8, `0` disables the size cap).
pub fn pair_budget_bytes() -> Option<u64> {
    let gb = std::env::var("DMB_PAIR_BUDGET_GB")
        .ok()
        .and_then(|text| text.parse::<u64>().ok())
        .unwrap_or(DEFAULT_PAIR_BUDGET_GB);
    (gb > 0).then(|| gb.saturating_mul(1_000_000_000))
}
/// Age cap of unprotected pairs (`DMB_PAIR_MAX_AGE_DAYS`, default 7).
pub fn pair_max_age() -> Duration {
    let days = std::env::var("DMB_PAIR_MAX_AGE_DAYS")
        .ok()
        .and_then(|text| text.parse::<u64>().ok())
        .filter(|days| *days > 0)
        .unwrap_or(DEFAULT_PAIR_MAX_AGE_DAYS);
    Duration::from_secs(days * 86400)
}
/// The per-machine pair stores a build can publish into without `--output-store`: `%LOCALAPPDATA%/dmbd/pairs` and
/// `<drive>:/dq-cache/dmbd/pairs` (and the legacy `<drive>:/.dmbd/pairs`) on each drive (see `publish::default_store_path`). Only existing directories are returned.
pub fn known_pair_stores() -> Vec<std::path::PathBuf> {
    let mut stores = Vec::new();
    #[cfg(windows)]
    {
        if let Some(local) = std::env::var_os("LOCALAPPDATA") {
            stores.push(std::path::PathBuf::from(local).join("dmbd/pairs"));
        }
        for letter in b'A'..=b'Z' {
            stores.push(std::path::PathBuf::from(format!("{}:/dq-cache/dmbd/pairs", letter as char)));
            // Legacy drive-root location, still swept so old pairs age out.
            stores.push(std::path::PathBuf::from(format!("{}:/.dmbd/pairs", letter as char)));
        }
    }
    stores.retain(|store| store.join("pairs").is_dir() && store.join("sessions").is_dir());
    stores
}
/// One age-and-size pass over every known pair store; returns one log line per store. Failures are reported, never raised.
pub fn evict_known_pair_stores() -> Vec<String> {
    let now = SystemTime::now();
    known_pair_stores()
        .into_iter()
        .map(|root| match crate::publish::PairStore::open(&root) {
            Ok(store) => match store.evict_to_budget(now, pair_max_age(), pair_budget_bytes()) {
                Ok(result) => format!("dmbd pair store {}: {result:?}", root.display()),
                Err(error) => format!("dmbd pair store {}: pass skipped: {error}", root.display()),
            },
            Err(error) => format!("dmbd pair store {}: not opened: {error}", root.display()),
        })
        .collect()
}

/// Bytes written to the shared file cache or a pair store by this process since the last budget pass.
static WRITTEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static PASS_RUNNING: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
const DEFAULT_PASS_WRITE_MB: u64 = 1024;
/// Written bytes after which a budget pass runs (`DMB_CACHE_PASS_WRITE_MB`, default 1024; `0` disables the amortized pass).
pub fn pass_threshold_bytes() -> Option<u64> {
    let mb = std::env::var("DMB_CACHE_PASS_WRITE_MB")
        .ok()
        .and_then(|text| text.parse::<u64>().ok())
        .unwrap_or(DEFAULT_PASS_WRITE_MB);
    (mb > 0).then(|| mb.saturating_mul(1_000_000))
}
/// Register this process's writes with the budget: called at startup so every cache write counts.
pub fn install_write_accounting() {
    dm_cache::set_write_observer(note_written);
}
/// Count `bytes` newly stored in a capped cache; once `pass_threshold_bytes` accumulate, one detached pass enforces every cap.
pub fn note_written(bytes: u64) {
    use std::sync::atomic::Ordering::SeqCst;
    let total = WRITTEN.fetch_add(bytes, SeqCst).saturating_add(bytes);
    let Some(threshold) = pass_threshold_bytes() else { return };
    if total < threshold || PASS_RUNNING.compare_exchange(false, true, SeqCst, SeqCst).is_err() {
        return;
    }
    WRITTEN.store(0, SeqCst);
    let spawned = std::thread::Builder::new().name("dmbd-cache-amortized".into()).spawn(move || {
        eprintln!("dmbd cache budget (after {total} bytes written): {}", crate::daemon::cache_gc_once());
        PASS_RUNNING.store(false, SeqCst);
    });
    if spawned.is_err() {
        PASS_RUNNING.store(false, SeqCst);
    }
}
/// A one-shot process that wrote to a capped cache runs one last pass before it exits, so no short-lived compile can leave the
/// stores over their caps. Waits for an amortized pass already in flight.
pub fn finish_process() {
    use std::sync::atomic::Ordering::SeqCst;
    while PASS_RUNNING.load(SeqCst) {
        std::thread::sleep(Duration::from_millis(50));
    }
    if WRITTEN.swap(0, SeqCst) > 0 {
        eprintln!("dmbd cache budget (at exit): {}", crate::daemon::cache_gc_once());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering::SeqCst;

    #[test]
    fn writes_below_the_threshold_only_accumulate_and_the_default_is_one_gigabyte() {
        assert_eq!(pass_threshold_bytes(), Some(1_024_000_000));
        let before = WRITTEN.load(SeqCst);
        note_written(1000);
        assert!(WRITTEN.load(SeqCst) >= before.min(1000));
        assert!(!PASS_RUNNING.load(SeqCst));
    }
}
