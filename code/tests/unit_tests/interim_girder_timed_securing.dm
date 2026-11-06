/// The wrench-secure step keeps a displaced girder movable until completion, then restores its material-derived integrity and cover without spending or refunding sheets.
/datum/unit_test/interim_girder_timed_securing/Run()
	test_driver_begin()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	user.enable_godmode() // the test floor has no air: the waits would put the actor out
	user.set_combat_mode(FALSE)
	var/obj/structure/girder/girder = allocate(/obj/structure/girder, T)
	var/obj/item/tool/wrench/wrench = allocate(/obj/item/tool/wrench, T)
	var/datum/material/material_before = girder.girder_material
	var/base_cover = girder.cover
	var/base_integrity = girder.max_integrity
	girder.displace() // Real displaced fixture; this test covers re-securing, not the preceding crowbar task.
	TEST_ASSERT(!girder.anchored, "the actual girder fixture is displaced and movable")
	var/displaced_integrity = girder.get_integrity()
	var/displaced_cover = girder.cover
	TEST_ASSERT(user.put_in_active_hand(wrench), "the actual actor holds the real securing tool")
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual actor is capable before securing")
	var/datum/op_result/securing = test_click(user, girder, wrench)
	TEST_ASSERT_NULL(securing?.outcome, "securing waits for its tool delay")
	test_time(2 SECONDS)
	TEST_ASSERT(!girder.anchored, "pending actual securing does not anchor the girder early")
	TEST_ASSERT_EQUAL(girder.get_integrity(), displaced_integrity, "pending actual securing does not restore integrity early")
	TEST_ASSERT_EQUAL(girder.cover, displaced_cover, "pending actual securing does not restore cover early")
	test_time(10 SECONDS)
	own_turf_contents(T)
	TEST_ASSERT(!user.incapacitated(INCAPACITATION_STUNNED | INCAPACITATION_KNOCKOUT), "the actual actor stays capable through securing")
	TEST_ASSERT(test_op_committed(securing), "the securing step commits")
	TEST_ASSERT(girder.anchored, "actual completion anchors the original girder")
	TEST_ASSERT_EQUAL(girder.girder_material, material_before, "actual securing preserves the original material identity")
	TEST_ASSERT_EQUAL(girder.loc, T, "actual securing preserves the original girder's floor")
	TEST_ASSERT_EQUAL(girder.max_integrity, base_integrity, "actual securing preserves the material-derived maximum integrity")
	TEST_ASSERT_EQUAL(girder.get_integrity(), base_integrity, "actual securing restores the displaced girder's integrity")
	TEST_ASSERT_EQUAL(girder.cover, base_cover, "actual securing restores the original projectile cover")
	TEST_ASSERT_EQUAL(user.get_active_hand(), wrench, "actual securing preserves the actor's held wrench")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/stack/material)), 0, "actual securing consumes and refunds no material sheets")
	test_driver_end()
