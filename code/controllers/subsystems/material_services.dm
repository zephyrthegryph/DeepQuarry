/// Coalesced, resumable exposure work. A station can contain tens of thousands
/// of assemblies; they must not each put an unbudgeted callback on SStimer.
SUBSYSTEM_DEF(material_services)
	name = "Material exposure"
	flags = SS_KEEP_TIMING | SS_NO_INIT
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	priority = FIRE_PRIORITY_OBJ
	wait = 1 SECOND
	var/list/scheduled = list()
	var/list/currentrun

/datum/controller/subsystem/material_services/fire(resumed)
	if(!resumed)
		currentrun = scheduled
		scheduled = list()
	while(length(currentrun))
		var/datum/material_service/service = currentrun[length(currentrun)]
		currentrun.len--
		if(QDELETED(service))
			continue
		if(service.next_update <= world.time)
			service.timer = FALSE
			service.advance()
		else
			scheduled += service
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/material_services/stat_entry(msg)
	msg += " P:[length(scheduled)]"
	return ..()
