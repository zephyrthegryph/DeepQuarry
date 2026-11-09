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
// that becomes visible to an observer is never shown with a draw still owed (the user's rule: no player sees an object drawn late). Everything here
// is driven by these chunk events alone, never by a scan of viewers, atoms or rings:
//   - entering the ring (one chunk past the view's edge, on every side): what the chunk owes joins the prefetch queue, nearest the observer's eye
//     first, and is drawn ahead of the presentation backlog as ticks have room, so a walker's next chunk is drawn before it comes into view;
//   - becoming visible on a view jump (a login, an arrival, a teleport: most of what the client sees is new at once): the client's screen is covered
//     (a black fullscreen), its owed draws are drawn nearest the eye first over as many ticks as they take, and the cover lifts when none is left;
//   - becoming visible otherwise (a walker's edge the prefetch has not finished, or a holder that is no client, such as a camera screen): what it
//     still owes is drawn at once, in that tick.
// The drain that works the queues is a keyed timer that exists only while a queue holds something (interest_arrival_drain()).

/// Edge of a chunk in turfs.
#define INTEREST_CHUNK 16
/// How many levels of stacked open space a client's view is followed down.
#define INTEREST_THROUGH_DEPTH 8
#define INTEREST_CHUNK_OF(v) (round(((v) - 1) / INTEREST_CHUNK))
#define INTEREST_KEY(z, cx, cy) ((z) * 1048576 + (cx) * 1024 + (cy))

/// z -> list(cx + 1 -> list(cy + 1 -> how many observers hold that chunk)). Built on demand; a missing cell is a chunk nobody holds.
GLOBAL_LIST_EMPTY(interest_grid)
/// Observer key (a client's handle_of(), a holder's handle_of()) -> the list of chunk keys it holds.
GLOBAL_ALIST_EMPTY(interest_holds)
/// Observer key -> the chunk keys it sees now (the window, the levels below open space, the turfs a holder shows): the ring is held beyond these.
GLOBAL_ALIST_EMPTY(interest_visible)
/// Observer key -> the chunk rectangle of its view window, as text (interest_view_set()). Equal text, nothing to do.
GLOBAL_ALIST_EMPTY(interest_sigs)
/// Anchor handle (the atom a client's eye or mob is carried by, standing on a turf) -> the list of client tokens it carries. Its Moved() updates them.
GLOBAL_ALIST_EMPTY(interest_anchors)
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
/// from unheld to held is walked: the draws it owes are queued. A chunk that becomes visible to the owner (new, or the ring it held already) has what
/// it owes drawn nearest `eye` first, as the tick allows (interest_arrive()). A chunk going to unheld is counted, nothing else (what it drew stays drawn).
/proc/interest_hold_set(owner, list/keys, list/visible, turf/eye = null)
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
	if(!length(keys))
		interest_uncover(owner) // the observer went: nothing of its own waits behind a cover
	var/list/arriving
	var/list/ringed
	for(var/key in entered)
		if((key in visible) && !(was_visible && (key in was_visible)))
			LAZYADD(arriving, key)
		else
			LAZYADD(ringed, key)
	for(var/key in visible)
		if((was_visible && (key in was_visible)) || (entered && (key in entered)))
			continue
		LAZYADD(arriving, key)
	if(length(ringed))
		interest_prefetch(ringed, visible, eye)
	if(length(arriving))
		// A view jump (a login, an arrival, a teleport) leaves nothing of the old view in the new one. A walker's window always overlaps the one it held a step ago.
		var/relocated = TRUE
		for(var/key in visible)
			if(was_visible && (key in was_visible))
				relocated = FALSE
				break
		interest_arrive(owner, arriving, visible, eye, relocated)

// ---- perceivability: nothing is drawn that no viewer could perceive ----
//
// A draw owed by an atom nobody could perceive waits, whoever looks at its chunk: covered (a cover on its turf hides its layer band: an intact floor
// over what lies under its tiles), contained (inside something, unless a look composes it: a worn or held item), or past every viewer's sight
// (invisibility at INVISIBILITY_ABSTRACT or above). Nothing here names a type: pipes, cables and disposals are covered by their layer band. The
// reveal is an event: a turf whose cover changed (interest_turf_revealed()), a move out of a container (interest_parked_moved()), an invisibility
// that dropped (its tracked write marks it).

/// First draws the perceivability rule held back (boot drains, arrivals, prefetch).
GLOBAL_VAR_INIT(interest_unperceivable_skipped, 0)

/// Could some viewer perceive `A` if it looked at A's chunk?
/proc/draw_perceivable(atom/A)
	if(A.invisibility >= INVISIBILITY_ABSTRACT)
		return FALSE
	if(!ismovable(A))
		return TRUE
	var/atom/movable/M = A
	if(!isturf(M.loc))
		return !!M.rx?.worn_watched // contained: perceived only through a look that composes it (worn or held)
	var/turf/T = M.loc
	return !T.cover_hides(M)

/// Does a cover on this turf hide `A` (A's layer band lies under it)? The engine's turf hides nothing; a floor hides what lies under its tiles.
/turf/proc/cover_hides(atom/movable/A)
	return FALSE

/// `T`'s cover changed (a floor tile went or came): what on it still owes a draw and can now be perceived is marked, so it is drawn as anything else is.
/proc/interest_turf_revealed(turf/T)
	FOR_CONTENTS(var/atom/movable/A as anything, T)
		if(A.refresh_queued && draw_perceivable(A))
			refresh_mark(A, DEP_ALL)

// ---- arrival: what a newly visible area owes, drawn before it is seen ----

/// Owed draws one drain pass always runs while ticks are tight: a covered arrival and the prefetch keep moving on a busy server.
#define INTEREST_ARRIVAL_MIN_STEP 32
/// Observer key -> handles (handle_of()) of the atoms it owes behind its cover, nearest its eye first. Present only while that observer is covered.
GLOBAL_ALIST_EMPTY(interest_covered)
/// Handles of atoms owed in ring chunks (a chunk away from someone's view), nearest the observer first, drawn ahead of the presentation backlog.
GLOBAL_LIST_EMPTY(interest_prefetched)
/// Owed draws run behind a cover, by the prefetch, and at once (a visible chunk the prefetch had not finished); covers raised.
GLOBAL_VAR_INIT(interest_cover_drawn, 0)
GLOBAL_VAR_INIT(interest_prefetch_drawn, 0)
GLOBAL_VAR_INIT(interest_at_once_drawn, 0)
GLOBAL_VAR_INIT(interest_covers_raised, 0)
/// The most owed draws one drain pass runs (0: the tick's budget decides). Tests set it to see the spread a busy tick makes.
GLOBAL_VAR_INIT(interest_arrival_step_max, 0)
/// Observer keys that tests treat as coverable without a client (a client is what a cover is shown on).
GLOBAL_LIST_EMPTY(interest_test_coverable)

/// Where the observer looks from, in chunk coordinates (fractional), for nearest-first ordering: `eye`, or the middle of what it sees.
/proc/interest_view_middle(list/visible, turf/eye)
	if(eye)
		return list((eye.x - INTEREST_CHUNK / 2) / INTEREST_CHUNK, (eye.y - INTEREST_CHUNK / 2) / INTEREST_CHUNK)
	var/sum_x = 0
	var/sum_y = 0
	for(var/key in visible)
		sum_x += round((key % 1048576) / 1024)
		sum_y += key % 1024
	return list(sum_x / max(1, length(visible)), sum_y / max(1, length(visible)))

/// The handles of what chunks `keys` owe, nearest (mid_cx, mid_cy) first: chunk by chunk, and turf by turf inside each chunk.
/proc/interest_owed_ordered(list/keys, list/middle)
	. = list()
	var/list/by_distance = list()
	for(var/key in keys)
		var/cx = round((key % 1048576) / 1024)
		var/cy = key % 1024
		by_distance["[key]"] = (cx - middle[1]) ** 2 + (cy - middle[2]) ** 2
	by_distance = sortTim(by_distance, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
	for(var/key_text in by_distance)
		var/key = text2num(key_text)
		interest_collect_owed(., round(key / 1048576), round((key % 1048576) / 1024), key % 1024, middle[1], middle[2])

/// Chunks `keys` entered an observer's ring: what they owe is drawn ahead of the backlog, nearest the observer first, before they come into view.
/proc/interest_prefetch(list/keys, list/visible, turf/eye)
	var/list/owed = interest_owed_ordered(keys, interest_view_middle(visible, eye))
	if(!length(owed))
		return
	// Each joins the presentation queue as it always did (the lane draws it if nothing else does first), and the prefetch draws them nearest first,
	// ahead of whatever backlog that queue holds.
	var/queued = 0
	for(var/handle in owed)
		var/atom/A = handle_get(handle)
		if(isatom(A))
			queued += interest_wake(A)
	if(queued)
		log_world("INTEREST: [length(keys)] chunk(s) in the ring, [queued] parked draw(s) queued, [length(owed)] prefetched nearest first")
	GLOB.interest_prefetched += owed
	interest_drain_soon()

/// Chunks `keys` became visible to `owner` (seeing `visible` from `eye`). Nothing they owe may be seen undrawn: on a view jump the owner's screen is
/// covered while its draws run over the ticks they take; otherwise (a walker's edge the prefetch has not finished, or no client to cover) they run now.
/proc/interest_arrive(owner, list/keys, list/visible, turf/eye, relocated = TRUE)
	var/list/owed = interest_owed_ordered(keys, interest_view_middle(visible, eye))
	if(!length(owed))
		return
	var/list/covered = GLOB.interest_covered[owner]
	var/jump = relocated // never the share of the view that is new: a walker crossing a chunk edge gets half of a two-chunk window new, and was blacked out for a frame by it
	if(!covered && jump && length(owed) > INTEREST_ARRIVAL_MIN_STEP && interest_cover(owner))
		covered = list()
		GLOB.interest_covered[owner] = covered
	if(covered)
		covered += owed
		log_world("INTEREST: [length(keys)] chunk(s) visible behind [owner]'s cover, [length(owed)] owed draw(s) queued nearest first")
		// The cover hides the rest: the tick the view jumps in draws only the nearest few, the following ticks draw the rest as they have room.
		interest_arrival_drain(INTEREST_ARRIVAL_MIN_STEP)
		return
	var/drawn = 0
	var/started = REALTIMEOFDAY
	for(var/handle in owed)
		var/atom/A = handle_get(handle)
		if(isatom(A) && !QDELETED(A))
			drawn += interest_draw_now(A)
	GLOB.interest_at_once_drawn += drawn
	if(drawn)
		log_world("INTEREST: [length(keys)] chunk(s) visible, [drawn] owed draw(s) run now in [round((REALTIMEOFDAY - started) * 100)] ms[relocated ? "" : " (a walker's edge, no cover)"]")

/// Covers `owner`'s screen (a client's mob gets a black fullscreen) while its view is drawn. FALSE when there is no client to cover.
/proc/interest_cover(owner)
	if(owner in GLOB.interest_test_coverable)
		GLOB.interest_covers_raised++
		return TRUE
	var/client/C = handle_get(owner)
	if(!istype(C) || !C.mob || !C.mob.view_cover_set(TRUE))
		log_world("INTEREST: no cover raised for [owner] (client [istype(C) ? "present" : "gone"], mob [istype(C) ? C.mob : "none"])")
		return FALSE
	log_world("INTEREST: cover raised for [owner] on [C.mob]")
	GLOB.interest_covers_raised++
	return TRUE

/// Lifts `owner`'s cover, if it has one, and forgets what was owed behind it (an observer that left owes nothing of its own).
/proc/interest_uncover(owner)
	if(isnull(GLOB.interest_covered[owner]))
		return
	GLOB.interest_covered -= owner
	var/client/C = handle_get(owner)
	if(istype(C) && C.mob)
		C.mob.view_cover_set(FALSE)
		log_world("INTEREST: cover lifted for [owner] on [C.mob]")
	else
		log_world("INTEREST: cover dropped for [owner]: no client or mob to lift it from")

/// Covers (`covered`) or uncovers this mob's view of the map while what it is about to see is drawn. TRUE when it could. The engine's default has no
/// cover to show; the HUD implements it (code/content/hud/fullscreen.dm).
/mob/proc/view_cover_set(covered)
	return FALSE

/// Arms the drain for the next tick while any queue holds something.
/proc/interest_drain_soon()
	if(!after_pending(null, "interest_arrival_drain"))
		after(null, world.tick_lag, GLOBAL_PROC_REF(interest_arrival_drain), key = "interest_arrival_drain")

/// Appends to `into` the handles of what chunk (z, cx, cy) owes, nearest the chunk point (mid_cx, mid_cy) first. Returns how many.
/proc/interest_collect_owed(list/into, z, cx, cy, mid_cx, mid_cy)
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
	// The point to order by, in turfs: a chunk is 16 turfs, so the order inside one matters.
	var/mid_x = mid_cx * INTEREST_CHUNK + INTEREST_CHUNK / 2
	var/mid_y = mid_cy * INTEREST_CHUNK + INTEREST_CHUNK / 2
	var/list/owed = list()
	for(var/turf/T as anything in block(low, high))
		var/owes = !!T.refresh_queued
		if(!owes)
			FOR_CONTENTS(var/atom/movable/A as anything, T)
				if(A.refresh_queued)
					owes = TRUE
					break
		if(owes)
			owed[T] = (T.x - mid_x) ** 2 + (T.y - mid_y) ** 2
	if(!length(owed))
		return
	owed = sortTim(owed, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
	for(var/turf/T as anything in owed)
		if(T.refresh_queued)
			into += handle_of(T)
			.++
		FOR_CONTENTS(var/atom/movable/A as anything, T)
			if(A.refresh_queued)
				into += handle_of(A)
				.++

/// One pass over the queues: every covered observer's owed draws first (its screen is black until they are done), then the prefetch, as the tick allows.
/// A covered observer whose queue empties is uncovered. The pass re-arms itself for the next tick only while something is left. Returns how many it drew.
/// `cap`: the most it draws this pass (0: the tick's budget decides).
/proc/interest_arrival_drain(cap = 0)
	. = 0
	var/budget_hit = FALSE
	for(var/owner in GLOB.interest_covered)
		var/list/Q = GLOB.interest_covered[owner]
		var/i = 0
		while(i < length(Q))
			i++
			var/atom/A = handle_get(Q[i])
			if(isatom(A) && !QDELETED(A))
				var/drawn = interest_draw_now(A)
				. += drawn
				GLOB.interest_cover_drawn += drawn
			if(interest_arrival_pass_full(., cap))
				budget_hit = TRUE
				break
		Q.Cut(1, i + 1)
		if(!length(Q))
			interest_uncover(owner)
		if(budget_hit)
			break
	if(!budget_hit)
		var/list/P = GLOB.interest_prefetched
		var/j = 0
		while(j < length(P))
			j++
			var/atom/A = handle_get(P[j])
			if(isatom(A) && !QDELETED(A))
				var/drawn = interest_draw_now(A)
				. += drawn
				GLOB.interest_prefetch_drawn += drawn
			if(interest_arrival_pass_full(., cap))
				break
		P.Cut(1, j + 1)
	if(length(GLOB.interest_covered) || length(GLOB.interest_prefetched))
		interest_drain_soon()

/// Has a drain pass that ran `drawn` draws used its share of the tick?
/proc/interest_arrival_pass_full(drawn, cap = 0)
	if(cap && drawn >= cap)
		return TRUE
	if(GLOB.interest_arrival_step_max)
		return drawn >= GLOB.interest_arrival_step_max
	return drawn >= INTEREST_ARRIVAL_MIN_STEP && KERNEL_OVER_BUDGET

/// The atoms in `owner`'s visible chunks that still owe a draw while it can see them (not covered): must always be empty (the rule the tests hold).
/proc/interest_view_owing(owner)
	. = list()
	if(!isnull(GLOB.interest_covered[owner]))
		return
	for(var/key in GLOB.interest_visible[owner])
		var/z = round(key / 1048576)
		var/cx = round((key % 1048576) / 1024)
		var/cy = key % 1024
		var/x0 = cx * INTEREST_CHUNK + 1
		var/y0 = cy * INTEREST_CHUNK + 1
		if(z < 1 || z > world.maxz || x0 > world.maxx || y0 > world.maxy)
			continue
		for(var/turf/T as anything in block(locate(x0, y0, z), locate(min(world.maxx, x0 + INTEREST_CHUNK - 1), min(world.maxy, y0 + INTEREST_CHUNK - 1), z)))
			if((T.refresh_queued & DEP_PARKED) && draw_perceivable(T))
				. += T
			FOR_CONTENTS(var/atom/movable/A as anything, T)
				if((A.refresh_queued & DEP_PARKED) && draw_perceivable(A))
					. += A

/// A parked `A` owes a draw and something can see its chunk coming: it joins the presentation queue with everything it owed. Returns 1 when it did.
/proc/interest_wake(atom/A)
	if(!(A.refresh_queued & DEP_PARKED) || QDELETED(A) || !interest_ready(A))
		return 0
	if(!draw_perceivable(A))
		GLOB.interest_unperceivable_skipped++
		return 0
	A.refresh_queued = DEP_ALL
	A.refresh_bits = 0
	refresh_queue_push(A)
	GLOB.refresh_near_drawn++
	GLOB.refresh_parked_near++
	return 1

/// An atom that owes a draw (parked, or queued behind the lane) and can be seen now: it draws on the spot, with everything it owed. The queue entry it
/// leaves is a stale duplicate the drain skips. Returns 1 when it ran. `force` draws it though nobody could perceive it (a T-ray scan showing it).
/proc/interest_draw_now(atom/A, force = FALSE)
	var/pending = A.refresh_queued
	if(!pending || QDELETED(A) || !interest_ready(A))
		return 0
	if(!force && !draw_perceivable(A))
		GLOB.interest_unperceivable_skipped++
		return 0 // it keeps owing its draw: the reveal (interest_turf_revealed(), a move out of its container, its invisibility dropping) marks it
	var/parked = pending & DEP_PARKED
	if(parked)
		pending = DEP_ALL // parked is alone in refresh_queued: it owes its whole refresh
		GLOB.refresh_parked_near++
	var/fresh = pending & DEP_CREATED
	pending &= ~(DEP_CREATED | DEP_PARKED)
	var/bits = A.refresh_bits
	A.refresh_queued = 0
	A.refresh_bits = 0
	refresh_queue_drop(A) // its queue entry goes with the draw: a deleted atom must not stay pinned by a stale one
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

//// An atom's init frame past Initialize() is one bit of its own datum_flags (DF_INIT_OPEN): its setup() hooks running (setup_run()), or a map-loaded
/// atom's after_init() entries waiting for the load frame to close and then running (after_init_flush()). On the atom itself, so it holds nothing and
/// needs no slot: one deleted inside its own frame takes the bit with it (interest_forget() clears it as well). The engine never opens a second frame
/// inside the first; one that does (a test, a hook that re-enters) is counted here by slot until the outer frame ends. A real global: atoms
/// initialize while the globals are still being made.
GLOBAL_REAL(init_open, /alist)

/// `A` enters an init frame that runs its own code after Initialize() returned: it is not drawn from here until the frame ends.
/proc/init_open_begin(atom/A)
	if(!(A.datum_flags & DF_INIT_OPEN))
		A.datum_flags |= DF_INIT_OPEN
		return
	var/slot = slot_of(A)
	if(!slot)
		return
	if(!init_open)
		init_open = alist()
	init_open[slot] = (init_open[slot] || 0) + 1

/// The frame ends. The last one out lets a draw it was owed (parked while its init ran, in a chunk someone sees now) happen. An atom deleted inside its
/// frame has lost the bit already.
/proc/init_open_end(atom/A)
	if(!(A.datum_flags & DF_INIT_OPEN))
		return
	var/slot = A.handle_slot
	var/nested = slot && init_open?[slot]
	if(nested)
		if(nested > 1)
			init_open[slot] = nested - 1
		else
			init_open -= slot
		return
	A.datum_flags &= ~DF_INIT_OPEN
	if(!QDELETED(A))
		interest_settle(A)

/// engine_forget(): a datum is being destroyed, its slot still valid. Its open init frame (an atom deleted inside its own setup) is dropped, so it is not
/// taken for one still setting up, and neither is the slot's next holder. Idempotent: a second call finds nothing.
/proc/interest_forget(datum/D)
	D.datum_flags &= ~DF_INIT_OPEN
	if(init_open && D.handle_slot)
		init_open -= D.handle_slot

/// Whether `A` can be drawn from here: it has finished Initialize() and no init frame of its own is open. This is per atom: a map load running elsewhere
/// (an expedition z-level takes seconds) holds back only the atoms it is still setting up, never the parked ones a player walks up to.
/proc/interest_ready(atom/A)
	return (A.flags & ATOM_INITIALIZED) && A != GLOB.atom_initializing && !(length(GLOB.atoms_init_outer) && (A in GLOB.atoms_init_outer)) && !(A.datum_flags & (DF_INIT_OPEN | DF_CONSTRUCTING))

// A parked atom moved (atom/movable Moved()): into a chunk someone holds it is queued, into one someone sees it draws.
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
	interest_view_set(handle_of(C), at_eye, at_mob, interest_view_half(C.view))
	C.interest_eye_moved(at_eye)

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
	interest_hold_set(token, keys, visible, at_eye || at_mob)
	return TRUE

/// Virtual: the client's eye was placed (it may not have moved): content that follows the eye hooks here (client_glow_holder.dm).
/client/proc/interest_eye_moved(turf/at_eye)
	return

/// Virtual: the client stopped observing (it left).
/client/proc/interest_eye_left()
	return

/// The client left: it holds nothing.
/proc/interest_eye_remove(client/C)
	if(!C)
		return
	interest_anchor_sync(C, null, null)
	C.interest_eye_left()
	var/token = handle_of(C)
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
		var/handle = handle_of(top)
		if(handle)
			LAZYADD(want, handle)
	var/token = handle_of(C)
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
		var/client/C = handle_get(token)
		if(C)
			interest_eye_update(C)

/// Open space appeared or went at `T` (z_transparency): every client whose hold reaches it recomputes what it looks down through.
/proc/interest_open_changed(turf/T)
	if(!length(GLOB.interest_holds))
		return
	for(var/client/C as anything in GLOB.clients)
		if(C && GLOB.interest_sigs[handle_of(C)])
			var/turf/at = get_turf(C.eye || C.mob)
			var/reach = interest_view_half(C.view) + 2 + INTEREST_CHUNK
			if(at && at.z >= T.z && abs(at.x - T.x) <= reach && abs(at.y - T.y) <= reach)
				GLOB.interest_sigs -= handle_of(C)
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
	handle ||= handle_of(holder)
	if(handle)
		interest_hold_set(handle, keys, keys)

/// `holder` is being deleted: what it showed is no longer observed.
/proc/interest_holder_gone(atom/movable/holder)
	var/handle = entity_handle_of(holder)
	if(handle && GLOB.interest_holds[handle])
		interest_hold_set(handle, null)

/// The interest census, for the periodic look log: held chunks, anchors, and the deferral counters.
/proc/interest_stats_text()
	return "interest: [length(GLOB.interest_holds)] observers, scanned [GLOB.interest_chunks_entered] chunks, left [GLOB.interest_chunks_left], drawn at once [GLOB.interest_drawn_now]; marks deferred [GLOB.refresh_deferred], absorbed while deferred [GLOB.refresh_deferred_absorbed]; queue forget scans [GLOB.refresh_forget_scans] ([GLOB.refresh_forget_scan_steps] steps, longest [GLOB.refresh_forget_scan_max])"

// ---- the sampled audit (debug and test builds only: DQ_LOOK_AUDIT; production compiles none of it) ----

#ifdef DQ_LOOK_AUDIT
/// Parked draws found inside a chunk an observer sees (the audit repairs them), and the atoms the audit looked at.
GLOBAL_VAR_INIT(interest_audit_parked_in_view, 0)
GLOBAL_VAR_INIT(interest_audit_looked, 0)

/// Up to `count` random turfs of chunks observers see: a random observer, a random chunk of its visible set, a random turf of the chunk. Nothing is kept between calls.
/proc/interest_sample_turfs(count)
	. = list()
	var/list/owner_keys = list()
	for(var/watcher in GLOB.interest_visible)
		owner_keys += watcher
	var/owners = length(owner_keys)
	if(!owners)
		return
	for(var/n in 1 to count)
		var/owner = owner_keys[rand(1, owners)]
		var/list/seen = GLOB.interest_visible[owner]
		if(!length(seen))
			continue
		var/key = seen[rand(1, length(seen))]
		var/z = round(key / 1048576)
		if(z < 1 || z > world.maxz)
			continue
		var/x = clamp(round((key % 1048576) / 1024) * INTEREST_CHUNK + rand(1, INTEREST_CHUNK), 1, world.maxx)
		var/y = clamp((key % 1024) * INTEREST_CHUNK + rand(1, INTEREST_CHUNK), 1, world.maxy)
		. += locate(x, y, z)

/// One sampled turf: a draw still owed by an atom on it that an observer sees is a bug (a viewer would see it undrawn): reported, counted and repaired. An
/// atom that was drawn is checked for drift as the old sweep did (refresh_check_drift()).
/proc/interest_audit_turf(turf/T)
	if(!interest_sees(T))
		return
	interest_audit_atom(T)
	FOR_CONTENTS(var/atom/movable/A as anything, T)
		interest_audit_atom(A)

/proc/interest_audit_atom(atom/A)
	if(QDELETED(A))
		return
	GLOB.interest_audit_looked++
	if(A.refresh_queued & DEP_PARKED)
		if(!interest_ready(A))
			return
		if(A.refresh_queued == DEP_PARKED && GLOB.type_look_stamp[A.type] && !A.periodic_cadence && !A.periodic_interval)
			return // held at boot by type (boot_created_hold()): an atom of an empty default look owes nothing, it was released with its type
		GLOB.interest_audit_parked_in_view++
		var/msg = "REFRESH PARKED IN VIEW: [A.type] at [A.x],[A.y],[A.z] still owes its draw in a chunk an observer sees"
		GLOB.refresh_drift += msg
		log_world(msg)
		interest_draw_now(A)
		return
	if(A.rx?.refresh_swept && !A.refresh_queued)
		refresh_check_drift(A)
#endif
