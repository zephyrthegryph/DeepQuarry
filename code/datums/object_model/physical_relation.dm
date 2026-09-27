// The engine's loc/contents pair is the sole physical containment authority.
// Expose it as a relation without retaining another edge per contained atom.
/datum/object_model/relation/physical_contents
	from_type = /atom
	to_type = /atom/movable
	virtual = TRUE
	changes_revision = FALSE

/datum/object_model/relation/physical_contents/query_from(datum/source)
	var/atom/holder = source
	return isatom(holder) ? holder.contents.Copy() : list()

/datum/object_model/relation/physical_contents/query_to(datum/target)
	var/atom/movable/thing = target
	return istype(thing) && isatom(thing.loc) ? list(thing.loc) : list()

/datum/object_model/relation/physical_contents/virtual_has(datum/source, datum/target)
	var/atom/movable/thing = target
	return isatom(source) && istype(thing) && thing.loc == source

/// Called after loc commits. Only observable holders pay the notification cost.
/proc/om_physical_contents_changed(atom/holder, atom/movable/thing)
	if(!holder?.om_state && !thing?.om_state)
		return
	om_derived_relation_membership_changed(holder, /datum/object_model/relation/physical_contents, thing)
	if(holder.om_state)
		if(!holder.ledger)
			om_changed(holder, "contents")
			om_bump_revision_if_tracked(holder)
