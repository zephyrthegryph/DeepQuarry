// load_new_z_level() (code/modules/maps/map_template.dm): a clean map and one with warnings only load onto a new z-level; a map whose report
// says it cannot load is refused and allocates nothing.

/datum/unit_test/dq_load_new_z_level
	abstract_type = /datum/unit_test/dq_load_new_z_level

/datum/unit_test/dq_load_new_z_level/clean_map_loads/Run()
	var/before = world.maxz
	TEST_ASSERT(load_new_z_level("code/modules/unit_tests/fixtures/dq_load_new_z_clean.dmm", "dq clean"), "a clean map loads")
	TEST_ASSERT_EQUAL(world.maxz, before + 1, "onto a new z-level")
	TEST_ASSERT(istype(locate(1, 1, world.maxz), /turf/simulated/floor), "with its floor")

/datum/unit_test/dq_load_new_z_level/unknown_object_still_loads/Run()
	var/before = world.maxz
	TEST_ASSERT(load_new_z_level("code/modules/unit_tests/fixtures/dq_load_new_z_unknown_obj.dmm", "dq unknown obj"), "a map whose only fault is an unknown object path loads")
	TEST_ASSERT_EQUAL(world.maxz, before + 1, "onto a new z-level")

/datum/unit_test/dq_load_new_z_level/unknown_turf_is_refused/Run()
	var/before = world.maxz
	TEST_ASSERT(!load_new_z_level("code/modules/unit_tests/fixtures/dq_load_new_z_broken.dmm", "dq broken"), "a map with an unknown turf is refused")
	TEST_ASSERT_EQUAL(world.maxz, before, "and allocates no z-level")
