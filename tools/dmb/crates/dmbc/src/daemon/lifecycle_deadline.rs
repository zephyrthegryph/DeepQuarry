//! Fixed lifecycle phase budgets; repeated handshakes cannot renew a drain.
use std::{
    io,
    time::{Duration, Instant},
};
const STARTUP: Duration = Duration::from_secs(20);
const DRAIN: Duration = Duration::from_secs(300);
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Startup,
    Drain,
    Replacement,
}
pub(super) struct LifecycleDeadline {
    phase: Phase,
    deadline: Instant,
}
impl LifecycleDeadline {
    pub(super) fn new(now: Instant) -> Self {
        Self {
            phase: Phase::Startup,
            deadline: now + STARTUP,
        }
    }
    pub(super) fn retiring(&mut self, now: Instant) -> io::Result<()> {
        self.remaining(now)?;
        if self.phase == Phase::Startup {
            self.phase = Phase::Drain;
            self.deadline = now + DRAIN;
        }
        Ok(())
    }
    pub(super) fn unavailable(&mut self, now: Instant) -> io::Result<()> {
        self.remaining(now)?;
        if self.phase == Phase::Drain {
            self.phase = Phase::Replacement;
            self.deadline = now + STARTUP;
        }
        Ok(())
    }
    pub(super) fn remaining(&self, now: Instant) -> io::Result<Duration> {
        self.deadline.checked_duration_since(now).filter(|value| !value.is_zero())
            .ok_or_else(|| io::Error::new(io::ErrorKind::TimedOut, match self.phase {
                Phase::Startup => "daemon startup deadline expired after 20 seconds",
                Phase::Drain => "daemon upgrade drain deadline expired after 300 seconds; running builds were not cancelled",
                Phase::Replacement => "replacement daemon startup deadline expired after 20 seconds",
            }))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn long_drain_has_one_fixed_budget_and_replacement_gets_its_own() {
        let start = Instant::now();
        let mut timer = LifecycleDeadline::new(start);
        timer.retiring(start + Duration::from_secs(5)).unwrap();
        timer.retiring(start + Duration::from_secs(100)).unwrap();
        assert_eq!(
            timer.remaining(start + Duration::from_secs(304)).unwrap(),
            Duration::from_secs(1)
        );
        timer.unavailable(start + Duration::from_secs(304)).unwrap();
        timer.unavailable(start + Duration::from_secs(310)).unwrap();
        assert_eq!(
            timer.remaining(start + Duration::from_secs(323)).unwrap(),
            Duration::from_secs(1)
        );
        assert!(timer
            .remaining(start + Duration::from_secs(324))
            .unwrap_err()
            .to_string()
            .contains("replacement"));
    }
    #[test]
    fn repeated_retirement_never_extends_deadline_and_expiry_cannot_change_phase() {
        let start = Instant::now();
        let mut timer = LifecycleDeadline::new(start);
        timer.retiring(start).unwrap();
        timer.retiring(start + Duration::from_secs(299)).unwrap();
        assert!(timer.unavailable(start + DRAIN).is_err());
        assert!(timer
            .retiring(start + DRAIN)
            .unwrap_err()
            .to_string()
            .contains("300 seconds"));
    }
    #[test]
    fn ordinary_startup_retries_never_extend_budget() {
        let start = Instant::now();
        let mut timer = LifecycleDeadline::new(start);
        timer.unavailable(start + Duration::from_secs(19)).unwrap();
        assert!(timer.retiring(start + STARTUP).is_err());
        assert!(timer
            .remaining(start + STARTUP)
            .unwrap_err()
            .to_string()
            .contains("startup"));
    }
    #[test]
    fn busy_listener_does_not_admit_replacement_or_shorten_drain() {
        let start = Instant::now();
        let mut timer = LifecycleDeadline::new(start);
        timer.retiring(start).unwrap();
        for error in [
            io::Error::from(io::ErrorKind::WouldBlock),
            io::Error::from(io::ErrorKind::TimedOut),
            io::Error::from_raw_os_error(231),
        ] {
            assert!(!super::super::listener_absent(&error));
        }
        assert_eq!(
            timer.remaining(start + Duration::from_secs(30)).unwrap(),
            Duration::from_secs(270)
        );
        assert!(super::super::listener_absent(&io::Error::from(
            io::ErrorKind::NotFound
        )));
    }
}
