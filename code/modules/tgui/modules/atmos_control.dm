/datum/tgui_module/atmos_control
	name = "Atmospherics Control"
	/// A private access-check object (owned: built in New).
	var/obj/access
	var/emagged = 0
	var/ui_ref
	/// Alarms this console is limited to (weak: the machines own themselves); empty means every alarm.
	var/list/monitored_alarms
	/// The panel of the alarm last opened from it (/datum/air_alarm_remote).
	var/datum/air_alarm_remote/remote_panel

CAPABILITIES(/datum/tgui_module/atmos_control)
	owns_one(nameof(access), /obj)
	owns_one(nameof(remote_panel), /datum/air_alarm_remote)
	interface("AtmosControl")
	op("alarm", ui_act("alarm", arg("alarm", schema_ref(/obj/machinery/alarm))), then(PROC_REF(ui_act_alarm)))
	op("setZLevel", ui_act("setZLevel", arg("mapZLevel", num())), then(PROC_REF(ui_act_setzlevel)))

/datum/tgui_module/atmos_control/New(atmos_computer, req_access, req_one_access, monitored_alarm_ids)
	..()
	rel_set(src, nameof(access), new /obj())
	access.req_access = req_access
	access.req_one_access = req_one_access

	if(monitored_alarm_ids)
		var/list/found = list()
		for(var/obj/machinery/alarm/alarm in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(alarm.alarm_id && (alarm.alarm_id in monitored_alarm_ids))
				found += alarm
		// machines may not yet be ordered at this point
		for(var/obj/machinery/alarm/alarm as anything in dd_sortedObjectList(found))
			rel_add(src, nameof(monitored_alarms), alarm)

/// The alarms this monitor shows (its own list, else every machine), for the UI's alarm refs.
/datum/tgui_module/atmos_control/proc/alarm_sources()
	return LAZYLEN(monitored_alarms) ? LAZYCOPY(monitored_alarms) : REGISTRY_MEMBERS(REGISTRY_MACHINES)

/// The alarm button: the alarm's window opens as this console's panel of it (its buttons go to the alarm, past its lock for whoever the console
/// lets in).
/datum/tgui_module/atmos_control/proc/ui_act_alarm(datum/act/op/A, obj/machinery/alarm/alarm)
	if(!(alarm in alarm_sources()))
		return OP_OK
	rel_set(src, nameof(remote_panel), new /datum/air_alarm_remote(src, alarm))
	remote_panel.tgui_interact(A.actor, parent_ui = ui_ref)
	return OP_OK

/datum/tgui_module/atmos_control/proc/ui_act_setzlevel(datum/act/op/A, mapZLevel)
	var/datum/tgui/ui = SStgui.get_open_ui(A.actor, src)
	ui?.set_map_z_level(mapZLevel)
	return TRUE

/datum/tgui_module/atmos_control/ui_assets(mob/user)
	. = ..()
	. += get_asset_datum(/datum/asset/simple/holo_nanomap)

/datum/tgui_module/atmos_control/ui_opening(mob/user, datum/tgui/ui)
	..()
	ui_ref = ui
	ui.set_autoupdate(TRUE)

/datum/tgui_module/atmos_control/tgui_static_data(mob/user)
	. = ..()

	var/z = get_z(user)
	var/list/map_levels = using_map.get_visible_map_levels(z)

	// TODO: Move these to a cache, similar to cameras
	var/alarms[0]
	for(var/obj/machinery/alarm/alarm in (LAZYLEN(monitored_alarms) ? LAZYCOPY(monitored_alarms) : REGISTRY_MEMBERS(REGISTRY_MACHINES)))
		if(!LAZYLEN(monitored_alarms) && alarm.alarms_hidden)
			continue
		if(!(alarm.z in map_levels))
			continue
		alarms[++alarms.len] = list(
			"name" = sanitize(alarm.name),
			"ref"= "\ref[alarm]",
			"danger" = max(alarm.danger_level, alarm.alarm_area?.atmosalm),
			"x" = alarm.x,
			"y" = alarm.y,
			"z" = alarm.z)
	.["alarms"] = alarms

/datum/tgui_module/atmos_control/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	var/z = get_z(user)
	var/list/map_levels = using_map.get_visible_map_levels(z)
	data["map_levels"] = map_levels

	return data

/datum/tgui_module/atmos_control/tgui_close()
	. = ..()
	ui_ref = null

/datum/tgui_module/atmos_control/ntos
	ntos = TRUE

/datum/tgui_module/atmos_control/robot
DECLARE_UI_STATE(/datum/tgui_module/atmos_control/robot, GLOB.tgui_self_state)
