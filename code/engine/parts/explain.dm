// Explain tooling (doc/rewrite/final_api.html, section 8 "Explaining a resolution"; section 15 "Explain tooling"; section 19 "E2, parts").
//
// Every filter drops candidates silently, so the engine also says why. These read the origin list the table builder keeps for every entry
// (__FILE__:__LINE__, kept in every build, production included):
//
//   explain_click(actor, target, held, gesture)   every candidate, the filter that dropped it (with the entry's file:line), the winner, its tier and
//                                                 the tie-break that placed it, and any passes() chain
//   perform_op(actor, target, key, held, trace = TRUE)   the same path, with the trace printed
//   assert_resolves(actor, target, held, GESTURE_CLICK, "cover.open")   a unit-test helper
//   explain_type(/type)                           the merged op table (E1: code/engine/declare/explain.dm)
//
// The text is deterministic (types, not names or refs) so a test can compare it with a golden.

/// The tier a number stands for, by name.
/proc/op_tier_name(tier)
	switch(tier)
		if(OP_PRIORITY_SUBVERT)
			return "subvert"
		if(OP_PRIORITY_CLAW)
			return "claw"
		if(OP_PRIORITY_TAKE_OUT)
			return "take_out"
		if(OP_PRIORITY_ATTACK)
			return "attack"
		if(OP_PRIORITY_PART)
			return "part"
		if(OP_PRIORITY_NORMAL)
			return "normal"
		if(OP_PRIORITY_DEFAULT)
			return "default"
	return "[tier]"

/proc/op_intent_name(intent)
	switch(intent)
		if(INTENT_USE)
			return "use"
		if(INTENT_ATTACK)
			return "attack"
		if(INTENT_TOGGLE)
			return "toggle"
		if(INTENT_OPEN)
			return "open"
		if(INTENT_EJECT)
			return "eject"
		if(INTENT_DROP_ONTO)
			return "drop_onto"
		if(INTENT_EXAMINE)
			return "examine"
		if(INTENT_PRESENT)
			return "present"
	return "none"

/proc/op_origin_name(origin)
	switch(origin)
		if(ORIGIN_CLICK)
			return "click"
		if(ORIGIN_UI)
			return "ui"
		if(ORIGIN_MENU)
			return "menu"
		if(ORIGIN_VERB)
			return "verb"
		if(ORIGIN_HOTKEY)
			return "hotkey"
		if(ORIGIN_AI)
			return "ai"
		if(ORIGIN_SYSTEM)
			return "system"
	return "[origin]"

/// A candidate's one line: its key, binding, intent, tier, where it came from and what happened to it.
/proc/op_cand_line(datum/op_cand/C, datum/op_resolution/R, index, datum/op_cand/winner, list/passed_chain)
	var/binding_text = C.binding ? C.binding.describe() : "legacy"
	var/key = C.oplan ? C.oplan.key : "legacy:[C.legacy?.type]"
	var/origin_text = C.oplan ? C.oplan.origin : "legacy"
	var/line = "[index ? "[index]. " : ""][key] [binding_text] tier=[op_tier_name(C.tier)] side=[C.side == CAND_TARGET ? "target" : (C.side == CAND_HELD ? "held" : "actor")] @ [origin_text]"
	var/path_why = (!C.dropped_by && C.oplan?.space) ? op_cand_path_reason(R, C) : null
	if(C.oplan?.space)
		var/atom/T = (C.side == CAND_TARGET) ? R.target : C.holder
		line += " [istype(T) ? "path [space_path_text(T, C.oplan.space, R.actor, R.authority || AUTH_PHYSICAL)]" : ""]"
	if(path_why && C != winner && op_cand_catch_all(C))
		line += " -> dropped: a catch-all behind a closed door ([reason_text(path_why)])"
	else if(path_why && C != winner)
		line += " -> set aside: the path is blocked ([reason_text(path_why)]); it answers only when nothing else does"
	else if(path_why && C == winner)
		line += " -> WINNER but blocked: nothing else answers, so Require refuses with the blocking door's reason ([reason_text(path_why)])"
	else if(C.dropped_by)
		line += " -> dropped by [C.dropped_by]"
		if(C.dropped_reason)
			line += " ([reason_text(C.dropped_reason)])"
		else if(C.dropped_cond)
			line += " (condition [op_cond_text(C.dropped_cond)] was false)"
	else if(C == winner)
		line += " -> WINNER (placed: intent rank [C.rank || "-"], tier [op_tier_name(C.tier)], side [C.side == CAND_TARGET ? "target" : (C.side == CAND_HELD ? "held" : "actor")], declared [C.seq])"
	else
		line += " -> survives, after the winner"
	if(C.oplan?.passes)
		line += " (passes)"
	return line

/proc/op_cond_text(cond)
	if(islist(cond))
		var/list/parts = list()
		for(var/part in cond)
			parts += op_cond_text(part)
		return "([jointext(parts, " ")])"
	if(istype(cond, /datum/entry/part))
		var/datum/entry/part/P = cond
		return P.describe()
	return "[cond]"

/// The explain text of a resolution: one line per candidate in the order they were considered, then the winner.
/proc/op_explain_lines(datum/op_resolution/R)
	. = list()
	var/datum/op_cand/winner = op_resolution_winner(R)
	. += "explain: actor [R.actor?.type] target [R.target?.type] held [R.held ? R.held.type : "nothing"] origin [op_origin_name(R.origin)][R.gesture ? " gesture [R.gesture]" : ""]"
	if(R.gate_reason)
		. += "  actor gate: [reason_text(R.gate_reason)]"
	if(R.intents)
		var/list/names = list()
		for(var/intent in R.intents)
			names += op_intent_name(intent)
		. += "  intents: [length(names) ? jointext(names, ", ") : "none"]"
	. += "  candidates ([length(R.all)]):"
	var/index = 0
	for(var/datum/op_cand/C as anything in R.all)
		index++
		. += "    [op_cand_line(C, R, index, winner)]"
	if(winner)
		. += "  winner: [winner.oplan ? winner.oplan.key : "legacy"] (tier [op_tier_name(winner.tier)])"
		for(var/datum/op_cand/C as anything in R.ordered)
			if(C != winner && op_cand_when(R, C) && winner.oplan?.passes)
				. += "  passes() chain: then [C.oplan.key]"
				break
	else
		. += "  winner: none"
		if(R.near_miss)
			. += "  near miss: [R.near_miss.oplan.key]: [reason_text(R.near_miss.dropped_reason)]"

/// explain_click(): the explanation of a click as text lines (one string, newline separated), or a list when `as_list`.
/proc/explain_click(mob/actor, atom/target, obj/item/held, gesture = GESTURE_CLICK, as_list = FALSE)
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_CLICK, actor_authority(actor), gesture, null, TRUE, TRUE)
	var/list/lines = op_explain_lines(R)
	return as_list ? lines : jointext(lines, "\n")

/// Asserts in a unit test that a click resolves to `key`. Returns TRUE when it does; a test calls it inside TEST_ASSERT.
/proc/assert_resolves(mob/actor, atom/target, obj/item/held, gesture, key)
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_CLICK, actor_authority(actor), gesture, null, TRUE)
	var/datum/op_cand/winner = op_resolution_winner(R)
	return !!winner && winner.oplan?.key == key

/// A pending op, printed: who waits on what, at which step, under which origin.
/proc/op_pending_line(datum/pending_op/P)
	var/list/lines = list("[P.actor || "something"] is waiting on [P.key] (step [P.cursor - 1] of [length(P.oplan.steps)], origin [op_origin_name(P.origin)])")
	if(P.request)
		lines += "  open request: [P.request.type]"
	if(length(P.watching))
		lines += "  watching [length(P.watching)] reads"
	return jointext(lines, "\n")

/// The pending ops of an actor, printed ("List Pending Ops"), oldest first.
/proc/op_pending_text(mob/actor)
	var/list/blocks = list()
	for(var/datum/pending_op/P as anything in op_pendings_of(actor))
		blocks += op_pending_line(P)
	if(!length(blocks))
		return "[actor] has no pending op"
	return jointext(blocks, "\n")

/// Every pending op in the world, one block each (the system-origin ones too).
/proc/op_pending_all_text()
	var/list/blocks = list()
	for(var/ref in GLOB.op_pending_all)
		var/datum/pending_op/P = GLOB.op_pending_all[ref]
		if(P?.active && !QDELETED(P))
			blocks += op_pending_line(P)
	return length(blocks) ? jointext(blocks, "\n") : "no pending ops"

// ---- the admin verbs ----
// "Explain Type" (the merged table of a type, each entry with its file:line), "Explain Interaction" (every candidate of a click on a thing and the filter
// that dropped each), "List Pending Ops" (every wait in the world) and, in code/engine/declare/explain.dm, "List Activations".

ADMIN_VERB_AND_CONTEXT_MENU(e2_explain_type, R_DEBUG, "Explain Type", "The merged declaration table of a thing's type: every capability and entry, with the file and line that declared it.", ADMIN_CATEGORY_DEBUG, atom/target in world)
	to_chat(user, "<b>Table of [target.type]</b><br>[replacetext(explain_type(target.type) || "no table", "\n", "<br>")]")

ADMIN_VERB_AND_CONTEXT_MENU(e2_explain_interaction, R_DEBUG, "Explain Interaction", "Every candidate op of a click on a thing with what you hold, the filter that dropped each, and the winner.", ADMIN_CATEGORY_DEBUG, atom/target in view())
	var/mob/actor = user.mob
	if(!actor)
		return
	to_chat(user, "<b>Click on [target] ([target.type])</b><br>[replacetext(explain_click(actor, target, actor.held_for_ops(), GESTURE_CLICK), "\n", "<br>")]")

ADMIN_VERB(e2_list_pending_ops, R_DEBUG, "List Pending Ops", "Every op that is waiting in the world: who, what, which step, and the request it is waiting on.", ADMIN_CATEGORY_DEBUG)
	to_chat(user, "<b>Pending ops</b><br>[replacetext(op_pending_all_text(), "\n", "<br>")]")
