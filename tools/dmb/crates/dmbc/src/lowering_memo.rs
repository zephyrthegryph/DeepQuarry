//! Exact request-local lowering variants. No tree arena or output table is cached.
//! Every hit rechecks recorded meanings; an unchanged domain version is only an
//! optional future optimization, never an authorization to skip a fresh check.
use dm_ir::{ReadDomain, ResolveQuery, ResolvedMeaning, Resolver};
use std::collections::BTreeMap;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc, Mutex,
};
#[derive(Default)]
pub struct MemoCounts {
    pub resident_hits: AtomicU64,
    pub disk_hits: AtomicU64,
    pub recomputed: AtomicU64,
    pub unsupported_disk: AtomicU64,
    pub pending_dropped: AtomicU64,
    pub resident_dropped: AtomicU64,
}
const PENDING_LIMIT: usize = 64 * 1024 * 1024;
const RESIDENT_LIMIT: usize = 8 * 1024 * 1024;
#[derive(Clone, Copy)]
pub struct MemoLimits {
    pub pending_bytes: usize,
    pub resident_bytes: usize,
}
impl Default for MemoLimits {
    fn default() -> Self {
        Self {
            pending_bytes: PENDING_LIMIT,
            resident_bytes: RESIDENT_LIMIT,
        }
    }
}
#[derive(Default)]
struct Pending {
    records: BTreeMap<dm_cache::RecordKey, dm_cache::Record>,
    bytes: usize,
}

/// Caller-issued compiler/ABI/emission policy identity, never whole-tree identity.
pub struct ProcedureMemo {
    pub policy: u128,
    pub values: LoweringMemo<crate::lowering::LoweredUnit>,
    disk: Option<dm_cache::CacheSnapshot>,
    pending: Mutex<Pending>,
    pub counts: MemoCounts,
    limits: MemoLimits,
}
impl ProcedureMemo {
    pub fn new(policy: u128) -> Self {
        Self {
            policy,
            values: LoweringMemo::default(),
            disk: None,
            pending: Mutex::new(Pending::default()),
            counts: MemoCounts::default(),
            limits: MemoLimits::default(),
        }
    }
    pub fn with_disk(policy: u128, snapshot: dm_cache::CacheSnapshot) -> Self {
        Self::with_disk_limits(policy, snapshot, MemoLimits::default())
    }
    pub fn with_disk_limits(
        policy: u128,
        snapshot: dm_cache::CacheSnapshot,
        limits: MemoLimits,
    ) -> Self {
        Self {
            policy,
            values: LoweringMemo::with_limit(limits.resident_bytes),
            disk: Some(snapshot),
            pending: Mutex::new(Pending::default()),
            counts: MemoCounts::default(),
            limits,
        }
    }
    fn record_key(key: &[u8]) -> dm_cache::RecordKey {
        dm_cache::RecordKey {
            stage: 2,
            version: 2,
            content: xxhash_rust::xxh3::xxh3_128(key),
        }
    }
    fn disk_variants(&self, key: &[u8]) -> Vec<Vec<u8>> {
        let Some(snapshot) = &self.disk else {
            return Vec::new();
        };
        snapshot
            .get(Self::record_key(key), |bytes, _symbols| {
                let variants = dm_cache::decode_variants(bytes)?;
                for variant in variants {
                    crate::lowering_memo_wire::validate(&variant)?;
                }
                Ok(())
            })
            .and_then(|record| {
                dm_cache::decode_variants(record.payload)
                    .ok()
                    .map(|variants| variants.into_iter().map(<[u8]>::to_vec).collect())
            })
            .unwrap_or_default()
    }
    pub(crate) fn lookup_disk<R: Resolver>(
        &self,
        key: &[u8],
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        host: &R,
    ) -> Option<crate::lowering::LoweredUnit> {
        self.disk_variants(key)
            .into_iter()
            .rev()
            .find_map(|bytes| crate::lowering_memo_wire::decode(&bytes, key, frontend, body, host))
    }
    pub(crate) fn queue_disk(
        &self,
        key: &[u8],
        reads: &[ResolverRead],
        unit: &crate::lowering::LoweredUnit,
    ) {
        if self.disk.is_none() {
            return;
        }
        if self
            .pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .bytes
            >= self.limits.pending_bytes
        {
            self.counts.pending_dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        let Some(payload) = crate::lowering_memo_wire::encode(key, reads, unit) else {
            self.counts.unsupported_disk.fetch_add(1, Ordering::Relaxed);
            return;
        };
        self.queue_payload(key, payload);
    }
    pub(crate) fn executable<R: Resolver>(
        &self,
        key: &[u8],
        host: &R,
    ) -> Option<dm_codegen_byond::lower_resolver::ResolverProc> {
        let result = self
            .disk_variants(key)
            .into_iter()
            .rev()
            .find_map(|bytes| crate::lowering_memo_wire::decode_executable(&bytes, key, host));
        if result.is_some() {
            self.counts.disk_hits.fetch_add(1, Ordering::Relaxed);
        }
        result
    }
    pub(crate) fn remember_executable(
        &self,
        key: &[u8],
        reads: &[ResolverRead],
        code: &dm_codegen_byond::lower_resolver::ResolverProc,
    ) {
        self.counts.recomputed.fetch_add(1, Ordering::Relaxed);
        if self.disk.is_none() {
            return;
        }
        if self.pending_bytes() >= self.limits.pending_bytes {
            self.counts.pending_dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        match crate::lowering_memo_wire::encode_executable(key, reads, code) {
            Some(payload) => self.queue_payload(key, payload),
            None => {
                self.counts.unsupported_disk.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
    fn queue_payload(&self, key: &[u8], payload: Vec<u8>) {
        let record_key = Self::record_key(key);
        let previous = self.disk_variants(key);
        let mut pending = self
            .pending
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let mut variants = pending
            .records
            .get(&record_key)
            .and_then(|record| {
                dm_cache::decode_variants(&record.payload)
                    .ok()
                    .map(|variants| variants.into_iter().map(<[u8]>::to_vec).collect())
            })
            .unwrap_or(previous);
        if !variants.contains(&payload) {
            variants.push(payload);
        }
        if variants.len() > 4 {
            variants.remove(0);
        }
        let Ok(bytes) = dm_cache::encode_variants(&variants) else {
            self.counts.pending_dropped.fetch_add(1, Ordering::Relaxed);
            return;
        };
        let old = pending
            .records
            .get(&record_key)
            .map_or(0, |record| record.payload.len() + 128);
        // Include descriptor/framing/alignment headroom so the default 64MiB segment fits.
        let total = pending.bytes - old + bytes.len() + 128;
        if total.saturating_add(256) > self.limits.pending_bytes {
            self.counts.pending_dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        pending.bytes = total;
        pending.records.insert(
            record_key,
            dm_cache::Record {
                key: record_key,
                symbols: Vec::new(),
                payload: bytes.into(),
            },
        );
    }
    /// Publish once per build; never create one physical segment per procedure.
    pub fn take_pending(&self) -> Vec<dm_cache::Record> {
        std::mem::take(
            &mut *self
                .pending
                .lock()
                .unwrap_or_else(|error| error.into_inner()),
        )
        .records
        .into_values()
        .collect()
    }
    pub fn pending_bytes(&self) -> usize {
        self.pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .bytes
    }
    pub(crate) fn remember(
        &self,
        key: Vec<u8>,
        reads: Vec<ResolverRead>,
        unit: &crate::lowering::LoweredUnit,
    ) {
        if self.values.available_bytes() < 8192 {
            self.counts.resident_dropped.fetch_add(1, Ordering::Relaxed);
            return;
        }
        // Unsupported AST-bearing sidecars need their absolute occurrence until
        // a dedicated rebasing wire is implemented. Resident reuse checks it.
        let mut code_bytes =
            serde_json::to_vec(&unit.code.procedure).map_or(usize::MAX, |bytes| bytes.len());
        for helper in &unit.source_helpers {
            code_bytes = code_bytes.saturating_add(
                serde_json::to_vec(&helper.code.procedure).map_or(usize::MAX, |bytes| bytes.len()),
            );
        }
        for descriptor in unit.code.modified_instances.values() {
            code_bytes = code_bytes.saturating_add(descriptor.descriptor.canonical_bytes().len());
        }
        let read_bytes = reads
            .iter()
            .map(|read| read.answer.canonical_bytes().len())
            .sum::<usize>();
        let weight = code_bytes
            .saturating_add(read_bytes)
            .saturating_add(key.len())
            .saturating_mul(4)
            .saturating_add(8192);
        if !self
            .values
            .insert_with(key.into(), reads, weight, || unit.clone())
        {
            self.counts.resident_dropped.fetch_add(1, Ordering::Relaxed);
        }
    }
}

pub(crate) fn prepared_key(
    key: &mut Vec<u8>,
    prepared: &crate::procedure_policy::PreparedUnit,
    base: usize,
) -> Option<()> {
    let inputs = &prepared.inputs;
    let types = inputs.parameter_types.iter().collect::<BTreeMap<_, _>>();
    let bytes = serde_json::to_vec(&(
        inputs.procedure_identity,
        &inputs.current_proc_path,
        &inputs.current_type_path,
        &inputs.parameters,
        &inputs.parameter_type_flags,
        &inputs.parameter_value_sources,
        &inputs.parameter_defaults,
        types,
        &inputs.readonly_parameters,
        inputs.resource_search_context,
    ))
    .ok()?;
    key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
    key.extend_from_slice(&bytes);
    match &prepared.abi {
        None => key.push(0),
        Some(abi) => {
            key.push(1);
            let bytes = abi.canonical_bytes();
            key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
            key.extend_from_slice(&bytes);
        }
    }
    fn items(key: &mut Vec<u8>, values: &[dm_syntax::Item], base: usize) -> Option<()> {
        key.extend_from_slice(&(values.len() as u64).to_le_bytes());
        for item in values {
            key.push(match item.kind {
                dm_syntax::ItemKind::Type => 0,
                dm_syntax::ItemKind::Proc => 1,
                dm_syntax::ItemKind::Verb => 2,
                dm_syntax::ItemKind::Var => 3,
                dm_syntax::ItemKind::Statement => 4,
                dm_syntax::ItemKind::Unknown => 5,
            });
            key.extend_from_slice(&(item.header.len() as u64).to_le_bytes());
            key.extend_from_slice(item.header.as_bytes());
            for offset in [
                item.span.start,
                item.span.end,
                item.header_span.start,
                item.header_span.end,
            ] {
                key.extend_from_slice(&(offset.checked_sub(base)? as u64).to_le_bytes());
            }
            key.extend_from_slice(&(item.indent as u64).to_le_bytes());
            items(key, &item.children, base)?;
        }
        Some(())
    }
    items(key, &prepared.executable_body, base)?;
    Some(())
}

pub(crate) fn key(
    frontend: &dm_tree::frontend::ColdFrontend,
    body: &dm_tree::frontend::BodyOccurrence,
    policy: u128,
) -> Option<Vec<u8>> {
    let tree = &frontend.snapshot.tree;
    let member = tree.member(body.member)?;
    let owner = tree.type_node(member.owner)?.path;
    let source = frontend.expanded.text.get(body.expanded_span.range())?;
    let mut key = b"dmbc-procedure-memo-v2-debug\0".to_vec();
    key.extend_from_slice(&policy.to_le_bytes());
    key.extend_from_slice(&owner.bits().to_le_bytes());
    key.extend_from_slice(&member.name.bits().to_le_bytes());
    key.push(u8::from(member.kind == dm_tree::MemberKind::Verb));
    let occurrence = tree
        .override_chain(body.member)
        .iter()
        .filter(|id| {
            tree.member(**id).is_some_and(|node| {
                node.owner == member.owner && node.name == member.name && node.kind == member.kind
            })
        })
        .count()
        .checked_sub(1)?;
    key.extend_from_slice(&(occurrence as u64).to_le_bytes());
    fn part(key: &mut Vec<u8>, bytes: &[u8]) {
        key.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
        key.extend_from_slice(bytes);
    }
    part(
        &mut key,
        &member.metadata.procedure.as_ref()?.canonical_bytes(),
    );
    part(&mut key, source.as_bytes());
    // Only relative offsets and actual logical provenance enter the key. A
    // different include expanding before this file can move its arena position
    // without changing emitted debug paths/lines. Line/path changes still miss.
    for token in dm_syntax::lex_spans(source).tokens {
        let location = frontend.location(body.expanded_span.start + token.span.start)?;
        key.extend_from_slice(&(token.span.start as u64).to_le_bytes());
        part(&mut key, location.semantic_path.as_bytes());
        key.extend_from_slice(&(location.line as u64).to_le_bytes());
    }
    Some(key)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ResolverRead {
    pub domain: ReadDomain,
    pub query: ResolveQuery,
    pub answer: ResolvedMeaning,
}

pub struct RecordingResolver<'a, R: Resolver> {
    resolver: &'a R,
    reads: Mutex<BTreeMap<ResolveQuery, Vec<ResolverRead>>>,
}
impl<'a, R: Resolver> RecordingResolver<'a, R> {
    pub fn new(resolver: &'a R) -> Self {
        Self {
            resolver,
            reads: Mutex::new(BTreeMap::new()),
        }
    }
    pub fn reads(&self) -> Vec<ResolverRead> {
        self.reads
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .values()
            .flatten()
            .cloned()
            .collect()
    }
    /// These reads are mandatory even for bodies that use no inherited names.
    pub fn record_occurrence(&self, identity: dm_ir::ProcedureIdentity) {
        self.resolve(ResolveQuery::Ancestry(identity.owner));
        self.resolve(ResolveQuery::OverrideChain {
            owner: identity.owner,
            name: identity.name,
            verb: identity.verb,
        });
    }
}
impl<R: Resolver> Resolver for RecordingResolver<'_, R> {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let answer = self.resolver.resolve(query);
        let mut reads = self.reads.lock().unwrap_or_else(|error| error.into_inner());
        let answers = reads.entry(query).or_default();
        if !answers.iter().any(|read| read.answer == answer) {
            answers.push(ResolverRead {
                domain: query.domain(),
                query,
                answer: answer.clone(),
            });
        }
        answer
    }
}

#[derive(Clone)]
struct Variant<T> {
    key: Arc<[u8]>,
    reads: Arc<[ResolverRead]>,
    value: Arc<T>,
    weight: usize,
}
struct Resident<T> {
    buckets: BTreeMap<u128, Vec<Variant<T>>>,
    bytes: usize,
}

/// Hashes choose buckets only; exact key bytes and all semantic answers authorize
/// reuse. Variants are insertion ordered; the oldest of at most four is evicted.
pub struct LoweringMemo<T> {
    state: Mutex<Resident<T>>,
    limit: usize,
}
impl<T> Default for LoweringMemo<T> {
    fn default() -> Self {
        Self::with_limit(RESIDENT_LIMIT)
    }
}
impl<T> LoweringMemo<T> {
    pub fn with_limit(limit: usize) -> Self {
        Self {
            state: Mutex::new(Resident {
                buckets: BTreeMap::new(),
                bytes: 0,
            }),
            limit,
        }
    }
    pub fn admitted_bytes(&self) -> usize {
        self.state
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .bytes
    }
    pub fn available_bytes(&self) -> usize {
        self.limit.saturating_sub(self.admitted_bytes())
    }
}
impl<T: Send + Sync> LoweringMemo<T> {
    pub fn lookup<R: Resolver>(&self, key: &[u8], resolver: &R) -> Option<Arc<T>> {
        let hash = xxhash_rust::xxh3::xxh3_128(key);
        // Resolver work takes place outside the store lock, allowing parallel units.
        let candidates = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state
                .buckets
                .get(&hash)?
                .iter()
                .filter(|entry| entry.key.as_ref() == key)
                .map(|entry| (Arc::clone(&entry.reads), Arc::clone(&entry.value)))
                .collect::<Vec<_>>()
        };
        candidates.into_iter().rev().find_map(|(reads, value)| {
            reads
                .iter()
                .all(|read| {
                    resolver.resolve(read.query).canonical_bytes() == read.answer.canonical_bytes()
                })
                .then_some(value)
        })
    }
    pub fn insert(&self, key: Arc<[u8]>, reads: Vec<ResolverRead>, value: T) {
        let weight = key.len()
            + std::mem::size_of::<T>()
            + reads
                .iter()
                .map(|read| read.answer.canonical_bytes().len())
                .sum::<usize>();
        self.insert_with(key, reads, weight, || value);
    }
    fn insert_with(
        &self,
        key: Arc<[u8]>,
        reads: Vec<ResolverRead>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> bool {
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        let removed_weight = state
            .buckets
            .get(&hash)
            .and_then(|bucket| {
                (bucket.iter().filter(|entry| entry.key == key).count() >= 4).then(|| {
                    bucket
                        .iter()
                        .find(|entry| entry.key == key)
                        .map_or(0, |entry| entry.weight)
                })
            })
            .unwrap_or(0);
        if weight > self.limit
            || state
                .bytes
                .saturating_sub(removed_weight)
                .saturating_add(weight)
                > self.limit
        {
            return false;
        }
        let bucket = state.buckets.entry(hash).or_default();
        // A hash collision must not evict another exact key's independent variants.
        if bucket.iter().filter(|entry| entry.key == key).count() >= 4 {
            if let Some(index) = bucket.iter().position(|entry| entry.key == key) {
                // Removing a variant releases accounted storage below.
                let removed = bucket.remove(index);
                let removed_weight = removed.weight;
                bucket.push(Variant {
                    key,
                    reads: reads.into(),
                    value: Arc::new(create()),
                    weight,
                });
                state.bytes = state.bytes - removed_weight + weight;
                return true;
            }
        }
        bucket.push(Variant {
            key,
            reads: reads.into(),
            value: Arc::new(create()),
            weight,
        });
        state.bytes += weight;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Host(bool);
    impl Resolver for Host {
        fn resolve(&self, _query: ResolveQuery) -> ResolvedMeaning {
            if self.0 {
                ResolvedMeaning::Symbol(dm_ir::SymbolId::of("/datum/changed"))
            } else {
                ResolvedMeaning::Missing
            }
        }
    }
    #[test]
    fn negative_reads_invalidate_and_exact_keys_never_alias() {
        let memo = LoweringMemo::default();
        let recorder = RecordingResolver::new(&Host(false));
        recorder.resolve(ResolveQuery::GlobalVar(dm_ir::SymbolId::of("absent")));
        memo.insert(
            Arc::from(b"full-header-body".as_slice()),
            recorder.reads(),
            7u32,
        );
        assert_eq!(
            memo.lookup(b"full-header-body", &Host(false)).as_deref(),
            Some(&7)
        );
        assert!(memo.lookup(b"full-header-body", &Host(true)).is_none());
        assert!(memo
            .lookup(b"changed-header-same-body", &Host(false))
            .is_none());
    }
    #[test]
    fn mandatory_reads_include_ancestry_and_override_position() {
        let recorder = RecordingResolver::new(&Host(false));
        recorder.record_occurrence(dm_ir::ProcedureIdentity {
            owner: dm_ir::SymbolId::of("/datum/a"),
            name: dm_ir::SymbolId::of("run"),
            verb: false,
            occurrence: 2,
        });
        let reads = recorder.reads();
        assert_eq!(reads.len(), 2);
        assert!(matches!(reads[0].query, ResolveQuery::Ancestry(_)));
        assert!(matches!(reads[1].query, ResolveQuery::OverrideChain { .. }));
    }
}
