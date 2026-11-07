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
// Nothing about refusals is computed on the way: an input with no winner that wants its reason told is resolved again by op_resolve(), whose
// near-miss and gate reasons are the ones the player has always seen. An input the compiled path does not take (no gesture, a menu pick or a
// UI press by key, the game acting for itself, an actor its gate refuses) goes to op_resolve() as before. Unit tests compare both on every click
// (op_click_parity).

/// TRUE in the unit-test build: every compiled click is resolved by op_resolve() too and the two orders are compared (a difference is a runtime).
#if defined(UNIT_TESTS) && !defined(BENCHMARK)
GLOBAL_VAR_INIT(op_click_parity, TRUE)
#else
GLOBAL_VAR_INIT(op_click_parity, FALSE)
#endif

/// Compiled resolutions made (the bench counts them beside op_count_resolves).
GLOBAL_VAR_INIT(op_count_compiled, 0)

/datum/op_resolution
	/// The compiled walk's state while it has groups left: list(list(holder, side table, next group), ...) in side order; null once spent or for a
	/// full resolution.
	var/list/fast_sides
	/// TRUE for a compiled resolution: `ordered` holds the survivors made so far, `all` stays empty.
	var/fast = FALSE

/// The compiled resolution of a gestured input, or null when the compiled path does not take it (the caller resolves it with op_resolve()). Its
/// `ordered` grows as op_resolution_winner() and op_resolution_next() walk it.
/proc/op_click_resolution(mob/actor, atom/target, obj/held, origin, authority, gesture)
	RETURN_TYPE(/datum/op_resolution)
	if(isnull(gesture) || origin == ORIGIN_SYSTEM || origin == ORIGIN_MENU || GLOB.op_resolver_legacy)
		return null
	if(actor_gate_reason(actor, origin, authority))
		return null
	GLOB.op_count_compiled++
	var/datum/op_resolution/R = op_resolution_new(actor, target, held, origin, authority, gesture)
	R.fast = TRUE
	var/stance = actor?.op_input_stance()
	var/held_type = held?.type
	var/list/sides = list()
	var/relative = FALSE
	if(target && !QDELETED(target))
		var/list/target_table = op_fast_side(target, CAND_TARGET, origin, authority, gesture, R.intents, held_type, stance)
		relative ||= target_table[3]
		sides += list(list(target, target_table, 1))
	if(held && !QDELETED(held))
		var/list/held_table = op_fast_side(held, CAND_HELD, origin, authority, gesture, R.intents, held_type, stance)
		relative ||= held_table[3]
		sides += list(list(held, held_table, 1))
	if(actor && !QDELETED(actor) && actor != target)
		var/list/actor_table = op_fast_side(actor, CAND_ACTOR, origin, authority, gesture, R.intents, held_type, stance)
		relative ||= actor_table[3]
		sides += list(list(actor, actor_table, 1))
	R.fast_sides = sides
	if(relative || GLOB.op_click_parity)
		// A relative priority moves an op over survivors the walk has not reached: make the whole order, then move as the full sort does.
		while(op_fast_more(R))
			pass()
		if(relative)
			R.ordered = op_order_relative(R.ordered)
	if(GLOB.op_click_parity)
		op_click_parity_check(R)
	return R

/// One holder's compiled table for an input shape on one side: list(groups' rows, groups, has a relative priority, side). The rows are the shape
/// rows (op_side_rows()) every gate the shape decides lets through, ordered by intent rank, then tier (highest first), then collection order;
/// a group is a run of rows tying on rank and tier: list(first, last, rank, tier). Interned on the shape rows, so it goes when they do.
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
		// stable insertion by (rank, tier highest first); collection order breaks the rest
		var/list/entry = list(P, B, acts[i], rank, P.tier, i)
		var/at = length(entries) + 1
		for(var/j in 1 to length(entries))
			var/list/other = entries[j]
			if(rank < other[4] || (rank == other[4] && P.tier > other[5]))
				at = j
				break
		entries.Insert(at, list(entry))
	var/list/groups = list()
	var/start = 1
	while(start <= length(entries))
		var/list/first = entries[start]
		var/stop = start
		while(stop < length(entries))
			var/list/following = entries[stop + 1]
			if(following[4] != first[4] || following[5] != first[5])
				break
			stop++
		groups += list(list(start, stop, first[4], first[5]))
		start = stop + 1
	table = list(entries, groups, relative, side)
	by_stance[stance_key] = table
	return table

/// The intent rank (1 first) at which (op, binding) answers a gestured input of this shape, or 0 when a gate the shape decides drops it: the
/// origin, the authority, an actor-side binding that is not the actor's own, a binding chosen by key, the intents, stance() and gesture(). The
/// same tests, in the same order, as op_silently_dropped() and op_cand_pass1() (which still run on each row the walk reaches, with the instance).
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

/// Makes the next group of survivors and adds them to R.ordered: the group that comes first over the three sides by (rank, tier, side), its
/// rows' instance gates asked (op_cand_pass1()), its survivors ordered by binding specificity. TRUE when it added any; FALSE when no group is left.
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
			if(!best || group[3] < best_group[3] || (group[3] == best_group[3] && group[4] > best_group[4]))
				best = state
				best_group = group
		if(!best)
			R.fast_sides = null
			return FALSE
		best[3] = best[3] + 1
		var/list/batch = op_fast_group(R, best[1], best[2], best_group)
		if(length(batch))
			R.ordered += batch
			return TRUE
	return FALSE

/// The survivors of one group of one side's table, in resolution order.
/proc/op_fast_group(datum/op_resolution/R, datum/holder, list/table, list/group)
	var/list/batch = list()
	var/list/entries = table[1]
	var/side = table[4]
	for(var/i in group[1] to group[2])
		var/list/entry = entries[i]
		var/datum/activation/granted_by = entry[3]
		if(granted_by && (granted_by.dead || !granted_by.runs))
			continue
		var/datum/op_cand/C = op_cand_make(entry[1], entry[2], holder, side, granted_by, entry[6])
		op_cand_pass1(R, C, R.gesture)
		if(!C.dropped_by)
			batch += C
	if(length(batch) > 1)
		op_specificity_sort(batch)
	return batch

/// The candidate after `after` in R's order whose when() conditions hold, or null; a compiled resolution makes more of its order as it goes.
/proc/op_resolution_next(datum/op_resolution/R, datum/op_cand/after)
	RETURN_TYPE(/datum/op_cand)
	var/seen = FALSE
	var/i = 0
	while(TRUE)
		i++
		if(i > length(R.ordered) && !op_fast_more(R))
			return null
		var/datum/op_cand/C = R.ordered[i]
		if(C == after)
			seen = TRUE
			continue
		if(seen && op_cand_when(R, C))
			return C

/// The unit-test check of a compiled resolution (made whole first): op_resolve() of the same input must order the same survivors the same way.
/proc/op_click_parity_check(datum/op_resolution/R)
	var/datum/op_resolution/full = op_resolve(R.actor, R.target, R.held, R.origin, R.authority, R.gesture, null)
	var/list/mine = R.ordered
	var/list/theirs = full.ordered
	var/bad = length(mine) != length(theirs)
	for(var/i in 1 to min(length(mine), length(theirs)))
		if(bad)
			break
		var/datum/op_cand/A = mine[i]
		var/datum/op_cand/B = theirs[i]
		bad = A.oplan != B.oplan || A.binding != B.binding || A.holder != B.holder || A.activation != B.activation || A.rank != B.rank || A.provider?.entry != B.provider?.entry || A.provider?.source != B.provider?.source
	if(bad)
		stack_trace("op_click_parity: the compiled click and op_resolve() differ for [R.actor?.type] on [R.target?.type] holding [R.held?.type] ([R.gesture]): compiled [op_cand_keys(mine)], full [op_cand_keys(theirs)]")

/// "key@side" of each candidate, for a parity report.
/proc/op_cand_keys(list/cands)
	var/list/keys = list()
	for(var/datum/op_cand/C as anything in cands)
		keys += "[C.oplan.key]@[C.side]"
	return jointext(keys, ", ")
