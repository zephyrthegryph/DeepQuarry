//
// The machine system (was SSmachines): gas wakes, the batched pump commit and
// the power step (M3: the power network itself runs in Rust, see code/modules/power/power_bridge.dm),
// run every MACHINE_SERVICE_INTERVAL by machine_step. It polls no machines: a machine's own work is an every(when = ...) that
// parks while the machine is not operable (started_work(), code/library/machine/started_work.dm). Pipenets live on SSair (LINDA).
//

SYSTEM_DEF(machines)
	name = "Machines"
	periodic_runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	/// TRUE while a machine step that ran over budget waits to resume.
	VAR_PRIVATE/machines_resuming = FALSE

	/// Stage costs (EMA of each logical stage, all resumed slices combined) and their last run.
	var/cost_machinery     = 0
	var/cost_powernets     = 0
	var/last_cost_machinery = 0
	var/last_cost_powernets = 0
	/// In-flight machinery and power stage accumulators. They deliberately survive yields.
	var/current_cost_machinery = 0
	var/current_cost_powernets = 0
	/// Re-read every power machine's region on the next power step even if the cable topology held still (boot,
	/// and anything that resets the grid lists by hand).
	var/power_regions_stale = TRUE

	/// Machine gas transfers accumulated since the last commit. Rust commits this flat set under
	/// one publication lock after the pipeline devices have calculated their requested flow.
	var/list/pending_pump_transfers = list()
	/// Cost and cardinality of the last atomic pump commit.
	var/last_pump_commit_ms = 0
	/// Independent monotonic wall time and its excess over BYOND active time.
	/// This prevents an OS pause from being diagnosed as gas-transfer work.
	var/last_pump_commit_wall_ms = 0
	var/last_pump_commit_suspended_ms = 0
	var/last_pump_commit_operations = 0
	var/last_pump_commit_turfs = 0

	/// Gas dependency observations (the frame's CHANGED records of gas watches, native_system().take_gas_changes()) retained while a step yields.
	var/list/pending_dirty_gas_mixtures
	var/pending_dirty_gas_index = 1
	var/gas_dirty_last = 0
	var/gas_woken_last = 0
	var/gas_dead_last = 0
	var/gas_wake_scan_last_ms = 0
	var/gas_wake_subscribers_last = 0
	var/current_gas_wake_scan_ms = 0
	var/current_gas_wake_subscribers = 0

/// Boot: one power step, then a complete gas wake and pump commit (SSair.Initialize calls this
/// where SSmachines used to initialize, before the atmos machinery setup).
/// SSair boots it by hand (kernel_boot_system()) at the top of its own initialize(): the machine step needs the map and
/// the pipenets, so it is not a node of the boot DAG.
/datum/system/machines/boots_in_dag()
	return FALSE

/datum/system/machines/initialize()
	process_power()
	while(!wake_dirty_gas_subscribers(FALSE))
		continue
	flush_pump_transfers()
	log_world("Machine service initialized: [length(power_grids)] power regions, [gas_dirty_last] gas observations.")

/// Gas watches, then the pump transfers the pipeline devices queued since the last commit, then
/// the power step. The gas wake may yield; the power step only starts once it has completed, and its
/// APC/SMES poll may yield too (a resumed step carries on with the poll).
/datum/system/machines/reactions()
	. = ..()
	. += every(MACHINE_SERVICE_INTERVAL, PROC_REF(machine_step), when = PROC_REF(work_ready), lane = LANE_SIMULATION)

/// One kernel run of the machine step: yields over budget (resumes next tick).
/datum/system/machines/proc/machine_step(dt)
	var/done = step_machines(machines_resuming)
	machines_resuming = !done
	return done ? STEP_DONE : STEP_YIELD

/datum/system/machines/proc/step_machines(resumed)
	if(!power_poll_queue)
		var/started = TICK_USAGE
		if(!resumed)
			current_cost_machinery = 0
			current_gas_wake_scan_ms = 0
			current_gas_wake_subscribers = 0
		var/complete = wake_dirty_gas_subscribers(TRUE)
		if(complete)
			flush_pump_transfers()
		current_cost_machinery += TICK_USAGE_TO_MS(started)
		if(!complete)
			return FALSE
		last_cost_machinery = current_cost_machinery
		cost_machinery = KERNEL_AVERAGE(cost_machinery, last_cost_machinery)
		current_cost_powernets = 0
		var/begin_started = TICK_USAGE
		process_power_begin()
		current_cost_powernets += TICK_USAGE_TO_MS(begin_started)
	var/power_started = TICK_USAGE
	var/polled = poll_power_storage(TRUE)
	if(polled)
		process_power_finish()
	current_cost_powernets += TICK_USAGE_TO_MS(power_started)
	if(!polled)
		return FALSE
	last_cost_powernets = current_cost_powernets
	cost_powernets = KERNEL_AVERAGE(cost_powernets, last_cost_powernets)
	return TRUE

/// The whole power step at once (boot and admin repair). The world lane runs it in parts instead
/// (service_step()), so the APC poll can yield between ticks.
/datum/system/machines/proc/process_power()
	process_power_begin()
	poll_power_storage(FALSE)
	process_power_finish()

/// The power step up to the APC/SMES poll: area loads, the Rust commit, grid state and every power
/// machine's region. Queues the APCs and SMES for poll_power_storage().
/datum/system/machines/proc/process_power_begin()
	power_flush_areas()
	vg_power_commit()
	for(var/id in power_grids)
		if(!power_grid_refresh(id))
			power_grids -= id
			continue
		power_grid_sync_problem(id)
	// Every power machine's `power_region` is polled here, not pushed --
	// a deferred `connect_to_network(FALSE)` (map load, and every
	// `power_autoconnect()`) relies on this to eventually resolve. Region ids
	// only change with the cable topology, so the poll runs only after it was
	// edited (power_topology_edited(), committed above or by a Rust frame): an
	// idle station's grid holds still, and two FFI calls per power machine every
	// step added up.
	if(power_regions_stale)
		power_regions_stale = FALSE
		for(var/obj/machinery/power/machine as anything in REGISTRY_MEMBERS(REGISTRY_POWER_MACHINES))
			if(!QDELETED(machine))
				machine.power_refresh_network()
	power_poll_queue = REGISTRY_MEMBERS(REGISTRY_APCS) + REGISTRY_MEMBERS(REGISTRY_SMES)
	power_poll_index = 1

/// Polls the queued APCs and SMES. A poll that finds an APC's channels changed repowers its area
/// (apply_area_power(): every machine and light in it), so when every APC changes at once -- the first
/// step of a round, or a grid coming back -- the poll is seconds of work. `budgeted` stops at the tick
/// limit and returns FALSE (the next call carries on); otherwise it polls them all.
/datum/system/machines/proc/poll_power_storage(budgeted)
	var/list/queue = power_poll_queue
	while(power_poll_index <= length(queue))
		var/obj/machinery/power/machine = queue[power_poll_index++]
		if(QDELETED(machine))
			continue
		if(istype(machine, /obj/machinery/power/apc))
			var/obj/machinery/power/apc/apc = machine
			apc.power_poll()
		else
			var/obj/machinery/power/smes/storage = machine
			storage.power_poll()
		if(budgeted && TICK_CHECK)
			return FALSE
	power_poll_queue = null
	power_poll_index = 1
	return TRUE

/datum/system/machines/stat_entry(msg)
	. = "[..()]C:{MC:[round(last_cost_machinery,1)]/[round(cost_machinery,1)]|"
	. += "PN:[round(last_cost_powernets,1)]/[round(cost_powernets,1)]} "
	. += "PN:[length(power_grids)]|"
	. += "GD:[gas_dirty_last] GW:[gas_woken_last] GX:[gas_dead_last]"

/datum/system/machines/proc/flush_pump_transfers()
	if(!length(pending_pump_transfers))
		last_pump_commit_ms = 0
		last_pump_commit_wall_ms = 0
		last_pump_commit_suspended_ms = 0
		last_pump_commit_operations = 0
		last_pump_commit_turfs = 0
		return
	var/commit_started = TICK_USAGE
	var/commit_wall_timer = "machines-pump-commit"
	rustg_time_reset(commit_wall_timer)
	var/list/operations = list()
	for(var/list/transfer as anything in pending_pump_transfers)
		// List union silently removes repeated datum values. Many vents share one
		// pipenet, so append by index to preserve the fixed source/sink/moles tuples.
		var/operation_offset = length(operations)
		operations.len += 3
		// Pass stable arena IDs, not DM wrapper datums. Pipenet publication may
		// replace a member's wrapper while preserving its authoritative Rust mix;
		// resolving a private wrapper var inside the FFI made otherwise valid
		// queued transfers silently report zero.
		var/datum/gas_mixture/source = transfer[2]
		var/datum/gas_mixture/sink = transfer[3]
		operations[operation_offset + 1] = source.arena_id()
		operations[operation_offset + 2] = sink.arena_id()
		operations[operation_offset + 3] = transfer[4]
	var/list/actual_moles = vg_batch_transfer_hook(operations)
	var/list/touched_turfs = list()
	for(var/i = 1 to length(pending_pump_transfers))
		var/list/transfer = pending_pump_transfers[i]
		var/obj/machinery/atmospherics/M = transfer[1]
		var/actual = (islist(actual_moles) && i <= length(actual_moles)) ? actual_moles[i] : 0
		if(!M || QDELETED(M))
			continue
		M.pump_transaction_committed(actual)
		if(actual < MINIMUM_MOLES_TO_PUMP)
			continue
		var/source_moles = max(transfer[6], MINIMUM_MOLES_TO_PUMP)
		M.last_flow_rate = (actual / source_moles) * transfer[7]
		var/power_draw = transfer[5] * actual
		var/datum/gas_mixture/destination = transfer[3]
		M.record_material_pumping(power_draw, destination, actual)
		M.last_power_draw = power_draw
		M.use_power(power_draw)
		if(isturf(M.loc))
			var/turf/open/T = M.loc
			if(istype(T))
				touched_turfs[T] = TRUE
		gas_touched(destination)
	// Publication is atomic, so visuals and turf dependencies should observe it
	// atomically too. Multiple devices on one turf now cause one semantic update.
	for(var/turf/open/T as anything in touched_turfs)
		T.update_visuals()
		T.air_update_turf(FALSE, FALSE)
	last_pump_commit_operations = length(pending_pump_transfers)
	last_pump_commit_turfs = length(touched_turfs)
	last_pump_commit_ms = TICK_DELTA_TO_MS(TICK_USAGE - commit_started)
	last_pump_commit_wall_ms = rustg_time_milliseconds(commit_wall_timer)
	last_pump_commit_suspended_ms = max(last_pump_commit_wall_ms - last_pump_commit_ms, 0)
	pending_pump_transfers.Cut()

/// Hands this batch of gas dependency observations (from the frame's outbox) to their native watches
/// (/datum/native_watch/gas, code/datums/om/native.dm). The OM watch layer owns one
/// native watch per watched mixture (code/datums/om/watch.dm), which fans the record
/// directly to each surviving native gas subscription.
/datum/system/machines/proc/wake_dirty_gas_subscribers(budgeted = FALSE)
	var/scan_started = TICK_USAGE
	if(!pending_dirty_gas_mixtures)
#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
		// Tests drive Rust by hand, not through OM ticks: what the next frame would have delivered is delivered now.
		native_system().drain()
#endif
		pending_dirty_gas_mixtures = native_system().take_gas_changes() || list()
		pending_dirty_gas_index = 1
		gas_dirty_last = length(pending_dirty_gas_mixtures) / GAS_DEPENDENCY_OBSERVATION_STRIDE
		gas_woken_last = 0
		gas_dead_last = 0
	var/list/observations = pending_dirty_gas_mixtures
	while(pending_dirty_gas_index <= length(observations))
		var/record = pending_dirty_gas_index
		pending_dirty_gas_index += GAS_DEPENDENCY_OBSERVATION_STRIDE
		var/datum/native_watch/gas/W = kernel_native_native_watch_of(observations[record])
		if(!W)
			gas_dead_last++
			continue
		current_gas_wake_subscribers++
		// The owner reads the record from its mixture id on (index + 1).
		W.fire(list(observations[record + 1], observations[record + 2], observations, record + 1))
		if(budgeted && TICK_CHECK)
			current_gas_wake_scan_ms += TICK_DELTA_TO_MS(TICK_USAGE - scan_started)
			return FALSE
	pending_dirty_gas_mixtures = null
	pending_dirty_gas_index = 1
	current_gas_wake_scan_ms += TICK_DELTA_TO_MS(TICK_USAGE - scan_started)
	gas_wake_scan_last_ms = current_gas_wake_scan_ms
	gas_wake_subscribers_last = current_gas_wake_subscribers
	return TRUE
