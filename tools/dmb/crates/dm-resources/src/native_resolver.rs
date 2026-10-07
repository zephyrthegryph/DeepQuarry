//! Immutable resource-search answers composed with a declaration resolver.
//!
//! Discovery supplies complete qualified outcomes from one captured snapshot.
//! This module neither discovers FILE_DIR policy nor reads the filesystem in
//! `resolve`. Unrecorded queries are Unsupported, never invented negative reads.

use crate::{validate_archive_name, ResourceSet};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId, SymbolTable};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io;
use std::sync::Arc;
use xxhash_rust::xxh3::xxh3_128;

/// Opaque exact search domain supplied by discovery. Bytes must include every
/// ordered search input (including source scope and negative candidate policy).
/// This host makes no assumptions about their serialization or FILE_DIR rules.
#[derive(Clone, Debug)]
pub struct CapturedSearchContext {
    identity: u128,
    bytes: Arc<[u8]>,
}
impl CapturedSearchContext {
    pub fn new(bytes: impl Into<Arc<[u8]>>) -> Self {
        let bytes = bytes.into();
        // Domain/version separate these identities from content fingerprints.
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(b"dm-resource-search-context-v1\0");
        hash.update(&(bytes.len() as u64).to_le_bytes());
        hash.update(&bytes);
        Self {
            identity: hash.digest128(),
            bytes,
        }
    }
    pub fn identity(&self) -> u128 {
        self.identity
    }
    pub fn bytes(&self) -> &[u8] {
        &self.bytes
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CapturedResourceOutcome {
    /// Ordinal in the captured ResourceSet, not a BYOND table ID.
    Found(usize),
    /// Discovery checked the complete qualified search and found no resource.
    Missing,
    /// Discovery cannot answer this request with its captured data.
    Unsupported,
}
#[derive(Clone, Debug)]
pub struct CapturedResourceLookup {
    pub path: String,
    pub search_context: u128,
    pub outcome: CapturedResourceOutcome,
}

/// Ordered aliases retain archive insertion and first-kind decisions separately
/// from search lookup. Equal content never merges distinct authored aliases.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct NativeResourceRecord {
    pub alias: SymbolId,
    pub content: u128,
    pub runtime_content_id: u32,
    pub kind: u8,
    pub payload_len: usize,
}

pub struct NativeResourceResolver<R> {
    tree: R,
    symbols: SymbolTable,
    resources: ResourceSet,
    ordered: Vec<NativeResourceRecord>,
    contexts: HashMap<u128, Arc<[u8]>>,
    lookups: HashMap<(SymbolId, u128), CapturedResourceOutcome>,
}

fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message.into())
}

impl<R: Resolver> NativeResourceResolver<R> {
    /// Seeds collision checking from the actual declaration snapshot's symbols.
    /// The caller must pass the same tree snapshot whose resolver is composed.
    pub fn from_captured(
        tree: R,
        tree_symbols: &SymbolTable,
        resources: ResourceSet,
        contexts: impl IntoIterator<Item = CapturedSearchContext>,
        lookups: impl IntoIterator<Item = CapturedResourceLookup>,
    ) -> io::Result<Self> {
        let mut symbols = tree_symbols.clone();
        let mut ordered = Vec::with_capacity(resources.inputs.len());
        let mut aliases = HashMap::new();
        let mut content_rows = HashMap::<u128, usize>::new();
        for input in &resources.inputs {
            validate_archive_name(&input.archive_name)?;
            if input.named.name != input.archive_name.as_bytes() {
                return Err(invalid(
                    "captured resource name disagrees with archive alias",
                ));
            }
            let payload = input.named.asset_bytes()?;
            let digest: [u8; 32] = Sha256::digest(payload).into();
            if digest != input.content_digest {
                return Err(invalid(
                    "captured resource payload disagrees with content digest",
                ));
            }
            if input.named.content_id()? != input.named.id {
                return Err(invalid(
                    "captured resource payload disagrees with runtime content ID",
                ));
            }
            let alias = symbols
                .intern(&input.archive_name)
                .map_err(|e| invalid(e.to_string()))?;
            if aliases.insert(alias, ordered.len()).is_some() {
                return Err(invalid("captured resource set repeats an archive alias"));
            }
            let content = xxh3_128(payload);
            if let Some(&previous) = content_rows.get(&content) {
                if resources.inputs[previous].named.asset_bytes()? != payload {
                    return Err(invalid("resource payload content hash collision"));
                }
            } else {
                content_rows.insert(content, ordered.len());
            }
            ordered.push(NativeResourceRecord {
                alias,
                content,
                runtime_content_id: input.named.id,
                kind: input.named.kind,
                payload_len: payload.len(),
            });
        }
        let mut captured_contexts = HashMap::<u128, Arc<[u8]>>::new();
        for context in contexts {
            if let Some(previous) = captured_contexts.get(&context.identity) {
                if previous.as_ref() != context.bytes.as_ref() {
                    return Err(invalid("resource search context hash collision"));
                }
            } else {
                captured_contexts.insert(context.identity, context.bytes);
            }
        }
        let mut captured_lookups = HashMap::new();
        for lookup in lookups {
            if !captured_contexts.contains_key(&lookup.search_context) {
                return Err(invalid("resource lookup has an uncaptured search context"));
            }
            if matches!(lookup.outcome, CapturedResourceOutcome::Found(index) if index >= ordered.len())
            {
                return Err(invalid("resource lookup points outside captured aliases"));
            }
            let path = symbols
                .intern(&lookup.path)
                .map_err(|e| invalid(e.to_string()))?;
            let key = (path, lookup.search_context);
            if let Some(previous) = captured_lookups.insert(key, lookup.outcome) {
                if previous != lookup.outcome {
                    return Err(invalid(
                        "conflicting resource lookup outcomes in one snapshot",
                    ));
                }
            }
        }
        Ok(Self {
            tree,
            symbols,
            resources,
            ordered,
            contexts: captured_contexts,
            lookups: captured_lookups,
        })
    }
    pub fn ordered_resources(&self) -> &[NativeResourceRecord] {
        &self.ordered
    }
    pub fn resources(&self) -> &ResourceSet {
        &self.resources
    }
    pub fn symbols(&self) -> &SymbolTable {
        &self.symbols
    }
    pub fn tree(&self) -> &R {
        &self.tree
    }
}
impl<R: Resolver> Resolver for NativeResourceResolver<R> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::ResourceIn {
                path,
                search_context,
            } => {
                if !self.contexts.contains_key(&search_context) {
                    return ResolvedMeaning::Unsupported(query);
                }
                match self.lookups.get(&(path, search_context)) {
                    Some(CapturedResourceOutcome::Found(index)) => {
                        let record = &self.ordered[*index];
                        ResolvedMeaning::Resource {
                            path: record.alias,
                            content: record.content,
                        }
                    }
                    Some(CapturedResourceOutcome::Missing) => ResolvedMeaning::Missing,
                    Some(CapturedResourceOutcome::Unsupported) | None => {
                        ResolvedMeaning::Unsupported(query)
                    }
                }
            }
            // An unqualified request has no captured search-domain authority.
            ResolveQuery::Resource(_) => ResolvedMeaning::Unsupported(query),
            other => self.tree.resolve(other),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ResourceInput;
    use byond_dmb::rsc::NamedResource;
    struct Tree;
    impl Resolver for Tree {
        fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
            match query {
                ResolveQuery::Type(path) => ResolvedMeaning::Symbol(path),
                _ => ResolvedMeaning::Unsupported(query),
            }
        }
    }
    fn resources() -> ResourceSet {
        ResourceSet {
            inputs: ["z.txt", "a.txt"]
                .into_iter()
                .map(|alias| {
                    let payload = b"same exact bytes".to_vec();
                    ResourceInput {
                        archive_name: alias.into(),
                        disk_path: alias.into(),
                        content_digest: Sha256::digest(&payload).into(),
                        named: NamedResource::from_data(
                            0,
                            alias.as_bytes().to_vec(),
                            payload,
                            0,
                            0,
                        )
                        .unwrap(),
                    }
                })
                .collect(),
            fingerprint: [0; 32],
        }
    }
    #[test]
    fn qualified_outcomes_and_alias_order_are_independent() {
        let first = CapturedSearchContext::new(Arc::<[u8]>::from(&b"first domain"[..]));
        let second = CapturedSearchContext::new(Arc::<[u8]>::from(&b"second domain"[..]));
        let a = first.identity();
        let b = second.identity();
        let host = NativeResourceResolver::from_captured(
            Tree,
            &SymbolTable::default(),
            resources(),
            [first, second],
            [
                CapturedResourceLookup {
                    path: "literal.txt".into(),
                    search_context: a,
                    outcome: CapturedResourceOutcome::Found(1),
                },
                CapturedResourceLookup {
                    path: "literal.txt".into(),
                    search_context: b,
                    outcome: CapturedResourceOutcome::Missing,
                },
            ],
        )
        .unwrap();
        let query = |context| ResolveQuery::ResourceIn {
            path: SymbolId::of("literal.txt"),
            search_context: context,
        };
        assert_eq!(
            host.resolve(query(a)),
            ResolvedMeaning::Resource {
                path: SymbolId::of("a.txt"),
                content: xxh3_128(b"same exact bytes")
            }
        );
        assert_eq!(host.resolve(query(b)), ResolvedMeaning::Missing);
        assert_eq!(
            host.resolve(query(0)),
            ResolvedMeaning::Unsupported(query(0))
        );
        assert_eq!(
            host.ordered_resources()
                .iter()
                .map(|r| r.alias)
                .collect::<Vec<_>>(),
            [SymbolId::of("z.txt"), SymbolId::of("a.txt")]
        );
        assert_eq!(
            host.resolve(ResolveQuery::Type(SymbolId::of("/datum"))),
            ResolvedMeaning::Symbol(SymbolId::of("/datum"))
        );
    }
    #[test]
    fn invalid_capture_never_mints_answers() {
        let context = CapturedSearchContext::new(Arc::<[u8]>::from(&b"domain"[..]));
        let id = context.identity();
        let invalid = CapturedResourceLookup {
            path: "x".into(),
            search_context: id,
            outcome: CapturedResourceOutcome::Found(2),
        };
        assert!(NativeResourceResolver::from_captured(
            Tree,
            &SymbolTable::default(),
            resources(),
            [context],
            [invalid]
        )
        .is_err());
        let mut corrupt = resources();
        corrupt.inputs[0].content_digest = [0; 32];
        assert!(NativeResourceResolver::from_captured(
            Tree,
            &SymbolTable::default(),
            corrupt,
            [],
            []
        )
        .is_err());
    }
}
