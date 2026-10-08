GLOBAL_VAR(world_time_season)
GLOBAL_VAR(world_time_year)
GLOBAL_VAR(world_time_month)
GLOBAL_VAR(world_time_day)

/proc/setup_season()
	GLOB.world_time_month = text2num(time2text(world.timeofday, "MM")) 	// get the current month
	switch(GLOB.world_time_month)
		if(1 to 2)
			GLOB.world_time_season = "winter"
		if(3 to 5)
			GLOB.world_time_season = "spring"
		if(6 to 8)
			GLOB.world_time_season = "summer"
		if(9 to 11)
			GLOB.world_time_season = "autumn"
		if(12)
			GLOB.world_time_season = "winter"
	GLOB.world_time_day = text2num(time2text(world.timeofday, "DD"))
	GLOB.world_time_year = text2num(time2text(world.timeofday, "YYYY"))

/turf/simulated/floor/outdoors/grass/seasonal
	name = "grass"
	icon = 'icons/seasonal/turf.dmi'
	icon_state = "s-grass"

	icon_edge = 'icons/seasonal/turf_edge.dmi'

	initial_flooring = /datum/decl/flooring/grass/seasonal_grass

	grass = null
	animal_chance = 0.5 // upstream redeclared these as new vars for some reason
	animals = null // end
	var/tree_chance = 1
	var/trees = null
	var/snow_chance = 10
	/// The sprite of the season's flowers or leaves lying on this tile (null for none), rolled once when the tile is made.
	var/season_overlay

TRACKED(/turf/simulated/floor/outdoors/grass/seasonal, season_overlay)

/turf/simulated/floor/outdoors/grass/seasonal/Initialize(mapload)
	switch(GLOB.world_time_season)
		if("spring")
			trees = "seasonalspring"
			animals = "seasonalspring"
			grass = "seasonalspring"

			grass_chance = 30
		if("summer")
			trees = "seasonalsummer"
			animals = "seasonalsummer"
			grass = "seasonalsummer"

		if("autumn")
			trees = "seasonalautumn"

			animals = "seasonalautumn"
			grass = "seasonalautumn"

			grass_chance = 10
			animal_chance = 0.25
		if("winter")
			grass_chance = 0
			trees = "seasonalwinter"

			animals = "seasonalwinter"
			if(prob(snow_chance))
				chill()
				. = ..()
				return

			grass = "seasonalwinter"

			grass_chance = 1
			animal_chance = 0.1


	if(tree_chance && prob(tree_chance) && !check_density())
		var/tree_type = pickweight(GLOB.grass_trees[trees])
		new tree_type(src)


	if(animal_chance && prob(animal_chance) && !check_density())
		var/animal_type = pickweight(GLOB.grass_animals[animals])
		new animal_type(src)


	. = ..()
	set_season_overlay(roll_season_overlay()) // after the tile's other rolls, where the draw used to roll it

/// What the tile is described as in this season.
/turf/simulated/floor/outdoors/grass/seasonal/proc/season_desc()
	switch(GLOB.world_time_season)
		if("spring")
			return "Lush green grass, flourishing! Little flowers peek out from between the blades here and there!"
		if("summer")
			return "Bright green grass, a little dry in the summer heat!"
		if("autumn")
			return "Golden grass, it's a little crunchy as it prepares for winter!"
		if("winter")
			return "Dry, seemingly dead grass! It's too cold for the grass..."

/// The flowers (spring) or leaves (autumn) this tile has, if any.
/turf/simulated/floor/outdoors/grass/seasonal/proc/roll_season_overlay()
	switch(GLOB.world_time_season)
		if("spring")
			if(prob(50))
				return "[GLOB.world_time_season]-overlay[rand(1,19)]"
		if("autumn")
			if(prob(33))
				return "[GLOB.world_time_season]-overlay[rand(1,6)]"
	return null

/turf/simulated/floor/outdoors/grass/seasonal/draw(datum/look/look)
	..()
	look.identity(desc = season_desc())
	if(season_overlay)
		look.overlay(CACHED_KEY(seasonal_grass_overlays, season_overlay, icon, season_overlay))

/turf/simulated/floor/outdoors/grass/seasonal/notrees_nomobs_nosnow
	tree_chance = 0
	animal_chance = 0
	snow_chance = 0

DECLARE_SHARED_CACHE(seasonal_grass_overlays, GLOBAL_PROC_REF(build_seasonal_grass_overlay), SC_NEVER)

/// Builder for seasonal_grass_overlays.
/proc/build_seasonal_grass_overlay(icon, state)
	var/image/I = image(icon = icon, icon_state = state, layer = ABOVE_TURF_LAYER) // Icon should be abstracted out
	I.plane = TURF_PLANE
	I.color = null
	I.appearance_flags = RESET_COLOR|KEEP_APART|PIXEL_SCALE
	return I
