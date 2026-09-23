//! Activity and sleep for laws (`rust_architecture.md` §4.4).
//!
//! Fields already sleep per chunk (`core::field`, kept as-is). This is the
//! equivalent for a law's own domain -- rows, regions or cells -- built on
//! [`crate::bitset::DenseBitSet`]: a plain bitset of which indices are due
//! to run next step. Rows are woken by a command write to that row, a
//! region payload change, a watch/reactor timer firing, or an explicit
//! [`crate::law::LawCtx::wake`]; a law returns [`crate::law::Settle::Sleep`]
//! for an index to put it back to sleep.

use crate::bitset::DenseBitSet;

/// Which rows/regions/cells of one law's domain are due to run.
#[derive(Clone, Debug, Default)]
pub struct Activity {
    awake: DenseBitSet,
}

impl Activity {
    /// Starts with capacity for indices `0..len`, all asleep.
    #[must_use]
    pub fn new(len: u32) -> Self {
        Self {
            awake: DenseBitSet::new(len),
        }
    }

    #[must_use]
    pub const fn capacity(&self) -> u32 {
        self.awake.capacity()
    }

    /// Grows (never shrinks) to hold `0..len`. New indices start asleep.
    pub fn grow(&mut self, len: u32) {
        self.awake.grow(len);
    }

    /// Wakes `index`; returns whether it was newly woken (`false` if it was
    /// already awake, or out of range).
    pub fn wake(&mut self, index: u32) -> bool {
        self.awake.insert(index)
    }

    /// Wakes every currently-valid index (a fresh boot, or a global event
    /// like a topology change that could affect anything).
    pub fn wake_all(&mut self) {
        for i in 0..self.awake.capacity() {
            self.awake.insert(i);
        }
    }

    /// Puts `index` to sleep; returns whether it was awake.
    pub fn sleep(&mut self, index: u32) -> bool {
        self.awake.remove(index)
    }

    #[must_use]
    pub fn is_awake(&self, index: u32) -> bool {
        self.awake.contains(index)
    }

    #[must_use]
    pub fn awake_count(&self) -> u32 {
        self.awake.count()
    }

    #[must_use]
    pub fn is_idle(&self) -> bool {
        self.awake.is_empty()
    }

    /// Every currently-awake index, in ascending order. Does not clear
    /// them: a law decides per index whether to stay awake by the
    /// [`crate::law::Settle`] it returns, so the driver applies that after
    /// running the step, via [`wake`](Self::wake)/[`sleep`](Self::sleep) on
    /// each index -- iterating doesn't itself change anything.
    pub fn iter(&self) -> impl Iterator<Item = u32> + '_ {
        self.awake.iter()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::law::Settle;

    #[test]
    fn starts_fully_asleep() {
        let a = Activity::new(10);
        assert!(a.is_idle());
        assert_eq!(a.awake_count(), 0);
        assert!(!a.is_awake(3));
    }

    #[test]
    fn wake_and_sleep_round_trip() {
        let mut a = Activity::new(10);
        assert!(a.wake(3));
        assert!(!a.wake(3), "already awake");
        assert!(a.is_awake(3));
        assert_eq!(a.awake_count(), 1);
        assert!(a.sleep(3));
        assert!(!a.sleep(3), "already asleep");
        assert!(a.is_idle());
    }

    #[test]
    fn wake_all_covers_the_whole_capacity() {
        let mut a = Activity::new(5);
        a.wake_all();
        assert_eq!(a.awake_count(), 5);
        for i in 0..5 {
            assert!(a.is_awake(i));
        }
    }

    #[test]
    fn grow_keeps_existing_state_and_new_indices_start_asleep() {
        let mut a = Activity::new(4);
        a.wake(1);
        a.grow(8);
        assert!(a.is_awake(1));
        assert!(!a.is_awake(6));
        assert_eq!(a.capacity(), 8);
    }

    #[test]
    fn iter_lists_only_awake_indices_in_order() {
        let mut a = Activity::new(10);
        a.wake(7);
        a.wake(2);
        a.wake(5);
        assert_eq!(a.iter().collect::<Vec<_>>(), vec![2, 5, 7]);
    }

    /// A driver's per-step loop: run every awake index's law, apply its
    /// `Settle`, and confirm the activity set reflects it afterward.
    #[test]
    fn settle_drives_the_activity_set_like_a_driver_would() {
        let mut a = Activity::new(4);
        a.wake_all();
        let settle_for = |i: u32| if i == 2 { Settle::Sleep } else { Settle::Active };
        let due: Vec<u32> = a.iter().collect();
        for i in due {
            match settle_for(i) {
                Settle::Active => {} // stays awake
                Settle::Sleep => {
                    a.sleep(i);
                }
            }
        }
        assert!(!a.is_awake(2));
        assert!(a.is_awake(0));
        assert!(a.is_awake(1));
        assert!(a.is_awake(3));
        assert_eq!(a.awake_count(), 3);
    }
}
