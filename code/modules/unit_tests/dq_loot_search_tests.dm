// The search of a loot pile as an op (code/library/loot/loot_search.dm): the requirements refuse before the wait, the roll runs when the wait ends, and what the
// pile remembers about its searchers is a keyed stat.

/datum/unit_test/dq_loot_search_op
	abstract_type = /datum/unit_test/dq_loot_search_op
	parent_type = /datum/unit_test/dq_timed_pin

/// A searcher with a ckey: the pile marks searchers by it.
/datum/unit_test/dq_loot_search_op/proc/searcher(key)
	var/mob/living/carbon/human/H = person()
	H.ckey = key
	return H

/// Takes the ckeys off the test mobs (a mob that still has one leaves a ghost behind when it is deleted).
/datum/unit_test/dq_loot_search_op/proc/forget_keys()
	for(var/mob/living/carbon/human/H in range(3, run_loc_floor_bottom_left))
		H.ckey = null

/// The things on the test floor that are not the pile or a person.
/datum/unit_test/dq_loot_search_op/proc/found_on_floor()
	. = list()
	for(var/atom/movable/AM as anything in contents_of(run_loc_floor_bottom_left))
		if(istype(AM, /obj/structure/loot_pile) || ismob(AM) || istype(AM, /obj/effect/landmark))
			continue
		. += AM

/// A click starts a timed search that yields nothing before its end and something at it; the searcher is marked in the keyed stat.
/datum/unit_test/dq_loot_search_op/a_search_waits_then_yields

/datum/unit_test/dq_loot_search_op/a_search_waits_then_yields/run_pin()
	var/mob/living/carbon/human/user = searcher("pinsearcher")
	var/obj/structure/loot_pile/maint/junk/P = allocate(/obj/structure/loot_pile/maint/junk, run_loc_floor_bottom_left)
	test_chat_clear()
	test_click(user, P, null)
	TEST_ASSERT(!isnull(running(user)), "a bare hand on the pile starts a timed action")
	TEST_ASSERT(said(user, "You search through"), "it says it began")
	test_time(3 SECONDS)
	TEST_ASSERT_EQUAL(length(found_on_floor()), 0, "nothing is found before the wait ends")
	test_time(4 SECONDS)
	TEST_ASSERT(length(found_on_floor()) >= 1, "something lies on the floor when it ends")
	TEST_ASSERT(said(user, "You found"), "and the searcher is told what it was")
	TEST_ASSERT_EQUAL(loot_search_keys(P, STAT_LOOT_SEARCHED)["pinsearcher"], 1, "the searcher is marked in the keyed stat")
	for(var/atom/movable/AM as anything in found_on_floor())
		qdel(AM)
	forget_keys()

/// The same searcher is refused at once (the requirement, not after a wait), with the old text; the menu says why too; another searcher may search.
/datum/unit_test/dq_loot_search_op/the_same_searcher_is_refused_at_once

/datum/unit_test/dq_loot_search_op/the_same_searcher_is_refused_at_once/run_pin()
	var/mob/living/carbon/human/user = searcher("pinsearcher")
	var/mob/living/carbon/human/other = searcher("pinother")
	var/obj/structure/loot_pile/maint/junk/P = allocate(/obj/structure/loot_pile/maint/junk, run_loc_floor_bottom_left)
	test_click(user, P, null)
	test_time(7 SECONDS)
	for(var/atom/movable/AM as anything in found_on_floor())
		qdel(AM)
	test_chat_clear()
	test_click(user, P, null)
	TEST_ASSERT_NULL(running(user), "the second search starts nothing")
	TEST_ASSERT(said(user, "You can't find anything else vaguely useful"), "and says why, at once")
	var/refused_in_menu = FALSE
	for(var/list/row as anything in op_menu(user, P, null))
		if(findtext("[row["label"]]", "Search") && !row["enabled"])
			refused_in_menu = TRUE
	TEST_ASSERT(refused_in_menu, "the menu greys the search out for this searcher")
	test_click(other, P, null)
	TEST_ASSERT(!isnull(running(other)), "another searcher may search")
	forget_keys()

/// A table that can be searched a number of times: the last yielding search says so, and the pile that deletes itself is gone after it; a pile that is
/// picked clean refuses everyone, whoever they are.
/datum/unit_test/dq_loot_search_op/a_pile_is_picked_clean

/datum/unit_test/dq_loot_search_op/a_pile_is_picked_clean/run_pin()
	var/obj/structure/loot_pile/surface/alien/P = allocate(/obj/structure/loot_pile/surface/alien, run_loc_floor_bottom_left)
	var/datum/loot_decl/decl = loot_decl_for(loot_search_table(P.type))
	TEST_ASSERT_NOTNULL(decl, "the alien pod has a table")
	TEST_ASSERT_EQUAL(decl.loot_left, 5, "it can be searched five times")
	var/yielded = 0
	for(var/i in 1 to 12)
		var/mob/living/carbon/human/user = searcher("pinsearcher[i]")
		test_chat_clear()
		test_click(user, P, null)
		if(isnull(running(user)))
			TEST_ASSERT(said(user, "has been picked clean"), "a refused search of a pod with nothing left says it was picked clean")
			break
		test_time(7 SECONDS)
		if(said(user, "You found"))
			yielded++
		for(var/atom/movable/AM as anything in found_on_floor())
			qdel(AM)
		if(QDELETED(P))
			break
	TEST_ASSERT_EQUAL(yielded, 5, "five searches yielded, then it was picked clean")
	TEST_ASSERT_EQUAL(loot_search_found(P), 5, "the keyed stat counts them")
	forget_keys()

/// A trash pile with something hiding in it: the hider may leap out instead of the search yielding anything, and nothing is marked then.
/datum/unit_test/dq_loot_search_op/a_hider_may_leap_out

/datum/unit_test/dq_loot_search_op/a_hider_may_leap_out/run_pin()
	var/mob/living/carbon/human/user = searcher("pinsearcher")
	var/obj/structure/trash_pile/P = allocate(/obj/structure/trash_pile, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(loot_search_table(P.type), /loot/trash_pile, "a trash pile searches its table")
	TEST_ASSERT_EQUAL(loot_search_wake_chance(P.type), 5, "and wakes a raccoon 5 percent of the time")
	var/mob/living/carbon/human/hider = person() // a mob with no AI of its own to wander out of the pile
	rel_set(P, nameof(hider), hider)
	hider.forceMove(P)
	TEST_ASSERT_EQUAL(P.hider(), hider, "someone is hiding in the pile")
	test_chat_clear()
	test_click(user, P, null)
	test_time(7 SECONDS)
	var/chat = jointext(test_chat_of(user), " / ")
	if(P.hider())
		TEST_ASSERT_EQUAL(P.hider(), hider, "the hider stayed in the pile")
		TEST_ASSERT(said(user, "You found"), "the search yielded something instead ([chat])")
		TEST_ASSERT(!said(user, "leaps out"), "and nothing leapt out ([chat])")
	else
		TEST_ASSERT(said(user, "Some sort of creature leaps out"), "the hider leapt out and the searcher is told ([chat])")
		TEST_ASSERT(!said(user, "You found"), "and nothing was rolled ([chat])")
		TEST_ASSERT(isturf(hider.loc), "the hider is out on the floor ([hider.loc])")
		TEST_ASSERT_NULL(loot_search_keys(P, STAT_LOOT_SEARCHED)["pinsearcher"], "and the searcher was not marked")
	for(var/atom/movable/AM as anything in found_on_floor())
		qdel(AM)
	forget_keys()
