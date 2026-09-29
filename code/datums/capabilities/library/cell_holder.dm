// The cell holder and charger capabilities (doc/rewrite/dx_conventions.md §2).
//
//	/obj/machinery/cell_charger/capabilities()
//		. = ..()
//		. += cell_holder(nameof(charging), /obj/item/cell, behind = NONE)
//		. += charger(rate = 250)
//
// cell_holder(var, cell_type): the holder var (from nameof()) holds at most one cell, owned by the
// holder (declare it OWN(..., OWN_CONTAINED)). It is a minimal single-item slot: the generic
// slot() capability (rewrite/dx-slots) is not in this tree yet, so cell_holder builds its own two
// entries; once slot() lands it becomes slot(var, cell_type, ...) plus the charge line.
// Entries: Insert cell (a held cell_type, while empty) and Remove cell (empty hand, while one is
// in). Examine: the cell and its charge. Look: overlay "cell" while one is in. UI: data[var] =
// {name, ref} or null. From code: cell_holder_insert(nameof(var), cell, user) and
// cell_holder_eject(nameof(var), user).
//
// charger(rate): charges the holder's cell by `rate` per second on the periodic lane (cadence
// PERIODIC_SECOND, taken as the holder's periodic_cadence at init) while a cell is in and the
// holder is powered and not broken. Joins the lane through on_holder_init until the core's
// systems() hook exists.

/datum/capability/cell_holder
	/// The holder var holding the cell (nameof()).
	var/cell_var
	/// The accepted cell type.
	var/cell_type = /obj/item/cell

/**
 * The cell holder for holder var `var_name` (nameof(var)) holding one `cell_type`. behind /
 * locked_by gate both entries (an APC: behind = COVER).
 */
/proc/cell_holder(var_name, cell_type = /obj/item/cell, behind = NONE, locked_by = NONE, works_broken = TRUE, works_unpowered = TRUE, log = null)
	var/datum/capability/cell_holder/C = new
	C.cell_var = var_name
	C.key = "cell_holder:[var_name]"
	C.cell_type = cell_type
	C.behind = behind
	C.locked_by = locked_by
	C.works_broken = works_broken
	C.works_unpowered = works_unpowered
	C.log = log
	return C

/datum/capability/cell_holder/interactions(atom/holder)
	. = list()
	. += cap_claim_entry(src, insert("Insert cell", cell_type, TYPE_PROC_REF(/atom, cap_cell_insert), behind = behind, locked_by = locked_by, needs = TYPE_PROC_REF(/atom, cap_cell_empty), else_say = "there's already a cell in it", works_broken = works_broken, works_unpowered = works_unpowered, log = log), "cell:insert:[cell_var]:[cell_type]")
	. += cap_claim_entry(src, hand("Remove cell", TYPE_PROC_REF(/atom, cap_cell_remove), behind = behind, locked_by = locked_by, needs = TYPE_PROC_REF(/atom, cap_cell_present), else_say = "there's no cell in it", works_broken = works_broken, works_unpowered = works_unpowered, log = log), "cell:remove:[cell_var]", INTERACTION_CAT_EJECT, empty_handed = TRUE)

/datum/capability/cell_holder/examine(atom/holder, mob/user)
	var/obj/item/cell/cell = holder.vars[cell_var]
	if(!cell)
		return list("It has no cell.")
	return list("It has \a [cell] installed, charged to [round(cell.percent())]%.")

/datum/capability/cell_holder/draw(atom/holder, datum/look/look)
	look.overlay("cell", when = !isnull(holder.vars[cell_var]))

/datum/capability/cell_holder/ui_data(atom/holder, mob/user, list/data)
	var/obj/item/cell/cell = holder.vars[cell_var]
	// Name and ref only: the charge is another object's untracked var (H4); a UI that shows it
	// reads it through a tracked setter once the cell has one.
	data[cell_var] = cell ? list("name" = cell.name, "ref" = REF(cell)) : null

/// The cell in holder, or null (a deleted cell is let go).
/datum/capability/cell_holder/proc/cell_in(atom/holder)
	var/obj/item/cell/cell = holder.vars[cell_var]
	if(cell && QDELETED(cell))
		own_take(holder, cell_var)
		return null
	return cell

/// Whether a live cell is in holder. Pure (for needs procs and gates).
/datum/capability/cell_holder/proc/has_cell(atom/holder)
	var/obj/item/cell/cell = holder.vars[cell_var]
	return !isnull(cell) && !QDELETED(cell)

/// Puts `cell` in: out of the hand or container it is in, into holder, adopted. TRUE when it went in.
/datum/capability/cell_holder/proc/put_cell(atom/holder, obj/item/cell/cell, mob/user)
	if(!istype(cell, cell_type) || cell_in(holder))
		return FALSE
	if(ismob(cell.loc))
		var/mob/carrier = cell.loc
		if(!carrier.unEquip(cell, target = holder))
			return FALSE
	if(cell.loc != holder)
		cell.forceMove(holder)
	own_set(holder, cell_var, cell)
	if(holder.vars[cell_var] != cell)
		return FALSE
	changed(holder)
	return TRUE

/// Takes the cell out, to user's hands (or the floor). Returns the cell.
/datum/capability/cell_holder/proc/take_cell(atom/holder, mob/user)
	var/obj/item/cell/cell = cell_in(holder)
	if(!cell)
		return null
	own_take(holder, cell_var)
	if(cell.loc == holder || isnull(cell.loc))
		cell.forceMove(holder.drop_location())
		user?.put_in_hands(cell)
	changed(holder)
	return cell

/// Inserts `cell` into the cell holder for `var_name` (nameof()) from code. TRUE when it went in.
/atom/proc/cell_holder_insert(var_name, obj/item/cell/cell, mob/user)
	var/datum/capability/cell_holder/C = cap_of(src, "cell_holder:[var_name]")
	return C ? C.put_cell(src, cell, user) : FALSE

/// Ejects the cell from the cell holder for `var_name` (nameof()) from code. Returns the cell.
/atom/proc/cell_holder_eject(var_name, mob/user)
	var/datum/capability/cell_holder/C = cap_of(src, "cell_holder:[var_name]")
	return C?.take_cell(src, user)

// ---- entry handlers and needs (procs on the holder) ----

/atom/proc/cap_cell_empty(mob/user, obj/item/held)
	var/datum/capability/cell_holder/C = cap_current(src, /datum/capability/cell_holder)
	return C && !C.has_cell(src)

/atom/proc/cap_cell_present(mob/user, obj/item/held)
	var/datum/capability/cell_holder/C = cap_current(src, /datum/capability/cell_holder)
	return C && C.has_cell(src)

/atom/proc/cap_cell_insert(mob/user, obj/item/held)
	var/datum/capability/cell_holder/C = cap_current(src, /datum/capability/cell_holder)
	if(!C?.put_cell(src, held, user))
		return refuse(user, "\The [held] won't go into \the [src].")
	act_message(user, src, self = "You insert %I% into %T%.", others = "%U% inserts %I% into %T%.", item = held)
	return TRUE

/atom/proc/cap_cell_remove(mob/user, obj/item/held)
	var/datum/capability/cell_holder/C = cap_current(src, /datum/capability/cell_holder)
	var/obj/item/cell/cell = C?.take_cell(src, user)
	if(!cell)
		return refuse(user, "There's no cell to take out.")
	act_message(user, src, self = "You take %I% out of %T%.", others = "%U% takes %I% out of %T%.", item = cell)
	return TRUE

// ---- charger ----

/datum/capability/charger
	cadence = PERIODIC_SECOND
	/// Charge given per second.
	var/rate = 100
	/// The cell_holder key it charges (null: the holder's first cell holder).
	var/holder_key

/// Charges the holder's cell (its cell_holder capability) by `rate` per second while powered.
/proc/charger(rate = 100, cell_var = null)
	var/datum/capability/charger/C = new
	C.rate = rate
	C.holder_key = cell_var ? "cell_holder:[cell_var]" : null
	return C

/datum/capability/charger/on_holder_init(atom/holder, mapload)
	if(!holder.periodic_cadence)
		holder.periodic_cadence = cadence // joins the lane; systems() replaces this

/datum/capability/charger/proc/cell_holder_of(atom/holder)
	return cap_of(holder, holder_key || /datum/capability/cell_holder)

/// Reads only the holder's own state (its cell var, power, broken bit): a cell that fills up keeps
/// the lane until it is removed, which costs one give() of zero per second.
/datum/capability/charger/cap_should_run(atom/holder)
	var/datum/capability/cell_holder/H = cell_holder_of(holder)
	if(!H || isnull(holder.vars[H.cell_var]))
		return FALSE
	return !is_broken(holder) && holder.cap_powered()

/datum/capability/charger/cap_periodic_step(atom/holder, delta)
	var/datum/capability/cell_holder/H = cell_holder_of(holder)
	var/obj/item/cell/cell = H?.cell_in(holder)
	if(!cell || cell.fully_charged())
		return
	cell.give(rate * delta / (1 SECOND))

/datum/capability/charger/examine(atom/holder, mob/user)
	var/datum/capability/cell_holder/H = cell_holder_of(holder)
	var/obj/item/cell/cell = H ? holder.vars[H.cell_var] : null
	if(cell && cap_should_run(holder))
		return list(cell.fully_charged() ? "It has finished charging \the [cell]." : "It is charging \the [cell].")
	return null
