/obj/machinery/appliance/mixer/cereal
	name = "cereal maker"
	desc = "Now with Dann O's available!"
	icon = 'icons/obj/cooking_machines.dmi'
	icon_state = "cereal_off"
	cook_type = "cerealized"
	on_icon = "cereal_on"
	off_icon = "cereal_off"
	appliancetype = CEREALMAKER
	var/datum/looping_sound/cerealmaker/cerealmaker_loop
	circuit = /obj/item/circuitboard/cerealmaker

	output_options = list(
		"Cereal" = /obj/item/reagent_containers/food/snacks/variable/cereal
	)

CAPABILITIES(/obj/machinery/appliance/mixer/cereal)
	owns_one(nameof(cerealmaker_loop), /datum/looping_sound/cerealmaker)

/obj/machinery/appliance/mixer/cereal/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(cerealmaker_loop), new /datum/looping_sound/cerealmaker(list(src), FALSE))


DECLARE_APPEARANCE_PROC(/obj/machinery/appliance/mixer/cereal, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/appliance/mixer/cereal/appearance_overlays()
	. = list()
	. += ..()

	if(!has_condition())
		icon_state = on_icon
		if(cerealmaker_loop)
			cerealmaker_loop.start(src)
	else
		icon_state = off_icon
		if(cerealmaker_loop)
			cerealmaker_loop.stop(src)

/obj/machinery/appliance/mixer/cereal/combination_cook(datum/cooking_item/CI)

	var/list/images = list()
	var/num = 0
	for(var/obj/item/I in CI.container())
		if (istype(I, /obj/item/reagent_containers/food/snacks/variable/cereal))
			//Images of cereal boxes on cereal boxes is dumb
			continue

		var/image/food_image = image(I.icon, I.icon_state)
		food_image.color = I.color
		food_image.add_overlay(I.overlays)
		food_image.transform *= 0.7 - (num * 0.05)
		food_image.pixel_x = rand(-2,2)
		food_image.pixel_y = rand(-3,5)

		if (!images[I.icon_state])
			images[I.icon_state] = food_image
			num++

		if (num > 3)
			continue

	var/obj/item/reagent_containers/food/snacks/result = ..()

	result.color = result.filling_color
	for (var/i in images)
		result.overlays += images[i]

EXTEND_INTERACTIONS(/obj/machinery/appliance/mixer/cereal, INTERACT_ITEM(null, PROC_REF(appliance_interaction_part_replace)))
