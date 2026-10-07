//! Explicit maintenance uses the same typed admission boundaries as reuse.
use std::{path::Path, time::{Duration, SystemTime}};
fn validate(key: dm_cache::RecordKey, bytes: &[u8], _: &[(u64, &[u8])]) -> Result<(), String> {
    use dm_preprocess::regions::{DirectiveRecord, ExpansionRecord, DIRECTIVE_VERSION, EXPANSION_VERSION};
    match key.stage {
        1 if key.version == EXPANSION_VERSION => {
            for entry in dm_cache::decode_variants(bytes)? { ExpansionRecord::from_bytes(entry)?; }
            Ok(())
        }
        2 if key.version == crate::lowering_memo::PROCEDURE_VERSION => {
            for entry in dm_cache::decode_variants(bytes)? { crate::lowering_memo_wire::validate(entry)?; }
            Ok(())
        }
        3 => crate::map_memo::MapMemo::validate_cache_payload(key.version, bytes),
        4 if key.version == DIRECTIVE_VERSION => {
            for entry in dm_cache::decode_variants(bytes)? { DirectiveRecord::from_bytes(entry)?; }
            Ok(())
        }
        _ => Err("unsupported compiler memo stage/version".into()),
    }
}
pub fn run(project: &Path) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let cache = dm_cache::Cache::user_default(dm_cache::Limits::default())?;
    let now = SystemTime::now();
    let result = cache.compact_leased(now, Duration::from_secs(14 * 86400), validate)?;
    let store = crate::publish::PairStore::open(crate::publish::default_store_path(project)?)?;
    let pairs = store.evict(now, Duration::from_secs(7 * 86400))?;
    Ok(serde_json::json!({"cache":format!("{result:?}"),"outputs":format!("{pairs:?}")}))
}
