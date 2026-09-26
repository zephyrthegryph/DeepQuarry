// Object-model core (doc/rewrite/object_model_core.md). Everything here is
// read by code/datums/om/*.dm and by content that declares om tables.

// ---- Lanes (section A.3). Each has a guaranteed budget share. ----
#define LANE_URGENT 1
#define LANE_SIMULATION 2
#define LANE_DERIVED 3
#define LANE_PRESENTATION 4
#define LANE_BACKGROUND 5
#define OM_LANE_COUNT 5

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
#define CHANGE_EFFECTS (1<<3)
#define CHANGE_CLOCK (1<<4)
#define CHANGE_RELEVANCE (1<<5)
#define CHANGE_CONTENTS (1<<6)
/// A related entity (relation forwarding or a watch) changed; delivered to the observer.
#define CHANGE_RELATED (1<<7)
#define CHANGE_GENERIC_MASK 0xFF

// Mob family.
#define CHANGE_MOB_STAT (1<<8)
#define CHANGE_MOB_HEALTH (1<<9)
#define CHANGE_MOB_LOC (1<<10)
#define CHANGE_MOB_HANDS (1<<11)
#define CHANGE_MOB_EQUIPMENT (1<<12)
#define CHANGE_MOB_CLIENT (1<<13)
#define CHANGE_MOB_MOVEMENT (1<<14)
#define CHANGE_MOB_STATUS (1<<15)
#define CHANGE_MOB_VITALS (1<<16)
#define CHANGE_MOB_CAN_MOVE (1<<17)
/// Modifiers, instability, diseases: the long-running conditions the upkeep systems follow.
#define CHANGE_MOB_CONDITIONS (1<<18)

// Item family.
#define CHANGE_ITEM_LOC (1<<8)
#define CHANGE_ITEM_MASS (1<<9)
#define CHANGE_ITEM_HEAT (1<<10)
#define CHANGE_ITEM_CHARGE (1<<11)
#define CHANGE_ITEM_WORN (1<<12)
#define CHANGE_ITEM_ARMOR (1<<13)
#define CHANGE_ITEM_TOTAL_MASS (1<<14)

// Machine family.
#define CHANGE_MACHINE_POWER (1<<8)
#define CHANGE_MACHINE_PANEL (1<<9)
#define CHANGE_MACHINE_BROKEN (1<<10)
#define CHANGE_MACHINE_ANCHORED (1<<11)
#define CHANGE_MACHINE_OCCUPANT (1<<12)
#define CHANGE_MACHINE_OUTPUT (1<<13)
#define CHANGE_MACHINE_POWERED_OK (1<<14)
#define CHANGE_MACHINE_CHARGE (1<<15)
/// Settings a player or program changed (input/output levels, breakers, modes).
#define CHANGE_MACHINE_SETTINGS (1<<16)

// Generic datum family (framework-owned datums: sessions, edges, tasks).
#define CHANGE_DATUM_A (1<<8)
#define CHANGE_DATUM_B (1<<9)
#define CHANGE_DATUM_C (1<<10)
#define CHANGE_DATUM_D (1<<11)

/// The one guarded setter call. Content writes om_changed(E, bits); this form
/// is for hot setters that want the listen-mask test inlined.
#define OM_CHANGED(E, bits) if((E).om_listen & (bits)) { om_dispatch_change(E, bits) }

// ---- Effects (section E). combine / stacking values for effect table rows. ----
#define COMBINE_ANY 1
#define COMBINE_SUM 2
#define COMBINE_MAX 3
#define COMBINE_MIN 4
#define COMBINE_MULTIPLY 5
#define COMBINE_SUM_PER_KEY 6

#define STACKING_REPLACE 1
#define STACKING_EXTEND 2
#define STACKING_MAX 3

// Effect kinds the framework itself reacts to.
#define OM_EFFECT_PLAIN 0
#define OM_EFFECT_CLOCK_MULT 1
#define OM_EFFECT_CLOCK_INHIBIT 2
#define OM_EFFECT_RELEVANCE 3
#define OM_EFFECT_SUSPEND 4
/// A timed status (units, wear rate, immunity, hooks): status.dm.
#define OM_EFFECT_STATUS 5

// Built-in effect ids (library.dm defines the rest).
#define EFFECT_RELEVANCE "om_relevance"
#define EFFECT_SUSPENDED "om_suspended"

// Grant kinds (effects with COMBINE_SUM_PER_KEY).
#define GRANT_ABILITY "grant_ability"
#define GRANT_LANGUAGE "grant_language"
#define GRANT_VERB "grant_verb"
#define GRANT_ACCESS "grant_access"
#define GRANT_TRAIT "grant_trait"

// Status and stat presets.
// Mob statuses (doc/rewrite/life_on_om.md §7): timed contributions a mob holds on itself,
// amounts in status units (one LIFE_CYCLE each unless the status wears off faster).
#define EFFECT_STUNNED "stunned"
#define EFFECT_PARALYZED "paralyzed"
#define EFFECT_WEAKENED "weakened"
#define EFFECT_SLEEPING "sleeping"
#define EFFECT_CONFUSED "confused"
/// Temporary blindness (was eye_blind).
#define EFFECT_BLINDED "blinded"
/// Blurred sight (was eye_blurry).
#define EFFECT_BLURRY "blurry"
/// Temporary deafness (was ear_deaf).
#define EFFECT_DEAFENED "deafened"
#define EFFECT_STUTTERING "stuttering"
/// Can't speak (was silent).
#define EFFECT_MUTED "muted"
/// Drugged (was druggy).
#define EFFECT_DRUGGED "drugged"
#define EFFECT_SLURRING "slurring"
/// Drowsy (was drowsyness).
#define EFFECT_DROWSY "drowsy"
#define EFFECT_HALLUCINATING "hallucinating"
/// Dizziness and jitters: magnitude statuses, 0-1000 points (were components' counters).
#define EFFECT_DIZZY "dizzy"
#define EFFECT_JITTERY "jittery"
// Status immunities: holding one blocks (and on gaining, ends) the statuses that name it.
#define EFFECT_IMMUNE_STUN "immune_stun"
#define EFFECT_IMMUNE_WEAKEN "immune_weaken"
#define EFFECT_IMMUNE_PARALYZE "immune_paralyze"
#define EFFECT_IMMUNE_DIZZY "immune_dizzy"
#define EFFECT_IMMUNE_JITTER "immune_jitter"
/// Godmode (admins, soulstones, AI eyes, preview dummies): harm is cancelled; implies the incapacitation immunities.
#define EFFECT_GODMODE "godmode"
#define EFFECT_BUCKLED "buckled"
#define EFFECT_SLOWED "slowed"
#define EFFECT_CAN_MOVE "can_move"
#define EFFECT_CAN_ACT "can_act"
#define EFFECT_ARMOR_MELEE "armor_melee"
#define EFFECT_ARMOR_BULLET "armor_bullet"
#define EFFECT_ARMOR_HEAT "armor_heat"
#define EFFECT_INSULATION "insulation"
#define EFFECT_MOVE_SPEED "move_speed"
#define EFFECT_POWER_DRAW "power_draw"
#define EFFECT_HUD_VITALS "hud_vitals"

// Clock domains and their generated effect ids ("clock:<id>:mult"/":inhibit").
#define CLOCK_BIO "bio"
#define CLOCK_MACHINE "machine"
#define CLOCK_CHEM "chem"
#define EFFECT_CLOCK_BIO_MULT "clock:bio:mult"
#define EFFECT_CLOCK_BIO_INHIBIT "clock:bio:inhibit"
#define EFFECT_CLOCK_MACHINE_MULT "clock:machine:mult"
#define EFFECT_CLOCK_MACHINE_INHIBIT "clock:machine:inhibit"
#define EFFECT_CLOCK_CHEM_MULT "clock:chem:mult"
#define EFFECT_CLOCK_CHEM_INHIBIT "clock:chem:inhibit"

// ---- Relations (section D). ----
#define OM_REL_REPLACE 1
#define OM_REL_REFUSE 2
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

// ---- Combinators for checks, effects and derived rows (plain lists).
// These are macros only so they can appear in var declarations; each is a plain list.
#define ALL_OF(parts...) list("all", ##parts)
#define ANY_OF(parts...) list("any", ##parts)
#define NOT_OF(part) list("not", part)
/// Effects only: sum of other effects' values.
#define SUM_OF(parts...) list("sum", ##parts)
/// A parameterised check spec: CHECK(/datum/om/check/in_range, 1). `path` must be a literal type path.
#define CHECK(path, arg) list(path = arg)

// One-line derived declarations (plain lists; see decl.dm).
#define FROM_VAR(name) list("var", name)
#define FROM_DERIVED(name) list("derived", name)
#define FROM_EFFECT(id) list("effect", id)
#define OVER_SLOT(id) list("slot", id)
#define DERIVE(name, expr, channel) list("derive" = "check", "name" = name, "expr" = expr, "channel" = channel)
#define DERIVE_SUM(name, over, reader, channel) list("derive" = "sum", "name" = name, "over" = over, "reader" = reader, "channel" = channel)
#define DERIVE_COUNT(name, over, channel) list("derive" = "count", "name" = name, "over" = over, "channel" = channel)
#define DERIVE_ANY(name, over, reader, channel) list("derive" = "any", "name" = name, "over" = over, "reader" = reader, "channel" = channel)
#define DERIVE_ALL(name, over, reader, channel) list("derive" = "all", "name" = name, "over" = over, "reader" = reader, "channel" = channel)
#define DERIVE_MIN(name, over, reader, channel) list("derive" = "min", "name" = name, "over" = over, "reader" = reader, "channel" = channel)
#define DERIVE_MAX(name, over, reader, channel) list("derive" = "max", "name" = name, "over" = over, "reader" = reader, "channel" = channel)

// ---- Events (section G). ----
#define EVENT_VETO 1

// ---- Tasks (section I). ----
/// Legacy sleeping procs wait on a task with a mandatory timeout (deciseconds).
#define AWAIT(task, timeout) om_await(task, timeout)
#define OM_TASK_RUNNING 0
#define OM_TASK_DONE 1
#define OM_TASK_CANCELLED 2

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
#define OM_ABORT_REST 2
/// A frame fact in a run_if spec: FACT("alive"), NOT_OF(FACT("in_stasis")).
#define FACT(name) list(/datum/om/check/fact = name)
/// /datum/om/pipeline/var/run_mode bits (compiled at boot).
#define OM_PIPE_MODE_HOOKS (1<<0)
#define OM_PIPE_MODE_FACTS (1<<1)
#define OM_PIPE_MODE_PROFILING (1<<2)
#define OM_PIPE_MODE_REACTIVE (1<<3)
#define OM_PIPE_MODE_PARKS (1<<4)
/// Set for one frame by run_frame() when the profiler samples it.
#define OM_PIPE_MODE_PROFILE (1<<5)
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

/// The single target of `E`'s edge of relation `REL` (E is the source), or null.
#define OM_REL_TARGET(E, REL) om_relation_of(E, REL)
/// The single source of an edge of relation `REL` targeting `E` (E is the
/// target), or null. Pair with a target_single relation.
#define OM_REL_SOURCE(E, REL) om_source_of(E, REL)
/// Every source of an edge of relation `REL` targeting `E` (E is the target).
#define OM_REL_SOURCES(E, REL) om_related_to(E, REL)
/// Every target of `E`'s edges of relation `REL` (E is the source).
#define OM_REL_TARGETS(E, REL) om_related(E, REL)

/// The one thing in `E`'s slot `SLOT` (null: its default slot), or null.
#define SLOT_ITEM(E, SLOT) ((E) ? (E).slot_item(SLOT) : null)
/// A copy of what is in `E`'s slot `SLOT` (null: every slot, in slot order).
#define SLOT_LIST(E, SLOT) ((E) ? (E).slot_contents(SLOT) : list())

/// What `M` is buckled to, or null.
#define BUCKLED(M) OM_REL_TARGET(M, /datum/om/relation/buckled_to)
/// Every mob buckled to `A`.
#define BUCKLED_MOBS(A) OM_REL_SOURCES(A, /datum/om/relation/buckled_to)
/// What `M` is pulling, or null.
#define PULLING(M) OM_REL_TARGET(M, /datum/om/relation/pulling)
/// Who is pulling `A`, or null.
#define PULLED_BY(A) OM_REL_SOURCE(A, /datum/om/relation/pulling)
/// Every grab item holding `M`.
#define GRABBED_BY(M) OM_REL_SOURCES(M, /datum/om/relation/grabbing)
/// The AI eye watching for `AI`, or null.
#define EYE_OF(AI) OM_REL_SOURCE(AI, /datum/om/relation/ai_eye_of)
/// The mob `G` (a grab item) is grabbing, or null.
#define GRAB_TARGET(G) OM_REL_TARGET(G, /datum/om/relation/grabbing)
