// ---- the draw queue: draw on change (doc/rewrite/draw_on_change.md) ----
//
// A look change marks the atom dirty (refresh_mark()) and files it here, in the bucket of the 16 x 16 turf chunk it stands in. Nothing waits for a
// viewer: every dirty atom is drawn, nearest a client's eye first and, when the lane has room, everything else after. A drain runs once per tick and
// does nothing while no bucket holds an atom.
//
//   - The order is a ring order around the eyes (draw_order()): the buckets of the chunks that hold a client's eye, then the ring of chunks round
//     them, and so on outward; the atoms that stand nowhere (nullspace) and every bucket on a level without a client come last. A client walking
//     changes that order for the work that exists; it adds none, and a walking client with nothing dirty costs the drain one length() read.
//   - The drain works under the presentation lane's budget (time_scheduler.out_of_budget()): the rest stays filed for the next tick. Nothing is
//     dropped and nothing is parked.
//   - An atom with outputs besides its look (values, a push, a window, a mob's verbs) is not filed: it is in the refresh queue, which drains first and
//     runs every output of the atom, its look included. A filed atom that gains such an output is queued there too (refresh_mark()); the bucket entry
//     it leaves is a stale one the drain skips.
//
// An atom is filed once (`draw_filed`, slot -> chunk key). A bucket is a list in the order atoms were filed; deleting a filed atom takes it out of
// its bucket (draw_unfile(), engine_forget()), so no bucket pins one.

/// The bucket key of an atom that stands on no turf (in nullspace, or in something that does not).
#define DRAW_ANYWHERE 0
/// Rings of chunks the order distinguishes; farther ones share the last.
#define DRAW_RINGS 64

/// Chunk key (GAZE_KEY) or DRAW_ANYWHERE -> the atoms filed there, in order.
GLOBAL_ALIST_EMPTY(draw_buckets)
/// An atom's slot -> the key of the bucket it is filed in.
GLOBAL_ALIST_EMPTY(draw_filed)
/// The bucket being drained and its key, so a delete in the middle of the drain finds its atom (draw_unfile()).
GLOBAL_LIST(draw_working)
GLOBAL_VAR_INIT(draw_working_key, -1)

/// Counters, by name: `dirtied` (look changes: atoms that went from nothing owed to owing a refresh, filed here or queued in the refresh queue), `filed_total`,
/// `drawn` (out of the buckets) and `drawn_near` (the share that stood within a chunk of an eye), `stale` (entries the drain skipped: the refresh queue
/// drew the atom since it was filed), `drain_calls` (passes that found work) and `drain_cut` (passes the budget cut). The ms of the passes follow.
GLOBAL_LIST_INIT(draw_n, list("dirtied" = 0, "filed_total" = 0, "drawn" = 0, "drawn_near" = 0, "stale" = 0, "drain_calls" = 0, "drain_cut" = 0)) // a list: the test state guard reads a scalar counter that went 0 to 1 as a leaked flag
GLOBAL_VAR_INIT(draw_drain_ms, 0)
GLOBAL_VAR_INIT(draw_drain_ms_max, 0)

/// Atoms filed and waiting.
/proc/draw_depth()
	return length(GLOB.draw_filed)

/// Files `A` in the bucket of the chunk it stands in. Filed already: nothing (the entry waiting will draw what it is owed now).
/proc/draw_file(atom/A)
	if(A.destroy_phase >= LIFECYCLE_PHASE_SLOTS_RELEASED)
		return
	var/slot = slot_of(A)
	if(!slot)
		refresh_queue_push(A) // nothing to file it by: the refresh queue draws it
		return
	if(!isnull(GLOB.draw_filed[slot]))
		return
	var/turf/T = isturf(A) ? A : get_turf(A)
	var/key = T ? GAZE_KEY(T.z, GAZE_CHUNK_OF(T.x), GAZE_CHUNK_OF(T.y)) : DRAW_ANYWHERE
	var/list/bucket = GLOB.draw_buckets[key]
	if(!bucket)
		bucket = list()
		GLOB.draw_buckets[key] = bucket
	bucket += A
	GLOB.draw_filed[slot] = key
	GLOB.draw_n["filed_total"]++

/// engine_forget(): a dying atom leaves its bucket.
/proc/draw_unfile(datum/D)
	var/slot = slot_known(D)
	if(!slot)
		return
	var/key = GLOB.draw_filed[slot]
	if(isnull(key))
		return
	GLOB.draw_filed -= slot
	var/list/bucket = GLOB.draw_buckets[key]
	if(bucket)
		bucket -= D
		if(!length(bucket))
			GLOB.draw_buckets -= key
	if(GLOB.draw_working_key == key && GLOB.draw_working)
		var/at = GLOB.draw_working.Find(D)
		if(at)
			GLOB.draw_working[at] = null // the drain skips a null

/// The keys of the filled buckets in the order they drain: by distance in chunks from the nearest client's eye on the same level (a level apart counts
/// four chunks), the buckets of levels no client is on and of atoms that stand nowhere last.
/proc/draw_order()
	var/list/eyes
	for(var/token in GLOB.gaze_at)
		var/turf/T = GLOB.gaze_at[token]
		if(T)
			LAZYADD(eyes, list(list(T.z, GAZE_CHUNK_OF(T.x), GAZE_CHUNK_OF(T.y))))
	var/list/rings = list()
	rings.len = DRAW_RINGS
	var/list/nowhere
	for(var/key in GLOB.draw_buckets)
		if(key == DRAW_ANYWHERE)
			nowhere = list(key)
			continue
		var/z = round(key / 1048576)
		var/cx = round((key % 1048576) / 1024)
		var/cy = key % 1024
		var/ring = DRAW_RINGS
		for(var/list/eye as anything in eyes)
			var/dist = max(abs(cx - eye[2]), abs(cy - eye[3])) + 4 * abs(z - eye[1]) + 1
			if(dist < ring)
				ring = dist
		var/list/in_ring = rings[ring]
		if(!in_ring)
			in_ring = list()
			rings[ring] = in_ring
		in_ring += key
	. = list()
	for(var/list/in_ring as anything in rings)
		if(in_ring)
			. += in_ring
	if(nowhere)
		. += nowhere

/// How many chunks from the nearest eye a bucket key is (the share of draws made near a client counts those within one).
/proc/draw_key_near(key)
	if(key == DRAW_ANYWHERE)
		return FALSE
	var/z = round(key / 1048576)
	var/cx = round((key % 1048576) / 1024)
	var/cy = key % 1024
	for(var/token in GLOB.gaze_at)
		var/turf/T = GLOB.gaze_at[token]
		if(T && T.z == z && abs(GAZE_CHUNK_OF(T.x) - cx) <= 1 && abs(GAZE_CHUNK_OF(T.y) - cy) <= 1)
			return TRUE
	return FALSE

/// Draws the filed atoms within the lane's budget, nearest an eye first. TRUE when nothing is filed any more (and, as the refresh queue's drain does,
/// FALSE when the budget cut the pass). `sched` null: no budget (tests, the boot drain): one pass over what was filed when it began.
/proc/draw_drain(datum/time_scheduler/sched)
	if(!length(GLOB.draw_buckets))
		return TRUE
	var/started = TICK_USAGE_REAL
	var/datum/km_attr/attr = (sched?.meter || km_meter()).attr
	var/pass = ++GLOB.refresh_drain_pass
	var/list/order = draw_order()
	var/cut = FALSE
	for(var/key in order)
		var/list/work = GLOB.draw_buckets[key]
		if(!work)
			continue
		GLOB.draw_buckets -= key
		GLOB.draw_working = work
		GLOB.draw_working_key = key
		var/near = draw_key_near(key)
		var/i = 0
		while(i < length(work))
			i++
			var/atom/A = work[i]
			if(isnull(A))
				continue
			var/slot = slot_known(A)
			if(slot)
				GLOB.draw_filed -= slot
			if(!A.refresh_queued)
				GLOB.draw_n["stale"]++ // the refresh queue drew it since it was filed
			else if(A.refresh_pass == pass)
				// A draw this pass marked it again: it waits for the next.
				GLOB.draw_buckets[key] = (GLOB.draw_buckets[key] || list()) + A
				if(slot)
					GLOB.draw_filed[slot] = key
				continue
			else
				refresh_run(A, pass, sched, attr)
				GLOB.draw_n["drawn"]++
				if(near)
					GLOB.draw_n["drawn_near"]++
			if(sched?.out_of_budget())
				var/list/rest = work.Copy(i + 1)
				if(length(rest))
					// What is left goes back ahead of what was filed meanwhile (its filings are still recorded).
					var/list/later = GLOB.draw_buckets[key]
					GLOB.draw_buckets[key] = later ? rest + later : rest
				cut = TRUE
				break
		GLOB.draw_working = null
		GLOB.draw_working_key = -1
		if(cut)
			break
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	GLOB.draw_n["drain_calls"]++
	GLOB.draw_drain_ms += ms
	GLOB.draw_drain_ms_max = max(GLOB.draw_drain_ms_max, ms)
	if(cut)
		GLOB.draw_n["drain_cut"]++
	return !length(GLOB.draw_buckets)

/// Every filed draw now, ignoring the budget (tests, admin tools, the boot drain). Marks a draw makes are drawn too, a bounded number of passes.
/proc/draw_flush()
	var/passes = 0
	while(length(GLOB.draw_buckets))
		draw_drain(null)
		if(++passes > 20)
			stack_trace("draw_flush: still filed after 20 passes (a draw re-marks atoms for ever?): [length(GLOB.draw_filed)] filed")
			break

/// The draw queue's counters, for the look log line: what is filed, what was drawn and how near, and what the drain cost.
/proc/draw_stats_text()
	return "draw queue: [draw_depth()] filed in [length(GLOB.draw_buckets)] buckets, [length(GLOB.refresh_queue)] in the refresh queue; dirtied [GLOB.draw_n["dirtied"]], filed [GLOB.draw_n["filed_total"]], drawn [GLOB.draw_n["drawn"]] ([GLOB.draw_n["drawn_near"]] within a chunk of an eye), stale entries skipped [GLOB.draw_n["stale"]]; drain [GLOB.draw_n["drain_calls"]] passes took [round(GLOB.draw_drain_ms, 0.1)] ms, longest [round(GLOB.draw_drain_ms_max, 0.1)] ms, cut by the budget [GLOB.draw_n["drain_cut"]]; default looks skipped [GLOB.type_look_stamp_skipped]; eye chunks entered [GLOB.gaze_chunks_entered], left [GLOB.gaze_chunks_left]"

// ---- rates ----

/// REALTIMEOFDAY of the last rates line, and the counters then.
GLOBAL_VAR_INIT(draw_rates_at, 0)
GLOBAL_VAR_INIT(draw_rates_dirtied, 0)
GLOBAL_VAR_INIT(draw_rates_draws, 0)
GLOBAL_VAR_INIT(draw_rates_drain_ms, 0)

/// Look changes, draws and drain time per second since the last call (the first call: since the world began). One line for the look log.
/proc/draw_rates_text()
	var/seconds = max(1, REALTIMEOFDAY - GLOB.draw_rates_at) / 10
	var/dirtied = GLOB.draw_n["dirtied"] - GLOB.draw_rates_dirtied
	var/draws = GLOB.look_cost_all_draws - GLOB.draw_rates_draws
	var/drain_ms = GLOB.draw_drain_ms - GLOB.draw_rates_drain_ms
	GLOB.draw_rates_at = REALTIMEOFDAY
	GLOB.draw_rates_dirtied = GLOB.draw_n["dirtied"]
	GLOB.draw_rates_draws = GLOB.look_cost_all_draws
	GLOB.draw_rates_drain_ms = GLOB.draw_drain_ms
	return "per second over the last [round(seconds)] s: [round(dirtied / seconds, 0.01)] look changes, [round(draws / seconds, 0.01)] draws, [round(drain_ms / seconds, 0.001)] ms of draw drain"
