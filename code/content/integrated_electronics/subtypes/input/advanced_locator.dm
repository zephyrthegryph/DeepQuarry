/obj/item/integrated_circuit/input/advanced_locator
	complexity = 6
	name = "advanced locator"
	desc = "This is needed for certain devices that demand a reference for a target to act upon. This type locates something \
		that is standing in given radius of up to 7 meters"
	extended_desc = "The first pin requires a reference, or string reference for a mob type. This means that it will \
		give refs to nearby objects that are similar to given sample. If this pin is a string, the locator will search for\
		item by matches in name / description / mobtype. If more than one valid object is found nearby, it will choose one of them at \
		random. The second pin is a radius."
	inputs = list(
		"desired type" = IC_PINTYPE_ANY,
		"radius" = IC_PINTYPE_NUMBER,
		"ignore dead" = IC_PINTYPE_BOOLEAN
		)
	outputs = list("located ref")
	activators = list("locate" = IC_PINTYPE_PULSE_IN,"found" = IC_PINTYPE_PULSE_OUT,"not found" = IC_PINTYPE_PULSE_OUT)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	power_draw_per_use = 50
	var/radius = 1

/obj/item/integrated_circuit/input/advanced_locator/on_data_written()
	var/rad = get_pin_data(IC_INPUT, 2)
	if(isnum(rad))
		rad = CLAMP(rad, 0, 7)
		radius = num_or_null(rad)

/obj/item/integrated_circuit/input/advanced_locator/do_work()
	var/datum/integrated_io/I = inputs[1]
	var/datum/integrated_io/O = outputs[1]
	O.set_data(null)
	var/turf/T = get_turf(src)
	var/list/nearby_things = range(radius, T)
	var/list/valid_things = list()
	if(ic_is_ref(I.data))
		var/atom/A = ic_ref_resolve(I.data)
		if(A)
			var/desired_type = A.type
			if(desired_type)
				for(var/atom/thing in nearby_things)
					var/atom/movable/M = thing
					if(ismob(M) && M:stat == DEAD && get_pin_data(IC_INPUT, 3) == TRUE) // Ignore dead mobs if requested.
						continue
					if(thing.is_incorporeal())
						continue
					// Skip invisible & incorporeal players.
					if(ismob(M) && M:invisibility > 0)
						continue
					if(istype(thing, desired_type))
						valid_things.Add(thing)
	else if(istext(I.data))
		if (length(I.data) > 2) // Ensure string is not empty.
			if (copytext(I.data, 1, 2) == "/")
				var/desired_type = text2path(I.data)
				for(var/atom/thing in nearby_things)
					var/atom/movable/M = thing
					if(ismob(M) && M:stat == DEAD && get_pin_data(IC_INPUT, 3) == TRUE) // Ignore dead mobs if requested.
						continue
					if(thing.is_incorporeal())
						continue
					// Skip invisible & incorporeal players.
					if(ismob(M) && M:invisibility > 0)
						continue
					if(istype(thing, desired_type))
						valid_things.Add(thing)
		var/DT = I.data
		for(var/atom/thing in nearby_things)
			if(thing.is_incorporeal())
				continue
			var/atom/movable/M = thing
			if(ismob(M) && M:stat == DEAD && get_pin_data(IC_INPUT, 3) == TRUE) // Ignore dead mobs if requested.
				continue
			// Skip invisible & incorporeal players.
			if(ismob(M) && M:invisibility > 0)
				continue
			if(findtext(addtext(thing.name," ",thing.desc), DT, 1, 0) )
				valid_things.Add(thing)
	if(valid_things.len)
		O.set_data(ic_ref(pick(valid_things)))
		O.push_data()
		activate_pin(2)
	else
		O.push_data()
		activate_pin(3)
