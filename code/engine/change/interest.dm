// ---- chunk interest: who can see what (doc/rewrite/proposals/demand_driven_refresh.md section 3) ----
//
// Presentation work is scheduled by observers. The map is cut into INTEREST_CHUNK x INTEREST_CHUNK turf chunks per z-level, and a chunk is interesting
// while some observer holds it: a client's eye (and its mob, and the open space the view looks down through), or a vis_contents holder that shows
// turfs of it (a camera screen, a picture in picture, a portal). An observer holds a list of chunk keys, set by an event and never by a poll:
//
//   - a client: interest_eye_update() runs when its eye moved or changed (mob Moved, client.set_eye(), login), when its view size changed
//     (set_viewsize()), when a container that carries the eye or the mob moved (interest_anchor_moved()), and when open space around it appeared or went
//     (interest_open_changed()). It returns at once when the chunk rectangle of its view window is the one it holds already, which is nearly every step.
//   - a vis_contents holder that is not a turf: vis_add()/vis_set()/... call interest_vis_sync(). The hold goes with the holder (interest_holder_gone()).
//
// An atom marked while its chunk is not interesting, whose live outputs are its look alone (a lazy type, look_stamp.dm), is parked (DEP_PARKED) instead
// of queued: it owes the draw and costs nothing until a chunk it stands in is entered. A parked atom that moves into an interesting chunk draws
// (interest_parked_moved()).
//
// A client holds the chunks its view window covers (the visible set) and a ring of one chunk around them (the prefetch). A chunk entering the ring has
// its owed draws queued in the presentation lane (FIFO, under its budget): a walker is a chunk away from seeing it, so the queue has time. A chunk
// that becomes visible to an observer has everything it still owes drawn at once, outside the budget (interest_scan(now = TRUE)): the lane being
// behind, a teleport or a zoom never shows an undrawn atom.

/// Edge of a chunk in turfs.
#define INTEREST_CHUNK 16
/// How many levels of stacked open space a client's view is followed down.
#define INTEREST_THROUGH_DEPTH 8
#define INTEREST_CHUNK_OF(v) (round(((v) - 1) / INTEREST_CHUNK))
#define INTEREST_KEY(z, cx, cy) ((z) * 1048576 + (cx) * 1024 + (cy))

/// z -> list(cx + 1 -> list(cy + 1 -> how many observers hold that chunk)). Built on demand; a missing cell is a chunk nobody holds.
GLOBAL_LIST_EMPTY(interest_grid)
/// Observer key (a client's ref_token(), a holder's ref_token()) -> the list of chunk keys it holds.
GLOBAL_LIST_EMPTY(interest_holds)
/// Observer key -> the chunk keys it sees now (the window, the levels below open space, the turfs a holder shows): the ring is held beyond these.
GLOBAL_LIST_EMPTY(interest_visible)
/// Observer key -> the chunk rectangle of its view window, as text (interest_view_set()). Equal text, nothing to do.
GLOBAL_LIST_EMPTY(interest_sigs)
/// Anchor handle (the atom a client's eye or mob is carried by, standing on a turf) -> the list of client tokens it carries. Its Moved() updates them.
GLOBAL_LIST_EMPTY(interest_anchors)
/// TRUE: a mark of an unobserved lazy atom parks it. Test builds default off (the suite marks atoms nobody watches and reads their looks); the deferral tests turn it on.
#if defined(UNIT_TESTS)
GLOBAL_VAR_INIT(interest_defer_marks, FALSE)
#else
GLOBAL_VAR_INIT(interest_defer_marks, TRUE)
#endif
/// Marks that parked an unobserved atom instead of queuing it, and marks that landed on an atom already parked (a redraw that never had to happen).
GLOBAL_VAR_INIT(refresh_deferred, 0)
GLOBAL_VAR_INIT(refresh_deferred_absorbed, 0)
/// Chunks walked for owed draws, chunks that lost their last observer, and owed draws run at once because a chunk became visible.
GLOBAL_VAR_INIT(interest_chunks_entered, 0)
GLOBAL_VAR_INIT(interest_chunks_left, 0)
GLOBAL_VAR_INIT(interest_drawn_now, 0)

/// The anchors (handles of the atoms standing on a turf that carry this client's eye or mob) registered for this client.
/client/var/tmp/list/interest_anchor_handles

// ---- the grid ----

/// How many observers hold the chunk (z, cx, cy).
/proc/interest_count(z, cx, cy)
	var/list/grid = GLOB.interest_grid
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
/proc/interest_adjust(z, cx, cy, step)
	var/list/grid = GLOB.interest_grid
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

/// TRUE when some observer holds the chunk `T` stands in.
/proc/interest_covers(turf/T)
	return interest_count(T.z, INTEREST_CHUNK_OF(T.x), INTEREST_CHUNK_OF(T.y)) > 0

/// TRUE when some observer sees the chunk `T` stands in (not just holds it as prefetch).
/proc/interest_sees(turf/T)
	var/key = INTEREST_KEY(T.z, INTEREST_CHUNK_OF(T.x), INTEREST_CHUNK_OF(T.y))
	for(var/owner in GLOB.interest_visible)
		var/list/seen = GLOB.interest_visible[owner]
		if(key in seen)
			return TRUE
	return FALSE

/// The chunk keys of the turf rectangle (x0, y0) to (x1, y1) on z, added to `into` once each.
/proc/interest_rect_keys(list/into, z, x0, y0, x1, y1)
	for(var/cx in INTEREST_CHUNK_OF(max(1, x0)) to INTEREST_CHUNK_OF(min(world.maxx, x1)))
		for(var/cy in INTEREST_CHUNK_OF(max(1, y0)) to INTEREST_CHUNK_OF(min(world.maxy, y1)))
			into |= INTEREST_KEY(z, cx, cy)

// ---- holds ----

/// Sets what `owner` (an observer key) holds to `keys` (chunk keys; null or empty releases everything), of which `visible` are in its view. A chunk going
/// from unheld to held is walked: the draws it owes are queued, or run at once when the chunk is visible to the owner. A chunk that becomes visible to
/// the owner while already held (it was the ring) has what it still owes drawn at once. A chunk going to unheld is counted, nothing else (what it drew
/// stays drawn).
/proc/interest_hold_set(owner, list/keys, list/visible)
	var/list/was = GLOB.interest_holds[owner]
	var/list/was_visible = GLOB.interest_visible[owner]
	var/list/entered
	for(var/key in keys)
		if(was && (key in was))
			continue
		if(interest_adjust(round(key / 1048576), round((key % 1048576) / 1024), key % 1024, 1) == 1)
			LAZYADD(entered, key)
	for(var/key in was)
		if(keys && (key in keys))
			continue
		if(!interest_adjust(round(key / 1048576), round((key % 1048576) / 1024), key % 1024, -1))
			GLOB.interest_chunks_left++
	if(length(keys))
		GLOB.interest_holds[owner] = keys
		GLOB.interest_visible[owner] = visible || list()
	else
		GLOB.interest_holds -= owner
		GLOB.interest_visible -= owner
	for(var/key in entered)
		interest_scan(round(key / 1048576), round((key % 1048576) / 1024), key % 1024, (key in visible) && !(key in was_visible))
	for(var/key in visible)
		if((was_visible && (key in was_visible)) || (entered && (key in entered)))
			continue
		interest_scan(round(key / 1048576), round((key % 1048576) / 1024), key % 1024, TRUE)

/// Walks the turfs of chunk (z, cx, cy). With `now` everything that still owes a draw there (parked, or queued behind the lane) is drawn on the spot;
/// without it the parked ones join the queue. Returns how many it handled.
/proc/interest_scan(z, cx, cy, now)
	. = 0
	GLOB.interest_chunks_entered++
	if(z < 1 || z > world.maxz)
		return
	var/x0 = cx * INTEREST_CHUNK + 1
	var/y0 = cy * INTEREST_CHUNK + 1
	if(x0 > world.maxx || y0 > world.maxy)
		return
	var/turf/low = locate(x0, y0, z)
	var/turf/high = locate(min(world.maxx, x0 + INTEREST_CHUNK - 1), min(world.maxy, y0 + INTEREST_CHUNK - 1), z)
	for(var/turf/T as anything in block(low, high))
		. += now ? interest_draw_now(T) : interest_wake(T)
		FOR_CONTENTS(var/atom/movable/A as anything, T)
			. += now ? interest_draw_now(A) : interest_wake(A)
	if(.)
		log_world("INTEREST: chunk [cx],[cy] z[z] [now ? "visible, [.] owed draw(s) run now" : "in the ring, [.] parked draw(s) queued"]")

/// A parked `A` owes a draw and something can see its chunk coming: it joins the presentation queue with everything it owed. Returns 1 when it did.
/proc/interest_wake(atom/A)
	if(!(A.refresh_queued & DEP_PARKED) || QDELETED(A) || !interest_ready(A))
		return 0
	A.refresh_queued = DEP_ALL
	A.refresh_bits = 0
	GLOB.refresh_queue += A
	GLOB.refresh_near_drawn++
	GLOB.refresh_parked_near++
	return 1

/// An atom that owes a draw (parked, or queued behind the lane) and can be seen now: it draws on the spot, with everything it owed. The queue entry it
/// leaves is a stale duplicate the drain skips. Returns 1 when it ran.
/proc/interest_draw_now(atom/A)
	var/pending = A.refresh_queued
	if(!pending || QDELETED(A) || !interest_ready(A))
		return 0
	var/parked = pending & DEP_PARKED
	if(parked)
		pending = DEP_ALL // parked is alone in refresh_queued: it owes its whole refresh
		GLOB.refresh_parked_near++
	var/fresh = pending & DEP_CREATED
	pending &= ~(DEP_CREATED | DEP_PARKED)
	var/bits = A.refresh_bits
	A.refresh_queued = 0
	A.refresh_bits = 0
	if(fresh && type_look_stamped(A))
		GLOB.type_look_stamp_skipped++
		return 0
	if(!refresh_wanted_queued(A))
		return 0
	try
		refresh_one(A, bits, pending)
		if(fresh)
			type_look_stamp_record(A)
	catch(var/exception/e)
		dq_report_caught(e, "visible refresh of [A.type]")
	GLOB.interest_drawn_now++
	GLOB.refresh_near_drawn++
	return 1

/// slot of an atom -> how many of its init frames are open past Initialize(): its setup() hooks running (setup_run()), and a map-loaded atom's after_init()
/// entries waiting for the load frame to close and then running (after_init_flush()). Keyed by slot, so it holds no atom: one deleted inside its
/// own frame leaves nothing behind, because slot_free() drops the slot's entry. A real global: atoms initialize while the globals are still being made.
GLOBAL_REAL(init_open, /alist)

/// `A` enters an init frame that runs its own code after Initialize() returned: it is not drawn from here until the frame ends.
/proc/init_open_begin(atom/A)
	var/slot = slot_of(A)
	if(!slot)
		return
	if(!init_open)
		init_open = alist()
	init_open[slot] = (init_open[slot] || 0) + 1

/// The frame ends. The last one out lets a draw it was owed (parked while its init ran, in a chunk someone sees now) happen. An atom deleted inside its
/// frame has lost its slot, and the entry went with it.
/proc/init_open_end(atom/A)
	var/slot = A.handle_slot
	if(!slot || isnull(init_open?[slot]))
		return
	var/left = init_open[slot] - 1
	if(left > 0)
		init_open[slot] = left
		return
	init_open -= slot
	if(!length(init_open))
		init_open = null
	if(!QDELETED(A))
		interest_settle(A)

/// Whether `A` can be drawn from here: it has finished Initialize() and no init frame of its own is open. This is per atom: a map load running elsewhere
/// (an expedition z-level takes seconds) holds back only the atoms it is still setting up, never the parked ones a player walks up to.
/proc/interest_ready(atom/A)
	return (A.flags & ATOM_INITIALIZED) && A != GLOB.atom_initializing && !(A.handle_slot && init_open?[A.handle_slot])

/// A parked atom moved (atom/movable Moved()): into a chunk someone holds it is queued, into one someone sees it draws.
/proc/interest_parked_moved(atom/movable/M)
	interest_settle(M)

/// A parked `A` that owes a draw where an observer holds its chunk: queued when the chunk is only prefetched, drawn now when it is seen.
/proc/interest_settle(atom/A)
	if(!(A.refresh_queued & DEP_PARKED))
		return
	var/turf/T = isturf(A) ? A : A.loc
	if(!isturf(T) || !interest_covers(T))
		return
	if(interest_sees(T))
		interest_draw_now(A)
	else
		interest_wake(A)

/// Whether a mark of `D` parks it: an atom of a lazy type (its live outputs are its look alone) standing on a turf nobody holds. A held item, an atom in a
/// container and a mob always queue: their look is shown wherever they are carried.
/proc/interest_defers(datum/D)
	if(!isatom(D) || ismob(D))
		return FALSE
	var/atom/A = D
	if(!look_lazy_ok(A))
		return FALSE
	var/turf/T = isturf(A) ? A : A.loc
	if(!isturf(T))
		return FALSE
	return !interest_covers(T)

// ---- a client's eye ----

/// Half the width of what a client with this `view` setting sees (a number, or "WxH": the longer side's half).
/proc/interest_view_half(view)
	if(isnum(view))
		return view
	if(istext(view))
		var/list/size = splittext(view, "x")
		return round(max(text2num(size[1]), text2num(size[length(size)])) / 2)
	return world.view

/// The chunk rectangle of the view window (half + 2 turfs round `where`): "z:cx0:cx1:cy0:cy1".
/proc/interest_rect_sig(turf/where, half)
	var/window = half + 2
	return "[where.z]:[INTEREST_CHUNK_OF(max(1, where.x - window))]:[INTEREST_CHUNK_OF(min(world.maxx, where.x + window))]:[INTEREST_CHUNK_OF(max(1, where.y - window))]:[INTEREST_CHUNK_OF(min(world.maxy, where.y + window))]"

/// The chunks a viewer standing at `where` holds. `visible` receives the ones it sees: the chunks of its view window and of every turf the window shows
/// through (open space: seen_through() is the turf whose contents this one shows), followed down for up to INTEREST_THROUGH_DEPTH layers. The result is
/// those and the ring of one chunk round the window.
/proc/interest_view_keys(turf/where, half, list/visible)
	var/window = half + 2
	var/list/seen = visible || list()
	interest_rect_keys(seen, where.z, where.x - window, where.y - window, where.x + window, where.y + window)
	var/list/keys = list()
	interest_rect_keys(keys, where.z, where.x - window - INTEREST_CHUNK, where.y - window - INTEREST_CHUNK, where.x + window + INTEREST_CHUNK, where.y + window + INTEREST_CHUNK)
	var/list/frontier = block(locate(max(1, where.x - window), max(1, where.y - window), where.z), locate(min(world.maxx, where.x + window), min(world.maxy, where.y + window), where.z))
	var/list/reached = list()
	for(var/depth in 1 to INTEREST_THROUGH_DEPTH)
		var/list/next = list()
		for(var/turf/T as anything in frontier)
			var/turf/below = T.seen_through()
			if(!below || reached[below])
				continue
			reached[below] = TRUE
			interest_rect_keys(seen, below.z, below.x, below.y, below.x, below.y)
			next += below
		if(!length(next))
			break
		frontier = next
	return keys | seen

/// The client's eye or view changed: its hold follows. Cheap when the chunk rectangle of its view window is the one it holds.
/proc/interest_eye_update(client/C)
	if(!C || QDELETED(C))
		return
	var/mob/M = C.mob
	var/atom/eye = C.eye || M
	var/turf/at_eye = get_turf(eye)
	var/turf/at_mob = get_turf(M)
	if(eye != M || (M && !isturf(M.loc)) || C.interest_anchor_handles)
		interest_anchor_sync(C, eye, M)
	interest_view_set(ref_token(C), at_eye, at_mob, interest_view_half(C.view))

/// Observer `token` sees from `at_eye` and from `at_mob` (either may be null) with a view of half-width `half`: its hold follows. Returns TRUE when the
/// hold changed. Nothing happens while the chunk rectangles of its view window are the ones it holds already.
/proc/interest_view_set(token, turf/at_eye, turf/at_mob, half)
	var/sig = at_eye ? interest_rect_sig(at_eye, half) : ""
	if(at_mob && at_mob != at_eye)
		sig += "|[interest_rect_sig(at_mob, half)]"
	if(sig == GLOB.interest_sigs[token])
		return FALSE
	GLOB.interest_sigs[token] = sig
	var/list/keys
	var/list/visible = list()
	if(at_eye)
		keys = interest_view_keys(at_eye, half, visible)
	if(at_mob && at_mob != at_eye)
		keys = (keys || list()) | interest_view_keys(at_mob, half, visible)
	interest_hold_set(token, keys, visible)
	return TRUE

/// The client left: it holds nothing.
/proc/interest_eye_remove(client/C)
	if(!C)
		return
	interest_anchor_sync(C, null, null)
	var/token = ref_token(C)
	GLOB.interest_sigs -= token
	if(token && GLOB.interest_holds[token])
		interest_hold_set(token, null)

/// The atom standing on a turf that carries `A` (A itself when it stands on one), or null for a turf.
/proc/interest_top(atom/A)
	if(!A || isturf(A))
		return null
	var/depth = 0
	while(A.loc && !isturf(A.loc) && depth++ < 64)
		A = A.loc
	return A

/// Registers the atoms that carry `C`'s eye and mob, so their Moved() updates the hold: a mob in a closet, a mech or a vehicle moves with no Moved() of its own.
/// The mob standing on a turf is not one (mob Moved() already updates). `eye` and `M` null drop every anchor.
/proc/interest_anchor_sync(client/C, atom/eye, mob/M)
	var/list/want
	for(var/atom/source in list(eye, M))
		var/atom/top = interest_top(source)
		if(!top || top == M)
			continue
		var/handle = ref_token(top)
		if(handle)
			LAZYADD(want, handle)
	var/token = ref_token(C)
	for(var/handle in C.interest_anchor_handles)
		if(want && (handle in want))
			continue
		var/list/who = GLOB.interest_anchors[handle]
		who -= token
		if(!length(who))
			GLOB.interest_anchors -= handle
	for(var/handle in want)
		if(C.interest_anchor_handles && (handle in C.interest_anchor_handles))
			continue
		var/list/who = GLOB.interest_anchors[handle]
		if(!who)
			who = list()
			GLOB.interest_anchors[handle] = who
		who |= token
	C.interest_anchor_handles = want

/// A registered anchor moved (atom/movable Moved()): the clients it carries update their hold.
/proc/interest_anchor_moved(atom/movable/M)
	var/handle = entity_handle_of(M)
	var/list/who = handle ? GLOB.interest_anchors[handle] : null
	if(!who)
		return
	for(var/token in who.Copy())
		var/client/C = resolve_token(token)
		if(C)
			interest_eye_update(C)

/// Open space appeared or went at `T` (z_transparency): every client whose hold reaches it recomputes what it looks down through.
/proc/interest_open_changed(turf/T)
	if(!length(GLOB.interest_holds))
		return
	for(var/client/C as anything in GLOB.clients)
		if(C && GLOB.interest_sigs[ref_token(C)])
			var/turf/at = get_turf(C.eye || C.mob)
			var/reach = interest_view_half(C.view) + 2 + INTEREST_CHUNK
			if(at && at.z >= T.z && abs(at.x - T.x) <= reach && abs(at.y - T.y) <= reach)
				GLOB.interest_sigs -= ref_token(C)
				interest_eye_update(C)

// ---- vis_contents observers ----

/// `holder` (anything but a turf) shows turfs through its vis_contents: those chunks are seen while it does. Called by the vis_* verbs after a write.
/proc/interest_vis_sync(atom/holder)
	if(!holder || isturf(holder))
		return
	var/list/shown
	if(ismovable(holder))
		var/atom/movable/M = holder
		shown = M.vis_contents
	var/list/keys
	for(var/atom/A as anything in shown)
		if(isturf(A))
			if(!keys)
				keys = list()
			interest_rect_keys(keys, A.z, A.x, A.y, A.x, A.y)
	var/handle = entity_handle_of(holder)
	if(!keys && !(handle && GLOB.interest_holds[handle]))
		return
	handle ||= ref_token(holder)
	if(handle)
		interest_hold_set(handle, keys, keys)

/// `holder` is being deleted: what it showed is no longer observed.
/proc/interest_holder_gone(atom/movable/holder)
	var/handle = entity_handle_of(holder)
	if(handle && GLOB.interest_holds[handle])
		interest_hold_set(handle, null)

/// The interest census, for the periodic look log: held chunks, anchors, and the deferral counters.
/proc/interest_stats_text()
	return "interest: [length(GLOB.interest_holds)] observers, scanned [GLOB.interest_chunks_entered] chunks, left [GLOB.interest_chunks_left], drawn at once [GLOB.interest_drawn_now]; marks deferred [GLOB.refresh_deferred], absorbed while deferred [GLOB.refresh_deferred_absorbed]"
