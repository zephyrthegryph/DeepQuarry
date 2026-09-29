/mob/living/simple_mob/horror/Steve
	reaction_sound = SFX_H_SOUNDS_HOLLA
	name = "???"
	desc = "A formless blob of flesh with one, giant, everblinking eye. It has a large machine gun and a watercooler stuck stright into its skin."

	icon_state = "Steve"
	icon_living = "Steve"
	icon_dead = "sg_head"
	icon_rest = "Steve"
	faction = "horror"
	icon = 'icons/mob/horror_show/GHPS.dmi'
	icon_gib = "generic_gib"

	attack_sound = SFX_H_SOUNDS_MUMBLE

	endurance = 175

	melee_damage_lower = 25
	melee_damage_upper = 35
	grab_resist = 100

	projectiletype = /obj/item/projectile/bullet/pistol/medium
	projectilesound = SFX_WEAPONS_GUNSHOT_LIGHT

	needs_reload = TRUE
	base_attack_cooldown = 5 // Two attacks a second or so.
	reload_max = 20

	response_help = "pets the"
	response_disarm = "bops the"
	response_harm = "hits the"
	attacktext = list("smashed")
	friendly = list("nuzzles", "boops", "bumps against", "leans on")


	say_list_type = /datum/say_list/Steve

/mob/living/simple_mob/horror/Steve/on_death(gibbed)
	play_sfx(src, SFX_H_SOUNDS_HOLLA)
	..()

DAMAGE_REACTION(/mob/living/simple_mob/horror/Steve, DAMAGE_PROJECTILE, PROC_REF(play_reaction_sound))

/datum/say_list/Steve
	speak = list("Uuurrgh?","Aauuugghh...", "AAARRRGH!")
	emote_hear = list("shrieks horrifically", "groans in pain", "cries", "whines")
	emote_see = list("blinks aggressively at", "shakes violently in place", "stares aggressively")
	say_maybe_target = list("Uuurrgghhh?")
	say_got_target = list("AAAHHHHH!")
