use super::*;
use dm_ir::{ResolveQuery as Q, ResolvedMeaning as M, Resolver, SymbolId};
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn finite_callable_exclusion_tracks_removal_move_and_shadow() {
    let mut build_host = crate::runner_host::BuildHost::default();
    let engine = build_host
        .engine(
            "fallback.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let retained = build_host.host_facts().unwrap();
    let semantic = std::cell::RefCell::new(dm_tree::frontend::RetainedSemanticTree::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |text| {
        dm_tree::frontend::build_with_executor_and_semantic_state(
            std::path::Path::new("fallback.dme"),
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
    let query = Q::GlobalProc(SymbolId::of("member_only"));
    // A nonretained tree has no issued name-specific root absence token.
    // A finite engine exclusion alone must not invent that source authority.
    let bare = dm_tree::frontend::build_with_config(
        std::path::Path::new("fallback.dme"),
        &Source("/datum/probe/proc/member_only()\n    return 1\n"),
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: Some(engine.frontend_seed()),
            observer: None,
        },
    )
    .unwrap();
    let (bare_host, _) = prepare_retained(&bare, &engine, Some(&retained)).unwrap();
    assert_eq!(bare_host.resolve(query), M::Missing);
    assert_eq!(bare_host.domain_version(query.domain()), None);
    let first = build("/datum/probe/proc/member_only()\n    return 1\n");
    let (first_host, _) = prepare_retained(&first, &engine, Some(&retained)).unwrap();
    assert_eq!(first_host.resolve(query), M::Missing);
    let first_version = first_host
        .domain_version(query.domain())
        .expect("finite current exclusion");
    // These bytes are the exact answer projection used by persisted read replay;
    // process-local domain versions never authorize disk answers.
    let persisted_answer = first_host.resolve(query).canonical_bytes();
    let root = std::path::PathBuf::from("E:/dq-cache/dmb-native-v2/callable-fallback-tests")
        .join(format!("{}-{}", std::process::id(), first_version));
    std::fs::create_dir_all(&root).unwrap();
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let disk_key = dm_cache::RecordKey {
        stage: 900,
        version: 1,
        content: first_version,
    };
    cache
        .publish(&[dm_cache::Record {
            key: disk_key,
            symbols: vec![],
            payload: Arc::from(persisted_answer.clone()),
        }])
        .unwrap();
    let snapshot = cache.snapshot().unwrap();
    let disk_accepts = |host: &dyn Resolver| {
        snapshot
            .get_candidate(disk_key, |payload, _| {
                Ok(payload == host.resolve(query).canonical_bytes())
            })
            .is_some()
    };
    assert!(disk_accepts(&first_host));
    let moved = build("/datum/other/proc/member_only()\n    return 2\n");
    let (moved_host, _) = prepare_retained(&moved, &engine, Some(&retained)).unwrap();
    assert_eq!(
        moved_host.resolve(query).canonical_bytes(),
        persisted_answer
    );
    assert_eq!(
        moved_host.domain_version(query.domain()),
        Some(first_version)
    );
    let shadowed = build("/proc/member_only()\n    return 3\n");
    let (shadowed_host, _) = prepare_retained(&shadowed, &engine, Some(&retained)).unwrap();
    assert!(matches!(shadowed_host.resolve(query), M::Member { .. }));
    assert_ne!(
        shadowed_host.resolve(query).canonical_bytes(),
        persisted_answer
    );
    assert_ne!(
        shadowed_host.domain_version(query.domain()),
        Some(first_version)
    );
    let removed = build("/datum/probe\n");
    let (removed_host, _) = prepare_retained(&removed, &engine, Some(&retained)).unwrap();
    assert!(matches!(removed_host.resolve(query), M::Unsupported(_)));
    assert_eq!(removed_host.domain_version(query.domain()), None);
    assert_ne!(
        removed_host.resolve(query).canonical_bytes(),
        persisted_answer
    );
    assert!(!disk_accepts(&removed_host));
    for name in ["never_authored_name", "sin"] {
        let query = Q::GlobalProc(SymbolId::of(name));
        assert_eq!(removed_host.domain_version(query.domain()), None);
    }
    drop(snapshot);
    drop(cache);
    std::fs::remove_dir_all(&root).unwrap();
    // The old host cannot repopulate an excluded current roster after removal.
    assert_eq!(first_host.domain_version(query.domain()), None);
}

#[test]
fn procedure_memo_executable_disk_replay_rejects_last_name_removal_and_shadow() {
    use crate::lowering_memo::{ProcedureMemo, RecordingResolver};
    let mut build_host = crate::runner_host::BuildHost::default();
    let engine = build_host
        .engine(
            "fallback-disk.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let retained = build_host.host_facts().unwrap();
    let semantic = std::cell::RefCell::new(dm_tree::frontend::RetainedSemanticTree::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let build = |text| {
        dm_tree::frontend::build_with_executor_and_semantic_state(
            std::path::Path::new("fallback-disk.dme"),
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
    let first = build("/datum/probe/proc/member_only()\n    return 1\n");
    let (first_host, _) = prepare_retained(&first, &engine, Some(&retained)).unwrap();
    let query = Q::GlobalProc(SymbolId::of("member_only"));
    let recorder = RecordingResolver::new(&first_host);
    assert_eq!(recorder.resolve(query), M::Missing);
    let reads = recorder.reads();
    let versions = recorder.domain_receipts();
    assert!(versions.iter().any(|(domain, _)| *domain == query.domain()));
    assert!(
        !query.domain().persistent_version(),
        "process-local certificate must not enter disk wire"
    );
    let ast = dm_syntax::parse("/proc/probe()\n    return 7\n");
    let code = dm_codegen_byond::compile_simple_proc_with_resolver(
        &ast.items[0].children,
        &Default::default(),
        &Default::default(),
        &recorder,
    )
    .unwrap();
    let token = first_host.domain_version(query.domain()).unwrap();
    let root = std::path::PathBuf::from("E:/dq-cache/dmb-native-v2/callable-fallback-tests")
        .join(format!("procedure-{}-{token}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let writer = ProcedureMemo::with_disk_only(77, cache.snapshot().unwrap());
    let key = b"finite-callable-negative-executable";
    writer.remember_executable(key, &reads, &code, &versions);
    let records = writer.take_pending();
    assert_eq!(
        records.len(),
        1,
        "real ProcedureMemo population must encode this result"
    );
    let inner = dm_cache::decode_variants(&records[0].payload).unwrap()[0].to_vec();
    crate::lowering_memo_wire::validate(&inner)
        .expect("real executable wire must decode structurally");
    assert_eq!(
        crate::lowering_memo_wire::decode_executable(&inner, key, &first_host, 0)
            .expect("initial exact host must admit before persistence")
            .procedure,
        code.procedure
    );
    cache.publish(&records).unwrap();
    drop(writer);
    drop(records);
    // A newly created memo has no resident result and uses the production typed
    // candidate decoder, read replay, and executable hydration path.
    let reader = ProcedureMemo::with_disk_only(77, cache.snapshot().unwrap());
    let replay = reader.lookup_anonymous(key, &first_host, 0);
    assert_eq!(replay.code.unwrap().procedure, code.procedure);
    assert!(replay.errors.is_none());
    let moved = build("/datum/other/proc/member_only()\n    return 2\n");
    let (moved_host, _) = prepare_retained(&moved, &engine, Some(&retained)).unwrap();
    assert_eq!(
        reader
            .lookup_anonymous(key, &moved_host, 0)
            .code
            .unwrap()
            .procedure,
        code.procedure
    );
    for text in ["/proc/member_only()\n    return 3\n", "/datum/probe\n"] {
        let current = build(text);
        let (host, _) = prepare_retained(&current, &engine, Some(&retained)).unwrap();
        let replay = reader.lookup_anonymous(key, &host, 0);
        assert!(
            replay.code.is_none() && replay.errors.is_none(),
            "changed finite negative cannot replay"
        );
    }
    assert_eq!(reader.counts.disk_hits.load(Ordering::Relaxed), 2);
    drop(reader);
    drop(cache);
    std::fs::remove_dir_all(&root).unwrap();
}

#[test]
fn actual_cached_failure_revalidates_member_global_and_deleted_callable() {
    use crate::lowering::{lower_frontend_with_memo, lower_frontend_with_statics, LoweringConfig};
    use crate::lowering_memo::ProcedureMemo;
    const UNKNOWN: &str = "/proc/probe()\n    return formerly_missing()\n";
    const MEMBER: &str = "/proc/probe()\n    return formerly_missing()\n/datum/a/proc/formerly_missing()\n    return 7\n";
    const GLOBAL: &str = "/proc/probe()\n    return formerly_missing()\n/datum/a/proc/formerly_missing()\n    return 7\n/proc/formerly_missing()\n    return 7\n";
    let mut build_host = crate::runner_host::BuildHost::default();
    let engine = build_host
        .engine(
            "failure-transitions.dme".into(),
            Default::default(),
            true,
            include_bytes!("../../../fixtures/native_template.bin").to_vec(),
        )
        .unwrap();
    let retained = build_host.host_facts().unwrap();
    let semantic = std::cell::RefCell::new(dm_tree::frontend::RetainedSemanticTree::default());
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let root = std::path::PathBuf::from("E:/dq-cache/dmb-native-v2/callable-fallback-tests").join(
        format!(
            "failure-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ),
    );
    std::fs::create_dir_all(&root).unwrap();
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let run = |text, memo: &ProcedureMemo| {
        let frontend = dm_tree::frontend::build_with_executor_and_semantic_state(
            std::path::Path::new("failure-transitions.dme"),
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
        .unwrap();
        let (facts, _) = prepare_retained(&frontend, &engine, Some(&retained)).unwrap();
        let startup = crate::startup::capture(&frontend).unwrap();
        let host = startup.resolver(&frontend, &facts).unwrap();
        let abi = crate::driver_facts::prepare_pinned_source_abi(
            &frontend,
            &engine.snapshot,
            &host,
            None,
            1,
        )
        .unwrap();
        assert!(
            abi.prepared.diagnostics.is_empty(),
            "{:?}",
            abi.prepared.diagnostics
        );
        let policy =
            crate::driver_facts::FrozenPreparedPolicy::new(&frontend, &abi.prepared).unwrap();
        let actual = lower_frontend_with_memo(
            &frontend,
            &host,
            &policy,
            LoweringConfig::default(),
            &startup,
            memo,
        );
        let fresh = lower_frontend_with_statics(
            &frontend,
            &host,
            &policy,
            LoweringConfig::default(),
            &startup,
        );
        // Include every current source coordinate and diagnostic identity, not
        // only the text: persisted failures must bind to the current revision.
        let diagnostics = |batch: &crate::lowering::LoweringBatch| {
            batch
                .diagnostics
                .iter()
                .map(|d| format!("{:?}|{:?}|{:?}|{}", d.kind, d.identity, d.origin, d.message))
                .collect::<Vec<_>>()
        };
        assert_eq!(diagnostics(&actual), diagnostics(&fresh));
        assert_eq!(actual.units.len(), fresh.units.len());
        for (actual, fresh) in actual.units.iter().zip(&fresh.units) {
            assert_eq!(actual.identity, fresh.identity);
            assert_eq!(actual.code.procedure, fresh.code.procedure);
            assert_eq!(actual.code.slots, fresh.code.slots);
            assert_eq!(actual.code.procedure_values, fresh.code.procedure_values);
            assert_eq!(actual.code.procedure_statics, fresh.code.procedure_statics);
            assert_eq!(actual.code.resources, fresh.code.resources);
        }
        let query = Q::GlobalProc(SymbolId::of("formerly_missing"));
        (actual, facts.resolve(query).canonical_bytes())
    };
    let writer = ProcedureMemo::with_disk(91, cache.snapshot().unwrap());
    let (initial, unknown_answer) = run(UNKNOWN, &writer);
    assert!(
        !initial.diagnostics.is_empty(),
        "unknown call must really fail lowering"
    );
    let records = writer.take_pending();
    assert!(
        !records.is_empty(),
        "actual failure must populate disk cache"
    );
    cache.publish(&records).unwrap();
    drop(records);
    drop(writer);
    let reader = ProcedureMemo::with_disk(91, cache.snapshot().unwrap());
    let before = reader.counts.disk_hits.load(Ordering::Relaxed);
    let (replayed, _) = run(UNKNOWN, &reader);
    assert!(!replayed.diagnostics.is_empty());
    assert!(
        reader.counts.disk_hits.load(Ordering::Relaxed) > before,
        "unchanged actual failure must traverse persisted replay"
    );
    let (member, missing_answer) = run(MEMBER, &reader);
    assert!(!member.diagnostics.is_empty());
    assert_ne!(
        unknown_answer, missing_answer,
        "finite member coverage changes the negative answer"
    );
    let (global, positive_answer) = run(GLOBAL, &reader);
    assert!(global.diagnostics.is_empty(), "{:?}", global.diagnostics);
    assert_ne!(missing_answer, positive_answer);
    let before = reader.counts.resident_hits.load(Ordering::Relaxed);
    let (unchanged, _) = run(GLOBAL, &reader);
    assert!(unchanged.diagnostics.is_empty());
    assert!(reader.counts.resident_hits.load(Ordering::Relaxed) > before);
    let records = reader.take_pending();
    assert!(!records.is_empty());
    cache.publish(&records).unwrap();
    drop(records);
    // Deletion must reject resident success, and a newly opened memo must also
    // reject the persisted positive candidate before replaying a valid failure.
    let (deleted, _) = run(UNKNOWN, &reader);
    assert!(!deleted.diagnostics.is_empty());
    let disk_reader = ProcedureMemo::with_disk(91, cache.snapshot().unwrap());
    let (disk_deleted, _) = run(UNKNOWN, &disk_reader);
    assert!(!disk_deleted.diagnostics.is_empty());
    drop(disk_reader);
    drop(reader);
    drop(cache);
    std::fs::remove_dir_all(&root).unwrap();
}
