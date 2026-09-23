#define SSMACHINES_MACHINERY     2
#define SSMACHINES_POWERNETS     3
#define SSMACHINES_POWER_OBJECTS 4
#define POWER_TOPOLOGY_WORK_SLICE 32

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
	/// Independent monotonic wall time and its excess over BYOND active time.
	/// This prevents an OS pause from being diagnosed as gas-transfer work.
	var/last_pump_commit_wall_ms = 0
	var/last_pump_commit_suspended_ms = 0
	var/last_pump_commit_operations = 0
	var/last_pump_commit_turfs = 0

	var/list/all_machines = list()
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
	/// Resource key -> monotonic generation for non-gas reactive dependencies.
	var/list/reactive_revisions = list()
	/// Resource key -> weakref map of sleeping machinery.
	var/list/reactive_subscribers = list()
	/// Number of "mob-chunk:" keys in reactive_subscribers; mob movement skips the key build while it is 0 (Q12).
	var/mob_chunk_subscriptions = 0
	/// Weakref reference -> captured resource generations for sleeping machinery.
	var/list/reactive_sleepers = list()
	/// Diagnostic provenance for dependency-driven scheduling.
	var/list/machine_wake_reason_counts = list()
	var/list/machine_noop_counts = list()

	/// Machines polled every pass. Order is not stable: removal swaps the last
	/// entry into the vacated slot (see stop_machine_processing()).
	var/list/processing_machines = list()
	/// Next processing_machines slot to visit in the current pass (walks down to 1).
	var/machine_run_cursor = 0
	/// Increments once per machinery pass; see /obj/machinery/var/machine_processing_pass.
	var/machine_run_pass = 1
	var/list/powernets = list()
	/// Powernets with a live accounting window. `powernets` remains the complete
	/// topology registry for rebuilds/admin tools.
	var/list/active_powernets = list()
	/// Networks which received dynamic APC usage in the preceding machinery
	/// generation. Only these need their old transaction cleared and finalized.
	var/list/accounting_powernets = list()
	var/list/current_accounting_powernets = list()
	var/list/powerobjs = list()
	/// Targeted cable topology transactions. A wire interaction only records the
	/// severed edge; connected components are discovered and published in bounded
	/// slices here instead of flood-filling the station inside attackby().
	var/list/powernet_topology_jobs = list()
	var/list/powernet_topology_jobs_by_net = list()
	var/powernet_topology_last_work = 0
	var/powernet_topology_last_ms = 0
	/// Generation used to expire a producer only when its own process() stopped
	/// publishing, preserving legacy add_avail() omission semantics.
	var/power_supply_generation = 0
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

	// Wait to rebuild powernets
	VAR_PRIVATE/defering_powernets = FALSE
	/// world.time when defer_powernet_rebuild() was last called. Used to
	/// auto-release the defer after powernet_defer_max_age if a matching
	/// release_powernet_defer() was never called (e.g. shuttle code crashed).
	VAR_PRIVATE/powernet_defer_started = 0
	/// Powernets that lost a cable while deferred; each gets a targeted topology job on release.
	var/list/deferred_powernet_splits = list()
	/// Cables placed or rotated while deferred; their merges replay on release.
	var/list/deferred_powernet_cables = list()
	/// Power machines that tried to connect while deferred; they retry on release.
	var/list/deferred_powernet_machines = list()
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
	if(!process_powernet_topology_jobs())
		return

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
	// While deferred, cable and machine edits record what they touched; release
	// repairs only those networks.
	if(!defering_powernets)
		defering_powernets = TRUE
		powernet_defer_started = world.time
		message_admins("Powernet generation deferred...")


/// Ends a defer_powernet_rebuild() window. Only the networks edited during the
/// window are repaired: split networks get a topology job, and deferred cable
/// merges and machine connections are replayed in the order they happened.
/datum/controller/subsystem/machines/proc/release_powernet_defer()
	if(!defering_powernets)
		return
	defering_powernets = FALSE
	var/list/splits = deferred_powernet_splits
	var/list/cables = deferred_powernet_cables
	var/list/machines = deferred_powernet_machines
	deferred_powernet_splits = list()
	deferred_powernet_cables = list()
	deferred_powernet_machines = list()
	message_admins("Powernet generation resumed. Repairing [length(splits)] network\s...")
	for(var/datum/powernet/network as anything in splits)
		queue_powernet_topology(network)
	for(var/obj/structure/cable/cable as anything in cables)
		if(QDELETED(cable) || !isturf(cable.loc))
			continue
		cable.replay_deferred_merges(cables[cable])
	for(var/obj/machinery/power/machine as anything in machines)
		if(QDELETED(machine) || machine.powernet)
			continue
		machine.connect_to_network()

/datum/controller/subsystem/machines/proc/note_deferred_powernet_split(datum/powernet/network)
	if(network && !QDELETED(network))
		deferred_powernet_splits[network] = TRUE

/// Records a merge request made while deferred. `merge` is a CABLE_DEFERRED_* flag.
/datum/controller/subsystem/machines/proc/note_deferred_powernet_cable(obj/structure/cable/cable, merge)
	deferred_powernet_cables[cable] |= merge

/datum/controller/subsystem/machines/proc/note_deferred_powernet_machine(obj/machinery/power/machine)
	deferred_powernet_machines[machine] = TRUE

/datum/controller/subsystem/machines/proc/powernet_is_defered()
	return defering_powernets

/// Queue one connected network for a targeted split/rebind. Repeated edits to
/// the same network coalesce by invalidating the in-flight snapshot.
/datum/controller/subsystem/machines/proc/queue_powernet_topology(datum/powernet/network)
	if(!network || QDELETED(network))
		return
	network.topology_generation++
	network.topology_pending = TRUE
	network.avail = 0
	network.newavail = 0
	network.netexcess = -network.load
	STOP_PROCESSING_POWERNET(network)
	var/datum/powernet_topology_job/job = powernet_topology_jobs_by_net[network]
	if(job)
		job.restart_requested = TRUE
		return
	job = new(network)
	powernet_topology_jobs += job
	powernet_topology_jobs_by_net[network] = job

/// Spend only the current subsystem slice on topology. A large station split
/// may span several ticks, but player interaction returns immediately.
/datum/controller/subsystem/machines/proc/process_powernet_topology_jobs()
	if(!length(powernet_topology_jobs))
		powernet_topology_last_work = 0
		powernet_topology_last_ms = 0
		return TRUE
	var/started = TICK_USAGE
	var/work_done = 0
	while(length(powernet_topology_jobs))
		var/datum/powernet_topology_job/job = powernet_topology_jobs[1]
		work_done += job.process_slice()
		if(job.complete)
			powernet_topology_jobs.Cut(1, 2)
			powernet_topology_jobs_by_net.Remove(job.source_net)
			qdel(job)
		if(MC_TICK_CHECK)
			powernet_topology_last_work = work_done
			powernet_topology_last_ms = TICK_DELTA_TO_MS(TICK_USAGE - started)
			return FALSE
	powernet_topology_last_work = work_done
	powernet_topology_last_ms = TICK_DELTA_TO_MS(TICK_USAGE - started)
	return TRUE

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
			NewPN.begin_topology_batch()
			NewPN.add_cable(PC)
			propagate_network(PC,PC.powernet)
			NewPN.end_topology_batch()

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
		machine_run_pass++
		machine_run_cursor = length(processing_machines)
		power_supply_generation++
		current_accounting_powernets = accounting_powernets.Copy()
		accounting_powernets.Cut()
		for(var/datum/powernet/PN as anything in current_accounting_powernets)
			if(PN && !QDELETED(PN))
				PN.begin_accounting_window()
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
			if(istype(M, /obj/machinery/power))
				var/obj/machinery/power/power_machine = M
				if(power_machine.powernet && power_machine.powernet.registered_sources[power_machine] && power_machine.power_supply_generation != power_supply_generation)
					power_machine.clear_power_supply()
		if(QDELETED(M) || process_result == PROCESS_KILL)
			if(process_result == PROCESS_KILL)
				machine_noop_counts["[M.type]"]++
			stop_machine_processing(M)
		if(MC_TICK_CHECK)
			flush_pump_transfers()
			return
	for(var/datum/powernet/PN as anything in current_accounting_powernets)
		if(PN && !QDELETED(PN))
			PN.finalize_accounting_window()
	current_accounting_powernets.Cut()
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

/// Enroll a powernet in the current completed-demand transaction. The first
/// report from a previously idle network establishes its window lazily.
/datum/controller/subsystem/machines/proc/touch_accounting_powernet(datum/powernet/PN)
	if(!PN || QDELETED(PN))
		return
	if(!(PN in current_accounting_powernets))
		PN.begin_accounting_window()
		current_accounting_powernets |= PN
	// It must be revisited once next generation to remove this generation's
	// dynamic contribution even if every reporting machine goes to sleep.
	accounting_powernets |= PN

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
	var/powernets_logged = 0
	for(var/datum/powernet/PN as anything in active_powernets)
		if(!PN || QDELETED(PN) || powernets_logged++ >= machine_profile_detail_limit)
			continue
		log_runtime("MACHINE_PROFILE_POWERNET nodes=[length(PN.nodes)] cables=[length(PN.cables)] load=[round(PN.load, 0.01)] supply=[round(PN.registered_supply_total, 0.01)] storage_demand=[round(PN.registered_storage_demand_total, 0.01)] custom=[PN.material_graph?.has_custom_conductors || FALSE] superconductors=[PN.material_graph?.has_superconductors || FALSE] wake=[PN.last_accounting_wake_reason] wakes=[PN.accounting_wake_count]")
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
	if(machine_profile_one_shot)
		profile_machine_types = FALSE
		machine_profile_one_shot = FALSE

/datum/controller/subsystem/machines/proc/request_adaptive_profile()
	if(profile_machine_types || last_cost_machinery < adaptive_profile_threshold_ms)
		return
	profile_machine_types = TRUE
	machine_profile_one_shot = TRUE
	next_machine_profile_dump = world.time + 10 SECONDS

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
	var/list/recovered_machines = list()
	for(var/datum/D as anything in SSmachines.processing_machines)
		if(!istype(D, /obj/machinery))
			log_world("## ERROR Found wrong type during SSmachinery recovery: list=SSmachines.machines, item=[D], type=[D?.type]")
			continue
		var/obj/machinery/M = D
		recovered_machines += M
		M.machine_processing_index = length(recovered_machines)
	SSmachines.processing_machines = recovered_machines
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
	material_gas_subscribers = SSmachines.material_gas_subscribers
	material_gas_subscriber_masks = SSmachines.material_gas_subscriber_masks
	material_gas_corrosion = SSmachines.material_gas_corrosion
	gas_mixture_watch_masks = SSmachines.gas_mixture_watch_masks
	pending_gas_watch_updates = SSmachines.pending_gas_watch_updates
	pending_dirty_gas_mixtures = SSmachines.pending_dirty_gas_mixtures
	pending_dirty_gas_index = SSmachines.pending_dirty_gas_index
	gas_wake_complete = SSmachines.gas_wake_complete
	reactive_revisions = SSmachines.reactive_revisions
	reactive_subscribers = SSmachines.reactive_subscribers
	mob_chunk_subscriptions = SSmachines.mob_chunk_subscriptions
	reactive_sleepers = SSmachines.reactive_sleepers
	powernet_topology_jobs = SSmachines.powernet_topology_jobs
	powernet_topology_jobs_by_net = SSmachines.powernet_topology_jobs_by_net
	deferred_powernet_splits = SSmachines.deferred_powernet_splits
	deferred_powernet_cables = SSmachines.deferred_powernet_cables
	deferred_powernet_machines = SSmachines.deferred_powernet_machines

/// Incremental connected-component rebuild for a single edited powernet.
/datum/powernet_topology_job
	var/datum/powernet/source_net
	var/captured_generation
	var/restart_requested = FALSE
	var/complete = FALSE
	var/phase = 1
	var/list/remaining = list()
	var/list/frontier = list()
	var/list/current_component
	var/list/components = list()
	var/list/target_nets
	var/list/old_nodes
	var/component_index = 1
	var/member_index = 1
	var/node_index = 1

/datum/powernet_topology_job/New(datum/powernet/network)
	source_net = network
	restart_snapshot()
	..()

/datum/powernet_topology_job/Destroy()
	source_net = null
	remaining = null
	frontier = null
	current_component = null
	components = null
	target_nets = null
	old_nodes = null
	return ..()

/datum/powernet_topology_job/proc/restart_snapshot()
	captured_generation = source_net?.topology_generation
	restart_requested = FALSE
	phase = 1
	remaining = list()
	frontier = list()
	current_component = null
	components = list()
	target_nets = list()
	old_nodes = null
	component_index = 1
	member_index = 1
	node_index = 1
	for(var/obj/structure/cable/cable as anything in source_net?.cables)
		if(cable && !QDELETED(cable) && cable.powernet == source_net)
			remaining[cable] = TRUE

/datum/powernet_topology_job/proc/start_component()
	var/obj/structure/cable/seed
	for(var/obj/structure/cable/candidate as anything in remaining)
		seed = candidate
		break
	if(!seed)
		return FALSE
	remaining.Remove(seed)
	current_component = list(seed)
	components += list(current_component)
	frontier += seed
	return TRUE

/datum/powernet_topology_job/proc/process_slice()
	var/work_done = 0
	if(!source_net || QDELETED(source_net))
		complete = TRUE
		return work_done
	if(restart_requested || captured_generation != source_net.topology_generation)
		restart_snapshot()
	while(!complete)
		if(phase == 1)
			if(!length(frontier))
				if(!start_component())
					phase = 2
					continue
			var/obj/structure/cable/cable = frontier[length(frontier)]
			frontier.len--
			for(var/obj/structure/cable/neighbor as anything in cable.get_connections())
				if(remaining[neighbor] && neighbor.powernet == source_net)
					remaining.Remove(neighbor)
					current_component += neighbor
					frontier += neighbor
			work_done++
		else if(phase == 2)
			old_nodes = source_net.nodes.Copy()
			source_net.prepare_topology_rebind()
			if(!length(components))
				qdel(source_net)
				complete = TRUE
				continue
			var/largest_index = 1
			for(var/i in 2 to length(components))
				if(length(components[i]) > length(components[largest_index]))
					largest_index = i
			for(var/i in 1 to length(components))
				var/datum/powernet/target = (i == largest_index) ? source_net : new()
				target.topology_pending = TRUE
				STOP_PROCESSING_POWERNET(target)
				LAZYADD(target_nets, target)
			source_net.cables = list()
			phase = 3
		else if(phase == 3)
			var/list/component = components[component_index]
			var/datum/powernet/target = LAZYACCESS(target_nets, component_index)
			var/obj/structure/cable/cable = component[member_index]
			cable.powernet = target
			target.cables += cable
			member_index++
			work_done++
			if(member_index > length(component))
				component_index++
				member_index = 1
				if(component_index > length(components))
					phase = 4
		else if(phase == 4)
			if(node_index <= length(old_nodes))
				var/obj/machinery/power/machine = old_nodes[node_index++]
				if(machine && !QDELETED(machine))
					var/turf/location = get_turf(machine)
					var/obj/structure/cable/node = location?.get_cable_node()
					var/datum/powernet/target = node?.powernet
					if(target && (target in target_nets))
						target.bind_machine_after_topology(machine)
					else
						machine.powernet = null
				work_done++
			else
				phase = 5
		else
			for(var/datum/powernet/target as anything in target_nets)
				target.topology_pending = FALSE
				target.invalidate_material_cache()
				target.publish_dependency()
			complete = TRUE
		if(work_done >= POWER_TOPOLOGY_WORK_SLICE)
			break
	return work_done

/// Advances a dependency generation and immediately wakes its exact subscribers.
/datum/controller/subsystem/machines/proc/publish_reactive_dependency(resource_key)
	if(isnull(resource_key))
		return
	resource_key = "[resource_key]"
	var/list/subscribers = reactive_subscribers[resource_key]
	if(!length(subscribers))
		// Revisions only matter to sleepers that captured them; with none, the
		// key would just sit in the table for the rest of the round.
		reactive_revisions -= resource_key
		return
	reactive_revisions[resource_key] = (reactive_revisions[resource_key] || 0) + 1
	for(var/subscriber_key in subscribers.Copy())
		wake_reactive_machine(subscribers[subscriber_key], resource_key)

/datum/controller/subsystem/machines/proc/mob_chunk_key(atom/location)
	var/turf/T = get_turf(location)
	if(!T)
		return
	return "mob-chunk:[T.z]:[FLOOR(T.x - 1, CHUNK_SIZE) / CHUNK_SIZE]:[FLOOR(T.y - 1, CHUNK_SIZE) / CHUNK_SIZE]"

/datum/controller/subsystem/machines/proc/publish_mob_chunk(atom/location)
	if(!mob_chunk_subscriptions)
		return
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
			if(findtext(resource_key, "mob-chunk:", 1, 11))
				mob_chunk_subscriptions++
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
			reactive_revisions -= resource_key
			if(findtext(resource_key, "mob-chunk:", 1, 11))
				mob_chunk_subscriptions--
	reactive_sleepers.Remove(WR.reference)
	var/obj/machinery/M = WR.resolve()
	if(M && !QDELETED(M))
		if(profile_machine_types)
			machine_wake_reason_counts["[M.type]|[reason]"]++
		START_MACHINE_PROCESSING(M)

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
		if(profile_machine_types)
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

#undef SSMACHINES_MACHINERY
#undef SSMACHINES_POWERNETS
#undef SSMACHINES_POWER_OBJECTS
