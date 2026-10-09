// The core Topic() dispatcher: every href on a datum is an op (topic(...) / topic_in(...), code/engine/parts/inputs.dm). The sources an op's
// among = names are in code/__defines/topic.dm.

/// Answers an href on `target` for `user`: the op that names it (the inbox tried first for a player's link; this reaches the admin holder's own,
/// a re-run answer and a forward), else the datum's topic_forward(). Returns TRUE when an op took it, or null when nothing did.
/proc/topic_dispatch(target, mob/user, list/href_list)
	if(!target || !href_list)
		return null
	if(istype(user, /client))
		var/client/UC = user
		user = UC.mob
	// An op that names the href answers it (the inbox tried first for a player's link; this reaches the admin holder's own, a re-run answer and a forward).
	if(user && op_topic_href(user, target, href_list))
		return TRUE
	var/datum/D = target
	var/datum/forward = D.topic_forward()
	if(forward && forward != D)
		return topic_dispatch(forward, user, href_list)
	return null

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
