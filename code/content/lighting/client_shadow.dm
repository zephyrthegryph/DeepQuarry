// Client lighting, piece 2: baked shapes. Each glow is the light's sprite already cut to the open floor its light reaches (the world opacity
// layer's sight from the light's turf, code/domains/verdigris/sight/), baked off-thread by iconforge, white so one icon serves every colour,
// and shared by every light with the same reach. No filter per light, and nothing depends on another object being drawn. Opaque tiles are not in the
// cut: walls take their light from the visible floor beside them, on the glow plane (client_lighting_screen.dm). The gameplay reach (glow_reach) still has them.
// A viewer's glow is the plain sprite until its shape is first baked; after a change it keeps its previous cut until the new one lands. A reach is recomputed only when its light is redrawn (it moved or changed) or
// when opacity changes inside its reach (a door, a wall built), found through a per-chunk index of glowing lights. The index holds a light in every chunk its
// reach box (CLIENT_GLOW_RADIUS about its turf) overlaps, so "the lights that reach this box" is the lights of the chunks the box covers, with no growing by a range.


/// Cumulative mask rebuilds and reach-triggered redraws (benchmarks, the door test).
GLOBAL_VAR_INIT(client_glow_mask_builds, 0)
GLOBAL_VAR_INIT(client_glow_reconsiders, 0)
/// "z,cx,cy" -> lights glowing whose reach box overlaps that chunk (client lighting only). A light is in each chunk its reach touches, up to nine.
GLOBAL_LIST_EMPTY(client_glow_chunks)
/// Opacity changes waiting for the next lighting step (client_glow_reconsider()): light handle -> TRUE for the glowing lights whose reach they touch, and z -> list(x0, y0, x1, y1)
/// for the box of the changed turfs on each level (the holders whose eye sees them follow).
GLOBAL_LIST_EMPTY(client_glow_dirty_lights)
GLOBAL_LIST_EMPTY(client_glow_dirty_boxes)
/// Door twin shapes asked for ahead, and opacity redraws that found their new shape cached (benchmarks, tests).
GLOBAL_VAR_INIT(client_glow_twins_made, 0)
GLOBAL_VAR_INIT(client_glow_twin_hits, 0)
/// "z,cx,cy" -> the doors standing in that chunk (the same grid as client_glow_chunks), kept by the door on init, move and removal (glow_door_index()): a light's twins look only at the
/// chunks under its reach box. Lights whose twins were worked out, and the doors they examined to do it (benchmarks, tests: doors examined per light is the local count).
GLOBAL_LIST_EMPTY(client_glow_door_chunks)
GLOBAL_VAR_INIT(client_glow_twin_lights, 0)
GLOBAL_VAR_INIT(client_glow_twin_doors_examined, 0)
/// Flushes run, and opacity changes folded into them (benchmarks, tests).
GLOBAL_VAR_INIT(client_glow_flushes, 0)
GLOBAL_VAR_INIT(client_glow_flush_changes, 0)

/datum/light_source
	/// The reach key it last computed ("margin|offsets"): names the baked mask its viewers cut its glow with.
	var/glow_mask_key
	/// The reach range and glow margin the mask was last built for (client_glow_mask_refresh()).
	var/glow_mask_range = 0
	var/glow_mask_margin = 0
	/// "dx,dy" -> TRUE for every turf the mask lets the glow onto (tests, debugging).
	var/list/glow_reach
	/// The turf glow_reach is measured from.
	var/turf/glow_reach_origin
	/// The chunks this light is indexed under while it glows: list(z, cx0, cy0, cx1, cy1), the chunks its reach box overlaps. Null while it is not indexed.
	var/list/glow_chunk_box
	/// The shapes this light takes when one door in its reach is flipped (open or shut), for the mask key in glow_twins_for; lazy. They are baked ahead and sent to the viewers
	/// holding the light, so a door's opacity change swaps a shape that is already on the client (client_glow_twins_ready()).
	var/list/glow_twins
	var/glow_twins_for

/// The index key of chunk (cx, cy) on level z.
/proc/client_glow_chunk_id(z, cx, cy)
	return "[z],[cx],[cy]"

/// The chunks box list(x0, y0, x1, y1) overlaps: list(cx0, cy0, cx1, cy1).
/proc/glow_chunk_range(list/box)
	return list(CLIENT_GLOW_CHUNK_OF(box[1]), CLIENT_GLOW_CHUNK_OF(box[2]), CLIENT_GLOW_CHUNK_OF(box[3]), CLIENT_GLOW_CHUNK_OF(box[4]))

/// The reach box of a light of radius `r` standing on `S`: list(x0, y0, x1, y1).
/proc/glow_reach_box(turf/S, r)
	return list(S.x - r, S.y - r, S.x + r, S.y + r)

/// Whether box `a` and box `b` (list(x0, y0, x1, y1)) overlap.
/proc/glow_boxes_overlap(list/a, list/b)
	return !(b[3] < a[1] || b[1] > a[3] || b[4] < a[2] || b[2] > a[4])

/// The baked shadow masks and their counters.
GLOBAL_DATUM_INIT(client_glow_baker, /datum/client_glow_baker, new)

CAPABILITIES_PART(/datum/controller/global_vars, client_glow_baker)
	owns_one(nameof(client_glow_baker), /datum/client_glow_baker)

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/client_glow_baker)

/// The mask bakes' state: one per world, and running bakes outlive whatever asked for them.
/datum/client_glow_baker
	/// Shape key -> icon resource (bounded, oldest out first: a filter already using one keeps it).
	var/list/icons = list()
	/// Shape keys queued or baking -> TRUE, so one shape bakes once.
	var/list/pending = list()
	/// Shape keys waiting for a free bake.
	var/list/queue = list()
	/// Shape key -> REALTIMEOFDAY it was asked for.
	var/list/asked_at = list()
	var/inflight = 0
	var/hits = 0
	var/misses = 0
	var/baked = 0
	var/failed = 0
	var/refused = 0
	var/evicted = 0
	/// Sum of the time from request to baked, deciseconds (real time).
	var/wait_ds = 0
	/// Shapes asked for ahead of a viewer holding them (the chunks around its reach box).
	var/prefetched = 0
	/// TRUE while a turn() timer is waiting: the baker's turns hand arrivals to viewers, work out door twins and start queued bakes, a few milliseconds a tick.
	var/turn_waiting = FALSE
	/// Light handle -> TRUE for held lights whose door twins are still to be worked out (client_glow_twins_pump()): each costs a sight query per nearby door, so a turn does a few ms of them.
	var/list/twin_work = list()
	/// Trace counters of the twin work: lights done, turns taken, the longest one light (ms).
	var/twins_done = 0
	var/twins_turns = 0
	var/twins_max_ms = 0
	/// Arrived shapes whose viewers have not all been told: list(key, icon, list of holders still to tell) each, oldest first. A holder is told a few milliseconds a tick
	/// (client_glow_arrivals_run()): one shape held by many clients was one call of tens of ms (the whole fan-out of a shape's arrival).
	var/list/arrivals = list()
	/// Trace counters of the arrival turns: steps taken and viewers told.
	var/arrival_steps = 0
	var/arrival_told = 0

/// The reached tiles (flat text list dx,dy,...) merged into rectangles: a flat number list x0,y0,x1,y1,... (tile offsets, inclusive).
/// Horizontal runs per row, then a run identical to the row below's extends that rectangle upward.
/proc/client_glow_mask_rects(list/offsets)
	. = list()
	if(!length(offsets))
		return
	var/list/rows = list()
	var/low = INFINITY
	var/high = -INFINITY
	for(var/i = 1, i < length(offsets), i += 2)
		var/x = text2num(offsets[i])
		var/y = text2num(offsets[i + 1])
		var/list/row = rows["[y]"]
		if(!row)
			row = rows["[y]"] = list()
		row += x
		low = min(low, y)
		high = max(high, y)
	var/list/open = list() // "x0,x1" -> index of its rectangle in the result
	for(var/y in low to high)
		var/list/row = rows["[y]"]
		var/list/next_open = list()
		if(row)
			sortTim(row, GLOBAL_PROC_REF(cmp_numeric_asc))
			var/start = row[1]
			var/last = start
			for(var/n in 2 to length(row) + 1)
				var/x = n <= length(row) ? row[n] : null
				if(!isnull(x) && x == last + 1)
					last = x
					continue
				var/run = "[start],[last]"
				var/at = open[run]
				if(at)
					.[at + 3] = y
				else
					at = length(.) + 1
					. += list(start, y, last, y)
				next_open[run] = at
				if(!isnull(x))
					start = x
					last = x
		open = next_open

/// Adds one draw step per rectangle (client_glow_mask_rects(), tile offsets) to `steps`, each grown `grow` pixels; a null colour clears.
/proc/client_glow_mask_boxes(list/steps, list/rects, margin, size, grow, color)
	for(var/i = 1, i < length(rects), i += 4)
		var/x1 = max(rects[i] * WORLD_ICON_SIZE + margin + 1 - grow, 1)
		var/y1 = max(rects[i + 1] * WORLD_ICON_SIZE + margin + 1 - grow, 1)
		var/x2 = min((rects[i + 2] + 1) * WORLD_ICON_SIZE + margin + grow, size)
		var/y2 = min((rects[i + 3] + 1) * WORLD_ICON_SIZE + margin + grow, size)
		if(x1 > x2 || y1 > y2)
			continue
		var/list/box = list("type" = RUSTG_ICONFORGE_DRAW_BOX, "x1" = x1, "y1" = y1, "x2" = x2, "y2" = y2)
		if(color)
			box["color"] = color
		steps += list(box)

/// The iconforge sprite of a mask of this shape (key "margin|dx,dy,...|blocked dx,dy,..."): the glow sprite wiped clear, then the reached
/// tiles solid. Every step overwrites. An edge against an unreached floor fades INWARD, inside the reached tile; an edge against a blocked
/// (opaque) tile stays full strength, because a wall is a real edge and floor beside it must not dim. The last steps clear every tile
/// outside the reach exactly, so the bake holds no light at all on a wall: its near half is on screen from the wall's far side.
/proc/client_glow_mask_sprite(key)
	var/list/parts = splittext(key, "|")
	var/margin = text2num(parts[1])
	var/list/offsets = length(parts) > 1 && length(parts[2]) ? splittext(parts[2], ",") : list()
	var/list/blocked_offsets = length(parts) > 2 && length(parts[3]) ? splittext(parts[3], ",") : list()
	var/size = margin * 2 + WORLD_ICON_SIZE
	var/list/steps = list(list("type" = RUSTG_ICONFORGE_DRAW_BOX, "x1" = 1, "y1" = 1, "x2" = size, "y2" = size))
	var/list/reached = list()
	for(var/i = 1, i < length(offsets), i += 2)
		reached["[offsets[i]],[offsets[i + 1]]"] = TRUE
	var/list/blocked = list()
	for(var/i = 1, i < length(blocked_offsets), i += 2)
		blocked["[blocked_offsets[i]],[blocked_offsets[i + 1]]"] = TRUE
	// Only the tiles the sprite covers: a reached tile past its edge would spend a step on nothing.
	var/grid = CEILING(margin / WORLD_ICON_SIZE, 1)
	var/list/inside = list()
	var/list/outside = list()
	var/list/fading = list()
	for(var/dy in -grid to grid)
		for(var/dx in -grid to grid)
			var/tile = "[dx],[dy]"
			if(reached[tile])
				inside += list("[dx]", "[dy]")
				continue
			outside += list("[dx]", "[dy]")
			if(!blocked[tile] && (reached["[dx - 1],[dy]"] || reached["[dx + 1],[dy]"] || reached["[dx],[dy - 1]"] || reached["[dx],[dy + 1]"])) // only a floor edge fades: a tile touching the reach by a corner alone would dim floor beside a wall
				fading += list("[dx]", "[dy]")
	var/list/inside_rects = client_glow_mask_rects(inside)
	var/list/outside_rects = client_glow_mask_rects(outside)
	var/list/fading_rects = client_glow_mask_rects(fading)
	client_glow_mask_boxes(steps, inside_rects, margin, size, 0, "#FFFFFFFF")
	// Iconforge refuses a sprite past CLIENT_GLOW_MASK_STEPS_MAX transforms. The body and the final clear always fit (merged rectangles);
	// a jagged shape gives up its widest rings first, so the fade narrows but the cut stays exact.
	var/static/list/ring_colors = list("#FFFFFFCC", "#FFFFFF99", "#FFFFFF66", "#FFFFFF33") // deepest into the reached tile first
	var/fading_count = length(fading_rects) / 4
	var/spare = CLIENT_GLOW_MASK_STEPS_MAX - 1 - (length(inside_rects) + length(outside_rects)) / 4
	var/rings = fading_count ? clamp(round(spare / fading_count), 0, length(ring_colors)) : 0
	for(var/ring in (length(ring_colors) - rings + 1) to length(ring_colors))
		client_glow_mask_boxes(steps, fading_rects, margin, size, (length(ring_colors) - ring + 1) * CLIENT_GLOW_MASK_RING_STEP, ring_colors[ring])
	client_glow_mask_boxes(steps, outside_rects, margin, size, 0, null)
	var/source = resolve_icon_dmi_path(get_icon_dmi_path(client_glow_icon(size)))
	var/list/mask = list("icon_file" = source, "icon_state" = "light", "dir" = SOUTH, "frame" = 1, "transform" = steps)
	return list("icon_file" = source, "icon_state" = "light", "dir" = SOUTH, "frame" = 1, "transform" = list(list("type" = RUSTG_ICONFORGE_BLEND_ICON, "icon" = mask, "blend_mode" = ICON_MULTIPLY, "x" = 1, "y" = 1)))

/// TRUE when shape `now` reaches a floor tile shape `was` did not (keys "margin|dx,dy,...|blocked").
/proc/client_glow_shape_grew(was, now)
	var/list/old_parts = splittext(was, "|")
	var/list/new_parts = splittext(now, "|")
	if(length(new_parts) < 2 || !length(new_parts[2]))
		return FALSE
	var/list/old_tiles = length(old_parts) > 1 && length(old_parts[2]) ? splittext(old_parts[2], ",") : list()
	var/list/new_tiles = splittext(new_parts[2], ",")
	var/list/had = list()
	for(var/i = 1, i < length(old_tiles), i += 2)
		had["[old_tiles[i]],[old_tiles[i + 1]]"] = TRUE
	for(var/i = 1, i < length(new_tiles), i += 2)
		if(!had["[new_tiles[i]],[new_tiles[i + 1]]"])
			return TRUE
	return FALSE

/// The baked mask of this shape, or null while it is not ready (asks for it). A crossing never waits on a bake: its glow shows the plain
/// sprite until the shape arrives.
/proc/client_glow_mask_icon(key)
	var/found = GLOB.client_glow_baker.icons[key]
	if(found)
		GLOB.client_glow_baker.hits++
		return found
	GLOB.client_glow_baker.misses++
	client_glow_mask_request(key)
	return GLOB.client_glow_baker.icons[key]

/// The baker's turn: arrived shapes are told to their viewers, queued bakes are started and door twins are worked out, `budget_ms` of them in all (each part at least one item),
/// and what is left waits for the next tick.
/proc/client_glow_baker_turn(budget_ms = CLIENT_GLOW_TURN_BUDGET_MS)
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	var/started = TICK_USAGE_REAL
	client_glow_arrivals_run(max(0, budget_ms - TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)))
	if(length(B.queue) && B.inflight < CLIENT_GLOW_MASK_BAKES_MAX)
		client_glow_mask_pump()
	client_glow_twins_pump(max(0, budget_ms - TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)))
	if(length(B.twin_work))
		client_glow_baker_wake()

/// Arms the baker's next turn if it is not already waiting.
/proc/client_glow_baker_wake()
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	if(B.turn_waiting)
		return
	B.turn_waiting = TRUE
	after(B, 1 TICKS, TYPE_PROC_REF(/datum/client_glow_baker, turn_continue))

/// Works out the door twins of the held lights waiting for it, until `budget_ms` is spent (at least one light a turn: the turn's own, however little the turn has left), then tells the
/// viewers holding each light. A light that was deleted or lost its glow meanwhile is skipped. Returns the lights done.
/proc/client_glow_twins_pump(budget_ms = CLIENT_GLOW_TURN_BUDGET_MS)
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	if(!length(B.twin_work))
		return 0
	var/started = TICK_USAGE_REAL
	var/done = 0
	B.twins_turns++
	while(length(B.twin_work))
		var/h = B.twin_work[1]
		B.twin_work.Cut(1, 2)
		var/datum/light_source/L = handle_get(h)
		if(!istype(L) || QDELETED(L) || !L.glow_mask_key)
			continue
		var/step_started = TICK_USAGE_REAL
		L.client_glow_twins_ready()
		done++
		for(var/datum/client_glow_holder/H as anything in REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS))
			if(!QDELETED(H) && LAZYACCESS(H.held, h))
				H.queue_twins(L)
		var/step_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
		B.twins_max_ms = max(B.twins_max_ms, step_ms)
		if(length(B.twin_work) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
			break
	B.twins_done += done
	if(done && client_glow_trace_line())
		log_world("client glow twins: [done] light(s) worked out in [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), 0.01)] ms, [length(B.twin_work)] more waiting (longest light [round(B.twins_max_ms, 0.01)] ms, [B.twins_done] in all over [B.twins_turns] turn(s))")
	return done

/// The timer of a baker turn that ran out of budget.
/datum/client_glow_baker/proc/turn_continue()
	turn_waiting = FALSE
	client_glow_baker_turn()

/proc/client_glow_mask_cache(key, res)
	GLOB.client_glow_baker.icons[key] = res
	if(length(GLOB.client_glow_baker.icons) > CLIENT_GLOW_MASK_CACHE_MAX)
		GLOB.client_glow_baker.icons.Cut(1, 2)
		GLOB.client_glow_baker.evicted++

/// Asks for a shape no viewer holds yet, so it is ready when one walks up.
/proc/client_glow_mask_prefetch(key)
	if(GLOB.client_glow_baker.icons[key] || GLOB.client_glow_baker.pending[key])
		return
	GLOB.client_glow_baker.prefetched++
	client_glow_mask_request(key, TRUE)

/proc/client_glow_mask_request(key, ahead = FALSE)
	if(GLOB.client_glow_baker.pending[key])
		if(!ahead) // a viewer holds it now: it goes before the shapes only asked for ahead
			var/at = GLOB.client_glow_baker.queue.Find(key)
			if(at > 1)
				GLOB.client_glow_baker.queue.Cut(at, at + 1)
				GLOB.client_glow_baker.queue.Insert(1, key)
		return
	if(length(GLOB.client_glow_baker.pending) >= CLIENT_GLOW_MASK_QUEUE_MAX)
		GLOB.client_glow_baker.refused++ // asked again the next time a viewer considers the light
		return
	GLOB.client_glow_baker.pending[key] = TRUE
	GLOB.client_glow_baker.asked_at[key] = REALTIMEOFDAY
	client_glow_mask_enqueue(key, ahead)

/// A shape waits for a baker. One a viewer asked for goes before the shapes only asked for ahead.
/proc/client_glow_mask_enqueue(key, ahead)
	if(ahead || !length(GLOB.client_glow_baker.queue))
		GLOB.client_glow_baker.queue += key
	else
		GLOB.client_glow_baker.queue.Insert(1, key)
	client_glow_mask_pump()

/proc/client_glow_mask_dir_ready()
	var/static/made = FALSE
	if(!made)
		rustg_file_write("", "[CLIENT_GLOW_MASK_DIR].keep")
		made = TRUE

/// Starts bakes for the queued shapes, up to CLIENT_GLOW_MASK_BAKES_MAX at once; each start is a sprite build and a JSON encode, so one call stops once it has spent
/// CLIENT_GLOW_TURN_BUDGET_MS (at least one start) and the baker's next turn goes on (client_glow_baker_turn()).
/proc/client_glow_mask_pump()
	var/started = TICK_USAGE_REAL
	var/begun = 0
	while(GLOB.client_glow_baker.inflight < CLIENT_GLOW_MASK_BAKES_MAX && length(GLOB.client_glow_baker.queue))
		if(begun && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= CLIENT_GLOW_TURN_BUDGET_MS)
			client_glow_baker_wake()
			return
		begun++
		var/key = GLOB.client_glow_baker.queue[1]
		GLOB.client_glow_baker.queue.Cut(1, 2)
		client_glow_mask_dir_ready()
		var/sheet = "cglow_[md5(key)]"
		var/job_id = rustg_iconforge_generate_async(CLIENT_GLOW_MASK_DIR, sheet, json_encode(list("mask" = client_glow_mask_sprite(key))), FALSE, FALSE, TRUE)
		GLOB.client_glow_baker.inflight++
		io_job(null, /datum/io_backend/rustg_job, job_id, GLOBAL_PROC_REF(client_glow_mask_job_done), key, sheet)

/// The PNG a bake's output names, or null.
/proc/client_glow_mask_png(sheet, output)
	if(!output || !findtext(output, "{", 1, 2))
		log_world("client glow mask: iconforge gave no result for [sheet]: [output]")
		return null
	var/list/data = json_decode(output)
	var/list/sprite_data = data["sprites"]?["mask"]
	if(length(data["error"]) || !sprite_data)
		log_world("client glow mask: iconforge reported [json_encode(data["error"])] for [sheet]: [output]")
		return null
	var/path = "[CLIENT_GLOW_MASK_DIR][sheet]_[sprite_data["size_id"]].png"
	return rustg_file_exists(path) ? path : null

/// io_job() callback: a mask bake finished.
/proc/client_glow_mask_job_done(result, error, key, sheet)
	GLOB.client_glow_baker.inflight--
	GLOB.client_glow_baker.pending -= key
	var/asked = GLOB.client_glow_baker.asked_at[key]
	GLOB.client_glow_baker.asked_at -= key
	var/path = error ? null : client_glow_mask_png(sheet, result)
	if(!path)
		GLOB.client_glow_baker.failed++
		log_world("client glow mask: bake failed for [sheet] ([error || result]); its lights stay uncut until asked again")
	else
		GLOB.client_glow_baker.wait_ds += REALTIMEOFDAY - asked
		client_glow_mask_store(key, path)
	client_glow_mask_pump()

/// Takes a baked PNG into the resource cache and gives it to every viewer waiting on the shape.
/proc/client_glow_mask_store(key, path)
	var/res = fcopy_rsc(file(path))
	fdel(path)
	client_glow_mask_cache(key, res)
	GLOB.client_glow_baker.baked++
	if(!length(GLOB.client_glow_baker.pending) && client_glow_trace_line())
		log_world("client glow masks: queue drained at [time2text(world.realtime, "hh:mm:ss")]; [client_glow_mask_stats()]") // the load-in timeline, with the first hold line
	if(!(GLOB.client_glow_baker.baked % 64) && client_glow_trace_line())
		log_world(client_glow_mask_stats())
	client_glow_mask_arrived(key, res)

/// Shape `key` is in the cache (baked): every viewer waiting on it shows it. The viewers are told in turns of CLIENT_GLOW_TURN_BUDGET_MS
/// (client_glow_arrivals_run()); the first of them is told now.
/proc/client_glow_mask_arrived(key, res)
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	B.arrivals += list(list(key, res, REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS).Copy()))
	client_glow_arrivals_run(CLIENT_GLOW_TURN_BUDGET_MS)

/// Tells the viewers of arrived shapes, oldest shape first, until `budget_ms` is spent (always at least one viewer); the rest waits for the next tick.
/// A viewer that was deleted meanwhile is skipped. Returns the viewers told.
/proc/client_glow_arrivals_run(budget_ms = CLIENT_GLOW_TURN_BUDGET_MS)
	var/datum/client_glow_baker/B = GLOB.client_glow_baker
	if(!length(B.arrivals))
		return 0
	var/started = TICK_USAGE_REAL
	var/told = 0
	while(length(B.arrivals))
		var/list/arrival = B.arrivals[1]
		var/list/holders = arrival[3]
		while(length(holders))
			var/datum/client_glow_holder/H = holders[1]
			holders.Cut(1, 2)
			if(QDELETED(H))
				continue
			H.shape_ready(arrival[1], arrival[2])
			told++
			if(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
				break
		if(!length(holders))
			B.arrivals.Cut(1, 2)
		if(told && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= budget_ms)
			break
	B.arrival_steps++
	B.arrival_told += told
	if(length(B.arrivals))
		client_glow_baker_wake()
	return told

/// (Tests, nothing else: it blocks.) Bakes a shape on the spot and returns the PNG's path; the caller deletes it.
/proc/client_glow_mask_bake_blocking(key)
	client_glow_mask_dir_ready()
	var/sheet = "cglow_test_[md5(key)]"
	return client_glow_mask_png(sheet, rustg_iconforge_generate(CLIENT_GLOW_MASK_DIR, sheet, json_encode(list("mask" = client_glow_mask_sprite(key))), FALSE, FALSE, TRUE))

/proc/client_glow_mask_stats()
	var/baked = GLOB.client_glow_baker.baked
	return "client glow masks: [length(GLOB.client_glow_baker.icons)] cached, [baked] baked, [GLOB.client_glow_baker.hits] hits, [GLOB.client_glow_baker.misses] misses, [GLOB.client_glow_baker.failed] failed, [GLOB.client_glow_baker.refused] refused, [GLOB.client_glow_baker.evicted] evicted, [GLOB.client_glow_baker.prefetched] prefetched, [length(GLOB.client_glow_baker.pending)] waiting, mean wait [baked ? round(GLOB.client_glow_baker.wait_ds / baked, 0.1) : 0] ds"

/// Recomputes this light's reach after an opacity change and rebuilds the mask only if the reach changed.
/datum/light_source/proc/client_glow_mask_refresh()
	if(!glow || !glow_mask_key || !source_turf)
		return
	if(client_glow_mask_apply(glow_mask_range, glow_mask_margin))
		var/twin = (glow_mask_key in glow_twins) || GLOB.client_glow_baker.icons[glow_mask_key] // the shape the door's other state was readied as, or any already baked
		if(twin)
			GLOB.client_glow_twin_hits++
		if(client_glow_trace_line())
			log_world("client glow: light at [source_turf.x],[source_turf.y],[source_turf.z] took a new shape after an opacity change, [twin ? "already baked" : "not baked yet: viewers wait for the bake"]")
		client_glow_holders_consider(src) // the held copies take the new mask
		client_flat_lights_refresh(src) // a turf in the reach may have gone dark or lit

/// Recomputes this light's reach and mask shape (client_glow_apply()). `margin` is the glow sprite's: the baked mask is the same size,
/// so the two line up with no offset. TRUE when the shape changed.
/datum/light_source/proc/client_glow_mask_apply(range, margin)
	glow_mask_range = range
	glow_mask_margin = margin
	// The reach first, as a shape key: an opacity change that leaves this light's reach as it was (most of them) stops here.
	var/list/seen = sight_view_turfs(source_turf, range)
	var/sx = source_turf.x
	var/sy = source_turf.y
	var/key = client_glow_shape_key(source_turf, margin, seen)
	if(key == glow_mask_key && glow_reach_origin == source_turf)
		return
	// Lum watches (watched(T, WATCH_LUM)) on turfs this light lit or now lights hear about it.
	var/watching = SSwatched.client_lum_watching()
	var/list/watched_turfs = watching ? client_glow_watched_reach() : list()
	var/list/reach = list()
	for(var/turf/T as anything in seen)
		reach["[T.x - sx],[T.y - sy]"] = TRUE
		if(watching && SSwatched.client_lum_watched(T))
			watched_turfs |= T
	glow_reach = reach
	glow_reach_origin = source_turf // ALLOW(ownership): lighting engine turf cache, rewritten on every mask rebuild like source_turf; a turf relation index entry per rebuild would grow without bound
	for(var/turf/W as anything in watched_turfs)
		SSwatched.lum_changed(W)
	GLOB.client_glow_mask_builds++
	glow_mask_key = key
	client_glow_index(TRUE)
	return TRUE

/// The shape key of a light on `S` whose sight is `seen` (client_glow_mask_sprite()'s "margin|dx,dy,...|blocked dx,dy,..."). `flipped`, when given, is read as blocking as
/// `flipped_dirs` says instead of as its directional_opacity does (the other state of a door).
/proc/client_glow_shape_key(turf/S, margin, list/seen, turf/flipped = null, flipped_dirs = NONE)
	var/list/offsets = list()
	var/list/blocked = list()
	for(var/turf/T as anything in seen)
		if((T == flipped ? flipped_dirs : T.directional_opacity) == ALL_CARDINALS)
			blocked += T.x - S.x
			blocked += T.y - S.y
			continue // a fully opaque tile (a border object leaves the rest of its tile lit); an opaque tile, the light's own included, is lit from the visible floor beside it, not by this cut
		offsets += T.x - S.x
		offsets += T.y - S.y
	return "[margin]|[jointext(offsets, ",")]|[jointext(blocked, ",")]"

/// How the directional opacity of `T` would read with door `D` in its other state, or null when the door's other state changes nothing a shape can show (it never blocks,
/// stands on a border, or another full-tile blocker holds the tile either way).
/proc/client_glow_door_flip(obj/machinery/door/D, turf/T)
	if((D.flags & ON_BORDER) || T.opacity)
		return null
	if(!D.opacity) // open: shut, it would block the tile, if it can block at all
		if(!D.visible || D.glass || T.directional_opacity == ALL_CARDINALS)
			return null
		return ALL_CARDINALS
	var/dirs = NONE // shut: open, the tile blocks only as the other sources it carries do
	for(var/atom/movable/O as anything in T.opacity_sources)
		if(O == D)
			continue
		if(!(O.flags & ON_BORDER))
			return null
		dirs |= O.dir
	return dirs

/// Readies the shapes this light takes when each door in its reach is flipped (the nearest CLIENT_GLOW_TWIN_MAX): the shape key with that door's tile read in its other state,
/// asked of the sight layer without touching the door. Each is baked ahead (client_glow_mask_prefetch()) and the viewers holding the
/// light are sent it (client_glow_holder queue_twins()), so when the door moves the light's new shape is already cached and on the client: the swap is the same step as the
/// opacity change. Done once per shape of the light; a viewer asks when it holds the light.
/datum/light_source/proc/client_glow_twins_ready()
	if(!glow_mask_key || !source_turf || glow_twins_for == glow_mask_key)
		return
	glow_twins_for = glow_mask_key
	glow_twins = null
	var/turf/S = source_turf
	var/list/near = client_glow_near_doors(S, glow_mask_range) // door -> distance, the nearest first
	GLOB.client_glow_twin_lights++
	if(!length(near))
		return
	sortTim(near, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
	var/list/cells = client_glow_door_cells(near)
	var/found = 0
	if(length(cells)) // one call: the flip, the shadowcast and the key of each door's twin happen in the sight layer
		for(var/key in sight_twin_keys(S, glow_mask_range, glow_mask_margin, cells, glow_mask_key, CLIENT_GLOW_TWIN_MAX))
			LAZYADD(glow_twins, key)
			client_glow_mask_prefetch(key)
			GLOB.client_glow_twins_made++
			found++
	if(found && client_glow_trace_line())
		log_world("client glow: light at [S.x],[S.y],[S.z] readied [found] door twin shape(s) ahead")

/// The doors a light on `S` of reach `range` could flip its shape with: door -> distance, from the door chunks under its reach box only (not every door in the world).
/proc/client_glow_near_doors(turf/S, range)
	. = list()
	var/list/box = glow_reach_box(S, range)
	var/list/chunks = glow_chunk_range(list(max(box[1], 1), max(box[2], 1), min(box[3], world.maxx), min(box[4], world.maxy)))
	var/examined = 0
	for(var/gx in chunks[1] to chunks[3])
		for(var/gy in chunks[2] to chunks[4])
			for(var/obj/machinery/door/D as anything in GLOB.client_glow_door_chunks[client_glow_chunk_id(S.z, gx, gy)])
				examined++
				var/turf/T = D.loc
				if(!isturf(T) || CLIENT_GLOW_CLEAR_OF(T.x, T.y, 0, box))
					continue
				.[D] = abs(T.x - S.x) + abs(T.y - S.y)
	GLOB.client_glow_twin_doors_examined += examined

/// The flat `x, y, z, dirs` list of the doors in `near` (nearest first) whose other state changes what a shape shows: the cells sight_twin_keys() reads as flipped, one at a time.
/proc/client_glow_door_cells(list/near)
	. = list()
	for(var/obj/machinery/door/D as anything in near)
		var/turf/T = D.loc
		var/dirs = client_glow_door_flip(D, T)
		if(isnull(dirs))
			continue
		. += list(T.x, T.y, T.z, dirs)

/// Files this door under the chunk it stands in (client_glow_near_doors()); cheap when it is where it was. Called on init and after every move.
/obj/machinery/door/proc/glow_door_index()
	var/turf/T = loc
	var/key = isturf(T) ? client_glow_chunk_id(T.z, CLIENT_GLOW_CHUNK_OF(T.x), CLIENT_GLOW_CHUNK_OF(T.y)) : null
	if(key == glow_door_chunk)
		return
	glow_door_unindex()
	if(!key)
		return
	var/list/members = GLOB.client_glow_door_chunks[key]
	if(!members)
		members = GLOB.client_glow_door_chunks[key] = list()
	members += src
	glow_door_chunk = key

/// Takes this door out of its chunk (it left the map or is going).
/obj/machinery/door/proc/glow_door_unindex()
	if(!glow_door_chunk)
		return
	var/list/members = GLOB.client_glow_door_chunks[glow_door_chunk]
	if(members)
		members -= src
		if(!length(members))
			GLOB.client_glow_door_chunks -= glow_door_chunk
	glow_door_chunk = null

/// The watched turfs (lum bands) in this light's last reach.
/datum/light_source/proc/client_glow_watched_reach()
	. = list()
	var/turf/O = glow_reach_origin
	if(!O || !glow_reach)
		return
	for(var/key in glow_reach)
		var/list/xy = splittext(key, ",")
		var/turf/T = locate(O.x + text2num(xy[1]), O.y + text2num(xy[2]), O.z)
		if(T && SSwatched.client_lum_watched(T))
			. += T

/// Keeps this light in (or out of) the chunk index: under every chunk its reach box overlaps. Cheap when its chunks are as they were.
/datum/light_source/proc/client_glow_index(on)
	var/list/box
	if(on && source_turf)
		var/list/reach_box = glow_reach_box(source_turf, CLIENT_GLOW_RADIUS(src))
		var/list/range = glow_chunk_range(list(max(reach_box[1], 1), max(reach_box[2], 1), min(reach_box[3], world.maxx), min(reach_box[4], world.maxy)))
		box = list(source_turf.z, range[1], range[2], range[3], range[4])
	var/list/was = glow_chunk_box
	if(!box && !was)
		return
	if(box && was && box[1] == was[1] && box[2] == was[2] && box[3] == was[3] && box[4] == was[4] && box[5] == was[5])
		return
	if(was)
		for(var/gx in was[2] to was[4])
			for(var/gy in was[3] to was[5])
				var/key = client_glow_chunk_id(was[1], gx, gy)
				var/list/old = GLOB.client_glow_chunks[key]
				if(!old)
					continue
				old -= src
				if(!length(old))
					GLOB.client_glow_chunks -= key
	glow_chunk_box = box
	if(box)
		for(var/gx in box[2] to box[4])
			for(var/gy in box[3] to box[5])
				var/key = client_glow_chunk_id(box[1], gx, gy)
				var/list/members = GLOB.client_glow_chunks[key]
				if(!members)
					members = GLOB.client_glow_chunks[key] = list()
				members += src

/// The mask goes with the glow.
/datum/light_source/proc/client_glow_mask_clear()
	client_glow_index(FALSE)
	for(var/turf/W as anything in client_glow_watched_reach())
		SSwatched.lum_changed(W)
	glow_mask_key = null
	glow_reach = null
	glow_reach_origin = null // ALLOW(ownership): lighting engine turf cache cleared with the mask, like source_turf

/// The value of a light's entry in client_glow_dirty_lights: far from every viewer, or in a chunk one holds.
#define CLIENT_GLOW_DIRTY_FAR 1
#define CLIENT_GLOW_DIRTY_NEAR 2

/// Opacity changed on `T` (reconsider_lights()): every glowing light whose reach covers it is marked, and redraws its mask once at the next lighting step however many
/// turfs changed (client_glow_reconsider_flush()): an explosion that opens fifty walls redraws each light once. The holders whose eye sees `T` are marked the same way.
/proc/client_glow_reconsider(turf/T)
	var/list/at = list(T.x, T.y, T.x, T.y)
	for(var/datum/light_source/L as anything in GLOB.client_glow_chunks[client_glow_chunk_id(T.z, CLIENT_GLOW_CHUNK_OF(T.x), CLIENT_GLOW_CHUNK_OF(T.y))])
		if(QDELETED(L))
			continue
		var/h = L.glow_holder_key || L.glow_holder_key()
		var/turf/S = L.source_turf
		if(!S || CLIENT_GLOW_CLEAR_OF(S.x, S.y, CLIENT_GLOW_RADIUS(L), at))
			continue
		var/near = interest_covers(S) ? CLIENT_GLOW_DIRTY_NEAR : CLIENT_GLOW_DIRTY_FAR // a light in a chunk some viewer holds redraws before the others, as the near source queue does
		if(GLOB.client_glow_dirty_lights[h] >= near)
			continue
		GLOB.client_glow_dirty_lights[h] = near
	var/list/box = GLOB.client_glow_dirty_boxes["[T.z]"]
	if(box)
		box[1] = min(box[1], T.x)
		box[2] = min(box[2], T.y)
		box[3] = max(box[3], T.x)
		box[4] = max(box[4], T.y)
	else
		GLOB.client_glow_dirty_boxes["[T.z]"] = list(T.x, T.y, T.x, T.y)
	GLOB.client_glow_flush_changes++

/// The lighting step's turn for the opacity changes since the last one (light_step()): each marked light redraws its mask once, then the holders whose eye sees a changed turf
/// take the new sight and move the glows standing on turfs they no longer see. At most until the tick is out of time (unless `all`): the rest waits for the next step.
/proc/client_glow_reconsider_flush(all = FALSE)
	if(!length(GLOB.client_glow_dirty_lights) && !length(GLOB.client_glow_dirty_boxes))
		return
	GLOB.client_glow_flushes++
	var/started = TICK_USAGE_REAL
	var/redrawn = 0
	var/list/todo = list()
	for(var/h in GLOB.client_glow_dirty_lights) // the lights a viewer holds the chunk of first
		if(GLOB.client_glow_dirty_lights[h] >= CLIENT_GLOW_DIRTY_NEAR)
			todo[h] = CLIENT_GLOW_DIRTY_NEAR
	var/near_count = length(todo)
	for(var/h in GLOB.client_glow_dirty_lights)
		if(!todo[h])
			todo[h] = CLIENT_GLOW_DIRTY_FAR
	GLOB.client_glow_dirty_lights = list()
	var/done = 0
	var/list/queued = todo.Copy()
	for(var/h in todo)
		done++
		// A near light (a door beside a viewer) is redrawn whatever the tick has left, up to CLIENT_GLOW_NEAR_REDRAW_MAX: the shadows round a player never wait behind the budget.
		if(!all && KERNEL_OVER_BUDGET && !(done <= near_count && done <= CLIENT_GLOW_NEAR_REDRAW_MAX))
			for(var/i in done to length(queued))
				var/key = queued[i]
				GLOB.client_glow_dirty_lights[key] = queued[key] // the rest waits for the next step
			break
		var/datum/light_source/L = handle_get(h)
		if(!istype(L) || QDELETED(L))
			continue
		GLOB.client_glow_reconsiders++
		redrawn++
		L.client_glow_mask_refresh() // only the mask: the glow's place, size and tint did not change
	if(length(GLOB.client_glow_dirty_lights))
		return // out of time: the holders follow when the last light is redrawn, so they see the shapes the lights now have
	var/list/boxes = GLOB.client_glow_dirty_boxes
	GLOB.client_glow_dirty_boxes = list()
	var/sighted = 0
	for(var/datum/client_glow_holder/H as anything in REGISTRY_COPY(REGISTRY_CLIENT_GLOW_HOLDERS))
		var/list/box = boxes["[H.z]"]
		if(box && H.sig && H.sees_box(box))
			H.sight_refresh()
			sighted++
	if(client_glow_trace_line())
		log_world("client glow flush: [redrawn] light(s) redrawn, [sighted] viewer(s) took new sight, [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), 0.01)] ms")

/// One line on what the glows are: how many, how much of their square each mask lets through, and how strong they are. Reads the chunk index, not every datum.
/proc/client_glow_census()
	var/glows = 0
	var/tiles = 0
	var/possible = 0
	var/faint = 0
	var/one_tile = 0
	var/list/counted = list()
	for(var/key in GLOB.client_glow_chunks)
		for(var/datum/light_source/L as anything in GLOB.client_glow_chunks[key])
			if(counted[L] || QDELETED(L) || !L.glow)
				continue
			counted[L] = TRUE
			glows++
			var/reached = length(L.glow_reach)
			var/side = 2 * L.glow_mask_range + 1
			tiles += reached
			possible += side * side
			if(reached <= 1)
				one_tile++
			var/obj/effect/overlay/client_glow/G = L.glow
			if(G.alpha < 128)
				faint++
	return "client glows: [glows] glow(s), masks open on [possible ? round(100 * tiles / possible) : 0]% of their squares ([tiles]/[possible] tiles), [one_tile] with one tile or none, [faint] under half strength; [client_glow_mask_stats()]"
