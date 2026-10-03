/// The probe supplies a different native ambient mob while invoking the actual evaluator.
/obj/interim_sdql_actor_probe
	var/datum/SDQL2_query/query
	var/resolved_actor

/obj/interim_sdql_actor_probe/Click(location, control, params)
	resolved_actor = world.SDQL_var(null, list("usr"), 1, src, FALSE, query)

/datum/unit_test/interim_sdql_query_actor_context/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/actor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/bystander = allocate(/mob/living/carbon/human, T)
	var/datum/SDQL2_query/system_query = allocate(/datum/SDQL2_query, list())
	var/datum/SDQL2_query/query = allocate(/datum/SDQL2_query, list(), FALSE, TRUE, system_query.options, FALSE, actor)
	TEST_ASSERT_EQUAL(query.requester, actor, "the actual query constructor stores its supplied actor relation")
	var/obj/interim_sdql_actor_probe/probe = allocate(/obj/interim_sdql_actor_probe, T)
	rel_set(probe, nameof(probe.query), query)
	km_synthetic_click(bystander, probe)
	TEST_ASSERT_EQUAL(probe.resolved_actor, actor, "the actual usr expression resolves the query actor instead of its ambient caller")
	TEST_ASSERT_EQUAL(world.SDQL_var(null, list("src"), 1, probe, FALSE, query), probe, "the actual src expression retains the selected source object")
	TEST_ASSERT_NULL(world.SDQL_var(null, list("marked"), 1, probe, FALSE, query), "a real actor without an admin client has no marked datum")
	TEST_ASSERT_EQUAL(world.SDQL_var(world, list("usr"), 1, probe, FALSE, query), actor, "the query's actual usr token remains available when evaluating world scope")
	TEST_ASSERT_NULL(system_query.requester, "an actual query without an actor has no requester")
	rel_set(probe, nameof(probe.query), system_query)
	km_synthetic_click(bystander, probe)
	TEST_ASSERT_NULL(probe.resolved_actor, "an actorless query cannot adopt the unrelated ambient caller")
	TEST_ASSERT_NULL(world.SDQL_var(null, list("marked"), 1, probe, FALSE, system_query), "an actorless query safely has no marked datum")
	TEST_ASSERT_NULL(world.SDQL_var(null, list("usr"), 1, probe, FALSE, null), "an evaluation without query context cannot inherit an ambient actor")
