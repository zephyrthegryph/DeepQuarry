// ---- eyes: who is looking where ----
//
// The map is cut into GAZE_CHUNK x GAZE_CHUNK turf chunks per z-level. A client's eye (its view window, its mob, and the levels its view looks down
// through open space) holds chunks; the count of holders per chunk is the grid. Two things read it and nothing else:
//
//   - gaze_covers(turf): "is a viewer near here": a footstep, a light's glow, anything whose work is for a watcher;
//   - the draw queue's order (draw_queue.dm): the buckets nearest any client's eye drain first. The order is computed from `gaze_at`, the turf each client
//     looks from, when the queue has work; a moving client changes the order of work that exists, and creates none.
//
// A hold is set by an event and never by a poll: gaze_update() runs when a client's eye moved or changed (mob Moved, client.set_eye(), login), its view size
// changed (set_viewsize()), a container that carries the eye or the mob moved (gaze_anchor_moved()), and open space around it appeared or went
// (gaze_open_changed()). It returns at once when the chunk rectangle of its view window is the one it holds already, which is nearly every step.
// Nothing here draws anything: no chunk is scanned, no draw is owed to a chunk, and a chunk entering or leaving a hold costs a counter.

/// z -> list(cx + 1 -> list(cy + 1 -> how many observers hold that chunk)). Built on demand; a missing cell is a chunk nobody holds.
GLOBAL_LIST_EMPTY(gaze_grid)
/// Observer key (a client's handle_of()) -> the list of chunk keys it holds.
GLOBAL_ALIST_EMPTY(gaze_holds)
/// Observer key -> the chunk rectangle of its view window, as text (gaze_view_set()). Equal text, nothing to do.
GLOBAL_ALIST_EMPTY(gaze_sigs)
/// Observer key -> the turf its eye looks from (and its mob's, when that is another): what the draw queue's order is measured from.
GLOBAL_ALIST_EMPTY(gaze_at)
/// Anchor handle (the atom a client's eye or mob is carried by, standing on a turf) -> the list of client tokens it carries. Its Moved() updates them.
GLOBAL_ALIST_EMPTY(gaze_anchors)
/// Chunks that gained their first holder, and chunks that lost their last.
GLOBAL_VAR_INIT(gaze_chunks_entered, 0)
GLOBAL_VAR_INIT(gaze_chunks_left, 0)

/// The anchors (handles of the atoms standing on a turf that carry this client's eye or mob) registered for this client.
/client/var/tmp/list/gaze_anchor_handles

/// How many observers hold the chunk (z, cx, cy).
/proc/gaze_count(z, cx, cy)
	var/list/grid = GLOB.gaze_grid
	if(z > length(grid))
		return 0
	var/list/col = grid[z]
	if(!col || cx + 1 > length(col))
		return 0
	var/list/row = col[cx + 1]
	if(!row || cy + 1 > length(row))
		return 0
	return row[cy + 1] || 0

/// Adds `step` to the hold count of the chunk (z, cx, cy) and returns the new count.
/proc/gaze_adjust(z, cx, cy, step)
	var/list/grid = GLOB.gaze_grid
	if(length(grid) < z)
		grid.len = z
	var/list/col = grid[z]
	if(!col)
		col = list()
		grid[z] = col
	if(length(col) < cx + 1)
		col.len = cx + 1
	var/list/row = col[cx + 1]
	if(!row)
		row = list()
		col[cx + 1] = row
	if(length(row) < cy + 1)
		row.len = cy + 1
	var/count = max(0, (row[cy + 1] || 0) + step)
	row[cy + 1] = count
	return count

/// TRUE when some observer holds the chunk `T` stands in (a client's view window or the one chunk round it).
/proc/gaze_covers(turf/T)
	return gaze_count(T.z, GAZE_CHUNK_OF(T.x), GAZE_CHUNK_OF(T.y)) > 0

/// The chunk keys of the turf rectangle (x0, y0) to (x1, y1) on z, added to `into` once each.
/proc/gaze_rect_keys(list/into, z, x0, y0, x1, y1)
	for(var/cx in GAZE_CHUNK_OF(max(1, x0)) to GAZE_CHUNK_OF(min(world.maxx, x1)))
		for(var/cy in GAZE_CHUNK_OF(max(1, y0)) to GAZE_CHUNK_OF(min(world.maxy, y1)))
			into |= GAZE_KEY(z, cx, cy)

/// Sets what `owner` (an observer key) holds to `keys` (chunk keys; null or empty releases everything). Only the grid's counts change.
/proc/gaze_hold_set(owner, list/keys)
	var/list/was = GLOB.gaze_holds[owner]
	for(var/key in keys)
		if(was && (key in was))
			continue
		if(gaze_adjust(round(key / 1048576), round((key % 1048576) / 1024), key % 1024, 1) == 1)
			GLOB.gaze_chunks_entered++
	for(var/key in was)
		if(keys && (key in keys))
			continue
		if(!gaze_adjust(round(key / 1048576), round((key % 1048576) / 1024), key % 1024, -1))
			GLOB.gaze_chunks_left++
	if(length(keys))
		GLOB.gaze_holds[owner] = keys
	else
		GLOB.gaze_holds -= owner

/// Half the width of what a client with this `view` setting sees (a number, or "WxH": the longer side's half).
/proc/gaze_view_half(view)
	if(isnum(view))
		return view
	if(istext(view))
		var/list/size = splittext(view, "x")
		return round(max(text2num(size[1]), text2num(size[length(size)])) / 2)
	return world.view

/// The chunk rectangle of the view window (half + 2 turfs round `where`): "z:cx0:cx1:cy0:cy1".
/proc/gaze_rect_sig(turf/where, half)
	var/window = half + 2
	return "[where.z]:[GAZE_CHUNK_OF(max(1, where.x - window))]:[GAZE_CHUNK_OF(min(world.maxx, where.x + window))]:[GAZE_CHUNK_OF(max(1, where.y - window))]:[GAZE_CHUNK_OF(min(world.maxy, where.y + window))]"

/// The chunks a viewer standing at `where` holds: the chunks of its view window and of every turf the window shows through (open space: seen_through() is
/// the turf whose contents this one shows), followed down for up to GAZE_THROUGH_DEPTH layers, and the ring of one chunk round the window.
/proc/gaze_view_keys(turf/where, half)
	var/window = half + 2
	var/list/keys = list()
	gaze_rect_keys(keys, where.z, where.x - window - GAZE_CHUNK, where.y - window - GAZE_CHUNK, where.x + window + GAZE_CHUNK, where.y + window + GAZE_CHUNK)
	var/list/frontier = block(locate(max(1, where.x - window), max(1, where.y - window), where.z), locate(min(world.maxx, where.x + window), min(world.maxy, where.y + window), where.z))
	var/list/reached = list()
	for(var/depth in 1 to GAZE_THROUGH_DEPTH)
		var/list/next = list()
		for(var/turf/T as anything in frontier)
			var/turf/below = T.seen_through()
			if(!below || reached[below])
				continue
			reached[below] = TRUE
			gaze_rect_keys(keys, below.z, below.x, below.y, below.x, below.y)
			next += below
		if(!length(next))
			break
		frontier = next
	return keys

/// The client's eye or view changed: its hold follows. Cheap when the chunk rectangle of its view window is the one it holds.
/proc/gaze_update(client/C)
	if(!C || QDELETED(C))
		return
	var/mob/M = C.mob
	var/atom/eye = C.eye || M
	var/turf/at_eye = get_turf(eye)
	var/turf/at_mob = get_turf(M)
	if(eye != M || (M && !isturf(M.loc)) || C.gaze_anchor_handles)
		gaze_anchor_sync(C, eye, M)
	var/token = handle_of(C)
	if(token)
		GLOB.gaze_at[token] = at_eye || at_mob
	gaze_view_set(token, at_eye, at_mob, gaze_view_half(C.view))
	C.gaze_moved(at_eye)

/// Observer `token` sees from `at_eye` and from `at_mob` (either may be null) with a view of half-width `half`: its hold follows. Returns TRUE when the
/// hold changed. Nothing happens while the chunk rectangles of its view window are the ones it holds already.
/proc/gaze_view_set(token, turf/at_eye, turf/at_mob, half)
	var/sig = at_eye ? gaze_rect_sig(at_eye, half) : ""
	if(at_mob && at_mob != at_eye)
		sig += "|[gaze_rect_sig(at_mob, half)]"
	if(sig == GLOB.gaze_sigs[token])
		return FALSE
	GLOB.gaze_sigs[token] = sig
	var/list/keys
	if(at_eye)
		keys = gaze_view_keys(at_eye, half)
	if(at_mob && at_mob != at_eye)
		keys = (keys || list()) | gaze_view_keys(at_mob, half)
	gaze_hold_set(token, keys)
	return TRUE

/// Virtual: the client's eye was placed (it may not have moved): content that follows the eye hooks here (client_glow_holder.dm).
/client/proc/gaze_moved(turf/at_eye)
	return

/// Virtual: the client stopped observing (it left).
/client/proc/gaze_left()
	return

/// The client left: it holds nothing.
/proc/gaze_remove(client/C)
	if(!C)
		return
	gaze_anchor_sync(C, null, null)
	C.gaze_left()
	var/token = handle_of(C)
	GLOB.gaze_sigs -= token
	GLOB.gaze_at -= token
	if(token && GLOB.gaze_holds[token])
		gaze_hold_set(token, null)

/// The atom standing on a turf that carries `A` (A itself when it stands on one), or null for a turf.
/proc/gaze_top(atom/A)
	if(!A || isturf(A))
		return null
	var/depth = 0
	while(A.loc && !isturf(A.loc) && depth++ < 64)
		A = A.loc
	return A

/// Registers the atoms that carry `C`'s eye and mob, so their Moved() updates the hold: a mob in a closet, a mech or a vehicle moves with no Moved() of its own.
/// The mob standing on a turf is not one (mob Moved() already updates). `eye` and `M` null drop every anchor.
/proc/gaze_anchor_sync(client/C, atom/eye, mob/M)
	var/list/want
	for(var/atom/source in list(eye, M))
		var/atom/top = gaze_top(source)
		if(!top || top == M)
			continue
		var/handle = handle_of(top)
		if(handle)
			LAZYADD(want, handle)
	var/token = handle_of(C)
	for(var/handle in C.gaze_anchor_handles)
		if(want && (handle in want))
			continue
		var/list/who = GLOB.gaze_anchors[handle]
		who -= token
		if(!length(who))
			GLOB.gaze_anchors -= handle
	for(var/handle in want)
		if(C.gaze_anchor_handles && (handle in C.gaze_anchor_handles))
			continue
		var/list/who = GLOB.gaze_anchors[handle]
		if(!who)
			who = list()
			GLOB.gaze_anchors[handle] = who
		who |= token
	C.gaze_anchor_handles = want

/// A registered anchor moved (atom/movable Moved()): the clients it carries update their hold.
/proc/gaze_anchor_moved(atom/movable/M)
	var/handle = entity_handle_of(M)
	var/list/who = handle ? GLOB.gaze_anchors[handle] : null
	if(!who)
		return
	for(var/token in who.Copy())
		var/client/C = handle_get(token)
		if(C)
			gaze_update(C)

/// Open space appeared or went at `T` (z_transparency): every client whose hold reaches it recomputes what it looks down through.
/proc/gaze_open_changed(turf/T)
	if(!length(GLOB.gaze_holds))
		return
	for(var/client/C as anything in GLOB.clients)
		if(C && GLOB.gaze_sigs[handle_of(C)])
			var/turf/at = get_turf(C.eye || C.mob)
			var/reach = gaze_view_half(C.view) + 2 + GAZE_CHUNK
			if(at && at.z >= T.z && abs(at.x - T.x) <= reach && abs(at.y - T.y) <= reach)
				GLOB.gaze_sigs -= handle_of(C)
				gaze_update(C)
