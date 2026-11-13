// Client lighting, piece 3: the per-client glow holder. BYOND sends a glow only to clients that see the light's own turf, so a
// light just off screen would not spill onto the screen and its glow would pop in as the player walks. Each client holds a copy
// of every glow in reach as its own images (client.images), recomputed only when the eye crosses a chunk (CLIENT_GLOW_CHUNK turfs a side).
//   - where it stands: on the light's own turf when the eye saw that turf at the crossing, else on the reached turf the eye saw that is
//     nearest the eye, offset to the light's place. Playtesting showed an image drawn far from where it stands is culled, so the offset stays within the light's range.
//   - the reach box: the turfs seen from some eye position in the chunk. Every light whose reach overlaps it is held, and stays held until its reach
//     leaves the keep box (the reach box grown by CLIENT_GLOW_KEEP_CHUNKS chunks), so a walk back and forth over that many chunks changes no image.
//   - a crossing walks only the chunks where a light's status can have changed, and tests each light there against the boxes before touching it. Light events
//     (client_glow_apply() and friends) keep every held copy current against the boxes as they stand, so only the boxes moving can change a status: a light is
//     acquired when its reach meets the new reach box and it is not held (its reach box overlaps the strip the new box gained), dropped when it is held and its reach
//     has left the keep box (it overlapped the strip the keep box lost), and has its shape readied ahead when it newly enters the prefetch ring. The chunk index holds
//     a light in every chunk its reach box overlaps, so the chunks walked are exactly the chunks the strips cover (no growing by a range): a step of one chunk walks
//     the chunks along the box edges, not the area; a held light inside the boxes costs a lookup and a comparison.
//   - stands change only where the eye's sight did: a held glow is looked at again only when the turf it stands on left the seen set, or a turf came into sight
//     within reach of its light. Those turfs are the difference of the old and new seen sets, and the glows near them are found through the chunk index. The seen set
//     is refreshed on every crossing, and between crossings when the eye moves inside its chunk (at most every CLIENT_GLOW_SIGHT_INTERVAL) or opacity changes in its
//     view (once per lighting step, client_glow_reconsider_flush()), so a door closing or a step behind a wall moves the glows standing on turfs now out of sight.
//   - a dropped glow's images go to a small pool (CLIENT_GLOW_POOL_MAX) reset to a blank image, and the next glow acquired takes from it.
//   - a held light is a glow image, baked to its reach shape once that is ready (client_shadow.dm), and an override image that hides
//     the real glow from this client, so it is never drawn twice.
//
//   - a delta crossing makes the glows of the lights newly in reach through a queue, CLIENT_GLOW_ACQUIRE_BUDGET_MS a tick (acquire_run()); drops and shape readying stay in the crossing.
//
//   - a full scan (a login, a teleport, a drop-all) is spread: chunks are walked nearest the eye first, a client's holder for CLIENT_GLOW_SCAN_BUDGET_MS a tick, and the rest on
//     the ticks that follow (scan_continue()). The step that finds the light around the eye runs inside the call that asked, so the view is lit when the login cover lifts. A crossing
//     that arrives while a scan is unfinished starts a full scan over its own boxes (the delta needs a finished scan to start from). Viewers with no client (tests) scan to the end at once.
//
// Events only: the eye crossing a chunk or changing view (interest_eye_update()), a light glowing, moving or changing
// (client_glow_apply()), its mask rebuilding (client_glow_mask_apply()), going out (client_glow_clear()), client lighting
// switching off and the client leaving.

/// Holder bookkeeping (benchmarks, tests): images made, images changed in place, images dropped, eye-chunk recomputes.
GLOBAL_VAR_INIT(client_glow_holder_made, 0)
GLOBAL_VAR_INIT(client_glow_holder_updated, 0)
GLOBAL_VAR_INIT(client_glow_holder_dropped, 0)
GLOBAL_VAR_INIT(client_glow_holder_recomputes, 0)
/// Glows put on a client that took their images from a holder's pool instead of making them.
GLOBAL_VAR_INIT(client_glow_holder_reused, 0)
/// Crossings that walked no chunk at all (nothing near the moved edges), and held glows whose standing turf a crossing moved.
GLOBAL_VAR_INIT(client_glow_holder_scans_skipped, 0)
GLOBAL_VAR_INIT(client_glow_holder_stands_moved, 0)
/// Chunks looked in by crossings and scans (empty ones too: the walk's cost), and sight refreshes between crossings.
GLOBAL_VAR_INIT(client_glow_holder_chunk_visits, 0)
GLOBAL_VAR_INIT(client_glow_holder_sight_refreshes, 0)

/// One viewer's held glows. A client owns one (client.glow_holder); tests and benchmarks make one with no client.
/datum/client_glow_holder
	/// The client shown the images (null: a test or benchmark viewer, its images are only kept here).
	var/client/client
	/// The eye's chunk signature "z:cx:cy:hx:hy"; equal text, nothing to do.
	var/sig
	var/z = 0
	/// The reach box, inclusive turf coordinates: list(x0, y0, x1, y1).
	var/list/reach
	/// The keep box: the reach box grown by CLIENT_GLOW_KEEP_CHUNKS chunks each way. A glow is acquired when its reach overlaps `reach` but kept while it
	/// overlaps this, so crossing a chunk edge and walking back makes and drops nothing: a chunk step moves the reach box by less than the margin.
	var/list/keep_reach
	/// TRUE once a scan has made the held glows match `reach` and `keep_reach`: the next crossing walks only the chunks where that can have changed. False
	/// after every drop-all, a login wipe and before the first hold, so the crossing after them walks the whole region.
	var/scanned = FALSE
	/// A full scan still under way: the chunks left to walk ("gx,gy" texts, nearest the eye first), the position of the next one, and the held keys the walked chunks kept.
	/// Null `scan_chunks` is no scan pending.
	var/list/scan_chunks
	var/scan_at = 0
	var/list/scan_keep
	/// What the pending scan has done so far: chunks with lights walked, lights examined, steps taken, server milliseconds spent over all steps.
	var/scan_walked = 0
	var/scan_lights = 0
	var/scan_steps = 0
	var/scan_ms = 0
	/// TRUE while a scan_continue() timer is waiting.
	var/scan_waiting = FALSE
	/// Server milliseconds one step of a full scan may spend before it hands the rest to the next tick; null: the scan runs to the end in one call (viewers without a client).
	var/scan_budget_ms
	/// Lights a delta crossing found newly in reach and not yet held (light handle key -> TRUE, oldest first): their glow images are made by acquire_run(), a budgeted step a tick.
	/// Lazy; null: none waiting.
	var/list/acquire_queue
	/// TRUE while an acquire_continue() timer is waiting.
	var/acquire_waiting = FALSE
	/// Server milliseconds one step of the acquire queue may spend before it leaves the rest to the next tick; null: the queue runs to the end in one call (viewers without a client).
	var/acquire_budget_ms
	/// The acquisitions made by the pending queue so far, and the steps and milliseconds they took (the log line of a spread queue).
	var/acquire_done = 0
	var/acquire_steps = 0
	var/acquire_ms = 0
	/// turf -> TRUE for the turfs the eye saw at its last chunk crossing: decides where a held glow stands.
	var/list/seen
	/// The radius of the sight query that made `seen`.
	var/seen_range = 0
	var/eye_x = 0
	var/eye_y = 0
	/// TRUE while the eye has moved inside its chunk (or opacity changed in its view) and `seen` is not yet taken again; (`sight_to_x`, `sight_to_y`) is where to see from (0: where `seen` was).
	var/sight_dirty = FALSE
	var/sight_to_x = 0
	var/sight_to_y = 0
	/// TRUE while a sight_wake() timer is waiting.
	var/sight_waiting = FALSE
	/// TRUE once this viewer's first hold has been logged (the load-in timeline).
	var/first_hold_logged = FALSE
	/// TRUE: a ghost still seeing darkness: its held copies carry no shadow mask (it sees through walls, so masks buy it nothing).
	var/unmasked = FALSE
	/// TRUE: this viewer does not see darkness (a ghost with darkness off, darkvision): lights draw nothing for it, so each is only hidden.
	var/unlit = FALSE
	/// light source glow_holder_key -> list(glow image, hide image), or list(hide image) while unlit. Lazy.
	var/list/held
	/// light source glow_holder_key -> the mask shape its glow image wants. Lazy.
	var/list/held_shape
	/// light source glow_holder_key -> the mask shape its glow image is cut by now. Lazy.
	var/list/cut_shape
	/// Baked shape -> its preload image, while this client is being sent the PNG. Lazy.
	var/list/delivering
	/// Baked shape -> TRUE once this client confirmed receiving its PNG (or the confirmation timed out). Oldest first; bounded by note_delivered(). Lazy.
	var/list/delivered
	/// Bumped whenever the client's images are forgotten: a delivery started under an older value belongs to a client state that is gone, and its answer is ignored.
	var/delivery_gen = 0
	/// Blank glow images and blank hide images of dropped glows, up to CLIENT_GLOW_POOL_MAX each, for the next glows acquired. Lazy; borrowed from no one: an
	/// image here is on no client, anchored to nothing, and carries nothing of the glow it served.
	var/list/glow_pool
	var/list/hide_pool

/client
	/// This client's held off-screen glows (client lighting only).
	var/datum/client_glow_holder/glow_holder

CAPABILITIES_PART(/client, client_glow_holder)
	owns_one(nameof(glow_holder), /datum/client_glow_holder)

/datum/light_source
	/// This light's key in the holders' held lists, taken once while it is alive (a dying datum's handle cannot be looked up again).
	var/glow_holder_key

SCHEMA(/datum/light_source, glow_holder_key, schema_text())

/datum/light_source/proc/glow_holder_key()
	if(!glow_holder_key)
		glow_holder_key = handle_text(handle_of(src))
	return glow_holder_key

/// Every live holder (REGISTRY_CLIENT_GLOW_HOLDERS): a light event walks them, one per connected client plus test and benchmark viewers.
REGISTRY_MEMBERSHIP(/datum/client_glow_holder, REGISTRY_CLIENT_GLOW_HOLDERS)

/client/interest_eye_moved(turf/at_eye)
	..()
	client_glow_holder_eye(src, at_eye) // held off-screen glows follow the eye's glow chunk
	client_glow_screen_sync(src) // the lighting screen objects (client_lighting_screen.dm); one comparison when in step

/client/interest_eye_left()
	..()
	client_glow_holder_gone(src)

/datum/client_glow_holder/New()
	..()
	join_registries()

/datum/client_glow_holder/on_destroy(force)
	drop_all("holder destroyed")
	glow_pool = null
	hide_pool = null
	seen = null
	client = null
	..()

/// Half the view in turfs on each axis: list(hx, hy). `view` is a number or "WxH".
/proc/client_glow_view_halves(view)
	if(istext(view))
		var/list/size = splittext(view, "x")
		return list(round(text2num(size[1]) / 2), round(text2num(size[length(size)]) / 2))
	var/n = isnum(view) ? view : world.view
	if(istext(n))
		return client_glow_view_halves(n)
	return list(n, n)

/// The client's eye moved or its view changed (interest_eye_update()): its holder follows when the eye's chunk did.
/proc/client_glow_holder_eye(client/C, turf/at_eye)
	if(!GLOB.client_lighting || !C || QDELETED(C))
		return
	if(!C.glow_holder)
		if(!at_eye)
			return
		var/datum/client_glow_holder/H = new
		H.client = C
		H.scan_budget_ms = CLIENT_GLOW_SCAN_BUDGET_MS
		H.acquire_budget_ms = CLIENT_GLOW_ACQUIRE_BUDGET_MS
		rel_set(C, nameof(C.glow_holder), H)
	var/list/halves = client_glow_view_halves(C.view)
	C.glow_holder.view_at(at_eye, halves[1], halves[2])

/// A mob Login just emptied client.images and client.screen: the holder's images and the lighting screen objects are gone from the client whatever
/// their records say, and an equal chunk signature would otherwise leave them gone. Forget both, so the eye update that follows the login rebuilds them.
/proc/client_glow_client_emptied(client/C)
	if(!C)
		return
	log_world("client lighting: [C.ckey] login emptied images and screen; [LAZYLEN(C.glow_holder?.held)] held glow(s) and screen state [C.lighting_screen] forgotten")
	client_glow_screen_forget(C)
	C.glow_holder?.forget_images()

/// The client's images are gone whatever this holder's records say: forget them, and the full scan under way (its chunks would go on holding for a client that has none of the glows it
/// kept). The next eye update starts a full scan again.
/datum/client_glow_holder/proc/forget_images()
	sig = null
	scanned = FALSE
	scan_cancel()
	held = null
	held_shape = null
	cut_shape = null
	delivering = null
	sight_dirty = FALSE
	sight_to_x = 0
	delivery_gen++
	log_world("client lighting: [client?.ckey] images forgotten; pending glow deliveries now stale (generation [delivery_gen])")

/// The client left: its held glows go.
/proc/client_glow_holder_gone(client/C)
	if(!C?.glow_holder)
		return
	var/datum/client_glow_holder/H = C.glow_holder
	rel_clear(C, nameof(C.glow_holder))
	spent(H)

/// The viewer sees from `eye` with view halves (hx, hy). Recomputes only when the eye's chunk or the view changed.
/datum/client_glow_holder/proc/view_at(turf/eye, hx, hy)
	if(!eye)
		sig = null
		drop_all("eye has no turf")
		return
	var/cx = round((eye.x - 1) / CLIENT_GLOW_CHUNK)
	var/cy = round((eye.y - 1) / CLIENT_GLOW_CHUNK)
	var/mob/viewer = client?.mob
	var/mob/observer/dead/ghost = istype(viewer, /mob/observer/dead) ? viewer : null
	var/now_unlit = viewer ? (!viewer.seedarkness || (ghost && !ghost.lighting_alpha)) : FALSE
	var/now_unmasked = !!ghost && !now_unlit
	var/new_sig = "[eye.z]:[cx]:[cy]:[hx]:[hy]:[now_unlit]:[now_unmasked]"
	if(new_sig == sig)
		if(eye.x != eye_x || eye.y != eye_y || sight_dirty)
			sight_follow(eye) // the eye moved inside its chunk: what it sees is not what `seen` holds
		return
	if(now_unlit != unlit || now_unmasked != unmasked)
		drop_all("darkness sight changed: unlit [unlit]->[now_unlit], unmasked [unmasked]->[now_unmasked]") // the entries have the other shape
		unlit = now_unlit
		unmasked = now_unmasked
	if(z != eye.z)
		scanned = FALSE // the old boxes are on another level
		if(LAZYLEN(held))
			drop_all("z-level changed [z]->[eye.z]")
		glow_pool = null // blank images could be kept, but a level change is the one moment a holder's reuse is over
		hide_pool = null
	var/started = TICK_USAGE_REAL
	var/delta = scanned
	var/list/old_reach = reach
	var/list/old_keep = keep_reach
	sig = new_sig
	z = eye.z
	GLOB.client_glow_holder_recomputes++
	var/made_before = GLOB.client_glow_holder_made
	var/dropped_before = GLOB.client_glow_holder_dropped
	var/reused_before = GLOB.client_glow_holder_reused
	var/moved_before = GLOB.client_glow_holder_stands_moved
	var/ex0 = cx * CLIENT_GLOW_CHUNK + 1
	var/ey0 = cy * CLIENT_GLOW_CHUNK + 1
	var/ex1 = ex0 + CLIENT_GLOW_CHUNK - 1
	var/ey1 = ey0 + CLIENT_GLOW_CHUNK - 1
	var/margin = CLIENT_GLOW_KEEP_CHUNKS * CLIENT_GLOW_CHUNK
	reach = list(ex0 - hx, ey0 - hy, ex1 + hx, ey1 + hy)
	keep_reach = list(reach[1] - margin, reach[2] - margin, reach[3] + margin, reach[4] + margin)
	if(delta && !glow_boxes_overlap(old_keep, keep_reach))
		drop_all("view jumped clear of the old keep box") // a teleport: nothing held can stay, and the images go to the pool for the glows of the new place
		delta = FALSE
	var/seen_started = TICK_USAGE_REAL
	var/had_seen = !!seen
	seen_range = max(hx, hy)
	var/list/added = list() // the turfs the eye newly sees and the ones it no longer sees: all that can move a stand on a delta crossing
	var/list/removed = list()
	resight(eye, delta ? added : null, delta ? removed : null)
	sight_dirty = FALSE // this crossing took the sight; a pending in-chunk refresh has nothing left to do
	sight_to_x = 0
	var/scan_started = TICK_USAGE_REAL
	var/list/walk_counts = list(0, 0) // chunks with lights walked, lights examined
	if(delta)
		scan_delta(old_reach, old_keep, walk_counts)
	else
		scan_all(walk_counts)
	var/chunks = walk_counts[1]
	var/lights = walk_counts[2]
	if(delta && !chunks)
		GLOB.client_glow_holder_scans_skipped++
	scanned = !scan_chunks // a full scan with chunks left walks them on the next ticks, and marks the scan done itself
	var/stands_started = TICK_USAGE_REAL
	if(delta && had_seen)
		refresh_stands_near(added, removed)
	else
		refresh_stands()
	var/stands_ended = TICK_USAGE_REAL
	if(!first_hold_logged && client)
		first_hold_logged = TRUE
		log_world("client glow holder: [client.ckey] first hold at [time2text(world.realtime, "hh:mm:ss")], [LAZYLEN(held)] glow(s)") // the load-in timeline
	if(!(GLOB.client_glow_holder_recomputes % 64) && client_glow_trace_line())
		log_world(client_glow_census())
	if(client && length(client.images) < LAZYLEN(held))
		log_world("client glow holder: [client.ckey] has [length(client.images)] images for [LAZYLEN(held)] held glows: something took them off the client")
	// This crossing's cost: the server time it took (a tick_usage delta, so well under a decisecond), and the glows (two client.images each) the client was sent or
	// told to forget. The server time is server cost; the images are the client's (the map FPS is only on the client, so this is as near as the server can say).
	if(!client_glow_trace_line())
		return
	var/made = GLOB.client_glow_holder_made - made_before
	var/dropped = GLOB.client_glow_holder_dropped - dropped_before
	var/reused = GLOB.client_glow_holder_reused - reused_before
	log_world("client glow holder: [client?.ckey] entered chunk [new_sig] from eye [eye.type] at [eye.x],[eye.y] (mob [viewer ? "[viewer.type]" : "none"]), holding [LAZYLEN(held)] glow(s), [LAZYLEN(held) - made] kept[unlit ? " (hidden only, viewer sees no darkness)" : (unmasked ? " (unmasked, ghost)" : "")], [made] made ([reused] images reused from the pool) and [dropped] dropped this crossing, pool [length(glow_pool)]/[length(hide_pool)], [delta ? (chunks ? "scan delta: [chunks] chunk(s), [lights] light(s), seen +[length(added)]/-[length(removed)] turf(s)" : "scan skipped: no light near the moved edges") : "scan full: [chunks] chunk(s), [lights] light(s)[scan_chunks ? ", [length(scan_chunks) - scan_at] more chunk(s) on the next ticks" : ""]"], [GLOB.client_glow_holder_stands_moved - moved_before] stand(s) moved, [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), 0.01)] ms (sight [round(TICK_DELTA_TO_MS(scan_started - seen_started), 0.01)], scan [round(TICK_DELTA_TO_MS(stands_started - scan_started), 0.01)], stands [round(TICK_DELTA_TO_MS(stands_ended - stands_started), 0.01)]), [GLOB.client_glow_holder_made] made and [GLOB.client_glow_holder_dropped] dropped so far")

/// The eye stands on `eye`: `seen` becomes the turfs it sees from there. With `added` (a list) and `removed` (an assoc list) given, they get the turfs the eye gained and
/// lost since `seen` was last taken: all that can move a stand.
/datum/client_glow_holder/proc/resight(turf/eye, list/added, list/removed)
	var/list/old_seen = seen
	eye_x = eye.x
	eye_y = eye.y
	seen = list()
	if(!unlit)
		for(var/turf/T as anything in sight_view_turfs(eye, seen_range))
			seen[T] = TRUE
	if(!isnull(added) && old_seen)
		for(var/turf/T as anything in seen)
			if(!old_seen[T])
				added += T
		for(var/turf/T as anything in old_seen)
			if(!seen[T])
				removed[T] = TRUE

/// The eye moved inside its chunk to `eye`. A client's sight is taken again after CLIENT_GLOW_SIGHT_INTERVAL at most (a step a tick would otherwise cost a sight
/// query a tick); a viewer with no client (a test) takes it at once.
/datum/client_glow_holder/proc/sight_follow(turf/eye)
	sight_to_x = eye.x
	sight_to_y = eye.y
	sight_dirty = TRUE
	if(!client)
		sight_refresh()
		return
	if(!sight_waiting)
		sight_waiting = TRUE
		after(src, CLIENT_GLOW_SIGHT_INTERVAL, PROC_REF(sight_wake))

/// The timer of sight_follow().
/datum/client_glow_holder/proc/sight_wake()
	sight_waiting = FALSE
	sight_refresh()

/// TRUE when box `box` (list(x0, y0, x1, y1)) could be in this viewer's sight: near the eye, with a chunk's slack for an eye that moved since `seen` was taken.
/datum/client_glow_holder/proc/sees_box(list/box)
	var/reach_tiles = seen_range + CLIENT_GLOW_CHUNK
	return !(box[3] < eye_x - reach_tiles || box[1] > eye_x + reach_tiles || box[4] < eye_y - reach_tiles || box[2] > eye_y + reach_tiles)

/// Takes the eye's sight again from where it stands (it moved inside its chunk, or opacity changed in its view) and moves the glows whose stand it changed: a glow
/// on a turf the eye no longer sees would be culled (it blinks), so it stands on a turf of its reach the eye does see.
/datum/client_glow_holder/proc/sight_refresh()
	var/turf/eye = sight_to_x ? locate(sight_to_x, sight_to_y, z) : locate(eye_x, eye_y, z)
	sight_dirty = FALSE
	sight_to_x = 0
	if(!sig || unlit || !eye || eye.z != z)
		return
	var/started = TICK_USAGE_REAL
	var/moved_before = GLOB.client_glow_holder_stands_moved
	var/list/added = list()
	var/list/removed = list()
	resight(eye, added, removed)
	refresh_stands_near(added, removed)
	GLOB.client_glow_holder_sight_refreshes++
	if(client_glow_trace_line())
		log_world("client glow holder: [client?.ckey] took new sight at [eye.x],[eye.y]: seen +[length(added)]/-[length(removed)] turf(s), [GLOB.client_glow_holder_stands_moved - moved_before] stand(s) moved, [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - started), 0.01)] ms")

/// Walks the lights of chunk `chunk_key` ("gx,gy") on this level: each is acquired, updated or dropped against the boxes; one that is not held may have its shape sent ahead.
/// `keep` (a full scan) collects the lights met (light -> TRUE if held): a light is in every chunk its reach box overlaps, so it is met once. Returns how many lights it examined.
/datum/client_glow_holder/proc/scan_chunk(chunk_key, list/keep)
	GLOB.client_glow_holder_chunk_visits++
	var/list/members = GLOB.client_glow_chunks["[z],[chunk_key]"]
	if(!members)
		return 0
	var/examined = 0
	for(var/datum/light_source/L as anything in members)
		if(!isnull(keep[L]))
			continue
		examined++
		if(consider(L))
			keep[L] = TRUE
		else
			keep[L] = FALSE
			prefetch(L)
	return examined

/// Readies the shape of light `L`, which is not held: baking starts, and the picture goes to the client before the crossing that holds it.
/datum/client_glow_holder/proc/prefetch(datum/light_source/L)
	if(unlit || unmasked || !L.glow_mask_key || L.glow_plain)
		return
	client_glow_mask_prefetch(L.glow_mask_key)
	var/ahead = GLOB.client_glow_baker.icons[L.glow_mask_key]
	if(ahead)
		deliver(L.glow_mask_key, ahead) // on the client before the crossing that holds it

/// The first crossing, a jump or any crossing after a drop-all: every chunk the reach box covers, and the ring one chunk further out
/// (those lights are not held, but their shapes are readied for the next crossing). The chunks are ordered nearest the eye first and walked a step at a time (scan_run()):
/// what the eye sees is held by the first step, the ring comes last. `counts` gets the chunks walked and lights examined by the step that ran here.
/datum/client_glow_holder/proc/scan_all(list/counts)
	scan_cancel()
	var/chunk = CLIENT_GLOW_CHUNK
	var/list/chunks_in_reach = glow_chunk_range(list(reach[1] - chunk, reach[2] - chunk, reach[3] + chunk, reach[4] + chunk))
	var/list/order = list()
	for(var/gx in chunks_in_reach[1] to chunks_in_reach[3])
		var/x0 = gx * CLIENT_GLOW_CHUNK + 1
		var/dx = max(x0 - eye_x, eye_x - (x0 + CLIENT_GLOW_CHUNK - 1), 0)
		for(var/gy in chunks_in_reach[2] to chunks_in_reach[4])
			var/y0 = gy * CLIENT_GLOW_CHUNK + 1
			var/dy = max(y0 - eye_y, eye_y - (y0 + CLIENT_GLOW_CHUNK - 1), 0)
			order["[gx],[gy]"] = dx * dx + dy * dy // the squared distance from the eye to the chunk's nearest turf
	scan_chunks = sortTim(order, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
	scan_at = 0
	scan_keep = list()
	scan_walked = 0
	scan_lights = 0
	scan_steps = 0
	scan_ms = 0
	scan_run()
	counts[1] = scan_walked
	counts[2] = scan_lights

/// One step of the pending full scan: chunks in order until the budget is spent (always at least one), then the rest is handed to the next tick; the last step closes the scan.
/datum/client_glow_holder/proc/scan_run()
	var/started = TICK_USAGE_REAL
	var/list/chunks = scan_chunks
	while(scan_at < length(chunks))
		var/walked = scan_chunk(chunks[++scan_at], scan_keep)
		if(walked)
			scan_walked++
			scan_lights += walked
		if(!isnull(scan_budget_ms) && scan_at < length(chunks) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= scan_budget_ms)
			break
	scan_steps++
	scan_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	if(scan_at < length(chunks))
		if(!scan_waiting)
			scan_waiting = TRUE
			after(src, 1 TICKS, PROC_REF(scan_continue))
		return
	scan_finish()

/// The timer of a spread full scan: its next step, unless the scan was cancelled (a drop-all, a login wipe) in the meantime.
/datum/client_glow_holder/proc/scan_continue()
	scan_waiting = FALSE
	if(!scan_chunks || !sig)
		return
	scan_run()

/// Every chunk is walked: a held glow no walked chunk kept (a stale one from an earlier unfinished scan, or a light that moved after its chunk was walked) stays only if it
/// still meets the boxes. Then the scan is closed, so the next crossing is a delta.
/datum/client_glow_holder/proc/scan_finish()
	var/list/keep = scan_keep
	for(var/h in LAZYCOPY(held))
		var/datum/light_source/L = handle_get(h)
		if(istype(L) && !QDELETED(L) && keep[L])
			continue
		if(!istype(L) || QDELETED(L) || !consider(L))
			drop_handle(h)
	var/steps = scan_steps
	var/spent_ms = scan_ms
	var/chunks = scan_walked
	var/lights = scan_lights
	scan_cancel()
	scanned = TRUE
	if(steps > 1) // a one-step scan is the crossing's own log line
		log_world("client glow holder: [client?.ckey] full scan finished over [steps] steps: [chunks] chunk(s), [lights] light(s), [round(spent_ms, 0.01)] ms in all, holding [LAZYLEN(held)] glow(s)")

/// Forgets the pending full scan (a new one begins, the held glows were dropped or the client's images wiped); a timer already waiting finds nothing to do.
/datum/client_glow_holder/proc/scan_cancel()
	acquire_cancel() // a full scan walks every light again; one that begins over nothing held or a client that lost its images makes the queued lights stale
	scan_chunks = null
	scan_keep = null
	scan_at = 0

/// A crossing from the boxes `old_reach`/`old_keep` to the current ones. Light events keep every held glow current against the boxes as they stood, so a
/// light's status changes only where the boxes moved. The lights that can change have their reach boxes overlapping one of three strips:
///   - acquire: the part of the new reach box the old one did not cover;
///   - ring: the part of the new reach box grown by one chunk that the old one grown the same did not cover (shapes readied ahead);
///   - drop: the part of the old keep box the new one does not cover.
/// The index holds a light in every chunk its reach box overlaps, so the chunks the strips cover hold exactly those lights (and a few more, which the exact test
/// below passes by): a step across one chunk walks the chunks along the box edges. Every light in them is then tested exactly against the boxes (scan_light_delta()).
/datum/client_glow_holder/proc/scan_delta(list/old_reach, list/old_keep, list/counts)
	var/chunk = CLIENT_GLOW_CHUNK
	var/list/new_ring = list(reach[1] - chunk, reach[2] - chunk, reach[3] + chunk, reach[4] + chunk)
	var/list/old_ring = list(old_reach[1] - chunk, old_reach[2] - chunk, old_reach[3] + chunk, old_reach[4] + chunk)
	var/list/strips = glow_box_minus(reach, old_reach) + glow_box_minus(new_ring, old_ring) + glow_box_minus(old_keep, keep_reach)
	var/list/done = list()
	for(var/list/strip as anything in strips)
		walk_box_chunks(strip, done, counts, new_ring, old_ring)

/// Walks the chunks (not yet in `done`) that box `box` covers, testing each light there (once: a light is in several chunks) against the boxes.
/datum/client_glow_holder/proc/walk_box_chunks(list/box, list/done, list/counts, list/new_ring, list/old_ring)
	var/list/chunks_in_box = glow_chunk_range(box)
	for(var/gx in chunks_in_box[1] to chunks_in_box[3])
		for(var/gy in chunks_in_box[2] to chunks_in_box[4])
			var/chunk_id = "[gx],[gy]"
			if(done[chunk_id])
				continue
			done[chunk_id] = TRUE
			GLOB.client_glow_holder_chunk_visits++
			var/list/members = GLOB.client_glow_chunks["[z],[chunk_id]"]
			if(!members)
				continue
			counts[1]++
			for(var/datum/light_source/L as anything in members)
				if(done[L])
					continue
				done[L] = TRUE
				counts[2]++
				scan_light_delta(L, new_ring, old_ring)

/// One light met by a delta crossing: held and clear of the keep box, it is dropped; not held and meeting the reach box, it is acquired; not held and newly inside the
/// prefetch ring, its shape is readied. A held light inside the keep box needs nothing (its events keep it current).
/datum/client_glow_holder/proc/scan_light_delta(datum/light_source/L, list/new_ring, list/old_ring)
	var/turf/S = L.source_turf
	if(!S)
		consider(L) // drops it
		return
	var/sx = S.x
	var/sy = S.y
	var/r = CLIENT_GLOW_RADIUS(L)
	var/h = L.glow_holder_key
	if(h && LAZYACCESS(held, h))
		if(CLIENT_GLOW_CLEAR_OF(sx, sy, r, keep_reach))
			drop_handle(h)
		return
	if(!CLIENT_GLOW_CLEAR_OF(sx, sy, r, reach))
		acquire_later(L)
		return
	if(!CLIENT_GLOW_CLEAR_OF(sx, sy, r, new_ring) && CLIENT_GLOW_CLEAR_OF(sx, sy, r, old_ring))
		prefetch(L)

/// Light `L` is newly in reach of a delta crossing: its glow is made by the budgeted acquire queue, so a crossing that brings many lights into view cannot spike a tick.
/// A viewer with no budget (tests) takes it at once.
/datum/client_glow_holder/proc/acquire_later(datum/light_source/L)
	if(isnull(acquire_budget_ms))
		consider(L)
		return
	var/h = L.glow_holder_key || L.glow_holder_key()
	if(LAZYACCESS(acquire_queue, h))
		return
	LAZYSET(acquire_queue, h, TRUE)
	if(!acquire_waiting)
		acquire_waiting = TRUE
		after(src, 1 TICKS, PROC_REF(acquire_continue))

/// The timer of the acquire queue: its next step, unless the queue was cancelled in the meantime.
/datum/client_glow_holder/proc/acquire_continue()
	acquire_waiting = FALSE
	if(!sig)
		acquire_cancel()
		return
	if(!length(acquire_queue))
		return
	acquire_run()

/// One step of the acquire queue: lights in order until the budget is spent (always at least one), then the rest waits for the next tick. A light is tested again against
/// the boxes as they stand now (consider()), so one that left reach or was dropped while it waited makes nothing.
/datum/client_glow_holder/proc/acquire_run()
	var/started = TICK_USAGE_REAL
	var/list/queue = acquire_queue
	while(length(queue))
		var/datum/light_source/L = handle_get(queue[1])
		queue.Cut(1, 2)
		if(istype(L) && !QDELETED(L) && consider(L))
			acquire_done++
		if(length(queue) && TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) >= acquire_budget_ms)
			break
	var/step_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
	acquire_steps++
	acquire_ms += step_ms
	if(length(queue))
		if(!acquire_waiting)
			acquire_waiting = TRUE
			after(src, 1 TICKS, PROC_REF(acquire_continue))
		return
	if(client_glow_trace_line())
		log_world("client glow holder: [client?.ckey] acquire queue finished over [acquire_steps] step(s): [acquire_done] glow(s) made, [round(acquire_ms, 0.01)] ms in all (last step [round(step_ms, 0.01)] ms), holding [LAZYLEN(held)] glow(s)")
	acquire_cancel()

/// Forgets the lights waiting to be acquired (a drop-all, a login wipe, a new full scan that walks them anyway); a timer already waiting finds nothing to do.
/datum/client_glow_holder/proc/acquire_cancel()
	acquire_queue = null
	acquire_done = 0
	acquire_steps = 0
	acquire_ms = 0

/// The parts of box `a` that box `b` does not cover, as up to four boxes list(x0, y0, x1, y1).
/proc/glow_box_minus(list/a, list/b)
	. = list()
	if(b[3] < a[1] || b[1] > a[3] || b[4] < a[2] || b[2] > a[4])
		. += list(a)
		return
	if(a[1] < b[1])
		. += list(list(a[1], a[2], b[1] - 1, a[4]))
	if(a[3] > b[3])
		. += list(list(b[3] + 1, a[2], a[3], a[4]))
	var/x0 = max(a[1], b[1])
	var/x1 = min(a[3], b[3])
	if(a[2] < b[2])
		. += list(list(x0, a[2], x1, b[2] - 1))
	if(a[4] > b[4])
		. += list(list(x0, b[4] + 1, x1, a[4]))

/// A delta crossing's stand upkeep: only the glows near what the eye's sight gained or lost are looked at. A glow needs a new place when the turf it stands on left the
/// seen set (`removed`), or, with its light reaching a turf that came into sight (`added`), when it is not where the eye's sight puts it (as in refresh_stands()). A glow's
/// stand is a turf of its light's reach, and a turf in the reach is in a chunk the light is indexed under: the chunks the changed turfs lie in hold every such light.
/datum/client_glow_holder/proc/refresh_stands_near(list/added, list/removed)
	if(!LAZYLEN(held) || unlit || (!length(added) && !length(removed)))
		return
	var/list/add_box = glow_turfs_box(added)
	var/list/rem_box = glow_turfs_box(removed)
	var/list/done = list()
	for(var/list/box as anything in list(add_box, rem_box))
		if(!box)
			continue
		var/list/chunks_in_box = glow_chunk_range(box)
		for(var/gx in chunks_in_box[1] to chunks_in_box[3])
			for(var/gy in chunks_in_box[2] to chunks_in_box[4])
				for(var/datum/light_source/L as anything in GLOB.client_glow_chunks["[z],[gx],[gy]"])
					if(done[L])
						continue
					done[L] = TRUE
					near_stand(L, removed, add_box)

/// The box of the turfs in `turfs` (a list of turfs, or an assoc list keyed by turf): list(x0, y0, x1, y1), or null for none.
/proc/glow_turfs_box(list/turfs)
	if(!length(turfs))
		return null
	var/x0 = INFINITY
	var/y0 = INFINITY
	var/x1 = 0
	var/y1 = 0
	for(var/turf/T as anything in turfs)
		x0 = min(x0, T.x)
		y0 = min(y0, T.y)
		x1 = max(x1, T.x)
		y1 = max(y1, T.y)
	return list(x0, y0, x1, y1)

/// Light `L`, near what the eye's sight gained or lost: its held glow gets a new place if the turf it stands on was lost, or if it is where sight no longer puts it.
/datum/client_glow_holder/proc/near_stand(datum/light_source/L, list/removed, list/add_box)
	var/list/entry = LAZYACCESS(held, L.glow_holder_key)
	if(length(entry) < 2)
		return
	var/image/glow_image = entry[1]
	var/turf/at = glow_image.loc
	var/turf/S = L.source_turf
	var/obj/effect/overlay/client_glow/G = L.glow
	if(!S || !G || QDELETED(L))
		return
	if(!(at && removed[at]))
		if(!add_box || CLIENT_GLOW_CLEAR_OF(S.x, S.y, CLIENT_GLOW_RADIUS(L), add_box))
			return
		if(seen[S] ? (at == S) : (at != S && seen[at]))
			return
	var/turf/stand_on = stand_turf(L, S, at)
	if(stand_on != at)
		restand(glow_image, G, S, stand_on)

/// Brings every held glow's standing turf in line with what the eye saw at this crossing. A glow stands on its own turf when the eye saw it, else on a seen turf of its
/// reach: one it already stands on stays valid while that turf is seen, so only a glow whose turf was left unseen (or whose own turf came into sight) is looked at again.
/// Reads only the images and the real glow they hide (its loc is the light's turf); the light is looked up for the few that need a new turf.
/datum/client_glow_holder/proc/refresh_stands()
	for(var/h in held)
		var/list/entry = held[h]
		if(length(entry) < 2)
			continue
		var/image/glow_image = entry[1]
		var/image/hide_image = entry[2]
		var/obj/effect/overlay/client_glow/G = hide_image.loc
		if(!istype(G))
			continue
		var/turf/S = G.loc
		if(!isturf(S))
			continue
		var/turf/at = glow_image.loc
		if(seen[S] ? (at == S) : (at != S && seen[at]))
			continue
		var/datum/light_source/L = handle_get(h)
		if(!istype(L) || QDELETED(L))
			continue
		var/turf/stand_on = stand_turf(L, S, at)
		if(stand_on != at)
			restand(glow_image, G, S, stand_on)

/// Puts `glow_image` on `stand_on`, offset so it draws where the real glow (standing on `S`) would. Only a changed value is written: an assignment to an
/// image the client holds can cost a client update even when nothing differs.
/datum/client_glow_holder/proc/restand(image/glow_image, obj/effect/overlay/client_glow/G, turf/S, turf/stand_on)
	var/px = (S.x - stand_on.x) * WORLD_ICON_SIZE + G.pixel_x
	var/py = (S.y - stand_on.y) * WORLD_ICON_SIZE + G.pixel_y
	if(glow_image.pixel_x != px)
		glow_image.pixel_x = px
	if(glow_image.pixel_y != py)
		glow_image.pixel_y = py
	if(glow_image.loc != stand_on)
		image_anchor(glow_image, stand_on)
		GLOB.client_glow_holder_stands_moved++

/// Shows, updates or drops this viewer's copy of light `L`. Returns TRUE while it is held.
/datum/client_glow_holder/proc/consider(datum/light_source/L)
	if(!sig || QDELETED(L) || !L.glow || !L.glow_mask_key)
		drop(L)
		return FALSE
	var/turf/S = L.source_turf
	if(!S || S.z != z)
		drop(L)
		return FALSE
	var/h = L.glow_holder_key || L.glow_holder_key()
	var/list/entry = LAZYACCESS(held, h)
	if(unlit)
		return consider_unlit(L, S, h, entry)
	var/r = CLIENT_GLOW_RADIUS(L)
	var/list/box = entry ? keep_reach : reach
	if(CLIENT_GLOW_CLEAR_OF(S.x, S.y, r, box))
		if(entry)
			drop_handle(h) // held and now clear of the keep box; not held and its reach never comes on screen from this chunk
		return FALSE
	var/obj/effect/overlay/client_glow/G = L.glow
	var/fresh = !entry
	if(fresh)
		entry = acquire_entry(G, TRUE)
	else
		GLOB.client_glow_holder_updated++
	var/image/glow_image = entry[1]
	var/turf/stand_on = stand_turf(L, S, fresh ? null : glow_image.loc)
	var/px = (S.x - stand_on.x) * WORLD_ICON_SIZE + G.pixel_x
	var/py = (S.y - stand_on.y) * WORLD_ICON_SIZE + G.pixel_y
	// Only a changed value is written: an assignment to an image the client holds can cost a client update even when nothing differs. A pooled image
	// was blanked when it was dropped, so each of these differs from the glow's and is written: nothing of its last glow can remain.
	if(glow_image.plane != G.plane)
		glow_image.plane = G.plane
	if(glow_image.color != G.color)
		glow_image.color = G.color
	if(glow_image.alpha != G.alpha)
		glow_image.alpha = G.alpha
	if(glow_image.pixel_x != px)
		glow_image.pixel_x = px
	if(glow_image.pixel_y != py)
		glow_image.pixel_y = py
	apply_shape(L, h, glow_image, G)
	if(fresh)
		LAZYSET(held, h, entry)
		client_images_add(client, entry)
	if(glow_image.loc != stand_on)
		image_anchor(glow_image, stand_on)
	return TRUE

/// A glow image and its hide image for a glow of `G`: from the pool when it has them, else new. Unlit viewers (`with_glow` FALSE) take a hide image only.
/// Everything that can differ between glows (picture, plane, colour, alpha, offset, loc) is left blank here for the caller to set.
/datum/client_glow_holder/proc/acquire_entry(obj/effect/overlay/client_glow/G, with_glow)
	var/image/hide_image
	if(length(hide_pool))
		hide_image = hide_pool[length(hide_pool)]
		hide_pool.len--
		GLOB.client_glow_holder_reused++
	else
		hide_image = image(null) // overrides the real glow for this viewer: never drawn twice
		hide_image.override = TRUE
	image_anchor(hide_image, G)
	if(!with_glow)
		GLOB.client_glow_holder_made++
		return list(hide_image)
	var/image/glow_image
	if(length(glow_pool))
		glow_image = glow_pool[length(glow_pool)]
		glow_pool.len--
		GLOB.client_glow_holder_reused++
	else
		glow_image = image(G.icon, null, G.icon_state)
		glow_image.blend_mode = BLEND_ADD
		glow_image.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_APART
		glow_image.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	glow_image.layer = G.layer
	GLOB.client_glow_holder_made++
	return list(glow_image, hide_image)

/// Takes a dropped glow's images (already off the client) back to the pool, blank: no picture, plane, colour, alpha, offset or loc of the glow they showed.
/datum/client_glow_holder/proc/release_entry(list/entry)
	for(var/image/I as anything in entry)
		image_anchor(I, null)
		I.icon = null
		I.icon_state = null
		I.plane = initial(I.plane)
		I.color = null
		I.alpha = initial(I.alpha)
		I.pixel_x = 0
		I.pixel_y = 0
	if(length(entry) == 2)
		if(length(glow_pool) < CLIENT_GLOW_POOL_MAX)
			LAZYADD(glow_pool, entry[1])
		if(length(hide_pool) < CLIENT_GLOW_POOL_MAX)
			LAZYADD(hide_pool, entry[2])
	else if(length(entry) == 1 && length(hide_pool) < CLIENT_GLOW_POOL_MAX)
		LAZYADD(hide_pool, entry[1])

/// Where light `L`'s held glow stands: its own turf if the eye saw it; else `current` while the eye still sees it (a glow already standing on a seen turf of its
/// reach stays); else the turf of its reach the eye saw that is nearest the eye. The search runs over the cells where the light's reach meets what the eye can
/// see, not over the reach's keys.
/datum/client_glow_holder/proc/stand_turf(datum/light_source/L, turf/S, turf/current = null)
	if(seen[S] || !L.glow_reach_origin)
		return S
	if(current && current != S && seen[current])
		return current
	var/turf/O = L.glow_reach_origin
	var/list/cells = L.glow_reach
	var/best_x
	var/best_y
	var/best = INFINITY
	for(var/x in max(O.x - CLIENT_GLOW_MAX_RANGE, eye_x - seen_range, 1) to min(O.x + CLIENT_GLOW_MAX_RANGE, eye_x + seen_range, world.maxx))
		for(var/y in max(O.y - CLIENT_GLOW_MAX_RANGE, eye_y - seen_range, 1) to min(O.y + CLIENT_GLOW_MAX_RANGE, eye_y + seen_range, world.maxy))
			var/dist = abs(x - eye_x) + abs(y - eye_y)
			if(dist >= best)
				continue
			var/turf/T = locate(x, y, z)
			if(!T || !seen[T] || !cells["[x - O.x],[y - O.y]"])
				continue
			best = dist
			best_x = x
			best_y = y
	return best == INFINITY ? S : locate(best_x, best_y, z)

/// Gives a held glow the picture it should show: the baked cut of its shape, its previous cut while a new one bakes, or the plain sprite.
/datum/client_glow_holder/proc/apply_shape(datum/light_source/L, h, image/glow_image, obj/effect/overlay/client_glow/G)
	if(unmasked || L.glow_plain)
		LAZYREMOVE(held_shape, h)
		LAZYREMOVE(cut_shape, h)
		show_plain(glow_image, G)
		return
	var/shape = L.glow_mask_key
	if(LAZYACCESS(held_shape, h) != shape)
		LAZYSET(held_shape, h, shape)
		var/baked = client_glow_mask_icon(shape)
		if(baked && deliver(shape, baked))
			cut_with(h, glow_image, shape, baked)
			return
	var/cut = LAZYACCESS(cut_shape, h)
	if(cut == shape)
		return
	// The old cut may only stand in when the new reach is inside it: a door opening grows the reach, and the old cut would leave the door
	// tile and the room behind it dark until the new one arrives. The plain sprite is already on the client; the visibility and wall cuts bound it.
	if(!cut || copytext(cut, 1, findtext(cut, "|")) != copytext(shape, 1, findtext(shape, "|")) || client_glow_shape_grew(cut, shape))
		LAZYREMOVE(cut_shape, h)
		show_plain(glow_image, G)

/datum/client_glow_holder/proc/show_plain(image/glow_image, obj/effect/overlay/client_glow/G)
	glow_image.icon = G.icon
	glow_image.icon_state = G.icon_state

/// Shows a held glow baked to `shape`.
/datum/client_glow_holder/proc/cut_with(h, image/glow_image, shape, baked)
	glow_image.icon = baked
	glow_image.icon_state = null
	LAZYSET(cut_shape, h, shape)

/// TRUE once this client can draw `baked`. An image whose icon the client has not received draws nothing until it arrives, so a new PNG goes
/// to the client first on a black (invisible under BLEND_ADD) preload image, and the held glows swap to it afterwards (client_glow_delivered()).
/datum/client_glow_holder/proc/deliver(shape, baked)
	if(!client || LAZYACCESS(delivered, shape))
		return TRUE
	if(LAZYACCESS(delivering, shape))
		return FALSE
	var/turf/eye = locate(eye_x, eye_y, z)
	if(!eye)
		return TRUE
	var/image/preload = image(baked)
	preload.color = "#000000" // adds nothing, however many are stacked: a faint copy would show as a patch around the eye
	preload.plane = PLANE_LIGHTING
	preload.layer = CLIENT_GLOW_LAYER
	preload.blend_mode = BLEND_ADD
	preload.appearance_flags = RESET_COLOR | RESET_ALPHA | RESET_TRANSFORM | KEEP_APART
	preload.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	image_anchor(preload, eye)
	LAZYSET(delivering, shape, preload)
	client_images_add(client, list(preload))
	// The icon goes into the client's browse queue, then the asset verify page behind it: the queue is FIFO, so the page's ack means the PNG has arrived
	// (client_session.dm flush_assets()). Until then the held glows keep their previous picture. A client with no session has no ack to wait for.
	client << browse_rsc(baked)
	if(client.session)
		client.session.flush_assets(src, PROC_REF(client_glow_delivered), shape, baked, delivery_gen, REALTIMEOFDAY)
	else
		after(src, CLIENT_GLOW_ICON_DELIVERY, PROC_REF(client_glow_delivered), with = list(shape, baked, delivery_gen, REALTIMEOFDAY))
	return FALSE

/// The client's ack for `shape`'s PNG arrived, or the wait ran out (ASSET_FLUSH_TIMEOUT: the glows then swap anyway, as a client that never answers must not keep a
/// stale glow forever). `gen` is the delivery_gen the send started under; `started` is its REALTIMEOFDAY.
/datum/client_glow_holder/proc/client_glow_delivered(shape, baked, gen, started)
	if(gen != delivery_gen)
		log_world("client lighting: [client?.ckey] ignored a stale glow delivery of a shape (generation [gen], now [delivery_gen])")
		return
	var/image/preload = LAZYACCESS(delivering, shape)
	LAZYREMOVE(delivering, shape)
	if(preload && client)
		client_images_remove(client, list(preload))
	var/waited = REALTIMEOFDAY - started
	if(waited >= ASSET_FLUSH_TIMEOUT || client_glow_trace_line()) // a timeout is an anomaly and always written; an ordinary ack only while tracing
		log_world("client lighting: [client?.ckey] glow shape delivery [waited >= ASSET_FLUSH_TIMEOUT ? "TIMED OUT, swapping anyway" : "acknowledged"] after [waited / 10]s")
	note_delivered(shape)
	shape_ready(shape, baked)

/// Records `shape` as delivered. Past CLIENT_GLOW_MASK_CACHE_MAX entries the oldest quarter goes in one cut, so the list is bounded without a trim per call.
/datum/client_glow_holder/proc/note_delivered(shape)
	LAZYSET(delivered, shape, TRUE)
	if(length(delivered) > CLIENT_GLOW_MASK_CACHE_MAX)
		var/keep = round(CLIENT_GLOW_MASK_CACHE_MAX * 0.75)
		delivered.Cut(1, length(delivered) - keep + 1)

/// A shape finished baking: every held glow waiting on it shows it, once this client has the picture.
/datum/client_glow_holder/proc/shape_ready(shape, baked)
	var/waited_on = FALSE
	for(var/h in held_shape)
		if(held_shape[h] == shape && LAZYACCESS(cut_shape, h) != shape)
			waited_on = TRUE
			break
	if(!waited_on || !deliver(shape, baked))
		return
	for(var/h in held_shape)
		if(held_shape[h] != shape || LAZYACCESS(cut_shape, h) == shape)
			continue
		var/list/entry = LAZYACCESS(held, h)
		if(length(entry) == 2)
			cut_with(h, entry[1], shape, baked)

/// A viewer that sees no darkness: every light its view can reach is hidden from it with a plain override image, so its client
/// never draws the glows (a ghost sees through walls, so otherwise all of them, for no visible light).
/datum/client_glow_holder/proc/consider_unlit(datum/light_source/L, turf/S, h, list/entry)
	var/r = CLIENT_GLOW_RADIUS(L)
	var/list/box = entry ? keep_reach : reach
	if(CLIENT_GLOW_CLEAR_OF(S.x, S.y, r, box))
		if(entry)
			drop_handle(h)
		return FALSE
	if(entry)
		return TRUE
	entry = acquire_entry(L.glow, FALSE)
	LAZYSET(held, h, entry)
	client_images_add(client, entry)
	return TRUE

/// This viewer stops holding light `L`.
/datum/client_glow_holder/proc/drop(datum/light_source/L)
	if(L.glow_holder_key)
		drop_handle(L.glow_holder_key)

/datum/client_glow_holder/proc/drop_handle(h)
	var/list/entry = LAZYACCESS(held, h)
	if(!entry)
		return
	LAZYREMOVE(held, h)
	LAZYREMOVE(held_shape, h)
	LAZYREMOVE(cut_shape, h)
	client_images_remove(client, entry) // first: the client index reads each image's loc to forget it
	release_entry(entry)
	GLOB.client_glow_holder_dropped++

/datum/client_glow_holder/proc/drop_all(reason = "unspecified")
	scanned = FALSE // nothing held matches any box now: the next crossing walks the whole region
	scan_cancel() // and a scan under way walked boxes that no longer hold
	if(LAZYLEN(held))
		log_world("client glow holder: [client?.ckey] dropped all [LAZYLEN(held)] held glow(s): [reason]") // every glow gone at once shows as black with only the darksight circle
	for(var/h in LAZYCOPY(held))
		drop_handle(h)

/// Images waiting in this viewer's pools (tests): list(glow images, hide images).
/datum/client_glow_holder/proc/pool_sizes()
	return list(length(glow_pool), length(hide_pool))

/// This viewer's copy of light `L` (tests): list(glow image, hide image), or null.
/datum/client_glow_holder/proc/entry_of(datum/light_source/L)
	return L.glow_holder_key && LAZYACCESS(held, L.glow_holder_key)

/// Every image this viewer holds (tests).
/datum/client_glow_holder/proc/images()
	. = list()
	for(var/h in held)
		. += held[h]

/// Light `L` glowed, moved, changed or rebuilt its mask: every viewer updates its copy.
/proc/client_glow_holders_consider(datum/light_source/L)
	for(var/datum/client_glow_holder/H as anything in REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS))
		H.consider(L)

/// Light `L` stopped glowing: every viewer drops its copy.
/proc/client_glow_holders_drop(datum/light_source/L)
	for(var/datum/client_glow_holder/H as anything in REGISTRY_MEMBERS(REGISTRY_CLIENT_GLOW_HOLDERS))
		H.drop(L)

/// Client lighting switched: off drops every held glow; on recomputes every client's holder from its eye.
/proc/client_glow_holders_switched(on)
	for(var/datum/client_glow_holder/H as anything in REGISTRY_COPY(REGISTRY_CLIENT_GLOW_HOLDERS))
		H.sig = null
		H.drop_all("client lighting switched")
	if(on)
		for(var/client/C as anything in GLOB.clients)
			client_glow_holder_eye(C, get_turf(C.eye || C.mob))

/// (Tests, benchmarks.) A viewer eye about ten turfs from `L` on x, in L's row: its reach comes on screen from that eye's chunk.
/proc/client_glow_test_eye(turf/L)
	var/x = L.x > 20 ? L.x - 10 : L.x + 10
	return locate(x, L.y, L.z)
