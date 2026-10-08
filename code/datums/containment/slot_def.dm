// Legacy slot paths retain their instance identities while inheriting the engine implementation.
/datum/om/relation/slot
	parent_type = /datum/relation_definition/slot
	abstract_type = /datum/om/relation/slot

/datum/om/relation/slot/declared
	name = "declared slot"
	capacity_model = SLOT_CAPACITY_COUNT
	drop_policy = SLOT_DROP_SPILL
	/// A slot() entry's accepts: the type a thing must be, or a list of them.
	var/accepts_type

/datum/om/relation/slot/declared/refusal(atom/holder, atom/movable/thing, mob/actor)
	. = declared_slot_type_refusal(accepts_type, thing)
	if(.)
		return .
	return ..()

/// A declared slot that is sealed (slot(..., exposure = SLOT_EXPOSURE_SEALED)): what is inside lives in the holder's shell, as a pod's patient
/// does: no gas reaches them, no heat or blast crosses it (containment.md section 10). Spilled onto the floor when the holder is destroyed.
/datum/om/relation/slot/declared/sealed
	name = "sealed slot"
	exposure = SLOT_EXPOSURE_SEALED
	reaches_mobs = TRUE
	heat_transmission = 0
	radiation_transmission = 1
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)


/datum/om/relation/slot/declared/set_declared_accepts(accepts)
	accepts_type = accepts

/datum/containment_slot_factory/create(exposure)
	return exposure == SLOT_EXPOSURE_SEALED ? new /datum/om/relation/slot/declared/sealed : new /datum/om/relation/slot/declared

/atom/construction_slot_declarations(list/taken, list/defs, existing_count)
	. = list()
	for(var/cap_id in list(CAP_CONSTRUCTION, CAP_DEPLOYMENT))
		var/datum/capability/construction/graph_def = cap_of(src, cap_id)
		var/datum/state_graph/G = graph_def?.graph
		if(!G)
			continue
		var/list/puts = list()
		for(var/datum/graph_edge/edge as anything in G.edges)
			for(var/datum/entry/part/effect/put_in/P in edge.parts)
				var/id = P.args["slot"]
				if(!isnull(id) && !(istext(id) && (id in vars)))
					puts[id] = (puts[id] || 0) + 1
		for(var/id in puts)
			if(taken[id])
				continue
			taken[id] = TRUE
			. += declared_slot_def(type, id, puts[id], G.space, null, !length(defs) && !existing_count && !length(.))

/obj/item/containment_constraint_refusal(kind, atom/movable/thing, mob/actor)
	return dq_constraint_refusal(src, kind, thing, actor)
