// The tag menu's and the ticket lists' links name ops of /datum/admins: each key resolves to an op and acts. A clientless fixture holder.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/admins/dq_dead_topic_fixture

/datum/admins/dq_dead_topic_fixture/op_topic_actor_ok(mob/actor)
	return TRUE

/datum/admins/dq_dead_topic_fixture/op_topic_token_ok(mob/actor, token)
	return TRUE

/datum/unit_test/om/dq_admin_dead_topic_actions

/datum/unit_test/om/dq_admin_dead_topic_actions/proc/click(mob/actor, datum/admins/holder, key, list/values = null, authority = AUTH_ADMIN)
	var/list/arg_values = list()
	arg_values[OP_TOPIC_HREF] = list("admin_token" = "test")
	for(var/k in values)
		arg_values[k] = values[k]
	return op_perform_by_key(actor, holder, null, key, ORIGIN_UI, authority, FALSE, arg_values)

/datum/unit_test/om/dq_admin_dead_topic_actions/run_om(list/made)
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/target = allocate(/mob/living, run_loc_floor_bottom_left)
	var/fixture_key = "dq_admin_dead_topic_actions"
	set_global("admin_datums", GLOB.admin_datums.Copy())
	set_global("deadmins", GLOB.deadmins.Copy())
	var/datum/admins/dq_dead_topic_fixture/holder = allocate(/datum/admins/dq_dead_topic_fixture, list(), fixture_key)
	GLOB.admin_datums -= fixture_key
	// MARK sets the marked datum
	var/datum/op_result/marked = click(actor, holder, "mark_datum", list("mark_datum" = target))
	TEST_ASSERT_EQUAL(marked?.outcome, ACT_COMMITTED, "MARK runs")
	TEST_ASSERT_EQUAL(holder.marked_datum(), target, "MARK sets the admin's marked datum")
	// UNTAG removes the tag
	holder.add_tagged_datum(target)
	TEST_ASSERT(LAZYFIND(holder.tagged_datums, target), "the datum is tagged")
	var/datum/op_result/untagged = click(actor, holder, "del_tag", list("del_tag" = target))
	TEST_ASSERT_EQUAL(untagged?.outcome, ACT_COMMITTED, "UNTAG runs")
	TEST_ASSERT(!LAZYFIND(holder.tagged_datums, target), "UNTAG removes the tag")
	// rights: an actor without admin authority is refused
	holder.add_tagged_datum(target)
	var/datum/op_result/refused = click(actor, holder, "del_tag", list("del_tag" = target), AUTH_PHYSICAL)
	TEST_ASSERT_EQUAL(refused?.outcome, ACT_REFUSED, "UNTAG refuses an actor without rights")
	TEST_ASSERT_EQUAL(refused?.reason, /datum/msg/req_no_rights, "with the rights message, so the key resolved to an op")
	TEST_ASSERT(LAZYFIND(holder.tagged_datums, target), "and the tag stays")

#endif
