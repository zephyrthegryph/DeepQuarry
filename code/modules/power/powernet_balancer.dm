// /datum/powernet_balancer
//
// Handles the SMES input-balancing pass that was previously inlined in
// /datum/powernet/proc/reset().  Extracted here so it can be reasoned
// about, tested, and modified independently of the reset bookkeeping.
//
// Caller pattern (see powernet.dm reset()):
//
//   var/datum/powernet_balancer/B = new(src)
//   B.execute()
//
// The balancer operates on a powernet snapshot and mutates SMES charge
// via SMES.input_power().  It is a single-use datum: create, execute, discard.

/datum/powernet_balancer
	/// Powernet this balancer was created for.  Nulled after execute() returns.
	var/datum/powernet/net = null

/datum/powernet_balancer/New(datum/powernet/powernet)
	net = powernet

/datum/powernet_balancer/Destroy()
	net = null
	return ..()

/// execute() — execute one balancing pass.
/// Distributes available power proportionally among all SMES units that
/// are demanding input from this powernet.  Guards against division-by-zero
/// and validates each terminal reference before dereferencing its master.
/datum/powernet_balancer/proc/execute()
	if(!net)
		return

	// Skip the pass entirely if no SMES is requesting input.
	if(!net.inputting.len || net.smes_demand <= 0)
		return

	// Compute what fraction of SMES demand can be met this tick.
	// between() clamps to [0, 100]; division is safe because smes_demand > 0.
	var/net_excess = net.avail - net.load
	var/smes_input_percentage = between(0, (net_excess / net.smes_demand) * 100, 100)

	// Walk each demanding SMES terminal and deliver its share.
	for(var/obj/machinery/power/terminal/T in net.inputting)
		// Guard: terminal may have been deleted or disconnected since it
		// added itself to inputting this tick.
		if(!T || QDELETED(T))
			continue
		var/obj/machinery/power/smes/S = T.master
		if(!istype(S))
			continue
		// Guard: SMES itself may have been qdel'd mid-tick.
		if(QDELETED(S))
			continue
		S.input_power(smes_input_percentage, T)
