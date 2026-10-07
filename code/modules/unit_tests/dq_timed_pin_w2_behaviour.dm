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

/// Builds a fresh actor, target and held item in `user`, `target` and `held`.
/datum/unit_test/dq_timed_pin_w2/proc/setup_scene()
	return

/// TRUE once the action has had its effect.
/datum/unit_test/dq_timed_pin_w2/proc/is_done()
	return FALSE

/// Takes the scene down so the next one starts clean.
/datum/unit_test/dq_timed_pin_w2/proc/clear_scene()
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
	// a move cancels
	setup_scene()
	start_click()
	T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action again")
	test_time(1 SECOND)
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

/// Pins of one type's own (a refusal, a second worker).
/datum/unit_test/dq_timed_pin_w2/proc/extra_pin()
	return

/// A new actor with a name the pins can recognise.
/datum/unit_test/dq_timed_pin_w2/proc/worker(name = "pinuser")
	var/mob/living/carbon/human/H = person()
	H.ckey = name
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
	held = hold(/obj/item/wrench)

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
	held = hold(/obj/item/screwdriver)

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
	held = hold(/obj/item/wrench)

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
	held = hold(/obj/item/wrench)

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
	held = hold(/obj/item/wrench)

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
	held = hold(/obj/item/crowbar)

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
	held = hold(/obj/item/wrench)

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
