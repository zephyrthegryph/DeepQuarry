// Destruction as a framework transaction (roadmap L track, doc/rewrite/lifecycle.md).
// destroy_transaction() (code/datums/lifecycle/transaction.dm) runs these in
// order; SSgarbage accumulates per-phase timing on /datum/qdel_item for the
// "per-phase destroy time" test (doc §8) and for live diagnostics, the same
// way it already times Destroy() itself.
#define LIFECYCLE_PHASE_GUARD 1
#define LIFECYCLE_PHASE_MIND 2
#define LIFECYCLE_PHASE_UNBIND 3
#define LIFECYCLE_PHASE_DEMATERIALIZE 4
#define LIFECYCLE_PHASE_CONTENTS 5
#define LIFECYCLE_PHASE_LINKS 6
#define LIFECYCLE_PHASE_TEARDOWN 7
#define LIFECYCLE_PHASE_EFFECTS 8
#define LIFECYCLE_PHASE_DESTROY 9
#define LIFECYCLE_PHASE_SCRUB 10
#define LIFECYCLE_PHASE_COUNT 10

/// A human label for a LIFECYCLE_PHASE_* id, for logs and test output.
#define LIFECYCLE_PHASE_NAME(id) (list("guard", "mind", "unbind", "dematerialize", "contents", "links", "teardown", "effects", "destroy", "scrub")[id])

// ---- Declared references (L2, doc/rewrite/lifecycle.md §4) ----
// One line next to the type replaces a hand-written Destroy() body. Each adds
// to what the parent type declared (read once per type, links.dm).
// NAMES is one var name or a list() of them; PAIRS/LISTS are assoc lists.

/// Owned children, not contained: deleted in phase 4 (was QDEL_NULL in Destroy()).
#define REF_OWNED(PATH, NAMES) ##PATH/declared_owned_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Owned lists of children: each member deleted in phase 4 (was QDEL_LIST in Destroy()).
#define REF_OWNED_LIST(PATH, NAMES) ##PATH/declared_owned_list_vars() { . = ..(); . = (. || list()) + NAMES; }
/// Pairs, our var -> the partner's var pointing back: nulled on both sides in phase 4.
#define REF_PAIR(PATH, PAIRS) ##PATH/declared_pair_vars() { return lifecycle_merge_assoc(..(), PAIRS); }
/// Back-lists, our var (the owner) -> the owner's list var we sit in: removed in phase 4.
#define REF_BACKLIST(PATH, LISTS) ##PATH/declared_backlist_vars() { return lifecycle_merge_assoc(..(), LISTS); }

/// Declared destruction effects (phase 6): DATA is a `new /datum/destroy_effects_data(...)`
/// with named arguments, built once per type. Replaces message/sound/debris/
/// neighbour-smoothing bodies in Destroy().
#define DESTROY_EFFECTS(PATH, DATA) ##PATH/destroy_effects() { var/static/datum/destroy_effects_data/data = DATA; return data; }
