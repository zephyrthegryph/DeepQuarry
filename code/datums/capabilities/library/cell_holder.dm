// The cell holder and charger capabilities (doc/rewrite/dx_conventions.md §2).
//
//	/obj/machinery/cell_charger/capabilities()
//		. = ..()
//		. += cap_cell_holder(nameof(charging), /obj/item/cell)
//		. += cap_charger(rate = 250)
//
// cap_cell_holder(var, cell_type): a cap_slot() on the holder var (declare it OWN(..., OWN_CONTAINED))
// holding one cell_type, with the slot's Insert / Remove entries, overlay "cell" while one is in,
// UI data[var] = {name, ref}, and a charge examine line. From code: slot_insert(nameof(var), cell,
// user) and slot_eject(nameof(var), user); cell_in(holder) on the capability.
//
// cap_charger(rate, cell_var): charges the holder's cell by `rate` per second on the periodic lane
// (cadence PERIODIC_SECOND, taken as the holder's periodic_cadence at init) while should_run():
// a cell is in and the holder is powered and not broken.

/datum/capability/slot/cell_holder

/**
 * The cell holder for holder var `var_name` (nameof(var)) holding one `cell_type`. Takes the standard
 * gating arguments (an APC: behind = COVER).
 */
/proc/cap_cell_holder(var_name, cell_type = /obj/item/cell, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log)
	var/datum/capability/slot/cell_holder/C = cap_slot(var_name, cell_type, name = "Insert cell", eject_name = "Remove cell", \
		eject_via = SLOT_VIA_HAND, layer = "cell", slot_type = /datum/capability/slot/cell_holder, \
		insert_msg = "You insert %I% into %T%.", eject_msg = "You take %I% out of %T%.", full_msg = "%T% already has %I% in it.")
	cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)
	C.else_say ||= "you can't do that right now"
	C.eject_else_say ||= "you can't do that right now"
	return C

/datum/capability/slot/cell_holder/examine(atom/holder, mob/user)
	var/obj/item/cell/cell = holder.vars[slot_var]
	if(!cell)
		return list("It has no cell.")
	return list("It has \a [cell] installed, charged to [round(cell.percent())]%.")

/// The live cell in holder, or null. Pure.
/datum/capability/slot/cell_holder/proc/cell_in(atom/holder)
	var/obj/item/cell/cell = holder.vars[slot_var]
	return (cell && !QDELETED(cell)) ? cell : null

// ---- charger ----

/datum/capability/charger
	cadence = PERIODIC_SECOND
	/// Charge given per second.
	var/rate = 100
	/// The cell holder's var it charges (null: the holder's first cell holder).
	var/cell_var

/// Charges the holder's cell (its cap_cell_holder()) by `rate` per second while powered and not broken.
/proc/cap_charger(rate = 100, cell_var = null, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = FALSE, works_unpowered = FALSE, log)
	var/datum/capability/charger/C = new
	C.rate = rate
	C.cell_var = cell_var
	C.key = cell_var ? "charger:[cell_var]" : "charger"
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/charger/on_holder_init(atom/holder, mapload)
	if(!holder.periodic_cadence)
		holder.periodic_cadence = cadence // joins the lane

/datum/capability/charger/proc/cell_holder_of(atom/holder)
	return cap_of(holder, cell_var ? "slot:[cell_var]" : /datum/capability/slot/cell_holder)

/// Pure: reads the holder's own state (its cell var, power, broken bit, the capability's bits). A
/// full cell keeps the lane until removed, which costs one give() of zero per second.
/datum/capability/charger/cap_should_run(atom/holder)
	var/datum/capability/slot/cell_holder/H = cell_holder_of(holder)
	if(!H?.cell_in(holder))
		return FALSE
	if(!works_broken && is_broken(holder))
		return FALSE
	if(!works_unpowered && !holder.cap_powered())
		return FALSE
	if(behind & ~holder.cap_state)
		return FALSE
	if(blocked_by & holder.cap_state)
		return FALSE
	return TRUE

/datum/capability/charger/cap_periodic_step(atom/holder, delta)
	var/datum/capability/slot/cell_holder/H = cell_holder_of(holder)
	var/obj/item/cell/cell = H?.cell_in(holder)
	if(!cell || cell.fully_charged())
		return
	cell.give(rate * delta / (1 SECOND))

/datum/capability/charger/examine(atom/holder, mob/user)
	var/datum/capability/slot/cell_holder/H = cell_holder_of(holder)
	var/obj/item/cell/cell = H?.cell_in(holder)
	if(cell && cap_should_run(holder))
		return list(cell.fully_charged() ? "It has finished charging \the [cell]." : "It is charging \the [cell].")
	return null
