// Explicit every() phase/lane routing. The deadline still uses its owner's
// clock; only ready delivery moves to a kernel work item. No-option entries
// keep their original direct deadline delivery.
GLOBAL_LIST_EMPTY(every_dispatch_items)

/proc/every_dispatch_needed(datum/entry/E)
	return !isnull(E.args["phase"]) || !isnull(E.args["lane"])

/proc/every_dispatch_item(datum/entry/E, default_phase = KERNEL_PHASE_P)
	var/phase = isnull(E.args["phase"]) ? default_phase : E.args["phase"]
	var/lane = isnull(E.args["lane"]) ? LANE_SIMULATION : E.args["lane"]
	var/key = "[phase]:[lane]:[!isnull(kernel().test_now)]"
	var/datum/work_item/every_dispatch/W = GLOB.every_dispatch_items[key]
	if(!W || QDELETED(W))
		W = new(TYPE_PROC_REF(/datum/work_item/every_dispatch, perform), WORK_EVERY_TICK, phase = phase, lane = lane)
		GLOB.every_dispatch_items[key] = W
	if(!W.key || kernel().work_by_key[W.key] != W)
		kernel_register_work(/datum/work_item/every_dispatch, W)
	return W

/proc/every_dispatch_queue(datum/entry/E, handler, list/arguments)
	var/list/captured = capture_args(arguments, TRUE)
	if(!captured)
		return
	every_dispatch_captured(E, handler, captured)

/proc/every_dispatch_captured(datum/entry/E, handler, list/captured, default_phase = KERNEL_PHASE_P)
	var/datum/work_item/every_dispatch/W = every_dispatch_item(E, default_phase)
	LAZYADD(W.pending, list(list(handler, captured)))
	W.wake()

/datum/work_item/every_dispatch
	var/list/pending

/datum/work_item/every_dispatch/item_key(owner_type)
	return "[owner_type]:[phase]:[lane]:[test_owned]"

/datum/work_item/every_dispatch/owner()
	return src

/datum/work_item/every_dispatch/runnable(datum/owner, datum/member)
	return !!length(pending)

/datum/work_item/every_dispatch/perform(datum/owner, datum/member, dt)
	while(length(pending))
		var/list/row = pending[1]
		pending.Cut(1, 2)
		var/list/captured = row[2]
		if(resolve_captured(captured[1], captured[2], TRUE))
			call(row[1])(arglist(captured[1]))
		if(KERNEL_OVER_BUDGET && length(pending))
			return STEP_YIELD
	pending = null
	return STEP_PARK

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/datum/work_item/every_dispatch/test_reset()
	..()
	pending = null
	parked = TRUE

#endif
