// Machines on an object-model pipeline (doc/rewrite/object_model_core.md §A.10).
//
// Every machine with DM-side periodic work runs /datum/om/pipeline/machine (SSmachines no longer
// polls anything): a power stage (what it does with its power, and its use_power mode), a step
// stage (its machine_step(), for machines whose work is started and stopped explicitly) and a
// present stage (its icon), every MACHINE_PIPELINE_INTERVAL while any has work. Settled, all idle
// and the machine parks; a channel wakes it (CHANGE_MACHINE_*), raised by the base setters
// (power_change(), atom_break(), atom_fix()) and by each type's own producers, or MACHINE_WAKE().
// A type's behaviour is a variant of a base stage, resolved by type depth: power/recharger serves
// every recharger.

/// One machine frame per machine service interval (MACHINE_SERVICE_INTERVAL).
#define MACHINE_PIPELINE_INTERVAL MACHINE_SERVICE_INTERVAL

/datum/om/decl/pipeline_machines
	of = list(
		/obj/machinery/recharger,
		/obj/machinery/cell_charger,
		/obj/machinery/power/apc,
		/obj/machinery/power/smes,
		/obj/machinery/firealarm,
		/obj/machinery/alarm,
		/obj/machinery/portable_atmospherics/canister,
		/obj/machinery/portable_atmospherics/powered/pump,
		/obj/machinery/portable_atmospherics/powered/scrubber,
		// Atmospherics devices with DM-side work (the "machine_step" section below). Devices whose
		// flow law is a Rust device edge (vent pumps and scrubbers, pumps, valves, passive gates)
		// and plain pipes have no DM work at all and don't join.
		/obj/machinery/atmospherics/unary/freezer,
		/obj/machinery/atmospherics/unary/heater,
		/obj/machinery/atmospherics/unary/heat_exchanger,
		/obj/machinery/atmospherics/unary/outlet_injector,
		/obj/machinery/atmospherics/unary/cryo_cell,
		/obj/machinery/atmospherics/binary/dp_vent_pump,
		/obj/machinery/atmospherics/binary/algae_farm,
		/obj/machinery/atmospherics/omni,
		/obj/machinery/atmospherics/trinary/atmos_filter,
		/obj/machinery/atmospherics/trinary/mixer,
		/obj/machinery/atmospherics/portables_connector,
		/obj/machinery/atmospherics/pipeturbine,
		/obj/machinery/atmospherics/pipe/simple/heat_exchanging,
		/obj/machinery/power/turbinemotor,
		/obj/machinery/power/thermoregulator,
		/obj/machinery/air_sensor,
		/obj/machinery/meter,
		/obj/machinery/computer/general_air_control/fuel_injection,
		/obj/machinery/portable_atmospherics/hydroponics,
		/obj/machinery/portable_atmospherics/powered/reagent_distillery,
		// Every other machine with machine_step() work (roadmap S5: the old SSmachines roster).
		// Each joins asleep: one frame at Initialize to find out whether it has work, then it
		// parks until MACHINE_WAKE() (tools/ci/pollers_lint.py checks this list is complete).
		/obj/machinery/abstract_grub_machine,
		/obj/machinery/ai_powersupply,
		/obj/machinery/airlock_sensor,
		/obj/machinery/anomaly_harvester,
		/obj/machinery/appliance,
		/obj/machinery/artifact,
		/obj/machinery/artifact_analyser,
		/obj/machinery/artifact_harvester,
		/obj/machinery/atm,
		/obj/machinery/auto_cloner,
		/obj/machinery/beehive,
		/obj/machinery/bluespace_beacon,
		/obj/machinery/bomb_tester,
		/obj/machinery/botany,
		/obj/machinery/bunsen_burner,
		/obj/machinery/chemical_dispenser,
		/obj/machinery/chemical_synthesizer,
		/obj/machinery/clonepod,
		/obj/machinery/compressor,
		/obj/machinery/computer/HolodeckControl,
		/obj/machinery/computer/aifixer,
		/obj/machinery/computer/cloning,
		/obj/machinery/computer/operating,
		/obj/machinery/computer/pod,
		/obj/machinery/computer/power_monitor,
		/obj/machinery/computer/security/telescreen/bodycamera,
		/obj/machinery/computer/ship/helm,
		/obj/machinery/computer/ship/sensors,
		/obj/machinery/conveyor,
		/obj/machinery/conveyor_switch,
		/obj/machinery/cryopod,
		/obj/machinery/disposal,
		/obj/machinery/dnaforensics,
		/obj/machinery/door/firedoor,
		/obj/machinery/door_timer,
		/obj/machinery/drone_fabricator,
		/obj/machinery/embedded_controller,
		/obj/machinery/exonet_node,
		/obj/machinery/feeder,
		/obj/machinery/field_generator,
		/obj/machinery/floodlight,
		/obj/machinery/floor_light,
		/obj/machinery/food_replicator,
		/obj/machinery/fusion_fuel_injector,
		/obj/machinery/gravity_generator/main,
		/obj/machinery/hologram/holopad,
		/obj/machinery/igniter,
		/obj/machinery/iv_drip,
		/obj/machinery/magnetic_controller,
		/obj/machinery/magnetic_module,
		/obj/machinery/mech_recharger,
		/obj/machinery/mecha_part_fabricator_tg,
		/obj/machinery/media/jukebox,
		/obj/machinery/message_server,
		/obj/machinery/mineral/processing_unit,
		/obj/machinery/mineral/stacking_machine,
		/obj/machinery/mineral/unloading_machine,
		/obj/machinery/mining/drill,
		/obj/machinery/ntnet_relay,
		/obj/machinery/nuclearbomb,
		/obj/machinery/optable,
		/obj/machinery/oxygen_pump,
		/obj/machinery/paradoxrift,
		/obj/machinery/particle_accelerator/control_box,
		/obj/machinery/particle_smasher,
		/obj/machinery/partslathe,
		/obj/machinery/pda_multicaster,
		/obj/machinery/pointdefense,
		/obj/machinery/porta_turret,
		/obj/machinery/power/debug_items/infinite_cable_powersink,
		/obj/machinery/power/debug_items/infinite_generator,
		/obj/machinery/power/emitter,
		/obj/machinery/power/fusion_core,
		/obj/machinery/power/generator,
		/obj/machinery/power/hydromagnetic_trap,
		/obj/machinery/power/port_gen,
		/obj/machinery/power/rtg,
		/obj/machinery/power/sensor,
		/obj/machinery/power/shield_generator,
		/obj/machinery/power/singularity_beacon,
		/obj/machinery/power/solar_control,
		/obj/machinery/power/supermatter,
		/obj/machinery/power/supply_beacon,
		/obj/machinery/power/turbine,
		/obj/machinery/pump,
		/obj/machinery/radiocarbon_spectrometer,
		/obj/machinery/reagent_refinery,
		/obj/machinery/recharge_station,
		/obj/machinery/recycling,
		/obj/machinery/replicator,
		/obj/machinery/seed_storage,
		/obj/machinery/shield/malfai,
		/obj/machinery/shield_capacitor,
		/obj/machinery/shield_diffuser,
		/obj/machinery/shield_gen,
		/obj/machinery/shieldgen,
		/obj/machinery/shieldwall,
		/obj/machinery/shieldwallgen,
		/obj/machinery/shipsensors,
		/obj/machinery/shower,
		/obj/machinery/shuttle_sensor,
		/obj/machinery/sleeper,
		/obj/machinery/smartfridge,
		/obj/machinery/space_heater,
		/obj/machinery/station_map,
		/obj/machinery/suit_cycler,
		/obj/machinery/suspension_gen,
		/obj/machinery/telecomms,
		/obj/machinery/the_singularitygen,
		/obj/machinery/transhuman/synthprinter,
		/obj/machinery/transportpod,
		/obj/machinery/v_garbosystem,
		/obj/machinery/vending,
		/obj/machinery/vitals_monitor,
		/obj/machinery/vr_sleeper,
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
	// every subsystem (machine_first_wakes_flush()), before the first air fire, instead of
	// thousands of zero-delay timers draining for minutes after the round starts.
	if(GLOB.machine_first_wakes_bulk)
		rel_add(om_global_owner(), "machine_first_wakes", M)
		return
	after_slot(M, "first_wake", 0, /obj/machinery/proc/materialize_wakes)

/// Machines waiting for the boot bulk first-wake pass, in join order. A relation list on the global
/// owner: a deleted machine drops out on its own (its relation teardown), nothing takes it out.
/datum/om/global_owner/var/list/obj/machinery/machine_first_wakes
REL_LIST(/datum/om/global_owner, machine_first_wakes)
/// TRUE until the MC finishes initializing; while set, on_start() queues first wakes in bulk.
GLOBAL_VAR_INIT(machine_first_wakes_bulk, TRUE)

/// Runs every queued machine's first wake (arm_wakes() and its start condition) in one pass. The MC
/// calls it once every subsystem has initialized (pipenets and air exist, so gas watches can
/// arm), before the first air fire. Machines that join later use their `first_wake` timer slot.
/proc/machine_first_wakes_flush()
	GLOB.machine_first_wakes_bulk = FALSE
	var/datum/om/global_owner/owner = om_global_owner()
	var/list/queued = owner.machine_first_wakes?.Copy() || list()
	// Emptied up front: each materialize_wakes() then leaves an empty queue in O(1).
	rel_clear(owner, "machine_first_wakes")
	var/start = REALTIMEOFDAY
	var/ran = 0
	for(var/obj/machinery/M as anything in queued)
		if(QDELETED(M))
			continue
		M.materialize_wakes()
		ran++
	log_world("Machine first wakes: [ran] of [length(queued)] armed in bulk in [(REALTIMEOFDAY - start) / 10] s")

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

// ---------------------------------------------------------------- rechargers

/datum/om/stage/machine/power/recharger
	of = /obj/machinery/recharger
	reads = list("charging")

/datum/om/stage/machine/power/recharger/perform(obj/machinery/recharger/M, datum/om/frame/machine/F)
	if(!F.usable())
		M.set_use_power(USE_POWER_OFF)
		M.icon_state = M.icon_state_idle
		return STAGE_IDLE
	if(!M.charging)
		M.set_use_power(USE_POWER_IDLE)
		M.icon_state = M.icon_state_idle
		return STAGE_IDLE
	if(M.charging_complete())
		M.set_use_power(USE_POWER_IDLE)
		M.icon_state = M.icon_state_charged
		return STAGE_IDLE
	M.charge_step()

/// Settled: nothing to charge (or it can't), and the power mode already says so.
/datum/om/stage/machine/power/recharger/idle(obj/machinery/recharger/M)
	if((!M.operable()) || !M.anchored)
		return M.use_power == USE_POWER_OFF
	if(!M.charging || M.charging_complete())
		return M.use_power == USE_POWER_IDLE
	return FALSE

// ---------------------------------------------------------------- cell chargers

/datum/om/stage/machine/power/cell_charger
	of = /obj/machinery/cell_charger
	reads = list("charging")

/datum/om/stage/machine/power/cell_charger/perform(obj/machinery/cell_charger/M, datum/om/frame/machine/F)
	if(!F.usable())
		M.set_use_power(USE_POWER_OFF)
		return STAGE_IDLE
	if(!M.charging || M.charging.fully_charged())
		M.set_use_power(USE_POWER_IDLE)
		return STAGE_IDLE
	var/newlevel = round(M.charging.percent() * 4.0 / 99)
	M.charging.give(M.efficiency * CELLRATE)
	M.set_use_power(USE_POWER_ACTIVE)
	if(M.chargelevel != newlevel)
		M.update_icon()

/datum/om/stage/machine/power/cell_charger/idle(obj/machinery/cell_charger/M)
	if((!M.operable()) || !M.anchored)
		return M.use_power == USE_POWER_OFF
	if(!M.charging || M.charging.fully_charged())
		return M.use_power == USE_POWER_IDLE
	return FALSE

// ---------------------------------------------------------------- APCs

/// Rust runs the distributor; a wake resends the settings, and a power failure ends by rewake.
/datum/om/stage/machine/power/apc
	of = /obj/machinery/power/apc

/datum/om/stage/machine/power/apc/perform(obj/machinery/power/apc/M, datum/om/frame/machine/F)
	if(M.failure_until && EXPIRY_EXPIRED(M, failure_until, CLOCK_WORLD))
		M.failure_timer = 0
		M.failure_until = 0
		M.queue_icon_update()
		M.update()
	M.power_sync()
	return STAGE_IDLE

/datum/om/stage/machine/power/apc/rewake_delay(obj/machinery/power/apc/M)
	return EXPIRY_LEFT(M, failure_until, CLOCK_WORLD)

/// Icon updates, at most every APC_UPDATE_ICON_COOLDOWN.
/datum/om/stage/machine/present/apc
	of = /obj/machinery/power/apc
	min_interval = APC_UPDATE_ICON_COOLDOWN

/datum/om/stage/machine/present/apc/perform(obj/machinery/power/apc/M, datum/om/frame/machine/F)
	M.icon_renderer?.apply(M)
	return STAGE_IDLE

// ---------------------------------------------------------------- SMES

/// Rust charges and discharges; the unit's own power_step() does the rest (buildable units
/// with a cut grounding wire, hybrids and battery racks keep working every frame).
/datum/om/stage/machine/power/smes
	of = /obj/machinery/power/smes

/datum/om/stage/machine/power/smes/perform(obj/machinery/power/smes/M, datum/om/frame/machine/F)
	return M.power_step()

/datum/om/stage/machine/power/smes/idle(obj/machinery/power/smes/M)
	return M.power_settled()

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

// ---------------------------------------------------------------- air alarms

/// The elected main alarm (per area) is the only one that scans and regulates;
/// followers park until elect_main_air_alarm() (an ownership change) wakes a
/// replacement. Gas wakes go through om_watch_arm_value() (air_alarm.dm
/// register_gas_dependencies(), code/datums/om/watch.dm): an air alarm's TLV table has several
/// bands per gas plus a temperature/pressure signature, condensed into one comparable
/// atmospheric_control_signature() value so the watch fires only on exactly the crossings a
/// full band set would, not on every harmless room-air diffusion tick. Active temperature
/// regulation has no "room reached target" event, so it keeps running every pipeline tick
/// (idle() below) until scan_atmo() reports the room has settled.
/datum/om/stage/machine/power/alarm
	of = /obj/machinery/alarm
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_OCCUPANT | CHANGE_MACHINE_GAS
	woken_by = "power_change(); atom_break()/atom_fix(); wire shorts; TLV/thermostat settings; elect_main_air_alarm(); a watched gas crossing"
	reads = list("regulating_temperature")

/datum/om/stage/machine/power/alarm/perform(obj/machinery/alarm/M, datum/om/frame/machine/F)
	if(!M.alarm_area_ref())
		return STAGE_IDLE
	var/obj/machinery/alarm/MA = M.alarm_area_ref().main_air_alarm
	if(!MA)
		M.alarm_area_ref().elect_main_air_alarm()
		MA = M.alarm_area_ref().main_air_alarm // try again
	if(!MA || (!M.operable()) || M.shorted || MA.shorted)
		M.register_gas_dependencies()
		return STAGE_IDLE
	// Only the elected controller scans and regulates. The main alarm publishes
	// the area's danger/icon state to every display.
	if(MA != M)
		M.unregister_gas_dependencies()
		return STAGE_IDLE
	if(!get_turf(M))
		return STAGE_IDLE
	M.scan_atmo()
	if(!M.regulating_temperature)
		M.register_gas_dependencies()
	return STAGE_IDLE

/// Settled unless it is the area's working controller with regulation running: a follower,
/// an unpowered/broken/shorted alarm or one with no area parks even if it was mid-regulation
/// when it lost control (an election, a short or a power cut wakes it back up).
/datum/om/stage/machine/power/alarm/idle(obj/machinery/alarm/M)
	if(!M.regulating_temperature)
		return TRUE
	if(M.has_stat(NOPOWER|BROKEN) || M.shorted || !get_turf(M))
		return TRUE
	var/area/A = M.alarm_area_ref()
	if(!A)
		return TRUE
	var/obj/machinery/alarm/MA = A.main_air_alarm
	return !MA || MA != M || MA.shorted

// ---------------------------------------------------------------- canisters

/// Only canister is on this pipeline (see the NOTE in portable_atmospherics.dm): the other
/// portable_atmospherics subtypes (powered/pump, powered/scrubber, hydroponics,
/// reagent_distillery) still have their own real process() overrides and stay polling.
///
/// Wakes on the valve, the holding tank and the connection (all raise
/// CHANGE_MACHINE_SETTINGS today; canister.dm), plus a gas watch armed by
/// hibernate_until_gas_changes() (portable_atmospherics.dm/canister.dm, code/datums/om/watch.dm)
/// every time perform() settles: "any change" while free-standing or connected with the valve
/// open (the canister's own react_or_update()/pipenet membership needs to re-run on literally
/// any composition/pressure/temperature change), or a value watch on desired_update_flag() while
/// closed and pipenet-connected (only the displayed gauge band matters then).
/datum/om/stage/machine/power/canister
	of = /obj/machinery/portable_atmospherics/canister
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_GAS
	woken_by = "power_change(); atom_break()/atom_fix(); valve/label/eject topic actions; a subscribed gas mixture changing"
	reads = list("om_settled", "valve_open")

/datum/om/stage/machine/power/canister/perform(obj/machinery/portable_atmospherics/canister/M, datum/om/frame/machine/F)
	if(M.destroyed)
		M.set_om_settled(TRUE)
		return STAGE_IDLE

	var/turf/canister_turf = get_turf(M)
	var/datum/gas_mixture/canister_environment = canister_turf ? canister_turf.return_air() : null
	M.material_observe_gases(M.air_contents, canister_environment)

	var/reaction_result = M.react_or_update()
	var/material_active = M.process_material_vessel()
	if(M.destroyed)
		M.set_om_settled(TRUE)
		return STAGE_IDLE

	if(M.valve_open)
		var/datum/gas_mixture/environment = M.holding ? M.holding.air_contents : M.loc.return_air()
		var/env_pressure = environment.return_pressure()
		var/pressure_delta = M.release_pressure - env_pressure

		if((M.air_contents.return_temperature() > 0) && (pressure_delta > 0))
			var/transfer_moles = calculate_transfer_moles(M.air_contents, environment, pressure_delta)
			transfer_moles = min(transfer_moles, (M.release_flow_rate/M.air_contents.return_volume())*M.air_contents.total_moles()) //flow rate limit

			var/returnval = pump_gas_passive(M, M.air_contents, environment, transfer_moles)
			if(returnval >= 0)
				M.update_icon()
				// pump_gas_passive directly mutates the turf's air mix via the gas_mixture
				// reference returned by loc.return_air(); it doesn't know what type of sink
				// it's writing to, so it can't enroll a turf in SSair.active_turfs. Without
				// this, under LINDA the gas lands on the turf but never spreads (active_turfs
				// stays empty) and the gas overlay never updates (update_visuals is never
				// called).
				if(!M.holding && isturf(M.loc))
					var/turf/open/T = M.loc
					if(istype(T))
						T.update_visuals()
						T.air_update_turf(FALSE, FALSE)

	M.can_label = M.air_contents.return_pressure() < 1

	M.set_om_settled(!M.valve_open && reaction_result == NO_REACTION && !material_active)
	if(M.om_settled)
		M.hibernate_until_gas_changes()
		return STAGE_IDLE
	// Unsettled (open valve, a reaction, material work): keep running every frame. An
	// unconditional STAGE_IDLE idled the stage with work left and set_om_settled() raises
	// nothing on a repeat, so the canister parked mid-release (OM_AUDIT missed wake).

/datum/om/stage/machine/power/canister/idle(obj/machinery/portable_atmospherics/canister/M)
	return M.om_settled

// ---------------------------------------------------------------- portable pumps and scrubbers

/// Neither device ever hibernates on its own: both keep running every tick while `on`, exactly
/// as their old process() did (no "target pressure reached" event exists), and idle() is simply
/// `!on`. `huge` subtypes are NOT migrated (they keep their own real process() override that
/// checks anchored/power every tick regardless of `on`) and set polls = TRUE back to opt out of
/// this pipeline's parent-type registration; they still get a (harmless, permanently-idle)
/// generic /datum/om/stage/machine/power frame alongside their unaffected SSmachines polling.
/datum/om/stage/machine/power/portable_pump
	of = /obj/machinery/portable_atmospherics/powered/pump
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED
	woken_by = "power_change(); atom_break()/atom_fix(); the power toggle; an EMP"
	reads = list("on")

/datum/om/stage/machine/power/portable_pump/perform(obj/machinery/portable_atmospherics/powered/pump/M, datum/om/frame/machine/F)
	M.pump_step()
	return STAGE_IDLE

/datum/om/stage/machine/power/portable_pump/idle(obj/machinery/portable_atmospherics/powered/pump/M)
	return !M.on

/datum/om/stage/machine/power/portable_scrubber
	of = /obj/machinery/portable_atmospherics/powered/scrubber
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED
	woken_by = "power_change(); atom_break()/atom_fix(); the power toggle; an EMP"
	reads = list("on")

/datum/om/stage/machine/power/portable_scrubber/perform(obj/machinery/portable_atmospherics/powered/scrubber/M, datum/om/frame/machine/F)
	M.scrubber_step()
	return STAGE_IDLE

/datum/om/stage/machine/power/portable_scrubber/idle(obj/machinery/portable_atmospherics/powered/scrubber/M)
	return !M.on

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

/datum/om/stage/machine/power/step/turbinemotor
	of = /obj/machinery/power/turbinemotor

/datum/om/stage/machine/power/step/thermoregulator
	of = /obj/machinery/power/thermoregulator

/datum/om/stage/machine/power/step/air_sensor
	of = /obj/machinery/air_sensor

/datum/om/stage/machine/power/step/meter
	of = /obj/machinery/meter

/// Runs every frame while its automation is on (it re-reads the latest sensor broadcasts and
/// commands the injectors) -- the one timed machine_step here; off, it parks.
/datum/om/stage/machine/power/step/fuel_injection
	of = /obj/machinery/computer/general_air_control/fuel_injection

/// The stationary "huge" portable pump/scrubber: their own machine_step() (anchored/power checks
/// every frame while on), not the base portable pump/scrubber stages above.
/datum/om/stage/machine/power/step/huge_pump
	of = /obj/machinery/portable_atmospherics/powered/pump/huge

/datum/om/stage/machine/power/step/huge_scrubber
	of = /obj/machinery/portable_atmospherics/powered/scrubber/huge

/// Hydroponics trays: a frame per growth cycle while something is growing or soaking in; between
/// cycles the tray parks on its growth timer (schedule_growth_wake()), and reagent or seed changes
/// wake it through MACHINE_WAKE().
/datum/om/stage/machine/power/step/hydroponics
	of = /obj/machinery/portable_atmospherics/hydroponics

/// The distillery: every frame while on (heating, pumping beakers); off, it parks until toggled.
/datum/om/stage/machine/power/step/reagent_distillery
	of = /obj/machinery/portable_atmospherics/powered/reagent_distillery

// ---------------------------------------------------------------- declared fields (code/datums/om/fields.dm)
// What the machine stages read to decide there is work, and the channel each raises. Written only
// through the generated set_<name>() setters (or om_set()); stages that read them wake on them.

/// TRUE while machine_step() has work: set by MACHINE_WAKE(), cleared when machine_step() returns
/// PROCESS_KILL or by MACHINE_SLEEP(). The step stage idles while it is FALSE.
OM_FIELD_TYPED(/obj/machinery, tmp, step_active, FALSE, CHANGE_EXPLICIT)
/// Set by sleep_until_powered(): power_change()/atom_fix() restart the step work.
OM_FIELD_TYPED(/obj/machinery, tmp, step_waiting_power, FALSE, CHANGE_MACHINE_POWER)
/// TRUE: machine_step() runs every 0.2 s on the fast periodic pipeline instead of the machine
/// pipeline (PERIODIC_FAST, code/datums/om/periodic.dm).
OM_FIELD(/obj/machinery, speed_process, FALSE, CHANGE_MACHINE_SETTINGS)

/// The item being recharged.
OM_FIELD_TYPED(/obj/machinery/recharger, obj/item, charging, null, CHANGE_MACHINE_OCCUPANT)
OWN(/obj/machinery/recharger, charging, OWN_SPILL)
/// The cell being charged.
OM_FIELD_TYPED(/obj/machinery/cell_charger, obj/item/cell, charging, null, CHANGE_MACHINE_OCCUPANT)
/// TRUE while the fire alarm's countdown runs.
OM_FIELD(/obj/machinery/firealarm, timing, 0, CHANGE_MACHINE_SETTINGS)
/// Heating/cooling mode of the air alarm's thermostat (0 off).
OM_FIELD(/obj/machinery/alarm, regulating_temperature, 0, CHANGE_MACHINE_SETTINGS)
/// The canister's release valve.
OM_FIELD(/obj/machinery/portable_atmospherics/canister, valve_open, 0, CHANGE_MACHINE_SETTINGS)
/// TRUE while the canister has nothing to do; until arm_wakes() or a frame says otherwise.
OM_FIELD(/obj/machinery/portable_atmospherics/canister, om_settled, TRUE, CHANGE_MACHINE_SETTINGS)
