/datum/controller/subsystem/air
	var/next_rust_pipe_port_id = 1
	var/list/rust_pipe_ports
	var/list/rust_pipe_region_networks
	var/rust_pipe_pending_operations = ""
	/// M2 (simulation.md §5): device edges by DM id -> owning machine.
	var/next_rust_device_id = 1
	var/list/rust_pipe_devices
	var/rust_device_pending_operations = ""

/obj/machinery/atmospherics
	/// Stable IDs for this machine's physical gas ports. Rust owns connectivity.
	var/list/rust_pipe_port_ids
	/// Only components without a pre-existing gas slot (valves/connectors) use this.
	var/list/datum/gas_mixture/rust_unbound_port_air
	/// M2: this machine's device edge id, or 0 if it has none registered.
	var/rust_device_id = 0

/obj/machinery/atmospherics/proc/rust_pipe_port_count()
	return 0

/obj/machinery/atmospherics/proc/rust_pipe_port_node(index)
	return null

/obj/machinery/atmospherics/proc/rust_pipe_port_neighbors(index)
	var/obj/machinery/atmospherics/node = rust_pipe_port_node(index)
	return node ? list(node) : null

/obj/machinery/atmospherics/proc/rust_pipe_port_air(index)
	var/datum/gas_mixture/air
	if(rust_unbound_port_air && index <= length(rust_unbound_port_air))
		air = rust_unbound_port_air[index]
	if(!air)
		air = new(max(rust_pipe_port_volume(index), 1))
		if(!rust_unbound_port_air)
			rust_unbound_port_air = list()
		if(length(rust_unbound_port_air) < index)
			rust_unbound_port_air.len = index
		rust_unbound_port_air[index] = air
	return air

/obj/machinery/atmospherics/proc/rust_pipe_port_volume(index)
	return 0

/obj/machinery/atmospherics/proc/rust_pipe_port_network(index)
	return null

/obj/machinery/atmospherics/proc/rust_pipe_port_index_for_neighbor(obj/machinery/atmospherics/neighbor)
	for(var/index = 1 to rust_pipe_port_count())
		if(rust_pipe_port_node(index) == neighbor)
			return index
	return 0

/obj/machinery/atmospherics/proc/rust_pipe_internal_edges()
	return null

/obj/machinery/atmospherics/proc/rust_bind_pipe_port(index, datum/pipe_network/network, datum/gas_mixture/network_air)
	var/datum/gas_mixture/old_air
	if(rust_unbound_port_air && index <= length(rust_unbound_port_air))
		old_air = rust_unbound_port_air[index]
	if(old_air && old_air != network_air)
		qdel(old_air)
		rust_unbound_port_air[index] = null
	return FALSE

/obj/machinery/atmospherics/proc/rust_allocate_pipe_ports()
	var/port_count = rust_pipe_port_count()
	if(port_count <= 0)
		return
	if(!rust_pipe_port_ids)
		rust_pipe_port_ids = list()
	if(length(rust_pipe_port_ids) < port_count)
		rust_pipe_port_ids.len = port_count
	for(var/index = 1 to port_count)
		if(index <= length(rust_pipe_port_ids) && rust_pipe_port_ids[index])
			continue
		var/port_id = SSair.next_rust_pipe_port_id++
		rust_pipe_port_ids[index] = port_id
		SSair.rust_pipe_ports["[port_id]"] = list(src, index)

/obj/machinery/atmospherics/proc/rust_register_pipe_topology(commit = TRUE)
	rust_allocate_pipe_ports()
	rust_register_pipe_port_data()
	rust_register_pipe_edges()
	if(commit && !SSexplosions?.is_bulk_resolving())
		SSair.rust_commit_pending_pipenets()

/// Queue authoritative port records without publishing any edges. Bulk graph
/// construction must publish every endpoint before it queues connectivity.
/obj/machinery/atmospherics/proc/rust_register_pipe_port_data()
	for(var/index = 1 to rust_pipe_port_count())
		var/datum/gas_mixture/port_air = rust_pipe_port_air(index)
		if(port_air)
			SSair.rust_queue_pipe_operation(RUST_PIPE_OP_UPSERT, rust_pipe_port_ids[index], port_air.arena_id(), rust_pipe_port_volume(index))

/// Queue physical and internal connectivity after all referenced ports exist.
/obj/machinery/atmospherics/proc/rust_register_pipe_edges()
	for(var/index = 1 to rust_pipe_port_count())
		for(var/obj/machinery/atmospherics/neighbor as anything in rust_pipe_port_neighbors(index))
			if(!neighbor)
				continue
			var/neighbor_index = neighbor.rust_pipe_port_index_for_neighbor(src)
			if(neighbor_index && neighbor.rust_pipe_port_ids && neighbor_index <= length(neighbor.rust_pipe_port_ids))
				SSair.rust_queue_pipe_operation(RUST_PIPE_OP_CONNECT, rust_pipe_port_ids[index], neighbor.rust_pipe_port_ids[neighbor_index])
	var/list/internal_edges = rust_pipe_internal_edges()
	for(var/edge_index = 1, edge_index < length(internal_edges), edge_index += 2)
		SSair.rust_queue_pipe_operation(RUST_PIPE_OP_CONNECT, rust_pipe_port_ids[internal_edges[edge_index]], rust_pipe_port_ids[internal_edges[edge_index + 1]])

/obj/machinery/atmospherics/proc/rust_set_physical_edges(enabled, commit = TRUE)
	if(!length(rust_pipe_port_ids))
		return
	for(var/index = 1 to rust_pipe_port_count())
		for(var/obj/machinery/atmospherics/neighbor as anything in rust_pipe_port_neighbors(index))
			if(!neighbor)
				continue
			var/neighbor_index = neighbor.rust_pipe_port_index_for_neighbor(src)
			if(!neighbor_index || !length(neighbor.rust_pipe_port_ids))
				continue
			SSair.rust_queue_pipe_operation(enabled ? RUST_PIPE_OP_CONNECT : RUST_PIPE_OP_DISCONNECT, rust_pipe_port_ids[index], neighbor.rust_pipe_port_ids[neighbor_index])
	if(commit)
		SSair.rust_commit_pending_pipenets()

/obj/machinery/atmospherics/proc/rust_rewire_internal_ports(list/old_edges, list/new_edges)
	// Map-loaded valves establish state during Initialize(), before SSair assigns
	// stable ports. setup_rust_pipenets() publishes that final state later.
	if(!length(rust_pipe_port_ids))
		return
	for(var/edge_index = 1, edge_index < length(old_edges), edge_index += 2)
		SSair.rust_queue_pipe_operation(RUST_PIPE_OP_DISCONNECT, rust_pipe_port_ids[old_edges[edge_index]], rust_pipe_port_ids[old_edges[edge_index + 1]])
	for(var/edge_index = 1, edge_index < length(new_edges), edge_index += 2)
		SSair.rust_queue_pipe_operation(RUST_PIPE_OP_CONNECT, rust_pipe_port_ids[new_edges[edge_index]], rust_pipe_port_ids[new_edges[edge_index + 1]])
	if(!SSexplosions?.is_bulk_resolving())
		SSair.rust_commit_pending_pipenets()

/obj/machinery/atmospherics/proc/rust_unregister_pipe_topology()
	rust_unregister_device()
	for(var/index = 1 to length(rust_pipe_port_ids))
		var/port_id = rust_pipe_port_ids[index]
		var/port_volume = rust_pipe_port_volume(index)
		var/turf/open/release_turf = get_turf(src)
		if(port_volume > 0 && release_turf?.air)
			SSair?.rust_queue_pipe_operation(RUST_PIPE_OP_REMOVE_TO_MIXTURE, port_id, release_turf.air.arena_id(), release_turf.air.return_volume())
		else
			SSair?.rust_queue_pipe_operation(RUST_PIPE_OP_REMOVE, port_id)
		SSair?.rust_pipe_ports.Remove("[port_id]")
	rust_pipe_port_ids = null
	if(SSair && !SSexplosions?.is_bulk_resolving())
		SSair.rust_commit_pending_pipenets()

/// Drop this compatibility membership without attempting to destroy a
/// Rust-owned region wrapper. The topology commit is the sole wrapper owner.
/obj/machinery/atmospherics/proc/rust_release_network_wrapper(datum/pipe_network/network)
	if(!network || QDELETED(network))
		return
	if(network.rust_authoritative)
		network.normal_members -= src
		unregister_network_membership(network)
		return
	qdel(network)

/datum/controller/subsystem/air/proc/rust_pipe_operation(opcode, first, second, volume = 0)
	return "[opcode],[first],[second],[volume];"

/datum/controller/subsystem/air/proc/rust_queue_pipe_operation(opcode, first, second = 0, volume = 0)
	rust_pipe_pending_operations += rust_pipe_operation(opcode, first, second, volume)

/datum/controller/subsystem/air/proc/rust_commit_pending_pipenets()
	if(!length(rust_pipe_pending_operations))
		return
	var/operations = rust_pipe_pending_operations
	rust_pipe_pending_operations = ""
	rust_apply_pipe_topology(operations)

// ---- M2: device edges (simulation.md §5) ------------------------------

/datum/controller/subsystem/air/proc/rust_device_operation(opcode, id, port_a = 0, port_b = 0, law_kind = 0, p0 = 0, p1 = 0, p2 = 0, p3 = 0)
	return "[opcode],[id],[port_a],[port_b],[law_kind],[p0],[p1],[p2],[p3];"

/datum/controller/subsystem/air/proc/rust_queue_device_operation(opcode, id, port_a = 0, port_b = 0, law_kind = 0, p0 = 0, p1 = 0, p2 = 0, p3 = 0)
	rust_device_pending_operations += rust_device_operation(opcode, id, port_a, port_b, law_kind, p0, p1, p2, p3)

/datum/controller/subsystem/air/proc/rust_commit_pending_devices()
	if(!length(rust_device_pending_operations))
		return
	var/operations = rust_device_pending_operations
	rust_device_pending_operations = ""
	vg_pipenet_device_batch(operations)

/// Registers (or replaces) `machine`'s device edge between its two ports
/// `port_index_a`/`port_index_b` (1-based, `rust_pipe_port_ids` indices),
/// with the flow law `law_kind`/`p0..p3` (`RUST_DEVICE_LAW_*`). Allocates a
/// stable device id on first use.
/obj/machinery/atmospherics/proc/rust_set_device(port_index_a, port_index_b, law_kind, p0 = 0, p1 = 0, p2 = 0, p3 = 0)
	if(!rust_pipe_port_ids || port_index_a > length(rust_pipe_port_ids) || port_index_b > length(rust_pipe_port_ids))
		return FALSE
	if(!rust_device_id)
		rust_device_id = SSair.next_rust_device_id++
		if(!SSair.rust_pipe_devices)
			SSair.rust_pipe_devices = list()
		SSair.rust_pipe_devices["[rust_device_id]"] = src
	SSair.rust_queue_device_operation(RUST_DEVICE_OP_SET, rust_device_id, rust_pipe_port_ids[port_index_a], rust_pipe_port_ids[port_index_b], law_kind, p0, p1, p2, p3)
	SSair.rust_commit_pending_devices()
	return TRUE

/obj/machinery/atmospherics/proc/rust_unregister_device()
	if(!rust_device_id)
		return
	SSair.rust_queue_device_operation(RUST_DEVICE_OP_REMOVE, rust_device_id)
	SSair.rust_pipe_devices?.Remove("[rust_device_id]")
	rust_device_id = 0
	SSair.rust_commit_pending_devices()

/// Called once per gas tick with this tick's flow-law result (M2). The base
/// implementation does nothing; devices with a UI/events override it.
/obj/machinery/atmospherics/proc/rust_device_stepped(moles, power_w, target_reached)
	return

/// Runs every device edge's flow law for this tick and dispatches results
/// (`SSair.fire()`, from `process_pipenets`).
/datum/controller/subsystem/air/proc/rust_step_pipe_devices()
	if(!length(rust_pipe_devices))
		return
	var/dt = wait / 10
	var/list/result = vg_pipenet_step_devices(dt)
	var/cursor = 1
	while(cursor <= length(result))
		var/id = result[cursor++]
		var/moles = result[cursor++]
		var/power_w = result[cursor++]
		var/target_reached = result[cursor++]
		var/obj/machinery/atmospherics/device = rust_pipe_devices["[id]"]
		device?.rust_device_stepped(moles, power_w, target_reached)

/// Publish the complete map topology once, then materialize all compatibility
/// `/datum/pipe_network` wrappers from Rust's atomic connected-region result.
/datum/controller/subsystem/air/proc/setup_rust_pipenets()
	rust_pipe_ports = list()
	rust_pipe_region_networks = list()
	next_rust_pipe_port_id = 1
	var/operations = rust_pipe_operation(RUST_PIPE_OP_CLEAR, 0, 0)

	for(var/obj/machinery/atmospherics/machine in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		machine.rust_allocate_pipe_ports()
		for(var/index = 1 to machine.rust_pipe_port_count())
			var/datum/gas_mixture/port_air = machine.rust_pipe_port_air(index)
			if(!port_air)
				continue
			operations += rust_pipe_operation(RUST_PIPE_OP_UPSERT, machine.rust_pipe_port_ids[index], port_air.arena_id(), machine.rust_pipe_port_volume(index))
		if(length(GLOB.clients) && TICK_CHECK)
			stoplag()

	var/list/seen_edges = list()
	for(var/obj/machinery/atmospherics/machine in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		for(var/index = 1 to machine.rust_pipe_port_count())
			for(var/obj/machinery/atmospherics/neighbor as anything in machine.rust_pipe_port_neighbors(index))
				if(!neighbor)
					continue
				var/neighbor_index = neighbor.rust_pipe_port_index_for_neighbor(machine)
				if(!neighbor_index || neighbor_index > length(neighbor.rust_pipe_port_ids))
					continue
				var/first = machine.rust_pipe_port_ids[index]
				var/second = neighbor.rust_pipe_port_ids[neighbor_index]
				var/edge_key = first < second ? "[first]:[second]" : "[second]:[first]"
				if(seen_edges[edge_key])
					continue
				seen_edges[edge_key] = TRUE
				operations += rust_pipe_operation(RUST_PIPE_OP_CONNECT, first, second)
		var/list/internal_edges = machine.rust_pipe_internal_edges()
		for(var/edge_index = 1, edge_index < length(internal_edges), edge_index += 2)
			var/first_index = internal_edges[edge_index]
			var/second_index = internal_edges[edge_index + 1]
			operations += rust_pipe_operation(RUST_PIPE_OP_CONNECT, machine.rust_pipe_port_ids[first_index], machine.rust_pipe_port_ids[second_index])
		if(length(GLOB.clients) && TICK_CHECK)
			stoplag()

	rust_apply_pipe_topology(operations)

/// Applies one topology transaction to the Rust pipe network (R7) and rebuilds
/// the compatibility wrappers of every region whose membership changed. Gas
/// never passes through DM: the network pools, splits and releases it, and
/// each region's air datum is bound to the region's gas handle.
/datum/controller/subsystem/air/proc/rust_apply_pipe_topology(operations)
	var/list/result = vg_pipenet_topology_batch(operations)
	if(!islist(result))
		CRASH("Rust pipenet topology did not return a region list")
	var/list/transitions = list()
	var/list/retired_regions = list()
	var/cursor = 1
	while(cursor <= length(result))
		if(length(result) - cursor + 1 < 4)
			CRASH("Rust pipenet topology returned a truncated region header")
		var/region = result[cursor++]
		var/port_count = result[cursor++]
		var/prior_count = result[cursor++]
		var/volume = result[cursor++]
		var/list/ports = result.Copy(cursor, cursor + port_count)
		cursor += port_count
		var/list/prior_regions = result.Copy(cursor, cursor + prior_count)
		cursor += prior_count
		for(var/prior_region in prior_regions)
			retired_regions["[prior_region]"] = TRUE
		if(volume < 0)
			retired_regions["[region]"] = TRUE
			continue
		transitions += list(list("region" = region, "ports" = ports, "volume" = volume))

	for(var/prior_key in retired_regions)
		var/datum/pipe_network/old_network = rust_pipe_region_networks[prior_key]
		rust_pipe_region_networks.Remove(prior_key)
		rust_retire_pipe_network(old_network)
	for(var/list/transition as anything in transitions)
		var/datum/gas_mixture/region_air = new(max(transition["volume"], 1))
		vg_bind_handle(region_air, transition["region"])
		transition["air"] = region_air
		rust_materialize_pipe_region(transition)

/datum/controller/subsystem/air/proc/rust_retire_pipe_network(datum/pipe_network/network)
	if(!network)
		return
	STOP_PROCESSING_PIPENET(network)
	var/list/datum/pipeline/old_lines = network.line_members
	var/list/obj/machinery/atmospherics/old_members = network.normal_members
	var/datum/gas_mixture/old_air = network.air
	network.rust_authoritative = FALSE
	network.line_members = null
	network.normal_members = null
	network.air = null
	network.gases = null
	network.leaks = null
	// The region's gas lives in the Rust network; the datum is only a handle.
	for(var/obj/machinery/atmospherics/member as anything in old_members)
		member.unregister_network_membership(network)
		member.material_service?.environment_changed()
	for(var/datum/pipeline/line as anything in old_lines)
		for(var/obj/machinery/atmospherics/pipe/pipe as anything in line.members)
			pipe.material_service?.environment_changed()
		line.network = null
		line.network_memberships = null
		line.air = null
		line.members = null
		line.edges = null
		line.leaks = null
		qdel(line)
	qdel(network)
	qdel(old_air)

/datum/controller/subsystem/air/proc/rust_materialize_pipe_region(list/transition)
	var/region = transition["region"]
	var/list/ports = transition["ports"]
	var/volume = transition["volume"]
	var/datum/gas_mixture/region_air = transition["air"]
	var/datum/pipe_network/network = new
	network.rust_authoritative = TRUE
	network.air = region_air
	network.gases = list(region_air)
	network.volume = volume
	network.update = FALSE
	rust_pipe_region_networks["[region]"] = network

	var/list/obj/machinery/atmospherics/pipe/region_pipes = list()
	for(var/port_id in ports)
		var/list/record = rust_pipe_ports["[port_id]"]
		var/obj/machinery/atmospherics/machine = record?[1]
		var/index = record?[2]
		if(!machine)
			continue
		if(istype(machine, /obj/machinery/atmospherics/pipe))
			region_pipes |= machine
		else
			network.add_normal_member(machine)
		machine.rust_bind_pipe_port(index, network, region_air)
		// A region replacement can preserve pressure/composition, so gas-dirty
		// publication alone cannot tell sleepers to subscribe to the new handle.
		machine.material_service?.environment_changed()

	if(length(region_pipes))
		var/datum/pipeline/pipeline = new
		pipeline.air = region_air
		pipeline.volume = 0
		pipeline.members = region_pipes
		pipeline.edges = list()
		pipeline.leaks = list()
		pipeline.network = network
		for(var/obj/machinery/atmospherics/pipe/pipe as anything in region_pipes)
			pipe.parent = pipeline
			pipeline.volume += pipe.volume
			if(pipe.leaking)
				pipeline.leaks |= pipe
				network.leaks |= pipe
		network.add_line_member(pipeline)

// Fixed pipes are one conductive Rust port regardless of sprite geometry.
/obj/machinery/atmospherics/pipe/rust_pipe_port_count()
	return 1

/obj/machinery/atmospherics/pipe/rust_pipe_port_node(index)
	return null

/obj/machinery/atmospherics/pipe/rust_pipe_port_neighbors(index)
	return pipeline_expansion()

/obj/machinery/atmospherics/pipe/rust_pipe_port_index_for_neighbor(obj/machinery/atmospherics/neighbor)
	return 1

/obj/machinery/atmospherics/pipe/rust_pipe_port_air(index)
	if(parent?.air)
		return parent.air
	if(!air_temporary)
		air_temporary = new(max(volume, 1))
	return air_temporary

/obj/machinery/atmospherics/pipe/rust_pipe_port_volume(index)
	return volume

/obj/machinery/atmospherics/pipe/rust_pipe_port_network(index)
	return parent?.network

/obj/machinery/atmospherics/pipe/rust_bind_pipe_port(index, datum/pipe_network/network, datum/gas_mixture/network_air)
	if(air_temporary && air_temporary != network_air)
		qdel(air_temporary)
	air_temporary = null
	return TRUE

/obj/machinery/atmospherics/unary/rust_pipe_port_count()
	return 1

/obj/machinery/atmospherics/unary/rust_pipe_port_node(index)
	return node

/obj/machinery/atmospherics/unary/rust_pipe_port_air(index)
	return air_contents

/obj/machinery/atmospherics/unary/rust_pipe_port_volume(index)
	return 200

/obj/machinery/atmospherics/unary/rust_pipe_port_network(index)
	return network

/obj/machinery/atmospherics/unary/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	if(air_contents != network_air)
		qdel(air_contents)
	air_contents = network_air
	network = new_network
	return TRUE

/obj/machinery/atmospherics/binary/rust_pipe_port_count()
	return 2

/obj/machinery/atmospherics/binary/rust_pipe_port_node(index)
	return index == 1 ? node1 : node2

/obj/machinery/atmospherics/binary/rust_pipe_port_air(index)
	return index == 1 ? air1 : air2

/obj/machinery/atmospherics/binary/rust_pipe_port_volume(index)
	return 200

/obj/machinery/atmospherics/binary/rust_pipe_port_network(index)
	return index == 1 ? network1 : network2

/obj/machinery/atmospherics/binary/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	if(index == 1)
		if(air1 != network_air)
			qdel(air1)
		air1 = network_air
		network1 = new_network
	else
		if(air2 != network_air)
			qdel(air2)
		air2 = network_air
		network2 = new_network
	return TRUE

/obj/machinery/atmospherics/trinary/rust_pipe_port_count()
	return 3

/obj/machinery/atmospherics/trinary/rust_pipe_port_node(index)
	return index == 1 ? node1 : (index == 2 ? node2 : node3)

/obj/machinery/atmospherics/trinary/rust_pipe_port_air(index)
	return index == 1 ? air1 : (index == 2 ? air2 : air3)

/obj/machinery/atmospherics/trinary/rust_pipe_port_volume(index)
	return 200

/obj/machinery/atmospherics/trinary/rust_pipe_port_network(index)
	return index == 1 ? network1 : (index == 2 ? network2 : network3)

/obj/machinery/atmospherics/trinary/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	if(index == 1)
		if(air1 != network_air)
			qdel(air1)
		air1 = network_air
		network1 = new_network
	else if(index == 2)
		if(air2 != network_air)
			qdel(air2)
		air2 = network_air
		network2 = new_network
	else
		if(air3 != network_air)
			qdel(air3)
		air3 = network_air
		network3 = new_network
	return TRUE

/obj/machinery/atmospherics/portables_connector/rust_pipe_port_count()
	return 1

/obj/machinery/atmospherics/portables_connector/rust_pipe_port_node(index)
	return node

/obj/machinery/atmospherics/portables_connector/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	if(index == 2)
		connected_device?.set_port_network_air(network_air)
		return TRUE
	. = ..()
	network = new_network
	return TRUE

/obj/machinery/atmospherics/valve/rust_pipe_port_count()
	return 2

/obj/machinery/atmospherics/valve/rust_pipe_port_node(index)
	return index == 1 ? node1 : node2

/obj/machinery/atmospherics/valve/rust_pipe_internal_edges()
	return open ? list(1, 2) : null

/obj/machinery/atmospherics/valve/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 1)
		network_node1 = new_network
	else
		network_node2 = new_network
	return TRUE

/obj/machinery/atmospherics/tvalve/rust_pipe_port_count()
	return 3

/obj/machinery/atmospherics/tvalve/rust_pipe_port_node(index)
	return index == 1 ? node1 : (index == 2 ? node2 : node3)

/obj/machinery/atmospherics/tvalve/rust_pipe_internal_edges()
	return state ? list(1, 2) : list(1, 3)

/obj/machinery/atmospherics/tvalve/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	. = ..()
	if(index == 1)
		network_node1 = new_network
	else if(index == 2)
		network_node2 = new_network
	else
		network_node3 = new_network
	return TRUE

/obj/machinery/atmospherics/omni/rust_pipe_port_count()
	return length(ports)

/obj/machinery/atmospherics/omni/rust_pipe_port_node(index)
	var/datum/omni_port/port = ports[index]
	return port?.node

/obj/machinery/atmospherics/omni/rust_pipe_port_air(index)
	var/datum/omni_port/port = ports[index]
	return port?.air

/obj/machinery/atmospherics/omni/rust_pipe_port_volume(index)
	return 200

/obj/machinery/atmospherics/omni/rust_pipe_port_network(index)
	var/datum/omni_port/port = ports[index]
	return port?.network

/obj/machinery/atmospherics/omni/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	var/datum/omni_port/port = ports[index]
	if(!port)
		return FALSE
	if(port.air != network_air)
		qdel(port.air)
	port.air = network_air
	port.network = new_network
	return TRUE

/obj/machinery/atmospherics/pipeturbine/rust_pipe_port_count()
	return 2

/obj/machinery/atmospherics/pipeturbine/rust_pipe_port_node(index)
	return index == 1 ? node1 : node2

/obj/machinery/atmospherics/pipeturbine/rust_pipe_port_air(index)
	return index == 1 ? air_in : air_out

/obj/machinery/atmospherics/pipeturbine/rust_pipe_port_volume(index)
	return index == 1 ? 200 : 800

/obj/machinery/atmospherics/pipeturbine/rust_pipe_port_network(index)
	return index == 1 ? network1 : network2

/obj/machinery/atmospherics/pipeturbine/rust_bind_pipe_port(index, datum/pipe_network/new_network, datum/gas_mixture/network_air)
	if(index == 1)
		if(air_in != network_air)
			qdel(air_in)
		air_in = network_air
		network1 = new_network
	else
		if(air_out != network_air)
			qdel(air_out)
		air_out = network_air
		network2 = new_network
	return TRUE
