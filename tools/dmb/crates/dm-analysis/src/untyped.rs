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
#[derive(Clone, Debug)]
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
    crate::untyped_order::assignments_current(view.syntax().view(), &mut |lhs, rhs, _, current| {
        if walker.error.is_none() {
            if let Err(error) = walker.assignment_at(lhs, rhs, current) {
                walker.error = Some(error);
            }
        }
    })
    .map_err(|e| Unsupported(e.into()))?;
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
    let locals = body.source_locals().map_err(Unsupported)?;
    require_local_source_projection(locals)?;
    scope_from_parameters(
        &frontend.snapshot.tree,
        body.occurrence(),
        view.syntax(),
        resolver,
        exempt_types,
        Some(body.source_parameters().map_err(Unsupported)?),
        Some(locals),
    )
}

/// Archive inputs authenticate their own semantic owner. There is deliberately
/// no caller-supplied tree/member parameter that could rebind source metadata.
pub(crate) fn archived_scope<'a, R: Resolver + ?Sized>(
    body: &'a ArchivedBody<'_>,
    resolver: &'a R,
    exempt_types: &'a [String],
) -> Result<Walker<'a, R>, Unsupported> {
    let locals = body.source_locals().map_err(Unsupported)?;
    require_local_source_projection(locals)?;
    scope_from_parameters(
        body.tree(),
        body.occurrence(),
        body.statement_body(),
        resolver,
        exempt_types,
        Some(body.source_parameters().map_err(Unsupported)?),
        Some(locals),
    )?
    .with_archive(body.archive_owner())
}

/// Validate the existing ORIGINAL ledger. No normalized declaration spelling
/// can stand in for these facts. Unsupported grammar remains an atomic refusal.
pub(crate) fn require_local_source_projection(
    view: dm_tree::frontend::SourceLocalView<'_>,
) -> Result<(), Unsupported> {
    if view.scope_admission().map_err(Unsupported)? > 64 * 1024 * 1024 {
        return Err(Unsupported(
            "original local scope exceeds bounded policy admission before allocation".into(),
        ));
    }
    Ok(())
}

/// Called only after the live-body issuance check, or with archive-owned parts.
/// This borrows declarations and syntax; it constructs only policy-local facts.
#[cfg(test)]
pub(crate) fn scope_from<'a, R: Resolver + ?Sized>(
    tree: &'a dm_tree::SemanticTree,
    occurrence: &dm_tree::frontend::BodyOccurrence,
    syntax: &StatementBody,
    resolver: &'a R,
    exempt_types: &'a [String],
) -> Result<Walker<'a, R>, Unsupported> {
    scope_from_parameters(tree, occurrence, syntax, resolver, exempt_types, None, None)
}
/// Only a sealed ORIGINAL body view can supply parameter path authority.
pub(crate) fn scope_from_parameters<'a, R: Resolver + ?Sized>(
    tree: &'a dm_tree::SemanticTree,
    occurrence: &dm_tree::frontend::BodyOccurrence,
    syntax: &StatementBody,
    resolver: &'a R,
    exempt_types: &'a [String],
    parameters: Option<dm_tree::frontend::SourceParameterView<'_>>,
    local_source: Option<dm_tree::frontend::SourceLocalView<'_>>,
) -> Result<Walker<'a, R>, Unsupported> {
    if let Some(parameters) = parameters {
        parameters
            .require_for(tree, occurrence)
            .map_err(Unsupported)?;
    }
    if let Some(source) = local_source {
        source
            .require_for(tree, occurrence, syntax)
            .map_err(Unsupported)?;
        require_local_source_projection(source)?;
    }
    if !syntax.syntax_complete() {
        return Err(Unsupported(
            "body has unsupported or malformed native syntax".into(),
        ));
    }
    let member = tree
        .member(occurrence.member)
        .ok_or_else(|| Unsupported("missing issued member".into()))?;
    let owner = tree
        .type_node(member.owner)
        .ok_or_else(|| Unsupported("missing issued owner".into()))?
        .path;
    // Reserve the whole original source-derived type map BEFORE strings or
    // hash buckets are built. This is the existing bounded policy cohort, not
    // a new cache or permission to emit a partial proof.
    let mut scope_admission = local_source
        .map(|v| v.scope_admission())
        .transpose()
        .map_err(Unsupported)?
        .unwrap_or(4096);
    if let Some(parameters) = parameters {
        for entry in parameters.entries().map_err(Unsupported)? {
            let width = entry
                .type_components()
                .iter()
                .try_fold(5usize, |sum, span| {
                    sum.checked_add(span.end.checked_sub(span.start)?)
                        .and_then(|n| n.checked_add(1))
                })
                .ok_or_else(|| Unsupported("original parameter scope width overflow".into()))?;
            scope_admission = scope_admission
                .checked_add(
                    parameters
                        .name(entry)
                        .map_err(Unsupported)?
                        .len()
                        .saturating_add(width)
                        .saturating_mul(4)
                        .saturating_add(256),
                )
                .ok_or_else(|| Unsupported("original parameter scope admission overflow".into()))?;
        }
    }
    if scope_admission > 64 * 1024 * 1024 {
        return Err(Unsupported(
            "original local/parameter scope exceeds bounded policy admission before allocation"
                .into(),
        ));
    }
    let mut local_types = HashMap::new();
    let procedure = member
        .metadata
        .procedure
        .as_ref()
        .ok_or_else(|| Unsupported("missing native procedure signature".into()))?;
    if let Some(parameters) = parameters {
        for parameter in parameters.entries().map_err(Unsupported)? {
            let name = parameters.name(parameter).map_err(Unsupported)?;
            let ty = parameters
                .type_path(parameter)
                .map_err(Unsupported)?
                .unwrap_or_default();
            local_types.insert(name.to_owned(), ty);
        }
    } else if !procedure.signature.parameters.is_empty() || procedure.signature.variadic {
        return Err(Unsupported("unissued parameters require an original primary signature receipt; zero runtime flags are not source proof".into()));
    }
    if let Some(source) = local_source {
        let mut locals = Locals {
            source,
            types: local_types,
            error: None,
        };
        dm_syntax::visit_statements(&syntax.parsed().statements, &mut locals);
        if let Some(error) = locals.error {
            return Err(error);
        }
        local_types = locals.types;
    } else if !syntax
        .parsed()
        .local_variables
        .entries()
        .map_err(|e| Unsupported(e.into()))?
        .is_empty()
    {
        return Err(Unsupported(
            "unissued local source ledger cannot authorize normalized scope".into(),
        ));
    }
    Ok(Walker {
        tree,
        archive: None,
        resolver,
        owner,
        locals: local_types,
        exempt_types,
        found: BTreeMap::new(),
        error: None,
    })
}

fn guard_declaration_type(
    tree: &dm_tree::SemanticTree,
    ty: Option<SymbolId>,
    element: Option<SymbolId>,
) -> Result<(), Unsupported> {
    for symbol in [ty, element].into_iter().flatten() {
        let path = tree
            .symbols()
            .text(symbol)
            .ok_or_else(|| Unsupported("unknown declaration type symbol".into()))?;
        if dm_syntax::has_checker_qualifiers(path) {
            return Err(Unsupported(
                "declaration needs native checker qualifier facts".into(),
            ));
        }
    }
    Ok(())
}
fn declaration_type(
    tree: &dm_tree::SemanticTree,
    ty: Option<SymbolId>,
    element: Option<SymbolId>,
) -> Result<String, Unsupported> {
    guard_declaration_type(tree, ty, element)?;
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

fn has_field_qualifiers(
    tree: &dm_tree::SemanticTree,
    ty: Option<SymbolId>,
    element: Option<SymbolId>,
) -> Result<bool, Unsupported> {
    let mut any = false;
    for symbol in ty.into_iter().chain(element) {
        let path = tree
            .symbols()
            .text(symbol)
            .ok_or_else(|| Unsupported("unknown field type symbol".into()))?;
        any |= dm_syntax::has_checker_qualifiers(path);
    }
    Ok(any)
}
/// Native metadata is never rewritten. Only the ORIGINAL archive's proved
/// formal supplies the checker hint for a qualified source declaration.
pub(crate) fn field_declared_hint<R: Resolver + ?Sized>(
    tree: &dm_tree::SemanticTree,
    resolver: &R,
    archive: Option<&dm_tree::frontend::BodyArchive>,
    owner: SymbolId,
    name: SymbolId,
    data: &DeclarationMeaning,
) -> Result<Option<String>, Unsupported> {
    if !has_field_qualifiers(tree, data.declared_type, data.list_element_type)? {
        let hint = declaration_type(tree, data.declared_type, data.list_element_type)?;
        return Ok((!hint.is_empty()).then_some(hint));
    }
    let archive = archive.ok_or_else(|| {
        Unsupported("qualified field needs its original archive hint provider".into())
    })?;
    if !std::ptr::eq(tree, archive.tree()) {
        return Err(Unsupported(
            "qualified field archive has another semantic owner".into(),
        ));
    }
    let profile = tree
        .checker_builtin_profile()
        .ok_or_else(|| Unsupported("qualified field checker profile unavailable".into()))?;
    let fact = crate::checker_variable_facts::variable(tree, resolver, profile, owner, name)
        .map_err(Unsupported)?
        .ok_or_else(|| Unsupported("qualified source formal unavailable".into()))?;
    if fact.metadata.declared_type != data.declared_type
        || fact.metadata.list_element_type != data.list_element_type
    {
        return Err(Unsupported(
            "qualified target metadata differs from selected original formal".into(),
        ));
    }
    let formal = fact
        .formal
        .ok_or_else(|| Unsupported("qualified hint has no authored primary formal".into()))?;
    let view = archive
        .checker_variable_properties(formal, profile)
        .map_err(Unsupported)?;
    if !std::ptr::eq(view.metadata, fact.metadata.as_ref()) {
        return Err(Unsupported(
            "qualified hint lost original metadata backing".into(),
        ));
    }
    Ok(view.declared_hint().map(str::to_owned))
}

/// Original pinned collect_locals policy: Var/Vars overwrite, ForList only
/// inserts absent names, pair bindings are untyped, singleton CStyle inserts.
/// ForRange and catch bindings are deliberately NOT collected by that policy.
struct Locals<'a> {
    source: dm_tree::frontend::SourceLocalView<'a>,
    types: HashMap<String, String>,
    error: Option<Unsupported>,
}
pub(crate) fn original_local_in_header<'a>(
    view: &dm_tree::frontend::SourceLocalView<'a>,
    span: Span,
) -> Result<Option<&'a dm_syntax::LocalVariableSyntax>, Unsupported> {
    let mut found = view.in_span(span).map_err(Unsupported)?.iter();
    let first = found.next();
    if found.next().is_some() {
        return Err(Unsupported(
            "original local header has multiple unprojected declarations".into(),
        ));
    }
    Ok(first)
}
impl Locals<'_> {
    fn declared(&mut self, span: Span, absent: bool) -> Result<(), Unsupported> {
        let fact = original_local_in_header(&self.source, span)?
            .ok_or_else(|| Unsupported("original local declaration occurrence missing".into()))?;
        let name = self.source.name(fact).map_err(Unsupported)?;
        if absent && self.types.contains_key(name) {
            return Ok(());
        }
        let ty = self
            .source
            .type_path(fact)
            .map_err(Unsupported)?
            .unwrap_or_default();
        self.types.insert(name.to_owned(), ty);
        Ok(())
    }
    fn bare(&mut self, name: &str) -> Result<(), Unsupported> {
        let mut chars = name.chars();
        if !chars.next().is_some_and(|c| c == '_' || c.is_alphabetic())
            || !chars.all(|c| c == '_' || c.is_alphanumeric())
        {
            return Err(Unsupported(
                "implicit loop binding lacks original bare-name authority".into(),
            ));
        }
        self.types.entry(name.to_owned()).or_default();
        Ok(())
    }
}
impl TypedVisitor for Locals<'_> {
    fn projected_expression(
        &mut self,
        _view: dm_syntax::ProjectedExprView<'_>,
        _path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        dm_syntax::VisitDecision::Descend
    }

    fn statement(&mut self, st: &Statement, _: &[NodeStep]) -> VisitDecision {
        if self.error.is_some() {
            return VisitDecision::Skip;
        }
        let result = (|| -> Result<(), Unsupported> {
            match &st.kind {
                StatementKind::Var { .. } => self.declared(st.header_span, false)?,
                StatementKind::For { control, .. } => match control {
                    ForControl::All { .. } => self.declared(st.header_span, true)?,
                    ForControl::Each { binding, .. } => {
                        if original_local_in_header(&self.source, st.header_span)?.is_some() {
                            self.declared(st.header_span, true)?;
                        } else {
                            self.bare(binding)?;
                        }
                    }
                    ForControl::Pair {
                        key_binding,
                        value_binding,
                        ..
                    } => {
                        let mut names = self
                            .source
                            .in_span(st.header_span)
                            .map_err(Unsupported)?
                            .iter();
                        if let Some(first) = names.next() {
                            let second = names.next().ok_or_else(|| {
                                Unsupported("original pair binding roster incomplete".into())
                            })?;
                            if names.next().is_some() {
                                return Err(Unsupported(
                                    "original pair binding roster ambiguous".into(),
                                ));
                            }
                            let a = self.source.name(first).map_err(Unsupported)?.to_owned();
                            let b = self.source.name(second).map_err(Unsupported)?.to_owned();
                            self.bare(&a)?;
                            self.bare(&b)?;
                        } else {
                            self.bare(key_binding)?;
                            self.bare(value_binding)?;
                        }
                    }
                    ForControl::CStyle {
                        initializer: Some(ForInitializer::Declare { .. }),
                        ..
                    } => self.declared(st.header_span, false)?,
                    ForControl::Range { .. }
                    | ForControl::RangeImplicitArray { .. }
                    | ForControl::CStyle { .. } => (),
                },
                _ => (),
            }
            Ok(())
        })();
        if let Err(error) = result {
            self.error = Some(error);
            VisitDecision::Skip
        } else {
            VisitDecision::Descend
        }
    }
}

pub(crate) struct Walker<'a, R: ?Sized> {
    tree: &'a dm_tree::SemanticTree,
    archive: Option<&'a dm_tree::frontend::BodyArchive>,
    resolver: &'a R,
    pub(crate) owner: SymbolId,
    pub(crate) locals: HashMap<String, String>,
    exempt_types: &'a [String],
    found: BTreeMap<(SymbolId, SymbolId), Contribution>,
    error: Option<Unsupported>,
}
impl<'a, R: Resolver + ?Sized> Walker<'a, R> {
    pub(crate) fn with_archive(
        mut self,
        archive: &'a dm_tree::frontend::BodyArchive,
    ) -> Result<Self, Unsupported> {
        if !std::ptr::eq(self.tree, archive.tree()) {
            return Err(Unsupported(
                "untyped source hints belong to another original semantic owner".into(),
            ));
        }
        self.archive = Some(archive);
        Ok(self)
    }
    pub(crate) fn field_is_typed(
        &self,
        owner: SymbolId,
        name: SymbolId,
        metadata: &DeclarationMeaning,
    ) -> Result<bool, Unsupported> {
        field_declared_hint(
            self.tree,
            self.resolver,
            self.archive,
            owner,
            name,
            metadata,
        )
        .map(|hint| hint.is_some())
    }

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
                // Refuse BEFORE callers can skip an apparently typed target.
                // These reserved type segments carry checker qualifiers, not a
                // proven declared type; do not strip or guess their meaning.
                field_declared_hint(
                    self.tree,
                    self.resolver,
                    self.archive,
                    owner,
                    SymbolId::of(name),
                    &data,
                )?;
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
        if let Some(profile) = self.tree.checker_builtin_profile() {
            if !self
                .tree
                .checker_source_type_presence(profile, ty)
                .map_err(|e| Unsupported(format!("{e:?}")))?
            {
                return Ok(false);
            }
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
        // Receiver typing needs only the independent declared-type proof, not
        // defaults, flags, a storage slot or a fabricated source declaration.
        // Pinned native catalog fields can prove this even when Q::Var must
        // refuse its larger metadata contract.
        let query = Q::DeclaredVarType {
            owner,
            name: SymbolId::of(name),
        };
        let declared = match self.resolver.resolve(query) {
            M::DeclaredType(declared) => declared,
            M::Missing => return Ok(None),
            _ => return Err(Unsupported(format!("field type is incomplete: {query:?}"))),
        };
        // Source list declarations carry element typing that the independent
        // field-type query does not encode. Keep that authored precision; an
        // opaque native /list proves no element type and stays plain /list.
        let element = if declared == Some(SymbolId::of("/list")) {
            match self.resolver.resolve(Q::Var {
                owner,
                name: SymbolId::of(name),
            }) {
                M::Member { data, .. } if data.inherited_opaque.is_none() => {
                    if data.declared_type != declared {
                        return Err(Unsupported("inconsistent source field type answers".into()));
                    }
                    data.list_element_type
                }
                _ => None,
            }
        } else {
            None
        };
        if has_field_qualifiers(self.tree, declared, element)? {
            let data = match self.resolver.resolve(Q::Var {
                owner,
                name: SymbolId::of(name),
            }) {
                M::Member { data, .. } if data.inherited_opaque.is_none() => data,
                _ => {
                    return Err(Unsupported(
                        "qualified field type has no original source metadata".into(),
                    ))
                }
            };
            if data.declared_type != declared || data.list_element_type != element {
                return Err(Unsupported(
                    "qualified receiver type differs from original field metadata".into(),
                ));
            }
            return field_declared_hint(
                self.tree,
                self.resolver,
                self.archive,
                owner,
                SymbolId::of(name),
                &data,
            )
            .map(|hint| Some(hint.unwrap_or_default()));
        }
        Ok(Some(declaration_type(self.tree, declared, element)?))
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
        self.assignment_at(lhs, rhs, lhs.span)
    }
    fn assignment_at(&mut self, lhs: &Expr, rhs: &Expr, current: Span) -> Result<(), Unsupported> {
        let Some((owner, name, metadata)) = self.place(lhs)? else {
            return Ok(());
        };
        if self.field_is_typed(owner, name, &metadata)? || metadata.flags & CONST_FLAG != 0 {
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
            assignment: current,
        });
        if rule == Rule::Typed {
            entry.rule = Rule::Typed;
        }
        Ok(())
    }
}
impl<R: Resolver + ?Sized> TypedVisitor for Walker<'_, R> {
    fn projected_expression(
        &mut self,
        view: dm_syntax::ProjectedExprView<'_>,
        path: &[dm_syntax::NodeStep],
    ) -> dm_syntax::VisitDecision {
        let _ = path;
        if let ExprKind::Binary { op, lhs, rhs } = &view.original().kind {
            if op == "=" {
                let result = view.current_span_of(lhs)
                    .ok_or_else(|| Unsupported("projected assignment target has no current span".into()))
                    .and_then(|at| self.assignment_at(lhs, rhs, at));
                if let Err(error) = result {
                    self.error = Some(error);
                    return VisitDecision::Stop;
                }
            }
        }
        // Type/place inference is shape/name based; only the reported target
        // span above is coordinate-sensitive. Never clone or shift the root.
        VisitDecision::Descend
    }

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

#[path = "untyped_player_link_receiver.rs"]
mod player_link_receiver;

#[cfg(test)]
#[path = "untyped_parameter_guard_tests.rs"]
mod parameter_guard_tests;

#[cfg(test)]
#[path = "untyped_local_source_gate_tests.rs"]
mod local_source_gate_tests;

#[cfg(test)]
#[path = "untyped_original_local_scope_tests.rs"]
mod original_local_scope_tests;

#[path = "untyped_stored_refs_scope.rs"]
mod stored_refs_scope;
pub(crate) use stored_refs_scope::archived_stored_scope;
#[path = "untyped_stored_refs.rs"]
mod stored_refs;
pub use stored_refs::{stored_findings, stored_findings_checked, stored_findings_with, StoredFinding, StoredPolicy};

// Borrowed original-policy traversal for native read annotations/consumers.
pub use crate::untyped_order::{try_policy_expressions,ExpressionObservation,PolicyVisitFailure};
