#define SSMACHINES_MACHINERY     2
#define SSMACHINES_POWERNETS     3
#define SSMACHINES_POWER_OBJECTS 4

//
// SSmachines subsystem - Processing machines and powernets.
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
	var/last_pump_commit_operations = 0
	var/last_pump_commit_turfs = 0

	var/list/all_machines = list()
	var/list/hibernating_vents = list()
	var/list/sleeping_gas_devices = list()
	/// Rust gas arena ID -> assoc list of weakrefs for sleeping gas-dependent devices.
	var/list/gas_mixture_subscribers = list()
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
	/// Resource key -> monotonic generation for non-gas reactive dependencies.
	var/list/reactive_revisions = list()
	/// Resource key -> weakref map of sleeping machinery.
	var/list/reactive_subscribers = list()
	/// Weakref reference -> captured resource generations for sleeping machinery.
	var/list/reactive_sleepers = list()
	/// Diagnostic provenance for dependency-driven scheduling.
	var/list/machine_wake_reason_counts = list()
	var/list/machine_noop_counts = list()

	var/list/processing_machines = list()
	var/list/powernets = list()
	/// Powernets with a live accounting window. `powernets` remains the complete
	/// topology registry for rebuilds/admin tools.
	var/list/active_powernets = list()
	var/list/powerobjs = list()
	/// Enables low-overhead concrete-type timing for machine polling audits.
	// Concrete-type timing performs extra high-resolution clock reads inside the
	// hot machine loop. Enable it explicitly for benchmark runs; production keeps
	// the compact subsystem totals without paying continuous sampling overhead.
	var/profile_machine_types = FALSE
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

	// Wait to rebuild powernets
	VAR_PRIVATE/defering_powernets = FALSE
	/// world.time when defer_powernet_rebuild() was last called. Used to
	/// auto-release the defer after powernet_defer_max_age if a matching
	/// release_powernet_defer() was never called (e.g. shuttle code crashed).
	VAR_PRIVATE/powernet_defer_started = 0
	/// Maximum time (deciseconds) a powernet defer may remain active before
	/// SSmachines auto-releases it.  Default: 5 minutes.  Keeps a missed
	/// release() from leaving powernets stale indefinitely.
	VAR_PRIVATE/powernet_defer_max_age = 5 MINUTES

/datum/controller/subsystem/machines/Initialize()
	makepowernets()
	fire()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/machines/fire(resumed = 0)
	var/timer = TICK_USAGE

	// Auto-release stale powernet defers. If a caller called defer_powernet_rebuild()
	// but never called release_powernet_defer() (e.g. due to an exception in the
	// shuttling code), powernets stay unbuilt indefinitely.  After
	// powernet_defer_max_age deciseconds, force a rebuild and log so the
	// responsible code can be found and fixed.
	if(defering_powernets && (world.time - powernet_defer_started) >= powernet_defer_max_age)
		log_game("SSmachines: powernet defer exceeded max age ([powernet_defer_max_age / 10]s); auto-releasing. Check for a missing release_powernet_defer() call.")
		message_admins("WARNING: Powernet generation defer auto-released after timeout -- check logs.")
		release_powernet_defer()

	// SSMACHINES_PIPENETS step removed; pipenets dispatch via SSair.
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_POWER_OBJECTS,FALSE,process_power_objects,cost_power_objects,last_cost_power_objects,current_cost_power_objects,SSMACHINES_MACHINERY) // Higher priority, damnit
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_MACHINERY,FALSE,process_machinery,cost_machinery,last_cost_machinery,current_cost_machinery,SSMACHINES_POWERNETS)
	INTERNAL_PROCESS_STEP_PROFILED(SSMACHINES_POWERNETS,FALSE,process_powernets,cost_powernets,last_cost_powernets,current_cost_powernets,SSMACHINES_POWER_OBJECTS)

// Call when you need the network rebuilt, but we should wait until we have a good time to do it
/datum/controller/subsystem/machines/proc/defer_powernet_rebuild()
	if(!SSticker.HasRoundStarted())
		return
	// Use with responsibility... Must regen the entire power network after deferral is finished.
	if(!defering_powernets)
		defering_powernets = TRUE
		powernet_defer_started = world.time
		message_admins("Powernet generation deferred...")


// This MUST be called if request_powernet_rebuild is called with defer = TRUE once the network is free to regen
/datum/controller/subsystem/machines/proc/release_powernet_defer()
	if(defering_powernets)
		defering_powernets = FALSE
		message_admins("Powernet generation resumed. Rebuilding network...")
		makepowernets()

/datum/controller/subsystem/machines/proc/powernet_is_defered()
	return defering_powernets

// rebuild all power networks from scratch - Called when major network changes happen, like shuttles/turbolifts with wires moving, or huge explosions, where doing it per-wire does not make sense.
/datum/controller/subsystem/machines/proc/makepowernets()
	// TODO - check to not run while in the middle of a tick!
	for(var/datum/powernet/PN as anything in powernets)
		qdel(PN)
	powernets.Cut()
	setup_powernets_for_cables(GLOB.cable_list)

/datum/controller/subsystem/machines/proc/setup_powernets_for_cables(list/cables)
	for(var/obj/structure/cable/PC as anything in cables)
		if(!PC.powernet)
			var/datum/powernet/NewPN = new()
			NewPN.add_cable(PC)
			propagate_network(PC,PC.powernet)

// (Submap loads call /obj/machinery/atmospherics/atmos_init() directly,
//  main-map load runs through SSair.Initialize → setup_atmos_machinery.)

/datum/controller/subsystem/machines/stat_entry(msg)
	msg = "C:{"
	msg += "MC:[round(last_cost_machinery,1)]/[round(cost_machinery,1)]|"
	msg += "PN:[round(last_cost_powernets,1)]/[round(cost_powernets,1)]|"
	msg += "PO:[round(last_cost_power_objects,1)]/[round(cost_power_objects,1)]"
	msg += "} "
	msg += "MC:[length(SSmachines.processing_machines)]|"
	msg += "PN:[length(SSmachines.active_powernets)]/[length(SSmachines.powernets)][defering_powernets ? " - !!DEFER!!" : ""]|"
	msg += "PO:[length(SSmachines.powerobjs)]|"
	msg += "HV:[length(SSmachines.hibernating_vents)]|"
	msg += "GD:[gas_dirty_last] GW:[gas_woken_last] GX:[gas_dead_last]|"
	msg += "MC/MS:[round((cost_machinery ? length(SSmachines.processing_machines)/cost_machinery : 0),0.1)]"
	return ..()

/datum/controller/subsystem/machines/proc/process_machinery(resumed = 0)
	if (!resumed)
		src.current_run = processing_machines.Copy()
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
	var/list/current_run = src.current_run
	while(length(current_run))
		var/obj/machinery/M = current_run[length(current_run)]
		current_run.len--
		var/process_result
		if(istype(M) && !QDELETED(M))
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
		if(!istype(M) || QDELETED(M) || process_result == PROCESS_KILL)
			if(istype(M) && process_result == PROCESS_KILL)
				machine_noop_counts["[M.type]"]++
			processing_machines.Remove(M)
			DISABLE_BITFIELD(M?.datum_flags, DF_ISPROCESSING)
		if(MC_TICK_CHECK)
			flush_pump_transfers()
			return
	flush_pump_transfers()
	if(profile_machine_types && world.time >= next_machine_profile_dump)
		dump_machine_profile()
	// Rotate the stratum only after the generation was actually exhausted; a
	// yielded/resumed fire keeps the same phase and never double-samples a slot.
	machine_profile_sample_phase = (machine_profile_sample_phase + 1) % machine_profile_sample_stride

/datum/controller/subsystem/machines/proc/queue_pump_transfer(obj/machinery/atmospherics/M, datum/gas_mixture/source, datum/gas_mixture/sink, requested_moles, specific_power, source_moles, source_volume)
	if(!M || !source || !sink || requested_moles <= 0)
		return FALSE
	pending_pump_transfers += list(list(M, source, sink, requested_moles, specific_power, source_moles, source_volume))
	return TRUE

/datum/controller/subsystem/machines/proc/flush_pump_transfers()
	if(!length(pending_pump_transfers))
		last_pump_commit_ms = 0
		last_pump_commit_operations = 0
		last_pump_commit_turfs = 0
		return
	var/commit_started = TICK_USAGE
	var/list/operations = list()
	for(var/list/transfer as anything in pending_pump_transfers)
		// List union silently removes repeated datum values. Many vents share one
		// pipenet, so append by index to preserve the fixed source/sink/moles tuples.
		var/operation_offset = length(operations)
		operations.len += 3
		operations[operation_offset + 1] = transfer[2]
		operations[operation_offset + 2] = transfer[3]
		operations[operation_offset + 3] = transfer[4]
	var/list/actual_moles = call_ext(VERDIGRIS, "byond:batch_transfer_hook_ffi")(operations)
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
	var/list/sorted_wakes = machine_wake_reason_counts.Copy()
	sortTim(sorted_wakes, /proc/cmp_numeric_desc, TRUE)
	rank = 0
	for(var/reason in sorted_wakes)
		log_runtime("MACHINE_PROFILE_WAKE reason=[reason] count=[machine_wake_reason_counts[reason]]")
		if(++rank >= 20)
			break
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
	machine_wake_reason_counts = list()
	machine_noop_counts = list()
	machine_profile_dumping = FALSE

/datum/controller/subsystem/machines/proc/process_powernets(resumed = 0)
	if (!resumed)
		src.current_run = active_powernets.Copy()

	var/wait = src.wait
	var/list/current_run = src.current_run
	while(length(current_run))
		var/datum/powernet/PN = current_run[length(current_run)]
		current_run.len--
		if(!PN || QDELETED(PN))
			powernets.Remove(PN)
			active_powernets.Remove(PN)
			DISABLE_BITFIELD(PN?.datum_flags, DF_ISPROCESSING)
		else if(PN.reset(wait) == PROCESS_KILL)
			STOP_PROCESSING_POWERNET(PN)
		if(MC_TICK_CHECK)
			return

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
	for(var/datum/D as anything in SSmachines.processing_machines)
		if(!istype(D, /obj/machinery))
			log_world("## ERROR Found wrong type during SSmachinery recovery: list=SSmachines.machines, item=[D], type=[D?.type]")
			SSmachines.processing_machines -= D
	for(var/datum/D as anything in SSmachines.powernets)
		if(!istype(D, /datum/powernet))
			log_world("## ERROR Found wrong type during SSmachinery recovery: list=SSmachines.powernets, item=[D], type=[D?.type]")
			SSmachines.powernets -= D
	for(var/datum/D as anything in SSmachines.powerobjs)
		if(!istype(D, /obj/item))
			log_world("## ERROR Found wrong type during SSmachinery recovery: list=SSmachines.powerobjs, item=[D], type=[D?.type]")
			SSmachines.powerobjs -= D

	all_machines = SSmachines.all_machines
	processing_machines = SSmachines.processing_machines
	powernets = SSmachines.powernets
	active_powernets = SSmachines.active_powernets
	powerobjs = SSmachines.powerobjs
	current_run = SSmachines.current_run
	pending_pump_transfers = SSmachines.pending_pump_transfers
	hibernating_vents = SSmachines.hibernating_vents
	sleeping_gas_devices = SSmachines.sleeping_gas_devices
	gas_mixture_subscribers = SSmachines.gas_mixture_subscribers
	gas_mixture_subscriber_masks = SSmachines.gas_mixture_subscriber_masks
	gas_mixture_interest_counts = SSmachines.gas_mixture_interest_counts
	gas_mixture_watch_masks = SSmachines.gas_mixture_watch_masks
	pending_gas_watch_updates = SSmachines.pending_gas_watch_updates
	pending_dirty_gas_mixtures = SSmachines.pending_dirty_gas_mixtures
	pending_dirty_gas_index = SSmachines.pending_dirty_gas_index
	gas_wake_complete = SSmachines.gas_wake_complete
	reactive_revisions = SSmachines.reactive_revisions
	reactive_subscribers = SSmachines.reactive_subscribers
	reactive_sleepers = SSmachines.reactive_sleepers

/// Advances a dependency generation and immediately wakes its exact subscribers.
/datum/controller/subsystem/machines/proc/publish_reactive_dependency(resource_key)
	if(isnull(resource_key))
		return
	resource_key = "[resource_key]"
	reactive_revisions[resource_key] = (reactive_revisions[resource_key] || 0) + 1
	var/list/subscribers = reactive_subscribers[resource_key]
	if(!length(subscribers))
		return
	for(var/subscriber_key in subscribers.Copy())
		wake_reactive_machine(subscribers[subscriber_key], resource_key)

/datum/controller/subsystem/machines/proc/mob_chunk_key(atom/location)
	var/turf/T = get_turf(location)
	if(!T)
		return
	return "mob-chunk:[T.z]:[FLOOR(T.x - 1, CHUNK_SIZE) / CHUNK_SIZE]:[FLOOR(T.y - 1, CHUNK_SIZE) / CHUNK_SIZE]"

/datum/controller/subsystem/machines/proc/publish_mob_chunk(atom/location)
	var/resource_key = mob_chunk_key(location)
	if(resource_key && length(reactive_subscribers[resource_key]))
		publish_reactive_dependency(resource_key)

/// Atomically subscribes to the supplied resources before removing a machine from polling.
/datum/controller/subsystem/machines/proc/hibernate_reactive_machine(obj/machinery/M, list/resource_keys)
	if(!M || QDELETED(M) || !length(resource_keys))
		return FALSE
	var/datum/weakref/WR = WEAKREF(M)
	var/list/captured = list()
	for(var/raw_key in resource_keys)
		var/resource_key = "[raw_key]"
		captured[resource_key] = reactive_revisions[resource_key] || 0
		var/list/subscribers = reactive_subscribers[resource_key]
		if(!subscribers)
			subscribers = list()
			reactive_subscribers[resource_key] = subscribers
		subscribers[WR.reference] = WR
	reactive_sleepers[WR.reference] = captured
	// Subscribe-before-sleep validation closes changes introduced by callbacks.
	for(var/resource_key in captured)
		if(captured[resource_key] != (reactive_revisions[resource_key] || 0))
			wake_reactive_machine(WR)
			return FALSE
	STOP_MACHINE_PROCESSING(M)
	return TRUE

/datum/controller/subsystem/machines/proc/wake_reactive_machine(datum/weakref/WR, reason = "explicit")
	if(!WR?.reference)
		return
	var/list/captured = reactive_sleepers[WR.reference]
	if(!captured)
		return
	for(var/resource_key in captured)
		var/list/subscribers = reactive_subscribers[resource_key]
		subscribers?.Remove(WR.reference)
		if(subscribers && !length(subscribers))
			reactive_subscribers.Remove(resource_key)
	reactive_sleepers.Remove(WR.reference)
	var/obj/machinery/M = WR.resolve()
	if(M && !QDELETED(M))
		machine_wake_reason_counts["[M.type]|[reason]"]++
		START_MACHINE_PROCESSING(M)

/// Diagnostic-only invariant audit; gameplay never relies on this to wake objects.
/datum/controller/subsystem/machines/proc/audit_reactive_sleepers(fail_hard = FALSE)
	var/list/problems = list()
	for(var/subscriber_key in reactive_sleepers)
		var/list/captured = reactive_sleepers[subscriber_key]
		var/datum/weakref/WR
		for(var/resource_key in captured)
			var/list/subscribers = reactive_subscribers[resource_key]
			WR ||= subscribers?[subscriber_key]
			if(!subscribers?[subscriber_key])
				problems += "[subscriber_key] missing subscription to [resource_key]"
			if(captured[resource_key] != (reactive_revisions[resource_key] || 0))
				problems += "[subscriber_key] stale on [resource_key]"
		var/obj/machinery/M = WR?.resolve()
		if(!M)
			problems += "dead reactive subscriber [subscriber_key]"
		else if(M in processing_machines)
			problems += "[M] is both sleeping and processing"
	if(length(problems) && fail_hard)
		CRASH("Reactive dependency audit failed: [problems.Join("; ")]")
	return problems

/datum/controller/subsystem/machines/proc/wake_dirty_gas_subscribers()
	var/scan_started = TICK_USAGE
	if(!pending_dirty_gas_mixtures)
		pending_dirty_gas_mixtures = drain_dirty_gas_observations()
		pending_dirty_gas_index = 1
		pending_leak_network_wakes = list()
		gas_dirty_last = length(pending_dirty_gas_mixtures) / 13
		gas_woken_last = 0
		gas_dead_last = 0
	while(pending_dirty_gas_index <= length(pending_dirty_gas_mixtures))
		var/observation_index = pending_dirty_gas_index
		var/mixture_id = pending_dirty_gas_mixtures[pending_dirty_gas_index]
		var/change_mask = pending_dirty_gas_mixtures[pending_dirty_gas_index + 1]
		pending_dirty_gas_index += 13
		var/list/subscribers = gas_mixture_subscribers["[mixture_id]"]
		if(length(subscribers))
			var/list/subscriber_masks = gas_mixture_subscriber_masks["[mixture_id]"]
			var/list/to_wake
			for(var/key in subscribers)
				if(!((subscriber_masks?[key] || GAS_DEPENDENCY_ALL) & change_mask))
					continue
				current_gas_wake_subscribers++
				var/datum/weakref/WR = subscribers[key]
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
	var/list/subscribers = gas_mixture_subscribers[key]
	if(!subscribers)
		subscribers = list()
		gas_mixture_subscribers[key] = subscribers
	var/list/subscriber_masks = gas_mixture_subscriber_masks[key]
	if(!subscriber_masks)
		subscriber_masks = list()
		gas_mixture_subscriber_masks[key] = subscriber_masks
	var/old_mask = subscriber_masks[WR.reference] || NONE
	var/obj/machinery/subscriber = WR.resolve()
	var/new_mask = subscriber ? subscriber.gas_dependency_interest_mask() : GAS_DEPENDENCY_ALL
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
		unwatch_dirty_gas_mixture(mixture_id)

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
		machine_wake_reason_counts["[woken_machine.type]|[reason]"]++
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
	else if(istype(subscriber, /obj/machinery/atmospherics/binary/pump))
		var/obj/machinery/atmospherics/binary/pump/P = subscriber
		P.clear_gas_dependencies()
		START_MACHINE_PROCESSING(P)
	else if(istype(subscriber, /obj/machinery/atmospherics/binary/passive_gate))
		var/obj/machinery/atmospherics/binary/passive_gate/G = subscriber
		G.clear_gas_dependencies()
		START_MACHINE_PROCESSING(G)
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

/// Diagnostic-only invariant audit. This never wakes devices or participates in gameplay.
/datum/controller/subsystem/machines/proc/audit_sleeping_gas_subscribers(fail_hard = FALSE)
	var/list/problems = list()
	for(var/key in sleeping_gas_devices)
		var/datum/weakref/WR = sleeping_gas_devices[key]
		var/atom/device = WR?.resolve()
		if(!device)
			problems += "dead subscriber [key]"
			continue
		if(istype(device, /obj/machinery/atmospherics/unary/vent_pump))
			var/obj/machinery/atmospherics/unary/vent_pump/V = device
			if(V.can_pump() && V.get_pressure_delta(V.return_air()) > 0.5)
				problems += "[V] sleeps with actionable pressure delta"
		else if(istype(device, /obj/machinery/alarm))
			var/obj/machinery/alarm/A = device
			if(A.regulating_temperature)
				problems += "[A] sleeps while regulating temperature"
	if(length(problems))
		var/message = "Gas dependency audit failed: [problems.Join("; ")]"
		if(fail_hard)
			CRASH(message)
		log_world(message)
	return problems

#undef SSMACHINES_MACHINERY
#undef SSMACHINES_POWERNETS
#undef SSMACHINES_POWER_OBJECTS
