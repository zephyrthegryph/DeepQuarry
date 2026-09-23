//! Heat constants, SI units. These are the single source for the values DM
//! used to duplicate (B12 / H1): DM reads them through `vg_heat_constants()`.

/// W/(m²·K⁴).
pub const STEFAN_BOLTZMANN: f64 = 5.670_374_419e-8;
/// Cosmic microwave background, K. The floor of every body and gas.
pub const TCMB: f32 = 2.7;
/// 0 °C, K.
pub const T0C: f32 = 273.15;
/// 20 °C, K.
pub const T20C: f32 = 293.15;

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
pub const DEFAULT_EMISSIVITY: f32 = 0.9;

/// Heat capacity DM gives vacuum (`HEAT_CAPACITY_VACUUM`), J/K: the capacity
/// of a space or planet reservoir cell.
pub const HEAT_CAPACITY_VACUUM: f32 = 7000.0;

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
