// A grant is a lifetime-managed edge from a source to an entity. The runtime's
// path tables are indexes; the two relations below own the cleanup semantics.
// Payload: behaviour path, grant source, added (TRUE/FALSE), active after change.
/datum/object_model/event/grant_changed

/datum/object_model/relation/grant_holder
	from_type = /datum
	to_type = /datum/object_model/behaviour_grant
	target_single = TRUE
	ownership = OM_REL_OWN_TARGET
	changes_revision = FALSE

/datum/object_model/relation/grant_source
	from_type = /datum/object_model/behaviour_grant
	to_type = /datum
	source_single = TRUE
	on_end_lost = OM_REL_DESTROY_SOURCE
	changes_revision = FALSE

/datum/object_model/behaviour_grant
	var/datum/object_model/behaviour_runtime/runtime
	var/datum/source
	var/behaviour_path

/datum/object_model/behaviour_grant/Destroy(force = FALSE)
	var/datum/object_model/behaviour_runtime/R = runtime
	runtime = null
	if(R && !QDELETED(R))
		R.grant_token_lost(src)
	source = null
	behaviour_path = null
	return ..()

// Generic keyed grants use the lifetime tree as their sole holder index. The
// source edge tears the claim down if its producer is deleted unexpectedly.
// Payload: key, source, added (TRUE/FALSE), still granted after this change.
/datum/object_model/event/keyed_grant_changed

/datum/object_model/relation/keyed_grant_source
	from_type = /datum/object_model/keyed_grant
	to_type = /datum
	source_single = TRUE
	on_end_lost = OM_REL_DESTROY_SOURCE
	changes_revision = FALSE

/datum/object_model/keyed_grant
	var/datum/holder
	var/datum/source
	var/key
	var/established = FALSE

/datum/object_model/keyed_grant/Destroy(force = FALSE)
	var/datum/old_holder = holder
	var/datum/old_source = source
	var/old_key = key
	var/was_established = established
	holder = null
	source = null
	key = null
	established = FALSE
	. = ..()
	if(was_established && old_holder && !om_is_dying(old_holder))
		om_emit(old_holder, /datum/object_model/event/keyed_grant_changed, old_key, old_source, FALSE, om_keyed_has(old_holder, old_key))

/proc/om_keyed_grant_slot(key)
	return "om:keyed_grant:[key]"

/// Idempotently grant a key to a holder for the lifetime of a datum source.
/proc/om_keyed_grant(datum/holder, key, datum/source)
	if(!holder || !source || isnull(key) || om_is_dying(holder) || om_is_dying(source))
		return FALSE
	var/slot = om_keyed_grant_slot(key)
	var/list/tokens = holder.om_state?.children?[slot]
	for(var/datum/object_model/keyed_grant/existing as anything in tokens)
		if(existing.source == source)
			return TRUE
	var/datum/object_model/keyed_grant/G = new
	G.holder = holder
	G.source = source
	G.key = key
	if(!om_claim(holder, slot, G) || !om_link(G, /datum/object_model/relation/keyed_grant_source, source))
		qdel(G)
		return FALSE
	G.established = TRUE
	om_emit(holder, /datum/object_model/event/keyed_grant_changed, key, source, TRUE, TRUE)
	return TRUE

/proc/om_keyed_revoke(datum/holder, key, datum/source)
	var/slot = om_keyed_grant_slot(key)
	var/list/tokens = holder?.om_state?.children?[slot]
	for(var/datum/object_model/keyed_grant/G as anything in tokens)
		if(G.source == source)
			qdel(G)
			return TRUE
	return FALSE

/// Reads the ownership slot directly, without allocating a snapshot.
/proc/om_keyed_has(datum/holder, key)
	var/slot = om_keyed_grant_slot(key)
	return length(holder?.om_state?.children?[slot]) > 0

/// Returns null for no grants, otherwise a private list of live sources.
/proc/om_keyed_sources(datum/holder, key)
	var/slot = om_keyed_grant_slot(key)
	var/list/tokens = holder?.om_state?.children?[slot]
	if(!length(tokens))
		return null
	var/list/sources = list()
	for(var/datum/object_model/keyed_grant/G as anything in tokens)
		if(G.source && !QDELETED(G.source))
			sources += G.source
	return length(sources) ? sources : null
