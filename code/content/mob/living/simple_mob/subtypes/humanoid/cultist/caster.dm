/mob/living/simple_mob/humanoid/cultist/caster
	name = "Blood Mage"
	desc = "A Robed individual whose hands pulsate with unnatural power."
	icon_state = "caster"
	icon_living = "caster"
	endurance = 150


	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_RAPIDSLICE
	projectilesound = SFX_WEAPONS_SPIDERLUNGE

/mob/living/simple_mob/humanoid/cultist/caster

/mob/living/simple_mob/humanoid/cultist/caster/on_death(gibbed)
	new /obj/effect/decal/remains/human (src.loc)
	new /obj/effect/decal/cleanable/blood/gibs (src.loc)
	..()
	ghostize()

/mob/living/simple_mob/humanoid/cultist/caster
	movement_cooldown = 1
	projectiletype = /obj/item/projectile/energy/inversion
	melee_damage_lower = 15 //Old 7
	melee_damage_upper = 15

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/caster)
	configure(atom_rules(armor_spec = "melee=50;bullet=30;laser=50;energy=80;bomb=25;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/caster)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(delete_on_death = TRUE))
	configure(mob_kind(death_message = "melts into a pile of blood and bones."))
	immune_to_incapacitation()
