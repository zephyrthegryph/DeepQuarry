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
    let intent = PolicyInputRequest {
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
fn unsupported_effect_contexts_are_not_clean_reports_and_multi_target_is_explicit() {
    for(source,needle)in[("/proc/probe()\n    set SpacemanDMM_should_be_pure=1\n    CRASH(\"bad\")\n","effect"),("/proc/a()\n    set SpacemanDMM_should_be_pure=1\n    return 1\n/proc/b()\n    set SpacemanDMM_should_be_pure=1\n    return 2\n","multi-target")]{let(snapshot,_)=fixture(source,None);let input=snapshot.native_purity_input(&snapshot.tree).unwrap();let error=snapshot.native_purity_report(&input,&env(),None,&snapshot.tree).unwrap_err();assert!(error.to_string().contains(needle),"{error}");}
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
