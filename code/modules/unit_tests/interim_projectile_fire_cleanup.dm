/// Real direct-target firing refuses a sticky source before damaging its target, then releases and consumes the actual floor shot.
/datum/unit_test/interim_projectile_fire_cleanup/Run()
	var/turf/T = run_loc_floor_bottom_left
	// Closed crate constructors gather loose items; create the actual target before the other fixtures.
	var/obj/structure/closet/crate/target = allocate(/obj/structure/closet/crate, T)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/obj/item/projectile/bullet/pistol/medium/shot = allocate(/obj/item/projectile/bullet/pistol/medium, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(shot.bump_targets && !shot.nodamage, "the actual canonical medium round uses its real direct-impact damage branch")
	TEST_ASSERT(actor.put_in_active_hand(shot), "the real actor holds the exact original medium round")
	var/target_integrity = target.get_integrity()
	add_trait(shot, TRAIT_NODROP, "interim_projectile_fire_cleanup")
	TEST_ASSERT_NOTNULL(actor.release_refusal(shot), "the actual source release requirement refuses the sticky held shot")
	TEST_ASSERT_NULL(shot.fire(null, target), "actual refused direct firing retains its implicit null return")
	TEST_ASSERT(!QDELETED(shot), "refused direct firing preserves the exact original sticky source")
	TEST_ASSERT_EQUAL(actor.get_active_hand(), shot, "refused direct firing preserves the original actual source hand")
	TEST_ASSERT_EQUAL(shot.loc, actor, "refused direct firing preserves the original physical hand containment")
	TEST_ASSERT_EQUAL(target.get_integrity(), target_integrity, "source release refusal precedes actual target damage")
	remove_trait(shot, TRAIT_NODROP, "interim_projectile_fire_cleanup")
	TEST_ASSERT(actor.drop_from_inventory(shot), "actual public dropping releases the exact original shot onto the floor")
	TEST_ASSERT_EQUAL(shot.loc, T, "the accepted exact original shot is on the real firing floor")
	var/shot_damage = shot.damage
	TEST_ASSERT_NULL(shot.fire(null, target), "actual accepted direct impact retains its implicit null return")
	TEST_ASSERT(QDELETED(shot), "real direct impact consumes the exact original medium round")
	TEST_ASSERT(!QDELETED(target), "the real nonlethal direct impact preserves its actual target")
	TEST_ASSERT_EQUAL(target.get_integrity(), target_integrity - shot_damage, "the real direct impact debits exactly the canonical shot's damage")
	TEST_ASSERT_NULL(actor.get_active_hand(), "accepted actual shot cleanup leaves its original hand empty")
	TEST_ASSERT(!QDELETED(actor), "actual direct impact preserves the original source actor")
	TEST_ASSERT(!QDELETED(pen), "actual direct impact preserves the original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "actual direct impact preserves the original unrelated pen floor")

/// Data-only base projectile: the diagnostic /projectile/test override records hits after its parent returns.
/obj/item/projectile/interim_nonbump_direct
	bump_targets = FALSE
	nodamage = TRUE
	damage = 0

/// A harmless base projectile takes the actual non-bumping direct-target terminal branch.
/datum/unit_test/interim_projectile_fire_cleanup/tracer/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/structure/closet/crate/target = allocate(/obj/structure/closet/crate, T)
	var/obj/item/projectile/interim_nonbump_direct/trace = allocate(/obj/item/projectile/interim_nonbump_direct, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	TEST_ASSERT(!trace.bump_targets && trace.nodamage && trace.damage == 0, "the data-only base projectile uses the real harmless non-bumping branch")
	var/target_integrity = target.get_integrity()
	trace.fire(null, target)
	TEST_ASSERT(QDELETED(trace), "actual harmless direct-target firing consumes the exact original tracer")
	TEST_ASSERT(!QDELETED(target), "actual harmless tracing preserves the original target")
	TEST_ASSERT_EQUAL(target.get_integrity(), target_integrity, "actual non-bumping tracing leaves real target integrity unchanged")
	TEST_ASSERT(!QDELETED(pen), "actual non-bumping tracing preserves the original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "actual non-bumping tracing preserves the original pen floor")

/// A genuine nullspace source cannot begin a real firing trajectory and is disposed of.
/datum/unit_test/interim_projectile_fire_cleanup/nullspace/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/projectile/source = allocate(/obj/item/projectile, T)
	var/obj/item/projectile/control = allocate(/obj/item/projectile, T)
	var/obj/item/pen/pen = allocate(/obj/item/pen, T)
	source.moveToNullspace()
	TEST_ASSERT_NULL(source.loc, "the supported public helper actually parks the original source in nullspace")
	TEST_ASSERT(!source.fired, "the real nullspace source has not begun a trajectory")
	TEST_ASSERT_NULL(source.fire(0), "actual invalid nullspace firing retains its implicit null return")
	TEST_ASSERT(QDELETED(source), "actual invalid nullspace firing consumes the exact original source")
	TEST_ASSERT(!QDELETED(control), "invalid source cleanup preserves the independent original projectile")
	TEST_ASSERT_EQUAL(control.loc, T, "invalid source cleanup preserves the independent projectile floor")
	TEST_ASSERT(!control.fired, "invalid source cleanup starts no independent control trajectory")
	TEST_ASSERT(!QDELETED(pen), "invalid source cleanup preserves the original unrelated pen")
	TEST_ASSERT_EQUAL(pen.loc, T, "invalid source cleanup preserves the original unrelated pen floor")
