// Persistent snapshots for declared, non-atom object-model ownership trees.
// The existing state codec owns value encoding and per-type migrations. This
// wrapper records the ownership slots that state_serialize() does not know.

#define OM_PERSIST_VERSION 1
#define OM_PERSIST_MAX_DEPTH 64

/// Returns a JSON-safe blob or null, appending a concrete refusal to errors.
/proc/om_persist_serialize(datum/root, list/errors)
	var/list/refusals = list()
	var/list/blob = om_persist_encode(root, refusals, 0)
	if(errors)
		errors += refusals
	return length(refusals) ? null : blob

/proc/om_persist_encode(datum/thing, list/errors, depth)
	if(!thing || QDELETED(thing) || isatom(thing))
		errors += "object-model persistence supports live datums only"
		return null
	if(depth > OM_PERSIST_MAX_DEPTH)
		errors += "object-model ownership exceeds [OM_PERSIST_MAX_DEPTH] levels"
		return null
	if(!om_declarations()[thing.type])
		errors += "[thing.type] has no static object-model declaration"
		return null
	var/datum/object_model/state/model = thing.om_state
	if(model?.dying || length(model?.outgoing) || length(model?.incoming) || model?.behaviour_runtime || length(model?.pending_wakes))
		errors += "[thing.type] has live object-model relations, behaviours or wakes"
		return null
	if(length(thing._active_timers) || (thing.datum_flags & DF_ISPROCESSING))
		errors += "[thing.type] has active timers or processing"
		return null
	var/list/state = state_serialize(thing, NONE, errors)
	if(!state)
		return null
	var/list/blob = list("version" = OM_PERSIST_VERSION, "state" = state)
	var/list/slots = list()
	for(var/slot_name in model?.children)
		var/datum/object_model/slot_def/slot_definition = om_slot_def_for(thing, slot_name)
		if(!slot_definition)
			errors += "[thing.type] owns undeclared slot [slot_name]"
			continue
		var/list/children = list()
		for(var/datum/child in om_children(thing, slot_name))
			var/list/child_blob = om_persist_encode(child, errors, depth + 1)
			if(child_blob)
				children += list(child_blob)
		slots += list(list("name" = slot_name, "children" = children))
	if(length(slots))
		blob["slots"] = slots
	return blob

/// Materializes a complete snapshot, or destroys its partial tree on refusal.
/proc/om_persist_materialize(list/blob, list/errors)
	var/list/refusals = list()
	var/datum/thing = om_persist_decode(blob, refusals, 0)
	if(length(refusals) && thing)
		om_destroy(thing)
		thing = null
	if(errors)
		errors += refusals
	return thing

/proc/om_persist_decode(list/blob, list/errors, depth)
	if(!islist(blob) || blob["version"] != OM_PERSIST_VERSION || !islist(blob["state"]))
		errors += "invalid or unsupported object-model snapshot version"
		return null
	if(depth > OM_PERSIST_MAX_DEPTH)
		errors += "object-model snapshot exceeds [OM_PERSIST_MAX_DEPTH] levels"
		return null
	var/list/state = blob["state"]
	var/type_text = state[STATE_KEY_TYPE]
	var/path = (type_text in GLOB.state_type_migrations) ? GLOB.state_type_migrations[type_text] : text2path(type_text)
	if(!ispath(path, /datum) || ispath(path, /atom) || !om_declarations()[path])
		errors += "[type_text] is not a declared datum entity"
		return null
	if(!isnull(blob["slots"]) && !islist(blob["slots"]))
		errors += "[type_text] has malformed ownership slots"
		return null
	var/datum/thing = state_materialize(state, null, NONE, errors)
	if(!thing)
		return null
	var/datum/object_model/archetype/A = om_archetype_for(thing.type)
	var/list/seen_slots = list()
	for(var/list/slot_blob as anything in blob["slots"])
		if(!islist(slot_blob))
			errors += "[thing.type] has a malformed ownership slot"
			break
		var/slot_name = slot_blob?["name"]
		var/list/children = slot_blob?["children"]
		var/datum/object_model/slot_def/slot_definition = A?.slots?[slot_name]
		if(!slot_definition || (slot_name in seen_slots) || !islist(children) || length(children) > slot_definition.capacity)
			errors += "[thing.type] has invalid or over-capacity slot [slot_name]"
			break
		seen_slots += slot_name
		for(var/list/child_blob as anything in children)
			var/datum/child = om_persist_decode(child_blob, errors, depth + 1)
			if(!child)
				break
			if(!om_claim(thing, slot_name, child))
				errors += "[thing.type] refused child in slot [slot_name]"
				qdel(child)
				break
		if(length(errors))
			break
	if(length(errors))
		om_destroy(thing)
		return null
	return thing
