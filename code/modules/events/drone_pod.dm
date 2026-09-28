/datum/event/drone_pod_drop
	var/land_target_handle
	var/attempt_amount = 10

/datum/event/drone_pod_drop/setup()
	startWhen = rand(8,15)

	var/land_spot_list = list()
	var/target_spot

	for(var/obj/effect/landmark/land_spot in REGISTRY_MEMBERS(REGISTRY_LANDMARKS))
		if(land_spot.name == "droppod_landing" && !(land_spot in land_spot_list))
			land_spot_list += land_spot

	target_spot = pick(land_spot_list)
	land_target_handle =  om_handle(get_turf(target_spot))

	if(!land_target())
		kill()
	else
		registry_leave(REGISTRY_LANDMARKS, target_spot)
		qdel(target_spot)

/datum/event/drone_pod_drop/announce()
	GLOB.command_announcement.Announce("An unidentified drone pod has been detected on a collision course towards the [location_name()]. Open and examine at your own risk.", "[location_name()] Sensor Network", ANNOUNCER_MSG_DRONEPOD)

/datum/event/drone_pod_drop/start()
	if(!land_target())
		kill()

	new /datum/random_map/droppod/supply(null, land_target().x-2, land_target().y-2, land_target().z, supplied_drops = list(/obj/structure/ghost_pod/manual/lost_drone/dogborg))


/// LC-refs: the land_target this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/event/drone_pod_drop/proc/land_target() as /turf
	return om_resolve(land_target_handle)
