// Behaviour pins for the timed actions of code/game (structures, effects, turfs, mecha, gamemodes), recorded on the legacy
// task_timed / task_start forms before they become ops with wait(). Every pin drives the real click path and records: the duration
// (not done a second before, done a second after), the start message, what a move, a dropped held item or a lost target does
// (nothing is done), what completion does and says, and a refusal. A conversion keeps every assertion; a difference is a documented
// class in doc/rewrite/intended_changes.md.

/datum/unit_test/dq_timed_pin_w2
	abstract_type = /datum/unit_test/dq_timed_pin_w2
	parent_type = /datum/unit_test/dq_timed_pin
	/// The actor of the current scene.
	var/mob/living/carbon/human/user
	/// The target of the current scene.
	var/atom/target
	/// What the actor holds in the current scene (null: a bare hand).
	var/obj/item/held
	/// The action's length in deciseconds (the longest, when it is random).
	var/duration = 0
	/// The shortest it can be (null: the same as duration).
	var/duration_min
	/// A text the start message contains (null: it says nothing).
	var/began
	/// A text the finishing message contains (null: it says nothing).
	var/finished
	/// TRUE when dropping the held item cancels the action.
	var/drop_cancels = FALSE
	/// TRUE when deleting the target must be checked (its loss cancels).
	var/loss_cancels = TRUE
	/// The actors given a ckey, which tidy() takes back.
	var/list/named
	/// FALSE for an action whose failure has a consequence a test world cannot take (a mine that goes off): only the finish is pinned.
	var/cancel_tests = TRUE

/// Builds a fresh actor, target and held item in `user`, `target` and `held`.
/datum/unit_test/dq_timed_pin_w2/proc/setup_scene()
	return

/// TRUE once the action has had its effect.
/datum/unit_test/dq_timed_pin_w2/proc/is_done()
	return FALSE

/// What an action leaves on the floor (its products) belongs to the test, so the leak check does not count it.
/datum/unit_test/dq_timed_pin_w2/proc/tidy()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		own_turf_contents(T)
	for(var/mob/M as anything in named)
		if(!QDELETED(M))
			M.ckey = null // a mob that still has a ckey leaves a ghost behind when it is deleted
	named = null

/// Takes the scene down so the next one starts clean.
/datum/unit_test/dq_timed_pin_w2/proc/clear_scene()
	tidy()
	if(target && !QDELETED(target))
		qdel(target)
	target = null

/// Clicks the target as the pin does: the held item (or a bare hand) on it.
/datum/unit_test/dq_timed_pin_w2/proc/start_click()
	test_chat_clear()
	test_click(user, target, held)

/datum/unit_test/dq_timed_pin_w2/run_pin()
	var/shortest = isnull(duration_min) ? duration : duration_min
	// the length, the start message and the finish
	setup_scene()
	start_click()
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	var/declared = declared_duration(T)
	TEST_ASSERT(isnull(declared) || (declared >= shortest && declared <= duration), "it lasts as long as it should")
	if(began)
		TEST_ASSERT(said(user, began), "it says it began")
	TEST_ASSERT(!is_done(), "nothing is done at the start")
	test_time(shortest - 1 SECOND)
	TEST_ASSERT(!is_done(), "not done a second before the end")
	test_time(duration - shortest + 2 SECONDS)
	TEST_ASSERT(is_done(), "done a second after the end")
	if(finished)
		TEST_ASSERT(said(user, finished), "it says it finished")
	clear_scene()
	if(!cancel_tests)
		extra_pin()
		return
	// a move cancels
	setup_scene()
	start_click()
	T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action again")
	test_time(round(duration / 2))
	user.forceMove(get_step(user, EAST))
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!is_done(), "moving cancels: nothing is done")
	TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
	clear_scene()
	// a dropped held item cancels
	if(drop_cancels)
		setup_scene()
		start_click()
		T = running(user)
		TEST_ASSERT(!isnull(T), "the click starts a timed action a third time")
		user.drop_from_inventory(held)
		test_time(duration + 2 SECONDS)
		TEST_ASSERT(!is_done(), "dropping the held item cancels: nothing is done")
		TEST_ASSERT(was_cancelled(T, user), "the action ends cancelled")
		clear_scene()
	// a lost target cancels
	if(loss_cancels)
		setup_scene()
		start_click()
		T = running(user)
		TEST_ASSERT(!isnull(T), "the click starts a timed action a last time")
		qdel(target)
		test_time(duration + 2 SECONDS)
		TEST_ASSERT(was_cancelled(T, user), "deleting the target cancels the action")
		clear_scene()
	extra_pin()
	tidy()

/// Pins of one type's own (a refusal, a second worker).
/datum/unit_test/dq_timed_pin_w2/proc/extra_pin()
	return

/// A new actor with a name the pins can recognise.
/datum/unit_test/dq_timed_pin_w2/proc/worker(name = "pinuser")
	var/mob/living/carbon/human/H = person()
	H.ckey = name
	LAZYADD(named, H)
	return H

/// A wrench / screwdriver / crowbar of the default speed in the actor's hand.
/datum/unit_test/dq_timed_pin_w2/proc/hold(path)
	var/obj/item/I = allocate(path, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	return I

// ---- Searching a pile: loot_pile, trash_pile (a search claims the pile) ----

/datum/unit_test/dq_timed_pin_w2/loot_pile_search
	duration = 6 SECONDS
	duration_min = 4 SECONDS
	began = "You search through"

/datum/unit_test/dq_timed_pin_w2/loot_pile_search/setup_scene()
	user = worker()
	target = allocate(/obj/structure/loot_pile/maint/junk, run_loc_floor_bottom_left)

/datum/unit_test/dq_timed_pin_w2/loot_pile_search/is_done()
	var/obj/structure/loot_pile/P = target
	return !QDELETED(P) && ("pinuser" in P.searchedby)

/datum/unit_test/dq_timed_pin_w2/loot_pile_search/extra_pin()
	setup_scene()
	var/mob/living/carbon/human/two = person()
	test_click(user, target, null)
	TEST_ASSERT(!isnull(running(user)), "the first search runs")
	test_chat_clear()
	test_click(two, target, null)
	TEST_ASSERT_NULL(running(two), "a second searcher is refused while the pile is being searched")
	TEST_ASSERT(length(test_chat_of(two)), "and is told so")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(is_done(), "the first search finishes")
	clear_scene()

/datum/unit_test/dq_timed_pin_w2/trash_pile_search
	duration = 6 SECONDS
	duration_min = 4 SECONDS
	began = "You search through"

/datum/unit_test/dq_timed_pin_w2/trash_pile_search/setup_scene()
	user = worker()
	target = allocate(/obj/structure/trash_pile, run_loc_floor_bottom_left)

/datum/unit_test/dq_timed_pin_w2/trash_pile_search/is_done()
	var/obj/structure/trash_pile/P = target
	return !QDELETED(P) && ("pinuser" in P.searchedby)

/datum/unit_test/dq_timed_pin_w2/trash_pile_search/extra_pin()
	setup_scene()
	var/mob/living/carbon/human/two = person()
	test_click(user, target, null)
	TEST_ASSERT(!isnull(running(user)), "the first search runs")
	test_chat_clear()
	test_click(two, target, null)
	TEST_ASSERT_NULL(running(two), "a second searcher is refused while the pile is being searched")
	TEST_ASSERT(length(test_chat_of(two)), "and is told so")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(is_done(), "the first search finishes")
	clear_scene()

// ---- Pushing a desert rock ----

/datum/unit_test/dq_timed_pin_w2/desert_rock_push
	duration = 3 SECONDS
	began = "You push on the"
	var/turf/start

/datum/unit_test/dq_timed_pin_w2/desert_rock_push/setup_scene()
	user = person()
	user.dir = EAST
	target = allocate(/obj/structure/prop/desert_rock/rock, run_loc_floor_bottom_left)
	start = get_turf(target)

/datum/unit_test/dq_timed_pin_w2/desert_rock_push/is_done()
	return !QDELETED(target) && get_turf(target) != start

// ---- Disassembling a pillow pile ----

/datum/unit_test/dq_timed_pin_w2/pillowpile_disassemble
	duration = 3 SECONDS
	began = "Now disassembling the large pillow pile"
	finished = "dissasembled the large pillow pile"

/datum/unit_test/dq_timed_pin_w2/pillowpile_disassemble/setup_scene()
	user = person()
	target = allocate(/obj/structure/bed/pillowpile, run_loc_floor_bottom_left)

/datum/unit_test/dq_timed_pin_w2/pillowpile_disassemble/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/pillowpilefront_disassemble
	duration = 3 SECONDS
	began = "Now disassembling the front of the pillow pile"
	finished = "dissasembled the the front of the pillow pile"

/datum/unit_test/dq_timed_pin_w2/pillowpilefront_disassemble/setup_scene()
	user = person()
	target = allocate(/obj/structure/bed/pillowpilefront, run_loc_floor_bottom_left)

/datum/unit_test/dq_timed_pin_w2/pillowpilefront_disassemble/is_done()
	return QDELETED(target)

// ---- Railing: wrench, welder, screwdriver ----

/datum/unit_test/dq_timed_pin_w2/railing_wrench
	duration = 2 SECONDS
	finished = "You dismantle"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/railing_wrench/setup_scene()
	user = person()
	var/obj/structure/railing/R = allocate(/obj/structure/railing, run_loc_floor_bottom_left)
	R.set_anchored(FALSE)
	target = R
	held = hold(/obj/item/tool/wrench)

/datum/unit_test/dq_timed_pin_w2/railing_wrench/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/railing_wrench/extra_pin()
	setup_scene()
	var/obj/structure/railing/R = target
	R.set_anchored(TRUE)
	start_click()
	TEST_ASSERT_NULL(running(user), "a wrench on an anchored railing starts nothing")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!QDELETED(R), "and the railing stays")
	clear_scene()

/datum/unit_test/dq_timed_pin_w2/railing_screwdriver
	duration = 1 SECOND
	finished = "You have unfastened"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/railing_screwdriver/setup_scene()
	user = person()
	target = allocate(/obj/structure/railing, run_loc_floor_bottom_left)
	held = hold(/obj/item/tool/screwdriver)

/datum/unit_test/dq_timed_pin_w2/railing_screwdriver/is_done()
	var/obj/structure/railing/R = target
	return !QDELETED(R) && !R.anchored

/datum/unit_test/dq_timed_pin_w2/railing_welder
	duration = 2 SECONDS
	finished = "You repair some damage"
	drop_cancels = TRUE
	var/before = 0

/datum/unit_test/dq_timed_pin_w2/railing_welder/setup_scene()
	user = person()
	var/obj/structure/railing/R = allocate(/obj/structure/railing, run_loc_floor_bottom_left)
	R.update_integrity(R.max_integrity - 40)
	before = R.get_integrity()
	target = R
	var/obj/item/weldingtool/W = hold(/obj/item/weldingtool)
	W.reagents.add_reagent(REAGENT_ID_FUEL, W.max_fuel)
	W.setWelding(TRUE)
	held = W

/datum/unit_test/dq_timed_pin_w2/railing_welder/is_done()
	var/obj/structure/railing/R = target
	return !QDELETED(R) && R.get_integrity() > before

/datum/unit_test/dq_timed_pin_w2/railing_welder/extra_pin()
	setup_scene()
	var/obj/structure/railing/R = target
	R.update_integrity(R.max_integrity)
	start_click()
	TEST_ASSERT_NULL(running(user), "a welder on an undamaged railing starts nothing")
	clear_scene()

// ---- Low wall: wrench ----

/datum/unit_test/dq_timed_pin_w2/low_wall_wrench
	duration = 4 SECONDS
	began = "Now disassembling the low wall"
	finished = "You disassembled the low wall"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/low_wall_wrench/setup_scene()
	user = person()
	target = allocate(/obj/structure/low_wall, run_loc_floor_bottom_left)
	held = hold(/obj/item/tool/wrench)

/datum/unit_test/dq_timed_pin_w2/low_wall_wrench/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/low_wall_wrench/extra_pin()
	setup_scene()
	var/obj/structure/grille/G = allocate(/obj/structure/grille, run_loc_floor_bottom_left)
	start_click()
	TEST_ASSERT_NULL(running(user), "a wrench on a low wall that still has a grille starts nothing")
	TEST_ASSERT(said(user, "There is still a grille on the low wall"), "and says why")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!QDELETED(target) && !QDELETED(G), "and nothing is taken apart")
	clear_scene()

// ---- Janitorial cart: wrench ----

/datum/unit_test/dq_timed_pin_w2/janicart_wrench
	duration = 5 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/janicart_wrench/setup_scene()
	user = person()
	var/obj/structure/janitorialcart/C = allocate(/obj/structure/janitorialcart, run_loc_floor_bottom_left)
	C.dismantled = FALSE
	target = C
	held = hold(/obj/item/tool/wrench)

/datum/unit_test/dq_timed_pin_w2/janicart_wrench/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/janicart_wrench/extra_pin()
	setup_scene()
	var/obj/structure/janitorialcart/C = target
	C.has_items = TRUE
	start_click()
	TEST_ASSERT_NULL(running(user), "a wrench on a cart that holds things starts nothing")
	clear_scene()

// ---- Drop pod: wrench ----

/datum/unit_test/dq_timed_pin_w2/droppod_wrench
	duration = 10 SECONDS
	began = "You start breaking down"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/droppod_wrench/setup_scene()
	user = person()
	var/obj/structure/drop_pod/P = allocate(/obj/structure/drop_pod, run_loc_floor_bottom_left)
	P.finished = TRUE
	target = P
	held = hold(/obj/item/tool/wrench)

/datum/unit_test/dq_timed_pin_w2/droppod_wrench/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/droppod_wrench/extra_pin()
	setup_scene()
	var/obj/structure/drop_pod/P = target
	P.finished = FALSE
	start_click()
	TEST_ASSERT_NULL(running(user), "a wrench on a pod that has not been opened starts nothing")
	TEST_ASSERT(said(user, "hasn't been opened yet"), "and says why")
	clear_scene()

// ---- Toilet: crowbar the cistern, wrench it apart ----

/datum/unit_test/dq_timed_pin_w2/toilet_crowbar
	duration = 3 SECONDS
	began = "You start to lift the lid off the cistern"
	finished = "You lift the lid off the cistern"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/toilet_crowbar/setup_scene()
	user = person()
	var/obj/structure/toilet/T = allocate(/obj/structure/toilet, run_loc_floor_bottom_left)
	T.set_cistern(FALSE)
	target = T
	held = hold(/obj/item/tool/crowbar)

/datum/unit_test/dq_timed_pin_w2/toilet_crowbar/is_done()
	var/obj/structure/toilet/T = target
	return !QDELETED(T) && T.cistern

/datum/unit_test/dq_timed_pin_w2/toilet_wrench
	duration = 5 SECONDS
	began = "You begin to dismantle"
	finished = "You dismantle"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/toilet_wrench/setup_scene()
	user = person()
	var/obj/structure/toilet/T = allocate(/obj/structure/toilet, run_loc_floor_bottom_left)
	T.set_cistern(TRUE)
	target = T
	held = hold(/obj/item/tool/wrench)

/datum/unit_test/dq_timed_pin_w2/toilet_wrench/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/toilet_wrench/extra_pin()
	setup_scene()
	var/obj/structure/toilet/T = target
	T.set_cistern(FALSE)
	start_click()
	TEST_ASSERT_NULL(running(user), "a wrench on a toilet with the cistern shut starts nothing")
	clear_scene()
	setup_scene()
	T = target
	T.refilling = TRUE
	start_click()
	TEST_ASSERT_NULL(running(user), "a wrench on a toilet that is refilling starts nothing")
	TEST_ASSERT(said(user, "Wait for"), "and says to wait")
	clear_scene()

// ---- Girder: a plasmacutter slices it apart ----

/datum/unit_test/dq_timed_pin_w2/girder_plasmacutter
	duration = 3 SECONDS
	began = "Now slicing apart the girder"
	finished = "You slice apart the girder"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/girder_plasmacutter/setup_scene()
	user = person()
	target = allocate(/obj/structure/girder, run_loc_floor_bottom_left)
	held = hold(/obj/item/pickaxe/plasmacutter)

/datum/unit_test/dq_timed_pin_w2/girder_plasmacutter/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/girder_cult_plasmacutter
	duration = 3 SECONDS
	began = "Now slicing apart the girder"
	finished = "You slice apart the girder"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/girder_cult_plasmacutter/setup_scene()
	user = person()
	target = allocate(/obj/structure/girder/cult, run_loc_floor_bottom_left)
	held = hold(/obj/item/pickaxe/plasmacutter)

/datum/unit_test/dq_timed_pin_w2/girder_cult_plasmacutter/is_done()
	return QDELETED(target)

// ---- Simple door: dug through with a pickaxe ----

/datum/unit_test/dq_timed_pin_w2/simple_door_dig
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/simple_door_dig/setup_scene()
	user = person()
	var/obj/structure/simple_door/D = allocate(/obj/structure/simple_door, run_loc_floor_bottom_left)
	target = D
	var/obj/item/pickaxe/P = hold(/obj/item/pickaxe)
	held = P
	duration = round(P.digspeed * D.get_integrity() / 10)

/datum/unit_test/dq_timed_pin_w2/simple_door_dig/is_done()
	return QDELETED(target)

// ---- A tree searched for sticks ----

/datum/unit_test/dq_timed_pin_w2/tree_sticks
	duration = 5 SECONDS
	began = "for loose sticks"

/datum/unit_test/dq_timed_pin_w2/tree_sticks/setup_scene()
	user = person()
	target = allocate(/obj/structure/flora/tree/desert_planet/palmtree, run_loc_floor_bottom_left)

/datum/unit_test/dq_timed_pin_w2/tree_sticks/is_done()
	var/obj/structure/flora/tree/T = target
	return !QDELETED(T) && !T.sticks

/datum/unit_test/dq_timed_pin_w2/tree_sticks/extra_pin()
	setup_scene()
	var/obj/structure/flora/tree/T = target
	T.sticks = FALSE
	start_click()
	TEST_ASSERT_NULL(running(user), "a tree with no sticks starts nothing")
	TEST_ASSERT(said(user, "You don't see any loose sticks"), "and says so")
	clear_scene()

// ---- Snow: scooped up by hand ----

/datum/unit_test/dq_timed_pin_w2/snow_scoop
	duration = 1 SECOND
	loss_cancels = FALSE
	var/turf/old_turf_type

/datum/unit_test/dq_timed_pin_w2/snow_scoop/setup_scene()
	user = person()
	var/turf/T = run_loc_floor_bottom_left
	if(!istype(T, /turf/simulated/floor/outdoors/snow))
		old_turf_type = T.type
		T = T.ChangeTurf(/turf/simulated/floor/outdoors/snow)
	target = T
	user.forceMove(T)

/datum/unit_test/dq_timed_pin_w2/snow_scoop/is_done()
	for(var/obj/item/stack/material/snow/S in user.get_all_held_items())
		return TRUE
	return FALSE

/datum/unit_test/dq_timed_pin_w2/snow_scoop/clear_scene()
	for(var/obj/item/stack/material/snow/S in view(1, user))
		qdel(S)
	if(old_turf_type && istype(target, /turf))
		var/turf/T = target
		T.ChangeTurf(old_turf_type)
		old_turf_type = null
	target = null

// ---- Weight machine: a lift claims the machine ----

/datum/unit_test/dq_timed_pin_w2/weightlifter_lift
	finished = "You lift the weights"
	var/start_nutrition = 300

/datum/unit_test/dq_timed_pin_w2/weightlifter_lift/setup_scene()
	user = person()
	user.set_nutrition(start_nutrition)
	user.weight = 150
	var/obj/structure/fitness/weightlifter/W = allocate(/obj/structure/fitness/weightlifter, run_loc_floor_bottom_left)
	target = W
	duration = 3 SECONDS + (W.weight * 10)

/datum/unit_test/dq_timed_pin_w2/weightlifter_lift/is_done()
	return said(user, "You lift the weights")

/datum/unit_test/dq_timed_pin_w2/weightlifter_lift/extra_pin()
	setup_scene()
	var/mob/living/carbon/human/two = person()
	two.set_nutrition(300)
	two.weight = 150
	test_click(user, target, null)
	TEST_ASSERT(!isnull(running(user)), "the first lifter runs")
	test_click(two, target, null)
	TEST_ASSERT_NULL(running(two), "a second lifter is refused while the machine is in use")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(is_done(), "the first lift finishes")
	clear_scene()

// ---- A bedsheet cut up with something sharp ----

/datum/unit_test/dq_timed_pin_w2/bedsheet_cut
	duration = 5 SECONDS
	began = "You begin cutting up"
	finished = "You cut"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/bedsheet_cut/setup_scene()
	user = person()
	target = allocate(/obj/item/bedsheet, run_loc_floor_bottom_left)
	held = hold(/obj/item/material/knife)

/datum/unit_test/dq_timed_pin_w2/bedsheet_cut/is_done()
	return QDELETED(target)

// ---- A barricade mended with a sheet of its own material ----

/datum/unit_test/dq_timed_pin_w2/barricade_repair
	duration = 2 SECONDS
	drop_cancels = TRUE
	var/obj/item/stack/material/wood/planks

/datum/unit_test/dq_timed_pin_w2/barricade_repair/setup_scene()
	user = person()
	var/obj/structure/barricade/B = allocate(/obj/structure/barricade, run_loc_floor_bottom_left)
	B.update_integrity(B.max_integrity - 20)
	target = B
	planks = allocate(/obj/item/stack/material/wood, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(planks)
	held = planks

/datum/unit_test/dq_timed_pin_w2/barricade_repair/is_done()
	var/obj/structure/barricade/B = target
	return !QDELETED(B) && B.get_integrity() >= B.max_integrity && planks.get_amount() == 4

/datum/unit_test/dq_timed_pin_w2/barricade_repair/extra_pin()
	setup_scene()
	var/obj/structure/barricade/B = target
	B.update_integrity(B.max_integrity)
	start_click()
	TEST_ASSERT_NULL(running(user), "a sound barricade starts no repair")
	TEST_ASSERT_EQUAL(planks.get_amount(), 5, "and spends nothing")
	clear_scene()

// ---- A mirror frame given glass ----

/datum/unit_test/dq_timed_pin_w2/mirror_add_glass
	duration = 2 SECONDS
	began = "You start to add the glass"
	finished = "You add the glass"
	drop_cancels = TRUE
	var/obj/item/stack/material/glass/sheets

/datum/unit_test/dq_timed_pin_w2/mirror_add_glass/setup_scene()
	user = person()
	var/obj/structure/mirror/M = allocate(/obj/structure/mirror, run_loc_floor_bottom_left)
	M.glass = 0
	M.shattered = 0
	target = M
	sheets = allocate(/obj/item/stack/material/glass, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(sheets)
	held = sheets

/datum/unit_test/dq_timed_pin_w2/mirror_add_glass/is_done()
	var/obj/structure/mirror/M = target
	return !QDELETED(M) && M.glass && sheets.get_amount() == 3

/datum/unit_test/dq_timed_pin_w2/mirror_add_glass/extra_pin()
	setup_scene()
	sheets.set_amount(1)
	start_click()
	TEST_ASSERT_NULL(running(user), "too little glass starts nothing")
	clear_scene()

// ---- A mine primed in hand ----

/datum/unit_test/dq_timed_pin_w2/mine_prime
	duration = 10 SECONDS
	began = "You start priming"
	cancel_tests = FALSE

/datum/unit_test/dq_timed_pin_w2/mine_prime/setup_scene()
	user = person()
	var/obj/item/mine/M = allocate(/obj/item/mine, run_loc_floor_bottom_left)
	user.put_in_active_hand(M)
	target = M
	held = M

/datum/unit_test/dq_timed_pin_w2/mine_prime/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w2/mine_prime/clear_scene()
	for(var/obj/effect/mine/M in view(1, user))
		qdel(M)
	target = null

// ---- A trap taken off a mine with a screwdriver ----

/datum/unit_test/dq_timed_pin_w2/mine_untrap
	duration = 10 SECONDS
	began = "You begin removing"
	finished = "You finish disconnecting"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/mine_untrap/setup_scene()
	user = person()
	var/obj/item/mine/M = allocate(/obj/item/mine, run_loc_floor_bottom_left)
	var/obj/item/assembly/signaler/S = allocate(/obj/item/assembly/signaler, run_loc_floor_bottom_left)
	rel_set(M, nameof(M.trap), S)
	target = M
	held = hold(/obj/item/tool/screwdriver)

/datum/unit_test/dq_timed_pin_w2/mine_untrap/is_done()
	var/obj/item/mine/M = target
	return !QDELETED(M) && isnull(M.trap)

/datum/unit_test/dq_timed_pin_w2/mine_untrap/extra_pin()
	setup_scene()
	var/obj/item/mine/M = target
	rel_clear(M, nameof(M.trap))
	start_click()
	TEST_ASSERT_NULL(running(user), "a screwdriver on a mine with no trap starts nothing")
	clear_scene()

// ---- An anomaly scanner buffering an anomaly ----

/datum/unit_test/dq_timed_pin_w2/anomaly_buffered
	duration = 1 SECOND
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/anomaly_buffered/setup_scene()
	user = person()
	var/obj/effect/anomaly/A = allocate(/obj/effect/anomaly/bioscrambler, run_loc_floor_bottom_left)
	A.stabilize(FALSE, TRUE, TRUE)
	target = A
	held = hold(/obj/item/anomaly_scanner)

/datum/unit_test/dq_timed_pin_w2/anomaly_buffered/is_done()
	var/obj/item/anomaly_scanner/S = held
	return S.buffered_anomaly == target

// ---- Flora: uprooted with a shovel ----

/datum/unit_test/dq_timed_pin_w2/flora_uproot
	duration = 3 SECONDS
	began = "You start uprooting"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/flora_uproot/setup_scene()
	user = person()
	target = allocate(/obj/structure/flora/bush, run_loc_floor_bottom_left)
	held = hold(/obj/item/shovel)

/datum/unit_test/dq_timed_pin_w2/flora_uproot/is_done()
	return QDELETED(target)

// ---- A potted plant: an item hidden in it, then found ----

/datum/unit_test/dq_timed_pin_w2/pottedplant_hide
	duration = 1 SECOND
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w2/pottedplant_hide/setup_scene()
	user = person()
	target = allocate(/obj/structure/flora/pottedplant, run_loc_floor_bottom_left)
	held = hold(/obj/item/pen)

/datum/unit_test/dq_timed_pin_w2/pottedplant_hide/is_done()
	var/obj/structure/flora/pottedplant/P = target
	return !QDELETED(P) && P.stored_item == held

/datum/unit_test/dq_timed_pin_w2/pottedplant_hide/extra_pin()
	setup_scene()
	start_click()
	user.drop_from_inventory(held)
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(said(user, "You refrain from putting things into the plant pot"), "a cancelled hide says so")
	clear_scene()

/datum/unit_test/dq_timed_pin_w2/pottedplant_search
	duration = 1 SECOND
	finished = "You find"

/datum/unit_test/dq_timed_pin_w2/pottedplant_search/setup_scene()
	user = person()
	var/obj/structure/flora/pottedplant/P = allocate(/obj/structure/flora/pottedplant, run_loc_floor_bottom_left)
	var/obj/item/pen/pen = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	pen.forceMove(P)
	rel_set(P, nameof(P.stored_item), pen)
	target = P

/datum/unit_test/dq_timed_pin_w2/pottedplant_search/is_done()
	var/obj/structure/flora/pottedplant/P = target
	return !QDELETED(P) && isnull(P.stored_item)

/datum/unit_test/dq_timed_pin_w2/pottedplant_search/extra_pin()
	var/mob/living/carbon/human/other = person()
	var/obj/structure/flora/pottedplant/P = allocate(/obj/structure/flora/pottedplant, run_loc_floor_bottom_left)
	test_chat_clear()
	test_click(other, P, null)
	TEST_ASSERT_NULL(running(other), "searching an empty pot starts nothing")
	TEST_ASSERT(said(other, "You see nothing of interest"), "and says so")

// ---- A lying mob crawls an object across to a tile ----

/datum/unit_test/dq_timed_pin_w2/turf_crawl_drag
	duration = 25
	loss_cancels = FALSE
	var/obj/item/pen/dragged
	var/turf/start

/datum/unit_test/dq_timed_pin_w2/turf_crawl_drag/setup_scene()
	user = person()
	user.lying = TRUE
	start = run_loc_floor_bottom_left
	dragged = allocate(/obj/item/pen, start)
	target = get_step(start, EAST)

/datum/unit_test/dq_timed_pin_w2/turf_crawl_drag/start_click()
	test_chat_clear()
	test_drag(user, dragged, target)

/datum/unit_test/dq_timed_pin_w2/turf_crawl_drag/is_done()
	return get_turf(dragged) == target

/datum/unit_test/dq_timed_pin_w2/turf_crawl_drag/clear_scene()
	if(dragged && !QDELETED(dragged))
		qdel(dragged)
	target = null

// ---- Low wall: a grille from rods, a window from glass ----

/datum/unit_test/dq_timed_pin_w2/low_wall_grille
	duration = 1 SECOND
	began = "Assembling grille"
	drop_cancels = TRUE
	var/obj/item/stack/rods/rods

/datum/unit_test/dq_timed_pin_w2/low_wall_grille/setup_scene()
	user = person()
	target = allocate(/obj/structure/low_wall/bay, run_loc_floor_bottom_left)
	rods = allocate(/obj/item/stack/rods, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(rods)
	held = rods

/datum/unit_test/dq_timed_pin_w2/low_wall_grille/is_done()
	return rods.get_amount() == 3 && !isnull(locate(/obj/structure/grille) in get_turf(target))

/datum/unit_test/dq_timed_pin_w2/low_wall_grille/clear_scene()
	for(var/obj/structure/grille/G in get_turf(target))
		qdel(G)
	..()

/datum/unit_test/dq_timed_pin_w2/low_wall_grille/extra_pin()
	setup_scene()
	rods.set_amount(1)
	start_click()
	TEST_ASSERT_NULL(running(user), "one rod starts nothing")
	clear_scene()

/datum/unit_test/dq_timed_pin_w2/low_wall_window
	duration = 4 SECONDS
	began = "Assembling window"
	drop_cancels = TRUE
	var/obj/item/stack/material/glass/sheets

/datum/unit_test/dq_timed_pin_w2/low_wall_window/setup_scene()
	user = person()
	target = allocate(/obj/structure/low_wall/bay, run_loc_floor_bottom_left)
	sheets = allocate(/obj/item/stack/material/glass, run_loc_floor_bottom_left, 8)
	user.put_in_active_hand(sheets)
	held = sheets

/datum/unit_test/dq_timed_pin_w2/low_wall_window/is_done()
	return sheets.get_amount() == 4 && !isnull(locate(/obj/structure/window) in get_turf(target))

/datum/unit_test/dq_timed_pin_w2/low_wall_window/clear_scene()
	for(var/obj/structure/window/W in get_turf(target))
		qdel(W)
	..()

// ---- Grille: a window placed from a stack ----

/datum/unit_test/dq_timed_pin_w2/grille_window
	duration = 2 SECONDS
	began = "You start placing the window"
	drop_cancels = TRUE
	var/obj/item/stack/material/glass/sheets

/datum/unit_test/dq_timed_pin_w2/grille_window/setup_scene()
	user = person()
	user.dir = SOUTH
	target = allocate(/obj/structure/grille, run_loc_floor_bottom_left)
	sheets = allocate(/obj/item/stack/material/glass, run_loc_floor_bottom_left, 5)
	user.put_in_active_hand(sheets)
	held = sheets

/datum/unit_test/dq_timed_pin_w2/grille_window/is_done()
	return sheets.get_amount() == 4 && !isnull(locate(/obj/structure/window) in get_turf(target))

/datum/unit_test/dq_timed_pin_w2/grille_window/clear_scene()
	for(var/obj/structure/window/W in get_turf(target))
		qdel(W)
	..()
