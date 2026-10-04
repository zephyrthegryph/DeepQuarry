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
	var/image/mane_overlay
	var/mane_living = "mane"
	var/mane_dead = "mane-dead"
	var/mane_rest = "mane_rest"
	var/mane_color = "#FFFFFF"

/mob/living/simple_mob/vore/retaliate/lion/proc/add_mane()
	if((stat == CONSCIOUS) && (!icon_rest || !resting || !incapacitated(INCAPACITATION_DISABLED)))
		if(!vore_fullness || !(vore_icons & SA_ICON_LIVING))
			mane_overlay = image(icon, "[mane_living]")
		else
			mane_overlay = image(icon, "[mane_living]-[vore_fullness]")
	else if(stat >= DEAD)
		if(!vore_fullness || !(vore_icons & SA_ICON_DEAD))
			mane_overlay = image(icon, "[mane_dead]")
		else
			mane_overlay = image(icon, "[mane_dead]-[vore_fullness]")
	else if(((stat == UNCONSCIOUS) || resting || incapacitated(INCAPACITATION_DISABLED) ) && icon_rest)
		if(!vore_fullness || !(vore_icons & SA_ICON_REST))
			mane_overlay = image(icon, "[mane_rest]")
		else
			mane_overlay = image(icon, "[mane_rest]-[vore_fullness]")
	mane_overlay.color = mane_color
	mane_overlay.plane = PLANE_LIGHTING_ABOVE
	mane_overlay.appearance_flags = appearance_flags | RESET_COLOR
	add_overlay(mane_overlay)

/mob/living/simple_mob/vore/retaliate/lion/proc/remove_mane()
	if(mane_overlay)
		cut_overlay(mane_overlay)
		qdel(mane_overlay)
		mane_overlay = null

DECLARE_APPEARANCE_PROC(/mob/living/simple_mob/vore/retaliate/lion, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/simple_mob/vore/retaliate/lion/appearance_overlays()
	. = list()
	. += ..()
	if(has_mane)
		add_mane()
	else
		remove_mane()


/mob/living/simple_mob/vore/retaliate/lion/proc/set_sex()
	set name = "Set Sex"
	set desc = "Set what sprite set you use (male/female)"
	set category = VERB_CAT_ABILITIES_SETTINGS
	open_request(src, /datum/prompt/choice, PROC_REF(sex_chosen), answerer = src, title = "Set Sex", question = "Please select a sex:", choices = list(FEMALE, MALE), timeout = 0)

/mob/living/simple_mob/vore/retaliate/lion/proc/sex_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/newsex = A.answer.answer_value
	if(newsex == FEMALE)
		icon_living = "lioness"
		icon_dead = "lioness-dead"
		icon_rest = "lioness_rest"
		has_mane = FALSE
		update_icon()
	else if(newsex == MALE)
		icon_living = "lion"
		icon_dead = "lion-dead"
		icon_rest = "lion_rest"
		has_mane = TRUE
		update_icon()

/mob/living/simple_mob/vore/retaliate/lion/proc/set_mane_color()
	set name = "Set Mane Color"
	set desc = "Set the color of your mane"
	set category = VERB_CAT_ABILITIES_SETTINGS
	om_ask(src, /datum/om/prompt/color, PROC_REF(mane_color_picked), title = "Mane Color", message = "Please pick a mane color:", default = mane_color)

/mob/living/simple_mob/vore/retaliate/lion/proc/mane_color_picked(datum/om/prompt/color/ask)
	if(ask.picked_color)
		mane_color = ask.picked_color
		update_icon()

DECLARE_LOGIN_VERB(/mob/living/simple_mob/vore/retaliate/lion, /mob/living/simple_mob/vore/retaliate/lion/proc/set_sex)
DECLARE_LOGIN_VERB(/mob/living/simple_mob/vore/retaliate/lion, /mob/living/simple_mob/proc/pick_color)
DECLARE_LOGIN_VERB(/mob/living/simple_mob/vore/retaliate/lion, /mob/living/simple_mob/vore/retaliate/lion/proc/set_mane_color)

