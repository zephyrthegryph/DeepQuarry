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
	// The mask is KEEP_TOGETHER: a colour on it applies to the whole drawn group, so a zero matrix there would erase every tile and every glow.
	TEST_ASSERT(S.glow_mask.appearance_flags & KEEP_TOGETHER, "the mask draws as one group")
	TEST_ASSERT_NULL(S.glow_mask.color, "no colour on the group: it would erase the tiles")
	TEST_ASSERT_NULL(S.glow_mask.icon, "the mask itself draws nothing opaque")
	TEST_ASSERT_EQUAL(length(S.glow_mask.overlays), length(S.glow_reach) + 1, "the transparent sizer and one tile per reached turf")
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

// ---- the per-client glow holder (client_glow_holder.dm) ----

/// A lit fixture with client lighting on, and a holder (no client) seeing from just off the light's screen.
/datum/unit_test/proc/client_glow_holder_setup(list/out)
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	for(var/counter in list(nameof(GLOB.client_glow_holder_made), nameof(GLOB.client_glow_holder_updated), nameof(GLOB.client_glow_holder_dropped), nameof(GLOB.client_glow_holder_recomputes)))
		set_global(counter, GLOB.vars[counter]) // teardown restores the counters
	var/obj/machinery/light/F = allocate(/obj/machinery/light, run_loc_floor_bottom_left)
	client_lighting_set(TRUE)
	SSlighting.light_step(0, TRUE)
	var/datum/client_glow_holder/H = new
	H.view_at(client_glow_test_eye(get_turf(F)), 7, 7)
	out += F
	out += H

/// A light just off screen shows its glow on screen: the viewer holds a glow image on a turf it always sees, offset to the
/// light's true place, and a mask image whose render target the glow image's alpha filter names; the real glow is hidden.
/datum/unit_test/dq_client_glow_holder_off_screen

/datum/unit_test/dq_client_glow_holder_off_screen/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	var/turf/LT = get_turf(F)
	TEST_ASSERT_NOTNULL(S?.glow, "the fixture glows")
	TEST_ASSERT(LT.x < H.safe[1] || LT.x > H.safe[3], "the light stands off the safe box")
	var/list/entry = H.entry_of(S)
	TEST_ASSERT_NOTNULL(entry, "the viewer holds the off-screen light's glow")
	var/image/glow_image = entry[1]
	var/image/mask_image = entry[2]
	var/image/hide_image = entry[3]
	var/turf/A = glow_image.loc
	TEST_ASSERT(isturf(A) && A.x >= H.safe[1] && A.x <= H.safe[3] && A.y >= H.safe[2] && A.y <= H.safe[4], "the glow image's anchor is seen from anywhere in the eye's chunk")
	TEST_ASSERT_EQUAL(A.x + (glow_image.pixel_x - S.glow.pixel_x) / WORLD_ICON_SIZE, LT.x, "its x offset puts it on the light")
	TEST_ASSERT_EQUAL(A.y + (glow_image.pixel_y - S.glow.pixel_y) / WORLD_ICON_SIZE, LT.y, "its y offset puts it on the light")
	TEST_ASSERT_EQUAL(glow_image.blend_mode, BLEND_ADD, "the copy adds like the glow")
	TEST_ASSERT_EQUAL(glow_image.plane, PLANE_LIGHTING, "the copy is on the lighting plane")
	TEST_ASSERT(findtext(mask_image.render_target, "*") == 1, "the mask image is a hidden render target")
	TEST_ASSERT(mask_image.render_target != S.glow_mask.render_target, "the mask image has a render target of its own")
	var/list/filters = glow_image.filters
	TEST_ASSERT(length(filters) && filters[1]:render_source == mask_image.render_target, "the glow image's alpha filter reads its own mask image")
	TEST_ASSERT_EQUAL(mask_image.loc, A, "the mask image stands on the same anchor")
	TEST_ASSERT(hide_image.override && hide_image.loc == S.glow, "the real glow is overridden for this viewer: never drawn twice")
	spent(H)
	client_lighting_set(FALSE)
	SSlighting.light_step(0, TRUE)

/// No double drawing: once the eye's chunk puts the light in its safe box, the copy goes and the normal glow shows.
/datum/unit_test/dq_client_glow_holder_in_view

/datum/unit_test/dq_client_glow_holder_in_view/Run()
	var/list/got = list()
	client_glow_holder_setup(got)
	var/obj/machinery/light/F = got[1]
	var/datum/client_glow_holder/H = got[2]
	var/datum/light_source/S = F.light
	TEST_ASSERT_NOTNULL(H.entry_of(S), "held while off screen")
	H.view_at(get_turf(F), 7, 7)
	TEST_ASSERT_NULL(H.entry_of(S), "the light's turf is always on screen: the copy is dropped")
	TEST_ASSERT_EQUAL(length(H.images()), 0, "no image is left over it")
	TEST_ASSERT_NOTNULL(S.glow, "the normal glow shows")
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
	var/image/mask_image = H.entry_of(S)[2]
	TEST_ASSERT_EQUAL(length(mask_image.overlays), length(S.glow_reach) + 1, "the transparent sizer and one mask tile per reached turf")
	TEST_ASSERT(S.glow_reach["2,0"], "the floor two east is lit before the blocker")
	var/before = length(mask_image.overlays)
	var/obj/structure/sight_test_blocker/B = allocate(/obj/structure/sight_test_blocker, east1)
	SSlighting.light_step(0, TRUE)
	mask_image = H.entry_of(S)?[2]
	TEST_ASSERT_NOTNULL(mask_image, "still held")
	TEST_ASSERT(!S.glow_reach["2,0"], "the floor behind the blocker is in shadow")
	TEST_ASSERT(length(mask_image.overlays) < before, "the copy's mask lost the shadowed tiles ([length(mask_image.overlays)] < [before])")
	TEST_ASSERT_EQUAL(length(mask_image.overlays), length(S.glow_reach) + 1, "the copy's mask matches the reach")
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
	for(var/screen_var in list(nameof(GLOB.client_glow_plane_master), nameof(GLOB.client_glow_base), nameof(GLOB.client_glow_compare_base), nameof(GLOB.client_glow_relay)))
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
	TEST_ASSERT_EQUAL(S.glow?.plane, PLANE_LIGHTING, "compare off: the glow is back on the lighting plane")
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
	for(var/screen_var in list(nameof(GLOB.client_glow_plane_master), nameof(GLOB.client_glow_base), nameof(GLOB.client_glow_compare_base), nameof(GLOB.client_glow_relay)))
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
