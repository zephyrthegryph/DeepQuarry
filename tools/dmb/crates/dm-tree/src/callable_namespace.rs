//! Positive callable namespace anchors for implicit declarations.
use super::*;
type CallableKinds = HashMap<(SymbolId, SymbolId), MemberKind>;
pub(crate) fn collect(
    skeletons: &[Skeleton],
    intrinsics: &[IntrinsicMember],
) -> Result<CallableKinds, TreeError> {
    // A bare callable overrides either callable namespace. Resolve its kind
    // from positive declarations before forming groups, including forward
    // formals and nonlexical parents. Explicit proc/verb declarations retain
    // their authored kind; unknown engine names supply no inferred meaning.
    let mut callable_kinds = HashMap::new();
    let mut callable_formals = HashSet::new();
    for intrinsic in intrinsics {
        if matches!(intrinsic.kind, MemberKind::Proc | MemberKind::Verb) {
            callable_kinds.insert((intrinsic.owner, intrinsic.name), intrinsic.kind);
        }
    }
    for skeleton in skeletons {
        if let Skeleton::Member {
            owner,
            name,
            kind,
            mode,
            ..
        } = skeleton
        {
            if *mode != DefinitionMode::Implicit
                && matches!(kind, MemberKind::Proc | MemberKind::Verb)
            {
                if *mode == DefinitionMode::Declare && !callable_formals.insert((*owner, *name)) {
                    return Err(TreeError::Duplicate {
                        owner: *owner,
                        name: *name,
                        kind: *kind,
                    });
                }
                callable_kinds.insert((*owner, *name), *kind);
            }
        }
    }
    Ok(callable_kinds)
}
pub(crate) fn effective_kind(
    tree: &SemanticTree,
    owner_id: TypeId,
    name: SymbolId,
    kind: MemberKind,
    mode: DefinitionMode,
    root: SymbolId,
    callable_kinds: &CallableKinds,
) -> MemberKind {
    if mode == DefinitionMode::Implicit && matches!(kind, MemberKind::Proc | MemberKind::Verb) {
        let mut cursor = Some(owner_id);
        let mut inherited = None;
        while let Some(current) = cursor {
            // Synthetic root callables belong to the global
            // namespace, not instance ancestry.
            if current != owner_id && tree.types[current.index()].path == root {
                break;
            }
            if let Some(kind) = callable_kinds.get(&(tree.types[current.index()].path, name)) {
                inherited = Some(*kind);
                break;
            }
            cursor = tree.parent(current);
        }
        inherited.unwrap_or(kind)
    } else {
        kind
    }
}
pub(crate) fn validate_explicit(
    tree: &SemanticTree,
    node: &MemberNode,
    mode: DefinitionMode,
    root: SymbolId,
    callable_kinds: &CallableKinds,
) -> Result<(), TreeError> {
    // An explicit proc declaration cannot replace a proven inherited verb
    // (or vice versa). Only the bare form inherits the callable namespace.
    if mode == DefinitionMode::Declare && matches!(node.kind, MemberKind::Proc | MemberKind::Verb) {
        let mut parent = tree.parent(node.owner);
        while let Some(owner) = parent {
            if tree.types[owner.index()].path == root {
                break;
            }
            if let Some(kind) = callable_kinds.get(&(tree.types[owner.index()].path, node.name)) {
                if *kind != node.kind {
                    return Err(TreeError::Duplicate {
                        owner: tree.types[node.owner.index()].path,
                        name: node.name,
                        kind: node.kind,
                    });
                }
                break;
            }
            parent = tree.parent(owner);
        }
    }
    Ok(())
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
    fn implicit_callable_inherits_forward_verb_namespace_and_same_owner_formal() {
        let mut base = member("/obj/base", "chain", DefinitionMode::Declare, 1);
        if let Skeleton::Member { kind, .. } = &mut base {
            *kind = MemberKind::Verb;
        }
        let tree = build(
            symbols(),
            &[
                Skeleton::Type {
                    path: SymbolId::of("/obj/child"),
                    explicit_parent: Some(SymbolId::of("/obj/base")),
                },
                member("/obj/child", "chain", DefinitionMode::Implicit, 2),
                member("/obj/base", "chain", DefinitionMode::Implicit, 3),
                base,
            ],
        )
        .unwrap();
        let child = tree.lookup_type(SymbolId::of("/obj/child")).unwrap();
        let id = tree
            .resolve(child, SymbolId::of("chain"), MemberKind::Verb)
            .unwrap();
        assert!(tree
            .resolve(child, SymbolId::of("chain"), MemberKind::Proc)
            .is_none());
        assert_eq!(
            tree.override_chain(id)
                .iter()
                .map(|id| tree.member(*id).unwrap().content)
                .collect::<Vec<_>>(),
            vec![2, 3, 1]
        );
    }
    #[test]
    fn explicit_proc_and_verb_formals_cannot_define_same_callable() {
        let mut verb = member("/obj/base", "chain", DefinitionMode::Declare, 1);
        if let Skeleton::Member { kind, .. } = &mut verb {
            *kind = MemberKind::Verb;
        }
        assert!(matches!(
            build(
                symbols(),
                &[
                    verb,
                    member("/obj/base", "chain", DefinitionMode::Declare, 2)
                ]
            ),
            Err(TreeError::Duplicate { .. })
        ));
        let mut inherited = member("/obj/base", "chain", DefinitionMode::Declare, 1);
        if let Skeleton::Member { kind, .. } = &mut inherited {
            *kind = MemberKind::Verb;
        }
        assert!(matches!(
            build(
                symbols(),
                &[
                    Skeleton::Type {
                        path: SymbolId::of("/obj/child"),
                        explicit_parent: Some(SymbolId::of("/obj/base"))
                    },
                    inherited,
                    member("/obj/child", "chain", DefinitionMode::Declare, 2),
                ]
            ),
            Err(TreeError::Duplicate { .. })
        ));
    }
    #[test]
    fn implicit_instance_callable_does_not_inherit_global_namespace() {
        let mut global = member("/", "chain", DefinitionMode::Declare, 1);
        if let Skeleton::Member { kind, .. } = &mut global {
            *kind = MemberKind::Verb;
        }
        let tree = build(
            symbols(),
            &[
                global,
                member("/obj/child", "chain", DefinitionMode::Implicit, 2),
            ],
        )
        .unwrap();
        let child = tree.lookup_type(SymbolId::of("/obj/child")).unwrap();
        let id = tree
            .resolve(child, SymbolId::of("chain"), MemberKind::Proc)
            .unwrap();
        assert_eq!(tree.member(id).unwrap().kind, MemberKind::Proc);
        assert_eq!(tree.member(id).unwrap().previous, None);
        assert!(tree
            .resolve(child, SymbolId::of("chain"), MemberKind::Verb)
            .is_none());
    }
}
