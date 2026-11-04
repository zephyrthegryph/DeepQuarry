/obj/item/integrated_circuit/input/examiner
	name = "examiner"
	desc = "It's a little machine vision system. It can return the name, description, distance,\
	relative coordinates, total amount of reagents, and maximum amount of reagents of the referenced object."
	icon_state = "video_camera"
	complexity = 6
	inputs = list(
		"target" = IC_PINTYPE_REF,
		"ignore dead" = IC_PINTYPE_BOOLEAN
		)
	outputs = list(
		"name"	            	= IC_PINTYPE_STRING,
		"description"       	= IC_PINTYPE_STRING,
		"X"         			= IC_PINTYPE_NUMBER,
		"Y"			            = IC_PINTYPE_NUMBER,
		"distance"			    = IC_PINTYPE_NUMBER,
		"max reagents"			= IC_PINTYPE_NUMBER,
		"amount of reagents"    = IC_PINTYPE_NUMBER,
		"is living"          	= IC_PINTYPE_BOOLEAN
	)
	activators = list("scan" = IC_PINTYPE_PULSE_IN, "on scanned" = IC_PINTYPE_PULSE_OUT, "not scanned" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_RESEARCH
	power_draw_per_use = 40

/obj/item/integrated_circuit/input/examiner/do_work()
	var/atom/movable/H = get_pin_data_as_type(IC_INPUT, 1, /atom/movable)
	var/turf/T = get_turf(src)
	if(!istype(H)) //Invalid input
		return
	if(get_pin_data(IC_INPUT, 2) == TRUE) // Ignore mob, if ignore dead is enabled.
		if(ismob(H) && H:stat == DEAD)
			return
	if(H in view(T)) // This is a camera. It can't examine thngs,that it can't see.
		set_pin_data(IC_OUTPUT, 1, H.name)
		set_pin_data(IC_OUTPUT, 2, H.desc)
		set_pin_data(IC_OUTPUT, 3, H.x-T.x)
		set_pin_data(IC_OUTPUT, 4, H.y-T.y)
		set_pin_data(IC_OUTPUT, 5, sqrt((H.x-T.x)*(H.x-T.x)+ (H.y-T.y)*(H.y-T.y)))
		var/mr = 0
		var/tr = 0
		if(H.reagents)
			mr = H.reagents.maximum_volume
			tr = H.reagents.total_volume
		set_pin_data(IC_OUTPUT, 6, mr)
		set_pin_data(IC_OUTPUT, 7, tr)
		var/mob/scanned_mob = H
		set_pin_data(IC_OUTPUT, 8, ismob(scanned_mob) && scanned_mob.stat != DEAD)
		push_data()
		activate_pin(2)
	else
		activate_pin(3)
