// Pooled waiting-context state and notification protocol; concrete operation policies live downstream.
/datum/operation_context
	parent_type = /datum/pooled
	pool_max_free = 32
	/// The mob acting.
	var/mob/actor
	var/datum/target
	var/obj/held
	/// The interaction entry running this op, when it came through the resolver.
	/// The slot decl that provides the affordance (a hand), and the ledger id of the actor's slot.
	/// ROUTE_*: how this attempt reaches the target.
	var/route = ROUTE_PHYSICAL
	/// Who authorizes it when route is ROUTE_AUTHORITY (an admin mob, a console); else null.
	var/datum/authority
	/// Unique per take: the handle a pending wait carries instead of the context itself.
	var/id = 0
	/// Text detail for a reason that has a %DETAIL% slot.
	var/detail
	/// The reason (a /datum/msg type) the last check() failed with, and the stage it failed at.
	var/reason
	var/failed_stage = 0
	/// (datum, key) pairs a pending wait watches: list(list(datum, key), ...).
	var/list/watch
	/// The datums this pending wait is registered on for teardown and for watching: actor, target, held, the
	/// provider's item, every watched datum (op_pending_add / op_pending_forget).
	var/list/ends
	/// Set once release() ran; touching a released context is a bug (CRASH in test builds).
	var/released = FALSE

/// Gives the context back: a pending wait is dropped, every field returns to its initial value
/// (the pool does it), and the context waits in the pool (poisoned in test builds).
/datum/operation_context/release()
	if(released)
#ifdef UNIT_TESTS
		CRASH("op_ctx released twice")
#else
		return
#endif
	forget_wait()
	..()

/// Runs after the pool reset every field: marks the context released.
/datum/operation_context/reset()
	..()
	released = TRUE

/// The test-build poison: reading a released context stops the test that did.
/datum/operation_context/proc/assert_live()
#ifdef UNIT_TESTS
	if(released)
		CRASH("use of a released op_ctx")
#endif

/// A read (E, key) was published: every pending operation watching it re-checks now and cancels
/// if a requirement no longer holds. Cheap when nothing is pending. W1's publish_change() calls
/// this; cap_set() calls it for OP_KEY_CAP_STATE.
/proc/op_reads_changed(datum/E, key)
	if(!length(GLOB.op_watchers))
		return
	var/list/on = GLOB.op_watchers["[REF(E)]|[key]"]
	if(!length(on))
		return
	for(var/datum/ctx as anything in on.Copy())
		if(istype(ctx, /datum/pending_op))
			var/datum/pending_op/pending = ctx // a wait of the part engine (code/engine/parts/run.dm)
			pending.reads_changed()
			continue
		if(istype(ctx, /datum/task))
			var/datum/task/task = ctx // a running task (code/engine/kernel/tasks.dm)
			task.reads_changed()
			continue
		var/datum/operation_context/legacy = ctx
		if(legacy.released)
			continue
		legacy.reads_changed()


/datum/operation_context/proc/forget_wait()
	return

/datum/operation_context/proc/reads_changed()
	return

/datum/operation_context/proc/cancel_deleted()
	return
