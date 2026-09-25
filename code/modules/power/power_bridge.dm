// M3: the DM side of the Rust power domain (verdigris/domains/power; binds
// in verdigris/ffi/src/power.rs, docs in doc/rewrite/simulation.md §6).
//
// Rust owns the cable graph, the per-region ledger, the APC distributor and
// SMES charge. DM:
//   - names every cable piece, power machine and APC by a dense power key;
//   - queues edits and commands in SSmachines.power_ops and sends them in one
//     vg_power_edit() call (a whole explosion's edits are one commit);
//   - draws synchronously with vg_power_draw();
//   - makes one vg_power_step() call per machinery tick and applies the
//     events: machine rebinds, region numbers, APC and SMES state, brownouts.
// There is no DM topology code: no flood fills, merges or rebuilds.

/// Key -> the cable, power machine or APC that owns it.
GLOBAL_LIST_EMPTY(power_key_objects)
GLOBAL_LIST_EMPTY(power_free_keys)
GLOBAL_VAR_INIT(power_next_key, 1)

/proc/power_key_alloc(datum/owner)
	var/key
	var/free = length(GLOB.power_free_keys)
	if(free)
		key = GLOB.power_free_keys[free]
		GLOB.power_free_keys.len--
	else
		key = GLOB.power_next_key++
	if(length(GLOB.power_key_objects) < key)
		GLOB.power_key_objects.len = key
	GLOB.power_key_objects[key] = owner
	return key

/proc/power_key_free(key)
	if(!key || key > length(GLOB.power_key_objects))
		return
	GLOB.power_key_objects[key] = null
	GLOB.power_free_keys += key

/proc/power_key_owner(key)
	if(key < 1 || key > length(GLOB.power_key_objects))
		return null
	return GLOB.power_key_objects[key]

/datum/controller/subsystem/machines
	/// Queued power edits and commands: `op, n, n values` each (POWER_OP_*).
	var/list/power_ops = list()
	/// Region id (Rust's raw handle bits + 1) -> its /datum/powernet. An alist:
	/// the ids are numbers, and a plain list would treat them as positions.
	var/alist/power_regions = alist()
	/// While above zero, queued power edits are held (an explosion epoch).
	var/power_batch_depth = 0
	/// Areas whose static or one-off loads changed since the last step.
	var/list/power_dirty_areas = list()
	/// Cables with an engineered conductor; their regions run the material overlay.
	var/list/power_material_cables = list()
	/// Diagnostics: events in the last step, and edits sent.
	var/power_last_events = 0
	var/power_edits_sent = 0

/datum/controller/subsystem/machines/proc/power_queue(list/op)
	power_ops += op

/// Sends queued edits. Held during a batch unless forced.
/datum/controller/subsystem/machines/proc/power_flush(force = FALSE)
	if(!length(power_ops) || (power_batch_depth && !force))
		return
	var/list/ops = power_ops
	power_ops = list()
	power_edits_sent += length(ops)
	vg_power_edit(ops)

/// Opens a power topology batch: edits wait until the matching end.
/datum/controller/subsystem/machines/proc/power_batch_begin()
	power_batch_depth++

/datum/controller/subsystem/machines/proc/power_batch_end()
	if(power_batch_depth <= 0)
		return
	power_batch_depth--
	if(!power_batch_depth)
		power_flush()

/// The /datum/powernet for region `id`, made on first use.
/datum/controller/subsystem/machines/proc/power_facade(id, key)
	if(!id)
		return null
	var/datum/powernet/network = power_regions[id]
	if(network)
		if(key)
			network.anchor_key = key
		return network
	network = new(id, key)
	power_regions[id] = network
	if(key)
		var/list/info = vg_power_region(key)
		if(info && info[1] == id)
			network.read_info(info)
	return network

/// The region the power key is on, or null. Flushes queued edits first.
/datum/controller/subsystem/machines/proc/power_region_of(key, connected_only = TRUE)
	if(!key)
		return null
	power_flush(TRUE)
	var/list/info = vg_power_region(key)
	if(!info || (connected_only && info[10] <= 1))
		return null
	var/datum/powernet/network = power_facade(info[1], key)
	network.read_info(info)
	return network

/// Queues an area's loads for its APC.
/area/proc/power_loads_changed()
	SSmachines.power_dirty_areas[src] = TRUE

/datum/controller/subsystem/machines/proc/power_flush_areas()
	for(var/area/A as anything in power_dirty_areas)
		var/key = A.apc?.power_key
		if(key)
			power_queue(list(POWER_OP_AREA_LOAD, 4, key, A.static_equip, A.static_light, A.static_environ))
			if(A.oneoff_equip || A.oneoff_light || A.oneoff_environ)
				power_queue(list(POWER_OP_ONEOFF, 4, key, A.oneoff_equip, A.oneoff_light, A.oneoff_environ))
		A.oneoff_equip = 0
		A.oneoff_light = 0
		A.oneoff_environ = 0
	power_dirty_areas.Cut()

/// One power step: send loads and edits, step Rust, apply the events.
/datum/controller/subsystem/machines/proc/process_power()
	power_flush_areas()
	power_flush()
	for(var/obj/structure/cable/cable as anything in power_material_cables)
		if(QDELETED(cable))
			power_material_cables -= cable
			continue
		cable.get_powernet()?.material_candidate = TRUE
	var/list/events = vg_power_step()
	var/count = 0
	var/i = 1
	var/len = length(events)
	while(i < len)
		var/kind = events[i]
		var/n = events[i + 1]
		var/at = i + 2
		i = at + n
		count++
		switch(kind)
			if(POWER_EV_BIND)
				var/obj/machinery/power/machine = power_key_owner(events[at])
				if(istype(machine))
					machine.power_bind(events[at + 1], events[at + 2])
			if(POWER_EV_REGION)
				var/datum/powernet/network = power_regions[events[at]]
				network?.read_step(events, at)
			if(POWER_EV_RETIRED)
				var/datum/powernet/network = power_regions[events[at]]
				if(network)
					power_regions -= events[at]
					network.retire()
			if(POWER_EV_APC)
				var/obj/machinery/power/apc/apc = power_key_owner(events[at])
				if(istype(apc))
					apc.power_event(events, at)
			if(POWER_EV_SMES)
				var/obj/machinery/power/smes/storage = power_key_owner(events[at])
				if(istype(storage))
					storage.power_event(events, at)
			if(POWER_EV_BROWNOUT)
				var/datum/powernet/network = power_regions[events[at]]
				network?.set_brownout(events[at + 1])
	power_last_events = count
	for(var/id in power_regions)
		var/datum/powernet/network = power_regions[id]
		if(network.material_candidate || network.material_graph)
			network.process_material_network()

/// Clears the Rust power world and sends every cable, power machine, APC and
/// SMES again (admin repair).
/datum/controller/subsystem/machines/proc/power_reregister_all()
	power_ops = list()
	vg_power_reset()
	for(var/id in power_regions)
		var/datum/powernet/network = power_regions[id]
		network.region_id = 0
		qdel(network)
	power_regions = alist()
	for(var/obj/structure/cable/cable as anything in REGISTRY_MEMBERS(REGISTRY_CABLES))
		cable.power_register()
	for(var/obj/machinery/power/machine in world)
		if(istype(machine, /obj/machinery/power/apc))
			continue
		if(machine.power_key && isturf(machine.loc))
			machine.power_send_node()
	for(var/obj/machinery/power/apc/apc in world)
		apc.power_sync()
	for(var/area/A in world)
		A.power_loads_changed()
	process_power()

/// Registers every cable and power machine again (admin repair, and after
/// bulk moves that bypass Moved()).
/datum/controller/subsystem/machines/proc/power_reregister(list/turfs)
	for(var/turf/T as anything in turfs)
		for(var/obj/structure/cable/cable in T)
			cable.power_register()
		for(var/obj/machinery/power/machine in T)
			if(machine.power_key && !istype(machine, /obj/machinery/power/apc))
				machine.power_send_node()
