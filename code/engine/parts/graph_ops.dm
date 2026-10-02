// State-graph edges as ops (doc/rewrite/final_api.html, section 12 "Construction", foundation X4; section 19 "E2, parts").
//
// A graph capability (construction(), deployment()) brings one op per edge and one per way back, generated from the compiled graph
// (code/engine/declare/graph.dm), so an author writes a graph and nothing else:
//
//   construction.build:<stage>[.<key>]   the edge: its own parts (a tool, an item, a stack, a wait, put_in, consumes), the condition that the
//                                        instance is at one of the edge's `from` stages, and a last effect that moves the instance along the edge
//                                        and writes the LEDGER entry of the transition: what the edge's reservations took in (stack units with
//                                        their material, a consumed item, what went into a slot).
//   construction.undo:<stage>[.<key>]    the way back: the same input reversed (a tool edge undoes with the same tool and the same wait, any
//                                        other with a hand), or the edge's own `undo = list(parts)`; none for `undo = null`. It is available only
//                                        while the transition on top of the instance's HISTORY is this edge, so a stage with two ways in undoes to
//                                        the one actually taken. Its effect pops the history and REFUNDS that transition's ledger entry.
//   construction.dismantle               dismantle(parts...): the parts, then everything the instance took in is refunded, newest first, and it ends.
//
// The ledger entry is written when the edge's reservations are made (they are open while the effects run), and the commit that follows spends
// them; a refund puts back exactly what the entry names, so what an undo returns is what that edge took, whichever path led there.

/// A condition and requirement: the instance is at one of `stages` of its graph (ANY_STAGE: any), and, for an undo, the transition on top of its
/// history is the edge into `into` with `key`. A pure read of the graph state (it never makes the instance's activation).
/datum/entry/part/req/graph_at
	part_name = "graph_at"
	default_reason = /datum/msg/op/not_available

/proc/req_graph_at(list/stages, into = null, key = null, cap_id = CAP_CONSTRUCTION)
	return part_make(/datum/entry/part/req/graph_at, list("stages" = stages, "into" = into, "key" = key, "cap" = cap_id, "undo" = !isnull(into)))

/datum/entry/part/req/graph_at/holds(datum/act/op/A)
	var/datum/E = A.holder
	var/list/stages = src.args["stages"]
	var/cap_id = src.args["cap"]
	if(!(ANY_STAGE in stages) && !(graph_current(E, cap_id) in stages))
		return FALSE
	if(!src.args["undo"])
		return TRUE
	var/list/top = graph_top(E, cap_id)
	return length(top) && top[3] == src.args["into"] && top[1] == src.args["key"]

/datum/entry/part/req/graph_at/read_keys(datum/act/op/A)
	return list(list(A.holder, "graph:[src.args["cap"]]"))

/// Two graph conditions that cannot hold together: disjoint stage sets, or two undos for different transitions.
/proc/graph_at_exclusive(datum/entry/part/req/graph_at/a, datum/entry/part/req/graph_at/b)
	var/list/sa = a.args["stages"]
	var/list/sb = b.args["stages"]
	if((ANY_STAGE in sa) || (ANY_STAGE in sb))
		return FALSE
	if(!length(sa & sb))
		return TRUE
	return a.args["undo"] && b.args["undo"] && (a.args["into"] != b.args["into"] || a.args["key"] != b.args["key"])

/// The transition on top of E's history: list(edge key, from stage, to stage, ledger), or null. Read without making the activation; a type
/// placed part-built reads the last transition of the path it is seeded along.
/proc/graph_top(datum/E, cap_id = CAP_CONSTRUCTION)
	var/datum/cap_data/graph_state/S = graph_state(E, cap_id, FALSE)
	if(S && length(S.history))
		return S.history[length(S.history)]
	if(S?.seeded)
		return null
	var/datum/capability/construction/def = cap_of(E, cap_id)
	if(!def?.graph || isnull(def.start) || def.start == def.graph.start)
		return null
	var/list/path = graph_seed_path(def)
	if(length(path) < 2)
		return null
	var/datum/graph_edge/edge = graph_first_edge(def.graph, path[length(path) - 1], path[length(path)])
	return list(edge?.key, path[length(path) - 1], path[length(path)], null)

// ---- the generated ops ----

/// The ops a graph capability brings: its edges, their ways back and the dismantle.
/proc/graph_op_entries(datum/state_graph/G, datum/capability/construction/def)
	. = list()
	var/cap_id = def.cap_id
	for(var/datum/graph_edge/edge as anything in G.edges)
		. += graph_build_op(G, edge, cap_id)
	for(var/datum/graph_edge/edge as anything in G.edges)
		var/list/undo_parts = graph_undo_parts(edge)
		if(length(undo_parts))
			. += graph_undo_op(G, edge, cap_id, undo_parts)
	if(G.dismantle_entry)
		. += graph_dismantle_op(G, cap_id)

/// The op key an edge is declared under, without the capability's prefix ("build:door_wired", "build:door_finished.kit").
/proc/graph_edge_base_key(datum/graph_edge/edge, verb)
	return "[verb]:[stage_key(edge.into)][edge.key ? ".[edge.key]" : ""]"

/// The label an edge's op shows: "Build wired" / "Undo finished".
/proc/graph_edge_label(datum/graph_edge/edge, verb)
	var/text = replacetext(copytext(stage_key(edge.into) || "", (findtext(stage_key(edge.into) || "", "_") || 0) + 1), "_", " ")
	return "[verb] [text]"

/proc/graph_build_op(datum/state_graph/G, datum/graph_edge/edge, cap_id)
	var/list/parts = list(when(req_graph_at(edge.from, null, null, cap_id)), label(graph_edge_label(edge, "Build")))
	for(var/part in entry_flatten(edge.parts))
		if(!istype(part, /datum/entry/part/undone))
			parts += part
	if(!isnull(G.bay))
		parts += at(G.bay)
	parts += part_make(/datum/entry/part/effect/graph_advance, list("into" = edge.into, "key" = edge.key, "cap" = cap_id))
	return entry_make(ENTRY_OP, graph_edge_base_key(edge, "build"), null, parts)

/// The input parts of an edge's way back: an explicit undo = list(parts) as written, else (derived) the edge's tool and its wait again, or a hand
/// for any other input. Empty when the edge declared undo = null.
/proc/graph_undo_parts(datum/graph_edge/edge)
	if(edge.has_undo)
		return entry_flatten(edge.undo_parts)
	. = list()
	var/derived_input = FALSE
	for(var/part in entry_flatten(edge.parts))
		if(istype(part, /datum/entry/part/bind))
			var/datum/entry/part/bind/B = part
			if(derived_input)
				continue
			derived_input = TRUE
			. += (B.bind_kind == BIND_TOOL) ? B : hand()
		else if(istype(part, /datum/entry/part/wait))
			. += part
	if(!derived_input)
		. += hand()

/proc/graph_undo_op(datum/state_graph/G, datum/graph_edge/edge, cap_id, list/undo_parts)
	var/list/parts = list(when(req_graph_at(list(edge.into), edge.into, edge.key, cap_id)), label(graph_edge_label(edge, "Undo")))
	parts += undo_parts
	for(var/part in entry_flatten(edge.parts))
		if(istype(part, /datum/entry/part/undone))
			parts += part
	if(!isnull(G.bay))
		parts += at(G.bay)
	parts += part_make(/datum/entry/part/effect/graph_undo, list("cap" = cap_id))
	return entry_make(ENTRY_OP, graph_edge_base_key(edge, "undo"), null, parts)

/proc/graph_dismantle_op(datum/state_graph/G, cap_id)
	var/list/parts = list(label("Dismantle"))
	parts += entry_flatten(G.dismantle_entry.children)
	if(!isnull(G.bay))
		parts += at(G.bay)
	parts += part_make(/datum/entry/part/effect/graph_dismantle, list("cap" = cap_id))
	return entry_make(ENTRY_OP, "dismantle", null, parts)

/datum/capability/construction/entries()
	if(!graph)
		return null
	return graph_op_entries(graph, src)

// ---- the effects ----

/// Moves the instance along an edge and writes the transition's ledger entry.
/datum/entry/part/effect/graph_advance
	part_name = "graph_advance"

/datum/entry/part/effect/graph_advance/run_effect(datum/act/op/A)
	var/datum/E = A.holder
	if(!graph_advance(E, src.args["into"], src.args["key"], graph_ledger_of(A), src.args["cap"]))
		return OP_FAILED
	return OP_OK

/// What the running op's reservations and put_in() effects take in: the ledger entry of its transition. The reservations are open (the commit
/// follows the effects), so it names exactly what the edge is about to spend.
/proc/graph_ledger_of(datum/act/op/A)
	var/list/rows = list()
	var/material = null
	for(var/datum/reservation/R as anything in A.reservations)
		switch(R.res_id)
			if(RES_STACK)
				var/units_material = op_var(R.held, "material")
				rows += list(list("res" = RES_STACK, "n" = R.amount, "type" = R.held?.type, "material" = units_material, "moved" = R.moved))
				if(isnull(material))
					material = units_material
			if(RES_ITEM)
				rows += list(list("res" = RES_ITEM, "type" = R.held?.type))
			if(RES_COOLDOWN)
				continue
			else
				rows += list(list("res" = R.res_id, "n" = R.amount))
	for(var/datum/entry/part/effect/put_in/P in A.oplan?.effects)
		rows += list(list("res" = "slot", "slot" = P.args["slot"]))
	return list("material" = material, "rows" = rows)

/// Pops the history and refunds the transition's ledger entry.
/datum/entry/part/effect/graph_undo
	part_name = "graph_undo"

/datum/entry/part/effect/graph_undo/run_effect(datum/act/op/A)
	var/datum/E = A.holder
	var/list/popped = graph_undo(E, src.args["cap"])
	if(!popped)
		return OP_FAILED
	graph_refund(E, popped[2], A.actor)
	for(var/datum/entry/part/undone/handler as anything in A.oplan?.undone)
		op_call(A, handler.args["handler"])
	return OP_OK

/// The whole thing is taken apart: everything the instance took in is refunded, newest first, and it ends.
/datum/entry/part/effect/graph_dismantle
	part_name = "graph_dismantle"

/datum/entry/part/effect/graph_dismantle/run_effect(datum/act/op/A)
	var/datum/E = A.holder
	for(var/list/ledger in graph_ledger_all(E, src.args["cap"]))
		graph_refund(E, ledger, A.actor)
	var/atom/movable/AM = E
	if(istype(AM))
		consume(AM, A.actor)
	return OP_OK

/// Puts back what a ledger entry names, where the holder is: stack units and consumed items as new things, the contents of a slot out of it.
/proc/graph_refund(datum/E, list/ledger, mob/actor)
	var/turf/where = get_turf(E)
	if(!where)
		return
	for(var/list/row in ledger?["rows"])
		switch(row["res"])
			if(RES_STACK)
				if(row["moved"] || !ispath(row["type"], /obj/item))
					continue
				var/item_path = row["type"]
				var/obj/item/refunded = ispath(item_path, /obj/item/stack) ? new item_path(where, row["n"]) : new item_path(where)
				if(!isnull(row["material"]) && ("material" in refunded.vars))
					refunded.vars["material"] = row["material"] // ALLOW(api): the refund restores the material the ledger recorded
				if(!ispath(item_path, /obj/item/stack) && ("amount" in refunded.vars))
					refunded.vars["amount"] = row["n"] // ALLOW(api): the refund restores the units the ledger recorded
			if(RES_ITEM)
				if(ispath(row["type"], /atom/movable))
					var/refunded_type = row["type"]
					new refunded_type(where)
			if("slot")
				var/atom/holder = E
				if(!istype(holder))
					continue
				for(var/atom/movable/thing as anything in holder.slot_contents(row["slot"]))
					if(holder.slot_remove(thing, where, actor))
						TEST_REC_TRANSFER(thing, holder, where, row["slot"])
