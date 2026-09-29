/mob/living/simple_mob/horror/Eddy
	reaction_sound = SFX_H_SOUNDS_HOLLA
	name = "???"
	desc = "A dark green, sluglike creature, covered in glowing green ooze, and carrying what look to be eggs on its back."

	icon_state = "Eddy"
	icon_living = "Eddy"
	icon_dead = "e_head"
	icon_rest = "Eddy"
	faction = "horror"
	icon = 'icons/mob/horror_show/GHPS.dmi'
	icon_gib = "generic_gib"

	attack_sound = SFX_H_SOUNDS_NEGATIVE

	endurance = 175

	melee_damage_lower = 25
	melee_damage_upper = 35
	grab_resist = 100

	response_help = "pets the"
	response_disarm = "bops the"
	response_harm = "hits the"
	attacktext = list("smashed")
	friendly = list("nuzzles", "boops", "bumps against", "leans on")


	say_list_type = /datum/say_list/Eddy

/mob/living/simple_mob/horror/Eddy/on_death(gibbed)
	play_sfx(src, SFX_H_SOUNDS_HEADCRAB)
	..()

DAMAGE_REACTION(/mob/living/simple_mob/horror/Eddy, DAMAGE_PROJECTILE, PROC_REF(play_reaction_sound))

/datum/say_list/Eddy
	speak = list("Uuurrgh?","Aauuugghh...", "AAARRRGH!")
	emote_hear = list("shrieks horrifically", "groans in pain", "cries", "whines")
	emote_see = list("blinks its many eyes", "shakes violently in place", "stares aggressively")
	say_maybe_target = list("Uuurrgghhh?")
	say_got_target = list("AAAHHHHH!")
