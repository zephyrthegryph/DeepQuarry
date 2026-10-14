use super::*;

#[test]
fn disk_only_memo_publishes_and_replays_without_retaining_rich_ir() {
    let frontend = frontend("/proc/first()\n    return 1\n/proc/second()\n    return 2\n");
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup
        .resolver(&frontend, frontend.snapshot.tree.as_ref())
        .unwrap();
    let root = std::path::PathBuf::from("E:/dq-cache/dmb-disk-only-tests").join(format!(
        "{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let cache = dm_cache::Cache::open(&root, dm_cache::Limits::default()).unwrap();
    let memo = crate::lowering_memo::ProcedureMemo::with_disk_only(71, cache.snapshot().unwrap());
    assert_eq!(
        memo.resident_retention(),
        crate::lowering_memo::ResidentRetention::DiskOnly
    );
    let cold = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &memo,
    );
    assert!(cold.diagnostics.is_empty(), "{:?}", cold.diagnostics);
    assert_eq!(memo.values.admitted_bytes(), 0);
    let records = memo.take_pending();
    assert_eq!(records.len(), 2);
    cache.publish(&records).unwrap();
    let restarted =
        crate::lowering_memo::ProcedureMemo::with_disk_only(71, cache.snapshot().unwrap());
    let disk = lower_frontend_with_memo(
        &frontend,
        &host,
        &NoParameters,
        LoweringConfig::default(),
        &startup,
        &restarted,
    );
    assert!(disk.diagnostics.is_empty(), "{:?}", disk.diagnostics);
    assert_eq!(restarted.values.admitted_bytes(), 0);
    assert_eq!(
        restarted
            .counts
            .disk_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        2
    );
    assert_eq!(
        restarted
            .counts
            .resident_hits
            .load(std::sync::atomic::Ordering::Relaxed),
        0
    );
    for (actual, expected) in disk.units.iter().zip(cold.units) {
        assert_eq!(actual.code.procedure, expected.code.procedure);
        assert_eq!(actual.debug_origins, expected.debug_origins);
    }
    drop(restarted);
    drop(memo);
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
}
