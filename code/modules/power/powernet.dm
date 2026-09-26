// A power network as DM sees it: one Rust cable region (rust_architecture.md
// step 3). The region's topology and ledger live in Rust
// (verdigris/domains/power); this datum carries the numbers monitors,
// shocks and machines read, refreshed by polling `vg_power_region_read`
// once a power step (there is no event stream any more -- `PowerHost` and
// its `POWER_EV_REGION` records are gone), and the machines bound to it.
//
// Region ids are stable across edits that keep the region (a merge keeps the
// larger region's id; a split keeps the parent id for one side), so this
// datum survives those. An empty region's datum is dropped by
// `process_power()`.

/datum/powernet
	/// Rust region id (0 for a detached test network).
	var/region_id = 0
	/// Power machines bound to this network.
	var/list/nodes = list()

	var/avail = 0       // supply this step (W)
	var/load = 0        // delivered this step (W)
	// Rust reports raw avail/load only (rust_core.md §15: no presentation
	// state in the step); viewavail/viewload are this datum's own display
	// smoothing for power monitors, eased 80/20 per read.
	var/viewavail = 0
	var/viewload = 0
	var/netexcess = 0   // avail - load at the last step
	/// Lost supply or overdrawn (Rust brownout event/poll).
	var/brownout = FALSE

	var/problem = 0     // non-zero: power monitors show a warning
	var/problem_timer
	var/material_problem = FALSE

	// Material overlay (engineered conductors only; see material_power_graph.dm).
	// Cables of an ordinary region never enter this path.
	var/material_candidate = FALSE
	/// Member cables, rebuilt with the material graph.
	var/list/cables = list()
	var/material_cache_dirty = TRUE
	var/material_flow_dirty = TRUE
	var/datum/material_power_graph/material_graph
	var/list/material_consumers
	var/material_loss_watts = 0
	var/material_pending_heat = 0
	var/material_pending_heat_elapsed = 0
	var/last_material_process = 0

/datum/powernet/New(id)
	region_id = id
	..()

/datum/powernet/Destroy()
	if(problem_timer)
		deltimer(problem_timer)
		problem_timer = null
	if(region_id && SSmachines.power_regions[region_id] == src)
		SSmachines.power_regions -= region_id
	for(var/obj/machinery/power/M as anything in nodes)
		if(M.powernet == src)
			M.powernet = null
	nodes = null
	release_material_cables()
	QDEL_NULL(material_graph)
	material_consumers = null
	return ..()

/// Polls this region's current numbers from Rust (`process_power()`, once
/// a power step; also called on facade creation).
/datum/powernet/proc/refresh()
	if(!region_id)
		return
	var/list/info = vg_power_region_read(region_id)
	if(!info)
		return
	avail = info[1]
	load = info[2]
	netexcess = avail - load
	smooth_view()
	var/was_brown = brownout
	brownout = !!info[3]
	if(was_brown != brownout)
		REACT_PUBLISH_OWN(src, REACT_KEY_POWERNET, REACT_POWERNET_STATE)
	REACT_PUBLISH_OWN(src, REACT_KEY_POWERNET, REACT_POWERNET_RATE)

/// Eases `viewavail`/`viewload` toward the raw numbers (80/20 per read):
/// this datum's own display smoothing, not Rust's -- the step reports raw
/// numbers only (`rust_core.md` §15).
/datum/powernet/proc/smooth_view()
	viewavail = round(0.8 * viewavail + 0.2 * avail)
	viewload = round(0.8 * viewload + 0.2 * load)

/datum/powernet/proc/bind_machine(obj/machinery/power/M)
	nodes[M] = M
	material_cache_dirty = TRUE
	REACT_PUBLISH_OWN(src, REACT_KEY_POWERNET, REACT_POWERNET_TOPOLOGY)

/datum/powernet/proc/unbind_machine(obj/machinery/power/M)
	if(QDELETED(src))
		return
	nodes -= M
	material_cache_dirty = TRUE
	REACT_PUBLISH_OWN(src, REACT_KEY_POWERNET, REACT_POWERNET_TOPOLOGY)

/// last_surplus() — spare power at the last step.
/datum/powernet/proc/last_surplus()
	return max(avail - load, 0)

/// Draws from this network for `consumer` (or the network itself). Returns
/// what was delivered; never more than the spare supply this step.
/datum/powernet/proc/draw_power(amount, atom/consumer)
	if(amount <= 0)
		return 0
	var/efficiency = consumer ? (material_graph?.efficiencies?[REF(consumer)] || 1) : 1
	var/drawn
	if(!region_id)
		// A detached network (tests): its own numbers are the ledger.
		drawn = between(0, amount / efficiency, avail - load)
	else
		drawn = vg_power_region_draw(region_id, amount / efficiency)
	load += drawn
	var/delivered = drawn * efficiency
	if(consumer && material_graph)
		LAZYINITLIST(material_consumers)
		material_consumers[WEAKREF(consumer)] += delivered
	return delivered

/datum/powernet/proc/is_empty()
	return !region_id && !length(cables) && !length(nodes)

/// trigger_warning() — flag a problem visible on power monitors.
/datum/powernet/proc/trigger_warning(duration_ticks = 20)
	var/was_clear = problem <= 0
	problem = TRUE
	if(problem_timer)
		deltimer(problem_timer)
	problem_timer = addtimer(CALLBACK(src, PROC_REF(clear_warning)), max(duration_ticks, 1), TIMER_STOPPABLE)
	if(was_clear)
		REACT_PUBLISH_OWN(src, REACT_KEY_POWERNET, REACT_POWERNET_STATE)

/datum/powernet/proc/clear_warning()
	problem_timer = null
	var/was_problem = problem
	problem = material_problem
	if(was_problem != problem)
		REACT_PUBLISH_OWN(src, REACT_KEY_POWERNET, REACT_POWERNET_STATE)

/datum/powernet/proc/set_material_warning(active)
	active = !!active
	if(material_problem == active)
		return
	material_problem = active
	var/was_problem = problem
	problem = material_problem || !!problem_timer
	if(was_problem != problem)
		REACT_PUBLISH_OWN(src, REACT_KEY_POWERNET, REACT_POWERNET_STATE)

/datum/powernet/proc/get_percent_load(smes_only = 0)
	if(smes_only)
		var/smes_avail = 0
		for(var/obj/machinery/power/smes/storage in nodes)
			smes_avail += storage.output_used
		if(!smes_avail || !load)
			return 0
		return between(0, (min(load, smes_avail) / smes_avail) * 100, 100)
	if(!load || !avail)
		return 0
	return between(0, (load / avail) * 100, 100)

/datum/powernet/proc/get_electrocute_damage()
	// Logarithmic damage scaling:
	// 1kW=5, 10kW=24, 100kW=45, 250kW=53, 1MW=66, 10MW=88, 100MW=110, 1GW=132
	if(avail >= 1000)
		var/damage = log(1.1, avail)
		damage = damage - (log(1.1, damage) * 1.5)
		return round(damage)
	return 0

// ---- Material overlay -------------------------------------------------------
// The CG voltage solver (material_power.rs) runs only for regions holding an
// engineered conductor. The graph builder compares cable.powernet, so member
// cables carry this datum while the overlay owns them.

/// A detached network (tests) holds machines and cables directly.
/datum/powernet/proc/add_machine(obj/machinery/power/M)
	M.powernet = src
	nodes[M] = M

/datum/powernet/proc/add_cable(obj/structure/cable/C)
	cables |= C
	C.powernet = src
	invalidate_material_cache()

/datum/powernet/proc/remove_cable(obj/structure/cable/C)
	cables -= C
	if(C.powernet == src)
		C.powernet = null
	invalidate_material_cache()

/datum/powernet/proc/invalidate_material_cache()
	material_cache_dirty = TRUE
	material_flow_dirty = TRUE

/datum/powernet/proc/release_material_cables()
	for(var/obj/structure/cable/C as anything in cables)
		if(C?.powernet == src)
			C.powernet = null
	cables = list()

/datum/powernet/proc/rebuild_material_cache()
	material_cache_dirty = FALSE
	if(region_id)
		release_material_cables()
		for(var/entity in vg_power_region_members(region_id))
			var/obj/structure/cable/C = GLOB.power_cable_by_entity["[entity]"]
			if(istype(C))
				cables += C
				C.powernet = src
	QDEL_NULL(material_graph)
	material_graph = new
	material_graph.build(cables)

/// Supply by source for the solver: each bound machine's registered rate.
/datum/powernet/proc/material_sources()
	var/list/sources = list()
	for(var/obj/machinery/power/M as anything in nodes)
		if(M.power_supply_rate > 0)
			sources[WEAKREF(M)] = M.power_supply_rate
	return sources

/// One overlay step: settle heat for the last interval, solve if the flow
/// changed, and pay the resistive loss from the grid.
/datum/powernet/proc/process_material_network()
	var/elapsed_seconds = last_material_process ? max((world.time - last_material_process) / 10, 0.1) : 1
	last_material_process = world.time
	if(material_cache_dirty)
		rebuild_material_cache()
	if(!material_graph?.has_custom_conductors && !material_graph?.has_superconductors)
		material_candidate = FALSE
		release_material_cables()
		QDEL_NULL(material_graph)
		material_consumers = null
		material_loss_watts = 0
		material_pending_heat = 0
		material_pending_heat_elapsed = 0
		set_material_warning(FALSE)
		return
	LAZYINITLIST(material_consumers)
	for(var/obj/machinery/power/terminal/T in nodes)
		var/obj/machinery/power/apc/A = T.master
		if(istype(A))
			material_consumers[WEAKREF(T)] += A.lastused_total
	material_pending_heat += material_loss_watts * elapsed_seconds
	material_pending_heat_elapsed += elapsed_seconds
	if(material_cache_dirty || material_graph.has_superconductors || material_pending_heat_elapsed >= MATERIAL_POWER_HEAT_SETTLEMENT_INTERVAL)
		material_graph.deposit_losses(material_pending_heat, material_pending_heat_elapsed)
		material_pending_heat = 0
		material_pending_heat_elapsed = 0
	material_graph.resolve_loads(material_sources(), material_consumers)
	material_flow_dirty = FALSE
	material_loss_watts = material_graph.loss_watts
	material_consumers = null
	if(material_loss_watts > 0 && region_id)
		load += vg_power_region_draw(region_id, material_loss_watts)
	set_material_warning(material_loss_watts > max(load * 0.1, 1000))

////////////////////////////////////////////////
// Misc.
///////////////////////////////////////////////

// return a knot cable (O-X) if one is present in the turf, null otherwise.
/turf/proc/get_cable_node()
	for(var/obj/structure/cable/C in src)
		if(C.d1 == 0)
			return C
	return null

/area/proc/get_apc()
	return apc
