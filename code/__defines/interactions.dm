// Clicks into the op engine and the input layer's shared defines (doc/rewrite/interactions.md §5-8).
// Code: code/datums/interactions/clicks.dm.

// What trying an action through the op engine did (try_interaction()).
/// An op ran (or started; either way the input was used).
#define INTERACTION_TRY_RAN "ran"
/// The op the click reached refused; the actor was told why.
#define INTERACTION_TRY_BLOCKED "blocked"

/// The keybinding id of a category key.
#define INTERACTION_CATEGORY_BINDING(category) "category_[category]"
/// The keybinding id of the Menu key.
#define INTERACTION_MENU_BINDING "interaction_menu"

// What an atom's plain Use does for actors without hands (I3, `/atom/var/silicon_use`).
// These replace the attack_ai/attack_robot overrides that only forwarded; the
// adapters read them through the base attack_ai and attack_robot procs, so a
// type's own override still wins. tools/ci/actor_forwarding_lint.py enforces it.
/// The AI's Use (and a cyborg's remote interfacing) is the hand's Use: attack_hand.
#define SILICON_USE_HAND (1<<0)
/// The AI's Use opens the atom's tgui interface.
#define SILICON_USE_UI (1<<1)
/// A cyborg's empty-gripper Use is the hand's Use, at any range.
#define ROBOT_USE_HAND (1<<2)
/// A cyborg's empty-gripper Use is the hand's Use when adjacent, and does nothing otherwise.
#define ROBOT_USE_HAND_ADJACENT (1<<3)

/// use_tool(): the job is a timed action that has started; its on_done runs later.
#define USE_TOOL_PENDING 2
