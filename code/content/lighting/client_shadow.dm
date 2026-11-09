// Client lighting, piece 2: baked shapes. Each glow is the light's sprite already cut to the open floor its light reaches (the world opacity
// layer's sight from the light's turf, code/domains/verdigris/sight/), baked off-thread by iconforge, white so one icon serves every colour,
// and shared by every light with the same reach. No filter per light, and nothing depends on another object being drawn. Opaque tiles are not in the
// cut: walls take their light from the visible floor beside them, on the glow plane (client_lighting_compare.dm). The gameplay reach (glow_reach) still has them.
// A viewer's glow is the plain sprite until its shape is first baked; after a change it keeps its previous cut until the new one lands. A reach is recomputed only when its light is redrawn (it moved or changed) or
// when opacity changes inside its reach (a door, a wall built), found through a per-chunk index of glowing lights.


/// Cumulative mask rebuilds and reach-triggered redraws (benchmarks, the door test).
GLOBAL_VAR_INIT(client_glow_mask_builds, 0)
GLOBAL_VAR_INIT(client_glow_reconsiders, 0)
/// "z,cx,cy" -> lights glowing from that chunk (client lighting only).
GLOBAL_LIST_EMPTY(client_glow_chunks)

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
	/// The chunk key this light is indexed under while it glows.
	var/glow_chunk

/proc/client_glow_chunk_key(z, x, y)
	return "[z],[round((x - 1) / CLIENT_GLOW_CHUNK)],[round((y - 1) / CLIENT_GLOW_CHUNK)]"

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

/// The baked mask of this shape, or null while it is not ready (asks for it).
/proc/client_glow_mask_icon(key)
	var/found = GLOB.client_glow_baker.icons[key]
	if(found)
		GLOB.client_glow_baker.hits++
		return found
	GLOB.client_glow_baker.misses++
	client_glow_mask_request(key)
	return null

/proc/client_glow_mask_request(key)
	if(GLOB.client_glow_baker.pending[key])
		return
	if(length(GLOB.client_glow_baker.pending) >= CLIENT_GLOW_MASK_QUEUE_MAX)
		GLOB.client_glow_baker.refused++ // asked again the next time a viewer considers the light
		return
	GLOB.client_glow_baker.pending[key] = TRUE
	GLOB.client_glow_baker.asked_at[key] = REALTIMEOFDAY
	GLOB.client_glow_baker.queue += key
	client_glow_mask_pump()

/proc/client_glow_mask_dir_ready()
	var/static/made = FALSE
	if(!made)
		rustg_file_write("", "[CLIENT_GLOW_MASK_DIR].keep")
		made = TRUE

/proc/client_glow_mask_pump()
	while(GLOB.client_glow_baker.inflight < CLIENT_GLOW_MASK_BAKES_MAX && length(GLOB.client_glow_baker.queue))
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
	GLOB.client_glow_baker.icons[key] = res
	if(length(GLOB.client_glow_baker.icons) > CLIENT_GLOW_MASK_CACHE_MAX)
		GLOB.client_glow_baker.icons.Cut(1, 2)
		GLOB.client_glow_baker.evicted++
	GLOB.client_glow_baker.baked++
	if(!length(GLOB.client_glow_baker.pending))
		log_world("client glow masks: queue drained at [time2text(world.realtime, "hh:mm:ss")]; [client_glow_mask_stats()]") // the load-in timeline, with the first hold line
	if(!(GLOB.client_glow_baker.baked % 64))
		log_world(client_glow_mask_stats())
	for(var/datum/client_glow_holder/H as anything in REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS))
		H.shape_ready(key, res)

/// (Tests, nothing else: it blocks.) Bakes a shape on the spot and returns the PNG's path; the caller deletes it.
/proc/client_glow_mask_bake_blocking(key)
	client_glow_mask_dir_ready()
	var/sheet = "cglow_test_[md5(key)]"
	return client_glow_mask_png(sheet, rustg_iconforge_generate(CLIENT_GLOW_MASK_DIR, sheet, json_encode(list("mask" = client_glow_mask_sprite(key))), FALSE, FALSE, TRUE))

/proc/client_glow_mask_stats()
	var/baked = GLOB.client_glow_baker.baked
	return "client glow masks: [length(GLOB.client_glow_baker.icons)] cached, [baked] baked, [GLOB.client_glow_baker.hits] hits, [GLOB.client_glow_baker.misses] misses, [GLOB.client_glow_baker.failed] failed, [GLOB.client_glow_baker.refused] refused, [GLOB.client_glow_baker.evicted] evicted, [length(GLOB.client_glow_baker.pending)] waiting, mean wait [baked ? round(GLOB.client_glow_baker.wait_ds / baked, 0.1) : 0] ds"

/// Recomputes this light's reach after an opacity change and rebuilds the mask only if the reach changed.
/datum/light_source/proc/client_glow_mask_refresh()
	if(!glow || !glow_mask_key || !source_turf)
		return
	if(client_glow_mask_apply(glow_mask_range, glow_mask_margin))
		client_glow_holders_consider(src) // the held copies take the new mask

/// Recomputes this light's reach and mask shape (client_glow_apply()). `margin` is the glow sprite's: the baked mask is the same size,
/// so the two line up with no offset. TRUE when the shape changed.
/datum/light_source/proc/client_glow_mask_apply(range, margin)
	glow_mask_range = range
	glow_mask_margin = margin
	// The reach first, as a shape key: an opacity change that leaves this light's reach as it was (most of them) stops here.
	var/list/seen = sight_view_turfs(source_turf, range)
	var/list/offsets = list()
	var/list/blocked = list()
	var/sx = source_turf.x
	var/sy = source_turf.y
	for(var/turf/T as anything in seen)
		if(T.directional_opacity == ALL_CARDINALS)
			blocked += T.x - sx
			blocked += T.y - sy
			continue // a fully opaque tile (a border object leaves the rest of its tile lit); an opaque tile, the light's own included, is lit from the visible floor beside it, not by this cut
		offsets += T.x - sx
		offsets += T.y - sy
	var/key = "[margin]|[jointext(offsets, ",")]|[jointext(blocked, ",")]"
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

/// Keeps this light in (or out of) the chunk index opacity changes look up.
/datum/light_source/proc/client_glow_index(on)
	var/key = on && source_turf ? client_glow_chunk_key(source_turf.z, source_turf.x, source_turf.y) : null
	if(key == glow_chunk)
		return
	if(glow_chunk)
		var/list/old = GLOB.client_glow_chunks[glow_chunk]
		old -= src
		if(!length(old))
			GLOB.client_glow_chunks -= glow_chunk
	glow_chunk = key
	if(key)
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

/// Opacity changed on `T` (reconsider_lights()): every glowing light whose reach covers it redraws its mask.
/proc/client_glow_reconsider(turf/T)
	var/cx = round((T.x - 1) / CLIENT_GLOW_CHUNK)
	var/cy = round((T.y - 1) / CLIENT_GLOW_CHUNK)
	var/span = CEILING(CLIENT_GLOW_MAX_RANGE / CLIENT_GLOW_CHUNK, 1)
	for(var/dx = -span, dx <= span, dx++)
		for(var/dy = -span, dy <= span, dy++)
			for(var/datum/light_source/L as anything in GLOB.client_glow_chunks["[T.z],[cx + dx],[cy + dy]"])
				if(QDELETED(L))
					continue
				var/turf/S = L.source_turf
				if(!S || max(abs(S.x - T.x), abs(S.y - T.y)) > CEILING(L.light_range, 1))
					continue
				GLOB.client_glow_reconsiders++
				L.client_glow_mask_refresh() // only the mask: the glow's place, size and tint did not change

/// One line on what the glows are: how many, how much of their square each mask lets through, and how strong they are.
/proc/client_glow_census()
	var/glows = 0
	var/tiles = 0
	var/possible = 0
	var/faint = 0
	var/one_tile = 0
	for(var/datum/light_source/L)
		if(QDELETED(L) || !L.glow)
			continue
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
