// Combat mode (doc/rewrite/interactions.md §12, roadmap I6).
// Code: code/modules/mob/combat_mode.dm.
//
// Intents are gone. What a Use does comes from two things:
// * `combat_mode`, a mob action the player toggles (keybind or HUD button);
// * `attack_variant`, the Disarm or Grab interaction the player chose for one
//   Use (the Disarm and Grab keys, or the Menu). AI brains may hold a variant
//   as their chosen special attack.
//
// The I_* values name the four stances a Use can have (help, disarm, grab, harm).
// Ops declare one (stance()): the engine offers a stance-declared op only when
// it matches the actor's input, so the op that runs carries the intent. Code an
// op calls into takes a `stance` argument. Only the input layer reads the mob's state, through
// /mob/proc/input_stance() (tools/ci/stance_examine_lint.py keeps it there).

/// The Disarm variant of a Use.
#define ATTACK_VARIANT_DISARM "disarm"
/// The Grab variant of a Use.
#define ATTACK_VARIANT_GRAB "grab"

/// Whether a stance is hostile (harm, disarm).
#define STANCE_IS_HOSTILE(stance) ((stance) == I_HURT || (stance) == I_DISARM)

/// How far combat mode moves a hostile interaction up (on) or down (off) the resolver's order.
#define COMBAT_MODE_PRIORITY_SHIFT 1000

/// The keybinding id of the Disarm key.
#define COMBAT_DISARM_BINDING "combat_disarm"
/// The keybinding id of the Grab key.
#define COMBAT_GRAB_BINDING "combat_grab"

/// From /mob/proc/set_combat_mode(): (new_mode)
