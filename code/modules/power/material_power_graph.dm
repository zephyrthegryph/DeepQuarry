/// Reduced resistor graph. Degree-two cable runs form one edge. Junctions and
/// equipment attachment points remain vertices. The graph holds no object
/// references: a cable is named by its power entity id (cable.power_entity,
/// resolved through material_power_cable(), so a deleted cable reads null), and
/// equipment by the vertex it attaches to. Sources and consumers handed to
/// resolve_loads() are keyed by vertex index (vertex_for()).
/datum/material_power_graph
	/// Vertex index -> cable power entity id.
	var/list/vertices
	/// Cable power entity id -> vertex index.
	var/alist/indices
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
	COOLDOWN_DECLARE(next_solve)
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
	/// Stable turf-to-vertex lookup (keyed by turf index). Resolving every APC through
	/// its turf and cable contents was a sizeable fraction of every powernet tick.
	var/alist/equipment_vertices
	/// Large station meshes solve away from the BYOND thread: the Rust solver's graph id
	/// (a number, 0 when none). Results carry solve_generation so a topology rebuild can
	/// never publish stale voltages.
	var/rust_graph_id = 0
	var/solve_generation = 0
	var/solve_pending = FALSE
	var/list/pending_reduced
	var/list/pending_sources
	var/list/pending_consumers
	var/pending_total_source = 0

/// Phase 1 (unbind): the Rust material power graph is dropped.
/datum/material_power_graph/lifecycle_unbind()
	. = ..()
	if(rust_graph_id)
		vg_drop_material_power_graph(rust_graph_id)
		rust_graph_id = 0

/// The live cable whose power entity id is `entity`, or null.
/proc/material_power_cable(entity)
	if(!entity)
		return null
	var/obj/structure/cable/cable = SSvg.entity_lookup(entity)
	return (istype(cable) && cable.power_entity == entity) ? cable : null

/// A turf's key in equipment_vertices.
/proc/material_power_turf_key(turf/T)
	return ((T.z - 1) * world.maxy + (T.y - 1)) * world.maxx + T.x

/// `region_id`: the power region the cables are on (0 for a detached test overlay).
/datum/material_power_graph/proc/build(list/cables, region_id = 0)
	vertices = list()
	indices = alist()
	edges = list()
	efficiencies = alist()
	cable_edges = alist()
	equipment_vertices = alist()
	var/list/adjacency = list()
	for(var/obj/structure/cable/cable as anything in cables)
		if(material_assembly_view(cable).custom || cable.engineered_material_id)
			has_custom_conductors = TRUE
		var/list/neighbors = list()
		var/has_attachment = FALSE
		if(cable.d1 == 0)
			for(var/obj/machinery/power/equipment in cable.loc)
				if(region_id && equipment.power_region == region_id)
					has_attachment = TRUE
					break
		for(var/obj/structure/cable/neighbor in cable.get_connections())
			if(neighbor != cable && neighbor.material_overlay == cable.material_overlay)
				neighbors |= neighbor
		adjacency[cable] = neighbors
		if(length(neighbors) != 2 || has_attachment)
			vertices += cable.power_entity
			indices[cable.power_entity] = length(vertices)
	if(!length(vertices) && length(cables))
		var/obj/structure/cable/first = cables[1]
		vertices += first.power_entity
		indices[first.power_entity] = 1
	var/alist/visited = alist()
	for(var/start_index in 1 to length(vertices))
		var/obj/structure/cable/start = material_power_cable(vertices[start_index])
		if(!start)
			continue
		for(var/obj/structure/cable/neighbor as anything in adjacency[start])
			if(neighbor.power_entity in visited[start.power_entity])
				continue
			var/list/run = list(start.power_entity)
			var/obj/structure/cable/previous = start
			var/obj/structure/cable/current = neighbor
			var/end_index
			while(current)
				LAZYADD(visited[previous.power_entity], current.power_entity)
				LAZYADD(visited[current.power_entity], previous.power_entity)
				run += current.power_entity
				end_index = indices[current.power_entity]
				if(end_index)
					break
				var/list/next_neighbors = adjacency[current]
				var/obj/structure/cable/next = next_neighbors[1] == previous ? next_neighbors[2] : next_neighbors[1]
				previous = current
				current = next
			if(end_index && end_index != start_index)
				var/list/edge = list(start_index, end_index, 1, run, 0, null, FALSE, FALSE)
				edges += list(edge)
				for(var/reference as anything in run)
					var/list/attached = cable_edges[reference]
					if(!attached)
						attached = list()
						cable_edges[reference] = attached
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
			var/obj/structure/cable/cable = material_power_cable(run[i])
			if(!cable)
				continue
			var/length_factor = (i == 1 || i == length(run)) ? 0.5 : 1
			var/temperature = material_service_of(cable)?.temperature || T20C
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
	for(var/list/edge as anything in cable_edges?[cable.power_entity])
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

/// The vertex index `equipment` attaches to (a cable's own vertex, or the knot cable on the
/// equipment's turf), or null.
/datum/material_power_graph/proc/vertex_for(atom/equipment)
	if(!equipment || !indices)
		return null
	if(istype(equipment, /obj/structure/cable))
		var/obj/structure/cable/as_cable = equipment
		return indices[as_cable.power_entity]
	var/turf/location = get_turf(equipment)
	if(!location)
		return null
	var/key = material_power_turf_key(location)
	var/cached = equipment_vertices?[key]
	if(cached)
		return cached
	var/obj/structure/cable/cable = location.get_cable_node()
	var/index = cable ? indices[cable.power_entity] : null
	if(index)
		equipment_vertices[key] = index
	return index

/// The supply efficiency (0.05-1) at `equipment`'s vertex: 1 when unsolved or detached.
/datum/material_power_graph/proc/efficiency_for(atom/equipment)
	var/index = vertex_for(equipment)
	return (index && efficiencies?[index]) || 1

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
	var/graph_id = vg_submit_material_power_graph(rust_graph_id, topology, core_loads, voltages, solve_generation)
	if(!graph_id)
		return FALSE
	rust_graph_id = graph_id
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
	if(!solve_pending || !rust_graph_id)
		return FALSE
	var/list/solution = vg_poll_material_power_graph(rust_graph_id)
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
	efficiencies = alist()
	var/source_potential = 0
	for(var/index in pending_sources)
		if(index >= 1 && index <= length(voltages))
			source_potential += (voltages[index] || 0) * pending_sources[index] / pending_total_source
	for(var/index in pending_consumers)
		if(index >= 1 && index <= length(voltages))
			efficiencies[index] = clamp(1 - max(0, source_potential - (voltages[index] || 0)) / MATERIAL_SERVICE_NOMINAL_VOLTAGE, 0.05, 1)
	pending_reduced = null
	pending_sources = null
	pending_consumers = null
	return TRUE

/// `sources` / `consumers`: vertex index -> watts (alists; vertex_for() names the vertex).
/datum/material_power_graph/proc/resolve_loads(alist/sources, alist/consumers)
	resistance_ms = 0
	solve_ms = 0
	var/async_result = poll_async_solve()
	if(isnull(async_result))
		return 2
	var/changed = refresh_resistance()
	efficiencies = alist()
	var/list/injections = new /list(length(vertices))
	var/total_source = 0
	var/total_demand = 0
	for(var/index in sources)
		if(index >= 1 && index <= length(vertices))
			total_source += sources[index]
	for(var/index in consumers)
		if(index >= 1 && index <= length(vertices))
			injections[index] -= consumers[index] / MATERIAL_SERVICE_NOMINAL_VOLTAGE
			total_demand += consumers[index]
	if(total_source <= 0 || total_demand <= 0)
		for(var/list/edge as anything in edges)
			edge[MATERIAL_POWER_EDGE_CURRENT] = 0
		loss_watts = 0
		last_injections = null
		return
	for(var/index in sources)
		if(index >= 1 && index <= length(vertices))
			injections[index] += sources[index] / total_source * total_demand / MATERIAL_SERVICE_NOMINAL_VOLTAGE
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
	if(changed && !has_superconductors && !COOLDOWN_FINISHED(src, next_solve))
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
			COOLDOWN_START(src, next_solve, MATERIAL_POWER_GRAPH_SETTLEMENT_INTERVAL)
			return 2
		if(!solve(injections))
			return FALSE
		last_injections = injections.Copy()
		COOLDOWN_START(src, next_solve, MATERIAL_POWER_GRAPH_SETTLEMENT_INTERVAL)
	var/source_potential = 0
	for(var/index in sources)
		if(index >= 1 && index <= length(vertices))
			source_potential += (voltages[index] || 0) * sources[index] / total_source
	for(var/index in consumers)
		if(index >= 1 && index <= length(vertices))
			efficiencies[index] = clamp(1 - max(0, source_potential - (voltages[index] || 0)) / MATERIAL_SERVICE_NOMINAL_VOLTAGE, 0.05, 1)

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
			var/obj/structure/cable/cable = material_power_cable(run[i])
			if(!cable)
				continue
			cable_current[cable] = max(cable_current[cable] || 0, abs(current))
			cable_heat[cable] += edge_energy * weights[i] / total_weight
	for(var/entity in energized_cables)
		var/obj/structure/cable/cable = material_power_cable(entity)
		if(cable && !(cable in cable_current))
			cable.material_current = 0
			var/datum/material_service/idle_service = material_service_of(cable)
			if(idle_service)
				idle_service.last_input_watts = 0
				idle_service.last_output_watts = 0
	energized_cables = list()
	for(var/obj/structure/cable/cable as anything in cable_current)
		energized_cables += cable.power_entity

		cable.material_current = cable_current[cable]
		var/heat = cable_heat[cable]
		cable.material_service_event(MATERIAL_EVENT_WORK, 1)
		var/datum/material_service/service = material_service_of(cable)
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
