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
    assert_eq!(qualified(u64::MAX, u64::MAX / 2, true), Some(u128::MAX));
    assert!(qualified(7, u64::MAX / 2 + 1, false).is_none());
    assert!(qualified(7, u64::MAX / 2 + 1, true).is_none());
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
