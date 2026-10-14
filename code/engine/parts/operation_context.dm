// Pooled requirement-context state and the read-change notification of waiting ops, every() hops and tasks.
/datum/operation_context
	parent_type = /datum/pooled
	pool_max_free = 32
	/// The mob acting.
	var/mob/actor
	var/datum/target
	var/obj/held
	/// ROUTE_*: how this attempt reaches the target.
	var/route = ROUTE_PHYSICAL
	/// Who authorizes it when route is ROUTE_AUTHORITY (an admin mob, a console); else null.
	var/datum/authority
	/// Unique per take.
	var/id = 0
	/// Text detail for a reason that has a %DETAIL% slot.
	var/detail
	/// The reason (a /datum/msg type) a boundary refused with.
	var/reason
	/// Set once release() ran; touching a released context is a bug (CRASH in test builds).
	var/released = FALSE

/// Gives the context back: every field returns to its initial value (the pool does it), and the context
/// waits in the pool (poisoned in test builds).
/datum/operation_context/release()
	if(released)
#ifdef UNIT_TESTS
		CRASH("op_ctx released twice")
#else
		return
#endif
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

/// "[REF(datum)]|[key]" -> what watches that read: waiting ops, every() hops, tasks.
GLOBAL_LIST_EMPTY(op_watchers)

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
		if(istype(ctx, /datum/every_hop_watch))
			var/datum/every_hop_watch/hop_watch = ctx // a parked every() following a relation hop (code/engine/actions/every.dm)
			hop_watch.reads_changed()
			continue
		if(istype(ctx, /datum/task))
			var/datum/task/task = ctx // a running task (code/engine/kernel/tasks.dm)
			task.reads_changed()
