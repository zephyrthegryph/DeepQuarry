// Inputs: how a client input becomes an op (doc/rewrite/final_api.html, section 8 "Action paths: how input becomes an op"; section 19 "E2, parts":
// "UI, topic and inside inputs"; "the test driver's input forms").
//
// The input inbox (E6) resolves a typed event when it drains it, and calls E2 through the three resolver seams (code/engine/kernel/inbox.dm):
//
//   input_resolve_click(E)   a click: the actor's intents for the gesture, the candidates of the target, the held item and the actor
//   input_resolve_menu(E)    a pick from a target's context menu: the op named by key, origin ORIGIN_MENU, the same gates as a click
//   input_resolve_ui(E)      a window button: the op with that ui_act() binding, its arguments through the schema boundary (X5)
//
// plus topic links: op_topic() runs the op whose topic("key", args...) binding names the key.
//
// A player's click on a target none of whose ops belong to the new engine runs the legacy mob click exactly as before: nothing changes for a type
// until it declares an op. A click on a target that has one resolves among the new ops and the legacy interaction entries beside them in ONE
// pass (legacy entries are candidates carrying the tier and intent of their macro).

/// The gesture a click's params mean, for the gestures the new resolver takes: a plain left click and an alt-click. null: the legacy click
/// handles it (shift examines, ctrl pulls, middle points).
/proc/op_gesture_of_params(params)
	var/list/modifiers = params2list(params)
	if(modifiers["shift"] || modifiers["ctrl"] || modifiers["middle"] || modifiers["right"])
		return null
	if(modifiers["alt"])
		return GESTURE_ALT
	return GESTURE_CLICK

/// The click seam. A driver-built click is always the new resolver's; a player's is when the target, the held item or the actor has an op.
/proc/input_resolve_click(datum/input_event/click/E)
	RETURN_TYPE(/datum/op_result)
	var/mob/actor = E.actor
	var/atom/target = E.target
	if(E.driven)
		return op_resolve_click_with_params(actor, target, E.held, E.gesture, E.origin || ORIGIN_CLICK, E.params)
	// The click event (hooks on the target see it), then the new resolver when something of the click has an op, else the mob's click handling.
	OM_EMIT(E.target, /datum/om/event/click, E.location, E.control, E.params, E.actor)
	var/gesture = op_gesture_of_params(E.params)
	var/obj/item/held = actor?.get_active_hand()
	if(!isnull(gesture) && target && (op_has_ops(target) || op_has_ops(held)))
		var/datum/op_result/result = op_resolve_click_with_params(actor, target, held, gesture, ORIGIN_CLICK, E.params, TRUE, TRUE)
		if(result)
			return result
	E.actor.ClickOn(E.target, E.params)
	return null

/// op_resolve_click() with the click's parameters readable by the effects it runs, through dq_interaction_click_params(actor): an item put on a table
/// aligns to where it was clicked. The previous parameters come back when the resolution is done.
/proc/op_resolve_click_with_params(mob/actor, atom/target, obj/item/held, gesture, origin, params, quiet = FALSE, defer_legacy = FALSE)
	RETURN_TYPE(/datum/op_result)
	var/saved_params = dq_interaction_set_click_params(actor, params)
	. = op_resolve_click(actor, target, held, gesture, origin, quiet, defer_legacy)
	dq_interaction_set_click_params(actor, saved_params)

/// Resolves a click among the candidates and runs the winner. Returns its /datum/op_result, or null when nothing resolved (and `quiet`: nothing was said).
/// `defer_legacy`: when a legacy interaction entry wins, nothing runs here and the result is null: the mob's own click handling runs the legacy chain
/// (the tool's own act first, then the entries) exactly as it did before the type declared an op. A player's click takes it; a driver-built one does not.
/proc/op_resolve_click(mob/actor, atom/target, obj/item/held, gesture, origin, quiet = FALSE, defer_legacy = FALSE)
	RETURN_TYPE(/datum/op_result)
	var/datum/op_resolution/R = op_resolve(actor, target, held, origin, AUTH_PHYSICAL, gesture, null, TRUE)
	var/datum/op_cand/winner = op_resolution_winner(R)
	if(!winner)
		if(!quiet && length(R.all))
			// nothing survived: show the best near-miss's reason (rate limited), so a click never just does nothing
			var/why = op_resolution_refusal(R)
			op_gate_feedback(actor, why)
		return null
	if(defer_legacy && winner.legacy)
		return null
	return op_passes_chain(winner, op_begin(winner, R, null, FALSE), R, defer_legacy)

/// passes(): an op that ends committed and passes does not use the input up. The next candidate whose conditions hold runs, then the next, until one
/// does not pass or commits nothing. When the chain ends on a pass (and a player's click, which has the legacy handling to go on to), the result is
/// null: the mob's own click handling takes the input from there, as it did before the type declared an op. A driver-built click returns the last result.
/proc/op_passes_chain(datum/op_cand/winner, datum/op_result/result, datum/op_resolution/R, defer_legacy)
	RETURN_TYPE(/datum/op_result)
	var/datum/op_cand/last = winner
	while(last.oplan.passes && result?.outcome == ACT_COMMITTED)
		var/datum/op_cand/next = null
		var/seen = FALSE
		for(var/datum/op_cand/C as anything in R.ordered)
			if(C == last)
				seen = TRUE
				continue
			if(seen && op_cand_when(R, C))
				next = C
				break
		if(!next || next.legacy)
			return defer_legacy ? null : result
		result = op_begin(next, R, null, FALSE)
		last = next
	return result

/// Shows a gate refusal to an actor, at most once per GATE_FEEDBACK_INTERVAL.
/proc/op_gate_feedback(mob/actor, reason)
	if(!actor || isnull(reason))
		return
	var/static/list/last = list()
	var/ref = "[REF(actor)]"
	if(!isnull(last[ref]) && op_now() - last[ref] < GATE_FEEDBACK_INTERVAL)
		return
	last[ref] = op_now()
	op_tell(actor, reason)

/// The menu seam: the op named by key, picked from the target's context menu.
/proc/input_resolve_menu(datum/input_event/menu/E)
	RETURN_TYPE(/datum/op_result)
	return op_perform_by_key(E.actor, E.target, E.held, E.op_key, ORIGIN_MENU, AUTH_PHYSICAL, FALSE)

/// The window seam: a driver-built window action (a player's goes through the tgui window as before).
/proc/input_resolve_ui(datum/input_event/ui_act/E)
	RETURN_TYPE(/datum/op_result)
	var/datum/window = E.window
	if(!window || QDELETED(window))
		return null
	return op_ui_act(E.actor, window, E.action, E.payload)

/// The plan of `holder` whose ui_act() binding answers window action `action`: the binding's own name, else the op's key, else the key without
/// its capability's prefix.
/proc/op_plan_by_ui_action(datum/holder, action, list/activation_out)
	RETURN_TYPE(/datum/op_plan)
	for(var/datum/op_src/S as anything in op_sources_of(holder))
		var/datum/op_plan/P = S.oplan
		for(var/datum/entry/part/bind/B as anything in P.bindings)
			if(B.bind_kind != BIND_UI)
				continue
			var/named = B.args["action"]
			if((named && named == action) || (!named && (P.key == action || P.base_key == action)))
				if(S.activation)
					activation_out += S.activation
				return P
	return null

/// A window button: the op with that ui_act() binding runs with origin ORIGIN_UI, its arguments validated by their schemas first.
/proc/op_ui_act(mob/actor, datum/holder, action, list/payload)
	RETURN_TYPE(/datum/op_result)
	var/list/found = list()
	var/datum/op_plan/P = op_plan_by_ui_action(holder, action, found)
	if(!P)
		return null
	var/datum/entry/part/bind/ui_binding = null
	for(var/datum/entry/part/bind/B as anything in P.bindings)
		if(B.bind_kind == BIND_UI)
			ui_binding = B
			break
	var/list/values = list()
	var/why = op_validate_args(P.ui_args, holder, payload, values)
	if(why)
		var/datum/op_result/refused = new
		refused.key = P.key
		refused.origin = ORIGIN_UI
		refused.outcome = ACT_REFUSED
		refused.reason = why
		op_tell(actor, why)
		TEST_REC_OUTCOME(P.key, ACT_REFUSED, why, actor)
		return refused
	return op_perform_by_key(actor, holder, null, P.key, ORIGIN_UI, AUTH_PHYSICAL, FALSE, values)

/// Runs a payload through the declared arg() schemas: fills `values` (name -> value) and returns a reason when one is refused. A number outside
/// its range is clamped and logged; any other failure refuses the press.
/proc/op_validate_args(list/declared, datum/holder, list/payload, list/values)
	for(var/datum/entry/part/ui_arg/arg_part as anything in declared)
		var/name = arg_part.args["name"]
		var/datum/schema/S = arg_part.arg_schema(holder)
		var/value = payload ? payload[name] : null
		if(!S)
			values[name] = value
			continue
		if(isnull(value) && S.has_default)
			value = S.default
		var/list/checked = schema_input(S, value, holder)
		if(checked[1] == SCHEMA_REJECT)
			schema_log(holder, name, "[name] [checked[2]]: input refused")
			return /datum/msg/op/bad_args
		if(checked[2])
			schema_log(holder, name, "[name] [checked[2]]")
		values[name] = checked[1]
	return null

/// The schema an arg() names: its own, or the tracked var's (from = nameof(v)).
/datum/entry/part/ui_arg/proc/arg_schema(datum/holder)
	var/datum/schema/own = src.args["schema"]
	if(own)
		return own
	var/from = src.args["from"]
	if(from && holder)
		return schema_of(holder.type, from)
	return null

/// A topic link: the op of `holder` whose topic("key", args...) binding names `key` runs with origin ORIGIN_UI.
/proc/op_topic(mob/actor, datum/holder, key, list/params)
	RETURN_TYPE(/datum/op_result)
	for(var/datum/op_src/S as anything in op_sources_of(holder))
		var/datum/op_plan/P = S.oplan
		if(P.topic_key != key)
			continue
		var/list/values = list()
		var/why = op_validate_args(P.topic_args, holder, params, values)
		if(why)
			var/datum/op_result/refused = new
			refused.key = P.key
			refused.origin = ORIGIN_UI
			refused.outcome = ACT_REFUSED
			refused.reason = why
			TEST_REC_OUTCOME(P.key, ACT_REFUSED, why, actor)
			return refused
		return op_perform_by_key(actor, holder, null, P.key, ORIGIN_UI, AUTH_PHYSICAL, FALSE, values)
	return null

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
