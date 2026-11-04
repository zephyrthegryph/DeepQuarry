/mob/living/simple_mob/humanoid/cultist/initiate
	name = "Blood Intiate"
	desc = "A Novice Amongst his betters, he still seems determined to slice you to bits."
	icon_state = "initiate"
	icon_living = "initiate"
	endurance = 150


	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	melee_damage_lower = 15	//Ritual Knife
	melee_damage_upper = 15
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_RAPIDSLICE
	movement_cooldown = 4

/mob/living/simple_mob/humanoid/cultist/initiate

/mob/living/simple_mob/humanoid/cultist/initiate/on_death(gibbed)
	new /obj/effect/decal/remains/human (src.loc)
	..()
	ghostize()

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/initiate)
	configure(atom_rules(armor_spec = "melee=50;bullet=30;laser=50;energy=80;bomb=25;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/initiate)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(delete_on_death = TRUE))
	configure(mob_kind(death_message = "lets out a horrified scream as his body crumbles away."))
	immune_to_incapacitation()
