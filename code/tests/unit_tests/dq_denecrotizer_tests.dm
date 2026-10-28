// The denecrotizer used to unconditionally reset a revived simple_mob's
// sight/see_in_dark/see_invisible to initial() after reviving it -- clobbering
// whatever any other system (a growth stage, a signal handler reacting to the
// revival, ...) had legitimately set those to. It turns out /mob/living/revive()
// already resets those exact three vars via rejuvenate() (living.dm), so the
// denecrotizer's own reset was pure redundant duplicate work: it never actually
// changed those vars itself, so per "restore only what it changed" it had
// nothing of its own to restore, and the extra reset was simply removed. This
// test proves it by having something else set a custom see_in_dark in
// response to the revival and checking the denecrotizer doesn't stomp it.

/datum/unit_test/dq_denecrotizer_does_not_reclobber_sight_after_revive
	var/custom_see_in_dark = 7

/datum/unit_test/dq_denecrotizer_does_not_reclobber_sight_after_revive/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	TEST_ASSERT_NOTNULL(test_turf, "No mapped turf was available for the denecrotizer revival test.")

	var/mob/living/simple_mob/target = allocate(/mob/living/simple_mob, test_turf)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_turf)
	var/obj/item/denecrotizer/D = allocate(/obj/item/denecrotizer, test_turf)
	D.revive_time = 0
	D.set_charges(5)

	target.death()

	// Something else (a growth stage recomputing vision, a species change, a
	// signal handler, ...) reacts to the revival and sets a custom, non-default
	// see_in_dark. revive()'s own rejuvenate() already ran by the time this
	// signal fires (return_from_death() emits living_revived after resetting the senses).
	observe(target, /datum/notice/living_revived, src, then(PROC_REF(set_custom_see_in_dark)))

	// The op's wait (revive_time is 0) ends and its then() runs.
	D.ghostjoin_rez(target, user)
	test_time(2 SECONDS)

	TEST_ASSERT_EQUAL(target.see_in_dark, custom_see_in_dark, "the denecrotizer must not reset see_in_dark back to initial() after another system set a legitimate post-revival value")

	unobserve(target, /datum/notice/living_revived, src)

/datum/unit_test/dq_denecrotizer_does_not_reclobber_sight_after_revive/proc/set_custom_see_in_dark(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/source = N.target
	source.see_in_dark = custom_see_in_dark

/// basic_rez() (used for a plain, non-ghostjoin revival) must have the same fix.
/datum/unit_test/dq_denecrotizer_basic_rez_does_not_reclobber_sight
	var/custom_see_in_dark = 7

/datum/unit_test/dq_denecrotizer_basic_rez_does_not_reclobber_sight/Run()
	var/turf/test_turf = get_turf(run_loc_floor_bottom_left ? run_loc_floor_bottom_left : locate(1, 1, 1))
	var/mob/living/simple_mob/target = allocate(/mob/living/simple_mob, test_turf)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_turf)
	var/obj/item/denecrotizer/D = allocate(/obj/item/denecrotizer, test_turf)
	D.revive_time = 0
	D.set_charges(5)

	target.death()
	observe(target, /datum/notice/living_revived, src, then(PROC_REF(set_custom_see_in_dark)))

	// basic_rez() starts the op; its wait (revive_time is 0) ends and the then() runs.
	D.basic_rez(target, user)
	test_time(2 SECONDS)

	TEST_ASSERT_EQUAL(target.see_in_dark, custom_see_in_dark, "basic_rez must not reset see_in_dark back to initial() after another system set a legitimate post-revival value")

	unobserve(target, /datum/notice/living_revived, src)

/datum/unit_test/dq_denecrotizer_basic_rez_does_not_reclobber_sight/proc/set_custom_see_in_dark(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	var/mob/living/source = N.target
	source.see_in_dark = custom_see_in_dark
