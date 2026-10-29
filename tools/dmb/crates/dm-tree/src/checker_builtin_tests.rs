use super::*;
use dm_ir::{FileId, Resolver};
fn seeded(source: &str) -> SemanticTree {
    let mut symbols = SymbolTable::default();
    let mut rows = Vec::new();
    for &(owner, parent) in data::PARENTS {
        let path = symbols.intern(owner).unwrap();
        let explicit_parent = parent.map(|p| symbols.intern(p).unwrap());
        rows.push(Skeleton::Type {
            path,
            explicit_parent,
        });
    }
    let source = crate::from_ast(&dm_syntax::parse(source), symbols, FileId(0), 0, 0).unwrap();
    rows.extend(source.skeletons.iter().cloned());
    crate::build(source.symbols, &rows).unwrap()
}
fn callable(profile: PackedU128, owner: &str, name: &str) -> Q {
    Q::CheckerIntrinsicCallable {
        profile,
        owner: SymbolId::of(owner),
        name: SymbolId::of(name),
        verb: false,
    }
}
#[test]
fn generated_catalog_is_exact_hash_bound_and_preserves_all_member_rows() {
    let catalog = pinned_catalog().unwrap();
    assert_eq!(catalog.declarations.len(), 822);
    assert_eq!(
        catalog
            .declarations
            .iter()
            .filter(|r| r.kind != MemberKind::Var)
            .count(),
        378
    );
    let mut rows = data::ROWS.to_vec();
    rows[0].name = "forged";
    assert_eq!(
        verified_profile(data::PARENTS, &rows),
        Err(CheckerBuiltinError::FactsHash)
    );
    assert_eq!(
        verified_profile(&data::PARENTS[..27], data::ROWS),
        Err(CheckerBuiltinError::FactsHash)
    );
}
#[test]
fn complete_means_pinned_checker_dsl_not_runtime_abi_inventory() {
    let original = seeded("/datum/example\n");
    let runtime = Q::IntrinsicCallable {
        owner: SymbolId::of("/datum/example"),
        name: SymbolId::of("New"),
        verb: false,
    };
    let old = Resolver::resolve(&original, runtime);
    let old_world = original.answer_world();
    let attached = original.with_pinned_checker_builtins().unwrap();
    let profile = attached.checker_builtin_profile().unwrap();
    assert_eq!(
        Resolver::resolve(&attached, callable(profile, "/datum/example", "New")),
        M::Presence(true)
    );
    assert_eq!(
        Resolver::resolve(
            &attached,
            callable(profile, "/datum/example", "not_in_fixed_dsl")
        ),
        M::Presence(false)
    );
    assert_eq!(Resolver::resolve(&attached, runtime), old);
    assert!(!attached.intrinsic_inventory_complete());
    assert_ne!(old_world, attached.answer_world());
    assert_eq!(
        attached
            .clone()
            .with_pinned_checker_builtins()
            .unwrap()
            .answer_world(),
        attached.answer_world()
    );
}
#[test]
fn wrong_or_absent_profile_and_unknown_owners_never_prove_absence() {
    let tree = seeded("");
    let profile = pinned_catalog().unwrap().profile;
    let query = callable(profile, "/datum", "New");
    assert_eq!(Resolver::resolve(&tree, query), M::Unsupported(query));
    let tree = tree.with_pinned_checker_builtins().unwrap();
    for query in [
        callable(PackedU128::new(profile.get() ^ 1), "/datum", "New"),
        callable(profile, "/missing", "New"),
    ] {
        assert_eq!(Resolver::resolve(&tree, query), M::Unsupported(query));
    }
}
#[test]
fn source_shadow_and_checker_root_lookup_are_preserved() {
    let tree=seeded("/datum/example/New()\n    return 1\n/datum/example/proc/not_in_fixed_dsl()\n    return 1\n").with_pinned_checker_builtins().unwrap();
    let profile = tree.checker_builtin_profile().unwrap();
    assert_eq!(
        Resolver::resolve(&tree, callable(profile, "/datum/example", "New")),
        M::Presence(true)
    );
    assert_eq!(
        Resolver::resolve(
            &tree,
            callable(profile, "/datum/example", "not_in_fixed_dsl")
        ),
        M::Presence(false)
    );
    assert_eq!(
        Resolver::resolve(&tree, callable(profile, "/datum/example", "abs")),
        M::Presence(true)
    );
    assert_eq!(
        Resolver::resolve(&tree, callable(profile, "/", "abs")),
        M::Presence(true)
    );
}
#[test]
fn field_types_flags_defaults_and_inherited_overrides_are_native_metadata() {
    let tree = seeded("").with_pinned_checker_builtins().unwrap();
    let profile = tree.checker_builtin_profile().unwrap();
    let query = |owner, name| Q::CheckerBuiltinVar {
        profile,
        owner: SymbolId::of(owner),
        name: SymbolId::of(name),
    };
    let M::Member { data, .. } = Resolver::resolve(&tree, query("/", "NORTH")) else {
        panic!()
    };
    assert_eq!(data.flags, 2);
    assert_eq!(
        data.resolved_constant,
        Some(SemanticValue::NumberBits(1f32.to_bits()))
    );
    let M::Member { data, .. } = Resolver::resolve(&tree, query("/area", "parent_type")) else {
        panic!()
    };
    assert_eq!(data.flags, 2);
    assert_eq!(
        data.resolved_constant,
        Some(SemanticValue::Type(SymbolId::of("/atom")))
    );
    let M::Member { data, .. } = Resolver::resolve(&tree, query("/atom", "contents")) else {
        panic!()
    };
    assert_eq!(data.declared_type, Some(SymbolId::of("/list")));
}
#[test]
fn signatures_preserve_effective_reference_defaults_not_comment_hints() {
    let catalog = pinned_catalog().unwrap();
    for row in catalog
        .declarations
        .iter()
        .filter(|r| r.kind != MemberKind::Var)
    {
        let proc = row.metadata.procedure.as_ref().unwrap();
        assert!(proc.signature.return_annotation.is_none());
        assert!(!proc.signature.variadic);
        for parameter in proc.signature.parameters.iter() {
            assert!(parameter.declared_type.is_none());
            assert!(parameter.default.is_none());
            assert!(parameter.input_annotation.is_none());
        }
    }
    assert!(catalog
        .declarations
        .iter()
        .any(|r| r.reference_parameter_defaults.iter().any(Option::is_some)));
}
#[test]
fn incompatible_existing_hierarchy_is_rejected_without_alternative_tree() {
    let mut symbols = SymbolTable::default();
    let rows = data::PARENTS
        .iter()
        .map(|&(owner, parent)| {
            let parent = if owner == "/image" {
                Some("/atom")
            } else {
                parent
            };
            Skeleton::Type {
                path: symbols.intern(owner).unwrap(),
                explicit_parent: parent.map(|p| symbols.intern(p).unwrap()),
            }
        })
        .collect::<Vec<_>>();
    let source = crate::build(symbols, &rows).unwrap();
    assert!(
        matches!(source.with_pinned_checker_builtins(),Err(CheckerBuiltinError::ParentMismatch(owner)) if owner==SymbolId::of("/image"))
    );
}

#[test]
fn checker_attachment_shares_every_common_source_and_runtime_owner() {
    let source = seeded("/datum/example/proc/probe()\n    return 1\n");
    let attached = source.clone().with_pinned_checker_builtins().unwrap();
    assert!(Arc::ptr_eq(&source.symbols, &attached.symbols));
    assert!(Arc::ptr_eq(&source.inventory, &attached.inventory));
    assert!(Arc::ptr_eq(
        &source.intrinsic_fields,
        &attached.intrinsic_fields
    ));
    assert!(Arc::ptr_eq(&source.types, &attached.types));
    assert!(Arc::ptr_eq(&source.by_path, &attached.by_path));
    assert!(Arc::ptr_eq(&source.direct, &attached.direct));
    assert!(Arc::ptr_eq(
        &source.declaration_targets,
        &attached.declaration_targets
    ));
    assert!(Arc::ptr_eq(
        source.members.chunk_offsets(),
        attached.members.chunk_offsets()
    ));
    assert_eq!(
        source.members.chunks().len(),
        attached.members.chunks().len()
    );
    for (before, after) in source
        .members
        .chunks()
        .iter()
        .zip(attached.members.chunks())
    {
        assert!(Arc::ptr_eq(before, after));
    }
    let profile = attached.checker_builtin_profile().unwrap();
    let builtin = SymbolId::of("arccos");
    assert_eq!(source.symbols.text(builtin), attached.symbols.text(builtin));
    assert_eq!(
        attached.checker_builtin_spelling(profile, builtin),
        Some("arccos")
    );
    assert!(attached
        .checker_builtin_spelling(PackedU128::new(profile.get() ^ 1), builtin)
        .is_none());
    assert_ne!(source.identity(), attached.identity());
    assert_ne!(source.answer_world(), attached.answer_world());
}
