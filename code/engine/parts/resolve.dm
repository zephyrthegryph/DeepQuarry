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
	/// A Menu read's shared op context (list(act)) while its rows are decided, and whether a row it listed shows a cooldown.
	var/list/menu_scratch
	var/menu_timed = FALSE
	/// Whether the caller wants the near miss (a click's refusal reason): when it does not (a Menu read), a candidate the origin or authority refuses
	/// is never made, the same as one its binding's input drops.
	var/near_misses = TRUE
	/// providers_for(actor, held), read once by the first candidate that needs a provider: pass 1 runs no effects, so every candidate sees the same set.
	var/list/providers

/// The resolver's work, counted for benches and tests (code/tests/benchmarks/active_play.dm): candidate records made, reach gates asked, candidates whose
/// when() conditions were tested, requirement checks (run.dm) and full resolutions.
GLOBAL_VAR_INIT(op_count_cands, 0)
GLOBAL_VAR_INIT(op_count_reach, 0)
GLOBAL_VAR_INIT(op_count_whens, 0)
GLOBAL_VAR_INIT(op_count_requires, 0)
GLOBAL_VAR_INIT(op_count_resolves, 0)

// ---- the ops an entity has ----

/// An op an entity has now: the plan, and the activation that brought it (null for a type-level op).
/datum/op_src
	var/datum/op_plan/oplan
	var/datum/activation/activation

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

/// The compiled op indexes an entity's ops come from: its table's, then each running granted definition's (the same set op_sources_of() walks,
/// with no record per op).
/proc/op_indexes_of(datum/D)
	. = list()
	if(!D || QDELETED(D))
		return
	var/datum/type_table/T = table_of(D)
	. += op_index_of_table(T)
	for(var/datum/activation/A as anything in D.rx?.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		. += op_index_of_def(T, A.def)

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

/// The intent lists a gesture means (op_intents_for()): shared constants, never edited.
GLOBAL_LIST_INIT(op_intents_use, list(INTENT_USE))
GLOBAL_LIST_INIT(op_intents_attack_then_use, list(INTENT_ATTACK, INTENT_USE))
GLOBAL_LIST_INIT(op_intents_alt, list(INTENT_TOGGLE, INTENT_OPEN, INTENT_EJECT))
GLOBAL_LIST_INIT(op_intents_examine, list(INTENT_EXAMINE))
GLOBAL_LIST_INIT(op_intents_drop_onto, list(INTENT_DROP_ONTO))
GLOBAL_LIST_INIT(op_intents_ctrl, list(GESTURE_CTRL))
GLOBAL_LIST_INIT(op_intents_middle, list(GESTURE_MIDDLE))
GLOBAL_LIST_INIT(op_intents_right, list(GESTURE_RIGHT))
GLOBAL_LIST_EMPTY(op_intents_none)

/// The intents a gesture means for this actor, in order: the bind profile's intent list. The lists are shared constants: never edit one.
/proc/op_intents_for(mob/actor, gesture)
	switch(gesture)
		if(GESTURE_CLICK, GESTURE_SELF)
			if(actor && STANCE_IS_HOSTILE(actor.op_input_stance()))
				return GLOB.op_intents_attack_then_use
			return GLOB.op_intents_use
		if(GESTURE_ALT)
			return GLOB.op_intents_alt
		if(GESTURE_SHIFT)
			return GLOB.op_intents_examine
		if(GESTURE_DRAG)
			return GLOB.op_intents_drop_onto
		// No intent of its own: the gesture is its own token, so only an op that pins it (gesture(GESTURE_CTRL)) answers it. A right click is never a player's gesture here (it opens the menu); a call that stands for one, the
		// secondary use of a tool (try_interaction()), resolves it so.
		if(GESTURE_CTRL)
			return GLOB.op_intents_ctrl
		if(GESTURE_MIDDLE)
			return GLOB.op_intents_middle
		if(GESTURE_RIGHT)
			return GLOB.op_intents_right
	return GLOB.op_intents_none

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
			return !B.args?["hint_tool"] // chosen by key: the actor's own op (an ability, a natural weapon) is reached from either side; menu(hint_tool = TRUE) is no input, only the hint (op_plan_hints_tool())
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

/datum/op_index
	/// signature -> list of /datum/op_row: the interned candidate rows of this index's ops (a table's own, or what one granted definition brings).
	var/list/op_row_cache

/// The key of one input shape: the facts every input of the shape shares (op_rows_for()).
/proc/op_shape_signature(side, origin, authority, gesture, list/intents, held_type, near_misses = TRUE)
	return "[side]|[origin]|[authority]|[isnull(gesture) ? "-" : gesture]|[intents ? jointext(intents, ",") : "-"]|[held_type || "-"][near_misses ? "" : "|x"]"

/// Interned candidate rows of `index` whose silent drops (the ones every input of this shape shares) are applied. In declaration order.
/// `signature`: op_shape_signature() of the same arguments, when the caller has it.
/proc/op_rows_for(datum/op_index/index, side, origin, authority, gesture, list/intents, held_type, signature = null, near_misses = TRUE)
	signature ||= op_shape_signature(side, origin, authority, gesture, intents, held_type, near_misses)
	var/list/rows = index.op_row_cache?[signature]
	if(!isnull(rows))
		return rows
	rows = list()
	for(var/datum/op_plan/P as anything in index.ordered)
		for(var/datum/entry/part/bind/B as anything in P.bindings)
			if(!op_row_maybe(P, B, side, origin, authority, gesture, intents, held_type, near_misses))
				continue
			var/datum/op_row/row = new
			row.oplan = P // ALLOW(ownership): an interned row of a compiled table: dropped with it
			row.binding = B // ALLOW(ownership): an interned row of a compiled table: dropped with it
			rows += row
	LAZYSET(index.op_row_cache, signature, rows)
	return rows

// ---- dispatch rows: one holder's candidate rows for one input shape, merged over its table and its running grants ----

/datum/rx_state
	/// The holder's candidate rows per input shape, merged over its table and its running grants (op_side_rows()): list(activation count, signature -> list(rows,
	/// activations)). Made on first read and dropped whenever the holder's capability generation moves (a grant attached, ended or restacked).
	var/list/op_dispatch_memo
	/// The holder's providers before their when() conditions (provider_rows()): list(providers, conditions, activations), dropped with the rows.
	var/list/op_provider_memo

/// TRUE runs every resolution through the collection as it was before the dispatch rows (a bench measures both in one run: active_play).
GLOBAL_VAR_INIT(op_resolver_legacy, FALSE)

/// The candidate rows a holder brings to one input shape on one side: its table's rows, then each running granted definition's, in the order a
/// resolution collects them, and the activation that brought each (null for the table's own). Returns list(rows, activations), interned: on the
/// table's index for a holder with no grants, else on the holder until its capability generation moves. A grant whose activation ended or stopped
/// running since is skipped by the caller, so a read inside a teardown never offers a dead grant's ops. The third slot holds the compiled tables
/// made from these rows (op_fast_side(), dispatch.dm), so they go with them.
/proc/op_side_rows(datum/holder, datum/type_table/T, side, origin, authority, gesture, list/intents, held_type, near_misses = TRUE)
	var/datum/op_index/index = op_index_of_table(T)
	var/signature = op_shape_signature(side, origin, authority, gesture, intents, held_type, near_misses)
	var/datum/rx_state/state = holder.rx
	var/count = length(state?.activations)
	if(!count)
		var/list/plain = index.op_side_rows?[signature]
		if(isnull(plain))
			var/list/own_rows = op_rows_for(index, side, origin, authority, gesture, intents, held_type, signature, near_misses)
			var/list/no_grants = list()
			no_grants.len = length(own_rows)
			plain = list(own_rows, no_grants, null)
			LAZYSET(index.op_side_rows, signature, plain)
		return plain
	// Kept with the count of the holder's activations as well: a grant being attached is in the list before its restack moves the generation.
	var/list/memo = state.op_dispatch_memo
	if(isnull(memo) || memo[1] != count)
		memo = list(count, list())
		state.op_dispatch_memo = memo
	var/list/by_shape = memo[2]
	var/list/made = by_shape[signature]
	if(made)
		return made
	var/list/rows = list()
	var/list/acts = list()
	for(var/datum/op_row/row as anything in op_rows_for(index, side, origin, authority, gesture, intents, held_type, signature, near_misses))
		rows += row
		acts += list(null)
	for(var/datum/activation/A as anything in state.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		for(var/datum/op_row/row as anything in op_rows_for(op_index_of_def(T, A.def), side, origin, authority, gesture, intents, held_type, signature, near_misses))
			rows += row
			acts += A
	made = list(rows, acts, null)
	by_shape[signature] = made
	return made

/datum/op_index
	/// signature -> list(rows, a null per row, compiled tables): op_side_rows() of a holder with no grants.
	var/list/op_side_rows

/// Can this (op, binding) never answer an input of this shape, whatever the origin or authority? An actor-side candidate whose binding is not
/// one of the actor's own, and a gesture the binding kind or the op's intents do not answer: such a candidate is no near miss either (an origin
/// that refused it explains nothing), so it is dropped before the origin and authority filters keep it for the near-miss reason.
/proc/op_shape_drops(datum/op_plan/P, datum/entry/part/bind/B, side, gesture, list/intents)
	if(side == CAND_ACTOR && !op_actor_side_binding(B))
		return TRUE
	if(isnull(gesture))
		return FALSE
	if(B.bind_kind == BIND_MENU || B.bind_kind == BIND_UI || B.bind_kind == BIND_TOPIC || B.bind_kind == BIND_AI)
		return TRUE
	var/list/answered = op_answers(P, B)
	for(var/intent in intents)
		if(intent in answered)
			return FALSE
	return TRUE

/// Could (op, binding) answer an input of this shape? FALSE only when the shared facts drop it silently: the side, the binding kind, the intents and
/// the held item's type. A candidate the origin or authority refuses is kept (it can be the near miss that explains a refusal).
/// With `near_misses` FALSE (a Menu read) one the origin or authority refuses is dropped too.
/proc/op_row_maybe(datum/op_plan/P, datum/entry/part/bind/B, side, origin, authority, gesture, list/intents, held_type, near_misses = TRUE)
	if(op_shape_drops(P, B, side, gesture, intents))
		return FALSE
	if(!op_accepts_origin(P, B, origin))
		return near_misses
	if(origin != ORIGIN_SYSTEM && !op_accepts_authority(P, B, authority))
		return near_misses
	if(side == CAND_ACTOR && !op_actor_side_binding(B))
		return FALSE
	if(origin != ORIGIN_SYSTEM || !isnull(gesture))
		switch(B.bind_kind)
			if(BIND_TOOL)
				if(side != CAND_TARGET || (!held_type && !(origin == ORIGIN_MENU && op_plan_hints_tool(P))))
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
		if(named)
			for(var/datum/entry/part/bind/B as anything in named.bindings)
				seq++
				seq = op_add_cand(R, named, B, holder, side, null, gesture, keep_dropped, seq)
		rows = list()
	else if(keep_dropped)
		rows = list()
		for(var/datum/op_plan/P as anything in index.ordered)
			for(var/datum/entry/part/bind/B as anything in P.bindings)
				var/datum/op_row/row = new
				row.oplan = P // ALLOW(ownership): a transient record of one resolution: dropped with it
				row.binding = B // ALLOW(ownership): a transient record of one resolution: dropped with it
				rows += row
	else if(!GLOB.op_resolver_legacy)
		// The holder's merged rows for this shape: the table's and every running grant's, one interned read.
		var/list/merged = op_side_rows(holder, T, side, R.origin, R.authority, gesture, R.intents, R.held?.type, R.near_misses)
		var/list/merged_rows = merged[1]
		var/list/merged_acts = merged[2]
		for(var/i in 1 to length(merged_rows))
			var/datum/activation/granted_by = merged_acts[i]
			if(granted_by && (granted_by.dead || !granted_by.runs))
				continue
			var/datum/op_row/row = merged_rows[i]
			seq++
			seq = op_add_cand(R, row.oplan, row.binding, holder, side, granted_by, gesture, keep_dropped, seq)
		return seq
	else
		rows = op_rows_for(index, side, R.origin, R.authority, gesture, R.intents, R.held?.type)
	for(var/datum/op_row/row as anything in rows)
		seq++
		seq = op_add_cand(R, row.oplan, row.binding, holder, side, null, gesture, keep_dropped, seq)
	// The capabilities granted to the holder at runtime bring their own ops (a shadowed activation brings none).
	for(var/datum/activation/A as anything in holder.rx?.activations)
		if(A.dead || !A.runs || T.caps[A.def.key])
			continue
		var/datum/op_index/granted = op_index_of_def(T, A.def)
		if(!key && !keep_dropped)
			// The same interned rows as the table's own: a holder with many granted capabilities (a human's organs and body) walks only what can answer.
			for(var/datum/op_row/row as anything in op_rows_for(granted, side, R.origin, R.authority, gesture, R.intents, R.held?.type))
				seq++
				seq = op_add_cand(R, row.oplan, row.binding, holder, side, A, gesture, keep_dropped, seq)
			continue
		if(key)
			// keys are unique in an index (op_index_build()): the one plan of that key, not a walk of every op the grant brings
			var/datum/op_plan/granted_named = granted.by_key[key]
			for(var/datum/entry/part/bind/B as anything in granted_named?.bindings)
				seq++
				seq = op_add_cand(R, granted_named, B, holder, side, A, gesture, keep_dropped, seq)
			continue
		for(var/datum/op_plan/P as anything in granted.ordered)
			for(var/datum/entry/part/bind/B as anything in P.bindings)
				seq++
				seq = op_add_cand(R, P, B, holder, side, A, gesture, keep_dropped, seq)
	return seq

/// One (op, binding) as a candidate of the resolution, unless the shared and per-input silent filters drop it. Returns the running counter.
/proc/op_add_cand(datum/op_resolution/R, datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, datum/activation/granted_by, gesture, keep_dropped, seq)
	if(!keep_dropped && !R.gate_reason && op_silently_dropped(R, P, B, holder, side, gesture))
		return seq
	if(!R.near_misses && op_menu_never_lists(R, P, holder))
		return seq // a Menu read: a row it could never list costs no gate
	var/datum/op_cand/C = op_cand_make(P, B, holder, side, granted_by, seq)
	R.all += C // ALLOW(ownership): a transient record of one resolution: dropped with it
	op_cand_pass1(R, C, gesture)
	if(!C.dropped_by)
		R.ordered += C // ALLOW(ownership): a transient record of one resolution: dropped with it
	return seq

/// The candidate record of (op, binding) on `holder`, brought by `granted_by` (null: the holder's own), before any gate has looked at it.
/proc/op_cand_make(datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, datum/activation/granted_by, seq)
	RETURN_TYPE(/datum/op_cand)
	GLOB.op_count_cands++
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
	return C

/// Builds the candidate list of an input. `gesture` null means a pick by key or a menu read (no intent filter). Pass 1: cheap gates only.
/// `near_misses` FALSE: no candidate is made only to explain a refusal (a Menu read shows none).
/proc/op_resolve(mob/actor, atom/target, obj/held, origin, authority, gesture = null, key = null, keep_dropped = FALSE, near_misses = TRUE)
	RETURN_TYPE(/datum/op_resolution)
	// A resolution that names a key, or explains itself, keeps every candidate and the filter that dropped it; the rest never allocate a
	// candidate for one the binding's own input or the intent drops silently.
	keep_dropped ||= !isnull(key)
	GLOB.op_count_resolves++
	var/datum/op_resolution/R = op_resolution_new(actor, target, held, origin, authority, gesture)
	R.near_misses = near_misses || keep_dropped
	R.gate_reason = actor_gate_reason(actor, origin, authority)
	var/seq = 0
	if(target && !QDELETED(target))
		seq = op_collect_side(R, target, CAND_TARGET, key, gesture, keep_dropped, seq)
	if(held && !QDELETED(held))
		seq = op_collect_side(R, held, CAND_HELD, key, gesture, keep_dropped, seq)
	if(actor && !QDELETED(actor) && actor != target)
		seq = op_collect_side(R, actor, CAND_ACTOR, key, gesture, keep_dropped, seq)
	op_resolution_sort(R)
	if(!length(R.ordered))
		for(var/datum/op_cand/C as anything in R.all)
			if(C.dropped_by in list(GATE_ORIGIN, GATE_PROVIDER, GATE_REACH))
				if(!R.near_miss || op_cand_better(C, R.near_miss))
					R.near_miss = C // ALLOW(ownership): a transient record of one resolution: dropped with it
	return R

/// Could a Menu read never list (op, holder) for this actor, whatever the state? An op only a drag reaches, one that only swallows a click, or
/// one whose requirements hide it from anyone but the holder itself (req_self(), FAILS_HIDDEN) on another holder. Decided per plan once.
/proc/op_menu_never_lists(datum/op_resolution/R, datum/op_plan/P, datum/holder)
	if(isnull(P.menu_static))
		var/static_kind = 0
		if(LAZYACCESS(P.selects, "gesture") == GESTURE_DRAG || (P.passes && !length(P.effects) && !length(P.steps)))
			static_kind = 1
		else
			for(var/datum/entry/part/req/self/self_only in P.needs)
				if(self_only.fails_as() == FAILS_HIDDEN)
					static_kind = 2
					break
		P.menu_static = static_kind
	switch(P.menu_static)
		if(1)
			return TRUE
		if(2)
			return R.actor && holder != R.actor
	return FALSE

/// An empty resolution of an input: who, on what, holding what, through which origin and authority, and the intents the gesture means.
/proc/op_resolution_new(mob/actor, atom/target, obj/held, origin, authority, gesture)
	RETURN_TYPE(/datum/op_resolution)
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
	return R

/// Would pass 1 drop this (op, binding) at the binding's own input or the intent, which are silent and the same for every input of that kind?
/// (Only after the origin and authority filters accepted it: those drops are kept for the near-miss reason.)
/proc/op_silently_dropped(datum/op_resolution/R, datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, gesture)
	if(op_shape_drops(P, B, side, gesture, R.intents))
		return TRUE
	if(!op_accepts_origin(P, B, R.origin))
		return !R.near_misses
	if(R.origin != ORIGIN_SYSTEM && !op_accepts_authority(P, B, R.authority))
		return !R.near_misses
	if(side == CAND_ACTOR && !op_actor_side_binding(B))
		return TRUE
	if((R.origin != ORIGIN_SYSTEM || !isnull(gesture)) && !op_binding_fits(B, R.actor, R.target, R.held, holder, side))
		if(R.origin == ORIGIN_MENU && B.bind_kind == BIND_TOOL && side == CAND_TARGET && op_plan_hints_tool(P))
			return FALSE // kept for the Menu: listed greyed as "needs a <tool>" (op_menu_tool_hints())
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
	if(R.origin == ORIGIN_MENU && B.bind_kind == BIND_MENU && C.side == CAND_HELD && R.target != R.held)
		// likewise the held item's own menu() op (Move To Top, Toggle Digestable) is a line of the item's own Menu, not of every target's
		C.dropped_by = GATE_MATCH
		return
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
		if(isnull(R.providers))
			R.providers = providers_for(R.actor, R.held)
		GLOB.op_count_reach++
		var/reached = reach_gate(R.actor, aim, R.held, P, B, R.authority, R.providers)
		if(istype(reached, /datum/prov))
			op_cand_set_provider(C, reached)
		else if(reached)
			C.dropped_by = (reached == /datum/msg/op/no_hands) ? GATE_PROVIDER : GATE_REACH
			C.dropped_reason = reached
			return

/// The provider the reach gate chose for candidate C.
/proc/op_cand_set_provider(datum/op_cand/C, datum/prov/V)
	C.provider = V // ALLOW(ownership): a transient record of one resolution: dropped with it

/// Pass 2 for one candidate: its when conditions, in the context the op would run in. Sets dropped_by = GATE_MATCH and dropped_cond when one is false.
/proc/op_cand_when(datum/op_resolution/R, datum/op_cand/C)
	if(!length(C.oplan.conds))
		return TRUE
	GLOB.op_count_whens++
	var/datum/act/op/A = op_act_for(C, R.actor, R.target, R.held, R.origin, R.authority)
	var/ok = TRUE
	try
		for(var/cond in C.oplan.conds)
			if(!op_cond(A, cond))
				C.dropped_by = GATE_MATCH
				C.dropped_cond = cond
				ok = FALSE
				break
	catch(var/exception/fault)
		A.release()
		throw fault
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
	// A total order (declaration order breaks every tie), so any sort gives the one result: a merge sort, not an insertion over the survivors.
	var/list/sorted = sortTim(R.ordered.Copy(), GLOBAL_PROC_REF(op_cand_cmp))
	op_specificity_sort(sorted)
	R.ordered = op_order_relative(sorted)

/// The explicit relative priorities and click orders applied to candidates in resolution order (they win over intent, tier, side and
/// specificity). Returns the list, reordered in place.
/proc/op_order_relative(list/sorted)
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
	return sorted

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

/// op_cand_precedes() as a sort comparator.
/proc/op_cand_cmp(datum/op_cand/A, datum/op_cand/B)
	if(A == B)
		return 0
	return op_cand_precedes(A, B) ? -1 : 1

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
	return op_act_fill(C.oplan, C.binding, C.holder, C.side, C.activation, C.cap, C.provider, actor, target, held, origin, authority)

/// A pooled op context for (op, binding) on `holder` from `side`, brought by `granted_by` (capability `cap`), performed by provider `V`: what
/// op_act_for() fills from a candidate record, for a compiled survivor that has none (dispatch.dm). The caller releases it.
/proc/op_act_fill(datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, datum/activation/granted_by, datum/capability/cap, datum/prov/V, mob/actor, datum/target, obj/held, origin, authority)
	RETURN_TYPE(/datum/act/op)
	var/datum/act/op/A = take(/datum/act/op)
	op_act_set(A, P, B, holder, side, granted_by, cap, V, actor, target, held, origin, authority)
	return A

/// Fills an op context's entry fields for (op, binding) on `holder` (op_act_fill()), or refills one a Menu read reuses for its next row: the held
/// relation is written only when it moves (a Menu's rows all share the actor's held item).
/proc/op_act_set(datum/act/op/A, datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, datum/activation/granted_by, datum/capability/cap, datum/prov/V, mob/actor, datum/target, obj/held, origin, authority)
	A.set_key(P.key)
	A.holder = holder // ALLOW(ownership): a pooled transient: reset on release
	A.cap = cap
	A.activation = granted_by // ALLOW(ownership): a pooled transient: reset on release
	A.source = granted_by ? granted_by.source : holder // ALLOW(ownership): a pooled transient: reset on release
	A.actor = actor
	if(A.held_provider() != held)
		A.set_held_provider(held)
	// An op with no target binding has A.target = A.holder (an actor's own op, a self ui_act()).
	// An actor-side op that declares a reach (a natural weapon's bite) is aimed at what the input addressed.
	var/aimed = side == CAND_ACTOR && !isnull(target) && target != actor && (!isnull(LAZYACCESS(P.selects, "reach")) || B?.bind_kind == BIND_CLICKS)
	A.target = ((side == CAND_ACTOR && !aimed) || isnull(target)) ? holder : target
	if(istype(A.target, /atom))
		A.target_atom = A.target // ALLOW(ownership): a pooled transient: reset on release
	A.origin = origin
	A.authority = authority
	A.provider = V?.source

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
/// A compiled resolution (dispatch.dm) makes its order as this walks it, so the walk stops at the winner.
/proc/op_resolution_winner(datum/op_resolution/R)
	RETURN_TYPE(/datum/op_cand)
	if(R.fast_rows)
		var/datum/op_cand/walked = op_fast_winner(R)
		if(GLOB.op_click_parity)
			op_click_parity_winner(R, walked)
		return walked
	var/datum/op_cand/set_aside = null
	var/i = 0
	while(TRUE)
		i++
		if(i > length(R.ordered) && !op_fast_more(R))
			break
		var/datum/op_cand/C = R.ordered[i]
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

/// op_cand_catch_all() of a binding (the item type an item() or stack() binding takes).
/proc/op_binding_catch_all(datum/entry/part/bind/B)
	var/item_type = (B.bind_kind == BIND_ITEM || B.bind_kind == BIND_STACK) ? B.args["type"] : null
	return operation_compatibility().broad_item_type(item_type) || item_type == /atom/movable || item_type == /obj

/// Does candidate C's binding take the held thing (item(), tool(), stack(), in_hand())? A hand() binding answers whatever is held.
/proc/op_cand_takes_held(datum/op_cand/C)
	return op_binding_takes_held(C.binding)

/// op_cand_takes_held() of a binding.
/proc/op_binding_takes_held(datum/entry/part/bind/B)
	return B && (B.bind_kind == BIND_ITEM || B.bind_kind == BIND_TOOL || B.bind_kind == BIND_STACK || B.bind_kind == BIND_IN_HAND || B.bind_kind == BIND_AT_TARGET)

/// Why candidate C's path is blocked (the op is placed at a space of the target that a door on the way keeps shut), or null.
/proc/op_cand_path_reason(datum/op_resolution/R, datum/op_cand/C)
	return op_path_reason(R, C.oplan, C.side, C.holder)

/// op_cand_path_reason() of (op, side, holder).
/proc/op_path_reason(datum/op_resolution/R, datum/op_plan/P, side, datum/holder)
	var/space_id = P?.space
	if(isnull(space_id) || R.origin == ORIGIN_SYSTEM)
		return null
	var/atom/T = (side == CAND_TARGET) ? R.target : holder
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

/// Is candidate C a line a player can choose in the Menu? Not an op only a drag reaches: it needs the dragged thing, which a pick has not got.
/proc/op_menu_lists(datum/op_cand/C)
	return LAZYACCESS(C.oplan.selects, "gesture") != GESTURE_DRAG

/// The Menu line of candidate C: its label, except that an unlabelled catch-all (item(/obj/item) with no label(): the "use what you hold on it"
/// fallback a click falls through to) reads as using the held thing, not as its key ("Turf item", "Wall item"), so the fallbacks a type
/// stacks up merge into one line (op_menu_read()).
/// The hover text of the op's menu() binding (menu(desc =)), or null.
/proc/op_menu_desc(datum/op_plan/P)
	for(var/datum/entry/part/bind/B as anything in P.bindings)
		if(B.bind_kind == BIND_MENU && istext(B.args?["desc"]))
			return B.args["desc"]
	return null

/// Is candidate C a click carrier: an item()/stack() binding that takes any item, with no when() and no requirement narrowing it, whose label is
/// then either missing or only one stance's name for "do the default thing with what is held" ("Hit the floor", "Shove with")? The Menu words it
/// for the held thing, not by the label, which is wrong for most items (op_menu_label()).
/proc/op_cand_click_carrier(datum/op_cand/C)
	if(!C.binding || !(C.binding.bind_kind in list(BIND_ITEM, BIND_STACK)) || !op_cand_catch_all(C))
		return FALSE
	if(!C.oplan.label)
		return TRUE
	if(length(C.oplan.conds) || length(C.oplan.needs))
		return FALSE
	return length(LAZYACCESS(C.oplan.selects, "stance")) || C.oplan.hostile || C.oplan.passes

/// Is candidate C an op that swallows an item click and does nothing else (passes() with no effect: "Nothing")? Not a Menu line.
/proc/op_cand_swallows_only(datum/op_cand/C)
	return C.oplan.passes && !length(C.oplan.effects) && !length(C.oplan.steps)

/// The stance variants the Menu collapses: candidates that differ only by stance() (stance(I_HELP) / stance(I_HURT) ... of one binding on one holder)
/// are one choice. Returns the candidates to leave out: of each group the one for the actor's stance stays, else (no variant for it) the first.
/proc/op_menu_stance_skips(datum/op_resolution/R)
	. = list()
	var/list/groups = list()
	for(var/datum/op_cand/C as anything in R.ordered)
		if(!length(LAZYACCESS(C.oplan.selects, "stance")) || !op_menu_lists(C))
			continue
		var/group_key = "[C.side]|[ref(C.holder)]|[C.binding?.bind_kind]|[C.item_type]|[C.tier]|[length(C.oplan.conds)]|[length(C.oplan.needs)]"
		var/list/members = groups[group_key]
		if(!members)
			members = list()
			groups[group_key] = members
		members += C
	var/stance = R.actor?.op_input_stance()
	for(var/group_key in groups)
		var/list/members = groups[group_key]
		if(length(members) < 2)
			continue
		var/datum/op_cand/keeper = members[1]
		for(var/datum/op_cand/C as anything in members)
			if(stance in LAZYACCESS(C.oplan.selects, "stance"))
				keeper = C
				break
		for(var/datum/op_cand/C as anything in members)
			if(C != keeper)
				.[C] = TRUE

/proc/op_menu_label(datum/op_resolution/R, datum/op_cand/C)
	if(R.held && !C.oplan.label_state && op_cand_click_carrier(C))
		return "Use [R.held.name]"
	var/datum/op_plan/P = C.oplan
	if(P.label_state_text && !isnull(P.label_state))
		var/datum/holder = (C.side == CAND_TARGET) ? R.target : C.holder
		if(holder && cap_key_get(holder, P.label_state, null))
			return P.label_state_text
	return op_label(P)

/// The menus read so far: key -> list(rows, time stamp or null, dependencies, read scope, hidden rows, sampled rows). The key is (actor, target, held,
/// the place generation of the actor and the target (where they are and what they hold, down their contents), the held item's act generation, the
/// actor's provider set and the capability generations, the actor's stance), the ids never reused. What the rows read is a dependency per (entity,
/// key) (op_menu_record_reads(): an unrelated change of a crewmate leaves the menu cached), a row that depends on its holder's whole state (a path,
/// a state-worded label) records the holder's act generation, and a row that sampled state is asked again (op_menu_sampled_rows_same()). Only a
/// menu that shows a cooldown also carries the time it was read at (a cooldown ends with no publication).
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

/// Does the op ask the Menu to list it, greyed, while the actor holds no fitting tool (menu(hint_tool = TRUE) beside its tool() binding)?
/proc/op_plan_hints_tool(datum/op_plan/P)
	for(var/datum/entry/part/bind/B as anything in P.bindings)
		if(B.bind_kind == BIND_MENU && B.args?["hint_tool"])
			return TRUE
	return FALSE

/// "needs a wrench or a welder": the tool qualities of the op's tool binding, as the Menu's reason for a hinted row.
/proc/op_tool_hint_reason(datum/entry/part/bind/B)
	var/list/names = list()
	for(var/quality in B.args["quality"])
		names += replacetext("[quality]", "_", " ")
	return "needs a [english_list(names, and_text = " or ")]"

/// The final action_options(): every candidate op on `target` for `actor` holding `held`, as a list of assoc lists with "key", "label", "enabled"
/// and "reason" (and the radial menu's "id" and "name"). Evaluated lazily and cached on (actor, target, held, their act generations, the
/// actor's provider set generation). Empty when neither the target nor the actor has an op and nothing is held.
/proc/action_options(mob/actor, atom/target, obj/held)
	if(isnull(held) && !op_has_ops(target) && !op_has_ops(actor))
		return list()
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
/// `hidden_out`, when given, receives the rows the Menu left out (list("key", "label", "hidden_by")): what the admin "Show hidden" view lists.
/proc/op_menu(mob/actor, atom/target, obj/held, list/hidden_out = null)
	var/list/previous = GLOB.op_menu_read_frame
	var/datum/lookup_read_scope/previous_scope = GLOB.lookup_read_scope_frame
	var/datum/lookup_read_scope/scope = new
	var/list/frame = list(previous, FALSE, null, scope, FALSE)
	GLOB.lookup_read_scope_frame = scope
	var/previous_pure_depth = GLOB.op_pure_depth
	GLOB.op_menu_read_frame = frame
	try
		. = op_menu_read(actor, target, held, frame, hidden_out)
	catch(var/exception/fault)
		GLOB.op_menu_read_frame = previous
		GLOB.lookup_read_scope_frame = previous_scope
		// An aborted condition may not have reached its matching op_pure_end().
		GLOB.op_pure_depth = previous_pure_depth
		lifeform_end(scope, END_SCOPE)
		throw fault
	GLOB.op_menu_read_frame = previous
	GLOB.lookup_read_scope_frame = previous_scope
	if(!frame[5])
		lifeform_end(scope, END_SCOPE)

/// Builds or reuses rows within the caller's synchronous admission read.
/proc/op_menu_read(mob/actor, atom/target, obj/held, list/frame, list/hidden_out = null)
	var/stamp = op_now()
	// An entity that has been asked about keeps a record, so what moves or changes it from now on bumps its generation.
	var/datum/rx_state/actor_state = actor ? rx_of(actor) : null
	var/datum/rx_state/target_state = target ? rx_of(target) : null
	var/datum/rx_state/held_state = held ? rx_of(held) : null
	var/cache_key = "[actor ? SHARED_CACHE_UID(actor) : "-"]|[target ? SHARED_CACHE_UID(target) : "-"]|[held ? SHARED_CACHE_UID(held) : "-"]|[actor_state?.place_gen]|[target_state?.place_gen]|[held_state?.act_gen]|[actor_state?.provider_gen]|[actor_state?.capability_generation]|[target_state?.capability_generation]|[actor?.op_input_stance()]"
	var/list/cached = GLOB.op_menu_cache[cache_key]
	if(cached && (isnull(cached[2]) || cached[2] == stamp) && op_menu_dependencies_valid(cached[3]) && op_menu_sampled_rows_same(cached, actor, target, held))
		var/list/cached_rows = cached[1]
		var/list/parent_frame = frame[1]
		while(parent_frame)
			if(length(parent_frame) < 3)
				parent_frame.len = 3
			if(!parent_frame[3])
				parent_frame[3] = list()
			var/list/parent_deps = parent_frame[3]
			var/list/cached_deps = cached[3]
			for(var/id in cached_deps)
				parent_deps[id] = cached_deps[id]
			parent_frame = parent_frame[1]
		if(hidden_out && length(cached) >= 5)
			hidden_out += cached[5]
		return cached_rows.Copy()
	GLOB.op_menu_builds++
	// A Menu shows no near miss: the candidates the menu origin refuses are never made.
	var/datum/op_resolution/R = op_menu_resolution(actor, target, held)
	var/list/sampled_rows = list() // the rows whose decision sampled state (read_once()): asked again on a later read, not the whole menu
	var/list/rows = list()
	var/list/hidden = list() // the rows left out, with the requirement that hid each (the admin "Show hidden" view)
	var/list/seen = list()
	var/list/label_rows = list() // label -> the row listed under it: one line per label (op_menu_lists())
	var/timed = FALSE
	var/list/stance_skips = op_menu_stance_skips(R)
	R.menu_scratch = list(take(/datum/act/op))
	try
		op_menu_rows(R, frame, rows, hidden, seen, label_rows, sampled_rows, stance_skips)
	catch(var/exception/fault)
		var/datum/act/op/failed_act = R.menu_scratch[1]
		R.menu_scratch = null
		failed_act.release()
		throw fault
	var/datum/act/op/menu_act = R.menu_scratch[1]
	R.menu_scratch = null
	menu_act.release()
	timed = R.menu_timed
	op_menu_tool_hints(R, rows, hidden, seen)
	if(hidden_out)
		hidden_out += hidden
	if(length(GLOB.op_menu_cache) >= OP_MENU_CACHE_MAX)
		op_menu_cache_clear()
	if(!frame[2])
		var/list/replaced = GLOB.op_menu_cache[cache_key]
		var/datum/lookup_read_scope/old_scope = length(replaced) >= 4 ? replaced[4] : null
		if(old_scope && !QDELETED(old_scope))
			lifeform_end(old_scope, END_SCOPE)
		GLOB.op_menu_cache[cache_key] = list(rows, timed ? stamp : null, frame[3], frame[4], hidden, length(sampled_rows) ? sampled_rows : null)
		frame[5] = TRUE
	return rows.Copy()

/// A Menu row's decision, in the order the Menu asks: list(signature, when() holds, the path is shut, the requirements' refusal, the FAILS_HIDDEN
/// requirements that hide it). The signature is the decision as text, what a sampled row is compared by. One pooled act serves the row's when()
/// and its requirements (they read the same fields).
/proc/op_menu_decide(datum/op_resolution/R, datum/op_cand/C)
	return op_menu_decide_fields(R, C.oplan, C.binding, C.holder, C.side, C.activation, C.cap, C.provider)

/proc/op_menu_decide_fields(datum/op_resolution/R, datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, datum/activation/granted_by, datum/capability/cap, datum/prov/V)
	if(R.menu_scratch)
		// One context serves every row of a Menu read: refilled per row, released by the read (conditions and requirements never write it).
		var/datum/act/op/shared = R.menu_scratch[1]
		op_act_set(shared, P, B, holder, side, granted_by, cap, V, R.actor, R.target, R.held, R.origin, R.authority)
		return op_menu_decide_in(R, P, B, holder, side, shared)
	var/datum/act/op/A = op_act_fill(P, B, holder, side, granted_by, cap, V, R.actor, R.target, R.held, R.origin, R.authority)
	try
		. = op_menu_decide_in(R, P, B, holder, side, A)
	catch(var/exception/fault)
		A.release()
		throw fault
	A.release()

/proc/op_menu_decide_in(datum/op_resolution/R, datum/op_plan/P, datum/entry/part/bind/B, datum/holder, side, datum/act/op/A)
	if(length(P.conds))
		GLOB.op_count_whens++
	for(var/cond in op_conds_cheapest_first(P))
		if(!op_cond(A, cond))
			return list("when", FALSE, FALSE, null, null)
	if(op_path_reason(R, P, side, holder))
		return list("path", TRUE, TRUE, null, null)
	var/list/hid_by = list()
	var/why = op_require_reason(A, P, B, hid_by)
	if(length(hid_by))
		var/datum/entry/part/req/hider = hid_by[1]
		return list("hidden|[hider.type]", TRUE, FALSE, why, hid_by)
	return list("open|[why ? reason_text(why) : ""]", TRUE, FALSE, why, hid_by)

/// The rows of a Menu read, in order (op_menu_read()): one decision per candidate in the read's shared context.
/proc/op_menu_rows(datum/op_resolution/R, list/frame, list/rows, list/hidden, list/seen, list/label_rows, list/sampled_rows, list/stance_skips)
	for(var/datum/op_cand/C as anything in R.ordered)
		if(seen[C.oplan.key])
			continue
		if(!op_menu_lists(C))
			continue
		if(stance_skips[C])
			hidden += list(list("key" = C.oplan.key, "label" = op_label(C.oplan), "hidden_by" = "another stance variant of the same choice"))
			continue
		if(op_cand_swallows_only(C))
			continue
		// The row's own decision (when, path, requirements) in one act. A decision that sampled state with read_once() leaves the rest of the
		// menu cacheable: the row is kept as a sampled row, and a later read asks it again and rebuilds only when its answer moved. The other
		// rows stay valid through the reads they recorded (op_menu_record_reads(): each read entity's act generation, which a change of what it
		// holds, down to an implant in one of its organs, moves: op_moved()).
		var/sampled_before = frame[2]
		frame[2] = FALSE
		if(C.oplan.space || C.oplan.label_state)
			op_menu_record_holder(C.side == CAND_TARGET ? R.target : C.holder)
		var/list/decision = op_menu_decide(R, C)
		if(frame[2])
			sampled_rows += list(op_menu_sampled_row(C, decision[1]))
		frame[2] = sampled_before
		if(!decision[2])
			hidden += list(list("key" = C.oplan.key, "label" = op_label(C.oplan), "hidden_by" = "when()"))
			continue
		if(decision[3])
			continue // behind a closed door: not a menu line, as a click sets it aside (spaces.dm)
		seen[C.oplan.key] = TRUE
		var/label = op_menu_label(R, C)
		var/list/same = label_rows[label]
		if(!isnull(C.oplan.cooldown_t))
			R.menu_timed = TRUE
		var/enabled = TRUE
		var/reason = null
		var/list/hid_by = decision[5]
		var/why = decision[4]
		if(length(hid_by))
			// A requirement about who the actor is or what the target is (FAILS_HIDDEN) failed: the row can never be chosen from here.
			var/datum/entry/part/req/hider = hid_by[1]
			hidden += list(list("key" = C.oplan.key, "label" = label, "hidden_by" = hider.hidden_by_name(R.actor)))
			continue
		if(why)
			enabled = FALSE
			reason = reason_text(why)
			if(!length(reason))
				// A refusal with no text (a guard that swallows a click, MSG(req_silent)) has nothing to show greyed: not a line.
				hidden += list(list("key" = C.oplan.key, "label" = label, "hidden_by" = "silent refusal (no reason text)"))
				continue
		var/list/row = list("key" = C.oplan.key, "label" = label, "enabled" = enabled, "reason" = reason, "id" = C.oplan.key, "name" = label, "desc" = op_menu_desc(C.oplan))
		if(same)
			// Two ops under one label (a wall's Touch over the turf's inherited Touch): the player sees one line, the first that would
			// run (the higher placed), unless only a later one is open now.
			if(!same["enabled"] && enabled)
				rows[rows.Find(same)] = row
				label_rows[label] = row
			continue
		label_rows[label] = row
		rows += list(row)

/// The ordered candidates of a Menu read, as compiled rows (plan, binding, side, grant, provider): what pass 1 decides depends only on who acts
/// on what holding what, where they are and what they hold, their providers, grants and stance, so it is kept per that shape and a Menu rebuilt
/// for a change of state skips op_resolve(). The rows hold handles, never entities; one whose entities are gone is made again.
GLOBAL_LIST_EMPTY(op_menu_pass1_rows)
#define OP_MENU_PASS1_MAX 512

/proc/op_menu_resolution(mob/actor, atom/target, obj/held)
	RETURN_TYPE(/datum/op_resolution)
	var/authority = actor_authority(actor)
	var/datum/rx_state/actor_state = actor ? rx_of(actor) : null
	var/datum/rx_state/target_state = target ? rx_of(target) : null
	var/datum/rx_state/held_state = held ? rx_of(held) : null
	var/shape = "[actor ? SHARED_CACHE_UID(actor) : "-"]|[target ? SHARED_CACHE_UID(target) : "-"]|[held ? SHARED_CACHE_UID(held) : "-"]|[actor_state?.place_gen]|[target_state?.place_gen]|[held_state?.act_gen]|[actor_state?.provider_gen]|[actor_state?.capability_generation]|[target_state?.capability_generation]|[held_state?.capability_generation]|[actor?.op_input_stance()]|[authority]"
	var/list/kept = GLOB.op_menu_pass1_rows[shape]
	if(kept)
		var/datum/op_resolution/again = op_menu_resolution_from(kept, actor, target, held, authority)
		if(again)
			return again
	var/datum/op_resolution/R = op_resolve(actor, target, held, ORIGIN_MENU, authority, null, null, near_misses = FALSE)
	if(length(GLOB.op_menu_pass1_rows) >= OP_MENU_PASS1_MAX)
		GLOB.op_menu_pass1_rows.Cut()
	var/list/ordered_rows = list()
	for(var/datum/op_cand/C as anything in R.ordered)
		ordered_rows += list(op_menu_pass1_row(C))
	var/list/hint_rows = list()
	for(var/datum/op_cand/C as anything in R.all)
		if(C.dropped_by == GATE_MATCH && C.binding.bind_kind == BIND_TOOL && C.side == CAND_TARGET)
			hint_rows += list(op_menu_pass1_row(C))
	GLOB.op_menu_pass1_rows[shape] = list(ordered_rows, hint_rows)
	return R

/proc/op_menu_pass1_row(datum/op_cand/C)
	return list(C.oplan, C.binding, C.side, C.activation ? handle_of(C.activation) : null, C.provider?.entry, C.provider ? handle_of(C.provider.source) : null, C.rank, C.seq)

/// A Menu resolution made again from kept rows, or null when an entity a row names is gone.
/proc/op_menu_resolution_from(list/kept, mob/actor, atom/target, obj/held, authority)
	RETURN_TYPE(/datum/op_resolution)
	var/datum/op_resolution/R = op_resolution_new(actor, target, held, ORIGIN_MENU, authority, null)
	R.near_misses = FALSE
	var/list/made = list()
	for(var/list/row as anything in kept[1])
		var/datum/op_cand/C = op_menu_pass1_cand(R, row)
		if(!C)
			return null
		made += C
	R.ordered = made
	var/list/hints = list()
	for(var/list/row as anything in kept[2])
		var/datum/op_cand/C = op_menu_pass1_cand(R, row)
		if(!C)
			return null
		C.dropped_by = GATE_MATCH
		hints += C
	R.all = hints
	return R

/proc/op_menu_pass1_cand(datum/op_resolution/R, list/row)
	RETURN_TYPE(/datum/op_cand)
	var/datum/activation/granted_by = null
	if(row[4])
		granted_by = handle_get(row[4])
		if(!granted_by || granted_by.dead || !granted_by.runs)
			return null
	var/datum/op_cand/C = op_cand_make(row[1], row[2], op_fast_holder(R, row[3]), row[3], granted_by, row[8])
	C.rank = row[7]
	if(row[5])
		var/datum/source = handle_get(row[6])
		if(!source)
			return null
		if(isnull(R.providers))
			R.providers = providers_for(R.actor, R.held)
		for(var/datum/prov/V as anything in R.providers)
			if(V.entry == row[5] && V.source == source)
				op_cand_set_provider(C, V)
				break
		if(!C.provider)
			return null
	return C

/// What a cached menu keeps of a row whose decision sampled state: enough to ask it again (the plan, binding and capability are compiled, shared
/// parts; the entities are handles, never held; the provider is found again among the actor's by its entry and its source), and the answer.
/proc/op_menu_sampled_row(datum/op_cand/C, signature)
	return list(C.oplan, C.binding, handle_of(C.holder), C.side, C.activation ? handle_of(C.activation) : null, C.cap, C.provider?.entry, C.provider ? handle_of(C.provider.source) : null, signature)

/// TRUE when every sampled row of the cached menu decides as it did when the menu was built. A sampled row whose entities are gone counts as moved.
/proc/op_menu_sampled_rows_same(list/cached, mob/actor, atom/target, obj/held)
	var/list/sampled = length(cached) >= 6 ? cached[6] : null
	if(!length(sampled))
		return TRUE
	var/datum/op_resolution/R = op_resolution_new(actor, target, held, ORIGIN_MENU, actor_authority(actor), null)
	for(var/list/row as anything in sampled)
		var/datum/holder = handle_get(row[3])
		if(!holder || QDELETED(holder))
			return FALSE
		var/datum/activation/granted_by = row[5] ? handle_get(row[5]) : null
		if(row[5] && (!granted_by || granted_by.dead))
			return FALSE
		var/datum/prov/V = null
		if(row[7])
			var/datum/source = handle_get(row[8])
			if(!source)
				return FALSE
			if(isnull(R.providers))
				R.providers = providers_for(actor, held)
			for(var/datum/prov/candidate as anything in R.providers)
				if(candidate.entry == row[7] && candidate.source == source)
					V = candidate
					break
			if(!V)
				return FALSE
		var/list/decision = op_menu_decide_fields(R, row[1], row[2], holder, row[4], granted_by, row[6], V)
		if(decision[1] != row[9])
			return FALSE
	return TRUE

/// The ops that asked (menu(hint_tool = TRUE)) to be listed while the actor holds no tool that fits: a greyed row "needs a <tool>", unless the op is
/// closed by its when() or its path. Adds to `rows`; `seen` keeps the keys already listed.
/proc/op_menu_tool_hints(datum/op_resolution/R, list/rows, list/hidden, list/seen)
	for(var/datum/op_cand/C as anything in R.all)
		if(C.dropped_by != GATE_MATCH || C.binding.bind_kind != BIND_TOOL || C.side != CAND_TARGET || seen[C.oplan.key])
			continue
		if(!op_plan_hints_tool(C.oplan) || !op_menu_lists(C))
			continue
		if(!op_cand_when(R, C))
			continue
		if(op_cand_path_reason(R, C))
			continue
		seen[C.oplan.key] = TRUE
		var/label = op_menu_label(R, C)
		rows += list(list("key" = C.oplan.key, "label" = label, "enabled" = FALSE, "reason" = op_tool_hint_reason(C.binding), "id" = C.oplan.key, "name" = label, "desc" = op_menu_desc(C.oplan)))

/// The reason Require would refuse candidate C now (the requirements only, nothing reserved), or null. `hide`, when given, receives the requirement
/// that hides the row (a failed FAILS_HIDDEN one, tested first): the reason is then null.
/proc/op_cand_require_reason(datum/op_resolution/R, datum/op_cand/C, list/hide = null)
	var/datum/act/op/A = op_act_for(C, R.actor, R.target, R.held, R.origin, R.authority)
	var/why
	try
		why = op_require_reason(A, C.oplan, C.binding, hide)
	catch(var/exception/fault)
		A.release()
		throw fault
	A.release()
	return why

/// The final screentip_for(): the text of the op a gesture (default: a plain click) would run, or null.
/proc/screentip_for(mob/actor, atom/target, obj/held, gesture = GESTURE_CLICK)
	if(!isnull(held) && !isobj(held))
		return null
	var/authority = actor_authority(actor)
	var/datum/op_resolution/R = op_click_resolution(actor, target, held, ORIGIN_CLICK, authority, gesture) || op_resolve(actor, target, held, ORIGIN_CLICK, authority, gesture, null)
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

SCHEMA(/datum/op_cand, dropped_reason, schema_msg())
