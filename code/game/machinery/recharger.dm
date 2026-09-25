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

//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31
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
	var/efficiency = 40000 //will provide the modified power rate when upgraded
	/// Runs on the machine pipeline (machine_pipeline.dm): the power/recharger stage charges.
	polls = FALSE
	var/obj/item/charging = null
	var/icon_state_charged = "recharger2"
	var/icon_state_charging = "recharger1"
	var/icon_state_idle = "recharger0" //also when unpowered
	///If we can be wrenched and moved around or not.
	var/portable = TRUE
	///If we can charge everything or use a smaller list.
	var/small = FALSE
	circuit = /obj/item/circuitboard/recharger

/obj/machinery/recharger/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/recharger/Destroy()
	if(charging)
		charging.update_icon()
		charging.forceMove(src.loc)
		charging = null
	. = ..()

/obj/machinery/recharger/examine(mob/user)
	. = ..()

	if(get_dist(user, src) <= 5)
		. += "[charging ? "[charging]" : "Nothing"] is in [src]."
		if(charging)
			var/obj/item/cell/C = charging.get_cell()
			if(C)				// Sometimes we get things without cells in it.
				. += "Current charge: [C.charge] / [C.maxcharge]"

///Checks valid items to see if there's any reasons we wouldn't allow them to be put in.
/obj/machinery/recharger/proc/do_allowed_checks(obj/item/G, mob/user)
	. = FALSE
	if(charging)
		to_chat(user, span_warning("\A [charging] is already charging here."))
		return
	// Checks to make sure he's not in space doing it, and that the area got proper power.
	if(!powered())
		to_chat(user, span_warning("\The [src] blinks red as you try to insert [G]!"))
		return
	if(istype(G, /obj/item/gun/energy))
		var/obj/item/gun/energy/E = G
		if(E.self_recharge)
			to_chat(user, span_notice("\The [E] has no recharge port."))
			return
	if(istype(G, /obj/item/modular_computer))
		var/obj/item/modular_computer/C = G
		if(!C.battery_module)
			to_chat(user, span_notice("\The [C] does not have a battery installed. "))
			return
	if(istype(G, /obj/item/flash))
		var/obj/item/flash/F = G
		if(F.use_external_power)
			to_chat(user, span_notice("\The [F] has no recharge port."))
			return
	if(istype(G, /obj/item/weldingtool/electric))
		var/obj/item/weldingtool/electric/EW = G
		if(EW.use_external_power)
			to_chat(user, span_notice("\The [EW] has no recharge port."))
			return
	if(!G.get_cell() && !is_type_in_list(G, GLOB.recharger_battery_exempt))
		to_chat(user, "\The [G] does not have a battery installed.")
		return
	if(istype(G, /obj/item/paicard))
		var/obj/item/paicard/ourcard = G
		if(ourcard.panel_open)
			to_chat(user, span_warning("\The [ourcard] won't fit in the recharger with its panel open."))
			return
		if(ourcard.pai)
			if(ourcard.pai.stat == CONSCIOUS)
				to_chat(user, span_warning("\The [ourcard] boops... it doesn't need to be recharged!"))
				return
		else
			to_chat(user, span_warning("\The [ourcard] doesn't have a personality!"))
			return
	return TRUE

/obj/machinery/recharger/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/recharger_insert,
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_hand/ungated/recharger_take,
		/datum/interaction/machine_drag/recharger_insert,
	)
	..()

/// Put a chargeable device in the recharger.
/datum/interaction/machine_item/recharger_insert
	id = "recharger_insert"
	name = "Insert to charge"
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/recharger/proc/takes_device, "it doesn't charge that"))
	effect = /obj/machinery/recharger/proc/interaction_insert

/// Drag a chargeable device onto the recharger.
/datum/interaction/machine_drag/recharger_insert
	id = "recharger_drag_insert"
	name = "Insert to charge"
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/recharger/proc/takes_device, "it doesn't charge that"))
	effect = /obj/machinery/recharger/proc/interaction_drag_insert

/// Take the charging device out.
/datum/interaction/machine_hand/ungated/recharger_take
	id = "recharger_take"
	name = "Take out"
	category = INTERACTION_CAT_EJECT
	requires = list(REQ_REACH_ADJACENT)
	effect = /obj/machinery/recharger/proc/interaction_take

/// Whether `held` is a device this recharger (or wall charger) takes.
/obj/machinery/recharger/proc/takes_device(mob/actor, atom/target, atom/held)
	if(!held)
		return FALSE
	return is_type_in_list(held, small ? GLOB.allowed_wallcharger_devices : GLOB.allowed_recharger_devices)

/obj/machinery/recharger/proc/interaction_insert(mob/user, obj/item/G, datum/interaction/interaction)
	if(!do_allowed_checks(G, user))
		return TRUE
	if(HAS_TRAIT(user, TRAIT_UNLUCKY) && prob(10))
		user.visible_message("[user] inserts [charging] into [src] backwards!", "You insert [charging] into [src] backwards!")
		user.drop_item()
		G.forceMove(get_turf(src))
		return TRUE
	user.drop_item()
	G.forceMove(src)
	charging = G
	om_changed(src, CHANGE_MACHINE_OCCUPANT)
	update_icon()
	user.visible_message("[user] inserts [charging] into [src].", "You insert [charging] into [src].")
	return TRUE

/obj/machinery/recharger/proc/interaction_drag_insert(mob/user, obj/item/G, datum/interaction/interaction)
	if(!do_allowed_checks(G, user))
		return TRUE
	G.forceMove(src)
	charging = G
	om_changed(src, CHANGE_MACHINE_OCCUPANT)
	update_icon()
	user.visible_message("[user] inserts [charging] into [src].", "You insert [charging] into [src].")
	return TRUE

/obj/machinery/recharger/wrench_act(mob/user, obj/item/tool)
	if(!portable)
		return ..()
	if(charging)
		to_chat(user, span_warning("Remove [charging] first!"))
		return ITEM_INTERACT_BLOCKING
	anchored = !anchored
	om_changed(src, CHANGE_MACHINE_ANCHORED)
	to_chat(user, "You [anchored ? "attached" : "detached"] [src].")
	playsound(src, tool.usesound, 75, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/recharger/proc/interaction_take(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(charging)
		user.visible_message("[user] removes [charging] from [src].", "You remove [charging] from [src].")
		charging.update_icon()
		user.put_in_hands(charging)
		charging = null
		om_changed(src, CHANGE_MACHINE_OCCUPANT)
		update_icon()
	return TRUE

/obj/machinery/recharger/attack_ai(mob/user)
	if(isrobot(user) && Adjacent(user)) // Borgs can remove the cell if they are near enough
		if(charging)
			user.visible_message("[user] removes [charging] from [src].", "You remove [charging] from [src].")
			charging.update_icon()
			charging.forceMove(src.loc)
			charging = null
			om_changed(src, CHANGE_MACHINE_OCCUPANT)
			update_icon()

/// One frame of charging (the machine pipeline's power/recharger stage decides whether to).
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
		if(!C.fully_charged())
			icon_state = icon_state_charging
			C.give(CELLRATE*efficiency)
			update_use_power(USE_POWER_ACTIVE)
		else
			icon_state = icon_state_charged
			update_use_power(USE_POWER_IDLE)
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
		pcard.forceMove(get_turf(src))
		charging = null
		update_icon()
		return
	if(pcard.pai.is_injured())
		pcard.pai.mend(TREAT_PLATING_REPAIR, 5)
		pcard.pai.mend(TREAT_WIRING_REPAIR, 5)
		pcard.pai.mend(TREAT_TISSUE_REPAIR, 5)
		pcard.pai.mend(TREAT_BURN_CARE, 5)
	else
		charging = null
		update_icon()
		visible_message(span_notice("\The [src] ejects the [pcard]!"))
		pcard.forceMove(get_turf(src))
		pcard.pai.full_restore()

///Charges microbatteries. One projectile at a time.
/obj/machinery/recharger/proc/charge_microbattery(obj/item/ammo_casing/microbattery/batt)
	if(batt.shots_left >= initial(batt.shots_left))
		batt.shots_left = initial(batt.shots_left)
		icon_state = icon_state_charged
		update_use_power(USE_POWER_IDLE)
	else
		icon_state = icon_state_charging
		batt.shots_left++
		update_use_power(USE_POWER_ACTIVE)

///Charges cell magazines, one projectile at a time.
/obj/machinery/recharger/proc/charge_cell_magazine(obj/item/ammo_magazine/cell_mag/magazine)
	if(LAZYLEN(magazine.stored_ammo))
		for(var/obj/item/ammo_casing/microbattery/shot_to_charge in magazine)
			if(shot_to_charge.shots_left >= initial(shot_to_charge.shots_left))
				continue
			shot_to_charge.shots_left++
			icon_state = icon_state_charging
			update_use_power(USE_POWER_ACTIVE)
			return
	icon_state = icon_state_charged
	update_use_power(USE_POWER_IDLE)

///Charges cell guns. First charges the currently chambered battery, then the batteries in the magazine.
/obj/machinery/recharger/proc/charge_cell_gun(obj/item/gun/projectile/cell_loaded/cellgun)
	var/obj/item/ammo_magazine/magazine = cellgun.ammo_magazine //CAN BE NULL.
	var/obj/item/ammo_casing/microbattery/batt = cellgun.chambered //CAN BE NULL.

	//First, we charge the currently chambered battery if there is one.
	if(batt && !(batt.shots_left >= initial(batt.shots_left)))
		icon_state = icon_state_charging
		batt.shots_left++
		update_use_power(USE_POWER_ACTIVE)
		return
	//Second, we charge the batteries in the magazine.
	else if(magazine && LAZYLEN(magazine.stored_ammo))
		for(var/obj/item/ammo_casing/microbattery/shot_to_charge in magazine)
			if(shot_to_charge.shots_left >= initial(shot_to_charge.shots_left))
				continue
			shot_to_charge.shots_left++
			icon_state = icon_state_charging
			update_use_power(USE_POWER_ACTIVE)
			return //only heal one at a time.
	//If the chambered battery AND the magazine are all full, we are done.
	icon_state = icon_state_charged
	update_use_power(USE_POWER_IDLE)
	return


/obj/machinery/recharger/update_icon()	// Immediate feedback; the power stage refines it (charged, charging) each frame.
	if(charging)
		icon_state = icon_state_charging
	else
		icon_state = icon_state_idle

/obj/machinery/recharger/RefreshParts()
	var/E = get_part_rating(/obj/item/stock_parts/capacitor)
	efficiency = active_power_usage * (1+ (E - 1)*0.5)

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
