//! One step of a chemical reaction (`/datum/decl/chemical_reaction/proc/calc_reaction_progress`).
//!
//! A reaction `aA + bB -> cC` in a holder with `n_A`, `n_B` units can proceed at most `limit = min(n_A / a, n_B / b)` "reaction units"
//! (each consumes `a` of A, `b` of B and makes `c` of C). One step goes `limit * rate * multiplier` of that, capped by the yield limit
//! (a reaction with yield `y < 1` stops when product / reactants reaches `y / (1 - y)`), and goes all the way when what it would leave
//! of any reactant is within `min_reaction` reaction units of nothing (no reaction crawls on forever over crumbs).

/// One reactant of a step: the units the holder has, and the units one reaction unit consumes.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Reactant {
    pub have: f32,
    pub ratio: f32,
}

/// The parameters of one reaction step.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Step {
    /// The stoichiometric limit, `min(have / ratio)` over the reactants.
    pub limit: f32,
    /// The fraction of `limit` one step goes (`HALF_LIFE(n)`, `REACTION_RATE(r)`; 1 completes at once).
    pub rate: f32,
    /// The holder's surface multiplier on the rate (a catalytic material; 1 when none).
    pub multiplier: f32,
    /// The yield, 0..1: 1 goes to completion.
    pub yield_: f32,
    /// Units of product one reaction unit makes.
    pub result_amount: f32,
    /// Units of the product already in the holder.
    pub product_have: f32,
    /// Reaction units below which a remainder completes the reaction.
    pub min_reaction: f32,
}

/// How far the step goes, in reaction units: DM's `calc_reaction_progress()` (the caller still takes `min(limit, progress)`).
#[must_use]
pub fn progress(step: &Step, reactants: &[Reactant]) -> f32 {
    let mut progress = step.limit * step.rate;
    // DM: `progress *= holder.my_atom?.material_reaction_rate_multiplier() || 1`: a 0 multiplier reads as 1.
    progress *= if step.multiplier == 0.0 { 1.0 } else { step.multiplier };
    if 1.0 - step.yield_ > 0.001 && step.result_amount != 0.0 {
        let yield_ratio = step.yield_ / (1.0 - step.yield_);
        let max_product = yield_ratio * step.limit * step.result_amount;
        let yield_limit = (max_product - step.product_have).max(0.0) / step.result_amount;
        progress = progress.min(yield_limit);
    }
    for r in reactants {
        let remainder = r.have - progress * r.ratio;
        if remainder <= step.min_reaction * r.ratio {
            progress = step.limit;
            break;
        }
    }
    progress
}

/// The stoichiometric limit of `reactants`: the reaction units the scarcest one allows (infinite for none).
#[must_use]
pub fn limit(reactants: &[Reactant]) -> f32 {
    reactants.iter().map(|r| r.have / r.ratio).fold(f32::INFINITY, f32::min)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn step(limit: f32) -> Step {
        Step { limit, rate: 1.0, multiplier: 1.0, yield_: 1.0, result_amount: 3.0, product_have: 0.0, min_reaction: 2.0 }
    }

    #[test]
    fn instant_reaction_goes_to_the_limit() {
        let rs = [Reactant { have: 10.0, ratio: 1.0 }, Reactant { have: 30.0, ratio: 2.0 }];
        let l = limit(&rs);
        assert_eq!(l, 10.0);
        assert_eq!(progress(&step(l), &rs), 10.0);
    }

    #[test]
    fn half_life_goes_part_way_until_the_remainder_is_small() {
        let rs = [Reactant { have: 100.0, ratio: 1.0 }];
        let s = Step { rate: 0.5, ..step(100.0) };
        assert_eq!(progress(&s, &rs), 50.0);
        // 3 left after 1.5 of 4.5: within min_reaction (2) of nothing? 4.5 - 2.25 = 2.25 > 2: no.
        let rs = [Reactant { have: 4.5, ratio: 1.0 }];
        assert_eq!(progress(&Step { rate: 0.5, ..step(4.5) }, &rs), 2.25);
        // 3.9 - 1.95 = 1.95 <= 2: completes.
        let rs = [Reactant { have: 3.9, ratio: 1.0 }];
        assert_eq!(progress(&Step { rate: 0.5, ..step(3.9) }, &rs), 3.9);
    }

    #[test]
    fn yield_limits_the_product() {
        // yield 0.5: product may reach limit * result_amount; 15 of 30 already there leaves 5 reaction units.
        let rs = [Reactant { have: 100.0, ratio: 10.0 }];
        let s = Step { yield_: 0.5, product_have: 15.0, ..step(10.0) };
        assert_eq!(progress(&s, &rs), 5.0);
        let s = Step { yield_: 0.5, product_have: 40.0, ..step(10.0) };
        assert_eq!(progress(&s, &rs), 0.0);
    }

    #[test]
    fn zero_multiplier_reads_as_one() {
        let rs = [Reactant { have: 100.0, ratio: 1.0 }];
        let s = Step { rate: 0.25, multiplier: 0.0, ..step(100.0) };
        assert_eq!(progress(&s, &rs), 25.0);
        let s = Step { rate: 0.25, multiplier: 2.0, ..step(100.0) };
        assert_eq!(progress(&s, &rs), 50.0);
    }

    proptest::proptest! {
        #[test]
        fn progress_never_exceeds_the_limit_for_complete_yield(have in 0.1f32..1e5, ratio in 0.1f32..50.0, rate in 0.0f32..=1.0) {
            let rs = [Reactant { have, ratio }];
            let l = limit(&rs);
            let p = progress(&Step { rate, ..step(l) }, &rs);
            proptest::prop_assert!(p <= l * 1.0001);
            proptest::prop_assert!(p >= 0.0);
        }
    }
}
