/mob/living/silicon
	var/register_alarms = 1
	var/datum/tgui_module/alarm_monitor/all/robot/alarm_monitor
	var/datum/tgui_module/atmos_control/robot/atmos_control
	var/datum/tgui_module/crew_manifest/robot/crew_manifest
	var/datum/tgui_module/crew_monitor/robot/crew_monitor
	var/datum/tgui_module/law_manager/robot/law_manager
	var/datum/tgui_module/power_monitor/robot/power_monitor
	var/datum/tgui_module/rcon/robot/rcon

/mob/living/silicon
	var/list/silicon_subsystems = list( // ALLOW(instance_list): c: interned per subtype by shared_type_list() in Initialize(), so instances share one list
		/mob/living/silicon/proc/subsystem_alarm_monitor,
		/mob/living/silicon/proc/subsystem_crew_manifest,
		/mob/living/silicon/proc/subsystem_law_manager
	)

/mob/living/silicon/ai
	silicon_subsystems = list(
		/mob/living/silicon/proc/subsystem_alarm_monitor,
		/mob/living/silicon/proc/subsystem_atmos_control,
		/mob/living/silicon/proc/subsystem_crew_manifest,
		/mob/living/silicon/proc/subsystem_crew_monitor,
		/mob/living/silicon/proc/subsystem_law_manager,
		/mob/living/silicon/proc/subsystem_power_monitor,
		/mob/living/silicon/proc/subsystem_rcon
	)

/mob/living/silicon/robot/syndicate
	register_alarms = 0
	silicon_subsystems = list(/mob/living/silicon/proc/subsystem_law_manager)
	idcard_type = /obj/item/card/id/syndicate

/mob/living/silicon/proc/init_subsystems()
	rel_set(src, nameof(alarm_monitor), new /datum/tgui_module/alarm_monitor/all/robot(src))
	rel_set(src, nameof(atmos_control), new /datum/tgui_module/atmos_control/robot(src))
	rel_set(src, nameof(crew_manifest), new /datum/tgui_module/crew_manifest/robot(src))
	rel_set(src, nameof(crew_monitor), new /datum/tgui_module/crew_monitor/robot(src))
	rel_set(src, nameof(law_manager), new /datum/tgui_module/law_manager/robot(src))
	rel_set(src, nameof(power_monitor), new /datum/tgui_module/power_monitor/robot(src))
	rel_set(src, nameof(rcon), new /datum/tgui_module/rcon/robot(src))

	if(!register_alarms)
		return

	for(var/datum/alarm_handler/AH in all_alarm_handlers())
		AH.register_alarm(src, /mob/living/silicon/proc/receive_alarm)
		rel_add(src, nameof(queued_alarms), new /datum/silicon_alarm_queue(AH.category), "[AH.type]")	// Makes sure alarms remain listed in consistent order

/********************
*	Alarm Monitor	*
********************/
/mob/living/silicon/proc/subsystem_alarm_monitor()
	set name = "Alarm Monitor"
	set category = VERB_CAT_ABILITIES_SILICON

	alarm_monitor.tgui_interact(src)

/// The "show alerts" link of a silicon's own chat (the op is declared on /mob, code/modules/mob/mob_defines.dm).
/mob/living/silicon/proc/topic_showalerts(datum/act/op/A)
	subsystem_alarm_monitor()

/********************
*	Atmos Control	*
********************/
/mob/living/silicon/proc/subsystem_atmos_control()
	set category = VERB_CAT_ABILITIES_SILICON
	set name = "Atmospherics Control"

	atmos_control.tgui_interact(src)

/********************
*	Crew Manifest	*
********************/
/mob/living/silicon/proc/subsystem_crew_manifest()
	set category = VERB_CAT_ABILITIES_SILICON
	set name = "Crew Manifest"

	crew_manifest.tgui_interact(src)

/********************
*	Crew Monitor	*
********************/
/mob/living/silicon/proc/subsystem_crew_monitor()
	set category = VERB_CAT_ABILITIES_SILICON
	set name = "Crew Monitor"

	crew_monitor.tgui_interact(src)

/****************
*	Law Manager	*
****************/
/mob/living/silicon/proc/subsystem_law_manager()
	set name = "Law Manager"
	set category = VERB_CAT_ABILITIES_SILICON

	law_manager.tgui_interact(src)

/********************
*	Power Monitor	*
********************/
/mob/living/silicon/proc/subsystem_power_monitor()
	set category = VERB_CAT_ABILITIES_SILICON
	set name = "Power Monitor"

	power_monitor.tgui_interact(src)

/************
*	RCON	*
************/
/mob/living/silicon/proc/subsystem_rcon()
	set category = VERB_CAT_ABILITIES_SILICON
	set name = "RCON"

	rcon.tgui_interact(src)

/mob/living/silicon/robot
	var/datum/tgui_module/robot_ui_decals/decal_control

/mob/living/silicon/robot/init_subsystems()
	..()
	rel_set(src, nameof(decal_control), new /datum/tgui_module/robot_ui_decals(src))

