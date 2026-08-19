/**********************Mining Equipment Locker Items**************************/

/**********************Mining Equipment Voucher**********************/

/obj/item/mining_voucher
	name = "mining voucher"
	desc = "A token to redeem a piece of equipment. Use it on a mining equipment vendor."
	icon = 'icons/obj/mining.dmi'
	icon_state = "mining_voucher"
	w_class = ITEMSIZE_TINY

/**********************Mining Point Card**********************/

/obj/item/card/mining_point_card
	name = "mining payment card"
	desc = "A small card preloaded with Thalers. Swipe your ID card over it to deposit them, then discard it."
	icon_state = "data"
	var/mine_points = 500
	var/survey_points = 0

/obj/item/card/mining_point_card/attackby(obj/item/I, mob/user, params)
	if(istype(I, /obj/item/card/id))
		var/obj/item/card/id/C = I
		var/datum/money_account/account = get_account(C.associated_account_number)
		if(mine_points)
			if(account?.credit(mine_points, name, "Mining payment card", name))
				to_chat(user, span_info("You transfer [mine_points] Thalers to [C]."))
				mine_points = 0
		else
			to_chat(user, span_info("There's no excavation points left on [src]."))

		if(survey_points)
			if(account?.credit(survey_points, name, "Survey payment card", name))
				to_chat(user, span_info("You transfer [survey_points] Thalers to [C]."))
				survey_points = 0
		else
			to_chat(user, span_info("There's no survey points left on [src]."))

	..()

/obj/item/card/mining_point_card/examine(mob/user)
	. = ..()
	. += "There are [mine_points + survey_points] Thalers on the card."

/obj/item/card/mining_point_card/survey
	mine_points = 0
	survey_points = 50
