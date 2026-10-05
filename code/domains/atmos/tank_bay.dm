// A gas tank bay (cell_bay()'s shape, code/engine/library/spaces.dm): the one tank a portable atmospherics machine holds, over a holder var.
//
//   tank_bay(nameof(holding), when = PROC_REF(takes_tanks))
//
// tank_bay.<var>.insert puts the tank in hand into the bay while it is empty (and while `when`, a holder condition, holds); tank_bay_eject() takes it
// out onto the floor (a window's eject button). The bay's tank shows in the holder's window and look through the var.

MSG_DEF_SELF(tank_bay/full, "There is already a tank in there.")

CAPABILITY_TYPE(tank_bay, CAP_TANK_BAY, /datum/capability/lib/tank_bay, key = slot_var, slot_var = null, when = null)

/datum/capability/lib/tank_bay

/datum/capability/lib/tank_bay/entries()
	return list(op("insert", item(/obj/item/tank), label("Insert tank"), wait(0), when ? global.when(when) : null,
		needs(req_empty(slot_var, because = MSG(tank_bay/full))), put_in(slot_var)))

/// Takes the tank in `holder`'s bay `slot_var` out onto the floor where the holder stands. Returns the tank, or null when the bay was empty.
/proc/tank_bay_eject(atom/holder, slot_var)
	var/obj/item/tank/T = holder.vars[slot_var]
	if(!istype(T))
		return null
	T.forceMove(get_turf(holder))
	varslot_set(holder, slot_var, null)
	return T
