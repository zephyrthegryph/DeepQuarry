// Mob Life on the kernel's Life sequence (/datum/sequence/life, doc/rewrite/life_sequences.md): these defines are
// its vocabulary. The machinery (sleep bits, parking, conditions, rewakes) is the kernel's
// (code/controllers/kernel/sequence.dm).

// --- Anchors: the bands of the old Life() sequence -------------------------------------------------------------------
// Named no-op steps. A step says which band it runs in with `after = LIFE_BODY`; an anchor is passed only
// when no step is ready, so everything in a band runs before the next band begins.
#define LIFE_INPUT "LIFE_INPUT"
#define LIFE_BODY "LIFE_BODY"
#define LIFE_MIND "LIFE_MIND"
#define LIFE_OUTPUT "LIFE_OUTPUT"
#define LIFE_TAIL "LIFE_TAIL"

// --- Wakes (doc/rewrite/life_on_om.md §5) ----------------------------------------------------
/// Channels that wake every Life step: set_stat, Login and Logout, explicit wakes (the old
/// "wake all"). Steps list only the channels specific to them in `reads`.
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

// --- Life sets (/mob/living/var/life_set) ---------------------------------------------------
// Which family of Life steps a mob runs (life_steps.dm checks it). The legacy silicon Life() procs never called
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
/// Frames in a row that must end with every step asleep before a mob parks.
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
/// Every Nth Life frame is timed per step (the mob service's two-minute profile).
#ifndef OM_NO_STAGE_PROFILE
#define LIFE_PROFILE_STRIDE 16
#else
#define LIFE_PROFILE_STRIDE 0
#endif
