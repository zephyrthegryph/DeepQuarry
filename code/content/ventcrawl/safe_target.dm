/proc/get_safe_ventcrawl_target(obj/machinery/atmospherics/unary/vent_pump/start_vent)
	if(!start_vent.network || !start_vent.network.normal_members.len)
		return
	var/list/vent_list = list()
	for(var/obj/machinery/atmospherics/unary/vent_pump/vent in start_vent.network.normal_members)
		if(vent == start_vent)
			continue
		if(is_welded(vent))
			continue
		var/area/A = get_area(vent)
		if(A.flag_check(AREA_FORBID_EVENTS))
			continue
		vent_list += vent
	if(!vent_list.len)
		return
	return pick(vent_list)
