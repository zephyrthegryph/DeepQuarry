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

	var/list/current_run = list()

	var/list/all_machines = list()
	var/list/hibernating_vents = list()
	var/list/sleeping_gas_devices = list()
	/// Rust gas arena ID -> assoc list of weakrefs for sleeping gas-dependent devices.
	var/list/gas_mixture_subscribers = list()
	/// Resource key -> monotonic generation for non-gas reactive dependencies.
	var/list/reactive_revisions = list()
	/// Resource key -> weakref map of sleeping machinery.
	var/list/reactive_subscribers = list()
	/// Weakref reference -> captured resource generations for sleeping machinery.
	var/list/reactive_sleepers = list()

	var/list/processing_machines = list()
	var/list/powernets = list()
	var/list/powerobjs = list()
	/// Enables concrete-type timing for machine polling audits.
	var/profile_machine_types = FALSE
	var/list/machine_profile_cost = list()
	var/list/machine_profile_calls = list()
	var/list/machine_profile_kills = list()
	var/next_machine_profile_dump = 0

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
	INTERNAL_PROCESS_STEP(SSMACHINES_POWER_OBJECTS,FALSE,process_power_objects,cost_power_objects,SSMACHINES_MACHINERY) // Higher priority, damnit
	INTERNAL_PROCESS_STEP(SSMACHINES_MACHINERY,FALSE,process_machinery,cost_machinery,SSMACHINES_POWERNETS)
	INTERNAL_PROCESS_STEP(SSMACHINES_POWERNETS,FALSE,process_powernets,cost_powernets,SSMACHINES_POWER_OBJECTS)

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
	msg += "MC:[round(cost_machinery,1)]|"
	msg += "PN:[round(cost_powernets,1)]|"
	msg += "PO:[round(cost_power_objects,1)]"
	msg += "} "
	msg += "MC:[length(SSmachines.processing_machines)]|"
	msg += "PN:[length(SSmachines.powernets)][defering_powernets ? " - !!DEFER!!" : ""]|"
	msg += "PO:[length(SSmachines.powerobjs)]|"
	msg += "HV:[length(SSmachines.hibernating_vents)]|"
	msg += "MC/MS:[round((cost_machinery ? length(SSmachines.processing_machines)/cost_machinery : 0),0.1)]"
	return ..()

/datum/controller/subsystem/machines/proc/process_machinery(resumed = 0)
	if (!resumed)
		wake_dirty_gas_subscribers()
		src.current_run = processing_machines.Copy()
		if(profile_machine_types && !next_machine_profile_dump)
			next_machine_profile_dump = world.time + 30 SECONDS

	var/wait = src.wait
	var/list/current_run = src.current_run
	while(length(current_run))
		var/obj/machinery/M = current_run[length(current_run)]
		current_run.len--
		var/process_result
		if(istype(M) && !QDELETED(M))
			if(profile_machine_types)
				var/machine_type = "[M.type]"
				var/profile_start = TICK_USAGE_REAL
				process_result = M.process(wait)
				machine_profile_cost[machine_type] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - profile_start)
				machine_profile_calls[machine_type]++
				if(process_result == PROCESS_KILL)
					machine_profile_kills[machine_type]++
			else
				process_result = M.process(wait)
		if(!istype(M) || QDELETED(M) || process_result == PROCESS_KILL)
			processing_machines.Remove(M)
			DISABLE_BITFIELD(M?.datum_flags, DF_ISPROCESSING)
		if(MC_TICK_CHECK)
			return
	if(profile_machine_types && world.time >= next_machine_profile_dump)
		dump_machine_profile()

/datum/controller/subsystem/machines/proc/dump_machine_profile()
	var/list/current_counts = list()
	for(var/obj/machinery/M as anything in processing_machines)
		if(M && !QDELETED(M))
			current_counts["[M.type]"]++
	var/list/sorted_cost = machine_profile_cost.Copy()
	sortTim(sorted_cost, /proc/cmp_numeric_desc, TRUE)
	var/rank = 0
	for(var/machine_type in sorted_cost)
		log_runtime("MACHINE_PROFILE type=[machine_type] cost_ms=[round(machine_profile_cost[machine_type], 0.01)] calls=[machine_profile_calls[machine_type]] active=[current_counts[machine_type] || 0] killed=[machine_profile_kills[machine_type] || 0]")
		if(++rank >= 25)
			break
	machine_profile_cost.Cut()
	machine_profile_calls.Cut()
	machine_profile_kills.Cut()
	next_machine_profile_dump = world.time + 30 SECONDS

/datum/controller/subsystem/machines/proc/process_powernets(resumed = 0)
	if (!resumed)
		src.current_run = powernets.Copy()

	var/wait = src.wait
	var/list/current_run = src.current_run
	while(length(current_run))
		var/datum/powernet/PN = current_run[length(current_run)]
		current_run.len--
		if(!PN)
			powernets.Remove(PN)
			DISABLE_BITFIELD(PN?.datum_flags, DF_ISPROCESSING)
		else
			PN.reset(wait)
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
	powerobjs = SSmachines.powerobjs

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
		wake_reactive_machine(subscribers[subscriber_key])

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

/datum/controller/subsystem/machines/proc/wake_reactive_machine(datum/weakref/WR)
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
	var/list/dirty_mixtures = drain_dirty_gas_mixtures()
	for(var/mixture_index = 1; mixture_index <= length(dirty_mixtures); mixture_index += 2)
		var/mixture_id = dirty_mixtures[mixture_index]
		var/change_mask = dirty_mixtures[mixture_index + 1]
		var/list/subscribers = gas_mixture_subscribers["[mixture_id]"]
		if(!length(subscribers))
			continue
		for(var/key in subscribers.Copy())
			var/datum/weakref/WR = subscribers[key]
			if(!sleeping_gas_devices[WR?.reference])
				continue
			var/atom/subscriber = WR?.resolve()
			if(!subscriber)
				wake_gas_subscriber(WR)
			else if(istype(subscriber, /obj/machinery/atmospherics/unary))
				var/obj/machinery/atmospherics/unary/V = subscriber
				if(V.gas_dependency_changed(mixture_id, change_mask))
					wake_gas_subscriber(WR)
			else if(istype(subscriber, /obj/machinery/alarm))
				var/obj/machinery/alarm/A = subscriber
				if(A.gas_dependency_changed(mixture_id, change_mask))
					wake_gas_subscriber(WR)
			else if(istype(subscriber, /obj/machinery/air_sensor))
				var/obj/machinery/air_sensor/S = subscriber
				if(S.gas_dependency_changed(mixture_id, change_mask))
					wake_gas_subscriber(WR)
			else if(istype(subscriber, /obj/machinery/airlock_sensor))
				var/obj/machinery/airlock_sensor/S = subscriber
				if(S.gas_dependency_changed(mixture_id, change_mask))
					wake_gas_subscriber(WR)
			else
				wake_gas_subscriber(WR)

/datum/controller/subsystem/machines/proc/subscribe_gas_dependency(mixture_id, datum/weakref/WR)
	if(isnull(mixture_id) || !WR)
		return
	var/key = "[mixture_id]"
	var/list/subscribers = gas_mixture_subscribers[key]
	if(!subscribers)
		subscribers = list()
		gas_mixture_subscribers[key] = subscribers
	subscribers[WR.reference] = WR

/datum/controller/subsystem/machines/proc/unsubscribe_gas_dependency(mixture_id, datum/weakref/WR)
	if(isnull(mixture_id) || !WR)
		return
	var/key = "[mixture_id]"
	var/list/subscribers = gas_mixture_subscribers[key]
	if(!subscribers)
		return
	subscribers.Remove(WR.reference)
	if(!length(subscribers))
		gas_mixture_subscribers.Remove(key)

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

/datum/controller/subsystem/machines/proc/hibernate_air_alarm(obj/machinery/alarm/A)
	if(!A)
		return
	var/datum/weakref/WR = WEAKREF(A)
	sleeping_gas_devices[WR.reference] = WR
	A.register_gas_dependencies(WR)
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

/datum/controller/subsystem/machines/proc/wake_vent(datum/weakref/WR)
	wake_gas_subscriber(WR)

/datum/controller/subsystem/machines/proc/wake_gas_subscriber(datum/weakref/WR)
	if(!WR)
		return
	if(WR.reference && !sleeping_gas_devices[WR.reference])
		return
	var/atom/subscriber = WR.resolve()
	if(istype(subscriber, /obj/machinery/atmospherics/unary))
		var/obj/machinery/atmospherics/unary/V = subscriber
		V.unregister_gas_dependencies(WR)
		START_MACHINE_PROCESSING(V)
	else if(istype(subscriber, /obj/machinery/alarm))
		var/obj/machinery/alarm/A = subscriber
		A.unregister_gas_dependencies(WR)
		START_MACHINE_PROCESSING(A)
	else if(istype(subscriber, /obj/machinery/air_sensor))
		var/obj/machinery/air_sensor/S = subscriber
		S.unregister_gas_dependencies(WR)
		START_MACHINE_PROCESSING(S)
	else if(istype(subscriber, /obj/machinery/airlock_sensor))
		var/obj/machinery/airlock_sensor/S = subscriber
		S.unregister_gas_dependencies(WR)
		START_MACHINE_PROCESSING(S)
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
