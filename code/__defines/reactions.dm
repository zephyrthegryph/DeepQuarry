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

/// Deepest chain of notices published from inside a delivery before the rest is dropped (a loop).
#define RX_NOTICE_LIMIT 500
/// Passes rx_drain() runs when change handlers keep changing state, before it reports a loop.
#define RX_DRAIN_PASSES 20

/// TRUE when someone reads `KEY` of `E` (a static reaction of its type, a generated or derived() read, or an
/// observe()). TRACKED setters, timed_set and ownership writes publish only when this holds.
#define READERS(E, KEY) rx_readers(E, KEY)
/// TRUE when someone wants notices of `TYPE` from `E`.
#define WANTS(E, TYPE) rx_wants_notice(E, TYPE)
/// Announces an occurrence: `PUBLISH(src, /datum/notice/door_opened, user)`. Nothing is allocated unless
/// something listens. Occurrences are ordered and never coalesced.
#define PUBLISH(E, TYPE, ARGS...) if(WANTS(E, TYPE)) { publish(E, take_notice(TYPE, ARGS)) }
