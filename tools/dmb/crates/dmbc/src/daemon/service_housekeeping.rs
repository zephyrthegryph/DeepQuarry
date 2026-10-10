//! Idle ownership transitions, independent of incoming connection activity.
use super::*;

const EXECUTOR_IDLE: Duration = Duration::from_secs(30);
const SESSION_IDLE: Duration = Duration::from_secs(600);
const RELEASES_PER_PASS: usize = 4;

pub(super) struct Deadline(Instant);
impl Deadline {
    pub(super) fn new(now: Instant) -> Self {
        Self(now + Duration::from_secs(1))
    }
    pub(super) fn due(&mut self, now: Instant) -> bool {
        if now < self.0 {
            return false;
        }
        // Advance from now, never repeatedly catch up after a long release.
        self.0 = now + Duration::from_secs(1);
        true
    }
}

fn target(age: Duration, pressured: bool, previous: usize) -> usize {
    if age >= SESSION_IDLE || pressured && previous >= 2 {
        3
    } else if pressured {
        2
    } else if age >= EXECUTOR_IDLE {
        1
    } else {
        0
    }
}

impl Shared {
    pub(super) fn housekeep(&self, now: Instant, pressured: bool) {
        let candidates = {
            let slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
            let mut candidates = BTreeMap::new();
            for (key, slot) in slots.iter() {
                if Arc::strong_count(slot) != 1 {
                    continue;
                }
                let last = *slot.last.lock().unwrap_or_else(|e| e.into_inner());
                let previous = slot.idle_tier.load(Ordering::Acquire);
                let next = target(now.saturating_duration_since(last), pressured, previous);
                if next > previous {
                    candidates.insert((last, key.clone()), (Arc::clone(slot), next));
                    if candidates.len() > RELEASES_PER_PASS {
                        candidates.pop_last();
                    }
                }
            }
            candidates
        };
        for ((last, key), (slot, next)) in candidates {
            let mut slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
            // A newly admitted/queued request owns another Arc. Never trim it.
            if !slots
                .get(&key)
                .is_some_and(|current| Arc::ptr_eq(current, &slot))
                || Arc::strong_count(&slot) != 2
                || *slot.last.lock().unwrap_or_else(|e| e.into_inner()) != last
            {
                continue;
            }
            if next == 3 {
                let removed = slots.remove(&key);
                drop(slots);
                // Pool joins and artifact destructors never run under slot roster lock.
                drop(removed);
                drop(slot);
                super::super::emit_stderr(format_args!(
                    "dmbd idle release tier=session project={} pressure={pressured}",
                    key.manifest.display()
                ));
                continue;
            }
            let mut host = match slot.host.try_lock() {
                Ok(host) => host,
                Err(std::sync::TryLockError::Poisoned(error)) => error.into_inner(),
                Err(std::sync::TryLockError::WouldBlock) => continue,
            };
            slot.idle_tier.store(next, Ordering::Release);
            drop(slots);
            host.release_idle_executor();
            if next >= 2 {
                host.release_idle_artifacts();
            }
            super::super::emit_stderr(format_args!(
                "dmbd idle release tier={} project={} pressure={pressured}",
                if next >= 2 { "rich-buffers" } else { "executor" },
                key.manifest.display()
            ));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn incoming_activity_cannot_defer_deadline_and_no_catchup_loop() {
        let now = Instant::now();
        let mut deadline = Deadline::new(now);
        assert!(!deadline.due(now + Duration::from_millis(999)));
        assert!(deadline.due(now + Duration::from_secs(1)));
        assert!(deadline.due(now + Duration::from_secs(40)));
        assert!(!deadline.due(now + Duration::from_secs(40)));
    }
    #[test]
    fn idle_tiers_and_pressure_have_explicit_order() {
        assert_eq!(target(Duration::from_secs(29), false, 0), 0);
        assert_eq!(target(Duration::from_secs(30), false, 0), 1);
        assert_eq!(target(Duration::from_secs(120), false, 1), 1);
        assert_eq!(target(Duration::from_secs(599), false, 1), 1);
        assert_eq!(target(Duration::from_secs(600), false, 2), 3);
        assert_eq!(target(Duration::ZERO, true, 0), 2);
        assert_eq!(target(Duration::ZERO, true, 2), 3);
    }
    #[test]
    fn bounded_eviction_is_deterministic_and_preserves_request_owned_slots() {
        let shared = Shared {
            engines: Arc::new(Default::default()),
            executors: Arc::new(Default::default()),
            compiler: 1,
            retiring: AtomicBool::new(false),
            slots: Mutex::new(BTreeMap::new()),
            running: Mutex::new(0),
            workers: Mutex::new(0),
            capacity: Condvar::new(),
            connections: AtomicUsize::new(0),
        };
        let now = Instant::now();
        let last = now - Duration::from_secs(601);
        for name in ["f", "e", "d", "c", "b", "a"] {
            let slot = shared.slot(PathBuf::from(name), &BTreeMap::new(), None);
            *slot.last.lock().unwrap() = last;
        }
        let active = shared.slot(PathBuf::from("active"), &BTreeMap::new(), None);
        *active.last.lock().unwrap() = last - Duration::from_secs(1);
        shared.housekeep(now, false);
        let remaining = shared
            .slots
            .lock()
            .unwrap()
            .keys()
            .map(|key| key.manifest.clone())
            .collect::<Vec<_>>();
        assert_eq!(remaining, ["active", "e", "f"].map(PathBuf::from));
        drop(active);
        shared.housekeep(now, false);
        assert!(shared.slots.lock().unwrap().is_empty());
    }
}
