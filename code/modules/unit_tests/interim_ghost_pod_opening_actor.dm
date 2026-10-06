/// Isolate volunteer dispatch while keeping the real query-completion event and pod effects.
/datum/ghost_query/interim_operator_probe/query()
	return

/obj/structure/ghost_pod/manual/corgi/interim_operator_probe
	ghost_query_type = /datum/ghost_query/interim_operator_probe

/obj/structure/ghost_pod/manual/cursedblade/interim_operator_probe
	ghost_query_type = /datum/ghost_query/interim_operator_probe

/// A winner is not the opener: the accepted query retains its actual initiating operator.
/datum/unit_test/interim_ghost_pod_opening_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/operator = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	var/mob/observer/dead/winner = allocate(/mob/observer/dead, T)
	var/obj/structure/ghost_pod/manual/corgi/interim_operator_probe/pod = allocate(/obj/structure/ghost_pod/manual/corgi/interim_operator_probe, T)
	pod.trigger(operator)
	TEST_ASSERT_EQUAL(pod.opening_actor, operator, "the real trigger captures its original operator")
	pod.trigger(other)
	TEST_ASSERT_EQUAL(pod.opening_actor, operator, "a busy refusal cannot replace the accepted operator")
	var/datum/ghost_query/query = pod.Q
	rel_add(query, nameof(query.candidates), winner)
	PUBLISH_LEGACY(query, /datum/notice/ghost_query_complete)
	own_turf_contents(T)
	TEST_ASSERT(pod.used && !pod.busy, "the real completion opens the pod and clears busy state")
	TEST_ASSERT(QDELETED(query), "completion disposes of the real owned query")
	TEST_ASSERT_NULL(pod.Q, "completion clears the owned query reference")
	var/mob/living/simple_mob/animal/passive/dog/corgi/corgi = locate_within(T, /mob/living/simple_mob/animal/passive/dog/corgi)
	TEST_ASSERT_NOTNULL(corgi, "the real completion creates its actual corgi occupant")
	TEST_ASSERT_EQUAL(pod.opening_actor, operator, "completion retains the original operator rather than the winning ghost")
	qdel(operator)
	TEST_ASSERT_NULL(pod.opening_actor, "deleting the operator clears its declared relation")

/// A clientless observer can inhabit the actual cursed sword through the real completion path.
/datum/unit_test/interim_cursedblade_opening_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/operator = allocate(/mob/living/carbon/human, T)
	var/mob/observer/dead/winner = allocate(/mob/observer/dead, T)
	var/obj/structure/ghost_pod/manual/cursedblade/interim_operator_probe/pod = allocate(/obj/structure/ghost_pod/manual/cursedblade/interim_operator_probe, T)
	pod.trigger(operator)
	var/datum/ghost_query/query = pod.Q
	rel_add(query, nameof(query.candidates), winner)
	PUBLISH_LEGACY(query, /datum/notice/ghost_query_complete)
	own_turf_contents(T)
	TEST_ASSERT(pod.used && !pod.busy && !pod.density, "the real sword completion opens its physical spawnpoint")
	var/obj/item/melee/cursedblade/sword = locate_within(T, /obj/item/melee/cursedblade)
	TEST_ASSERT_NOTNULL(sword, "the real completion creates the actual cursed sword")
	TEST_ASSERT_EQUAL(length(sword.voice_mobs), 1, "the real observer inhabitation creates one owned voice mob")
	TEST_ASSERT_EQUAL(pod.opening_actor, operator, "the opener remains distinct from the inhabiting observer")
	TEST_ASSERT(QDELETED(query), "the completed query is disposed")
