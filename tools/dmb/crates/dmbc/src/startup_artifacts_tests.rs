use super::*;
use std::{
    path::Path,
    sync::{atomic::Ordering, Arc},
};

#[test]
fn issued_static_roster_is_shared_after_exact_current_source_bind() {
    let store = StartupArtifacts::default();
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let original = revision("/proc/p()\n    var/static/cache = 3\n    return cache\n");
    let arena = dm_tree::frontend::BodyArena::new(&original);
    let first = capture(&original, &pool, &arena, Some(&store));
    let compact = store.compact_for_pressure(1024 * 1024);
    assert!(compact.retained_entries > 0);
    assert_eq!(
        compact.evicted_entries, 0,
        "known scalar inventory backing is charged"
    );
    let shifted = revision("// shifted\n/proc/p()\n    var/static/cache = 3\n    return cache\n");
    let arena = dm_tree::frontend::BodyArena::new(&shifted);
    let second = capture(&shifted, &pool, &arena, Some(&store));
    let roster = |facts: &StartupFacts| match &facts.procedures[0].1 {
        ProcedureCapture::Issued(receipt) => receipt.canonical_declarations().unwrap(),
        ProcedureCapture::Empty(_) => panic!("expected issued static declaration"),
    };
    assert!(Arc::ptr_eq(&roster(&first), &roster(&second)));
    assert_ne!(first.plan.origins, second.plan.origins);
    assert!(Arc::ptr_eq(
        &first.static_inventory,
        &second.static_inventory
    ));
}

#[test]
fn whole_inventory_reuses_after_current_body_rebind_and_releases_on_change() {
    let store = StartupArtifacts::default();
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let old = revision(
        "/proc/p()\n    var/static/cache = 3\n    return cache\n/proc/empty()\n    return 1\n",
    );
    let arena = dm_tree::frontend::BodyArena::new(&old);
    let first = capture(&old, &pool, &arena, Some(&store));
    let weak = Arc::downgrade(&first.static_inventory);
    let shifted = revision("// moved\n/proc/p()\n    var/static/cache = 3\n    return cache + 1\n/proc/empty()\n    return 2\n");
    let arena = dm_tree::frontend::BodyArena::new(&shifted);
    let reused = capture(&shifted, &pool, &arena, Some(&store));
    let fresh_arena = dm_tree::frontend::BodyArena::new(&shifted);
    let fresh = capture(&shifted, &pool, &fresh_arena, None);
    assert!(Arc::ptr_eq(
        &first.static_inventory,
        &reused.static_inventory
    ));
    assert_eq!(reused.plan.writes, fresh.plan.writes);
    assert_eq!(reused.plan.origins, fresh.plan.origins);
    assert_ne!(first.plan.origins, reused.plan.origins);
    assert_eq!(store.inventory_hits.load(Ordering::Relaxed), 1);
    drop(first);
    drop(reused);
    let changed = revision(
        "/proc/p()\n    var/static/cache = 4\n    return cache\n/proc/empty()\n    return 2\n",
    );
    let arena = dm_tree::frontend::BodyArena::new(&changed);
    let changed = capture(&changed, &pool, &arena, Some(&store));
    assert!(
        weak.upgrade().is_none(),
        "latest-only inventory must release replaced backing"
    );
    assert_eq!(store.inventory_recomputed.load(Ordering::Relaxed), 2);
    let stats = store.retention_census();
    assert!(stats
        .owners
        .iter()
        .any(|owner| owner.owner == "startup.inventory_roster"));
    drop(changed);
}

#[test]
fn failed_inventory_does_not_publish_or_hide_ordinary_error_and_recovers() {
    let store = StartupArtifacts::default();
    let id = dm_ir::ProcedureIdentity {
        owner: dm_ir::SymbolId::of("/"),
        name: dm_ir::SymbolId::of("p"),
        verb: false,
        occurrence: 0,
    };
    let plan = dm_tree::procedure_statics::capture_declarations(id, &[]).unwrap();
    let first = store.inventory(&[&plan]).unwrap();
    let error = match store.inventory(&[&plan, &plan]) {
        Ok(_) => panic!("duplicate inventory must fail"),
        Err(error) => error,
    };
    assert_eq!(error, "duplicate procedure static inventory");
    assert!(Arc::ptr_eq(&first, &store.inventory(&[&plan]).unwrap()));
    let weak = Arc::downgrade(&first);
    drop(first);
    store.inventory(&[]).unwrap();
    assert!(weak.upgrade().is_none());
}
struct Text(&'static str);
impl dm_preprocess::SourceProvider for Text {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn revision(source: &'static str) -> dm_tree::frontend::FrontendRevision {
    dm_tree::frontend::FrontendRevision::new(
        dm_tree::frontend::build(
            Path::new("startup-reuse.dme"),
            &Text(source),
            &Default::default(),
            1,
        )
        .unwrap(),
    )
}
fn capture<'a>(
    front: &'a dm_tree::frontend::FrontendRevision,
    pool: &dm_exec::BuildExecutor,
    arena: &dm_tree::frontend::BodyArena<'a>,
    store: Option<&StartupArtifacts>,
) -> Arc<StartupFacts> {
    capture_revision_facts_with_executor_and_bodies_and_artifacts(front, &[], pool, arena, store)
        .unwrap()
}
#[test]
fn unchanged_static_payload_rebinds_current_origins_without_parsing_or_retagging() {
    let store = StartupArtifacts::default();
    let pool = dm_exec::BuildExecutor::new(2).unwrap();
    let old = revision("/proc/p()\n    var/static/cache = 3\n    return cache\n");
    let old_arena = dm_tree::frontend::BodyArena::new(&old);
    let before = capture(&old, &pool, &old_arena, Some(&store));
    let current =
        revision("// source moved\n\n/proc/p()\n    var/static/cache = 3\n    return cache\n");
    let current_arena = dm_tree::frontend::BodyArena::new(&current);
    let reused = capture(&current, &pool, &current_arena, Some(&store));
    let fresh_arena = dm_tree::frontend::BodyArena::new(&current);
    let fresh = capture(&current, &pool, &fresh_arena, None);
    assert_eq!(reused.plan.writes, fresh.plan.writes);
    assert_eq!(reused.plan.identity, fresh.plan.identity);
    assert_eq!(reused.plan.origins, fresh.plan.origins);
    assert_ne!(before.plan.origins, reused.plan.origins);
    assert!(before.view_revision(&current).is_err());
    reused.view_revision(&current).unwrap();
    let mut retained = 0;
    current_arena.visit_retained(|_, _| retained += 1);
    assert_eq!(
        retained, 0,
        "static hit must not populate current syntax arena"
    );
    let (ProcedureCapture::Issued(a), ProcedureCapture::Issued(b)) =
        (&before.procedures[0].1, &reused.procedures[0].1)
    else {
        panic!("issued plans required")
    };
    assert!(!Arc::ptr_eq(a, b), "current origin binding must be fresh");
    assert!(Arc::ptr_eq(
        &a.relative_payload().unwrap(),
        &b.relative_payload().unwrap()
    ));
    assert_eq!(store.hits.load(Ordering::Relaxed), 1);
}
#[test]
fn shifted_array_and_nested_static_expressions_match_independent_fresh_capture() {
    let store = StartupArtifacts::default();
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let old = revision("/proc/p()\n    var/static/list/rows[2][3]\n    var/static/value = list(1, list(2, 3))\n    return value\n");
    let old_arena = dm_tree::frontend::BodyArena::new(&old);
    let before = capture(&old, &pool, &old_arena, Some(&store));
    let current = revision("// moved static syntax\n\n/proc/p()\n    var/static/list/rows[2][3]\n    var/static/value = list(1, list(2, 3))\n    return value\n");
    let arena = dm_tree::frontend::BodyArena::new(&current);
    let reused = capture(&current, &pool, &arena, Some(&store));
    let fresh_arena = dm_tree::frontend::BodyArena::new(&current);
    let fresh = capture(&current, &pool, &fresh_arena, None);
    assert_eq!(reused.plan.writes, fresh.plan.writes);
    assert_eq!(reused.plan.origins, fresh.plan.origins);
    let old_plan = &*before.procedures[0].1;
    let current_plan = &*reused.procedures[0].1;
    assert_eq!(old_plan.declarations, current_plan.declarations);
    assert_ne!(old_plan.origins, current_plan.origins);
    assert_eq!(current_plan.origins, fresh.procedures[0].1.origins);
    let ProcedureCapture::Issued(receipt) = &before.procedures[0].1 else {
        panic!("issued syntax required")
    };
    let payload = receipt.relative_payload().unwrap();
    assert!(payload
        .plan()
        .origins
        .iter()
        .all(|origin| origin.span.end <= payload.source().len()
            && origin.header_span.end <= payload.source().len()));
    let changed = revision("/proc/p()\n    var/static/list/rows[2][4]\n    return rows\n");
    assert!(payload.bind(&changed, &changed.bodies[0]).is_err());
    assert!(
        payload.bind(&current, &old.bodies[0]).is_err(),
        "foreign issuance must not bind"
    );
}
#[test]
fn changed_static_body_and_deleted_procedure_replace_current_roster_without_source_retention() {
    let store = StartupArtifacts::default();
    let pool = dm_exec::BuildExecutor::new(1).unwrap();
    let original = revision("/proc/p()\n    var/static/cache = 3\n    return cache\n");
    let source = original.expanded.text.downgrade();
    {
        let arena = dm_tree::frontend::BodyArena::new(&original);
        drop(capture(&original, &pool, &arena, Some(&store)));
    }
    drop(original);
    assert!(
        source.upgrade().is_none(),
        "retained syntax must not retain old source owner"
    );
    let changed = revision("/proc/p()\n    var/static/cache = 4\n    return cache\n");
    let arena = dm_tree::frontend::BodyArena::new(&changed);
    let changed_facts = capture(&changed, &pool, &arena, Some(&store));
    let fresh_arena = dm_tree::frontend::BodyArena::new(&changed);
    let fresh = capture(&changed, &pool, &fresh_arena, None);
    assert_eq!(changed_facts.plan.writes, fresh.plan.writes);
    assert_eq!(store.recomputed.load(Ordering::Relaxed), 2);
    let empty = revision("/datum/replacement\n    var/value = 1\n");
    let arena = dm_tree::frontend::BodyArena::new(&empty);
    capture(&empty, &pool, &arena, Some(&store));
    let restored = revision("/proc/p()\n    var/static/cache = 4\n    return cache\n");
    let arena = dm_tree::frontend::BodyArena::new(&restored);
    capture(&restored, &pool, &arena, Some(&store));
    assert_eq!(
        store.recomputed.load(Ordering::Relaxed),
        3,
        "deleted current key must be pruned"
    );
}

#[path = "startup_inventory_fresh_tests.rs"]
mod fresh_inventory;
