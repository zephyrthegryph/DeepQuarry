/datum/event/meteor_strike
	announceWhen = 1
	var/tmp/turf/strike_target

/datum/event/meteor_strike/setup()
	startWhen = rand(8,15)
	if(LAZYLEN(using_map.meteor_strike_areas))
		rel_set(src, nameof(strike_target), pick(get_area_turfs(pick(using_map.meteor_strike_areas))))

	if(!strike_target())
		kill()

/datum/event/meteor_strike/announce()
	GLOB.command_announcement.Announce("A meteoroid has been detected entering the atmosphere on a trajectory that will terminate near the surface facilty. Brace for impact.", "NanoTrasen Orbital Monitoring")

/datum/event/meteor_strike/start()
	new /obj/effect/meteor_falling(strike_target())

/// Accessor for the strike_target var.
/datum/event/meteor_strike/proc/strike_target() as /turf
	return strike_target

CAPABILITIES(/datum/event/meteor_strike)
	ref_one(nameof(strike_target))
