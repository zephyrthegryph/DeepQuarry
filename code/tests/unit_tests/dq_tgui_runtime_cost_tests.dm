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
