/obj/structure/blob/shield
	name = "thick blob"
	base_name = "thick"
	icon = 'icons/mob/blob.dmi'
	icon_state = "blob_shield"
	desc = "A solid wall of slightly twitching tendrils."
	max_integrity = 100
	point_return = 4
	can_atmos_pass = ATMOS_PASS_NO

/obj/structure/blob/shield/core
	point_return = 0

/obj/structure/blob/shield/look_parts(datum/look/look)
	..()
	var/desc_shown
	if(get_integrity_damage() >= max_integrity - 75)
		look.state("blob_shield_damaged")
		desc_shown = "A wall of twitching tendrils."
	else
		look.state(initial(icon_state))
		desc_shown = initial(desc)
	look.identity(name = look_title ? "[base_name] [look_title]" : "inert [base_name] blob", desc = desc_shown)
