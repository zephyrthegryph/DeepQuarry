// stages(): a state machine over one tracked var (code/library/structures/stages.dm). The camera assembly is the pinned user.

/// The camera assembly walks 0 -> 3 and back down by its stages() steps: each step is an op listed in the menu only at its stage, and each moves the var.
/datum/unit_test/dq_stages_camera_assembly_ladder

/datum/unit_test/dq_stages_camera_assembly_ladder/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.teleop = H // a clientless test human counts as SSD and falls asleep; a teleoperated one stays awake through the ladder
	var/obj/item/camera_assembly/C = allocate(/obj/item/camera_assembly, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/weldingtool/welder = dq_fueled_welder(T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T)
	coil.set_amount(10)
	var/obj/item/clothing/glasses/welding/goggles = allocate(/obj/item/clothing/glasses/welding, T)
	TEST_ASSERT(H.equip_to_slot_if_possible(goggles, SLOT_ID_EYES, disable_warning = TRUE), "the welder's goggles go on (the weld's flash would knock the welder out)")

	H.put_in_active_hand(wrench)
	TEST_ASSERT(dq_stages_menu_has(H, C, "state_0_1"), "a loose assembly offers the wrench-down step")
	TEST_ASSERT(!dq_stages_menu_has(H, C, "state_1_0"), "and not the step of another stage")
	H.drop_from_inventory(wrench)
	dq_stages_use(H, C, wrench)
	TEST_ASSERT_EQUAL(C.state, 1, "the wrench fastens it (0 -> 1)")
	TEST_ASSERT(C.anchored, "and the step's then() anchors it")
	var/datum/op_result/R = dq_stages_use(H, C, welder)
	TEST_ASSERT_EQUAL(C.state, 2, "the timed weld moves it on (1 -> 2)")
	R = dq_stages_use(H, C, coil)
	TEST_ASSERT_EQUAL(C.state, 3, "two lengths of cable wire it (2 -> 3)")
	TEST_ASSERT_EQUAL(coil.get_amount(), 8, "and the stack paid for it")
	dq_stages_use(H, C, cutters)
	TEST_ASSERT_EQUAL(C.state, 2, "the wirecutters take the wires out (3 -> 2)")
	for(var/obj/item/stack/cable_coil/dropped in T)
		if(dropped != coil)
			qdel(dropped)
	H.put_in_active_hand(welder)
	TEST_ASSERT(dq_stages_menu_has(H, C, "state_2_1") && !dq_stages_menu_has(H, C, "state_1_2"), "a stage compares exactly: at 2 the welder offers only the unweld")
	H.drop_from_inventory(welder)
	R = dq_stages_use(H, C, welder)
	TEST_ASSERT_EQUAL(C.state, 1, "the weld comes undone (2 -> 1)")
	dq_stages_use(H, C, wrench)
	TEST_ASSERT_EQUAL(C.state, 0, "and the wrench frees it (1 -> 0)")
	TEST_ASSERT(!C.anchored, "loose again")
	test_driver_end()

/// Whether the actor's menu on `target` (with what they hold) lists the op `key`.
/datum/unit_test/proc/dq_stages_menu_has(mob/actor, atom/target, key)
	for(var/list/row in op_menu(actor, target, actor.get_active_hand()))
		if(row["key"] == key)
			return TRUE
	return FALSE

/// Clicks `target` with `held` in hand and lets a short wait run out (the tools here are instant: dq_fast_tool()).
/datum/unit_test/proc/dq_stages_use(mob/living/carbon/human/H, atom/target, obj/item/held)
	H.put_in_active_hand(held)
	. = test_click(H, target, held)
	test_time(5 SECONDS)
	H.drop_from_inventory(held)

/// The AI core frame's ladder by its stages() steps: bolted, the board in and screwed down, wired, unwired, the board out. req_stage() compares
/// exactly: at stage 2 the wrench's unanchor (from 1) is not offered.
/datum/unit_test/dq_stages_ai_core_ladder

/datum/unit_test/dq_stages_ai_core_ladder/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	H.teleop = H
	var/obj/structure/AIcore/C = allocate(/obj/structure/AIcore, T)
	var/obj/item/tool/wrench/wrench = dq_fast_tool(/obj/item/tool/wrench, T)
	var/obj/item/tool/screwdriver/screwdriver = dq_fast_tool(/obj/item/tool/screwdriver, T)
	var/obj/item/tool/wirecutters/cutters = dq_fast_tool(/obj/item/tool/wirecutters, T)
	var/obj/item/tool/crowbar/crowbar = dq_fast_tool(/obj/item/tool/crowbar, T)
	var/obj/item/circuitboard/aicore/board = allocate(/obj/item/circuitboard/aicore, T)
	var/obj/item/stack/cable_coil/coil = allocate(/obj/item/stack/cable_coil, T)
	coil.set_amount(10)

	dq_stages_use(H, C, wrench)
	TEST_ASSERT_EQUAL(C.state, 1, "the wrench bolts the frame (0 -> 1)")
	dq_stages_use(H, C, board)
	TEST_ASSERT_EQUAL(C.circuit, board, "the board goes in at 1")
	dq_stages_use(H, C, screwdriver)
	TEST_ASSERT_EQUAL(C.state, 2, "the screwdriver fastens the board (1 -> 2)")
	H.put_in_active_hand(wrench)
	TEST_ASSERT(!dq_stages_menu_has(H, C, "unanchor"), "at 2 the wrench does not unbolt the frame")
	H.drop_from_inventory(wrench)
	dq_stages_use(H, C, coil)
	TEST_ASSERT_EQUAL(C.state, 3, "five lengths wire it (2 -> 3)")
	dq_stages_use(H, C, cutters)
	TEST_ASSERT_EQUAL(C.state, 2, "the cutters take the wires out (3 -> 2)")
	dq_stages_use(H, C, screwdriver)
	TEST_ASSERT_EQUAL(C.state, 1, "the board is unfastened (2 -> 1)")
	dq_stages_use(H, C, crowbar)
	TEST_ASSERT_NULL(C.circuit, "the crowbar takes the board out at 1")
	for(var/obj/item/stack/cable_coil/dropped in T)
		if(dropped != coil)
			qdel(dropped)
	if(!QDELETED(board))
		qdel(board)
	test_driver_end()
