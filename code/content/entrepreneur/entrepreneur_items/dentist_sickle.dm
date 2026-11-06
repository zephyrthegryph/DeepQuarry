/obj/item/entrepreneur/dentist_sickle
	name = "dental sickle"
	icon = 'icons/obj/entrepreneur.dmi'
	icon_state = "sickle"
	desc = "A narrow, sharp hook at the end of a short, stainless steel rod."
	w_class = ITEMSIZE_TINY

/obj/item/entrepreneur/dentist_sickle/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(stance == I_HELP)	//A tad messy, but this should stop people from smacking their patients in surgery
		to_chat(user, span_notice("You loosen some stuck debris from [M]'s mouth with the hook."))
		to_chat(M, span_notice("[user] uses a hook to scrape out something stuck in your mouth, it's pretty uncomfortable."))
		return ITEM_INTERACT_SUCCESS
	..()
