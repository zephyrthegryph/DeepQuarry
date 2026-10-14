//! Explicit intrinsic completeness and name-indexed shared-variable inventory.
use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M};
use std::collections::BTreeMap;

/// Authoritative intrinsic member inventory for one pinned engine configuration.
/// Supply all intrinsic fields/procs/verbs, including untyped fields. A shared
/// field must name its actual declaring owner; inherited copies use that owner.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IntrinsicMember {
    pub owner: SymbolId,
    pub name: SymbolId,
    pub kind: MemberKind,
    pub shared_owner: Option<SymbolId>,
    /// Explicit instance-storage proof; shared_owner=None alone proves nothing.
    pub instance_storage_proven: bool,
}
/// Caller-supplied authoritative engine hierarchy, already merged into this
/// tree. `parents` includes root and every engine type; schema pins the source.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EngineHierarchy {
    pub schema: u128,
    pub parents: Vec<(SymbolId, Option<SymbolId>)>,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum InventoryError {
    MissingRoot,
    DuplicateType(SymbolId),
    UnknownOwner(SymbolId),
    ParentMismatch(SymbolId),
    InvalidStorage {
        owner: SymbolId,
        name: SymbolId,
    },
    ConflictingMember {
        owner: SymbolId,
        name: SymbolId,
        kind: MemberKind,
    },
}
#[derive(Clone, Debug, Default)]
pub(crate) struct ResolverInventory {
    pub(super) complete: bool,
    pub(crate) hierarchy_certified: bool,
    source_identity: Option<u128>,
    pub(crate) intrinsic: Arc<[IntrinsicMember]>,
    pub(super) index: HashMap<(SymbolId, SymbolId, MemberKind), IntrinsicMember>,
    unique: HashMap<SymbolId, Option<(SymbolId, SymbolId)>>,
    // Positive counterexamples remain valid even when other engine rows are
    // uncaptured. Absence and a single shared candidate still need completeness.
    non_unique: HashSet<SymbolId>,
    pub(crate) unique_certificates: BTreeMap<SymbolId, u64>,
}
impl SemanticTree {
    /// Borrow the captured intrinsic roster without cloning a catalog. Positive
    /// rows remain valid when incomplete; missing rows then prove no absence.
    pub fn intrinsic_members(&self) -> &[IntrinsicMember] {
        &self.inventory.intrinsic
    }
    pub fn intrinsic_inventory_complete(&self) -> bool {
        self.inventory.complete
    }
    pub fn intrinsic_hierarchy_certified(&self) -> bool {
        self.inventory.hierarchy_certified
    }

    /// The caller certifies this is the complete intrinsic inventory for the
    /// pinned engine. This produces another immutable snapshot; no global state
    /// or wire IDs enter the model. Source declarations take precedence.
    pub fn with_complete_intrinsics(
        self,
        hierarchy: EngineHierarchy,
        entries: Vec<IntrinsicMember>,
    ) -> Result<Self, InventoryError> {
        self.attach_intrinsics(hierarchy, entries, true, None, None)
    }
    /// Certify hierarchy while retaining incomplete member inventory. Known
    /// presence/slots resolve; unknown declarations remain Unsupported.
    pub fn with_engine_intrinsics(
        self,
        hierarchy: EngineHierarchy,
        entries: Vec<IntrinsicMember>,
    ) -> Result<Self, InventoryError> {
        self.attach_intrinsics(hierarchy, entries, false, None, None)
    }
    pub(crate) fn with_engine_intrinsics_on_executor(
        self,
        hierarchy: EngineHierarchy,
        entries: Vec<IntrinsicMember>,
        executor: &dm_exec::BuildExecutor,
    ) -> Result<Self, InventoryError> {
        self.attach_intrinsics(hierarchy, entries, false, Some(executor), None)
    }
    pub(crate) fn with_engine_intrinsics_retained(
        self,
        hierarchy: EngineHierarchy,
        entries: Vec<IntrinsicMember>,
        executor: Option<&dm_exec::BuildExecutor>,
        declarations: &crate::declaration_contributions::KeyedDeclarations,
        retained: &storage_inventory::RetainedStorage,
    ) -> Result<Self, InventoryError> {
        self.attach_intrinsics(
            hierarchy,
            entries,
            false,
            executor,
            Some((declarations, retained)),
        )
    }
    fn attach_intrinsics(
        mut self,
        mut hierarchy: EngineHierarchy,
        mut entries: Vec<IntrinsicMember>,
        complete: bool,
        executor: Option<&dm_exec::BuildExecutor>,
        retained: Option<(
            &crate::declaration_contributions::KeyedDeclarations,
            &storage_inventory::RetainedStorage,
        )>,
    ) -> Result<Self, InventoryError> {
        hierarchy.parents.sort_by_key(|entry| entry.0);
        let mut parents = HashMap::new();
        for &(owner, parent) in &hierarchy.parents {
            if parents.insert(owner, parent).is_some() {
                return Err(InventoryError::DuplicateType(owner));
            }
            let id = self
                .lookup_type(owner)
                .ok_or(InventoryError::UnknownOwner(owner))?;
            let actual = self.parent(id).map(|id| self.types[id.index()].path);
            if actual != parent {
                return Err(InventoryError::ParentMismatch(owner));
            }
        }
        if parents.get(&SymbolId::of("/")) != Some(&None) {
            return Err(InventoryError::MissingRoot);
        }
        for &(owner, parent) in &hierarchy.parents {
            if parent.is_some_and(|parent| !parents.contains_key(&parent)) {
                return Err(InventoryError::ParentMismatch(owner));
            }
        }
        let mut index = HashMap::new();
        for entry in &entries {
            if entry.instance_storage_proven
                && (entry.kind != MemberKind::Var || entry.shared_owner.is_some())
            {
                return Err(InventoryError::InvalidStorage {
                    owner: entry.owner,
                    name: entry.name,
                });
            }
            for owner in [Some(entry.owner), entry.shared_owner]
                .into_iter()
                .flatten()
            {
                if !parents.contains_key(&owner) {
                    return Err(InventoryError::UnknownOwner(owner));
                }
            }
            let key = (entry.owner, entry.name, entry.kind);
            if index
                .insert(key, entry.clone())
                .is_some_and(|previous| previous != *entry)
            {
                return Err(InventoryError::ConflictingMember {
                    owner: entry.owner,
                    name: entry.name,
                    kind: entry.kind,
                });
            }
        }
        entries.sort_by_key(|e| (e.owner, e.name, e.kind as u8, e.shared_owner));
        entries.dedup();
        self.owner_callables = Arc::new(Default::default());
        self.owner_callable_demands = Arc::new(Default::default());
        self.owner_callable_selections = Arc::new(Default::default());
        self.owner_variable_selections = Arc::new(Default::default());
        let source_identity = *Arc::make_mut(&mut self.inventory)
            .source_identity
            .get_or_insert(self.identity);
        self.identity = intrinsic_identity(source_identity, complete, &hierarchy, &entries);
        let inventory = Arc::make_mut(&mut self.inventory);
        inventory.complete = complete;
        inventory.hierarchy_certified = true;
        inventory.intrinsic = entries.into();
        inventory.index = index;
        if let Some((declarations, retained)) = retained {
            inventory::rebuild_retained(&mut self, executor, declarations, retained);
        } else {
            self.rebuild_inventory_on_executor(executor);
        }
        if let Some(issuer) = &self.owner_certificate_issuer {
            self.owner_callables = Arc::new(issuer.certify_callables(&self));
            self.owner_callable_selections = Arc::new(issuer.certify_selections(&self));
            self.owner_variable_selections = Arc::new(issuer.certify_variables(&self));
        }
        Ok(self)
    }
    pub(crate) fn publish_selection_owner(&mut self) {
        self.selection_publication_deferred = false;
        if let Some(issuer) = &self.owner_certificate_issuer {
            issuer.bind_selection_owner(self);
        }
    }
    pub(crate) fn refresh_metadata_identity(
        &mut self,
        source_identity: u128,
        mut hierarchy: Option<EngineHierarchy>,
    ) {
        if let Some(hierarchy) = &mut hierarchy {
            hierarchy.parents.sort_by_key(|entry| entry.0);
            let inventory = Arc::make_mut(&mut self.inventory);
            inventory.source_identity = Some(source_identity);
            self.identity = intrinsic_identity(
                source_identity,
                inventory.complete,
                hierarchy,
                &inventory.intrinsic,
            );
        } else {
            self.identity = source_identity;
        }
        self.owner_callable_demands = Arc::new(Default::default());
        self.owner_variable_selections = self.owner_certificate_issuer.as_ref().map_or_else(
            || Arc::new(Default::default()),
            |issuer| Arc::new(issuer.certify_variables(self)),
        );
        self.owner_callable_selections = self.owner_certificate_issuer.as_ref().map_or_else(
            || Arc::new(Default::default()),
            |issuer| Arc::new(issuer.certify_selections(self)),
        );
        self.owner_callables = self.owner_certificate_issuer.as_ref().map_or_else(
            || Arc::new(Default::default()),
            |issuer| Arc::new(issuer.certify_callables(self)),
        );
    }
    pub(crate) fn complete_answer(&self, query: Q, answer: M) -> M {
        if !self.inventory.hierarchy_certified && matches!(query, Q::Parent(_) | Q::Ancestry(_)) {
            return M::Unsupported(query);
        }
        if let Q::Parent(path) = query {
            if self.inventory.hierarchy_certified && self.lookup_type(path).is_some() {
                return answer;
            }
        }
        if answer == M::Missing && matches!(query, Q::Signature(_)) {
            return M::Unsupported(query);
        }
        if answer != M::Missing {
            return answer;
        }
        if !self.inventory.complete {
            return M::Unsupported(query);
        }
        // Presence-only intrinsic inventory cannot fabricate typed member data.
        let requested = match query {
            Q::Var { owner, name } | Q::Constant { owner, name } => {
                Some((owner, name, MemberKind::Var))
            }
            Q::Proc { owner, name, verb }
            | Q::ProcedureValue {
                owner, name, verb, ..
            }
            | Q::MethodProcedureValue { owner, name, verb }
            | Q::OverrideChain { owner, name, verb }
            | Q::DeclarationChain { owner, name, verb } => Some((
                owner,
                name,
                if verb {
                    MemberKind::Verb
                } else {
                    MemberKind::Proc
                },
            )),
            Q::GlobalVar(name) => Some((SymbolId::of("/"), name, MemberKind::Var)),
            Q::GlobalProc(name) => Some((SymbolId::of("/"), name, MemberKind::Proc)),
            _ => None,
        };
        if let Some((owner, name, kind)) = requested {
            let mut current = self.lookup_type(owner);
            while let Some(id) = current {
                if self
                    .inventory
                    .index
                    .contains_key(&(self.types[id.index()].path, name, kind))
                {
                    return M::Unsupported(query);
                }
                current = self.parent(id);
            }
        }
        answer
    }
    pub(crate) fn rebuild_inventory_retained(
        &mut self,
        declarations: &crate::declaration_contributions::KeyedDeclarations,
        retained: &storage_inventory::RetainedStorage,
        executor: Option<&dm_exec::BuildExecutor>,
    ) {
        inventory::rebuild_retained(self, executor, declarations, retained);
    }
    pub(crate) fn rebuild_inventory(&mut self) {
        self.rebuild_inventory_on_executor(None);
    }
    fn rebuild_inventory_on_executor(&mut self, executor: Option<&dm_exec::BuildExecutor>) {
        inventory::rebuild(self, executor);
    }
    pub(crate) fn rebuild_inventory_selectors(
        &mut self,
        selected: &HashSet<SymbolId>,
        executor: &dm_exec::BuildExecutor,
    ) {
        if !selected.is_empty() {
            inventory::rebuild_selected(self, Some(executor), Some(selected));
        }
    }
    pub(super) fn slot(owner: SymbolId, name: SymbolId) -> M {
        // Domain-separated structural identity; the returned owner/name mapping
        // lets a linker assign a slot without reverse-decoding the hash.
        // The exact (owner,name) tuple is authoritative; symbol is a convenience
        // digest and must never select a slot without verifying that tuple.
        let symbol = SymbolId::of(&format!(
            "@dm/shared/{:032x}/{:032x}",
            owner.bits(),
            name.bits()
        ));
        M::Slot {
            symbol,
            owner,
            name,
        }
    }
    /// Uniqueness within the captured declarations and supplied intrinsic rows.
    /// This is not a full-program absence proof. A resolver host must certify
    /// that no uncaptured engine field can share this name before using it.
    /// Inherited assignments share the exact formal owner/name slot; an
    /// instance field or a second distinct slot makes the name ambiguous.
    pub fn captured_variable_uniqueness(&self, name: SymbolId) -> M {
        self.inventory
            .unique
            .get(&name)
            .copied()
            .flatten()
            .map(|(owner, name)| Self::slot(owner, name))
            .unwrap_or(M::Missing)
    }
    pub(crate) fn resolve_inventory(&self, query: Q) -> M {
        match query {
            Q::UniqueStaticVar(name) => {
                if self.inventory.non_unique.contains(&name) {
                    return M::Missing;
                }
                if !self.inventory.complete {
                    return M::Unsupported(query);
                }
                self.captured_variable_uniqueness(name)
            }
            Q::HasMemberVar { .. } | Q::DeclaredVarType { .. } | Q::VarStorage { .. } => {
                self.resolve_variable_fact(query)
            }
            Q::StaticVar { owner, name } => {
                match self.resolve_variable_fact(Q::VarStorage { owner, name }) {
                    M::InstanceField { .. } => M::Missing,
                    M::Unsupported(_) => M::Unsupported(query),
                    answer => answer,
                }
            }
            Q::HasMemberProc { owner, name } => {
                let mut current = self.lookup_type(owner);
                while let Some(id) = current {
                    if owner != SymbolId::of("/")
                        && self.types[id.index()].path == SymbolId::of("/")
                    {
                        break;
                    }
                    if [MemberKind::Proc, MemberKind::Verb]
                        .iter()
                        .any(|kind| self.direct.contains_key(&(id, name, *kind)))
                        || [MemberKind::Proc, MemberKind::Verb].iter().any(|kind| {
                            self.inventory.index.contains_key(&(
                                self.types[id.index()].path,
                                name,
                                *kind,
                            ))
                        })
                    {
                        return M::Presence(true);
                    }
                    current = self.parent(id);
                }
                if self.inventory.complete {
                    M::Presence(false)
                } else {
                    M::Unsupported(query)
                }
            }
            _ => M::Unsupported(query),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::{FileId, Resolver};
    fn tree(source: &str) -> SemanticTree {
        let adapted = from_ast(
            &dm_syntax::parse(source),
            SymbolTable::default(),
            FileId(0),
            0,
            0,
        )
        .unwrap();
        build(adapted.symbols, &adapted.skeletons).unwrap()
    }
    fn hierarchy(tree: &SemanticTree) -> EngineHierarchy {
        EngineHierarchy {
            schema: 1,
            parents: tree
                .types
                .iter()
                .map(|node| (node.path, node.parent.map(|id| tree.types[id.index()].path)))
                .collect(),
        }
    }
    #[test]
    fn known_instance_field_is_not_a_shared_slot_with_partial_inventory() {
        let tree = tree("/datum/a\n    var/value = 1\n/datum/a/b\n");
        assert_eq!(
            Resolver::resolve(
                &tree,
                Q::StaticVar {
                    owner: SymbolId::of("/datum/a/b"),
                    name: SymbolId::of("value")
                }
            ),
            M::Missing
        );
        let unknown = Q::StaticVar {
            owner: SymbolId::of("/datum/a/b"),
            name: SymbolId::of("unknown"),
        };
        assert_eq!(Resolver::resolve(&tree, unknown), M::Unsupported(unknown));
    }
    #[test]
    fn source_positives_and_intrinsic_negatives_are_distinct() {
        let tree = tree("/datum/a\n    proc/read()\n        return 1\n/datum/a/b\n");
        let owner = SymbolId::of("/datum/a/b");
        assert_eq!(
            Resolver::resolve(
                &tree,
                Q::HasMemberProc {
                    owner,
                    name: SymbolId::of("read")
                }
            ),
            M::Presence(true)
        );
        let missing = Q::HasMemberProc {
            owner,
            name: SymbolId::of("missing"),
        };
        assert_eq!(Resolver::resolve(&tree, missing), M::Unsupported(missing));
        let complete = tree
            .clone()
            .with_complete_intrinsics(hierarchy(&tree), vec![])
            .unwrap();
        assert_eq!(Resolver::resolve(&complete, missing), M::Presence(false));
    }
    #[test]
    fn positive_storage_counterexamples_disprove_uniqueness_in_partial_inventory() {
        let base = tree("/datum/a\n    var/static/one\n    var/instance\n/datum/b\n    var/static/two\n/datum/c\n    var/static/two\n");
        for name in ["instance", "two"] {
            assert_eq!(
                Resolver::resolve(&base, Q::UniqueStaticVar(SymbolId::of(name))),
                M::Missing
            );
        }
        let one = Q::UniqueStaticVar(SymbolId::of("one"));
        assert_eq!(Resolver::resolve(&base, one), M::Unsupported(one));
        let unknown = Q::UniqueStaticVar(SymbolId::of("uncaptured"));
        assert_eq!(Resolver::resolve(&base, unknown), M::Unsupported(unknown));
        let opaque = IntrinsicMember {
            owner: SymbolId::of("/datum/a"),
            name: SymbolId::of("native"),
            kind: MemberKind::Var,
            shared_owner: None,
            instance_storage_proven: false,
        };
        let query = Q::UniqueStaticVar(opaque.name);
        let partial = base
            .clone()
            .with_engine_intrinsics(hierarchy(&base), vec![opaque.clone()])
            .unwrap();
        assert_eq!(Resolver::resolve(&partial, query), M::Unsupported(query));
        let proven = base
            .clone()
            .with_engine_intrinsics(
                hierarchy(&base),
                vec![IntrinsicMember {
                    instance_storage_proven: true,
                    ..opaque
                }],
            )
            .unwrap();
        assert_eq!(Resolver::resolve(&proven, query), M::Missing);
    }
    #[test]
    fn inherited_static_slots_share_formal_identity_and_require_complete_uniqueness() {
        let tree = tree("/atom\n/datum/a\n    var/static/value = 1\n/datum/a/b\n    value = 2\n");
        let name = SymbolId::of("value");
        let base = Resolver::resolve(
            &tree,
            Q::StaticVar {
                owner: SymbolId::of("/datum/a"),
                name,
            },
        );
        assert!(matches!(base,M::Slot {owner,..} if owner == SymbolId::of("/datum/a")));
        assert_eq!(
            base,
            Resolver::resolve(
                &tree,
                Q::StaticVar {
                    owner: SymbolId::of("/datum/a/b"),
                    name
                }
            )
        );
        assert_eq!(
            Resolver::resolve(&tree, Q::UniqueStaticVar(name)),
            M::Unsupported(Q::UniqueStaticVar(name))
        );
        let identity = tree.identity();
        let complete = tree
            .clone()
            .with_complete_intrinsics(hierarchy(&tree), vec![])
            .unwrap();
        assert_ne!(identity, complete.identity());
        assert_eq!(base, Resolver::resolve(&complete, Q::UniqueStaticVar(name)));
        let collision = tree
            .clone()
            .with_complete_intrinsics(
                hierarchy(&tree),
                vec![IntrinsicMember {
                    owner: SymbolId::of("/atom"),
                    name,
                    kind: MemberKind::Var,
                    shared_owner: None,
                    instance_storage_proven: false,
                }],
            )
            .unwrap();
        assert_eq!(
            Resolver::resolve(&collision, Q::UniqueStaticVar(name)),
            M::Missing
        );
        assert_ne!(collision.identity(), complete.identity());
    }
    #[test]
    fn unrelated_static_slots_are_ambiguous_and_intrinsic_order_is_canonical() {
        let tree = tree("/datum/a\n    var/static/value = 1\n/datum/b\n    var/global/value = 2\n");
        let name = SymbolId::of("value");
        let complete = tree
            .clone()
            .with_complete_intrinsics(hierarchy(&tree), vec![])
            .unwrap();
        assert_eq!(
            Resolver::resolve(&complete, Q::UniqueStaticVar(name)),
            M::Missing
        );
        let a = IntrinsicMember {
            owner: SymbolId::of("/datum/a"),
            name: SymbolId::of("x"),
            kind: MemberKind::Proc,
            shared_owner: None,
            instance_storage_proven: false,
        };
        let b = IntrinsicMember {
            name: SymbolId::of("y"),
            ..a.clone()
        };
        assert_eq!(
            tree.clone()
                .with_complete_intrinsics(hierarchy(&tree), vec![a.clone(), b.clone()])
                .unwrap()
                .identity(),
            tree.clone()
                .with_complete_intrinsics(hierarchy(&tree), vec![b, a])
                .unwrap()
                .identity()
        );
    }
    #[test]
    fn engine_parent_proof_rejects_lexical_only_hierarchy() {
        let source = tree("/atom\n/obj\n");
        let proof = EngineHierarchy {
            schema: 516,
            parents: vec![
                (SymbolId::of("/"), None),
                (SymbolId::of("/atom"), Some(SymbolId::of("/"))),
                (SymbolId::of("/obj"), Some(SymbolId::of("/atom"))),
            ],
        };
        assert!(
            matches!(source.with_complete_intrinsics(proof.clone(),vec![]),
            Err(InventoryError::ParentMismatch(owner)) if owner == SymbolId::of("/obj"))
        );
        let merged = tree("/atom\n/obj\n    parent_type = /atom\n");
        let member = IntrinsicMember {
            owner: SymbolId::of("/atom"),
            name: SymbolId::of("engine_proc"),
            kind: MemberKind::Proc,
            shared_owner: None,
            instance_storage_proven: false,
        };
        let complete = merged
            .with_complete_intrinsics(proof, vec![member.clone()])
            .unwrap();
        let query = Q::HasMemberProc {
            owner: SymbolId::of("/obj"),
            name: member.name,
        };
        assert_eq!(Resolver::resolve(&complete, query), M::Presence(true));
        let typed = Q::Proc {
            owner: SymbolId::of("/obj"),
            name: member.name,
            verb: false,
        };
        assert_eq!(Resolver::resolve(&complete, typed), M::Unsupported(typed));
        let unknown = IntrinsicMember {
            owner: SymbolId::of("/missing"),
            ..member
        };
        let source = tree("/datum\n");
        assert!(matches!(
            source
                .clone()
                .with_complete_intrinsics(hierarchy(&source), vec![unknown]),
            Err(InventoryError::UnknownOwner(_))
        ));
    }
}

mod inventory;
pub mod storage_inventory;

fn intrinsic_identity(
    source_identity: u128,
    complete: bool,
    hierarchy: &EngineHierarchy,
    entries: &[IntrinsicMember],
) -> u128 {
    let mut bytes = b"dm-tree-intrinsics-v2\0".to_vec();
    bytes.extend_from_slice(&source_identity.to_le_bytes());
    bytes.push(u8::from(complete));
    bytes.extend_from_slice(&hierarchy.schema.to_le_bytes());
    bytes.extend_from_slice(&(hierarchy.parents.len() as u64).to_le_bytes());
    for &(owner, parent) in &hierarchy.parents {
        bytes.extend_from_slice(&owner.bits().to_le_bytes());
        bytes.push(u8::from(parent.is_some()));
        if let Some(parent) = parent {
            bytes.extend_from_slice(&parent.bits().to_le_bytes());
        }
    }
    bytes.extend_from_slice(&(entries.len() as u64).to_le_bytes());
    for e in entries {
        bytes.extend_from_slice(&e.owner.bits().to_le_bytes());
        bytes.extend_from_slice(&e.name.bits().to_le_bytes());
        bytes.push(e.kind as u8);
        bytes.push(u8::from(e.instance_storage_proven));
        bytes.push(u8::from(e.shared_owner.is_some()));
        if let Some(owner) = e.shared_owner {
            bytes.extend_from_slice(&owner.bits().to_le_bytes());
        }
    }
    xxhash_rust::xxh3::xxh3_128(&bytes)
}
