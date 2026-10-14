/mob/living/simple_mob/animal/passive/lizard
	name = "lizard"
	desc = "A cute, tiny lizard."
	tt_desc = "E Anolis cuvieri"

	icon_state = "lizard_green"
	icon_living = "lizard_green"
	icon_dead = "lizard_green_dead"

	endurance = 5
	mob_size = MOB_MINISCULE

	response_help  = "pets"
	response_disarm = "shoos"
	response_harm   = "stomps on"

	attacktext = list("bitten")
	melee_damage_lower = 1
	melee_damage_upper = 2

	speak_emote = list("hisses")

	say_list_type = /datum/say_list/lizard

	meat_amount = 1

	var/body_color			// Green, red, orange, yellow or cyan. Keep blank for random (including rare redblue)

CAPABILITIES(/mob/living/simple_mob/animal/passive/lizard)
	rolls(nameof(body_color), pick_one(list("redblue" = 1, "green" = 200, "red" = 200, "orange" = 200, "yellow" = 200, "cyan" = 200)), when = cond_not(nameof(body_color)))
	look_from(nameof(body_color), state = "lizard_*", item = "lizard_*", living = "lizard_*", dead = "lizard_*_dead")
	rolls(nameof(desc), PROC_REF(roll_desc), from = list(nameof(body_color)))
	trait(TRAIT_AMBIENT_PEST_MOB)

/// Its description names its colour (rolls()).
/mob/living/simple_mob/animal/passive/lizard/proc/roll_desc(datum/roller/R)
	if(body_color == "redblue")
		return "A cute, tiny, red lizard with distinctive blueish markings on its tiny limbs. Seems rare!"
	return "A cute, tiny, [body_color] lizard."

/mob/living/simple_mob/animal/passive/lizard/large
	desc = "A cute, big lizard."
	endurance = 20

	melee_damage_lower = 5
	melee_damage_upper = 15

	attack_injury_kind = INJURY_PIERCE

CAPABILITIES(/mob/living/simple_mob/animal/passive/lizard/large)
	rolls(nameof(icon_scale_x), range_of(1.2, 2, 0.1))
	rolls(nameof(icon_scale_y), PROC_REF(roll_same_scale), from = list(nameof(icon_scale_x)))

/mob/living/simple_mob/animal/passive/lizard/large/defensive
	endurance = 30
