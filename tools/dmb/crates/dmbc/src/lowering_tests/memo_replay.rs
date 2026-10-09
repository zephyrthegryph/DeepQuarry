use super::*;

#[test]
fn procedure_memo_reuses_resident_and_disk_and_rebases_shifted_origins() {
    let source = "/proc/first()\n    return 1\n/proc/second()\n    return 2\n";
    let frontend = frontend(source);
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let root = std::env::temp_dir().join(format!(
        "dmbc-lowering-memo-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::with_disk(11, cache.snapshot().unwrap());
    let cold = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
    let warm = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert_eq!(
        memo.counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert_eq!(cold.units[0].code.procedure, warm.units[0].code.procedure);
    let records = memo.take_pending();
    assert_eq!(records.len(), 2);
    cache.publish(&records).unwrap();
    let restarted = crate::lowering_memo::ProcedureMemo::with_disk(11, cache.snapshot().unwrap());
    let disk = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &restarted,
    );
    assert!(disk.diagnostics.is_empty());
    assert_eq!(
        restarted
            .counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert_eq!(cold.units[0].code.procedure, disk.units[0].code.procedure);
    assert_eq!(cold.units[0].debug_origins, disk.units[0].debug_origins);
    let moved = super::frontend("\n/proc/first()\n    return 1\n/proc/second()\n    return 2\n");
    let moved_startup = crate::startup::capture(&moved).unwrap();
    let moved_host = moved_startup
        .resolver(&moved, moved.snapshot.tree.as_ref())
        .unwrap();
    let moved_batch = lower_frontend_with_memo(
        &moved,
        &moved_host,
        &NoParameters,
        LoweringConfig::default(),
        &moved_startup,
        &restarted,
    );
    assert!(moved_batch.diagnostics.is_empty());
    assert_eq!(
        restarted
            .counts
            .recomputed
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    assert_eq!(
        restarted
            .counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    // Validated disk results are promoted without being published again. The
    // shifted revision must replay those resident records and rebase origins.
    assert_eq!(
        restarted
            .counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert!(restarted.take_pending().is_empty());
    assert_eq!(
        cold.units[0].code.procedure,
        moved_batch.units[0].code.procedure
    );
    for (old, new) in cold.units[0]
        .debug_origins
        .entries
        .iter()
        .zip(&moved_batch.units[0].debug_origins.entries)
    {
        assert_eq!(old.semantic_path, new.semantic_path);
        assert_eq!(old.line + 1, new.line);
    }
    // Cleanup only the freshly-created absolute task directory.
    let bounded_cache =
        dm_cache::Cache::open(root.join("bounded"), dm_cache::Limits::default()).unwrap();
    let bounded = crate::lowering_memo::ProcedureMemo::with_disk_limits(
        11,
        bounded_cache.snapshot().unwrap(),
        crate::lowering_memo::MemoLimits {
            pending_bytes: 1,
            resident_bytes: 1,
        },
    );
    let bounded_batch = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &bounded,
    );
    assert!(bounded_batch.diagnostics.is_empty());
    assert_eq!(bounded.pending_bytes(), 0);
    assert_eq!(bounded.values.admitted_bytes(), 0);
    assert_eq!(
        bounded
            .counts
            .pending_dropped
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    // Queue pressure flushes records instead of skipping memo population.
    assert_eq!(
        bounded
            .counts
            .published_records
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert_eq!(
        bounded
            .counts
            .publication_failed
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    let flushed =
        crate::lowering_memo::ProcedureMemo::with_disk(11, bounded_cache.snapshot().unwrap());
    let replayed = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &flushed,
    );
    assert!(
        replayed.diagnostics.is_empty(),
        "{:?}",
        replayed.diagnostics
    );
    assert_eq!(
        flushed
            .counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert_eq!(
        flushed
            .counts
            .recomputed
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    assert_eq!(
        bounded
            .counts
            .resident_dropped
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn procedure_memo_reuses_when_another_include_moves_only_expanded_arena_offsets() {
    struct Files {
        before: &'static str,
    }
    impl dm_preprocess::SourceProvider for Files {
        fn read(&self, path: &Path) -> Result<String, String> {
            Ok(match path.file_name().unwrap().to_str().unwrap() {
                "project.dme" => "#include \"before.dm\"\n#include \"body.dm\"\n",
                "before.dm" => self.before,
                "body.dm" => "/proc/first()\n    return 1\n",
                _ => return Err("unknown input".into()),
            }
            .into())
        }
    }
    let original = dm_tree::frontend::build(
        Path::new("project.dme"),
        &Files { before: "" },
        &BTreeMap::new(),
        1,
    )
    .unwrap();
    let shifted = dm_tree::frontend::build(
        Path::new("project.dme"),
        &Files {
            before: "/proc/earlier()\n    return 2\n",
        },
        &BTreeMap::new(),
        1,
    )
    .unwrap();
    let first_startup = crate::startup::capture(&original).unwrap();
    let first_host = first_startup
        .resolver(&original, original.snapshot.tree.as_ref())
        .unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(14);
    let first = lower_frontend_with_memo(
        &original,
        &first_host,
        &NoParameters,
        LoweringConfig::default(),
        &first_startup,
        &memo,
    );
    assert!(first.diagnostics.is_empty());
    let shifted_startup = crate::startup::capture(&shifted).unwrap();
    let shifted_host = shifted_startup
        .resolver(&shifted, shifted.snapshot.tree.as_ref())
        .unwrap();
    let second = lower_frontend_with_memo(
        &shifted,
        &shifted_host,
        &NoParameters,
        LoweringConfig::default(),
        &shifted_startup,
        &memo,
    );
    assert!(second.diagnostics.is_empty());
    assert_eq!(
        memo.counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        1
    );
    let reused = second
        .units
        .iter()
        .find(|unit| unit.identity.name == SymbolId::of("first"))
        .unwrap();
    assert_ne!(
        first.units[0].origin.expanded_span,
        reused.origin.expanded_span
    );
    assert_eq!(reused.code.procedure, first.units[0].code.procedure);
    assert_eq!(reused.debug_origins, first.units[0].debug_origins);
    assert_eq!(
        reused.origin.expanded_span,
        shifted
            .bodies
            .iter()
            .find(|body| shifted
                .snapshot
                .tree
                .member(body.member)
                .is_some_and(|member| member.name == SymbolId::of("first")))
            .unwrap()
            .expanded_span
    );
}
#[test]
fn procedure_memo_replays_macro_diagnostics_at_current_origins_in_worker_order() {
    struct Included(bool);
    impl dm_preprocess::SourceProvider for Included {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name|name.to_str()) {
                Some("project.dme")=>Ok("#include \"body.dm\"\n".into()),
                Some("body.dm")=>Ok(format!("{}#define BAD missing_call()\n/proc/first()\n    if(1)\n        return BAD\n/proc/second()\n    return BAD\n",if self.0{"\n"}else{""})),
                _=>Err("unexpected source".into()),
            }
        }
    }
    let build = |shifted| {
        dm_tree::frontend::build(
            Path::new("project.dme"),
            &Included(shifted),
            &BTreeMap::new(),
            1,
        )
        .unwrap()
    };
    let first = build(false);
    let moved = build(true);
    let root = std::env::temp_dir().join(format!(
        "dmbc-diagnostic-memo-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::with_disk(41, cache.snapshot().unwrap());
    let startup = crate::startup::capture(&first).unwrap();
    let host = startup.resolver(&first, &Host).unwrap();
    let cold = lower_frontend_with_memo(
        &first,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert_eq!(cold.diagnostics.len(), 2);
    let pending = memo.take_pending();
    assert_eq!(pending.len(), 2);
    cache.publish(&pending).unwrap();
    let restarted = crate::lowering_memo::ProcedureMemo::with_disk(41, cache.snapshot().unwrap());
    let startup = crate::startup::capture(&moved).unwrap();
    let host = startup.resolver(&moved, &Host).unwrap();
    let replay = lower_frontend_with_memo(
        &moved,
        &host,
        &NoParameters,
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        &startup,
        &restarted,
    );
    let oracle = lower_frontend_with_statics(
        &moved,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
    );
    assert_eq!(
        restarted
            .counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    for ((old, new), expected) in cold
        .diagnostics
        .iter()
        .zip(&replay.diagnostics)
        .zip(&oracle.diagnostics)
    {
        assert_eq!(old.message, new.message);
        assert_eq!(old.origin.line + 1, new.origin.line);
        assert_eq!(new.kind, expected.kind);
        assert_eq!(new.origin.span, expected.origin.span);
        assert_eq!(
            new.origin.macro_expansions.len(),
            expected.origin.macro_expansions.len()
        );
        assert_eq!(new.origin.include_chain, expected.origin.include_chain);
    }
    assert!(restarted
        .explain()
        .iter()
        .all(|record| record.outcome == crate::lowering_memo::MemoOutcome::DiskHit));
    std::fs::remove_dir_all(root).unwrap();
}
#[test]
fn procedure_memo_keys_current_folded_default_inputs() {
    struct Defaults(u32);
    impl AbiPolicy for Defaults {
        fn inputs(
            &self,
            _: UnitIdentity,
            _: &ProcedureMetadata,
            _: &SymbolTable,
            _: &SourceLocation,
        ) -> Result<ProcedureInputs, String> {
            Ok(ProcedureInputs {
                parameters: vec!["value".into()],
                parameter_defaults: vec![Some(self.0.to_string())],
                ..Default::default()
            })
        }
    }
    let frontend = frontend("/proc/read(value = 1)\n    return value\n");
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::new(19);
    let first = lower_frontend_with_memo(
        &frontend,
        &host,
        &Defaults(1),
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    let changed = lower_frontend_with_memo(
        &frontend,
        &host,
        &Defaults(2),
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert!(first.diagnostics.is_empty(), "{:?}", first.diagnostics);
    assert!(changed.diagnostics.is_empty(), "{:?}", changed.diagnostics);
    assert_eq!(
        memo.counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    assert_eq!(
        memo.counts
            .recomputed
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert_ne!(
        first.units[0].code.procedure,
        changed.units[0].code.procedure
    );
}
