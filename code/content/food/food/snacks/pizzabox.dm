/obj/item/pizzabox
	name = "pizza box"
	desc = "A box suited for pizzas."
	icon = 'icons/obj/food.dmi'
	icon_state = "pizzabox1"

	var/open = 0 // Is the box open?
	var/ismessy = 0 // Fancy mess on the lid
	var/obj/item/reagent_containers/food/snacks/sliceable/pizza/pizza // Content pizza
	/// The pizza a box starts with (a subtype or a map edit sets it); made into `pizza` at init.
	var/pizza_type
	var/list/boxes // If the boxes are stacked, they come here
	var/boxtag = ""

// A pizza box: using it opens and shuts it (a stack stays shut); an empty hand takes the pizza out of an open one, or the top box off a stack held in the
// other hand; a box goes on a shut box up to five high, a pizza into an open one, and a pen writes on the tag of a shut one.
CAPABILITIES(/obj/item/pizzabox)
	configure(item_handling(center_x = 16, center_y = 6))
	owns_one(nameof(pizza), /obj/item/reagent_containers/food/snacks/sliceable/pizza, starts = nameof(pizza_type))
	ref_many(nameof(boxes), /obj/item/pizzabox)
	op("toggle", in_hand(), label("Open or close it"), needs(req(PROC_REF(not_stacked))), then(PROC_REF(toggled)))
	op("take_pizza", hand(), priority(OP_PRIORITY_PART + 1), when(req(PROC_REF(open_with_pizza))), label("Take the pizza"), then(PROC_REF(pizza_taken)))
	op("take_box", hand(), priority(OP_PRIORITY_PART), when(req(PROC_REF(stack_in_off_hand))), label("Take the top box"), then(PROC_REF(box_taken)))
	op("stack", item(/obj/item/pizzabox), priority(OP_PRIORITY_PART), when(PROC_REF(held_is_another)), label("Put it on top"),
		needs(req(PROC_REF(both_shut)), req(PROC_REF(stack_has_room))), then(PROC_REF(box_stacked)))
	op("put_pizza", item(/obj/item/reagent_containers/food/snacks/sliceable/pizza), priority(OP_PRIORITY_PART),
		needs(req(PROC_REF(is_open))), then(PROC_REF(pizza_put_in)))
	op("write_tag", item(/obj/item/pen), priority(OP_PRIORITY_PART), when(req(PROC_REF(is_shut))), label("Write on the tag"),
		asks(/datum/prompt/text, fields = list("question" = "Enter what you want to add to the tag:", "title" = "Write", "max_len" = 30)), then(PROC_REF(tag_written)))
	examine_line(PROC_REF(pizza_text))

MSG_DEF_SELF(pizzabox/stacked, "It is under a stack of boxes.")
MSG_DEF_SELF(pizzabox/close_first, "Close the box first!")
MSG_DEF_SELF(pizzabox/too_high, "The stack is too high!")
MSG_DEF_SELF(pizzabox/lid_shut, "You try to push it through the lid but it doesn't work!")

/// The box shows shut (a tag on the top box of a stack, its height) or open (the pizza in it, messy once it held one), and says what it holds.
/obj/item/pizzabox/draw(datum/look/look)
	..()
	var/stacked = length(boxes)
	var/obj/item/pizzabox/topbox = stacked ? boxes[stacked] : null
	look.watch(pizza)
	look.watch(topbox)

	// Set appropriate description
	if(open && pizza)
		look.identity(desc = "A box suited for pizzas. It appears to have a pizza inside.")
	else if(stacked > 0)
		var/stack_desc = "A pile of boxes suited for pizzas. There appears to be [stacked + 1] boxes in the pile."
		var/toptag = topbox.boxtag
		if(toptag != "")
			stack_desc = "[stack_desc] The box on top has a tag, it reads: '[toptag]'."
		look.identity(desc = stack_desc)
	else
		var/box_desc = "A box suited for pizzas."
		if(boxtag != "")
			box_desc = "[box_desc] The box has a tag, it reads: '[boxtag]'."
		look.identity(desc = box_desc)

	// Icon states and overlays
	if(open)
		look.state(ismessy ? "pizzabox_messy" : "pizzabox_open")
		if(pizza)
			look.overlay(look_overlay_image(pizza.icon, pizza.icon_state, pixel_y = -3))
		return

	var/tagged = stacked ? topbox.boxtag != "" : boxtag != ""
	if(tagged)
		look.overlay(look_overlay_image('icons/obj/food.dmi', "pizzabox_tag", pixel_y = stacked * 3))
	look.state("pizzabox[stacked + 1]")

/// Which pizza an open box holds, asked when it is examined (a name is not a tracked read, so it is not part of the look).
/obj/item/pizzabox/proc/pizza_text(datum/act/A)
	if(!open || !pizza)
		return null
	return "The pizza inside is a [read_once(pizza.name)]."

/// A stack stays shut.
/obj/item/pizzabox/proc/not_stacked(datum/act/op/A)
	return (length(boxes) == 0) ? null : MSG(pizzabox/stacked)

/obj/item/pizzabox/proc/toggled(datum/act/op/A)
	set_open(!open)
	if( open && pizza )
		set_ismessy(1)
	return OP_OK

/obj/item/pizzabox/proc/open_with_pizza(datum/act/op/A)
	return (open && !isnull(pizza) && isnull(A.held)) ? null : /datum/msg/req_failed

/obj/item/pizzabox/proc/is_open(datum/act/op/A)
	return (!!open) ? null : /datum/msg/pizzabox/lid_shut

/obj/item/pizzabox/proc/is_shut(datum/act/op/A)
	return (!open) ? null : /datum/msg/req_failed

/obj/item/pizzabox/proc/pizza_taken(datum/act/op/A)
	var/mob/user = A.actor
	user.put_in_hands( pizza )
	to_chat(user, span_warning("You take \the [src.pizza] out of \the [src]."))
	rel_take(src, nameof(pizza))
	return OP_OK

/// A stack of boxes, with the one it is in held in the other hand.
/obj/item/pizzabox/proc/stack_in_off_hand(datum/act/op/A)
	var/mob/user = A.actor
	return (length(boxes) > 0 && isnull(A.held) && user.get_inactive_hand() == src) ? null : /datum/msg/req_failed

/obj/item/pizzabox/proc/box_taken(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/pizzabox/box = boxes[length(boxes)]
	rel_remove(src, nameof(boxes), box)
	user.put_in_hands( box )
	to_chat(user, span_warning("You remove the topmost [src] from your hand."))
	return OP_OK

/// The held box is another one, not this one used in hand.
/obj/item/pizzabox/proc/held_is_another(datum/act/op/A)
	return A.held != src

/obj/item/pizzabox/proc/both_shut(datum/act/op/A)
	var/obj/item/pizzabox/box = A.held
	return (!box.open && !open) ? null : MSG(pizzabox/close_first)

/// The boxes to add, with the ones already in the pile, are no more than five.
/obj/item/pizzabox/proc/stack_has_room(datum/act/op/A)
	var/obj/item/pizzabox/box = A.held
	return ((length(boxes) + 1) + (1 + length(box.boxes)) <= 5) ? null : MSG(pizzabox/too_high)

/obj/item/pizzabox/proc/box_stacked(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/pizzabox/box = A.held
	// Make a list of all boxes to be added
	var/list/boxestoadd = list()
	boxestoadd += box
	for(var/obj/item/pizzabox/i in box.boxes)
		boxestoadd += i
	user.drop_item()
	box.forceMove(src)
	rel_clear(box, nameof(box.boxes)) // Clear the box boxes so we don't have boxes inside boxes. - Xzibit
	for(var/obj/item/pizzabox/stacked_box in boxestoadd)
		rel_add(src, nameof(boxes), stacked_box)
	to_chat(user, span_warning("You put \the [box] ontop of \the [src]!"))
	return OP_OK

/obj/item/pizzabox/proc/pizza_put_in(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(!move_into(src, nameof(src.pizza), I, user))
		return OP_REFUSED
	to_chat(user, span_warning("You put \the [I] in \the [src]!"))
	return OP_OK

/obj/item/pizzabox/proc/tag_written(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/obj/item/pizzabox/boxtotagto = src
	if(length(boxes) > 0)
		boxtotagto = boxes[length(boxes)]
	boxtotagto.set_boxtag(copytext("[boxtotagto.boxtag][R?.value]", 1, 30))
	return OP_OK

/obj/item/pizzabox/margherita
	pizza_type = /obj/item/reagent_containers/food/snacks/sliceable/pizza/margherita
	boxtag = "Margherita Deluxe"

/obj/item/pizzabox/vegetable
	pizza_type = /obj/item/reagent_containers/food/snacks/sliceable/pizza/vegetablepizza
	boxtag = "Gourmet Vegatable"

/obj/item/pizzabox/mushroom
	pizza_type = /obj/item/reagent_containers/food/snacks/sliceable/pizza/mushroompizza
	boxtag = "Mushroom Special"

/obj/item/pizzabox/meat
	pizza_type = /obj/item/reagent_containers/food/snacks/sliceable/pizza/meatpizza
	boxtag = "Meatlover's Supreme"

/obj/item/pizzabox/pineapple
	pizza_type = /obj/item/reagent_containers/food/snacks/sliceable/pizza/pineapple
	boxtag = "Hawaiian Sunrise"

/obj/item/pizzabox/old
	pizza_type = /obj/item/reagent_containers/food/snacks/sliceable/pizza/oldpizza
	boxtag = "Deluxe Gourmet"
