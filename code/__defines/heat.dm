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

/// Emissivity used when a type declares none.
#define THERMAL_EMISSIVITY_DEFAULT 0.9
/// Heat capacity of an atom that declares nothing better, J/K.
#define THERMAL_CAPACITY_DEFAULT 2000
/// Conductance of an atom to its surroundings when it declares nothing better, W/K.
#define THERMAL_CONDUCTANCE_DEFAULT 2
/// Heat capacity per w_class point of an item, J/K (a small steel item is about 400 J/K).
#define THERMAL_CAPACITY_PER_W_CLASS 400
/// Conductance per w_class point of an item to its surroundings, W/K.
#define THERMAL_CONDUCTANCE_PER_W_CLASS 0.5

// Wake lanes for heat watches (vg-core outbox lanes).
#define HEAT_LANE_URGENT 0
#define HEAT_LANE_NORMAL 1
#define HEAT_LANE_BACKGROUND 2
