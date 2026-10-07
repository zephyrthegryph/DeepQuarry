#ifndef DQ_COMBAT_AI_DEFINES_DM
#define DQ_COMBAT_AI_DEFINES_DM

// DeepQuarry combat AI framework — defines.
// All identifiers prefixed with DQ_ or DQAI_ to avoid colliding with upstream.

// ---------------------------------------------------------------------------
// Dispositions — how the brain feels about another mob.
// Numeric so target selectors can compare with > / < / >= and so disposition
// shifts (grudges, healing-bonds) can move along an axis instead of toggling.
// ---------------------------------------------------------------------------
#define DQ_DISPOSITION_NEMESIS   -2  // engage preferentially, ignore weaker targets
#define DQ_DISPOSITION_HOSTILE   -1  // engage normally
#define DQ_DISPOSITION_WARY       0  // threaten or flee, no engage
#define DQ_DISPOSITION_NEUTRAL    1  // ignore unless provoked
#define DQ_DISPOSITION_FRIENDLY   2  // won't attack, may emote
#define DQ_DISPOSITION_ALLY       3  // protect, heal, follow

// Used by the personal-relationship cache.
#define DQ_DISPOSITION_DEFAULT    DQ_DISPOSITION_NEUTRAL

// ---------------------------------------------------------------------------
// Intent bitflags for behavior filtering on player-controlled mobs.
// Behaviors declare which use stances (combat mode, Disarm, Grab) they're eligible for.
// AI mobs ignore these (consider all behaviors).
// ---------------------------------------------------------------------------
#define DQ_INTENT_HURT_FLAG       (1<<0)
#define DQ_INTENT_DISARM_FLAG     (1<<1)
#define DQ_INTENT_GRAB_FLAG       (1<<2)
#define DQ_INTENT_HELP_FLAG       (1<<3)
#define DQ_INTENT_ANY             (DQ_INTENT_HURT_FLAG | DQ_INTENT_DISARM_FLAG | DQ_INTENT_GRAB_FLAG | DQ_INTENT_HELP_FLAG)

// ---------------------------------------------------------------------------
// Behavior priority classes. The brain prefers higher classes regardless of
// raw score — a low-score INTERRUPT beats a high-score NORMAL. Inside a class
// the score chooses.
// ---------------------------------------------------------------------------
#define DQ_BEHAVIOR_PRIORITY_INTERRUPT  4  // can interrupt anything (panic flee, dodge grenade)
#define DQ_BEHAVIOR_PRIORITY_OVERRIDE   3  // overrides normal selection while active (boss windup)
#define DQ_BEHAVIOR_PRIORITY_NORMAL     2  // standard combat decisions
#define DQ_BEHAVIOR_PRIORITY_IDLE       1  // run only when nothing better (wander, idle speak)
#define DQ_BEHAVIOR_PRIORITY_BACKGROUND 0  // run only when nothing else is eligible at all

// ---------------------------------------------------------------------------
// tick() return values.
// ---------------------------------------------------------------------------
#define DQ_BEHAVIOR_CONTINUE   0  // keep running this behavior next tick
#define DQ_BEHAVIOR_DONE       1  // finished cleanly, allow re-selection
#define DQ_BEHAVIOR_INTERRUPTED 2 // stopped externally; treat like DONE for the brain
#define DQ_BEHAVIOR_FAILED     3  // couldn't run; brain re-picks and applies short cooldown

// stop() reasons.
#define DQ_BEHAVIOR_STOP_COMPLETED   1
#define DQ_BEHAVIOR_STOP_INTERRUPTED 2
#define DQ_BEHAVIOR_STOP_FAILED      3
#define DQ_BEHAVIOR_STOP_QDEL        4

// ---------------------------------------------------------------------------
// Target kinds — what an evaluate() result's target field is.
// Brain uses this to decide whether to face / follow / pathfind.
// ---------------------------------------------------------------------------
#define DQ_TARGET_NONE  0
#define DQ_TARGET_MOB   1
#define DQ_TARGET_TURF  2
#define DQ_TARGET_ITEM  3
#define DQ_TARGET_SELF  4

// ---------------------------------------------------------------------------
// Behavior trigger keys. The brain dispatches these to behaviors that list them
// in eval_triggers, so they re-evaluate only when relevant. The brain also emits
// the matching OM events on the mob (/datum/om/event/dqai_damage_taken,
// dqai_target_lost, dqai_target_changed, dqai_ally_distress) for other listeners.
// ---------------------------------------------------------------------------
#define DQAI_TRIGGER_DAMAGE_TAKEN     "dqai_damage_taken"      // (amount, injury_kind, source_mob)
#define DQAI_TRIGGER_TARGET_LOST      "dqai_target_lost"       // (old_target)
#define DQAI_TRIGGER_TARGET_CHANGED   "dqai_target_changed"    // (new_target, old_target)
#define DQAI_TRIGGER_ALLY_DISTRESS    "dqai_ally_distress"     // (ally, attacker)
#define DQAI_TRIGGER_LOW_HEALTH       "dqai_low_health"        // (hp_fraction)

// ---------------------------------------------------------------------------
// Misc helpers / tuning.
// ---------------------------------------------------------------------------
// How long personal relationship entries last by default if duration is unset.
#define DQ_PERSONAL_DEFAULT_DURATION (30 SECONDS)
// At or below this vitality() fraction (0..1 wellness), DQAI_TRIGGER_LOW_HEALTH is dispatched.
#define DQ_LOW_HP_THRESHOLD 0.4
// World model perception refresh interval (in slow ticks). 1 = every slow tick.
#define DQ_PERCEPTION_REFRESH_RATE 1
// Maximum entries kept in the world model's recent_damage_events list.
#define DQ_DAMAGE_HISTORY_CAP 8
// Default behavior cooldown after FAILED.
#define DQ_BEHAVIOR_FAIL_COOLDOWN (1 SECOND)
// Grace period (deciseconds) before the brain drops a target that left view().
// Mirrors legacy ai_holder.lose_target_timeout (5 SECONDS).
#define DQ_LOSE_THREAT_TIMEOUT (5 SECONDS)

// Quick log macro; keep parity with the existing ai_log noop philosophy.
// Flip to enable for debugging.
#define dqai_log(M) // pass

// Helper macro for evaluate() return.
// Returns a one-shot list with named keys; cheaper than constructing repeatedly.
#define DQAI_RESULT(score, target_atom) list("score" = (score), "target" = (target_atom))

// Legacy carry-overs from the deleted ai_holder engine (AI_NORMAL,
// MOVEMENT_*, ATTACK_*, AI_TARGET_*, ai_log) live in code/modules/ai/_defines.dm
// so files included before this modular block can still see them.
// end of the include guard

// Action loop cadence (brain/scheduling.dm, ai_packs.md B2).
/// The action loop's default interval (and the rate an active behaviour ticks at unless it sets tick_interval).
#define DQ_ACTION_TICK (0.25 SECONDS)
/// IDLE and BACKGROUND behaviours below RELEVANCE_VISIBLE tick this many times slower.
#define DQ_IDLE_STRETCH 3
/// The wind-up of a charge (the "mob_attacks.charge" op) before the dash.
#define MOB_CHARGE_WINDUP (1.2 SECONDS)
/// The action loop's interval while the brain has no target and no tactic running: the idle-selection cadence.
#define DQ_CALM_TICK (2 SECONDS)
/// While engaged the brain re-selects at least this often even without an event.
#define DQ_ENGAGED_RECHECK (1 SECOND)

// ---------------------------------------------------------------------------
// Packs (pack/, doc/rewrite/ai_packs.md B3).
// ---------------------------------------------------------------------------
/// Targeting doctrine: members spread over the pack's hostiles, at most `spread_cap` members on one.
#define PACK_SPREAD "spread"
/// Targeting doctrine: members follow the leader's target when they know it.
#define PACK_FOCUS "focus"
/// Seconds a calm pack waits between perceptions (event-only: nothing triggers them without chunk activity).
#define PACK_PERCEIVE_CALM (5 SECONDS)
/// A pack that knows a hostile (alert) or fights (engaged) perceives this often.
#define PACK_PERCEIVE_ACTIVE (1 SECOND)
/// An engaged pack with nobody on screen perceives this often.
#define PACK_PERCEIVE_OFFSCREEN (2 SECONDS)
/// A pack's upkeep (splits, merges, chunk re-cover).
#define PACK_UPKEEP_INTERVAL (5 SECONDS)

// ---------------------------------------------------------------------------
// Standings providers (standings/standings.dm, doc/rewrite/ai_packs.md B5): the priority of each provider's rows.
// ---------------------------------------------------------------------------
#define AI_STANDING_FACTION 0
#define AI_STANDING_PACK 50
#define AI_STANDING_SERVES 55
#define AI_STANDING_GRUDGE 60
#define AI_STANDING_EFFECT 80
#define AI_STANDING_ADMIN 100
/// How long a grudge (a hit, a taunt, a call for help) lasts.
#define DQ_GRUDGE_DURATION (5 MINUTES)

// Columns of a pack sighting (pack.sightings[REF(mob)]).
#define SIGHT_SPOTTER 1
#define SIGHT_FIRST_AT 2
#define SIGHT_SEEN 3

#endif
