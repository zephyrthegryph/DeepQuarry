use super::*;
#[test]
fn optional_release_resamples_pressure_before_remaining_artifacts_and_session() {
    assert_eq!(target(Duration::ZERO, true, 3), OPTIONAL_IMAGES);
    assert_eq!(target(Duration::ZERO, false, OPTIONAL_IMAGES), 0);
    assert_eq!(
        target(Duration::ZERO, true, OPTIONAL_IMAGES),
        COMPACT_SYMBOLIC
    );
    assert_eq!(target(Duration::ZERO, false, COMPACT_SYMBOLIC), 0);
    assert_eq!(
        target(Duration::ZERO, true, COMPACT_SYMBOLIC),
        REMAINING_OPTIONAL
    );
    assert_eq!(target(Duration::ZERO, false, REMAINING_OPTIONAL), 0);
    assert_eq!(
        target(Duration::ZERO, true, REMAINING_OPTIONAL),
        SESSION_RELEASE
    );
    assert_eq!(target(SESSION_IDLE, false, 0), SESSION_RELEASE);
}
