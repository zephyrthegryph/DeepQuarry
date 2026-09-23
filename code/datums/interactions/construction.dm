/**
 * Construction graphs (doc/rewrite/interactions.md §10).
 *
 * A graph is a per-type singleton: states (frame, wired, board installed,
 * panel closed...) and edges between them. Each edge is an interaction
 * (/datum/interaction/construction): tool requirements through the P2
 * predicate, a cost through use_tool() (the tool, its fuel and the wait), and
 * an effect that changes the state and takes or gives materials. The target
 * stores only its current state id, in the var the graph names (`state_var`),
 * or its graph derives the state from what the target already has
 * (state_of()).
 *
 * An atom offers a graph by setting `construction_graph` to the graph's type.
 * The resolver then offers the edges leaving the target's current state as
 * interactions, and examine adds a "Next: weld the frame (needs a welder)" line
 * for each.
 *
 *	/datum/construction_graph/example
 *		id = "example"
 *		states = list("frame", "welded")
 *		initial_states = list("frame")
 *		edge_types = list(/datum/interaction/construction/example_weld)
 *
 *	/datum/interaction/construction/example_weld
 *		from_state = "frame"
 *		to_state = "welded"
 *		step_text = "weld the frame"
 *		tool = TOOL_WELDER
 *		duration = 2 SECONDS
 *
 * Generated graphs (the mech chassis tables) add their edges in build().
 */

/// The construction graph type this atom follows, or null. A type var: it costs nothing per instance.
/atom/var/construction_graph

/// Graph type -> shared singleton. Abstract types (no id) are skipped.
GLOBAL_LIST_INIT(construction_graphs, init_construction_graphs())
/proc/init_construction_graphs()
	var/list/graphs = list()
	for(var/datum/construction_graph/path as anything in subtypesof(/datum/construction_graph))
		if(!initial(path.id))
			continue
		graphs[path] = new path
	return graphs

/// The graph `target` follows, or null.
/proc/construction_graph_of(atom/target)
	var/path = target?.construction_graph
	return path ? GLOB.construction_graphs[path] : null

/// The edges leaving `target`'s current state: the resolver offers these as interactions.
/proc/construction_edges_for(atom/target)
	var/datum/construction_graph/graph = construction_graph_of(target)
	return graph ? graph.edges_for(target) : list()

/// The construction edge with this id, or null (the Menu runs interactions by id).
/proc/construction_edge_by_id(id)
	for(var/path in GLOB.construction_graphs)
		var/datum/construction_graph/graph = GLOB.construction_graphs[path]
		var/datum/interaction/construction/edge = graph.edges_by_id[id]
		if(edge)
			return edge
	return null

/datum/construction_graph
	/// Stable id; edge ids start with it.
	var/id
	/// Every state id, in build order. Numbers and text both work.
	var/list/states
	/// The states a new target can start in. Every state must be reachable from one of them.
	var/list/initial_states
	/// Hand-written edges: /datum/interaction/construction types, made once for this graph.
	var/list/edge_types
	/// Requirements added to every edge (REQ_* clauses), e.g. who can build here at all.
	var/list/edge_requires
	/// The target var holding the state id. Null when state_of() works it out instead.
	var/state_var = "construction_state"
	/// All edges, as shared singletons.
	var/tmp/list/edges
	/// "[state]" -> the edges leaving it.
	var/tmp/list/edges_by_state
	/// Edges with from_state CONSTRUCTION_ANY_STATE: each one's leaves() decides.
	var/tmp/list/wildcard_edges
	/// Edge id -> edge.
	var/tmp/list/edges_by_id

/datum/construction_graph/New()
	..()
	edges = list()
	edges_by_state = list()
	wildcard_edges = list()
	edges_by_id = list()
	for(var/path in edge_types)
		add_edge(new path)
	build()

/// Generated graphs add their edges here, with add_edge().
/datum/construction_graph/proc/build()
	return

/// Registers an edge with this graph and gives it an id and a name.
/datum/construction_graph/proc/add_edge(datum/interaction/construction/edge)
	edge.graph = src
	if(length(edge_requires))
		edge.requires = (edge.requires || list()) + edge_requires
	if(!edge.id)
		edge.id = "[id]:[edge.from_state]>[isnull(edge.to_state) ? "?" : edge.to_state]:[edge.tool || edge.item_key()]"
	var/base_id = edge.id
	var/n = 1
	while(edges_by_id[edge.id])
		n++
		edge.id = "[base_id]#[n]"
	if(!edge.name)
		edge.name = capitalize(edge.step_text)
	edges += edge
	edges_by_id[edge.id] = edge
	if(edge.from_state == CONSTRUCTION_ANY_STATE)
		wildcard_edges += edge
	else
		LAZYADD(edges_by_state["[edge.from_state]"], edge)
	return edge

/// The target's current state id, or null when it is not on this graph right now.
/datum/construction_graph/proc/state_of(atom/target)
	return state_var ? target.vars[state_var] : null

/// Stores the state id on the target.
/datum/construction_graph/proc/set_state(atom/target, state)
	if(state_var && state != CONSTRUCTION_DONE)
		target.vars[state_var] = state

/// Called when a step starts, before its cost is paid (click cooldown, touching the target).
/datum/construction_graph/proc/on_step_started(atom/target, mob/actor, obj/item/held)
	return

/// The edges leaving `state`.
/datum/construction_graph/proc/edges_leaving(state)
	. = list()
	if(isnull(state))
		return
	var/list/fixed = edges_by_state["[state]"]
	if(fixed)
		. += fixed
	for(var/datum/interaction/construction/edge as anything in wildcard_edges)
		if(edge.leaves(state))
			. += edge

/// The edges leaving the target's current state.
/datum/construction_graph/proc/edges_for(atom/target)
	return edges_leaving(state_of(target))

/**
 * Called after an edge ran (the state is already stored). `target` may be gone
 * or replaced when the edge finished the construction. Default: redraw.
 */
/datum/construction_graph/proc/on_traversed(atom/target, mob/actor, datum/interaction/construction/edge, before, after)
	if(!QDELETED(target))
		target.update_icon()

/**
 * Problems with this graph, as text: unknown states, states no edge reaches,
 * edges that leave or reach no state, requirements that don't compile. Empty
 * when the graph is valid. Unit tests call this for every graph.
 */
/datum/construction_graph/proc/validate()
	. = list()
	if(!length(states))
		. += "[id]: no states"
		return
	var/list/known = list()
	for(var/state in states)
		known["[state]"] = TRUE
	if(!length(initial_states))
		. += "[id]: no initial states"
	for(var/state in initial_states)
		if(!known["[state]"])
			. += "[id]: initial state [state] is not a state"
	for(var/datum/interaction/construction/edge as anything in edges)
		if(edge.from_state != CONSTRUCTION_ANY_STATE && !known["[edge.from_state]"])
			. += "[edge.id]: leaves unknown state [edge.from_state]"
		if(!edge.name || !edge.step_text)
			. += "[edge.id]: no name or step text"
		if(!edge.tool && !edge.item_type && !edge.no_item_ok)
			. += "[edge.id]: needs neither a tool nor an item"
		var/datum/predicate/pred = edge.predicate()
		if(pred?.errors)
			. += "[edge.id]: requirements don't compile: [jointext(pred.errors, "; ")]"
	// Every state is reachable from an initial state.
	var/list/reached = list()
	var/list/queue = list()
	for(var/state in initial_states)
		reached["[state]"] = TRUE
		queue += list(state)
	while(length(queue))
		var/state = queue[1]
		queue.Cut(1, 2)
		for(var/datum/interaction/construction/edge as anything in edges_leaving(state))
			var/next = edge.next_state(state)
			if(isnull(next))
				. += "[edge.id]: leads nowhere from [state]"
				continue
			if(next != CONSTRUCTION_DONE && !known["[next]"])
				. += "[edge.id]: leads to unknown state [next]"
				continue
			if(reached["[next]"])
				continue
			reached["[next]"] = TRUE
			queue += list(next)
	for(var/state in states)
		if(!reached["[state]"])
			. += "[id]: state [state] is unreachable"

// ---------------------------------------------------------------------------
// Edges

/datum/interaction/construction
	category = INTERACTION_CAT_MAINTAIN
	default_action = INPUT_ACTION_USE
	priority = 10
	tags = list(INTERACTION_TAG_CONSTRUCTION)
	requires = list(REQ_REACH_ADJACENT)
	effect = /atom/proc/traverse_construction_edge
	/// The graph this edge belongs to (set by add_edge()).
	var/tmp/datum/construction_graph/graph
	/// The state it leaves, or CONSTRUCTION_ANY_STATE (then leaves() decides).
	var/from_state
	/// The state it reaches, CONSTRUCTION_DONE when the target becomes something else. next_state() may work it out.
	var/to_state
	/// What the step is, for the Next line and the default name: "weld the frame".
	var/step_text
	/// A held item this edge needs instead of (or besides) a tool: a type or a list of types.
	var/item_type
	/// For a stack, how many units it needs.
	var/item_amount = 0
	/// CONSTRUCTION_ITEM_*: what happens to the held item.
	var/item_use = CONSTRUCTION_ITEM_KEEP
	/// How reasons name the item ("steel sheets"). Defaults to the type's name.
	var/item_name
	/// Materials placed on the target's turf when the edge runs: type -> amount.
	var/list/materials_out
	/// Whether the wait scales with the tool's speed (a few old steps didn't).
	var/tool_scaled = TRUE
	/// Messages when a timed step starts. Tokens as for message_self.
	var/start_self
	var/start_others
	/// Set on edges that need neither a tool nor an item (validate() allows them).
	var/no_item_ok = FALSE
	/// Items that stand in for `tool` (a plasma cutter for a welder). The tool clause is skipped for them;
	/// alt_delay() and alt_sound() give their wait and sound. Callers reach them with try_construction_alt().
	var/list/alt_item_types
	/// The compiled predicate without the tool clause, for alt items.
	var/tmp/datum/predicate/compiled_alt

/// Does this edge leave `state`? Only wildcard edges ask; others compare from_state.
/datum/interaction/construction/proc/leaves(state)
	return "[state]" == "[from_state]"

/// The state this edge reaches from `state`.
/datum/interaction/construction/proc/next_state(state)
	return to_state

/// Offered when the target is in a state this edge leaves, and available_on() agrees.
/datum/interaction/construction/applies_to(atom/target)
	if(!graph)
		return FALSE
	var/state = graph.state_of(target)
	if(isnull(state))
		return FALSE
	if(from_state == CONSTRUCTION_ANY_STATE ? !leaves(state) : "[state]" != "[from_state]")
		return FALSE
	return available_on(target)

/// Edge-specific conditions that hide it (not block it): e.g. which flooring this is.
/datum/interaction/construction/proc/available_on(atom/target)
	return TRUE

/// Edges are instances, not registered types: cache the predicate per edge.
/datum/interaction/construction/predicate()
	if(compiled)
		return compiled
	var/list/spec = full_spec()
	if(!length(spec))
		return null
	compiled = dq_predicate_for("construction:[id]", spec, "construction edge [id]")
	return compiled

/datum/interaction/construction/why_not(mob/actor, atom/target, obj/item/held)
	// Re-checked after the wait: the target may have moved on to another state.
	if(!applies_to(target))
		return "it has changed"
	if(is_alt_item(held))
		var/datum/predicate/pred = alt_predicate()
		. = pred?.why_not(actor, target, held)
	else
		. = ..()
	if(.)
		return
	if(item_type)
		return item_failure(held)

/// The requirements without the tool clause, for alt items.
/datum/interaction/construction/proc/alt_predicate()
	if(compiled_alt || !length(requires))
		return compiled_alt
	compiled_alt = dq_predicate_for("construction-alt:[id]", requires, "construction edge [id] (alt item)")
	return compiled_alt

/// Whether `held` is one of the items standing in for the tool.
/datum/interaction/construction/proc/is_alt_item(obj/item/held)
	if(!held || !length(alt_item_types))
		return FALSE
	for(var/path in alt_item_types)
		if(istype(held, path))
			return TRUE
	return FALSE

/// The unscaled wait for an alt item (use_tool() scales it by the item's toolspeed).
/datum/interaction/construction/proc/alt_delay(mob/actor, atom/target, obj/item/held)
	return duration

/// The sound an alt item makes when the step starts.
/datum/interaction/construction/proc/alt_sound(obj/item/held)
	return held.usesound

/datum/interaction/construction/pay_cost(mob/actor, atom/target, obj/item/held)
	graph.on_step_started(target, actor, held)
	if(!is_alt_item(held))
		return ..()
	var/sound = alt_sound(held)
	if(sound && tool_volume)
		playsound(target, sound, tool_volume, TRUE)
	var/list/start = start_messages(actor, target, held)
	return use_tool(actor, held, target, delay = alt_delay(actor, target, held), volume = 0,
		message_self = fill_message(start?[1], actor, target), message_others = fill_message(start?[2], actor, target))

/// Why `held` won't do for this edge's item, or null.
/datum/interaction/construction/proc/item_failure(obj/item/held)
	if(!held || !item_matches(held))
		return "needs [item_text()]"
	if(item_amount && istype(held, /obj/item/stack))
		var/obj/item/stack/stack = held
		if(stack.get_amount() < item_amount)
			return "needs [item_text()]"
	return null

/// Whether `held` is the kind of item this edge takes.
/datum/interaction/construction/proc/item_matches(obj/item/held)
	if(islist(item_type))
		for(var/path in item_type)
			if(istype(held, path))
				return TRUE
		return FALSE
	return istype(held, item_type)

/// "5 steel sheets", "a cell".
/datum/interaction/construction/proc/item_text()
	var/noun = item_name
	if(!noun)
		var/obj/item/path = islist(item_type) ? item_type[1] : item_type
		noun = initial(path.name)
	if(item_amount > 1)
		return "[item_amount] [noun]"
	return dq_pred_article(noun)

/// Short key for generated ids: the item's type name.
/datum/interaction/construction/proc/item_key()
	var/path = islist(item_type) ? item_type[1] : item_type
	if(!path)
		return "none"
	var/text = "[path]"
	var/slash = findlasttext(text, "/")
	return slash ? copytext(text, slash + 1) : text

/// "needs a welder", "needs 5 steel sheets".
/datum/interaction/construction/proc/requirement_text()
	var/list/parts = list()
	if(tool)
		parts += dq_pred_article(dq_pred_tool_name(tool))
	if(item_type)
		parts += item_text()
	return length(parts) ? "needs [jointext(parts, " and ")]" : null

#ifdef UNIT_TESTS
/// Unit tests set this to run construction steps with no wait.
GLOBAL_VAR_INIT(dq_construction_instant, FALSE)
#endif

/datum/interaction/construction/duration_for(mob/actor, atom/target, obj/item/held)
#ifdef UNIT_TESTS
	if(GLOB.dq_construction_instant)
		return 0
#endif
	if(tool && tool_scaled)
		return tool_delay(actor, held, duration, tool)
	return duration

/datum/interaction/construction/start_messages(mob/actor, atom/target, obj/item/held)
	if(!start_self && !start_others)
		return null
	return list(start_self, start_others)

/**
 * Runs the edge on `target` (the effect, after the cost is paid): takes the
 * item, stores the new state, runs on_traverse() and the graph's
 * on_traversed(), then places `materials_out`.
 */
/datum/interaction/construction/proc/traverse(atom/target, mob/actor, obj/item/held)
	var/turf/where = get_turf(target)
	var/before = graph.state_of(target)
	var/after = next_state(before)
	if(item_type && item_use == CONSTRUCTION_ITEM_USE && item_amount)
		var/obj/item/stack/stack = held
		if(!istype(stack) || !stack.use(item_amount))
			to_chat(actor, span_warning("You need [item_text()] for this."))
			return FALSE
	if(item_type && item_use == CONSTRUCTION_ITEM_INSERT && held)
		actor.drop_from_inventory(held)
		held.forceMove(target)
	graph.set_state(target, after)
	if(!on_traverse(target, actor, held, before, after))
		graph.set_state(target, before)
		return FALSE
	if(item_type && item_use == CONSTRUCTION_ITEM_DELETE && !QDELETED(held))
		actor.drop_from_inventory(held)
		qdel(held)
	give_materials(where)
	graph.on_traversed(target, actor, src, before, after)
	return TRUE

/// The edge's own effect, after the state is stored. Return FALSE to undo the state change.
/datum/interaction/construction/proc/on_traverse(atom/target, mob/actor, obj/item/held, before, after)
	return TRUE

/// Places `materials_out` on `where`.
/datum/interaction/construction/proc/give_materials(turf/where)
	if(!where)
		return
	for(var/path in materials_out)
		var/amount = materials_out[path] || 1
		if(ispath(path, /obj/item/stack))
			new path(where, amount)
		else
			for(var/i in 1 to amount)
				new path(where)

/**
 * Runs the edge leaving `target`'s state that `held` stands in a tool for (a
 * plasma cutter on a wall). For attackby fallbacks: items without the edge's
 * tool quality never reach the resolver's tool path. TRUE if one was found.
 */
/proc/try_construction_alt(mob/user, atom/target, obj/item/held)
	for(var/datum/interaction/construction/edge as anything in construction_edges_for(target))
		if(edge.is_alt_item(held) && edge.applies_to(target))
			edge.perform(user, target, held)
			return TRUE
	return FALSE

/// The effect proc every construction edge names.
/atom/proc/traverse_construction_edge(mob/actor, obj/item/held, datum/interaction/construction/edge)
	return edge.traverse(src, actor, held)

// ---------------------------------------------------------------------------
// Examine

/// "Next: weld the frame (needs a welder)", one line per edge leaving the target's state. Null if none.
/proc/construction_examine_lines(mob/user, atom/target)
	var/datum/construction_graph/graph = construction_graph_of(target)
	if(!graph)
		return null
	var/list/lines = list()
	for(var/datum/interaction/construction/edge as anything in graph.edges_for(target))
		if(!edge.applies_to(target))
			continue
		var/needs = edge.requirement_text()
		lines += span_notice("Next: [edge.step_text][needs ? " ([needs])" : ""]")
	return length(lines) ? lines : null
