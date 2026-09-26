// R_IDEAL_GAS_EQUATION/TCMB/T0C/T20C moved to vg_core::units::consts
// (`rust_architecture.md` §4.11: this crate used to keep its own copy,
// exactly matching heat's, with nothing enforcing that it stayed so).
// Re-exported so every existing unqualified reference in this crate keeps
// working.
pub use vg_core::units::consts::{R_IDEAL_GAS_EQUATION, T0C, T20C, TCMB};

/// kPa
pub const ONE_ATMOSPHERE: f32 = 101.325;
/// Amount of gas below which any amounts will be truncated to 0.
pub const GAS_MIN_MOLES: f32 = 0.0001;
/// DM's `MINIMUM_MOLES_TO_FILTER` (`code/__defines/machinery.dm`): below
/// this, a filter/mixer's power-budget calc ([`crate::power_budget`])
/// treats a gas, or a computed transfer, as not worth moving.
pub const MINIMUM_MOLES_TO_FILTER: f32 = 0.04;
/// Heat capacities below which heat will be considered 0.
pub const MINIMUM_HEAT_CAPACITY: f32 = 0.0003;

/// liters in a cell
pub const CELL_VOLUME: f32 = 2500.0;
/// moles in a 2.5 m^3 cell at 101.325 Pa and 20 degC
pub const MOLES_CELLSTANDARD: f32 = ONE_ATMOSPHERE * CELL_VOLUME / (T20C * R_IDEAL_GAS_EQUATION);

/// Minimum ratio of air that must move to/from a tile
pub const MINIMUM_AIR_RATIO_TO_MOVE: f32 = 0.001;
/// Either this must be active
pub const MINIMUM_MOLES_DELTA_TO_MOVE: f32 = MOLES_CELLSTANDARD * MINIMUM_AIR_RATIO_TO_MOVE;
/// Minimum temperature difference before group processing is suspended
pub const MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND: f32 = 4.0;

// Solid heat transfer constants live in vg-heat (domains/heat/src/consts.rs).

// GASES

/// `moles_visible` * `FACTOR_GAS_VISIBLE_MAX` = Moles after which gas is at maximum visibility
pub const FACTOR_GAS_VISIBLE_MAX: f32 = 20.0;
/// Mole step for alpha updates. This means alpha can update at 0.25, 0.5, 0.75 and so on
pub const MOLES_GAS_VISIBLE_STEP: f32 = 0.25;
