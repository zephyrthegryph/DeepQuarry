/obj/machinery/computer/area_atmos

	name = "Area Air Control"
	desc = "A computer used to control the stationary scrubbers and pumps in the area."
	icon_keyboard = "atmos_key"
	icon_screen = "area_atmos"
	light_color = "#e6ffff"
	circuit = /obj/item/circuitboard/area_atmos

	var/list/connectedscrubbers = list() // ALLOW(instance_list): d: filled when the console scans; atmos console
	var/status = ""

	var/range = 25

	//Simple variable to prevent me from doing attack_hand in both this and the child computer
	var/zone = "This computer is working on a wireless range, the range is currently limited to "

/obj/machinery/computer/area_atmos/Initialize(mapload)
	. = ..()
	scanscrubbers()

/obj/machinery/computer/area_atmos/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/open_ui,
	)
	..()

DECLARE_UI(/obj/machinery/computer/area_atmos, "AreaScrubberControl")

UI_DATA_REPLACE(/obj/machinery/computer/area_atmos, "merge:ui_data_obj_machinery_computer_area_atmos{}")

/// The computed part of /obj/machinery/computer/area_atmos's window data (declared on its UI_DATA row).
/obj/machinery/computer/area_atmos/proc/ui_data_obj_machinery_computer_area_atmos(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/working = list()
	for(var/id in connectedscrubbers)
		var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber = connectedscrubbers[id]
		if(!validscrubber(scrubber))
			connectedscrubbers -= scrubber
			continue
		working.Add(list(list(
			"id" = id,
			"name" = scrubber.name,
			"on" = scrubber.on,
			"pressure" = scrubber.air_contents.return_pressure(),
			"flow_rate" = scrubber.last_flow_rate,
			"load" = scrubber.last_power_draw,
			"area" = get_area(scrubber),
		)))

	return list("scrubbers" = working)

UI_ACT(/obj/machinery/computer/area_atmos, "toggle", ui_act_toggle, UI_ARG_TEXT("id"))
UI_ACT_PROC(/obj/machinery/computer/area_atmos, ui_act_toggle)
	var/scrub_id = params["id"]
	var/obj/machinery/portable_atmospherics/powered/scrubber/huge/S = connectedscrubbers["[scrub_id]"]
	if(!validscrubber(S))
		connectedscrubbers -= S
		return TRUE
	S.set_on(!S.on)
	S.update_icon()
	MACHINE_WAKE(S)
	. = TRUE
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/computer/area_atmos, "allon", ui_act_allon)
UI_ACT_PROC(/obj/machinery/computer/area_atmos, ui_act_allon)
	toggle_all(TRUE)
	. = TRUE
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/computer/area_atmos, "alloff", ui_act_alloff)
UI_ACT_PROC(/obj/machinery/computer/area_atmos, ui_act_alloff)
	toggle_all(FALSE)
	. = TRUE
	add_fingerprint(ui.user)

UI_ACT(/obj/machinery/computer/area_atmos, "scan", ui_act_scan)
UI_ACT_PROC(/obj/machinery/computer/area_atmos, ui_act_scan)
	scanscrubbers_user(ui.user)
	. = TRUE
	add_fingerprint(ui.user)

/obj/machinery/computer/area_atmos/proc/toggle_all(on)
	for(var/id in connectedscrubbers)
		var/obj/machinery/portable_atmospherics/powered/scrubber/huge/S = connectedscrubbers["[id]"]
		if(!validscrubber(S))
			connectedscrubbers -= S
			continue
		S.set_on(on)
		S.update_icon()
		MACHINE_WAKE(S)
		CHECK_TICK

/obj/machinery/computer/area_atmos/proc/validscrubber(obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber as obj)
	if(!isobj(scrubber) || get_dist(scrubber.loc, src.loc) > src.range || scrubber.loc.z != src.loc.z)
		return FALSE
	return TRUE

/obj/machinery/computer/area_atmos/proc/scanscrubbers()
	connectedscrubbers = list()

	var/found = 0
	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber in range(range, src.loc))
		found = 1
		// ALLOW(object_keyed_lists): scan roster of nearby scrubbers, rebuilt by every scan and pruned when one is gone
		connectedscrubbers["[scrubber.id]"] = scrubber

	if(!found)
		status = "ERROR: No scrubber found!"

/obj/machinery/computer/area_atmos/proc/scanscrubbers_user(mob/user) //Used when the user is in the UI and scans for scrubbers.
	scanscrubbers()

// The one that only works in the same map area
/obj/machinery/computer/area_atmos/area
	zone = "This computer is working in a wired network limited to this area."

/obj/machinery/computer/area_atmos/area/scanscrubbers(mob/user)
	connectedscrubbers.Cut()

	var/found = 0
	var/area/A = get_area(src)
	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber in area_contents_of_type(A, /obj/machinery/portable_atmospherics/powered/scrubber/huge))
		// ALLOW(object_keyed_lists): scan roster of nearby scrubbers, rebuilt by every scan and pruned when one is gone
		connectedscrubbers["[scrubber.id]"] = scrubber
		found = 1

	if(!found)
		status = "ERROR: No scrubber found!"

/obj/machinery/computer/area_atmos/area/scanscrubbers_user(mob/user) //Used when the user is in the UI and scans for scrubbers.
	scanscrubbers()

/obj/machinery/computer/area_atmos/area/validscrubber(obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber)
	if(!istype(scrubber))
		return FALSE

	if(get_area(scrubber) == get_area(src))
		return TRUE

	return FALSE


// The one that only works in the same map area
/obj/machinery/portable_atmospherics/powered/scrubber/huge/var/scrub_id = "generic"

/obj/machinery/computer/area_atmos/tag
	name = "Heavy Scrubber Control"
	zone = "This computer is operating industrial scrubbers nearby."
	var/scrub_id = "generic"
	EXPIRY_DECLARE(last_scan)

/obj/machinery/computer/area_atmos/tag/scanscrubbers()
	if(last_scan && ELAPSED(src, last_scan, CLOCK_WORLD) < 20 SECONDS)
		return 0
	else
		EXPIRY_STAMP(src, last_scan, CLOCK_WORLD)

	connectedscrubbers.Cut()

	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber in world)
		if(scrubber.scrub_id == src.scrub_id)
			// ALLOW(object_keyed_lists): scan roster of nearby scrubbers, rebuilt by every scan and pruned when one is gone
			connectedscrubbers["[scrubber.id]"] = scrubber

	SStgui.update_uis(src)

/obj/machinery/computer/area_atmos/tag/validscrubber(obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber)
	if(!istype(scrubber))
		return FALSE

	if(scrubber.scrub_id == src.scrub_id)
		return TRUE

	return FALSE
