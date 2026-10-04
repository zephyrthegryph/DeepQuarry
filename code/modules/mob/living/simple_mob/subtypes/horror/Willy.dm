/mob/living/simple_mob/horror/Willy
	reaction_sound = SFX_H_SOUNDS_HOLLA
	name = "???"
	desc = "It looks like a giant mascot costume made of flesh and fabric. The two bulging eyes aren't comforting to look at either. At least it smells like a burger and fries."

	icon_state = "Willy"
	icon_living = "Willy"
	icon_dead = "w_head"
	icon_rest = "Willy"
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


	say_list_type = /datum/say_list/Willy

/mob/living/simple_mob/horror/Willy/on_death(gibbed)
	play_sfx(src, SFX_H_SOUNDS_SAMPLER)
	..()

CAPABILITIES(/mob/living/simple_mob/horror/Willy)
	on_notice(/datum/notice/hit/projectile, then(PROC_REF(play_reaction_sound)))

/datum/say_list/Willy
	speak = list("Uuurrgh?","Aauuugghh...", "AAARRRGH!")
	emote_hear = list("shrieks horrifically", "groans in pain", "cries", "whines")
	emote_see = list("headbobs", "shakes violently in place", "stares aggressively")
	say_maybe_target = list("Uuurrgghhh?")
	say_got_target = list("AAAHHHHH!")
