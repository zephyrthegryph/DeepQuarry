//turkey - sprites and writing done by VerySoft
/mob/living/simple_mob/vore/turkeygirl
	name = "turkeygirl"
	desc = "A feathered woman! She looks like some kind of plump turkey!"
	tt_desc = "Meleagris gallopian"
	icon = 'icons/mob/turkey.dmi'
	icon_state = "turkeygirl"
	icon_living = "turkeygirl"
	icon_dead = "turkeygirl-dead"

	endurance = 100

	has_hands = TRUE

	faction = "turkey"

	response_help  = "hugs"
	response_disarm = "pushes"
	response_harm   = "punches"
	attacktext = list("pecked")

	has_langs = list(LANGUAGE_GALCOM , LANGUAGE_ANIMAL)

	meat_amount = 100
	meat_type = /obj/item/reagent_containers/food/snacks/meat/chicken


	say_list_type = /datum/say_list/turkey

	vore_active = 1
	vore_capacity = 2
	vore_bump_chance = 10
	vore_pounce_chance = 10
	vore_pounce_maxhealth = 999
	vore_ignores_undigestable = 0
	vore_default_mode = DM_SELECT
	vore_icons = SA_ICON_LIVING
	vore_stomach_name = "Stomach"
	vore_default_contamination_flavor = "Wet"
	vore_default_contamination_color = "grey"
	vore_default_item_mode = IM_DIGEST
	vore_standing_too = TRUE

/mob/living/simple_mob/vore/turkeygirl/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected
	B.name = "stomach"
	B.desc = "The hot churning stomach of a turkey girl! The doughy flesh presses inward to form to your figure, thick slime coating everything, and very shortly that includes you as well! There isn't any escaping that constant full body motion, as her body works to ball yours up into a tight little package. Gurgling and glubbing with every shifting movement, while her pulse throbs through the flesh all around you with every beat of her heart. All in all, one thing is for certain! You've become turkey stuffing! Oh no..."
	B.mode_flags = DM_FLAG_THICKBELLY | DM_FLAG_NUMBING
	B.belly_fullscreen = "VBOanim_belly1"
	B.digest_brute = 1
	B.digest_burn = 6
	B.digestchance = 0
	B.absorbchance = 0
	B.escapechance = 15
	B.colorization_enabled = TRUE
	B.belly_fullscreen_color = "#521717"

/datum/say_list/turkey
	speak = list("Gobble!", "Gobble gobble!", "Gobble gobble gobble!", "Give me something to be thankful for~", "Could use something to gobble~", "Why don't you make a pilgrimage over here and give me something good to eat?", "I want a treat... I could bite you too if you like~", "What's your favorite time of year?", "Autumn is the best time of year~", "You just gonna let a girl go hungry?")

/mob/living/simple_mob/vore/turkeygirl/draw(datum/look/look)
	..()
	if(stat == DEAD)
		return
	var/state = look.state_so_far(src)
	if(vore_fullness == 2 || nutrition >= 5000)
		state = "[icon_living]-2"
	else if(vore_fullness == 1 || nutrition >= 2500)
		state = "[icon_living]-1"
	if(resting)
		state = "[state]-resting"
	look.state(state)

CAPABILITIES(/mob/living/simple_mob/vore/turkeygirl)
	op("turkeygirl_item", item(/obj/item), then(PROC_REF(turkeygirl_interaction_item)))

/// Old attackby: feeding.
/mob/living/simple_mob/vore/turkeygirl/proc/turkeygirl_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/O = A.held
	. = OP_OK
	if(stat)
		return OP_DECLINE

	if(!istype(O, /obj/item/reagent_containers/food/snacks))
		return OP_DECLINE

	if(nutrition >= max_nutrition)
		if(user == src)
			to_chat(src, span_notice("You're too full to eat another bite."))
			return
		to_chat(user, span_notice("\The [src] seems too full to eat."))
		return

	user.setClickCooldown(user.get_attack_speed(O))
	if(O.reagents)
		O.reagents.trans_to_mob(src, O.bitesize, CHEM_INGEST)
		adjust_nutrition(O.bitesize * 20)
	O.bitecount ++
	O.On_Consume(src)
	if(O)
		to_chat(user, span_notice("\The [src] takes a bite of \the [O]."))
		if(user != src)
			to_chat(src, span_notice("\The [user] feeds \the [O] to you."))
	play_sfx(src, SFX_ITEMS_EATFOOD)
