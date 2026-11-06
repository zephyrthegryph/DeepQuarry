/obj/item/inflatable_dispenser
	name = "inflatables dispenser"
	desc = "Hand-held device which allows rapid deployment and removal of inflatables."
	icon = 'icons/obj/storage.dmi'
	icon_state = "inf_deployer"
	w_class = ITEMSIZE_LARGE

	var/stored_walls = 5
	var/stored_doors = 2
	var/max_walls = 5
	var/max_doors = 2
	var/mode = 0 // 0 - Walls   1 - Doors

/obj/item/inflatable_dispenser/robot
	w_class = ITEMSIZE_HUGE
	stored_walls = 10
	stored_doors = 5
	max_walls = 10
	max_doors = 5

/obj/item/inflatable_dispenser/examine(mob/user)
	. = ..()
	. += "It has [stored_walls] wall segment\s and [stored_doors] door segment\s stored."
	. += "It is set to deploy [mode ? "doors" : "walls"]"

CAPABILITIES(/obj/item/inflatable_dispenser)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/inflatable_dispenser/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	mode = !mode
	to_chat(user, span_filter_notice("You set \the [src] to deploy [mode ? "doors" : "walls"]."))
	return TRUE

/obj/item/inflatable_dispenser/afterattack(atom/A, mob/user)
	..(A, user)
	if(!user)
		return
	if(!user.Adjacent(A))
		to_chat(user, span_filter_notice("You can't reach!"))
		return
	if(istype(A, /turf))
		try_deploy_inflatable(A, user)
	if(istype(A, /obj/item/inflatable) || istype(A, /obj/structure/inflatable))
		pick_up(A, user)

/obj/item/inflatable_dispenser/proc/try_deploy_inflatable(turf/T, mob/living/user)
	if(mode) // Door deployment
		if(!stored_doors)
			to_chat(user, span_filter_notice("\The [src] is out of doors!"))
			return

		if(T && istype(T))
			new /obj/structure/inflatable/door(T)
			stored_doors--

	else // Wall deployment
		if(!stored_walls)
			to_chat(user, span_filter_notice("\The [src] is out of walls!"))
			return

		if(T && istype(T))
			new /obj/structure/inflatable(T)
			stored_walls--

	play_sfx(T, SFX_ITEMS_ZIP)
	to_chat(user, span_filter_notice("You deploy the inflatable [mode ? "door" : "wall"]!"))

/obj/item/inflatable_dispenser/proc/pick_up(obj/A, mob/living/user)
	if(istype(A, /obj/structure/inflatable))
		if(!istype(A, /obj/structure/inflatable/door))
			if(stored_walls >= max_walls)
				to_chat(user, span_filter_notice("\The [src] is full."))
				return
			stored_walls++
			consumed(A, src)
		else
			if(stored_doors >= max_doors)
				to_chat(user, span_filter_notice("\The [src] is full."))
				return
			stored_doors++
			consumed(A, src)
		play_sfx(src, SFX_MACHINES_HISS, 1.5, vary = TRUE)
		act_message(user, A, others = span_filter_notice("%U% deflates %T% with \the [src]!"))
		return
	if(istype(A, /obj/item/inflatable))
		if(!istype(A, /obj/item/inflatable/door))
			if(stored_walls >= max_walls)
				to_chat(user, span_filter_notice("\The [src] is full."))
				return
			stored_walls++
			consumed(A, src)
		else
			if(stored_doors >= max_doors)
				to_chat(user, span_filter_notice("\The [src] is full!"))
				return
			stored_doors++
			consumed(A, src)
		act_message(user, A, others = span_filter_notice("%U% picks up %T% with \the [src]!"))
		return

	to_chat(user, span_filter_notice("You fail to pick up \the [A] with \the [src]."))
	return
