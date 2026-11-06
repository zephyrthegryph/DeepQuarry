// The world's x/y size is fixed once Rust is configured.
//
// The native tables (heat field, gas arena, watches, power network) key a turf by its BYOND ref, which is its index in a maxx x maxy grid
// (verdigris/core/src/grid.rs). Growing maxx or maxy renumbers every turf, so every cell then belongs to another turf: on the 100x100 test world a
// 256-wide template cooled 8286 of 8713 station floors to space temperature. Nothing remaps those tables, so nothing may grow the world after
// vg_configure_world() has run:
//
//     - Before it runs (world/New()), the world is grown once to hold the largest expedition template (world_size_grow_for_templates()).
//     - After it runs (GLOB.world_size_fixed), a template larger than the world is refused (world_size_admits()): a WARNING names the template
//       and both sizes, the load fails, and increase_max_x()/increase_max_y() refuse as the last guard.
//
// A template larger than the world is a content error someone should see, never a crop.

/// TRUE once vg_configure_world() has sized the native tables: the world's maxx and maxy are fixed from then on.
GLOBAL_VAR_INIT(world_size_fixed, FALSE)
/// Template loads (and growth attempts) refused because they needed a larger world since boot.
GLOBAL_VAR_INIT(world_growth_refusal_count, 0)

/// The x and y size the world needs so every expedition template fits, as list(x, y). Read from the build's template bounds, or the file.
/proc/world_size_templates_need()
	var/need_x = 0
	var/need_y = 0
	for(var/template_path in typesof(/datum/map_template/expedition_site))
		var/datum/map_template/T = template_path
		var/mappath = initial(T.mappath)
		if(!mappath)
			continue
		var/list/bounds = build_time_template_bounds(mappath)
		if(!bounds)
			// The parse is kept in the map cache (the template's own load reuses it), where the round owns it.
			var/cache_key = file(mappath)
			if(!(cache_key in GLOB.cached_maps))
				GLOB.cached_maps[cache_key] = new /datum/parsed_map(cache_key)
			var/datum/parsed_map/parsed = GLOB.cached_maps[cache_key]
			bounds = parsed.bounds
		if(!bounds)
			continue
		need_x = max(need_x, bounds[MAP_MAXX])
		need_y = max(need_y, bounds[MAP_MAXY])
	return list(need_x, need_y)

/// world/New(), before Rust is configured: grows the world to hold the largest expedition template, so production and the test map boot the same way.
/proc/world_size_grow_for_templates()
	var/list/need = world_size_templates_need()
	var/old_x = world.maxx
	var/old_y = world.maxy
	if(need[1] > world.maxx)
		world.increase_max_x(need[1])
	if(need[2] > world.maxy)
		world.increase_max_y(need[2])
	log_world("World size: [old_x]x[old_y] from the compiled map, [world.maxx]x[world.maxy] to hold the largest expedition template ([need[1]]x[need[2]]).")

/// Whether the world can hold `T`. After the size is fixed a larger template is refused: logs the WARNING and counts it.
/proc/world_size_admits(datum/map_template/T)
	if(!GLOB.world_size_fixed)
		return TRUE
	if(T.width <= world.maxx && T.height <= world.maxy)
		return TRUE
	GLOB.world_growth_refusal_count++
	log_world("WARNING: map template '[T.name]' ([T.mappath]) is [T.width]x[T.height] but the world is fixed at [world.maxx]x[world.maxy] once Rust is configured: the load is refused. Make the template fit, or raise the size the world boots with (world_size_templates_need()).")
	return FALSE
