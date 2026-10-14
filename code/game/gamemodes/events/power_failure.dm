
/proc/power_failure(announce = 1)
	if(announce)
		GLOB.command_announcement.Announce("Abnormal activity detected in [station_name()]'s powernet. As a precautionary measure, the station's power will be shut off for an indeterminate duration.", "Critical Power Failure", new_sound = ANNOUNCER_MSG_POWER_OFF)

	var/static/list/skipped_areas = list(/area/ai)

	for(var/obj/machinery/power/smes/S in REGISTRY_MEMBERS(REGISTRY_SMES))
		var/area/current_area = get_area(S)
		if((current_area.type in skipped_areas) || !(S.z in using_map.station_levels))
			continue
		S.held_through_outage = list(S.stored_charge(), S.output_attempt, S.input_attempt)
		S.set_stored_charge(0)
		S.set_input_on(0)
		S.set_output_on(0)


	for(var/obj/machinery/power/apc/C in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(!C.is_critical && C.cell && (C.z in using_map.station_levels))
			C.set_cell_charge(0)

/proc/power_restore(announce = 1)
	var/static/list/skipped_areas = list(/area/ai)

	if(announce)
		GLOB.command_announcement.Announce("Power has been restored to [station_name()]. We apologize for the inconvenience.", "Power Systems Nominal", new_sound = ANNOUNCER_MSG_POWER_ON)
	for(var/obj/machinery/power/apc/C in REGISTRY_MEMBERS(REGISTRY_APCS))
		if(C.cell && (C.z in using_map.station_levels))
			C.set_cell_charge(C.cell.maxcharge)
	for(var/obj/machinery/power/smes/S in REGISTRY_MEMBERS(REGISTRY_SMES))
		var/area/current_area = get_area(S)
		if((current_area.type in skipped_areas) || isNotStationLevel(S.z))
			continue
		var/list/held = S.held_through_outage
		if(!held)
			continue
		S.held_through_outage = null
		S.set_stored_charge(held[1])
		S.set_output_attempt(held[2])
		S.set_input_attempt(held[3])

/proc/power_restore_quick(announce = 1)

	if(announce)
		GLOB.command_announcement.Announce("All SMESs on [station_name()] have been recharged. We apologize for the inconvenience.", "Power Systems Nominal", new_sound = ANNOUNCER_MSG_POWER_ON)
	for(var/obj/machinery/power/smes/S in REGISTRY_MEMBERS(REGISTRY_SMES))
		if(isNotStationLevel(S.z))
			continue
		S.set_stored_charge(S.capacity)
		S.set_output_level(S.output_level_max)
		S.set_output_attempt(1)
		S.set_input_attempt(1)
