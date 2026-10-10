/datum/system/air
	/// Pipe region gas handle -> its /datum/pipe_network wrapper (numeric keys).
	var/alist/rust_pipe_region_networks = alist()
	/// Topology changed since the last vg_pipe_commit().
	var/rust_pipe_topology_dirty = FALSE
	/// Registered device edges (M2, simulation.md §5), for the step's early out.
	var/rust_pipe_device_count = 0

/// One physical gas port of a pipe machine: a World entity (its handle is
/// the port's identity in Rust), found again through SSvg's entity table.
/datum/pipe_port
	var/obj/machinery/atmospherics/machine
	/// The machine's port index (rust_pipe_port_ids).
	var/index
	var/handle = 0

/datum/pipe_port/New(obj/machinery/atmospherics/machine, index)
	..()
	rel_set(src, nameof(machine), machine)
	src.index = index
	handle = SSvg.bind_datum(src)

/datum/pipe_port/lifecycle_unbind()
	. = ..()
	if(handle)
		SSvg.unbind_datum(src, handle)
		handle = 0

/// The live port behind `handle`, or null.
/proc/rust_pipe_port_of(handle)
	var/datum/pipe_port/port = SSvg.entity_lookup(handle)
	return (istype(port) && port.handle == handle) ? port : null

/// A new port for `machine`'s `index`; returns its handle.
/proc/rust_new_pipe_port(obj/machinery/atmospherics/machine, index)
	var/datum/pipe_port/port = new(machine, index)
	return port.handle

/// Frees the port behind `handle` (after Rust has removed it).
/proc/rust_free_pipe_port(handle)
	spent(rust_pipe_port_of(handle))

/// An entity handle's World slot index (a component's entity-index field).
/proc/vg_entity_index(handle)
	return (handle - 1) & VG_ENTITY_INDEX_MASK

/obj/machinery/atmospherics
	/// This machine's physical gas ports, by index: /datum/pipe_port entity handles. Rust owns connectivity.
	var/list/rust_pipe_port_ids
	/// Only components without a pre-existing gas slot (valves/connectors) use this: port
	/// index (text) -> the private mixture this machine owns until Rust binds the port.
	var/list/datum/gas_mixture/rust_unbound_port_air

	/// M2: this machine's (one) device edge, an entity handle bound to this
	/// machine (SSvg.bind_datum()), or 0 if it has none
	/// registered. Single-edge devices (pump, volume pump, passive gate,
	/// vent pump, vent scrubber) use this; a multi-port device (filter,
	/// mixer) uses `rust_device_ids`/the `_n` procs below instead.
	var/rust_device_id = 0
	/// The budget group this machine's filter / mixer legs share (rust_set_budget_leg()); 0 until it has one.
	var/rust_budget_group = 0
	/// This device's one flow law, if it has one: the bare `DeviceFlow`
	/// row's entity handle (`rust_architecture.md` §8.5 step 6's
	/// pipe-device redesign) -- not a DM object, never placed on the map;
	/// 0 means none registered yet.
	var/rust_flow_entity = 0
	/// This device's valve gate, if it has one: a bare `DeviceValve` row's
	/// entity handle, same pattern as `rust_flow_entity`.
	var/rust_valve_entity = 0
	/// A multi-port device's (filter, mixer) device edges, one per named
	/// slot (an arbitrary string key the caller picks, e.g. "filtered"/
	/// "clean", or "a"/"b") -- the N-edges-per-machine extension of
	/// `rust_device_id` (`rust_set_device_n()` and friends, below).
	var/list/rust_device_ids
	/// Per slot, that edge's `DeviceFlow` row entity (`rust_flow_entity`'s
	/// N-edge counterpart).
	var/list/rust_flow_entities

CAPABILITIES(/obj/machinery/atmospherics)
	blast_contents() // a ventcrawler in the pipes takes the full blast
	ref_one(nameof(node1))
	ref_one(nameof(node2))
	owns_many(nameof(rust_unbound_port_air), /datum/gas_mixture)
	op("fit_material", stack(/obj/item/stack/material, 1), label("Fit engineered material"), wait(0), when(PROC_REF(material_fittable)),
		needs(req_bool(PROC_REF(no_shell), because = MSG(atmospherics/has_shell))), then(PROC_REF(material_fitted)))
	// a pipe painter used on anything it cannot paint does nothing (its own op paints a pipe, a tier above)
	op("painter", item(/obj/item/pipe_painter), wait(0), then(PROC_REF(painter_swallowed)))
	param(nameof(dir), pos = 1)

/obj/machinery/atmospherics/proc/rust_pipe_port_count()
	return 0

/obj/machinery/atmospherics/proc/rust_pipe_port_node(index)
	return null

/obj/machinery/atmospherics/proc/rust_pipe_port_neighbors(index)
	var/obj/machinery/atmospherics/node = rust_pipe_port_node(index)
	return node ? list(node) : null

/obj/machinery/atmospherics/proc/rust_pipe_port_air(index)
	var/datum/gas_mixture/air = rust_unbound_port_air?["[index]"]
	if(!air)
		air = new(max(rust_pipe_port_volume(index), 1))
		rel_add(src, nameof(rust_unbound_port_air), air, "[index]")
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
	var/datum/gas_mixture/old_air = rust_unbound_port_air?["[index]"]
	if(old_air && old_air != network_air)
		rel_add(src, nameof(rust_unbound_port_air), null, "[index]")
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
		var/port_id = rust_new_pipe_port(src, index) // a numeric Rust port id, not an entity
		rust_pipe_port_ids[index] = port_id

/obj/machinery/atmospherics/proc/rust_register_pipe_topology(commit = TRUE)
	rust_allocate_pipe_ports()
	rust_register_pipe_port_data()
	rust_register_pipe_edges()
	if(GLOB.heat_edge_records_of[src])
		heat_entries_complete(src) // its heat entries that name a port (HEAT_PORT(i)) can be made now
	if(commit && !SSexplosions.is_bulk_resolving())
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
	if(!SSexplosions.is_bulk_resolving())
		SSair.rust_commit_pending_pipenets()

/obj/machinery/atmospherics/proc/rust_unregister_pipe_topology()
	rust_unregister_device()
	rust_unregister_all_devices_n()
	for(var/index = 1 to length(rust_pipe_port_ids))
		var/port_id = rust_pipe_port_ids[index]
		var/port_volume = rust_pipe_port_volume(index)
		var/turf/open/release_turf = get_turf(src)
		var/release_to = port_volume > 0 && release_turf?.air ? release_turf.air.arena_id() : 0
		// Batched destroy: one removal call for the whole doomed set (init_and_turfs.md §4.4).
		if(dq_pipe_port_remove(src, port_id, release_to))
			continue
		if(release_to)
			SSair?.rust_queue_pipe_operation(RUST_PIPE_OP_REMOVE_TO_MIXTURE, port_id, release_to, release_turf.air.return_volume())
		else
			SSair?.rust_queue_pipe_operation(RUST_PIPE_OP_REMOVE, port_id)
		rust_free_pipe_port(port_id)
	rust_pipe_port_ids = null
	if(SSair && !SSexplosions.is_bulk_resolving())
		SSair.rust_commit_pending_pipenets()

/// Drop this compatibility membership without attempting to destroy a
/// Rust-owned region wrapper. The topology commit is the sole wrapper owner.
/obj/machinery/atmospherics/proc/rust_release_network_wrapper(datum/pipe_network/network)
	if(!network || QDELETED(network))
		return
	if(network.rust_authoritative)
		rel_remove(network, nameof(network.normal_members), src)
		return
	spent(network)

/// One topology edit (RUST_PIPE_OP_*), applied to the Rust network now;
/// rust_commit_pending_pipenets() commits the batch and rebuilds wrappers.
/// `first`/`second` are port handles (REMOVE_TO_MIXTURE: port, mixture handle).
/datum/system/air/proc/rust_queue_pipe_operation(opcode, first, second = 0, volume = 0)
	rust_pipe_topology_dirty = TRUE
	switch(opcode)
		if(RUST_PIPE_OP_UPSERT)
			vg_pipe_upsert(first, second, volume)
		if(RUST_PIPE_OP_REMOVE)
			vg_pipe_remove(first, 0)
		if(RUST_PIPE_OP_CONNECT)
			vg_pipe_connect(first, second)
		if(RUST_PIPE_OP_DISCONNECT)
			vg_pipe_disconnect(first, second)
		if(RUST_PIPE_OP_CLEAR)
			vg_pipe_clear()
		if(RUST_PIPE_OP_REMOVE_TO_MIXTURE)
			vg_pipe_remove(first, second)

/datum/system/air/proc/rust_commit_pending_pipenets()
	if(!rust_pipe_topology_dirty)
		return
	// Inside a batched destroy the topology commits once, after the batch's
	// one port removal call (dq_batch_flush()).
	if(dq_batch_defer_pipe_commit())
		return
	rust_pipe_topology_dirty = FALSE
	rust_apply_pipe_commit()

// ---- M2: device edges (simulation.md §5) ------------------------------

/// One device edge edit (RUST_DEVICE_OP_*), applied to the Rust network now.
/// `id` is the device's entity handle; SET uses `f1`/`f2` as the two port
/// handles, SET_TURF `f1` the port and `f2` the turf's gas handle. A device's
/// flow(s) and valve are rows set through the generated component accessors.
/datum/system/air/proc/rust_queue_device_operation(opcode, id, f1 = 0, f2 = 0)
	switch(opcode)
		if(RUST_DEVICE_OP_SET)
			vg_pipe_device_set(id, f1, f2)
		if(RUST_DEVICE_OP_SET_TURF)
			vg_pipe_device_set_turf(id, f1, f2)
		if(RUST_DEVICE_OP_REMOVE)
			vg_pipe_device_remove(id)

/// Kept for callers that batch device edits: they apply as queued.
/datum/system/air/proc/rust_commit_pending_devices()
	return

/// A new device edge handle bound to `machine`.
/proc/rust_new_pipe_device(obj/machinery/atmospherics/machine)
	SSair.rust_pipe_device_count++
	return SSvg.bind_datum(machine)

/// Frees a device edge handle (after Rust has removed the edge).
/proc/rust_free_pipe_device(obj/machinery/atmospherics/machine, id)
	SSair.rust_pipe_device_count = max(SSair.rust_pipe_device_count - 1, 0)
	SSvg.unbind_datum(machine, id)

/// Whether `id` is one of this machine's device edges.
/obj/machinery/atmospherics/proc/rust_owns_device(id)
	if(id == rust_device_id)
		return TRUE
	for(var/slot in rust_device_ids)
		if(rust_device_ids[slot] == id)
			return TRUE
	return FALSE

/// Allocates `src`'s stable device id on first use.
/obj/machinery/atmospherics/proc/rust_ensure_device_id()
	if(!rust_device_id)
		rust_device_id = rust_new_pipe_device(src)
	return rust_device_id

/// Registers (or replaces) `machine`'s device edge between its two ports
/// `port_index_a`/`port_index_b` (1-based, `rust_pipe_port_ids` indices).
/// Carries no flow law of its own -- `rust_set_device_flow()`/
/// `rust_set_device_valve()` attach that afterward.
/obj/machinery/atmospherics/proc/rust_set_device(port_index_a, port_index_b)
	if(!rust_pipe_port_ids || port_index_a > length(rust_pipe_port_ids) || port_index_b > length(rust_pipe_port_ids))
		return FALSE
	rust_ensure_device_id()
	SSair.rust_queue_device_operation(RUST_DEVICE_OP_SET, rust_device_id, rust_pipe_port_ids[port_index_a], rust_pipe_port_ids[port_index_b])
	SSair.rust_commit_pending_devices()
	return TRUE

/// Registers (or replaces) `machine`'s device edge between its port
/// `port_index` (1-based, a `rust_pipe_port_ids` index) and the turf gas
/// mixture `turf_air` faces (a vent pump or scrubber). Allocates a stable
/// device id on first use. `device::VentPump`/`Scrubber`'s `a` side is the
/// turf, so pass flow fields with that convention.
/obj/machinery/atmospherics/proc/rust_set_turf_device(port_index, datum/gas_mixture/turf_air)
	if(!rust_pipe_port_ids || port_index > length(rust_pipe_port_ids) || !turf_air)
		return FALSE
	// Space, walls and unsimulated turfs hand back a shared immutable vacuum
	// whose handle lives in the main arena; Rust turf devices can only address
	// turf-arena cells. A device on (or moved onto) such a tile has no turf edge.
	var/turf_arena_id = turf_air.arena_id()
	if(turf_arena_id < GAS_HANDLE_TURF_BASE)
		rust_unregister_device()
		return FALSE
	rust_ensure_device_id()
	SSair.rust_queue_device_operation(RUST_DEVICE_OP_SET_TURF, rust_device_id, rust_pipe_port_ids[port_index], turf_arena_id)

	SSair.rust_commit_pending_devices()
	return TRUE

/// Sets (creating the row on first use) `machine`'s device edge's one flow
/// law: `gases` a `1 << gas_id` bitset (0: every gas), `rate_kind`/
/// `direction`/`stop_cmp` the `RUST_FLOW_*`/`RUST_DIR_*`/`RUST_STOP_*`
/// wire values (`atmospherics.dm`), `stop_side` `RUST_SIDE_A`/`_B`. The row
/// is a bare Rust entity with no backing DM object at all (never an
/// `/obj/effect` placed on the map): `vg_bind_device_flow()` is the
/// bindings generator's free-function accessor for a component with no
/// `dm` type (`DeviceFlow`, `verdigris/domains/gas/src/kind/device.rs`),
/// taking the entity number directly instead of a per-type instance.
/// The row names its device by the device entity's slot index.
/// `limit_*`: a second target that only caps the flow (device.rs `Flow::limit`); `limit_cmp` RUST_STOP_NONE: none.
/obj/machinery/atmospherics/proc/rust_set_device_flow(gases, rate_kind, rate, direction, stop_side = RUST_SIDE_A, stop_cmp = RUST_STOP_NONE, stop_kpa = 0, limit_side = RUST_SIDE_A, limit_cmp = RUST_STOP_NONE, limit_kpa = 0)
	if(!rust_device_id)
		return FALSE
	var/device_index = vg_entity_index(rust_device_id)
	rust_flow_entity = vg_bind_device_flow(rust_flow_entity, device_index, gases, rate_kind, rate, direction, stop_side, stop_cmp, stop_kpa, limit_side, limit_cmp, limit_kpa, 0, 0, 0, 0, 1)
	return rust_flow_entity != 0

/// Sets (creating the row on first use) `machine`'s device edge's valve
/// gate (a valve or shutoff valve: equalizes while `open`, blocks
/// otherwise). Same bare-entity, generated-free-proc pattern as
/// `rust_set_device_flow()`.
/obj/machinery/atmospherics/proc/rust_set_device_valve(open)
	if(!rust_device_id)
		return FALSE
	var/device_index = vg_entity_index(rust_device_id)
	rust_valve_entity = vg_bind_device_valve(rust_valve_entity, device_index, open)
	return rust_valve_entity != 0

/// Binds many DeviceFlow rows in one FFI call (round-start registration; runtime edits stay
/// single via rust_set_device_flow()). `rows` is flat, nine values per row: row entity (0: a new
/// one), device entity index, gases, rate_kind (RUST_FLOW_*), rate, direction, stop_side,
/// stop_cmp, stop_kpa. Returns the row entity handles in row order.
/proc/rust_bind_device_flow_list(list/rows)
	return vg_component_bind_list(VG_KIND_DEVICEFLOW, list(VG_DEVICEFLOW_FIELD_DEVICE, VG_DEVICEFLOW_FIELD_GASES, VG_DEVICEFLOW_FIELD_RATE_KIND, VG_DEVICEFLOW_FIELD_RATE, VG_DEVICEFLOW_FIELD_DIRECTION, VG_DEVICEFLOW_FIELD_STOP_SIDE, VG_DEVICEFLOW_FIELD_STOP_CMP, VG_DEVICEFLOW_FIELD_STOP_KPA), rows)

/obj/machinery/atmospherics/proc/rust_unregister_device()
	if(rust_flow_entity)
		vg_entity_unbind(rust_flow_entity)
		rust_flow_entity = 0
	if(rust_valve_entity)
		vg_entity_unbind(rust_valve_entity)
		rust_valve_entity = 0
	if(!rust_device_id)
		return
	SSair.rust_queue_device_operation(RUST_DEVICE_OP_REMOVE, rust_device_id)
	rust_free_pipe_device(src, rust_device_id)
	rust_device_id = 0
	SSair.rust_commit_pending_devices()

// ---- N device edges per machine (filter, mixer: rust_architecture.md §8.5
// step 6's filter/mixer slice) -- the same shape as rust_device_id/
// rust_set_device()/rust_set_device_flow()/rust_unregister_device() above,
// keyed by an arbitrary per-machine slot string instead of being the one
// implicit edge, so one machine can register several (a filter's source-
// >filtered and source->clean edges; a mixer's two input->output edges).

/// Allocates `src`'s `slot` device id on first use.
/obj/machinery/atmospherics/proc/rust_ensure_device_id_n(slot)
	LAZYINITLIST(rust_device_ids)
	if(!rust_device_ids[slot])
		var/device_id = rust_new_pipe_device(src) // a numeric Rust device id, not an entity
		rust_device_ids[slot] = device_id
	return rust_device_ids[slot]

/// `rust_set_device()`'s N-edge counterpart: registers (or replaces)
/// `slot`'s device edge between ports `port_index_a`/`port_index_b`.
/obj/machinery/atmospherics/proc/rust_set_device_n(slot, port_index_a, port_index_b)
	if(!rust_pipe_port_ids || port_index_a > length(rust_pipe_port_ids) || port_index_b > length(rust_pipe_port_ids))
		return FALSE
	var/id = rust_ensure_device_id_n(slot)
	SSair.rust_queue_device_operation(RUST_DEVICE_OP_SET, id, rust_pipe_port_ids[port_index_a], rust_pipe_port_ids[port_index_b])
	SSair.rust_commit_pending_devices()
	return TRUE

/// `rust_set_device_flow()`'s N-edge counterpart: sets (creating on first
/// use) `slot`'s one flow law.
/obj/machinery/atmospherics/proc/rust_set_device_flow_n(slot, gases, rate_kind, rate, direction, stop_side = RUST_SIDE_A, stop_cmp = RUST_STOP_NONE, stop_kpa = 0, limit_side = RUST_SIDE_A, limit_cmp = RUST_STOP_NONE, limit_kpa = 0, group = 0, role = 0, ratio = 0, power_w = 0, efficiency = 1)
	LAZYINITLIST(rust_device_ids)
	var/id = rust_device_ids[slot]
	if(!id)
		return FALSE
	var/device_index = vg_entity_index(id)
	LAZYINITLIST(rust_flow_entities)
	rust_flow_entities[slot] = vg_bind_device_flow(rust_flow_entities[slot] || 0, device_index, gases, rate_kind, rate, direction, stop_side, stop_cmp, stop_kpa, limit_side, limit_cmp, limit_kpa, group, role, ratio, power_w, efficiency)
	return rust_flow_entities[slot] != 0

/// One leg of a filter's or mixer's budget group: the device edge between two ports and a RUST_FLOW_FILTER / RUST_FLOW_MIX
/// flow on it. The group's legs are stepped together in Rust (requested moles from the hub's live gas, the entropy/power
/// budget, the split across the legs): `rate` is the requested volume flow (L/s), `power_w` the available power and
/// `efficiency` the pumping efficiency; a filter leg takes the gases in `gases` (role RUST_ROLE_OUTPUT) or the rest
/// (RUST_ROLE_CLEAN), a mixer leg is an input with share `ratio`. A filter's hub is port a, a mixer's port b.
/obj/machinery/atmospherics/proc/rust_set_budget_leg(slot, port_index_a, port_index_b, rate_kind, gases, role, ratio, rate, power_w, efficiency)
	if(!rust_set_device_n(slot, port_index_a, port_index_b))
		return FALSE
	if(!rust_budget_group)
		var/static/serial = 0
		rust_budget_group = ++serial
	return rust_set_device_flow_n(slot, gases, rate_kind, rate, RUST_DIR_FORCED, RUST_SIDE_A, RUST_STOP_NONE, 0, RUST_SIDE_A, RUST_STOP_NONE, 0, rust_budget_group, role, ratio, power_w, efficiency)

/// `rust_unregister_device()`'s N-edge counterpart: removes just `slot`.
/obj/machinery/atmospherics/proc/rust_unregister_device_n(slot)
	if(rust_flow_entities?[slot])
		vg_entity_unbind(rust_flow_entities[slot])
		rust_flow_entities -= slot
	var/id = rust_device_ids?[slot]
	if(!id)
		return
	rust_device_ids -= slot
	SSair.rust_queue_device_operation(RUST_DEVICE_OP_REMOVE, id)
	rust_free_pipe_device(src, id)

/// Removes every slot this machine registered (`rust_unregister_pipe_topology()`).
/obj/machinery/atmospherics/proc/rust_unregister_all_devices_n()
	if(!length(rust_device_ids))
		return
	for(var/slot in rust_device_ids.Copy())
		rust_unregister_device_n(slot)

/// Called once per gas tick with this tick's flow-law result (M2). The base
/// implementation does nothing; devices with a UI/events override it.
/obj/machinery/atmospherics/proc/rust_device_stepped(moles, power_w, target_reached)
	return

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
/// Test hook: steps every pipe device now, as a frame does once a period, and delivers their reports.
/datum/system/air/proc/rust_step_pipe_devices()
	if(!rust_pipe_device_count)
		return
	vg_frame_force_devices()
	native_system().drain()
#endif

/// Publish the complete map topology once, then materialize all compatibility
/// `/datum/pipe_network` wrappers from Rust's atomic connected-region result.
/datum/system/air/proc/setup_rust_pipenets()
	rust_pipe_region_networks = alist()
	rust_queue_pipe_operation(RUST_PIPE_OP_CLEAR, 0, 0)
	// The whole map's ports and edges go to Rust in one call each
	// (init_and_turfs.md §3.3 step 4), not one call per port and edge.
	var/list/upserts = list()
	var/list/edges = list()

	for(var/obj/machinery/atmospherics/machine in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		machine.rust_allocate_pipe_ports()
		for(var/index = 1 to machine.rust_pipe_port_count())
			var/datum/gas_mixture/port_air = machine.rust_pipe_port_air(index)
			if(!port_air)
				continue
			upserts += machine.rust_pipe_port_ids[index]
			upserts += port_air.arena_id()
			upserts += machine.rust_pipe_port_volume(index)

	if(length(upserts))
		vg_pipe_upsert_list(upserts)

	for(var/obj/machinery/atmospherics/machine in REGISTRY_MEMBERS(REGISTRY_MACHINES))
		for(var/index = 1 to machine.rust_pipe_port_count())
			var/first = machine.rust_pipe_port_ids[index]
			for(var/obj/machinery/atmospherics/neighbor as anything in machine.rust_pipe_port_neighbors(index))
				if(!neighbor)
					continue
				var/neighbor_index = neighbor.rust_pipe_port_index_for_neighbor(machine)
				if(!neighbor_index || neighbor_index > length(neighbor.rust_pipe_port_ids))
					continue
				var/second = neighbor.rust_pipe_port_ids[neighbor_index]
				// Each physical edge once: from its lower port handle.
				if(first < second)
					edges += first
					edges += second
		var/list/internal_edges = machine.rust_pipe_internal_edges()
		for(var/edge_index = 1, edge_index < length(internal_edges), edge_index += 2)
			var/first_index = internal_edges[edge_index]
			var/second_index = internal_edges[edge_index + 1]
			edges += machine.rust_pipe_port_ids[first_index]
			edges += machine.rust_pipe_port_ids[second_index]

	if(length(edges))
		vg_pipe_connect_list(edges)
	rust_pipe_topology_dirty = TRUE
	rust_commit_pending_pipenets()

/// Commits this batch of topology edits to the Rust pipe network (R7) and
/// rebuilds the compatibility wrappers of every region whose membership
/// changed. Gas never passes through DM: the network pools, splits and
/// releases it, and each region's air datum is bound to the region's gas handle.
/datum/system/air/proc/rust_apply_pipe_commit()
	var/list/result = vg_pipe_commit()
	if(!islist(result))
		CRASH("Rust pipenet topology did not return a region list")
	var/list/transitions = list()
	var/alist/retired_regions = alist()
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
			retired_regions[prior_region] = TRUE
		if(volume < 0)
			retired_regions[region] = TRUE
			continue
		transitions += list(list("region" = region, "ports" = ports, "volume" = volume))

	for(var/prior_region in retired_regions)
		var/datum/pipe_network/old_network = rust_pipe_region_networks[prior_region]
		rust_pipe_region_networks -= prior_region
		rust_retire_pipe_network(old_network)
	for(var/list/transition as anything in transitions)
		var/datum/gas_mixture/region_air = new(max(transition["volume"], 1))
		vg_bind_handle(region_air, transition["region"])
		transition["air"] = region_air
		rust_materialize_pipe_region(transition)

/datum/system/air/proc/rust_retire_pipe_network(datum/pipe_network/network)
	if(!network)
		return
	STOP_PROCESSING_PIPENET(network)
	var/list/datum/pipeline/old_lines = network.line_members?.Copy()
	var/list/obj/machinery/atmospherics/old_members = network.normal_members?.Copy()
	network.rust_authoritative = FALSE
	// Empty the rosters first: a retired Rust wrapper must not run the legacy gas split
	// (pipe_network/lifecycle_unbind()) across members that Rust is rebinding.
	rel_clear(network, nameof(network.line_members))
	rel_clear(network, nameof(network.normal_members))
	rel_clear(network, nameof(network.leaks))
	// The region's gas lives in the Rust network; the datum is only a handle.
	for(var/obj/machinery/atmospherics/member as anything in old_members)
		material_service_of(member)?.environment_changed()
	for(var/datum/pipeline/line as anything in old_lines)
		for(var/obj/machinery/atmospherics/pipe/pipe as anything in line.members)
			material_service_of(pipe)?.environment_changed()
		// Likewise the line: no network to destroy, no gas to store back into its pipes.
		rel_clear(line, nameof(line.network))
		atmos_air_set(line, nameof(line.air), null)
		rel_clear(line, nameof(line.leaks))
		spent(line)
	// The network owns the retired region mixture: destroyed with it.
	spent(network)

/datum/system/air/proc/rust_materialize_pipe_region(list/transition)
	var/region = transition["region"]
	var/list/ports = transition["ports"]
	var/datum/gas_mixture/region_air = transition["air"]
	var/datum/pipe_network/network = new
	network.rust_authoritative = TRUE
	rel_set(network, nameof(network.air), region_air)
	network.update = FALSE
	rust_pipe_region_networks[region] = network

	var/list/obj/machinery/atmospherics/pipe/region_pipes = list()
	for(var/port_handle in ports)
		var/datum/pipe_port/port = rust_pipe_port_of(port_handle)
		var/obj/machinery/atmospherics/machine = port?.machine
		var/index = port?.index
		if(!machine)
			continue
		if(istype(machine, /obj/machinery/atmospherics/pipe))
			region_pipes |= machine
		else
			network.add_normal_member(machine)
		machine.rust_bind_pipe_port(index, network, region_air)
		// A region replacement can preserve pressure/composition, so gas-dirty
		// publication alone cannot tell sleepers to subscribe to the new handle.
		material_service_of(machine)?.environment_changed()

	if(length(region_pipes))
		var/datum/pipeline/pipeline = new
		atmos_air_set(pipeline, "air", region_air)
		rel_clear(pipeline, nameof(pipeline.leaks))
		rel_set(pipeline, nameof(pipeline.network), network)
		for(var/obj/machinery/atmospherics/pipe/pipe as anything in region_pipes)
			rel_set(pipe, nameof(pipe.parent), pipeline) // two-sided: adds the pipe to pipeline.members
			if(pipe.leaking)
				rel_add(pipeline, nameof(pipeline.leaks), pipe)
				rel_add(network, nameof(network.leaks), pipe)
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
		rel_set(src, nameof(air_temporary), new /datum/gas_mixture(max(volume, 1)))
	return air_temporary

/obj/machinery/atmospherics/pipe/rust_pipe_port_volume(index)
	return volume

/obj/machinery/atmospherics/pipe/rust_pipe_port_network(index)
	return parent?.network

/obj/machinery/atmospherics/pipe/rust_bind_pipe_port(index, datum/pipe_network/network, datum/gas_mixture/network_air)
	if(air_temporary == network_air)
		rel_take(src, nameof(air_temporary))
	else
		rel_clear(src, nameof(air_temporary))
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
	atmos_air_set(src, nameof(air_contents), network_air)
	rel_set(src, nameof(network), new_network)
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
		atmos_air_set(src, nameof(air1), network_air)
		rel_set(src, nameof(network1), new_network)
	else
		atmos_air_set(src, nameof(air2), network_air)
		rel_set(src, nameof(network2), new_network)
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
		atmos_air_set(src, nameof(air1), network_air)
		rel_set(src, nameof(network1), new_network)
	else if(index == 2)
		atmos_air_set(src, nameof(air2), network_air)
		rel_set(src, nameof(network2), new_network)
	else
		atmos_air_set(src, nameof(air3), network_air)
		rel_set(src, nameof(network3), new_network)
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
	rel_set(src, nameof(network), new_network)
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
		rel_set(src, nameof(network_node1), new_network)
	else
		rel_set(src, nameof(network_node2), new_network)
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
		rel_set(src, nameof(network_node1), new_network)
	else if(index == 2)
		rel_set(src, nameof(network_node2), new_network)
	else
		rel_set(src, nameof(network_node3), new_network)
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
	atmos_air_set(port, nameof(port.air), network_air)
	rel_set(port, nameof(port.network), new_network)
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
		atmos_air_set(src, nameof(air_in), network_air)
		rel_set(src, nameof(network1), new_network)
	else
		atmos_air_set(src, nameof(air_out), network_air)
		rel_set(src, nameof(network2), new_network)
	return TRUE


