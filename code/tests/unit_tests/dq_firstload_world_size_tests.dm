// The world's x/y size is fixed once Rust is configured (code/content/maps/world_size.dm).
//
// The native tables key a turf by its BYOND ref, its index in a maxx x maxy grid, so growing the world renumbers every cell: on a 100x100 world a
// 256-wide template cooled 8286 of 8713 station floors to space temperature. The world boots large enough for every template, and a template
// that does not fit is refused.

/// The solid temperatures of the station floors and the air pressure of the first open floor, to compare across a load.
/proc/dq_firstload_world_readings()
	var/list/turfs = unit_test_air_tracked()
	var/pressure = -1
	for(var/turf/open/T in turfs)
		if(T.turf_air())
			pressure = T.turf_air().return_pressure()
			break
	return list("turfs" = turfs, "k" = vg_heat_turf_temperatures(turfs), "pressure" = pressure)

/// How many floors of `readings` have another temperature now.
/proc/dq_firstload_floors_moved(list/readings)
	var/list/was = readings["k"]
	var/list/now = vg_heat_turf_temperatures(readings["turfs"])
	var/moved = 0
	for(var/i in 1 to length(was))
		if(was[i] >= 0 && abs(now[i] - was[i]) > 1)
			moved++
	return moved

/// After boot the world holds the largest template, and its size is fixed.
/datum/unit_test/dq_firstload_world_holds_templates

/datum/unit_test/dq_firstload_world_holds_templates/Run()
	var/list/need = world_size_templates_need()
	TEST_ASSERT(need[1] > 0 && need[2] > 0, "the expedition template has a size")
	TEST_ASSERT(world.maxx >= need[1], "the world is [world.maxx] wide, the largest template [need[1]]")
	TEST_ASSERT(world.maxy >= need[2], "the world is [world.maxy] high, the largest template [need[2]]")
	TEST_ASSERT(GLOB.world_size_fixed, "the size is fixed once Rust is configured")

/// A template loaded after boot never changes maxx or maxy, and no station floor changes temperature or pressure.
/datum/unit_test/dq_firstload_new_z_keeps_world_size

/datum/unit_test/dq_firstload_new_z_keeps_world_size/Run()
	test_driver_begin()
	var/list/readings = dq_firstload_world_readings()
	var/max_x = world.maxx
	var/max_y = world.maxy
	var/datum/map_template/expedition_site/template = new
	var/z = template.load_new_z()
	TEST_ASSERT(z, "the template loaded")
	TEST_ASSERT_EQUAL(world.maxx, max_x, "the world did not grow in x")
	TEST_ASSERT_EQUAL(world.maxy, max_y, "the world did not grow in y")
	TEST_ASSERT_EQUAL(dq_firstload_floors_moved(readings), 0, "floors whose solid temperature the load moved")
	var/list/after = dq_firstload_world_readings()
	TEST_ASSERT_EQUAL(after["pressure"], readings["pressure"], "the air pressure of the first open floor")
	TEST_ASSERT_EQUAL(dq_firstload_initialized_turfs(z), world.maxx * world.maxy, "every turf of the level is initialized")
	test_driver_end()

/// A template larger than the world is refused with a warning, and no z-level is left behind.
/datum/unit_test/dq_firstload_oversized_template_refused

/datum/unit_test/dq_firstload_oversized_template_refused/Run()
	test_driver_begin()
	var/max_x = world.maxx
	var/max_y = world.maxy
	var/max_z = world.maxz
	var/refusals = GLOB.world_growth_refusal_count
	var/datum/map_template/expedition_site/template = new
	template.width = world.maxx + 1
	var/result = template.load_new_z()
	TEST_ASSERT(!result, "the oversized template did not load")
	TEST_ASSERT_EQUAL(GLOB.world_growth_refusal_count, refusals + 1, "the refusal was counted (and warned about)")
	TEST_ASSERT_EQUAL(world.maxz, max_z, "no partial z-level was left behind")
	TEST_ASSERT_EQUAL(world.maxx, max_x, "the world did not grow in x")
	TEST_ASSERT_EQUAL(world.maxy, max_y, "the world did not grow in y")
	test_driver_end()
