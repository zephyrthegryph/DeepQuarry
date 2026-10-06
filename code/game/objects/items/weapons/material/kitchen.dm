/obj/item/material/kitchen
	icon = 'icons/obj/kitchen.dmi'

/*
 * Utensils
 */
/obj/item/material/kitchen/utensil
	drop_sound = SFX_ITEMS_DROP_KNIFE
	pickup_sound = SFX_ITEMS_PICKUP_KNIFE
	w_class = ITEMSIZE_TINY
	thrown_force_divisor = 1
	attack_verb = list("attacked", "stabbed", "poked")
	sharp = TRUE
	edge = TRUE
	injury_kind = INJURY_CUT
	force_divisor = 0.1 // 6 when wielded with hardness 60 (steel)
	thrown_force_divisor = 0.25 // 5 when thrown with weight 20 (steel)
	var/scoop_volume = 5
	var/loaded // Name for currently loaded food object.
	var/loaded_color // Color for currently loaded food object.

	var/list/food_inserted_micros


CAPABILITIES(/obj/item/material/kitchen/utensil)
	reagents(nameof(scoop_volume))
	rolls(nameof(pixel_y), PROC_REF(roll_pixel_y))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/material/kitchen/utensil/proc/roll_pixel_y(datum/roller/R)
	return R.chance(60) ? R.number(0, 4) : pixel_y

DECLARE_APPEARANCE_PROC(/obj/item/material/kitchen/utensil, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/material/kitchen/utensil/appearance_overlays()
	. = list()
	. += ..()
	if(loaded)
		var/image/I = new(icon, "loadedfood")
		I.color = loaded_color
		. += I

/obj/item/material/kitchen/utensil/proc/load_food(mob/user, obj/item/reagent_containers/food/snacks/loading)
	if (reagents.total_volume > 0)
		to_chat(user, span_danger("There is already something on \the [src]."))
		return
	if (!loading?.reagents?.total_volume)
		to_chat(user, span_notice("Nothing to scoop up in \the [loading]!"))
		return

	loaded = "\the [loading]"
	act_message(user, src, MSG_SELF(span_notice("You scoop up some of [loaded] with %T%!")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " scoops up some of [loaded] with %T%!")))
	loading.bitecount++
	loading.reagents.trans_to_obj(src, min(loading.reagents.total_volume, scoop_volume))
	loaded_color = loading.filling_color

	if(loading.food_inserted_micros && loading.food_inserted_micros.len)
		if(!food_inserted_micros)
			rel_set(src, nameof(food_inserted_micros), list())

		for(var/mob/living/F in loading.food_inserted_micros)
			var/do_transfer = FALSE

			if(!loading.reagents.total_volume)
				do_transfer = TRUE
			else
				var/transfer_chance = (loading.bitecount/(loading.bitecount + (loading.bitesize / loading.reagents.total_volume) + 1))*100
				if(prob(transfer_chance))
					do_transfer = TRUE

			if(do_transfer)
				move_into(src, nameof(src.food_inserted_micros), F) // out of the food, whose food_inserted_micros lets it go

	if (loading.reagents.total_volume <= 0)
		consume(loading, user)
	update_icon()

/obj/item/material/kitchen/utensil/proc/force_feed_done(mob/living/carbon/M, mob/living/user)
	if(!loaded)
		return
	act_message(user, M, others = span_bold("%U%") + " feeds some of [loaded] to %T% with \the [src].")
	play_sfx(src, SFX_ITEMS_EATFOOD, volume = rand(10,40))
	loaded = null
	update_icon()

/obj/item/material/kitchen/utensil/attack(mob/living/carbon/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	if(!istype(M))
		return ..()

	if(stance != I_HELP)
		if(user.zone_sel.selecting == BP_HEAD || user.zone_sel.selecting == O_EYES)
			if(CLUMSY_HARM_CHANCE(user))
				M = user
			return eyestab(M,user)
		else
			return ..()

	if (loaded && reagents.total_volume > 0)
		reagents.trans_to_mob(M, reagents.total_volume, CHEM_INGEST)
		if(food_inserted_micros && food_inserted_micros.len)
			for(var/mob/living/F in food_inserted_micros)
				own_take_member(src, nameof(food_inserted_micros), F)
				if(!can_food_vore(M, F))
					F.forceMove(get_turf(src))
				else
					M.vore_selected.nom_atom(F)
		if(M == user)
			if(!M.can_eat(loaded))
				return ITEM_INTERACT_FAILURE
			act_message(user, M, others = span_bold("%U%") + " eats some of [loaded] with \the [src].")
		else
			act_message(user, M, others = span_warning("%U% begins to feed %T%!"))
			if(!M.can_force_feed(user, loaded))
				return ITEM_INTERACT_FAILURE
			task_timed(user, 5 SECONDS, target = M, receiver = src, on_done = PROC_REF(force_feed_done), done_args = list(M, user))
			return ITEM_INTERACT_SUCCESS
		play_sfx(src, SFX_ITEMS_EATFOOD, volume = rand(10,40))
		loaded = null
		update_icon()
		return ITEM_INTERACT_SUCCESS
	else
		to_chat(user, span_warning("You don't have anything on \the [src]."))	//if we have help intent and no food scooped up DON'T STAB OURSELVES WITH THE FORK
		return ITEM_INTERACT_FAILURE

/obj/item/material/kitchen/utensil/on_rag_wipe()
	. = ..()
	if(reagents.total_volume > 0)
		reagents.clear_reagents()
		cut_overlays()
	return

/obj/item/material/kitchen/utensil/container_resist(mob/living/M)
	if(food_inserted_micros)
		own_take_member(src, nameof(food_inserted_micros), M)
	if(isdisposalpacket(loc))
		M.forceMove(loc)
	else
		M.forceMove(get_turf(src))
	to_chat(M, span_warning("You climb off of \the [src]."))

/obj/item/material/kitchen/utensil/fork
	name = "fork"
	desc = "It's a fork. Sure is pointy."
	icon_state = "fork"
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE

/obj/item/material/kitchen/utensil/fork/plastic
	default_material = MAT_PLASTIC

/obj/item/material/kitchen/utensil/foon
	name = "foon"
	desc = "It's a foon. The forgotten cousin of the spork."
	icon_state = "foon"
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE

/obj/item/material/kitchen/utensil/foon/plastic
	default_material = MAT_PLASTIC

/obj/item/material/kitchen/utensil/spork
	name = "spork"
	desc = "It's a spork. The (un)holy merger of a spoon and fork."
	icon_state = "spork"
	sharp = TRUE
	edge = FALSE
	injury_kind = INJURY_PIERCE

/obj/item/material/kitchen/utensil/spork/plastic
	default_material = MAT_PLASTIC

/obj/item/material/kitchen/utensil/spoon
	name = "spoon"
	desc = "It's a spoon. You can see your own upside-down face in it."
	icon_state = "spoon"
	attack_verb = list("attacked", "poked")
	edge = FALSE
	sharp = FALSE
	injury_kind = INJURY_BLUNT
	force_divisor = 0.1 //2 when wielded with weight 20 (steel)

/obj/item/material/kitchen/utensil/spoon/plastic
	default_material = MAT_PLASTIC

/*
 * Knives
 */

/* From the time of Clowns. Commented out for posterity, and sanity.
/obj/item/material/knife/attack(target as mob, mob/living/user as mob)
	if (CLUMSY_HARM_CHANCE(user))
		to_chat(user, span_warning("You accidentally cut yourself with \the [src]."))
		user.injure(INJURY_CUT, 20, source = src)
		return
	return ..()
*/
/obj/item/material/knife/plastic
	default_material = MAT_PLASTIC

/*
 * Rolling Pins
 */

/obj/item/material/kitchen/rollingpin
	name = "rolling pin"
	desc = "Used to knock out the " + JOB_BARTENDER+ "."
	icon_state = "rolling_pin"
	attack_verb = list("bashed", "battered", "bludgeoned", "thrashed", "whacked")
	default_material = MAT_WOOD
	force_divisor = 0.7 // 10 when wielded with weight 15 (wood)
	dulled_divisor = 0.75	// Still a club
	thrown_force_divisor = 1 // as above
	drop_sound = SFX_ITEMS_DROP_WOODEN
	pickup_sound = SFX_ITEMS_PICKUP_WOODEN

/obj/item/material/kitchen/rollingpin/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(CLUMSY_HARM_CHANCE(user))
		to_chat(user, span_warning("\The [src] slips out of your hand and hits your head."))
		user.injure(INJURY_BLUNT, 10, BP_HEAD, src)
		user.status_at_least(STAT_PARALYZED, 2)
		return ITEM_INTERACT_SUCCESS
	return ..()

/obj/item/material/kitchen/utensil/ownership()
	. = ..()
	. += owns(nameof(food_inserted_micros), policy = OWN_SPILL, is_list = TRUE)
