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
/// Part of the Maintainable behaviour (panel, anchor, deconstruct, repair).
#define INTERACTION_TAG_MAINTENANCE "maintenance"

/// The keybinding id of a category key.
#define INTERACTION_CATEGORY_BINDING(category) "category_[category]"
/// The keybinding id of the Menu key.
#define INTERACTION_MENU_BINDING "interaction_menu"
