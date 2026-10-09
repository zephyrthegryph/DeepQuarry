// Customizable Foods //////////////////////////////////////////
#define INGREDIENT_LIMIT 20

/obj/item/reagent_containers/food/snacks/customizable
	icon = 'icons/obj/food_custom.dmi'
	bitesize = 2

	var/ingMax = 20000
	var/list/ingredients
	var/stackIngredients = 0
	var/fullyCustom = 0
	var/addTop = 0
	var/image/topping
	var/image/filling


/obj/item/reagent_containers/food/snacks/customizable/Initialize(mapload,ingredient)
	. = ..()
	topping = image(icon,,"[initial(icon_state)]_top")
	filling = image(icon,,"[initial(icon_state)]_filling")
	updateName()

// A food put in it is one more ingredient, up to a limit; a custom food cannot be put in another.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/customizable)
	configure(reagents(add = list(REAGENT_ID_NUTRIMENT = 3)))
	op("add", item(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), label("Add it"),
		needs(req_bool(PROC_REF(has_room_for), because = MSG(custom/stuffed)), req_bool(PROC_REF(not_custom_itself), because = PROC_REF(custom_refusal))), then(PROC_REF(ingredient_added)))
	owns_many(nameof(ingredients))

MSG_DEF_SELF(custom/stuffed, "That's already looking pretty stuffed.")
MSG_DEF_SELF(custom/slap, "You slap yourself on the back of the head for thinking that stacking plates is an interesting dish.")
MSG_DEF_SELF(custom/unique, "As uniquely original as that idea is, you can't figure out how to perform it.")
MSG_DEF_SELF(custom/recursive, "Sorry, no recursive food.")

/obj/item/reagent_containers/food/snacks/customizable/proc/has_room_for(datum/act/op/A)
	return length(contents) < ingMax && length(contents) < INGREDIENT_LIMIT // ALLOW(spatial,reads): what is in it is counted when a food is added; the click asks again

/obj/item/reagent_containers/food/snacks/customizable/proc/not_custom_itself(datum/act/op/A)
	return !istype(A.held, /obj/item/reagent_containers/food/snacks/customizable)

/// Two plates are a joke; anything else custom cannot be done.
/obj/item/reagent_containers/food/snacks/customizable/proc/custom_refusal(datum/act/op/A)
	var/obj/item/reagent_containers/food/snacks/customizable/SC = A.held
	return (fullyCustom && SC.fullyCustom) ? /datum/msg/custom/slap : /datum/msg/custom/unique

/obj/item/reagent_containers/food/snacks/customizable/proc/ingredient_added(datum/act/op/A)
	return add_ingredient(A.actor, A.held) ? OP_OK : OP_REFUSED

/// A food goes into it (when it can be let go of): what it holds mixes in, and the picture and the name follow.
/obj/item/reagent_containers/food/snacks/customizable/proc/add_ingredient(mob/user, obj/item/reagent_containers/food/snacks/S)
	if(!move_into(src, nameof(ingredients), S, user))
		return FALSE

	if(S.reagents)
		S.reagents.trans_to_holder(reagents,S.reagents.total_volume)

	if(src.addTop)
		cut_overlay(topping)
	if(!fullyCustom && !stackIngredients && LAZYLEN(overlays))
		cut_overlay(filling) //we can't directly modify the overlay, so we have to remove it and then add it again
		var/newcolor = S.filling_color != "#FFFFFF" ? S.filling_color : AverageColor(getFlatIcon(S, S.dir, 0), 1, 1)
		filling.color = BlendRGB(filling.color, newcolor, 1/ingredients.len)
		add_overlay(filling)
	else
		add_overlay(generateFilling(S))
	if(addTop)
		drawTopping()

	updateName()
	to_chat(user, span_notice("You add the [S.name] to the [src.name]."))
	return TRUE

/obj/item/reagent_containers/food/snacks/customizable/proc/generateFilling(obj/item/reagent_containers/food/snacks/S, params)
	var/image/I
	if(fullyCustom)
		var/icon/C = getFlatIcon(S, S.dir, 0)
		I = image(C)
		I.pixel_y = 12 * empty_Y_space(C)
	else
		I = filling
		if(istype(S) && S.filling_color != "#FFFFFF")
			I.color = S.filling_color
		else
			I.color = AverageColor(getFlatIcon(S, S.dir, 0), 1, 1)
		if(src.stackIngredients)
			I.pixel_y = length(src.ingredients) * 2
		else
			src.overlays.len = 0
	if(src.fullyCustom || src.stackIngredients)
		var/clicked_x = text2num(params2list(params)["icon-x"])
		if (isnull(clicked_x))
			I.pixel_x = 0
		else if (clicked_x < 9)
			I.pixel_x = -2 //this looks pretty shitty
		else if (clicked_x < 14)
			I.pixel_x = -1 //but hey
		else if (clicked_x < 19)
			I.pixel_x = 0  //it works
		else if (clicked_x < 25)
			I.pixel_x = 1
		else
			I.pixel_x = 2
	return I

/obj/item/reagent_containers/food/snacks/customizable/proc/updateName()
	var/i = 1
	var/new_name
	for(var/obj/item/S in ingredients)
		if(i == 1)
			new_name += "[S.name]"
		else if(i == length(src.ingredients))
			new_name += " and [S.name]"
		else
			new_name += ", [S.name]"
		i++
	new_name = "[new_name] [initial(name)]"
	if(length(new_name) >= 150)
		name = "something yummy"
	else
		name = new_name
	return new_name


/obj/item/reagent_containers/food/snacks/customizable/proc/drawTopping()
	var/image/I = topping
	I.pixel_y = (length(ingredients)+1)*2
	add_overlay(I)

// Sandwiches //////////////////////////////////////////////////

/obj/item/reagent_containers/food/snacks/customizable/sandwich
	name = "sandwich"
	desc = "A timeless classic."
	icon_state = "c_sandwich"
	stackIngredients = 1
	addTop = 0

// A slice of bread closes it.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/customizable/sandwich)
	op("top", item(/obj/item/reagent_containers/food/snacks/slice/bread), priority(OP_PRIORITY_PART + 1), when(req_bool(PROC_REF(open_topped))), label("Close it"), then(PROC_REF(topped)))

/obj/item/reagent_containers/food/snacks/customizable/sandwich/proc/open_topped(datum/act/op/A)
	return !addTop // ALLOW(reads): the food's own state is read when the click asks; it asks again at the end

/obj/item/reagent_containers/food/snacks/customizable/sandwich/proc/topped(datum/act/op/A)
	var/obj/item/I = A.held
	I.reagents.trans_to_holder(reagents,I.reagents.total_volume)
	consume(I, A.actor)
	addTop = 1
	drawTopping()
	return OP_OK

/obj/item/reagent_containers/food/snacks/customizable/burger
	name = "burger"
	desc = "The apex of space culinary achievement."
	icon_state = "c_burger"
	stackIngredients = 1
	addTop = 1

// Misc Subtypes ///////////////////////////////////////////////

/obj/item/reagent_containers/food/snacks/customizable/fullycustom
	name = "on a plate"
	desc = "A unique dish."
	icon_state = "fullycustom"
	fullyCustom = 1 //how the fuck do you forget to add this?
	ingMax = 1

/obj/item/reagent_containers/food/snacks/customizable/soup
	name = "soup"
	desc = "A bowl with liquid and... stuff in it."
	icon_state = "soup"
	trash = /obj/item/trash/bowl

/obj/item/reagent_containers/food/snacks/customizable/pizza
	name = "pan pizza"
	desc = "A personalized pan pizza meant for only one person."
	icon_state = "personal_pizza"

/obj/item/reagent_containers/food/snacks/customizable/pasta
	name = "spaghetti"
	desc = "Noodles. With stuff. Delicious."
	icon_state = "pasta_bot"

// Various Snacks //////////////////////////////////////////////

/// A food in the held hand starts a custom dish of `product` with `src` as its base (never one made of a custom food).
/obj/item/reagent_containers/food/snacks/proc/custom_base_for(datum/act/op/A, product)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/customizable/F = new product(get_turf(src), A.held)
	F.add_ingredient(user, A.held)
	consume(src, user)
	return OP_OK

/// The held thing is a food that is not itself custom.
/obj/item/reagent_containers/food/snacks/proc/holds_plain_food(datum/act/op/A)
	return !istype(A.held, /obj/item/reagent_containers/food/snacks/customizable)

// Bread + a food = a sandwich, bread + a shard = a sandwich with a shard in it.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/slice/bread)
	op("start_sandwich", item(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), needs(req_bool(PROC_REF(holds_plain_food), because = MSG(custom/recursive))), label("Make a sandwich"), then(PROC_REF(sandwich_started)))
	op("shard_sandwich", item(/obj/item/material/shard), priority(OP_PRIORITY_PART), label("Make a sandwich"), then(PROC_REF(shard_sandwich_made)))

/obj/item/reagent_containers/food/snacks/slice/bread/proc/sandwich_started(datum/act/op/A)
	return custom_base_for(A, /obj/item/reagent_containers/food/snacks/customizable/sandwich)

/obj/item/reagent_containers/food/snacks/slice/bread/proc/shard_sandwich_made(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/csandwich/S = new(get_turf(src))
	S.shard_hidden(A)
	consume(src, user)
	return OP_OK

// A bun + a meatball or a cutlet = a burger, + a sausage = a hot dog, + any other food = a custom burger.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/bun)
	op("add_meatball", item(/obj/item/reagent_containers/food/snacks/meatball), priority(OP_PRIORITY_PART + 1), label("Make a burger"), then(PROC_REF(burger_made)))
	op("add_cutlet", item(/obj/item/reagent_containers/food/snacks/cutlet), priority(OP_PRIORITY_PART + 1), label("Make a burger"), then(PROC_REF(burger_made)))
	op("add_sausage", item(/obj/item/reagent_containers/food/snacks/sausage), priority(OP_PRIORITY_PART + 1), label("Make a hot dog"), then(PROC_REF(hotdog_made)))
	op("start_burger", item(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), needs(req_bool(PROC_REF(holds_plain_food), because = MSG(custom/recursive))), label("Make a burger"), then(PROC_REF(burger_started)))

/obj/item/reagent_containers/food/snacks/bun/proc/burger_made(datum/act/op/A)
	return turn_into(A, /obj/item/reagent_containers/food/snacks/monkeyburger, "You make a burger.", uses_held = TRUE)

/obj/item/reagent_containers/food/snacks/bun/proc/hotdog_made(datum/act/op/A)
	return turn_into(A, /obj/item/reagent_containers/food/snacks/hotdog, "You make a hotdog.", uses_held = TRUE)

/obj/item/reagent_containers/food/snacks/bun/proc/burger_started(datum/act/op/A)
	return custom_base_for(A, /obj/item/reagent_containers/food/snacks/customizable/burger)

// A flat dough + a food = a pizza.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/sliceable/flatdough)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 1)))
	op("start_pizza", item(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), needs(req_bool(PROC_REF(holds_plain_food), because = MSG(custom/recursive))), label("Make a pizza"), then(PROC_REF(pizza_started)))

/obj/item/reagent_containers/food/snacks/sliceable/flatdough/proc/pizza_started(datum/act/op/A)
	return custom_base_for(A, /obj/item/reagent_containers/food/snacks/customizable/pizza)

// A spaghetti + a food = a pasta dish.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/spagetti)
	op("start_pasta", item(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), needs(req_bool(PROC_REF(holds_plain_food), because = MSG(custom/recursive))), label("Make a pasta dish"), then(PROC_REF(pasta_started)))

/obj/item/reagent_containers/food/snacks/spagetti/proc/pasta_started(datum/act/op/A)
	return custom_base_for(A, /obj/item/reagent_containers/food/snacks/customizable/pasta)

// Custom Meals ////////////////////////////////////////////////

/obj/item/trash/bowl
	name = "bowl"
	desc = "An empty bowl. Put some food in it to start making a soup."
	icon = 'icons/obj/food_custom.dmi'
	icon_state = "soup"

// A food put in a bowl starts a soup.
CAPABILITIES(/obj/item/trash/bowl)
	op("start_soup", item(/obj/item/reagent_containers/food/snacks), priority(OP_PRIORITY_PART), needs(req_bool(PROC_REF(holds_plain_food), because = MSG(custom/recursive))), label("Make a soup"), then(PROC_REF(soup_started)))

/obj/item/trash/bowl/proc/holds_plain_food(datum/act/op/A)
	return !istype(A.held, /obj/item/reagent_containers/food/snacks/customizable)

/obj/item/trash/bowl/proc/soup_started(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/food/snacks/customizable/F = new /obj/item/reagent_containers/food/snacks/customizable/soup(get_turf(src), A.held)
	F.add_ingredient(user, A.held)
	consume(src, user)
	return OP_OK

#undef INGREDIENT_LIMIT

