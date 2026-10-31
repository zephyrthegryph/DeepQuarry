// Wave 5 of the window conversions: the shutoff valve, fuel injector, fusion core, gyrotron and air alarm monitors, the atmospherics alert console,
// the bomb tester, the turbolift panel, the drone, exosuit and robotics consoles, the safe, the point defense control, the security and skills
// record consoles, the ship helm, the noticeboard and the ghost spawn menu's fabricator, virtual reality and player buttons send their rows by handle
// (ref_token()) and take them back only from the lists they show. Every window is checked through the real tgui state with a person who has a
// client-like transport (a clientless mob is closed out by the state and can fail nothing), every handle that is not one of the window's own is
// refused, and no button changes what a clientless or distant person could not already do.

/// The shutoff valve monitor: valves by handle, only the ones the registry lists.
/datum/unit_test/dq_topic5_shutoff_window

/datum/unit_test/dq_topic5_shutoff_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/host = allocate(/obj/item/paper, get_step(T, EAST))
	var/datum/tgui_module/shutoff_monitor/window = allocate(/datum/tgui_module/shutoff_monitor, host)
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the monitor works its window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/machinery/atmospherics/valve/shutoff/listed = allocate(/obj/machinery/atmospherics/valve/shutoff, get_step(T, NORTH))
	var/obj/machinery/atmospherics/valve/shutoff/stray = allocate(/obj/machinery/atmospherics/valve/shutoff, get_step(T, SOUTH))
	registry_leave(REGISTRY_SHUTOFF_VALVES, stray)
	var/list/data = hc_data(window, user)
	var/found = FALSE
	for(var/list/row in data["valves"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(stray), "a valve outside the registry is not listed")
	TEST_ASSERT(found, "the window names the valve by handle")
	var/leaks = listed.close_on_leaks
	var/stray_leaks = stray.close_on_leaks
	own(test_ui(user, window, "toggle_enable", list("valve" = ref_token(stray))))
	TEST_ASSERT_EQUAL(stray.close_on_leaks, stray_leaks, "a valve the window does not list is not switched")
	own(test_ui(user, window, "toggle_enable", list("valve" = "not a handle")))
	TEST_ASSERT_EQUAL(listed.close_on_leaks, leaks, "nor is one by a made-up name")
	own(test_ui(user, window, "toggle_enable", list("valve" = ref_token(listed))))
	TEST_ASSERT(listed.close_on_leaks != leaks, "the listed valve's handle switches it")
	var/was_open = listed.open
	own(test_ui(user, window, "toggle_open", list("valve" = ref_token(listed))))
	TEST_ASSERT(listed.open != was_open, "and opens or closes it")

/// The fuel injector control: injectors by handle, only the ones on its tag.
/datum/unit_test/dq_topic5_fuel_injector_window

/datum/unit_test/dq_topic5_fuel_injector_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/host = allocate(/obj/item/paper, get_step(T, EAST))
	var/datum/tgui_module/rustfuel_control/window = allocate(/datum/tgui_module/rustfuel_control, host)
	window.set_fuel_tag("dq-topic5-fuel")
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the control works its window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/machinery/fusion_fuel_injector/listed = allocate(/obj/machinery/fusion_fuel_injector, get_step(T, NORTH))
	listed.set_id_tag("dq-topic5-fuel")
	var/obj/machinery/fusion_fuel_injector/stray = allocate(/obj/machinery/fusion_fuel_injector, get_step(T, SOUTH))
	stray.set_id_tag("dq-topic5-other")
	listed.set_injecting(TRUE)
	stray.set_injecting(TRUE)
	var/list/data = hc_data(window, user)
	var/found = FALSE
	for(var/list/row in data["fuels"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(stray), "an injector on another tag is not listed")
	TEST_ASSERT(found, "the window names the injector by handle")
	own(test_ui(user, window, "toggle_active", list("fuel" = ref_token(stray))))
	TEST_ASSERT(stray.injecting, "an injector on another tag is not switched")
	own(test_ui(user, window, "toggle_active", list("fuel" = "not a handle")))
	TEST_ASSERT(listed.injecting, "nor is one by a made-up name")
	own(test_ui(user, window, "toggle_active", list("fuel" = ref_token(listed))))
	TEST_ASSERT(!listed.injecting, "the listed injector's handle switches it")

/// The fusion core monitor: cores by handle, only the ones on its tag.
/datum/unit_test/dq_topic5_fusion_core_window

/datum/unit_test/dq_topic5_fusion_core_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/host = allocate(/obj/item/paper, get_step(T, EAST))
	var/datum/tgui_module/rustcore_monitor/window = allocate(/datum/tgui_module/rustcore_monitor, host)
	window.set_core_tag("dq-topic5-core")
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the monitor works its window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/machinery/power/fusion_core/listed = allocate(/obj/machinery/power/fusion_core, get_step(T, NORTH))
	listed.set_id_tag("dq-topic5-core")
	var/obj/machinery/power/fusion_core/stray = allocate(/obj/machinery/power/fusion_core, get_step(T, SOUTH))
	stray.set_id_tag("dq-topic5-other")
	var/list/data = hc_data(window, user)
	var/found = FALSE
	for(var/list/row in data["cores"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(stray), "a core on another tag is not listed")
	TEST_ASSERT(found, "the window names the core by handle")
	var/dump = listed.reactant_dump
	var/stray_dump = stray.reactant_dump
	own(test_ui(user, window, "toggle_reactantdump", list("core" = ref_token(stray))))
	TEST_ASSERT_EQUAL(stray.reactant_dump, stray_dump, "a core on another tag is not switched")
	own(test_ui(user, window, "toggle_reactantdump", list("core" = "not a handle")))
	TEST_ASSERT_EQUAL(listed.reactant_dump, dump, "nor is one by a made-up name")
	own(test_ui(user, window, "toggle_reactantdump", list("core" = ref_token(listed))))
	TEST_ASSERT(listed.reactant_dump != dump, "the listed core's handle switches its reactant dump")

/// The gyrotron control: gyrotrons by handle, only the ones on its tag.
/datum/unit_test/dq_topic5_gyrotron_window

/datum/unit_test/dq_topic5_gyrotron_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/host = allocate(/obj/item/paper, get_step(T, EAST))
	var/datum/tgui_module/gyrotron_control/window = allocate(/datum/tgui_module/gyrotron_control, host)
	window.set_gyro_tag("dq-topic5-gyro")
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the control works its window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/machinery/power/emitter/gyrotron/listed = allocate(/obj/machinery/power/emitter/gyrotron, get_step(T, NORTH))
	listed.set_id_tag("dq-topic5-gyro")
	var/obj/machinery/power/emitter/gyrotron/stray = allocate(/obj/machinery/power/emitter/gyrotron, get_step(T, SOUTH))
	stray.set_id_tag("dq-topic5-other")
	var/list/data = hc_data(window, user)
	var/found = FALSE
	for(var/list/row in data["gyros"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(stray), "a gyrotron on another tag is not listed")
	TEST_ASSERT(found, "the window names the gyrotron by handle")
	var/rate = listed.rate
	var/stray_rate = stray.rate
	own(test_ui(user, window, "set_rate", list("gyro" = ref_token(stray), "rate" = 77)))
	TEST_ASSERT_EQUAL(stray.rate, stray_rate, "a gyrotron on another tag keeps its rate")
	own(test_ui(user, window, "set_rate", list("gyro" = "not a handle", "rate" = 77)))
	TEST_ASSERT_EQUAL(listed.rate, rate, "nor does one by a made-up name")
	own(test_ui(user, window, "set_rate", list("gyro" = ref_token(listed), "rate" = 77)))
	TEST_ASSERT_EQUAL(listed.rate, 77, "the listed gyrotron's handle sets its rate")

/// A recording air alarm: it counts how many times the console reset it.
/obj/machinery/alarm/dq_topic5_recording
	var/resets = 0

/obj/machinery/alarm/dq_topic5_recording/atmos_reset()
	resets++

/// The air alarm monitor: alarms by handle, only the ones it monitors.
/datum/unit_test/dq_topic5_atmos_control_window

/datum/unit_test/dq_topic5_atmos_control_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/item/paper/host = allocate(/obj/item/paper, get_step(T, EAST))
	var/datum/tgui_module/atmos_control/window = allocate(/datum/tgui_module/atmos_control)
	rel_set(window, nameof(/datum/tgui_module::host), host)
	TEST_ASSERT_EQUAL(window.tgui_status(user, window.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the monitor works its window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/machinery/alarm/listed = allocate(/obj/machinery/alarm, get_step(T, NORTH))
	var/obj/machinery/alarm/stray = allocate(/obj/machinery/alarm, get_step(T, SOUTH))
	rel_add(window, nameof(/datum/tgui_module/atmos_control::monitored_alarms), listed)
	var/list/static_data = window.tgui_static_data(user)
	var/found = FALSE
	for(var/list/row in static_data["alarms"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(stray), "an alarm the monitor does not watch is not listed")
	TEST_ASSERT(found, "the window names the alarm by handle")
	own(test_ui(user, window, "alarm", list("alarm" = ref_token(stray))))
	TEST_ASSERT_NULL(window.remote_panel, "an alarm the monitor does not watch opens no panel")
	own(test_ui(user, window, "alarm", list("alarm" = "not a handle")))
	TEST_ASSERT_NULL(window.remote_panel, "nor does one by a made-up name")
	own(test_ui(user, window, "alarm", list("alarm" = ref_token(listed))))
	TEST_ASSERT_NOTNULL(window.remote_panel, "the watched alarm's handle opens its panel")

/// The atmospherics alert console: alarms by handle, only the ones its level shows.
/datum/unit_test/dq_topic5_atmos_alert_window

/datum/unit_test/dq_topic5_atmos_alert_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/atmos_alert/console = allocate(/obj/machinery/computer/atmos_alert, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/machinery/alarm/dq_topic5_recording/air_alarm = allocate(/obj/machinery/alarm/dq_topic5_recording, get_step(T, NORTH))
	var/area/alarm_area = get_area(air_alarm)
	GLOB.atmosphere_alarm.triggerAlarm(alarm_area, air_alarm, 0, 2)
	var/datum/alarm/raised = GLOB.atmosphere_alarm.alarm_for(alarm_area)
	TEST_ASSERT_NOTNULL(raised, "the alarm is raised")
	var/datum/alarm/stray = allocate(/datum/alarm, alarm_area, air_alarm, 0, 2, 0)
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["priority_alarms"])
		if(row["ref"] == ref_token(raised))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(stray), "an alarm of no handler is not listed")
	TEST_ASSERT(found, "the window names the alarm by handle")
	own(test_ui(user, console, "clear", list("ref" = ref_token(stray))))
	TEST_ASSERT_EQUAL(air_alarm.resets, 0, "an alarm the console does not list resets nothing")
	own(test_ui(user, console, "clear", list("ref" = "not a handle")))
	TEST_ASSERT_EQUAL(air_alarm.resets, 0, "nor does a made-up name")
	own(test_ui(user, console, "clear", list("ref" = ref_token(raised))))
	TEST_ASSERT_EQUAL(air_alarm.resets, 1, "the listed alarm's handle resets the air alarm that raised it")
	GLOB.atmosphere_alarm.clearAlarm(alarm_area, air_alarm)

/// The bomb tester: tanks by handle, only the ones loaded.
/datum/unit_test/dq_topic5_bomb_tester_window

/datum/unit_test/dq_topic5_bomb_tester_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/bomb_tester/tester = allocate(/obj/machinery/bomb_tester, get_step(T, EAST))
	tester.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(tester.tgui_status(user, tester.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the tester works its window")
	TEST_ASSERT_EQUAL(tester.tgui_status(clientless, tester.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/item/tank/loaded = allocate(/obj/item/tank, T)
	var/obj/item/tank/stray = allocate(/obj/item/tank, T)
	TEST_ASSERT(move_into(tester, nameof(/obj/machinery/bomb_tester::tank1), loaded, user), "a tank is loaded")
	var/list/data = hc_data(tester, user)
	TEST_ASSERT_EQUAL(data["tank1ref"], ref_token(loaded), "the window names the loaded tank by handle")
	own(test_ui(user, tester, "remove_tank", list("ref" = ref_token(stray))))
	TEST_ASSERT_EQUAL(tester.tank1, loaded, "a tank that is not loaded takes nothing out")
	own(test_ui(user, tester, "remove_tank", list("ref" = "not a handle")))
	TEST_ASSERT_EQUAL(tester.tank1, loaded, "nor does a made-up name")
	own(test_ui(user, tester, "remove_tank", list("ref" = ref_token(loaded))))
	TEST_ASSERT_NULL(tester.tank1, "the loaded tank's handle takes it out")

/// The turbolift panel: floors by handle, only the lift's own.
/datum/unit_test/dq_topic5_turbolift_window

/datum/unit_test/dq_topic5_turbolift_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/structure/lift/panel/panel = allocate(/obj/structure/lift/panel, get_step(T, EAST))
	var/datum/turbolift/lift = allocate(/datum/turbolift)
	var/datum/turbolift_floor/mine = allocate(/datum/turbolift_floor)
	var/datum/turbolift_floor/foreign = allocate(/datum/turbolift_floor)
	rel_add(lift, nameof(/datum/turbolift::floors), mine)
	rel_set(panel, nameof(/obj/structure/lift::lift), lift)
	TEST_ASSERT_EQUAL(panel.tgui_status(user, panel.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the panel works its window")
	TEST_ASSERT_EQUAL(panel.tgui_status(clientless, panel.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/list/data = hc_data(panel, user)
	var/found = FALSE
	for(var/list/row in data["floors"])
		if(row["ref"] == ref_token(mine))
			found = TRUE
	TEST_ASSERT(found, "the window names the floor by handle")
	own(test_ui(user, panel, "move_to_floor", list("ref" = ref_token(foreign))))
	TEST_ASSERT(!(foreign in lift.queued_floors), "a floor of another lift is not queued")
	own(test_ui(user, panel, "move_to_floor", list("ref" = "not a handle")))
	TEST_ASSERT(!LAZYLEN(lift.queued_floors), "nor is one by a made-up name")
	own(test_ui(user, panel, "move_to_floor", list("ref" = ref_token(mine))))
	TEST_ASSERT(mine in lift.queued_floors, "the lift's own floor is queued by its handle")

/// The drone control console: drones by handle, only the ones it shows.
/datum/unit_test/dq_topic5_drone_console_window

/datum/unit_test/dq_topic5_drone_console_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/drone_control/console = allocate(/obj/machinery/computer/drone_control, get_step(T, EAST))
	console.set_grid_power(TRUE)
	console.set_req_access(list()) // opens the console's own access gate, which a person with no ID cannot pass
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/mob/living/silicon/robot/drone/mine = allocate(/mob/living/silicon/robot/drone, get_step(T, NORTH))
	var/mob/living/silicon/robot/drone/foreign = allocate(/mob/living/silicon/robot/drone, get_step(T, SOUTH))
	foreign.foreign_droid = TRUE
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["drones"])
		if(row["ref"] == ref_token(mine))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(foreign), "a foreign drone is not listed")
	TEST_ASSERT(found, "the window names the drone by handle")
	own(test_ui(user, console, "shutdown", list("ref" = ref_token(foreign))))
	TEST_ASSERT(foreign.stat != DEAD, "a drone the console does not list is not shut down")
	own(test_ui(user, console, "shutdown", list("ref" = "not a handle")))
	TEST_ASSERT(mine.stat != DEAD, "nor is one by a made-up name")
	own(test_ui(user, console, "shutdown", list("ref" = ref_token(mine))))
	TEST_ASSERT_EQUAL(mine.stat, DEAD, "the listed drone's handle shuts it down")

/// The exosuit control console: tracking beacons by handle, only the ones in an exosuit.
/datum/unit_test/dq_topic5_mecha_console_window

/datum/unit_test/dq_topic5_mecha_console_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/mecha/console = allocate(/obj/machinery/computer/mecha, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/mecha/working/ripley/suit = allocate(/obj/mecha/working/ripley, get_step(T, NORTH))
	var/obj/item/mecha_parts/mecha_tracking/worn = allocate(/obj/item/mecha_parts/mecha_tracking, suit)
	var/obj/item/mecha_parts/mecha_tracking/loose = allocate(/obj/item/mecha_parts/mecha_tracking, get_step(T, SOUTH))
	TEST_ASSERT_NOTNULL(worn.in_mecha(), "the beacon is in the exosuit")
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["beacons"])
		if(row["ref"] == ref_token(worn))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(loose), "a beacon that is in no exosuit is not listed")
	TEST_ASSERT(found, "the window names the beacon by handle")
	TEST_ASSERT_NULL(console.beacon_of(ref_token(loose)), "a loose beacon is not one the console names")
	TEST_ASSERT_NULL(console.beacon_of("not a handle"), "nor is a made-up name")
	TEST_ASSERT_EQUAL(console.beacon_of(ref_token(worn)), worn, "the worn beacon's handle names it")
	var/datum/op_result/refused = test_ui(user, console, "send_message", list("mt" = ref_token(loose)))
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "the message button refuses a beacon the window does not list")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "which asks nothing")
	console.set_stored_data(list("dq-topic5-marker"))
	own(test_ui(user, console, "get_log", list("mt" = ref_token(loose))))
	TEST_ASSERT_EQUAL(console.stored_data[1], "dq-topic5-marker", "a loose beacon's log is not read")
	own(test_ui(user, console, "get_log", list("mt" = ref_token(worn))))
	TEST_ASSERT(console.stored_data[1] != "dq-topic5-marker" || length(console.stored_data) != 1, "the worn beacon's handle reads its log")

/// The robotics control console: cyborgs by handle, only the ones it shows.
/datum/unit_test/dq_topic5_robotics_window

/datum/unit_test/dq_topic5_robotics_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/robotics/console = allocate(/obj/machinery/computer/robotics, get_step(T, EAST))
	console.set_grid_power(TRUE)
	console.set_req_access(list())
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/mob/living/silicon/robot/shown = allocate(/mob/living/silicon/robot, get_step(T, NORTH))
	var/mob/living/silicon/robot/drone/hidden = allocate(/mob/living/silicon/robot/drone, get_step(T, SOUTH))
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["cyborgs"])
		if(row["ref"] == ref_token(shown))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(hidden), "a drone is not listed")
	TEST_ASSERT(found, "the window names the cyborg by handle")
	own(test_ui(user, console, "stopbot", list("ref" = ref_token(hidden))))
	TEST_ASSERT(!hidden.lockcharge, "a cyborg the console does not show is not locked down")
	own(test_ui(user, console, "stopbot", list("ref" = "not a handle")))
	TEST_ASSERT(!shown.lockcharge, "nor is one by a made-up name")
	own(test_ui(user, console, "stopbot", list("ref" = ref_token(shown))))
	TEST_ASSERT(shown.lockcharge, "the shown cyborg's handle locks it down")

/// The safe: contents by handle, only what is inside.
/datum/unit_test/dq_topic5_safe_window

/datum/unit_test/dq_topic5_safe_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/structure/safe/safe = allocate(/obj/structure/safe, get_step(T, EAST))
	TEST_ASSERT_EQUAL(safe.tgui_status(user, safe.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the safe works its window")
	TEST_ASSERT_EQUAL(safe.tgui_status(clientless, safe.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/item/pen/inside = allocate(/obj/item/pen, safe)
	var/obj/item/pen/outside = allocate(/obj/item/pen, get_step(T, NORTH))
	safe.set_open(TRUE)
	var/list/data = hc_data(safe, user)
	var/found = FALSE
	for(var/list/row in data["contents"])
		if(row["ref"] == ref_token(inside))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(outside), "a thing outside the safe is not listed")
	TEST_ASSERT(found, "the window names what is inside by handle")
	own(test_ui(user, safe, "retrieve", list("ref" = ref_token(outside))))
	TEST_ASSERT(outside.loc != user, "a thing outside the safe is not handed over")
	own(test_ui(user, safe, "retrieve", list("ref" = "not a handle")))
	TEST_ASSERT(inside.loc == safe, "nor is anything by a made-up name")
	own(test_ui(user, safe, "retrieve", list("ref" = ref_token(inside))))
	TEST_ASSERT(inside.loc != safe, "what is inside comes out by its handle")

/// The point defense control: turrets by handle, only the ones on its tag in reach.
/datum/unit_test/dq_topic5_point_defense_window

/datum/unit_test/dq_topic5_point_defense_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/pointdefense_control/console = allocate(/obj/machinery/pointdefense_control, get_step(T, EAST))
	console.set_grid_power(TRUE)
	console.set_id_tag("dq-topic5-pd")
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/machinery/pointdefense/mine = allocate(/obj/machinery/pointdefense, get_step(T, NORTH))
	mine.set_id_tag("dq-topic5-pd")
	var/obj/machinery/pointdefense/other = allocate(/obj/machinery/pointdefense, get_step(T, SOUTH))
	other.set_id_tag("dq-topic5-other")
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["turrets"])
		if(row["ref"] == ref_token(mine))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(other), "a turret on another tag is not listed")
	TEST_ASSERT(found, "the window names the turret by handle")
	var/active = mine.active
	var/other_active = other.active
	own(test_ui(user, console, "toggle_active", list("target" = ref_token(other))))
	TEST_ASSERT_EQUAL(other.active, other_active, "a turret on another tag is not switched")
	own(test_ui(user, console, "toggle_active", list("target" = "not a handle")))
	TEST_ASSERT_EQUAL(mine.active, active, "nor is one by a made-up name")
	own(test_ui(user, console, "toggle_active", list("target" = ref_token(mine))))
	TEST_ASSERT(mine.active != active, "the listed turret's handle switches it")

/// The security records console: records by handle, only the ones in the data core, and only to a person who is logged in.
/datum/unit_test/dq_topic5_security_records_window

/datum/unit_test/dq_topic5_security_records_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/secure_data/console = allocate(/obj/machinery/computer/secure_data, get_step(T, EAST))
	console.set_grid_power(TRUE)
	console.set_broken_condition(FALSE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/datum/data/record/listed = GLOB.data_core.CreateGeneralRecord(null, "5SEC")
	listed.set_fields_at("name", "Dq Topic Five")
	var/datum/data/record/stray = new
	stray.set_fields_at("name", "Dq Topic Stray")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(listed))))
	TEST_ASSERT_NULL(console.active1(), "a person who is not logged in opens no record")
	console.set_authenticated("Dq Topic")
	console.set_screen(2) // the record list (the console keeps its screen numbers to itself)
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["records"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
			TEST_ASSERT_EQUAL(row["name"], "Dq Topic Five", "the record is listed with its name")
	TEST_ASSERT(found, "the window names the record by handle")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(stray))))
	TEST_ASSERT_NULL(console.active1(), "a record that is not in the data core is not opened")
	own(test_ui(user, console, "d_rec", list("d_rec" = "not a handle")))
	TEST_ASSERT_NULL(console.active1(), "nor is a made-up name")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(listed))))
	TEST_ASSERT_EQUAL(console.active1(), listed, "a listed record's handle opens it")
	qdel(listed)
	qdel(stray)

/// The skills records console: records by handle, only the ones in the data core, and only to a person who is logged in.
/datum/unit_test/dq_topic5_skills_records_window

/datum/unit_test/dq_topic5_skills_records_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/skills/console = allocate(/obj/machinery/computer/skills, get_step(T, EAST))
	console.set_grid_power(TRUE)
	console.set_broken_condition(FALSE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/datum/data/record/listed = GLOB.data_core.CreateGeneralRecord(null, "5SKL")
	listed.set_fields_at("name", "Dq Topic Five Skills")
	var/datum/data/record/stray = new
	stray.set_fields_at("name", "Dq Topic Stray")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(listed))))
	TEST_ASSERT_NULL(console.active1(), "a person who is not logged in opens no record")
	console.set_authenticated("Dq Topic")
	console.set_screen(2) // the record list (the console keeps its screen numbers to itself)
	var/list/data = hc_data(console, user)
	var/found = FALSE
	for(var/list/row in data["records"])
		if(row["ref"] == ref_token(listed))
			found = TRUE
	TEST_ASSERT(found, "the window names the record by handle")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(stray))))
	TEST_ASSERT_NULL(console.active1(), "a record that is not in the data core is not opened")
	own(test_ui(user, console, "d_rec", list("d_rec" = "not a handle")))
	TEST_ASSERT_NULL(console.active1(), "nor is a made-up name")
	own(test_ui(user, console, "d_rec", list("d_rec" = ref_token(listed))))
	TEST_ASSERT_EQUAL(console.active1(), listed, "a listed record's handle opens it")
	qdel(listed)
	qdel(stray)

/// The ship helm: waypoints by handle, only the console's own entries.
/datum/unit_test/dq_topic5_ship_helm_window

/datum/unit_test/dq_topic5_ship_helm_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/machinery/computer/ship/helm/console = allocate(/obj/machinery/computer/ship/helm, get_step(T, EAST))
	console.set_grid_power(TRUE)
	TEST_ASSERT_EQUAL(console.tgui_status(user, console.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the console works its window")
	TEST_ASSERT_EQUAL(console.tgui_status(clientless, console.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/effect/overmap/visitable/ship/ship = allocate(/obj/effect/overmap/visitable/ship, T)
	rel_set(console, nameof(/obj/machinery/computer/ship::linked), ship)
	var/datum/computer_file/data/waypoint/mine = allocate(/datum/computer_file/data/waypoint)
	mine.fields["name"] = "dq-topic5-mine"
	mine.fields["x"] = 3
	mine.fields["y"] = 4
	rel_add(console, nameof(/obj/machinery/computer/ship/helm::known_sectors), mine, "dq-topic5-mine")
	var/datum/computer_file/data/waypoint/foreign = allocate(/datum/computer_file/data/waypoint)
	foreign.fields["name"] = "dq-topic5-foreign"
	TEST_ASSERT_EQUAL(console.waypoint_of(ref_token(mine)), mine, "the console's own waypoint is named by its handle")
	TEST_ASSERT_NULL(console.waypoint_of(ref_token(foreign)), "another waypoint is not")
	TEST_ASSERT_NULL(console.waypoint_of("not a handle"), "nor is a made-up name")
	own(test_ui(user, console, "remove", list("remove" = ref_token(foreign))))
	TEST_ASSERT(console.known_sectors["dq-topic5-mine"] == mine, "a waypoint the console does not hold stays")
	own(test_ui(user, console, "remove", list("remove" = ref_token(mine))))
	TEST_ASSERT_NULL(console.known_sectors?["dq-topic5-mine"], "the console's own waypoint is removed by its handle")

/// The noticeboard: notices by handle, only the ones pinned to it.
/datum/unit_test/dq_topic5_noticeboard_window

/datum/unit_test/dq_topic5_noticeboard_window/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/dq_tgui_transport/user = allocate(/mob/living/carbon/human/dq_tgui_transport, T)
	user.enable_godmode()
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/obj/structure/noticeboard/board = allocate(/obj/structure/noticeboard, get_step(T, EAST))
	TEST_ASSERT_EQUAL(board.tgui_status(user, board.tgui_state(user)), STATUS_INTERACTIVE, "a conscious person at the board works its window")
	TEST_ASSERT_EQUAL(board.tgui_status(clientless, board.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	var/obj/item/paper/pinned = allocate(/obj/item/paper, T)
	var/obj/item/paper/loose = allocate(/obj/item/paper, T)
	rel_add(board, nameof(/obj/structure/noticeboard::notices), pinned)
	pinned.forceMove(board)
	var/list/data = hc_data(board, user)
	var/found = FALSE
	for(var/list/row in data["notices"])
		if(row["ref"] == ref_token(pinned))
			found = TRUE
		TEST_ASSERT(row["ref"] != ref_token(loose), "a paper that is not pinned is not listed")
	TEST_ASSERT(found, "the window names the notice by handle")
	own(test_ui(user, board, "remove", list("ref" = ref_token(loose))))
	TEST_ASSERT(pinned in board.notices, "a paper that is not pinned takes nothing off the board")
	own(test_ui(user, board, "remove", list("ref" = "not a handle")))
	TEST_ASSERT(pinned in board.notices, "nor does a made-up name")
	own(test_ui(user, board, "remove", list("ref" = ref_token(pinned))))
	TEST_ASSERT(!(pinned in board.notices), "the pinned notice comes off by its handle")

/// A ghost that records the virtual reality landmark the menu sent it to (a test world has no client to build an avatar for).
/mob/observer/dead/dq_topic5_ghost
	var/entered_landmark = null

/mob/observer/dead/dq_topic5_ghost/shared_tgui_interaction(src_object)
	if(stat)
		return STATUS_DISABLED
	return STATUS_INTERACTIVE

/mob/observer/dead/dq_topic5_ghost/MayRespawn()
	return TRUE

/mob/observer/dead/dq_topic5_ghost/fake_enter_vr(landmark)
	entered_landmark = landmark

/// A drone fabricator that records the player it was asked to make a drone for.
/obj/machinery/drone_fabricator/dq_topic5_recording
	var/made_for = 0

/obj/machinery/drone_fabricator/dq_topic5_recording/create_drone(client/player)
	made_for++

/// The ghost spawn menu's fabricator, virtual reality and player buttons: each takes only what the registries list, and carries it out.
/datum/unit_test/dq_topic5_ghost_buttons_window

/datum/unit_test/dq_topic5_ghost_buttons_window/Run()
	test_driver_begin()
	set_var(SSticker, "current_state", GAME_STATE_PLAYING)
	var/turf/T = test_floor()
	var/mob/observer/dead/dq_topic5_ghost/ghost = allocate(/mob/observer/dead/dq_topic5_ghost, T)
	ghost.set_timeofdeath(-1 HOURS) // dead long enough to spawn as a drone
	var/mob/living/carbon/human/clientless = allocate(/mob/living/carbon/human, T)
	var/datum/tgui_module/ghost_spawn_menu/window = allocate(/datum/tgui_module/ghost_spawn_menu)
	TEST_ASSERT_EQUAL(window.tgui_status(ghost, window.tgui_state(ghost)), STATUS_INTERACTIVE, "a ghost works the window")
	TEST_ASSERT_EQUAL(window.tgui_status(clientless, window.tgui_state(clientless)), STATUS_CLOSE, "a person with no client is closed out of it")
	// virtual reality: a landmark of the registry is entered, anything else is not
	var/obj/effect/landmark/virtual_reality/vr = allocate(/obj/effect/landmark/virtual_reality, get_step(T, EAST))
	var/obj/effect/landmark/virtual_reality/vr_stray = allocate(/obj/effect/landmark/virtual_reality, get_step(T, WEST))
	registry_leave(REGISTRY_LANDMARKS, vr_stray)
	own(test_ui(ghost, window, "vr_spawn", list("landmark" = ref_token(vr_stray))))
	TEST_ASSERT_NULL(ghost.entered_landmark, "a landmark outside the registry is not entered")
	own(test_ui(ghost, window, "vr_spawn", list("landmark" = "not a handle")))
	TEST_ASSERT_NULL(ghost.entered_landmark, "nor is one by a made-up name")
	own(test_ui(ghost, window, "vr_spawn", list("landmark" = ref_token(vr))))
	TEST_ASSERT_EQUAL(ghost.entered_landmark, vr, "the registered landmark's handle sends the ghost into it")
	// drone fabricators
	var/obj/machinery/drone_fabricator/dq_topic5_recording/fab = allocate(/obj/machinery/drone_fabricator/dq_topic5_recording, get_step(T, NORTH))
	fab.set_grid_power(TRUE)
	fab.set_produce_drones(TRUE)
	fab.set_drone_progress(100)
	var/obj/machinery/drone_fabricator/dq_topic5_recording/fab_stray = allocate(/obj/machinery/drone_fabricator/dq_topic5_recording, get_step(T, SOUTH))
	fab_stray.set_grid_power(TRUE)
	fab_stray.set_produce_drones(TRUE)
	fab_stray.set_drone_progress(100)
	registry_leave(REGISTRY_DRONE_FABRICATORS, fab_stray)
	own(test_ui(ghost, window, "drone_spawn", list("fabricator" = ref_token(fab_stray))))
	TEST_ASSERT_EQUAL(fab_stray.made_for, 0, "a fabricator outside the registry makes no drone")
	own(test_ui(ghost, window, "drone_spawn", list("fabricator" = "not a handle")))
	TEST_ASSERT_EQUAL(fab.made_for, 0, "nor does one by a made-up name")
	own(test_ui(ghost, window, "drone_spawn", list("fabricator" = ref_token(fab))))
	TEST_ASSERT_EQUAL(fab.made_for, 1, "the registered fabricator's handle makes a drone for the ghost")
	// players: the soulcatcher request goes to the player the handle names, and to nobody else
	var/mob/living/carbon/human/host = allocate(/mob/living/carbon/human, get_step(T, EAST))
	var/mob/living/carbon/human/stray_host = allocate(/mob/living/carbon/human, get_step(T, WEST))
	host.enable_godmode()
	stray_host.enable_godmode()
	var/obj/soulgem/gem = allocate(/obj/soulgem, T)
	gem.transfer_self(host)
	TEST_ASSERT_EQUAL(host.soulgem, gem, "the soulgem is the host's")
	gem.set_setting_flags(gem.setting_flags | SOULGEM_ACTIVE)
	var/obj/soulgem/stray_gem = allocate(/obj/soulgem, T)
	stray_gem.transfer_self(stray_host)
	stray_gem.set_setting_flags(stray_gem.setting_flags | SOULGEM_ACTIVE)
	registry_join(REGISTRY_PLAYERS, host)
	own(test_ui(ghost, window, "soulcatcher_vore_spawn", list("selected_player" = ref_token(stray_host))))
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(SSrequests.open_for(stray_host), "a person outside the registry is asked nothing")
	own(test_ui(ghost, window, "soulcatcher_vore_spawn", list("selected_player" = "not a handle")))
	test_time(3 SECONDS)
	TEST_ASSERT_NULL(SSrequests.open_for(host), "nor is anyone by a made-up name")
	own(test_ui(ghost, window, "soulcatcher_vore_spawn", list("selected_player" = ref_token(host))))
	test_time(3 SECONDS)
	TEST_ASSERT(istype(SSrequests.open_for(host), /datum/prompt/choice/soulcatcher_admission), "the registered player is asked whether the ghost may join")
	test_answer(host, null, REQ_CANCELLED)
	registry_leave(REGISTRY_PLAYERS, host)
	test_driver_end()
