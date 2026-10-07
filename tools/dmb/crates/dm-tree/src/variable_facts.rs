//! Independent, conservative facts about one variable lookup.
use super::*;
use dm_ir::{DeclaredTypeKnowledge, ResolveQuery as Q, ResolvedMeaning as M};

enum Origin<'a> {
    Source(MemberId),
    Intrinsic(&'a IntrinsicMember),
}

impl SemanticTree {
    fn variable_origin(&self, owner: SymbolId, name: SymbolId) -> Option<Origin<'_>> {
        let mut current = self.lookup_type(owner);
        while let Some(id) = current {
            if let Some(member) = self.direct.get(&(id, name, MemberKind::Var)) {
                return Some(Origin::Source(*member));
            }
            let node = &self.types[id.index()];
            if let Some(entry) = self
                .inventory
                .index
                .get(&(node.path, name, MemberKind::Var))
            {
                return Some(Origin::Intrinsic(entry));
            }
            current = node.parent;
        }
        None
    }
    fn intrinsic_storage(entry: &IntrinsicMember, query: Q) -> M {
        if let Some(owner) = entry.shared_owner {
            Self::slot(owner, entry.name)
        } else if entry.instance_storage_proven {
            M::InstanceField {
                declaring_owner: entry.owner,
                name: entry.name,
            }
        } else {
            M::Unsupported(query)
        }
    }
    pub(crate) fn resolve_variable_fact(&self, query: Q) -> M {
        let (owner, name) = match query {
            Q::HasMemberVar { owner, name }
            | Q::DeclaredVarType { owner, name }
            | Q::VarStorage { owner, name } => (owner, name),
            _ => return M::Unsupported(query),
        };
        let Some(origin) = self.variable_origin(owner, name) else {
            return if !self.inventory.complete {
                M::Unsupported(query)
            } else if matches!(query, Q::HasMemberVar { .. }) {
                M::Presence(false)
            } else {
                M::Missing
            };
        };
        if matches!(query, Q::HasMemberVar { .. }) {
            return M::Presence(true);
        }
        match origin {
            Origin::Intrinsic(entry) => {
                if matches!(query, Q::VarStorage { .. }) {
                    return Self::intrinsic_storage(entry, query);
                }
                match self
                    .intrinsic_fields
                    .get(&(entry.owner, name))
                    .map(|field| &field.declared_type)
                {
                    Some(DeclaredTypeKnowledge::Known(path)) => M::DeclaredType(Some(*path)),
                    _ => M::Unsupported(query),
                }
            }
            Origin::Source(mut id) => {
                let node = &self.members[id.index()];
                if matches!(query, Q::DeclaredVarType { .. }) {
                    return match node.metadata.inherited_opaque.as_ref() {
                        Some(base) => match base.declared_type {
                            DeclaredTypeKnowledge::Known(path) => M::DeclaredType(Some(path)),
                            DeclaredTypeKnowledge::Unsupported => M::Unsupported(query),
                        },
                        None => M::DeclaredType(node.metadata.declared_type),
                    };
                }
                if let Some(base) = &node.metadata.inherited_opaque {
                    return self
                        .inventory
                        .index
                        .get(&(base.owner, base.name, MemberKind::Var))
                        .map_or(M::Unsupported(query), |entry| {
                            Self::intrinsic_storage(entry, query)
                        });
                }
                loop {
                    let node = &self.members[id.index()];
                    if matches!(
                        node.definition,
                        DefinitionMode::Override | DefinitionMode::Reopen
                    ) {
                        if let Some(previous) = node.previous {
                            id = previous;
                            continue;
                        }
                    }
                    let declaring_owner = self.types[node.owner.index()].path;
                    return if node.metadata.flags & (1 | 8) != 0 {
                        Self::slot(declaring_owner, name)
                    } else {
                        M::InstanceField {
                            declaring_owner,
                            name,
                        }
                    };
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use dm_ir::Resolver;
    fn tree(source: &str) -> SemanticTree {
        let parsed = dm_syntax::parse(source);
        let adapted =
            crate::adapter::from_ast(&parsed, SymbolTable::default(), dm_ir::FileId(0), 0, 0)
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
    fn authored_storage_and_type_are_independent_facts() {
        let tree =
            tree("/datum/a\n    var/value\n    var/static/shared\n/datum/a/b\n    shared = 2\n");
        let owner = SymbolId::of("/datum/a/b");
        let name = SymbolId::of("value");
        assert_eq!(
            Resolver::resolve(&tree, Q::HasMemberVar { owner, name }),
            M::Presence(true)
        );
        assert_eq!(
            Resolver::resolve(&tree, Q::DeclaredVarType { owner, name }),
            M::DeclaredType(None)
        );
        assert_eq!(
            Resolver::resolve(&tree, Q::VarStorage { owner, name }),
            M::InstanceField {
                declaring_owner: SymbolId::of("/datum/a"),
                name
            }
        );
        assert!(
            matches!(Resolver::resolve(&tree, Q::VarStorage { owner, name: SymbolId::of("shared") }),
            M::Slot { owner, .. } if owner == SymbolId::of("/datum/a"))
        );
        let missing = Q::HasMemberVar {
            owner,
            name: SymbolId::of("unknown"),
        };
        assert_eq!(Resolver::resolve(&tree, missing), M::Unsupported(missing));
        let complete = tree
            .clone()
            .with_complete_intrinsics(hierarchy(&tree), vec![])
            .unwrap();
        assert_eq!(Resolver::resolve(&complete, missing), M::Presence(false));
    }
    #[test]
    fn opaque_presence_does_not_invent_storage_or_type() {
        let tree = tree("/datum/a\n/datum/a/b\n");
        let owner = SymbolId::of("/datum/a/b");
        let name = SymbolId::of("native_field");
        let entry = IntrinsicMember {
            owner: SymbolId::of("/datum/a"),
            name,
            kind: MemberKind::Var,
            shared_owner: None,
            instance_storage_proven: false,
        };
        let unknown = tree
            .clone()
            .with_engine_intrinsics(hierarchy(&tree), vec![entry.clone()])
            .unwrap();
        assert_eq!(
            Resolver::resolve(&unknown, Q::HasMemberVar { owner, name }),
            M::Presence(true)
        );
        for query in [
            Q::DeclaredVarType { owner, name },
            Q::VarStorage { owner, name },
            Q::Var { owner, name },
        ] {
            assert_eq!(Resolver::resolve(&unknown, query), M::Unsupported(query));
        }
        let proven = tree
            .clone()
            .with_engine_intrinsics(
                hierarchy(&tree),
                vec![IntrinsicMember {
                    instance_storage_proven: true,
                    ..entry
                }],
            )
            .unwrap();
        assert_eq!(
            Resolver::resolve(&proven, Q::VarStorage { owner, name }),
            M::InstanceField {
                declaring_owner: SymbolId::of("/datum/a"),
                name
            }
        );
        assert_ne!(unknown.identity(), proven.identity());
    }
    #[test]
    fn authored_opaque_assignment_uses_exact_intrinsic_base() {
        let parsed = dm_syntax::parse("/datum/a\n/datum/a/b\n    native_field = 7\n");
        let adapted =
            crate::adapter::from_ast(&parsed, SymbolTable::default(), dm_ir::FileId(0), 0, 0)
                .unwrap();
        let base = dm_ir::OpaqueFieldBase {
            owner: SymbolId::of("/datum/a"),
            name: SymbolId::of("native_field"),
            declared_type: DeclaredTypeKnowledge::Known(SymbolId::of("/datum/a")),
        };
        let tree = build_with_intrinsic_fields(
            adapted.symbols,
            &adapted.skeletons,
            std::slice::from_ref(&base),
        )
        .unwrap();
        let tree = tree
            .clone()
            .with_engine_intrinsics(
                hierarchy(&tree),
                vec![IntrinsicMember {
                    owner: base.owner,
                    name: base.name,
                    kind: MemberKind::Var,
                    shared_owner: None,
                    instance_storage_proven: true,
                }],
            )
            .unwrap();
        let owner = SymbolId::of("/datum/a/b");
        assert_eq!(
            Resolver::resolve(
                &tree,
                Q::VarStorage {
                    owner,
                    name: base.name
                }
            ),
            M::InstanceField {
                declaring_owner: base.owner,
                name: base.name
            }
        );
        assert_eq!(
            Resolver::resolve(
                &tree,
                Q::DeclaredVarType {
                    owner,
                    name: base.name
                }
            ),
            M::DeclaredType(Some(base.owner))
        );
        let query = Q::Var {
            owner,
            name: base.name,
        };
        assert_eq!(Resolver::resolve(&tree, query), M::Unsupported(query));
    }
}
