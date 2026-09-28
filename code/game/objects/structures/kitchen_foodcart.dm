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
	for(var/obj/item/I in loc)
		if(istype(I, /obj/item/reagent_containers/food))
			I.loc = src
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
	user.drop_item()
	O.loc = src
	update_icon()
	return TRUE

/// Old attack_hand: pick a food item out of the cart.
/datum/interaction/entry_hand/foodcart_hand
	id = "foodcart_hand"
	name = "Grab food"
	effect = /obj/structure/foodcart/proc/interaction_hand

/obj/structure/foodcart/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(contents.len)
		om_ask(user, /datum/om/prompt/choice/foodcart, PROC_REF(food_chosen), choices = contents)
	return TRUE

/datum/om/prompt/choice/foodcart
	title = "Grab Choice"
	message = "What would you like to grab from the cart?"
	ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE

/obj/structure/foodcart/proc/food_chosen(datum/om/prompt/choice/foodcart/ask)
	var/mob/user = ask.answerer
	var/obj/item/reagent_containers/food/choice = ask.choice
	if(choice.loc == src)
		if(!user.canmove)
			return
		if(ishuman(user))
			if(!user.get_active_hand())
				user.put_in_hands(choice)
		else
			choice.loc = get_turf(src)
		update_icon()

/obj/structure/foodcart/update_icon()
	if(contents.len < 5)
		icon_state = "foodcart-[contents.len]"
	else
		icon_state = "foodcart-5"
