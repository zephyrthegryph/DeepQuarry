/// Real player input starts the legacy insertion route; its existing timer must credit only successfully consumed originals.
/datum/unit_test/round2_robot_fabricator_consumption
	parent_type = /datum/unit_test/dq_p2_engine
	var/remove_pending_stack = FALSE

/datum/unit_test/round2_robot_fabricator_consumption/stale
	remove_pending_stack = TRUE

/datum/unit_test/round2_robot_fabricator_consumption/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/robotic_fabricator/machine = allocate(/obj/machinery/robotic_fabricator, T)
	var/obj/item/stack/material/steel/original = allocate(/obj/item/stack/material/steel, T, 2)
	dq_machine_clear(machine)
	TEST_ASSERT_EQUAL(machine.metal_amount, 0, "actual fabricator starts with no stock")
	TEST_ASSERT_EQUAL(original.get_amount(), 2, "actual steel stack initializes exactly two sheets")
	TEST_ASSERT_EQUAL(original.get_material_name(), MAT_STEEL, "actual insertion ingredient is steel")
	var/unit_steel = original.material_totals()[MAT_STEEL]
	TEST_ASSERT(unit_steel > 0, "actual sheet declares positive steel mass")
	TEST_ASSERT(user.put_in_active_hand(original), "actor holds the exact original stack")
	var/datum/input_event/click/click = new(user, machine, null, null, "left=1")
	var/immediate = input_submit(click)
	TEST_ASSERT_EQUAL(click.result?.key, "insert_steel", "the real item click selects insertion before the inherited UI hand binding")
	TEST_ASSERT(machine.inserting, "real player input starts actual insertion timer (immediate=[immediate], actual key=[click.result?.key], outcome=[click.result?.outcome], reason=[click.result?.reason])")
	TEST_ASSERT_EQUAL(machine.metal_amount, 0, "pending insertion credits no steel")
	TEST_ASSERT_EQUAL(original.get_amount(), 2, "pending insertion consumes no sheets")
	TEST_ASSERT_EQUAL(user.get_active_hand(), original, "pending timer retains original source hand")
	if(remove_pending_stack)
		qdel(original)
		TEST_ASSERT(QDELETED(original), "actual pending original is deleted before completion")
	test_time(1 SECOND)
	TEST_ASSERT(!machine.inserting, "actual completion clears insertion state even after source deletion")
	TEST_ASSERT(QDELETED(original), "completed insertion leaves no surviving original steel stack")
	TEST_ASSERT_NULL(user.get_active_hand(), "completed removal clears original inventory slot")
	if(remove_pending_stack)
		TEST_ASSERT_EQUAL(machine.metal_amount, 0, "stale completion credits no missing steel")
	else
		TEST_ASSERT_EQUAL(machine.metal_amount, unit_steel * 2, "actual completion credits exactly both successfully consumed sheets including the final sheet")
