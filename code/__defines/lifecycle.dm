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
