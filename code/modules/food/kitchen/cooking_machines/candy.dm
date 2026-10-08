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
	op("part_replace", item(/obj/item), label("Use"), then(PROC_REF(appliance_interaction_part_replace)))

/obj/machinery/appliance/mixer/candy/Initialize(mapload)
	. = ..()

	rel_set(src, nameof(candymaker_loop), new /datum/looping_sound/candymaker(list(src), FALSE))


/// The candy maker hums while it is on, beside the mixer's own sound.
/obj/machinery/appliance/mixer/candy/loop_sync(datum/act/A)
	..()
	if(!has_condition())
		candymaker_loop?.start(src)
	else
		candymaker_loop?.stop(src)

/obj/machinery/appliance/mixer/candy/change_product_appearance(obj/item/reagent_containers/food/snacks/product)
	food_color = get_random_colour(1)
	. = ..()

