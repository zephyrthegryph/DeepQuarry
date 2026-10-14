/// Actual board insertion must honor removal refusal before creating a completed firedoor.
/datum/unit_test/interim_firedoor_board_consumption
	parent_type = /datum/unit_test/dq_p2_reagents
	var/glass_case = FALSE

/datum/unit_test/interim_firedoor_board_consumption/glass
	glass_case = TRUE

/datum/unit_test/interim_firedoor_board_consumption/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = rc_actor(T)
	var/obj/structure/firedoor_assembly/frame = allocate(/obj/structure/firedoor_assembly, T)
	TEST_ASSERT(!frame.anchored, "The real frame must start unsecured")
	TEST_ASSERT(!p2_firedoor_assembly_wired(frame), "The real frame must start bare")
	if(glass_case)
		var/obj/item/stack/material/glass/reinforced/glass = allocate(/obj/item/stack/material/glass/reinforced, T, 2)
		rc_click(actor, frame, glass, I_HELP, FALSE)
		test_time(5 SECONDS)
		TEST_ASSERT_EQUAL(glass.amount, 1, "Actual glazing must consume exactly one reinforced sheet")
	TEST_ASSERT_EQUAL(frame.glass, glass_case, "Actual glazing must preserve the selected variant")
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	rc_click(actor, frame, wrench, I_HELP, FALSE)
	TEST_ASSERT(frame.anchored, "The real wrench input must secure the frame")
	var/obj/item/stack/cable_coil/cable = allocate(/obj/item/stack/cable_coil, T, 2)
	rc_click(actor, frame, cable, I_HELP, FALSE)
	test_time(5 SECONDS)
	TEST_ASSERT(p2_firedoor_assembly_wired(frame), "Actual cable insertion must complete the wired stage")
	TEST_ASSERT_EQUAL(cable.amount, 1, "Wiring must consume exactly one length of cable")
	actor.drop_item()
	var/obj/item/circuitboard/airalarm/board = allocate(/obj/item/circuitboard/airalarm, T)
	TEST_ASSERT(actor.put_in_active_hand(board), "The actor must hold the actual air-alarm board")
	var/list/before = turf_contents_of_type(T, /obj/machinery/door/firedoor)
	var/frame_handle = entity_handle(frame)
	add_trait(board, TRAIT_NODROP, "interim_firedoor_board_consumption")
	rc_click(actor, frame, board, I_HELP, FALSE)
	own_turf_contents(T)
	TEST_ASSERT(!QDELETED(frame), "Refused board consumption must preserve the assembly")
	TEST_ASSERT(!QDELETED(board), "Refused consumption must preserve the actual board")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), board, "Refused consumption must preserve the actor's occupied hand")
	TEST_ASSERT_EQUAL(frame.loc, T, "Refusal must preserve the assembly's actual floor")
	TEST_ASSERT(p2_firedoor_assembly_wired(frame), "Refusal must preserve the actual completed wiring stage")
	TEST_ASSERT_EQUAL(frame.glass, glass_case, "Refusal must preserve the assembly glass configuration")
	var/list/refused_products = turf_contents_of_type(T, /obj/machinery/door/firedoor) - before
	TEST_ASSERT_EQUAL(length(refused_products), 0, "A stuck board must not create a free completed firedoor")
	remove_trait(board, TRAIT_NODROP, "interim_firedoor_board_consumption")
	rc_click(actor, frame, board, I_HELP, FALSE)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(frame), "Successful board insertion must replace the assembly")
	TEST_ASSERT(QDELETED(board), "Successful insertion must consume the exact board")
	TEST_ASSERT_NULL(actor.get_active_hand(), "Successful insertion must release the actor's actual hand")
	var/list/products = turf_contents_of_type(T, /obj/machinery/door/firedoor) - before
	TEST_ASSERT_EQUAL(length(products), 1, "Successful insertion must produce exactly one firedoor")
	var/obj/machinery/door/firedoor/door = products[1]
	var/expected_type = glass_case ? /obj/machinery/door/firedoor/glass : /obj/machinery/door/firedoor
	TEST_ASSERT_EQUAL(door.type, expected_type, "Successful insertion must preserve the chosen glass configuration")
	TEST_ASSERT_EQUAL(door.loc, T, "The completed firedoor must remain on the secured assembly floor")
	TEST_ASSERT_NULL(resolve_handle(frame_handle), "A structure assembly handle must terminate for its cross-family firedoor successor")
