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
/// Channels that wake every Life step: explicit wakes (the old "wake all"). Steps list only the keys specific to them in `reads`.
#define LIFE_WAKE_ALL CHANGE_EXPLICIT
/// Keys that wake every Life step: set_stat() and a client logging in or out.
#define LIFE_WAKE_KEYS list(nameof(/mob::stat), MOB_KEY_CLIENT)

/// What wakes a Life step that reads a mob's status: the status fact and the tracked vars Life's status steps follow.
#define LIFE_STATUS_READS list(MOB_KEY_STATUS, nameof(/mob::sdisabilities), nameof(/mob::ear_damage), nameof(/mob/living/simple_mob::purge))
/// What wakes a Life step that reads a mob's long-running conditions: the condition fact and the tracked vars the condition steps follow.
#define LIFE_CONDITION_READS list(MOB_KEY_CONDITIONS, nameof(/mob/living::instability), nameof(/mob/living::virtual_reality_mob), 	nameof(/mob/living::glow_toggle), nameof(/mob/living::glow_override), nameof(/mob/living::glow_range), 	nameof(/mob/living::glow_intensity), nameof(/mob/living::glow_color), nameof(/mob/living::tf_mob_holder))

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
/// A living mob's nutrition changed (set_nutrition()); nutrition_of() reads as it.
#define MOB_KEY_NUTRITION "mob_nutrition"
/// A mob picked up, dropped or swapped what it holds in its hands (a window that needs a held tool re-checks its status).
#define MOB_KEY_HANDS "mob_hands"
/// The air the mob stands in crossed a level that matters to it (its air watch, air_watch.dm: oxygen, toxins, N2O, CO2,
/// temperature or pressure moved into another band). The breathing
/// and environment steps read it, so a gas filling a room, the oxygen draining or the room heating wakes the breathers in it.
#define MOB_KEY_AIR "mob_air"
/// The mob's body temperature crossed a level that matters to it (its body heat watch, air_watch.dm): the comfort band
/// around its set point, the discomfort and harm levels. Thermoregulation, environment and medical read it.
#define MOB_KEY_BODY_HEAT "mob_body_heat"
/// The mob's radiation dose changed (add_radiation(), purge_radiation(), clear_radiation()). The radiation step reads it.
#define MOB_KEY_RADIATION "mob_radiation"
/// What others see of who the mob is changed outside its own vars: a face disfigured or mended, the name on a worn ID or
/// PDA, a disguise (shadekin phase) toggled. Published by those setters (identity_changed_on_holder()); the real name
/// is its own tracked key (nameof(real_name)).
#define MOB_KEY_IDENTITY "mob_identity"
/// The ground under the mob changed: its turf (or the one below it) was replaced, or its area's gravity switched
/// (ChangeTurf(), /area/gravitychange()). Falling and the gravity read in movement follow it.
#define MOB_KEY_GROUND "mob_ground"
/// A movable moved (its turf or container changed): published only while someone observes it (a window watching its host).
#define ATOM_KEY_LOC "atom_loc"

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
// --- Wakes first, resampling only as a fallback (doc/rewrite/life_on_om.md §5) ------------------
// A sleeping step is woken by the change of what it reads (its `reads`, listed with their producers in `woken_by`).
// A rewake no shorter than LIFE_SAFETY_RESAMPLE is only a safety net behind those wakes; a shorter one is allowed only
// for work that drifts with time itself (hunger, germs, a timer), declared with LIFE_WOKEN_BY_TIME in woken_by. There
// is no polling: every input is tracked state, a published key or a declared relation
// (life_om/steps_declare_their_wakes checks it).
/// The safety re-check behind a step's wakes: a missed wake costs at most this long.
#define LIFE_SAFETY_RESAMPLE (2 MINUTES)
/// The woken_by entry of a step whose rewake is its work (it drifts with time), not a stand-in for a missing wake.
#define LIFE_WOKEN_BY_TIME "time"
/// A carbon breathing stage idle in steady air: woken by its air watch, moving, equipment; this is the fallback.
#define BREATH_STEADY_RESAMPLE LIFE_SAFETY_RESAMPLE
/// A human environment stage idle in comfortable air: woken by its air watch and body heat watch; this is the fallback.
#define ENVIRONMENT_STEADY_RESAMPLE LIFE_SAFETY_RESAMPLE
/// A human chemicals stage with nothing to metabolise wakes this often to charge hunger (time-driven: hunger drifts).
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

// --- Breath levels (kPa of a gas in the breath; the same as in the air breathed) --------------------
// The breath code acts on them and a breather's air watch (air_watch.dm) wakes on crossing them: one list.
/// The species' exhaled gas past this crowds out the breath (hypercapnia); 0.6 and 0.7 of it warn and start to worsen it.
#define BREATH_EXHALED_MAX 10
/// A poison gas (the species' poison_type, methane) past this is smelt or burns.
#define BREATH_TOXINS_MIN 0.05
/// A poison gas past this poisons (toxin in the blood) or displaces the breath (methane).
#define BREATH_TOXINS_MAX 0.2
/// Nitrous oxide past this makes the breather giggle.
#define BREATH_N2O_GIGGLE 0.15
/// Nitrous oxide past this paralyses.
#define BREATH_N2O_PARALYSE 1
/// Nitrous oxide past this puts the breather to sleep.
#define BREATH_N2O_SLEEP 5
/// Kelvin below the species' normal body temperature where cold exposure (hypothermia) begins (the medical metric trigger).
#define DQ_COLD_EXPOSURE_KELVIN 20
/// Kelvin above it where heat exposure (heatstroke) begins.
#define DQ_HEAT_EXPOSURE_KELVIN 5
