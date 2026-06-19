// Defines shared between SSquarry's implementation and the quarry unit
// tests. Hoisted into its own file so it's included BEFORE
// code/modules/unit_tests/_unit_tests.dm in the DME — the test file
// references QUARRY_LAYER_SIZE while parsing the test scope, which
// happens long before quarry_controller.dm gets included.

#ifndef QUARRY_LAYER_SIZE
#define QUARRY_LAYER_SIZE 256
#endif

// Rolling frontier ("the bore drifts"). The next-deeper stratum isn't
// fixed until a player commits to it: while the deepest unlocked depth
// is un-generated, SSquarry re-rolls its candidate feature/goal set
// every QUARRY_FRONTIER_ROLL_INTERVAL until someone locks it in (at the
// surface panel) or descends to it. See quarry_controller.dm
// (tick_frontier_roll / begin_frontier_roll / frontier_candidate_depth).
#define QUARRY_FRONTIER_ROLL_INTERVAL (2 MINUTES)

// Raw-chemistry mineral names. These index GLOB.ore_data the same way
// the upstream ORE_HEMATITE / ORE_PHORON defines do, and have to be
// available at parse time wherever a quarry feature lists them in
// ore_contributions.
#define ORE_RAWCHEM_SALTPETER "raw_saltpeter"
#define ORE_RAWCHEM_LITHIUM "raw_lithium"
#define ORE_RAWCHEM_COPPER_SULFATE "raw_copper_sulfate"
#define ORE_RAWCHEM_PHORON_GAS "raw_phoron_gas"

// Danger system thresholds + accrual rates. Hoisted here so the
// event-hook procs in quarry_goal_hooks.dm (which gets included
// before quarry_danger.dm) can reference them at parse time.
#define QUARRY_DANGER_QUIET     30
#define QUARRY_DANGER_RESTLESS  60
#define QUARRY_DANGER_DANGEROUS 85

#define QUARRY_DANGER_PASSIVE_BASE 1.0
#define QUARRY_DANGER_PASSIVE_PER_DEPTH 0.1

#define QUARRY_DANGER_PER_WALL_MINED 0.5
#define QUARRY_DANGER_PER_PUMP_TICK 0.15
#define QUARRY_DANGER_PER_GAS_VENT 3
#define QUARRY_DANGER_PER_MOB_KILL 0.3

#define QUARRY_DANGER_DECAY 1.0

// Per-tick hazard/danger magnitudes above are authored for the CURRENT
// SSquarry wait of 30 SECONDS. BYOND subsystem `wait` is in deciseconds
// (30 SECONDS == 300 ds), and callers pass `seconds = wait/10 == 30`. To
// decouple the magnitudes from the scheduler without rebalancing, callers
// multiply by the tick's `seconds` and divide by this normalization constant
// — so at the 30s wait the factor is exactly 1 (present-day balance preserved)
// and any other wait scales proportionally. If the wait define changes, update this too.
#define QUARRY_TICK_NORMALIZE_SECONDS 30

// Noise system loudness presets. Used at the call site to keep the
// per-source values consistent. Each value is both the alert radius
// (tiles) and the input to the danger bump (divided by a divisor in
// quarry_noise.dm).
#define QUARRY_NOISE_PICK 4
#define QUARRY_NOISE_PUMP 5
#define QUARRY_NOISE_VENT 8
#define QUARRY_NOISE_MOBDEATH 6
#define QUARRY_NOISE_WEAPON_MELEE 5
#define QUARRY_NOISE_WEAPON_LASER 7
#define QUARRY_NOISE_WEAPON_BALLISTIC 14
#define QUARRY_NOISE_CAVEIN 20
#define QUARRY_NOISE_EXPLOSION 25
