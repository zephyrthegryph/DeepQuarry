// Machines through their windows: a player opens an airlock controller's console, its window shows the console it draws and the
// airlock's state, and pressing Cycle starts the cycle the window then shows.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_gameplay/airlock_controller_cycle

/datum/unit_test/dq_gameplay/airlock_controller_cycle/play()
	var/mob/living/carbon/human/H = spawn_player(tile(2, 1), SSaccess.get_all_station_access())
	var/obj/machinery/embedded_controller/radio/airlock/airlock_controller/C = allocate(/obj/machinery/embedded_controller/radio/airlock/airlock_controller, tile(2, 2))
	var/datum/op_result/opened = click(H, C)
	TEST_ASSERT(opened?.outcome != ACT_REFUSED, "clicking the controller is not refused ([opened?.key]: [opened?.outcome])")
	TEST_ASSERT_EQUAL(C.ui_interface(H), "EmbeddedController", "the click opens the controller's window")
	var/list/data = hc_data(C, H)
	TEST_ASSERT_EQUAL(data["internalTemplateName"], "AirlockConsoleSimple", "the window names the console it draws: [json_encode(data)]")
	for(var/key in list("chamber_pressure", "exterior_status", "interior_status", "processing"))
		TEST_ASSERT(key in data, "the console shows [key]: [json_encode(data)]")
	TEST_ASSERT(!data["processing"], "the airlock is idle before the press")
	var/datum/op_result/pressed = press(H, C, "cycle_ext")
	TEST_ASSERT(pressed && pressed.outcome != ACT_REFUSED, "the Cycle to Exterior button works ([pressed?.outcome])")
	data = hc_data(C, H)
	TEST_ASSERT(data["processing"], "the window shows the airlock cycling after the press: [json_encode(data)]")
	press(H, C, "abort", wait = 5) // the console shows the program's state as of its next step
	TEST_ASSERT(!hc_data(C, H)["processing"], "Abort stops the cycle")

#endif
