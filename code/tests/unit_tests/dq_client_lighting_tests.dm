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

/// Marks every client lighting counter a test may move, so teardown restores them.
/datum/unit_test/proc/client_glow_counters_restore()
	for(var/counter in list(nameof(GLOB.client_glow_holder_made), nameof(GLOB.client_glow_holder_updated), nameof(GLOB.client_glow_holder_dropped), nameof(GLOB.client_glow_holder_recomputes), nameof(GLOB.client_glow_holder_reused), nameof(GLOB.client_glow_holder_scans_skipped), nameof(GLOB.client_glow_holder_stands_moved), nameof(GLOB.client_glow_holder_chunk_visits), nameof(GLOB.client_glow_holder_sight_refreshes), nameof(GLOB.client_glow_trace_lines), nameof(GLOB.client_glow_flushes), nameof(GLOB.client_glow_flush_changes), nameof(GLOB.client_glow_reconsiders), nameof(GLOB.client_glow_mask_builds), nameof(GLOB.client_flat_light_refreshes), nameof(GLOB.client_flat_light_recolours), nameof(GLOB.client_flat_light_makes), nameof(GLOB.client_glow_twins_made), nameof(GLOB.client_glow_twin_hits)))
		set_global(counter, GLOB.vars[counter])

/// A lit fixture with client lighting on, and a holder (no client) seeing from just off the light's screen.
/datum/unit_test/proc/client_glow_holder_setup(list/out)
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	client_glow_counters_restore()
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
		var/moved = GLOB.client_glow_holder_stands_moved
		H.refresh_stands() // the full pass: the delta crossing's stand upkeep left nothing for it to move
		TEST_ASSERT_EQUAL(GLOB.client_glow_holder_stands_moved, moved, "a delta crossing leaves every stand where a full pass puts it (eye at [at.x],[at.y])")
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
	var/list/indexed = list()
	for(var/key in GLOB.client_glow_chunks)
		for(var/datum/light_source/indexed_light as anything in GLOB.client_glow_chunks[key])
			indexed[indexed_light] = TRUE
	var/lights = length(indexed)
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

/// The keys of the glows a holder holds, as a sorted text (to compare two holders).
/datum/unit_test/proc/client_glow_held_keys(datum/client_glow_holder/H)
	var/list/keys = list()
	for(var/h in H.held)
		keys += "[h]"
	return jointext(sortTim(keys, GLOBAL_PROC_REF(cmp_text_asc)), ",")

/// Runs a spread scan's remaining steps by hand (what its timer does a tick at a time). Returns how many it took.
/datum/unit_test/proc/client_glow_finish_scan(datum/client_glow_holder/H, limit = 200)
	var/steps = 0
	while(H.scan_chunks && steps < limit)
		H.scan_continue()
		steps++
	return steps

/// A full scan with a budget walks the chunks nearest the eye first and finishes on later steps: after the first step the light at the eye is held and a light a chunk away is not,
/// and once the scan is done the holder holds exactly what a scan in one go holds.
/datum/unit_test/dq_client_glow_holder_spread_scan_nearest_first

/datum/unit_test/dq_client_glow_holder_spread_scan_nearest_first/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/whole = got[2]
	var/turf/E = client_glow_test_eye(get_turf(F))
	var/obj/machinery/light/G = allocate(/obj/machinery/light, E) // in the eye's own chunk
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(G.light?.glow, "the light at the eye glows")
	var/datum/client_glow_holder/spread = new
	spread.scan_budget_ms = 0 // a step walks one chunk
	spread.view_at(E, 7, 7)
	TEST_ASSERT_NOTNULL(spread.scan_chunks, "the first step leaves chunks for the next ticks")
	TEST_ASSERT(!spread.scanned, "an unfinished scan is not a scan the next crossing can start from")
	TEST_ASSERT_NOTNULL(spread.entry_of(G.light), "the step that ran in the call holds the light at the eye")
	TEST_ASSERT_NULL(spread.entry_of(F.light), "a light a chunk or two away waits for a later step")
	var/steps = client_glow_finish_scan(spread)
	TEST_ASSERT(steps > 1, "the rest took several steps ([steps])")
	TEST_ASSERT_NULL(spread.scan_chunks, "the scan closed")
	TEST_ASSERT(spread.scanned, "and is a scan the next crossing can start from")
	TEST_ASSERT_NOTNULL(spread.entry_of(F.light), "the farther light is held once the scan is done")
	TEST_ASSERT_EQUAL(client_glow_held_keys(spread), client_glow_held_keys(whole), "a spread scan holds what the scan in one go holds")
	spent(spread)
	spent(whole)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A crossing while a scan is unfinished, and a teleport, end in the same state a scan in one go gives; a delta crossing after the scan finished is correct too.
/datum/unit_test/dq_client_glow_holder_crossing_during_spread_scan

/datum/unit_test/dq_client_glow_holder_crossing_during_spread_scan/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/first = got[2]
	var/turf/LT = get_turf(F)
	var/turf/A = client_glow_test_eye(LT)
	var/side = A.x > LT.x ? 1 : -1
	var/turf/B = locate(A.x + side * CLIENT_GLOW_CHUNK, A.y, A.z) // the next chunk away from the light
	var/turf/C = locate(A.x - side * CLIENT_GLOW_CHUNK, A.y, A.z) // and the next one toward it
	TEST_ASSERT(B && C, "the chunks beside the eye exist")
	var/obj/machinery/light/G = allocate(/obj/machinery/light, B)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(G.light?.glow, "the second light glows")
	var/datum/client_glow_holder/spread = new
	spread.scan_budget_ms = 0
	spread.view_at(A, 7, 7)
	TEST_ASSERT_NOTNULL(spread.scan_chunks, "unfinished after the first step")
	spread.view_at(B, 7, 7) // the eye crosses a chunk before the scan is done
	TEST_ASSERT(!spread.scanned, "a new full scan is under way, not a delta")
	client_glow_finish_scan(spread)
	var/datum/client_glow_holder/direct = new
	direct.view_at(B, 7, 7)
	TEST_ASSERT_EQUAL(client_glow_held_keys(spread), client_glow_held_keys(direct), "a crossing during a spread scan ends where a scan from there in one go ends")
	spread.view_at(C, 7, 7) // a delta crossing from the finished scan
	client_glow_finish_scan(spread)
	var/datum/client_glow_holder/direct_c = new
	direct_c.view_at(C, 7, 7)
	for(var/h in direct_c.held) // a delta crossing also keeps what the keep box still covers, so it holds at least what a scan from there holds
		TEST_ASSERT(!isnull(LAZYACCESS(spread.held, h)), "a crossing after the scan finished holds every glow a scan from there in one go holds")
	// A teleport far from the old boxes while a scan is unfinished.
	var/turf/far = locate(min(world.maxx, A.x + 6 * CLIENT_GLOW_CHUNK), A.y, A.z)
	var/datum/client_glow_holder/jumper = new
	jumper.scan_budget_ms = 0
	jumper.view_at(A, 7, 7)
	jumper.view_at(far, 7, 7)
	client_glow_finish_scan(jumper)
	var/datum/client_glow_holder/direct_far = new
	direct_far.view_at(far, 7, 7)
	TEST_ASSERT_EQUAL(client_glow_held_keys(jumper), client_glow_held_keys(direct_far), "a teleport during a spread scan ends where a scan from the new place in one go ends")
	for(var/datum/client_glow_holder/H as anything in list(first, spread, direct, direct_c, jumper, direct_far))
		spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A light made or put out while a scan is unfinished is held or dropped at once by its own event, and the scan's end neither loses nor resurrects it.
/datum/unit_test/dq_client_glow_holder_light_events_during_spread_scan

/datum/unit_test/dq_client_glow_holder_light_events_during_spread_scan/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/first = got[2]
	var/turf/E = client_glow_test_eye(get_turf(F))
	var/datum/client_glow_holder/spread = new
	spread.scan_budget_ms = 0
	spread.view_at(E, 7, 7)
	TEST_ASSERT_NOTNULL(spread.scan_chunks, "unfinished after the first step")
	var/obj/machinery/light/N = allocate(/obj/machinery/light, E)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(spread.entry_of(N.light), "a light that appears mid-scan is held by its own event")
	var/datum/light_source/gone = F.light
	qdel(F)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NULL(spread.entry_of(gone), "a light that goes out mid-scan is dropped by its own event")
	client_glow_finish_scan(spread)
	TEST_ASSERT_NOTNULL(spread.entry_of(N.light), "the new light is still held once the scan is done")
	TEST_ASSERT_NULL(spread.entry_of(gone), "the light that went out is not held again by the scan")
	TEST_ASSERT_EQUAL(client_glow_held_keys(spread), client_glow_held_keys(first), "and the holder matches one that saw the same events")
	spent(spread)
	spent(first)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A login wipe or a drop-all ends the scan under way: no later step puts a glow back, and the next eye update starts a whole scan.
/datum/unit_test/dq_client_glow_holder_wipe_cancels_spread_scan

/datum/unit_test/dq_client_glow_holder_wipe_cancels_spread_scan/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/first = got[2]
	var/turf/E = client_glow_test_eye(get_turf(F))
	var/datum/client_glow_holder/spread = new
	spread.scan_budget_ms = 0
	spread.view_at(E, 7, 7)
	TEST_ASSERT_NOTNULL(spread.scan_chunks, "unfinished after the first step")
	spread.forget_images() // what a login's wipe of client.images does
	TEST_ASSERT_NULL(spread.scan_chunks, "the wipe ends the scan")
	TEST_ASSERT_EQUAL(LAZYLEN(spread.held), 0, "and the held glows are forgotten")
	spread.scan_continue() // a timer that was waiting
	TEST_ASSERT_EQUAL(LAZYLEN(spread.held), 0, "a waiting step finds nothing to do")
	spread.view_at(E, 7, 7)
	TEST_ASSERT_NOTNULL(spread.scan_chunks, "the next eye update starts a scan again")
	client_glow_finish_scan(spread)
	TEST_ASSERT_EQUAL(client_glow_held_keys(spread), client_glow_held_keys(first), "and it ends holding what the first scan held")
	spread.drop_all("test")
	TEST_ASSERT_NULL(spread.scan_chunks, "a drop-all leaves no scan pending")
	spent(spread)
	spent(first)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The timer finishes a spread scan with no one calling: a few ticks after the first step the scan is done.
/datum/unit_test/dq_client_glow_holder_spread_scan_timer_finishes

/datum/unit_test/dq_client_glow_holder_spread_scan_timer_finishes/Run()
	test_driver_begin()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/first = got[2]
	var/turf/E = client_glow_test_eye(get_turf(F))
	var/datum/client_glow_holder/spread = new
	spread.scan_budget_ms = 0
	spread.view_at(E, 7, 7)
	TEST_ASSERT_NOTNULL(spread.scan_chunks, "unfinished after the first step")
	TEST_ASSERT(spread.scan_waiting, "a timer waits for the next step")
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(spread.scan_chunks, "the timer's steps finished the scan")
	TEST_ASSERT(spread.scanned, "and closed it")
	TEST_ASSERT_EQUAL(client_glow_held_keys(spread), client_glow_held_keys(first), "holding what a scan in one go holds")
	spent(spread)
	spent(first)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	test_driver_end()

/// A delta crossing that brings lights into reach queues them: its call makes no glow, and the queue makes them a budgeted step at a time on the ticks after, to the same state a viewer
/// with no budget reaches at once.
/datum/unit_test/dq_client_glow_holder_crossing_acquire_is_budgeted

/datum/unit_test/dq_client_glow_holder_crossing_acquire_is_budgeted/Run()
	test_driver_begin()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/whole = got[2]
	var/turf/LT = get_turf(F)
	var/turf/E = client_glow_test_eye(LT)
	var/obj/machinery/light/G = allocate(/obj/machinery/light, locate(LT.x + 1, LT.y, LT.z))
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(G.light?.glow, "the second light glows")
	var/step = (E.x > LT.x ? 1 : -1) * CLIENT_GLOW_CHUNK
	var/turf/far
	for(var/chunks in 6 to 3 step -1)
		far = locate(E.x + step * chunks, E.y, E.z)
		if(far)
			break
	TEST_ASSERT_NOTNULL(far, "a chunk far from the lights exists")
	var/datum/client_glow_holder/lazy = new
	lazy.acquire_budget_ms = 0 // a step makes one glow
	lazy.view_at(far, 7, 7)
	lazy.scan_cancel()
	lazy.scanned = TRUE
	TEST_ASSERT_NULL(lazy.entry_of(F.light), "far from the lights, nothing is held")
	var/turf/at = far
	for(var/chunks in 1 to 12)
		if(lazy.acquire_queue)
			break
		at = locate(at.x - step, at.y, at.z)
		if(!at)
			break
		lazy.view_at(at, 7, 7)
	TEST_ASSERT_NOTNULL(lazy.acquire_queue, "a crossing that brings the lights into reach queues them")
	var/queued = length(lazy.acquire_queue)
	TEST_ASSERT(queued >= 2, "both lights are queued ([queued])")
	TEST_ASSERT_NULL(lazy.entry_of(F.light), "and the crossing itself made no glow")
	var/made = GLOB.client_glow_holder_made
	lazy.acquire_continue()
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_made - made, 1, "a step with no budget left makes one glow")
	TEST_ASSERT_EQUAL(length(lazy.acquire_queue), queued - 1, "and leaves the rest queued")
	test_time(5 SECONDS)
	TEST_ASSERT_NULL(lazy.acquire_queue, "the timer finished the queue")
	TEST_ASSERT_NOTNULL(lazy.entry_of(F.light), "the light is held once its turn came")
	TEST_ASSERT_NOTNULL(lazy.entry_of(G.light), "so is the second")
	var/datum/client_glow_holder/direct = new // no budget: the crossing takes the lights at once
	direct.view_at(far, 7, 7)
	var/turf/there = far
	for(var/chunks in 1 to 12)
		if(direct.entry_of(F.light))
			break
		there = locate(there.x - step, there.y, there.z)
		if(!there)
			break
		direct.view_at(there, 7, 7)
	TEST_ASSERT_NULL(direct.acquire_queue, "a viewer with no budget queues nothing")
	TEST_ASSERT_NOTNULL(direct.entry_of(F.light), "and holds the light as its crossing ends")
	spent(direct)
	spent(lazy)
	spent(whole)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	test_driver_end()

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
	client_glow_counters_restore()
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
	GLOB.client_glow_baker.icons -= key
	fdel(png)

/// A sprite bigger than a tile is lit as the turf it stands on: under client lighting it carries a flat light whose grey is that
/// turf's level, a normal-sized atom carries none, the grey follows a light coming and going and the atom moving, and the flat
/// light goes with the mode, with the size and with the atom.
/datum/unit_test/dq_client_flat_light_big_mob

/datum/unit_test/dq_client_flat_light_big_mob/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	client_glow_counters_restore()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/east = locate(T.x + 12, T.y, T.z)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/small = allocate(/mob/living/carbon/human, T)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	H.resize(2, animate = FALSE, uncapped = TRUE, ignore_prefs = TRUE)
	small.update_transform(TRUE)
	TEST_ASSERT_NOTNULL(H.flat_light, "a double-size character has a flat light")
	TEST_ASSERT_NULL(small.flat_light, "a normal-size character has none")
	TEST_ASSERT_EQUAL(H.flat_light.plane, PLANE_CLIENT_GLOW, "the flat light is on the glow plane, so it replaces the glows instead of being added to by them")
	TEST_ASSERT(H.plane < PLANE_LIGHTING, "a character is drawn under the lighting plane's multiplication ([H.plane])")
	TEST_ASSERT(!(H.appearance_flags & PLANE_MASTER), "a character is not a plane master")
	TEST_ASSERT(H.flat_light.layer > CLIENT_GLOW_LAYER, "it is drawn above every glow")
	TEST_ASSERT_EQUAL(H.flat_light.render_source, H.render_target, "it copies the atom's own sprite")
	TEST_ASSERT(registry_has(REGISTRY_CLIENT_FLAT_LIT, H) && !registry_has(REGISTRY_CLIENT_FLAT_LIT, small), "only the big atom is registered")
	var/dark_key = H.flat_light.lit_key
	TEST_ASSERT_EQUAL(dark_key, client_flat_light_key(client_flat_light_rgb(T)), "its colour is the light its turf is drawn with")
	// A light on the turf lifts the colour without anything asking the atom.
	allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(H.flat_light.lit_key > dark_key, "a light on its turf raises its colour ([dark_key] -> [H.flat_light.lit_key])")
	TEST_ASSERT_EQUAL(H.flat_light.lit_key, client_flat_light_key(client_flat_light_rgb(T)), "and the colour is the turf's again")
	// Moving to an unlit turf follows the turf.
	if(east && !east.directional_opacity)
		H.forceMove(east)
		client_flat_light_update(H) // the moved notice does this in play; the test clock does not deliver it here
		TEST_ASSERT_EQUAL(H.flat_light.lit_key, client_flat_light_key(client_flat_light_rgb(east)), "after a move it takes the new turf's light")
	var/recolours = GLOB.client_flat_light_recolours
	client_flat_light_update(H)
	TEST_ASSERT_EQUAL(GLOB.client_flat_light_recolours, recolours, "an unchanged level rewrites nothing")
	log_test("CLIENT FLAT LIGHT: [GLOB.client_flat_light_makes] made, [GLOB.client_flat_light_recolours] recolours")
	// Shrinking it back takes the flat light away.
	H.resize(1, animate = FALSE, uncapped = TRUE, ignore_prefs = TRUE)
	TEST_ASSERT_NULL(H.flat_light, "back to normal size: no flat light")
	TEST_ASSERT(!registry_has(REGISTRY_CLIENT_FLAT_LIT, H), "and it left the registry")
	H.resize(2, animate = FALSE, uncapped = TRUE, ignore_prefs = TRUE)
	TEST_ASSERT_NOTNULL(H.flat_light, "big again: it has one")
	client_lighting_set(FALSE)
	TEST_ASSERT_NULL(H.flat_light, "DM lighting: no flat light")

/// A delivery answer that arrives after forget_images() (a login emptied the client's images) belongs to a client state that is gone: it marks nothing
/// delivered. An answer under the current generation marks the shape.
/datum/unit_test/dq_client_glow_delivery_stale_after_reset

/datum/unit_test/dq_client_glow_delivery_stale_after_reset/Run()
	var/datum/client_glow_holder/H = new
	var/gen = H.delivery_gen
	H.forget_images()
	TEST_ASSERT(H.delivery_gen != gen, "forgetting the images starts a new delivery generation")
	H.client_glow_delivered("stale_shape", null, gen, REALTIMEOFDAY)
	TEST_ASSERT(!LAZYACCESS(H.delivered, "stale_shape"), "an answer from before the reset marks nothing delivered")
	H.client_glow_delivered("fresh_shape", null, H.delivery_gen, REALTIMEOFDAY)
	TEST_ASSERT(LAZYACCESS(H.delivered, "fresh_shape"), "an answer of the current generation marks its shape delivered")
	spent(H)

/// The delivered record is bounded: past CLIENT_GLOW_MASK_CACHE_MAX it drops its oldest entries in one cut, newest kept.
/datum/unit_test/dq_client_glow_delivered_bounded

/datum/unit_test/dq_client_glow_delivered_bounded/Run()
	var/datum/client_glow_holder/H = new
	for(var/i in 1 to CLIENT_GLOW_MASK_CACHE_MAX)
		H.note_delivered("shape[i]")
	TEST_ASSERT_EQUAL(length(H.delivered), CLIENT_GLOW_MASK_CACHE_MAX, "at the limit nothing is dropped")
	H.note_delivered("newest")
	TEST_ASSERT(length(H.delivered) <= round(CLIENT_GLOW_MASK_CACHE_MAX * 0.75), "past the limit the record shrinks well below it ([length(H.delivered)])")
	TEST_ASSERT(LAZYACCESS(H.delivered, "newest"), "the newest entry is kept")
	TEST_ASSERT(!LAZYACCESS(H.delivered, "shape1"), "the oldest entry is dropped")
	TEST_ASSERT(LAZYACCESS(H.delivered, "shape[CLIENT_GLOW_MASK_CACHE_MAX]"), "the entry before the newest is kept")
	spent(H)

// ---- the reach index, crossings that walk only their edges, batched opacity, sight between crossings, tracing

/// A light is indexed under every chunk its reach box overlaps, and under no other; it follows the light when it moves and leaves with it.
/datum/unit_test/dq_client_glow_index_covers_reach_box

/datum/unit_test/dq_client_glow_index_covers_reach_box/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	client_glow_counters_restore()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/light/F = allocate(/obj/machinery/light, T)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = F.light
	TEST_ASSERT_NOTNULL(S?.glow_chunk_box, "a glowing light is indexed")
	var/r = CLIENT_GLOW_RADIUS(S)
	var/list/box = glow_reach_box(T, r)
	var/expected = 0
	var/found = 0
	for(var/gx in -1 to world.maxx / CLIENT_GLOW_CHUNK + 1)
		for(var/gy in -1 to world.maxy / CLIENT_GLOW_CHUNK + 1)
			var/list/chunk_box = list(gx * CLIENT_GLOW_CHUNK + 1, gy * CLIENT_GLOW_CHUNK + 1, gx * CLIENT_GLOW_CHUNK + CLIENT_GLOW_CHUNK, gy * CLIENT_GLOW_CHUNK + CLIENT_GLOW_CHUNK)
			var/overlaps = glow_boxes_overlap(box, chunk_box) && gx >= 0 && gy >= 0
			var/indexed = (S in GLOB.client_glow_chunks[client_glow_chunk_id(T.z, gx, gy)])
			if(overlaps)
				expected++
			if(indexed)
				found++
			TEST_ASSERT_EQUAL(!!indexed, !!overlaps, "the light is indexed under chunk [gx],[gy] exactly when its reach box [box[1]],[box[2]] to [box[3]],[box[4]] overlaps it")
	TEST_ASSERT_EQUAL(found, expected, "and under no other chunk")
	var/turf/far = locate(T.x + CLIENT_GLOW_CHUNK * 2, T.y, T.z)
	if(far)
		F.forceMove(far)
		SSlighting.light_step(0, TRUE)
		S = F.light
		var/list/moved_box = glow_reach_box(far, r)
		var/moved_found = 0
		for(var/key in GLOB.client_glow_chunks)
			if(S in GLOB.client_glow_chunks[key])
				moved_found++
		var/list/moved_chunks = glow_chunk_range(list(max(moved_box[1], 1), max(moved_box[2], 1), min(moved_box[3], world.maxx), min(moved_box[4], world.maxy))) // the index stays on the map
		TEST_ASSERT_EQUAL(moved_found, (moved_chunks[3] - moved_chunks[1] + 1) * (moved_chunks[4] - moved_chunks[2] + 1), "after a move the light is under the chunks of its new reach box only")
	var/datum/light_source/gone = S
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	for(var/key in GLOB.client_glow_chunks)
		TEST_ASSERT(!(gone in GLOB.client_glow_chunks[key]), "a light that stopped glowing is in no chunk ([key])")

/// A crossing of one chunk looks in exactly the chunks the three strips cover (the part of the new reach box the old did not cover, the same for the box grown by a
/// chunk, and the part of the old keep box the new does not cover): no range grows them, so the walk is the edges of the boxes, well under a full scan.
/datum/unit_test/dq_client_glow_holder_crossing_walks_edge_chunks

/datum/unit_test/dq_client_glow_holder_crossing_walks_edge_chunks/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/datum/client_glow_holder/H = got[2]
	var/obj/machinery/light/F = got[1]
	var/turf/A = client_glow_test_eye(get_turf(F))
	var/step = (A.x > F.x ? 1 : -1) * CLIENT_GLOW_CHUNK
	var/turf/B = locate(A.x + step, A.y, A.z)
	TEST_ASSERT_NOTNULL(B, "the next chunk exists")
	H.view_at(A, 7, 7)
	var/list/old_reach = H.reach.Copy()
	var/list/old_keep = H.keep_reach.Copy()
	var/visits = GLOB.client_glow_holder_chunk_visits
	H.view_at(B, 7, 7)
	visits = GLOB.client_glow_holder_chunk_visits - visits
	var/chunk = CLIENT_GLOW_CHUNK
	var/list/new_ring = list(H.reach[1] - chunk, H.reach[2] - chunk, H.reach[3] + chunk, H.reach[4] + chunk)
	var/list/old_ring = list(old_reach[1] - chunk, old_reach[2] - chunk, old_reach[3] + chunk, old_reach[4] + chunk)
	var/list/strips = glow_box_minus(H.reach, old_reach) + glow_box_minus(new_ring, old_ring) + glow_box_minus(old_keep, H.keep_reach)
	var/covered = 0
	for(var/gx in -4 to world.maxx / chunk + 4)
		for(var/gy in -4 to world.maxy / chunk + 4)
			var/list/chunk_box = list(gx * chunk + 1, gy * chunk + 1, gx * chunk + chunk, gy * chunk + chunk)
			for(var/list/strip as anything in strips)
				if(glow_boxes_overlap(strip, chunk_box))
					covered++
					break
	TEST_ASSERT_EQUAL(visits, covered, "a one-chunk step looks in exactly the chunks the strips cover, not the strips grown by a range")
	var/grown = 0 // what the strips would have cost grown by a light's longest reach, as the position index needed
	for(var/gx in -4 to world.maxx / chunk + 4)
		for(var/gy in -4 to world.maxy / chunk + 4)
			var/list/chunk_box = list(gx * chunk + 1, gy * chunk + 1, gx * chunk + chunk, gy * chunk + chunk)
			for(var/list/strip as anything in strips)
				if(glow_boxes_overlap(list(strip[1] - CLIENT_GLOW_MAX_RANGE, strip[2] - CLIENT_GLOW_MAX_RANGE, strip[3] + CLIENT_GLOW_MAX_RANGE, strip[4] + CLIENT_GLOW_MAX_RANGE), chunk_box))
					grown++
					break
	TEST_ASSERT(visits < grown, "and fewer than the strips grown by a light's reach ([visits] against [grown])")
	log_test("CLIENT GLOW CROSSING: one chunk step looked in [visits] chunk(s); the strips grown by a light's reach would be [grown]")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Opacity changes are folded: any number of turfs changing near a light before the next lighting step redraw its mask once.
/datum/unit_test/dq_client_glow_opacity_changes_batched

/datum/unit_test/dq_client_glow_opacity_changes_batched/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	client_glow_counters_restore()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/east1 = locate(T.x + 1, T.y, T.z)
	var/turf/north1 = locate(T.x, T.y + 1, T.z)
	TEST_ASSERT(east1 && north1 && !east1.directional_opacity && !north1.directional_opacity, "the test floor has clear turfs east and north")
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = L.light
	TEST_ASSERT_NOTNULL(S?.glow_mask_key, "the light has a mask")
	var/reconsiders = GLOB.client_glow_reconsiders
	var/changes = GLOB.client_glow_flush_changes
	var/builds = GLOB.client_glow_mask_builds
	allocate(/obj/structure/sight_test_blocker, east1)
	allocate(/obj/structure/sight_test_blocker, north1)
	TEST_ASSERT(length(GLOB.client_glow_dirty_lights), "the light waits for the lighting step instead of redrawing at once")
	TEST_ASSERT_EQUAL(GLOB.client_glow_reconsiders, reconsiders, "nothing is redrawn before the step")
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(GLOB.client_glow_flush_changes >= changes + 2, "both turfs' changes were noted ([GLOB.client_glow_flush_changes - changes])")
	TEST_ASSERT_EQUAL(GLOB.client_glow_reconsiders, reconsiders + 1, "the light was redrawn once for the two changes")
	TEST_ASSERT_EQUAL(GLOB.client_glow_mask_builds, builds + 1, "and its mask was rebuilt once")
	TEST_ASSERT(S.glow_reach["1,0"] && S.glow_reach["0,1"], "each blocker's face is lit")
	TEST_ASSERT(!S.glow_reach["2,0"] && !S.glow_reach["0,2"], "the floor behind each blocker is in shadow")
	TEST_ASSERT(!length(GLOB.client_glow_dirty_lights), "the step left nothing waiting")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A held glow standing on a turf the eye can no longer see (a door closes in front of it) moves to one it does: refreshed when opacity changes in view, and when
/// the eye steps inside its chunk, with no chunk crossing.
/datum/unit_test/dq_client_glow_holder_stand_follows_sight

/datum/unit_test/dq_client_glow_holder_stand_follows_sight/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	var/list/entry = H.entry_of(S)
	TEST_ASSERT_NOTNULL(entry, "the viewer holds the off-screen light")
	var/image/glow_image = entry[1]
	var/turf/stand = glow_image.loc
	TEST_ASSERT(isturf(stand) && H.seen[stand] && stand != LT, "it stands on a turf the eye sees, away from the light")
	var/toward_eye = (H.eye_x > stand.x ? 1 : -1)
	var/turf/in_front = locate(stand.x + toward_eye, stand.y, stand.z)
	TEST_ASSERT_NOTNULL(in_front, "there is a turf between the stand and the eye")
	TEST_ASSERT(H.seen[in_front], "the turf in front of it is seen")
	var/refreshes = GLOB.client_glow_holder_sight_refreshes
	allocate(/obj/structure/sight_test_blocker, in_front) // a door closing, in the eye's row
	SSlighting.light_step(0, TRUE) // the opacity flush: the viewer takes the new sight
	TEST_ASSERT(GLOB.client_glow_holder_sight_refreshes > refreshes, "the opacity change in its view made the viewer take its sight again")
	TEST_ASSERT(!H.seen[stand], "the turf behind the blocker is no longer seen")
	entry = H.entry_of(S)
	TEST_ASSERT_NOTNULL(entry, "the light is still held")
	glow_image = entry[1]
	var/turf/now_on = glow_image.loc
	TEST_ASSERT(isturf(now_on) && H.seen[now_on], "the glow stands on a turf the eye still sees")
	TEST_ASSERT(now_on != stand, "and not on the one it lost")
	// The eye steps inside its chunk: sight is taken again with no crossing.
	var/recomputes = GLOB.client_glow_holder_recomputes
	var/eye_before_x = H.eye_x
	var/turf/stepped = locate(H.eye_x + ((H.eye_x - 1) % CLIENT_GLOW_CHUNK < CLIENT_GLOW_CHUNK - 1 ? 1 : -1), H.eye_y + ((H.eye_y - 1) % CLIENT_GLOW_CHUNK < CLIENT_GLOW_CHUNK - 1 ? 1 : -1), H.z)
	refreshes = GLOB.client_glow_holder_sight_refreshes
	H.view_at(stepped, 7, 7)
	TEST_ASSERT_EQUAL(GLOB.client_glow_holder_recomputes, recomputes, "a step inside the chunk is not a crossing")
	TEST_ASSERT(GLOB.client_glow_holder_sight_refreshes > refreshes, "but it takes the sight again")
	TEST_ASSERT(H.eye_x == stepped.x && H.eye_y == stepped.y && H.eye_x != eye_before_x, "from where the eye stands now")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// Per-event diagnostics are written only while the lighting_trace flag is on; a crossing counts a trace line then, none otherwise.
/datum/unit_test/dq_client_glow_trace_is_profiling_only

/datum/unit_test/dq_client_glow_trace_is_profiling_only/Run()
	var/was = CONFIG_GET(flag/lighting_trace)
	CONFIG_SET(flag/lighting_trace, FALSE)
	var/list/got = list()
	client_glow_holder_setup(got)
	var/datum/client_glow_holder/H = got[2]
	var/obj/machinery/light/F = got[1]
	var/turf/A = client_glow_test_eye(get_turf(F))
	var/turf/B = locate(A.x + (A.x > F.x ? 1 : -1) * CLIENT_GLOW_CHUNK, A.y, A.z)
	var/lines = GLOB.client_glow_trace_lines
	H.view_at(B, 7, 7)
	TEST_ASSERT_EQUAL(GLOB.client_glow_trace_lines, lines, "a crossing writes no diagnostic line with tracing off")
	CONFIG_SET(flag/lighting_trace, TRUE)
	H.view_at(A, 7, 7)
	TEST_ASSERT(GLOB.client_glow_trace_lines > lines, "a crossing writes its diagnostic line with tracing on")
	CONFIG_SET(flag/lighting_trace, was)
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The census reads the chunk index and counts each glowing light once, however many chunks it is in.
/datum/unit_test/dq_client_glow_census_counts_indexed_lights

/datum/unit_test/dq_client_glow_census_counts_indexed_lights/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	client_glow_counters_restore()
	allocate(/obj/machinery/light, run_loc_floor_bottom_left)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/glows = 0
	for(var/datum/light_source/L)
		if(!QDELETED(L) && L.glow)
			glows++
	TEST_ASSERT(glows > 0, "a light glows")
	TEST_ASSERT(findtext(client_glow_census(), "client glows: [glows] glow(s)"), "the census counts every glowing light once")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// A flat-lit big atom is redone only for a light that reaches it: one beyond the light's reach box is left alone.
/datum/unit_test/dq_client_flat_light_refresh_is_local

/datum/unit_test/dq_client_flat_light_refresh_is_local/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	client_glow_counters_restore()
	var/turf/T = run_loc_floor_bottom_left
	var/turf/far = locate(T.x + CLIENT_GLOW_MAX_RANGE * 2 + 6, T.y, T.z)
	TEST_ASSERT_NOTNULL(far, "a turf well clear of a light's reach exists")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	H.resize(2, animate = FALSE, uncapped = TRUE, ignore_prefs = TRUE)
	TEST_ASSERT_NOTNULL(H.flat_light, "a double-size character has a flat light")
	var/refreshes = GLOB.client_flat_light_refreshes
	allocate(/obj/machinery/light, far)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_EQUAL(GLOB.client_flat_light_refreshes, refreshes, "a light far from the big atom leaves it alone")
	allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT(GLOB.client_flat_light_refreshes > refreshes, "a light on its turf redoes it")
	TEST_ASSERT_EQUAL(H.flat_light.lit_key, client_flat_light_key(client_flat_light_rgb(T)), "and its colour is its turf's drawn light")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The sprite's falloff the flat light models is the falloff the glow icons really have: the profile table against the pixels of the shipped sprites.
/datum/unit_test/dq_client_flat_light_profile

/datum/unit_test/dq_client_flat_light_profile/Run()
	for(var/size in list(96, 224, 352))
		var/icon/I = icon(client_glow_icon(size), "light")
		var/centre = (size - 1) / 2
		for(var/step in 0 to 19) // the last sample is the rim pixel itself, which the model rounds to nothing
			var/f = step / 20
			var/px = clamp(round(centre + f * (size / 2 - 1)) + 1, 1, size)
			var/real = client_lighting_test_alpha(I.GetPixel(px, round(centre) + 1)) / 255
			var/model = client_flat_light_profile(f)
			TEST_ASSERT(abs(real - model) <= 0.07, "the [size] px glow at [f] of its half width draws [real], the model says [model]")
	TEST_ASSERT_EQUAL(client_flat_light_profile(1), 0, "nothing at the rim")
	TEST_ASSERT_EQUAL(client_flat_light_profile(0), 1, "full at the centre")

/// The plane and blend chain that lights a character, as the screen is built: the flat light replaces the glows (same plane, above them), the glow plane is a hidden
/// target the lighting master ADDS over its black base, and what the silhouette holds is what the floor of its tile is drawn with, in colour, for a big sprite;
/// a normal sprite has none because the floor's own per-pixel light is already exact. A character in the dark is dark, in a light is lit, never brighter than the floor.
/datum/unit_test/dq_client_flat_light_chain

/datum/unit_test/dq_client_flat_light_chain/Run()
	for(var/screen_var in list(nameof(GLOB.client_glow_plane_master), nameof(GLOB.client_glow_base), nameof(GLOB.client_glow_compare_base), nameof(GLOB.client_glow_relay), nameof(GLOB.client_walls_plane_master), nameof(GLOB.client_spread_plane_master), nameof(GLOB.client_visible_plane_master), nameof(GLOB.client_glow_spread_relay)))
		set_global(screen_var, GLOB.vars[screen_var])
	set_global(nameof(GLOB.client_lighting), FALSE)
	client_glow_counters_restore()
	// The chain: glow plane master -> hidden target -> added by the lighting master over the base -> multiplied over the world.
	var/list/screen = client_glow_screen_objects()
	var/atom/movable/screen/plane_master/client_glow/glow_master = screen[1]
	TEST_ASSERT_EQUAL(glow_master.plane, PLANE_CLIENT_GLOW, "the glow plane master is the glow plane")
	TEST_ASSERT(glow_master.appearance_flags & PLANE_MASTER, "it is a plane master")
	TEST_ASSERT_EQUAL(glow_master.render_target, CLIENT_GLOW_RENDER_TARGET, "it renders only to a hidden target")
	var/atom/movable/screen/plane_master/lighting/lit_master = new
	client_glow_master_compose(lit_master)
	var/list/added = lit_master.filter_data?["client_glow_add"]
	TEST_ASSERT_NOTNULL(added, "the lighting master adds the glow plane")
	TEST_ASSERT_EQUAL(added["render_source"], CLIENT_GLOW_RENDER_TARGET, "the filter reads the glow target")
	TEST_ASSERT_EQUAL(added["blend_mode"], BLEND_ADD, "the glow plane is added over the black base, not overlaid or multiplied")
	QDEL_NULL(lit_master)
	var/atom/movable/screen/client_glow_base/base = GLOB.client_glow_base
	TEST_ASSERT_EQUAL(base.color, "#000000", "the base the glow plane is added to is black")
	var/obj/effect/overlay/client_glow/sample_glow = new
	TEST_ASSERT_EQUAL(sample_glow.blend_mode, BLEND_ADD, "a glow adds")
	TEST_ASSERT_EQUAL(sample_glow.layer, CLIENT_GLOW_LAYER, "a glow draws at the glow layer")
	qdel(sample_glow)
	// The characters.
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/big = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/small = allocate(/mob/living/carbon/human, T)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	big.resize(2, animate = FALSE, uncapped = TRUE, ignore_prefs = TRUE)
	small.update_transform(TRUE)
	TEST_ASSERT_NULL(small.flat_light, "a normal-size character has no flat light: it is lit by the per-pixel light under it, which is the floor's light exactly")
	var/atom/movable/client_flat_light/F = big.flat_light
	TEST_ASSERT_NOTNULL(F, "a big character has a flat light")
	TEST_ASSERT_EQUAL(F.plane, glow_master.plane, "the silhouette is on the glow plane with the glows it replaces")
	TEST_ASSERT(F.layer > CLIENT_GLOW_LAYER, "and above every glow")
	TEST_ASSERT(F.appearance_flags & RESET_COLOR, "the character's own colour does not tint it")
	TEST_ASSERT(F.appearance_flags & RESET_TRANSFORM, "nor its transform")
	TEST_ASSERT_EQUAL(F.mouse_opacity, MOUSE_OPACITY_TRANSPARENT, "it takes no clicks")
	// Dark: the dark floor is black and so is the character.
	var/list/dark = client_flat_light_rgb(T)
	TEST_ASSERT_EQUAL(dark[1] + dark[2] + dark[3], 0, "an unlit floor draws black")
	TEST_ASSERT_EQUAL(F.lit_key, 0, "so the big character in the dark is black: it does not glow")
	var/list/dark_matrix = client_flat_light_color(F.lit_key)
	TEST_ASSERT_EQUAL(dark_matrix[10] + dark_matrix[11] + dark_matrix[12], 0, "its colour matrix adds nothing")
	// A light: the floor under the character is drawn as the glow's sprite times its alpha, and the silhouette is that colour.
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = L.light
	var/obj/effect/overlay/client_glow/G = S?.glow
	TEST_ASSERT_NOTNULL(G, "the light glows")
	var/list/lit = client_flat_light_rgb(T)
	var/expect = min(1, client_flat_light_profile(0) * G.alpha / 255)
	var/list/tint = rgb2num(G.color)
	TEST_ASSERT(abs(lit[1] - min(1, expect * tint[1] / 255)) < 0.001 && abs(lit[3] - min(1, expect * tint[3] / 255)) < 0.001, "on the light's own tile the floor is drawn at the glow's alpha, in its colour ([lit[1]],[lit[2]],[lit[3]])")
	TEST_ASSERT(lit[1] > 0, "a lit floor is lit")
	TEST_ASSERT_EQUAL(F.lit_key, client_flat_light_key(lit), "the silhouette is the floor's light")
	TEST_ASSERT(lit[1] <= 1 && lit[2] <= 1 && lit[3] <= 1, "never brighter than white")
	// Further from the light the floor, and the character with it, is dimmer; past the reach it is dark.
	var/turf/two = locate(T.x + 2, T.y, T.z)
	if(two && S.glow_reach["2,0"])
		var/list/farther = client_flat_light_rgb(two)
		TEST_ASSERT(farther[1] <= lit[1], "two tiles from the light is no brighter than under it")
	// A coloured light is a coloured floor, so a coloured silhouette.
	L.set_light_color("#FF0000")
	SSlighting.light_step(0, TRUE)
	var/list/red = client_flat_light_rgb(T)
	TEST_ASSERT(red[1] > 0 && red[2] == 0 && red[3] == 0, "a red light draws a red floor ([red[1]],[red[2]],[red[3]])")
	TEST_ASSERT_EQUAL(big.flat_light.lit_key, client_flat_light_key(red), "and the character takes the red")
	// Outside dynamic lighting the floor is a white tile: full light.
	for(var/turf/F2 as anything in block(locate(1, 1, T.z), locate(world.maxx, world.maxy, T.z)))
		if(!F2.has_dynamic_lighting())
			var/list/white = client_flat_light_rgb(F2)
			TEST_ASSERT_EQUAL(white[1] + white[2] + white[3], 3, "a floor outside dynamic lighting is fully lit")
			break
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)


/// A door beside a light: its other state is readied ahead (baked and sent to the viewer holding the light), and when the door opens with a viewer near, the light is
/// marked near, redrawn in the very next lighting step, and the viewer's glow takes the open shape in that same step, with no bake to wait for.
/datum/unit_test/dq_client_glow_door_opens_in_one_step

/datum/unit_test/dq_client_glow_door_opens_in_one_step/Run()
	interest_isolate()
	for(var/counter in list(nameof(GLOB.client_glow_twins_made), nameof(GLOB.client_glow_twin_hits)))
		set_global(counter, GLOB.vars[counter])
	var/turf/T = run_loc_floor_bottom_left
	var/turf/east1 = locate(T.x + 1, T.y, T.z)
	var/turf/east2 = locate(T.x + 2, T.y, T.z)
	TEST_ASSERT(east1 && east2 && !east1.directional_opacity && !east2.directional_opacity, "the test floor has clear turfs east")
	var/obj/machinery/door/airlock/D = allocate(/obj/machinery/door/airlock, east1)
	TEST_ASSERT(D.opacity, "the airlock starts shut and opaque")
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	interest_view_set("dq-test-viewer", T, null, world.view)
	SSlighting.light_step(0, TRUE)
	var/datum/light_source/S = F.light
	var/h = S.glow_holder_key()
	TEST_ASSERT(!S.glow_reach["2,0"], "shut, the door keeps the floor behind it in shadow")
	var/shut_key = S.glow_mask_key
	// The other state is readied: one twin shape for the one door, a different shape from the shut one, with the floor behind the door in it.
	S.client_glow_twins_ready()
	TEST_ASSERT_EQUAL(length(S.glow_twins), 1, "the light readied the one shape its door can give it")
	var/open_key = S.glow_twins[1]
	TEST_ASSERT(open_key != shut_key, "the open shape differs from the shut one")
	TEST_ASSERT(client_glow_shape_grew(shut_key, open_key), "and reaches floor the shut one does not")
	TEST_ASSERT(GLOB.client_glow_twins_made > 0, "the twin was counted")
	TEST_ASSERT(GLOB.client_glow_baker.pending[open_key] || GLOB.client_glow_baker.icons[open_key], "and asked of the bakers ahead")
	if(!GLOB.client_glow_baker.icons[open_key]) // a unit-test world bakes on the spot instead of waiting on iconforge's thread
		var/png = client_glow_mask_bake_blocking(open_key)
		TEST_ASSERT_NOTNULL(png, "iconforge baked the open shape")
		client_glow_mask_cache(open_key, fcopy_rsc(file(png)))
		fdel(png)
	// Open it.
	var/hits = GLOB.client_glow_twin_hits
	var/reconsiders = GLOB.client_glow_reconsiders
	D.set_opacity(0)
	TEST_ASSERT(!D.opacity, "the door is open and clear")
	TEST_ASSERT_EQUAL(GLOB.client_glow_dirty_lights[h], CLIENT_GLOW_DIRTY_NEAR, "a light in a chunk a viewer holds is marked near")
	client_glow_reconsider_flush()
	TEST_ASSERT_EQUAL(GLOB.client_glow_reconsiders, reconsiders + 1, "the very next step redrew the light")
	TEST_ASSERT(S.glow_reach["2,0"], "the floor behind the open door is lit")
	TEST_ASSERT_EQUAL(S.glow_mask_key, open_key, "the light's shape is the one readied ahead")
	TEST_ASSERT_EQUAL(GLOB.client_glow_twin_hits, hits + 1, "and it was found baked")
	TEST_ASSERT_EQUAL(LAZYACCESS(H.cut_shape, h), open_key, "the viewer's glow is cut to the open shape in the same step, with no bake to wait for")
	// Shut again: the shape it came from is the twin now, and the glow goes back the same way.
	S.client_glow_twins_ready()
	TEST_ASSERT(shut_key in S.glow_twins, "the shut shape is the open one's twin")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)
	spent(H)

/// A light far from every viewer is marked far: it redraws after the ones near a viewer.
/datum/unit_test/dq_client_glow_opacity_marks_near_first

/datum/unit_test/dq_client_glow_opacity_marks_near_first/Run()
	interest_isolate()
	set_global(nameof(GLOB.client_lighting), FALSE)
	client_glow_counters_restore()
	var/turf/home = test_floor()
	var/turf/far = interest_far_from(home)
	TEST_ASSERT(home && far, "the map has room")
	var/turf/home_east = locate(home.x + 1, home.y, home.z)
	var/turf/far_east = locate(far.x + 1, far.y, far.z)
	TEST_ASSERT(home_east && far_east && !home_east.directional_opacity && !far_east.directional_opacity, "clear turfs beside both lights")
	var/obj/machinery/light/near_light = allocate(/obj/machinery/light, home)
	var/obj/machinery/light/far_light = allocate(/obj/machinery/light, far)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	interest_view_set("dq-test-viewer", home, null, world.view)
	allocate(/obj/structure/sight_test_blocker, far_east)
	allocate(/obj/structure/sight_test_blocker, home_east)
	TEST_ASSERT_EQUAL(GLOB.client_glow_dirty_lights[near_light.light.glow_holder_key()], CLIENT_GLOW_DIRTY_NEAR, "the light beside the viewer is marked near")
	TEST_ASSERT_EQUAL(GLOB.client_glow_dirty_lights[far_light.light.glow_holder_key()], CLIENT_GLOW_DIRTY_FAR, "the one nobody holds is marked far")
	var/reconsiders = GLOB.client_glow_reconsiders
	client_glow_reconsider_flush(TRUE)
	TEST_ASSERT_EQUAL(GLOB.client_glow_reconsiders, reconsiders + 2, "both were redrawn")
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// The darksight overlay (a radial additive glow centred on the player) eases in by how dark the player's turf is. Under client lighting that is the light the floor
/// is drawn with, not the gameplay light level (which read a lit corridor dark and gave the player's own character a halo); with the mode off it is the gameplay level.
/datum/unit_test/dq_client_darksight_follows_drawn_light

/datum/unit_test/dq_client_darksight_follows_drawn_light/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	set_global(nameof(GLOB.client_light_level_reads), GLOB.client_light_level_reads) // the drawn-light read counts itself; teardown restores the counter
	client_glow_counters_restore()
	var/turf/T = run_loc_floor_bottom_left
	TEST_ASSERT_EQUAL(client_darksight_brightness(T), T.get_lumcount(), "with client lighting off the gameplay light level decides")
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	allocate(/obj/machinery/light, T)
	SSlighting.light_step(0, TRUE)
	var/list/rgb = client_flat_light_rgb(T)
	var/drawn = max(rgb[1], rgb[2], rgb[3])
	TEST_ASSERT(drawn > 0, "a light on the turf draws light on its floor")
	TEST_ASSERT_EQUAL(client_darksight_brightness(T), drawn, "under client lighting the drawn light decides, not the gameplay level ([T.get_lumcount()])")
	log_test("CLIENT DARKSIGHT: drawn [drawn] against gameplay level [T.get_lumcount()]")
	client_lighting_set(FALSE)

/// Night vision is none for a mob with no darksight, grows with see_in_dark, reaches no further than the view, adds at most DARKSIGHT_MAX_ALPHA and
/// fades out as the floor gets lighter.
/datum/unit_test/dq_darksight_night_vision_curve

/datum/unit_test/dq_darksight_night_vision_curve/Run()
	TEST_ASSERT_EQUAL(darksight_alpha(0, 1), 0, "no darksight, no night vision")
	TEST_ASSERT_EQUAL(darksight_alpha(DARKSIGHT_MIN_SIGHT, 1), 0, "the human default of 2 gets none")
	var/weak = darksight_alpha(4, 1)
	var/strong = darksight_alpha(7, 1)
	TEST_ASSERT(weak > 0 && strong > weak, "more see_in_dark is stronger ([weak] < [strong])")
	TEST_ASSERT(darksight_alpha(DARKSIGHT_FULL_SIGHT, 1) <= DARKSIGHT_MAX_ALPHA, "never over the cap")
	TEST_ASSERT_EQUAL(darksight_alpha(25, 1), DARKSIGHT_MAX_ALPHA, "a hyena's 25 is capped at full")
	TEST_ASSERT(DARKSIGHT_MAX_ALPHA <= 0.4, "dim: at most about 40%")
	TEST_ASSERT_EQUAL(darksight_alpha(8, 0), 0, "none in a lit area")
	TEST_ASSERT(darksight_alpha(8, 0.5) < darksight_alpha(8, 1), "it eases in with the dark")
	TEST_ASSERT_EQUAL(darksight_view_radius("15x15"), 7.5, "a text view is read as its half width")
	TEST_ASSERT_EQUAL(darksight_view_radius(7), 7.5, "a number view is a radius around the player")
	TEST_ASSERT(darksight_scale(4, 7.5) < darksight_scale(8, 7.5), "more sight, a wider disc")
	TEST_ASSERT_EQUAL(darksight_scale(25, 7.5), 1, "the disc stops at the view")
	TEST_ASSERT_EQUAL(darksight_radius(25, 7.5), 7.5, "never past the view")
	TEST_ASSERT(darksight_scale(5, 15) > darksight_scale(5, 7.5) || darksight_scale(5, 15) == darksight_scale(5, 7.5), "a bigger view never narrows it")

/// The overlay icon is a flat disc: no hot spot at the centre, and its tint is a grey rather than white.
/datum/unit_test/dq_darksight_overlay_is_flat_and_grey

/datum/unit_test/dq_darksight_overlay_is_flat_and_grey/Run()
	var/list/tint = rgb2num(DARKSIGHT_TINT)
	TEST_ASSERT(max(tint[1], tint[2], tint[3]) - min(tint[1], tint[2], tint[3]) <= 40, "the tint is desaturated")
	TEST_ASSERT(min(tint[1], tint[2], tint[3]) >= 100, "and not dark")
	var/icon/I = icon('icons/mob/darksight.dmi')
	TEST_ASSERT_EQUAL(I.Width(), 480, "the icon is 15 tiles wide")
	var/centre = I.GetPixel(240, 240)
	var/near = I.GetPixel(240, 240 + 100)
	TEST_ASSERT_EQUAL(centre, near, "a flat centre: no peak at the player's own tile")
	TEST_ASSERT(isnull(I.GetPixel(2, 2)) || I.GetPixel(2, 2) != centre, "the corner fades out")
