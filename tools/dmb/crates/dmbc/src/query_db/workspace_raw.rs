//! DATA draft: page contributions in the SAME native Db. No sibling payload cache.
//! Only WorkspaceCapture::page issues PageInput after current native read-guard
//! authentication; a retained PageResult alone cannot authorize current sources.
use super::*;
use crate::runner_host::{
    query_snapshot::workspace_native_guard::NativeReadGuard, workspace_capture::WorkspaceCapture,
};
use dm_preprocess::{source_acquisition::OriginalAcquisitionIdentity, SourceText};
use dm_resources::SharedBytesOwner;
use dq_analyze::captured_raw_file::{self, Config, File, Findings, Scope};
use dq_analyze::captured_raw_policy::{Configuration, RawRun};
use std::{
    io,
    path::PathBuf,
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        Arc, Weak,
    },
};
const PAGE_INPUT: Kind = Kind(13);
const PAGE_RESULT: Kind = Kind(14);
const RAW_TERMINAL: Kind = Kind(806);
const RAW_TERMINAL_KEY: Key = Key { kind: RAW_TERMINAL, id: 0 };
const MAX_CACHED_RAW_REPORT: usize = 1024 * 1024;

struct RawTerminalBody {
    witness: Mutex<Weak<WorkspaceCapture>>,
    bytes: Vec<u8>,
    hash: u128,
    clean: bool,
}
impl RawTerminalBody {
    fn retained_bytes(&self) -> usize {
        Self::fixed_bytes() + self.bytes.capacity()
    }
    fn fixed_bytes() -> usize {
        std::mem::size_of::<Self>() + std::mem::size_of::<WorkspaceCapture>()
            + 4 * std::mem::size_of::<usize>()
    }
}
const INPUT_BOUND: usize = 256 * 1024 * 1024;
const RESULT_BOUND: usize = 64 * 1024 * 1024;
const NODE_BOUND: usize = 4096;
const MAX_SITES: usize = 10_000;
/// Coordination/eviction metadata only. Reusable findings stay solely in Db.
#[derive(Default)]
pub(super) struct State {
    raw_sources: Mutex<raw_input_credits::Ledger>,
    pages: Mutex<BTreeMap<Key, (Key, std::time::Instant, bool)>>,
    roots: Mutex<BTreeMap<Key, (Key, std::time::Instant)>>,
}

const PAGE_FILES: usize = 128;
fn invalid(s: impl std::fmt::Display) -> io::Error {
    io::Error::other(s.to_string())
}
#[path = "workspace_raw_aggregate.rs"]
mod aggregate;
#[path = "workspace_raw_code.rs"]
mod code;
pub(crate) use code::{SelectedHandlerFiles,UiInputProof,WorkspaceCodeReader,WorkspaceCodeWitness,WorkspaceCodeTraversal,WorkspaceGeneratorTestWitness,WorkspaceTrackedWitness,WorkspaceSysReactiveWitness,WorkspaceDerivedWitness};
#[path = "workspace_check_grep.rs"]
mod check_grep;
#[path = "workspace_resource_inventory.rs"]
mod resource_inventory;
pub use aggregate::{WorkspaceCursor, WorkspacePageReader, WorkspacePageView};
use resource_inventory::ResourceInventory;
#[path="workspace_source_arena.rs"]mod source_arena;
pub(crate) use source_arena::{retire_path_fact_node, seal_path_fact_control};
#[path="workspace_raw_input_credits.rs"]mod raw_input_credits;
pub(crate) use raw_input_credits::{FundedPairedDmm, RawInputCredits};
/// Resource-only live allocation census. Addresses never authorize content or
/// policy reuse. All payload owners remain in Db values; this stores numbers.
#[derive(Default)]
struct Owners {
    keys: BTreeMap<(u8, usize), Owner>,
    bytes: usize,
    #[cfg(test)]
    page_walks: usize,
}
enum OwnerLife {
    Scope(Weak<Scope>),
    Rows(Weak<Findings>),
    Metadata,
    Outcome(Weak<dyn std::any::Any + Send + Sync>),
}
struct Owner {
    bytes: usize,
    life: OwnerLife,
}
impl OwnerLife {
    fn live(&self) -> bool {
        match self {
            Self::Scope(w) => w.strong_count() != 0,
            Self::Rows(w) => w.strong_count() != 0,
            Self::Metadata => true,
            Self::Outcome(w) => w.strong_count() != 0,
        }
    }
}
impl Owners {
    fn add(&mut self, kind: u8, address: usize, bytes: usize) {
        self.add_life(kind, address, bytes, OwnerLife::Metadata);
    }
    fn add_life(&mut self, kind: u8, address: usize, bytes: usize, life: OwnerLife) {
        let old = self.keys.entry((kind, address)).or_insert(Owner {
            bytes: 0,
            life: OwnerLife::Metadata,
        });
        self.bytes = self.bytes.saturating_add(bytes.saturating_sub(old.bytes));
        if bytes >= old.bytes {
            old.bytes = bytes;
            old.life = life;
        }
    }
    fn scope(&mut self, scope: &Arc<Scope>) {
        self.add_life(
            0,
            Arc::as_ptr(scope) as usize,
            scope.budget_charge(),
            OwnerLife::Scope(Arc::downgrade(scope)),
        );
    }
    fn rows(&mut self, rows: &Arc<Findings>) {
        self.add_life(
            1,
            Arc::as_ptr(rows) as usize,
            compact_charge(rows),
            OwnerLife::Rows(Arc::downgrade(rows)),
        );
    }
    fn add_unless(&mut self, live: &Self, kind: u8, address: usize, bytes: usize) {
        if !live
            .keys
            .get(&(kind, address))
            .is_some_and(|o| o.life.live() && o.bytes >= bytes)
        {
            self.add(kind, address, bytes);
        }
    }
    fn outcome<T: std::any::Any + Send + Sync>(
        &mut self,
        tag: u8,
        value: &Arc<Result<Arc<T>, String>>,
    ) {
        let bytes = std::mem::size_of::<Result<Arc<T>, String>>()
            + 2 * std::mem::size_of::<usize>()
            + value.as_ref().as_ref().err().map_or(0, |e| e.capacity());
        let erased: Arc<dyn std::any::Any + Send + Sync> = value.clone();
        self.add_life(
            tag,
            Arc::as_ptr(value) as usize,
            bytes,
            OwnerLife::Outcome(Arc::downgrade(&erased)),
        );
    }
    fn page(&mut self, page: &Arc<PageResult>) {
        // Immutable owner identity is a resource dedup key, never authority.
        // The query inventory pins all initial Outcomes and holds new pages.
        if self.keys.contains_key(&(2, Arc::as_ptr(page) as usize)) {
            return;
        }
        #[cfg(test)]
        {
            self.page_walks += 1;
        }
        let metadata = std::mem::size_of::<PageResult>()
            + 4 * std::mem::size_of::<usize>()
            + std::mem::size_of::<Result<Arc<PageResult>, String>>()
            + 2 * std::mem::size_of::<usize>()
            + page.root.capacity()
            + page.configuration.capacity()
            + page.names.capacity() * std::mem::size_of::<&str>()
            + page.scopes.capacity() * std::mem::size_of::<Arc<Scope>>()
            + page.files.capacity() * std::mem::size_of::<Contribution>()
            + page
                .files
                .iter()
                .map(|f| {
                    f.path.capacity()
                        + f.proof.metadata_charge()
                        + f.findings.capacity() * std::mem::size_of::<Arc<Findings>>()
                })
                .sum::<usize>();
        self.add(2, Arc::as_ptr(page) as usize, metadata);
        for scope in &page.scopes {
            self.scope(scope);
        }
        for file in &page.files {
            for rows in &file.findings {
                self.rows(rows);
            }
        }
    }
}
/// Only genuine already-admitted original owners enter this compare-only token.
#[derive(Clone)]
pub(crate) enum SourceProof {
    Native(OriginalAcquisitionIdentity),
    Owned(dm_resources::WeakSharedBytes),
    PairedDmm(usize),
    Spool(crate::input_snapshot::WorkspaceRawSpoolIdentity),
}
impl SourceProof {
    fn metadata_charge(&self) -> usize {
        match self {
            Self::Native(id) => {
                let mut n = 0usize;
                id.visit_storage(|s| {
                    if let dm_preprocess::source_acquisition::AcquisitionStorage::Object {
                        bytes,
                        ..
                    } = s
                    {
                        n = n.saturating_add(bytes + 2 * std::mem::size_of::<usize>());
                    }
                });
                n
            }
            Self::PairedDmm(_) => 0,
            Self::Spool(id) => id.metadata_charge(),
            Self::Owned(_) => {
                std::mem::size_of::<SharedBytesOwner>() + 2 * std::mem::size_of::<usize>()
            }
        }
    }
    fn same(&self, b: &Self) -> bool {
        match (self, b) {
            (Self::Native(a), Self::Native(b)) => a.same_live_original(b),
            (Self::Spool(a), Self::Spool(b)) => a.same_live(b),
            (Self::Owned(a), Self::Owned(b)) => {
                a.strong_count() != 0 && b.strong_count() != 0 && a.ptr_eq(b)
            }
            _ => false,
        }
    }
}
pub(crate) struct CurrentFile {
    pub(crate) path: PathBuf,
    pub(crate) text: Option<SourceText>,
    pub(crate) proof: SourceProof,
    pub(crate) charge: usize,
    /// Exact relative path and sole scope's exclusion result, recorded by
    /// the current raw page before its source is acquired. Scoped DATA only.
    pub(crate) raw_selection: Option<(String, bool)>,
}
/// Private producer/factory only. Current bytes are scoped page owners and
/// evicted immediately after a result, including all error/cancellation paths.
struct PageInput {
    scoped_patterns:bool,
    graph: u64,
    root: PathBuf,
    configuration: PathBuf,
    scopes: Vec<Arc<Scope>>,
    names: Vec<&'static str>,
    files: Vec<CurrentFile>,
    previous: Weak<Result<Arc<PageResult>, String>>,
    scans: Arc<AtomicUsize>,
    result_budget: usize,
    input_budget: usize,
    live: Weak<Mutex<Owners>>,
    remaining_sites: usize,
}
struct Contribution {
    path: PathBuf,
    proof: SourceProof,
    findings: Vec<Arc<Findings>>,
}
struct PageResult {
    scoped_patterns:bool,
    graph: u64,
    root: PathBuf,
    configuration: PathBuf,
    names: Vec<&'static str>,
    scopes: Vec<Arc<Scope>>,
    files: Vec<Contribution>,
    charge: usize,
}
#[derive(Clone)]
struct Params {
    input: Key,
}
fn compact_charge(f: &Findings) -> usize {
    f.budget_charge()
        .saturating_sub(1024)
        .saturating_add(std::mem::size_of::<Findings>() + 2 * std::mem::size_of::<usize>())
}
impl PageResult {
    fn same_policy(&self, p: &PageInput) -> bool {
        self.graph == p.graph
            && self.root == p.root
            && self.configuration == p.configuration
            && self.names == p.names
    }
}
/// Wire from QueryDb::default, with the existing native graph. These kinds are
/// provisional until root verifies no intervening kind allocation collision.
#[cfg(test)]
pub(super) fn register(db: &Db) {
    register_with_admission(db, Arc::new(super::Admission::default()));
}
pub(super) fn register_with_admission(db: &Db, admission: Arc<super::Admission>) {
    db.define_input(RAW_TERMINAL, "native-raw-selected-terminal-body");
    aggregate::register_with_admission(db, Arc::clone(&admission));
    db.define_input(PAGE_INPUT, "native-workspace-raw-page-input");
    db.define(
        PAGE_RESULT,
        "native-workspace-raw-page-result",
        move |ctx,p|produce_page(ctx,p,&admission,None),
    );
}

struct PatternResources<'a>{budget:&'a Arc<dq_analyze::captured_generator_budget::Budget>,provider:&'a dyn dq_analyze::native_pattern::Provider}
enum PageFailure{Policy(String),Operational(io::Error)}
impl From<String> for PageFailure{fn from(actual:String)->Self{Self::Policy(actual)}}
impl From<&str> for PageFailure{fn from(actual:&str)->Self{Self::Policy(actual.into())}}
impl PageFailure{fn into_message(self)->String{match self{Self::Policy(message)=>message,Self::Operational(actual)=>actual.to_string()}}}
fn produce_page(ctx:&mut dm_query::Ctx<'_>,p:&dm_query::Value,admission:&super::Admission,resources:Option<&PatternResources<'_>>)->Result<Outcome,QueryError>{

            let p = p.downcast_ref::<Params>().expect("workspace page params");
            admission.abort.before_outcome(p.input)?;
            let input = ctx.input::<PageInput>(p.input)?;
            if input.scoped_patterns!=resources.is_some(){return Err(QueryError::operational(p.input,io::Error::new(io::ErrorKind::NotConnected,"this page requires its actual scoped pattern lender")))}
            let result=match compute_with_pattern_resources(&input,admission,resources){
                Ok(actual)=>Ok(Arc::new(actual)),
                Err(PageFailure::Policy(message))=>Err(message),
                Err(PageFailure::Operational(actual))=>return Err(QueryError::operational(p.input,actual)),
            };
            if admission.denied.load(Ordering::Relaxed) { return Err(QueryError::Missing(p.input)); }
            let (hash, charge) = match &result {
                Ok(page) => {
                    // Content hash drives normal Db early-cutoff only. Every use
                    // still starts with current authenticated source/page inputs.
                    let mut h = xxhash_rust::xxh3::Xxh3::new();
                    for file in &page.files {
                        for rows in &file.findings {
                            h.update(&rows.fingerprint().to_le_bytes());
                        }
                    }
                    (h.digest128(), page.charge)
                }
                Err(e) => (
                    dm_query::hash_bytes(e.as_bytes()),
                    super::result_error_charge::<Arc<PageResult>>(e),
                ),
            };
            if result.is_err() && charge > input.result_budget {
                admission.denied.store(true, Ordering::Relaxed);
                return Err(QueryError::Missing(p.input));
            }
            admission.abort.before_outcome(p.input)?;
            Ok(Outcome::new(result, hash, charge))
}
#[cfg(test)]
fn compute(p: &PageInput) -> Result<PageResult, String> {
    compute_with_admission(p, &super::Admission::default())
}
fn compute_with_admission(p:&PageInput,admission:&super::Admission)->Result<PageResult,String>{compute_with_pattern_resources(p,admission,None).map_err(PageFailure::into_message)}
fn compute_with_pattern_resources(p:&PageInput,admission:&super::Admission,resources:Option<&PatternResources<'_>>)->Result<PageResult,PageFailure>{
    let live_owner = p
        .live
        .upgrade()
        .ok_or("workspace resource inventory expired")?;
    let live = live_owner.lock().unwrap_or_else(|e| e.into_inner());
    let previous = p.previous.upgrade();
    let previous = previous
        .as_ref()
        .and_then(|v| v.as_ref().as_ref().ok())
        .filter(|old| old.same_policy(p)&&old.scoped_patterns==p.scoped_patterns);
    // The current input owns only source texts, not their per-lint derived
    // views. Designate the active file's shared source charge to its own view
    // budget; union all other live sources by real allocation key exactly once.
    let mut source_owners = BTreeMap::new();
    let mut path_bytes = 0usize;
    for file in &p.files {
        path_bytes = path_bytes
            .checked_add(file.path.capacity())
            .and_then(|n| n.checked_add(file.raw_selection.as_ref().map_or(0, |(rel,_)|rel.capacity())))
            .ok_or("page path accounting overflow")?;
        if let Some(text) = &file.text {
            captured_raw_file::visit_source_storage(text, |key, bytes| {
                source_owners
                    .entry(key)
                    .and_modify(|old: &mut usize| *old = (*old).max(bytes))
                    .or_insert(bytes);
            });
        }
    }
    let source_bytes = source_owners
        .values()
        .try_fold(path_bytes, |n, b| n.checked_add(*b))
        .ok_or("page source accounting overflow")?;
    if source_bytes > p.input_budget {
        return Err("current page source inputs exceed shared input budget".into());
    }
    let metadata = std::mem::size_of::<PageResult>()
        + p.root.capacity()
        + p.configuration.capacity()
        + p.files.len() * std::mem::size_of::<Contribution>()
        + p.scopes.len() * std::mem::size_of::<Arc<Scope>>()
        + p.names.len() * std::mem::size_of::<&str>();
    if metadata > p.result_budget {
        return Err("page metadata exceeds result headroom".into());
    }
    let mut files = Vec::with_capacity(p.files.len());
    let mut charge = metadata;
    let mut new = Owners::default();
    let mut sites = 0usize;
    for scope in &p.scopes {
        new.add_unless(&live, 0, Arc::as_ptr(scope) as usize, scope.budget_charge());
    }
    charge = charge
        .checked_add(new.bytes)
        .filter(|n| *n <= p.result_budget)
        .ok_or("page scopes exceed result headroom")?;
    for current in &p.files {
        admission.abort.scan_checkpoint()?;
        let old = previous.and_then(|old| {
            old.files
                .iter()
                .find(|old| old.path == current.path && old.proof.same(&current.proof))
        });
        let file_meta = current.path.capacity()
            + current.proof.metadata_charge()
            + p.scopes.len() * std::mem::size_of::<Arc<Findings>>();
        charge = charge
            .checked_add(file_meta)
            .filter(|n| *n <= p.result_budget)
            .ok_or("contribution metadata exceeds result headroom")?;
        let mut file = None;
        let mut findings = Vec::with_capacity(p.scopes.len());
        for (index, scope) in p.scopes.iter().enumerate() {
            let reused = old.and_then(|old| {
                previous
                    .and_then(|page| page.scopes.get(index))
                    .filter(|prior| prior.equivalent_to(scope))
                    .and_then(|_| old.findings.get(index))
            });
            if let Some(rows) = reused {
                let before = new.bytes;
                new.add_unless(&live, 1, Arc::as_ptr(rows) as usize, compact_charge(rows));
                charge = charge
                    .checked_add(new.bytes - before)
                    .filter(|n| *n <= p.result_budget)
                    .ok_or("reused findings exceed result headroom")?;
                sites = sites
                    .checked_add(rows.run.sites.len())
                    .filter(|n| *n <= p.remaining_sites)
                    .ok_or("workspace site bound exceeded")?;
                findings.push(Arc::clone(rows));
                continue;
            }
            admission.abort.scan_checkpoint()?;
            let fallback;
            let (rel, excluded) = if let Some((rel, excluded)) = &current.raw_selection {
                if p.scopes.len() != 1 || *excluded == current.text.is_some() {
                    return Err("raw page selection contradicts current source/scope".into());
                }
                (rel.as_str(), *excluded)
            } else {
                fallback = dm_preprocess::regions::relative_filesystem_path(&current.path, &p.root)
                    .ok_or("workspace file escapes admitted root")?
                    .to_string_lossy()
                    .replace('\\', "/");
                (fallback.as_str(), scope.excludes_path(&fallback)?)
            };
            if excluded && p.result_budget.saturating_sub(charge) < 1024 {
                return Err("excluded finding metadata has no admitted headroom".into());
            }
            if excluded {
                let empty = scope.empty_excluded_findings();
                let cost = compact_charge(&empty);
                charge = charge
                    .checked_add(cost)
                    .filter(|n| *n <= p.result_budget)
                    .ok_or("excluded finding metadata exceeds result headroom")?;
                let rows = Arc::new(empty);
                new.add(1, Arc::as_ptr(&rows) as usize, cost);
                findings.push(rows);
                continue;
            }
            if file.is_none() {
                let text = current
                    .text
                    .as_ref()
                    .ok_or("non-exempt workspace source has no admitted real text")?;
                let others = source_bytes
                    .checked_sub(current.charge)
                    .ok_or("page source ownership accounting mismatch")?;
                let available = p
                    .input_budget
                    .checked_sub(others)
                    .ok_or("shared file view headroom exhausted")?;
                file = Some(if current.raw_selection.is_some() {
                    File::capture_budgeted_preselected(&p.root, &current.path, rel, text.clone(), available)?
                } else {
                    File::capture_budgeted(&p.root, &current.path, text.clone(), available)?
                });
            }
            file.as_ref()
                .expect("captured above")
                .require_view_budget()?;
            p.scans.fetch_add(1, Ordering::Relaxed);
            let available = p
                .result_budget
                .checked_sub(charge)
                .ok_or("result headroom exhausted")?;
            let file = file.as_ref().expect("file created above");
            let scanned = if let Some(resources)=resources{
                file.scan_with_pattern_resources(scope,p.remaining_sites-sites,available,current.raw_selection.is_some(),resources.budget,resources.provider,&crate::daemon::control::checkpoint)
            }else if current.raw_selection.is_some() {
                file.scan_preselected_budgeted_checked(scope, p.remaining_sites - sites, available)
            } else {
                file.scan_budgeted_checked(scope, p.remaining_sites - sites, available)
            };
            let rows = scanned.map_err(|failure| match failure {
                captured_raw_file::ScanFailure::Policy(error) => PageFailure::Policy(error),
                captured_raw_file::ScanFailure::Operational(actual)=>PageFailure::Operational(actual),
                captured_raw_file::ScanFailure::Admission(error) => {
                    admission.denied.store(true,Ordering::Relaxed);
                    PageFailure::Policy(error)
                }
            })?;
            let cost = compact_charge(&rows);
            charge = charge
                .checked_add(cost)
                .filter(|n| *n <= p.result_budget)
                .ok_or("findings exceed admitted result headroom")?;
            sites = sites
                .checked_add(rows.run.sites.len())
                .filter(|n| *n <= p.remaining_sites)
                .ok_or("workspace site bound exceeded")?;
            let rows = Arc::new(rows);
            new.add(1, Arc::as_ptr(&rows) as usize, cost);
            findings.push(rows);
        }
        files.push(Contribution {
            path: current.path.clone(),
            proof: current.proof.clone(),
            findings,
        });
    }
    // Outcome's standalone estimate remains conservative for generic Db/LRU
    // stats. Shared-family admission uses the deduplicated live-owner census.
    let charge = metadata
        + p.scopes.iter().map(|s| s.budget_charge()).sum::<usize>()
        + files
            .iter()
            .map(|f| {
                f.path.capacity()
                    + f.proof.metadata_charge()
                    + f.findings.capacity() * std::mem::size_of::<Arc<Findings>>()
                    + f.findings.iter().map(|r| compact_charge(r)).sum::<usize>()
            })
            .sum::<usize>();
    Ok(PageResult {
        scoped_patterns:p.scoped_patterns,
        graph: p.graph,
        root: p.root.clone(),
        configuration: p.configuration.clone(),
        names: p.names.clone(),
        scopes: p.scopes.clone(),
        files,
        charge,
    })
}
/// Eviction cleanup on success, policy refusal, cancellation and Db error.
struct PageInputLease<'a> {
    db: &'a Db,
    key: Key,
}
impl Drop for PageInputLease<'_> {
    fn drop(&mut self) {
        self.db.evict_value_at(self.key);
    }
}
impl QueryDb {
    /// Source-free protocol accounting, the SAME unchanged report reservation.
    pub(crate) fn workspace_raw_report_reserve()->usize{aggregate::REPORT_RESERVE}

    pub(super) fn workspace_clear_locked(&self) {
        self.db.remove(RAW_TERMINAL_KEY);
        self.workspace_roots_clear_locked();
        let mut pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        for (result, (input, _, _)) in pages.iter() {
            self.db.remove(*input);
            self.db.remove(*result);
        }
        pages.clear();
    }
    fn workspace_admit_page(&self, input: Key, result: Key, bulk_raw: bool) -> io::Result<()> {
        let now = std::time::Instant::now();
        let mut pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let root_nodes = self
            .raw_policy
            .workspace
            .roots
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .len()
            .saturating_mul(2);
        let raw_nodes = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .len()
            .saturating_add(root_nodes).saturating_add(self.bulk_raw_terminal_nodes_locked());
        let expired = pages
            .iter()
            .filter(|(key, (_, t, _))| {
                **key != result
                    && now.saturating_duration_since(*t) > std::time::Duration::from_secs(300)
            })
            .map(|(key, _)| *key)
            .collect::<Vec<_>>();
        for key in expired {
            if let Some((input, _, _)) = pages.remove(&key) {
                self.db.remove(input);
                self.db.remove(key);
            }
        }
        while pages
            .len()
            .checked_mul(2)
            .and_then(|n| {
                n.checked_add(raw_nodes + if pages.contains_key(&result) { 0 } else { 2 })
            })
            .is_none_or(|n| n > NODE_BOUND)
        {
            let old = pages
                .iter()
                .filter(|(key, _)| **key != result)
                .min_by_key(|(_, (_, t, _))| *t)
                .map(|(key, _)| *key)
                .ok_or_else(|| invalid("native raw/workspace node budget exhausted"))?;
            if let Some((input, _, _)) = pages.remove(&old) {
                self.db.remove(input);
                self.db.remove(old);
            }
        }
        pages.insert(result, (input, now, bulk_raw));
        Ok(())
    }
    // Caller holds the existing raw-family gate. These return/trim metadata
    // only; retained payloads remain owned exclusively by the native Db.
    pub(super) fn workspace_prune_expired_locked(&self, now: std::time::Instant) {
        self.workspace_roots_prune_locked(now);
        if let Some(body) = self.db.retained_value::<RawTerminalBody>(RAW_TERMINAL_KEY) {
            let live = body.witness.lock().unwrap_or_else(|e| e.into_inner()).strong_count() != 0;
            if !live { self.db.remove(RAW_TERMINAL_KEY); }
        }
        let mut pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        let expired = pages
            .iter()
            .filter(|(_, (_, time, _))| {
                now.saturating_duration_since(*time) > std::time::Duration::from_secs(300)
            })
            .map(|(key, _)| *key)
            .collect::<Vec<_>>();
        for key in expired {
            if let Some((input, _, _)) = pages.remove(&key) {
                self.db.remove(input);
                self.db.remove(key);
            }
        }
    }
    pub(super) fn workspace_input_headroom_locked(&self,fixed:usize)->io::Result<usize>{let sources=self.raw_source_input_charge_locked()?;self.workspace_input_base_headroom_locked(fixed.checked_add(sources).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?)}
    pub(super) fn workspace_raw_page_input_headroom_locked(&self,capture:&WorkspaceCapture,fixed:usize)->io::Result<usize>{
        if capture.is_sealed_raw_file_capture(){
            self.workspace_input_headroom_with_source_upper_locked(fixed)
        }else{
            self.workspace_input_headroom_locked(fixed)
        }
    }
    pub(super) fn workspace_input_base_headroom_locked(&self, fixed: usize) -> io::Result<usize> {
        self.workspace_input_base_remaining_locked(fixed)?.filter(|n| *n > 0)
            .ok_or_else(|| io::Error::new(io::ErrorKind::OutOfMemory,"shared raw input-family budget exhausted"))
    }
    pub(super) fn workspace_input_base_remaining_locked(&self, fixed: usize) -> io::Result<Option<usize>> {
        let raw_inputs = self
            .raw_policy
            .admission.leases
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .values()
            .try_fold(0usize, |n, lease| {
                n.checked_add(lease.bytes)
                    .ok_or_else(|| invalid("shared raw input accounting overflow"))
            })?;
        let manifests = self.workspace_manifest_charge_locked();
        let coordination = self.workspace_nodes_locked().saturating_mul(96);
        Ok(INPUT_BOUND
            .checked_sub(raw_inputs)
            .and_then(|n| n.checked_sub(manifests))
            .and_then(|n| n.checked_sub(coordination))
            .and_then(|n| n.checked_sub(fixed)))
    }
    pub(super) fn workspace_nodes_locked(&self) -> usize {
        self.raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .len()
            * 2
            + self
                .raw_policy
                .workspace
                .roots
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .len()
                * 2
            + self.bulk_raw_terminal_nodes_locked()
    }
    pub(super) fn workspace_counts_locked(&self) -> (usize, usize) {
        (
            self.workspace_nodes_locked(),
            self.workspace_owners_locked(&[])
                .map_or(RESULT_BOUND, |o| o.bytes),
        )
    }
    pub(super) fn workspace_trim_locked(&self, max_nodes: usize, max_bytes: usize) {
        self.db.remove(RAW_TERMINAL_KEY);
        // Root values retain page Arcs transitively. Drop root values first when
        // an unrelated raw cohort needs room; page-node trimming alone cannot free them.
        self.workspace_roots_clear_locked();
        let mut pages = self
            .raw_policy
            .workspace
            .pages
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        loop {
            let bytes = pages.keys().fold(0usize, |total, key| {
                total.saturating_add(self.db.value_bytes_at(*key))
            });
            if pages.len().saturating_mul(2) <= max_nodes && bytes <= max_bytes {
                break;
            }
            let Some(old) = pages
                .iter()
                .min_by_key(|(_, (_, time, _))| *time)
                .map(|(key, _)| *key)
            else {
                break;
            };
            if let Some((input, _, _)) = pages.remove(&old) {
                self.db.remove(input);
                self.db.remove(old);
            }
        }
    }
    /// Trim only eligible previous raw-bulk payloads. Each stage takes
    /// its exact inventory after this optional warm retention policy runs.
    /// No value still held by an aggregate or operation is a candidate.
    fn trim_bulk_raw_values_locked(&self, warm_target: usize) {
        let pages = self.raw_policy.workspace.pages.lock().unwrap_or_else(|e| e.into_inner());
        let mut estimated = pages.iter().filter(|(_, (_, _, bulk))| *bulk)
            .fold(0usize, |total, (key, _)| total.saturating_add(self.db.value_bytes_at(*key)));
        let mut cursor = None;
        while estimated > warm_target {
            let next = pages.iter()
                .filter(|(_, (_, _, bulk))| *bulk)
                .map(|(key, (_, time, _))| (*time, *key))
                .filter(|candidate| cursor.is_none_or(|after| *candidate > after))
                .min();
            let Some((time, key)) = next else { break; };
            cursor = Some((time, key));
            let Some(value) = self.db.retained_value::<Result<Arc<PageResult>, String>>(key) else { continue; };
            if Arc::strong_count(&value) != 2
                || value.as_ref().as_ref().is_ok_and(|page| Arc::strong_count(page) != 1)
            {
                continue;
            }
            // Keep the real query node, parameters and dependency edges.
            // This estimate only stops LRU work; it is never admission credit.
            let dropped = self.db.evict_value_if_current(key, &value);
            drop(value);
            estimated = estimated.saturating_sub(dropped);
        }
    }
    pub(crate) fn workspace_raw_cache_stats(&self) -> (usize, usize) {
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        self.workspace_counts_locked()
    }
    pub(super) fn workspace_result_charge_locked(&self) -> io::Result<usize> {
        Ok(self.workspace_owners_locked(&[])?.bytes)
    }
    fn bulk_raw_terminal_nodes_locked(&self) -> usize {
        usize::from(self.db.retained_value::<RawTerminalBody>(RAW_TERMINAL_KEY).is_some())
    }

    fn bulk_terminal_node_room_locked(&self) -> bool {
        let raw = self.raw_policy.admission.leases.lock().unwrap_or_else(|e| e.into_inner()).len();
        self.workspace_nodes_locked().saturating_add(raw) < NODE_BOUND
    }

    /// Called only after the bulk report completed and its transient result
    /// owners dropped, while the same raw-family gate remains held. Prefer
    /// an already payload-free coordinate. Otherwise retire at most the
    /// oldest selected bulk page whose value and page are both unborrowed.
    fn retire_bulk_page_coordinate_locked(&self) -> bool {
        let mut pages = self.raw_policy.workspace.pages.lock().unwrap_or_else(|e| e.into_inner());
        let best = pages.iter().filter_map(|(key, (_, time, bulk))| {
            if !*bulk { return None; }
            let value = self.db.retained_value::<Result<Arc<PageResult>, String>>(*key);
            if value.as_ref().is_some_and(|value|
                Arc::strong_count(value) != 2
                    || value.as_ref().as_ref().is_ok_and(|page| Arc::strong_count(page) != 1))
            {
                return None;
            }
            Some((value.is_some(), *time, *key))
        }).min();
        let Some((_, _, key)) = best else { return false; };
        let (input, _, _) = pages.remove(&key).expect("still held bulk page coordinate");
        self.db.remove(input);
        self.db.remove(key);
        true
    }

    /// The caller has already checked the exact new frame and closed plan.
    /// An old terminal is never reused, and no output callback runs here.
    pub(crate) fn restore_bulk_raw_report(
        &self, capture: &Arc<WorkspaceCapture>, scope: &NativeReadGuard<'_>,
        prior: &Arc<WorkspaceCapture>, stage: &mut crate::selected_report_spool::Stage,
    ) -> io::Result<Option<(bool, u128)>> {
        use std::io::Write as _;
        crate::daemon::control::checkpoint()?;
        capture.require_scope(scope)?;
        if !scope.uses_queries(self) || !capture.is_sealed_raw_file_capture() {
            return Err(invalid("raw terminal replay requires its actual current capture"));
        }
        let _gate = self.raw_policy.gate.lock().unwrap_or_else(|e| e.into_inner());
        let Some(body) = self.db.retained_value::<RawTerminalBody>(RAW_TERMINAL_KEY) else { return Ok(None); };
        let mut witness = body.witness.lock().unwrap_or_else(|e| e.into_inner());
        if !Weak::ptr_eq(&witness, &Arc::downgrade(prior)) || !capture.same_bulk_report_inputs(prior)? {
            // An actual candidate miss may retire just this one report body.
            drop(witness);
            self.db.remove(RAW_TERMINAL_KEY);
            return Ok(None);
        }
        stage.write_all(&body.bytes)?;
        capture.require_scope(scope)?;
        *witness = Arc::downgrade(capture);
        Ok(Some((body.clean, body.hash)))
    }

    /// Collect the existing sealed validation stream into one optional,
    /// exactly charged result owner. This does not add a second spool read.
    pub(crate) fn finish_bulk_raw_report(
        &self, capture: &Arc<WorkspaceCapture>, scope: &NativeReadGuard<'_>,
        stage: crate::selected_report_spool::Stage, clean: bool,
    ) -> io::Result<crate::selected_report_spool::Verified> {
        crate::daemon::control::checkpoint()?;
        capture.require_scope(scope)?;
        if !scope.uses_queries(self) || !capture.is_sealed_raw_file_capture() {
            return Err(invalid("raw terminal retention requires its actual current capture"));
        }
        let _gate = self.raw_policy.gate.lock().unwrap_or_else(|e| e.into_inner());
        self.db.remove(RAW_TERMINAL_KEY);
        let length = usize::try_from(stage.length()).ok().filter(|&len| len <= MAX_CACHED_RAW_REPORT);
        let mut copy = if let Some(length) = length {
            // Prior artifact has been dropped. Workspace result census and
            // native raw charge count all other retained results under this gate.
            let live = match self.workspace_result_charge_locked() {
                Ok(bytes) => Some(bytes),
                Err(error) if error.kind() == io::ErrorKind::InvalidInput => None,
                Err(error) => return Err(error),
            };
            let available = live.and_then(|live| RESULT_BOUND.checked_sub(live))
                .and_then(|n| n.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)))
                .and_then(|n| n.checked_sub(aggregate::REPORT_RESERVE)).unwrap_or(0);
            let fixed = RawTerminalBody::fixed_bytes();
            let mut bytes = Vec::new();
            if length.checked_add(fixed).is_some_and(|total| total <= available)
                && bytes.try_reserve_exact(length).is_ok() && bytes.capacity() <= length
            {
                bytes.resize(length, 0);
                Some(bytes)
            } else { None }
        } else { None };
        let length = stage.length();
        let (verified, read) = stage.seal()?.validate(|reader| {
            if let Some(bytes) = &mut copy {
                reader.read_exact(bytes)?;
                Ok(bytes.len() as u64)
            } else {
                io::copy(reader, &mut io::sink())
            }
        })?;
        if read != length || verified.length() != length {
            return Err(invalid("raw terminal validation omitted report bytes"));
        }
        crate::daemon::control::checkpoint()?;
        capture.require_scope(scope)?;
        if let Some(bytes) = copy.filter(|bytes| xxhash_rust::xxh3::xxh3_128(bytes) == verified.hash()) {
            if !self.bulk_terminal_node_room_locked()
                && (!self.retire_bulk_page_coordinate_locked() || !self.bulk_terminal_node_room_locked())
            {
                return Ok(verified);
            }
            self.db.set_input(RAW_TERMINAL_KEY, RawTerminalBody {
                witness: Mutex::new(Arc::downgrade(capture)), bytes, hash: verified.hash(), clean,
            }, u128::from(capture.issuance()));
        }
        Ok(verified)
    }

    fn workspace_remaining_results(&self, _current: Key) -> io::Result<usize> {
        let owners = self.workspace_owners_locked(&[])?;
        RESULT_BOUND
            .checked_sub(self.raw_policy.charge.load(Ordering::Relaxed))
            .and_then(|n| n.checked_sub(owners.bytes))
            .ok_or_else(|| invalid("shared native raw result-family budget exhausted"))
    }
    /// Transactional raw-only execution. All rows remain private until every
    /// discovered page succeeds. No full-lint/semantic/baseline parity claim.
    fn build_workspace_pages_locked(
        &self,
        capture: &WorkspaceCapture,
        scope: &NativeReadGuard<'_>,
        names: &[String],
        scans: Arc<AtomicUsize>,
        inventory: &ResourceInventory,
        bulk_raw: bool,
        pattern_budget:Option<&Arc<dq_analyze::captured_generator_budget::Budget>>,
    ) -> io::Result<(Vec<Arc<PageResult>>, Vec<Arc<Scope>>)> {
        crate::daemon::control::checkpoint()?;
        capture.require_scope(scope)?; // exact immutable map/revision BEFORE cache
        if !scope.uses_queries(self) {
            return Err(invalid("workspace query needs the SAME compiler QueryDb"));
        }
        let admit_fixed = |fixed| if bulk_raw {
            self.workspace_input_headroom_with_source_upper_locked(fixed)
        } else {
            self.workspace_input_headroom_locked(fixed)
        };
        let ordered = captured_raw_file::ordered_names(names).map_err(invalid)?;
        self.raw_prune_locked(std::time::Instant::now());
        let (configuration, bytes) = capture.configuration();
        let config_preflight = bytes
            .map_or(0, |b| b.len())
            .checked_mul(64)
            .and_then(|n| n.checked_add(16 * 1024))
            .ok_or_else(|| invalid("configuration preflight overflow"))?;
        let capture_charge = capture.retained_charge()?;
        admit_fixed(
            capture_charge
                .checked_add(config_preflight)
                .ok_or_else(|| invalid("configuration admission overflow"))?,
        )?;
        let config = Config::capture(match bytes {
            Some(b) => Configuration::Captured(b),
            None => Configuration::ProvenMissing,
        })
        .map_err(invalid)?;
        let mut scopes = Vec::with_capacity(ordered.len());
        let mut scope_charge = 0usize;
        for name in &ordered {
            admit_fixed(
                capture_charge
                    .saturating_add(config.budget_charge())
                    .saturating_add(scope_charge)
                    .saturating_add(config_preflight),
            )?;
            let scope = Arc::new(config.scope(name).map_err(invalid)?);
            scope_charge = scope_charge
                .checked_add(scope.budget_charge())
                .ok_or_else(|| invalid("scope accounting overflow"))?;
            scopes.push(scope);
        }
        let fixed_inputs = config
            .budget_charge()
            .checked_add(capture_charge)
            .ok_or_else(|| invalid("workspace capture accounting overflow"))?
            .checked_add(scopes.iter().try_fold(0usize, |n, scope| {
                n.checked_add(scope.budget_charge())
                    .ok_or_else(|| invalid("workspace scope accounting overflow"))
            })?)
            .and_then(|n| {
                n.checked_add(
                    std::mem::size_of::<PageInput>()
                        + PAGE_FILES * std::mem::size_of::<CurrentFile>(),
                )
            })
            .ok_or_else(|| invalid("workspace fixed input accounting overflow"))?;
        admit_fixed(fixed_inputs)?;
        admit_fixed(fixed_inputs.saturating_add(inventory.coordination_charge(scopes.len())?))?;
        inventory.add_scopes(&scopes);
        let mut held = Vec::new();
        let mut start = 0;
        let mut page_index = 0;
        let mut sites = 0;

        while start < capture.file_count() {
            crate::daemon::control::checkpoint()?;
            capture.require_scope(scope)?;
            // Reserve the current page's maximum contribution-key growth BEFORE
            // constructing the page or extending the dedup BTreeMap.
            inventory.require_pin_room()?;
            let growth = 2usize
                .saturating_add(scopes.len())
                .saturating_add(PAGE_FILES.saturating_mul(scopes.len()));
            let held_coordination = held
                .capacity()
                .saturating_add(1)
                .saturating_mul(std::mem::size_of::<Arc<PageResult>>());
            let current_budget = self.workspace_raw_page_input_headroom_locked(
                capture,
                fixed_inputs
                    .saturating_add(inventory.coordination_charge(growth)?)
                    .saturating_add(held_coordination),
            )?;
            let live = Arc::downgrade(&inventory.owners);
            let (files, end) = capture.page(scope, start, PAGE_FILES, current_budget, &scopes)?;
            if end <= start {
                return Err(invalid("workspace page made no progress"));
            }
            let metadata = (&capture.root(), configuration, &ordered, page_index,pattern_budget.is_some());
            let id = dm_query::hash_bytes(&serde_json::to_vec(&metadata).map_err(invalid)?);
            let input_key = Key::new(PAGE_INPUT, id);
            let result_key = Key::new(PAGE_RESULT, id);
            self.workspace_admit_page(input_key, result_key, bulk_raw)?;
            let result_budget = RESULT_BOUND
                .checked_sub(self.raw_policy.charge.load(Ordering::Relaxed))
                .and_then(|n| n.checked_sub(inventory.bytes()))
                .and_then(|n| n.checked_sub(aggregate::REPORT_RESERVE))
                .ok_or_else(|| invalid("shared result-family headroom exhausted"))?;
            let previous = self
                .db
                .retained_value::<Result<Arc<PageResult>, String>>(result_key);
            static NEXT: AtomicU64 = AtomicU64::new(1);
            let epoch = NEXT
                .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_add(1))
                .map_err(|_| invalid("workspace page issuance exhausted"))?;
            // A new authenticated current input is ALWAYS installed. The hash
            // does not authorize owner reuse; per-contribution proof above does.
            self.db.set_input(
                input_key,
                PageInput {
                    scoped_patterns:pattern_budget.is_some(),
                    graph: self.id,
                    root: capture.root().to_path_buf(),
                    configuration: configuration.to_path_buf(),
                    scopes: scopes.clone(),
                    names: ordered.clone(),
                    files,
                    previous: previous.as_ref().map_or_else(Weak::new, Arc::downgrade),
                    scans: Arc::clone(&scans),
                    result_budget,
                    input_budget: current_budget,
                    live,
                    remaining_sites: MAX_SITES - sites,
                },
                u128::from(epoch),
            );
            let _release = PageInputLease {
                db: &self.db,
                key: input_key,
            };
            let result=if let Some(budget)=pattern_budget{
                let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|e|e.into_inner());
                source_arena::with_held_pattern_work(self,&mut ledger,budget,|work,scratch|{
                    let provider=crate::query_db::PatternProvider::scoped(self,work,scratch);
                    let resources=PatternResources{budget,provider:&provider};
                    self.db.get_with_scoped_computation::<Result<Arc<PageResult>,String>>(result_key,Arc::new(Params{input:input_key}),|ctx,p|produce_page(ctx,p,&self.raw_policy.admission,Some(&resources)))
                        .map_err(|actual|match actual.into_operational(){Ok(actual)=>actual.into_io(),Err(other)=>self.derived_query_error("workspace page query",other)})
                })?
            }else{self.db.get::<Result<Arc<PageResult>,String>>(result_key,Arc::new(Params{input:input_key})).map_err(|e|self.derived_query_error("workspace page query",e))?};
            let page = result.as_ref().as_ref().map_err(|e| invalid(e.clone()))?;
            for file in &page.files {
                for rows in &file.findings {
                    sites = sites
                        .checked_add(rows.run.sites.len())
                        .filter(|n| *n <= MAX_SITES)
                        .ok_or_else(|| {
                            invalid("workspace finding count exceeds existing10000 bound")
                        })?;
                }
            }
            inventory.add_page_result(&result)?;
            // Retain only the existing Db result owner, never cloned row payloads.
            held.try_reserve_exact(1)
                .map_err(|_| invalid("page manifest allocation refused"))?;
            held.push(Arc::clone(page));
            start = end;
            page_index += 1;
        }
        capture.require_scope(scope)?;
        crate::daemon::control::checkpoint()?;
        Ok((held,scopes))
    }
    /// Internal compatibility adapter. The public endpoint uses borrowed paging.
    pub(crate) fn workspace_raw_findings(
        &self,
        capture: &WorkspaceCapture,
        scope: &NativeReadGuard<'_>,
        names: &[String],
        scans: Arc<AtomicUsize>,
    ) -> io::Result<Vec<RawRun>> {
        capture.require_scope(scope)?;
        if !scope.uses_queries(self) {
            return Err(invalid(
                "workspace report requires current compiler QueryDb",
            ));
        }
        captured_raw_file::ordered_names(names).map_err(invalid)?;
        let _gate = self
            .raw_policy
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        self.raw_policy.admission.abort.begin();
        self.raw_policy
            .admission
            .denied
            .store(false, Ordering::Relaxed);
        let inventory = self.workspace_resource_inventory_locked()?;
        let (pages,_scopes) = self.build_workspace_pages_locked(capture, scope, names, scans, &inventory, false,None)?;
        let ordered = captured_raw_file::ordered_names(names).map_err(invalid)?;
        let mut available = RESULT_BOUND
            .checked_sub(inventory.bytes())
            .and_then(|n| n.checked_sub(self.raw_policy.charge.load(Ordering::Relaxed)))
            .ok_or_else(|| invalid("internal report has no result headroom"))?;
        let mut runs = Vec::with_capacity(ordered.len());
        for (i, name) in ordered.iter().enumerate() {
            let mut run = RawRun {
                name: (*name).into(),
                run: Default::default(),
                allow_used: Vec::new(),
            };
            for page in &pages {
                for file in &page.files {
                    let rows = &file.findings[i];
                    let cost = compact_charge(rows);
                    available = available
                        .checked_sub(cost)
                        .ok_or_else(|| invalid("internal report exceeds result headroom"))?;
                    run.run
                        .sites
                        .try_reserve_exact(rows.run.sites.len())
                        .map_err(invalid)?;
                    run.run
                        .notes
                        .try_reserve_exact(rows.run.notes.len())
                        .map_err(invalid)?;
                    run.allow_used
                        .try_reserve_exact(rows.allow_used.len())
                        .map_err(invalid)?;
                    run.run.sites.extend(rows.run.sites.iter().cloned());
                    run.run.notes.extend(rows.run.notes.iter().cloned());
                    run.allow_used.extend(rows.allow_used.iter().cloned());
                }
            }
            runs.push(run);
        }
        crate::daemon::control::checkpoint()?;
        capture.require_scope(scope)?;
        Ok(runs)
    }
}

#[cfg(test)]
#[path = "workspace_raw_tests.rs"]
mod tests;

#[path="generation_source_policy.rs"]mod generation_source_policy;

impl QueryDb{
 pub(crate) fn with_workspace_raw_allow_usage<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,name:&str,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,consume:impl FnOnce(&mut dyn Iterator<Item=&dq_analyze::lint::AllowUse>)->io::Result<R>)->io::Result<R>{
  self.with_workspace_raw_union_rows(capture,scope,name,budget,false,|_,usage,_|consume(usage))
 }
 // Both cursors borrow the same completed pages. Traversing the result rows
 // and their ALLOW uses does not execute a second raw policy or source query.
 pub(crate) fn with_workspace_raw_union_rows<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,name:&str,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,with_report:bool,consume:impl FnOnce(&mut dyn Iterator<Item=&Findings>,&mut dyn Iterator<Item=&dq_analyze::lint::AllowUse>,Option<(&dq_analyze::scopes::LintScope,&Arc<dq_analyze::captured_generator_budget::Budget>)>)->io::Result<R>)->io::Result<R>{
  self.with_workspace_raw_union_rows_mode(capture,scope,name,budget,with_report,false,consume,None)
 }
 pub(crate) fn with_workspace_bulk_raw_union_rows<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,name:&str,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,consume:impl FnOnce(&mut dyn Iterator<Item=&Findings>,&mut dyn Iterator<Item=&dq_analyze::lint::AllowUse>,Option<(&dq_analyze::scopes::LintScope,&Arc<dq_analyze::captured_generator_budget::Budget>)>)->io::Result<R>)->io::Result<R>{
  if !capture.is_sealed_raw_file_capture(){return Err(invalid("bulk raw pages require the sealed raw capture"))}
  self.with_workspace_raw_union_rows_mode(capture,scope,name,budget,true,true,consume,None)
 }
 pub(crate) fn with_workspace_raw_union_rows_observed<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,name:&str,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,consume:impl FnOnce(&mut dyn Iterator<Item=&Findings>,&mut dyn Iterator<Item=&dq_analyze::lint::AllowUse>,Option<(&dq_analyze::scopes::LintScope,&Arc<dq_analyze::captured_generator_budget::Budget>)>)->io::Result<R>,observed:&mut dyn FnMut(usize,usize,std::time::Duration)->io::Result<()>)->io::Result<R>{self.with_workspace_raw_union_rows_mode(capture,scope,name,budget,true,false,consume,Some(observed))}
 fn with_workspace_raw_union_rows_mode<R>(&self,capture:&Arc<WorkspaceCapture>,scope:&NativeReadGuard<'_>,name:&str,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,with_report:bool,bulk_raw:bool,consume:impl FnOnce(&mut dyn Iterator<Item=&Findings>,&mut dyn Iterator<Item=&dq_analyze::lint::AllowUse>,Option<(&dq_analyze::scopes::LintScope,&Arc<dq_analyze::captured_generator_budget::Budget>)>)->io::Result<R>,mut observed:Option<&mut dyn FnMut(usize,usize,std::time::Duration)->io::Result<()>>)->io::Result<R>{
  crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;if !scope.uses_queries(self){return Err(invalid("full ALLOW raw producer uses another QueryDb"))}
  budget.charge(name.len().saturating_mul(4).saturating_add(4096)).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;let names=[name.to_owned()];
  if !capture.covers_selected_raw_policies(&names,&mut|bytes|budget.charge(bytes).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m)))?{return Err(io::Error::new(io::ErrorKind::Unsupported,"full ALLOW raw producer requires actual complete selected discovery"))}
  captured_raw_file::ordered_names(&names).map_err(invalid)?;
  let _gate=self.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());self.raw_policy.admission.abort.begin();self.raw_policy.admission.denied.store(false,Ordering::Relaxed);
  // Cache retention target only. An active stage still uses the original
  // full 64 MiB result-family admission, with its unchanged report reserve.
  if bulk_raw { self.trim_bulk_raw_values_locked(16 * 1024 * 1024); }
  let started=observed.is_some().then(std::time::Instant::now);let scans=Arc::new(AtomicUsize::new(0));let inventory=self.workspace_resource_inventory_using_locked(bulk_raw)?;let(pages,scopes)=self.build_workspace_pages_locked(capture,scope,&names,Arc::clone(&scans),&inventory,bulk_raw,Some(budget))?;
  crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;
  if pages.iter().flat_map(|page|page.files.iter()).any(|file|file.findings.len()!=1){return Err(invalid("actual raw usage producer returned another finding cohort"))}
  if let Some(observed)=observed.as_deref_mut(){let files=pages.iter().try_fold(0usize,|n,page|n.checked_add(page.files.len()).ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory)))?;observed(files,scans.load(Ordering::Relaxed),started.expect("actual optional timing observation").elapsed())?;}
  let mut rows=pages.iter().flat_map(|page|page.files.iter()).map(|file|file.findings[0].as_ref());
  let mut usage=rows.clone().flat_map(|file|file.allow_used.iter());
  let pending=if with_report{
   let actual=scopes.first().ok_or_else(||invalid("raw union report scope unavailable"))?;
   if bulk_raw {
    self.with_bulk_raw_render_budget_locked(capture,scope,&inventory,|child|
     consume(&mut rows,&mut usage,Some((actual.report_scope(),child))))
   } else {
    self.with_workspace_code_pages_locked(capture,scope,|reader|
     consume(&mut rows,&mut usage,Some((actual.report_scope(),reader.budget()))).map_err(dq_analyze::captured_reactive_reads::Failure::Operational)
    ).map_err(|failure|match failure{dq_analyze::captured_reactive_reads::Failure::Operational(e)=>e,dq_analyze::captured_reactive_reads::Failure::Unsupported(message)=>io::Error::new(io::ErrorKind::Unsupported,message)})
   }
  }else{consume(&mut rows,&mut usage,None)};if pending.is_err(){return pending}crate::daemon::control::checkpoint()?;capture.require_scope(scope)?;pending
 }
}

#[cfg(test)]mod shared_input_exhaustion_controls{
 use super::*;
 #[test]fn actual_shared_raw_input_headroom_denial_is_out_of_memory_without_changing_remaining_credit(){
  let db=QueryDb::default();let _gate=db.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  let before=db.workspace_input_base_headroom_locked(0).unwrap();assert!(before>0);
  for fixed in [before,before.checked_add(1).unwrap()]{
   let error=db.workspace_input_base_headroom_locked(fixed).unwrap_err();
   assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
   assert_eq!(error.to_string(),"shared raw input-family budget exhausted");
   assert_eq!(db.workspace_input_base_headroom_locked(0).unwrap(),before,"denial does not allocate or consume headroom");
  }
 }
 #[test]fn actual_shared_raw_source_capture_preserves_first_callback_io_before_any_late_headroom_check(){
  let db=QueryDb::default();let mut calls=0;
  let error=match db.with_raw_source_capture_inputs(|_,_|{calls+=1;Err(io::Error::from_raw_os_error(1450))}){Err(actual)=>actual,Ok(_)=>panic!("first callback IO cannot become success")};
  assert_eq!(calls,1);assert_eq!(error.raw_os_error(),Some(1450));
  let _gate=db.raw_policy.gate.lock().unwrap_or_else(|e|e.into_inner());
  assert!(db.workspace_input_base_headroom_locked(0).unwrap()>0);
 }
}

impl QueryDb{
 pub(super) fn with_held_raw_pattern_work<R>(&self,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,consume:impl FnOnce(&dyn dm_preprocess::source_arena_credit::SourceArenaWork,&dyn crate::query_db::native_patterns::PatternWorkLender)->io::Result<R>)->io::Result<R>{
  let mut ledger=self.raw_policy.workspace.raw_sources.lock().unwrap_or_else(|error|error.into_inner());
  source_arena::with_held_pattern_work(self,&mut ledger,budget,consume)
 }
}

impl QueryDb{
 /// Pure native callback fixture kernels only; the held raw ledger closes
 /// before any nested actual source preparation or file acquisition resumes.
 pub(crate) fn with_native_fixture_patterns<T>(&self,budget:&Arc<dq_analyze::captured_generator_budget::Budget>,consume:impl FnOnce(&dyn dq_analyze::native_pattern::Provider)->io::Result<T>)->io::Result<T>{
  crate::daemon::control::checkpoint()?;let _gate=self.raw_policy.gate.lock().unwrap_or_else(|error|error.into_inner());
  self.with_held_raw_pattern_work(budget,|work,lender|consume(&crate::query_db::native_patterns::PatternProvider::scoped(self,work,lender)))
 }
}
