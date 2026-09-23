// Combat mode (doc/rewrite/interactions.md §12, roadmap I6).
// Code: code/modules/mob/combat_mode.dm.
//
// Intents are gone. What a Use does comes from two things:
// * `combat_mode`, a mob action the player toggles (keybind or HUD button);
// * `attack_variant`, the Disarm or Grab interaction the player chose for one
//   Use (the Disarm and Grab keys, or the Menu). AI brains may hold a variant
//   as their chosen special attack.
//
// The I_* values name the four outcomes a Use can have. use_stance() returns
// one of them; the IS_* macros below test for one.

/// The Disarm variant of a Use.
#define ATTACK_VARIANT_DISARM "disarm"
/// The Grab variant of a Use.
#define ATTACK_VARIANT_GRAB "grab"

/// A Use with combat mode off and no variant: help and neutral outcomes.
#define IS_HELPING(M) (!(M).combat_mode && !(M).attack_variant)
/// A Use with combat mode on and no variant: the harm outcome.
#define IS_HARMING(M) ((M).combat_mode && !(M).attack_variant)
/// The Disarm variant.
#define IS_DISARMING(M) ((M).attack_variant == ATTACK_VARIANT_DISARM)
/// The Grab variant.
#define IS_GRABBING(M) ((M).attack_variant == ATTACK_VARIANT_GRAB)

/// Interaction requirement: the actor has combat mode on.
#define REQ_COMBAT_MODE REQ_ON(PRED_ACTOR, /mob/proc/pred_combat_mode, "combat mode is off")
/// Interaction requirement: the actor has combat mode off.
#define REQ_NO_COMBAT_MODE REQ_ON(PRED_ACTOR, /mob/proc/pred_no_combat_mode, "combat mode is on")

/// How far combat mode moves a hostile interaction up (on) or down (off) the resolver's order.
#define COMBAT_MODE_PRIORITY_SHIFT 1000

/// The keybinding id of the Disarm key.
#define COMBAT_DISARM_BINDING "combat_disarm"
/// The keybinding id of the Grab key.
#define COMBAT_GRAB_BINDING "combat_grab"

/// From /mob/proc/set_combat_mode(): (new_mode)
#define COMSIG_MOB_COMBAT_MODE_CHANGED "mob_combat_mode_changed"
