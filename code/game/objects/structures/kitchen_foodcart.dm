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

/obj/structure/foodcart/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_item/foodcart_item,
		/datum/interaction/entry_hand/foodcart_hand,
	)
	..()

/// Old attackby: put a food item in the cart.
/datum/interaction/entry_item/foodcart_item
	id = "foodcart_item"
	name = "Use"
	held_type = /obj/item/reagent_containers/food
	effect = /obj/structure/foodcart/proc/interaction_item

/obj/structure/foodcart/proc/interaction_item(mob/user, obj/item/O, datum/interaction/interaction)
	if(!own_bring_in(src, nameof(contents), O, null, user, TRUE, null, FALSE))
		return TRUE
	update_icon()
	return TRUE

/// Old attack_hand: pick a food item out of the cart.
/datum/interaction/entry_hand/foodcart_hand
	id = "foodcart_hand"
	name = "Grab food"
	effect = /obj/structure/foodcart/proc/interaction_hand

/obj/structure/foodcart/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(contents_count(src))
		open_request(src, /datum/prompt/choice, PROC_REF(food_chosen), answerer = user, title = "Grab Choice", question = "What would you like to grab from the cart?", choices = contents, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE, timeout = 0)
	return TRUE

/obj/structure/foodcart/proc/food_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj/item/reagent_containers/food/choice = A.answer.value
	if(choice.loc == src)
		if(!user.canmove)
			return
		if(ishuman(user))
			if(!user.get_active_hand())
				user.put_in_hands(choice)
		else
			choice.forceMove(get_turf(src))
		update_icon()

/obj/structure/foodcart/draw(datum/look/look)
	..()
	if(contents_count(src) < 5)
		look.state("foodcart-[contents.len]")
	else
		look.state("foodcart-5")
