// The recharger and the wall recharger (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md).
//
// ONE CAPABILITIES list says what each is: a machine that works only with power and a whole casing, a wrench-anchored base (the wall one is bolted
// to its wall), a part-replacer target, a one-item slot (`charging`, owned: a device left in it is dropped when the recharger goes), the ops that
// fill it (by hand or by dragging) and empty it, and the charge loop. The imperative parts below are its own: the conditions and effects the list
// names (the take op sits at priority 5: below the insert, above a module-less cyborg's generic swallow of an empty touch), the charge frames for each kind of device, its power mode and its look.
//
// What the machine core still keeps until the machine track (phase 4): the stat bits (BROKEN, NOPOWER, ...) read through machine_basics()'s one
// bridge contribution, set_use_power(), RefreshParts() with the circuit board and its parts, and maintenance_flags (the panel and the crowbar).

MSG_DEF_SELF(recharger/occupied, "Something is already charging here.")
MSG_DEF_SELF(recharger/no_power, "It blinks red as you try to insert that.")
MSG_DEF_SELF(recharger/no_port, "That has no recharge port.")
MSG_DEF_SELF(recharger/no_battery_installed, "That does not have a battery installed.")
MSG_DEF_SELF(recharger/pai_panel, "That won't fit in the recharger with its panel open.")
MSG_DEF_SELF(recharger/pai_fine, "That boops... it doesn't need to be recharged!")
MSG_DEF_SELF(recharger/pai_empty, "That doesn't have a personality!")

GLOBAL_LIST_INIT(allowed_recharger_devices, list(
	/obj/item/gun/energy,
	/obj/item/gun/magnetic,
	/obj/item/melee/baton,
	/obj/item/modular_computer,
	/obj/item/computer_hardware/battery_module,
	/obj/item/cell,
	/obj/item/suit_cooling_unit/emergency,
	/obj/item/flashlight,
	/obj/item/electronic_assembly,
	/obj/item/weldingtool/electric,
	/obj/item/ammo_magazine/smart,
	/obj/item/flash,
	/obj/item/defib_kit,
	/obj/item/ammo_casing/microbattery,
	/obj/item/paicard,
	/obj/item/personal_shield_generator,
	/obj/item/gun/projectile/cell_loaded,
	/obj/item/ammo_magazine/cell_mag,
	/obj/item/medigun_backpack
	))

GLOBAL_LIST_INIT(allowed_wallcharger_devices, list(
	/obj/item/gun/energy,
	/obj/item/gun/magnetic,
	/obj/item/melee/baton,
	/obj/item/flashlight,
	/obj/item/cell/device
	))

GLOBAL_LIST_INIT(recharger_battery_exempt, list(
	/obj/item/ammo_casing/microbattery,
	/obj/item/paicard,
	/obj/item/gun/projectile/cell_loaded,
	/obj/item/ammo_magazine/cell_mag
	))

/// What the recharger is doing, as the look shows it.
#define RECHARGER_IDLE 0
#define RECHARGER_CHARGING 1
#define RECHARGER_CHARGED 2

/obj/machinery/recharger
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "recharger"
	desc = "A standard recharger for all devices that use power."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "recharger0"
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 4
	active_power_usage = 40000	//40 kW
	/// The charge given per machine frame, in watts; the capacitors set it (RefreshParts()).
	var/efficiency = 40000
	var/icon_state_charged = "recharger2"
	var/icon_state_charging = "recharger1"
	var/icon_state_idle = "recharger0" //also when unpowered
	///If we can be wrenched and moved around or not.
	var/portable = TRUE
	///If we can charge everything or use a smaller list.
	var/small = FALSE
	/// The item being recharged.
	var/obj/item/charging
	/// RECHARGER_*: what the look shows.
	var/charge_phase = RECHARGER_IDLE
	circuit = /obj/item/circuitboard/recharger

TRACKED(/obj/machinery/recharger, charge_phase)

CAPABILITIES(/obj/machinery/recharger)
	default_parts()
	machine_basics(repair = NONE)
	anchor(empty = nameof(charging))
	part_replacement()
	owns_one(nameof(charging), /obj/item, on_destroy = ON_DESTROY_SPILL)
	op("insert", item(/obj/item), when(req_bool(PROC_REF(takes_device))),
		needs(req(PROC_REF(device_refusal))),
		then(PROC_REF(insert_device)))
	op("insert_drag", item(/obj/item), gesture(GESTURE_DRAG), when(req_bool(PROC_REF(takes_device))),
		needs(req(PROC_REF(device_refusal))),
		then(PROC_REF(drag_in_device)))
	op("take", hand(), when(nameof(charging)), priority(OP_PRIORITY_NORMAL + 5), then(PROC_REF(take_device)))
	examine_line(PROC_REF(examine_contents))
	on_change(nameof(charging), ANY, then(PROC_REF(charging_changed)))
	on_change(nameof(anchored), ANY, then(PROC_REF(charging_changed)))
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(charging_changed)))
	every(MACHINE_SERVICE_INTERVAL, then(PROC_REF(charge_frame)), when = nameof(charging))

/// A wall recharger is bolted to its wall: its wrench does nothing.
/obj/machinery/recharger/wallcharger
	name = "wall recharger"
	desc = "A more powerful recharger designed for energy weapons."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "wrecharger0"
	plane = TURF_PLANE
	layer = ABOVE_TURF_LAYER
	active_power_usage = 60000	//60 kW , It's more specialized than the standalone recharger (guns, batons, and flashlights only) so make it more powerful
	efficiency = 60000
	small = TRUE
	icon_state_charged = "wrecharger2"
	icon_state_charging = "wrecharger1"
	icon_state_idle = "wrecharger0"
	portable = FALSE
	circuit = /obj/item/circuitboard/recharger/wrecharger
	flags = WALL_ITEM

CAPABILITIES(/obj/machinery/recharger/wallcharger)
	without(CAP_ANCHOR)

/obj/machinery/recharger/Initialize(mapload)
	. = ..()
	settle_power()

/obj/machinery/recharger/RefreshParts()
	var/E = get_part_rating(/obj/item/stock_parts/capacitor)
	efficiency = active_power_usage * (1+ (E - 1)*0.5)

// ---- the slot's conditions ----

/// Whether the held item is a device this recharger (or wall charger) takes.
/obj/machinery/recharger/proc/takes_device(datum/act/op/A)
	var/obj/item/held = A.held
	if(!held)
		return FALSE
	for(var/type in (small ? GLOB.allowed_wallcharger_devices : GLOB.allowed_recharger_devices)) // ALLOW(reads): the lists are constants and an item's type is fixed for its life
		if(istype(held, type))
			return TRUE
	return FALSE

/// Why this device cannot go in now, or null.
/obj/machinery/recharger/proc/device_refusal(datum/act/op/A)
	var/obj/item/G = A.held
	if(charging)
		return /datum/msg/recharger/occupied
	// Checks to make sure he's not in space doing it, and that the area got proper power.
	if(!cap_powered())
		return /datum/msg/recharger/no_power
	if(istype(G, /obj/item/gun/energy))
		var/obj/item/gun/energy/E = G
		if(E.self_recharge)
			return /datum/msg/recharger/no_port
	if(istype(G, /obj/item/modular_computer))
		var/obj/item/modular_computer/C = G
		if(!C.battery_module)
			return /datum/msg/recharger/no_battery_installed
	if(istype(G, /obj/item/flash))
		var/obj/item/flash/F = G
		if(F.use_external_power)
			return /datum/msg/recharger/no_port
	if(istype(G, /obj/item/weldingtool/electric))
		var/obj/item/weldingtool/electric/EW = G
		if(EW.use_external_power)
			return /datum/msg/recharger/no_port
	if(!G.get_cell() && !battery_exempt(G))
		return /datum/msg/recharger/no_battery_installed
	if(istype(G, /obj/item/paicard))
		var/obj/item/paicard/ourcard = G
		if(ourcard.panel_open)
			return /datum/msg/recharger/pai_panel
		if(ourcard.pai)
			if(ourcard.pai.stat == CONSCIOUS)
				return /datum/msg/recharger/pai_fine
		else
			return /datum/msg/recharger/pai_empty
	return null

/// Devices that charge without a cell of their own (a pAI card, microbatteries).
/obj/machinery/recharger/proc/battery_exempt(obj/item/G)
	for(var/type in GLOB.recharger_battery_exempt)
		if(istype(G, type))
			return TRUE
	return FALSE


/// A device goes in by hand: an unlucky person sometimes puts it in backwards, and it lands on the floor.
/obj/machinery/recharger/proc/insert_device(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/G = A.held
	if(has_trait(user, TRAIT_UNLUCKY) && prob(10))
		if(!user.unEquip(G, target = get_turf(src)) || G.loc != get_turf(src))
			return OP_REFUSED
		act_message(user, src, MSG_SELF("You insert [G] into %T% backwards!"), MSG_OTHERS("%U% inserts [G] into %T% backwards!"))
		return OP_OK
	return put_device(user, G)

/// A device dragged onto it goes in (no luck involved).
/obj/machinery/recharger/proc/drag_in_device(datum/act/op/A)
	return put_device(A.actor, A.held)

/obj/machinery/recharger/proc/put_device(mob/user, obj/item/G)
	if(!varslot_insert(src, nameof(charging), G, user))
		return OP_REFUSED
	act_message(user, src, MSG_SELF("You insert [G] into %T%."), MSG_OTHERS("%U% inserts [G] into %T%."))
	return OP_OK

/// The empty hand takes the device out. A cyborg takes it with its gripper.
/obj/machinery/recharger/proc/take_device(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/device = charging
	if(!device || !user)
		return OP_REFUSED
	add_fingerprint(user)
	act_message(user, src, MSG_SELF("You remove [device] from %T%."), MSG_OTHERS("%U% removes [device] from %T%."))
	device.update_icon()
	varslot_take(src, nameof(charging), user, op_carrier(A)) // a cyborg's gripper carries it
	return OP_OK

// ---- the charge loop ----

/// Powered, whole and bolted down.
/obj/machinery/recharger/proc/usable()
	return operable() && anchored

/// The power mode and look this recharger should have: off when it cannot work, idle with nothing to charge, active while it charges.
/obj/machinery/recharger/proc/settle_power()
	if(!usable())
		set_use_power(USE_POWER_OFF)
		set_charge_phase(RECHARGER_IDLE)
	else if(!charging)
		set_use_power(USE_POWER_IDLE)
		set_charge_phase(RECHARGER_IDLE)
	else if(charging_complete())
		set_use_power(USE_POWER_IDLE)
		set_charge_phase(RECHARGER_CHARGED)
	else
		set_use_power(USE_POWER_ACTIVE)
		set_charge_phase(RECHARGER_CHARGING)

/// A device went in or out, or it was bolted or unbolted, or its power or casing changed: the power mode and look follow.
/obj/machinery/recharger/proc/charging_changed(datum/act/A)
	settle_power()

/// One machine frame.
/obj/machinery/recharger/proc/charge_frame(datum/act/timer/A)
	if(usable() && charging && !charging_complete())
		charge_step()
	settle_power()

/// One frame of charging.
/obj/machinery/recharger/proc/charge_step()
	if(istype(charging, /obj/item/paicard))
		charge_pai(charging)
		return
	if(istype(charging, /obj/item/gun/projectile/cell_loaded))
		charge_cell_gun(charging)
		return
	if(istype(charging, /obj/item/ammo_magazine/cell_mag))
		charge_cell_magazine(charging)
		return
	var/obj/item/cell/C = charging.get_cell()
	if(istype(C))
		C.give(CELLRATE*efficiency)
	else if(istype(charging, /obj/item/ammo_casing/microbattery))
		charge_microbattery(charging)

/obj/machinery/recharger/proc/charging_complete()
	if(!charging || istype(charging, /obj/item/paicard))
		return FALSE
	if(istype(charging, /obj/item/ammo_casing/microbattery))
		var/obj/item/ammo_casing/microbattery/battery = charging
		return battery.shots_left >= initial(battery.shots_left)
	if(istype(charging, /obj/item/ammo_magazine/cell_mag))
		var/obj/item/ammo_magazine/cell_mag/magazine = charging
		for(var/obj/item/ammo_casing/microbattery/battery in magazine)
			if(battery.shots_left < initial(battery.shots_left))
				return FALSE
		return TRUE
	if(istype(charging, /obj/item/gun/projectile/cell_loaded))
		var/obj/item/gun/projectile/cell_loaded/gun = charging
		var/obj/item/ammo_casing/microbattery/chambered = gun.chambered
		if(chambered && chambered.shots_left < initial(chambered.shots_left))
			return FALSE
		for(var/obj/item/ammo_casing/microbattery/battery in gun.ammo_magazine)
			if(battery.shots_left < initial(battery.shots_left))
				return FALSE
		return TRUE
	var/obj/item/cell/C = charging.get_cell()
	return C?.fully_charged()

///Charges PAIs.
/obj/machinery/recharger/proc/charge_pai(obj/item/paicard/pcard)
	if(pcard.is_damage_critical())
		varslot_take(src, nameof(charging), null)
		return
	if(pcard.pai.is_injured())
		pcard.pai.mend(TREAT_PLATING_REPAIR, 5)
		pcard.pai.mend(TREAT_WIRING_REPAIR, 5)
		pcard.pai.mend(TREAT_TISSUE_REPAIR, 5)
		pcard.pai.mend(TREAT_BURN_CARE, 5)
	else
		varslot_take(src, nameof(charging), null)
		visible_message(span_notice("\The [src] ejects the [pcard]!"))
		pcard.pai.full_restore()

///Charges microbatteries. One projectile at a time.
/obj/machinery/recharger/proc/charge_microbattery(obj/item/ammo_casing/microbattery/batt)
	if(batt.shots_left >= initial(batt.shots_left))
		batt.set_shots_left(initial(batt.shots_left))
	else
		batt.set_shots_left(batt.shots_left + 1)

///Charges cell magazines, one projectile at a time.
/obj/machinery/recharger/proc/charge_cell_magazine(obj/item/ammo_magazine/cell_mag/magazine)
	if(LAZYLEN(magazine.stored_ammo))
		for(var/obj/item/ammo_casing/microbattery/shot_to_charge in magazine)
			if(shot_to_charge.shots_left >= initial(shot_to_charge.shots_left))
				continue
			shot_to_charge.set_shots_left(shot_to_charge.shots_left + 1)
			return

///Charges cell guns. First charges the currently chambered battery, then the batteries in the magazine.
/obj/machinery/recharger/proc/charge_cell_gun(obj/item/gun/projectile/cell_loaded/cellgun)
	var/obj/item/ammo_magazine/magazine = cellgun.ammo_magazine //CAN BE NULL.
	var/obj/item/ammo_casing/microbattery/batt = cellgun.chambered //CAN BE NULL.

	//First, we charge the currently chambered battery if there is one.
	if(batt && !(batt.shots_left >= initial(batt.shots_left)))
		batt.set_shots_left(batt.shots_left + 1)
		return
	//Second, we charge the batteries in the magazine.
	else if(magazine && LAZYLEN(magazine.stored_ammo))
		for(var/obj/item/ammo_casing/microbattery/shot_to_charge in magazine)
			if(shot_to_charge.shots_left >= initial(shot_to_charge.shots_left))
				continue
			shot_to_charge.set_shots_left(shot_to_charge.shots_left + 1)
			return //only heal one at a time.

// ---- what it shows ----

/obj/machinery/recharger/draw(datum/look/look)
	..()
	switch(charge_phase)
		if(RECHARGER_CHARGED)
			look.state(icon_state_charged)
		if(RECHARGER_CHARGING)
			look.state(icon_state_charging)
		else
			look.state(icon_state_idle)

/// Within a few tiles it says what it holds.
/obj/machinery/recharger/proc/examine_contents(datum/act/op/A)
	var/mob/user = A.actor
	if(!user || get_dist(user, src) > 5)
		return null
	var/list/lines = list("[charging ? "[charging]" : "Nothing"] is in [src].")
	if(charging)
		var/obj/item/cell/C = charging.get_cell()
		if(C) // Sometimes we get things without cells in it.
			lines += "Current charge: [C.charge] / [C.maxcharge]"
	return lines
