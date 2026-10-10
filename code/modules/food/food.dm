////////////////////////////////////////////////////////////////////////////////
/// Food.
////////////////////////////////////////////////////////////////////////////////
/obj/item/reagent_containers/food
	max_transfer_amount = null
	volume = 50 //Sets the default container amount for all food items.
	var/filling_color = "#FFFFFF" //Used by sandwiches and custom food.
	drop_sound = SFX_ITEMS_DROP_FOOD
	pickup_sound = SFX_ITEMS_PICKUP_FOOD

	var/food_can_insert_micro = FALSE
	var/list/food_inserted_micros
	resistance_flags = FLAMMABLE

// What every food has: a hot thing held over an open one with blood in it tests the blood, anyone who can cook gives it a name, and a tiny person or a mouse
// in a holder is stuffed into it (when it takes them: food_can_insert_micro and stuffing_refusal()). Whoever is stuffed in is in its contents, and drops
// out when it is destroyed.
CAPABILITIES(/obj/item/reagent_containers/food)
	owns_many(nameof(food_inserted_micros), on_destroy = ON_DESTROY_SPILL)
	op("blood_test", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), when(req_bool(TYPE_PROC_REF(/obj/item/reagent_containers, blood_test_fits))), label("Test the blood"),
		then(TYPE_PROC_REF(/obj/item/reagent_containers, blood_tested)))
	op("rename", menu(), label("Rename food"), needs(req_bool(PROC_REF(can_cook), because = MSG(food/cannot_cook))),
		asks(/datum/prompt/text, fields = list("question" = computed(PROC_REF(rename_question)), "title" = "Food Naming", "default" = computed(PROC_REF(rename_default)), "max_len" = MAX_NAME_LEN)),
		then(PROC_REF(renamed)))
	op("climb_in", item(/mob/living), gesture(GESTURE_DRAG), by(0), when(req_bool(PROC_REF(small_self_drag))), label("Climb in"), then(PROC_REF(climbed_in)))
	op("stuff", item(/obj/item/holder), priority(OP_PRIORITY_PART), when(req_bool(PROC_REF(takes_micro))), label("Put in"),
		needs(req_bool(PROC_REF(stuffing_free), because = MSG(food/closed_to_micros))), then(PROC_REF(micro_stuffed)))

MSG_DEF_SELF(food/cannot_cook, "You can't cook!")
MSG_DEF_SELF(food/closed_to_micros, "You cannot stuff anything into it without opening it first.")

/// Anyone alive who has hands for it, or a robot, can give a food a name.
/obj/item/reagent_containers/food/proc/can_cook(datum/act/op/A)
	var/mob/user = A.actor
	return user.stat != DEAD && (ishuman(user) || isrobot(user))

/obj/item/reagent_containers/food/proc/rename_question(datum/act/op/A)
	return "What would you like to name \the [src]? Leave blank to reset."

/obj/item/reagent_containers/food/proc/rename_default(datum/act/op/A)
	return initial(name)

/// The name that was given, or the original one when it was left blank.
/obj/item/reagent_containers/food/proc/renamed(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/n_name = sanitizeSafe("[R?.value]")
	if(!n_name)
		n_name = initial(name)
	name = n_name
	return OP_OK

/// The held holder carries a tiny person or a mouse, and this food takes them.
/obj/item/reagent_containers/food/proc/takes_micro(datum/act/op/A)
	return food_can_insert_micro && (istype(A.held, /obj/item/holder/micro) || istype(A.held, /obj/item/holder/mouse))

/// Whether a micro may be put in now: a food that is shut (a wrapper, a lid) does not take them.
/obj/item/reagent_containers/food/proc/stuffing_free(datum/act/op/A)
	return TRUE

/// What is said when whoever is stuffed in is put in: the one stuffing, and the one stuffed.
/obj/item/reagent_containers/food/proc/micro_stuffed_messages(mob/user, mob/living/micro)
	to_chat(user, "Stuffed [micro] into \the [src].")
	balloon_alert(user, "stuffs [micro] into \the [src].")
	to_chat(micro, span_warning("[user] stuffs you into \the [src]."))

/// The micro in the held holder goes into the food (out of the holder, and the holder is used up).
/obj/item/reagent_containers/food/proc/micro_stuffed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/holder/holder = A.held
	var/mob/living/living_mob = holder.held_mob
	move_into(src, nameof(src.food_inserted_micros), living_mob, user) // out of the holder
	rel_clear(holder, nameof(holder.held_mob))
	consume(holder, user)
	micro_stuffed_messages(user, living_mob)
	return OP_OK

// ALLOW(init/INSTANCE_STATE): rolls its pixel offset when it has a centre of mass and no map offset
/obj/item/reagent_containers/food/Initialize(mapload)
	. = ..()
	if ((center_of_mass_x || center_of_mass_y) && !pixel_x && !pixel_y)
		src.pixel_x = rand(-6.0, 6) //Randomizes postion
		src.pixel_y = rand(-6.0, 6)

/obj/item/reagent_containers/food/container_resist(mob/living/M)
	if(istype(M, /mob/living/voice)) return // Stops sentient food from astral projecting
	if(food_inserted_micros)
		own_take_member(src, nameof(food_inserted_micros), M)
	if(isdisposalpacket(loc))
		M.forceMove(loc)
	else
		M.forceMove(get_turf(src))
	to_chat(M, span_warning("You climb out of \the [src]."))

/// A tiny person who drags themselves onto the food.
/obj/item/reagent_containers/food/proc/small_self_drag(datum/act/op/A)
	var/mob/living/user = A.actor
	return istype(user) && A.held == user && food_can_insert_micro && user.get_effective_size(TRUE) <= 0.50

/// They climb in.
/obj/item/reagent_containers/food/proc/climbed_in(datum/act/op/A)
	var/mob/living/user = A.actor
	move_into(src, nameof(src.food_inserted_micros), user, user)
	to_chat(user, span_warning("You climb into \the [src]."))
	return OP_OK
