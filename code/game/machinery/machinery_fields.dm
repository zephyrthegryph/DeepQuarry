// Core machine state as declared fields (doc/rewrite/systems.md §2).
//
// Every write goes through the generated setter (set_on(), set_locked(), set_stat(), ...), which
// raises the channel only on a real change; tools/ci/sys_rules/fields.py and field_write_lint.py
// reject direct writes. operable() is the one reader for "powered and working".

// on: instance storage belongs to the machine families that use it.
/obj/machinery/access_button/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/access_button, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/air_sensor/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/air_sensor, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/airlock_sensor/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/airlock_sensor, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/cablelayer/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/cablelayer, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/embedded_controller/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/embedded_controller, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/exonet_node/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/exonet_node, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/floodlight/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/floodlight, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/floor_light/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/floor_light, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/floorlayer/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/floorlayer, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/igniter/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/igniter, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/ion_engine/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/ion_engine, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/light/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/light, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/light_switch/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/light_switch, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/magnetic_module/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/magnetic_module, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/mech_sensor/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/mech_sensor, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/pda_multicaster/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/pda_multicaster, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/pipelayer/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/pipelayer, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/pump/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/pump, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/shower/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/shower, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/atmospherics/portables_connector/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/atmospherics/portables_connector, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/gravity_generator/main/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/gravity_generator/main, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/portable_atmospherics/powered/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/portable_atmospherics/powered, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/breakerbox/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/power/breakerbox, on, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/thermoregulator/var/on = FALSE
TRACKED_BRIDGED(/obj/machinery/power/thermoregulator, on, CHANGE_MACHINE_SETTINGS)
/datum/scheduler_field_definition/obj/machinery/on
	of = /obj/machinery
	field = "on"
	channel = CHANGE_MACHINE_SETTINGS
// active: instance storage belongs to the machine families that use it.
/obj/machinery/botany/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/botany, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/button/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/button, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/field_generator/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/field_generator, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/giga_drill/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/giga_drill, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/keycard_auth/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/keycard_auth, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/message_server/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/message_server, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/particle_accelerator/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/particle_accelerator, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/pointdefense/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/pointdefense, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/shield_capacitor/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/shield_capacitor, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/shield_gen/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/shield_gen, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/shieldgen/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/shieldgen, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/shieldwall/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/shieldwall, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/shieldwallgen/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/shieldwallgen, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/suit_cycler/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/suit_cycler, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/vending/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/vending, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/computer/HolodeckControl/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/computer/HolodeckControl, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/mineral/processing_unit/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/mineral/processing_unit, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/mining/drill/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/mining/drill, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/emitter/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/power/emitter, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/hydromagnetic_trap/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/power/hydromagnetic_trap, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/port_gen/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/power/port_gen, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/rad_collector/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/power/rad_collector, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/singularity_beacon/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/power/singularity_beacon, active, CHANGE_MACHINE_SETTINGS)
/obj/machinery/door/airlock/uranium/var/active = FALSE
TRACKED_BRIDGED(/obj/machinery/door/airlock/uranium, active, CHANGE_MACHINE_SETTINGS)
/datum/scheduler_field_definition/obj/machinery/active
	of = /obj/machinery
	field = "active"
	channel = CHANGE_MACHINE_SETTINGS
/datum/scheduler_field_definition/obj/machinery/state
	of = /obj/machinery
	field = "state"
	channel = CHANGE_MACHINE_SETTINGS
// mode: instance storage belongs to the machine families that use it.
/obj/machinery/ai_status_display/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/ai_status_display, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/alarm/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/alarm, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/chem_master/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/chem_master, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/disposal/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/disposal, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/iv_drip/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/iv_drip, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/status_display/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/status_display, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/computer/card/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/computer/card, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/computer/cryopod/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/computer/cryopod, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/computer/guestpass/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/computer/guestpass, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/thermoregulator/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/power/thermoregulator, mode, CHANGE_MACHINE_SETTINGS)
/obj/machinery/power/smes/batteryrack/var/mode = 0
TRACKED_BRIDGED(/obj/machinery/power/smes/batteryrack, mode, CHANGE_MACHINE_SETTINGS)
/datum/scheduler_field_definition/obj/machinery/mode
	of = /obj/machinery
	field = "mode"
	channel = CHANGE_MACHINE_SETTINGS
// locked: instance storage belongs to the machine families that use it.
/obj/machinery/ai_slipper/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/ai_slipper, locked, CHANGE_MACHINE_MODE)
/obj/machinery/bodyscanner/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/bodyscanner, locked, CHANGE_MACHINE_MODE)
/obj/machinery/cash_register/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/cash_register, locked, CHANGE_MACHINE_MODE)
/obj/machinery/clonepod/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/clonepod, locked, CHANGE_MACHINE_MODE)
/obj/machinery/dna_scannernew/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/dna_scannernew, locked, CHANGE_MACHINE_MODE)
/obj/machinery/navbeacon/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/navbeacon, locked, CHANGE_MACHINE_MODE)
/obj/machinery/shield_capacitor/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/shield_capacitor, locked, CHANGE_MACHINE_MODE)
/obj/machinery/shield_gen/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/shield_gen, locked, CHANGE_MACHINE_MODE)
/obj/machinery/shieldgen/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/shieldgen, locked, CHANGE_MACHINE_MODE)
/obj/machinery/shieldwallgen/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/shieldwallgen, locked, CHANGE_MACHINE_MODE)
/obj/machinery/smartfridge/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/smartfridge, locked, CHANGE_MACHINE_MODE)
/obj/machinery/suit_cycler/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/suit_cycler, locked, CHANGE_MACHINE_MODE)
/obj/machinery/suspension_gen/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/suspension_gen, locked, CHANGE_MACHINE_MODE)
/obj/machinery/computer/rdconsole_tg/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/computer/rdconsole_tg, locked, CHANGE_MACHINE_MODE)
/obj/machinery/deployable/barrier/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/deployable/barrier, locked, CHANGE_MACHINE_MODE)
/obj/machinery/door/unpowered/var/locked = FALSE
TRACKED_BRIDGED(/obj/machinery/door/unpowered, locked, CHANGE_MACHINE_MODE)

/// Machine conditions are stats held by sources (code/contracts/ids/stats.dm):
///   has_power      false while the area's channel is dark (area_gives_power(): the grid's reading) or SRC_GRID holds it (set_grid_power(), a shim)
///   intact         false while SRC_DAMAGE holds it (atom_break() until atom_fix())
///   in_maintenance true while SRC_MAINTENANCE holds it (an open service hatch: set_maintenance())
///   switched_on    false while SRC_SWITCH holds it (the machine's own switch: set_switched_on())
/// and a pulse is a timed SRC_EMP hold on STAT_OPERABLE (emp_disable()). STAT_OPERABLE is the machine working. The named readers below say each in
/// one word. There is no `stat` var on a machine: watchers use on_change(STAT_OPERABLE) and the "stat" key is only what the conditions publish.
/// The channels the conditions raise, as the look's watch list names them ("stat"). The machine has no var of that name any more: the field is only the
/// channel mask the conditions' announcements raise.
/datum/scheduler_field_definition/obj/machinery/stat
	of = /obj/machinery
	field = "stat"
	channel = CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_POWER

READS_AS(/obj/machinery/proc/power_lost, MACHINE_KEY_STAT)
/obj/machinery/proc/power_lost()
	return !stat_value(src, STAT_HAS_POWER)

READS_AS(/obj/machinery/proc/broken_now, MACHINE_KEY_STAT)
/obj/machinery/proc/broken_now()
	return !stat_value(src, STAT_INTACT)

READS_AS(/obj/machinery/proc/under_maintenance, MACHINE_KEY_STAT)
/obj/machinery/proc/under_maintenance()
	return !!stat_value(src, STAT_IN_MAINTENANCE)

READS_AS(/obj/machinery/proc/switched_off, MACHINE_KEY_STAT)
/obj/machinery/proc/switched_off()
	return !stat_value(src, STAT_SWITCHED_ON)

/// A pulse is holding it down now.
READS_AS(/obj/machinery/proc/emp_held, MACHINE_KEY_STAT)
/obj/machinery/proc/emp_held()
	return emp_disabled(src)

/// Anything wrong at all: no power, broken, in maintenance, switched off or pulsed.
READS_AS(/obj/machinery/proc/has_condition, MACHINE_KEY_STAT)
/obj/machinery/proc/has_condition()
	return power_lost() || broken_now() || under_maintenance() || switched_off() || emp_held()

/// Whether `condition` (a condition stat) is in force now: has_power, intact and switched_on are in force while false, in_maintenance while true.
/obj/machinery/proc/condition_in_force(condition)
	if(condition == STAT_IN_MAINTENANCE)
		return !!stat_value(src, condition)
	return !stat_value(src, condition)

/// Places or releases `source`'s hold on `condition` (a condition stat) and tells the watchers. `held` is the condition being in force. TRUE when it changed.
/obj/machinery/proc/condition_hold(condition, source, held, bit, channel)
	var/was = condition_in_force(condition)
	if(held)
		hold(src, condition, (condition == STAT_IN_MAINTENANCE) ? TRUE : FALSE, source)
	else
		release(src, condition, source)
	var/now = condition_in_force(condition)
	if(was == now)
		return FALSE
	condition_announce(channel)
	return TRUE

/// Tells the watchers a condition changed: its channel, the publish, and the stat layer's recompute of what reads it.
/obj/machinery/proc/condition_announce(channel)
	changed(src, channel)
	PUBLISH_CHANGE(src, MACHINE_KEY_STAT)

/// COMPATIBILITY SHIM (tests, the benchmark's old path): forces a machine's power by hand. The grid does not write has_power: it is the area's channel
/// read (area_gives_power(), machinery_power.dm). Forcing it dark is a SRC_GRID hold; forcing it on a machine whose area is dark sets `power_forced`.
/// TRUE when the machine's power changed.
/obj/machinery/proc/set_grid_power(powered)
	var/was = power_lost()
	if(powered)
		condition_hold(STAT_HAS_POWER, SRC_GRID, FALSE, NOPOWER, CHANGE_MACHINE_POWER)
		if(power_lost())
			set_power_forced(TRUE)
	else
		set_power_forced(FALSE)
		condition_hold(STAT_HAS_POWER, SRC_GRID, TRUE, NOPOWER, CHANGE_MACHINE_POWER)
	var/flipped = was != power_lost()
	if(flipped)
		condition_announce(CHANGE_MACHINE_POWER)
	return flipped

/// The machine is broken (atom_break()) or mended (atom_fix()). TRUE when it changed.
/obj/machinery/proc/set_broken_condition(broken)
	return condition_hold(STAT_INTACT, SRC_DAMAGE, broken, BROKEN, CHANGE_MACHINE_BROKEN)

/// The service hatch is open (the machine is under maintenance) or shut. TRUE when it changed.
/obj/machinery/proc/set_maintenance(maintaining)
	return condition_hold(STAT_IN_MAINTENANCE, SRC_MAINTENANCE, maintaining, MAINT, CHANGE_MACHINE_BROKEN)

/// The machine's own switch: on or off. TRUE when it changed.
/obj/machinery/proc/set_switched_on(on_now)
	return condition_hold(STAT_SWITCHED_ON, SRC_SWITCH, !on_now, POWEROFF, CHANGE_MACHINE_POWER)

/// Powered and working: powered, whole, not in maintenance, and no pulse holding it down.
/// interact_offline is deliberately not folded in: it is a UI-reach rule (tgui_status,
/// CanUseTopic), not "the machine works".
READS_AS(/obj/machinery/proc/operable, MACHINE_KEY_STAT)
/obj/machinery/proc/operable()
	return !!stat_value(src, STAT_OPERABLE)

/// Anchoring: set_anchored() (atoms_movable.dm) is the setter and raises the family channel.
/datum/scheduler_field_definition/atom/movable/anchored
	of = /atom/movable
	field = "anchored"
	channel = 0
/datum/scheduler_field_definition/obj/machinery/anchored
	of = /obj/machinery
	field = "anchored"
	channel = CHANGE_MACHINE_ANCHORED
/datum/scheduler_field_definition/mob/anchored
	of = /mob
	field = "anchored"
	channel = CHANGE_MOB_CAN_MOVE

/// Density: set_density() (_atom.dm) is the setter; a machine hears CHANGE_MACHINE_SETTINGS.
/datum/scheduler_field_definition/atom/density
	of = /atom
	field = "density"
	channel = 0
/datum/scheduler_field_definition/obj/machinery/density
	of = /obj/machinery
	field = "density"
	channel = CHANGE_MACHINE_SETTINGS

/// Vehicles keep their own condition bits (BROKEN, ...), same API as machines.
/obj/vehicle/var/stat = 0
TRACKED_BRIDGED(/obj/vehicle, stat, CHANGE_EXPLICIT)

/obj/vehicle/proc/stat_add(bits)
	return set_stat(stat | bits)

/obj/vehicle/proc/stat_remove(bits)
	return set_stat(stat & ~bits)

/obj/vehicle/proc/has_stat(bits)
	return (stat & bits) ? TRUE : FALSE
/datum/scheduler_field_definition/obj/vehicle/stat
	of = /obj/vehicle
	field = "stat"
	channel = CHANGE_EXPLICIT

/// Power mode (USE_POWER_OFF/IDLE/ACTIVE): set_use_power() (machinery_power.dm) is the setter and
/// moves the area's tally between the type's idle_power_usage and active_power_usage rows, so the
/// draw always follows the field.
/datum/scheduler_field_definition/obj/machinery/use_power
	of = /obj/machinery
	field = "use_power"
	channel = CHANGE_MACHINE_SETTINGS

/// Appearance (doc/rewrite/systems.md section 1): a machine's look follows its core fields, so a
/// change to any of them re-runs update_icon() on the presentation lane (once per frame) and no
/// setter is followed by a manual update_icon(). Declared appearances add the fields they read.
APPEARANCE_WATCH(/obj/machinery, list("stat", "on", "active", "state", "mode", "locked", "emagged", "use_power", "anchored", "density"))
/// Vehicles draw their condition bits.
APPEARANCE_WATCH(/obj/vehicle, list("stat"))

/// Integrity (atom_defense.dm): update_integrity() is the only writer and raises CHANGE_INTEGRITY, so
/// sprites drawn from damage declare "get_integrity" and redraw on hits and repairs by themselves.
/datum/scheduler_field_definition/atom/get_integrity
	of = /atom
	field = "get_integrity"
	derived = TRUE
	inputs = list(CHANGE_INTEGRITY)

/// TRUE: a machine in high gear (the mining and conveyor lines read it; their work runs at the same interval either way).
/obj/machinery/proc/high_gear_enabled()
	return FALSE

/obj/machinery/mineral/var/speed_process = FALSE
TRACKED_BRIDGED(/obj/machinery/mineral, speed_process, CHANGE_MACHINE_SETTINGS)

/obj/machinery/mineral/high_gear_enabled()
	return speed_process

/obj/machinery/conveyor/var/speed_process = FALSE
TRACKED_BRIDGED(/obj/machinery/conveyor, speed_process, CHANGE_MACHINE_SETTINGS)

/obj/machinery/conveyor/high_gear_enabled()
	return speed_process

/datum/scheduler_field_definition/obj/machinery/locked
	of = /obj/machinery
	field = "locked"
	channel = CHANGE_MACHINE_MODE

/datum/scheduler_field_definition/obj/machinery/emagged
	of = /obj/machinery
	field = "emagged"
	channel = CHANGE_MACHINE_SETTINGS

/datum/scheduler_field_definition/obj/machinery/speed_process
	of = /obj/machinery
	field = "speed_process"
	channel = CHANGE_MACHINE_SETTINGS

/// Both native emag keys and the legacy generic bit are genuine subversion storage.
/obj/machinery/proc/emagged(datum/act/eval/A = null)
	return is_emagged(src)

/obj/machinery/proc/set_emagged(value)
	value = !!value
	if(emagged() == value)
		return FALSE
	if(cap_of(src, CAP_EMAG))
		key_set(src, EMAG_EMAGGED, value)
		if(!value)
			cap_set(src, CAP_EMAGGED, FALSE)
	else
		cap_set(src, CAP_EMAGGED, value)
	tracked_bridged_changed(src, "emagged")
	return TRUE
SETTER(/obj/machinery, emagged)
