// The core Topic() dispatcher (doc/rewrite/systems.md §20; macros in code/__defines/topic.dm).

/// type -> (href key -> action row). Built once per type on first use.
GLOBAL_LIST_EMPTY(topic_tables)

/// The action rows of this type, as a list of rows (TOPIC_ACTION links onto this).
/datum/proc/topic_actions()
	return null

/// Appends one row (list(key, proc, specs, namespace)) to `rows`; used by TOPIC_ACTION and
/// TOPIC_NS_ACTION. A row with a namespace is only reachable through a dispatch naming it.
/proc/topic_register(list/rows, key, proc_name, list/specs, namespace = null)
	if(!rows)
		rows = list()
	rows += list(list(key, proc_name, specs, namespace))
	return rows

/// The type of `target` (a client counts as a datum here).
/proc/topic_target_type(datum/target)
	return target.type

/// The key -> row table of `target`'s type in `namespace` (null: the plain href rows).
/proc/topic_table(target, namespace = null)
	var/target_type = topic_target_type(target)
	var/cache_key = isnull(namespace) ? target_type : "[namespace]|[target_type]"
	var/list/table = GLOB.topic_tables[cache_key]
	if(table)
		return table
	table = list()
	var/datum/D = target
	var/list/rows = D.topic_actions()
	for(var/list/row as anything in rows)
		if(row[4] == namespace)
			table[row[1]] = row
	GLOB.topic_tables[cache_key] = table
	return table

/// The row of `target`'s table (in `namespace`) matching `href_list`, or null.
/proc/topic_find_row(target, list/href_list, namespace = null)
	var/list/table = topic_table(target, namespace)
	for(var/key in href_list)
		if(!istext(key))
			continue
		var/value = href_list[key]
		var/list/row = istext(value) ? table["[key]=[value]"] : null
		if(!row)
			row = table[key]
		if(row)
			return row
	return null

/// Finds the row matching `href_list` in `target`'s table and runs it for `user`.
/// Returns the handler's return value, or null when nothing matched or a check failed.
/proc/topic_dispatch(target, mob/user, list/href_list)
	if(!target || !href_list)
		return null
	if(istype(user, /client))
		var/client/UC = user
		user = UC.mob
	// An op that names the href answers it (the inbox tried first for a player's link; this reaches the admin holder's own, a re-run answer and a forward).
	if(user && op_topic_href(user, target, href_list))
		return TRUE
	var/list/row = topic_find_row(target, href_list)
	if(!row)
		var/datum/D = target
		var/datum/forward = D.topic_forward()
		if(forward && forward != D)
			return topic_dispatch(forward, user, href_list)
		return null
	return topic_run(target, user, href_list, row)

/// Runs one row: gate (unless `gate` is FALSE: a namespace with its own gate), rights, typed
/// args, handler.
/proc/topic_run(target, mob/user, list/href_list, list/row, gate = TRUE)
	var/datum/D = target
	if(QDELETED(D) || (gate && !D.topic_allowed(user, href_list)))
		return null
	var/list/handler_args = list()
	handler_args[TOPIC_HREF] = href_list
	for(var/list/spec as anything in row[3])
		switch(spec[1])
			if(TOPIC_SPEC_RIGHTS)
				if(!admin_can(user?.client, spec[2]))
					// A rights failure on an href is how exploit attempts show up: always tell admins.
					var/attempt = "[key_name(user)] tried href action '[row[1]]' on [topic_target_type(target)] without [rights2text(spec[2], " ")]"
					admin_log_denial(user?.client, "topic:[row[1]]", spec[2])
					log_admin(attempt)
					log_href("TOPIC_RIGHTS rejected: [attempt]")
					message_admins("[key_name_admin(user)] tried href action '[row[1]]' on [topic_target_type(target)] without sufficient rights.")
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
				// ALLOW(sys_topic_raw_num): the core dispatcher's TOPIC_NUM conversion.
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
			// ALLOW(spatial): a TOPIC_IN_WORLD ref is any atom on the map; world is not a list to hand locate_in_list().
			found = locate(raw) in world
		if(TOPIC_IN_CLIENTS)
			found = locate_in_list(GLOB.clients, raw)
		if(TOPIC_IN_MOBS)
			found = locate_in_list(REGISTRY_MEMBERS(REGISTRY_MOBS), raw)
		if(TOPIC_IN_CONTENTS)
			var/atom/A = target
			if(!istype(A))
				return null
			found = locate_in_list(contents_of(A), raw)
		else
			var/list/pool = call(target, source)()
			if(!islist(pool))
				return null
			found = locate_in_list(pool, raw)
	if(isnull(found))
		return null
	if(islist(wanted)) // any of several types
		var/matched = FALSE
		for(var/wanted_type in wanted)
			if(istype(found, wanted_type))
				matched = TRUE
				break
		if(!matched)
			return null
	else if(!isnull(wanted) && !istype(found, wanted)) // null: whatever locate() finds (the handler validates)
		return null
	if(isdatum(found))
		var/datum/FD = found
		if(QDELETED(FD))
			return null
	return found

// ALLOW(sys_topic_override): the one core dispatcher every href on a datum reaches.
/datum/Topic(href, list/href_list)
	return topic_dispatch(src, usr, href_list)
