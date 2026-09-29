/mob/living/simple_mob/horror/TinyTim
	reaction_sound = SFX_H_SOUNDS_HOLLA
	name = "???"
	desc = "A tall figure wearing ripped clothes. Its eyes are placed on the bulb of skin that's folded over the front of its face."

	icon_state = "timling"
	icon_living = "timling"
	icon_dead = "tt_head"
	icon_rest = "timling"
	faction = "horror"
	icon = 'icons/mob/horror_show/tallhorror.dmi'
	vis_height = 64
	icon_gib = "generic_gib"

	attack_sound = SFX_H_SOUNDS_YOUKNOWWHOITIS

	endurance = 200

	melee_damage_lower = 30
	melee_damage_upper = 40
	grab_resist = 100

	response_help = "pets the"
	response_disarm = "bops the"
	response_harm = "hits the"
	attacktext = list("mutilated")
	friendly = list("nuzzles", "boops", "headbumps against", "leans on")


	say_list_type = /datum/say_list/TinyTim

/mob/living/simple_mob/horror/TinyTim/on_death(gibbed)
	play_sfx(src, SFX_H_SOUNDS_SHITTY_TIM)
	..()

/mob/living/simple_mob/horror/TinyTim/bullet_act()
	play_sfx(src, SFX_H_SOUNDS_HOLLA)
	..()

/datum/say_list/TinyTim
	speak = list("Wuuuuuhhuuhhhhh?","Urk! Aaaaahaaa!", "Yuhyuhyuhyuh...")
	emote_hear = list("shrieks", "groans in pain", "flaps", "gnashes its teeth")
	emote_see = list("jiggles its teeth", "shakes violently", "stares aggressively")
	say_maybe_target = list("Uuurrgghhh?")
	say_got_target = list("AAAHHHHH!")
