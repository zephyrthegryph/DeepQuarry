/// Use the existing controlled query boundary while retaining actual passenger spawning.
/obj/structure/ghost_pod/manual/human/interim_operator_probe
	ghost_query_type = /datum/ghost_query/interim_operator_probe
	make_antag = FALSE
	allow_appearance_change = FALSE
	start_injured = FALSE

/// The manual passenger's original opener survives the winner's real completion path.
/datum/unit_test/interim_manual_passenger_opening_actor/Run()
	test_driver_begin()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/operator = allocate(/mob/living/carbon/human, get_step(T, EAST))
	var/mob/observer/dead/winner = allocate(/mob/observer/dead, T)
	var/obj/structure/ghost_pod/manual/human/interim_operator_probe/pod = allocate(/obj/structure/ghost_pod/manual/human/interim_operator_probe, T)
	pod.trigger(operator)
	var/datum/ghost_query/query = pod.Q
	TEST_ASSERT_NOTNULL(query, "the real manual pod starts an owned query")
	rel_add(query, nameof(query.candidates), winner)
	PUBLISH_LEGACY(query, /datum/notice/ghost_query_complete)
	own_turf_contents(T)
	TEST_ASSERT(pod.used && !pod.busy, "real completion opens the passenger pod")
	TEST_ASSERT(QDELETED(query), "real completion disposes of the pending query")
	var/mob/living/carbon/human/passenger = locate_within(T, /mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(passenger, "the real completion creates a human passenger")
	TEST_ASSERT(passenger != operator, "the passenger is distinct from the operator")
	TEST_ASSERT_EQUAL(passenger.loc, T, "the real passenger exits onto the pod's turf")
	TEST_ASSERT_EQUAL(pod.opening_actor, operator, "the completion retains its original opener rather than the winning ghost")
	TEST_ASSERT_NOTNULL(passenger.get_equipped_item(SLOT_ID_UNIFORM), "the real passenger spawn equips its selected uniform")
	TEST_ASSERT_NOTNULL(passenger.get_equipped_item(SLOT_ID_SHOES), "the real passenger spawn equips its selected shoes")
