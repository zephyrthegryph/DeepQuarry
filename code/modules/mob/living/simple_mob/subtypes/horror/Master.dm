/mob/living/simple_mob/horror/Master
	reaction_sound = SFX_H_SOUNDS_HOLLA
	name = "Dr. Helix"
	desc = "A massive pile of grotesque flesh and bulging tumor like growths. Every inch of its skin is undulating in every direction possible, bringing a literal definition to 'Skin Crawling.' Stuck in the middle of this monstrosity is a large AI core with a bloodied, emaciated man sewn into its circuitry."

	icon_state = "Helix"
	icon_living = "Helix"
	icon_dead = "m_dead"
	icon_rest = "Helix"
	faction = "horror"
	icon = 'icons/mob/horror_show/master.dmi'
	vis_height = 64
	icon_gib = "generic_gib"
	anchored = TRUE

	attack_sound = SFX_H_SOUNDS_SHITTY_TIM

	endurance = 400

	melee_damage_lower = 5
	melee_damage_upper = 8
	grab_resist = 100

	response_help = "pets the"
	response_disarm = "bops the"
	response_harm = "hits the"
	attacktext = list("smushed")
	friendly = list("nuzzles", "boops", "bumps against", "leans on")



/mob/living/simple_mob/horror/Master/on_death(gibbed)
	play_sfx(src, SFX_H_SOUNDS_IMBECILES)
	..()

/mob/living/simple_mob/horror/Master/bullet_act()
	play_sfx(src, SFX_H_SOUNDS_HOLLA)
	..()


// === merged from Master_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob/horror/Master/aerostat

	say_list_type = /datum/say_list/cyber_horror/master

/datum/say_list/cyber_horror/master
	threaten_sound = 'sound/mob/robots/mastersee.ogg'
