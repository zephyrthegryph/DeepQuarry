// Grants: what a source lets a target have (a verb, a capability, a trait, an ability, a language, access, a cadence). Each kind is a SUM_PER_KEY
// stat (code/contracts/ids/stats.dm): the key is the thing granted, held by every source that grants it, so it is on while any source holds it. A
// deleted source's holds are released by the stat layer, and a timed grant ends on its own. A client is not a datum: its grants live on its
// /datum/client_verbs holder (om_grant_target()).
//
//	grant_hold(M, GRANT_VERB, /mob/living/proc/ventcrawl, source)           grant_hold(C, GRANT_CAPABILITY, path, source, 30 SECONDS)
//	grant_release(M, GRANT_VERB, /mob/living/proc/ventcrawl, source)        grant_held(M, GRANT_TRAIT, trait)
//	grant_values(M, GRANT_TRAIT)   grant_sources(M, kind, key)   grants_given_by(M, source)   grant_release_all_of(M, kind, source)
//
// A change of what is on (a key flipping between granted and not) runs the kind's applier from stat_recompute(): verbs write the verbs list, a
// capability attaches, a cadence tells its system.

/// The stat id of grant kind `kind` (GRANT_*).
/proc/grant_stat(kind)
	var/static/list/ids = list(
		GRANT_ABILITY = STAT_GRANT_ABILITY,
		GRANT_LANGUAGE = STAT_GRANT_LANGUAGE,
		GRANT_VERB = STAT_GRANT_VERB,
		GRANT_VERB_HIDE = STAT_GRANT_VERB_HIDE,
		GRANT_CAPABILITY = STAT_GRANT_CAPABILITY,
		GRANT_ACCESS = STAT_GRANT_ACCESS,
		GRANT_TRAIT = STAT_GRANT_TRAIT,
		GRANT_CADENCE = STAT_GRANT_CADENCE,
	)
	return ids[kind]

/// The grant kind (GRANT_*) of stat id `stat_id`, or null when it is not a grant stat.
/proc/grant_kind_of_stat(stat_id)
	var/static/list/kinds
	if(!kinds)
		kinds = list()
		for(var/kind in list(GRANT_ABILITY, GRANT_LANGUAGE, GRANT_VERB, GRANT_VERB_HIDE, GRANT_CAPABILITY, GRANT_ACCESS, GRANT_TRAIT, GRANT_CADENCE))
			kinds["[grant_stat(kind)]"] = kind
	return kinds["[stat_id]"]

/// `source` grants `key` of `kind` to `target` (a datum or a client), for `lasts` deciseconds of the target's clock when given, else until released.
/// TRUE when placed.
/proc/grant_hold(target, kind, key, datum/source, lasts)
	var/datum/E = om_grant_target(target)
	if(!E || QDELETED(E) || !source || QDELETED(source))
		return FALSE
	return !!hold(E, grant_stat(kind), 1, source, lasts = lasts, key = key)

/// `source` stops granting `key` of `kind` to `target`. TRUE when it held it.
/proc/grant_release(target, kind, key, datum/source)
	var/datum/E = om_grant_target(target, FALSE)
	return E ? release(E, grant_stat(kind), source, key) : FALSE

/// `source` grants every key in `keys` (a list, or one key).
/proc/grant_hold_each(target, kind, keys, datum/source)
	if(!islist(keys))
		return grant_hold(target, kind, keys, source)
	for(var/key in keys)
		grant_hold(target, kind, key, source)
	return TRUE

/// `source` revokes every key in `keys` (a list, or one key).
/proc/grant_release_each(target, kind, keys, datum/source)
	if(!islist(keys))
		return grant_release(target, kind, keys, source)
	for(var/key in keys)
		grant_release(target, kind, key, source)
	return TRUE

/// `source` revokes everything of `kind` it grants `target`.
/proc/grant_release_all_of(target, kind, datum/source)
	for(var/list/pair as anything in grants_given_by(target, source))
		if(pair[1] == kind)
			grant_release(target, kind, pair[2], source)

/// key -> hold count of `kind` on `target` (read only), or null when nothing is granted.
/proc/grant_values(target, kind)
	var/datum/E = om_grant_target(target, FALSE)
	if(!E)
		return null
	var/list/per_key = stat_value(E, grant_stat(kind))
	return length(per_key) ? per_key : null

/// TRUE while any source grants `key` of `kind` to `target`.
/proc/grant_held(target, kind, key)
	READS_FROM() // a grant is asked when a choice is made, never cached
	var/list/per_key = grant_values(target, kind)
	return !!per_key && per_key[key] > 0

/// The sources granting `target` the `kind` grant `key` (a list), or null when none does.
/proc/grant_sources(target, kind, key)
	var/datum/E = om_grant_target(target, FALSE)
	var/stat_id = grant_stat(kind)
	for(var/list/row as anything in E?.rx?.stats?.holds)
		if(row[H_STAT] == stat_id && row[H_KEY] == key && !isnull(row[H_SOURCE]))
			LAZYOR(., row[H_SOURCE])

/// Every grant `source` gives `target`: list of list(kind, key).
/proc/grants_given_by(target, datum/source)
	. = list()
	var/datum/E = om_grant_target(target, FALSE)
	for(var/list/row as anything in E?.rx?.stats?.holds)
		if(row[H_SOURCE] != source)
			continue
		var/kind = grant_kind_of_stat(row[H_STAT])
		if(kind)
			. += list(list(kind, row[H_KEY]))

/// A grant stat of `E` moved from `old_value` to `new_value` (stat_recompute): runs the kind's applier for each key that flipped between on and off.
/proc/grant_changed(datum/E, stat_id, old_value, new_value)
	var/kind = grant_kind_of_stat(stat_id)
	if(!kind)
		return
	var/list/old_list = islist(old_value) ? old_value : null
	var/list/new_list = islist(new_value) ? new_value : null
	var/list/flipped
	for(var/key in new_list)
		if((new_list[key] > 0) != (old_list?[key] > 0))
			LAZYOR(flipped, key)
	for(var/key in old_list)
		if((old_list[key] > 0) != (new_list?[key] > 0))
			LAZYOR(flipped, key)
	if(!flipped)
		return
	switch(kind)
		if(GRANT_VERB, GRANT_VERB_HIDE)
			verb_store_sync(E, flipped)
		if(GRANT_CAPABILITY)
			capability_grants_changed(E, old_list, new_list)
		if(GRANT_CADENCE)
			var/datum/step_cadence/C = E
			if(istype(C))
				C.cadence_changed()
