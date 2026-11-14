// Lighting smoothing: the client engine draws every glow as a smooth sprite, but its tile-shaped cuts (the baked reach masks, the walls, the
// visibility cut) leave each turf one flat brightness with stair-stepped edges. Two layers, both live:
//
//   blur     always on: the glow plane's filter is LIGHTING_SMOOTH_BLUR_SIZE px (about 0.4 of a tile). Client GPU only, no server cost. The blur runs
//            after the wall cut, so a wider radius bleeds light a few pixels past a wall: keep it tight.
//   corners  on top of it (config lighting_corners, default on; the Toggle Corner Lighting admin verb switches it live): each open turf is shaded from four
//            corner brightnesses, interpolated across the tile by the gradient icon (the corner engine's own gradient state: a colour matrix whose rows
//            are the corners), so edges are smooth and a wall still cuts crisply. The lighting master no longer adds the glow plane (client_glow_master_compose()),
//            so the gradient underlays on the lighting plane, added over the black base, are the floor's light. The glow plane itself is still drawn, cut to what
//            each client sees: it feeds the wall spread (client_lighting_screen.dm), which lights the face of a wall from the floor beside it exactly as in
//            glow mode, per viewer, so a wall is lit only on the side its light is on and a viewer behind it sees none of it.
//
// Corner mode is incremental. A light change dirties only the turfs in its reach box (lighting_smooth_dirty(), from client_flat_lights_refresh()), and an
// opacity change dirties its own turf (reconsider_lights()). Each lighting step samples a bounded number of them: the sample of a turf is the light its floor is
// drawn with (client_flat_light_rgb(), the model the flat lights use; opaque turfs and turfs outside dynamic lighting have none). A sample that changed
// queues the nine tiles it can touch. A tile is drawn from its own sample and its neighbours': each of its four corners is the average of the tile and the
// open turfs around that corner on the tile's own side of any wall (lighting_smooth_vertex()): a blocker never counts, and the diagonal turf counts
// only when one of the two turfs between it and the tile is open, so a wall blocks light and a wall corner never lends the far side's light. A blocker is
// what the sight layer and the glow cut say blocks (IS_OPAQUE_TURF: the turf's own opacity or an opaque thing standing on it, a closed door, a shutter); an
// opacity change of either kind comes through reconsider_lights(). A blocker gets no gradient at all, and a tile whose corners are all dark loses its underlay. Redraws wait until the sampling backlog is drained (a tile drawn from half
// the samples is drawn again), except when the redraw backlog grows past four steps' worth. Sampling and drawing yield when the tick is over budget after a
// small minimum, so they never starve, and a step spends at most LIGHTING_SMOOTH_BUDGET_MS. Nothing runs when nothing changes. Counters and a log line every LIGHTING_SMOOTH_LOG_EVERY give samples, corner reads,
// redraws and the milliseconds spent.

/// Whether corner lighting was switched live (TRUE or FALSE); null until first asked (then the lighting_corners config value).
GLOBAL_VAR(lighting_corners)
/// "z" -> list(turf key -> list(red, green, blue)): the sample each lit turf contributed.
GLOBAL_LIST_EMPTY(lighting_smooth_samples)
/// turf -> TRUE: turfs to sample again.
GLOBAL_LIST_EMPTY(lighting_smooth_dirty)
/// turf -> TRUE: turfs to redraw.
GLOBAL_LIST_EMPTY(lighting_smooth_redraw)
/// turf -> the gradient underlay it carries.
GLOBAL_LIST_EMPTY(lighting_smooth_underlays)
/// turf -> the twelve corner levels (quantised, as text) its underlay was drawn from: a redraw that works out the same levels leaves the underlay as it is.
GLOBAL_LIST_EMPTY(lighting_smooth_levels)

/// Cumulative counters (tests, the log line, benchmarks).
GLOBAL_VAR_INIT(lighting_smooth_samples_taken, 0)
GLOBAL_VAR_INIT(lighting_smooth_samples_changed, 0)
/// Corner values worked out by redraws (four a tile).
GLOBAL_VAR_INIT(lighting_smooth_corner_updates, 0)
GLOBAL_VAR_INIT(lighting_smooth_redraws, 0)
GLOBAL_VAR_INIT(lighting_smooth_ms, 0)
/// What the counters read at the last log line; the next line is due at lighting_smooth_log_next.
GLOBAL_VAR_INIT(lighting_smooth_log_next, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_samples, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_corners, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_redraws, 0)
GLOBAL_VAR_INIT(lighting_smooth_logged_ms, 0)

/// Whether corner lighting is switched on (the live setting, else the config).
/proc/lighting_corners_enabled()
	var/on = GLOB.lighting_corners
	if(isnull(on))
		on = CONFIG_GET(flag/lighting_corners)
	return !!on

/// Whether the corner layer is running: client lighting is on and so are the corners.
/proc/lighting_corners_active()
	return GLOB.client_lighting && lighting_corners_enabled()

/// The glow plane's blur size: the wide blur, always.
/proc/lighting_smooth_blur_size()
	return LIGHTING_SMOOTH_BLUR_SIZE

/// The key of tile (x, y) in a per-level table (text: a number would index the list).
/proc/lighting_smooth_key(x, y)
	return "[x],[y]"

/// Switches corner lighting on or off live and puts the screen and the corner layer in step with it.
/proc/lighting_corners_set(on)
	GLOB.lighting_corners = !!on
	log_world("lighting corners: [GLOB.lighting_corners ? "on" : "off"]")
	lighting_smooth_apply()

/// Puts the glow plane's filter, its visibility and the corner layer in step with the corner setting and with client lighting being on.
/proc/lighting_smooth_apply()
	var/corners = lighting_corners_active()
	var/atom/movable/screen/plane_master/client_glow/master = GLOB.client_glow_plane_master // made on first use, with this filter
	if(master)
		master.modify_filter("client_glow_soften", list(size = lighting_smooth_blur_size()))
	// The glow plane is drawn either way (the wall spread reads it); whether the lighting master adds it over the floor is the corner setting.
	for(var/mob/M as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS)) // a player made later composes its own master (plane_holder New)
		var/datum/plane_holder/holder = hud_of(M)?.plane_holder
		if(holder)
			client_glow_master_compose(holder.plane_masters[VIS_LIGHTING])
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

/// Takes every gradient underlay off and forgets every sample.
/proc/lighting_smooth_clear()
	if(!length(GLOB.lighting_smooth_underlays) && !length(GLOB.lighting_smooth_samples) && !length(GLOB.lighting_smooth_dirty))
		return
	for(var/turf/T as anything in GLOB.lighting_smooth_underlays)
		T.underlays -= GLOB.lighting_smooth_underlays[T]
	GLOB.lighting_smooth_underlays.Cut()
	GLOB.lighting_smooth_levels.Cut()
	GLOB.lighting_smooth_samples.Cut()
	GLOB.lighting_smooth_dirty.Cut()
	GLOB.lighting_smooth_redraw.Cut()

/// A light changed (it glows, moved, resized, went dark or its mask changed): the turfs it lights now (its reach) and the turfs it lit before (`was_reach` about
/// `was_at`, or its own place when it did not move; a box when the old reach is not known) are sampled again. Only those: a turf the light never reached is
/// the same dark before and after, and so is an opaque one (its opacity changing is lighting_smooth_dirty_turf()'s).
/proc/lighting_smooth_dirty(datum/light_source/L, turf/was_at = null, was_range = 0, list/was_reach = null)
	if(!lighting_corners_active())
		return
	var/r = CLIENT_GLOW_RADIUS(L)
	var/turf/at = L.source_turf || L.glow_reach_origin
	var/list/reach = L.glow_reach
	if(at && L.glow)
		lighting_smooth_dirty_area(L.glow_reach_origin || at, r, reach)
	var/turf/was_origin = was_at || at
	if(!was_origin || (was_origin == at && was_reach == reach))
		return
	lighting_smooth_dirty_area(was_origin, max(r, was_range), was_reach)

/// The non-opaque turfs of the box of radius `r` about `centre` that are in `reach` (a list of "dx,dy" keys about `centre`; every turf of the box when null).
/proc/lighting_smooth_dirty_area(turf/centre, r, list/reach)
	var/cx = centre.x
	var/cy = centre.y
	for(var/turf/T as anything in RANGE_TURFS(r, centre))
		if(IS_OPAQUE_TURF(T))
			continue
		if(reach && !reach["[T.x - cx],[T.y - cy]"])
			continue
		GLOB.lighting_smooth_dirty[T] = TRUE

/// `T` changed what it blocks (a wall built, a door opened or closed): it is sampled again, and the nine tiles around it are drawn again when that changes its sample.
/proc/lighting_smooth_dirty_turf(turf/T)
	if(!lighting_corners_active())
		return
	GLOB.lighting_smooth_dirty[T] = TRUE

/// The sample of `T`: the light its floor is drawn with (a carried light cut by its reach too: a wall blocks it), or null for an opaque turf or one outside dynamic lighting.
/proc/lighting_smooth_sample_of(turf/T)
	if(IS_OPAQUE_TURF(T) || !T.has_dynamic_lighting())
		return null
	return client_flat_light_rgb(T, TRUE)

/// Takes a fresh sample of `T` and, when it changed, queues the nine tiles it can touch. TRUE when it changed.
/proc/lighting_smooth_sample(turf/T)
	GLOB.lighting_smooth_samples_taken++
	var/z = T.z
	var/list/samples = GLOB.lighting_smooth_samples["[z]"]
	if(!samples)
		samples = list()
		GLOB.lighting_smooth_samples["[z]"] = samples
	var/key = lighting_smooth_key(T.x, T.y)
	var/list/old = samples[key]
	var/list/new_sample = lighting_smooth_sample_of(T)
	if(isnull(old) && isnull(new_sample))
		return FALSE
	if(old && new_sample && abs(new_sample[1] - old[1]) < 0.004 && abs(new_sample[2] - old[2]) < 0.004 && abs(new_sample[3] - old[3]) < 0.004)
		return FALSE
	GLOB.lighting_smooth_samples_changed++
	if(new_sample)
		samples[key] = new_sample
	else
		samples -= key
	for(var/turf/N as anything in RANGE_TURFS(1, T))
		GLOB.lighting_smooth_redraw[N] = TRUE
	return TRUE

/// The corner of tile `T` towards (sx, sy) (each -1 or 1): list(red, green, blue), the average of the samples of `T` and of the open turfs around that corner on
/// its side of any wall. An orthogonal neighbour counts when it is not a blocker (IS_OPAQUE_TURF); the diagonal one only when it is not a blocker and one of the two turfs between it and
/// `T` is open: light never crosses a wall, and a corner that touches a wall never lends the far side's light. `samples` is the level's sample table; `T` has a sample.
/proc/lighting_smooth_vertex(turf/T, list/samples, sx, sy)
	var/list/own = samples[lighting_smooth_key(T.x, T.y)]
	var/red = own[1]
	var/green = own[2]
	var/blue = own[3]
	var/n = 1
	var/z = T.z
	var/turf/X = locate(T.x + sx, T.y, z)
	var/turf/Y = locate(T.x, T.y + sy, z)
	var/open_x = X && !IS_OPAQUE_TURF(X)
	var/open_y = Y && !IS_OPAQUE_TURF(Y)
	var/list/s
	if(open_x)
		s = samples[lighting_smooth_key(X.x, X.y)]
		if(s)
			red += s[1]
			green += s[2]
			blue += s[3]
			n++
	if(open_y)
		s = samples[lighting_smooth_key(Y.x, Y.y)]
		if(s)
			red += s[1]
			green += s[2]
			blue += s[3]
			n++
	if(open_x || open_y)
		var/turf/D = locate(T.x + sx, T.y + sy, z)
		if(D && !IS_OPAQUE_TURF(D))
			s = samples[lighting_smooth_key(D.x, D.y)]
			if(s)
				red += s[1]
				green += s[2]
				blue += s[3]
				n++
	GLOB.lighting_smooth_corner_updates++
	return list(clamp(red / n, 0, 1), clamp(green / n, 0, 1), clamp(blue / n, 0, 1))

/// Redraws `T`: its gradient underlay from its four corners, or none when they are all dark or `T` is a blocker (a wall or a closed door takes no light of its own: its face is the wall spread's). A tile whose twelve corner
/// levels (LIGHTING_SMOOTH_LEVEL_STEPS steps each, as dark as the screen tells apart) are the ones it was drawn from keeps its underlay: no appearance is made or swapped.
/proc/lighting_smooth_draw(turf/T)
	GLOB.lighting_smooth_redraws++
	var/list/samples = GLOB.lighting_smooth_samples["[T.z]"]
	var/list/own = IS_OPAQUE_TURF(T) ? null : samples?[lighting_smooth_key(T.x, T.y)]
	if(!own)
		lighting_smooth_undraw(T)
		return
	var/list/sw = lighting_smooth_vertex(T, samples, -1, -1)
	var/list/se = lighting_smooth_vertex(T, samples, 1, -1)
	var/list/nw = lighting_smooth_vertex(T, samples, -1, 1)
	var/list/ne = lighting_smooth_vertex(T, samples, 1, 1)
	var/steps = LIGHTING_SMOOTH_LEVEL_STEPS
	var/levels = "[round(sw[1] * steps)],[round(sw[2] * steps)],[round(sw[3] * steps)],[round(se[1] * steps)],[round(se[2] * steps)],[round(se[3] * steps)],[round(nw[1] * steps)],[round(nw[2] * steps)],[round(nw[3] * steps)],[round(ne[1] * steps)],[round(ne[2] * steps)],[round(ne[3] * steps)]"
	if(GLOB.lighting_smooth_levels[T] == levels) // the same levels: the underlay it has is right
		return
	if(!(sw[1] + sw[2] + sw[3] + se[1] + se[2] + se[3] + nw[1] + nw[2] + nw[3] + ne[1] + ne[2] + ne[3] >= 0.01))
		lighting_smooth_undraw(T)
		return
	lighting_smooth_undraw(T)
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
	GLOB.lighting_smooth_levels[T] = levels

/// Takes `T`'s gradient underlay off.
/proc/lighting_smooth_undraw(turf/T)
	var/mutable_appearance/old = GLOB.lighting_smooth_underlays[T]
	if(old)
		T.underlays -= old
		GLOB.lighting_smooth_underlays -= T
		GLOB.lighting_smooth_levels -= T

/// One lighting step of corner mode: samples at most LIGHTING_SMOOTH_SAMPLES_MAX dirty turfs, then (once the sampling backlog is drained) redraws at most
/// LIGHTING_SMOOTH_RENDERS_MAX tiles. Both stop after LIGHTING_SMOOTH_BUDGET_MS of the step, or when the tick is over budget (KERNEL_OVER_BUDGET), once a small
/// minimum is done, so a busy tick still moves them on and the corner layer never takes more than its share of a tick.
/proc/lighting_smooth_step(init_tick_checks)
	if(!lighting_corners_active())
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
		if(!init_tick_checks && done >= LIGHTING_SMOOTH_MIN_SAMPLES && (KERNEL_OVER_BUDGET || TICK_USAGE_TO_MS(started) >= LIGHTING_SMOOTH_BUDGET_MS))
			break
	queue = GLOB.lighting_smooth_redraw
	// A tile drawn while its neighbours still wait to be sampled is drawn again: wait for the sampling, unless the redraws pile up.
	if(!length(GLOB.lighting_smooth_dirty) || length(queue) > 4 * LIGHTING_SMOOTH_RENDERS_MAX)
		done = 0
		while(length(queue) && done < LIGHTING_SMOOTH_RENDERS_MAX)
			var/turf/T = queue[length(queue)]
			queue.len--
			done++
			if(!QDELETED(T))
				lighting_smooth_draw(T)
			if(!init_tick_checks && done >= LIGHTING_SMOOTH_MIN_RENDERS && (KERNEL_OVER_BUDGET || TICK_USAGE_TO_MS(started) >= LIGHTING_SMOOTH_BUDGET_MS))
				break
	GLOB.lighting_smooth_ms += TICK_USAGE_TO_MS(started)
	if(COOLDOWN_FINISHED(GLOB, lighting_smooth_log_next))
		lighting_smooth_log()

/// Writes what corner mode did since the last line: samples, changed samples, corner reads, redraws and milliseconds, with what waits.
/proc/lighting_smooth_log()
	var/seconds = LIGHTING_SMOOTH_LOG_EVERY / (1 SECONDS)
	log_world("lighting smoothing corners: [round((GLOB.lighting_smooth_samples_taken - GLOB.lighting_smooth_logged_samples) / seconds, 0.1)] samples/s ([GLOB.lighting_smooth_samples_changed] changed in all), [round((GLOB.lighting_smooth_corner_updates - GLOB.lighting_smooth_logged_corners) / seconds, 0.1)] corner reads/s, [round((GLOB.lighting_smooth_redraws - GLOB.lighting_smooth_logged_redraws) / seconds, 0.1)] redraws/s, [round(GLOB.lighting_smooth_ms - GLOB.lighting_smooth_logged_ms, 0.1)] ms in the last [round(seconds)] s; waiting: [length(GLOB.lighting_smooth_dirty)] to sample, [length(GLOB.lighting_smooth_redraw)] to redraw; [length(GLOB.lighting_smooth_underlays)] lit tiles")
	COOLDOWN_START(GLOB, lighting_smooth_log_next, LIGHTING_SMOOTH_LOG_EVERY)
	GLOB.lighting_smooth_logged_samples = GLOB.lighting_smooth_samples_taken
	GLOB.lighting_smooth_logged_corners = GLOB.lighting_smooth_corner_updates
	GLOB.lighting_smooth_logged_redraws = GLOB.lighting_smooth_redraws
	GLOB.lighting_smooth_logged_ms = GLOB.lighting_smooth_ms

ADMIN_VERB(toggle_corner_lighting, R_DEBUG|R_SERVER, "Toggle Corner Lighting", "Switch client lighting's corner layer (each tile shaded from its four corners, on top of the always-on blur) on or off.", ADMIN_CATEGORY_DEBUG_GAME)
	var/next = !lighting_corners_enabled()
	lighting_corners_set(next)
	message_admins("[key_name_admin(user)] set corner lighting [next ? "on" : "off"].")
