/mob/living/simple_mob/vore/wolfgirl
	name = "wolfgirl"
	desc = "AwooOOOOoooo!"
	tt_desc = "Homo lupus"

	icon_state = "wolfgirl"
	icon_living = "wolfgirl"
	icon_dead = "wolfgirl-dead"
	icon = 'icons/mob/vore.dmi'

	faction = FACTION_WOLFGIRL
	maxHealth = 30
	health = 30

	response_help = "pats"
	response_disarm = "gently pushes aside"
	response_harm = "hits"

	harm_intent_damage = 8
	melee_damage_lower = 7
	melee_damage_upper = 7
	attacktext = list("slashed")

	say_list_type = /datum/say_list/wolfgirl
	can_be_drop_prey = FALSE
	species_sounds = "Canine"
	pain_emote_1p = list("yelp", "whine", "bark", "growl")
	pain_emote_3p = list("yelps", "whines", "barks", "growls")
// Activate Noms!
/mob/living/simple_mob/vore/wolfgirl
	vore_active = 1
	vore_pounce_chance = 40
	vore_icons = SA_ICON_LIVING


/datum/say_list/wolfgirl
	speak = list("AwoooOOOOoooo!","Awoo~","I'll protect the forest! ... Where's the forest again?","All I need is my sword!","Awoo?","Anyone else smell that?")
	emote_hear = list("awoooos!","hmms to herself","plays with her sword")
	emote_see = list("narrows her eyes","sniffs the air")
	say_maybe_target = list("An enemy!?","What was that?","Is that...?","Hmm?")
	say_got_target = list("You won't get away!","I've had it!","I'll vanquish you!","AWOOOOO!")
