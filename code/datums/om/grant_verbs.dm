// Verbs through grants (doc/rewrite/systems.md §19).
//
// A verb is on a mob (or object, or turf) while any source grants it:
//
//     om_grant(M, GRANT_VERB, /mob/living/proc/ventcrawl, source)
//     om_revoke(M, GRANT_VERB, /mob/living/proc/ventcrawl, source)
//
// The GRANT_VERB effect's change hook adds the verb (add_verb) when the first source grants it
// and removes it (remove_verb) when the last source revokes or is deleted: the contribution
// store drops a deleted source's holds, so nothing has to pair an add with a remove. A mob is
// its own source for verbs that come with what it is (its type, its species form).
//
// Clients are not datums and have no contribution store: client verb sets (admin verbs, the
// ticket and OOC verb sets) go through add_verb()/remove_verb() directly, each site annotated
// ALLOW(sys_add_verb_pair).

/datum/om/effect/grant_verb

/datum/om/effect/grant_verb/on_changed(datum/E, old_value, new_value)
	var/atom/A = E
	if(!istype(A))
		return
	var/list/old_list = islist(old_value) ? old_value : null
	var/list/new_list = islist(new_value) ? new_value : null
	var/list/gained
	var/list/lost
	for(var/v in new_list)
		if(new_list[v] > 0 && !(old_list?[v] > 0))
			LAZYADD(gained, v)
	for(var/v in old_list)
		if(old_list[v] > 0 && !(new_list?[v] > 0))
			LAZYADD(lost, v)
	if(!ismob(A))
		// Objects and turfs have no stat panel: their verb list is the whole story.
		if(lost)
			A.verbs -= lost // ALLOW(sys_add_verb_pair): the grant hook itself
		if(gained)
			A.verbs += gained // ALLOW(sys_add_verb_pair): the grant hook itself
		return
	if(lost)
		remove_verb(A, lost) // ALLOW(sys_add_verb_pair): the grant hook itself
	if(gained)
		add_verb(A, gained) // ALLOW(sys_add_verb_pair): the grant hook itself

/// `source` grants every id in `ids` (a list, or one id) of `kind` to `target`.
/proc/om_grant_each(datum/target, kind, ids, datum/source)
	if(!islist(ids))
		return om_grant(target, kind, ids, source)
	for(var/id in ids)
		om_grant(target, kind, id, source)
	return TRUE

/// `source` revokes every id in `ids` (a list, or one id) of `kind` from `target`.
/proc/om_revoke_each(datum/target, kind, ids, datum/source)
	if(!islist(ids))
		return om_revoke(target, kind, ids, source)
	for(var/id in ids)
		om_revoke(target, kind, id, source)
	return TRUE

/// `source` revokes everything of `kind` it grants `target`.
/proc/om_revoke_all_of(datum/target, kind, datum/source)
	for(var/list/pair as anything in om_grants_from(target, source))
		if(pair[1] == kind)
			om_revoke(target, kind, pair[2], source)
