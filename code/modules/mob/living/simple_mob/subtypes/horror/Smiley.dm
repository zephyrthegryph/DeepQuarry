/mob/living/simple_mob/horror/Smiley
	reaction_sound = 'sound/h_sounds/holla.ogg'
	name = "???"
	desc = "A giant hand, with a large, smiling head on top."

	icon_state = "Smiley"
	icon_living = "Smiley"
	icon_dead = "s_head"
	icon_rest = "Smiley"
	faction = "horror"
	icon = 'icons/mob/horror_show/GHPS.dmi'
	icon_gib = "generic_gib"

	attack_sound = 'sound/h_sounds/holla.ogg'

	endurance = 175

	melee_damage_lower = 25
	melee_damage_upper = 35
	grab_resist = 100

	response_help = "pets the"
	response_disarm = "bops the"
	response_harm = "hits the"
	attacktext = list("smashed")
	friendly = list("nuzzles", "boops", "bumps against", "leans on")


	say_list_type = /datum/say_list/Smiley

/mob/living/simple_mob/horror/Smiley/on_death(gibbed)
	play_sfx(src, SFX_H_SOUNDS_LYNX)
	..()

/mob/living/simple_mob/horror/Smiley/bullet_act()
	play_sfx(src, SFX_H_SOUNDS_HOLLA)
	..()

/datum/say_list/Smiley
	speak = list("Uuurrgh?","Aauuugghh...", "AAARRRGH!")
	emote_hear = list("shrieks horrifically", "groans in pain", "cries", "whines")
	emote_see = list("squeezes its fingers together", "shakes violently in place", "stares aggressively")
	say_maybe_target = list("Uuurrgghhh?")
	say_got_target = list("AAAHHHHH!")
