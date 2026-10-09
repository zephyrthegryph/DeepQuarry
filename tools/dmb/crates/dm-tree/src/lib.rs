//! Immutable declarations independent of source paths, spans and output IDs.
//!
//! Build a semantic tree only when skeletons change. Rebuild the occurrence
//! table for every source snapshot, even when the tree remains shared in an Arc.
//! This crate intentionally has no dependency on the legacy declaration index.
mod adapter;
mod callable_namespace;
pub mod constant_resolution;
pub mod constants;
pub mod declaration_contributions;
pub mod declaration_observations;
pub mod frontend;
pub mod initializers;
pub mod maps;
mod member_arena;
mod member_normalization;
mod metadata_update;
pub mod owner_callable;
pub mod owner_local_shape;
pub mod owner_metadata;
mod owner_normalization;
pub use member_arena::MemberArena;
pub use owner_normalization::{NormalizationStorageView, ResolvedMember};
pub mod non_text;
mod normalize;
mod procedure;
pub mod procedure_statics;
mod resolver;
pub mod settings;
pub mod type_paths;
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
#[derive(
    Clone, Copy, Debug, Eq, PartialEq, PartialOrd, Ord, Hash, serde::Serialize, serde::Deserialize,
)]
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
    members: MemberArena,
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
    pub fn members(&self) -> &MemberArena {
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
    symbols: SymbolTable,
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
    intrinsics: &[IntrinsicMember],
    rebuild_inventory: bool,
) -> Result<SemanticTree, TreeError> {
    build_with_intrinsic_members_indexed(
        symbols,
        skeletons,
        fields,
        intrinsics,
        rebuild_inventory,
        None,
    )
}
pub(crate) fn build_with_intrinsic_members_indexed(
    mut symbols: SymbolTable,
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
    intrinsics: &[IntrinsicMember],
    rebuild_inventory: bool,
    normalization: Option<(
        &declaration_contributions::KeyedDeclarations,
        &owner_normalization::RetainedNormalization,
    )>,
) -> Result<SemanticTree, TreeError> {
    let mut paths = Vec::new();
    let mut by_path = HashMap::new();
    let mut lexical_parents = HashMap::new();
    let path_store = normalization.map(|(_, retained)| &retained.paths);
    fn ensure(
        path: SymbolId,
        symbols: &mut SymbolTable,
        paths: &mut Vec<SymbolId>,
        index: &mut HashMap<SymbolId, TypeId>,
        lexical_parents: &mut HashMap<SymbolId, Option<SymbolId>>,
        retained: Option<&type_paths::RetainedTypePaths>,
    ) -> Result<TypeId, TreeError> {
        if let Some(id) = index.get(&path) {
            return Ok(*id);
        }
        let parent = if let Some(retained) = retained {
            retained.resolve(path, symbols)?.parent.clone()
        } else {
            let text = symbols.text(path).ok_or(TreeError::UnknownSymbol(path))?;
            let parsed = dm_ir::TypePath::parse(text).map_err(|_| TreeError::InvalidPath(path))?;
            parsed
                .parent()
                .map(|parent| Arc::<str>::from(parent.as_str()))
        };
        let parent = parent.map(|parent| symbols.intern(&parent)).transpose()?;
        if let Some(parent) = parent {
            ensure(parent, symbols, paths, index, lexical_parents, retained)?;
        }
        lexical_parents.insert(path, parent);
        let id = TypeId(u32::try_from(paths.len()).map_err(|_| TreeError::TooManyNodes)?);
        paths.push(path);
        index.insert(path, id);
        Ok(id)
    }
    let root = symbols.intern("/")?;
    ensure(
        root,
        &mut symbols,
        &mut paths,
        &mut by_path,
        &mut lexical_parents,
        path_store,
    )?;
    for skeleton in skeletons {
        let path = match skeleton {
            Skeleton::Type { path, .. } => *path,
            Skeleton::Member { owner, .. } => *owner,
        };
        ensure(
            path,
            &mut symbols,
            &mut paths,
            &mut by_path,
            &mut lexical_parents,
            path_store,
        )?;
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
            lexical_parents[&path].map(|lexical| {
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
    if let Some(retained) = path_store {
        retained.retain(&paths);
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
        members: MemberArena::default(),
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
    let callable_kinds = if let Some((declarations, retained)) = normalization {
        retained
            .callables
            .collect(&tree, declarations, intrinsics)?
    } else {
        callable_namespace::collect(skeletons, intrinsics)?
    };
    let local_owners = normalization.map(|(declarations, retained)| {
        retained.local.prepare(&tree, declarations, &callable_kinds)
    });
    let local_members = local_owners.as_ref().and_then(|owners| {
        let (declarations, _) = normalization?;
        let members: Vec<_> = declarations
            .roster()
            .iter()
            .filter_map(|handle| owners[&handle.owner].rows[handle.row as usize].as_ref())
            .collect();
        (members.len()
            == skeletons
                .iter()
                .filter(|row| matches!(row, Skeleton::Member { .. }))
                .count())
        .then_some(members)
    });
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
                let local = local_members.as_ref().map(|local| local[members.len()]);
                let kind = local.map(|member| member.kind).unwrap_or_else(|| {
                    callable_namespace::effective_kind(
                        &tree,
                        owner_id,
                        *name,
                        *kind,
                        *mode,
                        root,
                        &callable_kinds,
                    )
                });
                let key = (owner_id, *name, kind);
                let previous = tree.direct.get(&key).copied();
                let duplicate = local
                    .map(|member| member.duplicate_formal)
                    .unwrap_or_else(|| {
                        *mode == DefinitionMode::Declare
                            && groups.get(&key).is_some_and(|ids| {
                                ids.iter()
                                    .any(|id| modes[id.index()] == DefinitionMode::Declare)
                            })
                    });
                if duplicate {
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
                if local_members.is_none() {
                    groups.entry(key).or_default().push(id);
                }
                Arc::make_mut(&mut tree.direct).insert(key, id);
                owned[owner_id.index()].push(id);
                targets.push(Target::Member(id));
            }
        }
    }
    if let Some(local_members) = &local_members {
        let projection: HashMap<_, _> = local_members
            .iter()
            .enumerate()
            .map(|(index, member)| (member.key, MemberId(index as u32)))
            .collect();
        for (index, local) in local_members.iter().enumerate() {
            members[index].previous = local.previous.map(|key| projection[&key]);
        }
        for (owner, local) in local_owners
            .as_ref()
            .expect("local members have their owner plan")
        {
            let owner_id = tree.by_path[owner];
            for &((name, kind), key) in local.selectors.iter() {
                Arc::make_mut(&mut tree.direct).insert((owner_id, name, kind), projection[&key]);
            }
        }
    } else {
        member_normalization::normalize_groups(&mut tree, &mut members, &modes, groups);
    }
    drop(member_install_profile);
    let previous_resolution_profile = dm_profile::stage("frontend.tree.previous_resolution");
    let normalized = if let Some((declarations, retained)) = normalization {
        retained.resolve(&tree, &mut members, &modes, &callable_kinds, declarations)?
    } else {
        let member_count = members.len();
        member_normalization::resolve_previous(
            &tree,
            &mut members,
            &modes,
            root,
            &callable_kinds,
            0..member_count,
        )?;
        None
    };
    drop(previous_resolution_profile);
    let metadata_inheritance_profile = dm_profile::stage("frontend.tree.metadata_inheritance");
    let order = metadata_update::resolution_order(members.len(), |id| members[id].previous);
    if let (Some((_, retained)), Some(normalized)) = (normalization, normalized) {
        retained
            .metadata
            .resolve(&tree, &mut members, &normalized, &order);
    } else {
        metadata_update::resolve_metadata(&tree, &mut members, &order);
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
    tree.identity = if let Some((index, _)) = normalization {
        let prefix = skeletons
            .len()
            .checked_sub(index.len())
            .expect("authored index is a source suffix");
        debug_assert!(index.skeletons().eq(skeletons[prefix..].iter()));
        tree_identity::retained_declaration_identity(&skeletons[..prefix], index, fields)
    } else {
        declaration_identity(skeletons, fields)
    };
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
