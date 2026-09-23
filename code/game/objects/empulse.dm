// Uncomment this define to check for possible lengthy processing of emp_act()s.
// If emp_act() takes more than defined deciseconds (1/10 seconds) an admin message and log is created.
// I do not recommend having this uncommented on main server, it probably causes a bit more lag, espicially with larger EMPs.

// # define EMPDEBUG 10

/proc/empulse(turf/epicenter, first_range, second_range, third_range, fourth_range, log=0)
	if(!epicenter)
		return

	if(!istype(epicenter, /turf))
		epicenter = get_turf(epicenter.loc)

	if(log)
		message_admins("EMP with size ([first_range], [second_range], [third_range], [fourth_range]) in area [epicenter.loc.name] ")
		log_game("EMP with size ([first_range], [second_range], [third_range], [fourth_range]) in area [epicenter.loc.name] ")

	if(first_range > 1)
		new /obj/effect/temp_visual/emp/pulse(epicenter)

	if(first_range > second_range)
		second_range = first_range
	if(second_range > third_range)
		third_range = second_range
	if(third_range > fourth_range)
		fourth_range = third_range

	// One sound for the pulse; playsound already reaches every listener in range (Q6).
	if(locate(/mob) in range(first_range, epicenter))
		playsound(epicenter, 'sound/effects/EMPulse.ogg', 100, TRUE)

	for(var/list/hit as anything in emp_falloff_turfs(epicenter, first_range, second_range, third_range, fourth_range))
		var/turf/T = hit[1]
		#ifdef EMPDEBUG
		var/time = world.timeofday
		#endif
		T.emp_act(hit[2])
		#ifdef EMPDEBUG
		if((world.timeofday - time) >= EMPDEBUG)
			log_and_message_admins("EMPDEBUG: [T.name] - [T.type] - took [world.timeofday - time]ds to process emp_act()!")
		#endif
	return TRUE

/// The turfs an EMP reaches and the severity each gets, as list(list(turf, severity), ...).
/// Rust computes the falloff bands (rays from the epicentre, so Chebyshev distance,
/// clipped at the map edge); the coin flip on each band's edge ring happens here.
/// Ranges must be non-decreasing.
/proc/emp_falloff_turfs(turf/epicenter, first_range, second_range, third_range, fourth_range)
	. = list()
	var/list/falloff = vg_emp_falloff(epicenter.x, epicenter.y, epicenter.z, world.maxx, world.maxy, world.maxz, list(first_range, second_range, third_range, fourth_range))
	if(!islist(falloff) || length(falloff) < 5)
		return
	var/list/turfs = block(locate(falloff[1], falloff[2], epicenter.z), locate(falloff[3], falloff[4], epicenter.z))
	if(length(turfs) != length(falloff) - 4)
		CRASH("emp_falloff returned [length(falloff) - 4] severities for [length(turfs)] turfs")
	for(var/i in 1 to length(turfs))
		var/severity = falloff[i + 4]
		if(severity <= 0)
			continue
		var/band = round(severity)
		if(severity != band)
			severity = prob(50) ? band : band + 1
		. += list(list(turfs[i], severity))
