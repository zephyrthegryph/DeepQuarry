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
			if(!T.init_air || (!T.blocks_air && isnull(T.air)))
				continue
			var/mask = T.air_block_mask()
			var/open = vg_atmos_open_dirs(T)
			for(var/direction in GLOB.cardinals_multiz)
				var/turf/open/N = get_step_multiz(T, direction)
				if(!istype(N) || !N.init_air || (!N.blocks_air && isnull(N.air)))
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
