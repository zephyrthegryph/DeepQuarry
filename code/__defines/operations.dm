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

// ---- routes: how an operation reaches its target ----
#define ROUTE_PHYSICAL (1<<0)
#define ROUTE_INTERFACE (1<<1)
#define ROUTE_UI (1<<2)
#define ROUTE_VERB (1<<3)
#define ROUTE_SPEECH (1<<4)
#define ROUTE_MIND (1<<5)
#define ROUTE_AUTHORITY (1<<6)
#define ROUTE_ANY (ROUTE_PHYSICAL | ROUTE_INTERFACE | ROUTE_UI | ROUTE_VERB | ROUTE_SPEECH | ROUTE_MIND | ROUTE_AUTHORITY)

// ---- operation kinds (cap_op(kind =)); also what cap_require(ops =) can name ----
/// An ordinary use: needs a capable actor.
#define OP_CONTROL "control"
/// Changes what the thing is (dismantle, rewire): needs a capable actor.
#define OP_STRUCTURAL "structural"
/// A last resort anyone alive can try (an emergency release): the actor-state stage only refuses the dead.
#define OP_EMERGENCY "emergency"

// ---- requirement subjects (req(of =)) ----
#define OP_ACTOR "actor"
#define OP_TARGET "target"
#define OP_HELD "held"
#define OP_PROVIDER "provider"

/// The read key of an atom's cap_state bits (req_set / req_clear publish and read it).
#define OP_KEY_CAP_STATE "cap_state"

// ---- compartments ----
/// door = CAP_KEY: the boundary's physical route passes only for an actor with access.
#define CAP_KEY "key"
#define BAY_MAIN "main"
#define BAY_CONTROLS "controls"
#define BAY_INTERIOR "interior"
#define BAY_CARGO "cargo"
#define BAY_ENGINE "engine"

// ---- op_ctx check stages, in the order they run ----
#define OP_STAGE_PROVIDER 1
#define OP_STAGE_ROUTE 2
#define OP_STAGE_ACTOR 3
#define OP_STAGE_TARGET 4
#define OP_STAGE_CAPS 5
#define OP_STAGE_NEEDS 6
#define OP_STAGE_ALL OP_STAGE_NEEDS

// ---- actions (action_defs) ----
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
