/mob/living/simple_mob/horror
	tt_desc = "Homo Horrificus"
	faction = "horror"
	icon = 'icons/mob/horror_show/GHPS.dmi'
	icon_gib = "generic_gib"


CAPABILITIES(/mob/living/simple_mob/horror)
	configure(voice_config(can_pain_emote = FALSE))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("can_be_drop_prey" = FALSE))

/mob/living/simple_mob/horror
	min_oxy = 0
	max_oxy = 0
	min_tox = 0
	max_tox = 0
	min_co2 = 0
	max_co2 = 0
	min_n2 = 0
	max_n2 = 0
	minbodytemp = 0
	maxbodytemp = 700

