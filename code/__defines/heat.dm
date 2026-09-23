// The heat domain (doc/rewrite/temperature.md, verdigris/domains/heat).
// HEAT_CELL_*, HEAT_TARGET_* and HEAT_WATCH_* are generated from the Rust into
// code/__defines/verdigris/_bindings.dm.

// Indices of the list thermal_properties() returns.
/// Heat capacity, J/K.
#define THERMAL_CAPACITY 1
/// Conductance to the surroundings, W/K (for a turf: its thermal_conductivity).
#define THERMAL_CONDUCTANCE 2
/// Emissivity of a surface exposed to space, 0..1.
#define THERMAL_EMISSIVITY 3

// The defaults (THERMAL_EMISSIVITY_DEFAULT, THERMAL_CAPACITY_DEFAULT,
// THERMAL_CONDUCTANCE_DEFAULT, THERMAL_CAPACITY_PER_W_CLASS,
// THERMAL_CONDUCTANCE_PER_W_CLASS) and the shared temperatures and heat
// capacities are generated from verdigris/domains/heat/src/consts.rs (H1).

// Wake lanes for heat watches (vg-core outbox lanes).
#define HEAT_LANE_URGENT 0
#define HEAT_LANE_NORMAL 1
#define HEAT_LANE_BACKGROUND 2
