//! Request-local sampling only; never cache or semantic authority.
use std::{
    collections::hash_map::RandomState,
    hash::{BuildHasher, Hasher},
    sync::atomic::{AtomicU64, Ordering},
};
#[derive(Clone, Copy)]
enum Mode {
    Off,
    Sample,
    All,
}
pub(crate) struct VerifyPolicy {
    mode: Mode,
    seed: u64,
    tickets: AtomicU64,
    pub checked: AtomicU64,
    pub mismatches: AtomicU64,
    pub anonymous_initializer_checked: AtomicU64,
    pub anonymous_initializer_mismatches: AtomicU64,
}
impl VerifyPolicy {
    pub(crate) fn from_environment() -> Self {
        let enabled = std::env::var_os("DMBD_VERIFY").is_some_and(|v| v == "1");
        let ci = std::env::var_os("CI").is_some_and(|v| v != "" && v != "0" && v != "false");
        Self::new(enabled, ci)
    }
    fn new(enabled: bool, ci: bool) -> Self {
        let mut hash = RandomState::new().build_hasher();
        hash.write_u8(1);
        Self {
            mode: if !enabled {
                Mode::Off
            } else if ci {
                Mode::All
            } else {
                Mode::Sample
            },
            seed: hash.finish(),
            tickets: AtomicU64::new(0),
            checked: AtomicU64::new(0),
            mismatches: AtomicU64::new(0),
            anonymous_initializer_checked: AtomicU64::new(0),
            anonymous_initializer_mismatches: AtomicU64::new(0),
        }
    }
    pub(crate) fn enabled(&self) -> bool {
        !matches!(self.mode, Mode::Off)
    }
    pub(crate) fn select(&self) -> bool {
        match self.mode {
            Mode::Off => false,
            Mode::All => true,
            Mode::Sample => {
                let mut x = self
                    .tickets
                    .fetch_add(1, Ordering::Relaxed)
                    .wrapping_add(self.seed);
                x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
                x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
                (x ^ (x >> 31)) % 20 == 0
            }
        }
    }
    #[cfg(test)]
    pub(crate) fn all() -> Self {
        Self::new(true, true)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn disabled_and_ci_modes_do_not_sample() {
        let off = VerifyPolicy::new(false, true);
        let all = VerifyPolicy::all();
        for _ in 0..100 {
            assert!(!off.select());
            assert!(all.select());
        }
        assert_eq!(off.tickets.load(Ordering::Relaxed), 0);
    }
}

impl super::ProcedureMemo {
    /// These counters cover procedure hits only; initializer counters are separate.
    pub fn procedure_verification_counts(&self) -> (u64, u64) {
        (
            self.verification.checked.load(Ordering::Relaxed),
            self.verification.mismatches.load(Ordering::Relaxed),
        )
    }
    /// Request-scoped legacy anonymous initializer disk-hit verification.
    pub fn anonymous_initializer_verification_counts(&self) -> (u64, u64) {
        (
            self.verification
                .anonymous_initializer_checked
                .load(Ordering::Relaxed),
            self.verification
                .anonymous_initializer_mismatches
                .load(Ordering::Relaxed),
        )
    }
    #[cfg(test)]
    pub(crate) fn with_all_procedure_verification(mut self) -> Self {
        self.verification = VerifyPolicy::all();
        self
    }
}
