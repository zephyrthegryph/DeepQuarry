/obj/item/entrepreneur/dentist_scaler
	name = "dental scaler"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "scaler"
	desc = "A flat and thin scraper at the end of a short, stainless steel rod."
	w_class = ITEMSIZE_TINY

/obj/item/entrepreneur/dentist_scaler/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(stance == I_HELP)	//A tad messy, but this should stop people from smacking their patients in surgery
		to_chat(user, span_notice("You scrape debris out from [M]'s mouth."))
		to_chat(M, span_notice("[user] scrapes debris from out of your mouth."))
		return ITEM_INTERACT_SUCCESS
	..()
