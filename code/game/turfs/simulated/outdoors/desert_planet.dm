

// Declarations (for initial_flooring)
/datum/decl/flooring/desert_planet // Yeah don't use this one, it's a parent just for setting icon.
	name = "desert stuff"
	desc = "If you see this, this turf is using the wrong decl."
	icon = 'icons/turf/desert_tiles.dmi'
	icon_base = null

/datum/decl/flooring/desert_planet/sand
	name = "sand"
	desc = "Salty and gritty."
	icon_base = "sand"
	has_base_range = 2

/datum/decl/flooring/desert_planet/deep_sand
	name = "sand"
	desc = "Really gets everywhere."
	icon_base = "deep_sand"
	has_base_range = 2

/datum/decl/flooring/desert_planet/grass
	name = "grass"
	desc = "Lively green grass, soft to walk on."
	icon_base = "grass"

/datum/decl/flooring/desert_planet/deep_grass
	name = "dense grass"
	desc = "Dense patch of grass, seems like a soft spot to lay on."
	icon_base = "deep_grass"

/datum/decl/flooring/desert_planet/gravel
	name = "gravel"
	desc = "Mix of dirt and sand, it crumbles in your hand."
	icon_base = "gravel"

/datum/decl/flooring/desert_planet/mud
	name = "mud"
	desc = "Squishy damp dirt, smells muddy."
	icon_base = "mud"

/datum/decl/flooring/desert_planet/stonewall
	name = "sandstone"
	desc = "Rough sandstone."
	icon_base = "stonewall"

/datum/decl/flooring/desert_planet/sandrock
	name = "sandstone tiles"
	desc = "Tightly joined in a mesmerizing lattice."
	icon_base = "sandrock"
	flags = TURF_HAS_EDGES | TURF_HAS_CORNERS

