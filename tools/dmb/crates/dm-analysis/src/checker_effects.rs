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

pub type CanonicalOriginalBodyLoan<'a>=dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>)->Result<Arc<dm_tree::frontend::OriginalBodySyntaxProduct>,dm_tree::frontend::BodySyntaxFailure>+'a;
#[path = "checker_effects_output.rs"]
pub(crate) mod output;
pub use output::{ExecutionAdmission,ExecutionAdmissionLoan};
use output::ReportBudget;
#[derive(Clone, Debug)]
pub(crate) struct DirectEffect {
    pub origin: CallOrigin,
    pub reason: &'static str,
}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub(crate) struct AcceptedKeywordUse{pub target:EffectTarget,pub receiver:SymbolId,pub name:SymbolId,pub accepted:SymbolId,pub at:Span}
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
    pub original:Vec<OriginalBodyDiagnostic>,
    pub original_evaluations:usize,
    pub keywords:Vec<AcceptedKeywordUse>,
    pub blocking: Vec<DirectEffect>,
    pub waitfor_disabled: bool,
    pub transient: ReportBudget,
}
/// Stack-only disjoint loans into the one actual Draft. The shared budget is
/// borrowed, so policy findings and effect buffers consume the SAME admission.
pub(crate) struct DraftLoan<'a>{pub direct:&'a mut Vec<DirectEffect>,pub calls:&'a mut Vec<CallEdge>,pub immediate:&'a mut Vec<Diagnostic>,pub blocking:&'a mut Vec<DirectEffect>,pub waitfor_disabled:&'a mut bool,pub transient:&'a ReportBudget}
impl Draft{pub(crate) fn loan(&mut self)->DraftLoan<'_>{DraftLoan{direct:&mut self.direct,calls:&mut self.calls,immediate:&mut self.immediate,blocking:&mut self.blocking,waitfor_disabled:&mut self.waitfor_disabled,transient:&self.transient}}}


/// A synchronous loan of the SAME Draft budget, without a second counter.
struct DraftPolicyWork<'a>(&'a ReportBudget);
impl EffectReportWork for DraftPolicyWork<'_>{type Mark=(usize,usize);fn reserve(&mut self,bytes:usize)->std::io::Result<()>{self.0.charge(bytes).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}fn mark(&mut self)->std::io::Result<Self::Mark>{self.reserve(0)?;Ok((std::ptr::from_ref(self.0)as usize,self.0.used()))}fn reconcile(&mut self,mark:Self::Mark,retained:usize)->std::io::Result<()>{if mark.0!=std::ptr::from_ref(self.0)as usize{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"Draft work mark belongs to another operation"))}self.0.reconcile_after_drop(mark.1,retained).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))}}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalDiagnosticLocation{Expanded,ParserSynthetic,Reader(dm_tree::frontend::StoredOriginalReportedPoint)}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum OriginalDiagnosticPhase{Prelude,Body}
pub struct OriginalBodyDiagnostic{effect_immediate:bool,phase:OriginalDiagnosticPhase,diagnostic:Diagnostic,location:OriginalDiagnosticLocation,registration_tag:Option<&'static str>,default_level:DiagnosticSeverity}
impl OriginalBodyDiagnostic{pub fn phase(&self)->OriginalDiagnosticPhase{self.phase}pub fn registration_tag(&self)->Option<&'static str>{self.registration_tag}pub fn default_level(&self)->DiagnosticSeverity{self.default_level}pub fn diagnostic(&self)->&Diagnostic{&self.diagnostic}pub fn location(&self)->OriginalDiagnosticLocation{self.location}}
/// Factory-issued source context. Params/results keep this weak, not a graph
/// clone. A caller must present this same current archive/Db BEFORE cache hits.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]enum BodyPurpose{Effects,OriginalChecker,OriginalCurrentChecker}
pub struct EffectInput {
    purpose:BodyPurpose,
    original_receipt:Option<Weak<dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt>>,
    key: u64,
    archive: Arc<BodyArchive>,
    profile: PackedU128,
    order: Box<[(usize, ProcedureIdentity)]>,
    whole_roster: bool,
}
/// Stack-only authority to reuse validation of one immutable Original input.
pub struct OriginalEffectSourceProof<'a> {
    input: &'a EffectInput,
    profile: dm_tree::checker_builtins::ValidatedCheckerProfile<'a>,
}
impl OriginalEffectSourceProof<'_> {
    pub fn resolve_with_canonical_work(
        &self, query: dm_ir::ResolveQuery, work: &mut dyn dm_ir::CanonicalWork,
    ) -> std::io::Result<dm_ir::ResolvedMeaning> {
        self.profile.resolve_with_canonical_work(query, work)
    }

    fn require(&self, input: &EffectInput) -> Result<(), String> {
        if !std::ptr::eq(self.input, input) {
            return Err("original checker proof belongs to another input".into());
        }
        input.check_original_source_owner()?;
        self.profile.require(input.archive.tree(), input.profile)
            .map_err(|error| format!("original checker input profile: {error:?}"))
    }
}
impl EffectInput {
    /// Source-query coordination only; the bounded whole-plan constructor and
    /// policy remain unchanged. Actual page/body work is admitted on demand.
    pub fn source_pages(archive:Arc<BodyArchive>,profile:PackedU128)->Result<Arc<Self>,String>{
        EffectSource::new(&archive,profile).map_err(|failure|failure.to_string())?;
        Ok(Arc::new(Self{purpose:BodyPurpose::Effects,original_receipt:None,key:next_input_key()?,archive,profile,order:Box::new([]),whole_roster:false}))
    }

    /// Actual diagnostic-only Original source purpose on the EXISTING input.
    /// A current archive/Db/receipt is mandatory before any body cache hit.
    pub fn original_checker_source(archive:Arc<BodyArchive>,profile:PackedU128,receipt:&Arc<dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt>,host:&dyn BodySyntaxQueries)->Result<Arc<Self>,String>{
        if !receipt.authenticates(archive.tree())||!archive.uses_body_queries(host)||archive.source_mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err("original checker body purpose needs actual current Original diagnostic archive/Db/receipt".into())}
        let mut input=Self::source_pages(archive,profile)?;let fresh=Arc::get_mut(&mut input).ok_or("fresh original body purpose unexpectedly shared")?;fresh.purpose=BodyPurpose::OriginalChecker;fresh.original_receipt=Some(Arc::downgrade(receipt));Ok(input)
    }
    /// Same authenticated Original source purpose and a fresh graph identity.
    /// The caller opts in before any body/effect query enters the graph.
    pub fn original_checker_source_with_current_bodies(archive:Arc<BodyArchive>,profile:PackedU128,receipt:&Arc<dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt>,host:&dyn BodySyntaxQueries)->Result<Arc<Self>,String>{
        let mut input=Self::original_checker_source(archive,profile,receipt,host)?;
        Arc::get_mut(&mut input).ok_or("fresh current Original input unexpectedly shared")?.purpose=BodyPurpose::OriginalCurrentChecker;
        Ok(input)
    }
    pub fn is_original_checker_source(&self)->bool{matches!(self.purpose,BodyPurpose::OriginalChecker|BodyPurpose::OriginalCurrentChecker)}
    pub fn uses_current_original_bodies(&self)->bool{self.purpose==BodyPurpose::OriginalCurrentChecker}
    fn check_original_source_owner(&self)->Result<(),String>{
        if !self.is_original_checker_source()||self.original_receipt.as_ref().and_then(Weak::upgrade).is_none_or(|receipt|!receipt.authenticates(self.archive.tree()))||self.archive.body_query_host().is_none()||self.archive.source_mapping().initial_environment()!=dm_preprocess::InitialEnvironment::OriginalChecker0290{return Err("original checker input lacks its authentic immutable diagnostic source owner".into())}
        Ok(())
    }
    pub fn original_source_proof(&self) -> Result<OriginalEffectSourceProof<'_>, String> {
        self.check_original_source_owner()?;
        let profile = self.archive.tree().validated_checker_profile(self.profile)
            .map_err(|error| format!("original checker input profile: {error:?}"))?;
        Ok(OriginalEffectSourceProof { input: self, profile })
    }
    pub fn require_original_checker_source(&self) -> Result<(), String> {
        self.original_source_proof().map(|_| ())
    }
    /// Only a current authentic Original input can lend its actual diagnostic receipt.
    /// The receipt cannot be fabricated or promoted to compiler acceptance.
    pub fn with_original_declaration_receipt<T>(&self,consume:impl FnOnce(&dm_tree::diagnostic_declarations::DiagnosticDeclarationReceipt)->T)->Result<T,String>{self.require_original_checker_source()?;let receipt=self.original_receipt.as_ref().and_then(Weak::upgrade).ok_or("original declaration receipt owner retired")?;if !receipt.authenticates(self.archive.tree()){return Err("original declaration receipt owner differs".into())}Ok(consume(&receipt))}
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
            purpose:BodyPurpose::Effects,original_receipt:None,
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
        if self.is_original_checker_source(){self.require_original_checker_source()?;}
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
    pub fn compute_body_checked_controlled(
        self: &Arc<Self>,
        ordinal: usize,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
        checkpoint:&dyn Fn()->std::io::Result<()>,
    ) -> Result<Arc<BodyEffects>, crate::policy_body_demand::PolicyFailure> {
        let host=self.archive.body_query_host().ok_or("effect checked body requires original body-query host")?;
        self.compute_body_checked_using_admitted_controlled(ordinal,resolver,admission,&|input,_|host.syntax_checked(input),checkpoint)
    }

    /// Same BODY finalization, with an authenticated diagnostic-only purpose.
    pub fn compute_original_body_checked_using_admitted_controlled(
        self:&Arc<Self>,ordinal:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>,checkpoint:&dyn Fn()->std::io::Result<()>,
    )->Result<Arc<BodyEffects>,crate::policy_body_demand::PolicyFailure>{
        use crate::policy_body_demand::PolicyFailure;
        if !self.is_original_checker_source(){return Err("ordinary effects input cannot promote to original checker BODY".into())}
        if self.uses_current_original_bodies(){return Err("current Original graph input requires its active canonical body loan".into())}
        self.require_original_checker_source()?;
        let profile=self.archive.tree().validated_checker_profile(self.profile).map_err(|e|PolicyFailure::from(format!("original body actual profile: {e:?}")))?;
        let demand=crate::checker_prefix_demand::Original(crate::checker_prefix_demand::Checked{body,admission,profile,checkpoint,original_syntax:true});
        self.compute_body_evaluated_using(ordinal,resolver,admission,|archive,ordinal|archive.parse_checked_using(ordinal,&|input:&Arc<dm_tree::frontend::BodySyntaxInput>|body(input,&admission.current_view())).map_err(|failure|match failure{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>PolicyFailure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>error.message.into()}),demand,|body,demand|original_draft_using(&self.archive,body,resolver,self.profile,admission,demand,checkpoint))
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
self.compute_body_checked_using_admitted_controlled(ordinal,resolver,admission,body,&||Ok(()))}
pub fn compute_body_checked_using_admitted_controlled(
        self:&Arc<Self>,ordinal:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        body:&dyn Fn(&Arc<dm_tree::frontend::BodySyntaxInput>,&ExecutionAdmission)->Result<Arc<dm_tree::frontend::BodySyntax>,dm_tree::frontend::BodySyntaxFailure>,
        checkpoint:&dyn Fn()->std::io::Result<()>,
    )->Result<Arc<BodyEffects>,crate::policy_body_demand::PolicyFailure>{
        if self.is_original_checker_source(){return self.compute_original_body_checked_using_admitted_controlled(ordinal,resolver,admission,body,checkpoint)}
        let profile=self.archive.tree().validated_checker_profile(self.profile).map_err(|e|crate::policy_body_demand::PolicyFailure::from(format!("purity settings profile unavailable: {e:?}")))?;
        self.compute_body_using(ordinal,resolver,admission,|archive,ordinal|archive.parse_checked_using(ordinal,&|input:&std::sync::Arc<dm_tree::frontend::BodySyntaxInput>|body(input,&admission.current_view())).map_err(|failure|match failure{
            dm_tree::frontend::BodySyntaxFailure::Syntax(source)=>crate::policy_body_demand::PolicyFailure::from(source.message),
            dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>crate::policy_body_demand::PolicyFailure::Operational(actual),
        }),crate::checker_prefix_demand::Checked{body,admission,profile,checkpoint,original_syntax:false})
    }
    fn compute_body_using<'a,E:From<String>+for<'b>From<&'b str>,D:crate::checker_prefix_demand::Demand<Error=E>>(
        self:&'a Arc<Self>,ordinal:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        parse:impl FnOnce(&'a BodyArchive,usize)->Result<dm_tree::frontend::ArchivedBody<'a>,E>,
        prefix_demand:D,
    )->Result<Arc<BodyEffects>,E>{
        if self.is_original_checker_source(){return Err("original BODY purpose requires its actual checked union path".into())}
        self.compute_body_evaluated_using(ordinal,resolver,admission,parse,prefix_demand,|body,demand|crate::checker_expression_visit::effects_archived_using(&self.archive,body,resolver,self.profile,admission,demand))
    }
    fn compute_body_evaluated_using<'a,E:From<String>+for<'b>From<&'b str>,D:crate::checker_prefix_demand::Demand<Error=E>>(
        self:&'a Arc<Self>,ordinal:usize,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,
        parse:impl FnOnce(&'a BodyArchive,usize)->Result<dm_tree::frontend::ArchivedBody<'a>,E>,
        prefix_demand:D,
        evaluate:impl FnOnce(&dm_tree::frontend::ArchivedBody<'a>,&D)->Result<Draft,E>,
    )->Result<Arc<BodyEffects>,E>{
        if self.is_original_checker_source(){self.require_original_checker_source()?;}
        let procedure = identity(&self.archive, ordinal)?;
        if !self.is_original_checker_source()&&!self
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
        let body = parse(&self.archive, ordinal)?;
        let draft=evaluate(&body,&prefix_demand)?;
        let opening_parenthesis=body.signature_opening_parenthesis();
        let original_note=self.archive.callable_note_origin_borrowed_from_parsed(procedure,ordinal,&body);
        self.finish_evaluated_body(ordinal,procedure,resolver,admission,&prefix_demand,&settings,draft,opening_parenthesis,original_note)
    }

    fn finish_evaluated_body<E:From<String>+for<'b>From<&'b str>,D:crate::checker_prefix_demand::Demand<Error=E>>(
        self:&Arc<Self>,ordinal:usize,procedure:ProcedureIdentity,resolver:&(impl Resolver+?Sized),
        admission:&ExecutionAdmission,prefix_demand:&D,settings:&crate::checker_return_facts::PuritySettingsPermit<'_>,
        draft:Draft,opening_parenthesis:Option<Span>,
        original_note:Result<dm_tree::frontend::BorrowedSourceNoteOrigin<'_>,dm_tree::frontend::BorrowedCallableOriginError>,
    )->Result<Arc<BodyEffects>,E>{
        if draft
            .direct
            .len()
            .checked_add(draft.calls.len())
            .and_then(|n| n.checked_add(draft.blocking.len()))
            .and_then(|n| n.checked_add(draft.immediate.len()))
            .is_none_or(|n| !self.is_original_checker_source()&&n > MAX_EVENTS)
        {
            ReportBudget::for_operation(admission).deny();
            return Err(prefix_demand.resource("purity body exceeds bounded event admission"));
        }
        let origin_charge=match &original_note{Ok(point)=>point.retained_charge(),Err(_)=>Some(0)}.and_then(|n|n.checked_add(std::mem::size_of::<Option<Span>>()+std::mem::size_of::<Result<SourceNoteOrigin,dm_tree::frontend::BorrowedCallableOriginError>>())).ok_or_else(||prefix_demand.resource("effect original note capacity overflow"))?;
        // Borrowed lookup above allocates/clones nothing, including failures.
        // Admit the actual path backing BEFORE extending its Arc lifetime.
        draft.transient.charge(origin_charge).map_err(|_|prefix_demand.resource("effect original note admission exhausted"))?;
        let callable_origin=original_note.map(dm_tree::frontend::BorrowedSourceNoteOrigin::into_owned);
        let parent = source_parent_using(
            &self.archive,
            resolver,
            self.profile,
            self.archive
                .occurrences()
                .get(ordinal)
                .ok_or("effect ordinal absent")?
                .member,
            procedure,
            &mut||prefix_demand.checkpoint(),
        )?;
        let new_box_bytes=draft.original.len().checked_mul(std::mem::size_of::<OriginalBodyDiagnostic>()).and_then(|n|n.checked_add(draft.keywords.len().checked_mul(std::mem::size_of::<AcceptedKeywordUse>())?)).ok_or_else(||prefix_demand.resource("original BODY boxed backing overflow"))?;draft.transient.charge(new_box_bytes).map_err(|_|prefix_demand.resource("original BODY boxed backing admission exhausted"))?;
        if self.is_original_checker_source(){self.require_original_checker_source()?;}
        Ok(Arc::new(BodyEffects {
            input: Arc::downgrade(self),
            ordinal,
            procedure,
            pure:settings.own_pure(),
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
            original:draft.original.into(),
            original_evaluations:draft.original_evaluations,
            keywords:draft.keywords.into(),
            opening_parenthesis,
            callable_origin,
        }))
    }
    /// Opt-in full Original body traversal. The supplied live canonical loan
    /// controls all body-relative coordinates. Prelude and body are emitted
    /// privately in order. Graph publication remains a separate phase.
    pub fn with_current_original_body_rows<T>(
        self:&Arc<Self>,
        body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,
        syntax:&dm_syntax::SettingAdmission<'_>,
        resolver:&(impl Resolver+?Sized),
        admission:&ExecutionAdmission,
        checkpoint:&dyn Fn()->std::io::Result<()>,
        consume:impl FnOnce(&[OriginalBodyDiagnostic])->Result<T,crate::policy_body_demand::PolicyFailure>,
    )->Result<T,crate::policy_body_demand::PolicyFailure>{
        let result=self.compute_current_original_body_direct(body,syntax,resolver,admission,checkpoint)?;
        result.with_original_diagnostics(self,consume)?
    }

    /// Opt-in canonical body contribution using the retained host's direct
    /// syntax queries. A production graph owner must lend its active child
    /// lookup when switching Kind17, to retain its existing dependencies.
    pub fn compute_current_original_body_direct(
        self:&Arc<Self>,
        body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,
        syntax:&dm_syntax::SettingAdmission<'_>,
        resolver:&(impl Resolver+?Sized),
        admission:&ExecutionAdmission,
        checkpoint:&dyn Fn()->std::io::Result<()>,
    )->Result<Arc<BodyEffects>,crate::policy_body_demand::PolicyFailure>{
        self.compute_current_original_body_using(body,syntax,resolver,admission,checkpoint,None)
    }

    pub fn compute_current_original_body_using(
        self:&Arc<Self>,
        body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,
        syntax:&dm_syntax::SettingAdmission<'_>,
        resolver:&(impl Resolver+?Sized),
        admission:&ExecutionAdmission,
        checkpoint:&dyn Fn()->std::io::Result<()>,
        obtain:Option<&CanonicalOriginalBodyLoan<'_>>,
    )->Result<Arc<BodyEffects>,crate::policy_body_demand::PolicyFailure>{
        let proof = self.original_source_proof()?;
        self.compute_current_original_body_with_proof(body, syntax, resolver, admission, checkpoint, obtain, &proof)
    }

    pub fn compute_current_original_body_with_proof(
        self: &Arc<Self>,
        body: &dm_tree::frontend::CurrentArchivedBody<'_,'_>,
        syntax: &dm_syntax::SettingAdmission<'_>,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
        checkpoint: &dyn Fn() -> std::io::Result<()>,
        obtain: Option<&CanonicalOriginalBodyLoan<'_>>,
        proof: &OriginalEffectSourceProof<'_>,
    ) -> Result<Arc<BodyEffects>, crate::policy_body_demand::PolicyFailure> {
        use crate::policy_body_demand::PolicyFailure;
        proof.require(self)?;
        if !body.belongs_to(&self.archive)||resolver.source_owner()!=Resolver::source_owner(self.archive.tree()){
            return Err("current Original contribution has another archive or resolver".into());
        }
        let ordinal=self.archive.callables().ordinal(body.occurrence().member).ok_or("current Original body ordinal unavailable")?;
        let procedure=identity(&self.archive,ordinal)?;
        if !self.archive.occurrences().get(ordinal).is_some_and(|expected|std::ptr::eq(expected,body.occurrence())){
            return Err("current Original body occurrence differs".into());
        }
        let mut draft=Draft{transient:ReportBudget::for_operation(admission),..Default::default()};
        let demand=crate::checker_prefix_demand::Original(crate::checker_prefix_demand::Current{
            archive:&self.archive,primary:body,admission:syntax,checkpoint,obtain,profile:proof.profile,
        });
        let settings=crate::checker_return_facts::PuritySettingsPermit::issue_using(
            &self.archive,self.profile,procedure,&demand,
        )?;
        append_current_original_prelude(body,syntax,resolver,&draft.transient,&mut draft.original,checkpoint)?;
        let mut work=DraftPolicyWork(&draft.transient);
        let mut recorder=crate::checks_keyword_overrides::Recorder{
            archive:&self.archive,profile:self.profile,budget:&draft.transient,poll:checkpoint,rows:&mut draft.keywords,
        };
        let loan=DraftLoan{direct:&mut draft.direct,calls:&mut draft.calls,immediate:&mut draft.immediate,blocking:&mut draft.blocking,waitfor_disabled:&mut draft.waitfor_disabled,transient:&draft.transient};
        crate::checks_call_arguments::with_original_union_current_body_using(&self.archive,body,syntax,resolver,self.profile,loan,&demand,&mut work,checkpoint,&mut recorder,|findings,count|{
            publish_original_body_rows(&self.archive,&draft.transient,&mut draft.original,findings,checkpoint)?;
            draft.original_evaluations=count;
            Ok(())
        })?;
        checkpoint().map_err(PolicyFailure::Operational)?;
        let opening=body.syntax().opening_parenthesis().map_err(|actual|match actual{
            dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>PolicyFailure::Operational(actual),
            dm_tree::frontend::BodySyntaxFailure::Syntax(actual)=>actual.message.into(),
        })?;
        let original_note=opening
            .ok_or(dm_tree::frontend::BorrowedCallableOriginError::Body("primary callable opening token unavailable"))
            .and_then(|at|self.archive.borrowed_source_note_point(at.start).map_err(dm_tree::frontend::BorrowedCallableOriginError::Projection));
        self.finish_evaluated_body(ordinal,procedure,resolver,admission,&demand,&settings,draft,opening,original_note)
    }
    pub fn plan(
        self: &Arc<Self>,
        bodies: Vec<Arc<BodyEffects>>,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
    ) -> Result<Arc<EffectPlan>, String> {
self.plan_using(bodies,resolver,admission,&mut||Ok(()))}
    pub fn plan_checked_controlled(self:&Arc<Self>,bodies:Vec<Arc<BodyEffects>>,resolver:&(impl Resolver+?Sized),admission:&ExecutionAdmission,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Arc<EffectPlan>,crate::policy_body_demand::PolicyFailure>{self.plan_using(bodies,resolver,admission,&mut||checkpoint().map_err(crate::policy_body_demand::PolicyFailure::Operational))}
    fn plan_using<E:From<String>+From<&'static str>>(
        self: &Arc<Self>,
        bodies: Vec<Arc<BodyEffects>>,
        resolver: &(impl Resolver + ?Sized),
        admission: &ExecutionAdmission,
        checkpoint:&mut impl FnMut()->Result<(),E>,
    ) -> Result<Arc<EffectPlan>, E> {
        checkpoint()?;
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
                    .and_then(|n| n.checked_add(b.immediate_len()))
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
                parent = target_parent_parts_using(self,resolver,p,&bodies,&index,checkpoint)?;
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

fn original_draft_using<D:crate::checker_prefix_demand::Demand<Error=crate::policy_body_demand::PolicyFailure>>(
 archive:&BodyArchive,body:&dm_tree::frontend::ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,admission:&ExecutionAdmission,demand:&D,checkpoint:&dyn Fn()->std::io::Result<()>
)->Result<Draft,crate::policy_body_demand::PolicyFailure>{
 use crate::policy_body_demand::PolicyFailure;
 let mut draft=Draft{transient:ReportBudget::for_operation(admission),..Default::default()};
 {
  let Draft{direct,calls,immediate,blocking,waitfor_disabled,transient,original,original_evaluations,keywords}=&mut draft;
  let mut work=DraftPolicyWork(transient);
  let prefix=crate::checks_directive_binding::original_prefix_into_body_work(body,&mut work,checkpoint)?;
  for diagnostic in prefix{checkpoint().map_err(PolicyFailure::Operational)?;let(tag,default_level)=match diagnostic.family{"invalid_lint_directive_value"|"directive_at_definition"|"unknown_setting"=>(None,DiagnosticSeverity::Warning),"unknown_linter_setting"=>(Some("unknown_linter_setting"),DiagnosticSeverity::Warning),"return_type_expression"=>(None,DiagnosticSeverity::Error),"incompatible_directive"=>(Some("incompatible_directive"),DiagnosticSeverity::Error),"disabled_directive"=>(Some("disabled_directive"),DiagnosticSeverity::Warning),"sets_directive_twice"=>(Some("sets_directive_twice"),DiagnosticSeverity::Warning),_=>return Err("original directive prelude returned an unissued producer family".into())};transient.push(original,OriginalBodyDiagnostic{effect_immediate:false,phase:OriginalDiagnosticPhase::Prelude,diagnostic,location:OriginalDiagnosticLocation::Expanded,registration_tag:tag,default_level}).map_err(|message|PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;}
  let loan=DraftLoan{direct,calls,immediate,blocking,waitfor_disabled,transient};let mut recorder=crate::checks_keyword_overrides::Recorder{archive,profile,budget:transient,poll:checkpoint,rows:keywords};
  crate::checks_call_arguments::with_original_union_body_using(archive,body,resolver,profile,loan,demand,&mut work,checkpoint,&mut recorder,|findings,count|{
   publish_original_body_rows(archive,transient,original,findings,checkpoint)?;
   *original_evaluations=count;Ok(())
  })?;
 }checkpoint().map_err(PolicyFailure::Operational)?;Ok(draft)
}
fn append_current_original_prelude(
 body:&dm_tree::frontend::CurrentArchivedBody<'_,'_>,syntax:&dm_syntax::SettingAdmission<'_>,
 resolver:&(impl Resolver+?Sized),transient:&ReportBudget,original:&mut Vec<OriginalBodyDiagnostic>,
 checkpoint:&dyn Fn()->std::io::Result<()>,
)->Result<(),crate::policy_body_demand::PolicyFailure>{
 use crate::policy_body_demand::PolicyFailure;
 use crate::checks_directive_binding::{current_setting_prelude,current_prelude_diagnostic_backing};
 let oom=||std::io::Error::new(std::io::ErrorKind::OutOfMemory,"current Original prelude retained storage denied");
 if original.capacity()!=0{return Err("current Original prelude must precede all other body rows".into())}
 let mut work=DraftPolicyWork(transient);
 let mark=work.mark().map_err(PolicyFailure::Operational)?;
 let prelude=current_setting_prelude(body,resolver,syntax,&mut work,checkpoint)?;
 let count=prelude.row_count();
 let max_count=count.checked_mul(4).ok_or_else(||PolicyFailure::Operational(oom()))?;
 let row_size=std::mem::size_of::<OriginalBodyDiagnostic>();
 let capacity_bytes=max_count.checked_mul(row_size).ok_or_else(||PolicyFailure::Operational(oom()))?;
 work.reserve(capacity_bytes).map_err(PolicyFailure::Operational)?;
 original.try_reserve_exact(count).map_err(|_|PolicyFailure::Operational(oom()))?;
 if original.capacity()>max_count{return Err(PolicyFailure::Operational(oom()))}
 prelude.move_current_registered(body,syntax,&mut work,checkpoint,|diagnostic,tag,level|{
  if original.len()>=count{return Err(oom())}
  original.push(OriginalBodyDiagnostic{
   effect_immediate:false,phase:OriginalDiagnosticPhase::Prelude,diagnostic,
   location:OriginalDiagnosticLocation::Expanded,registration_tag:tag,default_level:level,
  });
  Ok(())
 })?;
 drop(prelude);
 let retained=original.capacity().checked_mul(row_size).and_then(|bytes|original.iter().try_fold(bytes,|sum,row|sum.checked_add(current_prelude_diagnostic_backing(&row.diagnostic)?))).ok_or_else(||PolicyFailure::Operational(oom()))?;
 work.reconcile(mark,retained).map_err(PolicyFailure::Operational)
}

fn publish_original_body_rows(
 archive:&BodyArchive,transient:&ReportBudget,original:&mut Vec<OriginalBodyDiagnostic>,
 findings:crate::checks_proc_visibility::Findings<'_>,checkpoint:&dyn Fn()->std::io::Result<()>,
)->Result<(),crate::policy_body_demand::PolicyFailure>{
 use crate::policy_body_demand::PolicyFailure;
   for row in findings.into_rows(){checkpoint().map_err(PolicyFailure::Operational)?;let(tag,level)=row.registration.ok_or("original BODY row lacks its actual producer registration")?;let location=if row.synthetic{OriginalDiagnosticLocation::ParserSynthetic}else if let Some(point)=row.reported{match point{crate::checks_proc_visibility::OriginalReported::Source(point)=>OriginalDiagnosticLocation::Reader(archive.source_mapping().store_original_reported_point(point)?),crate::checks_proc_visibility::OriginalReported::Builtin=>return Err("builtin declaration event cannot be delivered through a BODY producer".into())}}else{OriginalDiagnosticLocation::Expanded};let phase=if row.diagnostic.family=="procedure_redeclaration"{OriginalDiagnosticPhase::Prelude}else{OriginalDiagnosticPhase::Body};let effect_immediate=matches!(row.diagnostic.family,"spawn_return"|"pure_discard"|"operator_overload");transient.push(original,OriginalBodyDiagnostic{effect_immediate,phase,diagnostic:row.diagnostic,location,registration_tag:tag,default_level:level}).map_err(|message|PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)))?;
   }
 Ok(())
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
    original:Box<[OriginalBodyDiagnostic]>,
    original_evaluations:usize,
    keywords:Box<[AcceptedKeywordUse]>,
    opening_parenthesis:Option<Span>,
    callable_origin:Result<SourceNoteOrigin,dm_tree::frontend::BorrowedCallableOriginError>,
}
impl BodyEffects {
    pub(super) fn immediate_diagnostics(&self)->impl Iterator<Item=&Diagnostic>{self.immediate.iter().chain(self.original.iter().filter(|row|row.effect_immediate).map(|row|&row.diagnostic))}
    pub(super) fn immediate_len(&self)->usize{self.immediate_diagnostics().count()}
    pub fn with_original_keyword_uses<T>(&self,input:&Arc<EffectInput>,ordinal:usize,consume:impl FnOnce(&[AcceptedKeywordUse])->T)->Result<T,String>{self.validate(input)?;input.require_original_checker_source()?;if self.original_evaluations!=1||self.ordinal!=ordinal{return Err("keyword uses require actual once-evaluated original body at admitted ordinal".into())}Ok(consume(&self.keywords))}
    pub fn original_evaluation_count(&self)->usize{self.original_evaluations}
    pub fn with_original_diagnostics<T>(&self,input:&Arc<EffectInput>,consume:impl FnOnce(&[OriginalBodyDiagnostic])->T)->Result<T,String>{
        self.validate(input)?;
        let proof=input.original_source_proof()?;
        self.with_original_diagnostics_proven(input,&proof,consume)
    }
    pub fn with_original_diagnostics_proven<T>(
        &self,input:&Arc<EffectInput>,proof:&OriginalEffectSourceProof<'_>,
        consume:impl FnOnce(&[OriginalBodyDiagnostic])->T,
    )->Result<T,String>{
        self.validate(input)?;
        proof.require(input)?;
        if self.original_evaluations!=1{return Err("original diagnostics require the actual once-evaluated body contribution".into())}
        Ok(consume(&self.original))
    }
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
 self.validate(input)?;let control=std::cell::RefCell::new(checkpoint);let poll=||(control.borrow_mut())().map_err(D::Error::from);report_core::purity(&report_core::LegacyReportAccess::<D>{input,plan:&self.plan,summary:Some(self),checkpoint:&poll,demand:std::marker::PhantomData},resolver,policy,admission,&poll)
}
}
/// Issued only by the original report producer at the real emission site.
/// This is internal phase authority; wire fields and registration remain unchanged.
#[derive(Clone,Copy,Debug,Eq,PartialEq)]
pub enum ProducedPhase { BodyImmediate, SleepGraph, PurityGraph }
#[derive(Clone, Debug)]
pub struct Produced {
    phase: ProducedPhase,
    pub registration_tag: Option<&'static str>,
    pub severity: DiagnosticSeverity,
    pub diagnostic: Diagnostic,
    pub origin: SourceNoteOrigin,
}
impl Produced { pub fn phase(&self) -> ProducedPhase { self.phase } }
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
    phase: ProducedPhase,
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
                phase,
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
    checkpoint:&mut impl FnMut()->Result<(),E>,
) -> Result<(), E> {
    for edge in path {
        budget.push(
            out,
            Note {
                message: budget.format(format_args!(
                    "{}() called here",
                    display_target(input, edge.callee, &budget,checkpoint)?
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
pub(crate) fn source_parent_using<E:From<String>+From<&'static str>>(
    archive: &BodyArchive,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    member: dm_tree::MemberId,
    id: ProcedureIdentity,
    checkpoint:&mut impl FnMut()->Result<(),E>,
) -> Result<Option<EffectTarget>, E> {
    checkpoint()?;
    use crate::checks_parent_call::SourcePredecessorProjection;
    if archive.callables().identity_for_member(member)!=Some(id){return Err("original mixed parent source occurrence is foreign".into())}
    if let Some(group)=crate::checker_original_group::Group::for_target_using(archive.tree(),profile,EffectTarget::Source(id),checkpoint)?{return group.parent_using(EffectTarget::Source(id),resolver,checkpoint)}
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

pub(crate) fn source_parent(archive:&BodyArchive,resolver:&(impl Resolver+?Sized),profile:PackedU128,member:dm_tree::MemberId,id:ProcedureIdentity)->Result<Option<EffectTarget>,String>{source_parent_using(archive,resolver,profile,member,id,&mut||Ok(()))}

fn display<E:From<String>+From<&'static str>>(input:&report_core::ReportSource<'_>,id:ProcedureIdentity,budget:&output::ReportBudgetWith<'_,E>,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<String,E>{let text=crate::checker_callable_display::original(input.archive.tree(),id,|count|budget.charge(count),&mut *checkpoint)?;budget.format(format_args!("{text}"))}
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
    builtin_parent_after_sources, callable_target, display_target, original_target_parent, original_target_parent_using,
    target_owner, target_parent_parts_using, EffectTarget,
};

fn next_input_key()->Result<u64,String>{
    static NEXT:AtomicU64=AtomicU64::new(1);
    NEXT.fetch_update(Ordering::Relaxed,Ordering::Relaxed,|v|v.checked_add(1)).map_err(|_|"purity issuance exhausted".into())
}
#[path="checker_effects_source.rs"]mod source_pages;
pub use source_pages::{EffectSource,EffectSourcePage,EffectContribution,OriginalBodyReadFailure};

#[path="checker_effects_scc_reader.rs"]mod scc_reader;
pub use scc_reader::{CompactEffectScc,CompactEffectSummary,OwnedCompactEffectSummary};

#[path="checker_effects_compact_source.rs"]
mod compact_source;
pub use compact_source::{CompactEffectGraph,RetainedEffectGraph,CurrentEffectGraph};

#[path="checker_effects_page_facts.rs"]
mod page_facts;
pub use page_facts::{EffectPageFacts,EffectPageRead};
#[path="checker_effects_compact_page.rs"]mod compact_page;
pub use compact_page::{CompactGraphPage,CompactGraphPageBuilder,CompactGraphPageLoan,CompactGraphBodyLoan};
#[path="checker_effects_compact_replay.rs"]mod compact_replay;
pub use compact_replay::CompactGraphReplay;

#[path="checker_effects_report.rs"]mod report_core;

#[path="checker_effects_report_pages.rs"]mod report_pages;

fn report_source_note<E:From<String>+From<&'static str>>(input:&report_core::ReportSource<'_>,offset:usize,budget:&output::ReportBudgetWith<'_,E>)->Result<SourceNoteOrigin,E>{let borrowed=input.archive.borrowed_source_note_point(offset)?;let bytes=borrowed.retained_charge().and_then(|n|n.checked_add(128)).ok_or("effect report note capacity overflow")?;budget.charge(bytes)?;Ok(borrowed.into_owned())}

pub use report_pages::{EffectReportOrder,EffectReportPhase,EffectReportWork};

#[path="checker_effects_fingerprint.rs"]mod fingerprint;
pub use fingerprint::report_fingerprint;
