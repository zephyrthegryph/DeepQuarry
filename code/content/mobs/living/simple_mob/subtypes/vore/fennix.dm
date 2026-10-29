/mob/living/simple_mob/vore/fennix
	name = "Fennix"
	desc = "A feral fennix, Warm to the touch"
	tt_desc = "Incaendium Faeles Vulpes"

	icon_state = "fennix"
	icon_living = "fennix"
	icon_dead = "fennix_dead"
	icon = 'icons/mob/vore.dmi'

	endurance = 60


	response_help = "pats"
	response_disarm = "gently pushes aside"
	response_harm = "hits"

	harm_intent_damage = 20
	melee_damage_lower = 1
	melee_damage_upper = 3
	attacktext = list("bit")


CAPABILITIES(/mob/living/simple_mob/vore/fennix)
	configure(mob_rules(faction = FACTION_FENNEC))
	configure(living_rules(say_list_type = /datum/say_list/fennix))
	configure(butchery_rules(meat_type = /obj/item/reagent_containers/food/snacks/meat/fox, meat_amount = 5))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("allow_mind_transfer" = TRUE))


/datum/say_list/fennix
	speak = list("SQUEL!","SQEL?","Skree.")
	emote_hear = list("Screeeeecheeeeessss!","Chirrup.")
	emote_see = list("earflicks","pats at the ground")
