/datum/tgui_module/atmos_control
	name = "Atmospherics Control"
	/// A private access-check object (owned: built in New).
	var/obj/access
	var/emagged = 0
	var/ui_ref
	/// Alarms this console is limited to (weak: the machines own themselves); empty means every alarm.
	var/list/monitored_alarms

CAPABILITIES(/datum/tgui_module/atmos_control)
	owns_one(nameof(access), /obj)
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

/datum/tgui_module/atmos_control/proc/ui_act_alarm(datum/act/op/A, obj/machinery/alarm/alarm)
	var/mob/user = A.actor
	if(ui_ref && (alarm in alarm_sources()))
		var/datum/tgui_state/TS = generate_state(alarm)
		alarm.tgui_interact(user, parent_ui = ui_ref, custom_state = TS)
	return 1

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
			"danger" = max(alarm.danger_level, alarm.alarm_area_ref().atmosalm),
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

/datum/tgui_module/atmos_control/proc/generate_state(air_alarm)
	var/datum/tgui_state/air_alarm_remote/state = new()
	rel_set(state, nameof(state.atmos_control), src)
	rel_set(state, nameof(state.air_alarm), air_alarm)
	return state

/datum/tgui_state/air_alarm_remote
	var/tmp/datum/tgui_module/atmos_control/atmos_control
	var/tmp/obj/machinery/alarm/air_alarm

/datum/tgui_state/air_alarm_remote/can_use_topic(src_object, mob/user)
	if(!atmos_control().ui_ref)
		qdel(src)
		return STATUS_CLOSE
	if(has_access(user))
		return STATUS_INTERACTIVE
	return STATUS_UPDATE

/datum/tgui_state/air_alarm_remote/proc/has_access(mob/user)
	return user && (isAI(user) || atmos_control().access.allowed(user) || atmos_control().emagged || air_alarm().rcon_setting == RCON_YES || (air_alarm().alarm_area_ref().atmosalm && air_alarm().rcon_setting == RCON_AUTO) || (ACCESS_CE in user.GetAccess()))

/datum/tgui_module/atmos_control/ntos
	ntos = TRUE

/datum/tgui_module/atmos_control/robot
DECLARE_UI_STATE(/datum/tgui_module/atmos_control/robot, GLOB.tgui_self_state)

/// The atmos_control this refers to (a relation view: null once that is deleted).
/datum/tgui_state/air_alarm_remote/proc/atmos_control() as /datum/tgui_module/atmos_control
	return atmos_control

/// The air_alarm this refers to (a relation view: null once that is deleted).
/datum/tgui_state/air_alarm_remote/proc/air_alarm() as /obj/machinery/alarm
	return air_alarm

/// Alarms shown by this UI, rebuilt when it opens.
