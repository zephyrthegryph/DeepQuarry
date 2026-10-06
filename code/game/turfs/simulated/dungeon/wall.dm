// Special wall type for Point of Interests.


DECLARE_APPEARANCE_PROC(/turf/simulated/wall, TYPE_PROC_REF(/atom, appearance_overlays), list())
/turf/simulated/wall/appearance_overlays()
	. = list()
	if(!material)
		return .

	if(!damage_overlays[1]) //list hasn't been populated
		generate_overlays()

	var/image/I

	if(!density)
		I = image(wall_masks, "rockvault")
		I.color = material.icon_colour
		. += I
		return .
	. += ..()

/turf/simulated/wall/solidrock //for more stylish anti-cheese.
	resistance_flags = INDESTRUCTIBLE //These things are suppose to be unbreakable
	var/rock_side = "rock_side"
	block_tele = TRUE

/turf/simulated/wall/solidrock/Initialize(mapload)
	. = ..(mapload, MAT_ALIEN_BEDROCK)
	update_icon()

/turf/simulated/wall/solidrock/update_material()
	name = "solid rock"
	desc = "This rock seems dense, impossible to drill."

/turf/simulated/wall/solidrock/proc/get_cached_border(cache_id, direction, icon_file, icon_state, offset = 32)
	if(!GLOB.mining_overlay_cache["[cache_id]_[direction]"])
		var/image/new_cached_image = image(icon_state, dir = direction, layer = ABOVE_TURF_LAYER)
		switch(direction)
			if(NORTH)
				new_cached_image.pixel_y = offset
			if(SOUTH)
				new_cached_image.pixel_y = -offset
			if(EAST)
				new_cached_image.pixel_x = offset
			if(WEST)
				new_cached_image.pixel_x = -offset
		GLOB.mining_overlay_cache["[cache_id]_[direction]"] = new_cached_image
		return new_cached_image

	return GLOB.mining_overlay_cache["[cache_id]_[direction]"]

DECLARE_APPEARANCE_PROC(/turf/simulated/wall/solidrock, TYPE_PROC_REF(/atom, appearance_overlays), list(CHANGE_NEIGHBOURS))
/turf/simulated/wall/solidrock/appearance_overlays()
	. = list()
	if(density)
		var/image/I
		for(var/i = 1 to 4)
			I = image('icons/turf/wall_masks.dmi', "rock[wall_connections[i]]", dir = 1<<(i-1))
			. += I
		for(var/direction in GLOB.cardinal)
			var/turf/T = get_step(src,direction)
			if(istype(T) && !T.density)
				. += get_cached_border(rock_side,direction,icon,rock_side)

	// Neighbouring rock connects to us: tell it when we appear or go.
	appearance_notify_neighbours("[type]|[density]", /turf/simulated/wall/solidrock)

// Old attackby: items do nothing here.
CAPABILITIES(/turf/simulated/wall/solidrock)
	op("pass_item", item(/obj/item), label("Nothing"), passes())

/turf/simulated/wall/solidrock
	resistance_flags = INDESTRUCTIBLE | BOMB_PROOF


//Mossy rocks for POI. Unbreakable, no teleport.

/turf/simulated/wall/solidrock/mossyrockpoi // Version for POI labyrinths. No teleporting, no breaking.
	desc = "An old, yet impressively durably rock wall."
	var/mossyrock_side = "mossyrock_side"

DECLARE_APPEARANCE_PROC(/turf/simulated/wall/solidrock/mossyrockpoi, TYPE_PROC_REF(/atom, appearance_overlays), list(CHANGE_NEIGHBOURS))
/turf/simulated/wall/solidrock/mossyrockpoi/appearance_overlays()
	. = list()
	if(density)
		var/image/I
		for(var/i = 1 to 4)
			I = image('icons/turf/wall_masks.dmi', "mossyrock[wall_connections[i]]", dir = 1<<(i-1))
			. += I
		for(var/direction in GLOB.cardinal)
			var/turf/T = get_step(src,direction)
			if(istype(T) && !T.density)
				. += get_cached_border(mossyrock_side,direction,icon,mossyrock_side)

	appearance_notify_neighbours("[type]|[density]", /turf/simulated/wall/solidrock/mossyrockpoi)
