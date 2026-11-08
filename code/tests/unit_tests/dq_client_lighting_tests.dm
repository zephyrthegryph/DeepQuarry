// Client-rendered lighting (code/content/lighting/client_glow.dm): the live toggle swaps DM lighting for glows and back.

/// Turning client lighting on gives a lit fixture a glow on its turf and leaves no lighting object anywhere; turning it off
/// takes the glow away and the lit floor grows its lighting object again.
/datum/unit_test/dq_client_lighting_toggle

/datum/unit_test/dq_client_lighting_toggle/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = L.light
	TEST_ASSERT_NOTNULL(S, "the fixture has a light source")
	var/start = REALTIMEOFDAY
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/on_ms = (REALTIMEOFDAY - start) * 100
	var/glows = 0
	for(var/obj/effect/overlay/client_glow/G in world)
		glows++
	TEST_ASSERT_NOTNULL(S.glow, "client lighting on: the light has a glow")
	TEST_ASSERT_EQUAL(S.glow.loc, get_turf(L), "the glow sits on the light's turf")
	TEST_ASSERT(S.glow.alpha > 0, "the glow is visible (alpha [S.glow.alpha])")
	TEST_ASSERT_EQUAL(S.glow.blend_mode, BLEND_ADD, "the glow adds onto the lighting plane")
	var/objects = 0
	for(var/turf/U as anything in block(locate(1, 1, T.z), locate(world.maxx, world.maxy, T.z)))
		if(U.lighting_object)
			objects++
	TEST_ASSERT_EQUAL(objects, 0, "client lighting on: no turf keeps a lighting object")
	TEST_ASSERT_EQUAL(T.luminosity, 1, "client lighting on: the dynamic floor is shown to BYOND")
	start = REALTIMEOFDAY
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	var/off_ms = (REALTIMEOFDAY - start) * 100
	var/lit_objects = 0
	for(var/turf/U as anything in block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz)))
		if(U.lighting_object)
			lit_objects++
	log_test("CLIENT LIGHTING: switch on + light pass [on_ms] ms ([glows] glows, 0 lighting objects); switch off + light pass [off_ms] ms ([lit_objects] lighting objects)")
	TEST_ASSERT_NULL(S.glow, "client lighting off: the glow is gone")
	TEST_ASSERT_NOTNULL(T.lighting_object, "client lighting off: the lit floor has its lighting object again")
