// Create lighting overlays on all turfs with dynamic lighting in areas with dynamic lighting.
/proc/create_all_lighting_objects()
	if(GLOB.client_lighting) // client-rendered glows: no lighting objects (client_glow.dm)
		return
	var/list/all_turfs = block(locate(1,1,1), locate(world.maxx, world.maxy, world.maxz))
	for(var/turf/T as anything in all_turfs)
		T.lighting_build_overlay()
		CHECK_TICK
