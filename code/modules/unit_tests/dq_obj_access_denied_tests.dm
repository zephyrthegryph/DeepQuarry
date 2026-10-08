// An obj the clicker's ID cannot use says "Access Denied" once per check, whether the check is a direct CanUseTopic() or a topic link's topic_usable().

/mob/living/simple_mob/e0_fixture/denied_counter
	var/denials = 0

/mob/living/simple_mob/e0_fixture/denied_counter/CanUseObjTopic(obj/O)
	return FALSE

/mob/living/simple_mob/e0_fixture/denied_counter/access_denied_feedback(obj/O)
	denials++

/datum/unit_test/dq_e2/obj_access_denied_once

/datum/unit_test/dq_e2/obj_access_denied_once/run_gate()
	var/mob/living/simple_mob/e0_fixture/denied_counter/M = allocate(/mob/living/simple_mob/e0_fixture/denied_counter)
	var/obj/structure/closet/C = allocate(/obj/structure/closet)
	TEST_ASSERT_EQUAL(C.CanUseTopic(M, C.topic_state()), STATUS_CLOSE, "the direct check refuses")
	TEST_ASSERT_EQUAL(M.denials, 1, "and says so once")
	M.denials = 0
	var/datum/act/op/A = new
	A.actor = M
	TEST_ASSERT(!C.topic_usable(A), "the topic requirement refuses")
	TEST_ASSERT_EQUAL(M.denials, 1, "and says so once, not twice")
	A.actor = null
	qdel(A)
