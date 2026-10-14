/// Actual inherited range dispatch consumes both generic and laser projectiles only on the last step.
/datum/unit_test/interim_projectile_range_end
	var/projectile_type = /obj/item/projectile

/datum/unit_test/interim_projectile_range_end/laser
	projectile_type = /obj/item/projectile/beam

/datum/unit_test/interim_projectile_range_end/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/projectile/projectile = allocate(projectile_type, T)
	projectile.range = 2
	projectile.Range()
	TEST_ASSERT(!QDELETED(projectile), "actual range dispatch preserves a projectile with a remaining step")
	TEST_ASSERT_EQUAL(projectile.range, 1, "actual range dispatch decrements the real range")
	TEST_ASSERT_EQUAL(projectile.loc, T, "the surviving projectile remains on its real floor")
	projectile.Range()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(projectile), "actual final range dispatch consumes the original projectile")
	TEST_ASSERT_EQUAL(length(contents_of(T, projectile_type)), 0, "the range endpoint leaves no duplicate projectile")
	var/obj/item/projectile/parked = allocate(projectile_type, null)
	parked.moveToNullspace()
	parked.range = 1
	parked.Range()
	TEST_ASSERT(!QDELETED(parked), "the existing actual nullspace guard preserves an unlaunched projectile")
	TEST_ASSERT_EQUAL(parked.range, 0, "the unlaunched projectile still tracks its spent range")
	TEST_ASSERT_NULL(parked.loc, "the unlaunched projectile remains in nullspace")

/// Actual laser collision damages a real low wall before consuming the spent projectile.
/datum/unit_test/interim_projectile_collision_end/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/low_wall/bay/wall = allocate(/obj/structure/low_wall/bay, T)
	var/obj/item/projectile/beam/projectile = allocate(/obj/item/projectile/beam, T)
	rel_set(projectile, nameof(projectile.starting), T)
	TEST_ASSERT(!projectile.nodamage, "the actual laser is a damaging projectile")
	TEST_ASSERT_EQUAL(projectile.penetrating, 0, "the actual laser does not penetrate this fixture")
	var/integrity_before = wall.get_integrity()
	TEST_ASSERT(integrity_before > projectile.damage, "the actual wall can survive one laser hit")
	TEST_ASSERT_EQUAL(projectile.Bump(wall), TRUE, "the actual wall collision stops the laser")
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(projectile), "actual collision consumes the original spent laser")
	TEST_ASSERT_NULL(locate_within(T, /obj/item/projectile/beam), "the collision leaves no duplicate laser")
	TEST_ASSERT(!QDELETED(wall), "the actual low wall survives the single laser hit")
	TEST_ASSERT(wall.get_integrity() < integrity_before, "actual collision applies real structural damage before consuming the laser")
	TEST_ASSERT_EQUAL(wall.loc, T, "the damaged wall remains on its original floor")
