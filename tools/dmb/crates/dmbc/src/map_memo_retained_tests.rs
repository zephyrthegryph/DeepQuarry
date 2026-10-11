use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning, SymbolId};
use std::path::PathBuf;
#[path = "map_memo_request_tests.rs"]
mod request_tests;
struct Host(bool);
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        match query {
            ResolveQuery::Type(path) => ResolvedMeaning::Symbol(path),
            ResolveQuery::Ancestry(path) => ResolvedMeaning::Symbols(
                (if path == SymbolId::of("/datum/widget") {
                    vec![
                        SymbolId::of(if self.0 { "/mob" } else { "/obj" }),
                        SymbolId::of("/datum"),
                    ]
                } else {
                    vec![SymbolId::of("/datum")]
                })
                .into(),
            ),
            _ => ResolvedMeaning::Unsupported(query),
        }
    }
}
fn captured(occurrence: u32) -> CapturedMap {
    CapturedMap {
        path: Arc::new(PathBuf::from("maps/probe.dmm")),
        include_occurrence: occurrence,
        source: Arc::from("\"a\"=(/datum/widget,/turf,/area)\n(1,1,1)={\"a\"}"),
    }
}
fn defaults() -> WorldDefaults {
    WorldDefaults {
        turf: SymbolId::of("/turf"),
        area: SymbolId::of("/area"),
        minimum_dimensions: [1; 3],
    }
}
#[test]
fn current_map_artifacts_share_payloads_rebind_occurrences_and_replay_reads() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let first = MapMemo::with_resident(1, owner.clone(), None);
    let plan = first.parse(captured(1)).unwrap();
    let projected = first
        .project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    first.finish_revision();
    let second = MapMemo::with_resident(1, owner.clone(), None);
    let current = second.parse(captured(9)).unwrap();
    assert_eq!(current.captured.include_occurrence, 9);
    assert!(Arc::ptr_eq(&plan.model, &current.model));
    let hit = second
        .project(std::slice::from_ref(&current), defaults(), &Host(false))
        .unwrap();
    assert!(Arc::ptr_eq(&projected.grid, &hit.grid));
    assert_eq!(second.counts.geometry_hits.load(Ordering::Relaxed), 1);
    let changed = second
        .project(std::slice::from_ref(&current), defaults(), &Host(true))
        .unwrap();
    assert_eq!(second.counts.projected.load(Ordering::Relaxed), 1);
    assert_ne!(projected.instances[2].kind, changed.instances[2].kind);
    second.finish_revision();
    let empty = MapMemo::with_resident(1, owner.clone(), None);
    empty.finish_revision();
    assert_eq!(owner.artifact_admitted_bytes(), 0);
}
#[test]
fn same_locator_cannot_authorize_changed_source_or_model() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let memo = MapMemo::with_resident(1, owner, None);
    let plan = memo.parse(captured(1)).unwrap();
    memo.project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    let locator = retained::geometry_locator(1, std::slice::from_ref(&plan), defaults());
    let mut changed_source = plan.clone();
    changed_source.captured.source = Arc::from("same locator, different exact bytes");
    assert!(memo
        .retained_geometry(&locator, &[changed_source], &Host(false))
        .is_none());
    let mut changed_model = plan.clone();
    let mut model = (*plan.model).clone();
    model.key_width = Some(99);
    changed_model.model = Arc::new(model);
    assert!(memo
        .retained_geometry(&locator, &[changed_model], &Host(false))
        .is_none());
}

#[test]
fn accepted_resident_parse_and_geometry_leave_lazy_disk_unopened() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let first = MapMemo::with_resident(1, owner.clone(), None);
    let plan = first.parse(captured(1)).unwrap();
    let projection = first
        .project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    first.finish_revision();
    let disk = Arc::new(crate::runner_disk::LazyDisk::new(PathBuf::from(
        "E:/dq-cache/unused-resident-map-fixture",
    )));
    let second = MapMemo::with_resident(1, owner, Some(disk.clone()));
    let current = second.parse(captured(9)).unwrap();
    let hit = second
        .project(std::slice::from_ref(&current), defaults(), &Host(false))
        .unwrap();
    assert!(Arc::ptr_eq(&plan.model, &current.model));
    assert!(Arc::ptr_eq(&projection.grid, &hit.grid));
    assert!(!disk.is_opened());
    assert!(disk.loaded_snapshot().is_none());
}
