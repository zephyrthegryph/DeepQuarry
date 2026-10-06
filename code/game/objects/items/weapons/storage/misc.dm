/*
 * Donut Box
 */

GLOBAL_LIST_INIT(random_weighted_donuts, list(
	/obj/item/reagent_containers/food/snacks/donut/plain = 5,
	/obj/item/reagent_containers/food/snacks/donut/plain/jelly = 5,
	/obj/item/reagent_containers/food/snacks/donut/pink = 4,
	/obj/item/reagent_containers/food/snacks/donut/pink/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/purple = 4,
	/obj/item/reagent_containers/food/snacks/donut/purple/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/green = 4,
	/obj/item/reagent_containers/food/snacks/donut/green/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/beige = 4,
	/obj/item/reagent_containers/food/snacks/donut/beige/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/choc = 4,
	/obj/item/reagent_containers/food/snacks/donut/choc/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/blue = 4,
	/obj/item/reagent_containers/food/snacks/donut/blue/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/yellow = 4,
	/obj/item/reagent_containers/food/snacks/donut/yellow/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/olive = 4,
	/obj/item/reagent_containers/food/snacks/donut/olive/jelly = 4,
	/obj/item/reagent_containers/food/snacks/donut/homer = 3,
	/obj/item/reagent_containers/food/snacks/donut/homer/jelly = 3,
	/obj/item/reagent_containers/food/snacks/donut/choc_sprinkles = 3,
	/obj/item/reagent_containers/food/snacks/donut/choc_sprinkles/jelly = 3,
	/obj/item/reagent_containers/food/snacks/donut/chaos = 1
))

/obj/item/storage/box/donut
	icon = 'icons/obj/food_donuts.dmi'
	icon_state = "donutbox"
	name = "donut box"
	desc = "A box that holds tasty donuts, if you're lucky."
	center_of_mass_x = 16
	center_of_mass_y = 9
	max_storage_space = ITEMSIZE_COST_SMALL * 6
	foldable = /obj/item/stack/material/cardboard
	//starts_with = list(/obj/item/reagent_containers/food/snacks/donut/normal = 6)


CAPABILITIES(/obj/item/storage/box/donut)
	configure(storage(accepts = list(/obj/item/reagent_containers/food/snacks/donut)))

/obj/item/storage/box/donut/Initialize(mapload)
	if(!empty)
		for(var/i in 1 to 6)
			var/type_to_spawn = pickweight(GLOB.random_weighted_donuts)
			new type_to_spawn(src)
	. = ..()

/obj/item/storage/box/donut/draw(datum/look/look)
	. = ..()
	for(var/mutable_appearance/ma in donut_overlays())
		look.overlay(ma)

/// One overlay per donut inside, each three pixels along from the last.
/obj/item/storage/box/donut/proc/donut_overlays()
	. = list()
	var/x_offset = 0
	for(var/obj/item/reagent_containers/food/snacks/donut/D in held_things())
		var/mutable_appearance/ma = mutable_appearance(icon = icon, icon_state = D.overlay_state)
		ma.pixel_x = x_offset
		. += ma
		x_offset += 3

READS_AS(/obj/item/storage/box/donut/proc/donut_overlays, STORAGE_CONTENTS_KEY)

/obj/item/storage/box/donut/empty
	empty = TRUE

/obj/item/storage/box/wormcan
	icon = 'icons/obj/food.dmi'
	icon_state = "wormcan"
	name = "can of worms"
	desc = "You probably do want to open this can of worms."
	max_storage_space = ITEMSIZE_COST_TINY * 6
	starts_with = list(/obj/item/reagent_containers/food/snacks/worm = 6)


CAPABILITIES(/obj/item/storage/box/wormcan)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/food/snacks/wormsickly,
		/obj/item/reagent_containers/food/snacks/worm,
		/obj/item/reagent_containers/food/snacks/wormdeluxe)))

/obj/item/storage/box/wormcan/Initialize(mapload)
	. = ..()

/obj/item/storage/box/wormcan/draw(datum/look/look)
	. = ..()
	if(held_count() == 0)
		look.state("wormcan_empty")

/obj/item/storage/box/wormcan/sickly
	icon_state = "wormcan_sickly"
	name = "can of sickly worms"
	desc = "You probably don't want to open this can of worms."
	max_storage_space = ITEMSIZE_COST_TINY * 6
	starts_with = list(/obj/item/reagent_containers/food/snacks/wormsickly = 6)

/obj/item/storage/box/wormcan/sickly/draw(datum/look/look)
	. = ..()
	if(held_count() == 0)
		look.state("wormcan_empty_sickly")

/obj/item/storage/box/wormcan/deluxe
	icon_state = "wormcan_deluxe"
	name = "can of deluxe worms"
	desc = "You absolutely want to open this can of worms."
	max_storage_space = ITEMSIZE_COST_TINY * 6
	starts_with = list(/obj/item/reagent_containers/food/snacks/wormdeluxe = 6)

/obj/item/storage/box/wormcan/deluxe/draw(datum/look/look)
	. = ..()
	if(held_count() == 0)
		look.state("wormcan_empty_deluxe")
