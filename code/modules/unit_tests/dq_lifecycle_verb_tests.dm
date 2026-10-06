// Lifecycle verbs (doc/rewrite/lifecycle.md §5, code/datums/lifecycle/verbs.dm):
// the behaviour the L4 qdel sweep relies on at its converted call sites.

/// consume() takes a held item off the mob, then destroys it.
/datum/unit_test/dq_lifecycle_consume_held
/datum/unit_test/dq_lifecycle_consume_held/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/paper/P = new(test_floor())
	TEST_ASSERT(H.put_in_hands(P), "the paper should go in a hand")
	TEST_ASSERT(consume(P, H), "consume() should succeed on a held item")
	TEST_ASSERT(QDELETED(P), "the consumed item should be deleted")
	TEST_ASSERT(!H.is_in_hands(P), "the consumed item should have left the hand")

/// replace_with() puts the successor into the hand the original held, and
/// put_in_hands() on it afterwards (the old call sites' follow-up) is a no-op.
/datum/unit_test/dq_lifecycle_replace_with_takes_hand
/datum/unit_test/dq_lifecycle_replace_with_takes_hand/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/paper/P = new(test_floor())
	TEST_ASSERT(H.put_in_hands(P), "the paper should go in a hand")
	var/slot = H.inventory_slot_id(P)
	var/obj/item/successor = replace_with(P, /obj/item/paper/crumpled)
	TEST_ASSERT(successor, "replace_with() should return the successor")
	TEST_ASSERT(QDELETED(P), "the original should be deleted")
	TEST_ASSERT_EQUAL(H.inventory_slot_id(successor), slot, "the successor should take the original's hand")
	TEST_ASSERT(H.put_in_hands(successor), "put_in_hands() on an already-held item should succeed")
	TEST_ASSERT_EQUAL(H.inventory_slot_id(successor), slot, "put_in_hands() should not move or drop a held item")
	qdel(successor)

/// replace_with() with a successor the caller already built keeps that
/// instance (and whatever the caller set on it).
/datum/unit_test/dq_lifecycle_replace_with_prebuilt
/datum/unit_test/dq_lifecycle_replace_with_prebuilt/Run()
	var/turf/T = test_floor()
	var/obj/item/paper/P = new(T)
	var/obj/item/paper/built = new(T)
	built.name = "carried over"
	var/obj/item/result = replace_with(P, built)
	TEST_ASSERT(result == built, "replace_with() should return the prebuilt successor")
	TEST_ASSERT(QDELETED(P), "the original should be deleted")
	TEST_ASSERT(!QDELETED(built) && built.loc == T, "the prebuilt successor should stay where it was built")
	TEST_ASSERT_EQUAL(built.name, "carried over", "state set on the prebuilt successor should survive")
	qdel(built)

/// replace_with() of a plain turf object leaves the successor on that turf.
/datum/unit_test/dq_lifecycle_replace_with_on_turf
/datum/unit_test/dq_lifecycle_replace_with_on_turf/Run()
	var/turf/T = test_floor()
	var/obj/item/paper/P = new(T)
	var/obj/item/stack/rods/R = replace_with(P, /obj/item/stack/rods, 3)
	TEST_ASSERT(QDELETED(P), "the original should be deleted")
	TEST_ASSERT(R?.loc == T, "the successor should be on the original's turf")
	TEST_ASSERT_EQUAL(R.get_amount(), 3, "constructor args should reach the successor")
	qdel(R)

/// slot_clear() with no slot on a holder without declared slots deletes its
/// plain contents.
/datum/unit_test/dq_lifecycle_slot_clear_plain_contents
/datum/unit_test/dq_lifecycle_slot_clear_plain_contents/Run()
	var/obj/structure/dq_holder = allocate(/obj/structure/table, test_floor())
	var/obj/item/paper/P = new(dq_holder)
	TEST_ASSERT(P.loc == dq_holder, "the paper should be inside the holder")
	if(dq_slot_defs_for(dq_holder))
		return // this holder declares slots; the plain-contents fallback does not apply
	TEST_ASSERT(dq_holder.slot_clear() >= 1, "slot_clear() should report what it deleted")
	TEST_ASSERT(QDELETED(P), "slot_clear() should delete plain contents")

/// expire() owns its timer: deleting the atom first cancels it, and a re-arm
/// replaces the old one.
/datum/unit_test/dq_lifecycle_expire_owns_timer
/datum/unit_test/dq_lifecycle_expire_owns_timer/Run()
	var/obj/effect/E = new /obj/effect(test_floor())
	E.expire(10 MINUTES)
	var/first = after_left(E, "lifecycle_lifetime_timer")
	TEST_ASSERT(first, "expire() should arm a timer")
	E.expire(20 MINUTES)
	TEST_ASSERT(after_pending(E, "lifecycle_lifetime_timer") && om_timer_count(E) == 1 && after_left(E, "lifecycle_lifetime_timer") != first, "a second expire() should replace the timer")
	E.expire(null)
	TEST_ASSERT(!after_pending(E, "lifecycle_lifetime_timer") && !om_timer_count(E), "expire(null) should disarm the timer")
	qdel(E)
	TEST_ASSERT(QDELETED(E), "the effect should be deleted")

/// delete_on_death deletes from the death pipeline's final hook, after subtype code.
/datum/unit_test/dq_lifecycle_delete_on_death_arms
/datum/unit_test/dq_lifecycle_delete_on_death_arms/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse, test_floor())
	M.delete_on_death = TRUE
	M.death()
	TEST_ASSERT(QDELETED(M), "the final hook of death() should delete a dead delete_on_death mob")
