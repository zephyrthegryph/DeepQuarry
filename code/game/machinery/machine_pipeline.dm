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
