/datum/powernet
	var/list/cables = list()   // all cables & junctions
	var/list/nodes  = list()   // all connected machines
	var/apc_count = 0
	var/list/smes_nodes = list()

	var/load     = 0           // current load; increased by each machine during processing
	var/newavail = 0           // power gathered this tick; becomes avail at tick end
	var/avail    = 0           // available power for this tick
	var/viewavail = 0          // availability as shown on power consoles (smoothed)
	var/viewload  = 0          // load as shown on power consoles (smoothed)
	var/number    = 0          // Unused — TODEL

	var/smes_demand    = 0     // total power demanded by SMESs from this network (for load balancing)
	var/list/inputting = list()// terminals whose SMES masters are demanding input this tick
	var/smes_avail     = 0     // power (avail) contributed by SMESes
	var/smes_newavail  = 0     // as above, for newavail

	var/perapc       = 0       // per-APC availability ration
	var/perapc_excess = 0      // accumulated excess fed back to perapc
	var/netexcess    = 0       // excess power on the net (avail - load), updated each tick

	var/problem = 0            // non-zero = some issue; power monitors will display warnings
	/// Stable demand retained for APCs that are dependency-sleeping.
	var/list/sleeping_apc_loads = list()
	/// Last semantic supply class observed by each sleeping APC. Accounting
	/// jitter which remains inside a class never wakes the APC.
	var/list/sleeping_apc_power_classes = list()
	/// One-tick machine usage folded into sleeping APC reservations.
	var/list/sleeping_apc_dynamic_loads = list()
	var/sleeping_apc_load_total = 0
	var/revision = 1
	/// Composite cable topology is scanned only when the network changes.
	var/material_cache_dirty = TRUE
	var/datum/material_power_graph/material_graph
	var/list/material_sources
	var/list/material_next_sources
	var/list/material_consumers
	var/material_paid_losses = 0
	var/material_loss_watts = 0
	/// Cable heat is conserved here and settled in batches. Per-cable thermal
	/// state does not need thousands of DM calls every accounting window.
	var/material_pending_heat = 0
	var/material_pending_heat_elapsed = 0
	/// Elapsed wall-clock integration of paid losses; the graph reuses its
	/// previous solution when injections and material resistance are unchanged.
	var/last_material_process = 0
	/// Consecutive accounting windows with no production, demand, warning, or
	/// engineered-material work. Two windows are required so producer shutdown is
	/// observed before the network sleeps.
	var/idle_accounting_windows = 0

/datum/powernet/New()
	SSmachines.powernets |= src
	START_PROCESSING_POWERNET(src)
	..()

/datum/powernet/Destroy()
	for(var/obj/machinery/power/apc/A as anything in sleeping_apc_loads)
		A?.wake_for_power_dependency()
	sleeping_apc_loads.Cut()
	sleeping_apc_power_classes.Cut()
	sleeping_apc_dynamic_loads.Cut()
	for(var/obj/structure/cable/C in cables)
		cables -= C
		C.powernet = null
	for(var/obj/machinery/power/M in nodes)
		nodes -= M
		M.powernet = null
	STOP_PROCESSING_POWERNET(src)
	SSmachines.powernets -= src
	QDEL_NULL(material_graph)
	material_sources = null
	material_next_sources = null
	material_consumers = null
	return ..()

/datum/powernet/proc/reserve_sleeping_apc_load(obj/machinery/power/apc/A, amount)
	if(!A)
		return
	unreserve_sleeping_apc_load(A)
	amount = max(amount, 0)
	sleeping_apc_loads[A] = amount
	sleeping_apc_load_total += amount
	sleeping_apc_power_classes[A] = apc_supply_class(amount)
	mark_accounting_dirty()

/datum/powernet/proc/unreserve_sleeping_apc_load(obj/machinery/power/apc/A)
	if(!A || !(A in sleeping_apc_loads))
		return
	var/reserved = sleeping_apc_loads[A]
	sleeping_apc_load_total -= reserved
	load = max(load - reserved, 0)
	sleeping_apc_loads.Remove(A)
	sleeping_apc_power_classes.Remove(A)
	sleeping_apc_dynamic_loads.Remove(A)
	mark_accounting_dirty()

/// Adjust demand in place without waking an APC for routine area accounting.
/datum/powernet/proc/adjust_sleeping_apc_load(obj/machinery/power/apc/A, delta)
	if(!A || !delta || !(A in sleeping_apc_loads))
		return FALSE
	var/old_amount = sleeping_apc_loads[A]
	var/new_amount = max(old_amount + delta, 0)
	sleeping_apc_loads[A] = new_amount
	sleeping_apc_dynamic_loads[A] = (sleeping_apc_dynamic_loads[A] || 0) + delta
	sleeping_apc_load_total += new_amount - old_amount
	load = max(load + new_amount - old_amount, 0)
	mark_accounting_dirty()
	return TRUE

/datum/powernet/proc/mark_accounting_dirty()
	idle_accounting_windows = 0
	START_PROCESSING_POWERNET(src)

/datum/powernet/proc/publish_dependency()
	revision++
	mark_accounting_dirty()
	SSmachines.publish_reactive_dependency("powernet:[REF(src)]")
	// Topology membership really can invalidate every APC on this network. This
	// path is intentionally separate from routine accounting publication below.
	for(var/obj/machinery/power/apc/A as anything in sleeping_apc_loads)
		SSmachines.publish_reactive_dependency("apc-power:[REF(A)]")

/// Publish monitor-visible state without fanning one accounting sample out to
/// every APC. APCs receive their own semantic supply transition below.
/datum/powernet/proc/publish_monitor_dependency()
	revision++
	mark_accounting_dirty()
	SSmachines.publish_reactive_dependency("powernet:[REF(src)]")

/datum/powernet/proc/apc_supply_class(demand)
	if(avail <= 0)
		return 0
	if(netexcess < -1 || perapc + 1 < demand)
		return 1
	return 2

/datum/powernet/proc/publish_apc_supply_changes()
	for(var/obj/machinery/power/apc/A as anything in sleeping_apc_loads)
		if(!A || QDELETED(A))
			continue
		var/new_class = apc_supply_class(sleeping_apc_loads[A])
		if(sleeping_apc_power_classes[A] == new_class)
			continue
		sleeping_apc_power_classes[A] = new_class
		SSmachines.publish_reactive_dependency("apc-power:[REF(A)]")

/// last_surplus() — excess power before refunds to SMESes, from last tick.
/// Machines may read this to adjust consumption.
/datum/powernet/proc/last_surplus()
	return max(avail - load, 0)

/datum/powernet/proc/draw_power(amount, atom/consumer)
	mark_accounting_dirty()
	var/efficiency = consumer ? (material_graph?.efficiencies?[REF(consumer)] || 1) : 1
	var/draw = between(0, amount / efficiency, avail - load)
	load += draw
	var/delivered = draw * efficiency
	material_paid_losses += draw - delivered
	if(consumer)
		LAZYINITLIST(material_consumers)
		material_consumers[WEAKREF(consumer)] += delivered
	return delivered

/datum/powernet/proc/is_empty()
	return !cables.len && !nodes.len

/// remove_cable() — remove a cable and delete the powernet if now empty.
/// Caller must verify the cable is in this net before calling.
/datum/powernet/proc/remove_cable(obj/structure/cable/C)
	cables -= C
	C.powernet = null
	invalidate_material_cache()
	publish_dependency()
	if(is_empty())
		qdel(src)

/// add_cable() — add a cable, migrating it from its current net if needed.
/// Idempotent: safe to call when the cable is already on this net.
/datum/powernet/proc/add_cable(obj/structure/cable/C)
	if(C.powernet)
		if(C.powernet == src)
			return
		C.powernet.remove_cable(C)
	C.powernet = src
	cables += C
	invalidate_material_cache()
	publish_dependency()

/datum/powernet/proc/invalidate_material_cache()
	material_cache_dirty = TRUE

/datum/powernet/proc/rebuild_material_cache()
	material_cache_dirty = FALSE
	QDEL_NULL(material_graph)
	material_graph = new
	material_graph.build(cables)

/datum/powernet/proc/process_material_network()
	var/elapsed_seconds = last_material_process ? max((world.time - last_material_process) / 10, 0.1) : 1
	last_material_process = world.time
	LAZYINITLIST(material_consumers)
	for(var/obj/machinery/power/apc/apc as anything in sleeping_apc_loads)
		if(apc.terminal)
			material_consumers[WEAKREF(apc.terminal)] += sleeping_apc_loads[apc]
			var/efficiency = material_graph?.efficiencies?[REF(apc.terminal)] || 1
			var/extra = sleeping_apc_loads[apc] * (1 / efficiency - 1)
			var/paid = min(extra, max(avail - load, 0))
			load += paid
			material_paid_losses += paid
			if(paid + 0.01 < extra)
				apc.wake_for_power_dependency()
	material_loss_watts = material_paid_losses
	// Settle the completed interval against its original flow distribution before
	// a switched-off load or topology rebuild replaces that distribution.
	material_pending_heat += material_paid_losses * elapsed_seconds
	material_pending_heat_elapsed += elapsed_seconds
	if(material_graph && (material_cache_dirty || material_graph.has_superconductors || material_pending_heat_elapsed >= MATERIAL_POWER_HEAT_SETTLEMENT_INTERVAL))
		material_graph.deposit_losses(material_pending_heat, material_pending_heat_elapsed)
		material_pending_heat = 0
		material_pending_heat_elapsed = 0
	if(material_cache_dirty)
		rebuild_material_cache()
	material_graph.resolve_loads(material_sources, material_consumers)
	material_paid_losses = 0
	material_consumers = null
	material_sources = material_next_sources
	material_next_sources = null
	if(material_loss_watts > max(load * 0.1, 1000))
		trigger_warning()

/// remove_machine() — remove a power machine; deletes the net if now empty.
/// Caller must verify the machine is in this net before calling.
/datum/powernet/proc/remove_machine(obj/machinery/power/M)
	if(istype(M, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/A = M
		unreserve_sleeping_apc_load(A)
	else if(istype(M, /obj/machinery/power/terminal))
		var/obj/machinery/power/terminal/T = M
		if(istype(T.master, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/A = T.master
			unreserve_sleeping_apc_load(A)
			apc_count = max(apc_count - 1, 0)
	else if(istype(M, /obj/machinery/power/smes))
		smes_nodes -= M
	nodes -= M
	invalidate_material_cache()
	M.powernet = null
	publish_dependency()
	if(is_empty())
		qdel(src)

/// add_machine() — add a power machine, disconnecting it from its old net first.
/// Idempotent: safe to call when the machine is already on this net.
/datum/powernet/proc/add_machine(obj/machinery/power/M)
	if(M.powernet)
		if(M.powernet == src)
			return
		M.disconnect_from_network()
	M.powernet = src
	nodes[M] = M
	invalidate_material_cache()
	if(istype(M, /obj/machinery/power/terminal))
		var/obj/machinery/power/terminal/T = M
		if(istype(T.master, /obj/machinery/power/apc))
			apc_count++
	else if(istype(M, /obj/machinery/power/smes))
		smes_nodes |= M
	publish_dependency()

/// trigger_warning() — flag a powernet problem visible on power monitors.
/datum/powernet/proc/trigger_warning(duration_ticks = 20)
	var/was_clear = problem <= 0
	problem = max(duration_ticks, problem)
	if(was_clear && problem > 0)
		publish_monitor_dependency()

/// reset() — handle per-tick power accounting.
/// Called every tick by the powernet controller (SSmachines).
///
/// Steps:
///   1. Decay the problem flag.
///   2. Update per-APC availability ration.
///   3. Delegate SMES input balancing to /datum/powernet_balancer.
///   4. Restore excess power to SMESes.
///   5. Smooth the viewable load/avail.
///   6. Reset accumulators for the next tick.
/datum/powernet/proc/reset()
	var/old_avail = avail
	var/old_netexcess = netexcess
	var/old_problem = problem
	// 1. Decay problem warning.
	if(problem > 0)
		problem = max(problem - 1, 0)
		if(old_problem > 0 && problem <= 0)
			publish_monitor_dependency()

	// 2. Count APC terminals and update per-APC ration.
	var/numapc = apc_count

	netexcess = avail - load

	if(numapc)
		// Simple load balancing: if net surplus existed this tick some APCs used less
		// than perapc, so raise the ration slightly expecting the same next tick.
		// Reverts to zero on deficit so we don't over-promise.
		if(netexcess >= 0)
			perapc_excess += min(netexcess / numapc, (avail - perapc) - perapc_excess)
		else
			perapc_excess = 0
		perapc = (numapc > 0) ? (avail / numapc + perapc_excess) : 0

	// 3. SMES input balancing — delegated to powernet_balancer.
	//    Only runs when there is actual SMES demand; balancer guards its own
	//    division-by-zero and validates terminal refs.
	if(inputting.len && smes_demand > 0)
		var/datum/powernet_balancer/balancer = new(src)
		balancer.execute()
		qdel(balancer)
	process_material_network()

	// 4. Restore excess power to SMESes proportionally.
	netexcess = avail - load
	if(netexcess)
		var/perc = get_percent_load(1)
		for(var/obj/machinery/power/smes/S as anything in smes_nodes)
			if(!S || QDELETED(S))
				continue
			S.restore(perc)

	// 5. Smooth viewable stats.
	viewavail = round(0.8 * viewavail + 0.2 * avail)
	viewload  = round(0.8 * viewload  + 0.2 * load)
	publish_apc_supply_changes()

	// 6. Reset accumulators for next tick.
	// Dynamic area usage is reported again by machines next tick. Keep only the
	// APC's stable base reservation between accounting windows.
	for(var/obj/machinery/power/apc/A as anything in sleeping_apc_dynamic_loads)
		var/dynamic_amount = sleeping_apc_dynamic_loads[A]
		if(A in sleeping_apc_loads)
			sleeping_apc_loads[A] = max(sleeping_apc_loads[A] - dynamic_amount, 0)
			sleeping_apc_load_total = max(sleeping_apc_load_total - dynamic_amount, 0)
	sleeping_apc_dynamic_loads.Cut()
	load         = sleeping_apc_load_total
	avail        = newavail
	smes_avail   = smes_newavail
	inputting.Cut()
	smes_demand  = 0
	newavail     = 0
	smes_newavail = 0
	// Sleeping APC demand is already reserved. Generator output jitter is not a
	// state change for them while the net remains on the same side of deficit;
	// charging progress has its own coarse elapsed-time wakeup.
	if((avail <= 0) != (old_avail <= 0) || ((netexcess < -1) != (old_netexcess < -1)))
		publish_monitor_dependency()
	var/has_live_accounting = avail || newavail || load > sleeping_apc_load_total || inputting.len || smes_demand || problem > 0
	if(has_live_accounting)
		idle_accounting_windows = 0
		return
	idle_accounting_windows++
	if(idle_accounting_windows >= 2)
		return PROCESS_KILL
	return

/datum/powernet/proc/get_percent_load(smes_only = 0)
	if(smes_only)
		var/smes_used = load - (avail - smes_avail)   // SMESes are last to provide power
		if(!smes_used || smes_used < 0 || !smes_avail)
			return 0
		return between(0, (smes_used / smes_avail) * 100, 100)
	else
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
	else
		return 0

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
