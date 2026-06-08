GLOBAL_LIST_INIT(spawntypes, populate_spawn_points())

/proc/populate_spawn_points()
	var/list/spawns = list()
	for(var/type in subtypesof(/datum/spawnpoint))
		var/datum/spawnpoint/spawn_point = new type()
		spawns[spawn_point.display_name] = spawn_point
	return spawns

/proc/get_spawn_points()
	return GLOB.spawntypes

/datum/spawnpoint
	var/msg          //Message to display on the arrivals computer.
	var/list/turfs   //List of turfs to spawn on.
	var/display_name //Name used in preference setup.
	var/list/restrict_job = null
	var/list/disallow_job = null
	var/announce_channel = "Common"
	var/allow_offmap_spawn = FALSE // add option to allow offmap spawns to a spawnpoint without entirely restricting that spawnpoint
	var/allowed_mob_types = JOB_SILICON|JOB_CARBON

/datum/spawnpoint/proc/check_job_spawning(job)
	if(restrict_job && !(job in restrict_job))
		return 0

	if(disallow_job && (job in disallow_job))
		return 0

	var/datum/job/J = SSjob.get_job(job)
	if(!J) // Couldn't find, admin shenanigans? Allow it
		return 1

	if(J.offmap_spawn && !allow_offmap_spawn && !(job in restrict_job)) // add option to allow offmap spawns to a spawnpoint without entirely restricting that spawnpoint
		return 0

	if(!(J.mob_type & allowed_mob_types))
		return 0

	return 1

/datum/spawnpoint/proc/get_spawn_position()
	return get_turf(pick(turfs))

/datum/spawnpoint/arrivals
	display_name = "Arrivals Shuttle"
	msg = "will arrive to the station shortly by shuttle"
	disallow_job = list(JOB_OUTSIDER) // add

/datum/spawnpoint/arrivals/New()
	..()
	turfs = GLOB.latejoin

/datum/spawnpoint/gateway
	display_name = "Gateway"
	msg = "has completed translation from offsite gateway"

/datum/spawnpoint/gateway/New()
	..()
	turfs = GLOB.latejoin_gateway
/* VOREStation Edit
/datum/spawnpoint/elevator
	display_name = "Elevator"
	msg = "has arrived from the residential district"

/datum/spawnpoint/elevator/New()
	..()
	turfs = latejoin_elevator
*/
/datum/spawnpoint/cryo
	display_name = "Cryogenic Storage"
	msg = "has completed cryogenic revival"
	allowed_mob_types = JOB_CARBON
	disallow_job = list(JOB_OUTSIDER) // add

/datum/spawnpoint/cryo/New()
	..()
	turfs = GLOB.latejoin_cryo

/datum/spawnpoint/cyborg
	display_name = "Cyborg Storage"
	msg = "has been activated from storage"
	allowed_mob_types = JOB_SILICON
	disallow_job = list(JOB_OUTSIDER) // add

/datum/spawnpoint/cyborg/New()
	..()
	turfs = GLOB.latejoin_cyborg

/obj/effect/landmark/arrivals
	name = "JoinLateShuttle"
	delete_me = TRUE

/obj/effect/landmark/arrivals/Initialize(mapload)
	GLOB.latejoin += loc
	. = ..()

/obj/effect/landmark/tram
	name = "JoinLateTram"
	delete_me = TRUE

/obj/effect/landmark/tram/Initialize(mapload)
	GLOB.latejoin_tram += loc // There's no tram but you know whatever man!
	. = ..()

/datum/spawnpoint/tram
	display_name = "Tram Station"
	msg = "will arrive to the station shortly by shuttle"
	disallow_job = list(JOB_OUTSIDER) // add

/datum/spawnpoint/tram/New()
	..()
	turfs = GLOB.latejoin_tram

/datum/spawnpoint/vore
	display_name = "Vorespawn - Prey"
	msg = "has arrived on the station"
	allow_offmap_spawn = TRUE

/datum/spawnpoint/vore/pred
	display_name = "Vorespawn - Pred"
	msg = "has arrived on the station"

// CHOMPEnable Start
/datum/spawnpoint/vore/itemtf
	display_name = "Item TF spawn"
	msg = "has arrived on the station"
// CHOMPEnable End

/datum/spawnpoint/vore/New()
	..()
	turfs = GLOB.latejoin


// === merged from preferences_spawnpoints_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/spawnpoint/stationgateway
	display_name = "Station gateway"
	msg = "has completed translation from station gateway"
	disallow_job = list(JOB_OUTSIDER)

/datum/spawnpoint/stationgateway/New()
	..()
	turfs = GLOB.latejoin_gatewaystation

/obj/effect/landmark/stationgateway
	name = "JoinLateStationGateway"

/datum/spawnpoint/plainspath
	display_name = "Sif plains"
	msg = "has checked in at the plains gate"
	restrict_job = list(JOB_OUTSIDER, JOB_ANOMALY)

/datum/spawnpoint/plainspath/New()
	..()
	turfs = GLOB.latejoin_plainspath

/obj/effect/landmark/plainspath
	name = "JoinLateSifPlains"

/datum/spawnpoint/fueldepot
	display_name = "Fuel Depot"
	msg = "woke up in the fuel depot"
	restrict_job = list(JOB_OUTSIDER)

/datum/spawnpoint/fueldepot/New()
	..()
	turfs = GLOB.latejoin_fueldepot

/obj/effect/landmark/fueldepot
	name = "JoinLateFuelDepot"

/datum/spawnpoint/tyrspawn
	display_name = "Tyr Wreckage"
	msg = "woke up in a ruined shuttle"
	restrict_job = list(JOB_OUTSIDER)

/datum/spawnpoint/tyrspawn/New()
	..()
	turfs = GLOB.latejoin_tyrvillage

/obj/effect/landmark/tyrspawn
	name = "JoinLateTyrVillage"

/datum/spawnpoint/darkspawn
	display_name = "The Dark"
	msg = "phased into the dark"
	restrict_job = list(JOB_ANOMALY)

/datum/spawnpoint/darkspawn/New()
	..()
	turfs = GLOB.latejoin_thedark

/obj/effect/landmark/darkspawn
	name = "JoinLateTheDark"
