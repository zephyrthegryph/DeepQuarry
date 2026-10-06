/obj/machinery/floodlight
	name = "Emergency Floodlight"
	desc = "Let there be light!"
	icon = 'icons/obj/machines/floodlight.dmi'
	icon_state = "flood00"
	density = TRUE
	light_system = MOVABLE_LIGHT_DIRECTIONAL
	light_cone_y_offset = 8
	on = 0
	var/obj/item/cell/cell = null
	var/use = 200 // 200W light
	var/unlocked = 0
	var/open = 0
	var/brightness_on = 8		//can't remember what the maxed out value is

CAPABILITIES(/obj/machinery/floodlight)
	started_work(step = PROC_REF(work_step), starts = TRUE, when = nameof(on), wakes_on = list(nameof(on)))
	climb()

/obj/machinery/floodlight/Initialize(mapload)
	. = ..()
	make_rotatable()

/obj/machinery/floodlight/proc/appearance_battery()
	return (open && cell) ? 1 : 0

/// The look (the draw sweep: from its template).
/obj/machinery/floodlight/draw(datum/look/look)
	..()
	look.state("flood[open ? "o" : ""][appearance_battery() ? "b" : ""]0[on]")

/obj/machinery/floodlight/proc/work_step(datum/act/timer/A)
	if(!cell || (cell.charge < (use * CELLRATE)))
		turn_off(1)
		return PROCESS_KILL

	cell.use(use * CELLRATE)

	// If the cell is almost empty rarely "flicker" the light. Aesthetic only.
	if((cell.percent() < 10) && prob(5))
		set_light_range(brightness_on/2)
		set_light_power(brightness_on/4)
		after(src, 20, PROC_REF(flicker_restore))

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

	set_on(1)
	set_light_range(brightness_on)
	set_light_power(brightness_on/2)
	set_light_on(TRUE)
	changed(src)
	if(loud)
		visible_message("\The [src] turns on.")
	return 1

/obj/machinery/floodlight/proc/turn_off(loud = 0)
	set_on(0)
	set_light_on(FALSE)
	changed(src)
	if(loud)
		visible_message("\The [src] shuts down.")

/// Old attack_ai: a cyborg next to it uses it by hand; otherwise it's switched remotely.
/obj/machinery/floodlight/proc/floodlight_silicon_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(isrobot(user) && Adjacent(user))
		attack_hand(user)
		return TRUE

	if(on)
		turn_off(1)
	else
		if(!turn_on(1))
			to_chat(user, "You try to turn on \the [src] but it does not work.")
	return TRUE

/obj/machinery/floodlight/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/floodlight_item,
		/datum/interaction/machine_hand/ungated/floodlight_use,
	)
	into += dq_interaction_from_spec(type, INTERACT_SILICON("Toggle", PROC_REF(floodlight_silicon_use)))
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
				cell.forceMove(user.loc)
		else
			cell.forceMove(src.loc)

		cell.add_fingerprint(user)
		cell.update_icon()

		own_take(src, nameof(cell))
		set_on(0)
		set_light(0)
		to_chat(user, "You remove the power cell")
		changed(src)
		return TRUE

	if(on)
		turn_off(1)
	else
		if(!turn_on(1))
			to_chat(user, "You try to turn on \the [src] but it does not work.")

	changed(src)
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
				if(!move_into(src, nameof(src.cell), W, user))
					return TRUE
				to_chat(user, "You insert the power cell.")
	changed(src)
	return TRUE

/obj/machinery/floodlight/screwdriver_act(mob/user, obj/item/tool)
	if(open)
		return ITEM_INTERACT_BLOCKING
	unlocked = !unlocked
	to_chat(user, "You [unlocked ? "unscrew" : "screw"] the battery panel [unlocked ? "" : "in place"].")
	changed(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floodlight/crowbar_act(mob/user, obj/item/tool)
	if(!unlocked)
		return ITEM_INTERACT_BLOCKING
	open = !open
	if(!open)
		overlays = null
	to_chat(user, "You [open ? "remove" : "crowbar"] the battery panel[open ? "" : " in place"].")
	changed(src)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/floodlight/starts_on
	icon_state = "flood01"

/obj/machinery/floodlight/starts_on/Initialize(mapload)
	. = ..()
	turn_on()


/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/floodlight/step_start_condition()
	return on

/obj/machinery/floodlight/ownership()
	. = ..()
	. += owns(nameof(cell), policy = OWN_CONTAINED, starts = /obj/item/cell)
