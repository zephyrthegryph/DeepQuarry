/mob/living/simple_mob/slime/xenobio/gold/get_mechanics_info(list/additional_information)
	return ..(list("The slimebaton and taser charge this slime instead of stunning it, though they still discipline it.") + additional_information)

/mob/living/simple_mob/slime/xenobio/gold
	desc ="This slime absorbs energy, and cannot be stunned by normal means."
	color = "#EEAA00"
	shiny = TRUE
	slime_color = "gold"
	coretype = /obj/item/slime_extract/gold

	slime_mutation = list(
			/mob/living/simple_mob/slime/xenobio/metal,
			/mob/living/simple_mob/slime/xenobio/gold,
			/mob/living/simple_mob/slime/xenobio/sapphire,
			/mob/living/simple_mob/slime/xenobio/sapphire
		)

/mob/living/simple_mob/slime/xenobio/gold/slimebatoned(mob/living/user, amount)
	adjust_discipline(round(amount/2))
	power_charge = between(0, power_charge + amount, 10)

/mob/living/simple_mob/slime/xenobio/gold/get_description_interaction(mob/viewer) // So it doesn't say to use a baton on them.
	return list()
