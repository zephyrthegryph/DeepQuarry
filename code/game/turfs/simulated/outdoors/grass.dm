/turf/simulated/floor/outdoors/grass
	name = "grass"
	icon_state = "grass0"
	edge_blending_priority = 4
	initial_flooring = /datum/decl/flooring/grass/outdoors
	flags = TURF_CAN_DIG_SHOVEL
	var/grass_chance = 12

	var/animal_chance = 1

	// Weighted spawn list.

/datum/category_item/catalogue/flora/sif_grass
	name = "Sivian Flora - Moss"
	desc = "A natural moss that has adapted to the sheer cold climate of Sif. \
	The moss came to rely partially on bioluminescent bacteria provided by the local tree populations. \
	As such, the moss often grows in large clusters in the denser forests of Sif. \
	The moss has evolved into it's distinctive blue hue thanks to it's reliance on bacteria that has a similar color."
	value = CATALOGUER_REWARD_TRIVIAL

//This controls how many trees and grass will spawn on this turf type
/turf/simulated/floor/outdoors/grass/sif
	name = "growth"
	icon_state = "grass_sif0"
	initial_flooring = /datum/decl/flooring/grass/sif
	edge_blending_priority = 3
	grass_chance = 5
	var/tree_chance = 0.7

	animal_chance = 0.25
	catalogue_data = list(/datum/category_item/catalogue/flora/sif_grass)

/turf/simulated/floor/outdoors/grass/sif/Initialize(mapload)
	if(tree_chance && prob(tree_chance) && !check_density())
		new /obj/structure/flora/tree/sif(src)
	. = ..()

/turf/simulated/floor/outdoors/grass/Initialize(mapload)
	if(grass && grass_chance && prob(grass_chance) && !check_density())
		var/grass_type = pickweight(GLOB.grass_grass[grass])
		if(grass_type)
			new grass_type(src)

	if(animals && animal_chance && prob(animal_chance) && !check_density())
		var/animal_type = pickweight(GLOB.grass_animals[animals])
		if(animal_type)
			new animal_type(src)

	. = ..()

/turf/simulated/floor/outdoors/grass/forest
	name = "thick grass"
	icon_state = "grass-dark0"
	grass_chance = 50
	//tree_chance = 20
	edge_blending_priority = 5
	initial_flooring = /datum/decl/flooring/grass/outdoors/forest

/turf/simulated/floor/outdoors/grass/sif/forest
	name = "thick growth"
	icon_state = "grass_sif_dark0"
	initial_flooring = /datum/decl/flooring/grass/sif/forest
	edge_blending_priority = 5
	tree_chance = 4
	grass_chance = 1

	grass = "sifforest"

/turf/simulated/floor/outdoors/rocks/sif
	var/animal_chance = 0.3

/turf/simulated/floor/outdoors/rocks/sif/Initialize(mapload)
	if(animal_chance && prob(animal_chance) && !check_density())
		new /mob/living/simple_mob/vore/slug(src)

	. = ..()

/turf/simulated/floor/outdoors/grass/sif/attackby(obj/item/C, mob/user)
	if(istype(C, /obj/item/stack/tile/floor))
		var/obj/item/stack/tile/floor/S = C
		if (S.get_amount() < 1)
			return
		playsound(src, 'sound/weapons/Genhit.ogg', 50, 1)
		ChangeTurf(/turf/simulated/floor)
		S.use(1)
		return
	. = ..()
