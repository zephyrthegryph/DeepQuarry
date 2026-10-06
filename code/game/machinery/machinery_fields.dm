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

/// Machine condition bits (BROKEN, NOPOWER, POWEROFF, MAINT, EMPED; code/__defines/machinery.dm).
/// BROKEN, MAINT and EMPED raise CHANGE_MACHINE_BROKEN, NOPOWER and POWEROFF CHANGE_MACHINE_POWER.
/datum/om/field_def/obj/machinery/stat
	of = /obj/machinery
	field = "stat"
	channel = CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_POWER

/obj/machinery/var/stat = 0

/obj/machinery/proc/stat_bit_channels()
	var/static/list/table = list("[BROKEN]" = CHANGE_MACHINE_BROKEN, "[NOPOWER]" = CHANGE_MACHINE_POWER, "[POWEROFF]" = CHANGE_MACHINE_POWER, "[MAINT]" = CHANGE_MACHINE_BROKEN, "[EMPED]" = CHANGE_MACHINE_BROKEN)
	return table


/// The bits among `bits` that are set now.
/obj/machinery/proc/stat_bits_now(bits)
	READS_FROM(src)
	. = stat & bits
	if((bits & NOPOWER) && !stat_value(src, STAT_HAS_POWER))
		. |= NOPOWER
	if((bits & BROKEN) && !stat_value(src, STAT_INTACT))
		. |= BROKEN

/obj/machinery/proc/has_stat(bits)
	return stat_bits_now(bits) ? TRUE : FALSE

/// Sets the bits in `bits` (all other bits stay). TRUE when any changed.
/obj/machinery/proc/stat_add(bits)
	var/flipped = bits & ~stat_bits_now(MACHINE_STAT_ANY)
	if(!flipped)
		return FALSE
	if(flipped & NOPOWER)
		hold(src, STAT_HAS_POWER, FALSE, SRC_GRID)
	if(flipped & BROKEN)
		hold(src, STAT_INTACT, FALSE, SRC_DAMAGE)
	var/bits_left = flipped & ~MACHINE_STAT_HELD
	if(bits_left)
		stat |= bits_left
	stat_changed(flipped)
	return TRUE

/// Clears the bits in `bits`. TRUE when any changed.
/obj/machinery/proc/stat_remove(bits)
	var/flipped = stat_bits_now(MACHINE_STAT_ANY) & bits
	if(!flipped)
		return FALSE
	if(flipped & NOPOWER)
		release(src, STAT_HAS_POWER, SRC_GRID)
	if(flipped & BROKEN)
		release(src, STAT_INTACT, SRC_DAMAGE)
	var/bits_left = flipped & ~MACHINE_STAT_HELD
	if(bits_left)
		stat &= ~bits_left
	stat_changed(flipped)
	return TRUE

/// Writes the whole set of condition bits.
/obj/machinery/proc/set_stat(value)
	var/now = stat_bits_now(MACHINE_STAT_ANY)
	. = FALSE
	if(stat_remove(now & ~value))
		. = TRUE
	if(stat_add(value & ~now))
		. = TRUE

/// What a change of bits raises: their channels, the `stat` publish, and the stat layer's recompute of what reads them.
/obj/machinery/proc/stat_changed(flipped)
	changed(src, om_flag_channels(stat_bit_channels(), flipped, CHANGE_MACHINE_BROKEN | CHANGE_MACHINE_POWER))
	PUBLISH_CHANGE(src, "stat")
	om_field_written(src, "stat")

/// Powered and working: none of NOPOWER, BROKEN, MAINT, EMPED (plus `additional_flags`), and no pulse holding it down (emp_disable()'s timed
/// hold on STAT_OPERABLE, which this legacy reader shares with the converted machines' stat).
/// interact_offline is deliberately not folded in: it is a UI-reach rule (tgui_status,
/// CanUseTopic), not "the machine works".
OM_DERIVE_FIELD(/obj/machinery, operable, list("stat"))
/obj/machinery/proc/operable(additional_flags = 0)
	return !stat_bits_now(MACHINE_INOPERABLE_FLAGS | additional_flags) && !emp_disabled(src)

/// Anchoring: set_anchored() (atoms_movable.dm) is the setter and raises the family channel.
OM_FIELD_SETTER(/atom/movable, anchored, 0)
OM_FIELD_SETTER(/obj/machinery, anchored, CHANGE_MACHINE_ANCHORED)
OM_FIELD_SETTER(/mob, anchored, CHANGE_MOB_CAN_MOVE)

/// Density: set_density() (_atom.dm) is the setter; a machine hears CHANGE_MACHINE_SETTINGS.
OM_FIELD_SETTER(/atom, density, 0)
OM_FIELD_SETTER(/obj/machinery, density, CHANGE_MACHINE_SETTINGS)

/// Vehicles keep their own condition bits (BROKEN, ...), same API as machines.
OM_FLAG_FIELD(/obj/vehicle, stat, 0, CHANGE_EXPLICIT)

/// Power mode (USE_POWER_OFF/IDLE/ACTIVE): set_use_power() (machinery_power.dm) is the setter; the machine's contribution to its
/// area's demand reads it with the idle and active usage, so the draw always follows the field.
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
