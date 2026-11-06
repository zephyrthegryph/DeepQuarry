/obj/item/entrepreneur/dentist_probe
	name = "dental probe"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "probe"
	desc = "A short stainless steel rod that ends with a narrow pointy bit for poking."
	w_class = ITEMSIZE_TINY

/obj/item/entrepreneur/dentist_probe/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(stance == I_HELP)	//A tad messy, but this should stop people from smacking their patients in surgery
		to_chat(user, span_notice("You use the probe to poke about inside of [M]'s mouth."))
		to_chat(M, span_notice("[user] examines the inside of your mouth with a sharp probe, it hurts a little being prodded."))
		return ITEM_INTERACT_SUCCESS
	..()
