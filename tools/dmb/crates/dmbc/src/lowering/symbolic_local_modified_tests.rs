//! Actual ABI/body/descriptor producers, with the same local admission and lease.
use super::*;
use std::{collections::BTreeMap, path::Path};
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
const SOURCE: &str = "/obj/outer\n    var/child\n/obj/inner\n    var/amount\n/datum/a/proc/p()\n    return /obj/outer{child=/obj/inner{amount=7}}\n";
fn build(
    state: &mut dm_tree::frontend::RetainedSemanticTree,
    text: &str,
    engine: &crate::runner_host::EnginePayload,
    executor: &dm_exec::BuildExecutor,
) -> ColdFrontend {
    let seed = engine.snapshot.frontend_seed();
    dm_tree::frontend::build_with_executor_and_semantic_state(
        Path::new("modified-local.dme"),
        &Source(text.into()),
        &BTreeMap::new(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(&seed),
            observer: None,
        },
        None,
        executor,
        Some(state),
    )
    .unwrap()
}
fn prepare<'a, R: Resolver>(
    front: &'a ColdFrontend,
    row: &PreparedBody<'a>,
    host: &R,
    policy: &impl AbiPolicy,
    startup: &crate::startup::CapturedStartup<'a>,
    licensed: &LocalInputRoster<'_>,
) -> (Record, crate::symbolic::PreparedContribution) {
    let prepared = licensed.prepared(row).unwrap();
    let current =
        crate::lowering_memo::key_recipe::CurrentKey::from_prepared(front, row, 7, false, false)
            .unwrap();
    let key: Arc<[u8]> = current
        .materialize(&crate::lowering_memo::key_recipe::PreparedKey::issued(&prepared).unwrap())
        .into();
    let recorder = crate::lowering_memo::RecordingResolver::new(host);
    let arena = dm_tree::frontend::BodyArena::new(front);
    let capture = RefCell::new(MemoCapture::default());
    let unit = lower_one_captured(
        front,
        row.body(),
        &recorder,
        policy,
        &arena,
        LoweringCapture {
            startup: Some(startup),
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
        front.callable_roster().unwrap().source_bindings(),
        &Default::default(),
        false,
    )
    .unwrap();
    let recipes = Arc::clone(value.modified_recipes_owner().unwrap());
    assert!(
        !recipes.is_empty(),
        "actual producer must capture modified recipes"
    );
    let record = Record {
        local: Some(Certificate::issue(licensed, row, 7).unwrap().bind_key(&key)),
        recipe: crate::lowering_memo::key_recipe::KeyRecipe::new(
            &key,
            Arc::clone(current.metadata),
        ),
        key,
        reads: recorder.reads().into(),
        versions: Arc::from([]),
        value: RecordValue::Executable(value.shared_artifact()),
        relative_debug: capture.borrow().debug.clone(),
        required_types: Arc::clone(value.required_types_owner()),
        modified_recipes: recipes,
    };
    (record, value)
}
#[test]
fn modified_local_candidate_reissues_current_nested_recipes_and_matches_fresh() {
    let engine = crate::runner_host::EnginePayload::capture(
        include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        1,
        true,
        0,
    )
    .unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let mut state = dm_tree::frontend::RetainedSemanticTree::default();
    let artifacts = crate::driver_facts::AbiArtifacts::with_engine_owner(Arc::clone(&engine));
    let owner = SessionSymbolicMemo::current_revision();
    let front = build(&mut state, SOURCE, &engine, &executor);
    let (host, _) = crate::request_runner::runner_facts::prepare(&front, &engine.snapshot).unwrap();
    let startup = crate::startup::capture(&front).unwrap();
    let abi =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &front,
            &engine.snapshot,
            &host,
            &startup,
            None,
            &executor,
            Some(&artifacts),
        )
        .unwrap();
    assert!(abi.prepared.diagnostics.is_empty());
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(&front, &abi.prepared).unwrap();
    let roster = PreparedBodyRoster::issue(&front).unwrap();
    let row = roster.at(0);
    let licensed = policy
        .current_local_inputs(&front, front.snapshot.tree.symbols())
        .unwrap();
    let (record, _) = prepare(&front, row, &host, &policy, &startup, &licensed);
    let first = owner.for_request(true);
    assert!(first.insert_record(row.source().identity, record));
    assert!(first.publish_successful());
    for text in [SOURCE.to_string(), format!("\n\n{SOURCE}")] {
        let current = build(&mut state, &text, &engine, &executor);
        let (host, _) =
            crate::request_runner::runner_facts::prepare(&current, &engine.snapshot).unwrap();
        let startup = crate::startup::capture(&current).unwrap();
        let abi =
            crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
                &current,
                &engine.snapshot,
                &host,
                &startup,
                None,
                &executor,
                Some(&artifacts),
            )
            .unwrap();
        assert!(abi.prepared.diagnostics.is_empty());
        let policy =
            crate::driver_facts::FrozenPreparedPolicy::new(&current, &abi.prepared).unwrap();
        let roster = PreparedBodyRoster::issue(&current).unwrap();
        let row = roster.at(0);
        let licensed = policy
            .current_local_inputs(&current, current.snapshot.tree.symbols())
            .unwrap();
        let request = owner.for_request(false);
        let admission = RequestAdmission::new(&host);
        let candidates = request.candidate_roster(&admission).unwrap();
        let arena = dm_tree::frontend::BodyArena::new(&current);
        let hit = request
            .lookup_unchanged_local(&licensed, &candidates, 7, &host, &current, row, &arena)
            .expect("modified local candidate must use ordinary current recipe reissue");
        let Input::Reused(reused) = hit.inner else {
            panic!("expected reused contribution")
        };
        let (_, fresh) = prepare(&current, row, &host, &policy, &startup, &licensed);
        assert!(reused
            .shared_artifact()
            .verification_equal(&fresh.shared_artifact()));
        assert_eq!(reused.modified_seeds().len(), fresh.modified_seeds().len());
        for (a, b) in reused.modified_seeds().iter().zip(fresh.modified_seeds()) {
            let (ar, ac) = a.clone().into_current_capture();
            let (br, bc) = b.clone().into_current_capture();
            assert_eq!(ar, br);
            assert_eq!(
                ac.descriptor.canonical_bytes(),
                bc.descriptor.canonical_bytes()
            );
            assert_eq!(ac.source_span, bc.source_span);
            assert_eq!(ac.field_origins, bc.field_origins);
        }
    }
    // The unchanged procedure text still depends on the current nested type.
    let removed = SOURCE.replace("/obj/inner\n    var/amount\n", "");
    let current = build(&mut state, &removed, &engine, &executor);
    let (host, _) =
        crate::request_runner::runner_facts::prepare(&current, &engine.snapshot).unwrap();
    assert!(!matches!(
        host.resolve(dm_ir::ResolveQuery::RuntimeType(SymbolId::of("/obj/inner"))),
        dm_ir::ResolvedMeaning::Symbol(_)
    ));
    let startup = crate::startup::capture(&current).unwrap();
    let abi =
        crate::driver_facts::prepare_pinned_source_abi_with_startup_on_executor_with_artifacts(
            &current,
            &engine.snapshot,
            &host,
            &startup,
            None,
            &executor,
            Some(&artifacts),
        )
        .unwrap();
    assert!(abi.prepared.diagnostics.is_empty());
    let policy = crate::driver_facts::FrozenPreparedPolicy::new(&current, &abi.prepared).unwrap();
    let roster = PreparedBodyRoster::issue(&current).unwrap();
    let row = roster.at(0);
    let licensed = policy
        .current_local_inputs(&current, current.snapshot.tree.symbols())
        .unwrap();
    let request = owner.for_request(false);
    let admission = RequestAdmission::new(&host);
    let candidates = request.candidate_roster(&admission).unwrap();
    let arena = dm_tree::frontend::BodyArena::new(&current);
    assert!(request
        .lookup_unchanged_local(&licensed, &candidates, 7, &host, &current, row, &arena)
        .is_none());
}
