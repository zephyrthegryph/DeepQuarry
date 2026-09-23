// Predicate language (doc/rewrite/rules.md §2). Code: code/datums/properties/predicates.dm.
//
// A predicate is declared as data: a list of clauses, all of which must pass.
// Each clause is itself a list built by the REQ_* macros below. The spec is
// compiled once into a shared /datum/predicate (no per-instance cost) and
// evaluated against (actor, target, held). On failure it gives the reason
// from the first failing clause.
//
//   requires = list(
//       REQ_REACH_ADJACENT,
//       REQ_HAND_FREE,
//       REQ_TOOL_TIER(TOOL_WELDER, 2),
//       REQ_BELOW(PRED_TARGET, PROP_MASS, KG(5)),
//       REQ_NOT(REQ_TAG(PRED_TARGET, TAG_FLAMMABLE)),
//   )

// ---- Subjects: what a clause reads ----
/// No subject: a global proc clause.
#define PRED_GLOBAL 0
/// The mob performing the interaction.
#define PRED_ACTOR 1
/// The atom being interacted with.
#define PRED_TARGET 2
/// The item in the actor's active hand, or null.
#define PRED_HELD 3

// ---- Clause opcodes (first element of a clause spec) ----
#define PRED_OP_AND "and"
#define PRED_OP_OR "or"
#define PRED_OP_NOT "not"
#define PRED_OP_BECAUSE "because"
#define PRED_OP_TAG "tag"
#define PRED_OP_CMP "cmp"
#define PRED_OP_BAND "band"
#define PRED_OP_REL "rel"
#define PRED_OP_TOOL "tool"
#define PRED_OP_HAND_FREE "hand_free"
#define PRED_OP_HOLDING "holding"
#define PRED_OP_ADJACENT "adjacent"
#define PRED_OP_RANGE "range"
#define PRED_OP_SELF "self"
#define PRED_OP_IN_HAND "in_hand"
#define PRED_OP_PROC "proc"

// ---- Comparison operators ----
#define PRED_CMP_GT ">"
#define PRED_CMP_GTE ">="
#define PRED_CMP_LT "<"
#define PRED_CMP_LTE "<="
#define PRED_CMP_EQ "=="
#define PRED_CMP_NE "!="

// ---- Unit literals: a value followed by its PROP_UNIT_* ----
// They expand to two list elements, so a bare number in a comparison is a
// compile (boot validation) error: every compared value states its unit.
#define KELVIN(v) v, PROP_UNIT_KELVIN
#define JOULES(v) v, PROP_UNIT_JOULES
#define PASCALS(v) v, PROP_UNIT_PASCALS
#define MOL(v) v, PROP_UNIT_MOLES
#define WATTS(v) v, PROP_UNIT_WATTS
#define J_PER_K(v) v, PROP_UNIT_HEAT_CAPACITY
#define KG(v) v, PROP_UNIT_KILOGRAMS
#define CUBIC_M(v) v, PROP_UNIT_CUBIC_METRES
#define SIZE_CLASS(v) v, PROP_UNIT_SIZE_CLASS
#define RATIO(v) v, PROP_UNIT_RATIO

// ---- Combinators ----
/// Every clause must pass. A predicate's top-level list is an implicit ALL.
#define REQ_ALL(clauses...) list(PRED_OP_AND, clauses)
/// At least one clause must pass. The reason joins the children's with "or".
#define REQ_ANY(clauses...) list(PRED_OP_OR, clauses)
/// Negation, pushed into the leaves at compile time (De Morgan).
#define REQ_NOT(clause) list(PRED_OP_NOT, clause)
/// Replace a clause's generated reason with fixed text.
#define REQ_BECAUSE(clause, text) list(PRED_OP_BECAUSE, clause, text)

// ---- Properties ----
#define REQ_TAG(subject, tag) list(PRED_OP_TAG, subject, tag)
#define REQ_NO_TAG(subject, tag) REQ_NOT(REQ_TAG(subject, tag))
#define REQ_ABOVE(subject, prop, value) list(PRED_OP_CMP, subject, prop, PRED_CMP_GT, value)
#define REQ_AT_LEAST(subject, prop, value) list(PRED_OP_CMP, subject, prop, PRED_CMP_GTE, value)
#define REQ_BELOW(subject, prop, value) list(PRED_OP_CMP, subject, prop, PRED_CMP_LT, value)
#define REQ_AT_MOST(subject, prop, value) list(PRED_OP_CMP, subject, prop, PRED_CMP_LTE, value)
#define REQ_EQUALS(subject, prop, value) list(PRED_OP_CMP, subject, prop, PRED_CMP_EQ, value)
/// lo <= value <= hi.
#define REQ_BETWEEN(subject, prop, lo, hi) list(PRED_OP_BAND, subject, prop, lo, hi)
/// One subject's property against another's, e.g. target mass below actor mass. Same unit required.
#define REQ_COMPARE(subject_a, prop_a, op, subject_b, prop_b) list(PRED_OP_REL, subject_a, prop_a, op, subject_b, prop_b)

// ---- Relationships (interactions.md §5) ----
/// The held item has tool quality `quality` (tier 1).
#define REQ_TOOL(quality) list(PRED_OP_TOOL, quality, 1)
/// The held item has tool quality `quality` at tier `tier` or better.
#define REQ_TOOL_TIER(quality, tier) list(PRED_OP_TOOL, quality, tier)
#define REQ_HAND_FREE list(PRED_OP_HAND_FREE)
#define REQ_HOLDING list(PRED_OP_HOLDING)
#define REQ_EMPTY_HANDED REQ_NOT(REQ_HOLDING)
#define REQ_REACH_ADJACENT list(PRED_OP_ADJACENT)
#define REQ_REACH(tiles) list(PRED_OP_RANGE, tiles)
#define REQ_SELF list(PRED_OP_SELF)
#define REQ_NOT_SELF REQ_NOT(REQ_SELF)
/// The target is in one of the actor's hands.
#define REQ_TARGET_IN_HAND list(PRED_OP_IN_HAND)

// ---- Escape hatch: procs ----
// The proc gets (actor, target, held). It returns TRUE to pass, FALSE to fail
// with `reason`, or a string to fail with that string as the reason.
/// A proc on the subject, e.g. REQ_ON(PRED_TARGET, /obj/machinery/proc/can_toggle_power, "it has no power").
#define REQ_ON(subject, proc_path, reason) list(PRED_OP_PROC, subject, proc_path, reason)
/// A proc on the target (interactions.md §5).
#define REQ_TARGET_STATE(proc_path) list(PRED_OP_PROC, PRED_TARGET, proc_path, null)
/// A global proc.
#define REQ_PROC(proc_path, reason) list(PRED_OP_PROC, PRED_GLOBAL, proc_path, reason)

// ---- Watchability (for P4: rules compile to reactor watches) ----
// Set on compiled comparison clauses over channel-backed (PROP_SOURCE_DOMAIN)
// properties. The names match the verdigris watch kinds (R5).
#define PRED_WATCH_THRESHOLD "Threshold"
#define PRED_WATCH_BAND "Band"
#define PRED_WATCH_DIFFERENCE "Difference"

// ---- Reads ----
/// The shared compiled predicate for a /datum/predicate subtype.
#define PREDICATE(path) dq_predicate(path)
/// TRUE if `pred` passes for (actor, target, held).
#define PREDICATE_PASSES(pred, actor, target, held) (pred.check(actor, target, held))
/// null if `pred` passes, else the reason text.
#define PREDICATE_REASON(pred, actor, target, held) (pred.why_not(actor, target, held))
