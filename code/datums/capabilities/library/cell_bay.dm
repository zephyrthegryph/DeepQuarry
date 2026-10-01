// cell_bay(): a power cell slot behind the cover (doc/rewrite/dx_conventions.md §2). One slot
// (cap_slot, needing the cover open, hand eject, part LOOK_CELL seen through the open cover), a charge examine
// line, charge UI data (data["caps"][slot var]["charge"]) and a low-charge helper for other entries:
// cell_charge_percent(A) (0 with no cell, never null) and the needs proc cap_cell_charged().
//
//	. += cell_bay(nameof(cell))
//	. += cell_bay(nameof(cell), at = BAY_HATCH)		// behind a maintenance_hatch(): the compartment's door is the open cover

/// The cell bay bundle for holder var `slot_var` (nameof(cell)).
/// `at`: the compartment (BAY_*) the bay is in instead of standing behind a cover. `needs`: a holder proc (mob/user, held) that
/// answers TRUE or the reason the bay can't be used now. `size`: the ITEMSIZE_* a cell must be to fit.
/proc/cell_bay(slot_var, accepts = /obj/item/cell, at, needs, size)
	var/datum/capability/slot/cell_bay/bay = cap_slot(slot_var, accepts, at = at, needs = at ? needs : cap_needs_with(req_set(COVER), needs), part = LOOK_CELL, eject_via = SLOT_VIA_HAND, name = "Insert power cell", eject_name = "Remove power cell", insert_msg = "You insert %I%.", eject_msg = "You remove %I%.", full_msg = "%T% already has a power cell installed.", slot_type = /datum/capability/slot/cell_bay)
	bay.size = size
	return list(cap_layer_order(bay, 50))

/datum/capability/slot/cell_bay
	/// The ITEMSIZE_* a cell must be to fit, or null for any.
	var/size

/// A cell of the wrong size doesn't fit (the input is used, the user told).
/datum/capability/slot/cell_bay/insert(atom/holder, obj/item/item, mob/user)
	if(size && ismovable(item) && is_type_in_list(item, islist(accepts) ? accepts : list(accepts)) && item.w_class != size)
		to_chat(user, span_warning("\The [item] is too [item.w_class < size ? "small" : "large"] to work here."))
		return UI_REFUSED
	return ..()

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
