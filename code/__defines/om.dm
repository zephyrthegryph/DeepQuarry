// Object-model core (doc/rewrite/object_model_core.md). Everything here is
// read by code/datums/om/*.dm and by content that declares om tables.

// ---- Lanes (section A.3). Each has a guaranteed budget share. ----
#define LANE_URGENT 1
#define LANE_SIMULATION 2
#define LANE_DERIVED 3
#define LANE_PRESENTATION 4
#define LANE_BACKGROUND 5
/// World-level systems (section 2): their every() work is budgeted here, beside the OM lanes the old scheduler had.
#define LANE_WORLD 6
#define OM_LANE_COUNT 6

// ---- Relevance levels (section A.8). ----
#define RELEVANCE_NONE 0
#define RELEVANCE_NEAR 1
#define RELEVANCE_VISIBLE 2
#define RELEVANCE_WATCHED 3
/// In a behaviour's `relevance` list: park at this level (off the ring; wakes and deadlines still arrive).
#define OM_PARK 0

// ---- Change channels (section B). 24 bits per family. The low 8 bits are
// generic and mean the same thing on every entity; bits 8-23 belong to the
// entity's family (mob, item, machine, generic datum), so the same bit can
// mean different things on a mob and on a machine. ----
#define CHANGE_EXPLICIT (1<<0)
#define CHANGE_RELATION_ADDED (1<<1)
#define CHANGE_RELATION_REMOVED (1<<2)
/// A related entity (relation forwarding or a watch) changed; delivered to the observer.
#define CHANGE_RELATED (1<<7)


// Machine family.
#define CHANGE_MACHINE_POWER (1<<8)
#define CHANGE_MACHINE_PANEL (1<<9)
#define CHANGE_MACHINE_BROKEN (1<<10)
#define CHANGE_MACHINE_ANCHORED (1<<11)
#define CHANGE_MACHINE_OCCUPANT (1<<12)
/// Settings a player or program changed (input/output levels, breakers, modes).
#define CHANGE_MACHINE_SETTINGS (1<<16)

// Generic datum family (framework-owned datums: sessions, edges, tasks).
#define CHANGE_DATUM_A (1<<8)
#define CHANGE_DATUM_B (1<<9)
#define CHANGE_DATUM_C (1<<10)

// Rust -> DM change delivery sources (code/datums/om/native_adapter.dm).
#define NATIVE_SRC_GAS_EVENT 1
#define NATIVE_SRC_GAS_WATCH 2
#define NATIVE_SRC_WORLD_WATCH 3
#define NATIVE_SRC_HEAT 4
#define NATIVE_SRC_POWER 5
#define NATIVE_SRC_OTHER 6
#define NATIVE_SRC_COUNT 6




/// verb_source() names: shared sources for verb grants nothing else owns.
#define VERB_SOURCE_CONFIG "config"
#define VERB_SOURCE_ADMIN "admin"
// Cadence ids (STAT_CADENCE_HOLDS keys). Shortest step wins; the system's own step (CADENCE_BASE_DT) applies with none held.
/// A canister rupture, hull breach or pressure-jump storm: gas publishes every 0.1 s.
#define CADENCE_GAS_FAST "gas_fast"
/// Something visibly moving but not violent: gas publishes every 0.25 s.
#define CADENCE_GAS_BRISK "gas_brisk"
/// The world's step with no cadence grant held, seconds.
#define CADENCE_BASE_DT 0.5

// Stat presets (statuses and godmode are stats: code/library/mob/statuses.dm).

// The biological clock domain: it runs at the clock_rate_bio stat (code/datums/om/contribution.dm, om_clock_compute()).
#define CLOCK_BIO "bio"

// ---- Relations (section D). ----
#define OM_REL_REPLACE 1
#define OM_REL_REFUSE 2

// Relation shapes (/datum/om/relation/var/shape, doc/rewrite/ownership.md §4.2).
/// A source has one target and a target one source.
#define REL_ONE_TO_ONE 1
/// A source has many targets; a target has one source.
#define REL_ONE_TO_MANY 2
/// Any number either way.
#define REL_MANY_TO_MANY 3
/// Membership with no direction (atmos node topology): either end may be the source.
#define REL_SYMMETRIC 4

// Unlink reasons (/datum/om/edge/var/unlink_reason, read in on_unlink()).
#define RELATION_UNLINKED "unlinked"
#define RELATION_DESTROYING "destroying"
#define RELATION_BROKEN "broken"
#define RELATION_REPLACED "replaced"
#define RELATION_LEFT "left"
#define RELATION_Z_RELEASED "z released"
#define OM_END_UNLINK 1
#define OM_END_DELETE_OTHER 2

// ---- Derived aggregates (section C). ----
#define AGG_NONE 0
#define AGG_SUM 1
#define AGG_COUNT 2
#define AGG_ANY 3
#define AGG_ALL 4
#define AGG_MIN 5
#define AGG_MAX 6
#define AGG_CUSTOM 7

/// A parameterised check spec: CHECK(/datum/om/check/in_range, 1). `path` must be a literal type path.
#define CHECK(path, arg) list(path = arg)

#define DERIVE(name, expr, channel) list("derive" = "check", "name" = name, "expr" = expr, "channel" = channel)

/// The entity world-wide events go to (was SEND_GLOBAL_SIGNAL's target).
#define OM_WORLD (GLOB.om_world)

// Attachment state bits (rec.att_state).
#define OM_ATT_STARTED (1<<0)
#define OM_ATT_REQ_OK (1<<1)
#define OM_ATT_PARKED (1<<2)

// ---- Deadline keys (section A.5). One deadline per (entity, behaviour, sub-key). ----
/// key = behaviour id + sub * OM_DL_SUB. Sub 0 is the behaviour's own on_deadline().
#define OM_DL_SUB 4096
/// Sub-key of the deferred wake of a min_interval behaviour (scheduler-owned).
#define OM_DL_THROTTLE 1
/// First sub-key of pipeline stage rewakes: OM_DL_STAGE + the stage's position in its pipeline.
#define OM_DL_STAGE 2

// ---- Pipelines (section A.10). ----
/// Stage run() result: nothing left to do until a wake_on channel changes (or its rewake).
#define STAGE_IDLE "stage_idle"
/// What F.abort() returns: `return F.abort()` stops the frame.
#define STAGE_ABORT "stage_abort"
/// F.abort() scopes. FRAME: stop now, nothing idles this frame. REST: stop now, keep the
/// idles already decided.
#define OM_ABORT_FRAME 1
/// A frame fact in a run_if spec: FACT("alive"), NOT_OF(FACT("in_stasis")).
#define FACT(name) list(/datum/om/check/fact = name)
/// /datum/om/pipeline/var/run_mode bits (compiled at boot).
#define OM_PIPE_MODE_HOOKS (1<<0)
#define OM_PIPE_MODE_FACTS (1<<1)
#define OM_PIPE_MODE_PROFILING (1<<2)
#define OM_PIPE_MODE_REACTIVE (1<<3)
#define OM_PIPE_MODE_PARKS (1<<4)
/// Asleep bits: 16 stages per word.
#define OM_PIPE_WORD(i) ((((i) - 1) >> 4) + 1)
#define OM_PIPE_BIT(i) (1 << (((i) - 1) & 15))

/// The pipeline missed-wake audit: how often, and how many parked and awake entities per pipeline.
#define OM_AUDIT_INTERVAL (30 SECONDS)
#define OM_AUDIT_PARKED_SAMPLE 400
#define OM_AUDIT_AWAKE_SAMPLE 100

// ---- Scheduler tuning. ----
/// Width of one cadence slot and one deadline bucket, deciseconds.
#define OM_SLOT_DS 1
#define OM_DEADLINE_BUCKETS 1024
/// Max substeps for a behaviour's max_dt.
#define OM_MAX_SUBSTEPS 10
/// Share of the tick budget reserved for deadlines, before lanes.
#define OM_DEADLINE_SHARE 0.2
/// Diagnostics: max behaviour types with their own counters.
#define OM_MAX_STAT_TYPES 512

// Diagnostics counters per behaviour id (scheduler.stats[bid] list indexes).
#define OM_STAT_RUNS 1
#define OM_STAT_MS 2
#define OM_STAT_LATE_MAX 3
#define OM_STAT_DEFERRALS 4
#define OM_STAT_BREACHES 5
#define OM_STAT_WAKES 6
#define OM_STAT_DEADLINES 7
#define OM_STAT_ERRORS 8
#define OM_STAT_CALL_MAX 9
/// Pipelines: entities parked, unparked, and missed wakes found by the audit.
#define OM_STAT_PARKS 10
#define OM_STAT_UNPARKS 11
#define OM_STAT_MISSED 12
#define OM_STAT_LEN 12

// Cadence loops in /datum/om/scheduler/proc/run_slot().
#define OM_SLOT_FAST 1
#define OM_SLOT_STEP 2
#define OM_SLOT_SLOW 3

// Hook kinds for /datum/om/scheduler/proc/call_hook().
#define OM_HOOK_TICK 1
#define OM_HOOK_WAKE 2
#define OM_HOOK_DEADLINE 3
#define OM_HOOK_STEP 4
#define OM_HOOK_START 5
#define OM_HOOK_STOP 6
#define OM_HOOK_NATIVE 7
#define OM_HOOK_KEYED 8
/// The entity is being destroyed (destroy transaction phase 4, before links clear).
#define OM_HOOK_DESTROY 9

/// One entity's step taking more than this (percent of a tick) is noted as the tick's slow step
/// (/datum/om/scheduler/proc/note_slow_step()), named in the MC's overrun record.
#define OM_SLOW_STEP_USAGE 100

// Uncomment (or pass -DOM_PROFILE_CALLS) for per-call timing in the cadence loop.
// #define OM_PROFILE_CALLS
// Uncomment (or pass -DOM_DERIVED_AUDIT) to recompute aggregates on every read and compare.
// #define OM_DERIVED_AUDIT

// ---------------------------------------------------------------- relation and slot accessors
//
// No view fields (doc/rewrite/object_model_core.md, relations; OM relations
// step 3): a relation or slot IS the state -- readers go through these, not a
// plain var the core used to mirror onto the entity. Each is a direct read
// against the entity's own OM record (its edge list, or the ledger for
// slots), so there is nothing for a lint to catch and nothing to keep in
// sync: deleting the old mirrored var is what makes every remaining direct
// read a compile error.

// Named relation reads are typed procs on /datum (code/datums/om/relation.dm):
// M.buckled_to(), A.buckled_mob_list(), M.pulling_target(), ... E.slot_item(slot).

// ---------------------------------------------------------------- periodic cadences (code/engine/kernel/cadences.dm)


/// The source a periodic member holds its cadence membership under (member_join()).
#define PERIODIC_SOURCE "periodic"
#define PERIODIC_SLOW /datum/cadence/slow
#define PERIODIC_SECOND /datum/cadence/second
#define PERIODIC_FAST /datum/cadence/fast

// ---------------------------------------------------------------- published facts as change channels
// What S2's reactor keys were is now plain change channels on the entity the fact belongs to;
// whatever waits on it om_watch()es those channels with its own behaviour.

/// Machine family: a mode another machine or program may wait on changed (door bolts, power,
/// electrification, open state; an APC's operating state).
#define CHANGE_MACHINE_MODE (1<<18)
// Bits 22 and 23 are the last two a DM bitfield holds (24-bit bitwise operators).
/// Any atom: its integrity changed (update_integrity()); the get_integrity derived field.
#define CHANGE_INTEGRITY (1<<23)
/// Power machine family, raised on every machine bound to a power region
/// (code/modules/power/power_grid.dm): the region's supply or load moved; its
/// brownout or monitor warning changed; a machine joined or left it.
#define CHANGE_POWER_GRID_RATE (1<<19)
#define CHANGE_POWER_GRID_STATE (1<<20)
#define CHANGE_POWER_GRID_TOPOLOGY (1<<21)
	/// Which schedule a status display shows (shuttle_schedule_source()).
	#define SHUTTLE_SCHEDULE_EVAC 1
	#define SHUTTLE_SCHEDULE_SUPPLY 2
// ---- Task steps (object_model_core.md §4.11): what a step proc returns. ----
/// om_guarded_call(): the callee slept (it finishes on its own; its result is lost).
#define OM_CALLEE_SLEPT "__om_callee_slept"
// STEP_NEXT, STEP_DONE, STEP_REPEAT() and STEP_FAIL() are code/__defines/engine/tasks.dm's.

// ---- Declared caches (lifecycle.md §4, LC-refs): the invalidation rule each entry of
// declared_cache_vars() names. The core nulls the var when the rule fires.
/// Cleared when any of `bits` is raised on the entity (changed / OM_CHANGED).
#define CACHE_ON_CHANGE(bits) list("change", bits)

// ---------------------------------------------------------------- declared fields (code/datums/om/fields.dm)




/// A derived (read-only) field: `T/proc/F()` computes it from its declared INPUTS, a list of the
/// declared fields it reads (by name) and of raw channels for inputs that are not fields (a datum's
/// own channel). Its channel is the union of the inputs' channels, resolved once per
/// type (scheduler_field_field_table()), so every input setter raises it: nothing refreshes a derived field by
/// hand. A stage that `reads = list("F")` wakes on it. There is no var and no setter. `OM_DERIVE_FIELD(/obj/item/tank, pressure_watched, list("leaking", "atom_integrity", CHANGE_DATUM_A))`
#define OM_DERIVE_FIELD(T, F, INPUTS) /datum/om/field_def##T/F { of = T; field = #F; inputs = INPUTS; derived = TRUE }

// ---------------------------------------------------------------- om_prompt requires (prompt.dm)
// Common re-checks for an answer: actor = the user, target = the spec's target, else E.


// ---------------------------------------------------------------- named-argument launchers
// DM rejects a named argument a proc doesn't declare, so these are macros: the named arguments
// become a list keyed by var name, and the caller's src rides along (the receiver default).



// The ASK_* re-check flags moved to code/__defines/kernel.dm (a request re-checks them when its answer arrives).


