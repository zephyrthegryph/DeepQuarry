//! Real frontend/startup/host fixtures, deliberately separate from key fixtures.
use super::*;
use std::path::Path;
struct Text(&'static str);
impl dm_preprocess::SourceProvider for Text {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str, engine: &EngineSnapshot) -> ColdFrontend {
    let seed = engine.frontend_seed();
    dm_tree::frontend::build_with_config(
        Path::new("abi-retained.dme"),
        &Text(source),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap()
}
fn prepared(
    front: &ColdFrontend,
    engine: &EngineSnapshot,
    store: Option<&AbiArtifacts>,
) -> PreparedPinnedSourceAbi {
    let startup = crate::startup::capture(front).unwrap();
    let mut symbols = front.snapshot.tree.symbols().clone();
    let constants = crate::engine_host::ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = crate::engine_host::RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        Vec::new(),
        front
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
        front.snapshot.tree.clone(),
        constants,
        runtime,
    )
    .with_pinned_variables(engine, front)
    .unwrap();
    assert!(!host.observes_reads());
    assert!(
        !startup.resolver(front, &host).unwrap().observes_reads(),
        "pinned ABI static overlay must retain immutable host admission"
    );
    let pool = dm_exec::BuildExecutor::new(2).unwrap();
    prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
        front, engine, &host, &startup, None, &pool, store,
    )
    .unwrap()
}
fn same(retained: &PreparedPinnedSourceAbi, fresh: &PreparedPinnedSourceAbi) {
    assert_eq!(retained.prepared.diagnostics, fresh.prepared.diagnostics);
    assert!(
        retained.prepared.diagnostics.is_empty(),
        "{:?}",
        retained.prepared.diagnostics
    );
    assert_eq!(
        retained.prepared.units().len(),
        fresh.prepared.units().len()
    );
    for ((a_member, a), (b_member, b)) in
        retained.prepared.units().iter().zip(fresh.prepared.units())
    {
        assert_eq!(a_member, b_member);
        assert_eq!(
            a.abi.as_ref().unwrap().canonical_bytes(),
            b.abi.as_ref().unwrap().canonical_bytes()
        );
        assert_eq!(a.inputs.parameters, b.inputs.parameters);
        assert_eq!(a.inputs.parameter_defaults, b.inputs.parameter_defaults);
        assert_eq!(a.inputs.parameter_type_flags, b.inputs.parameter_type_flags);
        assert_eq!(a.inputs.parameter_types, b.inputs.parameter_types);
        assert_eq!(a.inputs.readonly_parameters, b.inputs.readonly_parameters);
    }
}
#[test]
fn structural_abi_scheduler_reuses_unrelated_owner_and_rebinds_formal_wave() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &owner.snapshot;
    let store = AbiArtifacts::with_engine_owner(owner.clone());
    let first=frontend("/datum/a/proc/p(x=1)\n    set invisibility = 7\n    return x\n/datum/a/mid/p(x=2)\n    return ..()\n/datum/a/mid/leaf/p(x=3)\n    return ..()\n/datum/independent/proc/q(x=4)\n    return x\n",engine);
    let before = prepared(&first, engine, Some(&store));
    assert_eq!(store.scheduled_reused(), 0);
    let changed=frontend("// current origin moved\n/datum/a/proc/p(x=1)\n    set invisibility = 9\n    return x\n/datum/a/mid/p(x=2)\n    return ..()\n/datum/a/mid/leaf/p(x=3)\n    return ..()\n/datum/independent/proc/q(x=4)\n    return x+1\n",engine);
    let retained = prepared(&changed, engine, Some(&store));
    same(&retained, &prepared(&changed, engine, None));
    assert_eq!(
        store.batch_reused(),
        0,
        "structural metadata edit must decline whole batch"
    );
    assert_eq!(
        store.scheduled_reused(),
        1,
        "only independent owner skips worker preparation"
    );
    let (_, old) = before.prepared.units().last().unwrap();
    let (_, current) = retained.prepared.units().last().unwrap();
    assert!(Arc::ptr_eq(&old.inputs, &current.inputs));
    for (_, unit) in retained.prepared.units().iter().take(3) {
        assert_eq!(unit.abi.as_ref().unwrap().layout.invisibility, Some(9));
    }
    assert!(store.visit_incidence_storage(|_| {}).unwrap().0 > 0);
}
#[test]
fn real_abi_artifact_rebinds_body_edits_and_invalidates_constant_and_parent_signature() {
    let engine_owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &engine_owner.snapshot;
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&engine_owner));
    let original=frontend("/var/const/C = 7\n/datum/base/proc/p(x=C)\n    set invisibility = C\n    return x\n/datum/base/child/p(x=C)\n    return ..()\n",&engine);
    for body in original.bodies.iter() {
        let proof = original
            .procedure_settings(body)
            .unwrap()
            .expect("production settings owner must be issued");
        let metadata = original
            .snapshot
            .tree
            .member(body.member)
            .unwrap()
            .metadata
            .procedure
            .as_ref()
            .unwrap();
        assert!(proof.authenticates(original.compact_body(body).unwrap(), metadata));
        let owner = original
            .settings_owner_storage()
            .iter()
            .flatten()
            .find(|owner| Arc::ptr_eq(&owner.settings, &metadata.settings));
        assert!(
            owner.is_some(),
            "settings proof shares existing producer payload"
        );
    }
    let before = prepared(&original, &engine, Some(&store));
    let mut structural = 0;
    store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { reads, value, .. } = view {
            if !matches!(value.as_ref(), Artifact::Unit(_)) {
                return;
            }
            for read in reads {
                if let observations::Query::Semantic(query) = &read.query {
                    assert!(!matches!(query, ResolveQuery::OverrideChain { .. }));
                    structural +=
                        usize::from(matches!(query, ResolveQuery::DeclarationChain { .. }));
                }
            }
        }
    });
    assert_eq!(
        structural, 2,
        "one declaration-chain receipt per current ABI"
    );
    same(&before, &prepared(&original, &engine, None));
    let edited=frontend("// moved provenance\n/var/const/C = 7\n/datum/base/proc/p(x=C)\n    set invisibility = C\n    return x+1\n/datum/base/child/p(x=C)\n    return ..()\n",&engine);
    let reused = prepared(&edited, &engine, Some(&store));
    same(&reused, &prepared(&edited, &engine, None));
    assert!(
        Arc::ptr_eq(before.prepared.units_owner(), reused.prepared.units_owner()),
        "batch replay shares the complete immutable unit roster"
    );
    FrozenPreparedPolicy::new(&edited, &reused.prepared).unwrap();
    assert_eq!(
        store.batch_reused(),
        1,
        "body/source shifts must bypass ABI scheduling"
    );
    assert!(
        store.totals().0 >= 2,
        "ordinary bodies must not invalidate ABI"
    );
    for ((_, old), (_, current)) in before.prepared.units().iter().zip(reused.prepared.units()) {
        assert!(Arc::ptr_eq(&old.inputs, &current.inputs));
        assert!(Arc::ptr_eq(
            old.abi.as_ref().unwrap(),
            current.abi.as_ref().unwrap()
        ));
    }
    let batch_hits = store.batch_reused();
    let recomputed = store.totals().1;
    let changed=frontend("/var/const/C = 9\n/datum/base/proc/p(x=C)\n    set invisibility = C\n    return x+1\n/datum/base/child/p(x=C)\n    return ..()\n",&engine);
    let changed_result = prepared(&changed, &engine, Some(&store));
    same(&changed_result, &prepared(&changed, &engine, None));
    assert_eq!(
        before.prepared.units()[0]
            .1
            .abi
            .as_ref()
            .unwrap()
            .layout
            .invisibility,
        Some(7)
    );
    assert_eq!(
        changed_result.prepared.units()[0]
            .1
            .abi
            .as_ref()
            .unwrap()
            .layout
            .invisibility,
        Some(9)
    );
    assert_eq!(
        store.batch_reused(),
        batch_hits,
        "changed scalar must decline batch"
    );
    assert!(
        store.totals().1 > recomputed,
        "captured constant dependency must invalidate"
    );
    let previous = store.totals().1;
    let signature=frontend("/var/const/C = 9\n/datum/base/proc/p(x=11,y=1)\n    set invisibility = C\n    return x+y\n/datum/base/child/p(x=C)\n    return ..()\n",&engine);
    let signature_result = prepared(&signature, &engine, Some(&store));
    assert_eq!(
        store.batch_reused(),
        batch_hits,
        "changed signature must decline batch"
    );
    same(&signature_result, &prepared(&signature, &engine, None));
    assert!(
        store.totals().1 > previous,
        "authored default/signature changes must invalidate"
    );
    FrozenPreparedPolicy::new(&signature, &signature_result.prepared).unwrap();
}

#[test]
fn authored_setting_error_and_blocked_override_preserve_source_diagnostics() {
    let engine_owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &engine_owner.snapshot;
    let front=frontend("/datum/base/proc/p()\n    set invisibility = 200\n    return 1\n/datum/base/child/p()\n    return ..()\n",&engine);
    let store = AbiArtifacts::with_engine_owner(engine_owner.clone());
    let batch = prepared(&front, &engine, Some(&store));
    let repeated = prepared(&front, &engine, Some(&store));
    assert_eq!(batch.prepared.diagnostics, repeated.prepared.diagnostics);
    assert_eq!(store.batch_reused(), 0, "failed recipes are never admitted");
    assert_eq!(batch.prepared.diagnostics.len(), 2);
    let diagnostics = abi_diagnostics(&front, &batch.prepared).unwrap();
    assert!(diagnostics
        .iter()
        .all(|diagnostic| diagnostic.kind == dm_tree::frontend::DiagnosticKind::SourceError));
    assert!(diagnostics[0].message.contains("invisibility exceeds 127"));
    assert_eq!(diagnostics[0].origin.line, 1);
}

fn stored_entries(store: &AbiArtifacts) -> usize {
    let mut entries = 0;
    store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries: n, .. } = view {
            entries = n
        }
    });
    entries
}
#[test]
fn typed_abi_requires_actual_engine_owner_and_prunes_failed_or_deleted_units() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &owner.snapshot;
    let front = frontend("/datum/base/proc/p(x=7)\n    return x\n", engine);
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&owner));
    same(
        &prepared(&front, engine, Some(&store)),
        &prepared(&front, engine, None),
    );
    assert_eq!(
        stored_entries(&store),
        2,
        "one unit plus successful batch recipe"
    );
    let foreign = (*engine).clone();
    same(
        &prepared(&front, &foreign, Some(&store)),
        &prepared(&front, &foreign, None),
    );
    assert_eq!(
        store.totals().0,
        0,
        "equal digest/decoded data without the issued physical owner cannot admit"
    );
    assert_eq!(stored_entries(&store), 0);
    let bare = AbiArtifacts::default();
    same(
        &prepared(&front, engine, Some(&bare)),
        &prepared(&front, engine, None),
    );
    assert_eq!(stored_entries(&bare), 0);
    prepared(&front, engine, Some(&store));
    let broken=frontend("/datum/base/proc/p(x=7)\n    set invisibility = 200\n    return x\n/datum/base/child/p()\n    return ..()\n",engine);
    let failed = prepared(&broken, engine, Some(&store));
    assert_eq!(failed.prepared.diagnostics.len(), 2);
    assert_eq!(
        stored_entries(&store),
        0,
        "failed current outcomes cannot retain old ABI answers"
    );
    prepared(&front, engine, Some(&store));
    let deleted = frontend("/datum/other\n", engine);
    prepared(&deleted, engine, Some(&store));
    assert_eq!(stored_entries(&store), 0);
}

#[path = "formal_abi_tests.rs"]
mod formal_abi_tests;

#[test]
fn engine_parent_structural_chain_uses_current_source_and_exact_boundary() {
    let engine_owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &engine_owner.snapshot;
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&engine_owner));
    let original = frontend("/datum/probe/New()\n    return ..()\n", engine);
    let before = prepared(&original, engine, Some(&store));
    same(&before, &prepared(&original, engine, None));
    let current = frontend(
        "// current source\n/datum/probe/New()\n    return ..()+1\n",
        engine,
    );
    let reused = prepared(&current, engine, Some(&store));
    same(&reused, &prepared(&current, engine, None));
    assert_eq!(before.prepared.units().len(), 1);
    assert!(Arc::ptr_eq(
        &before.prepared.units()[0].1.inputs,
        &reused.prepared.units()[0].1.inputs
    ));
    let query = ResolveQuery::DeclarationChain {
        owner: SymbolId::of("/datum/probe"),
        name: SymbolId::of("New"),
        verb: false,
    };
    let meaning = dm_ir::Resolver::resolve(current.snapshot.tree.as_ref(), query);
    assert!(matches!(meaning, ResolvedMeaning::Members(_)));
    let engine_only = ResolveQuery::DeclarationChain {
        owner: SymbolId::of("/datum"),
        name: SymbolId::of("New"),
        verb: false,
    };
    // The binary intrinsic inventory supplies presence, not source declaration
    // metadata. No invented declaration chain is returned for the engine body.
    assert_eq!(
        dm_ir::Resolver::resolve(current.snapshot.tree.as_ref(), engine_only),
        ResolvedMeaning::Unsupported(engine_only)
    );
    let mut inputs = 0;
    store.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Entry { reads, value, .. } = view {
            if !matches!(value.as_ref(), Artifact::Unit(_)) {
                return;
            }
            for read in reads {
                if let observations::Answer::Inputs(current) = &read.answer {
                    assert!(!matches!(current.boundary, observations::Boundary::Absent));
                    assert!(Arc::ptr_eq(&current.engine, &engine_owner));
                    inputs += 1;
                }
            }
        }
    });
    assert_eq!(inputs, 1);
}

#[test]
fn abi_batch_signature_away_and_back_keeps_actual_chosen_unit_and_receipt() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &owner.snapshot;
    let store = AbiArtifacts::with_engine_owner(owner.clone());
    let original = frontend(
        "/var/const/C = 7\n/datum/probe/proc/p(x=C)\n    return x\n",
        engine,
    );
    let first = prepared(&original, engine, Some(&store));
    let away = frontend(
        "/var/const/C = 9\n/datum/probe/proc/p(x=2,y=C)\n    return x+y\n",
        engine,
    );
    let changed = prepared(&away, engine, Some(&store));
    same(&changed, &prepared(&away, engine, None));
    assert_eq!(store.batch_reused(), 0);
    let restored = prepared(&original, engine, Some(&store));
    same(&restored, &prepared(&original, engine, None));
    assert_eq!(store.batch_reused(), 0);
    assert_eq!(
        first.prepared.units()[0].1.inputs.parameter_defaults,
        restored.prepared.units()[0].1.inputs.parameter_defaults
    );
    let moved = frontend(
        "// current origin\n/var/const/C = 7\n/datum/probe/proc/p(x=C)\n    return x+1\n",
        engine,
    );
    let reused = prepared(&moved, engine, Some(&store));
    same(&reused, &prepared(&moved, engine, None));
    assert_eq!(store.batch_reused(), 1);
    assert!(Arc::ptr_eq(
        &restored.prepared.units()[0].1.inputs,
        &reused.prepared.units()[0].1.inputs
    ));
    assert!(Arc::ptr_eq(
        restored.prepared.units()[0].1.abi.as_ref().unwrap(),
        reused.prepared.units()[0].1.abi.as_ref().unwrap()
    ));
    FrozenPreparedPolicy::new(&moved, &reused.prepared).unwrap();
}
