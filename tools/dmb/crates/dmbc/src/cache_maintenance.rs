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
/// `<drive>:/.dmbd/pairs` on each drive (see `publish::default_store_path`). Only existing directories are returned.
pub fn known_pair_stores() -> Vec<std::path::PathBuf> {
    let mut stores = Vec::new();
    #[cfg(windows)]
    {
        if let Some(local) = std::env::var_os("LOCALAPPDATA") {
            stores.push(std::path::PathBuf::from(local).join("dmbd/pairs"));
        }
        for letter in b'A'..=b'Z' {
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
