//! Immutable declarations independent of source paths, spans and output IDs.
//!
//! Build a semantic tree only when skeletons change. Rebuild the occurrence
//! table for every source snapshot, even when the tree remains shared in an Arc.
//! This crate intentionally has no dependency on the legacy declaration index.
mod adapter;
mod callable_namespace;
pub mod constant_resolution;
pub mod constants;
pub mod frontend;
pub mod initializers;
pub mod maps;
pub mod non_text;
mod normalize;
mod procedure;
pub mod procedure_statics;
mod resolver;
pub mod settings;
mod variable_facts;
pub use adapter::{
    from_ast, from_ast_in_scope, AdaptedDeclarations, AdapterError, SnapshotError, TreeSnapshot,
};
pub use dm_ir::{
    ExpressionToken, Parameter, ProcedureMetadata, ProcedureSetting, ProcedureSettingNode,
    ProcedureSignature, SemanticValue, SettingOperation, SymbolicExpression,
};
pub use resolver::{EngineHierarchy, IntrinsicMember, InventoryError};

use dm_ir::{Span, SymbolCollision, SymbolId, SymbolTable, TypeId};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub struct MemberId(pub u32);
impl MemberId {
    pub const fn index(self) -> usize {
        self.0 as usize
    }
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub struct OccurrenceId(pub u32);
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, serde::Serialize, serde::Deserialize)]
pub enum MemberKind {
    Var,
    Proc,
    Verb,
}

pub use dm_ir::DeclarationMeaning as MemberMetadata;

#[derive(Clone, Copy, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum DefinitionMode {
    /// A fresh declaration; repeating it on the same owner is an error.
    Declare,
    /// A method/field override. An inherited definition must exist.
    Override,
    /// Reopen a declaration on the same owner, preserving its earlier identity.
    Reopen,
    /// Bare method form: override if inherited, otherwise a new method.
    Implicit,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum Skeleton {
    Type {
        path: SymbolId,
        explicit_parent: Option<SymbolId>,
    },
    Member {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
        mode: DefinitionMode,
        metadata: Arc<MemberMetadata>,
        content: u128,
    },
}
#[derive(Clone, Debug)]
pub struct TypeNode {
    pub path: SymbolId,
    pub parent: Option<TypeId>,
    pub explicit_parent: bool,
    pub synthetic: bool,
    pub members: Arc<[MemberId]>,
}
#[derive(Clone, Debug)]
pub struct MemberNode {
    pub definition: DefinitionMode,
    pub owner: TypeId,
    pub name: SymbolId,
    pub kind: MemberKind,
    pub metadata: Arc<MemberMetadata>,
    pub content: u128,
    /// Earlier declaration in the same owner or inherited declaration.
    pub previous: Option<MemberId>,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum Target {
    Type(TypeId),
    Member(MemberId),
}
#[derive(Clone, Debug)]
pub struct SemanticTree {
    symbols: Arc<SymbolTable>,
    types: Arc<[TypeNode]>,
    members: Arc<[MemberNode]>,
    by_path: Arc<HashMap<SymbolId, TypeId>>,
    direct: Arc<HashMap<(TypeId, SymbolId, MemberKind), MemberId>>,
    /// One target per ordered skeleton, including all reopens.
    declaration_targets: Arc<[Target]>,
    identity: u128,
    inventory: Arc<resolver::ResolverInventory>,
    intrinsic_fields: Arc<HashMap<(SymbolId, SymbolId), dm_ir::OpaqueFieldBase>>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum TreeError {
    Symbol(SymbolCollision),
    UnknownSymbol(SymbolId),
    InvalidPath(SymbolId),
    ConflictingParent(SymbolId),
    InheritanceCycle(SymbolId),
    MissingParent(SymbolId),
    Duplicate {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
    MissingOverride {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
    ConflictingIntrinsicField {
        owner: SymbolId,
        name: SymbolId,
    },
    TooManyNodes,
}
impl From<SymbolCollision> for TreeError {
    fn from(e: SymbolCollision) -> Self {
        Self::Symbol(e)
    }
}

impl SemanticTree {
    /// Phase1 integration must reject unsupported queries before invoking Resolver.
    pub fn supports(&self, query: dm_ir::ResolveQuery) -> bool {
        !matches!(
            dm_ir::Resolver::resolve(self, query),
            dm_ir::ResolvedMeaning::Unsupported(_)
        )
    }
    pub fn symbols(&self) -> &SymbolTable {
        &self.symbols
    }
    pub fn shared_symbols(&self) -> Arc<SymbolTable> {
        Arc::clone(&self.symbols)
    }
    pub fn identity(&self) -> u128 {
        self.identity
    }
    pub fn types(&self) -> &[TypeNode] {
        &self.types
    }
    pub fn members(&self) -> &[MemberNode] {
        &self.members
    }
    pub fn type_node(&self, id: TypeId) -> Option<&TypeNode> {
        self.types.get(id.index())
    }
    pub fn member(&self, id: MemberId) -> Option<&MemberNode> {
        self.members.get(id.index())
    }
    pub fn lookup_type(&self, path: SymbolId) -> Option<TypeId> {
        self.by_path.get(&path).copied()
    }
    pub fn parent(&self, id: TypeId) -> Option<TypeId> {
        self.type_node(id)?.parent
    }
    pub fn declarations(&self) -> &[Target] {
        &self.declaration_targets
    }
    pub fn resolve(&self, mut owner: TypeId, name: SymbolId, kind: MemberKind) -> Option<MemberId> {
        let instance_namespace = self.types[owner.index()].path != SymbolId::of("/");
        loop {
            // The synthetic root owns globals, not inherited instance members.
            if instance_namespace && self.types[owner.index()].path == SymbolId::of("/") {
                return None;
            }
            if let Some(id) = self.direct.get(&(owner, name, kind)) {
                return Some(*id);
            }
            owner = self.parent(owner)?;
        }
    }
    pub fn override_chain_iter(&self, id: MemberId) -> impl Iterator<Item = MemberId> + '_ {
        let mut next = Some(id);
        std::iter::from_fn(move || {
            let id = next?;
            let member = self.member(id)?;
            next = member.previous;
            Some(id)
        })
    }
    pub fn override_chain(&self, id: MemberId) -> Vec<MemberId> {
        self.override_chain_iter(id).collect()
    }
    /// Owner-local ordinal in the normalized declaration/override chain.
    /// Inherited ancestors do not consume this owner's occurrence IDs.
    pub fn member_occurrence(&self, id: MemberId) -> Option<u32> {
        let member = self.member(id)?;
        let count = self
            .override_chain_iter(id)
            .filter(|prior| {
                self.member(*prior).is_some_and(|prior| {
                    prior.owner == member.owner
                        && prior.name == member.name
                        && prior.kind == member.kind
                })
            })
            .count();
        u32::try_from(count.checked_sub(1)?).ok()
    }
    /// Query-only lexical path order. Nonlexical parents may appear after a
    /// child in this view. Source occurrence order remains
    /// separate. LINK fixtures certify this view for their finite type cases,
    /// not as a universal BYOND wire-ID assignment policy.
    pub fn lexical_types(&self) -> Vec<TypeId> {
        let mut ids: Vec<_> = (0..self.types.len()).map(|i| TypeId(i as u32)).collect();
        ids.sort_by_key(|id| self.symbols.text(self.types[id.index()].path).unwrap_or(""));
        ids
    }
    /// Effective inherited verbs ordered by visible name, then source name.
    /// This is an explicit analysis view, not a claimed complete BYOND order.
    pub fn visible_verbs(&self, mut owner: TypeId) -> Vec<MemberId> {
        let mut seen = HashSet::new();
        let mut result = Vec::new();
        loop {
            for &id in self.types[owner.index()].members.iter().rev() {
                let member = &self.members[id.index()];
                if member.kind == MemberKind::Verb && seen.insert(member.name) {
                    result.push(id);
                }
            }
            match self.parent(owner) {
                Some(parent) => owner = parent,
                None => break,
            }
        }
        result.sort_by_key(|id| {
            let member = &self.members[id.index()];
            (
                self.symbols
                    .text(member.metadata.display_name.unwrap_or(member.name))
                    .unwrap_or(""),
                self.symbols.text(member.name).unwrap_or(""),
            )
        });
        result
    }
}

/// Source spans belong to the current snapshot, not to shared semantic nodes.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Provenance {
    pub span: Span,
    pub include_occurrence: u32,
    /// Byte hash of the original pre-expansion region, suitable for exports.
    pub region: u128,
    pub expansion_stack: Arc<[Span]>,
}
#[derive(Clone, Debug)]
pub struct Occurrence {
    pub target: Target,
    pub provenance: Provenance,
}
#[derive(Clone, Debug)]
pub struct OccurrenceTable {
    tree_identity: u128,
    occurrences: Arc<[Occurrence]>,
    by_target: HashMap<Target, Arc<[OccurrenceId]>>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OccurrenceCountMismatch {
    pub declarations: usize,
    pub origins: usize,
}
impl OccurrenceTable {
    pub fn build(
        tree: &SemanticTree,
        origins: Vec<Provenance>,
    ) -> Result<Self, OccurrenceCountMismatch> {
        if origins.len() != tree.declarations().len() {
            return Err(OccurrenceCountMismatch {
                declarations: tree.declarations().len(),
                origins: origins.len(),
            });
        }
        let mut groups: HashMap<Target, Vec<OccurrenceId>> = HashMap::new();
        let occurrences: Vec<_> = tree
            .declarations()
            .iter()
            .copied()
            .zip(origins)
            .enumerate()
            .map(|(i, (target, provenance))| {
                groups
                    .entry(target)
                    .or_default()
                    .push(OccurrenceId(i as u32));
                Occurrence { target, provenance }
            })
            .collect();
        Ok(Self {
            tree_identity: tree.identity(),
            occurrences: occurrences.into(),
            by_target: groups
                .into_iter()
                .map(|(key, value)| (key, value.into()))
                .collect(),
        })
    }
    pub fn tree_identity(&self) -> u128 {
        self.tree_identity
    }
    pub fn source_order(&self) -> &[Occurrence] {
        &self.occurrences
    }
    pub fn get(&self, id: OccurrenceId) -> Option<&Occurrence> {
        self.occurrences.get(id.0 as usize)
    }
    pub fn for_target(&self, target: Target) -> &[OccurrenceId] {
        self.by_target
            .get(&target)
            .map(AsRef::as_ref)
            .unwrap_or(&[])
    }
}

/// Resolve forward parent declarations before members, then preserve the exact
/// source ledger for member overrides and reopens. No body/spans enter identity.
pub fn build(symbols: SymbolTable, skeletons: &[Skeleton]) -> Result<SemanticTree, TreeError> {
    build_with_intrinsic_fields(symbols, skeletons, &[])
}

/// Link authored fields against a separate presence/type-only engine catalog.
/// Intrinsic bases have no member arena IDs and no invented source occurrences.
pub fn build_with_intrinsic_fields(
    symbols: SymbolTable,
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
) -> Result<SemanticTree, TreeError> {
    build_with_intrinsic_members(symbols, skeletons, fields, &[])
}

pub(crate) fn build_with_intrinsic_members(
    symbols: SymbolTable,
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
    intrinsics: &[IntrinsicMember],
) -> Result<SemanticTree, TreeError> {
    build_with_intrinsic_members_inventory(symbols, skeletons, fields, intrinsics, true)
}
pub(crate) fn build_with_intrinsic_members_inventory(
    mut symbols: SymbolTable,
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
    intrinsics: &[IntrinsicMember],
    rebuild_inventory: bool,
) -> Result<SemanticTree, TreeError> {
    let mut paths = Vec::new();
    let mut by_path = HashMap::new();
    fn ensure(
        path: SymbolId,
        symbols: &mut SymbolTable,
        paths: &mut Vec<SymbolId>,
        index: &mut HashMap<SymbolId, TypeId>,
    ) -> Result<TypeId, TreeError> {
        if let Some(id) = index.get(&path) {
            return Ok(*id);
        }
        let text = symbols
            .text(path)
            .ok_or(TreeError::UnknownSymbol(path))?
            .to_owned();
        let parsed = dm_ir::TypePath::parse(&text).map_err(|_| TreeError::InvalidPath(path))?;
        if let Some(parent) = parsed.parent() {
            let symbol = symbols.intern(parent.as_str())?;
            ensure(symbol, symbols, paths, index)?;
        }
        let id = TypeId(u32::try_from(paths.len()).map_err(|_| TreeError::TooManyNodes)?);
        paths.push(path);
        index.insert(path, id);
        Ok(id)
    }
    let root = symbols.intern("/")?;
    ensure(root, &mut symbols, &mut paths, &mut by_path)?;
    for skeleton in skeletons {
        let path = match skeleton {
            Skeleton::Type { path, .. } => *path,
            Skeleton::Member { owner, .. } => *owner,
        };
        ensure(path, &mut symbols, &mut paths, &mut by_path)?;
    }
    let mut explicit = HashMap::new();
    let mut declared = HashSet::new();
    for skeleton in skeletons {
        if let Skeleton::Type {
            path,
            explicit_parent,
        } = skeleton
        {
            declared.insert(*path);
            if let Some(parent) = explicit_parent {
                if !by_path.contains_key(parent) {
                    return Err(TreeError::MissingParent(*parent));
                }
                if let Some(previous) = explicit.insert(*path, *parent) {
                    if previous != *parent {
                        return Err(TreeError::ConflictingParent(*path));
                    }
                }
            }
        }
    }
    let mut types = Vec::new();
    for &path in &paths {
        let parent = if let Some(parent) = explicit.get(&path) {
            Some(by_path[parent])
        } else {
            let parent_text = dm_ir::TypePath::parse(symbols.text(path).unwrap())
                .unwrap()
                .parent();
            parent_text.map(|parent| {
                let lexical = SymbolId::of(parent.as_str());
                let datum = SymbolId::of("/datum");
                // Native ordinary top-level declarations inherit /datum.
                // Engine roots have explicit parents and take the branch above;
                // generic source-only trees without /datum retain lexical roots.
                if lexical == root && path != datum && by_path.contains_key(&datum) {
                    by_path[&datum]
                } else {
                    by_path[&lexical]
                }
            })
        };
        types.push(TypeNode {
            path,
            parent,
            explicit_parent: explicit.contains_key(&path),
            synthetic: !declared.contains(&path),
            members: Arc::from([]),
        });
    }
    // Linear graph coloring avoids per-node ancestry walks on deep trees.
    let mut colors = vec![0u8; types.len()];
    for start in 0..types.len() {
        let mut chain = Vec::new();
        let mut cursor = Some(TypeId(start as u32));
        while let Some(id) = cursor {
            match colors[id.index()] {
                2 => break,
                1 => return Err(TreeError::InheritanceCycle(types[id.index()].path)),
                _ => {}
            }
            colors[id.index()] = 1;
            chain.push(id);
            cursor = types[id.index()].parent;
        }
        for id in chain {
            colors[id.index()] = 2;
        }
    }
    let mut tree = SemanticTree {
        symbols: Arc::new(symbols),
        types: types.into(),
        members: Arc::from([]),
        by_path: Arc::new(by_path),
        direct: Arc::new(HashMap::new()),
        declaration_targets: Arc::from([]),
        identity: 0,
        inventory: Arc::new(resolver::ResolverInventory::default()),
        intrinsic_fields: Arc::new(HashMap::new()),
    };
    let mut intrinsic_fields = HashMap::new();
    for field in fields {
        let owner = tree
            .lookup_type(field.owner)
            .ok_or(TreeError::UnknownSymbol(field.owner))?;
        if tree.symbols.text(field.name).is_none() {
            return Err(TreeError::UnknownSymbol(field.name));
        }
        if let dm_ir::DeclaredTypeKnowledge::Known(path) = field.declared_type {
            if tree.symbols.text(path).is_none() {
                return Err(TreeError::UnknownSymbol(path));
            }
        }
        if intrinsic_fields
            .insert((owner, field.name), field)
            .is_some_and(|previous| previous != field)
        {
            return Err(TreeError::ConflictingIntrinsicField {
                owner: field.owner,
                name: field.name,
            });
        }
    }
    tree.intrinsic_fields = Arc::new(
        fields
            .iter()
            .map(|field| ((field.owner, field.name), field.clone()))
            .collect(),
    );
    let member_install_profile = dm_profile::stage("frontend.tree.member_install");
    let mut members: Vec<MemberNode> = Vec::new();
    let mut targets = Vec::new();
    let mut owned = vec![Vec::new(); tree.types.len()];
    // First collect every member so inherited overrides work even when the child
    // appears before its parent. Resolve previous links only after collection.
    let mut modes = Vec::new();
    let mut groups: HashMap<(TypeId, SymbolId, MemberKind), Vec<MemberId>> = HashMap::new();
    let callable_kinds = callable_namespace::collect(skeletons, intrinsics)?;
    for skeleton in skeletons {
        match skeleton {
            Skeleton::Type { path, .. } => targets.push(Target::Type(tree.by_path[path])),
            Skeleton::Member {
                owner,
                name,
                kind,
                mode,
                metadata,
                content,
            } => {
                if tree.symbols.text(*name).is_none() {
                    return Err(TreeError::UnknownSymbol(*name));
                }
                let owner_id = tree.by_path[owner];
                let kind = callable_namespace::effective_kind(
                    &tree,
                    owner_id,
                    *name,
                    *kind,
                    *mode,
                    root,
                    &callable_kinds,
                );
                let key = (owner_id, *name, kind);
                let previous = tree.direct.get(&key).copied();
                if *mode == DefinitionMode::Declare
                    && groups.get(&key).is_some_and(|ids| {
                        ids.iter()
                            .any(|id| modes[id.index()] == DefinitionMode::Declare)
                    })
                {
                    return Err(TreeError::Duplicate {
                        owner: *owner,
                        name: *name,
                        kind,
                    });
                }
                let id =
                    MemberId(u32::try_from(members.len()).map_err(|_| TreeError::TooManyNodes)?);
                members.push(MemberNode {
                    definition: *mode,
                    owner: owner_id,
                    name: *name,
                    kind,
                    metadata: Arc::clone(metadata),
                    content: *content,
                    previous,
                });
                modes.push(*mode);
                groups.entry(key).or_default().push(id);
                Arc::make_mut(&mut tree.direct).insert(key, id);
                owned[owner_id.index()].push(id);
                targets.push(Target::Member(id));
            }
        }
    }
    // Formal definitions establish a group's base irrespective of source
    // position; overrides keep encounter order. BYOND compile-only probes show
    // implicit-before-formal and formal-before-implicit compile identically.
    for (key, ids) in groups {
        let formal = ids
            .iter()
            .copied()
            .find(|id| modes[id.index()] == DefinitionMode::Declare);
        let chain: Vec<_> = formal
            .into_iter()
            .chain(ids.into_iter().filter(|id| Some(*id) != formal))
            .collect();
        let mut previous = None;
        for id in &chain {
            members[id.index()].previous = previous;
            previous = Some(*id);
        }
        if let Some(last) = chain.last() {
            Arc::make_mut(&mut tree.direct).insert(key, *last);
        }
    }
    drop(member_install_profile);
    let previous_resolution_profile = dm_profile::stage("frontend.tree.previous_resolution");
    for i in 0..members.len() {
        callable_namespace::validate_explicit(&tree, &members[i], modes[i], root, &callable_kinds)?;
        if members[i].previous.is_none() {
            let node = &members[i];
            let mut parent = tree.parent(node.owner);
            let mut previous = None;
            while let Some(owner) = parent {
                if tree.types[owner.index()].path == root {
                    break;
                }
                if let Some(id) = tree.direct.get(&(owner, node.name, node.kind)) {
                    previous = Some(*id);
                    break;
                }
                parent = tree.parent(owner);
            }
            if modes[i] == DefinitionMode::Override
                && previous.is_none()
                && node.kind == MemberKind::Var
            {
                let mut owner = Some(node.owner);
                let mut opaque = None;
                while let Some(current) = owner {
                    if let Some(field) = intrinsic_fields.get(&(current, node.name)) {
                        opaque = Some((*field).clone());
                        break;
                    }
                    owner = tree.parent(current);
                }
                if let Some(opaque) = opaque {
                    let metadata = Arc::make_mut(&mut members[i].metadata);
                    metadata.declared_type = match opaque.declared_type {
                        dm_ir::DeclaredTypeKnowledge::Known(path) => Some(path),
                        dm_ir::DeclaredTypeKnowledge::Unsupported
                        | dm_ir::DeclaredTypeKnowledge::KnownUntyped => None,
                    };
                    metadata.inherited_opaque = Some(opaque);
                }
            }
            let node = &members[i];
            if modes[i] == DefinitionMode::Override
                && previous.is_none()
                && node.metadata.inherited_opaque.is_none()
            {
                let mut ancestry = Vec::new();
                let mut cursor = Some(node.owner);
                while let Some(owner) = cursor {
                    if ancestry.len() == 16 {
                        break;
                    }
                    ancestry.push(
                        tree.symbols
                            .text(tree.types[owner.index()].path)
                            .unwrap_or("<unknown>"),
                    );
                    cursor = tree.parent(owner);
                }
                let candidates: Vec<_> = members
                    .iter()
                    .enumerate()
                    .filter(|(_, candidate)| {
                        candidate.name == node.name && candidate.kind == node.kind
                    })
                    .take(8)
                    .map(|(index, candidate)| {
                        (
                            tree.symbols
                                .text(tree.types[candidate.owner.index()].path)
                                .unwrap_or("<unknown>"),
                            modes[index],
                        )
                    })
                    .collect();
                eprintln!("dm-tree missing override: name={} ancestry={ancestry:?} source_candidates={candidates:?}", tree.symbols.text(node.name).unwrap_or("<unknown>"));
                return Err(TreeError::MissingOverride {
                    owner: tree.types[node.owner.index()].path,
                    name: node.name,
                    kind: node.kind,
                });
            }
            members[i].previous = previous;
        }
    }
    drop(previous_resolution_profile);
    let metadata_inheritance_profile = dm_profile::stage("frontend.tree.metadata_inheritance");
    // Process previous links before dependants, including child declarations
    // preceding both their parent and grandparent in the source stream.
    let mut resolved = vec![false; members.len()];
    for start in 0..members.len() {
        let mut chain = Vec::new();
        let mut cursor = Some(MemberId(start as u32));
        while let Some(id) = cursor {
            if resolved[id.index()] {
                break;
            }
            chain.push(id);
            cursor = members[id.index()].previous;
        }
        for id in chain.into_iter().rev() {
            let i = id.index();
            if modes[i] == DefinitionMode::Override && members[i].kind == MemberKind::Var {
                if let Some(previous) = members[i].previous {
                    let inherited = members[previous.index()].metadata.clone();
                    let metadata = Arc::make_mut(&mut members[i].metadata);
                    metadata.inherited_opaque = inherited.inherited_opaque.clone();
                    metadata.declared_type = inherited.declared_type;
                    metadata.list_element_type = inherited.list_element_type;
                    metadata.flags = inherited.flags;
                    metadata.array = inherited.array.clone();
                    metadata.declared_initializer = inherited.declared_initializer.clone();
                }
            }
            resolved[i] = true;
        }
    }
    drop(metadata_inheritance_profile);
    let mut mutable_types = tree.types.to_vec();
    for (node, ids) in mutable_types.iter_mut().zip(owned) {
        node.members = ids.into();
    }
    tree.types = mutable_types.into();
    tree.members = members.into();
    if rebuild_inventory {
        tree.rebuild_inventory();
    }
    tree.declaration_targets = targets.into();
    let identity_profile = dm_profile::stage("frontend.tree.identity");
    tree.identity = declaration_identity(skeletons, fields);
    drop(identity_profile);
    Ok(tree)
}
mod tree_identity;
use tree_identity::{declaration_identity, metadata_fingerprint};
mod resolver_impl;

#[cfg(test)]
#[path = "tree_tests.rs"]
mod tests;

pub mod allocation_ledger;

#[cfg(test)]
mod native_root_parent_tests {
    use super::*;
    #[test]
    fn native_ordinary_roots_default_to_datum_without_overriding_explicit_engine_roots() {
        // native_root_procpath/probe.native.bin: procpath, standalone,
        // appearance and synthetic hook all have /datum parent records.
        let mut symbols = SymbolTable::default();
        let root = symbols.intern("/").unwrap();
        let datum = symbols.intern("/datum").unwrap();
        let paths = ["/procpath", "/standalone", "/appearance", "/hook/startup"];
        let mut skeletons = vec![Skeleton::Type {
            path: datum,
            explicit_parent: Some(root),
        }];
        for path in paths {
            skeletons.push(Skeleton::Type {
                path: symbols.intern(path).unwrap(),
                explicit_parent: None,
            });
        }
        let engine = symbols.intern("/client").unwrap();
        skeletons.push(Skeleton::Type {
            path: engine,
            explicit_parent: Some(root),
        });
        let redirected = symbols.intern("/redirected").unwrap();
        skeletons.push(Skeleton::Type {
            path: redirected,
            explicit_parent: Some(engine),
        });
        let tree = build(symbols, &skeletons).unwrap();
        let parent_path = |path| {
            let id = tree.lookup_type(SymbolId::of(path)).unwrap();
            tree.type_node(tree.parent(id).unwrap()).unwrap().path
        };
        for path in ["/procpath", "/standalone", "/appearance", "/hook"] {
            assert_eq!(parent_path(path), datum);
        }
        assert_eq!(parent_path("/hook/startup"), SymbolId::of("/hook"));
        assert_eq!(parent_path("/client"), root);
        assert_eq!(parent_path("/redirected"), engine);
        assert_eq!(parent_path("/datum"), root);
        let mut symbols = SymbolTable::default();
        let ordinary = symbols.intern("/ordinary").unwrap();
        let unseeded = build(
            symbols,
            &[Skeleton::Type {
                path: ordinary,
                explicit_parent: None,
            }],
        )
        .unwrap();
        assert_eq!(
            unseeded
                .type_node(
                    unseeded
                        .parent(unseeded.lookup_type(ordinary).unwrap())
                        .unwrap()
                )
                .unwrap()
                .path,
            root
        );
    }
}

#[cfg(test)]
#[path = "shared_indexes_tests.rs"]
mod shared_indexes_tests;
