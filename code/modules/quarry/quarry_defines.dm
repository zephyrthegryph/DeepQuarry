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

// Layer fauna spawns as single-species packs rather than per-tile random
// scatter: pick one type at a seed tile, then fill a contiguous cluster of
// this many with it. Same-species packmates are faction allies, so they don't
// infight and a player attack pack-aggros the rest (call_for_help).
#define QUARRY_PACK_SIZE_MIN 2
#define QUARRY_PACK_SIZE_MAX 4

// Passive eyes-only sight range for quarry fauna (default brain vision is 7). Kept
// very short so a quiet player can slip between packs — detection is led by NOISE
// (gunfire/mining → notify_noise draws them from much farther). With thousands of
// mobs per layer, anything longer means a pack is always in sight as you walk.
// See tag_fauna.
#define QUARRY_FAUNA_VISION_RANGE 2

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

// Reinforcement siege ("going loud"). Above QUARRY_REINFORCE_MIN_DANGER heat a
// layer lays siege: waves of mobs spawn just off-screen and beeline the nearest
// player, on a cadence and in sizes that tighten as heat climbs to 100. The loop
// runs on its own heat-scaled timer (not the 30s SS tick) so it feels continuous.
// Heat bleeds off once the layer goes quiet (no noise for QUARRY_QUIET_PERIOD),
// so breaking contact / going quiet ends the swarm — the core go-loud/go-quiet loop.
#define QUARRY_REINFORCE_MIN_DANGER 55              // heat at/above which the siege runs
#define QUARRY_REINFORCE_INTERVAL_SLOW (40 SECONDS) // wave spacing at MIN heat
#define QUARRY_REINFORCE_INTERVAL_FAST (8 SECONDS)  // wave spacing at 100 heat
#define QUARRY_REINFORCE_WAVE_MIN 2                 // mobs per wave at MIN heat
#define QUARRY_REINFORCE_WAVE_MAX 6                 // mobs per wave at 100 heat
#define QUARRY_REINFORCE_RING 8                     // spawn this many tiles from the player (just off-screen)
#define QUARRY_QUIET_PERIOD (25 SECONDS)            // no noise for this long => heat cools instead of rising
#define QUARRY_QUIET_DECAY 6                        // heat lost per SS tick while quiet (beats passive accrual)
#define QUARRY_HEAT_FLOOR_PER_DEPTH 4               // quiet heat settles toward depth*this (capped below the siege threshold)
#define QUARRY_HEAT_FLOOR_MAX 45                    // cap on the depth heat floor, so going quiet can always end a siege
#define QUARRY_REINFORCE_MAX_ALIVE 28               // stop spawning waves past this many reinforcement mobs alive on a layer (perf + fairness cap)

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
