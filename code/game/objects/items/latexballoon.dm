/obj/item/latexballon
	name = "latex glove"
	desc = "A latex glove, usually used as a balloon."
	icon = 'icons/obj/items.dmi'
	icon_state = "latexballon"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_gloves.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_gloves.dmi',
			)
	item_state = "lgloves"
	force = 0
	throwforce = 0
	w_class = ITEMSIZE_SMALL
	throw_speed = 1
	throw_range = 15
	var/state
	var/datum/gas_mixture/air_contents = null

/obj/item/latexballon/proc/blow(obj/item/tank/tank)
	if (icon_state == "latexballon_bursted")
		return
	src.air_contents = tank.remove_air_volume(3)
	icon_state = "latexballon_blow"
	item_state = "latexballon"

/obj/item/latexballon/proc/burst()
	if (!air_contents)
		return
	playsound(src, 'sound/weapons/gunshot_old.ogg', 100, 1)
	icon_state = "latexballon_bursted"
	item_state = "lgloves"
	loc.assume_air(air_contents)

/obj/item/latexballon/ex_act(severity)
	burst()
	return ..()

/obj/item/latexballon/bullet_act()
	burst()


/obj/item/latexballon/attackby(obj/item/W as obj, mob/user as mob)
	if (can_puncture(W))
		burst()

