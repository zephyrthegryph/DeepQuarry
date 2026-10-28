// Access feedback runs once for a direct UI check or an actual rejected topic; requirement evaluation is pure.

/mob/living/simple_mob/e0_fixture/denied_counter
	var/denials = 0

/mob/living/simple_mob/e0_fixture/denied_counter/CanUseObjTopic(obj/O)
	return FALSE

/mob/living/simple_mob/e0_fixture/denied_counter/access_denied_feedback(obj/O)
	denials++

/datum/unit_test/dq_e2/obj_access_denied_once

/datum/unit_test/dq_e2/obj_access_denied_once/run_gate()
	var/mob/living/simple_mob/e0_fixture/denied_counter/M = allocate(/mob/living/simple_mob/e0_fixture/denied_counter)
	var/obj/structure/closet/dq_access_denied_probe/C = allocate(/obj/structure/closet/dq_access_denied_probe)
	TEST_ASSERT_EQUAL(C.CanUseTopic(M, C.topic_state()), STATUS_CLOSE, "the direct check refuses")
	TEST_ASSERT_EQUAL(M.denials, 1, "and says so once")
	M.denials = 0
	var/datum/act/op/A = new
	A.actor = M
	TEST_ASSERT_EQUAL(C.topic_usable(A), MSG(op/topic_gate), "the topic requirement refuses with its reason")
	TEST_ASSERT_EQUAL(M.denials, 0, "Evaluating the requirement must not deliver feedback")
	var/datum/op_result/R = inbox_topic(M, C, list("denied_probe" = 1))
	TEST_ASSERT_EQUAL(R?.outcome, ACT_REFUSED, "The real topic dispatcher refuses the denied actor")
	TEST_ASSERT_EQUAL(R?.reason, MSG(op/topic_gate), "The dispatcher preserves the access gate reason")
	TEST_ASSERT_EQUAL(M.denials, 1, "Actual refusal delivers feedback once")
	TEST_ASSERT_EQUAL(C.effects, 0, "A refused topic never runs its effect")
	A.actor = null
	qdel(A)

/obj/structure/closet/dq_access_denied_probe
	var/effects = 0

CAPABILITIES(/obj/structure/closet/dq_access_denied_probe)
	op("denied_probe", topic("denied_probe"), then(PROC_REF(probe_effect)))

/obj/structure/closet/dq_access_denied_probe/proc/probe_effect(datum/act/op/A)
	effects++
