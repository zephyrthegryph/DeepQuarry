GLOBAL_LIST_INIT(spawntypes, populate_spawn_points())

/proc/populate_spawn_points()
	var/list/spawns = list()
	for(var/type in subtypesof(/datum/spawnpoint))
		var/datum/spawnpoint/spawn_point = new type()
		if(!spawn_point.display_name) // an abstract base, not a place to offer
			continue
		spawns[spawn_point.display_name] = spawn_point
	return spawns


/datum/spawnpoint
	var/msg          //Message to display on the arrivals computer.
	var/display_name //Name used in preference setup.
	var/landing_list //Name of the GLOB list the map's landmarks record into.
	var/list/restrict_job = null
	var/list/disallow_job = null
	var/announce_channel = "Common"
	var/allow_offmap_spawn = FALSE // lets offmap jobs use it without restricting it to them
	var/allowed_mob_types = JOB_SILICON|JOB_CARBON

/datum/spawnpoint/proc/check_job_spawning(job)
	if(restrict_job && !(job in restrict_job))
		return 0

	if(disallow_job && (job in disallow_job))
		return 0

	var/datum/job/J = SSjob.get_job(job)
	if(!J) // Couldn't find, admin shenanigans? Allow it
		return 1

	if(J.offmap_spawn && !J.any_spawn_point && !allow_offmap_spawn && !(job in restrict_job)) // lets offmap jobs use it without restricting it to them
		return 0

	if(!(J.mob_type & allowed_mob_types))
		return 0

	return 1

/// What the map registered for this spawn point (turfs or landmarks), read when asked: a list held from world setup goes stale.
/datum/spawnpoint/proc/candidates()
	return landing_list ? GLOB.vars[landing_list] : null

/// The turfs a joiner can actually stand on.
/datum/spawnpoint/proc/usable_turfs()
	. = list()
	for(var/atom/candidate as anything in candidates())
		var/turf/T = get_turf(candidate)
		if(T && spawnpoint_turf_safe(T))
			. |= T

/datum/spawnpoint/proc/get_spawn_position()
	var/list/usable = usable_turfs()
	return length(usable) ? pick(usable) : null

/// Whether this map offers the spawn point at all: listed in allowed_spawns and with somewhere to stand.
/datum/spawnpoint/proc/is_on_map()
	return (display_name in using_map.allowed_spawns) && length(usable_turfs())

/// Why this character cannot join as `rank` here, or null. The one check behind the setup list, the saved choice and the join.
/datum/spawnpoint/proc/rank_refusal(datum/preferences/prefs, rank)
	if(!check_job_spawning(rank))
		return "not open to [rank]"
	var/datum/job/J = SSjob.get_job(rank)
	if(!J || !prefs)
		return null
	var/species = prefs.read_preference(/datum/preference/choiced/species)
	if(J.is_species_banned(species, prefs.read_preference(/datum/preference/organ_data)?[O_BRAIN]))
		return "[rank] is closed to [species]"
	if(play_mode_rank_refusal(prefs.read_preference(/datum/preference/text/human/play_mode) || "human", rank))
		return "[rank] does not fit this play mode"
	var/client/C = prefs.client()
	if(C)
		if(alien_whitelist_refusal(C, GLOB.all_species[species]))
			return "not whitelisted for [species]"
		if(job_whitelist_refusal(C.mob, rank))
			return "not whitelisted for [rank]"
	return null

/// Why this character cannot take the spawn point, or null. With a `rank` it answers for that job, without one for any job the character could
/// take (the AI is left out: it joins into a core, so no spawn point is ever its reason to pick one).
/// While the world is still loading the map and the jobs are not known yet, so a saved choice is not judged by them.
/datum/spawnpoint/proc/refusal(datum/preferences/prefs, rank = null)
	if(atoms_atom_initialized() == INITIALIZATION_INNEW_REGULAR && !is_on_map())
		return "not on this map"
	if(rank)
		return rank_refusal(prefs, rank)
	var/list/jobs = job_occupations()
	if(!length(jobs))
		return null
	for(var/datum/job/J as anything in jobs)
		if(J.mob_type & JOB_SILICON_AI)
			continue
		if(!rank_refusal(prefs, J.title))
			return null
	return "no job this character can take uses it"

/// A joiner can stand here: not space, not a wall, nothing solid in the way.
/proc/spawnpoint_turf_safe(turf/T)
	if(!isturf(T) || T.density || istype(T, /turf/space))
		return FALSE
	for(var/atom/movable/O as anything in contents_of(T))
		if(isobj(O) && O.density && !(O.flags & ON_BORDER)) // a border window beside a shuttle seat does not stop anyone standing there
			return FALSE
	return TRUE

/// Why this play mode cannot take `rank`, or null: cyborgs are the only option for a robot and no option for anyone else, and a pAI takes no job.
/proc/play_mode_rank_refusal(play_mode, rank)
	var/is_cyborg_job = (rank == JOB_CYBORG || rank == JOB_ALT_ROBOT || rank == JOB_ALT_DRONE)
	if(play_mode == "pai" || (play_mode == "robot" && !is_cyborg_job) || (play_mode == "human" && is_cyborg_job))
		return /datum/msg/join/wrong_play_mode
	return null

/// The spawn points this character can take, by display name; never empty, so the setup list always has the default to show.
/proc/spawnpoint_choices_for(datum/preferences/prefs)
	. = list()
	for(var/name in GLOB.spawntypes)
		var/datum/spawnpoint/P = GLOB.spawntypes[name]
		if(!P.refusal(prefs))
			. += name
	if(!length(.))
		var/datum/spawnpoint/fallback = DEFAULT_LATEJOIN_LOCATION
		. += fallback::display_name

/// The default for this character: the usual one if they can take it, else the first they can that needs no host.
/proc/spawnpoint_default_for(datum/preferences/prefs)
	var/datum/spawnpoint/usual = DEFAULT_LATEJOIN_LOCATION
	var/list/choices = spawnpoint_choices_for(prefs)
	if(usual::display_name in choices)
		return usual::display_name
	for(var/name in choices)
		if(!istype(GLOB.spawntypes[name], /datum/spawnpoint/vore))
			return name
	return choices[1]

/// Where a join as `rank` goes: the chosen spawn point when it holds for this character and job, else the first that does, else null.
/// The vore and item spawn points need a host and answers from the joiner, so they are never picked for someone who did not choose them.
/proc/spawnpoint_for_join(datum/preferences/prefs, rank, preferred)
	var/datum/spawnpoint/chosen = GLOB.spawntypes[preferred]
	if(chosen && !chosen.refusal(prefs, rank))
		return chosen
	for(var/name in GLOB.spawntypes)
		var/datum/spawnpoint/P = GLOB.spawntypes[name]
		if(!istype(P, /datum/spawnpoint/vore) && !P.refusal(prefs, rank))
			return P
	return null

/datum/spawnpoint/arrivals
	display_name = "Arrivals Shuttle"
	msg = "will arrive to the station shortly by shuttle"

/datum/spawnpoint/arrivals/candidates()
	return REGISTRY_MEMBERS(REGISTRY_LATEJOIN)

/datum/spawnpoint/gateway
	landing_list = "latejoin_gateway"
	display_name = "Gateway"
	msg = "has completed translation from offsite gateway"

/datum/spawnpoint/teleporter
	landing_list = "latejoin_teleporter"
	display_name = "Teleporter"
	msg = "has arrived by teleporter"

/datum/spawnpoint/cryo
	landing_list = "latejoin_cryo"
	display_name = "Cryogenic Storage"
	msg = "has completed cryogenic revival"
	allowed_mob_types = JOB_CARBON

/datum/spawnpoint/cyborg
	landing_list = "latejoin_cyborg"
	display_name = "Cyborg Storage"
	msg = "has been activated from storage"
	allowed_mob_types = JOB_SILICON


/datum/spawnpoint/tram
	landing_list = "latejoin_tram"
	display_name = "Tram Station"
	msg = "will arrive to the station shortly by shuttle"

/datum/spawnpoint/vore
	display_name = "Vorespawn - Prey"
	msg = "has arrived on the station"
	allow_offmap_spawn = TRUE

/datum/spawnpoint/vore/pred
	display_name = "Vorespawn - Pred"
	msg = "has arrived on the station"

/datum/spawnpoint/vore/itemtf
	display_name = "Item TF spawn"
	msg = "has arrived on the station"

/datum/spawnpoint/vore/candidates()
	return REGISTRY_MEMBERS(REGISTRY_LATEJOIN)


/// Hosts decide these at the join (SSjob.late_spawn()), so no map lists them; they need only the arrivals spot the body starts on.
/datum/spawnpoint/vore/is_on_map()
	return length(usable_turfs())

/datum/spawnpoint/stationgateway
	landing_list = "latejoin_gatewaystation"
	display_name = "Station gateway"
	msg = "has completed translation from station gateway"


/datum/spawnpoint/plainspath
	landing_list = "latejoin_plainspath"
	display_name = "Sif plains"
	msg = "has checked in at the plains gate"
	restrict_job = list(JOB_OUTSIDER, JOB_ANOMALY)


/datum/spawnpoint/fueldepot
	landing_list = "latejoin_fueldepot"
	display_name = "Fuel Depot"
	msg = "woke up in the fuel depot"
	restrict_job = list(JOB_OUTSIDER)


/datum/spawnpoint/tyrspawn
	landing_list = "latejoin_tyrvillage"
	display_name = "Tyr Wreckage"
	msg = "woke up in a ruined shuttle"
	restrict_job = list(JOB_OUTSIDER)


/datum/spawnpoint/darkspawn
	landing_list = "latejoin_thedark"
	display_name = "The Dark"
	msg = "phased into the dark"
	restrict_job = list(JOB_ANOMALY)

