// A Topic href is an op (doc/rewrite/final_api.html, section 13 "Topic links"): the op whose topic("key") names the href runs through the input
// inbox with the requirements and refusals of a click, its arg() schemas check the href's values, and an href no op names is the TOPIC_ACTION table's.

/datum/dq_topic_op_probe
	var/bumped = 0
	var/last_n
	var/last_who
	var/last_note
	var/open = TRUE
	var/obj/item/last_item
	var/list/pool
	var/gate_open = TRUE

MSG_DEF_SELF(dq_topic_probe/closed, "The probe is closed.")

CAPABILITIES(/datum/dq_topic_op_probe)
	op("bump", topic("action=bump", arg("n", int(0, 9), optional = TRUE), arg("who", schema_text(8), optional = TRUE)), needs(req(PROC_REF(probe_open), because = MSG(dq_topic_probe/closed))), then(PROC_REF(do_bump)))
	op("plain", topic("plain"), then(PROC_REF(do_plain)))
	op("secret", topic("secret"), needs(req_rights(R_ADMIN)), then(PROC_REF(do_secret)))
	op("pick_item", topic("pick_item", arg("item", schema_ref(/obj/item))), then(PROC_REF(do_pick_item)))
	op("pick_pooled", topic("pick_pooled", arg("item", schema_ref(/obj/item), among = PROC_REF(item_pool))), then(PROC_REF(do_pick_item)))

/datum/dq_topic_op_probe/topic_allowed(mob/user, list/href_list)
	return gate_open

/datum/dq_topic_op_probe/proc/item_pool()
	return pool

/datum/dq_topic_op_probe/proc/probe_open(datum/act/op/A)
	return open

/datum/dq_topic_op_probe/proc/do_bump(datum/act/op/A, n, who)
	bumped++
	last_n = n
	last_who = who
	last_note = A.topic_href()?["action"]
	return TRUE

/datum/dq_topic_op_probe/proc/do_plain(datum/act/op/A)
	bumped++
	return TRUE

/datum/dq_topic_op_probe/proc/do_secret(datum/act/op/A)
	bumped++
	return TRUE

/datum/dq_topic_op_probe/proc/do_pick_item(datum/act/op/A, item)
	last_item = item
	return TRUE

/datum/dq_topic_op_probe/proc/topic_legacy_row(mob/user, list/args)
	last_note = "legacy"
	return TRUE

TOPIC_ACTION(/datum/dq_topic_op_probe, "legacy", PROC_REF(topic_legacy_row))

/// A page with no op of its own: it hands every href to its book.
/datum/dq_topic_op_page
	var/datum/dq_topic_op_probe/book

/datum/dq_topic_op_page/topic_forward()
	return book

/datum/unit_test/dq_e2/topic_is_an_op

/datum/unit_test/dq_e2/topic_is_an_op/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/datum/dq_topic_op_probe/P = new
	// "action=bump" names the op, the schema types the number and the optional text may be absent
	var/datum/op_result/by_href = inbox_topic(M, P, list("action" = "bump", "n" = "4"))
	TEST_ASSERT_EQUAL(by_href?.key, "bump", "an href is the op whose topic key names it")
	TEST_ASSERT_EQUAL(by_href?.origin, ORIGIN_UI, "with the UI origin")
	TEST_ASSERT_EQUAL(P.bumped, 1, "the handler ran")
	TEST_ASSERT_EQUAL(P.last_n, 4, "the href's text became a number through the schema")
	TEST_ASSERT_NULL(P.last_who, "an optional value left out reaches the handler as null")
	TEST_ASSERT_EQUAL(P.last_note, "bump", "A.topic_href() is the raw href")
	// a bare key names its op whatever the value is
	inbox_topic(M, P, list("plain" = "anything"))
	TEST_ASSERT_EQUAL(P.bumped, 2, "a bare key matches on the key alone")
	// the value of a keyed topic must match: action=other names nothing
	TEST_ASSERT_NULL(inbox_topic(M, P, list("action" = "other")), "an href no op names resolves to nothing")
	TEST_ASSERT_EQUAL(P.bumped, 2, "and nothing ran")
	// a number out of range is clamped by the schema, text that is not a number refuses
	inbox_topic(M, P, list("action" = "bump", "n" = "40"))
	TEST_ASSERT_EQUAL(P.last_n, 9, "a number past the schema's ceiling is clamped")
	var/datum/op_result/bad = inbox_topic(M, P, list("action" = "bump", "n" = "many"))
	TEST_ASSERT_EQUAL(bad?.outcome, ACT_REFUSED, "a value the schema cannot read refuses the href")
	TEST_ASSERT_EQUAL(P.bumped, 3, "and the handler never ran for it")
	// a ref arg: the schema locates it and checks its type
	var/obj/item/I = allocate(/obj/item)
	inbox_topic(M, P, list("pick_item" = "[REF(I)]", "item" = "[REF(I)]"))
	TEST_ASSERT_EQUAL(P.last_item, I, "a ref in an href is located and typed by its schema")
	var/datum/op_result/not_item = inbox_topic(M, P, list("pick_item" = "1", "item" = "[REF(M)]"))
	TEST_ASSERT_EQUAL(not_item?.outcome, ACT_REFUSED, "a ref of the wrong type is refused")

/datum/unit_test/dq_e2/topic_refuses_like_a_click

/datum/unit_test/dq_e2/topic_refuses_like_a_click/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/datum/dq_topic_op_probe/P = new
	P.open = FALSE
	var/datum/op_result/refused = inbox_topic(M, P, list("action" = "bump"))
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "a requirement refuses an href as it refuses a click")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/dq_topic_probe/closed, "with its reason")
	TEST_ASSERT_EQUAL(P.bumped, 0, "and the handler never ran")
	P.open = TRUE
	TEST_ASSERT_EQUAL(inbox_topic(M, P, list("action" = "bump"))?.outcome, ACT_COMMITTED, "once the requirement holds the same href runs")
	// rights: an actor with no admin rights is refused
	var/datum/op_result/no_rights = inbox_topic(M, P, list("secret" = 1))
	TEST_ASSERT_EQUAL(no_rights?.outcome, ACT_REFUSED, "req_rights refuses an href from an actor without the right")
	TEST_ASSERT_EQUAL(P.bumped, 1, "and the handler never ran")

/datum/unit_test/dq_e2/topic_forwards_and_falls_back

/datum/unit_test/dq_e2/topic_forwards_and_falls_back/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/datum/dq_topic_op_page/pg = new
	pg.book = new
	var/datum/op_result/forwarded = inbox_topic(M, pg, list("plain" = 1))
	TEST_ASSERT_EQUAL(forwarded?.key, "plain", "an href the page names no op for goes to the datum it forwards to")
	TEST_ASSERT_EQUAL(pg.book.bumped, 1, "and runs there")
	// an href no op names is left to the TOPIC_ACTION table (the driver reports no op result for it)
	TEST_ASSERT_NULL(inbox_topic(M, pg.book, list("legacy" = 1)), "an href only a TOPIC_ACTION row names is not an op")
	TEST_ASSERT_EQUAL(pg.book.last_note, "legacy", "and the row still runs")

/datum/unit_test/dq_e2/topic_ref_among_and_gate

/datum/unit_test/dq_e2/topic_ref_among_and_gate/run_gate()
	var/mob/living/simple_mob/e0_fixture/M = actor()
	var/datum/dq_topic_op_probe/P = new
	var/obj/item/in_pool = allocate(/obj/item)
	var/obj/item/outside = allocate(/obj/item)
	P.pool = list(in_pool)
	inbox_topic(M, P, list("pick_pooled" = 1, "item" = "[REF(in_pool)]"))
	TEST_ASSERT_EQUAL(P.last_item, in_pool, "a ref among a pool is found in the pool")
	P.last_item = null
	var/datum/op_result/stranger = inbox_topic(M, P, list("pick_pooled" = 1, "item" = "[REF(outside)]"))
	TEST_ASSERT_EQUAL(stranger?.outcome, ACT_REFUSED, "a real item that is not in the pool is refused")
	TEST_ASSERT_NULL(P.last_item, "and the handler never saw it")
	// the holder's topic_allowed() gate comes before the op
	P.gate_open = FALSE
	var/datum/op_result/gated = inbox_topic(M, P, list("plain" = 1))
	TEST_ASSERT_EQUAL(gated?.outcome, ACT_REFUSED, "a holder whose topic_allowed() says no refuses the link")
	TEST_ASSERT_EQUAL(P.bumped, 0, "and no op ran")
