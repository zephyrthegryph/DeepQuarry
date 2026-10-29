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
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TypeFact {
    Known(SymbolId),
    List(Option<SymbolId>),
    Unknown,
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
            Self::Unknown => Ok(None),
            Self::Deferred(reason) => Err(reason.into()),
        }
    }
}
#[derive(Clone, Debug)]
pub enum Event<'a> {
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
        &frontend.expanded.text,
        body.occurrence().member,
        resolver,
        profile,
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
        &frontend.expanded.text,
        body.occurrence().member,
        resolver,
        profile,
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
        archive.expanded_source(),
        body.occurrence().member,
        resolver,
        profile,
    )?;
    crate::checker_reachable::archived_with_observer(body, &mut walker)?;
    Ok(Walk {
        events: walker.events,
    })
}
struct Walker<'a, 'r, R: ?Sized> {
    tree: &'a SemanticTree,
    source: &'a str,
    member: MemberId,
    resolver: &'r R,
    profile: PackedU128,
    owner: SymbolId,
    locals: BTreeMap<SymbolId, TypeFact>,
    events: Vec<Event<'a>>,
    scopes: Vec<BTreeMap<SymbolId, TypeFact>>,
}
impl<'a, 'r, R: Resolver + ?Sized> Walker<'a, 'r, R> {
    fn new(
        tree: &'a SemanticTree,
        source: &'a str,
        member: MemberId,
        resolver: &'r R,
        profile: PackedU128,
    ) -> Result<Self, String> {
        let node = tree
            .member(member)
            .ok_or("missing issued callable member")?;
        let owner = tree
            .type_node(node.owner)
            .ok_or("missing issued callable owner")?
            .path;
        let metadata = node
            .metadata
            .procedure
            .as_ref()
            .ok_or("missing issued procedure signature")?;
        let mut locals = BTreeMap::new();
        for (name, ty) in [
            (".", TypeFact::Unknown),
            ("args", TypeFact::List(None)),
            ("usr", TypeFact::Known(SymbolId::of("/mob"))),
            ("callee", TypeFact::Known(SymbolId::of("/callee"))),
            ("caller", TypeFact::Known(SymbolId::of("/callee"))),
            ("global", TypeFact::Known(SymbolId::of("/"))),
        ] {
            locals.insert(SymbolId::of(name), ty);
        }
        if owner != SymbolId::of("/") {
            locals.insert(SymbolId::of("src"), TypeFact::Known(owner));
        }
        for parameter in metadata.signature.parameters.iter() {
            if parameter.array.is_some() {
                return Err(
                    "checker parameter array context needs issued pinned projection".into(),
                );
            }
            locals.insert(
                parameter.name,
                checked_type(
                    tree,
                    resolver,
                    parameter.declared_type,
                    parameter.list_element_type,
                )?,
            );
        }
        Ok(Walker {
            tree,
            source,
            member,
            resolver,
            profile,
            owner,
            locals,
            events: Vec::new(),
            scopes: Vec::new(),
        })
    }
    fn leaf_statement(&mut self, statement: &'a Statement) -> Result<bool, String> {
        match &statement.kind {
            StatementKind::Set { .. } => (),
            StatementKind::Var { declaration, value } => {
                self.declaration(declaration, value.as_ref())?
            }
            StatementKind::Assign { target, value, .. } => {
                let hint = self.expression(target, None)?.receiver()?;
                self.expression(value, hint)?;
            }
            StatementKind::Expression(value) | StatementKind::Call(value) => {
                if let ExprKind::Binary { op, lhs, .. } = &value.kind {
                    if op == "<<" {
                        self.expression(lhs, None)?;
                    }
                }
                self.expression(value, None)?;
                if matches!(&value.kind,ExprKind::Call {callee,..} if matches!(&callee.kind,ExprKind::Ident(name) if name=="CRASH"))
                {
                    return Ok(true);
                }
            }
            StatementKind::Return(value) => {
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
    fn declaration(&mut self, declaration: &'a str, value: Option<&'a Expr>) -> Result<(), String> {
        let projection =
            dm_syntax::project_local_declaration(declaration).map_err(str::to_owned)?;
        let ty = if let Some(declared) = projection.declared_type {
            checked_type(
                self.tree,
                self.resolver,
                Some(SymbolId::of(&format!(
                    "/{}",
                    declared.runtime_path.trim_start_matches('/')
                ))),
                declared
                    .list_element_path
                    .map(|path| SymbolId::of(&format!("/{}", path.trim_start_matches('/')))),
            )?
        } else {
            TypeFact::Unknown
        };
        // Pinned visit_var supplies the declaration hint to the initializer,
        // then discards initializer inference in favor of its declared type.
        if let Some(value) = value {
            self.expression(value, ty.receiver()?)?;
        }
        self.locals.insert(SymbolId::of(projection.name), ty);
        Ok(())
    }
    fn variable_type(
        &self,
        fact: &crate::checker_variable_facts::VariableFact,
    ) -> Result<TypeFact, String> {
        if fact.metadata.flags & !15 != 0 || fact.metadata.array.is_some() {
            return Err("field modifiers/arrays need complete native declaration context".into());
        }
        checked_type(
            self.tree,
            self.resolver,
            fact.metadata.declared_type,
            fact.metadata.list_element_type,
        )
    }
    fn arguments(&mut self, args: &'a [Expr]) -> Result<(), String> {
        for argument in args {
            let value = match &argument.kind {
                ExprKind::Binary { op, lhs, rhs } if op == "=" && kwarg_key(lhs)? => rhs.as_ref(),
                _ => argument,
            };
            self.expression(value, None)?;
        }
        Ok(())
    }
    fn ordinary_call(
        &mut self,
        expression: &'a Expr,
        at: Span,
        name: &'a str,
        receiver: SymbolId,
        args: &'a [Expr],
        member_follow: bool,
    ) -> Result<TypeFact, String> {
        let fact = checker_call_facts::callable_any(
            self.tree,
            self.resolver,
            self.profile,
            receiver,
            SymbolId::of(name),
        )?;
        if matches!(fact, CallableFact::Missing) {
            self.events.push(Event::MissingCall {
                expression,
                at,
                name,
                receiver,
            });
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
                            let M::Declaration { data, .. } = row else {
                                return Err("member-call directive chain malformed".into());
                            };
                            if data
                                .procedure
                                .as_ref()
                                .is_some_and(|p| !p.settings.is_empty())
                            {
                                return Err(
                                    "inherited member-call directive context not yet evaluated"
                                        .into(),
                                );
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
            if !metadata.settings.is_empty() || metadata.signature.return_annotation.is_some() {
                return Err(
                    "checker callable directives/return type context is not yet evaluated".into(),
                );
            }
        }
        let returned = match &fact {
            CallableFact::Source { .. } => TypeFact::Unknown,
            _ => TypeFact::Deferred("fixed builtin return-type policy is not yet imported"),
        };
        self.events.push(Event::ResolvedCall {
            expression,
            at,
            name,
            fact,
        });
        self.arguments(args)?;
        Ok(returned)
    }
    fn expression(
        &mut self,
        expression: &'a Expr,
        hint: Option<SymbolId>,
    ) -> Result<TypeFact, String> {
        match &expression.kind {
            ExprKind::Ident(name) => {
                if let Some(ty) = self.locals.get(&SymbolId::of(name)) {
                    return Ok(*ty);
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
                    Some(fact) => self.variable_type(&fact),
                    None => {
                        self.events.push(Event::MissingVariable {
                            expression,
                            at: expression.span,
                            name,
                        });
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
                Ok(TypeFact::Unknown)
            }
            ExprKind::TypePath(_) => Ok(TypeFact::Unknown),
            ExprKind::Group(value) => self.expression(value, hint),
            ExprKind::Conditional {
                condition,
                then_value,
                else_value,
            } => {
                self.expression(condition, None)?;
                let first = self.expression(then_value, hint)?;
                self.expression(else_value, hint)?;
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
                let right =
                    self.expression(rhs, if op == "=" { left.receiver()? } else { None })?;
                if op == "=" {
                    return Ok(right);
                }
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
                ExprKind::Ident(name) if name == "new" => {
                    if hint.is_some() {
                        return Err("implicit new with hint needs constructor call context".into());
                    }
                    self.events
                        .push(Event::MissingImplicitNewHint { expression });
                    Ok(TypeFact::Unknown)
                }
                ExprKind::Ident(name) if name == ".." => {
                    let fact = checks_parent_call::parent_fact_in_profile(
                        self.tree,
                        self.member,
                        self.resolver,
                        Some(self.profile),
                    )?;
                    if !fact.has_parent {
                        self.events.push(Event::MissingParent {
                            expression,
                            at: callee.span,
                            display: fact.display,
                        });
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
                    self.arguments(args)?;
                    Ok(TypeFact::List(None))
                }
                ExprKind::Ident(name) if name == "CRASH" => {
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
                            | "locate"
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
                        self.events.push(Event::DynamicMemberCall {
                            expression,
                            at,
                            name: selector,
                        });
                        self.arguments(args)?;
                        return Ok(TypeFact::Unknown);
                    }
                    let Some(receiver) = base.receiver()? else {
                        self.events.push(Event::UnknownReceiverCall {
                            expression,
                            at,
                            name: selector,
                        });
                        return Ok(TypeFact::Unknown);
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
                if *via_colon {
                    return Ok(TypeFact::Unknown);
                }
                let Some(receiver) = base.receiver()? else {
                    return Err(
                        "unknown-receiver field access needs pinned fix-hint/declaration origins"
                            .into(),
                    );
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
                    Some(fact) => self.variable_type(&fact),
                    None => {
                        self.events.push(Event::MissingField {
                            expression,
                            at,
                            name: selector,
                            receiver,
                        });
                        Ok(TypeFact::Unknown)
                    }
                }
            }
            ExprKind::Index { object, index } | ExprKind::SafeIndex { object, index } => {
                let base = self.expression(object, None)?;
                self.expression(index, None)?;
                match base {
                    TypeFact::List(element) => {
                        checked_type(self.tree, self.resolver, element, None)
                    }
                    other => Ok(other),
                }
            }
            ExprKind::Unary { op, value } if op == "new" || op == "new()" => {
                if op == "new()" {
                    if hint.is_some() {
                        return Err("implicit new with hint needs constructor call context".into());
                    }
                    self.events
                        .push(Event::MissingImplicitNewHint { expression });
                    return Ok(TypeFact::Unknown);
                }
                let target = match &value.kind {
                    ExprKind::Call { callee, .. } => callee.as_ref(),
                    _ => value.as_ref(),
                };
                match &target.kind {
                    // Pinned NewMiniExpr is TODO and visits neither target nor args.
                    ExprKind::Ident(_) | ExprKind::Member { .. } => Ok(TypeFact::Unknown),
                    _ => {
                        Err("static constructor needs pinned New call/type/argument context".into())
                    }
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
impl<'a, R: Resolver + ?Sized> EvaluatedObserver<'a> for Walker<'a, '_, R> {
    fn enter_scope(&mut self, _: ScopeKind) {
        self.scopes.push(self.locals.clone());
    }
    fn leave_scope(&mut self, _: ScopeKind) {
        self.locals = self.scopes.pop().expect("paired pinned traversal scope");
    }
    fn leaf(&mut self, statement: &'a Statement) -> Result<(), String> {
        self.leaf_statement(statement).map(|_| ())
    }
    fn expression(&mut self, expression: &'a Expr) -> Result<(), String> {
        Walker::expression(self, expression, None).map(|_| ())
    }
    fn statement_expression(&mut self, expression: &'a Expr) -> Result<(), String> {
        if let ExprKind::Binary { op, lhs, .. } = &expression.kind {
            if op == "<<" {
                Walker::expression(self, lhs, None)?;
            }
        }
        Walker::expression(self, expression, None).map(|_| ())
    }
    fn initializer(&mut self, initializer: &'a ForInitializer, at: Span) -> Result<(), String> {
        match initializer {
            ForInitializer::Declare { declaration, value } => {
                self.binding(declaration, value.as_ref(), false, at)
            }
            ForInitializer::Expr(value) => self.statement_expression(value),
        }
    }
    fn binding(
        &mut self,
        binding: &'a str,
        value: Option<&'a Expr>,
        always_untyped: bool,
        _: Span,
    ) -> Result<(), String> {
        if dm_syntax::local_name(binding).is_some() {
            return self.declaration(binding, value);
        }
        if always_untyped {
            if binding.is_empty() || !binding.chars().all(|c| c.is_alphanumeric() || c == '_') {
                return Err("pair/catch binding lacks native simple-name projection".into());
            }
            if let Some(value) = value {
                Walker::expression(self, value, None)?;
            }
            self.locals.insert(SymbolId::of(binding), TypeFact::Unknown);
        }
        // Existing (nondeclared) range bindings deliberately skip their start.
        Ok(())
    }
    fn catch_binding(&mut self, binding: Option<&'a str>, at: Span) -> Result<(), String> {
        if let Some(binding) = binding {
            self.binding(binding, None, true, at)?;
        }
        Ok(())
    }
}
fn checked_type(
    tree: &SemanticTree,
    resolver: &(impl Resolver + ?Sized),
    owner: Option<SymbolId>,
    element: Option<SymbolId>,
) -> Result<TypeFact, String> {
    for ty in owner.into_iter().chain(element) {
        let spelling = tree
            .symbols()
            .text(ty)
            .ok_or("declared type lacks native symbol spelling")?;
        if spelling.split('/').any(|part| {
            matches!(
                part,
                "final" | "SpacemanDMM_final" | "SpacemanDMM_private" | "SpacemanDMM_protected"
            )
        }) {
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
