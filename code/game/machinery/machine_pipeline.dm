// Machines on an object-model pipeline (doc/rewrite/object_model_core.md §A.10).
//
// A machine whose type is listed below runs /datum/om/pipeline/machine instead of SSmachines'
// polling roster: a power stage (what it does with its power, and its use_power mode) and a
// present stage (its icon), every MACHINE_PIPELINE_INTERVAL while either has work. Settled, both
// idle and the machine parks; a channel wakes it (CHANGE_MACHINE_*), raised by the base setters
// (power_change(), atom_break(), atom_fix()) and by each type's own producers. A type's behaviour
// is a variant of a base stage, resolved by type depth: power/recharger serves every recharger.

/// One machine frame per SSmachines-equivalent tick.
#define MACHINE_PIPELINE_INTERVAL (2 SECONDS)

/datum/om/decl/pipeline_machines
	of = list(
		/obj/machinery/recharger,
		/obj/machinery/cell_charger,
		/obj/machinery/power/apc,
		/obj/machinery/power/smes,
		/obj/machinery/firealarm,
		/obj/machinery/alarm,
		/obj/machinery/portable_atmospherics/canister,
	)
	behaviours = list(/datum/om/pipeline/machine)

/datum/om/pipeline/machine
	name = "machine"
	every = MACHINE_PIPELINE_INTERVAL
	lane = LANE_SIMULATION
	runlevels = RUNLEVEL_GAME | RUNLEVEL_POSTGAME
	stages = list(/datum/om/stage/machine)
	frame_type = /datum/om/frame/machine
	wake_all = CHANGE_EXPLICIT

/datum/om/frame/machine
	facts = list(
		"powered" = list(/datum/om/frame/machine/proc/fact_powered, CHANGE_MACHINE_POWER),
		"broken" = list(/datum/om/frame/machine/proc/fact_broken, CHANGE_MACHINE_BROKEN),
		"anchored" = list(/datum/om/frame/machine/proc/fact_anchored, CHANGE_MACHINE_ANCHORED),
	)

/datum/om/frame/machine/proc/fact_powered()
	var/obj/machinery/M = entity
	return !(M.stat & NOPOWER)

/datum/om/frame/machine/proc/fact_broken()
	var/obj/machinery/M = entity
	return M.stat & BROKEN

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

/datum/om/stage/machine/power/recharger/perform(obj/machinery/recharger/M, datum/om/frame/machine/F)
	if(!F.usable())
		M.update_use_power(USE_POWER_OFF)
		M.icon_state = M.icon_state_idle
		return STAGE_IDLE
	if(!M.charging)
		M.update_use_power(USE_POWER_IDLE)
		M.icon_state = M.icon_state_idle
		return STAGE_IDLE
	if(M.charging_complete())
		M.update_use_power(USE_POWER_IDLE)
		M.icon_state = M.icon_state_charged
		return STAGE_IDLE
	M.charge_step()

/// Settled: nothing to charge (or it can't), and the power mode already says so.
/datum/om/stage/machine/power/recharger/idle(obj/machinery/recharger/M)
	if((M.stat & (NOPOWER | BROKEN)) || !M.anchored)
		return M.use_power == USE_POWER_OFF
	if(!M.charging || M.charging_complete())
		return M.use_power == USE_POWER_IDLE
	return FALSE

// ---------------------------------------------------------------- cell chargers

/datum/om/stage/machine/power/cell_charger
	of = /obj/machinery/cell_charger

/datum/om/stage/machine/power/cell_charger/perform(obj/machinery/cell_charger/M, datum/om/frame/machine/F)
	if(!F.usable())
		M.update_use_power(USE_POWER_OFF)
		return STAGE_IDLE
	if(!M.charging || M.charging.fully_charged())
		M.update_use_power(USE_POWER_IDLE)
		return STAGE_IDLE
	var/newlevel = round(M.charging.percent() * 4.0 / 99)
	M.charging.give(M.efficiency * CELLRATE)
	M.update_use_power(USE_POWER_ACTIVE)
	if(M.chargelevel != newlevel)
		M.update_icon()

/datum/om/stage/machine/power/cell_charger/idle(obj/machinery/cell_charger/M)
	if((M.stat & (NOPOWER | BROKEN)) || !M.anchored)
		return M.use_power == USE_POWER_OFF
	if(!M.charging || M.charging.fully_charged())
		return M.use_power == USE_POWER_IDLE
	return FALSE

// ---------------------------------------------------------------- APCs

/// Rust runs the distributor; a wake resends the settings, and a power failure ends by rewake.
/datum/om/stage/machine/power/apc
	of = /obj/machinery/power/apc

/datum/om/stage/machine/power/apc/perform(obj/machinery/power/apc/M, datum/om/frame/machine/F)
	if(M.failure_until && world.time >= M.failure_until)
		M.failure_timer = 0
		M.failure_until = 0
		M.queue_icon_update()
		M.update()
	M.power_sync()
	return STAGE_IDLE

/datum/om/stage/machine/power/apc/rewake_delay(obj/machinery/power/apc/M)
	return M.failure_until > world.time ? M.failure_until - world.time : 0

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

/datum/om/stage/machine/power/firealarm/perform(obj/machinery/firealarm/M, datum/om/frame/machine/F)
	if(M.stat & (NOPOWER|BROKEN))
		return STAGE_IDLE

	if(M.timing)
		if(M.time > 0)
			M.time = max(M.time - (MACHINE_PIPELINE_INTERVAL / 10), 0)
		if(M.time <= 0)
			M.alarm()
			M.time = 0
			M.timing = 0

	if(M.detecting && (locate(/obj/effect/hotspot) in M.loc))
		M.alarm()

	return STAGE_IDLE

/// Settled once there's no countdown left running; a fresh alarm still gets
/// one perform() (from Initialize's first frame) before it parks.
/datum/om/stage/machine/power/firealarm/idle(obj/machinery/firealarm/M)
	return !M.timing

// ---------------------------------------------------------------- air alarms

/// The elected main alarm (per area) is the only one that scans and regulates;
/// followers park until elect_main_air_alarm() (an ownership change) wakes a
/// replacement. Gas wakes go through the alarm's own signature-diff
/// gas_dependency_changed() (air_alarm.dm) rather than om_watch_gas()
/// (code/datums/om/watch.dm): an air alarm's TLV table has several bands per
/// gas plus a temperature/pressure signature, and the existing
/// revision+signature compare already fires on exactly the crossings a band
/// set would — re-deriving that as generic bands would duplicate, not
/// improve, an already-tested check, for a device whose false-negative cost
/// (a missed atmosphere alarm) is unusually high. It reaches the OM pipeline
/// through the one bridge point: SSmachines' wake_gas_subscriber() and
/// elect_main_air_alarm() now call om_changed(A, CHANGE_MACHINE_GAS /
/// CHANGE_MACHINE_SETTINGS) instead of START_MACHINE_PROCESSING() once
/// A.polls is FALSE. Active temperature regulation has no "room reached
/// target" event, so it keeps running every pipeline tick (idle() below)
/// until scan_atmo() reports the room has settled.
/datum/om/stage/machine/power/alarm
	of = /obj/machinery/alarm
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_OCCUPANT | CHANGE_MACHINE_SETTINGS | CHANGE_MACHINE_GAS
	woken_by = "power_change(); atom_break()/atom_fix(); wire shorts; TLV/thermostat settings; elect_main_air_alarm(); a watched gas crossing"

/datum/om/stage/machine/power/alarm/perform(obj/machinery/alarm/M, datum/om/frame/machine/F)
	if(!M.alarm_area)
		return STAGE_IDLE
	var/obj/machinery/alarm/MA = M.alarm_area.main_air_alarm?.resolve()
	if(!MA)
		M.alarm_area.elect_main_air_alarm()
		MA = M.alarm_area.main_air_alarm?.resolve() // try again
	if(!MA || (M.stat & (NOPOWER|BROKEN)) || M.shorted || MA.shorted)
		SSmachines.hibernate_air_alarm(M)
		return STAGE_IDLE
	// Only the elected controller scans and regulates. The main alarm publishes
	// the area's danger/icon state to every display.
	if(MA != M)
		SSmachines.hibernate_air_alarm(M, FALSE)
		return STAGE_IDLE
	if(!get_turf(M))
		return STAGE_IDLE
	M.scan_atmo()
	if(!M.regulating_temperature)
		SSmachines.hibernate_air_alarm(M)
	return STAGE_IDLE

/datum/om/stage/machine/power/alarm/idle(obj/machinery/alarm/M)
	return !M.regulating_temperature

// ---------------------------------------------------------------- canisters

/// Only canister is on this pipeline (see the NOTE in portable_atmospherics.dm): the other
/// portable_atmospherics subtypes (powered/pump, powered/scrubber, hydroponics,
/// reagent_distillery) still have their own real process() overrides and stay polling.
///
/// Wakes on the valve, the holding tank and the connection (all raise
/// CHANGE_MACHINE_SETTINGS today; canister.dm), plus any gas change on either mixture it
/// touches through the existing subscribe_gas_dependency()/gas_dependency_changed() transport
/// (air_alarm.dm's neighbour section explains why that stays hand-rolled rather than becoming
/// om_watch_gas() bands here too: a canister's wake condition is "any composition, pressure or
/// temperature change", which is exactly what the dirty-mixture watch already delivers, not a
/// single threshold edge). hibernate_until_gas_changes() (unchanged) re-arms that subscription
/// every time perform() settles.
/datum/om/stage/machine/power/canister
	of = /obj/machinery/portable_atmospherics/canister
	wake_on = CHANGE_MACHINE_POWER | CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_ANCHORED | CHANGE_MACHINE_SETTINGS | CHANGE_MACHINE_GAS
	woken_by = "power_change(); atom_break()/atom_fix(); valve/label/eject topic actions; a subscribed gas mixture changing"

/datum/om/stage/machine/power/canister/perform(obj/machinery/portable_atmospherics/canister/M, datum/om/frame/machine/F)
	if(M.destroyed)
		M.om_settled = TRUE
		return STAGE_IDLE

	var/turf/canister_turf = get_turf(M)
	var/datum/gas_mixture/canister_environment = canister_turf ? canister_turf.return_air() : null
	M.material_observe_gases(M.air_contents, canister_environment)

	var/reaction_result = M.react_or_update()
	var/material_active = M.process_material_vessel()
	if(M.destroyed)
		M.om_settled = TRUE
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

	M.om_settled = !M.valve_open && reaction_result == NO_REACTION && !material_active
	if(M.om_settled)
		M.hibernate_until_gas_changes()
	return STAGE_IDLE

/datum/om/stage/machine/power/canister/idle(obj/machinery/portable_atmospherics/canister/M)
	return M.om_settled
