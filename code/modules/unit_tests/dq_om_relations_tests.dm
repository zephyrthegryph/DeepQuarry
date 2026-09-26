// Unit tests for entity-to-entity OM relations that replaced hand-rolled
// two-sided reference/cleanup code (doc/rewrite/om_framework_report.md,
// doc/rewrite/object_model_core.md "relations"). One file per relation
// family; each relation gets: establishing the link, the link breaking with
// no dangling refs when either end is hard-deleted, and (where the relation
// declares a range/break_if check) the link breaking when the sides move
// apart, again with no dangling refs left over.

/// White-box helper: the edge of relation `rel_path` directly between `source`
/// and `target`, or null. Tests use this to drive om_edge_refresh() directly
/// instead of waiting on the live scheduler's next lane pass.
/proc/dq_test_find_edge(datum/source, datum/target, rel_path)
	RETURN_TYPE(/datum/om/edge)
	var/datum/om/relation/R = om_registry().relation(rel_path)
	for(var/datum/om/edge/edge as anything in source?.om_rec?.edges)
		if(edge.rel == R && edge.source == source && edge.target == target)
			return edge
	return null

// ---------------------------------------------------------------- buckled_to

/// Buckling a mob to an object establishes the buckled_to relation: the
/// declared view fields (buckled/buckled_mobs) and the direct relation lookup
/// agree, and the EFFECT_BUCKLED contribution is live.
/datum/unit_test/dq_om_relation_buckling_establishes

/datum/unit_test/dq_om_relation_buckling_establishes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "buckle_mob should succeed on a fresh chair")
	TEST_ASSERT_EQUAL(H.buckled, C, "H.buckled should be the chair")
	TEST_ASSERT(H in C.buckled_mobs, "H should be in the chair's buckled_mobs")
	TEST_ASSERT_EQUAL(om_relation_of(H, /datum/om/relation/buckled_to), C, "om_relation_of should agree with the buckled var")
	TEST_ASSERT(om_has(H, EFFECT_BUCKLED), "buckling should raise EFFECT_BUCKLED on the mob")
	TEST_ASSERT_NOTNULL(dq_test_find_edge(H, C, /datum/om/relation/buckled_to), "an edge should exist between H and C")

/// Hard-deleting the object a mob is buckled to unbuckles it, with no dangling
/// reference left on either side.
/datum/unit_test/dq_om_relation_buckling_breaks_on_target_delete

/datum/unit_test/dq_om_relation_buckling_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")
	qdel(C)
	TEST_ASSERT(QDELETED(C), "setup: the chair should be deleted")
	TEST_ASSERT_NULL(H.buckled, "H.buckled should be cleared once the chair is deleted")
	TEST_ASSERT_NULL(om_relation_of(H, /datum/om/relation/buckled_to), "the relation lookup should agree")
	TEST_ASSERT(!om_has(H, EFFECT_BUCKLED), "EFFECT_BUCKLED should be gone once unbuckled")

/// Hard-deleting a buckled mob removes it from the object's buckled_mobs, with
/// no dangling reference left behind.
/datum/unit_test/dq_om_relation_buckling_breaks_on_source_delete

/datum/unit_test/dq_om_relation_buckling_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")
	qdel(H)
	TEST_ASSERT(QDELETED(H), "setup: the mob should be deleted")
	TEST_ASSERT_EQUAL(LAZYLEN(C.buckled_mobs), 0, "the chair should have no buckled mobs left")
	TEST_ASSERT(!(H in C.buckled_mobs), "the deleted mob should not still be listed")

/// break_if = in_range(0) (library.dm) unlinks the edge outright -- not just
/// its contribution -- the instant the mob ends up off the chair's tile, e.g.
/// a forceMove() that bypassed handle_buckled_mob_movement().
/datum/unit_test/dq_om_relation_buckling_breaks_on_range

/datum/unit_test/dq_om_relation_buckling_breaks_on_range/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")
	var/datum/om/edge/edge = dq_test_find_edge(H, C, /datum/om/relation/buckled_to)
	TEST_ASSERT_NOTNULL(edge, "setup: an edge should exist between H and C")

	var/turf/away = locate(C.x + 3, C.y, C.z)
	TEST_ASSERT_NOTNULL(away, "setup: needs a turf 3 tiles east of the chair")
	H.forceMove(away)
	TEST_ASSERT_NOTEQUAL(get_turf(H), get_turf(C), "setup: H should now be off the chair's tile")

	// The live scheduler would run this on its next lane pass (relation.dm's
	// edge_refresh behaviour, watching CHANGE_MOB_LOC/CHANGE_ITEM_LOC); drive
	// it directly so the test doesn't depend on tick timing.
	om_edge_refresh(edge)

	TEST_ASSERT_NULL(H.buckled, "H.buckled should be cleared once out of range")
	TEST_ASSERT_EQUAL(LAZYLEN(C.buckled_mobs), 0, "the chair should have no buckled mobs left")
	TEST_ASSERT_NULL(edge.source, "the edge itself should be torn down (no dangling source)")
	TEST_ASSERT_NULL(edge.target, "the edge itself should be torn down (no dangling target)")
	TEST_ASSERT_NULL(om_relation_of(H, /datum/om/relation/buckled_to), "the relation lookup should agree")

// ---------------------------------------------------------------- grabbing

/// Grabbing a mob establishes the grabbing relation: the grab item's
/// `affecting` and the victim's `grabbed_by` agree with the direct lookup.
/datum/unit_test/dq_om_relation_grabbing_establishes

/datum/unit_test/dq_om_relation_grabbing_establishes/Run()
	var/mob/living/carbon/human/assailant = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/obj/item/grab/G = allocate(/obj/item/grab, assailant, victim)
	TEST_ASSERT(!QDELETED(G), "the grab should not immediately self-delete")
	TEST_ASSERT_EQUAL(G.affecting, victim, "G.affecting should be the victim")
	TEST_ASSERT(G in victim.grabbed_by, "G should be in the victim's grabbed_by")
	TEST_ASSERT_EQUAL(om_relation_of(G, /datum/om/relation/grabbing), victim, "om_relation_of should agree with the affecting var")
	TEST_ASSERT_NOTNULL(dq_test_find_edge(G, victim, /datum/om/relation/grabbing), "an edge should exist between G and the victim")

/// Hard-deleting a grab removes it from the victim's grabbed_by, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_grabbing_breaks_on_source_delete

/datum/unit_test/dq_om_relation_grabbing_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/assailant = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/obj/item/grab/G = allocate(/obj/item/grab, assailant, victim)
	TEST_ASSERT(!QDELETED(G), "setup: the grab should not immediately self-delete")
	qdel(G)
	TEST_ASSERT(QDELETED(G), "setup: the grab should be deleted")
	TEST_ASSERT_EQUAL(LAZYLEN(victim.grabbed_by), 0, "the victim should have no grabs left")
	TEST_ASSERT(!(G in victim.grabbed_by), "the deleted grab should not still be listed")

/// Hard-deleting the grabbed mob deletes the grab item too (on_target_delete
/// = OM_END_DELETE_OTHER): the item has nothing left to grab, and previously
/// this left a dangling `affecting` reference to a QDELETED mob forever,
/// since the grab item lives in the assailant's hand, not the victim's
/// contents, so ordinary contents-destroy never reached it.
/datum/unit_test/dq_om_relation_grabbing_breaks_on_target_delete

/datum/unit_test/dq_om_relation_grabbing_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/assailant = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/obj/item/grab/G = allocate(/obj/item/grab, assailant, victim)
	TEST_ASSERT(!QDELETED(G), "setup: the grab should not immediately self-delete")
	qdel(victim)
	TEST_ASSERT(QDELETED(victim), "setup: the victim should be deleted")
	TEST_ASSERT(QDELETED(G), "the grab item should be deleted along with its target")
