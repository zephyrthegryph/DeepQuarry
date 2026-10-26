// A topic op that requires the admin token (req_topic_token()) takes only the clicking admin's own token: another admin's token and the world's are
// refused when the clicker has a holder, and the world's is taken only from a clicker with no holder (the real op_topic_token_ok(), not overridden).

/// The clicker's holder is simulated by op_topic_token_held(): the token an admin with a holder of its own carries.
/datum/dq_token_strict_probe
	var/bumped = 0
	var/held_token = "admin-a-token"

/datum/dq_token_strict_probe/op_topic_actor_ok(mob/actor)
	return TRUE

/datum/dq_token_strict_probe/op_topic_token_held(mob/actor)
	return held_token

/datum/dq_token_strict_probe/proc/do_bump(datum/act/op/A)
	bumped++
	return TRUE

CAPABILITIES(/datum/dq_token_strict_probe)
	op("guarded", topic("guarded"), needs(req_topic_token()), then(PROC_REF(do_bump)))

/// The same op on a datum that keeps the real op_topic_token_held(): the test actor has no client, so no holder.
/datum/dq_token_strict_default
	var/bumped = 0

/datum/dq_token_strict_default/op_topic_actor_ok(mob/actor)
	return TRUE

/datum/dq_token_strict_default/proc/do_bump(datum/act/op/A)
	bumped++
	return TRUE

CAPABILITIES(/datum/dq_token_strict_default)
	op("guarded", topic("guarded"), needs(req_topic_token()), then(PROC_REF(do_bump)))

/datum/unit_test/dq_e2/topic_token_strict

/datum/unit_test/dq_e2/topic_token_strict/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/datum/dq_token_strict_probe/P = new
	inbox_topic(M, P, list("guarded" = 1, "admin_token" = P.held_token))
	TEST_ASSERT_EQUAL(P.bumped, 1, "the clicking admin's own token runs the op")
	inbox_topic(M, P, list("guarded" = 1, "admin_token" = "admin-b-token"))
	TEST_ASSERT_EQUAL(P.bumped, 1, "another admin's token is refused")
	inbox_topic(M, P, list("guarded" = 1, "admin_token" = GLOB.href_token))
	TEST_ASSERT_EQUAL(P.bumped, 1, "the world token is refused for a clicker who has a holder")
	inbox_topic(M, P, list("guarded" = 1))
	TEST_ASSERT_EQUAL(P.bumped, 1, "no token is refused")
	var/datum/dq_token_strict_default/D = new
	inbox_topic(M, D, list("guarded" = 1, "admin_token" = "admin-b-token"))
	TEST_ASSERT_EQUAL(D.bumped, 0, "a clicker with no holder is refused another admin's token")
	inbox_topic(M, D, list("guarded" = 1, "admin_token" = GLOB.href_token))
	TEST_ASSERT_EQUAL(D.bumped, 1, "and takes the world token, the one a holderless caller carries")
