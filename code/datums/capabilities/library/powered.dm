// The powered capability (doc/rewrite/dx_conventions.md §2): no state of its own, it reads
// holder.cap_powered(). Layer: "dark" while unpowered; an examine line says so. Machinery marks
// itself changed on every power change (power_change()), so the layer follows.
//
//	. += needs_power()
//
// Named needs_power(), not powered(): machinery has a powered() proc, which a bare call inside its
// capabilities() would reach first.

/datum/capability/powered

/// Shows the holder dark (and says so on examine) while it has no power.
/proc/cap_power()
	return new /datum/capability/powered

/datum/capability/powered/examine(atom/holder, mob/user)
	if(!holder.cap_powered())
		return list("It is unpowered.")
	return null

/datum/capability/powered/draw(atom/holder, datum/look/look)
	look.overlay("dark", when = !holder.cap_powered())

/datum/capability/powered/ui_data(atom/holder, mob/user, list/data)
	data["powered"] = holder.cap_powered()
