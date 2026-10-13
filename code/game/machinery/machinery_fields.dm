// Core machine state as declared fields (doc/rewrite/systems.md §2).
//
// Every write goes through the generated setter (set_on(), set_locked(), set_stat(), ...), which
// publishes the var's key only on a real change; the tracked lint rejects direct writes. operable() is the one
// reader for "powered and working".

// on: instance storage belongs to the machine families that use it.
/obj/machinery/access_button/var/on = FALSE
TRACKED(/obj/machinery/access_button, on)
/obj/machinery/air_sensor/var/on = FALSE
TRACKED(/obj/machinery/air_sensor, on)
/obj/machinery/airlock_sensor/var/on = FALSE
TRACKED(/obj/machinery/airlock_sensor, on)
/obj/machinery/cablelayer/var/on = FALSE
TRACKED(/obj/machinery/cablelayer, on)
/obj/machinery/embedded_controller/var/on = FALSE
TRACKED(/obj/machinery/embedded_controller, on)
/obj/machinery/exonet_node/var/on = FALSE
TRACKED(/obj/machinery/exonet_node, on)
/obj/machinery/floodlight/var/on = FALSE
TRACKED(/obj/machinery/floodlight, on)
/obj/machinery/floor_light/var/on = FALSE
TRACKED(/obj/machinery/floor_light, on)
/obj/machinery/floorlayer/var/on = FALSE
TRACKED(/obj/machinery/floorlayer, on)
/obj/machinery/igniter/var/on = FALSE
TRACKED(/obj/machinery/igniter, on)
/obj/machinery/ion_engine/var/on = FALSE
TRACKED(/obj/machinery/ion_engine, on)
/obj/machinery/light/var/on = FALSE
TRACKED(/obj/machinery/light, on)
/obj/machinery/light_switch/var/on = FALSE
TRACKED(/obj/machinery/light_switch, on)
/obj/machinery/magnetic_module/var/on = FALSE
TRACKED(/obj/machinery/magnetic_module, on)
/obj/machinery/mech_sensor/var/on = FALSE
TRACKED(/obj/machinery/mech_sensor, on)
/obj/machinery/pda_multicaster/var/on = FALSE
TRACKED(/obj/machinery/pda_multicaster, on)
/obj/machinery/pipelayer/var/on = FALSE
TRACKED(/obj/machinery/pipelayer, on)
/obj/machinery/pump/var/on = FALSE
TRACKED(/obj/machinery/pump, on)
/obj/machinery/shower/var/on = FALSE
TRACKED(/obj/machinery/shower, on)
/obj/machinery/atmospherics/portables_connector/var/on = FALSE
TRACKED(/obj/machinery/atmospherics/portables_connector, on)
/obj/machinery/gravity_generator/main/var/on = FALSE
TRACKED(/obj/machinery/gravity_generator/main, on)
/obj/machinery/portable_atmospherics/powered/var/on = FALSE
TRACKED(/obj/machinery/portable_atmospherics/powered, on)
/obj/machinery/power/breakerbox/var/on = FALSE
TRACKED(/obj/machinery/power/breakerbox, on)
/obj/machinery/power/thermoregulator/var/on = FALSE
TRACKED(/obj/machinery/power/thermoregulator, on)
// active: instance storage belongs to the machine families that use it.
/obj/machinery/botany/var/active = FALSE
TRACKED(/obj/machinery/botany, active)
/obj/machinery/button/var/active = FALSE
TRACKED(/obj/machinery/button, active)
/obj/machinery/field_generator/var/active = FALSE
TRACKED(/obj/machinery/field_generator, active)
/obj/machinery/giga_drill/var/active = FALSE
TRACKED(/obj/machinery/giga_drill, active)
/obj/machinery/keycard_auth/var/active = FALSE
TRACKED(/obj/machinery/keycard_auth, active)
/obj/machinery/message_server/var/active = FALSE
TRACKED(/obj/machinery/message_server, active)
/obj/machinery/particle_accelerator/var/active = FALSE
TRACKED(/obj/machinery/particle_accelerator, active)
/obj/machinery/pointdefense/var/active = FALSE
TRACKED(/obj/machinery/pointdefense, active)
/obj/machinery/shield_capacitor/var/active = FALSE
TRACKED(/obj/machinery/shield_capacitor, active)
/obj/machinery/shield_gen/var/active = FALSE
TRACKED(/obj/machinery/shield_gen, active)
/obj/machinery/shieldgen/var/active = FALSE
TRACKED(/obj/machinery/shieldgen, active)
/obj/machinery/shieldwall/var/active = FALSE
TRACKED(/obj/machinery/shieldwall, active)
/obj/machinery/shieldwallgen/var/active = FALSE
TRACKED(/obj/machinery/shieldwallgen, active)
/obj/machinery/suit_cycler/var/active = FALSE
TRACKED(/obj/machinery/suit_cycler, active)
/obj/machinery/vending/var/active = FALSE
TRACKED(/obj/machinery/vending, active)
/obj/machinery/computer/HolodeckControl/var/active = FALSE
TRACKED(/obj/machinery/computer/HolodeckControl, active)
/obj/machinery/mineral/processing_unit/var/active = FALSE
TRACKED(/obj/machinery/mineral/processing_unit, active)
/obj/machinery/mining/drill/var/active = FALSE
TRACKED(/obj/machinery/mining/drill, active)
/obj/machinery/power/emitter/var/active = FALSE
TRACKED(/obj/machinery/power/emitter, active)
/obj/machinery/power/hydromagnetic_trap/var/active = FALSE
TRACKED(/obj/machinery/power/hydromagnetic_trap, active)
/obj/machinery/power/port_gen/var/active = FALSE
TRACKED(/obj/machinery/power/port_gen, active)
/obj/machinery/power/rad_collector/var/active = FALSE
TRACKED(/obj/machinery/power/rad_collector, active)
/obj/machinery/power/singularity_beacon/var/active = FALSE
TRACKED(/obj/machinery/power/singularity_beacon, active)
/obj/machinery/door/airlock/uranium/var/active = FALSE
TRACKED(/obj/machinery/door/airlock/uranium, active)
// mode: instance storage belongs to the machine families that use it.
/obj/machinery/ai_status_display/var/mode = 0
TRACKED(/obj/machinery/ai_status_display, mode)
/obj/machinery/alarm/var/mode = 0
TRACKED(/obj/machinery/alarm, mode)
/obj/machinery/chem_master/var/mode = 0
TRACKED(/obj/machinery/chem_master, mode)
/obj/machinery/disposal/var/mode = 0
TRACKED(/obj/machinery/disposal, mode)
/obj/machinery/iv_drip/var/mode = 0
TRACKED(/obj/machinery/iv_drip, mode)
/obj/machinery/status_display/var/mode = 0
TRACKED(/obj/machinery/status_display, mode)
/obj/machinery/computer/card/var/mode = 0
TRACKED(/obj/machinery/computer/card, mode)
/obj/machinery/computer/cryopod/var/mode = 0
TRACKED(/obj/machinery/computer/cryopod, mode)
/obj/machinery/computer/guestpass/var/mode = 0
TRACKED(/obj/machinery/computer/guestpass, mode)
/obj/machinery/power/thermoregulator/var/mode = 0
TRACKED(/obj/machinery/power/thermoregulator, mode)
/obj/machinery/power/smes/batteryrack/var/mode = 0
TRACKED(/obj/machinery/power/smes/batteryrack, mode)
// locked: instance storage belongs to the machine families that use it.
/obj/machinery/ai_slipper/var/locked = FALSE
TRACKED(/obj/machinery/ai_slipper, locked)
/obj/machinery/bodyscanner/var/locked = FALSE
TRACKED(/obj/machinery/bodyscanner, locked)
/obj/machinery/cash_register/var/locked = FALSE
TRACKED(/obj/machinery/cash_register, locked)
/obj/machinery/clonepod/var/locked = FALSE
TRACKED(/obj/machinery/clonepod, locked)
/obj/machinery/dna_scannernew/var/locked = FALSE
TRACKED(/obj/machinery/dna_scannernew, locked)
/obj/machinery/navbeacon/var/locked = FALSE
TRACKED(/obj/machinery/navbeacon, locked)
/obj/machinery/shield_capacitor/var/locked = FALSE
TRACKED(/obj/machinery/shield_capacitor, locked)
/obj/machinery/shield_gen/var/locked = FALSE
TRACKED(/obj/machinery/shield_gen, locked)
/obj/machinery/shieldgen/var/locked = FALSE
TRACKED(/obj/machinery/shieldgen, locked)
/obj/machinery/shieldwallgen/var/locked = FALSE
TRACKED(/obj/machinery/shieldwallgen, locked)
/obj/machinery/smartfridge/var/locked = FALSE
TRACKED(/obj/machinery/smartfridge, locked)
/obj/machinery/suit_cycler/var/locked = FALSE
TRACKED(/obj/machinery/suit_cycler, locked)
/obj/machinery/suspension_gen/var/locked = FALSE
TRACKED(/obj/machinery/suspension_gen, locked)
/obj/machinery/computer/rdconsole_tg/var/locked = FALSE
TRACKED(/obj/machinery/computer/rdconsole_tg, locked)
/obj/machinery/deployable/barrier/var/locked = FALSE
TRACKED(/obj/machinery/deployable/barrier, locked)
/obj/machinery/door/unpowered/var/locked = FALSE
TRACKED(/obj/machinery/door/unpowered, locked)

/// Machine conditions are stats held by sources (code/contracts/ids/stats.dm):
///   has_power      false while the area's channel is dark (area_gives_power(): the grid's reading) or SRC_GRID holds it (set_grid_power(), a shim)
///   intact         false while SRC_DAMAGE holds it (atom_break() until atom_fix())
///   in_maintenance true while SRC_MAINTENANCE holds it (an open service hatch: set_maintenance())
///   switched_on    false while SRC_SWITCH holds it (the machine's own switch: set_switched_on())
/// and a pulse is a timed SRC_EMP hold on STAT_OPERABLE (emp_disable()). STAT_OPERABLE is the machine working. The named readers below say each in
/// one word. There is no `stat` var on a machine: watchers use on_change(STAT_OPERABLE) and the "stat" key is only what the conditions publish.

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
/obj/machinery/proc/condition_hold(condition, source, held)
	var/was = condition_in_force(condition)
	if(held)
		hold(src, condition, (condition == STAT_IN_MAINTENANCE) ? TRUE : FALSE, source)
	else
		release(src, condition, source)
	var/now = condition_in_force(condition)
	if(was == now)
		return FALSE
	condition_announce()
	return TRUE

/// Tells the watchers a condition changed: the publish of the stat key, the stat layer's recompute of what reads it, and the draws that read a condition
/// through an accessor (power_lost(), operable(), broken_now(): each READS_AS the key, which the generated draw keys list) redraw. An exact type is
/// marked for those draws only; a type that declares no dependencies re-derives everything, as it does for any write.
/obj/machinery/proc/condition_announce()
	state_changed(src, 0, MACHINE_KEY_STAT)

/// COMPATIBILITY SHIM (tests, the benchmark's old path): forces a machine's power by hand. The grid does not write has_power: it is the area's channel
/// read (area_gives_power(), machinery_power.dm). Forcing it dark is a SRC_GRID hold; forcing it on a machine whose area is dark sets `power_forced`.
/// TRUE when the machine's power changed.
/obj/machinery/proc/set_grid_power(powered)
	var/was = power_lost()
	if(powered)
		condition_hold(STAT_HAS_POWER, SRC_GRID, FALSE)
		if(power_lost())
			set_power_forced(TRUE)
	else
		set_power_forced(FALSE)
		condition_hold(STAT_HAS_POWER, SRC_GRID, TRUE)
	var/flipped = was != power_lost()
	if(flipped)
		condition_announce()
	return flipped

/// The machine is broken (atom_break()) or mended (atom_fix()). TRUE when it changed.
/obj/machinery/proc/set_broken_condition(broken)
	return condition_hold(STAT_INTACT, SRC_DAMAGE, broken)

/// The service hatch is open (the machine is under maintenance) or shut. TRUE when it changed.
/obj/machinery/proc/set_maintenance(maintaining)
	return condition_hold(STAT_IN_MAINTENANCE, SRC_MAINTENANCE, maintaining)

/// The machine's own switch: on or off. TRUE when it changed.
/obj/machinery/proc/set_switched_on(on_now)
	return condition_hold(STAT_SWITCHED_ON, SRC_SWITCH, !on_now)

/// Powered and working: powered, whole, not in maintenance, and no pulse holding it down.
/// interact_offline is deliberately not folded in: it is a UI-reach rule (tgui_status,
/// CanUseTopic), not "the machine works".
READS_AS(/obj/machinery/proc/operable, MACHINE_KEY_STAT)
/obj/machinery/proc/operable()
	return !!stat_value(src, STAT_OPERABLE)

/// Vehicles keep their own condition bits (BROKEN, ...), same API as machines.
/obj/vehicle/var/stat = 0
TRACKED(/obj/vehicle, stat)

/obj/vehicle/proc/stat_add(bits)
	return set_stat(stat | bits)

/obj/vehicle/proc/stat_remove(bits)
	return set_stat(stat & ~bits)

/obj/vehicle/proc/has_stat(bits)
	return (stat & bits) ? TRUE : FALSE

/// TRUE: a machine in high gear (the mining and conveyor lines read it; their work runs at the same interval either way).
/obj/machinery/proc/high_gear_enabled()
	return FALSE

/obj/machinery/mineral/var/speed_process = FALSE
TRACKED(/obj/machinery/mineral, speed_process)

/obj/machinery/mineral/high_gear_enabled()
	return speed_process

/obj/machinery/conveyor/var/speed_process = FALSE
TRACKED(/obj/machinery/conveyor, speed_process)

/obj/machinery/conveyor/high_gear_enabled()
	return speed_process




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
	tracked_changed(src, "emagged")
	return TRUE
SETTER(/obj/machinery, emagged)
