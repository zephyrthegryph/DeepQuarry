///////Dentist tools, basically just fluff for RP

/obj/item/entrepreneur/dentist_mirror
	name = "dental mirror"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "mirror"
	desc = "A small mirror at the end of a short, stainless steel rod."
	w_class = ITEMSIZE_TINY

/obj/item/entrepreneur/dentist_mirror/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(stance == I_HELP)	//A tad messy, but this should stop people from smacking their patients in surgery
		to_chat(user, span_notice("You use the mirror to get a good look inside of [M]'s mouth."))
		to_chat(M, span_notice("[user] uses a small mirror to look inside of your mouth."))
		return ITEM_INTERACT_SUCCESS
	..()
