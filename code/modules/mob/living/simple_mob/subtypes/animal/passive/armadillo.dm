//Straight import from Mexico and a direct hit to your heart
/mob/living/simple_mob/animal/passive/armadillo
	name = "armadillo"
	desc = "A small, armored mammal. It seems to enjoy rolling around and sleep as a ball."
	tt_desc = "Dasypus novemcinctus"
	//faction = "mexico" //They are from Mexico. //Amusing but this prompts aggression from crew-aligned mobs.

	icon = 'icons/mob/animal.dmi'
	icon_state = "armadillo"
	item_state = "armadillo_rest"
	icon_living = "armadillo"
	icon_rest = "armadillo_rest"
	icon_dead = "armadillo_dead"

	endurance = 30

	mob_size = MOB_SMALL
	pass_flags = PASSTABLE
	can_pull_size = ITEMSIZE_TINY
	can_pull_mobs = MOB_PULL_NONE
	layer = MOB_LAYER
	density = 0
	movement_cooldown = 0.75 //roughly a bit faster than a person

	response_help  = "pets"
	response_disarm = "rolls aside"
	response_harm   = "stomps"

	melee_damage_lower = 2
	melee_damage_upper = 1
	attacktext = list("nips", "bumps", "scratches")

	vore_taste = "sand"

	min_oxy = 16 //Require atleast 16kPA oxygen
	minbodytemp = 223		//Below -50 Degrees Celcius
	maxbodytemp = 523	//Above 80 Degrees Celcius
	heat_damage_per_tick = 3
	cold_damage_per_tick = 3

	meat_amount = 2
	holder_type = /obj/item/holder/armadillo

	speak_emote = list("rumbles", "chirr?", "churr")

	say_list_type = /datum/say_list/armadillo

	var/obj/item/clothing/head/hat = null // The hat the armadillo may be wearing.

//Hat simulator stolen from slime code.
CAPABILITIES(/mob/living/simple_mob/animal/passive/armadillo)
	owns_one(nameof(hat), on_destroy = ON_DESTROY_SPILL)
	op("armadillo_item", item(/obj/item), then(PROC_REF(armadillo_interaction_item)))
	op("armadillo_hand_grab", hand(), ungated(), stance(I_GRAB), label("Take hat"), then(PROC_REF(armadillo_interaction_hand_grab)))

/// The grab-stance input of armadillo_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/armadillo/proc/armadillo_interaction_hand_grab(datum/act/op/A)
	return armadillo_interaction_hand(A, I_GRAB)

/// The hat it wears, drawn over the legacy provider's state (look.hat() reads the hat's own sprite and hears it change).
/mob/living/simple_mob/animal/passive/armadillo/draw(datum/look/look)
	..()
	look.hat(hat, -7) // Smol

// Clicked on by empty hand.

/// Old attack_hand: grab the hat off.
/mob/living/simple_mob/animal/passive/armadillo/proc/armadillo_interaction_hand(datum/act/op/A, stance)
	var/mob/living/L = A.actor
	. = OP_OK
	if(stance == I_GRAB && hat)
		remove_hat(L)
	else
		return OP_DECLINE

/// Old attackby: hat simulator.
/mob/living/simple_mob/animal/passive/armadillo/proc/armadillo_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	. = OP_OK
	if(istype(I, /obj/item/clothing/head)) // Handle hat simulator.
		give_hat(I, user)
		return
	return OP_DECLINE

// Hat simulator
/mob/living/simple_mob/animal/passive/armadillo/proc/give_hat(obj/item/clothing/head/new_hat, mob/living/user)
	if(!istype(new_hat))
		to_chat(user, span_warning("\The [new_hat] isn't a hat."))
		return
	if(hat)
		to_chat(user, span_warning("\The [src] is already wearing \a [hat]."))
		return
	else
		if(!move_into(src, nameof(src.hat), new_hat, user))
			return
		to_chat(user, span_notice("You place \a [new_hat] on \the [src].  How adorable!"))
		return

/mob/living/simple_mob/animal/passive/armadillo/proc/remove_hat(mob/living/user)
	if(!hat)
		to_chat(user, span_warning("\The [src] doesn't have a hat to remove."))
	else
		var/obj/item/clothing/head/old_hat = rel_take(src, nameof(hat))
		old_hat.forceMove(get_turf(src))
		user.put_in_hands(old_hat)
		to_chat(user, span_warning("You take away \the [src]'s [old_hat.name].  How mean."))

/mob/living/simple_mob/animal/passive/armadillo/proc/drop_hat()
	if(!hat)
		return
	var/obj/item/clothing/head/old_hat = rel_take(src, nameof(hat))
	old_hat.forceMove(get_turf(src))

/obj/item/holder/armadillo
	default_worn_icon = 'icons/mob/head.dmi'
	//item_state = "armadillo_rest" //Commented here as a reminder that holders will always set the item_state to icon_rest. You cannot override it like this.

/mob/living/simple_mob/animal/passive/armadillo/torta
	name = "Torta"
	desc = "A small, armored mammal. It seems to be territorial and protective of the dorms."

/datum/say_list/armadillo
	emote_hear = list("churrs","rumbles","chirrs")
	emote_see = list("rolls in place", "shuffles", "scritches at something")

CAPABILITIES(/mob/living/simple_mob/animal/passive/armadillo/torta)
	owns_one(nameof(hat), starts = /obj/item/clothing/head/sombrero, on_destroy = ON_DESTROY_SPILL)

