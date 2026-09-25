/obj/machinery/cell_charger
	name = "heavy-duty cell charger"
	desc = "A much more powerful version of the standard recharger that is specially designed for charging power cells."
	icon = 'icons/obj/power.dmi'
	icon_state = "ccharger0"
	anchored = 1
	use_power = USE_POWER_IDLE
	idle_power_usage = 5
	active_power_usage = 60000	//60 kW. (this the power drawn when charging)
	var/efficiency = 60000 //will provide the modified power rate when upgraded
	power_channel = EQUIP
	/// Runs on the machine pipeline (machine_pipeline.dm): the power/cell_charger stage charges.
	polls = FALSE
	var/obj/item/cell/charging = null
	var/chargelevel = -1
	circuit = /obj/item/circuitboard/cell_charger
	maintenance_flags = MACHINE_MAINT_STANDARD

/obj/machinery/cell_charger/Initialize(mapload)
	. = ..()
	default_apply_parts()
	add_overlay("ccharger1")

/obj/machinery/cell_charger/update_icon()
	if(!anchored)
		cut_overlays()
		icon_state = "ccharger2"

	if(charging && !(stat & (BROKEN|NOPOWER)))
		var/newlevel = 	round(charging.percent() * 4.0 / 99)
		//to_world("nl: [newlevel]")

		cut_overlays()
		add_overlay("ccharger-o[newlevel]")

		chargelevel = newlevel
		add_overlay(image(charging.icon, charging.icon_state))
		add_overlay("ccharger-[charging.connector_type]-on")

	else if(anchored)
		cut_overlays()
		icon_state = "ccharger0"
		add_overlay("ccharger1")

/obj/machinery/cell_charger/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 5)
		. += "[charging ? "[charging]" : "Nothing"] is in [src]."
		if(charging)
			. += "Current charge: [charging.charge] / [charging.maxcharge]"

/obj/machinery/cell_charger/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/cell_charger_insert,
		/datum/interaction/machine_item/cell_charger_part_replacement,
		/datum/interaction/machine_hand/ungated/cell_charger_take,
	)
	..()

/// Old attackby's `if(stat & BROKEN) return` guarded both branches: part_replacement too.
/datum/interaction/machine_item/cell_charger_part_replacement
	id = "cell_charger_part_replacement"
	name = "Replace parts"
	category = INTERACTION_CAT_MAINTAIN
	held_type = /obj/item/storage/part_replacer
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/cell_charger/proc/is_working, "it isn't working"))
	effect = /obj/machinery/proc/interaction_part_replacement

/// Insert a cell to charge it.
/datum/interaction/machine_item/cell_charger_insert
	id = "cell_charger_insert"
	name = "Insert cell"
	held_type = /obj/item/cell
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/cell_charger/proc/is_working, "it isn't working"))
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/cell_charger/proc/is_anchored, "it isn't anchored"))
	effect = /obj/machinery/cell_charger/proc/interaction_insert

/obj/machinery/cell_charger/proc/is_working(mob/actor, atom/target, obj/item/held)
	return !(stat & BROKEN)

/obj/machinery/cell_charger/proc/is_anchored(mob/actor, atom/target, obj/item/held)
	return anchored

/obj/machinery/cell_charger/proc/interaction_insert(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/cell/device))
		to_chat(user, span_warning("\The [src] isn't fitted for that type of cell."))
		return TRUE
	if(charging)
		to_chat(user, span_warning("There is already [charging] in [src]."))
		return TRUE
	var/area/a = loc.loc // Gets our locations location, like a dream within a dream
	if(!isarea(a))
		return TRUE
	if(a.power_equip == 0) // There's no APC in this area, don't try to cheat power!
		to_chat(user, span_warning("\The [src] blinks red as you try to insert [W]!"))
		return TRUE

	user.drop_item()
	W.loc = src
	charging = W
	om_changed(src, CHANGE_MACHINE_OCCUPANT)
	user.visible_message("[user] inserts [charging] into [src].", "You insert [charging] into [src].")
	chargelevel = -1
	update_icon()
	return TRUE

/obj/machinery/cell_charger/wrench_act(mob/user, obj/item/tool)
	if(charging)
		to_chat(user, span_warning("Remove [charging] first!"))
		return ITEM_INTERACT_BLOCKING
	anchored = !anchored
	om_changed(src, CHANGE_MACHINE_ANCHORED)
	to_chat(user, "You [anchored ? "attach" : "detach"] [src] [anchored ? "to" : "from"] the ground")
	playsound(src, tool.usesound, 75, TRUE)
	update_icon()
	return ITEM_INTERACT_SUCCESS

/// Take the charging cell out.
/datum/interaction/machine_hand/ungated/cell_charger_take
	id = "cell_charger_take"
	name = "Take out"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/cell_charger/proc/interaction_take

/obj/machinery/cell_charger/proc/interaction_take(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)

	if(charging)
		user.put_in_hands(charging)
		charging.update_icon()
		user.visible_message("[user] removes [charging] from [src].", "You remove [charging] from [src].")

		charging = null
		chargelevel = -1
		om_changed(src, CHANGE_MACHINE_OCCUPANT)
		update_icon()
	return TRUE

/obj/machinery/cell_charger/attack_ai(mob/user)
	if(isrobot(user) && Adjacent(user)) // Borgs can remove the cell if they are near enough
		if(charging)
			user.visible_message("[user] removes [charging] from [src].", "You remove [charging] from [src].")
			charging.loc = src.loc
			charging.update_icon()
			charging = null
			om_changed(src, CHANGE_MACHINE_OCCUPANT)
			update_icon()

/obj/machinery/cell_charger/RefreshParts()
	var/E = get_part_rating(/obj/item/stock_parts/capacitor)
	efficiency = active_power_usage * (1+ (E - 1)*0.5)
