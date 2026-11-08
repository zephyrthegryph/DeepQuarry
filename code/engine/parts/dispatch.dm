// The compiled click (doc/rewrite/proposals/op_compiled.md; doc/rewrite/final_api.html, section 8 "Resolution cost").
//
// A gestured input (a click, an alt-click, a drag, a use in hand) has one winner: the first candidate, in resolution order, whose cheap gates pass,
// whose when() conditions hold and whose path is open. The full resolver (op_resolve()) finds it by building every candidate, sorting them all and
// testing them in turn; this file finds the same winner from tables compiled per input shape, best first, and stops at the first that answers:
//
//   shape     what every input of one kind shares: the side, the origin, the authority, the gesture and its intents, the held item's type and the
//             actor's stance. A holder's rows for a shape (op_side_rows(): its table's and its running grants') are filtered once by every gate
//             the shape decides (origin, authority, the binding kind, the intent, stance(), gesture()) and ordered once by intent rank, tier and
//             declaration (op_fast_side()), interned until the holder's capability generation moves.
//   groups    the rows of one side that tie on intent rank and tier. Binding specificity reorders survivors within such a run, and which rows
//             survive is an instance fact (reach, a tool's quality, an at_target() filter), so a group's gates are asked together, its survivors
//             ordered exactly as op_specificity_sort() orders them, then handed on. Groups of the three sides merge by (rank, tier, side), the
//             order op_cand_precedes() gives.
//   order     a relative priority (priority(above/below())) or a click_order() moves an op next to another survivor, so when a shape has one the
//             whole order is made first and moved exactly as op_resolution_sort() moves it; otherwise groups are made only as the walk needs them.
//
// The walk keeps its survivors flat (the compiled row, its side, its provider's place in the input's provider list): no record is made for a
// candidate until it wins, or a decline or passes() chain moves on to it. Nothing about refusals is computed on the way: an input with no winner
// that wants its reason told is resolved again by op_resolve(), whose near-miss and gate reasons are the ones the player has always seen. An input
// the compiled path does not take (no gesture, a menu pick or a UI press by key, the game acting for itself, an actor its gate refuses) goes to
// op_resolve() as before. Unit tests compare both on every click (op_click_parity).

/// TRUE in the unit-test build: every compiled click is resolved by op_resolve() too and the two orders are compared (a difference is a runtime).
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
GLOBAL_VAR_INIT(op_click_parity, TRUE)
#else
GLOBAL_VAR_INIT(op_click_parity, FALSE)
#endif

/// Compiled resolutions made (the bench counts them beside op_count_resolves).
GLOBAL_VAR_INIT(op_count_compiled, 0)

// A compiled row: list(plan, binding, activation, intent rank, tier, collection index, needs the reach gate, binding specificity).
#define FAST_PLAN 1
#define FAST_BINDING 2
#define FAST_ACTIVATION 3
#define FAST_RANK 4
#define FAST_TIER 5
#define FAST_SEQ 6
#define FAST_REACH 7
#define FAST_SPECIFICITY 8
// A group of a side table: list(first row, last row, rank, tier, its survivors need the specificity order).
#define FAST_GROUP_FIRST 1
#define FAST_GROUP_LAST 2
#define FAST_GROUP_RANK 3
#define FAST_GROUP_TIER 4
#define FAST_GROUP_SPECIFIC 5

/datum/op_resolution
	/// The compiled walk's state while it has groups left: list(list(side, side table, next group), ...) in side order; null once spent or for a
	/// full resolution.
	var/list/fast_sides
	/// TRUE for a compiled resolution.
	var/fast = FALSE
	/// The compiled survivors made so far, in resolution order: the row (list), its side, and its provider's place in `providers` (0: none).
	/// Empty once they are records in `ordered` (a shape with a relative priority, the parity check).
	var/list/fast_rows
	var/list/fast_row_sides
	var/list/fast_row_providers

/datum/op_cand
	/// The candidate's place among a compiled resolution's survivors (dispatch.dm), or 0.
	var/fast_index = 0

/// The compiled resolution of a gestured input, or null when the compiled path does not take it (the caller resolves it with op_resolve()). Its
/// survivors are made as op_resolution_winner() and op_resolution_next() walk it.
/proc/op_click_resolution(mob/actor, atom/target, obj/held, origin, authority, gesture)
	RETURN_TYPE(/datum/op_resolution)
	if(isnull(gesture) || origin == ORIGIN_SYSTEM || origin == ORIGIN_MENU || GLOB.op_resolver_legacy)
		return null
	if(actor_gate_reason(actor, origin, authority))
		return null
	GLOB.op_count_compiled++
	var/datum/op_resolution/R = op_click_build(actor, target, held, origin, authority, gesture)
	if(GLOB.op_click_parity)
		op_click_parity_check(R)
	return R

/// The compiled resolution itself. `whole`: every survivor made a record in R.ordered at once (the parity check's copy).
/proc/op_click_build(mob/actor, atom/target, obj/held, origin, authority, gesture, whole = FALSE)
	RETURN_TYPE(/datum/op_resolution)
	var/datum/op_resolution/R = op_resolution_new(actor, target, held, origin, authority, gesture)
	R.fast = TRUE
	R.fast_rows = list()
	R.fast_row_sides = list()
	R.fast_row_providers = list()
	var/stance = actor?.op_input_stance()
	var/held_type = held?.type
	var/list/sides = list()
	var/relative = FALSE
	if(target && !QDELETED(target))
		var/list/target_table = op_fast_side(target, CAND_TARGET, origin, authority, gesture, R.intents, held_type, stance)
		relative ||= target_table[3]
		sides += list(list(CAND_TARGET, target_table, 1))
	if(held && !QDELETED(held))
		var/list/held_table = op_fast_side(held, CAND_HELD, origin, authority, gesture, R.intents, held_type, stance)
		relative ||= held_table[3]
		sides += list(list(CAND_HELD, held_table, 1))
	if(actor && !QDELETED(actor) && actor != target)
		var/list/actor_table = op_fast_side(actor, CAND_ACTOR, origin, authority, gesture, R.intents, held_type, stance)
		relative ||= actor_table[3]
		sides += list(list(CAND_ACTOR, actor_table, 1))
	R.fast_sides = sides
	if(relative || whole)
		// A relative priority moves an op over survivors the walk has not reached: make the whole order as records, then move as the full sort does.
		op_fast_materialize(R)
		if(relative)
			R.ordered = op_order_relative(R.ordered)
	return R

/// The holder a compiled survivor of `side` belongs to.
/proc/op_fast_holder(datum/op_resolution/R, side)
	switch(side)
		if(CAND_TARGET)
			return R.target
		if(CAND_HELD)
			return R.held
	return R.actor

/// One holder's compiled table for an input shape on one side: list(rows, groups, has a relative priority, side). The rows are the shape rows
/// (op_side_rows()) every gate the shape decides lets through, ordered by intent rank, then tier (highest first), then collection order; a group
/// is a run of rows tying on rank and tier. Interned on the shape rows, so it goes when they do.
/proc/op_fast_side(datum/holder, side, origin, authority, gesture, list/intents, held_type, stance)
	var/datum/type_table/T = table_of(holder)
	var/list/merged = op_side_rows(holder, T, side, origin, authority, gesture, intents, held_type)
	var/list/by_stance = merged[3]
	if(isnull(by_stance))
		by_stance = list()
		merged[3] = by_stance
	var/stance_key = "[stance]"
	var/list/table = by_stance[stance_key]
	if(table)
		return table
	var/list/rows = merged[1]
	var/list/acts = merged[2]
	var/list/entries = list()
	var/relative = FALSE
	for(var/i in 1 to length(rows))
		var/datum/op_row/row = rows[i]
		var/datum/op_plan/P = row.oplan
		var/datum/entry/part/bind/B = row.binding
		var/rank = op_fast_row_rank(P, B, side, origin, authority, gesture, intents, stance)
		if(!rank)
			continue
		if(length(P.priority_rel) || length(P.click_below))
			relative = TRUE
		var/needs_reach = op_reach_policy(P, B) != REACH_ANY || op_affordance(P, B, null)
		// stable insertion by (rank, tier highest first); collection order breaks the rest
		var/list/entry = list(P, B, acts[i], rank, P.tier, i, needs_reach, op_binding_specificity(B))
		var/at = length(entries) + 1
		for(var/j in 1 to length(entries))
			var/list/other = entries[j]
			if(rank < other[FAST_RANK] || (rank == other[FAST_RANK] && P.tier > other[FAST_TIER]))
				at = j
				break
		entries.Insert(at, list(entry))
	var/list/groups = list()
	var/start = 1
	while(start <= length(entries))
		var/list/first = entries[start]
		var/stop = start
		var/specific = 0
		var/list/kinds = list()
		while(TRUE)
			var/list/member = entries[stop]
			if(member[FAST_SPECIFICITY])
				specific++
				kinds["[member[FAST_SPECIFICITY]]"] = TRUE
			if(stop >= length(entries))
				break
			var/list/following = entries[stop + 1]
			if(following[FAST_RANK] != first[FAST_RANK] || following[FAST_TIER] != first[FAST_TIER])
				break
			stop++
		// only a group with held-item bindings of different specificities is reordered (op_specificity_sort() is stable)
		groups += list(list(start, stop, first[FAST_RANK], first[FAST_TIER], specific > 1 && length(kinds) > 1))
		start = stop + 1
	table = list(entries, groups, relative, side)
	by_stance[stance_key] = table
	return table

/// The intent rank (1 first) at which (op, binding) answers a gestured input of this shape, or 0 when a gate the shape decides drops it: the
/// origin, the authority, an actor-side binding that is not the actor's own, a binding chosen by key, the intents, stance() and gesture(). The
/// same tests as op_silently_dropped() and op_cand_pass1() make of every input of the shape.
/proc/op_fast_row_rank(datum/op_plan/P, datum/entry/part/bind/B, side, origin, authority, gesture, list/intents, stance)
	if(!op_accepts_origin(P, B, origin))
		return 0
	if(!op_accepts_authority(P, B, authority))
		return 0
	if(side == CAND_ACTOR && !op_actor_side_binding(B))
		return 0
	if(B.bind_kind == BIND_MENU || B.bind_kind == BIND_UI || B.bind_kind == BIND_TOPIC || B.bind_kind == BIND_AI)
		return 0
	var/list/answered = op_answers(P, B)
	var/rank = 0
	for(var/i in 1 to length(intents))
		if(intents[i] in answered)
			rank = i
			break
	if(!rank)
		return 0
	var/list/stances = LAZYACCESS(P.selects, "stance")
	if(length(stances) && !(stance in stances))
		return 0
	var/pinned = LAZYACCESS(P.selects, "gesture")
	if(!isnull(pinned) && pinned != gesture)
		return 0
	return rank

/// Makes the next group of survivors: the group that comes first over the three sides by (rank, tier, side), its rows' instance gates asked
/// (op_fast_row_reach()), its survivors ordered by binding specificity. TRUE when it added any; FALSE when no group is left.
/proc/op_fast_more(datum/op_resolution/R)
	while(R.fast_sides)
		var/list/best = null
		var/list/best_group = null
		for(var/list/state as anything in R.fast_sides)
			var/list/table = state[2]
			var/list/groups = table[2]
			var/at = state[3]
			if(at > length(groups))
				continue
			var/list/group = groups[at]
			if(!best || group[FAST_GROUP_RANK] < best_group[FAST_GROUP_RANK] || (group[FAST_GROUP_RANK] == best_group[FAST_GROUP_RANK] && group[FAST_GROUP_TIER] > best_group[FAST_GROUP_TIER]))
				best = state
				best_group = group
		if(!best)
			R.fast_sides = null
			return FALSE
		best[3] = best[3] + 1
		if(op_fast_group(R, best[1], best[2], best_group))
			return TRUE
	return FALSE

/// Adds the survivors of one group of one side's table to R's flat survivors, in resolution order. How many it added.
/proc/op_fast_group(datum/op_resolution/R, side, list/table, list/group)
	var/list/entries = table[1]
	var/before = length(R.fast_rows)
	for(var/i in group[FAST_GROUP_FIRST] to group[FAST_GROUP_LAST])
		var/list/entry = entries[i]
		var/datum/activation/granted_by = entry[FAST_ACTIVATION]
		if(granted_by && (granted_by.dead || !granted_by.runs))
			continue
		var/reached = op_fast_row_reach(R, entry, side)
		if(!reached)
			continue
		var/n = length(R.fast_rows) + 1
		R.fast_rows.len = n
		R.fast_row_sides.len = n
		R.fast_row_providers.len = n
		R.fast_rows[n] = entry
		R.fast_row_sides[n] = side
		R.fast_row_providers[n] = (reached == TRUE) ? 0 : R.providers.Find(reached)
	var/added = length(R.fast_rows) - before
	if(added > 1 && group[FAST_GROUP_SPECIFIC])
		op_fast_specificity_sort(R, before + 1, before + added)
	return added

/// The instance gates of one compiled row (what op_cand_pass1() asks once the shape's gates have passed): the binding's own input, then the
/// providers and the reach gate. FALSE: dropped; TRUE: it answers with no provider; else the /datum/prov that performs it.
/proc/op_fast_row_reach(datum/op_resolution/R, list/entry, side)
	var/datum/op_plan/P = entry[FAST_PLAN]
	var/datum/entry/part/bind/B = entry[FAST_BINDING]
	if(!op_binding_fits(B, R.actor, R.target, R.held, op_fast_holder(R, side), side))
		return FALSE
	if(!entry[FAST_REACH])
		return TRUE
	var/atom/aim = (side == CAND_ACTOR && B.bind_kind != BIND_CLICKS) ? R.actor : R.target
	if(isnull(R.providers))
		R.providers = providers_for(R.actor, R.held)
	GLOB.op_count_reach++
	var/reached = reach_gate(R.actor, aim, R.held, P, B, R.authority, R.providers, R.reach_fit_memo ||= list())
	if(istype(reached, /datum/prov))
		return reached
	return reached ? FALSE : TRUE

/// op_specificity_sort() on survivors first..last of one group (they tie on rank, tier and side): the held-item bindings, most specific first and
/// stably, in the slots they already hold.
/proc/op_fast_specificity_sort(datum/op_resolution/R, first, last)
	var/list/slots = list()
	var/list/rows = list()
	var/list/providers = list()
	for(var/i in first to last)
		var/list/entry = R.fast_rows[i]
		if(!entry[FAST_SPECIFICITY])
			continue
		slots += i
		var/at = length(rows) + 1
		for(var/j in 1 to length(rows))
			var/list/placed = rows[j]
			if(entry[FAST_SPECIFICITY] > placed[FAST_SPECIFICITY])
				at = j
				break
		rows.Insert(at, list(entry))
		providers.Insert(at, R.fast_row_providers[i])
	for(var/k in 1 to length(slots))
		R.fast_rows[slots[k]] = rows[k]
		R.fast_row_providers[slots[k]] = providers[k]

/// The record of compiled survivor `k`: what op_begin(), the pass-2 tests and a decline chain read.
/proc/op_fast_cand(datum/op_resolution/R, k)
	RETURN_TYPE(/datum/op_cand)
	var/list/entry = R.fast_rows[k]
	var/side = R.fast_row_sides[k]
	var/datum/op_cand/C = op_cand_make(entry[FAST_PLAN], entry[FAST_BINDING], op_fast_holder(R, side), side, entry[FAST_ACTIVATION], entry[FAST_SEQ])
	C.rank = entry[FAST_RANK]
	C.intent = R.intents[C.rank]
	C.fast_index = k
	var/at = R.fast_row_providers[k]
	if(at)
		op_cand_set_provider(C, R.providers[at])
	return C

/// Makes every survivor a record in R.ordered (a shape with a relative priority, the parity check): the walk then reads the records.
/proc/op_fast_materialize(datum/op_resolution/R)
	while(op_fast_more(R))
		pass()
	var/list/made = list()
	for(var/k in 1 to length(R.fast_rows))
		made += op_fast_cand(R, k)
	R.ordered = made
	R.fast_rows = null

/// The when() test of compiled survivor `k` (op_cand_when() without a record).
/proc/op_fast_when(datum/op_resolution/R, k)
	var/list/entry = R.fast_rows[k]
	var/datum/op_plan/P = entry[FAST_PLAN]
	if(!length(P.conds))
		return TRUE
	GLOB.op_count_whens++
	var/side = R.fast_row_sides[k]
	var/datum/activation/granted_by = entry[FAST_ACTIVATION]
	var/at = R.fast_row_providers[k]
	var/datum/prov/V = at ? R.providers[at] : null
	if(R.menu_scratch)
		// The walk's one context, refilled per row (op_fast_walk()); each condition is answered once per holder and target in the walk, and a row
		// whose conditions were all answered before is decided from those answers without filling the context.
		var/datum/act/op/shared = R.menu_scratch[1]
		var/datum/holder = op_fast_holder(R, side)
		var/datum/capability/cap = granted_by ? granted_by.def : P.owner_def
		var/row_key = op_menu_cond_key_of(R, holder, op_act_target(P, entry[FAST_BINDING], holder, side, R.actor, R.target), cap, granted_by)
		var/filled = FALSE
		var/list/answers = R.menu_cond_answers
		for(var/cond in op_conds_cheapest_first(P))
			if(answers && (istext(cond) || isnum(cond)))
				var/known = answers["[row_key]|[cond]"]
				if(!isnull(known))
					if(!known)
						return FALSE
					continue
			if(!filled)
				op_act_set(shared, P, entry[FAST_BINDING], holder, side, granted_by, cap, V, R.actor, R.target, R.held, R.origin, R.authority)
				filled = TRUE
			if(!op_menu_cond(R, shared, cond, row_key))
				return FALSE
		return TRUE
	var/datum/act/op/A = op_act_fill(P, entry[FAST_BINDING], op_fast_holder(R, side), side, granted_by, granted_by ? granted_by.def : P.owner_def, V, R.actor, R.target, R.held, R.origin, R.authority)
	var/ok = TRUE
	try
		for(var/cond in P.conds)
			if(!op_cond(A, cond))
				ok = FALSE
				break
	catch(var/exception/fault)
		A.release()
		throw fault
	A.release()
	return ok

/// Runs `proc_name` (op_fast_winner_walk or op_fast_next_walk) with one op context for every row's when() test, released after: a click that walks
/// a body's surgery steps fills one context, not one per step. The conditions' answers are kept for the walk only.
/proc/op_fast_walk(datum/op_resolution/R, proc_name, datum/op_cand/after = null)
	if(R.menu_scratch)
		return call(proc_name)(R, after)
	R.menu_scratch = list(take(/datum/act/op))
	try
		. = call(proc_name)(R, after)
	catch(var/exception/fault)
		op_fast_walk_end(R)
		throw fault
	op_fast_walk_end(R)

/proc/op_fast_walk_end(datum/op_resolution/R)
	var/datum/act/op/shared = R.menu_scratch[1]
	R.menu_scratch = null
	R.menu_cond_answers = null
	R.menu_cond_ids = null
	shared.release()

/// The winner among R's compiled survivors (op_resolution_winner() over the flat rows, made as it goes): a record of the one that wins. The same
/// rule: the first whose when() holds and whose path is open, a blocked one set aside for a later one that answers the same input.
/proc/op_fast_winner(datum/op_resolution/R)
	RETURN_TYPE(/datum/op_cand)
	return op_fast_walk(R, GLOBAL_PROC_REF(op_fast_winner_walk))

/proc/op_fast_winner_walk(datum/op_resolution/R, datum/op_cand/unused)
	RETURN_TYPE(/datum/op_cand)
	var/set_aside = 0
	var/k = 0
	while(TRUE)
		k++
		if(k > length(R.fast_rows) && !op_fast_more(R))
			break
		if(!op_fast_when(R, k))
			continue
		var/list/entry = R.fast_rows[k]
		var/datum/op_plan/P = entry[FAST_PLAN]
		var/datum/entry/part/bind/B = entry[FAST_BINDING]
		if(op_path_reason(R, P, R.fast_row_sides[k], op_fast_holder(R, R.fast_row_sides[k])))
			if(!op_binding_catch_all(B))
				set_aside ||= k
			continue
		if(set_aside && R.held && op_binding_takes_held(R.fast_rows[set_aside][FAST_BINDING]) && !op_binding_takes_held(B))
			return op_fast_cand(R, set_aside)
		return op_fast_cand(R, k)
	return set_aside ? op_fast_cand(R, set_aside) : null

/// The compiled survivor after `after` whose when() conditions hold, as a record, or null.
/proc/op_fast_next(datum/op_resolution/R, datum/op_cand/after)
	RETURN_TYPE(/datum/op_cand)
	return op_fast_walk(R, GLOBAL_PROC_REF(op_fast_next_walk), after)

/proc/op_fast_next_walk(datum/op_resolution/R, datum/op_cand/after)
	RETURN_TYPE(/datum/op_cand)
	var/k = after.fast_index
	while(TRUE)
		k++
		if(k > length(R.fast_rows) && !op_fast_more(R))
			return null
		if(op_fast_when(R, k))
			return op_fast_cand(R, k)

/// The candidate after `after` in R's order whose when() conditions hold, or null; a compiled resolution makes more of its order as it goes.
/proc/op_resolution_next(datum/op_resolution/R, datum/op_cand/after)
	RETURN_TYPE(/datum/op_cand)
	if(R.fast_rows && after.fast_index)
		return op_fast_next(R, after)
	var/seen = FALSE
	for(var/datum/op_cand/C as anything in R.ordered)
		if(C == after)
			seen = TRUE
			continue
		if(seen && op_cand_when(R, C))
			return C
	return null

/// The unit-test check of a compiled resolution: a whole copy of it must order the same survivors as op_resolve() of the same input, the same way.
/// (op_resolution_winner() checks the winner the walk itself finds.)
/proc/op_click_parity_check(datum/op_resolution/R)
	var/datum/op_resolution/whole = op_click_build(R.actor, R.target, R.held, R.origin, R.authority, R.gesture, TRUE)
	var/datum/op_resolution/full = op_resolve(R.actor, R.target, R.held, R.origin, R.authority, R.gesture, null)
	var/list/mine = whole.ordered
	var/list/theirs = full.ordered
	var/bad = length(mine) != length(theirs)
	for(var/i in 1 to min(length(mine), length(theirs)))
		if(bad)
			break
		var/datum/op_cand/A = mine[i]
		var/datum/op_cand/B = theirs[i]
		bad = !op_cands_same(A, B)
	if(bad)
		stack_trace("op_click_parity: the compiled click and op_resolve() differ for [R.actor?.type] on [R.target?.type] holding [R.held?.type] ([R.gesture]): compiled [op_cand_keys(mine)], full [op_cand_keys(theirs)]")

/// The parity check of a compiled walk's winner: op_resolve()'s winner of the same input is the same candidate.
/proc/op_click_parity_winner(datum/op_resolution/R, datum/op_cand/mine)
	var/datum/op_cand/theirs = op_resolution_winner(op_resolve(R.actor, R.target, R.held, R.origin, R.authority, R.gesture, null))
	if(isnull(mine) != isnull(theirs) || (mine && !op_cands_same(mine, theirs)))
		stack_trace("op_click_parity: the compiled walk's winner differs for [R.actor?.type] on [R.target?.type] holding [R.held?.type] ([R.gesture]): compiled [mine ? op_cand_keys(list(mine)) : "none"], full [theirs ? op_cand_keys(list(theirs)) : "none"]")

/// Are two candidate records the same candidate (op, binding, holder, grant, intent rank, provider)?
/proc/op_cands_same(datum/op_cand/A, datum/op_cand/B)
	return A.oplan == B.oplan && A.binding == B.binding && A.holder == B.holder && A.activation == B.activation && A.rank == B.rank && A.provider?.entry == B.provider?.entry && A.provider?.source == B.provider?.source

/// "key@side" of each candidate, for a parity report.
/proc/op_cand_keys(list/cands)
	var/list/keys = list()
	for(var/datum/op_cand/C as anything in cands)
		keys += "[C.oplan.key]@[C.side]"
	return jointext(keys, ", ")

#undef FAST_PLAN
#undef FAST_BINDING
#undef FAST_ACTIVATION
#undef FAST_RANK
#undef FAST_TIER
#undef FAST_SEQ
#undef FAST_REACH
#undef FAST_SPECIFICITY
#undef FAST_GROUP_FIRST
#undef FAST_GROUP_LAST
#undef FAST_GROUP_RANK
#undef FAST_GROUP_TIER
#undef FAST_GROUP_SPECIFIC
