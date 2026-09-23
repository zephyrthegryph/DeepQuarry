// POWERNET SENSOR MONITORING CONSOLE
// Connects to powernet sensors and loads data from them. Shows this data to the user.
// Newly supports NanoUI.

/obj/machinery/computer/power_monitor
	name = "Power Monitoring Console"
	desc = "Computer designed to remotely monitor power levels around the station"
	icon_keyboard = "power_key"
	icon_screen = "power_monitor"
	light_color = "#ffcc33"

	//computer stuff
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/powermonitor
	var/alerting = 0
	use_power = USE_POWER_IDLE
	idle_power_usage = 300
	active_power_usage = 300
	var/datum/tgui_module/power_monitor/power_monitor

// Checks the sensors for alerts. If change (alerts cleared or detected) occurs, calls for icon update.
/obj/machinery/computer/power_monitor/process()
	var/alert = check_warnings()
	if(alert != alerting)
		alerting = alert
		update_icon()
	var/list/dependencies = list()
	for(var/obj/machinery/power/sensor/S as anything in power_monitor.grid_sensors)
		if(S.powernet)
			dependencies[S.powernet] = TRUE
	if(length(dependencies))
		var/list/keys = list()
		for(var/datum/powernet/PN as anything in dependencies)
			keys += list(REACT_KEY_POWERNET, REACT_ID(PN), REACT_POWERNET_STATE)
		sleep_until_keys(keys)
		return PROCESS_KILL
// On creation automatically connects to active sensors. This is delayed to ensure sensors already exist.
/obj/machinery/computer/power_monitor/Initialize(mapload)
	. = ..()
	power_monitor = new(src)

/obj/machinery/computer/power_monitor/Destroy()
	qdel(power_monitor)
	power_monitor = null
	return ..()

// On user click opens the UI of this computer.
/obj/machinery/computer/power_monitor/attack_hand(mob/user)
	add_fingerprint(user)

	if(stat & (BROKEN|NOPOWER))
		return
	tgui_interact(user)

/obj/machinery/computer/power_monitor/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

// Uses dark magic to operate the NanoUI of this computer.
/obj/machinery/computer/power_monitor/tgui_interact(mob/user, datum/tgui/ui = null)
	power_monitor.tgui_interact(user, ui)

// Verifies if any warnings were registered by connected sensors.
/obj/machinery/computer/power_monitor/proc/check_warnings()
	for(var/obj/machinery/power/sensor/S in power_monitor.grid_sensors)
		if(S.check_grid_warning())
			return 1
	return 0

/// Audit: a sleeping monitor's alert light must match its sensors.
/obj/machinery/computer/power_monitor/react_sleep_violation()
	if(!asleep_on_keys())
		return null
	if(check_warnings() != alerting)
		return "asleep with a stale alert ([alerting] vs [check_warnings()])"
	return null
