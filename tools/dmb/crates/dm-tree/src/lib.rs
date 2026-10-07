//! Immutable declarations independent of source paths, spans and output IDs.
//!
//! Build a semantic tree only when skeletons change. Rebuild the occurrence
//! table for every source snapshot, even when the tree remains shared in an Arc.
//! This crate intentionally has no dependency on the legacy declaration index.
mod adapter;
pub mod constant_resolution;
pub mod constants;
pub mod frontend;
pub mod initializers;
pub mod maps;
pub mod non_text;
mod normalize;
mod procedure;
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
#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
pub enum MemberKind {
    Var,
    Proc,
    Verb,
}

pub use dm_ir::DeclarationMeaning as MemberMetadata;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
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
        metadata: MemberMetadata,
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
    by_path: HashMap<SymbolId, TypeId>,
    direct: HashMap<(TypeId, SymbolId, MemberKind), MemberId>,
    /// One target per ordered skeleton, including all reopens.
    declaration_targets: Arc<[Target]>,
    identity: u128,
    inventory: resolver::ResolverInventory,
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
        loop {
            if let Some(id) = self.direct.get(&(owner, name, kind)) {
                return Some(*id);
            }
            owner = self.parent(owner)?;
        }
    }
    pub fn override_chain(&self, mut id: MemberId) -> Vec<MemberId> {
        let mut result = Vec::new();
        while let Some(member) = self.member(id) {
            result.push(id);
            match member.previous {
                Some(previous) => id = previous,
                None => break,
            }
        }
        result
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
    mut symbols: SymbolTable,
    skeletons: &[Skeleton],
    fields: &[dm_ir::OpaqueFieldBase],
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
            parent_text.map(|parent| by_path[&SymbolId::of(parent.as_str())])
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
        by_path,
        direct: HashMap::new(),
        declaration_targets: Arc::from([]),
        identity: 0,
        inventory: resolver::ResolverInventory::default(),
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
    let mut members: Vec<MemberNode> = Vec::new();
    let mut targets = Vec::new();
    let mut owned = vec![Vec::new(); tree.types.len()];
    // First collect every member so inherited overrides work even when the child
    // appears before its parent. Resolve previous links only after collection.
    let mut modes = Vec::new();
    let mut groups: HashMap<(TypeId, SymbolId, MemberKind), Vec<MemberId>> = HashMap::new();
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
                let key = (owner_id, *name, *kind);
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
                        kind: *kind,
                    });
                }
                let id =
                    MemberId(u32::try_from(members.len()).map_err(|_| TreeError::TooManyNodes)?);
                members.push(MemberNode {
                    definition: *mode,
                    owner: owner_id,
                    name: *name,
                    kind: *kind,
                    metadata: Arc::new(metadata.clone()),
                    content: *content,
                    previous,
                });
                modes.push(*mode);
                groups.entry(key).or_default().push(id);
                tree.direct.insert(key, id);
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
            tree.direct.insert(key, *last);
        }
    }
    for i in 0..members.len() {
        if members[i].previous.is_none() {
            let node = &members[i];
            let mut parent = tree.parent(node.owner);
            let mut previous = None;
            while let Some(owner) = parent {
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
                        dm_ir::DeclaredTypeKnowledge::Unsupported => None,
                    };
                    metadata.inherited_opaque = Some(opaque);
                }
            }
            let node = &members[i];
            if modes[i] == DefinitionMode::Override
                && previous.is_none()
                && node.metadata.inherited_opaque.is_none()
            {
                return Err(TreeError::MissingOverride {
                    owner: tree.types[node.owner.index()].path,
                    name: node.name,
                    kind: node.kind,
                });
            }
            members[i].previous = previous;
        }
    }
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
                    metadata.flags = inherited.flags;
                    metadata.array = inherited.array.clone();
                    metadata.declared_initializer = inherited.declared_initializer.clone();
                }
            }
            resolved[i] = true;
        }
    }
    let mut mutable_types = tree.types.to_vec();
    for (node, ids) in mutable_types.iter_mut().zip(owned) {
        node.members = ids.into();
    }
    tree.types = mutable_types.into();
    tree.members = members.into();
    tree.rebuild_inventory();
    tree.declaration_targets = targets.into();
    // Hash an explicit versioned encoding; never Debug formatting or arena IDs.
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"dm-tree-v2\0");
    for skeleton in skeletons {
        match skeleton {
            Skeleton::Type {
                path,
                explicit_parent,
            } => {
                bytes.push(0);
                bytes.extend_from_slice(&path.bits().to_le_bytes());
                bytes.push(u8::from(explicit_parent.is_some()));
                bytes.extend_from_slice(
                    &explicit_parent
                        .map(SymbolId::bits)
                        .unwrap_or(0)
                        .to_le_bytes(),
                );
            }
            Skeleton::Member {
                owner,
                name,
                kind,
                mode,
                metadata,
                content,
            } => {
                bytes.push(1);
                bytes.extend_from_slice(&owner.bits().to_le_bytes());
                bytes.extend_from_slice(&name.bits().to_le_bytes());
                bytes.push(*kind as u8);
                bytes.push(*mode as u8);
                bytes.extend_from_slice(&content.to_le_bytes());
                bytes.extend_from_slice(&metadata_fingerprint(metadata).to_le_bytes());
            }
        }
    }
    let mut catalog = fields.iter().collect::<Vec<_>>();
    catalog.sort_by_key(|field| (field.owner, field.name));
    catalog.dedup();
    for field in catalog {
        let data = field.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    tree.identity = xxhash_rust::xxh3::xxh3_128(&bytes);
    Ok(tree)
}
fn metadata_fingerprint(metadata: &MemberMetadata) -> u128 {
    let mut bytes = Vec::new();
    bytes.push(u8::from(metadata.inherited_opaque.is_some()));
    if let Some(base) = &metadata.inherited_opaque {
        bytes.extend_from_slice(&base.canonical_bytes());
    }
    for symbol in [metadata.declared_type, metadata.display_name] {
        bytes.push(u8::from(symbol.is_some()));
        bytes.extend_from_slice(&symbol.map(SymbolId::bits).unwrap_or(0).to_le_bytes());
    }
    bytes.push(u8::from(metadata.array.is_some()));
    if let Some(array) = &metadata.array {
        let data = array.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.push(u8::from(metadata.procedure.is_some()));
    if let Some(procedure) = &metadata.procedure {
        let value = procedure.canonical_bytes();
        bytes.extend_from_slice(&(value.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&value);
    }
    bytes.push(u8::from(metadata.declared_initializer.is_some()));
    if let Some(initializer) = &metadata.declared_initializer {
        let data = initializer.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.push(u8::from(metadata.initializer.is_some()));
    if let Some(initializer) = &metadata.initializer {
        let data = initializer.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.push(u8::from(metadata.resolved_constant.is_some()));
    if let Some(value) = &metadata.resolved_constant {
        let data = value.canonical_bytes();
        bytes.extend_from_slice(&(data.len() as u64).to_le_bytes());
        bytes.extend_from_slice(&data);
    }
    bytes.extend_from_slice(&metadata.flags.to_le_bytes());
    bytes.extend_from_slice(&metadata.canonical);
    xxhash_rust::xxh3::xxh3_128(&bytes)
}
impl dm_ir::Resolver for SemanticTree {
    fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
        use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
        let root = SymbolId::of("/");
        let member = |owner, name, kind| {
            self.lookup_type(owner)
                .and_then(|id| self.resolve(id, name, kind))
                .map(|id| {
                    let node = &self.members[id.index()];
                    if node.metadata.inherited_opaque.is_some() {
                        return M::Unsupported(query);
                    }
                    let mut bytes = node.content.to_le_bytes().to_vec();
                    bytes.extend_from_slice(&metadata_fingerprint(&node.metadata).to_le_bytes());
                    M::Member {
                        owner: self.types[node.owner.index()].path,
                        name: node.name,
                        data: Arc::clone(&node.metadata),
                        fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes),
                    }
                })
                .unwrap_or(M::Missing)
        };
        let result = match query {
            Q::Type(path) => self
                .lookup_type(path)
                .map(|_| M::Symbol(path))
                .unwrap_or(M::Missing),
            Q::Parent(path) => self
                .lookup_type(path)
                .and_then(|id| self.parent(id))
                .map(|id| M::Symbol(self.types[id.index()].path))
                .unwrap_or(M::Missing),
            Q::Ancestry(path) => {
                let Some(mut id) = self.lookup_type(path) else {
                    return self.complete_answer(query, M::Missing);
                };
                let mut paths = Vec::new();
                loop {
                    paths.push(self.types[id.index()].path);
                    match self.parent(id) {
                        Some(parent) => id = parent,
                        None => break,
                    }
                }
                M::Symbols(paths)
            }
            Q::Var { owner, name } => member(owner, name, MemberKind::Var),
            Q::Proc { owner, name, verb } => member(
                owner,
                name,
                if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                },
            ),
            Q::GlobalVar(name) => member(root, name, MemberKind::Var),
            Q::GlobalProc(name) => member(root, name, MemberKind::Proc),
            Q::OverrideChain { owner, name, verb } => {
                let kind = if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                };
                self.lookup_type(owner)
                    .and_then(|id| self.resolve(id, name, kind))
                    .map(|id| {
                        M::Members(
                            self.override_chain(id)
                                .iter()
                                .map(|id| {
                                    let node = &self.members[id.index()];
                                    let mut bytes = node.content.to_le_bytes().to_vec();
                                    bytes.extend_from_slice(
                                        &metadata_fingerprint(&node.metadata).to_le_bytes(),
                                    );
                                    M::Member {
                                        owner: self.types[node.owner.index()].path,
                                        name: node.name,
                                        data: Arc::clone(&node.metadata),
                                        fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes),
                                    }
                                })
                                .collect(),
                        )
                    })
                    .unwrap_or(M::Missing)
            }
            // Phase1 adapter must populate typed constant/signature/resource
            // domains before callers may issue these unsupported queries.
            Q::Signature(path) => {
                let Some(text) = self.symbols.text(path) else {
                    return self.complete_answer(query, M::Missing);
                };
                let Some((owner, name)) = text
                    .rsplit_once("/proc/")
                    .or_else(|| text.rsplit_once("/verb/"))
                else {
                    return self.complete_answer(query, M::Missing);
                };
                let kind = if text.contains("/verb/") {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                };
                self.lookup_type(SymbolId::of(if owner.is_empty() { "/" } else { owner }))
                    .and_then(|id| self.resolve(id, SymbolId::of(name), kind))
                    .map(|id| {
                        let node = &self.members[id.index()];
                        match &node.metadata.procedure {
                            Some(bytes) => M::Member {
                                owner: self.types[node.owner.index()].path,
                                name: node.name,
                                data: Arc::clone(&node.metadata),
                                fingerprint: xxhash_rust::xxh3::xxh3_128(
                                    &bytes.signature.canonical_bytes(),
                                ),
                            },
                            None => M::Unsupported(query),
                        }
                    })
                    .unwrap_or(M::Missing)
            }
            Q::Constant { owner, name } => self
                .lookup_type(owner)
                .and_then(|id| self.resolve(id, name, MemberKind::Var))
                .map(|id| {
                    let node = &self.members[id.index()];
                    if node.metadata.inherited_opaque.is_some() {
                        return M::Unsupported(query);
                    }
                    match &node.metadata.resolved_constant {
                        Some(bytes) => M::Member {
                            owner: self.types[node.owner.index()].path,
                            name: node.name,
                            data: Arc::clone(&node.metadata),
                            fingerprint: xxhash_rust::xxh3::xxh3_128(&bytes.canonical_bytes()),
                        },
                        None => M::Unsupported(query),
                    }
                })
                .unwrap_or(M::Missing),
            Q::HasMemberVar { .. }
            | Q::DeclaredVarType { .. }
            | Q::VarStorage { .. }
            | Q::StaticVar { .. }
            | Q::UniqueStaticVar(_)
            | Q::HasMemberProc { .. } => {
                // Inventory queries certify their own positive/negative coverage.
                // A known instance field is authoritatively not a shared slot,
                // even while unrelated intrinsic member names remain unknown.
                return self.resolve_inventory(query);
            }
            Q::Resource(_)
            | Q::ResourceIn { .. }
            | Q::RuntimeType(_)
            | Q::PredefinedConstant(_) => M::Unsupported(query),
        };
        self.complete_answer(query, result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn symbols() -> SymbolTable {
        let mut symbols = SymbolTable::default();
        for text in ["/", "/obj", "/obj/base", "/obj/child", "value", "chain"] {
            symbols.intern(text).unwrap();
        }
        symbols
    }
    fn member(owner: &str, name: &str, mode: DefinitionMode, content: u128) -> Skeleton {
        Skeleton::Member {
            owner: SymbolId::of(owner),
            name: SymbolId::of(name),
            kind: MemberKind::Proc,
            mode,
            metadata: MemberMetadata::default(),
            content,
        }
    }
    #[test]
    fn forward_nonlexical_parent_and_override_resolve() {
        let tree = build(
            symbols(),
            &[
                Skeleton::Type {
                    path: SymbolId::of("/obj/child"),
                    explicit_parent: Some(SymbolId::of("/obj/base")),
                },
                member("/obj/child", "chain", DefinitionMode::Override, 2),
                Skeleton::Type {
                    path: SymbolId::of("/obj/base"),
                    explicit_parent: None,
                },
                member("/obj/base", "chain", DefinitionMode::Declare, 1),
            ],
        )
        .unwrap();
        let id = tree
            .resolve(
                tree.lookup_type(SymbolId::of("/obj/child")).unwrap(),
                SymbolId::of("chain"),
                MemberKind::Proc,
            )
            .unwrap();
        let chain = tree.override_chain(id);
        assert_eq!(chain.len(), 2);
        assert_eq!(tree.member(chain[1]).unwrap().content, 1);
    }
    #[test]
    fn source_relocation_does_not_change_semantic_identity() {
        let tree = build(
            symbols(),
            &[member("/obj/base", "chain", DefinitionMode::Declare, 1)],
        )
        .unwrap();
        let origin = |start| Provenance {
            span: Span {
                file: dm_ir::FileId(0),
                start,
                end: start + 1,
            },
            include_occurrence: 0,
            region: 4,
            expansion_stack: Arc::from([]),
        };
        let a = OccurrenceTable::build(&tree, vec![origin(1)]).unwrap();
        let b = OccurrenceTable::build(&tree, vec![origin(99)]).unwrap();
        assert_eq!(a.tree_identity(), b.tree_identity());
        assert_ne!(
            a.source_order()[0].provenance,
            b.source_order()[0].provenance
        );
    }
    #[test]
    fn cycles_and_duplicate_declarations_are_errors() {
        assert!(matches!(
            build(
                symbols(),
                &[
                    Skeleton::Type {
                        path: SymbolId::of("/obj/base"),
                        explicit_parent: Some(SymbolId::of("/obj/child"))
                    },
                    Skeleton::Type {
                        path: SymbolId::of("/obj/child"),
                        explicit_parent: Some(SymbolId::of("/obj/base"))
                    },
                ]
            ),
            Err(TreeError::InheritanceCycle(_))
        ));
        assert!(matches!(
            build(
                symbols(),
                &[
                    member("/obj/base", "chain", DefinitionMode::Declare, 1),
                    member("/obj/base", "chain", DefinitionMode::Declare, 2)
                ]
            ),
            Err(TreeError::Duplicate { .. })
        ));
    }
}
