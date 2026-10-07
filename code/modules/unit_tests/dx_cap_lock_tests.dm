// The lock capability (code/datums/capabilities/library/lock.dm).

/obj/cap_fixture/lock/capabilities()
	. = ..()
	. += cap_lock(access = list(ACCESS_SECURITY))
	. += cap_cover(open_tool = BY_HAND, needs = req_clear(LOCK))

/// A swipe with access toggles the lock, which gates locked_by = LOCK entries; no access is refused.
/datum/unit_test/dx_cap_lock_swipe/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lock/A = allocate(/obj/cap_fixture/lock, T)
	var/obj/item/card/id/good = allocate(/obj/item/card/id, T)
	var/obj/item/card/id/bad = allocate(/obj/item/card/id, T)
	good.access = list(ACCESS_SECURITY)
	bad.access = list()
	var/datum/interaction/capability/swipe = cap_test_entry(A, "hand:Lock:cap_lock_toggle")
	var/datum/interaction/capability/cover_entry = cap_test_entry(A, "cover:[BY_HAND]")
	TEST_ASSERT_NOTNULL(swipe, "the lock offers a swipe entry")
	TEST_ASSERT(swipe.is_meant(H, A, good), "an ID is meant")
	TEST_ASSERT(swipe.is_meant(H, A, null), "an empty hand is meant by an alt-click (the actor's own access)")
	set_global("op_gesture_now", GESTURE_CLICK)
	TEST_ASSERT(swipe.is_meant(H, A, good), "a click holding an ID is a swipe")
	TEST_ASSERT(!swipe.is_meant(H, A, null), "a plain click with an empty hand is not")
	set_global("op_gesture_now", null)
	TEST_ASSERT("It is unlocked." in caps_examine(A, H), "examine says unlocked")
	TEST_ASSERT_EQUAL(swipe.display_name(H, A), "Lock", "named Lock while unlocked")

	// No access: refused with the reason, nothing changes.
	var/result = cap_dispatch(new /datum/dispatch_context(H, A, bad, swipe))
	TEST_ASSERT_EQUAL(result, UI_REFUSED, "an ID without access is refused")
	TEST_ASSERT(!is_locked(A), "and the lock stays open")

	TEST_ASSERT(H.put_in_active_hand(good), "the human holds the good ID")
	TEST_ASSERT(swipe.perform(H, A, good), "the good ID locks it")
	TEST_ASSERT(is_locked(A), "locked")
	TEST_ASSERT(capability_bits(A) & CAP_LOCKED, "the bit is set")
	TEST_ASSERT_EQUAL(swipe.display_name(H, A), "Unlock", "named Unlock while locked")
	TEST_ASSERT("It is locked." in caps_examine(A, H), "examine says locked")
	TEST_ASSERT_EQUAL(cover_entry.why_not(H, A, null), "it's locked", "a locked_by = LOCK entry refuses")
	refresh_flush()
	TEST_ASSERT(cap_test_has_layer(A, "locked"), "the locked layer is drawn")
	TEST_ASSERT(swipe.perform(H, A, good), "the good ID unlocks it")
	TEST_ASSERT(!is_locked(A), "unlocked")
	TEST_ASSERT_NULL(cover_entry.why_not(H, A, null), "the cover works again")
	refresh_flush()
	TEST_ASSERT(!cap_test_has_layer(A, "locked"), "the layer is gone")

/// The lock is electronic: it refuses while the holder is broken.
/datum/unit_test/dx_cap_lock_broken/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lock/A = allocate(/obj/cap_fixture/lock, T)
	var/obj/item/card/id/good = allocate(/obj/item/card/id, T)
	good.access = list(ACCESS_SECURITY)
	var/datum/interaction/capability/swipe = cap_test_entry(A, "hand:Lock:cap_lock_toggle")
	cap_set(A, CAP_BROKEN, TRUE)
	TEST_ASSERT_EQUAL(swipe.why_not(H, A, good), "it's broken", "a broken lock refuses")

/// The holder's own req_access (a map edit) overrides the capability's type default.
/datum/unit_test/dx_cap_lock_instance_access/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/lock/A = allocate(/obj/cap_fixture/lock, T)
	var/obj/item/card/id/sec = allocate(/obj/item/card/id, T)
	var/obj/item/card/id/eng = allocate(/obj/item/card/id, T)
	sec.access = list(ACCESS_SECURITY)
	eng.access = list(ACCESS_ENGINE)
	A.req_access = list(ACCESS_ENGINE)
	var/datum/interaction/capability/swipe = cap_test_entry(A, "hand:Lock:cap_lock_toggle")
	TEST_ASSERT_EQUAL(cap_dispatch(new /datum/dispatch_context(H, A, sec, swipe)), UI_REFUSED, "the type default no longer opens it")
	TEST_ASSERT(!is_locked(A), "still unlocked")
	TEST_ASSERT_NOTEQUAL(cap_dispatch(new /datum/dispatch_context(H, A, eng, swipe)), UI_REFUSED, "the instance's access does")
	TEST_ASSERT(is_locked(A), "locked by the instance access")
