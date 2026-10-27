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

// A link written with HREF_TOKEN_PLACEHOLDER carries the token of the admin it is delivered to, and none for a player.
/datum/unit_test/dq_e2/href_token_delivery

/// The value of the link's admin_token query part ("" when it has none).
/datum/unit_test/dq_e2/href_token_delivery/proc/token_of(text)
	var/at = findtext(text, "admin_token=")
	if(!at)
		return ""
	var/start = at + length("admin_token=")
	var/stop = findtext(text, ";", start) || findtext(text, "'", start)
	return copytext(text, start, stop)

/datum/unit_test/dq_e2/href_token_delivery/run_gate()
	var/link = "<a href='byond://?_src_=holder;[HREF_TOKEN_PLACEHOLDER];adminmoreinfo=1'>?</a>"
	var/to_a = href_fill("admin-a-token", link)
	TEST_ASSERT_EQUAL(token_of(to_a), "admin-a-token", "delivered to admin A, the link carries A's token")
	var/to_b = href_fill("admin-b-token", link)
	TEST_ASSERT_EQUAL(token_of(to_b), "admin-b-token", "delivered to admin B, the link carries B's token")
	var/to_player = href_fill(null, link)
	TEST_ASSERT(!findtext(to_player, "admin_token"), "delivered to a player, the link carries no token")
	TEST_ASSERT(!findtext(to_player, HREF_TOKEN_PLACEHOLDER) && !findtext(to_player, ";;"), "and no placeholder or empty query part is left")
	// the tgui push fills the JSON of its payload: the link survives encoding, and decodes with the admin's token
	var/pushed = href_fill("admin-a-token", json_encode(list("value_html" = link)))
	var/list/decoded = json_decode(pushed)
	TEST_ASSERT_EQUAL(token_of(decoded["value_html"]), "admin-a-token", "a tgui payload's link carries A's token after the JSON is filled")
	TEST_ASSERT_EQUAL(href_fill("tok", "no links here"), "no links here", "text without the placeholder is returned as it was")
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/datum/dq_token_strict_probe/P = new
	inbox_topic(M, P, list("guarded" = 1, "admin_token" = token_of(to_a)))
	TEST_ASSERT_EQUAL(P.bumped, 1, "the strict op accepts A's delivered link from A")
	inbox_topic(M, P, list("guarded" = 1, "admin_token" = token_of(to_b)))
	TEST_ASSERT_EQUAL(P.bumped, 1, "and refuses B's delivered link from A")
