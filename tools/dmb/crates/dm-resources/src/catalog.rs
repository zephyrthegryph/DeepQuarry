//! Payload-free captured resource facts. Restoring a record requires its exact
//! previously issued identity; asset freshness and archive authentication are
//! caller responsibilities, never inferred from these metadata alone.
use crate::native_resolver::{
    CapturedResourceLookup, CapturedResourceOutcome, CapturedSearchContext, NativeResourceRecord,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
    path::PathBuf,
};
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AliasRecord {
    pub name: String,
    pub disk_path: PathBuf,
    pub facts: NativeResourceRecord,
}
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct CatalogRecord {
    pub version: u32,
    pub aliases: Vec<AliasRecord>,
    pub contexts: Vec<Vec<u8>>,
    pub lookups: Vec<CapturedResourceLookup>,
}
#[derive(Clone, Debug)]
pub struct ResourceCatalog {
    record: CatalogRecord,
    identity: u128,
}
fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
impl ResourceCatalog {
    pub(crate) fn issued(
        aliases: Vec<AliasRecord>,
        contexts: Vec<Vec<u8>>,
        lookups: Vec<CapturedResourceLookup>,
    ) -> Self {
        let record = CatalogRecord {
            version: 1,
            aliases,
            contexts,
            lookups,
        };
        let identity = xxhash_rust::xxh3::xxh3_128(
            &serde_json::to_vec(&record).expect("resource catalog serialization"),
        );
        Self { record, identity }
    }
    pub fn identity(&self) -> u128 {
        self.identity
    }
    pub fn record(&self) -> &CatalogRecord {
        &self.record
    }
    pub fn restore(record: CatalogRecord, issued_identity: u128) -> io::Result<Self> {
        let bytes = serde_json::to_vec(&record).map_err(io::Error::other)?;
        if bytes.len() > 32 * 1024 * 1024
            || xxhash_rust::xxh3::xxh3_128(&bytes) != issued_identity
            || record.version != 1
        {
            return Err(invalid("resource catalog identity/version differs"));
        }
        let mut aliases = BTreeSet::new();
        let mut contents = BTreeMap::new();
        let mut runtime = BTreeMap::new();
        for alias in &record.aliases {
            crate::validate_archive_name(&alias.name)?;
            let facts = &alias.facts;
            if facts.alias != dm_ir::SymbolId::of(&alias.name) || !aliases.insert(facts.alias) {
                return Err(invalid("invalid/repeated resource catalog alias"));
            }
            if contents
                .insert(facts.content, facts.payload_len)
                .is_some_and(|previous| previous != facts.payload_len)
                || runtime
                    .insert(facts.runtime_content_id, (facts.content, facts.payload_len))
                    .is_some_and(|previous| previous != (facts.content, facts.payload_len))
            {
                return Err(invalid("resource catalog content/runtime collision"));
            }
        }
        let mut contexts = BTreeSet::new();
        for bytes in &record.contexts {
            if !contexts.insert(CapturedSearchContext::new(bytes.clone()).identity()) {
                return Err(invalid("repeated resource search context"));
            }
        }
        let mut lookups = BTreeMap::new();
        for lookup in &record.lookups {
            if !contexts.contains(&lookup.search_context)
                || matches!(lookup.outcome,CapturedResourceOutcome::Found(index) if index>=record.aliases.len())
            {
                return Err(invalid("resource catalog lookup outside captured domain"));
            }
            if lookups
                .insert((&lookup.path, lookup.search_context), lookup.outcome)
                .is_some()
            {
                return Err(invalid("repeated resource catalog lookup"));
            }
        }
        Ok(Self {
            record,
            identity: issued_identity,
        })
    }
}
/// Link payload meaning is exact captured content identity, runtime ID and
/// length. Archive alias/kind order belongs to output rows, not this shared key.
pub fn binding_bytes(facts: &NativeResourceRecord) -> Vec<u8> {
    let mut bytes = b"byond-resource-content-v1\0".to_vec();
    bytes.extend_from_slice(&facts.content.to_le_bytes());
    bytes.extend_from_slice(&facts.runtime_content_id.to_le_bytes());
    bytes.extend_from_slice(&(facts.payload_len as u64).to_le_bytes());
    bytes
}
