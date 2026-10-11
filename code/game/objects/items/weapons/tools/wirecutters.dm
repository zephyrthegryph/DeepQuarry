/*
 * Wirecutters
 */
/obj/item/tool/wirecutters
	name = "wirecutters"
	desc = "This cuts wires."
	icon = 'icons/obj/tools.dmi'
	icon_state = "cutters"
	item_state = "cutters"
	center_of_mass_x = 18
	center_of_mass_y = 10
	slot_flags = SLOT_BELT
	force = 6
	throw_speed = 2
	throw_range = 9
	w_class = ITEMSIZE_SMALL
	material_total = 80
	attack_verb = list("pinched", "nipped")
	sharp = TRUE
	edge = TRUE
	injury_kind = INJURY_CUT
	toolspeed = 1
	tool_qualities = list(TOOL_WIRECUTTER)
	var/random_color = TRUE

CAPABILITIES(/obj/item/tool/wirecutters)
	rolls(nameof(icon_state), PROC_REF(roll_colour), when = nameof(random_color))
	rolls(nameof(item_state), PROC_REF(item_state_for_colour), when = nameof(random_color), from = list(nameof(icon_state)))
	rolls(nameof(pixel_y), PROC_REF(roll_drop_y))
	configure(item_sounds(hit = SFX_ITEMS_WIRECUTTER, use = SFX_ITEMS_WIRECUTTER, drop = SFX_ITEMS_DROP_WIRECUTTER, pickup = SFX_ITEMS_PICKUP_WIRECUTTER))

/// A random handle colour (rolls()): icon_state -> the matching in-hand item_state.
/obj/item/tool/wirecutters/proc/colour_table()
	var/static/list/colours = list(
		"cutters" = "cutters",
		"cutters-b" = "cutters_blue",
		"cutters-y" = "cutters_yellow")
	return colours

/// Rolled before init (rolls()): one of the handle colours.
/obj/item/tool/wirecutters/proc/roll_colour(datum/roller/R)
	return R.choose(colour_table())

/// Rolled before init (rolls()), after the colour: the in-hand sprite of the colour it rolled.
/obj/item/tool/wirecutters/proc/item_state_for_colour(datum/roller/R)
	return colour_table()[icon_state] || item_state


/obj/item/tool/wirecutters/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(!iscarbon(M))
		return ..()
	var/mob/living/carbon/C = M
	if(istype(C) && stance == I_HELP && (C.get_equipped_item(SLOT_ID_HANDCUFFED)) && (istype(C.get_equipped_item(SLOT_ID_HANDCUFFED), /obj/item/handcuffs/cable)))
		act_message(user, src, MSG_SELF("You cut \the [C]'s restraints with %T%!"), \
			MSG_OTHERS("%U% cuts \the [C]'s restraints with %T%!"), \
			MSG_BLIND("You hear cable being cut."))
		var/obj/item/cut = C.get_equipped_item(SLOT_ID_HANDCUFFED)
		consume(cut, C)
		return ITEM_INTERACT_SUCCESS
	else
		..()

/datum/category_item/catalogue/anomalous/precursor_a/alien_wirecutters
	name = "Precursor Alpha Object - Wire Separator"
	desc = "An object appearing to have a tool shape. It has two handles, and two \
	sides which are attached to each other in the center. At the end on each side \
	is a sharp cutting edge, made from a separate material than the rest of the \
	tool.\
	<br><br>\
	This tool appears to serve the same purpose as conventional wirecutters, due \
	to how similar the shapes are. If so, this implies that the creators of this \
	object also may utilize flexible cylindrical strands of metal to transmit \
	energy and signals, just as humans do."
	value = CATALOGUER_REWARD_EASY

/obj/item/tool/wirecutters/alien
	name = "alien wirecutters"
	desc = "Extremely sharp wirecutters, made out of a silvery-green metal."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_wirecutters)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "cutters"
	toolspeed = 0.1
	random_color = FALSE

/obj/item/tool/wirecutters/hybrid
	name = "strange wirecutters"
	desc = "This cuts wires. With " + span_purple("Science!")
	icon_state = "hybcutters"
	random_color = FALSE
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("pinched", "nipped", "warped", "blasted")
	toolspeed = 0.4
	reach = 2

CAPABILITIES(/obj/item/tool/wirecutters/hybrid)
	configure(item_sounds(use = SFX_EFFECTS_STEALTHOFF))

/obj/item/tool/wirecutters/power
	name = "power cutters"
	desc = "You shouldn't see this."
	force = 15
	toolspeed = 0.25

CAPABILITIES(/obj/item/tool/wirecutters/power)
	configure(item_sounds(use = SFX_ITEMS_JAWS_CUT))
