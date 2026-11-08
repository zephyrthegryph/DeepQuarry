// Dependency capture for the native operation menu cache.
// Store handles and generations, never retain entities through cache rows.
/proc/op_menu_record_reads(list/pairs)
	var/list/frame = GLOB.op_menu_read_frame
	while(frame)
		if(length(frame) < 3)
			frame.len = 3
		if(!frame[3])
			frame[3] = list()
		var/list/deps = frame[3]
		for(var/list/pair as anything in pairs)
			if(length(pair) != 2)
				continue
			var/datum/D = pair[1]
			if(!D || QDELETED(D))
				frame[2] = TRUE
				continue
			var/datum/rx_state/S = rx_of(D)
			var/key = pair[2]
			if(istext(key))
				// Per key: the row is stale only when this key of D is published again (state_changed() bumps a watched key).
				if(!S.menu_keys)
					S.menu_keys = list()
				if(isnull(S.menu_keys[key]))
					S.menu_keys[key] = 0
				deps["[SHARED_CACHE_UID(D)]|[key]"] = list(handle_of(D), S.menu_keys[key], key)
			else
				deps["[SHARED_CACHE_UID(D)]"] = list(handle_of(D), S.act_gen)
		frame = frame[1]
/proc/op_menu_dependencies_valid(list/dependencies)
	for(var/id in dependencies)
		var/list/record = dependencies[id]
		if(length(record) < 2 || !record[1])
			return FALSE
		var/datum/D = handle_get(record[1])
		if(!D || QDELETED(D))
			return FALSE
		var/datum/rx_state/S = rx_of(D)
		if(length(record) >= 3)
			if(S.menu_keys?[record[3]] != record[2])
				return FALSE
		else if(S.act_gen != record[2])
			return FALSE
	return TRUE

/// A Menu row whose decision depends on its holder's whole state beyond its recorded reads (a path through spaces, a state-worded label): the
/// holder's act generation is a dependency of the read.
/proc/op_menu_record_holder(datum/D)
	if(!D || QDELETED(D))
		return
	var/list/frame = GLOB.op_menu_read_frame
	var/datum/rx_state/S = rx_of(D)
	while(frame)
		if(length(frame) < 3)
			frame.len = 3
		if(!frame[3])
			frame[3] = list()
		var/list/deps = frame[3]
		deps["[SHARED_CACHE_UID(D)]"] = list(handle_of(D), S.act_gen)
		frame = frame[1]
