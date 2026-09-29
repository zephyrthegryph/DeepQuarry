// The core Topic() dispatcher (doc/rewrite/systems.md §20; macros in code/__defines/topic.dm).

/// type -> (href key -> action row). Built once per type on first use.
GLOBAL_LIST_EMPTY(topic_tables)

/// The action rows of this type, as a list of rows (TOPIC_ACTION links onto this).
/datum/proc/topic_actions()
	return null

/// Whether `user` may use this datum's href actions at all (checked before any row).
/datum/proc/topic_allowed(mob/user, list/href_list)
	return TRUE

/// A datum whose href actions this one's links also reach (a page forwarding to its book):
/// hrefs matching none of this type's rows are dispatched to it instead.
/datum/proc/topic_forward()
	return null

/// Appends one row (list(key, proc, specs)) to `rows`; used by TOPIC_ACTION.
/proc/topic_register(list/rows, key, proc_name, list/specs)
	if(!rows)
		rows = list()
	rows += list(list(key, proc_name, specs))
	return rows

/// The type of `target` (a client counts as a datum here).
/proc/topic_target_type(datum/target)
	return target.type

/// The key -> row table of `target`'s type.
/proc/topic_table(target)
	var/target_type = topic_target_type(target)
	var/list/table = GLOB.topic_tables[target_type]
	if(table)
		return table
	table = list()
	var/datum/D = target
	var/list/rows = D.topic_actions()
	for(var/list/row as anything in rows)
		table[row[1]] = row
	GLOB.topic_tables[target_type] = table
	return table

/// Finds the row matching `href_list` in `target`'s table and runs it for `user`.
/// Returns the handler's return value, or null when nothing matched or a check failed.
/proc/topic_dispatch(target, mob/user, list/href_list)
	if(!target || !href_list)
		return null
	if(istype(user, /client))
		var/client/UC = user
		user = UC.mob
	var/list/table = topic_table(target)
	var/list/row
	for(var/key in href_list)
		if(!istext(key))
			continue
		var/value = href_list[key]
		row = istext(value) ? table["[key]=[value]"] : null
		if(!row)
			row = table[key]
		if(row)
			break
	if(!row)
		var/datum/D = target
		var/datum/forward = D.topic_forward()
		if(forward && forward != D)
			return topic_dispatch(forward, user, href_list)
		return null
	return topic_run(target, user, href_list, row)

/// Runs one row: gate, rights, typed args, handler.
/proc/topic_run(target, mob/user, list/href_list, list/row)
	var/datum/D = target
	if(QDELETED(D) || !D.topic_allowed(user, href_list))
		return null
	var/list/handler_args = list()
	handler_args[TOPIC_HREF] = href_list
	for(var/list/spec as anything in row[3])
		switch(spec[1])
			if(TOPIC_SPEC_RIGHTS)
				if(!check_rights_for(user?.client, spec[2]))
					if(user)
						to_chat(user, span_red("Error: You do not have sufficient rights to do that. You require one of the following flags:[rights2text(spec[2], " ")]."), confidential = TRUE)
					return null
			if(TOPIC_SPEC_REF)
				var/name = spec[2]
				var/raw = href_list[name]
				if(isnull(raw))
					handler_args[name] = null
					continue
				var/found = topic_resolve_ref(target, raw, spec[3], length(spec) >= 4 ? spec[4] : null)
				if(isnull(found))
					log_href("TOPIC_REF rejected: [key_name(user)] sent [name]=[raw] (wants [spec[3]]) to [topic_target_type(target)] action [row[1]]")
					return null
				handler_args[name] = found
			if(TOPIC_SPEC_NUM)
				handler_args[spec[2]] = text2num(href_list[spec[2]])
			if(TOPIC_SPEC_TEXT)
				var/text = href_list[spec[2]]
				if(!isnull(text))
					text = "[text]"
					if(length(spec) >= 3 && spec[3] && length(text) > spec[3])
						text = copytext(text, 1, spec[3] + 1)
				handler_args[spec[2]] = text
	return call(target, row[2])(user, handler_args)

/// `locate(raw) in <source>`, then istype(`wanted`); null if either fails or it is being deleted.
/proc/topic_resolve_ref(target, raw, wanted, source)
	if(isnull(source))
		if(ispath(wanted, /client))
			source = TOPIC_IN_CLIENTS
		else if(ispath(wanted, /turf))
			source = TOPIC_IN_WORLD
		else
			source = TOPIC_ANY
	var/found
	switch(source)
		if(TOPIC_ANY)
			found = locate(raw)
		if(TOPIC_IN_WORLD)
			found = locate(raw) in world
		if(TOPIC_IN_CLIENTS)
			found = locate(raw) in GLOB.clients
		if(TOPIC_IN_CONTENTS)
			var/atom/A = target
			if(!istype(A))
				return null
			found = locate(raw) in A.contents
		else
			var/list/pool = call(target, source)()
			if(!islist(pool))
				return null
			found = locate(raw) in pool
	if(isnull(found) || !istype(found, wanted))
		return null
	if(isdatum(found))
		var/datum/FD = found
		if(QDELETED(FD))
			return null
	return found

// ALLOW(sys_topic_override): the one core dispatcher every href on a datum reaches.
/datum/Topic(href, list/href_list)
	return topic_dispatch(src, usr, href_list)
