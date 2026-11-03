//! Bounded unique purity work in the compiler's ORIGINAL query database.
//! Metadata lives until node removal, independently of derived-value eviction.
use super::*;
use dm_analysis::{
    check_policy::CheckerPolicy,
    checker_effects::{
        BodyEffects, EffectInput, EffectPlan, ExecutionAdmission, Produced, SccSummary,
    },
};
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
use std::{any::Any, sync::{Weak,atomic::Ordering}};
use dm_analysis::checker_effects::Storage;
const BODY: Kind = Kind(17);
const PLAN: Kind = Kind(18);
const SCC: Kind = Kind(19);
const REPORT: Kind = Kind(20);
const RESOLVER: Kind = Kind(21);
const SLEEP_REPORT: Kind = Kind(22);
const BUDGET: usize = 64 * 1024 * 1024;
const MAX_NODES: usize = 10_000;
// Admission bounds include unexposed BTree/Db node and edge bookkeeping. They
// are intentionally conservative, never advertised as measured allocation size.
const NODE_BOUND: usize = 1024;
const EDGE_BOUND: usize = 256;
const CONTEXT_BOUND: usize = 512;
type SourceRegistry = Arc<Mutex<BTreeMap<PathBuf, (Key, Arc<PreparedSource>, u128)>>>;
#[derive(Default)]
pub(super) struct State {
    gate: Mutex<()>,
    pub(super) ledger: Arc<Mutex<Ledger>>,
}
struct SourceContext {
    input: Weak<EffectInput>,
    keys: Arc<Vec<Key>>,
}
struct NodeLease {
    input: Weak<EffectInput>,
    params: Option<Weak<dyn Any + Send + Sync>>,
    param_size: usize,
    param_reserved: usize,
    observed_edges: usize,
}
struct Live {
    owner: Weak<dyn Any + Send + Sync>,
    completion: Option<Arc<std::sync::atomic::AtomicBool>>,
    bytes: usize,
    kind: Kind,
    error: bool,
}
#[derive(Default)]
pub(super) struct Ledger {
    contexts: BTreeMap<u64, SourceContext>,
    nodes: BTreeMap<Key, NodeLease>,
    live: Vec<Live>,
    active_policy: usize,
    active_graph_work: usize,
    fixed_request_inputs: usize,
    // Resource-only cache pressure cursor over the existing Kind23 nodes.
    page_retirement_cursor: Option<Key>,
    denied: bool,
    // Actual operational error, never a memoized semantic refusal String.
    aborted: Option<std::io::Error>,
    #[cfg(test)]
    storage_test_limit: Option<usize>,
}
impl Ledger {
    fn live_bytes(&mut self) -> usize {
        self.live.retain(|v| v.completion.as_ref().map_or_else(||v.owner.strong_count()>0,|done|!done.load(Ordering::Acquire)));
        self.live
            .iter()
            .fold(0usize, |n, x| n.saturating_add(x.bytes))
    }
    fn metadata(&self) -> usize {
        self.contexts
            .values()
            .fold(self.contexts.len().saturating_mul(CONTEXT_BOUND), |n, c| {
                n.saturating_add(std::mem::size_of::<Vec<Key>>())
                    .saturating_add(c.keys.capacity().saturating_mul(std::mem::size_of::<Key>()))
            })
            .saturating_add(self.nodes.values().fold(0usize, |n, p| {
                n.saturating_add(NODE_BOUND)
                    .saturating_add(p.param_size)
                    .saturating_add(p.param_reserved)
                    .saturating_add(p.observed_edges.saturating_mul(EDGE_BOUND))
            }))
            .saturating_add(
                self.live
                    .capacity()
                    .saturating_mul(std::mem::size_of::<Live>()),
            )
            .saturating_add(self.active_policy)
            .saturating_add(self.active_graph_work)
            .saturating_add(self.fixed_request_inputs)
            .saturating_add(self.live.iter().filter(|entry|entry.completion.is_some()).count().saturating_mul(std::mem::size_of::<std::sync::atomic::AtomicBool>()))
    }
    fn admit(&mut self, extra: usize) -> Result<(), String> {
        let fits = self
            .live_bytes()
            .checked_add(self.metadata())
            .and_then(|n| n.checked_add(extra))
            .is_some_and(|n| n <= BUDGET);
        if fits {
            Ok(())
        } else {
            self.denied = true;
            Err("native purity retained metadata/result budget exhausted before publication".into())
        }
    }
}
#[derive(Clone)]
struct Params {
    body_admission:Option<dm_analysis::checker_effects::ExecutionAdmissionLoan>,
    input: Weak<EffectInput>,
    key: Key,
    ordinal: usize,
    sources: Arc<Vec<Key>>,
    policy: Weak<CheckerPolicy>,
}
struct ResolveParams {
    input: Weak<EffectInput>,
    key: Key,
    query: ResolveQuery,
    sources: Arc<Vec<Key>>,
}
fn key(kind: Kind, input: &EffectInput, part: u128) -> Key {
    let mut h = xxhash_rust::xxh3::Xxh3::new();
    h.update(&input.key().to_le_bytes());
    h.update(&part.to_le_bytes());
    Key::new(kind, h.digest128())
}
fn params_for(p: &Params, kind: Kind, part: u128) -> Arc<Params> {
    let mut p = p.clone();
    p.key = key(
        kind,
        &p.input
            .upgrade()
            .expect("caller holds current effect input"),
        part,
    );
    p.ordinal = part as usize;
    Arc::new(p)
}
struct ParamReservation {
    ledger: Arc<Mutex<Ledger>>,
    key: Key,
    bytes: usize,
}
impl Drop for ParamReservation {
    fn drop(&mut self) {
        if self.bytes > 0 {
            let mut l = self.ledger.lock().unwrap_or_else(|e| e.into_inner());
            if let Some(node) = l.nodes.get_mut(&self.key) {
                node.param_reserved = node.param_reserved.saturating_sub(self.bytes);
            }
        }
    }
}
fn node_admission(
    ledger: &Arc<Mutex<Ledger>>,
    input: &Arc<EffectInput>,
    key: Key,
    bytes: usize,
) -> Result<ParamReservation, String> {
    let mut l = ledger.lock().unwrap_or_else(|e| e.into_inner());
    let reserved = if let Some(old) = l.nodes.get(&key) {
        if !old.input.ptr_eq(&Arc::downgrade(input)) {
            return Err("purity query key belongs to another issuance".into());
        }
        l.admit(bytes)?;
        let node = l.nodes.get_mut(&key).unwrap();
        node.param_reserved = node
            .param_reserved
            .checked_add(bytes)
            .ok_or("purity parameter reservation overflow")?;
        bytes
    } else {
        if l.nodes.len() >= MAX_NODES {
            l.denied = true;
            return Err("purity immutable query-node bound exceeded".into());
        }
        l.admit(NODE_BOUND.saturating_add(bytes))?;
        // Reserve immutable node/Params metadata before the parent edge or Arc
        // allocation. The placeholder survives failures until ordinary pruning.
        l.nodes.insert(
            key,
            NodeLease {
                input: Arc::downgrade(input),
                params: None,
                param_size: bytes,
                param_reserved: 0,
                observed_edges: 0,
            },
        );
        0
    };
    Ok(ParamReservation {
        ledger: Arc::clone(ledger),
        key,
        bytes: reserved,
    })
}
fn remember_params<T: Any + Send + Sync>(
    ledger: &Arc<Mutex<Ledger>>,
    input: &Arc<EffectInput>,
    key: Key,
    params: &Arc<T>,
) {
    remember_params_with_backing(ledger,input,key,params,0)
}
fn remember_params_with_backing<T: Any + Send + Sync>(
    ledger: &Arc<Mutex<Ledger>>,
    input: &Arc<EffectInput>,
    key: Key,
    params: &Arc<T>,
    extra:usize,
) {
    let erased: Value = params.clone();
    let mut l = ledger.lock().unwrap_or_else(|e| e.into_inner());
    let node = l
        .nodes
        .get_mut(&key)
        .expect("Params node was reserved before allocation");
    debug_assert!(node.input.ptr_eq(&Arc::downgrade(input)));
    node.params = Some(Arc::downgrade(&erased));
    node.param_size = std::mem::size_of::<T>().saturating_add(extra);
}
fn edge(ledger: &Arc<Mutex<Ledger>>, from: Key) -> Result<(), String> {
    let mut l = ledger.lock().unwrap_or_else(|e| e.into_inner());
    l.admit(EDGE_BOUND)?;
    let n = l
        .nodes
        .get_mut(&from)
        .ok_or("purity dependency node was not preadmitted")?;
    n.observed_edges = n
        .observed_edges
        .checked_add(1)
        .ok_or("purity edge metadata overflow")?;
    Ok(())
}
fn checked_sources(input:&EffectInput,keys:&[Key],sources:&SourceRegistry)->Result<(),String>{checked_sources_using(input,keys,sources,||crate::daemon::control::checkpoint().map_err(|error|error.to_string()))}
fn checked_sources_using<E:From<String>+for<'a>From<&'a str>>(
    input: &EffectInput,
    keys: &[Key],
    sources: &SourceRegistry,
    mut checkpoint:impl FnMut()->Result<(),E>,
) -> Result<(), E> {
    if input.is_original_checker_source(){checkpoint()?;input.require_original_checker_source()?;if !keys.is_empty(){return Err("diagnostic body input cannot claim compiler source-key authority".into())}return Ok(())}
    let current = sources.lock().unwrap_or_else(|e| e.into_inner());
    if current.len() != keys.len() || !current.values().map(|x| x.0).eq(keys.iter().copied()) {
        return Err("purity dependency roster is not the current compiler roster".into());
    }
    for (index, (path, lease)) in input
        .archive()
        .source_mapping()
        .source_acquisitions()
        .enumerate()
    {
        if index % 128 == 0 {
            checkpoint()?;
        }
        let lease = lease.ok_or("purity source acquisition is unissued")?;
        let canonical = dm_preprocess::regions::canonical_path(path);
        let source = &current
            .get(&canonical)
            .ok_or("purity original compiled input is absent from current Db")?
            .1;
        if !source.original().same_view(&lease.source_text()) {
            return Err(
                "purity compiled input owner differs from current archive acquisition".into(),
            );
        }
    }
    Ok(())
}
fn observe_program(
    ctx: &mut dm_query::Ctx<'_>,
    ledger: &Arc<Mutex<Ledger>>,
    from: Key,
    input:&EffectInput,
    keys: &Arc<Vec<Key>>,
) -> Result<(), QueryError> {
    if input.is_original_checker_source(){input.require_original_checker_source().map_err(|_|QueryError::Missing(from))?;return publication_checkpoint(ledger,from)}
    edge(ledger, from).map_err(|_| QueryError::Missing(from))?;
    ctx.observe_input(PROJECT_KEY)?;
    edge(ledger, from).map_err(|_| QueryError::Missing(from))?;
    ctx.get::<u128>(PROGRAM_KEY, keys.clone())?;
    Ok(())
}
fn execution_admission(ledger: &Arc<Mutex<Ledger>>) -> ExecutionAdmission {
    #[cfg(test)]
    if let Some(limit) = ledger
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .storage_test_limit
    {
        return ExecutionAdmission::with_limit(limit);
    }
    #[cfg(not(test))]
    let _ = ledger;
    ExecutionAdmission::default()
}
fn latch_transient_denial(ledger: &Arc<Mutex<Ledger>>, admission: &ExecutionAdmission) {
    if admission.is_denied() {
        ledger.lock().unwrap_or_else(|e| e.into_inner()).denied = true
    }
}
fn size_error<T>(value: &Result<Arc<T>, String>, size: impl FnOnce(&T) -> usize) -> usize {
    value.as_ref().map_or_else(
        |e| {
            e.capacity()
                .saturating_add(std::mem::size_of_val(value))
                .saturating_add(64)
        },
        |v| size(v).saturating_add(64),
    )
}
fn execution_checkpoint(ledger: &Arc<Mutex<Ledger>>) -> Result<(), String> {
    if let Err(error) = crate::daemon::control::checkpoint() {
        let message = error.to_string();
        let mut l = ledger.lock().unwrap_or_else(|e| e.into_inner());
        if l.aborted.is_none() {
            l.aborted = Some(error);
        }
        return Err(message);
    }
    if let Some(error) = ledger
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .aborted
        .as_ref()
    {
        return Err(error.to_string());
    }
    Ok(())
}
fn job_checkpoint(ledger: &Arc<Mutex<Ledger>>, key: Key) -> Result<(), QueryError> {
    execution_checkpoint(ledger).map_err(|_| QueryError::Missing(key))
}
fn publication_checkpoint(ledger: &Arc<Mutex<Ledger>>, key: Key) -> Result<(), QueryError> {
    #[cfg(test)]
    cancellation_test_checkpoint(key.kind);
    job_checkpoint(ledger, key)
}
fn keep(ledger:&Arc<Mutex<Ledger>>,key:Key,owner:Value,bytes:usize,error:bool)->Result<(),QueryError>{keep_using(ledger,key,owner,bytes,error,publication_checkpoint,|key,_|QueryError::Missing(key))}
fn keep_using(
    ledger: &Arc<Mutex<Ledger>>,
    key: Key,
    owner: Value,
    bytes: usize,
    error: bool,
    check:fn(&Arc<Mutex<Ledger>>,Key)->Result<(),QueryError>,
    allocation:fn(Key,std::collections::TryReserveError)->QueryError,
) -> Result<(), QueryError> {
    check(ledger, key)?;
    let mut l = ledger.lock().unwrap_or_else(|e| e.into_inner());
    if l.denied || l.aborted.is_some() {
        return Err(QueryError::Missing(key));
    }
    let growth = if l.live.len() == l.live.capacity() {
        std::mem::size_of::<Live>()
    } else {
        0
    };
    l.admit(bytes.saturating_add(growth))
        .map_err(|_| QueryError::Missing(key))?;
    if let Err(actual)=l.live.try_reserve_exact(1) {
        l.denied = true;
        return Err(allocation(key,actual));
    }
    l.live.push(Live {
        owner: Arc::downgrade(&owner),
        completion:None,
        bytes,
        kind: key.kind,
        error,
    });
    Ok(())
}
fn finish<T:Any+Send+Sync>(ledger:&Arc<Mutex<Ledger>>,key:Key,value:Result<Arc<T>,String>,bytes:usize)->Result<Outcome,QueryError>{finish_using(ledger,key,value,bytes,publication_checkpoint,|key,_|QueryError::Missing(key))}
fn finish_using<T: Any + Send + Sync>(
    ledger: &Arc<Mutex<Ledger>>,
    key: Key,
    value: Result<Arc<T>, String>,
    bytes: usize,
    check:fn(&Arc<Mutex<Ledger>>,Key)->Result<(),QueryError>,
    allocation:fn(Key,std::collections::TryReserveError)->QueryError,
) -> Result<Outcome, QueryError> {
    check(ledger, key)?;
    let success = value.as_ref().ok().map(|v| {
        let erased: Value = v.clone();
        erased
    });
    let error = value.is_err();
    let outcome = Outcome::new(value, key.id, bytes);
    keep_using(
        ledger,
        key,
        success.unwrap_or_else(|| Arc::clone(&outcome.value)),
        bytes,
        error,
        check,
        allocation,
    )?;
    Ok(outcome)
}
/// Transport errors are not native policy refusals. This operation-local
/// sum never becomes an Outcome; split_transport removes Query before finish.
#[derive(Debug)]
enum ReadFailure {
    Semantic(String),
    Query(QueryError),
}
impl From<String> for ReadFailure {
    fn from(e: String) -> Self {
        Self::Semantic(e)
    }
}
impl From<&str> for ReadFailure {
    fn from(e: &str) -> Self {
        Self::Semantic(e.into())
    }
}
fn policy_read_failure(
    key: Key,
    error: dm_analysis::policy_body_demand::PolicyFailure,
) -> ReadFailure {
    match error {
        dm_analysis::policy_body_demand::PolicyFailure::Unsupported(error) => {
            ReadFailure::Semantic(error.0)
        }
        dm_analysis::policy_body_demand::PolicyFailure::Operational(error) => {
            ReadFailure::Query(QueryError::operational(key, error))
        }
    }
}
fn split_transport<T>(result: Result<T, ReadFailure>) -> Result<Result<T, String>, QueryError> {
    match result {
        Ok(v) => Ok(Ok(v)),
        Err(ReadFailure::Semantic(e)) => Ok(Err(e)),
        Err(ReadFailure::Query(e)) => Err(e),
    }
}
fn get_body(
    ctx: &mut dm_query::Ctx<'_>,
    ledger: &Arc<Mutex<Ledger>>,
    parent: &Params,
    ordinal: usize,
) -> Result<Arc<BodyEffects>, ReadFailure> {
    get_body_with_admission(ctx,ledger,parent,ordinal,None)
}
fn get_body_with_admission(
    ctx: &mut dm_query::Ctx<'_>,
    ledger: &Arc<Mutex<Ledger>>,
    parent: &Params,
    ordinal: usize,
    live:Option<&ExecutionAdmission>,
) -> Result<Arc<BodyEffects>, ReadFailure> {
    let input = parent.input.upgrade().ok_or("purity input expired")?;
    let k = key(BODY, &input, ordinal as u128);
    let extra=live.map_or(0,|_|ExecutionAdmission::fixed_control_charge());let bytes=std::mem::size_of::<Params>().checked_add(extra).ok_or("original BODY parameter backing overflow")?;let _reservation=node_admission(ledger,&input,k,bytes)?;
    edge(ledger, parent.key)?;
    let mut actual=parent.clone();actual.body_admission=live.map(ExecutionAdmission::downgrade_for_job);if let Some(loan)=&actual.body_admission{let headroom=pages::page_execution_headroom(ledger)?;loan.upgrade_for_job(headroom).map_err(|e|ReadFailure::Query(QueryError::operational(k,e)))?;}let q=params_for(&actual,BODY,ordinal as u128);
    remember_params_with_backing(ledger,&input,k,&q,extra);
    ctx.get::<Result<Arc<BodyEffects>, String>>(k, q)
        .map_err(ReadFailure::Query)?
        .as_ref()
        .clone()
        .map_err(ReadFailure::Semantic)
}
fn get_plan(
    ctx: &mut dm_query::Ctx<'_>,
    ledger: &Arc<Mutex<Ledger>>,
    p: &Params,
) -> Result<Arc<EffectPlan>, ReadFailure> {
    let input = p.input.upgrade().ok_or("purity input expired")?;
    let k = key(PLAN, &input, 0);
    let _reservation = node_admission(ledger, &input, k, std::mem::size_of::<Params>())?;
    edge(ledger, p.key)?;
    let q = params_for(p, PLAN, 0);
    remember_params(ledger, &input, k, &q);
    ctx.get::<Result<Arc<EffectPlan>, String>>(k, q)
        .map_err(ReadFailure::Query)?
        .as_ref()
        .clone()
        .map_err(ReadFailure::Semantic)
}
fn get_scc(
    ctx: &mut dm_query::Ctx<'_>,
    ledger: &Arc<Mutex<Ledger>>,
    p: &Params,
) -> Result<Arc<SccSummary>, ReadFailure> {
    let input = p.input.upgrade().ok_or("purity input expired")?;
    let k = key(SCC, &input, 0);
    let _reservation = node_admission(ledger, &input, k, std::mem::size_of::<Params>())?;
    edge(ledger, p.key)?;
    let q = params_for(p, SCC, 0);
    remember_params(ledger, &input, k, &q);
    ctx.get::<Result<Arc<SccSummary>, String>>(k, q)
        .map_err(ReadFailure::Query)?
        .as_ref()
        .clone()
        .map_err(ReadFailure::Semantic)
}
struct Observed<'a, 'b> {
    ctx: Mutex<&'a mut dm_query::Ctx<'b>>,
    input: &'a Arc<EffectInput>,
    sources: Arc<Vec<Key>>,
    registry: SourceRegistry,
    ledger: Arc<Mutex<Ledger>>,
    parent: Key,
    error: Mutex<Option<ReadFailure>>,
}
impl Observed<'_, '_> {
    fn finish(&self) -> Result<(), ReadFailure> {
        self.error
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
            .map_or(Ok(()), Err)
    }
    fn fail(&self, error: ReadFailure) {
        let mut first = self.error.lock().unwrap_or_else(|e| e.into_inner());
        if first.is_none()
            || matches!(
                (&*first, &error),
                (Some(ReadFailure::Semantic(_)), ReadFailure::Query(_))
            )
        {
            *first = Some(error);
        }
    }
}
impl Resolver for Observed<'_, '_> {
    fn source_owner(&self) -> Option<*const ()> {
        Resolver::source_owner(self.input.archive().tree())
    }
    fn resolve(&self, q: ResolveQuery) -> ResolvedMeaning {
        if let Err(e) = execution_checkpoint(&self.ledger) {
            self.fail(ReadFailure::Semantic(e));
            return ResolvedMeaning::Unsupported(q);
        }
        if let Err(e) = checked_sources(self.input, &self.sources, &self.registry) {
            self.fail(ReadFailure::Semantic(e));
            return ResolvedMeaning::Unsupported(q);
        }
        let k = key(RESOLVER, self.input, query_id(&q));
        if self
            .error
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .is_some()
        {
            return ResolvedMeaning::Unsupported(q);
        }
        let result = (|| -> Result<ResolvedMeaning, ReadFailure> {
            let _reservation = node_admission(
                &self.ledger,
                self.input,
                k,
                std::mem::size_of::<ResolveParams>(),
            )?;
            edge(&self.ledger, self.parent)?;
            let p = Arc::new(ResolveParams {
                input: Arc::downgrade(self.input),
                key: k,
                query: q,
                sources: Arc::clone(&self.sources),
            });
            remember_params(&self.ledger, self.input, k, &p);
            let mut ctx = self.ctx.lock().unwrap_or_else(|e| e.into_inner());
            let proof = ctx.get::<u128>(k, p).map_err(ReadFailure::Query)?;
            let answer = Resolver::resolve(self.input.archive().tree(), q);
            if *proof != answer_hash(&answer) {
                return Err("purity original resolver answer differs from dependency hash".into());
            }
            fn settings(
                ctx: &mut dm_query::Ctx<'_>,
                input: &EffectInput,
                value: &ResolvedMeaning,
                ledger: &Arc<Mutex<Ledger>>,
                parent: Key,
            ) -> Result<(), ReadFailure> {
                match value {
                    ResolvedMeaning::Declaration { identity, .. } => {
                        if let Some(ordinal) = input.ordinal_for(*identity) {
                            let s = input
                                .archive()
                                .syntax_inputs()
                                .and_then(|v| v.get(ordinal))
                                .ok_or("purity source settings input missing")?;
                            edge(ledger, parent)?;
                            body_syntax::observe(ctx, s).map_err(ReadFailure::Query)?
                        }
                    }
                    ResolvedMeaning::Members(rows) => {
                        for row in rows.iter() {
                            settings(ctx, input, row, ledger, parent)?
                        }
                    }
                    _ => {}
                }
                Ok(())
            }
            settings(&mut ctx, self.input, &answer, &self.ledger, self.parent)?;
            Ok(answer)
        })();
        match result {
            Ok(v) => v,
            Err(e) => {
                self.fail(e);
                ResolvedMeaning::Unsupported(q)
            }
        }
    }
}
pub(super) fn register(db: &Db, ledger: Arc<Mutex<Ledger>>, registry: SourceRegistry) {
    current_variables::register(db,Arc::clone(&ledger));
    pages::register(db,Arc::clone(&ledger),Arc::clone(&registry));
    global_graph::register(db,Arc::clone(&ledger),Arc::clone(&registry));
    global_summary::register(db,Arc::clone(&ledger),Arc::clone(&registry));
    global_report::register(db,Arc::clone(&ledger),Arc::clone(&registry));
    let l = Arc::clone(&ledger);
    let sources = Arc::clone(&registry);
    db.define(RESOLVER, "native-effect-resolver-hash", move |ctx, raw| {
        let p = raw
            .downcast_ref::<ResolveParams>()
            .expect("effect resolver params");
        job_checkpoint(&l, p.key)?;
        let input = p.input.upgrade().ok_or(QueryError::Missing(p.key))?;
        checked_sources(&input, &p.sources, &sources).map_err(|_| QueryError::Missing(p.key))?;
        observe_program(ctx, &l, p.key, &input, &p.sources)?;
        let answer = Resolver::resolve(input.archive().tree(), p.query);
        let hash = answer_hash(&answer);
        let outcome = Outcome::new(hash, hash, 16);
        keep(&l, p.key, Arc::clone(&outcome.value), 16, false)?;
        Ok(outcome)
    });
    let l = Arc::clone(&ledger);
    let sources = Arc::clone(&registry);
    db.define(BODY, "native-body-effects", move |ctx, raw| {
        let p = raw.downcast_ref::<Params>().expect("effect body params");
        job_checkpoint(&l, p.key)?;
        let input = p.input.upgrade().ok_or(QueryError::Missing(p.key))?;
        checked_sources(&input, &p.sources, &sources).map_err(|_| QueryError::Missing(p.key))?;
        observe_program(ctx, &l, p.key, &input, &p.sources)?;
        let syntax = input
            .archive()
            .syntax_inputs()
            .and_then(|v| v.get(p.ordinal))
            .ok_or(QueryError::Missing(p.key))?;
        edge(&l, p.key).map_err(|_| QueryError::Missing(p.key))?;
        body_syntax::observe(ctx, syntax)?;
        let resolver = Observed {
            ctx: Mutex::new(ctx),
            input: &input,
            sources: Arc::clone(&p.sources),
            registry: Arc::clone(&sources),
            ledger: Arc::clone(&l),
            parent: p.key,
            error: Mutex::new(None),
        };
        let admission = match &p.body_admission{Some(loan)=>{let headroom=pages::page_execution_headroom(&l).map_err(|message|QueryError::operational(p.key,std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;loan.upgrade_for_job(headroom).map_err(|actual|QueryError::operational(p.key,actual))?},None=>execution_admission(&l)};
        let computed = input.compute_body_checked_controlled(p.ordinal,&resolver,&admission,&||crate::daemon::control::checkpoint());
        let result = resolver
            .finish()
            .and_then(|_| computed.map_err(|e| policy_read_failure(p.key, e)));
        latch_transient_denial(&l, &admission);
        let result = split_transport(result)?;
        let bytes = size_error(&result, BodyEffects::charge);
        finish(&l, p.key, result, bytes)
    });
    let l = Arc::clone(&ledger);
    let sources = Arc::clone(&registry);
    db.define(PLAN, "native-effect-plan", move |ctx, raw| {
        let p = raw.downcast_ref::<Params>().expect("effect plan params");
        job_checkpoint(&l, p.key)?;
        let input = p.input.upgrade().ok_or(QueryError::Missing(p.key))?;
        let admission = execution_admission(&l);
        let result = (|| -> Result<Arc<EffectPlan>, ReadFailure> {
            let bodies = input
                .order()
                .iter()
                .map(|&(i, _)| get_body(ctx, &l, p, i))
                .collect::<Result<Vec<_>, ReadFailure>>()?;
            let resolver = Observed {
                ctx: Mutex::new(ctx),
                input: &input,
                sources: Arc::clone(&p.sources),
                registry: Arc::clone(&sources),
                ledger: Arc::clone(&l),
                parent: p.key,
                error: Mutex::new(None),
            };
            let plan = input.plan_checked_controlled(bodies,&resolver,&admission,&||crate::daemon::control::checkpoint());
            resolver.finish()?;
            plan.map_err(|error|policy_read_failure(p.key,error))
        })();
        latch_transient_denial(&l, &admission);
        let result = split_transport(result)?;
        let bytes = size_error(&result, EffectPlan::charge);
        finish(&l, p.key, result, bytes)
    });
    let l = Arc::clone(&ledger);
    db.define(SCC, "native-effect-SCC", move |ctx, raw| {
        let p = raw.downcast_ref::<Params>().expect("effect SCC params");
        job_checkpoint(&l, p.key)?;
        let input = p.input.upgrade().ok_or(QueryError::Missing(p.key))?;
        let result =
            get_plan(ctx, &l, p).and_then(|p| p.summarize(&input).map_err(ReadFailure::Semantic));
        let result = split_transport(result)?;
        let bytes = size_error(&result, SccSummary::charge);
        finish(&l, p.key, result, bytes)
    });
    for (kind, label) in [
        (REPORT, "native-purity-report"),
        (SLEEP_REPORT, "native-sleep-report"),
    ] {
        let ledger = Arc::clone(&ledger);
        let registry = Arc::clone(&registry);
        db.define(kind, label, move |ctx, raw| {
            let p = raw.downcast_ref::<Params>().expect("effect report params");
            job_checkpoint(&ledger, p.key)?;
            let input = p.input.upgrade().ok_or(QueryError::Missing(p.key))?;
            let admission = execution_admission(&ledger);
            let result = (|| -> Result<Arc<Vec<Produced>>, ReadFailure> {
                let policy = p
                    .policy
                    .upgrade()
                    .ok_or("purity report has no current privately scoped policy")?;
                let summary = if kind == REPORT {
                    Some(get_scc(ctx, &ledger, p)?)
                } else {
                    None
                };
                let plan = if kind == SLEEP_REPORT {
                    Some(get_plan(ctx, &ledger, p)?)
                } else {
                    None
                };
                let resolver = Observed {
                    ctx: Mutex::new(ctx),
                    input: &input,
                    sources: Arc::clone(&p.sources),
                    registry: Arc::clone(&registry),
                    ledger: Arc::clone(&ledger),
                    parent: p.key,
                    error: Mutex::new(None),
                };
                let check = || execution_checkpoint(&ledger);
                let rows = if let Some(summary) = summary {
                    summary.report_checked(&input, &resolver, &policy, &admission, check)
                } else {
                    plan.ok_or("sleep shared plan unavailable")?
                        .sleep_report_checked(&input, &resolver, &policy, &admission, check)
                };
                resolver.finish()?;
                Ok(Arc::new(rows.map_err(|e| policy_read_failure(p.key, e))?))
            })();
            latch_transient_denial(&ledger, &admission);
            let result = split_transport(result)?;
            let bytes = size_error(&result, dm_analysis::checker_effects::report_capacity_bound);
            finish(&ledger, p.key, result, bytes)
        });
    }
}
fn policy_charge(p: &CheckerPolicy) -> usize {
    p.diagnostics
        .iter()
        .fold(std::mem::size_of::<CheckerPolicy>(), |n, (name, _)| {
            n.saturating_add(name.capacity()).saturating_add(NODE_BOUND)
        })
}
struct PolicyWorkingSet {
    ledger: Arc<Mutex<Ledger>>,
}
impl Drop for PolicyWorkingSet {
    fn drop(&mut self) {
        self.ledger
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .active_policy = 0
    }
}
impl QueryDb {
    pub(super) fn prune_purity(&self) {
        let _gate = self.purity.gate.lock().unwrap_or_else(|e| e.into_inner());
        self.prune_purity_under_gate();
    }
    // Callers either acquired the family gate here or are the authenticated
    // current source selection already holding that SAME gate.
    fn prune_purity_under_gate(&self){
        let mut l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
        l.nodes.retain(|key, lease| {
            if if current_variables::is_current_node(*key){current_variables::retains(*key,lease,&self.db)}else{lease.input.strong_count()>0} {
                true
            } else {
                self.db.remove(*key);
                false
            }
        });
        l.contexts.retain(|_, c| c.input.strong_count() > 0);
        l.live_bytes();
    }
    fn purity_sources(&self,input:&Arc<EffectInput>)->Result<Arc<Vec<Key>>,String>{self.purity_sources_using(input,|keys|checked_sources(input,keys,&self.sources),|_|"purity source key allocation refused".to_string())}
    fn purity_sources_using<E:From<String>+for<'a>From<&'a str>>(&self,input:&Arc<EffectInput>,mut check:impl FnMut(&[Key])->Result<(),E>,allocation:impl FnOnce(std::collections::TryReserveError)->E)->Result<Arc<Vec<Key>>,E>{
        let mut l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(c) = l.contexts.get(&input.key()) {
            let keys = Arc::clone(&c.keys);
            if !c.input.ptr_eq(&Arc::downgrade(input)) {
                return Err("purity source context issuance differs".into());
            }
            drop(l);
            check(&keys)?;
            return Ok(keys);
        }
        let current = self.sources.lock().unwrap_or_else(|e| e.into_inner());
        let n = if input.is_original_checker_source(){0}else{current.len()};
        l.admit(
            n.checked_mul(std::mem::size_of::<Key>())
                .and_then(|n| n.checked_add(CONTEXT_BOUND + std::mem::size_of::<Vec<Key>>()))
                .ok_or("purity source roster size overflow")?,
        )?;
        let mut keys = Vec::new();
        keys.try_reserve_exact(n)
            .map_err(allocation)?;
        if !input.is_original_checker_source(){keys.extend(current.values().map(|x| x.0));}
        drop(current);
        let keys = Arc::new(keys);
        check(&keys)?;
        l.contexts.insert(
            input.key(),
            SourceContext {
                input: Arc::downgrade(input),
                keys: Arc::clone(&keys),
            },
        );
        Ok(keys)
    }
    pub(crate) fn native_purity_report(
        &self,
        input: &Arc<EffectInput>,
        scope: &crate::runner_host::query_snapshot::PurityScope<'_>,
    ) -> std::io::Result<Arc<Vec<Produced>>> {
        self.native_effect_report(input, scope, REPORT)
    }
    pub(crate) fn native_sleep_report(
        &self,
        input: &Arc<EffectInput>,
        scope: &crate::runner_host::query_snapshot::PurityScope<'_>,
    ) -> std::io::Result<Arc<Vec<Produced>>> {
        self.native_effect_report(input, scope, SLEEP_REPORT)
    }
    fn native_effect_report(
        &self,
        input: &Arc<EffectInput>,
        scope: &crate::runner_host::query_snapshot::PurityScope<'_>,
        report_kind: Kind,
    ) -> std::io::Result<Arc<Vec<Produced>>> {
        crate::daemon::control::checkpoint()?;
        scope.validate(self, input).map_err(std::io::Error::other)?;
        self.prune_purity();
        let _gate = self.purity.gate.lock().unwrap_or_else(|e| e.into_inner());
        scope.validate(self, input).map_err(std::io::Error::other)?;
        {
            let mut l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
            l.denied = false;
            l.aborted = None;
        }
        let result = (|| -> Result<Arc<Vec<Produced>>, ReadFailure> {
            let sources = self.purity_sources(input)?;
            let k = key(report_kind, input, scope.policy_key());
            let syntax = input
                .archive()
                .syntax_inputs()
                .ok_or("purity original syntax inputs unavailable")?;
            syntax
                .iter()
                .try_fold(0usize, |n, s| {
                    n.checked_add(s.budget_charge())
                        .filter(|&n| n <= body_syntax::BUDGET)
                })
                .ok_or("purity syntax cohort exceeds existing parser budget")?;
            {
                let mut inputs = self.body_inputs.lock().unwrap_or_else(|e| e.into_inner());
                for s in syntax {
                    inputs
                        .entry(Key::new(body_syntax::BODY_SYNTAX, s.key().into()))
                        .or_insert_with(|| Arc::downgrade(s));
                }
            }
            let size = policy_charge(scope.policy());
            {
                let mut l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
                l.admit(size)?;
                l.active_policy = size;
            }
            let _working = PolicyWorkingSet {
                ledger: Arc::clone(&self.purity.ledger),
            };
            let policy = Arc::new(scope.policy().clone());
            let _reservation =
                node_admission(&self.purity.ledger, input, k, std::mem::size_of::<Params>())?;
            let p = Arc::new(Params{
                body_admission:None,input: Arc::downgrade(input),
                key: k,
                ordinal: 0,
                sources,
                policy: Arc::downgrade(&policy),
            });
            remember_params(&self.purity.ledger, input, k, &p);
            let result = self
                .db
                .get::<Result<Arc<Vec<Produced>>, String>>(k, p)
                .map_err(ReadFailure::Query)?;
            scope.validate(self, input)?;
            result.as_ref().clone().map_err(ReadFailure::Semantic)
        })();
        // Still under the family gate: do not race a new query resetting the
        // operational latch, and never downgrade the actual IO failure.
        let _ = execution_checkpoint(&self.purity.ledger);
        if let Some(error) = self
            .purity
            .ledger
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .aborted
            .take()
        {
            return Err(error);
        }
        match result {
            Ok(value) => Ok(value),
            Err(ReadFailure::Semantic(message)) => Err(std::io::Error::other(message)),
            Err(ReadFailure::Query(error)) => match error.into_operational() {
                Ok(error) => Err(error.into_io()),
                Err(error) => Err(std::io::Error::other(format!(
                    "native purity graph job: {error:?}"
                ))),
            },
        }
    }
}
impl QueryDb {
    pub(crate) fn purity_census(&self, census: &mut crate::heap_census::HeapCensus) {
        use dm_analysis::checker_effects::Storage;
        let _gate = self.purity.gate.lock().unwrap_or_else(|e| e.into_inner());
        let mut l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
        l.live_bytes();
        let mut visit = |s| {
            match s{Storage::Buffer{owner,address,logical,capacity}=>{census.exposed_buffer(owner,address,logical,capacity);},Storage::Unknown{owner,items}=>census.unknown(owner,&format!("{items} logical entries; private BTree node capacity and allocator overhead unknown"))}
        };
        for c in l.contexts.values() {
            if let Some(input) = c.input.upgrade() {
                input.visit_storage(&mut visit)
            }
            visit(Storage::Buffer {
                owner: "purity.source_key_vector",
                address: Arc::as_ptr(&c.keys) as usize,
                logical: std::mem::size_of::<Vec<Key>>(),
                capacity: std::mem::size_of::<Vec<Key>>(),
            });
            visit(Storage::Buffer {
                owner: "purity.source_key_buffer",
                address: c.keys.as_ptr() as usize,
                logical: c.keys.len().saturating_mul(std::mem::size_of::<Key>()),
                capacity: c.keys.capacity().saturating_mul(std::mem::size_of::<Key>()),
            });
        }
        for node in l.nodes.values() {
            if let Some(params) = node.params.as_ref().and_then(Weak::upgrade) {
                visit(Storage::Buffer {
                    owner: "purity.immutable_params",
                    address: Arc::as_ptr(&params) as *const () as usize,
                    logical: node.param_size,
                    capacity: node.param_size,
                });
            }
        }
        for live in &l.live {
            let Some(value) = live.owner.upgrade() else {
                continue;
            };
            if live.kind==current_variables::CURRENT_VARIABLES{if let Some(value)=value.downcast_ref::<current_variables::NativeCurrentVariables>(){value.visit_storage(&mut visit);}}
            if live.kind==current_variables::CURRENT_LOOKUP{if let Some(value)=value.downcast_ref::<current_variables::NativeCurrentLookup>(){value.visit_storage(&mut visit);}}
            if live.error {
                let error = if live.kind == global_report::PURE||live.kind == global_report::SLEEP {
                    value.downcast_ref::<Result<Arc<global_report::NativeEffectReport>,String>>().and_then(|result|result.as_ref().err())
                }else if live.kind == global_summary::SUMMARY {
                    value.downcast_ref::<Result<Arc<global_summary::NativeEffectSummary>,String>>().and_then(|result|result.as_ref().err())
                } else if live.kind == global_graph::GLOBAL_GRAPH {
                    value.downcast_ref::<Result<Arc<global_graph::NativeEffectGraph>,String>>().and_then(|result|result.as_ref().err())
                } else if live.kind == pages::PAGE {
                    value.downcast_ref::<Result<Arc<pages::NativeEffectPage>,String>>().and_then(|x|x.as_ref().err())
                } else if live.kind == BODY {
                    value
                        .downcast_ref::<Result<Arc<BodyEffects>, String>>()
                        .and_then(|x| x.as_ref().err())
                } else if live.kind == PLAN {
                    value
                        .downcast_ref::<Result<Arc<EffectPlan>, String>>()
                        .and_then(|x| x.as_ref().err())
                } else if live.kind == SCC {
                    value
                        .downcast_ref::<Result<Arc<SccSummary>, String>>()
                        .and_then(|x| x.as_ref().err())
                } else if (live.kind == REPORT || live.kind == SLEEP_REPORT) {
                    value
                        .downcast_ref::<Result<Arc<Vec<Produced>>, String>>()
                        .and_then(|x| x.as_ref().err())
                } else {
                    None
                };
                if let Some(s) = error {
                    visit(Storage::Buffer {
                        owner: "purity.cached_error_text",
                        address: s.as_ptr() as usize,
                        logical: s.len(),
                        capacity: s.capacity(),
                    });
                }
            } else if live.kind == global_report::PURE||live.kind == global_report::SLEEP {
                if let Some(value)=value.downcast_ref::<global_report::NativeEffectReport>(){value.visit_storage(&mut visit)}
            } else if live.kind == global_summary::SUMMARY {
                if let Some(value)=value.downcast_ref::<global_summary::NativeEffectSummary>(){value.visit_storage(&mut visit)}
            } else if live.kind == global_graph::GLOBAL_GRAPH {
                if let Some(value)=value.downcast_ref::<global_graph::NativeEffectGraph>(){value.visit_storage(&mut visit)}
            } else if live.kind == pages::PAGE {
                if let Some(value)=value.downcast_ref::<pages::NativeEffectPage>(){value.visit_storage(&mut visit)}
            } else if live.kind == BODY {
                if let Some(v) = value.downcast_ref::<BodyEffects>() {
                    v.visit_storage(&mut visit)
                }
            } else if live.kind == PLAN {
                if let Some(v) = value.downcast_ref::<EffectPlan>() {
                    v.visit_storage(&mut visit)
                }
            } else if live.kind == SCC {
                if let Some(v) = value.downcast_ref::<SccSummary>() {
                    v.visit_storage(&mut visit)
                }
            } else if (live.kind == REPORT || live.kind == SLEEP_REPORT) {
                if let Some(v) = value.downcast_ref::<Vec<Produced>>() {
                    dm_analysis::checker_effects::visit_report(v, &mut visit)
                }
            } else if live.kind == RESOLVER {
                visit(Storage::Buffer {
                    owner: "purity.resolver_hash",
                    address: Arc::as_ptr(&value) as *const () as usize,
                    logical: 16,
                    capacity: 16,
                });
            }
        }
        drop(visit);
        census.exposed_buffer(
            "purity.weak_live_value_ledger",
            l.live.as_ptr() as usize,
            l.live.len().saturating_mul(std::mem::size_of::<Live>()),
            l.live
                .capacity()
                .saturating_mul(std::mem::size_of::<Live>()),
        );
        if l.aborted.is_some() {
            census.unknown("purity.operational_failure","actual io::Error preserved after interrupted work; opaque standard-library error payload capacity is not exposed");
        }
        census.unknown("purity.query_graph_bookkeeping",&format!("{} immutable nodes, {} contexts; private BTree/Db nodes, dependency and reverse-edge containers plus Arc headers remain unknown. Conservative metadata admission {} bytes is NOT exact heap usage",l.nodes.len(),l.contexts.len(),l.metadata()));
    }
    #[cfg(test)]
    pub(crate) fn purity_cache_probe(&self) -> (usize, usize, usize) {
        let _gate = self.purity.gate.lock().unwrap_or_else(|e| e.into_inner());
        let mut l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
        let live = l.live_bytes();
        (l.nodes.len(), l.metadata(), live)
    }
}
#[cfg(test)]
mod retention_budget_tests {
    use super::*;
    #[test]
    fn metadata_admission_is_checked_before_reserving_query_storage() {
        let mut l = Ledger::default();
        assert!(l.admit(BUDGET).is_ok());
        assert!(l.admit(BUDGET + 1).is_err());
        assert!(l.admit(usize::MAX).is_err());
        l.active_policy = BUDGET;
        assert!(l.admit(1).is_err());
    }
    #[test]
    fn held_outputs_remain_charged_after_cache_owner_is_dropped() {
        let ledger = Arc::new(Mutex::new(Ledger::default()));
        let rows: Value = Arc::new(vec![1u8; 4096]);
        let weak = Arc::downgrade(&rows);
        keep(&ledger, Key::new(REPORT, 1), Arc::clone(&rows), 4096, false).unwrap();
        assert_eq!(ledger.lock().unwrap().live_bytes(), 4096);
        drop(rows);
        assert!(weak.upgrade().is_none());
        assert_eq!(ledger.lock().unwrap().live_bytes(), 0);
        assert!(
            ledger.lock().unwrap().metadata() > 0,
            "retained ledger capacity still counts"
        );
    }
}

#[cfg(test)]
mod reservation_tests {
    use super::*;
    #[test]
    fn replacement_parameter_reservation_counts_peak_overlap_and_releases_on_error_exit() {
        let ledger = Arc::new(Mutex::new(Ledger::default()));
        let k = Key::new(BODY, 99);
        ledger.lock().unwrap().nodes.insert(
            k,
            NodeLease {
                input: Weak::new(),
                params: None,
                param_size: 64,
                param_reserved: 32,
                observed_edges: 1,
            },
        );
        let before = ledger.lock().unwrap().metadata();
        {
            let _reservation = ParamReservation {
                ledger: Arc::clone(&ledger),
                key: k,
                bytes: 32,
            };
            assert!(ledger.lock().unwrap().metadata() >= NODE_BOUND + 64 + 32 + EDGE_BOUND);
        }
        assert_eq!(ledger.lock().unwrap().metadata(), before - 32);
    }
    #[test]
    fn denied_budget_never_publishes_an_empty_or_cached_error_outcome() {
        let ledger = Arc::new(Mutex::new(Ledger::default()));
        assert!(ledger.lock().unwrap().admit(BUDGET + 1).is_err());
        let value: Result<Arc<Vec<Produced>>, String> = Err("bounded refusal text".into());
        assert!(finish(&ledger, Key::new(REPORT, 42), value, 32).is_err());
        assert!(ledger.lock().unwrap().live.is_empty());
    }
}

// Test-only scheduling invokes the REAL request cancellation token at a
// semantic publication boundary. It cannot fabricate facts or cache values.
#[cfg(test)]
thread_local! {static CANCEL_CHECKPOINT:std::cell::RefCell<Option<(Kind,crate::daemon::control::Cancellation)>>=const{std::cell::RefCell::new(None)};}
#[cfg(test)]
pub(crate) struct EffectCancellationSchedule;
#[cfg(test)]
impl Drop for EffectCancellationSchedule {
    fn drop(&mut self) {
        CANCEL_CHECKPOINT.with(|s| *s.borrow_mut() = None);
    }
}
#[cfg(test)]
fn cancellation_test_checkpoint(kind: Kind) {
    CANCEL_CHECKPOINT.with(|s| {
        let mut slot = s.borrow_mut();
        if let Some((wanted, token)) = slot.as_mut() {
            if *wanted == kind {
                token.cancel();
                *slot = None;
            }
        }
    })
}
#[cfg(test)]
impl QueryDb {
    pub(crate) fn cancel_effect_before_publication_for_test(
        &self,
        kind: Kind,
        token: crate::daemon::control::Cancellation,
    ) -> EffectCancellationSchedule {
        CANCEL_CHECKPOINT.with(|s| {
            assert!(
                s.borrow().is_none(),
                "one explicit cancellation schedule per thread"
            );
            *s.borrow_mut() = Some((kind, token));
        });
        EffectCancellationSchedule
    }
    #[cfg(test)]
    pub(crate) fn effect_dependency_count_for_test(&self,kind:Kind)->usize{let _gate=self.purity.gate.lock().unwrap_or_else(|e|e.into_inner());self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).nodes.iter().filter(|(key,_)|key.kind==kind).map(|(_,node)|node.observed_edges).sum()}
    pub(crate) fn effect_retained_values_for_test(&self, kind: Kind) -> usize {
        let _gate = self.purity.gate.lock().unwrap_or_else(|e| e.into_inner());
        let l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
        l.nodes
            .keys()
            .filter(|key| key.kind == kind && self.db.value_bytes_at(**key) > 0)
            .count()
    }
}

#[cfg(test)]
mod policy_capacity_tests {
    use super::*;
    #[test]
    fn active_policy_admission_accounts_spare_owned_key_capacity() {
        let mut policy = CheckerPolicy::default();
        let mut name = String::from("must_be_pure");
        let initial_capacity = name.capacity();
        name.reserve_exact(8192);
        let extra = name.capacity() - initial_capacity;
        assert!(extra > 0);
        let mut ordinary = CheckerPolicy::default();
        ordinary.diagnostics.insert(
            "must_be_pure".to_owned(),
            dm_analysis::check_policy::WarningLevel::Warning,
        );
        policy
            .diagnostics
            .insert(name, dm_analysis::check_policy::WarningLevel::Warning);
        assert_eq!(policy_charge(&policy) - policy_charge(&ordinary), extra);
        assert_eq!(policy, ordinary);
    }
}

#[cfg(test)]
pub(crate) struct EffectStorageTestLimit<'a> {
    queries: &'a QueryDb,
    previous: Option<usize>,
}
#[cfg(test)]
impl Drop for EffectStorageTestLimit<'_> {
    fn drop(&mut self) {
        let _gate = self
            .queries
            .purity
            .gate
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        self.queries
            .purity
            .ledger
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .storage_test_limit = self.previous;
    }
}
#[cfg(test)]
impl QueryDb {
    /// Test changes only an operation's allocation allowance, never source facts.
    pub(crate) fn effect_storage_limit_for_test(&self, limit: usize) -> EffectStorageTestLimit<'_> {
        let _gate = self.purity.gate.lock().unwrap_or_else(|e| e.into_inner());
        let mut l = self.purity.ledger.lock().unwrap_or_else(|e| e.into_inner());
        let previous = l.storage_test_limit.replace(limit);
        EffectStorageTestLimit {
            queries: self,
            previous,
        }
    }
}

#[path="purity_pages.rs"]
pub(super) mod pages;

#[path="purity_graph_work.rs"]mod graph_work;
#[path="purity_global_graph.rs"]pub(super) mod global_graph;
#[cfg(test)]impl QueryDb{pub(crate) fn effect_graph_work_for_test(&self)->usize{self.purity.ledger.lock().unwrap_or_else(|e|e.into_inner()).active_graph_work}}

#[cfg(test)]impl QueryDb{pub(crate) fn effect_graph_ledger_liveness_for_test(&self)->impl Fn()->bool+Send+'static{let weak=Arc::downgrade(&self.purity.ledger);move||weak.strong_count()!=0}}

#[path="purity_global_summary.rs"]pub(super) mod global_summary;

#[path="purity_global_report.rs"]pub(super) mod global_report;

#[path="purity_report_wire.rs"]pub(super) mod report_wire;

#[path="purity_current_variables.rs"]pub(super) mod current_variables;
