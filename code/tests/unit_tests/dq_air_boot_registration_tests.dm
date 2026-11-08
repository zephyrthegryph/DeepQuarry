// The Rust atmos core registers the map's turfs at round start (vg_hook_register_world_turfs()): every face it opened or
// closed must match what DM's /turf/open/air_block_mask() says of the two turfs sharing it.

/// Every turf in a stretch of the station: a face is open in Rust exactly when neither turf's DM mask blocks it, the
/// vertical faces (air between decks) included.
/datum/unit_test/dq_air_boot_masks_match_dm

/datum/unit_test/dq_air_boot_masks_match_dm/Run()
	var/checked = 0
	var/vertical = 0
	var/list/z_levels = using_map.station_levels.Copy()
	for(var/z in z_levels)
		var/turf/centre = locate(round(world.maxx / 2), round(world.maxy / 2), z)
		if(!centre)
			continue
		for(var/turf/open/T in block(locate(max(1, centre.x - 40), max(1, centre.y - 40), z), locate(min(world.maxx, centre.x + 40), min(world.maxy, centre.y + 40), z)))
			if(!T.init_air || (!T.blocks_air && isnull(T.turf_air())))
				continue
			var/mask = T.air_block_mask()
			var/open = vg_atmos_open_dirs(T)
			for(var/direction in GLOB.cardinals_multiz)
				var/turf/open/N = get_step_multiz(T, direction)
				if(!istype(N) || !N.init_air || (!N.blocks_air && isnull(N.turf_air())))
					continue
				var/expected = !(mask & direction) && !(N.air_block_mask() & REVERSE_DIR(direction))
				var/actual = !!(open & direction)
				if(direction & (UP|DOWN))
					vertical++
				checked++
				if(expected != actual)
					TEST_FAIL("face [dir2text(direction)] of [T] at [T.x],[T.y],[T.z] (towards [N.type]): Rust has it [actual ? "open" : "closed"], DM masks say [expected ? "open" : "closed"]")
					return
	TEST_ASSERT(checked > 200, "only [checked] faces checked")
	log_test("AIR_BOOT_MASKS: [checked] faces matched, [vertical] of them vertical")

/// A registered turf without an air datum (the boot leaves every open turf so; the test harness's air snapshot reads them
/// all, so the test makes one) gets, on its first read, a datum bound to its Rust cell with the gas the cell holds.
/datum/unit_test/dq_turf_air_made_on_first_read

/datum/unit_test/dq_turf_air_made_on_first_read/Run()
	var/turf/open/T
	for(var/turf/simulated/floor/candidate in world)
		if(!candidate.blocks_air && !candidate.immutable_atmos && !candidate.planetary_atmos && candidate.z <= 3 && candidate.initial_gas_mix == OPENTURF_DEFAULT_ATMOS)
			T = candidate
			break
	TEST_ASSERT_NOTNULL(T, "no station-air floor")
	dq_atmos_test_snapshot_air(T)
	var/before = T.turf_air().return_pressure()
	rel_clear(T, nameof(T._air)) // the datum goes; the turf stays in the arena, its gas in its cell
	TEST_ASSERT_NULL(T._air, "the turf holds no air datum")
	var/datum/gas_mixture/air = T.turf_air()
	TEST_ASSERT_NOTNULL(air, "the first read made no air")
	TEST_ASSERT(T._air == air, "the turf keeps the datum it made")
	TEST_ASSERT(air.arena_id() >= GAS_HANDLE_TURF_BASE, "the new datum is a handle to the turf's field cell ([air.arena_id()])")
	TEST_ASSERT(vg_topology_matches(T), "the turf's datum names its field cell")
	TEST_ASSERT(abs(air.return_pressure() - before) < 0.5, "the new datum reads the cell's gas ([air.return_pressure()] kPa, was [before])")
	TEST_ASSERT(T.turf_air() == air, "a second read returns the same datum")

/// A z-level made while the round runs registers its turfs in one call from the turf grid: its space is in the arena as
/// immutable vacuum, cold, sharing air with its neighbours, without each turf registering itself.
/datum/unit_test/dq_new_level_registers_in_bulk

/datum/unit_test/dq_new_level_registers_in_bulk/Run()
	var/z = world.increment_max_z()
	var/turf/T = locate(round(world.maxx / 2), round(world.maxy / 2), z)
	TEST_ASSERT(istype(T, /turf/space), "the new level is space")
	TEST_ASSERT(vg_topology_matches(T), "the new level's space is in the air arena")
	TEST_ASSERT(vg_atmos_open_dirs(T) & EAST, "space shares air with the space beside it")
	TEST_ASSERT(T.return_air().return_pressure() < 1, "the new level's space is vacuum")
	TEST_ASSERT(T.get_temperature() < 10, "the new level's space is cold ([T.get_temperature()] K)")

/// A level a map load makes (MAP_LOAD_NEW_Z) ends with its space in the arena and its loaded turfs registered.
/datum/unit_test/dq_new_level_load_registers_space

/datum/unit_test/dq_new_level_load_registers_space/Run()
	test_driver_begin()
	var/datum/map_template/expedition_site/template = new
	var/datum/map_load/M = new(template, MAP_LOAD_NEW_Z, FALSE)
	var/t0 = REALTIMEOFDAY
	var/alone_before = GLOB.air_turfs_registered_alone
	while(M.advance(TRUE) == JOB_MORE)
		continue
	var/z = M.new_z
	TEST_ASSERT(M.result && z, "the load made its level")
	var/alone = GLOB.air_turfs_registered_alone - alone_before
	log_test("AIR_NEW_LEVEL: load_new_z took [(REALTIMEOFDAY - t0) / 10]s; [alone] turf(s) of [world.maxx * world.maxy] registered one at a time")
	TEST_ASSERT(alone < world.maxx * world.maxy / 4, "[alone] turfs of the new level registered one at a time: its space should register with the level")
	var/checked = 0
	for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(!(T.flags & ATOM_INITIALIZED))
			continue
		if(istype(T, /turf/space) || (istype(T, /turf/open) && !T.blocks_air))
			TEST_ASSERT(vg_topology_matches(T), "[T.type] at [T.x],[T.y],[T.z] is not in the air arena after the level loaded")
			if(++checked >= 400)
				break
	TEST_ASSERT(checked > 0, "nothing on the new level to check")
	test_driver_end()
