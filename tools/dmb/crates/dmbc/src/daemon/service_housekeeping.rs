//! Idle ownership transitions, independent of incoming connection activity.
use super::*;

#[path = "service_housekeeping_allocations.rs"]
mod allocations;

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
    if age >= SESSION_IDLE || pressured && previous >= 3 {
        4
    } else if pressured && previous >= 2 {
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
                if Arc::strong_count(slot) != 1 && !pressured {
                    continue;
                }
                // Queued requests keep their slot, but do not borrow host state.
                // Exclude currently running hosts before bounding the candidates.
                if matches!(slot.host.try_lock(), Err(std::sync::TryLockError::WouldBlock)) {
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
            // Never remove a request-owned slot. Under pressure its idle host
            // may be cleared in place only while no build borrows host state.
            if !slots
                .get(&key)
                .is_some_and(|current| Arc::ptr_eq(current, &slot))
                || Arc::strong_count(&slot) != 2 && !pressured
                || *slot.last.lock().unwrap_or_else(|e| e.into_inner()) != last
            {
                continue;
            }
            let mut host = match slot.host.try_lock() {
                Ok(host) => host,
                Err(std::sync::TryLockError::Poisoned(error)) => error.into_inner(),
                Err(std::sync::TryLockError::WouldBlock) => continue,
            };
            if next == 4 && Arc::strong_count(&slot) == 2 {
                let removed = slots.remove(&key);
                drop(slots);
                let before = transport::private_bytes();
                let requested_before = allocations::requested_live();
                let started = Instant::now();
                // Pool joins and artifact destructors never run under slot roster lock.
                drop(host);
                drop(removed);
                drop(slot);
                super::super::emit_stderr(format_args!(
                    "dmbd idle release tier=session project={} pressure={pressured} private-before={before:?} private-after={:?} seconds={:.6} rust-requested-live-before={requested_before} rust-requested-live-after={}",
                    key.manifest.display(),
                    transport::private_bytes(),
                    started.elapsed().as_secs_f64(),
                    allocations::requested_live()
                ));
                continue;
            }
            slot.idle_tier.store(next, Ordering::Release);
            drop(slots);
            if next == 4 {
                // Preserve the queued Slot and its cancellation/serialization
                // state; replace only idle compiler ownership outside roster lock.
                let before = transport::private_bytes();
                let requested_before = allocations::requested_live();
                self.reset_host(&mut host);
                super::super::emit_stderr(format_args!(
                    "dmbd idle release tier=queued-session project={} pressure={pressured} private-before={before:?} private-after={:?} rust-requested-live-before={requested_before} rust-requested-live-after={}",
                    key.manifest.display(),
                    transport::private_bytes(),
                    allocations::requested_live()
                ));
                continue;
            }
            host.release_idle_executor();
            if next >= 2 {
                let before = transport::private_bytes();
                let requested_before = allocations::requested_live();
                let started = Instant::now();
                if next == 3 {
                    host.release_idle_compiler_artifacts();
                } else {
                    host.release_idle_artifacts();
                }
                super::super::emit_stderr(format_args!(
                    "dmbd artifact release tier={next} project={} private-before={before:?} private-after={:?} seconds={:.6} rust-requested-live-before={requested_before} rust-requested-live-after={}",
                    key.manifest.display(),
                    transport::private_bytes(),
                    started.elapsed().as_secs_f64(),
                    allocations::requested_live()
                ));
            }
            super::super::emit_stderr(format_args!(
                "dmbd idle release tier={} project={} pressure={pressured}",
                if next == 3 {
                    "compiler-artifacts"
                } else if next >= 2 {
                    "rich-buffers"
                } else {
                    "executor"
                },
                key.manifest.display()
            ));
        }
        self.capacity.notify_all();
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
        assert_eq!(target(Duration::from_secs(600), false, 2), 4);
        assert_eq!(target(Duration::ZERO, true, 0), 2);
        assert_eq!(target(Duration::ZERO, true, 2), 3);
        assert_eq!(target(Duration::ZERO, false, 3), 0);
        assert_eq!(target(Duration::ZERO, true, 3), 4);
    }
    #[test]
    fn bounded_eviction_is_deterministic_and_preserves_request_owned_slots() {
        let shared = Shared {
            engines: Arc::new(Default::default()),
            executors: Arc::new(Default::default()),
            procedures: Arc::new(Default::default()),
            compiler: 1,
            retiring: AtomicBool::new(false),
            slots: Mutex::new(BTreeMap::new()),
            running: Mutex::new(0),
            workers: Mutex::new(0),
            max_workers: 8,
            soft_private_bytes: soft_memory::DEFAULT,
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
