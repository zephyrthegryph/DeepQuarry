// Input layer (doc/rewrite/interactions.md §2-4).
// Physical inputs (keys, mouse buttons plus modifiers) map to these abstract
// actions. Only the input router reads click modifiers; everything after it
// works in actions.

// Target actions: run through the target's interactions.
/// The default interaction. Left click.
#define INPUT_ACTION_USE "use"
/// The secondary interaction. Alt-click, and right-click when bound.
#define INPUT_ACTION_ALTERNATE "alternate"
/// Alt plus right-click: the secondary alternate interaction.
#define INPUT_ACTION_ALTERNATE_SECONDARY "alternate_secondary"
/// List every interaction, with availability and reasons: the interaction menu (code/datums/interactions/menu.dm).
#define INPUT_ACTION_MENU "menu"
/// Examine. Shift-click.
#define INPUT_ACTION_INSPECT "inspect"
/// Move or transfer one thing onto another. Drag and drop.
#define INPUT_ACTION_DRAG "drag"
/// Use the held item on itself. Z, or clicking the held item.
#define INPUT_ACTION_SELF_USE "self_use"
/// Ctrl+shift click: the quick interaction (AI door bolts and the like).
#define INPUT_ACTION_QUICK "quick"
/// Alt+shift click: open the target's inventory (loot) panel.
#define INPUT_ACTION_LOOT "loot"

// Mob actions: not object interactions.
/// Ctrl-click.
#define INPUT_ACTION_PULL "pull"
/// Shift+middle click.
#define INPUT_ACTION_POINT "point"
/// Middle click. Borgs cycle modules, the AI toggles bolt lights.
#define INPUT_ACTION_SWAP_HANDS "swap_hands"
/// Ctrl+middle click: admins tag the datum, everyone else pulls.
#define INPUT_ACTION_TAG "tag"
#define INPUT_ACTION_THROW "throw"
#define INPUT_ACTION_RESIST "resist"
#define INPUT_ACTION_REST "rest"
#define INPUT_ACTION_COMBAT_MODE "combat_mode"
#define INPUT_ACTION_MOVE "move"

/// The click is swallowed (the extra mouse buttons).
#define INPUT_ACTION_NONE "none"
/// Click-table marker: use whatever the player bound right-click to.
#define INPUT_ACTION_RIGHT_CLICK_BINDING "right_click_binding"

// Interaction categories that can be bound to keys. A category key runs the best
// interaction in that category on the hovered atom, or on the tile in front of
// the player (try_interaction_category()).
#define INTERACTION_CAT_TOGGLE "toggle"
#define INTERACTION_CAT_OPEN "open"
#define INTERACTION_CAT_EJECT "eject"
#define INTERACTION_CAT_INSERT "insert"
#define INTERACTION_CAT_LOCK "lock"
#define INTERACTION_CAT_CONFIGURE "configure"
#define INTERACTION_CAT_REPAIR "repair"
#define INTERACTION_CAT_MAINTAIN "maintain"
#define INTERACTION_CAT_ATTACK "attack"

#define INTERACTION_CATEGORIES list(INTERACTION_CAT_TOGGLE, INTERACTION_CAT_OPEN, INTERACTION_CAT_EJECT, INTERACTION_CAT_INSERT, INTERACTION_CAT_LOCK, INTERACTION_CAT_CONFIGURE, INTERACTION_CAT_REPAIR, INTERACTION_CAT_MAINTAIN, INTERACTION_CAT_ATTACK)

/// What right-click can be bound to: the interaction menu, or the Alternate action.
#define RIGHT_CLICK_BINDINGS list(INPUT_ACTION_MENU, INPUT_ACTION_ALTERNATE)

// Keybinding profiles: which default set a mob gets.
#define KEYBIND_PROFILE_DEFAULT "default"
#define KEYBIND_PROFILE_ROBOT "robot"
#define KEYBIND_PROFILES list(KEYBIND_PROFILE_DEFAULT, KEYBIND_PROFILE_ROBOT)

// Keybinding categories, for grouping in the editor.
#define KEYBIND_CAT_MOVEMENT "Movement"
#define KEYBIND_CAT_MOB "Mob"
#define KEYBIND_CAT_COMMS "Communication"
#define KEYBIND_CAT_COMBAT "Combat"
#define KEYBIND_CAT_TARGETING "Targeting"
#define KEYBIND_CAT_ITEMS "Items"
#define KEYBIND_CAT_ROBOT "Robot"
#define KEYBIND_CAT_INTERACTION "Interaction"
#define KEYBIND_CAT_CLIENT "Client"
#define KEYBIND_CAT_ADMIN "Admin"

/// The one skin macro set every client uses; bindings are added to it with winset.
#define KEYBIND_MACRO_SET "default"
/// Prefix of the macro elements created per client.
#define KEYBIND_MACRO_PREFIX "dqkb"
/// Longest key name a player can bind (e.g. "CTRL+SHIFT+NUMPAD8+REP").
#define KEYBIND_MAX_KEY_LENGTH 32
/// Most keys one binding can hold.
#define KEYBIND_MAX_KEYS 4

/// Minimum time between two hover updates for one client.
#define INPUT_HOVER_THROTTLE (0.2 SECONDS)

/// The singleton capability adapter of a type, e.g. INPUT_ADAPTER(telekinesis).
#define INPUT_ADAPTER(adapter_name) (GLOB.input_adapters[/datum/input_adapter/##adapter_name])
