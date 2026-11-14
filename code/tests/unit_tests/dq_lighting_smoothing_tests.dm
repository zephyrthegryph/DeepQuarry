// Lighting smoothing (code/content/lighting/lighting_smoothing.dm): the blur mode widens the filter on the glow plane, the corner mode shades each turf from
// four corner values that are the average of the neighbouring turfs' samples, and every mode switches back cleanly.

/// The blur size of the glow plane's softening filter now.
/proc/dq_smoothing_filter_size()
	var/atom/movable/screen/plane_master/client_glow/master = client_glow_screen_objects()[1]
	var/list/data = master.filter_data?["client_glow_soften"]
	return data ? data["size"] : null

/// The screen objects client_glow_screen_objects() makes on first use: restored so the state guard sees no leak.
/proc/dq_smoothing_keep_screens(datum/unit_test/T)
	T.set_global(nameof(GLOB.client_glow_plane_master), GLOB.client_glow_plane_master)
	T.set_global(nameof(GLOB.client_glow_base), GLOB.client_glow_base)
	T.set_global(nameof(GLOB.client_glow_compare_base), GLOB.client_glow_compare_base)
	T.set_global(nameof(GLOB.client_glow_relay), GLOB.client_glow_relay)
	T.set_global(nameof(GLOB.client_walls_plane_master), GLOB.client_walls_plane_master)
	T.set_global(nameof(GLOB.client_spread_plane_master), GLOB.client_spread_plane_master)
	T.set_global(nameof(GLOB.client_glow_spread_relay), GLOB.client_glow_spread_relay)
	T.set_global(nameof(GLOB.client_visible_plane_master), GLOB.client_visible_plane_master)
	for(var/counter in list(nameof(GLOB.lighting_smooth_samples_taken), nameof(GLOB.lighting_smooth_samples_changed), nameof(GLOB.lighting_smooth_corner_updates), nameof(GLOB.lighting_smooth_redraws), nameof(GLOB.lighting_smooth_ms), nameof(GLOB.lighting_smooth_log_next), nameof(GLOB.lighting_smooth_logged_samples), nameof(GLOB.lighting_smooth_logged_corners), nameof(GLOB.lighting_smooth_logged_redraws), nameof(GLOB.lighting_smooth_logged_ms)))
		T.set_global(counter, 0)
	for(var/table in list(nameof(GLOB.lighting_smooth_corners), nameof(GLOB.lighting_smooth_samples), nameof(GLOB.lighting_smooth_dirty), nameof(GLOB.lighting_smooth_redraw), nameof(GLOB.lighting_smooth_underlays)))
		T.set_global(table, list())

/datum/unit_test/dq_lighting_smoothing_blur

/datum/unit_test/dq_lighting_smoothing_blur/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	set_global(nameof(GLOB.lighting_smoothing), null)
	dq_smoothing_keep_screens(src)
	client_lighting_set(TRUE)
	lighting_smooth_set(LIGHTING_SMOOTH_BLUR)
	TEST_ASSERT_EQUAL(dq_smoothing_filter_size(), LIGHTING_SMOOTH_BLUR_SIZE, "blur mode: the glow plane carries the wide blur filter")
	var/atom/movable/screen/plane_master/client_glow/master = client_glow_screen_objects()[1]
	TEST_ASSERT_EQUAL(master.alpha, 255, "blur mode: the glow plane is drawn")
	TEST_ASSERT(LIGHTING_SMOOTH_BLUR_SIZE <= WORLD_ICON_SIZE / 2, "the blur stays under half a tile so light does not bleed far past a wall")
	lighting_smooth_set(LIGHTING_SMOOTH_OFF)
	TEST_ASSERT_EQUAL(dq_smoothing_filter_size(), CLIENT_GLOW_SOFTEN_SIZE, "off mode: the plain softening filter")
	TEST_ASSERT_EQUAL(length(GLOB.lighting_smooth_underlays), 0, "off mode: no corner underlay")
	client_lighting_set(FALSE)
	set_global(nameof(GLOB.lighting_smoothing), null)

/datum/unit_test/dq_lighting_smoothing_corners

/datum/unit_test/dq_lighting_smoothing_corners/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	set_global(nameof(GLOB.lighting_smoothing), null)
	dq_smoothing_keep_screens(src)
	TEST_ASSERT(LIGHTING_SMOOTH_GRADIENT_STATE in icon_states(LIGHTING_ICON), "the lighting icon has the gradient state the tiles use (states: [json_encode(icon_states(LIGHTING_ICON))])")
	client_lighting_set(TRUE)
	lighting_smooth_set(LIGHTING_SMOOTH_CORNERS)
	var/atom/movable/screen/plane_master/client_glow/master = client_glow_screen_objects()[1]
	TEST_ASSERT_EQUAL(master.alpha, 0, "corner mode: the glow plane is hidden, the gradients are the light")
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	for(var/i in 1 to 9) // the dirty turfs drain a bounded number per step
		SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(L.light?.glow, "the fixture glows")
	TEST_ASSERT(GLOB.lighting_smooth_samples_taken > 0, "a light change sampled the turfs of its reach")
	TEST_ASSERT(GLOB.lighting_smooth_corner_updates > 0, "changed samples updated corners")
	TEST_ASSERT(length(GLOB.lighting_smooth_underlays) > 0, "lit tiles carry a gradient underlay")
	// A corner beside the light is the average of the samples of its neighbouring turfs.
	var/checked = 0
	for(var/turf/N as anything in RANGE_TURFS(2, T))
		var/list/got = lighting_smooth_corner(N.z, N.x, N.y)
		var/sum_r = 0
		var/sum_g = 0
		var/sum_b = 0
		var/n = 0
		for(var/oy in N.y - 1 to N.y)
			for(var/ox in N.x - 1 to N.x)
				var/turf/O = locate(ox, oy, N.z)
				if(!lighting_smooth_counts(O))
					continue
				var/list/rgb = client_flat_light_rgb(O)
				sum_r += rgb[1]
				sum_g += rgb[2]
				sum_b += rgb[3]
				n++
		if(!n)
			continue
		checked++
		TEST_ASSERT(abs(got[1] - clamp(sum_r / n, 0, 1)) < 0.02 && abs(got[2] - clamp(sum_g / n, 0, 1)) < 0.02 && abs(got[3] - clamp(sum_b / n, 0, 1)) < 0.02, "the corner at [N.x],[N.y] is the average of its neighbouring turfs ([json_encode(got)] against [round(sum_r / n, 0.01)],[round(sum_g / n, 0.01)],[round(sum_b / n, 0.01)])")
	TEST_ASSERT(checked > 0, "corners were checked")
	for(var/i in 1 to 200) // the backlog of dirty turfs and tiles drains
		if(!length(GLOB.lighting_smooth_dirty) && !length(GLOB.lighting_smooth_redraw))
			break
		SSlighting.light_step(0, TRUE)
	// A quiet world does no corner work: a step with nothing dirty changes no counter.
	var/updates = GLOB.lighting_smooth_corner_updates
	var/redraws = GLOB.lighting_smooth_redraws
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_EQUAL(GLOB.lighting_smooth_corner_updates, updates, "an idle step updates no corner")
	TEST_ASSERT_EQUAL(GLOB.lighting_smooth_redraws, redraws, "an idle step redraws no tile")
	log_test("LIGHTING SMOOTHING CORNERS: [GLOB.lighting_smooth_samples_taken] samples ([GLOB.lighting_smooth_samples_changed] changed), [GLOB.lighting_smooth_corner_updates] corner updates, [GLOB.lighting_smooth_redraws] redraws, [round(GLOB.lighting_smooth_ms, 0.1)] ms in all, [length(GLOB.lighting_smooth_underlays)] lit tiles")
	lighting_smooth_set(LIGHTING_SMOOTH_BLUR)
	TEST_ASSERT_EQUAL(length(GLOB.lighting_smooth_underlays), 0, "leaving corner mode takes every gradient away")
	TEST_ASSERT_EQUAL(master.alpha, 255, "leaving corner mode draws the glow plane again")
	client_lighting_set(FALSE)
	set_global(nameof(GLOB.lighting_smoothing), null)
