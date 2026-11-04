/obj/item/reagent_containers/food/snacks/ratpackramen
	name = "Big Noodle Package"
	desc = "A compression sealed package containing a fully cooked ramen meal. It comes with some seafood-and-rice based sides. Utensils included."
	icon = 'icons/obj/food.dmi'
	icon_state = "altevian_pack_ramen"
	package_open_state = "altevian_pack_ramen_standard-open"
	package_opening_state = "altevian_pack_ramen_standard-opening"
	package = TRUE
	trash = /obj/item/trash/ratpackramen/standard
	nutriment_amt = 2
	nutriment_desc = list("savory noodles" = 4)
	var/static/list/bowl_color_options = list("standard" = 6,
										"lacquer1" = 2,
										"lacquer2" = 2,
										"lacquer3" = 2,
										"fleet" = 6,
										"trans" = 3,
										"ace" = 3)
	var/randomize_bowl_color = TRUE
	/// The bowl colour it rolled (when randomize_bowl_color): its package states and trash follow it.
	var/bowl_color

CAPABILITIES(/obj/item/reagent_containers/food/snacks/ratpackramen)
	rolls(nameof(bowl_color), PROC_REF(roll_bowl_color), when = nameof(randomize_bowl_color))
	rolls(nameof(package_open_state), PROC_REF(bowl_open_state), when = nameof(bowl_color), from = list(nameof(bowl_color)))
	rolls(nameof(package_opening_state), PROC_REF(bowl_opening_state), when = nameof(bowl_color), from = list(nameof(bowl_color)))
	rolls(nameof(trash), PROC_REF(bowl_trash), when = nameof(bowl_color), from = list(nameof(bowl_color)))

/obj/item/reagent_containers/food/snacks/ratpackramen/proc/roll_bowl_color(datum/roller/R)
	return R.weighted(bowl_color_options)

/obj/item/reagent_containers/food/snacks/ratpackramen/proc/bowl_open_state(datum/roller/R)
	return "altevian_pack_ramen_[bowl_color]-open"

/obj/item/reagent_containers/food/snacks/ratpackramen/proc/bowl_opening_state(datum/roller/R)
	return "altevian_pack_ramen_[bowl_color]-opening"

/obj/item/reagent_containers/food/snacks/ratpackramen/proc/bowl_trash(datum/roller/R)
	return text2path("/obj/item/trash/ratpackramen/[bowl_color]")
