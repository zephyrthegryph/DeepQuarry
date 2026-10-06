/obj/machinery/appliance/mixer/candy
	name = "candy machine"
	desc = "Get yer candied cheese wheels here!"
	icon_state = "mixer_off"
	off_icon = "mixer_off"
	on_icon = "mixer_on"
	cook_type = "candied"
	appliancetype = CANDYMAKER
	var/datum/looping_sound/candymaker/candymaker_loop
	circuit = /obj/item/circuitboard/candymachine
	cooking_coeff = 1.0 // Original Value 0.6

	output_options = list(
		"Jawbreaker" = /obj/item/reagent_containers/food/snacks/variable/jawbreaker,
		"Candy Bar" = /obj/item/reagent_containers/food/snacks/variable/candybar,
		"Sucker" = /obj/item/reagent_containers/food/snacks/variable/sucker,
		"Jelly" = /obj/item/reagent_containers/food/snacks/variable/jelly
		)

CAPABILITIES(/obj/machinery/appliance/mixer/candy)
	owns_one(nameof(candymaker_loop), /datum/looping_sound/candymaker)

/obj/machinery/appliance/mixer/candy/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(candymaker_loop), new /datum/looping_sound/candymaker(list(src), FALSE))


DECLARE_APPEARANCE_PROC(/obj/machinery/appliance/mixer/candy, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/appliance/mixer/candy/appearance_overlays()
	. = list()
	. += ..()

	if(!has_condition())
		icon_state = on_icon
		if(candymaker_loop)
			candymaker_loop.start(src)
	else
		icon_state = off_icon
		if(candymaker_loop)
			candymaker_loop.stop(src)

/obj/machinery/appliance/mixer/candy/change_product_appearance(obj/item/reagent_containers/food/snacks/product)
	food_color = get_random_colour(1)
	. = ..()

EXTEND_INTERACTIONS(/obj/machinery/appliance/mixer/candy, INTERACT_ITEM(null, PROC_REF(appliance_interaction_part_replace)))
