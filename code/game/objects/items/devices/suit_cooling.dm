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

/obj/item/suit_cooling_unit/ui_action_click(mob/user, actiontype)
	toggle(user)


/// Is it turned on?
OM_FIELD(/obj/item/suit_cooling_unit, on, 0, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/suit_cooling_unit, PERIODIC_SLOW, "on")
DECLARE_DEFAULT_CHILD(/obj/item/suit_cooling_unit, "cell", null)

/obj/item/suit_cooling_unit/periodic_step()
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
		temp_adj = min(H.bodytemperature - max(thermostat, env_temp), max_cooling)
	else
		temp_adj = min(H.bodytemperature - thermostat, max_cooling)

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
	update_icon()

/obj/item/suit_cooling_unit/proc/turn_off(failed)
	if(failed) visible_message("\The [src] clicks and whines as it powers down.")
	set_on(0)
	update_icon()

DECLARE_INTERACTIONS(/obj/item/suit_cooling_unit, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_INSERT(/obj/item/cell, PROC_REF(interaction_item), "Insert cell"), \
)

/obj/item/suit_cooling_unit/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(cover_open && cell)
		if(ishuman(user))
			user.put_in_hands(cell)
		else
			cell.forceMove(get_turf(loc))

		cell.add_fingerprint(user)
		cell.update_icon()

		to_chat(user, "You remove \the [src.cell].")
		own_take(src, "cell")
		update_icon()
		return

	toggle(user)

/obj/item/suit_cooling_unit/proc/toggle(mob/user)
	if(on)
		turn_off()
	else
		turn_on()
	to_chat(user, span_notice("You switch \the [src] [on ? "on" : "off"]."))

/obj/item/suit_cooling_unit/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(cover_open)
		if(cell)
			to_chat(user, "There is a [cell] already installed here.")
		else
			user.drop_item()
			W.forceMove(src)
			own_set(src, "cell", W)
			to_chat(user, "You insert the [cell].")
	update_icon()
	return TRUE

/obj/item/suit_cooling_unit/screwdriver_act(mob/user, obj/item/tool)
	cover_open = !cover_open
	to_chat(user, "You [cover_open ? "unscrew" : "screw"] the panel [cover_open ? "open" : "into place"].")
	playsound(src, tool.usesound, 50, 1)
	update_icon()
	return ITEM_INTERACT_SUCCESS

DECLARE_APPEARANCE_PROC(/obj/item/suit_cooling_unit, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/suit_cooling_unit/appearance_overlays()
	. = list()
	if(cover_open)
		if(cell)
			icon_state = "suitcooler1"
		else
			icon_state = "suitcooler2"
		return .

	icon_state = "suitcooler0"

	if(!cell || !on)
		return .

	switch(round(cell.percent()))
		if(86 to INFINITY)
			. += "battery-0"
		if(69 to 85)
			. += "battery-1"
		if(52 to 68)
			. += "battery-2"
		if(35 to 51)
			. += "battery-3"
		if(18 to 34)
			. += "battery-4"
		if(-INFINITY to 17)
			. += "battery-5"

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

APPEARANCE_NONE(/obj/item/suit_cooling_unit/emergency)

/obj/item/suit_cooling_unit/emergency/get_cell()
	if(on)
		return null // Don't let recharging happen while we're on
	return cell

/obj/item/suit_cooling_unit/emergency/screwdriver_act(mob/user, obj/item/tool)
	to_chat(user, span_warning("This cooler's cell is permanently installed!"))
	return ITEM_INTERACT_BLOCKING
