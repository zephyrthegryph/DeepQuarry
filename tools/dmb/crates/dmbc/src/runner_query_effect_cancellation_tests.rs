//! Real daemon Cancellation/IO status, never memoized as semantic refusal.
use super::*;
use std::time::{Duration, Instant};
#[test]
fn cancelled_and_expired_empty_requests_are_not_clean_reports_or_poisoned_cache_entries() {
    let (snapshot, _) = fixture("/datum/empty\n", None);
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let db = snapshot.native_raw_queries.as_ref().unwrap();
    let before = (17..=22)
        .map(|kind| db.db().stats(dm_query::Kind(kind)).computed)
        .collect::<Vec<_>>();
    for expired in [false, true] {
        let token = crate::daemon::control::Cancellation::default();
        if !expired {
            token.cancel();
        }
        let binding = crate::daemon::control::bind_with_deadline(
            token,
            if expired {
                Instant::now()
            } else {
                Instant::now() + Duration::from_secs(60)
            },
        );
        for sleeping in [false, true] {
            let error = if sleeping {
                snapshot.native_sleep_report(&input, &env(), None, &snapshot.tree)
            } else {
                snapshot.native_purity_report(&input, &env(), None, &snapshot.tree)
            }
            .unwrap_err();
            assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
        }
        drop(binding);
        assert_eq!(
            before,
            (17..=22)
                .map(|kind| db.db().stats(dm_query::Kind(kind)).computed)
                .collect::<Vec<_>>()
        );
    }
    assert!(snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap()
        .is_empty());
    assert!(snapshot
        .native_sleep_report(&input, &env(), None, &snapshot.tree)
        .unwrap()
        .is_empty());
}
#[test]
fn cancellation_after_real_body_computation_publishes_no_error_or_partial_result_and_fresh_request_recovers(
) {
    let (snapshot, _) = fixture(
        include_str!("../../../fixtures/unified_checks/purity/parameter/probe.dme"),
        None,
    );
    let input = snapshot.native_purity_input(&snapshot.tree).unwrap();
    let db = snapshot.native_raw_queries.as_ref().unwrap();
    let owner = dm_ir::Resolver::source_owner(snapshot.tree.as_ref());
    let token = crate::daemon::control::Cancellation::default();
    let binding = crate::daemon::control::bind_with_deadline(
        token.clone(),
        Instant::now() + Duration::from_secs(60),
    );
    // Cancel when BODY17 has its real completed original syntax/Walker result
    // but has not published an Outcome or a semantic refusal into the cache.
    let scheduled = db.cancel_effect_before_publication_for_test(dm_query::Kind(17), token.clone());
    let error = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap_err();
    assert!(token.is_cancelled());
    assert_eq!(error.kind(), std::io::ErrorKind::Interrupted);
    assert!(
        db.db().stats(dm_query::Kind(4)).computed > 0,
        "real original body was parsed before cancellation"
    );
    assert_eq!(
        db.effect_retained_values_for_test(dm_query::Kind(17)),
        0,
        "no body outcome/error after abort"
    );
    assert_eq!(
        db.effect_retained_values_for_test(dm_query::Kind(20)),
        0,
        "operational failure must not become cached semantic refusal"
    );
    drop(scheduled);
    drop(binding);
    let rows = snapshot
        .native_purity_report(&input, &env(), None, &snapshot.tree)
        .unwrap();
    assert_eq!(
        render(&rows),
        decode_oracle_transport(include_str!(
            "../../../fixtures/unified_checks/purity/parameter/reference.stderr"
        ))
        .as_ref()
    );
    assert_eq!(owner, dm_ir::Resolver::source_owner(snapshot.tree.as_ref()));
    assert!(db.effect_retained_values_for_test(dm_query::Kind(20)) > 0);
}
