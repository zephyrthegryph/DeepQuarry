#define CELLS 8
#define CELLSIZE (32/CELLS)

////////////////////////////////////////////////////////////////////////////////
/// Food.
////////////////////////////////////////////////////////////////////////////////
/obj/item/reagent_containers/food
	max_transfer_amount = null
	volume = 50 //Sets the default container amount for all food items.
	description_info = "Food can use the Rename Food verb in the Object Tab to rename it."
	var/filling_color = "#FFFFFF" //Used by sandwiches and custom food.
	drop_sound = 'sound/items/drop/food.ogg'
	pickup_sound = 'sound/items/pickup/food.ogg'

	var/food_can_insert_micro = FALSE
	var/list/food_inserted_micros
	resistance_flags = FLAMMABLE

/obj/item/reagent_containers/food/proc/food_change_name_effect(mob/user, obj/item/held, datum/interaction/interaction)

	handle_name_change(user)

/obj/item/reagent_containers/food/proc/handle_name_change(mob/living/user)
	if(user.stat == DEAD || !(ishuman(user) || isrobot(user)))
		to_chat(user, span_warning("You can't cook!"))
		return
	var/_answer_k30 = rerun_prompt(user, "k30", list("kind" = "text", "message" = "What would you like to name \the [src]? Leave blank to reset.", "title" = "Food Naming", "default" = initial(name), "max_length" = MAX_NAME_LEN, "encode" = FALSE), PROC_REF(handle_name_change), args)
	if(isnull(_answer_k30))
		return
	var/n_name = sanitizeSafe(_answer_k30)
	if(!n_name)
		n_name = initial(name)

	name = n_name

/obj/item/reagent_containers/food/Initialize(mapload)
	. = ..()
	if ((center_of_mass_x || center_of_mass_y) && !pixel_x && !pixel_y)
		src.pixel_x = rand(-6.0, 6) //Randomizes postion
		src.pixel_y = rand(-6.0, 6)

// DECLARE here, EXTEND on every food subtype: this spec must stay last (it was the ..() end of their chains).
DECLARE_INTERACTIONS(/obj/item/reagent_containers/food, INTERACT_ITEM(null, PROC_REF(food_item)))

/// Old attackby: the changeling blood test, then the base item handling (FALSE).
/obj/item/reagent_containers/food/proc/food_item(mob/user, obj/item/W, datum/interaction/interaction)
	attempt_changeling_test(W,user)
	return FALSE

/obj/item/reagent_containers/food/afterattack(atom/A, mob/user, proximity, params)
	if((center_of_mass_x || center_of_mass_y) && proximity && params && istype(A, /obj/structure/table))
		//Places the item on a grid
		var/list/mouse_control = params2list(params)

		var/mouse_x = text2num(mouse_control["icon-x"])
		var/mouse_y = text2num(mouse_control["icon-y"])

		if(!isnum(mouse_x) || !isnum(mouse_y))
			return

		var/cell_x = max(0, min(CELLS-1, round(mouse_x/CELLSIZE)))
		var/cell_y = max(0, min(CELLS-1, round(mouse_y/CELLSIZE)))

		pixel_x = (CELLSIZE * (0.5 + cell_x)) - center_of_mass_x
		pixel_y = (CELLSIZE * (0.5 + cell_y)) - center_of_mass_y

/obj/item/reagent_containers/food/container_resist(mob/living/M)
	if(istype(M, /mob/living/voice)) return // Stops sentient food from astral projecting
	if(food_inserted_micros)
		food_inserted_micros -= M
	if(isdisposalpacket(loc))
		M.forceMove(loc)
	else
		M.forceMove(get_turf(src))
	to_chat(M, span_warning("You climb out of \the [src]."))

#undef CELLS
#undef CELLSIZE

/// Old object verbs.
EXTEND_INTERACTIONS(/obj/item/reagent_containers/food, \
	INTERACT_VERB("Rename Food", PROC_REF(food_change_name_effect)), \
)
