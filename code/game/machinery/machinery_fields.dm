// Core machine state as declared fields (doc/rewrite/systems.md §2).
//
// Every write goes through the generated setter (set_on(), set_locked(), stat_add(), ...), which
// raises the channel only on a real change; tools/ci/sys_rules/fields.py and field_write_lint.py
// reject direct writes. operable() is the one reader for "powered and working".

OM_FIELD(/obj/machinery, on, FALSE, CHANGE_MACHINE_SETTINGS)
OM_FIELD(/obj/machinery, active, FALSE, CHANGE_MACHINE_SETTINGS)
OM_FIELD(/obj/machinery, state, 0, CHANGE_MACHINE_SETTINGS)
OM_FIELD(/obj/machinery, mode, 0, CHANGE_MACHINE_SETTINGS)
OM_FIELD(/obj/machinery, locked, FALSE, CHANGE_MACHINE_MODE)
OM_FIELD(/obj/machinery, emagged, FALSE, CHANGE_MACHINE_SETTINGS)

/// Machine conditions are stats held by sources (code/contracts/ids/stats.dm):
///   has_power      false while the area's channel is dark (area_gives_power(): the grid's reading) or SRC_GRID holds it (set_grid_power(), a shim)
///   intact         false while SRC_DAMAGE holds it (atom_break() until atom_fix())
///   in_maintenance true while SRC_MAINTENANCE holds it (an open service hatch: set_maintenance())
///   switched_on    false while SRC_SWITCH holds it (the machine's own switch: set_switched_on())
/// and a pulse is a timed SRC_EMP hold on STAT_OPERABLE (emp_disable()). STAT_OPERABLE is the machine working. The named readers below say each in
/// one word. There is no `stat` var on a machine: watchers use on_change(STAT_OPERABLE) and the "stat" key is only what the conditions publish.
/// The channels the conditions raise, as the look's watch list names them ("stat"). The machine has no var of that name any more: the field is only the
/// channel mask the conditions' announcements raise.
/datum/om/field_def/obj/machinery/stat
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
OM_FIELD_SETTER(/atom/movable, anchored, 0)
OM_FIELD_SETTER(/obj/machinery, anchored, CHANGE_MACHINE_ANCHORED)
OM_FIELD_SETTER(/mob, anchored, CHANGE_MOB_CAN_MOVE)

/// Density: set_density() (_atom.dm) is the setter; a machine hears CHANGE_MACHINE_SETTINGS.
OM_FIELD_SETTER(/atom, density, 0)
OM_FIELD_SETTER(/obj/machinery, density, CHANGE_MACHINE_SETTINGS)

/// Vehicles keep their own condition bits (BROKEN, ...), same API as machines.
OM_FLAG_FIELD(/obj/vehicle, stat, 0, CHANGE_EXPLICIT)

/// Power mode (USE_POWER_OFF/IDLE/ACTIVE): set_use_power() (machinery_power.dm) is the setter and
/// moves the area's tally between the type's idle_power_usage and active_power_usage rows, so the
/// draw always follows the field.
OM_FIELD_SETTER(/obj/machinery, use_power, CHANGE_MACHINE_SETTINGS)

/// Appearance (doc/rewrite/systems.md section 1): a machine's look follows its core fields, so a
/// change to any of them re-runs update_icon() on the presentation lane (once per frame) and no
/// setter is followed by a manual update_icon(). Declared appearances add the fields they read.
APPEARANCE_WATCH(/obj/machinery, list("stat", "on", "active", "state", "mode", "locked", "emagged", "use_power", "anchored", "density"))
/// Vehicles draw their condition bits.
APPEARANCE_WATCH(/obj/vehicle, list("stat"))

/// Integrity (atom_defense.dm): update_integrity() is the only writer and raises CHANGE_INTEGRITY, so
/// sprites drawn from damage declare "get_integrity" and redraw on hits and repairs by themselves.
OM_DERIVE_FIELD(/atom, get_integrity, list(CHANGE_INTEGRITY))

/// TRUE: a machine in high gear (the mining and conveyor lines read it; their work runs at the same interval either way).
OM_FIELD(/obj/machinery, speed_process, FALSE, CHANGE_MACHINE_SETTINGS)
