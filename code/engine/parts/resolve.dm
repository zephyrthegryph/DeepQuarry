// Resolution (doc/rewrite/final_api.html, section 8 "Resolution", "Resolution cost", "Explaining a resolution"; section 19 "E2, parts").
//
// Every client input first becomes a typed event in the input inbox (E6) and resolves here when the inbox drains it. Candidates come from three
// places: the target's ops (its type table plus every activation on it), the held item's at_target ops, and the actor's own ops. The filters,
// in order, are the Match stage and drop a candidate silently:
//
//   step 0   the actor gate: the origin the input arrived on must be in the actor's acts_via (ORIGIN_SYSTEM is exempt);
//            one of the op's bindings accepts the origin and the authority in use;
//   step 0.5 the providers and the reach gate;
//   the intent the gesture means, and the binding's own input (the held item is of the type item(T) names, a tool of quality Q);
//   the op's when conditions hold.
//
// Order: the bind profile's intent list, then the op's tier, then target before held before actor, then the more specific held-item binding
// (an item type narrower than /obj, then a tool quality, then a broad item), then declaration order; an explicit priority(above/below)
// or click_order() moves an op over all of that. The first candidate runs through Require, Wait and Do. If Require refuses the player sees the reason and the input never
// falls through; only Match failures fall through. If nothing survives and a gate dropped something, the engine shows the best near-miss's reason.
//
// Two passes keep the cost flat as candidates grow: pass 1 builds the ordered list with the cheap gates and runs no requirement code, pass 2
// tests when conditions until one holds. Menus and screentips run needs() lazily for every candidate under a budget.

/// One (op, binding) pair that might answer an input, and why it was dropped when it was.
/datum/op_cand
	var/datum/op_plan/oplan
	var/datum/entry/part/bind/binding
	/// The entity whose entry runs (the target, the held item, the actor), and where it sits.
	var/datum/holder
	var/side = CAND_TARGET
	var/datum/activation/activation
	var/datum/capability/cap
	/// The matched intent's position in the gesture's list (lower first), and the intent itself.
	var/rank = 0
	var/intent
	/// The provider chosen by the reach gate.
	var/datum/prov/provider
	/// A legacy interaction wrapped as a candidate (a /datum/interaction), or null.
	var/datum/legacy
	/// The filter that dropped it (GATE_*), the reason that filter gave, and the condition that was false.
	var/dropped_by
	var/dropped_reason
	var/dropped_cond
	/// The tier it sits at.
	var/tier = OP_PRIORITY_NORMAL
	/// The type its item() or stack() binding takes, or null.
	var/item_type
	/// How specific its binding is about the held item (op_binding_specificity): 0 for a binding that names no held item.
	var/specificity = 0
	var/seq = 0

/// What one resolution found: every candidate with the filter that dropped it, the ordered survivors and the winner.
/datum/op_resolution
	var/mob/actor
	var/atom/target
	var/obj/held
	var/origin
	var/authority
	var/gesture
	var/list/intents
	/// Every candidate considered, dropped or not.
	var/list/all
	/// The survivors in order.
	var/list/ordered
	/// The best near-miss when nothing survived: the highest-ranked candidate the origin, provider or reach filter dropped.
	var/datum/op_cand/near_miss
	/// The gate that dropped candidates before any was a candidate (the actor gate's reason), or null.
	var/gate_reason

// ---- the ops an entity has ----

/// An op an entity has now: the plan, and the activation that brought it (null for a type-level op).
/datum/op_src
	var/datum/op_plan/oplan
	var/datum/activation/activation

/// Every op plan of an entity: its type's, and the ones of capabilities granted to it. A fresh list.
/proc/op_plans_of(datum/D)
	. = list()
	for(var/datum/op_src/S as anything in op_sources_of(D))
		. += S.oplan

/// The ops an entity has with the activation that brought each. A granted capability whose activation does not run (stacking: another beat
/// it) brings none.
/proc/op_sources_of(datum/D)
	. = list()
	if(!D || QDELETED(D))
		return
	var/datum/type_table/T = table_of(D)
	var/datum/op_index/index = op_index_of_table(T)
	for(var/datum/op_plan/P as anything in index.ordered)
		var/datum/op_src/S = new
		S.oplan = P // ALLOW(ownership): a transient record of one resolution: dropped with it
		. += S
	for(var/datum/activation/A as anything in D.rx?.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		var/datum/op_index/granted = op_index_of_def(T, A.def)
		for(var/datum/op_plan/P as anything in granted.ordered)
			var/datum/op_src/S = new
			S.oplan = P // ALLOW(ownership): a transient record of one resolution: dropped with it
			S.activation = A // ALLOW(ownership): a transient record of one resolution: dropped with it
			. += S

/// The plan of `key` an entity has, or null; `activation` is set to the one that brought it.
/proc/op_plan_for(datum/D, key, list/found_activation)
	RETURN_TYPE(/datum/op_plan)
	if(!D || QDELETED(D))
		return null
	var/datum/type_table/T = table_of(D)
	var/datum/op_plan/P = op_index_of_table(T).by_key[key]
	if(P)
		return P
	for(var/datum/activation/A as anything in D.rx?.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		P = op_index_of_def(T, A.def).by_key[key]
		if(P)
			found_activation += A
			return P
	return null

// ---- intents ----

/// The intents a gesture means for this actor, in order: the bind profile's intent list.
/proc/op_intents_for(mob/actor, gesture)
	switch(gesture)
		if(GESTURE_CLICK, GESTURE_SELF)
			if(actor && STANCE_IS_HOSTILE(actor.op_input_stance()))
				return list(INTENT_ATTACK, INTENT_USE)
			return list(INTENT_USE)
		if(GESTURE_ALT)
			return list(INTENT_TOGGLE, INTENT_OPEN, INTENT_EJECT)
		if(GESTURE_SHIFT)
			return list(INTENT_EXAMINE)
		if(GESTURE_DRAG)
			return list(INTENT_DROP_ONTO)
		if(GESTURE_CTRL, GESTURE_MIDDLE, GESTURE_RIGHT)
			// No intent of its own: the gesture is its own token, so only an op that pins it (gesture(GESTURE_CTRL)) answers it. A right click is never a player's gesture here (it opens the menu); a call that stands for one, the
			// secondary use of a tool (try_interaction()), resolves it so.
			return list(gesture)
	return list()

/// The intents an op answers through a binding: answers() when written, else what the binding implies.
/proc/op_answers(datum/op_plan/P, datum/entry/part/bind/B)
	var/list/chosen = LAZYACCESS(P.selects, "answers")
	if(length(chosen))
		return chosen
	switch(B.bind_kind)
		if(BIND_MENU, BIND_UI, BIND_TOPIC, BIND_AI)
			return list()
	// An op that pins a gesture (a drag, an alt-click) answers the intents that gesture means: the pin alone is enough to be matched by it.
	var/pinned = LAZYACCESS(P.selects, "gesture")
	if(!isnull(pinned))
		return op_intents_for(null, pinned)
	var/list/implied = list(INTENT_USE)
	if(P.toggles && B.bind_kind == BIND_HAND)
		implied += INTENT_TOGGLE
	if(LAZYACCESS(P.selects, "presents"))
		implied = list(INTENT_PRESENT)
	return implied

// ---- candidate collection ----

/// The input's own match of a binding: does this (actor, target, held) fit what the binding asks for? Silent.
/proc/op_binding_fits(datum/entry/part/bind/B, mob/actor, datum/target, obj/held, datum/holder, side)
	switch(B.bind_kind)
		if(BIND_TOOL)
			if(!op_item_like(held) || side != CAND_TARGET)
				return FALSE
			for(var/quality in B.args["quality"])
				if(held.op_tool_quality(quality))
					return TRUE
			return FALSE
		if(BIND_ITEM, BIND_STACK)
			// an item used on itself is its in_hand() use, never an item() of its own (the old attackby never ran on itself)
			return side == CAND_TARGET && !isnull(held) && held != target && istype(held, B.args["type"])
		if(BIND_IN_HAND)
			return !isnull(held) && held == holder && target == held
		if(BIND_AT_TARGET)
			if(side != CAND_HELD || isnull(held) || holder != held || target == held)
				return FALSE
			var/filter = B.args["filter"]
			return isnull(filter) || istype(target, filter)
		if(BIND_INSIDE)
			return side == CAND_TARGET
		if(BIND_HAND, BIND_REMOTE)
			return side == CAND_TARGET
		if(BIND_TK)
			// telekinesis answers what no hand reaches: a target next to the actor (or on it) is the hand's, as the old tk adapter ran only for a ranged click
			if(side != CAND_TARGET || !actor || !isatom(target))
				return FALSE
			var/atom/far = target
			return far.loc != actor && !far.Adjacent(actor)
		if(BIND_MENU, BIND_AI)
			return TRUE // chosen by key: the actor's own op (an ability, a natural weapon) is reached from either side
		if(BIND_CLICKS)
			return side == CAND_ACTOR // the actor's own op, reached by its click on the target
	return side == CAND_TARGET

// ---- the candidate index: rows interned by (origin, authority, gesture, intents, side, held type) ----
//
// What a binding can answer is mostly decided by facts that are the same for every input of one shape: the origin and authority it came through,
// the gesture and the intents it means, which side of the input the entry sits on, and the TYPE of the held item (an item(T) or stack(T) binding
// fits a held item by its type). A type table therefore interns, per such signature, the (op, binding) rows that can still answer, in declaration
// order; a resolution walks those rows instead of every op of the type. The facts that need the instance (a tool's quality, whether the held item is
// the holder, the target of an at_target filter, reach, conditions) are asked of the surviving rows exactly as before, so the result is the one a
// walk of every op would give.

/// One (op, binding) pair of a type-level plan.
/datum/op_row
	var/datum/op_plan/oplan
	var/datum/entry/part/bind/binding

/datum/type_table
	/// signature -> list of /datum/op_row: the interned candidate rows of this table's own ops.
	var/list/op_row_cache

/// Interned candidate rows whose silent drops (the ones every input of this shape shares) are applied. In declaration order.
/proc/op_rows_for(datum/type_table/T, datum/op_index/index, side, origin, authority, gesture, list/intents, held_type)
	var/signature = "[side]|[origin]|[authority]|[isnull(gesture) ? "-" : gesture]|[intents ? jointext(intents, ",") : "-"]|[held_type || "-"]"
	var/list/rows = T.op_row_cache?[signature]
	if(!isnull(rows))
		return rows
	rows = list()
	for(var/datum/op_plan/P as anything in index.ordered)
		for(var/datum/entry/part/bind/B as anything in P.bindings)
			if(!op_row_maybe(P, B, side, origin, authority, gesture, intents, held_type))
				continue
			var/datum/op_row/row = new
			row.oplan = P // ALLOW(ownership): an interned row of a compiled table: dropped with it
			row.binding = B // ALLOW(ownership): an interned row of a compiled table: dropped with it
			rows += row
	LAZYSET(T.op_row_cache, signature, rows)
	return rows

/// Could (op, binding) answer an input of this shape? FALSE only when the shared facts drop it silently: the side, the binding kind, the intents and
/// the held item's type. A candidate the origin or authority refuses is kept (it can be the near miss that explains a refusal).
/proc/op_row_maybe(datum/op_plan/P, datum/entry/part/bind/B, side, origin, authority, gesture, list/intents, held_type)
	if(!op_accepts_origin(P, B, origin))
		return TRUE
	if(origin != ORIGIN_SYSTEM && !op_accepts_authority(P, B, authority))
		return TRUE
	if(side == CAND_ACTOR && !op_actor_side_binding(B))
		return FALSE
	if(origin != ORIGIN_SYSTEM || !isnull(gesture))
		switch(B.bind_kind)
			if(BIND_TOOL)
				if(!held_type || side != CAND_TARGET)
					return FALSE
			if(BIND_ITEM, BIND_STACK)
				if(side != CAND_TARGET || !held_type || !ispath(held_type, B.args["type"]))
					return FALSE
			if(BIND_IN_HAND)
				if(!held_type)
					return FALSE
			if(BIND_AT_TARGET)
				if(side != CAND_HELD || !held_type)
					return FALSE
			if(BIND_MENU)
				pass()
			if(BIND_CLICKS)
				if(side != CAND_ACTOR)
					return FALSE
			else
				if(side != CAND_TARGET)
					return FALSE
	if(!isnull(gesture))
		if(B.bind_kind in list(BIND_MENU, BIND_UI, BIND_TOPIC, BIND_AI))
			return FALSE
		var/list/answered = op_answers(P, B)
		var/matched = FALSE
		for(var/intent in intents)
			if(intent in answered)
				matched = TRUE
				break
		if(!matched)
			return FALSE
	return TRUE

/// Can an op with this binding be a candidate on the actor's side? An actor's own menu and ai ops are chosen by key; a clicks() op is reached by the click.
/proc/op_actor_side_binding(datum/entry/part/bind/B)
	return B.bind_kind == BIND_MENU || B.bind_kind == BIND_AI || B.bind_kind == BIND_CLICKS

/// Adds the candidates of one side of an input (the target's, the held item's or the actor's own ops) to the resolution. `seq` is the running
/// declaration counter; the new value is returned.
/proc/op_collect_side(datum/op_resolution/R, datum/holder, side, key, gesture, keep_dropped, seq)
	var/datum/type_table/T = table_of(holder)
	var/datum/op_index/index = op_index_of_table(T)
	var/list/rows = null
	if(key)
		var/datum/op_plan/named = index.by_key[key]
		rows = list()
		if(named)
			for(var/datum/entry/part/bind/B as anything in named.bindings)
				var/datum/op_row/row = new
				row.oplan = named // ALLOW(ownership): a transient record of one resolution: dropped with it
				row.binding = B // ALLOW(ownership): a transient record of one resolution: dropped with it
				rows += row
	else if(keep_dropped)
		rows = list()
		for(var/datum/op_plan/P as anything in index.ordered)
			for(var/datum/entry/part/bind/B as anything in P.bindings)
				var/datum/op_row/row = new
				row.oplan = P // ALLOW(ownership): a transient record of one resolution: dropped with it
				row.binding = B // ALLOW(ownership): a transient record of one resolution: dropped with it
				rows += row
	else
		rows = op_rows_for(T, index, side, R.origin, R.authority, gesture, R.intents, R.held?.type)
	for(var/datum/op_row/row as anything in rows)
		seq++
		seq = op_add_cand(R, row.oplan, row.binding, holder, side, null, gesture, keep_dropped, seq)
	// The capabilities granted to the holder at runtime bring their own ops (a shadowed activation brings none).
	for(var/datum/activation/A as anything in holder.rx?.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		var/datum/op_index/granted = op_index_of_def(T, A.def)
		for(var/datum/op_plan/P as anything in granted.ordered)
			if(key && P.key != key)
				continue
			for(var/datum/entry/part/bind/B as anything in P.bindings)
				seq++
				seq = op_add_cand(R, P, B, holder, side, A, gesture, keep_dropped, seq)
	return seq

/// One (op, binding) as a candidate of the resolution, unless the shared and per-input silent filters drop it. Returns the running counter.
/proc/op_add_cand(datum/op_resolution/R, datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, datum/activation/granted_by, gesture, keep_dropped, seq)
	if(!keep_dropped && !R.gate_reason && op_silently_dropped(R, P, B, holder, side, gesture))
		return seq
	var/datum/op_cand/C = new
	C.oplan = P // ALLOW(ownership): a transient record of one resolution: dropped with it
	C.binding = B // ALLOW(ownership): a transient record of one resolution: dropped with it
	C.holder = holder // ALLOW(ownership): a transient record of one resolution: dropped with it
	C.side = side
	C.activation = granted_by // ALLOW(ownership): a transient record of one resolution: dropped with it
	C.cap = granted_by ? granted_by.def : P.owner_def
	C.tier = P.tier
	if(B.bind_kind == BIND_ITEM || B.bind_kind == BIND_STACK)
		C.item_type = B.args["type"]
	C.specificity = op_binding_specificity(B)
	C.seq = seq
	R.all += C // ALLOW(ownership): a transient record of one resolution: dropped with it
	op_cand_pass1(R, C, gesture)
	if(!C.dropped_by)
		R.ordered += C // ALLOW(ownership): a transient record of one resolution: dropped with it
	return seq

/// Builds the candidate list of an input. `gesture` null means a pick by key or a menu read (no intent filter). Pass 1: cheap gates only.
/proc/op_resolve(mob/actor, atom/target, obj/held, origin, authority, gesture = null, key = null, include_legacy = FALSE, keep_dropped = FALSE)
	RETURN_TYPE(/datum/op_resolution)
	// A resolution that names a key, or explains itself, keeps every candidate and the filter that dropped it; the rest never allocate a
	// candidate for one the binding's own input or the intent drops silently.
	keep_dropped ||= !isnull(key)
	var/datum/op_resolution/R = new
	R.actor = actor // ALLOW(ownership): a transient record of one resolution: dropped with it
	R.target = target // ALLOW(ownership): a transient record of one resolution: dropped with it
	R.held = held // ALLOW(ownership): a transient record of one resolution: dropped with it
	R.origin = origin
	R.authority = authority
	R.gesture = gesture
	R.intents = isnull(gesture) ? null : op_intents_for(actor, gesture)
	R.all = list()
	R.ordered = list()
	R.gate_reason = actor_gate_reason(actor, origin, authority)
	var/seq = 0
	if(target && !QDELETED(target))
		seq = op_collect_side(R, target, CAND_TARGET, key, gesture, keep_dropped, seq)
	if(held && !QDELETED(held))
		seq = op_collect_side(R, held, CAND_HELD, key, gesture, keep_dropped, seq)
	if(actor && !QDELETED(actor) && actor != target)
		seq = op_collect_side(R, actor, CAND_ACTOR, key, gesture, keep_dropped, seq)
	if(include_legacy)
		input_compatibility().compatibility_candidates(R)
	op_resolution_sort(R)
	if(!length(R.ordered))
		for(var/datum/op_cand/C as anything in R.all)
			if(C.dropped_by in list(GATE_ORIGIN, GATE_PROVIDER, GATE_REACH))
				if(!R.near_miss || op_cand_better(C, R.near_miss))
					R.near_miss = C // ALLOW(ownership): a transient record of one resolution: dropped with it
	return R

/// Would pass 1 drop this (op, binding) at the binding's own input or the intent, which are silent and the same for every input of that kind?
/// (Only after the origin and authority filters accepted it: those drops are kept for the near-miss reason.)
/proc/op_silently_dropped(datum/op_resolution/R, datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, gesture)
	if(!op_accepts_origin(P, B, R.origin))
		return FALSE
	if(R.origin != ORIGIN_SYSTEM && !op_accepts_authority(P, B, R.authority))
		return FALSE
	if(side == CAND_ACTOR && !op_actor_side_binding(B))
		return TRUE
	if((R.origin != ORIGIN_SYSTEM || !isnull(gesture)) && !op_binding_fits(B, R.actor, R.target, R.held, holder, side))
		return TRUE
	if(!isnull(gesture))
		if(B.bind_kind in list(BIND_MENU, BIND_UI, BIND_TOPIC, BIND_AI))
			return TRUE
		var/matched = FALSE
		var/list/answered = op_answers(P, B)
		for(var/intent in R.intents)
			if(intent in answered)
				matched = TRUE
				break
		if(!matched)
			return TRUE
	return FALSE

/// Pass 1 for one candidate: origin, authority, binding input, intent, then provider and reach. Sets dropped_by on the first filter that fails.
/proc/op_cand_pass1(datum/op_resolution/R, datum/op_cand/C, gesture)
	var/datum/op_plan/P = C.oplan
	var/datum/entry/part/bind/B = C.binding
	if(R.gate_reason)
		C.dropped_by = GATE_ACTOR
		C.dropped_reason = R.gate_reason
		return
	if(!op_accepts_origin(P, B, R.origin))
		C.dropped_by = GATE_ORIGIN
		C.dropped_reason = /datum/msg/op/no_binding
		return
	if(R.origin != ORIGIN_SYSTEM && !op_accepts_authority(P, B, R.authority))
		C.dropped_by = GATE_ORIGIN
		C.dropped_reason = /datum/msg/op/no_binding
		return
	if(R.origin != ORIGIN_SYSTEM && R.origin == ORIGIN_MENU && B.bind_kind == BIND_MENU && C.side == CAND_ACTOR && !isnull(R.target) && R.target != R.actor)
		// an actor's own menu() op is the Abilities entry, not a target's menu line
		C.dropped_by = GATE_MATCH
		return
	var/datum/target = (C.side == CAND_ACTOR) ? R.actor : R.target
	if(C.side == CAND_ACTOR && !op_actor_side_binding(B))
		C.dropped_by = GATE_MATCH
		return
	if(R.origin != ORIGIN_SYSTEM || !isnull(gesture))
		if(!op_binding_fits(B, R.actor, R.target, R.held, C.holder, C.side))
			C.dropped_by = GATE_MATCH
			return
	// the gesture's intent
	if(!isnull(gesture))
		if(B.bind_kind in list(BIND_MENU, BIND_UI, BIND_TOPIC, BIND_AI))
			C.dropped_by = GATE_MATCH
			return
		var/list/answered = op_answers(P, B)
		var/best = null
		for(var/i in 1 to length(R.intents))
			if(R.intents[i] in answered)
				best = i
				C.intent = R.intents[i]
				break
		if(isnull(best))
			C.dropped_by = GATE_MATCH
			return
		C.rank = best
		var/list/stances = LAZYACCESS(P.selects, "stance")
		if(length(stances) && !(R.actor?.op_input_stance() in stances))
			C.dropped_by = GATE_MATCH
			return
		var/pinned = LAZYACCESS(P.selects, "gesture")
		if(!isnull(pinned) && pinned != gesture)
			C.dropped_by = GATE_MATCH
			return
	// providers and the reach gate (not for the game acting for itself). A REACH_ANY op still needs its provider when its binding names an affordance
	// (observer(): only a ghost provides AFF_OBSERVE); the gate then runs no spatial step.
	if(R.origin != ORIGIN_SYSTEM && (op_reach_policy(P, B) != REACH_ANY || op_affordance(P, B, R.held)))
		var/atom/aim = (C.side == CAND_ACTOR && B.bind_kind != BIND_CLICKS) ? R.actor : R.target
		var/list/chosen = list()
		var/why = reach_gate(R.actor, aim, R.held, P, B, R.authority, chosen)
		if(why)
			C.dropped_by = (why == /datum/msg/op/no_hands) ? GATE_PROVIDER : GATE_REACH
			C.dropped_reason = why
			return
		if(length(chosen))
			C.provider = chosen[1] // ALLOW(ownership): a transient record of one resolution: dropped with it

/// Pass 2 for one candidate: its when conditions, in the context the op would run in. Sets dropped_by = GATE_MATCH and dropped_cond when one is false.
/proc/op_cand_when(datum/op_resolution/R, datum/op_cand/C)
	if(C.legacy || !length(C.oplan.conds))
		return TRUE
	var/datum/act/op/A = op_act_for(C, R.actor, R.target, R.held, R.origin, R.authority)
	var/ok = TRUE
	for(var/cond in C.oplan.conds)
		if(!op_cond(A, cond))
			C.dropped_by = GATE_MATCH
			C.dropped_cond = cond
			ok = FALSE
			break
	A.release()
	return ok

/// The order candidates answer in.
/proc/op_cand_better(datum/op_cand/A, datum/op_cand/B)
	// the gates a candidate got past: the one that got further is the better near-miss
	var/static/list/depth = list(GATE_ACTOR = 1, GATE_ORIGIN = 2, GATE_PROVIDER = 3, GATE_REACH = 4)
	return (depth[A.dropped_by] || 0) > (depth[B.dropped_by] || 0)

/// Sorts the survivors: intent rank, tier, then target before held before actor, then binding specificity, then declaration order; then explicit
/// relative priorities and click orders, which win over all of these.
/proc/op_resolution_sort(datum/op_resolution/R)
	var/list/sorted = list()
	for(var/datum/op_cand/C as anything in R.ordered)
		var/position = length(sorted) + 1
		for(var/i in 1 to length(sorted))
			if(op_cand_precedes(C, sorted[i]))
				position = i
				break
		sorted.Insert(position, C)
	op_specificity_sort(sorted)
	// priority(above(key)) / priority(below(key)): moved next to the named candidate whatever the tiers
	var/list/chained = null
	for(var/datum/op_cand/C as anything in sorted.Copy())
		var/list/rel = C.oplan.priority_rel
		var/datum/op_cand/anchor = null
		var/placement = "above"
		if(length(rel))
			placement = rel[1]
			for(var/datum/op_cand/O as anything in sorted)
				if(O != C && O.oplan.key == rel[2])
					anchor = O
					break
		else if(C.oplan.click_below)
			LAZYADD(chained, C)
			continue
		if(!anchor)
			continue
		sorted -= C
		var/at = sorted.Find(anchor)
		sorted.Insert(placement == "above" ? at : at + 1, C)
	// canonical click orders (click_order()): the lowest rank first, so each op lands just above one already in its place and an order's ops end up
	// together, top to bottom
	while(length(chained))
		var/datum/op_cand/C = chained[1]
		for(var/datum/op_cand/other as anything in chained)
			if(op_click_depth(other) < op_click_depth(C))
				C = other
		chained -= C
		var/datum/op_cand/anchor = op_click_anchor(C, sorted)
		if(!anchor)
			continue
		sorted -= C
		sorted.Insert(sorted.Find(anchor), C)
	R.ordered = sorted

/// How many ranks a click order puts below the candidate (the fewest, over its orders).
/proc/op_click_depth(datum/op_cand/C)
	. = INFINITY
	for(var/list/chain as anything in C.oplan.click_below)
		. = min(., length(chain) - 1)

/// The candidate a canonical click_order() puts C just above: of the same holder, answering the order's input, the nearest key after C's in the
/// order (the next one the holder has). null: none.
/proc/op_click_anchor(datum/op_cand/C, list/sorted)
	for(var/list/chain as anything in C.oplan.click_below)
		var/input = chain[1]
		for(var/i in 2 to length(chain))
			for(var/datum/op_cand/O as anything in sorted)
				if(O != C && O.holder == C.holder && op_key_matches(O.oplan.key, chain[i]) && op_plan_takes_input(O.oplan, input))
					return O
	return null

/// How specific a binding is about the held item, for op_specificity_sort: of two candidates answering one input at one intent and tier, on
/// one side, the more specific binding answers first. 0: the binding names no held item (hand(), in_hand(), at_target(), ...), and is not
/// compared. Inventory-specific ranks come from the library: a broad inventory item ranks below a tool quality,
/// and a narrower inventory item ranks above it by its declared type depth. Other dragged types rank zero.
/proc/op_binding_specificity(datum/entry/part/bind/B)
	switch(B.bind_kind)
		if(BIND_TOOL)
			return 2
		if(BIND_ITEM, BIND_STACK)
			return operation_compatibility().item_specificity(B.args["type"])
	return 0

/// Binding specificity: within each run of candidates tied on intent rank, tier and side, the held-item bindings (op_binding_specificity
/// above 0) are reordered most specific first, stably, in the slots they already hold; a binding that names no held item keeps its slot, so
/// specificity orders only held-item bindings against each other and the order stays a total one.
/proc/op_specificity_sort(list/sorted)
	var/n = length(sorted)
	var/start = 1
	while(start <= n)
		var/datum/op_cand/first = sorted[start]
		var/stop = start
		while(stop < n)
			var/datum/op_cand/next = sorted[stop + 1]
			if(next.rank != first.rank || next.tier != first.tier || next.side != first.side)
				break
			stop++
		if(stop > start)
			var/list/slots = list()
			var/list/held = list()
			for(var/i in start to stop)
				var/datum/op_cand/C = sorted[i]
				if(C.specificity)
					slots += i
					// stable insertion: after every candidate at least as specific
					var/at = length(held) + 1
					for(var/j in 1 to length(held))
						var/datum/op_cand/O = held[j]
						if(C.specificity > O.specificity)
							at = j
							break
					held.Insert(at, C)
			for(var/k in 1 to length(slots))
				sorted[slots[k]] = held[k]
		start = stop + 1

/// Does candidate A come before B?
/proc/op_cand_precedes(datum/op_cand/A, datum/op_cand/B)
	if(A.rank != B.rank)
		return A.rank < B.rank
	if(A.tier != B.tier)
		return A.tier > B.tier
	if(A.side != B.side)
		return A.side < B.side
	return A.seq < B.seq

// ---- the act a candidate runs in ----

/// A pooled op context for candidate C and an input: the fields a requirement or a condition reads. The caller releases it.
/proc/op_act_for(datum/op_cand/C, mob/actor, datum/target, obj/held, origin, authority)
	RETURN_TYPE(/datum/act/op)
	var/datum/act/op/A = take(/datum/act/op)
	A.key = C.oplan.key
	A.holder = C.holder // ALLOW(ownership): a pooled transient: reset on release
	A.cap = C.cap
	A.activation = C.activation // ALLOW(ownership): a pooled transient: reset on release
	A.source = C.activation ? C.activation.source : C.holder // ALLOW(ownership): a pooled transient: reset on release
	A.actor = actor
	A.set_held_provider(held)
	// An op with no target binding has A.target = A.holder (an actor's own op, a self ui_act()).
	// An actor-side op that declares a reach (a natural weapon's bite) is aimed at what the input addressed.
	var/aimed = C.side == CAND_ACTOR && !isnull(target) && target != actor && (!isnull(LAZYACCESS(C.oplan.selects, "reach")) || C.binding?.bind_kind == BIND_CLICKS)
	A.target = ((C.side == CAND_ACTOR && !aimed) || isnull(target)) ? C.holder : target
	if(istype(A.target, /atom))
		A.target_atom = A.target // ALLOW(ownership): a pooled transient: reset on release
	A.origin = origin
	A.authority = authority
	A.provider = C.provider?.source
	return A

// ---- pass 2 and the winner ----

/// Runs pass 2 over the survivors in order and returns the candidates whose when conditions hold, best first.
/proc/op_resolution_matches(datum/op_resolution/R)
	. = list()
	for(var/datum/op_cand/C as anything in R.ordered)
		if(op_cand_when(R, C))
			. += C

/// The winner of a click: the first survivor whose conditions hold and whose path is open. The silent-or-refuse rule of spaces (section 8): a
/// candidate placed at(SPACE_X) behind a closed door is set aside while another candidate answers the same input; when none does, the first
/// one set aside wins, and Require refuses it with the blocking door's reason.
/proc/op_resolution_winner(datum/op_resolution/R)
	RETURN_TYPE(/datum/op_cand)
	var/datum/op_cand/set_aside = null
	for(var/datum/op_cand/C as anything in R.ordered)
		if(!op_cand_when(R, C))
			continue
		if(op_cand_path_reason(R, C))
			// A catch-all (item(/obj): set anything down inside, swallow anything) behind a closed door claims nothing: it is dropped as if
			// its door were a when(), so the click goes on to what the held thing does by itself (package wrap on a shut locker).
			if(!op_cand_catch_all(C))
				set_aside ||= C
			continue
		// The held thing was meant for the space (a cell for its bay): a later candidate that ignores what is held (an empty-hand touch, the
		// window) does not answer the same input, so the blocked one stands and Require gives the door's reason.
		if(set_aside && R.held && op_cand_takes_held(set_aside) && !op_cand_takes_held(C))
			return set_aside
		return C
	return set_aside

/// Is candidate C a catch-all: its item() binding takes any item or movable?
/proc/op_cand_catch_all(datum/op_cand/C)
	return operation_compatibility().broad_item_type(C.item_type) || C.item_type == /atom/movable || C.item_type == /obj

/// Does candidate C's binding take the held thing (item(), tool(), stack(), in_hand())? A hand() binding answers whatever is held.
/proc/op_cand_takes_held(datum/op_cand/C)
	return C.binding && (C.binding.bind_kind in list(BIND_ITEM, BIND_TOOL, BIND_STACK, BIND_IN_HAND, BIND_AT_TARGET))

/// Why candidate C's path is blocked (the op is placed at a space of the target that a door on the way keeps shut), or null.
/proc/op_cand_path_reason(datum/op_resolution/R, datum/op_cand/C)
	var/space_id = C.oplan?.space
	if(isnull(space_id) || R.origin == ORIGIN_SYSTEM)
		return null
	var/atom/T = (C.side == CAND_TARGET) ? R.target : C.holder
	return istype(T) ? T.space_reason(space_id, R.authority, R.actor) : null

/// The text label of an op: label("Text"), else its key's last segment, spaced.
/proc/op_label(datum/op_plan/P)
	if(P.label)
		return P.label
	var/key = P.key
	var/at = findlasttext(key, ".")
	if(at)
		key = copytext(key, at + 1)
	var/colon = findtext(key, ":")
	if(colon)
		key = copytext(key, 1, colon)
	return capitalize(replacetext(key, "_", " "))

// ---- the menu and the screentip ----

/// The menus read so far: key -> list(rows, time stamp or null). The key is (actor, target, held, the act generation of each of the three, the actor's
/// provider set generation), the ids never reused (a ref would be). An entity's act generation bumps when a published key, a relation, a stat, its place or
/// its contents change (op_changed()), and the provider set generation when an activation with provides attaches or detaches, so a stale read never
/// matches: the key itself is what changed. Only a menu that shows a cooldown also carries the time it was read at (a cooldown ends with no publication).
// Temporary synchronous read scope: list(parent frame, encountered read_once).
GLOBAL_LIST(op_menu_read_frame)
GLOBAL_LIST_EMPTY(op_menu_cache) // ALLOW(cache): keyed by generations, so a state change makes the old entry unreachable; bounded by OP_MENU_CACHE_MAX
#define OP_MENU_CACHE_MAX 512
/// Menus built (cache misses) since the world started: a test or a bench reads it.
GLOBAL_VAR_INIT(op_menu_builds, 0)

/// The kernel time the cache stamps with: the injected test clock when a test drives it, else the world clock.
/proc/op_now()
	var/datum/controller/kernel/K = kernel()
	return isnull(K?.test_now) ? world.time : K.test_now

/// The final action_options(): every candidate op on `target` for `actor` holding `held`, as a list of assoc lists with "key", "label", "enabled"
/// and "reason". Evaluated lazily and cached on (actor, target, held, their act generations, the actor's provider set generation); the legacy
/// radial menu's rows keep their shape ("id", "name") beside the final ones.
/proc/action_options(mob/actor, atom/target, held_or_route, route = null)
	// The legacy shape action_options(user, target, route) passes a ROUTE_* text; it keeps its own implementation.
	if(!isnull(held_or_route) && !isobj(held_or_route) && !ismob(held_or_route))
		return input_compatibility().compatibility_menu(actor, target, held_or_route)
	if(isnull(held_or_route) && isnull(route) && !op_has_ops(target) && !op_has_ops(actor))
		return input_compatibility().compatibility_menu(actor, target)
	var/obj/held = held_or_route
	return op_menu(actor, target, held)

/// Does the entity have any op of the new engine?
/proc/op_has_ops(datum/D)
	if(!D || QDELETED(D))
		return FALSE
	if(length(op_index_of_table(table_of(D)).ordered))
		return TRUE
	for(var/datum/activation/A as anything in D.rx?.activations)
		if(!A.dead && A.runs && length(op_index_of_def(table_of(D), A.def).ordered))
			return TRUE
	return FALSE

/// The menu of `target` for `actor`: every op a pick (origin ORIGIN_MENU) could reach, with whether Require would pass now and why not.
/proc/op_menu(mob/actor, atom/target, obj/held)
	var/list/previous = GLOB.op_menu_read_frame
	var/list/frame = list(previous, FALSE)
	var/previous_pure_depth = GLOB.op_pure_depth
	GLOB.op_menu_read_frame = frame
	try
		. = op_menu_read(actor, target, held, frame)
	catch(var/exception/fault)
		GLOB.op_menu_read_frame = previous
		// An aborted condition may not have reached its matching op_pure_end().
		GLOB.op_pure_depth = previous_pure_depth
		throw fault
	GLOB.op_menu_read_frame = previous

/// Builds or reuses rows within the caller's synchronous admission read.
/proc/op_menu_read(mob/actor, atom/target, obj/held, list/frame)
	var/stamp = op_now()
	// An entity that has been asked about keeps a record, so what moves or changes it from now on bumps its generation.
	var/datum/rx_state/actor_state = actor ? rx_of(actor) : null
	var/datum/rx_state/target_state = target ? rx_of(target) : null
	var/datum/rx_state/held_state = held ? rx_of(held) : null
	var/cache_key = "[actor ? SHARED_CACHE_UID(actor) : "-"]|[target ? SHARED_CACHE_UID(target) : "-"]|[held ? SHARED_CACHE_UID(held) : "-"]|[actor_state?.act_gen]|[target_state?.act_gen]|[held_state?.act_gen]|[actor_state?.provider_gen]"
	var/list/cached = GLOB.op_menu_cache[cache_key]
	if(cached && (isnull(cached[2]) || cached[2] == stamp))
		var/list/cached_rows = cached[1]
		return cached_rows.Copy()
	GLOB.op_menu_builds++
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_MENU, actor_authority(actor), null, null, FALSE)
	var/list/rows = list()
	var/list/seen = list()
	var/timed = FALSE
	for(var/datum/op_cand/C as anything in R.ordered)
		if(seen[C.oplan.key])
			continue
		if(!op_cand_when(R, C))
			continue
		if(op_cand_path_reason(R, C))
			continue // behind a closed door: not a menu line, as a click sets it aside (spaces.dm)
		seen[C.oplan.key] = TRUE
		if(!isnull(C.oplan.cooldown_t))
			timed = TRUE
		var/enabled = TRUE
		var/reason = null
		var/why = op_cand_require_reason(R, C)
		if(why)
			enabled = FALSE
			reason = reason_text(why)
		rows += list(list("key" = C.oplan.key, "label" = op_label(C.oplan), "enabled" = enabled, "reason" = reason, "id" = C.oplan.key, "name" = op_label(C.oplan)))
	// A modern actor can inspect an unconverted target: retain that target's legacy radial
	// rows (and their route/state refusals) beside the actual engine candidates.
	var/list/legacy_rows = input_compatibility().compatibility_menu(actor, target, ROUTE_PHYSICAL, operations_only = TRUE)
	for(var/list/legacy_row as anything in legacy_rows)
		var/key = legacy_row["id"]
		if(seen[key])
			continue
		seen[key] = TRUE
		var/list/row = legacy_row.Copy()
		row["key"] = key
		row["label"] = legacy_row["name"]
		rows += list(row)
	// Legacy requirements can read uncached data: evaluate their current refusals each tick.
	if(length(legacy_rows))
		timed = TRUE
	if(length(GLOB.op_menu_cache) >= OP_MENU_CACHE_MAX)
		GLOB.op_menu_cache.Cut()
	if(!frame[2])
		GLOB.op_menu_cache[cache_key] = list(rows, timed ? stamp : null)
	return rows.Copy()

/// The reason Require would refuse candidate C now (the requirements only, nothing reserved), or null.
/proc/op_cand_require_reason(datum/op_resolution/R, datum/op_cand/C)
	if(C.legacy)
		return null
	var/datum/act/op/A = op_act_for(C, R.actor, R.target, R.held, R.origin, R.authority)
	var/why = op_require_reason(A, C.oplan, C.binding)
	A.release()
	return why

/// The final screentip_for(): the text of the op a gesture would run, or null. The legacy screentip_for(user, target, gesture) keeps its shape.
/proc/screentip_for(mob/actor, atom/target, held_or_gesture, gesture = null)
	if(isnull(gesture))
		if(istext(held_or_gesture))
			return input_compatibility().compatibility_screentip(actor, target, held_or_gesture)
		gesture = GESTURE_CLICK
	var/obj/held = held_or_gesture
	if(!istext(held_or_gesture) && !isnull(held_or_gesture) && !isobj(held_or_gesture))
		return null
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_CLICK, actor_authority(actor), gesture, null, FALSE)
	var/datum/op_cand/winner = op_resolution_winner(R)
	if(!winner)
		return null
	return "[op_gesture_label(gesture)]: [op_label(winner.oplan)]"

/proc/op_gesture_label(gesture)
	switch(gesture)
		if(GESTURE_CLICK)
			return "Click"
		if(GESTURE_SELF)
			return "Use in hand"
		if(GESTURE_ALT)
			return "Alt-click"
		if(GESTURE_CTRL)
			return "Ctrl-click"
		if(GESTURE_SHIFT)
			return "Shift-click"
		if(GESTURE_DRAG)
			return "Drag"
		if(GESTURE_RIGHT)
			return "Right-click"
	return "[gesture]"

/mob/proc/op_input_stance()
	return null

/obj/proc/op_tool_quality(quality)
	return FALSE
