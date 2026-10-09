MATERIAL_MIX(/obj/item/suit_cooling_unit, list(MAT_STEEL = 15000, MAT_GLASS = 3500))
/obj/item/suit_cooling_unit
	name = "portable suit cooling unit"
	desc = "A portable heat sink and liquid cooled radiator that can be hooked up to a space suit's existing temperature controls to provide industrial levels of cooling."
	w_class = ITEMSIZE_LARGE
	icon = 'icons/obj/suit_cooler.dmi'
	icon_state = "suitcooler0"
	item_state = "coolingpack"
	slot_flags = SLOT_BACK

	//copied from tank.dm
	force = 5.0
	throwforce = 10.0
	throw_speed = 1
	throw_range = 4
	actions_types = list(/datum/action/item_action/toggle_heatsink)


	var/cover_open = 0		//is the cover open?
	var/obj/item/cell/cell = /obj/item/cell/high
	var/max_cooling = 15				// in degrees per second - probably don't need to mess with heat capacity here
	var/charge_consumption = 3			// charge per second at max_cooling
	var/thermostat = T20C
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	//TODO: make it heat up the surroundings when not in space

CAPABILITIES(/obj/item/suit_cooling_unit)
	owns_one(nameof(cell), /obj/item/cell, starts = nameof(cell))
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	op("item", item(/obj/item/cell), label("Insert cell"), then(PROC_REF(interaction_item)))
	every(2 SECONDS, then(PROC_REF(suit_cooling_unit_step)), when = nameof(on))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))

/obj/item/suit_cooling_unit/ui_action_click(mob/user, actiontype)
	toggle(user)


/// Is it turned on?
/obj/item/suit_cooling_unit/var/on = 0
TRACKED(/obj/item/suit_cooling_unit, on)
TRACKED(/obj/item/suit_cooling_unit, cover_open)

/obj/item/suit_cooling_unit/proc/suit_cooling_unit_step(datum/act/timer/A)
	if (!cell)
		turn_off()
		return

	if (!ismob(loc))
		return

	if (!attached_to_suit(loc))		//make sure they have a suit and we are attached to it
		return

	var/mob/living/carbon/human/H = loc

	var/turf/T = get_turf(src)
	var/datum/gas_mixture/environment = T.return_air()
	var/efficiency = 1 - H.get_pressure_weakness(environment.return_pressure())	// You need to have a good seal for effective cooling
	var/temp_adj = 0										// How much the unit cools you. Adjusted later on.
	var/env_temp = get_environment_temperature()			// This won't save you from a fire
	var/thermal_protection = H.get_heat_protection(env_temp)	// ... unless you've got a good suit.

	if(thermal_protection < 0.99)		//For some reason, < 1 returns false if the value is 1.
		temp_adj = min(H.body_temperature() - max(thermostat, env_temp), max_cooling)
	else
		temp_adj = min(H.body_temperature() - thermostat, max_cooling)

	if (temp_adj < 0.5)	//only cools, doesn't heat, also we don't need extreme precision
		return

	var/charge_usage = (temp_adj/max_cooling)*charge_consumption

	H.adjust_bodytemperature(-(temp_adj*efficiency))

	cell.use(charge_usage)

	if(cell.charge <= 0)
		turn_off(1)

/obj/item/suit_cooling_unit/proc/get_environment_temperature()
	if (ishuman(loc))
		var/mob/living/carbon/human/H = loc
		if(istype(H.loc, /obj/mecha))
			var/obj/mecha/M = H.loc
			return M.get_interior_temperature()
		else if(istype(H.loc, /obj/machinery/atmospherics/unary/cryo_cell))
			var/obj/machinery/atmospherics/unary/cryo_cell/cc = H.loc
			return cc.air_contents.return_temperature()

	var/turf/T = get_turf(src)
	if(istype(T, /turf/space))
		return 0	//space has no temperature, this just makes sure the cooling unit works in space

	var/datum/gas_mixture/environment = T.return_air()
	if (!environment)
		return 0

	return environment.return_temperature()

/obj/item/suit_cooling_unit/proc/attached_to_suit(mob/M)
	if (!ishuman(M))
		return 0

	var/mob/living/carbon/human/H = M

	if (!H.get_equipped_item(SLOT_ID_SUIT) || (H.get_equipped_item(SLOT_ID_SUIT_STORAGE) != src && H.get_equipped_item(SLOT_ID_BACK) != src))
		return 0

	return 1

/obj/item/suit_cooling_unit/proc/turn_on()
	if(!cell)
		return
	if(cell.charge <= 0)
		return

	set_on(1)

/obj/item/suit_cooling_unit/proc/turn_off(failed)
	if(failed) visible_message("\The [src] clicks and whines as it powers down.")
	set_on(0)

/obj/item/suit_cooling_unit/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(cover_open && cell)
		if(ishuman(user))
			user.put_in_hands(cell)
		else
			cell.forceMove(get_turf(loc))

		cell.add_fingerprint(user)

		to_chat(user, "You remove \the [src.cell].")
		rel_take(src, nameof(cell))
		return

	toggle(user)

/obj/item/suit_cooling_unit/proc/toggle(mob/user)
	if(on)
		turn_off()
	else
		turn_on()
	to_chat(user, span_notice("You switch \the [src] [on ? "on" : "off"]."))

/obj/item/suit_cooling_unit/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(cover_open)
		if(cell)
			to_chat(user, "There is a [cell] already installed here.")
		else
			if(!move_into(src, nameof(src.cell), W, user))
				return TRUE
			to_chat(user, "You insert the [cell].")
	return TRUE

/obj/item/suit_cooling_unit/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	set_cover_open(!cover_open)
	to_chat(user, "You [cover_open ? "unscrew" : "screw"] the panel [cover_open ? "open" : "into place"].")
	playsound(src, tool.usesound, 50, 1)
	return OP_OK

/obj/item/suit_cooling_unit/draw(datum/look/look)
	..()
	if(cover_open)
		if(cell)
			look.state("suitcooler1")
		else
			look.state("suitcooler2")
		return

	look.state("suitcooler0")

	if(!cell || !on)
		return

	switch(round(cell.percent()))
		if(86 to INFINITY)
			look.overlay("battery-0")
		if(69 to 85)
			look.overlay("battery-1")
		if(52 to 68)
			look.overlay("battery-2")
		if(35 to 51)
			look.overlay("battery-3")
		if(18 to 34)
			look.overlay("battery-4")
		if(-INFINITY to 17)
			look.overlay("battery-5")

/obj/item/suit_cooling_unit/examine(mob/user)
	. = ..()

	if(Adjacent(user))

		if (on)
			if (attached_to_suit(src.loc))
				. += "It's switched on and running."
			else
				. += "It's switched on, but not attached to anything."
		else
			. += "It is switched off."

		if (cover_open)
			if(cell)
				. += "The panel is open, exposing the [cell]."
			else
				. += "The panel is open."

		if (cell)
			. += "The charge meter reads [round(cell.percent())]%."
		else
			. += "It doesn't have a power cell installed."

/obj/item/suit_cooling_unit/emergency
	icon_state = "esuitcooler"
	cell = /obj/item/cell
	w_class = ITEMSIZE_NORMAL

/// The look (the draw sweep: from APPEARANCE_NONE).
/obj/item/suit_cooling_unit/emergency/draw(datum/look/look)
	..()
	// APPEARANCE_NONE: the mapped sprite, without the parent's declared states and layers
	look.state(null)
	look.hide("battery-0")
	look.hide("battery-1")
	look.hide("battery-2")
	look.hide("battery-3")
	look.hide("battery-4")
	look.hide("battery-5")

/obj/item/suit_cooling_unit/emergency/get_cell()
	if(on)
		return null // Don't let recharging happen while we're on
	return cell

/obj/item/suit_cooling_unit/emergency/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_warning("This cooler's cell is permanently installed!"))
	return OP_OK
