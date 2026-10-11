/// Rolled before init (rolls()): a dropped tool sits up to 16 px up its tile three times in four.
/obj/item/tool/proc/roll_drop_y(datum/roller/R)
	return R.chance(75) ? R.number(0, 16) : pixel_y

/*
 * Screwdriver
 */
/obj/item/tool/screwdriver
	name = "screwdriver"
	desc = "You can be totally screwwy with this."
	icon = 'icons/obj/tools.dmi'
	icon_state = "screwdriver"
	center_of_mass_x = 13
	center_of_mass_y = 7
	slot_flags = SLOT_BELT | SLOT_EARS
	force = 6
	w_class = ITEMSIZE_TINY
	throwforce = 5
	throw_speed = 3
	throw_range = 5
	material_total = 75
	attack_verb = list("stabbed")
	sharp  = TRUE
	injury_kind = INJURY_PIERCE
	toolspeed = 1
	tool_qualities = list(TOOL_SCREWDRIVER)
	var/random_color = TRUE

CAPABILITIES(/obj/item/tool/screwdriver)
	rolls(nameof(icon_state), PROC_REF(roll_colour), when = nameof(random_color))
	rolls(nameof(item_state), PROC_REF(item_state_for_colour), when = nameof(random_color), from = list(nameof(icon_state)))
	rolls(nameof(pixel_y), PROC_REF(roll_drop_y))
	configure(item_sounds(hit = SFX_WEAPONS_BLADESLICE, use = SFX_ITEMS_SCREWDRIVER, drop = SFX_ITEMS_DROP_SCREWDRIVER, pickup = SFX_ITEMS_PICKUP_SCREWDRIVER))

/// A random handle colour (rolls()): icon_state -> the matching in-hand item_state.
GLOBAL_LIST_INIT(screwdriver_colours, list(
		"screwdriver2" = "screwdriver",
		"screwdriver" = "screwdriver_blue",
		"screwdriver3" = "screwdriver_purple",
		"screwdriver4" = "screwdriver_brown",
		"screwdriver5" = "screwdriver_green",
		"screwdriver6" = "screwdriver_cyan",
		"screwdriver7" = "screwdriver_yellow"))

/// Rolled before init (rolls()): one of the handle colours.
/obj/item/tool/screwdriver/proc/roll_colour(datum/roller/R)
	return R.choose(GLOB.screwdriver_colours)

/// Rolled before init (rolls()), after the colour: the in-hand sprite of the colour it rolled.
/obj/item/tool/screwdriver/proc/item_state_for_colour(datum/roller/R)
	return GLOB.screwdriver_colours[icon_state] || item_state


/obj/item/tool/screwdriver/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(!istype(M) || stance == I_HELP)
		return ..()
	if(user.zone_sel.selecting != O_EYES && user.zone_sel.selecting != BP_HEAD)
		return ..()
	if(CLUMSY_HARM_CHANCE(user))
		M = user
	return eyestab(M,user)

/datum/category_item/catalogue/anomalous/precursor_a/alien_screwdriver
	name = "Precursor Alpha Object - Hard Light Torgue Tool"
	desc = "This appears to be a tool, with a solid handle, and a thin hard light \
	shaft, with a tip at the end. On the handle appears to be two mechanisms that \
	causes the hard light section to spin at a high speed while held down, in a \
	similar fashion as an electric drill. One makes it spin clockwise, the other \
	counter-clockwise.\
	<br><br>\
	The hard light tip is able to shift its shape to a degree when pressed into \
	a solid receptacle. This allows it to be able to function on many kinds of \
	fastener, which includes the screws."
	value = CATALOGUER_REWARD_EASY

/obj/item/tool/screwdriver/alien
	name = "alien screwdriver"
	desc = "An ultrasonic screwdriver."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_screwdriver)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "screwdriver_a"
	item_state = "screwdriver_black"
	toolspeed = 0.1
	random_color = FALSE

CAPABILITIES(/obj/item/tool/screwdriver/alien)
	configure(item_sounds(use = SFX_ITEMS_PSHOOM))

/obj/item/tool/screwdriver/hybrid
	name = "strange screwdriver"
	desc = "A strange conglomerate of a screwdriver."
	icon_state = "hybscrewdriver"
	item_state = "screwdriver_black"
	w_class = ITEMSIZE_NORMAL
	toolspeed = 0.4
	random_color = FALSE
	reach = 2

CAPABILITIES(/obj/item/tool/screwdriver/hybrid)
	configure(item_sounds(use = SFX_EFFECTS_UNCLOAK))

/obj/item/tool/screwdriver/power
	name = "power screwdriver"
	desc = "You shouldn't see this."
	force = 8
	attack_verb = list("drilled", "screwed", "jabbed", "whacked")
	toolspeed = 0.25

CAPABILITIES(/obj/item/tool/screwdriver/power)
	configure(item_sounds(hit = SFX_ITEMS_DRILL_HIT, use = SFX_ITEMS_DRILL_USE_2))
