/obj/machinery/floodlight
	name = "Emergency Floodlight"
	desc = "Let there be light!"
	icon = 'icons/obj/machines/floodlight.dmi'
	icon_state = "flood00"
	density = TRUE
	on = 0
	var/obj/item/cell/cell = null
	var/use = 200 // 200W light
	var/unlocked = 0
	var/open = 0
	var/brightness_on = 8		//can't remember what the maxed out value is
	/// A nearly flat cell makes the light flicker for a moment (the draw dims it while this is set).
	var/flickering = FALSE
	/// Whether the cell can feed the light a step (runs_on_cell() writes it when it crosses, not once per step).
	var/cell_powered = FALSE


CAPABILITIES(/obj/machinery/floodlight)
	configure(atom_rules(light_system = MOVABLE_LIGHT_DIRECTIONAL))
	configure(movable_motion(cone_y = 8))
	runs_on_cell(draw = nameof(use), when = nameof(on), powered_var = nameof(cell_powered), on_lost = PROC_REF(cell_power_lost), after_draw = PROC_REF(drawn))
	climb()
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use item"), then(PROC_REF(interaction_item)))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), ungated(), label("Use"), then(PROC_REF(interaction_use)))
	op("floodlight_silicon_use", remote(), priority(OP_PRIORITY_DEFAULT - 1), label("Toggle"), then(PROC_REF(floodlight_silicon_use)))
	rotatable()
	owns_one(nameof(cell), starts = /obj/item/cell, on_destroy = ON_DESTROY_CONTAINED)

/obj/machinery/floodlight/proc/appearance_battery()
	return (open && cell) ? 1 : 0

/// Whether the light burns: switched on, with a cell in it that can feed it (cell_powered, which runs_on_cell() writes when the cell crosses the threshold).
/obj/machinery/floodlight/proc/powered_on()
	return on && cell && cell_powered

/// The look (the draw sweep: from its template). The light is part of it: lit while it is switched on and its cell can feed it, dark otherwise.
/obj/machinery/floodlight/draw(datum/look/look)
	..()
	look.state("flood[open ? "o" : ""][appearance_battery() ? "b" : ""]0[on]")
	if(powered_on())
		look.glow(flickering ? brightness_on / 2 : brightness_on, flickering ? brightness_on / 4 : brightness_on / 2)
	else
		look.glow(GLOW_OFF)

/// The cell can no longer feed the light: it shuts down, and stays off when the cell is charged again.
/obj/machinery/floodlight/proc/cell_power_lost()
	if(on)
		turn_off(1)

/// After a step took its charge: a nearly empty cell rarely makes the light "flicker". Aesthetic only.
/obj/machinery/floodlight/proc/drawn(obj/item/cell/C)
	if((C.percent() < 10) && prob(5))
		set_flickering(TRUE)
		after(src, 2 SECONDS, PROC_REF(flicker_restore))

/obj/machinery/floodlight/proc/flicker_restore()
	set_flickering(FALSE)


// Returns 0 on failure and 1 on success
/obj/machinery/floodlight/proc/turn_on(loud = 0)
	if(!cell_can_feed(src))
		return 0

	set_on(1)
	if(loud)
		visible_message("\The [src] turns on.")
	return 1

/obj/machinery/floodlight/proc/turn_off(loud = 0)
	set_on(0)
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

		rel_take(src, nameof(cell))
		set_on(0)
		to_chat(user, "You remove the power cell")
		return TRUE

	if(on)
		turn_off(1)
	else
		if(!turn_on(1))
			to_chat(user, "You try to turn on \the [src] but it does not work.")

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
	return TRUE

/obj/machinery/floodlight/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	if(open)
		return OP_OK
	set_unlocked(!unlocked)
	to_chat(user, "You [unlocked ? "unscrew" : "screw"] the battery panel [unlocked ? "" : "in place"].")
	return OP_OK

/obj/machinery/floodlight/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!unlocked)
		return OP_OK
	set_open(!open)
	if(!open)
		overlays = null
	to_chat(user, "You [open ? "remove" : "crowbar"] the battery panel[open ? "" : " in place"].")
	return OP_OK

/obj/machinery/floodlight/starts_on
	icon_state = "flood01"

CAPABILITIES(/obj/machinery/floodlight/starts_on)
	setup(PROC_REF(turn_on))
