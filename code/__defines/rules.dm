// Rules (doc/rewrite/rules.md §4). Code: code/datums/rules/.
//
// A rule is a condition (a predicate over the object, PRED_TARGET) plus an
// effect. Rules are declared as /datum/rule subtypes naming the types they
// apply to; they are shared singletons, and an instance costs nothing until it
// is subscribed when it materializes.

// ---- Effect kinds ----
/// Work on the object's state: set saved vars, swap the type, remove it.
#define RULE_EFFECT_DATA 1
/// A proc on the real object: `effect_proc`, called with (rule).
#define RULE_EFFECT_BEHAVIOUR 2

// ---- Data transform ops (lists; applied in order) ----
#define RULE_OP_SET "set"
#define RULE_OP_SWAP "swap"
#define RULE_OP_REMOVE "remove"
/// Set saved var `var_name` to `value` (a property override when a property reads that var).
#define RULE_SET_STATE(var_name, value) list(RULE_OP_SET, var_name, value)
/// Replace the object with a new `path` at the same place; its contents drop out.
#define RULE_SWAP_TYPE(path) list(RULE_OP_SWAP, path)
/// Delete the object.
#define RULE_REMOVE list(RULE_OP_REMOVE)

// ---- Trigger kinds, compiled from the condition's clauses ----
/// A reactor Threshold watch on a channel-backed property.
#define RULE_TRIGGER_THRESHOLD "Threshold"
/// A reactor Band watch on a channel-backed property.
#define RULE_TRIGGER_BAND "Band"
/// Change watches on both channel-backed sides of a comparison.
#define RULE_TRIGGER_DIFFERENCE "Difference"
/// A DM-owned key (REACT_ON_KEY): re-evaluate when the key is published.
#define RULE_TRIGGER_KEY "Key"

// ---- Legacy paths a rule replaces. The old code checks these and stands down. ----
/// take_damage()/repair_damage()'s integrity_failure crossing -> atom_break()/atom_fix().
#define RULE_REPLACES_INTEGRITY_BREAK (1<<1)

// ---- DM-owned keys (reactor.md §4). Kinds past S1's own (1-3). ----
/// An atom's integrity changed. Id: the atom's reactor id.
#define RULE_KEY_INTEGRITY 16

/// hold_for bookkeeping: the rule fired during the current spell. Rate model ids can be 0.
#define RULE_HOLD_SPENT "spent"

/// The rules that apply to `path`: a shared list, or null.
#define RULES_FOR_TYPE(path) dq_rules_for_type(path)
/// RULE_REPLACES_* flags of the rules on `path`.
#define RULES_REPLACE(path, flag) (dq_rules_replace_flags(path) & (flag))

// ---- Reactor adapter (code/datums/rules/reactor_adapter.dm) ----
// Wake reasons passed to rule_wake(): SSreactor's reason classes.
#define DQ_RX_REASON_CONDITION REACT_REASON_CONDITION
#define DQ_RX_REASON_TIMER REACT_REASON_TIMER
#define DQ_RX_REASON_KEY REACT_REASON_KEY
#define DQ_RX_REASON_RATE REACT_REASON_RATE

/// Channel ids on a heat node.
#define DQ_RX_CH_TEMPERATURE 1
