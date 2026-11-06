/mob/living/simple_mob/humanoid/cultist/magus
	name = "Blood Magus"
	desc = "A leader of the bloody cult and master of the forbidden arts, wielding powers beyond that of mortal men."
	icon_state = "magus"
	icon_living = "magus"


	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_BLADESLICE

	projectilesound = SFX_WEAPONS_SPIDERLUNGE
	var/obj/item/shield_projector/shields = null

/mob/living/simple_mob/humanoid/cultist/magus

/mob/living/simple_mob/humanoid/cultist/magus/on_death(gibbed)
	new /obj/effect/decal/cleanable/blood/gibs (src.loc)
	..()
	ghostize()

CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/magus)
	configure(atom_rules(armor_spec = "melee=60;bullet=50;laser=50;energy=80;bomb=30;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/magus)))
	configure(mob_rules(faction = "cult"))
	configure(living_rules(delete_on_death = TRUE))
	configure(mob_kind(attack_cooldown = 5, death_message = "let's out a dark laugh as it collapses into a puddle of blood."))
	immune_to_incapacitation()
	owns_one(nameof(shields), starts = /obj/item/shield_projector/rectangle/automatic/magus)

/mob/living/simple_mob/humanoid/cultist/magus
	movement_cooldown = 1
	projectiletype = /obj/item/projectile/energy/inversion
	endurance = 150 //Old 100
	melee_damage_lower = 15
	melee_damage_upper = 15
