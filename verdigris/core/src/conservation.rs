//! A generic conservation audit (`rust_core.md` §15).
//!
//! A domain registers each conserved quantity it cares about (gas moles per
//! species, energy in J across gas/heat/power, ...) with a [`Ledger`] by
//! name, reporting any *explicit external* [`Ledger::source`]/[`Ledger::sink`]
//! events for it (DM setting a mixture directly, a power cell's supply this
//! tick, energy crossing a domain boundary, ...) and then [`Ledger::check`]ing
//! its current total once per step. In debug and test builds this is a real
//! assertion: if the total moved by more than the recorded sources minus
//! sinks (within a tolerance), that is either a missed source/sink call
//! somewhere or an actual accounting leak, and it fails loudly instead of
//! drifting silently across many steps until a player notices missing gas
//! or power.
//!
//! This does not replace a domain's own targeted conservation tests (the
//! existing gas/heat proptests that check specific operations); it is the
//! one mechanism for the "did this *step*, as a whole, conserve its
//! declared quantities" question, shared instead of reimplemented per
//! domain.

use std::collections::HashMap;

#[derive(Clone, Copy, Debug, Default)]
struct Entry {
    last_total: f64,
    sources: f64,
    sinks: f64,
    initialized: bool,
}

/// A set of named conserved quantities, each checked independently.
#[derive(Debug, Default)]
pub struct Ledger {
    entries: HashMap<&'static str, Entry>,
}

/// A step moved `name`'s total by more than its recorded sources minus
/// sinks accounts for, beyond `tolerance`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Violation {
    pub name: &'static str,
    /// `total_now - total_at_last_check`.
    pub delta: f64,
    /// `sources - sinks` recorded since the last check.
    pub expected: f64,
    pub tolerance: f64,
}

impl std::fmt::Display for Violation {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "conservation violated for {:?}: total moved by {} but recorded sources-sinks only account for {} (tolerance {})",
            self.name, self.delta, self.expected, self.tolerance
        )
    }
}

impl std::error::Error for Violation {}

impl Ledger {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Records an explicit external addition to `name` since the last
    /// [`check`](Self::check) -- e.g. DM setting a gas mixture's moles
    /// directly, or a power cell's supply this tick. Never called for
    /// internal transfers between two things the ledger's `total` already
    /// covers (a transfer conserves on its own; only what crosses the
    /// boundary of what `total` measures is a source or a sink).
    pub fn source(&mut self, name: &'static str, amount: f64) {
        self.entries.entry(name).or_default().sources += amount;
    }

    /// As [`source`](Self::source), for an explicit external removal.
    pub fn sink(&mut self, name: &'static str, amount: f64) {
        self.entries.entry(name).or_default().sinks += amount;
    }

    /// Checks `name`'s current `total` against the sources/sinks recorded
    /// since the last check, within an absolute `tolerance`, then resets
    /// the accumulators for the next step. The first call for a given
    /// `name` only records the starting baseline (nothing to compare
    /// against yet), so callers can check from the first step without a
    /// separate "prime the ledger" call.
    pub fn check(
        &mut self,
        name: &'static str,
        total: f64,
        tolerance: f64,
    ) -> Result<(), Violation> {
        let entry = self.entries.entry(name).or_default();
        if !entry.initialized {
            entry.initialized = true;
            entry.last_total = total;
            entry.sources = 0.0;
            entry.sinks = 0.0;
            return Ok(());
        }
        let delta = total - entry.last_total;
        let expected = entry.sources - entry.sinks;
        entry.last_total = total;
        entry.sources = 0.0;
        entry.sinks = 0.0;
        if (delta - expected).abs() <= tolerance {
            Ok(())
        } else {
            Err(Violation {
                name,
                delta,
                expected,
                tolerance,
            })
        }
    }
}

/// Test-harness helper: [`Ledger::check`], panicking with the [`Violation`]
/// on failure instead of returning it. For a domain's own conservation
/// tests/proptests, where a panic is the right way to fail; production
/// step code should match on [`Ledger::check`]'s `Result` instead (e.g. to
/// report through `vg_describe`/a metrics counter rather than panic a live
/// server).
#[track_caller]
pub fn assert_conserved(ledger: &mut Ledger, name: &'static str, total: f64, tolerance: f64) {
    if let Err(violation) = ledger.check(name, total, tolerance) {
        panic!("{violation}");
    }
}

/// Something that holds conserved quantities: a field kind, a network
/// payload, a component column, a law's plain test type. The driver's
/// per-frame auto-wiring (`rust_architecture.md` §4.9) sums every declared
/// quantity across every source and checks it through a [`Ledger`], instead
/// of each domain writing its own `HeatLedger`/`Totals`/`Books`.
///
/// Implementations only *visit* (`visit(name, amount)` once per quantity
/// they hold); the caller does the summing, so a source never needs to know
/// what else is being counted.
pub trait Conserved {
    fn totals(&self, visit: &mut dyn FnMut(&'static str, f64));
}

/// Per-quantity sums for one check. Reused across frames (cleared, not
/// reallocated).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Totals {
    sums: Vec<(&'static str, f64)>,
}

impl Totals {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Zeroes every sum, keeping the names (so a quantity that drops to
    /// nothing still reads 0 rather than disappearing).
    pub fn clear(&mut self) {
        for (_, v) in &mut self.sums {
            *v = 0.0;
        }
    }

    pub fn add(&mut self, name: &'static str, amount: f64) {
        match self.sums.iter_mut().find(|(n, _)| *n == name) {
            Some((_, v)) => *v += amount,
            None => self.sums.push((name, amount)),
        }
    }

    /// Adds everything `source` holds.
    pub fn add_source(&mut self, source: &dyn Conserved) {
        source.totals(&mut |name, amount| self.add(name, amount));
    }

    #[must_use]
    pub fn get(&self, name: &str) -> f64 {
        self.sums
            .iter()
            .find(|(n, _)| *n == name)
            .map_or(0.0, |(_, v)| *v)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&'static str, f64)> + '_ {
        self.sums.iter().copied()
    }
}

/// An absolute plus relative tolerance for one quantity's check.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tolerance {
    pub abs: f64,
    /// Fraction of the current total (float rounding scales with size).
    pub rel: f64,
}

impl Tolerance {
    #[must_use]
    pub fn at(self, total: f64) -> f64 {
        self.abs + self.rel * total.abs()
    }
}

impl Default for Tolerance {
    fn default() -> Self {
        Self {
            abs: 1e-6,
            rel: 1e-6,
        }
    }
}

impl Ledger {
    /// Moves every source and sink recorded in `other` into this ledger
    /// (the driver merges each law's per-step ledger after a frame).
    pub fn absorb(&mut self, other: &mut Self) {
        for (name, e) in &mut other.entries {
            let mine = self.entries.entry(name).or_default();
            mine.sources += e.sources;
            mine.sinks += e.sinks;
            e.sources = 0.0;
            e.sinks = 0.0;
        }
    }

    /// Checks every `(quantity, tolerance)` in `declared` against `totals`,
    /// returning each violation.
    pub fn check_all(
        &mut self,
        totals: &Totals,
        declared: &[(&'static str, Tolerance)],
    ) -> Vec<Violation> {
        declared
            .iter()
            .filter_map(|&(name, tol)| {
                let total = totals.get(name);
                self.check(name, total, tol.at(total)).err()
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_check_only_primes_the_baseline() {
        let mut ledger = Ledger::new();
        assert!(ledger.check("moles", 100.0, 1e-6).is_ok());
    }

    #[test]
    fn an_unexplained_change_is_a_violation() {
        let mut ledger = Ledger::new();
        ledger.check("moles", 100.0, 1e-6).unwrap();
        let violation = ledger.check("moles", 150.0, 1e-6).unwrap_err();
        assert_eq!(violation.name, "moles");
        assert!((violation.delta - 50.0).abs() < 1e-9);
        assert!((violation.expected - 0.0).abs() < 1e-9);
    }

    #[test]
    fn a_recorded_source_explains_an_increase() {
        let mut ledger = Ledger::new();
        ledger.check("moles", 100.0, 1e-6).unwrap();
        ledger.source("moles", 50.0);
        assert!(ledger.check("moles", 150.0, 1e-6).is_ok());
    }

    #[test]
    fn a_recorded_sink_explains_a_decrease() {
        let mut ledger = Ledger::new();
        ledger.check("energy", 1000.0, 1e-6).unwrap();
        ledger.sink("energy", 200.0);
        assert!(ledger.check("energy", 800.0, 1e-6).is_ok());
    }

    #[test]
    fn sources_and_sinks_reset_each_check() {
        let mut ledger = Ledger::new();
        ledger.check("moles", 0.0, 1e-6).unwrap();
        ledger.source("moles", 10.0);
        ledger.check("moles", 10.0, 1e-6).unwrap();
        // No new source/sink recorded this step: an unexplained move fails.
        assert!(ledger.check("moles", 20.0, 1e-6).is_err());
    }

    #[test]
    fn quantities_are_independent() {
        let mut ledger = Ledger::new();
        ledger.check("moles", 100.0, 1e-6).unwrap();
        ledger.check("energy", 5000.0, 1e-6).unwrap();
        ledger.source("moles", 1.0);
        assert!(ledger.check("moles", 101.0, 1e-6).is_ok());
        // energy had no source recorded, and didn't move: still fine.
        assert!(ledger.check("energy", 5000.0, 1e-6).is_ok());
    }

    #[test]
    fn tolerance_absorbs_float_rounding() {
        let mut ledger = Ledger::new();
        ledger.check("moles", 100.0, 1e-3).unwrap();
        assert!(ledger.check("moles", 100.0 + 1e-6, 1e-3).is_ok());
    }

    #[test]
    #[should_panic(expected = "conservation violated")]
    fn assert_conserved_panics_on_violation() {
        let mut ledger = Ledger::new();
        ledger.check("moles", 0.0, 1e-6).unwrap();
        assert_conserved(&mut ledger, "moles", 5.0, 1e-6);
    }

    struct FixedSource(&'static str, f64);
    impl Conserved for FixedSource {
        fn totals(&self, visit: &mut dyn FnMut(&'static str, f64)) {
            visit(self.0, self.1);
        }
    }

    #[test]
    fn totals_sum_across_sources_and_check_all_reports_leaks() {
        let mut totals = Totals::new();
        totals.add_source(&FixedSource("moles", 10.0));
        totals.add_source(&FixedSource("energy", 1000.0));
        totals.add_source(&FixedSource("moles", 5.0));
        assert_eq!(totals.get("moles"), 15.0);
        assert_eq!(totals.get("energy"), 1000.0);

        let declared = [("moles", Tolerance::default())];
        let mut ledger = Ledger::new();
        assert!(
            ledger.check_all(&totals, &declared).is_empty(),
            "priming never fails"
        );
        totals.clear();
        totals.add_source(&FixedSource("moles", 20.0));
        let v = ledger.check_all(&totals, &declared);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].name, "moles");
    }

    #[test]
    fn absorb_moves_sources_and_sinks() {
        let mut a = Ledger::new();
        a.check("q", 0.0, 1e-9).unwrap();
        let mut b = Ledger::new();
        b.source("q", 3.0);
        b.sink("q", 1.0);
        a.absorb(&mut b);
        assert!(a.check("q", 2.0, 1e-9).is_ok());
    }
}
