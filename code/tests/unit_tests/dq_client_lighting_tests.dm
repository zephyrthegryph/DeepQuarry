// Client-rendered lighting (code/content/lighting/client_glow.dm): the live toggle swaps DM lighting for glows and back.

/// Turning client lighting on gives a lit fixture a glow on its turf and leaves no lighting object anywhere; turning it off
/// takes the glow away and the lit floor grows its lighting object again.
/datum/unit_test/dq_client_lighting_toggle

/datum/unit_test/dq_client_lighting_toggle/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
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

/// The glow's mask stops at a wall: an opaque blocker east of the light keeps the floor behind it dark, and the mask is
/// rebuilt when the blocker comes and goes (a door closing and opening), and when the light moves.
/datum/unit_test/dq_client_lighting_shadows

/datum/unit_test/dq_client_lighting_shadows/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	var/turf/T = run_loc_floor_bottom_left
	var/turf/east1 = locate(T.x + 1, T.y, T.z)
	var/turf/east2 = locate(T.x + 2, T.y, T.z)
	var/turf/north1 = locate(T.x, T.y + 1, T.z)
	TEST_ASSERT(east1 && east2 && north1 && !east1.directional_opacity && !east2.directional_opacity && !north1.directional_opacity, "the test floor has clear turfs east and north")
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = L.light
	TEST_ASSERT_NOTNULL(S?.glow_mask, "the glow has a shadow mask")
	TEST_ASSERT_NOTNULL(S.glow.get_filter("client_shadow"), "the glow is cut by an alpha filter")
	TEST_ASSERT_NOTNULL(S.glow_mask.get_filter("client_shadow_soft"), "the mask is blurred before it cuts the glow")
	TEST_ASSERT(findtext(S.glow_mask.render_target, "*") == 1, "the mask is a hidden render target")
	TEST_ASSERT(S.glow_reach["2,0"], "the open floor two tiles east is lit")
	var/builds = GLOB.client_glow_mask_builds
	var/obj/structure/sight_test_blocker/B = allocate(/obj/structure/sight_test_blocker, east1)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(GLOB.client_glow_mask_builds > builds, "closing the blocker rebuilt the mask")
	TEST_ASSERT(S.glow_reach["1,0"], "the blocker's face is lit")
	TEST_ASSERT(!S.glow_reach["2,0"], "the floor behind the blocker is in shadow")
	builds = GLOB.client_glow_mask_builds
	qdel(B)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(GLOB.client_glow_mask_builds > builds, "opening it rebuilt the mask")
	TEST_ASSERT(S.glow_reach["2,0"], "the floor behind is lit again")
	builds = GLOB.client_glow_mask_builds
	L.forceMove(north1)
	SSlighting.light_step(0, TRUE)
	S = L.light
	TEST_ASSERT_EQUAL(S?.glow?.loc, north1, "the glow followed the moved light")
	TEST_ASSERT(GLOB.client_glow_mask_builds > builds, "the moved light rebuilt its mask")
	log_test("CLIENT SHADOWS: [GLOB.client_glow_mask_builds] mask builds, [GLOB.client_glow_reconsiders] opacity-triggered redraws")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NULL(S?.glow_mask, "client lighting off: the mask is gone")

/// The lighting step drops a deleted light source left in its queue instead of spinning on it (a caller once re-queued
/// spent sources, and light_step() stepped back over the same entry forever).
/datum/unit_test/dq_light_step_drops_deleted_sources

/datum/unit_test/dq_light_step_drops_deleted_sources/Run()
	var/obj/machinery/light/L = allocate(/obj/machinery/light, run_loc_floor_bottom_left)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = L.light
	TEST_ASSERT_NOTNULL(S, "the fixture has a light source")
	qdel(S)
	TEST_ASSERT(QDELETED(S), "the source is deleted")
	SSlighting.queue_source(S)
	SSlighting.queue_source(S)
	SSlighting.light_step(0, TRUE) // must return
	TEST_ASSERT(!(S in SSlighting.sources_queue), "the deleted source left the queue")

/// The gameplay light level under client lighting tracks the corner engine's: next to a fixture both are bright and close,
/// far away and behind a wall both are dark.
/datum/unit_test/dq_client_light_level_parity

/datum/unit_test/dq_client_light_level_parity/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	var/list/probes = list()
	for(var/dx in 0 to 3)
		var/turf/P = locate(T.x + dx, T.y, T.z)
		if(P && !P.directional_opacity)
			probes += P
	TEST_ASSERT(length(probes) >= 2, "the test room has open floor east of the fixture")
	// A floor out of the fixture's reach: whatever else lights it, both engines agree.
	var/turf/far = locate(min(world.maxx, T.x + 12), T.y, T.z)
	if(far && !far.directional_opacity)
		probes += far
	var/list/old_levels = list()
	for(var/turf/P as anything in probes)
		old_levels += P.get_lumcount()
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/list/report = list()
	for(var/i in 1 to length(probes))
		var/turf/P = probes[i]
		var/now = P.get_lumcount()
		report += "+[P.x - T.x]: corners [round(old_levels[i], 0.01)] / client [round(now, 0.01)]"
		TEST_ASSERT(abs(now - old_levels[i]) <= 0.2, "light level at +[P.x - T.x] differs too much: corner engine [old_levels[i]], client [now]")
	log_test("CLIENT LIGHT LEVEL: [jointext(report, "; ")]")
	TEST_ASSERT(probes[1].get_lumcount() > 0.3, "the fixture's own floor is lit under client lighting")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A lum band watched on a floor under client lighting moves when a light comes on beside it and when it goes again (the
/// shadow mask rebuild reports the watched turfs it covers).
/datum/unit_test/dq_client_lighting_lum_watch

/datum/unit_test/dq_client_lighting_lum_watch/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	var/turf/T = run_loc_floor_bottom_left
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/list/levels = list(0.6)
	var/dark_band = watched(T, WATCH_LUM, levels)
	SSwatched.arm_pending(0)
	TEST_ASSERT(watched_armed(T, WATCH_LUM, levels), "the read armed a lum band under client lighting")
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	SSwatched.arm_pending(0)
	var/list/rows = SSwatched.lum_rows(T)
	var/list/row = rows[jointext(levels, ",")]
	TEST_ASSERT(T.get_lumcount() > 0.6, "the fixture lights its floor ([T.get_lumcount()])")
	TEST_ASSERT(row[2] != dark_band, "the band moved when the light came on (band [row[2]], dark [dark_band])")
	qdel(L)
	SSlighting.light_step(0, TRUE)
	SSwatched.arm_pending(0)
	row = SSwatched.lum_rows(T)[jointext(levels, ",")]
	TEST_ASSERT_EQUAL(row[2], watched_band(T.get_lumcount(), levels), "the band follows the level once the light is gone")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
