/mob/living/simple_mob/animal/passive/dog
	name = "dog"
	real_name = "dog"
	desc = "It's a dog."
	tt_desc = "E Canis lupus familiaris"
	icon = 'icons/mob/pets.dmi'
	icon_state = "corgi"
	icon_living = "corgi"
	icon_dead = "corgi_dead"

	endurance = 20

	response_help  = "pets"
	response_disarm = "bops"
	response_harm   = "kicks"

	mob_size = MOB_SMALL

	has_langs = list(LANGUAGE_ANIMAL)

	say_list_type = /datum/say_list/dog

	meat_amount = 3
	meat_type = /obj/item/reagent_containers/food/snacks/meat/corgi

	var/obj/item/inventory_head
	var/obj/item/inventory_back
	species_sounds = "Canine"
	pain_emote_1p = list("yelp", "whine", "bark", "growl")
	pain_emote_3p = list("yelps", "whines", "barks", "growls")

CAPABILITIES(/mob/living/simple_mob/animal/passive/dog)
	op("dog_item", item(/obj/item), then(PROC_REF(dog_interaction_item)))
	owns_one(nameof(inventory_head), on_destroy = ON_DESTROY_SPILL)
	owns_one(nameof(inventory_back), on_destroy = ON_DESTROY_SPILL)

/// Old attackby: newspaper bap.
/mob/living/simple_mob/animal/passive/dog/proc/dog_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held
	. = OP_OK
	if(istype(O, /obj/item/newspaper))
		if(!stat)
			for(var/mob/M in viewers(user, null))
				if ((M.client && !( M.blinded )))
					M.show_message(span_blue("[user] baps [name] on the nose with the rolled up [O]."))
			dir_sequence(list(1,2,4,8,4,2,1,2))
	else
		return OP_DECLINE

/mob/living/simple_mob/animal/passive/dog/regenerate_icons()
	cut_overlays()

	if(inventory_head)
		var/head_icon_state = inventory_head.icon_state
		if(stat == DEAD)
			head_icon_state += "2"

		var/icon/head_icon = image('icons/mob/corgi_head.dmi',head_icon_state)
		if(head_icon)
			add_overlay(head_icon)

	if(inventory_back)
		var/back_icon_state = inventory_back.icon_state
		if(stat == DEAD)
			back_icon_state += "2"

		var/icon/back_icon = image('icons/mob/corgi_back.dmi',back_icon_state)
		if(back_icon)
			add_overlay(back_icon)

	return


/obj/item/reagent_containers/food/snacks/meat/corgi
	name = "corgi meat"
	desc = "Tastes like... well, you know..."


/datum/say_list/dog
	speak = list("YAP", "Woof!", "Bark!", "AUUUUUU")
	emote_hear = list("barks", "woofs", "yaps","pants")
	emote_see = list("shakes its head", "shivers")

// This exists so not every type of dog has to be a subtype of corgi, and in case we get more dog sprites
/mob/living/simple_mob/animal/passive/dog/corgi
	name = "corgi"
	real_name = "corgi"
	desc = "It's a corgi."
	tt_desc = "E Canis lupus familiaris"
	icon_state = "corgi"
	icon_living = "corgi"
	icon_dead = "corgi_dead"
	holder_type = /obj/item/holder/corgi
	organ_names = /datum/decl/mob_organ_names/corgi

/mob/living/simple_mob/animal/passive/dog/corgi/puppy
	name = "corgi puppy"
	real_name = "corgi"
	desc = "It's a corgi puppy."
	icon_state = "puppy"
	icon_living = "puppy"
	icon_dead = "puppy_dead"
	holder_type = /obj/item/holder/corgi

//pupplies cannot wear anything.

/mob/living/simple_mob/animal/passive/dog/corgi/puppy/Bockscar
	name = "Bockscar"
	real_name = "Bockscar"

/mob/living/simple_mob/animal/passive/dog/corgi/puppy/wiggle
	name = "Mister Wiggles"
	real_name = "Mister Wiggles"
	desc = "An emotional support corgi! He gets along with everyone, even Runtime."

//IAN! SQUEEEEEEEEE~
/mob/living/simple_mob/animal/passive/dog/corgi/Ian
	name = "Ian"
	real_name = "Ian"	//Intended to hold the name without altering it.
	gender = MALE
	desc = "It's a corgi."
	var/turns_since_scan = 0
	makes_dirt = FALSE // no more dirt
	holder_type = /obj/item/holder/corgi

/mob/living/simple_mob/animal/passive/dog/corgi/Ian/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/passive/dog/corgi/Ian/life_type_post(datum/seq_frame/life/F)
	..()

	//Not replacing with SA FollowTarget mechanics because Ian behaves... very... specifically.

	//Feeding, chasing food, FOOOOODDDD
	if(!src.stat && !src.resting && !src?.buckled_to())
		src.turns_since_scan++
		if(src.turns_since_scan > 5)
			src.turns_since_scan = 0
			if((src.movement_target) && !(isturf(src.movement_target.loc) || ishuman(src.movement_target.loc) ))
				rel_clear(src, nameof(src.movement_target))
			if(!src.movement_target || !(src.movement_target.loc in oview(src, 7)) )
				rel_clear(src, nameof(src.movement_target))
				for(var/obj/item/reagent_containers/food/snacks/S in oview(src,7))
					if(isturf(S.loc) || ishuman(S.loc))
						rel_set(src, nameof(src.movement_target), S)
						break
			if(src.movement_target)
				after(src, 0, TYPE_PROC_REF(/mob/living/simple_mob, chase_target))

		if(prob(1))
			after(src, 0, TYPE_PROC_REF(/mob, visible_emote), with = list(pick("dances around","chases their tail")))
			src.dir_sequence(list(1,2,4,8,4,2,1,2,4,8,4,2,1,2,4,8,4,2))

//LISA! SQUEEEEEEEEE~
/mob/living/simple_mob/animal/passive/dog/corgi/Lisa
	name = "Lisa"
	real_name = "Lisa"
	gender = FEMALE
	desc = "It's a corgi with a cute pink bow."
	icon_state = "lisa"
	icon_living = "lisa"
	icon_dead = "lisa_dead"
	response_help  = "pets"
	response_disarm = "bops"
	response_harm   = "kicks"
	var/turns_since_scan = 0
	var/puppies = 0
	holder_type = /obj/item/holder/lisa

//Lisa already has a cute bow!

/mob/living/simple_mob/animal/passive/dog/corgi/Lisa/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/passive/dog/corgi/Lisa/life_type_post(datum/seq_frame/life/F)
	..()

	if(!src.stat && !src.resting && !src?.buckled_to())
		src.turns_since_scan++
		if(src.turns_since_scan > 15)
			src.turns_since_scan = 0
			var/alone = TRUE
			var/ian = FALSE
			for(var/mob/M in oviewers(7, src))
				if(istype(M, /mob/living/simple_mob/animal/passive/dog/corgi/Ian))
					if(M.client)
						alone = FALSE
						break
					else
						ian = M
				else
					alone = FALSE
					break
			if(alone && ian && src.puppies < 4)
				if(src.near_camera(src) || src.near_camera(ian))
					return
				new /mob/living/simple_mob/animal/passive/dog/corgi/puppy(src.loc)

		if(prob(1))
			after(src, 0, TYPE_PROC_REF(/mob, visible_emote), with = list(pick("dances around","chases her tail")))
			src.dir_sequence(list(1,2,4,8,4,2,1,2,4,8,4,2,1,2,4,8,4,2))

//NARSIAN HAS COME
/mob/living/simple_mob/animal/passive/dog/corgi/narsian
	name = "Nars-Ian"
	desc = "It's a corgi???"
	icon_state = "narsian"
	icon_living = "narsian"
	icon_rest = "narsian_rest"
	icon_dead = "narsian_dead"

	makes_dirt = FALSE
	holder_type = /obj/item/holder/narsian

/mob/living/simple_mob/animal/passive/dog/void_puppy
	name = "void puppy"
	desc = "My stars!"
	icon_state = "void_puppy"
	icon_living = "void_puppy"
	icon_dead = "void_puppy_dead"
	holder_type = /obj/item/holder/void_puppy

/mob/living/simple_mob/animal/passive/dog/bullterrier
	name = "bull terrier"
	desc = "It's a bull terrier."
	icon_state = "bullterrier"
	icon_living = "bullterrier"
	icon_dead = "bullterrier_dead"
	icon_rest = null
	holder_type = /obj/item/holder/bullterrier

// Tamaskans
/mob/living/simple_mob/animal/passive/dog/tamaskan
	name = "tamaskan"
	real_name = "tamaskan"
	desc = "It's a tamaskan."
	icon_state = "tamaskan"
	icon_living = "tamaskan"
	icon_dead = "tamaskan_dead"

/mob/living/simple_mob/animal/passive/dog/tamaskan/Spice
	name = "Spice"
	real_name = "Spice"	//Intended to hold the name without altering it.
	gender = FEMALE
	desc = "It's a tamaskan, the name Spice can be found on its collar."

// Brittany Spaniel
/mob/living/simple_mob/animal/passive/dog/brittany
	name = "brittany"
	real_name = "brittany"
	desc = "It's a brittany spaniel."
	icon_state = "brittany"
	icon_living = "brittany"
	icon_dead = "brittany_dead"

/datum/decl/mob_organ_names/corgi
//You monster.
TYPE_TABLE(/datum/decl/mob_organ_names/corgi, mob_organ_hit_zones, list("head", "body", "left foreleg", "right foreleg", "left hind leg", "right hind leg", "tail", "heart"))
