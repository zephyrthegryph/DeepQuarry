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
