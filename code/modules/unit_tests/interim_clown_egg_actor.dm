/// Query dispatch is the controlled boundary: no volunteer prompts leave this fixture.
/datum/ghost_query/hellclown/interim_dispatch_probe
	var/query_calls = 0

/datum/ghost_query/hellclown/interim_dispatch_probe/query()
	query_calls++

/obj/structure/ghost_pod/manual/clegg/interim_actor_probe
	ghost_query_type = /datum/ghost_query/hellclown/interim_dispatch_probe
	var/visible_text_seen
	var/visible_calls = 0

/obj/structure/ghost_pod/manual/clegg/interim_actor_probe/visible_message(message, blind_message, list/exclude_mobs, range = world.view, runemessage = "")
	visible_text_seen = message
	visible_calls++
	return ..()

/// The real clown-egg trigger retains its warning, actor position and owned query transaction.
/datum/unit_test/interim_clown_egg_trigger_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/structure/ghost_pod/manual/clegg/interim_actor_probe/pod = allocate(/obj/structure/ghost_pod/manual/clegg/interim_actor_probe, T)
	TEST_ASSERT(!pod.busy && !pod.Q, "the actual egg starts without a pending query")
	pod.trigger(user)
	TEST_ASSERT(pod.busy, "the real parent trigger marks the egg busy")
	var/datum/ghost_query/hellclown/interim_dispatch_probe/query = pod.Q
	TEST_ASSERT(istype(query), "the real parent trigger creates the declared owned query")
	TEST_ASSERT_EQUAL(query.query_calls, 1, "the parent dispatches exactly one query without external volunteer prompts")
	TEST_ASSERT_EQUAL(pod.visible_calls, 1, "the parent displays exactly one egg-touch warning")
	TEST_ASSERT_EQUAL(pod.visible_text_seen, span_warning("\The [user] places their hand on the egg!"), "the original warning names the supplied operator and occupies the alert argument")
	pod.trigger(user)
	TEST_ASSERT_EQUAL(pod.Q, query, "a busy egg preserves its existing query")
	TEST_ASSERT_EQUAL(query.query_calls, 1, "a busy egg starts no extra query")
	TEST_ASSERT_EQUAL(pod.visible_calls, 1, "a busy egg adds no duplicate touch warning")
	qdel(pod)
	TEST_ASSERT(QDELETED(query), "deleting the egg disposes of its actual owned query")
