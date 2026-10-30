use super::*;
use crate::input_snapshot::{
    FileSystemInputs, FolderListing, RecordingInputs, SnapshotProvider, Stamp,
};
use crate::runner_host::query_snapshot::{QueryAttempt, QueryState};
use std::{
    path::{Path, PathBuf},
    sync::atomic::{AtomicUsize, Ordering},
};
#[derive(Clone)]
struct Files(Arc<AtomicUsize>);
impl SnapshotProvider for Files {
    fn stamp(&self, p: &Path) -> io::Result<Stamp> {
        self.0.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.stamp(p)
    }
    fn read(&self, p: &Path) -> io::Result<(Stamp, Vec<u8>)> {
        self.0.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.read(p)
    }
    fn list(&self, p: &Path) -> io::Result<FolderListing> {
        self.0.fetch_add(1, Ordering::Relaxed);
        FileSystemInputs.list(p)
    }
}
struct Fixture {
    environment: PathBuf,
    inputs: RecordingInputs<Files>,
    provider: Files,
    frontend: dm_tree::frontend::ColdFrontend,
    engine: Arc<crate::runner_host::RetainedEngine>,
    db: Arc<QueryDb>,
}
fn fixture(source: &str, db: Arc<QueryDb>) -> Fixture {
    let root = crate::test_scratch::dir("source-answer-scope");
    std::fs::create_dir_all(&root).unwrap();
    let environment = root.join("p.dme");
    std::fs::write(&environment, source).unwrap();
    let provider = Files(Arc::new(AtomicUsize::new(0)));
    let inputs = RecordingInputs::new(provider.clone(), 4_000_000_000)
        .with_prepared_sources(Some(Arc::new(Default::default())));
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            environment.clone(),
            Default::default(),
            true,
            include_bytes!("../../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &environment,
        &inputs,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(engine.frontend_seed()),
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .unwrap()
    .with_body_queries(db.clone());
    let original = frontend
        .files
        .iter()
        .find(|f| f.path.as_ref() == &environment)
        .unwrap();
    let acquired =
        dm_preprocess::SourceProvider::source_acquisition(&inputs, &environment, &original.text)
            .unwrap();
    let prepared = dm_preprocess::regions::prepared_source::PreparedSources::from_prepared([(
        environment.clone(),
        Arc::clone(acquired.prepared()),
    )])
    .unwrap();
    db.revise(&prepared, 123).unwrap();
    Fixture {
        environment,
        inputs,
        provider,
        frontend,
        engine,
        db,
    }
}
fn stage(f: &Fixture, state: &Arc<Mutex<QueryState>>) -> QueryAttempt {
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&f.frontend, f.db.clone(), None, &f.inputs)
        .unwrap();
    attempt.require_source_answers().unwrap();
    attempt
}
fn admission(
    f: &Fixture,
    attempt: &QueryAttempt,
) -> crate::request_runner::runner_freshness::SourceFrameAdmission {
    crate::request_runner::runner_freshness::admit_source_captured_with_provider_for_test(
        &f.inputs,
        &f.provider,
        attempt.pending_source().unwrap(),
    )
    .unwrap()
    .1
}
fn publish(f: &Fixture, state: &Arc<Mutex<QueryState>>) {
    let mut attempt = stage(f, state);
    attempt.admit_source_frame(admission(f, &attempt)).unwrap();
    attempt.finish_analyzed();
}
fn ask(f: &Fixture, state: &Arc<Mutex<QueryState>>, q: Q) -> io::Result<u128> {
    state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .source_answer_hash(f.frontend.snapshot.tree.as_ref(), q)
}
fn type_question(path: dm_ir::SymbolId) -> Q {
    Q::CertifiedHierarchy {
        kind: dm_ir::HierarchyQuestion::Type,
        path,
    }
}
fn parent_question(path: dm_ir::SymbolId) -> Q {
    Q::CertifiedHierarchy {
        kind: dm_ir::HierarchyQuestion::Parent,
        path,
    }
}
fn ancestry_question(path: dm_ir::SymbolId) -> Q {
    Q::CertifiedHierarchy {
        kind: dm_ir::HierarchyQuestion::Ancestry,
        path,
    }
}
const BODY: &str = "/datum/answer_box\n    var/value\n/proc/answer_work()\n    return\n";
#[test]
fn actual_source_scope_current_db_warm_missing_builtin_and_foreign_samehash_guards() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    // Successful frontend alone does not publish or issue any Answers binding.
    {
        let attempt = stage(&f, &state);
        assert!(state.lock().unwrap().snapshot.is_none());
        drop(attempt);
    }
    publish(&f, &state);
    let tree = f.frontend.snapshot.tree.as_ref();
    let qs = [
        type_question(dm_ir::SymbolId::of("/datum/answer_box")),
        type_question(dm_ir::SymbolId::of("/list")),
        type_question(dm_ir::SymbolId::of("/datum/missing")),
        parent_question(dm_ir::SymbolId::of("/datum/answer_box")),
        ancestry_question(dm_ir::SymbolId::of("/datum/answer_box")),
        ancestry_question(dm_ir::SymbolId::of("/datum/missing")),
    ];
    for q in qs {
        assert_eq!(
            ask(&f, &state, q).unwrap(),
            answer_hash(&Resolver::resolve(tree, q))
        );
    }
    let before = f.db.answer_counts();
    let io_before = f.provider.0.load(Ordering::Relaxed);
    for q in qs {
        ask(&f, &state, q).unwrap();
    }
    assert_eq!(
        f.db.answer_counts(),
        before,
        "same input warm queries do not resolve or add Answers"
    );
    assert_eq!(
        f.provider.0.load(Ordering::Relaxed),
        io_before,
        "source queries do no provider IO"
    );
    let copied = tree.clone();
    assert_eq!(copied.identity(), tree.identity());
    assert!(state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .source_answer_hash(&copied, qs[0])
        .is_err());
    assert!(ask(
        &f,
        &state,
        Q::GlobalProc(dm_ir::SymbolId::of("answer_work"))
    )
    .is_err());
    assert!(ask(&f, &state, Q::Resource(dm_ir::SymbolId::of("asset.dmi"))).is_err());
    assert_eq!(
        f.db.answer_counts(),
        before,
        "rejected families/owners never reach the cache"
    );
    f.db.next_request();
    assert_eq!(
        ask(&f, &state, qs[0]).unwrap_err().kind(),
        io::ErrorKind::InvalidInput
    );
    assert_eq!(
        f.db.answer_counts().0,
        0,
        "request advance resets counters, stale scope did not resolve"
    );
}
#[test]
fn real_runtime_startup_source_binding_orders_and_builtin_negative_answers() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    let (runtime, _) =
        crate::request_runner::runner_facts::prepare_retained(&f.frontend, &f.engine, None)
            .unwrap();
    let startup = crate::startup::capture(&f.frontend).unwrap();
    let startup_resolver = startup.resolver(&f.frontend, &runtime).unwrap();
    let tree = &f.frontend.snapshot.tree;
    let qs = [
        type_question(dm_ir::SymbolId::of("/list")),
        type_question(dm_ir::SymbolId::of("/datum/missing")),
        parent_question(dm_ir::SymbolId::of("/datum/answer_box")),
        ancestry_question(dm_ir::SymbolId::of("/list")),
    ];
    let resolve = |q: &Q| startup_resolver.resolve(*q);
    f.db.begin_answers(tree, startup_resolver.answer_world(), &resolve);
    for q in qs {
        let source = Resolver::resolve(tree.as_ref(), q);
        assert_eq!(runtime.resolve(q), source, "engine fallback {q:?}");
        assert_eq!(
            startup_resolver.resolve(q),
            source,
            "startup delegation {q:?}"
        );
        f.db.request_answers(&resolve).current(query_id(&q), &q);
    }
    publish(&f, &state); // runtime -> source: freshness is required before rebinding.
    for q in qs {
        assert_eq!(
            ask(&f, &state, q).unwrap(),
            answer_hash(&Resolver::resolve(tree.as_ref(), q))
        );
    }
    f.db.begin_answers(tree, startup_resolver.answer_world(), &resolve); // source -> runtime
    let before = f.db.answer_counts();
    assert!(
        ask(&f, &state, qs[0]).is_err(),
        "a later runtime binding invalidates exact source generation"
    );
    assert_eq!(before, f.db.answer_counts());
    for q in qs {
        assert_eq!(
            f.db.request_answers(&resolve).current(query_id(&q), &q),
            answer_hash(&runtime.resolve(q))
        );
    }
}
#[test]
fn ordinary_same_request_world_rebind_recomputes_value_answers_without_source_mode() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let tree = &f.frontend.snapshot.tree;
    let q = Q::Constant {
        owner: dm_ir::SymbolId::of("/"),
        name: dm_ir::SymbolId::of("world_changing"),
    };
    let one =
        |_: &Q| dm_ir::ResolvedMeaning::Value(dm_ir::SemanticValue::NumberBits(1f32.to_bits()));
    let two =
        |_: &Q| dm_ir::ResolvedMeaning::Value(dm_ir::SemanticValue::NumberBits(2f32.to_bits()));
    f.db.begin_answers(tree, Some(1), &one);
    assert_eq!(
        f.db.request_answers(&one).current(query_id(&q), &q),
        answer_hash(&one(&q))
    );
    f.db.begin_answers(tree, Some(2), &two);
    assert_eq!(
        f.db.request_answers(&two).current(query_id(&q), &q),
        answer_hash(&two(&q)),
        "same request/tree alone cannot carry a different world"
    );
}
#[test]
fn failed_freshness_and_failed_candidate_leave_old_frame_but_never_mix_new_answers() {
    let db = Arc::new(QueryDb::default());
    let old = fixture(BODY, db.clone());
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&old, &state);
    let q = type_question(dm_ir::SymbolId::of("/datum/new_decl"));
    assert_eq!(
        ask(&old, &state, q).unwrap(),
        answer_hash(&dm_ir::ResolvedMeaning::Missing)
    );
    let old_revision = state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .source_revision;
    let candidate = fixture("/datum/new_decl\n/proc/p()\n    return\n", db.clone());
    {
        let attempt = stage(&candidate, &state);
        std::fs::write(&candidate.environment, "/datum/changed_after_capture\n").unwrap();
        assert!(
            crate::request_runner::runner_freshness::admit_source_captured_with_provider_for_test(
                &candidate.inputs,
                &candidate.provider,
                attempt.pending_source().unwrap()
            )
            .is_err()
        );
        drop(attempt);
    }
    assert_eq!(
        state
            .lock()
            .unwrap()
            .snapshot
            .as_ref()
            .unwrap()
            .source_revision,
        old_revision
    );
    let counts = db.answer_counts();
    assert!(ask(&old, &state, q).is_err());
    assert_eq!(counts, db.answer_counts());
    let next = fixture("/datum/new_decl\n/proc/p()\n    return\n", db.clone());
    publish(&next, &state);
    assert_eq!(
        ask(&next, &state, q).unwrap(),
        answer_hash(&dm_ir::ResolvedMeaning::Symbol(dm_ir::SymbolId::of(
            "/datum/new_decl"
        )))
    );
    let removed = fixture(BODY, db);
    publish(&removed, &state);
    assert_eq!(
        ask(&removed, &state, q).unwrap(),
        answer_hash(&dm_ir::ResolvedMeaning::Missing)
    );
}
#[test]
fn cancellation_before_binding_preserves_old_generation_after_binding_commit_is_indivisible() {
    use crate::daemon::control::Cancellation;
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    let q = type_question(dm_ir::SymbolId::of("/list"));
    let original = ask(&f, &state, q).unwrap();
    let mut attempt = stage(&f, &state);
    let admitted = admission(&f, &attempt);
    let token = Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    let hook = hooks::cancel_at(false, token.clone());
    assert_eq!(
        attempt.admit_source_frame(admitted).unwrap_err().kind(),
        io::ErrorKind::Interrupted
    );
    drop(hook);
    drop(binding);
    drop(attempt);
    assert_eq!(
        ask(&f, &state, q).unwrap(),
        original,
        "failed staging left the exact prior binding usable"
    );
    let mut attempt = stage(&f, &state);
    let admitted = admission(&f, &attempt);
    let token = Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    let hook = hooks::cancel_at(true, token.clone());
    attempt.admit_source_frame(admitted).unwrap();
    attempt.finish_analyzed();
    assert!(
        !token.is_cancelled(),
        "publication fence rejects cancellation after commit starts"
    );
    crate::daemon::control::checkpoint().unwrap();
    drop(hook);
    drop(binding);
    drop(attempt);
    assert_eq!(
        ask(&f, &state, q).unwrap(),
        original,
        "new source frame and binding commit together"
    );
}

#[test]
fn original_answer_table_settles_forced_query_id_collision_by_exact_question_not_hash() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let tree = &f.frontend.snapshot.tree;
    let one = type_question(dm_ir::SymbolId::of("/list"));
    let two = type_question(dm_ir::SymbolId::of("/datum/not_declared"));
    let resolve = |q: &Q| Resolver::resolve(tree.as_ref(), *q);
    f.db.begin_answers(tree, tree.answer_world(), &resolve);
    let request = f.db.request_answers(&resolve);
    let forced = 0xfeed;
    assert_eq!(request.current(forced, &one), answer_hash(&resolve(&one)));
    assert_eq!(
        request.current(forced, &two),
        answer_hash(&resolve(&two)),
        "same hash slot cannot conceal a different qualified query"
    );
}

fn raw_same_request(f: &Fixture) -> dm_tree::frontend::ColdFrontend {
    // Genuine original provider/build, not an injected eligibility flag. This
    // unseeded frontend has no checker profile; no Db.revise/request advance.
    dm_tree::frontend::build(&f.environment, &f.inputs, &Default::default(), 1)
        .unwrap()
        .with_body_queries(f.db.clone())
}
fn stage_raw(
    f: &Fixture,
    state: &Arc<Mutex<QueryState>>,
    front: &dm_tree::frontend::ColdFrontend,
) -> QueryAttempt {
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(front, f.db.clone(), None, &f.inputs)
        .unwrap();
    attempt
}
#[test]
fn ineligible_publication_checks_cancellation_and_request_before_replacing_current_frame() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    let q = type_question(dm_ir::SymbolId::of("/list"));
    let original = ask(&f, &state, q).unwrap();
    let revision = state
        .lock()
        .unwrap()
        .snapshot
        .as_ref()
        .unwrap()
        .source_revision;
    let raw = raw_same_request(&f);
    assert!(raw.snapshot.tree.checker_builtin_profile().is_none());
    let mut attempt = stage_raw(&f, &state, &raw);
    let admitted = admission(&f, &attempt);
    let token = crate::daemon::control::Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        std::time::Instant::now() + std::time::Duration::from_secs(60),
    );
    let hook = hooks::cancel_at(false, token);
    assert_eq!(
        attempt.admit_source_frame(admitted).unwrap_err().kind(),
        io::ErrorKind::Interrupted
    );
    drop(hook);
    drop(binding);
    drop(attempt);
    assert_eq!(
        state
            .lock()
            .unwrap()
            .snapshot
            .as_ref()
            .unwrap()
            .source_revision,
        revision
    );
    assert_eq!(
        ask(&f, &state, q).unwrap(),
        original,
        "cancelled ineligible publication preserves old binding"
    );
    let mut attempt = stage_raw(&f, &state, &raw);
    let admitted = admission(&f, &attempt);
    f.db.next_request();
    let prior = f.db.answers.current.read().unwrap().source_binding.clone();
    assert_eq!(
        attempt.admit_source_frame(admitted).unwrap_err().kind(),
        io::ErrorKind::InvalidInput
    );
    drop(attempt);
    let current = f.db.answers.current.read().unwrap();
    assert!(match (&prior, &current.source_binding) {
        (None, None) => true,
        (Some(a), Some(b)) => a.same_owner(b),
        _ => false,
    });
    drop(current);
    assert_eq!(
        state
            .lock()
            .unwrap()
            .snapshot
            .as_ref()
            .unwrap()
            .source_revision,
        revision
    );
}
#[test]
fn same_request_eligible_to_ineligible_publication_retires_old_scope_without_rebinding_world() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    // Retain the actual old issued snapshot just as a caller holding its frame.
    let old = state.lock().unwrap().snapshot.take().unwrap();
    let q = type_question(dm_ir::SymbolId::of("/list"));
    old.source_answer_hash(f.frontend.snapshot.tree.as_ref(), q)
        .unwrap();
    let (prior_request, prior_world, prior_generation) = {
        let current = f.db.answers.current.read().unwrap();
        (
            current.request,
            current.world,
            current.source_binding.clone(),
        )
    };
    let raw = raw_same_request(&f);
    let mut attempt = stage_raw(&f, &state, &raw);
    attempt.admit_source_frame(admission(&f, &attempt)).unwrap();
    attempt.finish_analyzed();
    let current = f.db.answers.current.read().unwrap();
    assert_eq!(current.request, prior_request);
    assert_eq!(current.world, prior_world);
    assert!(prior_generation.is_some());
    assert!(current.source_binding.is_none());
    drop(current);
    assert!(
        old.source_answer_hash(f.frontend.snapshot.tree.as_ref(), q)
            .is_err(),
        "successful raw frame retires old source scope in SAME request"
    );
    assert_eq!(
        state
            .lock()
            .unwrap()
            .snapshot
            .as_ref()
            .unwrap()
            .source_answer_hash(raw.snapshot.tree.as_ref(), q)
            .unwrap_err()
            .kind(),
        io::ErrorKind::Unsupported
    );
}

fn unrequested(f: &Fixture, state: &Arc<Mutex<QueryState>>) -> QueryAttempt {
    let mut attempt = QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&f.frontend, f.db.clone(), None, &f.inputs)
        .unwrap();
    attempt
}
fn source_quota_db(bytes: usize) -> Arc<QueryDb> {
    let mut db = QueryDb::default();
    db.answers = Answers::with_values(Arc::new(AnswerValues::with_source_ledger(
        SourceLedger::new(bytes),
    )));
    Arc::new(db)
}
#[test]
fn explicit_not_requested_works_without_source_quota_and_required_denial_preserves_frame() {
    let f = fixture(BODY, source_quota_db(0));
    let state = Arc::new(Mutex::new(QueryState::default()));
    let mut plain = unrequested(&f, &state);
    plain.admit_source_frame(admission(&f, &plain)).unwrap();
    plain.finish_analyzed();
    let q = type_question(dm_ir::SymbolId::of("/list"));
    assert_eq!(
        ask(&f, &state, q).unwrap_err().kind(),
        io::ErrorKind::Unsupported
    );
    state.lock().unwrap().snapshot.as_mut().unwrap().outcome =
        "source-frame-before-denied-required";
    let before = f.db.answers.values.source_ledger.snapshot();
    let mut required = stage(&f, &state);
    let ready = admission(&f, &required);
    assert_eq!(
        required.admit_source_frame(ready).unwrap_err().kind(),
        io::ErrorKind::OutOfMemory
    );
    drop(required);
    assert_eq!(
        state.lock().unwrap().snapshot.as_ref().unwrap().outcome,
        "source-frame-before-denied-required"
    );
    assert!(f
        .db
        .answers
        .current
        .read()
        .unwrap()
        .source_binding
        .is_none());
    assert_eq!(
        f.db.answers.values.source_ledger.snapshot().live,
        before.live
    );
}
#[test]
fn denied_arc_profile_is_not_downgraded_and_required_mode_freezes_before_admission() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    let q = type_question(dm_ir::SymbolId::of("/list"));
    let expected = ask(&f, &state, q).unwrap();
    state.lock().unwrap().snapshot.as_mut().unwrap().outcome =
        "source-frame-before-unqualified-required";
    let generation =
        f.db.answers
            .current
            .read()
            .unwrap()
            .source_binding
            .clone()
            .unwrap();
    let mut required = stage(&f, &state);
    let ready = admission(&f, &required);
    assert!(
        required.require_source_answers().is_err(),
        "admission borrowed the immutable exact frame"
    );
    let deny = super::super::native_arc_allocation::test_denial::deny();
    assert_eq!(
        required.admit_source_frame(ready).unwrap_err().kind(),
        io::ErrorKind::Unsupported
    );
    drop(required);
    assert_eq!(
        state.lock().unwrap().snapshot.as_ref().unwrap().outcome,
        "source-frame-before-unqualified-required"
    );
    assert!(f
        .db
        .answers
        .current
        .read()
        .unwrap()
        .source_binding
        .as_ref()
        .unwrap()
        .same_owner(&generation));
    assert_eq!(
        ask(&f, &state, q).unwrap(),
        expected,
        "already admitted warm value/frame survives failed source publication"
    );
    drop(deny);
}
#[test]
fn bounded_missing_ids_deny_without_semantic_error_slots_and_warm_answer_needs_no_new_lease() {
    let f = fixture(BODY, source_quota_db(32 * 1024));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    let warm = type_question(dm_ir::SymbolId::of("/list"));
    let expected = ask(&f, &state, warm).unwrap();
    let mut denied = false;
    for n in 0..2000 {
        let q = type_question(dm_ir::SymbolId::of(&format!("/datum/bounded_missing_{n}")));
        let before = f.db.answer_counts();
        match ask(&f, &state, q) {
            Ok(hash) => assert_eq!(hash, answer_hash(&dm_ir::ResolvedMeaning::Missing)),
            Err(error) => {
                assert_eq!(error.kind(), io::ErrorKind::OutOfMemory);
                assert_eq!(
                    f.db.answer_counts().0,
                    before.0,
                    "denied query cannot publish a semantic/error slot"
                );
                denied = true;
                break;
            }
        }
    }
    assert!(
        denied,
        "finite global source quota must cap arbitrary missing IDs"
    );
    let before = f.db.answers.values.source_ledger.snapshot();
    assert_eq!(ask(&f, &state, warm).unwrap(), expected);
    assert_eq!(
        f.db.answers.values.source_ledger.snapshot(),
        before,
        "warm path allocates/scans/reserves nothing"
    );
}
#[test]
fn real_runtime_authority_advance_refuses_scope_without_erasing_its_published_token() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    let token =
        f.db.answers
            .current
            .read()
            .unwrap()
            .source_binding
            .clone()
            .unwrap();
    let q = type_question(dm_ir::SymbolId::of("/list"));
    ask(&f, &state, q).unwrap();
    state.lock().unwrap().snapshot.as_mut().unwrap().outcome =
        "published-source-before-real-runtime-advance";
    let world = f.db.answers.current.read().unwrap().world;
    let tree = Arc::clone(&f.frontend.snapshot.tree);
    f.db.begin_answers(&tree, Some(world.wrapping_add(1)), &|q| {
        Resolver::resolve(tree.as_ref(), *q)
    });
    assert!(f
        .db
        .answers
        .current
        .read()
        .unwrap()
        .source_binding
        .as_ref()
        .unwrap()
        .same_owner(&token));
    assert_eq!(
        ask(&f, &state, q).unwrap_err().kind(),
        io::ErrorKind::InvalidInput
    );
    assert_eq!(
        state.lock().unwrap().snapshot.as_ref().unwrap().outcome,
        "published-source-before-real-runtime-advance"
    );
}

#[test]
fn census_counts_generation_retained_only_by_original_current_binding() {
    let f = fixture(BODY, Arc::new(QueryDb::default()));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    state.lock().unwrap().snapshot = None;
    let mut census = crate::heap_census::HeapCensus::new("source-generation-only");
    f.db.answer_storage_census(&mut census);
    let report = census.finish();
    let generation = report
        .owners
        .iter()
        .find(|owner| owner.owner == "answers.original_source_generation")
        .expect("the current original binding is itself a retained allocation");
    assert_eq!(generation.unique_allocations, 1);
    assert_eq!(
        generation.unique_known_capacity_bytes,
        Plan::source_generation().unwrap().layout().size() as u64
    );
}

#[test]
fn repeated_cancelled_required_publications_release_transients_and_keep_old_frame_warm() {
    use crate::daemon::control::Cancellation;
    let f = fixture(BODY, source_quota_db(64 * 1024));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    let q = type_question(dm_ir::SymbolId::of("/list"));
    let expected = ask(&f, &state, q).unwrap();
    let generation =
        f.db.answers
            .current
            .read()
            .unwrap()
            .source_binding
            .clone()
            .unwrap();
    let baseline = f.db.answers.values.source_ledger.snapshot().live;
    let counts = f.db.answer_counts();
    for _ in 0..16 {
        let mut attempt = stage(&f, &state);
        let ready = admission(&f, &attempt);
        let token = Cancellation::default();
        let binding = crate::daemon::control::bind_with_deadline(
            token.clone(),
            std::time::Instant::now() + std::time::Duration::from_secs(60),
        );
        let hook = hooks::cancel_at(false, token);
        assert_eq!(
            attempt.admit_source_frame(ready).unwrap_err().kind(),
            io::ErrorKind::Interrupted
        );
        drop(hook);
        drop(binding);
        drop(attempt);
        assert_eq!(
            f.db.answers.values.source_ledger.snapshot().live,
            baseline,
            "cancelled transient allocations must return quota after actual free"
        );
        assert!(f
            .db
            .answers
            .current
            .read()
            .unwrap()
            .source_binding
            .as_ref()
            .unwrap()
            .same_owner(&generation));
        assert_eq!(ask(&f, &state, q).unwrap(), expected);
        assert_eq!(
            f.db.answer_counts(),
            counts,
            "cancelled publication/warm query cannot publish an answer slot"
        );
    }
    // Cancellation is operation-local, not a permanently poisoned admission.
    publish(&f, &state);
    assert_eq!(ask(&f, &state, q).unwrap(), expected);
}

#[test]
fn actual_source_value_drop_orders_preserve_weak_charge_and_original_backing() {
    for weak_first in [false, true] {
        let f = fixture(BODY, source_quota_db(64 * 1024));
        let state = Arc::new(Mutex::new(QueryState::default()));
        publish(&f, &state);
        let q = type_question(dm_ir::SymbolId::of("/datum/missing_drop_order"));
        assert_eq!(
            ask(&f, &state, q).unwrap(),
            answer_hash(&dm_ir::ResolvedMeaning::Missing)
        );
        let id = query_id(&q);
        let shard = (id as usize) % ANSWER_SHARDS;
        let pool_shard = (id as usize) % VALUE_SHARDS;
        let slot = f.db.answers.shards[shard]
            .lock()
            .unwrap()
            .remove(&id)
            .unwrap();
        assert!(slot.base.is_none());
        let retained = slot.value.clone();
        assert!(retained.source_admitted());
        drop(slot);
        let charged = f.db.answers.values.source_ledger.snapshot().live;
        let slot_backing = f.db.answers.shards[shard]
            .lock()
            .unwrap()
            .allocator()
            .allocation_snapshot();
        let pool_backing = f.db.answers.values.shards[pool_shard]
            .lock()
            .unwrap()
            .allocator()
            .allocation_snapshot();
        if weak_first {
            let pooled = f.db.answers.values.shards[pool_shard]
                .lock()
                .unwrap()
                .remove(&(id as u64))
                .unwrap();
            drop(pooled);
            assert_eq!(
                f.db.answers.values.source_ledger.snapshot().live,
                charged,
                "original strong owner survives actual pooled Weak removal"
            );
            drop(retained);
        } else {
            drop(retained);
            assert_eq!(
                f.db.answers.values.source_ledger.snapshot().live,
                charged,
                "original pooled Weak retains allocation after final strong drop"
            );
            assert_eq!(
                f.db.answers.values.shards[pool_shard]
                    .lock()
                    .unwrap()
                    .get(&(id as u64))
                    .unwrap()
                    .strong_count(),
                0
            );
            f.db.answers.values.prune();
        }
        let released = Plan::canonical_value().unwrap().layout().size()
            + Plan::retention_lease().unwrap().layout().size();
        assert_eq!(
            f.db.answers.values.source_ledger.snapshot().live,
            charged - released,
            "only actual canonical value and its final retention allocation were freed"
        );
        assert_eq!(
            f.db.answers.shards[shard]
                .lock()
                .unwrap()
                .allocator()
                .allocation_snapshot(),
            slot_backing
        );
        assert_eq!(
            f.db.answers.values.shards[pool_shard]
                .lock()
                .unwrap()
                .allocator()
                .allocation_snapshot(),
            pool_backing,
            "removing entries cannot return quota for retained original map backing"
        );
    }
}

#[test]
fn actual_source_endpoint_rejects_same_request_stamp_collision_with_different_question() {
    let f = fixture(BODY, source_quota_db(64 * 1024));
    let state = Arc::new(Mutex::new(QueryState::default()));
    publish(&f, &state);
    let requested = type_question(dm_ir::SymbolId::of("/datum/collision_absent"));
    let different = type_question(dm_ir::SymbolId::of("/list"));
    let id = query_id(&requested);
    let wrong = f.db.answers.values.intern(
        id,
        &different,
        &dm_ir::ResolvedMeaning::Symbol(dm_ir::SymbolId::of("/list")),
    );
    // Inject an adversarial collision into the ORIGINAL table. The request,
    // tree/world stamp and low-level slot id all match; only actual Q differs.
    {
        let current = f.db.answers.current.read().unwrap();
        f.db.answers.shards[(id as usize) % ANSWER_SHARDS]
            .lock()
            .unwrap()
            .insert(
                id,
                AnswerSlot {
                    request: slot_request(current.request),
                    stamp: current.stamp,
                    value: wrong,
                    born: 0,
                    changed: 0,
                    base: None,
                },
            );
    }
    assert_eq!(
        ask(&f, &state, requested).unwrap(),
        answer_hash(&dm_ir::ResolvedMeaning::Missing)
    );
    let slots = f.db.answers.shards[(id as usize) % ANSWER_SHARDS]
        .lock()
        .unwrap();
    assert_eq!(slots.get(&id).unwrap().value.query, requested);
    assert!(slots.get(&id).unwrap().value.source_admitted());
}
