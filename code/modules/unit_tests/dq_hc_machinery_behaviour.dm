// Behaviour-preservation tests for the hand-converted machines (code/game/machinery, code/modules/reagents/machinery). Same rules and helpers as
// dq_hc_struct_behaviour.dm (its base type, hci_click / hci_answer / hc_ui / hc_data): they pin what a player observes through window buttons,
// clicks, hits and questions, so the file passes before and after a machine moves to the final forms.

// ---------------------------------------------------------------------------------------------------------------------
// Navigation beacon
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/navbeacon_codes_are_edited_through_the_window
/datum/unit_test/dq_hc_struct/navbeacon_codes_are_edited_through_the_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/navbeacon/N = mach(/obj/machinery/navbeacon, tile(3, 2))
	N.open = TRUE
	N.set_locked(FALSE)
	press(H, N, "loc_edit", list("new_loc" = "Cargo Bay"))
	TEST_ASSERT_EQUAL(N.location, "Cargo Bay", "the location is set")
	press(H, N, "trans_add_code", list("new_key" = "patrol", "new_val" = "1"))
	TEST_ASSERT_EQUAL(N.codes["patrol"], "1", "a code is added")
	press(H, N, "trans_edit_key", list("code" = "patrol", "new_key" = "route"))
	TEST_ASSERT_EQUAL(N.codes["route"], "1", "a code is renamed")
	TEST_ASSERT_NULL(N.codes["patrol"], "and the old name is gone")
	press(H, N, "trans_edit_code", list("code" = "route", "new_val" = "2"))
	TEST_ASSERT_EQUAL(N.codes["route"], "2", "a code's value is changed")
	var/list/data = hc_data(N, H)
	TEST_ASSERT_EQUAL(data["location"], "Cargo Bay", "the window shows the location")
	TEST_ASSERT_EQUAL(data["codes"]["route"], "2", "and the codes")
	press(H, N, "trans_del", list("code" = "route"))
	TEST_ASSERT_NULL(N.codes?["route"], "a code is deleted")

/datum/unit_test/dq_hc_struct/locked_navbeacon_refuses_edits
/datum/unit_test/dq_hc_struct/locked_navbeacon_refuses_edits/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/navbeacon/N = mach(/obj/machinery/navbeacon, tile(3, 2))
	N.open = TRUE
	N.location = "Home"
	press(H, N, "loc_edit", list("new_loc" = "Away"))
	TEST_ASSERT_EQUAL(N.location, "Home", "a locked beacon keeps its location")
	N.set_locked(FALSE)
	N.open = FALSE
	press(H, N, "loc_edit", list("new_loc" = "Away"))
	TEST_ASSERT_EQUAL(N.location, "Home", "so does one whose cover is shut")

// ---------------------------------------------------------------------------------------------------------------------
// Fire alarm and party button
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/fire_alarm_goes_off_when_shot
/datum/unit_test/dq_hc_struct/fire_alarm_goes_off_when_shot/run_gate()
	var/obj/machinery/firealarm/F = mach(/obj/machinery/firealarm, tile(3, 2))
	TEST_ASSERT(!F.firewarn, "starts quiet")
	var/obj/item/projectile/bullet/B = allocate(/obj/item/projectile/bullet)
	F.bullet_act(B)
	TEST_ASSERT(F.firewarn, "a hit sets it off")

/datum/unit_test/dq_hc_struct/fire_alarm_may_go_off_in_an_emp
/datum/unit_test/dq_hc_struct/fire_alarm_may_go_off_in_an_emp/run_gate()
	var/obj/machinery/firealarm/F = mach(/obj/machinery/firealarm, tile(3, 2))
	for(var/i in 1 to 30)
		F.emp_act(1)
		if(F.firewarn)
			break
	TEST_ASSERT(F.firewarn, "a few EMPs set it off")

/datum/unit_test/dq_hc_struct/party_button_window
/datum/unit_test/dq_hc_struct/party_button_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/partyalarm/P = mach(/obj/machinery/partyalarm, tile(3, 2))
	var/area/A = get_area(P)
	press(H, P, "time", list("value" = 1))
	TEST_ASSERT_EQUAL(P.timing, 1, "the timer is switched on")
	press(H, P, "tp", list("value" = 5))
	TEST_ASSERT_EQUAL(P.time, 15, "the time is stepped")
	press(H, P, "tp", list("value" = 500))
	TEST_ASSERT_EQUAL(P.time, 120, "up to a ceiling")
	var/list/data = hc_data(P, H)
	TEST_ASSERT_EQUAL(data["timing"], TRUE, "the window shows the timer")
	TEST_ASSERT_EQUAL(data["scrambled"], FALSE, "to a human in clear text")
	press(H, P, "alarm")
	TEST_ASSERT(A.party, "the alarm button starts the party")
	press(H, P, "reset")
	TEST_ASSERT(!A.party, "the reset button ends it")
	P.stat_add(NOPOWER)
	press(H, P, "tp", list("value" = 5))
	TEST_ASSERT_EQUAL(P.time, 120, "a dead button takes no presses")

// ---------------------------------------------------------------------------------------------------------------------
// AI liquid dispenser
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/ai_slipper_window
/datum/unit_test/dq_hc_struct/ai_slipper_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/ai_slipper/S = mach(/obj/machinery/ai_slipper, tile(3, 2))
	TEST_ASSERT(S.locked, "starts locked")
	press(H, S, "toggle_on")
	TEST_ASSERT(S.disabled, "a locked dispenser takes no presses from a human")
	S.set_locked(FALSE)
	press(H, S, "toggle_on")
	TEST_ASSERT(!S.disabled, "an unlocked one is switched on")
	var/uses = S.uses
	press(H, S, "toggle_use")
	TEST_ASSERT_EQUAL(S.uses, uses - 1, "firing it spends a use")
	TEST_ASSERT(S.cooldown_on, "and starts the cooldown")
	press(H, S, "toggle_use")
	TEST_ASSERT_EQUAL(S.uses, uses - 1, "a second shot during the cooldown does nothing")
	var/list/data = hc_data(S, H)
	TEST_ASSERT_EQUAL(data["uses"], uses - 1, "the window shows the uses")
	TEST_ASSERT_EQUAL(data["is_silicon"], FALSE, "and who is looking")

// ---------------------------------------------------------------------------------------------------------------------
// Oxygen pump
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/oxygen_pump_pressure_is_set_through_the_window
/datum/unit_test/dq_hc_struct/oxygen_pump_pressure_is_set_through_the_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/oxygen_pump/anesthetic/P = mach(/obj/machinery/oxygen_pump/anesthetic, tile(3, 2))
	TEST_ASSERT_NOTNULL(P.tank, "the pump has a tank")
	press(H, P, "pressure", list("pressure" = "max"))
	TEST_ASSERT(abs(P.tank.distribute_pressure - TANK_MAX_RELEASE_PRESSURE) < 1, "max sets the ceiling")
	press(H, P, "pressure", list("pressure" = 50))
	TEST_ASSERT_EQUAL(P.tank.distribute_pressure, 50, "a number is taken")
	press(H, P, "pressure", list("pressure" = "reset"))
	TEST_ASSERT_EQUAL(P.tank.distribute_pressure, TANK_DEFAULT_RELEASE_PRESSURE, "reset restores the default")
	press(H, P, "pressure", list("pressure" = "min"))
	TEST_ASSERT_EQUAL(P.tank.distribute_pressure, 0, "min closes it")
	var/list/data = hc_data(P, H)
	TEST_ASSERT_EQUAL(data["maxReleasePressure"], round(TANK_MAX_RELEASE_PRESSURE), "the window shows the limits")

// ---------------------------------------------------------------------------------------------------------------------
// Pipe dispenser
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/pipe_dispenser_window
/datum/unit_test/dq_hc_struct/pipe_dispenser_window/run_gate()
	var/mob/living/carbon/human/H = person()
	var/turf/T = tile(3, 2)
	var/obj/machinery/pipedispenser/D = mach(/obj/machinery/pipedispenser, T)
	press(H, D, "p_layer", list("p_layer" = 3))
	TEST_ASSERT_EQUAL(D.p_layer, 3, "the layer is set")
	var/list/data = hc_data(D, H)
	TEST_ASSERT(length(data["categories"]) > 0, "the window lists the recipes")
	var/list/first = GLOB.atmos_pipe_recipes[GLOB.atmos_pipe_recipes[1]]
	var/datum/pipe_recipe/recipe = first[1]
	press(H, D, "dispense_pipe", list("ref" = "\ref[recipe]"))
	TEST_ASSERT_NOTNULL(locate(/obj/item/pipe) in T, "a pipe is dispensed")
	for(var/obj/item/pipe/P in T)
		qdel(P)
	D.unwrenched = 1
	press(H, D, "dispense_pipe", list("ref" = "\ref[recipe]"))
	TEST_ASSERT_NULL(locate(/obj/item/pipe) in T, "an unwrenched dispenser gives nothing")

// ---------------------------------------------------------------------------------------------------------------------
// Floor layer
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_struct/floorlayer_work_mode_is_chosen_with_a_wrench
/datum/unit_test/dq_hc_struct/floorlayer_work_mode_is_chosen_with_a_wrench/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/floorlayer/F = mach(/obj/machinery/floorlayer, tile(3, 2))
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, tile(2, 2))
	TEST_ASSERT(!F.work_modes["laying"], "laying starts off")
	hci_click(H, F, W)
	hci_answer(H, "laying")
	settle()
	TEST_ASSERT(F.work_modes["laying"], "the chosen mode is switched on")
	hci_click(H, F, W)
	hci_answer(H, "laying")
	settle()
	TEST_ASSERT(!F.work_modes["laying"], "and off again")

/datum/unit_test/dq_hc_struct/floorlayer_work_mode_answer_is_dropped_when_the_person_walks_away
/datum/unit_test/dq_hc_struct/floorlayer_work_mode_answer_is_dropped_when_the_person_walks_away/run_gate()
	var/mob/living/carbon/human/H = person()
	var/obj/machinery/floorlayer/F = mach(/obj/machinery/floorlayer, tile(3, 2))
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench, tile(2, 2))
	hci_click(H, F, W)
	H.forceMove(tile(0, 0))
	hci_answer(H, "collect")
	settle()
	TEST_ASSERT(!F.work_modes["collect"], "an answer from someone no longer next to it is dropped")
