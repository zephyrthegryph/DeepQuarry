/datum/unit_test/interim_aiming_orphan_cleanup
	var/periodic = TRUE

/datum/unit_test/interim_aiming_orphan_cleanup/update
	periodic = FALSE

/datum/unit_test/interim_aiming_orphan_cleanup/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, T)
	var/obj/item/binoculars/tool = allocate(/obj/item/binoculars, T)
	TEST_ASSERT(actor.put_in_active_hand(tool), "The actual actor holds its original real aiming tool")
	// Exercise a constructor-supported independent overlay, so owner deletion clears its relation without deleting it through the actor's separately owned aiming field.
	var/obj/aiming_overlay/aim = allocate(/obj/aiming_overlay, actor)
	TEST_ASSERT(aim && !QDELETED(aim), "The actual supported mob-location constructor creates a real original overlay")
	TEST_ASSERT_EQUAL(aim.owner(), actor, "The actual constructor records its exact original real owner")
	TEST_ASSERT_NULL(aim.loc, "The actual constructor genuinely moves its original overlay to nullspace")
	aim.aim_at(target, tool)
	TEST_ASSERT_EQUAL(aim.aiming_at, target, "Actual aiming selects its exact original real target")
	TEST_ASSERT_EQUAL(aim.aiming_with(), tool, "Actual aiming selects its exact original real held tool")
	TEST_ASSERT(aim in target.aimed, "Actual aiming establishes its real incoming target relation")
	TEST_ASSERT_EQUAL(aim.loc, T, "Actual aiming places its exact original overlay on its real target's floor")
	if(periodic)
		aim.aiming_step()
	else
		aim.update_aiming()
	TEST_ASSERT(!QDELETED(aim), "The actual live-owner positive control preserves its original aiming overlay")
	TEST_ASSERT_EQUAL(aim.aiming_at, target, "The actual live-owner positive control preserves its exact real target")
	TEST_ASSERT(aim in target.aimed, "The actual live-owner positive control preserves its original target backlink")
	TEST_ASSERT(consume(actor), "The actual original owner is genuinely deleted through its public lifecycle")
	TEST_ASSERT(QDELETED(actor), "The real owner is genuinely gone before orphan cleanup")
	TEST_ASSERT(!QDELETED(aim), "The actual independent overlay survives owner deletion until its orphan cleanup endpoint")
	TEST_ASSERT_NULL(aim.owner(), "Actual owner deletion clears the original overlay's real owner relation")
	if(periodic)
		TEST_ASSERT_NULL(aim.aiming_step(), "The actual orphan periodic endpoint retains its original null result")
	else
		TEST_ASSERT_NULL(aim.update_aiming(), "The actual orphan update endpoint retains its original null result")
	TEST_ASSERT(QDELETED(aim), "The actual orphan endpoint consumes the exact original aiming overlay")
	TEST_ASSERT(!(aim in target.aimed), "The actual orphan teardown removes its exact original incoming target relation")
	TEST_ASSERT(!QDELETED(target) && target.loc == T, "Actual orphan cleanup preserves its exact original real target")
