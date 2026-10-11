use super::*;
use crate::lowering_memo::{ProcedureMemo, RecordingResolver};
use crate::request_runner::runner_facts::prepare_retained;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
struct EmptyAbi;
impl crate::lowering::AbiPolicy for EmptyAbi {
    fn inputs(
        &self,
        _: crate::lowering::UnitIdentity,
        _: &dm_ir::ProcedureMetadata,
        _: &SymbolTable,
        _: &dm_tree::frontend::SourceLocation,
    ) -> Result<dm_codegen_byond::ProcedureInputs, String> {
        Ok(Default::default())
    }
}
#[test]
fn qualified_branch_tags_are_disjoint_and_never_truncate() {
    assert_ne!(qualified(7, 11, false), qualified(7, 11, true));
    assert_eq!(qualified(u64::MAX, u64::MAX / 4, true), Some(u128::MAX - 2));
    assert!(qualified(7, u64::MAX / 4 + 1, false).is_none());
    assert!(qualified(7, u64::MAX / 4 + 1, true).is_none());
    assert_ne!(qualified_tag(7, 11, 2), qualified(7, 11, true));
    assert_ne!(qualified_tag(7, 11, 2), qualified(7, 11, false));
    assert!(qualified_tag(7, u64::MAX / 4 + 1, 2).is_none());
    let positive_catalog = 11u64.checked_mul(4).unwrap() + 3;
    assert_ne!(qualified_tag(0, 11, 2), Some(u128::from(positive_catalog)));
}
#[test]
fn finite_variable_negative_resident_and_disk_replay_tracks_inheritance_and_deletion() {
    let mut build_host = crate::runner_host::BuildHost::default();
    let engine = build_host
        .engine(
            "variable-negative.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let facts = build_host.host_facts().unwrap();
    let semantic = std::cell::RefCell::new(dm_tree::frontend::RetainedSemanticTree::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |text| {
        dm_tree::frontend::build_with_executor_and_semantic_state(
            std::path::Path::new("variable-negative.dme"),
            &Source(text),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
            None,
            &executor,
            Some(&mut semantic.borrow_mut()),
        )
        .unwrap()
    };
    let owner = SymbolId::of("/datum/child");
    let name = SymbolId::of("finite_value");
    let queries = [
        Q::Var { owner, name },
        Q::HasMemberVar { owner, name },
        Q::DeclaredVarType { owner, name },
    ];
    let first = build("/proc/probe()\n    return 7\n/datum/base\n    var/finite_value = 1\n/datum/child\n    parent_type = /datum/base\n/datum/other\n");
    let (positive, _) = prepare_retained(&first, &engine, Some(&facts)).unwrap();
    assert_eq!(positive.resolve(queries[1]), M::Presence(true));
    let positive_token = positive.domain_version(queries[1].domain()).unwrap();
    let removed = build("/proc/probe()\n    return 7\n/datum/base\n/datum/child\n    parent_type = /datum/base\n/datum/other\n    var/finite_value = 1\n");
    let (host, _) = prepare_retained(&removed, &engine, Some(&facts)).unwrap();
    let recorder = RecordingResolver::new(&host);
    for query in queries {
        assert!(matches!(
            recorder.resolve(query),
            M::Missing | M::Presence(false)
        ));
        assert!(host.domain_version(query.domain()).is_some());
    }
    assert_ne!(
        host.domain_version(queries[1].domain()),
        Some(positive_token)
    );
    let unknown = Q::HasMemberVar {
        owner,
        name: SymbolId::of("unknown_native_variable_name"),
    };
    assert!(host.domain_version(unknown.domain()).is_none());
    struct Opaque;
    impl Resolver for Opaque {
        fn resolve(&self, query: Q) -> M {
            M::Unsupported(query)
        }
    }
    let opaque = EngineResolverHost::new(
        Arc::new(Opaque),
        host.constants.clone(),
        host.runtime.clone(),
    )
    .with_pinned_variables(&engine.snapshot, &removed)
    .unwrap();
    for query in queries {
        assert!(opaque.domain_version(query.domain()).is_none());
        assert!(matches!(opaque.resolve(query), M::Unsupported(_)));
    }
    let reads = recorder.reads();
    let versions = recorder.domain_receipts();
    let ast = dm_syntax::parse("/proc/probe()\n    return 7\n");
    let code = dm_codegen_byond::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &Default::default(),
        &Default::default(),
        &recorder,
    )
    .unwrap();
    let batch = crate::lowering::lower_frontend(&removed, &host, &EmptyAbi, Default::default());
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    let unit = batch
        .units
        .iter()
        .find(|unit| unit.identity.name == SymbolId::of("probe"))
        .unwrap();
    let resident = ProcedureMemo::new(91);
    let key = b"finite-variable-negative-return7";
    resident.remember(key.to_vec(), reads.clone(), unit, vec![], versions.clone());
    assert!(resident.values.lookup(key, &host).is_some());
    let token = host.domain_version(queries[1].domain()).unwrap();
    let root = std::path::PathBuf::from("E:/dq-cache/dmb-native-v2/variable-negative-tests")
        .join(format!("{}-{token}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let writer = ProcedureMemo::with_disk_only(91, cache.snapshot().unwrap());
    writer.remember_executable(key, &reads, &code, &versions);
    let records = writer.take_pending();
    assert_eq!(records.len(), 1);
    cache.publish(&records).unwrap();
    drop(writer);
    drop(records);
    let disk = ProcedureMemo::with_disk_only(91, cache.snapshot().unwrap());
    assert_eq!(
        disk.lookup_anonymous(key, &host, 0).code.unwrap().procedure,
        code.procedure
    );
    // Moving the unrelated declaration keeps the selected owner's absence exact.
    let moved = build("/proc/probe()\n    return 7\n/datum/base\n/datum/child\n    parent_type = /datum/base\n/datum/other\n/datum/unrelated\n    var/finite_value = 2\n");
    let (moved_host, _) = prepare_retained(&moved, &engine, Some(&facts)).unwrap();
    for query in queries {
        assert_eq!(
            moved_host.resolve(query).canonical_bytes(),
            host.resolve(query).canonical_bytes()
        );
        assert_eq!(
            moved_host.domain_version(query.domain()),
            host.domain_version(query.domain())
        );
    }
    assert_eq!(
        resident
            .values
            .lookup(key, &moved_host)
            .unwrap()
            .unit
            .code
            .procedure,
        unit.code.procedure
    );
    assert_eq!(
        disk.lookup_anonymous(key, &moved_host, 0)
            .code
            .unwrap()
            .procedure,
        code.procedure
    );
    for text in [
        "/proc/probe()\n    return 7\n/datum/base\n/datum/child\n    parent_type = /datum/other\n/datum/other\n    var/finite_value = 1\n",
        "/proc/probe()\n    return 7\n/datum/base\n/datum/child\n    parent_type = /datum/base\n/datum/other\n    var/renamed_value = 1\n",
        "/proc/probe()\n    return 7\n/datum/base\n/datum/child\n    parent_type = /datum/base\n/datum/other\n",
        "/proc/probe()\n    return 7\n/datum/base\n/datum/other\n    var/finite_value = 2\n",
    ] {
        let current = build(text);
        let (current_host, _) = prepare_retained(&current, &engine, Some(&facts)).unwrap();
        assert!(resident.values.lookup(key, &current_host).is_none());
        assert!(disk.lookup_anonymous(key, &current_host, 0).code.is_none());
        let fresh = crate::request_runner::runner_facts::prepare(&current, &engine.snapshot).unwrap().0;
        for query in queries { assert_eq!(current_host.resolve(query).canonical_bytes(), fresh.resolve(query).canonical_bytes()); }
    }
    drop(disk);
    drop(cache);
    std::fs::remove_dir_all(&root).unwrap();
}

#[test]
fn ordinary_global_negative_tracks_new_body_names_shadowing_and_provider_scope() {
    let mut build_host = crate::runner_host::BuildHost::default();
    let engine = build_host
        .engine(
            "global-negative.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let facts = build_host.host_facts().unwrap();
    let semantic = std::cell::RefCell::new(dm_tree::frontend::RetainedSemanticTree::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |text| {
        dm_tree::frontend::build_with_executor_and_semantic_state(
            std::path::Path::new("global-negative.dme"),
            &Source(text),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(engine.frontend_seed()),
                observer: None,
            },
            None,
            &executor,
            Some(&mut semantic.borrow_mut()),
        )
        .unwrap()
    };
    let initial = build("/proc/probe()\n    return 7\n");
    let (host, _) = prepare_retained(&initial, &engine, Some(&facts)).unwrap();
    let name = SymbolId::of("new_missing_global_name");
    let query = Q::GlobalVar(name);
    assert_eq!(host.resolve(query), M::Missing);
    let version = host.domain_version(query.domain()).unwrap();
    let predefined = Q::PredefinedConstant(name);
    assert_eq!(host.resolve(predefined), M::Missing);
    let predefined_version = host.domain_version(predefined.domain()).unwrap();
    assert_ne!(predefined_version, version);
    let changed = build("/proc/probe()\n    return new_missing_global_name\n");
    let (current, _) = prepare_retained(&changed, &engine, Some(&facts)).unwrap();
    assert_eq!(current.resolve(query), M::Missing);
    assert_eq!(current.domain_version(query.domain()), Some(version));
    assert_eq!(current.resolve(predefined), M::Missing);
    assert_eq!(
        current.domain_version(predefined.domain()),
        Some(predefined_version)
    );
    let recorded = RecordingResolver::new(&current);
    assert_eq!(recorded.resolve(query), M::Missing);
    assert_eq!(recorded.reads().len(), 1);
    let retained: dm_session::ArtifactStore<usize> = dm_session::ArtifactStore::current_revision();
    retained.insert(
        Arc::from(&b"ordinary-global-negative"[..]),
        recorded.reads().to_vec(),
        7,
    );
    assert_eq!(
        retained
            .lookup(b"ordinary-global-negative", &host)
            .as_deref(),
        Some(&7)
    );
    assert_eq!(
        retained
            .lookup(b"ordinary-global-negative", &current)
            .as_deref(),
        Some(&7)
    );
    // Production cold preparation installs the captured per-procedure static
    // inventory before probing ordinary globals. A bare scalar host deliberately
    // has no license to declare an arbitrary procedure-static name absent.
    let startup = crate::startup::capture(&changed).unwrap();
    let lexical_host = startup.resolver(&changed, &current).unwrap();
    let lowered = crate::lowering::lower_frontend_with_statics(
        &changed,
        &lexical_host,
        &EmptyAbi,
        Default::default(),
        &startup,
    );
    assert!(
        lowered
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.kind == dm_tree::frontend::DiagnosticKind::SourceError),
        "{:?}",
        lowered.diagnostics
    );
    for spelling in [
        "world", "usr", "src", "args", "callee", "caller", "global", "__PROC__", "NORTH", "TRUE",
    ] {
        let q = Q::GlobalVar(SymbolId::of(spelling));
        assert!(
            !current
                .variable_absence
                .as_ref()
                .unwrap()
                .payload
                .covers_predefined_absence(SymbolId::of(spelling)),
            "{spelling}"
        );
        if matches!(spelling, "NORTH" | "TRUE") {
            // Finite approved constant coverage predates the ordinary policy.
            // Its variable-storage absence allows the positive constant lookup.
            assert!(
                matches!(
                    current.resolve(Q::PredefinedConstant(SymbolId::of(spelling))),
                    M::Value(_)
                ),
                "{spelling}"
            );
        } else {
            assert!(!matches!(current.resolve(q), M::Missing), "{spelling}");
        }
    }
    // The old finite lexical-storage receipt remains admitted independently of
    // the new ordinary policy's exclusion of the __TYPE__ special name.
    let lexical_storage = Q::GlobalVar(SymbolId::of("__TYPE__"));
    assert!(current
        .variable_absence
        .as_ref()
        .unwrap()
        .payload
        .covers(lexical_storage));
    assert_eq!(current.resolve(lexical_storage), M::Missing);
    assert!(current.domain_version(lexical_storage.domain()).is_some());
    // Neither ordinary receiver fields nor unissued providers borrow this rule.
    let receiver = Q::Var {
        owner: SymbolId::of("/datum"),
        name,
    };
    assert!(!current
        .variable_absence
        .as_ref()
        .unwrap()
        .payload
        .covers(receiver));
    struct Opaque;
    impl Resolver for Opaque {
        fn resolve(&self, query: Q) -> M {
            M::Unsupported(query)
        }
    }
    let opaque = EngineResolverHost::new(
        Arc::new(Opaque),
        current.constants.clone(),
        current.runtime.clone(),
    )
    .with_pinned_variables(&engine.snapshot, &changed)
    .unwrap();
    assert!(opaque.domain_version(query.domain()).is_none());
    assert!(matches!(opaque.resolve(query), M::Unsupported(_)));
    assert_eq!(opaque.resolve(predefined), M::Unsupported(predefined));
    assert!(opaque.domain_version(predefined.domain()).is_none());
    let authored = build("var/global/new_missing_global_name = 4\n/proc/probe()\n    return new_missing_global_name\n");
    let (positive, _) = prepare_retained(&authored, &engine, Some(&facts)).unwrap();
    assert!(!matches!(
        positive.resolve(query),
        M::Missing | M::Unsupported(_)
    ));
    assert_ne!(positive.domain_version(query.domain()), Some(version));
    assert!(positive.domain_version(predefined.domain()).is_none());
    assert_eq!(positive.resolve(predefined), M::Unsupported(predefined));
    assert!(retained
        .lookup(b"ordinary-global-negative", &positive)
        .is_none());
    let deleted = build("/proc/probe()\n    return new_missing_global_name\n");
    let (removed, _) = prepare_retained(&deleted, &engine, Some(&facts)).unwrap();
    assert_eq!(removed.resolve(query), M::Missing);
    assert_eq!(
        retained
            .lookup(b"ordinary-global-negative", &removed)
            .as_deref(),
        Some(&7)
    );
    let fresh = crate::request_runner::runner_facts::prepare(&deleted, &engine.snapshot)
        .unwrap()
        .0;
    assert_eq!(removed.resolve(query), fresh.resolve(query));
    let altered = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        2,
    )
    .unwrap();
    assert!(super::super::engine_providers::VariableProviders::capture(&altered).is_err());
}
