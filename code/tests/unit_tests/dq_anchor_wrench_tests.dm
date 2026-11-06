// anchor(sfx =, attached =, detached =) (code/library/machine/anchor.dm) and the refusals converted onto requirements: a wrench on a fixture
// flips its anchored flag through the setter, a refusal comes from the op's needs() with its reason, never a message in the effect.

/datum/unit_test/dq_anchor_wrench
	abstract_type = /datum/unit_test/dq_anchor_wrench

/datum/unit_test/dq_anchor_wrench/Run()
	test_driver_begin()
	run_wrench()

/datum/unit_test/dq_anchor_wrench/proc/run_wrench()
	return

/// `held` in the active hand of `user`, and a click on `target` with it.
/datum/unit_test/dq_anchor_wrench/proc/click_with(mob/living/user, atom/target, obj/item/held)
	if(user.get_active_hand() != held)
		if(user.get_active_hand())
			user.drop_item()
		if(held)
			user.put_in_active_hand(held)
	STATE_SET(user, cooldowns, next_click, 0)
	return test_click(user, target, held)

/datum/unit_test/dq_anchor_wrench/a_wrench_flips_a_fixture_between_anchored_and_loose

/datum/unit_test/dq_anchor_wrench/a_wrench_flips_a_fixture_between_anchored_and_loose/run_wrench()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench)
	var/obj/structure/filingcabinet/C = allocate(/obj/structure/filingcabinet)
	TEST_ASSERT(C.anchored, "the cabinet starts bolted down")
	var/datum/op_result/loosened = click_with(M, C, W)
	TEST_ASSERT_EQUAL(loosened?.outcome, ACT_COMMITTED, "a wrench on the cabinet commits")
	TEST_ASSERT(!C.anchored, "and unbolts it")
	var/datum/op_result/bolted = click_with(M, C, W)
	TEST_ASSERT_EQUAL(bolted?.outcome, ACT_COMMITTED, "a second wrench commits")
	TEST_ASSERT(C.anchored, "and bolts it down again")

/datum/unit_test/dq_anchor_wrench/an_extra_requirement_refuses_the_wrench_with_its_reason

/datum/unit_test/dq_anchor_wrench/an_extra_requirement_refuses_the_wrench_with_its_reason/run_wrench()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench)
	var/obj/machinery/honey_extractor/H = allocate(/obj/machinery/honey_extractor)
	H.set_processing(1)
	var/datum/op_result/refused = click_with(M, H, W)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a spinning extractor refuses the wrench")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/honey_extractor/spinning, "with the extractor's reason")
	TEST_ASSERT(H.anchored, "and stays bolted down")
	H.set_processing(0)
	var/datum/op_result/done = click_with(M, H, W)
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "an idle one takes the wrench")
	TEST_ASSERT(!H.anchored, "and comes loose")

/datum/unit_test/dq_anchor_wrench/a_shut_fuel_port_refuses_a_hand_with_its_reason

/datum/unit_test/dq_anchor_wrench/a_shut_fuel_port_refuses_a_hand_with_its_reason/run_wrench()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/structure/fuel_port/P = allocate(/obj/structure/fuel_port, test_floor())
	var/datum/op_result/refused = click_with(M, P, null)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a shut fuel port refuses a bare hand")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/fuel_port/secured, "with the port's reason")
	TEST_ASSERT_EQUAL(contents_count(P), 1, "and keeps its tank")
	P.set_opened(TRUE)
	var/datum/op_result/taken = click_with(M, P, null)
	TEST_ASSERT_EQUAL(taken?.outcome, ACT_COMMITTED, "an open one gives its tank")
	TEST_ASSERT_EQUAL(contents_count(P), 0, "out of the port")
