/datum/unit_test/interim_dragon_projectile_range_cleanup
	var/projectile_type = /obj/item/projectile/bullet/dragon
	var/original_range = 0

/datum/unit_test/interim_dragon_projectile_range_cleanup/flame
	projectile_type = /obj/item/projectile/bullet/incendiary/dragonflame
	original_range = 12

/datum/unit_test/interim_dragon_projectile_range_cleanup/Run()
	var/turf/T = test_floor()
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	var/obj/item/projectile/control = allocate(/obj/item/projectile, T)
	var/obj/item/projectile/projectile = allocate(projectile_type, T)
	TEST_ASSERT(projectile && !QDELETED(projectile) && projectile.loc == T, "The actual canonical projectile constructor creates its real original floor projectile")
	TEST_ASSERT_EQUAL(projectile.range, original_range, "The actual canonical projectile retains its exact original declared range")
	for(var/step_number = 1, step_number < original_range, step_number++)
		projectile.Range()
		TEST_ASSERT(!QDELETED(projectile) && projectile.loc == T, "Actual inherited range dispatch preserves the original projectile before its final range step")
		TEST_ASSERT_EQUAL(projectile.range, original_range - step_number, "Actual range dispatch decrements the original projectile range exactly once")
	projectile.Range()
	TEST_ASSERT(QDELETED(projectile), "Actual final range dispatch consumes the exact original dragon projectile")
	TEST_ASSERT(!QDELETED(control) && control.loc == T, "Actual final range dispatch preserves the exact unrelated neighboring projectile")
	TEST_ASSERT(!QDELETED(pen) && pen.loc == T, "Actual final range dispatch preserves the exact unrelated floor pen")
	var/obj/item/projectile/parked = allocate(projectile_type, T)
	parked.moveToNullspace()
	TEST_ASSERT_NULL(parked.loc, "The actual public move helper genuinely parks the original projectile in nullspace")
	TEST_ASSERT_EQUAL(parked.range, original_range, "The original parked projectile retains the canonical constructor range")
	var/parked_steps = max(1, original_range)
	for(var/parked_step = 1, parked_step <= parked_steps, parked_step++)
		parked.Range()
	TEST_ASSERT(!QDELETED(parked), "The actual inherited nullspace guard preserves the original unlaunched projectile at its spent range")
	TEST_ASSERT_EQUAL(parked.range, original_range - parked_steps, "The actual nullspace control still decrements its original range through every actual dispatch")
	TEST_ASSERT_NULL(parked.loc, "The actual unlaunched projectile remains in nullspace")
