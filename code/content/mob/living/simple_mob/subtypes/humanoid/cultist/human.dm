/mob/living/simple_mob/humanoid/cultist/human
	name = "cultist"
	desc = "A fanatical zealot armed with a darkly colored sword."
	icon_state = "cultist"
	icon_living = "cultist"

	status_flags = 0

	response_help = "pokes"
	response_disarm = "shoves"
	response_harm = "hits"

	harm_intent_damage = 5
	attack_injury_kind = INJURY_CUT
	attacktext = list("slashed", "stabbed")
	attack_sound = SFX_WEAPONS_BLADESLICE

/mob/living/simple_mob/humanoid/cultist/human

/mob/living/simple_mob/humanoid/cultist/human/on_death(gibbed)
	new /obj/effect/decal/remains/human (src.loc)
	..()
	ghostize()

// === merged from cultist_ch.dm during hard-fork de-suffix (verified no override-order change) ===

/*
/mob/living/simple_mob/humanoid/cultist
	endurance = 75
*/
/mob/living/simple_mob/humanoid/cultist/human
	movement_cooldown = 1
	melee_damage_lower = 15
	melee_damage_upper = 15

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/simple_mob/humanoid/cultist/human)
	configure(atom_rules(armor_spec = "melee=60;bullet=50;laser=30;energy=80;bomb=30;bio=100;rad=100", catalogue_data = list(/datum/category_item/catalogue/fauna/cultist/human)))
	configure(living_rules(delete_on_death = TRUE))
	configure(mob_kind(death_message = "let's out a maddening laugh as his body crumbles away."))
	immune_to_incapacitation()
