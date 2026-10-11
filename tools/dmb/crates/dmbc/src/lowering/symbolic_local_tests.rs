use super::*;
use crate::lowering::AbiPolicy;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok("/datum/a/proc/p(x = 7)\n    return x\n".into())
    }
}
#[test]
fn local_proof_uses_actual_shared_inputs_and_declines_changed_source_policy_or_owner() {
    let engine = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let seed = engine.snapshot.frontend_seed();
    let build = || {
        dm_tree::frontend::build_with_config(
            std::path::Path::new("local.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap()
    };
    let front = build();
    let startup = crate::startup::capture(&front).unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let artifacts = crate::driver_facts::AbiArtifacts::with_engine_owner(Arc::clone(&engine));
    let prepared =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &front,
            &engine.snapshot,
            front.snapshot.tree.as_ref(),
            &startup,
            None,
            &executor,
            Some(&artifacts),
        )
        .unwrap();
    assert!(
        prepared.prepared.diagnostics.is_empty(),
        "{:?}",
        prepared.prepared.diagnostics
    );
    let policy =
        crate::driver_facts::FrozenPreparedPolicy::new(&front, &prepared.prepared).unwrap();

    let roster = PreparedBodyRoster::issue(&front).unwrap();
    let row = roster.ordered().next().unwrap();
    let licensed = policy
        .current_local_inputs(&front, front.snapshot.tree.symbols())
        .unwrap();
    let issued_inputs = licensed.prepared(row).unwrap().inputs;
    let owners_before = Arc::strong_count(&issued_inputs);
    let mut certificate = Certificate::issue(&licensed, row, 7).unwrap();
    assert_eq!(
        Arc::strong_count(&issued_inputs),
        owners_before,
        "certificate witnesses must not keep source-bearing input owners alive"
    );
    assert!(
        certificate.selected.is_some(),
        "the actual successful ABI producer issues this unit owner"
    );
    assert!(
        certificate.graph.is_none(),
        "per-unit proof must not retain old full graphs across structural edits"
    );
    let prepared = licensed.prepared(row).unwrap();
    let current =
        crate::lowering_memo::key_recipe::CurrentKey::from_prepared(&front, row, 7, false, false)
            .unwrap();
    let tail = crate::lowering_memo::key_recipe::PreparedKey::issued(&prepared).unwrap();
    let key: Arc<[u8]> = current.materialize(&tail).into();
    certificate = certificate.bind_key(&key);
    let mut record = Record {
        local: Some(certificate.clone()),
        recipe: crate::lowering_memo::key_recipe::KeyRecipe::new(
            &key,
            Arc::clone(current.metadata),
        ),
        key,
        reads: Vec::<ResolverRead>::new().into(),
        versions: Arc::from([]),
        value: RecordValue::Selections {
            facts: Arc::new(Default::default()),
            abi: vec![],
        },
        relative_debug: vec![],
        required_types: Arc::from([]),
        modified_recipes: Arc::from([]),
    };
    let admitted = certificate.matches(&licensed, row, 7, &record).unwrap();
    assert!(Arc::ptr_eq(&admitted.inputs, &prepared.inputs));
    assert!(certificate.matches(&licensed, row, 8, &record).is_none());
    let mut detached = certificate.clone();
    detached.inputs = std::sync::Weak::new();
    assert!(detached.matches(&licensed, row, 7, &record).is_none());
    let foreign = build();
    let foreign_roster = PreparedBodyRoster::issue(&foreign).unwrap();
    assert!(certificate
        .matches(
            &licensed,
            foreign_roster.ordered().next().unwrap(),
            7,
            &record
        )
        .is_none());
    let mut bytes = record.key.to_vec();
    let at = bytes
        .windows(b"return x".len())
        .position(|bytes| bytes == b"return x")
        .unwrap();
    bytes[at + 7] = b'y';
    let original_key = Arc::clone(&record.key);
    record.key = bytes.into();
    assert!(certificate.matches(&licensed, row, 7, &record).is_none());
    record.key = original_key;
    // The same local capability is consumed by the real frozen contribution
    // rebind and existing lease; this fixture does not synthesize machine code.
    let arena = dm_tree::frontend::BodyArena::new(&front);
    let capture = std::cell::RefCell::new(MemoCapture::default());
    let unit = lower_one_captured(
        &front,
        row.body(),
        front.snapshot.tree.as_ref(),
        &policy,
        &arena,
        LoweringCapture {
            startup: Some(&startup),
            capture: Some(&capture),
            ready: None,
            capture_references: false,
            current: Some(row.source()),
        },
    )
    .unwrap();
    let value = crate::symbolic::prepare_contribution(
        unit,
        front.snapshot.tree.symbols(),
        roster.source_bindings(&front).unwrap(),
        &Default::default(),
        false,
    )
    .unwrap();
    record.value = RecordValue::Executable(value.shared_artifact());
    record.required_types = Arc::clone(value.required_types_owner());
    record.relative_debug = capture.borrow().debug.clone();
    let owner = SessionSymbolicMemo::current_revision();
    let first = owner.for_request(true);
    assert!(first.insert_record(row.source().identity, record));
    assert!(first.publish_successful());
    drop(first);
    let next = owner.for_request(false);
    let admission = RequestAdmission::new(front.snapshot.tree.as_ref());
    let candidates = next.candidate_roster(&admission).unwrap();
    let fresh_arena = dm_tree::frontend::BodyArena::new(&front);
    let replay_roster = PreparedBodyRoster::issue(&front).unwrap();
    let replay_row = replay_roster.ordered().next().unwrap();
    assert!(!replay_row.input_bound());
    let replay = next
        .lookup_unchanged_local(
            &licensed,
            &candidates,
            7,
            front.snapshot.tree.as_ref(),
            &front,
            replay_row,
            &fresh_arena,
        )
        .unwrap();
    assert!(
        !replay_row.input_bound(),
        "exact producer owner hit must not bind the source envelope"
    );
    assert_eq!(replay.identity(), row.source().identity);
    assert_eq!(replay.into_selected().source(), &row.body().source);
}
