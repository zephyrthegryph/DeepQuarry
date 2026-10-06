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
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(crowbar_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(screwdriver_used)))
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use item"), then(PROC_REF(interaction_item)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	op("floodlight_silicon_use", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(floodlight_silicon_use)))
	rotatable()

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
/obj/machinery/floodlight/proc/floodlight_silicon_use(datum/act/op/A)
	var/mob/user = A.actor
	if(!(A.authority & AUTH_REMOTE_ACCESS) && Adjacent(user)) // a cyborg beside it uses it by hand
		attack_hand(user)
		return TRUE

	if(on)
		turn_off(1)
	else
		if(!turn_on(1))
			to_chat(user, "You try to turn on \the [src] but it does not work.")
	return TRUE

/obj/machinery/floodlight/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
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
/obj/machinery/floodlight/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
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

/obj/machinery/floodlight/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	if(open)
		return OP_OK
	unlocked = !unlocked
	to_chat(user, "You [unlocked ? "unscrew" : "screw"] the battery panel [unlocked ? "" : "in place"].")
	return OP_OK

/obj/machinery/floodlight/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!unlocked)
		return OP_OK
	open = !open
	if(!open)
		overlays = null
	to_chat(user, "You [open ? "remove" : "crowbar"] the battery panel[open ? "" : " in place"].")
	return OP_OK

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
