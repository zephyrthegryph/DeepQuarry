GLOBAL_VAR_CONST(MAX_CHICKENS, 50)	// How many chickens CAN we have?
GLOBAL_VAR_INIT(chicken_count, 0)	// How mant chickens DO we have?

/mob/living/simple_mob/animal/passive/chicken
	name = "chicken"
	desc = "Hopefully the eggs are good this season."
	tt_desc = "E Gallus gallus"
	icon_state = "chicken_white"
	icon_living = "chicken"
	icon_dead = "chicken_dead"

	endurance = 10

	pass_flags = PASSTABLE
	mob_size = MOB_SMALL

	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"
	attacktext = list("pecked")

	organ_names = /datum/decl/mob_organ_names/chicken

	has_langs = list(LANGUAGE_ANIMAL)

	say_list_type = /datum/say_list/chicken

	meat_amount = 4
	meat_type = /obj/item/reagent_containers/food/snacks/meat/chicken

	var/eggsleft = 0
	var/body_color

/mob/living/simple_mob/animal/passive/chicken/Initialize(mapload)
	. = ..()
	if(!body_color)
		body_color = pick( list("brown","black","white") )
	icon_state = "chicken_[body_color]" // ALLOW(decl): Initialize rolls a random colour per instance; a declaration has no random form
	icon_living = "chicken_[body_color]"
	icon_dead = "chicken_[body_color]_dead"
	pixel_x = rand(-6, 6)
	pixel_y = rand(0, 10)
	GLOB.chicken_count += 1

// the population cap counts it out.
/mob/living/simple_mob/animal/passive/chicken/lifecycle_dematerialize()
	GLOB.chicken_count -= 1
	..()

EXTEND_INTERACTIONS(/mob/living/simple_mob/animal/passive/chicken, INTERACT_ITEM(null, PROC_REF(chicken_interaction_item)))

/// Old attackby: feeding wheat.
/mob/living/simple_mob/animal/passive/chicken/proc/chicken_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	. = TRUE
	if(istype(O, /obj/item/reagent_containers/food/snacks/grown)) //feedin' dem chickens
		var/obj/item/reagent_containers/food/snacks/grown/G = O
		if(G.seed() && G.seed().kitchen_tag == PLANT_WHEAT)
			if(!stat && eggsleft < 8)
				act_message(user, O, MSG_SELF(span_blue("You feed %T% to [name]! It clucks happily.")), MSG_OTHERS(span_blue("%U% feeds %T% to [name]! It clucks happily.")))
				user.drop_item()
				consume(O, user)
				eggsleft += rand(1, 4)
			else
				to_chat(user, span_blue("[name] doesn't seem hungry!"))
		else
			to_chat(user, "[name] doesn't seem interested in that.")
	else
		return FALSE

/mob/living/simple_mob/animal/passive/chicken/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/passive/chicken/life_type_post(datum/seq_frame/life/F)
	..()
	if(!F.alive())
		return
	if(!src.stat && prob(3) && src.eggsleft > 0)
		act_message(src, null, null, MSG_OTHERS("%U% [pick("lays an egg.","squats down and croons.","begins making a huge racket.","begins clucking raucously.")]"))
		src.eggsleft--
		var/obj/item/reagent_containers/food/snacks/egg/E = new(get_turf(src))
		E.pixel_x = rand(-6,6)
		E.pixel_y = rand(-6,6)
		if(GLOB.chicken_count < GLOB.MAX_CHICKENS && prob(10))
			om_task_periodic(E, PERIODIC_SLOW)

/obj/item/reagent_containers/food/snacks/egg/var/amount_grown = 0

// This only starts normally if there are less than MAX_CHICKENS chickens
/obj/item/reagent_containers/food/snacks/egg/periodic_step()
	if(isturf(loc))
		amount_grown += rand(1,2)
		if(amount_grown >= 100)
			visible_message("[src] hatches with a quiet cracking sound.")
			om_task_periodic_stop(src)
			replace_with(src, /mob/living/simple_mob/animal/passive/chick)
	else
		om_task_periodic_stop(src)

/mob/living/simple_mob/animal/passive/chick
	name = "chick"
	desc = "Adorable! They make such a racket though."
	tt_desc = "E Gallus gallus"
	icon_state = "chick"
	icon_living = "chick"
	icon_dead = "chick_dead"
	icon_gib = "chick_gib"

	endurance = 1

	pass_flags = PASSTABLE | PASSGRILLE
	mob_size = MOB_MINISCULE

	response_help  = "pets"
	response_disarm = "gently pushes aside"
	response_harm   = "kicks"
	attacktext = list("kicked")

	has_langs = list(LANGUAGE_ANIMAL)

	say_list_type = /datum/say_list/chick

	meat_amount = 1
	meat_type = /obj/item/reagent_containers/food/snacks/meat/chicken

	var/amount_grown = 0

CAPABILITIES(/mob/living/simple_mob/animal/passive/chick)
	rolls(nameof(pixel_x), range_of(-6, 6))
	rolls(nameof(pixel_y), range_of(0, 10))

/mob/living/simple_mob/animal/passive/chick/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/passive/chick/life_type_post(datum/seq_frame/life/F)
	..()
	if(!F.alive())
		return
	if(!src.stat)
		src.amount_grown += rand(1,2)
		if(src.amount_grown >= 100)
			var/mob/living/simple_mob/animal/passive/chicken/C = new (src.loc)
			C.set_ghostjoin(1)
			C.ghostjoin_icon()
			registry_join(REGISTRY_GHOST_PODS, C)
			spent(src)

// Say Lists
/datum/say_list/chicken
	speak = list("Cluck!","BWAAAAARK BWAK BWAK BWAK!","Bwaak bwak.")
	emote_hear = list("clucks","croons")
	emote_see = list("pecks at the ground","flaps its wings viciously")

/datum/say_list/chick
	speak = list("Cherp.","Cherp?","Chirrup.","Cheep!")
	emote_hear = list("cheeps")
	emote_see = list("pecks at the ground","flaps its tiny wings")

/datum/decl/mob_organ_names/chicken
TYPE_TABLE(/datum/decl/mob_organ_names/chicken, mob_organ_hit_zones, list("head", "body", "left wing", "right wing", "left leg", "right leg", "tendies"))
