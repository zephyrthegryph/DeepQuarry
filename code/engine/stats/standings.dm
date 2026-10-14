// Keyed standings: standing() / standing_toward() (doc/rewrite/final_api.html, section 5 "Standings"; doc/rewrite/ai_packs.md A3).
//
//	standing(E, toward = target, value = STANDING_HOSTILE, source = grudge, lasts = 5 MINUTES, priority = 60)
//	standing_toward(E, target)                                  // what E's rows add up to toward `target`: a number, lower is more hostile
//
// A standing is what an entity thinks of a subject, held the way a stat is held: a row in the entity's hold store (store.dm) with the subject in
// the row's H_KEY column and the standing pseudo-stat HOLD_STANDING in H_STAT, so it is source-attributed, released when its source is deleted (the
// row is always bound to it), expires on its own (lasts, deciseconds of the world clock), and one source holds one row per subject: stancing the
// same (source, subject) again replaces its value, priority and deadline. The existing hold machinery does all of that; no second store, no
// second expiry timer, no second teardown. A standing row is invisible to the stat recompute (it matches no stat id).
//
// Subjects: a datum (a mob), a faction key (text), STANDING_PLAYERS (any mob a player controls) or STANDING_ANY (everything).
//
// standing_toward(E, subject) reads the rows of E that apply to the subject, in this order of specificity: rows toward the subject itself, rows toward
// its faction (its `faction` var, standing_faction_of()), rows toward STANDING_PLAYERS when a player controls it, rows toward STANDING_ANY. All of
// them compete in one pool, and the order of the contest is explicit:
//   1. the highest priority wins;
//   2. on equal priority the LOWEST value wins (the most hostile);
//   3. on equal priority and value the more specific row wins (only the reported source can differ).
// No row applies: the `default` (STANDING_NEUTRAL). So a base standing from a faction table at priority 0 is overridden by any row of higher priority,
// whatever it is toward, and between two rows of the same priority hostility beats friendship.
//
// Cache: the result is cached per (E, subject) in E's stat record and read back while the subject's faction and player state are what they were.
// ANY write to a standing row of E (placed, replaced, released, expired, source deleted) drops the whole cache of E and publishes
// /datum/notice/standing_changed on E, so a listener (a pack, a brain) re-reads its classifications. GLOB.forms_trace logs the invalidations.
//
// Hold cost: an entity with standing rows has a hold list, so the stat recompute takes its general path (stat_compute_fast needs no holds) for it.

/datum/stat_record
	/// Subject key -> list(value or null for "no row", faction, player): the standing_toward() answers since the last row change.
	var/list/standing_cache

/// How the cache fared, for tests and the trace.
GLOBAL_VAR_INIT(standing_cache_hits, 0)
GLOBAL_VAR_INIT(standing_cache_misses, 0)
GLOBAL_VAR_INIT(standing_cache_drops, 0)

/// The H_KEY text of a subject, or null when it names none (a deleted datum cannot be given a row, an empty faction names nothing). `live` FALSE reads the
/// key of a datum that is going away too, for the lookups and releases that name a subject whatever its state.
/proc/standing_key(subject, live = TRUE)
	if(isdatum(subject))
		var/datum/D = subject
		if(live && QDELETED(D))
			return null
		return "d:[REF(D)]"
	if(istext(subject))
		if(subject == STANDING_PLAYERS || subject == STANDING_ANY)
			return subject
		return length(subject) ? "f:[subject]" : null
	return null

/// The faction key a subject belongs to, or null. The default reads the subject's `faction` var when it is a text; a type whose faction is something
/// else overrides it.
/datum/proc/standing_faction()
	if(!("faction" in vars))
		return null
	var/faction = vars["faction"]
	return (istext(faction) && length(faction)) ? faction : null

/// TRUE when a player controls the subject now (the mobs a STANDING_PLAYERS row applies to). A mob overrides nothing: its client is the answer.
/datum/proc/standing_player()
	return FALSE

/mob/standing_player()
	return !!client

/proc/standing_faction_of(subject)
	if(!isdatum(subject))
		return null
	var/datum/D = subject
	return D.standing_faction()

/proc/standing_is_player(subject)
	if(!isdatum(subject))
		return FALSE
	var/datum/D = subject
	return D.standing_player()

// ---- placing and releasing ----

/// standing(E, toward = subject, value, source = S, lasts = T, priority = P, reason = text): the standings form of standing(). `value` is a number (lower is
/// more hostile); `lasts` deciseconds of the world clock, omitted for a standing that lasts until released or until its source is deleted. TRUE when the row
/// is placed, null (reported) when it is refused.
/proc/standing(datum/E, toward, value, source, lasts, priority, reason)
	OP_PURE_GUARD("a standing on [E?.type] was placed")
	if(!isdatum(E) || QDELETED(E))
		declare_report("standing(): the holder is deleted or not a datum")
		return null
	var/key = standing_key(toward)
	if(isnull(key))
		declare_report("standing([E.type]): the subject must be a live datum, a faction key (text), STANDING_PLAYERS or STANDING_ANY, got [isnull(toward) ? "null" : "[toward]"]")
		return null
	if(!isnum(value))
		declare_report("standing([E.type], [key]): the value must be a number (STANDING_HOSTILE .. STANDING_ALLY), got [isnull(value) ? "null" : "[value]"]")
		return null
	if(!source_is_valid(source))
		declare_report("standing([E.type], [key]): the source must be a live datum or a SOURCE_DEF id, got [isnull(source) ? "null" : "[source]"]")
		return null
	if(!isnull(lasts) && (!isnum(lasts) || lasts <= 0))
		declare_report("standing([E.type], [key]): lasts must be a positive number of deciseconds, got [lasts]")
		return null
	if(isnull(priority))
		priority = PRIORITY_DEFAULT
	var/datum/stat_record/rec = stat_record_of(E)
	var/expires = lasts ? stat_clock_now(E, HOLD_CLOCK_WORLD) + lasts : 0
	var/list/row = stat_hold_find(rec, HOLD_STANDING, source, key)
	if(row)
		row[H_VALUE] = value
		row[H_EXPIRES] = expires
		row[H_PRIORITY] = priority
		row[H_REASON] = reason || row[H_REASON]
	else
		row = list(HOLD_STANDING, source, value, expires, priority, 0, HOLD_CLOCK_WORLD, reason, ++GLOB.stat_hold_serial, key, null)
		rec.holds += list(row)
		if(isdatum(source))
			var/datum/stat_record/src_rec = stat_record_of(source)
			LAZYOR(src_rec.held_on, E)
	stat_expiry_reschedule(E)
	standing_rows_changed(E, key)
	return TRUE

/// Releases `source`'s standing toward `toward` on E (SRC_ALL: every source's). The number of rows released.
/proc/unstanding(datum/E, toward, source)
	OP_PURE_GUARD("a standing on [E?.type] was released")
	var/key = standing_key(toward, FALSE)
	var/datum/stat_record/rec = isdatum(E) ? E.rx?.stats : null
	if(isnull(key) || !rec?.holds)
		return 0
	var/list/gone = list()
	for(var/list/row as anything in rec.holds)
		if(row[H_STAT] == HOLD_STANDING && row[H_KEY] == key && (source == SRC_ALL || row[H_SOURCE] == source))
			gone += list(row)
	for(var/list/row as anything in gone)
		stat_hold_remove(E, rec, row)
	if(length(gone))
		stat_expiry_reschedule(E)
	return length(gone)

/// A standing row of E went (the hold store removed one): called by stat_hold_remove().
/proc/standing_row_removed(datum/E, list/row)
	standing_rows_changed(E, row[H_KEY])

/// A standing row of E changed: its cache is dropped and standing_changed is published.
/proc/standing_rows_changed(datum/E, key)
	var/datum/stat_record/rec = E?.rx?.stats
	if(rec?.standing_cache)
		GLOB.standing_cache_drops++
		forms_trace("standing", "[E.type]: a row toward [key] changed; [length(rec.standing_cache)] cached answer(s) dropped")
		rec.standing_cache = null
	else
		forms_trace("standing", "[E.type]: a row toward [key] changed; nothing cached")
	PUBLISH(E, standing_change, key)

// ---- reading ----

/// What E's rows add up to toward `subject`: a number (lower is more hostile), or `default` when no row applies.
/proc/standing_toward(datum/E, subject, default = STANDING_NEUTRAL)
	if(!isdatum(E))
		return default
	var/datum/stat_record/rec = E.rx?.stats
	if(!rec?.holds)
		return default
	var/key = standing_key(subject, FALSE)
	var/faction = standing_faction_of(subject)
	var/player = standing_is_player(subject)
	var/cache_key = key
	if(cache_key)
		var/list/hit = rec.standing_cache?[cache_key]
		if(hit && hit[2] == faction && hit[3] == player)
			GLOB.standing_cache_hits++
			return isnull(hit[1]) ? default : hit[1]
	GLOB.standing_cache_misses++
	var/list/winner = standing_resolve(rec, key, faction, player)
	var/value = winner ? winner[H_VALUE] : null
	if(cache_key)
		LAZYSET(rec.standing_cache, cache_key, list(value, faction, player))
	return isnull(value) ? default : value

/// The winning row of E's rows toward a subject (the contest in the file header), or null. The row is the store's: read it, never write it.
/proc/standing_resolve(datum/stat_record/rec, key, faction, player)
	var/list/candidates = list()
	if(key)
		candidates += key
	if(faction)
		candidates += "f:[faction]"
	if(player)
		candidates += STANDING_PLAYERS
	candidates += STANDING_ANY
	var/list/best = null
	var/best_tier = 0
	for(var/list/row as anything in rec.holds)
		if(row[H_STAT] != HOLD_STANDING)
			continue
		var/tier = candidates.Find(row[H_KEY])
		if(!tier)
			continue
		if(!best)
			best = row
			best_tier = tier
			continue
		if(row[H_PRIORITY] > best[H_PRIORITY])
			best = row
			best_tier = tier
		else if(row[H_PRIORITY] == best[H_PRIORITY])
			if(row[H_VALUE] < best[H_VALUE] || (row[H_VALUE] == best[H_VALUE] && tier < best_tier))
				best = row
				best_tier = tier
	return best

/// The source of the row that decides standing_toward(E, subject), or null when none does. For explanations and the trace.
/proc/standing_decided_by(datum/E, subject)
	var/datum/stat_record/rec = isdatum(E) ? E.rx?.stats : null
	if(!rec?.holds)
		return null
	var/list/winner = standing_resolve(rec, standing_key(subject, FALSE), standing_faction_of(subject), standing_is_player(subject))
	return winner ? winner[H_SOURCE] : null

/// E's standing rows as text, one per line (a debug listing).
/proc/standing_explain(datum/E)
	var/list/lines = list()
	for(var/list/row as anything in E?.rx?.stats?.holds)
		if(row[H_STAT] == HOLD_STANDING)
			lines += "[row[H_KEY]] = [row[H_VALUE]] (priority [row[H_PRIORITY]], source [row[H_SOURCE]][row[H_EXPIRES] ? ", until [row[H_EXPIRES]]" : ""])"
	return jointext(lines, "\n")
