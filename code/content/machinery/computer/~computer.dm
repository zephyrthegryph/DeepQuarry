//Various overrides to make Eris sprites look nicer
/obj/machinery/computer/power_monitor
	icon_keyboard = "power_key"
	icon_screen = "power_monitor"

/// The screen: a warning while a sensor alerts (a broken console draws its broken screen in the base draw).
/obj/machinery/computer/power_monitor/screen_state()
	return alerting ? "power_monitor_warn" : "power_monitor"

/obj/machinery/computer/rcon
	icon_keyboard = "power_key"
	icon_screen = "ai-fixer"
