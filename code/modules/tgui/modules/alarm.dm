/datum/tgui_module/alarm_monitor
	name = "Alarm monitor"
	var/list_cameras = 0						// Whether or not to list camera references. A future goal would be to merge this with the enginering/security camera console. Currently really only for AI-use.

/// The particular list of alarm handlers this alarm monitor should present to the user. The handlers
/// are global singletons, so each subtype names them per call instead of holding references.
/datum/tgui_module/alarm_monitor/proc/alarm_handlers()
	return list()

/datum/tgui_module/alarm_monitor/all
/datum/tgui_module/alarm_monitor/all/alarm_handlers()
	return all_alarm_handlers()

// Subtype for glasses_state
/datum/tgui_module/alarm_monitor/all/glasses
CAPABILITIES(/datum/tgui_module/alarm_monitor/all/glasses)
	interface("StationAlertConsole", state = nameof(GLOB.tgui_glasses_state))

/datum/tgui_module/alarm_monitor/all/robot
CAPABILITIES(/datum/tgui_module/alarm_monitor/all/robot)
	interface("StationAlertConsole", state = nameof(GLOB.tgui_self_state))

/datum/tgui_module/alarm_monitor/engineering
/datum/tgui_module/alarm_monitor/engineering/alarm_handlers()
	return list(GLOB.atmosphere_alarm, GLOB.fire_alarm, GLOB.power_alarm)

// Subtype for glasses_state
/datum/tgui_module/alarm_monitor/engineering/glasses
CAPABILITIES(/datum/tgui_module/alarm_monitor/engineering/glasses)
	interface("StationAlertConsole", state = nameof(GLOB.tgui_glasses_state))

// Subtype for nif_state
/datum/tgui_module/alarm_monitor/engineering/nif
CAPABILITIES(/datum/tgui_module/alarm_monitor/engineering/nif)
	interface("StationAlertConsole", state = nameof(GLOB.tgui_nif_state))

// Subtype for NTOS
/datum/tgui_module/alarm_monitor/engineering/ntos
	ntos = TRUE

/datum/tgui_module/alarm_monitor/security
/datum/tgui_module/alarm_monitor/security/alarm_handlers()
	return list(GLOB.camera_alarm, GLOB.motion_alarm)

// Subtype for glasses_state
/datum/tgui_module/alarm_monitor/security/glasses
CAPABILITIES(/datum/tgui_module/alarm_monitor/security/glasses)
	interface("StationAlertConsole", state = nameof(GLOB.tgui_glasses_state))

// Subtype for NTOS
/datum/tgui_module/alarm_monitor/security/ntos
	ntos = TRUE

/datum/tgui_module/alarm_monitor/proc/register_alarm(object, procName)
	for(var/datum/alarm_handler/AH in alarm_handlers())
		AH.register_alarm(object, procName)

/datum/tgui_module/alarm_monitor/proc/unregister_alarm(object)
	for(var/datum/alarm_handler/AH in alarm_handlers())
		AH.unregister_alarm(object)

/datum/tgui_module/alarm_monitor/proc/all_alarms()
	var/z = get_z(tgui_host())
	var/list/all_alarms = new()
	for(var/datum/alarm_handler/AH in alarm_handlers())
		all_alarms += AH.visible_alarms(z)

	return all_alarms

/datum/tgui_module/alarm_monitor/proc/major_alarms()
	var/z = get_z(tgui_host())
	var/list/all_alarms = new()
	for(var/datum/alarm_handler/AH in alarm_handlers())
		all_alarms += AH.major_alarms(z)

	return all_alarms

// Modified version of above proc that uses slightly less resources, returns 1 if there is a major alarm, 0 otherwise.
/datum/tgui_module/alarm_monitor/proc/has_major_alarms()
	var/z = get_z(tgui_host())
	for(var/datum/alarm_handler/AH in alarm_handlers())
		if(AH.has_major_alarms(z))
			return 1

	return 0

/datum/tgui_module/alarm_monitor/proc/minor_alarms()
	var/z = get_z(tgui_host())
	var/list/all_alarms = new()
	for(var/datum/alarm_handler/AH in alarm_handlers())
		all_alarms += AH.minor_alarms(z)

	return all_alarms

/// Only an AI works the buttons (silently: anyone else is just not answered).
/datum/tgui_module/alarm_monitor/proc/ui_gate(datum/act/op/A)
	return isAI(A.actor)

CAPABILITIES(/datum/tgui_module/alarm_monitor)
	interface("StationAlertConsole")
	op("switchTo", ui_act("switchTo", arg("camera", schema_ref(/obj/machinery/camera))), needs(req_bool(PROC_REF(ui_gate), silent = TRUE)), then(PROC_REF(ui_act_switchto)))

/datum/tgui_module/alarm_monitor/proc/ui_act_switchto(datum/act/op/A, camera)
	var/mob/user = A.actor
	var/obj/machinery/camera/C = camera
	if(!C)
		return

	user.switch_to_camera(C)
	return 1

/datum/tgui_module/alarm_monitor/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()

	var/categories[0]
	var/z = get_z(tgui_host())
	for(var/datum/alarm_handler/AH in alarm_handlers())
		categories[++categories.len] = list("category" = AH.category, "alarms" = list())
		for(var/datum/alarm/A2 in AH.visible_alarms(z))
			var/cameras[0]
			var/lost_sources[0]

			if(isAI(user))
				for(var/obj/machinery/camera/C in A2.cameras())
					cameras[++cameras.len] = C.tgui_structure()
			for(var/datum/alarm_source/AS in A2.sources)
				if(!AS.source)
					lost_sources[++lost_sources.len] = AS.source_name

			categories[categories.len]["alarms"] += list(list(
					"name" = "[A2.alarm_name()]" + "[A2.max_severity() > 1 ? "(MAJOR)" : ""]",
					"origin_lost" = A2.origin() == null,
					"has_cameras" = cameras.len,
					"cameras" = cameras,
					"lost_sources" = lost_sources.len ? sanitize(english_list(lost_sources, nothing_text = "", and_text = ", ")) : ""))
	data["categories"] = categories

	return data

// The global alarm handler singletons.
