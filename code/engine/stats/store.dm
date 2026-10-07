// Holds: runtime contributions to a stat (doc/rewrite/final_api.html, section 5 "Holds: runtime contributions", "Sources", "Clock and units";
// section 19 "E3, stats").
//
//	hold(E, STAT_X, value, source, lasts =, priority =, clock =, reason =, outlives_source =)   hold_until(E, STAT_X, value, source, until =, ...)
//	hold_override(E, STAT_X, value, source, priority =)   release(E, STAT_X, source)   release_all(E, source)
//	held_by(E, STAT_X)   held_by_source(E, STAT_X, source)   hold_left(E, STAT_X, source)
//
// A hold is a row in the entity's stat record: (stat, source, value, deadline, priority, flags, clock, reason, serial). The source is required: a
// datum or a SOURCE_DEF flyweight (SRC_*), and null or text is an error, so no hold is unreleasable. One source holds once per stat; holding again
// follows the stat's reapply rule. A hold on a boolean stat takes no value: on an ALL stat it is a veto, on an ANY stat a force; the other direction
// can never change anything and is refused. A hold is released when its datum source dies (stat_sources_teardown from the destroy transaction), timed or not, unless it
// was placed with outlives_source = TRUE (a stun from a projectile that deleted itself on hit still lasts its four seconds).
//
// The recompute is inline (recompute.dm): when hold() returns, the stat, and the stats that read it on the entity, hold their settled values.
//
// The hold store here is the stat layer's own rows, of the contribution store's shape (stat, source, value, expiry, key). The legacy store
// (code/datums/om/contribution.dm) stays authoritative for its own EFFECT_* ids until the callers of om_apply and om_hold migrate (phase 3 and
// after); a status or stat declared with STAT lives here.

/// Everything the stat layer keeps for one entity, in its reaction state (allocated on the first hold or the first init).
/datum/stat_record
	/// The hold rows, oldest first.
	var/list/holds
	/// stat id ("[id]") -> the value of a virtual stat (a stat with no var of its own).
	var/list/virtual
	/// stat id ("[id]") -> TRUE while the stat waits in the marked queue.
	var/list/marked
	/// A stat's map-edited constant: "[id]" -> the value the var held when the entity initialized, when it differed from the type's.
	var/list/constants
	/// TRUE once the entity's stats have been computed silently at init.
	var/inited = FALSE
	/// contributes_to entries: "[serial]" -> the entity currently holding this entity's contribution.
	var/list/ct_targets
	/// The entities holding rows that name this datum as their source (so its deletion can release them).
	var/list/held_on
	/// Hop readers naming this datum through a single-valued relation: rel var -> the readers (the reverse of what the readers' relation vars name).
	var/list/hop_in
	/// What this datum's own hop relations name now: rel var -> target, so a change finds the list to leave.
	var/list/hop_targets

/datum/rx_state
	/// The stat layer's record, or null.
	var/datum/stat_record/stats

/// D's stat record, made when first needed.
/proc/stat_record_of(datum/D)
	RETURN_TYPE(/datum/stat_record)
	var/datum/rx_state/rx = rx_of(D)
	if(!rx.stats)
		rx.stats = new // ALLOW(ownership): a bookkeeping record the framework owns
	return rx.stats

GLOBAL_VAR_INIT(stat_hold_serial, 0)
GLOBAL_VAR(stat_dead_source) // never set: a hold whose datum source is gone keeps null

/// The time on `clock` for entity E: the scheduler's for WORLD and OWN, the entity's biological clock for BIO. Deciseconds.
/proc/stat_clock_now(datum/E, clock)
	if(clock == HOLD_CLOCK_BIO)
		return clock_now(E, CLOCK_BIO)
	return om_time_of(E)

// ---- validation ----

/// Why a hold cannot be placed, as a report; null when it can. Pure.
/proc/stat_hold_refusal(datum/E, datum/stat_def/def, source, value, lasts, clock, override, key)
	if(!isdatum(E) || QDELETED(E))
		return "the holder is deleted or not a datum"
	if(!def)
		return "the stat is not declared"
	if(!stat_declared_on(E.type, def))
		return "[E.type] does not declare stat [def.name]"
	if(!source_is_valid(source))
		return "the source must be a live datum or a SOURCE_DEF id, got [isnull(source) ? "null" : "[source]"]"
	if(!isnull(lasts) && (!isnum(lasts) || lasts <= 0))
		return "lasts must be a positive number of deciseconds, got [lasts]"
	if((def.name == "clock_rate" || def.name == "clock_rate_bio") && clock != HOLD_CLOCK_WORLD)
		return "a hold on [def.name] takes CLOCK_WORLD only: a stasis hold on the clock it feeds would stretch its own duration"
	if(def.keyed)
		if(isnull(key))
			return "a hold on the SUM_PER_KEY stat [def.name] needs a key"
		if(!isnum(value))
			return "a hold on the SUM_PER_KEY stat [def.name] needs a number, got [isnull(value) ? "null" : "[value]"]"
		if(override)
			return "a SUM_PER_KEY stat has no override: hold or release a key"
	else if(!isnull(key))
		return "key = is for a SUM_PER_KEY stat; [def.name] is [def.rule]"
	if(stat_rule_is_boolean(def.rule) && !isnull(value))
		var/forcing = stat_forcing_value(def)
		if(!!value != !!forcing)
			return "a hold on the [def.rule] stat [def.name] forces [forcing ? "TRUE" : "FALSE"]; holding the other way can never change anything"
	if(!stat_rule_is_boolean(def.rule) && isnull(value) && !override)
		return "a hold on the [def.rule] stat [def.name] needs a value"
	if(def.schema && !isnull(value) && !stat_rule_is_boolean(def.rule))
		var/list/checked = schema_check(def.schema, value)
		if(checked[1] == SCHEMA_REJECT || checked[2])
			return "the value [value] does not satisfy the schema of [def.name] ([checked[2]])"
	return null

// ---- the verbs ----

/// A runtime contribution to a stat, kept by `source` (a SUM_PER_KEY stat also takes `key`: the hold adds `value` to that key's total, one hold per (source, key)); `lasts` is a duration (deciseconds) on `clock`. Returns TRUE when it is placed, or null
/// with the reason reported when it is refused.
/proc/hold(datum/E, stat, value, source, lasts, priority = PRIORITY_DEFAULT, clock, reason, outlives_source = FALSE, key = null)
	return stat_hold_place(E, stat, value, source, lasts, null, priority, clock, reason, outlives_source, FALSE, FALSE, key)

/// A hold that ends at an exact deadline on `clock` and, unlike hold(), replaces the value and may shorten: what status_set and status_adjust use.
/proc/hold_until(datum/E, stat, value, source, until, priority = PRIORITY_DEFAULT, clock, reason, outlives_source = FALSE)
	return stat_hold_place(E, stat, value, source, null, until, priority, clock, reason, outlives_source, FALSE, TRUE)

/// Replaces the composed value of a stat until released (not on a SET stat). An admin's VV edit of a stat is one of these, sourced SRC_VV.
/proc/hold_override(datum/E, stat, value, source, priority = PRIORITY_ADMIN)
	return stat_hold_place(E, stat, value, source, null, null, priority, HOLD_CLOCK_OWN, null, FALSE, TRUE, FALSE)

/// The one place a hold is placed. `exact` is hold_until's replace-and-may-shorten; `override` the replace-the-composed-value flag.
/proc/stat_hold_place(datum/E, stat, value, source, lasts, until, priority, clock, reason, outlives_source, override, exact, key = null)
	OP_PURE_GUARD("a hold on [E?.type] was placed")
	var/datum/stat_def/def = stat_def_of(stat)
	if(isnull(clock))
		clock = HOLD_CLOCK_OWN
	var/problem = stat_hold_refusal(E, def, source, value, lasts, clock, override, key)
	if(!problem && override && def.rule == STAT_RULE_SET)
		problem = "a SET stat has no override: grant or revoke instead"
	if(problem)
		declare_report("hold([E?.type], [def ? def.name : stat]): [problem]")
		return null
	// A status's immunity refuses a new hold (a hold already running keeps its clock while the immunity lasts).
	if(def.units && stat_status_immune(E, def))
		return null
	if(isnull(value) && stat_rule_is_boolean(def.rule))
		value = stat_forcing_value(def)
	var/datum/stat_record/rec = stat_record_of(E)
	var/now = stat_clock_now(E, clock)
	var/expires = 0
	if(!isnull(until))
		expires = until
	else if(lasts)
		expires = now + lasts
	var/flags = (outlives_source ? HF_OUTLIVES : 0) | (override ? HF_OVERRIDE : 0)
	var/list/row = stat_hold_find(rec, def.id, source, key)
	if(row && !override == !(row[H_FLAGS] & HF_OVERRIDE))
		stat_hold_reapply(E, def, row, value, expires, now, lasts, exact, priority, reason, flags)
	else if(row)
		// The same (stat, source) placed again with the other override flag: the one row is replaced outright, never a second row beside it that
		// release() might leave behind.
		log_world("STAT: hold on [E.type] [def.name] from [source] changed override [!!(row[H_FLAGS] & HF_OVERRIDE)] -> [!!override]: the existing row was replaced")
		row[H_VALUE] = value
		row[H_EXPIRES] = expires
		row[H_PRIORITY] = priority
		row[H_FLAGS] = flags
		row[H_CLOCK] = clock
		row[H_REASON] = reason || row[H_REASON]
	else
		row = list(def.id, source, value, expires, priority, flags, clock, reason, ++GLOB.stat_hold_serial, key, null)
		rec.holds += list(row)
		if(isdatum(source))
			var/datum/stat_record/src_rec = stat_record_of(source)
			LAZYOR(src_rec.held_on, E)
	if(expires)
		stat_expiry_reschedule(E)
	TEST_REC_DELTA(E, "hold:[def.name]", null, value)
	stat_settle_def(E, def)
	return TRUE

/// Re-applying from the same source follows the stat's reapply rule: REAPPLY_MAX keeps the stronger value for the rule and the later expiry (never
/// shortens), REAPPLY_EXTEND takes the new value and adds the new duration to the time remaining, REAPPLY_REPLACE takes the new value and expiry.
/// An exact hold (hold_until) always replaces both.
/proc/stat_hold_reapply(datum/E, datum/stat_def/def, list/row, value, expires, now, lasts, exact, priority, reason, flags)
	var/old_expires = row[H_EXPIRES]
	if(exact || def.reapply == REAPPLY_REPLACE)
		row[H_VALUE] = value
		row[H_EXPIRES] = expires
	else if(def.reapply == REAPPLY_EXTEND)
		row[H_VALUE] = value
		if(lasts)
			row[H_EXPIRES] = (old_expires ? max(old_expires, now) : now) + lasts
		else
			row[H_EXPIRES] = old_expires
	else
		row[H_VALUE] = stat_stronger(def, row[H_VALUE], value)
		if(!old_expires)
			row[H_EXPIRES] = 0 // a hold with no deadline stays one
		else if(!expires)
			row[H_EXPIRES] = 0 // an untimed re-hold outlasts any deadline
		else
			row[H_EXPIRES] = max(old_expires, expires)
	row[H_PRIORITY] = priority
	row[H_REASON] = reason || row[H_REASON]
	row[H_FLAGS] = flags

/// The stronger of two values for the stat's rule: the larger for MAX, SUM, PRODUCT and the boolean forces, the smaller for MIN, else the new one.
/proc/stat_stronger(datum/stat_def/def, old_value, new_value)
	switch(def.rule)
		if(STAT_RULE_MAX, STAT_RULE_SUM, STAT_RULE_PRODUCT, STAT_RULE_ANY, STAT_RULE_MASK_OR)
			return (isnum(old_value) && isnum(new_value)) ? max(old_value, new_value) : new_value
		if(STAT_RULE_MIN)
			return (isnum(old_value) && isnum(new_value)) ? min(old_value, new_value) : new_value
	return new_value

/// The row of (stat, source, key) in the record, or null.
/proc/stat_hold_find(datum/stat_record/rec, stat_id, source, key)
	for(var/list/row as anything in rec.holds)
		if(row[H_STAT] == stat_id && row[H_SOURCE] == source && row[H_KEY] == key)
			return row
	return null

/// Releases `source`'s hold on a stat (SRC_ALL drops every source's); on a SUM_PER_KEY stat `key` limits it to that key (null: every key of the source). TRUE when something was released.
/proc/release(datum/E, stat, source, key = null)
	OP_PURE_GUARD("a hold on [E?.type] was released")
	var/datum/stat_def/def = stat_def_of(stat)
	if(!isdatum(E) || !def)
		return FALSE
	var/datum/stat_record/rec = E.rx?.stats
	if(!rec?.holds)
		return FALSE
	var/removed = FALSE
	for(var/list/row as anything in rec.holds.Copy())
		if(row[H_STAT] != def.id || (def.keyed ? (!isnull(key) && row[H_KEY] != key) : row[H_KEY]))
			continue
		if(source == SRC_ALL || row[H_SOURCE] == source)
			stat_hold_remove(E, rec, row)
			removed = TRUE
	if(removed)
		stat_expiry_reschedule(E)
		stat_settle_def(E, def)
	return removed

/// Releases everything one source holds on E. A source holding more than HOLD_RELEASE_BATCH holds releases in slices (stat_release_slice, phase G).
/proc/release_all(datum/E, source)
	var/datum/stat_record/rec = E?.rx?.stats
	if(!rec?.holds)
		return 0
	var/list/mine = list()
	for(var/list/row as anything in rec.holds)
		if(row[H_SOURCE] == source)
			mine += list(row)
	if(!length(mine))
		return 0
	var/list/to_release = mine
	if(length(mine) > HOLD_RELEASE_BATCH)
		to_release = mine.Copy(1, HOLD_RELEASE_BATCH + 1)
		stat_release_queue_add(E, source)
	return stat_release_rows(E, rec, to_release)

/// Removes rows and settles each stat they touched once.
/proc/stat_release_rows(datum/E, datum/stat_record/rec, list/rows)
	var/list/touched = list()
	for(var/list/row as anything in rows)
		var/datum/stat_def/def = stat_def_of(row[H_STAT])
		if(def && !(def in touched))
			touched += def
		stat_hold_remove(E, rec, row)
	stat_expiry_reschedule(E)
	stat_settle(E, touched)
	return length(rows)

GLOBAL_LIST_EMPTY(stat_release_queue) // list(entity, source) rows waiting for their next slice

/proc/stat_release_queue_add(datum/E, source)
	for(var/list/pending as anything in GLOB.stat_release_queue)
		if(pending[1] == E && pending[2] == source)
			return
	GLOB.stat_release_queue += list(list(E, source))

/// One slice of the releases a big source left behind: HOLD_RELEASE_BATCH rows per entity. Phase G runs it; the recompute it marks runs at the next
/// marked drain. The holds not yet released still apply until their slice runs. Returns how many rows it released.
/proc/stat_release_slice()
	. = 0
	var/list/pending = GLOB.stat_release_queue
	GLOB.stat_release_queue = list()
	for(var/list/entry as anything in pending)
		var/datum/E = entry[1]
		var/source = entry[2]
		if(QDELETED(E))
			continue
		var/datum/stat_record/rec = E.rx?.stats
		if(!rec?.holds)
			continue
		var/list/mine = list()
		for(var/list/row as anything in rec.holds)
			if(row[H_SOURCE] == source)
				mine += list(row)
		if(!length(mine))
			continue
		var/list/slice = mine
		if(length(mine) > HOLD_RELEASE_BATCH)
			slice = mine.Copy(1, HOLD_RELEASE_BATCH + 1)
			GLOB.stat_release_queue += list(entry)
		. += stat_release_rows_marked(E, rec, slice)

/// stat_release_rows() for a slice: the stats it touches are marked for the next marked drain instead of recomputed inline.
/proc/stat_release_rows_marked(datum/E, datum/stat_record/rec, list/rows)
	var/list/touched = list()
	for(var/list/row as anything in rows)
		var/datum/stat_def/def = stat_def_of(row[H_STAT])
		if(def && !(def in touched))
			touched += def
		stat_hold_remove(E, rec, row)
	stat_expiry_reschedule(E)
	for(var/datum/stat_def/def as anything in touched)
		stat_mark(E, def)
	return length(rows)

/// Takes one row out of the record, and its source's index of where it holds.
/proc/stat_hold_remove(datum/E, datum/stat_record/rec, list/row)
	rec.holds -= list(row)
	if(!length(rec.holds))
		rec.holds = null
	var/source = row[H_SOURCE]
	if(isdatum(source))
		var/datum/src_datum = source
		var/datum/stat_record/src_rec = src_datum.rx?.stats
		if(src_rec?.held_on)
			var/still = FALSE
			for(var/list/other as anything in rec.holds)
				if(other[H_SOURCE] == source)
					still = TRUE
					break
			if(!still)
				src_rec.held_on -= E
				if(!length(src_rec.held_on))
					src_rec.held_on = null
	if(row[H_STAT] == HOLD_STANDING)
		standing_row_removed(E, row) // a standing row: the entity's cached standings are stale (standings.dm)

/// The sources holding a stat: a fresh list, safe to hold while releasing.
/proc/held_by(datum/E, stat)
	. = list()
	var/datum/stat_def/def = stat_def_of(stat)
	for(var/list/row as anything in E?.rx?.stats?.holds)
		if(def && row[H_STAT] == def.id && !isnull(row[H_SOURCE]))
			. |= list(row[H_SOURCE])

/// TRUE if `source` holds the stat. Allocates nothing.
/proc/held_by_source(datum/E, stat, source)
	READS_FROM(E)
	var/datum/stat_def/def = stat_def_of(stat)
	if(!def)
		return FALSE
	for(var/list/row as anything in E?.rx?.stats?.holds)
		if(row[H_STAT] == def.id && row[H_SOURCE] == source)
			return TRUE
	return FALSE

/// Time left on a timed hold, in deciseconds of the hold's clock (null: no such hold, 0: it has no deadline).
/proc/hold_left(datum/E, stat, source)
	READS_FROM(E)
	var/datum/stat_def/def = stat_def_of(stat)
	if(!def)
		return null
	var/datum/stat_record/rec = E?.rx?.stats
	var/list/row = rec ? stat_hold_find(rec, def.id, source, null) : null
	if(!row)
		return null
	if(!row[H_EXPIRES])
		return 0
	return max(row[H_EXPIRES] - stat_clock_now(E, row[H_CLOCK]), 0)

// ---- expiry ----

/// The entity's next deadline is one timer per clock. Arms it for the earliest hold that has one.
/proc/stat_expiry_reschedule(datum/E)
	var/datum/stat_record/rec = E.rx?.stats
	var/list/earliest = list() // clock -> remaining
	for(var/list/row as anything in rec?.holds)
		if(!row[H_EXPIRES])
			continue
		var/clock = row[H_CLOCK]
		var/remaining = max(row[H_EXPIRES] - stat_clock_now(E, clock), 1)
		if(isnull(earliest["[clock]"]) || remaining < earliest["[clock]"])
			earliest["[clock]"] = remaining
	for(var/clock in list(HOLD_CLOCK_WORLD, HOLD_CLOCK_OWN, HOLD_CLOCK_BIO))
		var/key = "stat_expiry:[clock]"
		var/remaining = earliest["[clock]"]
		if(isnull(remaining))
			cancel_after(E, key)
		else
			after(E, remaining, GLOBAL_PROC_REF(stat_expire), key = key, clock = (clock == HOLD_CLOCK_WORLD ? CLOCK_WORLD : CLOCK_OWN), with = list(E, clock), keeps_dead = TRUE)

/// A deadline fired: every hold of that clock that is due ends, and its stats settle.
/proc/stat_expire(datum/E, clock)
	if(!E || QDELETED(E))
		return
	var/datum/stat_record/rec = E.rx?.stats
	if(!rec?.holds)
		return
	var/now = stat_clock_now(E, clock)
	var/list/due = list()
	for(var/list/row as anything in rec.holds)
		if(row[H_CLOCK] == clock && row[H_EXPIRES] && row[H_EXPIRES] <= now)
			due += list(row)
	if(length(due))
		stat_release_rows(E, rec, due)
	else
		stat_expiry_reschedule(E)

// ---- teardown ----

/// The destroy transaction's call for a dying datum, as a source and as a holder. As a source: every hold it keeps on any
/// entity ends, unless it was placed with outlives_source = TRUE (its source is then forgotten). As a holder: its rows go, and the sources' indexes forget it.
/proc/stat_sources_teardown(datum/D)
	var/datum/stat_record/rec = D.rx?.stats
	if(!rec)
		return
	for(var/datum/target as anything in rec.held_on?.Copy())
		if(QDELETED(target))
			continue
		var/datum/stat_record/trec = target.rx?.stats
		if(!trec?.holds)
			continue
		var/list/gone = list()
		for(var/list/row as anything in trec.holds)
			if(row[H_SOURCE] != D)
				continue
			if(!(row[H_FLAGS] & HF_OUTLIVES))
				gone += list(row)
			else
				row[H_SOURCE] = null // outlives_source = TRUE: it runs its course (or stays, if untimed), with nothing to release it by
				log_world("STAT: hold on [target.type] [row[H_STAT]] outlived its source [D.type] (outlives_source)")
		if(length(gone))
			stat_release_rows(target, trec, gone)
	rec.held_on = null
	stat_hop_teardown(D, rec)
	// As a holder.
	for(var/list/row as anything in rec.holds)
		var/source = row[H_SOURCE]
		if(isdatum(source))
			var/datum/src_datum = source
			var/datum/stat_record/src_rec = src_datum.rx?.stats
			if(src_rec?.held_on)
				src_rec.held_on -= D
	rec.holds = null
	// The contributes_to rows this entity placed on other entities leave with it (their source is this datum, released above); forget the targets.
	rec.ct_targets = null
