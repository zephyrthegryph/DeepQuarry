/obj/machinery/floodlight
	name = "Emergency Floodlight"
	desc = "Let there be light!"
	icon = 'icons/obj/machines/floodlight.dmi'
	icon_state = "flood00"
	density = TRUE
	light_system = MOVABLE_LIGHT_DIRECTIONAL
	light_cone_y_offset = 8
	var/on = 0
	var/obj/item/cell/cell = null
	var/use = 200 // 200W light
	var/unlocked = 0
	var/open = 0
	var/brightness_on = 8		//can't remember what the maxed out value is

/obj/machinery/floodlight/Initialize(mapload)
	. = ..()
	cell = new(src)
	AddElement(/datum/element/climbable)
	AddElement(/datum/element/rotatable)

/obj/machinery/floodlight/update_icon()
	cut_overlays()
	icon_state = "flood[open ? "o" : ""][open && cell ? "b" : ""]0[on]"

/obj/machinery/floodlight/process()
	if(!on)
		return PROCESS_KILL

	if(!cell || (cell.charge < (use * CELLRATE)))
		turn_off(1)
		return PROCESS_KILL

	cell.use(use * CELLRATE)

	// If the cell is almost empty rarely "flicker" the light. Aesthetic only.
	if((cell.percent() < 10) && prob(5))
		set_light_range(brightness_on/2)
		set_light_power(brightness_on/4)
		addtimer(CALLBACK(src, PROC_REF(flicker_restore)), 20, TIMER_DELETE_ME)

/obj/machinery/floodlight/proc/flicker_restore()
	if(on)
		set_light_range(brightness_on)
		set_light_power(brightness_on/2)


// Returns 0 on failure and 1 on success
/obj/machinery/floodlight/proc/turn_on(loud = 0)
	if(!cell)
		return 0
	if(cell.charge < (use * CELLRATE))
		return 0

	on = 1
	START_MACHINE_PROCESSING(src)
	set_light_range(brightness_on)
	set_light_power(brightness_on/2)
	set_light_on(TRUE)
	update_icon()
	if(loud)
		visible_message("\The [src] turns on.")
	return 1

/obj/machinery/floodlight/proc/turn_off(loud = 0)
	on = 0
	set_light_on(FALSE)
	update_icon()
	if(loud)
		visible_message("\The [src] shuts down.")

/obj/machinery/floodlight/attack_ai(mob/user as mob)
	if(isrobot(user) && Adjacent(user))
		return attack_hand(user)

	if(on)
		turn_off(1)
	else
		if(!turn_on(1))
			to_chat(user, "You try to turn on \the [src] but it does not work.")

/obj/machinery/floodlight/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/floodlight_item,
		/datum/interaction/machine_hand/ungated/floodlight_use,
	)
	..()

/// Old attack_hand, which never called ..(): no gate.
/datum/interaction/machine_hand/ungated/floodlight_use
	id = "floodlight_use"
	name = "Use"
	effect = /obj/machinery/floodlight/proc/interaction_use

/obj/machinery/floodlight/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(open && cell)
		if(ishuman(user))
			if(!user.get_active_hand())
				user.put_in_hands(cell)
				cell.loc = user.loc
		else
			cell.loc = src.loc

		cell.add_fingerprint(user)
		cell.update_icon()

		cell = null
		on = 0
		set_light(0)
		to_chat(user, "You remove the power cell")
		update_icon()
		return TRUE

	if(on)
		turn_off(1)
	else
		if(!turn_on(1))
			to_chat(user, "You try to turn on \the [src] but it does not work.")

	update_icon()
	return TRUE

/**
 * Old attackby: never called `..()`, and `update_icon()` ran regardless of the item type
 * (outside the `istype` check), so it's a single interaction for any item, not just cells.
 */
/datum/interaction/machine_item/floodlight_item
	id = "floodlight_item"
	name = "Use item"
	held_type = /obj/item
	effect = /obj/machinery/floodlight/proc/interaction_item

/obj/machinery/floodlight/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/cell))
		if(open)
			if(cell)
				to_chat(user, "There is a power cell already installed.")
			else
				user.drop_item()
				W.loc = src
				cell = W
				to_chat(user, "You insert the power cell.")
	update_icon()
	return TRUE

/obj/machinery/floodlight/screwdriver_act(mob/user, obj/item/tool)
	if(open)
		return ITEM_INTERACT_BLOCKING
	unlocked = !unlocked
	to_chat(user, "You [unlocked ? "unscrew" : "screw"] the battery panel [unlocked ? "" : "in place"].")
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floodlight/crowbar_act(mob/user, obj/item/tool)
	if(!unlocked)
		return ITEM_INTERACT_BLOCKING
	open = !open
	if(!open)
		overlays = null
	to_chat(user, "You [open ? "remove" : "crowbar"] the battery panel[open ? "" : " in place"].")
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floodlight/starts_on
	icon_state = "flood01"

/obj/machinery/floodlight/starts_on/Initialize(mapload)
	. = ..()
	turn_on()
