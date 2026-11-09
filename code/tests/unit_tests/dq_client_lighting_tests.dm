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
	var/turf/edge = locate(T.x + CEILING(S.light_range, 1), T.y, T.z)
	if(edge && GLOB.client_glow_bounds)
		TEST_ASSERT(edge in S.glow.locs, "the glow's bounds reach the turf at the edge of its range, so a client seeing only that turf gets it")
	var/live_glows = 0
	var/holders = 0
	for(var/obj/effect/overlay/client_glow/G in world)
		if(!QDELETED(G))
			live_glows++
	for(var/datum/light_source/LS)
		if(!QDELETED(LS) && LS.glow)
			holders++
	TEST_ASSERT_EQUAL(live_glows, holders, "one live glow per glowing light (no duplicates)")
	log_test("CLIENT GLOW COUNT: [glows] glows in the world loop, [live_glows] live, [holders] lights holding one")
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
/// The alpha of a GetPixel() colour.
/proc/client_lighting_test_alpha(color)
	return length(color) >= 9 ? text2num(copytext(color, 8, 10), 16) : 255

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
	TEST_ASSERT(S?.glow_mask_key, "the glow has a shadow mask shape")
	// The bake itself: real pixels, orientation included. The glow's margin is the shape's; a reached tile is solid, an unreached one clear.
	var/list/shape_parts = splittext(S.glow_mask_key, "|")
	var/margin = text2num(shape_parts[1])
	var/north_margin_key = "[margin]|0,0,0,1"
	var/png = client_glow_mask_bake_blocking(north_margin_key)
	TEST_ASSERT_NOTNULL(png, "iconforge baked the mask")
	var/icon/baked = icon(file(png))
	var/size = margin * 2 + WORLD_ICON_SIZE
	TEST_ASSERT_EQUAL(baked.Width(), size, "the mask is the glow sprite's size")
	TEST_ASSERT_NOTNULL(baked.GetPixel(margin + 16, margin + 16), "the light's own tile is open")
	TEST_ASSERT_NOTNULL(baked.GetPixel(margin + 16, margin + 48), "the tile north of the light is open: north is up in the mask")
	TEST_ASSERT_NULL(baked.GetPixel(margin + 16, margin - 24), "the tile south, not reached, is clear past the fade")
	TEST_ASSERT_NULL(baked.GetPixel(margin + 56, margin + 16), "the tile east, not reached, is clear past the fade")
	TEST_ASSERT_NULL(baked.GetPixel(margin + 34, margin + 16), "nothing spills past a reached tile's edge")
	TEST_ASSERT(client_lighting_test_alpha(baked.GetPixel(margin + 31, margin + 16)) < client_lighting_test_alpha(baked.GetPixel(margin + 16, margin + 16)), "the fade is inside the reached tile")
	fdel(png)
	// A wall is exact: no light anywhere on it, and the floor beside it is not faded.
	var/wall_png = client_glow_mask_bake_blocking("[margin]|0,0,0,1|0,-1,1,0")
	TEST_ASSERT_NOTNULL(wall_png, "iconforge baked the walled mask")
	var/icon/walled = icon(file(wall_png))
	for(var/px in 1 to WORLD_ICON_SIZE)
		for(var/py in 1 to WORLD_ICON_SIZE)
			TEST_ASSERT_NULL(walled.GetPixel(margin + px, margin - WORLD_ICON_SIZE + py), "no light on the wall south of the light")
	TEST_ASSERT_EQUAL(client_lighting_test_alpha(walled.GetPixel(margin + 24, margin + 1)), client_lighting_test_alpha(walled.GetPixel(margin + 24, margin + 16)), "the floor against the wall is not faded")
	fdel(wall_png)
	// The real tube on Southern Cross, when this run has that map (--full-map): through the real path, its wall row and everything past it hold no light.
	var/obj/machinery/light/real_tube = locate(/obj/machinery/light) in locate(132, 80, 2)
	if(real_tube?.light?.glow_mask_key)
		var/real_key = real_tube.light.glow_mask_key
		var/real_margin = text2num(splittext(real_key, "|")[1])
		var/real_png = client_glow_mask_bake_blocking(real_key)
		TEST_ASSERT_NOTNULL(real_png, "iconforge baked the real tube")
		var/icon/real = icon(file(real_png))
		var/real_size = real_margin * 2 + WORLD_ICON_SIZE
		TEST_ASSERT_NOTNULL(real.GetPixel(real_margin + 16, real_margin + 16), "the tube's floor tile is lit")
		for(var/px in 1 to real_size)
			for(var/py in 1 to real_margin)
				TEST_ASSERT_NULL(real.GetPixel(px, py), "no light on the wall row or past it")
		log_world("client glow test: real tube key [real_key] clear below its own tile")
		fdel(real_png)
	TEST_ASSERT(S.glow_reach["2,0"], "the open floor two tiles east is lit")
	// The largest glow, wide open and then checkered (the most rectangles a shape can need): both must bake, iconforge refuses over 128 steps.
	var/list/open_tiles = list()
	var/list/checkered = list()
	for(var/dx in -5 to 5)
		for(var/dy in -5 to 5)
			open_tiles += "[dx],[dy]"
			if(!((dx + dy) % 2))
				checkered += "[dx],[dy]"
	var/list/open_sprite = client_glow_mask_sprite("160|[jointext(open_tiles, ",")]")
	TEST_ASSERT(length(open_sprite["transform"]) <= CLIENT_GLOW_MASK_STEPS_MAX, "an open range 6 mask fits iconforge's transform limit")
	for(var/list/shape in list(open_tiles, checkered))
		var/big_png = client_glow_mask_bake_blocking("160|[jointext(shape, ",")]")
		TEST_ASSERT_NOTNULL(big_png, "iconforge baked a range 6 mask")
		fdel(big_png)
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
	TEST_ASSERT_NULL(S?.glow_mask_key, "client lighting off: the mask shape is gone")

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

// ---- the per-client glow holder (client_glow_holder.dm) ----

/// A lit fixture with client lighting on, and a holder (no client) seeing from just off the light's screen.
/datum/unit_test/proc/client_glow_holder_setup(list/out)
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	for(var/counter in list(nameof(GLOB.client_glow_holder_made), nameof(GLOB.client_glow_holder_updated), nameof(GLOB.client_glow_holder_dropped), nameof(GLOB.client_glow_holder_recomputes), nameof(GLOB.client_glow_holder_reused), nameof(GLOB.client_glow_holder_scans_skipped), nameof(GLOB.client_glow_holder_stands_moved)))
		set_global(counter, GLOB.vars[counter]) // teardown restores the counters
	var/obj/machinery/light/F = allocate(/obj/machinery/light, run_loc_floor_bottom_left)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/datum/client_glow_holder/H = new
	H.view_at(client_glow_test_eye(get_turf(F)), 7, 7)
	out += F
	out += H

/// A light just off screen shows its glow on screen: the viewer holds a glow image on a turf it saw, offset to the light's true
/// place and within the light's range, baked to its shape once ready; the real glow is hidden.
/datum/unit_test/dq_client_glow_holder_off_screen

/datum/unit_test/dq_client_glow_holder_off_screen/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	TEST_ASSERT_NOTNULL(S?.glow, "the fixture glows")
	var/list/entry = H.entry_of(S)
	TEST_ASSERT_NOTNULL(entry, "the viewer holds the off-screen light's glow")
	var/image/glow_image = entry[1]
	var/image/hide_image = entry[2]
	var/turf/A = glow_image.loc
	TEST_ASSERT(isturf(A) && H.seen[A], "the hidden light's glow stands on a turf the eye saw")
	TEST_ASSERT(max(abs(A.x - LT.x), abs(A.y - LT.y)) <= CEILING(S.light_range, 1), "it stands within the light's range")
	TEST_ASSERT_EQUAL(A.x + (glow_image.pixel_x - S.glow.pixel_x) / WORLD_ICON_SIZE, LT.x, "its x offset puts it on the light")
	TEST_ASSERT_EQUAL(A.y + (glow_image.pixel_y - S.glow.pixel_y) / WORLD_ICON_SIZE, LT.y, "its y offset puts it on the light")
	TEST_ASSERT_EQUAL(glow_image.blend_mode, BLEND_ADD, "the copy adds like the glow")
	TEST_ASSERT_EQUAL(glow_image.plane, PLANE_CLIENT_GLOW, "the copy is on the glow plane")
	H.shape_ready(S.glow_mask_key, 'icons/effects/light_overlays/light_32.dmi')
	TEST_ASSERT_EQUAL(glow_image.icon, 'icons/effects/light_overlays/light_32.dmi', "a baked shape replaces the waiting glow image's picture")
	TEST_ASSERT(!length(glow_image.filters), "a held glow carries no filter of its own")
	TEST_ASSERT(hide_image.override && hide_image.loc == S.glow, "the real glow is overridden for this viewer: never drawn twice")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A light on screen is held too: its own turf may be behind a wall from the eye while its light reaches turfs the viewer sees.
/datum/unit_test/dq_client_glow_holder_in_view

/datum/unit_test/dq_client_glow_holder_in_view/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	TEST_ASSERT_NOTNULL(H.entry_of(S), "held while off screen")
	H.view_at(get_turf(F), 7, 7)
	var/list/entry = H.entry_of(S)
	TEST_ASSERT_NOTNULL(entry, "still held with the eye on the light")
	var/image/glow_image = entry[1]
	var/turf/LT = get_turf(F)
	TEST_ASSERT_EQUAL(glow_image.loc, LT, "a light the eye sees stands on its own turf")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Standing on the light's own turf: a held glow and its mask sit there with only the glow's own centring offset.
/datum/unit_test/dq_client_glow_holder_light_turf

/datum/unit_test/dq_client_glow_holder_light_turf/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	H.view_at(LT, 7, 7)
	var/list/entry = H.entry_of(S)
	TEST_ASSERT_NOTNULL(entry, "the viewer holds the light")
	var/image/glow_image = entry[1]
	TEST_ASSERT_EQUAL(glow_image.loc, LT, "the glow image stands on its light's turf")
	TEST_ASSERT_EQUAL(glow_image.pixel_x, S.glow.pixel_x, "only the glow's own offset remains")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Occlusion still applies: a blocker next to the light rebuilds the copy's mask image, and the shadowed turf leaves it.
/datum/unit_test/dq_client_glow_holder_occlusion

/datum/unit_test/dq_client_glow_holder_occlusion/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	var/turf/east1 = locate(LT.x + 1, LT.y, LT.z)
	TEST_ASSERT(S.glow_reach["2,0"], "the floor two east is lit before the blocker")
	var/before = S.glow_mask_key
	TEST_ASSERT_EQUAL(H.held_shape[S.glow_holder_key], before, "the copy wants the light's mask shape")
	var/obj/structure/sight_test_blocker/B = allocate(/obj/structure/sight_test_blocker, east1)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(H.entry_of(S), "still held")
	TEST_ASSERT(!S.glow_reach["2,0"], "the floor behind the blocker is in shadow")
	TEST_ASSERT(S.glow_mask_key != before, "the shape changed")
	TEST_ASSERT_EQUAL(H.held_shape[S.glow_holder_key], S.glow_mask_key, "the copy wants the new shape")
	TEST_ASSERT(S.glow_reach["1,0"], "the gameplay reach keeps the opaque tile")
	var/list/shape_offsets = splittext(splittext(S.glow_mask_key, "|")[2], ",")
	for(var/i = 1, i < length(shape_offsets), i += 2)
		TEST_ASSERT(!(shape_offsets[i] == "1" && shape_offsets[i + 1] == "0"), "the baked shape leaves out the opaque tile")
	qdel(B)
	SSlighting.light_step(0, TRUE)
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Event-driven: a step inside the eye's chunk touches nothing; crossing into the next chunk recomputes.
/datum/unit_test/dq_client_glow_holder_events

/datum/unit_test/dq_client_glow_holder_events/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/turf/E = client_glow_test_eye(get_turf(F))
	var/cx0 = round((E.x - 1) / CLIENT_GLOW_CHUNK) * CLIENT_GLOW_CHUNK + 1
	var/recomputes = GLOB.client_glow_holder_recomputes
	var/touched = GLOB.client_glow_holder_made + GLOB.client_glow_holder_updated + GLOB.client_glow_holder_dropped
	for(var/x in cx0 to cx0 + CLIENT_GLOW_CHUNK - 1)
		H.view_at(locate(x, E.y, E.z), 7, 7)
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_recomputes, recomputes, "stepping inside the chunk recomputes nothing")
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_made + GLOB.client_glow_holder_updated + GLOB.client_glow_holder_dropped, touched, "stepping inside the chunk touches no image")
	var/turf/next = locate(cx0 + CLIENT_GLOW_CHUNK, E.y, E.z) || locate(cx0 - 1, E.y, E.z)
	H.view_at(next, 7, 7)
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_recomputes, recomputes + 1, "crossing a chunk recomputes once")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Hysteresis: a glow is acquired by the reach box but kept until it leaves the keep box, so a walk back and forth over a chunk edge makes and
/// drops nothing after the first crossing, and walking on far enough drops it.
/datum/unit_test/dq_client_glow_holder_chunk_hysteresis

/datum/unit_test/dq_client_glow_holder_chunk_hysteresis/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	var/turf/A = client_glow_test_eye(LT)
	var/step = (A.x > LT.x ? 1 : -1) * CLIENT_GLOW_CHUNK
	var/turf/B = locate(A.x + step, A.y, A.z)
	TEST_ASSERT_NOTNULL(B, "the next chunk away from the light exists")
	TEST_ASSERT_NOTNULL(H.entry_of(S), "held from the first chunk")
	H.view_at(B, 7, 7)
	TEST_ASSERT_NOTNULL(H.entry_of(S), "one chunk further away it is still kept")
	var/images = length(H.images())
	var/made = GLOB.client_glow_holder_made
	var/dropped = GLOB.client_glow_holder_dropped
	for(var/i in 1 to 4)
		H.view_at(A, 7, 7)
		H.view_at(B, 7, 7)
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_made, made, "walking back and forth over the edge makes no glow")
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_dropped, dropped, "walking back and forth over the edge drops no glow")
	TEST_ASSERT_EQUAL(length(H.images()), images, "the held images stay as they were")
	var/turf/far
	for(var/chunks in 2 to 8)
		far = locate(A.x + step * chunks, A.y, A.z)
		if(!far)
			break
		H.view_at(far, 7, 7)
		if(!H.entry_of(S))
			break
	TEST_ASSERT_NULL(H.entry_of(S), "clear of the keep box the glow is dropped")
	TEST_ASSERT(GLOB.client_glow_holder_dropped > dropped, "leaving the keep range drops it")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The eye walks (a turf at a time) from `A` away from the light `LT` until `entry_of(S)` is gone or `limit` chunks were crossed. Returns the turf it ended on, or null.
/datum/unit_test/proc/client_glow_walk_away(datum/client_glow_holder/H, datum/light_source/S, turf/A, turf/LT, limit = 12)
	var/step = A.x > LT.x ? 1 : -1
	var/turf/at = A
	for(var/i in 1 to limit * CLIENT_GLOW_CHUNK)
		var/turf/next = locate(at.x + step, at.y, at.z)
		if(!next)
			return null
		at = next
		H.view_at(at, 7, 7)
		if(!H.entry_of(S))
			return at
	return null

/// Reuse: a glow dropped on the walk away blanks its images into the holder's pool (no loc, picture, plane, colour, alpha or offset left), and the glow
/// acquired next takes the very same image objects, written afresh whatever was left on them. The keep box is two chunks past the reach box: a walk back
/// and forth inside it makes and drops nothing at all.
/datum/unit_test/dq_client_glow_holder_reuses_dropped_images

/datum/unit_test/dq_client_glow_holder_reuses_dropped_images/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	var/turf/A = client_glow_test_eye(LT)
	var/list/old = H.entry_of(S)
	TEST_ASSERT_NOTNULL(old, "held from the first chunk")
	var/image/old_glow = old[1]
	var/image/old_hide = old[2]
	TEST_ASSERT_EQUAL(CLIENT_GLOW_KEEP_CHUNKS, 2, "the keep box is two chunks past the reach box")
	var/step = (A.x > LT.x ? 1 : -1) * CLIENT_GLOW_CHUNK
	var/made = GLOB.client_glow_holder_made
	var/dropped = GLOB.client_glow_holder_dropped
	var/turf/B = locate(A.x + step, A.y, A.z)
	var/turf/C = locate(A.x + 2 * step, A.y, A.z)
	TEST_ASSERT(B && C, "the map has two chunks past the eye")
	for(var/i in 1 to 3)
		H.view_at(C, 7, 7)
		H.view_at(B, 7, 7)
		H.view_at(A, 7, 7)
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_made, made, "two chunks out and back makes no glow")
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_dropped, dropped, "two chunks out and back drops no glow")
	TEST_ASSERT_EQUAL(H.entry_of(S)[1], old_glow, "the same glow image all the way")
	// Out of the keep box: dropped, its images blank in the pool.
	var/turf/far = client_glow_walk_away(H, S, A, LT)
	TEST_ASSERT_NOTNULL(far, "walking away drops the glow within a dozen chunks")
	TEST_ASSERT_EQUAL(H.pool_sizes()[1], 1, "the glow image is pooled")
	TEST_ASSERT_EQUAL(H.pool_sizes()[2], 1, "the hide image is pooled")
	TEST_ASSERT_NULL(old_glow.loc, "a pooled glow image is anchored to nothing")
	TEST_ASSERT_NULL(old_hide.loc, "a pooled hide image is anchored to nothing")
	TEST_ASSERT_NULL(old_glow.icon, "no picture left")
	TEST_ASSERT_NULL(old_glow.color, "no colour left")
	TEST_ASSERT_EQUAL(old_glow.alpha, 255, "no alpha left")
	TEST_ASSERT_EQUAL(old_glow.pixel_x, 0, "no offset left")
	TEST_ASSERT_EQUAL(old_glow.pixel_y, 0, "no offset left")
	TEST_ASSERT(!(old_glow in H.images()), "a pooled image is not held")
	// Dirty the pooled images as a careless user might: acquiring must overwrite every one of these.
	old_glow.color = "#12ab34"
	old_glow.alpha = 17
	old_glow.pixel_x = 99
	old_glow.pixel_y = -99
	old_glow.plane = 3
	old_glow.icon = 'icons/effects/light_overlays/light_96.dmi'
	image_anchor(old_glow, LT)
	var/reused = GLOB.client_glow_holder_reused
	made = GLOB.client_glow_holder_made
	H.view_at(A, 7, 7)
	var/list/entry = H.entry_of(S)
	TEST_ASSERT_NOTNULL(entry, "acquired again on the way back")
	TEST_ASSERT_EQUAL(entry[1], old_glow, "the glow image is the pooled one")
	TEST_ASSERT_EQUAL(entry[2], old_hide, "the hide image is the pooled one")
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_reused, reused + 2, "both images count as reused")
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_made, made + 1, "and the glow counts as put on the client")
	TEST_ASSERT_EQUAL(H.pool_sizes()[1], 0, "the pool is empty again")
	var/image/glow_image = entry[1]
	var/image/hide_image = entry[2]
	var/turf/stand = glow_image.loc
	TEST_ASSERT(isturf(stand) && H.seen[stand], "it stands on a turf the eye saw")
	TEST_ASSERT_EQUAL(glow_image.plane, S.glow.plane, "no stale plane")
	TEST_ASSERT_EQUAL(glow_image.color, S.glow.color, "no stale colour")
	TEST_ASSERT_EQUAL(glow_image.alpha, S.glow.alpha, "no stale alpha")
	TEST_ASSERT_EQUAL(stand.x + (glow_image.pixel_x - S.glow.pixel_x) / WORLD_ICON_SIZE, LT.x, "its x offset puts it on the light")
	TEST_ASSERT_EQUAL(stand.y + (glow_image.pixel_y - S.glow.pixel_y) / WORLD_ICON_SIZE, LT.y, "its y offset puts it on the light")
	TEST_ASSERT(glow_image.icon != 'icons/effects/light_overlays/light_96.dmi' || S.glow.icon == 'icons/effects/light_overlays/light_96.dmi', "no stale picture")
	TEST_ASSERT_EQUAL(glow_image.blend_mode, BLEND_ADD, "still adds")
	TEST_ASSERT(hide_image.loc == S.glow && hide_image.override, "the hide image rides the real glow again")
	spent(H)
	TEST_ASSERT_EQUAL(H.pool_sizes()[1] + H.pool_sizes()[2], 0, "a holder that is gone keeps no pool")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The pool is bounded: past CLIENT_GLOW_POOL_MAX a dropped image is let go.
/datum/unit_test/dq_client_glow_holder_pool_is_bounded

/datum/unit_test/dq_client_glow_holder_pool_is_bounded/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/datum/client_glow_holder/H = got[2]
	var/obj/effect/overlay/client_glow/G = allocate(/obj/effect/overlay/client_glow, run_loc_floor_bottom_left)
	var/list/entries = list()
	for(var/i in 1 to CLIENT_GLOW_POOL_MAX + 5)
		entries += list(H.acquire_entry(G, TRUE))
	for(var/list/entry as anything in entries)
		H.release_entry(entry)
	TEST_ASSERT_EQUAL(H.pool_sizes()[1], CLIENT_GLOW_POOL_MAX, "the glow pool stops at its cap")
	TEST_ASSERT_EQUAL(H.pool_sizes()[2], CLIENT_GLOW_POOL_MAX, "the hide pool stops at its cap")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The delta crossing is the full scan's answer: running straight past a light, turf by turf, it is held whenever it overlaps the reach box, is never held clear
/// of the keep box, is acquired only by the reach box, and while held keeps one and the same image.
/datum/unit_test/dq_client_glow_holder_straight_run_matches_boxes

/datum/unit_test/dq_client_glow_holder_straight_run_matches_boxes/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	var/turf/A = client_glow_test_eye(LT)
	var/step = A.x > LT.x ? 1 : -1 // away from the light
	var/r = CEILING(S.light_range, 1)
	var/held_run = 0
	var/was_held = TRUE
	var/image/last_image
	var/reused = GLOB.client_glow_holder_reused
	for(var/i in 0 to 14 * CLIENT_GLOW_CHUNK)
		var/turf/at = locate(A.x + step * 30 - step * i, A.y, A.z) // starts well clear of the light and runs toward it and past it
		if(!at)
			continue
		H.view_at(at, 7, 7)
		var/list/reach = H.reach
		var/list/keep = H.keep_reach
		var/in_reach = !(LT.x + r < reach[1] || LT.x - r > reach[3] || LT.y + r < reach[2] || LT.y - r > reach[4])
		var/in_keep = !(LT.x + r < keep[1] || LT.x - r > keep[3] || LT.y + r < keep[2] || LT.y - r > keep[4])
		var/list/entry = H.entry_of(S)
		if(in_reach)
			TEST_ASSERT_NOTNULL(entry, "a light overlapping the reach box with the eye at [at.x],[at.y] is held")
		if(!in_keep)
			TEST_ASSERT_NULL(entry, "a light clear of the keep box with the eye at [at.x],[at.y] is not held")
		if(entry)
			held_run++
			TEST_ASSERT(was_held || in_reach, "a light is acquired only by the reach box (eye at [at.x],[at.y])")
			if(was_held && last_image)
				TEST_ASSERT_EQUAL(entry[1], last_image, "the image is never replaced while held (eye at [at.x],[at.y])")
			last_image = entry[1]
		else
			last_image = null
		was_held = !!entry
	TEST_ASSERT(held_run > 0, "the run held the light")
	TEST_ASSERT(GLOB.client_glow_holder_reused > reused, "a glow taken up again after it was dropped reuses its images")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A light made after a crossing that walked no chunk is held at once (by its own event), and one that goes out is dropped without a crossing.
/datum/unit_test/dq_client_glow_holder_skipped_scan_sees_new_light

/datum/unit_test/dq_client_glow_holder_skipped_scan_sees_new_light/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	var/turf/A = client_glow_test_eye(LT)
	var/away = (A.x > LT.x ? 1 : -1) * CLIENT_GLOW_CHUNK
	var/turf/B = locate(A.x + away, A.y, A.z)
	TEST_ASSERT_NOTNULL(B, "a chunk further from the light exists")
	var/lights = 0
	for(var/key in GLOB.client_glow_chunks)
		lights += length(GLOB.client_glow_chunks[key])
	var/skipped = GLOB.client_glow_holder_scans_skipped
	H.view_at(B, 7, 7)
	if(lights == 1)
		TEST_ASSERT_EQUAL(GLOB.client_glow_holder_scans_skipped, skipped + 1, "a crossing with no light near its moved edges walks no chunk")
	TEST_ASSERT_NOTNULL(H.entry_of(S), "the first light is still kept")
	var/obj/machinery/light/N = allocate(/obj/machinery/light, B)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(N.light?.glow, "the new light glows")
	var/list/entry = H.entry_of(N.light)
	TEST_ASSERT_NOTNULL(entry, "a light that appears after a crossing is picked up with no crossing")
	var/image/new_glow = entry?[1]
	TEST_ASSERT_EQUAL(new_glow?.loc, B, "it stands on its own turf, which the eye sees")
	var/datum/light_source/N_light = N.light
	qdel(N)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NULL(H.entry_of(N_light), "a light that goes out is dropped with no crossing")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Cleanup: client lighting off, the light deleted and the viewer leaving each leave no image.
/datum/unit_test/dq_client_glow_holder_cleanup

/datum/unit_test/dq_client_glow_holder_cleanup/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/turf/E = client_glow_test_eye(get_turf(F))
	TEST_ASSERT(length(H.images()), "held before")
	client_lighting_set(FALSE)
	TEST_ASSERT_EQUAL(length(H.images()), 0, "client lighting off: no image")
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	H.view_at(E, 7, 7)
	var/datum/light_source/S = F.light
	TEST_ASSERT_NOTNULL(H.entry_of(S), "held again")
	var/list/copy = H.entry_of(S)
	qdel(S)
	TEST_ASSERT_NULL(H.entry_of(S), "light deleted: its copy is dropped")
	for(var/image/I as anything in copy)
		TEST_ASSERT(!(I in H.images()), "light deleted: none of its images is left")
	spent(H)
	TEST_ASSERT(!(H in REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS)), "a gone viewer is not walked")
	TEST_ASSERT_EQUAL(LAZYLEN(H.held), 0, "a gone viewer holds nothing")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

// ---- compare mode (client_lighting_compare.dm) ----

/// Compare mode runs both engines: a lit fixture keeps its glow (on the glow plane) and its turf gets a lighting object, every
/// dynamic turf has one and stays shown to BYOND; switching off goes back to glows alone; client lighting off ends it too.
/datum/unit_test/dq_client_lighting_compare

/datum/unit_test/dq_client_lighting_compare/Run()
	for(var/screen_var in list(nameof(GLOB.client_glow_plane_master), nameof(GLOB.client_glow_base), nameof(GLOB.client_glow_compare_base), nameof(GLOB.client_glow_relay), nameof(GLOB.client_walls_plane_master), nameof(GLOB.client_spread_plane_master), nameof(GLOB.client_visible_plane_master), nameof(GLOB.client_glow_spread_relay)))
		set_global(screen_var, GLOB.vars[screen_var]) // the shared screen objects are made on first use; teardown restores
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the modes off for the next test
	set_global(nameof(GLOB.client_lighting_compare), FALSE)
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	client_lighting_compare_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = L.light
	TEST_ASSERT(GLOB.client_lighting, "compare mode turns client lighting on")
	TEST_ASSERT_NOTNULL(S?.glow, "compare: the light glows")
	TEST_ASSERT_EQUAL(S.glow.plane, PLANE_CLIENT_GLOW, "compare: the glow is on the glow plane")
	TEST_ASSERT_NOTNULL(T.lighting_object, "compare: the lit turf has its lighting object")
	var/turf/far = run_loc_floor_top_right
	TEST_ASSERT(!far.has_dynamic_lighting() || far.lighting_object, "compare: every dynamic turf has a lighting object")
	TEST_ASSERT_EQUAL(T.luminosity, 1, "compare: the turf stays shown for the glows")
	TEST_ASSERT(T.lighting_corners_lit(), "compare: the corners carry the light too")
	var/list/dm_screen = client_glow_screen(CLIENT_GLOW_SCREEN_COMPARE_DM)
	var/list/glow_screen = client_glow_screen(CLIENT_GLOW_SCREEN_COMPARE_GLOW)
	TEST_ASSERT(!(GLOB.client_glow_relay in dm_screen), "the DM view does not relay the glow plane")
	TEST_ASSERT(GLOB.client_glow_relay in glow_screen, "the client view relays the glow plane")
	TEST_ASSERT(GLOB.client_glow_compare_base in glow_screen, "the client view has the glow plane's black base")
	TEST_ASSERT(GLOB.client_glow_plane_master in dm_screen, "the DM view hides the glow plane behind its master")
	TEST_ASSERT_EQUAL(GLOB.client_glow_relay.render_source, GLOB.client_glow_plane_master.render_target, "the relay draws the glow plane's render target")
	TEST_ASSERT(findtext(GLOB.client_glow_plane_master.render_target, "*") == 1, "the glow plane renders only as a hidden target")
	client_lighting_compare_set(FALSE)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(GLOB.client_lighting, "compare off keeps client lighting")
	TEST_ASSERT_NULL(T.lighting_object, "compare off: no lighting object")
	TEST_ASSERT_EQUAL(S.glow?.plane, PLANE_CLIENT_GLOW, "compare off: the glow stays on the glow plane")
	TEST_ASSERT(!T.lighting_corners_lit(), "compare off: the corners hold no light")
	client_lighting_compare_set(TRUE)
	SSlighting.light_step(0, TRUE)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(!GLOB.client_lighting_compare, "client lighting off ends compare mode")
	TEST_ASSERT_NULL(S.glow, "client lighting off: no glow")
	TEST_ASSERT_NOTNULL(T.lighting_object, "client lighting off: the DM lighting is back")

/// The dark base: in client mode every client's screen holds a black base on the lighting plane, under the glows (an unlit
/// turf would otherwise multiply by nothing and show fully bright), and a turf outside dynamic lighting carries a white tile
/// over it; DM mode shows neither.
/datum/unit_test/dq_client_lighting_dark_base

/datum/unit_test/dq_client_lighting_dark_base/Run()
	for(var/screen_var in list(nameof(GLOB.client_glow_plane_master), nameof(GLOB.client_glow_base), nameof(GLOB.client_glow_compare_base), nameof(GLOB.client_glow_relay), nameof(GLOB.client_walls_plane_master), nameof(GLOB.client_spread_plane_master), nameof(GLOB.client_visible_plane_master), nameof(GLOB.client_glow_spread_relay)))
		set_global(screen_var, GLOB.vars[screen_var]) // the shared screen objects are made on first use; teardown restores
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	TEST_ASSERT_EQUAL(length(client_glow_screen(client_glow_screen_state(null))), 0, "DM lighting: no base on the screen")
	var/turf/fixed
	for(var/turf/T as anything in block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz)))
		if(!T.has_dynamic_lighting())
			fixed = T
			break
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	// Boot path: the map's turfs initialize before the config turns the mode on, at the DM engine's luminosity 0.
	var/turf/dynamic
	for(var/turf/T as anything in block(locate(1, 1, 1), locate(world.maxx, world.maxy, world.maxz)))
		if(T.has_dynamic_lighting())
			dynamic = T
			break
	TEST_ASSERT(dynamic, "the map has a dynamic turf")
	var/old_luminosity = dynamic.luminosity
	dynamic.luminosity = 0
	create_all_lighting_objects()
	TEST_ASSERT_EQUAL(dynamic.luminosity, 1, "boot in client mode shows a dynamic turf that initialized dark")
	dynamic.luminosity = old_luminosity
	var/list/screen = client_glow_screen(client_glow_screen_state(null))
	TEST_ASSERT(GLOB.client_glow_base in screen, "client lighting: the screen holds the black base")
	TEST_ASSERT(GLOB.client_glow_spread_relay in screen, "client lighting: the screen holds the spread relay")
	TEST_ASSERT_EQUAL(GLOB.client_glow_spread_relay.screen_loc, "1,1", "the relay stands at 1,1: at CENTER it draws shifted")
	TEST_ASSERT_EQUAL(length(GLOB.client_glow_plane_master.filters), 3, "the glow plane is cut by the visibility plane, loses opaque tiles and is softened")
	TEST_ASSERT_EQUAL(length(GLOB.client_spread_plane_master.filters), 2, "the spread plane is bloomed and limited to opaque tiles")
	var/atom/movable/screen/plane_master/lighting/lit_master = new
	client_glow_master_compose(lit_master)
	TEST_ASSERT_EQUAL(length(lit_master.filters), 4, "the lighting master keeps its two emissive masks and adds the glow plane and the spread")
	QDEL_NULL(lit_master)
	var/turf/wall_tile = run_loc_floor_bottom_left
	var/old_opacity_dirs = wall_tile.directional_opacity
	wall_tile.directional_opacity = ALL_CARDINALS
	wall_tile.client_glow_wall_sync()
	TEST_ASSERT(client_walls_tile() in wall_tile.underlays, "an opaque turf is on the walls plane")
	wall_tile.directional_opacity = NONE
	wall_tile.client_glow_wall_sync()
	TEST_ASSERT(!(client_walls_tile() in wall_tile.underlays), "a clear turf is not on the walls plane")
	wall_tile.directional_opacity = old_opacity_dirs
	for(var/area/shown_area in world)
		TEST_ASSERT(shown_area.client_visible_shown, "client lighting: [shown_area.type] draws the visibility tile")
		break
	TEST_ASSERT((GLOB.client_visible_plane_master in screen) && (GLOB.client_walls_plane_master in screen) && (GLOB.client_spread_plane_master in screen), "client lighting: the screen holds the hidden planes")
	var/atom/movable/screen/client_glow_base/B = GLOB.client_glow_base
	TEST_ASSERT_EQUAL(B.plane, PLANE_LIGHTING, "the base is on the lighting plane")
	TEST_ASSERT_EQUAL(B.color, "#000000", "the base is black")
	TEST_ASSERT_EQUAL((CLIENT_GLOW_LAYER < BACKGROUND_LAYER && CLIENT_GLOW_LAYER > 0), TRUE, "the glows are on an ordinary layer, drawn over the screen base")
	var/mutable_appearance/white = CACHED_FAST(client_glow_white_tiles, "[PLANE_LIGHTING]")
	TEST_ASSERT(white.layer < BACKGROUND_LAYER && white.layer < CLIENT_GLOW_LAYER, "a white tile sits between the base and the glows")
	TEST_ASSERT(!(white in run_loc_floor_bottom_left.underlays), "a dynamic floor has no white tile")
	if(fixed)
		var/area/FA = fixed.loc
		TEST_ASSERT((white in fixed.underlays) || client_glow_area_white(FA) == white, "a turf outside dynamic lighting ([fixed.type] in [FA.type]) carries a white tile, its own or its area's")
	log_test("CLIENT DARK BASE: [client_glow_whites_set(TRUE)] area(s) and turf(s) outside dynamic lighting carry a white tile")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_EQUAL(length(client_glow_screen(client_glow_screen_state(null))), 0, "DM lighting again: no base")
	if(fixed)
		var/area/FA2 = fixed.loc
		TEST_ASSERT(!(white in fixed.underlays) && !client_glow_area_white(FA2), "DM lighting again: the white tile is gone")

/// Every hidden master the lighting composition reads must be drawn: the base plane master starts at alpha 0, which renders an empty target.
/datum/unit_test/dq_client_lighting_masters_opaque

/datum/unit_test/dq_client_lighting_masters_opaque/Run()
	for(var/path in list(/atom/movable/screen/plane_master/client_glow, /atom/movable/screen/plane_master/client_visible, /atom/movable/screen/plane_master/client_walls, /atom/movable/screen/plane_master/client_spread))
		var/atom/movable/screen/plane_master/M = new path
		TEST_ASSERT_EQUAL(M.alpha, 255, "[path]: a hidden render target at alpha 0 is empty")
		qdel(M)
	return TRUE

/// A door opening grows a light's reach, so its old cut must not stand in; a door closing shrinks it, so the old cut may.
/datum/unit_test/dq_client_lighting_shape_grew/Run()
	TEST_ASSERT(client_glow_shape_grew("80|0,0|1,0", "80|0,0,1,0|"), "a newly reached tile is growth")
	TEST_ASSERT(!client_glow_shape_grew("80|0,0,1,0|", "80|0,0|1,0"), "a lost tile is not growth")
	TEST_ASSERT(!client_glow_shape_grew("80|0,0|", "80|0,0|"), "the same reach is not growth")

/// A wide-open bake is the plain sprite, pixel for pixel, so swapping plain for baked cannot move a glow; a stored shape loads without a bake.
/datum/unit_test/dq_client_lighting_bake_matches_plain

/datum/unit_test/dq_client_lighting_bake_matches_plain/Run()
	var/list/tiles = list()
	for(var/dx in -5 to 5)
		for(var/dy in -5 to 5)
			tiles += "[dx],[dy]"
	var/key = "160|[jointext(tiles, ",")]|"
	var/started = REALTIMEOFDAY
	for(var/i in 1 to 10)
		var/timed = client_glow_mask_bake_blocking(key)
		fdel(timed)
	log_world("client glow test: one open range 6 bake takes [(REALTIMEOFDAY - started) / 10] ds")
	var/png = client_glow_mask_bake_blocking(key)
	TEST_ASSERT_NOTNULL(png, "baked")
	var/icon/baked = icon(file(png))
	var/icon/plain = icon(client_glow_icon(352), "light")
	TEST_ASSERT_EQUAL(baked.Width(), plain.Width(), "same width")
	TEST_ASSERT_EQUAL(baked.Height(), plain.Height(), "same height")
	var/worst = 0
	for(var/x = 4, x <= 352, x += 12)
		for(var/y = 4, y <= 352, y += 12)
			var/a = client_lighting_test_alpha(baked.GetPixel(x, y))
			var/b = client_lighting_test_alpha(plain.GetPixel(x, y))
			worst = max(worst, abs(a - b))
	log_world("client glow test: worst bake-against-plain alpha difference [worst]")
	TEST_ASSERT(worst <= 2, "the bake lines up with the plain sprite (worst alpha difference [worst])")
	GLOB.client_glow_baker.store_on = TRUE
	var/store = client_glow_store_path(key)
	fcopy(png, store)
	fdel(png)
	GLOB.client_glow_baker.icons -= key
	var/loads = GLOB.client_glow_baker.stored_loads
	TEST_ASSERT_NOTNULL(client_glow_mask_icon(key), "a stored shape is ready at once")
	TEST_ASSERT_EQUAL(GLOB.client_glow_baker.stored_loads, loads + 1, "it came from the store")
	TEST_ASSERT(!GLOB.client_glow_baker.pending[key], "nothing was queued")
	GLOB.client_glow_baker.store_on = FALSE
	GLOB.client_glow_baker.icons -= key
	fdel(store)
