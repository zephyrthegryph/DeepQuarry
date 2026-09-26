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

// ---------------------------------------------------------------- pulling

/// Pulling something establishes the pulling relation: pulling/pulledby agree
/// with the direct relation lookup.
/datum/unit_test/dq_om_relation_pulling_establishes

/datum/unit_test/dq_om_relation_pulling_establishes/Run()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)
	TEST_ASSERT_EQUAL(puller.pulling, pulled, "puller.pulling should be the pulled mob")
	TEST_ASSERT_EQUAL(pulled.pulledby, puller, "pulled.pulledby should be the puller")
	TEST_ASSERT_EQUAL(om_relation_of(puller, /datum/om/relation/pulling), pulled, "om_relation_of should agree with the pulling var")
	TEST_ASSERT_NOTNULL(dq_test_find_edge(puller, pulled, /datum/om/relation/pulling), "an edge should exist between puller and pulled")

/// Hard-deleting the puller clears the pulled mob's pulledby, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_pulling_breaks_on_source_delete

/datum/unit_test/dq_om_relation_pulling_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)
	TEST_ASSERT_EQUAL(puller.pulling, pulled, "setup: start_pulling should succeed")
	qdel(puller)
	TEST_ASSERT(QDELETED(puller), "setup: the puller should be deleted")
	TEST_ASSERT_NULL(pulled.pulledby, "pulled.pulledby should be cleared once the puller is deleted")

/// Hard-deleting the pulled atom clears the puller's pulling var, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_pulling_breaks_on_target_delete

/datum/unit_test/dq_om_relation_pulling_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)
	TEST_ASSERT_EQUAL(puller.pulling, pulled, "setup: start_pulling should succeed")
	qdel(pulled)
	TEST_ASSERT(QDELETED(pulled), "setup: the pulled mob should be deleted")
	TEST_ASSERT_NULL(puller.pulling, "puller.pulling should be cleared once the pulled mob is deleted")

/// break_if = in_range(1) unlinks the edge outright once puller and pulled
/// end up more than one tile apart, replacing the hand-rolled distance check
/// that used to live in /atom/movable/Move() (atoms_movable.dm).
/datum/unit_test/dq_om_relation_pulling_breaks_on_range

/datum/unit_test/dq_om_relation_pulling_breaks_on_range/Run()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)
	var/datum/om/edge/edge = dq_test_find_edge(puller, pulled, /datum/om/relation/pulling)
	TEST_ASSERT_NOTNULL(edge, "setup: an edge should exist between puller and pulled")

	var/turf/away = locate(pulled.x + 5, pulled.y, pulled.z)
	TEST_ASSERT_NOTNULL(away, "setup: needs a turf 5 tiles east of the pulled mob")
	puller.forceMove(away)
	TEST_ASSERT(get_dist(puller, pulled) > 1, "setup: puller should now be more than one tile from pulled")

	om_edge_refresh(edge)

	TEST_ASSERT_NULL(puller.pulling, "puller.pulling should be cleared once out of range")
	TEST_ASSERT_NULL(pulled.pulledby, "pulled.pulledby should be cleared once out of range")
	TEST_ASSERT_NULL(edge.source, "the edge itself should be torn down (no dangling source)")
	TEST_ASSERT_NULL(edge.target, "the edge itself should be torn down (no dangling target)")

// ---------------------------------------------------------------- occupant_of

/// Entering a machine's occupant slot establishes occupant_of: the machine's
/// `occupant` var agrees with the direct relation lookup. Exercised through
/// the sleeper, one of several machines (also cryo, cryopod, mecha,
/// rechargestation, the implant chair and the gibber) that share this
/// relation via target_ref_field = "occupant".
/datum/unit_test/dq_om_relation_occupant_of_establishes

/datum/unit_test/dq_om_relation_occupant_of_establishes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, get_turf(H))
	om_link(H, S, /datum/om/relation/occupant_of)
	TEST_ASSERT_EQUAL(S.occupant, H, "S.occupant should be H")
	TEST_ASSERT_EQUAL(om_relation_of(H, /datum/om/relation/occupant_of), S, "om_relation_of should agree with the occupant var")
	TEST_ASSERT_NOTNULL(dq_test_find_edge(H, S, /datum/om/relation/occupant_of), "an edge should exist between H and S")
	om_unlink(H, S, /datum/om/relation/occupant_of)

/// Hard-deleting the machine clears the occupant mob's relation lookup, with
/// no dangling reference left behind.
/datum/unit_test/dq_om_relation_occupant_of_breaks_on_target_delete

/datum/unit_test/dq_om_relation_occupant_of_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, get_turf(H))
	om_link(H, S, /datum/om/relation/occupant_of)
	TEST_ASSERT_EQUAL(S.occupant, H, "setup: om_link should succeed")
	qdel(S)
	TEST_ASSERT(QDELETED(S), "setup: the sleeper should be deleted")
	TEST_ASSERT_NULL(om_relation_of(H, /datum/om/relation/occupant_of), "the relation lookup should agree")

/// Hard-deleting the occupant mob clears the machine's `occupant` var --
/// closing the same class of dangling-reference bug the grabbing relation
/// fixed: these machines used to hand-set `occupant = M` on entry with no
/// COMSIG_QDELETING hook, so hard-deleting the occupant mid-occupancy left
/// `occupant` pointing at a QDELETED mob indefinitely.
/datum/unit_test/dq_om_relation_occupant_of_breaks_on_source_delete

/datum/unit_test/dq_om_relation_occupant_of_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, get_turf(H))
	om_link(H, S, /datum/om/relation/occupant_of)
	TEST_ASSERT_EQUAL(S.occupant, H, "setup: om_link should succeed")
	qdel(H)
	TEST_ASSERT(QDELETED(H), "setup: the mob should be deleted")
	TEST_ASSERT_NULL(S.occupant, "S.occupant should be cleared once the occupant is deleted")

// ---------------------------------------------------------------- implanted_in

/// Implanting a human establishes implanted_in: the implant's `part`/`imp_in`
/// and the organ's `implants` list agree with the direct relation lookup.
/datum/unit_test/dq_om_relation_implanted_in_establishes

/datum/unit_test/dq_om_relation_implanted_in_establishes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(torso, "setup: H should have a torso")
	var/obj/item/implant/I = allocate(/obj/item/implant)
	I.handle_implant(H, BP_TORSO)
	TEST_ASSERT_EQUAL(I.part, torso, "I.part should be the torso")
	TEST_ASSERT_EQUAL(I.imp_in, H, "I.imp_in should be H")
	TEST_ASSERT(I in torso.implants, "I should be in the torso's implants list")
	TEST_ASSERT_EQUAL(om_relation_of(I, /datum/om/relation/slot/implant_site), torso, "om_relation_of should agree with the part var")

/// Hard-deleting the organ clears the implant's part/imp_in, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_implanted_in_breaks_on_target_delete

/datum/unit_test/dq_om_relation_implanted_in_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/obj/item/implant/I = allocate(/obj/item/implant)
	I.handle_implant(H, BP_TORSO)
	TEST_ASSERT_EQUAL(I.part, torso, "setup: handle_implant should succeed")
	qdel(torso)
	TEST_ASSERT(QDELETED(torso), "setup: the organ should be deleted")
	TEST_ASSERT_NULL(I.part, "I.part should be cleared once the organ is deleted")
	TEST_ASSERT_NULL(I.imp_in, "I.imp_in should be cleared once the organ is deleted")

/// Hard-deleting the implant removes it from the organ's implants list, with
/// no dangling reference left behind.
/datum/unit_test/dq_om_relation_implanted_in_breaks_on_source_delete

/datum/unit_test/dq_om_relation_implanted_in_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/obj/item/implant/I = allocate(/obj/item/implant)
	I.handle_implant(H, BP_TORSO)
	TEST_ASSERT(I in torso.implants, "setup: handle_implant should succeed")
	qdel(I)
	TEST_ASSERT(QDELETED(I), "setup: the implant should be deleted")
	TEST_ASSERT(!(I in torso.implants), "the deleted implant should not still be listed")

/// The implant site is keyed by implant type (organ_external.dm, OM
/// relations step 2): a second implant of the same type is refused, and a
/// different type still fits.
/datum/unit_test/dq_om_relation_implanted_in_keyed_by_type

/datum/unit_test/dq_om_relation_implanted_in_keyed_by_type/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/obj/item/implant/I1 = allocate(/obj/item/implant)
	I1.handle_implant(H, BP_TORSO)
	TEST_ASSERT_EQUAL(I1.part, torso, "setup: the first implant should take")

	var/obj/item/implant/I2 = allocate(/obj/item/implant)
	TEST_ASSERT_NOTNULL(dq_ledger_refusal(I2, torso, ORGAN_SLOT_IMPLANTS, null), "a second implant of the same type should be refused")

	var/obj/item/implant/tracking/I3 = allocate(/obj/item/implant/tracking)
	TEST_ASSERT_NULL(dq_ledger_refusal(I3, torso, ORGAN_SLOT_IMPLANTS, null), "a different implant type should still fit")

/// Destroying the organ deletes its implants (SLOT_DROP_DELETE), same as the
/// raw contents this slot replaced.
/datum/unit_test/dq_om_relation_implanted_in_drop_policy_deletes

/datum/unit_test/dq_om_relation_implanted_in_drop_policy_deletes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/obj/item/implant/I = allocate(/obj/item/implant)
	I.handle_implant(H, BP_TORSO)
	TEST_ASSERT(I in torso.implants, "setup: handle_implant should succeed")
	qdel(torso)
	TEST_ASSERT(QDELETED(I), "the implant should be deleted along with its organ")

// ---------------------------------------------------------------- ai_eye_of

/// Creating an AI's eye establishes ai_eye_of: the eye's `owner` and the AI's
/// `all_eyes`/`eyeobj` agree with the direct relation lookup.
/datum/unit_test/dq_om_relation_ai_eye_of_establishes

// These drive the relation directly with om_link()/om_unlink() and a bare
// aiEye, rather than through create_eyeobj(), which also calls SetName() --
// that reaches into an AI's announcer/camera setup that a bare allocate()
// doesn't stand up and isn't part of what these tests are checking.
/datum/unit_test/dq_om_relation_ai_eye_of_establishes/Run()
	var/mob/living/silicon/ai/A = allocate(/mob/living/silicon/ai, null, null, null, null, TRUE)
	var/mob/observer/eye/aiEye/E = allocate(/mob/observer/eye/aiEye)
	var/link_result = om_link(E, A, /datum/om/relation/ai_eye_of)
	TEST_ASSERT(istype(link_result, /datum/om/edge), "om_link should return an edge, got: [link_result]")
	A.eyeobj = E
	TEST_ASSERT_EQUAL(E.owner, A, "E.owner should be the AI")
	TEST_ASSERT(E in A.all_eyes, "E should be in the AI's all_eyes")
	TEST_ASSERT_EQUAL(om_relation_of(E, /datum/om/relation/ai_eye_of), A, "om_relation_of should agree with the owner var")

/// Hard-deleting the AI clears the eye's `owner`, with no dangling reference
/// left behind.
/datum/unit_test/dq_om_relation_ai_eye_of_breaks_on_target_delete

/datum/unit_test/dq_om_relation_ai_eye_of_breaks_on_target_delete/Run()
	var/mob/living/silicon/ai/A = allocate(/mob/living/silicon/ai, null, null, null, null, TRUE)
	var/mob/observer/eye/aiEye/E = allocate(/mob/observer/eye/aiEye)
	om_link(E, A, /datum/om/relation/ai_eye_of)
	A.eyeobj = E
	qdel(A)
	TEST_ASSERT(QDELETED(A), "setup: the AI should be deleted")
	TEST_ASSERT_NULL(E.owner, "E.owner should be cleared once the AI is deleted")

/// Hard-deleting the eye clears the AI's `all_eyes` entry and `eyeobj`, with
/// no dangling reference left behind.
/datum/unit_test/dq_om_relation_ai_eye_of_breaks_on_source_delete

/datum/unit_test/dq_om_relation_ai_eye_of_breaks_on_source_delete/Run()
	var/mob/living/silicon/ai/A = allocate(/mob/living/silicon/ai, null, null, null, null, TRUE)
	var/mob/observer/eye/aiEye/E = allocate(/mob/observer/eye/aiEye)
	om_link(E, A, /datum/om/relation/ai_eye_of)
	A.eyeobj = E
	qdel(E)
	TEST_ASSERT(QDELETED(E), "setup: the eye should be deleted")
	// Not LAZYLEN(A.all_eyes) == 0: the AI's own Initialize() (safety = TRUE
	// still runs create_eyeobj()) already created and linked its own eye, so
	// A legitimately has one left -- just not this one.
	TEST_ASSERT(!(E in A.all_eyes), "the deleted eye should not still be listed")
	TEST_ASSERT_NULL(A.eyeobj, "A.eyeobj should be cleared once the eye is deleted")
