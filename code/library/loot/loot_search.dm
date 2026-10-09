// Searching a pile (doc/rewrite/proposals/loot_and_map_resolvers.md, Option B): search is an op, not a proc.
//
//   CAPABILITIES(/obj/structure/loot_pile)
//       op("search", hand(), label("Search"), claims(), needs(req(/mob/living, of = ON_ACTOR, silent = TRUE)),
//           needs(req_loot_unsearched(), req_loot_not_picked_clean()), begins(MSG(loot_pile/searching)), wait(PROC_REF(search_time)), loot_rolls())
//
// The table a pile searches is its loot_search(table =) entry (loot_entries.dm); the tiers, the depletion and the repeat rule are the table's own loot(...) rows.
// The two refusals are requirements: the menu greys the op out with the reason, and a refused search costs the searcher no waiting. The roll is the effect
// part loot_rolls(), which runs the tiered draw when the wait ends (loot_search_roll(): the same draw, the same seeds, as the proc it replaced).
// `loot_rolls(unless = PROC_REF(x))` lets the pile's own handler take the search over (a hider that leaps out of a trash pile): x(datum/act/op/A) answers TRUE.
//
// What a pile remembers about its searchers is two keyed stats, not lists on the instance and a global: STAT_LOOT_SEARCHED holds, per searcher key (the
// ckey), that the key searched the pile (the "already searched" refusal), and STAT_LOOT_FOUND how many of that key's searches yielded something (the sum over
// the keys is what depletion counts). A searcher without a ckey (a test mob, an NPC) is never marked and is counted under "(no key)".

/// Searcher key -> TRUE-ish (1): the keys that searched this pile.
STAT(/obj/structure, loot_searched, SUM_PER_KEY, virtual = TRUE)
/// Searcher key -> how many of that key's searches yielded something.
STAT(/obj/structure, loot_found, SUM_PER_KEY, virtual = TRUE)

MSG_DEF_SELF(loot_search/picked_clean, span_warning("%T% has been picked clean."))
MSG_DEF_SELF(loot_search/nothing_more, span_warning("You can't find anything else vaguely useful in %T%.  Another set of eyes might, however."))

/// The key -> count list of one of the pile's search stats (a fresh read, empty when nothing was held).
/proc/loot_search_keys(obj/structure/source, stat)
	READS_FROM(source)
	return stat_value(source, stat) || list()

/// How many searches of `source` yielded something, by anyone: what a table's depletion counts.
/proc/loot_search_found(obj/structure/source)
	READS_FROM(source)
	var/list/by_key = loot_search_keys(source, STAT_LOOT_FOUND)
	var/total = 0
	for(var/key in by_key)
		total += by_key[key]
	return total

/// The message type that says why `L` may not search `source` now, or null: the pile is picked clean, or this searcher already searched it.
/proc/loot_search_refusal(obj/structure/source, mob/living/L)
	READS_FROM(source)
	var/datum/loot_decl/decl = loot_decl_for(loot_search_table(source.type))
	if(!decl)
		return null
	if(decl.loot_left && loot_search_found(source) >= decl.loot_left)
		return /datum/msg/loot_search/picked_clean
	if(L?.ckey && !decl.repeat_search && loot_search_keys(source, STAT_LOOT_SEARCHED)[L.ckey])
		return /datum/msg/loot_search/nothing_more
	return null

/// The pile has not been searched out (a table's depletion: `left` yielding searches by anyone).
/proc/req_loot_not_picked_clean()
	return part_make(/datum/entry/part/req/loot_not_picked_clean)

/datum/entry/part/req/loot_not_picked_clean
	part_name = "req_loot_not_picked_clean"
	default_reason = /datum/msg/loot_search/picked_clean

/datum/entry/part/req/loot_not_picked_clean/holds(datum/act/op/A)
	return loot_search_refusal(A.holder, A.actor) != /datum/msg/loot_search/picked_clean

/// The searcher has not searched this pile yet (unless the table lets the same searcher search again).
/proc/req_loot_unsearched()
	return part_make(/datum/entry/part/req/loot_unsearched)

/datum/entry/part/req/loot_unsearched
	part_name = "req_loot_unsearched"
	default_reason = /datum/msg/loot_search/nothing_more

/datum/entry/part/req/loot_unsearched/holds(datum/act/op/A)
	return loot_search_refusal(A.holder, A.actor) != /datum/msg/loot_search/nothing_more

/// loot_rolls(unless =): the tiered draw of the pile's table, when the wait is over. `unless` (PROC_REF(x), x(datum/act/op/A)) answers TRUE when the
/// pile took the search over and nothing is rolled.
/proc/loot_rolls(unless = null)
	return part_make(/datum/entry/part/effect/loot_rolls, list("unless" = unless))

/datum/entry/part/effect/loot_rolls
	part_name = "loot_rolls"

/datum/entry/part/effect/loot_rolls/run_effect(datum/act/op/A)
	var/taken_over = src.args["unless"]
	if(taken_over && op_call(A, taken_over))
		return OP_OK
	loot_search_roll(A.holder, A.actor)
	return OP_OK
