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
// Behaviors declare which a_intents they're eligible for.
// AI mobs ignore these (consider all behaviors).
// ---------------------------------------------------------------------------
#define DQ_INTENT_HURT_FLAG       (1<<0)
#define DQ_INTENT_DISARM_FLAG     (1<<1)
#define DQ_INTENT_GRAB_FLAG       (1<<2)
#define DQ_INTENT_HELP_FLAG       (1<<3)
#define DQ_INTENT_ANY             (DQ_INTENT_HURT_FLAG | DQ_INTENT_DISARM_FLAG | DQ_INTENT_GRAB_FLAG | DQ_INTENT_HELP_FLAG)

// ---------------------------------------------------------------------------
// AI Lords — per-pack coordinator that extends the brain framework.
// A lord tracks the pack's shared threats/goals on its own faster tick and
// pushes orders down to member brains. See code/modules/combat_ai/lord/.
// ---------------------------------------------------------------------------
#define LORD_TICK_INTERVAL (1 SECONDS)  // pack coordination cadence; faster than the 2s member strategic tick
#define LORD_FOCUS_GRACE   (6 SECONDS)  // pursue a lost player's last-known tile this long before standing down
#define LORD_DETECT_RANGE  9            // the lord's own prey-scan radius around the pack centroid

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
// Signals emitted on the mob by the brain framework. Behaviors can subscribe
// to these via their eval_triggers list to re-evaluate only when relevant.
// ---------------------------------------------------------------------------
#define COMSIG_DQAI_DAMAGE_TAKEN     "dqai_damage_taken"      // (amount, damagetype, source_mob)
#define COMSIG_DQAI_TARGET_LOST      "dqai_target_lost"       // (old_target)
#define COMSIG_DQAI_TARGET_CHANGED   "dqai_target_changed"    // (new_target, old_target)
#define COMSIG_DQAI_ALLY_DISTRESS    "dqai_ally_distress"     // (ally, attacker)
#define COMSIG_DQAI_BEHAVIORS_DIRTY  "dqai_behaviors_dirty"   // ()
#define COMSIG_DQAI_LOW_HEALTH       "dqai_low_health"        // (hp_fraction)
#define COMSIG_DQAI_ENTERED_VIEW     "dqai_entered_view"      // (mob_seen)
#define COMSIG_DQAI_HEARD_HAZARD     "dqai_heard_hazard"      // (hazard_atom)
#define COMSIG_DQAI_INCOMING_ATTACK  "dqai_incoming_attack"   // (attacker) — a telegraphed swing is winding up on this mob

// ---------------------------------------------------------------------------
// Misc helpers / tuning.
// ---------------------------------------------------------------------------
// How long personal relationship entries last by default if duration is unset.
#define DQ_PERSONAL_DEFAULT_DURATION (30 SECONDS)
// Below this fraction of max HP, COMSIG_DQAI_LOW_HEALTH fires.
#define DQ_LOW_HP_THRESHOLD 0.4
// World model perception refresh interval (in slow ticks). 1 = every slow tick.
#define DQ_PERCEPTION_REFRESH_RATE 1
// Maximum entries kept in the world model's recent_damage_events list.
#define DQ_DAMAGE_HISTORY_CAP 8
// Default behavior cooldown after FAILED.
#define DQ_BEHAVIOR_FAIL_COOLDOWN (1 SECOND)
// How long a mob remembers / pursues a heard noise before giving up.
// (DQ_AI_NOISE_MIN_VOL lives in code/__defines/mobs.dm — it's referenced from
// game/sound.dm, which is compiled well before this modular block.)
#define DQ_NOISE_INVESTIGATE_TTL (8 SECONDS)
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
