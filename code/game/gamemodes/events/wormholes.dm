/proc/wormhole_event(set_duration = 5 MINUTES, wormhole_duration_modifier = 1)
	// Deferred: collecting the turfs walks the world. The global owner: a round event.
	after(null, 0, GLOBAL_PROC_REF(wormhole_event_start), with = list(set_duration, wormhole_duration_modifier))

/proc/wormhole_event_start(set_duration, wormhole_duration_modifier)
// Only allowing these to go to the station
	var/list/pick_turfs = list()
	var/list/exits = list()
	var/list/Z_choices = list()

	Z_choices |= using_map.get_map_levels(1, FALSE)
	Z_choices -= global.using_map.sealed_levels
	for(var/turf/simulated/floor/T in world)
		var/area/A = T.loc
		if(T.z in Z_choices)
			if(!T.block_tele)
				pick_turfs += T
			if(A.flag_check(AREA_FORBID_EVENTS)) // No spawning in dorms
				continue
	// Chance to end up in a belly. Fun (:
	for(var/mob/living/mob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(mob.can_be_drop_pred && isfloor(mob.loc))
			var/turf/simulated/floor/T = get_turf(mob.loc)
			if(!T.block_tele)
				if(mob.vore_selected)
					exits += mob.vore_selected
				else if(length(mob.vore_organs))
					exits += pick(mob.vore_organs)

	exits |= pick_turfs

	if(pick_turfs.len)

		var/wormhole_max_duration = round((5 MINUTES) * wormhole_duration_modifier)
		var/wormhole_min_duration = round((30 SECONDS) * wormhole_duration_modifier)

		//All ready. Announce that bad juju is afoot.
		GLOB.command_announcement.Announce("Space-time anomalies detected on the station. There is no additional data.", "Anomaly Alert", new_sound = ANNOUNCER_MSG_SPACETIME_ANOMS)

		//prob(20) can be approximated to 1 wormhole every 5 turfs!
		//admittedly less random but totally worth it >_<
		var/event_duration = set_duration
		var/number_of_selections = round(pick_turfs.len/(4 * (Z_choices.len + 1)))+1	//+1 to avoid division by zero!
		var/sleep_duration = 0.2 SECONDS
		var/ends_at = world.time + event_duration	//the time by which the event should have ended

		var/increment =	max(1,round(number_of_selections/50))

		var/index = 1
		var/delay = 0
		for(var/I = 1 to number_of_selections)

			//we've run into overtime. End the event
			if( LEFT_UNTIL(world, ends_at, CLOCK_WORLD) < delay )
				return
			if( !pick_turfs.len )
				return

			//loop it round
			index += increment
			index %= pick_turfs.len
			index++

			//get our enter and exit locations
			var/turf/simulated/floor/enter = pick_turfs[index]
			pick_turfs -= enter							//remove it from pickable turfs list
			if( !enter || !istype(enter) )	continue	//sanity

			var/atom/exit = pick(exits)
			if( !exit || !istype(exit) )	continue	//sanity

			after(null, delay, GLOBAL_PROC_REF(create_wormhole), with = list(enter, exit, wormhole_min_duration, wormhole_max_duration))
			delay += sleep_duration

//maybe this proc can even be used as an admin tool for teleporting players without ruining immulsions?
/proc/create_wormhole(turf/enter as turf, atom/exit, min_duration = 30 SECONDS, max_duration = 60 SECONDS)
	var/obj/effect/portal/P = new /obj/effect/portal( enter )
	rel_set(P, nameof(P.target), exit)
	P.creator = null
	P.icon = 'icons/obj/objects.dmi'
	P.failchance = 0
	P.icon_state = "bhole3" // Better icon as well
	P.name = "wormhole"
	P.event = TRUE
	P.expire(rand(min_duration,max_duration))
