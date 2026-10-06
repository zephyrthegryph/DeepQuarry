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
TRACKED(/obj/machinery/computer/power_monitor, alerting)

/// Checks the sensors for alerts every machine service interval; a change (alerts cleared or detected) redraws it.
/obj/machinery/computer/power_monitor/proc/monitor_step(datum/act/timer/A)
	set_alerting(check_warnings()) // the screen follows (screen_state())
// On creation automatically connects to active sensors. This is delayed to ensure sensors already exist.
// The power monitoring console: its window is its monitor module's (an empty hand on a working console), and it watches its sensors for alerts
// (monitor_step()).
CAPABILITIES(/obj/machinery/computer/power_monitor)
	owns_one(nameof(power_monitor), starts = /datum/tgui_module/power_monitor)
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(monitor_step)))
	op("use", hand(), label("Use"), ungated(), wait(0), when(req_empty_hand()), needs(req_operable()), then(PROC_REF(used)))


/// A hand opens its monitor.
/obj/machinery/computer/power_monitor/proc/used(datum/act/op/A)
	add_fingerprint(A.actor)
	tgui_interact(A.actor)
	return OP_OK

/obj/machinery/computer/power_monitor/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

// Uses dark magic to operate the NanoUI of this computer.
/obj/machinery/computer/power_monitor/ui_redirect(mob/user)
	return power_monitor

// Verifies if any warnings were registered by connected sensors.
/obj/machinery/computer/power_monitor/proc/check_warnings()
	for(var/obj/machinery/power/sensor/S in LAZYCOPY(power_monitor.grid_sensors))
		if(S.check_grid_warning())
			return 1
	return 0

