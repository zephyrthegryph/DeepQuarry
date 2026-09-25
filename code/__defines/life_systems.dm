// Life scheduler (doc/mob_life_architecture.md §4). /mob/living/Life() runs an ordered list
// of /datum/life_system flyweights; these defines are its vocabulary.

// --- Phases: the coarse position of a system inside one Life cycle --------------------------
// Systems sort by phase, then order. The phase-2 move keeps the legacy Life() sequence, so
// every system sits in the phase that matches where its code ran before; LIFE_PHASE_TAIL
// holds the code subtypes ran after ..() (human, alien, simple mob and bot tails, and the
// per-type pre/post chains). Later phases re-home those systems.
#define LIFE_PHASE_INPUT 1
#define LIFE_PHASE_BODY 2
#define LIFE_PHASE_MIND 3
#define LIFE_PHASE_OUTPUT 4
#define LIFE_PHASE_TAIL 5

// --- tick() results ------------------------------------------------------------------------
// Strings, so no legacy return value (TRUE, 1, a flag) can be mistaken for a scheduler code.
/// Nothing left to do until woken: clears the system's wake bit.
#define LIFE_SLEEP "life_sleep"
/// End this mob's cycle now (the old early `return` before `..()` in a Life() override).
#define LIFE_HALT "life_halt"

// --- Wake masks (doc/rewrite/life_on_om.md §5) ----------------------------------------------
// A system declares `wake_on`: the mob change channels (code/__defines/om.dm) whose change can
// give it work. Producers raise channels with om_changed(); the life behaviour's on_wake clears the
// asleep flag of every system whose mask matches. STAT, CLIENT and EXPLICIT wake every system.
// Each mask below is the old wake bit of that concern translated to the channels whose producers
// used to wake it.
/// Every system wakes on these (the old "wake all": set_stat, Login, Logout, recomposition).
#define LIFE_WAKE_ALWAYS (CHANGE_MOB_STAT | CHANGE_MOB_CLIENT | CHANGE_EXPLICIT)
#define LIFE_WAKE_ON_TRAITS (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_UPKEEP (LIFE_WAKE_ALWAYS | CHANGE_MOB_LOC | CHANGE_MOB_CONDITIONS)
#define LIFE_WAKE_ON_BREATHING (LIFE_WAKE_ALWAYS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT)
#define LIFE_WAKE_ON_THERMAL (LIFE_WAKE_ALWAYS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT)
#define LIFE_WAKE_ON_RADIATION (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_METABOLISM (LIFE_WAKE_ALWAYS | CHANGE_MOB_HEALTH)
#define LIFE_WAKE_ON_BODY (LIFE_WAKE_ALWAYS | CHANGE_MOB_HEALTH)
#define LIFE_WAKE_ON_BLOOD (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_ORGANS (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_NUTRITION (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_GENETICS (LIFE_WAKE_ALWAYS | CHANGE_MOB_STATUS)
#define LIFE_WAKE_ON_STATUS (LIFE_WAKE_ALWAYS | CHANGE_MOB_STATUS)
#define LIFE_WAKE_ON_ADDICTION (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_SENSES (LIFE_WAKE_ALWAYS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT)
#define LIFE_WAKE_ON_IDENTITY (LIFE_WAKE_ALWAYS | CHANGE_MOB_HEALTH | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT)
#define LIFE_WAKE_ON_HUD (LIFE_WAKE_ALWAYS | CHANGE_MOB_HEALTH | CHANGE_MOB_STATUS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT)
#define LIFE_WAKE_ON_CLIENT (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_MOVEMENT (LIFE_WAKE_ALWAYS | CHANGE_MOB_STATUS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT)
#define LIFE_WAKE_ON_MACHINE (LIFE_WAKE_ALWAYS)
#define LIFE_WAKE_ON_BEHAVIOUR (LIFE_WAKE_ALWAYS)
/// Every channel any system wakes on: the life behaviour's own wake_on.
#define LIFE_WAKE_CHANNELS (LIFE_WAKE_ALWAYS | CHANGE_MOB_HEALTH | CHANGE_MOB_STATUS | CHANGE_MOB_LOC | CHANGE_MOB_EQUIPMENT | CHANGE_MOB_CONDITIONS)

// --- Wake-only systems (doc/rewrite/life_on_om.md §6) ------------------------------------------
/// Not wake-only: runs in the frame.
#define LIFE_WAKE_ONLY_NONE 0
/// Status derivation (canmove): run by the life_derive behaviour when the status changes.
#define LIFE_WAKE_ONLY_DERIVE 1
/// Presentation (HUD, vision): run by the life_present behaviour, only for mobs with a client.
#define LIFE_WAKE_ONLY_PRESENT 2
/// Channels the derive behaviour reacts to.
#define LIFE_DERIVE_CHANNELS (CHANGE_MOB_STATUS | CHANGE_MOB_STAT | CHANGE_EXPLICIT)
/// Channels the present behaviour reacts to.
#define LIFE_PRESENT_CHANNELS (LIFE_WAKE_ON_HUD)
/// The present behaviour runs at most this often; changes in between are coalesced.
#define LIFE_PRESENT_MIN_INTERVAL (0.5 SECONDS)

// --- Segments (/datum/life_context/var/blocked) ---------------------------------------------
// A segment is the run of code that followed an early `return` in a legacy Life() or an
// `if` around a block of hooks. A gate system blocks its segment; the scheduler then skips
// every system tagged with it for the rest of the cycle.
/// /mob/living core after `if(transforming) return` / `if(!loc) return`.
#define LIFE_SEG_LIVING (1<<0)
/// /mob/living core inside `if(stat != DEAD)`.
#define LIFE_SEG_LIVING_ALIVE (1<<1)
/// /mob/living core inside `if(handle_regular_status_updates())`.
#define LIFE_SEG_LIVING_STATUS (1<<2)
/// Human tail inside `if(!stasis) if(stat != DEAD)`.
#define LIFE_SEG_HUMAN_LIVE (1<<3)
/// Human tail inside `if(!stasis) else if(stat == DEAD)`.
#define LIFE_SEG_HUMAN_DEAD (1<<4)
/// Simple mob core after `if(stat >= DEAD) return FALSE`.
#define LIFE_SEG_SIMPLE (1<<5)

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

// --- Hibernation (doc/rewrite/life_on_om.md §5) ----------------------------------------------
/// Default for GLOB.mob_hibernation_enabled: a mob whose systems are all asleep leaves the life
/// ring (om_sleep) until a change wakes it. On for every mob, players included. The GLOB var is the
/// runtime switch (benchmarks and admins flip it).
#define MOB_HIBERNATION_ENABLED TRUE
/// Default for GLOB.mob_hibernation_trace: log every hibernate and wake transition
/// (MOB_HIBERNATE lines). Off by default because it is one line per transition.
#define MOB_HIBERNATION_TRACE FALSE
/// How often SSmobs audits sleeping mobs for a missed wake.
#define MOB_HIBERNATION_AUDIT_INTERVAL (30 SECONDS)
/// Hibernating mobs checked per audit (round robin).
#define MOB_HIBERNATION_AUDIT_SAMPLE 400
/// Awake mobs with sleeping systems checked per audit (round robin).
#define MOB_HIBERNATION_AUDIT_AWAKE_SAMPLE 100
/// Segments a dead mob never runs (the alive gate, the status system and the simple and
/// human vitals gates block them), so the audit doesn't expect their systems to be idle.
#define LIFE_SEGS_BLOCKED_WHEN_DEAD (LIFE_SEG_LIVING_ALIVE | LIFE_SEG_LIVING_STATUS | LIFE_SEG_HUMAN_LIVE | LIFE_SEG_SIMPLE)

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
/// Observer upkeep (ghosts, AI eyes, blob overmind) runs this often.
#define OBSERVER_UPKEEP_INTERVAL (LIFE_CYCLE)
