/// Picking up a deployed beacon hands over its configured stack and evidence.
/datum/unit_test/interim_marker_beacon_pickup/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/marker_beacon/beacon = allocate(/obj/structure/marker_beacon, T)
	beacon.picked_color = "Cerulean"
	var/datum/forensics_crime/evidence = beacon.init_forensic_data()
	TEST_ASSERT(evidence.add_prints(user), "the deployed beacon carries actual fingerprint evidence")
	var/list/prints = evidence.get_prints().Copy()
	TEST_ASSERT(length(prints), "the fixture has fingerprints to transfer")
	test_op_handler(beacon, "picked_up_by_hand", user)
	TEST_ASSERT(QDELETED(beacon), "successful pickup removes the deployed beacon")
	var/obj/item/stack/marker_beacon/stack = user.get_active_hand()
	TEST_ASSERT(istype(stack), "pickup places the prepared stack in the actor's hand")
	own(stack)
	TEST_ASSERT_EQUAL(stack.get_amount(), 1, "pickup produces one marker beacon")
	TEST_ASSERT_EQUAL(stack.picked_color, "Cerulean", "pickup preserves the deployed color")
	var/list/transferred = stack.forensic_data?.get_prints()
	for(var/print in prints)
		TEST_ASSERT_EQUAL(transferred?[print], prints[print], "pickup preserves each fingerprint")

/// Failed hand placement and permanent-beacon interaction preserve the deployed object.
/datum/unit_test/interim_marker_beacon_pickup_refusal/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/left = allocate(/obj/item/pen, T)
	var/obj/item/pen/right = allocate(/obj/item/pen, T)
	TEST_ASSERT(user.put_in_l_hand(left), "the left hand is occupied")
	TEST_ASSERT(user.put_in_r_hand(right), "the right hand is occupied")
	var/obj/structure/marker_beacon/beacon = allocate(/obj/structure/marker_beacon, T)
	test_op_handler(beacon, "picked_up_by_hand", user)
	own_turf_contents(T)
	TEST_ASSERT(!QDELETED(beacon), "failed hand placement retains the deployed beacon")
	TEST_ASSERT_NULL(locate_within(T, /obj/item/stack/marker_beacon), "failed placement leaves no duplicate stack on the floor")
	TEST_ASSERT_EQUAL(user.get_equipped_item(SLOT_ID_HAND_L), left, "failed pickup preserves the left-hand item")
	TEST_ASSERT_EQUAL(user.get_equipped_item(SLOT_ID_HAND_R), right, "failed pickup preserves the right-hand item")
	beacon.perma = TRUE
	TEST_ASSERT(beacon.perma, "the permanent beacon is refused by the requirement (dq_timed_pin_w1/marker_beacon_permanent_stays pins the click)")
	TEST_ASSERT(!QDELETED(beacon), "the permanent beacon remains deployed")

/// Existing stacks gain one beacon; a full stack refuses without consuming the source.
/datum/unit_test/interim_marker_beacon_stack_merge/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/stack/marker_beacon/stack = allocate(/obj/item/stack/marker_beacon, T)
	stack.set_amount(stack.max_amount)
	var/obj/structure/marker_beacon/beacon = allocate(/obj/structure/marker_beacon, T)
	test_op_handler(beacon, "picked_up_into_stack", null, stack)
	TEST_ASSERT(!QDELETED(beacon), "a full stack preserves the deployed beacon")
	TEST_ASSERT_EQUAL(stack.get_amount(), stack.max_amount, "a full stack does not grow")
	stack.set_amount(stack.max_amount - 1)
	test_op_handler(beacon, "picked_up_into_stack", null, stack)
	TEST_ASSERT(QDELETED(beacon), "successful stack merge consumes the deployed beacon")
	TEST_ASSERT_EQUAL(stack.get_amount(), stack.max_amount, "successful merge adds exactly one beacon")
