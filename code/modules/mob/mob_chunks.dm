// Mob chunks (roadmap S3: mob chunk keys).
//
// A 16x16 chunk that something waits on is a /datum/mob_chunk. A mob entering, leaving or moving in
// it raises its bits -- CHANGE_CHUNK_ANY_MOB for any mob, CHANGE_CHUNK_PLAYER for a mob with a
// client -- and whatever sleeps on it (a calm AI brain, a dormant looping sound, a proximity-gated
// object) is called back: watch_mob_chunks(watcher, chunks, mask, PROC_REF(x)) runs
// watcher.x(chunk, bits). Watchers are held by REF text, so a deleted watcher is dropped at the
// next wake. A chunk nobody watches has no datum, and mob movement skips the lookup entirely while
// nothing watches any chunk.

/// Chunk id -> /datum/mob_chunk, for chunks something watches.
GLOBAL_LIST_EMPTY(mob_chunks)
/// Live any-mob and player chunk watches. Movement publishes only while these are non-zero; a
/// watch dropped with its watcher leaves them high, which only costs lookups.
GLOBAL_VAR_INIT(mob_chunk_watches, 0)
GLOBAL_VAR_INIT(player_chunk_watches, 0)

/datum/mob_chunk
	var/id
	/// REF(watcher) -> list(mask, handler).
	var/list/watchers
	/// REF(mob) -> TRUE for every living mob standing in this chunk, kept by publish_mob_move() and the mob's init and destroy. Held by REF text like the
	/// watchers, so a deleted mob never lingers; the AI packs read it to find who is near (living_in_chunk()). Filled by a scan when the chunk is made.
	var/list/living_refs

/// The chunk id for a location, or null off-map.
/proc/mob_chunk_id(atom/location)
	var/turf/T = get_turf(location)
	if(!T)
		return
	return MOB_CHUNK_NUMERIC_KEY(T.z, MOB_CHUNK_COORD(T.x), MOB_CHUNK_COORD(T.y))

/// The chunk entity for `id`, made on first use.
/proc/mob_chunk(id)
	var/datum/mob_chunk/C = GLOB.mob_chunks["[id]"]
	if(!C)
		C = new
		C.id = id
		GLOB.mob_chunks["[id]"] = C
		mob_chunk_scan(C)
	return C

/// Fills a new chunk's living_refs from the turfs it covers (the ids are MOB_CHUNK_NUMERIC_KEY(z, chunk_x, chunk_y)).
/proc/mob_chunk_scan(datum/mob_chunk/C)
	var/chunk_x = C.id % 256
	var/rest = (C.id - chunk_x) / 256
	var/chunk_y = rest % 256
	var/z = (rest - chunk_y) / 256
	if(z < 1 || z > world.maxz)
		return
	for(var/x in (chunk_x * CHUNK_SIZE + 1) to min(chunk_x * CHUNK_SIZE + CHUNK_SIZE, world.maxx))
		for(var/y in (chunk_y * CHUNK_SIZE + 1) to min(chunk_y * CHUNK_SIZE + CHUNK_SIZE, world.maxy))
			var/turf/T = locate(x, y, z)
			if(!T)
				continue
			for(var/mob/living/L as anything in turf_contents_of_type(T, /mob/living))
				LAZYSET(C.living_refs, REF(L), TRUE)

/// The living mobs standing in the chunk with id `id` (a fresh list; callers filter stat and deletion).
/proc/living_in_chunk(id)
	. = list()
	var/datum/mob_chunk/C = GLOB.mob_chunks["[id]"] || mob_chunk(id)
	for(var/key in C.living_refs)
		var/mob/living/L = locate(key)
		if(L && !QDELETED(L) && REF(L) == key)
			. += L

/// A living mob came into (`entered` TRUE) or left the chunk with id `id`: kept only for chunks that exist (a new chunk scans).
/proc/living_chunk_note(mob/living/L, id, entered)
	if(isnull(id))
		return
	var/datum/mob_chunk/C = GLOB.mob_chunks["[id]"]
	if(!C)
		return
	if(entered)
		LAZYSET(C.living_refs, REF(L), TRUE)
	else
		LAZYREMOVE(C.living_refs, REF(L))

/// Raises `bits` on chunk `id` if anything watches it.
/proc/mob_chunk_changed(id, bits)
	if(isnull(id))
		return
	var/datum/mob_chunk/C = GLOB.mob_chunks["[id]"]
	if(!C)
		return
	if(!length(C.watchers))
		GLOB.mob_chunks -= "[id]"
		spent(C)
		return
	for(var/key in C.watchers.Copy())
		var/list/watch = C.watchers[key]
		if(!watch || !(watch[1] & bits))
			continue
		var/datum/watcher = locate(key)
		if(!watcher || QDELETED(watcher) || REF(watcher) != key)
			C.watchers -= key
			continue
		call(watcher, watch[2])(C, bits)

/// Every chunk within `radius` tiles of `center`.
/proc/mob_chunks_around(turf/center, radius)
	. = list()
	if(!center)
		return
	for(var/chunk_x in MOB_CHUNK_COORD(max(center.x - radius, 1)) to MOB_CHUNK_COORD(min(center.x + radius, world.maxx)))
		for(var/chunk_y in MOB_CHUNK_COORD(max(center.y - radius, 1)) to MOB_CHUNK_COORD(min(center.y + radius, world.maxy)))
			. += mob_chunk(MOB_CHUNK_NUMERIC_KEY(center.z, chunk_x, chunk_y))

/// `watcher`.handler(chunk, bits) runs when `mask` is raised on any of `chunks`. Returns the chunks, for unwatch_mob_chunks().
/proc/watch_mob_chunks(datum/watcher, list/chunks, mask, handler)
	var/key = REF(watcher)
	for(var/datum/mob_chunk/C as anything in chunks)
		LAZYSET(C.watchers, key, list(mask, handler))
	if(mask & CHANGE_CHUNK_ANY_MOB)
		GLOB.mob_chunk_watches += length(chunks)
	if(mask & CHANGE_CHUNK_PLAYER)
		GLOB.player_chunk_watches += length(chunks)
	return chunks

/// Drops watches made by watch_mob_chunks(). Returns null, for `chunks = unwatch_mob_chunks(...)`.
/proc/unwatch_mob_chunks(datum/watcher, list/chunks, mask)
	var/key = REF(watcher)
	for(var/datum/mob_chunk/C as anything in chunks)
		LAZYREMOVE(C.watchers, key)
	if(mask & CHANGE_CHUNK_ANY_MOB)
		GLOB.mob_chunk_watches = max(GLOB.mob_chunk_watches - length(chunks), 0)
	if(mask & CHANGE_CHUNK_PLAYER)
		GLOB.player_chunk_watches = max(GLOB.player_chunk_watches - length(chunks), 0)
	return null

/// A mob appeared in or vanished from `location`'s chunk (Initialize, Destroy).
/proc/publish_mob_chunk(atom/location, entered = null)
	if(isliving(location) && !isnull(entered))
		living_chunk_note(location, mob_chunk_id(location), entered)
	if(GLOB.mob_chunk_watches)
		mob_chunk_changed(mob_chunk_id(location), CHANGE_CHUNK_ANY_MOB)

/// A player is in `T`'s chunk.
/proc/publish_player_chunk(turf/T)
	if(T)
		mob_chunk_changed(mob_chunk_id(T), CHANGE_CHUNK_PLAYER)

/**
 * /mob/Moved()'s one publish. The new chunk hears CHANGE_CHUNK_ANY_MOB (while anything watches
 * chunks) plus CHANGE_CHUNK_PLAYER for a player (while anything watches players). The old chunk
 * hears CHANGE_CHUNK_ANY_MOB only when the step crossed a chunk edge. Callers gate on the two
 * counters first.
 */
/proc/publish_mob_move(atom/old_loc, atom/movable/mover, player)
	var/bits = GLOB.mob_chunk_watches ? CHANGE_CHUNK_ANY_MOB : 0
	if(player && GLOB.player_chunk_watches)
		bits |= CHANGE_CHUNK_PLAYER
	if(!bits)
		return
	var/new_id = mob_chunk_id(mover)
	if(isliving(mover))
		var/old_living_id = mob_chunk_id(old_loc)
		if(old_living_id != new_id)
			living_chunk_note(mover, old_living_id, FALSE)
			living_chunk_note(mover, new_id, TRUE)
	mob_chunk_changed(new_id, bits)
	if(bits & CHANGE_CHUNK_ANY_MOB)
		var/old_id = mob_chunk_id(old_loc)
		if(old_id != new_id)
			mob_chunk_changed(old_id, CHANGE_CHUNK_ANY_MOB)

// ---------------------------------------------------------------- proximity gate

/// Something whose periodic work only matters with mobs (or players) nearby -- a radiation source,
/// a spawner, a haunting -- ends its step with `return sleep_until_mob_near(radius)` when nobody is
/// in range: it watches the chunks around it and restarts on its lane when a mob moves into one (proximity_woke(), periodic.dm).

/atom/movable/var/tmp/list/proximity_chunks
/atom/movable/var/tmp/proximity_mask = 0
/atom/movable/var/tmp/proximity_lane

/// TRUE when a living mob (a player, with `players_only`) is within `radius` tiles.
/atom/movable/proc/mob_near(radius, players_only = FALSE)
	var/turf/T = get_turf(src)
	if(!T)
		return FALSE
	for(var/mob/living/L in range(radius, T))
		if(!players_only || L.client)
			return TRUE
	return FALSE

/// Ends this step's periodic work until a mob (a player, with `players_only`) moves within reach of
/// `radius`. Returns PROCESS_KILL. `lane` is the periodic lane to restart on.
/atom/movable/proc/sleep_until_mob_near(radius, players_only = FALSE, lane = PERIODIC_SLOW)
	if(proximity_chunks)
		proximity_chunks = unwatch_mob_chunks(src, proximity_chunks, proximity_mask)
	var/turf/T = get_turf(src)
	if(!T)
		return PROCESS_KILL
	proximity_mask = players_only ? CHANGE_CHUNK_PLAYER : CHANGE_CHUNK_ANY_MOB
	proximity_lane = lane
	sleep_audit_join(src)
	proximity_chunks = watch_mob_chunks(src, mob_chunks_around(T, radius), proximity_mask, PROC_REF(proximity_woke))
	return PROCESS_KILL

/atom/movable/sleep_violation()
	if(proximity_chunks && om_task_periodic_running(src))
		return "watching for mobs while already running"
	return ..()
