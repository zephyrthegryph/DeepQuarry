/datum/powernet
	var/list/cables = list()   // all cables & junctions
	var/list/nodes   // all connected machines
	var/apc_count = 0
	var/list/smes_nodes

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
	/// Persistent source rates. Republishing an unchanged rate is free.
	var/list/registered_sources
	var/list/registered_source_refs
	var/registered_supply_total = 0
	var/registered_smes_total = 0
	/// Persistent SMES charge requests keyed by their input terminal. Entry:
	/// storage, requested rate, currently allocated rate.
	var/list/registered_storage_demands
	var/registered_storage_demand_total = 0
	var/registered_storage_input_total = 0
	var/last_storage_settlement = 0

	var/perapc       = 0       // per-APC availability ration
	var/perapc_excess = 0      // accumulated excess fed back to perapc
	var/netexcess    = 0       // excess power on the net (avail - load), updated each tick

	var/problem = 0            // non-zero = some issue; power monitors will display warnings
	var/problem_timer
	var/material_problem = FALSE
	/// Stable demand retained for APCs that are dependency-sleeping.
	var/list/sleeping_apc_loads = list()
	/// Last semantic supply class observed by each sleeping APC. Accounting
	/// jitter which remains inside a class never wakes the APC.
	var/list/sleeping_apc_power_classes
	/// One-tick machine usage folded into sleeping APC reservations.
	var/list/sleeping_apc_dynamic_loads = list()
	var/sleeping_apc_load_total = 0
	/// Demand solved by the last completed accounting window. Repeated one-off
	/// area use is compared against this completed value, not against the cleared
	/// beginning-of-window accumulator.
	var/published_load_total = 0
	var/window_start_balance_class = 0
	var/revision = 1
	/// Composite cable topology is scanned only when the network changes.
	var/material_cache_dirty = TRUE
	/// Source/load vectors are independent from cable topology. Ordinary grids
	/// coalesce their changes until the physical settlement boundary; engineered
	/// conductors request an immediate solution.
	var/material_flow_dirty = TRUE
	var/datum/material_power_graph/material_graph
	var/list/material_sources
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
	/// Consecutive accounting windows with live state changes. Producer omission
	/// is resolved before powernets run, so a clean completed transaction can
	/// sleep immediately rather than paying for a redundant confirmation solve.
	var/idle_accounting_windows = 0
	var/accounting_dirty = TRUE
	var/material_settlement_timer
	/// Bounded diagnostic provenance for grids that refuse to settle.
	var/last_accounting_wake_reason = "initial"
	var/accounting_wake_count = 0
	/// Set while an edited cable graph is being repartitioned. The old network
	/// cannot deliver power across a severed edge during this interval.
	var/topology_pending = FALSE
	var/topology_generation = 0
	var/topology_batch_depth = 0

/datum/powernet/New()
	SSmachines.powernets |= src
	START_PROCESSING_POWERNET(src)
	..()

/datum/powernet/Destroy()
	SSmachines.deferred_powernet_splits -= src
	if(material_settlement_timer)
		deltimer(material_settlement_timer)
		material_settlement_timer = null
	if(problem_timer)
		deltimer(problem_timer)
		problem_timer = null
	for(var/obj/machinery/power/apc/A as anything in sleeping_apc_loads)
		A?.wake_for_power_dependency()
	sleeping_apc_loads.Cut()
	LAZYCLEARLIST(sleeping_apc_power_classes)
	sleeping_apc_dynamic_loads.Cut()
	for(var/obj/structure/cable/C in cables)
		cables -= C
		C.powernet = null
	for(var/obj/machinery/power/M in nodes)
		LAZYREMOVE(nodes, M)
		M.powernet = null
	STOP_PROCESSING_POWERNET(src)
	SSmachines.powernets -= src
	QDEL_NULL(material_graph)
	material_sources = null
	material_consumers = null
	registered_sources = null
	registered_source_refs = null
	registered_storage_demands = null
	return ..()

/datum/powernet/proc/register_power_supply(obj/machinery/power/source, amount, is_smes = FALSE)
	if(!source)
		return FALSE
	amount = max(amount, 0)
	var/list/entry = LAZYACCESS(registered_sources, source)
	if(!entry)
		entry = list(0, is_smes, 0)
		LAZYSET(registered_sources, source, entry)
		LAZYSET(registered_source_refs, source, WEAKREF(source))
	var/old_amount = entry[1]
	var/old_smes = entry[2]
	if(old_amount == amount && old_smes == is_smes)
		return FALSE
	var/old_supply_total = registered_supply_total
	var/old_balance_class = supply_balance_class(old_supply_total)
	if(old_smes || is_smes || registered_smes_total > 0 || registered_storage_input_total > 0)
		settle_registered_storage()
	registered_supply_total += amount - old_amount
	// Exact-rate consumers (capacitor chargers, diagnostics) are isolated from
	// the broad topology/availability dependency. They wake without forcing the
	// entire cable graph or every APC to process.
	SSmachines.publish_reactive_dependency("powernet-rate:[REF(src)]")
	if(old_smes)
		registered_smes_total -= old_amount
	if(is_smes)
		registered_smes_total += amount
	entry[1] = amount
	entry[2] = is_smes
	newavail = registered_supply_total
	smes_newavail = registered_smes_total
	rebuild_material_sources()
	var/new_balance_class = supply_balance_class(registered_supply_total)
	var/published_amount = entry[3] || 0
	var/publication_threshold = max(abs(published_amount) * MATERIAL_POWER_LOAD_RELATIVE_EPSILON, MATERIAL_POWER_LOAD_ABSOLUTE_EPSILON)
	// A healthy ordinary grid is load-led: changing surplus production cannot
	// alter delivery, cable current, or APC state until it crosses a balance
	// boundary. Keep monitor totals current in place without waking the complete
	// material/accounting graph for generator jitter. Engineered conductors and
	// storage retain magnitude publication because their physical state depends
	// on the exact source distribution.
	var/exact_supply_matters = old_smes || is_smes || registered_smes_total > 0 || registered_storage_demand_total > 0 || material_graph?.has_superconductors
	var/should_publish = !old_amount || !amount || old_smes != is_smes || old_balance_class != new_balance_class || (exact_supply_matters && abs(amount - published_amount) > publication_threshold)
	if(should_publish)
		entry[3] = amount
		mark_accounting_dirty("supply:[source.type]")
	else if(!(src in SSmachines.active_powernets))
		avail = registered_supply_total
		smes_avail = registered_smes_total
		netexcess = avail - load
	return TRUE

/datum/powernet/proc/supply_balance_class(supply)
	if(supply <= 0)
		return 0
	var/excess = supply - load
	if(excess < 0)
		return 1
	if(registered_storage_demand_total > 0 && excess + 0.01 < registered_storage_demand_total)
		return 2
	return 3

/datum/powernet/proc/unregister_power_supply(obj/machinery/power/source)
	var/list/entry = registered_sources?[source]
	if(!entry)
		return FALSE
	if(entry[2])
		settle_registered_storage()
	registered_supply_total = max(registered_supply_total - entry[1], 0)
	if(entry[2])
		registered_smes_total = max(registered_smes_total - entry[1], 0)
	LAZYREMOVE(registered_sources, source)
	LAZYREMOVE(registered_source_refs, source)
	newavail = registered_supply_total
	smes_newavail = registered_smes_total
	rebuild_material_sources()
	mark_accounting_dirty()
	return TRUE

/datum/powernet/proc/register_storage_demand(obj/machinery/power/smes/storage, obj/machinery/power/terminal/terminal, amount)
	if(!storage || !terminal || terminal.powernet != src)
		return FALSE
	amount = max(amount, 0)
	var/list/entry = LAZYACCESS(registered_storage_demands, terminal)
	if(!amount)
		if(!entry)
			return FALSE
		settle_registered_storage()
		registered_storage_demand_total = max(registered_storage_demand_total - entry[2], 0)
		registered_storage_input_total = max(registered_storage_input_total - entry[3], 0)
		load = max(load - entry[3], 0)
		LAZYREMOVE(registered_storage_demands, terminal)
		mark_accounting_dirty()
		return TRUE
	if(entry && entry[1] == storage && entry[2] == amount)
		return FALSE
	settle_registered_storage()
	if(entry)
		registered_storage_demand_total -= entry[2]
		registered_storage_input_total -= entry[3]
		load = max(load - entry[3], 0)
	else
		entry = list(storage, 0, 0)
		LAZYSET(registered_storage_demands, terminal, entry)
	entry[1] = storage
	entry[2] = amount
	entry[3] = 0
	registered_storage_demand_total += amount
	mark_accounting_dirty()
	return TRUE

/datum/powernet/proc/unregister_storage_terminal(obj/machinery/power/terminal/terminal)
	var/list/entry = registered_storage_demands?[terminal]
	if(!entry)
		return FALSE
	return register_storage_demand(entry[1], terminal, 0)

/datum/powernet/proc/rebuild_material_sources()
	material_sources = list()
	for(var/obj/machinery/power/source as anything in registered_sources)
		var/list/entry = LAZYACCESS(registered_sources, source)
		if(entry[1] > 0)
			material_sources[LAZYACCESS(registered_source_refs, source)] = entry[1]
	material_flow_dirty = TRUE

/// Integrate actual SMES energy usage over elapsed machinery intervals. Stable
/// SMES output is a registered rate, so an unchanged network needs no debit and
/// refund cycle on every subsystem fire.
/datum/powernet/proc/settle_registered_storage()
	if(!last_storage_settlement)
		last_storage_settlement = world.time
		return
	var/elapsed_ticks = max((world.time - last_storage_settlement) / max(SSmachines.wait, 1), 0)
	last_storage_settlement = world.time
	if(elapsed_ticks <= 0 || registered_smes_total <= 0)
		// Charging-only networks still have elapsed work below.
		if(elapsed_ticks <= 0 || registered_storage_input_total <= 0)
			return
	var/non_smes_supply = max(avail - smes_avail, 0)
	// `load` is reset to the retained non-storage demand between accounting
	// windows; the persistent charging allocation remains a real consumer.
	var/smes_used = clamp(load + registered_storage_input_total - non_smes_supply, 0, registered_smes_total)
	for(var/obj/machinery/power/smes/storage as anything in registered_sources)
		var/list/entry = LAZYACCESS(registered_sources, storage)
		if(!entry[2] || entry[1] <= 0)
			continue
		storage.consume_registered_output(smes_used * entry[1] / registered_smes_total, elapsed_ticks)
	for(var/obj/machinery/power/terminal/terminal as anything in registered_storage_demands)
		var/list/demand = LAZYACCESS(registered_storage_demands, terminal)
		if(demand[3] <= 0)
			continue
		var/obj/machinery/power/smes/storage = demand[1]
		storage.receive_registered_input(demand[3], elapsed_ticks)

/datum/powernet/proc/reserve_sleeping_apc_load(obj/machinery/power/apc/A, amount)
	if(!A)
		return
	// An APC briefly leaves the reservation table while integrating a semantic
	// wake. Preserve the supply class which caused that wake. Recomputing it
	// against the previous accounting window here made the completed window flip
	// it back again, waking every APC on the station in an endless two-state loop.
	var/previous_supply_class = LAZYACCESS(sleeping_apc_power_classes, A)
	unreserve_sleeping_apc_load(A)
	amount = max(amount, 0)
	sleeping_apc_loads[A] = amount
	sleeping_apc_load_total += amount
	LAZYSET(sleeping_apc_power_classes, A, isnull(previous_supply_class) ? apc_supply_class(amount) : previous_supply_class)
	material_flow_dirty = TRUE
	mark_accounting_dirty()

/datum/powernet/proc/unreserve_sleeping_apc_load(obj/machinery/power/apc/A)
	if(!A || !(A in sleeping_apc_loads))
		return
	var/reserved = sleeping_apc_loads[A]
	sleeping_apc_load_total -= reserved
	load = max(load - reserved, 0)
	sleeping_apc_loads.Remove(A)
	LAZYREMOVE(sleeping_apc_power_classes, A)
	sleeping_apc_dynamic_loads.Remove(A)
	material_flow_dirty = TRUE
	mark_accounting_dirty()

/// Adjust demand in place without waking an APC for routine area accounting.
/datum/powernet/proc/adjust_sleeping_apc_load(obj/machinery/power/apc/A, delta)
	if(!A || !delta || !(A in sleeping_apc_loads))
		return FALSE
	SSmachines.touch_accounting_powernet(src)
	var/old_amount = sleeping_apc_loads[A]
	var/new_amount = max(old_amount + delta, 0)
	sleeping_apc_loads[A] = new_amount
	sleeping_apc_dynamic_loads[A] = (sleeping_apc_dynamic_loads[A] || 0) + delta
	sleeping_apc_load_total += new_amount - old_amount
	load = max(load + new_amount - old_amount, 0)
	return TRUE

/// Start a new machine accounting window without waking this grid. Dynamic area
/// draws are reported again during the machinery pass; clearing the previous
/// window here lets an identical load compare equal to published_load_total and
/// keeps an otherwise stable powernet asleep.
/datum/powernet/proc/begin_accounting_window()
	window_start_balance_class = supply_balance_class(registered_supply_total)
	for(var/obj/machinery/power/apc/A as anything in sleeping_apc_dynamic_loads)
		var/dynamic_amount = sleeping_apc_dynamic_loads[A]
		if(A in sleeping_apc_loads)
			sleeping_apc_loads[A] = max(sleeping_apc_loads[A] - dynamic_amount, 0)
			sleeping_apc_load_total = max(sleeping_apc_load_total - dynamic_amount, 0)
	load = sleeping_apc_load_total + material_loss_watts
	sleeping_apc_dynamic_loads.Cut()

/// Publish a completed demand transaction once, after every APC has reported.
/// Comparing partial accumulation made a healthy grid appear to cross deficit
/// boundaries hundreds of times per fire and woke every sleeping APC.
/datum/powernet/proc/finalize_accounting_window()
	var/new_balance_class = supply_balance_class(registered_supply_total)
	var/load_threshold = max(abs(published_load_total) * MATERIAL_POWER_LOAD_RELATIVE_EPSILON, MATERIAL_POWER_LOAD_ABSOLUTE_EPSILON)
	var/material_flow_matters = material_graph?.has_custom_conductors || material_graph?.has_superconductors
	var/exact_load_matters = material_graph?.has_superconductors
	var/load_changed = abs(load - published_load_total) > load_threshold
	if(load_changed)
		SSmachines.publish_reactive_dependency("powernet-rate:[REF(src)]")
		// Ordinary steel/copper station wiring has no stateful material response
		// to a routine load-rate change. Only an engineered conductor needs a new
		// flow solve and a future thermal settlement.
		if(material_flow_matters)
			material_flow_dirty = TRUE
		if(material_graph?.has_custom_conductors && !exact_load_matters)
			schedule_material_settlement(MATERIAL_POWER_GRAPH_SETTLEMENT_INTERVAL)
	if(window_start_balance_class != new_balance_class || (exact_load_matters && abs(load - published_load_total) > load_threshold))
		mark_accounting_dirty("area-load-window")

/datum/powernet/proc/mark_accounting_dirty(reason = "state")
	accounting_dirty = TRUE
	idle_accounting_windows = 0
	last_accounting_wake_reason = reason
	accounting_wake_count++
	START_PROCESSING_POWERNET(src)

/datum/powernet/proc/schedule_material_settlement(delay)
	if(material_settlement_timer || QDELETED(src))
		return
	delay = max(delay, 1)
	material_settlement_timer = addtimer(CALLBACK(src, PROC_REF(material_settlement_due)), delay, TIMER_STOPPABLE)

/datum/powernet/proc/material_settlement_due()
	material_settlement_timer = null
	mark_accounting_dirty()

/// Machine membership changed. Sleeping APCs subscribe to this network's
/// topology key, so one publication reaches all of them.
/datum/powernet/proc/publish_dependency()
	publish_cable_dependency()
	SSmachines.publish_reactive_dependency("powernet-topology:[REF(src)]")

/// Cable membership changed. That moves line losses but not which machines
/// share the network, so APCs are left asleep.
/datum/powernet/proc/publish_cable_dependency()
	revision++
	mark_accounting_dirty()
	SSmachines.publish_reactive_dependency("powernet:[REF(src)]")

/// Publish monitor-visible state without fanning one accounting sample out to
/// every APC. APCs receive their own semantic supply transition below.
/datum/powernet/proc/publish_monitor_dependency()
	revision++
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
		if(LAZYACCESS(sleeping_apc_power_classes, A) == new_class)
			continue
		LAZYSET(sleeping_apc_power_classes, A, new_class)
		SSmachines.publish_reactive_dependency("apc-power:[REF(A)]")

/// last_surplus() — excess power before refunds to SMESes, from last tick.
/// Machines may read this to adjust consumption.
/datum/powernet/proc/last_surplus()
	return max(avail - load, 0)

/datum/powernet/proc/draw_power(amount, atom/consumer)
	mark_accounting_dirty(consumer ? "draw:[consumer.type]" : "draw:unknown")
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
	return !cables.len && !length(nodes)

/// remove_cable() — remove a cable and delete the powernet if now empty.
/// Caller must verify the cable is in this net before calling.
/datum/powernet/proc/remove_cable(obj/structure/cable/C)
	cables -= C
	C.powernet = null
	if(!topology_batch_depth)
		invalidate_material_cache()
		publish_cable_dependency()
	if(is_empty())
		qdel(src)

/// Clear accounting membership before a targeted topology transaction rebinds
/// the affected machines. Cable membership is published separately.
/datum/powernet/proc/prepare_topology_rebind()
	if(material_settlement_timer)
		deltimer(material_settlement_timer)
		material_settlement_timer = null
	for(var/obj/machinery/power/apc/apc as anything in sleeping_apc_loads)
		apc.wake_for_power_dependency()
	for(var/obj/machinery/power/machine as anything in nodes)
		machine.powernet = null
	nodes = list()
	apc_count = 0
	smes_nodes = list()
	registered_sources = list()
	registered_source_refs = list()
	registered_storage_demands = list()
	registered_supply_total = 0
	registered_smes_total = 0
	registered_storage_demand_total = 0
	registered_storage_input_total = 0
	sleeping_apc_loads = list()
	sleeping_apc_power_classes = list()
	sleeping_apc_dynamic_loads = list()
	sleeping_apc_load_total = 0
	material_sources = null
	material_consumers = null
	material_loss_watts = 0
	material_pending_heat = 0
	material_pending_heat_elapsed = 0
	avail = 0
	newavail = 0
	load = 0
	netexcess = 0
	QDEL_NULL(material_graph)

/// Bind a machine without emitting per-object topology publications. Its next
/// process call republishes source, storage, or APC accounting state.
/datum/powernet/proc/bind_machine_after_topology(obj/machinery/power/machine)
	machine.powernet = src
	LAZYSET(nodes, machine, machine)
	if(istype(machine, /obj/machinery/power/terminal))
		var/obj/machinery/power/terminal/terminal = machine
		if(istype(terminal.master, /obj/machinery/power/apc))
			apc_count++
	else if(istype(machine, /obj/machinery/power/smes))
		LAZYOR(smes_nodes, machine)
	machine.power_supply_generation = 0
	START_MACHINE_PROCESSING(machine)

/// add_cable() — add a cable, migrating it from its current net if needed.
/// Idempotent: safe to call when the cable is already on this net.
/datum/powernet/proc/add_cable(obj/structure/cable/C)
	if(C.powernet)
		if(C.powernet == src)
			return
		C.powernet.remove_cable(C)
	C.powernet = src
	cables += C
	if(!topology_batch_depth)
		invalidate_material_cache()
		publish_cable_dependency()

/datum/powernet/proc/begin_topology_batch()
	topology_batch_depth++

/datum/powernet/proc/end_topology_batch()
	if(topology_batch_depth <= 0)
		return
	topology_batch_depth--
	if(topology_batch_depth)
		return
	invalidate_material_cache()
	publish_dependency()

/datum/powernet/proc/invalidate_material_cache()
	material_cache_dirty = TRUE
	material_flow_dirty = TRUE

/datum/powernet/proc/rebuild_material_cache()
	material_cache_dirty = FALSE
	QDEL_NULL(material_graph)
	material_graph = new
	material_graph.build(cables)

/datum/powernet/proc/process_material_network()
	// Any accounting wake invalidates the old predicted deadline. Recompute it
	// from the newly published source/load state below.
	if(material_settlement_timer)
		deltimer(material_settlement_timer)
		material_settlement_timer = null
	var/elapsed_seconds = last_material_process ? max((world.time - last_material_process) / 10, 0.1) : 1
	last_material_process = world.time
	if(material_cache_dirty)
		rebuild_material_cache()
	// The standard mapped grid has no stateful conductor behavior to integrate.
	// Building its topology once keeps it ready for diagnostics and later cable
	// replacement, but walking every sleeping APC and solving resistive losses on
	// every accounting event merely feeds ordinary load back into itself. A
	// custom or superconducting conductor flips these graph flags and enters the
	// physical path below without any machine-type exception.
	if(!material_graph?.has_custom_conductors && !material_graph?.has_superconductors)
		material_consumers = null
		material_loss_watts = 0
		material_paid_losses = 0
		material_pending_heat = 0
		material_pending_heat_elapsed = 0
		material_flow_dirty = FALSE
		return
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
	// Settle the previous solved rate over the interval for which it was valid.
	if(material_graph?.has_custom_conductors || material_graph?.has_superconductors)
		material_pending_heat += material_loss_watts * elapsed_seconds
		material_pending_heat_elapsed += elapsed_seconds
	else
		material_pending_heat = 0
		material_pending_heat_elapsed = 0
	// Settle the completed interval against its original flow distribution before
	// a switched-off load or topology rebuild replaces that distribution.
	if(material_graph && (material_graph.has_custom_conductors || material_graph.has_superconductors) && (material_cache_dirty || material_graph.has_superconductors || material_pending_heat_elapsed >= MATERIAL_POWER_HEAT_SETTLEMENT_INTERVAL))
		material_graph.deposit_losses(material_pending_heat, material_pending_heat_elapsed)
		material_pending_heat = 0
		material_pending_heat_elapsed = 0
	// The base powernet remains authoritative every tick. Its material overlay
	// only needs a new mesh solution at the physical settlement cadence unless
	// an engineered conductor has temperature/current-dependent behaviour.
	if(material_flow_dirty || material_graph.has_superconductors || material_graph.solve_pending)
		var/solve_result = material_graph.resolve_loads(material_sources, material_consumers)
		material_flow_dirty = FALSE
		if(solve_result == 2)
			schedule_material_settlement(1)
	material_loss_watts = material_graph.loss_watts
	material_paid_losses = 0
	material_consumers = null
	var/settlement_delay = 0
	if(material_graph.has_superconductors)
		settlement_delay = MATERIAL_POWER_HEAT_SETTLEMENT_INTERVAL
	else if(material_graph.has_custom_conductors)
		settlement_delay = MATERIAL_POWER_GRAPH_SETTLEMENT_INTERVAL
	// Output-only storage needs one wake at the earliest possible depletion
	// boundary. Stable unused capacity has no passage-of-time work to perform.
	if(registered_smes_total > 0)
		var/non_smes_supply = max(avail - smes_avail, 0)
		var/smes_used = clamp(load - non_smes_supply, 0, registered_smes_total)
		if(smes_used > 0)
			for(var/obj/machinery/power/smes/storage as anything in registered_sources)
				var/list/entry = LAZYACCESS(registered_sources, storage)
				if(!entry[2] || entry[1] <= 0)
					continue
				var/storage_rate = smes_used * entry[1] / registered_smes_total
				if(storage_rate <= 0)
					continue
				var/depletion_delay = CEILING(storage.charge / SMESRATE / storage_rate * SSmachines.wait, 1)
				if(!settlement_delay || depletion_delay < settlement_delay)
					settlement_delay = depletion_delay
	for(var/obj/machinery/power/terminal/terminal as anything in registered_storage_demands)
		var/list/demand = LAZYACCESS(registered_storage_demands, terminal)
		if(demand[3] <= 0)
			continue
		var/obj/machinery/power/smes/storage = demand[1]
		var/fill_delay = CEILING((storage.capacity - storage.charge) / SMESRATE / demand[3] * SSmachines.wait, 1)
		if(!settlement_delay || fill_delay < settlement_delay)
			settlement_delay = fill_delay
	if(settlement_delay)
		schedule_material_settlement(settlement_delay)
	set_material_warning(material_loss_watts > max(load * 0.1, 1000))

/// remove_machine() — remove a power machine; deletes the net if now empty.
/// Caller must verify the machine is in this net before calling.
/datum/powernet/proc/remove_machine(obj/machinery/power/M)
	unregister_power_supply(M)
	if(istype(M, /obj/machinery/power/apc))
		var/obj/machinery/power/apc/A = M
		unreserve_sleeping_apc_load(A)
	else if(istype(M, /obj/machinery/power/terminal))
		var/obj/machinery/power/terminal/T = M
		unregister_storage_terminal(T)
		if(istype(T.master, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/A = T.master
			unreserve_sleeping_apc_load(A)
			apc_count = max(apc_count - 1, 0)
	else if(istype(M, /obj/machinery/power/smes))
		LAZYREMOVE(smes_nodes, M)
	LAZYREMOVE(nodes, M)
	if(!topology_batch_depth)
		invalidate_material_cache()
	M.powernet = null
	if(!topology_batch_depth)
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
	LAZYSET(nodes, M, M)
	if(!topology_batch_depth)
		invalidate_material_cache()
	if(istype(M, /obj/machinery/power/terminal))
		var/obj/machinery/power/terminal/T = M
		if(istype(T.master, /obj/machinery/power/apc))
			apc_count++
	else if(istype(M, /obj/machinery/power/smes))
		LAZYOR(smes_nodes, M)
	if(!topology_batch_depth)
		publish_dependency()

/// trigger_warning() — flag a powernet problem visible on power monitors.
/datum/powernet/proc/trigger_warning(duration_ticks = 20)
	var/was_clear = problem <= 0
	problem = TRUE
	if(problem_timer)
		deltimer(problem_timer)
	problem_timer = addtimer(CALLBACK(src, PROC_REF(clear_warning)), max(duration_ticks, 1), TIMER_STOPPABLE)
	if(was_clear)
		publish_monitor_dependency()

/datum/powernet/proc/clear_warning()
	problem_timer = null
	var/was_problem = problem
	problem = material_problem
	if(was_problem == problem)
		return
	publish_monitor_dependency()

/datum/powernet/proc/set_material_warning(active)
	active = !!active
	if(material_problem == active)
		return
	material_problem = active
	var/was_problem = problem
	problem = material_problem || !!problem_timer
	if(was_problem != problem)
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
	if(topology_pending)
		return PROCESS_KILL
	accounting_dirty = FALSE
	settle_registered_storage()
	var/old_avail = avail
	var/old_netexcess = netexcess
	// 1. Count APC terminals and update per-APC ration.
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

	// 2. Legacy transient SMES input requests remain supported.
	if(inputting.len && smes_demand > 0)
		var/datum/powernet_balancer/balancer = new(src)
		balancer.execute()
		qdel(balancer)
	// Stable requests are allocated once and then integrated by elapsed time.
	registered_storage_input_total = 0
	if(registered_storage_demand_total > 0)
		var/storage_excess = max(avail - load, 0)
		var/storage_fraction = clamp(storage_excess / registered_storage_demand_total, 0, 1)
		for(var/obj/machinery/power/terminal/terminal as anything in registered_storage_demands)
			var/list/demand = LAZYACCESS(registered_storage_demands, terminal)
			var/allocated = demand[2] * storage_fraction
			demand[3] = allocated
			registered_storage_input_total += allocated
			var/obj/machinery/power/smes/storage = demand[1]
			storage.set_registered_input(allocated, demand[2])
		load += registered_storage_input_total
	process_material_network()

	// 3. SMES storage was settled above from its registered output rate.
	netexcess = avail - load

	// 4. Smooth viewable stats.
	viewavail = round(0.8 * viewavail + 0.2 * avail)
	viewload  = round(0.8 * viewload  + 0.2 * load)
	published_load_total = load
	publish_apc_supply_changes()

	// 5. Reset accumulators for next tick.
	// Dynamic area usage is reported again by machines next tick. Keep only the
	// APC's stable base reservation between accounting windows.
	// Dynamic demand remains as the monitor-visible completed window until
	// begin_accounting_window() clears it immediately before the next machinery
	// pass reports current use.
	avail        = newavail
	smes_avail   = smes_newavail
	inputting.Cut()
	smes_demand  = 0
	newavail     = registered_supply_total
	smes_newavail = registered_smes_total
	// Sleeping APC demand is already reserved. Generator output jitter is not a
	// state change for them while the net remains on the same side of deficit;
	// charging progress has its own coarse elapsed-time wakeup.
	if((avail <= 0) != (old_avail <= 0) || ((netexcess < -1) != (old_netexcess < -1)))
		publish_monitor_dependency()
	var/has_live_accounting = accounting_dirty || inputting.len || smes_demand
	if(has_live_accounting)
		idle_accounting_windows = 0
		return
	idle_accounting_windows++
	return PROCESS_KILL

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
