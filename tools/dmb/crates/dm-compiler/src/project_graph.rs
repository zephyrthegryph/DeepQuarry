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
#[path = "project_graph_dag.rs"]
mod dag;

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
    pub invalidated_procedures: usize,
    pub metadata_nodes_rebuilt: usize,
    pub metadata_bytes_rebuilt: usize,
    pub header_read_batches: usize,
    pub identity_probes: usize,
    pub prepared_header_seconds: f64,
    pub fact_refresh_seconds: f64,
    pub identity_probe_seconds: f64,
    pub prepared_persist_seconds: f64,
    pub candidate_install_seconds: f64,
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
    #[serde(default)]
    dependencies: Vec<BindingWitness>,
    #[serde(default)]
    readset: Option<String>,
    payload: String,
}
#[derive(Serialize, Deserialize)]
struct DiskReadSet { witnesses: Vec<(String, String)> }
#[derive(Default)]
struct DecodedDagNodes {
    facts: BTreeMap<String, FactId>,
    values: BTreeMap<String, Arc<FactValue>>,
    bytes: usize,
}
struct Persistence {
    store: dm_store::Store,
    headers_namespace: String,
    payloads_namespace: String,
    readsets_namespace: String,
    facts_namespace: String,
    values_namespace: String,
    headers_seen: BTreeSet<ProcKey>,
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
    value: Option<Arc<FactValue>>,
}
type FactId = u32;
#[derive(Clone, Eq, PartialEq)]
struct CompactWitness { fact: FactId, value: Arc<FactValue> }
#[derive(Clone, Eq, PartialEq)]
struct Candidate {
    generation: u64,
    descriptor: ProcDescriptor,
    dependencies: Arc<[CompactWitness]>,
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
    id: u32,
    input: ProcedureInput,
    descriptor: ProcDescriptor,
    facts: BTreeMap<FactId, ObservedFact>,
    witness_bytes: usize,
    resident_bytes: usize,
    artifact: Option<DecodedArtifact>,
    touched: u64,
    active: bool,
    descriptor_bytes: usize,
}

struct ValidatedCertificate {
    id: u32,
    descriptor: ProcDescriptor,
    disk: ProcedureMemoRef,
    facts: Vec<FactId>,
    valid: bool,
}

/// One graph per project/worktree session. The shared disk cache remains
/// content addressed; this live graph tracks the worktree's current facts.
pub struct ProjectProcedureGraph {
    db: Database,
    records: BTreeMap<ProcKey, Record>,
    certificates: BTreeMap<ProcKey, ValidatedCertificate>,
    /// Declaration-scoped observations have one Salsa input across all procedures.
    shared_facts: BTreeMap<FactId, ObservedFact>,
    fact_ids: BTreeMap<Arc<BindingFact>, FactId>,
    fact_names: Vec<Arc<BindingFact>>,
    values: BTreeMap<Vec<u8>, Arc<FactValue>>,
    reverse: BTreeMap<FactId, BTreeSet<u32>>,
    procedure_names: Vec<ProcKey>,
    readsets: BTreeMap<Vec<(FactId, usize)>, std::sync::Weak<[CompactWitness]>>,
    decoded_nodes: DecodedDagNodes,
    dirty: BTreeSet<ProcKey>,
    pending_shared: BTreeSet<FactId>,
    pending_private: BTreeSet<(u32, FactId)>,
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
            certificates: BTreeMap::new(),
            shared_facts: BTreeMap::new(),
            fact_ids: BTreeMap::new(), fact_names: Vec::new(), values: BTreeMap::new(),
            reverse: BTreeMap::new(), dirty: BTreeSet::new(), procedure_names: Vec::new(), readsets: BTreeMap::new(), decoded_nodes: DecodedDagNodes::default(),
            pending_shared: BTreeSet::new(), pending_private: BTreeSet::new(),
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
        graph.persistence = Some(Persistence {
            store,
            headers_namespace,
            payloads_namespace,
            readsets_namespace: format!("graph-readsets-v2-{DISK_STAGE}"),
            facts_namespace: format!("graph-facts-v2-{DISK_STAGE}"),
            values_namespace: format!("graph-values-v2-{DISK_STAGE}"),
            headers_seen: BTreeSet::new(),
            payloads: BTreeMap::new(),
            payload_lru: BTreeSet::new(),
            payload_clock: 0,
            bulk_read_failed: false,
            pending: BTreeMap::new(),
            pending_bytes: 0,
        });
        // Restored inputs deliberately start unavailable. The adapter must
        // refresh against its current skeleton before any cached result is used.
        graph.revision = None;
        // Payloads are fetched in bounded caller-supplied source order. Eager
        // loading here would retain arbitrary manifest order before emission.
        graph.trace_memory("startup");
        graph
    }

    pub fn known_keys(&self) -> impl Iterator<Item = &ProcKey> {
        self.records.keys().chain(self.certificates.keys())
    }
    pub fn observed_facts(&self) -> impl Iterator<Item = &BindingFact> {
        self.reverse.iter().filter(|(_, readers)| readers.iter().any(|id| {
            let key = &self.procedure_names[*id as usize];
            self.records.get(key).is_some_and(|record| record.active)
                || self.certificates.contains_key(key)
        })).map(|(id, _)| self.fact_names[*id as usize].as_ref())
    }

    /// Read nearby portable payloads in caller-supplied emission order. This
    /// fetches bytes only: probe still validates the current descriptor/facts.
    /// Refills an encoded LRU after pressure trimming instead of reopening the
    /// store for each procedure. Errors are optional cache misses at the caller.
    pub fn prefetch(&mut self, keys: &[ProcKey]) -> io::Result<usize> {
        let mut names = Vec::new();
        let mut seen = BTreeSet::new();
        for key in keys {
            if let Some(certificate) = self.certificates.get(key).filter(|c| c.valid) {
                if seen.insert(certificate.disk.key.as_str()) {
                    names.push(certificate.disk.key.clone());
                }
                continue;
            }
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
            .saturating_add((self.pending_shared.len()+self.pending_private.len()).saturating_mul(64))
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

    /// Drop optional interning/restore indexes without dropping live query
    /// witnesses. Candidates and Salsa inputs retain their immutable payloads;
    /// subsequent installs can rebuild these acceleration indexes on demand.
    pub fn trim_metadata_accelerators(&mut self) -> usize {
        let before = self.stats.metadata_bytes;
        let mut freed = self.decoded_nodes.bytes;
        self.decoded_nodes = DecodedDagNodes::default();
        for (key, value) in &self.values {
            freed = freed.saturating_add(key.capacity() + 96);
            if Arc::strong_count(value) == 1 {
                freed = freed.saturating_add(value_heap(value));
            }
        }
        self.values.clear();
        for (key, value) in &self.readsets {
            freed = freed.saturating_add(
                key.capacity() * std::mem::size_of::<(FactId, usize)>() + 96,
            );
            if value.strong_count() == 0 {
                freed = freed.saturating_add(
                    key.len() * std::mem::size_of::<CompactWitness>(),
                );
            }
        }
        self.readsets.clear();
        self.stats.metadata_bytes = self.stats.metadata_bytes.saturating_sub(freed);
        before.saturating_sub(self.stats.metadata_bytes)
    }

    /// Publication pressure tier: retain validated disk identities and compact
    /// dependency edges, restoring exact witness pages only for affected readers.
    pub fn compact_validated_candidates(&mut self) -> usize {
        if self.persistence.is_none() || self.flush().is_err() { return 0; }
        let before = self.resident_bytes();
        for (key, record) in &self.records {
            if !record.active { continue; }
            let Some(candidate) = current_candidate(&self.db, record.input) else { continue; };
            let Some(disk) = candidate.disk.clone() else { continue; };
            self.certificates.insert(key.clone(), ValidatedCertificate {
                id: record.id, descriptor: candidate.descriptor.clone(), disk,
                facts: candidate.dependencies.iter().map(|w| w.fact).collect(), valid: true,
            });
        }
        let live: BTreeSet<_> = self.certificates.values().map(|c| c.id).collect();
        self.reverse.retain(|_, readers| { readers.retain(|id| live.contains(id)); !readers.is_empty() });
        self.records.clear(); self.shared_facts.clear(); self.values.clear(); self.readsets.clear();
        self.decoded_nodes = DecodedDagNodes::default();
        self.pending_shared.clear(); self.pending_private.clear(); self.lru.clear(); self.dirty.clear();
        self.db = Database::default();
        self.stats.resident_bytes = 0;
        self.stats.facts = 0;
        self.stats.procedures = self.certificates.len();
        self.stats.metadata_bytes = self.certificates.iter().map(|(key,c)|
            512 + key.path.capacity() + c.descriptor.body_digest.capacity()
                + c.descriptor.frame_digest.capacity() + c.disk.key.capacity()
                + c.facts.capacity()*std::mem::size_of::<FactId>()).sum::<usize>()
            + self.fact_names.iter().map(|fact| fact_heap(fact)+96).sum::<usize>()
            + self.reverse.values().map(|readers| 96+readers.len()*64).sum::<usize>()
            + self.procedure_names.iter().map(|key| key.path.capacity()+96).sum::<usize>();
        before.saturating_sub(self.resident_bytes())
    }

    fn restore_certificate_readers(&mut self, ids: &BTreeSet<FactId>) {
        let readers: BTreeSet<_> = ids.iter().flat_map(|id| self.reverse.get(id).into_iter().flatten()).copied().collect();
        let keys: Vec<_> = readers.into_iter().filter_map(|id| {
            let key = self.procedure_names[id as usize].clone();
            let certificate = self.certificates.get_mut(&key)?;
            certificate.valid = false;
            Some(key)
        }).collect();
        if let Some(p) = self.persistence.as_mut() {
            for key in &keys { p.headers_seen.remove(key); }
        }
        // Failed or corrupt reads leave revoked certificates, forcing lowering.
        let _ = self.prepare_keys(&keys);
    }

    pub fn dependencies(&self, key: &ProcKey) -> Option<Arc<[BindingWitness]>> {
        let record = self.records.get(key)?;
        record
            .input
            .candidate(&self.db)
            .as_ref()
            .map(|c| c.dependencies.iter().map(|w| BindingWitness {
                fact: (*self.fact_names[w.fact as usize]).clone(),
                value: (*w.value).clone(),
            }).collect::<Vec<_>>().into())
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
                self.stats.metadata_bytes += growth;
                self.stats.metadata_nodes_rebuilt += 1;
                self.stats.metadata_bytes_rebuilt += descriptor.body_digest.len()+descriptor.frame_digest.len();
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
        if self.stats.procedures >= self.limits.procedures {
            return false;
        }
        let input = ProcedureInput::new(&self.db, descriptor.clone(), None, Vec::new());
        let id = if let Some(certificate) = self.certificates.remove(key) {
            self.stats.procedures = self.stats.procedures.saturating_sub(1);
            self.stats.metadata_bytes = self.stats.metadata_bytes.saturating_sub(
                512 + key.path.capacity() + certificate.descriptor.body_digest.capacity()
                    + certificate.descriptor.frame_digest.capacity() + certificate.disk.key.capacity()
                    + certificate.facts.capacity()*std::mem::size_of::<FactId>(),
            );
            for fact in certificate.facts {
                if let Some(readers) = self.reverse.get_mut(&fact) { readers.remove(&certificate.id); }
            }
            certificate.id
        } else {
            let id = u32::try_from(self.procedure_names.len()).expect("procedure index exceeds address space");
            self.procedure_names.push(key.clone()); id
        };
        self.records.insert(
            key.clone(),
            Record {
                id,
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
        self.stats.metadata_nodes_rebuilt += 1;
        self.stats.metadata_bytes_rebuilt += bytes;
        true
    }

    pub fn probe(&mut self, key: &ProcKey, descriptor: &ProcDescriptor) -> ProcedureProbe {
        if let Some(disk) = self.certificates.get(key).filter(|c| c.valid && &c.descriptor == descriptor).map(|c| c.disk.clone()) {
            if let Some(envelope) = self.load_payload(&disk) {
                self.stats.disk_hits += 1;
                return ProcedureProbe::Resident(ProcedureArtifact::Prepared(envelope));
            }
            if let Some(certificate) = self.certificates.get_mut(key) { certificate.valid = false; }
            self.stats.misses += 1;
            return ProcedureProbe::Miss;
        }
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
                let generation = candidate.generation;
                if let Some(envelope) = self.load_payload(&disk) {
                    let artifact = ProcedureArtifact::Prepared(Arc::clone(&envelope));
                    // Residency never mutates semantic candidates or rebuilds
                    // a portable readset. Its exact candidate was just checked.
                    let record = self.records.get_mut(key).unwrap();
                    self.stats.resident_bytes = self.stats.resident_bytes.saturating_sub(record.resident_bytes);
                    record.resident_bytes = artifact.resident_bytes();
                    self.stats.resident_bytes += record.resident_bytes;
                    record.artifact = Some(DecodedArtifact { generation, artifact: artifact.clone() });
                    self.touch(key);
                    self.trim();
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
        let persisted = std::time::Instant::now();
        let disk = self
            .persist_prepared(&key, &descriptor, &envelope, &dependencies)
            .or(disk);
        self.stats.prepared_persist_seconds += persisted.elapsed().as_secs_f64();
        let installed = std::time::Instant::now();
        let result = self.install_candidate(
            key,
            descriptor,
            dependencies,
            Some(ProcedureArtifact::Prepared(envelope)),
            disk,
            false,
        );
        self.stats.candidate_install_seconds += installed.elapsed().as_secs_f64();
        result
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

    fn intern_fact(&mut self, fact: &BindingFact) -> FactId {
        if let Some(id) = self.fact_ids.get(fact) { return *id; }
        let id = u32::try_from(self.fact_names.len()).expect("semantic fact index exceeds address space");
        let fact = Arc::new(fact.clone());
        self.stats.metadata_bytes += fact_heap(&fact)+96;
        self.stats.metadata_nodes_rebuilt += 1;
        self.stats.metadata_bytes_rebuilt += fact_heap(&fact)+96;
        self.fact_ids.insert(Arc::clone(&fact), id);
        self.fact_names.push(fact);
        id
    }
    fn intern_value(&mut self, value: &FactValue) -> Arc<FactValue> {
        let key = serde_json::to_vec(value).expect("semantic value serialization");
        if let Some(value) = self.values.get(&key) { return Arc::clone(value); }
        let value = Arc::new(value.clone());
        self.stats.metadata_bytes += key.capacity()+value_heap(&value)+96;
        self.stats.metadata_nodes_rebuilt += 1;
        self.stats.metadata_bytes_rebuilt += key.capacity()+value_heap(&value)+96;
        self.values.insert(key, Arc::clone(&value));
        value
    }

    fn install_candidate(
        &mut self, key: ProcKey, descriptor: ProcDescriptor,
        dependencies: Arc<[BindingWitness]>, artifact: Option<ProcedureArtifact>,
        disk: Option<ProcedureMemoRef>, untrusted: bool,
    ) -> bool {
        let coherent = dependencies.iter().any(|w| w.fact == BindingFact::SharedPresence)
            && dependencies.windows(2).all(|p| p[0].fact < p[1].fact);
        if !coherent || disk.as_ref().is_some_and(|r| r.key.is_empty() || r.key.len()>1024)
            || self.records.get(&key).is_some_and(|r| r.descriptor != descriptor)
            || !self.ensure_record(&key, &descriptor) {
            self.stats.refused_installs += 1;
            return false;
        }
        let compact: Vec<CompactWitness> = dependencies.iter().map(|w| {
            CompactWitness { fact: self.intern_fact(&w.fact), value: self.intern_value(&w.value) }
        }).collect();
        let readset_key: Vec<_> = compact.iter().map(|w| (w.fact, Arc::as_ptr(&w.value) as usize)).collect();
        let dependencies: Arc<[CompactWitness]> = if let Some(shared) = self.readsets.get(&readset_key).and_then(std::sync::Weak::upgrade) { shared }
            else {
                if let Some((old_key, _)) = self.readsets.remove_entry(&readset_key) {
                    self.stats.metadata_bytes = self.stats.metadata_bytes.saturating_sub(old_key.capacity()*std::mem::size_of::<(FactId,usize)>()+old_key.len()*std::mem::size_of::<CompactWitness>()+96);
                }
                let shared: Arc<[CompactWitness]> = compact.into();
                self.stats.metadata_bytes += readset_key.capacity()*std::mem::size_of::<(FactId,usize)>()+shared.len()*std::mem::size_of::<CompactWitness>()+96;
                self.readsets.insert(readset_key, Arc::downgrade(&shared)); shared
            };
        // Available facts certify the current revision. An asynchronous lowering
        // result cannot overwrite a conflicting positive OR negative observation.
        if !untrusted && dependencies.iter().any(|w| {
            let facts = if self.fact_names[w.fact as usize].is_shared() { &self.shared_facts } else { &self.records[&key].facts };
            facts.get(&w.fact).is_some_and(|f| f.input.value(&self.db).as_ref().is_some_and(|value| value != &w.value))
        }) {
            self.stats.refused_installs += 1;
            return false;
        }
        let input = self.records[&key].input;
        let procedure_id = self.records[&key].id;
        self.clear_pending_private(procedure_id);
        let old_candidate = input.candidate(&self.db).as_ref().cloned();
        let mut inputs = Vec::with_capacity(dependencies.len());
        for witness in dependencies.iter() {
            let facts = if self.fact_names[witness.fact as usize].is_shared() { &mut self.shared_facts }
                else { &mut self.records.get_mut(&key).unwrap().facts };
            let fact = facts.entry(witness.fact).or_insert_with(|| {
                self.stats.facts += 1;
                self.stats.metadata_bytes += 64;
                ObservedFact { input: FactInput::new(&self.db, (!untrusted).then(|| Arc::clone(&witness.value))), value_bytes: 0 }
            });
            if !untrusted && fact.input.value(&self.db).is_none() {
                fact.input.set_value(&mut self.db).to(Some(Arc::clone(&witness.value)));
            }
            if fact.input.value(&self.db).is_none() {
                if self.fact_names[witness.fact as usize].is_shared() { self.pending_shared.insert(witness.fact); }
                else { self.pending_private.insert((procedure_id,witness.fact)); }
            } else {
                if self.fact_names[witness.fact as usize].is_shared() { self.pending_shared.remove(&witness.fact); }
                else { self.pending_private.remove(&(procedure_id,witness.fact)); }
            }
            inputs.push(fact.input);
        }
        let candidate = if let Some(old) = old_candidate.as_ref().filter(|old| old.descriptor == descriptor && old.dependencies == dependencies && old.disk == disk) {
            Arc::clone(old)
        } else {
            if let Some(old) = &old_candidate { for witness in old.dependencies.iter() {
                if let Some(readers) = self.reverse.get_mut(&witness.fact) { readers.remove(&procedure_id); }
            } }
            for witness in dependencies.iter() { self.reverse.entry(witness.fact).or_default().insert(procedure_id); }
            self.stats.metadata_nodes_rebuilt += 1;
            self.stats.metadata_bytes_rebuilt += std::mem::size_of::<Candidate>()+descriptor.body_digest.len()+descriptor.frame_digest.len();
            Arc::new(Candidate { generation: old_candidate.as_ref().map_or(1, |old| old.generation.checked_add(1).expect("candidate generation overflow")), descriptor, dependencies, disk })
        };
        let witness_bytes = candidate.dependencies.len()*(std::mem::size_of::<FactInput>()+QUERY_EDGE_BYTES+32)+128
            +candidate.disk.as_ref().map_or(0, |r| r.key.len()+64);
        let record = self.records.get_mut(&key).unwrap();
        self.stats.metadata_bytes = self.stats.metadata_bytes.saturating_sub(record.witness_bytes)+witness_bytes;
        record.witness_bytes = witness_bytes;
        self.stats.resident_bytes = self.stats.resident_bytes.saturating_sub(record.resident_bytes);
        record.resident_bytes = artifact.as_ref().map_or(0, ProcedureArtifact::resident_bytes);
        self.stats.resident_bytes += record.resident_bytes;
        self.lru.remove(&(record.touched, key.clone()));
        if input.facts(&self.db) != &inputs { input.set_facts(&mut self.db).to(inputs); }
        if old_candidate.as_ref().is_none_or(|old| !Arc::ptr_eq(old, &candidate)) {
            input.set_candidate(&mut self.db).to(Some(Arc::clone(&candidate)));
        }
        record.artifact = artifact.map(|artifact| DecodedArtifact { generation: candidate.generation, artifact });
        self.dirty.remove(&key);
        let _ = current_candidate(&self.db, input);
        self.stats.installs += 1;
        // Full interner collection is linear in the graph. Geometric cold
        // thresholds keep total collection work linear rather than rescanning
        // a growing project once every 64 installed procedures.
        if self.stats.installs.is_power_of_two() && self.stats.installs >= 1024 {
            self.collect_unused_interns();
        }
        self.touch(&key);
        self.trim();
        true
    }

    fn collect_unused_interns(&mut self) {
        let mut freed = 0usize;
        self.readsets.retain(|key, value| {
            let live = value.strong_count() != 0;
            if !live { freed += key.capacity()*std::mem::size_of::<(FactId,usize)>()+key.len()*std::mem::size_of::<CompactWitness>()+96; }
            live
        });
        self.values.retain(|key, value| {
            let live = Arc::strong_count(value)>1;
            if !live { freed += key.capacity()+value_heap(value)+96; }
            live
        });
        self.stats.metadata_bytes = self.stats.metadata_bytes.saturating_sub(freed);
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
        let p = self.persistence.as_ref()?;
        let mut records = Vec::new();
        let mut witnesses = Vec::with_capacity(dependencies.len());
        for witness in dependencies {
            let fact = serde_json::to_vec(&witness.fact).ok()?;
            let value = serde_json::to_vec(&witness.value).ok()?;
            let fact_name = format!("{:x}", Sha256::digest(&fact));
            let value_name = format!("{:x}", Sha256::digest(&value));
            records.push((dm_store::Key::new(&p.facts_namespace, &fact_name), fact));
            records.push((dm_store::Key::new(&p.values_namespace, &value_name), value));
            witnesses.push((fact_name, value_name));
        }
        let readset = serde_json::to_vec(&DiskReadSet { witnesses }).ok()?;
        let readset_name = format!("{:x}", Sha256::digest(&readset));
        records.push((dm_store::Key::new(&p.readsets_namespace, &readset_name), readset));
        let header = serde_json::to_vec(&DiskHeader {
            key: key.clone(),
            descriptor: descriptor.clone(),
            dependencies: Vec::new(),
            readset: Some(readset_name),
            payload: name.clone(),
        })
        .ok()?;
        if header.len() > MAX_HEADER {
            return None;
        }
        let p = self.persistence.as_ref()?;
        let header_name = format!("{:x}", Sha256::digest(serde_json::to_vec(key).ok()?));
        records.push((dm_store::Key::new(&p.payloads_namespace, &name), payload));
        records.push((
                dm_store::Key::new(&p.headers_namespace, header_name),
                header,
            ));
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
    pub fn refresh_facts(&mut self, revision: &str, mut resolve: impl FnMut(&ProcKey, &BindingFact) -> FactValue) -> usize {
        if self.revision.as_deref() == Some(revision) { return self.refresh_pending(&mut resolve); }
        let ids: BTreeSet<_> = self.reverse.keys().copied().collect();
        self.restore_certificate_readers(&ids);
        let changed = self.refresh_fact_ids(&ids, &mut resolve);
        self.pending_shared.clear(); self.pending_private.clear();
        self.revision = Some(revision.to_owned());
        changed
    }

    /// Declaration deltas identify the exact observed keys, including absent
    /// names that became present. Only readers of these keys enter the closure.
    pub fn refresh_changed_facts(&mut self, revision: &str, facts: &BTreeSet<BindingFact>, mut resolve: impl FnMut(&ProcKey, &BindingFact)->FactValue) -> BTreeSet<ProcKey> {
        let ids: BTreeSet<_> = facts.iter().filter_map(|fact| self.fact_ids.get(fact).copied()).collect();
        self.restore_certificate_readers(&ids);
        self.refresh_fact_ids(&ids, &mut resolve);
        self.refresh_pending(&mut resolve);
        self.revision = Some(revision.to_owned());
        self.dirty.clone()
    }
    pub fn dirty_keys(&self) -> impl Iterator<Item=&ProcKey> { self.dirty.iter() }
    pub fn has_pending_validation(&self) -> bool { !self.pending_shared.is_empty() || !self.pending_private.is_empty() }
    fn clear_pending_private(&mut self,procedure:u32) {
        let edges:Vec<_>=self.pending_private.range((procedure,0)..=(procedure,u32::MAX)).copied().collect();
        for edge in edges {self.pending_private.remove(&edge);}
    }

    /// Disk candidates add unknown edges, independently of declaration changes.
    /// Replay only those private edges in authored procedure order; shared facts
    /// use one input and one resolution regardless of their reader count.
    fn refresh_pending(&mut self, resolve:&mut impl FnMut(&ProcKey,&BindingFact)->FactValue) -> usize {
        let started=std::time::Instant::now();
        let mut changed=0;
        for id in std::mem::take(&mut self.pending_shared) {
            if self.shared_facts.get(&id).is_none_or(|fact|fact.input.value(&self.db).is_some()) {continue;}
            let readers:Vec<_>=self.reverse.get(&id).into_iter().flatten()
                .map(|id|&self.procedure_names[*id as usize])
                .filter(|key|self.records.get(*key).is_some_and(|record|record.active)).cloned().collect();
            let Some(key)=readers.first() else {continue;};
            let fact=Arc::clone(&self.fact_names[id as usize]);
            let value=self.intern_value(&resolve(key,&fact));
            self.shared_facts[&id].input.set_value(&mut self.db).to(Some(value));
            self.dirty.extend(readers); self.stats.fact_refreshes+=1; changed+=1;
        }
        for (procedure,id) in std::mem::take(&mut self.pending_private) {
            let key=self.procedure_names[procedure as usize].clone();
            let Some(record)=self.records.get(&key).filter(|record|record.active) else {continue;};
            let Some(input)=record.facts.get(&id).filter(|fact|fact.input.value(&self.db).is_none()).map(|fact|fact.input) else {continue;};
            let fact=Arc::clone(&self.fact_names[id as usize]);
            let value=self.intern_value(&resolve(&key,&fact));
            input.set_value(&mut self.db).to(Some(value));
            self.dirty.insert(key); self.stats.fact_refreshes+=1; changed+=1;
        }
        self.stats.changed_facts+=changed;
        self.stats.invalidated_procedures=self.dirty.len();
        self.stats.fact_refresh_seconds+=started.elapsed().as_secs_f64();
        changed
    }

    fn refresh_fact_ids(&mut self, ids: &BTreeSet<FactId>, resolve: &mut impl FnMut(&ProcKey,&BindingFact)->FactValue) -> usize {
        let started = std::time::Instant::now();
        let mut changed = 0;
        for id in ids {
            let fact = Arc::clone(&self.fact_names[*id as usize]);
            let readers: Vec<_> = self.reverse.get(id).into_iter().flatten().map(|id| &self.procedure_names[*id as usize]).filter(|key| self.records.get(*key).is_some_and(|record| record.active)).cloned().collect();
            if fact.is_shared() {
                let Some(key) = readers.first() else { continue; };
                self.stats.fact_refreshes += 1;
                let value = self.intern_value(&resolve(key, &fact));
                let Some(observed) = self.shared_facts.get_mut(id) else { continue; };
                if observed.input.value(&self.db).as_ref() != Some(&value) {
                    observed.input.set_value(&mut self.db).to(Some(value));
                    self.dirty.extend(readers); changed += 1;
                }
            } else {
                for key in readers {
                    self.stats.fact_refreshes += 1;
                    let value = self.intern_value(&resolve(&key, &fact));
                    let Some(observed) = self.records.get_mut(&key).and_then(|record| record.facts.get_mut(id)) else { continue; };
                    if observed.input.value(&self.db).as_ref() != Some(&value) {
                        observed.input.set_value(&mut self.db).to(Some(value));
                        self.dirty.insert(key); changed += 1;
                    }
                }
            }
        }
        self.stats.changed_facts += changed;
        self.stats.invalidated_procedures = self.dirty.len();
        self.stats.fact_refresh_seconds += started.elapsed().as_secs_f64();
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
        if let Some(descriptor) = self.certificates.get(key).map(|c| c.descriptor.clone()) {
            self.ensure_record(key, &descriptor);
        }
        if !self.records.contains_key(key) {
            return;
        }
        self.evict_artifact(key);
        let id=self.records[key].id;
        self.clear_pending_private(id);
        let record = self.records.get_mut(key).unwrap();
        if let Some(candidate) = record.input.candidate(&self.db).as_ref() {
            for witness in candidate.dependencies.iter() {
                if let Some(readers) = self.reverse.get_mut(&witness.fact) { readers.remove(&record.id); }
            }
        }
        self.dirty.remove(key);
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
