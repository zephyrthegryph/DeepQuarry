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

/// use_tool(): the job is a timed action that has started; its on_done runs later.
#define USE_TOOL_PENDING 2
