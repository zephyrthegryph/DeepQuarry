/mob/living/simple_mob/animal/passive/fennec
	name = "fennec"
	desc = "A fox preferring arid climates, also known as a dingler, or a goob."
	tt_desc = "Vulpes Zerda"
	icon_state = "fennec"
	item_state = "fennec"

	movement_cooldown = -1

	see_in_dark = 6
	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"

	holder_type = /obj/item/holder/fennec
	mob_size = MOB_SMALL

	has_langs = list(LANGUAGE_ANIMAL)

/mob/living/simple_mob/animal/passive/fennec/faux
	name = "faux"
	desc = "Domesticated fennec. Seems to like screaming just as much though."

CAPABILITIES(/mob/living/simple_mob/animal/passive/fennec)
	look_from(nameof(icon_state), living = "*", dead = "*_dead", rest = "*_rest")
