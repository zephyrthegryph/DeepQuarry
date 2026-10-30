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
    let attached = original;
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
    assert_eq!(old_world, attached.answer_world());
    attached.validate_checker_builtin_profile(profile).unwrap();
}
#[test]
fn wrong_profile_and_unknown_owners_never_prove_absence() {
    let tree = seeded("");
    let profile = pinned_catalog().unwrap().profile;
    let query = callable(profile, "/datum", "New");
    assert_eq!(Resolver::resolve(&tree, query), M::Presence(true));
    for query in [
        callable(PackedU128::new(profile.get() ^ 1), "/datum", "New"),
        callable(profile, "/missing", "New"),
    ] {
        assert_eq!(Resolver::resolve(&tree, query), M::Unsupported(query));
    }
}
#[test]
fn source_shadow_and_checker_root_lookup_are_preserved() {
    let tree=seeded("/datum/example/New()\n    return 1\n/datum/example/proc/not_in_fixed_dsl()\n    return 1\n");
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
    let tree = seeded("");
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
        matches!(source.validate_checker_builtin_profile(pinned_catalog().unwrap().profile),Err(CheckerBuiltinError::ParentMismatch(owner)) if owner==SymbolId::of("/image"))
    );
}

#[test]
fn checker_queries_borrow_original_owner_without_cow_or_world_mutation() {
    let source = seeded("/datum/example/proc/probe()\n    return 1\n");
    let identity = source.identity();
    let world = source.answer_world();
    let symbols = Arc::as_ptr(&source.symbols);
    let inventory = Arc::as_ptr(&source.inventory);
    let members = source
        .members
        .chunks()
        .iter()
        .map(Arc::as_ptr)
        .collect::<Vec<_>>();
    let count = Arc::strong_count(&source.symbols);
    let builtin = SymbolId::of("arccos");
    let old_symbol = source.symbols.text(builtin).map(str::to_owned);
    let profile = source.checker_builtin_profile().unwrap();
    source.validate_checker_builtin_profile(profile).unwrap();
    assert_eq!(
        source.checker_builtin_spelling(profile, builtin),
        Some("arccos")
    );
    assert_eq!(
        Resolver::resolve(&source, callable(profile, "/datum/example", "New")),
        M::Presence(true)
    );
    assert!(source
        .checker_builtin_spelling(PackedU128::new(profile.get() ^ 1), builtin)
        .is_none());
    assert_eq!(source.identity(), identity);
    assert_eq!(source.answer_world(), world);
    assert_eq!(Arc::as_ptr(&source.symbols), symbols);
    assert_eq!(Arc::as_ptr(&source.inventory), inventory);
    assert_eq!(
        source
            .members
            .chunks()
            .iter()
            .map(Arc::as_ptr)
            .collect::<Vec<_>>(),
        members
    );
    assert_eq!(Arc::strong_count(&source.symbols), count);
    assert_eq!(source.symbols.text(builtin).map(str::to_owned), old_symbol);
}

#[test]
fn visibility_qualifier_domain_uses_actual_formal_declarations_not_value_overrides() {
    let catalog = super::pinned_catalog().unwrap();
    let mut declared = 0;
    let mut value_only = 0;
    for row in catalog
        .declarations
        .iter()
        .filter(|row| row.kind == MemberKind::Var)
    {
        match row.definition {
            DefinitionMode::Declare => {
                declared += 1;
                let flags = row
                    .reference_flags
                    .expect("pinned formal has complete source qualifier flags");
                assert_eq!(flags & (16|32|64),0,"profile must supply builtin note provenance before introducing a qualified builtin");
            }
            DefinitionMode::Override => {
                value_only += 1;
                assert_eq!(
                    row.reference_flags, None,
                    "value-only row must not invent a new declaration's flags"
                );
            }
            other => panic!("unexpected pinned var producer {other:?}"),
        }
    }
    assert!(declared > 0);
    assert_eq!(value_only, 11);
}

#[test]
fn checker_source_type_presence_excludes_engine_only_types_but_includes_authored_prefixes() {
    let mut symbols = SymbolTable::default();
    let mut parents = Vec::new();
    for &(path, parent) in data::PARENTS {
        symbols.intern(path).unwrap();
        parents.push((SymbolId::of(path), parent.map(SymbolId::of)));
    }
    symbols.intern("/datum/runtime_only").unwrap();
    parents.push((
        SymbolId::of("/datum/runtime_only"),
        Some(SymbolId::of("/datum")),
    ));
    let seed = crate::frontend::EngineSeed {
        identity: 1,
        symbols,
        hierarchy: crate::EngineHierarchy { schema: 2, parents },
        intrinsics: Arc::from([]),
        fields: Arc::from([]),
    };
    let authored = crate::from_ast(
        &dm_syntax::parse("/datum/authored/child/proc/read()\n    return null\n"),
        // Match the real frontend: engine hierarchy IDs must belong to the
        // authored adapter symbol roster before finish_with_engine().
        seed.symbols.clone(),
        FileId(0),
        0,
        0,
    )
    .unwrap();
    let snapshot = authored.finish_with_engine(Some(&seed)).unwrap();
    let tree = &snapshot.tree;
    let profile = tree.checker_builtin_profile().unwrap();
    assert!(tree
        .lookup_type(SymbolId::of("/datum/runtime_only"))
        .is_some());
    assert!(!tree
        .checker_source_type_presence(profile, "/datum/runtime_only")
        .unwrap());
    assert!(tree.checker_source_type_presence(profile, "/mob").unwrap());
    assert!(tree
        .checker_source_type_presence(profile, "/datum/authored")
        .unwrap());
    assert!(tree
        .checker_source_type_presence(profile, "/datum/authored/child")
        .unwrap());
    assert!(!tree
        .checker_source_type_presence(profile, "/datum/not_declared")
        .unwrap());
    assert!(tree
        .checker_source_type_presence(PackedU128::from(0u128), "/mob")
        .is_err());
}

#[test]
fn builtin_effect_identity_borrows_exact_original_metadata_and_rejects_equal_copy() {
    let tree = seeded("");
    let profile = tree.checker_builtin_profile().unwrap();
    let M::Member {
        owner, name, data, ..
    } = Resolver::resolve(
        &tree,
        Q::CheckerBuiltinProc {
            profile,
            owner: SymbolId::of("/client"),
            name: SymbolId::of("MeasureText"),
            verb: false,
        },
    )
    else {
        panic!("builtin")
    };
    let id = tree
        .checker_builtin_procedure_identity(profile, owner, name, false, &data)
        .unwrap();
    tree.with_checker_builtin_procedure(id, |row| {
        assert_eq!(row.owner, owner);
        assert_eq!(row.name, name);
        assert!(Arc::ptr_eq(&row.metadata, &data));
    })
    .unwrap();
    let copied = Arc::new(data.as_ref().clone());
    assert!(tree
        .checker_builtin_procedure_identity(profile, owner, name, false, &copied)
        .is_err());
    assert!(tree
        .checker_builtin_procedure_identity(
            PackedU128::new(profile.get() ^ 1),
            owner,
            name,
            false,
            &data
        )
        .is_err());
}
