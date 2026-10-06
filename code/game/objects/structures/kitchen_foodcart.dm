/obj/structure/foodcart
	name = "Foodcart"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "foodcart-0"
	desc = "The ultimate in food transport! When opened you notice two compartments with odd blue glows to them. One feels very warm, while the other is very cold."
	anchored = FALSE
	opacity = 0
	density = TRUE

/obj/structure/foodcart/Initialize(mapload)
	. = ..()
	for(var/obj/item/I in contents_of(loc))
		if(istype(I, /obj/item/reagent_containers/food))
			I.forceMove(src)
	update_icon()

CAPABILITIES(/obj/structure/foodcart)
	op("stock", item(/obj/item/reagent_containers/food), label("Use"), then(PROC_REF(interaction_item)))
	op("grab_food", hand(), label("Grab food"), when(req_full(nameof(contents))),
		asks(/datum/prompt/choice, fields = list("title" = "Grab Choice", "question" = "What would you like to grab from the cart?", "choices" = computed(PROC_REF(food_choices)), "timeout" = 0)),
		then(PROC_REF(food_chosen)))

/// Food in hand goes into the cart.
/obj/structure/foodcart/proc/interaction_item(datum/act/op/A)
	if(!own_bring_in(src, nameof(contents), A.held, null, A.actor, TRUE, null, FALSE))
		return OP_OK
	update_icon()
	return OP_OK

/// What the cart holds, to pick from.
/obj/structure/foodcart/proc/food_choices(datum/act/A)
	return contents_of(src)

/// The picked food comes out into the hand (or onto the floor).
/obj/structure/foodcart/proc/food_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R)
		return OP_OK
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/choice = R.value
	if(choice.loc == src)
		if(!user.canmove)
			return OP_OK
		if(ishuman(user))
			if(!user.get_active_hand())
				user.put_in_hands(choice)
		else
			choice.forceMove(get_turf(src))
		update_icon()
	return OP_OK

/obj/structure/foodcart/draw(datum/look/look)
	..()
	if(contents_count(src) < 5)
		look.state("foodcart-[contents.len]")
	else
		look.state("foodcart-5")
