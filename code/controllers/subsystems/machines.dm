#define SSMACHINES_MACHINERY     2
#define SSMACHINES_POWERNETS     3
#define SSMACHINES_POWER_OBJECTS 4

//
// SSmachines subsystem - Processing machines and the power step (M3: the
// power network itself runs in Rust, see code/modules/power/power_bridge.dm).
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
	var/cost_power_objects = 0
	/// Most recently completed logical stage costs (all resumed slices combined).
	var/last_cost_machinery = 0
	var/last_cost_powernets = 0
	var/last_cost_power_objects = 0
	/// In-flight logical stage accumulators. These deliberately survive yields.
	var/current_cost_machinery = 0
	var/current_cost_powernets = 0
	var/current_cost_power_objects = 0

	var/list/current_run = list()
	/// Machine gas transfers accumulated during one logical machinery generation.
	/// Rust commits this flat set under one publication lock after all devices have
	/// calculated their requested flow.
	var/list/pending_pump_transfers = list()
	/// Cost and cardinality of the last atomic pump commit. Kept separate from
	/// per-machine process timing because the commit happens after the roster.
	var/last_pump_commit_ms = 0
	/// Independent monotonic wall time and its excess over BYOND active time.
	/// This prevents an OS pause from being diagnosed as gas-transfer work.
	var/last_pump_commit_wall_ms = 0
	var/last_pump_commit_suspended_ms = 0
	var/last_pump_commit_operations = 0
	var/last_pump_commit_turfs = 0

	var/list/hibernating_vents = list()
	var/list/sleeping_gas_devices = list()
	/// Rust gas arena ID -> assoc list of weakrefs for sleeping gas-dependent devices.
	var/list/gas_mixture_subscribers = list()
	/// Material services are grouped separately so a harmless composition event
	/// can be rejected once per mixture instead of once per object on that turf.
	var/list/material_gas_subscribers = list()
	var/list/material_gas_subscriber_masks = list()
	var/list/material_gas_corrosion = list()
	/// Rust gas arena ID -> weakref reference -> dependency mask captured when the
	/// device went to sleep. This permits rejecting irrelevant semantic events
	/// before resolving a weakref or invoking a device-specific predicate.
	var/list/gas_mixture_subscriber_masks = list()
	/// Per mixture, one count for each semantic dependency bit. Maintaining these
	/// incrementally makes subscribe/unsubscribe O(number of bits), rather than
	/// rescanning every vent/firedoor sharing a large pipenet.
	var/list/gas_mixture_interest_counts = list()
	/// Last aggregate mask published to Rust. An explosion can remove hundreds of
	/// subscribers without crossing the FFI unless the actual aggregate changes.
	var/list/gas_mixture_watch_masks = list()
	/// Mixture key -> list(id, desired mask), coalesced while an explosion bulk
	/// transaction destroys many subscribers.
	var/list/pending_gas_watch_updates = list()
	/// Dirty-mixture notification batch retained while a Machines fire yields.
	var/list/pending_dirty_gas_mixtures
	var/pending_dirty_gas_index = 1
	/// Leak faces collapse to one network-owned transaction per dirty batch.
	var/list/pending_leak_network_wakes
	var/gas_wake_complete = TRUE
	var/gas_dirty_last = 0
	var/gas_woken_last = 0
	var/gas_dead_last = 0
	var/gas_wake_scan_last_ms = 0
	var/gas_wake_subscribers_last = 0
	var/current_gas_wake_scan_ms = 0
	var/current_gas_wake_subscribers = 0
	var/list/machine_noop_counts = list()

	/// Machines polled every pass. Order is not stable: removal swaps the last
	/// entry into the vacated slot (see stop_machine_processing()).
	var/list/processing_machines = list()
	/// Next processing_machines slot to visit in the current pass (walks down to 1).
	var/machine_run_cursor = 0
	/// Increments once per machinery pass; see /obj/machinery/var/machine_processing_pass.
	var/machine_run_pass = 1
	var/list/powerobjs = list()
	/// Enables low-overhead concrete-type timing for machine polling audits.
	// Concrete-type timing performs extra high-resolution clock reads inside the
	// hot machine loop. Enable it explicitly for benchmark runs; production keeps
	// the compact subsystem totals without paying continuous sampling overhead.
	var/profile_machine_types = FALSE
	/// Benchmark marker profiles capture one bounded window; leaving per-object
	/// high-resolution timing enabled permanently materially changes the workload.
	var/machine_profile_one_shot = FALSE
	/// Sampling phase advances once per completed processing-list generation. This
	/// prevents a stable machine list from aliasing against a fixed Nth-item sampler.
	var/machine_profile_sample_phase = 0
	var/machine_profile_run_index = 0
	var/machine_profile_sample_stride = 16
	var/list/machine_profile_cost = list()
	var/list/machine_profile_calls = list()
	var/list/machine_profile_kills = list()
	var/list/machine_profile_productive = list()
	/// Exact cost of deciding whether a dirty gas publication should wake each
	/// sleeping device. Kept separate from process() cost so dependency fan-out
	/// cannot masquerade as useful machine work.
	var/list/gas_predicate_profile_cost = list()
	var/list/gas_predicate_profile_calls = list()
	var/next_machine_profile_dump = 0
	/// log_runtime() may yield under heavy output. Prevent a resumed machinery
	/// fire from recursively starting another full dump before this one finishes.
	var/machine_profile_dumping = FALSE
	/// Diagnostic detail is bounded so profiling cannot itself create subsystem overruns.
	var/machine_profile_detail_limit = 8
	var/adaptive_profile_threshold_ms = 25

/datum/controller/subsystem/machines/Initialize()
	process_power()
	fire()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/machines/fire(resumed = 0)
	var/timer = TICK_USAGE
	// SSMACHINES_PIPENETS step removed; pipenets dispatch via SSair.
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_POWER_OBJECTS,FALSE,process_power_objects,cost_power_objects,last_cost_power_objects,current_cost_power_objects,SSMACHINES_MACHINERY) // Higher priority, damnit
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_MACHINERY,FALSE,process_machinery,cost_machinery,last_cost_machinery,current_cost_machinery,SSMACHINES_POWERNETS)
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_POWERNETS,FALSE,process_powernets,cost_powernets,last_cost_powernets,current_cost_powernets,SSMACHINES_POWER_OBJECTS)

// (Submap loads call /obj/machinery/atmospherics/atmos_init() directly,
//  main-map load runs through SSair.Initialize → setup_atmos_machinery.)

/datum/controller/subsystem/machines/stat_entry(msg)
	msg = "C:{"
	msg += "MC:[round(last_cost_machinery,1)]/[round(cost_machinery,1)]|"
	msg += "PN:[round(last_cost_powernets,1)]/[round(cost_powernets,1)]|"
	msg += "PO:[round(last_cost_power_objects,1)]/[round(cost_power_objects,1)]"
	msg += "} "
	msg += "MC:[length(SSmachines.processing_machines)]|"
	msg += "PN:[length(power_regions)] ev:[power_last_events][power_batch_depth ? " - BATCH" : ""]|"
	msg += "PO:[length(SSmachines.powerobjs)]|"
	msg += "HV:[length(SSmachines.hibernating_vents)]|"
	msg += "GD:[gas_dirty_last] GW:[gas_woken_last] GX:[gas_dead_last]|"
	msg += "MC/MS:[round((cost_machinery ? length(SSmachines.processing_machines)/cost_machinery : 0),0.1)]"
	return ..()

/datum/controller/subsystem/machines/proc/process_machinery(resumed = 0)
	if (!resumed)
		machine_run_pass++
		machine_run_cursor = length(processing_machines)
		machine_profile_run_index = 0
		gas_wake_complete = FALSE
		current_gas_wake_scan_ms = 0
		current_gas_wake_subscribers = 0
		if(profile_machine_types && !next_machine_profile_dump)
			next_machine_profile_dump = world.time + 2 MINUTES
	if(!gas_wake_complete)
		gas_wake_complete = wake_dirty_gas_subscribers()
		if(!gas_wake_complete)
			return

	var/wait = src.wait
	var/list/roster = processing_machines
	var/pass = machine_run_pass
	while(machine_run_cursor > 0)
		// Removals while we yielded can shrink the list below the cursor.
		if(machine_run_cursor > length(roster))
			machine_run_cursor = length(roster)
			continue
		var/obj/machinery/M = roster[machine_run_cursor]
		if(!istype(M))
			// Hard-deleted entry: swap the last slot in and look at this slot again.
			roster[machine_run_cursor] = roster[length(roster)]
			var/obj/machinery/moved = roster[machine_run_cursor]
			if(istype(moved))
				moved.machine_processing_index = machine_run_cursor
			roster.len--
			continue
		machine_run_cursor--
		if(M.machine_processing_pass == pass)
			continue
		M.machine_processing_pass = pass
		var/process_result
		if(!QDELETED(M))
			machine_profile_run_index++
			if(profile_machine_types && !((machine_profile_run_index + machine_profile_sample_phase) % machine_profile_sample_stride))
				var/machine_type = "[M.type]"
				var/profile_start = TICK_USAGE
				process_result = M.process(wait)
				machine_profile_cost[machine_type] += TICK_DELTA_TO_MS(TICK_USAGE - profile_start) * machine_profile_sample_stride
				machine_profile_calls[machine_type] += machine_profile_sample_stride
				if(istype(M, /obj/machinery/atmospherics))
					var/obj/machinery/atmospherics/atmos_machine = M
					if(abs(atmos_machine.last_flow_rate) > 0.001 || atmos_machine.last_power_draw > 0)
						machine_profile_productive[machine_type] += machine_profile_sample_stride
				if(process_result == PROCESS_KILL)
					machine_profile_kills[machine_type] += machine_profile_sample_stride
			else
				process_result = M.process(wait)
		if(QDELETED(M) || process_result == PROCESS_KILL)
			if(process_result == PROCESS_KILL)
				machine_noop_counts["[M.type]"]++
			stop_machine_processing(M)
		if(MC_TICK_CHECK)
			flush_pump_transfers()
			return
	flush_pump_transfers()
	if(profile_machine_types && world.time >= next_machine_profile_dump)
		dump_machine_profile()
	// Rotate the stratum only after the generation was actually exhausted; a
	// yielded/resumed fire keeps the same phase and never double-samples a slot.
	machine_profile_sample_phase = (machine_profile_sample_phase + 1) % machine_profile_sample_stride

/// Adds a machine to the polling roster. It is not polled until the next pass.
/datum/controller/subsystem/machines/proc/start_machine_processing(obj/machinery/M)
	if(M.datum_flags & DF_ISPROCESSING)
		return
	M.datum_flags |= DF_ISPROCESSING
	processing_machines += M
	M.machine_processing_index = length(processing_machines)
	M.machine_processing_pass = machine_run_pass

/// Removes a machine from the polling roster in O(1) by moving the last entry
/// into its slot. The pass walks down from the end, so the entry that moves is
/// either already polled or started mid-pass; its pass stamp stops a second poll.
/datum/controller/subsystem/machines/proc/stop_machine_processing(obj/machinery/M)
	if(!(M.datum_flags & DF_ISPROCESSING))
		return
	M.datum_flags &= ~DF_ISPROCESSING
	var/index = M.machine_processing_index
	M.machine_processing_index = 0
	var/last = length(processing_machines)
	// DF_ISPROCESSING is shared with other processing lists (SSfastprocess), so a
	// flagged machine is not necessarily on this roster.
	if(index < 1 || index > last || processing_machines[index] != M)
		return
	if(index != last)
		var/obj/machinery/moved = processing_machines[last]
		processing_machines[index] = moved
		moved.machine_processing_index = index
	processing_machines.len--

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

/datum/controller/subsystem/machines/proc/dump_machine_profile()
	if(machine_profile_dumping)
		return
	machine_profile_dumping = TRUE
	// Advance the deadline before producing output. Some logger backends yield;
	// setting this at the end allowed every resumed machinery fire to enter again.
	next_machine_profile_dump = world.time + 2 MINUTES
	var/list/current_counts = list()
	var/airlocks_processing = 0
	var/airlocks_autoclose = 0
	var/airlocks_commanded = 0
	var/airlocks_power_wait = 0
	var/airlocks_electrified = 0
	var/airlocks_other = 0
	var/list/leaking_pipes = list()
	var/list/active_vents = list()
	var/list/active_lights = list()
	for(var/obj/machinery/M as anything in processing_machines)
		if(M && !QDELETED(M))
			current_counts["[M.type]"]++
			if(istype(M, /obj/machinery/door/airlock))
				var/obj/machinery/door/airlock/A = M
				airlocks_processing++
				if(A.close_door_at)
					airlocks_autoclose++
				else if(A.cur_command)
					airlocks_commanded++
				else if(A.main_power_lost_until > 0 || A.backup_power_lost_until > 0)
					airlocks_power_wait++
				else if(A.electrified_until > 0)
					airlocks_electrified++
				else
					airlocks_other++
			if(istype(M, /obj/machinery/atmospherics/pipe))
				var/obj/machinery/atmospherics/pipe/P = M
				if(P.leaking)
					leaking_pipes += P
			if(istype(M, /obj/machinery/atmospherics/unary/vent_pump))
				active_vents += M
			if(istype(M, /obj/machinery/light))
				active_lights += M
	var/list/sorted_cost = machine_profile_cost.Copy()
	sortTim(sorted_cost, /proc/cmp_numeric_desc, TRUE)
	var/rank = 0
	for(var/machine_type in sorted_cost)
		log_runtime("MACHINE_PROFILE type=[machine_type] cost_ms=[round(machine_profile_cost[machine_type], 0.01)] calls=[machine_profile_calls[machine_type]] productive=[machine_profile_productive[machine_type] || 0] active=[current_counts[machine_type] || 0] killed=[machine_profile_kills[machine_type] || 0]")
		if(++rank >= 25)
			break
	var/list/sorted_counts = current_counts.Copy()
	sortTim(sorted_counts, /proc/cmp_numeric_desc, TRUE)
	rank = 0
	for(var/machine_type in sorted_counts)
		log_runtime("MACHINE_PROFILE_ACTIVE type=[machine_type] active=[current_counts[machine_type]]")
		if(++rank >= 50)
			break
	log_runtime("MACHINE_PROFILE_SUMMARY active=[length(processing_machines)] concrete_types=[length(current_counts)]")
	log_runtime("MACHINE_PROFILE_POWER regions=[length(power_regions)] events=[power_last_events] edits_sent=[power_edits_sent]")
	var/list/sorted_predicates = gas_predicate_profile_cost.Copy()
	sortTim(sorted_predicates, /proc/cmp_numeric_desc, TRUE)
	rank = 0
	for(var/machine_type in sorted_predicates)
		log_runtime("MACHINE_PROFILE_GAS_PREDICATE type=[machine_type] cost_ms=[round(gas_predicate_profile_cost[machine_type], 0.01)] calls=[gas_predicate_profile_calls[machine_type]]")
		if(++rank >= 20)
			break
	log_runtime("MACHINE_PROFILE_DETAIL airlocks processing=[airlocks_processing] autoclose=[airlocks_autoclose] commanded=[airlocks_commanded] power_wait=[airlocks_power_wait] electrified=[airlocks_electrified] other=[airlocks_other]")
	var/leaks_logged = 0
	for(var/obj/machinery/atmospherics/pipe/P as anything in leaking_pipes)
		if(leaks_logged++ >= machine_profile_detail_limit)
			break
		var/connected_nodes = 0
		for(var/obj/machinery/atmospherics/node as anything in P.get_neighbor_nodes_for_init())
			if(node)
				connected_nodes++
		log_runtime("MACHINE_PROFILE_LEAK type=[P.type] x=[P.x] y=[P.y] z=[P.z] area=[get_area(P)] nodes=[connected_nodes] damaged=[P.damaged_leak]")
	if(length(leaking_pipes) > machine_profile_detail_limit)
		log_runtime("MACHINE_PROFILE_LEAK_SUMMARY total=[length(leaking_pipes)] detailed=[machine_profile_detail_limit]")
	var/vents_logged = 0
	for(var/obj/machinery/atmospherics/unary/vent_pump/V as anything in active_vents)
		if(vents_logged++ >= machine_profile_detail_limit)
			break
		var/datum/gas_mixture/environment = V.return_air()
		var/datum/gas_mixture/source = V.pump_direction ? V.air_contents : environment
		log_runtime("MACHINE_PROFILE_VENT type=[V.type] x=[V.x] y=[V.y] z=[V.z] area=[get_area(V)] direction=[V.pump_direction] environment_kpa=[round(environment ? environment.return_pressure() : 0, 0.01)] pipe_kpa=[round(V.air_contents.return_pressure(), 0.01)] delta_kpa=[round(environment ? V.get_pressure_delta(environment) : 0, 0.01)] source_moles=[round(source ? source.total_moles() : 0, 0.01)]")
	var/lights_logged = 0
	for(var/obj/machinery/light/L as anything in active_lights)
		if(lights_logged++ >= machine_profile_detail_limit)
			break
		log_runtime("MACHINE_PROFILE_LIGHT type=[L.type] x=[L.x] y=[L.y] z=[L.z] area=[get_area(L)] powered=[L.has_power()] emergency=[L.emergency_mode] auto_flicker=[L.auto_flicker] flickering=[L.flickering] cell=[L.cell ? round(L.cell.charge, 0.01) : -1]/[L.cell ? L.cell.maxcharge : -1]")
	var/apcs_logged = 0
	for(var/obj/machinery/power/apc/A in processing_machines)
		if(apcs_logged++ >= machine_profile_detail_limit)
			break
		log_runtime("MACHINE_PROFILE_APC x=[A.x] y=[A.y] z=[A.z] area=[get_area(A)] status=[A.stat] failure_remaining=[max(A.failure_until - world.time, 0)] cell=[A.cell ? round(A.cell.charge, 0.01) : -1]/[A.cell ? A.cell.maxcharge : -1] operating=[A.operating] shorted=[A.shorted] chargemode=[A.chargemode]")
	// These are associative-only tables. Cut() is unreliable for clearing tables
	// without a numeric sequence, which made every supposedly bounded profile
	// window retain costs from round start. Replace the tables so checkpoints are
	// genuinely independent samples.
	machine_profile_cost = list()
	machine_profile_calls = list()
	machine_profile_kills = list()
	machine_profile_productive = list()
	gas_predicate_profile_cost = list()
	gas_predicate_profile_calls = list()
	machine_noop_counts = list()
	machine_profile_dumping = FALSE
	if(machine_profile_one_shot)
		profile_machine_types = FALSE
		machine_profile_one_shot = FALSE

/datum/controller/subsystem/machines/proc/request_adaptive_profile()
	if(profile_machine_types || last_cost_machinery < adaptive_profile_threshold_ms)
		return
	profile_machine_types = TRUE
	machine_profile_one_shot = TRUE
	next_machine_profile_dump = world.time + 10 SECONDS

/// The power step: one Rust call for every network, APC and SMES.
/datum/controller/subsystem/machines/proc/process_powernets(resumed = 0)
	process_power()

// Actually only processes power DRAIN objects.
// Currently only used by powersinks. These items get priority processed before machinery
/datum/controller/subsystem/machines/proc/process_power_objects(resumed = 0)
	if (!resumed)
		src.current_run = powerobjs.Copy()

	var/wait = src.wait
	var/list/current_run = src.current_run
	while(length(current_run))
		var/obj/item/I = current_run[length(current_run)]
		current_run.len--
		if(!I || (I.pwr_drain(wait) == PROCESS_KILL))
			powerobjs.Remove(I)
			DISABLE_BITFIELD(I?.datum_flags, DF_ISPROCESSING)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/machines/Recover()
	var/list/recovered_machines = list()
	for(var/datum/D as anything in SSmachines.processing_machines)
		if(!istype(D, /obj/machinery))
			log_world("## ERROR Found wrong type during SSmachinery recovery: list=SSmachines.machines, item=[D], type=[D?.type]")
			continue
		var/obj/machinery/M = D
		recovered_machines += M
		M.machine_processing_index = length(recovered_machines)
	SSmachines.processing_machines = recovered_machines
	for(var/datum/D as anything in SSmachines.powerobjs)
		if(!istype(D, /obj/item))
			log_world("## ERROR Found wrong type during SSmachinery recovery: list=SSmachines.powerobjs, item=[D], type=[D?.type]")
			SSmachines.powerobjs -= D

	processing_machines = SSmachines.processing_machines
	power_ops = SSmachines.power_ops
	power_regions = SSmachines.power_regions
	power_dirty_areas = SSmachines.power_dirty_areas
	power_material_cables = SSmachines.power_material_cables
	powerobjs = SSmachines.powerobjs
	current_run = SSmachines.current_run
	pending_pump_transfers = SSmachines.pending_pump_transfers
	hibernating_vents = SSmachines.hibernating_vents
	sleeping_gas_devices = SSmachines.sleeping_gas_devices
	gas_mixture_subscribers = SSmachines.gas_mixture_subscribers
	gas_mixture_subscriber_masks = SSmachines.gas_mixture_subscriber_masks
	gas_mixture_interest_counts = SSmachines.gas_mixture_interest_counts
	material_gas_subscribers = SSmachines.material_gas_subscribers
	material_gas_subscriber_masks = SSmachines.material_gas_subscriber_masks
	material_gas_corrosion = SSmachines.material_gas_corrosion
	gas_mixture_watch_masks = SSmachines.gas_mixture_watch_masks
	pending_gas_watch_updates = SSmachines.pending_gas_watch_updates
	pending_dirty_gas_mixtures = SSmachines.pending_dirty_gas_mixtures
	pending_dirty_gas_index = SSmachines.pending_dirty_gas_index
	gas_wake_complete = SSmachines.gas_wake_complete

/datum/controller/subsystem/machines/proc/wake_dirty_gas_subscribers()
	var/scan_started = TICK_USAGE
	if(!pending_dirty_gas_mixtures)
		pending_dirty_gas_mixtures = vg_drain_dirty_gas_observations()
		pending_dirty_gas_index = 1
		pending_leak_network_wakes = list()
		gas_dirty_last = length(pending_dirty_gas_mixtures) / GAS_DEPENDENCY_OBSERVATION_STRIDE
		gas_woken_last = 0
		gas_dead_last = 0
	while(pending_dirty_gas_index <= length(pending_dirty_gas_mixtures))
		var/observation_index = pending_dirty_gas_index
		var/mixture_id = pending_dirty_gas_mixtures[pending_dirty_gas_index]
		var/change_mask = pending_dirty_gas_mixtures[pending_dirty_gas_index + 1]
		pending_dirty_gas_index += GAS_DEPENDENCY_OBSERVATION_STRIDE
		var/list/subscribers = gas_mixture_subscribers["[mixture_id]"]
		if(length(subscribers))
			var/list/subscriber_masks = gas_mixture_subscriber_masks["[mixture_id]"]
			var/list/to_wake
			for(var/key in subscribers)
				if(!((subscriber_masks?[key] || GAS_DEPENDENCY_ALL) & change_mask))
					continue
				current_gas_wake_subscribers++
				var/datum/weakref/WR = subscribers[key]
				var/datum/observed = WR?.resolve()
				if(istype(observed, /datum/material_service))
					var/datum/material_service/service = observed
					if(!service.timer && service.gas_dependency_changed(mixture_id, change_mask, pending_dirty_gas_mixtures, observation_index))
						service.environment_changed(FALSE)
					continue
				if(!sleeping_gas_devices[WR?.reference])
					continue
				var/obj/machinery/subscriber = WR?.resolve()
				if(!subscriber)
					gas_dead_last++
					LAZYADD(to_wake, WR)
				else if(istype(subscriber, /obj/machinery/atmospherics/pipe))
					var/obj/machinery/atmospherics/pipe/leaking_pipe = subscriber
					// Rust already filtered this to a material change in one of the
					// two subscribed mixtures. The network's atomic batch computes
					// the residual for all faces together; repeating pressure,
					// temperature, and per-gas FFI reads for every pipe here is both
					// redundant and the dominant post-explosion machine cost.
					if(leaking_pipe.leaking && leaking_pipe.parent?.network)
						pending_leak_network_wakes[leaking_pipe.parent.network] = TRUE
					else if(leaking_pipe.leaking)
						LAZYADD(to_wake, WR)
				else if(profile_machine_types)
					var/machine_type = "[subscriber.type]"
					var/predicate_started = TICK_USAGE
					var/should_wake = subscriber.gas_dependency_changed(mixture_id, change_mask, pending_dirty_gas_mixtures, observation_index)
					gas_predicate_profile_cost[machine_type] += TICK_DELTA_TO_MS(TICK_USAGE - predicate_started)
					gas_predicate_profile_calls[machine_type]++
					if(should_wake)
						LAZYADD(to_wake, WR)
				else if(subscriber.gas_dependency_changed(mixture_id, change_mask, pending_dirty_gas_mixtures, observation_index))
					LAZYADD(to_wake, WR)
			for(var/datum/weakref/WR as anything in to_wake)
				gas_woken_last++
				wake_gas_subscriber(WR, "gas:[mixture_id]:[change_mask]")
		var/list/material_subscribers = material_gas_subscribers["[mixture_id]"]
		if(length(material_subscribers))
			var/material_change_mask = change_mask
			if(material_change_mask & GAS_DEPENDENCY_COMPOSITION)
				var/temperature = pending_dirty_gas_mixtures[observation_index + 4]
				var/volume = max(pending_dirty_gas_mixtures[observation_index + 5], 1)
				var/corrosive_moles = pending_dirty_gas_mixtures[observation_index + 8] * 0.03 + pending_dirty_gas_mixtures[observation_index + 12] * 0.01 + pending_dirty_gas_mixtures[observation_index + 13] * 0.1
				if(temperature >= 500)
					corrosive_moles += pending_dirty_gas_mixtures[observation_index + 6] * 0.02
				var/new_corrosion = corrosive_moles * R_IDEAL_GAS_EQUATION * temperature / volume / ONE_ATMOSPHERE * max(0.25, 1 + (temperature - T20C) / 600)
				var/old_corrosion = material_gas_corrosion["[mixture_id]"] || 0
				material_gas_corrosion["[mixture_id]"] = new_corrosion
				if(abs(new_corrosion - old_corrosion) <= 0.000001)
					material_change_mask &= ~GAS_DEPENDENCY_COMPOSITION
			if(material_change_mask)
				for(var/key in material_subscribers)
					var/datum/weakref/material_ref = material_subscribers[key]
					var/datum/material_service/service = material_ref?.resolve()
					if(!service || !(service.gas_dependency_interest_mask() & material_change_mask))
						continue
					current_gas_wake_subscribers++
					if(service.gas_dependency_changed(mixture_id, material_change_mask, pending_dirty_gas_mixtures, observation_index))
						service.environment_changed(FALSE)
		if(MC_TICK_CHECK)
			current_gas_wake_scan_ms += TICK_DELTA_TO_MS(TICK_USAGE - scan_started)
			return FALSE
	pending_dirty_gas_mixtures = null
	pending_dirty_gas_index = 1
	for(var/datum/pipe_network/network as anything in pending_leak_network_wakes)
		if(network && !QDELETED(network))
			network.mark_leak_dirty()
	pending_leak_network_wakes = null
	current_gas_wake_scan_ms += TICK_DELTA_TO_MS(TICK_USAGE - scan_started)
	gas_wake_scan_last_ms = current_gas_wake_scan_ms
	gas_wake_subscribers_last = current_gas_wake_subscribers
	return TRUE

/datum/controller/subsystem/machines/proc/subscribe_gas_dependency(mixture_id, datum/weakref/WR)
	if(isnull(mixture_id) || !WR)
		return
	var/key = "[mixture_id]"
	var/datum/subscriber = WR.resolve()
	if(istype(subscriber, /datum/material_service))
		var/datum/material_service/service = subscriber
		var/list/material_subscribers = material_gas_subscribers[key]
		if(!material_subscribers)
			material_subscribers = list()
			material_gas_subscribers[key] = material_subscribers
		if(material_subscribers[WR.reference])
			return
		var/material_mask = service.gas_dependency_interest_mask()
		material_subscribers[WR.reference] = WR
		var/list/material_masks = material_gas_subscriber_masks[key]
		if(!material_masks)
			material_masks = list()
			material_gas_subscriber_masks[key] = material_masks
		material_masks[WR.reference] = material_mask
		adjust_gas_interest_counts(key, NONE, material_mask)
		refresh_gas_watch_mask(mixture_id)
		return
	var/list/subscribers = gas_mixture_subscribers[key]
	if(!subscribers)
		subscribers = list()
		gas_mixture_subscribers[key] = subscribers
	var/list/subscriber_masks = gas_mixture_subscriber_masks[key]
	if(!subscriber_masks)
		subscriber_masks = list()
		gas_mixture_subscriber_masks[key] = subscriber_masks
	var/old_mask = subscriber_masks[WR.reference] || NONE
	var/new_mask = GAS_DEPENDENCY_ALL
	if(istype(subscriber, /obj/machinery))
		var/obj/machinery/machine = subscriber
		new_mask = machine.gas_dependency_interest_mask()
	subscribers[WR.reference] = WR
	subscriber_masks[WR.reference] = new_mask
	adjust_gas_interest_counts(key, old_mask, new_mask)
	refresh_gas_watch_mask(mixture_id)

/datum/controller/subsystem/machines/proc/gas_dependency_bits()
	var/static/list/bits = list(GAS_DEPENDENCY_PRESSURE, GAS_DEPENDENCY_TEMPERATURE, GAS_DEPENDENCY_COMPOSITION)
	return bits

/datum/controller/subsystem/machines/proc/adjust_gas_interest_counts(key, old_mask, new_mask)
	var/list/counts = gas_mixture_interest_counts[key]
	if(!counts)
		counts = list()
		gas_mixture_interest_counts[key] = counts
	for(var/bit in gas_dependency_bits())
		var/old_has_bit = old_mask & bit
		var/new_has_bit = new_mask & bit
		if(old_has_bit == new_has_bit)
			continue
		var/bit_key = "[bit]"
		counts[bit_key] = max((counts[bit_key] || 0) + (new_has_bit ? 1 : -1), 0)

/datum/controller/subsystem/machines/proc/refresh_gas_watch_mask(mixture_id)
	var/key = "[mixture_id]"
	var/aggregate_mask = NONE
	var/list/counts = gas_mixture_interest_counts[key]
	for(var/bit in gas_dependency_bits())
		if(counts?["[bit]"] > 0)
			aggregate_mask |= bit
	if(SSexplosions?.is_bulk_resolving())
		pending_gas_watch_updates[key] = list(mixture_id, aggregate_mask)
		return
	publish_gas_watch_mask(mixture_id, aggregate_mask)

/datum/controller/subsystem/machines/proc/publish_gas_watch_mask(mixture_id, aggregate_mask)
	var/key = "[mixture_id]"
	var/old_aggregate = gas_mixture_watch_masks[key] || NONE
	if(aggregate_mask == old_aggregate)
		return
	if(aggregate_mask)
		gas_mixture_watch_masks[key] = aggregate_mask
		watch_dirty_gas_mixture(mixture_id, aggregate_mask)
	else
		gas_mixture_watch_masks.Remove(key)
		vg_unwatch_dirty_gas_mixture(mixture_id)

/datum/controller/subsystem/machines/proc/flush_gas_watch_updates()
	if(!length(pending_gas_watch_updates))
		return
	var/list/updates = pending_gas_watch_updates
	pending_gas_watch_updates = list()
	for(var/key in updates)
		var/list/update = updates[key]
		publish_gas_watch_mask(update[1], update[2])

/datum/controller/subsystem/machines/proc/unsubscribe_gas_dependency(mixture_id, datum/weakref/WR)
	if(isnull(mixture_id) || !WR)
		return
	var/key = "[mixture_id]"
	var/list/material_subscribers = material_gas_subscribers[key]
	if(material_subscribers?[WR.reference])
		var/list/material_masks = material_gas_subscriber_masks[key]
		var/old_material_mask = material_masks?[WR.reference] || NONE
		material_subscribers.Remove(WR.reference)
		material_masks?.Remove(WR.reference)
		adjust_gas_interest_counts(key, old_material_mask, NONE)
		if(!length(material_subscribers))
			material_gas_subscribers.Remove(key)
			material_gas_subscriber_masks.Remove(key)
			material_gas_corrosion.Remove(key)
		if(!length(material_subscribers) && !length(gas_mixture_subscribers[key]))
			gas_mixture_interest_counts.Remove(key)
		refresh_gas_watch_mask(mixture_id)
		return
	var/list/subscribers = gas_mixture_subscribers[key]
	if(!subscribers)
		return
	subscribers.Remove(WR.reference)
	var/list/subscriber_masks = gas_mixture_subscriber_masks[key]
	var/old_mask = subscriber_masks?[WR.reference] || NONE
	subscriber_masks?.Remove(WR.reference)
	adjust_gas_interest_counts(key, old_mask, NONE)
	if(!length(subscribers))
		gas_mixture_subscribers.Remove(key)
		gas_mixture_subscriber_masks.Remove(key)
		if(!length(material_gas_subscribers[key]))
			gas_mixture_interest_counts.Remove(key)
	refresh_gas_watch_mask(mixture_id)

/datum/controller/subsystem/machines/proc/hibernate_vent(obj/machinery/atmospherics/unary/V)
	if(!V)
		return
	var/datum/weakref/WR = WEAKREF(V)
	if(!WR)
		return
	hibernating_vents[WR.reference] = WR
	sleeping_gas_devices[WR.reference] = WR
	V.register_gas_dependencies(WR)
	STOP_MACHINE_PROCESSING(V)

/datum/controller/subsystem/machines/proc/hibernate_heat_pipe(obj/machinery/atmospherics/pipe/simple/heat_exchanging/P)
	if(!P)
		return
	var/datum/weakref/WR = WEAKREF(P)
	if(!WR)
		return
	sleeping_gas_devices[WR.reference] = WR
	P.register_gas_dependencies(WR)
	STOP_MACHINE_PROCESSING(P)

/datum/controller/subsystem/machines/proc/hibernate_air_alarm(obj/machinery/alarm/A, subscribe = TRUE)
	if(!A)
		return
	var/datum/weakref/WR = WEAKREF(A)
	if(subscribe)
		sleeping_gas_devices[WR.reference] = WR
		A.register_gas_dependencies(WR)
	else
		A.unregister_gas_dependencies(WR)
		sleeping_gas_devices.Remove(WR.reference)
	STOP_MACHINE_PROCESSING(A)

/datum/controller/subsystem/machines/proc/hibernate_air_sensor(obj/machinery/air_sensor/S)
	if(!S)
		return
	var/datum/weakref/WR = WEAKREF(S)
	sleeping_gas_devices[WR.reference] = WR
	S.register_gas_dependencies(WR)
	STOP_MACHINE_PROCESSING(S)

/datum/controller/subsystem/machines/proc/hibernate_airlock_sensor(obj/machinery/airlock_sensor/S)
	if(!S)
		return
	var/datum/weakref/WR = WEAKREF(S)
	sleeping_gas_devices[WR.reference] = WR
	S.register_gas_dependencies(WR)
	STOP_MACHINE_PROCESSING(S)

/datum/controller/subsystem/machines/proc/hibernate_meter(obj/machinery/meter/M)
	if(!M)
		return
	var/datum/weakref/WR = WEAKREF(M)
	sleeping_gas_devices[WR.reference] = WR
	M.register_gas_dependency(WR)
	STOP_MACHINE_PROCESSING(M)

/datum/controller/subsystem/machines/proc/hibernate_generator(obj/machinery/power/generator/G)
	if(!G)
		return
	var/datum/weakref/WR = WEAKREF(G)
	sleeping_gas_devices[WR.reference] = WR
	G.register_gas_dependencies(WR)
	STOP_MACHINE_PROCESSING(G)

/datum/controller/subsystem/machines/proc/wake_vent(datum/weakref/WR)
	wake_gas_subscriber(WR)

/datum/controller/subsystem/machines/proc/wake_gas_subscriber(datum/weakref/WR, reason = "gas")
	if(!WR)
		return
	if(WR.reference && !sleeping_gas_devices[WR.reference])
		return
	var/atom/subscriber = WR.resolve()
	if(istype(subscriber, /obj/machinery))
		var/obj/machinery/woken_machine = subscriber
		woken_machine.gas_dependency_wake_count++
	if(istype(subscriber, /obj/machinery/atmospherics/unary))
		var/obj/machinery/atmospherics/unary/V = subscriber
		// Unary devices usually settle again in one fire. Keep their arena
		// watches across that short active interval. Hibernation replaces a watch
		// if topology changed; Destroy() removes both permanently.
		START_MACHINE_PROCESSING(V)
	else if(istype(subscriber, /obj/machinery/atmospherics/pipe/simple/heat_exchanging))
		var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/P = subscriber
		P.unregister_gas_dependencies(WR)
		P.stable_temperature_cycles = 0
		START_MACHINE_PROCESSING(P)
	else if(istype(subscriber, /obj/machinery/atmospherics/pipe))
		var/obj/machinery/atmospherics/pipe/P = subscriber
		// Exposed pipe faces are network-owned transactions. Route the semantic
		// wake straight to that transaction instead of enrolling each pipe in the
		// generic machine roster merely to call mark_leak_dirty() and kill itself.
		if(P.leaking && P.parent?.network)
			P.parent.network.mark_leak_dirty()
			return
		P.clear_leak_gas_dependencies()
		START_MACHINE_PROCESSING(P)
	else if(istype(subscriber, /obj/machinery/alarm))
		var/obj/machinery/alarm/A = subscriber
		// Dependency registrations describe topology, not scheduler state. Keep
		// them while the device performs its one active pass; sleeping_gas_devices
		// gates delivery, and hibernation refreshes its revision/signature. This
		// avoids two arena FFI calls for every harmless pressure notification.
		START_MACHINE_PROCESSING(A)
	else if(istype(subscriber, /obj/machinery/air_sensor))
		var/obj/machinery/air_sensor/S = subscriber
		START_MACHINE_PROCESSING(S)
	else if(istype(subscriber, /obj/machinery/airlock_sensor))
		var/obj/machinery/airlock_sensor/S = subscriber
		START_MACHINE_PROCESSING(S)
	else if(istype(subscriber, /obj/machinery/door/firedoor))
		var/obj/machinery/door/firedoor/F = subscriber
		START_MACHINE_PROCESSING(F)
	else if(istype(subscriber, /obj/machinery/meter))
		var/obj/machinery/meter/M = subscriber
		START_MACHINE_PROCESSING(M)
	else if(istype(subscriber, /obj/machinery/atmospherics/portables_connector))
		var/obj/machinery/atmospherics/portables_connector/C = subscriber
		C.clear_gas_dependency()
		START_MACHINE_PROCESSING(C)
	else if(istype(subscriber, /obj/machinery/portable_atmospherics))
		var/obj/machinery/portable_atmospherics/P = subscriber
		P.clear_gas_dependency()
		START_MACHINE_PROCESSING(P)
	else if(istype(subscriber, /obj/machinery/atmospherics/binary/dp_vent_pump))
		var/obj/machinery/atmospherics/binary/dp_vent_pump/V = subscriber
		V.clear_gas_dependencies()
		START_MACHINE_PROCESSING(V)
	else if(istype(subscriber, /obj/machinery/disposal))
		var/obj/machinery/disposal/D = subscriber
		D.clear_gas_dependency()
		START_MACHINE_PROCESSING(D)
	else if(istype(subscriber, /obj/machinery/power/thermoregulator))
		var/obj/machinery/power/thermoregulator/T = subscriber
		T.clear_gas_dependency()
		START_MACHINE_PROCESSING(T)
	else if(istype(subscriber, /obj/machinery/power/generator))
		var/obj/machinery/power/generator/G = subscriber
		G.clear_gas_dependencies(WR)
		START_MACHINE_PROCESSING(G)
	if(WR.reference)
		sleeping_gas_devices.Remove(WR.reference)
		hibernating_vents[WR.reference] = null
		hibernating_vents.Remove(WR.reference)

#undef SSMACHINES_MACHINERY
#undef SSMACHINES_POWERNETS
#undef SSMACHINES_POWER_OBJECTS
