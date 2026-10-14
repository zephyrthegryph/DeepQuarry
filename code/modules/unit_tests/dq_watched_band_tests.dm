// watched() (code/modules/heat/watched.dm): a draw that reads Rust-owned heat as a band redraws when Rust reports a band change.

/obj/dq_watched_probe
	name = "watched probe"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "fix"
	var/watch_level = 400

/obj/dq_watched_probe/draw(datum/look/look)
	..()
	look.overlay("band-[watched(src, WATCH_HEAT, list(watch_level))]")

/datum/unit_test/dq_watched_band_redraws_on_a_crossing

/datum/unit_test/dq_watched_band_redraws_on_a_crossing/Run()
	var/turf/T = test_floor()
	var/obj/dq_watched_probe/P = allocate(/obj/dq_watched_probe, T)
	TEST_ASSERT(P.create_heat_body(TRUE), "the probe got no heat body")
	P.set_watch_level(P.get_temperature() + 50)
	state_changed(P)
	refresh_flush()
	TEST_ASSERT(("band-0" in P.rx?.look_overlays), "below the level it reads band 0: [json_encode(P.rx?.look_overlays)]")
	SSwatched.arm_pending(0)
	TEST_ASSERT(watched_armed(P, WATCH_HEAT, list(P.watch_level)), "the read armed a band watch after the draw")
	vg_world_run_steps(2)
	native_system().drain()
	refresh_flush()
	heat_set(P, P.watch_level + 100)
	vg_world_run_steps(2)
	native_system().drain()
	refresh_flush()
	TEST_ASSERT(P.get_temperature() >= P.watch_level, "the heat did not raise the body past the level: [P.get_temperature()]")
	TEST_ASSERT(("band-1" in P.rx?.look_overlays), "a crossing Rust reported redrew it: [json_encode(P.rx?.look_overlays)]")

/datum/unit_test/dq_watched_lum_band_publishes_on_a_corner_change

/datum/unit_test/dq_watched_lum_band_publishes_on_a_corner_change/Run()
	var/turf/T = test_floor()
	if(!T.lighting_object)
		T.lighting_build_overlay()
	var/datum/lighting_object/O = T.lighting_object
	TEST_ASSERT_NOTNULL(O, "the test floor has no dynamic lighting")
	// A floor no light ever reached has no corners yet: make the one this test lights (the lighting engine makes them the same way).
	var/datum/lighting_corner/made
	if(!T.lighting_corner_NE)
		made = new /datum/lighting_corner(T.x, T.y, T.z, TRUE)
	TEST_ASSERT_NOTNULL(T.lighting_corner_NE, "the test floor has no lighting corner")
	var/list/levels = list(0.5)
	var/before = watched(T, WATCH_LUM, levels)
	SSwatched.arm_pending(0)
	TEST_ASSERT(watched_armed(T, WATCH_LUM, levels), "the read armed a lum band on the turf's lighting object")
	var/key = jointext(levels, ",")
	var/list/row = O.lum_watch[key]
	TEST_ASSERT_EQUAL(row[2], before, "the armed band is the one the reader saw")
	// Light every corner past the level: the lighting object update reports the turf, the pass republishes the band.
	var/list/corners = list(T.lighting_corner_NE, T.lighting_corner_SE, T.lighting_corner_SW, T.lighting_corner_NW)
	var/list/saved = list()
	for(var/datum/lighting_corner/L as anything in corners)
		if(!L)
			continue
		saved[L] = list(L.lum_r, L.lum_g, L.lum_b)
		L.lum_r = 5
		L.lum_g = 5
		L.lum_b = 5
	O.update()
	SSwatched.arm_pending(0)
	var/after = row[2]
	for(var/datum/lighting_corner/L as anything in saved)
		var/list/rgb = saved[L]
		L.lum_r = rgb[1]
		L.lum_g = rgb[2]
		L.lum_b = rgb[3]
	O.update()
	SSwatched.arm_pending(0)
	if(made)
		qdel(made)
	TEST_ASSERT_EQUAL(after, 1, "a corner change past the level moved the published band (was [before])")
	// The lighting hot path: an update on a turf nothing watches pays one var read. Logged for the record, not asserted.
	var/list/watch = O.lum_watch
	O.lum_watch = null
	var/start = TICK_USAGE_REAL
	for(var/i in 1 to 5000)
		O.update()
	var/unwatched = TICK_USAGE_REAL - start
	O.lum_watch = watch
	start = TICK_USAGE_REAL
	for(var/i in 1 to 5000)
		O.update()
	var/watched_cost = TICK_USAGE_REAL - start
	log_world("LUM WATCH TIMING: 5000 lighting_object.update(): unwatched [unwatched] tick%, watched [watched_cost] tick%")
	SSwatched.arm_pending(0)
