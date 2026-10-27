

/obj/item/reagent_containers/food/drinks/drinkingglass
	name = "glass"
	desc = "Your standard drinking glass."
	icon_state = "glass_empty"
	amount_per_transfer_from_this = 5
	max_transfer_amount = 30
	min_transfer_amount = 1
	volume = 30
	material_template = /datum/material_template/container
	material_total = 500

CAPABILITIES(/obj/item/reagent_containers/food/drinks/drinkingglass)
	configure(movable_motion(unacidable = TRUE))
	configure(item_handling(center_x = 16, center_y = 10))

/obj/item/reagent_containers/food/drinks/drinkingglass/on_reagent_change()
	if (!length(reagents?.reagent_list))
		set_icon_state("glass_empty")
		name = "glass"
		desc = "Your standard drinking glass."
		set_center_of_mass_x(16)
		set_center_of_mass_y(10)
		return
	var/datum/reagent/R = reagents.get_master_reagent()

	if(R.glass_icon_state)
		set_icon_state(R.glass_icon_state)
	else
		set_icon_state("glass_brown")

	if(R.glass_name)
		name = R.glass_name
	else
		name = "Glass of.. what?"

	if(R.glass_desc)
		desc = R.glass_desc
	else
		desc = "You can't really tell what this is."

	if(R.glass_center_of_mass_x || R.glass_center_of_mass_y)
		set_center_of_mass_x(R.glass_center_of_mass_x)
		set_center_of_mass_y(R.glass_center_of_mass_y)
	else
		set_center_of_mass_x(16)
		set_center_of_mass_y(10)

	if(R.price_tag)
		set_price_tag(R.price_tag)
	else
		set_price_tag(null)

/obj/item/reagent_containers/food/drinks/cup
	name = "coffee cup"
	desc = "The container of oriental luxuries."
	icon_state = "cup_empty"
	amount_per_transfer_from_this = 5
	volume = 30

CAPABILITIES(/obj/item/reagent_containers/food/drinks/cup)
	configure(item_handling(center_x = 16, center_y = 16))

/obj/item/reagent_containers/food/drinks/cup/on_reagent_change()
	..()
	if (!length(reagents?.reagent_list))
		set_icon_state("cup_empty")
		name = "coffee cup"
		desc = "The container of oriental luxuries."
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)
		return
	var/datum/reagent/R = reagents.get_master_reagent()

	if(R.cup_icon_state)
		set_icon_state(R.cup_icon_state)
	else
		set_icon_state("cup_brown")

	if(R.cup_name)
		var/prefix = " "
		for(var/datum/reagent/S in reagents.reagent_list)
			if(S.cup_prefix)
				var/current_prefix = prefix
				prefix = "[current_prefix][S.cup_prefix] "
		name = "cup of[prefix][R.cup_name]"
	else
		name = "Cup of.. what?"

	if(R.cup_desc)
		desc = R.cup_desc
	else
		desc = "You can't really tell what this is."

	if(R.cup_center_of_mass_x || R.cup_center_of_mass_y)
		set_center_of_mass_x(R.cup_center_of_mass_x)
		set_center_of_mass_y(R.cup_center_of_mass_y)
	else
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)

	if(R.price_tag)
		set_price_tag(R.price_tag)
	else
		set_price_tag(null)

// for /obj/machinery/vending/sovietsoda
CAPABILITIES(/obj/item/reagent_containers/food/drinks/drinkingglass/soda)
	configure(reagents(add = list(REAGENT_ID_SODAWATER = 50)))

CAPABILITIES(/obj/item/reagent_containers/food/drinks/drinkingglass/cola)
	configure(reagents(add = list(REAGENT_ID_COLA = 50)))

/obj/item/reagent_containers/food/drinks/drinkingglass/shotglass
	name = "shot glass"
	desc = "No glasses were shot in the making of this glass."
	icon_state = "shotglass"
	amount_per_transfer_from_this = 10
	volume = 10
	material_template = /datum/material_template/container
	material_total = 175

/obj/item/reagent_containers/food/drinks/drinkingglass/shotglass/on_reagent_change()
	name = "shot glass"

	if(!reagents.total_volume)
		return
	name += " of [reagents.get_master_reagent_name()]" //No matter what, the glass will tell you the reagent's name. Might be too abusable in the future.

/obj/item/reagent_containers/food/drinks/drinkingglass/shotglass/draw(datum/look/look)
	..()
	var/datum/reagents/R = reagents
	look.watch(R) // its level and colour are tracked on the holder: the filling follows them
	if(!R?.total_volume)
		return
	var/fill_state = "[icon_state]1"
	switch(R.total_volume)
		if(0 to 3)			fill_state = "[icon_state]1"
		if(4 to 7) 			fill_state = "[icon_state]5"
		if(8 to INFINITY)	fill_state = "[icon_state]12"
	look.overlay(look_overlay_image('icons/obj/reagentfillings.dmi', fill_state, color = R.tint))

/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask
	name = "fitness shaker"
	desc = "Big enough to contain enough protein to get perfectly swole. Don't mind the bits."
	icon_state = "fitness-cup_black"
	volume = 100
	MATERIAL_BULK(MAT_PLASTIC, 2000)

CAPABILITIES(/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask)
	rolls(nameof(icon_state), pick_one(list("fitness-cup_black", "fitness-cup_red", "fitness-cup_black")))

/// The shaker keeps its own sprite whatever it holds (it does not take the glass's reagent-driven name and icon); its filling is drawn.
/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask/on_reagent_change()
	return

/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask/draw(datum/look/look)
	..()
	var/datum/reagents/R = reagents
	look.watch(R) // its level and colour are tracked on the holder: the filling follows them
	if(!R?.total_volume)
		return
	var/fill_state = "fitness-cup10"
	switch(R.total_volume)
		if(0 to 10)			fill_state = "fitness-cup10"
		if(11 to 20)		fill_state = "fitness-cup20"
		if(21 to 29)		fill_state = "fitness-cup30"
		if(30 to 39)		fill_state = "fitness-cup40"
		if(40 to 49)		fill_state = "fitness-cup50"
		if(50 to 59)		fill_state = "fitness-cup60"
		if(60 to 69)		fill_state = "fitness-cup70"
		if(70 to 79)		fill_state = "fitness-cup80"
		if(80 to 89)		fill_state = "fitness-cup90"
		if(90 to INFINITY)	fill_state = "fitness-cup100"
	look.overlay(look_overlay_image('icons/obj/reagentfillings.dmi', fill_state, color = R.tint))

/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask/proteinshake
	name = "protein shake"

CAPABILITIES(/obj/item/reagent_containers/food/drinks/drinkingglass/fitnessflask/proteinshake)
	configure(reagents(add = list(REAGENT_ID_NUTRIMENT = 30, REAGENT_ID_IRON = 10, REAGENT_ID_PROTEIN = 15, REAGENT_ID_WATER = 45)))


////////////////Fancy coffee cups

/obj/item/reagent_containers/food/drinks/tall
	name = "tall cup"
	desc = "A larger coffee cup."
	icon_state = "tall_cup_empty"
	amount_per_transfer_from_this = 5
	volume = 40

CAPABILITIES(/obj/item/reagent_containers/food/drinks/tall)
	configure(item_handling(center_x = 16, center_y = 16))

/obj/item/reagent_containers/food/drinks/tall/on_reagent_change()
	if (!length(reagents?.reagent_list))
		set_icon_state("tall_cup_empty")
		name = "tall cup"
		desc = "A larger coffee cup."
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)
		return
	var/datum/reagent/R = reagents.get_master_reagent()

	if(R.cup_icon_state)
		set_icon_state("tall_[R.cup_icon_state]")
	else
		set_icon_state("tall_cup_brown")

	if(R.cup_name)
		var/prefix = " "
		for(var/datum/reagent/S in reagents.reagent_list)
			if(S.cup_prefix)
				var/current_prefix = prefix
				prefix = "[current_prefix][S.cup_prefix] "
		name = "tall[prefix][R.cup_name]"
	else
		name = "tall.. what?"

	if(R.cup_desc)
		desc = R.cup_desc
	else
		desc = "You can't really tell what this is."

	if(R.cup_center_of_mass_x || R.cup_center_of_mass_y)
		set_center_of_mass_x(R.cup_center_of_mass_x)
		set_center_of_mass_y(R.cup_center_of_mass_y)
	else
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)

	if(R.price_tag)
		set_price_tag(R.price_tag)
	else
		set_price_tag(null)

/obj/item/reagent_containers/food/drinks/grande
	name = "grande cup"
	desc = "A much taller coffee cup for people who really need their coffee."
	icon_state = "grande_cup_empty"
	amount_per_transfer_from_this = 5
	volume = 50

CAPABILITIES(/obj/item/reagent_containers/food/drinks/grande)
	configure(item_handling(center_x = 16, center_y = 16))

/obj/item/reagent_containers/food/drinks/grande/on_reagent_change()
	if (!length(reagents?.reagent_list))
		set_icon_state("grande_cup_empty")
		name = "grande cup"
		desc = "A much taller coffee cup for people who really need their coffee."
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)
		return
	var/datum/reagent/R = reagents.get_master_reagent()

	if(R.cup_icon_state)
		set_icon_state("grande_[R.cup_icon_state]")
	else
		set_icon_state("grande_cup_brown")

	if(R.cup_name)
		var/prefix = " "
		for(var/datum/reagent/S in reagents.reagent_list)
			if(S.cup_prefix)
				var/current_prefix = prefix
				prefix = "[current_prefix][S.cup_prefix] "
		name = "grande[prefix][R.cup_name]"
	else
		name = "grande.. what?"

	if(R.cup_desc)
		desc = R.cup_desc
	else
		desc = "You can't really tell what this is."

	if(R.cup_center_of_mass_x || R.cup_center_of_mass_y)
		set_center_of_mass_x(R.cup_center_of_mass_x)
		set_center_of_mass_y(R.cup_center_of_mass_y)
	else
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)

	if(R.price_tag)
		set_price_tag(R.price_tag)
	else
		set_price_tag(null)

/obj/item/reagent_containers/food/drinks/venti
	name = "venti cup"
	desc = "A huge coffee cup for people who literally cannot function without it."
	icon_state = "venti_cup_empty"
	amount_per_transfer_from_this = 5
	volume = 60

CAPABILITIES(/obj/item/reagent_containers/food/drinks/venti)
	configure(item_handling(center_x = 16, center_y = 16))

/obj/item/reagent_containers/food/drinks/venti/on_reagent_change()
	if (!length(reagents?.reagent_list))
		set_icon_state("venti_cup_empty")
		name = "venti cup"
		desc = "A huge coffee cup for people who literally cannot function without it."
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)
		return
	var/datum/reagent/R = reagents.get_master_reagent()

	if(R.cup_icon_state)
		set_icon_state("venti_[R.cup_icon_state]")
	else
		set_icon_state("venti_cup_brown")

	if(R.cup_name)
		var/prefix = " "
		for(var/datum/reagent/S in reagents.reagent_list)
			if(S.cup_prefix)
				var/current_prefix = prefix
				prefix = "[current_prefix][S.cup_prefix] "
		name = "venti[prefix][R.cup_name]"
	else
		name = "venti.. what?"

	if(R.cup_desc)
		desc = R.cup_desc
	else
		desc = "You can't really tell what this is."

	if(R.cup_center_of_mass_x || R.cup_center_of_mass_y)
		set_center_of_mass_x(R.cup_center_of_mass_x)
		set_center_of_mass_y(R.cup_center_of_mass_y)
	else
		set_center_of_mass_x(16)
		set_center_of_mass_y(16)

	if(R.price_tag)
		set_price_tag(R.price_tag)
	else
		set_price_tag(null)
