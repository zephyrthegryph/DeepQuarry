// The shared needs checks (code/datums/capabilities/library/checks.dm) and ask_* re-validation with needs.

/obj/cap_fixture/chk_hand

/// The needs the fixture's checks run: conscious, then adjacent.
/proc/chk_test_needs()
	return list(GLOBAL_PROC_REF(chk_conscious), GLOBAL_PROC_REF(chk_adjacent))

/// A human whose restrained() the test flips.
/mob/living/carbon/human/chk_bindable
	var/bound = FALSE

/mob/living/carbon/human/chk_bindable/restrained()
	return bound

/datum/unit_test/dx_chk_checks/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	TEST_ASSERT_EQUAL(chk_alive(H, P, null), TRUE, "alive passes")
	TEST_ASSERT_EQUAL(chk_conscious(H, P, null), TRUE, "conscious passes")
	TEST_ASSERT_EQUAL(chk_capable(H, P, null), TRUE, "capable passes")
	TEST_ASSERT_EQUAL(chk_unrestrained(H, P, null), TRUE, "unrestrained passes")
	TEST_ASSERT_EQUAL(chk_adjacent(H, P, null), TRUE, "adjacent passes on the same turf")
	TEST_ASSERT_EQUAL(chk_near_subject(H, P, null), TRUE, "near subject passes")
	TEST_ASSERT_EQUAL(chk_on_turf(H, P, null), TRUE, "on a turf passes")
	TEST_ASSERT_EQUAL(chk_hand_free(H, P, null), TRUE, "empty hands pass")
	TEST_ASSERT_EQUAL(chk_held(H, P, null), "you are not holding it", "not held refuses")
	TEST_ASSERT_EQUAL(chk_carried(H, P, null), "you are not carrying it", "not carried refuses")
	H.put_in_active_hand(P)
	TEST_ASSERT_EQUAL(chk_held(H, P, null), TRUE, "held passes")
	TEST_ASSERT_EQUAL(chk_carried(H, P, null), TRUE, "carried passes")
	TEST_ASSERT_EQUAL(chk_on_turf(H, P, null), "it has to be on the ground", "a held item is not on a turf")
	P.forceMove(T)
	var/obj/item/storage/box/B = allocate(/obj/item/storage/box, T)
	P.forceMove(B)
	TEST_ASSERT_EQUAL(chk_on_turf(H, P, null), "it has to be on the ground", "an item in a box is not on a turf")
	TEST_ASSERT_EQUAL(chk_carried(H, P, null), "you are not carrying it", "a box on the floor is not carried")
	H.forceMove(run_loc_floor_top_right)
	TEST_ASSERT_EQUAL(chk_adjacent(H, B, null), "you are too far away", "adjacent refuses at range")
	TEST_ASSERT_EQUAL(chk_near_subject(H, B, null), "you are too far away", "near subject refuses at range")
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT_EQUAL(chk_conscious(H, B, null), "you are not conscious", "conscious refuses")
	TEST_ASSERT_EQUAL(chk_capable(H, B, null), "you can't do that right now", "capable refuses the unconscious (stat is part of it)")
	TEST_ASSERT_EQUAL(chk_alive(H, B, null), TRUE, "unconscious is still alive")
	H.set_stat(DEAD)
	TEST_ASSERT_EQUAL(chk_alive(H, B, null), "you are dead", "alive refuses when dead")
	var/mob/living/carbon/human/chk_bindable/Bd = allocate(/mob/living/carbon/human/chk_bindable, T)
	Bd.bound = TRUE
	TEST_ASSERT_EQUAL(chk_capable(Bd, B, null), "you can't do that right now", "capable refuses when restrained")
	TEST_ASSERT_EQUAL(chk_unrestrained(Bd, B, null), "you are restrained", "unrestrained refuses when restrained")

/datum/unit_test/dx_chk_entry_needs/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/chk_hand/F = allocate(/obj/cap_fixture/chk_hand, T)
	TEST_ASSERT_NULL(cap_needs_reason(F, H, null, chk_test_needs()), "global needs pass")
	H.forceMove(run_loc_floor_top_right)
	TEST_ASSERT_EQUAL(cap_needs_reason(F, H, null, chk_test_needs()), "you are too far away", "the second check refuses with its text")
	H.forceMove(T)
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT_EQUAL(cap_needs_reason(F, H, null, chk_test_needs()), "you are not conscious", "the first check refuses first")

/datum/unit_test/dx_chk_ask_revalidation/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/chk_hand/F = allocate(/obj/cap_fixture/chk_hand, T)
	var/datum/dispatch_context/ctx = ask_context_needs(new /datum/dispatch_context(H, F), chk_test_needs())
	TEST_ASSERT(ask_still_valid(ctx), "valid while every need holds")
	H.forceMove(run_loc_floor_top_right)
	TEST_ASSERT(!ask_still_valid(ctx), "the needs re-check and refuse after moving away")
	TEST_ASSERT_EQUAL(ctx.invalid_reason(), "you are too far away", "with the check's text")
	H.forceMove(T)
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT(!ask_still_valid(ctx), "the needs re-run on the answer")

/datum/unit_test/dx_chk_ask_explicit_needs/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/pen/P = allocate(/obj/item/pen, T)
	var/datum/dispatch_context/ctx = ask_context(H, P, null, list(GLOBAL_PROC_REF(chk_capable), GLOBAL_PROC_REF(chk_near_subject)))
	TEST_ASSERT_EQUAL(length(ctx.ask_needs), 2, "the explicit needs are captured flat")
	TEST_ASSERT(ask_still_valid(ctx), "valid while the needs pass")
	H.forceMove(run_loc_floor_top_right)
	TEST_ASSERT(!ask_still_valid(ctx), "refused once near-subject fails")
	H.forceMove(T)
	TEST_ASSERT(ask_still_valid(ctx), "valid again in reach")
	H.set_stat(UNCONSCIOUS)
	TEST_ASSERT(!ask_still_valid(ctx), "refused once the user is out")
