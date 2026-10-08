/datum/om/effect/grant_verb
	parent_type = /datum/effect_definition/grant_verb

/proc/om_grant_target(target, create = TRUE)
	return verb_grant_target(target, create)

// ---------------------------------------------------------------- list helpers

/// Timed grant: `source` grants (or hides, for GRANT_VERB_HIDE) `id` on `target` for `duration`.
/proc/om_grant_for(target, kind, id, datum/source, duration)
	return om_apply(om_grant_target(target), kind, source, duration, 1, id)

/// `source` grants every id in `ids` (a list, or one id) of `kind` to `target`.
/proc/om_grant_each(target, kind, ids, datum/source)
	if(!islist(ids))
		return om_grant(target, kind, ids, source)
	for(var/id in ids)
		om_grant(target, kind, id, source)
	return TRUE

/// `source` revokes every id in `ids` (a list, or one id) of `kind` from `target`.
/proc/om_revoke_each(target, kind, ids, datum/source)
	if(!islist(ids))
		return om_revoke(target, kind, ids, source)
	for(var/id in ids)
		om_revoke(target, kind, id, source)
	return TRUE

/// `source` revokes everything of `kind` it grants `target`.
/proc/om_revoke_all_of(target, kind, datum/source)
	for(var/list/pair as anything in om_grants_from(target, source))
		if(pair[1] == kind)
			om_revoke(target, kind, pair[2], source)

