// Unit tests for entity-to-entity OM relations that replaced hand-rolled
// two-sided reference/cleanup code (doc/rewrite/om_framework_report.md,
// doc/rewrite/object_model_core.md "relations"). One file per relation
// family; each relation gets: establishing the link, the link breaking with
// no dangling refs when either end is hard-deleted, and (where the relation
// declares a range/holds_while check) the link breaking when the sides move
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
	TEST_ASSERT_EQUAL(H?.buckled_to(), C, "H?.buckled_to() should be the chair")
	TEST_ASSERT(H in C?.buckled_mob_list(), "H should be in the chair's BUCKLED_MOBS")
	TEST_ASSERT(stat_value(H, STAT_BUCKLED), "buckling should raise EFFECT_BUCKLED on the mob")

/// Hard-deleting the object a mob is buckled to unbuckles it, with no dangling
/// reference left on either side.
/datum/unit_test/dq_om_relation_buckling_breaks_on_target_delete

/datum/unit_test/dq_om_relation_buckling_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")
	qdel(C)
	TEST_ASSERT(QDELETED(C), "setup: the chair should be deleted")
	TEST_ASSERT_NULL(H?.buckled_to(), "H?.buckled_to() should be cleared once the chair is deleted")
	TEST_ASSERT(!stat_value(H, STAT_BUCKLED), "EFFECT_BUCKLED should be gone once unbuckled")

/// Hard-deleting a buckled mob removes it from the object's buckled_mobs, with
/// no dangling reference left behind.
/datum/unit_test/dq_om_relation_buckling_breaks_on_source_delete

/datum/unit_test/dq_om_relation_buckling_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")
	qdel(H)
	TEST_ASSERT(QDELETED(H), "setup: the mob should be deleted")
	TEST_ASSERT_EQUAL(LAZYLEN(C?.buckled_mob_list()), 0, "the chair should have no buckled mobs left")
	TEST_ASSERT(!(H in C?.buckled_mob_list()), "the deleted mob should not still be listed")

/// holds_while = in_range(0) (library.dm) unlinks the edge outright -- not just
/// its contribution -- the instant the mob ends up off the chair's tile, e.g.
/// a forceMove() that bypassed handle_buckled_mob_movement().
/datum/unit_test/dq_om_relation_buckling_breaks_on_range

/datum/unit_test/dq_om_relation_buckling_breaks_on_range/Run()
	test_driver_begin()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/structure/bed/chair/C = allocate(/obj/structure/bed/chair, get_turf(H))
	TEST_ASSERT(C.buckle_mob(H, forced = TRUE), "setup: buckle_mob should succeed")

	var/turf/away = locate(C.x + 3, C.y, C.z)
	TEST_ASSERT_NOTNULL(away, "setup: needs a turf 3 tiles east of the chair")
	H.forceMove(away)
	TEST_ASSERT_NOTEQUAL(get_turf(H), get_turf(C), "setup: H should now be off the chair's tile")

	// The live scheduler would run this on its next lane pass (relation.dm's
	// edge_refresh behaviour, watching CHANGE_MOB_LOC/CHANGE_ITEM_LOC); drive
	// it directly so the test doesn't depend on tick timing.
	test_time(1 SECONDS)
	test_driver_end()

	TEST_ASSERT_NULL(H?.buckled_to(), "H?.buckled_to() should be cleared once out of range")
	TEST_ASSERT_EQUAL(LAZYLEN(C?.buckled_mob_list()), 0, "the chair should have no buckled mobs left")

// ---------------------------------------------------------------- grabbing

/// Grabbing a mob establishes the grabbing relation: GRAB_TARGET(G) and
/// GRABBED_BY(victim) agree with the direct lookup. No view fields (OM
/// relations step 6): the grab item's `affecting` and the victim's
/// `grabbed_by` fields are gone -- both are pure graph reads now.
/datum/unit_test/dq_om_relation_grabbing_establishes

/datum/unit_test/dq_om_relation_grabbing_establishes/Run()
	var/mob/living/carbon/human/assailant = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/obj/item/grab/G = allocate(/obj/item/grab, assailant, victim)
	TEST_ASSERT(!QDELETED(G), "the grab should not immediately self-delete")
	TEST_ASSERT_EQUAL(G?.grab_target(), victim, "G?.grab_target() should be the victim")
	TEST_ASSERT(G in victim?.grabbed_by_list(), "G should be in the victim's GRABBED_BY")

/// Hard-deleting a grab removes it from the victim's GRABBED_BY, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_grabbing_breaks_on_source_delete

/datum/unit_test/dq_om_relation_grabbing_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/assailant = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/obj/item/grab/G = allocate(/obj/item/grab, assailant, victim)
	TEST_ASSERT(!QDELETED(G), "setup: the grab should not immediately self-delete")
	qdel(G)
	TEST_ASSERT(QDELETED(G), "setup: the grab should be deleted")
	TEST_ASSERT_EQUAL(length(victim?.grabbed_by_list()), 0, "the victim should have no grabs left")
	TEST_ASSERT(!(G in victim?.grabbed_by_list()), "the deleted grab should not still be listed")

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

/// Pulling something establishes the pulling relation: PULLING()/PULLED_BY()
/// agree with the direct relation lookup. No view fields (OM relations step
/// 6): pulling/pulledby are gone entirely, pure graph reads.
/datum/unit_test/dq_om_relation_pulling_establishes

/datum/unit_test/dq_om_relation_pulling_establishes/Run()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)
	TEST_ASSERT_EQUAL(puller?.pulling_target(), pulled, "puller?.pulling_target() should be the pulled mob")
	TEST_ASSERT_EQUAL(pulled?.pulled_by_mob(), puller, "pulled?.pulled_by_mob() should be the puller")

/// Hard-deleting the puller clears the pulled mob's pulledby, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_pulling_breaks_on_source_delete

/datum/unit_test/dq_om_relation_pulling_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)
	TEST_ASSERT_EQUAL(puller?.pulling_target(), pulled, "setup: start_pulling should succeed")
	qdel(puller)
	TEST_ASSERT(QDELETED(puller), "setup: the puller should be deleted")
	TEST_ASSERT_NULL(pulled?.pulled_by_mob(), "pulled?.pulled_by_mob() should be cleared once the puller is deleted")

/// Hard-deleting the pulled atom clears the puller's pulling var, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_pulling_breaks_on_target_delete

/datum/unit_test/dq_om_relation_pulling_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)
	TEST_ASSERT_EQUAL(puller?.pulling_target(), pulled, "setup: start_pulling should succeed")
	qdel(pulled)
	TEST_ASSERT(QDELETED(pulled), "setup: the pulled mob should be deleted")
	TEST_ASSERT_NULL(puller?.pulling_target(), "puller?.pulling_target() should be cleared once the pulled mob is deleted")

/// holds_while = in_range(1) unlinks the edge outright once puller and pulled
/// end up more than one tile apart, replacing the hand-rolled distance check
/// that used to live in /atom/movable/Move() (atoms_movable.dm).
/datum/unit_test/dq_om_relation_pulling_breaks_on_range

/datum/unit_test/dq_om_relation_pulling_breaks_on_range/Run()
	test_driver_begin()
	var/mob/living/carbon/human/puller = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/pulled = allocate(/mob/living/carbon/human)
	puller.start_pulling(pulled)

	var/turf/away = locate(pulled.x + 5, pulled.y, pulled.z)
	TEST_ASSERT_NOTNULL(away, "setup: needs a turf 5 tiles east of the pulled mob")
	puller.forceMove(away)
	TEST_ASSERT(get_dist(puller, pulled) > 1, "setup: puller should now be more than one tile from pulled")

	test_time(1 SECONDS)
	test_driver_end()

	TEST_ASSERT_NULL(puller?.pulling_target(), "puller?.pulling_target() should be cleared once out of range")
	TEST_ASSERT_NULL(pulled?.pulled_by_mob(), "pulled?.pulled_by_mob() should be cleared once out of range")

// ---------------------------------------------------------------- occupant slots

/// Entering a machine's occupant slot links it, the slot itself being the
/// relation.
/// Exercised through the sleeper, one of several machines (also cryo,
/// cryopod, mecha, rechargestation, the implant chair and the gibber, adv_med
/// and the clone pod) built on a sealed occupant slot (the sleeper's is occupant_pod()'s declared one).
/datum/unit_test/dq_om_relation_occupant_slot_establishes

/datum/unit_test/dq_om_relation_occupant_slot_establishes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, get_turf(H))
	TEST_ASSERT(move_into(S, OCCUPANT_SLOT_SLEEPER, H), "setup: move_into should succeed")
	TEST_ASSERT_EQUAL(occupant_of(S), H, "the sleeper's occupant slot should hold H")
	TEST_ASSERT_EQUAL(link_of(H, /datum/om/relation/slot/declared/sealed), S, "om_relation_of should agree with the slot")
	TEST_ASSERT_NOTNULL(dq_test_find_edge(H, S, /datum/om/relation/slot/declared/sealed), "an edge should exist between H and S")
	S.slot_remove(H, get_turf(S))

/// Hard-deleting the machine clears the occupant mob's relation lookup, with
/// no dangling reference left behind.
/datum/unit_test/dq_om_relation_occupant_slot_breaks_on_target_delete

/datum/unit_test/dq_om_relation_occupant_slot_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, get_turf(H))
	TEST_ASSERT(move_into(S, OCCUPANT_SLOT_SLEEPER, H), "setup: move_into should succeed")
	qdel(S)
	TEST_ASSERT(QDELETED(S), "setup: the sleeper should be deleted")
	TEST_ASSERT_NULL(link_of(H, /datum/om/relation/slot/declared/sealed), "the relation lookup should agree")

/// Hard-deleting the occupant mob clears the slot, with no dangling reference
/// left behind -- closing the same class of dangling-reference bug the
/// grabbing relation fixed: these machines used to hand-set `occupant = M` on
/// entry with no /datum/om/event/qdeleting hook, so hard-deleting the occupant
/// mid-occupancy left `occupant` pointing at a QDELETED mob indefinitely.
/datum/unit_test/dq_om_relation_occupant_slot_breaks_on_source_delete

/datum/unit_test/dq_om_relation_occupant_slot_breaks_on_source_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, get_turf(H))
	TEST_ASSERT(move_into(S, OCCUPANT_SLOT_SLEEPER, H), "setup: move_into should succeed")
	qdel(H)
	TEST_ASSERT(QDELETED(H), "setup: the mob should be deleted")
	TEST_ASSERT_NULL(occupant_of(S), "the sleeper's occupant slot should be cleared once the occupant is deleted")

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
	TEST_ASSERT_EQUAL(I.imp_in(), H, "I.imp_in should be H")
	TEST_ASSERT(I in torso.implants, "I should be in the torso's implants list")
	TEST_ASSERT_EQUAL(link_of(I, /datum/om/relation/slot/implant_site), torso, "om_relation_of should agree with the part var")

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
	TEST_ASSERT_NULL(I.imp_in(), "I.imp_in should be cleared once the organ is deleted")

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

// ---------------------------------------------------------------- eyes

// These use a bare aiEye and take_eye() rather than create_eyeobj(), which
// also calls SetName() -- that reaches into AI announcer/camera setup a bare
// allocate() doesn't stand up.

/// take_eye() links eye_of and active_eye: EYE_OWNER, EYES_OF and ACTIVE_EYE agree.
/datum/unit_test/dq_om_relation_eye_establishes

/datum/unit_test/dq_om_relation_eye_establishes/Run()
	var/mob/living/silicon/ai/A = allocate(/mob/living/silicon/ai, null, null, null, null, TRUE)
	var/mob/observer/eye/aiEye/E = allocate(/mob/observer/eye/aiEye)
	TEST_ASSERT(A.take_eye(E), "take_eye() should succeed")
	TEST_ASSERT_EQUAL(E?.eye_owner(), A, "E?.eye_owner() should be the AI")
	TEST_ASSERT(E in A?.eyes_list(), "E should be in A?.eyes_list()")
	TEST_ASSERT_EQUAL(A?.active_eye(), E, "A?.active_eye() should be E")

/// A second eye linked with eye_of only (a multicam eye) is listed but not active.
/datum/unit_test/dq_om_relation_eye_secondary

/datum/unit_test/dq_om_relation_eye_secondary/Run()
	var/mob/living/silicon/ai/A = allocate(/mob/living/silicon/ai, null, null, null, null, TRUE)
	var/mob/observer/eye/aiEye/E = allocate(/mob/observer/eye/aiEye)
	var/mob/observer/eye/aiEye/P = allocate(/mob/observer/eye/aiEye)
	A.take_eye(E)
	rel_set(P, nameof(P.eye_looker), A)
	TEST_ASSERT(P in A?.eyes_list(), "the secondary eye should be listed")
	TEST_ASSERT_EQUAL(A?.active_eye(), E, "the secondary eye should not become active")
	A.drop_eye()
	TEST_ASSERT_NULL(A?.active_eye(), "drop_eye() should clear the active eye")
	TEST_ASSERT_NULL(E?.eye_owner(), "drop_eye() should unlink the eye")
	TEST_ASSERT_EQUAL(P?.eye_owner(), A, "drop_eye() should leave the secondary eye alone")

/// Deleting the owner unlinks the eye.
/datum/unit_test/dq_om_relation_eye_breaks_on_target_delete

/datum/unit_test/dq_om_relation_eye_breaks_on_target_delete/Run()
	var/mob/living/silicon/ai/A = allocate(/mob/living/silicon/ai, null, null, null, null, TRUE)
	var/mob/observer/eye/aiEye/E = allocate(/mob/observer/eye/aiEye)
	A.take_eye(E)
	qdel(A)
	TEST_ASSERT(QDELETED(A), "setup: the AI should be deleted")
	TEST_ASSERT_NULL(E?.eye_owner(), "E?.eye_owner() should be cleared once the AI is deleted")

/// Deleting the eye clears the owner's active eye and eye list entry.
/datum/unit_test/dq_om_relation_eye_breaks_on_source_delete

/datum/unit_test/dq_om_relation_eye_breaks_on_source_delete/Run()
	var/mob/living/silicon/ai/A = allocate(/mob/living/silicon/ai, null, null, null, null, TRUE)
	var/mob/observer/eye/aiEye/E = allocate(/mob/observer/eye/aiEye)
	A.take_eye(E)
	qdel(E)
	TEST_ASSERT(QDELETED(E), "setup: the eye should be deleted")
	TEST_ASSERT(!(E in A?.eyes_list()), "the deleted eye should not still be listed")
	TEST_ASSERT_NULL(A?.active_eye(), "A?.active_eye() should be cleared once the eye is deleted")

// ---------------------------------------------------------------- host_of (borer)

/// Infesting a host establishes host_of: the borer's `host` var and the
/// host's head organ's `implants` list agree with the direct relation lookup.
/datum/unit_test/dq_om_relation_host_of_establishes

/datum/unit_test/dq_om_relation_host_of_establishes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/simple_mob/animal/borer/B = allocate(/mob/living/simple_mob/animal/borer)
	var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
	TEST_ASSERT_NOTNULL(head, "setup: H should have a head organ")
	TEST_ASSERT(B.take_host(H), "infest() should link the borer")
	TEST_ASSERT_EQUAL(B?.borer_host(), H, "B?.borer_host() should be H")
	TEST_ASSERT(B in head.implants, "B should be listed in the host's head implants")
	TEST_ASSERT_EQUAL(H?.borer_of(), B, "the host should name its borer")
	rel_set(B, nameof(B.borer_host_mob), null)
	TEST_ASSERT_NULL(B?.borer_host(), "B?.borer_host() should be cleared after unlink")
	TEST_ASSERT(!(B in head.implants), "B should no longer be listed in the host's head implants")

/// Hard-deleting the host clears the borer's `host`, with no dangling
/// reference left behind -- this is the desync detatch()/leave_host() used to
/// risk when only one of the two was called (the organ-removal path,
/// misc.dm, only ever called leave_host()).
/datum/unit_test/dq_om_relation_host_of_breaks_on_target_delete

/datum/unit_test/dq_om_relation_host_of_breaks_on_target_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/simple_mob/animal/borer/B = allocate(/mob/living/simple_mob/animal/borer)
	B.take_host(H)
	qdel(H)
	TEST_ASSERT(QDELETED(H), "setup: the host should be deleted")
	TEST_ASSERT_NULL(B?.borer_host(), "B?.borer_host() should be cleared once the host is deleted")

// ---------------------------------------------------------------- following (ghost)

/// Following a target establishes the following relation: FOLLOWING() and
/// FOLLOWERS() agree with the direct relation lookup.
/datum/unit_test/dq_om_relation_following_establishes

/datum/unit_test/dq_om_relation_following_establishes/Run()
	var/mob/observer/dead/G = allocate(/mob/observer/dead)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	rel_set(G, nameof(G.following), H)
	TEST_ASSERT_EQUAL(G?.following_target(), H, "G?.following_target() should be H")
	TEST_ASSERT(G in H?.follower_list(), "G should be listed in H?.follower_list()")
	G.stop_following()
	TEST_ASSERT_NULL(G?.following_target(), "G?.following_target() should be cleared after stop_following()")
	TEST_ASSERT(!(G in H?.follower_list()), "G should no longer be listed in H?.follower_list()")

/// Hard-deleting the followed target ends the ghost's follow, with no
/// dangling reference left behind.
/datum/unit_test/dq_om_relation_following_breaks_on_target_delete

/datum/unit_test/dq_om_relation_following_breaks_on_target_delete/Run()
	var/mob/observer/dead/G = allocate(/mob/observer/dead)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	rel_set(G, nameof(G.following), H)
	qdel(H)
	TEST_ASSERT(QDELETED(H), "setup: the target should be deleted")
	TEST_ASSERT_NULL(G?.following_target(), "G?.following_target() should be cleared once the target is deleted")

// ---------------------------------------------------------------- orbiting

/// orbit() links the orbiting relation (ORBIT_TARGET/ORBITERS), puts the
/// orbiter on the center's turf, keeps it there when the center moves, and
/// stop_orbit() ends it.
/datum/unit_test/dq_om_relation_orbiting_follows_center

/datum/unit_test/dq_om_relation_orbiting_follows_center/Run()
	var/mob/living/carbon/human/center = allocate(/mob/living/carbon/human)
	var/obj/item/dq_containment_test/orbiter = allocate(/obj/item/dq_containment_test)
	orbiter.orbit(center, 16)
	TEST_ASSERT_EQUAL(orbiter?.orbit_target(), center, "ORBIT_TARGET should be the center")
	TEST_ASSERT(orbiter in center?.orbiter_list(), "the orbiter should be listed in center?.orbiter_list()")
	TEST_ASSERT_EQUAL(orbiter.loc, get_turf(center), "the orbiter should sit on the center's turf")
	var/turf/away = locate(center.x + 2, center.y, center.z)
	TEST_ASSERT_NOTNULL(away, "setup: needs a turf 2 tiles east")
	center.forceMove(away)
	TEST_ASSERT_EQUAL(orbiter.loc, away, "the orbiter should follow the center")
	TEST_ASSERT_EQUAL(orbiter?.orbit_target(), center, "following the center should not end the orbit")
	orbiter.stop_orbit()
	TEST_ASSERT_NULL(orbiter?.orbit_target(), "stop_orbit() should end the orbit")
	TEST_ASSERT(!LAZYLEN(center?.orbiter_list()), "the center should have no orbiters left")

/// An orbiter that leaves the center's turf on its own stops orbiting, and
/// deleting the center ends every orbit around it.
/datum/unit_test/dq_om_relation_orbiting_breaks

/datum/unit_test/dq_om_relation_orbiting_breaks/Run()
	var/mob/living/carbon/human/center = allocate(/mob/living/carbon/human)
	var/obj/item/dq_containment_test/orbiter = allocate(/obj/item/dq_containment_test)
	orbiter.orbit(center, 16)
	var/turf/away = locate(center.x + 2, center.y, center.z)
	orbiter.forceMove(away)
	TEST_ASSERT_NULL(orbiter?.orbit_target(), "leaving the center's turf should end the orbit")
	orbiter.orbit(center, 16)
	TEST_ASSERT_EQUAL(orbiter?.orbit_target(), center, "setup: re-orbit should succeed")
	qdel(center)
	TEST_ASSERT_NULL(orbiter?.orbit_target(), "deleting the center should end the orbit")

/// The centre can be a turf, and the orbiter's transform comes back when the orbit ends (it was saved on the link).
/datum/unit_test/dq_om_relation_orbiting_turf_centre

/datum/unit_test/dq_om_relation_orbiting_turf_centre/Run()
	var/turf/centre = get_turf(run_loc_floor_bottom_left)
	var/obj/item/dq_containment_test/orbiter = allocate(/obj/item/dq_containment_test, centre)
	var/matrix/before = matrix(orbiter.transform)
	orbiter.orbit(centre, 16)
	TEST_ASSERT_EQUAL(orbiter?.orbit_target(), centre, "a turf can be the centre")
	TEST_ASSERT(orbiter in centre.orbiter_list(), "the turf lists its orbiter")
	TEST_ASSERT(orbiter.transform.f != before.f || orbiter.transform.b != before.b, "the orbit shifts the orbiter")
	orbiter.stop_orbit()
	TEST_ASSERT_NULL(orbiter?.orbit_target(), "stop_orbit() ends it")
	var/matrix/now = orbiter.transform
	TEST_ASSERT(now.a == before.a && now.b == before.b && now.c == before.c && now.d == before.d && now.e == before.e && now.f == before.f, "the saved transform is back")

// ---------------------------------------------------------------- leash

/// A leash is two edges (pet -> leash, leash -> holder). Deleting the holder
/// drops the holder edge, which frees the pet as well.
/datum/unit_test/dq_om_relation_leash_breaks_with_holder

/datum/unit_test/dq_om_relation_leash_breaks_with_holder/Run()
	var/mob/living/carbon/human/pet = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/master = allocate(/mob/living/carbon/human)
	var/obj/item/leash/L = allocate(/obj/item/leash)
	TEST_ASSERT(L.attach(pet, master), "setup: the leash should attach")
	TEST_ASSERT_EQUAL(L?.leash_pet(), pet, "LEASH_PET should be the pet")
	TEST_ASSERT_EQUAL(L?.leash_master(), master, "LEASH_MASTER should be the holder")
	TEST_ASSERT_EQUAL(pet?.leash_item(), L, "pet?.leash_item() should be the leash")
	TEST_ASSERT(pet.alerts && pet.alerts["leashed"], "the pet should get the leashed alert")
	qdel(master)
	TEST_ASSERT_NULL(L?.leash_master(), "deleting the holder should drop the holder edge")
	TEST_ASSERT_NULL(pet?.leash_item(), "dropping the holder edge should free the pet")
	TEST_ASSERT(!(pet.alerts && pet.alerts["leashed"]), "the freed pet should lose the leashed alert")

// ---------------------------------------------------------------- tethered items

/// A tethered-item host links its handheld on creation, remakes it if the
/// handheld is deleted, and takes it down with it when deleted.
/datum/unit_test/dq_om_relation_tether

/datum/unit_test/dq_om_relation_tether/Run()
	var/obj/item/defib_kit/kit = allocate(/obj/item/defib_kit)
	var/obj/item/paddles = kit?.tethered_handheld()
	TEST_ASSERT_NOTNULL(paddles, "the kit should have tethered paddles")
	TEST_ASSERT_EQUAL(paddles?.tether_host(), kit, "paddles?.tether_host() should be the kit")
	qdel(paddles)
	// The host remakes its handheld out of the unlink, on an om_after(0) timer
	// that fires on the next scheduler slot, so wait for it.
	var/obj/item/remade
	for(var/i in 1 to 40)
		remade = kit?.tethered_handheld()
		if(remade)
			break
		sleep(world.tick_lag)
	TEST_ASSERT(remade && remade != paddles, "deleting the paddles should remake them")
	qdel(kit)
	TEST_ASSERT(QDELETED(remade), "deleting the kit should delete its paddles")
