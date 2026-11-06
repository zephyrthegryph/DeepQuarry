//! Pinned evaluated-expression events, initial linear/ordinary-call cohort.
//!
//! Adapted from SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc
//! dreamchecker visit_statement/visit_expression/visit_term/visit_call (GPL-3.0).
//! This borrows primary syntax and native semantic facts. It never reparses DM.
//! Unsupported evaluation/origin contexts abort the entire event contribution.
// Debug observation only: counts actual evaluator entries, including selected
// compatibility paths. It stores no program facts and exposes no reset/setter.
#[cfg(debug_assertions)]std::thread_local!{static ACTUAL_EVALUATOR_ENTRIES:std::cell::Cell<u64>=const{std::cell::Cell::new(0)};}
#[cfg(debug_assertions)]pub fn actual_evaluator_entries_on_current_thread()->u64{ACTUAL_EVALUATOR_ENTRIES.with(std::cell::Cell::get)}

use crate::checker_evaluated_observer::{EvaluatedObserver, ScopeKind};
use crate::{
    checker_call_facts::{self, CallableFact},
    checks::BodyView,
    checks_parent_call,
};
use dm_ir::{PackedU128, ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, ForInitializer, Span, Statement, StatementKind};
use dm_tree::{
    frontend::{ArchivedBody, BodyArchive, ColdFrontend, ParsedBody},
    MemberId, SemanticTree,
};
use std::{collections::BTreeMap,borrow::Cow};
use foldhash::{HashMap,HashMapExt};
use crate::checker_prefix_demand::{Demand as PrefixDemand,Compatibility as PrefixCompatibility};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TypeFact {
    Known(SymbolId),
    List(Option<SymbolId>),
    /// Recursive list shape from the existing original parameter/local issuer.
    NestedList{depth:usize,element:Option<SymbolId>},
    Unknown,
    Unhinted,
    /// Actual pinned /callee.proc static result, not a runtime type or value.
    Proc,
    ReturnHint(crate::checker_return_facts::ReturnFixHint, Span),
    Deferred(&'static str),
}
impl TypeFact {
    fn declared(owner: Option<SymbolId>, element: Option<SymbolId>) -> Self {
        match owner {
            Some(owner) if owner == SymbolId::of("/list") => Self::List(element),
            Some(owner) => Self::Known(owner),
            None => Self::Unknown,
        }
    }
    fn receiver(self) -> Result<Option<SymbolId>, String> {
        match self {
            Self::Known(owner) => Ok(Some(owner)),
            Self::List(_) | Self::NestedList{..} => Ok(Some(SymbolId::of("/list"))),
            Self::Unknown | Self::Unhinted | Self::Proc | Self::ReturnHint(..) => Ok(None),
            Self::Deferred(reason) => Err(reason.into()),
        }
    }
}
#[derive(Clone, Debug)]
pub enum Event<'a> {
    ResolvedField {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
        fact: crate::checker_variable_facts::VariableFact,
    },
    FieldWithoutStaticType {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        hint: Option<(crate::checker_return_facts::ReturnFixHint, Span)>,
    },
    MissingVariable {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        explicit_global: bool,
    },
    MissingField {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
    },
    MissingCall {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
    },
    ResolvedImplicitListConstructor {
        initializer: &'a dm_syntax::ImplicitListInitializer,
        fact: CallableFact,
    },
    ResolvedCall {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        fact: CallableFact,
    },
    MissingParent {
        expression: &'a Expr,
        at: Span,
        display: String,
    },
    UnknownReceiverCall {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        // Unknown variables/parameters may need a declaration fix note that
        // current primary metadata has not issued. Other families can still
        // consume the same evaluation walk without inventing that note.
        hint: Result<Option<(crate::checker_return_facts::ReturnFixHint, Span)>, &'static str>,
    },
    DynamicMemberCall {
        expression: &'a Expr,
        at: Span,
        name: &'a str,
    },
    MissingImplicitNewHint {
        expression: &'a Expr,
    },
}
#[derive(Clone, Copy)]
enum EvaluationCallSite<'a> {
    Written(&'a Expr),
    ImplicitList(&'a dm_syntax::ImplicitListInitializer),
}
#[derive(Debug)]
pub struct Walk<'a> {
    pub events: Vec<Event<'a>>,
}
pub fn linear<'a>(
    frontend: &'a ColdFrontend,
    body: &'a ParsedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
) -> Result<Walk<'a>, String> {
    let view = BodyView::new(frontend, body)?;
    let mut walker = Walker::new(
        &frontend.snapshot.tree,
        None,
        &view.syntax().parsed().local_variables,
        &frontend.expanded.text,
        body.occurrence(),
        body.checker_parameters(profile)?,
        resolver,
        profile,
        None,
    )?;
    for statement in &view.syntax().parsed().statements {
        if walker.leaf_statement(statement)? {
            break;
        }
    }
    Ok(Walk {
        events: walker.events,
    })
}
/// Exact same evaluated-expression visitor, driven by the pinned reachable
/// traversal. There is no second CFG or model. Findings are atomic on Err.
pub fn evaluated<'a>(
    frontend: &'a ColdFrontend,
    body: &'a ParsedBody<'a>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
) -> Result<Walk<'a>, String> {
    let view = BodyView::new(frontend, body)?;
    let mut walker = Walker::new(
        &frontend.snapshot.tree,
        None,
        &view.syntax().parsed().local_variables,
        &frontend.expanded.text,
        body.occurrence(),
        body.checker_parameters(profile)?,
        resolver,
        profile,
        None,
    )?;
    crate::checker_reachable::analyze_with_observer(&view, &mut walker)?;
    Ok(Walk {
        events: walker.events,
    })
}
/// Borrow primary syntax and source from the exact retained compiler archive.
pub fn archived<'a>(
    archive: &'a BodyArchive,
    body: &'a ArchivedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
) -> Result<Walk<'a>, String> {
    if !body.belongs_to(archive) {
        return Err("semantic checker body belongs to another archive".into());
    }
    let mut walker = Walker::new(
        archive.tree(),
        Some(archive),
        &body.statement_body().parsed().local_variables,
        archive.expanded_source(),
        body.occurrence(),
        body.checker_parameters(profile)?,
        resolver,
        profile,
        None,
    )?;
    crate::checker_reachable::archived_with_observer(body, &mut walker)?;
    Ok(Walk {
        events: walker.events,
    })
}
/// Original evaluator value, carried beside static type by the SAME walk.
/// These are borrowed primary literal/path facts, never native compiler constants.
#[derive(Clone,Copy,Debug)]pub(crate) enum OriginalValue<'a>{Null,Literal(&'a dm_syntax::LiteralText),PrefabPath(&'a str),PrefabOwner(SymbolId),ProcedurePath{owner:SymbolId,kind:Option<&'static str>,name:&'a str}}
/// Checker facts for an existing native local binding, not another model.
/// The proof is intentionally narrow: authored null/literal initialization,
/// with no later reassignment, argument escape, or unsupported initializer.
/// original_value is the separate pinned evaluator channel: its local saved
/// value intentionally survives assignment, matching the original evaluator.
#[derive(Clone, Copy, Debug)]
struct LocalFact<'a> {
    original_value:Option<OriginalValue<'a>>,
    ty: TypeFact,
    declaration: Option<Span>,
    mutation_pure: bool,
    impurity: Option<bool>,
}
impl LocalFact<'_> {
    fn unproved(ty: TypeFact) -> Self {
        Self {
            ty,
            original_value:None,
            declaration: None,
            mutation_pure: false,
            impurity: None,
        }
    }
}
/// Borrowed pre-RHS hook in the existing evaluated call transition.
/// The callback may retain source metadata, never the temporary CallableFact.
pub(crate) trait CaseObserver<E>{fn switch_started(&mut self,_selector:&Expr,_cases:&[dm_syntax::SwitchCase],_default_present:bool,_at:Span)->Result<(),E>{Ok(())}fn do_while_unreachable(&mut self,at:Span,condition:Span)->Result<(),E>;fn logical_or(&mut self,cursor:dm_syntax::OriginalCaseCursor,expression:Span)->Result<(),E>;}
pub(crate) trait TypeIssueObserver<E>{fn undefined_type(&mut self,path:&str,at:Span)->Result<(),E>;}
pub(crate) trait IterationObserver<E>{fn iterable(&mut self,ty:TypeFact,at:Span)->Result<(),E>;fn invalid_range(&mut self,at:Span)->Result<(),E>;}
pub(crate) trait StaticObserver<E>{fn failure(&mut self,failure:crate::checker_static_reference::Failure<'_>,name:&str,procedure:bool,at:Span,expression:Span)->Result<(),E>;}
pub(crate) trait CatchObserver<E>{fn parameters(&mut self,count:usize,at:Span,expression:Span)->Result<(),E>;}
pub(crate) trait KeywordObserver<E>{fn begin_call(&mut self,tree:&SemanticTree,fact:&CallableFact,name:&str)->Result<(),E>;fn accepted_argument(&mut self,tree:&SemanticTree,fact:&CallableFact,receiver:SymbolId,name:&str,key:&Expr,at:Span)->Result<(),E>;}
/// Untagged original call-argument errors at the same pre-RHS transition.
pub(crate) type NamedArguments<'a>=HashMap<Cow<'a,str>,&'a Expr>;
#[derive(Clone,Copy,Debug,Default)]pub(crate) struct OriginalArguments<'a>{pub(crate) type_present:bool,pub(crate) type_value:Option<OriginalValue<'a>>,pub(crate) first_arglist:bool}
pub(crate) trait ArgumentObserver<E>{fn reserve(&mut self,bytes:usize)->Result<(),E>;fn original_values(&self)->bool{false}fn finished(&mut self,_tree:&SemanticTree,_fact:&CallableFact,_name:&str,_args:&[Expr],_named:&NamedArguments<'_>,_values:OriginalArguments<'_>,_at:Option<Span>,_expression:Span)->Result<(),E>{Ok(())}fn begin_call(&mut self,tree:&SemanticTree,fact:&CallableFact,name:&str)->Result<(),E>;fn argument(&mut self,tree:&SemanticTree,fact:&CallableFact,name:&str,key:Option<&Expr>,after_keyword:bool,at:Option<Span>,expression:Span)->Result<(),E>;}

/// One synchronous observer union for the actual body evaluation. These loans
/// are operation-local; no AST, result cache, or retained semantic owner is made.
pub(crate) enum BinaryWarning<'a> {
 Membership(&'a Expr),
 NegatedBitwise{op:&'a str,lhs:&'a Expr},
}
pub(crate) trait OriginalObserver<'a>: ArgumentObserver<crate::policy_body_demand::PolicyFailure>+KeywordObserver<crate::policy_body_demand::PolicyFailure>+TypeIssueObserver<crate::policy_body_demand::PolicyFailure>+IterationObserver<crate::policy_body_demand::PolicyFailure>+StaticObserver<crate::policy_body_demand::PolicyFailure>+CatchObserver<crate::policy_body_demand::PolicyFailure>+CaseObserver<crate::policy_body_demand::PolicyFailure>{
 fn access_levels(&self)->[crate::checks::Severity;5];
 fn body_started(&mut self)->Result<(),crate::policy_body_demand::PolicyFailure>;
 fn expression_event(&mut self,event:Event<'a>)->Result<(),crate::policy_body_demand::PolicyFailure>;
 fn flow_event(&mut self,event:crate::checker_reachable::Event<'a>)->Result<(),crate::policy_body_demand::PolicyFailure>;
 fn access_row(&mut self,row:crate::checks_proc_visibility::Row<'a>)->Result<(),crate::policy_body_demand::PolicyFailure>;
 fn immediate_row(&mut self,row:crate::checks::Diagnostic)->Result<(),crate::policy_body_demand::PolicyFailure>;
 fn binary_warning(&mut self,warning:BinaryWarning<'a>,expression:Span,at:Option<crate::checker_evaluated_observer::ExpressionOrigin>)->Result<(),crate::policy_body_demand::PolicyFailure>;
}
trait OriginalEvents<'a,E>{fn expression_event(&mut self,event:Event<'a>)->Result<(),E>;fn flow_event(&mut self,event:crate::checker_reachable::Event<'a>)->Result<(),E>;fn access_row(&mut self,row:crate::checks_proc_visibility::Row<'a>)->Result<(),E>;fn immediate_row(&mut self,row:crate::checks::Diagnostic)->Result<(),E>;fn binary_warning(&mut self,_warning:BinaryWarning<'a>,_expression:Span,_at:Option<crate::checker_evaluated_observer::ExpressionOrigin>)->Result<(),E>{Ok(())}}
#[path="checker_original_union.rs"]mod original_union;
#[path="checker_current_evaluation.rs"]mod current_evaluation;
pub(crate) use current_evaluation::{events_using as current_events_using,CurrentEvaluation};
pub(crate) use original_union::archived_using as original_union_archived_using;

#[derive(Clone,Copy)]struct KeywordCall<'c>{fact:&'c CallableFact,receiver:SymbolId,name:&'c str,at:Option<Span>,expression:Span,exact:bool}
/// Borrowed coordinate adapter for the SAME evaluator and primary roots.
/// Current construction requires an actual private archive/body/code binding;
/// no shifted AST, padded string, copied source or semantic model is built.
#[derive(Clone,Copy)]struct CodeSource<'a>{source:&'a str,projection:Option<dm_syntax::SyntaxProjection>}
impl<'a> CodeSource<'a>{
 fn issued(source:&'a str)->Self{Self{source,projection:None}}
 fn current(body:&'a dm_tree::frontend::CurrentArchivedBody<'_,'_>)->Self{Self{source:body.archive_owner().expanded_source(),projection:Some(body.syntax().projection())}}
 fn get(self,range:std::ops::Range<usize>)->Option<&'a str>{let span=Span::new(range.start,range.end);let span=match self.projection{Some(projection)=>projection.span(span)?,None=>span};self.source.get(span.range())}
 fn canonical_parameter_cursor(self,current:Span)->Result<Span,String>{match self.projection{Some(projection)=>projection.inverse().span(current).ok_or_else(||"current parameter cursor escaped actual canonical body binding".into()),None=>Ok(current)}}
}
struct Walker<'a, 'r, R: ?Sized,D:PrefixDemand=PrefixCompatibility> {
    prefix_demand:D,
    original_events:Option<&'r mut dyn OriginalEvents<'a,D::Error>>,
    keywords:Option<&'r mut dyn KeywordObserver<D::Error>>,
    case_errors:Option<&'r mut dyn CaseObserver<D::Error>>,
    type_errors:Option<&'r mut dyn TypeIssueObserver<D::Error>>,
    iteration_errors:Option<&'r mut dyn IterationObserver<D::Error>>,
    static_errors:Option<&'r mut dyn StaticObserver<D::Error>>,
    catch_errors:Option<&'r mut dyn CatchObserver<D::Error>>,
    argument_errors:Option<&'r mut dyn ArgumentObserver<D::Error>>,
    tree: &'a SemanticTree,
    prefix_archive: Option<&'a BodyArchive>,
    local_syntax: &'a dm_syntax::LocalVariableLedger,
    source: CodeSource<'a>,
    member: MemberId,
    resolver: &'r R,
    profile: PackedU128,
    owner: SymbolId,
    locals: BTreeMap<SymbolId, LocalFact<'a>>,
    events: Vec<Event<'a>>,
    scopes: Vec<BTreeMap<SymbolId, LocalFact<'a>>>,
    in_arguments: bool,
    effects: Option<crate::checker_effects::DraftLoan<'r>>,
    last_impurity: Option<bool>,
    original_value:Option<OriginalValue<'a>>,
    original_values:bool,
    finite_effect_events:bool,
    new_context: usize,
    evaluation_anchor: Option<crate::checker_effects::CallOrigin>,
    warning_anchor: Option<crate::checker_evaluated_observer::ExpressionOrigin>,
    statement_root: Option<&'a Expr>,
    terminal_return: Option<&'a Expr>,
    scope_denied_depth: usize,
    access: Option<crate::checks_proc_visibility::Access<'a>>,
}
impl<'a,'r,R:Resolver+?Sized> Walker<'a,'r,R,PrefixCompatibility>{
fn new(
        tree: &'a SemanticTree,
        prefix_archive: Option<&'a BodyArchive>,
        local_syntax: &'a dm_syntax::LocalVariableLedger,
        source: &'a str,
        occurrence: &dm_tree::frontend::BodyOccurrence,
        parameters: dm_tree::frontend::SourceParameterView<'_>,
        resolver: &'r R,
        profile: PackedU128,
        budget: Option<&crate::checker_effects::output::ReportBudget>,
    ) -> Result<Self, String> {Self::new_using(tree,prefix_archive,local_syntax,source,occurrence,parameters,resolver,profile,budget,PrefixCompatibility::new())}
}
impl<'a, 'r, R: Resolver + ?Sized,D:PrefixDemand> Walker<'a, 'r, R,D> {
    fn new_using(
        tree: &'a SemanticTree,
        prefix_archive: Option<&'a BodyArchive>,
        local_syntax: &'a dm_syntax::LocalVariableLedger,
        source: &'a str,
        occurrence: &dm_tree::frontend::BodyOccurrence,
        parameters: dm_tree::frontend::SourceParameterView<'_>,
        resolver: &'r R,
        profile: PackedU128,
        budget: Option<&crate::checker_effects::output::ReportBudget>, prefix_demand:D
) -> Result<Self, D::Error> {
        Self::new_using_with_type_issues(tree,prefix_archive,local_syntax,source,occurrence,parameters,resolver,profile,budget,prefix_demand,None)
    }
    fn new_using_with_type_issues(
        tree: &'a SemanticTree,
        prefix_archive: Option<&'a BodyArchive>,
        local_syntax: &'a dm_syntax::LocalVariableLedger,
        source: &'a str,
        occurrence: &dm_tree::frontend::BodyOccurrence,
        parameters: dm_tree::frontend::SourceParameterView<'_>,
        resolver: &'r R,
        profile: PackedU128,
        budget: Option<&crate::checker_effects::output::ReportBudget>, prefix_demand:D,mut type_errors:Option<&'r mut dyn TypeIssueObserver<D::Error>>
) -> Result<Self, D::Error> {
        Self::new_using_with_type_issues_source(tree,prefix_archive,local_syntax,CodeSource::issued(source),occurrence,parameters,resolver,profile,budget,prefix_demand,type_errors)
    }
    fn new_using_with_type_issues_source(
        tree: &'a SemanticTree,
        prefix_archive: Option<&'a BodyArchive>,
        local_syntax: &'a dm_syntax::LocalVariableLedger,
        source: CodeSource<'a>,
        occurrence: &dm_tree::frontend::BodyOccurrence,
        parameters: dm_tree::frontend::SourceParameterView<'_>,
        resolver: &'r R,
        profile: PackedU128,
        budget: Option<&crate::checker_effects::output::ReportBudget>, prefix_demand:D,mut type_errors:Option<&'r mut dyn TypeIssueObserver<D::Error>>
) -> Result<Self, D::Error> {
        parameters.require_for(tree, occurrence)?;
        let entries = parameters.entries()?;
        let member = occurrence.member;
        let node = tree
            .member(member)
            .ok_or("missing issued callable member")?;
        let owner = tree
            .type_node(node.owner)
            .ok_or("missing issued callable owner")?
            .path;
        // Map storage and every temporary source type String are admitted
        // before allocation. Normalized runtime signatures are not checker
        // type-path authority (qualifiers and suffix arrays may differ).
        if let Some(budget)=budget{budget.charge(Self::local_map_bound(entries.len().saturating_add(7)))?;}else{prefix_demand.storage(Self::local_map_bound(entries.len().saturating_add(7)))?;}
        #[cfg(debug_assertions)]ACTUAL_EVALUATOR_ENTRIES.with(|count|count.set(count.get().saturating_add(1)));
        let mut locals = BTreeMap::new();
        for (name, ty) in [
            (".", TypeFact::Unknown),
            ("args", TypeFact::List(None)),
            ("usr", TypeFact::Known(SymbolId::of("/mob"))),
            ("callee", TypeFact::Known(SymbolId::of("/callee"))),
            ("caller", TypeFact::Known(SymbolId::of("/callee"))),
            ("global", TypeFact::Known(SymbolId::of("/"))),
        ] {
            let mut fact = LocalFact::unproved(ty);
            if matches!(name, "args" | "global") {
                fact.impurity = Some(true);
            }
            locals.insert(SymbolId::of(name), fact);
        }
        if owner != SymbolId::of("/") {
            locals.insert(
                SymbolId::of("src"),
                LocalFact::unproved(TypeFact::Known(owner)),
            );
        }
        for parameter in entries {
            if parameter.variadic() {
                continue;
            }
            if let Some(budget) = budget {
                let bytes = parameter
                    .type_components()
                    .iter()
                    .fold(5usize, |sum, span| {
                        sum.saturating_add(span.end.saturating_sub(span.start))
                            .saturating_add(1)
                    });
                // String growth may overlap old/new allocations; do not credit
                // freed temporaries. Four times final bound covers both owners.
                budget.charge(bytes.saturating_mul(4).saturating_add(128))?;
            }else{let bytes=parameter.type_components().iter().try_fold(5usize,|sum,span|sum.checked_add(span.end.checked_sub(span.start)?).and_then(|n|n.checked_add(1))).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128)).ok_or_else(||prefix_demand.resource("current parameter path geometry overflow"))?;prefix_demand.storage(bytes)?;}
            let path = parameters.type_path(parameter)?;
            let ty = if let Some(observer)=type_errors.as_deref_mut(){let at=source.canonical_parameter_cursor(parameters.declaration_cursor(parameter)?)?;prefix_demand.checkpoint()?;checked_parameter_type_using(tree,resolver,profile,path.as_deref(),&mut|path|observer.undefined_type(path,at),&mut||prefix_demand.checkpoint())?}else{checked_parameter_type_using(tree,resolver,profile,path.as_deref(),&mut|_|Err(D::Error::from("parameter checker type needs undefined-type diagnostic projection")),&mut||prefix_demand.checkpoint())?};
            let mut fact = LocalFact::unproved(ty);
            fact.impurity = Some(true); // Pinned checker: every parameter is impure.
            locals.insert(SymbolId::of(parameters.name(parameter)?), fact);
        }
        Ok(Walker {
            prefix_demand,
            original_events:None,
            keywords:None,
            case_errors:None,
            type_errors,
            iteration_errors:None,static_errors:None,catch_errors:None,
            argument_errors:None,
            tree,
            prefix_archive,
            local_syntax,
            source,
            member,
            resolver,
            profile,
            owner,
            locals,
            events: Vec::new(),
            scopes: Vec::new(),
            in_arguments: false,
            effects: None,
            last_impurity: None,
            original_value:None,
            original_values:false,
            finite_effect_events:true,
            new_context: 0,
            evaluation_anchor: None,
            warning_anchor: None,
            statement_root: None,
            terminal_return: None,
            scope_denied_depth: 0,
            access: None,
        })
    }
    fn new_current_using(current:&'a dm_tree::frontend::CurrentArchivedBody<'_,'_>,parameters:dm_tree::frontend::SourceParameterView<'_>,resolver:&'r R,profile:PackedU128,demand:D)->Result<Self,D::Error>{
        Self::new_using_with_type_issues_source(current.tree(),Some(current.archive_owner()),&current.syntax().canonical_statement_storage().parsed().local_variables,CodeSource::current(current),current.occurrence(),parameters,resolver,profile,None,demand,None)
    }
    fn local_entry_bound() -> usize {
        1024usize.saturating_add(std::mem::size_of::<(SymbolId, LocalFact)>().saturating_mul(2))
    }
    fn local_map_bound(entries: usize) -> usize {
        entries
            .saturating_mul(Self::local_entry_bound())
            .saturating_add(std::mem::size_of::<BTreeMap<SymbolId, LocalFact<'a>>>())
            .saturating_add(64)
    }
    fn check_effect_admission(&self) -> Result<(), D::Error> {
        self.prefix_demand.checkpoint()?;
        if self.scope_denied_depth>0{return Err(self.prefix_demand.resource("native evaluator scope storage was refused"))}
        if let Some(effects) = &self.effects {
            effects.transient.charge(0)?
        }
        Ok(())
    }
    fn insert_local(&mut self, name: SymbolId, fact: LocalFact<'a>) -> Result<(), D::Error> {
        if let Some(effects)=&self.effects{effects.transient.charge(Self::local_entry_bound())?}else{self.prefix_demand.storage(Self::local_entry_bound())?;}
        self.locals.insert(name, fact);
        Ok(())
    }
    fn flush_access_rows(&mut self)->Result<(),D::Error>{if let(Some(access),Some(observer))=(self.access.as_mut(),self.original_events.as_deref_mut()){for row in access.drain_rows(){observer.access_row(row)?;}}Ok(())}
    fn event(&mut self, event: Event<'a>) -> Result<(), D::Error> {
        if let Some(observer)=self.original_events.as_deref_mut(){observer.expression_event(event)?;return self.prefix_demand.checkpoint()}
        if self.access.is_some(){return self.prefix_demand.checkpoint()}

        if let Some(effects) = &self.effects {
            effects.transient.push(&mut self.events, event)?
        } else {
            self.events.push(event)
        }
        Ok(())
    }
    fn with_warning_anchor<T>(
        &mut self, at: Option<crate::checker_evaluated_observer::ExpressionOrigin>,
        evaluate: impl FnOnce(&mut Self)->Result<T,D::Error>,
    )->Result<T,D::Error>{
        let old=std::mem::replace(&mut self.warning_anchor,at);
        let result=evaluate(self);
        self.warning_anchor=old;
        result
    }
    fn warning_source(at:Span)->Option<crate::checker_evaluated_observer::ExpressionOrigin>{
        Some(crate::checker_evaluated_observer::ExpressionOrigin::Source(at))
    }
    fn binary_warning(&mut self,warning:BinaryWarning<'a>,expression:Span)->Result<(),D::Error>{
        if self.effects.is_some(){
            if let Some(observer)=self.original_events.as_deref_mut(){
                observer.binary_warning(warning,expression,self.warning_anchor)?;
            }
        }
        Ok(())
    }
    fn leaf_statement(&mut self, statement: &'a Statement) -> Result<bool, D::Error> {
        self.check_effect_admission()?;
        let previous = self
            .evaluation_anchor
            .replace(crate::checker_effects::CallOrigin::Source(
                statement.header_span,
            ));
        let result = self.with_warning_anchor(Self::warning_source(statement.header_span),
            |this|this.leaf_statement_inner(statement));
        self.evaluation_anchor = previous;
        result
    }
    fn leaf_statement_inner(&mut self, statement: &'a Statement) -> Result<bool, D::Error> {
        // Both storage variants are the SAME written non-evaluated Set.
        if let Some(setting) = statement.setting() {
            let value = setting.value.original();
            if let Some(effects) = &mut self.effects {
                if setting.attribute == "waitfor"
                    && setting.relation == "="
                    && (matches!(&value.kind,ExprKind::Literal(n)if match n.original_value(){Some(value)=>matches!(value,dm_syntax::OriginalTokenValue::Int(0)),None=>n=="0"})
                        || matches!(&value.kind,ExprKind::Ident(n)if n=="FALSE"))
                {
                    *effects.waitfor_disabled = true;
                }
            }
            return Ok(false);
        }
        match &statement.kind {
            StatementKind::Var { declaration, value } => {
                self.declaration(declaration, value.as_ref(), statement.header_span)?
            }
            StatementKind::Assign { target, value, .. } => {
                let hint = self.expression(target, None)?.receiver()?;
                if self.last_impurity == Some(true) {
                    self.direct_effect("Assignment on purity breaking expression", None)?;
                }
                self.expression(value, hint)?;
                self.invalidate_local_target(target);
            }
            StatementKind::Expression(value) | StatementKind::Call(value) => {
                // Pinned Statement::Crash is not an ordinary callable term:
                // visit its one optional expression, then terminate. In
                // particular, an assignment argument is an expression rather
                // than a named-argument key and must retain its effects.
                if let ExprKind::Call{callee,args}=&value.kind {
                    if matches!(&callee.kind,ExprKind::Ident(name)if name=="CRASH") {
                        if args.len()>1{return Err("pinned CRASH statement accepts at most one expression".into())}
                        if let Some(argument)=args.first(){self.expression(argument,None)?;}
                        return Ok(true);
                    }
                }
                self.statement_expression(value)?;
            }
            StatementKind::Return(value) => {
                if self.effects.is_some() && self.new_context > 0 && value.is_some() {
                    self.immediate_effect(
                        "spawn_return",
                        crate::checks::Severity::Warning,
                        statement.header_span,
                        format_args!("returning a value in a spawn has no effect"),
                        Vec::new(),
                    )?;
                }
                if let Some(value) = value {
                    let previous = self.terminal_return.replace(value);
                    let result = self.expression(value, None);
                    self.terminal_return = previous;
                    result?;
                }
                return Ok(true);
            }
            StatementKind::Throw(value) => {
                self.expression(value, None)?;
            }
            StatementKind::Goto(_)
            | StatementKind::Break
            | StatementKind::BreakLabel(_)
            | StatementKind::Continue
            | StatementKind::ContinueLabel(_) => (),
            _ => {
                return Err(
                    "evaluated expressions need shared pinned control/root-observer contract"
                        .into(),
                )
            }
        }

        Ok(false)
    }
    fn declaration(
        &mut self,
        declaration: &'a str,
        value: Option<&'a Expr>,
        at: Span,
    ) -> Result<(), D::Error> {
        let matches = self.local_syntax.in_span(at).map_err(str::to_owned)?;
        let fact = match matches {
            [fact] => fact,
            [] => return Err("native local declaration has no original source receipt".into()),
            _ => {
                // A pair header can own two issued simple bindings. The
                // primary declaration spelling selects only between those
                // original facts; it cannot create a missing fact/type.
                let expected_name = dm_syntax::local_name(declaration)
                    .ok_or("native local declaration receipt is ambiguous")?;
                let mut selected = matches
                    .iter()
                    .filter(|fact| self.source.get(fact.name.range()) == Some(expected_name));
                let fact = selected
                    .next()
                    .ok_or("native local declaration has no matching source receipt")?;
                if selected.next().is_some() {
                    return Err("native local declaration fact is ambiguous".into());
                }
                fact
            }
        };
        let name = self
            .source
            .get(fact.name.range())
            .ok_or("native local name span unavailable")?;
        // The ledger already applied the ORIGINAL leading-only modifier and
        // one-list suffix rules. Never normalize that source path a second time.
        let source_type = fact.type_path_using(|span|self.source.get(span.range()).ok_or("native local component source unavailable")).map_err(str::to_owned)?;
        let ty=if let Some(observer)=self.type_errors.as_deref_mut(){self.prefix_demand.checkpoint()?;checked_parameter_type_using(self.tree,self.resolver,self.profile,source_type.as_deref(),&mut|path|observer.undefined_type(path,fact.anchor),&mut||self.prefix_demand.checkpoint())?}else{checked_parameter_type_using(self.tree,self.resolver,self.profile,source_type.as_deref(),&mut|_|Err(D::Error::from("parameter checker type needs undefined-type diagnostic projection")),&mut||self.prefix_demand.checkpoint())?};
        if let Some(value) = value {
            let hint=ty.receiver()?;
            let warning_at = fact.checker_statement_anchor().unwrap_or(at);
            self.with_warning_anchor(Self::warning_source(warning_at), |this| {
                this.expression(value, hint)
            })?;
        } else if let Some(initializer) = fact.implicit_list_initializer() {
            self.implicit_list_constructor(initializer)?;
        }
        let impurity = if value.is_some() {
            self.last_impurity
        } else {
            None
        };
        self.insert_local(
            SymbolId::of(name),
            LocalFact {
                ty,
                original_value:if value.is_some(){self.original_value}else if fact.implicit_list_initializer().is_some(){None}else{Some(OriginalValue::Null)},
                declaration: Some(fact.name),
                mutation_pure: literal_mutation_origin(value)?,
                impurity,
            },
        )?;
        Ok(())
    }
    /// Qualify one plain authored declaration against the ORIGINAL type
    /// roster. Keep existing projection for modifiers, lists, arrays and
    /// builtins. The terminal-return guard prevents losing a definition hint
    /// that a subsequent field/call follow could consume.
    fn missing_variable_type(
        &self,
        fact: &crate::checker_variable_facts::VariableFact,
        use_expr: &Expr,
    ) -> Result<Option<&'a str>, D::Error> {
        if !self.original_values
            || self.type_errors.is_none()
            || fact.formal.is_none()
            || fact.metadata.array.is_some()
            || fact.metadata.flags & !15 != 0
            || fact.metadata.list_element_type.is_some()
        {
            return Ok(None);
        }
        let Some(owner) = fact.metadata.declared_type else {
            return Ok(None);
        };
        // Avoid a whole authored-roster scan on ordinary known-type reads.
        // This tranche diagnoses only absence in both native and Checker views.
        if self.tree.lookup_type(owner).is_some() {
            return Ok(None);
        }
        let tree = self.tree;
        let path = tree.symbols().text(owner).ok_or("authored variable type spelling absent")?;
        let Some(first) = path.strip_prefix('/').and_then(|path| path.split('/').next()) else {
            return Ok(None);
        };
        if first.is_empty()
            || first == "list"
            || dm_syntax::is_original_static_type_modifier(first)
            || dm_syntax::has_checker_qualifiers(path)
        {
            return Ok(None);
        }
        let mut missing = false;
        checked_parameter_type_using(
            self.tree,
            self.resolver,
            self.profile,
            Some(path),
            &mut |_| { missing = true; Ok(()) },
            &mut || self.prefix_demand.checkpoint(),
        )?;
        if !missing {
            return Ok(None);
        }
        if !self.terminal_return.is_some_and(|root| std::ptr::eq(root, use_expr)) {
            return Err("missing authored variable type needs original downstream definition-hint propagation".into());
        }
        Ok(Some(path))
    }

    fn emit_missing_variable_type(&mut self, path: &str, at: Span) -> Result<TypeFact, D::Error> {
        self.prefix_demand.checkpoint()?;
        self.type_errors.as_deref_mut().ok_or("authored variable type observer disappeared")?
            .undefined_type(path, at)?;
        Ok(TypeFact::Unknown)
    }

    fn variable_use_type(
        &mut self,
        fact: &crate::checker_variable_facts::VariableFact,
        use_expr: &Expr,
        at: Span,
    ) -> Result<TypeFact, D::Error> {
        if let Some(path) = self.missing_variable_type(fact, use_expr)? {
            return self.emit_missing_variable_type(path, at);
        }
        self.variable_type(fact)
    }

    fn variable_type(
        &self,
        fact: &crate::checker_variable_facts::VariableFact,
    ) -> Result<TypeFact, D::Error> {
        if let (Some(archive), Some(formal)) = (self.prefix_archive, fact.formal) {
            let qualified = fact
                .metadata
                .declared_type
                .into_iter()
                .chain(fact.metadata.list_element_type)
                .any(|id| {
                    self.tree
                        .symbols()
                        .text(id)
                        .is_some_and(dm_syntax::has_checker_qualifiers)
                });
            if qualified || fact.metadata.array.is_some() {
                let properties = if self.source.projection.is_some(){
                    archive.checker_variable_properties_with_work(formal,self.profile,&mut|bytes|self.prefix_demand.storage(bytes),&mut|actual|self.prefix_demand.policy_failure(crate::policy_body_demand::PolicyFailure::Operational(actual)))?
                }else{archive.checker_variable_properties(formal,self.profile)?};
                return checked_issued_type(
                    self.tree,
                    self.resolver,
                    properties.declared_type,
                    properties.list_element_type,
                ).map_err(D::Error::from);
            }
        }
        if fact.metadata.flags & !15 != 0 || fact.metadata.array.is_some() {
            return Err("field modifiers/arrays need complete native declaration context".into());
        }
        checked_type(
            self.tree,
            self.resolver,
            fact.metadata.declared_type,
            fact.metadata.list_element_type,
        ).map_err(D::Error::from)
    }
    fn arguments(&mut self,args:&'a [Expr])->Result<(),D::Error>{self.arguments_for_call(args,None)}
    fn arguments_for_call(&mut self,args:&'a [Expr],call:Option<KeywordCall<'_>>)->Result<(),D::Error>{self.arguments_for_call_collect(args,call,None)}
    fn arguments_for_call_collect(&mut self,args:&'a [Expr],call:Option<KeywordCall<'_>>,mut captured:Option<&mut Vec<crate::checker_return_binding::Argument<'a>>>)->Result<(),D::Error>{
      if let(Some(call),Some(observer))=(call,self.keywords.as_mut()){observer.begin_call(self.tree,call.fact,call.name)?;}
      if let(Some(call),Some(observer))=(call,self.argument_errors.as_mut()){observer.begin_call(self.tree,call.fact,call.name)?;}
      let mut any_keywords=false;
      let filter=call.is_some_and(|call|self.argument_errors.as_ref().is_some_and(|observer|observer.original_values())&&call.name=="filter"&&call.fact.owner()==Some(SymbolId::of("/")));
      let mut values=OriginalArguments::default();
      let mut named=filter.then(NamedArguments::new);
      if filter{let bytes=args.len().checked_mul(std::mem::size_of::<(Cow<'_,str>,&Expr)>()).and_then(|n|n.checked_mul(16)).and_then(|n|n.checked_add(args.len().checked_mul(1024)?)).ok_or_else(||self.prefix_demand.resource("filter argument map capacity overflow"))?;self.argument_errors.as_mut().expect("filter observer selected").reserve(bytes)?;named.as_mut().expect("filter map selected").try_reserve(args.len()).map_err(|_|self.prefix_demand.resource("filter argument map allocation refused"))?;if named.as_ref().expect("filter map selected").capacity()>args.len().saturating_mul(4).saturating_add(3){return Err(self.prefix_demand.resource("filter argument map exceeded admitted capacity"))}}
      let mut binding_position=0usize;let mut original_index=0usize;for argument in args.iter() {
        if filter&&argument.span.start==argument.span.end&&matches!(&argument.kind,ExprKind::Literal(value)if value.as_str()=="null"){continue}let index=original_index;original_index=original_index.checked_add(1).ok_or("original argument index overflow")?;
        let (key,value)=match &argument.kind{ExprKind::Binary{op,lhs,rhs}if op=="="&&kwarg_key_mode(lhs,self.access.is_some())?=>(Some(lhs.as_ref()),rhs.as_ref()),_=>(None,argument)};
        // Original visit_call records the accepted key BEFORE visiting its
        // RHS. The enclosing call therefore wins this key before nested calls.
        any_keywords|=key.is_some();
        if let(Some(call),Some(observer))=(call,self.argument_errors.as_mut()){observer.argument(self.tree,call.fact,call.name,key,key.is_none()&&any_keywords,call.at,call.expression)?;}
        if let(Some(call),Some(key),Some(observer))=(call.filter(|call|!call.exact),key,self.keywords.as_mut()){observer.accepted_argument(self.tree,call.fact,call.receiver,call.name,key,call.at.ok_or("virtual keyword call lacks original source point")?)?;}
        if filter&&index==0&&key.is_none(){values.first_arglist=matches!(&value.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if name=="arglist"));}
        let previous=self.in_arguments;self.in_arguments=true;let result=self.expression(value,None);self.in_arguments=previous;let evaluated_type=result?;
        if let Some(captured)=captured.as_deref_mut(){
         // Empty native argument placeholders were omitted by original
         // arguments(); they do not consume a positional binding index.
         if !(argument.span.start==argument.span.end&&matches!(&argument.kind,ExprKind::Literal(raw)if raw.as_str()=="null")){
          let name=if let Some(key)=key{let demand=&self.prefix_demand;let budget=self.effects.as_ref().map(|effects|effects.transient);Some(original_argument_key::<D::Error>(key,&mut|bytes|{if let Some(budget)=budget{budget.charge(bytes).map_err(|_|demand.resource("return argument name admission refused"))?;}else{demand.storage(bytes)?;}Ok(())},&|message|demand.resource(message))?)}else{None};
          if captured.len()==captured.capacity(){return Err(self.prefix_demand.resource("return argument capture exceeds pre-admitted capacity"))}
          captured.push(crate::checker_return_binding::Argument{key:name,position:binding_position,ty:evaluated_type,value:self.original_value});
          if key.is_none(){binding_position=binding_position.checked_add(1).ok_or("return positional argument ordinal overflow")?;}
         }
        }
        if filter{if let Some(key)=key{let demand=&self.prefix_demand;let observer=self.argument_errors.as_mut().expect("selected filter observer");let name=original_argument_key::<D::Error>(key,&mut|bytes|observer.reserve(bytes),&|message|demand.resource(message))?;if name=="type"{values.type_present=true;values.type_value=self.original_value;}named.as_mut().expect("filter map selected").insert(name,value);}}
      }
      if filter{if let(Some(call),Some(observer))=(call,self.argument_errors.as_mut()){observer.finished(self.tree,call.fact,call.name,args,named.as_ref().expect("filter map selected"),values,call.at,call.expression)?;}}Ok(())
    }

    fn invalidate_local_name(&mut self, name: SymbolId) {
        let Some(current) = self.locals.get_mut(&name) else {
            return;
        };
        current.mutation_pure = false;
        let declaration = current.declaration;
        // Preserve this invalidation even if an inner declaration later
        // shadows the same name before leave_scope restores its parent map.
        for saved in self.scopes.iter_mut() {
            if let Some(older) = saved.get_mut(&name) {
                if older.declaration == declaration {
                    older.mutation_pure = false;
                }
            }
        }
    }
    fn invalidate_local_target(&mut self, target: &Expr) {
        match &target.kind {
            ExprKind::Ident(name) => {
                self.invalidate_local_name(SymbolId::of(name));
            }
            ExprKind::Group(value) => self.invalidate_local_target(value),
            ExprKind::Index { object, .. }
            | ExprKind::SafeIndex { object, .. }
            | ExprKind::Member { object, .. }
            | ExprKind::SafeMember { object, .. } => self.invalidate_local_target(object),
            _ => (),
        }
    }
    fn direct_effect(&mut self, reason: &'static str, at: Option<Span>) -> Result<(), D::Error> {
        if self.effects.is_none() {
            return Ok(());
        }
        let origin = at
            .map(crate::checker_effects::CallOrigin::Source)
            .or(self.evaluation_anchor)
            .ok_or("mutation effect needs original enclosing evaluation anchor")?;
        let effects = self.effects.as_mut().unwrap();
        if self.finite_effect_events && effects.direct.len() >= crate::checker_effects::MAX_EVENTS {
            return Err("native direct effects exceed bounded admission".into());
        }
        effects.transient.push(
            &mut effects.direct,
            crate::checker_effects::DirectEffect { reason, origin },
        )?;
        Ok(())
    }
    fn immediate_effect(
        &mut self,
        family: &'static str,
        severity: crate::checks::Severity,
        at: Span,
        message: std::fmt::Arguments<'_>,
        notes: Vec<crate::checks::Note>,
    ) -> Result<(), D::Error> {
        if let Some(effects) = &mut self.effects {
            if self.finite_effect_events && effects.immediate.len() >= crate::checker_effects::MAX_EVENTS {
                return Err("native immediate effects exceed bounded admission".into());
            }
            let message = effects.transient.format(message)?;
            effects.transient.charge(
                notes
                    .capacity()
                    .saturating_mul(std::mem::size_of::<crate::checks::Note>())
                    .saturating_add(64),
            )?;
            for note in &notes {
                effects
                    .transient
                    .charge(note.message.capacity().saturating_add(64))?
            }
            let row=crate::checks::Diagnostic{family,severity,span:at,expression_span:at,message,notes};
            if let Some(observer)=self.original_events.as_deref_mut(){observer.immediate_row(row)?;}else{effects.transient.push(&mut effects.immediate,row)?;}
        }
        Ok(())
    }
    // Only a genuine full Original BODY may complete these fixed diagnostics.
    // Selected/runtime contracts retain their previous explicit refusal.
    fn original_error(&mut self,family:&'static str,at:Span,message:std::fmt::Arguments<'_>)->Result<(),D::Error>{
        if self.original_events.is_none(){return Err("fixed original diagnostic needs the actual combined BODY observer".into())}
        self.immediate_effect(family,crate::checks::Severity::Error,at,message,Vec::new())
    }
    fn arguments_at(&mut self, args: &'a [Expr], at: Span) -> Result<(), D::Error> {
        let previous = self
            .evaluation_anchor
            .replace(crate::checker_effects::CallOrigin::Source(at));
        let result = self.with_warning_anchor(Self::warning_source(at),|this|this.arguments(args));
        self.evaluation_anchor = previous;
        result
    }
    fn ordinary_call(
        &mut self,
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
        args: &'a [Expr],
        member_follow: bool,
    ) -> Result<TypeFact, D::Error> {
        self.ordinary_call_with_dispatch(expression, at, name, receiver, args, member_follow, false)
    }
    fn ordinary_call_with_dispatch(
        &mut self,
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
        args: &'a [Expr],
        member_follow: bool,
        exact: bool,
    ) -> Result<TypeFact, D::Error> {
        self.call_with_origin(
            EvaluationCallSite::Written(expression),
            at,
            name,
            receiver,
            args,
            member_follow,
            exact,
        )
    }
    fn call_with_origin(
        &mut self,
        site: EvaluationCallSite<'a>,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
        args: &'a [Expr],
        member_follow: bool,
        exact: bool,
    ) -> Result<TypeFact, D::Error> {
        let fact = checker_call_facts::callable_any_using(
            self.tree,
            self.resolver,
            self.profile,
            receiver,
            SymbolId::of(name),
            &mut||self.prefix_demand.checkpoint(),
        )?;
        self.call_with_actual_fact(site,at,name,receiver,args,member_follow,exact,fact,false)
    }
    fn call_with_actual_fact(
        &mut self,
        site: EvaluationCallSite<'a>,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
        args: &'a [Expr],
        member_follow: bool,
        exact: bool,
        fact:CallableFact,
        resolved_exact_call:bool,
    ) -> Result<TypeFact, D::Error> {
        if matches!(fact, CallableFact::Missing) {
            if let EvaluationCallSite::Written(expression) = site {
                self.event(Event::MissingCall {
                    expression,
                    at,
                    name,
                    receiver,
                })?;
            }
            // Exact old missing-callee branch never evaluates arguments.
            return Ok(TypeFact::Unknown);
        }
        if let Some(access)=self.access.as_mut(){
            let expression=match site{EvaluationCallSite::Written(expression)=>expression.span,EvaluationCallSite::ImplicitList(_)=>at};
            let origin=match site{EvaluationCallSite::Written(_)=>Some(at),EvaluationCallSite::ImplicitList(_)=>None};
            let abort=access.call(&fact,receiver,member_follow,origin,expression,self.resolver,self.profile,&self.prefix_demand)?;
            self.flush_access_rows()?;if abort{return Ok(TypeFact::Unknown)}
        }
        if member_follow && self.access.is_none() {
            // Pinned Follow::Call checks inherited private directives BEFORE
            // visit_call/argument visitation. Source annotations on an older
            // ancestor can affect even a nearer builtin implementation.
            for verb in [false, true] {
                let query = Q::SourceDeclarationChain {
                    owner: receiver,
                    name: SymbolId::of(name),
                    verb,
                };
                let answer = self.resolver.resolve(query);
                if answer != Resolver::resolve(self.tree, query) {
                    return Err(
                        "member-call directive host differs from issued source chain".into(),
                    );
                }
                match answer {
                    M::Members(rows) => {
                        for row in rows.iter() {
                            let M::Declaration { identity, data, .. } = row else {
                                return Err("member-call directive chain malformed".into());
                            };
                            if data
                                .procedure
                                .as_ref()
                                .is_some_and(|p| !p.settings.is_empty())
                            {
                                if self.effects.is_some() {
                                    let archive = self
                                        .prefix_archive
                                        .ok_or("purity needs original archive")?;
                                    let permit =
                                        crate::checker_return_facts::PuritySettingsPermit::issue_using(
                                            archive,
                                            self.profile,
                                            *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?;
                                    crate::checker_return_facts::validate_source_directives_for_purity_using(self.tree,self.prefix_archive,*identity,&permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?;
                                } else {
                                    crate::checker_return_facts::validate_source_directives_using(
                                        self.tree,
                                        self.prefix_archive,
                                        *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?;
                                }
                            }
                        }
                    }
                    M::Missing => (),
                    _ => return Err("member-call directive source presence is unsupported".into()),
                }
            }
        }
        if self.access.is_none(){ if let Some(metadata) = fact.metadata() {
            let metadata = metadata
                .procedure
                .as_ref()
                .ok_or("callable signature unavailable")?;
            if !metadata.settings.is_empty() {
                let CallableFact::Source { identity, .. } = &fact else {
                    return Err("unexpected source directive metadata provenance".into());
                };
                if self.effects.is_some() {
                    let archive = self.prefix_archive.ok_or("purity needs original archive")?;
                    let permit = crate::checker_return_facts::PuritySettingsPermit::issue_using(
                        archive,
                        self.profile,
                        *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?;
                    crate::checker_return_facts::validate_source_directives_for_purity_using(
                        self.tree,
                        self.prefix_archive,
                        *identity,
                        &permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?;
                } else {
                    crate::checker_return_facts::validate_source_directives_using(
                        self.tree,
                        self.prefix_archive,
                        *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?;
                }
            }
        }
        }
        if self.effects.is_some() {
            let target = crate::checker_effects::callable_target(self.tree, self.profile, &fact)?;
            if let (Some(root), EvaluationCallSite::Written(expression)) =
                (self.statement_root, site)
            {
                if pure_discard_term(root, expression) {
                    let annotation = purity_annotation_using(
                        self.prefix_archive.ok_or("purity source archive absent")?,
                        self.resolver,
                        self.profile,
                        target, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?;
                    if let Some(annotation) = annotation {
                        let statement_at = self.evaluation_anchor.ok_or(
                            "discarded pure return needs original statement evaluation anchor",
                        )?;
                        self.immediate_effect(
                            "pure_discard",
                            crate::checks::Severity::Error,
                            statement_at.source_span()?,
                            format_args!("call to pure proc {name} discards return value"),
                            vec![crate::checks::Note {
                                message: "prohibited by this must_be_pure annotation".into(),
                                source: Some(
                                    self.prefix_archive
                                        .unwrap()
                                        .source_note_point(annotation.start)?,
                                ),
                            }],
                        )?;
                    }
                }
            }
            let effects = self.effects.as_mut().unwrap();
            if self.finite_effect_events && effects.calls.len() >= crate::checker_effects::MAX_EVENTS {
                return Err("effect call event admission exceeded".into());
            }
            effects.transient.push(
                &mut effects.calls,
                crate::checker_effects::CallEdge {
                    callee: target,
                    origin: match site {
                        EvaluationCallSite::Written(_) => {
                            crate::checker_effects::CallOrigin::Source(at)
                        }
                        EvaluationCallSite::ImplicitList(initializer) => {
                            crate::checker_effects::CallOrigin::ImplicitList(initializer.origin)
                        }
                    },
                    exact,
                    new_context: self.new_context > 0,
                },
            )?;
            if let EvaluationCallSite::Written(expression) = site {
                if self.new_context == 0 {
                    if let Some(reason) = blocking_call_reason_source_using(
                        self.tree,
                        self.profile,
                        self.source,
                        expression,
                        receiver,
                        &fact,
                        &self.prefix_demand,
                    )? {
                        let effects = self.effects.as_mut().unwrap();
                        if self.finite_effect_events && effects.blocking.len() >= crate::checker_effects::MAX_EVENTS {
                            return Err("blocking event admission exceeded".into());
                        }
                        effects.transient.push(
                            &mut effects.blocking,
                            crate::checker_effects::DirectEffect {
                                origin: crate::checker_effects::CallOrigin::Source(at),
                                reason,
                            },
                        )?;
                    }
                }
            }
        }
        match site {
            EvaluationCallSite::Written(expression) => self.event(Event::ResolvedCall {
                expression,
                at,
                name,
                fact: fact.clone(),
            })?,
            EvaluationCallSite::ImplicitList(initializer) => {
                self.event(Event::ResolvedImplicitListConstructor {
                    initializer,
                    fact: fact.clone(),
                })?
            }
        }
        let mut capture_return=false;
        if self.original_values&&(self.effects.is_some()||self.source.projection.is_some())&&self.original_events.is_some()&&self.prefix_demand.owns_return_expression_binding(){if let CallableFact::Source{metadata,..}=&fact{for node in metadata.procedure.as_ref().ok_or("return capture source signature absent")?.settings.iter(){self.prefix_demand.checkpoint()?;if matches!(node,dm_ir::ProcedureSettingNode::Setting(setting)if setting.name==SymbolId::of("SpacemanDMM_return_type")){capture_return=true;break}}}}

        let mut return_arguments=Vec::new();
        if capture_return{
            let bound=args.len().checked_mul(std::mem::size_of::<crate::checker_return_binding::Argument<'_>>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(256)).ok_or_else(||self.prefix_demand.resource("return argument capture capacity overflow"))?;
            if let Some(effects)=self.effects.as_ref(){effects.transient.charge(bound).map_err(|_|self.prefix_demand.resource("return argument capture admission denied"))?;}else{self.prefix_demand.storage(bound)?;}
            return_arguments.try_reserve_exact(args.len()).map_err(|_|self.prefix_demand.resource("return argument capture allocation refused"))?;
            if return_arguments.capacity()>args.len().saturating_mul(4).max(4){return Err(self.prefix_demand.resource("return argument capture exceeded admitted capacity"))}
        }
        match site {
            EvaluationCallSite::Written(_) => {
                let previous=self.evaluation_anchor.replace(crate::checker_effects::CallOrigin::Source(at));
                let expression=match site{EvaluationCallSite::Written(expression)=>expression.span,EvaluationCallSite::ImplicitList(_)=>at};
                let result=self.with_warning_anchor(Self::warning_source(at),|this|
                    this.arguments_for_call_collect(args,Some(KeywordCall{fact:&fact,receiver,name,at:Some(at),expression,exact}),capture_return.then_some(&mut return_arguments)));
                self.evaluation_anchor=previous;result?;
            },
            EvaluationCallSite::ImplicitList(initializer) => {
                let saved = self.evaluation_anchor.replace(
                    crate::checker_effects::CallOrigin::ImplicitList(initializer.origin),
                );
                let result = self.arguments_for_call(args,Some(KeywordCall{fact:&fact,receiver,name,at:None,expression:at,exact:true}));
                self.evaluation_anchor = saved;
                result?;
            }
        }
        self.last_impurity = None;
        if matches!(site, EvaluationCallSite::ImplicitList(_)) {
            // Old visit_new returns its own IsType assumption, not the New
            // procedure's return analysis. Its synthetic origin is not a
            // source cursor for a return-hint diagnostic.
            return Ok(TypeFact::Unhinted);
        }
        let mut skip_return_prefix=false;
        if capture_return{
            let CallableFact::Source{identity,..}=&fact else{unreachable!()};let archive=self.prefix_archive.ok_or("original return binding archive absent")?;let demand=self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient));let observer=&mut self.type_errors;
            match crate::checker_return_binding::for_call(archive,self.resolver,*identity,&return_arguments,&demand,|path|{if let Some(observer)=observer.as_deref_mut(){observer.undefined_type(path,at)}else{Err("dynamic return needs its actual undefined-type observer".into())}})?{
                crate::checker_return_binding::Binding::Bound(value)=>return Ok(if matches!(value,TypeFact::Unknown|TypeFact::Unhinted){TypeFact::ReturnHint(crate::checker_return_facts::ReturnFixHint::EvaluatedNone,at)}else{value}),
                crate::checker_return_binding::Binding::DiagnosedNone=>return Ok(TypeFact::Unknown),
                crate::checker_return_binding::Binding::InvalidOnly=>skip_return_prefix=true,
                crate::checker_return_binding::Binding::Absent=>(),
            }
        }
        let purity_permit =
            if self.effects.is_some() && matches!(&fact, CallableFact::Source { .. }) {
                let CallableFact::Source { identity, .. } = &fact else {
                    unreachable!()
                };
                Some(crate::checker_return_facts::PuritySettingsPermit::issue_using(
                    self.prefix_archive.unwrap(),
                    self.profile,
                    *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?)
            } else {
                None
            };
        let returned = if resolved_exact_call {
            crate::checker_return_facts::return_hint_for_actual_fact_using(self.tree,self.resolver,self.profile,&fact,name,self.prefix_archive,purity_permit.as_ref(),&self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)),skip_return_prefix)?
        } else if skip_return_prefix {
            crate::checker_return_facts::return_hint_without_return_prefix_using(self.tree,self.resolver,self.profile,receiver,SymbolId::of(name),self.prefix_archive,purity_permit.as_ref(),&self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?
        } else if let Some(permit) = &purity_permit {
            crate::checker_return_facts::return_hint_with_prefix_for_purity_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive,
                permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?
        } else {
            crate::checker_return_facts::return_hint_with_prefix_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?
        };
        let ty = checked_type(
            self.tree,
            self.resolver,
            returned.declared_type,
            returned.list_element_type,
        )?;
        if ty != TypeFact::Unknown {
            return Ok(ty);
        }
        if skip_return_prefix{let CallableFact::Source{identity,..}=&fact else{unreachable!()};return Ok(TypeFact::ReturnHint(crate::checker_return_facts::ReturnFixHint::UnannotatedSource(*identity),at));}
        let hint = if resolved_exact_call {
            crate::checker_return_facts::return_fix_hint_for_actual_fact_using(self.tree,self.resolver,self.profile,&fact,name,self.prefix_archive,purity_permit.as_ref(),&self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?
        } else if let Some(permit) = &purity_permit {
            crate::checker_return_facts::return_fix_hint_for_purity_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive,
                permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?
        } else {
            crate::checker_return_facts::return_fix_hint_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|effects.transient)))?
        };
        Ok(match hint {
            crate::checker_return_facts::ReturnFixHint::None => TypeFact::Unhinted,
            crate::checker_return_facts::ReturnFixHint::UnissuedBuiltin => TypeFact::Unknown,
            hint => TypeFact::ReturnHint(hint, at),
        })
    }
    fn explicit_source_call(&mut self,expression:&'a Expr,at:Span,args:&'a[Expr],parent:bool)->Result<TypeFact,D::Error>{
        let archive=self.prefix_archive.ok_or("exact source call lacks actual current archive")?;
        let caller=archive.callables().identity_for_member(self.member).ok_or("exact source call current occurrence absent")?;
        let fact=crate::checker_call_facts::explicit_fact_using(archive,caller,parent,self.resolver,self.profile,&mut||self.prefix_demand.checkpoint())?.ok_or("exact source call target disappeared")?;
        let name=match &fact{CallableFact::Source{identity,..}=>archive.tree().symbols().text(identity.name).ok_or("exact source call name absent")?,CallableFact::CheckerBuiltin{name,..}=>dm_tree::checker_builtins::pinned_catalog().map_err(|e|format!("exact builtin catalog: {e:?}"))?.spelling(*name).ok_or("exact builtin call name absent")?,CallableFact::Missing=>return Err("exact source call is not positively issued".into())};
        self.call_with_actual_fact(EvaluationCallSite::Written(expression),at,name,self.owner,args,false,true,fact,true)
    }
    fn implicit_list_constructor(
        &mut self,
        initializer: &'a dm_syntax::ImplicitListInitializer,
    ) -> Result<TypeFact, D::Error> {
        let owner = SymbolId::of("/list");
        let _ = checked_type(self.tree, self.resolver, Some(owner), None)?;
        let fact = checker_call_facts::callable_any_using(
            self.tree,
            self.resolver,
            self.profile,
            owner,
            SymbolId::of("New"),
            &mut||self.prefix_demand.checkpoint(),
        )?;
        if matches!(fact, CallableFact::Missing) {
            return Ok(TypeFact::Unknown); // pinned constructor skips every dimension without /list/New
        }
        self.call_with_origin(
            EvaluationCallSite::ImplicitList(initializer),
            initializer.brackets[0],
            "New",
            owner,
            &initializer.dimensions,
            false,
            true,
        )?;
        Ok(TypeFact::Unhinted)
    }
    fn construct(
        &mut self,
        expression: &'a Expr,
        form: dm_syntax::native_special_forms::Constructor<'a>,
        hint: Option<SymbolId>,
    ) -> Result<TypeFact, D::Error> {
        use dm_syntax::native_special_forms::Constructor;
        let (owner, args) = match form {
            Constructor::Dynamic => return Ok(TypeFact::Unknown), // old NewMiniExpr TODO skips target/args
            Constructor::Implicit { args } => {
                let Some(owner) = hint else {
                    self.event(Event::MissingImplicitNewHint { expression })?;
                    return Ok(TypeFact::Unknown);
                };
                (owner, args)
            }
            Constructor::Static { path, args } => {
                if self.original_events.is_some(){
                    let Some(owner)=crate::checker_prefab_value::value_using(self.tree,self.resolver,self.profile,self.owner,path,&mut||self.prefix_demand.checkpoint())?else{
                        self.original_error("unresolved_prefab",expression.span,format_args!("failed to resolve path {path}"))?;
                        return Ok(TypeFact::Unhinted);
                    };(owner,args)
                }else{
                    if !path.starts_with('/') {return Err("relative constructor path needs primary navigation facts".into());}
                    (SymbolId::of(path), args)
                }
            }
        };
        let _ = checked_type(self.tree, self.resolver, Some(owner), None)?;
        let new = crate::checker_call_facts::callable_any_using(
            self.tree,
            self.resolver,
            self.profile,
            owner,
            SymbolId::of("New"),
            &mut||self.prefix_demand.checkpoint(),
        )?;
        if matches!(new, CallableFact::Missing) {
            if ["/list", "/alist", "/vector", "/pixloc"]
                .iter()
                .any(|name| owner == SymbolId::of(name))
            {
                return Ok(if self.original_events.is_some(){TypeFact::Unhinted}else{TypeFact::Unknown}); // intentionally does NOT visit args
            }
            if self.original_events.is_some(){
                let path=self.tree.symbols().text(owner).ok_or("missing constructor owner spelling unavailable")?;
                self.original_error("missing_constructor",expression.span,format_args!("couldn't find {path}/proc/New"))?;
                return Ok(TypeFact::Unhinted);
            }
            return Err("constructor missing-New diagnostic is not yet implemented".into());
        }
        self.ordinary_call_with_dispatch(
            expression,
            expression.span,
            "New",
            owner,
            args,
            false,
            true,
        )?;
        self.last_impurity = None;
        // visit_new's IsType assumption does NOT set Analysis.static_ty. Never
        // turn runtime construction provenance into a static receiver type.
        Ok(TypeFact::Unhinted)
    }
    fn expression(
        &mut self,
        expression: &'a Expr,
        hint: Option<SymbolId>,
    ) -> Result<TypeFact, D::Error> {
        self.check_effect_admission()?;
        self.last_impurity = None;
        self.original_value=None;
        let result = self.expression_inner(expression, hint)?;
        // Child argument/RHS evaluation must not leak a value into a call,
        // unary or binary result. Only the original propagation cases retain it.
        if !match &expression.kind{ExprKind::Ident(_)|ExprKind::Literal(_)|ExprKind::TypePath(_)|ExprKind::Group(_)|ExprKind::Conditional{..}|ExprKind::Index{..}|ExprKind::SafeIndex{..}|ExprKind::ObjectInitializer{..}|ExprKind::StaticMember{..}=>true,ExprKind::Binary{op,..}=>crate::checker_original_expression_debug::original_assignment_operator(op),ExprKind::Call{callee,..}=>matches!(callee.kind,ExprKind::StaticMember{..}),_=>false}{self.original_value=None;}
        if self.effects.is_some() {
            if let TypeFact::Deferred(reason) = result {
                return Err(reason.into());
            }
        }
        Ok(result)
    }
    fn static_failure(&mut self,failure:crate::checker_static_reference::Failure<'a>,name:&str,procedure:bool,at:Span,expression:Span)->Result<TypeFact,D::Error>{self.original_value=None;self.last_impurity=None;self.prefix_demand.checkpoint()?;if let Some(observer)=self.static_errors.as_mut(){observer.failure(failure,name,procedure,at,expression)?;}Ok(TypeFact::Unhinted)}
    fn static_reference(&mut self,expression:&'a Expr,follow:&'a Expr,object:&'a Expr,name:&'a str,procedure:bool)->Result<TypeFact,D::Error>{
        use crate::checker_static_reference::Failure;
        if !self.original_values{return Err("static references require the original evaluated value channel".into())}
        let base=self.expression(object,None)?;let value=self.original_value;self.original_value=None;self.last_impurity=None;let end=follow.span.end.checked_sub(name.len()).ok_or("static selector origin underflow")?;if self.source.get(end..follow.span.end)!=Some(name){return Err("static selector differs from primary span".into())}let gap=self.source.get(object.span.end..end).ok_or("static separator outside primary spans")?;if gap.trim()!="::"{return Err("static separator needs retained primary token origin".into())}let offset=object.span.end+gap.len()-gap.trim_start().len();let at=Span::new(offset,offset+2);
        let owner=if let Some(owner)=base.receiver()?{owner}else{let Some(value)=value else{return self.static_failure(Failure::NoValue,name,procedure,at,expression.span)};if matches!(value,OriginalValue::Null|OriginalValue::Literal(_)){return self.static_failure(Failure::NonPath(value),name,procedure,at,expression.span)}let Some(owner)=crate::checker_static_reference::prefab_type_using(self.tree,self.resolver,value,&mut||self.prefix_demand.checkpoint())?else{return self.static_failure(Failure::MissingType(value),name,procedure,at,expression.span)};owner};
        if procedure{let fact=checker_call_facts::callable_any_using(self.tree,self.resolver,self.profile,owner,SymbolId::of(name),&mut||self.prefix_demand.checkpoint())?;if matches!(fact,CallableFact::Missing){return self.static_failure(Failure::MissingProc(owner),name,true,at,expression.span)}let declaring=fact.owner().ok_or("static proc reference resolved owner absent")?;let kind=crate::checker_static_reference::declaration_kind_using(self.tree,self.resolver,self.profile,declaring,SymbolId::of(name),&mut||self.prefix_demand.checkpoint())?;self.original_value=Some(OriginalValue::ProcedurePath{owner,kind,name});Ok(TypeFact::Unhinted)
        }else{match crate::checker_variable_facts::variable(self.tree,self.resolver,self.profile,owner,SymbolId::of(name))?{Some(fact)=>self.variable_use_type(&fact,expression,at),None=>self.static_failure(Failure::MissingField(owner),name,false,at,expression.span)}}
    }
    fn expression_inner(
        &mut self,
        expression: &'a Expr,
        hint: Option<SymbolId>,
    ) -> Result<TypeFact, D::Error> {
        if let Some(form) =
            dm_syntax::native_special_forms::constructor(expression).map_err(str::to_owned)?
        {
            return self.construct(expression, form, hint);
        }
        if let Some(form) =
            dm_syntax::native_special_forms::input(expression).map_err(str::to_owned)?
        {
            if self.effects.is_some() && self.new_context == 0 {
                let effects = self.effects.as_mut().unwrap();
                if self.finite_effect_events && effects.blocking.len() >= crate::checker_effects::MAX_EVENTS {
                    return Err("input blocking event admission exceeded".into());
                }
                effects.transient.push(
                    &mut effects.blocking,
                    crate::checker_effects::DirectEffect {
                        origin: crate::checker_effects::CallOrigin::Source(form.at),
                        reason: "input",
                    },
                )?;
            }
            self.arguments_at(form.args, form.at)?;
            if let Some(container) = form.in_list {
                let old = self
                    .evaluation_anchor
                    .replace(crate::checker_effects::CallOrigin::Source(form.at));
                let result = self.with_warning_anchor(Self::warning_source(form.at),
                    |this|this.expression(container,None));
                self.evaluation_anchor = old;
                result?;
            }
            self.last_impurity = None;
            // The old InputType produces assumptions, NOT Analysis.static_ty.
            return Ok(TypeFact::Unhinted);
        }
        if let Some(form) =
            dm_syntax::native_special_forms::locate(expression).map_err(str::to_owned)?
        {
            self.arguments_at(form.args, form.at)?;
            if let Some(container) = form.in_list {
                let old = self
                    .evaluation_anchor
                    .replace(crate::checker_effects::CallOrigin::Source(form.at));
                let result = self.with_warning_anchor(Self::warning_source(form.at),
                    |this|this.expression(container,None));
                self.evaluation_anchor = old;
                result?;
            }
            // Pinned locate's IsType assumption (even its 3-argument form)
            // leaves Analysis.static_ty unset. Do not invent receiver typing.
            return Ok(TypeFact::Unhinted);
        }
        if let Some(form) = dm_syntax::native_special_forms::pick(expression) {
            // The pinned checker visits each weight before its value. Both are
            // ordinary expressions, so assignment is never a named argument.
            let previous = self.evaluation_anchor.replace(
                crate::checker_effects::CallOrigin::Source(form.at),
            );
            let result = self.with_warning_anchor(Self::warning_source(form.at),|this| {
                for choice in form.choices() {
                    if let Some(weight) = choice.weight {
                        this.expression(weight, None)?;
                    }
                    this.expression(choice.value, None)?;
                }
                Ok(())
            });
            self.evaluation_anchor = previous;
            result?;
            self.last_impurity = None;
            self.original_value = None;
            return Ok(TypeFact::Unhinted);
        }
        if let Some(form) = dm_syntax::native_special_forms::chained_dispatch(expression)
            .map_err(str::to_owned)?
        {
            use dm_syntax::native_special_forms::DispatchTarget;
            let previous = self.evaluation_anchor.replace(
                crate::checker_effects::CallOrigin::Source(form.at),
            );
            let result = self.with_warning_anchor(Self::warning_source(form.at),|this| {
                match form.target {
                    DispatchTarget::Dynamic(targets) => this.arguments(targets)?,
                    DispatchTarget::External { library, function } => {
                        if let Some(library) = library {
                            this.expression(library, None)?;
                        }
                        this.expression(function, None)?;
                    }
                }
                this.arguments(form.args)
            });
            self.evaluation_anchor = previous;
            result?;
            self.last_impurity = None;
            self.original_value = None;
            return Ok(TypeFact::Unhinted);
        }
        match &expression.kind {
            ExprKind::Ident(name) => {
                if let Some(local) = self.locals.get(&SymbolId::of(name)).copied() {
                    let ty = local.ty;
                    self.last_impurity = local.impurity;
                    self.original_value=local.original_value;
                    if self.in_arguments {
                        self.invalidate_local_name(SymbolId::of(name));
                    }
                    return Ok(ty);
                }
                // Pinned `type` is a prefab/value fact, not a field declaration.
                if matches!(name.as_str(), "type" | "null") || self.original_values&&matches!(name.as_str(),"__TYPE__"|"__IMPLIED_TYPE__"|"__PROC__") {
                    self.original_value=match name.as_str(){"null"=>Some(OriginalValue::Null),"__PROC__"=>None,"__IMPLIED_TYPE__"=>hint.map(OriginalValue::PrefabOwner),_=>Some(OriginalValue::PrefabOwner(self.owner))};
                    return Ok(TypeFact::Unknown);
                }
                match crate::checker_variable_facts::variable(
                    self.tree,
                    self.resolver,
                    self.profile,
                    self.owner,
                    SymbolId::of(name),
                )? {
                    Some(fact) => {
                        let ty = self.variable_use_type(&fact, expression, expression.span)?;
                        self.last_impurity = Some(true);
                        Ok(ty)
                    }
                    None => {
                        self.event(Event::MissingVariable {
                            expression,
                            at: expression.span,
                            name,
                            explicit_global: false,
                        })?;
                        Ok(TypeFact::Unknown)
                    }
                }
            }
            ExprKind::Literal(text) => {
                let mut static_value=true;
                if let Some(parts) = (if text.original_value().is_some(){Ok(None)}else if self.access.is_some(){text.syntax_parts()}else{text.parts()}).map_err(str::to_owned)? {
                    static_value=!parts.lexical.map_err(|e|format!("checker literal context unsupported: {e:?}"))?.interpolated;
                    self.with_warning_anchor(Self::warning_source(expression.span),|this|{
                        for child in &parts.expressions {this.expression(child,None)?;}
                        Ok(())
                    })?;
                }
                self.last_impurity = None;
                self.original_value=static_value.then_some(OriginalValue::Literal(text));
                Ok(TypeFact::Unknown)
            }
            ExprKind::TypePath(path) => {if self.original_values{match crate::checker_prefab_value::value_using(self.tree,self.resolver,self.profile,self.owner,path,&mut||self.prefix_demand.checkpoint())?{Some(owner)=>self.original_value=Some(OriginalValue::PrefabOwner(owner)),None=>{self.original_error("unresolved_prefab",expression.span,format_args!("failed to resolve path {path}"))?;return Ok(TypeFact::Unhinted)}}}Ok(TypeFact::Unknown)},
            ExprKind::Group(value) => {
                let old = self.evaluation_anchor;
                if self.effects.is_some() {
                    let end = expression
                        .span
                        .start
                        .checked_add(1)
                        .ok_or("group origin overflow")?;
                    if self.source.get(expression.span.start..end) != Some("(") {
                        return Err("group lacks original opening-parenthesis token".into());
                    }
                    self.evaluation_anchor =
                        Some(crate::checker_effects::CallOrigin::Source(Span {
                            start: expression.span.start,
                            end,
                        }));
                }
                let result = self.with_warning_anchor(Self::warning_source(expression.span),
                    |this|this.expression(value,hint));
                self.evaluation_anchor = old;
                result
            }
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                self.expression(condition, None)?;
                let first = self.expression(then_value, hint)?;
                let impurity = self.last_impurity;
                let original_value=self.original_value;
                self.expression(else_value, hint)?;
                self.last_impurity = impurity;
                self.original_value=original_value;
                Ok(first)
            }
            ExprKind::Binary { op, lhs, rhs } if op == "<=>" && self.original_events.is_some() => {
                // Original LessOrGreater visits both operands without a hint,
                // then returns an empty Analysis even when the lhs is a list.
                self.expression(lhs, None)?;
                self.expression(rhs, None)?;
                self.last_impurity = None;
                Ok(TypeFact::Unhinted)
            }
            ExprKind::Binary { op, lhs, rhs } => {
                // Pinned AssignOp treats every assignment spelling alike:
                // visit lhs once, record its impurity, then visit rhs with its
                // basic static type. Return the RHS analysis, not arithmetic.
                let assignment=crate::checker_original_expression_debug::original_assignment_operator(op);
                if !assignment && !matches!(
                    op.as_str(),
                    "=" | "+"
                        | "-"
                        | "*"
                        | "/"
                        | "%"
                        | "%%"
                        | "**"
                        | "|"
                        | "&"
                        | "^"
                        | "<<"
                        | ">>"
                        | "&&"
                        | "||"
                        | "=="
                        | "!="
                        | "<>"
                        | "<"
                        | ">"
                        | "<="
                        | ">="
                        | "~="
                        | "~!"
                        | "in"
                ) {
                    return Err(
                        "unsupported binary operator needs its pinned evaluation contract"
                            .into(),
                    );
                }
                // Pinned `visit_expression` forwards the destination type
                // to both operands of logical OR, including implicit new.
                let operand_hint = if op == "||" { hint } else { None };
                if op=="in" {
                    self.binary_warning(BinaryWarning::Membership(lhs),expression.span)?;
                }
                let left = self.expression(lhs, operand_hint)?;
                let left_impurity = self.last_impurity;
                if assignment && left_impurity == Some(true) {
                    self.direct_effect("Assignment on purity breaking expression", None)?;
                }
                if op == "<<" {
                    let reason = if left == TypeFact::Known(SymbolId::of("/mob")) {
                        Some("LShift onto mob")
                    } else if left == TypeFact::Known(SymbolId::of("/savefile")) {
                        Some("LShift onto savefile")
                    } else if left == TypeFact::Known(SymbolId::of("/list")) {
                        Some("LShift onto list")
                    } else {
                        None
                    };
                    if let Some(reason) = reason {
                        self.direct_effect(reason, None)?;
                    }
                }
                let right =
                    self.expression(rhs, if assignment { left.receiver()? } else { operand_hint })?;
                if matches!(op.as_str(),"&"|"|"|"^"){
                    self.binary_warning(BinaryWarning::NegatedBitwise{op,lhs},expression.span)?;
                }
                if assignment {
                    self.invalidate_local_target(lhs);
                    return Ok(right);
                }
                // Pinned visit_binary retains a list STATIC TYPE, not the
                // lhs Analysis. Conversion from StaticType resets impurity.
                self.last_impurity = None;
                // Exact pinned visit_binary: only these LHS-list operations
                // retain a static list type. Every other binary is empty.
                Ok(
                    if matches!(left, TypeFact::List(_)|TypeFact::NestedList{..})
                        && matches!(op.as_str(), "+" | "-" | "|" | "&" | "^")
                    {
                        left
                    } else {
                        TypeFact::Unknown
                    },
                )
            }
            ExprKind::Call { callee, args } => match &callee.kind {
                ExprKind::Unary { op, value } if op == "::" => {
                    let ExprKind::Ident(name) = &value.kind else {
                        return Err("invalid primary global call target".into());
                    };
                    self.ordinary_call(
                        expression,
                        callee.span,
                        name,
                        SymbolId::of("/"),
                        args,
                        false,
                    )
                }
                ExprKind::Ident(name) if name == ".." => {
                    if let Some(access)=self.access.as_mut(){access.parent_call();}
                    let fact = checks_parent_call::parent_fact_in_profile_using(
                        self.tree,
                        self.member,
                        self.resolver,
                        Some(self.profile),
                        &mut||self.prefix_demand.checkpoint(),
                    )?;
                    if !fact.has_parent {
                        self.event(Event::MissingParent {
                            expression,
                            at: callee.span,
                            display: fact.display,
                        })?;
                        return Ok(TypeFact::Unknown);
                    }
                    self.explicit_source_call(expression,callee.span,args,true)
                }
                ExprKind::Ident(name) if name == "." => {
                    self.explicit_source_call(expression,callee.span,args,false)
                }
                // These are syntax primitives in the pinned grammar, not names
                // admitted from a diagnostic-only builtin spelling table.
                ExprKind::Ident(name) if matches!(name.as_str(), "list" | "alist") => {
                    self.arguments_at(args, expression.span)?;
                    self.last_impurity = None;
                    Ok(TypeFact::List(None))
                }
                ExprKind::Ident(name) if name == "CRASH" => {
                    if self.effects.is_some() {
                        return Err(
                            "CRASH effect primitive needs pinned source effect context".into()
                        );
                    }
                    if args.len() > 1 {
                        return Err("CRASH accepts at most one expression".into());
                    }
                    self.arguments(args)?;
                    Ok(TypeFact::Unknown)
                }
                ExprKind::Ident(name)
                    if matches!(
                        name.as_str(),
                        "call"
                            | "call_ext"
                            | "input"
                            | "pick"
                            | "as"
                            | "null"
                            | "__PROC__"
                            | "__TYPE__"
                            | "__IMPLIED_TYPE__"
                            | "SpacemanDMM_unlint"
                            | "SpacemanDMM_debug"
                    ) =>
                {
                    Err(
                        "call needs a primary syntax-primitive context, not ordinary proc lookup"
                            .into(),
                    )
                }
                ExprKind::Ident(name) => {
                    self.ordinary_call(expression, callee.span, name, self.owner, args, false)
                }
                ExprKind::StaticMember{object,selector}=>self.static_reference(expression,callee,object,selector,true),
                ExprKind::Member {
                    object,
                    selector,
                    via_colon,
                }
                | ExprKind::SafeMember {
                    object,
                    selector,
                    via_colon,
                } => {
                    let base = self.expression(object, None)?;
                    let at = member_origin_source(self.source, callee, object, selector, *via_colon)?;
                    if *via_colon {
                        self.event(Event::DynamicMemberCall {
                            expression,
                            at,
                            name: selector,
                        })?;
                        self.arguments_at(args, at)?;
                        self.last_impurity = None;
                        // Original colon calls visit argument values, then drop the receiver hint.
                        return Ok(if self.original_events.is_some() { TypeFact::Unhinted } else { TypeFact::Unknown });
                    }
                    let Some(receiver) = base.receiver()? else {
                        let hint = match base {
                            TypeFact::Unhinted => Ok(None),
                            TypeFact::ReturnHint(hint, call) => Ok(Some((hint, call))),
                            _ => Err(
                                "unknown-receiver call needs pinned fix-hint/declaration origins",
                            ),
                        };
                        self.event(Event::UnknownReceiverCall {
                            expression,
                            at,
                            name: selector,
                            hint,
                        })?;
                        // Exact failed Follow::Call returns Analysis::empty:
                        // later follows do not inherit the lhs fix hint.
                        return Ok(TypeFact::Unhinted);
                    };
                    self.ordinary_call(expression, at, selector, receiver, args, true)
                }
                _ => Err("call target requires pinned follow/selector origin context".into()),
            },
            ExprKind::StaticMember{object,selector}=>self.static_reference(expression,expression,object,selector,false),
            ExprKind::Member {
                object,
                selector,
                via_colon,
            }
            | ExprKind::SafeMember {
                object,
                selector,
                via_colon,
            } => {
                let base = self.expression(object, None)?;
                self.last_impurity = None;
                if !*via_colon&&base==TypeFact::Proc {if matches!(selector.as_str(),"type"|"name"|"desc"|"category"|"invisibility"){return Ok(TypeFact::Unhinted)}let at=member_origin_source(self.source,expression,object,selector,*via_colon)?;self.original_error("undefined_field_procpath",at,format_args!("undefined field: {selector:?} on procpath"))?;return Ok(TypeFact::Unhinted)}
                if *via_colon {
                    // Original colon fields return Analysis::empty, including safe colon.
                    return Ok(if self.original_events.is_some() { TypeFact::Unhinted } else { TypeFact::Unknown });
                }
                let Some(receiver) = base.receiver()? else {
                    let hint=match base {
                        TypeFact::Unhinted=>None,
                        TypeFact::ReturnHint(hint,call)=>Some((hint,call)),
                        _=>return Err("unknown-receiver field access needs pinned fix-hint/declaration origins".into()),
                    };
                    let at = member_origin_source(self.source, expression, object, selector, false)?;
                    self.event(Event::FieldWithoutStaticType {
                        expression,
                        at,
                        name: selector,
                        hint,
                    })?;
                    // The old failed follow returns Analysis::empty: subsequent
                    // fields have no inherited hint, while Index carries hints.
                    return Ok(TypeFact::Unhinted);
                };
                let at = member_origin_source(self.source, expression, object, selector, false)?;
                if receiver == SymbolId::of("/callee") && selector == "proc" {return Ok(TypeFact::Proc); }
                match crate::checker_variable_facts::variable(
                    self.tree,
                    self.resolver,
                    self.profile,
                    receiver,
                    SymbolId::of(selector),
                )? {
                    Some(fact) => {
                        let missing = self.missing_variable_type(&fact, expression)?;
                        let ty = if missing.is_none() { Some(self.variable_type(&fact)?) } else { None };
                        self.event(Event::ResolvedField {
                            expression,
                            at,
                            name: selector,
                            receiver,
                            fact,
                        })?;
                        // Pinned Follow::Field registers access before static_type.
                        match (ty, missing) {
                            (Some(ty), None) => Ok(ty),
                            (None, Some(path)) => self.emit_missing_variable_type(path, at),
                            _ => Err("invalid authored field type outcome".into()),
                        }
                    }
                    None => {
                        self.event(Event::MissingField {
                            expression,
                            at,
                            name: selector,
                            receiver,
                        })?;
                        Ok(TypeFact::Unknown)
                    }
                }
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                let base = self.expression(object, None)?;
                let impurity = self.last_impurity;
                let original=self.original_value;
                self.expression(index, None)?;
                self.original_value=if matches!(base,TypeFact::List(_)|TypeFact::NestedList{..}){None}else{original};
                self.last_impurity = if matches!(base, TypeFact::List(_)|TypeFact::NestedList{..}) {
                    None
                } else {
                    impurity
                };
                match base {
                    TypeFact::NestedList{depth:2,element}=>Ok(TypeFact::List(element)),
                    TypeFact::NestedList{depth,element}if depth>2=>Ok(TypeFact::NestedList{depth:depth-1,element}),
                    TypeFact::NestedList{..}=>Err("recursive list fact has invalid issued depth".into()),
                    TypeFact::List(element) => {
                        checked_type(self.tree, self.resolver, element, None).map_err(D::Error::from)
                    }
                    other => Ok(other),
                }
            }
            ExprKind::Unary { op, value }
                if matches!(op.as_str(), "pre++" | "post++" | "pre--" | "post--") =>
            {
                // The original parser issued this operator + operand shape.
                // Verify its primary token bytes before evaluating the operand.
                let _at = increment_origin_source(self.source, expression, value, op)?;
                if self.effects.is_some() || self.access.is_some() {
                    let operand = self.expression(value, None)?;
                    let operator = if op.ends_with("++") {
                        "operator++"
                    } else {
                        "operator--"
                    };
                    if self.last_impurity == Some(true) {
                        self.direct_effect(
                            if operator == "operator++" {
                                "operator++ done on non-local var"
                            } else {
                                "operator-- done on non-local var"
                            },
                            Some(_at),
                        )?;
                    }
                    self.last_impurity = None;
                    return match operand {
                        TypeFact::Unknown | TypeFact::Unhinted | TypeFact::Proc | TypeFact::ReturnHint(..) => {
                            Ok(TypeFact::Unhinted)
                        }
                        TypeFact::Known(owner) => {
                            match checker_call_facts::callable_any_using(
                                self.tree,
                                self.resolver,
                                self.profile,
                                owner,
                                SymbolId::of(operator),
                                &mut||self.prefix_demand.checkpoint(),
                            )? {
                                CallableFact::Missing => {
                                    let name = if self.original_values && owner == SymbolId::of("/") {
                                        "(global)"
                                    } else {
                                        self.tree.symbols().text(owner).ok_or("operator type spelling absent")?
                                    };
                                    self.immediate_effect("operator_overload",crate::checks::Severity::Error,_at,
                                        format_args!("Attempting {operator} on a {name} which does not overload {operator}"),Vec::new())?;
                                    Ok(TypeFact::Unhinted)
                                }
                                _ => self.ordinary_call_with_dispatch(
                                    expression,
                                    _at,
                                    operator,
                                    owner,
                                    &[],
                                    false,
                                    true,
                                ),
                            }
                        }
                        TypeFact::List(_) | TypeFact::NestedList{..} => {
                            self.immediate_effect("operator_overload",crate::checks::Severity::Error,_at,
                            format_args!("Attempting {operator} on a list which does not overload {operator}"),Vec::new())?;
                            Ok(TypeFact::Unhinted)
                        }
                        TypeFact::Deferred(reason) => Err(reason.into()),
                    };
                }

                let ExprKind::Ident(name) = &value.kind else {
                    return Err(
                        "increment target needs native non-local/overload purity facts".into(),
                    );
                };
                let Some(local) = self.locals.get(&SymbolId::of(name)) else {
                    return Err(
                        "increment target needs native non-local mutation purity facts".into(),
                    );
                };
                if !local.mutation_pure {
                    return Err(
                        "local increment needs native initializer/assignment/escape purity proof"
                            .into(),
                    );
                }
                let operand = self.expression(value, None)?;
                match operand {
                    // Exact pinned check_operator_overload: StaticType::None
                    // returns Analysis::empty, clearing any return fix hint.
                    // A direct local target has no non-local impurity effect.
                    TypeFact::Unknown | TypeFact::Unhinted | TypeFact::ReturnHint(..) => {
                        Ok(TypeFact::Unhinted)
                    }
                    _ => Err(
                        "typed increment needs native operator overload/error and purity context"
                            .into(),
                    ),
                }
            }
            ExprKind::Unary { op, value } if op == "::" => {
                // Pinned GlobalIdent is one term, not an ordinary identifier
                // visit or a dynamic access through the 'global' local.
                let ExprKind::Ident(name) = &value.kind else {
                    return Err("invalid primary global variable term".into());
                };
                let at = prefix_origin_source(self.source, expression, value, op)?;
                if self.source.get(value.span.range()) != Some(name.as_str()) {
                    return Err("global variable name differs from primary term span".into());
                }
                match crate::checker_variable_facts::variable_using(
                    self.tree, self.resolver, self.profile, SymbolId::of("/"),
                    SymbolId::of(name), &mut || self.prefix_demand.checkpoint(),
                )? {
                    Some(fact) => {
                        let ty = self.variable_use_type(&fact, expression, at)?;
                        self.last_impurity = Some(true);
                        Ok(ty)
                    }
                    None => {
                        self.event(Event::MissingVariable {
                            expression, at, name, explicit_global: true,
                        })?;
                        // Pinned returns Analysis::empty, with no fix hint.
                        Ok(TypeFact::Unhinted)
                    }
                }
            }
            ExprKind::Unary{op,value}if matches!(op.as_str(),"!"|"-"|"~"|"&"|"*")=>{
                // Pinned visit_follow visits the operand first. visit_unary
                // clears static type, value, fix hint and impurity for these
                // operators (Not adds assumptions only, not a static type).
                let _at=prefix_origin_source(self.source,expression,value,op)?;
                self.expression(value,None)?;self.last_impurity=None;
                Ok(TypeFact::Unhinted)
            }
            ExprKind::Unary { .. } => {
                Err("unary expression needs exact primary term-origin projection".into())
            }
            ExprKind::ObjectInitializer { object, .. }
                if matches!(object.kind, ExprKind::TypePath(_)) =>
            {
                if self.original_values{self.expression(object,None)?;}
                Ok(TypeFact::Unknown)
            } // pinned Prefab fields are not evaluated
            ExprKind::ObjectInitializer { .. } => {
                Err("non-prefab modification needs primary constructor context".into())
            }
            _ => Err("unsupported pinned expression evaluation form".into()),
        }
    }
}
impl<'a,R:Resolver+?Sized,D:PrefixDemand> EvaluatedObserver<'a,D::Error> for Walker<'a,'_,R,D> {
    fn control_event(&mut self,event:crate::checker_reachable::Event<'a>)->Result<bool,D::Error>{if let Some(observer)=self.original_events.as_deref_mut(){observer.flow_event(event)?;Ok(true)}else{Ok(false)}}
    fn admit_storage(&mut self, bytes: usize) -> Result<bool, D::Error> {
        if let Some(effects) = &self.effects {
            effects.transient.charge(bytes)?;
            Ok(true)
        } else if self.source.projection.is_some(){self.prefix_demand.storage(bytes)?;Ok(true)}else{
            Ok(false)
        }
    }
    fn storage_allocation_failed(&mut self) {
        if let Some(effects) = &self.effects {
            effects.transient.deny()
        }else if self.source.projection.is_some(){let _=self.prefix_demand.resource("current evaluator actual allocation refused");}
    }
    fn enter_scope(&mut self, kind: ScopeKind) {
        if kind == ScopeKind::Spawn {
            self.new_context += 1
        }
        if self.scope_denied_depth > 0 {
            self.scope_denied_depth = self.scope_denied_depth.saturating_add(1);
            return;
        }
        if let Some(effects) = &self.effects {
            let admitted = (|| {
                effects
                    .transient
                    .charge(Self::local_map_bound(self.locals.len()))?;
                effects.transient.reserve_slot(&mut self.scopes)
            })();
            if admitted.is_err() {
                effects.transient.deny();
                self.scope_denied_depth = 1;
                return;
            }
        }else{
            let admitted=(||{self.prefix_demand.storage(Self::local_map_bound(self.locals.len()))?;if self.scopes.len()==self.scopes.capacity(){let count=self.scopes.capacity().max(2).checked_mul(2).ok_or_else(||self.prefix_demand.resource("current evaluator scope count overflow"))?;let bytes=count.checked_mul(std::mem::size_of::<BTreeMap<SymbolId,LocalFact<'a>>>()).and_then(|n|n.checked_mul(4)).ok_or_else(||self.prefix_demand.resource("current evaluator scope geometry overflow"))?;self.prefix_demand.storage(bytes)?;self.scopes.try_reserve_exact(count-self.scopes.len()).map_err(|_|self.prefix_demand.resource("current evaluator scope allocation refused"))?;}Ok::<(),D::Error>(())})();
            if admitted.is_err(){self.scope_denied_depth=1;return}
        }
        self.scopes.push(self.locals.clone());
    }
    fn leave_scope(&mut self, kind: ScopeKind) {
        if kind == ScopeKind::Spawn {
            self.new_context -= 1;
        }
        if self.scope_denied_depth > 0 {
            self.scope_denied_depth -= 1;
            return;
        }
        let mut previous = self.scopes.pop().expect("paired pinned traversal scope");
        for (name, older) in previous.iter_mut() {
            if self.locals.get(name).is_some_and(|current| {
                current.declaration == older.declaration && !current.mutation_pure
            }) {
                older.mutation_pure = false;
            }
        }
        self.locals = previous;
    }
    fn leaf(&mut self, statement: &'a Statement) -> Result<(), D::Error> {
        self.leaf_statement(statement).map(|_| ())
    }
    fn expression(&mut self, expression: &'a Expr) -> Result<(), D::Error> {
        Walker::expression(self, expression, None).map(|_| ())
    }
    fn expression_at(&mut self,expression:&'a Expr,at:Option<crate::checker_evaluated_observer::ExpressionOrigin>)->Result<(),D::Error>{
        self.with_warning_anchor(at,|this|Walker::expression(this,expression,None).map(|_|()))
    }
    fn statement_expression_at(&mut self,expression:&'a Expr,at:Span)->Result<(),D::Error>{
        self.with_warning_anchor(Self::warning_source(at),|this|this.statement_expression(expression))
    }
    fn statement_expression(&mut self, expression: &'a Expr) -> Result<(), D::Error> {
        let old_root = self.statement_root.replace(expression);
        let old_anchor = self.evaluation_anchor;
        if self.evaluation_anchor.is_none() && self.effects.is_none() {
            self.evaluation_anchor =
                Some(crate::checker_effects::CallOrigin::Source(expression.span));
        }
        let result = (|| {
            if let ExprKind::Binary { op, lhs, .. } = &expression.kind {
                if op == "<<" {
                    Walker::expression(self, lhs, None)?;
                    if self.last_impurity == Some(true) {
                        self.direct_effect("purity breaking << on expression", None)?;
                    }
                }
            }
            Walker::expression(self, expression, None).map(|_| ())
        })();
        self.statement_root = old_root;
        self.evaluation_anchor = old_anchor;
        result
    }
    fn initializer(&mut self, initializer: &'a ForInitializer, at: Span) -> Result<(), D::Error> {
        match initializer {
            ForInitializer::Declare { declaration, value } => {
                self.binding(declaration, value.as_ref(), false, at)
            }
            ForInitializer::Expr(value) => {
                let previous = self
                    .evaluation_anchor
                    .replace(crate::checker_effects::CallOrigin::Source(at));
                let result = self.statement_expression_at(value,at);
                self.evaluation_anchor = previous;
                result
            }
        }
    }
    fn binding(
        &mut self,
        binding: &'a str,
        value: Option<&'a Expr>,
        always_untyped: bool,
        at: Span,
    ) -> Result<(), D::Error> {
        if dm_syntax::local_name(binding).is_some() {
            return self.declaration(binding, value, at);
        }
        if always_untyped {
            if binding.is_empty() || !binding.chars().all(|c| c.is_alphanumeric() || c == '_') {
                return Err("pair/catch binding lacks native simple-name projection".into());
            }
            if let Some(value) = value {
                Walker::expression(self, value, None)?;
            }
            self.insert_local(
                SymbolId::of(binding),
                LocalFact::unproved(TypeFact::Unknown),
            )?;
        }
        // Existing (nondeclared) range bindings deliberately skip their start.
        Ok(())
    }
    fn do_while_unreachable(&mut self,at:Span,condition:Span)->Result<(),D::Error>{if let Some(observer)=self.case_errors.as_deref_mut(){self.prefix_demand.checkpoint()?;observer.do_while_unreachable(at,condition)?;}Ok(())}
    fn switch_started(&mut self,selector:&'a Expr,cases:&'a [dm_syntax::SwitchCase],default_present:bool,at:Span)->Result<(),D::Error>{if let Some(observer)=self.case_errors.as_deref_mut(){self.prefix_demand.checkpoint()?;observer.switch_started(selector,cases,default_present,at)?;}Ok(())}
    fn switch_case(&mut self,case:&'a dm_syntax::SwitchCase)->Result<(),D::Error>{if let Some(observer)=self.case_errors.as_deref_mut(){self.prefix_demand.checkpoint()?;let cursor=case.original_cursor.map_err(D::Error::from)?;if let [dm_syntax::SwitchAlternative::Exact(value)]=case.alternatives.as_slice(){if matches!(&value.kind,ExprKind::Binary{op,..}if op=="||"){observer.logical_or(cursor,value.span)?;}}}Ok(())}
    fn iterable(&mut self,expression:&'a Expr,at:Span)->Result<(),D::Error>{let ty=self.with_warning_anchor(Self::warning_source(at),|this|Walker::expression(this,expression,None))?;self.prefix_demand.checkpoint()?;if let Some(observer)=self.iteration_errors.as_mut(){observer.iterable(ty,at)?;}Ok(())}
    fn invalid_range(&mut self,at:Span)->Result<(),D::Error>{self.prefix_demand.checkpoint()?;if let Some(observer)=self.iteration_errors.as_mut(){observer.invalid_range(at)?;}Ok(())}
    fn catch_parameters(&mut self,count:usize,at:Span,catch_header:Span)->Result<(),D::Error>{self.prefix_demand.checkpoint()?;if let Some(observer)=self.catch_errors.as_mut(){observer.parameters(count,at,catch_header)?;}Ok(())}
    fn catch_binding(&mut self,binding:Option<&'a str>,at:Span)->Result<(),D::Error>{
        let Some(binding)=binding else{return Ok(())};if binding.trim().is_empty(){return Ok(())}
        let ledger=self.local_syntax;let facts=ledger.in_span(at).map_err(str::to_owned)?;let mut found=false;
        for fact in facts.iter().filter(|fact|fact.source_kind==dm_syntax::LocalSourceKind::CatchBinding){self.prefix_demand.checkpoint()?;found=true;self.declaration(binding,None,Span::new(fact.anchor.start,fact.name.end))?;}
        if !found{return Err("actual catch binding has no primary parameter facts".into())}Ok(())
    }
}
/// Reuse the privately issued ORIGINAL parameter path, then authenticate every
/// resolved type against both the certified checker source roster and current
/// native resolver. Only an explicit missing-type observer may emit Unknown;
/// strict compatibility callbacks still refuse the missing source type.
fn checked_parameter_type_using<E:From<String>+for<'b>From<&'b str>>(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    path: Option<&str>,
    missing:&mut impl FnMut(&str)->Result<(),E>,
    checkpoint:&mut impl FnMut()->Result<(),E>,
) -> Result<TypeFact, E> {
    let Some(path) = path else {
        return Ok(TypeFact::Unknown);
    };
    if path.is_empty(){return Err("parameter checker type spelling is empty".into())}
    // The privately issued path already encodes every leading list layer and
    // the declaration suffix. Decode that shape once; do not flatten it into
    // an invented /list/subtype node. Each recursive static_type call strips
    // its own leading modifiers, using the SAME original vocabulary.
    let mut remaining=path;let mut depth=0usize;
    loop{checkpoint()?;if depth>0{loop{checkpoint()?;let Some(body)=remaining.strip_prefix('/')else{break};let component=body.split('/').next().ok_or("recursive original type component absent")?;if !dm_syntax::is_original_static_type_modifier(component){break}remaining=remaining.get(component.len()+1..).ok_or("recursive original modifier extent differs")?;}}if remaining=="/list"{depth=depth.checked_add(1).ok_or("recursive list depth overflow")?;remaining="";break}else if remaining.starts_with("/list/"){depth=depth.checked_add(1).ok_or("recursive list depth overflow")?;remaining=&remaining[5..];}else{break}}
    let element=(!remaining.is_empty()).then_some(remaining);
    for spelling in (depth>0).then_some("/list").into_iter().chain(element){
        if !tree.checker_source_type_presence(profile,spelling).map_err(|e|format!("parameter checker source type proof: {e:?}"))?{
            // Closed checker-source absence is distinct from native runtime
            // inventory. Keep the real native answer and observe exactly it.
            let id=SymbolId::of(spelling);let query=Q::Type(id);let expected=Resolver::resolve(tree,query);let native_present=tree.lookup_type(id).is_some();
            let consistent=match &expected{M::Missing=>!native_present,M::Unsupported(actual)=>*actual==query&&!native_present&&!tree.intrinsic_inventory_complete(),M::Symbol(actual)=>*actual==id&&native_present,_=>false};
            if !consistent||resolver.resolve(query)!=expected{return Err("undefined checker type contradicts actual current resolver".into())}
            missing(spelling)?;return Ok(TypeFact::Unknown)
        }
        let id=SymbolId::of(spelling);let query=Q::Type(id);let expected=Resolver::resolve(tree,query);if expected!=M::Symbol(id)||resolver.resolve(query)!=expected{return Err("parameter checker type differs from current native resolver".into())}
    }
    Ok(match depth{0=>TypeFact::Known(SymbolId::of(path)),1=>TypeFact::List(element.map(SymbolId::of)),_=>TypeFact::NestedList{depth,element:element.map(SymbolId::of)}})

}
fn checked_type(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    owner: Option<SymbolId>,
    element: Option<SymbolId>,
) -> Result<TypeFact, String> {
    checked_type_impl(tree, resolver, owner, element, false)
}
fn checked_issued_type(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    owner: Option<SymbolId>,
    element: Option<SymbolId>,
) -> Result<TypeFact, String> {
    checked_type_impl(tree, resolver, owner, element, true)
}
fn checked_type_impl(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    owner: Option<SymbolId>,
    element: Option<SymbolId>,
    issued: bool,
) -> Result<TypeFact, String> {
    for ty in owner.into_iter().chain(element) {
        let spelling = tree
            .symbols()
            .text(ty)
            .ok_or("declared type lacks native symbol spelling")?;
        if !issued && dm_syntax::has_checker_qualifiers(spelling) {
            return Err(
                "checker-specific declaration flags require primary compiler metadata".into(),
            );
        }
        let query = Q::Type(ty);
        let expected = Resolver::resolve(tree, query);
        if resolver.resolve(query) != expected || expected != M::Symbol(ty) {
            return Err("declared checker type needs existing compiler type fact".into());
        }
    }
    if owner == Some(SymbolId::of("/list")) {
        if let Some(element) = element {
            let spelling = tree
                .symbols()
                .text(element)
                .ok_or("list element lacks native spelling")?;
            if spelling == "/list" || spelling.starts_with("/list/") {
                return Err(
                    "nested-list static type requires recursive native declaration projection"
                        .into(),
                );
            }
        }
    }
    Ok(TypeFact::declared(owner, element))
}
fn kwarg_key(expression:&Expr)->Result<bool,String>{kwarg_key_mode(expression,false)}
fn kwarg_key_mode(expression: &Expr,original:bool) -> Result<bool, String> {
    Ok(match &expression.kind {
        ExprKind::Ident(_) => true,
        ExprKind::Literal(text) if original&&text.original_value().is_some()=>matches!(text.original_value(),Some(dm_syntax::OriginalTokenValue::String(_))),
        ExprKind::Literal(text) => match (if original{text.syntax_parts()}else{text.parts()}).map_err(str::to_owned)? {
            Some(parts) => {
                !parts
                    .lexical
                    .map_err(|e| format!("kwarg lexical shape unsupported: {e:?}"))?
                    .interpolated
            }
            None => false,
        },
        _ => false,
    })
}
fn pure_discard_term(mut root: &Expr, call: &Expr) -> bool {
    loop {
        if std::ptr::eq(root, call) {
            return matches!(&call.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(_)));
        }
        root = match &root.kind {
            ExprKind::Member { object, .. }
            | ExprKind::SafeMember { object, .. }
            | ExprKind::Index { object, .. }
            | ExprKind::SafeIndex { object, .. } => object,
            ExprKind::Unary { op, value }
                if matches!(
                    op.as_str(),
                    "pre++" | "post++" | "pre--" | "post--" | "!" | "-" | "~"
                ) =>
            {
                value
            }
            _ => return false,
        };
    }
}
fn purity_annotation_using<D:PrefixDemand>(
    archive: &BodyArchive,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    target: crate::checker_effects::EffectTarget, demand:&D
) -> Result<Option<Span>, D::Error> {
    let mut at = Some(target);
    let mut seen = std::collections::BTreeSet::new();
    while let Some(target) = at {
        if !seen.insert(target) {
            return Err("purity directive predecessor cycle".into());
        }
        if let crate::checker_effects::EffectTarget::Source(id) = target {
            let permit =
                crate::checker_return_facts::PuritySettingsPermit::issue_using(archive, profile, id, demand)?;
            if let Some(at) = permit.own_pure() {
                return Ok(Some(at));
            }
        }
        at = crate::checker_effects::original_target_parent_using(archive,profile,resolver,target,&mut||demand.checkpoint())?;
    }
    Ok(None)
}
/// Same original Walker, original reachable observer and current resolver. No
/// body job asks for another body's EFFECT contribution (only syntax/settings).
pub(crate) fn effects_archived<'a>(
    archive: &'a BodyArchive,
    body: &'a ArchivedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    admission: &crate::checker_effects::ExecutionAdmission,
) -> Result<crate::checker_effects::Draft, String> {effects_archived_using(archive,body,resolver,profile,admission,PrefixCompatibility::<String>::new())}
pub(crate) fn effects_archived_using<'a,D:PrefixDemand>(
    archive: &'a BodyArchive,
    body: &'a ArchivedBody<'_>,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    admission: &crate::checker_effects::ExecutionAdmission, prefix_demand:D
) -> Result<crate::checker_effects::Draft, D::Error> {
    if !body.belongs_to(archive) {
        return Err("effect body belongs to another archive".into());
    }
    let mut draft = crate::checker_effects::Draft {
        transient: crate::checker_effects::output::ReportBudget::for_operation(admission),
        ..Default::default()
    };
    let loan=draft.loan();
    let mut walker = Walker::new_using(
        archive.tree(),
        Some(archive),
        &body.statement_body().parsed().local_variables,
        archive.expanded_source(),
        body.occurrence(),
        body.checker_parameters(profile)?,
        resolver,
        profile,
        Some(loan.transient),
        prefix_demand,
    )?;
    walker.effects = Some(loan);
    crate::checker_reachable::archived_with_observer_using(body, &mut walker)?;
    walker.check_effect_admission()?;
    drop(walker);Ok(draft)
}
/// Native primary literal shape only. No inferred alias purity or evaluation
/// of an initializer a second time. Unsupported forms stay unproved.
fn literal_mutation_origin(value: Option<&Expr>) -> Result<bool, String> {
    let Some(value) = value else { return Ok(true) };
    match &value.kind {
        ExprKind::Literal(text) if text.original_value().is_some()=>Ok(true),
        ExprKind::Literal(text) => match text.parts().map_err(str::to_owned)? {
            Some(parts) => Ok(!parts
                .lexical
                .map_err(|e| format!("local mutation literal shape: {e:?}"))?
                .interpolated
                && parts.expressions.is_empty()),
            None => Ok(true),
        },
        ExprKind::Group(value) => literal_mutation_origin(Some(value)),
        _ => Ok(false),
    }
}
/// The ORIGINAL expression parser already distinguishes pre/post operators.
/// This validates its exact primary spans; no tokenization/source reparse or
/// inferred source column is used. Non-whitespace gaps remain unsupported.
fn increment_origin(
    source: &str,
    expression: &Expr,
    operand: &Expr,
    op: &str,
) -> Result<Span, String> {
    increment_origin_source(CodeSource::issued(source), expression, operand, op)
}
fn increment_origin_source(
    source: CodeSource<'_>,
    expression: &Expr,
    operand: &Expr,
    op: &str,
) -> Result<Span, String> {
    let (prefix, token) = match op {
        "pre++" => (true, "++"),
        "post++" => (false, "++"),
        "pre--" => (true, "--"),
        "post--" => (false, "--"),
        _ => return Err("not an issued increment/decrement shape".into()),
    };
    let (span, gap) = if prefix {
        if operand.span.end != expression.span.end {
            return Err("prefix operand end differs from primary expression".into());
        }
        let end = expression
            .span
            .start
            .checked_add(token.len())
            .ok_or("prefix operator span overflow")?;
        (
            Span::new(expression.span.start, end),
            source.get(end..operand.span.start),
        )
    } else {
        if operand.span.start != expression.span.start {
            return Err("postfix operand start differs from primary expression".into());
        }
        let start = expression
            .span
            .end
            .checked_sub(token.len())
            .ok_or("postfix operator span underflow")?;
        (
            Span::new(start, expression.span.end),
            source.get(operand.span.end..start),
        )
    };
    if source.get(span.range()) != Some(token)
        || !gap.is_some_and(|gap| gap.chars().all(char::is_whitespace))
    {
        return Err("increment token/gap differs from primary operator proof".into());
    }
    Ok(span)
}
/// Verify the primary-issued receiver/selector gap rather than assuming a -1
/// column. Comments/other tokens need retained primary origin metadata.
fn member_origin(
    source: &str,
    member: &Expr,
    object: &Expr,
    selector: &str,
    colon: bool,
) -> Result<Span, String> {
    member_origin_source(CodeSource::issued(source), member, object, selector, colon)
}
fn member_origin_source(
    source: CodeSource<'_>,
    member: &Expr,
    object: &Expr,
    selector: &str,
    colon: bool,
) -> Result<Span, String> {
    let end = member
        .span
        .end
        .checked_sub(selector.len())
        .ok_or("selector origin underflow")?;
    if source.get(end..member.span.end) != Some(selector) {
        return Err("selector spelling differs from primary span".into());
    }
    let gap = source
        .get(object.span.end..end)
        .ok_or("member origin outside primary spans")?;
    let mut marks = gap.char_indices().filter(|(_, c)| !c.is_whitespace());
    let Some((start, first)) = marks.next() else {
        return Err("missing member separator origin".into());
    };
    let expected = if colon { ':' } else { '.' };
    let separator = if first == '?' {
        let Some((_, second)) = marks.next() else {
            return Err("missing safe separator origin".into());
        };
        second
    } else {
        first
    };
    if separator != expected || marks.next().is_some() {
        return Err("member separator needs retained primary token origin".into());
    }
    Ok(Span::new(
        object.span.end + start,
        object.span.end + start + if first == '?' { 2 } else { 1 },
    ))
}
#[cfg(test)]
#[path = "checker_expression_visit_tests.rs"]
mod tests;

// The name policy is pinned old checker behavior, but callable identity must
// first come from the certified native profile/original declaration resolver.
fn certified_builtin_effect_contract(
    tree: &SemanticTree,
    profile: PackedU128,
    fact: &CallableFact,
) -> Result<bool, String> {
    match crate::checker_effects::callable_target(tree, profile, fact)? {
        crate::checker_effects::EffectTarget::Builtin(id) => tree
            .with_checker_builtin_procedure(id, |row| {
                // The fixed DSL owns DECLARATIONS with no executable DM body.
                // Old checker contributes no direct effects for code=None; virtual
                // source descendants remain explicit targets in the SAME plan.
                row.metadata.procedure.is_some()
            })
            .map_err(|e| format!("{e:?}")),
        crate::checker_effects::EffectTarget::Source(_) => Ok(false),
    }
}

fn blocking_call_reason(
    tree: &SemanticTree,
    profile: PackedU128,
    source: &str,
    expression: &Expr,
    receiver: SymbolId,
    fact: &CallableFact,
) -> Result<Option<&'static str>, String> {blocking_call_reason_using(tree,profile,source,expression,receiver,fact,&PrefixCompatibility::<String>::new())}
fn blocking_call_reason_using<D:PrefixDemand>(
    tree: &SemanticTree,
    profile: PackedU128,
    source: &str,
    expression: &Expr,
    receiver: SymbolId,
    fact: &CallableFact,
    demand:&D,
) -> Result<Option<&'static str>, String> {
    blocking_call_reason_source_using(tree,profile,CodeSource::issued(source),expression,receiver,fact,demand)
}
fn blocking_call_reason_source_using<D:PrefixDemand>(
    tree: &SemanticTree,
    profile: PackedU128,
    source: CodeSource<'_>,
    expression: &Expr,
    receiver: SymbolId,
    fact: &CallableFact,
    demand:&D,
) -> Result<Option<&'static str>, String> {
    demand.validate_profile(tree,profile)
        .map_err(|e| format!("blocking call profile: {e:?}"))?;
    let (identity_name, source_callable) = match fact {
        CallableFact::Source { identity, .. } => (identity.name, true),
        CallableFact::CheckerBuiltin { name, .. } => (*name, false),
        CallableFact::Missing => return Ok(None),
    };
    // Pinned check_operator_overload and visit_new call visit_call directly;
    // neither adds an unscoped direct blocker. Their real call edge remains in
    // the SAME plan, so a sleeping overload/New still propagates normally.
    if let Some(form) =
        dm_syntax::native_special_forms::constructor(expression).map_err(str::to_owned)?
    {
        if matches!(form, dm_syntax::native_special_forms::Constructor::Dynamic)
            || identity_name != SymbolId::of("New")
        {
            return Err("blocking constructor differs from original callable grammar".into());
        }
        return Ok(None);
    }
    if let ExprKind::Unary { op, value } = &expression.kind {
        if matches!(op.as_str(), "pre++" | "post++" | "pre--" | "post--") {
            increment_origin_source(source, expression, value, op)?;
            let operator = if op.ends_with("++") {
                "operator++"
            } else {
                "operator--"
            };
            if identity_name != SymbolId::of(operator) {
                return Err("blocking overload differs from original operator grammar".into());
            }
            return Ok(None);
        }
    }
    let ExprKind::Call { callee, .. } = &expression.kind else {
        return Err("blocking call lacks original call grammar".into());
    };
    // Term::GlobalCall intentionally does NOT record an unscoped blocker in
    // the old checker. Only the actual primary Ident call shape does so.
    if let ExprKind::Ident(name) = &callee.kind {
        // Self and parent calls already contributed their exact selected edge.
        // The Original checker never adds an unscoped blocker for either term.
        if matches!(name.as_str(), "." | "..") {
            return Ok(None);
        }
        if identity_name != SymbolId::of(name) {
            return Err("blocking name differs from original callable identity".into());
        }
        if let Some(reason) = ["sleep", "alert", "shell", "winexists", "winget"]
            .into_iter()
            .find(|n| *n == name)
        {
            if source_callable || certified_builtin_effect_contract(tree, profile, fact)? {
                return Ok(Some(reason));
            }
        }
    }
    // Source implementations on these exact static receiver types are real
    // graph edges. Virtual builtin implementations remain unsupported until
    // the original override-closure provider is available; never pure-clean.
    let names = if receiver == SymbolId::of("/client") {
        Some([
            ("SoundQuery", "client.SoundQuery"),
            ("MeasureText", "client.MeasureText"),
        ])
    } else if receiver == SymbolId::of("/world") {
        Some([("Import", "world.Import"), ("Export", "world.Export")])
    } else {
        None
    };
    if let Some(names) = names {
        for (name, reason) in names {
            if identity_name == SymbolId::of(name) {
                if !source_callable && !certified_builtin_effect_contract(tree, profile, fact)? {
                    return Err("blocking builtin contract unavailable".into());
                }
                return Ok(Some(reason));
            }
        }
    }
    Ok(None)
}

/// One evaluated call walk, with the original private/protected checks at its
/// existing before-argument transition. No second call or statement traversal.
pub(crate) fn procedure_visibility_archived<'a>(archive:&'a BodyArchive,body:&'a ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,family:crate::checks_proc_visibility::Family,severity:crate::checks::Severity,checkpoint:&dyn Fn()->std::io::Result<()>)->Result<Vec<crate::checks_proc_visibility::Row<'a>>,crate::policy_body_demand::PolicyFailure>{
 if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("procedure visibility body is foreign or incomplete".into())}
 let demand=crate::checker_prefix_demand::Policy{checkpoint};let mut walker=Walker::new_using(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand)?;
 walker.access=Some(crate::checks_proc_visibility::Access::new(archive,body,family,severity)?);crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;walker.access.take().expect("issued procedure visibility policy").finish(resolver,profile,&walker.prefix_demand)
}

/// Whole-frame keyword folding borrows this exact evaluated visitor; no events
/// or per-body keyword findings are published or cached.
pub(crate) fn keyword_calls_archived(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&dyn Fn()->std::io::Result<()>,observer:&mut dyn KeywordObserver<crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{
 if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("keyword call body is foreign or incomplete".into())}
 let demand=crate::checker_prefix_demand::Policy{checkpoint};
 let mut walker=Walker::new_using(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand)?;
 walker.access=Some(crate::checks_proc_visibility::Access::for_keyword_calls(archive,body)?);walker.keywords=Some(observer);
 crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(())
}

/// Untagged call diagnostics share the original evaluated pre-RHS seam.
pub(crate) fn call_arguments_archived(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&dyn Fn()->std::io::Result<()>,observer:&mut dyn ArgumentObserver<crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{
 if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("argument call body is foreign or incomplete".into())}
 let demand=crate::checker_prefix_demand::Policy{checkpoint};let mut walker=Walker::new_using(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand)?;
 walker.access=Some(crate::checks_proc_visibility::Access::for_keyword_calls(archive,body)?);walker.original_values=observer.original_values();walker.argument_errors=Some(observer);crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(())
}

fn original_argument_key<'a,E:From<String>+for<'s>From<&'s str>>(key:&'a Expr,reserve:&mut impl FnMut(usize)->Result<(),E>,resource:&impl Fn(&'static str)->E)->Result<Cow<'a,str>,E>{match &key.kind{ExprKind::Ident(name)=>Ok(Cow::Borrowed(name)),ExprKind::Literal(value)=>{let width=match value.original_value(){Some(dm_syntax::OriginalTokenValue::String(text))=>text.len(),Some(_)=>return Err("original keyword VALUE is not text".into()),None=>value.as_str().len()};let bound=width.checked_mul(4).ok_or("original keyword capacity overflow")?;reserve(bound.checked_add(std::mem::size_of::<String>()+128).ok_or("original keyword capacity overflow")?)?;let mut text=String::new();text.try_reserve_exact(width).map_err(|_|resource("original keyword allocation refused"))?;if text.capacity()>bound{return Err(resource("original keyword capacity exceeded"))}struct Fixed<'a>(&'a mut String);impl std::fmt::Write for Fixed<'_>{fn write_str(&mut self,text:&str)->std::fmt::Result{if text.len()>self.0.capacity()-self.0.len(){return Err(std::fmt::Error)}self.0.push_str(text);Ok(())}}if !value.write_pinned_static_text(&mut Fixed(&mut text)).map_err(|error|format!("original argument keyword text: {error:?}"))?{return Err("original keyword is not static text".into())}Ok(Cow::Owned(text))},_=>Err("original argument key is outside the issued keyword grammar".into())}}

/// Fixed original catch Warning uses this SAME evaluated/ordered catch scope.
pub(crate) fn catch_parameters_archived(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&dyn Fn()->std::io::Result<()>,observer:&mut dyn CatchObserver<crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{
 if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("catch policy body is foreign or incomplete".into())}let demand=crate::checker_prefix_demand::Policy{checkpoint};let mut walker=Walker::new_using(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand)?;walker.access=Some(crate::checks_proc_visibility::Access::for_keyword_calls(archive,body)?);walker.catch_errors=Some(observer);crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(())
}

/// Static-reference diagnostics use the same ordered evaluator and value facts.
pub(crate) fn static_references_archived(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&dyn Fn()->std::io::Result<()>,observer:&mut dyn StaticObserver<crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("static policy body is foreign or incomplete".into())}let demand=crate::checker_prefix_demand::Policy{checkpoint};let mut walker=Walker::new_using(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand)?;walker.access=Some(crate::checks_proc_visibility::Access::for_keyword_calls(archive,body)?);walker.original_values=true;walker.static_errors=Some(observer);crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(())}

/// Validate the already-parsed prefix span; never lex or parse a new node.
fn prefix_origin(source:&str,expression:&Expr,operand:&Expr,op:&str)->Result<Span,String>{prefix_origin_source(CodeSource::issued(source),expression,operand,op)}
fn prefix_origin_source(source:CodeSource<'_>,expression:&Expr,operand:&Expr,op:&str)->Result<Span,String>{
 if expression.span.end!=operand.span.end||op.len()!=1&&op!="::"{return Err("prefix operand extent differs from primary expression".into())}let start=expression.span.start;let end=start.checked_add(op.len()).ok_or("prefix origin overflow")?;if source.get(start..end)!=Some(op)||source.get(end..operand.span.start).is_none_or(|gap|!gap.chars().all(char::is_whitespace)){return Err("prefix needs retained primary operator origin".into())}Ok(Span::new(start,end))
}

/// Type/range diagnostics borrow the same evaluator and exact control traversal.
pub(crate) fn iteration_ranges_archived(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&dyn Fn()->std::io::Result<()>,observer:&mut dyn IterationObserver<crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("iteration body is foreign or incomplete".into())}let demand=crate::checker_prefix_demand::Policy{checkpoint};let mut walker=Walker::new_using(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand)?;walker.access=Some(crate::checks_proc_visibility::Access::for_keyword_calls(archive,body)?);walker.original_values=true;walker.iteration_errors=Some(observer);crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(())}

pub(crate) fn undefined_types_archived(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&dyn Fn()->std::io::Result<()>,observer:&mut dyn TypeIssueObserver<crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("type diagnostic body is foreign or incomplete".into())}let demand=crate::checker_prefix_demand::Policy{checkpoint};let mut walker=Walker::new_using_with_type_issues(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand,Some(observer))?;walker.access=Some(crate::checks_proc_visibility::Access::for_keyword_calls(archive,body)?);walker.original_values=true;crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(())}

pub(crate) fn switch_cases_archived(archive:&BodyArchive,body:&ArchivedBody<'_>,resolver:&(impl Resolver+?Sized),profile:PackedU128,checkpoint:&dyn Fn()->std::io::Result<()>,observer:&mut dyn CaseObserver<crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{if !body.belongs_to(archive)||!body.statement_body().original_literal_syntax_complete(){return Err("switch body is foreign or incomplete".into())}let demand=crate::checker_prefix_demand::Policy{checkpoint};let mut walker=Walker::new_using(archive.tree(),Some(archive),&body.statement_body().parsed().local_variables,archive.expanded_source(),body.occurrence(),body.checker_parameters(profile)?,resolver,profile,None,demand)?;walker.access=Some(crate::checks_proc_visibility::Access::for_keyword_calls(archive,body)?);walker.original_values=true;walker.case_errors=Some(observer);crate::checker_reachable::archived_original_syntax_with_observer_using(body,&mut walker)?;walker.check_effect_admission()?;Ok(())}

#[cfg(test)]mod declared_type_answer_domain_tests{
 use super::*;
 fn source_tree(extra:Option<&str>)->std::sync::Arc<SemanticTree>{let original=dm_tree::checker_builtins::original_analysis_seed().unwrap();let mut seed=original.frontend_seed().clone();if let Some(path)=extra{seed.symbols.intern(path).unwrap();seed.hierarchy.parents.push((SymbolId::of(path),Some(SymbolId::of("/datum"))));let mut identity=xxhash_rust::xxh3::Xxh3::new();identity.update(b"actual-declared-type-engine-hierarchy-control-v1");identity.update(&seed.identity.to_le_bytes());identity.update(path.as_bytes());seed.identity=identity.digest128();seed.hierarchy.schema=seed.identity;}let ast=dm_syntax::parse("/proc/probe()\n    return null\n");dm_tree::from_ast(&ast,seed.symbols.clone(),dm_ir::FileId(0),0,0).unwrap().finish_with_engine(Some(&seed)).unwrap().tree}
 struct Wrong<'a>{tree:&'a SemanticTree,query:Q}impl Resolver for Wrong<'_>{fn source_owner(&self)->Option<*const ()>{Some(std::ptr::from_ref(self.tree).cast())}fn resolve(&self,query:Q)->M{if query==self.query{M::Presence(false)}else{Resolver::resolve(self.tree,query)}}}
 #[test]fn actual_checker_absence_preserves_incomplete_and_engine_only_native_type_answers(){for(extra,path,present)in[(None,"/missing",false),(Some("/datum/runtime_only_declared"),"/datum/runtime_only_declared",true)]{let tree=source_tree(extra);let profile=tree.checker_builtin_profile().unwrap();assert!(!tree.checker_source_type_presence(profile,path).unwrap());let query=Q::Type(SymbolId::of(path));assert_eq!(tree.lookup_type(SymbolId::of(path)).is_some(),present);let expected=Resolver::resolve(tree.as_ref(),query);if present{assert_eq!(expected,M::Symbol(SymbolId::of(path)));}else{assert!(!tree.intrinsic_inventory_complete());assert_eq!(expected,M::Unsupported(query));}let mut emitted=Vec::new();let got=checked_parameter_type_using(tree.as_ref(),tree.as_ref(),profile,Some(path),&mut|name|{emitted.push(name.to_owned());Ok::<(),String>(())},&mut||Ok::<(),String>(())).unwrap();assert_eq!(got,TypeFact::Unknown);assert_eq!(emitted,[path]);assert_eq!(Resolver::resolve(tree.as_ref(),query),expected,"diagnostic projection cannot change runtime/native meaning");let strict=checked_parameter_type_using(tree.as_ref(),tree.as_ref(),profile,Some(path),&mut|_|Err::<(),String>("strict parameter still refuses absent checker type".into()),&mut||Ok::<(),String>(())).unwrap_err();assert!(strict.contains("strict parameter still refuses"));let mut called=false;let error=checked_parameter_type_using(tree.as_ref(),&Wrong{tree:tree.as_ref(),query},profile,Some(path),&mut|_|{called=true;Ok::<(),String>(())},&mut||Ok::<(),String>(())).unwrap_err();assert!(error.contains("contradicts actual current resolver"));assert!(!called);}}
}
