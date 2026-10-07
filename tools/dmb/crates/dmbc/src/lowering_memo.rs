//! Exact lowering variants with retained dependency answers and source replay.
//! A matching complete issuer domain version certifies its recorded answers;
//! changed or uncertified domains still recheck every exact semantic answer.
pub const PROCEDURE_VERSION: u32 = 5;
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
    pub published_records: AtomicU64,
    pub publication_failed: AtomicU64,
    /// Key preparation includes current parse and ABI input preparation.
    pub key_preparation_ns: AtomicU64,
    pub issued_preparations: AtomicU64,
    pub parsed_preparations: AtomicU64,
    /// Resident/disk lookup, typed decoding, and current meaning verification.
    pub lookup_ns: AtomicU64,
    pub occurrence_reads_ns: AtomicU64,
    pub explanation_ns: AtomicU64,
    /// Supported result wire creation, excluding publication IO.
    pub encode_ns: AtomicU64,
    pub publication_ns: AtomicU64,
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
    pub values: LoweringMemo<CachedProcedure>,
    disk: Option<Arc<dm_cache::CacheSnapshot>>,
    pending: Mutex<Pending>,
    pub counts: MemoCounts,
    limits: MemoLimits,
    explanations: Mutex<BTreeMap<dm_ir::ProcedureIdentity, MemoExplanation>>,
    publisher: Option<Arc<CachePublisher>>,
    publication_errors: Mutex<Vec<String>>,
    explanation_limit: usize,
}
pub type CachePublisher = dyn Fn(Vec<dm_cache::Record>) -> Result<(), String> + Send + Sync;
#[derive(Clone)]
pub struct CachedProcedure {
    pub unit: crate::lowering::LoweredUnit,
    pub relative_debug: Vec<usize>,
}
pub(crate) fn rebase_debug(
    frontend: &dm_tree::frontend::ColdFrontend,
    body: &dm_tree::frontend::BodyOccurrence,
    offsets: &[usize],
) -> Option<crate::debug_sources::DebugOrigins> {
    use crate::debug_sources::DebugOriginProvider;
    let length = body
        .expanded_span
        .end
        .checked_sub(body.expanded_span.start)?;
    let entries = offsets
        .iter()
        .map(|offset| {
            if *offset >= length {
                return None;
            }
            frontend
                .origin(body.expanded_span.start.checked_add(*offset)?)
                .ok()
        })
        .collect::<Option<Vec<_>>>()?;
    Some(crate::debug_sources::DebugOrigins { entries })
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MemoOutcome {
    ResidentHit,
    DiskHit,
    Recomputed,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MemoMissReason {
    NoExactVariant,
    RecordAbsent,
    FullKeyMismatch,
    PrivateReplayDeclined(ReplayDecline),
    ReadMeaningChanged,
    UnrebasablePrivateSidecar,
    UncacheableInput,
}
/// Bounded replay diagnostics; never authority to bypass a declined check.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ReplayDecline {
    BodyIdentity,
    PreparedAbi,
    DebugOrigins,
    ExecutableIssuer,
    PreparedIdentity,
    HelperInventory,
    HelperIssuer,
}
#[derive(Clone, Debug)]
pub struct MemoExplanation {
    pub identity: dm_ir::ProcedureIdentity,
    pub outcome: MemoOutcome,
    pub reason: Option<MemoMissReason>,
    pub changed_query: Option<ResolveQuery>,
}
impl ProcedureMemo {
    pub fn with_explanation_limit(mut self, limit: usize) -> Self {
        self.explanation_limit = limit.min(131072);
        self
    }
    /// Request-owned publication; IO happens outside the pending lock. Failure
    /// affects cache availability only and is observable through counts/errors.
    pub fn with_publisher(mut self, publisher: Arc<CachePublisher>) -> Self {
        self.publisher = Some(publisher);
        self
    }
    fn wire_error(&self, message: &str) {
        self.counts.unsupported_disk.fetch_add(1, Ordering::Relaxed);
        self.counts
            .publication_failed
            .fetch_add(1, Ordering::Relaxed);
        let mut errors = self
            .publication_errors
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        if errors.len() < 8 {
            errors.push(message.to_owned());
        }
    }
    pub fn publication_errors(&self) -> Vec<String> {
        self.publication_errors
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }
    fn publish(&self, records: Vec<dm_cache::Record>) {
        let count = records.len();
        let start = std::time::Instant::now();
        let outcome = match &self.publisher {
            Some(publisher) => publisher(records),
            None => self
                .disk
                .as_ref()
                .ok_or_else(|| "cache publication has no captured writer".to_owned())
                .and_then(|disk| {
                    disk.publish(&records)
                        .map(|_| ())
                        .map_err(|error| error.to_string())
                }),
        };
        match outcome {
            Ok(()) => {
                self.counts
                    .published_records
                    .fetch_add(count as u64, Ordering::Relaxed);
            }
            Err(message) => {
                self.counts
                    .publication_failed
                    .fetch_add(count as u64, Ordering::Relaxed);
                let mut errors = self
                    .publication_errors
                    .lock()
                    .unwrap_or_else(|error| error.into_inner());
                if errors.len() < 8 {
                    errors.push(message.chars().take(512).collect());
                }
            }
        }
        self.counts.publication_ns.fetch_add(
            start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
    }
    /// Bounded, structurally sorted observations. Hash-only bucket misses are
    /// reported as NoExactVariant, never invented dependency changes.
    pub fn explain(&self) -> Vec<MemoExplanation> {
        self.explanations
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .values()
            .cloned()
            .collect()
    }
    pub(crate) fn note(&self, record: MemoExplanation) {
        let start = std::time::Instant::now();
        let mut records = self
            .explanations
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        records.insert(record.identity, record);
        if records.len() > self.explanation_limit {
            records.pop_last();
        }
        self.counts.explanation_ns.fetch_add(
            start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
    }
    pub fn new(policy: u128) -> Self {
        Self {
            policy,
            values: LoweringMemo::default(),
            disk: None,
            pending: Mutex::new(Pending::default()),
            counts: MemoCounts::default(),
            limits: MemoLimits::default(),
            explanations: Mutex::new(BTreeMap::new()),
            publisher: None,
            publication_errors: Mutex::new(Vec::new()),
            explanation_limit: 256,
        }
    }
    pub fn with_disk(policy: u128, snapshot: impl Into<Arc<dm_cache::CacheSnapshot>>) -> Self {
        Self::with_disk_limits(policy, snapshot, MemoLimits::default())
    }
    pub fn with_disk_limits(
        policy: u128,
        snapshot: impl Into<Arc<dm_cache::CacheSnapshot>>,
        limits: MemoLimits,
    ) -> Self {
        Self {
            policy,
            values: LoweringMemo::with_limit(limits.resident_bytes),
            disk: Some(snapshot.into()),
            pending: Mutex::new(Pending::default()),
            counts: MemoCounts::default(),
            limits,
            explanations: Mutex::new(BTreeMap::new()),
            publisher: None,
            publication_errors: Mutex::new(Vec::new()),
            explanation_limit: 256,
        }
    }
    fn record_key(key: &[u8]) -> dm_cache::RecordKey {
        dm_cache::RecordKey {
            stage: 2,
            version: PROCEDURE_VERSION,
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
    pub(crate) fn lookup_procedure<R: Resolver>(
        &self,
        key: &[u8],
        identity: dm_ir::ProcedureIdentity,
        frontend: &dm_tree::frontend::ColdFrontend,
        body: &dm_tree::frontend::BodyOccurrence,
        host: &R,
        prepared: &crate::procedure_policy::PreparedUnit,
        parsed: Option<&dm_syntax::Item>,
    ) -> crate::lowering_memo_wire::ProcedureLookup {
        let Some(snapshot) = &self.disk else {
            return crate::lowering_memo_wire::ProcedureLookup {
                miss: Some(MemoMissReason::RecordAbsent),
                ..Default::default()
            };
        };
        let decoded = std::cell::RefCell::new(None);
        let view = snapshot.get(Self::record_key(key), |bytes, _symbols| {
            let candidates = crate::lowering_memo_wire::candidates(bytes)?;
            *decoded.borrow_mut() = Some(candidates);
            Ok(())
        });
        if view.is_none() {
            return crate::lowering_memo_wire::ProcedureLookup {
                miss: Some(MemoMissReason::RecordAbsent),
                ..Default::default()
            };
        }
        let Some(candidates) = decoded.into_inner() else {
            return Default::default();
        };
        candidates.procedure(key, identity, frontend, body, host, prepared, parsed)
    }
    pub(crate) fn queue_disk(
        &self,
        key: &[u8],
        reads: &[ResolverRead],
        unit: &crate::lowering::LoweredUnit,
        relative_debug: &[usize],
        versions: &[(ReadDomain, u128)],
    ) {
        if self.disk.is_none() {
            return;
        }
        let start = std::time::Instant::now();
        let payload = crate::lowering_memo_wire::encode(key, reads, versions, unit, relative_debug);
        self.counts.encode_ns.fetch_add(
            start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
        let Some(payload) = payload else {
            self.wire_error("procedure record cannot be represented by the cache wire format");
            return;
        };
        self.queue_payload(key, payload);
    }
    pub(crate) fn lookup_anonymous<R: Resolver>(
        &self,
        key: &[u8],
        host: &R,
        debug_count: usize,
    ) -> crate::lowering_memo_wire::AnonymousLookup {
        let Some(snapshot) = &self.disk else {
            return Default::default();
        };
        let decoded = std::cell::RefCell::new(None);
        let view = snapshot.get(Self::record_key(key), |bytes, _symbols| {
            let candidates = crate::lowering_memo_wire::candidates(bytes)?;
            *decoded.borrow_mut() = Some(candidates);
            Ok(())
        });
        if view.is_none() {
            return Default::default();
        }
        let Some(candidates) = decoded.into_inner() else {
            return Default::default();
        };
        let outcome = candidates.anonymous(key, host, debug_count);
        if outcome.code.is_some() || outcome.errors.is_some() {
            self.counts.disk_hits.fetch_add(1, Ordering::Relaxed);
        }
        outcome
    }
    pub(crate) fn remember_failure(
        &self,
        key: &[u8],
        identity: Option<dm_ir::ProcedureIdentity>,
        reads: &[ResolverRead],
        errors: &[dm_codegen_byond::LowerError],
        versions: &[(ReadDomain, u128)],
    ) {
        if self.disk.is_none() {
            return;
        }
        if let Some(payload) =
            crate::lowering_memo_wire::encode_failure(key, identity, reads, versions, errors)
        {
            self.queue_payload(key, payload);
        } else {
            self.wire_error(
                "procedure diagnostic record cannot be represented by the cache wire format",
            );
        }
    }
    pub(crate) fn remember_executable(
        &self,
        key: &[u8],
        reads: &[ResolverRead],
        code: &dm_codegen_byond::lower_resolver::ResolverProc,
        versions: &[(ReadDomain, u128)],
    ) {
        self.counts.recomputed.fetch_add(1, Ordering::Relaxed);
        if self.disk.is_none() {
            return;
        }
        let start = std::time::Instant::now();
        let payload = crate::lowering_memo_wire::encode_executable(key, reads, versions, code);
        self.counts.encode_ns.fetch_add(
            start.elapsed().as_nanos().min(u64::MAX as u128) as u64,
            Ordering::Relaxed,
        );
        match payload {
            Some(payload) => self.queue_payload(key, payload),
            None => {
                self.wire_error(
                    "anonymous procedure record cannot be represented by the cache wire format",
                );
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
        let bytes = match dm_cache::encode_variants(&variants) {
            Ok(bytes) => bytes,
            Err(error) => {
                self.counts
                    .publication_failed
                    .fetch_add(1, Ordering::Relaxed);
                let mut errors = self
                    .publication_errors
                    .lock()
                    .unwrap_or_else(|e| e.into_inner());
                if errors.len() < 8 {
                    errors.push(format!("cache variant encoding failed: {error}"));
                }
                return;
            }
        };
        let old = pending
            .records
            .get(&record_key)
            .map_or(0, |record| record.payload.len() + 128);
        // Include descriptor/framing/alignment headroom so the default 64MiB segment fits.
        let total = pending.bytes - old + bytes.len() + 128;
        pending.bytes = total;
        pending.records.insert(
            record_key,
            dm_cache::Record {
                key: record_key,
                symbols: Vec::new(),
                payload: bytes.into(),
            },
        );
        if pending.bytes >= self.limits.pending_bytes.min(8 * 1024 * 1024).max(1) {
            let records = std::mem::take(&mut *pending)
                .records
                .into_values()
                .collect();
            drop(pending);
            self.publish(records);
        }
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
        relative_debug: Vec<usize>,
        versions: Vec<(ReadDomain, u128)>,
    ) {
        // Unsupported AST-bearing sidecars need their absolute occurrence until
        // a dedicated rebasing wire is implemented. Resident reuse checks it.
        let mut code_bytes = dm_wire::encode(0x0204_0003, &unit.code.procedure)
            .map_or(usize::MAX, |bytes| bytes.len());
        for helper in &unit.source_helpers {
            code_bytes = code_bytes.saturating_add(
                dm_wire::encode(0x0204_0003, &helper.code.procedure)
                    .map_or(usize::MAX, |bytes| bytes.len()),
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
            .saturating_add(
                versions
                    .len()
                    .saturating_mul(std::mem::size_of::<(ReadDomain, u128)>()),
            )
            .saturating_mul(4)
            .saturating_add(8192);
        if !self
            .values
            .insert_with(key.into(), reads, versions, weight, || CachedProcedure {
                unit: unit.clone(),
                relative_debug,
            })
        {
            self.counts.resident_dropped.fetch_add(1, Ordering::Relaxed);
        }
    }
}

fn prepared_metadata_key(
    key: &mut Vec<u8>,
    prepared: &crate::procedure_policy::PreparedUnit,
) -> Option<()> {
    let inputs = &prepared.inputs;
    let types = inputs.parameter_types.iter().collect::<BTreeMap<_, _>>();
    let bytes = dm_wire::encode(
        0x0204_0004,
        &(
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
        ),
    )
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
    Some(())
}

pub(crate) fn prepared_replay_key(
    key: &mut Vec<u8>,
    prepared: &crate::procedure_policy::PreparedUnit,
) -> Option<()> {
    prepared_metadata_key(key, prepared)?;
    key.push(1);
    let transform = crate::procedure_policy::PreparedReplay::TRANSFORM;
    key.extend_from_slice(&(transform.len() as u64).to_le_bytes());
    key.extend_from_slice(transform);
    Some(())
}

pub(crate) fn prepared_key(
    key: &mut Vec<u8>,
    prepared: &crate::procedure_policy::PreparedUnit,
    base: usize,
) -> Option<()> {
    prepared_metadata_key(key, prepared)?;
    key.push(0);
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
    let mut key = b"dmbc-procedure-memo-v4-issued-body\0".to_vec();
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
    // Provenance is rebuilt from producer-issued relative source anchors.
    // Expanded __FILE__/__LINE__ values, when executable, are already in source.
    Some(key)
}

/// Versions are immutable issuer facts. Missing/different receipts require every
/// original positive or negative answer to be checked exactly.
pub(crate) fn matching_domains<R: Resolver>(
    versions: &[(ReadDomain, u128)],
    resolver: &R,
) -> std::collections::BTreeSet<ReadDomain> {
    versions
        .iter()
        .filter_map(|&(domain, version)| {
            (resolver.domain_version(domain) == Some(version)).then_some(domain)
        })
        .collect()
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
    versions: Mutex<BTreeMap<ReadDomain, Option<u128>>>,
}
impl<'a, R: Resolver> RecordingResolver<'a, R> {
    pub fn new(resolver: &'a R) -> Self {
        Self {
            resolver,
            reads: Mutex::new(BTreeMap::new()),
            versions: Mutex::new(BTreeMap::new()),
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
    pub fn domain_receipts(&self) -> Vec<(ReadDomain, u128)> {
        self.versions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .iter()
            .filter_map(|(&domain, &version)| version.map(|version| (domain, version)))
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
    fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
        self.resolver.domain_version(domain)
    }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        self.versions
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .entry(query.domain())
            .or_insert_with(|| self.resolver.domain_version(query.domain()));
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
    versions: Arc<[(ReadDomain, u128)]>,
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
        self.lookup_explained(key, resolver).0
    }
    pub fn lookup_explained<R: Resolver>(
        &self,
        key: &[u8],
        resolver: &R,
    ) -> (Option<Arc<T>>, Option<ResolveQuery>) {
        let hash = xxhash_rust::xxh3::xxh3_128(key);
        // Resolver work takes place outside the store lock, allowing parallel units.
        let candidates = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state
                .buckets
                .get(&hash)
                .into_iter()
                .flatten()
                .filter(|entry| entry.key.as_ref() == key)
                .map(|entry| {
                    (
                        Arc::clone(&entry.reads),
                        Arc::clone(&entry.versions),
                        Arc::clone(&entry.value),
                    )
                })
                .collect::<Vec<_>>()
        };
        let mut changed = None;
        for (reads, versions, value) in candidates.into_iter().rev() {
            let matching = matching_domains(&versions, resolver);
            let mismatch = reads.iter().find(|read| {
                !matching.contains(&read.domain)
                    && resolver.resolve(read.query).canonical_bytes()
                        != read.answer.canonical_bytes()
            });
            if let Some(read) = mismatch {
                changed = Some(read.query);
            } else {
                return (Some(value), None);
            }
        }
        (None, changed)
    }
    pub fn insert(&self, key: Arc<[u8]>, reads: Vec<ResolverRead>, value: T) {
        let weight = key.len()
            + std::mem::size_of::<T>()
            + reads
                .iter()
                .map(|read| read.answer.canonical_bytes().len())
                .sum::<usize>();
        self.insert_with(key, reads, Vec::new(), weight, || value);
    }
    fn insert_with(
        &self,
        key: Arc<[u8]>,
        reads: Vec<ResolverRead>,
        versions: Vec<(ReadDomain, u128)>,
        weight: usize,
        create: impl FnOnce() -> T,
    ) -> bool {
        let hash = xxhash_rust::xxh3::xxh3_128(&key);
        let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
        // Resident storage evicts before admitting a new value. Results are
        // independently published; an oversized value needs no resident copy.
        if weight > self.limit {
            return false;
        }
        while state.bytes.saturating_add(weight) > self.limit {
            let Some(oldest_bucket) = state.buckets.keys().next().copied() else {
                break;
            };
            let bucket = state.buckets.get_mut(&oldest_bucket).unwrap();
            let removed = bucket.remove(0);
            let empty = bucket.is_empty();
            state.bytes -= removed.weight;
            if empty {
                state.buckets.remove(&oldest_bucket);
            }
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
                    versions: versions.into(),
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
            versions: versions.into(),
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
    #[test]
    fn resident_budget_evicts_before_retaining_new_results() {
        let memo = LoweringMemo::with_limit(10);
        assert!(memo.insert_with(Arc::from(b"a".as_slice()), vec![], vec![], 6, || 1u32));
        assert!(memo.insert_with(Arc::from(b"b".as_slice()), vec![], vec![], 6, || 2u32));
        assert!(memo.lookup(b"a", &Host(false)).is_none());
        assert_eq!(memo.lookup(b"b", &Host(false)).as_deref(), Some(&2));
        assert_eq!(memo.admitted_bytes(), 6);
    }

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
    struct VersionHost {
        tree: Option<u128>,
        resource: Option<u128>,
        changed: bool,
        calls: std::sync::atomic::AtomicUsize,
    }
    impl Resolver for VersionHost {
        fn domain_version(&self, domain: ReadDomain) -> Option<u128> {
            match domain {
                ReadDomain::Tree => self.tree,
                ReadDomain::ResourceSearch => self.resource,
            }
        }
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            self.calls
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            if self.changed {
                ResolvedMeaning::Symbol(dm_ir::SymbolId::of("changed"))
            } else {
                ResolvedMeaning::Missing
            }
        }
    }
    #[test]
    fn domain_receipts_skip_matching_domains_and_recheck_changed_or_unknown_versions() {
        let host = |tree, resource, changed| VersionHost {
            tree,
            resource,
            changed,
            calls: Default::default(),
        };
        let initial = host(Some(1), Some(2), false);
        let recorder = RecordingResolver::new(&initial);
        recorder.resolve(ResolveQuery::GlobalVar(dm_ir::SymbolId::of("absent")));
        recorder.resolve(ResolveQuery::Resource(dm_ir::SymbolId::of("missing.asset")));
        assert_eq!(recorder.reads().len(), 2);
        assert_eq!(recorder.domain_receipts().len(), 2);
        assert_eq!(recorder.domain_version(ReadDomain::Tree), Some(1));
        let memo = LoweringMemo::default();
        assert!(memo.insert_with(
            Arc::from(b"domain-key".as_slice()),
            recorder.reads(),
            recorder.domain_receipts(),
            1,
            || 7u32
        ));
        let same = host(Some(1), Some(2), false);
        assert_eq!(memo.lookup(b"domain-key", &same).as_deref(), Some(&7));
        assert_eq!(same.calls.load(std::sync::atomic::Ordering::Relaxed), 0);
        let partial = host(Some(1), Some(3), false);
        assert!(memo.lookup(b"domain-key", &partial).is_some());
        assert_eq!(partial.calls.load(std::sync::atomic::Ordering::Relaxed), 1);
        let unknown = host(None, None, false);
        assert!(memo.lookup(b"domain-key", &unknown).is_some());
        assert_eq!(unknown.calls.load(std::sync::atomic::Ordering::Relaxed), 2);
        let changed = host(Some(4), Some(3), true);
        assert!(memo.lookup(b"domain-key", &changed).is_none());
    }
}
