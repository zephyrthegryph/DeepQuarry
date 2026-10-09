/obj/machinery/appliance/cooker/grill
	name = "grill"
	desc = "Backyard grilling, IN SPACE."
	icon_state = "grill_off"
	cook_type = "grilled"
	appliancetype = GRILL
	food_color = "#A34719"
	on_icon = "grill_on"
	off_icon = "grill_off"
	can_burn_food = TRUE
	var/datum/looping_sound/grill/grill_loop
	circuit = /obj/item/circuitboard/grill
	active_power_usage = 4 KILOWATTS
	heating_power = 4000
	idle_power_usage = 2 KILOWATTS

	optimal_power = 1.2 // Things on the grill cook .6 faster - this is now the fastest appliance to heat and to cook on. BURGERS GO SIZZLE.

	starts_off = TRUE

	// Grill is faster to heat and setup than the rest.
	optimal_temp = 120 + T0C
	min_temp = 60 + T0C
	resistance = 2 KILOWATTS // Very fast to heat up.

	max_contents = 3 // Arbitrary number, 3 grill 'racks'
	container_type = /obj/item/reagent_containers/cooking_container/grill

	tgui_id = "CookingGrill"

CAPABILITIES(/obj/machinery/appliance/cooker/grill)
	owns_one(nameof(grill_loop), /datum/looping_sound/grill)
	op("part_replace", item(/obj/item), label("Use"), then(PROC_REF(appliance_interaction_part_replace)))

/obj/machinery/appliance/cooker/grill/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(grill_loop), new /datum/looping_sound/grill(list(src), FALSE))


/// A grill shows no status light, only whether it is on. // TODO: Cooking icon
/obj/machinery/appliance/cooker/grill/draw(datum/look/look)
	..()
	look.state(has_condition() ? off_icon : on_icon)

/obj/machinery/appliance/cooker/grill/draw_lights(datum/look/look)
	return

/// The grill sizzles while it cooks.
/obj/machinery/appliance/cooker/grill/loop_sync(datum/act/A)
	if(!has_condition() && cooking == TRUE)
		grill_loop?.start(src)
	else
		grill_loop?.stop(src)

