/datum/category_item/catalogue/fauna/lion
	name = "Creature - Lion"
	desc = "Some sort of lion, a descendent or otherwise of regular Earth felidae. They look almost exactly like their \
	Earth counterparts."
	value = CATALOGUER_REWARD_MEDIUM

/mob/living/simple_mob/vore/retaliate/lion
	name = "lion"
	desc = "A large feline creature."
	catalogue_data = list(/datum/category_item/catalogue/fauna/lion)

	icon_state = "lion"
	icon_living = "lion"
	icon_dead = "lion-dead"
	icon_rest = "lion_rest"
	icon = 'icons/mob/vore64x32.dmi'

	endurance = 200
	see_in_dark = 8

	melee_damage_lower = 10
	melee_damage_upper = 20
	grab_resist = 100

	meat_type = /obj/item/reagent_containers/food/snacks/meat
	meat_amount = 5

	response_help = "pets"
	response_disarm = "bops"
	response_harm = "hits"
	attacktext = list("chomps")
	friendly = list("nuzzles", "slobberlicks", "noses softly at", "noseboops", "headbumps against", "leans on", "nibbles affectionately on")

	old_x = -16
	old_y = 0
	default_pixel_x = -16
	pixel_x = -16
	pixel_y = 0

	minbodytemp = 200

	max_buckled_mobs = 1 //Yeehaw
	can_buckle = TRUE
	buckle_movable = TRUE
	buckle_lying = FALSE

	vore_active = TRUE
	vore_pounce_chance = 80 //hongry
	vore_icons = SA_ICON_LIVING | SA_ICON_REST

	var/has_mane = TRUE
	var/mane_living = "mane"
	var/mane_dead = "mane-dead"
	var/mane_rest = "mane_rest"
	var/mane_color = "#FFFFFF"

/// The lion's mane, tinted, over the body: the mane state of the body's current life state and fullness.
/mob/living/simple_mob/vore/retaliate/lion/draw(datum/look/look)
	..()
	if(!has_mane)
		return
	var/mane_state = mane_living
	if((stat == CONSCIOUS) && (!icon_rest || !resting || !incapacitated(INCAPACITATION_DISABLED)))
		if(vore_fullness && (vore_icons & SA_ICON_LIVING))
			mane_state = "[mane_living]-[vore_fullness]"
	else if(stat >= DEAD)
		if(vore_fullness && (vore_icons & SA_ICON_DEAD))
			mane_state = "[mane_dead]-[vore_fullness]"
		else
			mane_state = mane_dead
	else if(((stat == UNCONSCIOUS) || resting || incapacitated(INCAPACITATION_DISABLED)) && icon_rest)
		if(vore_fullness && (vore_icons & SA_ICON_REST))
			mane_state = "[mane_rest]-[vore_fullness]"
		else
			mane_state = mane_rest
	look.overlay(look_overlay_image(icon, mane_state, plane = PLANE_LIGHTING_ABOVE, color = mane_color, appearance_flags = (appearance_flags | RESET_COLOR)))

/mob/living/simple_mob/vore/retaliate/lion/proc/set_sex()
	set name = "Set Sex"
	set desc = "Set what sprite set you use (male/female)"
	set category = VERB_CAT_ABILITIES_SETTINGS
	open_request(src, /datum/prompt/choice, PROC_REF(sex_chosen), answerer = src, title = "Set Sex", question = "Please select a sex:", choices = list(FEMALE, MALE), timeout = 0)

/mob/living/simple_mob/vore/retaliate/lion/proc/sex_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/newsex = A.answer.value
	if(newsex == FEMALE)
		set_icon_living("lioness")
		set_icon_dead("lioness-dead")
		set_icon_rest("lioness_rest")
		set_has_mane(FALSE)
	else if(newsex == MALE)
		set_icon_living("lion")
		set_icon_dead("lion-dead")
		set_icon_rest("lion_rest")
		set_has_mane(TRUE)

/mob/living/simple_mob/vore/retaliate/lion/proc/pick_mane_color()
	set name = "Set Mane Color"
	set desc = "Set the color of your mane"
	set category = VERB_CAT_ABILITIES_SETTINGS
	open_request(src, /datum/prompt/color, PROC_REF(mane_color_picked), answerer = src, title = "Mane Color", question = "Please pick a mane color:", default = mane_color, timeout = 0)

/mob/living/simple_mob/vore/retaliate/lion/proc/mane_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		set_mane_color(A.answer.value)

TRACKED(/mob/living/simple_mob/vore/retaliate/lion, has_mane)
TRACKED(/mob/living/simple_mob/vore/retaliate/lion, mane_color)

CAPABILITIES(/mob/living/simple_mob/vore/retaliate/lion)
	verb_entry(/mob/living/simple_mob/vore/retaliate/lion/proc/set_sex, login = TRUE)
	verb_entry(/mob/living/simple_mob/proc/pick_color, login = TRUE)
	verb_entry(/mob/living/simple_mob/vore/retaliate/lion/proc/pick_mane_color, login = TRUE)

