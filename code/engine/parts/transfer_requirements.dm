// Native insertion/removal requirement queries. Effects retain their real ACTION contexts.
/proc/op_transfer_precheck(atom/destination, action_type, atom/movable/candidate, slot_id, mob/mover = null)
	var/list/reads = list()
	var/reason = op_transfer_query(destination, action_type, candidate, slot_id, mover, reads)
	op_menu_record_reads(reads)
	return reason

/proc/op_transfer_read_keys(atom/destination, action_type, atom/movable/candidate, slot_id, mob/mover = null)
	. = list()
	op_transfer_query(destination, action_type, candidate, slot_id, mover, ., evaluate = FALSE)

/proc/op_transfer_query(atom/destination, action_type, atom/movable/candidate, slot_id, mob/mover, list/reads, evaluate = TRUE)
	if(!destination || QDELETED(destination))
		return "there is nowhere to put it"
	var/datum/rx_state/S = rx_of(destination)
	reads += list(list(S, nameof(S.hooks_generation)))
	var/datum/act_plan/P = act_plan_for(destination, action_type)
	if(!P || !length(P.needs))
		qdel(P)
		return null
	var/datum/act/op/acceptance/A
	var/previous_pure_depth = GLOB.op_pure_depth
	try
		A = acceptance_act(destination, destination, candidate, null, mover, slot_id)
		op_pure_begin()
		// Metadata precedes ordered refusal so later branches remain subscribed.
		for(var/datum/hook/H as anything in P.needs)
			op_transfer_hook_reads(A, H, reads)
		if(evaluate)
			for(var/datum/hook/H as anything in P.needs)
				. = op_transfer_hook_reason(A, H)
				if(!isnull(.))
					break
	catch(var/exception/fault)
		GLOB.op_pure_depth = previous_pure_depth
		acceptance_act_release(A)
		qdel(P)
		throw fault
	op_pure_end()
	acceptance_act_release(A)
	qdel(P)

/proc/op_transfer_hook_reads(datum/act/op/acceptance/A, datum/hook/H, list/reads)
	A.holder = A.destination
	// Static guards are holder conditions, not candidate requirements.
	for(var/datum/entry/W as anything in H.whens)
		// Native query reads preserve generated entity roots and every relation hop.
		op_reads_of(A, W.args["cond"], reads)
	if(!hook_enter(A, H))
		return
	hook_context(A, H)
	for(var/child in H.entry.children)
		if(!istype(child, /datum/entry/part/req))
			CRASH("Transfer admission needs a native null-or-reason requirement")
		op_reads_of(A, child, reads)
	A.holder = A.destination

/proc/op_transfer_hook_reason(datum/act/op/acceptance/A, datum/hook/H)
	A.holder = A.destination
	if(!hook_conditions_hold(H, A.destination) || !hook_enter(A, H))
		return null
	hook_context(A, H)
	for(var/datum/entry/part/req/R as anything in H.entry.children)
		. = op_req_check(A, R)
		if(!isnull(.))
			break
	A.holder = A.destination

// Final action needs uses the same native callback context. No effect callback receives this query.
/proc/op_transfer_action_requirement(datum/act/action/F, datum/hook/H)
	var/atom/movable/candidate
	var/slot_id
	if(istype(F, /datum/act/insert))
		var/datum/act/insert/I = F
		candidate = I.item
		slot_id = I.slot_id
	else if(istype(F, /datum/act/remove))
		var/datum/act/remove/R = F
		candidate = R.item
		slot_id = R.slot_id
	else
		CRASH("Only insert/remove requirements use transfer query context")
	var/datum/act/op/acceptance/A
	var/previous_pure_depth = GLOB.op_pure_depth
	try
		A = acceptance_act(F.target, F.target, candidate, null, F.actor, slot_id)
		op_pure_begin()
		. = op_transfer_hook_reason(A, H)
	catch(var/exception/fault)
		GLOB.op_pure_depth = previous_pure_depth
		acceptance_act_release(A)
		throw fault
	op_pure_end()
	acceptance_act_release(A)
