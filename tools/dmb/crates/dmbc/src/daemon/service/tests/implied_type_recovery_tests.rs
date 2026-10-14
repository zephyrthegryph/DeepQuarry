//! Actual initializer/body diagnostic continuation through retained requests.
use super::*;

const INVALID: &str =
    "var/global/datum/formerly_missing_type/value = new\n/proc/probe()\n    return value\n";
const VALID: &str = "/datum/formerly_missing_type\n    var/amount = 7\nvar/global/datum/formerly_missing_type/value = new\n/proc/probe()\n    return value\n";

#[test]
fn implied_type_errors_match_fresh_current_include_and_recover_without_replacing_prior_pair() {
    let roots = Roots::new();
    roots.edit(0, VALID);
    let shared = shared();
    let initial_request = request(&roots, 0, false);
    let slot = shared.slot(
        initial_request.project.clone(),
        &initial_request.defines,
        Some(&initial_request),
    );
    let destination = initial_request.artifact_directory.as_ref().unwrap().clone();
    let mut host = slot.lock_host().unwrap();
    let (initial, diagnostics) = run_captured(initial_request, &mut host);
    assert!(diagnostics.is_empty());
    let initial = published(initial.unwrap(), &destination);
    for shift in [0, 3] {
        roots.edit(
            0,
            &format!("{}{INVALID}", "// shifted current include\n".repeat(shift)),
        );
        let (retained, retained_diagnostics) = run_captured(request(&roots, 0, false), &mut host);
        let (fresh, fresh_diagnostics) = run_captured(
            request(&roots, 0, true),
            &mut crate::runner_host::BuildHost::one_shot(),
        );
        for result in [retained, fresh] {
            let error = result.err().expect("invalid implied declared type rejects");
            assert_eq!(
                crate::request_failure::classify(error.as_ref()),
                crate::request_failure::FailureKind::Source
            );
        }
        assert_eq!(retained_diagnostics, fresh_diagnostics);
        assert_eq!(
            retained_diagnostics,
            vec![
                format!("probe.dm:{}:error: value: unknown variable type", shift + 1),
                format!(
                    "probe.dm:{}:error: returnvalue: undefined type: /datum/formerly_missing_type",
                    shift + 3
                ),
            ]
        );
        assert_eq!(
            std::fs::read(destination.join("probe.dmb")).unwrap(),
            initial.1
        );
        assert_eq!(
            std::fs::read(destination.join("probe.rsc")).unwrap(),
            initial.2
        );
    }
    let recovered_source = VALID.replace("return value", "return value.amount");
    roots.edit(0, &recovered_source);
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
