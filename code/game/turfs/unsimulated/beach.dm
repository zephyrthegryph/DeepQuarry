/turf/unsimulated/beach
	name = "Beach"
	icon = 'icons/misc/beach.dmi'

/turf/unsimulated/beach/sand
	name = "Sand"
	icon_state = "sand"

/turf/unsimulated/beach/coastline
	name = "Coastline"
	icon = 'icons/misc/beach2.dmi'
	icon_state = "sandwater"

/turf/unsimulated/beach/water
	name = "Water"
	icon_state = "water"
	skip_init = FALSE
	init_from_table = FALSE
	movement_cost = 4 // Water should slow you down, just like simulated turf.

/turf/unsimulated/beach/water/Initialize(mapload)
	. = ..()

/turf/simulated/floor/beach
	name = "Beach"
	icon = 'icons/misc/beach.dmi'
	initial_flooring = /datum/decl/flooring/sand

/turf/simulated/floor/beach/sand
	name = "Sand"
	icon_state = "sand"
	initial_flooring = /datum/decl/flooring/sand
	flags = TURF_CAN_DIG_SHOVEL // Can dig but can't cultivate

/turf/simulated/floor/beach/sand/get_dig_loot_type(mob/user, obj/item/W)
	if(prob(2))
		// Things of note that might wash up on a beach
		return pick(/obj/item/coin/silver,
					/obj/item/coin/gold,
					/obj/item/coin/copper,
					/obj/item/clothing/shoes/sandal,
					/obj/item/cell/empty,
					/obj/item/stack/cable_coil/cut,
					/obj/item/ore/iron,
					/obj/item/stack/material/wood,
					/obj/item/stack/material/stick,
					/obj/item/stack/material/flint,
					/obj/item/stack/material/smolebricks,
				)
	return null

/turf/simulated/floor/beach/sand/desert
	icon = 'icons/turf/desert.dmi'
	icon_state = "desert"
	initial_flooring = /datum/decl/flooring/sand/desert

CAPABILITIES(/turf/simulated/floor/beach/sand/desert)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/turf/simulated/floor/beach/sand/desert/proc/roll_icon_state(datum/roller/R)
	return R.chance(5) ? "desert[R.number(0, 4)]" : icon_state

/turf/simulated/floor/beach/coastline
	name = "Coastline"
	icon = 'icons/misc/beach2.dmi'
	icon_state = "sandwater"

/turf/simulated/floor/beach/water
	name = "Water"
	icon_state = "water"
	movement_cost = 4 // Water should slow you down, just like the original simulated turf.
	initial_flooring = /datum/decl/flooring/water

/turf/simulated/floor/beach/water/ocean
	icon_state = "seadeep"
	movement_cost = 8 // Deep water should be difficult to wade through.
	initial_flooring = /datum/decl/flooring/water/beach/deep

/turf/simulated/floor/beach/water/Initialize(mapload)
	. = ..()

/datum/decl/flooring/water/beach/deep // We're custom-defining a 'deep' water turf for the beach.
	name = "deep water"
	desc = "Deep Ocean Water"
	icon = 'icons/misc/beach.dmi'
	icon_base = "seadeep"

/turf/unsimulated/beach/water/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image('icons/misc/beach.dmi', "water2", layer = MOB_LAYER + 0.1))

/turf/simulated/floor/beach/water/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image('icons/misc/beach.dmi', "water5", layer = MOB_LAYER + 0.1))
