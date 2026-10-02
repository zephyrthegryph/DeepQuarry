//! Persistent procedure queries, independent of syntax and output table IDs.
//!
//! A body-only edit changes one descriptor. Declaration changes refresh only
//! previously observed semantic facts, including unsuccessful resolutions.
//! Query hits require neither an AST nor reconstruction of LowerBindings.
use crate::{
    semantic_queries::{fact_heap, memo_heap, value_heap},
    ProcedureMemo,
};
use dm_codegen_byond::{
    prepared_cache::PreparedProcedureEnvelope, BindingFact, BindingWitness, FactValue,
};
use salsa::Setter;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    io,
    path::Path,
    sync::Arc,
};

const DISK_STAGE: &str = env!("DM_LOWERING_FINGERPRINT");
const MAX_HEADER: usize = 4 * 1024 * 1024;
const MAX_PAYLOAD: usize = 32 * 1024 * 1024;
const SNAPSHOT_BYTES: usize = 128 * 1024 * 1024;
const PENDING_BYTES: usize = 32 * 1024 * 1024;
// Limit the temporary raw + checksum-decoded read batch independently of the
// retained startup snapshot. Larger individual records are read on demand.
const PREFETCH_BATCH_BYTES: usize = 8 * 1024 * 1024;
// Salsa 0.28 retains 8/12-byte dependency edges. Charge 16 bytes per edge,
// including the three ProcedureInput fields, in addition to witness storage.
const QUERY_EDGE_BYTES: usize = 16;
// Include tree nodes and retained string/Vec allocations, not just wire bytes.
const BUFFER_ENTRY_OVERHEAD: usize = 160;
const MAX_PENDING_RECORDS: usize = 64_000;

fn pending_record_bytes(key: &dm_store::Key, bytes: &Vec<u8>) -> usize {
    BUFFER_ENTRY_OVERHEAD
        .saturating_add(key.namespace.capacity())
        .saturating_add(key.name.capacity())
        .saturating_add(bytes.capacity())
}

/// Occurrences preserve authored override order; offsets and output IDs are not
/// identities. The frontend adapter owns matching occurrences across revisions.
#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash, Serialize, Deserialize)]
pub struct ProcKey {
    pub path: String,
    pub occurrence: u32,
}

/// Body includes relative debug span shape. Frame includes signature, defaults,
/// current owner and static aliases, but excludes unrelated declaration facts.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ProcDescriptor {
    pub body_digest: String,
    pub frame_digest: String,
}

/// Opaque portable cache handle. The adapter owns its namespace and decoding;
/// it must include the implementation fingerprint and exact semantic result.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ProcedureMemoRef {
    pub key: String,
}

/// Prepared code must be independent of current absolute source locations.
/// Apply the current source-origin sidecar during output materialization.
#[derive(Clone)]
pub enum ProcedureArtifact {
    Symbolic(Arc<ProcedureMemo>),
    Prepared(Arc<PreparedProcedureEnvelope>),
}
impl ProcedureArtifact {
    fn resident_bytes(&self) -> usize {
        match self {
            Self::Symbolic(memo) => memo_heap(memo),
            Self::Prepared(envelope) => {
                let p = &envelope.metadata;
                let mut bytes = std::mem::size_of::<PreparedProcedureEnvelope>()
                    .saturating_add(envelope.section.resident_bytes())
                    .saturating_add(envelope.reference_origin_bytes());
                for strings in [
                    &p.strings,
                    &p.class_paths,
                    &p.instance_paths,
                    &p.resources,
                    &p.local_names,
                    &p.argument_names,
                ] {
                    bytes =
                        bytes.saturating_add(strings.capacity() * std::mem::size_of::<String>());
                    for text in strings {
                        bytes = bytes.saturating_add(text.capacity());
                    }
                }
                bytes = bytes
                    .saturating_add(
                        p.statement_origins.capacity()
                            * std::mem::size_of::<dm_codegen_byond::debug::StatementOrigin>(),
                    )
                    .saturating_add(p.argument_type_flags.capacity() * 4)
                    .saturating_add(p.argument_value_sources.capacity() * 4);
                for (key, value) in &p.format_templates {
                    bytes = bytes
                        .saturating_add(128)
                        .saturating_add(key.capacity())
                        .saturating_add(value.capacity());
                }
                bytes
            }
        }
    }
}

#[derive(Clone)]
pub enum ProcedureProbe {
    Resident(ProcedureArtifact),
    /// Its witnesses have already been checked by Salsa. Disk decoding can
    /// replace the resident artifact without parsing or rebuilding a frame.
    Disk(ProcedureMemoRef),
    Miss,
}

/// Artifact and metadata budgets are independent. Counts include every input
/// ever allocated in this session: removing a proc cannot bypass the bounds.
#[derive(Clone, Copy, Debug)]
pub struct ProjectGraphLimits {
    pub resident_bytes: usize,
    pub metadata_bytes: usize,
    pub procedures: usize,
    pub facts: usize,
}
impl Default for ProjectGraphLimits {
    fn default() -> Self {
        Self {
            resident_bytes: 96 * 1024 * 1024,
            metadata_bytes: 256 * 1024 * 1024,
            procedures: 128_000,
            facts: 1_000_000,
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct ProjectGraphStats {
    pub resident_hits: usize,
    pub disk_hits: usize,
    pub misses: usize,
    pub installs: usize,
    pub evictions: usize,
    pub refused_installs: usize,
    pub fact_refreshes: usize,
    pub changed_facts: usize,
    pub procedures: usize,
    pub facts: usize,
    pub resident_bytes: usize,
    pub metadata_bytes: usize,
    pub disk_decodes: usize,
    pub corrupt_records: usize,
    pub restored_procedures: usize,
    pub snapshot_bytes: usize,
    pub snapshot_complete: bool,
    pub prefetch_batches: usize,
    pub prefetched_payloads: usize,
    pub payload_single_reads: usize,
}

#[derive(Serialize, Deserialize)]
struct DiskHeader {
    key: ProcKey,
    descriptor: ProcDescriptor,
    dependencies: Vec<BindingWitness>,
    payload: String,
}
struct Persistence {
    store: dm_store::Store,
    headers_namespace: String,
    payloads_namespace: String,
    payloads: BTreeMap<String, EncodedPayload>,
    payload_lru: BTreeSet<(u64, String)>,
    payload_clock: u64,
    bulk_read_failed: bool,
    pending: BTreeMap<dm_store::Key, Vec<u8>>,
    pending_bytes: usize,
}
struct EncodedPayload {
    // A missing disk row is also a bounded cache observation. It does not
    // authorize output reuse and avoids reopening the store for every miss.
    bytes: Option<Vec<u8>>,
    touched: u64,
}
fn encoded_payload_bytes(name: &str, bytes: &Option<Vec<u8>>) -> usize {
    BUFFER_ENTRY_OVERHEAD
        .saturating_mul(2)
        .saturating_add(name.len().saturating_mul(2))
        .saturating_add(bytes.as_ref().map_or(0, Vec::capacity))
}

#[salsa::input]
struct FactInput {
    #[returns(ref)]
    value: Option<FactValue>,
}
#[derive(Clone, Eq, PartialEq)]
struct Candidate {
    generation: u64,
    descriptor: ProcDescriptor,
    dependencies: Arc<[BindingWitness]>,
    disk: Option<ProcedureMemoRef>,
}
struct DecodedArtifact {
    // Code is usable only after this exact candidate has been validated.
    generation: u64,
    artifact: ProcedureArtifact,
}
#[salsa::input]
struct ProcedureInput {
    #[returns(ref)]
    descriptor: ProcDescriptor,
    #[returns(ref)]
    candidate: Option<Arc<Candidate>>,
    #[returns(ref)]
    facts: Vec<FactInput>,
}
#[salsa::db]
trait GraphDb: salsa::Database {}
#[salsa::db]
#[derive(Clone, Default)]
struct Database {
    storage: salsa::Storage<Self>,
}
#[salsa::db]
impl salsa::Database for Database {}
#[salsa::db]
impl GraphDb for Database {}

#[salsa::tracked]
fn current_candidate(db: &dyn GraphDb, input: ProcedureInput) -> Option<Arc<Candidate>> {
    let candidate = input.candidate(db).as_ref()?;
    if &candidate.descriptor != input.descriptor(db) {
        return None;
    }
    let facts = input.facts(db);
    if facts.len() != candidate.dependencies.len() {
        return None;
    }
    for (input, witness) in facts.iter().zip(candidate.dependencies.iter()) {
        if input.value(db).as_ref() != Some(&witness.value) {
            return None;
        }
    }
    Some(Arc::clone(candidate))
}

struct ObservedFact {
    input: FactInput,
    value_bytes: usize,
}
struct Record {
    input: ProcedureInput,
    descriptor: ProcDescriptor,
    facts: BTreeMap<BindingFact, ObservedFact>,
    witness_bytes: usize,
    resident_bytes: usize,
    artifact: Option<DecodedArtifact>,
    touched: u64,
    active: bool,
    descriptor_bytes: usize,
}

/// One graph per project/worktree session. The shared disk cache remains
/// content addressed; this live graph tracks the worktree's current facts.
pub struct ProjectProcedureGraph {
    db: Database,
    records: BTreeMap<ProcKey, Record>,
    /// Declaration-scoped observations have one Salsa input across all procedures.
    shared_facts: BTreeMap<BindingFact, ObservedFact>,
    lru: BTreeSet<(u64, ProcKey)>,
    revision: Option<String>,
    clock: u64,
    limits: ProjectGraphLimits,
    stats: ProjectGraphStats,
    persistence: Option<Persistence>,
    configured_identity: Option<String>,
}
impl Default for ProjectProcedureGraph {
    fn default() -> Self {
        Self::new(ProjectGraphLimits::default())
    }
}
impl ProjectProcedureGraph {
    pub fn new(limits: ProjectGraphLimits) -> Self {
        Self {
            db: Database::default(),
            records: BTreeMap::new(),
            shared_facts: BTreeMap::new(),
            lru: BTreeSet::new(),
            revision: None,
            clock: 0,
            limits,
            stats: ProjectGraphStats::default(),
            persistence: None,
            configured_identity: None,
        }
    }
    pub fn stats(&self) -> ProjectGraphStats {
        self.stats
    }

    /// The project identity selects an independent latest-procedure manifest
    /// for each worktree. Prepared payloads remain shared and content addressed.
    /// I/O failures disable persistence; fresh compilation remains available.
    pub fn open(root: &Path, project_identity: &str) -> Self {
        let mut graph = Self::default();
        graph.configured_identity = Some(format!("{}\0{project_identity}", root.display()));
        let Ok(store) = dm_store::Store::open(root.join("procedure-graph.redb")) else {
            return graph;
        };
        let identity = format!("{:x}", Sha256::digest(project_identity.as_bytes()));
        let headers_namespace = format!("graph-headers-v1-{DISK_STAGE}-{identity}");
        let payloads_namespace = format!("graph-payloads-v1-{DISK_STAGE}");
        let headers = store
            .snapshot_namespace(&headers_namespace, 128_000, 64 * 1024 * 1024, None)
            .ok();
        graph.persistence = Some(Persistence {
            store,
            headers_namespace,
            payloads_namespace,
            payloads: BTreeMap::new(),
            payload_lru: BTreeSet::new(),
            payload_clock: 0,
            bulk_read_failed: false,
            pending: BTreeMap::new(),
            pending_bytes: 0,
        });
        if let Some(headers) = headers {
            for (_, bytes) in headers.records {
                if bytes.is_empty() {
                    continue;
                } // Removed authored procedure.
                if bytes.len() > MAX_HEADER {
                    graph.stats.corrupt_records += 1;
                    continue;
                }
                let Ok(header) = serde_json::from_slice::<DiskHeader>(&bytes) else {
                    graph.stats.corrupt_records += 1;
                    continue;
                };
                if graph.install_candidate(
                    header.key,
                    header.descriptor,
                    header.dependencies.into(),
                    None,
                    Some(ProcedureMemoRef {
                        key: header.payload,
                    }),
                    true,
                ) {
                    graph.stats.restored_procedures += 1;
                }
            }
        }
        // Restored inputs deliberately start unavailable. The adapter must
        // refresh against its current skeleton before any cached result is used.
        graph.revision = None;
        // Payloads are fetched in bounded caller-supplied source order. Eager
        // loading here would retain arbitrary manifest order before emission.
        graph.trace_memory("startup");
        graph
    }

    pub fn known_keys(&self) -> impl Iterator<Item = &ProcKey> {
        self.records.keys()
    }

    /// Read nearby portable payloads in caller-supplied emission order. This
    /// fetches bytes only: probe still validates the current descriptor/facts.
    /// Refills an encoded LRU after pressure trimming instead of reopening the
    /// store for each procedure. Errors are optional cache misses at the caller.
    pub fn prefetch(&mut self, keys: &[ProcKey]) -> io::Result<usize> {
        let mut names = Vec::new();
        let mut seen = BTreeSet::new();
        for key in keys {
            let Some(record) = self.records.get(key) else {
                continue;
            };
            let Some(candidate) = record.input.candidate(&self.db).as_ref() else {
                continue;
            };
            if record
                .artifact
                .as_ref()
                .is_some_and(|a| a.generation == candidate.generation)
            {
                continue;
            }
            let Some(reference) = &candidate.disk else {
                continue;
            };
            if seen.insert(reference.key.as_str()) {
                names.push(reference.key.clone());
            }
        }
        drop(seen);
        if self.persistence.is_none() || names.is_empty() {
            return Ok(0);
        }
        let mut fetched = 0;
        for chunk in names.chunks(256) {
            let p = self.persistence.as_mut().unwrap();
            let mut reads = Vec::new();
            for name in chunk {
                let key = dm_store::Key::new(&p.payloads_namespace, name);
                if p.pending.contains_key(&key) {
                    continue;
                }
                if p.payloads.contains_key(name) {
                    Self::touch_encoded(p, name);
                } else {
                    reads.push(key);
                }
            }
            if reads.is_empty() {
                continue;
            }
            fetched += self.prefetch_batch(&reads)?;
        }
        self.stats.prefetched_payloads += fetched;
        Ok(fetched)
    }

    fn prefetch_batch(&mut self, keys: &[dm_store::Key]) -> io::Result<usize> {
        self.stats.prefetch_batches += 1;
        let result = self.persistence.as_ref().unwrap().store.read_many_bounded(
            keys,
            MAX_PAYLOAD,
            PREFETCH_BATCH_BYTES,
            None,
        );
        match result {
            Ok(batch) => {
                self.persistence.as_mut().unwrap().bulk_read_failed = false;
                let mut fetched = 0;
                for (key, bytes) in keys.iter().zip(batch.values) {
                    fetched += usize::from(bytes.is_some());
                    self.retain_encoded(key.name.clone(), bytes);
                }
                Ok(fetched)
            }
            Err(error) if error.kind() == io::ErrorKind::InvalidInput => {
                // A batch limit is not evidence of missing data. Split only
                // typed budget failures; an unusually large individual payload
                // remains available through the bounded on-demand reader.
                if keys.len() == 1 {
                    self.persistence.as_mut().unwrap().bulk_read_failed = false;
                    return Ok(0);
                }
                let (left, right) = keys.split_at(keys.len() / 2);
                Ok(self.prefetch_batch(left)? + self.prefetch_batch(right)?)
            }
            Err(error) => {
                // Do not turn one optional failed batch into hundreds of
                // individual opens. The next explicit refill retries I/O.
                self.persistence.as_mut().unwrap().bulk_read_failed = true;
                Err(error)
            }
        }
    }

    fn touch_encoded(p: &mut Persistence, name: &str) {
        let Some(payload) = p.payloads.get_mut(name) else {
            return;
        };
        p.payload_lru.remove(&(payload.touched, name.to_owned()));
        p.payload_clock = p.payload_clock.wrapping_add(1);
        payload.touched = p.payload_clock;
        p.payload_lru.insert((payload.touched, name.to_owned()));
    }

    fn retain_encoded(&mut self, name: String, bytes: Option<Vec<u8>>) {
        let charge = encoded_payload_bytes(&name, &bytes);
        if charge > SNAPSHOT_BYTES {
            return;
        }
        let p = self.persistence.as_mut().unwrap();
        if let Some(old) = p.payloads.remove(&name) {
            p.payload_lru.remove(&(old.touched, name.clone()));
            self.stats.snapshot_bytes = self
                .stats
                .snapshot_bytes
                .saturating_sub(encoded_payload_bytes(&name, &old.bytes));
        }
        while self.stats.snapshot_bytes.saturating_add(charge) > SNAPSHOT_BYTES {
            let Some((_, old_name)) = p.payload_lru.pop_first() else {
                break;
            };
            if let Some(old) = p.payloads.remove(&old_name) {
                self.stats.snapshot_bytes = self
                    .stats
                    .snapshot_bytes
                    .saturating_sub(encoded_payload_bytes(&old_name, &old.bytes));
            }
        }
        p.payload_clock = p.payload_clock.wrapping_add(1);
        p.payload_lru.insert((p.payload_clock, name.clone()));
        p.payloads.insert(
            name,
            EncodedPayload {
                bytes,
                touched: p.payload_clock,
            },
        );
        self.stats.snapshot_bytes += charge;
        self.stats.snapshot_complete = false;
    }

    pub fn configure(&mut self, root: &Path, project_identity: &str) {
        let identity = format!("{}\0{project_identity}", root.display());
        if self.configured_identity.as_deref() == Some(&identity) {
            return;
        }
        let _ = self.flush();
        *self = Self::open(root, project_identity);
    }

    /// Includes encoded startup/pending buffers, not only decoded code. Used by
    /// the coordinator's aggregate retained-session budget.
    pub fn resident_bytes(&self) -> usize {
        self.stats
            .resident_bytes
            .saturating_add(self.stats.metadata_bytes)
            .saturating_add(self.stats.snapshot_bytes)
            .saturating_add(self.persistence.as_ref().map_or(0, |p| p.pending_bytes))
    }
    pub fn release_encoded_snapshot(&mut self) {
        let _ = self.flush();
        if let Some(p) = self.persistence.as_mut() {
            p.payloads.clear();
            p.payload_lru.clear();
            p.bulk_read_failed = false;
        }
        self.stats.snapshot_bytes = 0;
        self.stats.snapshot_complete = false;
    }

    /// Release decoded code under aggregate session pressure without losing
    /// procedure identities, fact observations or persisted payload handles.
    /// Future installs still obey the graph's configured resident-byte limit.
    /// Returns the charged decoded bytes released by this call.
    pub fn trim_decoded_to(&mut self, limit: usize) -> usize {
        let before = self.stats.resident_bytes;
        self.trim_to(limit);
        before.saturating_sub(self.stats.resident_bytes)
    }

    pub fn dependencies(&self, key: &ProcKey) -> Option<Arc<[BindingWitness]>> {
        let record = self.records.get(key)?;
        record
            .input
            .candidate(&self.db)
            .as_ref()
            .map(|c| Arc::clone(&c.dependencies))
    }

    pub fn flush(&mut self) -> io::Result<()> {
        let Some(persistence) = self.persistence.as_mut() else {
            return Ok(());
        };
        if persistence.pending.is_empty() {
            return Ok(());
        }
        // Moving the batch avoids retaining a second full pending payload
        // while dm-store creates its checksum-encoded transaction records.
        // A failed optional cache write is discarded: resident code remains
        // usable and missing persisted handles cause ordinary cache misses.
        let pending = std::mem::take(&mut persistence.pending);
        persistence.pending_bytes = 0;
        // Snapshot is a bounded startup view. Successful writes not retained
        // there must remain discoverable if their resident artifact is evicted.
        persistence
            .store
            .put_many(pending.into_iter().collect(), None)?;
        Ok(())
    }

    fn ensure_record(&mut self, key: &ProcKey, descriptor: &ProcDescriptor) -> bool {
        if key.path.len() > 16 * 1024
            || descriptor.body_digest.len() > 256
            || descriptor.frame_digest.len() > 256
        {
            return false;
        }
        if let Some(record) = self.records.get_mut(key) {
            record.active = true;
            if record.descriptor != *descriptor {
                let bytes = (descriptor.body_digest.len() + descriptor.frame_digest.len()) * 4;
                let growth = bytes.saturating_sub(record.descriptor_bytes);
                if self.stats.metadata_bytes.saturating_add(growth) > self.limits.metadata_bytes {
                    return false;
                }
                self.stats.metadata_bytes += growth;
                record.descriptor_bytes = record.descriptor_bytes.max(bytes);
                // Old outputs must cease to be observable immediately, even
                // when lowering the replacement later fails.
                record
                    .input
                    .set_descriptor(&mut self.db)
                    .to(descriptor.clone());
                record.descriptor = descriptor.clone();
            }
            return true;
        }
        let bytes = 512usize
            .saturating_add(key.path.len() * 2)
            .saturating_add(descriptor.body_digest.len() * 4)
            .saturating_add(descriptor.frame_digest.len() * 4);
        if self.stats.procedures >= self.limits.procedures
            || self.stats.metadata_bytes.saturating_add(bytes) > self.limits.metadata_bytes
        {
            return false;
        }
        let input = ProcedureInput::new(&self.db, descriptor.clone(), None, Vec::new());
        self.records.insert(
            key.clone(),
            Record {
                input,
                descriptor: descriptor.clone(),
                facts: BTreeMap::new(),
                witness_bytes: 0,
                resident_bytes: 0,
                artifact: None,
                touched: 0,
                active: true,
                descriptor_bytes: (descriptor.body_digest.len() + descriptor.frame_digest.len())
                    * 4,
            },
        );
        self.stats.procedures += 1;
        self.stats.metadata_bytes += bytes;
        true
    }

    pub fn probe(&mut self, key: &ProcKey, descriptor: &ProcDescriptor) -> ProcedureProbe {
        if !self.ensure_record(key, descriptor) {
            self.stats.misses += 1;
            return ProcedureProbe::Miss;
        }
        let input = self.records[key].input;
        let candidate = current_candidate(&self.db, input);
        if let Some(candidate) = candidate {
            if let Some(decoded) = self.records[key]
                .artifact
                .as_ref()
                .filter(|decoded| decoded.generation == candidate.generation)
            {
                let artifact = decoded.artifact.clone();
                self.touch(key);
                self.stats.resident_hits += 1;
                return ProcedureProbe::Resident(artifact);
            }
            if let Some(disk) = &candidate.disk {
                let disk = disk.clone();
                let dependencies = Arc::clone(&candidate.dependencies);
                if let Some(envelope) = self.load_payload(&disk) {
                    let artifact = ProcedureArtifact::Prepared(Arc::clone(&envelope));
                    let _ = self.install_candidate(
                        key.clone(),
                        descriptor.clone(),
                        dependencies,
                        Some(artifact.clone()),
                        Some(disk.clone()),
                        false,
                    );
                    self.stats.disk_hits += 1;
                    return ProcedureProbe::Resident(artifact);
                }
                self.stats.misses += 1;
                return ProcedureProbe::Miss;
            }
        }
        self.stats.misses += 1;
        ProcedureProbe::Miss
    }

    /// A memo returned by compile_memo has been validated against the current
    /// frozen frame. The descriptor must still be current when workers finish.
    pub fn install(
        &mut self,
        key: ProcKey,
        descriptor: ProcDescriptor,
        memo: Arc<ProcedureMemo>,
        disk: Option<ProcedureMemoRef>,
    ) -> bool {
        let dependencies: Arc<[BindingWitness]> = memo.dependencies.clone().into();
        self.install_candidate(
            key,
            descriptor,
            dependencies,
            Some(ProcedureArtifact::Symbolic(memo)),
            disk,
            false,
        )
    }

    /// Prepared metadata must have empty symbolic code and current relative
    /// statement origins. Absolute DBG locations are applied after this stage.
    pub fn install_prepared(
        &mut self,
        key: ProcKey,
        descriptor: ProcDescriptor,
        envelope: Arc<PreparedProcedureEnvelope>,
        dependencies: Arc<[BindingWitness]>,
        disk: Option<ProcedureMemoRef>,
    ) -> bool {
        if !envelope.metadata.code.items.is_empty() {
            return false;
        }
        if self
            .records
            .get(&key)
            .is_some_and(|r| r.descriptor != descriptor)
        {
            return false;
        }
        let disk = self
            .persist_prepared(&key, &descriptor, &envelope, &dependencies)
            .or(disk);
        self.install_candidate(
            key,
            descriptor,
            dependencies,
            Some(ProcedureArtifact::Prepared(envelope)),
            disk,
            false,
        )
    }

    /// Restore only a compact witness/reference record on cold start. Resolve
    /// actual current facts before trusting persisted witnesses; the producer
    /// must also verify the disk record's checksum and stage fingerprint.
    pub fn restore_disk(
        &mut self,
        key: ProcKey,
        descriptor: ProcDescriptor,
        dependencies: Arc<[BindingWitness]>,
        disk: ProcedureMemoRef,
        mut resolve: impl FnMut(&ProcKey, &BindingFact) -> FactValue,
    ) -> bool {
        if dependencies
            .iter()
            .any(|w| resolve(&key, &w.fact) != w.value)
        {
            return false;
        }
        self.install_candidate(key, descriptor, dependencies, None, Some(disk), false)
    }

    fn install_candidate(
        &mut self,
        key: ProcKey,
        descriptor: ProcDescriptor,
        dependencies: Arc<[BindingWitness]>,
        artifact: Option<ProcedureArtifact>,
        disk: Option<ProcedureMemoRef>,
        untrusted: bool,
    ) -> bool {
        let coherent = dependencies
            .iter()
            .any(|w| w.fact == BindingFact::SharedPresence)
            && dependencies.windows(2).all(|p| p[0].fact < p[1].fact);
        if !coherent
            || disk
                .as_ref()
                .is_some_and(|r| r.key.is_empty() || r.key.len() > 1024)
            || self
                .records
                .get(&key)
                .is_some_and(|r| r.descriptor != descriptor)
            || !self.ensure_record(&key, &descriptor)
        {
            self.stats.refused_installs += 1;
            return false;
        }
        let record = &self.records[&key];
        let new_facts: Vec<_> = dependencies
            .iter()
            .filter(|w| {
                !(if w.fact.is_shared() {
                    self.shared_facts.contains_key(&w.fact)
                } else {
                    record.facts.contains_key(&w.fact)
                })
            })
            .collect();
        let fact_bytes = new_facts.iter().fold(0usize, |n, w| {
            n.saturating_add(192)
                .saturating_add(fact_heap(&w.fact))
                .saturating_add(if untrusted { 0 } else { value_heap(&w.value) })
        });
        let witness_bytes = dependencies
            .iter()
            .fold(
                dependencies.len() * std::mem::size_of::<BindingWitness>() + 128,
                |n, w| {
                    n.saturating_add(fact_heap(&w.fact))
                        .saturating_add(value_heap(&w.value))
                },
            )
            .saturating_add(dependencies.len().saturating_add(3) * QUERY_EDGE_BYTES)
            .saturating_add(disk.as_ref().map_or(0, |r| r.key.len() + 64));
        let mut planned = self
            .stats
            .metadata_bytes
            .saturating_sub(record.witness_bytes)
            .saturating_add(fact_bytes)
            .saturating_add(witness_bytes);
        if !untrusted {
            for w in dependencies.iter() {
                if let Some(fact) = if w.fact.is_shared() {
                    self.shared_facts.get(&w.fact)
                } else {
                    record.facts.get(&w.fact)
                } {
                    if fact.input.value(&self.db).is_none() {
                        planned = planned
                            .saturating_sub(fact.value_bytes)
                            .saturating_add(value_heap(&w.value));
                    }
                }
            }
        }
        if self.stats.facts.saturating_add(new_facts.len()) > self.limits.facts
            || planned > self.limits.metadata_bytes
            || (!untrusted
                && dependencies.iter().any(|w| {
                    (if w.fact.is_shared() {
                        self.shared_facts.get(&w.fact)
                    } else {
                        record.facts.get(&w.fact)
                    })
                    .is_some_and(|f| {
                        f.input
                            .value(&self.db)
                            .as_ref()
                            .is_some_and(|value| value != &w.value)
                    })
                }))
        {
            self.stats.refused_installs += 1;
            if self.stats.refused_installs == 1 || self.stats.refused_installs % 5_000 == 0 {
                self.trace_memory("refused install");
            }
            return false;
        }
        let input = record.input;
        let old_bytes = record.resident_bytes;
        let old_touch = record.touched;
        self.stats.metadata_bytes = planned;
        self.stats.facts += new_facts.len();
        let record = self.records.get_mut(&key).unwrap();
        let mut inputs = Vec::with_capacity(dependencies.len());
        for witness in dependencies.iter() {
            let fact = if witness.fact.is_shared() {
                &mut self.shared_facts
            } else {
                &mut record.facts
            }
            .entry(witness.fact.clone())
            .or_insert_with(|| ObservedFact {
                input: FactInput::new(&self.db, (!untrusted).then(|| witness.value.clone())),
                value_bytes: if untrusted {
                    0
                } else {
                    value_heap(&witness.value)
                },
            });
            if !untrusted && fact.input.value(&self.db).is_none() {
                fact.input
                    .set_value(&mut self.db)
                    .to(Some(witness.value.clone()));
                fact.value_bytes = value_heap(&witness.value);
            }
            inputs.push(fact.input);
        }
        record.witness_bytes = witness_bytes;
        record.resident_bytes = artifact
            .as_ref()
            .map_or(0, ProcedureArtifact::resident_bytes);
        self.stats.resident_bytes = self
            .stats
            .resident_bytes
            .saturating_sub(old_bytes)
            .saturating_add(record.resident_bytes);
        self.lru.remove(&(old_touch, key.clone()));
        // Re-decoding a valid disk payload changes residency only. Keep the
        // tracked identity and fact inputs unchanged so other procedure queries
        // do not need validation merely because code entered/left the LRU.
        let old_candidate = input.candidate(&self.db).as_ref().cloned();
        let candidate = if let Some(old) = old_candidate.as_ref().filter(|old| {
            old.descriptor == descriptor
                && old.dependencies.as_ref() == dependencies.as_ref()
                && old.disk == disk
        }) {
            Arc::clone(old)
        } else {
            Arc::new(Candidate {
                generation: old_candidate.as_ref().map_or(1, |old| {
                    old.generation
                        .checked_add(1)
                        .expect("procedure candidate generation overflow")
                }),
                descriptor,
                dependencies,
                disk,
            })
        };
        if input.facts(&self.db) != &inputs {
            input.set_facts(&mut self.db).to(inputs);
        }
        if old_candidate
            .as_ref()
            .is_none_or(|old| !Arc::ptr_eq(old, &candidate))
        {
            input
                .set_candidate(&mut self.db)
                .to(Some(Arc::clone(&candidate)));
        }
        self.records.get_mut(&key).unwrap().artifact = artifact.map(|artifact| DecodedArtifact {
            generation: candidate.generation,
            artifact,
        });
        let _ = current_candidate(&self.db, input);
        self.stats.installs += 1;
        self.touch(&key);
        self.trim();
        if self.stats.installs % 5_000 == 0 {
            self.trace_memory("install");
        }
        true
    }

    fn trace_memory(&self, stage: &str) {
        if std::env::var_os("DM_BUILD_TRACE").is_none() {
            return;
        }
        let pending_bytes = self.persistence.as_ref().map_or(0, |p| p.pending_bytes);
        eprintln!(
            "DM_BUILD_TRACE procedure graph {stage}: {} procedures, {} facts, {} installs, {} refusals, {} evictions, {} resident bytes, {} metadata bytes, {} snapshot bytes, {} pending bytes, {} prefetch batches, {} single reads",
            self.stats.procedures,
            self.stats.facts,
            self.stats.installs,
            self.stats.refused_installs,
            self.stats.evictions,
            self.stats.resident_bytes,
            self.stats.metadata_bytes,
            self.stats.snapshot_bytes,
            pending_bytes,
            self.stats.prefetch_batches,
            self.stats.payload_single_reads,
        );
    }

    fn persist_prepared(
        &mut self,
        key: &ProcKey,
        descriptor: &ProcDescriptor,
        envelope: &PreparedProcedureEnvelope,
        dependencies: &[BindingWitness],
    ) -> Option<ProcedureMemoRef> {
        self.persistence.as_ref()?;
        let payload = envelope.encode().ok()?;
        if payload.len() > MAX_PAYLOAD {
            return None;
        }
        let name = format!("{:x}", Sha256::digest(&payload));
        let header = serde_json::to_vec(&DiskHeader {
            key: key.clone(),
            descriptor: descriptor.clone(),
            dependencies: dependencies.to_vec(),
            payload: name.clone(),
        })
        .ok()?;
        if header.len() > MAX_HEADER {
            return None;
        }
        let p = self.persistence.as_ref()?;
        let header_name = format!("{:x}", Sha256::digest(serde_json::to_vec(key).ok()?));
        let records = [
            (dm_store::Key::new(&p.payloads_namespace, &name), payload),
            (
                dm_store::Key::new(&p.headers_namespace, header_name),
                header,
            ),
        ];
        let incoming_bytes = records.iter().fold(0usize, |total, (key, bytes)| {
            total.saturating_add(pending_record_bytes(key, bytes))
        });
        if incoming_bytes > PENDING_BYTES {
            return None;
        }
        if p.pending_bytes.saturating_add(incoming_bytes) > PENDING_BYTES
            || p.pending.len().saturating_add(records.len()) > MAX_PENDING_RECORDS
        {
            if self.flush().is_err() {
                // Cache writes are optional. Drop the bounded pending batch if
                // persistence is unavailable, keeping compilation independent.
                let p = self.persistence.as_mut()?;
                p.pending.clear();
                p.pending_bytes = 0;
                return None;
            }
        }
        let p = self.persistence.as_mut()?;
        for (key, bytes) in records {
            let charge = pending_record_bytes(&key, &bytes);
            let previous_charge = p
                .pending
                .get_key_value(&key)
                .map_or(0, |(key, bytes)| pending_record_bytes(key, bytes));
            p.pending_bytes = p.pending_bytes.saturating_add(charge);
            let previous = p.pending.insert(key, bytes);
            if previous.is_some() {
                p.pending_bytes = p.pending_bytes.saturating_sub(previous_charge);
            }
        }
        Some(ProcedureMemoRef { key: name })
    }

    fn load_payload(
        &mut self,
        reference: &ProcedureMemoRef,
    ) -> Option<Arc<PreparedProcedureEnvelope>> {
        let p = self.persistence.as_mut()?;
        let key = dm_store::Key::new(&p.payloads_namespace, &reference.key);
        if !p.pending.contains_key(&key) && !p.payloads.contains_key(&reference.key) {
            if p.bulk_read_failed {
                return None;
            }
            self.stats.payload_single_reads += 1;
            let read =
                match p
                    .store
                    .read_many_bounded(&[key.clone()], MAX_PAYLOAD, MAX_PAYLOAD + 32, None)
                {
                    Ok(mut batch) => batch.values.pop()?,
                    Err(_) => {
                        p.bulk_read_failed = true;
                        return None;
                    }
                };
            self.retain_encoded(reference.key.clone(), read);
        }
        let p = self.persistence.as_mut()?;
        Self::touch_encoded(p, &reference.key);
        let bytes = p
            .pending
            .get(&key)
            .or_else(|| {
                p.payloads
                    .get(&reference.key)
                    .and_then(|payload| payload.bytes.as_ref())
            })?
            .as_slice();
        if bytes.len() > MAX_PAYLOAD || format!("{:x}", Sha256::digest(bytes)) != reference.key {
            self.stats.corrupt_records += 1;
            return None;
        }
        match PreparedProcedureEnvelope::decode(bytes) {
            Ok(envelope) => {
                self.stats.disk_decodes += 1;
                Some(Arc::new(envelope))
            }
            Err(_) => {
                self.stats.corrupt_records += 1;
                None
            }
        }
    }

    /// Call once per changed skeleton, before probing procedures. Body-only
    /// edits reuse the same revision and perform no semantic fact replay.
    /// The resolver must include each procedure's owner/static overlays.
    pub fn refresh_facts(
        &mut self,
        revision: &str,
        mut resolve: impl FnMut(&ProcKey, &BindingFact) -> FactValue,
    ) -> usize {
        if self.revision.as_deref() == Some(revision) {
            return 0;
        }
        let mut changed = 0;
        // Choose an active invocation merely as the adapter's route to the shared
        // snapshot. The fact itself is explicitly declaration-scoped; no local
        // parameter/static overlay may affect these resolutions.
        let mut representatives = BTreeMap::new();
        for (key, record) in &self.records {
            if !record.active {
                continue;
            }
            if let Some(candidate) = record.input.candidate(&self.db).as_ref() {
                for witness in candidate.dependencies.iter().filter(|w| w.fact.is_shared()) {
                    representatives
                        .entry(witness.fact.clone())
                        .or_insert_with(|| key.clone());
                }
            }
        }
        for (fact, observed) in &mut self.shared_facts {
            let Some(key) = representatives.get(fact) else {
                continue;
            };
            self.stats.fact_refreshes += 1;
            let value = resolve(key, fact);
            if observed.input.value(&self.db).as_ref() == Some(&value) {
                continue;
            }
            let bytes = value_heap(&value);
            let total = self
                .stats
                .metadata_bytes
                .saturating_sub(observed.value_bytes)
                .saturating_add(bytes);
            let value = if total <= self.limits.metadata_bytes {
                self.stats.metadata_bytes = total;
                observed.value_bytes = bytes;
                Some(value)
            } else {
                self.stats.metadata_bytes = self
                    .stats
                    .metadata_bytes
                    .saturating_sub(observed.value_bytes);
                observed.value_bytes = 0;
                None
            };
            observed.input.set_value(&mut self.db).to(value);
            changed += 1;
        }
        for (key, record) in &mut self.records {
            if !record.active {
                continue;
            }
            for (fact, observed) in &mut record.facts {
                self.stats.fact_refreshes += 1;
                let value = resolve(key, fact);
                if observed.input.value(&self.db).as_ref() == Some(&value) {
                    continue;
                }
                let bytes = value_heap(&value);
                let total = self
                    .stats
                    .metadata_bytes
                    .saturating_sub(observed.value_bytes)
                    .saturating_add(bytes);
                // An over-budget fact becomes unavailable, forcing a miss;
                // never leave an old value observable as a cache hit.
                let value = if total <= self.limits.metadata_bytes {
                    self.stats.metadata_bytes = total;
                    observed.value_bytes = bytes;
                    Some(value)
                } else {
                    self.stats.metadata_bytes = self
                        .stats
                        .metadata_bytes
                        .saturating_sub(observed.value_bytes);
                    observed.value_bytes = 0;
                    None
                };
                observed.input.set_value(&mut self.db).to(value);
                changed += 1;
            }
        }
        self.revision = Some(revision.to_owned());
        self.stats.changed_facts += changed;
        changed
    }

    fn touch(&mut self, key: &ProcKey) {
        let record = self.records.get_mut(key).unwrap();
        self.lru.remove(&(record.touched, key.clone()));
        self.clock = self.clock.wrapping_add(1);
        record.touched = self.clock;
        if record.resident_bytes != 0 {
            self.lru.insert((self.clock, key.clone()));
        }
    }
    fn trim(&mut self) {
        self.trim_to(self.limits.resident_bytes);
    }
    fn trim_to(&mut self, limit: usize) {
        while self.stats.resident_bytes > limit {
            let Some((_, key)) = self.lru.pop_first() else {
                break;
            };
            self.evict_artifact(&key);
        }
    }
    fn evict_artifact(&mut self, key: &ProcKey) {
        let record = self.records.get_mut(key).unwrap();
        self.stats.resident_bytes = self
            .stats
            .resident_bytes
            .saturating_sub(record.resident_bytes);
        record.resident_bytes = 0;
        self.lru.remove(&(record.touched, key.clone()));
        record.artifact = None;
        self.stats.evictions += 1;
    }

    /// Deletion immediately removes both resident and disk observations. Input
    /// handles remain bounded and stable if that authored proc later returns.
    pub fn remove(&mut self, key: &ProcKey) {
        if !self.records.contains_key(key) {
            return;
        }
        self.evict_artifact(key);
        let record = self.records.get_mut(key).unwrap();
        record.input.set_candidate(&mut self.db).to(None);
        record.input.set_facts(&mut self.db).to(Vec::new());
        let _ = current_candidate(&self.db, record.input);
        // Retain bounded handles, but none of this deleted invocation's facts
        // is current. A re-added body can observe a different subset before a
        // later edit reads one of these dormant facts again.
        for observed in record.facts.values_mut() {
            if observed.input.value(&self.db).is_some() {
                observed.input.set_value(&mut self.db).to(None);
            }
            self.stats.metadata_bytes = self
                .stats
                .metadata_bytes
                .saturating_sub(observed.value_bytes);
            observed.value_bytes = 0;
        }
        self.stats.metadata_bytes = self
            .stats
            .metadata_bytes
            .saturating_sub(record.witness_bytes);
        record.witness_bytes = 0;
        record.active = false;
        let tombstone = self.persistence.as_ref().and_then(|p| {
            let bytes = serde_json::to_vec(key).ok()?;
            let name = format!("{:x}", Sha256::digest(bytes));
            Some(dm_store::Key::new(&p.headers_namespace, name))
        });
        if let Some(key) = tombstone {
            let charge = pending_record_bytes(&key, &Vec::new());
            let needs_flush = self.persistence.as_ref().is_some_and(|p| {
                p.pending_bytes.saturating_add(charge) > PENDING_BYTES
                    || p.pending.len().saturating_add(1) > MAX_PENDING_RECORDS
            });
            if needs_flush && self.flush().is_err() {
                return;
            }
            let p = self.persistence.as_mut().unwrap();
            let previous_charge = p
                .pending
                .get_key_value(&key)
                .map_or(0, |(key, bytes)| pending_record_bytes(key, bytes));
            p.pending.insert(key, Vec::new());
            p.pending_bytes = p
                .pending_bytes
                .saturating_sub(previous_charge)
                .saturating_add(charge);
        }
    }
    pub fn retain_keys(&mut self, keys: &BTreeSet<ProcKey>) {
        let removed: Vec<_> = self
            .records
            .iter()
            .filter(|(key, record)| record.active && !keys.contains(*key))
            .map(|(key, _)| key.clone())
            .collect();
        for key in removed {
            self.remove(&key);
        }
    }
}
impl Drop for ProjectProcedureGraph {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trim_decoded_releases_last_query_arc_without_erasing_fact_tracking() {
        let mut graph = ProjectProcedureGraph::default();
        let key = ProcKey {
            path: "/proc/trim".into(),
            occurrence: 0,
        };
        let descriptor = ProcDescriptor {
            body_digest: "body".into(),
            frame_digest: "frame".into(),
        };
        let envelope = Arc::new(
            PreparedProcedureEnvelope::prepare(&dm_codegen_byond::SimpleProc::default()).unwrap(),
        );
        let weak = Arc::downgrade(&envelope);
        let dependencies: Arc<[BindingWitness]> = vec![BindingWitness {
            fact: BindingFact::SharedPresence,
            value: FactValue::Boolean(true),
        }]
        .into();
        graph.refresh_facts("initial", |_, _| FactValue::Boolean(true));
        assert!(graph.install_prepared(key.clone(), descriptor, envelope, dependencies, None,));
        let before = graph.stats().resident_bytes;
        let revision = salsa::plumbing::current_revision(&graph.db);
        let candidate = current_candidate(&graph.db, graph.records[&key].input)
            .clone()
            .unwrap();
        assert!(before > 0);
        assert!(weak.upgrade().is_some());
        assert_eq!(graph.trim_decoded_to(0), before);
        assert_eq!(graph.stats().resident_bytes, 0);
        assert_eq!(
            salsa::plumbing::current_revision(&graph.db),
            revision,
            "code eviction must not advance the semantic query revision"
        );
        assert!(Arc::ptr_eq(
            &candidate,
            current_candidate(&graph.db, graph.records[&key].input)
                .as_ref()
                .unwrap()
        ));
        assert!(
            weak.upgrade().is_none(),
            "the semantic query must not own the evicted code"
        );
        assert_eq!(graph.stats().procedures, 1);
        assert_eq!(graph.stats().facts, 1);
        assert_eq!(graph.dependencies(&key).unwrap().len(), 1);
        assert_eq!(
            graph.refresh_facts("changed", |_, _| FactValue::Boolean(false)),
            1
        );
    }

    #[test]
    fn bulk_refill_after_pressure_trim_avoids_per_procedure_reads_and_query_writes() {
        let root = std::env::temp_dir().join(format!(
            "dm-graph-bulk-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
        ));
        let descriptor = ProcDescriptor {
            body_digest: "body".into(),
            frame_digest: "frame".into(),
        };
        let dependencies: Arc<[BindingWitness]> = vec![BindingWitness {
            fact: BindingFact::SharedPresence,
            value: FactValue::Boolean(true),
        }]
        .into();
        let mut graph = ProjectProcedureGraph::open(&root, "bulk-test");
        let keys: Vec<_> = (0..32)
            .map(|i| ProcKey {
                path: format!("/proc/p{i}"),
                occurrence: 0,
            })
            .collect();
        for (i, key) in keys.iter().enumerate() {
            let simple = dm_codegen_byond::SimpleProc {
                strings: vec![format!("payload-{i}")],
                ..Default::default()
            };
            assert!(graph.install_prepared(
                key.clone(),
                descriptor.clone(),
                Arc::new(PreparedProcedureEnvelope::prepare(&simple).unwrap()),
                Arc::clone(&dependencies),
                None
            ));
        }
        graph.flush().unwrap();
        graph.trim_decoded_to(0);
        graph.release_encoded_snapshot();
        assert_eq!(graph.stats().snapshot_bytes, 0);
        let revision = salsa::plumbing::current_revision(&graph.db);
        assert_eq!(graph.prefetch(&keys).unwrap(), keys.len());
        assert_eq!(graph.stats().prefetch_batches, 1);
        let charged = graph.stats().snapshot_bytes;
        assert!(charged > 0 && charged <= SNAPSHOT_BYTES);
        for (i, key) in keys.iter().enumerate() {
            let ProcedureProbe::Resident(ProcedureArtifact::Prepared(envelope)) =
                graph.probe(key, &descriptor)
            else {
                panic!("prefetched payload must restore without individual store reads");
            };
            assert_eq!(envelope.metadata.strings, [format!("payload-{i}")]);
        }
        assert_eq!(graph.stats().payload_single_reads, 0);
        assert_eq!(
            salsa::plumbing::current_revision(&graph.db),
            revision,
            "restoring identical code must not mutate semantic inputs"
        );
        graph.trim_decoded_to(0);
        assert_eq!(
            graph.prefetch(&keys).unwrap(),
            0,
            "existing encoded rows need no disk refill"
        );
        assert_eq!(graph.stats().prefetch_batches, 1);
        assert_eq!(graph.stats().snapshot_bytes, charged);
        let missing = ProcKey {
            path: "/proc/missing-payload".into(),
            occurrence: 0,
        };
        assert!(graph.restore_disk(
            missing.clone(),
            descriptor.clone(),
            dependencies,
            ProcedureMemoRef {
                key: "0".repeat(64)
            },
            |_, _| FactValue::Boolean(true)
        ));
        assert_eq!(graph.prefetch(std::slice::from_ref(&missing)).unwrap(), 0);
        for _ in 0..3 {
            assert!(matches!(
                graph.probe(&missing, &descriptor),
                ProcedureProbe::Miss
            ));
        }
        assert_eq!(
            graph.stats().payload_single_reads,
            0,
            "a missing row in a successful bulk read must not reopen the store"
        );
        graph.refresh_facts("removed", |_, _| FactValue::Boolean(false));
        assert!(
            matches!(graph.probe(&keys[0], &descriptor), ProcedureProbe::Miss),
            "prefetched bytes cannot bypass witness validation"
        );
        drop(graph);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn prepared_candidate_tracks_positive_and_negative_facts_and_rejects_stale_install() {
        let mut graph = ProjectProcedureGraph::default();
        let key = ProcKey {
            path: "/proc/read".into(),
            occurrence: 0,
        };
        let descriptor = ProcDescriptor {
            body_digest: "body-a".into(),
            frame_digest: "frame".into(),
        };
        let envelope = Arc::new(
            PreparedProcedureEnvelope::prepare(&dm_codegen_byond::SimpleProc::default()).unwrap(),
        );
        let dependencies: Arc<[BindingWitness]> = vec![
            BindingWitness {
                fact: BindingFact::Field("missing".into()),
                value: FactValue::Boolean(false),
            },
            BindingWitness {
                fact: BindingFact::Field("present".into()),
                value: FactValue::Boolean(true),
            },
            BindingWitness {
                fact: BindingFact::SharedPresence,
                value: FactValue::Boolean(true),
            },
        ]
        .into();
        let resolve = |present: bool, missing: bool, fact: &BindingFact| match fact {
            BindingFact::Field(name) if name == "present" => FactValue::Boolean(present),
            BindingFact::Field(name) if name == "missing" => FactValue::Boolean(missing),
            BindingFact::SharedPresence => FactValue::Boolean(true),
            _ => panic!("unexpected observed fact: {fact:?}"),
        };
        graph.refresh_facts("initial", |_, fact| resolve(true, false, fact));
        assert!(graph.install_prepared(
            key.clone(),
            descriptor.clone(),
            Arc::clone(&envelope),
            Arc::clone(&dependencies),
            None
        ));
        for _ in 0..2 {
            let ProcedureProbe::Resident(ProcedureArtifact::Prepared(hit)) =
                graph.probe(&key, &descriptor)
            else {
                panic!("unchanged descriptor and facts must reuse the prepared candidate");
            };
            assert!(Arc::ptr_eq(&hit, &envelope));
        }

        assert_eq!(
            graph.refresh_facts("positive-removed", |_, fact| resolve(false, false, fact)),
            1
        );
        assert!(matches!(
            graph.probe(&key, &descriptor),
            ProcedureProbe::Miss
        ));
        assert_eq!(
            graph.refresh_facts("positive-restored", |_, fact| resolve(true, false, fact)),
            1
        );
        assert!(matches!(
            graph.probe(&key, &descriptor),
            ProcedureProbe::Resident(_)
        ));
        assert_eq!(
            graph.refresh_facts("negative-became-present", |_, fact| resolve(
                true, true, fact
            )),
            1
        );
        assert!(matches!(
            graph.probe(&key, &descriptor),
            ProcedureProbe::Miss
        ));
        graph.refresh_facts("negative-restored", |_, fact| resolve(true, false, fact));

        let current = ProcDescriptor {
            body_digest: "body-b".into(),
            ..descriptor.clone()
        };
        assert!(matches!(graph.probe(&key, &current), ProcedureProbe::Miss));
        assert!(
            !graph.install_prepared(key.clone(), descriptor, envelope, dependencies, None),
            "the completed body-a job must not replace the current body-b input"
        );
        assert!(matches!(graph.probe(&key, &current), ProcedureProbe::Miss));
    }

    #[test]
    fn readded_procedure_can_populate_dormant_facts_but_cannot_overwrite_current_values() {
        let mut graph = ProjectProcedureGraph::default();
        let key = ProcKey {
            path: "/proc/readded".into(),
            occurrence: 0,
        };
        let descriptor = ProcDescriptor {
            body_digest: "old".into(),
            frame_digest: "frame".into(),
        };
        let envelope = Arc::new(
            PreparedProcedureEnvelope::prepare(&dm_codegen_byond::SimpleProc::default()).unwrap(),
        );
        let shared = BindingWitness {
            fact: BindingFact::SharedPresence,
            value: FactValue::Boolean(true),
        };
        let old_dependencies: Arc<[BindingWitness]> = vec![
            BindingWitness {
                fact: BindingFact::FieldType("dormant".into()),
                value: FactValue::Text("/old".into()),
            },
            shared.clone(),
        ]
        .into();
        assert!(graph.install_prepared(
            key.clone(),
            descriptor.clone(),
            Arc::clone(&envelope),
            Arc::clone(&old_dependencies),
            None
        ));
        let charged = graph.stats().metadata_bytes;
        graph.remove(&key);
        assert!(graph.stats().metadata_bytes < charged);
        assert_eq!(
            graph.stats().facts,
            2,
            "deleted input handles still count toward the bound"
        );
        assert_eq!(
            graph.refresh_facts("changed-while-deleted", |_, _| panic!(
                "inactive facts must not be replayed"
            )),
            0
        );

        let no_read = ProcDescriptor {
            body_digest: "without-dormant-read".into(),
            ..descriptor.clone()
        };
        assert!(matches!(graph.probe(&key, &no_read), ProcedureProbe::Miss));
        assert!(graph.install_prepared(
            key.clone(),
            no_read,
            Arc::clone(&envelope),
            vec![shared.clone()].into(),
            None
        ));

        let current = ProcDescriptor {
            body_digest: "reads-dormant-again".into(),
            ..descriptor
        };
        assert!(matches!(graph.probe(&key, &current), ProcedureProbe::Miss));
        let current_dependencies: Arc<[BindingWitness]> = vec![
            BindingWitness {
                fact: BindingFact::FieldType("dormant".into()),
                value: FactValue::Text("/new".into()),
            },
            shared,
        ]
        .into();
        assert!(graph.install_prepared(
            key.clone(),
            current.clone(),
            Arc::clone(&envelope),
            current_dependencies,
            None
        ));
        assert_eq!(
            graph.stats().facts,
            2,
            "re-addition must reuse the bounded fact handles"
        );
        assert!(matches!(
            graph.probe(&key, &current),
            ProcedureProbe::Resident(_)
        ));
        assert!(
            !graph.install_prepared(
                key.clone(),
                current.clone(),
                envelope,
                old_dependencies,
                None
            ),
            "a fresh install cannot overwrite a conflicting available fact"
        );
        assert!(matches!(
            graph.probe(&key, &current),
            ProcedureProbe::Resident(_)
        ));
    }
}
