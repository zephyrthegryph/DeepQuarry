// ---- legacy interaction entries as candidates ----

/// The plan stand-in of a legacy interaction: no parts, the interaction's id as its key.
GLOBAL_LIST_EMPTY(op_legacy_plans) // interaction type -> /datum/op_plan

/proc/op_legacy_plan(datum/interaction/I)
	RETURN_TYPE(/datum/op_plan)
	var/datum/op_plan/P = GLOB.op_legacy_plans["[I.type]"]
	if(P)
		return P
	P = new
	P.key = "legacy:[I.id || I.type]"
	P.base_key = P.key
	P.origin = "legacy [I.type]"
	P.label = I.name
	P.tier = I.priority
	P.bindings = list()
	GLOB.op_legacy_plans["[I.type]"] = P
	return P

/// The intent a legacy interaction answers: what its macro's default_action means.
/proc/op_legacy_intent(datum/interaction/I)
	switch(I.default_action)
		if(INPUT_ACTION_USE)
			return INTENT_USE
		if(INPUT_ACTION_ALTERNATE, INPUT_ACTION_ALTERNATE_SECONDARY)
			return INTENT_TOGGLE
		if(INPUT_ACTION_DRAG)
			return INTENT_DROP_ONTO
		if(INPUT_ACTION_INSPECT)
			return INTENT_EXAMINE
		if(INPUT_ACTION_SELF_USE)
			return INTENT_USE
	return null

/// Adds the legacy interaction entries that apply to the target to a click's candidates. They sit beside the new ops in one pass: each carries the
/// tier and the intent of its macro, and after a new op at equal tier and rank (declared later).
/proc/op_legacy_candidates(datum/op_resolution/R)
	if(isnull(R.gesture) || !R.target || !R.actor)
		return
	var/datum/interaction_resolution/L = interactions_for(R.actor, R.target, R.held, null, null, null, null, FALSE, FALSE)
	var/seq = 1000
	for(var/datum/interaction/I as anything in L.available)
		if(!op_legacy_fits(I, R))
			continue
		var/intent = op_legacy_intent(I)
		if(isnull(intent))
			continue
		var/datum/op_cand/C = new
		C.oplan = op_legacy_plan(I) // ALLOW(ownership): a transient record of one resolution: dropped with it
		C.legacy = I // ALLOW(ownership): a transient record of one resolution: dropped with it
		C.holder = R.target // ALLOW(ownership): a transient record of one resolution: dropped with it
		C.side = CAND_TARGET
		C.tier = I.priority
		C.seq = ++seq
		R.all += C // ALLOW(ownership): a transient record of one resolution: dropped with it
		var/rank = R.intents.Find(intent)
		if(!rank && (INTERACTION_TAG_HOSTILE in I.tags))
			rank = R.intents.Find(INTENT_ATTACK)
		if(!rank)
			C.dropped_by = GATE_MATCH
			continue
		C.rank = rank
		C.intent = intent
		R.ordered += C // ALLOW(ownership): a transient record of one resolution: dropped with it

/// Does a legacy entry interaction fit the shape of this input? The legacy handlers it came from ran only for such an input: attack_hand for an empty
/// hand, attackby for a held item used on something else, attack_self for the held item itself. (The resolver of the interactions does not ask: the
/// caller is what chose the entry, and here nobody has.) Without it a held item is offered the hand's touches of its target, and a punch is thrown with it.
/proc/op_legacy_fits(datum/interaction/I, datum/op_resolution/R)
	switch(I.entry)
		if(INTERACTION_ENTRY_HAND)
			return isnull(R.held)
		if(INTERACTION_ENTRY_ITEM)
			return !isnull(R.held) && R.held != R.target
		if(INTERACTION_ENTRY_SELF)
			return !isnull(R.held) && R.held == R.target
	return TRUE

/// Runs a legacy interaction that won a resolution: its own attempt() decides, the result is the outcome.
/proc/op_run_legacy(datum/op_cand/C, datum/op_resolution/R, datum/op_result/result)
	var/datum/interaction/I = C.legacy
	var/ran = I.attempt(R.actor, R.target, R.held)
	if(ran == INTERACTION_TRY_RAN || ran == INTERACTION_TRY_PENDING || ran == INTERACTION_TRY_PASS)
		result.outcome = ACT_COMMITTED
	else
		result.outcome = ACT_REFUSED
		result.reason = /datum/msg/op/not_available
	TEST_REC_OUTCOME(result.key, result.outcome, result.reason, R.actor)
	return result

/datum/input_adapter/compatibility_candidates(datum/op_resolution/R)
	return op_legacy_candidates(R)

/datum/input_adapter/compatibility_menu(mob/actor, atom/target, route = null, operations_only = FALSE)
	return legacy_action_options(actor, target, route, operations_only)

/datum/input_adapter/compatibility_screentip(mob/actor, atom/target, gesture)
	return legacy_screentip_for(actor, target, gesture)

/datum/input_adapter/compatibility_run(datum/op_cand/C, datum/op_resolution/R, datum/op_result/result)
	return op_run_legacy(C, R, result)

/datum/input_adapter/compatibility_topic(datum/holder, mob/actor, list/href_list)
	return topic_dispatch(holder, actor, href_list)
