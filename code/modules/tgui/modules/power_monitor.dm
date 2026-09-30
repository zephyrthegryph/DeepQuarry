/datum/tgui_module/power_monitor
	name = "Power monitor"
	tgui_id = "PowerMonitor"
	var/list/grid_sensors
	var/active_sensor = null	//name_tag of the currently selected sensor

/datum/tgui_module/power_monitor/New()
	. = ..()
	refresh_sensors()

UI_DATA_REPLACE(/datum/tgui_module/power_monitor, "merge:ui_data_datum_tgui_module_power_monitor{all_sensors:list,focus:unknown}")

/// The computed part of /datum/tgui_module/power_monitor's window data (declared on its UI_DATA row).
/datum/tgui_module/power_monitor/proc/ui_data_datum_tgui_module_power_monitor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/sensors = list()
	// Focus: If it remains null if no sensor is selected and UI will display sensor list, otherwise it will display sensor reading.
	var/obj/machinery/power/sensor/focus = null

	var/z = get_z(user)
	var/list/map_levels = using_map.get_map_levels(z)

	// Build list of data from sensor readings.
	for(var/obj/machinery/power/sensor/S in LAZYCOPY(grid_sensors))
		if(!(S.z in map_levels))
			continue
		sensors.Add(list(list(
			"name" = S.name_tag,
			"alarm" = S.check_grid_warning()
		)))
		if(S.name_tag == active_sensor)
			focus = S

	data["all_sensors"] = sensors
	if(focus)
		data["focus"] = focus.tgui_data(user)
	else
		data["focus"] = null

	return data

UI_ACT(/datum/tgui_module/power_monitor, "clear", ui_act_clear)
UI_ACT_PROC(/datum/tgui_module/power_monitor, ui_act_clear)
	active_sensor = null
	. = TRUE

UI_ACT(/datum/tgui_module/power_monitor, "refresh", ui_act_refresh)
UI_ACT_PROC(/datum/tgui_module/power_monitor, ui_act_refresh)
	refresh_sensors()
	. = TRUE

UI_ACT(/datum/tgui_module/power_monitor, "setsensor", ui_act_setsensor, UI_ARG_TEXT("id"))
UI_ACT_PROC(/datum/tgui_module/power_monitor, ui_act_setsensor)
	active_sensor = params["id"]
	. = TRUE

/datum/tgui_module/power_monitor/proc/has_alarm()
	for(var/obj/machinery/power/sensor/S in LAZYCOPY(grid_sensors))
		if(S.check_grid_warning())
			return TRUE
	return FALSE

/datum/tgui_module/power_monitor/proc/refresh_sensors()
	rel_clear(src, nameof(grid_sensors))

	// Handle ultranested programs
	var/turf/T = get_turf(tgui_host())

	var/list/levels = list()
	if(!T) // Safety check
		return
	if(T)
		levels += using_map.get_map_levels(T.z, FALSE)
	for(var/obj/machinery/power/sensor/S in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		if(QDELETED(S))
			continue
		if(T && (S.loc.z == T.z) || (S.loc.z in levels) || (S.long_range)) // Consoles have range on their Z-Level. Sensors with long_range var will work between Z levels.
			if(S.name_tag == "#UNKN#") // Default name. Shouldn't happen!
				WARNING("Powernet sensor with unset ID Tag! [S.x]X [S.y]Y [S.z]Z")
			else
				rel_add(src, nameof(grid_sensors), S)

/datum/tgui_module/power_monitor/ntos
	ntos = TRUE

// Subtype for self_state
/datum/tgui_module/power_monitor/robot
DECLARE_UI_STATE(/datum/tgui_module/power_monitor/robot, GLOB.tgui_self_state)

/// Sensors on the grid, rebuilt by refresh_sensors().
