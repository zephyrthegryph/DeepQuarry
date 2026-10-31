//! Actual original bytes -> native frontend -> existing Walker -> SAME Db jobs.
//! Expected stderr is the complete independently pinned old executable output;
//! only the fixture filename is replaced by a literal test manifest marker.
use super::*;
use crate::input_snapshot::{FolderListing, RecordingInputs, SnapshotProvider, Stamp};
use crate::policy_request::{PolicyInputFile, PolicyInputRequest, PolicyInputRole};
use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Mutex,
    },
};
#[derive(Clone)]
struct Memory {
    files: Arc<BTreeMap<PathBuf, Vec<u8>>>,
    reads: Arc<AtomicUsize>,
}
impl SnapshotProvider for Memory {
    fn stamp(&self, p: &Path) -> std::io::Result<Stamp> {
        let b = self.files.get(p).ok_or(std::io::ErrorKind::NotFound)?;
        Ok(Stamp {
            size: b.len() as u64,
            modified_ns: 1,
            file_id: Some(1),
        })
    }
    fn read(&self, p: &Path) -> std::io::Result<(Stamp, Vec<u8>)> {
        self.reads.fetch_add(1, Ordering::Relaxed);
        Ok((self.stamp(p)?, self.files[p].clone()))
    }
    fn list(&self, p: &Path) -> std::io::Result<FolderListing> {
        Ok(FolderListing::Present(
            self.files
                .keys()
                .filter(|f| f.parent() == Some(p))
                .filter_map(|f| f.file_name().map(|v| v.to_string_lossy().into_owned()))
                .collect(),
        ))
    }
}
fn env() -> PathBuf {
    std::env::current_dir()
        .unwrap()
        .join("native-purity-provider/project.dme")
}
fn fixture(source: &str, config: Option<&[u8]>) -> (SourceSnapshot, Arc<AtomicUsize>) {
    let environment = env();
    let mut files = BTreeMap::from([(environment.clone(), source.as_bytes().to_vec())]);
    if let Some(c) = config {
        files.insert(
            environment.parent().unwrap().join("SpacemanDMM.toml"),
            c.to_vec(),
        );
    }
    let reads = Arc::new(AtomicUsize::new(0));
    let provider = Memory {
        files: Arc::new(files),
        reads: Arc::clone(&reads),
    };
    let inputs = RecordingInputs::new(provider.clone(), 1)
        .with_prepared_sources(Some(Arc::new(Default::default())));
    let mut host = crate::runner_host::BuildHost::one_shot();
    let engine = host
        .engine(
            environment.clone(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let db = Arc::new(crate::query_db::QueryDb::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
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
        .with_body_queries(db.clone()),
    );
    // Borrow the exact already-prepared source owner used by that frontend;
    // no source reread, re-lex, model parse or secondary semantic owner.
    let original = frontend
        .files
        .iter()
        .find(|file| file.path.as_ref() == &environment)
        .expect("fixture environment is an actual original compiled source");
    let acquired =
        dm_preprocess::SourceProvider::source_acquisition(&inputs, &environment, &original.text)
            .expect("same primary read retains the frontend's exact acquisition");
    assert!(frontend
        .plan
        .source_acquisitions
        .values()
        .any(|lease| { lease.same_binding(acquired.lease()) }));
    // A prepared_source lookup here would refresh/reissue the private lease,
    // invalidating the already-created source mapping. Borrow without reissue.
    let source = Arc::clone(acquired.prepared());
    let prepared = dm_preprocess::regions::prepared_source::PreparedSources::from_prepared([(
        environment.clone(),
        source,
    )])
    .unwrap();
    db.revise(&prepared, 123).unwrap();
    let intent = PolicyInputRequest {workspace_generators:Vec::new(),
        workspace: None,
        files: vec![PolicyInputFile {
            path: environment.parent().unwrap().join("SpacemanDMM.toml"),
            role: PolicyInputRole::Configuration,
            required: false,
        }],
        search_folders: vec![],
    }
    .admit()
    .unwrap();
    let captured = Arc::new(
        crate::runner_host::policy_capture::capture(
            &frontend,
            &inputs,
            &intent.capture_files(),
            &[],
        )
        .unwrap()
        .bind_request(&intent)
        .unwrap(),
    );
    let state = Arc::new(Mutex::new(
        crate::runner_host::query_snapshot::QueryState::default(),
    ));
    let mut attempt = crate::runner_host::query_snapshot::QueryAttempt::new(state.clone(), true);
    attempt
        .capture_with_recorded_sources(&frontend, db, Some(captured), &inputs)
        .unwrap();
    assert!(state.lock().unwrap().snapshot.is_none());
    let frame = attempt.pending_source().unwrap();
    // Semantic policy fixtures need original frontend facts, not runtime ABI
    // inference. Use the existing real-provider closure barrier and receipt.
    let (_, admission) =
        crate::request_runner::runner_freshness::admit_source_captured_with_provider_for_test(
            &inputs, &provider, frame,
        )
        .unwrap();
    attempt.admit_source_frame(admission).unwrap();
    attempt.finish_analyzed();
    drop(attempt);
    let snapshot = state.lock().unwrap().snapshot.take().unwrap();
    (snapshot, reads)
}
/// Decode only the Windows newline transport of the independent stderr file.
/// Do not use lines()/trim(): bare CR, message whitespace, every blank line,
/// note, source point and original ordering remain comparison-significant.
/// Oracle files retain their original bytes; decoding occurs once on expected
/// text, never on native output or source text.
fn decode_oracle_transport(text: &str) -> std::borrow::Cow<'_, str> {
    if text.contains("\r\n") {
        std::borrow::Cow::Owned(text.replace("\r\n", "\n"))
    } else {
        std::borrow::Cow::Borrowed(text)
    }
}
#[test]
fn oracle_transport_decodes_only_crlf_and_preserves_lf_bare_cr_and_full_transcript() {
    let lf = "@FIXTURE@, line 2, column 5:\nerror: a  message \n- 3:4: note\n\n";
    assert!(matches!(
        decode_oracle_transport(lf),
        std::borrow::Cow::Borrowed(_)
    ));
    assert_eq!(
        decode_oracle_transport(&lf.replace("\n", "\r\n")).as_ref(),
        lf
    );
    let bare = "a\rb\nlast\r";
    assert!(matches!(
        decode_oracle_transport(bare),
        std::borrow::Cow::Borrowed(_)
    ));
    assert_eq!(decode_oracle_transport(bare).as_ref(), bare);
    assert_eq!(decode_oracle_transport("a\r\r\nb\r").as_ref(), "a\r\nb\r");
    assert_ne!(decode_oracle_transport("a\r\nb\r\n").as_ref(), "b\na\n");
    assert_ne!(decode_oracle_transport(lf).as_ref(), lf.trim());
    assert_ne!(
        decode_oracle_transport(lf).as_ref(),
        lf.replace("line 2", "line 3")
    );
    assert_ne!(
        decode_oracle_transport(lf).as_ref(),
        lf.replace("a  message", "a message")
    );
}
fn render(rows: &[Produced]) -> String {
    use dm_analysis::check_policy::DiagnosticSeverity as S;
    let mut out = String::new();
    for row in rows {
        let severity = match row.severity {
            S::Error => "error",
            S::Warning => "warning",
            S::Info => "info",
            S::Hint => "hint",
        };
        out.push_str(&format!(
            "@FIXTURE@, line {}, column {}:\n{severity}: {}\n",
            row.origin.line, row.origin.byte_column, row.diagnostic.message
        ));
        for note in &row.diagnostic.notes {
            let p = note
                .source
                .as_ref()
                .expect("all independently audited notes carry actual source");
            if p.line == 0 && p.byte_column == 0 && p.path.as_os_str() == "(unknown)" {
                out.push_str(&format!("- (unknown):0:0: {}\n", note.message));
            } else {
                out.push_str(&format!(
                    "- {}:{}: {}\n",
                    p.line, p.byte_column, note.message
                ));
            }
        }
        out.push('\n');
    }
    out
}
#[test]
fn original_walker_same_database_matches_all_pinned_purity_rows_and_order() {
    macro_rules! case {
        ($name:literal) => {
            (
                include_str!(concat!(
                    "../../../fixtures/unified_checks/purity/",
                    $name,
                    "/probe.dme"
                )),
                include_str!(concat!(
                    "../../../fixtures/unified_checks/purity/",
                    $name,
                    "/reference.stderr"
                )),
                $name,
            )
        };
    }
    for (source, expected, name) in [
        case!("parameter"),
        case!("local-literal"),
        case!("local-alias"),
        case!("overload"),
        case!("no-overload"),
        case!("cycle"),
        case!("spawn"),
        case!("pure-discard"),
        case!("qualified-field"),
        case!("override"),
        case!("global-source"),
        case!("verb"),
    ] {
        let (snapshot, reads) = fixture(source, None);
        let db = snapshot.native_raw_queries.as_ref().unwrap();
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        let owner = dm_ir::Resolver::source_owner(snapshot.tree.as_ref());
        let rows = snapshot
            .native_purity_report(&input, &env(), None, &snapshot.tree)
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(
            render(&rows),
            decode_oracle_transport(expected).as_ref(),
            "{name}: preserve every old finding/note and order"
        );
        let counts = (17..=21)
            .map(|k| db.db().stats(dm_query::Kind(k)).computed)
            .collect::<Vec<_>>();
        let syntax = db.db().stats(dm_query::Kind(4)).computed;
        let io = reads.load(Ordering::Relaxed);
        let again = snapshot
            .native_purity_report(&input, &env(), None, &snapshot.tree)
            .unwrap();
        assert!(
            Arc::ptr_eq(&rows, &again),
            "warm query reuses exact result owner"
        );
        assert_eq!(
            io,
            reads.load(Ordering::Relaxed),
            "warm query performs no provider IO"
        );
        assert_eq!(syntax, db.db().stats(dm_query::Kind(4)).computed);
        assert_eq!(
            counts,
            (17..=21)
                .map(|k| db.db().stats(dm_query::Kind(k)).computed)
                .collect::<Vec<_>>()
        );
        assert_eq!(owner, dm_ir::Resolver::source_owner(snapshot.tree.as_ref()));
    }
}
#[test]
fn foreign_archive_and_unissued_or_changed_policy_refuse_before_any_cached_job() {
    let source = include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme");
    let (mut a, _) = fixture(source, None);
    let (b, _) = fixture(source, None);
    let input = a.native_purity_input(&a.tree).unwrap();
    a.native_purity_report(&input, &env(), None, &a.tree)
        .unwrap();
    let db = a.native_raw_queries.as_ref().unwrap().clone();
    let count = db.db().stats(dm_query::Kind(20)).computed;
    assert!(b
        .native_purity_report(&input, &env(), None, &b.tree)
        .is_err());
    let old = a.policy_revision;
    a.policy_revision = None;
    assert!(a
        .native_purity_report(&input, &env(), None, &a.tree)
        .is_err());
    a.policy_revision = old.map(|p| p ^ 1);
    assert!(a
        .native_purity_report(&input, &env(), None, &a.tree)
        .is_err());
    a.policy_revision = old;
    assert!(a
        .native_purity_report(
            &input,
            &env(),
            Some(&env().with_file_name("uncaptured.toml")),
            &a.tree
        )
        .is_err());
    assert_eq!(count, db.db().stats(dm_query::Kind(20)).computed);
    let weak = Arc::downgrade(&input);
    drop(input);
    assert!(
        weak.upgrade().is_none(),
        "cached effects keep no strong input/archive wrapper owner"
    );
    dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());
}
#[test]
fn unsupported_effect_contexts_are_not_clean_reports() {
    let (snapshot, _) = fixture("/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    CRASH(\"bad\")\n", None);
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let error = snapshot.native_purity_report(&input, &env(), None, &snapshot.tree).unwrap_err();
    assert!(error.to_string().contains("effect"), "{error}");
}
#[test]
fn multiple_effect_targets_with_no_violations_are_valid_shared_plan_reports() {
    let source="/proc/a()\n    set SpacemanDMM_should_be_pure=1\n    return 1\n/proc/b()\n    set SpacemanDMM_should_be_pure=1\n    return 2\n";
    let(snapshot,reads)=fixture(source,None);let input=snapshot.native_purity_input(&snapshot.tree).unwrap();
    let first=snapshot.native_purity_report(&input,&env(),None,&snapshot.tree).unwrap();
    assert!(first.is_empty());let before=reads.load(Ordering::Relaxed);
    let warm=snapshot.native_purity_report(&input,&env(),None,&snapshot.tree).unwrap();
    assert!(Arc::ptr_eq(&first,&warm));assert_eq!(reads.load(Ordering::Relaxed),before);
}

#[test]
fn evicted_values_keep_immutable_params_bounded_and_held_report_storage_charged() {
    let source = include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme");
    let (snapshot, _) = fixture(source, None);
    let db = snapshot.native_raw_queries.as_ref().unwrap().clone();
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let rows = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap();
    let cached = db.purity_cache_probe();
    assert!(cached.0 > 0 && cached.1 > 0 && cached.2 > 0);
    db.db()
        .evict_values(&(17..=21).map(dm_query::Kind).collect::<Vec<_>>());
    let evicted = db.purity_cache_probe();
    assert_eq!(
        evicted.0, cached.0,
        "immutable query Params survive derived eviction"
    );
    assert!(
        evicted.1 > 0 && evicted.2 > 0,
        "held report retains its real allocations after cache eviction"
    );
    drop(input);
    dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());
    let held = db.purity_cache_probe();
    assert_eq!(held.0, 0);
    assert!(
        held.2 > 0,
        "dead input pruning cannot release a still-held report's charge"
    );
    assert!(
        held.2 >= dm_analysis::checker_effects::report_capacity_bound(&rows),
        "still-held original output retains its full exposed capacity admission"
    );
    let mut census = crate::heap_census::HeapCensus::new("purity.held-report");
    db.purity_census(&mut census);
    let measured = census.finish();
    let buffer = measured
        .owners
        .iter()
        .find(|o| o.owner == "purity.report_rows")
        .unwrap();
    assert_eq!(
        buffer.unique_known_capacity_bytes,
        rows.capacity()
            .saturating_mul(std::mem::size_of::<Produced>()) as u64
    );
    assert!(measured
        .owners
        .iter()
        .any(|o| o.owner == "purity.query_graph_bookkeeping" && !o.unknown.is_empty()));
    drop(rows);
    dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());
    assert_eq!(db.purity_cache_probe().2, 0);
}
#[test]
fn cached_refusal_strings_have_real_capacity_census_and_eviction_keeps_metadata() {
    let (snapshot, _) = fixture(
        "/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    CRASH(\"bad\")\n",
        None,
    );
    let db = snapshot.native_raw_queries.as_ref().unwrap();
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    assert!(snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .is_err());
    let mut census = crate::heap_census::HeapCensus::new("purity.errors");
    db.purity_census(&mut census);
    let found = census.finish();
    let error = found
        .owners
        .iter()
        .find(|o| o.owner == "purity.cached_error_text")
        .expect("actual cached String allocation, no nominal 1024-byte error fallback");
    assert!(
        error.unique_known_capacity_bytes >= error.unique_payload_bytes
            && error.unique_payload_bytes > 0
    );
    let before = db.purity_cache_probe();
    db.db()
        .evict_values(&(17..=21).map(dm_query::Kind).collect::<Vec<_>>());
    let after = db.purity_cache_probe();
    assert_eq!(before.0, after.0);
    assert!(after.1 > 0);
    assert_eq!(after.2, 0);
}
#[test]
fn impure_parent_and_self_calls_cannot_discard_deferred_effect_contexts() {
    for source in ["/datum/base\n    var/value=0\n    proc/probe()\n        value=1\n/datum/base/child/probe()\n    ..()\n/proc/check(datum/base/child/B)\n    set SpacemanDMM_should_be_pure=1\n    B.probe()\n","var/global_value=0\n/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    global_value=1\n    .()\n"]{let(snapshot,_)=fixture(source,None);let input=snapshot.native_purity_input(&snapshot.tree).unwrap();let error=snapshot.native_purity_report(&input,&env(),None,&snapshot.tree).unwrap_err();assert!(error.to_string().contains("parent")||error.to_string().contains("self"),"{error}");}
}

#[test]
fn shared_effect_plan_preserves_all_pinned_sleep_rows_and_visited_before_skip() {
    macro_rules! sleep_case {
        ($name:literal) => {
            (
                include_str!(concat!(
                    "../../../fixtures/unified_checks/sleep/",
                    $name,
                    "/probe.dme"
                )),
                include_str!(concat!(
                    "../../../fixtures/unified_checks/sleep/",
                    $name,
                    "/reference.stderr"
                )),
                $name,
            )
        };
    }
    for (source, expected, name) in [
        sleep_case!("direct"),
        sleep_case!("transitive"),
        sleep_case!("waitfor"),
        sleep_case!("own-waitfor"),
        sleep_case!("exempt"),
        sleep_case!("spawn-direct"),
        sleep_case!("spawn-first"),
        sleep_case!("plain-first"),
        sleep_case!("override"),
        sleep_case!("cycle"),
        sleep_case!("global-sleep"),
        sleep_case!("return-anchor"),
        sleep_case!("initializer-anchor"),
        sleep_case!("constructor-sleep"),
    ] {
        let (snapshot, reads) = fixture(source, None);
        let db = snapshot.native_raw_queries.as_ref().unwrap();
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        // Purity and sleep must share exact original BodyEffects/EffectPlan jobs.
        snapshot
            .native_purity_report(&input, &env(), None, &snapshot.tree)
            .unwrap();
        let before = (
            db.db().stats(dm_query::Kind(17)).computed,
            db.db().stats(dm_query::Kind(18)).computed,
        );
        let rows = snapshot
            .native_sleep_report(&input, &env(), None, &snapshot.tree)
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(
            render(&rows),
            decode_oracle_transport(expected).as_ref(),
            "{name}: independent original checker transcript"
        );
        assert_eq!(
            before,
            (
                db.db().stats(dm_query::Kind(17)).computed,
                db.db().stats(dm_query::Kind(18)).computed
            ),
            "sleep must NOT produce another effect/call graph"
        );
        let io = reads.load(Ordering::Relaxed);
        let parsed = db.db().stats(dm_query::Kind(4)).computed;
        let again = snapshot
            .native_sleep_report(&input, &env(), None, &snapshot.tree)
            .unwrap();
        assert!(Arc::ptr_eq(&rows, &again));
        assert_eq!(io, reads.load(Ordering::Relaxed));
        assert_eq!(parsed, db.db().stats(dm_query::Kind(4)).computed);
    }
}

#[test]
fn sleep_policy_captured_config_and_foreign_frames_gate_before_warm_cache() {
    let source = include_str!("../../../fixtures/unified_checks/sleep/direct/probe.dme");
    let (mut a, _) = fixture(source, None);
    let (b, _) = fixture(source, None);
    let input = a.native_purity_input(&a.tree).unwrap();
    assert_eq!(
        a.native_sleep_report(&input, &env(), None, &a.tree)
            .unwrap()
            .len(),
        1
    );
    let db = a.native_raw_queries.as_ref().unwrap().clone();
    let before = db.db().stats(dm_query::Kind(22)).computed;
    assert!(b
        .native_sleep_report(&input, &env(), None, &b.tree)
        .is_err());
    let pin = a.policy_revision;
    a.policy_revision = None;
    assert!(a
        .native_sleep_report(&input, &env(), None, &a.tree)
        .is_err());
    a.policy_revision = pin.map(|p| p ^ 1);
    assert!(a
        .native_sleep_report(&input, &env(), None, &a.tree)
        .is_err());
    a.policy_revision = pin;
    assert!(a
        .native_sleep_report(
            &input,
            &env(),
            Some(&env().with_file_name("uncaptured.toml")),
            &a.tree
        )
        .is_err());
    assert_eq!(before, db.db().stats(dm_query::Kind(22)).computed);
    let (disabled, _) = fixture(source, Some(b"[diagnostics]\nmust_not_sleep='off'\n"));
    let input = disabled.native_purity_input(&disabled.tree).unwrap();
    assert!(disabled
        .native_sleep_report(&input, &env(), None, &disabled.tree)
        .unwrap()
        .is_empty());
}

#[test]
fn builtin_and_input_effects_match_original_whole_fixture_transcripts() {
    macro_rules! case {
        ($name:literal,$sleep:literal) => {
            (
                include_str!(concat!(
                    "../../../fixtures/unified_checks/builtin_effects/",
                    $name,
                    "/probe.dme"
                )),
                include_str!(concat!(
                    "../../../fixtures/unified_checks/builtin_effects/",
                    $name,
                    "/reference.stderr"
                )),
                $sleep,
                $name,
            )
        };
    }
    for (source, expected, sleep, name) in [
        case!("input-direct", true),
        case!("input-return", true),
        case!("input-list", true),
        case!("input-spawn", true),
        case!("input-pure", false),
        case!("builtin-pure", false),
        case!("builtin-inherited-pure-discard", false),
        case!("group-return", false),
        case!("group-call", false),
        case!("group-locate-shift", false),
        case!("client-blocker", true),
        case!("world-blocker", true),
        case!("client-override-pure", false),
        case!("world-override-pure", false),
        case!("client-override-sleep", true),
        case!("near-builtin", false),
        case!("source-behind-builtin", false),
        case!("far-source-near-builtin", false),
    ] {
        let (snapshot, reads) = fixture(source, None);
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        let db = snapshot.native_raw_queries.as_ref().unwrap();
        let rows = if sleep {
            snapshot.native_sleep_report(&input, &env(), None, &snapshot.tree)
        } else {
            snapshot.native_purity_report(&input, &env(), None, &snapshot.tree)
        }
        .unwrap_or_else(|e| panic!("{name}: {e}"));
        assert_eq!(
            render(&rows),
            decode_oracle_transport(expected).as_ref(),
            "{name}: entire original executable transcript"
        );
        let before = reads.load(Ordering::Relaxed);
        let parsed = db.db().stats(dm_query::Kind(4)).computed;
        let again = if sleep {
            snapshot.native_sleep_report(&input, &env(), None, &snapshot.tree)
        } else {
            snapshot.native_purity_report(&input, &env(), None, &snapshot.tree)
        }
        .unwrap();
        assert!(Arc::ptr_eq(&rows, &again));
        assert_eq!(before, reads.load(Ordering::Relaxed));
        assert_eq!(parsed, db.db().stats(dm_query::Kind(4)).computed);
    }
}

#[test]
fn original_builtin_parent_boundary_has_exact_native_target_and_old_rows() {
    let (snapshot, _) = fixture(
        include_str!("../../../fixtures/unified_checks/purity/builtin-root/probe.dme"),
        None,
    );
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let rows = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap();
    assert_eq!(
        render(&rows),
        decode_oracle_transport(include_str!(
            "../../../fixtures/unified_checks/purity/builtin-root/reference.stderr"
        ))
        .as_ref()
    );
}

#[path = "runner_query_purity_failed_candidate_tests.rs"]
mod failed_candidate;

#[path = "runner_query_effect_cancellation_tests.rs"]
mod cancellation_tests;

#[test]
fn actual_original_long_call_trace_is_pre_admitted_and_never_caches_budget_failure_as_semantics() {
    // Resource-admission regression, not a fabricated semantic fact/expected row.
    // <2 MiB of real primary source can request >64 MiB of repeated trace text.
    let names = (0..96)
        .map(|i| format!("helper_{i}_{}", "x".repeat(8192)))
        .collect::<Vec<_>>();
    let mut source =
        String::from("var/global_value=0\n/proc/check()\n    set SpacemanDMM_should_be_pure=1\n");
    source.push_str(&format!("    {}()\n", names[0]));
    for (i, name) in names.iter().enumerate() {
        source.push_str(&format!("/proc/{name}()\n    global_value=1\n"));
        if let Some(next) = names.get(i + 1) {
            source.push_str(&format!("    {next}()\n"))
        }
    }
    assert!(source.len() < 2 * 1024 * 1024);
    let (snapshot, reads) = fixture(&source, None);
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let db = snapshot.native_raw_queries.as_ref().unwrap();
    let owner = dm_ir::Resolver::source_owner(snapshot.tree.as_ref());
    let before = reads.load(Ordering::Relaxed);
    let error = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap_err();
    assert!(error.to_string().contains("budget"), "{error}");
    assert_eq!(
        db.effect_retained_values_for_test(dm_query::Kind(20)),
        0,
        "budget denial must not publish even a cached String refusal"
    );
    assert_eq!(before, reads.load(Ordering::Relaxed));
    assert_eq!(owner, dm_ir::Resolver::source_owner(snapshot.tree.as_ref()));
}

#[test]
fn owner_local_original_index_preserves_exact_duplicate_display_chronology_and_old_rows() {
    let (snapshot, _) = fixture(
        include_str!("../../../fixtures/unified_checks/purity/owner-index-chronology/probe.dme"),
        None,
    );
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let rows = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap();
    assert_eq!(
        render(&rows),
        decode_oracle_transport(include_str!(
            "../../../fixtures/unified_checks/purity/owner-index-chronology/reference.stderr"
        ))
        .as_ref()
    );
}

#[path = "runner_query_effect_walker_admission_tests.rs"]
mod walker_admission_tests;

#[path = "runner_query_parameter_source_tests.rs"]
mod parameter_source_tests;

#[test]
fn original_array_constructor_and_dimension_effect_origins_match_complete_old_transcripts() {
    for (source, reference) in [
        (include_str!("../../../fixtures/unified_checks/arrays/pure_constructor_origin/probe.dme"), include_str!("../../../fixtures/unified_checks/arrays/pure_constructor_origin/reference.stderr")),
        (include_str!("../../../fixtures/unified_checks/arrays/dimension_mob_binary_origin/probe.dme"), include_str!("../../../fixtures/unified_checks/arrays/dimension_mob_binary_origin/reference.stderr")),
        (include_str!("../../../fixtures/unified_checks/arrays/dimension_mob_group_origin/probe.dme"), include_str!("../../../fixtures/unified_checks/arrays/dimension_mob_group_origin/reference.stderr")),
    ] {
        let (snapshot, reads) = fixture(source, None);
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        let queries = snapshot.native_raw_queries.as_ref().unwrap();
        let first = snapshot.native_purity_report(&input, &env(), None, &snapshot.tree).unwrap();
        assert_eq!(render(&first), decode_oracle_transport(reference).as_ref(), "preserve actual synthetic0:0 versus physical group location");
        let parsed = queries.db().stats(dm_query::Kind(4)).computed;
        let io = reads.load(Ordering::Relaxed);
        let second = snapshot.native_purity_report(&input, &env(), None, &snapshot.tree).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        assert_eq!(queries.db().stats(dm_query::Kind(4)).computed, parsed);
        assert_eq!(reads.load(Ordering::Relaxed), io);
    }
}

#[test]
fn typed_body_query_failure_never_becomes_effect_refusal_and_same_input_recovers() {
    // Actual frontend/Walker/report jobs, including a source callee's prefix
    // settings read through Observed. Only the Kind4 IO event is scheduled.
    let source="/proc/check()\n    set SpacemanDMM_should_be_pure=1\n    helper()\n/proc/helper()\n    return 1\n";
    for sleeping in [false, true] {
        for completed in [0, 1] {
            let (snapshot, reads) = fixture(source, None);
            let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
            let queries = snapshot.native_raw_queries.as_ref().unwrap();
            let owner = dm_ir::Resolver::source_owner(snapshot.tree.as_ref());
            let io = reads.load(Ordering::Relaxed);
            let original = std::io::Error::from_raw_os_error(1450);
            let kind = original.kind();
            let schedule = queries.fail_body_syntax_after_for_test(completed, original);
            let result = if sleeping {
                snapshot.native_sleep_report(&input, &env(), None, &snapshot.tree)
            } else {
                snapshot.native_purity_report(&input, &env(), None, &snapshot.tree)
            };
            let error = result.unwrap_err();
            assert_eq!(error.kind(), kind);
            assert_eq!(
                error.raw_os_error(),
                Some(1450),
                "retain actual OS error, not a formatted graph String"
            );
            for k in [18, 19, 20, 22] {
                assert_eq!(
                    queries.effect_retained_values_for_test(dm_query::Kind(k)),
                    0,
                    "no plan/SCC/report semantic error Outcome"
                );
            }
            assert_eq!(reads.load(Ordering::Relaxed), io);
            drop(schedule);
            let recovered = if sleeping {
                snapshot.native_sleep_report(&input, &env(), None, &snapshot.tree)
            } else {
                snapshot.native_purity_report(&input, &env(), None, &snapshot.tree)
            }
            .unwrap();
            assert!(recovered.is_empty());
            assert_eq!(reads.load(Ordering::Relaxed), io);
            assert_eq!(dm_ir::Resolver::source_owner(snapshot.tree.as_ref()), owner);
        }
    }
}

#[test]
fn native_checked_archive_keeps_actual_operational_io_and_retries_original_input() {
    let (snapshot, reads) = fixture("/proc/probe()\n    return 1\n", None);
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let queries = snapshot.native_raw_queries.as_ref().unwrap();
    let archive = input.archive();
    let ordinal = input.order()[0].0;
    let io = reads.load(Ordering::Relaxed);
    let schedule = queries.fail_body_syntax_after_for_test(
        0,
        std::io::Error::new(
            std::io::ErrorKind::OutOfMemory,
            "actual native syntax admission",
        ),
    );
    let error = archive
        .parse_checked(ordinal)
        .err()
        .expect("scheduled native IO error");
    match error {
        dm_tree::frontend::BodySyntaxFailure::Operational(error) => {
            assert_eq!(error.kind(), std::io::ErrorKind::OutOfMemory);
            assert_eq!(error.to_string(), "actual native syntax admission");
        }
        dm_tree::frontend::BodySyntaxFailure::Syntax(error) => {
            panic!("operational error became cached diagnostic: {error:?}")
        }
    }
    assert_eq!(queries.db().stats(dm_query::Kind(4)).computed, 0);
    drop(schedule);
    let parsed = archive.parse_checked(ordinal).unwrap();
    let again = archive.parse_checked(ordinal).unwrap();
    assert_eq!(
        parsed.occurrence().expanded_span,
        again.occurrence().expanded_span
    );
    assert_eq!(queries.db().stats(dm_query::Kind(4)).computed, 1);
    assert_eq!(reads.load(Ordering::Relaxed), io);
}

#[test]
fn checked_body_outer_graph_failure_is_not_a_parser_rejection_or_cached_syntax() {
    let (snapshot, reads) = fixture("/proc/probe()\n    return 1\n", None);
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let queries = snapshot.native_raw_queries.as_ref().unwrap();
    let archive = input.archive();
    let ordinal = input.order()[0].0;
    let io = reads.load(Ordering::Relaxed);
    let schedule = queries.fail_body_graph_once_for_test();
    match archive
        .parse_checked(ordinal)
        .err()
        .expect("scheduled infrastructure failure")
    {
        dm_tree::frontend::BodySyntaxFailure::Operational(error) => {
            assert_eq!(error.kind(), std::io::ErrorKind::Other);
            assert!(error.get_ref().is_some(), "retain actual graph error owner");
        }
        dm_tree::frontend::BodySyntaxFailure::Syntax(error) => {
            panic!("graph failure became parser meaning: {error:?}")
        }
    }
    assert_eq!(queries.db().stats(dm_query::Kind(4)).computed, 0);
    drop(schedule);
    let schedule = queries.fail_body_graph_once_for_test();
    let compatibility = archive
        .parse(ordinal)
        .err()
        .expect("legacy graph diagnostic");
    assert_eq!(
        compatibility.kind,
        dm_tree::frontend::DiagnosticKind::Internal
    );
    drop(schedule);
    assert!(archive.parse_checked(ordinal).is_ok());
    assert_eq!(queries.db().stats(dm_query::Kind(4)).computed, 1);
    assert_eq!(reads.load(Ordering::Relaxed), io);
}

#[test]
fn public_body_model_and_checker_keep_actual_demand_io_without_partial_output() {
    for checker in [false, true] {
        let (snapshot, reads) = fixture("/proc/probe()\n    return 1\n", None);
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        let queries = snapshot.native_raw_queries.as_ref().unwrap();
        let ordinal = input.order()[0].0 as u32;
        let io = reads.load(Ordering::Relaxed);
        let schedule = queries.fail_body_syntax_after_for_test(
            0,
            std::io::Error::new(std::io::ErrorKind::OutOfMemory, "actual public body demand"),
        );
        let mut bytes = Vec::new();
        let result = if checker {
            snapshot.write_native_checker(ordinal, "warning", &snapshot.tree, &mut bytes)
        } else {
            snapshot.write_body_model(ordinal, &snapshot.tree, &mut bytes)
        };
        let error = result.unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::OutOfMemory);
        assert_eq!(error.to_string(), "actual public body demand");
        assert!(
            bytes.is_empty(),
            "body failure precedes any completed public row"
        );
        assert_eq!(queries.db().stats(dm_query::Kind(4)).computed, 0);
        drop(schedule);
        if checker {
            snapshot.write_native_checker(ordinal, "warning", &snapshot.tree, &mut bytes)
        } else {
            snapshot.write_body_model(ordinal, &snapshot.tree, &mut bytes)
        }
        .unwrap();
        let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(
            row["row"],
            if checker {
                "source_native_checker_fixture"
            } else {
                "source_body_model"
            }
        );
        assert_eq!(reads.load(Ordering::Relaxed), io);
    }
}

#[test]
fn warmed_effect_reports_redemand_original_kind4_without_caching_actual_io() {
    for sleeping in [false, true] {
        let source = if sleeping {
            "/proc/check()\n    set SpacemanDMM_should_not_sleep=1\n    sleep(1)\n"
        } else {
            "/proc/check(value)\n    set SpacemanDMM_should_be_pure=1\n    value=1\n"
        };
        let (snapshot, reads) = fixture(source, None);
        let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
        let queries = snapshot.native_raw_queries.as_ref().unwrap();
        let report = || {
            if sleeping {
                snapshot.native_sleep_report(&input, &env(), None, &snapshot.tree)
            } else {
                snapshot.native_purity_report(&input, &env(), None, &snapshot.tree)
            }
        };
        let expected = report().unwrap();
        assert!(
            !expected.is_empty(),
            "actual original target demands callable note/header"
        );
        let original_reads = reads.load(Ordering::Relaxed);
        let bodies = queries.db().stats(dm_query::Kind(17)).computed;
        let plans = queries.db().stats(dm_query::Kind(18)).computed;
        assert!(
            queries
                .db()
                .evict_values(&[dm_query::Kind(4), dm_query::Kind(20), dm_query::Kind(22)])
                > 0
        );
        let schedule =
            queries.fail_body_syntax_after_for_test(0, std::io::Error::from_raw_os_error(1450));
        let error = report()
            .err()
            .expect("real report-time original body demand");
        assert_eq!(error.raw_os_error(), Some(1450));
        assert_eq!(
            queries.effect_retained_values_for_test(dm_query::Kind(if sleeping { 22 } else { 20 })),
            0,
            "no operational report rejection Outcome"
        );
        assert_eq!(queries.db().stats(dm_query::Kind(17)).computed, bodies);
        assert_eq!(queries.db().stats(dm_query::Kind(18)).computed, plans);
        drop(schedule);
        let recovered = report().unwrap();
        assert_eq!(render(&recovered), render(&expected));
        assert!(Arc::ptr_eq(&recovered, &report().unwrap()));
        assert_eq!(
            reads.load(Ordering::Relaxed),
            original_reads,
            "no request filesystem re-read"
        );
    }
}
#[test]
fn callable_note_transport_requires_exact_selected_original_occurrence() {
    let (snapshot, _) = fixture(
        "/proc/first()\n    return 1\n/proc/second()\n    return 2\n",
        None,
    );
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    assert_eq!(input.order().len(), 2);
    let archive = input.archive();
    let (ordinal, identity) = input.order()[0];
    let other = input.order()[1].0;
    assert_ne!(ordinal, other);
    let error = archive
        .callable_note_origin_with(identity, |archive, _| {
            archive.parse(other).map_err(|e| e.message)
        })
        .err()
        .expect("same archive but wrong original occurrence must refuse");
    assert_eq!(error, "callable note primary source unavailable");
    let expected = archive.callable_note_origin(identity).unwrap();
    let actual = archive
        .callable_note_origin_with(identity, |archive, i| {
            archive.parse_checked(i).map_err(|e| match e {
                dm_tree::frontend::BodySyntaxFailure::Syntax(e) => {
                    dm_analysis::policy_body_demand::PolicyFailure::from(e.message)
                }
                dm_tree::frontend::BodySyntaxFailure::Operational(e) => {
                    dm_analysis::policy_body_demand::PolicyFailure::Operational(e)
                }
            })
        })
        .unwrap();
    assert_eq!(expected.path, actual.path);
    assert_eq!(
        (expected.line, expected.byte_column),
        (actual.line, actual.byte_column)
    );
}

#[path = "runner_query_effect_multi_target_tests.rs"]
mod multi_target_tests;


type EffectPageRow=(bool,Option<dm_ir::ProcedureIdentity>,Vec<(dm_ir::ProcedureIdentity,bool,bool)>);
fn effect_page_row(row:dm_analysis::checker_effects::EffectContribution<'_>)->(dm_ir::ProcedureIdentity,EffectPageRow){
    let mut calls=Vec::new();row.visit_source_calls(|id,exact,new_context|calls.push((id,exact,new_context)));(row.procedure(),(row.has_direct_effect(),row.source_parent(),calls))
}
fn collect_effect_pages(snapshot:&SourceSnapshot,width:usize)->BTreeMap<dm_ir::ProcedureIdentity,EffectPageRow>{
    use dm_analysis::checker_effects::{EffectSource,ExecutionAdmission};
    let archive=snapshot.body_archive.as_ref().unwrap();let host=archive.body_query_host().unwrap();let profile=archive.tree().checker_builtin_profile().unwrap();let source=EffectSource::new(archive,profile).unwrap();source.validate_current(archive,host).unwrap();
    let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>,_:&dm_analysis::checker_effects::ExecutionAdmission|host.syntax_checked(input);let mut rows=BTreeMap::new();let mut offset=0;
    source.for_each_page_checked(width,archive.tree(),&ExecutionAdmission::default(),&mut crate::daemon::control::checkpoint,&body,|page|{
        assert_eq!(page.start(),offset);assert_eq!(page.total(),source.len());assert!(page.len()<=width);assert!(page.events()<=dm_analysis::checker_effects::MAX_EVENTS);
        for i in 0..page.len(){let row=page.contribution(i)?.unwrap();assert_eq!(source.original_ordinal(offset+i),Some(row.ordinal()));let(id,facts)=effect_page_row(row);assert!(rows.insert(id,facts).is_none());}offset+=page.len();Ok(())
    }).unwrap();assert_eq!(offset,source.len());rows
}
#[test]
fn effect_source_pages_preserve_cross_page_cycle_and_override_facts_from_same_original_bodies(){
    for source in [include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),include_str!("../../../fixtures/unified_checks/purity/override/probe.dme")]{
        let(snapshot,_)=fixture(source,None);let archive=snapshot.body_archive.as_ref().unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let reads_before=db.db().stats(dm_query::Kind(4)).computed;
        let profile=archive.tree().checker_builtin_profile().unwrap();let input=EffectInput::new(Arc::clone(archive),profile).unwrap();let mut expected=BTreeMap::new();
        for &(ordinal,_) in input.order(){let body=input.compute_body_checked(ordinal,archive.tree(),&dm_analysis::checker_effects::ExecutionAdmission::default()).unwrap();let(id,row)=effect_page_row(body.source_contribution());expected.insert(id,row);}
        let computed=db.db().stats(dm_query::Kind(4)).computed;assert!(computed>reads_before);
        assert_eq!(collect_effect_pages(&snapshot,1),expected,"global IDs must not be restricted to an independent page graph");assert_eq!(collect_effect_pages(&snapshot,2),expected);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,computed,"actual canonical body queries stay warm across source windows");
        let named=|name:&str|expected.keys().copied().find(|id|id.name==dm_ir::SymbolId::of(name)).unwrap();
        if source.contains("global_value") {let a=named("a");let b=named("b");assert!(expected[&a].2.iter().any(|call|call.0==b));assert!(expected[&b].2.iter().any(|call|call.0==a));assert!(expected[&b].0,"actual direct effect in another page");}
        else{assert!(expected.iter().any(|(id,row)|id.owner==dm_ir::SymbolId::of("/datum/base/child")&&row.0&&row.1.is_some_and(|parent|parent.owner==dm_ir::SymbolId::of("/datum/base"))),"actual direct override links to original predecessor outside its page");}
    }
}
#[test]
fn effect_source_pages_retract_on_body_edit_and_refuse_foreign_current_frame(){
    use dm_analysis::checker_effects::EffectSource;
    let source=include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme");let(first,_)=fixture(source,None);let edited=source.replace("global_value=1","global_value");let(current,_)=fixture(&edited,None);
    let old=collect_effect_pages(&first,1);let new=collect_effect_pages(&current,1);let b=old.keys().copied().find(|id|id.name==dm_ir::SymbolId::of("b")).unwrap();assert!(old[&b].0);assert!(!new[&b].0,"source-global effect disappears after actual RHS/write removal");assert_eq!(old[&b].2,new[&b].2,"cross-page recursion remains intact");
    let old_archive=first.body_archive.as_ref().unwrap();let fresh=current.body_archive.as_ref().unwrap();let view=EffectSource::new(old_archive,old_archive.tree().checker_builtin_profile().unwrap()).unwrap();assert!(view.validate_current(fresh,fresh.body_query_host().unwrap()).is_err());
}
#[test]
fn effect_source_page_actual_kind4_stop_retains_completed_pure_work_and_retries_without_output_claim(){
    use dm_analysis::checker_effects::{EffectSource,ExecutionAdmission};
    use dm_analysis::policy_body_demand::PolicyFailure;
    let(snapshot,_)=fixture(&format!("/proc/completed_leaf()\n    return 1\n{}",include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme")),None);let archive=snapshot.body_archive.as_ref().unwrap();let host=archive.body_query_host().unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let source=EffectSource::new(archive,archive.tree().checker_builtin_profile().unwrap()).unwrap();let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>,_:&dm_analysis::checker_effects::ExecutionAdmission|host.syntax_checked(input);
    let schedule=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));let mut completed=0;let result=source.for_each_page_checked(1,archive.tree(),&ExecutionAdmission::default(),&mut crate::daemon::control::checkpoint,&body,|_|{completed+=1;Ok(())});assert!(matches!(&result,Err(PolicyFailure::Operational(error))if error.raw_os_error()==Some(1450)),"actual original Kind4 failure: {result:?}; completed={completed}");assert_eq!(completed,1,"a valid earlier contribution may complete, but not the aggregate request");drop(schedule);
    let before=db.db().stats(dm_query::Kind(4)).computed;let rows=collect_effect_pages(&snapshot,1);assert_eq!(rows.len(),source.len());assert_eq!(db.db().stats(dm_query::Kind(4)).computed-before,(source.len()-1) as u64);
    let denied=ExecutionAdmission::with_limit(1);assert!(matches!(source.for_each_page_checked(1,archive.tree(),&denied,&mut crate::daemon::control::checkpoint,&body,|_|Ok(())),Err(PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));assert!(denied.is_denied());assert_eq!(collect_effect_pages(&snapshot,1),rows);
}

#[test]
fn actual_effect_source_pages_join_one_global_scc_and_retract_effects_without_losing_cross_page_cycles(){
    use dm_analysis::checker_effects::{CompactEffectScc,ExecutionAdmission};
    let source=include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme");let(first,_)=fixture(source,None);let(after,_)=fixture(&source.replace("global_value=1","global_value"),None);
    for(snapshot,expect_effect)in[(&first,true),(&after,false)]{
        let facts=collect_effect_pages(snapshot,1);let ids=facts.keys().copied().collect::<Vec<_>>();let index=ids.iter().copied().enumerate().map(|(i,id)|(id,i)).collect::<BTreeMap<_,_>>();
        let edges=ids.iter().map(|id|facts[id].2.iter().map(|(to,_,_)|index[to]).collect::<Vec<_>>()).collect::<Vec<_>>();let scc=CompactEffectScc::compute_checked(ids.len(),&ExecutionAdmission::default(),|node,next,_|Ok(edges[node].get(next).copied()),&mut||Ok(())).unwrap();let summary=scc.summarize_checked(&ExecutionAdmission::default(),|node,_|Ok(facts[&ids[node]].0),|node,next,_|Ok(edges[node].get(next).copied()),&mut||Ok(())).unwrap();
        let named=|name:&str|ids.iter().position(|id|id.name==dm_ir::SymbolId::of(name)).unwrap();assert_eq!(scc.same_component(named("a"),named("b")),Some(true),"cycle spans source windows but remains ONE component");for name in["a","b","probe"]{assert_eq!(summary.node_has_effect(named(name)),Some(expect_effect),"original graph propagation/retraction for {name}");}
    }
}

#[test]
fn effect_source_page_final_nested_denial_and_empty_failed_operation_cannot_return_success(){
    use dm_analysis::checker_effects::{CompactEffectScc,EffectSource,ExecutionAdmission};
    use dm_analysis::policy_body_demand::PolicyFailure;
    let(snapshot,_)=fixture("/proc/probe()\n    return 1\n",None);let archive=snapshot.body_archive.as_ref().unwrap();let host=archive.body_query_host().unwrap();let source=EffectSource::new(archive,archive.tree().checker_builtin_profile().unwrap()).unwrap();let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>,_:&dm_analysis::checker_effects::ExecutionAdmission|host.syntax_checked(input);let admission=ExecutionAdmission::default();let mut callbacks=0;
    let failed=source.for_each_page_checked(1,archive.tree(),&admission,&mut||Ok(()),&body,|_|{
        callbacks+=1;let denied=CompactEffectScc::compute_checked(1_000_000,&admission,|_,_,_|panic!("shared quota refuses before reading any edge"),&mut||Ok(()));assert!(matches!(denied,Err(PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));Ok(())
    });assert_eq!(callbacks,1);assert!(admission.is_denied());assert!(matches!(failed,Err(PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory),"nested quota failure cannot be swallowed by final page callback");
    let(empty,_)=fixture("/datum/probe\n    var/value=1\n",None);let empty_archive=empty.body_archive.as_ref().unwrap();let empty_source=EffectSource::new(empty_archive,empty_archive.tree().checker_builtin_profile().unwrap()).unwrap();assert!(empty_source.is_empty());let empty_host=empty_archive.body_query_host().unwrap();let empty_body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>,_:&dm_analysis::checker_effects::ExecutionAdmission|empty_host.syntax_checked(input);
    assert!(matches!(empty_source.for_each_page_checked(1,empty_archive.tree(),&admission,&mut||Ok(()),&empty_body,|_|panic!("no original callable")),Err(PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));
    source.for_each_page_checked(1,archive.tree(),&ExecutionAdmission::default(),&mut||Ok(()),&body,|_|Ok(())).unwrap();
}

#[test]
fn compact_effect_global_source_graph_matches_original_calls_overrides_and_retraction_across_pages(){
    use dm_analysis::checker_effects::{CompactEffectGraph,EffectSource,ExecutionAdmission};
    let duplicate_calls=format!("var/global_value\n/proc/fanout()\n{}/proc/leaf()\n    global_value=1\n","    leaf()\n".repeat(512));
    let reversed_calls="/proc/reversed()\n    zed()\n    alpha()\n/proc/alpha()\n    return 0\n/proc/zed()\n    return 0\n".to_owned();
    for text in[duplicate_calls,reversed_calls,include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme").to_owned(),include_str!("../../../fixtures/unified_checks/purity/override/probe.dme").to_owned(),include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme").replace("global_value=1","global_value")]{
        let(snapshot,_)=fixture(&text,None);let archive=snapshot.body_archive.as_ref().unwrap();let profile=archive.tree().checker_builtin_profile().unwrap();let host=archive.body_query_host().unwrap();let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>,_:&dm_analysis::checker_effects::ExecutionAdmission|host.syntax_checked(input);let source=EffectSource::new(archive,profile).unwrap();let input=EffectInput::new(Arc::clone(archive),profile).unwrap();let admission=ExecutionAdmission::default();
        let old_bodies=input.order().iter().map(|&(ordinal,_)|input.compute_body_checked(ordinal,archive.tree(),&admission).unwrap()).collect();let old_plan=input.plan(old_bodies,archive.tree(),&admission).unwrap();let old=old_plan.summarize(&input).unwrap();let before=snapshot.native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed;
        for width in[1,2]{let graph=CompactEffectGraph::build_checked(&source,width,archive.tree(),&ExecutionAdmission::default(),&mut||Ok(()),&body).unwrap();let scc=graph.compute_scc_checked(&ExecutionAdmission::default(),&mut||Ok(())).unwrap();let summary=graph.summarize_checked(&scc,&ExecutionAdmission::default(),&mut||Ok(())).unwrap();
            for node in 0..graph.len(){let mut successors=Vec::new();while let Some(to)=graph.successor(node,successors.len()).unwrap(){successors.push(to);}assert!(successors.windows(2).all(|pair|pair[0]<=pair[1]),"prior sorted successor order, including distinct reversed authored calls, is preserved");let ordinal=graph.original_ordinal(node).unwrap();let id=input.order().iter().find(|(actual,_)|*actual==ordinal).unwrap().1;if id.name==dm_ir::SymbolId::of("fanout"){let mut count=0;while graph.successor(node,count).unwrap().is_some(){count+=1;}assert_eq!(count,512,"count/fill preserves every original repeated call without growing pair storage");}assert_eq!(summary.node_has_effect(node),old.source_has_effect(id),"actual original global calls/override effect meaning at page width {width}");}
        }assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed,before,"global scalar graph retains no body owners and reuses actual warm Kind4");
    }
}
#[test]
fn compact_effect_global_source_graph_actual_body_io_and_quota_are_uncached_and_retryable(){
    use dm_analysis::checker_effects::{CompactEffectGraph,EffectSource,ExecutionAdmission};use dm_analysis::policy_body_demand::PolicyFailure;
    let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let archive=snapshot.body_archive.as_ref().unwrap();let source=EffectSource::new(archive,archive.tree().checker_builtin_profile().unwrap()).unwrap();let host=archive.body_query_host().unwrap();let body=|input:&Arc<dm_tree::frontend::BodySyntaxInput>,_:&dm_analysis::checker_effects::ExecutionAdmission|host.syntax_checked(input);let db=snapshot.native_raw_queries.as_ref().unwrap();let schedule=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));
    let failed=CompactEffectGraph::build_checked(&source,1,archive.tree(),&ExecutionAdmission::default(),&mut||Ok(()),&body).err().unwrap();assert!(matches!(&failed,PolicyFailure::Operational(actual)if actual.raw_os_error()==Some(1450)),"actual original graph body/prefix failure: {failed:?}");drop(schedule);
    let recovered=CompactEffectGraph::build_checked(&source,1,archive.tree(),&ExecutionAdmission::default(),&mut||Ok(()),&body).unwrap();assert_eq!(recovered.len(),source.len());let tiny=ExecutionAdmission::with_limit(1);assert!(matches!(CompactEffectGraph::build_checked(&source,1,archive.tree(),&tiny,&mut||Ok(()),&body),Err(PolicyFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));assert!(tiny.is_denied());assert_eq!(CompactEffectGraph::build_checked(&source,1,archive.tree(),&ExecutionAdmission::default(),&mut||Ok(()),&body).unwrap().len(),source.len());
}

#[test]
fn actual_effect_page_query_records_only_its_kind4_children_and_warm_source_frame(){
    use dm_analysis::checker_effects::EffectSource;
    let(snapshot,reads)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let archive=input.archive();let source=EffectSource::new(archive,input.profile()).unwrap();assert_eq!((0..source.len()).map(|i|archive.callables().identity(source.original_ordinal(i).unwrap()).unwrap().name).collect::<Vec<_>>(),["a","b","probe"].map(dm_ir::SymbolId::of),"original authored contribution order, independent of checker report order");let db=snapshot.native_raw_queries.as_ref().unwrap();let before=reads.load(Ordering::Relaxed);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,0);
    let page=snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).unwrap();assert_eq!(page.start(),0);assert_eq!(page.len(),1);assert_eq!(page.total(),source.len());page.validate(&source).unwrap();assert_eq!(page.ordinal(0),source.original_ordinal(0));assert_eq!(page.procedure(0).unwrap().name,dm_ir::SymbolId::of("a"));assert_eq!(page.source_calls(0).unwrap().len(),1);assert_eq!(page.source_calls(0).unwrap()[0].name,dm_ir::SymbolId::of("b"));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,2,"original a body plus its real b-prefix/return syntax demand");assert_eq!(db.db().stats(dm_query::Kind(23)).computed,1);
    let callee=page.source_calls(0).unwrap()[0];let callee_ordinal=(0..source.len()).filter_map(|i|source.original_ordinal(i)).find(|ordinal|archive.callables().identity(*ordinal)==Some(callee)).unwrap();
    let ordinal=source.original_ordinal(0).unwrap();let syntax=&archive.syntax_inputs().unwrap()[ordinal];let body_key=dm_query::Key::new(dm_query::Kind(4),syntax.key().into());assert!(db.db().dependants(&[body_key]).iter().any(|key|key.kind==dm_query::Kind(23)),"actual pageÃ¢â€ â€™Kind4 dynamic edge");
    let callee_syntax=&archive.syntax_inputs().unwrap()[callee_ordinal];let callee_key=dm_query::Key::new(dm_query::Kind(4),callee_syntax.key().into());assert!(db.db().dependants(&[callee_key]).iter().any(|key|key.kind==dm_query::Kind(23)),"callee prefix demand is an actual PAGE to Kind4 dependency");assert_eq!(db.effect_dependency_count_for_test(dm_query::Kind(23)),4,"own body plus callee prefix plus project/program actual read set");
    for i in 0..source.len(){let other=source.original_ordinal(i).unwrap();if other!=ordinal&&other!=callee_ordinal{let syntax=&archive.syntax_inputs().unwrap()[other];assert_eq!(db.db().value_bytes_at(dm_query::Key::new(dm_query::Kind(4),syntax.key().into())),0,"unrelated original body stays unparsed");}}
    let warm=snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).unwrap();assert!(Arc::ptr_eq(&page,&warm));assert_eq!(db.db().stats(dm_query::Kind(23)).computed,1);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,2);assert_eq!(reads.load(Ordering::Relaxed),before,"no source rereads on compute or warm claim");
    let expected=collect_effect_pages(&snapshot,1);let id=page.procedure(0).unwrap();assert_eq!(page.has_direct_effect(0),Some(expected[&id].0));assert_eq!(page.source_parent(0),expected[&id].1);assert_eq!(page.source_calls(0).unwrap(),expected[&id].2.iter().map(|row|row.0).collect::<Vec<_>>());
    let(foreign,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);assert!(foreign.native_effect_source_page(&input,0,1,&env(),None,&foreign.tree).is_err(),"equal source text is not current scope authority");
}
#[test]
fn actual_effect_page_query_io_quota_cancel_and_escaped_owner_are_not_cached_refusals(){
    let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let schedule=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));
    let error=snapshot.native_effect_source_page(&input,0,2,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450),"actual PAGE/Kind4 source failure: {error:?}");assert_eq!(db.db().stats(dm_query::Kind(23)).computed,0);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(23)),0);drop(schedule);
    let value=snapshot.native_effect_source_page(&input,0,2,&env(),None,&snapshot.tree).unwrap();let expected=value.retained_charge().unwrap();let bodies=db.db().stats(dm_query::Kind(4)).computed;let dependencies=db.effect_dependency_count_for_test(dm_query::Kind(23));
    assert!(db.db().evict_values(&[dm_query::Kind(23)])>0);let quota=db.effect_storage_limit_for_test(1);let refused=snapshot.native_effect_source_page(&input,0,2,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(refused.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(23)),0);drop(quota);let recovered=snapshot.native_effect_source_page(&input,0,2,&env(),None,&snapshot.tree).unwrap();assert_eq!(recovered.procedure(0),value.procedure(0));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,bodies);assert_eq!(db.effect_dependency_count_for_test(dm_query::Kind(23)),dependencies,"immutable dependency admission settles after failed and successful recomputation without retry growth");
    let cancellation=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(cancellation.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));cancellation.cancel();let stopped=snapshot.native_effect_source_page(&input,0,2,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(stopped.kind(),std::io::ErrorKind::Interrupted);drop(guard);assert!(Arc::ptr_eq(&recovered,&snapshot.native_effect_source_page(&input,0,2,&env(),None,&snapshot.tree).unwrap()));
    drop(recovered);drop(input);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert_eq!(db.purity_cache_probe().0,0);assert!(db.purity_cache_probe().2>=expected,"escaped actual page remains charged after graph node retirement");drop(value);assert_eq!(db.purity_cache_probe().2,0);
}

#[test]
fn checked_effect_prefix_loan_refuses_another_actual_body_from_same_archive(){
 let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let archive=snapshot.body_archive.as_ref().unwrap();let source=dm_analysis::checker_effects::EffectSource::new(archive,archive.tree().checker_builtin_profile().unwrap()).unwrap();let first=source.original_ordinal(0).unwrap();let other=source.original_ordinal(1).unwrap();let identity=archive.callables().identity(first).unwrap();
 let failed=archive.with_initial_setting_prefix_using(identity,|same,_|same.parse(other).map_err(|error|error.message),|prefix|prefix.settings().len());assert!(matches!(failed,Err(ref message)if message=="prefix parser returned another original callable occurrence"),"actual foreign original body loan cannot mint another prefix identity: {failed:?}");
 let actual=archive.with_initial_setting_prefix_using(identity,|same,ordinal|same.parse_checked(ordinal).map_err(|error|match error{dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>dm_analysis::policy_body_demand::PolicyFailure::from(error.message),dm_tree::frontend::BodySyntaxFailure::Operational(error)=>dm_analysis::policy_body_demand::PolicyFailure::Operational(error)}),|prefix|prefix.identity()).unwrap();assert_eq!(actual,identity);
}

#[test]
fn actual_page_callee_edge_delta_refuses_combined_live_scratch_before_metadata_growth(){
 let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();db.take_effect_edge_headroom_for_test();
 let first=snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).unwrap();let(initial,remaining,delta)=db.take_effect_edge_headroom_for_test().expect("actual extra callee prefix edge after own body");assert!(delta>0);assert!(initial>remaining);
 let limited=initial.checked_sub(remaining).unwrap().checked_add(delta-1).unwrap();drop(first);assert!(db.db().evict_values(&[dm_query::Kind(23)])>0);let before=db.effect_dependency_count_for_test(dm_query::Kind(23));let computed=db.db().stats(dm_query::Kind(23)).computed;let body_count=db.db().stats(dm_query::Kind(4)).computed;
 let pressure=db.effect_storage_limit_for_test(limited);let error=snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).err().expect("actual live scratch plus new edge delta exceeds same admission");assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory,"{error:?}");let(_,observed,requested)=db.take_effect_edge_headroom_for_test().expect("reaches actual same callee-prefix growth boundary");assert_eq!(requested,delta);assert_eq!(observed,delta-1);assert_eq!(db.effect_dependency_count_for_test(dm_query::Kind(23)),before,"metadata must not grow on refused delta and failed Ctx must settle old bound");assert_eq!(db.db().stats(dm_query::Kind(23)).computed,computed);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,body_count,"refusal precedes actual new callee get");drop(pressure);
 let recovered=snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).unwrap();assert_eq!(recovered.procedure(0).unwrap().name,dm_ir::SymbolId::of("probe"));assert!(Arc::ptr_eq(&recovered,&snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).unwrap()));
}

#[test]
fn actual_effect_query_event_windows_preserve_all_original_bodies_and_cross_window_calls(){
 use dm_analysis::checker_effects::EffectSource;
 let calls="    leaf()\n".repeat(6000);let text=format!("/proc/first()\n{calls}/proc/second()\n{calls}/proc/leaf()\n    return 0\n");
 let(snapshot,reads)=fixture(&text,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let archive=input.archive();let source=EffectSource::new(archive,input.profile()).unwrap();assert_eq!(source.len(),3);let before=reads.load(Ordering::Relaxed);
 let first=snapshot.native_effect_source_page(&input,0,3,&env(),None,&snapshot.tree).unwrap();assert_eq!(first.len(),1);assert_eq!(first.source_calls(0).unwrap().len(),6000);
 let next=snapshot.native_effect_source_page(&input,first.len(),3,&env(),None,&snapshot.tree).unwrap();assert_eq!(next.len(),2);assert_eq!(next.source_calls(0).unwrap().len(),6000);assert_eq!(next.source_calls(1).unwrap().len(),0);
 let ordinals=(0..first.len()).map(|i|first.ordinal(i).unwrap()).chain((0..next.len()).map(|i|next.ordinal(i).unwrap())).collect::<Vec<_>>();assert_eq!(ordinals,(0..source.len()).map(|i|source.original_ordinal(i).unwrap()).collect::<Vec<_>>());
 assert_eq!(first.source_calls(0).unwrap()[0],next.procedure(1).unwrap());assert_eq!(next.source_calls(0).unwrap()[0],next.procedure(1).unwrap());
 let host=archive.body_query_host().unwrap();let body=|syntax:&Arc<dm_tree::frontend::BodySyntaxInput>,_:&dm_analysis::checker_effects::ExecutionAdmission|host.syntax_checked(syntax);let graph=dm_analysis::checker_effects::CompactEffectGraph::build_original_checked(&source,3,&dm_analysis::checker_effects::ExecutionAdmission::default(),&mut||Ok(()),&body).unwrap();assert_eq!(graph.len(),3);for node in 0..2{let mut count=0;while let Some(target)=graph.successor(node,count).unwrap(){assert_eq!(target,2);count+=1;}assert_eq!(count,6000,"global CSR keeps every cross-window original edge");}
 assert!(Arc::ptr_eq(&first,&snapshot.native_effect_source_page(&input,0,3,&env(),None,&snapshot.tree).unwrap()));assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().db().stats(dm_query::Kind(4)).computed,3);assert_eq!(reads.load(Ordering::Relaxed),before);
}

#[test]
fn actual_global_effect_graph_query_uses_page_edges_and_reuses_current_retained_owner(){
 use dm_analysis::checker_effects::{EffectSource,ExecutionAdmission};
 let(snapshot,reads)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let source=EffectSource::new(input.archive(),input.profile()).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=reads.load(Ordering::Relaxed);
 let graph=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap();let current=graph.current(&source).unwrap();assert_eq!(current.len(),source.len());let scc=current.compute_scc_checked(&ExecutionAdmission::default(),&mut||Ok(())).unwrap();assert_eq!(scc.components().len(),source.len());
 assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,source.len() as u64);assert_eq!(db.db().stats(dm_query::Kind(17)).computed,0,"no one-node-per-body purity graph");assert_eq!(db.effect_graph_work_for_test(),0);
 let warm=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap();assert!(Arc::ptr_eq(&graph,&warm));assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1);assert_eq!(reads.load(Ordering::Relaxed),before);
 let first=snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).unwrap();let ordinal=first.ordinal(0).unwrap();let syntax=&input.archive().syntax_inputs().unwrap()[ordinal];let dependencies=db.db().dependants(&[dm_query::Key::new(dm_query::Kind(4),syntax.key().into())]);assert!(dependencies.iter().any(|key|key.kind==dm_query::Kind(23)));assert!(dependencies.iter().any(|key|key.kind==dm_query::Kind(24)),"actual global→page→Kind4 transitive dependency");
 let(foreign,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let foreign_input=foreign.native_effect_source_input(&foreign.tree).unwrap();let foreign_source=EffectSource::new(foreign_input.archive(),foreign_input.profile()).unwrap();assert!(graph.current(&foreign_source).is_err(),"equal text cannot promote a retained global graph");
}
#[test]
fn actual_global_effect_graph_io_quota_cancel_retry_and_escaped_charge(){
 let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let schedule=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));
 let error=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(db.db().stats(dm_query::Kind(24)).computed,0);assert_eq!(db.effect_graph_work_for_test(),0);drop(schedule);
 let quota=db.effect_storage_limit_for_test(1);assert_eq!(snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(db.effect_graph_work_for_test(),0);drop(quota);
 let graph=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap();let expected=graph.retained_charge().unwrap();let bodies=db.db().stats(dm_query::Kind(4)).computed;let cancel=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(cancel.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));cancel.cancel();assert_eq!(snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);assert!(Arc::ptr_eq(&graph,&snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap()));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,bodies);
 drop(input);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert_eq!(db.purity_cache_probe().0,0);assert!(db.purity_cache_probe().2>=expected,"escaped actual scalar graph remains charged after node retirement");drop(graph);assert_eq!(db.purity_cache_probe().2,0);assert_eq!(db.effect_graph_work_for_test(),0);
}

#[test]
fn escaped_effect_graph_charge_survives_zero_strong_count_until_physical_buffers_free(){
 let(snapshot,_)=fixture("/proc/a()\n    return 1\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let graph=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap();let bytes=graph.retained_charge().unwrap();
 drop(input);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert_eq!(db.purity_cache_probe().0,0);
 let entered=Arc::new(std::sync::Barrier::new(2));let release=Arc::new(std::sync::Barrier::new(2));graph.pause_drop_for_test(entered.clone(),release.clone());let thread=std::thread::spawn(move||drop(graph));entered.wait();
 assert!(db.purity_cache_probe().2>=bytes,"physical graph buffers still live after outer Arc strong count reaches zero");release.wait();thread.join().unwrap();assert_eq!(db.purity_cache_probe().2,0);
}
#[test]
fn escaped_effect_graph_keeps_same_ledger_alive_after_database_drops(){
 let(snapshot,_)=fixture("/proc/a()\n    return 1\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let graph=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap();let alive=snapshot.native_raw_queries.as_ref().unwrap().effect_graph_ledger_liveness_for_test();
 drop(input);drop(snapshot);assert!(alive(),"actual escaped payload retains SAME admission domain");drop(graph);assert!(!alive(),"no ledger/result strong cycle survives final payload release");
}

#[test]
fn actual_global_summary_query_matches_original_whole_scc_and_warm_graph_dependency(){
 use dm_analysis::checker_effects::{EffectInput,EffectSource,ExecutionAdmission};
 for changed in [false,true]{let text=include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme");let text=if changed{text.replace("global_value=1","global_value")}else{text.to_owned()};let(snapshot,reads)=fixture(&text,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let source=EffectSource::new(input.archive(),input.profile()).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=reads.load(Ordering::Relaxed);
 let summary=snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).unwrap();let graph=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap();assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1);assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1);assert_eq!(db.effect_graph_work_for_test(),0);
 let old_input=EffectInput::new(input.archive().clone(),input.profile()).unwrap();let a=ExecutionAdmission::default();let bodies=old_input.order().iter().map(|(ordinal,_)|old_input.compute_body_checked(*ordinal,input.archive().tree(),&a).unwrap()).collect();let plan=old_input.plan(bodies,input.archive().tree(),&a).unwrap();let old=plan.summarize(&old_input).unwrap();for node in 0..source.len(){let id=input.archive().callables().identity(source.original_ordinal(node).unwrap()).unwrap();assert_eq!(summary.has_effect(&source,node).unwrap(),old.source_has_effect(id));assert_eq!(summary.has_effect(&source,node).unwrap(),Some(!changed));}
 assert!(Arc::ptr_eq(&summary,&snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).unwrap()));assert!(Arc::ptr_eq(&graph,&snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).unwrap()));assert_eq!(reads.load(Ordering::Relaxed),before);
 let syntax=&input.archive().syntax_inputs().unwrap()[source.original_ordinal(0).unwrap()];assert!(db.db().dependants(&[dm_query::Key::new(dm_query::Kind(4),syntax.key().into())]).iter().any(|key|key.kind==dm_query::Kind(25)),"actual transitive global summary→global graph→page→originalKind4 dependency");}
}
#[test]
fn actual_global_summary_io_quota_cancel_and_escaped_graph_credit_recover(){
 let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let fail=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));assert_eq!(snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).err().unwrap().raw_os_error(),Some(1450));assert_eq!(db.db().stats(dm_query::Kind(25)).computed,0);assert_eq!(db.effect_graph_work_for_test(),0);drop(fail);
 let value=snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).unwrap();assert!(db.db().evict_values(&[dm_query::Kind(25)])>0);let quota=db.effect_storage_limit_for_test(1);assert_eq!(snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(db.effect_graph_work_for_test(),0);drop(quota);let recovered=snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).unwrap();
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);assert!(Arc::ptr_eq(&recovered,&snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).unwrap()));
 drop(value);let retained=recovered.retained_charge().unwrap();drop(input);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert_eq!(db.purity_cache_probe().0,0);assert!(db.purity_cache_probe().2>=retained);drop(recovered);assert_eq!(db.purity_cache_probe().2,0);
}

#[test]
fn actual_global_summary_preserves_original_deferred_body_source_error_as_semantic_outcome(){
 let(snapshot,_)=fixture("/proc/probe()\n    return 1+\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let original=snapshot.native_effect_source_graph(&input,1,&env(),None,&snapshot.tree).err().expect("actual original deferred body syntax must refuse");assert_eq!(original.kind(),std::io::ErrorKind::Other);assert_eq!(original.raw_os_error(),None);assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1,"genuine source refusal is a valid graph semantic outcome");
 let summary=snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(summary.to_string(),original.to_string(),"Kind25 must preserve actual original source message instead of Missing query transport");assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1,"actual source error follows normal typed semantic publication");assert_eq!(db.effect_graph_work_for_test(),0);
 assert_eq!(snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).err().unwrap().to_string(),original.to_string());assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1,"same valid source refusal may stay warm");
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);assert_eq!(snapshot.native_effect_source_summary(&input,1,&env(),None,&snapshot.tree).err().unwrap().to_string(),original.to_string());
}

#[test]
fn retained_effect_page_metadata_credit_survives_actual_physical_final_drop(){
 let(snapshot,_)=fixture("/proc/a()\n    return 1\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let page=snapshot.native_effect_source_page(&input,0,1,&env(),None,&snapshot.tree).unwrap();let bytes=page.retained_charge().unwrap();drop(input);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert_eq!(db.purity_cache_probe().0,0);
 let entered=Arc::new(std::sync::Barrier::new(2));let release=Arc::new(std::sync::Barrier::new(2));page.pause_drop_for_test(entered.clone(),release.clone());let thread=std::thread::spawn(move||drop(page));entered.wait();assert!(db.purity_cache_probe().2>=bytes,"original contribution buffers/Weak coordination physically remain despite outer strong0");release.wait();thread.join().unwrap();assert_eq!(db.purity_cache_probe().2,0);
}

#[test]
fn callable_note_from_already_issued_body_preserves_original_point_without_another_get(){
 let(snapshot,_)=fixture("/proc/first()\n    return 1\n/proc/second()\n    return 2\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let archive=input.archive();let first=archive.callables().source_order()[0];let other=archive.callables().source_order()[1];let id=archive.callables().identity(first).unwrap();let body=archive.parse_checked(first).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let before=db.db().stats(dm_query::Kind(4));
 let actual=archive.callable_note_origin_from_parsed::<String>(id,first,&body).unwrap();assert_eq!(db.db().stats(dm_query::Kind(4)).computed,before.computed,"borrowed source projection cannot compute another body");assert_eq!(db.db().stats(dm_query::Kind(4)).green,before.green,"borrowed source projection cannot perform even a warm body get");assert_eq!(actual,archive.callable_note_origin(id).unwrap());let sibling=archive.parse_checked(other).unwrap();assert_eq!(archive.callable_note_origin_from_parsed::<String>(id,first,&sibling).unwrap_err(),"callable note primary source unavailable");
}

#[test]
fn parsed_callable_note_projection_matches_original_proc_verb_override_versions_and_precharges_path_clone(){
 let(snapshot,_)=fixture("/datum/source_notes/proc/same()\n    return 1\n/datum/source_notes/same()\n    return 2\n/datum/source_notes/verb/present_note()\n    return 3\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let archive=input.archive();let mut procs=Vec::new();let mut verbs=0;
 for &ordinal in archive.callables().source_order(){let identity=archive.callables().identity(ordinal).unwrap();if identity.verb{verbs+=1}else{procs.push((ordinal,identity));}let body=archive.parse_checked(ordinal).unwrap();let expected=archive.callable_note_origin(identity).unwrap();let original_owners=Arc::strong_count(&expected.path);let borrowed=archive.callable_note_origin_borrowed_from_parsed(identity,ordinal,&body).unwrap();assert_eq!(Arc::strong_count(&expected.path),original_owners,"borrowed projection does not extend any path owner");let charge=borrowed.retained_charge().unwrap();let tiny=dm_analysis::checker_effects::ExecutionAdmission::with_limit(charge-1);assert!(tiny.reserve_external(charge).is_err());assert_eq!(Arc::strong_count(&expected.path),original_owners,"admission failure precedes path-owner clone");let admission=dm_analysis::checker_effects::ExecutionAdmission::default();admission.reserve_external(charge).unwrap();assert_eq!(borrowed.into_owned(),expected);assert_eq!(archive.callable_note_origin_from_parsed::<String>(identity,ordinal,&body).unwrap(),expected);}
 assert_eq!(verbs,1);assert_eq!(procs.len(),2);assert_ne!(procs[0].1.occurrence,procs[1].1.occurrence);let sibling=archive.parse_checked(procs[1].0).unwrap();assert_eq!(archive.callable_note_origin_from_parsed::<String>(procs[0].1,procs[0].0,&sibling).unwrap_err(),"callable note primary source unavailable","same name/owner/kind cannot promote another actual version");
}

#[test]
fn actual_page_fingerprint_covers_report_only_metadata_and_is_stable_across_fresh_physical_page_recomputation(){
 // Both fixtures are global procedures (no override parent); compare the public
 // graph fields without exposing the checker's private EffectTarget type.
 let(a,_)=fixture("/proc/probe()\n    set waitfor=0\n    return 1\n",None);let(b,_)=fixture("/proc/probe()\n    set waitfor=1\n    return 1\n",None);let ai=a.native_effect_source_input(&a.tree).unwrap();let bi=b.native_effect_source_input(&b.tree).unwrap();let ap=a.native_effect_source_page(&ai,0,1,&env(),None,&a.tree).unwrap();let bp=b.native_effect_source_page(&bi,0,1,&env(),None,&b.tree).unwrap();assert_eq!(ap.procedure(0),bp.procedure(0));assert_eq!(ap.source_calls(0),bp.source_calls(0));assert_eq!(ap.has_direct_effect(0),bp.has_direct_effect(0));assert_eq!(ap.has_builtin_effect_call(0),bp.has_builtin_effect_call(0));assert_ne!(ap.report_fingerprint(),bp.report_fingerprint(),"waitfor-only report meaning changes even with identical graph rows");let db=a.native_raw_queries.as_ref().unwrap();assert_eq!(db.effect_page_outcome_hash_for_test(&ai,0,1),ap.report_fingerprint(),"actual GraphWork publication uses complete report fields, not key.id");let body_computes=db.db().stats(dm_query::Kind(4)).computed;assert!(db.db().evict_values(&[dm_query::Kind(23)])>0);let fresh=a.native_effect_source_page(&ai,0,1,&env(),None,&a.tree).unwrap();assert!(!Arc::ptr_eq(&ap,&fresh));assert_eq!(ap.report_fingerprint(),fresh.report_fingerprint(),"new per-page EffectInput Weak identity and allocation capacity are not semantic content");assert_eq!(db.effect_page_outcome_hash_for_test(&ai,0,1),fresh.report_fingerprint());assert_eq!(db.db().stats(dm_query::Kind(4)).computed,body_computes);
}
#[test]
fn actual_page_fingerprint_covers_original_callable_line_and_body_directive_points_without_graph_changes(){let(a,_)=fixture("/proc/probe()\n    return 1\n",None);let(b,_)=fixture("\n/proc/probe()\n    return 1\n",None);let ai=a.native_effect_source_input(&a.tree).unwrap();let bi=b.native_effect_source_input(&b.tree).unwrap();let ap=a.native_effect_source_page(&ai,0,1,&env(),None,&a.tree).unwrap();let bp=b.native_effect_source_page(&bi,0,1,&env(),None,&b.tree).unwrap();assert_eq!(ap.procedure(0),bp.procedure(0));assert_eq!(ap.source_calls(0),bp.source_calls(0));assert_eq!(ap.has_direct_effect(0),bp.has_direct_effect(0));assert_ne!(ap.report_fingerprint(),bp.report_fingerprint());}

#[test]
fn actual_ordered_global_effect_reports_match_all_complete_pinned_purity_and_sleep_transcripts(){
 use dm_analysis::checker_effects::EffectReportPhase::{Purity,Sleep};
 macro_rules! case{($family:literal,$name:literal,$phase:ident)=>{(include_str!(concat!("../../../fixtures/unified_checks/",$family,"/",$name,"/probe.dme")),include_str!(concat!("../../../fixtures/unified_checks/",$family,"/",$name,"/reference.stderr")),concat!($family,"/",$name),$phase)}}
 for(source,expected,name,phase)in[case!("purity","parameter",Purity),case!("purity","local-literal",Purity),case!("purity","local-alias",Purity),case!("purity","overload",Purity),case!("purity","no-overload",Purity),case!("purity","cycle",Purity),case!("purity","spawn",Purity),case!("purity","pure-discard",Purity),case!("purity","qualified-field",Purity),case!("purity","override",Purity),case!("purity","global-source",Purity),case!("purity","verb",Purity),case!("sleep","direct",Sleep),case!("sleep","transitive",Sleep),case!("sleep","waitfor",Sleep),case!("sleep","own-waitfor",Sleep),case!("sleep","exempt",Sleep),case!("sleep","spawn-direct",Sleep),case!("sleep","spawn-first",Sleep),case!("sleep","plain-first",Sleep),case!("sleep","override",Sleep),case!("sleep","cycle",Sleep),case!("sleep","global-sleep",Sleep),case!("sleep","return-anchor",Sleep),case!("sleep","initializer-anchor",Sleep),case!("sleep","constructor-sleep",Sleep)]{let(snapshot,reads)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let rows=snapshot.native_effect_source_report(&input,2,phase,&env(),None,&snapshot.tree).unwrap_or_else(|e|panic!("{name}: {e:?}"));assert_eq!(render(&rows),decode_oracle_transport(expected).as_ref(),"{name}: complete independent original finding/note/source/order contract");let syntax=db.db().stats(dm_query::Kind(4)).computed;let io=reads.load(Ordering::Relaxed);let counts=(23..=27).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>();let warm=snapshot.native_effect_source_report(&input,2,phase,&env(),None,&snapshot.tree).unwrap();assert!(Arc::ptr_eq(&rows,&warm));assert_eq!(db.db().stats(dm_query::Kind(4)).computed,syntax);assert_eq!(reads.load(Ordering::Relaxed),io);assert_eq!((23..=27).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>(),counts);assert_eq!(db.effect_graph_work_for_test(),0);}
}

#[test]
fn actual_ordered_global_report_preserves_real_child_io_no_outcome_quota_cancel_and_same_input_recovery(){
 use dm_analysis::checker_effects::EffectReportPhase::Purity;let source=include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme");let(snapshot,_)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let stop=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));let failure=snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(failure.raw_os_error(),Some(1450),"actual Kind26→25→24→23→Kind4 operation must keep first OS cause: {failure:?}");assert_eq!(db.db().stats(dm_query::Kind(26)).computed,0);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(26)),0);assert_eq!(db.effect_graph_work_for_test(),0);drop(stop);
 let rows=snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).unwrap();assert_eq!(render(&rows),decode_oracle_transport(include_str!("../../../fixtures/unified_checks/purity/cycle/reference.stderr")).as_ref());let count=db.db().stats(dm_query::Kind(26)).computed;let(other,_)=fixture(source,None);assert!(other.native_effect_source_report(&input,2,Purity,&env(),None,&other.tree).is_err());assert_eq!(db.db().stats(dm_query::Kind(26)).computed,count);
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);assert!(Arc::ptr_eq(&rows,&snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).unwrap()));assert!(db.db().evict_values(&[dm_query::Kind(26)])>0);let quota=db.effect_storage_limit_for_test(1);assert_eq!(snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(db.db().stats(dm_query::Kind(26)).computed,count);assert_eq!(db.effect_graph_work_for_test(),0);drop(quota);let recovered=snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).unwrap();assert_eq!(render(&recovered),render(&rows));drop(recovered);let bytes=rows.retained_charge().unwrap();drop(input);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert_eq!(db.purity_cache_probe().0,0);assert!(db.purity_cache_probe().2>=bytes);drop(rows);assert_eq!(db.purity_cache_probe().2,0);
}

#[test]
fn escaped_ordered_report_credit_waits_for_actual_message_path_and_note_buffer_free(){use dm_analysis::checker_effects::EffectReportPhase::Purity;let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme"),None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let rows=snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).unwrap();assert!(!rows.is_empty());let bytes=rows.retained_charge().unwrap();drop(input);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert_eq!(db.purity_cache_probe().0,0);let entered=Arc::new(std::sync::Barrier::new(2));let release=Arc::new(std::sync::Barrier::new(2));rows.pause_drop_for_test(entered.clone(),release.clone());let thread=std::thread::spawn(move||drop(rows));entered.wait();assert!(db.purity_cache_probe().2>=bytes,"all diagnostic allocations still physically live after outer strong0");release.wait();thread.join().unwrap();assert_eq!(db.purity_cache_probe().2,0);}

#[test]
fn ordered_global_report_preserves_deferred_body_source_error_without_promoting_it_to_query_io(){use dm_analysis::checker_effects::EffectReportPhase::Purity;let(snapshot,_)=fixture("/proc/bad()\n    return 1+\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let summary=snapshot.native_effect_source_summary(&input,2,&env(),None,&snapshot.tree).err().unwrap().to_string();let error=snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(error.to_string(),summary);assert_eq!(db.db().stats(dm_query::Kind(26)).computed,1,"genuine unchanged source refusal is an ordinary valid Err outcome");assert_eq!(db.effect_graph_work_for_test(),0);assert_eq!(snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).err().unwrap().to_string(),summary);assert_eq!(db.db().stats(dm_query::Kind(26)).computed,1);let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);assert_eq!(snapshot.native_effect_source_report(&input,2,Purity,&env(),None,&snapshot.tree).err().unwrap().to_string(),summary);}

#[test]
fn many_small_original_target_groups_retire_real_scratch_under_the_unchanged_family_cap(){use dm_analysis::checker_effects::{EffectReportPhase::Purity,RESULT_BUDGET};use std::fmt::Write;let mut source=String::new();for at in 0..6000{writeln!(&mut source,"/proc/group_{at}(i)\n    set SpacemanDMM_should_be_pure=1\n    i++").unwrap();}let(snapshot,_)=fixture(&source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let rows=snapshot.native_effect_source_report(&input,64,Purity,&env(),None,&snapshot.tree).unwrap();assert_eq!(rows.len(),6000);let(peak,total,retired)=rows.report_scope_counts();assert!(total>RESULT_BUDGET,"actual group allocations exceed one monotone family envelope: total={total}, peak={peak}, retired={retired}");assert!(peak<RESULT_BUDGET);assert!(retired>0);let db=snapshot.native_raw_queries.as_ref().unwrap();assert_eq!(db.effect_graph_work_for_test(),0);assert!(Arc::ptr_eq(&rows,&snapshot.native_effect_source_report(&input,64,Purity,&env(),None,&snapshot.tree).unwrap()));}


fn effect_wire_transcript(value:&serde_json::Value)->String{use std::fmt::Write;let mut text=String::new();for row in value["diagnostics"].as_array().unwrap(){let point=&row["source"];writeln!(&mut text,"@FIXTURE@, line {}, column {}:\n{}: {}",point["line"].as_u64().unwrap(),point["column"].as_u64().unwrap(),row["severity"].as_str().unwrap(),row["message"].as_str().unwrap()).unwrap();for note in row["notes"].as_array().unwrap(){let at=&note["source"];if at["file"]=="(unknown)"&&at["line"]==0&&at["column"]==0{writeln!(&mut text,"- (unknown):0:0: {}",note["message"].as_str().unwrap()).unwrap()}else{writeln!(&mut text,"- {}:{}: {}",at["line"].as_u64().unwrap(),at["column"].as_u64().unwrap(),note["message"].as_str().unwrap()).unwrap()}}text.push('\n');}text}
#[test]
fn buffered_effect_writer_matches_all_whole_original_both_family_oracles_and_has_stable_warm_bytes(){let source=include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/probe.dme");let(snapshot,reads)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let mut output=Vec::new();snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut output).unwrap();let value:serde_json::Value=serde_json::from_slice(&output).unwrap();assert_eq!(value["row"],"source_native_effect_reports");assert_eq!(value["schema"],"dm-session-source-query-v1");assert_eq!(value["full_checker_parity"],false);assert_eq!(value["effect_report_only"],true);assert_eq!(value["effect_phase_order"],serde_json::json!(["body_immediate","must_not_sleep","must_be_pure"]));assert_eq!(value["body_count"],input.archive().len());let actual=multi_target_tests::target_groups(&effect_wire_transcript(&value));for expected in[include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-0.stderr"),include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-1.stderr"),include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-2.stderr"),include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-3.stderr")]{assert_eq!(actual,multi_target_tests::target_groups(expected),"entire original diagnostics/notes/positions/order with ONLY permitted whole-group permutations");}let db=snapshot.native_raw_queries.as_ref().unwrap();let counts=(23..=27).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>();let syntax=db.db().stats(dm_query::Kind(4)).computed;let io=reads.load(Ordering::Relaxed);let mut warm=Vec::new();snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,output);assert_eq!((23..=27).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>(),counts);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,syntax);assert_eq!(reads.load(Ordering::Relaxed),io);assert_eq!(db.effect_graph_work_for_test(),0);}
#[test]
fn buffered_effect_writer_puts_actual_immediate_before_sleep_before_purity_without_row_or_note_sorting(){let source=format!("{}\n{}",include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/probe.dme"),include_str!("../../../fixtures/unified_checks/purity/pure-discard/probe.dme"));let(snapshot,_)=fixture(&source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let mut bytes=Vec::new();snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();let rows=value["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),5);assert_eq!(rows.iter().map(|row|row["phase"].as_str().unwrap()).collect::<Vec<_>>(),["body_immediate","must_not_sleep","must_not_sleep","must_be_pure","must_be_pure"]);assert_eq!(rows[0]["message"],"call to pure proc value discards return value");assert_eq!(rows[0]["notes"][0]["message"],"prohibited by this must_be_pure annotation");}
#[test]
fn buffered_effect_writer_actual_kind4_io_cancel_quota_and_foreign_frame_never_write_partial_envelopes(){let source=include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/probe.dme");let(snapshot,_)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let schedule=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));let mut bytes=b"prefix".to_vec();let error=snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut bytes).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(bytes,b"prefix");assert_eq!(db.effect_graph_work_for_test(),0);drop(schedule);let mut expected=Vec::new();snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut expected).unwrap();let count=db.db().stats(dm_query::Kind(4)).computed;let quota=db.effect_storage_limit_for_test(1);assert_eq!(snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut bytes).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(bytes,b"prefix");assert_eq!(db.effect_graph_work_for_test(),0);drop(quota);let token=crate::daemon::control::Cancellation::default();let binding=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut bytes).unwrap_err().kind(),std::io::ErrorKind::Interrupted);assert_eq!(bytes,b"prefix");drop(binding);let(foreign,_)=fixture(source,None);assert!(foreign.write_native_effect_reports(&input,2,&env(),None,&foreign.tree,&mut bytes).is_err());assert_eq!(bytes,b"prefix");let mut retry=Vec::new();snapshot.write_native_effect_reports(&input,2,&env(),None,&snapshot.tree,&mut retry).unwrap();assert_eq!(retry,expected);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,count);}


#[test]
fn actual_target_report_windows_preserve_complete_original_cross_window_cycles_and_override_notes(){
 use dm_analysis::checker_effects::EffectReportPhase::{Purity,Sleep};
 for(source,expected,phase)in[(include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme"),include_str!("../../../fixtures/unified_checks/purity/cycle/reference.stderr"),Purity),(include_str!("../../../fixtures/unified_checks/purity/override/probe.dme"),include_str!("../../../fixtures/unified_checks/purity/override/reference.stderr"),Purity),(include_str!("../../../fixtures/unified_checks/sleep/cycle/probe.dme"),include_str!("../../../fixtures/unified_checks/sleep/cycle/reference.stderr"),Sleep),(include_str!("../../../fixtures/unified_checks/sleep/override/probe.dme"),include_str!("../../../fixtures/unified_checks/sleep/override/reference.stderr"),Sleep)]{
  let(snapshot,reads)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let total=input.archive().callables().source_order().len();let mut actual=String::new();let mut warmed=Vec::new();
  for start in 0..total{let rows=snapshot.native_effect_source_report_window(&input,2,phase,start,1,&env(),None,&snapshot.tree).unwrap();actual.push_str(&render(&rows));warmed.push(rows);}
  assert_eq!(actual,decode_oracle_transport(expected).as_ref());assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1,"one actual complete graph drives every target window");assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1,"no per-window summary");let body_count=db.db().stats(dm_query::Kind(4)).computed;let io=reads.load(Ordering::Relaxed);let kind=dm_query::Kind(if phase==Purity{26}else{27});let count=db.db().stats(kind).computed;let edges=db.effect_dependency_count_for_test(kind);assert!(edges<total.saturating_mul(total+4).saturating_mul(2)+16,"actual read-set settlement replaces MAX_NODES per window");
  for(start,old)in warmed.iter().enumerate(){let warm=snapshot.native_effect_source_report_window(&input,2,phase,start,1,&env(),None,&snapshot.tree).unwrap();assert!(Arc::ptr_eq(old,&warm));}
  assert_eq!(db.db().stats(kind).computed,count);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,body_count);assert_eq!(reads.load(Ordering::Relaxed),io);assert_eq!(db.effect_dependency_count_for_test(kind),edges);assert_eq!(db.effect_graph_work_for_test(),0);
 }
}

#[test]
fn actual_report_window_identity_refuses_wrong_ranges_and_keeps_first_child_io_and_recovery(){
 use dm_analysis::checker_effects::EffectReportPhase::Purity;let source=include_str!("../../../fixtures/unified_checks/purity/cycle/probe.dme");let(snapshot,_)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let total=input.archive().callables().source_order().len();assert!(total>1);
 assert!(snapshot.native_effect_source_report_window(&input,2,Purity,total,1,&env(),None,&snapshot.tree).is_err());assert_eq!(db.db().stats(dm_query::Kind(26)).computed,0);
 let stop=db.fail_body_syntax_after_for_test(0,std::io::Error::from_raw_os_error(1450));let error=snapshot.native_effect_source_report_window(&input,2,Purity,0,1,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450),"{error:?}");assert_eq!(db.db().stats(dm_query::Kind(26)).computed,0);assert_eq!(db.effect_graph_work_for_test(),0);drop(stop);
 let first=snapshot.native_effect_source_report_window(&input,2,Purity,0,1,&env(),None,&snapshot.tree).unwrap();let second=snapshot.native_effect_source_report_window(&input,2,Purity,1,1,&env(),None,&snapshot.tree).unwrap();assert!(!Arc::ptr_eq(&first,&second));assert_eq!(db.db().stats(dm_query::Kind(26)).computed,2);
 let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snapshot.native_effect_source_report_window(&input,2,Purity,0,1,&env(),None,&snapshot.tree).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);assert!(Arc::ptr_eq(&first,&snapshot.native_effect_source_report_window(&input,2,Purity,0,1,&env(),None,&snapshot.tree).unwrap()));assert_eq!(db.effect_graph_work_for_test(),0);
}

#[test]
fn source_error_report_window_settles_its_actual_summary_edge_and_warm_reuses_immutable_dependencies(){use dm_analysis::checker_effects::EffectReportPhase::Purity;let(snapshot,_)=fixture("/proc/bad()\n    return 1+\n",None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let error=snapshot.native_effect_source_report_window(&input,2,Purity,0,1,&env(),None,&snapshot.tree).err().unwrap().to_string();assert_eq!(db.db().stats(dm_query::Kind(26)).computed,1);let edges=db.effect_dependency_count_for_test(dm_query::Kind(26));assert_eq!(edges,1,"the cached actual source error depends on its one global summary child");let warm=snapshot.native_effect_source_report_window(&input,2,Purity,0,1,&env(),None,&snapshot.tree).err().unwrap();assert_eq!(warm.to_string(),error);assert_eq!(db.effect_dependency_count_for_test(dm_query::Kind(26)),edges);assert_eq!(db.db().stats(dm_query::Kind(26)).computed,1);assert_eq!(db.effect_graph_work_for_test(),0);}


#[test]
fn exhausted_effect_writer_preserves_all_whole_original_group_transcripts_across_target_windows(){let source=include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/probe.dme");let(snapshot,reads)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let mut bytes=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut bytes).unwrap();let value:serde_json::Value=serde_json::from_slice(&bytes).unwrap();assert_eq!(value["target_windows_exhausted"],true);assert_eq!(value["full_checker_parity"],false);assert_eq!(value["effect_report_only"],true);let actual=multi_target_tests::target_groups(&effect_wire_transcript(&value));for expected in[include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-0.stderr"),include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-1.stderr"),include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-2.stderr"),include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/reference-3.stderr")]{assert_eq!(actual,multi_target_tests::target_groups(expected));}assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(26)),0);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(27)),0);let syntax=db.db().stats(dm_query::Kind(4)).computed;let io=reads.load(Ordering::Relaxed);let global=(24..=25).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>();let edges=(26..=27).map(|k|db.effect_dependency_count_for_test(dm_query::Kind(k))).collect::<Vec<_>>();let mut warm=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(warm,bytes);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,syntax);assert_eq!(reads.load(Ordering::Relaxed),io);assert_eq!((24..=25).map(|k|db.db().stats(dm_query::Kind(k)).computed).collect::<Vec<_>>(),global);assert_eq!((26..=27).map(|k|db.effect_dependency_count_for_test(dm_query::Kind(k))).collect::<Vec<_>>(),edges);assert_eq!(db.effect_graph_work_for_test(),0);}

#[test]
fn exhausted_effect_writer_preserves_typed_child_failures_prefix_and_physical_credit_on_unwind(){let source=include_str!("../../../fixtures/unified_checks/effect_multi_target/both-families/probe.dme");let(snapshot,_)=fixture(source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let schedule=db.fail_body_syntax_after_for_test(1,std::io::Error::from_raw_os_error(1450));let mut output=b"prefix".to_vec();let error=snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut output).unwrap_err();assert_eq!(error.raw_os_error(),Some(1450),"{error:?}");assert_eq!(output,b"prefix");assert_eq!(db.effect_graph_work_for_test(),0);drop(schedule);let mut healthy=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut healthy).unwrap();let quota=db.effect_storage_limit_for_test(1);assert_eq!(snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut output).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(output,b"prefix");drop(quota);let token=crate::daemon::control::Cancellation::default();let bound=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut output).unwrap_err().kind(),std::io::ErrorKind::Interrupted);assert_eq!(output,b"prefix");drop(bound);
 struct PanicWriter;impl std::io::Write for PanicWriter{fn write(&mut self,_:&[u8])->std::io::Result<usize>{panic!("actual final output boundary") }fn flush(&mut self)->std::io::Result<()>{Ok(())}}
 let unwind=std::panic::catch_unwind(std::panic::AssertUnwindSafe(||snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut PanicWriter)));assert!(unwind.is_err());assert_eq!(db.effect_graph_work_for_test(),0);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(26)),0);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(27)),0);let mut recovered=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,2,1,&env(),None,&snapshot.tree,&mut recovered).unwrap();assert_eq!(recovered,healthy);}

#[test]
fn exhausted_effect_writer_keeps_all_10001_original_targets_without_raising_any_window_or_family_cap(){use std::fmt::Write;let mut source=String::new();for at in 0..10001{writeln!(&mut source,"/proc/exhausted_{at}(i)\n    set SpacemanDMM_should_be_pure=1\n    i++").unwrap();}let phase_started=std::time::Instant::now();eprintln!("effect-10001 phase=fixture-begin targets=10001");let(snapshot,reads)=fixture(&source,None);eprintln!("effect-10001 phase=fixture-end elapsed_ms={}",phase_started.elapsed().as_millis());let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let _trace=db.trace_effect_pressure_for_test();db.trace_effect_phase_for_test("cold-begin",0,10001);assert_eq!(input.archive().callables().source_order().len(),10001);let mut output=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,64,dm_analysis::checker_effects::MAX_EVENTS,&env(),None,&snapshot.tree,&mut output).unwrap();db.trace_effect_phase_for_test("cold-end",10001,10001);let wire:serde_json::Value=serde_json::from_slice(&output).unwrap();let rows=wire["diagnostics"].as_array().unwrap();assert_eq!(rows.len(),10001);assert!(rows.iter().all(|row|row["phase"]=="must_be_pure"));assert_eq!(wire["target_windows_exhausted"],true);assert_eq!(wire["full_checker_parity"],false);assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1);assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(26)),0);assert_eq!(db.effect_retained_values_for_test(dm_query::Kind(27)),0);assert_eq!(db.effect_graph_work_for_test(),0);let bodies=db.db().stats(dm_query::Kind(4)).computed;let before_reads=reads.load(std::sync::atomic::Ordering::Relaxed);let mut warm=Vec::new();db.trace_effect_phase_for_test("warm-begin",0,10001);snapshot.write_native_effect_reports_exhausted(&input,64,dm_analysis::checker_effects::MAX_EVENTS,&env(),None,&snapshot.tree,&mut warm).unwrap();db.trace_effect_phase_for_test("warm-end",10001,10001);assert_eq!(warm,output);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,bodies,"large warm reporting must reuse detached page facts after syntax retirement");assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1);assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1);assert_eq!(reads.load(std::sync::atomic::Ordering::Relaxed),before_reads);}


fn actual_effect_daemon_request(snapshot:&SourceSnapshot,questions:Vec<crate::daemon::query::SourceQuery>)->crate::daemon::query::QueryRequest{crate::daemon::query::QueryRequest{timeout_seconds:Some(300),project:env(),defines:Default::default(),engine_template:None,bootstrap_catalog:false,expected_revision:Some(format!("{:032x}",snapshot.tree.identity())),expected_source_revision:Some(format!("{:032x}",snapshot.source_revision)),expected_policy_revision:Some(format!("{:032x}",snapshot.policy_revision.unwrap())),queries:vec![],source_queries:questions}}
fn actual_effect_question()->crate::daemon::query::SourceQuery{crate::daemon::query::SourceQuery::NativeEffectReports{environment:env(),configuration:None,page_width:2,target_window:1}}
#[test]
fn actual_source_effect_request_preserves_configured_family_rows_and_same_retained_native_frame_between_distinct_queries(){use crate::daemon::query::{self,SourceQuery};let source="var/global_value=0\n/proc/check()\n    set SpacemanDMM_should_be_pure=1\n    set SpacemanDMM_should_not_sleep=1\n    if(1)\n        global_value++\n    sleep(1)\n";let(snapshot,reads)=fixture(source,Some(b"[diagnostics]\nmust_be_pure='warning'\nmust_not_sleep='off'\ncontrol_condition_static='hint'\n"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let families=vec!["control_condition_static".to_owned()];let mut expected_control=Vec::new();snapshot.write_native_configured_control_batch(0,&families,&env(),None,&tree,&mut expected_control).unwrap();let request=actual_effect_daemon_request(&snapshot,vec![SourceQuery::NativeConfiguredControlBatch{ordinal:0,families,environment:env(),configuration:None},actual_effect_question()]);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let first=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&first).unwrap();let rows=first.jsonl.lines().map(|line|serde_json::from_str::<serde_json::Value>(line).unwrap()).collect::<Vec<_>>();assert_eq!(rows.len(),2);assert_eq!(rows[0],serde_json::from_slice::<serde_json::Value>(&expected_control).unwrap());assert_eq!(rows[0]["diagnostics"][0]["severity"],"hint");assert_eq!(rows[1]["configuration_present"],true);assert_eq!(rows[1]["configuration_explicit"],false);assert_eq!(rows[1]["target_windows_exhausted"],true);assert_eq!(rows[1]["full_checker_parity"],false);let effects=rows[1]["diagnostics"].as_array().unwrap();assert!(!effects.is_empty());assert!(effects.iter().all(|row|row["phase"]!="must_not_sleep"));assert!(effects.iter().filter(|row|row["phase"]=="must_be_pure").all(|row|row["severity"]=="warning"));let counts=(4..=27).map(|kind|db.db().stats(dm_query::Kind(kind)).computed).collect::<Vec<_>>();let io=reads.load(Ordering::Relaxed);let fixed=db.effect_request_input_charge_for_test();assert!(fixed>0);let second_request=request.clone();let second=query::evaluate_snapshot(&second_request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&second_request,&second).unwrap();assert_eq!(first.jsonl,second.jsonl);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,counts[0]);assert_eq!((24..=25).map(|kind|db.db().stats(dm_query::Kind(kind)).computed).collect::<Vec<_>>(),counts[20..22]);assert_eq!(reads.load(Ordering::Relaxed),io);assert_eq!(db.effect_request_input_charge_for_test(),fixed);assert_eq!(db.effect_graph_work_for_test(),0);let mut stale=request;stale.expected_source_revision=Some("0".repeat(32));assert!(query::evaluate_snapshot(&stale,&tree,&state).is_err());}
#[test]
fn actual_effect_request_fixed_input_denial_first_kind4_io_and_cancellation_never_deliver_a_partial_reply(){use crate::daemon::query;let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme"),None);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=actual_effect_daemon_request(&snapshot,vec![actual_effect_question()]);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let quota=db.effect_storage_limit_for_test(1);let error=query::evaluate_snapshot(&request,&tree,&state).err().unwrap();assert_eq!(error.kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(db.effect_request_input_charge_for_test(),0);assert!(state.snapshot.as_ref().unwrap().native_effect_request_input.get().is_none());drop(quota);let schedule=db.fail_body_syntax_after_for_test(0,std::io::Error::from_raw_os_error(1450));let error=query::evaluate_snapshot(&request,&tree,&state).err().unwrap();assert_eq!(error.raw_os_error(),Some(1450),"{error:?}");assert_eq!(db.db().stats(dm_query::Kind(26)).computed,0);assert_eq!(db.effect_graph_work_for_test(),0);drop(schedule);let recovered=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&recovered).unwrap();let fixed=db.effect_request_input_charge_for_test();let quota=db.effect_storage_limit_for_test(1);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);assert_eq!(db.effect_request_input_charge_for_test(),fixed,"operation denial/reset preserves the live fixed owner");drop(quota);let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);let retry=query::evaluate_snapshot(&request,&tree,&state).unwrap();assert_eq!(retry.jsonl,recovered.jsonl);let(foreign_equal,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme"),None);assert!(state.snapshot.as_ref().unwrap().write_native_effect_request(2,1,&env(),None,&foreign_equal.tree,&mut Vec::new()).is_err(),"equal source cannot replace actual retained tree/host owner");let(foreign,_)=fixture("/proc/another(i)\n    set SpacemanDMM_should_be_pure=1\n    i++\n",None);let other_tree=foreign.tree.clone();let foreign_state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(foreign),last_request_outcome:"analyzed",publication_pair:None};assert!(query::evaluate_snapshot(&request,&other_tree,&foreign_state).is_err());}
#[test]
fn request_input_owner_frees_before_credit_while_escaped_report_storage_remains_funded(){use dm_analysis::checker_effects::EffectReportPhase::Purity;let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme"),None);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();snapshot.write_native_effect_request(2,1,&env(),None,&snapshot.tree,&mut Vec::new()).unwrap();let input=snapshot.native_effect_request_input.get().unwrap().input.as_ref().unwrap();let escaped=snapshot.native_effect_source_report(input,2,Purity,&env(),None,&snapshot.tree).unwrap();let retained=escaped.retained_charge().unwrap();assert!(db.effect_request_input_charge_for_test()>0);dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert!(db.effect_request_input_charge_for_test()>0,"revision/pruning cannot clear actual retained request owner");drop(snapshot);assert_eq!(db.effect_request_input_charge_for_test(),0);assert!(!escaped.is_empty());dm_tree::frontend::BodySyntaxQueries::begin_revision(db.as_ref());assert!(db.purity_cache_probe().2>=retained,"escaped report message/note and fixed Weak backing retain their separate physical lease");drop(escaped);assert_eq!(db.purity_cache_probe().2,0);assert_eq!(db.effect_graph_work_for_test(),0);}

#[test]fn actual_effect_byte_requests_reassemble_identical_encoder_across_distinct_queries_without_new_graph_body_or_io(){use crate::daemon::query::{self,SourceQuery,encoded_bytes::{Continuity,Fragment}};let(snapshot,reads)=fixture("var/global_value=0\n/proc/check()\n    set SpacemanDMM_should_be_pure=1\n    global_value++\n",Some(b"[diagnostics]\nmust_be_pure='warning'\n"));let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let mut original=Vec::new();snapshot.write_native_effect_request(2,1,&env(),None,&tree,&mut original).unwrap();let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let counts=(db.db().stats(dm_query::Kind(4)).computed,db.db().stats(dm_query::Kind(24)).computed,db.db().stats(dm_query::Kind(25)).computed);let io=reads.load(Ordering::Relaxed);let fixed=db.effect_request_input_charge_for_test();let mut sequence=Continuity::new(64*1024*1024);let mut result=Vec::new();let mut cursor=None;loop{let request=actual_effect_daemon_request(state.snapshot.as_ref().unwrap(),vec![SourceQuery::NativeEffectReportBytes{environment:env(),configuration:None,page_width:2,target_window:1,cursor,limit:127}]);let reply=query::evaluate_snapshot(&request,&tree,&state).unwrap();query::validate_effect_batch_for_test(&request,&reply).unwrap();let row:serde_json::Value=serde_json::from_str(reply.jsonl.trim()).unwrap();let fragment:Fragment=serde_json::from_value(row["fragment"].clone()).unwrap();let bytes:Vec<u8>=serde_json::from_value(row["bytes"].clone()).unwrap();cursor=sequence.accept(fragment,&bytes,&mut result).unwrap();assert_eq!(db.effect_graph_work_for_test(),0);if cursor.is_none(){break}}sequence.finish().unwrap();assert_eq!(result,original);assert_eq!(counts,(db.db().stats(dm_query::Kind(4)).computed,db.db().stats(dm_query::Kind(24)).computed,db.db().stats(dm_query::Kind(25)).computed));assert_eq!(reads.load(Ordering::Relaxed),io);assert_eq!(db.effect_request_input_charge_for_test(),fixed);}
#[test]fn actual_effect_byte_requests_preserve_source_io_quota_cancellation_and_cursor_refusal_before_reply(){use crate::daemon::query::{self,SourceQuery,encoded_bytes::ByteCursor};let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme"),None);let db=snapshot.native_raw_queries.as_ref().unwrap().clone();let tree=snapshot.tree.clone();let request=actual_effect_daemon_request(&snapshot,vec![SourceQuery::NativeEffectReportBytes{environment:env(),configuration:None,page_width:2,target_window:1,cursor:None,limit:127}]);let state=crate::runner_host::query_snapshot::QueryState{snapshot:Some(snapshot),last_request_outcome:"analyzed",publication_pair:None};let schedule=db.fail_body_syntax_after_for_test(0,std::io::Error::from_raw_os_error(1450));assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().raw_os_error(),Some(1450));drop(schedule);let good=query::evaluate_snapshot(&request,&tree,&state).unwrap();let row:serde_json::Value=serde_json::from_str(good.jsonl.trim()).unwrap();let cursor:ByteCursor=serde_json::from_value(row["fragment"]["next"].clone()).unwrap();let mut wrong=request.clone();if let SourceQuery::NativeEffectReportBytes{cursor:slot,..}=&mut wrong.source_queries[0]{let mut other=cursor;other.total+=1;*slot=Some(other);}assert!(query::evaluate_snapshot(&wrong,&tree,&state).is_err());let quota=db.effect_storage_limit_for_test(1);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),std::io::ErrorKind::OutOfMemory);drop(quota);let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));token.cancel();assert_eq!(query::evaluate_snapshot(&request,&tree,&state).err().unwrap().kind(),std::io::ErrorKind::Interrupted);drop(guard);assert_eq!(query::evaluate_snapshot(&request,&tree,&state).unwrap().jsonl,good.jsonl);let mut stale=request;stale.expected_source_revision=Some("0".repeat(32));assert!(query::evaluate_snapshot(&stale,&tree,&state).is_err());assert_eq!(db.effect_graph_work_for_test(),0);}

#[test]fn actual_effect_fragment_final_serialization_cancellation_never_completes_delivery(){use std::io::Write;let(snapshot,_)=fixture(include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme"),None);let tree=snapshot.tree.clone();let token=crate::daemon::control::Cancellation::default();let guard=crate::daemon::control::bind_with_deadline(token.clone(),std::time::Instant::now()+std::time::Duration::from_secs(30));struct StagedCancellation(crate::daemon::control::Cancellation);impl Write for StagedCancellation{fn write(&mut self,bytes:&[u8])->std::io::Result<usize>{self.0.cancel();Ok(bytes.len())}fn flush(&mut self)->std::io::Result<()>{Ok(())}}let error=snapshot.write_native_effect_byte_request(2,1,None,127,&env(),None,&tree,&mut StagedCancellation(token)).unwrap_err();assert_eq!(error.kind(),std::io::ErrorKind::Interrupted);drop(guard);let mut healthy=Vec::new();snapshot.write_native_effect_byte_request(2,1,None,127,&env(),None,&tree,&mut healthy).unwrap();assert!(!healthy.is_empty());assert_eq!(snapshot.native_raw_queries.as_ref().unwrap().effect_graph_work_for_test(),0);}

#[test]fn actual_report_page_cache_reuses_detached_facts_after_syntax_retirement_and_unrelated_revision(){use std::fmt::Write;let mut source=String::new();for at in 0..129{writeln!(&mut source,"/proc/page_reuse_{at}(i)\n    set SpacemanDMM_should_be_pure=1\n    i++").unwrap();}let(snapshot,reads)=fixture(&source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let mut first=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,64,128,&env(),None,&snapshot.tree,&mut first).unwrap();let decoded:serde_json::Value=serde_json::from_slice(&first).unwrap();assert_eq!(decoded["diagnostics"].as_array().unwrap().len(),129);let bodies=db.db().stats(dm_query::Kind(4)).computed;let pages=db.db().stats(dm_query::Kind(23)).computed;assert!(pages<=9,"graph count/fill and one retained report page walk suffice, got {pages}");let body=input.archive().syntax_inputs().unwrap()[0].clone();let child=dm_query::Key::new(dm_query::Kind(4),body.key().into());assert!(db.db().dependants(&[child]).iter().any(|key|key.kind==dm_query::Kind(23)));db.db().evict_values(&[dm_query::Kind(4)]);db.db().set_input(dm_query::Key::new(dm_query::Kind(240),4321),1usize,1);let before=reads.load(Ordering::Relaxed);let mut warm=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,64,128,&env(),None,&snapshot.tree,&mut warm).unwrap();assert_eq!(first,warm);assert_eq!(db.db().stats(dm_query::Kind(4)).computed,bodies,"detached page answers must not demand evicted syntax values");assert_eq!(db.db().stats(dm_query::Kind(23)).computed,pages,"unchanged hashes preserve the original current page result");assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1);assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1);assert_eq!(reads.load(Ordering::Relaxed),before);assert_eq!(db.effect_graph_work_for_test(),0);}
#[test]fn actual_report_page_pressure_retires_only_unloaned_values_keeps_hash_edges_and_escaped_page_funding(){use std::fmt::Write;let mut source=String::new();for at in 0..129{writeln!(&mut source,"/proc/page_pressure_{at}(i)\n    set SpacemanDMM_should_be_pure=1\n    i++").unwrap();}let(snapshot,reads)=fixture(&source,None);let input=snapshot.native_effect_source_input(&snapshot.tree).unwrap();let db=snapshot.native_raw_queries.as_ref().unwrap();let mut expected=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,64,128,&env(),None,&snapshot.tree,&mut expected).unwrap();let escaped=snapshot.native_effect_source_page(&input,0,64,&env(),None,&snapshot.tree).unwrap();let prior=db.db().stats(dm_query::Kind(23)).computed;let body=input.archive().syntax_inputs().unwrap()[64].clone();let child=dm_query::Key::new(dm_query::Kind(4),body.key().into());let dependencies=db.db().dependants(&[child]);assert!(dependencies.iter().any(|key|key.kind==dm_query::Kind(23)));let pressure=db.hold_effect_page_cache_pressure_for_test().unwrap();let mut actual=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,64,128,&env(),None,&snapshot.tree,&mut actual).unwrap();assert_eq!(expected,actual);assert!(db.db().stats(dm_query::Kind(23)).computed>prior,"real family pressure must retire consumed PAGE values");assert_eq!(db.db().dependants(&[child]),dependencies,"physical retirement keeps original graph dependencies");let still=snapshot.native_effect_source_page(&input,0,64,&env(),None,&snapshot.tree).unwrap();assert!(Arc::ptr_eq(&escaped,&still),"an actual escaped page stays physically owned and current");drop(still);assert!(db.effect_graph_work_for_test()>0);drop(pressure);assert_eq!(db.effect_graph_work_for_test(),0);let before=reads.load(Ordering::Relaxed);let mut recovered=Vec::new();snapshot.write_native_effect_reports_exhausted(&input,64,128,&env(),None,&snapshot.tree,&mut recovered).unwrap();assert_eq!(recovered,expected);assert_eq!(reads.load(Ordering::Relaxed),before);assert_eq!(db.db().stats(dm_query::Kind(24)).computed,1);assert_eq!(db.db().stats(dm_query::Kind(25)).computed,1);assert_eq!(escaped.len(),64);}
