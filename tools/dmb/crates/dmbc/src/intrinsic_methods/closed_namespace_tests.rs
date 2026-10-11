use super::*;
#[test]
fn documented_datum_namespace_closes_arbitrary_missing_names_only_on_reviewed_hierarchy() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/probe/proc/present()\n    return 1\n/datum/open\n    parent_type = /client\n/datum/probe/verb/Copy()\n    return 2\n/datum/probe/verb/verb_only()\n    return 3\n".into())
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = crate::engine_host::ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = crate::engine_host::RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        crate::engine_host::Completeness::Partial,
    )
    .unwrap();
    let host = crate::engine_host::EngineResolverHost::new(
        frontend.snapshot.tree.clone(),
        constants,
        runtime,
    )
    .with_pinned_callables(&engine, &frontend)
    .unwrap();
    use dm_ir::Resolver;
    assert!(matches!(
        host.resolve(ResolveQuery::Proc {
            owner: SymbolId::of("/list"),
            name: SymbolId::of("Copy"),
            verb: false
        }),
        ResolvedMeaning::IntrinsicProc { .. } | ResolvedMeaning::RetainedProc { .. }
    ));
    for owner in ["/datum", "/datum/probe", "/list"] {
        for name in [
            "arbitrary_missing_one",
            "arbitrary_missing_two",
            "formerly_missing",
        ] {
            for query in [
                ResolveQuery::Proc {
                    owner: SymbolId::of(owner),
                    name: SymbolId::of(name),
                    verb: false,
                },
                ResolveQuery::Proc {
                    owner: SymbolId::of(owner),
                    name: SymbolId::of(name),
                    verb: true,
                },
            ] {
                assert_eq!(host.resolve(query), ResolvedMeaning::Missing);
            }
            assert_eq!(
                host.resolve(ResolveQuery::HasMemberProc {
                    owner: SymbolId::of(owner),
                    name: SymbolId::of(name)
                }),
                ResolvedMeaning::Presence(false)
            );
        }
    }
    assert!(matches!(
        host.resolve(ResolveQuery::Proc {
            owner: SymbolId::of("/datum/probe"),
            name: SymbolId::of("present"),
            verb: false
        }),
        ResolvedMeaning::Member { .. }
    ));
    for owner in ["/client", "/datum/open"] {
        let query = ResolveQuery::Proc {
            owner: SymbolId::of(owner),
            name: SymbolId::of("arbitrary_missing_one"),
            verb: false,
        };
        assert_eq!(host.resolve(query), ResolvedMeaning::Unsupported(query));
    }
    for owner in ["/not_current"] {
        let query = ResolveQuery::Proc {
            owner: SymbolId::of(owner),
            name: SymbolId::of("arbitrary_missing_one"),
            verb: false,
        };
        assert_eq!(host.resolve(query), ResolvedMeaning::Unsupported(query));
    }
    for name in ["present", "New", "Copy"] {
        assert_eq!(
            host.resolve(ResolveQuery::MemberCallableName(SymbolId::of(name))),
            ResolvedMeaning::Presence(true)
        );
    }
    for name in ["arbitrary_missing_one", "arbitrary_missing_two"] {
        assert_eq!(
            host.resolve(ResolveQuery::MemberCallableName(SymbolId::of(name))),
            ResolvedMeaning::Presence(false)
        );
    }
    // Source verbs cannot displace an independently documented native proc
    // name in dynamic namespace selection. Ambiguous native entries decline.
    for (name, verb) in [("Copy", false), ("present", false), ("verb_only", true)] {
        assert_eq!(
            host.resolve(ResolveQuery::MemberCallableVerbName(SymbolId::of(name))),
            ResolvedMeaning::Presence(verb)
        );
    }
    let opaque_selector =
        ResolveQuery::MemberCallableVerbName(SymbolId::of("ODHotReloadInterface"));
    assert_eq!(
        host.resolve(opaque_selector),
        ResolvedMeaning::Unsupported(opaque_selector)
    );
    assert_eq!(host.domain_version(opaque_selector.domain()), None);
    let opaque = ResolveQuery::MemberCallableName(SymbolId::of("ODHotReloadInterface"));
    assert_eq!(host.resolve(opaque), ResolvedMeaning::Unsupported(opaque));
    let query = ResolveQuery::GlobalProc(SymbolId::of("arbitrary_missing_one"));
    assert_eq!(host.resolve(query), ResolvedMeaning::Unsupported(query));
    assert!(!matches!(
        host.resolve(ResolveQuery::Proc {
            owner: SymbolId::of("/datum"),
            name: SymbolId::of("New"),
            verb: false
        }),
        ResolvedMeaning::Missing
    ));
}

#[test]
fn list_exclusion_declines_modified_catalog_and_keeps_opaque_constructor() {
    let catalog: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../../fixtures/native_template_nativebuiltins_5161687.json"
    ))
    .unwrap();
    let closed = ClosedNamespace::capture(&catalog).unwrap();
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let source = engine.build_tree(engine.symbols().clone(), &[]).unwrap();
    assert!(!closed.excludes(&source, SymbolId::of("/list"), SymbolId::of("New")));
    assert!(closed.excludes(&source, SymbolId::of("/list"), SymbolId::of("missing")));
    let (methods, _) = IntrinsicMethods::capture_payload(&catalog).unwrap();
    let unissued = IntrinsicMethods {
        source: Arc::new(source),
        methods,
        closed: None,
    };
    assert_eq!(
        unissued.resolve(ResolveQuery::HasMemberProc {
            owner: SymbolId::of("/list"),
            name: SymbolId::of("missing"),
        }),
        None
    );
    let list_index = catalog["Types"]
        .as_array()
        .unwrap()
        .iter()
        .position(|ty| ty["Path"] == "/list")
        .unwrap();
    let mut added = catalog.clone();
    added["Procs"]
        .as_array_mut()
        .unwrap()
        .push(serde_json::json!({
            "OwningTypeId": list_index, "Name": "unreviewed_native_method"
        }));
    assert!(ClosedNamespace::capture(&added).is_err());
    let mut removed = catalog.clone();
    removed["Procs"].as_array_mut().unwrap().retain(|proc| {
        !(proc["OwningTypeId"].as_u64() == Some(list_index as u64) && proc["Name"] == "New")
    });
    assert!(ClosedNamespace::capture(&removed).is_err());
}

#[test]
fn list_negative_declines_authored_foreign_parent_but_source_positive_wins() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok(
                "/list\n    parent_type = /client\n/list/proc/source_present()\n    return 1\n"
                    .into(),
            )
        }
    }
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let catalog: serde_json::Value = serde_json::from_slice(include_bytes!(
        "../../../../fixtures/native_template_nativebuiltins_5161687.json"
    ))
    .unwrap();
    let closed = ClosedNamespace::capture(&catalog).unwrap();
    assert!(!closed.excludes(
        &frontend.snapshot.tree,
        SymbolId::of("/list"),
        SymbolId::of("missing")
    ));
    use dm_ir::Resolver;
    assert!(matches!(
        frontend.snapshot.tree.resolve(ResolveQuery::Proc {
            owner: SymbolId::of("/list"),
            name: SymbolId::of("source_present"),
            verb: false,
        }),
        ResolvedMeaning::Member { .. }
    ));
    let mut changed = catalog;
    let types = changed["Types"].as_array_mut().unwrap();
    let client = types.iter().position(|ty| ty["Path"] == "/client").unwrap();
    let list = types.iter().position(|ty| ty["Path"] == "/list").unwrap();
    types[list]["Parent"] = serde_json::json!(client);
    assert!(ClosedNamespace::capture(&changed).is_err());
}
