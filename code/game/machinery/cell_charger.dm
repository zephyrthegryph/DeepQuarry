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
	var/chargelevel = -1
	circuit = /obj/item/circuitboard/cell_charger
	maintenance_flags = MACHINE_MAINT_STANDARD

/obj/machinery/cell_charger/Initialize(mapload)
	. = ..()
	default_apply_parts()
	add_overlay("ccharger1")

DECLARE_APPEARANCE_PROC(/obj/machinery/cell_charger, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/cell_charger/appearance_overlays()
	. = list()
	if(!anchored)
		icon_state = "ccharger2"

	if(charging && operable())
		var/newlevel = 	round(charging.percent() * 4.0 / 99)

		. += "ccharger-o[newlevel]"

		chargelevel = newlevel
		. += image(charging.icon, charging.icon_state)
		. += "ccharger-[charging.connector_type]-on"

	else if(anchored)
		icon_state = "ccharger0"
		. += "ccharger1"

/obj/machinery/cell_charger/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 5)
		. += "[charging ? "[charging]" : "Nothing"] is in [src]."
		if(charging)
			. += "Current charge: [charging.charge] / [charging.maxcharge]"

/obj/machinery/cell_charger/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/cell_charger_insert,
		/datum/interaction/machine_hand/ungated/cell_charger_take,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Take cell", PROC_REF(cell_charger_silicon_take)))
	..()

/// Its charge rate follows its capacitors (cap_parts(): efficiency is derived from the parts, never written by hand),
/// and the RPED upgrades them through the parts capability's "replace_parts" op.
/obj/machinery/cell_charger/capabilities()
	. = ..()
	. += cap_parts(list(
		part_stat(nameof(efficiency), /obj/item/stock_parts/capacitor, base = 1, per = 0.5, scale = nameof(active_power_usage)),
	))

/// Insert a cell to charge it.
/datum/interaction/machine_item/cell_charger_insert
	id = "cell_charger_insert"
	name = "Insert cell"
	held_type = /obj/item/cell
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_TARGET, /obj/machinery/cell_charger/proc/is_working, "it isn't working"), REQ_TARGET_STATE(/obj/machinery/cell_charger/proc/can_insert_cell))
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/cell_charger/proc/is_anchored, "it isn't anchored"))
	effect = /obj/machinery/cell_charger/proc/interaction_insert

/obj/machinery/cell_charger/proc/is_working(mob/actor, atom/target, obj/item/held)
	return !has_stat(BROKEN)

/obj/machinery/cell_charger/proc/is_anchored(mob/actor, atom/target, obj/item/held)
	return anchored

/// Requirement: TRUE, or why the cell can't go in.
/obj/machinery/cell_charger/proc/can_insert_cell(mob/user, atom/target, obj/item/W)
	if(istype(W, /obj/item/cell/device))
		return "it isn't fitted for that type of cell"
	if(charging)
		return "there is already [charging] in it"
	var/area/a = loc?.loc
	if(isarea(a) && a.power_equip == 0) // There's no APC in this area, don't try to cheat power!
		return "it blinks red as you try to insert [W]"
	return TRUE

/obj/machinery/cell_charger/proc/interaction_insert(mob/user, obj/item/W, datum/interaction/interaction)
	var/area/a = loc.loc // Gets our locations location, like a dream within a dream
	if(!isarea(a))
		return TRUE

	user.drop_item()
	W.forceMove(src)
	set_charging(W)
	changed(src, CHANGE_MACHINE_OCCUPANT)
	act_message(user, src, MSG_SELF("You insert [charging] into %T%."), MSG_OTHERS("%U% inserts [charging] into %T%."))
	chargelevel = -1
	update_icon()
	return TRUE

/obj/machinery/cell_charger/wrench_act(mob/user, obj/item/tool)
	if(charging)
		to_chat(user, span_warning("Remove [charging] first!"))
		return ITEM_INTERACT_BLOCKING
	set_anchored(!anchored)
	changed(src, CHANGE_MACHINE_ANCHORED)
	to_chat(user, "You [anchored ? "attach" : "detach"] [src] [anchored ? "to" : "from"] the ground")
	playsound(src, tool.usesound, 75, TRUE)
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
		act_message(user, src, MSG_SELF("You remove [charging] from %T%."), MSG_OTHERS("%U% removes [charging] from %T%."))

		set_charging(null)
		chargelevel = -1
		changed(src, CHANGE_MACHINE_OCCUPANT)
		update_icon()
	return TRUE

/// Old attack_ai: a cyborg next to it takes the cell out. Nothing for the AI.
/obj/machinery/cell_charger/proc/cell_charger_silicon_take(mob/user, obj/item/held, datum/interaction/interaction)
	if(isrobot(user) && Adjacent(user)) // Borgs can remove the cell if they are near enough
		if(charging)
			act_message(user, src, MSG_SELF("You remove [charging] from %T%."), MSG_OTHERS("%U% removes [charging] from %T%."))
			charging.forceMove(src.loc)
			charging.update_icon()
			set_charging(null)
			changed(src, CHANGE_MACHINE_OCCUPANT)
			update_icon()
	return TRUE


