//! Idle ownership transitions, independent of incoming connection activity.
use super::*;

#[path = "service_housekeeping_allocations.rs"]
pub(super) mod allocations;

const EXECUTOR_IDLE: Duration = Duration::from_secs(30);
// A retained session is the next edit's resident state; developers iterate in
// minutes but not always within ten, so the whole-session release waits an hour.
pub(super) const SESSION_IDLE: Duration = Duration::from_secs(3600);
const RELEASES_PER_PASS: usize = 4;
/// How long the most recently used session stays exempt from memory-pressure degradation.
pub(super) const MRU_PROTECTED: Duration = Duration::from_secs(1800);
/// Set when a retained session was dropped because its project no longer exists on disk.
pub(super) static ROOT_GONE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);

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
pub(super) const SESSION_RELEASE: usize = 7;
// Soft pressure sheds nothing. Measured on DeepQuarry (2026-10-15): the tier-2 release of rich
// buffers (prepared sources, maps, link bindings, initializer assemblies) returned no private
// memory (private bytes before and after differ by under 0.1%: the freed pages are scattered among
// live blocks), yet it cost the next edit about 11 s of re-preparing 5,800 sources plus the map and
// link rebuilds, and because the daemon stays above the soft limit it fired after every build. The
// symbolic memo, generation, link bindings and frontend host that make the next edit resident are
// released (tiers 3..7) only above the hard ceiling or after SESSION_IDLE.
fn target(age: Duration, pressured: bool, hard: bool, previous: usize) -> usize {
    if pressured && !hard {
        return if age >= SESSION_IDLE { SESSION_RELEASE } else { previous };
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
    /// Drop the retained session of every idle slot (a daemon that is exiting serves no further edit). A slot whose host is
    /// building is left to finish; it is released on a later pass. True when anything was released.
    pub(super) fn release_for_retire(&self) -> bool {
        let slots: Vec<(SessionKey, Arc<Slot>)> = self
            .slots
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .map(|(key, slot)| (key.clone(), Arc::clone(slot)))
            .collect();
        let mut released = false;
        for (key, slot) in slots {
            let manifest = key.manifest.clone();
            if slot.idle_tier.load(Ordering::Acquire) == SESSION_RELEASE {
                continue;
            }
            // Never under the roster lock: a host drop joins pools and can take seconds.
            let Ok(mut host) = slot.host.try_lock() else { continue };
            let before = transport::private_bytes();
            self.reset_host(&mut host);
            slot.idle_tier.store(SESSION_RELEASE, Ordering::Release);
            note_eviction(&key, "daemon-retiring");
            released = true;
            super::super::emit_stderr(format_args!(
                "dmbd retire release project={} private-before={before:?} private-after={:?}",
                manifest.display(),
                transport::private_bytes()
            ));
        }
        released
    }

    /// Diagnostic (feature `allocation-sites`): apply the idle release ladder up to `upto` to every idle session, as the
    /// housekeeping pass would one tier per pass, so the next edit's latency can be measured per tier.
    #[cfg(feature = "allocation-sites")]
    pub(super) fn diag_release_tiers(&self, upto: usize) -> bool {
        let slots: Vec<(SessionKey, Arc<Slot>)> = self
            .slots
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .map(|(key, slot)| (key.clone(), Arc::clone(slot)))
            .collect();
        let mut released = false;
        for (key, slot) in slots {
            let Ok(mut host) = slot.host.try_lock() else { continue };
            host.release_idle_executor();
            for tier in 2..=upto {
                let before = transport::private_bytes();
                if tier == OPTIONAL_IMAGES {
                    host.release_idle_optional_images();
                } else if tier == COMPACT_SYMBOLIC {
                    host.release_idle_compact_symbolic();
                } else if tier == REMAINING_OPTIONAL {
                    host.release_idle_remaining_optional();
                } else if tier == 3 {
                    host.release_idle_compiler_artifacts();
                } else if tier == 2 {
                    host.release_idle_artifacts();
                }
                super::super::emit_stderr(format_args!(
                    "dmbd diagnostic release tier={tier} project={} private-before={before:?} private-after={:?}",
                    key.manifest.display(),
                    transport::private_bytes()
                ));
            }
            slot.idle_tier.store(upto.min(SESSION_RELEASE - 1), Ordering::Release);
            released = true;
        }
        released
    }

    pub(super) fn housekeep(&self, now: Instant, pressured: bool, hard: bool) {
        // The newest session is shielded from pressure degradation, except when the machine is about to page.
        let emergency = hard && self.memory_emergency();
        let candidates = {
            let slots = self.slots.lock().unwrap_or_else(|e| e.into_inner());
            let mut candidates = BTreeMap::new();
            // The session someone is iterating on is exempt from memory-pressure degradation while it is fresh: a single
            // retained session can alone exceed the budget (about 8.6 GB private on DeepQuarry), and degrading it after every
            // build would make every edit a full compile. Pressure sheds the other sessions (least recently used first).
            let protected = slots
                .iter()
                .map(|(key, slot)| (*slot.last.lock().unwrap_or_else(|e| e.into_inner()), key))
                .max()
                .filter(|(last, _)| now.saturating_duration_since(*last) < MRU_PROTECTED)
                .map(|(_, key)| key.clone());
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
                let shielded = pressured && protected.as_ref() == Some(key) && !emergency;
                let mut next = target(now.saturating_duration_since(last), pressured && !shielded, hard && !shielded, previous);
                // A removed worktree's session can never be edited again: release it whole, whatever the tier.
                if !key.manifest.exists() {
                    next = SESSION_RELEASE;
                    ROOT_GONE.store(true, Ordering::Release);
                }
                if next > previous {
                    candidates.insert((last, key.clone()), (Arc::clone(slot), next));
                    if candidates.len() > RELEASES_PER_PASS {
                        candidates.pop_last();
                    }
                }
            }
            // Over the memory budget with several retained projects: shed the least recently used project whole
            // (the next most recent stays resident) instead of degrading every session a tier at a time.
            if hard && slots.len() > 1 {
                if let Some((first, (slot, _))) = candidates.pop_first() {
                    candidates.clear();
                    candidates.insert(first, (slot, SESSION_RELEASE));
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
                note_eviction(
                    &key,
                    if !key.manifest.exists() {
                        "root-gone"
                    } else if hard {
                        "hard-memory-limit"
                    } else if pressured {
                        "memory-pressure"
                    } else {
                        "idle"
                    },
                );
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
                allocations::dump_sites("after_session_release");
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
                note_eviction(&key, if hard { "hard-memory-limit" } else if pressured { "memory-pressure" } else { "idle" });
                super::super::emit_stderr(format_args!(
                    "dmbd idle release tier=queued-session project={} pressure={pressured} hard={hard} private-before={before:?} private-after={:?} rust-requested-live-before={requested_before} rust-requested-live-after={}",
                    key.manifest.display(),
                    transport::private_bytes(),
                    allocations::requested_live()
                ));
                allocations::dump_sites("after_queued_session_release");
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
    fn soft_pressure_never_releases_anything_before_session_idle() {
        for previous in 0..=SESSION_RELEASE {
            assert_eq!(target(Duration::ZERO, true, false, previous), previous);
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
    fn a_fresh_single_session_over_the_hard_limit_keeps_its_state() {
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
        // The project must exist on disk: housekeeping drops sessions whose manifest is gone.
        let only = shared.slot(std::env::temp_dir(), None);
        *only.last.lock().unwrap() = now - Duration::from_secs(60);
        drop(only);
        // Hard pressure, as after every build of a session larger than the whole budget: nothing is degraded or released.
        shared.housekeep(now, true, true);
        let slots = shared.slots.lock().unwrap();
        let slot = slots.values().next().expect("the session survives");
        assert!(slot.idle_tier.load(Ordering::Acquire) <= 1, "only the idle executor may be released");
        drop(slots);
        // Once it has been idle past the protection window the ordinary pressure policy applies again.
        shared.housekeep(now + MRU_PROTECTED + Duration::from_secs(120), true, true);
        assert!(shared.slots.lock().unwrap().values().next().is_none_or(|slot| slot.idle_tier.load(Ordering::Acquire) > 0));
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
            let slot = shared.slot(PathBuf::from(name), None);
            *slot.last.lock().unwrap() = last;
        }
        let active = shared.slot(PathBuf::from("active"), None);
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
