//! Analyze base-vars declaration supplements over the compiler's native owners.
//!
//! Raw declarations, homes, exemptions, ALLOW accounting and baseline policy
//! remain with Analyze. This module returns compact rows, never another tree.
use crate::untyped::Unsupported;
use dm_ir::{
    DeclarationMeaning, ResolveQuery, ResolvedMeaning, Resolver, SymbolId, SymbolicExpression,
};
use dm_syntax::TokenKind;
use dm_tree::{
    frontend::{BodyArchive, SourceLocation},
    DefinitionMode, MemberId, MemberKind, SemanticTree,
};
use std::{path::Path, sync::Arc};

// Native declaration masks, defined by dm-tree's authored declaration adapter.
// Global is a separate native mask, but shares STATIC's legacy policy meaning.
const NO_INSTANCE_COST: u32 = 1 | 2 | 8;

#[derive(Debug)]
pub struct BaseVarDeclaration<'a> {
    tree: &'a SemanticTree,
    pub declaration: MemberId,
    pub effective: MemberId,
    pub owner: SymbolId,
    pub name: SymbolId,
    pub metadata: &'a DeclarationMeaning,
    pub source: SourceLocation,
    pub base: bool,
    pub list_init: bool,
}
impl BaseVarDeclaration<'_> {
    /// Analyze's legacy VarSig type spelling, not the canonical runtime type.
    /// List element and array annotations are retained in native metadata.
    pub fn declared_type_text(&self) -> Result<String, Unsupported> {
        let spelling = |symbol| {
            self.tree
                .symbols()
                .text(symbol)
                .ok_or_else(|| Unsupported("base-var declared-type spelling unavailable".into()))
        };
        if let Some(array) = &self.metadata.array {
            if array.dimensions.is_empty() {
                return Err(Unsupported(
                    "base-var array has no captured dimensions".into(),
                ));
            }
            return Ok(match array.element_type {
                Some(element) => format!("/list{}", spelling(element)?),
                None => "/list".into(),
            });
        }
        match (self.metadata.declared_type, self.metadata.list_element_type) {
            (Some(container), Some(element)) if container == SymbolId::of("/list") => {
                Ok(format!("/list{}", spelling(element)?))
            }
            (Some(declared), None) => Ok(spelling(declared)?.to_owned()),
            (None, None) => Ok(String::new()),
            _ => Err(Unsupported(
                "base-var list element metadata has no list container".into(),
            )),
        }
    }
}

/// Whether the authored initializer has exactly the ungrouped empty list term.
/// Folded values, parenthesized lists, sized arrays and `new /list` do not count.
fn empty_list(
    tree: &SemanticTree,
    initializer: Option<&SymbolicExpression>,
) -> Result<bool, Unsupported> {
    let Some(initializer) = initializer else {
        return Ok(false);
    };
    // Validate spelling coverage before rejecting a nonmatching shape. Missing
    // symbol data is incomplete input, not evidence of a non-list initializer.
    for token in initializer.tokens.iter() {
        if tree.symbols().text(token.text).is_none() {
            return Err(Unsupported(
                "base-var initializer token spelling unavailable".into(),
            ));
        }
        if matches!(token.kind, TokenKind::Unknown) {
            return Err(Unsupported(
                "base-var initializer has unknown token syntax".into(),
            ));
        }
    }
    let [name, open, close] = initializer.tokens.as_ref() else {
        return Ok(false);
    };
    Ok(name.kind == TokenKind::Ident
        && tree.symbols().text(name.text) == Some("list")
        && open.kind == TokenKind::Punctuation
        && tree.symbols().text(open.text) == Some("(")
        && close.kind == TokenKind::Punctuation
        && tree.symbols().text(close.text) == Some(")"))
}

fn effective_metadata<'a>(
    tree: &'a SemanticTree,
    declaration: MemberId,
) -> Result<(MemberId, &'a DeclarationMeaning), Unsupported> {
    let formal = tree
        .member(declaration)
        .ok_or_else(|| Unsupported("base-var declaration absent".into()))?;
    let owner = tree
        .type_node(formal.owner)
        .ok_or_else(|| Unsupported("base-var owner absent".into()))?
        .path;
    let effective = tree
        .resolve(formal.owner, formal.name, MemberKind::Var)
        .ok_or_else(|| Unsupported("base-var effective definition absent".into()))?;
    let selected = tree
        .member(effective)
        .ok_or_else(|| Unsupported("base-var effective member absent".into()))?;
    match Resolver::resolve(
        tree,
        ResolveQuery::Var {
            owner,
            name: formal.name,
        },
    ) {
        ResolvedMeaning::Member {
            owner: selected_owner,
            name,
            data,
            ..
        } if selected_owner == owner
            && name == formal.name
            && selected.owner == formal.owner
            && Arc::ptr_eq(&data, &selected.metadata)
            && data.inherited_opaque.is_none() =>
        {
            Ok((effective, selected.metadata.as_ref()))
        }
        _ => Err(Unsupported(
            "base-var effective metadata is incomplete or foreign".into(),
        )),
    }
}

fn file(root: &Path, source: &SourceLocation) -> String {
    let relative = source.path.strip_prefix(root).unwrap_or(&source.path);
    let text = relative.to_string_lossy().replace('\\', "/");
    if !text.contains("/.") {
        return text;
    }
    let mut out: Vec<&str> = Vec::new();
    for segment in text.split('/') {
        match segment {
            "." => (),
            ".." if out.last().is_some_and(|last| *last != "..") => {
                out.pop();
            }
            _ => out.push(segment),
        }
    }
    out.join("/")
}

/// Legacy `typed_vars`: declarations only, effective same-owner initializer,
/// declaration source location, caller-supplied base type set. Child defaults
/// are not declarations and cannot manufacture rows on a subtype.
///
/// Sort is file/header/owner, stable for ties. Neither legacy typed_vars nor
/// record_procs deduplicates equal report rows. Source lines remain native
/// issued coordinates; lone-CR display correction belongs to a captured raw
/// source projection, never a fresh filesystem read.
pub fn base_var_declarations<'a>(
    archive: &'a BodyArchive,
    base_types: &[&str],
    root: &Path,
) -> Result<Vec<BaseVarDeclaration<'a>>, Unsupported> {
    let tree = archive.tree();
    let mut rows = Vec::new();
    for (index, member) in tree.members().iter().enumerate() {
        if member.kind != MemberKind::Var || member.definition != DefinitionMode::Declare {
            continue;
        }
        let owner = tree
            .type_node(member.owner)
            .ok_or_else(|| Unsupported("base-var declaration owner absent".into()))?
            .path;
        if owner == SymbolId::of("/") {
            continue;
        }
        if member.metadata.inherited_opaque.is_some() {
            return Err(Unsupported("base-var declared flags are opaque".into()));
        }
        if member.metadata.flags & NO_INSTANCE_COST != 0 {
            continue;
        }
        let owner_text = tree
            .symbols()
            .text(owner)
            .ok_or_else(|| Unsupported("base-var owner spelling unavailable".into()))?;
        let base = base_types.contains(&owner_text);
        let declaration = MemberId(
            index
                .try_into()
                .map_err(|_| Unsupported("base-var member index overflow".into()))?,
        );
        let (effective, metadata) = effective_metadata(tree, declaration)?;
        let list_init = empty_list(tree, metadata.initializer.as_ref())?;
        if !base && !list_init {
            continue;
        }
        let source = archive
            .member_location(declaration)
            .filter(|source| source.line != 0 && !source.path.as_os_str().is_empty())
            .ok_or_else(|| {
                Unsupported("base-var declaration has no issued source origin".into())
            })?;
        rows.push(BaseVarDeclaration {
            tree,
            declaration,
            effective,
            owner,
            name: member.name,
            metadata: member.metadata.as_ref(),
            source,
            base,
            list_init,
        });
    }
    rows.sort_by(|a, b| {
        (
            file(root, &a.source),
            a.source.line,
            tree.symbols().text(a.owner),
        )
            .cmp(&(
                file(root, &b.source),
                b.source.line,
                tree.symbols().text(b.owner),
            ))
    });
    Ok(rows)
}

#[derive(Clone, Copy, Debug)]
pub struct RecordProcedure<'a> {
    pub member: MemberId,
    pub owner: SymbolId,
    pub name: SymbolId,
    pub source: &'a SourceLocation,
}

/// Legacy `record_procs` uses the lexical `/datum/record` prefix, not actual
/// inheritance. Only authored body occurrences count, never inherited copies
/// or native engine declarations with no source body. Body validity remains
/// the compiler producer's responsibility; this does not parse executable ASTs.
pub fn record_procedures<'a>(
    archive: &'a BodyArchive,
    root: &Path,
) -> Result<Vec<RecordProcedure<'a>>, Unsupported> {
    let tree = archive.tree();
    let mut rows = Vec::new();
    for occurrence in archive.occurrences() {
        let member = tree
            .member(occurrence.member)
            .ok_or_else(|| Unsupported("record body member absent".into()))?;
        if !matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
            return Err(Unsupported(
                "record body names a non-callable member".into(),
            ));
        }
        let owner = tree
            .type_node(member.owner)
            .ok_or_else(|| Unsupported("record owner absent".into()))?
            .path;
        let owner_text = tree
            .symbols()
            .text(owner)
            .ok_or_else(|| Unsupported("record owner spelling unavailable".into()))?;
        if owner_text != "/datum/record" && !owner_text.starts_with("/datum/record/") {
            continue;
        }
        if member.metadata.procedure.is_none() || tree.symbols().text(member.name).is_none() {
            return Err(Unsupported("record signature incomplete".into()));
        }
        if occurrence.source.line == 0 || occurrence.source.path.as_os_str().is_empty() {
            return Err(Unsupported(
                "record definition has no issued source origin".into(),
            ));
        }
        rows.push(RecordProcedure {
            member: occurrence.member,
            owner,
            name: member.name,
            source: &occurrence.source,
        });
    }
    rows.sort_by(|a, b| {
        (
            file(root, a.source),
            a.source.line,
            tree.symbols().text(a.name),
        )
            .cmp(&(
                file(root, b.source),
                b.source.line,
                tree.symbols().text(b.name),
            ))
    });
    Ok(rows)
}

#[cfg(test)]
#[path = "base_var_declarations_tests.rs"]
mod tests;
