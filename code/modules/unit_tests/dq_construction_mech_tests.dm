// Mech/fighter/micro-mech chassis construction graphs (roadmap I5): every graph
// walks its full parts phase and reversible ladder forward to the finished
// mecha, and its reversible steps go back with the same materials and state.
//
// Helpers reused from dq_construction_tests.dm: dq_walk, dq_materials_on,
// dq_fast_tool, dq_fueled_welder.

/// The chassis type that names `graph_path` as its construction_graph, or null.
/datum/unit_test/proc/mech_chassis_type_for(graph_path)
	for(var/obj/item/mecha_parts/path as anything in subtypesof(/obj/item/mecha_parts))
		if(initial(path.construction_graph) == graph_path)
			return path
	return null

/// The edge among `target`'s current edges whose item matches `item`'s type.
/datum/unit_test/proc/mech_edge_for_item(atom/target, obj/item/item)
	for(var/datum/interaction/construction/edge as anything in construction_edges_for(target))
		if(edge.item_type && istype(item, edge.item_type))
			return edge
	return null

/// The edge leaving a reversible-ladder state that builds forward (the higher-priority one).
/datum/unit_test/proc/mech_forward_edge(atom/target)
	var/datum/interaction/construction/best
	for(var/datum/interaction/construction/edge as anything in construction_edges_for(target))
		if(!best || edge.priority > best.priority)
			best = edge
	return best

/// The edge leaving a reversible-ladder state that undoes the last forward step, or null at the top.
/datum/unit_test/proc/mech_backward_edge(atom/target)
	var/list/edges = construction_edges_for(target)
	if(length(edges) < 2)
		return null
	var/datum/interaction/construction/worst
	for(var/datum/interaction/construction/edge as anything in edges)
		if(!worst || edge.priority < worst.priority)
			worst = edge
	return worst

/// One of each tool quality the mecha ladders use, sitting on `T`, zero-speed and fuelled.
/datum/unit_test/proc/mech_make_tools(turf/T)
	. = list()
	.[TOOL_WELDER] = dq_fueled_welder(T)
	.[TOOL_WRENCH] = dq_fast_tool(/obj/item/tool/wrench, T)
	.[TOOL_SCREWDRIVER] = dq_fast_tool(/obj/item/tool/screwdriver, T)
	.[TOOL_WIRECUTTER] = dq_fast_tool(/obj/item/tool/wirecutters, T)
	.[TOOL_CROWBAR] = dq_fast_tool(/obj/item/tool/crowbar, T)

/// What `edge` needs held: a tool from `tools`, a matching item already sitting on `T`
/// (left there by a refund, or pre-staged for a round trip), or a freshly made one.
/datum/unit_test/proc/mech_item_for_edge(datum/interaction/construction/edge, list/tools, turf/T)
	if(edge.tool)
		return tools[edge.tool]
	var/obj/item/path = edge.item_type
	if(ispath(path, /obj/item/stack))
		var/obj/item/stack/existing = locate(path) in T
		if(existing && existing.get_amount() >= max(edge.item_amount, 1))
			return existing
		return new path(T, max(edge.item_amount, 1))
	var/obj/item/existing = locate(path) in T
	if(existing)
		return existing
	return new path(T)

/// Attaches every part `graph` needs to `chassis`, in graph order, with `actor`.
/datum/unit_test/proc/mech_attach_all_parts(mob/actor, obj/item/chassis, datum/construction_graph/mecha/graph, turf/T)
	for(var/obj/item/part_type as anything in graph.mecha_parts)
		var/obj/item/part = new part_type(T)
		var/datum/interaction/construction/edge = mech_edge_for_item(chassis, part)
		TEST_ASSERT(edge, "[graph.id]: a part edge exists for [part_type]")
		if(!edge)
			continue
		TEST_ASSERT(dq_walk(actor, chassis, edge, part), "[graph.id]: attaching [part_type] succeeds")

/// Walks `target`'s reversible ladder all the way forward (to completion). TRUE if it finished.
/datum/unit_test/proc/mech_walk_to_completion(mob/actor, atom/target, list/tools, turf/T)
	var/guard = 0
	while(!QDELETED(target) && guard < 100)
		guard++
		var/datum/interaction/construction/edge = mech_forward_edge(target)
		if(!edge)
			return FALSE
		var/obj/item/held = mech_item_for_edge(edge, tools, T)
		if(!dq_walk(actor, target, edge, held))
			return FALSE
	return QDELETED(target)

/// Creates on `T` whatever items the top `steps_down` ladder rungs of `graph` will consume
/// going forward, so the round trip's "materials before" snapshot already counts them as the
/// player's own supplies (rather than materials the ladder's refunds conjure from nothing).
/// Stack amounts match mecha_ladder/New()'s own defaults (4 for cable coil, 5 otherwise).
/datum/unit_test/proc/mech_prestage_ladder_items(datum/construction_graph/mecha/graph, steps_down, turf/T)
	var/top = length(graph.ladder)
	for(var/i in 0 to steps_down - 1)
		var/idx = top - i
		if(idx < 1)
			break
		var/key = graph.ladder[idx]["key"]
		if(!ispath(key))
			continue
		if(ispath(key, /obj/item/stack))
			var/amount = ispath(key, /obj/item/stack/cable_coil) ? 4 : 5
			var/obj/item/stack/existing = locate(key) in T
			if(existing)
				existing.add(amount)
			else
				new key(T, amount)
		else if(!(locate(key) in T))
			new key(T)

/// Builds a fresh chassis for `graph_path`, attaches its parts, and returns it (already at the top of the ladder).
/datum/unit_test/proc/mech_fresh_shell(mob/actor, graph_path, turf/T)
	var/datum/construction_graph/mecha/graph = GLOB.construction_graphs[graph_path]
	if(!graph)
		return null
	var/chassis_type = mech_chassis_type_for(graph_path)
	if(!chassis_type)
		return null
	var/obj/item/chassis = allocate(chassis_type, T)
	mech_attach_all_parts(actor, chassis, graph, T)
	return chassis

// ---- Full builds: parts, then every forward ladder step, to the finished mecha ----

/datum/unit_test/dq_construction_mech_ripley_full_build

/datum/unit_test/dq_construction_mech_ripley_full_build/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/tools = mech_make_tools(T)
	var/obj/item/chassis = mech_fresh_shell(H, /datum/construction_graph/mecha/ripley, T)
	TEST_ASSERT(chassis, "a ripley chassis and graph exist")
	if(!chassis)
		return
	TEST_ASSERT_EQUAL(chassis.icon_state, "ripley0", "the shell is finished once every part is attached")
	TEST_ASSERT(mech_walk_to_completion(H, chassis, tools, T), "the ladder walks all the way to completion")
	TEST_ASSERT(QDELETED(chassis), "the chassis is gone")
	TEST_ASSERT(locate(/obj/mecha/working/ripley) in T, "the finished Ripley spawned")

/datum/unit_test/dq_construction_mech_gygax_full_build

/datum/unit_test/dq_construction_mech_gygax_full_build/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/tools = mech_make_tools(T)
	var/obj/item/chassis = mech_fresh_shell(H, /datum/construction_graph/mecha/gygax, T)
	TEST_ASSERT(chassis, "a gygax chassis and graph exist")
	if(!chassis)
		return
	TEST_ASSERT_EQUAL(chassis.icon_state, "gygax0", "the shell is finished once every part is attached")
	TEST_ASSERT(mech_walk_to_completion(H, chassis, tools, T), "the ladder walks all the way to completion")
	TEST_ASSERT(QDELETED(chassis), "the chassis is gone")
	TEST_ASSERT(locate(/obj/mecha/combat/gygax) in T, "the finished Gygax spawned")

/datum/unit_test/dq_construction_mech_pinnace_full_build

/datum/unit_test/dq_construction_mech_pinnace_full_build/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/tools = mech_make_tools(T)
	var/obj/item/chassis = mech_fresh_shell(H, /datum/construction_graph/mecha/fighter/pinnace, T)
	TEST_ASSERT(chassis, "a pinnace chassis and graph exist")
	if(!chassis)
		return
	TEST_ASSERT_EQUAL(chassis.icon_state, "pinnace0", "the shell is finished once every part is attached")
	TEST_ASSERT(mech_walk_to_completion(H, chassis, tools, T), "the ladder walks all the way to completion")
	TEST_ASSERT(QDELETED(chassis), "the chassis is gone")
	TEST_ASSERT(locate(/obj/mecha/combat/fighter/pinnace) in T, "the finished Pinnace spawned")

/datum/unit_test/dq_construction_mech_polecat_full_build

/datum/unit_test/dq_construction_mech_polecat_full_build/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/tools = mech_make_tools(T)
	var/obj/item/chassis = mech_fresh_shell(H, /datum/construction_graph/mecha/micro/polecat, T)
	TEST_ASSERT(chassis, "a polecat chassis and graph exist")
	if(!chassis)
		return
	TEST_ASSERT_EQUAL(chassis.icon_state, "polecat0", "the shell is finished once every part is attached")
	TEST_ASSERT(mech_walk_to_completion(H, chassis, tools, T), "the ladder walks all the way to completion")
	TEST_ASSERT(QDELETED(chassis), "the chassis is gone")
	TEST_ASSERT(locate(/obj/mecha/micro/sec/polecat) in T, "the finished Polecat spawned")

// ---- Round trips: forward some steps, then the same steps back, same materials and state ----

/datum/unit_test/proc/mech_round_trip(graph_path, steps_down)
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/list/tools = mech_make_tools(T)
	var/obj/item/chassis = mech_fresh_shell(H, graph_path, T)
	TEST_ASSERT(chassis, "[graph_path]: a chassis and graph exist")
	if(!chassis)
		return
	var/datum/construction_graph/mecha/graph = GLOB.construction_graphs[graph_path]
	if(graph)
		mech_prestage_ladder_items(graph, steps_down, T)
	var/before_state = chassis.vars["construction_state"]
	var/before_icon = chassis.icon_state
	var/list/materials_before = dq_materials_on(T)
	for(var/i in 1 to steps_down)
		var/datum/interaction/construction/edge = mech_forward_edge(chassis)
		TEST_ASSERT(edge, "[graph_path]: a forward edge exists at step [i]")
		if(!edge)
			return
		var/obj/item/held = mech_item_for_edge(edge, tools, T)
		TEST_ASSERT(dq_walk(H, chassis, edge, held), "[graph_path]: forward step [i] succeeds")
	for(var/i in 1 to steps_down)
		var/datum/interaction/construction/edge = mech_backward_edge(chassis)
		TEST_ASSERT(edge, "[graph_path]: a backward edge exists at step [i]")
		if(!edge)
			return
		var/obj/item/held = mech_item_for_edge(edge, tools, T)
		TEST_ASSERT(dq_walk(H, chassis, edge, held), "[graph_path]: backward step [i] succeeds")
	TEST_ASSERT_EQUAL(chassis.vars["construction_state"], before_state, "[graph_path]: the state round-trips")
	TEST_ASSERT_EQUAL(chassis.icon_state, before_icon, "[graph_path]: the icon_state round-trips")
	TEST_ASSERT_EQUAL(dq_materials_on(T), materials_before, "[graph_path]: the same materials came back")

/datum/unit_test/dq_construction_mech_ripley_round_trip

/datum/unit_test/dq_construction_mech_ripley_round_trip/Run()
	mech_round_trip(/datum/construction_graph/mecha/ripley, 5)

/datum/unit_test/dq_construction_mech_gygax_round_trip

/datum/unit_test/dq_construction_mech_gygax_round_trip/Run()
	mech_round_trip(/datum/construction_graph/mecha/gygax, 6)

/datum/unit_test/dq_construction_mech_pinnace_round_trip

/datum/unit_test/dq_construction_mech_pinnace_round_trip/Run()
	mech_round_trip(/datum/construction_graph/mecha/fighter/pinnace, 5)

/datum/unit_test/dq_construction_mech_polecat_round_trip

/datum/unit_test/dq_construction_mech_polecat_round_trip/Run()
	mech_round_trip(/datum/construction_graph/mecha/micro/polecat, 6)

// ---- Every mech graph: one step forward then straight back, from the top of the ladder ----

/datum/unit_test/dq_construction_mech_all_graphs_round_trip

/datum/unit_test/dq_construction_mech_all_graphs_round_trip/Run()
	for(var/datum/construction_graph/mecha/path as anything in subtypesof(/datum/construction_graph/mecha))
		if(!initial(path.id))
			continue
		var/turf/T = test_floor()
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
		var/list/tools = mech_make_tools(T)
		var/obj/item/chassis = mech_fresh_shell(H, path, T)
		TEST_ASSERT(chassis, "[path]: a chassis and graph exist")
		if(!chassis)
			continue
		var/guard = 0
		while(!QDELETED(chassis) && guard < 100)
			guard++
			var/state_before = chassis.vars["construction_state"]
			var/icon_before = chassis.icon_state
			var/datum/interaction/construction/fwd = mech_forward_edge(chassis)
			if(!fwd)
				break
			var/obj/item/fwd_held = mech_item_for_edge(fwd, tools, T)
			TEST_ASSERT(dq_walk(H, chassis, fwd, fwd_held), "[path]: forward from [state_before] succeeds")
			if(QDELETED(chassis))
				break
			var/datum/interaction/construction/back = mech_backward_edge(chassis)
			TEST_ASSERT(back, "[path]: a backward edge exists after leaving [state_before]")
			if(!back)
				break
			var/obj/item/back_held = mech_item_for_edge(back, tools, T)
			TEST_ASSERT(dq_walk(H, chassis, back, back_held), "[path]: backward to [state_before] succeeds")
			TEST_ASSERT_EQUAL(chassis.vars["construction_state"], state_before, "[path]: state round-trips at [state_before]")
			TEST_ASSERT_EQUAL(chassis.icon_state, icon_before, "[path]: icon_state round-trips at [state_before]")
			// Advance past this rung without reversing it, so the next iteration tests the next one down.
			var/obj/item/advance_held = mech_item_for_edge(fwd, tools, T)
			if(!dq_walk(H, chassis, fwd, advance_held))
				break
