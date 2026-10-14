//! Current map executable identity, including exact debug source provenance.
use dm_tree::{frontend::ColdFrontend, maps::MapPlan};
use std::sync::Arc;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Document {
    pub identity: u128,
    pub semantic_path: Arc<str>,
    pub source: Arc<str>,
    pub model: Arc<[u8]>,
}
pub fn capture(frontend: &ColdFrontend, map: &MapPlan) -> Result<Document, String> {
    let include = frontend
        .plan
        .occurrences
        .get(map.captured.include_occurrence as usize)
        .ok_or("map include occurrence absent")?;
    if include.path != map.captured.path {
        return Err("map include path differs from capture".into());
    }
    let model: Arc<[u8]> = map.model.canonical_bytes().into();
    if xxhash_rust::xxh3::xxh3_128(&model) != map.semantic_identity
        || xxhash_rust::xxh3::xxh3_128(map.captured.source.as_bytes()) != map.source_identity
    {
        return Err("map capture identity differs from exact current bytes".into());
    }
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    hash.update(b"byond-map-executable-document-v1\0");
    for bytes in [
        model.as_ref(),
        include.semantic_path.as_bytes(),
        map.captured.source.as_bytes(),
    ] {
        hash.update(&(bytes.len() as u64).to_le_bytes());
        hash.update(bytes);
    }
    Ok(Document {
        identity: hash.digest128(),
        semantic_path: include.semantic_path.clone(),
        source: map.captured.source.clone(),
        model,
    })
}
