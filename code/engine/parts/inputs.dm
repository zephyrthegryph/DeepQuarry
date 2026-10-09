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

/// The gesture a click's params mean, for the gestures the new resolver takes: a plain left click, an alt-, shift-, ctrl- and middle-click. A
/// shift-, ctrl- or middle-click that no op answers (no op pins it, as a silicon's remote controls do) goes on to the legacy click (shift
/// examines, ctrl pulls, middle points). null: the legacy click alone handles it (a right click, a combination of modifiers).
/proc/op_gesture_of_params(params)
	var/list/modifiers = params2list(params)
	if(modifiers["right"])
		return null
	var/held_down = !!modifiers["shift"] + !!modifiers["ctrl"] + !!modifiers["alt"]
	if(held_down > 1)
		return null
	if(modifiers["middle"])
		return held_down ? null : GESTURE_MIDDLE
	if(modifiers["alt"])
		return GESTURE_ALT
	if(modifiers["shift"])
		return GESTURE_SHIFT
	if(modifiers["ctrl"])
		return GESTURE_CTRL
	return GESTURE_CLICK

/// The click seam. A driver-built click is always the new resolver's; a player's is when the target, the held item or the actor has an op.
/proc/input_resolve_click(datum/input_event/click/E)
	RETURN_TYPE(/datum/op_result)
	var/mob/actor = E.actor
	var/atom/target = E.target
	if(E.driven)
		return op_resolve_click_with_params(actor, target, E.held, E.gesture, E.origin || ORIGIN_CLICK, E.params)
	// The click event (hooks on the target see it), then the new resolver when something of the click has an op, else the mob's click handling.
	E.publish_compatibility_click()
	var/gesture = op_gesture_of_params(E.params)
	var/obj/held = actor?.held_for_ops()
	if(!isnull(gesture) && target && (op_has_ops(target) || op_has_ops(held) || op_has_click_ops(actor)))
		var/datum/op_result/result = op_resolve_click_with_params(actor, target, held, gesture, ORIGIN_CLICK, E.params, TRUE, TRUE)
		if(result)
			return result
	// The ops had their say: the mob's click handling below must not resolve them a second time (route_click()).
	GLOB.op_click_resolved[actor] = TRUE
	E.actor.op_compatibility_click(E.target, E.params)
	GLOB.op_click_resolved -= actor
	return null

/// Actors whose click the inbox already resolved among the ops (it is in the mob's own click handling now). A click that reaches the router any other
/// way (the router entry of an AI hotkey, a pAI card, a test) resolves the ops first itself (route_click()).
GLOBAL_LIST_EMPTY(op_click_resolved)

/// op_resolve_click() with the click's parameters readable by the effects it runs, through dq_interaction_click_params(actor): an item put on a table
/// aligns to where it was clicked. The previous parameters come back when the resolution is done.
/proc/op_resolve_click_with_params(mob/actor, atom/target, obj/held, gesture, origin, params, quiet = FALSE, defer_legacy = FALSE)
	RETURN_TYPE(/datum/op_result)
	var/saved_params = actor?.op_click_params(params)
	. = op_resolve_click(actor, target, held, gesture, origin, quiet, defer_legacy)
	actor?.op_click_params(saved_params)

/// Does the actor have an op of its own that its clicks reach (a clicks() binding: a natural weapon)? A plain read of the compiled index, so a click of a
/// mob with none costs two lookups.
/proc/op_has_click_ops(mob/actor)
	if(!actor || QDELETED(actor))
		return FALSE
	var/datum/type_table/T = table_of(actor)
	if(op_index_of_table(T).has_clicks)
		return TRUE
	for(var/datum/activation/A as anything in actor.rx?.activations)
		if(!A.dead && A.runs && op_index_of_def(T, A.def).has_clicks)
			return TRUE
	return FALSE

/// The drag seam. A driver-built drag is always the new resolver's; a player's is when the target or the dragged atom has an op, and what no op answers goes
/// on to the legacy chain (the gesture entries, then MouseDrop_T) exactly as before.
/proc/input_resolve_drag(datum/input_event/drag/E)
	RETURN_TYPE(/datum/op_result)
	var/mob/actor = E.actor
	var/atom/over = E.over
	var/atom/dragged = E.dragged
	var/params = E.legacy_args?[5]
	if(E.driven)
		return op_resolve_click_with_params(actor, over, dragged, GESTURE_DRAG, E.origin || ORIGIN_CLICK, params)
	if(over && (op_has_ops(over) || op_has_ops(dragged)))
		var/datum/op_result/result = op_resolve_click_with_params(actor, over, dragged, GESTURE_DRAG, ORIGIN_CLICK, params, TRUE, TRUE)
		if(result)
			return result
	var/datum/input_adapter/adapter = actor.input_adapter()
	adapter.drag_legacy(actor, dragged, over, E.legacy_args)
	return null

/// Resolves a click among the candidates and runs the winner. Returns its /datum/op_result, or null when nothing resolved (and `quiet`: nothing was said).
/// `defer_legacy`: when a legacy interaction entry wins, nothing runs here and the result is null: the mob's own click handling runs the legacy chain
/// (the tool's own act first, then the entries) exactly as it did before the type declared an op. A player's click takes it; a driver-built one does not.
/proc/op_resolve_click(mob/actor, atom/target, obj/held, gesture, origin, quiet = FALSE, defer_legacy = FALSE, quality = null, no_tool = FALSE)
	RETURN_TYPE(/datum/op_result)
	var/datum/op_resolution/R = op_resolve(actor, target, held, origin, actor_authority(actor), gesture, null, TRUE)
	var/datum/op_cand/winner = op_resolution_winner(R)
	// `quality` / `no_tool`: a tool's own act (crowbar_act) or an item's plain use (item_interaction) asks for the winner of that kind only; any other winner is
	// not this call's to run.
	if(winner && !winner.legacy)
		if(quality && !(winner.binding?.bind_kind == BIND_TOOL && (quality in winner.binding.args["quality"])))
			return null
		if(no_tool && winner.binding?.bind_kind == BIND_TOOL)
			return null
	if(!winner)
		if(!quiet && length(R.all))
			// nothing survived: show the best near-miss's reason (rate limited), so a click never just does nothing
			var/why = op_resolution_refusal(R)
			op_gate_feedback(actor, why)
		return null
	if(defer_legacy && winner.legacy)
		return null
	var/datum/op_result/result = op_begin(winner, R, null, FALSE)
	// OP_DECLINE: the handler said "not handled": the next candidate whose conditions hold gets the click, then the next, until one takes it. Nothing
	// was committed, told or published by the ones that declined; when every one declines a player's click is as if none had answered (null) and a driver-built click returns the last declined result.
	var/datum/op_cand/tried = winner
	while(result?.outcome == ACT_DECLINED)
		var/datum/op_cand/next = null
		var/seen = FALSE
		for(var/datum/op_cand/C as anything in R.ordered)
			if(C == tried)
				seen = TRUE
				continue
			if(seen && op_cand_when(R, C))
				next = C
				break
		if(!next || (defer_legacy && next.legacy))
			return defer_legacy ? null : result
		winner = next
		tried = next
		result = op_begin(next, R, null, FALSE)
	return op_passes_chain(winner, result, R, defer_legacy)

/// passes(): an op that ends committed and passes does not use the input up. The next candidate whose conditions hold runs, then the next, until one
/// does not pass or commits nothing. When the chain ends on a pass (and a player's click, which has the legacy handling to go on to), the result is
/// null: the mob's own click handling takes the input from there, as it did before the type declared an op. A driver-built click returns the last result.
/proc/op_passes_chain(datum/op_cand/winner, datum/op_result/result, datum/op_resolution/R, defer_legacy)
	RETURN_TYPE(/datum/op_result)
	var/datum/op_cand/last = winner
	while((last.oplan.passes || result?.passed) && result?.outcome == ACT_COMMITTED)
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
	return op_perform_by_key(E.actor, E.target, E.held, E.op_key, ORIGIN_MENU, actor_authority(E.actor), FALSE)

/// The window seam: a driver-built window action (a player's goes through the tgui window as before).
/proc/input_resolve_ui(datum/input_event/ui_act/E)
	RETURN_TYPE(/datum/op_result)
	var/datum/window = E.window
	if(!window || QDELETED(window))
		return null
	return op_ui_act(E.actor, window, E.action, E.payload)

/// The plan of `holder` whose ui_act() binding answers window action `action`: the binding's own name, else the op's key, else the key without
/// its capability's prefix. Two names are the engine's: `modal_open` (the client opens a modal of its window by id) is the action "modal:<id>", and an
/// op that says ui_act("*") answers every window action no op of the holder names (the old UI_ACT_FALLBACK). The named one always wins; `exact`
/// leaves the fallback out.
/proc/op_plan_by_ui_action(datum/holder, action, list/activation_out, list/payload = null, exact = FALSE)
	RETURN_TYPE(/datum/op_plan)
	if(action == OP_UI_MODAL_OPEN && istext(payload?["id"]))
		var/datum/op_plan/modal_plan = op_plan_by_ui_action(holder, "[OP_UI_MODAL_PREFIX][payload["id"]]", activation_out, null, TRUE)
		if(modal_plan)
			return modal_plan
	var/datum/op_plan/fallback = null
	var/datum/activation/fallback_activation = null
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
			if(named == OP_UI_ANY && !fallback)
				fallback = P
				fallback_activation = S.activation
	if(exact || !fallback)
		return null
	if(fallback_activation)
		activation_out += fallback_activation
	return fallback

/// A window button: the op with that ui_act() binding runs with origin ORIGIN_UI, its arguments validated by their schemas first.
/proc/op_ui_act(mob/actor, datum/holder, action, list/payload, forward_depth = 0, datum/forwarded_by = null, datum/pressed_in = null)
	RETURN_TYPE(/datum/op_result)
	if(!forward_depth)
		var/datum/entry/window_decl = present_interface(holder)
		var/pressed = window_decl?.args["pressed"]
		if(pressed)
			call(holder, pressed)(actor, action) // interface(pressed =): the holder's reaction to any press in its window
	var/list/found = list()
	var/datum/op_plan/P = op_plan_by_ui_action(holder, action, found, payload)
	if(!P)
		return op_ui_forward(actor, holder, action, payload, forward_depth, pressed_in)
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
	values[OP_UI_WINDOW_ACTION] = action // the op reads which action reached it with A.window_action() (a ui_act("*") op answers many)
	if(pressed_in)
		values[OP_UI_TGUI] = pressed_in // A.window_ui(): the window the button was pressed in (its modal, its assets, closing it)
	if(forwarded_by)
		values[OP_UI_FORWARDED_BY] = forwarded_by // A.window_forwarder(): the window that sent the button on (a datum, only for the op's own read)
	return op_perform_by_key(actor, holder, null, P.key, ORIGIN_UI, actor_authority(actor), FALSE, values)

/// A window action the holder has no op for goes to the datums its interface(forwards = nameof(var)) names (a var holding one datum or a list): the first with
/// an op for it answers, as if its own window had sent the button (the old UI_ACT_FORWARD). A forward goes at most OP_UI_FORWARD_DEPTH windows deep.
/proc/op_ui_forward(mob/actor, datum/holder, action, list/payload, forward_depth = 0, datum/pressed_in = null)
	RETURN_TYPE(/datum/op_result)
	if(forward_depth >= OP_UI_FORWARD_DEPTH)
		return null
	var/datum/entry/declared = present_interface(holder)
	var/where = declared?.args["forwards"]
	if(!istext(where) || !(where in holder.vars))
		return null
	var/targets = holder.vars[where]
	if(!islist(targets))
		targets = targets ? list(targets) : null
	for(var/datum/target as anything in targets)
		if(QDELETED(target) || target == holder)
			continue
		var/datum/op_result/answered = op_ui_act(actor, target, action, payload, forward_depth + 1, holder, pressed_in)
		if(answered)
			return answered
	return null

/// A sub-action's arguments: the nested message an op's handler routes itself (a board game's "game_action" carries a move and its data). `schemas`
/// is name -> schema (null passes the value as it came). Returns name -> value, or null when one is refused (logged like a refused arg()).
/proc/payload_args(datum/holder, list/data, list/schemas)
	var/list/typed = list()
	for(var/name in schemas)
		var/datum/schema/S = schemas[name]
		var/value = islist(data) ? data[name] : null
		if(!S || isnull(value))
			typed[name] = value
			continue
		var/list/checked = schema_input(S, value, holder)
		if(checked[1] == SCHEMA_REJECT)
			schema_log(holder, name, "[name] [checked[2]]: sub-action refused")
			return null
		typed[name] = checked[1]
	return typed

/// Runs a payload through the declared arg() schemas: fills `values` (name -> value) and returns a reason when one is refused. A number outside
/// its range is clamped and logged; any other failure refuses the press.
/proc/op_validate_args(list/declared, datum/holder, list/payload, list/values)
	for(var/datum/entry/part/ui_arg/arg_part as anything in declared)
		var/name = arg_part.args["name"]
		var/datum/schema/S = arg_part.arg_schema(holder)
		var/value = payload ? payload[name] : null
		if(isnull(value) && arg_part.args["optional"])
			values[name] = null // arg(optional = TRUE): a value the link may leave out reaches the handler as null
			continue
		var/among = arg_part.args["among"]
		if(!isnull(among) && istext(value) && S)
			var/found = holder.op_topic_resolve_ref(value, S.type_of, among) // arg(among =): the ref is looked up in its source, never anywhere locate() reaches
			if(isnull(found))
				schema_log(holder, name, "[name] names nothing among [among]: input refused")
				return /datum/msg/op/bad_args
			value = found
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
		return op_topic_run(actor, holder, P, params)
	return null

/// Runs the plan a topic link named: its arg() schemas check the href's values, then the op runs as a click would (Match, Require, Wait, Do).
/proc/op_topic_run(mob/actor, datum/holder, datum/op_plan/P, list/params)
	RETURN_TYPE(/datum/op_result)
	// Who may use the holder's links at all is a requirement of its ops (needs(req_topic_token()), or extend(TAG_TOPIC, needs(...))), checked with the rest.
	var/list/values = list()
	var/why = op_validate_args(P.topic_args, holder, params, values)
	if(why)
		var/datum/op_result/refused = new
		refused.key = P.key
		refused.origin = ORIGIN_UI
		refused.outcome = ACT_REFUSED
		refused.reason = why
		op_tell(actor, why)
		TEST_REC_OUTCOME(P.key, ACT_REFUSED, why, actor)
		return refused
	values[OP_TOPIC_HREF] = params // A.topic_href(): the raw href (a re-run of an ask reads it)
	var/datum/op_result/result = op_perform_by_key(actor, holder, null, P.key, ORIGIN_UI, actor_authority(actor), FALSE, values)
	if(result?.outcome == ACT_REFUSED && result.reason == /datum/msg/req_no_rights)
		// A rights failure on an href is how exploit attempts show up: always tell admins.
		var/wanted = 0
		for(var/datum/entry/part/req/rights/needed in P.needs)
			wanted |= needed.args["rights"]
		holder.op_topic_rights_denied(actor, P.topic_key, wanted)
	else if(result?.outcome == ACT_REFUSED && (result.reason == /datum/msg/op/topic_token || result.reason == /datum/msg/op/topic_gate))
		holder.op_topic_refused(actor, P.topic_key, result.reason, params)
	return result

/// The topic ops of a type, by topic key, in one namespace (null: plain hrefs); a subtype's own op for a key beats its parent's, as everywhere. Built once per type.
/proc/op_topic_table(datum/holder, namespace = null)
	var/datum/op_index/index = op_index_of_table(table_of(holder))
	var/slot = isnull(namespace) ? "" : "[namespace]"
	var/list/made = index.topic_plans?[slot]
	if(isnull(made))
		made = list()
		for(var/datum/op_plan/P as anything in index.ordered)
			if(isnull(P.topic_key) || P.topic_namespace != namespace)
				continue
			made[P.topic_key] = P
		LAZYSET(index.topic_plans, slot, made)
	return made

/// The plan of `holder` whose topic("key") names this href: a key "action=foo" matches href action=foo and is tried before a bare "action" key, as a
/// retired table row's did, so an op names its href by the same text and no link changes. The args are every other value of the href.
/proc/op_topic_plan(datum/holder, list/href_list, namespace = null)
	RETURN_TYPE(/datum/op_plan)
	if(!isdatum(holder) || QDELETED(holder) || !length(href_list))
		return null
	var/list/by_key = op_topic_table(holder, namespace)
	if(length(holder.rx?.activations)) // a granted capability can bring topic ops of its own (rare): this holder reads them in too
		by_key = by_key.Copy()
		for(var/datum/op_src/S as anything in op_sources_of(holder))
			var/datum/op_plan/P = S.oplan
			if(S.activation && !isnull(P.topic_key) && P.topic_namespace == namespace)
				by_key[P.topic_key] = P
	if(!length(by_key))
		return null
	for(var/key in href_list)
		if(!istext(key))
			continue
		var/value = href_list[key]
		var/datum/op_plan/found = istext(value) ? by_key["[key]=[value]"] : null
		found = found || by_key[key]
		if(found)
			return found
	return null

/// A Topic href as an op: the holder's topic op that names it (or the holder its topic_forward() hands the href to) runs for `actor`, through the same
/// path and the same refusals as a click. Returns its /datum/op_result, or null when no op names the href.
/proc/op_topic_href(mob/actor, datum/holder, list/href_list, forward_depth = 0, namespace = null)
	RETURN_TYPE(/datum/op_result)
	if(!actor || !isdatum(holder) || QDELETED(holder))
		return null
	var/datum/op_plan/P = op_topic_plan(holder, href_list, namespace)
	if(P)
		return op_topic_run(actor, holder, P, href_list)
	if(!isnull(namespace)) // a namespace has no forwards: its dispatch names the one holder
		return null
	var/datum/forward = holder.topic_forward()
	if(forward && forward != holder && forward_depth < OP_UI_FORWARD_DEPTH)
		return op_topic_href(actor, forward, href_list, forward_depth + 1)
	return null

/datum/input_event/click/proc/publish_compatibility_click()
	return

/mob/proc/op_compatibility_click(atom/target, params)
	return

/mob/proc/op_click_params(params)
	return null


/// Whether `token` is the admin token `actor` currently holds for this datum's links (req_topic_token()). Closed by default: a datum whose links carry a token
/// says how it is checked.
/datum/proc/op_topic_token_ok(mob/actor, token)
	return FALSE

/// Whether `actor` may use this datum's links at all (req_topic_ok()). Closed by default: a datum that gates its links says how.
/datum/proc/op_topic_actor_ok(mob/actor)
	return FALSE

/// A link refused by its holder's gate (MSG(op/topic_token) or MSG(op/topic_gate)), for the holder to report: a forged token is how exploit attempts show up.
/datum/proc/op_topic_refused(mob/actor, key, reason, list/href_list)
	return

/// A datum whose href actions this one's links also reach (a page forwarding to its book):
/// hrefs matching none of this type's rows are dispatched to it instead.
/datum/proc/topic_forward()
	return null

/// Resolve a typed href argument through the world-facing topic transport.
/datum/proc/op_topic_resolve_ref(raw, wanted, source)
	return null

/// Report a refused href to the administration transport.
/datum/proc/op_topic_rights_denied(mob/actor, key, wanted)
	return
