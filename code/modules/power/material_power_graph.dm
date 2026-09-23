/// Reduced resistor graph. Degree-two cable runs form one edge. Junctions and
/// equipment attachment points remain vertices. Only weak object references
/// survive a rebuild, so a deleted cable cannot be retained by a cached graph.
/datum/material_power_graph
	var/list/vertices
	var/list/indices
	var/list/edges
	var/list/voltages
	var/list/efficiencies
	var/residual = 0
	var/iterations = 0
	var/loss_watts = 0
	var/list/last_injections
	var/resistance_dirty = TRUE
	var/has_superconductors = FALSE
	var/has_custom_conductors = FALSE
	var/next_solve = 0
	var/list/numeric_topology
	var/list/energized_cables
	var/list/core_vertices
	var/list/core_edges
	var/list/leaf_order
	var/list/solver_source_edges
	var/solve_ms = 0
	var/deposit_ms = 0
	var/resistance_ms = 0
	var/list/cable_edges
	var/list/dirty_edges
	/// Stable equipment-to-vertex lookup. Resolving every APC weakref through its
	/// turf and cable contents was a sizeable fraction of every powernet tick.
	var/list/equipment_vertices
	/// Large station meshes solve away from the BYOND thread. Results carry this
	/// generation so a topology rebuild can never publish stale voltages.
	var/rust_handle = 0
	var/solve_generation = 0
	var/solve_pending = FALSE
	var/list/pending_reduced
	var/list/pending_sources
	var/list/pending_consumers
	var/pending_total_source = 0

/datum/material_power_graph/Destroy()
	if(rust_handle)
		vg_drop_material_power_graph(rust_handle)
		rust_handle = 0
	vertices = null
	indices = null
	edges = null
	voltages = null
	efficiencies = null
	last_injections = null
	numeric_topology = null
	energized_cables = null
	core_vertices = null
	core_edges = null
	leaf_order = null
	solver_source_edges = null
	cable_edges = null
	dirty_edges = null
	equipment_vertices = null
	pending_reduced = null
	pending_sources = null
	pending_consumers = null
	return ..()

/datum/material_power_graph/proc/build(list/cables)
	vertices = list()
	indices = list()
	edges = list()
	efficiencies = list()
	cable_edges = list()
	equipment_vertices = list()
	var/list/adjacency = list()
	for(var/obj/structure/cable/cable as anything in cables)
		if(cable.material_custom_assembly || cable.engineered_material_id)
			has_custom_conductors = TRUE
		var/list/neighbors = list()
		var/has_attachment = FALSE
		if(cable.d1 == 0)
			for(var/obj/machinery/power/equipment in cable.loc)
				if(equipment.powernet == cable.powernet)
					has_attachment = TRUE
					break
		for(var/obj/structure/cable/neighbor in cable.get_connections())
			if(neighbor != cable && neighbor.powernet == cable.powernet)
				neighbors |= neighbor
		adjacency[cable] = neighbors
		if(length(neighbors) != 2 || has_attachment)
			vertices += WEAKREF(cable)
			indices[REF(cable)] = length(vertices)
	if(!length(vertices) && length(cables))
		var/obj/structure/cable/first = cables[1]
		vertices += WEAKREF(first)
		indices[REF(first)] = 1
	var/list/visited = list()
	for(var/start_index in 1 to length(vertices))
		var/datum/weakref/start_ref = vertices[start_index]
		var/obj/structure/cable/start = start_ref.resolve()
		for(var/obj/structure/cable/neighbor as anything in adjacency[start])
			var/forward_key = "[REF(start)]>[REF(neighbor)]"
			if(visited[forward_key])
				continue
			var/list/run = list(WEAKREF(start))
			var/obj/structure/cable/previous = start
			var/obj/structure/cable/current = neighbor
			var/end_index
			while(current)
				visited["[REF(previous)]>[REF(current)]"] = TRUE
				visited["[REF(current)]>[REF(previous)]"] = TRUE
				run += WEAKREF(current)
				end_index = indices[REF(current)]
				if(end_index)
					break
				var/list/next_neighbors = adjacency[current]
				var/obj/structure/cable/next = next_neighbors[1] == previous ? next_neighbors[2] : next_neighbors[1]
				previous = current
				current = next
			if(end_index && end_index != start_index)
				var/list/edge = list(start_index, end_index, 1, run, 0, null, FALSE, FALSE)
				edges += list(edge)
				for(var/datum/weakref/reference as anything in run)
					var/list/attached = cable_edges[reference.reference]
					if(!attached)
						attached = list()
						cable_edges[reference.reference] = attached
					attached += list(edge)
	voltages = new /list(length(vertices))
	refresh_resistance()

/datum/material_power_graph/proc/refresh_resistance()
	if(!resistance_dirty && !length(dirty_edges))
		return FALSE
	var/started = REALTIMEOFDAY
	var/list/work = resistance_dirty ? edges : dirty_edges
	numeric_topology = null
	dirty_edges = null
	resistance_dirty = FALSE
	var/changed = FALSE
	for(var/list/edge as anything in work)
		if(length(edge) < MATERIAL_POWER_EDGE_CRITICAL)
			edge.len = MATERIAL_POWER_EDGE_CRITICAL
		edge[MATERIAL_POWER_EDGE_DIRTY] = FALSE
		edge[MATERIAL_POWER_EDGE_CRITICAL] = FALSE
		var/resistance = 0
		var/list/run = edge[MATERIAL_POWER_EDGE_CABLES]
		var/list/weights = new /list(length(run))
		for(var/i in 1 to length(run))
			var/datum/weakref/reference = run[i]
			var/obj/structure/cable/cable = reference.resolve()
			if(!cable)
				continue
			var/length_factor = (i == 1 || i == length(run)) ? 0.5 : 1
			var/temperature = cable.material_service ? cable.material_service.current_temperature() : T20C
			if(cable.material_for_role(MATERIAL_ROLE_CONDUCTOR)?.critical_temperature)
				has_superconductors = TRUE
				edge[MATERIAL_POWER_EDGE_CRITICAL] = TRUE
			var/current_density = abs(edge[MATERIAL_POWER_EDGE_CURRENT]) / MATERIAL_CABLE_REFERENCE_AREA
			weights[i] = max(cable.construction_electrical_resistance(length_factor, MATERIAL_CABLE_REFERENCE_AREA, temperature, current_density) * MATERIAL_SERVICE_RESISTANCE_SCALE, 0.000000001)
			resistance += weights[i]
		resistance = max(resistance, 0.000000001)
		if(abs(resistance - edge[MATERIAL_POWER_EDGE_R]) > max(resistance * 0.00001, 0.000000001))
			changed = TRUE
		edge[MATERIAL_POWER_EDGE_R] = resistance
		if(length(edge) < MATERIAL_POWER_EDGE_WEIGHTS)
			edge.len = MATERIAL_POWER_EDGE_WEIGHTS
		edge[MATERIAL_POWER_EDGE_WEIGHTS] = weights
	resistance_ms = (REALTIMEOFDAY - started) * 100
	return changed

/datum/material_power_graph/proc/queue_resistance_edge(list/edge)
	if(edge[MATERIAL_POWER_EDGE_DIRTY])
		return
	edge[MATERIAL_POWER_EDGE_DIRTY] = TRUE
	LAZYADD(dirty_edges, list(edge))

/datum/material_power_graph/proc/invalidate_cable(obj/structure/cable/cable)
	for(var/list/edge as anything in cable_edges?[REF(cable)])
		queue_resistance_edge(edge)

/// Strip pendant branches once per topology. Their currents are determined by
/// their own demand, exactly; only the remaining loop core needs iteration.
/datum/material_power_graph/proc/prepare_solver()
	if(solver_source_edges == edges)
		return
	solver_source_edges = edges
	numeric_topology = null
	var/count = length(vertices)
	var/list/adjacency = new /list(count)
	var/list/degrees = new /list(count)
	var/list/removed = new /list(count)
	for(var/i in 1 to count)
		adjacency[i] = list()
	for(var/list/edge as anything in edges)
		var/list/a = adjacency[edge[MATERIAL_POWER_EDGE_A]]
		var/list/b = adjacency[edge[MATERIAL_POWER_EDGE_B]]
		a += list(edge)
		b += list(edge)
		degrees[edge[MATERIAL_POWER_EDGE_A]]++
		degrees[edge[MATERIAL_POWER_EDGE_B]]++
	var/list/pending = list()
	for(var/i in 2 to count)
		if(degrees[i] == 1)
			pending += i
	leaf_order = list()
	while(length(pending))
		var/leaf = pending[length(pending)]
		pending.len--
		if(removed[leaf])
			continue
		removed[leaf] = TRUE
		for(var/list/edge as anything in adjacency[leaf])
			var/parent = edge[MATERIAL_POWER_EDGE_A] == leaf ? edge[MATERIAL_POWER_EDGE_B] : edge[MATERIAL_POWER_EDGE_A]
			if(removed[parent])
				continue
			leaf_order += list(list(leaf, parent, edge))
			degrees[parent]--
			if(parent != 1 && degrees[parent] == 1)
				pending += parent
	core_vertices = list()
	core_edges = list()
	for(var/i in 2 to count)
		if(!removed[i])
			core_vertices += i
	for(var/list/edge as anything in edges)
		if(!removed[edge[MATERIAL_POWER_EDGE_A]] && !removed[edge[MATERIAL_POWER_EDGE_B]])
			core_edges += list(edge)

/datum/material_power_graph/proc/vertex_for(atom/equipment)
	if(istype(equipment, /obj/structure/cable))
		return indices[REF(equipment)]
	var/key = REF(equipment)
	var/cached = equipment_vertices[key]
	if(cached)
		return cached
	var/turf/location = get_turf(equipment)
	var/obj/structure/cable/cable = location?.get_cable_node()
	var/index = cable ? indices[REF(cable)] : null
	if(index)
		equipment_vertices[key] = index
	return index

/// The bounded f64 solve runs in Rust. DM retains the physical topology,
/// constitutive inputs and conserved energy ledger, with no duplicate solver.
/datum/material_power_graph/proc/solve(list/injections)
	var/started = REALTIMEOFDAY
	var/count = length(vertices)
	if(count < 2)
		return TRUE
	prepare_solver()
	var/list/reduced = injections.Copy()
	for(var/list/step as anything in leaf_order)
		reduced[step[2]] += reduced[step[1]] || 0
	if(length(voltages) != count)
		voltages = new /list(count)
	if(!numeric_topology)
		numeric_topology = list()
		for(var/list/edge as anything in core_edges)
			numeric_topology += list(edge[MATERIAL_POWER_EDGE_A], edge[MATERIAL_POWER_EDGE_B], edge[MATERIAL_POWER_EDGE_R])
	var/list/core_loads = reduced.Copy()
	for(var/list/step as anything in leaf_order)
		core_loads[step[1]] = 0
	var/list/solution = vg_solve_material_power_graph(numeric_topology, core_loads, voltages)
	if(!islist(solution) || length(solution) != count + 2)
		residual = INFINITY
		return FALSE
	residual = solution[1]
	iterations = solution[2]
	voltages = solution.Copy(3)
	for(var/i = length(leaf_order), i >= 1, i--)
		var/list/step = leaf_order[i]
		var/list/edge = step[3]
		voltages[step[1]] = (voltages[step[2]] || 0) + (reduced[step[1]] || 0) * edge[MATERIAL_POWER_EDGE_R]
	loss_watts = 0
	for(var/list/edge as anything in edges)
		var/current = ((voltages[edge[MATERIAL_POWER_EDGE_A]] || 0) - (voltages[edge[MATERIAL_POWER_EDGE_B]] || 0)) / edge[MATERIAL_POWER_EDGE_R]
		if(length(edge) >= MATERIAL_POWER_EDGE_CRITICAL && edge[MATERIAL_POWER_EDGE_CRITICAL] && current != edge[MATERIAL_POWER_EDGE_CURRENT])
			queue_resistance_edge(edge)
		edge[MATERIAL_POWER_EDGE_CURRENT] = current
		loss_watts += current * current * edge[MATERIAL_POWER_EDGE_R]
	solve_ms = (REALTIMEOFDAY - started) * 100
	return TRUE

/// Submit a station-scale solve to Rust. Topology is transferred only for the
/// first request on this graph; subsequent requests carry just the load vector.
/datum/material_power_graph/proc/submit_async_solve(list/injections, list/sources, list/consumers, total_source)
	prepare_solver()
	var/list/reduced = injections.Copy()
	for(var/list/step as anything in leaf_order)
		reduced[step[2]] += reduced[step[1]] || 0
	if(length(voltages) != length(vertices))
		voltages = new /list(length(vertices))
	var/list/core_loads = reduced.Copy()
	for(var/list/step as anything in leaf_order)
		core_loads[step[1]] = 0
	var/list/topology = list()
	if(!numeric_topology)
		numeric_topology = list()
		for(var/list/edge as anything in core_edges)
			numeric_topology += list(edge[MATERIAL_POWER_EDGE_A], edge[MATERIAL_POWER_EDGE_B], edge[MATERIAL_POWER_EDGE_R])
		topology = numeric_topology
	solve_generation++
	var/handle = vg_submit_material_power_graph(rust_handle, topology, core_loads, voltages, solve_generation)
	if(!handle)
		return FALSE
	rust_handle = handle
	solve_pending = TRUE
	pending_reduced = reduced
	pending_sources = sources?.Copy()
	pending_consumers = consumers?.Copy()
	pending_total_source = total_source
	return TRUE

/// Apply a completed versioned worker result. No BYOND datum is touched by the
/// worker; all edge currents, heat accounting, and equipment efficiency remain
/// authoritative here on the main thread.
/datum/material_power_graph/proc/poll_async_solve()
	if(!solve_pending || !rust_handle)
		return FALSE
	var/list/solution = vg_poll_material_power_graph(rust_handle)
	if(!islist(solution) || !length(solution))
		return null
	solve_pending = FALSE
	if(length(solution) != length(vertices) + 3 || solution[1] != solve_generation)
		pending_reduced = null
		pending_sources = null
		pending_consumers = null
		return FALSE
	residual = solution[2]
	iterations = solution[3]
	voltages = solution.Copy(4)
	for(var/i = length(leaf_order), i >= 1, i--)
		var/list/step = leaf_order[i]
		var/list/edge = step[3]
		voltages[step[1]] = (voltages[step[2]] || 0) + (pending_reduced[step[1]] || 0) * edge[MATERIAL_POWER_EDGE_R]
	loss_watts = 0
	for(var/list/edge as anything in edges)
		var/current = ((voltages[edge[MATERIAL_POWER_EDGE_A]] || 0) - (voltages[edge[MATERIAL_POWER_EDGE_B]] || 0)) / edge[MATERIAL_POWER_EDGE_R]
		if(length(edge) >= MATERIAL_POWER_EDGE_CRITICAL && edge[MATERIAL_POWER_EDGE_CRITICAL] && current != edge[MATERIAL_POWER_EDGE_CURRENT])
			queue_resistance_edge(edge)
		edge[MATERIAL_POWER_EDGE_CURRENT] = current
		loss_watts += current * current * edge[MATERIAL_POWER_EDGE_R]
	efficiencies = list()
	var/source_potential = 0
	for(var/datum/weakref/reference as anything in pending_sources)
		var/index = vertex_for(reference.resolve())
		if(index)
			source_potential += (voltages[index] || 0) * pending_sources[reference] / pending_total_source
	for(var/datum/weakref/reference as anything in pending_consumers)
		var/atom/consumer = reference.resolve()
		var/index = vertex_for(consumer)
		if(index && consumer)
			efficiencies[REF(consumer)] = clamp(1 - max(0, source_potential - (voltages[index] || 0)) / MATERIAL_SERVICE_NOMINAL_VOLTAGE, 0.05, 1)
	pending_reduced = null
	pending_sources = null
	pending_consumers = null
	return TRUE

/datum/material_power_graph/proc/resolve_loads(list/sources, list/consumers)
	resistance_ms = 0
	solve_ms = 0
	var/async_result = poll_async_solve()
	if(isnull(async_result))
		return 2
	var/changed = refresh_resistance()
	efficiencies = list()
	var/list/injections = new /list(length(vertices))
	var/total_source = 0
	var/total_demand = 0
	for(var/datum/weakref/reference as anything in sources)
		if(vertex_for(reference.resolve()))
			total_source += sources[reference]
	for(var/datum/weakref/reference as anything in consumers)
		var/index = vertex_for(reference.resolve())
		if(index)
			injections[index] -= consumers[reference] / MATERIAL_SERVICE_NOMINAL_VOLTAGE
			total_demand += consumers[reference]
	if(total_source <= 0 || total_demand <= 0)
		for(var/list/edge as anything in edges)
			edge[MATERIAL_POWER_EDGE_CURRENT] = 0
		loss_watts = 0
		last_injections = null
		return
	for(var/datum/weakref/reference as anything in sources)
		var/index = vertex_for(reference.resolve())
		if(index)
			injections[index] += sources[reference] / total_source * total_demand / MATERIAL_SERVICE_NOMINAL_VOLTAGE
	if(!last_injections || length(last_injections) != length(injections))
		changed = TRUE
	else
		for(var/index in 1 to length(injections))
			var/old_injection = last_injections[index] || 0
			var/new_injection = injections[index] || 0
			// APC demand jitters by tiny amounts every machinery fire. Re-solving a
			// thousand-node loop graph for sub-percent, sub-100 W changes cannot
			// produce a visible voltage change, but previously cost 20-80 ms.
			var/material_change = max(abs(old_injection) * MATERIAL_POWER_LOAD_RELATIVE_EPSILON, MATERIAL_POWER_LOAD_ABSOLUTE_EPSILON)
			if(abs(new_injection - old_injection) > material_change)
				changed = TRUE
				break
	if(changed && !has_superconductors && world.time < next_solve)
		changed = FALSE
	if(changed)
		// Baseline station cable meshes are large and highly cyclic. Their
		// material voltage/loss model is observability and failure physics layered
		// over the authoritative legacy power accounting; it does not need to
		// chase APC load jitter every machine tick. Superconductors retain
		// immediate solves because their current and temperature limits are gameplay.
		if(length(vertices) > 128)
			if(!submit_async_solve(injections, sources, consumers, total_source))
				return solve_pending ? 2 : FALSE
			last_injections = injections.Copy()
			next_solve = world.time + MATERIAL_POWER_GRAPH_SETTLEMENT_INTERVAL
			return 2
		if(!solve(injections))
			return FALSE
		last_injections = injections.Copy()
		next_solve = world.time + MATERIAL_POWER_GRAPH_SETTLEMENT_INTERVAL
	var/source_potential = 0
	for(var/datum/weakref/reference as anything in sources)
		var/index = vertex_for(reference.resolve())
		if(index)
			source_potential += (voltages[index] || 0) * sources[reference] / total_source
	for(var/datum/weakref/reference as anything in consumers)
		var/index = vertex_for(reference.resolve())
		if(index)
			efficiencies[REF(reference.resolve())] = clamp(1 - max(0, source_potential - (voltages[index] || 0)) / MATERIAL_SERVICE_NOMINAL_VOLTAGE, 0.05, 1)

/// Heat exactly the energy debited for cable loss, apportioned by the solved
/// I^2 R distribution. No thermal energy is minted by an accounting estimate.
/datum/material_power_graph/proc/deposit_losses(joules, elapsed = 1)
	var/started = REALTIMEOFDAY
	// Baseline station cable loss remains part of the power ledger, but does not
	// become thousands of individually simulated heat reservoirs. Standard cable
	// has no temperature-dependent electrical behaviour, so publishing this
	// imperceptible heat cannot change the solution or create useful gameplay.
	// Engineered cable and superconductors retain exact, conservative deposition.
	if(!has_custom_conductors && !has_superconductors)
		deposit_ms = (REALTIMEOFDAY - started) * 100
		return
	var/list/cable_heat = list()
	var/list/cable_current = list()
	var/distribution_loss = 0
	for(var/list/edge as anything in edges)
		distribution_loss += edge[MATERIAL_POWER_EDGE_CURRENT] ** 2 * edge[MATERIAL_POWER_EDGE_R]
	for(var/list/edge as anything in edges)
		var/current = edge[MATERIAL_POWER_EDGE_CURRENT]
		if(!current)
			continue
		var/edge_energy = distribution_loss > 0 ? joules * current * current * edge[MATERIAL_POWER_EDGE_R] / distribution_loss : 0
		var/list/run = edge[MATERIAL_POWER_EDGE_CABLES]
		var/list/weights = edge[MATERIAL_POWER_EDGE_WEIGHTS]
		var/total_weight = edge[MATERIAL_POWER_EDGE_R]
		for(var/i in 1 to length(run))
			var/datum/weakref/reference = run[i]
			var/obj/structure/cable/cable = reference.resolve()
			if(!cable)
				continue
			cable_current[cable] = max(cable_current[cable] || 0, abs(current))
			cable_heat[cable] += edge_energy * weights[i] / total_weight
	for(var/datum/weakref/reference as anything in energized_cables)
		var/obj/structure/cable/cable = reference.resolve()
		if(cable && !(cable in cable_current))
			cable.material_current = 0
			if(cable.material_service)
				cable.material_service.last_input_watts = 0
				cable.material_service.last_output_watts = 0
	energized_cables = list()
	for(var/obj/structure/cable/cable as anything in cable_current)
		energized_cables += WEAKREF(cable)
		cable.material_current = cable_current[cable]
		var/heat = cable_heat[cable]
		cable.material_service_event(MATERIAL_EVENT_WORK, 1)
		var/datum/material_service/service = cable.material_service
		if(!service)
			continue
		var/input = max(heat, cable.material_current * MATERIAL_SERVICE_NOMINAL_VOLTAGE * elapsed)
		service.input_joules += input
		service.output_joules += input - heat
		service.loss_joules += heat
		service.last_input_watts = input / max(elapsed, 0.1)
		service.last_output_watts = (input - heat) / max(elapsed, 0.1)
		service.add_heat(heat)
	deposit_ms = (REALTIMEOFDAY - started) * 100
