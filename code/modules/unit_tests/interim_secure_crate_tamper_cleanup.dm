/// Data-only anti-tamper settings retain the real secure crate's constructor and bullet behavior.
/obj/structure/closet/crate/secure/interim_tamper_alert
	tamper_proof = 2

/obj/structure/closet/crate/secure/interim_tamper_random
	tamper_proof = 1

/datum/unit_test/interim_secure_crate_tamper_cleanup
	var/crate_type = /obj/structure/closet/crate/secure/interim_tamper_alert
	var/random_alert = FALSE

/datum/unit_test/interim_secure_crate_tamper_cleanup/random
	crate_type = /obj/structure/closet/crate/secure/interim_tamper_random
	random_alert = TRUE

/datum/unit_test/interim_secure_crate_tamper_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	// Closed crate constructors gather loose floor items, so create both before the original fixtures.
	var/obj/structure/closet/crate/secure/crate = allocate(crate_type, T)
	var/obj/structure/closet/crate/secure/control = allocate(/obj/structure/closet/crate/secure/interim_tamper_alert, T)
	var/obj/item/pen/cargo = allocate(/obj/item/pen, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/obj/item/projectile/bullet/pistol/medium/shot = allocate(/obj/item/projectile/bullet/pistol/medium, T)
	TEST_ASSERT(lock_locked(crate) && !crate.opened, "the real secure crate constructor starts locked and closed")
	TEST_ASSERT_EQUAL(crate.tamper_proof, random_alert ? 1 : 2, "the real crate uses the intended existing anti-tamper setting")
	TEST_ASSERT_EQUAL(shot.obj_damage_type(), BRUTE, "the real projectile has the actual object damage kind accepted by anti-tamper")
	TEST_ASSERT(shot.damage > 0 && shot.damage < crate.get_integrity(), "the real canonical projectile is damaging but nonlethal to intact crates")
	TEST_ASSERT(cargo.move_into(crate), "the real original cargo enters the declared crate interior through the public transfer API")
	TEST_ASSERT_EQUAL(cargo.loc, crate, "the exact original cargo physically occupies its real crate")
	TEST_ASSERT(cargo in crate.slot_contents(CONTAINER_SLOT_INTERIOR), "the exact original cargo is registered in the actual interior ledger")
	var/control_integrity = control.get_integrity()
	control.bullet_act(shot)
	TEST_ASSERT(!QDELETED(control), "the same real shot preserves an intact anti-tamper crate")
	TEST_ASSERT(control.get_integrity() < control_integrity, "the intact control takes real parent projectile damage rather than passing by default")
	TEST_ASSERT(lock_locked(control) && !control.opened, "the real nonlethal shot preserves the control's original closed lock state")
	var/control_after_hit = control.get_integrity()
	crate.take_damage(crate.get_integrity() - shot.damage, BRUTE, null, FALSE)
	TEST_ASSERT(!QDELETED(crate), "actual public damage leaves the original source crate alive at the final-hit threshold")
	TEST_ASSERT_EQUAL(crate.get_integrity(), shot.damage, "actual public damage produces the exact existing lethal anti-tamper threshold")
	if(random_alert)
		var/chosen_seed
		for(var/seed in 1 to 1000)
			test_rng(seed)
			if(rand(1, 5) == 1)
				chosen_seed = seed
				break
		TEST_ASSERT_NOTNULL(chosen_seed, "a bounded genuine RNG seed search finds the original alert-explosion branch")
		test_rng(chosen_seed)
	TEST_ASSERT_NULL(crate.bullet_act(shot), "real lethal anti-tamper retains its original implicit null return")
	TEST_ASSERT(QDELETED(crate), "real non-damaging anti-tamper alert consumes the exact original crate")
	TEST_ASSERT(!QDELETED(cargo), "unchanged real container teardown preserves the exact original cargo")
	TEST_ASSERT_EQUAL(cargo.loc, T, "unchanged real interior teardown spills the exact original cargo onto its original floor")
	TEST_ASSERT(!QDELETED(control), "the alert explosion preserves the original independent control crate")
	TEST_ASSERT_EQUAL(control.get_integrity(), control_after_hit, "the explicitly non-damaging alert explosion causes no extra damage to the original control")
	TEST_ASSERT_EQUAL(control.loc, T, "the original control crate remains on its original floor")
	TEST_ASSERT(!QDELETED(shot), "the actual anti-tamper endpoint preserves the original supplied projectile identity")
	TEST_ASSERT_EQUAL(shot.loc, T, "the supplied original projectile retains its original fixture location")
	TEST_ASSERT(!QDELETED(wrench), "the non-damaging alert preserves the original unrelated tool")
	TEST_ASSERT_EQUAL(wrench.loc, T, "the original unrelated tool remains on its original floor")
	// Unit-test teardown always calls test_driver_end(), including assertion/runtime failure, resetting RNG and clock state.
