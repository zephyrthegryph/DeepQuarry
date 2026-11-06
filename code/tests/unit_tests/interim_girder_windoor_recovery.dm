/// Real steel girder dismantling returns exactly two sheets on its floor.
/datum/unit_test/interim_girder_dismantle_recovery/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)
	TEST_ASSERT_EQUAL(girder.girder_material.name, MAT_STEEL, "the real girder initializes its steel material")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material/steel)), 0, "the fixture starts without returned steel")
	girder.dismantle()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(girder), "actual dismantling consumes the original girder")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/girder), "dismantling leaves no duplicate girder")
	var/sheets = 0
	for(var/obj/item/stack/material/steel/steel as anything in contents_of(T, /obj/item/stack/material/steel))
		TEST_ASSERT_EQUAL(steel.loc, T, "returned steel remains on the original floor")
		sheets += steel.get_amount()
	TEST_ASSERT_EQUAL(sheets, 2, "actual girder dismantling returns exactly two steel sheets")

/// Actual welder completion distinguishes ordinary and secure windoor frame materials.
/datum/unit_test/interim_windoor_frame_recovery
	parent_type = /datum/unit_test/dq_p2_reagents
	var/assembly_type = /obj/structure/windoor_assembly
	var/product_type = /obj/item/stack/material/glass

/datum/unit_test/interim_windoor_frame_recovery/secure
	assembly_type = /obj/structure/windoor_assembly/secure
	product_type = /obj/item/stack/material/glass/reinforced

/datum/unit_test/interim_windoor_frame_recovery/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = rc_actor(T)
	var/obj/structure/windoor_assembly/frame = allocate(assembly_type, T)
	TEST_ASSERT(built(frame, STAGE_WINDOOR_ASSEMBLY_FRAME), "the real frame starts at the bare unwired dismantling stage")
	TEST_ASSERT(!frame.anchored, "the real frame starts unanchored for dismantling")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material/glass)), 0, "the fixture starts without recovered glass")
	var/obj/item/weldingtool/welder = allocate(/obj/item/weldingtool, T)
	welder.reagents.add_reagent(REAGENT_ID_FUEL, welder.max_fuel)
	welder.setWelding(TRUE)
	rc_click(user, frame, welder, I_HELP, FALSE)
	test_time(5 SECONDS)
	user.drop_item()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(frame), "actual welding completion consumes the original frame")
	TEST_ASSERT_NULL(locate_within(T, /obj/structure/windoor_assembly), "completion leaves no duplicate frame")
	var/sheets = 0
	var/wrong_sheets = 0
	for(var/obj/item/stack/material/glass/glass as anything in contents_of(T, /obj/item/stack/material/glass))
		TEST_ASSERT_EQUAL(glass.loc, T, "all returned glass stays on the original floor")
		if(glass.type == product_type)
			sheets += glass.get_amount()
		else
			wrong_sheets += glass.get_amount()
	TEST_ASSERT_EQUAL(sheets, 2, "the actual frame returns exactly two sheets of the correct glass type")
	TEST_ASSERT_EQUAL(wrong_sheets, 0, "completion returns no sheets of the other glass type")
	TEST_ASSERT_NULL(user.get_active_hand(), "welding completion does not equip the recovered glass")
