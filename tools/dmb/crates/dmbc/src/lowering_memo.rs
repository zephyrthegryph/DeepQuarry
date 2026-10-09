//! Exact lowering variants with retained dependency answers and source replay.
//! A matching complete issuer domain version certifies its recorded answers;
//! changed or uncertified domains still recheck every exact semantic answer.
pub const PROCEDURE_VERSION: u32 = 5;
#[cfg(test)]
use dm_ir::ResolvedMeaning;
use dm_ir::{ReadDomain, ResolveQuery, Resolver};
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
const RESIDENT_LIMIT: usize = dm_session::DEFAULT_RESIDENT_BYTES;
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

/// One-shot CLI requests publish disk records without retaining duplicate rich IR.
/// Retained sessions may enable bounded resident replay explicitly.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResidentRetention {
    Enabled,
    DiskOnly,
}
/// Caller-issued compiler/ABI/emission policy identity, never whole-tree identity.
pub struct ProcedureMemo {
    pub policy: u128,
    resident_retention: ResidentRetention,
    pub values: Arc<LoweringMemo<CachedProcedure>>,
    pub(crate) symbolic: Option<Arc<crate::lowering::symbolic_input::SessionSymbolicMemo>>,
    pub(crate) initializers: Option<Arc<crate::initializer_policy::InitializerArtifacts>>,
    pub(crate) startup: Option<Arc<crate::startup::StartupArtifacts>>,
    pub(crate) abi: Option<Arc<crate::driver_facts::AbiArtifacts>>,
    pub(crate) initializer_fragments:
        Option<Arc<crate::initializer_lowering::InitializerFragments>>,
    pub(crate) initializer_assemblies:
        Option<Arc<crate::initializer_lowering::InitializerAssemblies>>,
    pub(crate) class_projections: Option<Arc<crate::class_projection::ClassProjections>>,
    pub(crate) link_bindings: Option<Arc<dm_link::RetainedBindings>>,
    disk: Option<Arc<dm_cache::CacheSnapshot>>,
    pending: Mutex<Pending>,
    pub counts: MemoCounts,
    limits: MemoLimits,
    explanations: Mutex<BTreeMap<dm_ir::ProcedureIdentity, MemoExplanation>>,
    read_only_disk: bool,
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
    /// Observe the optional retained assembled-code owner without decoding it.
    pub fn initializer_assembly_retention_census(
        &self,
    ) -> Option<crate::heap_census::HeapCensusReport> {
        self.initializer_assemblies
            .as_ref()
            .map(|store| crate::heap_census::initializer_assembly_census(store))
    }

    pub fn with_explanation_limit(mut self, limit: usize) -> Self {
        self.explanation_limit = limit.min(131072);
        self
    }
    /// Request-owned publication; IO happens outside the pending lock. Failure
    /// affects cache availability only and is observable through counts/errors.
    /// Hydrate existing records without encoding/populating this disk store.
    pub fn with_read_only_disk(mut self) -> Self {
        self.read_only_disk = true;
        self
    }
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
        let _profile = dm_profile::stage("lowering.population_flush");
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
            resident_retention: ResidentRetention::Enabled,
            values: Arc::new(LoweringMemo::default()),
            symbolic: None,
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            link_bindings: None,
            disk: None,
            pending: Mutex::new(Pending::default()),
            counts: MemoCounts::default(),
            limits: MemoLimits::default(),
            explanations: Mutex::new(BTreeMap::new()),
            read_only_disk: false,
            publisher: None,
            publication_errors: Mutex::new(Vec::new()),
            explanation_limit: 256,
        }
    }
    /// Request-local facade: only immutable resident results survive requests.
    pub fn with_resident(
        policy: u128,
        values: Arc<LoweringMemo<CachedProcedure>>,
        disk: Option<Arc<dm_cache::CacheSnapshot>>,
    ) -> Self {
        let mut memo = Self::new(policy);
        memo.values = values;
        memo.disk = disk;
        memo
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
            resident_retention: ResidentRetention::Enabled,
            values: Arc::new(LoweringMemo::with_limit(limits.resident_bytes)),
            symbolic: None,
            initializers: None,
            startup: None,
            abi: None,
            initializer_fragments: None,
            initializer_assemblies: None,
            class_projections: None,
            link_bindings: None,
            disk: Some(snapshot.into()),
            pending: Mutex::new(Pending::default()),
            counts: MemoCounts::default(),
            limits,
            explanations: Mutex::new(BTreeMap::new()),
            read_only_disk: false,
            publisher: None,
            publication_errors: Mutex::new(Vec::new()),
            explanation_limit: 256,
        }
    }
    pub fn with_disk_only(policy: u128, snapshot: impl Into<Arc<dm_cache::CacheSnapshot>>) -> Self {
        let mut memo = Self::with_disk(policy, snapshot);
        memo.resident_retention = ResidentRetention::DiskOnly;
        memo
    }
    pub fn resident_retention(&self) -> ResidentRetention {
        self.resident_retention
    }
    fn record_key(key: &[u8]) -> dm_cache::RecordKey {
        dm_cache::RecordKey {
            stage: 2,
            version: PROCEDURE_VERSION,
            content: xxhash_rust::xxh3::xxh3_128(key),
        }
    }
    fn disk_variants(&self, key: &[u8]) -> Vec<Vec<u8>> {
        let _profile = dm_profile::item("lowering.population_previous_variants");
        let Some(snapshot) = &self.disk else {
            return Vec::new();
        };
        snapshot
            .get(Self::record_key(key), |bytes, _symbols| {
                let variants = dm_cache::decode_variants(bytes)?;
                for variant in variants {
                    crate::lowering_memo_wire::validate(variant)?;
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
        context: crate::lowering_memo_wire::ProcedureReplayContext<'_>,
        host: &R,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> crate::lowering_memo_wire::ProcedureLookup {
        let Some(snapshot) = &self.disk else {
            return crate::lowering_memo_wire::ProcedureLookup {
                miss: Some(MemoMissReason::RecordAbsent),
                ..Default::default()
            };
        };
        let decoded = std::cell::RefCell::new(None);
        let view = {
            let _profile = dm_profile::item("lowering.disk_lookup_decode");
            snapshot.get(Self::record_key(key), |bytes, _symbols| {
                let candidates = crate::lowering_memo_wire::candidates(bytes)?;
                *decoded.borrow_mut() = Some(candidates);
                Ok(())
            })
        };
        if view.is_none() {
            return crate::lowering_memo_wire::ProcedureLookup {
                miss: Some(MemoMissReason::RecordAbsent),
                ..Default::default()
            };
        }
        let Some(candidates) = decoded.into_inner() else {
            return Default::default();
        };
        let _profile = dm_profile::item("lowering.disk_validate_replay");
        let result = candidates.procedure(key, identity, context, host, prepared);
        if self.resident_retention == ResidentRetention::Enabled {
            if let (Some(unit), Some(promotion)) = (&result.unit, result.resident.as_ref()) {
                let reads = promotion
                    .queries
                    .iter()
                    .copied()
                    .map(|query| ResolverRead {
                        domain: query.domain(),
                        answer: host.resolve(query),
                        query,
                    })
                    .collect();
                self.remember(
                    key.to_vec(),
                    reads,
                    unit,
                    promotion.relative_debug.clone(),
                    promotion.versions.clone(),
                );
            }
        }
        result
    }
    pub(crate) fn queue_disk(
        &self,
        key: &[u8],
        reads: &[ResolverRead],
        unit: &crate::lowering::LoweredUnit,
        relative_debug: &[usize],
        versions: &[(ReadDomain, u128)],
    ) {
        if self.read_only_disk || self.disk.is_none() {
            return;
        }
        let start = std::time::Instant::now();
        let payload = {
            let _profile = dm_profile::item("lowering.population_encode");
            crate::lowering_memo_wire::encode(key, reads, versions, unit, relative_debug)
        };
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
        let view = {
            let _profile = dm_profile::item("lowering.disk_lookup_decode");
            snapshot.get(Self::record_key(key), |bytes, _symbols| {
                let candidates = crate::lowering_memo_wire::candidates(bytes)?;
                *decoded.borrow_mut() = Some(candidates);
                Ok(())
            })
        };
        if view.is_none() {
            return Default::default();
        }
        let Some(candidates) = decoded.into_inner() else {
            return Default::default();
        };
        let outcome = {
            let _profile = dm_profile::item("lowering.disk_validate_replay");
            candidates.anonymous(key, host, debug_count)
        };
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
        if self.read_only_disk || self.disk.is_none() {
            return;
        }
        let payload = {
            let _profile = dm_profile::item("lowering.population_encode");
            crate::lowering_memo_wire::encode_failure(key, identity, reads, versions, errors)
        };
        if let Some(payload) = payload {
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
        if self.read_only_disk || self.disk.is_none() {
            return;
        }
        let start = std::time::Instant::now();
        let payload = {
            let _profile = dm_profile::item("lowering.population_encode");
            crate::lowering_memo_wire::encode_executable(key, reads, versions, code)
        };
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
        let queue_profile = dm_profile::item("lowering.population_queue");
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
        if pending.bytes >= self.limits.pending_bytes.clamp(1, 8 * 1024 * 1024) {
            let records = std::mem::take(&mut *pending)
                .records
                .into_values()
                .collect();
            drop(pending);
            drop(queue_profile);
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
        if self.resident_retention == ResidentRetention::DiskOnly {
            // Avoid weight serialization and RichIR clone for a request-local
            // cache. Disk publication occurred independently before this call.
            return;
        }
        let _profile = dm_profile::item("lowering.resident_store");
        let Some(weight) = crate::heap_census::resident_weight::procedure(
            unit,
            &relative_debug,
            &key,
            &reads,
            &versions,
        ) else {
            self.counts.resident_dropped.fetch_add(1, Ordering::Relaxed);
            return;
        };
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
    let _profile = dm_profile::item("lowering.key_create");
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

// Compatibility names preserve all existing procedure memo and wire consumers.
pub(crate) use dm_session::matching_domains;
pub use dm_session::{ArtifactStore as LoweringMemo, RecordingResolver, ResolverRead};

#[cfg(test)]
#[path = "lowering_memo/tests.rs"]
mod tests;
