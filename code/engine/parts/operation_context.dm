// The read-change notification of waiting ops, every() hops and tasks.

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
