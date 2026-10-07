// Temporary conditions with behaviour (doc/rewrite/migration_guide.md B15): a capability granted for a
// time by a source.
//
//	grant_hold(apc, GRANT_CAPABILITY, /datum/capability/condition/power_failure, source, 30 SECONDS)
//	grant_hold(apc, GRANT_CAPABILITY, /datum/capability/condition/power_failure, source)    // until revoked
//	grant_release(apc, GRANT_CAPABILITY, /datum/capability/condition/power_failure, source)
//
// The contribution store owns the holds: several sources may hold one condition (it is on while any
// does), a timed hold expires by itself and a deleted source's holds are dropped. The effect below
// attaches the capability with add_capability() when the first hold starts and detaches it when the last
// one ends; both mark the holder changed, so the refresh engine redraws. The capability instance is
// shared by every holder (one per path, interned).

/// GRANT_CAPABILITY moved (grant_changed()): keys are capability paths, values are hold counts.
/proc/capability_grants_changed(datum/E, list/old_list, list/new_list)
	if(!isatom(E))
		return
	var/atom/A = E
	for(var/key in new_list)
		if(new_list[key] > 0 && !(old_list?[key] > 0))
			var/datum/capability/C = cap_condition_instance(key)
			if(C)
				add_capability(A, C)
	for(var/key in old_list)
		if(old_list[key] > 0 && !(new_list?[key] > 0))
			remove_capability(A, key)

/// The one shared instance of capability `path`.
/proc/cap_condition_instance(path)
	RETURN_TYPE(/datum/capability)
	if(!ispath(path, /datum/capability))
		stack_trace("GRANT_CAPABILITY: [path] is not a capability path")
		return null
	var/static/list/instances = list()
	var/datum/capability/C = instances[path]
	if(!C)
		C = new path
		instances[path] = C
	return C

/// A capability held for a time: refuses the holder's other entries, draws, may hide verbs.
/datum/capability/condition
	/// ALL_ENTRIES, or a list of capability types whose entries this condition refuses.
	var/blocks = ALL_ENTRIES
	/// Capability types whose entries still work (the way a jammed machine still lets an engineer open its
	/// panel). Entries of the condition's own type are never refused.
	var/list/exempt
	/// Shown to the user when an entry is refused (plain text; the refusal is prefixed by the entry's name).
	else_say = "it isn't responding"
	/// Verbs hidden while the condition holds (a list of verb paths), or null.
	var/list/hides_verbs

/datum/capability/condition/gate(atom/holder, mob/user, datum/interaction/entry)
	var/datum/interaction/capability/E = entry
	if(!istype(E) || !E.cap || E.cap == src)
		return null
	if(istype(E.cap, /datum/capability/condition))
		return null // conditions don't gate each other's entries
	if(blocks != ALL_ENTRIES)
		var/matched = FALSE
		for(var/path in blocks)
			if(istype(E.cap, path))
				matched = TRUE
				break
		if(!matched)
			return null
	for(var/path in exempt)
		if(istype(E.cap, path))
			return null
	return refusal(holder)

/// The refusal text for holder. Override when it needs the holder's name; the default is else_say.
/datum/capability/condition/proc/refusal(atom/holder)
	return else_say

/datum/capability/condition/draw(atom/holder, datum/look/look)
	..()
	look.part(layer_name || "[key]")

/datum/capability/condition/hidden_verbs(atom/holder)
	return hides_verbs
