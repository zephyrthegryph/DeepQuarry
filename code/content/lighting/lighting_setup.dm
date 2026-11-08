// Create lighting overlays on all turfs with dynamic lighting in areas with dynamic lighting.
/proc/create_all_lighting_objects()
	if(GLOB.client_lighting && !GLOB.client_lighting_compare) // client-rendered glows: no lighting objects (client_glow.dm)
		client_glow_whites_set(TRUE) // only the white tiles that keep turfs outside dynamic lighting bright over the black base
		return
	var/list/all_turfs = block(locate(1,1,1), locate(world.maxx, world.maxy, world.maxz))
	for(var/turf/T as anything in all_turfs)
		T.lighting_build_overlay()
		CHECK_TICK
