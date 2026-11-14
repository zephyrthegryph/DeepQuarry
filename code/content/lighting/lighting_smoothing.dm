// Lighting smoothing: the client engine draws every glow as a smooth sprite, but its tile-shaped cuts (the baked reach masks, the walls, the
// visibility cut) leave each turf one flat brightness with stair-stepped edges. Three modes, switched live (lighting_smooth_set()), default from the
// lighting_smoothing config entry, and an admin verb cycles them:
//
//   off      the plain softening blur (CLIENT_GLOW_SOFTEN_SIZE px) on the glow plane: the look before this existed.
//   blur     the same filter widened to LIGHTING_SMOOTH_BLUR_SIZE px (about 0.4 of a tile). Client GPU only, no server cost. The blur runs after the
//            wall cut, so a wider radius bleeds light a few pixels past a wall: keep it tight.
//   corners  each turf is shaded from four corner brightnesses, interpolated across the tile by the gradient icon (the corner engine's own gradient
//            state: a colour matrix whose rows are the corners), so edges are smooth and a wall still cuts crisply. The glow plane is hidden (alpha 0)
//            and the gradient underlays on the lighting plane, added over the black base, are the light.
//
// Corner mode is incremental. A light change dirties only the turfs in its reach box (lighting_smooth_dirty(), from client_flat_lights_refresh()). Each lighting
// step samples a bounded number of them: the sample of a turf is the light its floor is drawn with (client_flat_light_rgb(), the model the flat lights use;
// opaque turfs and turfs outside dynamic lighting have none). A sample that changed adds its delta to the sums of its four corners; a corner is the sum
// over its four turfs divided by how many of them have a sample, i.e. the average of the neighbouring turfs. The nine tiles that share one of the changed
// corners are redrawn, and a tile whose corners are all dark loses its underlay. Nothing runs when nothing changes. Counters and a log line every
// LIGHTING_SMOOTH_LOG_EVERY give samples, corner updates, redraws and the milliseconds spent.

/// The mode live now; null until first asked (then the config value).
GLOBAL_VAR(lighting_smoothing)
/// "z" -> list(vertex key -> list(red, green, blue) summed over the sampled turfs around that vertex). Sparse: a vertex with no light has no entry.
GLOBAL_LIST_EMPTY(lighting_smooth_corners)
/// "z" -> list(turf key -> list(red, green, blue)): the sample each lit turf contributed to its four corners.
GLOBAL_LIST_EMPTY(lighting_smooth_samples)
/// turf -> TRUE: turfs to sample again.
GLOBAL_LIST_EMPTY(lighting_smooth_dirty)
/// turf -> TRUE: turfs to redraw.
GLOBAL_LIST_EMPTY(lighting_smooth_redraw)
/// turf -> the gradient underlay it carries.
GLOBAL_LIST_EMPTY(lighting_smooth_underlays)

/// Cumulative counters (tests, the log line, benchmarks).
GLOBAL_VAR_INIT(lighting_smooth_samples_taken, 0)
GLOBAL_VAR_INIT(lighting_smooth_samples_changed, 0)
GLOBAL_VAR_INIT(lighting_smooth_corner_updates, 0)
GLOBAL_VAR_INIT(lighting_smooth_redraws, 0)
GLOBAL_VAR_INIT(lighting_smooth_ms, 0)
/// What the counters read at the last log line; the next line is due at lighting_smooth_log_next.
GLOBAL_VAR_INIT(lighting_smooth_log_next, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_samples, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_corners, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_redraws, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_ms, 0)

/// The mode in force: off, blur or corners.
/proc/lighting_smooth_mode()
	var/mode = GLOB.lighting_smoothing
	if(isnull(mode))
		mode = CONFIG_GET(string/lighting_smoothing)
	if(mode != LIGHTING_SMOOTH_OFF && mode != LIGHTING_SMOOTH_BLUR && mode != LIGHTING_SMOOTH_CORNERS)
		return LIGHTING_SMOOTH_BLUR
	return mode

/// The glow plane's blur size for the mode in force.
/proc/lighting_smooth_blur_size()
	if(lighting_smooth_mode() == LIGHTING_SMOOTH_BLUR)
		return LIGHTING_SMOOTH_BLUR_SIZE
	return CLIENT_GLOW_SOFTEN_SIZE

/// The glow plane's alpha: 0 in corner mode (a hidden render target at alpha 0 renders empty, so the gradients are the light), else drawn.
/proc/lighting_smooth_glow_alpha()
	if(GLOB.client_lighting && lighting_smooth_mode() == LIGHTING_SMOOTH_CORNERS)
		return 0
	return 255

/// The key of tile or vertex (x, y) in a per-level table (text: a number would index the list).
/proc/lighting_smooth_key(x, y)
	return "[x],[y]"

/// Switches the mode live and puts the screen and the corner layer in step with it.
/proc/lighting_smooth_set(mode)
	if(mode != LIGHTING_SMOOTH_OFF && mode != LIGHTING_SMOOTH_BLUR && mode != LIGHTING_SMOOTH_CORNERS)
		return
	GLOB.lighting_smoothing = mode
	log_world("lighting smoothing: [mode]")
	lighting_smooth_apply()

/// Puts the glow plane's filter, its visibility and the corner layer in step with the mode and with client lighting being on.
/proc/lighting_smooth_apply()
	var/mode = lighting_smooth_mode()
	var/corners = GLOB.client_lighting && mode == LIGHTING_SMOOTH_CORNERS
	var/atom/movable/screen/plane_master/client_glow/master = GLOB.client_glow_plane_master // made on first use, with this mode's filter and alpha
	if(master)
		master.modify_filter("client_glow_soften", list(size = lighting_smooth_blur_size()))
		master.set_alpha(lighting_smooth_glow_alpha())
	if(!corners)
		lighting_smooth_clear()
		return
	// Every glowing light dirties the turfs in its reach: the corner layer is built from what the screen draws now.
	for(var/datum/light_source/L as anything in lighting_smooth_lights())
		lighting_smooth_dirty(L)
	log_world("lighting smoothing: corner layer starting, [length(GLOB.lighting_smooth_dirty)] turfs to sample")

/// Every glowing light (one entry each), read off the chunk index.
/proc/lighting_smooth_lights()
	var/list/found = list()
	for(var/chunk in GLOB.client_glow_chunks)
		for(var/datum/light_source/L as anything in GLOB.client_glow_chunks[chunk])
			if(!QDELETED(L))
				found[L] = TRUE
	return found

/// Takes every gradient underlay off and forgets every sample and corner.
/proc/lighting_smooth_clear()
	if(!length(GLOB.lighting_smooth_underlays) && !length(GLOB.lighting_smooth_samples) && !length(GLOB.lighting_smooth_dirty))
		return
	for(var/turf/T as anything in GLOB.lighting_smooth_underlays)
		T.underlays -= GLOB.lighting_smooth_underlays[T]
	GLOB.lighting_smooth_underlays.Cut()
	GLOB.lighting_smooth_corners.Cut()
	GLOB.lighting_smooth_samples.Cut()
	GLOB.lighting_smooth_dirty.Cut()
	GLOB.lighting_smooth_redraw.Cut()

/// A light changed (it glows, moved, resized, went dark or its mask changed): the turfs of its reach box, and of the box it left, are sampled again.
/proc/lighting_smooth_dirty(datum/light_source/L, turf/was_at = null, was_range = 0)
	if(!GLOB.client_lighting || lighting_smooth_mode() != LIGHTING_SMOOTH_CORNERS)
		return
	var/r = CLIENT_GLOW_RADIUS(L) + 1 // a turf's corner reaches one tile past the glow's last tile
	var/turf/at = L.source_turf || L.glow_reach_origin
	if(at)
		lighting_smooth_dirty_box(at, r)
	if(was_at && was_at != at)
		lighting_smooth_dirty_box(was_at, max(r, was_range + 1))

/proc/lighting_smooth_dirty_box(turf/centre, r)
	for(var/turf/T as anything in RANGE_TURFS(r, centre))
		GLOB.lighting_smooth_dirty[T] = TRUE

/// The sample of `T`: the light its floor is drawn with, or null for an opaque turf or one outside dynamic lighting.
/proc/lighting_smooth_sample_of(turf/T)
	if(T.opacity || !T.has_dynamic_lighting())
		return null
	return client_flat_light_rgb(T)

/// Whether `T` counts when its corners are averaged.
/proc/lighting_smooth_counts(turf/T)
	return T && !T.opacity && T.has_dynamic_lighting()

/// Takes a fresh sample of `T` and, when it changed, adds the difference to its four corners and queues the nine tiles that share one. TRUE when it changed.
/proc/lighting_smooth_sample(turf/T)
	GLOB.lighting_smooth_samples_taken++
	var/z = T.z
	var/list/samples = GLOB.lighting_smooth_samples["[z]"]
	if(!samples)
		samples = list()
		GLOB.lighting_smooth_samples["[z]"] = samples
	var/list/corners = GLOB.lighting_smooth_corners["[z]"]
	if(!corners)
		corners = list()
		GLOB.lighting_smooth_corners["[z]"] = corners
	var/key = lighting_smooth_key(T.x, T.y)
	var/list/old = samples[key]
	var/list/new_sample = lighting_smooth_sample_of(T)
	var/dr = (new_sample ? new_sample[1] : 0) - (old ? old[1] : 0)
	var/dg = (new_sample ? new_sample[2] : 0) - (old ? old[2] : 0)
	var/db = (new_sample ? new_sample[3] : 0) - (old ? old[3] : 0)
	var/counts_before = !isnull(old)
	if(abs(dr) < 0.004 && abs(dg) < 0.004 && abs(db) < 0.004 && counts_before == !isnull(new_sample))
		return FALSE
	GLOB.lighting_smooth_samples_changed++
	if(new_sample)
		samples[key] = new_sample
	else
		samples -= key
	for(var/vy in T.y to T.y + 1)
		for(var/vx in T.x to T.x + 1)
			var/vkey = lighting_smooth_key(vx, vy)
			var/list/sum = corners[vkey]
			if(!sum)
				sum = list(0, 0, 0)
				corners[vkey] = sum
			sum[1] += dr
			sum[2] += dg
			sum[3] += db
			if(sum[1] < 0.0005 && sum[2] < 0.0005 && sum[3] < 0.0005 && !lighting_smooth_lit_around(samples, vx, vy))
				corners -= vkey
			GLOB.lighting_smooth_corner_updates++
	for(var/turf/N as anything in RANGE_TURFS(1, T))
		GLOB.lighting_smooth_redraw[N] = TRUE
	return TRUE

/// Whether any of the four sampled turfs around vertex (vx, vy) is in `samples`.
/proc/lighting_smooth_lit_around(list/samples, vx, vy)
	return (lighting_smooth_key(vx - 1, vy - 1) in samples) || (lighting_smooth_key(vx, vy - 1) in samples) || (lighting_smooth_key(vx - 1, vy) in samples) || (lighting_smooth_key(vx, vy) in samples)

/// The corner value at vertex (vx, vy) on level `z`: list(red, green, blue), the average of the sampled turfs around it (0 where it has none).
/proc/lighting_smooth_corner(z, vx, vy)
	var/list/corners = GLOB.lighting_smooth_corners["[z]"]
	var/list/sum = corners?[lighting_smooth_key(vx, vy)]
	if(!sum)
		return list(0, 0, 0)
	var/n = 0
	for(var/oy in vy - 1 to vy)
		for(var/ox in vx - 1 to vx)
			if(lighting_smooth_counts(locate(ox, oy, z)))
				n++
	if(!n)
		return list(0, 0, 0)
	return list(clamp(sum[1] / n, 0, 1), clamp(sum[2] / n, 0, 1), clamp(sum[3] / n, 0, 1))

/// Redraws `T`: its gradient underlay from its four corners, or none when they are all dark.
/proc/lighting_smooth_draw(turf/T)
	GLOB.lighting_smooth_redraws++
	var/z = T.z
	var/list/sw = lighting_smooth_corner(z, T.x, T.y)
	var/list/se = lighting_smooth_corner(z, T.x + 1, T.y)
	var/list/nw = lighting_smooth_corner(z, T.x, T.y + 1)
	var/list/ne = lighting_smooth_corner(z, T.x + 1, T.y + 1)
	var/mutable_appearance/old = GLOB.lighting_smooth_underlays[T]
	if(old)
		T.underlays -= old
		GLOB.lighting_smooth_underlays -= T
	var/lit = sw[1] + sw[2] + sw[3] + se[1] + se[2] + se[3] + nw[1] + nw[2] + nw[3] + ne[1] + ne[2] + ne[3]
	if(lit < 0.01)
		return
	var/mutable_appearance/MA = mutable_appearance(LIGHTING_ICON, LIGHTING_SMOOTH_GRADIENT_STATE, CLIENT_GLOW_LAYER, PLANE_LIGHTING, 255, RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM)
	MA.blend_mode = BLEND_ADD
	MA.color = list(
		sw[1], sw[2], sw[3], 0,
		se[1], se[2], se[3], 0,
		nw[1], nw[2], nw[3], 0,
		ne[1], ne[2], ne[3], 0,
		0, 0, 0, 1
	)
	T.underlays += MA
	GLOB.lighting_smooth_underlays[T] = MA

/// One lighting step of corner mode: samples at most LIGHTING_SMOOTH_SAMPLES_MAX dirty turfs and redraws at most LIGHTING_SMOOTH_RENDERS_MAX tiles, within the tick budget.
/proc/lighting_smooth_step(init_tick_checks)
	if(!GLOB.client_lighting || lighting_smooth_mode() != LIGHTING_SMOOTH_CORNERS)
		return
	if(!length(GLOB.lighting_smooth_dirty) && !length(GLOB.lighting_smooth_redraw))
		return
	var/started = TICK_USAGE
	var/list/queue = GLOB.lighting_smooth_dirty
	var/done = 0
	while(length(queue) && done < LIGHTING_SMOOTH_SAMPLES_MAX)
		var/turf/T = queue[length(queue)]
		queue.len--
		done++
		if(!QDELETED(T))
			lighting_smooth_sample(T)
		if(!init_tick_checks && KERNEL_OVER_BUDGET)
			break
	queue = GLOB.lighting_smooth_redraw
	done = 0
	while(length(queue) && done < LIGHTING_SMOOTH_RENDERS_MAX)
		var/turf/T = queue[length(queue)]
		queue.len--
		done++
		if(!QDELETED(T))
			lighting_smooth_draw(T)
		if(!init_tick_checks && KERNEL_OVER_BUDGET)
			break
	GLOB.lighting_smooth_ms += TICK_USAGE_TO_MS(started)
	if(COOLDOWN_FINISHED(GLOB, lighting_smooth_log_next))
		lighting_smooth_log()

/// Writes what corner mode did since the last line: samples, changed samples, corner updates, redraws and milliseconds, with what waits.
/proc/lighting_smooth_log()
	var/seconds = LIGHTING_SMOOTH_LOG_EVERY / (1 SECONDS)
	log_world("lighting smoothing corners: [round((GLOB.lighting_smooth_samples_taken - GLOB.lighting_smooth_logged_samples) / seconds, 0.1)] samples/s ([GLOB.lighting_smooth_samples_changed] changed in all), [round((GLOB.lighting_smooth_corner_updates - GLOB.lighting_smooth_logged_corners) / seconds, 0.1)] corner updates/s, [round((GLOB.lighting_smooth_redraws - GLOB.lighting_smooth_logged_redraws) / seconds, 0.1)] redraws/s, [round(GLOB.lighting_smooth_ms - GLOB.lighting_smooth_logged_ms, 0.1)] ms in the last [round(seconds)] s; waiting: [length(GLOB.lighting_smooth_dirty)] to sample, [length(GLOB.lighting_smooth_redraw)] to redraw; [length(GLOB.lighting_smooth_underlays)] lit tiles")
	COOLDOWN_START(GLOB, lighting_smooth_log_next, LIGHTING_SMOOTH_LOG_EVERY)
	GLOB.lighting_smooth_logged_samples = GLOB.lighting_smooth_samples_taken
	GLOB.lighting_smooth_logged_corners = GLOB.lighting_smooth_corner_updates
	GLOB.lighting_smooth_logged_redraws = GLOB.lighting_smooth_redraws
	GLOB.lighting_smooth_logged_ms = GLOB.lighting_smooth_ms

ADMIN_VERB(cycle_lighting_smoothing, R_DEBUG|R_SERVER, "Cycle Lighting Smoothing", "Switch client lighting smoothing between off, blur (a wider blur on the glow plane) and corners (each tile shaded from its four corners).", ADMIN_CATEGORY_DEBUG_GAME)
	var/next = LIGHTING_SMOOTH_BLUR
	switch(lighting_smooth_mode())
		if(LIGHTING_SMOOTH_OFF)
			next = LIGHTING_SMOOTH_BLUR
		if(LIGHTING_SMOOTH_BLUR)
			next = LIGHTING_SMOOTH_CORNERS
		if(LIGHTING_SMOOTH_CORNERS)
			next = LIGHTING_SMOOTH_OFF
	lighting_smooth_set(next)
	message_admins("[key_name_admin(user)] set lighting smoothing to [next].")
