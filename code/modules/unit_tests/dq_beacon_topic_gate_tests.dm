/// Mutable access fixtures exercise the real CanUseTopic requirement, including request resumption.
/mob/living/carbon/human/beacon_topic_gate_actor
	var/permits_topics = TRUE
	var/access_denials = 0

/mob/living/carbon/human/beacon_topic_gate_actor/CanUseObjTopic(obj/O)
	return permits_topics

/mob/living/carbon/human/beacon_topic_gate_actor/access_denied_feedback(obj/O)
	access_denials++

/obj/machinery/syndicate_beacon/topic_gate_probe
	var/offers_accepted = 0

/obj/machinery/syndicate_beacon/topic_gate_probe/topic_state()
	return GLOB.tgui_always_state

/obj/machinery/syndicate_beacon/topic_gate_probe/betraitor(mob/user, mob/M)
	offers_accepted++

/obj/machinery/syndicate_beacon/virgo/topic_gate_probe
	var/transfers_attempted = 0

/obj/machinery/syndicate_beacon/virgo/topic_gate_probe/topic_state()
	return GLOB.tgui_always_state

/obj/machinery/syndicate_beacon/virgo/topic_gate_probe/ui_act_transfer_supplies(datum/act/op/A, mob_ref)
	transfers_attempted++
	return OP_OK

/datum/unit_test/dq_e2/beacon_topic_gate_request
/datum/unit_test/dq_e2/beacon_topic_gate_request/run_gate()
	var/mob/living/carbon/human/beacon_topic_gate_actor/user = allocate(/mob/living/carbon/human/beacon_topic_gate_actor, test_floor())
	user.enable_godmode()
	var/obj/machinery/syndicate_beacon/topic_gate_probe/B = allocate(/obj/machinery/syndicate_beacon/topic_gate_probe, get_turf(user))
	B.set_grid_power(TRUE)
	B.set_broken_condition(FALSE)
	user.permits_topics = FALSE
	test_menu(user, B, "beacon_talk")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Denied topic access prevents the real beacon question from opening")
	TEST_ASSERT(user.access_denials > 0, "The actual CanUseObjTopic gate reports the denial")
	TEST_ASSERT_EQUAL(B.offers_accepted, 0, "Denied admission executes no offer effect")
	user.permits_topics = TRUE
	test_menu(user, B, "beacon_talk")
	var/datum/prompt/choice/offer = SSrequests.open_for(user)
	TEST_ASSERT(istype(offer), "Allowed topic access opens the real beacon choice request")
	var/accept = offer.choices[1]
	TEST_ASSERT(accept != "Hang up", "The real human receives an actual recruitment offer")
	user.permits_topics = FALSE
	test_answer(user, accept)
	TEST_ASSERT_EQUAL(B.offers_accepted, 0, "Losing topic access after the question prevents its completion effect")
	TEST_ASSERT_NULL(SSrequests.open_for(user), "Refused request resumption closes the native request")
	user.permits_topics = TRUE
	test_menu(user, B, "beacon_talk")
	offer = SSrequests.open_for(user)
	TEST_ASSERT(istype(offer), "Restored access can open the actual question again")
	test_answer(user, offer.choices[1])
	TEST_ASSERT_EQUAL(B.offers_accepted, 1, "Allowed real request completion reaches the offer effect once")

/datum/unit_test/dq_e2/beacon_topic_gate_ui
/datum/unit_test/dq_e2/beacon_topic_gate_ui/run_gate()
	var/mob/living/carbon/human/beacon_topic_gate_actor/user = allocate(/mob/living/carbon/human/beacon_topic_gate_actor, test_floor())
	user.enable_godmode()
	var/obj/machinery/syndicate_beacon/virgo/topic_gate_probe/B = allocate(/obj/machinery/syndicate_beacon/virgo/topic_gate_probe, get_turf(user))
	B.set_grid_power(TRUE)
	B.set_broken_condition(FALSE)
	user.permits_topics = FALSE
	test_ui(user, B, "transfer_supplies", list("mob_ref" = REF(user)))
	TEST_ASSERT_EQUAL(B.transfers_attempted, 0, "Inherited UI topic admission blocks the real transfer op")
	TEST_ASSERT(user.access_denials > 0, "The UI op really checked CanUseObjTopic")
	user.permits_topics = TRUE
	test_ui(user, B, "transfer_supplies", list("mob_ref" = REF(user)))
	TEST_ASSERT_EQUAL(B.transfers_attempted, 1, "Allowed inherited UI admission reaches its actual op handler")
