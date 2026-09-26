// Timed and keyed wakes on the object-model core (doc/rewrite/object_model_core.md §4.11;
// roadmap S3). This is what the S2 SSreactor timers and DM-owned keys become: one scheduler.
//
// A datum that sleeps until a time or until some published fact changes arms:
//   OM_WAKE_AT(E, time)            one timer per entity (setting it again replaces it), on the
//                                  core deadline wheel; OM_WAKE_CANCEL(E) drops it
//   OM_KEY_ON(E, kind, id, mask)   a subscription to key (kind, id); returns the token that
//                                  OM_KEY_OFF(E, token) takes. OM_KEY_PUBLISH(kind, id, mask)
//                                  wakes every subscriber whose mask shares a bit
// and is called back through /datum/proc/om_woken(reason) with OM_WOKEN_TIMER and/or
// OM_WOKEN_KEY. Both ride /datum/om/behaviour/woken: a key is an OM entity (/datum/om_key)
// that its subscribers om_watch(), so a publish is one om_changed() and the core's lanes,
// budgets and coalescing apply. Handlers read current state; wakes can merge.
//
// The missed-wake audit (om_woken_audit(), run with the pipeline audit) asks each sampled
// subscriber's om_sleep_violation() whether it is asleep while it has work.

/datum/var/tmp/om_key_id = 0
GLOBAL_VAR_INIT(om_key_next_id, 0)
/// "kind:id" -> /datum/om_key, for keys with at least one subscriber.
GLOBAL_LIST_EMPTY(om_keys)
/// Every entity with the woken behaviour attached (the audit's sample space).
GLOBAL_LIST_EMPTY(om_woken_entities)

/// A key's id for datum `D` (assigned on first use; never reused).
/proc/om_key_id_of(datum/D)
	if(!D.om_key_id)
		D.om_key_id = ++GLOB.om_key_next_id
	return D.om_key_id

/// One published fact (kind, id): an OM entity its subscribers watch. Mask bit n of a
/// publish is channel bit n + 8 (the generic datum family), so a watch filters by mask.
/datum/om_key
	var/kind
	var/id

/// TRUE while anything watches `K` (a subscriber torn down with its entity leaves no watch).
/proc/om_key_live(datum/om_key/K)
	return length(K.om_rec?.watches_in) > 0

/proc/om_key_drop(datum/om_key/K)
	GLOB.om_keys -= "[K.kind]:[K.id]"
	qdel(K)

/proc/om_key_mask_bits(mask)
	return (mask & 0xFFFF) << 8

/proc/om_key_publish(kind, id, mask)
	var/datum/om_key/K = GLOB.om_keys["[kind]:[id]"]
	if(!K)
		return
	if(!om_key_live(K))
		om_key_drop(K)
		return
	om_changed(K, om_key_mask_bits(mask))

/proc/om_key_on(datum/E, kind, id, mask)
	if(!E || QDELETED(E) || isnull(id))
		return null
	var/key = "[kind]:[id]"
	var/datum/om_key/K = GLOB.om_keys[key]
	if(!K)
		K = new
		K.kind = kind
		K.id = id
		GLOB.om_keys[key] = K
	om_woken_attach(E)
	var/datum/om/rec/trec = om_rec_of(K)
	var/list/W = trec?.watches_in
	var/already = FALSE
	for(var/i in 1 to length(W) step 3)
		if(W[i] == E)
			already = TRUE
			W[i + 1] |= om_key_mask_bits(mask)
			om_recompute_listen(trec)
			break
	if(!already)
		om_watch(E, K, om_key_mask_bits(mask), /datum/om/behaviour/woken)
	return K

/proc/om_key_off(datum/E, datum/om_key/K)
	if(!istype(K) || !E)
		return
	var/datum/om/rec/trec = K.om_rec
	var/found = FALSE
	for(var/i in 1 to length(trec?.watches_in) step 3)
		if(trec.watches_in[i] == E)
			found = TRUE
			break
	if(!found)
		return
	om_unwatch(E, K, /datum/om/behaviour/woken)
	if(!om_key_live(K))
		om_key_drop(K)

/proc/om_wake_at(datum/E, time)
	if(!E || QDELETED(E))
		return FALSE
	om_woken_attach(E)
	return om_after(E, max(time - world.time, 0), /datum/om/behaviour/woken)

/proc/om_wake_cancel(datum/E)
	om_cancel_after(E, /datum/om/behaviour/woken)

/proc/om_wake_pending(datum/E)
	return om_deadline_pending(E, /datum/om/behaviour/woken)

/proc/om_woken_attach(datum/E)
	if(!om_attached(E, /datum/om/behaviour/woken))
		om_attach(E, /datum/om/behaviour/woken)

/// Called when a timer or a subscribed key fires. `reason`: OM_WOKEN_TIMER | OM_WOKEN_KEY.
/datum/proc/om_woken(reason)
	SHOULD_NOT_SLEEP(TRUE)
	return

/// For the audit: null while this sleeper's sleep condition holds, else why it should be awake.
/datum/proc/om_sleep_violation()
	SHOULD_NOT_SLEEP(TRUE)
	return null

/datum/om/behaviour/woken
	name = "woken"
	wake_on = CHANGE_RELATED

/datum/om/behaviour/woken/on_start(datum/E)
	GLOB.om_woken_entities[E] = TRUE

/datum/om/behaviour/woken/on_stop(datum/E)
	GLOB.om_woken_entities -= E

/datum/om/behaviour/woken/on_wake(datum/E, changes)
	if(QDELETED(E))
		return
	if(GLOB.om_woken_traced[E])
		GLOB.om_woken_traced[E]++
	E.om_woken(OM_WOKEN_KEY)

/datum/om/behaviour/woken/on_deadline(datum/E)
	if(QDELETED(E))
		return
	if(GLOB.om_woken_traced[E])
		GLOB.om_woken_traced[E]++
	E.om_woken(OM_WOKEN_TIMER)

/// Samples sleepers and asks each whether it sleeps through work. Returns the findings; with
/// `report`, a runtime in test builds (failing the run) and a log line on servers.
/proc/om_woken_audit(sample = 64, report = FALSE)
	var/list/findings = list()
	var/list/pool = GLOB.om_woken_entities
	var/count = length(pool)
	if(!count)
		return findings
	var/list/candidates = list()
	if(count <= sample)
		for(var/datum/D as anything in pool)
			candidates += D
	else
		for(var/i in 1 to sample)
			candidates += pool[rand(1, count)]
	for(var/datum/D as anything in candidates)
		if(!D || QDELETED(D))
			continue
		var/violation = D.om_sleep_violation()
		if(!violation)
			continue
		findings += "[D.type]: [violation]"
		if(!report)
			continue
#if defined(UNIT_TESTS) || defined(TESTING)
		stack_trace("OM_AUDIT: MISSED WAKE (woken) [D.type]: [violation]")
#else
		log_runtime("OM_AUDIT: MISSED WAKE (woken) [D.type]: [violation]")
#endif
	return findings

// ---------------------------------------------------------------- sleeping on keys; mob chunks

/// Live KEY_MOB_CHUNK any-mob subscriptions (om_sleep_on_keys()). Mob movement skips the turf
/// lookup and the publish while it is 0.
GLOBAL_VAR_INIT(om_mob_chunk_subscriptions, 0)
/// Live player chunk subscriptions (om_subscribe_player_chunks()). A player's move publishes
/// only while this is non-zero. A subscription dropped with its entity leaves it high, which
/// only costs publishes.
GLOBAL_VAR_INIT(om_player_chunk_subscriptions, 0)

/// Subscribes `D` to every (kind, id, mask) triple in the flat list `keys`. Returns the flat
/// list (token, kind, ...) that om_cancel_keys() takes when `D` wakes.
/proc/om_sleep_on_keys(datum/D, list/keys)
	. = list()
	for(var/i = 1; i <= length(keys); i += 3)
		var/kind = keys[i]
		. += om_key_on(D, kind, keys[i + 1], keys[i + 2])
		. += kind
		if(kind == KEY_MOB_CHUNK)
			GLOB.om_mob_chunk_subscriptions++

/// Drops the subscriptions om_sleep_on_keys() returned.
/proc/om_cancel_keys(datum/D, list/tokens)
	for(var/i = 1; i <= length(tokens); i += 2)
		om_key_off(D, tokens[i])
		if(tokens[i + 1] == KEY_MOB_CHUNK)
			GLOB.om_mob_chunk_subscriptions = max(GLOB.om_mob_chunk_subscriptions - 1, 0)

/// The mob-chunk key id for a location, or null off-map.
/proc/om_mob_chunk_id(atom/location)
	var/turf/T = get_turf(location)
	if(!T)
		return
	return MOB_CHUNK_NUMERIC_KEY(T.z, MOB_CHUNK_COORD(T.x), MOB_CHUNK_COORD(T.y))

/// A mob appeared in or vanished from `location`'s chunk (Initialize, Destroy).
/proc/om_publish_mob_chunk(atom/location)
	if(!GLOB.om_mob_chunk_subscriptions)
		return
	var/id = om_mob_chunk_id(location)
	if(!isnull(id))
		om_key_publish(KEY_MOB_CHUNK, id, KEY_CHUNK_ANY_MOB)

/// Subscribes `D` to players in every chunk within `radius` tiles of `center`. Returns the
/// tokens, for om_unsubscribe_player_chunks().
/proc/om_subscribe_player_chunks(datum/D, turf/center, radius)
	. = list()
	if(!center)
		return
	var/min_x = MOB_CHUNK_COORD(max(center.x - radius, 1))
	var/max_x = MOB_CHUNK_COORD(min(center.x + radius, world.maxx))
	var/min_y = MOB_CHUNK_COORD(max(center.y - radius, 1))
	var/max_y = MOB_CHUNK_COORD(min(center.y + radius, world.maxy))
	for(var/chunk_x in min_x to max_x)
		for(var/chunk_y in min_y to max_y)
			. += om_key_on(D, KEY_MOB_CHUNK, MOB_CHUNK_NUMERIC_KEY(center.z, chunk_x, chunk_y), KEY_CHUNK_PLAYER)
	GLOB.om_player_chunk_subscriptions += length(.)

/// Drops tokens from om_subscribe_player_chunks(). Returns null, for `tokens = om_unsubscribe_player_chunks(...)`.
/proc/om_unsubscribe_player_chunks(datum/D, list/tokens)
	for(var/datum/om_key/K as anything in tokens)
		om_key_off(D, K)
		GLOB.om_player_chunk_subscriptions = max(GLOB.om_player_chunk_subscriptions - 1, 0)
	return null

/// A player is in `T`'s chunk.
/proc/om_publish_player_chunk(turf/T)
	if(T)
		om_key_publish(KEY_MOB_CHUNK, MOB_CHUNK_NUMERIC_KEY(T.z, MOB_CHUNK_COORD(T.x), MOB_CHUNK_COORD(T.y)), KEY_CHUNK_PLAYER)

/**
 * /mob/Moved()'s one publish. The new chunk hears KEY_CHUNK_ANY_MOB (while anything sleeps on
 * it) plus KEY_CHUNK_PLAYER for a player (while anything listens for players). The old chunk
 * hears KEY_CHUNK_ANY_MOB only when the step crossed a chunk edge. Callers gate on the two
 * counters first.
 */
/proc/om_publish_mob_move(atom/old_loc, atom/movable/mover, player)
	var/mask = GLOB.om_mob_chunk_subscriptions ? KEY_CHUNK_ANY_MOB : 0
	if(player && GLOB.om_player_chunk_subscriptions)
		mask |= KEY_CHUNK_PLAYER
	if(!mask)
		return
	var/turf/old_turf = get_turf(old_loc)
	var/turf/new_turf = get_turf(mover)
	var/new_id = new_turf ? MOB_CHUNK_NUMERIC_KEY(new_turf.z, MOB_CHUNK_COORD(new_turf.x), MOB_CHUNK_COORD(new_turf.y)) : null
	if(!isnull(new_id))
		om_key_publish(KEY_MOB_CHUNK, new_id, mask)
	if(old_turf && (mask & KEY_CHUNK_ANY_MOB))
		var/old_id = MOB_CHUNK_NUMERIC_KEY(old_turf.z, MOB_CHUNK_COORD(old_turf.x), MOB_CHUNK_COORD(old_turf.y))
		if(old_id != new_id)
			om_key_publish(KEY_MOB_CHUNK, old_id, KEY_CHUNK_ANY_MOB)

// ---------------------------------------------------------------- tests

/// Test-only: datum -> om_woken() calls + 1 (so a traced datum is truthy).
GLOBAL_LIST_EMPTY(om_woken_traced)

/// Counts om_woken() deliveries for `D` from now on.
/proc/om_woken_trace(datum/D)
	if(!GLOB.om_woken_traced[D])
		GLOB.om_woken_traced[D] = 1

/proc/om_woken_traced_count(datum/D)
	var/n = GLOB.om_woken_traced[D]
	return n ? n - 1 : 0

/proc/om_woken_untrace(datum/D)
	GLOB.om_woken_traced -= D
