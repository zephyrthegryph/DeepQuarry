//! Pinned private/protected variable producer categories over ORIGINAL owners.
//! SpacemanDMM0290db5c752fa292f9824521515b603a2afd11dc (GPL-3.0):
//! parser.rs1755/1761; dreamchecker lib.rs984-1033 and2120-2138.
//! Unsupported byte origins abort atomically; in particular LINE-only macro
//! receipts never fabricate a definition-note column. Not a full checker.
//! The strict native inherited-var-declaration error domain also requires a
//! dedicated original diagnostic-preparation receipt. The old-positive fixture
//! remains unsupported, never a clean or matched result, until that lands.

/// Producer inventory, not an all-source or full-checker admission receipt.
/// Every producer of each listed registered tag is implemented; unsupported
/// syntax/origins abort the request rather than silently reducing this set.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Coverage {
    pub registered_tags: &'static [&'static str],
    pub producer_categories: &'static [&'static str],
    pub all_registered_producers: bool,
    pub all_source_contexts_supported: bool,
    pub full_checker_parity: bool,
}
pub const COVERAGE: Coverage = Coverage {
    registered_tags: &["private_var", "protected_var", "final_var"],
    producer_categories: &["parser_locals", "global_declarations", "evaluated_fields"],
    all_registered_producers: true,
    all_source_contexts_supported: false,
    full_checker_parity: false,
};
#[cfg(test)]
mod coverage_tests {
    #[test]
    fn complete_variable_producer_inventory_is_not_full_source_or_checker_parity() {
        let coverage = super::COVERAGE;
        assert_eq!(
            coverage.registered_tags,
            ["private_var", "protected_var", "final_var"]
        );
        assert_eq!(
            coverage.producer_categories,
            ["parser_locals", "global_declarations", "evaluated_fields"]
        );
        assert!(coverage.all_registered_producers);
        assert!(!coverage.all_source_contexts_supported);
        assert!(!coverage.full_checker_parity);
    }
}

use crate::{
    check_policy::{CheckerPolicy, DiagnosticSeverity},
    checker_expression_visit::{Event, Walk},
    checks::{Diagnostic, Note, Severity},
};
use dm_ir::{PackedU128, Resolver, SymbolId, TypeId};
use dm_tree::{
    frontend::{ArchivedBody, BodyArchive, SourceNoteOrigin},
    DefinitionMode, MemberId, MemberKind, SemanticTree,
};
const PRIVATE: u8 = 32;
const PROTECTED: u8 = 64;
const FINAL: u8 = 16;
const MAX_FINDINGS: usize = 10_000;
fn append(out: &mut Vec<Produced>, rows: Vec<Produced>) -> Result<(), String> {
    if out
        .len()
        .checked_add(rows.len())
        .is_none_or(|n| n > MAX_FINDINGS)
    {
        return Err("visibility exceeds existing finding admission".into());
    }
    out.extend(rows);
    Ok(())
}
fn check_count(out: &[Produced]) -> Result<(), String> {
    if out.len() > MAX_FINDINGS {
        Err("visibility exceeds existing finding admission".into())
    } else {
        Ok(())
    }
}
fn enabled(policy: &CheckerPolicy, site: Site) -> bool {
    policy.register(site.tag(), site.default()).is_some()
}

/// These are the original producer registrations, not a caller-supplied default.
#[derive(Clone, Copy)]
enum Site {
    LocalPrivate,
    LocalProtected,
    OverridePrivate,
    OverrideFinal,
    Redeclaration,
    FieldPrivate,
    FieldProtected,
}
impl Site {
    fn family(self) -> &'static str {
        match self {
            Self::LocalPrivate | Self::OverridePrivate | Self::FieldPrivate => "private_var",
            Self::LocalProtected | Self::FieldProtected => "protected_var",
            Self::OverrideFinal => "final_var",
            Self::Redeclaration => "variable_redeclaration",
        }
    }
    fn tag(self) -> Option<&'static str> {
        if matches!(self, Self::Redeclaration) {
            None
        } else {
            Some(self.family())
        }
    }
    fn default(self) -> DiagnosticSeverity {
        if matches!(
            self,
            Self::OverridePrivate | Self::OverrideFinal | Self::Redeclaration
        ) {
            DiagnosticSeverity::Error
        } else {
            DiagnosticSeverity::Warning
        }
    }
}
/// No public constructor: every default severity/tag comes from its real site.
pub struct Produced {
    site: Site,
    diagnostic: Diagnostic,
    origin: SourceNoteOrigin,
}
impl Produced {
    pub(crate) fn into_original_parts(self)->(Diagnostic,Option<&'static str>,DiagnosticSeverity){let tag=self.site.tag();let level=self.site.default();(self.diagnostic,tag,level)}
    pub fn diagnostic(&self) -> &Diagnostic {
        &self.diagnostic
    }
    pub fn origin(&self) -> &SourceNoteOrigin {
        &self.origin
    }
    pub fn registration_tag(&self) -> Option<&'static str> {
        self.site.tag()
    }
    pub fn default_severity(&self) -> DiagnosticSeverity {
        self.site.default()
    }
}
pub struct Configured {
    pub finding: Produced,
    pub severity: DiagnosticSeverity,
}
fn produced(
    site: Site,
    origin: SourceNoteOrigin,
    span: dm_syntax::Span,
    expression_span: dm_syntax::Span,
    message: String,
    notes: Vec<Note>,
) -> Produced {
    let severity = match site.default() {
        DiagnosticSeverity::Error => Severity::Error,
        _ => Severity::Warning,
    };
    Produced {
        site,
        origin,
        diagnostic: Diagnostic {
            family: site.family(),
            severity,
            span,
            expression_span,
            message,
            notes,
        },
    }
}
fn text(tree: &SemanticTree, id: SymbolId) -> Result<&str, String> {
    tree.symbols()
        .text(id)
        .ok_or_else(|| "visibility native spelling unavailable".into())
}
fn point(archive: &BodyArchive, member: MemberId) -> Result<SourceNoteOrigin, String> {
    let cursor = archive.member_policy_compatibility_cursor(member)?;
    let Some(byte_column) = cursor.byte_column else {
        // A genuine native token receipt may supply an invocation byte point;
        // a LINE receipt by itself still supplies no column.
        return archive.member_source_note_point(member);
    };
    Ok(SourceNoteOrigin {
        path: cursor.path,
        line: cursor.line,
        byte_column,
    })
}
fn own_formal(
    tree: &SemanticTree,
    mut id: MemberId,
    owner: TypeId,
) -> Result<Option<MemberId>, String> {
    loop {
        let node = tree
            .member(id)
            .ok_or("visibility ancestor entry unavailable")?;
        if node.owner != owner {
            return Ok(None);
        }
        match node.definition {
            DefinitionMode::Declare if node.metadata.inherited_opaque().is_none() => {
                return Ok(Some(id))
            }
            DefinitionMode::Override => (),
            DefinitionMode::Declare if node.metadata.inherited_opaque().is_some() => return Ok(None),
            _ => return Err("visibility own-entry declaration mode unavailable".into()),
        }
        let Some(previous) = node.previous else {
            return Ok(None);
        };
        id = previous;
    }
}
/// Parser diagnostics happen for ALL parsed locals, before reachability walks.
fn parser_locals(
    archive: &BodyArchive,
    body: &ArchivedBody<'_>,
    policy: &CheckerPolicy,
) -> Result<Vec<Produced>, String> {
    if !body.belongs_to(archive) {
        return Err("visibility parser body belongs to another archive".into());
    }
    let syntax = body.statement_body();
    if !syntax.syntax_complete() {
        return Err("visibility local grammar coverage incomplete".into());
    }
    let mut out = Vec::new();
    for local in syntax
        .parsed()
        .local_variables
        .entries()
        .map_err(str::to_owned)?
    {
        if local.source_kind == dm_syntax::LocalSourceKind::CatchBinding {
            continue;
        }
        for (bit, site, name) in [
            (PRIVATE, Site::LocalPrivate, "SpacemanDMM_private"),
            (PROTECTED, Site::LocalProtected, "SpacemanDMM_protected"),
        ] {
            if local.source_modifiers & bit != 0 && enabled(policy, site) {
                if out.len() >= MAX_FINDINGS {
                    return Err("visibility exceeds existing finding admission".into());
                }
                out.push(produced(
                    site,
                    archive.source_note_point(local.anchor.start)?,
                    local.anchor,
                    local.anchor,
                    format!("var/{name} has no effect here"),
                    Vec::new(),
                ));
            }
        }
    }
    check_count(&out)?;
    Ok(out)
}
fn declarations<E: From<String> + for<'a> From<&'a str>>(
    archive:&BodyArchive,profile:PackedU128,policy:&CheckerPolicy,
    checkpoint:&mut impl FnMut()->Result<(),E>,
)->Result<Vec<Produced>,E>{
 let mut out=Vec::new();visit_declarations_using(archive,profile,policy,checkpoint,&mut|_|Ok(()),&|message|E::from(message),&mut|row|{if out.len()>=MAX_FINDINGS{return Err("visibility exceeds existing finding admission".into())}out.push(row);Ok(())})?;Ok(out)
}
fn visit_declarations_using<E: From<String> + for<'a> From<&'a str>>(
    archive: &BodyArchive,
    profile: PackedU128,
    policy: &CheckerPolicy,
    checkpoint: &mut impl FnMut() -> Result<(), E>,
    reserve: &mut impl FnMut(usize)->Result<(),E>,
    resource: &impl Fn(&'static str)->E,
    emit: &mut impl FnMut(Produced)->Result<(),E>,
) -> Result<(), E> {
    let tree = archive.tree();
    tree.validate_checker_builtin_profile(profile)
        .map_err(|e| format!("visibility profile: {e:?}"))?;
    let catalog = dm_tree::checker_builtins::pinned_catalog()
        .map_err(|e| format!("visibility catalog: {e:?}"))?;
    // This is an inspected, hash-verified inventory absence. Unknown metadata
    // cannot silently be interpreted as no private/protected/final builtins.
    // Value-only overrides have no declaration flags by construction; the
    // actual pinned declaration producer is checked, not missing flags as zero.
    if catalog.profile != profile
        || catalog.declarations.iter().any(|r| {
            r.kind == MemberKind::Var
                && r.definition == DefinitionMode::Declare
                && r.reference_flags.is_none_or(|f| f & 112 != 0)
        })
    {
        return Err("visibility builtin flag/note domain unavailable".into());
    }
    let mut types=declaration_buffer::<(&str,TypeId),E>(tree.types().len(),reserve,resource)?;
    for(index,node)in tree.types().iter().enumerate(){checkpoint()?;types.push((text(tree,node.path)?,TypeId(u32::try_from(index).map_err(|_|resource("visibility type ordinal overflow"))?)));}
    // Pinned check_var_defs uses objtree.iter_types(), i.e. graph node creation
    // order (objtree.rs668-674), not root().recurse() or lexical path order.
    // The authentic Original seed preserves builtin declaration encounter order;
    // the same native builder then ensures source paths/ancestors in encounter
    // order. Keep this actual native type arena order without sorting it.
    let mut widest_source=0usize;for(path,_)in archive.source_mapping().source_acquisitions(){checkpoint()?;widest_source=widest_source.max(path.as_os_str().len());}

    let mut own=Vec::new();let mut own_funded=0usize;
    for (_, owner) in types {
        checkpoint()?;
        let node = tree
            .type_node(owner)
            .ok_or("visibility owner unavailable")?;
        let path = text(tree, node.path)?;
        own.clear();declaration_grow(&mut own,node.members.len(),&mut own_funded,reserve,resource)?;
        for &id in node.members.iter(){checkpoint()?;let m=tree.member(id).ok_or("visibility own field unavailable")?;if m.kind==MemberKind::Var&&m.owner==owner{own.push((text(tree,m.name)?,m.name));}}
        crate::checker_order::sort_source_order(&mut own,&mut|left,right|->Result<std::cmp::Ordering,E>{checkpoint()?;Ok(left.0.cmp(right.0))})?;own.dedup_by(|right,left|right.0==left.0);
        let mut parent = tree.parent(owner);
        while let Some(parent_id) = parent {
            checkpoint()?;
            let ancestor = tree
                .type_node(parent_id)
                .ok_or("visibility ancestor unavailable")?;
            if ancestor.path == SymbolId::of("/") {
                break;
            }
            for (index, &(name, symbol)) in own.iter().enumerate() {
                if index % 256 == 0 {
                    checkpoint()?;
                }
                if name == "vars" || (path == "/client" && name == "parent_type") {
                    continue;
                }
                let current = tree
                    .resolve(owner, symbol, MemberKind::Var)
                    .ok_or("visibility current field unavailable")?;
                let current_node = tree
                    .member(current)
                    .ok_or("visibility current member unavailable")?;
                if current_node.owner != owner {
                    return Err("visibility own roster selected inherited entry".into());
                }
                let Some(parent_latest) = tree.resolve(parent_id, symbol, MemberKind::Var) else {
                    continue;
                };
                let Some(formal) = own_formal(tree, parent_latest, parent_id)? else {
                    continue;
                };
                let flags = archive.checker_variable_qualifiers(formal, profile)?;
                let mydecl = own_formal(tree, current, owner)?;
                let report_redeclaration = mydecl.is_some() && enabled(policy, Site::Redeclaration);
                let report_final = flags & FINAL != 0 && enabled(policy, Site::OverrideFinal);
                let report_private = flags & PRIVATE != 0 && enabled(policy, Site::OverridePrivate);
                if !report_redeclaration && !report_final && !report_private {
                    continue;
                }
                // Fund real path/note/message construction before point()
                // allocates an owned SourceNoteOrigin. The visitor never owns
                // a second source roster or a parsed-body projection.
                let width=path.len().checked_add(name.len()).and_then(|n|n.checked_add(text(tree,ancestor.path).ok()?.len())).and_then(|n|n.checked_add(widest_source)).ok_or_else(||resource("global declaration row width overflow"))?;
                let bound=width.checked_mul(32).and_then(|n|n.checked_add(4096)).ok_or_else(||resource("global declaration row capacity overflow"))?;reserve(bound)?;
                let note = point(archive, formal)?;
                let current_span = archive.member_primary_policy_span(current)?;
                if let Some(mydecl) = mydecl.filter(|_| report_redeclaration) {
                    let span = archive.member_primary_policy_span(mydecl)?;
                    emit(produced(
                        Site::Redeclaration,
                        point(archive, mydecl)?,
                        span,
                        span,
                        format!("{path} redeclares var {name:?}"),
                        vec![Note {
                            message: format!("declared on {} here", text(tree, ancestor.path)?),
                            source: Some(note.clone()),
                        }],
                    ))?;
                }
                for (bit, site, kind) in [
                    (FINAL, Site::OverrideFinal, "final"),
                    (PRIVATE, Site::OverridePrivate, "private"),
                ] {
                    if flags & bit != 0 && enabled(policy, site) {
                        emit(produced(
                            site,
                            point(archive, current)?,
                            current_span,
                            current_span,
                            format!("{path} overrides {kind} var {name:?}"),
                            vec![Note {
                                message: format!(
                                    "declared {kind} on {} here",
                                    text(tree, ancestor.path)?
                                ),
                                source: Some(note.clone()),
                            }],
                        ))?;
                    }
                }
            }
            parent = tree.parent(parent_id);
        }
    }
    Ok(())
}
fn declaration_grow<T,E>(rows:&mut Vec<T>,count:usize,funded:&mut usize,reserve:&mut impl FnMut(usize)->Result<(),E>,resource:&impl Fn(&'static str)->E)->Result<(),E>{
 if rows.capacity()>=count{return Ok(())}
 // One operation-local buffer is reused for all owners. Reserve only its
 // increasing live peak; eight target capacities cover old+new overlap even
 // under the explicit four-times returned-capacity guard.
 let bound=count.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_mul(8)).and_then(|n|n.checked_add(std::mem::size_of::<Vec<T>>()+64)).ok_or_else(||resource("global own-field scratch overflow"))?;
 if bound>*funded{reserve(bound-*funded)?;*funded=bound;}
 rows.try_reserve_exact(count.saturating_sub(rows.len())).map_err(|_|resource("global own-field scratch allocation refused"))?;
 if rows.capacity()>count.saturating_mul(4).max(4){return Err(resource("global own-field scratch exceeded admitted capacity"))}Ok(())
}

fn declaration_buffer<T,E>(count:usize,reserve:&mut impl FnMut(usize)->Result<(),E>,resource:&impl Fn(&'static str)->E)->Result<Vec<T>,E>{
 let bytes=count.checked_mul(std::mem::size_of::<T>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(std::mem::size_of::<Vec<T>>()+64)).ok_or_else(||resource("global declaration buffer overflow"))?;reserve(bytes)?;let mut rows=Vec::new();rows.try_reserve_exact(count).map_err(|_|resource("global declaration buffer allocation denied"))?;if rows.capacity()>count.saturating_mul(4).max(4){return Err(resource("global declaration buffer exceeded admitted capacity"))}Ok(rows)
}

fn subtype(tree:&SemanticTree,child:SymbolId,parent:SymbolId)->Result<bool,String>{subtype_using(tree,child,parent,&mut||Ok(()))}
fn subtype_using<E:From<String>+for<'e>From<&'e str>>(tree:&SemanticTree,child:SymbolId,parent:SymbolId,checkpoint:&mut impl FnMut()->Result<(),E>)->Result<bool,E>{
    let mut current = Some(
        tree.lookup_type(child)
            .ok_or("visibility current owner unavailable")?,
    );
    let mut remaining=tree.types().len();
    while let Some(id) = current {
        checkpoint()?;remaining=remaining.checked_sub(1).ok_or("visibility actual parent chain cycles")?;
        let node = tree.type_node(id).ok_or("visibility subtype unavailable")?;
        if node.path == parent {
            return Ok(true);
        }
        current = tree.parent(id)
    }
    Ok(false)
}
fn fields(
    archive: &BodyArchive,
    body: &ArchivedBody<'_>,
    profile: PackedU128,
    walk: Walk<'_>,
    policy: &CheckerPolicy,
) -> Result<Vec<Produced>, String> {
    let mut out=Vec::new();visit_field_events(archive,body,profile,walk.events,policy,&mut||Ok::<(),String>(()),|row|{if out.len()>=MAX_FINDINGS{return Err("visibility exceeds existing finding admission".to_owned())}out.push(row);Ok(())})?;check_count(&out)?;Ok(out)
}
pub(crate) fn visit_field_events<'a,E:From<String>+for<'e>From<&'e str>>(archive:&BodyArchive,body:&dyn dm_tree::frontend::InitialSettingSource,profile:PackedU128,events:impl IntoIterator<Item=Event<'a>>,policy:&CheckerPolicy,checkpoint:&mut impl FnMut()->Result<(),E>,mut emit:impl FnMut(Produced)->Result<(),E>)->Result<(),E>{
    if !std::ptr::eq(body.archive_owner(), archive) {
        return Err("visibility field body belongs to another archive".into());
    }
    let tree = archive.tree();
    let caller = tree
        .member(body.occurrence().member)
        .ok_or("visibility callable unavailable")?;
    let caller = tree
        .type_node(caller.owner)
        .ok_or("visibility callable owner unavailable")?
        .path;
    for event in events {
        checkpoint()?;
        let Event::ResolvedField {
            expression,
            at,
            name,
            receiver,
            fact,
        } = event
        else {
            continue;
        };
        let Some(formal) = fact.formal else { continue };
        let flags = archive.checker_variable_qualifiers(formal, profile)?;
        let selected = if receiver != caller && flags & PRIVATE != 0 {
            Some((Site::FieldPrivate, "private"))
        } else if !subtype_using(tree,caller,receiver,checkpoint)? && flags & PROTECTED != 0 {
            Some((Site::FieldProtected, "protected"))
        } else {
            None
        };
        let Some((site, kind)) = selected else {
            continue;
        };
        if !enabled(policy, site) {
            continue;
        }
        let at = body.source_point(at)?;
        let expression_span = body.source_point(expression.span)?;
        emit(produced(
            site,
            archive.source_note_point(at.start)?,
            at,
            expression_span,
            format!(
                "field {name:?} on {} is declared as {kind}",
                text(tree, receiver)?
            ),
            vec![Note {
                message: "definition is here".into(),
                source: Some(point(archive, formal)?),
            }],
        ))?;
    }
    Ok(())
}
/// One complete producer-category pass. Findings are buffered and only returned
/// after every category succeeds; unsupported locations never become omissions.
pub fn scan(
    archive: &BodyArchive,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    policy: &CheckerPolicy,
) -> Result<Vec<Configured>, String> {
    scan_with_checkpoint(archive, resolver, profile, policy, || Ok(()))
}
pub fn scan_with_checkpoint(
    archive: &BodyArchive,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    policy: &CheckerPolicy,
    mut checkpoint: impl FnMut() -> Result<(), String>,
) -> Result<Vec<Configured>, String> {
    scan_with::<crate::policy_body_demand::Compatibility>(
        archive,
        resolver,
        profile,
        policy,
        || checkpoint().map_err(crate::untyped::Unsupported),
    )
    .map_err(|e| e.0)
}
pub fn scan_checked(
    archive: &BodyArchive,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    policy: &CheckerPolicy,
    mut checkpoint: impl FnMut() -> std::io::Result<()>,
) -> Result<Vec<Configured>, crate::policy_body_demand::PolicyFailure> {
    scan_with::<crate::policy_body_demand::Checked>(archive, resolver, profile, policy, || {
        checkpoint().map_err(crate::policy_body_demand::PolicyFailure::Operational)
    })
}
fn scan_with<D: crate::policy_body_demand::Demand>(
    archive: &BodyArchive,
    resolver: &(impl Resolver + ?Sized),
    profile: PackedU128,
    policy: &CheckerPolicy,
    mut checkpoint: impl FnMut() -> Result<(), D::Error>,
) -> Result<Vec<Configured>, D::Error> {
    checkpoint()?;
    if resolver.source_owner() != Resolver::source_owner(archive.tree()) {
        return Err("visibility resolver is not the original native owner".into());
    }
    archive
        .tree()
        .validate_checker_builtin_profile(profile)
        .map_err(|e| format!("visibility profile: {e:?}"))?;
    let mut source_order = archive
        .occurrences()
        .iter()
        .enumerate()
        .map(|(ordinal, body)| {
            (
                body.source.encounter_ordinal,
                body.expanded_span.start,
                ordinal,
            )
        })
        .collect::<Vec<_>>();
    source_order.sort_unstable();
    let mut raw = Vec::new();
    let locals_enabled =
        enabled(policy, Site::LocalPrivate) || enabled(policy, Site::LocalProtected);
    for (_, _, ordinal) in source_order.into_iter().filter(|_| locals_enabled) {
        checkpoint()?;
        let body = D::parse(archive, ordinal)?;
        append(&mut raw, parser_locals(archive, &body, policy)?)?;
    }
    append(
        &mut raw,
        declarations(archive, profile, policy, &mut checkpoint)?,
    )?;
    let fields_enabled =
        enabled(policy, Site::FieldPrivate) || enabled(policy, Site::FieldProtected);
    for (ordinal, _) in crate::checker_order::archived_bodies(archive)?
        .into_iter()
        .filter(|_| fields_enabled)
    {
        checkpoint()?;
        let body = D::parse(archive, ordinal)?;
        let walk = crate::checker_expression_visit::archived(archive, &body, resolver, profile)?;
        append(&mut raw, fields(archive, &body, profile, walk, policy)?)?;
    }
    Ok(raw
        .into_iter()
        .filter_map(|finding| {
            policy
                .register(finding.site.tag(), finding.site.default())
                .map(|severity| Configured { finding, severity })
        })
        .collect())
}

#[cfg(test)]
mod policy_tests {
    use super::*;
    use std::collections::BTreeMap;
    #[test]
    fn private_categories_preserve_each_real_site_default() {
        let policy = CheckerPolicy::default();
        assert_eq!(
            policy.register(Site::LocalPrivate.tag(), Site::LocalPrivate.default()),
            Some(DiagnosticSeverity::Warning)
        );
        assert_eq!(
            policy.register(Site::FieldPrivate.tag(), Site::FieldPrivate.default()),
            Some(DiagnosticSeverity::Warning)
        );
        assert_eq!(
            policy.register(Site::OverridePrivate.tag(), Site::OverridePrivate.default()),
            Some(DiagnosticSeverity::Error)
        );
    }
    #[test]
    fn named_overrides_do_not_retag_the_untagged_redeclaration() {
        let policy = CheckerPolicy {
            diagnostics: BTreeMap::from([
                (
                    "private_var".into(),
                    crate::check_policy::WarningLevel::Disabled,
                ),
                (
                    "variable_redeclaration".into(),
                    crate::check_policy::WarningLevel::Disabled,
                ),
            ]),
            ..Default::default()
        };
        assert!(!enabled(&policy, Site::LocalPrivate));
        assert!(!enabled(&policy, Site::OverridePrivate));
        assert!(enabled(&policy, Site::Redeclaration));
        assert_eq!(Site::Redeclaration.tag(), None);
    }
}

/// An actual complete global declaration producer result. Constructed only
/// after the whole shared judge succeeds under one current Original input.
/// This is not a full checker or a receipt for executable body diagnostics.
pub struct OriginalDeclarations<'a>{input:&'a crate::checker_effects::EffectInput,rows:Vec<Produced>}
impl OriginalDeclarations<'_>{
 pub fn rows(&self)->&[Produced]{&self.rows}
 pub fn belongs_to(&self,input:&crate::checker_effects::EffectInput)->bool{std::ptr::eq(self.input,input)}
}
pub fn with_original_declarations<W:crate::checker_effects::EffectReportWork>(input:&crate::checker_effects::EffectInput,resolver:&(impl Resolver+?Sized),admission:&crate::checker_effects::ExecutionAdmission,work:&mut W,checkpoint:&dyn Fn()->std::io::Result<()>,consume:impl FnOnce(&OriginalDeclarations<'_>)->Result<(),crate::policy_body_demand::PolicyFailure>)->Result<(),crate::policy_body_demand::PolicyFailure>{
 use crate::policy_body_demand::PolicyFailure;
 checkpoint().map_err(PolicyFailure::Operational)?;input.require_original_checker_source()?;let archive=input.archive();let tree=archive.tree();if resolver.source_owner()!=Resolver::source_owner(tree){return Err("original global declaration resolver is foreign".into())}
 let budget=crate::checker_effects::output::ReportBudget::for_operation(admission);let work=std::cell::RefCell::new(work);
 let admit=|bytes|->Result<(),PolicyFailure>{budget.charge(bytes).map_err(|_|PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original global declaration admission denied")))?;work.borrow_mut().reserve(bytes).map_err(PolicyFailure::Operational)};
 let mut rows=Vec::new();let pending=visit_declarations_using(archive,input.profile(),&CheckerPolicy::default(),&mut||checkpoint().map_err(PolicyFailure::Operational),&mut|bytes|admit(bytes),&|message|PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,message)),&mut|row|{
  if rows.len()==rows.capacity(){let capacity=rows.capacity().max(2).checked_mul(2).ok_or("original global row count overflow")?;let bytes=capacity.checked_mul(std::mem::size_of::<Produced>()).and_then(|n|n.checked_mul(4)).and_then(|n|n.checked_add(128)).ok_or("original global row backing overflow")?;admit(bytes)?;rows.try_reserve_exact(capacity-rows.len()).map_err(|_|PolicyFailure::Operational(std::io::Error::new(std::io::ErrorKind::OutOfMemory,"original global row allocation refused")))?;if rows.capacity()>capacity.saturating_mul(4){return Err("original global row backing exceeded admitted capacity".into())}}
  rows.push(row);Ok(())
 });
 if let Err(PolicyFailure::Operational(actual))=pending{return Err(PolicyFailure::Operational(actual))}pending?;checkpoint().map_err(PolicyFailure::Operational)?;input.require_original_checker_source()?;admission.reserve_external(0).map_err(PolicyFailure::Operational)?;
 let findings=OriginalDeclarations{input,rows};let pending=consume(&findings);drop(findings);if matches!(pending,Err(PolicyFailure::Operational(_))){return pending}pending?;checkpoint().map_err(PolicyFailure::Operational)?;input.require_original_checker_source()?;admission.reserve_external(0).map_err(PolicyFailure::Operational)
}

#[cfg(test)]mod original_global_resource_tests{
 use super::*;
 #[test]fn original_global_field_scratch_reserves_one_increasing_peak_across_owners(){
  let mut rows:Vec<u64>=Vec::new();let mut funded=0;let mut calls=0;let resource=|m:&'static str|m.to_owned();{let mut reserve=|_:usize|{calls+=1;Ok::<(),String>(())};declaration_grow(&mut rows,23,&mut funded,&mut reserve,&resource).unwrap();let first=funded;for _ in 0..1024{rows.clear();declaration_grow(&mut rows,23,&mut funded,&mut reserve,&resource).unwrap();}assert_eq!(funded,first);}assert_eq!(calls,1);let previous=rows.capacity();let before=funded;assert_eq!(declaration_grow(&mut rows,previous+100,&mut funded,&mut|_|Err::<(),String>("actual resource callback refusal".into()),&resource),Err("actual resource callback refusal".into()));assert_eq!(rows.capacity(),previous);assert_eq!(funded,before);
 }
}
