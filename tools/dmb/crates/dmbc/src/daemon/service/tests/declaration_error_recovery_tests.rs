//! Structural initializer failure cannot publish over a valid artifact roster.
use super::*;
fn assembly_rows(host: &crate::runner_host::BuildHost) -> Vec<(String, u64)> {
    let report = host.initializer_assembly_retention_census().unwrap();
    report
        .owners
        .into_iter()
        .map(|owner| (owner.owner, owner.observed_items))
        .collect()
}
#[test]
fn missing_initializer_type_preserves_published_rosters_and_new_type_recovery_matches_fresh() {
    let roots = Roots::new();
    let initial_source = SOURCE.replace("return item.result()", "return item.result() + shared[1]")
        + "var/global/list/shared = list(7)\n";
    roots.edit(0, &initial_source);
    let mut host = crate::runner_host::BuildHost::default();
    let first_request = request(&roots, 0, false);
    let destination = first_request.artifact_directory.as_ref().unwrap().clone();
    let (first, diagnostics) = run_captured(first_request, &mut host);
    assert!(diagnostics.is_empty());
    let initial = published(first.unwrap(), &destination);
    let old_symbolic = host.symbolic_retention_stats().unwrap();
    assert!(old_symbolic.records > 0);
    let old_assemblies = assembly_rows(&host);
    assert!(
        old_assemblies
            .iter()
            .any(|(name, count)| name == "initializer_assemblies.index" && *count > 0),
        "fixture must publish an actual runtime initializer assembly"
    );
    for shift in [0, 3] {
        let invalid = format!(
            "{}{}var/global/broken = /datum/formerly_missing_type{{amount=1}}\n",
            "\n".repeat(shift),
            initial_source
        );
        roots.edit(0, &invalid);
        let (retained, retained_diagnostics) = run_captured(request(&roots, 0, false), &mut host);
        let (fresh, fresh_diagnostics) = run_captured(
            request(&roots, 0, true),
            &mut crate::runner_host::BuildHost::one_shot(),
        );
        for result in [retained, fresh] {
            let failure = result.err().expect("missing initializer type must reject");
            assert_eq!(
                crate::request_failure::classify(failure.as_ref()),
                crate::request_failure::FailureKind::Source
            );
        }
        assert!(!retained_diagnostics.is_empty());
        assert!(retained_diagnostics
            .iter()
            .any(|line| line.contains("formerly_missing_type: undefined type")));
        assert_eq!(retained_diagnostics, fresh_diagnostics);
        let now = host.symbolic_retention_stats().unwrap();
        assert_eq!(now.records, old_symbolic.records);
        assert_eq!(
            now.successful_admissions,
            old_symbolic.successful_admissions
        );
        assert_eq!(assembly_rows(&host), old_assemblies);
        assert_eq!(
            std::fs::read(destination.join("probe.dmb")).unwrap(),
            initial.1
        );
        assert_eq!(
            std::fs::read(destination.join("probe.rsc")).unwrap(),
            initial.2
        );
    }
    let restored = initial_source.replace("return item.result() + shared[1]", "return item.result() + shared[1] + fresh_instance.own")
        + "/datum/added\n    parent_type = /datum/base\n    value = 11\n    var/own = 19\nvar/global/datum/added/fresh_instance = new\n";
    roots.edit(0, &restored);
    let (recovered, diagnostics) = run_captured(request(&roots, 0, false), &mut host);
    assert!(diagnostics.is_empty());
    let recovered = published(recovered.unwrap(), &destination);
    let fresh_request = request(&roots, 0, true);
    let fresh_destination = fresh_request.artifact_directory.as_ref().unwrap().clone();
    let (fresh, diagnostics) = run_captured(
        fresh_request,
        &mut crate::runner_host::BuildHost::one_shot(),
    );
    assert!(diagnostics.is_empty());
    assert_eq!(recovered, published(fresh.unwrap(), &fresh_destination));
    assert_ne!(recovered.0, initial.0);
}
