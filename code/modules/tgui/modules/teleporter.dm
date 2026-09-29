/datum/tgui_module/teleport_control
	name = "Teleporter Control"
	tgui_id = "Teleporter"
	var/locked_name = "Not Locked"
	var/tmp/obj/item/locked
	var/tmp/obj/machinery/teleport/station/station
	var/tmp/obj/machinery/teleport/hub/hub

/datum/tgui_module/teleport_control/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = ..()

	data["locked_name"] = locked_name || "No Target"
	data["station_connected"] = !!station()
	data["hub_connected"] = !!hub()
	data["calibrated"] = hub()?.accurate
	data["teleporter_on"] = station()?.engaged

	return data

/datum/tgui_module/teleport_control/tgui_act(action, params, datum/tgui/ui, datum/tgui_state/state)
	if(..())
		return TRUE

	switch(action)
		if("select_target")
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
						if(M.timeofdeath + 6000 < world.time)
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

		if("test_fire")
			station()?.testfire()
			return TRUE

		if("toggle_on")
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
