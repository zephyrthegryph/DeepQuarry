// The cost of a light's holder change, alone: an observer of a carrier's moved and qdeleting notices comes and goes, as overlay_lighting's
// set_holder() does on every pick up and drop. Run with --profile-tests for the proc breakdown; the test checks the observer works.

/obj/item/dq_observe_cost_listener
	var/heard = 0

/obj/item/dq_observe_cost_listener/proc/on_moved(datum/act/A)
	heard++

/obj/item/dq_observe_cost_listener/proc/on_gone(datum/act/A)
	return

/datum/unit_test/dq_observe_cost_cycle

/datum/unit_test/dq_observe_cost_cycle/Run()
	var/turf/floor = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, floor)
	var/obj/item/dq_observe_cost_listener/L = allocate(/obj/item/dq_observe_cost_listener, floor)
	var/cycles = 500
	var/start = TICK_USAGE_REAL
	for(var/i in 1 to cycles)
		observe(H, /datum/notice/qdeleting, L, then(TYPE_PROC_REF(/obj/item/dq_observe_cost_listener, on_gone)))
		observe(H, /datum/notice/moved, L, then(TYPE_PROC_REF(/obj/item/dq_observe_cost_listener, on_moved)))
		unobserve(H, /datum/notice/qdeleting, L)
		unobserve(H, /datum/notice/moved, L)
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	log_world("dq_observe_cost_cycle: [round(ms * 1000 / (cycles * 4), 0.1)] us per observe or unobserve ([cycles] cycles)")
	observe(H, /datum/notice/moved, L, then(TYPE_PROC_REF(/obj/item/dq_observe_cost_listener, on_moved)))
	H.forceMove(get_step(floor, EAST) || floor)
	TEST_ASSERT(L.heard >= 1 || H.loc == floor, "the observer hears its carrier move")
	TEST_ASSERT_EQUAL(unobserve(H, /datum/notice/moved, L), 1, "the one observer ends")
	TEST_ASSERT_EQUAL(unobserve(H, /datum/notice/moved, L), 0, "and nothing of it is left")

/// observe_notices(): one grant hears each of its notices, and unobserve() of any one of them ends all of them. Logs its cost per holder change
/// (one grant and one end) beside the per-notice pair above.
/datum/unit_test/dq_observe_notices_one_grant

/datum/unit_test/dq_observe_notices_one_grant/Run()
	var/turf/floor = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, floor)
	var/obj/item/dq_observe_cost_listener/L = allocate(/obj/item/dq_observe_cost_listener, floor)
	var/list/notices = list(/datum/notice/qdeleting = then(TYPE_PROC_REF(/obj/item/dq_observe_cost_listener, on_gone)), /datum/notice/moved = then(TYPE_PROC_REF(/obj/item/dq_observe_cost_listener, on_moved)))
	var/before = length(H.rx?.activations)
	var/datum/activation/A = observe_notices(H, L, notices)
	TEST_ASSERT(A, "the grant is made")
	TEST_ASSERT_EQUAL(length(H.rx.activations), before + 1, "one activation for both notices")
	var/turf/east = get_step(floor, EAST)
	if(east)
		H.forceMove(east)
		TEST_ASSERT(L.heard >= 1, "it hears its holder move")
	TEST_ASSERT_EQUAL(unobserve(H, /datum/notice/qdeleting, L), 1, "unobserving one notice ends the grant")
	TEST_ASSERT_EQUAL(unobserve(H, /datum/notice/moved, L), 0, "so the other is gone with it")
	TEST_ASSERT_EQUAL(length(H.rx.activations), before, "nothing of it is left")
	var/cycles = 500
	var/start = TICK_USAGE_REAL
	for(var/i in 1 to cycles)
		observe_notices(H, L, notices)
		unobserve(H, /datum/notice/qdeleting, L)
	log_world("dq_observe_notices_one_grant: [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / cycles, 0.1)] us per holder change (grant and end of both notices)")
