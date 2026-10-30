//! Native policy boundary under parity validation: value summaries and
//! schemas feed classification; baseline/ALLOW admission remains with Analyze.
use crate::native_program::{BodyDemand, CheckedBodyDemand, CompatibilityBodyDemand};
use crate::{
    untyped::{self, Unsupported},
    value_program::Values,
    value_schemas::{Kind, Schemas},
};
use dm_ir::{Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, Span};
use dm_tree::frontend::{
    ArchivedBody, BodyArchive, BodyArena, BodyOccurrence, ColdFrontend, ParsedBody, SourceLocation,
    StatementBody,
};
use dm_tree::SemanticTree;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Rule {
    Typed,
    Call,
    Schema,
}
impl Rule {
    pub fn name(self) -> &'static str {
        match self {
            Self::Typed => "typed",
            Self::Call => "call",
            Self::Schema => "schema",
        }
    }
}
#[derive(Debug)]
pub struct Evidence {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub rule: Rule,
    pub at: Span,
    pub rejected_path: Option<(String, String)>,
}
fn node(mut node: &Expr) -> &Expr {
    while let ExprKind::Group(inner) = &node.kind {
        node = inner;
    }
    node
}
fn path_literals(node_: &Expr, out: &mut Vec<String>) {
    match &node(node_).kind {
        ExprKind::TypePath(path) => out.push(path.clone()),
        ExprKind::Conditional {
            then_value,
            else_value,
            ..
        } => {
            path_literals(then_value, out);
            path_literals(else_value, out);
        }
        _ => (),
    }
}

enum PolicyBody<'a> {
    Live(&'a ColdFrontend, &'a ParsedBody<'a>),
    Archive(&'a BodyArchive, &'a ArchivedBody<'a>),
}
impl<'a> PolicyBody<'a> {
    fn tree(&self) -> &'a SemanticTree {
        match self {
            Self::Live(f, _) => &f.snapshot.tree,
            Self::Archive(a, _) => a.tree(),
        }
    }
    fn has_field(&self, values: &Values<'a>, name: &str) -> Result<bool, Unsupported> {
        match self {
            Self::Live(f, _) => values.has_field_name(f, name),
            Self::Archive(a, _) => values.archive_has_field_name(a, name),
        }
    }
    fn local_call(&self, values: &Values<'a>, name: &str) -> Result<bool, Unsupported> {
        match self {
            Self::Live(f, b) => values.local_holds_call(f, b, name),
            Self::Archive(_, b) => values.archive_local_holds_call(b, name),
        }
    }
    fn call_value(
        &self,
        values: &Values<'a>,
        expression: &Expr,
        exempt: &'a [String],
    ) -> Result<bool, Unsupported> {
        match self {
            Self::Live(f, b) => values.call_is_value(f, b, expression, exempt),
            Self::Archive(_, b) => values.archive_call_is_value(b, expression, exempt),
        }
    }
}

pub fn body_evidence<'a>(
    frontend: &'a ColdFrontend,
    body: &ParsedBody<'_>,
    values: &Values<'a>,
    schemas: &Schemas,
    exempt_types: &'a [String],
) -> Result<Vec<Evidence>, Unsupported> {
    values.validate_live(frontend)?;
    values.validate_exempt_types(exempt_types)?;
    let scope = untyped::scope(frontend, body, values.resolver(), exempt_types)?;
    let syntax = body
        .statement_body()
        .ok_or_else(|| Unsupported("missing native typed body".into()))?;
    evidence(
        PolicyBody::Live(frontend, body),
        syntax,
        scope,
        values,
        schemas,
        exempt_types,
    )
}

pub fn archived_body_evidence<'a>(
    archive: &'a BodyArchive,
    body: &'a ArchivedBody<'a>,
    values: &Values<'a>,
    schemas: &Schemas,
    exempt_types: &'a [String],
) -> Result<Vec<Evidence>, Unsupported> {
    if !body.belongs_to(archive) {
        return Err(Unsupported(
            "policy body belongs to another archive issuance".into(),
        ));
    }
    values.validate_archive(archive)?;
    values.validate_exempt_types(exempt_types)?;
    let scope = untyped::archived_scope(body, values.resolver(), exempt_types)?;
    evidence(
        PolicyBody::Archive(archive, body),
        body.statement_body(),
        scope,
        values,
        schemas,
        exempt_types,
    )
}

fn evidence<'a, R: Resolver + ?Sized>(
    body: PolicyBody<'a>,
    syntax: &StatementBody,
    scope: untyped::Walker<'a, R>,
    values: &Values<'a>,
    schemas: &Schemas,
    exempt_types: &'a [String],
) -> Result<Vec<Evidence>, Unsupported> {
    struct Scan<'a, 'c, R: ?Sized> {
        body: PolicyBody<'a>,
        scope: untyped::Walker<'a, R>,
        values: &'c Values<'a>,
        schemas: &'c Schemas,
        exempt: &'a [String],
        evidence: Vec<Evidence>,
        error: Option<Unsupported>,
    }
    impl<R: Resolver + ?Sized> Scan<'_, '_, R> {
        fn assign(&mut self, target: &Expr, rhs: &Expr, at: Span) -> Result<(), Unsupported> {
            let name = match &node(target).kind {
                ExprKind::Ident(name) => Some(name.as_str()),
                ExprKind::Member { selector, .. } | ExprKind::SafeMember { selector, .. } => {
                    Some(selector.as_str())
                }
                _ => None,
            };
            if let Some(name) = name {
                if !self.body.has_field(self.values, name)? {
                    return Ok(());
                }
            }
            let Some((owner, name, metadata)) = self.scope.place(target)? else {
                return Ok(());
            };
            if self.scope.field_is_typed(owner, name, &metadata)? || metadata.flags & 2 != 0 {
                return Ok(());
            }
            let rhs = node(rhs);
            if matches!(&rhs.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if name == "list"))
            {
                return Ok(());
            }
            let schema = self.schemas.find(self.body.tree(), owner, name);
            if let Some(kind) = schema.filter(|kind| **kind != Kind::Any) {
                let mut paths = Vec::new();
                path_literals(rhs, &mut paths);
                if let Some(path) = paths
                    .into_iter()
                    .find(|path| !Schemas::accepts_path(self.body.tree(), kind, path))
                {
                    let wanted = match kind {
                        Kind::Path(base) => format!("a path under {base}"),
                        Kind::Msg => "a /datum/msg path".into(),
                        _ => "a plain value".into(),
                    };
                    self.evidence.push(Evidence {
                        owner,
                        name,
                        rule: Rule::Schema,
                        at,
                        rejected_path: Some((path, wanted)),
                    });
                }
                return Ok(());
            }
            let rule = match self.scope.type_of(rhs)? {
                Some(path) if self.scope.is_ref(&path)? => Rule::Typed,
                Some(path)
                    if path.is_empty()
                        && matches!(&rhs.kind, ExprKind::Ident(local) if self.scope.locals.contains_key(local) && self.body.local_call(self.values, local)?) =>
                {
                    Rule::Call
                }
                Some(_) => return Ok(()),
                None if crate::value_program::is_call_result(rhs)
                    && !self.body.call_value(self.values, rhs, self.exempt)? =>
                {
                    Rule::Call
                }
                None => return Ok(()),
            };
            if schema == Some(&Kind::Any) && rule == Rule::Call {
                return Ok(());
            }
            self.evidence.push(Evidence {
                owner,
                name,
                rule,
                at,
                rejected_path: None,
            });
            Ok(())
        }
    }
    let mut scan = Scan {
        body,
        scope,
        values,
        schemas,
        exempt: exempt_types,
        evidence: Vec::new(),
        error: None,
    };
    crate::untyped_order::assignments(syntax.view(), &mut |target, rhs, at| {
        if scan.error.is_none() {
            if let Err(error) = scan.assign(target, rhs, at) {
                scan.error = Some(error);
            }
        }
    })
    .map_err(|e| Unsupported(e.into()))?;
    if let Some(error) = scan.error {
        Err(error)
    } else {
        Ok(scan.evidence)
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct Finding {
    pub rule: Rule,
    pub file: String,
    pub line: usize,
    pub message: String,
    pub identity: String,
}
fn relative(root: &std::path::Path, path: &std::path::Path) -> String {
    // Report-only filesystem equivalence. Keep original provider/origin keys;
    // only the shared safe ordinary-DOS/verbatim comparison may unify paths.
    dm_preprocess::regions::relative_filesystem_path(path, root)
        .as_deref()
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}
pub fn findings<'a>(
    frontend: &'a ColdFrontend,
    bodies: &BodyArena<'a>,
    values: &Values<'a>,
    schemas: &Schemas,
    root: &std::path::Path,
    exempt_types: &'a [String],
    exempt_file: impl Fn(&str) -> bool,
) -> Result<Vec<Finding>, Unsupported> {
    values.validate_live(frontend)?;
    values.validate_exempt_types(exempt_types)?;
    let mut grouped: BTreeMap<(SymbolId, SymbolId), (Rule, Vec<String>)> = BTreeMap::new();
    let tree = &frontend.snapshot.tree;
    let ordered = ordered_bodies(tree, &frontend.bodies)?;
    for (_, body) in ordered {
        let file = relative(root, &body.source.path);
        if exempt_file(&file) {
            continue;
        }
        bodies
            .with_parsed(body, |body| -> Result<(), Unsupported> {
                for evidence in body_evidence(frontend, body, values, schemas, exempt_types)? {
                    let source = frontend.location(evidence.at.start).ok_or_else(|| {
                        Unsupported("assignment has no native source origin".into())
                    })?;
                    record(&mut grouped, evidence, root, source);
                }
                Ok(())
            })
            .map_err(|error| Unsupported(error.message))??;
    }
    render(tree, grouped, root, &exempt_file, |declaration| {
        let Some(&occurrence) = frontend
            .snapshot
            .occurrences
            .for_target(dm_tree::Target::Member(declaration))
            .first()
        else {
            return Ok(None);
        };
        Ok(frontend
            .source_export_mapping()
            .and_then(|mapping| mapping.location_of(occurrence)))
    })
}

type Groups = BTreeMap<(SymbolId, SymbolId), (Rule, Vec<String>)>;
pub(crate) fn ordered_bodies<'a>(
    tree: &SemanticTree,
    bodies: &'a [BodyOccurrence],
) -> Result<Vec<(usize, &'a BodyOccurrence)>, Unsupported> {
    // Legacy diagnostics group by type encounter, then first callable-name
    // encounter, with a later authored formal body preceding its overrides.
    // This is report policy, not runtime dispatch or a second semantic model.
    let mut first_name = BTreeMap::new();
    for (at, target) in tree.declarations().iter().enumerate() {
        if let dm_tree::Target::Member(id) = target {
            let member = tree
                .member(*id)
                .ok_or_else(|| Unsupported("report declaration absent".into()))?;
            if matches!(
                member.kind,
                dm_tree::MemberKind::Proc | dm_tree::MemberKind::Verb
            ) {
                first_name.entry((member.owner, member.name)).or_insert(at);
            }
        }
    }
    let mut ordered = Vec::with_capacity(bodies.len());
    for (ordinal, body) in bodies.iter().enumerate() {
        let member = tree
            .member(body.member)
            .ok_or_else(|| Unsupported("report body member absent".into()))?;
        let first = first_name
            .get(&(member.owner, member.name))
            .copied()
            .ok_or_else(|| Unsupported("report callable encounter absent".into()))?;
        let occurrence = tree
            .member_occurrence(body.member)
            .ok_or_else(|| Unsupported("report callable occurrence absent".into()))?;
        ordered.push((
            (
                member.owner.index(),
                first,
                member.definition != dm_tree::DefinitionMode::Declare,
                occurrence,
                ordinal,
            ),
            body,
        ));
    }
    ordered.sort_by_key(|(key, _)| *key);
    Ok(ordered
        .into_iter()
        .map(|(key, body)| (key.4, body))
        .collect())
}

/// Same policy, report order and aggregation over the retained compiler archive.
/// The archive owns source mappings; no current filesystem reads are performed.
#[derive(Clone, Copy, Debug)]
pub enum PolicyAnchor {
    Assignment(Span),
    Declaration(dm_tree::MemberId),
}
pub fn archived_findings<'a>(
    archive: &'a BodyArchive,
    values: &Values<'a>,
    schemas: &Schemas,
    root: &std::path::Path,
    exempt_types: &'a [String],
    exempt_file: impl Fn(&str) -> bool,
) -> Result<Vec<Finding>, Unsupported> {
    archived_findings_projected(
        archive,
        values,
        schemas,
        root,
        exempt_types,
        exempt_file,
        |_, source| Ok(source),
    )
}
/// Same original policy/rendering with host-projected source coordinates.
/// The callback may normalize only coordinates of this issued source location;
/// encoding/capture authority remains the host's prerequisite.
pub fn archived_findings_projected<'a>(
    archive: &'a BodyArchive,
    values: &Values<'a>,
    schemas: &Schemas,
    root: &std::path::Path,
    exempt_types: &'a [String],
    exempt_file: impl Fn(&str) -> bool,
    project: impl Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>,
) -> Result<Vec<Finding>, Unsupported> {
    archived_findings_projected_with(
        archive,
        values,
        schemas,
        root,
        exempt_types,
        exempt_file,
        project,
        CompatibilityBodyDemand,
    )
}
/// Checked native demand over the same archived owner, policy and report order.
pub fn archived_findings_projected_checked<'a>(
    archive: &'a BodyArchive,
    values: &Values<'a>,
    schemas: &Schemas,
    root: &std::path::Path,
    exempt_types: &'a [String],
    exempt_file: impl Fn(&str) -> bool,
    project: impl Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>,
) -> Result<Vec<Finding>, crate::value_query::ValueQueryFailure> {
    archived_findings_projected_with(
        archive,
        values,
        schemas,
        root,
        exempt_types,
        exempt_file,
        project,
        CheckedBodyDemand,
    )
}
fn archived_findings_projected_with<'a, D: BodyDemand>(
    archive: &'a BodyArchive,
    values: &Values<'a>,
    schemas: &Schemas,
    root: &std::path::Path,
    exempt_types: &'a [String],
    exempt_file: impl Fn(&str) -> bool,
    project: impl Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>,
    demand: D,
) -> Result<Vec<Finding>, D::Failure> {
    values.validate_archive(archive)?;
    values.validate_exempt_types(exempt_types)?;
    let tree = archive.tree();
    let mut grouped = Groups::new();
    for (ordinal, occurrence) in ordered_bodies(tree, archive.occurrences())? {
        if exempt_file(&relative(root, &occurrence.source.path)) {
            continue;
        }
        demand.with_archived(archive, ordinal, |body| {
            for evidence in archived_body_evidence(archive, body, values, schemas, exempt_types)? {
                let source = archive
                    .location(evidence.at.start)
                    .ok_or_else(|| Unsupported("assignment has no native source origin".into()))?;
                let source = project(PolicyAnchor::Assignment(evidence.at), source)?;
                record(&mut grouped, evidence, root, source);
            }
            Ok(())
        })?;
    }
    render(tree, grouped, root, &exempt_file, |member| {
        archive
            .member_location(member)
            .map(|source| project(PolicyAnchor::Declaration(member), source))
            .transpose()
    })
    .map_err(Into::into)
}

fn record(
    grouped: &mut Groups,
    evidence: Evidence,
    root: &std::path::Path,
    source: SourceLocation,
) {
    let at = format!("{}:{}", relative(root, &source.path), source.line);
    let at = evidence.rejected_path.map_or(at.clone(), |(path, wanted)| {
        format!("{at} ({path} is not {wanted})")
    });
    let slot = grouped
        .entry((evidence.owner, evidence.name))
        .or_insert((evidence.rule, Vec::new()));
    if evidence.rule == Rule::Typed && slot.0 == Rule::Call {
        slot.0 = Rule::Typed;
    }
    if !slot.1.contains(&at) {
        slot.1.push(at);
    }
}

fn render(
    tree: &SemanticTree,
    grouped: Groups,
    root: &std::path::Path,
    exempt_file: &impl Fn(&str) -> bool,
    member_location: impl Fn(dm_tree::MemberId) -> Result<Option<SourceLocation>, Unsupported>,
) -> Result<Vec<Finding>, Unsupported> {
    let symbols = tree.symbols();
    let mut findings = Vec::new();
    for ((owner, name), (rule, at)) in grouped {
        let ty = tree
            .lookup_type(owner)
            .ok_or_else(|| Unsupported("finding owner missing".into()))?;
        let selected = tree
            .resolve(ty, name, dm_tree::MemberKind::Var)
            .ok_or_else(|| Unsupported("finding declaration missing".into()))?;
        let declaration = tree
            .override_chain_iter(selected)
            .find(|id| {
                tree.member(*id).is_some_and(|node| {
                    node.definition == dm_tree::DefinitionMode::Declare
                        && tree.type_node(node.owner).unwrap().path == owner
                })
            })
            .unwrap_or(selected);
        let source = member_location(declaration)?
            .ok_or_else(|| Unsupported("finding declaration origin missing".into()))?;
        let file = relative(root, &source.path);
        if !file.starts_with("code/") || exempt_file(&file) {
            continue;
        }
        let line = source.line;
        let owner = symbols
            .text(owner)
            .ok_or_else(|| Unsupported("owner spelling missing".into()))?;
        let name = symbols
            .text(name)
            .ok_or_else(|| Unsupported("field spelling missing".into()))?;
        let what = match rule {
            Rule::Typed => "an atom or datum",
            Rule::Call => "a call's result",
            Rule::Schema => "a value its SCHEMA refuses",
        };
        let shown = at.iter().take(8).cloned().collect::<Vec<_>>().join(", ");
        let more = if at.len() > 8 {
            format!(" and {} more", at.len() - 8)
        } else {
            String::new()
        };
        findings.push(Finding {
            rule,
            file,
            line,
            message: format!(
                "{}/var/{name} has no type and is assigned {what} at {shown}{more}",
                if owner == "/" { "" } else { owner }
            ),
            identity: format!("{owner}::{name}"),
        });
    }
    findings.sort_by(|a, b| {
        (&a.file, a.line, a.rule.name(), &a.message, &a.identity).cmp(&(
            &b.file,
            b.line,
            b.rule.name(),
            &b.message,
            &b.identity,
        ))
    });
    Ok(findings)
}

#[cfg(test)]
#[path = "untyped_native_tests.rs"]
mod tests;
