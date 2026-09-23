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
#[derive(Default)]
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
    pub fn check(&mut self, name: &'static str, total: f64, tolerance: f64) -> Result<(), Violation> {
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

/// Implemented by a field kind, a network payload or a conserved component
/// column: the driver's per-frame auto-wiring (`rust_architecture.md` §4.9)
/// sums every declared quantity across every registered source and checks
/// it through a [`Ledger`], instead of each domain writing its own
/// `HeatLedger`/`Totals`/`Books`-style summing code.
///
/// Object-safe by design (`(name, value)` pairs, not a fixed-width `out`
/// slice keyed by a separate `QUANTITIES` const) so a driver can hold a
/// `Vec<Box<dyn Conserved>>` of heterogeneous sources.
pub trait Conserved {
    /// This source's contribution to each conserved quantity it
    /// participates in, as `(name, value)`. A source that doesn't touch a
    /// quantity simply omits it, rather than contributing `0.0` -- the two
    /// are equivalent for summing, but omitting avoids every source having
    /// to know every quantity's name.
    fn contributions(&self) -> Vec<(&'static str, f64)>;
}

/// The driver's registry of [`Conserved`] sources for one frame's check:
/// collect every source, sum per quantity name, and check each sum through
/// a [`Ledger`] (§4.9). Cross-domain transfers are a sink in one domain's
/// source and a matching source in the other's, both recorded by the
/// coupling law through [`crate::law::LawCtx::ledger`] -- this set only
/// sums *totals*, it doesn't itself know about transfers.
#[derive(Default)]
pub struct ConservationSet {
    sources: Vec<Box<dyn Conserved>>,
}

impl ConservationSet {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Registers a source. Order doesn't matter: contributions are summed
    /// per quantity name regardless of registration order.
    pub fn register(&mut self, source: Box<dyn Conserved>) {
        self.sources.push(source);
    }

    /// Sums every registered source's contributions per quantity name.
    #[must_use]
    pub fn totals(&self) -> std::collections::BTreeMap<&'static str, f64> {
        let mut totals = std::collections::BTreeMap::new();
        for source in &self.sources {
            for (name, value) in source.contributions() {
                *totals.entry(name).or_insert(0.0) += value;
            }
        }
        totals
    }

    /// Sums every registered source and checks each quantity's total
    /// through `ledger`, within `tolerance` for every quantity (a per-
    /// quantity tolerance can be layered on top by calling
    /// [`Ledger::check`] directly for quantities that need a different
    /// one). Returns every violation found this frame, not just the first,
    /// so a driver can report or panic on all of them at once.
    pub fn check(&self, ledger: &mut Ledger, tolerance: f64) -> Vec<Violation> {
        self.totals()
            .into_iter()
            .filter_map(|(name, total)| ledger.check(name, total, tolerance).err())
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

    struct FixedSource(Vec<(&'static str, f64)>);
    impl Conserved for FixedSource {
        fn contributions(&self) -> Vec<(&'static str, f64)> {
            self.0.clone()
        }
    }

    #[test]
    fn conservation_set_sums_across_sources() {
        let mut set = ConservationSet::new();
        set.register(Box::new(FixedSource(vec![("moles", 10.0), ("energy", 1000.0)])));
        set.register(Box::new(FixedSource(vec![("moles", 5.0)])));
        let totals = set.totals();
        assert_eq!(totals[&"moles"], 15.0);
        assert_eq!(totals[&"energy"], 1000.0);
    }

    #[test]
    fn conservation_set_check_catches_a_leak() {
        let mut set = ConservationSet::new();
        set.register(Box::new(FixedSource(vec![("moles", 100.0)])));
        let mut ledger = Ledger::new();
        assert!(set.check(&mut ledger, 1e-6).is_empty(), "priming never fails");
        // Same total: fine.
        assert!(set.check(&mut ledger, 1e-6).is_empty());
    }

    #[test]
    fn conservation_set_check_reports_a_violation() {
        let mut set = ConservationSet::new();
        set.register(Box::new(FixedSource(vec![("moles", 100.0)])));
        let mut ledger = Ledger::new();
        assert!(set.check(&mut ledger, 1e-6).is_empty(), "priming never fails");
        set.sources[0] = Box::new(FixedSource(vec![("moles", 150.0)]));
        let violations = set.check(&mut ledger, 1e-6);
        assert_eq!(violations.len(), 1);
        assert_eq!(violations[0].name, "moles");
    }
}
