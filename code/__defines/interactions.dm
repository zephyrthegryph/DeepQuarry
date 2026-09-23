// Interaction framework (doc/rewrite/interactions.md §5-8).
// Code: code/datums/interactions/.

/// The shared singleton of an interaction type, e.g. INTERACTION(/datum/interaction/machine_panel).
#define INTERACTION(path) (GLOB.interactions_by_type[path])
/// The shared singleton with this id.
#define INTERACTION_BY_ID(id) (interaction_by_id(id))

// What trying an action through the resolver did.
/// An interaction ran (or started and was interrupted; either way the input was used).
#define INTERACTION_TRY_RAN "ran"
/// Several interactions tied for the action, so the Menu opened.
#define INTERACTION_TRY_MENU "menu"
/// The interaction the player meant is blocked; they were told why.
#define INTERACTION_TRY_BLOCKED "blocked"

// Interaction tags, for filtering and actor adapters.
/// Can be done remotely (the AI, a cyborg interfacing without an item). Used by I3.
#define INTERACTION_TAG_REMOTE "remote"
/// Hostile: attacks and sabotage. Used by combat mode (I6).
#define INTERACTION_TAG_HOSTILE "hostile"
/// Observer-only: offered to ghosts and to no one else (I3).
#define INTERACTION_TAG_OBSERVER "observer"
/// Part of the Maintainable behaviour (panel, anchor, deconstruct, repair).
#define INTERACTION_TAG_MAINTENANCE "maintenance"

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
