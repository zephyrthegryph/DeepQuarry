// Operations (doc/rewrite/dx_conventions.md, "Operations"): requirements, routes, affordances,
// compartments and actions. Runtime: code/datums/operations/.

// ---- affordances: what a slot lets its holder do (slot_def.provides) ----
/// Hold a thing of any size.
#define AFF_HOLD (1<<0)
/// Manipulate a thing (turn, press, use a tool on it).
#define AFF_MANIPULATE (1<<1)
/// Hold a small thing (a hand slot, a gripper; not a hook or a clamp).
#define AFF_HOLD_SMALL (1<<2)
/// Work an interface (a keyboard, a touchscreen, a lever).
#define AFF_INTERFACE (1<<3)
/// Everything a control needs.
#define AFF_CONTROL (AFF_MANIPULATE | AFF_INTERFACE)
/// Reach out with the mind (the telekinesis affordance, mob/has_telegrip()): the provider of ROUTE_TK. It is no slot.
#define AFF_TELEKINESIS (1<<4)
/// What the telekinesis affordance stands in for over ROUTE_TK: it manipulates and works controls, it holds nothing.
#define AFF_TK_PROVIDES (AFF_MANIPULATE | AFF_INTERFACE | AFF_TELEKINESIS)
/// What a silicon's interface stands in for over ROUTE_INTERFACE: it works controls, it holds nothing.
#define AFF_INTERFACE_PROVIDES (AFF_MANIPULATE | AFF_INTERFACE)

// ---- routes: how an operation reaches its target ----
#define ROUTE_PHYSICAL (1<<0)
#define ROUTE_INTERFACE (1<<1)
#define ROUTE_UI (1<<2)
#define ROUTE_VERB (1<<3)
#define ROUTE_SPEECH (1<<4)
#define ROUTE_MIND (1<<5)
#define ROUTE_AUTHORITY (1<<6)
/// A telekinetic reach at range (the telekinesis adapter's click): the provider is the telekinesis affordance.
#define ROUTE_TK (1<<7)
#define ROUTE_ANY (ROUTE_PHYSICAL | ROUTE_INTERFACE | ROUTE_UI | ROUTE_VERB | ROUTE_SPEECH | ROUTE_MIND | ROUTE_AUTHORITY | ROUTE_TK)

// ---- requirement subjects (req(of =)) ----
#define OP_ACTOR "actor"
#define OP_TARGET "target"
#define OP_HELD "held"
#define OP_PROVIDER "provider"

/// The read key of an atom's cap_state bits (req_set / req_clear publish and read it).
#define OP_KEY_CAP_STATE "cap_state"
#define OP_KEY_CAP_DATA "cap_data"
#define OP_KEY_CAP_EXTRAS "cap_extras"

// ---- compartments ----
/// door = CAP_KEY: the boundary's physical route passes only for an actor with access.
#define CAP_KEY "key"
#define BAY_MAIN "main"
#define BAY_CONTROLS "controls"
#define BAY_INTERIOR "interior"
#define BAY_CARGO "cargo"
#define BAY_ENGINE "engine"

// ---- physical spaces (code/engine/library/spaces.dm) ----
/// A maintenance hatch: what sits behind a cover (a cell bay, a frame's board and wiring). Its door is the cover.
#define SPACE_HATCH "hatch"
/// Behind a maintenance panel: the wires. Its door is the panel.
#define SPACE_PANEL "panel"
/// A cell's own bay inside a hatch (an APC's, which exists only once the electronics are fastened).
#define SPACE_CELL "cell"
/// The inside of a container with a door (a locker).
#define SPACE_INTERIOR "interior"
/// The entry kinds of the space library.
#define ENTRY_SPACE "space"
#define ENTRY_SPACE_SLOT "space_slot"
#define ENTRY_LATCH "latch"
#define ENTRY_PROTRUSION "protrusion"

// ---- op keys of the library's lock and emag ops ----
/// The emag op of a hatch.
#define LEGACY_CAP_EMAG "emag"
/// Toggling a lock with a credential (a held card, worn ID/PDA or a silicon's access): ACT_LOCK.
#define LEGACY_CAP_LOCK "toggle_lock"
/// The key of claw_op(): a shredder tearing at a breakable machine.
#define CAP_CLAW "claw"

// ---- op priorities: higher first among the ops one input reaches (doc/rewrite/operations_and_actions.md §5) ----
/// What a type does when nothing more specific it offers answers (an item's pickup, a mob being hit): the old
/// INTERACT_*_DEFAULT shapes. The same scale as the resolver's INTERACTION_DEFAULT_PRIORITY.
#define OP_PRIORITY_DEFAULT -2000
#define OP_PRIORITY_NORMAL 0
/// A maintenance part worked with a tool (a cover, a panel, wires, a repair): ahead of the holder's own uses of that tool.
#define OP_PRIORITY_PART 10
/// Taking out what sits in an open bay or slot by hand: ahead of the holder's own empty-hand use (the APC's cell over
/// its interface).
#define OP_PRIORITY_TAKE_OUT 30
/// Claws tearing at a machine (claw_op()): ahead of everything else an empty hand does to it.
#define OP_PRIORITY_CLAW 40
/// Subverting the holder (an emag): ahead of anything else the card could be used for.
#define OP_PRIORITY_SUBVERT 50

// ---- actions (action_defs) ----
/// No gesture reaches the op: it is chosen from the Menu, the radial or the command bar by its key or name (the old
/// INTERACT_VERB). Never listed by a bind profile, has no action_def.
#define ACT_NONE "none"
/// The hostile use: a click in a hostile stance (harm, disarm) reaches it before ACT_USE (the bind profile's
/// stance table). Hostile ops declare it.
#define ACT_ATTACK "attack"
#define ACT_USE "use"
#define ACT_DROP_ONTO "drop_onto"
#define ACT_OPEN "open"
#define ACT_CLOSE "close"
#define ACT_TOGGLE "toggle"
#define ACT_LOCK "lock"
#define ACT_UNLOCK "unlock"
#define ACT_INSERT "insert"
#define ACT_EJECT "eject"
#define ACT_PRY "pry"
#define ACT_REPAIR "repair"
#define ACT_DISMANTLE "dismantle"
#define ACT_EXAMINE "examine"
#define ACT_PULL "pull"

// ---- gestures: physical inputs, before they become actions ----
#define GESTURE_CLICK "click"
#define GESTURE_SELF "self_click"
#define GESTURE_ALT "alt_click"
#define GESTURE_CTRL "ctrl_click"
#define GESTURE_SHIFT "shift_click"
#define GESTURE_DRAG "drag"
#define GESTURE_RIGHT "right_click"

// ---- action categories (radial / screentip grouping) ----
#define ACT_CAT_USE "use"
#define ACT_CAT_STATE "state"
#define ACT_CAT_ITEM "item"
#define ACT_CAT_MAINTAIN "maintain"
#define ACT_CAT_INFO "info"
