// TOPIC_ACTION registry (doc/rewrite/systems.md §20): the core dispatcher finds rows by href
// key, validates refs against their declared source and type, converts typed args, checks
// rights, inherits rows, and hands topic_ask() the raw href_list.

/datum/dq_topic_probe
	var/last_action
	var/list/last_args
	var/list/obj/item/pool

/datum/dq_topic_probe/relations()
	. = ..()
	. += rel_many(nameof(pool))
TOPIC_ACTION(/datum/dq_topic_probe, "pick", PROC_REF(topic_pick), TOPIC_REF("pick", /obj/item))
TOPIC_ACTION(/datum/dq_topic_probe, "pooled", PROC_REF(topic_pooled), TOPIC_REF("pooled", /obj/item, PROC_REF(topic_pool)))
TOPIC_ACTION(/datum/dq_topic_probe, "set", PROC_REF(topic_set), TOPIC_NUM("amount"), TOPIC_TEXT("label", 4))
TOPIC_ACTION(/datum/dq_topic_probe, "action", PROC_REF(topic_action_any))
TOPIC_ACTION(/datum/dq_topic_probe, "action=special", PROC_REF(topic_action_special))
TOPIC_ACTION(/datum/dq_topic_probe, "admin_only", PROC_REF(topic_admin_only), TOPIC_RIGHTS(R_ADMIN))

/datum/dq_topic_probe/proc/topic_pool()
	return pool

/datum/dq_topic_probe/proc/topic_pick(mob/user, list/args)
	last_action = "pick"
	last_args = args
	return TRUE

/datum/dq_topic_probe/proc/topic_pooled(mob/user, list/args)
	last_action = "pooled"
	last_args = args
	return TRUE

/datum/dq_topic_probe/proc/topic_set(mob/user, list/args)
	last_action = "set"
	last_args = args
	return TRUE

/datum/dq_topic_probe/proc/topic_action_any(mob/user, list/args)
	last_action = "action"
	return TRUE

/datum/dq_topic_probe/proc/topic_action_special(mob/user, list/args)
	last_action = "special"
	return TRUE

/datum/dq_topic_probe/proc/topic_admin_only(mob/user, list/args)
	last_action = "admin_only"
	return TRUE

/datum/dq_topic_probe/child

TOPIC_ACTION(/datum/dq_topic_probe/child, "pick", PROC_REF(topic_child_pick), TOPIC_REF("pick", /obj/item))

/datum/dq_topic_probe/child/proc/topic_child_pick(mob/user, list/args)
	last_action = "child_pick"
	return TRUE

/datum/unit_test/dq_sys_topic_dispatch

/datum/unit_test/dq_sys_topic_dispatch/Run()
	var/datum/dq_topic_probe/P = new
	var/obj/item/I = allocate(/obj/item, test_floor())
	var/obj/structure/S = allocate(/obj/structure, test_floor())

	// A valid ref of the declared type reaches the handler as the object.
	TEST_ASSERT(topic_dispatch(P, null, list("pick" = REF(I))), "a valid ref dispatches")
	TEST_ASSERT_EQUAL(P.last_action, "pick", "the pick row ran")
	TEST_ASSERT_EQUAL(P.last_args["pick"], I, "the handler got the located object")
	TEST_ASSERT(islist(P.last_args[TOPIC_HREF]), "the raw href_list rides along")

	// A ref of the wrong type, or to nothing, is rejected before the handler runs.
	P.last_action = null
	TEST_ASSERT_NULL(topic_dispatch(P, null, list("pick" = REF(S))), "a wrong-type ref is rejected")
	TEST_ASSERT_NULL(P.last_action, "the handler did not run for a wrong-type ref")
	var/dangling = topic_dispatch(P, null, list("pick" = "\[0x21ffffff]"))
	TEST_ASSERT_NULL(dangling, "a dangling ref is rejected")
	TEST_ASSERT_NULL(P.last_action, "the handler did not run for a dangling ref")

	// A declared source: only objects in the pool resolve.
	rel_clear(P, nameof(P.pool))
	TEST_ASSERT_NULL(topic_dispatch(P, null, list("pooled" = REF(I))), "a ref outside the declared source is rejected")
	rel_add(P, nameof(P.pool), I)
	TEST_ASSERT(topic_dispatch(P, null, list("pooled" = REF(I))), "a ref inside the declared source resolves")
	TEST_ASSERT_EQUAL(P.last_args["pooled"], I, "pooled ref located")

	// Typed args.
	TEST_ASSERT(topic_dispatch(P, null, list("set" = "1", "amount" = "12", "label" = "abcdefgh")), "set dispatches")
	TEST_ASSERT_EQUAL(P.last_args["amount"], 12, "TOPIC_NUM converts")
	TEST_ASSERT_EQUAL(P.last_args["label"], "abcd", "TOPIC_TEXT cuts to its max length")
	topic_dispatch(P, null, list("set" = "1", "amount" = "lots"))
	TEST_ASSERT_NULL(P.last_args["amount"], "a non-number TOPIC_NUM is null")
	TEST_ASSERT_NULL(P.last_args["label"], "an absent TOPIC_TEXT is null")

	// "key=value" rows win over a bare key row.
	topic_dispatch(P, null, list("action" = "special"))
	TEST_ASSERT_EQUAL(P.last_action, "special", "the key=value row matched")
	topic_dispatch(P, null, list("action" = "other"))
	TEST_ASSERT_EQUAL(P.last_action, "action", "the bare key row matched")

	// Unknown hrefs match nothing.
	P.last_action = null
	TEST_ASSERT_NULL(topic_dispatch(P, null, list("nonsense" = "1")), "unknown keys match nothing")
	TEST_ASSERT_NULL(P.last_action, "nothing ran")

	// Rights: a user without a holder cannot run a TOPIC_RIGHTS row.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT_NULL(topic_dispatch(P, H, list("admin_only" = "1")), "rights are checked")
	TEST_ASSERT_NULL(P.last_action, "the rights-gated handler did not run")

	// Inheritance and override.
	var/datum/dq_topic_probe/child/C = new
	topic_dispatch(C, null, list("set" = "1", "amount" = "3"))
	TEST_ASSERT_EQUAL(C.last_action, "set", "a subtype inherits its parent's rows")
	topic_dispatch(C, null, list("pick" = REF(I)))
	TEST_ASSERT_EQUAL(C.last_action, "child_pick", "a subtype row replaces its parent's for the same key")

	// Topic() is the dispatcher.
	P.last_action = null
	P.Topic(null, list("action" = "special"))
	TEST_ASSERT_EQUAL(P.last_action, "special", "Topic() dispatches")

	qdel(P)
	qdel(C)

/// topic_ask() handed a handler's args list finds the raw href_list inside it.
/datum/unit_test/dq_sys_topic_ask_unwraps

/datum/unit_test/dq_sys_topic_ask_unwraps/Run()
	var/datum/dq_topic_probe/P = new
	var/list/href = list("set" = "1", "rerun_answer_k1" = "42")
	var/list/handler_args = list()
	handler_args[TOPIC_HREF] = href
	TEST_ASSERT_EQUAL(P.topic_rerun_ask(null, handler_args, "k1", /datum/prompt/number, list()), "42", "a re-run answer is read from the raw href_list")
	qdel(P)

/// admin_can() is the single rights primitive: a null or holder-less subject holds no rights, check_rights_for()
/// is its alias, and a denial through admin_require() is refused (and audited) without reading usr.
/datum/unit_test/dq_admin_can
	var/client/fake_client

/datum/unit_test/dq_admin_can/Run()
	TEST_ASSERT(!admin_can(null, R_ADMIN), "admin_can(null) must deny")
	TEST_ASSERT(!admin_can(null, R_NONE), "admin_can(null, R_NONE) must deny: no client is not an admin")
	TEST_ASSERT(!check_rights_for(null, R_ADMIN), "check_rights_for must alias admin_can")
	TEST_ASSERT(!admin_require(null, R_BAN, "dq_admin_can test"), "admin_require(null) must deny")
