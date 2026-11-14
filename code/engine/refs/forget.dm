// engine_forget(D): the one place a dying datum leaves the engine's own tables and queues.
//
// An engine queue or index that names a datum by reference would keep it alive past qdel(), so each one drops the datum here, once, in the destroy
// transaction, before the last reference goes. A queue that holds the datum itself, or a table keyed by its slot, adds its removal to this proc,
// and only to this proc: refs does not need to know about them.
//
// WHEN: engine_forget(D) is the first half of the last thing a destroy transaction does (dq_lifecycle_release_slot(), code/library/lifecycle/transaction.dm), after
// Destroy() and the scrub and BEFORE slot_release(D). slot_of(D) and D.handle_slot are still valid inside it, so a per-slot table can find and drop its row. After
// it returns the slot is freed (code/engine/refs/slots.dm) and nothing may name D again. It can run twice for one datum (an aborted transaction
// finishes the teardown again), so every removal in it is idempotent.

/// Drops `D` from every engine table and queue that holds it by reference. Called once per destroyed datum, in the teardown phase, before its slot is released.
/proc/engine_forget(datum/D)
	capability_runtime_forget(D)
	lazy_state_forget(D)
	per_type_forget(D)
	staleness_forget(D)
	derived_forget(D)
	init_open_forget(D)
	refresh_forget(D)
	sense_forget(D)
