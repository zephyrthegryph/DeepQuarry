use super::*;
#[test]
fn optional_release_resamples_pressure_before_remaining_artifacts_and_session() {
    assert_eq!(target(Duration::ZERO, true, true, 3), OPTIONAL_IMAGES);
    assert_eq!(target(Duration::ZERO, false, false, OPTIONAL_IMAGES), 0);
    assert_eq!(
        target(Duration::ZERO, true, true, OPTIONAL_IMAGES),
        COMPACT_SYMBOLIC
    );
    assert_eq!(target(Duration::ZERO, false, false, COMPACT_SYMBOLIC), 0);
    assert_eq!(
        target(Duration::ZERO, true, true, COMPACT_SYMBOLIC),
        REMAINING_OPTIONAL
    );
    assert_eq!(target(Duration::ZERO, false, false, REMAINING_OPTIONAL), 0);
    assert_eq!(
        target(Duration::ZERO, true, true, REMAINING_OPTIONAL),
        SESSION_RELEASE
    );
    assert_eq!(target(SESSION_IDLE, false, false, 0), SESSION_RELEASE);
}
