//! Native body contributions for Analyze's `untyped` policy. The policy layer
//! still owns exemptions, declaration locations, baselines and ALLOW accounting.
//! No dreammaker AST or copied object tree is involved in this path.
//! This is the assignment-fact stage, NOT the complete production lint: whole-tree
//! value-proc inference and value-schema policy must consume these facts before
//! this path can replace the legacy lint. Unknown calls stay conservative here.
use crate::checks::BodyView;
use dm_ir::{DeclarationMeaning, ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
use dm_syntax::{
    Expr, ExprKind, ForControl, ForInitializer, NodeStep, Span, Statement, StatementKind,
    TypedVisitor, VisitDecision,
};
use dm_tree::frontend::{ArchivedBody, ColdFrontend, ParsedBody, StatementBody};
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Rule {
    Typed,
    Call,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Contribution {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub rule: Rule,
    pub assignment: Span,
}

/// Missing semantic knowledge is an error, never a clean lint result. In
/// particular, opaque builtin declarations cannot be treated as untyped fields.
#[derive(Debug)]
pub struct Unsupported(pub String);
impl std::fmt::Display for Unsupported {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}
impl std::error::Error for Unsupported {}

const CONST_FLAG: u32 = 2; // Native declaration flag, dm-tree/adapter.rs.
const NOT_REFS: &[&str] = &[
    "/turf",
    "/area",
    "/client",
    "/world",
    "/savefile",
    "/database",
    "/exception",
    "/regex",
    "/icon",
    "/image",
    "/mutable_appearance",
    "/sound",
    "/matrix",
    "/generator",
    "/particles",
    "/filter",
    "/alist",
    "/list",
    "/callee",
];

fn under(path: &str, root: &str) -> bool {
    path == root
        || path
            .strip_prefix(root)
            .is_some_and(|tail| tail.starts_with('/'))
}
fn ungroup(mut expression: &Expr) -> &Expr {
    while let ExprKind::Group(inner) = &expression.kind {
        expression = inner;
    }
    expression
}
fn declared_local(text: &str) -> Option<(String, String)> {
    let name = dm_syntax::local_name(text)?.to_owned();
    let prefix = text
        .trim_start_matches("var/")
        .trim_start_matches("var ")
        .trim();
    let before_name = prefix.rsplit_once('/').map_or("", |(prefix, _)| prefix);
    let parts: Vec<_> = before_name
        .split('/')
        .filter(|part| !matches!(*part, "static" | "const" | "global" | "tmp" | ""))
        .collect();
    let mut ty = if parts.is_empty() {
        String::new()
    } else {
        format!("/{}", parts.join("/"))
    };
    if text.contains('[') && !under(&ty, "/list") {
        ty = format!("/list{ty}");
    }
    Some((name, ty))
}

/// `resolver` is the SAME immutable native host used by lowering. A host with a
/// read observer records positive and negative lookups here in the normal way.
pub fn contributions(
    frontend: &ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &impl Resolver,
    exempt_types: &[String],
) -> Result<Vec<Contribution>, Unsupported> {
    let view = BodyView::new(frontend, body).map_err(Unsupported)?;
    let mut walker = scope(frontend, body, resolver, exempt_types)?;
    dm_syntax::visit_statements(&view.syntax().parsed().statements, &mut walker);
    if let Some(error) = walker.error {
        return Err(error);
    }
    Ok(walker.found.into_values().collect())
}

pub(crate) fn scope<'a, R: Resolver + ?Sized>(
    frontend: &'a ColdFrontend,
    body: &ParsedBody<'_>,
    resolver: &'a R,
    exempt_types: &'a [String],
) -> Result<Walker<'a, R>, Unsupported> {
    let view = BodyView::new(frontend, body).map_err(Unsupported)?;
    scope_from(
        &frontend.snapshot.tree,
        body.occurrence().member,
        view.syntax(),
        resolver,
        exempt_types,
    )
}

/// Archive inputs authenticate their own semantic owner. There is deliberately
/// no caller-supplied tree/member parameter that could rebind source metadata.
pub(crate) fn archived_scope<'a, R: Resolver + ?Sized>(
    body: &'a ArchivedBody<'_>,
    resolver: &'a R,
    exempt_types: &'a [String],
) -> Result<Walker<'a, R>, Unsupported> {
    scope_from(
        body.tree(),
        body.occurrence().member,
        body.statement_body(),
        resolver,
        exempt_types,
    )
}

/// Called only after the live-body issuance check, or with archive-owned parts.
/// This borrows declarations and syntax; it constructs only policy-local facts.
pub(crate) fn scope_from<'a, R: Resolver + ?Sized>(
    tree: &'a dm_tree::SemanticTree,
    member: dm_tree::MemberId,
    syntax: &StatementBody,
    resolver: &'a R,
    exempt_types: &'a [String],
) -> Result<Walker<'a, R>, Unsupported> {
    if !syntax.syntax_complete() {
        return Err(Unsupported(
            "body has unsupported or malformed native syntax".into(),
        ));
    }
    let member = tree
        .member(member)
        .ok_or_else(|| Unsupported("missing issued member".into()))?;
    let owner = tree
        .type_node(member.owner)
        .ok_or_else(|| Unsupported("missing issued owner".into()))?
        .path;
    let mut locals = Locals::default();
    let procedure = member
        .metadata
        .procedure
        .as_ref()
        .ok_or_else(|| Unsupported("missing native procedure signature".into()))?;
    for parameter in procedure.signature.parameters.iter() {
        let name = tree
            .symbols()
            .text(parameter.name)
            .ok_or_else(|| Unsupported("unknown parameter symbol".into()))?;
        locals.types.insert(
            name.to_owned(),
            declaration_type(tree, parameter.declared_type, parameter.list_element_type)?,
        );
    }
    dm_syntax::visit_statements(&syntax.parsed().statements, &mut locals);
    if locals.unsupported {
        return Err(Unsupported(
            "native local declaration coverage is incomplete".into(),
        ));
    }
    Ok(Walker {
        tree,
        resolver,
        owner,
        locals: locals.types,
        exempt_types,
        found: BTreeMap::new(),
        error: None,
    })
}

fn declaration_type(
    tree: &dm_tree::SemanticTree,
    ty: Option<SymbolId>,
    element: Option<SymbolId>,
) -> Result<String, Unsupported> {
    let Some(ty) = ty else {
        return Ok(String::new());
    };
    let path = tree
        .symbols()
        .text(ty)
        .ok_or_else(|| Unsupported("unknown type symbol".into()))?;
    if path == "/list" {
        if let Some(element) = element {
            let element = tree
                .symbols()
                .text(element)
                .ok_or_else(|| Unsupported("unknown list element symbol".into()))?;
            return Ok(format!("/list{element}"));
        }
    }
    Ok(path.to_owned())
}

#[derive(Default)]
struct Locals {
    types: HashMap<String, String>,
    unsupported: bool,
}
impl Locals {
    fn insert_if_absent(&mut self, declaration: &str) {
        match declared_local(declaration) {
            Some((name, ty)) => {
                self.types.entry(name).or_insert(ty);
            }
            None => self.unsupported = true,
        }
    }
    fn insert(&mut self, declaration: &str) {
        // Static locals also shadow fields in the reference rule. They are not
        // candidates for this lint (stored_refs has its own static-list rule).
        let normalized = declaration
            .replace("var/static/", "var/")
            .replace("var/global/", "var/");
        match declared_local(&normalized) {
            Some((name, ty)) => {
                self.types.insert(name, ty);
            }
            None => self.unsupported = true,
        }
    }
}
impl TypedVisitor for Locals {
    fn statement(&mut self, statement: &Statement, _: &[NodeStep]) -> VisitDecision {
        match &statement.kind {
            StatementKind::Var { declaration, .. } => self.insert(declaration),
            StatementKind::For { control, .. } => match control {
                ForControl::All { declaration } => self.insert_if_absent(declaration),
                ForControl::Each { binding, .. } | ForControl::Range { binding, .. } => {
                    if binding.starts_with("var/") {
                        self.insert_if_absent(binding.split(" as ").next().unwrap());
                    } else {
                        self.types.entry(binding.clone()).or_default();
                    }
                }
                ForControl::Pair {
                    key_binding,
                    value_binding,
                    ..
                } => {
                    for binding in [key_binding, value_binding] {
                        self.types
                            .entry(dm_syntax::local_name(binding).unwrap_or(binding).to_owned())
                            .or_default();
                    }
                }
                ForControl::CStyle {
                    initializer: Some(ForInitializer::Declare { declaration, .. }),
                    ..
                } => self.insert(declaration),
                _ => (),
            },
            _ => (),
        }
        VisitDecision::Descend
    }
}

pub(crate) struct Walker<'a, R: ?Sized> {
    tree: &'a dm_tree::SemanticTree,
    resolver: &'a R,
    pub(crate) owner: SymbolId,
    pub(crate) locals: HashMap<String, String>,
    exempt_types: &'a [String],
    found: BTreeMap<(SymbolId, SymbolId), Contribution>,
    error: Option<Unsupported>,
}
impl<R: Resolver + ?Sized> Walker<'_, R> {
    pub(crate) fn field(
        &self,
        owner: SymbolId,
        name: &str,
    ) -> Result<Option<(SymbolId, Arc<DeclarationMeaning>)>, Unsupported> {
        let query = Q::Var {
            owner,
            name: SymbolId::of(name),
        };
        match self.resolver.resolve(query) {
            M::Member { data, .. } if data.inherited_opaque.is_none() => {
                // An inherited default override does not declare another slot.
                // The compiler's storage query supplies its formal owner.
                let storage = Q::VarStorage {
                    owner,
                    name: SymbolId::of(name),
                };
                let declaring_owner = match self.resolver.resolve(storage) {
                    M::Slot { owner, .. } => owner,
                    M::InstanceField {
                        declaring_owner, ..
                    } => declaring_owner,
                    _ => {
                        return Err(Unsupported(format!(
                            "field storage is incomplete: {storage:?}"
                        )))
                    }
                };
                Ok(Some((declaring_owner, data)))
            }
            M::Missing => Ok(None),
            _ => Err(Unsupported(format!(
                "field lookup is incomplete: {}::{name} ({query:?})",
                self.tree.symbols().text(owner).unwrap_or("<unknown owner>")
            ))),
        }
    }
    pub(crate) fn is_ref(&self, ty: &str) -> Result<bool, Unsupported> {
        if ty.is_empty()
            || ty == "/"
            || NOT_REFS
                .iter()
                .copied()
                .chain(self.exempt_types.iter().map(String::as_str))
                .any(|root| under(ty, root))
        {
            return Ok(false);
        }
        if ["/datum", "/atom", "/obj", "/mob"]
            .iter()
            .any(|root| ty.starts_with(root))
        {
            return Ok(true);
        }
        match self.resolver.resolve(Q::Ancestry(SymbolId::of(ty))) {
            M::Missing => Ok(false),
            M::Symbols(ancestors) => Ok(ancestors.contains(&SymbolId::of("/datum"))
                && !ancestors.contains(&SymbolId::of("/turf"))
                && !ancestors.contains(&SymbolId::of("/area"))),
            other => Err(Unsupported(format!(
                "type ancestry is incomplete: {other:?}"
            ))),
        }
    }
    fn field_type(&self, owner: SymbolId, name: &str) -> Result<Option<String>, Unsupported> {
        self.field(owner, name)?
            .map(|(_, metadata)| {
                declaration_type(
                    self.tree,
                    metadata.declared_type,
                    metadata.list_element_type,
                )
            })
            .transpose()
    }
    fn return_type(&self, owner: SymbolId, name: &str) -> Result<Option<String>, Unsupported> {
        let query = Q::SourceDeclarationChain {
            owner,
            name: SymbolId::of(name),
            verb: false,
        };
        let metadata = match self.resolver.resolve(query) {
            M::Members(rows) => rows
                .iter()
                .find_map(|row| match row {
                    M::Declaration {
                        data,
                        definition: dm_ir::ProcedureDefinition::Declare,
                        ..
                    } => Some(data.clone()),
                    _ => None,
                })
                .or_else(|| {
                    rows.iter().find_map(|row| match row {
                        M::Declaration { data, .. } => Some(data.clone()),
                        _ => None,
                    })
                })
                .ok_or_else(|| Unsupported("source return declaration missing".into()))?,
            M::Missing if owner != SymbolId::of("/") => {
                return self.return_type(SymbolId::of("/"), name)
            }
            // This is absence of a SOURCE annotation, not proof of a builtin's
            // result. Value classification still requires its own contract.
            M::Missing => return Ok(None),
            _ => {
                return Err(Unsupported(format!(
                    "return declaration is incomplete: {query:?}"
                )))
            }
        };
        let Some(annotation) = metadata
            .procedure
            .as_ref()
            .and_then(|p| p.signature.return_annotation.as_ref())
        else {
            return Ok(None);
        };
        let text = annotation
            .source_text(self.tree.symbols())
            .ok_or_else(|| Unsupported("unknown return annotation symbol".into()))?;
        let compact: String = text.chars().filter(|ch| !ch.is_whitespace()).collect();
        Ok((compact.starts_with('/')
            && compact[1..].split('/').all(|part| {
                !part.is_empty() && part.chars().all(|ch| ch.is_alphanumeric() || ch == '_')
            }))
        .then_some(compact))
    }
    pub(crate) fn type_of(&self, expression: &Expr) -> Result<Option<String>, Unsupported> {
        Ok(match &ungroup(expression).kind {
            ExprKind::Ident(name) => {
                if name == "src" {
                    self.tree
                        .symbols()
                        .text(self.owner)
                        .filter(|owner| *owner != "/")
                        .map(str::to_owned)
                } else if name == "global" {
                    Some("/".into())
                } else if name == "." {
                    Some(String::new())
                } else if name == "world" {
                    Some("/world".into())
                } else if name == "usr" {
                    Some("/mob".into())
                } else if let Some(ty) = self.locals.get(name) {
                    Some(ty.clone())
                } else {
                    match self.field_type(self.owner, name)? {
                        some @ Some(_) => some,
                        None => self.field_type(SymbolId::of("/"), name)?,
                    }
                }
            }
            ExprKind::Unary { op, value } if op == "new" => match &ungroup(value).kind {
                ExprKind::TypePath(path) => Some(path.clone()),
                _ => None,
            },
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => match self.type_of(object)? {
                Some(owner) if !owner.is_empty() => {
                    self.field_type(SymbolId::of(&owner), selector)?
                }
                Some(_) => None,
                None => None,
            },
            ExprKind::Index { object, .. } | ExprKind::SafeIndex { object, .. } => {
                self.type_of(object)?.and_then(|path| {
                    path.strip_prefix("/list")
                        .filter(|tail| tail.starts_with('/'))
                        .map(str::to_owned)
                })
            }
            ExprKind::Call { callee, .. } => match &ungroup(callee).kind {
                ExprKind::Unary { op, value } if op == "new" => match &value.kind {
                    ExprKind::TypePath(path) => Some(path.clone()),
                    _ => None,
                },
                ExprKind::Ident(name) => self.return_type(self.owner, name)?,
                ExprKind::Member {
                    object, selector, ..
                }
                | ExprKind::SafeMember {
                    object, selector, ..
                } => match self.type_of(object)? {
                    Some(owner) => self.return_type(SymbolId::of(&owner), selector)?,
                    None => None,
                },
                _ => None,
            },
            ExprKind::Conditional {
                then_value,
                else_value,
                ..
            } => match self.type_of(then_value)? {
                Some(ty) if self.is_ref(&ty)? => Some(ty),
                _ => self.type_of(else_value)?,
            },
            _ => None,
        })
    }
    pub(crate) fn place(
        &self,
        expression: &Expr,
    ) -> Result<Option<(SymbolId, SymbolId, Arc<DeclarationMeaning>)>, Unsupported> {
        let (receiver, name) = match &ungroup(expression).kind {
            ExprKind::Ident(name) if name != "." && !self.locals.contains_key(name) => {
                let field = match self.field(self.owner, name)? {
                    some @ Some(_) => some,
                    None => self.field(SymbolId::of("/"), name)?,
                };
                return Ok(field.map(|(owner, metadata)| (owner, SymbolId::of(name), metadata)));
            }
            ExprKind::Member {
                object, selector, ..
            }
            | ExprKind::SafeMember {
                object, selector, ..
            } => (object.as_ref(), selector),
            _ => return Ok(None),
        };
        let Some(owner) = self.type_of(receiver)?.filter(|owner| !owner.is_empty()) else {
            return Ok(None);
        };
        Ok(self
            .field(SymbolId::of(&owner), name)?
            .map(|(owner, metadata)| (owner, SymbolId::of(name), metadata)))
    }
    fn assignment(&mut self, lhs: &Expr, rhs: &Expr) -> Result<(), Unsupported> {
        let Some((owner, name, metadata)) = self.place(lhs)? else {
            return Ok(());
        };
        if metadata.declared_type.is_some() || metadata.flags & CONST_FLAG != 0 {
            return Ok(());
        }
        let rhs = ungroup(rhs);
        if matches!(&rhs.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if name == "list"))
        {
            return Ok(());
        }
        let rule = match self.type_of(rhs)? {
            Some(ty) if self.is_ref(&ty)? => Rule::Typed,
            Some(_) => return Ok(()),
            None if is_unknown_call(rhs) => Rule::Call,
            None => return Ok(()),
        };
        let entry = self.found.entry((owner, name)).or_insert(Contribution {
            owner,
            name,
            rule,
            assignment: lhs.span,
        });
        if rule == Rule::Typed {
            entry.rule = Rule::Typed;
        }
        Ok(())
    }
}
impl<R: Resolver + ?Sized> TypedVisitor for Walker<'_, R> {
    fn statement(&mut self, statement: &Statement, _: &[NodeStep]) -> VisitDecision {
        if let StatementKind::Assign { target, op, value } = &statement.kind {
            if op == "=" {
                if let Err(error) = self.assignment(target, value) {
                    self.error = Some(error);
                    return VisitDecision::Stop;
                }
            }
        }
        VisitDecision::Descend
    }
    fn expression(&mut self, expression: &Expr, _: &[NodeStep]) -> VisitDecision {
        if let ExprKind::Binary { op, lhs, rhs } = &expression.kind {
            if op == "=" {
                if let Err(error) = self.assignment(lhs, rhs) {
                    self.error = Some(error);
                    return VisitDecision::Stop;
                }
            }
        }
        VisitDecision::Descend
    }
}

fn is_unknown_call(expression: &Expr) -> bool {
    let ExprKind::Call { callee, .. } = &ungroup(expression).kind else {
        return false;
    };
    let _ = callee;
    true
}

#[cfg(test)]
#[path = "untyped_tests.rs"]
mod tests;
