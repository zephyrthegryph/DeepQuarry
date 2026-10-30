//! Process-wide sharing of immutable compose-side tables that two sessions build from the same inputs.
//!
//! A second worktree or variant of one tree derives equal string indexes and method rosters; each session held its
//! own. A table here is immutable once built, so equal tables are one allocation. The pool holds weak references only
//! (an entry lives exactly as long as some session holds it), and a candidate is adopted only after a full equality
//! check, so the fingerprint merely selects a bucket. `get_or_build` runs the check before building, so a session that
//! finds its table already live skips the build as well.
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, Weak},
};

pub(crate) struct Pool<T> {
    buckets: Mutex<Buckets<T>>,
}
struct Buckets<T> {
    map: HashMap<u64, Vec<Weak<T>>>,
    sweep_at: usize,
}
impl<T> Pool<T> {
    pub(crate) fn new() -> Self {
        Self {
            buckets: Mutex::new(Buckets {
                map: HashMap::new(),
                sweep_at: 64,
            }),
        }
    }
    /// The live table in bucket `fingerprint` for which `same` holds, else the one `build` makes (registered weakly).
    pub(crate) fn get_or_build(
        &self,
        label: &str,
        fingerprint: u64,
        same: impl Fn(&T) -> bool,
        build: impl FnOnce() -> T,
    ) -> Arc<T> {
        let started = std::time::Instant::now();
        let mut buckets = self.buckets.lock().unwrap_or_else(|e| e.into_inner());
        if buckets.map.len() >= buckets.sweep_at {
            buckets.map.retain(|_, bucket| {
                bucket.retain(|entry| entry.strong_count() > 0);
                !bucket.is_empty()
            });
            buckets.sweep_at = (buckets.map.len() * 2).max(64);
        }
        let bucket = buckets.map.entry(fingerprint).or_default();
        bucket.retain(|entry| entry.strong_count() > 0);
        let mut compared = 0usize;
        for entry in bucket.iter() {
            if let Some(held) = entry.upgrade() {
                compared += 1;
                if same(&held) {
                    log_cost(label, started, compared, true);
                    return held;
                }
            }
        }
        let shared = Arc::new(build());
        bucket.push(Arc::downgrade(&shared));
        log_cost(label, started, compared, false);
        shared
    }
}
impl<T: PartialEq> Pool<T> {
    /// `value`, or the live equal table already in bucket `fingerprint` (the candidate is then dropped).
    pub(crate) fn share(&self, label: &str, fingerprint: u64, value: T) -> Arc<T> {
        let slot = std::cell::RefCell::new(Some(value));
        self.get_or_build(
            label,
            fingerprint,
            |held| slot.borrow().as_ref().is_some_and(|candidate| held == candidate),
            || slot.borrow_mut().take().expect("candidate consumed once"),
        )
    }
}
/// Per-call cost (lock wait, sweep, equality checks, build) when `DMB_TIMINGS_DETAIL=1`.
fn log_cost(label: &str, started: std::time::Instant, compared: usize, adopted: bool) {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    if *ENABLED.get_or_init(|| std::env::var_os("DMB_TIMINGS_DETAIL").is_some_and(|value| value == "1")) {
        eprintln!(
            "detail compose.pool.{label}: {:.4}s compared={compared} adopted={adopted}",
            started.elapsed().as_secs_f64()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_equal_live_table_is_shared_without_building_and_a_dropped_one_is_rebuilt() {
        let pool: Pool<Vec<u32>> = Pool::new();
        let first = pool.get_or_build("t", 1, |held| held == &[1, 2], || vec![1, 2]);
        let second = pool.get_or_build("t", 1, |held| held == &[1, 2], || panic!("an equal live table must not rebuild"));
        assert!(Arc::ptr_eq(&first, &second));
        let different = pool.get_or_build("t", 1, |held| held == &[3], || vec![3]);
        assert!(!Arc::ptr_eq(&first, &different));
        drop((first, second));
        let rebuilt = pool.get_or_build("t", 1, |held| held == &[1, 2], || vec![1, 2]);
        assert_eq!(*rebuilt, vec![1, 2]);
    }
}
