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
#define LORD_COMMAND_RANGE 8            // only pull pack members within this many tiles of the prey; farther
                                        // members aren't teleport-aggroed across the layer when one spots you

// Pack roles the lord hands out while focused, so the pack pincers a target instead of
// clumping on one side. ANCHORs press head-on and hold aggro; FLANKERs take an assigned
// slot around the target and close from the sides/rear; HARRIERs (ranged) keep their
// distance and kite. Read by approach_threat via brain.pack_role / brain.flank_dir.
#define DQ_ROLE_NONE    0
#define DQ_ROLE_ANCHOR  1
#define DQ_ROLE_FLANKER 2
#define DQ_ROLE_HARRIER 3

// Stalker — an ambush predator that keeps its distance and circles, only committing to the
// kill when the prey is weakened or isolated. See code/modules/combat_ai/behaviors/stalker.dm.
#define DQ_STALK_RANGE_MIN    3   // closer than this while stalking → give ground
#define DQ_STALK_RANGE_MAX    5   // farther than this while stalking → close to the band
#define DQ_STALK_COMMIT_HP    0.5 // commit when the prey is at/below this fraction of max HP
#define DQ_STALK_LONELY_RANGE 5   // no ally within this of the prey → it's alone, commit

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

// ---------------------------------------------------------------------------
// Predation — the staged grapple→devour sequence a vore-capable predator runs on
// edible prey. Each stage is a readable beat the prey can answer (dodge the
// tackle, struggle out of the pin, or beat the predator off with a combo). See
// code/modules/combat_ai/behaviors/predation.dm.
// ---------------------------------------------------------------------------
#define DQ_PREDATION_TACKLE    1  // telegraphed lunge that knocks the prey down
#define DQ_PREDATION_PIN       2  // holding the prey down; they can struggle free
#define DQ_PREDATION_REINFORCE 3  // grip tightened — much harder to break
#define DQ_PREDATION_DEVOUR    4  // committed; the prey is swallowed
// The pin is a real /obj/item/grab (AGGRESSIVE), upgraded to a neck-lock (NECK) at
// REINFORCE — escape is the standard grab Resist, hardest once reinforced.
// How long the predator holds each stage before escalating (deciseconds).
#define DQ_PREDATION_PIN_HOLD       (2 SECONDS)
#define DQ_PREDATION_REINFORCE_HOLD (1.5 SECONDS)
// Cooldown after a predation attempt ends (success, escape, or whiff).
#define DQ_PREDATION_COOLDOWN (12 SECONDS)
// The grapple re-pins the prey and advances stages on this pulse (faster than the
// weakened status decays, so a held prey stays prone the whole time).
#define DQ_PREDATION_PULSE 3
// A predator only goes for the grab once the prey is gassed: at/below this fraction of
// its max stamina, or freshly collapsed from exhaustion. Players bleed stamina blocking,
// swinging, and running, so this turns predation into a finisher you set up by grinding
// them down first. NPCs don't tire (they sit at max), so they're not grappled this way.
#define DQ_PREDATION_STAMINA_FRAC 0.25

// ---------------------------------------------------------------------------
// Combo pressure — consecutive hits the prey lands on a mob in a short window.
// Drives the "dodge after being comboed" reaction and makes a grappling predator
// bail when it's being beaten off.
// ---------------------------------------------------------------------------
#define DQ_COMBO_WINDOW          (2 SECONDS) // hits within this of each other chain
#define DQ_COMBO_DODGE_THRESHOLD 3           // a chain this long forces the next dodge
#define DQ_COMBO_GRAPPLE_BREAK   3           // a chain this long breaks an active grapple

// ---------------------------------------------------------------------------
// Combat stances — the mob's current "mind-set", swapped from the situation each
// strategic tick. A stance biases behavior scores (press the attack vs. cover up)
// and sets the mob's a_intent, the way a player switches intents mid-fight. See
// /datum/ai_brain/proc/update_stance + apply_stance.
// ---------------------------------------------------------------------------
#define DQ_STANCE_NEUTRAL    0  // not fighting — no bias
#define DQ_STANCE_AGGRESSIVE 1  // healthy + unpressured: commit to offense (HURT/GRAB)
#define DQ_STANCE_DEFENSIVE  2  // pressured (comboed / hurt): dodge, brace, give ground (DISARM)
#define DQ_STANCE_DESPERATE  3  // low HP: all-in or break for it

// Quick log macro; keep parity with the existing ai_log noop philosophy.
// Flip to enable for debugging.
#define dqai_log(M) // pass

// AI movement pacing. An AI step waits max(fast-tick, the mob's own move delay) times this
// multiplier, so the baseline pursuit pace is a clear fraction of a running player's speed —
// the player can open distance and kite a pack instead of being kept in melee. Higher = slower.
#define DQ_AI_MOVE_DELAY_MULT 3

// Extra slowdown while a mob is just INVESTIGATING a noise (no target yet) — a wary creep
// toward the sound, not a charge, so a noise-drawn mob is slow and easy to see coming. Applied
// on top of the base pursuit delay, i.e. investigating is this many times slower than chasing.
#define DQ_AI_INVESTIGATE_SLOW_MULT 3.5

// Master switch for retreat/disengage behaviors (back_off, flee_low_hp, kite_away, hit_and_run,
// pack_retreat). 1 = disabled: mobs hold their ground and keep pressing instead of giving ground,
// kiting, or fleeing. Flip to 0 to restore the disengage kit.
#define DQ_AI_RETREAT_DISABLED 1

// Selection runs continuously: every fast tick re-picks the best eligible behavior so a
// higher-priority-class one (e.g. the predation finisher) can preempt a running lower one the
// instant it qualifies. To keep same-class selection from thrashing between near-ties, the
// currently-active behavior gets this score bonus when it's re-evaluated — it keeps the slot
// unless a rival clearly beats it. Class still dominates (an eligible OVERRIDE always preempts a
// sticky INTERRUPT), so this only smooths within-class churn.
#define DQ_AI_ACTIVE_STICKINESS 1.15

// Helper macro for evaluate() return.
// Returns a one-shot list with named keys; cheaper than constructing repeatedly.
#define DQAI_RESULT(score, target_atom) list("score" = (score), "target" = (target_atom))

// Legacy carry-overs from the deleted ai_holder engine (AI_NORMAL,
// MOVEMENT_*, ATTACK_*, AI_TARGET_*, ai_log) live in code/modules/ai/_defines.dm
// so files included before this modular block can still see them.
