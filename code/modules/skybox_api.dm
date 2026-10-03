// The skybox system's API (code/modules/skybox_service.dm declares the system).
//
//   SSskybox.ready()                     the system, built on first use (it is lazy)
//   SSskybox.get_skybox(z)               the skybox overlay of a z-level
//   SSskybox.rebuild_skyboxes(zlevels)   drop the cached skyboxes of those z-levels (null: all) and refresh them

/// Typed, so `SSskybox.ready().var` reads as the system's own var.
/datum/system/skybox/ready()
	RETURN_TYPE(/datum/system/skybox)
	return ..()

/datum/system/skybox/proc/get_skybox(z)
	if(!skybox_cache["[z]"])
		skybox_cache["[z]"] = generate_skybox(z)
	return skybox_cache["[z]"]

/datum/system/skybox/proc/rebuild_skyboxes(list/zlevels)
	for(var/z in zlevels)
		skybox_cache["[z]"] = generate_skybox(z)

	for(var/client/C in GLOB.clients)
		var/their_z = get_z(C.mob)
		if(!their_z) //Nullspace
			continue
		if(their_z in zlevels)
			C.update_skybox(1)
