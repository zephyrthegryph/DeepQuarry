//! One Life cycle of a metabolism holder (a mob's bloodstream, stomach or skin), batched over its reagents
//! (`/datum/reagents/metabolism/proc/metabolize`).
//!
//! DM works out each reagent's rate this cycle (its metabolism times the body's: species and traits, the heart's pulse, a damaged
//! stomach, a filtering liver) and whether the reagent acts at all; this takes those rates and returns, per reagent, what is taken up
//! this cycle, the dose so far, and the overdose.

/// One reagent at the start of the cycle.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Uptake {
    /// Units in the holder.
    pub volume: f32,
    /// Units the body takes up this cycle at most (the rate DM worked out).
    pub rate: f32,
    /// The dose so far.
    pub dose: f32,
    /// The largest volume the holder has had of it.
    pub max_dose: f32,
    /// The volume above which it overdoses (its `overdose` times the species' threshold); 0: it never does.
    pub overdose_at: f32,
    /// The reagent's own `overdose` (the injury scales with volume over it).
    pub overdose: f32,
    /// The overdose injury multiplier (the reagent's `overdose_mod` times the species').
    pub overdose_mod: f32,
}

/// What one cycle does to one reagent.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Taken {
    /// Units taken up (and removed from the holder) this cycle.
    pub removed: f32,
    pub dose: f32,
    pub max_dose: f32,
    /// Whether it overdoses this cycle.
    pub overdosing: bool,
    /// The base overdose injury (toxin), when it does: `min(removed * mod * floor(3 + 3 * volume / overdose), 3.6)`.
    pub overdose_injury: f32,
}

/// The base overdose cap per cycle: 18 per unit at the default rate, so no amount of a reagent kills outright.
pub const OVERDOSE_INJURY_CAP: f32 = 3.6;

/// One cycle of one reagent.
#[must_use]
pub fn take(u: &Uptake) -> Taken {
    let removed = u.rate.min(u.volume);
    let max_dose = u.volume.max(u.max_dose);
    let dose = (u.dose + removed).min(max_dose);
    let overdosing = u.overdose_at > 0.0 && u.overdose > 0.0 && u.volume > u.overdose_at;
    let overdose_injury = if overdosing { overdose_injury(removed, u.overdose_mod, u.volume, u.overdose) } else { 0.0 };
    Taken { removed, dose, max_dose, overdosing, overdose_injury }
}

/// The base overdose injury (toxin) of taking up `removed` units with `volume` in the holder, for a reagent that overdoses over
/// `overdose`: 6 per unit at least, more the further over, never more than [`OVERDOSE_INJURY_CAP`] a cycle.
#[must_use]
pub fn overdose_injury(removed: f32, overdose_mod: f32, volume: f32, overdose: f32) -> f32 {
    (removed * overdose_mod * (3.0 + 3.0 * volume / overdose).floor()).min(OVERDOSE_INJURY_CAP)
}

/// One cycle of a holder: [`take`] for each reagent, in order.
#[must_use]
pub fn cycle(reagents: &[Uptake]) -> Vec<Taken> {
    reagents.iter().map(take).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn u(volume: f32, rate: f32) -> Uptake {
        Uptake { volume, rate, dose: 0.0, max_dose: 0.0, overdose_at: 0.0, overdose: 0.0, overdose_mod: 1.0 }
    }

    #[test]
    fn takes_the_rate_or_what_is_left() {
        assert_eq!(take(&u(10.0, 0.2)).removed, 0.2);
        assert_eq!(take(&u(0.1, 0.2)).removed, 0.1);
    }

    #[test]
    fn dose_accumulates_up_to_the_largest_volume_seen() {
        let t = take(&Uptake { dose: 4.9, max_dose: 5.0, ..u(3.0, 0.2) });
        assert_eq!(t.max_dose, 5.0);
        assert_eq!(t.dose, 5.0);
        let t = take(&Uptake { dose: 1.0, ..u(8.0, 0.5) });
        assert_eq!(t.max_dose, 8.0);
        assert_eq!(t.dose, 1.5);
    }

    #[test]
    fn overdose_scales_with_volume_and_is_capped() {
        // tramadol-like: overdose 30, 40 in the blood: floor(3 + 4) = 7; 0.2 * 7 = 1.4.
        let t = take(&Uptake { overdose_at: 30.0, overdose: 30.0, ..u(40.0, 0.2) });
        assert!(t.overdosing);
        assert!((t.overdose_injury - 1.4).abs() < 1e-6);
        let t = take(&Uptake { overdose_at: 30.0, overdose: 30.0, ..u(400.0, 0.2) });
        assert_eq!(t.overdose_injury, OVERDOSE_INJURY_CAP);
        let t = take(&Uptake { overdose_at: 30.0, overdose: 30.0, ..u(30.0, 0.2) });
        assert!(!t.overdosing, "at the threshold is not over it");
    }
}
