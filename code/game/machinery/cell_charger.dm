// The heavy-duty cell charger (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md).
//
// ONE CAPABILITIES list says what it is: a machine that works only with power and a whole casing, a wrench-anchored base, a part-replacer target,
// a one-cell slot (`charging`, owned: the cell goes when the charger does), the ops that fill and empty the slot, and the charge loop.
// The take op sits at priority 5: below the insert (a refused insert keeps what is in the charger) and above a module-less cyborg's generic swallow of an
// empty touch. The imperative parts below are its own: the conditions and effects the list names, the charge frame, its power mode and its look.
//
// What the machine core still keeps until the machine track (phase 4): the stat bits (BROKEN, NOPOWER, ...) read through machine_basics()'s one
// bridge contribution, set_use_power(), RefreshParts() with the circuit board and its parts, and maintenance_flags (the panel and the crowbar).

MSG_DEF(charger/inserted, "You insert %I% into %T%.", "%U% inserts %I% into %T%.")
MSG_DEF_SELF(charger/wrong_cell, "It isn't fitted for that type of cell.")
MSG_DEF_SELF(charger/no_area_power, "It blinks red as you try to insert the cell.")

/obj/machinery/cell_charger
	name = "heavy-duty cell charger"
	desc = "A much more powerful version of the standard recharger that is specially designed for charging power cells."
	icon = 'icons/obj/power.dmi'
	icon_state = "ccharger0"
	anchored = 1
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 60000	//60 kW. (this the power drawn when charging)
	/// The charge given per machine frame, in watts; the capacitors set it (RefreshParts()).
	var/efficiency = 60000
	power_channel = EQUIP
	/// The cell being charged.
	var/obj/item/cell/charging
	/// How full the shown cell looks (0 to 4), or -1 with none: the look reads it, the charge frame writes it.
	var/chargelevel = -1
	circuit = /obj/item/circuitboard/cell_charger
	maintenance_flags = MACHINE_MAINT_STANDARD

TRACKED(/obj/machinery/cell_charger, chargelevel)

CAPABILITIES(/obj/machinery/cell_charger)
	default_parts()
	machine_basics(repair = NONE)
	anchor(empty = nameof(charging))
	part_replacement()
	extend("part_replacement.replace", needs(req_operable()))
	owns_one(nameof(charging), /obj/item/cell)
	op("insert", item(/obj/item/cell), when(nameof(anchored)),
		needs(req_bool(PROC_REF(can_insert), because = PROC_REF(insert_refusal))),
		put_in(nameof(charging)), says(MSG(charger/inserted)))
	op("take", hand(), when(nameof(charging)), priority(OP_PRIORITY_NORMAL + 5), then(PROC_REF(take_cell)))
	examine_line(PROC_REF(examine_contents))
	on_change(nameof(charging), ANY, then(PROC_REF(charging_changed)))
	on_change(nameof(anchored), ANY, then(PROC_REF(condition_changed)))
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(condition_changed)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(charge_frame)), when = nameof(charging))

/obj/machinery/cell_charger/Initialize(mapload)
	. = ..()
	settle_power()

/// Its charge rate follows its capacitors (the machine core calls this when parts change).
/obj/machinery/cell_charger/RefreshParts()
	var/rating = get_part_rating(/obj/item/stock_parts/capacitor)
	efficiency = active_power_usage * (1 + (rating - 1) * 0.5)

// ---- the slot's conditions ----

/// Why this cell cannot go in now, or null: a casing that is broken, a device cell, a cell already in, an area with no power (it will not let the
/// charger cheat power where no APC serves).
/obj/machinery/cell_charger/proc/insert_refusal(datum/act/op/A)
	var/obj/item/held = A.held
	if(broken_now())
		return /datum/msg/machine/inoperable
	if(istype(held, /obj/item/cell/device))
		return /datum/msg/charger/wrong_cell
	if(charging)
		return /datum/msg/bay/full
	var/area/a = loc?.loc // ALLOW(reads): the area a machine stands in is legacy map state, read when a cell is offered, never from a cached menu
	if(isarea(a) && a.power_equip == 0)
		return /datum/msg/charger/no_area_power
	return null

/obj/machinery/cell_charger/proc/can_insert(datum/act/op/A)
	return isnull(insert_refusal(A))

/// The empty hand takes the cell out. A cyborg takes it with its gripper.
/obj/machinery/cell_charger/proc/take_cell(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/cell/cell = charging
	if(!cell || !user)
		return OP_REFUSED
	add_fingerprint(user)
	act_message(user, src, MSG_SELF("You remove [cell] from %T%."), MSG_OTHERS("%U% removes [cell] from %T%."))
	varslot_take(src, nameof(charging), user, op_carrier(A)) // a cyborg's gripper carries it
	cell.update_icon()
	return OP_OK

// ---- the charge loop ----

/// Powered, whole and bolted down.
/obj/machinery/cell_charger/proc/usable()
	return operable() && anchored

/// The power mode this charger should be in: off when it cannot work, idle with nothing to charge, active while it charges.
/obj/machinery/cell_charger/proc/settle_power()
	if(!usable())
		set_use_power(USE_POWER_OFF)
	else if(!charging || charging.fully_charged())
		set_use_power(USE_POWER_IDLE)
	else
		set_use_power(USE_POWER_ACTIVE)

/// One machine frame: the cell takes its share of charge.
/obj/machinery/cell_charger/proc/charge_frame(datum/act/timer/A)
	if(usable() && charging && !charging.fully_charged())
		charging.give(efficiency * CELLRATE)
		set_chargelevel(level_of(charging))
	settle_power()

/// It was bolted down or unbolted, or its power or casing changed: the power mode follows.
/obj/machinery/cell_charger/proc/condition_changed(datum/act/A)
	settle_power()

/// A cell went in or out: the power mode and the shown level follow.
/obj/machinery/cell_charger/proc/charging_changed(datum/act/A)
	set_chargelevel(charging ? level_of(charging) : -1)
	settle_power()

/// How full the cell looks, 0 to 4.
/obj/machinery/cell_charger/proc/level_of(obj/item/cell/cell)
	return round(cell.percent() * 4.0 / 99)

// ---- what it shows ----

/obj/machinery/cell_charger/draw(datum/look/look)
	..()
	look.state(anchored ? "ccharger0" : "ccharger2")
	var/obj/item/cell/cell = charging
	if(cell && operable())
		look.overlay("ccharger-o[chargelevel]")
		look.overlay(cell.icon_state, icon = cell.icon) // ALLOW(sys_dx_untracked_read): a cell's sprite is fixed for its life
		look.overlay("ccharger-[cell.connector_type]-on") // ALLOW(sys_dx_untracked_read): a cell's connector type is fixed for its life
	else if(anchored)
		look.overlay("ccharger1")

/// Within a few tiles it says what it holds.
/obj/machinery/cell_charger/proc/examine_contents(datum/act/op/A)
	var/mob/user = A.actor
	if(!user || get_dist(user, src) > 5)
		return null
	var/obj/item/cell/cell = charging
	var/list/lines = list("[cell ? "[cell]" : "Nothing"] is in [src].")
	if(cell)
		lines += "Current charge: [cell.charge] / [cell.maxcharge]"
	return lines
