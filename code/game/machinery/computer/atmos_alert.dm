/obj/machinery/computer/atmos_alert
	name = "atmospheric alert computer"
	desc = "Used to access the station's atmospheric sensors."
	circuit = /obj/item/circuitboard/atmos_alert
	icon_keyboard = "atmos_key"
	icon_screen = "alert:0"
	light_color = "#e6ffff"

/// The console listens to the station's atmosphere alarms once it is placed.
/obj/machinery/computer/atmos_alert/proc/listen_alarms(datum/act/timer/A)
	GLOB.atmosphere_alarm.register_alarm(src, TYPE_PROC_REF(/obj/machinery/computer/atmos_alert, alarms_changed))

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

CAPABILITIES(/obj/machinery/computer/atmos_alert)
	after_init(0, then(PROC_REF(listen_alarms)))
	interface("AtmosAlertConsole")
	op("clear", ui_act("clear", arg("ref")), then(PROC_REF(ui_act_clear)))

/obj/machinery/computer/atmos_alert/ui_data(datum/act/eval/A)
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

/// The station's atmosphere alarms changed: the screen shows the worst level, and the console sounds it (again ten seconds later for an alarm).
/obj/machinery/computer/atmos_alert/proc/alarms_changed()
	if(!operable())
		return
	var/level = length(GLOB.atmosphere_alarm.major_alarms()) ? 2 : (length(GLOB.atmosphere_alarm.minor_alarms()) ? 1 : 0)
	icon_screen = level ? "alert:[level]" : initial(icon_screen)
	switch(level)
		if(2)
			play_sfx(src, SFX_EFFECTS_COMP_ALERT_MAJOR)
			after(src, 10 SECONDS, TYPE_PROC_REF(/atom, om_playsound), key = "alert_repeat", with = list('sound/effects/comp_alert_major.ogg', 70, 1))
		if(1)
			play_sfx(src, SFX_EFFECTS_COMP_ALERT_MINOR)
			after(src, 10 SECONDS, TYPE_PROC_REF(/atom, om_playsound), key = "alert_repeat", with = list('sound/effects/comp_alert_minor.ogg', 50, 1))
		else
			play_sfx(src, SFX_EFFECTS_COMP_ALERT_CLEAR)
	changed(src)

/obj/machinery/computer/atmos_alert/proc/ui_act_clear(datum/act/op/A, ref)
	var/datum/alarm/alarm = ui_ref(ref, GLOB.atmosphere_alarm.alarms, /datum/alarm)
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
