// The engine pieces the occupant pods brought (doc/rewrite/intended_changes.md, "Medical pods"): a while_slotted() entry gated by when() on the
// side that declares it, a slotted contribution that reads a var of that side, holds_status(), and the stat clock_rate_bio reaching the body's stasis.

/// A pod whose occupant runs at `rate` and sleeps while it is `working`.
/obj/machinery/dq_pod_fixture
	name = "pod fixture"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_OFF
	var/working = TRUE
	var/rate = 0.5

TRACKED(/obj/machinery/dq_pod_fixture, working)
TRACKED(/obj/machinery/dq_pod_fixture, rate)

CAPABILITIES(/obj/machinery/dq_pod_fixture)
	occupant_pod(OCCUPANT_SLOT_TEST_FIXTURE)
	when(nameof(working), while_slotted(OCCUPANT_SLOT_TEST_FIXTURE, contributes(STAT_CLOCK_RATE_BIO, nameof(rate)), holds_status(STAT_SLEEPING), on = ON_CONTENTS))

/// The same pod, leaving to the south.
/obj/machinery/dq_pod_fixture/south_exit

CAPABILITIES(/obj/machinery/dq_pod_fixture/south_exit)
	configure(occupant_pod(OCCUPANT_SLOT_TEST_FIXTURE, exit_to = SOUTH))

/datum/unit_test/dq_medpod_lib
	abstract_type = /datum/unit_test/dq_medpod_lib

/datum/unit_test/dq_medpod_lib/Run()
	test_driver_begin()
	run_lib()
	test_driver_end()

/datum/unit_test/dq_medpod_lib/proc/run_lib()
	return

/// The scope follows the gate and the value: in, the rate holds and the occupant sleeps; a new rate re-applies; off, both go; out, nothing is left.
/datum/unit_test/dq_medpod_lib/gated_slot_scope
/datum/unit_test/dq_medpod_lib/gated_slot_scope/run_lib()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/machinery/dq_pod_fixture/pod = allocate(/obj/machinery/dq_pod_fixture, T)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	TEST_ASSERT(occupant_enter(pod, H), "setup: in")
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 0.5, "the occupant's biology runs at the pod's rate")
	TEST_ASSERT(H.has_status(STAT_SLEEPING), "and they sleep")
	test_time(1)
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0.5, "the rate is the body's stasis")
	pod.set_rate(0.1)
	test_time(1)
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 0.1, "a new rate re-applies the scope")
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0.9, "and deepens the stasis")
	pod.set_working(FALSE)
	test_time(1)
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 1, "a pod that stops working lets go of the rate")
	TEST_ASSERT(!H.has_status(STAT_SLEEPING), "and of the sleep")
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0, "no stasis")
	pod.set_working(TRUE)
	test_time(1)
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 0.1, "working again, it holds again")
	occupant_eject(pod)
	test_time(1)
	TEST_ASSERT_EQUAL(H.clock_rate_bio, 1, "out of the pod, nothing holds the rate")
	TEST_ASSERT(!H.has_status(STAT_SLEEPING), "nor the sleep")
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0, "nor the stasis")

/// The rate a stasis level stands for.
/datum/unit_test/dq_medpod_lib/stasis_levels_for_rates
/datum/unit_test/dq_medpod_lib/stasis_levels_for_rates/run_lib()
	TEST_ASSERT_NULL(stasis_type_for_rate(1), "full speed: none")
	TEST_ASSERT_EQUAL(stasis_type_for_rate(0.5), /datum/body_effect/stasis/light, "half speed: light")
	TEST_ASSERT_EQUAL(stasis_type_for_rate(0.2), /datum/body_effect/stasis/moderate, "a fifth: moderate")
	TEST_ASSERT_EQUAL(stasis_type_for_rate(0.1), /datum/body_effect/stasis/deep, "a tenth: deep")
	TEST_ASSERT_EQUAL(stasis_type_for_rate(0.01), /datum/body_effect/stasis/complete, "a hundredth: complete")
	TEST_ASSERT_EQUAL(stasis_type_for_rate(0), /datum/body_effect/stasis/total, "stopped: total")
	TEST_ASSERT_EQUAL(stasis_type_for_rate(0.3), /datum/body_effect/stasis/light, "between two levels: the shallower")

/// A pod's occupant leaves toward exit_to when that tile is open, else onto the pod's own tile; never into a wall.
/datum/unit_test/dq_medpod_lib/exit_never_into_a_wall
/datum/unit_test/dq_medpod_lib/exit_never_into_a_wall/run_lib()
	var/turf/here = locate(run_loc_floor_bottom_left.x + 1, run_loc_floor_bottom_left.y + 1, run_loc_floor_bottom_left.z)
	var/turf/south = get_step(here, SOUTH)
	var/obj/machinery/dq_pod_fixture/south_exit/pod = allocate(/obj/machinery/dq_pod_fixture/south_exit, here)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, here)
	TEST_ASSERT(occupant_enter(pod, H), "setup: in")
	occupant_eject(pod)
	TEST_ASSERT_EQUAL(H.loc, south, "an open tile to the south is where they leave")
	TEST_ASSERT(occupant_enter(pod, H), "setup: in again")
	south.ChangeTurf(/turf/simulated/wall)
	occupant_eject(pod)
	TEST_ASSERT_EQUAL(H.loc, here, "a wall to the south: the pod's own tile")
	south.ChangeTurf(/turf/simulated/floor)

