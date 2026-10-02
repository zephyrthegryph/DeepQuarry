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

// --- Anchors: the same bands on the Life sequence (/datum/sequence/life, doc/rewrite/life_sequences.md) ---
// Named no-op steps. A step says which band it runs in with `after = LIFE_BODY`; an anchor is passed only
// when no step is ready, so everything in a band runs before the next band begins.
#define LIFE_INPUT "LIFE_INPUT"
#define LIFE_BODY "LIFE_BODY"
#define LIFE_MIND "LIFE_MIND"
#define LIFE_OUTPUT "LIFE_OUTPUT"
#define LIFE_TAIL "LIFE_TAIL"

// --- Wakes (doc/rewrite/life_on_om.md §5) ----------------------------------------------------
/// Channels that wake every Life stage: set_stat, Login and Logout, explicit wakes (the old
/// "wake all"). Stages list only the channels specific to them in `wake_on`.
#define LIFE_WAKE_ALL (CHANGE_MOB_STAT | CHANGE_MOB_CLIENT | CHANGE_EXPLICIT)

// ---- change keys a mob publishes (PUBLISH_CHANGE) for the facts that are not one tracked var ----
// Read by on_change() reactions (the Life presentation reactions, living_systems.dm). A mob's stat is the tracked
// var key nameof(stat) (set_stat()).
/// A status started or ended, a status immunity or godmode or buckling changed, a pull began or ended.
#define MOB_KEY_STATUS "mob_status"
/// The body re-derived: injury, affliction, factors, organs (body.invalidate()).
#define MOB_KEY_HEALTH "mob_health"
/// The mob moved (its turf or container changed).
#define MOB_KEY_LOC "mob_loc"
/// Something was equipped or unequipped.
#define MOB_KEY_EQUIPMENT "mob_equipment"
/// A condition changed: body effects, mutations, species senses, stasis.
#define MOB_KEY_CONDITIONS "mob_conditions"
/// A client logged in or out.
#define MOB_KEY_CLIENT "mob_client"
/// What the client looks through changed: its eye, a remote view starting or ending, the view range (remote_view.dm,
/// reset_perspective()).
#define MOB_KEY_VIEW "mob_view"
/// HUD-list bits were marked stale (flag_hud_update()).
#define MOB_KEY_HUD_FLAGS "mob_hud_flags"

// --- run_if: the old early returns and `if` blocks, as frame facts --------------------------
/// The /mob/living core after `if(transforming) return` and `if(!loc) return`.
#define LIFE_RUN_IF_PLACED FACT("placed")
/// ... inside `if(stat != DEAD)`.
#define LIFE_RUN_IF_PLACED_ALIVE ALL_OF(FACT("placed"), FACT("alive"))
/// ... inside `if(handle_regular_status_updates())` (the status stage's result).
#define LIFE_RUN_IF_STATUS_OK ALL_OF(FACT("placed"), FACT("status_ok"))
/// The human tail inside `if(!stasis) if(stat != DEAD)` and `... else if(stat == DEAD)`.
#define LIFE_RUN_IF_LIVE_BIOLOGY ALL_OF(NOT_OF(FACT("in_stasis")), FACT("alive"))
/// P2-S6: a placed, living mob whose biology is not paused by stasis this frame. Stages that
/// declare it never ask inStasisNow() themselves.
#define LIFE_RUN_IF_PLACED_LIVE_BIOLOGY ALL_OF(FACT("placed"), NOT_OF(FACT("in_stasis")), FACT("alive"))
/// P2-S6: placed and not paused by stasis this frame, dead or alive (metabolism keeps running in a corpse).
#define LIFE_RUN_IF_PLACED_UNPAUSED ALL_OF(FACT("placed"), NOT_OF(FACT("in_stasis")))
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
// --- Steady-state resampling (idle rules with a rewake behind them; w5 human sleep rules) ------
/// A carbon breathing stage idle in steady air re-samples it this often (air can change in place).
#define BREATH_STEADY_RESAMPLE (30 SECONDS)
/// A human environment stage idle in comfortable air re-samples it this often.
#define ENVIRONMENT_STEADY_RESAMPLE (15 SECONDS)
/// A human chemicals stage with nothing to metabolise wakes this often to charge hunger.
#define NUTRITION_RESAMPLE (30 SECONDS)
/// At most this many Life cycles of hunger are charged at once after a nap.
#define NUTRITION_CATCHUP_CYCLES 50
/// A carbon's germs stage rolls its creep toward the ambient level this often.
#define GERM_RESAMPLE (1 MINUTES)
/// At most this many Life cycles of germ creep are charged at once.
#define GERM_CATCHUP_CYCLES 100
/// The HUD and sight reactions run at most this often (on_change at_most); changes in between coalesce.
#define LIFE_PRESENT_MIN_INTERVAL (0.5 SECONDS)
/// Observer upkeep (ghosts, AI eyes, blob overmind) runs this often.
#define OBSERVER_UPKEEP_INTERVAL (LIFE_CYCLE)
/// Every Nth pipeline frame is timed per stage and mob type (the mob service's two-minute profile).
#ifndef OM_NO_STAGE_PROFILE
#define LIFE_PROFILE_STRIDE 16
#else
#define LIFE_PROFILE_STRIDE 0
#endif
