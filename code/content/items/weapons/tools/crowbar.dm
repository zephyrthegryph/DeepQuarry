/*
 * Crowbar
 */
/obj/item/tool/crowbar
	name = "crowbar"
	desc = "Used to remove floors and to pry open doors."
	icon = 'icons/obj/tools.dmi'
	icon_state = "crowbar"
	item_state = "crowbar"
	w_class = ITEMSIZE_SMALL
	material_total = 50
	tool_qualities = list(TOOL_CROWBAR)

CAPABILITIES(/obj/item/tool/crowbar)
	configure(item_tooling(pry = 1, speed = 1))
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 7))
	configure(item_combat(force = 6, attack_verbs = list("attacked", "bashed", "battered", "bludgeoned", "whacked")))
	configure(item_sounds(use = SFX_ITEMS_CROWBAR, drop = SFX_ITEMS_DROP_CROWBAR, pickup = SFX_ITEMS_PICKUP_CROWBAR))

/obj/item/tool/crowbar/red
	icon = 'icons/obj/tools.dmi'
	icon_state = "red_crowbar"
	item_state = "crowbar_red"

CAPABILITIES(/obj/item/tool/crowbar/red)
	configure(item_combat(force = 10))

/obj/item/tool/crowbar/old
	icon = 'icons/obj/tools.dmi'
	icon_state = "old_crowbar"
	item_state = "crowbar"

/datum/category_item/catalogue/anomalous/precursor_a/alien_crowbar
	name = "Precursor Alpha Object - Hard Light Pry Tool"
	desc = "An object which bears striking resemblence to the common crowbar. \
	It appears to also serve a similar purpose, being used for prying. Unlike \
	a crowbar, however, this object is made of some form of 'hard light'.\
	<br><br>\
	There is a visible switch on the base of the tool, which controls the \
	hard light side of the tool. When the switch is used, the shape of \
	the tool changes, with the hard light moving and making a prying motion. \
	This allows the user to pry something with no physical effort beyond keeping \
	the tool aligned while in use."
	value = CATALOGUER_REWARD_EASY

/obj/item/tool/crowbar/alien
	name = "alien crowbar"
	desc = "A hard-light crowbar. It appears to pry by itself, without any effort required."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_crowbar)
	icon = 'icons/obj/abductor.dmi'
	icon_state = "crowbar"

CAPABILITIES(/obj/item/tool/crowbar/alien)
	configure(item_tooling(speed = 0.1))
	configure(item_sounds(use = SFX_WEAPONS_SONIC_JACKHAMMER))

/obj/item/tool/crowbar/hybrid
	name = "strange crowbar"
	desc = "A crowbar whose head seems to phase in and out of view."
	catalogue_data = list(/datum/category_item/catalogue/anomalous/precursor_a/alien_crowbar)
	icon_state = "hybcrowbar"

CAPABILITIES(/obj/item/tool/crowbar/hybrid)
	configure(item_tooling(speed = 0.4))
	configure(item_combat(reach = 2))
	configure(item_sounds(use = SFX_WEAPONS_SONIC_JACKHAMMER))

/obj/item/tool/crowbar/power
	name = "power pryer"
	desc = "You shouldn't see this."

CAPABILITIES(/obj/item/tool/crowbar/power)
	configure(item_tooling(speed = 0.25))
	configure(item_combat(force = 15))
	configure(item_sounds(use = SFX_ITEMS_JAWS_PRY))

/*
 * Prybar
 */

/obj/item/tool/prybar
	name = "pry bar"
	desc = "A steel bar with a wedge, designed specifically for opening unpowered doors in an emergency. It comes in a variety of configurations - collect them all!"
	icon = 'icons/obj/tools_vr.dmi'
	icon_state = "prybar"
	item_state = "crowbar"
	w_class = ITEMSIZE_SMALL
	material_total = 30
	var/random_color = TRUE

/obj/item/tool/prybar/red
	icon_state = "prybar_red"
	item_state = "crowbar_red"
	random_color = FALSE

CAPABILITIES(/obj/item/tool/prybar)
	configure(item_tooling(pry = 1, speed = 1))
	configure(item_worn(slots = SLOT_BELT))
	configure(item_thrown(force = 5))
	configure(item_combat(force = 4, attack_verbs = list("whapped", "smacked", "swatted", "thwacked", "hit")))
	configure(item_sounds(use = SFX_ITEMS_CROWBAR))
	rolls(nameof(icon_state), pick_one(list("prybar", "prybar_green", "prybar_aubergine", "prybar_blue")), when = nameof(random_color))

