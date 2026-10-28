use super::*;
use dm_ir::{FileId, ReadDomain, Resolver};

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
        schema: 71,
        parents: tree
            .types()
            .iter()
            .map(|node| {
                (
                    node.path,
                    node.parent.map(|id| tree.types()[id.index()].path),
                )
            })
            .collect(),
    }
}

fn intrinsic(owner: &str, name: &str, kind: MemberKind) -> IntrinsicMember {
    IntrinsicMember {
        owner: SymbolId::of(owner),
        name: SymbolId::of(name),
        kind,
        shared_owner: None,
        instance_storage_proven: false,
    }
}

fn callable(owner: &str, name: &str, verb: bool) -> Q {
    Q::IntrinsicCallable {
        owner: SymbolId::of(owner),
        name: SymbolId::of(name),
        verb,
    }
}

fn method_name(name: &str) -> Q {
    Q::IntrinsicCallableName(SymbolId::of(name))
}

#[test]
fn intrinsic_callable_known_positives_work_before_inventory_is_complete() {
    let source = tree("/datum/base\n");
    let entries = vec![intrinsic("/datum/base", "native", MemberKind::Proc)];
    let partial = source
        .clone()
        .with_engine_intrinsics(hierarchy(&source), entries.clone())
        .unwrap();
    for query in [
        callable("/datum/base", "native", false),
        method_name("native"),
    ] {
        assert_eq!(Resolver::resolve(&partial, query), M::Presence(true));
    }
    for query in [
        callable("/datum/base", "absent", false),
        callable("/datum/base", "native", true),
        method_name("absent"),
    ] {
        assert_eq!(Resolver::resolve(&partial, query), M::Unsupported(query));
    }
    let complete = source
        .clone()
        .with_complete_intrinsics(hierarchy(&source), entries)
        .unwrap();
    for query in [
        callable("/datum/base", "absent", false),
        callable("/datum/base", "native", true),
        method_name("absent"),
    ] {
        assert_eq!(Resolver::resolve(&complete, query), M::Presence(false));
    }
}

#[test]
fn authored_source_shadow_does_not_erase_intrinsic_provenance() {
    let source = tree("/datum/base\n    proc/native()\n        return 42\n");
    let captured = source
        .clone()
        .with_engine_intrinsics(
            hierarchy(&source),
            vec![intrinsic("/datum/base", "native", MemberKind::Proc)],
        )
        .unwrap();
    assert!(matches!(
        Resolver::resolve(
            &captured,
            Q::Proc {
                owner: SymbolId::of("/datum/base"),
                name: SymbolId::of("native"),
                verb: false,
            }
        ),
        M::Member { .. }
    ));
    assert_eq!(
        Resolver::resolve(&captured, callable("/datum/base", "native", false)),
        M::Presence(true)
    );
    assert_eq!(
        Resolver::resolve(&captured, method_name("native")),
        M::Presence(true)
    );
}

#[test]
fn authored_proc_with_builtin_like_spelling_is_not_an_intrinsic_fact() {
    let source = tree("/datum/plain\n    proc/native()\n        return 42\n");
    let partial = source
        .clone()
        .with_engine_intrinsics(hierarchy(&source), vec![])
        .unwrap();
    for query in [
        callable("/datum/plain", "native", false),
        method_name("native"),
    ] {
        assert_eq!(Resolver::resolve(&partial, query), M::Unsupported(query));
    }
    let complete = source
        .clone()
        .with_complete_intrinsics(hierarchy(&source), vec![])
        .unwrap();
    for query in [
        callable("/datum/plain", "native", false),
        method_name("native"),
    ] {
        assert_eq!(Resolver::resolve(&complete, query), M::Presence(false));
    }
}

#[test]
fn receiver_query_walks_ancestors_without_confusing_proc_and_verb_namespaces() {
    let source = tree("/datum/base\n/datum/base/child\n");
    let captured = source
        .clone()
        .with_engine_intrinsics(
            hierarchy(&source),
            vec![
                intrinsic("/datum/base", "native", MemberKind::Proc),
                intrinsic("/datum/base", "choice", MemberKind::Verb),
            ],
        )
        .unwrap();
    assert_eq!(
        Resolver::resolve(&captured, callable("/datum/base/child", "native", false)),
        M::Presence(true)
    );
    assert_eq!(
        Resolver::resolve(&captured, callable("/datum/base/child", "choice", true)),
        M::Presence(true)
    );
    assert_eq!(
        Resolver::resolve(&captured, method_name("choice")),
        M::Presence(true)
    );
    let other_kind = callable("/datum/base/child", "choice", false);
    assert_eq!(
        Resolver::resolve(&captured, other_kind),
        M::Unsupported(other_kind)
    );
}

#[test]
fn root_global_procs_and_vars_are_not_unknown_receiver_methods() {
    let source = tree("/datum/base\n");
    let captured = source
        .clone()
        .with_complete_intrinsics(
            hierarchy(&source),
            vec![
                intrinsic("/", "global_builtin", MemberKind::Proc),
                intrinsic("/datum/base", "field_only", MemberKind::Var),
            ],
        )
        .unwrap();
    assert_eq!(
        Resolver::resolve(&captured, callable("/", "global_builtin", false)),
        M::Presence(true)
    );
    for query in [
        callable("/datum/base", "global_builtin", false),
        callable("/datum/base", "field_only", false),
        method_name("global_builtin"),
        method_name("field_only"),
    ] {
        assert_eq!(Resolver::resolve(&captured, query), M::Presence(false));
    }
}

#[test]
fn unrelated_authored_shadow_does_not_hide_an_engine_name_elsewhere() {
    let source = tree("/datum/engine\n/datum/plain\n    proc/native()\n        return 42\n");
    let captured = source
        .clone()
        .with_complete_intrinsics(
            hierarchy(&source),
            vec![intrinsic("/datum/engine", "native", MemberKind::Proc)],
        )
        .unwrap();
    assert_eq!(
        Resolver::resolve(&captured, callable("/datum/plain", "native", false)),
        M::Presence(false)
    );
    assert_eq!(
        Resolver::resolve(&captured, method_name("native")),
        M::Presence(true)
    );
}

#[test]
fn engine_inventory_and_completeness_changes_invalidate_tree_domain_answers() {
    let source = tree("/datum/base\n");
    let partial = source
        .clone()
        .with_engine_intrinsics(hierarchy(&source), vec![])
        .unwrap();
    let complete = source
        .clone()
        .with_complete_intrinsics(hierarchy(&source), vec![])
        .unwrap();
    let populated = source
        .clone()
        .with_complete_intrinsics(
            hierarchy(&source),
            vec![intrinsic("/datum/base", "native", MemberKind::Proc)],
        )
        .unwrap();
    assert_ne!(partial.answer_world(), complete.answer_world());
    assert_ne!(complete.answer_world(), populated.answer_world());
    for query in [
        callable("/datum/base", "native", false),
        method_name("native"),
    ] {
        assert_eq!(query.domain(), ReadDomain::Tree);
        assert_eq!(Resolver::resolve(&partial, query), M::Unsupported(query));
        assert_eq!(Resolver::resolve(&complete, query), M::Presence(false));
        assert_eq!(Resolver::resolve(&populated, query), M::Presence(true));
    }
}
