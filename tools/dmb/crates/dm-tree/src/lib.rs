//! Immutable declarations independent of source paths, spans and output IDs.
//!
//! Build a semantic tree only when skeletons change. Rebuild the occurrence
//! table for every source snapshot, even when the tree remains shared in an Arc.
//! This crate intentionally has no dependency on the legacy declaration index.
mod adapter;
mod occurrence_index;
mod relative_origins;
mod skeleton_roster;
pub(crate) use adapter::SharedAdaptedDeclarations;
mod callable_namespace;
pub mod change_set;
pub mod constant_resolution;
pub mod constants;
pub mod declaration_contributions;
pub mod declaration_observations;
pub mod frontend;
mod host_declaration_selection;
pub mod initializers;
pub mod maps;
mod member_arena;
mod member_binding;
use member_binding::{MemberRead, MemberWrite};
mod member_normalization;
mod metadata_update;
pub use host_declaration_selection::HostDeclarationSelection;
pub mod owner_callable;
pub mod owner_local_shape;
pub mod owner_metadata;
mod owner_normalization;
pub use member_arena::MemberArena;
pub use owner_normalization::{
    NormalizationStorageView, ResolvedMember, SharedNormalizedDeclarations,
};
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
pub use resolver::storage_inventory::{
    StorageAnswer, StorageFact, StorageInput, StorageOwner, StorageQuery,
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
#[derive(Clone, Debug, PartialEq, Eq)]
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
    host_selections: Arc<host_declaration_selection::Selections>,
    member_callable_names: Arc<std::collections::BTreeMap<SymbolId, u8>>,
    owner_hierarchy: Arc<std::collections::BTreeMap<SymbolId, u128>>,
    owner_ancestry: Arc<std::collections::BTreeMap<SymbolId, Arc<[SymbolId]>>>,
    owner_callables: Arc<std::collections::BTreeMap<SymbolId, u128>>,
    owner_callable_demands: Arc<owner_metadata::CallableDemands>,
    owner_callable_selections: Arc<std::collections::BTreeMap<(SymbolId, SymbolId, bool), u128>>,
    owner_variable_selections: Arc<std::collections::BTreeMap<(SymbolId, SymbolId), u128>>,
    owner_certificate_issuer: Option<Arc<owner_metadata::RetainedMetadata>>,
    selection_publication_deferred: bool,
    /// Set by a clean change-set carry (no type removed): publication may skip
    /// the demand-store sweep. Never set on a full construction.
    selection_prune_skippable: bool,
    /// Types ensured by the root and engine rows, before any authored row;
    /// the change-set splice replays authored first-encounter order after it.
    /// `None` when unknown (the splice then keeps the type roster fixed).
    authored_type_start: Option<u32>,
    /// Set only by the in-place metadata update when every changed row is a
    /// formal non-const, non-shared var whose default changed between numeric
    /// literals: the output then differs only in those Variables records.
    default_edits: Option<Arc<DefaultEdits>>,
    /// Set only by the change-set splice when every changed row is an added
    /// proc or verb on an existing type (stable-numbering append patch).
    appended_callables: Option<Arc<AppendedCallables>>,
    by_path: Arc<HashMap<SymbolId, TypeId>>,
    direct: Arc<HashMap<(TypeId, SymbolId, MemberKind), MemberId>>,
    /// One target per ordered skeleton, including all reopens.
    declaration_targets: Arc<[Target]>,
    identity: u128,
    inventory: Arc<resolver::ResolverInventory>,
    intrinsic_fields: Arc<HashMap<(SymbolId, SymbolId), dm_ir::OpaqueFieldBase>>,
}
/// One numeric default edit of a formal var (see `SemanticTree::default_edits`).
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DefaultEdit {
    pub owner: SymbolId,
    pub name: SymbolId,
    /// f32 bits of the previous and the new numeric literal default.
    pub old_bits: u32,
    pub value_bits: u32,
}
/// Pure default edits from the tree with identity `from_identity`.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct DefaultEdits {
    pub from_identity: u128,
    pub edits: Vec<DefaultEdit>,
}
/// Callables added relative to the tree with identity `from_identity`.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AppendedCallables {
    pub from_identity: u128,
    /// `(owner, name, kind)` of each added row.
    pub members: Vec<(SymbolId, SymbolId, MemberKind)>,
}
impl SemanticTree {
    /// Callables added by the last splice relative to the previous tree.
    pub fn appended_callables(&self) -> Option<&AppendedCallables> {
        self.appended_callables.as_deref()
    }
    /// Pure numeric default edits relative to the previous retained tree.
    pub fn default_edits(&self) -> Option<&DefaultEdits> {
        self.default_edits.as_deref()
    }
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
    InheritedDuplicate {
        owner: SymbolId,
        previous_owner: SymbolId,
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
    /// Diagnostic access to the current immutable hierarchy certificate index.
    /// Tokens are process-local; no certificate grants authority by itself.
    /// Borrowed census owner; the store's mutation and certificate issuance APIs
    /// stay private to the semantic normalization pipeline.
    pub fn owner_certificate_issuer(&self) -> Option<&Arc<owner_metadata::RetainedMetadata>> {
        self.owner_certificate_issuer.as_ref()
    }
    pub fn owner_variable_selection_certificates(
        &self,
    ) -> &Arc<std::collections::BTreeMap<(SymbolId, SymbolId), u128>> {
        &self.owner_variable_selections
    }
    /// Queried-name certificate index for this immutable current tree.
    pub fn owner_callable_demand_certificates(&self) -> &Arc<owner_metadata::CallableDemands> {
        &self.owner_callable_demands
    }
    pub fn owner_callable_selection_certificates(
        &self,
    ) -> &Arc<std::collections::BTreeMap<(SymbolId, SymbolId, bool), u128>> {
        &self.owner_callable_selections
    }
    pub fn owner_callable_certificates(&self) -> &Arc<std::collections::BTreeMap<SymbolId, u128>> {
        &self.owner_callables
    }
    /// Exact hierarchy payload owners admitted by the existing retained issuer.
    pub fn owner_ancestry_storage(
        &self,
    ) -> &Arc<std::collections::BTreeMap<SymbolId, Arc<[SymbolId]>>> {
        &self.owner_ancestry
    }
    pub fn owner_hierarchy_certificates(&self) -> &Arc<std::collections::BTreeMap<SymbolId, u128>> {
        &self.owner_hierarchy
    }
    pub fn identity(&self) -> u128 {
        self.identity
    }
    pub fn types(&self) -> &[TypeNode] {
        &self.types
    }
    /// Share the immutable current type roster, without issuing source authority.
    pub fn shared_types(&self) -> Arc<[TypeNode]> {
        Arc::clone(&self.types)
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
    index: Arc<occurrence_index::TargetOccurrenceIndex>,
}
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct OccurrenceCountMismatch {
    pub declarations: usize,
    pub origins: usize,
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
        skeletons.into(),
        fields,
        intrinsics,
        rebuild_inventory,
        None,
    )
}
pub(crate) fn build_with_intrinsic_members_indexed(
    symbols: SymbolTable,
    skeletons: skeleton_roster::SkeletonView<'_>,
    fields: &[dm_ir::OpaqueFieldBase],
    intrinsics: &[IntrinsicMember],
    rebuild_inventory: bool,
    normalization: Option<(
        &declaration_contributions::KeyedDeclarations,
        &owner_normalization::RetainedNormalization,
    )>,
) -> Result<SemanticTree, TreeError> {
    build_with_intrinsic_members_indexed_publication(
        symbols,
        skeletons,
        fields,
        intrinsics,
        rebuild_inventory,
        normalization,
        false,
    )
}
pub(crate) fn build_with_intrinsic_members_indexed_publication(
    symbols: SymbolTable,
    skeletons: skeleton_roster::SkeletonView<'_>,
    fields: &[dm_ir::OpaqueFieldBase],
    intrinsics: &[IntrinsicMember],
    rebuild_inventory: bool,
    normalization: Option<(
        &declaration_contributions::KeyedDeclarations,
        &owner_normalization::RetainedNormalization,
    )>,
    selection_publication_deferred: bool,
) -> Result<SemanticTree, TreeError> {
    build_with_intrinsic_members_structural(
        symbols,
        skeletons,
        fields,
        intrinsics,
        rebuild_inventory,
        normalization,
        selection_publication_deferred,
        None,
    )
}
pub(crate) fn build_with_intrinsic_members_structural(
    mut symbols: SymbolTable,
    skeletons: skeleton_roster::SkeletonView<'_>,
    fields: &[dm_ir::OpaqueFieldBase],
    intrinsics: &[IntrinsicMember],
    rebuild_inventory: bool,
    normalization: Option<(
        &declaration_contributions::KeyedDeclarations,
        &owner_normalization::RetainedNormalization,
    )>,
    selection_publication_deferred: bool,
    structural: Option<metadata_update::StructuralMetadata<'_>>,
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
        host_selections: Arc::new(Default::default()),
        member_callable_names: Arc::new(Default::default()),
        owner_hierarchy: Arc::new(Default::default()),
        owner_ancestry: Arc::new(Default::default()),
        owner_callables: Arc::new(Default::default()),
        owner_callable_demands: Arc::new(Default::default()),
        owner_callable_selections: Arc::new(Default::default()),
        owner_variable_selections: Arc::new(Default::default()),
        owner_certificate_issuer: None,
        selection_publication_deferred,
        selection_prune_skippable: false,
        authored_type_start: None,
        default_edits: None,
        appended_callables: None,
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
    let member_install_timer = dm_profile::detail_timer("tree.member_install");
    let member_count = skeletons
        .iter()
        .filter(|row| matches!(row, Skeleton::Member { .. }))
        .count();
    let member_projection = normalization.and_then(|(declarations, _)| {
        member_binding::CurrentProjection::new(declarations, member_count)
    });
    let mut members = member_binding::MemberBindings::new(member_projection.as_ref());
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
        callable_namespace::collect_view(skeletons, intrinsics)?
    };
    let local_owners = normalization.map(|(declarations, retained)| {
        retained.local.prepare(&tree, declarations, &callable_kinds)
    });
    let local_members = local_owners.as_ref().and_then(|owners| {
        let (declarations, _) = normalization?;
        member_projection.as_ref()?;
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
                let local = local_members.as_ref().map(|local| local[members.len()]);
                if let Some(local) = local {
                    if let Some((key, failure)) =
                        local_owners.as_ref().unwrap()[owner].first_failure
                    {
                        if key == local.key {
                            return Err(failure.error());
                        }
                    }
                } else if tree.symbols.text(*name).is_none() {
                    return Err(TreeError::UnknownSymbol(*name));
                }
                let owner_id = tree.by_path[owner];
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
                let duplicate = local.is_none() && {
                    *mode == DefinitionMode::Declare
                        && groups.get(&key).is_some_and(|ids| {
                            ids.iter()
                                .any(|id| modes[id.index()] == DefinitionMode::Declare)
                        })
                };
                if duplicate {
                    return Err(TreeError::Duplicate {
                        owner: *owner,
                        name: *name,
                        kind,
                    });
                }
                let id =
                    MemberId(u32::try_from(members.len()).map_err(|_| TreeError::TooManyNodes)?);
                members.push(member_binding::MemberView {
                    definition: *mode,
                    owner: owner_id,
                    name: *name,
                    kind,
                    metadata,
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
        let projection = &member_projection
            .as_ref()
            .expect("local rows have current key projection")
            .ids;
        for (index, local) in local_members.iter().enumerate() {
            members.set_previous(index, local.previous.map(|key| projection[&key]));
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
    drop(member_install_timer);
    let previous_resolution_timer = dm_profile::detail_timer("tree.previous_resolution");
    let previous_resolution_profile = dm_profile::stage("frontend.tree.previous_resolution");
    let normalized = if let Some((declarations, retained)) = normalization {
        retained.resolve(
            &tree,
            &mut members,
            &modes,
            &callable_kinds,
            declarations,
            member_projection.as_ref(),
        )?
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
    drop(previous_resolution_timer);
    let metadata_inheritance_timer = dm_profile::detail_timer("tree.metadata_inheritance");
    let metadata_inheritance_profile = dm_profile::stage("frontend.tree.metadata_inheritance");
    let order = metadata_update::resolution_order(members.len(), |id| members.member(id).previous);
    tree.host_selections = Arc::new(
        if let (Some((_, retained)), Some(normalized)) = (normalization, normalized) {
            retained.metadata.resolve(
                &tree,
                &mut members,
                &normalized,
                &order,
                member_projection
                    .as_ref()
                    .expect("normalized rows have current projection"),
                structural.map(|prior| (prior, normalization.unwrap().0)),
            )
        } else {
            metadata_update::resolve_metadata(&tree, &mut members, &order);
            host_declaration_selection::collect(&tree, &members, order.iter().copied())
        },
    );
    drop(metadata_inheritance_profile);
    drop(metadata_inheritance_timer);
    let publish_timer = dm_profile::detail_timer("tree.publish_members_and_inventory");
    let mut mutable_types = tree.types.to_vec();
    for (node, ids) in mutable_types.iter_mut().zip(owned) {
        node.members = ids.into();
    }
    tree.types = mutable_types.into();
    tree.members = match normalization {
        Some((_, retained)) => retained.publish_members(&members, member_projection.as_ref()),
        None => members.bind_all(),
    };
    tree.refresh_member_callable_names();
    if rebuild_inventory {
        if let Some((index, retained)) = normalization {
            tree.rebuild_inventory_retained(index, &retained.storage, None);
        } else {
            tree.rebuild_inventory();
        }
    }
    tree.declaration_targets = targets.into();
    drop(publish_timer);
    let identity_profile = dm_profile::stage("frontend.tree.identity");
    tree.identity = if let Some((index, _)) = normalization {
        let prefix = skeletons
            .len()
            .checked_sub(index.len())
            .expect("authored index is a source suffix");
        debug_assert!(index
            .skeletons()
            .eq(skeletons.slice(prefix..skeletons.len()).iter()));
        tree_identity::retained_declaration_identity_view(skeletons.slice(0..prefix), index, fields)
    } else {
        tree_identity::declaration_identity_view(skeletons, fields)
    };
    drop(identity_profile);
    let _certify_timer = dm_profile::detail_timer("tree.certify_owners");
    if let Some((_, retained)) = normalization {
        tree.owner_certificate_issuer = Some(Arc::clone(&retained.metadata));
        let (versions, paths) = retained.metadata.certify_hierarchy(&tree);
        tree.owner_hierarchy = Arc::new(versions);
        tree.owner_ancestry = Arc::new(paths);
        tree.owner_callables = Arc::new(retained.metadata.certify_callables(&tree));
        tree.owner_callable_selections = Arc::new(retained.metadata.certify_selections(&tree));
        tree.owner_variable_selections = Arc::new(retained.metadata.certify_variables(&tree));
    }
    Ok(tree)
}
mod tree_identity;
use tree_identity::metadata_fingerprint;
mod resolver_impl;
pub use resolver_impl::{TREE_DOMAIN_VERSION_CALLS, TREE_DOMAIN_VERSION_NANOS};
mod resolver_member_names;

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

#[cfg(test)]
mod declaration_chain_tests;
