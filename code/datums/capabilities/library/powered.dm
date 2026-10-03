// The powered capability (doc/rewrite/dx_conventions.md §2): no state of its own, it reads
// holder.cap_powered(). Layer: LOOK_DARK while unpowered; an examine line says so. Machinery marks
// itself changed on every power change (power_change()), so the layer follows.
//
//	. += cap_power()

/datum/capability/powered
	layer_name = LOOK_DARK

/// Shows the holder dark (and says so on examine) while it has no power.
/proc/cap_power(needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/powered/C = new
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

GLOBAL_LIST_INIT(cap_examine_unpowered, list("It is unpowered."))

/datum/capability/powered/examine(atom/holder, mob/user)
	if(!holder.cap_powered())
		return GLOB.cap_examine_unpowered
	return null

/datum/capability/powered/draw(atom/holder, datum/look/look)
	draw_layer(look, when = !holder.cap_powered())

/datum/capability/powered/legacy_ui_data(atom/holder, mob/user, list/data)
	data["powered"] = holder.cap_powered()
