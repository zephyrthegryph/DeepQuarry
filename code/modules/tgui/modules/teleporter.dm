/datum/tgui_module/teleport_control
	name = "Teleporter Control"
	tgui_id = "Teleporter"
	var/locked_name = "Not Locked"
	var/tmp/obj/item/locked
	var/tmp/obj/machinery/teleport/station/station
	var/tmp/obj/machinery/teleport/hub/hub

UI_DATA(/datum/tgui_module/teleport_control, "merge:ui_data_datum_tgui_module_teleport_control{locked_name:bool,station_connected:bool,hub_connected:bool,calibrated:num,teleporter_on:num}")

/// The computed part of /datum/tgui_module/teleport_control's window data (declared on its UI_DATA row).
/datum/tgui_module/teleport_control/proc/ui_data_datum_tgui_module_teleport_control(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["locked_name"] = locked_name || "No Target"
	data["station_connected"] = !!station()
	data["hub_connected"] = !!hub()
	data["calibrated"] = hub()?.accurate
	data["teleporter_on"] = station()?.engaged

	return data

UI_ACT(/datum/tgui_module/teleport_control, "select_target", ui_act_select_target)
UI_ACT_PROC(/datum/tgui_module/teleport_control, ui_act_select_target)
	var/list/L = list()
	var/list/areaindex = list()

	for(var/obj/item/radio/beacon/R in REGISTRY_MEMBERS(REGISTRY_BEACONS))
		var/turf/T = get_turf(R)
		if(!T)
			continue
		if(!(T.z in using_map.player_levels))
			continue
		var/tmpname = T.loc.name
		if(areaindex[tmpname])
			tmpname = "[tmpname] ([++areaindex[tmpname]])"
		else
			areaindex[tmpname] = 1
		L[tmpname] = R

	for(var/obj/item/implant/tracking/I in REGISTRY_MEMBERS(REGISTRY_TRACKING_IMPLANTS))
		if(!I.implanted || !ismob(I.loc) || is_vore_jammed(I))
			continue
		else
			var/mob/M = I.loc
			if(M.stat == 2)
				if(ELAPSED(M, timeofdeath, CLOCK_WORLD) > 10 MINUTES)
					continue
			var/turf/T = get_turf(M)
			if(!T)
				continue
			if(!(T.z in using_map.station_levels))
				continue
			var/tmpname = M.real_name
			if(areaindex[tmpname])
				tmpname = "[tmpname] ([++areaindex[tmpname]])"
			else
				areaindex[tmpname] = 1
			L[tmpname] = I

	var/desc = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/choice, message = "Please select a location to lock in.", title = "Locking Menu", choices = L)
	if(isnull(desc))
		return
	if(!desc)
		return FALSE
	if(tgui_status(ui.user, state) != STATUS_INTERACTIVE)
		return FALSE

	rel_set(src, "locked", L[desc])
	locked_name = desc
	return TRUE

UI_ACT(/datum/tgui_module/teleport_control, "test_fire", ui_act_test_fire)
UI_ACT_PROC(/datum/tgui_module/teleport_control, ui_act_test_fire)
	station()?.testfire()
	return TRUE

UI_ACT(/datum/tgui_module/teleport_control, "toggle_on", ui_act_toggle_on)
UI_ACT_PROC(/datum/tgui_module/teleport_control, ui_act_toggle_on)
	if(!station())
		return FALSE

	if(station().engaged)
		station().disengage(ui.user)
	else
		station().engage(ui.user)

	return TRUE

/// The locked this refers to (a relation view: null once that is deleted).
/datum/tgui_module/teleport_control/proc/locked() as /obj/item
	return locked

/// The station this refers to (a relation view: null once that is deleted).
/datum/tgui_module/teleport_control/proc/station() as /obj/machinery/teleport/station
	return station

/// The hub this refers to (a relation view: null once that is deleted).
/datum/tgui_module/teleport_control/proc/hub() as /obj/machinery/teleport/hub
	return hub
