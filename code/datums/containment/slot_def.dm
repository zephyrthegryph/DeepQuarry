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
