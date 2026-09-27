// Generic lifetime authority and non-owning relations for converted datums.
// Nothing is installed on legacy instances until an om_* API is used.

#define OM_REL_ONE_TO_ONE 1
#define OM_REL_ONE_TO_MANY 2
#define OM_REL_MANY_TO_MANY 3
#define OM_REL_SYMMETRIC 4
#define OM_REL_UNLINK 1
#define OM_REL_DESTROY_SOURCE 2
#define OM_REL_DESTROY_TARGET 3
#define OM_REL_OWN_NONE 0
#define OM_REL_OWN_SOURCE 1 // target owns source
#define OM_REL_OWN_TARGET 2 // source owns target
#define OM_REL_DESTROYING "destroying"
#define OM_REL_REPLACED "replaced"
#define OM_REL_EXPLICIT "explicit"
#define OM_KIND_DEF 1
#define OM_KIND_SERVICE 2
#define OM_KIND_LOCATION 3
#define OM_KIND_ENTITY 4
#define OM_SLOT_DELETE 1
#define OM_SLOT_SPILL 2
#define OM_SLOT_TRANSFER 3
#define OM_SLOT_TO_LATENT 4
#define OM_SLOT_KEEP_WITH 5

/// Attach an existing field to a single-child ownership slot. The field name
/// is checked by DM; the caller's typed child argument enforces child type.
#define OM_CLAIM_FIELD(holder, field, slot, child) om_claim_field(holder, NAMEOF(holder, field), holder.field, slot, child)

/// Converted subtypes override this classification when their lifetime differs.
/datum/proc/om_kind()
	return OM_KIND_ENTITY

/turf/om_kind()
	return OM_KIND_LOCATION

/area/om_kind()
	return OM_KIND_LOCATION

/datum/object_model/relation/om_kind()
	return OM_KIND_DEF

/datum/object_model/declaration/om_kind()
	return OM_KIND_DEF

/datum/object_model/archetype/om_kind()
	return OM_KIND_DEF

/datum/object_model/slot_def/om_kind()
	return OM_KIND_DEF

/datum/object_model/behaviour/om_kind()
	return OM_KIND_DEF

/datum/object_model/bundle/om_kind()
	return OM_KIND_DEF

/datum/object_model/requirement/om_kind()
	return OM_KIND_DEF

/datum/object_model/event/om_kind()
	return OM_KIND_DEF

/datum/controller/subsystem/om_kind()
	return OM_KIND_SERVICE

/datum/var/tmp/datum/object_model/state/om_state

/datum/object_model/state
	var/tmp/datum/owner
	var/owner_slot
	/// Optional direct owner field that mirrors this single-child slot.
	var/owner_field
	var/revision = 0
	var/revision_tracked = FALSE
	var/tmp/list/children
	var/tmp/list/outgoing
	var/tmp/list/incoming
	var/tmp/list/rich_edges
	var/tmp/list/pending_wakes
	var/tmp/list/proc_timers
	var/tmp/list/observations
	var/tmp/list/declared_rates
	var/tmp/datum/object_model/behaviour_runtime/behaviour_runtime
	var/tmp/list/clock_states
	var/tmp/list/suspensions
	var/tmp/datum/object_model/cache_state/cache
	var/tmp/datum/object_model/change_state/change
	var/dying = FALSE
	var/prepared = FALSE
	var/cleaned = FALSE

/datum/object_model/state/Destroy()
	owner = null
	owner_field = null
	children = null
	outgoing = null
	incoming = null
	rich_edges = null
	pending_wakes = null
	proc_timers = null
	observations = null
	declared_rates = null
	for(var/domain in clock_states)
		var/datum/object_model/clock_state/C = clock_states[domain]
		if(C && !QDELETED(C))
			qdel(C)
	clock_states = null
	for(var/set_path in suspensions)
		for(var/datum/object_model/suspension/T as anything in suspensions[set_path])
			if(T && !QDELETED(T))
				qdel(T)
	suspensions = null
	cache = null
	if(change)
		qdel(change)
		change = null
	if(behaviour_runtime)
		qdel(behaviour_runtime)
		behaviour_runtime = null
	return ..()

/// A slot's resolver may transfer a surviving child to another authority.
/datum/object_model/slot_def/proc/resolve_destroy(datum/owner, datum/child)
	return null

/// Return TRUE only after a durable latent representation has been stored.
/datum/object_model/slot_def/proc/store_latent(datum/owner, datum/child)
	return FALSE

/// A static declaration also imposes its slot limits on inherited subtypes.
/proc/om_slot_def_for(datum/owner, slot_id)
	if(!owner || !om_declaration_for(owner.type))
		return null
	var/datum/object_model/archetype/A = om_archetype_for(owner.type)
	return A?.slots?[slot_id]

/// Allocate metadata only for a datum participating in the model.
/proc/om_state_for(datum/thing)
	if(!thing || QDELETED(thing))
		return null
	if(!thing.om_state)
		thing.om_state = new /datum/object_model/state
	return thing.om_state

/proc/om_owner(datum/child)
	return child?.om_state?.owner

/proc/om_owner_slot(datum/child)
	return child?.om_state?.owner_slot

/proc/om_is_dying(datum/thing)
	return !thing || QDELETED(thing) || thing.om_state?.dying

/// Return a private copy; callers may freely mutate it.
/proc/om_children(datum/owner, slot_id)
	var/list/result = list()
	var/list/slots = owner?.om_state?.children
	if(!slots)
		return result
	if(!isnull(slot_id))
		var/list/items = slots[slot_id]
		return items ? items.Copy() : result
	for(var/key in slots)
		var/list/items = slots[key]
		result += items
	return result

/// Claim a datum in a named ownership slot. Ownership remains a tree.
/proc/om_claim(datum/owner, slot_id, datum/child)
	if(!owner || !child || owner == child || isnull(slot_id) || om_is_dying(owner) || om_is_dying(child))
		return FALSE
	var/datum/object_model/state/child_state = child.om_state
	if(child_state?.owner == owner && child_state.owner_slot == slot_id)
		return TRUE
	var/datum/object_model/slot_def/slot_definition = om_slot_def_for(owner, slot_id)
	if(om_declaration_for(owner.type) && !slot_definition && copytext(slot_id, 1, 4) != "om:")
		return FALSE
	if(slot_definition)
		if(!istype(child, slot_definition.accepts))
			return FALSE
		var/list/current = owner.om_state?.children?[slot_id]
		if(length(current) >= slot_definition.capacity)
			return FALSE
	child_state = om_state_for(child)
	for(var/datum/ancestor = owner; ancestor; ancestor = om_owner(ancestor))
		if(ancestor == child)
			return FALSE
	if(child_state.owner)
		om_release(child)
		// Releasing an old owner publishes a change and may run user callbacks.
		// A callback can delete the destination or reclaim the child, so do not
		// commit the stale pre-release validation result.
		if(om_is_dying(owner) || om_is_dying(child))
			return FALSE
		if(child_state.owner)
			return child_state.owner == owner && child_state.owner_slot == slot_id
		if(slot_definition)
			var/list/current_after_release = owner.om_state?.children?[slot_id]
			if(length(current_after_release) >= slot_definition.capacity)
				return FALSE
		for(var/datum/ancestor = owner; ancestor; ancestor = om_owner(ancestor))
			if(ancestor == child)
				return FALSE
	var/datum/object_model/state/owner_state = om_state_for(owner)
	if(!owner_state.children)
		owner_state.children = list()
	var/list/items = owner_state.children[slot_id]
	if(!items)
		items = list()
		owner_state.children[slot_id] = items
	items += child
	child_state.owner = owner
	child_state.owner_slot = slot_id
	om_changed(owner, "children")
	om_changed(child, "owner")
	if(copytext(slot_id, 1, 4) != "om:")
		om_bump_revision_if_tracked(owner)
		om_bump_revision_if_tracked(child)
	om_derived_owned_membership_changed(owner, slot_id)
	return TRUE

/// Keep a compile-checked owner field and its lifetime slot in one transaction.
/// Pass the field through NAMEOF(owner, field), and the field value as current.
/// The mirror is installed before om_claim publishes any change.
/proc/om_claim_field(datum/owner, field_name, datum/current, slot_id, datum/child)
	if(!owner || !field_name || !child || om_is_dying(owner) || om_is_dying(child))
		return FALSE
	if(owner.vars[field_name] != current)
		return FALSE
	if(current == child)
		return om_owner(child) == owner && om_owner_slot(child) == slot_id && child.om_state?.owner_field == field_name
	if(current && !QDELETED(current))
		return FALSE
	// A field mirror cannot safely follow a claim from another owner: its
	// release publishes callbacks before this owner's field can be installed.
	if(om_owner(child))
		return FALSE
	owner.vars[field_name] = child
	var/datum/object_model/state/child_state = om_state_for(child)
	child_state.owner_field = field_name
	if(om_claim(owner, slot_id, child))
		return TRUE
	if(owner.vars[field_name] == child)
		owner.vars[field_name] = null
	if(child_state.owner_field == field_name && !child_state.owner)
		child_state.owner_field = null
	return FALSE

/proc/om_release(datum/child)
	var/datum/object_model/state/child_state = child?.om_state
	var/datum/owner = child_state?.owner
	if(!owner)
		return FALSE
	var/list/slots = owner.om_state?.children
	var/old_slot = child_state.owner_slot
	var/old_field = child_state.owner_field
	var/list/items = slots?[old_slot]
	items -= child
	if(!length(items))
		slots -= child_state.owner_slot
	child_state.owner = null
	child_state.owner_slot = null
	child_state.owner_field = null
	if(old_field && owner.vars[old_field] == child)
		owner.vars[old_field] = null
	// The prepared tree has already marked both ends for deletion. Its slot
	// structure still must be detached, but no reader can use these revisions
	// or derived values before the leaf-first delete pass.
	if(om_is_dying(owner) && om_is_dying(child))
		return TRUE
	om_changed(owner, "children")
	om_changed(child, "owner")
	if(copytext(old_slot, 1, 4) != "om:")
		om_bump_revision_if_tracked(owner)
		om_bump_revision_if_tracked(child)
	om_derived_owned_membership_changed(owner, old_slot)
	return TRUE

/// Definition singleton. Subtypes set type paths and override the hooks.
/datum/object_model/relation
	var/from_type = /datum
	var/to_type = /datum
	var/shape = OM_REL_MANY_TO_MANY
	var/exclusive = FALSE
	/// Enforce at most one target for each source, or one source for each target.
	var/source_single = FALSE
	var/target_single = FALSE
	/// An ownership relation uses the existing lifetime tree as its authority.
	var/ownership = OM_REL_OWN_NONE
	/// Framework bookkeeping edges may opt out of task revision changes.
	var/changes_revision = TRUE
	var/on_end_lost = OM_REL_UNLINK
	var/rich = FALSE
	var/edge_type = /datum/object_model/edge
	/// A virtual relation reads an existing authority instead of storing edges.
	/// It cannot be changed with om_link/om_unlink.
	var/virtual = FALSE

/datum/object_model/relation/proc/query_from(datum/source)
	return list()

/datum/object_model/relation/proc/query_to(datum/target)
	return list()

/datum/object_model/relation/proc/virtual_has(datum/source, datum/target)
	return target in query_from(source)

/// Optional stateful edge. Its lifetime authority is its source endpoint.
/datum/object_model/edge
	var/tmp/datum/source
	var/tmp/datum/target
	var/kind

/datum/object_model/edge/Destroy()
	source = null
	target = null
	return ..()

/datum/object_model/relation/proc/on_link(datum/source, datum/target)
	return

/datum/object_model/relation/proc/on_unlink(datum/source, datum/target, reason)
	return

/proc/om_relation_def(kind)
	if(!ispath(kind, /datum/object_model/relation) || kind == /datum/object_model/relation)
		return null
	var/static/list/defs = list()
	var/datum/object_model/relation/definition = defs[kind]
	if(!definition)
		definition = new kind
		defs[kind] = definition
	return definition

/proc/om_linked(datum/source, kind)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(definition?.virtual)
		return definition.query_from(source)
	var/list/items = source?.om_state?.outgoing?[kind]
	var/list/result = items ? items.Copy() : list()
	if(definition?.shape == OM_REL_SYMMETRIC)
		var/list/reverse = source?.om_state?.incoming?[kind]
		if(reverse)
			result |= reverse
	return result

/proc/om_linked_to(datum/target, kind)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(definition?.virtual)
		return definition.query_to(target)
	var/list/items = target?.om_state?.incoming?[kind]
	var/list/result = items ? items.Copy() : list()
	if(definition?.shape == OM_REL_SYMMETRIC)
		var/list/reverse = target?.om_state?.outgoing?[kind]
		if(reverse)
			result |= reverse
	return result

/// Read the first endpoint without copying a stored relation's endpoint list.
/// Intended for declared one-to-one or one-sided single relationships.
/proc/om_first_linked(datum/source, kind)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(definition?.virtual)
		var/list/items = definition.query_from(source)
		return length(items) ? items[1] : null
	var/list/items = source?.om_state?.outgoing?[kind]
	if(length(items))
		return items[1]
	if(definition?.shape == OM_REL_SYMMETRIC)
		items = source?.om_state?.incoming?[kind]
		return length(items) ? items[1] : null
	return null

/proc/om_first_linked_to(datum/target, kind)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(definition?.virtual)
		var/list/items = definition.query_to(target)
		return length(items) ? items[1] : null
	var/list/items = target?.om_state?.incoming?[kind]
	if(length(items))
		return items[1]
	if(definition?.shape == OM_REL_SYMMETRIC)
		items = target?.om_state?.outgoing?[kind]
		return length(items) ? items[1] : null
	return null

/proc/om_has_link(datum/source, kind, datum/target)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(definition?.virtual)
		return definition.virtual_has(source, target)
	var/list/items = source?.om_state?.outgoing?[kind]
	if(items && (target in items))
		return TRUE
	if(definition?.shape == OM_REL_SYMMETRIC)
		items = source?.om_state?.incoming?[kind]
		return items && (target in items)
	return FALSE

/proc/om_edge(datum/source, kind, datum/target)
	var/list/by_kind = source?.om_state?.rich_edges?[kind]
	return by_kind?[target]

/// Link one directed edge. Symmetric kinds are queried from either end.
/proc/om_link(datum/source, kind, datum/target)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(definition?.virtual)
		CRASH("virtual relation [kind] is changed by its authority, not om_link")
	if(!definition || !source || !target || om_is_dying(source) || om_is_dying(target))
		return FALSE
	if(!istype(source, definition.from_type) || !istype(target, definition.to_type))
		return FALSE
	if(om_has_link(source, kind, target))
		return TRUE
	var/list/prior_sources = om_linked_to(target, kind)
	var/list/prior_targets = om_linked(source, kind)
	if(definition.ownership == OM_REL_OWN_SOURCE)
		if(isatom(source) || !definition.source_single || om_owned_by(target, source))
			return FALSE
		var/datum/current_owner = om_owner(source)
		if(current_owner && current_owner != target && !(current_owner in prior_targets))
			return FALSE
	else if(definition.ownership == OM_REL_OWN_TARGET)
		if(isatom(target) || !definition.target_single || om_owned_by(source, target))
			return FALSE
		var/datum/current_owner = om_owner(target)
		if(current_owner && current_owner != source && !(current_owner in prior_sources))
			return FALSE
	if(definition.shape == OM_REL_ONE_TO_ONE || definition.target_single || definition.exclusive)
		for(var/datum/prior in prior_sources)
			om_unlink(prior, kind, target, OM_REL_REPLACED)
	if(definition.shape == OM_REL_ONE_TO_ONE || definition.source_single || definition.exclusive)
		for(var/datum/prior in prior_targets)
			om_unlink(source, kind, prior, OM_REL_REPLACED)
	if(om_is_dying(source) || om_is_dying(target))
		return FALSE
	// Unlink hooks may reentrantly install a different edge while replacement is
	// in progress. Do not append a second edge past a single-endpoint limit.
	if(om_has_link(source, kind, target))
		return TRUE
	if((definition.shape == OM_REL_ONE_TO_ONE || definition.target_single || definition.exclusive) && om_first_linked_to(target, kind))
		return FALSE
	if((definition.shape == OM_REL_ONE_TO_ONE || definition.source_single || definition.exclusive) && om_first_linked(source, kind))
		return FALSE
	if(definition.ownership == OM_REL_OWN_SOURCE && !om_claim(target, "om:relation:[kind]", source))
		return FALSE
	if(definition.ownership == OM_REL_OWN_TARGET && !om_claim(source, "om:relation:[kind]", target))
		return FALSE
	// Claim publishes ownership changes. A callback can delete an endpoint,
	// release the claim, or install a competing edge before we store this one.
	if(om_is_dying(source) || om_is_dying(target))
		return FALSE
	if(definition.ownership == OM_REL_OWN_SOURCE && (om_owner(source) != target || om_owner_slot(source) != "om:relation:[kind]"))
		return FALSE
	if(definition.ownership == OM_REL_OWN_TARGET && (om_owner(target) != source || om_owner_slot(target) != "om:relation:[kind]"))
		return FALSE
	if(om_has_link(source, kind, target))
		return TRUE
	if((definition.shape == OM_REL_ONE_TO_ONE || definition.target_single || definition.exclusive) && om_first_linked_to(target, kind))
		if(definition.ownership == OM_REL_OWN_SOURCE && !length(om_linked(source, kind)))
			om_release(source)
		else if(definition.ownership == OM_REL_OWN_TARGET && !length(om_linked_to(target, kind)))
			om_release(target)
		return FALSE
	if((definition.shape == OM_REL_ONE_TO_ONE || definition.source_single || definition.exclusive) && om_first_linked(source, kind))
		if(definition.ownership == OM_REL_OWN_SOURCE && !length(om_linked(source, kind)))
			om_release(source)
		else if(definition.ownership == OM_REL_OWN_TARGET && !length(om_linked_to(target, kind)))
			om_release(target)
		return FALSE
	var/datum/object_model/edge/linked_edge
	if(definition.rich)
		linked_edge = new definition.edge_type
		linked_edge.source = source
		linked_edge.target = target
		linked_edge.kind = kind
		// Claim the edge before exposing the relation. Claim callbacks may
		// install another edge, but cannot observe an unhooked provisional one.
		if(!om_claim(source, "om:edges", linked_edge))
			qdel(linked_edge)
			return FALSE
		if(om_is_dying(source) || om_is_dying(target) || QDELETED(linked_edge) || om_owner(linked_edge) != source || om_has_link(source, kind, target) || ((definition.shape == OM_REL_ONE_TO_ONE || definition.target_single || definition.exclusive) && om_first_linked_to(target, kind)) || ((definition.shape == OM_REL_ONE_TO_ONE || definition.source_single || definition.exclusive) && om_first_linked(source, kind)))
			if(!QDELETED(linked_edge))
				if(om_owner(linked_edge) == source)
					om_release(linked_edge)
				qdel(linked_edge)
			return !om_is_dying(source) && !om_is_dying(target) && om_has_link(source, kind, target)
	var/datum/object_model/state/source_state = om_state_for(source)
	var/datum/object_model/state/target_state = om_state_for(target)
	if(!source_state.outgoing)
		source_state.outgoing = list()
	if(!target_state.incoming)
		target_state.incoming = list()
	var/list/out = source_state.outgoing[kind]
	if(!out)
		out = list()
		source_state.outgoing[kind] = out
	var/list/incoming_list = target_state.incoming[kind]
	if(!incoming_list)
		incoming_list = list()
		target_state.incoming[kind] = incoming_list
	out += target
	incoming_list += source
	if(linked_edge)
		if(!source_state.rich_edges)
			source_state.rich_edges = list()
		var/list/by_kind = source_state.rich_edges[kind]
		if(!by_kind)
			by_kind = list()
			source_state.rich_edges[kind] = by_kind
		by_kind[target] = linked_edge
	// Install external mirrors and signals before publishing the edge. A
	// synchronous observer may remove it during the publication.
	definition.on_link(source, target)
	if(om_is_dying(source) || om_is_dying(target) || !om_has_link(source, kind, target) || (definition.rich && om_edge(source, kind, target) != linked_edge))
		return FALSE
	om_changed(source, "relations")
	if(om_is_dying(source) || om_is_dying(target) || !om_has_link(source, kind, target) || (definition.rich && om_edge(source, kind, target) != linked_edge))
		return FALSE
	om_changed(target, "relations")
	if(om_is_dying(source) || om_is_dying(target) || !om_has_link(source, kind, target) || (definition.rich && om_edge(source, kind, target) != linked_edge))
		return FALSE
	if(definition.changes_revision)
		om_bump_revision_if_tracked(source)
		om_bump_revision_if_tracked(target)
	om_derived_relation_membership_changed(source, kind, target)
	// Hooks may synchronously unlink or destroy an endpoint. Report the
	// relationship that actually survived the hook.
	return !om_is_dying(source) && !om_is_dying(target) && om_has_link(source, kind, target)

/proc/om_unlink(datum/source, kind, datum/target, reason = OM_REL_EXPLICIT)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(definition?.virtual)
		CRASH("virtual relation [kind] is changed by its authority, not om_unlink")
	if(!om_has_link(source, kind, target))
		return FALSE
	var/list/direct = source.om_state.outgoing?[kind]
	if(!direct || !(target in direct))
		var/datum/previous_source = source
		source = target
		target = previous_source
	var/list/out = source.om_state.outgoing[kind]
	out -= target
	if(!length(out))
		source.om_state.outgoing -= kind
	var/list/incoming_list = target.om_state.incoming[kind]
	incoming_list -= source
	if(!length(incoming_list))
		target.om_state.incoming -= kind
	var/list/by_kind = source.om_state.rich_edges?[kind]
	var/datum/object_model/edge/edge = by_kind?[target]
	if(edge)
		by_kind -= target
		if(!length(by_kind))
			source.om_state.rich_edges -= kind
	// Hooks remove external mirrors and signal registrations for the old edge.
	// Any later ownership-release callback may install a new edge.
	definition.on_unlink(source, target, reason)
	if(edge)
		om_release(edge)
		qdel(edge)
	if(reason != OM_REL_DESTROYING)
		if(definition.ownership == OM_REL_OWN_SOURCE && !om_has_link(source, kind, target) && om_owner(source) == target && om_owner_slot(source) == "om:relation:[kind]")
			om_release(source)
		else if(definition.ownership == OM_REL_OWN_TARGET && !om_has_link(source, kind, target) && om_owner(target) == source && om_owner_slot(target) == "om:relation:[kind]")
			om_release(target)
	// A hook or release callback may already have installed a replacement.
	// Its link published the final relation state; do not publish stale removal.
	if(om_has_link(source, kind, target))
		return TRUE
	// Both endpoints in one prepared destroy tree are already terminal. Keep
	// the unlink hook and edge cleanup above, but skip obsolete notifications,
	// revisions and derived invalidation for this dead pair.
	if(reason == OM_REL_DESTROYING && om_is_dying(source) && om_is_dying(target))
		return TRUE
	om_changed(source, "relations")
	if(om_has_link(source, kind, target))
		return TRUE
	om_changed(target, "relations")
	if(om_has_link(source, kind, target))
		return TRUE
	if(definition.changes_revision)
		om_bump_revision_if_tracked(source)
		om_bump_revision_if_tracked(target)
	om_derived_relation_membership_changed(source, kind, target)
	if(reason == OM_REL_DESTROYING)
		if(om_is_dying(target) && !om_is_dying(source) && definition.on_end_lost == OM_REL_DESTROY_SOURCE)
			om_destroy(source)
		if(om_is_dying(source) && !om_is_dying(target) && definition.on_end_lost == OM_REL_DESTROY_TARGET)
			om_destroy(target)
	return TRUE

/// Replace one outgoing endpoint. om_link() validates the candidate before
/// unlinking its predecessor; if a reentrant hook defeats the commit, restore
/// the former live endpoint unless another callback has claimed the slot.
/proc/om_replace_related(datum/source, kind, datum/new_target)
	var/datum/object_model/relation/definition = om_relation_def(kind)
	if(!definition || definition.virtual || !definition.source_single || om_is_dying(source))
		return FALSE
	var/datum/old_target = om_first_linked(source, kind)
	if(old_target == new_target)
		return TRUE
	if(!new_target)
		return !old_target || om_unlink(source, kind, old_target)
	if(!istype(source, definition.from_type) || !istype(new_target, definition.to_type) || om_is_dying(new_target))
		return FALSE
	if(om_link(source, kind, new_target))
		return TRUE
	if(old_target && !om_is_dying(old_target) && !om_is_dying(source) && !om_first_linked(source, kind))
		om_link(source, kind, old_target)
	return FALSE

/// A service-scoped queue keeps hook-requested destruction outside the
/// transaction currently running, including when callers use bare qdel().
/datum/object_model/destroy_queue
	var/list/pending = list()
	var/draining = FALSE
	var/transactions = 0

/datum/object_model/destroy_queue/om_kind()
	return OM_KIND_SERVICE

/proc/om_destroy_queue()
	var/static/datum/object_model/destroy_queue/queue
	if(!queue)
		queue = new
	return queue

/datum/object_model/destroy_queue/proc/drain()
	if(draining || transactions)
		return
	draining = TRUE
	var/processed = 0
	while(length(pending))
		if(++processed > 10000)
			CRASH("object model destroy worklist exceeded 10000 objects")
		var/datum/next = pending[1]
		pending.Cut(1, 2)
		if(next && !QDELETED(next) && !next.om_state?.dying)
			qdel(next)
	draining = FALSE

/// True when `candidate` is inside `root`'s lifetime tree.
/proc/om_owned_by(datum/candidate, datum/root)
	for(var/datum/current = candidate; current; current = om_owner(current))
		if(current == root)
			return TRUE
	return FALSE

/// Resolve surviving children before marking the tracked tree. A failed
/// transfer stays in the tree and takes the delete fallback.
/proc/om_resolve_children(datum/owner, datum/root, datum/spill_owner)
	var/list/slots = owner.om_state?.children?.Copy()
	for(var/slot_id in slots)
		var/datum/object_model/slot_def/slot_definition = om_slot_def_for(owner, slot_id)
		for(var/datum/child in om_children(owner, slot_id))
			var/policy = slot_definition?.on_destroy || OM_SLOT_DELETE
			var/datum/new_owner
			if(policy == OM_SLOT_SPILL)
				new_owner = spill_owner
			else if(policy == OM_SLOT_TRANSFER || policy == OM_SLOT_KEEP_WITH)
				new_owner = slot_definition.resolve_destroy(owner, child)
			else if(policy == OM_SLOT_TO_LATENT && slot_definition?.store_latent(owner, child))
				continue // stored child remains to be deleted, leaf first
			if(new_owner && !om_is_dying(new_owner) && !om_owned_by(new_owner, root))
				om_claim(new_owner, slot_id, child)

/// Called after the qdel guard but before COMSIG_QDELETING. Returns TRUE
/// when this transaction opened the worklist barrier and must close it.
/proc/om_prepare_destroy(datum/root)
	var/datum/object_model/state/root_state = root?.om_state
	if(!root_state || root_state.prepared)
		return FALSE
	var/datum/object_model/destroy_queue/queue = om_destroy_queue()
	queue.transactions++
	// Free the outer slot before trying SPILL into it; descendants can then
	// transfer to the nearest surviving authority without a false capacity hit.
	var/datum/spill_owner = om_owner(root)
	om_release(root)
	var/list/stack = list(root)
	var/list/expanded = list(FALSE)
	var/list/postorder = list()
	while(length(stack))
		var/index = length(stack)
		var/datum/current = stack[index]
		var/is_expanded = expanded[index]
		stack.Cut(index, index + 1)
		expanded.Cut(index, index + 1)
		if(is_expanded)
			postorder += current
			continue
		om_resolve_children(current, root, spill_owner)
		stack += current
		expanded += TRUE
		var/list/children = om_children(current)
		for(var/i = length(children); i >= 1; i--)
			stack += children[i]
			expanded += FALSE
	// Every descendant is now known; hooks cannot relink any of them.
	for(var/datum/current in postorder)
		var/datum/object_model/state/state = current.om_state
		state.prepared = TRUE
		state.dying = TRUE
	for(var/datum/current in postorder)
		var/datum/object_model/state/state = current.om_state
		var/list/outgoing = state.outgoing?.Copy()
		for(var/kind in outgoing)
			for(var/datum/target in om_linked(current, kind))
				om_unlink(current, kind, target, OM_REL_DESTROYING)
		var/list/incoming = state.incoming?.Copy()
		for(var/kind in incoming)
			for(var/datum/source in om_linked_to(current, kind))
				om_unlink(source, kind, current, OM_REL_DESTROYING)
	// Detach before qdel so child transactions never recurse through these slots.
	for(var/datum/current in postorder)
		om_release(current)
	for(var/i = 1; i < length(postorder); i++)
		var/datum/child = postorder[i]
		if(!QDELETED(child))
			qdel(child)
	return TRUE

/// Called from phase 4. The prepare pass handled relationships; this releases
/// sparse behaviour state and metadata before legacy declared-link cleanup.
/proc/om_before_destroy(datum/thing)
	om_cache_clear(thing)
	var/datum/object_model/state/state = thing?.om_state
	if(!state || state.cleaned)
		return
	state.cleaned = TRUE
	state.dying = TRUE
	om_behaviour_release(thing)
	// Defensive path for a datum whose state was installed after phase 0.
	var/list/outgoing = state.outgoing?.Copy()
	for(var/kind in outgoing)
		for(var/datum/target in om_linked(thing, kind))
			om_unlink(thing, kind, target, OM_REL_DESTROYING)
	var/list/incoming = state.incoming?.Copy()
	for(var/kind in incoming)
		for(var/datum/source in om_linked_to(thing, kind))
			om_unlink(source, kind, thing, OM_REL_DESTROYING)
	om_release(thing)
	thing.om_state = null
	qdel(state)

/// Close a prepare-pass barrier after the transaction's scrub phase.
/proc/om_finish_destroy(prepared)
	if(!prepared)
		return
	var/datum/object_model/destroy_queue/queue = om_destroy_queue()
	queue.transactions--
	queue.drain()

/// Queue destruction requested from hooks, avoiding recursive hook cascades.
/proc/om_destroy(datum/thing)
	if(!thing || QDELETED(thing) || thing.om_state?.dying)
		return FALSE
	var/datum/object_model/destroy_queue/queue = om_destroy_queue()
	if(!(thing in queue.pending))
		queue.pending += thing
	queue.drain()
	return TRUE
