// Create lighting overlays on all turfs with dynamic lighting in areas with dynamic lighting.
/proc/create_all_lighting_objects()
	if(GLOB.client_lighting && !GLOB.client_lighting_compare) // client-rendered glows: no lighting objects (client_glow.dm)
		client_glow_whites_set(TRUE) // only the white tiles that keep turfs outside dynamic lighting bright over the black base
		// The map's turfs initialized before this system read the config (atoms come first), so they hold the DM engine's luminosity 0:
		// BYOND would draw them black and send no glow on them. Client mode shows every dynamic turf; the lighting plane does the darkness.
		var/shown = 0
		for(var/turf/T as anything in block(locate(1,1,1), locate(world.maxx, world.maxy, world.maxz)))
			if(T.has_dynamic_lighting() && !T.luminosity)
				T.set_luminosity(1, TRUE)
				shown++
			CHECK_TICK
		log_world("client lighting: boot showed [shown] dynamic turf(s) that initialized at luminosity 0")
		return
	var/list/all_turfs = block(locate(1,1,1), locate(world.maxx, world.maxy, world.maxz))
	for(var/turf/T as anything in all_turfs)
		T.lighting_build_overlay()
		CHECK_TICK
