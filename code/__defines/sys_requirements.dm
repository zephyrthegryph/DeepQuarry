// Requirement clauses over the target's state (doc/rewrite/systems.md section 6).
// Runtime: code/datums/sys/requirements.dm. Lint: tools/ci/sys_rules/requirements.py.
//
// A guard at the head of an interaction effect ("if it's locked, tell them no and return") is
// declared on the interaction instead, so the resolver, the Menu and examine all know why the
// interaction is unavailable, and the effect proc only does the work:
//
//   CAPABILITIES(/obj/machinery/thing,
//   	op("toggle", hand(), label("Toggle"), needs(req_is(STAT_OPERABLE), ...), then(PROC_REF(toggle))),
//   )
//
// Every clause reads the interaction's target (the atom the effect proc runs on). The reason is
// optional; when omitted it is generated from the field name and the value that failed:
//
//   REQ_FIELD("operable")           fails "it isn't operable"; a null value: "it has no <field>"
//   REQ_FIELD_NOT("locked")         fails "it's locked"; an atom value: "it already has <thing>"
//   REQ_FIELD_EQ("state", 2)        fails "its state must be 2"
//
// A field is a var of the target or a derived field (a proc of that name taking no arguments,
// e.g. OM_DERIVE_FIELD's operable()). Underscores read as spaces in generated reasons.
// Anything that isn't a plain field is REQ_TARGET_STATE(PROC_REF(can_x)) (predicates.dm): the
// proc gets (actor, target, held) and returns TRUE, or the reason text.
// Clauses compose with REQ_NOT / REQ_ANY / REQ_BECAUSE like every other predicate clause.

#define PRED_OP_FIELD "field"
#define PRED_OP_ACCESS "access"
#define PRED_OP_EMAGGED "emagged"
#define PRED_OP_ANCHORED "anchored"
#define PRED_OP_PANEL "panel"

/// PRED_OP_FIELD modes.
#define REQ_FIELD_MODE_TRUE "true"
#define REQ_FIELD_MODE_EQ "eq"

/// The target's field `name` is truthy (an empty list counts as false). `reason` optional.
#define REQ_FIELD(name, reason...) list(PRED_OP_FIELD, name, REQ_FIELD_MODE_TRUE, null, reason)
/// The target's field `name` is falsy (null, 0 or ""). `reason` optional.
#define REQ_FIELD_NOT(name, reason...) REQ_NOT(list(PRED_OP_FIELD, name, REQ_FIELD_MODE_TRUE, null, reason))
/// The target's field `name` equals `value`. `reason` optional.
#define REQ_FIELD_EQ(name, value, reason...) list(PRED_OP_FIELD, name, REQ_FIELD_MODE_EQ, value, reason)
/// The actor has the target's access (its req_access / req_one_access, through /obj/proc/allowed()).
#define REQ_ACCESS list(PRED_OP_ACCESS)
/// The target is not emagged.
#define REQ_NOT_EMAGGED REQ_NOT(list(PRED_OP_EMAGGED))
/// The target is anchored. REQ_NOT(REQ_ANCHORED): it must be unanchored.
#define REQ_ANCHORED list(PRED_OP_ANCHORED)
/// The target's maintenance panel is open (`open` TRUE) or closed (`open` FALSE).
#define REQ_PANEL(open) list(PRED_OP_PANEL, open)
