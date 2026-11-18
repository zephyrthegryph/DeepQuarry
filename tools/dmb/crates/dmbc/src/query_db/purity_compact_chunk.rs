//! Private real query proof for bounded canonical BODY chunks.
use super::*;
use dm_analysis::{checker_effects::{CompactGraphPage, CompactGraphPageBuilder, EffectReportWork}, policy_body_demand::PolicyFailure};
use std::{io, path::Path};

fn trace_compact_checker() -> bool {
    cfg!(debug_assertions) && std::env::var_os("DMB_ORIGINAL_TRACE_STAGES").is_some()
}

const MODEL: Kind = Kind(31);
const CHUNK: Kind = Kind(32);
use dm_analysis::checker_order::{ARCHIVED_CHUNK_WIDTH as WIDTH, ArchivedChunkOrdinals};

struct Model(Weak<EffectInput>);
struct Params {
    input: Weak<EffectInput>,
    model: Key,
    key: Key,
    start: usize,
    count: usize,
    old_edges: usize,
    edges: std::sync::atomic::AtomicUsize,
    stage: Option<Weak<Mutex<BodyStageSlot>>>,
    order: Option<ArchivedChunkOrdinals>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Disposition { Missing, FalsePresence, EmptyMembers, Unissued, Present }

#[derive(Clone, Copy)]
struct Lookup { query: ResolveQuery, answer: u128, disposition: Disposition }

struct Data {
    page: CompactGraphPage,
    lookups: Vec<Lookup>,
    staged: Option<u64>,
}

struct Chunk {
    data: Data,
    _lease: graph_work::GraphLease,
}

impl graph_work::RetainedHandle for Chunk {
    type Data = Data;
    fn issue(data: Data, ledger: Arc<Mutex<Ledger>>, completion: Arc<std::sync::atomic::AtomicBool>) -> Arc<Self> {
        Arc::new(Self { data, _lease: graph_work::GraphLease::new(ledger, completion) })
    }
    fn coordination_charge() -> usize {
        std::mem::size_of::<Self>() - std::mem::size_of::<CompactGraphPage>()
            + 2 * std::mem::size_of::<usize>()
    }
    fn retained_charge(&self) -> Option<usize> {
        self.data.page.retained_charge()?.checked_add(Self::coordination_charge())?
            .checked_add(self.data.lookups.capacity().checked_mul(std::mem::size_of::<Lookup>())?)
    }
    fn fingerprint(&self, key: Key) -> u128 {
        // The key is qualified by immutable authenticated EffectInput
        // issuance/range. Real Kind4 and model edges are separately observed.
        let mut hash = xxhash_rust::xxh3::Xxh3::new();
        hash.update(&key.id.to_le_bytes());
        for row in &self.data.lookups {
            hash.update(&query_id(&row.query).to_le_bytes());
            hash.update(&row.answer.to_le_bytes());
            hash.update(&[row.disposition as u8]);
        }
        hash.digest128()
    }
}

fn oom(message: &'static str) -> io::Error { io::Error::new(io::ErrorKind::OutOfMemory, message) }

struct Scratch<'a> {
    work: &'a mut graph_work::GraphWork,
    admission: &'a ExecutionAdmission,
}
impl dm_ir::CanonicalWork for Scratch<'_> {
    fn poll(&mut self) -> io::Result<()> { crate::daemon::control::checkpoint() }
    fn reserve(&mut self, bytes: usize) -> io::Result<()> {
        self.admission.reserve_external(bytes)?;
        self.work.reserve(bytes)
    }
}

struct LookupRecorder<'a> {
    input: &'a EffectInput,
    proof: &'a dm_analysis::checker_effects::OriginalEffectSourceProof<'a>,
    key: Key,
    scratch: Mutex<&'a mut graph_work::GraphWork>,
    admission: &'a ExecutionAdmission,
    output: Mutex<(&'a mut graph_work::GraphWork, &'a mut Vec<Lookup>)>,
    error: Mutex<Option<QueryError>>,
}
impl Resolver for LookupRecorder<'_> {
    fn source_owner(&self) -> Option<*const ()> { Resolver::source_owner(self.input.archive().tree()) }
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        let mut first = self.error.lock().unwrap_or_else(|error| error.into_inner());
        if first.is_some() { return ResolvedMeaning::Unsupported(query); }
        let result = (|| -> io::Result<ResolvedMeaning> {
            crate::daemon::control::checkpoint()?;
            let mut work = self.scratch.lock().unwrap_or_else(|error| error.into_inner());
            let mut scratch = Scratch { work: &mut work, admission: self.admission };
            let answer = self.proof.resolve_with_canonical_work(query, &mut scratch)?;
            let fingerprint = current_variables::current_answer_hash(self.input, query, &answer, &mut scratch, None)?;
            let disposition = match &answer {
                ResolvedMeaning::Missing => Disposition::Missing,
                ResolvedMeaning::Presence(false) => Disposition::FalsePresence,
                ResolvedMeaning::Members(rows) if rows.is_empty() => Disposition::EmptyMembers,
                ResolvedMeaning::Unsupported(_) => Disposition::Unissued,
                _ => Disposition::Present,
            };
            let mut output = self.output.lock().unwrap_or_else(|error| error.into_inner());
            let (work, rows) = &mut *output;
            if rows.len() == rows.capacity() {
                let old = rows.capacity();
                let requested = old.max(2).checked_mul(2).ok_or_else(|| oom("chunk lookup capacity overflow"))?;
                let bound = requested.checked_mul(4).ok_or_else(|| oom("chunk lookup envelope overflow"))?;
                let bytes = bound.checked_mul(std::mem::size_of::<Lookup>()).ok_or_else(|| oom("chunk lookup charge overflow"))?;
                let mark = work.mark()?;
                self.admission.reserve_external(bytes)?;
                work.reserve(bytes)?;
                rows.try_reserve_exact(requested - rows.len()).map_err(|actual| io::Error::new(io::ErrorKind::OutOfMemory, actual))?;
                if rows.capacity() > bound { return Err(oom("chunk lookup allocation exceeds envelope")); }
                work.reconcile(mark, (rows.capacity() - old) * std::mem::size_of::<Lookup>())?;
            }
            rows.push(Lookup { query, answer: fingerprint, disposition });
            Ok(answer)
        })();
        match result {
            Ok(answer) => answer,
            Err(error) => {
                *first = Some(QueryError::operational(self.key, error));
                ResolvedMeaning::Unsupported(query)
            }
        }
    }
}

pub(crate) type BodyRenderer = fn(&EffectInput, &dm_analysis::checker_effects::OriginalBodyDiagnostic,
    dm_analysis::check_policy::DiagnosticSeverity, &mut dyn io::Write) -> io::Result<()>;

struct BodyStageSlot {
    id: u64,
    start: usize,
    total: usize,
    pending: Option<BodyPhases>,
    ready: Option<VerifiedBodyPhases>,
}

#[derive(Clone,Copy,PartialEq,Eq)]
enum BodyFormat{OrderedArray,RegisteredText}

struct VerifiedBodyPhases {
    prelude: crate::selected_report_spool::Verified,
    body: crate::selected_report_spool::Verified,
    clean: bool,
    bodies: usize,
    counts:crate::runner_host::query_snapshot::DiagnosticCounts,
    emitted:usize,
}

/// Issued only after actual body stage sealing and both final graph walks.
/// Its private fields cannot be constructed by report metadata callers.
pub(crate) struct CompletedCompactReport<'a>{input:&'a EffectInput,bodies:usize,graph_visits:[usize;2],graph_targets:usize}
impl CompletedCompactReport<'_>{
 pub(crate) fn body_count_for(&self,input:&EffectInput)->io::Result<usize>{
  if !std::ptr::eq(self.input,input)||self.bodies!=input.archive().len()
   ||self.graph_targets!=input.archive().callables().source_order().len()
   ||self.graph_visits!=[self.graph_targets;2]{
   return Err(io::Error::new(io::ErrorKind::InvalidInput,"compact completion is foreign or incomplete"));
  }Ok(self.bodies)
 }
}

struct BodyPhases {
    id: u64,
    input: u64,
    policy: CheckerPolicy,
    render: BodyRenderer,
    format:BodyFormat,
    counts:crate::runner_host::query_snapshot::DiagnosticCounts,
    emitted:usize,
    prelude: crate::selected_report_spool::Stage,
    body: crate::selected_report_spool::Stage,
    first_prelude: bool,
    first_body: bool,
    rows: usize,
    clean: bool,
}

struct PhaseWrite<'a> {
    phase: &'a mut crate::selected_report_spool::Stage,
    other: u64,
}
impl io::Write for PhaseWrite<'_> {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        const LIMIT: u64 = dq_analyze::selected_exclusions_wire::MAX_STREAM;
        self.phase.length().checked_add(self.other).and_then(|n| n.checked_add(bytes.len() as u64))
            .filter(|n| *n <= LIMIT).ok_or_else(|| oom("combined checker body stage exceeds the private report bound"))?;
        io::Write::write(self.phase, bytes)
    }
    fn flush(&mut self) -> io::Result<()> { io::Write::flush(self.phase) }
}

/// Copy exact configured keys under the SAME live graph work before allocating.
/// NODE_BOUND is this ledger's existing conservative BTree/Db node envelope;
/// key backing uses the existing four-capacity std allocation frontier.
fn funded_body_policy(policy:&CheckerPolicy,work:&mut graph_work::GraphWork)->io::Result<CheckerPolicy>{
    let mut copy=CheckerPolicy{display_error_level:policy.display_error_level,diagnostics:Default::default()};
    for(name,level)in &policy.diagnostics{
        let bound=name.len().checked_mul(4).ok_or_else(||oom("checker policy key capacity overflow"))?;
        work.reserve(NODE_BOUND.checked_add(bound).ok_or_else(||oom("checker policy copy admission overflow"))?)?;
        let mut key=String::new();key.try_reserve_exact(name.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;
        if key.capacity()>bound{return Err(oom("checker policy key exposed excess capacity"))}key.push_str(name);
        copy.diagnostics.insert(key,*level);
    }Ok(copy)
}
impl BodyPhases {
    fn next_id()->io::Result<u64>{
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        NEXT.fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| value.checked_add(1))
            .map_err(|_| oom("checker body staging issuance exhausted"))
    }
    fn new_using(input:&EffectInput,policy:&CheckerPolicy,cache:&Path,render:BodyRenderer,format:BodyFormat,id:u64,work:&mut graph_work::GraphWork)->io::Result<Self>{
        use std::io::Write as _;
        let policy=funded_body_policy(policy,work)?;
        let mut prelude = crate::selected_report_spool::Stage::new(cache)?;
        let mut body = crate::selected_report_spool::Stage::new(cache)?;
        if format==BodyFormat::OrderedArray{prelude.write_all(b"[")?;body.write_all(b"[")?;}
        Ok(Self { id, input: input.key(), policy, render, format, counts:Default::default(),emitted:0,prelude, body,
            first_prelude: true, first_body: true, rows: 0, clean: true })
    }

    fn append(
        &mut self, input: &Arc<EffectInput>, body: &BodyEffects,
        proof: &dm_analysis::checker_effects::OriginalEffectSourceProof<'_>,
    ) -> io::Result<()> {
        use dm_analysis::{check_policy::DiagnosticSeverity as Severity, checker_effects::OriginalDiagnosticPhase};
        use std::io::Write as _;
        if self.input != input.key() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "checker body stage belongs to another input"));
        }
        body.with_original_diagnostics_proven(input, proof, |rows| {
            for row in rows {
                crate::daemon::control::checkpoint()?;
                let Some(severity) = self.policy.register(row.registration_tag(), row.default_level()) else { continue; };
                if self.format==BodyFormat::RegisteredText{self.counts.register(severity)?;}
                if !dm_analysis::check_policy::cli_printed(severity){continue;}
                let (mut stage, first) = match row.phase() {
                    OriginalDiagnosticPhase::Prelude => (PhaseWrite { phase: &mut self.prelude, other: self.body.length() }, &mut self.first_prelude),
                    OriginalDiagnosticPhase::Body => (PhaseWrite { phase: &mut self.body, other: self.prelude.length() }, &mut self.first_body),
                };
                if self.format==BodyFormat::OrderedArray && !*first { stage.write_all(b",")?; }
                (self.render)(input, row, severity, &mut stage)?;
                *first = false;
                self.emitted=self.emitted.checked_add(1).ok_or_else(||oom("registered checker body count overflow"))?;
                self.clean &= severity > Severity::Info;
            }
            Ok::<(), io::Error>(())
        }).map_err(io::Error::other)??;
        self.rows = self.rows.checked_add(1).ok_or_else(|| oom("checker staged body count overflow"))?;
        Ok(())
    }

    fn seal(mut self, expected: usize) -> io::Result<VerifiedBodyPhases> {
        use std::io::Write as _;
        if self.rows != expected {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "checker body stage lacks completed chunk coverage"));
        }
        if self.format==BodyFormat::OrderedArray{
            PhaseWrite { phase: &mut self.prelude, other: self.body.length() }.write_all(b"]")?;
            PhaseWrite { phase: &mut self.body, other: self.prelude.length() }.write_all(b"]")?;
        }
        fn verified(stage: crate::selected_report_spool::Stage,format:BodyFormat) -> io::Result<crate::selected_report_spool::Verified> {
            let sealed=if format==BodyFormat::RegisteredText{stage.seal_allow_empty()?}else{stage.seal()?};
            let (verified, _) = sealed.validate(|source| io::copy(source, &mut io::sink()))?;
            Ok(verified)
        }
        Ok(VerifiedBodyPhases { prelude: verified(self.prelude,self.format)?, body: verified(self.body,self.format)?, clean: self.clean, bodies: self.rows,counts:self.counts,emitted:self.emitted })
    }
}

pub(super) fn register(db: &Db, ledger: Arc<Mutex<Ledger>>, body_charge: Arc<dm_syntax::SettingChargeCounter>) {
    db.define_input(MODEL, "original-chunk-immutable-model");
    db.define(CHUNK, "original-compact-canonical-body-chunk", move |ctx, raw| {
        let p = raw.downcast_ref::<Params>().expect("Original chunk params");
        pages::typed_publication(&ledger, p.key)?;
        let input = p.input.upgrade().ok_or(QueryError::Missing(p.key))?;
        let source_proof = input.original_source_proof().map_err(|message| QueryError::operational(p.key, io::Error::other(message)))?;
        let transport = |actual| QueryError::operational(p.key, actual);
        let failure = |actual| match actual {
            PolicyFailure::Operational(actual) => transport(actual),
            PolicyFailure::Unsupported(reason) => transport(io::Error::new(io::ErrorKind::Unsupported, reason.0)),
        };
        let model = ctx.input::<Model>(p.model)?;
        let stage = p.stage.as_ref().map(|stage| stage.upgrade().ok_or(QueryError::Missing(p.key))).transpose()?;
        if !model.0.ptr_eq(&p.input) || !input.uses_current_original_bodies() {
            return Err(transport(io::Error::new(io::ErrorKind::InvalidInput, "chunk model issuance differs")));
        }
        let mut work = graph_work::GraphWork::new(Arc::clone(&ledger), p.key);
        let mut builder = match &p.order {
            Some(order) => CompactGraphPageBuilder::in_archived_order(&input, order, &mut work),
            None => CompactGraphPageBuilder::new(&input, p.start, p.count, &mut work),
        }.map_err(failure)?;
        let roster = p.order.as_ref().map_or_else(
            || &input.archive().callables().source_order()[p.start..p.start + p.count],
            ArchivedChunkOrdinals::ordinals,
        );
        if let Some(stage) = &stage {
            let stage = stage.lock().unwrap_or_else(|error| error.into_inner());
            if stage.pending.as_ref().and_then(|pending| stage.start.checked_add(pending.rows)) != Some(p.start) {
                return Err(transport(io::Error::new(io::ErrorKind::InvalidData, "checker stage rank is not consecutive")));
            }
        }
        let mut lookups = Vec::new();
        let context = Mutex::new(ctx);
        let trace = stage.is_some() && trace_compact_checker();
        for (local, &ordinal) in roster.iter().enumerate() {
            let operation = std::cell::Cell::new("prepare_current_body");
            let body_mark = work.mark().map_err(transport)?;
            work.reserve(ExecutionAdmission::fixed_control_charge()).map_err(transport)?;
            let admission = pages::page_execution_admission(&ledger).map_err(|message| transport(io::Error::other(message)))?;
            let obtain = |syntax: &Arc<dm_tree::frontend::BodySyntaxInput>| {
                use dm_tree::frontend::BodySyntaxFailure as F;
                operation.set("admit_syntax_dependency");
                let key = body_syntax::code_key(syntax)?;
                let mut context = context.lock().unwrap_or_else(|error| error.into_inner());
                if !context.has_dependency(key) {
                    pages::reserve_actual_dependency(&ledger, p.key, p.old_edges, context.dependency_count() + 1, &admission, admission.available())
                        .map_err(F::Operational)?;
                }
                operation.set("obtain_kind4_syntax");
                let product = body_syntax::obtain_product(&mut context, syntax)?;
                operation.set("bind_or_evaluate_body");
                Ok(product)
            };
            let before = work.charged_bytes_for_chunk();
            let mut scratch = graph_work::GraphWork::new(Arc::clone(&ledger), p.key);
            let recorder = LookupRecorder {
                input: &input, proof: &source_proof, key: p.key, scratch: Mutex::new(&mut scratch), admission: &admission,
                output: Mutex::new((&mut work, &mut lookups)), error: Mutex::new(None),
            };
            let pending = compute_current_body_using(&input, ordinal, &recorder, &admission, &body_charge, &obtain, Some(&source_proof));
            let trace_failure = |operation| {
                if trace {
                    let source = input.archive().occurrences().get(ordinal).map(|row| &row.source);
                    let _ = io::Write::write_fmt(&mut io::stderr().lock(), format_args!(
                        "checker.body_failed rank={} ordinal={ordinal} window_start={} window_count={} operation={operation} syntax_bytes={} file={} line={}\n",
                        p.start + local, p.start, p.count, body_charge.load(Ordering::Acquire),
                        source.map_or("", |row| row.semantic_path.as_ref()),
                        source.map_or(0, |row| row.line),
                    ));
                }
            };
            if let Some(actual) = recorder.error.into_inner().unwrap_or_else(|error| error.into_inner()) {
                trace_failure("resolve_body_lookup");
                return Err(actual);
            }
            let body = pending.map_err(|actual| {
                trace_failure(operation.get());
                failure(actual)
            })?;
            drop(scratch);
            let body_charge = body.charge();
            work.reserve(body_charge).map_err(transport)?;
            if let Some(stage) = &stage {
                let mut stage = stage.lock().unwrap_or_else(|error| error.into_inner());
                stage.pending.as_mut().ok_or(QueryError::Missing(p.key))?.append(&input, &body, &source_proof).map_err(transport)?;
            }
            builder.push(&body, &mut work).map_err(failure)?;
            drop(body);
            drop(admission);
            let retained = work
                .charged_bytes_for_chunk()
                .checked_sub(before)
                .and_then(|delta| delta.checked_sub(body_charge))
                .ok_or_else(|| transport(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "compact Checker body retired more than its own escrow",
                )))?;
            work.reconcile(body_mark, retained).map_err(transport)?;
        }
        p.edges.store(context.lock().unwrap_or_else(|error| error.into_inner()).dependency_count(), Ordering::Release);
        let page = builder.finish().map_err(failure)?;
        let staged = if let Some(stage) = &stage {
            let mut stage = stage.lock().unwrap_or_else(|error| error.into_inner());
            let rows = stage.pending.as_ref().ok_or(QueryError::Missing(p.key))?.rows;
            if rows == stage.total {
                let pending = stage.pending.take().ok_or(QueryError::Missing(p.key))?;
                stage.ready = Some(pending.seal(stage.total).map_err(transport)?);
            } else if rows > stage.total {
                return Err(transport(io::Error::new(io::ErrorKind::InvalidData, "checker stage exceeds actual ordered coverage")));
            }
            Some(stage.id)
        } else { None };
        work.publish_data::<Chunk>(Data { page, lookups, staged })
    });
}

impl QueryDb {
    #[cfg(test)]
    pub(crate) fn compact_original_chunk_body_key_for_test(input: &EffectInput, ordinal: usize) -> Key {
        body_syntax::code_key(&input.archive().syntax_input_checked(ordinal,&||crate::daemon::control::checkpoint()).unwrap()).unwrap()
    }

    #[cfg(test)]
    pub(crate) fn compact_original_chunk_proof_for_test(
        &self,
        input: &Arc<EffectInput>,
        start: usize,
        count: usize,
    ) -> io::Result<(Key, Key, Vec<(ResolveQuery, bool)>)> {
        let (key, model, result) = self.compact_original_chunk(input, start, count, None, None)?;
        let result = result.as_ref().as_ref().map_err(|message| io::Error::other(message.clone()))?;
        Ok((key, model, result.data.lookups.iter().map(|row| (row.query, row.disposition == Disposition::Missing)).collect()))
    }

    #[cfg(test)]
    pub(crate) fn stage_compact_original_chunk_for_test(
        &self,
        input: &Arc<EffectInput>,
        scope: &crate::runner_host::query_snapshot::PurityScope<'_>,
        start: usize,
        count: usize,
        cache: &Path,
        render: BodyRenderer,
        prelude: &mut impl io::Write,
        body: &mut impl io::Write,
    ) -> io::Result<()> {
        scope.validate(self, input).map_err(io::Error::other)?;
        let id=BodyPhases::next_id()?;
        let mut work=graph_work::GraphWork::new(Arc::clone(&self.purity.ledger),key(CHUNK,input,id as u128));
        work.reserve(ExecutionAdmission::fixed_control_charge().checked_add(std::mem::size_of::<Mutex<BodyStageSlot>>()+2*std::mem::size_of::<usize>()+64).ok_or_else(||oom("registered checker stage control overflow"))?)?;
        let pending=BodyPhases::new_using(input,scope.policy(),cache,render,BodyFormat::OrderedArray,id,&mut work)?;
        let stage = Arc::new(Mutex::new(BodyStageSlot { id, start, total: count, pending: Some(pending), ready: None }));
        let (_, _, result) = self.compact_original_chunk(input, start, count, Some(&stage), None)?;
        let result = result.as_ref().as_ref().map_err(|message| io::Error::other(message.clone()))?;
        if result.data.staged != Some(id) {
            return Err(io::Error::new(io::ErrorKind::InvalidData, "compact chunk omitted its actual body stage"));
        }
        let phases = stage.lock().unwrap_or_else(|error| error.into_inner())
            .ready.take().ok_or_else(|| io::Error::other("checker body stage has no verified phases"))?;
        scope.validate(self, input).map_err(io::Error::other)?;
        phases.prelude.publish(prelude)?;
        phases.body.publish(body)
    }

    #[cfg(test)]
    pub(crate) fn stage_archived_original_body_windows_for_test(
        &self,
        input: &Arc<EffectInput>,
        scope: &crate::runner_host::query_snapshot::PurityScope<'_>,
        width: usize,
        cache: &Path,
        render: BodyRenderer,
        prelude: &mut impl io::Write,
        body: &mut impl io::Write,
    ) -> io::Result<()> {
        let phases = self.with_archived_compact_body_phases(input, scope, width, cache, render,BodyFormat::OrderedArray, |_,_| Ok(()))?;
        phases.prelude.publish(prelude)?;
        phases.body.publish(body)
    }

    pub(crate) fn with_archived_compact_report_completed<'a>(
        &self,input:&'a Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,width:usize,cache:&Path,render:BodyRenderer,
        keyword:impl FnMut(&dm_analysis::checks_keyword_overrides::Findings<'_>)->io::Result<()>,graph_row:impl FnMut(&Produced)->io::Result<()>,
    )->io::Result<(crate::selected_report_spool::Verified,crate::selected_report_spool::Verified,bool,CompletedCompactReport<'a>)>{
        let(a,b,clean,_,_,complete)=self.with_archived_compact_report_completed_using(input,scope,width,cache,render,BodyFormat::OrderedArray,keyword,graph_row)?;Ok((a,b,clean,complete))
    }
    pub(crate) fn with_archived_compact_cli_report_completed<'a>(
        &self,input:&'a Arc<EffectInput>,scope:&crate::runner_host::query_snapshot::PurityScope<'_>,width:usize,cache:&Path,render:BodyRenderer,
        keyword:impl FnMut(&dm_analysis::checks_keyword_overrides::Findings<'_>)->io::Result<()>,graph_row:impl FnMut(&Produced)->io::Result<()>,
    )->io::Result<(crate::selected_report_spool::Verified,crate::selected_report_spool::Verified,crate::runner_host::query_snapshot::DiagnosticCounts,usize,CompletedCompactReport<'a>)>{
        let(a,b,_,counts,emitted,complete)=self.with_archived_compact_report_completed_using(input,scope,width,cache,render,BodyFormat::RegisteredText,keyword,graph_row)?;Ok((a,b,counts,emitted,complete))
    }
    fn with_archived_compact_report_completed_using<'a>(
        &self,
        input: &'a Arc<EffectInput>,
        scope: &crate::runner_host::query_snapshot::PurityScope<'_>,
        width: usize,
        cache: &Path,
        render: BodyRenderer,
        format:BodyFormat,
        mut keyword: impl FnMut(&dm_analysis::checks_keyword_overrides::Findings<'_>) -> io::Result<()>,
        mut graph_row: impl FnMut(&Produced) -> io::Result<()>,
    ) -> io::Result<(crate::selected_report_spool::Verified, crate::selected_report_spool::Verified, bool,crate::runner_host::query_snapshot::DiagnosticCounts,usize, CompletedCompactReport<'a>)> {
        use dm_analysis::checker_effects::{CompactEffectGraph, CompactEffectScc, CompactGraphReplay, EffectReportPhase, EffectSource, ProducedPhase};
        let mut graph_visits=[0usize;2];
        let mut graph_targets=None;
        let phases = self.with_archived_compact_body_phases(input, scope, width, cache, render,format, |chunks, work| {
            let _gate = self.purity.gate.lock().unwrap_or_else(|error| error.into_inner());
            let validate = || scope.validate(self, input).map_err(io::Error::other);
            validate()?;
            // The snapshot, input and replay loan are fixed for this operation.
            // Poll cancellation inside their algorithms; check frame authority
            // at phase boundaries and again before releasing the result.
            let checkpoint = crate::daemon::control::checkpoint;
            let transport = |failure| match failure {
                PolicyFailure::Operational(actual) => actual,
                PolicyFailure::Unsupported(reason) => io::Error::other(reason.0),
            };
            let trace = trace_compact_checker().then(std::time::Instant::now);
            let ledger = &self.purity.ledger;
            let source = EffectSource::new(input.archive(), input.profile()).map_err(transport)?;
            let resolver = input.archive().tree();
            let pages = reserve_refs(chunks.len(), work, |index| &chunks[index].data.page)?;
            let replay = CompactGraphReplay::new(input, &pages, work, &checkpoint).map_err(transport)?;
            {
                let mut phase_work = graph_work::GraphWork::new(Arc::clone(ledger), key(CHUNK,input,1));
                phase_work.reserve(ExecutionAdmission::fixed_control_charge())?;
                let admission = pages::page_execution_admission(ledger).map_err(oom_string)?;
                dm_analysis::checks_keyword_overrides::with_compact_body_uses(
                    input, resolver, &admission, &mut phase_work, &checkpoint,
                    |ordinal| replay.body(ordinal),
                    |rows| keyword(rows).map_err(PolicyFailure::Operational),
                ).map_err(transport)?;
            }
            if let Some(started) = trace {
                let _ = io::Write::write_fmt(&mut io::stderr().lock(), format_args!("checker.keywords_done bodies={} elapsed_ms={}\n", source.len(), started.elapsed().as_millis()));
            }
            validate()?;
            let graph_mark = work.mark()?;
            work.reserve(ExecutionAdmission::fixed_control_charge())?;
            let admission = pages::page_execution_admission(ledger).map_err(oom_string)?;
            let graph = CompactEffectGraph::build_replay_reserved_checked(
                &source, width, &replay, resolver, &admission, &mut || checkpoint(), &mut |bytes| work.reserve(bytes),
            ).map_err(transport)?.into_retained_checked(&mut || checkpoint(), &mut |bytes| work.reserve(bytes)).map_err(transport)?;
            drop(admission);
            work.reconcile(graph_mark, graph.retained_charge().ok_or_else(|| oom("compact graph retained capacity overflow"))?)?;
            let current = graph.current(&source).map_err(transport)?;
            let summary_mark = work.mark()?;
            work.reserve(ExecutionAdmission::fixed_control_charge())?;
            let admission = pages::page_execution_admission(ledger).map_err(oom_string)?;
            let scc_bound = CompactEffectScc::work_charge(current.len()).and_then(|n| {
                CompactEffectScc::summary_work_charge_bound(current.len()).and_then(|m| n.checked_add(m))
            }).ok_or_else(|| oom("compact summary work overflow"))?;
            work.reserve(scc_bound)?;
            let scc = CompactEffectScc::compute_checked(current.len(), &admission,
                |node,next,_| current.successor(node,next), &mut || checkpoint()).map_err(transport)?;
            let summary = scc.into_summary_checked(&admission,
                |node,_| current.direct_effect(node).ok_or_else(|| "compact graph seed absent".into()),
                |node,next,_| current.successor(node,next), &mut || checkpoint()).map_err(transport)?;
            drop(admission);
            work.reconcile(summary_mark, summary.retained_charge().ok_or_else(|| oom("compact summary retained capacity overflow"))?)?;
            validate()?;
            let order_mark = work.mark()?;
            work.reserve(ExecutionAdmission::fixed_control_charge())?;
            let admission = pages::page_execution_admission(ledger).map_err(oom_string)?;
            let order = source.report_order_checked(&graph, &admission, &mut || checkpoint(), work)
                .map_err(transport)?;
            drop(admission);
            work.reconcile(order_mark, order.retained_charge().ok_or_else(|| oom("compact report order retention overflow"))?)?;
            graph_targets=Some(source.len());
            for (phase_index,(phase, wanted)) in [(EffectReportPhase::Sleep, ProducedPhase::SleepGraph),
                                    (EffectReportPhase::Purity, ProducedPhase::PurityGraph)].into_iter().enumerate() {
                validate()?;
                for start in (0..source.len()).step_by(256) {
                    let mut phase_work = graph_work::GraphWork::new(Arc::clone(ledger), key(CHUNK,input,2));
                    phase_work.reserve(ExecutionAdmission::fixed_control_charge())?;
                    let admission = pages::page_execution_admission(ledger).map_err(oom_string)?;
                    let rows = source.report_replay_window_using_order_checked(
                        &order, &summary, start, 256.min(source.len()-start), phase, resolver, scope.policy(),
                        &admission, &mut || checkpoint(), &replay, &mut phase_work,
                    ).map_err(transport)?;
                    for row in rows.iter().filter(|row| row.phase() == wanted) { graph_row(row)?; }
                    graph_visits[phase_index]=graph_visits[phase_index].checked_add(256.min(source.len()-start))
                        .ok_or_else(||oom("compact completed graph count overflow"))?;
                }
            }
            validate()?;
            if let Some(started) = trace {
                let _ = io::Write::write_fmt(&mut io::stderr().lock(), format_args!("checker.graph_done nodes={} replay_elapsed_ms={}\n", current.len(), started.elapsed().as_millis()));
            }
            Ok(())
        })?;
        let completion=CompletedCompactReport{input:input.as_ref(),bodies:phases.bodies,
            graph_visits,graph_targets:graph_targets.ok_or_else(||io::Error::other("compact graph traversal did not complete"))?};
        completion.body_count_for(input.as_ref())?;
        Ok((phases.prelude, phases.body, phases.clean,phases.counts,phases.emitted,completion))
    }

    fn with_archived_compact_body_phases(
        &self,
        input: &Arc<EffectInput>,
        scope: &crate::runner_host::query_snapshot::PurityScope<'_>,
        width: usize,
        cache: &Path,
        render: BodyRenderer,
        format:BodyFormat,
        replay: impl FnOnce(&[Arc<Chunk>], &mut graph_work::GraphWork)->io::Result<()>,
    ) -> io::Result<VerifiedBodyPhases> {
        scope.validate(self, input).map_err(io::Error::other)?;
        if width == 0 || width > WIDTH { return Err(io::ErrorKind::InvalidInput.into()); }
        let id = BodyPhases::next_id()?;
        let total = input.archive().len();
        let mut work = graph_work::GraphWork::new(Arc::clone(&self.purity.ledger), key(CHUNK, input, id as u128));
        work.reserve(ExecutionAdmission::fixed_control_charge().checked_add(std::mem::size_of::<Mutex<BodyStageSlot>>()+2*std::mem::size_of::<usize>()+64).ok_or_else(||oom("registered checker stage control overflow"))?)?;
        let pending = BodyPhases::new_using(input, scope.policy(), cache, render,format,id,&mut work)?;
        let stage = Arc::new(Mutex::new(BodyStageSlot { id, start: 0, total, pending: Some(pending), ready: None }));
        let validate = || scope.validate(self, input).map_err(io::Error::other);
        let admission = pages::page_execution_admission(&self.purity.ledger).map_err(oom_string)?;
        let mut chunks = reserve_chunk_list(total.div_ceil(width), &mut work)?;
        let trace = trace_compact_checker().then(std::time::Instant::now);
        let progress_stride = total.div_ceil(4).max(1);
        let mut next_progress = progress_stride;
        let staged = dm_analysis::checker_order::with_archived_order_using(
            input.archive(), &admission, &mut work, &crate::daemon::control::checkpoint,
            |order, _| {
                if order.len() != total { return Err("checker archived order has different body coverage".into()); }
                if let Some(started) = trace {
                    let _ = io::Write::write_fmt(&mut io::stderr().lock(), format_args!("checker.body_windows completed=0 total={total} windows=0 elapsed_ms={}\n", started.elapsed().as_millis()));
                }
                for start in (0..total).step_by(width) {
                    crate::daemon::control::checkpoint().map_err(PolicyFailure::Operational)?;
                    let count = width.min(total - start);
                    let roster = order.chunk(start, count)?;
                    let (_, _, result) = self.compact_original_chunk(input, start, count, Some(&stage), Some(roster))
                        .map_err(PolicyFailure::Operational)?;
                    let result = result.as_ref().as_ref().map_err(|message| PolicyFailure::from(message.clone()))?;
                    if result.data.staged != Some(id) {
                        return Err("checker window omitted its actual private stage".into());
                    }
                    chunks.push(Arc::clone(result));
                    if let Some(started) = trace {
                        let completed = start + count;
                        if completed >= next_progress || completed == total {
                            let _ = io::Write::write_fmt(&mut io::stderr().lock(), format_args!(
                                "checker.body_windows completed={completed} total={total} windows={} syntax_bytes={} elapsed_ms={}\n",
                                chunks.len(), self.body_charge.load(Ordering::Acquire), started.elapsed().as_millis(),
                            ));
                            while next_progress <= completed && next_progress < total {
                                next_progress = next_progress.saturating_add(progress_stride);
                            }
                        }
                    }
                }
                Ok(())
            },
        );
        staged.map_err(|failure| match failure {
            PolicyFailure::Operational(actual) => actual,
            PolicyFailure::Unsupported(reason) => io::Error::other(reason.0),
        })?;
        drop(admission);
        let phases = {
            let mut stage = stage.lock().unwrap_or_else(|error| error.into_inner());
            if total == 0 {
                stage.pending.take().ok_or_else(|| io::Error::other("empty checker stage unavailable"))?.seal(0)?
            } else {
                stage.ready.take().ok_or_else(|| io::Error::other("checker stage has no verified full coverage"))?
            }
        };
        validate()?;
        replay(&chunks, &mut work)?;
        validate()?;
        Ok(phases)
    }

    fn compact_original_chunk(
        &self,
        input: &Arc<EffectInput>,
        start: usize,
        count: usize,
        stage: Option<&Arc<Mutex<BodyStageSlot>>>,
        order: Option<ArchivedChunkOrdinals>,
    ) -> io::Result<(Key, Key, Arc<Result<Arc<Chunk>, String>>)> {
        crate::daemon::control::checkpoint()?;
        input.require_original_checker_source().map_err(io::Error::other)?;
        input.validate_current(input.archive(), self).map_err(io::Error::other)?;
        if count == 0 || count > WIDTH || start.checked_add(count).is_none_or(|end| end > input.archive().callables().source_order().len()) {
            return Err(io::ErrorKind::InvalidInput.into());
        }
        self.prune_purity();
        let _gate = self.purity.gate.lock().unwrap_or_else(|error| error.into_inner());
        let ledger = &self.purity.ledger;
        {
            let mut state = ledger.lock().unwrap_or_else(|error| error.into_inner());
            state.denied = false;
            state.aborted = None;
        }
        let model = key(MODEL, input, 0);
        let _model = node_admission(ledger, input, model, std::mem::size_of::<Model>()).map_err(oom_string)?;
        self.db.set_input(model, Model(Arc::downgrade(input)), input.key() as u128);
        let stage_id = stage.map_or(0, |stage| stage.lock().unwrap_or_else(|error| error.into_inner()).id);
        let start_key = u32::try_from(start).map_err(|_| oom("compact body chunk start exceeds key range"))?;
        let key = key(CHUNK, input, ((stage_id as u128) << 64) | ((start_key as u128) << 32) | count as u128);
        let _chunk = node_admission(ledger, input, key, std::mem::size_of::<Params>()).map_err(oom_string)?;
        let mut dependencies = pages::reserve_dependencies(ledger, key, count).map_err(oom_string)?;
        let params = Arc::new(Params {
            input: Arc::downgrade(input), model, key, start, count, old_edges: dependencies.old,
            edges: std::sync::atomic::AtomicUsize::new(0),
            stage: stage.map(Arc::downgrade),
            order,
        });
        remember_params(ledger, input, key, &params);
        let result = self.db.get::<Result<Arc<Chunk>, String>>(key, params.clone())
            .map_err(|error| pages::restore_graph_error(ledger, error))?;
        dependencies.commit(params.edges.load(Ordering::Acquire));
        input.validate_current(input.archive(), self).map_err(io::Error::other)?;
        {
            let actual = result.as_ref().as_ref().map_err(|message| io::Error::other(message.clone()))?;
            let _actual_page = actual.data.page.loan(input).map_err(io::Error::other)?;
        }
        Ok((key, model, result))
    }
}

fn oom_string(message: String) -> io::Error { io::Error::new(io::ErrorKind::OutOfMemory, message) }
fn reserve_refs<'a,T>(count:usize,work:&mut graph_work::GraphWork,mut obtain:impl FnMut(usize)->&'a T)->io::Result<Vec<&'a T>> {
    let mut rows = reserve_chunk_list(count,work)?;
    rows.extend((0..count).map(|index| obtain(index)));
    Ok(rows)
}
fn reserve_chunk_list<T>(count:usize,work:&mut graph_work::GraphWork)->io::Result<Vec<T>> {
    let capacity=count.checked_mul(4).ok_or_else(||oom("compact window list capacity overflow"))?;
    let bytes=capacity.checked_mul(std::mem::size_of::<T>()).ok_or_else(||oom("compact window list byte overflow"))?;
    let mark=work.mark()?;
    work.reserve(bytes)?;
    let mut rows=Vec::new();
    rows.try_reserve_exact(count).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;
    if rows.capacity()>capacity { return Err(oom("compact window list exposed excess capacity")); }
    work.reconcile(mark,rows.capacity()*std::mem::size_of::<T>())?;
    Ok(rows)
}

#[cfg(test)]mod funded_policy_controls{
 use super::*;
 #[test]fn actual_body_policy_copy_reserves_before_owned_keys_and_same_ledger_recovers(){
  let mut policy=CheckerPolicy::default();policy.diagnostics.insert("unknown_linter_setting".into(),dm_analysis::check_policy::WarningLevel::Hint);policy.diagnostics.insert("case_sensitive_é".into(),dm_analysis::check_policy::WarningLevel::Disabled);
  let ledger=Arc::new(Mutex::new(Ledger::default()));let mut denied=graph_work::GraphWork::new(ledger.clone(),Key::new(CHUNK,1));
  let base=ledger.lock().unwrap().metadata();denied.reserve(BUDGET-base-NODE_BOUND/2).unwrap();let held=ledger.lock().unwrap().active_graph_work;
  assert_eq!(funded_body_policy(&policy,&mut denied).unwrap_err().kind(),io::ErrorKind::OutOfMemory);assert_eq!(ledger.lock().unwrap().active_graph_work,held);assert_eq!(policy.diagnostics.len(),2);drop(denied);assert_eq!(ledger.lock().unwrap().active_graph_work,0);
  let fresh=Arc::new(Mutex::new(Ledger::default()));let mut work=graph_work::GraphWork::new(fresh.clone(),Key::new(CHUNK,2));let actual=funded_body_policy(&policy,&mut work).unwrap();assert_eq!(actual,policy);assert!(fresh.lock().unwrap().active_graph_work>=2*NODE_BOUND);drop(actual);drop(work);assert_eq!(fresh.lock().unwrap().active_graph_work,0);
 }
}
