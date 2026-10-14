use super::*;

fn owner<'a>(report: &'a HeapCensusReport, name: &str) -> &'a OwnerReport {
    report.owners.iter().find(|row| row.owner == name).unwrap()
}

#[test]
fn empty_shared_core_reports_lease_gaps_without_inventing_heap_bytes() {
    let store = dm_session::ObservedArtifactStore::<u32, u8, u32, u8>::shared_current_rosters();
    let a = store.lease();
    let b = store.lease();
    let mut census = HeapCensus::new("empty_shared_core");
    census.artifact_storage_accounting("shared", a.storage_accounting());
    census.artifact_storage_accounting("shared", b.storage_accounting());
    let report = census.finish();
    assert_eq!(owner(&report, "shared.control.leases").observed_items, 2);
    assert_eq!(owner(&report, "shared.control.variants").observed_items, 0);
    assert_eq!(owner(&report, "shared.control.claims").observed_items, 0);
    assert_eq!(owner(&report, "shared.control").shared_encounters, 1);
    assert!(owner(&report, "shared.control")
        .unknown
        .iter()
        .any(|reason| reason.contains("lease roster BTree")));
    assert!(owner(&report, "shared.control")
        .unknown
        .iter()
        .any(|reason| reason.contains("coverage is partial")));
    assert_eq!(report.unique_known_capacity_bytes, 0);
    assert_eq!(report.unknown_capacity_payload_bytes, 0);
    assert!(report
        .owners
        .iter()
        .all(|row| row.unique_payload_bytes == 0));
    let json = serde_json::to_value(&report).unwrap();
    assert_eq!(
        json["schema"], 1,
        "existing report shape remains compatible"
    );
    assert_eq!(
        json["scope"],
        "retained_accessible_container_payload_and_capacity_not_total_heap"
    );
}

#[test]
fn shared_local_shape_census_reports_engine_leases_without_inventing_bytes() {
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/obj/base\n    var/count = 1\n/proc/probe()\n    return 7\n".into())
        }
    }
    let shared = Arc::new(dm_tree::SharedNormalizedDeclarations::default());
    let mut a =
        dm_tree::frontend::RetainedSemanticTree::with_shared_normalized(Arc::clone(&shared));
    let mut b = dm_tree::frontend::RetainedSemanticTree::with_shared_normalized(shared);
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    for (path, state) in [("first.dme", &mut a), ("sibling.dme", &mut b)] {
        dm_tree::frontend::build_with_executor_and_semantic_state(
            std::path::Path::new(path),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: None,
                observer: None,
            },
            None,
            &executor,
            Some(state),
        )
        .unwrap();
    }
    let accounting = a.local_shape_storage_accounting();
    assert_eq!(accounting, b.local_shape_storage_accounting());
    assert_eq!(accounting.leases, 2);
    assert!(accounting.claimed_variants > 0);
    let mut single = HeapCensus::new("single");
    super::super::local_shape::inspect(&mut single, &a);
    let single = single.finish();
    let mut aliases = HeapCensus::new("aliases");
    super::super::local_shape::inspect(&mut aliases, &a);
    super::super::local_shape::inspect(&mut aliases, &b);
    let aliases = aliases.finish();
    assert_eq!(
        single.unique_known_capacity_bytes,
        aliases.unique_known_capacity_bytes
    );
    assert_eq!(
        owner(&aliases, "retained_local_shape.control.leases").observed_items,
        2
    );
    assert_eq!(
        owner(&aliases, "retained_local_shape.control.claims").observed_items,
        accounting.claims as u64
    );
    assert!(owner(&aliases, "retained_local_shape.control")
        .unknown
        .iter()
        .any(|reason| reason.contains("physical variant claim BTree")));
}
