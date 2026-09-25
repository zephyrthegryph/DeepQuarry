// Mob Life on object-model pipelines (doc/rewrite/life_on_om.md). Life is three pipelines
// (code/modules/mob/living/life/life_om.dm) of /datum/om/stage/life flyweights; these defines are
// its vocabulary. The machinery (idle bits, parking, facts, rewakes) is the core's
// (code/datums/om/pipeline.dm).

// --- Order: the coarse position of a stage in one frame ------------------------------------
// A stage's `order` is one of these plus its position inside the phase. The phases keep the old
// Life() sequence; LIFE_PHASE_TAIL holds the code subtypes ran after ..() (human, alien, simple
// mob and bot tails, and the per-type pre/post chains).
#define LIFE_PHASE_INPUT 1000
#define LIFE_PHASE_BODY 2000
#define LIFE_PHASE_MIND 3000
#define LIFE_PHASE_OUTPUT 4000
#define LIFE_PHASE_TAIL 5000

// --- Wakes (doc/rewrite/life_on_om.md §5) ----------------------------------------------------
/// Channels that wake every Life stage: set_stat, Login and Logout, explicit wakes (the old
/// "wake all"). Stages list only the channels specific to them in `wake_on`.
#define LIFE_WAKE_ALL (CHANGE_MOB_STAT | CHANGE_MOB_CLIENT | CHANGE_EXPLICIT)

// --- run_if: the old early returns and `if` blocks, as frame facts --------------------------
/// The /mob/living core after `if(transforming) return` and `if(!loc) return`.
#define LIFE_RUN_IF_PLACED FACT("placed")
/// ... inside `if(stat != DEAD)`.
#define LIFE_RUN_IF_PLACED_ALIVE ALL_OF(FACT("placed"), FACT("alive"))
/// ... inside `if(handle_regular_status_updates())` (the status stage's result).
#define LIFE_RUN_IF_STATUS_OK ALL_OF(FACT("placed"), FACT("status_ok"))
/// The human tail inside `if(!stasis) if(stat != DEAD)` and `... else if(stat == DEAD)`.
#define LIFE_RUN_IF_LIVE_BIOLOGY ALL_OF(NOT_OF(FACT("in_stasis")), FACT("alive"))
#define LIFE_RUN_IF_DEAD_BIOLOGY ALL_OF(NOT_OF(FACT("in_stasis")), NOT_OF(FACT("alive")))

// --- Life sets (/mob/living/var/life_set) ---------------------------------------------------
// Which family of Life sequences a mob runs. The legacy silicon Life() procs never called
// the /mob/living parent, so they compose from their own families.
#define LIFE_SET_LIVING (1<<0)
#define LIFE_SET_ROBOT (1<<1)
#define LIFE_SET_AI (1<<2)
#define LIFE_SET_PAI (1<<3)
#define LIFE_SET_DECOY (1<<4)
/// Mobs whose Life() only removes them from the mob lists (dummies, announcers).
#define LIFE_SET_DELIST (1<<5)

// --- Cadence (doc/rewrite/life_on_om.md §3) -----------------------------------------------------
// One Life frame per LIFE_CYCLE of real time. Almost all life content is written per frame (a stun
// unit, a hunger tick, one organ pass), so this sets its per-second balance. 6 s is what the old
// SSmobs actually delivered at a normal population (its per-fire quota shrank as its run list
// drained); see the doc before changing it. Tests and benchmarks may compile another value.
#ifndef LIFE_CYCLE_DS
#define LIFE_CYCLE_DS 60
#endif
/// Real time per Life frame, deciseconds.
#define LIFE_CYCLE (LIFE_CYCLE_DS)
/// Real time per Life frame, seconds (what a frame's dt-scaled content integrates).
#define LIFE_CYCLE_SECONDS (LIFE_CYCLE_DS / 10)
/// At most this many frames in one tick when the scheduler is late; the rest are dropped.
#define LIFE_MAX_CATCHUP 2
/// Frames in a row that must end with every stage idle before a mob parks.
#define LIFE_PARK_AFTER 2
/// The presentation pipeline (HUD, vision) runs at most this often; changes in between coalesce.
#define LIFE_PRESENT_MIN_INTERVAL (0.5 SECONDS)
/// Observer upkeep (ghosts, AI eyes, blob overmind) runs this often.
#define OBSERVER_UPKEEP_INTERVAL (LIFE_CYCLE)
/// Every Nth pipeline frame is timed per stage and mob type (SSmobs' two-minute profile).
#ifndef OM_NO_STAGE_PROFILE
#define LIFE_PROFILE_STRIDE 16
#else
#define LIFE_PROFILE_STRIDE 0
#endif
