// The powered capability (doc/rewrite/dx_conventions.md §2): no state of its own, it reads
// holder.cap_powered(). Layer: LOOK_DARK while unpowered; an examine line says so. Machinery marks
// itself changed on every power change (power_change()), so the layer follows.
//
//	. += cap_power()

/datum/capability/powered
	layer_name = LOOK_DARK

/// Shows the holder dark (and says so on examine) while it has no power.
/proc/cap_power(behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log, layer = LOOK_DARK)
	var/datum/capability/powered/C = new
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/powered/examine(atom/holder, mob/user)
	if(!holder.cap_powered())
		return list("It is unpowered.")
	return null

/datum/capability/powered/draw(atom/holder, datum/look/look)
	draw_layer(look, when = !holder.cap_powered())

/datum/capability/powered/ui_data(atom/holder, mob/user, list/data)
	data["powered"] = holder.cap_powered()
