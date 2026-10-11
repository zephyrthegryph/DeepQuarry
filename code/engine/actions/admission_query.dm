// Synchronous typed admission context: no event dispatch, effects, notices or metrics.
ACTION(admission_query, mob/wearer, mob/mover, datum/destination, slot_id, requirement_channel, list/query_options, QUERY)

// Named scalar options only: no world references or aliasable nested containers.
/proc/op_query_input_copy(value)
	if(isnull(value))
		return null
	if(!islist(value))
		CRASH("query options must be a named scalar map")
	var/list/input = value
	var/list/output = list()
	for(var/key in input)
		if(!istext(key) || !(isnull(input[key]) || isnum(input[key]) || istext(input[key]) || ispath(input[key])))
			CRASH("query options require text keys and immutable scalar values")
		output[key] = input[key]
	return output

// Generated callback rows carry the root and relation hops separately. Resolve them
// against this invocation, not the declarer: replacement membership is itself watched.
/proc/op_query_read_pairs(datum/act/admission_query/A, proc_name)
	. = list()
	var/path = A.holder.type
	var/list/row
	while(ispath(path, /datum))
		row = GLOB.generated_reads_table["[path]::[proc_name]"]
		if(row)
			break
		var/datum/typed = path
		path = initial(typed.parent_type)
	if(!row)
		if(proc_name in A.holder.vars)
			. += list(list(A.holder, proc_name))
		return
	for(var/i in 2 to length(row))
		var/list/read = row[i]
		var/root = GLOB.generated_read_roots[read[1]]
		var/datum/D
		if(read[2] == SREAD_KIND_SYSTEM)
			if(findtext(root, "system:") != 1)
				CRASH("invalid generated system query root [root]")
			D = stat_system_singleton(copytext(root, 8))
			if(!D || QDELETED(D))
				CRASH("query system root [root] is not initialized")
			. += list(list(D, GLOB.generated_read_names[read[3]]))
			continue
		switch(root)
			if("holder")
				D = A.holder
			if("actor")
				D = A.actor
			if("held")
				D = A.held_provider()
			if("target")
				D = A.target
			if("wearer")
				D = A.wearer
			if("mover")
				D = A.mover
			if("destination")
				D = A.destination
			else
				CRASH("unsupported query dependency root [root]")
		if(!(read[2] in list(SREAD_KIND_VAR, SREAD_KIND_ACCESSOR, READ_KIND_NATIVE)))
			CRASH("query dependency needs a native read provider for kind [read[2]]")
		var/list/owners = D && !QDELETED(D) ? list(D) : list()
		for(var/h = 4; h <= length(read); h++)
			var/hop = GLOB.generated_read_names[read[h]]
			if(copytext(hop, length(hop) - 1) == "[]")
				hop = copytext(hop, 1, length(hop) - 1)
			var/list/next = list()
			for(var/datum/owner as anything in owners)
				. += list(list(owner, hop))
				var/value = owner.vars[hop]
				if(islist(value))
					var/list/members = value
					for(var/member_key in members)
						// Plain relation lists carry datums directly. Associative owned
						// relations carry the datum as the value of a stable key.
						if(isdatum(member_key))
							var/datum/key_owner = member_key
							if(!QDELETED(key_owner))
								next |= key_owner
						if(istext(member_key) || ispath(member_key) || isdatum(member_key))
							var/member_value = members[member_key]
							if(isdatum(member_value))
								var/datum/value_owner = member_value
								if(!QDELETED(value_owner))
									next |= value_owner
				else if(isdatum(value))
					var/datum/value_owner = value
					if(!QDELETED(value_owner))
						next |= value_owner
			owners = next
		var/key = GLOB.generated_read_names[read[3]]
		for(var/datum/owner as anything in owners)
			. += list(list(owner, key))
