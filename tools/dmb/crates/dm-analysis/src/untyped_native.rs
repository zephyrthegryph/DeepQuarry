//! Native policy boundary under parity validation: value summaries and
//! schemas feed classification; baseline/ALLOW admission remains with Analyze.
use crate::native_program::{BodyDemand, CheckedBodyDemand, CompatibilityBodyDemand};
use crate::{
    untyped::{self, Unsupported},
    value_program::Values,
    value_schemas::{Kind, Schemas},
};
use dm_ir::{ProcedureIdentity, Resolver, SymbolId};
use dm_syntax::{Expr, ExprKind, Span};
use dm_tree::frontend::{
    ArchivedBody, BodyArchive, BodyArena, BodyOccurrence, BodySyntaxFailure, ColdFrontend, CurrentArchivedBody, ParsedBody, SourceLocation,
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
fn path_literals(node:&Expr,out:&mut Vec<String>){match path_literals_using(node,out,&mut LegacyWork){Ok(())=>(),Err(_)=>unreachable!("noop legacy work cannot fail")}}
fn path_literals_using<W:crate::policy_body_demand::WorkspaceWork>(node_:&Expr,out:&mut Vec<String>,work:&mut W)->Result<(),W::Error>{work.checkpoint()?;match &untyped::ungroup_using(node_,&mut||work.checkpoint())?.kind{ExprKind::TypePath(path)=>{if W::CHECKED{let width=path.len().checked_add(128).ok_or_else(||work.overflow())?;work.retain(width)?;out.try_reserve(1).map_err(|_|work.allocation_failed())?;}out.push(path.clone())},ExprKind::Conditional{then_value,else_value,..}=>{path_literals_using(then_value,out,work)?;path_literals_using(else_value,out,work)?;},_=>()}Ok(())}
struct LegacyWork;impl crate::policy_body_demand::WorkspaceWork for LegacyWork{type Error=Unsupported;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Unsupported>{Ok(())}fn retain(&mut self,_:usize)->Result<(),Unsupported>{Ok(())}fn temporary(&mut self,_:usize)->Result<(),Unsupported>{Ok(())}fn overflow(&mut self)->Unsupported{Unsupported("legacy untyped geometry".into())}fn allocation_failed(&mut self)->Unsupported{Unsupported("legacy untyped allocation".into())}fn body<'a>(&mut self,a:&'a BodyArchive,n:usize)->Result<ArchivedBody<'a>,Unsupported>{a.parse(n).map_err(|e|Unsupported(e.message))}}
fn evidence_row<W:crate::policy_body_demand::WorkspaceWork>(rows:&mut Vec<Evidence>,work:&mut W)->Result<(),W::Error>{if W::CHECKED&&rows.len()==rows.capacity(){let max=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||work.overflow())?;let bytes=max.checked_mul(std::mem::size_of::<Evidence>()).and_then(|n|n.checked_add(128)).ok_or_else(||work.overflow())?;work.retain(bytes)?;rows.try_reserve_exact(max-rows.len()).map_err(|_|work.allocation_failed())?;if rows.capacity()>max.checked_mul(2).ok_or_else(||work.overflow())?{return Err(work.allocation_failed())}}Ok(())}

enum PolicyBody<'a> {
    Live(&'a ColdFrontend, &'a ParsedBody<'a>),
    Archive(&'a BodyArchive, &'a ArchivedBody<'a>),
    Current(&'a BodyArchive, ProcedureIdentity),
}
impl<'a> PolicyBody<'a> {
    fn tree(&self) -> &'a SemanticTree {
        match self {
            Self::Live(f, _) => &f.snapshot.tree,
            Self::Archive(a, _) | Self::Current(a, _) => a.tree(),
        }
    }
    fn has_field(&self, values: &Values<'a>, name: &str) -> Result<bool, Unsupported> {
        match self {
            Self::Live(f, _) => values.has_field_name(f, name),
            Self::Archive(a, _) | Self::Current(a, _) => values.archive_has_field_name(a, name),
        }
    }
    fn local_call_using<W: crate::policy_body_demand::WorkspaceWork>(
        &self, values: &Values<'a>, name: &str, work: &mut W,
    ) -> Result<bool, W::Error> {
        work.checkpoint()?;
        match self {
            Self::Live(frontend, body) => values.local_holds_call(frontend, body, name).map_err(W::Error::from),
            Self::Archive(_, body) => values.archive_local_holds_call_using(body, name, work),
            Self::Current(_, current) => values.policy_local_holds_call_using(*current, name, work),
        }
    }

    fn call_value_using<W: crate::policy_body_demand::WorkspaceWork>(
        &self, values: &Values<'a>, scope: &untyped::Walker<'a, dyn Resolver + 'a>,
        expression: &Expr, exempt: &'a [String], work: &mut W,
    ) -> Result<bool, W::Error> {
        work.checkpoint()?;
        match self {
            Self::Live(frontend, body) => values.call_is_value(frontend, body, expression, exempt).map_err(W::Error::from),
            Self::Archive(_, body) => values.archive_call_is_value_using(body, expression, exempt, work),
            Self::Current(_, current) => values.policy_call_is_value_using(*current, scope, expression, work),
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

pub fn archived_body_evidence_using<'a,W:crate::policy_body_demand::WorkspaceWork>(archive:&'a BodyArchive,body:&'a ArchivedBody<'a>,values:&Values<'a>,schemas:&Schemas,exempt_types:&'a[String],work:&mut W)->Result<Vec<Evidence>,W::Error>{work.checkpoint()?;if !body.belongs_to(archive){return Err("policy body belongs to another archive issuance".into())}values.validate_archive(archive)?;values.validate_exempt_types(exempt_types)?;let scope=untyped::archived_scope_using(body,values.resolver(),exempt_types,work)?;evidence_using(PolicyBody::Archive(archive,body),body.statement_body(),scope,values,schemas,exempt_types,work)}

fn evidence<'a>(
    body: PolicyBody<'a>,
    syntax: &StatementBody,
    scope: untyped::Walker<'a, dyn Resolver + 'a>,
    values: &Values<'a>,
    schemas: &Schemas,
    exempt_types: &'a [String],
) -> Result<Vec<Evidence>, Unsupported> {
    evidence_using(body,syntax,scope,values,schemas,exempt_types,&mut LegacyWork)
}
fn evidence_using<'a,W:crate::policy_body_demand::WorkspaceWork>(body:PolicyBody<'a>,syntax:&StatementBody,scope:untyped::Walker<'a,dyn Resolver + 'a>,values:&Values<'a>,schemas:&Schemas,exempt_types:&'a[String],work:&mut W)->Result<Vec<Evidence>,W::Error>{
    struct Scan<'a, 'c, 'w, W:crate::policy_body_demand::WorkspaceWork> {
        body: PolicyBody<'a>,
        scope: untyped::Walker<'a, dyn Resolver + 'a>,
        values: &'c Values<'a>,
        schemas: &'c Schemas,
        exempt: &'a [String],
        evidence: Vec<Evidence>,
        work:&'w mut W,
    }
    impl<W:crate::policy_body_demand::WorkspaceWork> Scan<'_, '_, '_, W> {
        fn assign(&mut self, target: &Expr, rhs: &Expr, at: Span) -> Result<(), W::Error> {
            self.work.checkpoint()?;
            let name = match &untyped::ungroup_using(target,&mut||self.work.checkpoint())?.kind {
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
            let Some((owner, name, metadata)) = self.scope.place_using(target,&mut||self.work.checkpoint())? else {
                return Ok(());
            };
            if self.scope.field_is_typed_using(owner,name,&metadata,&mut||self.work.checkpoint())? || metadata.flags & 2 != 0 {
                return Ok(());
            }
            let rhs = untyped::ungroup_using(rhs,&mut||self.work.checkpoint())?;
            if matches!(&rhs.kind, ExprKind::Call { callee, .. } if matches!(&callee.kind, ExprKind::Ident(name) if name == "list"))
            {
                return Ok(());
            }
            let schema = self.schemas.find_using(self.body.tree(),owner,name,&mut||self.work.checkpoint())?;
            if let Some(kind) = schema.filter(|kind| **kind != Kind::Any) {
                let mut paths = Vec::new();
                path_literals_using(rhs,&mut paths,self.work)?;
                let mut rejected=None;for path in paths{self.work.checkpoint()?;if !Schemas::accepts_path_using(self.body.tree(),kind,&path,&mut||self.work.checkpoint())?{rejected=Some(path);break}}
                if let Some(path)=rejected {
                    if W::CHECKED{let width=path.len().checked_add(match kind{Kind::Path(base)=>base.len(),_=>128}).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128)).ok_or_else(||self.work.overflow())?;self.work.retain(width)?;}
                    let wanted = match kind {
                        Kind::Path(base) => format!("a path under {base}"),
                        Kind::Msg => "a /datum/msg path".into(),
                        _ => "a plain value".into(),
                    };
                    evidence_row(&mut self.evidence,self.work)?;
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
            let rule = match self.scope.type_of_using(rhs,&mut||self.work.checkpoint())? {
                Some(path) if self.scope.is_ref_using(&path,&mut||self.work.checkpoint())? => Rule::Typed,
                Some(path)
                    if path.is_empty()
                        && matches!(&rhs.kind, ExprKind::Ident(local) if self.scope.locals.contains_key(local) && self.body.local_call_using(self.values,local,self.work)?) =>
                {
                    Rule::Call
                }
                Some(_) => return Ok(()),
                None if crate::value_program::is_call_result(rhs)
                    && !self.body.call_value_using(self.values,&self.scope,rhs,self.exempt,self.work)? =>
                {
                    Rule::Call
                }
                None => return Ok(()),
            };
            if schema == Some(&Kind::Any) && rule == Rule::Call {
                return Ok(());
            }
            evidence_row(&mut self.evidence,self.work)?;
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
        work,
    };
    let observed=crate::untyped_order::try_assignments_current(syntax.view(),&mut scan,&mut|scan|scan.work.checkpoint(),&mut|scan,target,rhs,at,_|scan.assign(target,rhs,at));
    match observed{Ok(())=>Ok(scan.evidence),Err(crate::untyped_order::PolicyVisitFailure::Callback(actual))=>Err(actual),Err(crate::untyped_order::PolicyVisitFailure::Unsupported(message))=>Err(Unsupported(message.into()).into())}
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
    ordered_bodies_using(tree,bodies,&mut||Ok::<(),Unsupported>(()))
}
pub(crate) fn ordered_bodies_using<'a,E:From<Unsupported>>(tree:&SemanticTree,bodies:&'a [BodyOccurrence],checkpoint:&mut impl FnMut()->Result<(),E>)->Result<Vec<(usize,&'a BodyOccurrence)>,E>{
    // Legacy diagnostics group by type encounter, then first callable-name
    // encounter, with a later authored formal body preceding its overrides.
    // This is report policy, not runtime dispatch or a second semantic model.
    let mut first_name = BTreeMap::new();
    for (at, target) in tree.declarations().iter().enumerate() {
        checkpoint()?;
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
        checkpoint()?;
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
    crate::checker_order::sort_source_order(&mut ordered,&mut|a,b|->Result<std::cmp::Ordering,E>{checkpoint()?;Ok(a.0.cmp(&b.0))})?;
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

/// Full authentic archive traversal on the existing compatibility BODY role.
pub fn archived_findings_workspace_using<'a, W: crate::policy_body_demand::WorkspaceWork>(
    archive: &'a BodyArchive, values: &Values<'a>, schemas: &Schemas, root: &std::path::Path,
    exempt_types: &'a [String], exempt_file: impl Fn(&str) -> bool,
    project: impl Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>, work: &mut W,
) -> Result<Vec<Finding>, W::Error> {
    workspace_findings_using(archive, values, root, exempt_types, exempt_file, project, work,
        |ordinal, occurrence, width, max_path, grouped, project, work| {
            let body = work.body(archive, ordinal)?;
            if !body.belongs_to(archive) || !std::ptr::eq(body.occurrence(), occurrence) {
                return Err("untyped host returned foreign original body loan".into());
            }
            if W::CHECKED {
                let locals = body.source_locals().map_err(Unsupported)?.scope_admission().map_err(Unsupported)?;
                charge_body(occurrence, width, max_path, locals, work)?;
            }
            let rows = archived_body_evidence_using(archive, &body, values, schemas, exempt_types, work)?;
            record_body(archive, rows, grouped, root, project, work)
        })
}

/// Only the host can produce the actual scoped canonical product; this loan
/// can neither outlive the visit nor fall back to the compatibility body.
pub trait CurrentFindingWork: crate::policy_body_demand::WorkspaceWork {
    fn with_current_body<'a>(
        &mut self, archive: &'a BodyArchive, ordinal: usize,
        use_body: impl for<'syntax> FnOnce(
            &mut Self, CurrentArchivedBody<'a, 'syntax>, &dm_syntax::SettingAdmission<'_>,
        ) -> Result<(), Self::Error>,
    ) -> Result<(), Self::Error>;
    fn syntax_failure(&mut self, error: BodySyntaxFailure) -> Self::Error;
}

pub fn current_findings_workspace_using<'a, W: CurrentFindingWork>(
    archive: &'a BodyArchive, values: &Values<'a>, schemas: &Schemas, root: &std::path::Path,
    exempt_types: &'a [String], exempt_file: impl Fn(&str) -> bool,
    project: impl Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>, work: &mut W,
) -> Result<Vec<Finding>, W::Error> {
    workspace_findings_using(archive, values, root, exempt_types, exempt_file, project, work,
        |ordinal, occurrence, width, max_path, grouped, project, work| {
            work.with_current_body(archive, ordinal, |work, body, admission| {
                if !body.belongs_to(archive) || !std::ptr::eq(body.occurrence(), occurrence) {
                    return Err("untyped host returned foreign canonical original body loan".into());
                }
                let current = values.current_body_identity(&body)?;
                let locals = body.source_locals(admission).map_err(|error| work.syntax_failure(error))?;
                if W::CHECKED {
                    charge_body(occurrence, width, max_path, locals.scope_admission().map_err(Unsupported)?, work)?;
                }
                let parameters = body.source_parameters(admission).map_err(|error| work.syntax_failure(error))?;
                let syntax = body.syntax().canonical_statement_storage();
                let scope = untyped::scope_from_parameters_using(
                    archive.tree(), occurrence, syntax, values.resolver(), exempt_types,
                    Some(parameters), Some(locals), work,
                )?.with_archive(archive)?;
                let mut rows = evidence_using(PolicyBody::Current(archive, current), syntax, scope,
                    values, schemas, exempt_types, work)?;
                for row in &mut rows {
                    work.checkpoint()?;
                    // The policy walker projected nested setting RHS anchors
                    // into the canonical BODY. Apply the outer binding once.
                    row.at = body.syntax().projection().span(row.at)
                        .ok_or("untyped assignment escapes its canonical body projection")?;
                    body.current_source(row.at).map_err(|error| work.syntax_failure(error))?;
                }
                record_body(archive, rows, grouped, root, project, work)
            })
        })
}

fn charge_body<W: crate::policy_body_demand::WorkspaceWork>(
    occurrence: &BodyOccurrence, width: usize, max_path: usize, locals: usize, work: &mut W,
) -> Result<(), W::Error> {
    let span = occurrence.expanded_span;
    let bytes = span.end.checked_sub(span.start).and_then(|n| n.checked_add(1))
        .and_then(|n| n.checked_mul(width)).and_then(|n| n.checked_mul(32))
        .and_then(|n| n.checked_add(locals)).and_then(|n| n.checked_add(max_path.checked_mul(128)?))
        .and_then(|n| n.checked_add(16384)).ok_or_else(|| work.overflow())?;
    work.temporary(bytes)
}

fn record_body<W: crate::policy_body_demand::WorkspaceWork>(
    archive: &BodyArchive, rows: Vec<Evidence>, grouped: &mut Groups, root: &std::path::Path,
    project: &dyn Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>,
    work: &mut W,
) -> Result<(), W::Error> {
    for value in rows {
        work.checkpoint()?;
        let source = archive.location(value.at.start)
            .ok_or_else(|| Unsupported("assignment has no native source origin".into()))?;
        let source = project(PolicyAnchor::Assignment(value.at), source)?;
        record_using(grouped, value, root, source, work)?;
    }
    Ok(())
}

fn workspace_findings_using<'a, W: crate::policy_body_demand::WorkspaceWork>(
    archive: &'a BodyArchive, values: &Values<'a>, root: &std::path::Path, exempt_types: &'a [String],
    exempt_file: impl Fn(&str) -> bool,
    project: impl Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>,
    work: &mut W,
    mut visit: impl FnMut(usize, &'a BodyOccurrence, usize, usize, &mut Groups,
        &dyn Fn(PolicyAnchor, SourceLocation) -> Result<SourceLocation, Unsupported>, &mut W) -> Result<(), W::Error>,
) -> Result<Vec<Finding>, W::Error> {
    work.checkpoint()?;
    values.validate_archive(archive)?;
    values.validate_exempt_types(exempt_types)?;
    let tree = archive.tree();
    let mut grouped = Groups::new();
    let mut width = 128usize;
    let mut max_path = root.as_os_str().len();
    if W::CHECKED {
        for ty in tree.types() {
            work.checkpoint()?;
            width = width.max(tree.symbols().text(ty.path).ok_or("untyped owner spelling unavailable")?.len());
        }
        for body in archive.occurrences() {
            work.checkpoint()?;
            max_path = max_path.max(body.source.path.as_os_str().len());
        }
        let bytes = tree.members().len().checked_add(tree.types().len()).and_then(|n| n.checked_add(archive.len()))
            .and_then(|n| n.checked_mul(width.checked_add(2048)?))
            .and_then(|n| n.checked_add(max_path.checked_mul(128)?)).and_then(|n| n.checked_add(16384))
            .ok_or_else(|| work.overflow())?;
        work.temporary(bytes)?;
    }
    for (ordinal, occurrence) in ordered_bodies_using(tree, archive.occurrences(), &mut || work.checkpoint())? {
        work.checkpoint()?;
        if exempt_file(&relative(root, &occurrence.source.path)) { continue; }
        visit(ordinal, occurrence, width, max_path, &mut grouped, &project, work)?;
    }
    render_using(tree, grouped, root, &exempt_file,
        |member| archive.member_location(member).map(|source| project(PolicyAnchor::Declaration(member), source)).transpose(),
        work)
}

fn record(
    grouped: &mut Groups,
    evidence: Evidence,
    root: &std::path::Path,
    source: SourceLocation,
) {
    match record_using(grouped,evidence,root,source,&mut LegacyWork){Ok(())=>(),Err(_)=>unreachable!("noop legacy recording cannot fail")}
}
fn record_using<W:crate::policy_body_demand::WorkspaceWork>(grouped:&mut Groups,evidence:Evidence,root:&std::path::Path,source:SourceLocation,work:&mut W)->Result<(),W::Error>{
    work.checkpoint()?;if W::CHECKED{let extra=evidence.rejected_path.as_ref().map_or(Some(0),|(path,wanted)|path.len().checked_add(wanted.len()));let width=source.path.as_os_str().len().checked_add(root.as_os_str().len()).and_then(|n|n.checked_mul(128)).and_then(|n|n.checked_add(extra?)).and_then(|n|n.checked_add(4096)).ok_or_else(||work.overflow())?;work.retain(width)?;}
    let at = format!("{}:{}", relative(root, &source.path), source.line);
    let at = evidence.rejected_path.map_or(at.clone(), |(path, wanted)| {
        format!("{at} ({path} is not {wanted})")
    });
    if W::CHECKED&&!grouped.contains_key(&(evidence.owner,evidence.name)){work.retain(2048)?;}
    let slot = grouped
        .entry((evidence.owner, evidence.name))
        .or_insert((evidence.rule, Vec::new()));
    if evidence.rule == Rule::Typed && slot.0 == Rule::Call {
        slot.0 = Rule::Typed;
    }
    if !slot.1.contains(&at) {
        if W::CHECKED{slot.1.try_reserve(1).map_err(|_|work.allocation_failed())?;}
        slot.1.push(at);
    }
    work.checkpoint()
}

fn render(
    tree: &SemanticTree,
    grouped: Groups,
    root: &std::path::Path,
    exempt_file: &impl Fn(&str) -> bool,
    member_location: impl Fn(dm_tree::MemberId) -> Result<Option<SourceLocation>, Unsupported>,
) -> Result<Vec<Finding>, Unsupported> {
    render_using(tree,grouped,root,exempt_file,member_location,&mut LegacyWork)
}
fn render_using<W:crate::policy_body_demand::WorkspaceWork>(tree:&SemanticTree,grouped:Groups,root:&std::path::Path,exempt_file:&impl Fn(&str)->bool,member_location:impl Fn(dm_tree::MemberId)->Result<Option<SourceLocation>,Unsupported>,work:&mut W)->Result<Vec<Finding>,W::Error>{
    let symbols = tree.symbols();
    let mut findings = Vec::new();
    for ((owner, name), (rule, at)) in grouped {
        work.checkpoint()?;
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
        if W::CHECKED{let width=at.iter().take(8).try_fold(0usize,|n,s|n.checked_add(s.len())).and_then(|n|n.checked_add(owner.len())).and_then(|n|n.checked_add(name.len())).and_then(|n|n.checked_add(file.len())).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(2048)).ok_or_else(||work.overflow())?;work.retain(width)?;findings.try_reserve(1).map_err(|_|work.allocation_failed())?;}
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
    crate::checker_order::sort_source_order(&mut findings,&mut|a,b|->Result<std::cmp::Ordering,W::Error>{work.checkpoint()?;Ok((&a.file,a.line,a.rule.name(),&a.message,&a.identity).cmp(&(&b.file,b.line,b.rule.name(),&b.message,&b.identity)))})?;
    work.checkpoint()?;Ok(findings)
}

#[cfg(test)]
#[path = "untyped_native_tests.rs"]
mod tests;
