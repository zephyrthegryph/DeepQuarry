// Machines on an object-model pipeline (doc/rewrite/object_model_core.md §A.10).
//
// Every machine with DM-side periodic work runs /datum/om/pipeline/machine (SSmachines no longer
// polls anything): a power stage (what it does with its power, and its use_power mode), a step
// stage (its machine_step(), for machines whose work is started and stopped explicitly) and a
// present stage (its icon), every MACHINE_PIPELINE_INTERVAL while any has work. Settled, all idle
// and the machine parks; a channel wakes it (CHANGE_MACHINE_*), raised by the base setters
// (power_change(), atom_break(), atom_fix()) and by each type's own producers, or MACHINE_WAKE().
// A type's behaviour is a variant of a base stage, resolved by type depth.

/// One machine frame per machine service interval (MACHINE_SERVICE_INTERVAL).
#define MACHINE_PIPELINE_INTERVAL MACHINE_SERVICE_INTERVAL

/datum/om/decl/pipeline_machines
	of = list(
		/obj/machinery/power/apc,
		/obj/machinery/firealarm,
		// Atmospherics devices with DM-side work (the "machine_step" section below). Devices whose
		// flow law is a Rust device edge (vent pumps, dual-port vents and scrubbers, pumps, valves, passive gates, filters and mixers)
		// and plain pipes have no DM work at all and don't join.
		/obj/machinery/portable_atmospherics/powered/reagent_distillery,
		// Every other machine with machine_step() work (roadmap S5: the old SSmachines roster).
		// Each joins asleep: one frame at Initialize to find out whether it has work, then it
		// parks until MACHINE_WAKE() (tools/ci/pollers_lint.py checks this list is complete).
		/obj/machinery/telecomms,
		/obj/machinery/vending,
	)
	behaviours = list(/datum/om/pipeline/machine)
	/// Machines with machine_step() work that need no frame at Initialize: nothing gives them work
	/// until a producer's MACHINE_WAKE(), which joins them to the pipeline then. Numerous types
	/// belong here so an idle one never costs a record (tools/ci/pollers_lint.py reads this list).
	var/list/lazy = list( // ALLOW(instance_list): a declaration singleton: one instance
		/obj/machinery/door/airlock, // a radio command (receive_signal()) is its only step work
	)

/datum/om/pipeline/machine
	name = "machine"
	every = MACHINE_PIPELINE_INTERVAL
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	stages = list(/datum/om/stage/machine)
	frame_type = /datum/om/frame/machine
	wake_all = CHANGE_EXPLICIT

/// Machines start asleep (roadmap S5): joining runs nothing. Every stage starts idle and the machine
/// parks at its first cadence slot without a frame. Setup it needs at spawn happens once the world
/// is up (materialize_wakes(): arm its watches, then wake it only if its declared start condition
/// holds); from then on it runs only when a declared wake fires.
/datum/om/pipeline/machine/on_start(obj/machinery/M)
	var/datum/om/frame/S = om_pipe_state(M, src, TRUE)
	if(!S)
		return
	om_pipe_set_all(S, TRUE, max(park_after - 1, 0))
	if(M.first_wake_pending())
		return
	// During init every machine's first wake runs in one bulk pass when the MC has initialized
	// every boot node (the machine service's on_members_ready()), before the first air fire, instead of
	// thousands of zero-delay timers draining for minutes after the round starts.
	if(GLOB.machine_first_wakes_bulk)
		rel_add(om_global_owner(), nameof(/datum/om/global_owner::machine_first_wakes), M)
		return
	after(M, 0, /obj/machinery/proc/materialize_wakes, key = "first_wake")

/// Machines waiting for the boot bulk first-wake pass, in join order. A relation list on the global
/// owner: a deleted machine drops out on its own (its relation teardown), nothing takes it out.
/datum/om/global_owner/var/list/obj/machinery/machine_first_wakes
/datum/om/global_owner/relations()
	. = ..()
	. += rel_many(nameof(machine_first_wakes))
/// TRUE until the MC finishes initializing; while set, on_start() queues first wakes in bulk.
GLOBAL_VAR_INIT(machine_first_wakes_bulk, TRUE)

/// Runs every queued machine's first wake (arm_wakes() and its start condition) in one pass. The kernel
/// calls on_members_ready() once every boot node has initialized (pipenets and air exist, so gas
/// watches can arm), before the first air fire. Machines that join later use their `first_wake` timer slot.
/datum/system/machines/on_members_ready()
	GLOB.machine_first_wakes_bulk = FALSE
	var/datum/om/global_owner/owner = om_global_owner()
	var/list/queued = owner.machine_first_wakes?.Copy() || list()
	// Emptied up front: each materialize_wakes() then leaves an empty queue in O(1).
	rel_clear(owner, nameof(owner.machine_first_wakes))
	var/start = REALTIMEOFDAY
	var/ran = 0
	// What each type's first wakes cost, so the log names what a slow pass spent its time on.
	var/list/type_ms = list()
	var/list/type_count = list()
	for(var/obj/machinery/M as anything in queued)
		if(QDELETED(M))
			continue
		var/started = TICK_USAGE
		M.materialize_wakes()
		type_ms[M.type] += TICK_USAGE_TO_MS(started)
		type_count[M.type] += 1
		ran++
	sortTim(type_ms, /proc/cmp_numeric_desc, TRUE)
	var/list/costliest = list()
	for(var/path in type_ms)
		costliest += "[path] x[type_count[path]] [round(type_ms[path], 0.1)] ms"
		if(length(costliest) >= 5)
			break
	log_world("Machine first wakes: [ran] of [length(queued)] armed in bulk in [(REALTIMEOFDAY - start) / 10] s; costliest: [jointext(costliest, ", ")]")

/// A machine's first wake is materialize_wakes(), queued by on_start(): it arms the machine's
/// watches (arm_wakes()) and applies its start condition. After a large map load that queue can
/// take a while to drain (machines joining after boot in large numbers, e.g. a generated site), and a machine still waiting on it
/// has armed nothing yet -- the audit must not call that a missed wake.
/datum/om/pipeline/machine/first_wake_pending(obj/machinery/M)
	return istype(M) && M.first_wake_pending()

/datum/om/frame/machine
	facts = list(
		"powered" = list(/datum/om/frame/machine/proc/fact_powered, CHANGE_MACHINE_POWER),
		"broken" = list(/datum/om/frame/machine/proc/fact_broken, CHANGE_MACHINE_BROKEN),
		"anchored" = list(/datum/om/frame/machine/proc/fact_anchored, CHANGE_MACHINE_ANCHORED),
	)

/datum/om/frame/machine/proc/fact_powered()
	var/obj/machinery/M = entity
	return !M.has_stat(NOPOWER)

/datum/om/frame/machine/proc/fact_broken()
	var/obj/machinery/M = entity
	return M.has_stat(BROKEN)

/datum/om/frame/machine/proc/fact_anchored()
	var/obj/machinery/M = entity
	return M.anchored

/// TRUE when the frame's machine is powered, whole and anchored.
/datum/om/frame/machine/proc/usable()
	return fact("powered") && !fact("broken") && fact("anchored")

/datum/om/stage/machine
	category = /datum/om/stage/machine
	pipeline = /datum/om/pipeline/machine
	of = /obj/machinery

/// What the machine does with its power each frame. The root has nothing to do.
/datum/om/stage/machine/power
	name = "power"
	order = 10
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_OCCUPANT | CHANGE_MACHINE_SETTINGS
	woken_by = "power_change(); atom_break()/atom_fix(); wrenching; inserting or removing what it works on; settings"

/datum/om/stage/machine/power/perform(obj/machinery/M, datum/om/frame/machine/F)
	return STAGE_IDLE

/datum/om/stage/machine/power/idle(obj/machinery/M)
	return TRUE

/// A machine's explicitly started work: its machine_step() every frame from MACHINE_WAKE() until it
/// returns PROCESS_KILL or MACHINE_SLEEP() ends it (step_active). This is the old SSmachines roster
/// contract, kept exact for the machines that moved off it: whatever gives the machine something to
/// do (a player's toggle, an item entering it, a timer, a gas watch it armed) wakes it, and the
/// machine says itself when it is done. Channels alone don't restart it, except for a machine that
/// ended its work with sleep_until_powered() (power and repair bring it back) and a type with
/// step_on_power_change (any power or break change runs one step to reconcile). Machines whose power
/// family variant already runs machine_step() on channels (power/step: atmospherics devices,
/// hydroponics) don't get this stage.
/datum/om/stage/machine/step
	name = "step"
	order = 15
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_SETTINGS | CHANGE_RELATED
	woken_by = "MACHINE_WAKE(): the machine's own producers; power_change()/atom_fix() after sleep_until_powered(); for a machine asleep on changes, a watched channel or its own settings"
	reads = list("step_active", "step_waiting_power", "speed_process")

/datum/om/stage/machine/step/applies(obj/machinery/M)
	var/datum/om/pipeline/P = om_registry().behaviour(/datum/om/pipeline/machine)
	for(var/datum/om/stage/V as anything in P.variants[/datum/om/stage/machine/power])
		if(istype(M, V.of))
			return !istype(V, /datum/om/stage/machine/power/step)
	return TRUE

/datum/om/stage/machine/step/perform(obj/machinery/M, datum/om/frame/machine/F)
	if(M.speed_process)
		return STAGE_IDLE
	if(!M.step_active)
		if(!isnull(M.react_sleep_tokens))
			M.cancel_sleep_keys()
		else if(!M.step_on_power_change && (!M.step_waiting_power || (!M.operable())))
			return STAGE_IDLE
		if(!sys_periodic_allows(M, MACHINE_PIPELINE))
			M.set_step_waiting_power(FALSE)
			return STAGE_IDLE
		M.set_step_active(TRUE)
	M.set_step_waiting_power(FALSE)
	if(M.machine_step() == PROCESS_KILL)
		M.set_step_active(FALSE)
	if(!M.step_active)
		return STAGE_IDLE

/// Idle exactly while it has no started work (or runs on the fast lane instead); a machine waiting
/// for power is idle only while it has none.
/datum/om/stage/machine/step/idle(obj/machinery/M)
	if(M.speed_process)
		return TRUE
	return !M.step_active && (!M.step_waiting_power || (!M.operable()))

/// The machine's look, after what changed it (CHANGE_MACHINE_OUTPUT). The root just updates.
/datum/om/stage/machine/present
	name = "present"
	order = 20
	wake_on = CHANGE_MACHINE_OUTPUT
	woken_by = "what the machine shows changed"

/datum/om/stage/machine/present/perform(obj/machinery/M, datum/om/frame/machine/F)
	M.update_icon()
	return STAGE_IDLE

/datum/om/stage/machine/present/idle(obj/machinery/M)
	return TRUE

// ---------------------------------------------------------------- APCs

// Rust runs the distributor and the APC's settings reach it through its generated push_to_rust(): the APC has
// no power stage of its own.

/// The APC draws through draw() (the refresh engine): its present stage has nothing to do. (The
/// generic one would call update_icon(), whose changed() mark wakes this pipeline again.)
/datum/om/stage/machine/present/apc
	of = /obj/machinery/power/apc

/datum/om/stage/machine/present/apc/perform(obj/machinery/power/apc/M, datum/om/frame/machine/F)
	return STAGE_IDLE

// ---------------------------------------------------------------- fire alarms

/// Hotspots are meant to reach an alarm without polling (nothing repeats the
/// detecting scan once armed); the only genuine per-tick work left is a
/// lockdown countdown that nothing in this fork currently starts (only the
/// sibling /obj/machinery/partyalarm has a live "timing" caller). There is no
/// publish/subscribe event for "world.time advanced", so a running countdown
/// rewakes on the pipeline's own cadence (MACHINE_PIPELINE_INTERVAL, 2s)
/// instead of a dedicated timer — the one rewake_delay fallback in this family.
/datum/om/stage/machine/power/firealarm
	of = /obj/machinery/firealarm
	reads = list("timing")

/datum/om/stage/machine/power/firealarm/perform(obj/machinery/firealarm/M, datum/om/frame/machine/F)
	if(!M.operable())
		return STAGE_IDLE

	if(M.timing)
		if(M.time > 0)
			M.time = max(M.time - (MACHINE_PIPELINE_INTERVAL / 10), 0)
		if(M.time <= 0)
			M.alarm()
			M.time = 0
			M.set_timing(0)

	if(M.detecting && (locate_within(M.loc, /obj/effect/hotspot)))
		M.alarm()

	// A running countdown is work every frame: returning STAGE_IDLE here would idle the stage
	// after one tick and strand the countdown (idle() says it still has work).
	if(!M.timing)
		return STAGE_IDLE

/// Settled once there's no countdown left running, or while unpowered/broken (power_change()
/// and atom_fix() wake it); a fresh alarm still gets one perform() before it parks.
/datum/om/stage/machine/power/firealarm/idle(obj/machinery/firealarm/M)
	return !M.timing || (!M.operable())

// ---------------------------------------------------------------- machine_step devices

/// The generic stage for a machine whose DM-side work is one machine_step() (machinery.dm): the
/// body its old process() had, run once per frame while it has work. PROCESS_KILL idles the stage
/// and the machine parks; it wakes on its channels, on MACHINE_WAKE() (which raises
/// CHANGE_EXPLICIT for a polls = FALSE machine, machines.dm), or on a gas watch it armed when it
/// settled (code/datums/om/watch.dm) -- never on a cadence it doesn't need.
/datum/om/stage/machine/power/step
	of = /obj/machinery/atmospherics
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_SETTINGS | CHANGE_MACHINE_GAS
	woken_by = "power_change(); atom_break()/atom_fix(); wrenching; settings and topology (MACHINE_WAKE()); its gas watch"
	reads = list("step_active")

/datum/om/stage/machine/power/step/perform(obj/machinery/M, datum/om/frame/machine/F)
	if(!sys_periodic_allows(M, MACHINE_PIPELINE))
		M.set_step_active(FALSE)
		return STAGE_IDLE
	M.set_step_active(M.machine_step() != PROCESS_KILL)
	if(!M.step_active)
		return STAGE_IDLE

/// Settled when it can't act (step_has_work(), each device's own eligibility rule) or when it is
/// parked on the gas watch that states that rule -- the watch is its wake producer. A parked device
/// with work and no armed watch is a lost wake, which the OM audit reports.
/datum/om/stage/machine/power/step/idle(obj/machinery/M)
	return om_watch_armed(M) || !M.step_has_work()

/// The distillery: every frame while on (heating, pumping beakers); off, it parks until toggled.
/datum/om/stage/machine/power/step/reagent_distillery
	of = /obj/machinery/portable_atmospherics/powered/reagent_distillery

// ---------------------------------------------------------------- declared fields (code/datums/om/fields.dm)
// What the machine stages read to decide there is work, and the channel each raises. Written only
// through the generated set_<name>() setters (or om_set()); stages that read them wake on them.

/// TRUE while machine_step() has work: set by MACHINE_WAKE(), cleared when machine_step() returns
/// PROCESS_KILL or by MACHINE_SLEEP(). The step stage idles while it is FALSE.
// ALLOW(base_vars): the existing step_active field (it was OM_FIELD_TYPED), now with a hand-written setter
/obj/machinery/var/tmp/step_active = FALSE
/// Registered on CHANGE_EXPLICIT, the channel that starts the step work: machine_wake() is the
/// writer that gives work, and it wakes the pipeline itself (om_wake()). The setter raises nothing on
/// the machine's own pipeline: its other writers are the step stages, mid-frame, and MACHINE_SLEEP(),
/// and neither gives any stage work. Raising it there woke the machine again after every frame that
/// ended its work (a sleeping machine woke once more for nothing).
OM_FIELD_SETTER(/obj/machinery, step_active, CHANGE_EXPLICIT)

/obj/machinery/proc/set_step_active(value)
	if(step_active == value)
		return FALSE
	step_active = value
	changed(src, 0)
	PUBLISH_CHANGE(src, "step_active")
	return TRUE
/// Set by sleep_until_powered(): power_change()/atom_fix() restart the step work.
OM_FIELD_TYPED(/obj/machinery, tmp, step_waiting_power, FALSE, CHANGE_MACHINE_POWER)
/// TRUE: machine_step() runs every 0.2 s on the fast periodic pipeline instead of the machine
/// pipeline (PERIODIC_FAST, code/datums/om/periodic.dm).
OM_FIELD(/obj/machinery, speed_process, FALSE, CHANGE_MACHINE_SETTINGS)

/// TRUE while the fire alarm's countdown runs.
OM_FIELD(/obj/machinery/firealarm, timing, 0, CHANGE_MACHINE_SETTINGS)
