//! Idle age starts after completed connections, not their arrival time.
//! One local clock observes the existing lifecycle; no new queue or timeout.
use super::*;
/// Publish before the zero-connection release. The serve-loop Acquire zero
/// observation then orders this completion before its final counter recheck.
pub(super) fn finished(completed: &AtomicU64, connections: &AtomicUsize) {
    completed.fetch_add(1, Ordering::Release);
    connections.fetch_sub(1, Ordering::AcqRel);
}

pub(super) struct Activity {
    since: Instant,
    completed: u64,
}
impl Activity {
    pub(super) fn new(now: Instant, completed: u64) -> Self {
        Self {
            since: now,
            completed,
        }
    }
    pub(super) fn accepted(&mut self, now: Instant) {
        self.since = now;
    }
    pub(super) fn observe_completed(&mut self, now: Instant, completed: u64) {
        if self.completed != completed {
            self.since = now;
            self.completed = completed;
        }
    }
    pub(super) fn matches_completed(&self, completed: u64) -> bool {
        self.completed == completed
    }
    pub(super) fn elapsed(&self) -> Duration {
        self.elapsed_at(Instant::now())
    }
    fn elapsed_at(&self, now: Instant) -> Duration {
        now.saturating_duration_since(self.since)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn long_query_completion_starts_a_fresh_idle_interval() {
        let start = Instant::now();
        let mut activity = Activity::new(start, 7);
        let completed = start + Duration::from_secs(99);
        assert!(activity.elapsed_at(completed) >= Duration::from_secs(60));
        activity.observe_completed(completed, 8);
        assert_eq!(activity.elapsed_at(completed), Duration::ZERO);
        assert_eq!(
            activity.elapsed_at(completed + Duration::from_secs(59)),
            Duration::from_secs(59)
        );
        activity.observe_completed(completed + Duration::from_secs(59), 8);
        assert_eq!(
            activity.elapsed_at(completed + Duration::from_secs(60)),
            Duration::from_secs(60)
        );
    }
    #[test]
    fn completion_racing_idle_decision_invalidates_the_old_observation() {
        let now = Instant::now();
        let mut activity = Activity::new(now, 10);
        assert!(activity.matches_completed(10));
        assert!(!activity.matches_completed(11));
        activity.observe_completed(now + Duration::from_secs(90), 11);
        assert!(activity.matches_completed(11));
        assert_eq!(
            activity.elapsed_at(now + Duration::from_secs(90)),
            Duration::ZERO
        );
    }
    #[test]
    fn a_new_connection_is_activity_without_a_completion_or_timer_override() {
        let now = Instant::now();
        let mut activity = Activity::new(now, 1);
        activity.accepted(now + Duration::from_secs(59));
        assert_eq!(
            activity.elapsed_at(now + Duration::from_secs(60)),
            Duration::from_secs(1)
        );
        assert!(activity.matches_completed(1));
    }
    #[test]
    fn final_zero_connection_observation_publishes_all_completions_before_idle_check() {
        // Local atomics exercise the actual production bridge without a
        // process-global completion counter being changed by parallel tests.
        let completed = AtomicU64::new(7);
        let connections = AtomicUsize::new(2);
        let start = Instant::now();
        let mut activity = Activity::new(start, 7);
        std::thread::scope(|scope| {
            for _ in 0..2 {
                scope.spawn(|| finished(&completed, &connections));
            }
            let deadline = Instant::now() + Duration::from_secs(2);
            while connections.load(Ordering::Acquire) != 0 {
                assert!(
                    Instant::now() < deadline,
                    "short completion workers did not finish"
                );
                std::thread::yield_now();
            }
            let observed = completed.load(Ordering::Acquire);
            assert_eq!(observed, 9);
            assert!(
                !activity.matches_completed(observed),
                "stale idle observation accepted final zero"
            );
            activity.observe_completed(start + Duration::from_secs(99), observed);
            assert_eq!(
                activity.elapsed_at(start + Duration::from_secs(99)),
                Duration::ZERO
            );
        });
    }
    #[test]
    fn wrapping_completion_count_still_refreshes_idle_without_an_order_comparison() {
        let start = Instant::now();
        let mut activity = Activity::new(start, u64::MAX);
        let completed = AtomicU64::new(u64::MAX);
        let connections = AtomicUsize::new(1);
        finished(&completed, &connections);
        assert_eq!(connections.load(Ordering::Acquire), 0);
        let observed = completed.load(Ordering::Acquire);
        assert_eq!(observed, 0);
        assert!(!activity.matches_completed(observed));
        activity.observe_completed(start + Duration::from_secs(99), observed);
        assert_eq!(
            activity.elapsed_at(start + Duration::from_secs(99)),
            Duration::ZERO
        );
    }
}
