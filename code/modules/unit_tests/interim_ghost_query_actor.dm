/// Observe callback arguments while chaining the actual client/eligibility refusals.
/datum/ghost_query/interim_actor_probe
	var/tmp/mob/observer/dead/reply_actor
	var/reply_response
	var/reply_calls = 0

/datum/ghost_query/interim_actor_probe/get_reply(mob/observer/dead/D, response)
	rel_set(src, nameof(reply_actor), D)
	reply_response = response
	reply_calls++
	return ..()

/obj/interim_ghost_query_alert_probe
	var/datum/tgui_alert/async/alert

/obj/interim_ghost_query_alert_probe/Click(location, control, params)
	alert.set_choice("I'm Sure")

/datum/unit_test/interim_ghost_query_async_actor/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/observer/dead/observer = allocate(/mob/observer/dead, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT_NULL(observer.client, "the real observer fixture cannot claim successful client-backed role admission")
	var/datum/ghost_query/interim_actor_probe/query = allocate(/datum/ghost_query/interim_actor_probe)
	test_driver_begin()
	var/datum/tgui_alert/async/first = allocate(/datum/tgui_alert/async, observer, "Test role", "Role", list("Yes", "No"), 0, TRUE, GLOB.tgui_always_state, TYPE_PROC_REF(/datum/ghost_query, get_reply), query, list(observer))
	first.set_choice("Yes")
	test_time(1)
	TEST_ASSERT_EQUAL(query.reply_calls, 1, "the actual async alert invokes the actual guarded query reply once")
	TEST_ASSERT_EQUAL(query.reply_actor, observer, "the actual async alert resolves the observer captured by the query")
	TEST_ASSERT_EQUAL(query.reply_response, "Yes", "the actual alert response follows the captured observer argument")
	TEST_ASSERT_EQUAL(length(query.candidates), 0, "the real clientless observer refusal adds no candidate")
	TEST_ASSERT_EQUAL(query.finished, FALSE, "the actual refusal does not finish the query")
	var/datum/tgui_alert/async/confirmation = allocate(/datum/tgui_alert/async, observer, "Confirm role", "Role", list("I'm Sure", "Nevermind"), 0, TRUE, GLOB.tgui_always_state, TYPE_PROC_REF(/datum/ghost_query, get_reply), query, list(observer))
	var/obj/interim_ghost_query_alert_probe/probe = allocate(/obj/interim_ghost_query_alert_probe, T)
	rel_set(probe, nameof(probe.alert), confirmation)
	km_synthetic_click(bystander, probe)
	test_time(1)
	TEST_ASSERT_EQUAL(query.reply_calls, 2, "the real confirmation async callback runs under an unrelated native click actor")
	TEST_ASSERT_EQUAL(query.reply_actor, observer, "confirmation keeps the captured observer instead of adopting the native bystander")
	TEST_ASSERT_EQUAL(query.reply_response, "I'm Sure", "the real confirmation response retains its exact argument position")
	TEST_ASSERT_EQUAL(length(query.candidates), 0, "the actual confirmation still refuses clientless admission")
	TEST_ASSERT_EQUAL(query.finished, FALSE, "refused confirmation leaves the actual query open")
	query.get_reply(null, "I'm Sure")
	TEST_ASSERT_EQUAL(query.reply_calls, 3, "the actual absent-actor reply reaches the guarded handler")
	TEST_ASSERT_NULL(query.reply_actor, "the absent actor remains absent at the actual reply guard")
	TEST_ASSERT_EQUAL(length(query.candidates), 0, "the actual absent-actor refusal adds no candidate")
	test_driver_end()

/datum/unit_test/interim_ghost_query_deleted_actor/Run()
	var/mob/observer/dead/observer = allocate(/mob/observer/dead, run_loc_floor_bottom_left)
	var/datum/ghost_query/interim_actor_probe/query = allocate(/datum/ghost_query/interim_actor_probe)
	test_driver_begin()
	var/datum/tgui_alert/async/alert = allocate(/datum/tgui_alert/async, observer, "Test role", "Role", list("I'm Sure", "Nevermind"), 0, TRUE, GLOB.tgui_always_state, TYPE_PROC_REF(/datum/ghost_query, get_reply), query, list(observer))
	qdel(observer)
	TEST_ASSERT(QDELETED(observer), "the captured real observer is actually deleted before answering")
	alert.set_choice("I'm Sure")
	test_time(1)
	TEST_ASSERT_EQUAL(alert.choice, "I'm Sure", "the actual async alert receives the real choice even after observer deletion")
	TEST_ASSERT_EQUAL(query.reply_calls, 0, "weak capture drops the actual callback for a deleted observer")
	TEST_ASSERT_EQUAL(length(query.candidates), 0, "a deleted observer cannot enter the actual candidate list")
	TEST_ASSERT_EQUAL(query.finished, FALSE, "the dropped callback leaves the actual query open")
	test_driver_end()
