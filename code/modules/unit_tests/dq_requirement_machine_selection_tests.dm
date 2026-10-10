/datum/unit_test/requirement_protocol_cablelayer_toggle/Run()
	var/obj/machinery/cablelayer/layer = allocate(/obj/machinery/cablelayer)
	var/datum/act/op/A = allocate(/datum/act/op)
	A.holder = layer
	TEST_ASSERT(layer.cable, "The real layer initializes its loaded reel")
	TEST_ASSERT_NULL(layer.toggle_ready(A), "The initialized reel permits toggling while off")
	rel_clear(layer, nameof(/obj/machinery/cablelayer::cable))
	layer.set_on(FALSE)
	TEST_ASSERT_EQUAL(layer.toggle_ready(A), MSG(cablelayer/toggle_no_cable), "An off layer with no reel refuses with the original reason")
	layer.set_on(TRUE)
	TEST_ASSERT_NULL(layer.toggle_ready(A), "A running empty layer still permits switching off")

/datum/unit_test/requirement_protocol_bomb_tester_slots/Run()
	var/obj/machinery/bomb_tester/tester = allocate(/obj/machinery/bomb_tester)
	var/datum/act/op/A = allocate(/datum/act/op)
	A.holder = tester
	TEST_ASSERT_NULL(tester.tank_slot_available(A), "Two empty real tank slots allow the loading selection")
	var/obj/item/tank/oxygen/first = allocate(/obj/item/tank/oxygen)
	var/obj/item/tank/oxygen/second = allocate(/obj/item/tank/oxygen)
	rel_set(tester, nameof(/obj/machinery/bomb_tester::tank1), first)
	TEST_ASSERT_NULL(tester.tank_slot_available(A), "An empty secondary slot still allows loading")
	rel_set(tester, nameof(/obj/machinery/bomb_tester::tank2), second)
	TEST_ASSERT_EQUAL(tester.tank_slot_available(A), MSG(req_wrong_state), "Both occupied slots suppress loading")
	rel_take(tester, nameof(/obj/machinery/bomb_tester::tank1))
	TEST_ASSERT_NULL(tester.tank_slot_available(A), "Removing the primary tank restores loading")

/// The native conversion retains the old silicon module action's disabled menu row.
/datum/unit_test/requirement_protocol_module_menu
	parent_type = /datum/unit_test/read_once_machinery_admission

/datum/unit_test/requirement_protocol_module_menu/run_gate()
	set_global(nameof(GLOB.op_menu_builds), GLOB.op_menu_builds)
	var/obj/item/floor_light/I = allocate(/obj/item/floor_light, tile(3, 2))
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, tile(2, 2))
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, tile(2, 2), null, null, null, TRUE)
	for(var/mob/actor as anything in list(R, AI))
		var/list/row = find_row(op_menu(actor, I, null), "gen_silicon_item_silicon_equip_module")
		TEST_ASSERT_NOTNULL(row, "Both silicons retain the original stable Equip menu key")
		TEST_ASSERT(!row?["enabled"], "A floor item cannot be equipped as a module")
		TEST_ASSERT_EQUAL(row?["reason"], "not possible right now", "The original disabled reason is preserved")
		var/datum/op_result/result = test_menu(actor, I, "gen_silicon_item_silicon_equip_module")
		TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "The real disabled menu action refuses")
	TEST_ASSERT_EQUAL(I.loc, tile(3, 2), "Refusal leaves the actual item on its turf")

/datum/unit_test/requirement_protocol_module_ai_noop/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/robot_module/module = allocate(/obj/item/robot_module, T)
	var/obj/item/I = allocate(/obj/item, module)
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, T, null, null, null, TRUE)
	var/datum/act/op/A = allocate(/datum/act/op)
	A.holder = I
	A.actor = AI
	TEST_ASSERT_NULL(I.item_in_robot_module(A), "The real module containment permits admission")
	TEST_ASSERT_EQUAL(I.item_silicon_equip_module(A), OP_OK, "An AI retains its successful module no-op without a robot cast")
	TEST_ASSERT_EQUAL(I.loc, module, "The AI no-op preserves actual module containment")
