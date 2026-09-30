// cell_bay(): a power cell slot behind the cover (doc/rewrite/dx_conventions.md §2). One slot
// (cap_slot, behind = COVER, hand eject, layer "cell" seen through the open cover), a charge examine
// line, charge UI data (data["caps"][slot var]["charge"]) and a low-charge helper for other entries:
// cell_charge_percent(A) (0 with no cell, never null) and the needs proc cap_cell_charged().
//
//	. += cell_bay(nameof(cell))

/// The cell bay bundle for holder var `slot_var` (nameof(cell)).
/proc/cell_bay(slot_var, accepts = /obj/item/cell, layer = LOOK_CELL, at)
	return list(cap_layer_order(cap_slot(slot_var, accepts, at = at, behind = COVER, layer = layer, eject_via = SLOT_VIA_HAND, name = "Insert power cell", eject_name = "Remove power cell", insert_msg = "You insert %I%.", eject_msg = "You remove %I%.", full_msg = "%T% already has a power cell installed.", slot_type = /datum/capability/slot/cell_bay), 50))

/datum/capability/slot/cell_bay

/// The hand eject is for hands: a silicon's touch falls through to the next entry (the window).
/datum/capability/slot/cell_bay/interactions(atom/holder)
	. = ..()
	for(var/datum/interaction/capability/slot_eject/E in .)
		E.offered_when = list(REQ_PROC(/proc/cap_actor_has_hands, "you need hands for that"))

/// The cell shows through the open cover (not with the cover gone: the holder draws that sprite).
/datum/capability/slot/cell_bay/draw(atom/holder, datum/look/look)
	draw_layer(look, when = holder.vars[slot_var] && cover_is_open(holder) && !cover_removed(holder))

/datum/capability/slot/cell_bay/examine(atom/holder, mob/user)
	var/obj/item/cell/C = holder.vars[slot_var]
	if(!istype(C))
		return cover_is_open(holder) ? list("The power cell is missing.") : null
	return list("The charge meter reads [round(C.percent())]%.")

/datum/capability/slot/cell_bay/ui_data(atom/holder, mob/user, list/data)
	..()
	data["charge"] = cell_charge_percent(holder)

/// The charge of A's cell bay in percent: 0 with no cell (never null).
/proc/cell_charge_percent(atom/A)
	var/datum/capability/slot/cell_bay/C = cap_of(A, /datum/capability/slot/cell_bay)
	var/obj/item/cell/cell = C ? A.vars[C.slot_var] : null
	return istype(cell) ? cell.percent() : 0

/// needs: the cell holds more than CELL_BAY_LOW_PERCENT.
/atom/proc/cap_cell_charged(mob/user, obj/item/held)
	return cell_charge_percent(src) > CELL_BAY_LOW_PERCENT ? TRUE : "its power cell is too low"
