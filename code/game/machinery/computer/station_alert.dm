
/obj/machinery/computer/station_alert
	name = "Station Alert Console"
	desc = "Used to access the station's automated alert system."
	icon_keyboard = "tech_key"
	icon_screen = "alert:0"
	light_color = "#e6ffff"
	circuit = /obj/item/circuitboard/stationalert_engineering
	var/datum/tgui_module/alarm_monitor/alarm_monitor
	var/monitor_type = /datum/tgui_module/alarm_monitor/engineering
	/// TRUE while a major alarm it watches is up: its screen shows the alert (screen_state()).
	var/alerting = FALSE

TRACKED(/obj/machinery/computer/station_alert, alerting)

CAPABILITIES(/obj/machinery/computer/station_alert)
	owns_one(nameof(alarm_monitor), /datum/tgui_module/alarm_monitor, starts = nameof(monitor_type))
	op("station_alert_open_ui", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_open_ui_impl)))
	op("open_ui_impl", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/computer/station_alert/security
	monitor_type = /datum/tgui_module/alarm_monitor/security
	circuit = /obj/item/circuitboard/stationalert_security

/obj/machinery/computer/station_alert/all
	monitor_type = /datum/tgui_module/alarm_monitor/all
	circuit = /obj/item/circuitboard/stationalert_all

/obj/machinery/computer/station_alert/Initialize(mapload)
	. = ..()
	alarm_monitor.register_alarm(src, "update_console_icon")

/// Phase 2: leaves its alarm monitor's listeners.
/obj/machinery/computer/station_alert/lifecycle_dematerialize()
	. = ..()
	alarm_monitor?.unregister_alarm(src)

/obj/machinery/computer/station_alert/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	if(!operable())
		return OP_OK
	tgui_interact(user)
	return OP_OK

/obj/machinery/computer/station_alert/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/machinery/computer/station_alert/ui_redirect(mob/user)
	return alarm_monitor

/// An alarm it watches was raised or cleared: its screen follows through its tracked `alerting` (the look reads it), with the alarm's chime.
/obj/machinery/computer/station_alert/proc/update_console_icon()
	if(!operable())
		return
	var/list/alarms = alarm_monitor ? alarm_monitor.major_alarms() : list()
	set_alerting(!!length(alarms))
	play_sfx(src, alerting ? SFX_EFFECTS_COMP_ALERT_MAJOR : SFX_EFFECTS_COMP_ALERT_CLEAR) // Alarm notifications

/obj/machinery/computer/station_alert/screen_state()
	return alerting ? "alert:2" : icon_screen

/obj/machinery/computer/station_alert/derived()
	. = ..()
	. += drawn_from(nameof(alerting))
