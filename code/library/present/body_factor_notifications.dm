/// recompute_factors() rebuilt D's factors from `before` to `after` (either may be null: every factor at
/// baseline): mark the entities that read a factor that state_changed.
/proc/derived_factors_recomputed(datum/D, list/before, list/after)
	var/datum/derived_table/T = GLOB.derived_tables[D.type]
	if(!T || !T.factor_ids) // 0 marks a type with no table: ?. does not see through it
		return
	var/mask = 0
	for(var/i in 1 to length(T.factor_ids))
		var/id = T.factor_ids[i]
		var/was = before ? before[id] : body_factor_baseline(id)
		var/now = after ? after[id] : body_factor_baseline(id)
		if(was != now)
			mask |= T.factor_masks[i]
	if(mask)
		refresh_mark(D, mask)
