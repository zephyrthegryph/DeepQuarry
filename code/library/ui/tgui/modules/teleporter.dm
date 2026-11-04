/datum/tgui_module/teleport_control
	name = "Teleporter Control"
	var/locked_name = "Not Locked"
	var/tmp/obj/item/locked
	var/tmp/obj/machinery/teleport/station/station
	var/tmp/obj/machinery/teleport/hub/hub

CAPABILITIES(/datum/tgui_module/teleport_control)
	interface("Teleporter")
	op("select_target", ui_act("select_target"), asks(/datum/prompt/choice, fields = list("title" = "Locking Menu", "question" = "Please select a location to lock in.", "choices" = computed(PROC_REF(target_choices)), "timeout" = 0)), then(PROC_REF(ui_act_select_target)))
	op("test_fire", ui_act("test_fire"), then(PROC_REF(ui_act_test_fire)))
	op("toggle_on", ui_act("toggle_on"), then(PROC_REF(ui_act_toggle_on)))
	ref_one(nameof(hub))
	ref_one(nameof(locked))
	ref_one(nameof(station))

/datum/tgui_module/teleport_control/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["locked_name"] = locked_name || "No Target"
	data["station_connected"] = !!station()
	data["hub_connected"] = !!hub()
	data["calibrated"] = hub()?.accurate
	data["teleporter_on"] = station()?.engaged

	return data

/// The places the teleporter can lock onto, by the name the window shows.
/datum/tgui_module/teleport_control/proc/teleport_targets()
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
	return L

/datum/tgui_module/teleport_control/proc/target_choices(datum/act/A)
	return teleport_targets()

/datum/tgui_module/teleport_control/proc/ui_act_select_target(datum/act/op/A)
	if(!A.answer)
		return OP_OK
	var/desc = A.answer.value
	if(!desc)
		return OP_OK
	var/list/L = teleport_targets()
	if(!L[desc])
		return OP_OK
	rel_set(src, nameof(src.locked), L[desc])
	set_locked_name(desc)
	SStgui.update_uis(src)
	return OP_OK

/datum/tgui_module/teleport_control/proc/ui_act_test_fire(datum/act/op/A)
	station()?.testfire()
	return OP_OK

/datum/tgui_module/teleport_control/proc/ui_act_toggle_on(datum/act/op/A)
	var/mob/user = A.actor
	if(!station())
		return FALSE

	if(station().engaged)
		station().disengage(user)
	else
		station().engage(user)

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
