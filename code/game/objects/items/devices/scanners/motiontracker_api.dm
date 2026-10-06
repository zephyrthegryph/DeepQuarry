// The motion tracker system's API (code/game/objects/items/devices/scanners/motiontracker_service.dm declares the system).
//
//   SSmotiontracker.ping(source, hear_chance)                 anything loud enough to echo: raises movable_motiontracker for every listener
//   SSmotiontracker.queue_echo(root_turf, at_turf, count, client)   a listener queues an echo to draw for one client

// We get this from anything in the world that would cause a motion tracker ping
// From sounds to motions, to mob attacks. This then sends a signal to anyone listening.
/datum/system/motiontracker/proc/ping(atom/source, hear_chance = 30)
	if(hide_all) // No pings, admins turned us off
		return
	var/turf/T = get_turf(source)
	if(!isturf(T)) // ONLY call from turfs
		return
	if(!prob(hear_chance))
		return
	if(hear_chance <= 40)
		T = get_step(T,pick(GLOB.cardinal))
		if(!T) // incase...
			return
	// Echo time, we have a turf
	if(queued_echo_turfs[REF(T)]) // Already echoing
		return
	all_pings_round++
	PUBLISH_LEGACY(src, /datum/notice/movable_motiontracker, source, T)

// We get this back from anything that handles the signal, and queues up a turf to draw the echo on
// The logic is in the SIGNAL HANDLER for if it does anything at all with the signal instead of assuming
// everything wants effects drawn, for example the motion tracker item just flicks() and doesn't call this.
/datum/system/motiontracker/proc/queue_echo(turf/Rt,turf/At,echo_count = 1,client)
	if(!Rt || !At || !client)
		return
	var/rfe = REF(At)
	if(!queued_echo_turfs[rfe]) // We only care about the final turf, not the root turf for duping
		queued_echo_turfs[rfe] = list(At, Rt, echo_count, list(client))
		all_echos_round++
	else
		var/list/data = queued_echo_turfs[rfe]
		data[4] += list(client)
