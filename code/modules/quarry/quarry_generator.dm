// Map template for a freshly-allocated quarry layer.
// The .dmm is a 40x40 of /turf/simulated/mineral/cave; the cave generator
// then carves the walkable space.
/datum/map_template/quarry_layer
	name = "Deep Quarry Layer"
	mappath = "maps/deep_quarry/deep_quarry_layer.dmm"

// Cave generator subtype.
//
// Carves walkable space out of the loaded /turf/simulated/mineral substrate
// via cellular automata. Reads its wall density and smoothing iterations
// from a /datum/quarry_layer_config that SSquarry sets on it before
// construction. The config also drives ore placement, decorations, and
// mob spawning, but those are post-generation passes run by SSquarry —
// not by this datum.
//
// We override cleanup() and apply_to_turf() to suppress the parent's
// hardcoded ore marking and mob_spawner injection. SSquarry handles those
// from the config.
/datum/random_map/automata/cave_system/quarry
	descriptor = "deep quarry"
	make_cracked_turfs = FALSE
	iterations = 4
	initial_wall_cell = 50
	// Parent runs generate() up to max_attempts times unconditionally — there's
	// no break on success in /datum/random_map/New. Setting this to 1 stops
	// the redundant 4-5x rework. If sanity-check failures become a problem we
	// can wrap this with a retry mechanism that DOES break early.
	max_attempts = 1

// Construct with a layer config. We need iterations and initial_wall_cell
// set BEFORE the parent's New() runs generate(), so the override applies
// them and then chains to the standard signature. Pass null for `cfg` to
// fall back to the type-default values.
/datum/random_map/automata/cave_system/quarry/New(datum/quarry_layer_config/cfg, tx, ty, tz, tlx, tly)
	if(cfg)
		initial_wall_cell = cfg.wall_density
		iterations = cfg.smoothing_iterations
	..(null, tx, ty, tz, tlx, tly)

// Override cleanup: skip the ore-placement loop that the parent runs.
// SSquarry handles ore placement from the config after generation.
/datum/random_map/automata/cave_system/quarry/cleanup()
	return 1

// Override apply_to_turf: keep make_floor/make_wall behavior, drop the
// ore-flag and mob-spawner side effects from the parent.
/datum/random_map/automata/cave_system/quarry/apply_to_turf(x, y)
	var/current_cell = get_map_cell(x, y)
	if(!current_cell)
		return 0
	var/turf/simulated/mineral/T = locate((origin_x - 1) + x, (origin_y - 1) + y, origin_z)
	if(!istype(T) || T.ignore_mapgen || T.ignore_cavegen)
		return T
	if(map[current_cell] == FLOOR_CHAR)
		T.make_floor()
	else
		T.make_wall()
	LAZYSET(turfs_changed, T, TRUE)
	return T

// Override apply_to_map: the parent calls sleep(-1) before every cell when
// priority_process isn't set, which costs ~1ms per yield. 65k cells * 1ms
// = 65 seconds of pure scheduler overhead, dwarfing the actual work.
// Replace with CHECK_TICK, which only yields when the current MC tick is
// already over budget. Result: tight loop runs to completion as long as
// the server isn't busy with other work; yields adaptively when it is.
/datum/random_map/automata/cave_system/quarry/apply_to_map()
	if(!origin_x) origin_x = 1
	if(!origin_y) origin_y = 1
	if(!origin_z) origin_z = 1

	var/t0 = world.timeofday
	for(var/x = 1, x <= limit_x, x++)
		for(var/y = 1, y <= limit_y, y++)
			apply_to_turf(x, y)
		CHECK_TICK	// yield once per column if we're over budget
	var/t1 = world.timeofday

	var/i = 0
	for(var/turf/simulated/mineral/T as anything in turfs_changed)
		T.update_icon(1, turfs_changed)
		if(++i % 1000 == 0)
			CHECK_TICK	// batch yields in the icon-update pass
	var/t2 = world.timeofday

	LAZYCLEARLIST(turfs_changed)
	var/t3 = world.timeofday
	log_game("quarry gen timing: apply=[(t1-t0)/10]s icons=[(t2-t1)/10]s ([i] turfs) clear=[(t3-t2)/10]s")
