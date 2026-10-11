//! Fixed request admission budget; retries cannot extend the client's contract.
use std::{
    io,
    time::{Duration, Instant},
};
pub(super) struct AdmissionDeadline(Instant);
impl AdmissionDeadline {
    pub(super) fn at(deadline: Instant) -> Self {
        Self(deadline)
    }
    pub(super) fn new(now: Instant) -> Self {
        Self(now + Duration::from_secs(600))
    }
    pub(super) fn remaining(&self, now: Instant) -> io::Result<Duration> {
        self.0
            .checked_duration_since(now)
            .filter(|duration| !duration.is_zero())
            .ok_or_else(|| {
                io::Error::new(
                    io::ErrorKind::Interrupted,
                    "daemon build admission deadline expired (session or worker capacity)",
                )
            })
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn query_admission_preserves_issued_deadline() {
        let start = Instant::now();
        let deadline = AdmissionDeadline::at(start + Duration::from_secs(20));
        assert_eq!(
            deadline.remaining(start + Duration::from_secs(19)).unwrap(),
            Duration::from_secs(1)
        );
        assert_eq!(
            crate::request_failure::exit_code(
                &deadline
                    .remaining(start + Duration::from_secs(20))
                    .unwrap_err()
            ),
            75
        );
    }
    #[test]
    fn retries_share_one_fixed_deadline_and_expiration_is_cancellation() {
        let start = Instant::now();
        let deadline = AdmissionDeadline::new(start);
        assert_eq!(deadline.remaining(start).unwrap(), Duration::from_secs(600));
        assert_eq!(
            deadline
                .remaining(start + Duration::from_secs(599))
                .unwrap(),
            Duration::from_secs(1)
        );
        let error = deadline
            .remaining(start + Duration::from_secs(600))
            .unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::Interrupted);
        assert_eq!(crate::request_failure::exit_code(&error), 75);
        assert!(deadline
            .remaining(start + Duration::from_secs(601))
            .is_err());
    }
}
