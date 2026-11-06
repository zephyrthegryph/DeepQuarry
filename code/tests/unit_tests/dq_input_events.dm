// An input event borrows its actor and target for the few ticks it waits in the inbox (/datum/input_event is a reviewed transient type in
// tools/ci/lint_scopes.toml). The borrow is checked where it is used: when the event resolves, gate() treats a deleted actor or target as
// stale, and nothing acts.

/// A queued click whose actor was deleted while it waited: the drain refuses it as stale, and the clicked thing is never touched.
/datum/unit_test/dq_input_event_deleted_actor_is_dropped

/datum/unit_test/dq_input_event_deleted_actor_is_dropped/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/structure/closet/dq_actor_probe/P = allocate(/obj/structure/closet/dq_actor_probe, run_loc_floor_bottom_left)
	GLOB.dq_actor_calls.Cut()
	var/datum/input_event/click/E = new(H, P, null, null, "left=1")
	qdel(H, TRUE)
	TEST_ASSERT_EQUAL(E.gate(), /datum/msg/input/stale_actor, "the gate sees the deleted actor")
	var/stale_before = SSinput.dropped_stale
	SSinput.run_event(E, TRUE)
	TEST_ASSERT_EQUAL(SSinput.dropped_stale, stale_before + 1, "the drain counted the event as stale")
	TEST_ASSERT(!length(GLOB.dq_actor_calls), "and nothing acted on the probe: [json_encode(GLOB.dq_actor_calls)]")

/// The same for a deleted target.
/datum/unit_test/dq_input_event_deleted_target_is_dropped

/datum/unit_test/dq_input_event_deleted_target_is_dropped/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/structure/closet/dq_actor_probe/P = allocate(/obj/structure/closet/dq_actor_probe, run_loc_floor_bottom_left)
	GLOB.dq_actor_calls.Cut()
	var/datum/input_event/click/E = new(H, P, null, null, "left=1")
	qdel(P, TRUE)
	TEST_ASSERT_EQUAL(E.gate(), /datum/msg/input/stale_target, "the gate sees the deleted target")
	var/stale_before = SSinput.dropped_stale
	SSinput.run_event(E, TRUE)
	TEST_ASSERT_EQUAL(SSinput.dropped_stale, stale_before + 1, "the drain counted the event as stale")
	TEST_ASSERT(!length(GLOB.dq_actor_calls), "and nothing acted: [json_encode(GLOB.dq_actor_calls)]")
