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

#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum CapturedResourceOutcome {
    /// Ordinal in the captured ResourceSet, not a BYOND table ID.
    Found(usize),
    /// Discovery checked the complete qualified search and found no resource.
    Missing,
    /// Discovery cannot answer this request with its captured data.
    Unsupported,
}
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct CapturedResourceLookup {
    pub path: String,
    pub search_context: u128,
    pub outcome: CapturedResourceOutcome,
}

/// Ordered aliases retain archive insertion and first-kind decisions separately
/// from search lookup. Equal content never merges distinct authored aliases.
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct NativeResourceRecord {
    pub alias: SymbolId,
    pub content: u128,
    pub runtime_content_id: u32,
    pub kind: u8,
    pub payload_len: usize,
}

pub struct NativeResourceResolver<R> {
    resource_domain: std::sync::OnceLock<u128>,
    tree: R,
    symbols: Arc<SymbolTable>,
    resources: Option<ResourceSet>,
    aliases: Vec<(String, std::path::PathBuf)>,
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
        Self::from_shared_symbols(
            tree,
            Arc::new(tree_symbols.clone()),
            resources,
            contexts,
            lookups,
        )
    }
    /// Immutable source dictionary plus a collision-checked resource delta.
    /// Resource metadata remains private and is validated before publication.
    pub fn from_shared_symbols(
        tree: R,
        tree_symbols: Arc<SymbolTable>,
        resources: ResourceSet,
        contexts: impl IntoIterator<Item = CapturedSearchContext>,
        lookups: impl IntoIterator<Item = CapturedResourceLookup>,
    ) -> io::Result<Self> {
        let mut symbols = SymbolTable::overlay(tree_symbols);
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
            let digest: [u8; 32] = if payload.len() == input.named.shared_data().len() {
                input.named.shared_data().sha256()
            } else {
                Sha256::digest(payload).into()
            };
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
            resource_domain: std::sync::OnceLock::new(),
            tree,
            symbols: Arc::new(symbols),
            aliases: resources
                .inputs
                .iter()
                .map(|input| (input.archive_name.clone(), input.disk_path.clone()))
                .collect(),
            resources: Some(resources),
            ordered,
            contexts: captured_contexts,
            lookups: captured_lookups,
        })
    }
    pub fn ordered_resources(&self) -> &[NativeResourceRecord] {
        &self.ordered
    }
    /// Release capture payloads after archive projection. All already-validated
    /// qualified answers and ordered alias facts remain unchanged.
    pub fn into_metadata(mut self) -> Self {
        self.resources = None;
        self
    }
    pub fn resources(&self) -> Option<&ResourceSet> {
        self.resources.as_ref()
    }
    /// Issue payload-free facts only after the normal constructor validated
    /// actual asset bytes. Metadata hosts retain the same already-issued facts.
    pub fn catalog(&self) -> crate::catalog::ResourceCatalog {
        let mut contexts = self
            .contexts
            .values()
            .map(|bytes| bytes.to_vec())
            .collect::<Vec<_>>();
        contexts.sort();
        let mut lookups = self
            .lookups
            .iter()
            .map(|((path, context), outcome)| CapturedResourceLookup {
                path: self
                    .symbols
                    .text(*path)
                    .expect("validated resource spelling")
                    .to_owned(),
                search_context: *context,
                outcome: *outcome,
            })
            .collect::<Vec<_>>();
        lookups.sort_by(|left, right| {
            (&left.path, left.search_context).cmp(&(&right.path, right.search_context))
        });
        crate::catalog::ResourceCatalog::issued(
            self.aliases
                .iter()
                .zip(&self.ordered)
                .map(|((name, path), facts)| crate::catalog::AliasRecord {
                    name: name.clone(),
                    disk_path: path.clone(),
                    facts: facts.clone(),
                })
                .collect(),
            contexts,
            lookups,
        )
    }
    /// No asset bytes or filesystem access are required. The caller must use a
    /// catalog restored from authenticated session and validated asset facts.
    pub fn from_catalog(
        tree: R,
        tree_symbols: Arc<SymbolTable>,
        catalog: &crate::catalog::ResourceCatalog,
    ) -> io::Result<Self> {
        let record = catalog.record();
        let mut symbols = SymbolTable::overlay(tree_symbols);
        let mut contexts = HashMap::new();
        for bytes in &record.contexts {
            let context = CapturedSearchContext::new(bytes.clone());
            contexts.insert(context.identity(), Arc::from(bytes.as_slice()));
        }
        let mut ordered = Vec::new();
        let mut aliases = Vec::new();
        for alias in &record.aliases {
            symbols
                .intern(&alias.name)
                .map_err(|error| invalid(error.to_string()))?;
            ordered.push(alias.facts.clone());
            aliases.push((alias.name.clone(), alias.disk_path.clone()));
        }
        let mut lookups = HashMap::new();
        for lookup in &record.lookups {
            let path = symbols
                .intern(&lookup.path)
                .map_err(|error| invalid(error.to_string()))?;
            lookups.insert((path, lookup.search_context), lookup.outcome);
        }
        Ok(Self {
            resource_domain: std::sync::OnceLock::new(),
            tree,
            symbols: Arc::new(symbols),
            resources: None,
            aliases,
            ordered,
            contexts,
            lookups,
        })
    }
    pub fn symbols(&self) -> &SymbolTable {
        &self.symbols
    }
    pub fn shared_symbols(&self) -> Arc<SymbolTable> {
        Arc::clone(&self.symbols)
    }
    pub fn tree(&self) -> &R {
        &self.tree
    }
}
impl<R: Resolver> Resolver for NativeResourceResolver<R> {
    fn domain_version(&self, domain: dm_ir::ReadDomain) -> Option<u128> {
        if domain != dm_ir::ReadDomain::ResourceSearch {
            return self.tree.domain_version(domain);
        }
        Some(*self.resource_domain.get_or_init(|| {
            let mut hash = xxhash_rust::xxh3::Xxh3::new();
            hash.update(b"dm-resource-answer-domain-v1\0");
            let mut contexts: Vec<_> = self.contexts.iter().collect();
            contexts.sort_by_key(|(id, _)| **id);
            hash.update(&(contexts.len() as u64).to_le_bytes());
            for (id, bytes) in contexts {
                hash.update(&id.to_le_bytes());
                hash.update(&(bytes.len() as u64).to_le_bytes());
                hash.update(bytes);
            }
            let mut lookups: Vec<_> = self.lookups.iter().collect();
            lookups.sort_by_key(|(key, _)| **key);
            hash.update(&(lookups.len() as u64).to_le_bytes());
            for ((path, context), outcome) in lookups {
                hash.update(&path.bits().to_le_bytes());
                hash.update(&context.to_le_bytes());
                match outcome {
                    CapturedResourceOutcome::Missing => hash.update(&[0]),
                    CapturedResourceOutcome::Unsupported => hash.update(&[1]),
                    CapturedResourceOutcome::Found(index) => {
                        hash.update(&[2]);
                        let record = &self.ordered[*index];
                        hash.update(&record.alias.bits().to_le_bytes());
                        hash.update(&record.content.to_le_bytes());
                    }
                }
            }
            hash.digest128()
        }))
    }

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
                        .unwrap()
                        .into(),
                    }
                })
                .collect(),
            fingerprint: [0; 32],
        }
    }
    #[test]
    fn immutable_digest_memo_does_not_admit_forged_digest_or_full_hash_for_prefix() {
        let admit = |resources| {
            NativeResourceResolver::from_captured(
                Tree,
                &SymbolTable::default(),
                resources,
                std::iter::empty::<CapturedSearchContext>(),
                std::iter::empty::<CapturedResourceLookup>(),
            )
        };
        let mut forged = resources();
        let cached = forged.inputs[0].named.shared_data().sha256();
        assert_eq!(cached, forged.inputs[0].content_digest);
        forged.inputs[0].content_digest[0] ^= 1;
        assert!(admit(forged).is_err());

        let mut prefix = resources();
        prefix.inputs.truncate(1);
        let input = &mut prefix.inputs[0];
        let full_digest = input.named.shared_data().sha256();
        input.named.declared_size = 4;
        input.named.id = byond_dmb::hash::nqcrc(u32::MAX, input.named.asset_bytes().unwrap());
        input.content_digest = Sha256::digest(input.named.asset_bytes().unwrap()).into();
        assert_ne!(input.content_digest, full_digest);
        assert!(admit(prefix.clone()).is_ok());
        prefix.inputs[0].content_digest = full_digest;
        assert!(admit(prefix).is_err());
    }

    #[test]
    fn resource_domain_invalidates_captured_negative_lookup() {
        // Context must be issued, including negative observations.
        let context = CapturedSearchContext::new(Arc::<[u8]>::from(&b"domain"[..]));
        let identity = context.identity();
        let build = |outcome| {
            NativeResourceResolver::from_captured(
                Tree,
                &SymbolTable::default(),
                resources(),
                [context.clone()],
                [CapturedResourceLookup {
                    path: "literal.txt".into(),
                    search_context: identity,
                    outcome,
                }],
            )
            .unwrap()
        };
        let missing = build(CapturedResourceOutcome::Missing);
        let found = build(CapturedResourceOutcome::Found(0));
        assert_ne!(
            missing.domain_version(dm_ir::ReadDomain::ResourceSearch),
            found.domain_version(dm_ir::ReadDomain::ResourceSearch)
        );
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
        let catalog = host.catalog();
        let restored =
            crate::catalog::ResourceCatalog::restore(catalog.record().clone(), catalog.identity())
                .unwrap();
        let metadata =
            NativeResourceResolver::from_catalog(Tree, Arc::new(SymbolTable::default()), &restored)
                .unwrap();
        assert_eq!(
            host.domain_version(dm_ir::ReadDomain::ResourceSearch),
            metadata.domain_version(dm_ir::ReadDomain::ResourceSearch)
        );
        assert!(host
            .domain_version(dm_ir::ReadDomain::ResourceSearch)
            .is_some());
        assert!(metadata.resources().is_none());
        for context in [a, b, 0] {
            assert_eq!(
                metadata.resolve(query(context)),
                host.resolve(query(context))
            );
        }
        assert_eq!(metadata.ordered_resources(), host.ordered_resources());
        assert_eq!(metadata.catalog().identity(), catalog.identity());
        let host = host.into_metadata();
        assert!(host.resources().is_none());
        for context in [a, b, 0] {
            assert_eq!(
                host.resolve(query(context)),
                metadata.resolve(query(context))
            );
        }

        let mut tampered = catalog.record().clone();
        tampered.aliases[0].facts.payload_len += 1;
        assert!(crate::catalog::ResourceCatalog::restore(tampered, catalog.identity()).is_err());
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
