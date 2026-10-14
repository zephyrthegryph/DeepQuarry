// Behaviour pins for the timed actions of code/game (items, structures, turfs) and code/modules/projectiles (worker X), recorded on the legacy
// task_timed / task_start forms before they become ops with wait(). Same harness as dq_timed_pin_w2_behaviour.dm: every pin drives the real click
// path and records the duration (not done a second before, done a second after), the start message, what a move, a dropped held item or a lost
// target does (nothing is done), what completion does and says, and a refusal. A conversion keeps every assertion; a difference is a documented
// class in doc/rewrite/intended_changes.md.

/datum/unit_test/dq_timed_pin_w5
	abstract_type = /datum/unit_test/dq_timed_pin_w5
	parent_type = /datum/unit_test/dq_timed_pin
	/// The actor of the current scene.
	var/mob/living/carbon/human/user
	/// The target of the current scene.
	var/atom/target
	/// What the actor holds in the current scene (null: a bare hand).
	var/obj/item/held
	/// The action's length in deciseconds.
	var/duration = 0
	/// A text the start message contains (null: it says nothing).
	var/began
	/// A text the finishing message contains (null: it says nothing).
	var/finished
	/// TRUE when dropping the held item cancels the action.
	var/drop_cancels = FALSE
	/// TRUE when deleting the target must be checked (its loss cancels).
	var/loss_cancels = TRUE
	/// The key of a context-menu op the scene starts (null: a click).
	var/menu_key

/// Builds a fresh actor, target and held item in `user`, `target` and `held`.
/datum/unit_test/dq_timed_pin_w5/proc/setup_scene()
	return

/// TRUE once the action has had its effect.
/datum/unit_test/dq_timed_pin_w5/proc/is_done()
	return FALSE

/// What an action leaves on the floor (its products) belongs to the test, so the leak check does not count it.
/datum/unit_test/dq_timed_pin_w5/proc/tidy()
	for(var/turf/T in block(run_loc_floor_bottom_left, run_loc_floor_top_right))
		own_turf_contents(T)
	forget_ghosts()

/// A mob that still has a ckey when it is deleted leaves an observer behind: take the ckeys off.
/datum/unit_test/dq_timed_pin_w5/proc/forget_ghosts()
	for(var/mob/living/carbon/human/H in range(3, run_loc_floor_bottom_left))
		H.ckey = null

/// Takes the scene down so the next one starts clean.
/datum/unit_test/dq_timed_pin_w5/proc/clear_scene()
	tidy()
	if(target && !QDELETED(target))
		qdel(target)
	target = null

/// Starts the action as the pin does: the held item (or a bare hand) clicked on the target, or the menu's op.
/datum/unit_test/dq_timed_pin_w5/proc/start_click()
	test_chat_clear()
	if(menu_key)
		test_menu(user, target, menu_key)
		return
	test_click(user, target, held)

/// The held item of the scene, put in the actor's active hand.
/datum/unit_test/dq_timed_pin_w5/proc/hold(path)
	var/obj/item/I = allocate(path, run_loc_floor_bottom_left)
	user.put_in_active_hand(I)
	return I

/datum/unit_test/dq_timed_pin_w5/run_pin()
	// the length, the start message and the finish
	setup_scene()
	start_click()
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts a timed action")
	var/declared = declared_duration(T)
	TEST_ASSERT(isnull(declared) || declared == duration, "it lasts as long as it should")
	if(began)
		TEST_ASSERT(said(user, began), "it says it began")
	TEST_ASSERT(!is_done(), "nothing is done at the start")
	test_time(duration - 1 SECOND)
	TEST_ASSERT(!is_done(), "not done a second before the end")
	test_time(2 SECONDS)
	TEST_ASSERT(is_done(), "done a second after the end")
	if(finished)
		TEST_ASSERT(said(user, finished), "it says it finished")
	clear_scene()
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
/datum/unit_test/dq_timed_pin_w5/proc/extra_pin()
	return

// ---- Snowball: compacted in the hand ----

/datum/unit_test/dq_timed_pin_w5/snowball_compact
	duration = 2 SECONDS
	began = "You start compacting"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/snowball_compact/setup_scene()
	user = person()
	held = hold(/obj/item/material/snow/snowball)
	target = held

/datum/unit_test/dq_timed_pin_w5/snowball_compact/is_done()
	for(var/obj/item/material/snow/snowball/reinforced/R in user.get_all_held_items() + view(0, user))
		return TRUE
	return FALSE

// ---- Bonfire: an empty one is taken apart by hand ----

/datum/unit_test/dq_timed_pin_w5/bonfire_dismantle
	duration = 5 SECONDS
	began = "You start dismantling"
	finished = "You dismantle"

/datum/unit_test/dq_timed_pin_w5/bonfire_dismantle/setup_scene()
	user = person()
	target = allocate(/obj/structure/bonfire, run_loc_floor_bottom_left)

/datum/unit_test/dq_timed_pin_w5/bonfire_dismantle/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w5/bonfire_dismantle/extra_pin()
	setup_scene()
	var/obj/structure/bonfire/B = target
	B.set_burning(TRUE)
	start_click()
	TEST_ASSERT_NULL(running(user), "a burning bonfire is not taken apart")
	TEST_ASSERT(said(user, "still burning"), "and the actor is told so")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!QDELETED(B), "and it stands")
	clear_scene()

// ---- Tree stump: dug up with a shovel ----

/datum/unit_test/dq_timed_pin_w5/tree_stump_dig
	duration = 5 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/tree_stump_dig/setup_scene()
	user = person()
	var/obj/structure/flora/tree/T = allocate(/obj/structure/flora/tree/desert_planet/palmtree, run_loc_floor_bottom_left)
	T.stump()
	target = T
	held = hold(/obj/item/shovel)

/datum/unit_test/dq_timed_pin_w5/tree_stump_dig/is_done()
	return QDELETED(target)

// ---- Reflector: a wrench takes a loose one apart, a welder fixes it to the floor ----

/datum/unit_test/dq_timed_pin_w5/reflector_dismantle
	duration = 2 SECONDS
	began = "You start to dismantle"
	finished = "You dismantle"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/reflector_dismantle/setup_scene()
	user = person()
	target = allocate(/obj/structure/reflector, run_loc_floor_bottom_left)
	held = hold(/obj/item/tool/wrench)

/datum/unit_test/dq_timed_pin_w5/reflector_dismantle/is_done()
	return QDELETED(target)

/datum/unit_test/dq_timed_pin_w5/reflector_dismantle/extra_pin()
	setup_scene()
	var/obj/structure/reflector/R = target
	R.set_anchored(TRUE)
	start_click()
	TEST_ASSERT_NULL(running(user), "a wrench on an anchored reflector starts nothing")
	TEST_ASSERT(said(user, "Unweld"), "and says to unweld it first")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!QDELETED(R), "and the reflector stays")
	clear_scene()

/datum/unit_test/dq_timed_pin_w5/reflector_weld
	duration = 2 SECONDS
	began = "You start to weld"
	finished = "You weld"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/reflector_weld/setup_scene()
	user = person()
	target = allocate(/obj/structure/reflector, run_loc_floor_bottom_left)
	var/obj/item/weldingtool/W = hold(/obj/item/weldingtool)
	W.reagents.add_reagent(REAGENT_ID_FUEL, W.max_fuel)
	W.setWelding(TRUE)
	held = W

/datum/unit_test/dq_timed_pin_w5/reflector_weld/is_done()
	var/obj/structure/reflector/R = target
	return !QDELETED(R) && R.anchored

// ---- Broken drone circuit: studied in the hand ----

/datum/unit_test/dq_timed_pin_w5/drone_circuit_analyze
	duration = 5 SECONDS
	began = "You take your time to analyze"
	finished = "stenciled onto the board"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/drone_circuit_analyze/setup_scene()
	user = person()
	held = hold(/obj/item/poi/broken_drone_circuit)
	target = held

/datum/unit_test/dq_timed_pin_w5/drone_circuit_analyze/is_done()
	return said(user, "stenciled onto the board")

/datum/unit_test/dq_timed_pin_w5/drone_circuit_analyze/extra_pin()
	setup_scene()
	var/obj/item/poi/broken_drone_circuit/C = held
	C.set_fried(TRUE)
	start_click()
	TEST_ASSERT_NULL(running(user), "a fried circuit is read at once")
	TEST_ASSERT(said(user, "scorch mark"), "and the actor reads what is left of it")
	clear_scene()

// ---- UAV: a power cell goes in after three seconds ----

/datum/unit_test/dq_timed_pin_w5/uav_cell_in
	duration = 3 SECONDS
	finished = "You insert"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/uav_cell_in/setup_scene()
	user = person()
	target = allocate(/obj/item/uav, run_loc_floor_bottom_left)
	held = hold(/obj/item/cell)

/datum/unit_test/dq_timed_pin_w5/uav_cell_in/is_done()
	var/obj/item/uav/U = target
	return !QDELETED(U) && !isnull(U.cell)

/datum/unit_test/dq_timed_pin_w5/uav_cell_in/extra_pin()
	user = person()
	var/obj/item/uav/loaded/U = allocate(/obj/item/uav/loaded, run_loc_floor_bottom_left)
	target = U
	var/obj/item/cell/spare = hold(/obj/item/cell)
	test_chat_clear()
	var/obj/item/cell/first = U.cell
	test_click(user, U, spare)
	test_time(5 SECONDS)
	TEST_ASSERT(U.cell == first && spare.loc != U, "a drone that has a cell takes no second one")
	clear_scene()

// ---- Sniper rifle parts: taken apart, put together, and the rifle collapsed ----

/datum/unit_test/dq_timed_pin_w5/sniper_part_disassemble
	duration = 4 SECONDS
	began = "You start disassembling"
	finished = "You disassemble"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/sniper_part_disassemble/setup_scene()
	user = person()
	var/obj/item/sniper_rifle_part/trigger_group/G = hold(/obj/item/sniper_rifle_part/trigger_group)
	var/obj/item/sniper_rifle_part/stock/S = new(G)
	rel_set(G, nameof(G.stock), S)
	G.set_part_count(2)
	held = G
	target = G

/datum/unit_test/dq_timed_pin_w5/sniper_part_disassemble/is_done()
	var/obj/item/sniper_rifle_part/G = target
	return !QDELETED(G) && G.part_count == 1

/datum/unit_test/dq_timed_pin_w5/sniper_part_disassemble/extra_pin()
	user = person()
	var/obj/item/sniper_rifle_part/barrel/B = hold(/obj/item/sniper_rifle_part/barrel)
	target = B
	held = B
	start_click()
	TEST_ASSERT_NULL(running(user), "a single part cannot be taken further apart")
	TEST_ASSERT(said(user, "can't disassemble"), "and the actor is told so")
	clear_scene()

/datum/unit_test/dq_timed_pin_w5/sniper_part_add
	duration = 3 SECONDS
	began = "You begin adding"
	finished = "You install"
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w5/sniper_part_add/setup_scene()
	user = person()
	target = allocate(/obj/item/sniper_rifle_part/trigger_group, run_loc_floor_bottom_left)
	held = hold(/obj/item/sniper_rifle_part/barrel)

/datum/unit_test/dq_timed_pin_w5/sniper_part_add/is_done()
	var/obj/item/sniper_rifle_part/G = target
	return !QDELETED(G) && G.part_count == 2

/datum/unit_test/dq_timed_pin_w5/sniper_rifle_collapse
	duration = 4 SECONDS
	began = "You begin removing"
	finished = "You remove"
	menu_key = "collapsible_sniper_verb_take_down"

/datum/unit_test/dq_timed_pin_w5/sniper_rifle_collapse/setup_scene()
	user = person()
	var/obj/item/gun/projectile/heavysniper/collapsible/R = hold(/obj/item/gun/projectile/heavysniper/collapsible)
	if(R.chambered)
		rel_clear(R, nameof(R.chambered)) // a fresh rifle may have a round chambered; the op refuses a loaded one
	held = R
	target = R

/datum/unit_test/dq_timed_pin_w5/sniper_rifle_collapse/is_done()
	return QDELETED(target)
