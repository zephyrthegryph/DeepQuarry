/mob/living/simple_mob/horror/Sally
	reaction_sound = 'sound/h_sounds/holla.ogg'
	name = "???"
	desc = "A mass of tentacles hold up a large head, graced with one of the grandest smiles in the galaxy. It's a shame about the constant oil leaking from its eyes."

	icon_state = "Sally"
	icon_living = "Sally"
	icon_dead = "ws_head"
	icon_rest = "Sally"
	faction = "horror"
	icon = 'icons/mob/horror_show/widehorror.dmi'
	icon_gib = "generic_gib"

	attack_sound = 'sound/h_sounds/sampler.ogg'

	endurance = 200

	melee_damage_lower = 30
	melee_damage_upper = 40
	grab_resist = 100

	response_help = "pets the"
	response_disarm = "bops the"
	response_harm = "hits the"
	attacktext = list("smashed")
	friendly = list("nuzzles", "boops", "headbumps against", "leans on")


	say_list_type = /datum/say_list/Sally

/mob/living/simple_mob/horror/Sally/on_death(gibbed)
	play_sfx(src, SFX_H_SOUNDS_LYNX)
	..()

/mob/living/simple_mob/horror/Sally/bullet_act()
	play_sfx(src, SFX_H_SOUNDS_HOLLA)
	..()

/datum/say_list/Sally
	speak = list("Yeeeeee?","Haaah! Gashuuuuuh!", "Gahgahgahgah...")
	emote_hear = list("shrieks", "groans in pain", "breathes heavily", "gnashes its teeth")
	emote_see = list("wiggles its head", "shakes violently", "stares aggressively")
	say_maybe_target = list("Uuurrgghhh?")
	say_got_target = list("AAAHHHHH!")
