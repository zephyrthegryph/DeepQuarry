/obj/machinery/appliance/cooker/oven
	name = "oven"
	desc = "Cookies are ready, dear."
	icon = 'icons/obj/cooking_machines.dmi'
	icon_state = "ovenopen"
	cook_type = "baked"
	appliancetype = OVEN
	food_color = "#A34719"
	can_burn_food = TRUE
	var/datum/looping_sound/oven/oven_loop
	circuit = /obj/item/circuitboard/oven
	active_power_usage = 6 KILOWATTS
	heating_power = 6 KILOWATTS
	//Based on a double deck electric convection oven

	resistance = 2 KILOWATTS // Approx. 2 minutes to heat up.
	idle_power_usage = 2 KILOWATTS
	//uses ~30% power to stay warm
	optimal_power = 0.8 // Oven cooks .2 faster than the default speed.

	light_x = 3
	light_y = 4
	max_contents = 5
	container_type = /obj/item/reagent_containers/cooking_container/oven

	starts_off = TRUE


	tgui_id = "CookingOven"

	output_options = list(
		"Pizza" = /obj/item/reagent_containers/food/snacks/variable/pizza,
		"Bread" = /obj/item/reagent_containers/food/snacks/variable/bread,
		"Pie" = /obj/item/reagent_containers/food/snacks/variable/pie,
		"Cake" = /obj/item/reagent_containers/food/snacks/variable/cake,
		"Hot Pocket" = /obj/item/reagent_containers/food/snacks/variable/pocket,
		"Kebab" = /obj/item/reagent_containers/food/snacks/variable/kebab,
		"Waffles" = /obj/item/reagent_containers/food/snacks/variable/waffles,
		"Cookie" = /obj/item/reagent_containers/food/snacks/variable/cookie,
		"Donut" = /obj/item/reagent_containers/food/snacks/variable/donut,
		)

CAPABILITIES(/obj/machinery/appliance/cooker/oven)
	owns_one(nameof(oven_loop), /datum/looping_sound/oven)
	op("part_replace", item(/obj/item), label("Use"), then(PROC_REF(appliance_interaction_part_replace)))
	op("toggle_door_alt", hand(), ungated(), gesture(GESTURE_ALT), label("Toggle door"), then(PROC_REF(oven_interaction_toggle_door)))
	op("toggle_door", ui_act("toggle_door"), then(PROC_REF(ui_act_toggle_door)))

/obj/machinery/appliance/cooker/oven/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(oven_loop), new /datum/looping_sound/oven(list(src), FALSE))


/obj/machinery/appliance/cooker/oven/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["is_open"] = open
	return data

/obj/machinery/appliance/cooker/oven/proc/ui_act_toggle_door(datum/act/op/A)
	var/mob/user = A.actor
	try_toggle_door(user)
	return TRUE

DECLARE_APPEARANCE_PROC(/obj/machinery/appliance/cooker/oven, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/appliance/cooker/oven/appearance_overlays()
	. = list()
	if(!open)
		if(!has_condition())
			icon_state = "ovenclosed_on"
			if(cooking == TRUE)
				icon_state = "ovenclosed_cooking"
				if(oven_loop)
					oven_loop.start(src)
			else
				icon_state = "ovenclosed_on"
				if(oven_loop)
					oven_loop.stop(src)
		else
			icon_state = "ovenclosed_off"
			if(oven_loop)
				oven_loop.stop(src)
	else
		icon_state = "ovenopen"
		if(oven_loop)
			oven_loop.stop(src)
	. += ..()

/// Old click_alt.
/obj/machinery/appliance/cooker/oven/proc/oven_interaction_toggle_door(datum/act/op/A)
	var/mob/user = A.actor
	try_toggle_door(user)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	return OP_OK

/// Start closed just so people don't try to preheat with it open, lol.
OM_FIELD(/obj/machinery/appliance/cooker/oven, open, FALSE, CHANGE_MACHINE_SETTINGS)

/// With the door open it doesn't step at all (the door's heat loss is the body's coupling).
/obj/machinery/appliance/cooker/oven/cooker_needs_step()
	if(open)
		return FALSE
	return ..()

/obj/machinery/appliance/cooker/oven/proc/try_toggle_door(mob/user)
	if(!isliving(user) || isAI(user))
		return

	if(!user.IsAdvancedToolUser())
		to_chat(user, span_notice("You lack the dexterity to do that."))
		return

	if(!Adjacent(user))
		to_chat(user, span_notice("You can't reach the [src] from there, get closer!"))
		return

	if(open)
		set_open(FALSE)
		heat_recouple()
		set_cooking(TRUE)
	else
		set_open(TRUE)
		heat_recouple()
		//When the oven door is opened, heat is lost MUCH faster and you stop cooking (because the door is open)
		set_cooking(FALSE)

	play_sfx(src, SFX_MACHINES_HATCH_OPEN, volume = 20)
	to_chat(user, span_notice("You [open? "open":"close"] the oven door"))
	update_icon()

/obj/machinery/appliance/cooker/oven/proc/manip(obj/item/I)
	// check if someone's trying to manipulate the machine

	if(I.has_tool_quality(TOOL_CROWBAR) || I.has_tool_quality(TOOL_SCREWDRIVER) || istype(I, /obj/item/storage/part_replacer))
		return TRUE
	else
		return FALSE

/obj/machinery/appliance/cooker/oven/can_insert(obj/item/I, mob/user)
	if(!open && !manip(I))
		to_chat(user, span_warning("You can't put anything in while the door is closed!"))
		return 0

	else
		return ..()

/// An open door loses heat to the room eight times faster (the body's coupling).
/obj/machinery/appliance/cooker/oven/cooker_conductance()
	return open ? COOKER_CONDUCTANCE * 8 : COOKER_CONDUCTANCE

/obj/machinery/appliance/cooker/oven/can_remove_items(mob/user, show_warning = TRUE)
	if(!open)
		if(show_warning)
			to_chat(user, span_warning("You can't take anything out while the door is closed!"))
		return 0

	else
		return ..()

//Oven has lots of recipes and combine options. The chance for interference is high, so
//If a combine target is set the oven will do it instead of checking recipes
/obj/machinery/appliance/cooker/oven/finish_cooking(datum/cooking_item/CI)
	if(CI.combine_target)
		CI.result_type = 3//Combination type. We're making something out of our ingredients
		visible_message(span_infoplain(span_bold("\The [src]") + " pings!"))
		combination_cook(CI)
		return
	else
		..()


