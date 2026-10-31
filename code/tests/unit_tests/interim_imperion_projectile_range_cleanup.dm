/// These tests exercise real range-end dispatch and constructor tables, not launched submunition volleys.
/datum/unit_test/interim_imperion_projectile_range_cleanup
	var/projectile_type = /obj/item/projectile/bullet/imperionspear
	var/submunition_type = /obj/item/projectile/energy/imperionspear
	var/submunition_count = 5

/datum/unit_test/interim_imperion_projectile_range_cleanup/blaster
	projectile_type = /obj/item/projectile/bullet/imperionblaster
	submunition_type = /obj/item/projectile/energy/imperionblaster
	submunition_count = 8

/datum/unit_test/interim_imperion_projectile_range_cleanup/tesla
	projectile_type = /obj/item/projectile/bullet/imperiontesla
	submunition_type = /obj/item/projectile/energy/imperiontesla
	submunition_count = 2

/datum/unit_test/interim_imperion_projectile_range_cleanup/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/obj/item/projectile/control = allocate(/obj/item/projectile, T)
	var/obj/item/projectile/projectile = allocate(projectile_type, T)
	TEST_ASSERT_EQUAL(projectile.type, projectile_type, "the real constructor produces the exact canonical carrier type")
	TEST_ASSERT(!QDELETED(projectile) && projectile.loc == T, "the actual canonical carrier starts alive on its original floor")
	TEST_ASSERT_EQUAL(projectile.range, 0, "the actual canonical carrier preserves its declared zero range")
	TEST_ASSERT(projectile.use_submunitions && projectile.only_submunitions, "the actual constructor preserves both existing carrier flags")
	TEST_ASSERT_EQUAL(length(projectile.submunitions), 1, "the actual constructor preserves the single canonical submunition table entry")
	TEST_ASSERT_EQUAL(projectile.submunitions[submunition_type], submunition_count, "the actual constructor preserves the exact canonical submunition type and count")
	var/control_range = control.range
	projectile.Range()
	TEST_ASSERT(QDELETED(projectile), "actual inherited range dispatch consumes the exact original spent carrier")
	TEST_ASSERT(!QDELETED(control), "actual range-end dispatch preserves the original independent projectile")
	TEST_ASSERT_EQUAL(control.loc, T, "actual range-end dispatch preserves the independent projectile's original floor")
	TEST_ASSERT_EQUAL(control.range, control_range, "actual range-end dispatch does not debit the unrelated projectile's range")
	TEST_ASSERT(!QDELETED(pen), "actual range-end dispatch preserves the original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "actual range-end dispatch preserves the original pen location")
	var/obj/item/projectile/parked = allocate(projectile_type, T)
	parked.moveToNullspace()
	TEST_ASSERT_NULL(parked.loc, "the supported public helper genuinely parks the original carrier in nullspace")
	TEST_ASSERT_EQUAL(parked.range, 0, "the original parked carrier retains its canonical zero constructor range")
	parked.Range()
	TEST_ASSERT(!QDELETED(parked), "the actual inherited nullspace guard preserves the exact unlaunched carrier")
	TEST_ASSERT_EQUAL(parked.range, -1, "actual nullspace range dispatch still debits the original range exactly once")
	TEST_ASSERT_NULL(parked.loc, "actual nullspace range dispatch preserves the parked carrier's original nullspace location")
	TEST_ASSERT_EQUAL(parked.submunitions[submunition_type], submunition_count, "actual nullspace dispatch preserves the original carrier's exact submunition table")
