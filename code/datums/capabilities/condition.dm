// Temporary conditions with behaviour (doc/rewrite/migration_guide.md B15): a capability held for a time by a source.
//
//	grant(apc, held_condition(/datum/capability/condition/power_failure), source, 30 SECONDS)
//	grant(apc, held_condition(/datum/capability/condition/power_failure), source)    // until revoked
//	revoke(apc, held_condition(/datum/capability/condition/power_failure), source)
//
// held_condition(path) is an activation like any granted capability: several sources may hold one condition (it is on while any does), a timed
// hold expires by itself and a deleted source's hold ends with it. It attaches the capability with add_capability() when the first hold starts and
// detaches it when the last one ends; both mark the holder changed, so the refresh engine redraws. The capability instance is shared by every
// holder (one per path, interned).

CAPABILITY_DEF(held_condition, CAP_HELD_CONDITION, key = condition_type, condition_type = null)

/datum/capability/def/held_condition/entries()
	return list()

/datum/capability/def/held_condition/on_activate(datum/activation/A)
	if(!isatom(A.holder) || length(activations_of(A.holder, A.def.key)) > 1)
		return
	var/datum/capability/C = cap_condition_instance(condition_type)
	if(C)
		add_capability(A.holder, C)

/datum/capability/def/held_condition/on_deactivate(datum/activation/A)
	if(!isatom(A.holder) || length(activations_of(A.holder, A.def.key)))
		return
	remove_capability(A.holder, condition_type)

/// The one shared instance of capability `path`.
/proc/cap_condition_instance(path)
	RETURN_TYPE(/datum/capability)
	if(!ispath(path, /datum/capability))
		stack_trace("held_condition: [path] is not a capability path")
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
