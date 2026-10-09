/obj/item/reagent_containers/food/drinks/glass2/fitnessflask
	name = "fitness shaker"
	base_name = "shaker"
	desc = "Big enough to contain enough protein to get perfectly swole. Don't mind the bits."
	icon_state = "fitness-cup_black"
	base_icon = "fitness-cup"
	volume = 100
	MATERIAL_BULK(MAT_PLASTIC, 2000)
	filling_states = list(10,20,30,40,50,60,70,80)
	max_transfer_amount = 50
	rim_pos = null // no fruit slices
	var/lid_color = "black"
TRACKED(/obj/item/reagent_containers/food/drinks/glass2/fitnessflask, lid_color)

// ALLOW(init/INSTANCE_STATE): rolls its lid colour
/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/Initialize(mapload)
	. = ..()
	set_lid_color(pick("black", "red", "blue"))

/// The shaker is drawn with the lid it rolled.
/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/draw_contents(datum/look/look)
	..()
	look.state("[base_icon]_[lid_color]")

/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/proteinshake
	name = "protein shake"
	icon = 'icons/obj/drinks.dmi'
	icon_state = "protein_shake"
	base_icon = "protein_shake"
	desc = "NanoTrasen brand pre-done pre-workout mix. Also perfect for an empty stomach."

CAPABILITIES(/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/proteinshake)
	configure(reagents(add = list(REAGENT_ID_NUTRIMENT = 30, REAGENT_ID_IRON = 10, REAGENT_ID_PROTEIN = 35, REAGENT_ID_WATER = 25)))

/// A shake in its carton keeps the carton's sprite: nothing of the glass is drawn on it.
/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/proteinshake/draw_contents(datum/look/look)
	return


/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/proteanshake
	name = "protean shake"
	icon = 'icons/obj/drinks.dmi'
	icon_state = "protean_shake"
	base_icon = "protean_shake"
	desc = "A strangely unlabeled, unbranded pre-workout drink carton."

CAPABILITIES(/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/proteanshake)
	configure(reagents(add = list(REAGENT_ID_LIQUIDPROTEAN = 50, REAGENT_ID_NUTRIMENT = 50)))

/// A shake in its carton keeps the carton's sprite: nothing of the glass is drawn on it.
/obj/item/reagent_containers/food/drinks/glass2/fitnessflask/proteanshake/draw_contents(datum/look/look)
	return
