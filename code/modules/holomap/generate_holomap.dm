//
// Holomap generation.
// Based on /vg/station but trimmed down (without antag stuff) and massively optimized (you should have seen it before!) ~Leshana
//

// Define what criteria makes a turf a path or not

// Turfs that will be colored as HOLOMAP_ROCK
#define IS_ROCK(tile) (istype(tile, /turf/simulated/mineral) && tile.density)

// Turfs that will be colored as HOLOMAP_OBSTACLE
#define IS_OBSTACLE(tile) ((!istype(tile, /turf/space) && istype(tile.loc, /area/mine/unexplored)) \
					|| istype(tile, /turf/simulated/wall) \
					|| istype(tile, /turf/unsimulated/mineral) \
					|| (istype(tile, /turf/unsimulated/wall) && !istype(tile, /turf/unsimulated/wall/planetary)) \
					/*|| istype(tile, /turf/simulated/shuttle/wall)*/ \
					|| (locate(/obj/structure/grille) in tile) \
					/*|| (locate(/obj/structure/window/full) in tile)*/)

// Turfs that will be colored as HOLOMAP_PATH
#define IS_PATH(tile) ((istype(tile, /turf/simulated/floor) && !istype(tile, /turf/simulated/floor/outdoors)) \
					|| istype(tile, /turf/unsimulated/floor) \
					/*|| istype(tile, /turf/simulated/shuttle/floor)*/ \
					|| (locate(/obj/structure/catwalk) in tile))

/// Generates all the holo minimaps, initializing it all nicely, probably.
/datum/controller/subsystem/holomaps/proc/generateHoloMinimaps()
	var/start_time = world.timeofday

	// Starting over if we're running midround (it runs real fast, so that's possible)
	holoMiniMaps.Cut()
	extraMiniMaps.Cut()

	// Build the base map for each z level
	for (var/z = 1 to world.maxz)
		holoMiniMaps |= z
		holoMiniMaps[z] = generateHoloMinimap(z)

	// Generate the area overlays, small maps, etc for the station levels.
	for (var/z in using_map.station_levels)
		generateStationMinimap(z)

	if(using_map.holomap_smoosh)
		for(var/smoosh_list in using_map.holomap_smoosh)
			smooshTetherHolomaps(smoosh_list)

	holomaps_initialized = TRUE
	admin_notice(span_notice("Holomaps initialized in [round(0.1*(world.timeofday-start_time),0.1)] seconds."), R_DEBUG)

	// TODO - Check - They had a delayed init perhaps?
	for (var/obj/machinery/station_map/S in station_holomaps)
		S.setup_holomap()

/// Transparent background key for the holomap PNGs; no holomap colour is opaque black.
#define HOLOMAP_PNG_BACKGROUND "#000000"
#define HOLOMAP_PNG_BASE 1
#define HOLOMAP_PNG_AREAS 2

/// Builds a holomap canvas in one rust-g call instead of one DrawBox per pixel (Q3).
/// The PNG is RGB only, so each tile is written as an opaque key colour; SwapColor then turns
/// every key into its real (translucent) colour and the background into transparency.
/// `color_keys` maps real colour -> key. In HOLOMAP_PNG_AREAS mode it is filled as areas appear.
/datum/controller/subsystem/holomaps/proc/render_holomap_png(zLevel, mode, list/color_keys)
	var/icon/blank = icon(HOLOMAP_ICON, "blank")
	var/canvas_width = blank.Width()
	var/canvas_height = blank.Height()
	if(world.maxx > canvas_width)
		stack_trace("Minimap for z=[zLevel] : world.maxx ([world.maxx]) must be <= [canvas_width]")
	if(world.maxy > canvas_height)
		stack_trace("Minimap for z=[zLevel] : world.maxy ([world.maxy]) must be <= [canvas_height]")
	var/map_width = min(world.maxx, canvas_width)
	var/map_height = min(world.maxy, canvas_height)

	var/list/background_row = new /list(canvas_width)
	for(var/i in 1 to canvas_width)
		background_row[i] = HOLOMAP_PNG_BACKGROUND
	var/background_row_text = background_row.Join("")
	var/right_padding = canvas_width > map_width ? background_row.Join("", 1, canvas_width - map_width + 1) : ""
	var/rock_key = color_keys[HOLOMAP_ROCK]
	var/path_key = color_keys[HOLOMAP_PATH]
	var/obstacle_key = color_keys[HOLOMAP_OBSTACLE]

	// PNG rows run top to bottom; icon y = 1 is the bottom row.
	var/list/rows = new /list(canvas_height)
	for(var/row in 1 to canvas_height)
		var/y = canvas_height - row + 1
		if(y > map_height)
			rows[row] = background_row_text
			continue
		var/list/pixels = new /list(map_width)
		for(var/x in 1 to map_width)
			var/turf/tile = locate(x, y, zLevel)
			var/key = HOLOMAP_PNG_BACKGROUND
			if(mode == HOLOMAP_PNG_BASE)
				// Obstacles win over paths and paths over rock, the order the old DrawBox calls painted in.
				if(tile && tile.loc:holomapAlwaysDraw())
					if(IS_OBSTACLE(tile))
						key = obstacle_key
					else if(IS_PATH(tile))
						key = path_key
					else if(IS_ROCK(tile))
						key = rock_key
			else
				var/area/area_to_paint = tile?.loc
				var/area_color = area_to_paint?.holomap_color
				if(area_color)
					key = color_keys[area_color]
					if(!key)
						key = rgb(0, 1, length(color_keys) + 1)
						color_keys[area_color] = key
			pixels[x] = key
		rows[row] = pixels.Join("") + right_padding
		CHECK_TICK

	var/png_path = "data/holomaps/[mode]_[zLevel].png"
	var/error = rustg_dmi_create_png(png_path, "[canvas_width]", "[canvas_height]", rows.Join(""))
	if(error)
		stack_trace("Failed to render holomap [png_path]: [error]")
		return blank
	var/icon/canvas = icon(file(png_path))
	canvas.SwapColor(HOLOMAP_PNG_BACKGROUND, null)
	for(var/real_color in color_keys)
		canvas.SwapColor(color_keys[real_color], real_color)
	fdel(png_path)
	return canvas

// Generates the "base" holomap for one z-level, showing only the physical structure of walls and paths.
/datum/controller/subsystem/holomaps/proc/generateHoloMinimap(zLevel = 1)
	var/static/list/base_keys = list(HOLOMAP_ROCK = "#000001", HOLOMAP_PATH = "#000002", HOLOMAP_OBSTACLE = "#000003")
	return render_holomap_png(zLevel, HOLOMAP_PNG_BASE, base_keys)

// Okay, what does this one do?
// This seems to do the drawing thing, but draws only the areas, having nothing to do with the tiles.
// Leshana: I'm guessing this map will get overlayed on top of the base map at runtime? We'll see.
// Wait, seems we actually blend the area map on top of it right now! Huh.
/datum/controller/subsystem/holomaps/proc/generateStationMinimap(zLevel)
	var/icon/canvas = render_holomap_png(zLevel, HOLOMAP_PNG_AREAS, list())

	// Save this nice area-colored canvas in case we want to layer it or something I guess
	extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAPAREAS]_[zLevel]"] = canvas

	var/icon/map_base = icon(holoMiniMaps[zLevel])
	map_base.Blend(HOLOMAP_HOLOFIER, ICON_MULTIPLY)

	// Generate the full sized map by blending the base and areas onto the backdrop
	var/icon/big_map = icon(HOLOMAP_ICON, "stationmap")
	big_map.Blend(map_base, ICON_OVERLAY)
	big_map.Blend(canvas, ICON_OVERLAY)
	extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAP]_[zLevel]"] = big_map

	// Generate the "small" map (I presume for putting on wall map things?)
	var/icon/small_map = icon(HOLOMAP_ICON, "blank")
	small_map.Blend(map_base, ICON_OVERLAY)
	small_map.Blend(canvas, ICON_OVERLAY)
	small_map.Scale(WORLD_ICON_SIZE, WORLD_ICON_SIZE)

	// And rotate it in every direction of course!
	var/icon/actual_small_map = icon(small_map)
	actual_small_map.Insert(new_icon = small_map, dir = SOUTH)
	actual_small_map.Insert(new_icon = turn(small_map, 90), dir = WEST)
	actual_small_map.Insert(new_icon = turn(small_map, 180), dir = NORTH)
	actual_small_map.Insert(new_icon = turn(small_map, 270), dir = EAST)
	extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAPSMALL]_[zLevel]"] = actual_small_map

// For tiny multi-z maps like the tether, we want to smoosh em together into a nice big one!
/datum/controller/subsystem/holomaps/proc/smooshTetherHolomaps(list/zlevels)
	var/icon/big_map = icon(HOLOMAP_ICON, "stationmap")
	var/icon/small_map = icon(HOLOMAP_ICON, "blank")
	// For each zlevel in turn, overlay them on top of each other
	for(var/zLevel in zlevels)
		if(!isnum(zLevel))
			zLevel = GLOB.map_templates_loaded[zLevel]
		var/offset_x = HOLOMAP_PIXEL_OFFSET_X(zLevel) || 1
		var/offset_y = HOLOMAP_PIXEL_OFFSET_Y(zLevel) || 1

		var/icon/z_terrain = icon(holoMiniMaps[zLevel])
		z_terrain.Blend(HOLOMAP_HOLOFIER, ICON_MULTIPLY, offset_x, offset_y)
		big_map.Blend(z_terrain, ICON_OVERLAY, offset_x, offset_y)
		small_map.Blend(z_terrain, ICON_OVERLAY, offset_x, offset_y)

		var/icon/z_areas = extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAPAREAS]_[zLevel]"]
		big_map.Blend(z_areas, ICON_OVERLAY, offset_x, offset_y)
		small_map.Blend(z_areas, ICON_OVERLAY, offset_x, offset_y)

	// Then scale and rotate to make the actual small map we will use
	small_map.Scale(WORLD_ICON_SIZE, WORLD_ICON_SIZE)
	var/icon/actual_small_map = icon(small_map)
	actual_small_map.Insert(new_icon = small_map, dir = SOUTH)
	actual_small_map.Insert(new_icon = turn(small_map, 90), dir = WEST)
	actual_small_map.Insert(new_icon = turn(small_map, 180), dir = NORTH)
	actual_small_map.Insert(new_icon = turn(small_map, 270), dir = EAST)

	// Then assign this icon as the icon for all those levels!
	for(var/zLevel in zlevels)
		extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAP]_[zLevel]"] = big_map
		extraMiniMaps["[HOLOMAP_EXTRA_STATIONMAPSMALL]_[zLevel]"] = actual_small_map

#undef IS_ROCK
#undef IS_OBSTACLE
#undef IS_PATH
#undef HOLOMAP_PNG_BACKGROUND
#undef HOLOMAP_PNG_BASE
#undef HOLOMAP_PNG_AREAS
