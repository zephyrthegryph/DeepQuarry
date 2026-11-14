// Lighting smoothing (code/content/lighting/lighting_smoothing.dm): the blur is always on (a wide filter on the glow plane); the corner layer on top of it shades each
// turf from four corner values that are the average of the turf and the open turfs on its side of any wall, and switches off cleanly.

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
	for(var/table in list(nameof(GLOB.lighting_smooth_samples), nameof(GLOB.lighting_smooth_dirty), nameof(GLOB.lighting_smooth_redraw), nameof(GLOB.lighting_smooth_underlays), nameof(GLOB.lighting_smooth_levels)))
		T.set_global(table, list())

/datum/unit_test/dq_lighting_smoothing_blur

/datum/unit_test/dq_lighting_smoothing_blur/Run()
	set_global(nameof(GLOB.client_lighting), FALSE) // a failed run leaves the mode off for the next test
	set_global(nameof(GLOB.lighting_corners), null)
	dq_smoothing_keep_screens(src)
	client_lighting_set(TRUE)
	lighting_corners_set(FALSE)
	TEST_ASSERT_EQUAL(dq_smoothing_filter_size(), LIGHTING_SMOOTH_BLUR_SIZE, "corners off: the glow plane carries the wide blur filter")
	var/atom/movable/screen/plane_master/client_glow/master = client_glow_screen_objects()[1]
	TEST_ASSERT_EQUAL(master.alpha, 255, "corners off: the glow plane is drawn")
	var/atom/movable/screen/plane_master/lighting/off_master = new
	client_glow_master_compose(off_master)
	TEST_ASSERT_NOTNULL(off_master.filter_data?["client_glow_add"], "corners off: the lighting master adds the glow plane")
	QDEL_NULL(off_master)
	TEST_ASSERT(LIGHTING_SMOOTH_BLUR_SIZE <= WORLD_ICON_SIZE / 2, "the blur stays under half a tile so light does not bleed far past a wall")
	TEST_ASSERT_EQUAL(length(GLOB.lighting_smooth_underlays), 0, "corners off: no corner underlay")
	lighting_corners_set(TRUE)
	TEST_ASSERT_EQUAL(dq_smoothing_filter_size(), LIGHTING_SMOOTH_BLUR_SIZE, "corners on: the blur stays under them")
	TEST_ASSERT_EQUAL(master.alpha, 255, "corners on: the glow plane stays drawn for the wall spread")
	client_lighting_set(FALSE)
	set_global(nameof(GLOB.lighting_corners), null)

/// Steps the lighting system until the corner layer has nothing left to sample or draw.
/proc/dq_smoothing_drain()
	for(var/i in 1 to 400)
		SSlighting.light_step(0, TRUE)
		if(!length(GLOB.lighting_smooth_dirty) && !length(GLOB.lighting_smooth_redraw))
			return

/// The brightest channel of a corner underlay's colour matrix (0 when the turf carries none).
/proc/dq_smoothing_underlay_level(turf/T)
	var/mutable_appearance/MA = GLOB.lighting_smooth_underlays[T]
	if(!MA)
		return 0
	var/list/m = MA.color
	return max(m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11], m[13], m[14], m[15])

/datum/unit_test/dq_lighting_smoothing_corners

/datum/unit_test/dq_lighting_smoothing_corners/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	set_global(nameof(GLOB.lighting_corners), null)
	dq_smoothing_keep_screens(src)
	TEST_ASSERT(LIGHTING_SMOOTH_GRADIENT_STATE in icon_states(LIGHTING_ICON), "the lighting icon has the gradient state the tiles use (states: [json_encode(icon_states(LIGHTING_ICON))])")
	TEST_ASSERT(CONFIG_GET(flag/lighting_corners), "corner lighting is on by default")
	client_lighting_set(TRUE)
	lighting_corners_set(TRUE)
	var/atom/movable/screen/plane_master/client_glow/master = client_glow_screen_objects()[1]
	TEST_ASSERT_EQUAL(master.alpha, 255, "corners on: the glow plane still renders, it feeds the wall spread")
	var/atom/movable/screen/plane_master/lighting/lit_master = new
	client_glow_master_compose(lit_master)
	TEST_ASSERT(!lit_master.filter_data?["client_glow_add"], "corners on: the lighting master does not add the glow plane over the floor, the gradients are the light")
	TEST_ASSERT_NOTNULL(lit_master.filter_data?["client_spread_add"], "corners on: the lighting master still adds the wall spread, so a wall face is lit as in glow mode")
	QDEL_NULL(lit_master)
	TEST_ASSERT_NOTNULL(master.filter_data?["client_visible_cut"], "the glow plane is cut to what each client sees, so a viewer behind a wall gets none of the light on the other side")
	TEST_ASSERT_EQUAL(dq_smoothing_filter_size(), LIGHTING_SMOOTH_BLUR_SIZE, "corners on: the blur is still there")
	var/turf/T = run_loc_floor_bottom_left
	var/turf/far = run_loc_floor_top_right
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	for(var/i in 1 to 9) // the dirty turfs drain a bounded number per step
		SSlighting.light_step(0, TRUE)
	TEST_ASSERT_NOTNULL(L.light?.glow, "the fixture glows")
	TEST_ASSERT(GLOB.lighting_smooth_samples_taken > 0, "a light change sampled the turfs of its reach")
	dq_smoothing_drain()
	TEST_ASSERT(GLOB.lighting_smooth_corner_updates > 0, "redraws worked out corners")
	TEST_ASSERT(length(GLOB.lighting_smooth_underlays) > 0, "lit tiles carry a gradient underlay")
	// Every lit tile in the room has a gradient, and no wall does.
	var/lit_tiles = 0
	for(var/turf/R as anything in block(T, far))
		if(R.opacity)
			TEST_ASSERT(!GLOB.lighting_smooth_underlays[R], "the opaque turf at [R.x],[R.y] carries no gradient")
			continue
		var/list/rgb = client_flat_light_rgb(R)
		if(max(rgb[1], rgb[2], rgb[3]) < 0.05)
			continue
		lit_tiles++
		TEST_ASSERT_NOTNULL(GLOB.lighting_smooth_underlays[R], "the lit tile at [R.x],[R.y] (light [json_encode(rgb)]) has a gradient")
	TEST_ASSERT(lit_tiles > 4, "the room around the light has lit tiles ([lit_tiles])")
	// A corner is the average of its tile and the open turfs round it (no wall here): checked on the tiles beside the light.
	var/checked = 0
	var/list/samples = GLOB.lighting_smooth_samples["[T.z]"]
	for(var/turf/N as anything in RANGE_TURFS(1, T))
		if(N.opacity || !samples[lighting_smooth_key(N.x, N.y)])
			continue
		var/list/got = lighting_smooth_vertex(N, samples, 1, 1)
		var/sum = 0
		var/n = 0
		for(var/turf/O as anything in list(N, locate(N.x + 1, N.y, N.z), locate(N.x, N.y + 1, N.z), locate(N.x + 1, N.y + 1, N.z)))
			if(O.opacity || !samples[lighting_smooth_key(O.x, O.y)])
				continue
			var/list/rgb = client_flat_light_rgb(O)
			sum += rgb[1]
			n++
		if(!n)
			continue
		checked++
		TEST_ASSERT(abs(got[1] - sum / n) < 0.02, "the corner of [N.x],[N.y] is the average of its tile and its open neighbours ([got[1]] against [sum / n])")
	TEST_ASSERT(checked > 0, "corners were checked")
	// A quiet world does no corner work: a step with nothing dirty changes no counter.
	var/updates = GLOB.lighting_smooth_corner_updates
	var/redraws = GLOB.lighting_smooth_redraws
	SSlighting.light_step(0, TRUE)
	TEST_ASSERT_EQUAL(GLOB.lighting_smooth_corner_updates, updates, "an idle step reads no corner")
	TEST_ASSERT_EQUAL(GLOB.lighting_smooth_redraws, redraws, "an idle step redraws no tile")
	// A wall between the light and the far side: the column two tiles from the light turns opaque across the room. The tiles behind it stay dark, the wall itself
	// carries no gradient, and the tiles in front of it still do.
	var/wall_x = T.x + 2
	var/list/wall = list()
	for(var/wy in T.y to far.y)
		var/turf/W = locate(wall_x, wy, T.z)
		wall += W
		W.set_opacity(TRUE)
	dq_smoothing_drain()
	for(var/turf/W as anything in wall)
		TEST_ASSERT(!GLOB.lighting_smooth_underlays[W], "the wall at [W.x],[W.y] carries no gradient")
	var/turf/behind = locate(wall_x + 1, T.y, T.z)
	var/turf/behind_far = locate(wall_x + 2, T.y, T.z)
	var/turf/front = locate(T.x + 1, T.y, T.z)
	TEST_ASSERT(dq_smoothing_underlay_level(front) > 0.05, "the tile in front of the wall is lit ([dq_smoothing_underlay_level(front)])")
	TEST_ASSERT(dq_smoothing_underlay_level(behind) < 0.05, "the tile behind the wall stays dark ([dq_smoothing_underlay_level(behind)], light [json_encode(client_flat_light_rgb(behind))])")
	TEST_ASSERT(dq_smoothing_underlay_level(behind_far) < 0.05, "the tile two behind the wall stays dark ([dq_smoothing_underlay_level(behind_far)])")
	// A corner shared between the lit floor and a wall takes nothing from the far side: the front tile's corner towards the wall averages only the open turfs on its side.
	samples = GLOB.lighting_smooth_samples["[T.z]"]
	var/list/toward_wall = lighting_smooth_vertex(front, samples, 1, 1)
	var/list/own = samples[lighting_smooth_key(front.x, front.y)]
	var/list/along = samples[lighting_smooth_key(front.x, front.y + 1)]
	TEST_ASSERT(abs(toward_wall[1] - (own[1] + along[1]) / 2) < 0.02, "the corner against the wall is the average of the two open turfs on this side alone ([toward_wall[1]] against [(own[1] + along[1]) / 2])")
	for(var/turf/W as anything in wall)
		W.set_opacity(FALSE)
	dq_smoothing_drain()
	log_test("LIGHTING SMOOTHING CORNERS: [GLOB.lighting_smooth_samples_taken] samples ([GLOB.lighting_smooth_samples_changed] changed), [GLOB.lighting_smooth_corner_updates] corner reads, [GLOB.lighting_smooth_redraws] redraws, [round(GLOB.lighting_smooth_ms, 0.1)] ms in all, [length(GLOB.lighting_smooth_underlays)] lit tiles")
	lighting_corners_set(FALSE)
	TEST_ASSERT_EQUAL(length(GLOB.lighting_smooth_underlays), 0, "leaving corner mode takes every gradient away")
	var/atom/movable/screen/plane_master/lighting/off_master = new
	client_glow_master_compose(off_master)
	TEST_ASSERT_NOTNULL(off_master.filter_data?["client_glow_add"], "leaving corner mode adds the glow plane again")
	QDEL_NULL(off_master)
	client_lighting_set(FALSE)
	set_global(nameof(GLOB.lighting_corners), null)

/// One light that keeps moving: each move samples only the turfs the light reached before and reaches now (not the whole box round it, opaque turfs and all), and
/// redraws that leave a tile's levels as they were add no underlay. The counters are what the round's log line reports (samples/s, ms): the live round with corners
/// on, before this, read 6785 samples/s and 7337 ms per 10 s.
/datum/unit_test/dq_lighting_smoothing_moving_light

/datum/unit_test/dq_lighting_smoothing_moving_light/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	set_global(nameof(GLOB.lighting_corners), null)
	dq_smoothing_keep_screens(src)
	client_lighting_set(TRUE)
	lighting_corners_set(TRUE)
	var/turf/start = run_loc_floor_bottom_left
	var/turf/next = locate(start.x + 1, start.y, start.z)
	var/obj/machinery/light/L = allocate(/obj/machinery/light, start)
	dq_smoothing_drain()
	TEST_ASSERT_NOTNULL(L.light?.glow, "the fixture glows")
	var/taken = GLOB.lighting_smooth_samples_taken
	var/changed = GLOB.lighting_smooth_samples_changed
	var/redraws = GLOB.lighting_smooth_redraws
	var/started = REALTIMEOFDAY
	var/moves = 30
	for(var/i in 1 to moves)
		L.forceMove(i % 2 ? next : start)
		dq_smoothing_drain()
	var/ms = (REALTIMEOFDAY - started) * 100
	var/per_move = (GLOB.lighting_smooth_samples_taken - taken) / moves
	log_test("LIGHTING SMOOTHING MOVING LIGHT: [moves] moves, [GLOB.lighting_smooth_samples_taken - taken] samples ([round(per_move, 0.1)] a move, [GLOB.lighting_smooth_samples_changed - changed] changed), [GLOB.lighting_smooth_redraws - redraws] redraws, [ms] ms of wall time in all ([round(ms / moves, 0.1)] a move)")
	// The room is 25 floor tiles; the old box dirtied (2r+1)^2 turfs twice a move, walls and all.
	TEST_ASSERT(per_move <= 60, "a move samples only the turfs the light reaches ([per_move] a move)")
	lighting_corners_set(FALSE)
	client_lighting_set(FALSE)
	set_global(nameof(GLOB.lighting_corners), null)

/// A closed door blocks the corner layer like a wall, and a wall's face is lit by the same spread as in glow mode. A column across the room is wall but for one
/// airlock on the light's row: shut, the floor behind it stays dark and the door tile carries no gradient; open (its opacity is what the door changes), the light goes through; shut
/// again, dark. The wall and the door tile are on the walls plane (the spread lights their face from the floor beside them, cut per client by what it sees), and from
/// behind the shut door the light's own tile is out of sight.
/datum/unit_test/dq_lighting_smoothing_doors

/datum/unit_test/dq_lighting_smoothing_doors/Run()
	set_global(nameof(GLOB.client_lighting), FALSE)
	set_global(nameof(GLOB.lighting_corners), null)
	dq_smoothing_keep_screens(src)
	client_lighting_set(TRUE)
	lighting_corners_set(TRUE)
	var/turf/T = run_loc_floor_bottom_left
	var/turf/far = run_loc_floor_top_right
	var/obj/machinery/light/L = allocate(/obj/machinery/light, T)
	var/wall_x = T.x + 2
	var/list/wall = list()
	for(var/wy in T.y + 1 to far.y)
		var/turf/W = locate(wall_x, wy, T.z)
		wall += W
		W.set_opacity(TRUE)
	var/turf/door_turf = locate(wall_x, T.y, T.z)
	var/obj/machinery/door/airlock/D = allocate(/obj/machinery/door/airlock, door_turf)
	TEST_ASSERT(D.opacity, "the airlock starts shut and opaque")
	TEST_ASSERT(IS_OPAQUE_TURF(door_turf) && !door_turf.opacity, "a shut door makes its open turf a blocker without the turf being opaque")
	SSlighting.light_step(0, TRUE)
	dq_smoothing_drain()
	TEST_ASSERT_NOTNULL(L.light?.glow, "the fixture glows")
	var/turf/front = locate(T.x + 1, T.y, T.z)
	var/turf/behind = locate(wall_x + 1, T.y, T.z)
	var/turf/behind_far = locate(wall_x + 2, T.y, T.z)
	TEST_ASSERT(dq_smoothing_underlay_level(front) > 0.05, "the tile in front of the door is lit ([dq_smoothing_underlay_level(front)])")
	TEST_ASSERT(!GLOB.lighting_smooth_underlays[door_turf], "the shut door's tile carries no gradient")
	TEST_ASSERT(dq_smoothing_underlay_level(behind) < 0.05, "shut, the tile behind the door stays dark ([dq_smoothing_underlay_level(behind)], light [json_encode(client_flat_light_rgb(behind, TRUE))])")
	TEST_ASSERT(dq_smoothing_underlay_level(behind_far) < 0.05, "shut, the tile two behind the door stays dark ([dq_smoothing_underlay_level(behind_far)])")
	// The corner of the tile in front towards the door takes nothing from behind it: the door is not a neighbour to average.
	var/list/samples = GLOB.lighting_smooth_samples["[T.z]"]
	var/list/toward_door = lighting_smooth_vertex(front, samples, 1, 1)
	var/list/own = samples[lighting_smooth_key(front.x, front.y)]
	var/list/along = samples[lighting_smooth_key(front.x, front.y + 1)]
	TEST_ASSERT(abs(toward_door[1] - (own[1] + along[1]) / 2) < 0.02, "the corner against the wall beside the door averages the open turfs on this side alone ([toward_door[1]] against [(own[1] + along[1]) / 2])")
	// The faces: the wall and the shut door are on the walls plane, which the spread lights from the floor beside them, per client.
	TEST_ASSERT(client_walls_tile() in door_turf.underlays, "the shut door's tile is on the walls plane")
	for(var/turf/W as anything in wall)
		TEST_ASSERT(client_walls_tile() in W.underlays, "the wall at [W.x],[W.y] is on the walls plane")
		TEST_ASSERT(!GLOB.lighting_smooth_underlays[W], "the wall at [W.x],[W.y] carries no gradient")
	TEST_ASSERT(!(T in sight_view_turfs(behind, 8)), "from behind the shut door the light's tile is out of sight")
	// Open it.
	var/samples_before = GLOB.lighting_smooth_samples_taken
	D.set_opacity(0)
	TEST_ASSERT(!IS_OPAQUE_TURF(door_turf), "the open door no longer blocks")
	SSlighting.light_step(0, TRUE)
	dq_smoothing_drain()
	TEST_ASSERT(dq_smoothing_underlay_level(behind) > 0.05, "open, the light goes through: the tile behind the door is lit ([dq_smoothing_underlay_level(behind)])")
	TEST_ASSERT_NOTNULL(GLOB.lighting_smooth_underlays[door_turf], "the open door's tile is lit")
	TEST_ASSERT(!(client_walls_tile() in door_turf.underlays), "the open door's tile leaves the walls plane")
	TEST_ASSERT(GLOB.lighting_smooth_samples_taken - samples_before <= 120, "opening a door samples only the turfs it changes ([GLOB.lighting_smooth_samples_taken - samples_before])")
	// Shut again.
	D.set_opacity(1)
	SSlighting.light_step(0, TRUE)
	dq_smoothing_drain()
	TEST_ASSERT(dq_smoothing_underlay_level(behind) < 0.05, "shut again, the tile behind the door is dark again ([dq_smoothing_underlay_level(behind)])")
	TEST_ASSERT(!GLOB.lighting_smooth_underlays[door_turf], "shut again, the door's tile carries no gradient")
	log_test("LIGHTING SMOOTHING DOORS: [GLOB.lighting_smooth_samples_taken] samples, [GLOB.lighting_smooth_corner_updates] corner reads, [GLOB.lighting_smooth_redraws] redraws, [round(GLOB.lighting_smooth_ms, 0.1)] ms in all")
	for(var/turf/W as anything in wall)
		W.set_opacity(FALSE)
	dq_smoothing_drain()
	lighting_corners_set(FALSE)
	client_lighting_set(FALSE)
	set_global(nameof(GLOB.lighting_corners), null)
