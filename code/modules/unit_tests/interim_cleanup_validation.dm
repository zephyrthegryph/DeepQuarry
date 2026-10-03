/// Real broken-gun validation removes an untyped wreck and preserves an initialized repairable one.
/datum/unit_test/interim_broken_gun_validation/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/broken_gun/invalid = allocate(/obj/item/broken_gun, T)
	TEST_ASSERT_NULL(invalid.my_guntype, "the untyped actual wreck has no repair target")
	invalid.validate_gun_type()
	TEST_ASSERT(QDELETED(invalid), "actual validation consumes an untyped wreck")
	TEST_ASSERT_NULL(locate_within(T, /obj/item/broken_gun), "invalid cleanup leaves no duplicate wreck")
	var/obj/item/broken_gun/valid = allocate(/obj/item/broken_gun, T, /obj/item/gun/projectile/colt/detective)
	TEST_ASSERT_EQUAL(valid.my_guntype, /obj/item/gun/projectile/colt/detective, "actual initialization records the real repair target")
	TEST_ASSERT(valid.material_needs[/obj/item/stack/material/steel] > 0, "actual initialization populates required repair steel")
	var/list/needs_before = valid.material_needs.Copy()
	valid.validate_gun_type()
	TEST_ASSERT(!QDELETED(valid), "actual validation preserves the initialized repairable wreck")
	TEST_ASSERT_EQUAL(valid.loc, T, "validation keeps the repairable wreck on its original floor")
	TEST_ASSERT_EQUAL(length(valid.material_needs), length(needs_before), "validation preserves the actual number of repair requirements")
	for(var/path in needs_before)
		TEST_ASSERT_EQUAL(valid.material_needs[path], needs_before[path], "validation preserves each actual randomized repair quantity")

/// The actual two-stage RCD animation remains until its declared ending delay then deletes itself.
/datum/unit_test/interim_rcd_effect_cleanup
	var/mode = RCD_FLOORWALL
	var/start_state = "rcd_shorter"
	var/end_state = "rcd_end"

/datum/unit_test/interim_rcd_effect_cleanup/reverse
	mode = RCD_DECONSTRUCT
	start_state = "rcd_shorter_reverse"
	end_state = "rcd_end_reverse"

/datum/unit_test/interim_rcd_effect_cleanup/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/effect/constructing_effect/effect = allocate(/obj/effect/constructing_effect, T, 1 SECOND, mode)
	TEST_ASSERT_EQUAL(effect.icon_state, start_state, "actual initialization starts the expected one-second animation")
	test_time(0.5 SECONDS)
	TEST_ASSERT(!QDELETED(effect), "the actual effect survives before its construction animation ends")
	TEST_ASSERT_EQUAL(effect.icon_state, start_state, "the actual effect retains its initial animation before the first deadline")
	test_time(0.6 SECONDS)
	TEST_ASSERT(!QDELETED(effect), "the actual effect survives while its ending animation plays")
	TEST_ASSERT_EQUAL(effect.icon_state, end_state, "the real first deadline switches to the matching ending animation")
	test_time(1 SECOND)
	TEST_ASSERT(!QDELETED(effect), "the ending animation survives before its full one-and-a-half-second delay")
	test_time(0.6 SECONDS)
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(effect), "the actual ending deadline consumes the original effect")
	TEST_ASSERT_NULL(locate_within(T, /obj/effect/constructing_effect), "animation cleanup leaves no duplicate effect")
