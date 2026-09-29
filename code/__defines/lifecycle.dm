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

// ---- Declared references ----
// Ownership kinds and their declarations live in code/__defines/ownership.dm
// (doc/rewrite/ownership.md).

/// Declared destruction effects (phase 6): DATA is a `new /datum/destroy_effects_data(...)`
/// with named arguments, built once per type. Replaces message/sound/debris/
/// neighbour-smoothing bodies in Destroy().
#define DESTROY_EFFECTS(PATH, DATA) ##PATH/destroy_effects() { var/static/datum/destroy_effects_data/data = DATA; return data; }

// ---- Object pools (code/datums/lifecycle/pool.dm, lifecycle.md §4.1) ----
/// /datum/var/pool_state values. Null: the datum is not pooled.
#define POOL_STATE_FREE 1
#define POOL_STATE_TAKEN 2
/// Released while poisoning was on: never handed out again, and every
/// POOL_ASSERT_LIVE on it crashes.
#define POOL_STATE_POISONED 3

/// Makes PATH a pooled type: take one with pool_take(PATH), give it back with
/// pool_release(obj) or obj.release(). Pooled objects refuse a normal qdel.
#define POOL_DECLARE(PATH) PATH/is_pooled() { return TRUE; }; PATH/proc/release() { pool_release(src); }; PATH/Destroy(force) { if(!force) { pool_refused_qdel(src); return QDEL_HINT_LETMELIVE; } return ..(); }

/// First line of a pooled type's procs: crashes when the object was released
/// (poisoned) or is sitting in the pool, catching use after release.
#define POOL_ASSERT_LIVE(D) if((D).pool_state != POOL_STATE_TAKEN) { pool_use_after_release(D); }

/// PATH refuses qdel() unless forced (singletons, registries, pooled objects):
/// the object is left untouched. See /datum/proc/lifecycle_keep().
#define LIFECYCLE_KEEP_UNLESS_FORCED(PATH) ##PATH/lifecycle_keep(force) { return !force; }
/// PATH refuses every qdel(), forced or not.
#define LIFECYCLE_KEEP_ALWAYS(PATH) ##PATH/lifecycle_keep(force) { return TRUE; }
