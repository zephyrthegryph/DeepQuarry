// State, change and reactions (doc/rewrite/dx_conventions.md "Reactions"; runtime in code/datums/reactions/).
//
// One vocabulary for "something happened": a var changed (publish_change), an occurrence was announced
// (PUBLISH a /datum/notice), an operation is about to commit or did (before_op / after_op), a read crossed
// a band (on_cross) or a period elapsed (every). A type declares what it reacts to in reactions(); anything
// else subscribes at runtime with observe().

// ---- relation kinds: rel_one()/rel_many(kind = ...) ----
/// A plain reference: cleared when the other end dies, never owning it.
#define RELK_REF 1
/// Both ends name each other (needs back =): one write links both sides.
#define RELK_PAIRED 2
/// The holder owns the value and tears it down with itself.
#define RELK_OWNED 3
// Internal kinds, kept in the holder's relation ledger (rx_ledger_*), never declared by a type.
/// grant(): a capability, bit or permission held for one or more sources.
#define RELK_GRANT 4
/// observe(): the holder (a source) is listened to.
#define RELK_LISTENER 5
/// join(): the holder (a system) has members.
#define RELK_MEMBER 6
/// after() with a key: the pending timer of that key.
#define RELK_TIMER 7
/// The holder holds a thing inside itself (source count = holders that keep it there).
#define RELK_CONTAINED 8

// ---- reaction kinds (/datum/reaction/kind) ----
#define RXN_CHANGE 1
#define RXN_BEFORE_OP 2
#define RXN_AFTER_OP 3
#define RXN_NOTICE 4
#define RXN_CROSS 5
#define RXN_EVERY 6
/// A derived() / generated read folded into reactions(): only feeds READERS.
#define RXN_READ 7

// ---- what a type's reactions() declares for the kernel (generated: code/_generated/reads.dm, rx_boot_types()) ----
/// The type declares every().
#define RXB_EVERY (1<<0)
/// The type declares on_cross().
#define RXB_CROSS (1<<1)
/// The type declares on_notice().
#define RXB_NOTICE (1<<2)
/// The source a holder joins its every() work under (join(key, holder, RX_ENROL_SOURCE)).
#define RX_ENROL_SOURCE "rx_enrol"
/// Deciseconds an urgent crossing may wait for the kernel's U phase before it counts as a breach.
#define RX_URGENT_DEADLINE 2

/// Deepest chain of notices published from inside a delivery before the rest is dropped (a loop).
#define RX_NOTICE_LIMIT 500

// ---- guard keys: before_op(GUARD_X, handler) / guard(E, GUARD_X, ...) (code/datums/reactions/guard.dm) ----
// "May this proceed?" for what is not an operation; they replace the om before/* veto events. A real operation
// (attackby, attack_self, attack_hand, tool use, alt-click) takes before_op on its op key once it is an op; until
// then its legacy entry point asks the guard of the same name.
/// The movable is about to move (before/movable_pre_move, movable_attempted_move vetoes).
#define GUARD_MOVE "guard:move"
/// The movable is about to change z-level (before/movable_z_changed).
#define GUARD_Z_CHANGE "guard:z_change"
/// The atom is about to be irradiated (before/in_range_of_irradiation, living_irradiate_effect).
#define GUARD_IRRADIATE "guard:irradiate"
/// The mob is about to be injured (before/living_injure).
#define GUARD_INJURE "guard:injure"
/// A body status is about to apply (before/living_body_status).
#define GUARD_BODY_STATUS "guard:body_status"
/// A thrown movable is about to hit the mob (before/hit_by_thrown): actor = the thrower, item = what was thrown.
#define GUARD_THROWN_HIT "guard:thrown_hit"
/// A movable is about to cross into the holder's turf (before/cross): actor = the crosser.
#define GUARD_CROSS "guard:cross"
/// The mob is about to land on a turf after a fall (before/falling_down): actor = the mob under it, data = the turf.
#define GUARD_FALL "guard:fall"
/// Somebody stumbles into the mob (before/stumbled_into): actor = the one stumbling.
#define GUARD_STUMBLED_INTO "guard:stumbled_into"
/// An item is used on the holder (before/attackby): actor = the user, item = the item.
#define GUARD_ATTACKBY "guard:attackby"
/// The item is used in hand (before/attack_self): actor = the user.
#define GUARD_ATTACK_SELF "guard:attack_self"
/// The holder is touched with an empty hand (before/attack_hand): actor = the user.
#define GUARD_ATTACK_HAND "guard:attack_hand"
/// A tool is used on the holder (before/atom_tool_act): actor = the user, item = the tool.
#define GUARD_TOOL_ACT "guard:tool_act"
/// The holder is alt-clicked (before/click_alt): actor = the user.
#define GUARD_CLICK_ALT "guard:click_alt"


/// Passes rx_drain() runs when change handlers keep changing state, before it reports a loop.
#define RX_DRAIN_PASSES 20

/// TRUE when someone reads `KEY` of `E` (a static reaction of its type, a generated or derived() read, or an
/// observe()). TRACKED setters, timed_set and ownership writes publish only when this holds.
#define READERS(E, KEY) rx_readers(E, KEY)
/// Publishes the change key `KEY` of `E` when someone reads it (READERS): for a fact that is not one tracked var (a
/// mob's equipment, its body re-deriving). A tracked var publishes itself through its setter.
#define PUBLISH_CHANGE(E, KEY) if(READERS(E, KEY)) { publish_change(E, KEY) }

/// WANTS(E, TYPE) and PUBLISH(E, token, ...) are the engine's (code/__defines/engine/actions.dm); the legacy PUBLISH is PUBLISH_LEGACY.
