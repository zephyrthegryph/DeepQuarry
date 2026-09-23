//! Heat constants, SI units. These are the single source for the values DM
//! used to duplicate (B12 / H1). Each `@dm-define` becomes a DM `#define` in
//! the generated bindings (`code/__defines/verdigris/_bindings.dm`); DM must
//! not redefine them (tools/ci/check_grep.sh). `vg_heat_constants()` returns
//! the same values at runtime so the tests can check the two agree.
//!
//! `STEFAN_BOLTZMANN`/`TCMB`/`T0C`/`T20C` moved to
//! `vg_core::units::consts` (`rust_architecture.md` §4.11: shared with gas,
//! which used to keep its own exactly-matching copy of `TCMB`/`T0C`/`T20C`
//! with nothing enforcing that it stayed exact) and are re-exported here so
//! every existing `heat::consts::TCMB`-style reference in this crate and its
//! FFI binds keeps working unchanged.

pub use vg_core::units::consts::{STEFAN_BOLTZMANN, T0C, T20C, TCMB};

/// The effective radiative sink temperature of space, K.
///
/// A face exposed to space radiates `ε σ A (T⁴ − T_sky⁴)`: the station's
/// hull absorbs starlight and the local star as well as emitting, and the
/// net balance of an insolated hull sits near room temperature. With the
/// sink at 20 °C a room-temperature hull neither gains nor loses heat
/// (today's behaviour: superconduct.rs only lost heat to space above 20 °C),
/// hotter faces cool by radiation, and colder ones warm slowly.
pub const SPACE_SKY_TEMPERATURE: f32 = T20C;
/// Radiating area of one exposed cell face, m² (turf tiles are 1 m², as the
/// old superconduction code assumed).
pub const RADIATING_AREA: f32 = 1.0;
/// Emissivity used when DM declares none.
/// @dm-define THERMAL_EMISSIVITY_DEFAULT
pub const DEFAULT_EMISSIVITY: f32 = 0.9;

/// Heat capacity DM gives vacuum (`HEAT_CAPACITY_VACUUM`), J/K: the capacity
/// of a space or planet reservoir cell.
/// @dm-define HEAT_CAPACITY_VACUUM
pub const HEAT_CAPACITY_VACUUM: f32 = 7000.0;

/// Normal human core body temperature, 37 °C in K. The one body temperature:
/// species, mobs, reagents and machines all read this define.
/// @dm-define BODYTEMP_NORMAL
pub const BODYTEMP_NORMAL: f32 = 310.15;
/// Heat capacity of an 80 kg human body, J/K (about 3.5 kJ/(kg·K)).
/// @dm-define HUMAN_HEAT_CAPACITY
pub const HUMAN_HEAT_CAPACITY: f32 = 280_000.0;
/// Lowest temperature a fire exists at, and phoron's ignition point, K
/// (100 °C). The gas crate's `FIRE_MINIMUM_TEMPERATURE_TO_EXIST` and
/// `PLASMA_MINIMUM_BURN_TEMPERATURE` must equal it (tested there).
/// @dm-define FIRE_MINIMUM_TEMPERATURE_TO_EXIST
pub const IGNITION_TEMPERATURE: f32 = 373.15;

/// Default heat capacity of an atom that declares no thermal properties, J/K.
/// @dm-define THERMAL_CAPACITY_DEFAULT
pub const THERMAL_CAPACITY_DEFAULT: f32 = 2000.0;
/// Default conductance of an atom to its surroundings, W/K.
/// @dm-define THERMAL_CONDUCTANCE_DEFAULT
pub const THERMAL_CONDUCTANCE_DEFAULT: f32 = 2.0;
/// An item's heat capacity per `w_class` step, J/K.
/// @dm-define THERMAL_CAPACITY_PER_W_CLASS
pub const THERMAL_CAPACITY_PER_W_CLASS: f32 = 400.0;
/// An item's conductance per `w_class` step, W/K.
/// @dm-define THERMAL_CONDUCTANCE_PER_W_CLASS
pub const THERMAL_CONDUCTANCE_PER_W_CLASS: f32 = 0.5;

/// A solid edge sleeps below this temperature difference, K.
pub const SOLID_SETTLED_K: f32 = 0.1;
/// Solid ↔ turf gas coupling: `OPEN_HEAT_TRANSFER_COEFFICIENT`. The pair
/// relaxes at `rate = GAS_COUPLING * conductivity` per second.
pub const GAS_COUPLING: f32 = 0.4;
/// Solid ↔ gas pairs closer than this are left alone, K
/// (`MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER`).
pub const GAS_COUPLING_MIN_K: f32 = 0.5;

/// Simulated seconds per heat frame.
pub const HEAT_DT: f32 = 1.0;
/// Most frames of backlog the host keeps when DM ticks faster than frames
/// finish (the rest is dropped: heat runs slow instead of spiralling).
pub const MAX_BACKLOG_FRAMES: f32 = 2.0;

/// A body within this of its environment is at equilibrium, K.
pub const BODY_SETTLED_K: f32 = 0.05;
/// A body whose environment has at least this many times its heat capacity
/// treats the environment as a reservoir and follows the exact relaxation
/// solution (the environment's own drift is caught by the hysteresis).
pub const RELAX_CAPACITY_RATIO: f32 = 100.0;
/// An analytic body re-anchors when its environment moves this far, K.
pub const RELAX_HYSTERESIS_K: f32 = 0.25;
/// Longest an analytic body goes without settling its energy into its
/// environment, s. Bounds how long exchanged energy is held in the model.
pub const RELAX_MAX_INTERVAL: f32 = 30.0;
/// Watched levels a body carries for crossing prediction.
pub const BODY_LEVELS: usize = 8;

/// Body slots.
pub const MAX_BODIES: u32 = 1 << 16;
/// Body handle bits for the generation (index is 16 bits; the handle is
/// `index | generation << 16`, below 2²⁴ so exact as an f32).
pub const BODY_GENERATION_BITS: u32 = 8;

/// Watch slots the host allocator hands out (`world.rs`'s own generation-
/// checked handles, mirroring `MAX_BODIES`/[`BODY_GENERATION_BITS`]).
/// `slot*2 + domain_bit` must fit the low 16 bits alongside an 8-bit
/// generation so the packed handle stays below 2²⁴ (exact as an f32).
pub const MAX_WATCHES: u32 = 1 << 15;
/// Watch handle generation bits. Was 4 (the DM-facing handle packed the
/// *sim's own* table generation as `index * 16 + generation & 15`), which
/// aliased a still-live watch's handle with an unrelated one after only 16
/// reuses of the same sim table slot -- a stale DM handle could then
/// silently act on the wrong watch. Watches now get their own host-owned
/// slot/generation allocation (like bodies), so a handle only repeats after
/// this many *host* slot reuses, each requiring an explicit `unwatch()` in
/// between.
pub const WATCH_GENERATION_BITS: u32 = 8;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derived_constants_agree() {
        // T20C/STEFAN_BOLTZMANN's own precision is pinned in
        // vg_core::units::consts, where they're now defined.
        assert!((T0C + 100.0 - IGNITION_TEMPERATURE).abs() < 1e-4);
        assert!((T0C + 37.0 - BODYTEMP_NORMAL).abs() < 1e-4);
    }
}
