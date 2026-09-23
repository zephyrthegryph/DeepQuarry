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

// Legacy input entries (I7). A converted handler's interactions keep the entry
// point the old proc had, so every caller of that proc still reaches them, in
// the same order: the most specific type first, then its parents, as an
// override chain did. Resolver-native interactions have no entry.
/// Used with an item: /atom/proc/attackby.
#define INTERACTION_ENTRY_ITEM "item"
/// Touched with an empty hand (or a silicon's Use through silicon_use): /atom/proc/attack_hand.
#define INTERACTION_ENTRY_HAND "hand"
/// The held item used on itself: /obj/item/proc/attack_self.
#define INTERACTION_ENTRY_SELF "self"
/// Alt-click: /atom/proc/click_alt.
#define INTERACTION_ENTRY_ALT "alt"
/// Something dragged onto the target (held is the dragged atom): /atom/proc/MouseDrop_T.
#define INTERACTION_ENTRY_DRAG "drag"

/// run_interaction_entry(): the entry's gate (hand_gate()) stopped the input before any interaction.
#define INTERACTION_GATE_STOPPED "gate_stopped"

/// Requirement: in reach. Adjacent, or a silicon the target lets use it remotely (silicon_use),
/// or already dispatched by the legacy entry (which decided reach itself: telekinesis, the AI).
#define REQ_INTERACTION_REACH REQ_PROC(/proc/dq_interaction_reach, "too far away")
