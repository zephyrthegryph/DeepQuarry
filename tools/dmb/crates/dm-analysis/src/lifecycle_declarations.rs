//! Analyze's lifecycle-definition supplements over issued compiler declarations.
//!
//! This intentionally selects authored body occurrences, not inherited callable
//! lookup results: an inherited method is not another definition on a child.
//! Raw text rules, excluded files, ALLOW handling and baselines remain policy.
use crate::untyped::Unsupported;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver, SymbolId};
use dm_tree::{
    frontend::{BodyArchive, BodyOccurrence, SourceLocation},
    DefinitionMode, MemberId, MemberKind, SemanticTree,
};
use std::path::Path;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LifecyclePolicy {
    Init,
    Decl,
}

/// Compact policy row borrowing the compiler's exact source occurrence.
/// Member IDs are meaningful only in the issuing archive's `tree()`.
#[derive(Clone, Copy, Debug)]
pub struct LifecycleDefinition<'a> {
    pub member: MemberId,
    pub owner: SymbolId,
    pub name: SymbolId,
    pub definition: DefinitionMode,
    pub source: &'a SourceLocation,
    /// The decl lint keeps a plain datum's Initialize definition in its roster
    /// but marks it as a manual callback, rather than an atom lifecycle hook.
    pub lifecycle: bool,
}

fn under(tree: &SemanticTree, owner: SymbolId, base: SymbolId) -> Result<bool, Unsupported> {
    let query = ResolveQuery::Ancestry(owner);
    match Resolver::resolve(tree, query) {
        ResolvedMeaning::Symbols(ancestry) => Ok(ancestry.contains(&base)),
        ResolvedMeaning::Unsupported(_) => Err(Unsupported(
            "lifecycle ancestry needs a certified current engine hierarchy".into(),
        )),
        ResolvedMeaning::Missing => Err(Unsupported(
            "lifecycle ancestry is absent from the issued tree".into(),
        )),
        _ => Err(Unsupported(
            "lifecycle ancestry query returned a foreign answer kind".into(),
        )),
    }
}

fn row<'a>(
    tree: &SemanticTree,
    occurrence: &'a BodyOccurrence,
    policy: LifecyclePolicy,
) -> Result<Option<LifecycleDefinition<'a>>, Unsupported> {
    let member = tree
        .member(occurrence.member)
        .ok_or_else(|| Unsupported("lifecycle body member absent from issued tree".into()))?;
    if !matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
        return Err(Unsupported(
            "lifecycle body names a non-callable member".into(),
        ));
    }
    let name = tree
        .symbols()
        .text(member.name)
        .ok_or_else(|| Unsupported("lifecycle callable name unavailable".into()))?;
    let owner = tree
        .type_node(member.owner)
        .ok_or_else(|| Unsupported("lifecycle callable owner unavailable".into()))?
        .path;
    let owner_text = tree
        .symbols()
        .text(owner)
        .ok_or_else(|| Unsupported("lifecycle owner spelling unavailable".into()))?;
    let selected = match policy {
        LifecyclePolicy::Decl => matches!(name, "Initialize" | "on_materialize" | "on_destroy"),
        LifecyclePolicy::Init => {
            matches!(name, "Initialize" | "LateInitialize")
                || name == "on_materialize"
                    && (owner_text == "/turf" || owner_text.starts_with("/turf/"))
        }
    };
    if !selected {
        return Ok(None);
    }
    if member.metadata.procedure.is_none() {
        return Err(Unsupported(
            "lifecycle callable signature unavailable".into(),
        ));
    }
    if occurrence.source.line == 0 || occurrence.source.path.as_os_str().is_empty() {
        return Err(Unsupported(
            "lifecycle definition has no issued source origin".into(),
        ));
    }
    let lifecycle = policy != LifecyclePolicy::Decl
        || name != "Initialize"
        || under(tree, owner, SymbolId::of("/atom"))?;
    Ok(Some(LifecycleDefinition {
        member: occurrence.member,
        owner,
        name: member.name,
        definition: member.definition,
        source: &occurrence.source,
        lifecycle,
    }))
}

fn file(root: &Path, source: &SourceLocation) -> String {
    // Report-only filesystem equivalence. Keep original provider/origin keys;
    // only the shared safe ordinary-DOS/verbatim comparison may unify paths.
    dm_preprocess::regions::relative_filesystem_path(source.path.as_path(), root)
        .as_deref()
        .unwrap_or(source.path.as_path())
        .to_string_lossy()
        .replace('\\', "/")
}

/// `sem::procs::proc_defs` ordering and each lifecycle lint's exact filter,
/// without parsing an executable body or materializing a second type model.
/// Every authored formal/override is retained at its own source location; no
/// nearest inherited body is substituted. Repeated identical report rows are
/// deduplicated, matching the old file/header/owner/name projection.
///
/// This header roster does not certify procedure-syntax parity. Its producer's
/// normal body validation still determines whether executable syntax is valid.
/// Source lines are native issued coordinates; a consumer preserving Analyze's
/// universal-newline display correction must derive it from captured raw bytes,
/// never reread mutable files or change the issued origin.
pub fn lifecycle_definitions<'a>(
    archive: &'a BodyArchive,
    policy: LifecyclePolicy,
    root: &Path,
) -> Result<Vec<LifecycleDefinition<'a>>, Unsupported> {
    let tree = archive.tree();
    let mut selected = Vec::new();
    for occurrence in archive.occurrences() {
        if let Some(row) = row(tree, occurrence, policy)? {
            let owner = tree
                .symbols()
                .text(row.owner)
                .ok_or_else(|| Unsupported("lifecycle report owner unavailable".into()))?;
            let name = tree
                .symbols()
                .text(row.name)
                .ok_or_else(|| Unsupported("lifecycle report name unavailable".into()))?;
            selected.push(((file(root, row.source), row.source.line, owner, name), row));
        }
    }
    selected.sort_by(|a, b| a.0.cmp(&b.0));
    selected.dedup_by(|a, b| a.0 == b.0);
    Ok(selected.into_iter().map(|(_, row)| row).collect())
}

#[cfg(test)]
#[path = "lifecycle_declarations_tests.rs"]
mod tests;

/// Borrow authenticated authored lifecycle rows without constructing a report roster.
/// The caller supplies its SAME operation control and owns ordering/deduplication.
pub fn visit_lifecycle_definitions_using<E>(archive:&BodyArchive,policy:LifecyclePolicy,poll:&dyn Fn()->Result<(),E>,unsupported:&dyn Fn(Unsupported)->E,visit:&mut dyn FnMut(LifecycleDefinition<'_>)->Result<(),E>)->Result<(),E>{
 poll()?;let tree=archive.tree();for occurrence in archive.occurrences(){poll()?;if let Some(value)=row(tree,occurrence,policy).map_err(unsupported)?{visit(value)?;}}poll()
}
