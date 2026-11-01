// Lights: a powered fixture placed in a room lights the floor around it. The light has to reach the turfs' lighting corners, not just show a lit
// sprite (perf/light-glow shipped fixtures that looked lit and cast nothing: their light source was never made).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A tube fixture placed in the powered test room is on, has a light source, and brightens the lighting corners of the floor next to it.
/datum/unit_test/dq_gameplay/light_fixture_lights_the_room

/datum/unit_test/dq_gameplay/light_fixture_lights_the_room/play()
	var/turf/under = tile(2, 2)
	var/turf/near = tile(2, 1)
	TEST_ASSERT(near.lighting_object, "the test room has dynamic lighting (no lighting object on [near])")
	SSlighting.light_step(0, TRUE)
	var/before = turf_corner_lum(near)
	var/obj/machinery/light/L = allocate(/obj/machinery/light, under)
	pass_time(1)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(L.on, "the fixture is on in the powered room")
	TEST_ASSERT(L.light, "the lit fixture has a light source (light_on=[L.light_on], glow range [glow_of(L).range], power [glow_of(L).power])")
	var/after = turf_corner_lum(near)
	TEST_ASSERT(after > before, "the fixture's light reaches the floor next to it: corner light [before] before, [after] after")

/// The light on a turf's four lighting corners (all channels summed), 0 without a lighting object.
/proc/turf_corner_lum(turf/T)
	if(!T.lighting_object)
		return 0
	. = 0
	for(var/datum/lighting_corner/C in list(T.lighting_corner_NE, T.lighting_corner_SE, T.lighting_corner_SW, T.lighting_corner_NW))
		. += C.lum_r + C.lum_g + C.lum_b

#endif
