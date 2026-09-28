#define SSMACHINES_MACHINERY     2
#define SSMACHINES_POWERNETS     3

//
// SSmachines subsystem - gas wakes, the batched pump commit and the power step (M3: the power
// network itself runs in Rust, see code/modules/power/power_bridge.dm). It no longer polls
// machines: their DM work runs on the machine pipeline (code/game/machinery/machine_pipeline.dm),
// woken by MACHINE_WAKE(), their channels and their watches (roadmap S5).
// (Pipenets moved to SSair under the LINDA migration.)
//

SUBSYSTEM_DEF(machines)
	name = "Machines"
	dependencies = list(
		/datum/controller/subsystem/points_of_interest
	)
	priority = FIRE_PRIORITY_MACHINES
	flags = SS_KEEP_TIMING
	runlevels = RUNLEVEL_GAME|RUNLEVEL_POSTGAME

	var/current_step = SSMACHINES_MACHINERY

	var/cost_machinery     = 0
	var/cost_powernets     = 0
	/// Most recently completed logical stage costs (all resumed slices combined).
	var/last_cost_machinery = 0
	var/last_cost_powernets = 0
	/// In-flight logical stage accumulators. These deliberately survive yields.
	var/current_cost_machinery = 0
	var/current_cost_powernets = 0

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

	/// Dirty-mixture notification batch retained while a Machines fire yields.
	/// Gas dependency observations (vg_drain_dirty_gas_observations()) retained while a Machines fire yields.
	var/list/pending_dirty_gas_mixtures
	var/pending_dirty_gas_index = 1
	var/gas_wake_complete = TRUE
	var/gas_dirty_last = 0
	var/gas_woken_last = 0
	var/gas_dead_last = 0
	var/gas_wake_scan_last_ms = 0
	var/gas_wake_subscribers_last = 0
	var/current_gas_wake_scan_ms = 0
	var/current_gas_wake_subscribers = 0

/datum/controller/subsystem/machines/Initialize()
	process_power()
	fire()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/machines/fire(resumed = 0)
	var/timer = TICK_USAGE
	// SSMACHINES_PIPENETS step removed; pipenets dispatch via SSair.
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_MACHINERY,TRUE,process_machinery,cost_machinery,last_cost_machinery,current_cost_machinery,SSMACHINES_POWERNETS)
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_POWERNETS,FALSE,process_powernets,cost_powernets,last_cost_powernets,current_cost_powernets,SSMACHINES_MACHINERY)

// (Submap loads call /obj/machinery/atmospherics/atmos_init() directly,
//  main-map load runs through SSair.Initialize -> setup_atmos_machinery.)

/datum/controller/subsystem/machines/stat_entry(msg)
	msg = "C:{"
	msg += "MC:[round(last_cost_machinery,1)]/[round(cost_machinery,1)]|"
	msg += "PN:[round(last_cost_powernets,1)]/[round(cost_powernets,1)]"
	msg += "} "
	msg += "MP:[om_pipeline_parked_count(/datum/om/pipeline/machine)] parked|"
	msg += "PN:[length(power_regions)]|"
	msg += "GD:[gas_dirty_last] GW:[gas_woken_last] GX:[gas_dead_last]"
	return ..()

/// Gas watches, then the pump transfers the pipeline devices queued since the last commit.
/datum/controller/subsystem/machines/proc/process_machinery(resumed = 0)
	if (!resumed)
		gas_wake_complete = FALSE
		current_gas_wake_scan_ms = 0
		current_gas_wake_subscribers = 0
	if(!gas_wake_complete)
		gas_wake_complete = wake_dirty_gas_subscribers()
		if(!gas_wake_complete)
			return
	flush_pump_transfers()

/datum/controller/subsystem/machines/proc/queue_pump_transfer(obj/machinery/atmospherics/M, datum/gas_mixture/source, datum/gas_mixture/sink, requested_moles, specific_power, source_moles, source_volume)
	if(!M || !source || !sink || requested_moles <= 0)
		return FALSE
	pending_pump_transfers += list(list(M, source, sink, requested_moles, specific_power, source_moles, source_volume))
	return TRUE

/datum/controller/subsystem/machines/proc/flush_pump_transfers()
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
		if(istype(M, /obj/machinery/atmospherics/unary))
			var/obj/machinery/atmospherics/unary/U = M
			U.network?.mark_dirty()
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

/// The power step: one Rust call for every network, APC and SMES.
/datum/controller/subsystem/machines/proc/process_powernets(resumed = 0)
	process_power()

/datum/controller/subsystem/machines/Recover()
	power_regions = SSmachines.power_regions
	power_dirty_areas = SSmachines.power_dirty_areas
	power_material_cables = SSmachines.power_material_cables
	pending_pump_transfers = SSmachines.pending_pump_transfers
	pending_dirty_gas_mixtures = SSmachines.pending_dirty_gas_mixtures
	pending_dirty_gas_index = SSmachines.pending_dirty_gas_index
	gas_wake_complete = SSmachines.gas_wake_complete

/// Hands this batch of gas dependency observations to their native watches
/// (/datum/native_watch/gas, code/datums/om/native.dm). The OM watch layer owns one
/// native watch per watched mixture (code/datums/om/watch.dm), which fans the record
/// out to every om_watch armed on that mixture (om_watch_dispatch_gas()).
/datum/controller/subsystem/machines/proc/wake_dirty_gas_subscribers()
	var/scan_started = TICK_USAGE
	if(!pending_dirty_gas_mixtures)
		pending_dirty_gas_mixtures = vg_drain_dirty_gas_observations()
		pending_dirty_gas_index = 1
		gas_dirty_last = length(pending_dirty_gas_mixtures) / GAS_DEPENDENCY_OBSERVATION_STRIDE
		gas_woken_last = 0
		gas_dead_last = 0
	var/list/observations = pending_dirty_gas_mixtures
	while(pending_dirty_gas_index <= length(observations))
		var/record = pending_dirty_gas_index
		pending_dirty_gas_index += GAS_DEPENDENCY_OBSERVATION_STRIDE
		var/datum/native_watch/gas/W = om_native_watch_of(observations[record])
		if(!W)
			gas_dead_last++
			continue
		current_gas_wake_subscribers++
		// The owner reads the record from its mixture id on (index + 1).
		W.fire(list(observations[record + 1], observations[record + 2], observations, record + 1))
		if(MC_TICK_CHECK)
			current_gas_wake_scan_ms += TICK_DELTA_TO_MS(TICK_USAGE - scan_started)
			return FALSE
	pending_dirty_gas_mixtures = null
	pending_dirty_gas_index = 1
	current_gas_wake_scan_ms += TICK_DELTA_TO_MS(TICK_USAGE - scan_started)
	gas_wake_scan_last_ms = current_gas_wake_scan_ms
	gas_wake_subscribers_last = current_gas_wake_subscribers
	return TRUE

/// Wakes any /obj/machinery hibernating on a gas watch (an atom-agnostic force-wake, used by
/// invalidate_gas_dependencies()-style callers whose device might not even be asleep, and by
/// tests): if it has no watch armed it's already running and this is a no-op.
/proc/om_watch_invalidate(datum/entity) // ALLOW(base_proc): global API written before the base-type ratchet
	om_watch_fire_all(entity)

/datum/controller/subsystem/machines/proc/hibernate_airlock_sensor(obj/machinery/airlock_sensor/S)
	if(!S)
		return
	S.register_gas_dependencies()
	MACHINE_SLEEP(S)

/datum/controller/subsystem/machines/proc/hibernate_generator(obj/machinery/power/generator/G)
	if(!G)
		return
	G.register_gas_dependencies()
	MACHINE_SLEEP(G)

#undef SSMACHINES_MACHINERY
#undef SSMACHINES_POWERNETS
