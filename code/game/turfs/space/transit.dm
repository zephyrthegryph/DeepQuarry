/turf/space/transit
	can_build_into_floor = FALSE
	var/pushdirection // push things that get caught in the transit tile this direction
	init_from_table = FALSE

//Overwrite because we dont want people building rods in space.
// Old attackby: no building rods in transit space.
CAPABILITIES(/turf/space/transit)
	setup(PROC_REF(point_transit_animation))
	op("pass_item", item(/obj/item), label("Nothing"), passes())

/turf/space/transit/proc/point_transit_animation()
	toggle_transit(GLOB.reverse_dir[pushdirection])

//------------------------

/turf/space/transit/north // moving to the north
	icon_state = "arrow-north"
	pushdirection = SOUTH  // south because the space tile is scrolling south

/turf/space/transit/south // moving to the south
	icon_state = "arrow-south"
	pushdirection = SOUTH  // south because the space tile is scrolling south

/turf/space/transit/east // moving to the east
	icon_state = "arrow-east"
	pushdirection = WEST


//------------------------
