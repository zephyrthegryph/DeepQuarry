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
/// In a behaviour's `relevance` list: do not run at this level (sleep).
#define OM_SLEEP 0

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
#define EFFECT_STUNNED "stunned"
#define EFFECT_PARALYZED "paralyzed"
#define EFFECT_BUCKLED "buckled"
#define EFFECT_SLOWED "slowed"
#define EFFECT_BLINDED "blinded"
#define EFFECT_MUTED "muted"
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
#define OM_ATT_SLEEPING (1<<2)

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
#define OM_STAT_LEN 9

// Hook kinds for /datum/om/scheduler/proc/call_hook().
#define OM_HOOK_TICK 1
#define OM_HOOK_WAKE 2
#define OM_HOOK_DEADLINE 3
#define OM_HOOK_STEP 4
#define OM_HOOK_START 5
#define OM_HOOK_STOP 6
#define OM_HOOK_NATIVE 7

// Uncomment (or pass -DOM_PROFILE_CALLS) for per-call timing in the cadence loop.
// #define OM_PROFILE_CALLS
// Uncomment (or pass -DOM_DERIVED_AUDIT) to recompute aggregates on every read and compare.
// #define OM_DERIVED_AUDIT
