//! Current lexical visibility over the compiler's issued statement model.
//! Specialized expression lowering and nonlocal meanings remain explicit gaps.
use super::NoTypedModel;
use dm_syntax::{
    local_name, BindingId, Expr, ExprKind, ForControl, ForInitializer, LexicalScopes, NodeStep,
    ScopeError, Span, Statement, StatementKind, StatementMask, StatementView, TypedVisitor,
    VisitDecision,
};
use dm_tree::frontend::{BodyOccurrence, ColdFrontend, Diagnostic, ParsedBody};
use std::sync::Arc;

#[derive(Clone, Debug)]
pub struct LocalDeclaration {
    pub path: Vec<NodeStep>,
    pub header_span: Span,
}
#[derive(Clone, Debug)]
pub enum ReferenceBinding {
    Lexical(BindingId),
    /// Could be a stored local, instance field, builtin or global. No guess.
    RequiresSemanticResolver,
}
#[derive(Clone, Debug)]
pub struct IdentifierReference {
    pub name: Arc<str>,
    pub path: Vec<NodeStep>,
    pub span: Span,
    pub binding: ReferenceBinding,
    /// Iterator names currently have the complete header span; ordinary typed
    /// expressions have the exact expression span.
    pub site: ReferenceSite,
    pub access: ReferenceAccess,
}
pub use dm_syntax::ReferenceAccess;
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ReferenceSite {
    Expression,
    IteratorHeader,
}
#[derive(Clone, Debug)]
pub struct ModelGap {
    pub path: Vec<NodeStep>,
    pub span: Span,
    pub reason: &'static str,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SelectorKind {
    Field,
    StaticField,
    Procedure,
    NamedProcedure,
    GlobalField,
    GlobalProcedure,
}
#[derive(Clone, Debug)]
pub struct SelectorReference {
    pub selector: Arc<str>,
    pub path: Vec<NodeStep>,
    pub span: Span,
    pub receiver_path: Option<Vec<NodeStep>>,
    pub kind: SelectorKind,
}
pub struct LexicalBody<'a> {
    pub occurrence: &'a BodyOccurrence,
    pub scopes: LexicalScopes<LocalDeclaration>,
    pub references: Vec<IdentifierReference>,
    pub selectors: Vec<SelectorReference>,
    pub gaps: Vec<ModelGap>,
    pub diagnostics: &'a [dm_syntax::Diagnostic],
}
#[derive(Debug)]
pub enum BindingError {
    Issuance(Diagnostic),
    NoTypedModel(NoTypedModel),
    InvalidSignature,
}
#[path = "typed_body_lexical_jsonl.rs"]
pub mod jsonl;
impl std::fmt::Display for BindingError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Issuance(error) => f.write_str(&error.message),
            Self::NoTypedModel(error) => error.fmt(f),
            Self::InvalidSignature => {
                f.write_str("issued procedure has no complete argument model")
            }
        }
    }
}
impl std::error::Error for BindingError {}
#[cfg(test)]
#[path = "typed_body_lexical_tests.rs"]
mod tests;

/// Parameters come from the authenticated current declaration. A mask permits
/// exactly the same executable view as lowering; omitted nodes have no effects.
pub fn analyze<'a>(
    frontend: &'a ColdFrontend,
    body: &'a ParsedBody<'_>,
    mask: Option<&StatementMask>,
) -> Result<LexicalBody<'a>, BindingError> {
    frontend
        .validate_parsed_body(body, body.occurrence())
        .map_err(BindingError::Issuance)?;
    let model = body
        .statement_body()
        .ok_or(BindingError::NoTypedModel(NoTypedModel))?
        .parsed();
    let tree = &frontend.snapshot.tree;
    let member = tree
        .member(body.occurrence().member)
        .ok_or(BindingError::InvalidSignature)?;
    let procedure = member
        .metadata
        .procedure
        .as_ref()
        .ok_or(BindingError::InvalidSignature)?;
    let parameters = procedure
        .signature
        .parameters
        .iter()
        .map(|parameter| tree.symbols().text(parameter.name).map(Arc::<str>::from))
        .collect::<Option<Vec<_>>>()
        .ok_or(BindingError::InvalidSignature)?;
    let mut visitor = Binder {
        scopes: LexicalScopes::new(parameters),
        references: Vec::new(),
        selectors: Vec::new(),
        gaps: Vec::new(),
        statement_scopes: Vec::new(),
        expression_roles: Vec::new(),
        assignment_targets: Vec::new(),
    };
    visitor.scopes.enter_scope();
    let view = match mask {
        Some(mask) => StatementView::masked(&model.statements, mask),
        None => StatementView::all(&model.statements),
    };
    dm_syntax::visit_statement_view(view, &mut visitor);
    visitor
        .scopes
        .leave_scope()
        .expect("root analysis scope is balanced");
    Ok(LexicalBody {
        occurrence: body.occurrence(),
        scopes: visitor.scopes,
        references: visitor.references,
        selectors: visitor.selectors,
        gaps: visitor.gaps,
        diagnostics: &model.diagnostics,
    })
}
struct Binder {
    scopes: LexicalScopes<LocalDeclaration>,
    references: Vec<IdentifierReference>,
    selectors: Vec<SelectorReference>,
    gaps: Vec<ModelGap>,
    statement_scopes: Vec<bool>,
    expression_roles: Vec<ExpressionRole>,
    assignment_targets: Vec<Option<ReferenceAccess>>,
}
#[derive(Clone, Copy, Default)]
struct ExpressionRole {
    member_call: bool,
    named_arguments: bool,
    arglist_wrapper: bool,
    suppress_child_zero: bool,
    child_zero_access: Option<ReferenceAccess>,
}
impl Binder {
    fn gap(&mut self, path: &[NodeStep], span: Span, reason: &'static str) {
        self.gaps.push(ModelGap {
            path: path.to_vec(),
            span,
            reason,
        });
    }
    fn declare(&mut self, name: &str, node: &Statement, path: &[NodeStep]) {
        if let Err(ScopeError::DuplicateLocal(_)) = self.scopes.declare(
            name,
            LocalDeclaration {
                path: path.to_vec(),
                header_span: node.header_span,
            },
        ) {
            self.gap(path, node.header_span, "active local cannot be redeclared");
        }
    }
    fn declaration(&mut self, text: &str, node: &Statement, path: &[NodeStep]) {
        if let Some(name) = local_name(text) {
            self.declare(name, node, path);
        } else {
            self.gap(
                path,
                node.header_span,
                "declaration needs stored inventory or unsupported syntax",
            );
        }
        if text.contains('[') {
            self.gap(
                path,
                node.header_span,
                "array dimension expressions require compiler reference roles",
            );
        }
    }
    fn reference(
        &mut self,
        name: &str,
        span: Span,
        path: &[NodeStep],
        site: ReferenceSite,
        access: ReferenceAccess,
    ) {
        let binding = self.scopes.resolve(name).map_or(
            ReferenceBinding::RequiresSemanticResolver,
            ReferenceBinding::Lexical,
        );
        self.references.push(IdentifierReference {
            name: Arc::from(name),
            path: path.to_vec(),
            span,
            binding,
            site,
            access,
        });
    }
    fn iterator(&mut self, text: &str, node: &Statement, path: &[NodeStep]) {
        if let Some(name) = local_name(text) {
            self.declare(name, node, path);
        } else {
            self.reference(
                text,
                node.header_span,
                path,
                ReferenceSite::IteratorHeader,
                ReferenceAccess::ReadWrite,
            );
        }
    }
}
impl TypedVisitor for Binder {
    fn statement(&mut self, node: &Statement, path: &[NodeStep]) -> VisitDecision {
        let scoped = matches!(
            &node.kind,
            StatementKind::For { .. } | StatementKind::Try { .. }
        );
        if scoped {
            self.scopes.enter_scope();
        }
        self.statement_scopes.push(scoped);
        self.assignment_targets.push(match &node.kind {
            StatementKind::Assign { op, .. } => Some(if op == "=" {
                ReferenceAccess::Write
            } else {
                ReferenceAccess::ReadWrite
            }),
            _ => None,
        });
        match &node.kind {
            StatementKind::Var { declaration, .. } => self.declaration(declaration, node, path),
            StatementKind::For { control, .. } => match control {
                ForControl::All { declaration } => self.declaration(declaration, node, path),
                ForControl::Each { binding, .. } => {
                    let binding = binding
                        .rsplit_once(" as ")
                        .map_or(binding.as_str(), |(name, _)| name.trim());
                    self.iterator(binding, node, path);
                }
                ForControl::Pair {
                    key_binding,
                    value_binding,
                    ..
                } => {
                    for binding in [key_binding, value_binding] {
                        let name = local_name(binding).unwrap_or(binding);
                        if binding.starts_with("var/") || self.scopes.resolve(name).is_none() {
                            self.declare(name, node, path);
                        } else {
                            self.reference(
                                name,
                                node.header_span,
                                path,
                                ReferenceSite::IteratorHeader,
                                ReferenceAccess::ReadWrite,
                            );
                        }
                    }
                }
                ForControl::Range { binding, .. } => self.iterator(binding, node, path),
                ForControl::CStyle {
                    initializer: Some(ForInitializer::Declare { declaration, .. }),
                    ..
                } => self.declaration(declaration, node, path),
                ForControl::CStyle { .. } => {}
            },
            StatementKind::Set { .. } => {
                self.gap(
                    path,
                    node.header_span,
                    "setting must be normalized before executable binding",
                );
                return VisitDecision::Skip;
            }
            StatementKind::Unsupported => {
                self.gap(path, node.header_span, "unsupported typed statement");
                return VisitDecision::Skip;
            }
            _ => {}
        }
        VisitDecision::Descend
    }
    fn leave_statement(&mut self, _: &Statement, _: &[NodeStep]) {
        self.assignment_targets
            .pop()
            .expect("statement callbacks are balanced");
        if self
            .statement_scopes
            .pop()
            .expect("statement callbacks are balanced")
        {
            self.scopes
                .leave_scope()
                .expect("statement scope is balanced");
        }
    }
    fn enter_branch(&mut self, owner: &Statement, index: usize, path: &[NodeStep]) {
        self.scopes.enter_scope();
        if let StatementKind::Try {
            catch_binding: Some(binding),
            ..
        } = &owner.kind
        {
            if index == 1 {
                self.declaration(binding, owner, path);
            }
        }
    }
    fn leave_branch(&mut self, _: &Statement, _: usize, _: &[NodeStep]) {
        self.scopes.leave_scope().expect("branch scope is balanced");
    }
    fn expression(&mut self, node: &Expr, path: &[NodeStep]) -> VisitDecision {
        let parent = self.expression_roles.last().copied().unwrap_or_default();
        let child = match path.last() {
            Some(NodeStep::Child(index)) => Some(*index),
            _ => None,
        };
        let access = if child == Some(0) {
            parent.child_zero_access.unwrap_or_default()
        } else if matches!(path.last(), Some(NodeStep::Expression(0))) {
            self.assignment_targets
                .last()
                .copied()
                .flatten()
                .unwrap_or_default()
        } else {
            ReferenceAccess::Read
        };
        self.expression_roles.push(ExpressionRole::default());
        if parent.suppress_child_zero && child == Some(0) {
            return VisitDecision::Skip;
        }
        match &node.kind {
            ExprKind::Ident(name)
                if access != ReferenceAccess::Read || !dm_syntax::is_literal_identifier(name) =>
            {
                self.reference(name, node.span, path, ReferenceSite::Expression, access)
            }
            ExprKind::Call { callee, args } => {
                if parent.arglist_wrapper && child == Some(1) {
                    self.expression_roles
                        .last_mut()
                        .unwrap()
                        .suppress_child_zero = true;
                    return VisitDecision::Descend;
                }
                match dm_syntax::call_target(callee) {
                    dm_syntax::CallTarget::Member { .. }
                    | dm_syntax::CallTarget::SafeMember { .. } => {
                        let frame = self.expression_roles.last_mut().unwrap();
                        frame.member_call = true;
                        frame.named_arguments = args
                            .iter()
                            .any(|arg| dm_syntax::named_argument(arg).is_some());
                        frame.arglist_wrapper = dm_syntax::arglist_argument(args).is_some()
                            && !matches!(dm_syntax::call_target(callee),dm_syntax::CallTarget::Member {object,..} if dm_syntax::is_global_receiver(object));
                    }
                    dm_syntax::CallTarget::Named(name) => {
                        let mut callee_path = path.to_vec();
                        callee_path.push(NodeStep::Child(0));
                        self.selectors.push(SelectorReference {
                            selector: Arc::from(name),
                            path: callee_path,
                            span: callee.span,
                            receiver_path: None,
                            kind: SelectorKind::NamedProcedure,
                        });
                        self.gap(
                            path,
                            node.span,
                            "named-call intrinsic argument roles require compiler policy",
                        );
                        return VisitDecision::Skip;
                    }
                    _ => {
                        self.gap(
                            path,
                            node.span,
                            "specialized call target requires compiler reference roles",
                        );
                        return VisitDecision::Skip;
                    }
                }
            }
            ExprKind::Binary { .. }
                if parent.member_call
                    && parent.named_arguments
                    && child.is_some_and(|index| index > 0)
                    && dm_syntax::named_argument(node).is_some() =>
            {
                if let Some(argument) = dm_syntax::named_argument(node) {
                    if matches!(&argument.key.kind, ExprKind::Ident(_)) {
                        self.expression_roles
                            .last_mut()
                            .unwrap()
                            .suppress_child_zero = true;
                    }
                }
            }
            ExprKind::Binary { op, .. } if dm_syntax::assignment_target_access(op).is_some() => {
                self.expression_roles.last_mut().unwrap().child_zero_access =
                    dm_syntax::assignment_target_access(op);
            }
            ExprKind::Unary { op, .. }
                if matches!(op.as_str(), "pre++" | "post++" | "pre--" | "post--") =>
            {
                self.expression_roles.last_mut().unwrap().child_zero_access =
                    Some(ReferenceAccess::ReadWrite);
            }
            ExprKind::Group(_) => {
                self.expression_roles.last_mut().unwrap().child_zero_access = Some(access)
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember { object, selector }
            | ExprKind::StaticMember { object, selector } => {
                let procedure = parent.member_call && child == Some(0);
                let global = matches!(&node.kind, ExprKind::Member { .. })
                    && dm_syntax::is_global_receiver(object);
                let kind = if global {
                    if procedure {
                        SelectorKind::GlobalProcedure
                    } else {
                        SelectorKind::GlobalField
                    }
                } else if procedure {
                    SelectorKind::Procedure
                } else if matches!(&node.kind, ExprKind::StaticMember { .. }) {
                    SelectorKind::StaticField
                } else {
                    SelectorKind::Field
                };
                let receiver_path = if global {
                    None
                } else {
                    let mut receiver = path.to_vec();
                    receiver.push(NodeStep::Child(0));
                    Some(receiver)
                };
                self.selectors.push(SelectorReference {
                    selector: Arc::from(selector.as_str()),
                    path: path.to_vec(),
                    span: node.span,
                    receiver_path,
                    kind,
                });
                self.expression_roles
                    .last_mut()
                    .unwrap()
                    .suppress_child_zero = global;
            }
            ExprKind::ObjectInitializer { .. } => {
                self.gap(
                    path,
                    node.span,
                    "modified instance requires compiler reference roles",
                );
                return VisitDecision::Skip;
            }
            ExprKind::Unary { op, .. } if op == "new" || op == "new()" => {
                self.gap(
                    path,
                    node.span,
                    "constructor operands require compiler reference roles",
                );
                return VisitDecision::Skip;
            }
            ExprKind::Literal(text) if text.starts_with('"') && text.contains('[') => self.gap(
                path,
                node.span,
                "string interpolation references are not represented as typed children",
            ),
            _ => {}
        }
        VisitDecision::Descend
    }
    fn leave_expression(&mut self, _: &Expr, _: &[NodeStep]) {
        self.expression_roles
            .pop()
            .expect("expression callbacks are balanced");
    }
}
