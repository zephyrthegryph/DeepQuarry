
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
	owns_one(nameof(alarm_monitor), /datum/tgui_module/alarm_monitor)

/obj/machinery/computer/station_alert/security
	monitor_type = /datum/tgui_module/alarm_monitor/security
	circuit = /obj/item/circuitboard/stationalert_security

/obj/machinery/computer/station_alert/all
	monitor_type = /datum/tgui_module/alarm_monitor/all
	circuit = /obj/item/circuitboard/stationalert_all

/obj/machinery/computer/station_alert/Initialize(mapload)
	rel_set(src, nameof(alarm_monitor), new monitor_type(src))
	alarm_monitor.register_alarm(src, "update_console_icon")
	. = ..()


/// Phase 2: leaves its alarm monitor's listeners.
/obj/machinery/computer/station_alert/lifecycle_dematerialize()
	. = ..()
	alarm_monitor?.unregister_alarm(src)

/obj/machinery/computer/station_alert/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/station_alert_open_ui,
	)
	// Old attack_ai: the same body as the hand's.
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Use", PROC_REF(interaction_open_ui_impl)))
	..()

/datum/interaction/machine_hand/ungated/station_alert_open_ui
	id = "station_alert_open_ui"
	name = "Use"
	effect = /obj/machinery/computer/station_alert/proc/interaction_open_ui_impl

/obj/machinery/computer/station_alert/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(!operable())
		return TRUE
	tgui_interact(user)
	return TRUE

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
