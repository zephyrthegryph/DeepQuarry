/mob/living/simple_mob/animal/space/tree
	name = "pine tree"
	desc = "A pissed off tree-like alien. It seems annoyed with the festivities..."
	tt_desc = "X Festivus tyrannus"
	icon = 'icons/obj/flora/pinetrees.dmi'
	icon_state = "pine_1"
	icon_living = "pine_1"
	icon_dead = "pine_1"
	icon_gib = "pine_1"

	mob_class = MOB_CLASS_PLANT

	faction = FACTION_PLANTS
	endurance = 250
	poison_resist = 1.0

	response_help = "brushes"
	response_disarm = "pushes"
	response_harm = "hits"

	harm_intent_damage = 5
	melee_damage_lower = 8
	melee_damage_upper = 12
	attacktext = list("bitten")
	attack_sound = SFX_WEAPONS_BITE

	organ_names = /datum/decl/mob_organ_names/tree

	meat_type = /obj/item/reagent_containers/food/snacks/xenomeat
	meat_amount = 2

	pixel_x = -16

	can_be_drop_prey = FALSE
	can_pain_emote = FALSE // Can't feel pain and shouldn't take damage anyways, but, sanity

/mob/living/simple_mob/animal/space/tree/apply_melee_effects(atom/A)
	if(isliving(A))
		var/mob/living/L = A
		if(prob(15))
			L.status_at_least(STAT_WEAKENED, 3)
			act_message(src, L, null, MSG_OTHERS(span_danger("%U% knocks down %T%!")))

/mob/living/simple_mob/animal/space/tree
	delete_on_death = TRUE
	death_message = "is hacked into pieces!"

/mob/living/simple_mob/animal/space/tree/on_death(gibbed)
	..()
	play_sfx(src, SFX_EFFECTS_WOODCUTTING)
	new /obj/item/stack/material/wood(loc)

/datum/decl/mob_organ_names/tree
TYPE_TABLE(/datum/decl/mob_organ_names/tree, mob_organ_hit_zones, list("trunk", "branches", "twigs"))
