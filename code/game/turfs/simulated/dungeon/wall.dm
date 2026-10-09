// Special wall type for Point of Interests.

/turf/simulated/wall/solidrock //for more stylish anti-cheese.
	resistance_flags = INDESTRUCTIBLE //These things are suppose to be unbreakable
	var/rock_side = "rock_side"
	block_tele = TRUE

/turf/simulated/wall/solidrock/Initialize(mapload)
	. = ..(mapload, MAT_ALIEN_BEDROCK)

/turf/simulated/wall/solidrock/update_material()
	name = "solid rock"
	desc = "This rock seems dense, impossible to drill."

DECLARE_SHARED_CACHE(rock_border_overlays, GLOBAL_PROC_REF(build_rock_border_overlay), SC_NEVER)

/// Builder for rock_border_overlays: the lip a rock wall shows toward an open tile on `direction`, one shared image per sprite and direction.
/proc/build_rock_border_overlay(border_state, direction, offset)
	var/image/new_cached_image = image(border_state, dir = direction, layer = ABOVE_TURF_LAYER)
	switch(direction)
		if(NORTH)
			new_cached_image.pixel_y = offset
		if(SOUTH)
			new_cached_image.pixel_y = -offset
		if(EAST)
			new_cached_image.pixel_x = offset
		if(WEST)
			new_cached_image.pixel_x = -offset
	return new_cached_image

/// The prefix of the sprites of the rock's connections ("rock", "mossyrock").
/turf/simulated/wall/solidrock/proc/rock_connection_prefix()
	return "rock"

/// The sprite of its lip toward an open tile.
/turf/simulated/wall/solidrock/proc/rock_border_state()
	return rock_side

/// A rock wall draws the connections it has with the rock around it and, on each side that is open (open_mask, kept by the adjacency index), a lip.
/turf/simulated/wall/solidrock/look_parts(datum/look/look)
	if(!density)
		return
	var/list/connections = get_wall_connections()
	for(var/i = 1 to 4)
		look.overlay(look_overlay_image('icons/turf/wall_masks.dmi', "[rock_connection_prefix()][connections[i]]", dir = 1<<(i-1)))
	for(var/direction in GLOB.cardinal)
		if(open_mask & direction)
			look.overlay(CACHED_KEY(rock_border_overlays, "[rock_border_state()]_[direction]", rock_border_state(), direction, 32))

/// The cardinal sides of this rock that are open (a neighbour that is not dense), written by the adjacency index (code/game/turfs/turf_edges.dm).
/turf/simulated/wall/solidrock/var/open_mask = 0
TRACKED(/turf/simulated/wall/solidrock, open_mask)

/turf/simulated/wall/solidrock/edges_changed(mask)
	..()
	var/open_sides = 0
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(src, direction)
		if(istype(T) && !T.density)
			open_sides |= direction
	set_open_mask(open_sides)
	log_edge_trace("[type] at [x],[y],[z]: open sides [open_mask]")

// Old attackby: items do nothing here.
CAPABILITIES(/turf/simulated/wall/solidrock)
	op("pass_item", item(/obj/item), label("Nothing"), passes())

/turf/simulated/wall/solidrock
	resistance_flags = INDESTRUCTIBLE | BOMB_PROOF


//Mossy rocks for POI. Unbreakable, no teleport.

/turf/simulated/wall/solidrock/mossyrockpoi // Version for POI labyrinths. No teleporting, no breaking.
	desc = "An old, yet impressively durably rock wall."
	var/mossyrock_side = "mossyrock_side"

/turf/simulated/wall/solidrock/mossyrockpoi/rock_connection_prefix()
	return "mossyrock"

/turf/simulated/wall/solidrock/mossyrockpoi/rock_border_state()
	return mossyrock_side
