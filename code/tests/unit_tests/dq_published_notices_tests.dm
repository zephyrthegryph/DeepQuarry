// Notices that are declared with ACTION(... FIXED) and sent with PUBLISH: a listener on the entity hears the occurrence with the fields
// its sender gave. Each test is the behaviour an observer in the game depends on.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Records the notices it was told to observe.
/datum/dq_published_listener
	var/list/heard = list()

/datum/dq_published_listener/proc/heard_moved(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/moved/event = A
	heard += "[event.old_loc]/[event.forced]"

/datum/dq_published_listener/proc/heard_statchange(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/mob_statchange/event = A
	heard += "[event.old_stat]>[event.new_stat]"

/// Appends a row to the turf change's callbacks, as the loot panel and the material service do.
/datum/dq_published_listener/proc/heard_turf_change(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/turf_change/event = A
	event.post_change_callbacks += list(list(src, TYPE_PROC_REF(/datum/dq_published_listener, heard_turf_change)))

/// A movable that moves tells its observers where it came from and whether it was forced.
/datum/unit_test/dq_notice_moved_carries_old_loc

/datum/unit_test/dq_notice_moved_carries_old_loc/Run()
	var/turf/start = test_floor()
	var/turf/next = get_step(start, NORTH)
	var/obj/item/thing = allocate(/obj/item, start)
	var/datum/dq_published_listener/L = allocate(/datum/dq_published_listener)
	observe(thing, /datum/notice/moved, L, then(TYPE_PROC_REF(/datum/dq_published_listener, heard_moved)))
	thing.forceMove(next)
	TEST_ASSERT(("[start]/[TRUE]" in L.heard), "the notice carried the old loc and that a forceMove did it: [json_encode(L.heard)]")

/// A living mob's stat change reaches its observers with both stats.
/datum/unit_test/dq_notice_statchange_carries_both_stats

/datum/unit_test/dq_notice_statchange_carries_both_stats/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/dq_published_listener/L = allocate(/datum/dq_published_listener)
	observe(H, /datum/notice/mob_statchange, L, then(TYPE_PROC_REF(/datum/dq_published_listener, heard_statchange)))
	var/old_stat = H.stat
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT_EQUAL(L.heard.len, 1, "one occurrence reached the observer: [json_encode(L.heard)]")
	TEST_ASSERT_EQUAL(L.heard[1], "[old_stat]>[UNCONSCIOUS]", "the notice carried the old and the new stat")

/// The sender of a turf change reads, once PUBLISH returns, the callbacks its handlers appended (ChangeTurf runs them on the new turf).
/datum/unit_test/dq_notice_turf_change_returns_handler_callbacks

/datum/unit_test/dq_notice_turf_change_returns_handler_callbacks/Run()
	var/turf/T = test_floor()
	var/datum/dq_published_listener/L = allocate(/datum/dq_published_listener)
	observe(T, /datum/notice/turf_change, L, then(TYPE_PROC_REF(/datum/dq_published_listener, heard_turf_change)))
	var/list/callbacks = list()
	TEST_ASSERT(WANTS(T, /datum/notice/turf_change), "the observer makes the notice wanted")
	PUBLISH(T, turf_change, path = /turf/simulated/floor/plating, new_baseturfs = null, flags = NONE, post_change_callbacks = callbacks)
	TEST_ASSERT_EQUAL(length(callbacks), 1, "the handler's row is in the list the sender passed")
	TEST_ASSERT(callbacks[1][1] == L, "and it names the handler's owner")

/// A robot's belly overlay fullness comes from its robot belly: a class the sleeper does not show is the chassis' own.
/datum/unit_test/dq_notice_robot_belly_display_fullness_passes_other_classes

/datum/unit_test/dq_notice_robot_belly_display_fullness_passes_other_classes/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/datum/robot_belly/B = R.add_robot_belly()
	TEST_ASSERT(B, "the robot has a belly")
	TEST_ASSERT_EQUAL(B.display_fullness("stomach", 2), 2, "only the sleeper class is adjusted")
	TEST_ASSERT_EQUAL(R.belly_display_fullness("stomach"), R.vore_fullness_ex["stomach"] || 0, "the chassis' accessor asks its belly and gets the fullness back")

#endif
