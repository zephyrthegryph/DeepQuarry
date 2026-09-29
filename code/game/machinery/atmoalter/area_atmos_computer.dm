/obj/machinery/computer/area_atmos

	name = "Area Air Control"
	desc = "A computer used to control the stationary scrubbers and pumps in the area."
	icon_keyboard = "atmos_key"
	icon_screen = "area_atmos"
	light_color = "#e6ffff"
	circuit = /obj/item/circuitboard/area_atmos

	/// Scrubbers found by the last scan (a relation view: dead ones leave by themselves).
	var/list/obj/machinery/portable_atmospherics/powered/scrubber/huge/connectedscrubbers
	var/status = ""

	var/range = 25

	//Simple variable to prevent me from doing attack_hand in both this and the child computer
	var/zone = "This computer is working on a wireless range, the range is currently limited to "

/obj/machinery/computer/area_atmos/declare_ownership(decl)
	..()
	rel(decl, nameof(connectedscrubbers), list = TRUE)

/// The connected scrubber with this id, or null.
/obj/machinery/computer/area_atmos/proc/scrubber_by_id(scrub_id)
	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/S as anything in connectedscrubbers)
		if("[S.id]" == "[scrub_id]")
			return S
	return null

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
	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber as anything in connectedscrubbers)
		if(!validscrubber(scrubber))
			rel_remove(src, nameof(connectedscrubbers), scrubber)
			continue
		working.Add(list(list(
			"id" = "[scrubber.id]",
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
	var/obj/machinery/portable_atmospherics/powered/scrubber/huge/S = scrubber_by_id(scrub_id)
	if(!validscrubber(S))
		rel_remove(src, nameof(/obj/machinery/computer/area_atmos::connectedscrubbers), S)
		return TRUE
	S.set_on(!S.on)
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
	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/S as anything in connectedscrubbers)
		if(!validscrubber(S))
			rel_remove(src, nameof(connectedscrubbers), S)
			continue
		S.set_on(on)
		MACHINE_WAKE(S)
		CHECK_TICK

/obj/machinery/computer/area_atmos/proc/validscrubber(obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber as obj)
	if(!isobj(scrubber) || get_dist(scrubber.loc, src.loc) > src.range || scrubber.loc.z != src.loc.z)
		return FALSE
	return TRUE

/obj/machinery/computer/area_atmos/proc/scanscrubbers()
	rel_clear(src, nameof(connectedscrubbers))

	var/found = 0
	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber in range(range, src.loc))
		found = 1
		rel_add(src, nameof(connectedscrubbers), scrubber)

	if(!found)
		status = "ERROR: No scrubber found!"

/obj/machinery/computer/area_atmos/proc/scanscrubbers_user(mob/user) //Used when the user is in the UI and scans for scrubbers.
	scanscrubbers()

// The one that only works in the same map area
/obj/machinery/computer/area_atmos/area
	zone = "This computer is working in a wired network limited to this area."

/obj/machinery/computer/area_atmos/area/scanscrubbers(mob/user)
	rel_clear(src, nameof(connectedscrubbers))

	var/found = 0
	var/area/A = get_area(src)
	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber in area_contents_of_type(A, /obj/machinery/portable_atmospherics/powered/scrubber/huge))
		rel_add(src, nameof(connectedscrubbers), scrubber)
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

	rel_clear(src, nameof(connectedscrubbers))

	for(var/obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber in world)
		if(scrubber.scrub_id == src.scrub_id)
			rel_add(src, nameof(connectedscrubbers), scrubber)

	SStgui.update_uis(src)

/obj/machinery/computer/area_atmos/tag/validscrubber(obj/machinery/portable_atmospherics/powered/scrubber/huge/scrubber)
	if(!istype(scrubber))
		return FALSE

	if(scrubber.scrub_id == src.scrub_id)
		return TRUE

	return FALSE
