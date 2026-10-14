use super::*;
use std::{
    path::PathBuf,
    sync::atomic::{AtomicU64, Ordering},
};
static NEXT: AtomicU64 = AtomicU64::new(0);
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        std::fs::create_dir_all(&base).unwrap();
        let path = base.join(format!(
            "lowering-disk-candidates-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::create_dir(&path).unwrap();
        Self(path)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
fn publish_failure(cache: &dm_cache::Cache, key: &[u8], host: &impl Resolver, reason: &str) {
    let recorder = RecordingResolver::new(host);
    recorder.resolve(ResolveQuery::GlobalVar(dm_ir::SymbolId::of("absent")));
    let errors = [dm_codegen_byond::LowerError {
        primary_anchor: None,
        related: Vec::new(),
        statement: "unsupported".into(),
        reason: reason.into(),
        span: None,
        kind: dm_codegen_byond::LowerErrorKind::UnsupportedModel,
    }];
    let payload =
        crate::lowering_memo_wire::encode_failure(key, None, &recorder.reads(), &[], &errors)
            .unwrap();
    let envelope = dm_cache::encode_variants(&[payload]).unwrap();
    cache
        .publish(&[dm_cache::Record {
            key: ProcedureMemo::record_key(key),
            symbols: Vec::new(),
            payload: Arc::from(envelope),
        }])
        .unwrap();
}
#[test]
fn anonymous_disk_lookup_falls_back_across_healthy_semantic_candidates() {
    let root = Temp::new();
    let cache = dm_cache::Cache::open(&root.0, dm_cache::Limits::default()).unwrap();
    let key = b"same-anonymous-source";
    publish_failure(&cache, key, &Host(false), "missing-context");
    publish_failure(&cache, key, &Host(true), "symbol-context");
    for (host, expected) in [
        (Host(false), "missing-context"),
        (Host(true), "symbol-context"),
    ] {
        let snapshot = Arc::new(cache.snapshot().unwrap());
        let memo = ProcedureMemo::with_disk(1, Arc::clone(&snapshot));
        let replay = memo.lookup_anonymous(key, &host, 0);
        assert!(replay.code.is_none());
        assert_eq!(replay.errors.unwrap()[0].reason, expected);
        assert_eq!(
            snapshot.record_used_keys(),
            [ProcedureMemo::record_key(key)].into_iter().collect()
        );
        assert!(snapshot.rejected().is_empty());
    }
    struct OtherHost;
    impl Resolver for OtherHost {
        fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Symbol(dm_ir::SymbolId::of("different"))
        }
    }
    let snapshot = Arc::new(cache.snapshot().unwrap());
    let memo = ProcedureMemo::with_disk(1, Arc::clone(&snapshot));
    let replay = memo.lookup_anonymous(key, &OtherHost, 0);
    assert!(replay.code.is_none() && replay.errors.is_none());
    assert!(snapshot.record_used_keys().is_empty());
    assert!(snapshot.rejected().is_empty());
}
