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
	var/mutable_appearance/mane_overlay
	var/mane_living = "mane"
	var/mane_dead = "mane-dead"
	var/mane_rest = "mane_rest"
	var/mane_color = "#FFFFFF"

/// Cached immutable mane appearances; player recolours have a bounded shared store.
DECLARE_SHARED_CACHE_EX(lion_mane, GLOBAL_PROC_REF(build_lion_mane), SC_NEVER, 1024, 0)

/proc/cached_lion_mane(mane_icon, state, tint, flags)
	if(!isfile(mane_icon))
		return build_lion_mane(mane_icon, state, tint, flags)
	var/key = json_encode(list("[mane_icon]", state, tint, flags))
	return CACHED_KEY(lion_mane, key, mane_icon, state, tint, flags)

/proc/build_lion_mane(mane_icon, state, tint, flags)
	var/static/image/scratch = image(null)
	scratch.icon = mane_icon
	scratch.icon_state = state
	scratch.color = tint
	scratch.plane = PLANE_LIGHTING_ABOVE
	scratch.appearance_flags = flags
	return scratch.appearance

/mob/living/simple_mob/vore/retaliate/lion/proc/add_mane()
	var/mane_icon = icon
	var/mane_state
	if((stat == CONSCIOUS) && (!icon_rest || !resting || !incapacitated(INCAPACITATION_DISABLED)))
		if(!vore_fullness || !(vore_icons & SA_ICON_LIVING))
			mane_state = "[mane_living]"
		else
			mane_state = "[mane_living]-[vore_fullness]"
	else if(stat >= DEAD)
		if(!vore_fullness || !(vore_icons & SA_ICON_DEAD))
			mane_state = "[mane_dead]"
		else
			mane_state = "[mane_dead]-[vore_fullness]"
	else if(((stat == UNCONSCIOUS) || resting || incapacitated(INCAPACITATION_DISABLED) ) && icon_rest)
		if(!vore_fullness || !(vore_icons & SA_ICON_REST))
			mane_state = "[mane_rest]"
		else
			mane_state = "[mane_rest]-[vore_fullness]"
	else
		// No state branch selected: retain the previous visual, then apply the current tint and flags.
		mane_icon = mane_overlay.icon
		mane_state = mane_overlay.icon_state
	mane_overlay = cached_lion_mane(mane_icon, mane_state, mane_color, appearance_flags | RESET_COLOR)
	add_overlay(mane_overlay)

/mob/living/simple_mob/vore/retaliate/lion/proc/remove_mane()
	if(mane_overlay)
		cut_overlay(mane_overlay)
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
	var/newsex = A.answer.value
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
	open_request(src, /datum/prompt/color, PROC_REF(mane_color_picked), answerer = src, title = "Mane Color", question = "Please pick a mane color:", default = mane_color, timeout = 0)

/mob/living/simple_mob/vore/retaliate/lion/proc/mane_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		mane_color = A.answer.value
		update_icon()

CAPABILITIES(/mob/living/simple_mob/vore/retaliate/lion)
	verb_entry(/mob/living/simple_mob/vore/retaliate/lion/proc/set_sex, login = TRUE)
	verb_entry(/mob/living/simple_mob/proc/pick_color, login = TRUE)
	verb_entry(/mob/living/simple_mob/vore/retaliate/lion/proc/set_mane_color, login = TRUE)

