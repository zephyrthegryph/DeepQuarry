/// Resolve the surviving tile at cleanup time: the dismantled wall's handle is intentionally dead.
/proc/interim_restore_wall_floor(x_coord, y_coord, z_coord, floor_type)
	var/turf/tile = locate(x_coord, y_coord, z_coord)
	if(!tile)
		CRASH("wall dismantle cleanup could not resolve its saved tile")
	return tile.ChangeTurf(floor_type)

/// Actual wall dismantling returns exact outer sheets and keeps reinforcement on the generated girder rather than refunding it twice.
/datum/unit_test/interim_wall_dismantle_materials
	var/reinforced_case = FALSE
	var/expected_sheets = 2

/datum/unit_test/interim_wall_dismantle_materials/reinforced
	reinforced_case = TRUE
	expected_sheets = 1

/datum/unit_test/interim_wall_dismantle_materials/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/restore_type = T.type
	var/tile_x = T.x
	var/tile_y = T.y
	var/tile_z = T.z
	defer_cleanup(null, GLOBAL_PROC_REF(interim_restore_wall_floor), tile_x, tile_y, tile_z, restore_type)
	var/turf/simulated/wall/wall = T.ChangeTurf(/turf/simulated/wall)
	var/datum/material/steel = get_material_by_name(MAT_STEEL)
	var/datum/material/reinforcement = reinforced_case ? get_material_by_name(MAT_PLASTEEL) : null
	wall.apply_materials(steel, reinforcement, steel)
	TEST_ASSERT_EQUAL(wall.material, steel, "the actual wall has steel outer material")
	TEST_ASSERT_EQUAL(wall.reinf_material, reinforcement, "the actual wall has the configured reinforcement")
	TEST_ASSERT_EQUAL(length(contents_of(wall, /obj/structure/girder)), 0, "the actual wall fixture starts without a girder")
	TEST_ASSERT_EQUAL(length(contents_of(wall, /obj/item/stack/material)), 0, "the actual wall fixture starts without recovered sheets")
	wall.dismantle_wall()
	var/turf/floor = locate(tile_x, tile_y, tile_z)
	own_turf_contents(floor)
	TEST_ASSERT(istype(floor, /turf/simulated/floor/plating), "actual dismantling replaces the wall with plating")
	var/list/girders = contents_of(floor, /obj/structure/girder)
	TEST_ASSERT_EQUAL(length(girders), 1, "actual dismantling produces exactly one support girder")
	var/obj/structure/girder/girder = girders[1]
	TEST_ASSERT_EQUAL(girder.girder_material, steel, "the actual support girder preserves its original frame material")
	TEST_ASSERT_EQUAL(girder.reinf_material, reinforcement, "the actual support girder preserves the exact configured reinforcement")
	TEST_ASSERT(girder.anchored, "the actual support girder remains anchored")
	TEST_ASSERT_EQUAL(girder.state, reinforced_case ? 2 : 0, "the actual support girder has the appropriate reinforced construction state")
	var/steel_sheets = 0
	var/other_sheets = 0
	for(var/obj/item/stack/material/sheet as anything in contents_of(floor, /obj/item/stack/material))
		if(istype(sheet, /obj/item/stack/material/steel))
			steel_sheets += sheet.get_amount()
		else
			other_sheets += sheet.get_amount()
	TEST_ASSERT_EQUAL(steel_sheets, expected_sheets, "actual dismantling refunds the exact outer-sheet allowance")
	TEST_ASSERT_EQUAL(other_sheets, 0, "actual dismantling does not refund reinforcement that remains on the girder")
