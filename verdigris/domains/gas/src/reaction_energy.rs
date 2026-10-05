//! Gas reaction energy (`doc/rewrite/temperature.md` §5): what a reaction
//! releases (or absorbs), and the temperature the mixture ends at.
//!
//! DM's reaction procs decide a reaction's rate and stoichiometry (how many
//! moles of which gas change: its *extent* and its deltas). Everything about
//! heat is here: each reaction's enthalpy per unit of extent, and
//! [`react`], which applies the deltas and settles the mixture's energy in
//! one step — the thermal energy it had (`T · C_old`) plus what the reaction
//! released, over its new heat capacity. The FFI layer books the release as
//! a reaction source in the heat ledger. The constants are the single source
//! of truth: DM reads them from the generated bindings.

use crate::gas::constants::{MINIMUM_HEAT_CAPACITY, TCMB};
use crate::gas::{GasIDX, Mixture};

// --- Enthalpies, J per unit of extent (positive: released) -------------------

/// Plasma combustion, per mole of plasma burned.
/// @dm-define FIRE_PLASMA_ENERGY_RELEASED
pub const FIRE_PLASMA_ENERGY_RELEASED: f64 = 3_000_000.0;
/// Carbon combustion (fire spreading on objects), per mole.
/// @dm-define FIRE_CARBON_ENERGY_RELEASED
pub const FIRE_CARBON_ENERGY_RELEASED: f64 = 100_000.0;
/// Hydrogen combustion, per mole of hydrogen burned.
/// @dm-define FIRE_HYDROGEN_ENERGY_RELEASED
pub const FIRE_HYDROGEN_ENERGY_RELEASED: f64 = 2_800_000.0;
/// Tritium combustion, per mole of tritium burned (tritium burns as hydrogen).
/// @dm-define FIRE_TRITIUM_ENERGY_RELEASED
pub const FIRE_TRITIUM_ENERGY_RELEASED: f64 = 2_800_000.0;
/// Freon combustion absorbs this per mole of freon burned.
/// @dm-define FIRE_FREON_ENERGY_CONSUMED
pub const FIRE_FREON_ENERGY_CONSUMED: f64 = 300_000.0;
/// Dry heat sterilization: the temperature rise per mole of miasma cleaned, K.
/// @dm-define MIASTER_STERILIZATION_ENERGY
pub const MIASTER_STERILIZATION_ENERGY: f64 = 0.002;
/// Nitrous oxide formation, per mole formed.
/// @dm-define N2O_FORMATION_ENERGY
pub const N2O_FORMATION_ENERGY: f64 = 10_000.0;
/// Nitrous oxide decomposition, per mole decomposed.
/// @dm-define N2O_DECOMPOSITION_ENERGY
pub const N2O_DECOMPOSITION_ENERGY: f64 = 200_000.0;
/// BZ formation, per mole of BZ made.
/// @dm-define BZ_FORMATION_ENERGY
pub const BZ_FORMATION_ENERGY: f64 = 80_000.0;
/// Pluoxium formation, per mole formed.
/// @dm-define PLUOXIUM_FORMATION_ENERGY
pub const PLUOXIUM_FORMATION_ENERGY: f64 = 250.0;
/// Nitrium formation absorbs this per unit of reaction.
/// @dm-define NITRIUM_FORMATION_ENERGY
pub const NITRIUM_FORMATION_ENERGY: f64 = 100_000.0;
/// Nitrium decomposition, per unit of reaction.
/// @dm-define NITRIUM_DECOMPOSITION_ENERGY
pub const NITRIUM_DECOMPOSITION_ENERGY: f64 = 30_000.0;
/// Freon formation (a scale; its energy follows the temperature, [`freon_formation_absorbed`]).
/// @dm-define FREON_FORMATION_ENERGY
pub const FREON_FORMATION_ENERGY: f64 = 100.0;
/// Hyper-noblium formation, per mole formed (divided by the BZ present).
/// @dm-define NOBLIUM_FORMATION_ENERGY
pub const NOBLIUM_FORMATION_ENERGY: f64 = 20_000_000.0;
/// Halon formation, per mole.
/// @dm-define HALON_FORMATION_ENERGY
pub const HALON_FORMATION_ENERGY: f64 = 91_232.1;
/// Halon's oxygen removal absorbs this per unit of reaction.
/// @dm-define HALON_COMBUSTION_ENERGY
pub const HALON_COMBUSTION_ENERGY: f64 = 2_500.0;
/// Healium formation, per unit of reaction.
/// @dm-define HEALIUM_FORMATION_ENERGY
pub const HEALIUM_FORMATION_ENERGY: f64 = 9_000.0;
/// Zauker formation absorbs this per unit of reaction.
/// @dm-define ZAUKER_FORMATION_ENERGY
pub const ZAUKER_FORMATION_ENERGY: f64 = 5_000.0;
/// Zauker decomposition, per mole decomposed.
/// @dm-define ZAUKER_DECOMPOSITION_ENERGY
pub const ZAUKER_DECOMPOSITION_ENERGY: f64 = 460.0;
/// Proto-nitrate formation, per unit of reaction.
/// @dm-define PN_FORMATION_ENERGY
pub const PN_FORMATION_ENERGY: f64 = 650.0;
/// Proto-nitrate's hydrogen response absorbs this per mole converted.
/// @dm-define PN_HYDROGEN_CONVERSION_ENERGY
pub const PN_HYDROGEN_CONVERSION_ENERGY: f64 = 2_500.0;
/// Proto-nitrate's tritium response, per mole converted.
/// @dm-define PN_TRITIUM_CONVERSION_ENERGY
pub const PN_TRITIUM_CONVERSION_ENERGY: f64 = 10_000.0;
/// Proto-nitrate's BZ response, per mole consumed.
/// @dm-define PN_BZASE_ENERGY
pub const PN_BZASE_ENERGY: f64 = 60_000.0;

// --- Reaction kinds (DM passes one) ---------------------------------------------

/// No enthalpy: the moles change and the mixture keeps its thermal energy over its new heat capacity.
/// @dm-define GAS_REACTION_KEEP_TEMPERATURE
pub const KEEP_TEMPERATURE: i32 = 0;
/// @dm-define GAS_REACTION_PLASMA_FIRE
pub const PLASMA_FIRE: i32 = 1;
/// @dm-define GAS_REACTION_HYDROGEN_FIRE
pub const HYDROGEN_FIRE: i32 = 2;
/// @dm-define GAS_REACTION_TRITIUM_FIRE
pub const TRITIUM_FIRE: i32 = 3;
/// @dm-define GAS_REACTION_FREON_FIRE
pub const FREON_FIRE: i32 = 4;
/// @dm-define GAS_REACTION_STERILIZATION
pub const STERILIZATION: i32 = 5;
/// @dm-define GAS_REACTION_N2O_FORMATION
pub const N2O_FORMATION: i32 = 6;
/// @dm-define GAS_REACTION_N2O_DECOMPOSITION
pub const N2O_DECOMPOSITION: i32 = 7;
/// Extent: BZ formed; `aux`: the fraction of nitrous oxide that decomposed instead.
/// @dm-define GAS_REACTION_BZ_FORMATION
pub const BZ_FORMATION: i32 = 8;
/// @dm-define GAS_REACTION_PLUOXIUM_FORMATION
pub const PLUOXIUM_FORMATION: i32 = 9;
/// @dm-define GAS_REACTION_NITRIUM_FORMATION
pub const NITRIUM_FORMATION: i32 = 10;
/// @dm-define GAS_REACTION_NITRIUM_DECOMPOSITION
pub const NITRIUM_DECOMPOSITION: i32 = 11;
/// Extent: freon formed (the energy absorbed follows the temperature).
/// @dm-define GAS_REACTION_FREON_FORMATION
pub const FREON_FORMATION: i32 = 12;
/// Extent: noblium formed; `aux`: the BZ present.
/// @dm-define GAS_REACTION_NOBLIUM_FORMATION
pub const NOBLIUM_FORMATION: i32 = 13;
/// @dm-define GAS_REACTION_HALON_COMBUSTION
pub const HALON_COMBUSTION: i32 = 14;
/// @dm-define GAS_REACTION_HEALIUM_FORMATION
pub const HEALIUM_FORMATION: i32 = 15;
/// @dm-define GAS_REACTION_ZAUKER_FORMATION
pub const ZAUKER_FORMATION: i32 = 16;
/// @dm-define GAS_REACTION_ZAUKER_DECOMPOSITION
pub const ZAUKER_DECOMPOSITION: i32 = 17;
/// @dm-define GAS_REACTION_PN_FORMATION
pub const PN_FORMATION: i32 = 18;
/// @dm-define GAS_REACTION_PN_HYDROGEN_RESPONSE
pub const PN_HYDROGEN_RESPONSE: i32 = 19;
/// @dm-define GAS_REACTION_PN_TRITIUM_RESPONSE
pub const PN_TRITIUM_RESPONSE: i32 = 20;
/// @dm-define GAS_REACTION_PN_BZ_RESPONSE
pub const PN_BZ_RESPONSE: i32 = 21;

/// What freon formation absorbs per mole of freon at `t` K: a logistic in
/// temperature, a tenth of `1000..8000` J.
#[must_use]
pub fn freon_formation_absorbed(t: f64) -> f64 {
    (7000.0 / (1.0 + (-0.0015 * (t - 6000.0)).exp()) + 1000.0) * 0.1
}

/// The energy a reaction of `kind` releases (negative: absorbs), J, for its
/// `extent` at temperature `t` K, with the reaction's `aux` value and the
/// mixture's heat capacity after it (`c_new`, for a temperature-rise kind).
/// `None` for an unknown kind.
#[must_use]
pub fn released(kind: i32, extent: f64, t: f64, aux: f64, c_new: f64) -> Option<f64> {
    Some(match kind {
        KEEP_TEMPERATURE => 0.0,
        PLASMA_FIRE => FIRE_PLASMA_ENERGY_RELEASED * extent,
        HYDROGEN_FIRE => FIRE_HYDROGEN_ENERGY_RELEASED * extent,
        TRITIUM_FIRE => FIRE_TRITIUM_ENERGY_RELEASED * extent,
        FREON_FIRE => -FIRE_FREON_ENERGY_CONSUMED * extent,
        // A temperature rise per mole cleaned: the energy that takes at the new capacity.
        STERILIZATION => MIASTER_STERILIZATION_ENERGY * extent * c_new,
        N2O_FORMATION => N2O_FORMATION_ENERGY * extent,
        N2O_DECOMPOSITION => N2O_DECOMPOSITION_ENERGY * extent,
        BZ_FORMATION => extent * (BZ_FORMATION_ENERGY + aux * (N2O_DECOMPOSITION_ENERGY - BZ_FORMATION_ENERGY)),
        PLUOXIUM_FORMATION => PLUOXIUM_FORMATION_ENERGY * extent,
        NITRIUM_FORMATION => -NITRIUM_FORMATION_ENERGY * extent,
        NITRIUM_DECOMPOSITION => NITRIUM_DECOMPOSITION_ENERGY * extent,
        FREON_FORMATION => -freon_formation_absorbed(t) * extent,
        NOBLIUM_FORMATION => NOBLIUM_FORMATION_ENERGY * extent / aux.max(1.0),
        HALON_COMBUSTION => -HALON_COMBUSTION_ENERGY * extent,
        HEALIUM_FORMATION => HEALIUM_FORMATION_ENERGY * extent,
        ZAUKER_FORMATION => -ZAUKER_FORMATION_ENERGY * extent,
        ZAUKER_DECOMPOSITION => ZAUKER_DECOMPOSITION_ENERGY * extent,
        PN_FORMATION => PN_FORMATION_ENERGY * extent,
        PN_HYDROGEN_RESPONSE => -PN_HYDROGEN_CONVERSION_ENERGY * extent,
        PN_TRITIUM_RESPONSE => PN_TRITIUM_CONVERSION_ENERGY * extent,
        PN_BZ_RESPONSE => PN_BZASE_ENERGY * extent,
        _ => return None,
    })
}

/// What [`react`] did: the energy the reaction released (J, negative:
/// absorbed) and the energy the mixture's thermal energy changed by.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Reacted {
    pub released: f64,
    pub applied: f64,
}

/// Applies a reaction to `mix`: `deltas` (gas, moles; a gas never goes below
/// zero), then the energy — the thermal energy it had at its old heat capacity
/// plus what the reaction released, over its new capacity, never below TCMB.
/// A mixture left with almost no heat capacity keeps its temperature. `None`
/// for an unknown kind (nothing is applied).
pub fn react(mix: &mut Mixture, kind: i32, extent: f64, aux: f64, deltas: &[(GasIDX, f32)]) -> Option<Reacted> {
    let t = f64::from(mix.get_temperature());
    released(kind, extent, t, aux, 0.0)?; // a known kind, before anything changes
    let c_old = f64::from(mix.heat_capacity());
    let before = t * c_old;
    // A gas named twice adds up, as two adjust_moles() calls did.
    for &(g, d) in deltas {
        mix.set_moles(g, (mix.get_moles(g) + d).max(0.0));
    }
    let c_new = f64::from(mix.heat_capacity());
    let released = released(kind, extent, t, aux, c_new)?;
    if c_new > f64::from(MINIMUM_HEAT_CAPACITY) {
        let energy = (before + released).max(c_new * f64::from(TCMB));
        #[allow(clippy::cast_possible_truncation)]
        mix.set_temperature((energy / c_new) as f32);
    }
    let after = f64::from(mix.get_temperature()) * f64::from(mix.heat_capacity());
    Some(Reacted { released, applied: after - before })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gas::ids::{GAS_CARBON_DIOXIDE as GAS_CO2, GAS_OXYGEN as GAS_O2, GAS_PLASMA, GAS_WATER_VAPOR};

    fn plasma_air(t: f32) -> Mixture {
        let mut m = Mixture::from_vol(2500.0);
        m.set_moles(GAS_PLASMA, 100.0);
        m.set_moles(GAS_O2, 100.0);
        m.set_temperature(t);
        m
    }

    #[test]
    fn a_fire_releases_its_enthalpy_into_the_mixture() {
        let mut m = plasma_air(500.0);
        let c_old = f64::from(m.heat_capacity());
        let burned = 2.0f32;
        let r = react(&mut m, PLASMA_FIRE, f64::from(burned), 0.0, &[(GAS_PLASMA, -burned), (GAS_O2, -burned), (GAS_CO2, burned * 0.75), (GAS_WATER_VAPOR, burned * 0.25)]).unwrap();
        assert!((r.released - FIRE_PLASMA_ENERGY_RELEASED * 2.0).abs() < 1e-6);
        let expected = (500.0 * c_old + r.released) / f64::from(m.heat_capacity());
        assert!((f64::from(m.get_temperature()) - expected).abs() < 0.01, "{} vs {expected}", m.get_temperature());
        assert!((r.applied - r.released).abs() / r.released < 1e-4);
    }

    #[test]
    fn an_endothermic_reaction_cools_but_never_below_tcmb() {
        let mut m = plasma_air(10.0);
        let _ = react(&mut m, FREON_FIRE, 1000.0, 0.0, &[]).unwrap();
        assert!((m.get_temperature() - TCMB).abs() < 1e-3);
    }

    #[test]
    fn an_unknown_kind_changes_nothing() {
        let mut m = plasma_air(400.0);
        assert!(react(&mut m, 999, 1.0, 0.0, &[(GAS_PLASMA, -1.0)]).is_none());
        assert!((m.get_moles(GAS_PLASMA) - 100.0).abs() < 1e-6);
    }
}
