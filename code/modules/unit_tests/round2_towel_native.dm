/// Immediate native wiping exercises the real fire-status API before natural status decay ticks.
/datum/unit_test/round2_towel_native
	parent_type = /datum/unit_test/dq_p2_engine

/datum/unit_test/round2_towel_native/run_gate()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	user.enable_godmode()
	bystander.enable_godmode()
	var/obj/item/towel/towel = allocate(/obj/item/towel, T)
	TEST_ASSERT(user.put_in_active_hand(towel), "actual actor holds original towel")
	user.set_fire_stacks(3)
	bystander.set_fire_stacks(4)
	TEST_ASSERT_EQUAL(user.fire_stacks, 3, "public fire-status API establishes real actor fuel stacks")
	TEST_ASSERT_EQUAL(bystander.fire_stacks, 4, "public fire-status API establishes bystander fuel stacks")
	var/datum/op_result/result = test_click(user, towel, towel)
	TEST_ASSERT(result && result.outcome == OP_OK, "actual native held input resolves wiping effect")
	TEST_ASSERT_EQUAL(user.fire_stacks, 1.5, "real first wiping reduces only actor stacks by original amount")
	TEST_ASSERT_EQUAL(bystander.fire_stacks, 4, "real first wiping does not affect nearby bystander")
	result = test_click(user, towel, towel)
	TEST_ASSERT(result && result.outcome == OP_OK, "actual second native wiping resolves")
	TEST_ASSERT_EQUAL(user.fire_stacks, 0, "real second wiping removes remaining actor stacks")
	result = test_click(user, towel, towel)
	TEST_ASSERT(result && result.outcome == OP_OK, "actual dry actor can still perform original wiping")
	TEST_ASSERT_EQUAL(user.fire_stacks, 0, "real dry wiping does not add wet or negative stacks")
	TEST_ASSERT_EQUAL(bystander.fire_stacks, 4, "complete real wiping sequence preserves bystander state")
	TEST_ASSERT_EQUAL(user.get_active_hand(), towel, "all actual wiping inputs retain original towel hand")
	TEST_ASSERT_EQUAL(towel.loc, user, "all actual wiping inputs retain original carrier")
