/mob/living/simple_mob/tomato
	name = PLANT_TOMATO
	desc = "It's a horrifyingly enormous beef tomato, and it's packing extra beef!"
	tt_desc = "X Solanum abominable"
	icon_state = "tomato"
	icon_living = "tomato"
	icon_dead = "tomato_dead"


	faction = FACTION_PLANTS
	endurance = 15
	poison_resist = 1.0

	response_help  = "prods"
	response_disarm = "pushes aside"
	response_harm   = "smacks"

	organ_names = /datum/decl/mob_organ_names/tomato

	harm_intent_damage = 5
	melee_damage_upper = 15
	melee_damage_lower = 10
	attacktext = list("mauled")


	meat_amount = 4


CAPABILITIES(/mob/living/simple_mob/tomato)
	configure(butchery_config(meat_type = /obj/item/reagent_containers/food/snacks/tomatomeat))
	configure(voice_config(can_pain_emote = FALSE))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = FALSE))
	configure(mob_kind(mob_class = MOB_CLASS_PLANT))

/datum/decl/mob_organ_names/tomato
TYPE_TABLE(/datum/decl/mob_organ_names/tomato, mob_organ_hit_zones, list("flesh", "leaf", "mouth"))
