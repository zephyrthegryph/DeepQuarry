//! Exact lowering variants with retained dependency answers and source replay.
//! A matching complete issuer domain version certifies its recorded answers;
//! changed or uncertified domains still recheck every exact semantic answer.
pub const PROCEDURE_VERSION: u32 = 7;
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
    pub compact_disk_hits: AtomicU64,
    pub compact_disk_encoded: AtomicU64,
    pub compact_fallback_encoding: AtomicU64,
    pub compact_fallback_ineligible: AtomicU64,
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
type Pending = dm_cache::PendingRecords;
#[path = "lowering_memo_population.rs"]
mod population;
pub(crate) use population::DiskWriter;

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
    pub(crate) required_types: Option<Arc<crate::required_types::RequiredTypeArtifacts>>,
    pub(crate) link_bindings: Option<Arc<dm_link::RetainedBindings>>,
    disk: Option<Arc<crate::runner_disk::LazyDisk>>,
    pending: Arc<Mutex<Pending>>,
    pub counts: Arc<MemoCounts>,
    limits: MemoLimits,
    explanations: Mutex<BTreeMap<dm_ir::ProcedureIdentity, MemoExplanation>>,
    read_only_disk: bool,
    publisher: Option<Arc<CachePublisher>>,
    publication_errors: Arc<Mutex<Vec<String>>>,
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
    pub(crate) fn completion_writer(&self) -> Option<DiskWriter> {
        (!self.read_only_disk && self.disk.is_some()).then(|| DiskWriter::from_memo(self))
    }
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
        DiskWriter::from_memo(self).wire_error(message);
    }
    pub fn publication_errors(&self) -> Vec<String> {
        self.publication_errors
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
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
            required_types: None,
            link_bindings: None,
            disk: None,
            pending: Arc::new(Mutex::new(Pending::default())),
            counts: Arc::new(MemoCounts::default()),
            limits: MemoLimits::default(),
            explanations: Mutex::new(BTreeMap::new()),
            read_only_disk: false,
            publisher: None,
            publication_errors: Arc::new(Mutex::new(Vec::new())),
            explanation_limit: 256,
        }
    }
    /// Request-local facade: only immutable resident results survive requests.
    pub fn with_resident(
        policy: u128,
        values: Arc<LoweringMemo<CachedProcedure>>,
        disk: Option<Arc<crate::runner_disk::LazyDisk>>,
    ) -> Self {
        let mut memo = Self::new(policy);
        memo.values = values;
        memo.disk = disk;
        memo
    }
    pub fn with_lazy_disk(policy: u128, disk: Arc<crate::runner_disk::LazyDisk>) -> Self {
        Self::with_resident(policy, Arc::new(LoweringMemo::default()), Some(disk))
    }
    pub fn with_lazy_disk_only(policy: u128, disk: Arc<crate::runner_disk::LazyDisk>) -> Self {
        let mut memo = Self::with_lazy_disk(policy, disk);
        memo.resident_retention = ResidentRetention::DiskOnly;
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
            required_types: None,
            link_bindings: None,
            disk: Some(Arc::new(crate::runner_disk::LazyDisk::from_snapshot(
                snapshot.into(),
            ))),
            pending: Arc::new(Mutex::new(Pending::default())),
            counts: Arc::new(MemoCounts::default()),
            limits,
            explanations: Mutex::new(BTreeMap::new()),
            read_only_disk: false,
            publisher: None,
            publication_errors: Arc::new(Mutex::new(Vec::new())),
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
    pub(crate) fn lookup_procedure<R: Resolver>(
        &self,
        key: &[u8],
        identity: dm_ir::ProcedureIdentity,
        context: crate::lowering_memo_wire::ProcedureReplayContext<'_>,
        host: &R,
        prepared: &crate::procedure_policy::PreparedUnit,
    ) -> crate::lowering_memo_wire::ProcedureLookup {
        let Some(snapshot) = self.disk.as_ref().and_then(|disk| disk.snapshot()) else {
            return crate::lowering_memo_wire::ProcedureLookup {
                miss: Some(MemoMissReason::RecordAbsent),
                ..Default::default()
            };
        };
        let replay = std::cell::RefCell::new(None);
        let view = snapshot.get_candidate(Self::record_key(key), |bytes, _symbols| {
            let candidates = {
                let _profile = dm_profile::item("lowering.disk_lookup_decode");
                crate::lowering_memo_wire::candidates(bytes)?
            };
            // Validate the complete typed envelope before replaying any reads.
            // Only exact semantic admission makes this mapped record reachable.
            let result = {
                let _profile = dm_profile::item("lowering.disk_validate_replay");
                candidates.procedure(
                    key,
                    identity,
                    crate::lowering_memo_wire::ProcedureReplayContext {
                        frontend: context.frontend,
                        body: context.body,
                        parsed: context.parsed,
                        bindings: context.bindings,
                    },
                    host,
                    prepared,
                )
            };
            let admitted =
                result.unit.is_some() || result.prepared.is_some() || result.errors.is_some();
            let mut replay = replay.borrow_mut();
            if admitted || replay.is_none() {
                *replay = Some(result);
            }
            Ok(admitted)
        });
        let result =
            replay
                .into_inner()
                .unwrap_or_else(|| crate::lowering_memo_wire::ProcedureLookup {
                    miss: Some(MemoMissReason::RecordAbsent),
                    ..Default::default()
                });
        debug_assert_eq!(
            view.is_some(),
            result.unit.is_some() || result.prepared.is_some() || result.errors.is_some()
        );
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
        let Some(snapshot) = self.disk.as_ref().and_then(|disk| disk.snapshot()) else {
            return Default::default();
        };
        let replay = std::cell::RefCell::new(None);
        let view = snapshot.get_candidate(Self::record_key(key), |bytes, _symbols| {
            let candidates = {
                let _profile = dm_profile::item("lowering.disk_lookup_decode");
                crate::lowering_memo_wire::candidates(bytes)?
            };
            let outcome = {
                let _profile = dm_profile::item("lowering.disk_validate_replay");
                candidates.anonymous(key, host, debug_count)
            };
            let admitted = outcome.code.is_some() || outcome.errors.is_some();
            if admitted {
                *replay.borrow_mut() = Some(outcome);
            }
            Ok(admitted)
        });
        let outcome = replay.into_inner().unwrap_or_default();
        debug_assert_eq!(
            view.is_some(),
            outcome.code.is_some() || outcome.errors.is_some()
        );
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
        DiskWriter::from_memo(self).queue_payload(key, payload);
    }
    /// Publish once per build; never create one physical segment per procedure.
    pub fn take_pending(&self) -> Vec<dm_cache::Record> {
        self.pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .take()
    }
    pub fn pending_bytes(&self) -> usize {
        self.pending
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .bytes() as usize
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
