// Defines shared between SSquarry's implementation and the quarry unit
// tests. Hoisted into its own file so it's included BEFORE
// code/modules/unit_tests/_unit_tests.dm in the DME — the test file
// references QUARRY_LAYER_SIZE while parsing the test scope, which
// happens long before quarry_controller.dm gets included.

#ifndef QUARRY_LAYER_SIZE
#define QUARRY_LAYER_SIZE 256
#endif

// Percent of per-goal completion required for a layer to count as
// "stabilised". Stabilising a layer unlocks the next-deeper depth on
// the elevator. Referenced from quarry_controller.dm / elevator_panel,
// which sort before quarry_goal.dm where the goal datum itself lives.
#define QUARRY_STABILITY_THRESHOLD 80

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
