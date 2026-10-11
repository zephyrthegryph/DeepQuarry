//! Request lifecycle controls over the same real parse/geometry stores.
use super::*;

fn entries(owner: &RetainedMaps) -> usize {
    owner.test_entries()
}

#[test]
fn aborted_new_keys_and_changed_answer_variants_leave_successful_maps_reusable() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let first = MapMemo::with_resident(1, owner.clone(), None);
    let plan = first.parse(captured(1)).unwrap();
    let original = first
        .project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    assert!(first.publish_successful());
    drop(first);
    let baseline = entries(&owner);
    assert_eq!(baseline, 2);
    for _ in 0..8 {
        let failed = MapMemo::with_resident(1, owner.clone(), None);
        let current = failed.parse(captured(2)).unwrap();
        let changed = failed
            .project(std::slice::from_ref(&current), defaults(), &Host(true))
            .unwrap();
        assert_ne!(changed.instances[2].kind, original.instances[2].kind);
        let mut added = captured(3);
        added.path = Arc::new(PathBuf::from("maps/new-failed.dmm"));
        failed.parse(added).unwrap();
        assert!(entries(&owner) > baseline);
        drop(failed); // cancellation/error outcome: no publication
        assert_eq!(entries(&owner), baseline);
    }
    let recovery = MapMemo::with_resident(1, owner.clone(), None);
    let current = recovery.parse(captured(9)).unwrap();
    let hit = recovery
        .project(std::slice::from_ref(&current), defaults(), &Host(false))
        .unwrap();
    assert!(Arc::ptr_eq(&original.grid, &hit.grid));
    assert_eq!(recovery.counts.geometry_hits.load(Ordering::Relaxed), 1);
    assert!(recovery.publish_successful());
    drop(recovery);
    assert_eq!(entries(&owner), baseline);
    let empty = MapMemo::with_resident(1, owner.clone(), None);
    assert!(empty.publish_successful());
    drop(empty);
    assert_eq!(entries(&owner), 0);
}

#[test]
fn superseded_publication_and_late_abort_cannot_erase_newer_exact_variant() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let old = MapMemo::with_resident(1, owner.clone(), None);
    let plan = old.parse(captured(1)).unwrap();
    old.project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    assert!(old.publish_successful());
    let older = MapMemo::with_resident(1, owner.clone(), None);
    older
        .project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    let newer = MapMemo::with_resident(1, owner.clone(), None);
    let changed = newer
        .project(std::slice::from_ref(&plan), defaults(), &Host(true))
        .unwrap();
    assert!(newer.publish_successful());
    assert!(!older.publish_successful());
    drop(old);
    drop(older);
    drop(newer);
    let recovery = MapMemo::with_resident(1, owner.clone(), None);
    let hit = recovery
        .project(std::slice::from_ref(&plan), defaults(), &Host(true))
        .unwrap();
    assert!(Arc::ptr_eq(&changed.grid, &hit.grid));
    assert_eq!(recovery.counts.geometry_hits.load(Ordering::Relaxed), 1);
}

#[test]
fn sealed_success_cannot_gain_claims_from_later_compatibility_operations() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let request = MapMemo::with_resident(1, owner.clone(), None);
    let plan = request.parse(captured(1)).unwrap();
    request
        .project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    assert!(request.publish_successful());
    let baseline = entries(&owner);
    let mut later = captured(2);
    later.path = Arc::new(PathBuf::from("maps/post-publication.dmm"));
    request.parse(later).unwrap();
    request
        .project(std::slice::from_ref(&plan), defaults(), &Host(true))
        .unwrap();
    assert_eq!(entries(&owner), baseline);
    assert!(!request.publish_successful());
    drop(request);
    assert_eq!(entries(&owner), baseline);
}

#[test]
fn analysis_attempt_does_not_supersede_in_flight_successful_build() {
    let owner = Arc::new(RetainedMaps::current_revision());
    let build = MapMemo::with_resident(1, owner.clone(), None);
    let plan = build.parse(captured(1)).unwrap();
    let expected = build
        .project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    let analysis = MapMemo::with_resident_for_request(1, owner.clone(), None, false);
    analysis
        .project(std::slice::from_ref(&plan), defaults(), &Host(true))
        .unwrap();
    assert!(!analysis.publish_successful());
    assert!(build.publish_successful());
    drop(analysis);
    drop(build);
    let next = MapMemo::with_resident(1, owner, None);
    let current = next
        .project(std::slice::from_ref(&plan), defaults(), &Host(false))
        .unwrap();
    assert!(Arc::ptr_eq(&expected.grid, &current.grid));
    assert_eq!(next.counts.geometry_hits.load(Ordering::Relaxed), 1);
}
