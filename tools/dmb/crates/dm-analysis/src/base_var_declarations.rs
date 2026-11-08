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
use std::{collections::BTreeMap, path::Path, sync::Arc};


/// Operation-only control for the existing declaration projection. No source role.
pub trait DeclarationWork{type Error:From<Unsupported>;const CHECKED:bool;fn checkpoint(&mut self)->Result<(),Self::Error>;fn reserve(&mut self,bytes:usize)->Result<(),Self::Error>;fn overflow(&mut self)->Self::Error;fn allocation_failed(&mut self)->Self::Error;}
struct Compatibility;
impl DeclarationWork for Compatibility{type Error=Unsupported;const CHECKED:bool=false;fn checkpoint(&mut self)->Result<(),Unsupported>{Ok(())}fn reserve(&mut self,_:usize)->Result<(),Unsupported>{Ok(())}fn overflow(&mut self)->Unsupported{unreachable!("compatibility does not compute native resource bounds")}fn allocation_failed(&mut self)->Unsupported{unreachable!("compatibility keeps original allocation APIs")}}
fn reserve<W:DeclarationWork>(work:&mut W,bytes:impl FnOnce()->Option<usize>)->Result<(),W::Error>{if !W::CHECKED{return Ok(())}work.checkpoint()?;let bytes=bytes().ok_or_else(||work.overflow())?;work.reserve(bytes)}
fn row<W:DeclarationWork,T>(work:&mut W,rows:&mut Vec<T>)->Result<(),W::Error>{if !W::CHECKED||rows.len()<rows.capacity(){return Ok(())}let wanted=rows.capacity().checked_mul(2).map(|n|n.max(4)).ok_or_else(||work.overflow())?;let bound=wanted.checked_mul(4).ok_or_else(||work.overflow())?;reserve(work,||bound.checked_mul(std::mem::size_of::<T>())?.checked_add(128))?;rows.try_reserve_exact(wanted-rows.len()).map_err(|_|work.allocation_failed())?;if rows.capacity()>bound{return Err(work.allocation_failed())}Ok(())}

// Native declaration masks, defined by dm-tree's authored declaration adapter.
// Global is a separate native mask, but shares STATIC's legacy policy meaning.
const NO_INSTANCE_COST: u32 = 1 | 2 | 8;

#[derive(Debug)]
pub struct BaseVarDeclaration<'a> {
    tree: &'a SemanticTree,
    pub declaration: MemberId,
    /// Runtime-normalized selection, used for declaration metadata proof only.
    pub effective: MemberId,
    /// Last authored same-owner value, matching legacy TypeVar.value policy.
    pub source_value: MemberId,
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
        match (self.metadata.declared_type(), self.metadata.list_element_type()) {
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
fn empty_list(tree:&SemanticTree,initializer:Option<&SymbolicExpression>)->Result<bool,Unsupported>{empty_list_using(tree,initializer,&mut Compatibility)}
fn empty_list_using<W:DeclarationWork>(tree:&SemanticTree,initializer:Option<&SymbolicExpression>,work:&mut W)->Result<bool,W::Error>{
    work.checkpoint()?;
    let Some(initializer) = initializer else {
        return Ok(false);
    };
    // Validate spelling coverage before rejecting a nonmatching shape. Missing
    // symbol data is incomplete input, not evidence of a non-list initializer.
    for token in initializer.tokens.iter() {
        work.checkpoint()?;
        if tree.symbols().text(token.text).is_none() {
            return Err(Unsupported(
                "base-var initializer token spelling unavailable".into(),
            ).into());
        }
        if matches!(token.kind, TokenKind::Unknown) {
            return Err(Unsupported(
                "base-var initializer has unknown token syntax".into(),
            ).into());
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
            && data.inherited_opaque().is_none() =>
        {
            Ok((effective, selected.metadata.as_ref()))
        }
        _ => Err(Unsupported(
            "base-var effective metadata is incomplete or foreign".into(),
        )),
    }
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

/// Legacy `typed_vars`: declarations only, last authored same-owner initializer,
/// declaration source location, caller-supplied base type set. Child defaults
/// are not declarations and cannot manufacture rows on a subtype.
///
/// Sort is file/header/owner, stable for ties. Neither legacy typed_vars nor
/// record_procs deduplicates equal report rows. Source lines remain native
/// issued coordinates; lone-CR display correction belongs to a captured raw
/// source projection, never a fresh filesystem read.
pub fn base_var_declarations<'a>(archive:&'a BodyArchive,base_types:&[&str],root:&Path)->Result<Vec<BaseVarDeclaration<'a>>,Unsupported>{base_var_declarations_using(archive,base_types,root,&mut Compatibility)}
pub fn base_var_declarations_using<'a,W:DeclarationWork>(archive:&'a BodyArchive,base_types:&[&str],root:&Path,work:&mut W)->Result<Vec<BaseVarDeclaration<'a>>,W::Error>{
    work.checkpoint()?;
    let tree = archive.tree();
    // Runtime dispatch normalizes a formal before overrides. Legacy Analyze's
    // TypeVar.value instead follows source encounter, including a later formal
    // declaration replacing an earlier assignment. Preserve that policy using
    // the compiler's authored ledger, not another parser or runtime inference.
    struct Group {
        formal: Option<MemberId>,
        value: MemberId,
        first: usize,
    }
    let mut groups: Vec<Group> = Vec::new();
    let mut by_name = BTreeMap::new();
    for (encounter, target) in tree.declarations().iter().enumerate() {
        work.checkpoint()?;
        let dm_tree::Target::Member(id) = target else {
            continue;
        };
        let member = tree
            .member(*id)
            .ok_or_else(|| Unsupported("base-var authored member is absent".into()))?;
        if member.kind != MemberKind::Var {
            continue;
        }
        let key=(member.owner.index(),member.name);let group=match by_name.get(&key).copied(){Some(group)=>group,None=>{reserve(work,||Some(2048))?;row(work,&mut groups)?;groups.push(Group{formal:None,value:*id,first:encounter});let group=groups.len()-1;by_name.insert(key,group);group}};
        groups[group].value = *id;
        if member.definition == DefinitionMode::Declare {
            groups[group].formal = Some(*id);
        }
    }
    let mut rows = Vec::new();
    for group in groups {
        work.checkpoint()?;
        let Some(declaration) = group.formal else {
            continue;
        };
        let member = tree
            .member(declaration)
            .ok_or_else(|| Unsupported("base-var formal declaration is absent".into()))?;
        let owner = tree
            .type_node(member.owner)
            .ok_or_else(|| Unsupported("base-var declaration owner absent".into()))?
            .path;
        if owner == SymbolId::of("/") {
            continue;
        }
        if member.metadata.inherited_opaque().is_some() {
            return Err(Unsupported("base-var declared flags are opaque".into()).into());
        }
        if member.metadata.flags & NO_INSTANCE_COST != 0 {
            continue;
        }
        let owner_text = tree
            .symbols()
            .text(owner)
            .ok_or_else(|| Unsupported("base-var owner spelling unavailable".into()))?;
        let base = base_types.contains(&owner_text);
        let (effective, _) = effective_metadata(tree, declaration)?;
        let value = tree
            .member(group.value)
            .ok_or_else(|| Unsupported("base-var authored value is absent".into()))?;
        if value.owner != member.owner
            || value.name != member.name
            || value.metadata.inherited_opaque().is_some()
        {
            return Err(Unsupported(
                "base-var authored initializer is incomplete or foreign".into(),
            ).into());
        }
        let list_init = empty_list_using(tree,value.metadata.initializer.as_ref(),work)?;
        if !base && !list_init {
            continue;
        }
        let source = archive
            .member_location(declaration)
            .filter(|source| source.line != 0 && !source.path.as_os_str().is_empty())
            .ok_or_else(|| {
                Unsupported("base-var declaration has no issued source origin".into())
            })?;
        row(work,&mut rows)?;rows.push((
            group.first,
            BaseVarDeclaration {
                tree,
                declaration,
                effective,
                source_value: group.value,
                owner,
                name: member.name,
                metadata: member.metadata.as_ref(),
                source,
                base,
                list_init,
            },
        ));
    }

    if !W::CHECKED{    rows.sort_by(|(first_a, a), (first_b, b)| {
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
            .then(first_a.cmp(first_b))
    });
    Ok(rows.into_iter().map(|(_, row)| row).collect())}
    else{let mut keyed=Vec::new();for(first,value)in rows{work.checkpoint()?;reserve(work,||value.source.path.as_os_str().len().checked_add(root.as_os_str().len())?.checked_mul(8)?.checked_add(512))?;let key=file(root,&value.source);let owner=tree.symbols().text(value.owner);row(work,&mut keyed)?;keyed.push((key,value.source.line,owner,first,value));}let mut error=None;keyed.sort_by(|a,b|{if error.is_none(){if let Err(actual)=work.checkpoint(){error=Some(actual)}}(&a.0,a.1,a.2,a.3).cmp(&(&b.0,b.1,b.2,b.3))});if let Some(actual)=error{return Err(actual)}reserve(work,||keyed.len().checked_mul(4*std::mem::size_of::<BaseVarDeclaration<'_>>())?.checked_add(128))?;Ok(keyed.into_iter().map(|(_,_,_,_,value)|value).collect())}

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
pub fn record_procedures<'a>(archive:&'a BodyArchive,root:&Path)->Result<Vec<RecordProcedure<'a>>,Unsupported>{record_procedures_using(archive,root,&mut Compatibility)}
pub fn record_procedures_using<'a,W:DeclarationWork>(archive:&'a BodyArchive,root:&Path,work:&mut W)->Result<Vec<RecordProcedure<'a>>,W::Error>{
    work.checkpoint()?;
    let tree = archive.tree();
    let mut rows = Vec::new();
    for occurrence in archive.occurrences() {
        work.checkpoint()?;
        let member = tree
            .member(occurrence.member)
            .ok_or_else(|| Unsupported("record body member absent".into()))?;
        if !matches!(member.kind, MemberKind::Proc | MemberKind::Verb) {
            return Err(Unsupported(
                "record body names a non-callable member".into(),
            ).into());
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
            return Err(Unsupported("record signature incomplete".into()).into());
        }
        if occurrence.source.line == 0 || occurrence.source.path.as_os_str().is_empty() {
            return Err(Unsupported(
                "record definition has no issued source origin".into(),
            ).into());
        }
        row(work,&mut rows)?;rows.push(RecordProcedure {
            member: occurrence.member,
            owner,
            name: member.name,
            source: &occurrence.source,
        });
    }
    if !W::CHECKED{    rows.sort_by(|a, b| {
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
    Ok(rows)}
    else{let mut keyed=Vec::new();for value in rows{work.checkpoint()?;reserve(work,||value.source.path.as_os_str().len().checked_add(root.as_os_str().len())?.checked_mul(8)?.checked_add(512))?;let key=file(root,value.source);let name=tree.symbols().text(value.name);row(work,&mut keyed)?;keyed.push((key,value.source.line,name,value));}let mut error=None;keyed.sort_by(|a,b|{if error.is_none(){if let Err(actual)=work.checkpoint(){error=Some(actual)}}(&a.0,a.1,a.2).cmp(&(&b.0,b.1,b.2))});if let Some(actual)=error{return Err(actual)}reserve(work,||keyed.len().checked_mul(4*std::mem::size_of::<RecordProcedure<'_>>())?.checked_add(128))?;Ok(keyed.into_iter().map(|(_,_,_,value)|value).collect())}

}

#[cfg(test)]
#[path = "base_var_declarations_tests.rs"]
mod tests;
