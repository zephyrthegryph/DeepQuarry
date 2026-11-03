//! Per-file raw policy lives in the compiler's SAME Db. Only explicit captured
//! bytes/config enter; no filesystem reads, DM parse or sibling result cache.
use super::*;
#[path = "analyze_policy.rs"]
mod analyze_policy;
#[path = "generator_policy.rs"]
mod generator_policy;
pub(crate) use generator_policy::Artifact as GeneratorArtifact;
pub use generator_policy::GeneratorName;
#[path = "workspace_raw.rs"]
pub(super) mod workspace;
use crate::runner_host::policy_capture::CapturedPolicyInputs;
use dm_analysis::policy_inputs::{PolicyRole, TextView};
use dq_analyze::{
    captured_raw_file::{self, Config, File, Findings, Scope},
    captured_raw_policy::{
        Configuration, RawRun, MAX_FIXTURE_FILE_BYTES, MAX_FIXTURE_SITES, MAX_FIXTURE_TOTAL_BYTES,
    },
};
use std::{
    collections::BTreeSet,
    io,
    path::Path,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Weak,
    },
    time::{Duration, Instant},
};
pub(super) const RAW_FINDINGS: Kind = Kind(6);
const RAW_FILE: Kind = Kind(7);
const RAW_CONFIG: Kind = Kind(8);
const RAW_SCOPE: Kind = Kind(9);
const INPUT_BUDGET: usize = 256 * 1024 * 1024;
const RESULT_BUDGET: usize = 64 * 1024 * 1024;
const MAX_NODES: usize = 4096;
const MAX_FILES: usize = 128;
const MAX_AGE: Duration = Duration::from_secs(5 * 60);
#[path = "raw_policy_operational_abort.rs"]
mod operational_abort;
use operational_abort::OperationalAbort;
#[path = "reactive_nested_admission.rs"]
mod reactive_nested_admission;
#[path="reactive_read_policy.rs"]
mod reactive_read_policy;
pub(crate) use reactive_read_policy::{Request as ReactiveRequest,Value as ReactiveValue};
#[path="reactive_workspace_operation.rs"]
mod reactive_workspace_operation;
#[path="reactive_ui_actions.rs"]
pub(super) mod reactive_ui_actions;
#[path="reactive_workspace_policy.rs"]
mod reactive_workspace_policy;
pub(super) struct Admission {
    workspace_operation:Mutex<Option<reactive_workspace_operation::Frame>>,
    abort: OperationalAbort,
    leases: Mutex<BTreeMap<Key, Lease>>,
    workspace_nodes: AtomicUsize,
    limit: AtomicUsize,
    denied: std::sync::atomic::AtomicBool,
    view_denied: std::sync::atomic::AtomicBool,
}
impl Default for Admission {
    fn default() -> Self {
        Self {
            workspace_operation:Mutex::new(None),
            abort: OperationalAbort::default(),
            leases: Mutex::new(BTreeMap::new()),
            workspace_nodes: AtomicUsize::new(0),
            limit: AtomicUsize::new(RESULT_BUDGET),
            denied: std::sync::atomic::AtomicBool::new(false),
            view_denied: std::sync::atomic::AtomicBool::new(false),
        }
    }
}
pub(super) struct State {
    pub(super) admission: Arc<Admission>,
    // Coordination/weak leases only. Every reusable source view/config/finding
    // is a value in Db, never another map of analysis payloads.
    gate: Mutex<()>,
    workspace: workspace::State,
    pub(super) charge: Arc<AtomicUsize>,
}
impl Default for State {
    fn default() -> Self {
        Self {
            admission: Arc::new(Admission::default()),
            gate: Mutex::new(()),
            workspace: workspace::State::default(),
            charge: Arc::new(AtomicUsize::new(0)),
        }
    }
}
enum LeaseOwner{Semantic(Weak<CapturedPolicyInputs>),UiRaw(Weak<crate::runner_host::workspace_capture::WorkspaceCapture>)}
impl LeaseOwner{fn expires_without_owner(&self)->bool{match self{Self::Semantic(owner)=>owner.strong_count()==0,Self::UiRaw(owner)=>{let _resource_only_liveness=owner.strong_count();false}}}}
struct Lease {
    owner: LeaseOwner,
    bytes: usize,
    touched: Instant,
}
struct FileData {
    file: Arc<File>,
    hash: u128,
}
struct ConfigData {
    config: Arc<Config>,
    hash: u128,
    original: Option<dm_resources::SharedBytes>,
}
impl ConfigData {
    fn require_original(&self, current: Option<&[u8]>) -> io::Result<()> {
        if self.original.as_ref().map(|bytes| bytes.as_slice()) != current {
            return Err(invalid(
                "cached configuration bytes/absence contradict current capture",
            ));
        }
        Ok(())
    }
}
#[derive(Clone)]
struct ScopeParams {
    config: Key,
    name: &'static str,
}
#[derive(Clone)]
struct FileParams {
    file: Key,
    scope: Key,
    scope_params: ScopeParams,
}
/// Factory-issued cohort. Receipt and root/config are private immutable values;
/// equal bytes are not an artifact's authority and foreign Db cohorts reject.
pub(crate) struct Cohort {
    issuer: u64,
    capture: Arc<CapturedPolicyInputs>,
    root: PathBuf,
    configuration: PathBuf,
    files: Vec<PathBuf>,
}
/// Cache admission/accounting estimates, explicitly not heap/RSS measurements.
#[derive(Clone, Debug)]
pub(crate) struct CacheStats {
    pub nodes: usize,
    pub input_and_param_estimate: usize,
    pub derived_estimate: usize,
    pub retained_shared_view_capacity: usize,
}
struct PreparedRawInputs {
    configuration: Key,
    sources: Vec<(Key, u128, Arc<File>)>,
}
pub(crate) struct Results {
    input: Weak<Cohort>,
    pub(crate) runs: Vec<RawRun>,
}
impl Results {
    pub(crate) fn validate_for(&self, input: &Arc<Cohort>) -> io::Result<()> {
        if !self.input.ptr_eq(&Arc::downgrade(input)) {
            return Err(invalid(
                "raw result belongs to another captured cohort/root/config issuance",
            ));
        }
        Ok(())
    }
}
fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message.into())
}
fn key(kind: Kind, value: &impl serde::Serialize) -> Key {
    Key::new(
        kind,
        dm_query::hash_bytes(&serde_json::to_vec(value).expect("raw key metadata serializes")),
    )
}
fn sort_files(root: &Path, files: &mut [PathBuf]) {
    files.sort_by_cached_key(|path| {
        dm_preprocess::regions::relative_filesystem_path(path, root)
            .as_deref()
            .unwrap_or(path)
            .to_string_lossy()
            .replace('\\', "/")
    });
}

/// Cached Result payload plus its Arc header. Capacity, not current text
/// length, is retained even when an error was shortened after construction.
fn result_error_charge<T>(error: &String) -> usize {
    std::mem::size_of::<Result<T, String>>() + 2 * std::mem::size_of::<usize>() + error.capacity()
}
fn retain_derived(
    charge: &AtomicUsize,
    bytes: usize,
    admission: &Admission,
    key: Key,
) -> Result<(), QueryError> {
    admission.abort.before_outcome(key)?;
    if charge
        .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |used| {
            used.checked_add(bytes)
                .filter(|n| *n <= admission.limit.load(Ordering::Relaxed).min(RESULT_BUDGET))
        })
        .is_err()
    {
        admission.denied.store(true, Ordering::Relaxed);
        return Err(QueryError::Missing(key));
    }
    Ok(())
}

fn error_hash(error: &str) -> u128 {
    let mut hash = xxhash_rust::xxh3::Xxh3::new();
    hash.update(b"native-raw-policy-error-v1\0");
    hash.update(error.as_bytes());
    hash.digest128()
}
pub(super) fn register(db: &Db, charge: Arc<AtomicUsize>, admission: Arc<Admission>) {
    workspace::register_with_admission(db, Arc::clone(&admission));
    analyze_policy::register_analyze(db, Arc::clone(&charge), Arc::clone(&admission));
    generator_policy::register(db, Arc::clone(&charge), Arc::clone(&admission));
    reactive_read_policy::register(db,Arc::clone(&charge),Arc::clone(&admission));
    db.define_input(RAW_FILE, "native-raw-shared-file");
    db.define_input(RAW_CONFIG, "native-raw-captured-config");
    let scope_charge = Arc::clone(&charge);
    let scope_admission = Arc::clone(&admission);
    db.define(
        RAW_SCOPE,
        "native-raw-resolved-scope",
        move |ctx, params| {
            let params = params
                .downcast_ref::<ScopeParams>()
                .expect("raw scope params");
            scope_admission.abort.before_outcome(params.config)?;
            let configuration = ctx.input::<ConfigData>(params.config)?;
            let available = scope_admission
                .limit
                .load(Ordering::Relaxed)
                .saturating_sub(scope_charge.load(Ordering::Relaxed));
            if configuration.config.budget_charge() > available {
                scope_admission.denied.store(true, Ordering::Relaxed);
                return Err(QueryError::Missing(params.config));
            }
            let result = configuration.config.scope(params.name).map(Arc::new);
            let (hash, bytes) = match &result {
                Ok(scope) => (scope.fingerprint(), scope.budget_charge()),
                Err(error) => (error_hash(error), result_error_charge::<Arc<Scope>>(error)),
            };
            retain_derived(&scope_charge, bytes, &scope_admission, params.config)?;
            scope_admission.abort.before_outcome(params.config)?;
            Ok(Outcome::new(result, hash, bytes))
        },
    );
    db.define(
        RAW_FINDINGS,
        "native-raw-per-file-findings",
        move |ctx, params| {
            let params = params
                .downcast_ref::<FileParams>()
                .expect("raw file params");
            admission.abort.before_outcome(params.file)?;
            let file = ctx.input::<FileData>(params.file)?;
            let scope = ctx.get::<Result<Arc<Scope>, String>>(
                params.scope,
                Arc::new(params.scope_params.clone()),
            )?;
            let available = admission
                .limit
                .load(Ordering::Relaxed)
                .saturating_sub(charge.load(Ordering::Relaxed));
            let result = match scope.as_ref() {
                Ok(scope) => match file.file.scan_budgeted_checked(scope, MAX_FIXTURE_SITES, available.saturating_sub(512)) {
                    Ok(rows) => Ok(Arc::new(rows)),
                    Err(captured_raw_file::ScanFailure::Policy(error)) => Err(error),
                    Err(captured_raw_file::ScanFailure::Admission(_)) => {
                        admission.denied.store(true,Ordering::Relaxed);
                        return Err(QueryError::Missing(params.file));
                    }
                },
                Err(error) => Err(error.clone()),
            };
            let (hash, bytes) = match &result {
                Ok(rows) => (rows.fingerprint(), rows.budget_charge()),
                Err(error) => (
                    error_hash(error),
                    result_error_charge::<Arc<Findings>>(error),
                ),
            };
            retain_derived(&charge, bytes, &admission, params.file)?;
            admission.abort.before_outcome(params.file)?;
            Ok(Outcome::new(result, hash, bytes))
        },
    );
}
impl QueryDb {
    fn begin_result_admission_locked(&self) -> io::Result<()> {
        self.raw_policy.admission.abort.begin();
        self.raw_policy.admission.workspace_nodes.store(self.workspace_nodes_locked(),Ordering::Release);
        let limit = RESULT_BUDGET
            .checked_sub(self.workspace_result_charge_locked()?)
            .ok_or_else(|| invalid("shared native policy result budget exhausted"))?;
        self.raw_policy
            .admission
            .limit
            .store(limit, Ordering::Relaxed);
        self.raw_policy
            .admission
            .denied
            .store(false, Ordering::Relaxed);
        self.raw_policy
            .admission
            .view_denied
            .store(false, Ordering::Relaxed);
        Ok(())
    }
    fn derived_query_error(&self, context: &str, error: QueryError) -> io::Error {
        if let Some(original) = self.raw_policy.admission.abort.take_error() {
            return original;
        }
        let error = match error.into_operational() {
            Ok(error) => return error.into_io(),
            Err(error) => error,
        };
        if self.raw_policy.admission.abort.is_aborted() {
            return io::Error::new(
                io::ErrorKind::Interrupted,
                "native policy operation aborted",
            );
        }
        if self.raw_policy.admission.denied.load(Ordering::Relaxed) {
            invalid("shared native policy result budget exhausted before cache publication")
        } else {
            invalid(format!("{context}: {error:?}"))
        }
    }
    pub(crate) fn raw_policy_cache_stats(&self) -> CacheStats {
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let leases = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let mut storage = BTreeMap::new();
        for key in leases.keys().filter(|key| key.kind == RAW_FILE && leases.get(key).is_some_and(|lease|matches!(&lease.owner,LeaseOwner::Semantic(_)))) {
            if let Some(source) = self.db.input::<FileData>(*key) {
                source.file.visit_policy_storage(|id, bytes| {
                    storage
                        .entry(id)
                        .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                        .or_insert(bytes);
                });
            }
        }
        let nodes = leases.len();
        let inputs = leases.values().map(|lease| lease.bytes).sum();
        drop(leases);
        let (workspace_nodes, workspace_bytes) = self.workspace_counts_locked();
        CacheStats {
            retained_shared_view_capacity: storage
                .values()
                .copied()
                .fold(0usize, usize::saturating_add),
            nodes: nodes.saturating_add(workspace_nodes),
            input_and_param_estimate: inputs,
            derived_estimate: self
                .raw_policy
                .charge
                .load(Ordering::Relaxed)
                .saturating_add(workspace_bytes),
        }
    }

    fn raw_retained_view_bytes_locked(&self) -> io::Result<usize> {
        let leases = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let mut storage = BTreeMap::new();
        for key in leases.keys().filter(|key| key.kind == RAW_FILE && leases.get(key).is_some_and(|lease|matches!(&lease.owner,LeaseOwner::Semantic(_)))) {
            if let Some(source) = self.db.input::<FileData>(*key) {
                source.file.visit_policy_storage(|id, bytes| {
                    storage
                        .entry(id)
                        .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                        .or_insert(bytes);
                });
            }
        }
        storage
            .values()
            .try_fold(0usize, |a, b| a.checked_add(*b))
            .ok_or_else(|| invalid("raw retained view census overflow"))
    }
    fn raw_clear_locked(&self) {
        let mut leases = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        for key in leases.keys() {
            self.db.remove(*key);
        }
        leases.clear();
        self.workspace_clear_locked();
        self.raw_policy.charge.store(0, Ordering::Relaxed);
    }
    pub(crate) fn prune_raw_policy(&self) {
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        self.raw_prune_locked(Instant::now());
    }
    pub(crate) fn release_raw_policy_cache(&self) {
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let mut leases = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        for key in leases.keys() {
            self.db.remove(*key);
        }
        leases.clear();
        drop(leases);
        self.workspace_clear_locked();
        self.raw_policy.charge.store(0, Ordering::Relaxed);
    }
    pub(crate) fn raw_cohort(
        &self,
        capture: Arc<CapturedPolicyInputs>,
        root: &Path,
        configuration: &Path,
    ) -> io::Result<Arc<Cohort>> {
        if capture.policy_revision().is_none()
            || !capture.policy().archive().uses_body_queries(self)
        {
            return Err(invalid(
                "raw cohort needs this compiler graph and an explicitly bound policy capture",
            ));
        }
        if !root.is_absolute() || !configuration.is_absolute() {
            return Err(invalid("raw cohort root/config must be caller-absolute"));
        }
        let root = dm_preprocess::regions::canonical_path(root);
        let configuration = dm_preprocess::regions::canonical_path(configuration);
        let config = capture.configuration_bytes(&configuration)?;
        let mut bytes = config.map_or(0, |b| b.len());
        if bytes > MAX_FIXTURE_FILE_BYTES {
            return Err(invalid("raw configuration exceeds fixture admission"));
        }
        let mut files = Vec::new();
        for file in capture
            .policy()
            .files()
            .filter(|f| f.role() == PolicyRole::DmSource)
        {
            // Never replace the issued key with its report-equivalent path.
            let path = file.path().to_path_buf();
            if dm_preprocess::regions::relative_filesystem_path(&path, &root).is_none() {
                return Err(invalid("captured raw source lies outside cohort root"));
            }
            let raw = file
                .view(TextView::AnalyzeRaw)
                .map_err(|e| invalid(e.to_string()))?;
            if raw.len() > MAX_FIXTURE_FILE_BYTES {
                return Err(invalid("raw file exceeds fixture admission"));
            }
            bytes = bytes
                .checked_add(raw.len())
                .filter(|v| *v <= MAX_FIXTURE_TOTAL_BYTES)
                .ok_or_else(|| invalid("raw cohort exceeds total fixture admission"))?;
            files.push(path);
            if files.len() > MAX_FILES {
                return Err(invalid("raw graph cohort exceeds 128 captured files"));
            }
        }
        if files.iter().collect::<BTreeSet<_>>().len() != files.len() {
            return Err(invalid("duplicate canonical raw source receipts"));
        }
        // Legacy Tree sorts by slash-normalized relative spelling; Windows
        // PathBuf order differs for `code/x.dm` versus `code0.dm`.
        sort_files(&root, &mut files);
        Ok(Arc::new(Cohort {
            issuer: self.id,
            capture,
            root,
            configuration,
            files,
        }))
    }
    fn raw_prune_locked(&self, now: Instant) {
        // SAME family gate is held. Snapshot operation status before leases;
        // no lease-map path then takes the operation-slot lock, so drop/bind
        // cannot invert these locks. Outer entry prunes before UiRaw is bound.
        let active_ui=self.raw_policy.admission.ui_operation_is_bound();
        let mut leases = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        self.workspace_prune_expired_locked(now);
        leases.retain(|key, lease| {
            // UI values are bounded metadata/offset DATA, never source loans. Keep
            // their charged Db values until real TTL eviction; a dead weak owner
            // grants nothing and current UI facts must be authenticated anew.
            if lease.owner.expires_without_owner()
                || (now.saturating_duration_since(lease.touched) > MAX_AGE
                    && !(active_ui && matches!(&lease.owner,LeaseOwner::UiRaw(_))))
            {
                let bytes = self.db.value_bytes_at(*key);
                self.db.remove(*key);
                if matches!(
                    key.kind,
                    RAW_FINDINGS
                        | RAW_SCOPE
                        | analyze_policy::ANALYZE_FINDINGS
                        | generator_policy::GENERATOR_RESULT
                        | reactive_read_policy::REACTIVE_RESULT
                ) {
                    let _ = self.raw_policy.charge.fetch_update(
                        Ordering::Relaxed,
                        Ordering::Relaxed,
                        |v| Some(v.saturating_sub(bytes)),
                    );
                }
                false
            } else {
                true
            }
        });
        // A cutoff can keep the prior cached owner after a fresh Outcome was
        // constructed. Reconcile only live derived lease values at request
        // boundaries, rather than accumulating those publications forever.
        let retained = leases
            .keys()
            .filter(|key| {
                matches!(
                    key.kind,
                    RAW_FINDINGS
                        | RAW_SCOPE
                        | analyze_policy::ANALYZE_FINDINGS
                        | generator_policy::GENERATOR_RESULT
                        | reactive_read_policy::REACTIVE_RESULT
                )
            })
            .fold(0usize, |n, key| {
                n.saturating_add(self.db.value_bytes_at(*key))
            });
        self.raw_policy.charge.store(retained, Ordering::Relaxed);
    }
    fn raw_admit_locked(
        &self,
        cohort: &Arc<Cohort>,
        planned: &BTreeMap<Key, usize>,
        now: Instant,
    ) -> io::Result<()> {
        let charge = planned
            .values()
            .try_fold(0usize, |a, b| a.checked_add(*b))
            .ok_or_else(|| invalid("raw graph charge overflow"))?;
        if planned.len() > MAX_NODES || charge > INPUT_BUDGET {
            return Err(invalid(
                "raw graph cohort exceeds node/input admission budget",
            ));
        }
        let mut leases = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let mut total = leases
            .iter()
            .filter(|(key, _)| !planned.contains_key(*key))
            .map(|(_, l)| l.bytes)
            .sum::<usize>()
            .saturating_add(charge);
        // Raw fixture and production page nodes share this family bound.
        // Only trim page memo values if the incoming regular cohort needs room.
        self.workspace_trim_locked(MAX_NODES - planned.len(), RESULT_BUDGET);
        let workspace_nodes = self.workspace_nodes_locked();
        let mut count = leases
            .keys()
            .filter(|key| !planned.contains_key(*key))
            .count()
            + planned.len()
            + workspace_nodes;
        let mut old: Vec<_> = leases
            .iter()
            .filter(|(key, _)| !planned.contains_key(*key))
            .map(|(key, l)| (*key, l.touched))
            .collect();
        old.sort_by_key(|(_, time)| *time);
        for (key, _) in old {
            if total <= INPUT_BUDGET && count <= MAX_NODES {
                break;
            }
            if let Some(lease) = leases.remove(&key) {
                total = total.saturating_sub(lease.bytes);
                count -= 1;
                let bytes = self.db.value_bytes_at(key);
                self.db.remove(key);
                if matches!(
                    key.kind,
                    RAW_FINDINGS
                        | RAW_SCOPE
                        | analyze_policy::ANALYZE_FINDINGS
                        | generator_policy::GENERATOR_RESULT
                        | reactive_read_policy::REACTIVE_RESULT
                ) {
                    let _ = self.raw_policy.charge.fetch_update(
                        Ordering::Relaxed,
                        Ordering::Relaxed,
                        |v| Some(v.saturating_sub(bytes)),
                    );
                }
            }
        }
        for (key, bytes) in planned {
            leases.insert(
                *key,
                Lease {
                    owner: LeaseOwner::Semantic(Arc::downgrade(&cohort.capture)),
                    bytes: *bytes,
                    touched: now,
                },
            );
        }
        Ok(())
    }
    fn raw_prepare_locked(
        &self,
        cohort: &Arc<Cohort>,
        ordered: &[&str],
        now: Instant,
    ) -> io::Result<PreparedRawInputs> {
        let config_key = key(RAW_CONFIG, &(&cohort.root, &cohort.configuration));
        let bytes = cohort.capture.configuration_bytes(&cohort.configuration)?;
        let config_hash = match bytes {
            Some(_) => {
                // Reuse the SAME ledger's captured raw-byte fingerprint. No
                // repeated config clone/hash or lossy decoded text is needed.
                let content = cohort
                    .capture
                    .facts()
                    .files()
                    .find(|file| file.path == cohort.configuration)
                    .ok_or_else(|| invalid("captured configuration has no recorded file digest"))?
                    .content;
                let mut h = b"present\0".to_vec();
                h.extend_from_slice(&content.to_le_bytes());
                dm_query::hash_bytes(&h)
            }
            None => dm_query::hash_bytes(b"proven-missing"),
        };
        let configuration = match self.db.input::<ConfigData>(config_key) {
            Some(old) if old.hash == config_hash => {
                old.require_original(bytes)?;
                Arc::clone(&old.config)
            }
            _ => Arc::new(
                Config::capture(match bytes {
                    Some(b) => Configuration::Captured(b),
                    None => Configuration::ProvenMissing,
                })
                .map_err(invalid)?,
            ),
        };
        let mut planned = BTreeMap::from([(config_key, configuration.budget_charge())]);
        let mut sources = Vec::new();
        for path in &cohort.files {
            let input = cohort
                .capture
                .policy()
                .file(path)
                .ok_or_else(|| invalid("raw source lost captured receipt"))?;
            let raw = input
                .view(TextView::AnalyzeRaw)
                .map_err(|e| invalid(e.to_string()))?;
            let hash = raw
                .span_fingerprint(0..raw.len())
                .ok_or_else(|| invalid("raw source fingerprint unavailable"))?;
            let file_key = key(RAW_FILE, &(&cohort.root, path));
            let file = match self.db.input::<FileData>(file_key) {
                Some(old) if old.hash == hash => {
                    old.file
                        .require_current_source(path, raw)
                        .map_err(invalid)?;
                    Arc::clone(&old.file)
                }
                _ => Arc::new(File::capture(&cohort.root, path, raw.clone()).map_err(invalid)?),
            };
            planned.insert(file_key, file.budget_charge());
            sources.push((file_key, hash, file));
            for name in ordered {
                let scope = key(RAW_SCOPE, &(config_key.id, name));
                planned.insert(scope, 1024);
                planned.insert(key(RAW_FINDINGS, &(file_key.id, scope.id)), 1024);
            }
        }
        self.raw_admit_locked(cohort, &planned, now)?;
        self.db.set_input(
            config_key,
            ConfigData {
                config: configuration,
                hash: config_hash,
                original: cohort.capture.configuration_owner(&cohort.configuration)?,
            },
            config_hash,
        );
        for (file_key, hash, file) in &sources {
            self.db.set_input(
                *file_key,
                FileData {
                    file: Arc::clone(file),
                    hash: *hash,
                },
                *hash,
            );
        }
        Ok(PreparedRawInputs {
            configuration: config_key,
            sources,
        })
    }
    pub(crate) fn raw_findings(
        &self,
        cohort: &Arc<Cohort>,
        names: &[String],
    ) -> io::Result<Results> {
        if cohort.issuer != self.id || !cohort.capture.policy().archive().uses_body_queries(self) {
            return Err(invalid("foreign raw cohort issuance"));
        }
        let ordered = captured_raw_file::ordered_names(names).map_err(invalid)?;
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let now = Instant::now();
        self.raw_prune_locked(now);
        let PreparedRawInputs {
            configuration: config_key,
            sources,
        } = self.raw_prepare_locked(cohort, &ordered, now)?;
        self.begin_result_admission_locked()?;
        let mut runs = Vec::new();
        let mut total_sites = 0usize;
        for name in ordered {
            let scope = key(RAW_SCOPE, &(config_key.id, name));
            let scope_params = ScopeParams {
                config: config_key,
                name,
            };
            let mut run = dq_analyze::lint::Run::default();
            let mut allow_used = Vec::new();
            for (file_key, _, _) in &sources {
                crate::daemon::control::checkpoint()?;
                if self.raw_policy.charge.load(Ordering::Relaxed) > RESULT_BUDGET {
                    let freed = self.db.evict_values(&[RAW_FINDINGS, RAW_SCOPE]);
                    let _ = self.raw_policy.charge.fetch_update(
                        Ordering::Relaxed,
                        Ordering::Relaxed,
                        |v| Some(v.saturating_sub(freed)),
                    );
                }
                let result = self
                    .db
                    .get::<Result<Arc<Findings>, String>>(
                        key(RAW_FINDINGS, &(file_key.id, scope.id)),
                        Arc::new(FileParams {
                            file: *file_key,
                            scope,
                            scope_params: scope_params.clone(),
                        }),
                    )
                    .map_err(|e| self.derived_query_error("native raw query", e))?;
                self.workspace_trim_locked(
                    MAX_NODES,
                    RESULT_BUDGET.saturating_sub(self.raw_policy.charge.load(Ordering::Relaxed)),
                );
                let result = result
                    .as_ref()
                    .as_ref()
                    .map_err(|e| io::Error::other(e.clone()))?;
                total_sites = total_sites
                    .checked_add(result.run.sites.len())
                    .filter(|v| *v <= MAX_FIXTURE_SITES)
                    .ok_or_else(|| invalid("raw cohort exceeds total finding fixture admission"))?;
                run.sites.extend(result.run.sites.iter().cloned());
                run.notes.extend(result.run.notes.iter().cloned());
                allow_used.extend(result.allow_used.iter().cloned());
            }
            runs.push(RawRun {
                name: name.into(),
                run,
                allow_used,
            });
        }
        Ok(Results {
            input: Arc::downgrade(cohort),
            runs,
        })
    }
}
#[cfg(test)]
#[path = "raw_policy_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "raw_policy_config_authority_tests.rs"]
mod config_authority_tests;
