/mob/living/simple_mob/humanoid/cultist/lizard
	name = "cultist"
	desc = "With a knife in each hand, this lizard looks ready to disect you."
	icon_state = "cultliz"
	icon_living = "cultliz"
	endurance = 200


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

/mob/living/simple_mob/humanoid/cultist/lizard

/mob/living/simple_mob/humanoid/cultist/lizard/on_death(gibbed)
	new /obj/effect/decal/remains/unathi (src.loc)
	..()
	ghostize()

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/lizard)
	configure(atom_rules(armor_spec = "melee=70;bullet=60;laser=30;energy=80;bomb=35;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/lizard)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(delete_on_death = TRUE))
	configure(mob_kind(attack_cooldown = 7.5, death_message = "hisses as he collapses into a pile of bones."))
	immune_to_incapacitation()
