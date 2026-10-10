// Behaviour pins for the timed actions of group H of round 3 (rewrite/timed3-H), on the harness of dq_timed_pin_w8_behaviour.dm. The scenes are written from the
// pre-conversion code and run against the ops that replaced it. Only what the test driver can reach is pinned: the gun overrides (attack(), afterattack(),
// Fire(), examine()), the hose prompt chain, the NTSL script task and the vent entry start from legacy hooks that test_click does not drive, so they have no pin.

// ---- Mass reloading: a magazine used on a casing on the floor collects the matching shells, one every half second ----

/datum/unit_test/dq_timed_pin_w8/ammo_collect
	duration = 1.5 SECONDS

/datum/unit_test/dq_timed_pin_w8/ammo_collect/setup_scene()
	user = person()
	var/turf/floor = get_step(user, NORTH)
	var/obj/item/ammo_casing/first
	for(var/i in 1 to 3)
		var/obj/item/ammo_casing/shell = allocate(/obj/item/ammo_casing/a9mm, floor)
		if(!first)
			first = shell
	target = first
	held = hold(/obj/item/ammo_magazine/m9mm/empty)

/datum/unit_test/dq_timed_pin_w8/ammo_collect/run_pin()
	setup_scene()
	var/obj/item/ammo_magazine/box = held
	start_click()
	TEST_ASSERT(!isnull(running(user)), "the click starts collecting")
	TEST_ASSERT(said(user, "You start collecting shells"), "it says it began")
	TEST_ASSERT_EQUAL(length(box.stored_ammo), 0, "nothing is collected at the start")
	test_time(1 SECOND)
	TEST_ASSERT(length(box.stored_ammo) < 3, "the shells come one at a time")
	test_time(duration + 2 SECONDS)
	TEST_ASSERT_EQUAL(length(box.stored_ammo), 3, "all three shells end up in the box")
	TEST_ASSERT(said(user, "You collect 3 shell"), "it says how many it collected")
	TEST_ASSERT(!box.reloading, "the box is free again")
	clear_scene()
	// a move ends it with what was collected so far
	setup_scene()
	box = held
	start_click()
	test_time(0.7 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(length(box.stored_ammo) < 3, "moving stops the collecting")
	TEST_ASSERT(!box.reloading, "and frees the box")
	clear_scene()
	tidy()

// ---- A broken gun: the right material from the hand repairs part of it, five to fifteen seconds ----

/datum/unit_test/dq_timed_pin_w8/broken_gun_repair
	duration = 15 SECONDS
	drop_cancels = TRUE

/datum/unit_test/dq_timed_pin_w8/broken_gun_repair/setup_scene()
	user = person()
	var/obj/item/broken_gun/wreck = allocate(/obj/item/broken_gun, get_step(user, NORTH))
	wreck.my_guntype = /obj/item/gun/energy/taser
	wreck.material_needs = list(/obj/item/stack/material/steel = 2, /obj/item/stock_parts/gear = 1)
	target = wreck
	var/obj/item/stack/material/steel/sheets = hold(/obj/item/stack/material/steel)
	sheets.set_amount(5)
	held = sheets

/datum/unit_test/dq_timed_pin_w8/broken_gun_repair/is_done()
	var/obj/item/broken_gun/wreck = target
	return !QDELETED(wreck) && wreck.material_needs[/obj/item/stack/material/steel] == 0

/datum/unit_test/dq_timed_pin_w8/broken_gun_repair/run_pin()
	setup_scene()
	start_click()
	var/datum/T = running(user)
	TEST_ASSERT(!isnull(T), "the click starts the repair")
	TEST_ASSERT(!is_done(), "nothing is done at the start")
	test_time(4 SECONDS)
	TEST_ASSERT(!is_done(), "not done before the shortest repair time")
	test_time(duration - 4 SECONDS + 2 SECONDS)
	TEST_ASSERT(is_done(), "done after the longest repair time")
	TEST_ASSERT(said(user, "You repair some damage"), "it says it repaired")
	clear_scene()
	// a move cancels
	setup_scene()
	start_click()
	T = running(user)
	test_time(2 SECONDS)
	user.forceMove(get_step(user, EAST))
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!is_done(), "moving cancels: nothing is repaired")
	TEST_ASSERT(was_cancelled(T, user), "the repair ends cancelled")
	clear_scene()
	// dropping the sheets cancels
	setup_scene()
	start_click()
	T = running(user)
	user.drop_from_inventory(held)
	test_time(duration + 2 SECONDS)
	TEST_ASSERT(!is_done(), "dropping the material cancels: nothing is repaired")
	TEST_ASSERT(was_cancelled(T, user), "the repair ends cancelled")
	clear_scene()
	// a stack that is too short refuses and starts nothing
	setup_scene()
	var/obj/item/stack/material/steel/short = held
	short.set_amount(1)
	refused("You do not have enough")
	clear_scene()
	tidy()
