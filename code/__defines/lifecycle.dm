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

/// From this phase on an entity refuses new ownership, relations, timers, hooks, tasks and
/// contents adoption (ownership.md sec 1.1 O5): the one predicate every accessor checks
/// through OWN_GUARD() (code/datums/ownership/guard.dm).
#define LIFECYCLE_REFUSE_PHASE LIFECYCLE_PHASE_GUARD
/// TRUE while D is in its destroy transaction at or past LIFECYCLE_REFUSE_PHASE, done, or
/// already marked for deletion (gc_destroyed: queued, or doomed by a destroy batch).
#define LIFECYCLE_DYING(D) ((D).destroy_phase >= LIFECYCLE_REFUSE_PHASE || (D).gc_destroyed)

// ---- The destroy transaction's steps: the one declared sequence ----
// destroy_transaction_phases() runs GLOB.destroy_step_sequence in order and nothing else, so a
// step (the contents release check, say) cannot drift to the wrong phase: its place is here.
// Each step is timed onto, and sets the datum's destroy_phase to, its LIFECYCLE_PHASE_*.
#define DESTROY_STEP_GUARD 1
#define DESTROY_STEP_LEAVE_REGISTRIES 2
#define DESTROY_STEP_MIND 3
#define DESTROY_STEP_UNBIND 4
#define DESTROY_STEP_DEMATERIALIZE 5
#define DESTROY_STEP_CONTENTS_RESOLVE 6
#define DESTROY_STEP_CONTENTS_SPILL 7
#define DESTROY_STEP_CONTENTS_CHECK_RELEASED 8
#define DESTROY_STEP_LINKS 9
#define DESTROY_STEP_TEARDOWN 10
#define DESTROY_STEP_EFFECTS 11
#define DESTROY_STEP_DESTROY 12
#define DESTROY_STEP_EFFECTS_AFTER 13
#define DESTROY_STEP_SCRUB 14
#define DESTROY_STEP_POSTCONDITION 15
#define DESTROY_STEP_COUNT 15
/// The LIFECYCLE_PHASE_* each step belongs to (timing and destroy_phase).
#define DESTROY_STEP_PHASE(step) (list(LIFECYCLE_PHASE_GUARD, LIFECYCLE_PHASE_GUARD, LIFECYCLE_PHASE_MIND, LIFECYCLE_PHASE_UNBIND, LIFECYCLE_PHASE_DEMATERIALIZE, LIFECYCLE_PHASE_CONTENTS, LIFECYCLE_PHASE_CONTENTS, LIFECYCLE_PHASE_CONTENTS, LIFECYCLE_PHASE_LINKS, LIFECYCLE_PHASE_TEARDOWN, LIFECYCLE_PHASE_EFFECTS, LIFECYCLE_PHASE_DESTROY, LIFECYCLE_PHASE_EFFECTS, LIFECYCLE_PHASE_SCRUB, LIFECYCLE_PHASE_SCRUB)[step])
#define DESTROY_STEP_NAME(step) (list("guard", "leave registries", "mind", "unbind", "dematerialize", "contents: resolve slots", "contents: spill owned", "contents: check released", "links", "teardown", "effects", "destroy", "effects after", "scrub", "postcondition")[step])

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

/// pool_reset_plan() values: a field reset to its initial value, and a list New() allocated (kept, emptied).
#define POOL_RESET_VALUE 1
#define POOL_RESET_LIST 2

/// (Legacy form; new pooled types are subtypes of /datum/pooled.) Makes PATH a pooled type: take one with pool_take(PATH), give it back with
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
