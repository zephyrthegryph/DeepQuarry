// The server's running cost of open windows: ten crew, each with a PDA, a vendor, an APC and a crew monitor in front of them. Per interface:
// the cost and size of one ui_data build, whether two builds in a row are identical (a push the window drops as unchanged: tgui_window.dm
// same_key) and how often the interface is rebuilt (autoupdate: every 0.9 s; the others when state they read is published).
// TGUI_RUNTIME_COST lines are the measurement.

/datum/unit_test/dq_tgui_runtime_cost
/datum/unit_test/dq_tgui_runtime_cost/Run()
	var/turf/T = test_floor()
	var/list/crew = list()
	for(var/i in 1 to 10)
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
		H.equip_to_slot_or_del(new /obj/item/clothing/under/color/grey(H), SLOT_ID_UNIFORM)
		crew += H
	var/mob/living/carbon/human/viewer = crew[1]
	var/obj/item/pda/pda = allocate(/obj/item/pda, T)
	var/obj/machinery/vending/coffee/vendor = allocate(/obj/machinery/vending/coffee, get_step(T, EAST))
	var/obj/machinery/power/apc/apc = locate() in world
	var/obj/machinery/computer/crew/console = allocate(/obj/machinery/computer/crew, get_step(T, WEST))
	measure(viewer, pda, "PDA", FALSE)
	measure(viewer, vendor, "vendor", FALSE)
	if(apc)
		measure(viewer, apc, "APC", FALSE)
	measure(viewer, console.crew_monitor, "crew monitor", TRUE)

/datum/unit_test/dq_tgui_runtime_cost/proc/measure(mob/user, datum/holder, label, autoupdate)
	var/n = 10
	var/list/first
	var/list/data
	var/started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		data = list()
		present_tgui_data(holder, user, data)
		if(!first)
			first = data
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/same = json_encode(first) == json_encode(data)
	var/bytes = length(json_encode(data))
	var/builds_per_minute = autoupdate ? round(60 / 0.9) : 0
	var/sends_per_minute = autoupdate ? (same ? 0 : builds_per_minute) : 0
	TEST_NOTICE(src, "TGUI_RUNTIME_COST [label]: ui_data [round(ms, 0.01)] ms, [bytes] bytes, rebuilt [autoupdate ? "every 0.9 s ([builds_per_minute]/min)" : "on published change"], two builds identical: [same ? "yes" : "no"], sends/min while unchanged: [sends_per_minute], so [round(sends_per_minute * bytes / 60)] bytes/s per window")

/// The power monitor while the grid it watches changes (APCs charging): the cost and size of a build focused on a sensor, and how many of
/// one rebuild a second over 20 s were new data (the rest the window drops).
/datum/unit_test/dq_tgui_runtime_cost_power
/datum/unit_test/dq_tgui_runtime_cost_power/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/machinery/power/sensor/S = locate() in world
	if(!S)
		TEST_NOTICE(src, "TGUI_RUNTIME_COST power monitor: no sensor on the map")
		test_driver_end()
		return
	var/datum/tgui_module/power_monitor/M = new(S)
	M.refresh_sensors()
	M.set_active_sensor(S.name_tag)
	var/n = 10
	var/list/data
	var/started = TICK_USAGE_REAL
	for(var/i in 1 to n)
		data = list()
		present_tgui_data(M, H, data)
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / n
	var/last = json_encode(data)
	var/changed = 0
	for(var/second in 1 to 20)
		test_time(1 SECOND)
		data = list()
		present_tgui_data(M, H, data)
		var/now = json_encode(data)
		if(now != last)
			changed++
		last = now
	TEST_NOTICE(src, "TGUI_RUNTIME_COST power monitor: ui_data [round(ms, 0.01)] ms, [length(last)] bytes, [changed] of 20 one-second rebuilds were new data")
	qdel(M)
	test_driver_end()

/// The camera console while its camera moves: what one step of the camera costs the console (its view recomputed for the map view).
/datum/unit_test/dq_tgui_runtime_cost_camera
/datum/unit_test/dq_tgui_runtime_cost_camera/Run()
	var/turf/T = test_floor()
	var/obj/machinery/camera/C = allocate(/obj/machinery/camera, T)
	var/datum/tgui_module/camera/M = new(null, list(NETWORK_DEFAULT))
	rel_set(M, nameof(/datum/tgui_module/camera::active_camera), C)
	M.update_active_camera_screen()
	var/steps = 0
	var/started = TICK_USAGE_REAL
	for(var/dir in list(EAST, EAST, NORTH, NORTH, WEST, WEST, SOUTH, SOUTH))
		var/turf/next = get_step(C, dir)
		if(!next || next.density)
			continue
		C.forceMove(next)
		M.update_active_camera_screen()
		steps++
	var/ms = steps ? TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) / steps : 0
	var/list/data = list()
	present_tgui_data(M, null, data)
	TEST_NOTICE(src, "TGUI_RUNTIME_COST camera console: [round(ms, 0.01)] ms a camera step ([steps] steps), ui_data [length(json_encode(data))] bytes")
	qdel(M)
