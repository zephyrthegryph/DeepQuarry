//! Real frontend/startup/host fixtures, deliberately separate from key fixtures.
use super::*;
use std::path::Path;
struct Text<'a>(&'a str);
impl dm_preprocess::SourceProvider for Text<'_> {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
pub(super) fn frontend(source: &str, engine: &EngineSnapshot) -> ColdFrontend {
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
fn retained_frontend(
    source: &str,
    engine: &EngineSnapshot,
    state: &mut dm_tree::frontend::RetainedSemanticTree,
) -> ColdFrontend {
    let seed = engine.frontend_seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    dm_tree::frontend::build_with_executor_and_semantic_state(
        Path::new("abi-retained.dme"),
        &Text(source),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        &executor,
        Some(state),
    )
    .unwrap()
}
pub(super) fn prepared(
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
pub(super) fn same(retained: &PreparedPinnedSourceAbi, fresh: &PreparedPinnedSourceAbi) {
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
    let store = AbiArtifacts::with_engine_owner(owner.clone()).with_retained_shortcuts();
    let mut state = dm_tree::frontend::RetainedSemanticTree::new();
    // Certificates are process-local issuer proofs: exercise the actual retained frontend.
    let first=retained_frontend("/datum/a/proc/p(x=1)\n    set invisibility = 7\n    return x\n/datum/a/mid/p(x=2)\n    return ..()\n/datum/a/mid/leaf/p(x=3)\n    return ..()\n/datum/independent/proc/q(x=4)\n    return x\n",engine, &mut state);
    let before = prepared(&first, engine, Some(&store));
    assert_eq!(store.scheduled_reused(), 0);
    let changed=retained_frontend("// current origin moved\n/datum/a/proc/p(x=1)\n    set invisibility = 9\n    return x\n/datum/a/mid/p(x=2)\n    return ..()\n/datum/a/mid/leaf/p(x=3)\n    return ..()\n/datum/independent/proc/q(x=4)\n    return x+1\n",engine, &mut state);
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
    assert_eq!(
        store.qualified_reused(),
        1,
        "independent issued owner must avoid inherited factory validation"
    );
    let (_, old) = before.prepared.units().last().unwrap();
    let (_, current) = retained.prepared.units().last().unwrap();
    assert!(Arc::ptr_eq(&old.inputs, &current.inputs));
    let previous_proof = before
        .prepared
        .units_owner()
        .selected(before.prepared.units().len() - 1)
        .unwrap();
    let current_proof = retained
        .prepared
        .units_owner()
        .selected(retained.prepared.units().len() - 1)
        .unwrap();
    assert!(
        Arc::ptr_eq(previous_proof, current_proof),
        "actual admitted independent unit certificate survives changed graph"
    );
    assert!(
        !Arc::ptr_eq(
            before.prepared.units_owner().selected(0).unwrap(),
            retained.prepared.units_owner().selected(0).unwrap()
        ),
        "changed inherited facts require a new actual unit certificate"
    );
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
    let store = AbiArtifacts::with_engine_owner(Arc::clone(&engine_owner)).with_retained_shortcuts();
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
    assert!(Arc::ptr_eq(&current.engine.upgrade().unwrap(), &engine_owner));
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
    let store = AbiArtifacts::with_engine_owner(owner.clone()).with_retained_shortcuts();
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

#[test]
fn symbolic_abi_batch_rebinds_variable_insert_remove_and_unrelated_type() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &owner.snapshot;
    let store = AbiArtifacts::with_engine_owner(owner.clone()).with_retained_shortcuts();
    let original = frontend(
        "/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n",
        engine,
    );
    let before = prepared(&original, engine, Some(&store));
    let inserted = frontend("/var/unrelated = 1\n/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n", engine);
    assert_ne!(original.bodies[0].member, inserted.bodies[0].member);
    let current = prepared(&inserted, engine, Some(&store));
    same(&current, &prepared(&inserted, engine, None));
    assert_eq!(
        store.batch_reused(),
        1,
        "symbolic batch must survive unrelated arena shift"
    );
    assert!(!Arc::ptr_eq(
        before.prepared.units_owner(),
        current.prepared.units_owner()
    ));
    for ((old_member, old), (member, unit)) in
        before.prepared.units().iter().zip(current.prepared.units())
    {
        assert_ne!(old_member, member);
        assert!(Arc::ptr_eq(&old.inputs, &unit.inputs));
        assert!(Arc::ptr_eq(
            old.abi.as_ref().unwrap(),
            unit.abi.as_ref().unwrap()
        ));
    }
    let removed = prepared(&original, engine, Some(&store));
    same(&removed, &prepared(&original, engine, None));
    assert_eq!(store.batch_reused(), 2);
    let unrelated = frontend("/datum/unrelated\n/datum/a/proc/p(x=1)\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n", engine);
    let current = prepared(&unrelated, engine, Some(&store));
    same(&current, &prepared(&unrelated, engine, None));
    assert_eq!(
        store.batch_reused(),
        3,
        "unrelated type must not change demanded callable ancestry"
    );
    let formal = frontend("/datum/unrelated\n/datum/a/proc/p(x=1)\n    set invisibility = 9\n    return x\n/datum/a/child/p(x=2)\n    return ..()\n", engine);
    let changed = prepared(&formal, engine, Some(&store));
    same(&changed, &prepared(&formal, engine, None));
    assert_eq!(
        store.batch_reused(),
        3,
        "changed formal metadata must decline symbolic batch"
    );
    assert_eq!(
        changed.prepared.units()[1]
            .1
            .abi
            .as_ref()
            .unwrap()
            .layout
            .invisibility,
        Some(9)
    );
}

#[test]
fn structural_batch_rows_splice_new_proc_and_removal_with_fresh_parity() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let store = AbiArtifacts::with_engine_owner(owner.clone());
    let initial = frontend(
        "/datum/a/proc/p(x=1)\n    return x\n/datum/b/proc/q(x=2)\n    return x\n",
        &owner.snapshot,
    );
    let before = prepared(&initial, &owner.snapshot, Some(&store));
    let added = frontend("/datum/new_owner/proc/new_proc(x=3)\n    return x\n/datum/a/proc/p(x=1)\n    return x\n/datum/b/proc/q(x=2)\n    return x\n", &owner.snapshot);
    let retained = prepared(&added, &owner.snapshot, Some(&store));
    same(&retained, &prepared(&added, &owner.snapshot, None));
    assert_eq!(store.structural_selection_counts(), (2, 0));
    assert_eq!(store.scheduled_reused(), 2);
    assert_eq!(store.totals().1, 3, "only added unit prepares");
    for (old, current) in before
        .prepared
        .units()
        .iter()
        .zip(retained.prepared.units().iter().skip(1))
    {
        assert!(Arc::ptr_eq(&old.1.inputs, &current.1.inputs));
    }
    let removed = frontend(
        "/datum/a/proc/p(x=1)\n    return x\n/datum/b/proc/q(x=2)\n    return x\n",
        &owner.snapshot,
    );
    let retained = prepared(&removed, &owner.snapshot, Some(&store));
    same(&retained, &prepared(&removed, &owner.snapshot, None));
    assert_eq!(store.structural_selection_counts(), (4, 0));
    assert_eq!(store.scheduled_reused(), 4);
    assert_eq!(store.totals().1, 3, "removal prepares no surviving units");
}

#[test]
fn batch_binding_survives_request_drop_and_replacement_releases_old_binding() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let store = AbiArtifacts::with_engine_owner(owner.clone()).with_retained_shortcuts();
    let first = frontend("/datum/a/proc/p(x=1)\n    return x\n", &owner.snapshot);
    let request = prepared(&first, &owner.snapshot, Some(&store));
    let weak = Arc::downgrade(request.prepared.units_owner());
    drop(request);
    assert!(
        weak.upgrade().is_some(),
        "same recipe owns admitted binding between requests"
    );
    let shifted = frontend(
        "// shifted current origin\n/datum/a/proc/p(x=1)\n    return x+1\n",
        &owner.snapshot,
    );
    let request = prepared(&shifted, &owner.snapshot, Some(&store));
    assert!(Arc::ptr_eq(
        &weak.upgrade().unwrap(),
        request.prepared.units_owner()
    ));
    same(&request, &prepared(&shifted, &owner.snapshot, None));
    drop(request);
    let signature = frontend("/datum/a/proc/p(x=2)\n    return x\n", &owner.snapshot);
    let request = prepared(&signature, &owner.snapshot, Some(&store));
    same(&request, &prepared(&signature, &owner.snapshot, None));
    assert!(
        weak.upgrade().is_none(),
        "replacement prunes previous binding"
    );
    let signature_weak = Arc::downgrade(request.prepared.units_owner());
    drop(request);
    let dense = frontend(
        "/var/added=1\n/datum/a/proc/p(x=2)\n    return x\n",
        &owner.snapshot,
    );
    let request = prepared(&dense, &owner.snapshot, Some(&store));
    same(&request, &prepared(&dense, &owner.snapshot, None));
    assert!(signature_weak.upgrade().is_none());
    let final_weak = Arc::downgrade(request.prepared.units_owner());
    drop(request);
    drop(store);
    assert!(
        final_weak.upgrade().is_none(),
        "store release drops only retained binding"
    );
}

#[test]
fn abi_disk_transport_rebinds_current_body_and_rejects_signature_change() {
    disk_roundtrip("value=7", "value=9,other=2");
}
#[test]
fn abi_disk_helper_transport_reissues_current_expression_and_rejects_change() {
    disk_roundtrip("value in list(1,2)", "value in list(1,3)");
}
fn disk_roundtrip(signature: &str, changed_signature: &str) {
    let root = std::path::PathBuf::from("E:/dq-cache/dmb-abi-disk-tests").join(format!(
        "{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    struct Owned(std::path::PathBuf);
    impl Drop for Owned {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    let _owned = Owned(root.clone());
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &owner.snapshot;
    let first_disk = Arc::new(crate::runner_host::disk::LazyDisk::new(root.clone()));
    let first_store = AbiArtifacts::with_disk(owner.clone(), first_disk.clone(), 17);
    let first = frontend(
        &format!("/proc/probe({signature})\n    return value\n"),
        engine,
    );
    same(
        &prepared(&first, engine, Some(&first_store)),
        &prepared(&first, engine, None),
    );
    assert!(first_disk.finish_batch().unwrap().records >= 2);
    // Drop every process-issued store and request binding before loading again.
    drop(first_store);
    drop(first_disk);
    let second_disk = Arc::new(crate::runner_host::disk::LazyDisk::new(root.clone()));
    let second_store = AbiArtifacts::with_disk(owner.clone(), second_disk.clone(), 17);
    let shifted = frontend(
        &format!("// shifted current source\n/proc/probe({signature})\n    return value+1\n"),
        engine,
    );
    same(
        &prepared(&shifted, engine, Some(&second_store)),
        &prepared(&shifted, engine, None),
    );
    assert!(
        second_store.totals().0 > 0,
        "source-neutral disk ABI must be admitted"
    );
    drop(second_store);
    drop(second_disk);
    let third_store = AbiArtifacts::with_disk(
        owner.clone(),
        Arc::new(crate::runner_host::disk::LazyDisk::new(root)),
        17,
    );
    let changed = frontend(
        &format!("/proc/probe({changed_signature})\n    return value\n"),
        engine,
    );
    same(
        &prepared(&changed, engine, Some(&third_store)),
        &prepared(&changed, engine, None),
    );
    assert_eq!(
        third_store.totals().0,
        0,
        "changed signature must prepare currently"
    );
}

#[test]
fn issued_abi_local_structure_tracks_parent_and_definition_without_sibling_churn() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let engine = &owner.snapshot;
    let facts = |text: &str| {
        let current = frontend(text, engine);
        let member = current.bodies.last().unwrap().member;
        abi_artifacts::observations::structural_inputs(&current, member).unwrap()
    };
    let original = facts(
        "/datum/base\n/datum/a\n    parent_type = /datum/base\n/datum/a/proc/p()\n    return 1\n",
    );
    let sibling = facts("/datum/other\n    var/extra = 2\n/datum/base\n/datum/a\n    parent_type = /datum/base\n/datum/a/proc/p()\n    return 1\n");
    assert_eq!(
        original, sibling,
        "unrelated owner cannot change local structural meaning"
    );
    let reparented = facts("/datum/base\n/datum/a\n/datum/a/proc/p()\n    return 1\n");
    assert_ne!(
        original.1, reparented.1,
        "parent mutation must reject the local licence"
    );
    let overriding = facts("/datum/base\n/datum/base/proc/p()\n    return 0\n/datum/a\n    parent_type = /datum/base\n/datum/a/p()\n    return 1\n");
    assert_ne!(
        original.0, overriding.0,
        "declaration/override mode is a mandatory local fact"
    );
}

#[test]
fn admitted_abi_seed_dispatches_only_dirty_dependency_roots() {
    let owner = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let current = frontend("/datum/a/proc/p(x=1)\n    return x\n/datum/a/mid/p(x=2)\n    return ..()\n/datum/a/mid/leaf/p(x=3)\n    return ..()\n/datum/independent/proc/q(x=4)\n    return x\n", &owner.snapshot);
    let prepared = prepared(&current, &owner.snapshot, None);
    let roster = current.callable_roster().unwrap();
    let all = || -> BTreeMap<_, _> {
        prepared
            .prepared
            .units()
            .iter()
            .enumerate()
            .map(|(ordinal, (_, unit))| {
                (
                    ordinal,
                    crate::procedure_policy::PreparedReplay::from_unit(unit)
                        .unwrap()
                        .into_view(),
                )
            })
            .collect()
    };
    let all_seed = abi_scheduler::seed(&current, roster, all()).unwrap();
    assert!(
        all_seed.ready.is_empty(),
        "fully admitted graph performs no executor wave"
    );
    assert!(all_seed.remaining.iter().all(|pending| !pending));
    for (ordinal, (_, expected)) in prepared.prepared.units().iter().enumerate() {
        let actual = all_seed.results[ordinal].as_ref().unwrap();
        assert!(Arc::ptr_eq(&actual.inputs, &expected.inputs));
        assert!(Arc::ptr_eq(
            actual.abi.as_ref().unwrap(),
            expected.abi.as_ref().unwrap()
        ));
    }
    let selected = all()
        .into_iter()
        .filter(|(ordinal, _)| *ordinal == 0 || *ordinal == 3)
        .collect();
    let partial = abi_scheduler::seed(&current, roster, selected).unwrap();
    assert_eq!(
        partial.ready,
        vec![1],
        "only first dirty descendant is ready, not its child or admitted sibling"
    );
    assert_eq!(partial.remaining, vec![false, true, true, false]);
    assert_eq!(partial.layouts.len(), 2);
    let cold = abi_scheduler::seed(&current, roster, BTreeMap::new()).unwrap();
    assert_eq!(
        cold.ready,
        roster.ready(),
        "unissued path retains original cold roots"
    );
}
