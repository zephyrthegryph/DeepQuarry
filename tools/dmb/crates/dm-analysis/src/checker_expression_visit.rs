//! Pinned evaluated-expression events, initial linear/ordinary-call cohort.
//!
//! Adapted from SpacemanDMM 0290db5c752fa292f9824521515b603a2afd11dc
//! dreamchecker visit_statement/visit_expression/visit_term/visit_call (GPL-3.0).
//! This borrows primary syntax and native semantic facts. It never reparses DM.
//! Unsupported evaluation/origin contexts abort the entire event contribution.
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
use std::collections::BTreeMap;
use crate::checker_prefix_demand::{Demand as PrefixDemand,Compatibility as PrefixCompatibility};
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TypeFact {
    Known(SymbolId),
    List(Option<SymbolId>),
    Unknown,
    Unhinted,
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
            Self::List(_) => Ok(Some(SymbolId::of("/list"))),
            Self::Unknown | Self::Unhinted | Self::ReturnHint(..) => Ok(None),
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
/// Checker facts for an existing native local binding, not another model.
/// The proof is intentionally narrow: authored null/literal initialization,
/// with no later reassignment, argument escape, or unsupported initializer.
#[derive(Clone, Copy, Debug)]
struct LocalFact {
    ty: TypeFact,
    declaration: Option<Span>,
    mutation_pure: bool,
    impurity: Option<bool>,
}
impl LocalFact {
    fn unproved(ty: TypeFact) -> Self {
        Self {
            ty,
            declaration: None,
            mutation_pure: false,
            impurity: None,
        }
    }
}
struct Walker<'a, 'r, R: ?Sized,D=PrefixCompatibility> {
    prefix_demand:D,
    tree: &'a SemanticTree,
    prefix_archive: Option<&'a BodyArchive>,
    local_syntax: &'a dm_syntax::LocalVariableLedger,
    source: &'a str,
    member: MemberId,
    resolver: &'r R,
    profile: PackedU128,
    owner: SymbolId,
    locals: BTreeMap<SymbolId, LocalFact>,
    events: Vec<Event<'a>>,
    scopes: Vec<BTreeMap<SymbolId, LocalFact>>,
    in_arguments: bool,
    effects: Option<crate::checker_effects::Draft>,
    last_impurity: Option<bool>,
    new_context: usize,
    evaluation_anchor: Option<crate::checker_effects::CallOrigin>,
    statement_root: Option<&'a Expr>,
    scope_denied_depth: usize,
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
        if let Some(budget) = budget {
            budget.charge(Self::local_map_bound(entries.len().saturating_add(7)))?;
        }
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
            }
            let path = parameters.type_path(parameter)?;
            let ty = checked_parameter_type(tree, resolver, profile, path.as_deref())?;
            let mut fact = LocalFact::unproved(ty);
            fact.impurity = Some(true); // Pinned checker: every parameter is impure.
            locals.insert(SymbolId::of(parameters.name(parameter)?), fact);
        }
        Ok(Walker {
            prefix_demand,
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
            new_context: 0,
            evaluation_anchor: None,
            statement_root: None,
            scope_denied_depth: 0,
        })
    }
    fn local_entry_bound() -> usize {
        1024usize.saturating_add(std::mem::size_of::<(SymbolId, LocalFact)>().saturating_mul(2))
    }
    fn local_map_bound(entries: usize) -> usize {
        entries
            .saturating_mul(Self::local_entry_bound())
            .saturating_add(std::mem::size_of::<BTreeMap<SymbolId, LocalFact>>())
            .saturating_add(64)
    }
    fn check_effect_admission(&self) -> Result<(), D::Error> {
        if let Some(effects) = &self.effects {
            effects.transient.charge(0)?
        }
        Ok(())
    }
    fn insert_local(&mut self, name: SymbolId, fact: LocalFact) -> Result<(), D::Error> {
        if let Some(effects) = &self.effects {
            effects.transient.charge(Self::local_entry_bound())?
        }
        self.locals.insert(name, fact);
        Ok(())
    }
    fn event(&mut self, event: Event<'a>) -> Result<(), D::Error> {
        if let Some(effects) = &self.effects {
            effects.transient.push(&mut self.events, event)?
        } else {
            self.events.push(event)
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
        let result = self.leaf_statement_inner(statement);
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
                    && (matches!(&value.kind,ExprKind::Literal(n)if n=="0")
                        || matches!(&value.kind,ExprKind::Ident(n)if n=="FALSE"))
                {
                    effects.waitfor_disabled = true;
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
                self.statement_expression(value)?;
                if matches!(&value.kind,ExprKind::Call{callee,..}if matches!(&callee.kind,ExprKind::Ident(name)if name=="CRASH"))
                {
                    return Ok(true);
                }
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
                    self.expression(value, None)?;
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
        let source_type = fact.type_path(self.source).map_err(str::to_owned)?;
        let ty = checked_parameter_type(
            self.tree,
            self.resolver,
            self.profile,
            source_type.as_deref(),
        )?;
        if let Some(value) = value {
            self.expression(value, ty.receiver()?)?;
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
                declaration: Some(fact.name),
                mutation_pure: literal_mutation_origin(value)?,
                impurity,
            },
        )?;
        Ok(())
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
                let properties = archive.checker_variable_properties(formal, self.profile)?;
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
    fn arguments(&mut self, args: &'a [Expr]) -> Result<(), D::Error> {
        for argument in args {
            let value = match &argument.kind {
                ExprKind::Binary { op, lhs, rhs } if op == "=" && kwarg_key(lhs)? => rhs.as_ref(),
                _ => argument,
            };
            let previous = self.in_arguments;
            self.in_arguments = true;
            let result = self.expression(value, None);
            self.in_arguments = previous;
            result?;
        }
        Ok(())
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
        if effects.direct.len() >= crate::checker_effects::MAX_EVENTS {
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
            if effects.immediate.len() >= crate::checker_effects::MAX_EVENTS {
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
            effects.transient.push(
                &mut effects.immediate,
                crate::checks::Diagnostic {
                    family,
                    severity,
                    span: at,
                    expression_span: at,
                    message,
                    notes,
                },
            )?;
        }
        Ok(())
    }
    fn arguments_at(&mut self, args: &'a [Expr], at: Span) -> Result<(), D::Error> {
        let previous = self
            .evaluation_anchor
            .replace(crate::checker_effects::CallOrigin::Source(at));
        let result = self.arguments(args);
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
        let fact = checker_call_facts::callable_any(
            self.tree,
            self.resolver,
            self.profile,
            receiver,
            SymbolId::of(name),
        )?;
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
        if member_follow {
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
                                            *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?;
                                    crate::checker_return_facts::validate_source_directives_for_purity_using(self.tree,self.prefix_archive,*identity,&permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?;
                                } else {
                                    crate::checker_return_facts::validate_source_directives_using(
                                        self.tree,
                                        self.prefix_archive,
                                        *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?;
                                }
                            }
                        }
                    }
                    M::Missing => (),
                    _ => return Err("member-call directive source presence is unsupported".into()),
                }
            }
        }
        if let Some(metadata) = fact.metadata() {
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
                        *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?;
                    crate::checker_return_facts::validate_source_directives_for_purity_using(
                        self.tree,
                        self.prefix_archive,
                        *identity,
                        &permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?;
                } else {
                    crate::checker_return_facts::validate_source_directives_using(
                        self.tree,
                        self.prefix_archive,
                        *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?;
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
                        target, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?;
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
            if effects.calls.len() >= crate::checker_effects::MAX_EVENTS {
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
                    if let Some(reason) = blocking_call_reason_using(
                        self.tree,
                        self.profile,
                        self.source,
                        expression,
                        receiver,
                        &fact,
                        &self.prefix_demand,
                    )? {
                        let effects = self.effects.as_mut().unwrap();
                        if effects.blocking.len() >= crate::checker_effects::MAX_EVENTS {
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
        match site {
            EvaluationCallSite::Written(_) => self.arguments_at(args, at)?,
            EvaluationCallSite::ImplicitList(initializer) => {
                let saved = self.evaluation_anchor.replace(
                    crate::checker_effects::CallOrigin::ImplicitList(initializer.origin),
                );
                let result = self.arguments(args);
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
        let purity_permit =
            if self.effects.is_some() && matches!(&fact, CallableFact::Source { .. }) {
                let CallableFact::Source { identity, .. } = &fact else {
                    unreachable!()
                };
                Some(crate::checker_return_facts::PuritySettingsPermit::issue_using(
                    self.prefix_archive.unwrap(),
                    self.profile,
                    *identity, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?)
            } else {
                None
            };
        let returned = if let Some(permit) = &purity_permit {
            crate::checker_return_facts::return_hint_with_prefix_for_purity_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive,
                permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?
        } else {
            crate::checker_return_facts::return_hint_with_prefix_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?
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
        let hint = if let Some(permit) = &purity_permit {
            crate::checker_return_facts::return_fix_hint_for_purity_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive,
                permit, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?
        } else {
            crate::checker_return_facts::return_fix_hint_using(
                self.tree,
                self.resolver,
                self.profile,
                receiver,
                SymbolId::of(name),
                self.prefix_archive, &self.prefix_demand.with_budget(self.effects.as_ref().map(|effects|&effects.transient)))?
        };
        Ok(match hint {
            crate::checker_return_facts::ReturnFixHint::None => TypeFact::Unhinted,
            crate::checker_return_facts::ReturnFixHint::UnissuedBuiltin => TypeFact::Unknown,
            hint => TypeFact::ReturnHint(hint, at),
        })
    }
    fn implicit_list_constructor(
        &mut self,
        initializer: &'a dm_syntax::ImplicitListInitializer,
    ) -> Result<TypeFact, D::Error> {
        let owner = SymbolId::of("/list");
        let _ = checked_type(self.tree, self.resolver, Some(owner), None)?;
        let fact = checker_call_facts::callable_any(
            self.tree,
            self.resolver,
            self.profile,
            owner,
            SymbolId::of("New"),
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
                if !path.starts_with('/') {
                    return Err("relative constructor path needs primary navigation facts".into());
                }
                (SymbolId::of(path), args)
            }
        };
        let _ = checked_type(self.tree, self.resolver, Some(owner), None)?;
        let new = crate::checker_call_facts::callable_any(
            self.tree,
            self.resolver,
            self.profile,
            owner,
            SymbolId::of("New"),
        )?;
        if matches!(new, CallableFact::Missing) {
            if ["/list", "/alist", "/vector", "/pixloc"]
                .iter()
                .any(|name| owner == SymbolId::of(name))
            {
                return Ok(TypeFact::Unknown); // intentionally does NOT visit args
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
        let result = self.expression_inner(expression, hint)?;
        if self.effects.is_some() {
            if let TypeFact::Deferred(reason) = result {
                return Err(reason.into());
            }
        }
        Ok(result)
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
                if effects.blocking.len() >= crate::checker_effects::MAX_EVENTS {
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
                let result = self.expression(container, None);
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
                let result = self.expression(container, None);
                self.evaluation_anchor = old;
                result?;
            }
            // Pinned locate's IsType assumption (even its 3-argument form)
            // leaves Analysis.static_ty unset. Do not invent receiver typing.
            return Ok(TypeFact::Unhinted);
        }
        match &expression.kind {
            ExprKind::Ident(name) => {
                if let Some(local) = self.locals.get(&SymbolId::of(name)).copied() {
                    let ty = local.ty;
                    self.last_impurity = local.impurity;
                    if self.in_arguments {
                        self.invalidate_local_name(SymbolId::of(name));
                    }
                    return Ok(ty);
                }
                // Pinned `type` is a prefab/value fact, not a field declaration.
                if matches!(name.as_str(), "type" | "null") {
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
                        let ty = self.variable_type(&fact)?;
                        self.last_impurity = Some(true);
                        Ok(ty)
                    }
                    None => {
                        self.event(Event::MissingVariable {
                            expression,
                            at: expression.span,
                            name,
                        })?;
                        Ok(TypeFact::Unknown)
                    }
                }
            }
            ExprKind::Literal(text) => {
                if let Some(parts) = text.parts().map_err(str::to_owned)? {
                    parts
                        .lexical
                        .map_err(|e| format!("checker literal context unsupported: {e:?}"))?;
                    for child in &parts.expressions {
                        self.expression(child, None)?;
                    }
                }
                self.last_impurity = None;
                Ok(TypeFact::Unknown)
            }
            ExprKind::TypePath(_) => Ok(TypeFact::Unknown),
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
                let result = self.expression(value, hint);
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
                self.expression(else_value, hint)?;
                self.last_impurity = impurity;
                Ok(first)
            }
            ExprKind::Binary { op, lhs, rhs } => {
                if !matches!(
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
                        "compound/unsupported operator needs shared pinned assignment context"
                            .into(),
                    );
                }
                let left = self.expression(lhs, None)?;
                let left_impurity = self.last_impurity;
                if op == "=" && left_impurity == Some(true) {
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
                    self.expression(rhs, if op == "=" { left.receiver()? } else { None })?;
                if op == "=" {
                    self.invalidate_local_target(lhs);
                    return Ok(right);
                }
                // Pinned visit_binary retains a list STATIC TYPE, not the
                // lhs Analysis. Conversion from StaticType resets impurity.
                self.last_impurity = None;
                // Exact pinned visit_binary: only these LHS-list operations
                // retain a static list type. Every other binary is empty.
                Ok(
                    if matches!(left, TypeFact::List(_))
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
                    let fact = checks_parent_call::parent_fact_in_profile(
                        self.tree,
                        self.member,
                        self.resolver,
                        Some(self.profile),
                    )?;
                    if !fact.has_parent {
                        self.event(Event::MissingParent {
                            expression,
                            at: callee.span,
                            display: fact.display,
                        })?;
                        return Ok(TypeFact::Unknown);
                    }
                    self.arguments(args)?;
                    Ok(TypeFact::Deferred(
                        "parent return/directive context not yet projected",
                    ))
                }
                ExprKind::Ident(name) if name == "." => {
                    self.arguments(args)?;
                    Ok(TypeFact::Deferred(
                        "self-call return/directive context not yet projected",
                    ))
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
                    let at = member_origin(self.source, callee, object, selector, *via_colon)?;
                    if *via_colon {
                        self.event(Event::DynamicMemberCall {
                            expression,
                            at,
                            name: selector,
                        })?;
                        self.arguments_at(args, at)?;
                        self.last_impurity = None;
                        return Ok(TypeFact::Unknown);
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
                if *via_colon {
                    return Ok(TypeFact::Unknown);
                }
                let Some(receiver) = base.receiver()? else {
                    let hint=match base {
                        TypeFact::Unhinted=>None,
                        TypeFact::ReturnHint(hint,call)=>Some((hint,call)),
                        _=>return Err("unknown-receiver field access needs pinned fix-hint/declaration origins".into()),
                    };
                    let at = member_origin(self.source, expression, object, selector, false)?;
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
                if receiver == SymbolId::of("/callee") && selector == "proc" {
                    return Ok(TypeFact::Deferred(
                        "call-frame procpath field needs native procpath static context",
                    ));
                }
                let at = member_origin(self.source, expression, object, selector, false)?;
                match crate::checker_variable_facts::variable(
                    self.tree,
                    self.resolver,
                    self.profile,
                    receiver,
                    SymbolId::of(selector),
                )? {
                    Some(fact) => {
                        let ty = self.variable_type(&fact)?;
                        self.event(Event::ResolvedField {
                            expression,
                            at,
                            name: selector,
                            receiver,
                            fact,
                        })?;
                        Ok(ty)
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
                self.expression(index, None)?;
                self.last_impurity = if matches!(base, TypeFact::List(_)) {
                    None
                } else {
                    impurity
                };
                match base {
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
                let _at = increment_origin(self.source, expression, value, op)?;
                if self.effects.is_some() {
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
                        TypeFact::Unknown | TypeFact::Unhinted | TypeFact::ReturnHint(..) => {
                            Ok(TypeFact::Unhinted)
                        }
                        TypeFact::Known(owner) => {
                            match checker_call_facts::callable_any(
                                self.tree,
                                self.resolver,
                                self.profile,
                                owner,
                                SymbolId::of(operator),
                            )? {
                                CallableFact::Missing => {
                                    let name = self
                                        .tree
                                        .symbols()
                                        .text(owner)
                                        .ok_or("operator type spelling absent")?;
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
                        TypeFact::List(_) => {
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
            ExprKind::Unary { .. } => {
                Err("unary expression needs exact primary term-origin projection".into())
            }
            ExprKind::ObjectInitializer { object, .. }
                if matches!(object.kind, ExprKind::TypePath(_)) =>
            {
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
    fn admit_storage(&mut self, bytes: usize) -> Result<bool, D::Error> {
        if let Some(effects) = &self.effects {
            effects.transient.charge(bytes)?;
            Ok(true)
        } else {
            Ok(false)
        }
    }
    fn storage_allocation_failed(&mut self) {
        if let Some(effects) = &self.effects {
            effects.transient.deny()
        }
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
                let result = self.statement_expression(value);
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
    fn catch_binding(&mut self, binding: Option<&'a str>, at: Span) -> Result<(), D::Error> {
        if let Some(binding) = binding {
            if binding.trim().is_empty() {
                return Ok(());
            }
            let issued = self
                .local_syntax
                .entries()
                .map_err(str::to_owned)?
                .iter()
                .any(|fact| {
                    fact.source_kind == dm_syntax::LocalSourceKind::CatchBinding
                        && fact.anchor.start >= at.start
                        && fact.anchor.start < at.end
                });
            if issued {
                self.declaration(binding, None, at)?;
            } else {
                self.binding(binding, None, true, at)?;
            }
        }
        Ok(())
    }
}
/// Reuse the privately issued ORIGINAL parameter path, then authenticate every
/// resolved type against both the certified checker source roster and current
/// native resolver. Missing checker types require diagnostics not yet produced
/// by this family, so refuse the whole report instead of erasing the hint.
fn checked_parameter_type(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    path: Option<&str>,
) -> Result<TypeFact, String> {
    let Some(path) = path else {
        return Ok(TypeFact::Unknown);
    };
    let (owner, element) = if path == "/list" {
        ("/list", None)
    } else if let Some(element) = path.strip_prefix("/list/") {
        // Borrow the slash already present in the original projected String.
        let _ = element;
        ("/list", Some(&path[5..]))
    } else {
        (path, None)
    };
    for spelling in std::iter::once(owner).chain(element) {
        if !tree
            .checker_source_type_presence(profile, spelling)
            .map_err(|e| format!("parameter checker source type proof: {e:?}"))?
        {
            return Err("parameter checker type needs undefined-type diagnostic projection".into());
        }
        let id = SymbolId::of(spelling);
        let query = Q::Type(id);
        let expected = Resolver::resolve(tree, query);
        if expected != M::Symbol(id) || resolver.resolve(query) != expected {
            return Err("parameter checker type differs from current native resolver".into());
        }
    }
    if element.is_some_and(|v| v == "/list" || v.starts_with("/list/")) {
        return Err("nested-list parameter needs recursive native type projection".into());
    }
    Ok(TypeFact::declared(
        Some(SymbolId::of(owner)),
        element.map(SymbolId::of),
    ))
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
fn kwarg_key(expression: &Expr) -> Result<bool, String> {
    Ok(match &expression.kind {
        ExprKind::Ident(_) => true,
        ExprKind::Literal(text) => match text.parts().map_err(str::to_owned)? {
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
        at = crate::checker_effects::original_target_parent(archive, profile, resolver, target)?;
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
    let draft = crate::checker_effects::Draft {
        transient: crate::checker_effects::output::ReportBudget::for_operation(admission),
        ..Default::default()
    };
    let mut walker = Walker::new_using(
        archive.tree(),
        Some(archive),
        &body.statement_body().parsed().local_variables,
        archive.expanded_source(),
        body.occurrence(),
        body.checker_parameters(profile)?,
        resolver,
        profile,
        Some(&draft.transient),
        prefix_demand,
    )?;
    walker.effects = Some(draft);
    crate::checker_reachable::archived_with_observer_using(body, &mut walker)?;
    walker.check_effect_admission()?;
    Ok(walker.effects.take().unwrap())
}
/// Native primary literal shape only. No inferred alias purity or evaluation
/// of an initializer a second time. Unsupported forms stay unproved.
fn literal_mutation_origin(value: Option<&Expr>) -> Result<bool, String> {
    let Some(value) = value else { return Ok(true) };
    match &value.kind {
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
            increment_origin(source, expression, value, op)?;
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
