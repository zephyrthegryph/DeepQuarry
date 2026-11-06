/mob/living/simple_mob/vore/alienanimals/catslug
	name = "catslug"
	desc = "A noodley bodied creature with thin arms and legs, and gloomy dark eyes."
	tt_desc = "Mollusca Feline"
	icon_state = "catslug"
	icon_living = "catslug"
	icon_dead = "catslug_dead"
	icon_rest = "catslug_rest"
	icon = 'icons/mob/alienanimals_x32.dmi'

	endurance = 50
	movement_cooldown = -1
	holder_type = /obj/item/holder/catslug

	response_help = "hugs"
	response_disarm = "rudely paps"
	response_harm = "punches"

	harm_intent_damage = 2
	melee_damage_lower = 2
	melee_damage_upper = 5

	has_hands = TRUE
	mob_size = MOB_SMALL
	friendly = list("hugs")
	see_in_dark = 8

	ID_provided = TRUE

	player_msg = "You have escaped the foul weather, into this much more pleasant place. You are an intelligent creature capable of more than most think. You can pick up and use many things, and even carry some of them with you into the vents, which you can use to move around quickly. You're quiet and capable, you speak with your hands and your deeds!<br>- - - - -<br>" + span_notice("Keep in mind, your goal should generally be to survive. You're expected to follow the same rules as everyone else, so don't go self antagging without permission from the staff team, but you are able and capable of defending yourself from those who would attack you for no reason.")

	has_langs = list(LANGUAGE_SIGN)

	var/obj/item/clothing/head/hat = null // Scughat.
	var/can_wear_hat = TRUE				  // Some have inbuilt hats


	vore_active = 1
	vore_bump_chance = 1
	vore_ignores_undigestable = 0
	vore_default_mode = DM_DIGEST
	vore_icons = SA_ICON_LIVING
	vore_stomach_name = "Stomach"
	vore_default_contamination_flavor = "Wet"
	vore_default_contamination_color = "grey"
	vore_default_item_mode = IM_DIGEST

/mob/living/simple_mob/vore/alienanimals/catslug/load_default_bellies()
	. = ..()
	var/obj/belly/B = vore_selected_of(src)
	B.name = "stomach"
	B.desc = "The hot slick gut of a catslug!! Copious slime smears over you as you’re packed away into the gloom and oppressive humidity of this churning gastric sac. The pressure around you is intense, the squashy flesh bends and forms to your figure, clinging to you insistently! There’s basically no free space at all as your ears are filled with the slick slide of flesh against flesh and the burbling of gastric juices glooping all around you. The thumping of a heart booms from somewhere nearby, making everything pulse in against you in time with it! This is it! You’ve been devoured by a catslug!!!"
	B.set_mode_flags(40)
	B.set_digest_brute(0.5)
	B.set_digest_burn(0.5)
	B.set_digestchance(10)
	B.set_absorbchance(1)
	B.set_escapechance(15)

// Catslug unique items.
TYPE_TABLE(/mob/living/simple_mob/vore/alienanimals/catslug, ventcrawl_get_item_whitelist, list( \
		VENTCRAWL_BASE_WHITELIST, \
		VENTCRAWL_VORE_WHITELIST, \
		VENTCRAWL_SMALLITEM_WHITELIST, \
		/obj/item/material, \
		/obj/item/melee, \
		/obj/item/stack/, \
		/obj/item/tool, \
		/obj/item/reagent_containers/food, \
		/obj/item/ore, \
		/obj/item/disk/nuclear, \
		/obj/item/card, \
		/obj/item/radio, \
		/obj/item/perfect_tele_beacon, \
		))

CAPABILITIES(/mob/living/simple_mob/vore/alienanimals/catslug)
	configure(atom_rules(catalogue_data = list(/datum/category_item/catalogue/fauna/catslug)))
	configure(mob_rules(faction = FACTION_CATSLUG))
	configure(living_rules(vore_capacity = 1, say_list_type = /datum/say_list/catslug, climbing_delay = 2.0))
	configure(butchery_rules(meat_type = /obj/item/reagent_containers/food/snacks/meat, meat_amount = 2))
	profile(nameof(vore_prefs), /datum/record/vore_prefs, fields = list("allow_mind_transfer" = TRUE))
	configure(mob_movement(can_climb = TRUE))
	verb_entry(/mob/living/proc/ventcrawl)
	verb_entry(/mob/living/proc/hide)
	verb_entry(/mob/living/simple_mob/vore/alienanimals/catslug/proc/catslug_color)
	owns_one(nameof(hat), on_destroy = ON_DESTROY_SPILL)
	op("catslug_item", item(/obj/item), then(PROC_REF(catslug_interaction_item)))
	op("catslug_hand_help", hand(), ungated(), stance(I_HELP), label("Pet"), then(PROC_REF(catslug_interaction_hand_help)))
	hat_bearer(nameof(hat), allowed = nameof(can_wear_hat))

/// The help-stance input of catslug_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/vore/alienanimals/catslug/proc/catslug_interaction_hand_help(datum/act/op/A)
	return catslug_interaction_hand(A, I_HELP)

/// Old attackby: feeding (a hat goes on through the hat_bearer capability).
/mob/living/simple_mob/vore/alienanimals/catslug/proc/catslug_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/O = A.held
	. = OP_OK
	if(!istype(O, /obj/item/reagent_containers/food/snacks))
		return OP_DECLINE
	if(resting)
		to_chat(user, span_notice("\The [src] is napping, and doesn't respond to \the [O]."))
		return
	if(nutrition_of(src) >= living_rules_of(src).max_nutrition)
		if(user == src)
			to_chat(src, span_notice("You're too full to eat another bite."))
			return
		to_chat(user, span_notice("\The [src] seems too full to eat."))
		return
	var/nutriment_amount = O.reagents?.get_reagent_amount(REAGENT_ID_NUTRIMENT) //does it have nutriment, if so how much?
	var/protein_amount = O.reagents?.get_reagent_amount(REAGENT_ID_PROTEIN) //does it have protein, if so how much?
	var/glucose_amount = O.reagents?.get_reagent_amount(REAGENT_ID_GLUCOSE) //does it have glucose, if so how much?
	var/yum = nutriment_amount + protein_amount + glucose_amount
	if(yum)
		yum = (yum * 20) / 3
		adjust_nutrition(yum) //add the nutriment!
	O.set_bitecount(O.bitecount + 1)
	if(O.bitecount >= 3)
		consume(O, user)
		act_message(src, O, null, MSG_OTHERS(span_notice("%U% eats %T%.")))
	else
		to_chat(user, span_notice("\The [src] takes a bite of \the [O]."))
		if(user != src)
			to_chat(src, span_notice("\The [user] feeds \the [O] to you."))
	play_sfx(src, SFX_ITEMS_EATFOOD)

/// Old attack_hand; subtypes override this proc.
/mob/living/simple_mob/vore/alienanimals/catslug/proc/catslug_interaction_hand(datum/act/op/A, stance)
	var/mob/living/carbon/human/M = A.actor
	. = OP_OK

	if(stat == DEAD)
		return OP_DECLINE
	if(stance != I_HELP)
		return OP_DECLINE
	play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
	if(resting)
		act_message(M, src, MSG_SELF(span_notice("You shake %T% awake!")), MSG_OTHERS(span_notice("\The [M.name] shakes %T% awake from their nap.")))
		lay_down()
		ai_brain.go_wake()
		return
	if(hud_of(M)?.zone_sel?.selecting == BP_HEAD)
		act_message(M, src, \
			MSG_SELF(span_notice("You pat %T% on the head.")), \
			MSG_OTHERS(span_notice("%U% pats %T% on the head.")))
		if(client)
			return
		if(prob(10))
			act_message(src, M, null, MSG_OTHERS(span_notice("%U% purrs and leans into %T%'s hand.")))
	else if(hud_of(M)?.zone_sel?.selecting == BP_R_HAND || hud_of(M)?.zone_sel?.selecting == BP_L_HAND)
		act_message(M, src, \
			MSG_SELF(span_notice("You shake %T%'s hand.")), \
			MSG_OTHERS(span_notice("%U% shakes %T%'s hand.")))
		if(client)
			return
		if(prob(10))
			act_message(src, M, null, MSG_OTHERS(span_notice("%U%'s looks a little confused nibbles at %T%'s hand experimentally.")))
	else if(hud_of(M)?.zone_sel?.selecting == "mouth")
		act_message(M, src, \
			MSG_SELF(span_notice("You boop %T% on the nose.")), \
			MSG_OTHERS(span_notice("%U% boops %T%'s nose.")))
		if(client)
			return
		if(prob(10))
			act_message(src, M, null, MSG_OTHERS(span_notice("%U%'s eyes widen as they stare at %T%. After a moment they rub their prodded snoot.")))
	else if(hud_of(M)?.zone_sel?.selecting == BP_GROIN)
		act_message(M, src, \
			MSG_SELF(span_notice("You rub %T%'s tummy... You feel the danger.")), \
			MSG_OTHERS(span_notice("%U% rubs %T%'s tummy...")))
		if(client)
			return
		act_message(src, M, null, MSG_OTHERS(span_notice("%U% pushes %T%'s hand away from their tummy and furrows their brow!")))
		//prob(5) give_target on tummy rub removed.
	else
		return OP_DECLINE

/// The hat it wears.
/mob/living/simple_mob/vore/alienanimals/catslug/draw(datum/look/look)
	..()
	look.hat(hat, -7)

/mob/living/simple_mob/vore/alienanimals/catslug/Login()	//If someone plays as us let's just be a passive mob in case accidents happen if the player D/Cs
	. = ..()
	//legacy if-block emptied.
		//legacy .wander reference removed (no equivalent on /datum/ai_brain).

/mob/living/simple_mob/vore/alienanimals/catslug/proc/catslug_color()
	set name = "Pick Color"
	set category = VERB_CAT_ABILITIES_SETTINGS
	set desc = "You can set your color!"
	if(picked_color)
		to_chat(src, span_notice("You have already picked a color! If you picked the wrong color, ask an admin to change your picked_color variable to 0."))
		return
	open_request(src, /datum/prompt/color, PROC_REF(catslug_color_picked), answerer = src, question = "Choose a color.", default = color, timeout = 0)

/mob/living/simple_mob/vore/alienanimals/catslug/proc/catslug_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value && !picked_color)
		set_color(A.answer.value)
		set_picked_color(TRUE)

/mob/living/simple_mob/vore/alienanimals/catslug/horrible
