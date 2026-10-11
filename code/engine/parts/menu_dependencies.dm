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
			deps["[SHARED_CACHE_UID(D)]"] = list(entity_handle(D), S.act_gen)
		frame = frame[1]
/proc/op_menu_dependencies_valid(list/dependencies)
	for(var/id in dependencies)
		var/list/record = dependencies[id]
		if(length(record) != 2 || !record[1])
			return FALSE
		var/datum/D = resolve_handle(record[1])
		if(!D || QDELETED(D) || rx_of(D).act_gen != record[2])
			return FALSE
	return TRUE
