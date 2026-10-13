//! Idle ownership transitions, independent of incoming connection activity.
use super::*;

#[path = "service_housekeeping_allocations.rs"]
pub(super) mod allocations;

const EXECUTOR_IDLE: Duration = Duration::from_secs(30);
// A retained session is the next edit's resident state; developers iterate in
// minutes but not always within ten, so the whole-session release waits an hour.
pub(super) const SESSION_IDLE: Duration = Duration::from_secs(3600);
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

// Named lifecycle stages; pressure is resampled by the ordinary next pass.
const OPTIONAL_IMAGES: usize = 4;
const COMPACT_SYMBOLIC: usize = 5;
const REMAINING_OPTIONAL: usize = 6;
const SESSION_RELEASE: usize = 7;
// Soft pressure only sheds rich/transient buffers (tier 2). The symbolic memo,
// generation, link bindings and frontend host that make the next edit resident
// are released (tiers 3..7) only above the hard ceiling or after SESSION_IDLE.
fn target(age: Duration, pressured: bool, hard: bool, previous: usize) -> usize {
    if pressured && !hard {
        return if age >= SESSION_IDLE { SESSION_RELEASE } else { 2 };
    }
    if age >= SESSION_IDLE || pressured && previous >= REMAINING_OPTIONAL {
        SESSION_RELEASE
    } else if pressured && previous >= COMPACT_SYMBOLIC {
        REMAINING_OPTIONAL
    } else if pressured && previous >= OPTIONAL_IMAGES {
        COMPACT_SYMBOLIC
    } else if pressured && previous >= 3 {
        OPTIONAL_IMAGES
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
    pub(super) fn housekeep(&self, now: Instant, pressured: bool, hard: bool) {
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
                let next = target(now.saturating_duration_since(last), pressured, hard, previous);
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
            if next == SESSION_RELEASE && Arc::strong_count(&slot) == 2 {
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
                    "dmbd idle release tier=session project={} pressure={pressured} hard={hard} private-before={before:?} private-after={:?} seconds={:.6} rust-requested-live-before={requested_before} rust-requested-live-after={}",
                    key.manifest.display(),
                    transport::private_bytes(),
                    started.elapsed().as_secs_f64(),
                    allocations::requested_live()
                ));
                continue;
            }
            slot.idle_tier.store(next, Ordering::Release);
            drop(slots);
            if next == SESSION_RELEASE {
                // Preserve the queued Slot and its cancellation/serialization
                // state; replace only idle compiler ownership outside roster lock.
                let before = transport::private_bytes();
                let requested_before = allocations::requested_live();
                self.reset_host(&mut host);
                super::super::emit_stderr(format_args!(
                    "dmbd idle release tier=queued-session project={} pressure={pressured} hard={hard} private-before={before:?} private-after={:?} rust-requested-live-before={requested_before} rust-requested-live-after={}",
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
                if next == OPTIONAL_IMAGES {
                    host.release_idle_optional_images();
                } else if next == COMPACT_SYMBOLIC {
                    host.release_idle_compact_symbolic();
                } else if next == REMAINING_OPTIONAL {
                    host.release_idle_remaining_optional();
                } else if next == 3 {
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
                if next == OPTIONAL_IMAGES {
                    "optional-images"
                } else if next == COMPACT_SYMBOLIC {
                    "compact-symbolic"
                } else if next == REMAINING_OPTIONAL {
                    "remaining-optional"
                } else if next == 3 {
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
    fn soft_pressure_never_reaches_symbolic_core_tiers() {
        for previous in 0..=SESSION_RELEASE {
            assert_eq!(target(Duration::ZERO, true, false, previous), 2);
        }
        assert_eq!(target(SESSION_IDLE, true, false, 2), SESSION_RELEASE);
    }
    #[test]
    fn idle_tiers_and_pressure_have_explicit_order() {
        assert_eq!(target(Duration::from_secs(29), false, false, 0), 0);
        assert_eq!(target(Duration::from_secs(30), false, false, 0), 1);
        assert_eq!(target(Duration::from_secs(120), false, false, 1), 1);
        assert_eq!(target(SESSION_IDLE - Duration::from_secs(1), false, false, 1), 1);
        assert_eq!(target(SESSION_IDLE, false, false, 2), SESSION_RELEASE);
        assert_eq!(target(Duration::ZERO, true, true, 0), 2);
        assert_eq!(target(Duration::ZERO, true, true, 2), 3);
        assert_eq!(target(Duration::ZERO, false, false, 3), 0);
        assert_eq!(target(Duration::ZERO, true, true, 3), OPTIONAL_IMAGES);
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
        let last = now - SESSION_IDLE - Duration::from_secs(1);
        for name in ["f", "e", "d", "c", "b", "a"] {
            let slot = shared.slot(PathBuf::from(name), &BTreeMap::new(), None);
            *slot.last.lock().unwrap() = last;
        }
        let active = shared.slot(PathBuf::from("active"), &BTreeMap::new(), None);
        *active.last.lock().unwrap() = last - Duration::from_secs(1);
        shared.housekeep(now, false, false);
        let remaining = shared
            .slots
            .lock()
            .unwrap()
            .keys()
            .map(|key| key.manifest.clone())
            .collect::<Vec<_>>();
        assert_eq!(remaining, ["active", "e", "f"].map(PathBuf::from));
        drop(active);
        shared.housekeep(now, false, false);
        assert!(shared.slots.lock().unwrap().is_empty());
    }
}

#[cfg(test)]
#[path = "service_housekeeping_optional_tests.rs"]
mod optional_tests;
