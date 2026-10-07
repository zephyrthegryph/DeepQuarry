//! Pinned engine input decoded once, separate from source and output tables.
#[path = "engine_catalog.rs"]
pub mod catalog;

use byond_dmb::{
    dmb::{Dmb, Proc, Variable},
    ids::NONE,
};
use dm_ir::{SymbolId, SymbolTable};
use dm_tree::{
    EngineHierarchy, IntrinsicMember, InventoryError, MemberKind, SemanticTree, Skeleton, TreeError,
};
use std::{collections::HashMap, io, sync::Arc};

#[derive(Debug)]
pub enum EngineError {
    Decode(io::Error),
    Invalid(String),
    Symbols(dm_ir::SymbolCollision),
    Tree(TreeError),
    Inventory(InventoryError),
}
impl From<dm_ir::SymbolCollision> for EngineError {
    fn from(value: dm_ir::SymbolCollision) -> Self {
        Self::Symbols(value)
    }
}
/// Wire metadata is deliberately opaque. Its flags/value payload are not DM
/// syntax modifier bits, declared types or authoritative source defaults.
#[derive(Clone, Debug)]
pub enum OpaqueMetadata {
    Variable {
        declaration_flags: u32,
        record: Variable,
    },
    Procedure(Proc),
}
#[derive(Clone, Debug)]
pub struct OpaqueMember {
    pub owner: SymbolId,
    /// None retains unnamed engine procedures without inventing a callable name.
    pub name: Option<SymbolId>,
    pub kind: MemberKind,
    pub metadata: OpaqueMetadata,
}
#[derive(Clone, Debug)]
pub struct EngineSnapshot {
    symbols: SymbolTable,
    hierarchy: EngineHierarchy,
    types: Arc<[Skeleton]>,
    members: Arc<[IntrinsicMember]>,
    opaque: Arc<[OpaqueMember]>,
    identity: u128,
    template_identity: u128,
    catalog_fields: Arc<[catalog::CatalogField]>,
}
impl EngineSnapshot {
    /// `schema` pins the interpretation/compiler configuration as well as exact
    /// template bytes. No mutable output DMB is retained in semantic queries.
    pub fn from_bytes(bytes: &[u8], schema: u128) -> Result<Self, EngineError> {
        let dmb = Dmb::from_bytes(bytes).map_err(EngineError::Decode)?;
        let mut identity = b"dm-engine-template-v1\0".to_vec();
        identity.extend_from_slice(&schema.to_le_bytes());
        identity.extend_from_slice(bytes);
        let identity = xxhash_rust::xxh3::xxh3_128(&identity);
        let mut symbols = SymbolTable::default();
        let root = symbols.intern("/")?;
        let text = |id| -> Result<&str, EngineError> {
            let bytes = dmb
                .string(id)
                .ok_or_else(|| EngineError::Invalid(format!("missing string {id}")))?;
            std::str::from_utf8(bytes)
                .map_err(|_| EngineError::Invalid(format!("non-UTF8 semantic name {id}")))
        };
        let mut paths = Vec::new();
        let mut seen = HashMap::new();
        for class in &dmb.classes {
            let path = text(class.path_string_id())?;
            dm_ir::TypePath::parse(path).map_err(|e| EngineError::Invalid(e.into()))?;
            let symbol = symbols.intern(path)?;
            if seen.insert(symbol, paths.len()).is_some() {
                return Err(EngineError::Invalid(format!(
                    "duplicate engine class {path}"
                )));
            }
            paths.push(symbol);
        }
        let mut parents = vec![(root, None)];
        let mut types = vec![Skeleton::Type {
            path: root,
            explicit_parent: None,
        }];
        for (i, class) in dmb.classes.iter().enumerate() {
            let path = paths[i];
            if path == root {
                continue;
            }
            let parent = if class.parent_class_id() == NONE {
                root
            } else {
                *paths
                    .get(class.parent_class_id() as usize)
                    .ok_or_else(|| EngineError::Invalid("class parent out of range".into()))?
            };
            parents.push((path, Some(parent)));
            types.push(Skeleton::Type {
                path,
                explicit_parent: Some(parent),
            });
        }
        let mut members = Vec::new();
        let mut opaque = Vec::new();
        for (i, class) in dmb.classes.iter().enumerate() {
            let owner = paths[i];
            if class.defining_variable_list_id() != NONE {
                let declarations = dmb.class_variable_declarations(i).ok_or_else(|| {
                    EngineError::Invalid("malformed class variable declarations".into())
                })?;
                for (id, flags) in declarations {
                    let record = dmb
                        .variables
                        .get(id as usize)
                        .ok_or_else(|| EngineError::Invalid("variable out of range".into()))?;
                    let name = symbols.intern(text(record.name)?)?;
                    members.push(IntrinsicMember {
                        owner,
                        name,
                        kind: MemberKind::Var,
                        shared_owner: (flags & 1 != 0).then_some(owner),
                    });
                    opaque.push(OpaqueMember {
                        owner,
                        name: Some(name),
                        kind: MemberKind::Var,
                        metadata: OpaqueMetadata::Variable {
                            declaration_flags: flags,
                            record: record.clone(),
                        },
                    });
                }
            }
            for (list, kind) in [
                (class.proc_list_id(), MemberKind::Proc),
                (class.verb_list_id(), MemberKind::Verb),
            ] {
                extract_procs(
                    &dmb,
                    list,
                    owner,
                    kind,
                    &mut symbols,
                    &mut members,
                    &mut opaque,
                )?;
            }
        }
        if dmb.variable_footer != NONE {
            for (id, flags) in dmb
                .global_variable_flags()
                .ok_or_else(|| EngineError::Invalid("malformed global declarations".into()))?
            {
                let record = dmb
                    .variables
                    .get(id as usize)
                    .ok_or_else(|| EngineError::Invalid("global variable out of range".into()))?;
                let name = symbols.intern(text(record.name)?)?;
                members.push(IntrinsicMember {
                    owner: root,
                    name,
                    kind: MemberKind::Var,
                    shared_owner: Some(root),
                });
                opaque.push(OpaqueMember {
                    owner: root,
                    name: Some(name),
                    kind: MemberKind::Var,
                    metadata: OpaqueMetadata::Variable {
                        declaration_flags: flags,
                        record: record.clone(),
                    },
                });
            }
        }
        extract_procs(
            &dmb,
            dmb.world.proc_list_id(),
            root,
            MemberKind::Proc,
            &mut symbols,
            &mut members,
            &mut opaque,
        )?;
        let hierarchy = EngineHierarchy {
            schema: identity,
            parents,
        };
        // Validate hierarchy before accepting this engine input.
        dm_tree::build(symbols.clone(), &types)
            .map_err(EngineError::Tree)?
            .with_engine_intrinsics(hierarchy.clone(), members.clone())
            .map_err(EngineError::Inventory)?;
        Ok(Self {
            symbols,
            hierarchy,
            types: types.into(),
            members: members.into(),
            opaque: opaque.into(),
            identity,
            template_identity: xxhash_rust::xxh3::xxh3_128(bytes),
            catalog_fields: Arc::from([]),
        })
    }
    /// Attach the migrated bootstrap catalog only to its exact pinned template.
    /// Presence and the narrow proven type mapping are supported; defaults and
    /// modifier metadata remain opaque. This does not certify a full catalog.
    pub fn with_bootstrap_catalog(mut self) -> Result<Self, EngineError> {
        const PINNED: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
        if self.template_identity != xxhash_rust::xxh3::xxh3_128(PINNED) {
            return Err(EngineError::Invalid(
                "bootstrap catalog requires exact pinned template".into(),
            ));
        }
        if !self.catalog_fields.is_empty() {
            return Ok(self);
        }
        // The DMB world header is a singleton, outside the regular class table.
        // The pinned bootstrap treats /world as a root-owned semantic type;
        // its settings and defaults still remain opaque here.
        // /list is a native value type, likewise absent from class records.
        // These semantic roots do not assert an output class-table identity.
        for path in ["/world", "/list"] {
            let special = self.symbols.intern(path)?;
            if !self.hierarchy.parents.iter().any(|row| row.0 == special) {
                let root = self.symbols.intern("/")?;
                self.hierarchy.parents.push((special, Some(root)));
                let mut types = self.types.to_vec();
                types.push(Skeleton::Type { path: special, explicit_parent: Some(root) });
                self.types = types.into();
            }
        }
        let fields = catalog::fields(&mut self.symbols)?;
        let known: std::collections::HashSet<_> =
            self.hierarchy.parents.iter().map(|p| p.0).collect();
        let mut members = self.members.to_vec();
        let mut keys: std::collections::HashSet<_> =
            members.iter().map(|m| (m.owner, m.name, m.kind)).collect();
        let mut bytes = catalog::CATALOG_SCHEMA.as_bytes().to_vec();
        bytes.extend_from_slice(&self.identity.to_le_bytes());
        for field in &fields {
            if !known.contains(&field.owner) {
                return Err(EngineError::Invalid(format!(
                    "catalog owner {} missing from pinned hierarchy",
                    self.symbols.text(field.owner).unwrap_or("<unknown>")
                )));
            }
            bytes.extend_from_slice(&field.owner.bits().to_le_bytes());
            bytes.extend_from_slice(&field.name.bits().to_le_bytes());
            match field.declared_type {
                catalog::FieldTypeMeaning::Known(ty) => {
                    bytes.push(1);
                    bytes.extend_from_slice(&ty.bits().to_le_bytes());
                }
                catalog::FieldTypeMeaning::Unsupported => bytes.push(0),
            }
            if keys.insert((field.owner, field.name, MemberKind::Var)) {
                members.push(field.presence());
            }
        }
        self.identity = xxhash_rust::xxh3::xxh3_128(&bytes);
        self.hierarchy.schema = self.identity;
        self.members = members.into();
        self.catalog_fields = fields.into();
        dm_tree::build(self.symbols.clone(), &self.types)
            .map_err(EngineError::Tree)?
            .with_engine_intrinsics(self.hierarchy.clone(), self.members.to_vec())
            .map_err(EngineError::Inventory)?;
        Ok(self)
    }
    pub fn catalog_fields(&self) -> &[catalog::CatalogField] {
        &self.catalog_fields
    }
    pub fn identity(&self) -> u128 {
        self.identity
    }
    pub fn symbols(&self) -> &SymbolTable {
        &self.symbols
    }
    pub fn hierarchy(&self) -> &EngineHierarchy {
        &self.hierarchy
    }
    pub fn type_skeletons(&self) -> &[Skeleton] {
        &self.types
    }
    pub fn intrinsic_members(&self) -> &[IntrinsicMember] {
        &self.members
    }
    pub fn opaque_members(&self) -> &[OpaqueMember] {
        &self.opaque
    }
    pub fn field_bases(&self) -> Vec<dm_ir::OpaqueFieldBase> {
        self.catalog_fields.iter().map(|field| dm_ir::OpaqueFieldBase {
            owner: field.owner,
            name: field.name,
            declared_type: match field.declared_type {
                catalog::FieldTypeMeaning::Known(path) => dm_ir::DeclaredTypeKnowledge::Known(path),
                catalog::FieldTypeMeaning::Unsupported => dm_ir::DeclaredTypeKnowledge::Unsupported,
            },
        }).collect()
    }
    pub fn frontend_seed(&self) -> dm_tree::frontend::EngineSeed {
        dm_tree::frontend::EngineSeed {
            identity: self.identity,
            symbols: self.symbols.clone(),
            hierarchy: self.hierarchy.clone(),
            intrinsics: self.members.clone(),
            fields: self.field_bases().into(),
        }
    }
    pub fn seed_symbols(&self, mut source: SymbolTable) -> Result<SymbolTable, EngineError> {
        for (_, text) in self.symbols.ordered() {
            source.intern(text)?;
        }
        Ok(source)
    }
    /// Merge engine hierarchy before resolving source declarations. Raw intrinsic
    /// member metadata is not invented into source MemberMetadata. Assignments
    /// requiring an opaque intrinsic base can still return MissingOverride until
    /// dm-tree implements that separate, explicit declaration representation.
    pub fn build_tree(
        &self,
        source_symbols: SymbolTable,
        source: &[Skeleton],
    ) -> Result<SemanticTree, EngineError> {
        let symbols = self.seed_symbols(source_symbols)?;
        let mut declarations = self.types.to_vec();
        declarations.extend_from_slice(source);
        dm_tree::build_with_intrinsic_fields(symbols, &declarations, &self.field_bases())
            .map_err(EngineError::Tree)?
            .with_engine_intrinsics(self.hierarchy.clone(), self.members.to_vec())
            .map_err(EngineError::Inventory)
    }
}
fn extract_procs(
    dmb: &Dmb,
    list: u32,
    owner: SymbolId,
    kind: MemberKind,
    symbols: &mut SymbolTable,
    members: &mut Vec<IntrinsicMember>,
    opaque: &mut Vec<OpaqueMember>,
) -> Result<(), EngineError> {
    if list == NONE {
        return Ok(());
    }
    let ids = dmb
        .lists
        .get(list as usize)
        .ok_or_else(|| EngineError::Invalid("procedure list out of range".into()))?;
    for id in ids {
        let record = dmb
            .procs
            .get(*id as usize)
            .ok_or_else(|| EngineError::Invalid("procedure out of range".into()))?;
        let path = dmb
            .string(record.strings[0])
            .and_then(|v| std::str::from_utf8(v).ok())
            .ok_or_else(|| EngineError::Invalid("invalid procedure path".into()))?;
        let Some(name) = path.rsplit('/').next().filter(|v| !v.is_empty()) else {
            opaque.push(OpaqueMember {
                owner,
                name: None,
                kind,
                metadata: OpaqueMetadata::Procedure(record.clone()),
            });
            continue;
        };
        symbols.intern(path)?;
        let name = symbols.intern(name)?;
        members.push(IntrinsicMember {
            owner,
            name,
            kind,
            shared_owner: None,
        });
        opaque.push(OpaqueMember {
            owner,
            name: Some(name),
            kind,
            metadata: OpaqueMetadata::Procedure(record.clone()),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
    const TEMPLATE: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
    #[test]
    fn pinned_template_preserves_engine_hierarchy_and_exact_identity() {
        let engine = EngineSnapshot::from_bytes(TEMPLATE, 1).unwrap();
        let tree = engine.build_tree(SymbolTable::default(), &[]).unwrap();
        let obj = tree.lookup_type(SymbolId::of("/obj")).unwrap();
        assert_eq!(
            tree.symbols().text(tree.type_node(tree.parent(obj).unwrap()).unwrap().path),
            Some("/atom/movable")
        );
        assert_eq!(
            engine.identity(),
            EngineSnapshot::from_bytes(TEMPLATE, 1).unwrap().identity()
        );
        assert_ne!(
            engine.identity(),
            EngineSnapshot::from_bytes(TEMPLATE, 2).unwrap().identity()
        );
        let missing = ResolveQuery::HasMemberProc {
            owner: SymbolId::of("/obj"),
            name: SymbolId::of("__absent_engine_member"),
        };
        assert_eq!(
            Resolver::resolve(&tree, missing),
            ResolvedMeaning::Unsupported(missing)
        );
        for entry in engine
            .intrinsic_members()
            .iter()
            .filter(|e| matches!(e.kind, MemberKind::Proc | MemberKind::Verb))
        {
            assert_eq!(
                Resolver::resolve(
                    &tree,
                    ResolveQuery::HasMemberProc {
                        owner: entry.owner,
                        name: entry.name
                    }
                ),
                ResolvedMeaning::Presence(true)
            );
        }
    }
    #[test]
    fn pinned_catalog_has_supported_types_and_opaque_remainder() {
        let engine = EngineSnapshot::from_bytes(TEMPLATE, 1).unwrap();
        let original = engine.identity();
        let engine = engine.with_bootstrap_catalog().unwrap();
        assert_ne!(original, engine.identity());
        assert!(engine
            .catalog_fields()
            .iter()
            .any(|field| field.owner == SymbolId::of("/atom")
                && field.name == SymbolId::of("loc")
                && field.declared_type == catalog::FieldTypeMeaning::Known(SymbolId::of("/atom"))));
        assert!(engine
            .catalog_fields()
            .iter()
            .any(|field| field.name == SymbolId::of("icon")
                && field.declared_type == catalog::FieldTypeMeaning::Unsupported));
        assert_eq!(
            engine.identity(),
            engine.clone().with_bootstrap_catalog().unwrap().identity()
        );
    }
    #[test]
    fn invalid_template_is_an_explicit_decode_error() {
        assert!(matches!(
            EngineSnapshot::from_bytes(b"invalid", 1),
            Err(EngineError::Decode(_))
        ));
    }
}
