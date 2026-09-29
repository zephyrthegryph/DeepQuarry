/obj/machinery/computer/atmos_alert
	name = "atmospheric alert computer"
	desc = "Used to access the station's atmospheric sensors."
	circuit = /obj/item/circuitboard/atmos_alert
	icon_keyboard = "atmos_key"
	icon_screen = "alert:0"
	light_color = "#e6ffff"

/obj/machinery/computer/atmos_alert/Initialize(mapload)
	. = ..()
	GLOB.atmosphere_alarm.register_alarm(src, /atom/proc/update_icon)

/// Phase 2: leaves the atmosphere alarm's listeners.
/obj/machinery/computer/atmos_alert/lifecycle_dematerialize()
	. = ..()
	GLOB.atmosphere_alarm.unregister_alarm(src)

/obj/machinery/computer/atmos_alert/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/open_ui,
	)
	..()

/obj/machinery/computer/atmos_alert/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

DECLARE_UI(/obj/machinery/computer/atmos_alert, "AtmosAlertConsole")

UI_DATA_REPLACE(/obj/machinery/computer/atmos_alert, "merge:ui_data_obj_machinery_computer_atmos_alert{priority_alarms:list,minor_alarms:list}")

/// The computed part of /obj/machinery/computer/atmos_alert's window data (declared on its UI_DATA row).
/obj/machinery/computer/atmos_alert/proc/ui_data_obj_machinery_computer_atmos_alert(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/list/major_alarms = list()
	var/list/minor_alarms = list()

	for(var/datum/alarm/alarm in GLOB.atmosphere_alarm.major_alarms(get_z(src)))
		major_alarms[++major_alarms.len] = list("name" = sanitize(alarm.alarm_name()), "ref" = "\ref[alarm]")

	for(var/datum/alarm/alarm in GLOB.atmosphere_alarm.minor_alarms(get_z(src)))
		minor_alarms[++minor_alarms.len] = list("name" = sanitize(alarm.alarm_name()), "ref" = "\ref[alarm]")

	data["priority_alarms"] = major_alarms
	data["minor_alarms"] = minor_alarms

	return data

/obj/machinery/computer/atmos_alert/update_icon()
	if(operable())
		var/list/alarms = GLOB.atmosphere_alarm.major_alarms()
		if(alarms.len)
			icon_screen = "alert:2"
			play_sfx(src, SFX_EFFECTS_COMP_ALERT_MAJOR) // Alarm notifications
			om_after(src, 10 SECONDS, TYPE_PROC_REF(/atom, om_playsound), 'sound/effects/comp_alert_major.ogg', 70, 1) // Wait 10 seconds, then play it again
		else
			alarms = GLOB.atmosphere_alarm.minor_alarms()
			if(alarms.len)
				icon_screen = "alert:1"
				play_sfx(src, SFX_EFFECTS_COMP_ALERT_MINOR) // Alarm notifications
				om_after(src, 10 SECONDS, TYPE_PROC_REF(/atom, om_playsound), 'sound/effects/comp_alert_minor.ogg', 50, 1) // Wait 10 seconds, then play it again
			else
				icon_screen = initial(icon_screen)
				play_sfx(src, SFX_EFFECTS_COMP_ALERT_CLEAR) // Alarm notifications
	..()

UI_ACT(/obj/machinery/computer/atmos_alert, "clear", ui_act_clear, UI_ARG_REF("ref", "proc:ui_source_glob_atmosphere_alarm_alarms", /datum/alarm))
UI_ACT_PROC(/obj/machinery/computer/atmos_alert, ui_act_clear)
	var/datum/alarm/alarm = params["ref"]
	if(alarm)
		for(var/datum/alarm_source/alarm_source in alarm.sources)
			var/obj/machinery/alarm/air_alarm = alarm_source.source
			if(istype(air_alarm))
				// I have to leave a note here:
				// Once upon a time, this called air_alarm.Topic() with a custom topic state
				// in order to perform three lines of code. In other words, pure insanity.
				// Whyyyyyyyyyyyyyyyyyyyyyyy.
				air_alarm.atmos_reset()
	. = TRUE
	update_icon()

/// The list the UI_ARG_REF rows resolve refs in.
/obj/machinery/computer/atmos_alert/proc/ui_source_glob_atmosphere_alarm_alarms()
	return GLOB.atmosphere_alarm.alarms
