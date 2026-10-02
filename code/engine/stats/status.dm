// Statuses over holds (doc/rewrite/final_api.html, section 5 "Statuses"; section 19 "E3, stats").
//
// A stat declared with `units =` is a status: its value is the intensity (the strongest hold's), its holds last `units` times the amount asked on the
// mob's biology clock, and its companion boolean ANY stat (STAT_<NAME>_IMMUNE, made by the same STAT line, contributed to by immune_to()) zeroes it
// while TRUE. The verbs below are the sugar the design names status_at_least/status_set/status_adjust/status_end/status_remaining/has_status; until
// the ~700 callers of the legacy /datum/proc/status_* family migrate (phase 3) these carry the `stat_` prefix, because an unqualified call inside a
// datum proc would resolve to the legacy proc of the same name. The renaming is one sed over the callers when they move.

/// The deciseconds one unit of status `def` lasts.
/proc/stat_status_unit_ds(datum/stat_def/def)
	return def.units || LIFE_CYCLE_DS

/// TRUE while the status's immunity holds on E (the companion stat is TRUE).
/proc/stat_status_immune(datum/E, datum/stat_def/def)
	var/datum/stat_def/immune = GLOB.stat_defs["[STAT_IMMUNE(def.id)]"]
	if(!immune)
		return FALSE
	return !!stat_value_now(E, immune)

/// Holds the status at least this long at this strength; never shortens or weakens. TRUE when a hold is in place.
/proc/stat_status_at_least(datum/E, stat_id, units, intensity = 1, source = SRC_STATUS)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def || !def.units)
		declare_report("stat_status_at_least([E?.type], [stat_id]): not a status stat (STAT(..., units = ...))")
		return null
	if(units <= 0)
		return null
	return hold(E, stat_id, intensity, source, lasts = units * stat_status_unit_ds(def), clock = HOLD_CLOCK_BIO)

/// Sets that source's hold to exactly this amount (hold_until: replaces value and deadline, may shorten); 0 units ends it.
/proc/stat_status_set(datum/E, stat_id, units, intensity = 1, source = SRC_STATUS)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def || !def.units)
		declare_report("stat_status_set([E?.type], [stat_id]): not a status stat (STAT(..., units = ...))")
		return null
	if(units <= 0)
		return release(E, stat_id, source)
	var/until = stat_clock_now(E, HOLD_CLOCK_BIO) + units * stat_status_unit_ds(def)
	return hold_until(E, stat_id, intensity, source, until, clock = HOLD_CLOCK_BIO)

/// Adds to (or cuts) that source's time; at or below zero ends it. With no hold yet a positive delta starts one.
/proc/stat_status_adjust(datum/E, stat_id, delta, source = SRC_STATUS)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def || !def.units || !isdatum(E))
		return null
	var/datum/stat_record/rec = E.rx?.stats
	var/list/row = rec ? stat_hold_find(rec, def.id, source, null) : null
	if(!row)
		return delta > 0 ? stat_status_at_least(E, stat_id, delta, 1, source) : null
	var/now = stat_clock_now(E, HOLD_CLOCK_BIO)
	var/until = max(row[H_EXPIRES], now) + delta * stat_status_unit_ds(def)
	if(until <= now)
		return release(E, stat_id, source)
	return hold_until(E, stat_id, row[H_VALUE], source, until, clock = HOLD_CLOCK_BIO)

/// Ends the status (source = SRC_ALL ends every source's hold).
/proc/stat_status_end(datum/E, stat_id, source = SRC_STATUS)
	return release(E, stat_id, source)

/// Units until the status lapses on its own (the longest hold), rounded up; 0 when none runs.
/proc/stat_status_remaining(datum/E, stat_id)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def || !def.units)
		return 0
	. = 0
	var/unit = stat_status_unit_ds(def)
	for(var/list/row as anything in E?.rx?.stats?.holds)
		if(row[H_STAT] != def.id || !row[H_EXPIRES])
			continue
		. = max(., ceil((row[H_EXPIRES] - stat_clock_now(E, row[H_CLOCK])) / unit))

/// TRUE while the status's value is above zero.
/proc/stat_has_status(datum/E, stat_id)
	var/datum/stat_def/def = stat_def_of(stat_id)
	if(!def)
		return FALSE
	var/value = stat_value(E, stat_id)
	return isnum(value) && value > 0
