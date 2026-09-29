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

DECLARE_REAGENTS(/obj/item/reagent_containers/food/snacks/customizable, null, list(REAGENT_ID_NUTRIMENT = 3))

/obj/item/reagent_containers/food/snacks/customizable/Initialize(mapload,ingredient)
	. = ..()
	topping = image(icon,,"[initial(icon_state)]_top")
	filling = image(icon,,"[initial(icon_state)]_filling")
	updateName()

EXTEND_INTERACTIONS(/obj/item/reagent_containers/food/snacks/customizable, INTERACT_ITEM(null, PROC_REF(customizable_item)))

/// Old attackby. FALSE falls to the snack handling, as the old ..() did.
/obj/item/reagent_containers/food/snacks/customizable/proc/customizable_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I,/obj/item/reagent_containers/food/snacks))
		if((contents_count(src) >= ingMax) || (contents_count(src) >= INGREDIENT_LIMIT))
			to_chat(user, span_warning("That's already looking pretty stuffed."))
			return INTERACTION_HANDLED_PASS

		var/obj/item/reagent_containers/food/snacks/S = I
		if(istype(S,/obj/item/reagent_containers/food/snacks/customizable))
			var/obj/item/reagent_containers/food/snacks/customizable/SC = S
			if(fullyCustom && SC.fullyCustom)
				to_chat(user, span_warning("You slap yourself on the back of the head for thinking that stacking plates is an interesting dish."))
				return INTERACTION_HANDLED_PASS
		if(istype(I, /obj/item/reagent_containers/food/snacks/customizable))
			to_chat(user, span_warning("As uniquely original as that idea is, you can't figure out how to perform it."))
			return INTERACTION_HANDLED_PASS
		/*if(!user.drop_item())
			to_chat(user, span_warning("\The [I] is stuck to your hands!"))
			return*/
		user.drop_item()
		I.forceMove(src)

		if(S.reagents)
			S.reagents.trans_to_holder(reagents,S.reagents.total_volume)

		own_add(src, nameof(ingredients), S)

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
		to_chat(user, span_notice("You add the [I.name] to the [src.name]."))
		return INTERACTION_HANDLED_PASS
	return FALSE

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

EXTEND_INTERACTIONS(/obj/item/reagent_containers/food/snacks/customizable/sandwich, INTERACT_ITEM(null, PROC_REF(custom_sandwich_item)))

/// Old attackby. FALSE falls to the customizable handling, as the old ..() did.
/obj/item/reagent_containers/food/snacks/customizable/sandwich/proc/custom_sandwich_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I,/obj/item/reagent_containers/food/snacks/slice/bread) && !addTop)
		I.reagents.trans_to_holder(reagents,I.reagents.total_volume)
		consume(I, user)
		addTop = 1
		src.drawTopping()
		return INTERACTION_HANDLED_PASS
	return FALSE

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

EXTEND_INTERACTIONS(/obj/item/reagent_containers/food/snacks/slice/bread, INTERACT_ITEM(null, PROC_REF(bread_slice_item)))

/// Old attackby: this file's override plus the sandwich.dm one it reached through ..() (shard -> sandwich), merged.
/// FALSE falls to the snack handling, as the old chain did.
/obj/item/reagent_containers/food/snacks/slice/bread/proc/bread_slice_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I,/obj/item/reagent_containers/food/snacks))
		if(istype(I, /obj/item/reagent_containers/food/snacks/customizable))
			to_chat(user, span_warning("Sorry, no recursive food."))
			return INTERACTION_HANDLED_PASS
		var/obj/F = new/obj/item/reagent_containers/food/snacks/customizable/sandwich(get_turf(src),I) //boy ain't this a mouthful
		F.attackby(I, user)
		consume(src, user)
		return INTERACTION_HANDLED_PASS
	if(istype(I,/obj/item/material/shard))
		var/obj/item/reagent_containers/food/snacks/csandwich/S = new(get_turf(src))
		S.attackby(I,user)
		consume(src, user)
		return INTERACTION_HANDLED_PASS
	return FALSE

EXTEND_INTERACTIONS(/obj/item/reagent_containers/food/snacks/bun, INTERACT_ITEM(null, PROC_REF(bun_item)))

/// Old attackby. Its ..() for a non-snack reached an older snacks.dm override whose recipes were all
/// snack-only and which never called its own parent, so every item is answered here.
/obj/item/reagent_containers/food/snacks/bun/proc/bun_item(mob/user, obj/item/I, datum/interaction/interaction)
	// Bun + meatball = burger
	if(istype(I,/obj/item/reagent_containers/food/snacks/meatball))
		new /obj/item/reagent_containers/food/snacks/monkeyburger(src)
		to_chat(user, "You make a burger.")
		consume(I, user)
		consume(src, user)

	// Bun + cutlet = hamburger
	else if(istype(I, /obj/item/reagent_containers/food/snacks/cutlet))
		new /obj/item/reagent_containers/food/snacks/monkeyburger(src)
		to_chat(user, "You make a burger.")
		consume(I, user)
		consume(src, user)

	// Bun + sausage = hotdog
	else if(istype(I, /obj/item/reagent_containers/food/snacks/sausage))
		new /obj/item/reagent_containers/food/snacks/hotdog(src)
		to_chat(user, "You make a hotdog.")
		consume(I, user)
		consume(src, user)

	if(istype(I,/obj/item/reagent_containers/food/snacks))
		if(istype(I, /obj/item/reagent_containers/food/snacks/customizable))
			to_chat(user, span_warning("Sorry, no recursive food."))
			return
		var/obj/F = new/obj/item/reagent_containers/food/snacks/customizable/burger(get_turf(src),I)
		F.attackby(I, user)
		consume(src, user)
	return INTERACTION_HANDLED_PASS

EXTEND_INTERACTIONS(/obj/item/reagent_containers/food/snacks/sliceable/flatdough, INTERACT_ITEM(null, PROC_REF(flatdough_item)))

/// Old attackby. FALSE falls to the snack handling, as the old ..() did.
/obj/item/reagent_containers/food/snacks/sliceable/flatdough/proc/flatdough_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/reagent_containers/food/snacks))
		if(istype(I, /obj/item/reagent_containers/food/snacks/customizable))
			to_chat(user, span_warning("Sorry, no recursive food."))
			return INTERACTION_HANDLED_PASS
		var/obj/F = new/obj/item/reagent_containers/food/snacks/customizable/pizza(get_turf(src),I)
		F.attackby(I, user)
		consume(src, user)
		return INTERACTION_HANDLED_PASS
	return FALSE

EXTEND_INTERACTIONS(/obj/item/reagent_containers/food/snacks/spagetti, INTERACT_ITEM(null, PROC_REF(spagetti_item)))

/// Old attackby. FALSE falls to the snack handling, as the old ..() did.
/obj/item/reagent_containers/food/snacks/spagetti/proc/spagetti_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I, /obj/item/reagent_containers/food/snacks))
		if(istype(I, /obj/item/reagent_containers/food/snacks/customizable))
			to_chat(user, span_warning("Sorry, no recursive food."))
			return INTERACTION_HANDLED_PASS
		var/obj/F = new/obj/item/reagent_containers/food/snacks/customizable/pasta(get_turf(src),I)
		F.attackby(I, user)
		consume(src, user)
		return INTERACTION_HANDLED_PASS
	return FALSE

// Custom Meals ////////////////////////////////////////////////

/obj/item/trash/bowl
	name = "bowl"
	desc = "An empty bowl. Put some food in it to start making a soup."
	icon = 'icons/obj/food_custom.dmi'
	icon_state = "soup"

DECLARE_INTERACTIONS(/obj/item/trash/bowl, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/trash/bowl/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(istype(I,/obj/item/reagent_containers/food/snacks))
		if(istype(I, /obj/item/reagent_containers/food/snacks/customizable))
			to_chat(user, span_warning("Sorry, no recursive food."))
			return INTERACTION_HANDLED_PASS
		var/obj/F = new/obj/item/reagent_containers/food/snacks/customizable/soup(get_turf(src),I)
		F.attackby(I, user)
		consume(src, user)
	else
		return FALSE
	return INTERACTION_HANDLED_PASS

#undef INGREDIENT_LIMIT

