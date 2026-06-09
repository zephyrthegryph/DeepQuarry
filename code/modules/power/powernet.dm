/datum/powernet
	var/list/cables = list()   // all cables & junctions
	var/list/nodes  = list()   // all connected machines

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

/datum/powernet/New()
	START_PROCESSING_POWERNET(src)
	..()

/datum/powernet/Destroy()
	for(var/obj/structure/cable/C in cables)
		cables -= C
		C.powernet = null
	for(var/obj/machinery/power/M in nodes)
		nodes -= M
		M.powernet = null
	STOP_PROCESSING_POWERNET(src)
	return ..()

/// last_surplus() — excess power before refunds to SMESes, from last tick.
/// Machines may read this to adjust consumption.
/datum/powernet/proc/last_surplus()
	return max(avail - load, 0)

/datum/powernet/proc/draw_power(amount)
	var/draw = between(0, amount, avail - load)
	load += draw
	return draw

/datum/powernet/proc/is_empty()
	return !cables.len && !nodes.len

/// remove_cable() — remove a cable and delete the powernet if now empty.
/// Caller must verify the cable is in this net before calling.
/datum/powernet/proc/remove_cable(obj/structure/cable/C)
	cables -= C
	C.powernet = null
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

/// remove_machine() — remove a power machine; deletes the net if now empty.
/// Caller must verify the machine is in this net before calling.
/datum/powernet/proc/remove_machine(obj/machinery/power/M)
	nodes -= M
	M.powernet = null
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

/// trigger_warning() — flag a powernet problem visible on power monitors.
/datum/powernet/proc/trigger_warning(duration_ticks = 20)
	problem = max(duration_ticks, problem)

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
	// 1. Decay problem warning.
	if(problem > 0)
		problem = max(problem - 1, 0)

	// 2. Count APC terminals and update per-APC ration.
	var/numapc = 0
	if(nodes && nodes.len)
		for(var/obj/machinery/power/terminal/term in nodes)
			// Guard: terminal may have been qdel'd mid-tick.
			if(!term || QDELETED(term))
				continue
			if(istype(term.master, /obj/machinery/power/apc))
				numapc++

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

	// 4. Restore excess power to SMESes proportionally.
	netexcess = avail - load
	if(netexcess)
		var/perc = get_percent_load(1)
		for(var/obj/machinery/power/smes/S in nodes)
			if(!S || QDELETED(S))
				continue
			S.restore(perc)

	// 5. Smooth viewable stats.
	viewavail = round(0.8 * viewavail + 0.2 * avail)
	viewload  = round(0.8 * viewload  + 0.2 * load)

	// 6. Reset accumulators for next tick.
	load         = 0
	avail        = newavail
	smes_avail   = smes_newavail
	inputting.Cut()
	smes_demand  = 0
	newavail     = 0
	smes_newavail = 0

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
