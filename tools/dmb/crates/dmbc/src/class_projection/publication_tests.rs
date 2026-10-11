//! Actual projection owners across request publication, failure and analysis.
use super::*;
const ORIGINAL: &str = "/datum/a\n    var/x = 3\n/datum/a/proc/p()\n    return 1\n";
const CHANGED: &str =
    "/datum/a\n    var/x = 4\n/datum/a/proc/added()\n    return 2\n/datum/b\n    var/y = 3\n";
fn entries(store: &ClassProjections) -> (usize, usize) {
    let mut owners = 0;
    let mut types = 0;
    store.visit_storage(|view| {
        if let dm_session::ArtifactStorageView::Store { entries, .. } = view {
            owners = entries;
        }
    });
    store.types.visit_storage(|view| {
        if let dm_session::ObservedArtifactStorageView::Store { entries, .. } = view {
            types = entries;
        }
    });
    (owners, types)
}
#[test]
fn failed_projection_attempt_keeps_exact_owner_type_and_method_rosters() {
    let owner = ClassProjections::default();
    let first = owner.with_request(true);
    let original = project_source(&first, ORIGINAL, false);
    assert!(first.publish_successful());
    drop(first);
    let baseline = entries(&owner);
    for _ in 0..4 {
        let failed = owner.with_request(true);
        let changed = project_source(&failed, CHANGED, false);
        assert_ne!(changed.procedure_membership, original.procedure_membership);
        assert!(entries(&owner).0 > baseline.0);
        assert!(entries(&owner).1 > baseline.1);
        drop(failed); // a later required request stage failed
        assert_eq!(entries(&owner), baseline);
    }
    let recovered = owner.with_request(true);
    let current = project_source(&recovered, ORIGINAL, false);
    assert!(Arc::ptr_eq(&original.fields[0], &current.fields[0]));
    assert!(Arc::ptr_eq(
        &original.type_construction,
        &current.type_construction
    ));
    assert!(Arc::ptr_eq(&original.chains, &current.chains));
    assert!(Arc::ptr_eq(
        &original.procedure_membership,
        &current.procedure_membership
    ));
    assert!(recovered.publish_successful());
    drop(recovered);
    assert_eq!(entries(&owner), baseline);
    let empty = owner.with_request(true);
    assert!(empty.publish_successful());
    drop(empty);
    assert_eq!(entries(&owner), (0, 0));
}
#[test]
fn latest_projection_attempt_wins_and_analysis_cannot_supersede_build() {
    let owner = ClassProjections::default();
    let older = owner.with_request(true);
    project_source(&older, ORIGINAL, false);
    let newer = owner.with_request(true);
    let latest = project_source(&newer, CHANGED, false);
    let analysis = owner.with_request(false);
    project_source(&analysis, ORIGINAL, false);
    assert!(!analysis.publish_successful());
    assert!(newer.publish_successful());
    assert!(!older.publish_successful());
    drop(analysis);
    drop(older);
    drop(newer);
    let current = owner.with_request(true);
    let recovered = project_source(&current, CHANGED, false);
    assert!(Arc::ptr_eq(&latest.fields[0], &recovered.fields[0]));
    assert!(Arc::ptr_eq(
        &latest.type_construction,
        &recovered.type_construction
    ));
    assert!(Arc::ptr_eq(&latest.chains, &recovered.chains));
}

#[test]
fn ordinary_projection_error_drops_pending_type_claim_without_consuming_methods() {
    let owner = ClassProjections::default();
    let first = owner.with_request(true);
    let original = project_source(&first, ORIGINAL, false);
    assert!(first.publish_successful());
    drop(first);
    let baseline = entries(&owner);
    let failed = owner.with_request(true);
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source(CHANGED),
        &Default::default(),
        1,
    )
    .unwrap();
    let mut order: Vec<_> = (0..frontend.snapshot.occurrences.source_order().len())
        .map(|i| OccurrenceId(i as u32))
        .collect();
    let plan = dm_tree::initializers::plan(&frontend.snapshot, &order).unwrap();
    let facts =
        crate::initializer_policy::classify(&plan.writes, &plan.symbols, &Evaluator).unwrap();
    let first_occurrence = order[0];
    *order.last_mut().unwrap() = first_occurrence;
    let error = project_classified_with_artifacts(
        &frontend.snapshot,
        &order,
        &plan,
        &facts,
        &[],
        Some(&failed),
    )
    .err()
    .expect("duplicate current occurrence must fail");
    assert!(matches!(error, ProjectionError::IncompleteOrder));
    drop(failed);
    assert_eq!(entries(&owner), baseline);
    let recovered = owner.with_request(true);
    let current = project_source(&recovered, ORIGINAL, false);
    assert!(Arc::ptr_eq(
        &original.type_construction,
        &current.type_construction
    ));
    assert!(Arc::ptr_eq(&original.chains, &current.chains));
    assert!(Arc::ptr_eq(&original.fields[0], &current.fields[0]));
}
