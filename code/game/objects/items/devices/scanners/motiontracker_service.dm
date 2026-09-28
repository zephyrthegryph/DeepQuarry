// The motion tracker world service (fold wave F3; was SSmotiontracker). ping() raises
// COMSIG_MOVABLE_MOTIONTRACKER on the service for every registered listener; listeners queue echo
// turfs with queue_echo(), and /datum/om/behaviour/world/motiontracker (code/datums/om/world_lanes.dm)
// draws the queued echoes every second.
GLOBAL_DATUM_INIT(motiontracker_service, /datum/world_service/motiontracker, new)

/datum/world_service/motiontracker
	name = "Motion Tracker"
	lane = /datum/om/behaviour/world/motiontracker
	var/hide_all = FALSE // Hide and seek mode
	var/min_range = 2
	var/max_range = 8
	var/all_echos_round = 0
	var/all_pings_round = 0
	var/list/queued_echo_turfs = list()
	var/list/currentrun = list()
	var/list/expended_echos = list()

/datum/world_service/motiontracker/stat_line()
	var/msg
	var/count = 0
	if(_listen_lookup)
		var/list/track_list = _listen_lookup[COMSIG_MOVABLE_MOTIONTRACKER]
		if(islist(track_list))
			count = length(track_list)
		else
			count = 1 // listen_lookup optimizes single entries into just returning the only thing
	if(hide_all)
		msg = "HIDE AND SEEK"
	else
		msg = "L: [count] | Q: [length(queued_echo_turfs)] | A: [all_echos_round]/[all_pings_round]"
	return msg

/datum/world_service/motiontracker/service_step(resumed)
	if(!resumed)
		src.currentrun = queued_echo_turfs.Copy()
		expended_echos.Cut()
	while(length(currentrun))
		var/key = currentrun[1] // Because using an index into an associative array gets the key at that index... I hate you byond.
		var/list/data = currentrun[key]
		var/AF= data[1]
		var/RF= data[2]
		var/count 			= data[3]
		var/list/clients 	= data[4]
		var/turf/At = om_resolve(AF)
		var/turf/Rt = om_resolve(RF)
		if(Rt && At && count)
			while(count-- > 0)
				// Place at root turf offset from signal responder's turf using px offsets. So it will show up over visblocking.
				var/image/client_only/motion_echo/E = new /image/client_only/motion_echo('icons/effects/effects.dmi', Rt, "motion_echo", OBFUSCATION_LAYER, SOUTH)
				E.place_from_root(At)
				for(var/CW in clients)
					var/client/C = om_resolve(CW)
					if(C)
						E.append_client(C)
		currentrun.Remove(key)
		expended_echos[key] = data
		if(TICK_CHECK)
			return FALSE
	// Removed used keys, incase the current queue grew while we were processing this one
	queued_echo_turfs -= expended_echos
	return TRUE

// We get this from anything in the world that would cause a motion tracker ping
// From sounds to motions, to mob attacks. This then sends a signal to anyone listening.
/datum/world_service/motiontracker/proc/ping(atom/source, hear_chance = 30)
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
	SEND_SIGNAL(src, COMSIG_MOVABLE_MOTIONTRACKER, om_handle(source), T)

// We get this back from anything that handles the signal, and queues up a turf to draw the echo on
// The logic is in the SIGNAL HANDLER for if it does anything at all with the signal instead of assuming
// everything wants effects drawn, for example the motion tracker item just flicks() and doesn't call this.
/datum/world_service/motiontracker/proc/queue_echo(turf/Rt,turf/At,echo_count = 1,client)
	if(!Rt || !At || !client)
		return
	var/rfe = REF(At)
	if(!queued_echo_turfs[rfe]) // We only care about the final turf, not the root turf for duping
		queued_echo_turfs[rfe] = list(om_handle(At),om_handle(Rt),echo_count,list(client))
		all_echos_round++
	else
		var/list/data = queued_echo_turfs[rfe]
		data[4] += list(client)
