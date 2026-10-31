//! Native source purity over the ORIGINAL archive/semantic IDs.
//! Pinned source: SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc.
//! Contributions/SCCs are unique checker work, never another Type/Proc model.
//! All unsupported syntax, source, dispatch or effect contexts refuse atomically.
use crate::{
    check_policy::{CheckerPolicy, DiagnosticSeverity},
    checks::{Diagnostic, Note, Severity},
};
use dm_ir::{
    PackedU128, ProcedureIdentity, ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId,
};
use dm_syntax::Span;
use dm_tree::{
    frontend::{BodyArchive, BodySyntaxQueries, SourceNoteOrigin},
    MemberKind,
};
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Weak,
    },
};
pub const MAX_EVENTS: usize = 10_000;
pub const RESULT_BUDGET: usize = 64 * 1024 * 1024;
/// External parity contract of the pinned checker call-tree diagnostics.
/// Directive HashMap iteration makes COMPLETE target-group permutations
/// unspecified. Native reports choose authored target order. Within each group,
/// every row, BFS first-encounter choice, source point, note and suppression is
/// order-significant. Oracle comparison may permute ONLY whole target groups;
/// it must never flatten/sort rows or notes. A combined checker renderer keeps
/// original phase order: body-time diagnostics, must_not_sleep, must_be_pure.
/// There is currently no public native effect-report writer; a future writer
/// must expose this contract rather than claim exact sampled transcript order.
pub const TARGET_GROUP_ORDER_CONTRACT: &str =
    "unspecified_whole_target_group_permutation;native_authored_order;exact_within_target_order";
pub const EFFECT_PHASE_ORDER: [&str; 3] = ["body_immediate", "must_not_sleep", "must_be_pure"];

#[path = "checker_effects_output.rs"]
pub(crate) mod output;
pub use output::ExecutionAdmission;
use output::ReportBudget;
#[derive(Clone, Debug)]
pub(crate) struct DirectEffect {
    pub origin: CallOrigin,
    pub reason: &'static str,
}
#[derive(Clone, Copy, Debug)]
pub(crate) enum CallOrigin {
    Source(Span),
    ImplicitList(dm_syntax::ImplicitListOrigin),
}
#[derive(Clone, Debug)]
pub(crate) struct CallEdge {
    pub callee: EffectTarget,
    pub origin: CallOrigin,
    pub exact: bool,
    pub new_context: bool,
}
#[derive(Default)]
pub(crate) struct Draft {
    pub direct: Vec<DirectEffect>,
    pub calls: Vec<CallEdge>,
    pub immediate: Vec<Diagnostic>,
    pub blocking: Vec<DirectEffect>,
    pub waitfor_disabled: bool,
    pub transient: ReportBudget,
}
/// Factory-issued source context. Params/results keep this weak, not a graph
/// clone. A caller must present this same current archive/Db BEFORE cache hits.
pub struct EffectInput {
    key: u64,
    archive: Arc<BodyArchive>,
    profile: PackedU128,
    order: Box<[(usize, ProcedureIdentity)]>,
    whole_roster: bool,
}
impl EffectInput {
    /// Source-query coordination only; the bounded whole-plan constructor and
    /// policy remain unchanged. Actual page/body work is admitted on demand.
    pub fn source_pages(archive:Arc<BodyArchive>,profile:PackedU128)->Result<Arc<Self>,String>{
        EffectSource::new(&archive,profile).map_err(|failure|failure.to_string())?;
        Ok(Arc::new(Self{key:next_input_key()?,archive,profile,order:Box::new([]),whole_roster:false}))
    }
    pub fn is_source_page_context(&self)->bool{!self.whole_roster&&self.order.is_empty()}
    pub fn new(archive: Arc<BodyArchive>, profile: PackedU128) -> Result<Arc<Self>, String> {
        archive
            .tree()
            .validate_checker_builtin_profile(profile)
            .map_err(|e| format!("purity builtin profile: {e:?}"))?;
        if archive.syntax_inputs().is_none() || archive.body_query_host().is_none() {
            return Err("purity requires original compiler body-query graph".into());
        }
        if archive.len() > MAX_EVENTS {
            return Err("purity original callable roster exceeds bounded admission".into());
        }
        let order = crate::checker_order::archived_bodies(&archive)?
            .into_iter()
            .map(|(i, _)| Ok((i, identity(&archive, i)?)))
            .collect::<Result<Vec<_>, String>>()?;
        let key = next_input_key()?;
        Ok(Arc::new(Self {
            key,
            archive,
            profile,
            order: order.into(),
            whole_roster: true,
        }))
    }
    pub fn key(&self) -> u64 {
        self.key
    }
    pub fn archive(&self) -> &Arc<BodyArchive> {
        &self.archive
    }
    pub fn profile(&self) -> PackedU128 {
        self.profile
    }
    pub fn order(&self) -> &[(usize, ProcedureIdentity)] {
        &self.order
    }
    pub fn ordinal_for(&self, procedure: ProcedureIdentity) -> Option<usize> {
        self.order
            .iter()
            .find_map(|&(i, p)| (p == procedure).then_some(i))
    }
    pub fn validate_current(
        &self,
        current: &Arc<BodyArchive>,
        host: &dyn BodySyntaxQueries,
    ) -> Result<(), String> {
        if !Arc::ptr_eq(&self.archive, current) || !current.uses_body_queries(host) {
            return Err("purity input is not the current original archive/Db".into());
        }
        self.archive
            .tree()
            .validate_checker_builtin_profile(self.profile)
            .map_err(|e| format!("purity profile changed: {e:?}"))?;
        Ok(())
    }
    pub fn compute_body(
        self: &Arc<Self>,
        ordinal: usize,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
    ) -> Result<Arc<BodyEffects>, String> {
        self.compute_body_with::<crate::policy_body_demand::Compatibility>(
            ordinal, resolver, admission,
        )
        .map_err(|e| e.0)
    }
    pub fn compute_body_checked(
        self: &Arc<Self>,
        ordinal: usize,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
    ) -> Result<Arc<BodyEffects>, crate::policy_body_demand::PolicyFailure> {
        let host=self.archive.body_query_host().ok_or("effect checked body requires original body-query host")?;
        self.compute_body_checked_using(ordinal,resolver,admission,&|input|host.syntax_checked(input))
    }
    fn compute_body_with<D: crate::policy_body_demand::Demand>(
        self: &Arc<Self>,
        ordinal: usize,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
    ) -> Result<Arc<BodyEffects>, D::Error> {
        self.compute_body_using(ordinal,resolver,admission,D::parse,crate::checker_prefix_demand::Compatibility::<D::Error>::new())
    }
    /// Direct original-graph body loan. The archive authenticates the returned
    /// syntax after this callback, just as its ordinary checked parse does.
    pub fn compute_body_checked_using(
        self:&Arc<Self>,ordinal:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>,
    )->Result<Arc<BodyEffects>,crate::policy_body_demand::PolicyFailure>{self.compute_body_checked_using_admitted(ordinal,resolver,admission,&|input,_|body(input))}
pub fn compute_body_checked_using_admitted(
        self:&Arc<Self>,ordinal:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>,
    )->Result<Arc<BodyEffects>,crate::policy_body_demand::PolicyFailure>{
        let profile=self.archive.tree().validated_checker_profile(self.profile).map_err(|e|crate::policy_body_demand::PolicyFailure::from(format!("purity settings profile unavailable: {e:?}")))?;
        self.compute_body_using(ordinal,resolver,admission,|archive,ordinal|archive.parse_checked_using(ordinal,&|input:&std::sync::Arc<dm_tree::frontend::BodySyntaxInput>|body(input,&admission.current_view())).map_err(|failure|match failure{
            dm_tree::frontend::BodySyntaxFailure::Syntax(source)=>crate::policy_body_demand::PolicyFailure::from(source.message),
            dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>crate::policy_body_demand::PolicyFailure::Operational(actual),
        }),crate::checker_prefix_demand::Checked{body,admission,profile})
    }
    fn compute_body_using<'a,E:From<String>+for<'b>From<&'b str>,D:crate::checker_prefix_demand::Demand<Error=E>>(
        self:&'a Arc<Self>,ordinal:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        parse:impl FnOnce(&'a BodyArchive,usize)->Result<dm_tree::frontend::ArchivedBody<'a>,E>,
        prefix_demand:D,
    )->Result<Arc<BodyEffects>,E>{
        let procedure = identity(&self.archive, ordinal)?;
        if !self
            .order
            .iter()
            .any(|&(i, p)| i == ordinal && p == procedure)
        {
            return Err("purity body has no issued procedure occurrence".into());
        }
        if resolver.source_owner() != Resolver::source_owner(self.archive.tree()) {
            return Err("purity resolver is not the original graph".into());
        }
        let settings = crate::checker_return_facts::PuritySettingsPermit::issue_using(
            &self.archive,
            self.profile,
            procedure, &&prefix_demand)?;
        let pure = settings.own_pure();
        let body = parse(&self.archive, ordinal)?;
        let draft = crate::checker_expression_visit::effects_archived_using(
            &self.archive,
            &body,
            resolver,
            self.profile,
            admission, &prefix_demand)?;
        if draft
            .direct
            .len()
            .checked_add(draft.calls.len())
            .and_then(|n| n.checked_add(draft.blocking.len()))
            .and_then(|n| n.checked_add(draft.immediate.len()))
            .is_none_or(|n| n > MAX_EVENTS)
        {
            ReportBudget::for_operation(admission).deny();
            return Err(prefix_demand.resource("purity body exceeds bounded event admission"));
        }
        // Reuse the actual already-obtained primary body. The stored optional
        // point/result preserves deferred report-source refusal without adding
        // an earlier body demand or a full roster search for each target.
        let opening_parenthesis=body.signature_opening_parenthesis();
        let original_note=self.archive.callable_note_origin_borrowed_from_parsed(procedure,ordinal,&body);
        let origin_charge=match &original_note{Ok(point)=>point.retained_charge(),Err(_)=>Some(0)}.and_then(|n|n.checked_add(std::mem::size_of::<Option<Span>>()+std::mem::size_of::<Result<SourceNoteOrigin,dm_tree::frontend::BorrowedCallableOriginError>>())).ok_or_else(||prefix_demand.resource("effect original note capacity overflow"))?;
        // Borrowed lookup above allocates/clones nothing, including failures.
        // Admit the actual path backing BEFORE extending its Arc lifetime.
        draft.transient.charge(origin_charge).map_err(|_|prefix_demand.resource("effect original note admission exhausted"))?;
        let callable_origin=original_note.map(dm_tree::frontend::BorrowedSourceNoteOrigin::into_owned);
        let parent = source_parent(
            &self.archive,
            resolver,
            self.profile,
            self.archive
                .occurrences()
                .get(ordinal)
                .ok_or("effect ordinal absent")?
                .member,
            procedure,
        )?;
        Ok(Arc::new(BodyEffects {
            input: Arc::downgrade(self),
            ordinal,
            procedure,
            pure,
            sleep: SleepSettings {
                no_sleep: settings.own_no_sleep(),
                exempt: settings.own_sleep_exempt(),
                waitfor_disabled: draft.waitfor_disabled,
            },
            blocking: draft.blocking.into(),
            parent,
            direct: draft.direct.into(),
            calls: draft.calls.into(),
            immediate: draft.immediate.into(),
            opening_parenthesis,
            callable_origin,
        }))
    }
    pub fn plan(
        self: &Arc<Self>,
        bodies: Vec<Arc<BodyEffects>>,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
    ) -> Result<Arc<EffectPlan>, String> {
        if !self.whole_roster{return Err("effect contribution windows require the global source graph; independent page SCC is forbidden".into())}
        if resolver.source_owner() != Resolver::source_owner(self.archive.tree()) {
            return Err("effect plan resolver foreign".into());
        }
        if bodies.len() != self.order.len() {
            return Err("purity plan omits an original callable".into());
        }
        let events = bodies
            .iter()
            .try_fold(0usize, |n, b| {
                n.checked_add(b.direct.len())
                    .and_then(|n| n.checked_add(b.calls.len()))
                    .and_then(|n| n.checked_add(b.blocking.len()))
                    .and_then(|n| n.checked_add(b.immediate.len()))
            })
            .ok_or("purity graph event admission overflow")?;
        if events > MAX_EVENTS {
            return Err("purity graph exceeds bounded event admission".into());
        }
        output::plan_admission(self, &bodies, admission)?;
        let mut index = BTreeMap::new();
        for (i, (body, &(ordinal, procedure))) in bodies.iter().zip(self.order.iter()).enumerate() {
            body.validate(self)?;
            if body.ordinal != ordinal
                || body.procedure != procedure
                || index.insert(procedure, i).is_some()
            {
                return Err("purity plan order/identity mismatch".into());
            }
        }
        let mut adjacency = vec![Vec::new(); bodies.len()];
        for (i, body) in bodies.iter().enumerate() {
            for call in body.calls.iter() {
                if let EffectTarget::Source(callee) = call.callee {
                    adjacency[i].push(
                        *index
                            .get(&callee)
                            .ok_or("effect call has no original source contribution")?,
                    );
                }
            }
        }
        let mut overrides = vec![Vec::new(); bodies.len()];
        for (child, body) in bodies.iter().enumerate() {
            if body.direct.is_empty() || body.procedure.name == SymbolId::of("New") {
                continue;
            }
            let mut parent = body.parent;
            let mut seen = BTreeSet::new();
            while let Some(p) = parent {
                if !seen.insert(p) {
                    return Err("purity original predecessor cycle".into());
                }
                if let EffectTarget::Source(id) = p {
                    let at = *index
                        .get(&id)
                        .ok_or("purity predecessor has no source contribution")?;
                    overrides[at].push(child);
                }
                parent = target_parent_parts(self, resolver, p, &bodies, &index)?;
            }
        }
        let mut graph = adjacency.clone();
        for (i, children) in overrides.iter().enumerate() {
            graph[i].extend(children.iter().copied())
        }
        let components = scc(&graph)?;
        let plan = EffectPlan {
            input: Arc::downgrade(self),
            bodies: bodies.into(),
            index,
            adjacency,
            overrides,
            components,
        };
        if plan.charge() > RESULT_BUDGET {
            return Err("purity plan exceeds bounded result admission".into());
        }
        Ok(Arc::new(plan))
    }
}
impl std::fmt::Debug for EffectInput {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("EffectInput")
            .field("key", &self.key)
            .field("bodies", &self.order.len())
            .finish()
    }
}
pub struct BodyEffects {
    input: Weak<EffectInput>,
    ordinal: usize,
    procedure: ProcedureIdentity,
    pure: Option<Span>,
    sleep: SleepSettings,
    blocking: Box<[DirectEffect]>,
    parent: Option<EffectTarget>,
    direct: Box<[DirectEffect]>,
    calls: Box<[CallEdge]>,
    immediate: Box<[Diagnostic]>,
    opening_parenthesis:Option<Span>,
    callable_origin:Result<SourceNoteOrigin,dm_tree::frontend::BorrowedCallableOriginError>,
}
impl BodyEffects {
    fn validate(&self, input: &Arc<EffectInput>) -> Result<(), String> {
        if !self.input.ptr_eq(&Arc::downgrade(input)) {
            return Err("purity body belongs to another source issuance".into());
        }
        Ok(())
    }
    pub fn charge(&self) -> usize {
        storage::body_capacity_bound(self)
    }
}
/// A DAG plan over source-owned procedure IDs. Callee EFFECT contributions are
/// never requested while a contribution computes; original callee prefix syntax
/// is obtained through the same checked loan. Recursive effects cannot create
/// recursive dm_query calls or wait cycles.
pub struct EffectPlan {
    input: Weak<EffectInput>,
    bodies: Box<[Arc<BodyEffects>]>,
    index: BTreeMap<ProcedureIdentity, usize>,
    adjacency: Vec<Vec<usize>>,
    overrides: Vec<Vec<usize>>,
    components: Vec<usize>,
}
impl EffectPlan {
    pub fn validate(&self, input: &Arc<EffectInput>) -> Result<(), String> {
        if !self.input.ptr_eq(&Arc::downgrade(input)) {
            return Err("purity plan belongs to another original input".into());
        }
        Ok(())
    }
    pub fn charge(&self) -> usize {
        storage::plan_capacity_bound(self)
    }
    pub fn summarize(
        self: &Arc<Self>,
        input: &Arc<EffectInput>,
    ) -> Result<Arc<SccSummary>, String> {
        self.validate(input)?;
        let count = self.components.iter().copied().max().map_or(0, |c| c + 1);
        let mut effect = vec![false; count];
        let mut dag = vec![BTreeSet::new(); count];
        for (i, b) in self.bodies.iter().enumerate() {
            let c = self.components[i];
            effect[c] |= !b.direct.is_empty()
                || b.calls
                    .iter()
                    .any(|e| matches!(e.callee, EffectTarget::Builtin(_)));
            for &to in self.adjacency[i].iter().chain(self.overrides[i].iter()) {
                let d = self.components[to];
                if c != d {
                    dag[c].insert(d);
                }
            }
        }
        // Explicit SCC job, not recursive Db queries: one reverse-topological pass.
        let mut pending = dag.iter().map(BTreeSet::len).collect::<Vec<_>>();
        let mut parents = vec![Vec::new(); count];
        for (c, children) in dag.iter().enumerate() {
            for &d in children {
                parents[d].push(c)
            }
        }
        let mut ready = (0..count)
            .filter(|&c| pending[c] == 0)
            .collect::<VecDeque<_>>();
        let mut completed = 0;
        while let Some(c) = ready.pop_front() {
            completed += 1;
            for &p in &parents[c] {
                effect[p] |= effect[c];
                pending[p] -= 1;
                if pending[p] == 0 {
                    ready.push_back(p)
                }
            }
        }
        if completed != count {
            return Err("purity SCC condensation is cyclic".into());
        }
        Ok(Arc::new(SccSummary {
            input: Arc::downgrade(input),
            plan: Arc::clone(self),
            has_effect: effect.into(),
        }))
    }
}
pub struct SccSummary {
    input: Weak<EffectInput>,
    plan: Arc<EffectPlan>,
    has_effect: Box<[bool]>,
}
impl SccSummary {
    /// Scalar observation of this existing original summary; not source authority.
    pub fn source_has_effect(&self,procedure:ProcedureIdentity)->Option<bool>{let row=*self.plan.index.get(&procedure)?;self.has_effect.get(*self.plan.components.get(row)?).copied()}
    pub fn validate(&self, input: &Arc<EffectInput>) -> Result<(), String> {
        if !self.input.ptr_eq(&Arc::downgrade(input)) {
            return Err("purity SCC belongs to another current source input".into());
        }
        self.plan.validate(input)
    }
    pub fn charge(&self) -> usize {
        storage::summary_capacity_bound(self)
    }
    pub fn report(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, String> {
        self.report_with::<crate::policy_body_demand::Compatibility>(
            input, resolver, policy, admission, checkpoint,
        )
        .map_err(|e| e.0)
    }
    pub fn report_checked(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, crate::policy_body_demand::PolicyFailure> {
        self.report_with::<crate::policy_body_demand::Checked>(
            input, resolver, policy, admission, checkpoint,
        )
    }
    fn report_with<D: crate::policy_body_demand::Demand>(
        &self,
        input: &Arc<EffectInput>,
        resolver: &(impl Resolver + ?Sized),
        policy: &CheckerPolicy,
        admission: &ExecutionAdmission,
        mut checkpoint: impl FnMut() -> Result<(), String>,
    ) -> Result<Vec<Produced>, D::Error> {
 self.validate(input)?;report_core::purity(&report_core::LegacyReportAccess::<D>{input,plan:&self.plan,summary:Some(self),demand:std::marker::PhantomData},resolver,policy,admission,||checkpoint().map_err(D::Error::from))
}
}
#[derive(Clone, Debug)]
pub struct Produced {
    pub registration_tag: Option<&'static str>,
    pub severity: DiagnosticSeverity,
    pub diagnostic: Diagnostic,
    pub origin: SourceNoteOrigin,
}
fn diagnostic(at: Span, message: String, notes: Vec<Note>) -> Diagnostic {
    Diagnostic {
        family: "must_be_pure",
        severity: Severity::Error,
        span: at,
        expression_span: at,
        message,
        notes,
    }
}
fn emit<E:From<String>+From<&'static str>>(
    out: &mut Vec<Produced>,
    _input: &report_core::ReportSource<'_>,
    tag: Option<&'static str>,
    diagnostic: Diagnostic,
    origin: SourceNoteOrigin,
    policy: &CheckerPolicy,
    budget: &output::ReportBudgetWith<'_,E>,
) -> Result<(), E> {
    let default = match diagnostic.severity {
        Severity::Error => DiagnosticSeverity::Error,
        Severity::Warning => DiagnosticSeverity::Warning,
        Severity::Disabled => return Err("disabled native effect diagnostic escaped".into()),
    };
    if let Some(severity) = policy.register(tag, default) {
        if out.len() >= MAX_EVENTS {
            return Err("purity report exceeds existing finding admission".into());
        }
        let produced=Produced {
                registration_tag: tag,
                severity,
                diagnostic,
                origin,
            };budget.record_output(&produced)?;budget.push(out,produced)?
    }
    Ok(())
}
impl CallOrigin {
    pub(crate) fn source_span(self) -> Result<Span, String> {
        match self {
            Self::Source(at) => Ok(at),
            Self::ImplicitList(_) => {
                Err("synthetic list initializer has no written source span".into())
            }
        }
    }
    fn note_point<E:From<String>+From<&'static str>>(
        self,
        input: &report_core::ReportSource<'_>,
        budget: &output::ReportBudgetWith<'_,E>,
    ) -> Result<SourceNoteOrigin, E> {
        match self {
            Self::Source(at) => report_source_note(input,at.start,budget),
            Self::ImplicitList(dm_syntax::ImplicitListOrigin::ParserSynthetic) => {
                // A small independent virtual point allocation, not a source
                // cursor fallback. Admit before allocating its PathBuf/Arc.
                budget.charge(4096)?;
                Ok(SourceNoteOrigin {
                    path: Arc::new(std::path::PathBuf::from("(unknown)")),
                    line: 0,
                    byte_column: 0,
                })
            }
        }
    }
}
fn effect_notes<E:From<String>+From<&'static str>>(
    input: &report_core::ReportSource<'_>,
    effects: &[DirectEffect],
    blocking: bool,
    out: &mut Vec<Note>,
    budget: &output::ReportBudgetWith<'_,E>,
) -> Result<(), E> {
    for e in effects {
        budget.push(
            out,
            Note {
                message: if blocking {
                    budget.format(format_args!("{}() called here", e.reason))?
                } else {
                    budget.format(format_args!("{} happens here", e.reason))?
                },
                source: Some(e.origin.note_point(input, budget)?),
            },
        )?
    }
    Ok(())
}
fn call_notes<E:From<String>+From<&'static str>>(
    input: &report_core::ReportSource<'_>,
    path: &[CallEdge],
    out: &mut Vec<Note>,
    budget: &output::ReportBudgetWith<'_,E>,
) -> Result<(), E> {
    for edge in path {
        budget.push(
            out,
            Note {
                message: budget.format(format_args!(
                    "{}() called here",
                    display_target(input, edge.callee, &budget)?
                ))?,
                source: Some(edge.origin.note_point(input, budget)?),
            },
        )?
    }
    Ok(())
}
fn is_subtype(
    resolver: &(impl Resolver + ?Sized),
    child: SymbolId,
    parent: SymbolId,
) -> Result<bool, String> {
    match resolver.resolve(Q::Ancestry(child)) {
        M::Symbols(rows) => Ok(rows.contains(&parent)),
        _ => Err("purity subtype needs native ancestry proof".into()),
    }
}
fn identity(archive: &BodyArchive, ordinal: usize) -> Result<ProcedureIdentity, String> {
    let body = archive
        .occurrences()
        .get(ordinal)
        .ok_or("purity body ordinal unavailable")?;
    let tree = archive.tree();
    let m = tree
        .member(body.member)
        .ok_or("purity source member absent")?;
    Ok(ProcedureIdentity {
        owner: tree
            .type_node(m.owner)
            .ok_or("purity source owner absent")?
            .path,
        name: m.name,
        verb: m.kind == MemberKind::Verb,
        occurrence: tree
            .member_occurrence(body.member)
            .ok_or("purity original source version absent")?,
    })
}
pub(crate) fn source_parent(
    archive: &BodyArchive,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    member: dm_tree::MemberId,
    id: ProcedureIdentity,
) -> Result<Option<EffectTarget>, String> {
    use crate::checks_parent_call::SourcePredecessorProjection;
    match crate::checks_parent_call::source_predecessor_in_profile(
        archive.tree(),
        member,
        resolver,
        profile,
    )? {
        SourcePredecessorProjection::Source(p) => Ok(Some(EffectTarget::Source(p))),
        SourcePredecessorProjection::NoParent => Ok(None),
        SourcePredecessorProjection::BuiltinBoundary => {
            builtin_parent_after_sources(archive, profile, resolver, id)?
                .map(Some)
                .ok_or_else(|| "old parent exists but native builtin identity is unissued".into())
        }
    }
}

fn display<E:From<String>+From<&'static str>>(
    input: &report_core::ReportSource<'_>,
    id: ProcedureIdentity,
    budget: &output::ReportBudgetWith<'_,E>,
) -> Result<String, E> {
    let tree = input.archive.tree();
    let owner = tree
        .symbols()
        .text(id.owner)
        .ok_or("purity owner spelling absent")?;
    let name = tree
        .symbols()
        .text(id.name)
        .ok_or("purity callable spelling absent")?;
    // Borrow the original owner-local declaration roster. The native builder
    // publishes each member into this roster and declaration_targets together;
    // unlike a previous-chain walk, it retains every proc/verb implementation.
    let owner_id = tree
        .lookup_type(id.owner)
        .ok_or("effect display owner index absent")?;
    let roster = &tree
        .type_node(owner_id)
        .ok_or("effect display owner absent")?
        .members;
    budget.charge(roster.len())?; // bound the actual local scan, not all project rows
    let mut count = 0usize;
    for member in roster.iter() {
        let member = tree
            .member(*member)
            .ok_or("effect display indexed member absent")?;
        if member.owner != owner_id {
            return Err("effect display original owner roster mismatch".into());
        }
        if member.name == id.name && matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
            count += 1
        }
    }
    if count > 1 {
        budget.format(format_args!(
            "{}/proc/{name}[{}/{}]",
            if owner == "/" { "" } else { owner },
            id.occurrence,
            count
        ))
    } else {
        budget.format(format_args!(
            "{}/proc/{name}",
            if owner == "/" { "" } else { owner }
        ))
    }
}
/// Iterative Kosaraju over the unique effect graph. No Rust recursion or Db
/// callee recursion, even for deep or mutually recursive source programs.
fn scc(edges: &[Vec<usize>]) -> Result<Vec<usize>, String> {
    let n = edges.len();
    let mut reverse = vec![Vec::new(); n];
    for (i, row) in edges.iter().enumerate() {
        for &to in row {
            if to >= n {
                return Err("purity graph endpoint outside roster".into());
            }
            reverse[to].push(i)
        }
    }
    let mut seen = vec![false; n];
    let mut order = Vec::with_capacity(n);
    for start in 0..n {
        if seen[start] {
            continue;
        }
        seen[start] = true;
        let mut stack = vec![(start, 0)];
        while let Some((node, next)) = stack.last_mut() {
            if *next < edges[*node].len() {
                let child = edges[*node][*next];
                *next += 1;
                if !seen[child] {
                    seen[child] = true;
                    stack.push((child, 0));
                }
            } else {
                order.push(*node);
                stack.pop();
            }
        }
    }
    let mut component = vec![usize::MAX; n];
    let mut next = 0;
    for &start in order.iter().rev() {
        if component[start] != usize::MAX {
            continue;
        }
        component[start] = next;
        let mut stack = vec![start];
        while let Some(node) = stack.pop() {
            for &parent in &reverse[node] {
                if component[parent] == usize::MAX {
                    component[parent] = next;
                    stack.push(parent)
                }
            }
        }
        next += 1;
    }
    Ok(component)
}

#[path = "checker_effects_storage.rs"]
mod storage;
pub use storage::{report_capacity_bound, visit_report, Storage};

#[path = "checker_effects_sleep.rs"]
mod sleep;
use sleep::SleepSettings;

#[path = "checker_effect_targets.rs"]
mod targets;
pub(crate) use targets::{
    builtin_parent_after_sources, callable_target, display_target, original_target_parent,
    target_owner, target_parent_parts, EffectTarget,
};

fn next_input_key()->Result<u64,String>{
    static NEXT:AtomicU64=AtomicU64::new(1);
    NEXT.fetch_update(Ordering::Relaxed,Ordering::Relaxed,|v|v.checked_add(1)).map_err(|_|"purity issuance exhausted".into())
}
#[path="checker_effects_source.rs"]mod source_pages;
pub use source_pages::{EffectSource,EffectSourcePage,EffectContribution};

#[path="checker_effects_scc_reader.rs"]mod scc_reader;
pub use scc_reader::{CompactEffectScc,CompactEffectSummary,OwnedCompactEffectSummary};

#[path="checker_effects_compact_source.rs"]
mod compact_source;
pub use compact_source::{CompactEffectGraph,RetainedEffectGraph,CurrentEffectGraph};

#[path="checker_effects_page_facts.rs"]
mod page_facts;
pub use page_facts::{EffectPageFacts,EffectPageRead};

#[path="checker_effects_report.rs"]mod report_core;

#[path="checker_effects_report_pages.rs"]mod report_pages;

fn report_source_note<E:From<String>+From<&'static str>>(input:&report_core::ReportSource<'_>,offset:usize,budget:&output::ReportBudgetWith<'_,E>)->Result<SourceNoteOrigin,E>{let borrowed=input.archive.borrowed_source_note_point(offset)?;let bytes=borrowed.retained_charge().and_then(|n|n.checked_add(128)).ok_or("effect report note capacity overflow")?;budget.charge(bytes)?;Ok(borrowed.into_owned())}

pub use report_pages::{EffectReportPhase,EffectReportWork};

#[path="checker_effects_fingerprint.rs"]mod fingerprint;
pub use fingerprint::report_fingerprint;
