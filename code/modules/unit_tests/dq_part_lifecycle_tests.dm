// Part slots and hooks (doc/medical_frameworks.md §2.2-2.3 and §2.10, slice O2).
//
// The attach/detach half of the lifecycle harness: every step asserts
// verify_body_tree() on the body and verify_detached_part() on what came off.
// Destruction ordering (O4) and the mind slot are not covered here.

/// Fails the test with every fault in `M`'s part tree, named by `label`.
/datum/unit_test/proc/dq_assert_body_tree(mob/living/M, label)
	var/list/faults = verify_body_tree(M)
	for(var/fault in faults)
		TEST_FAIL("[label]: [fault]")
	return !length(faults)

/// Fails the test with every fault of a detached part.
/datum/unit_test/proc/dq_assert_detached(obj/item/organ/part, label)
	var/list/faults = verify_detached_part(part)
	for(var/fault in faults)
		TEST_FAIL("[label]: [fault]")
	return !length(faults)

/// A fresh human's limbs are nested in the ledger: torso in the mob's root
/// slot, each limb in its parent's child slot, organs in their limb.
/datum/unit_test/dq_part_tree_is_nested

/datum/unit_test/dq_part_tree_is_nested/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	var/obj/item/organ/internal/heart = H.organ_in(O_HEART)
	TEST_ASSERT_NOTNULL(torso, "no torso")
	TEST_ASSERT_NOTNULL(hand, "no left hand")
	TEST_ASSERT_EQUAL(H.slot_item(SLOT_ID_PART_ROOT), torso, "the torso is the mob's root part")
	TEST_ASSERT_EQUAL(torso.loc, H, "the torso sits in the mob")
	TEST_ASSERT_EQUAL(arm.loc, torso, "the arm sits in the torso")
	TEST_ASSERT_EQUAL(hand.loc, arm, "the hand sits in the arm")
	TEST_ASSERT_EQUAL(torso.slot_lookup(SLOT_ID_PART_CHILD, BP_L_ARM), arm, "the torso's child slot is keyed by organ_tag")
	TEST_ASSERT_EQUAL(arm.slot_lookup(SLOT_ID_PART_CHILD, BP_L_HAND), hand, "the arm's child slot is keyed by organ_tag")
	TEST_ASSERT_EQUAL(heart.parent_part(), H.get_organ(heart.parent_organ), "the heart sits in its parent limb")
	TEST_ASSERT_EQUAL(hand.parent, arm, "the tree cache names the hand's parent")
	TEST_ASSERT(hand in arm.children, "the tree cache lists the hand under the arm")
	TEST_ASSERT_EQUAL(H.body.part(BP_L_HAND), hand, "body.part() finds the hand")
	TEST_ASSERT_EQUAL(H.body.organ(O_HEART), heart, "body.organ() finds the heart")
	TEST_ASSERT_EQUAL(length(H.body.parts()), length(H.organs), "parts() walks every limb")
	TEST_ASSERT_EQUAL(length(H.body.organs()), length(H.internal_organ_list()), "organs() walks every organ")
	TEST_ASSERT_NULL(H.inventory_slot_id(torso), "the root part is not equipment")
	dq_assert_body_tree(H, "fresh human")

/// A clean sever moves the whole subtree in one ledger move; afflictions
/// ride the limbs detached; reattaching to another human adopts all of it.
/datum/unit_test/dq_part_sever_and_reattach

/datum/unit_test/dq_part_sever_and_reattach/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/recipient = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	var/datum/affliction/custom/A = H.body.afflict(/datum/affliction/custom, hand, 40)
	TEST_ASSERT_NOTNULL(A, "the custom affliction didn't land on the hand")

	var/attached = 0
	var/detached = 0
	observe(H, /datum/notice/body_part_detached, src, then(PROC_REF(dq_count_detached)))
	observe(recipient, /datum/notice/body_part_attached, src, then(PROC_REF(dq_count_attached)))

	arm.droplimb(TRUE, DROPLIMB_EDGE)
	TEST_ASSERT(isturf(arm.loc), "the severed arm lies on the floor")
	TEST_ASSERT_EQUAL(hand.loc, arm, "the hand came off inside the arm")
	TEST_ASSERT_NULL(arm.owner, "the severed arm has no owner")
	TEST_ASSERT_NULL(hand.owner, "the hand below it has no owner")
	TEST_ASSERT_NULL(H.body.part(BP_L_HAND), "the body no longer has a left hand")
	TEST_ASSERT(A in hand.detached_afflictions, "the hand's affliction rides it")
	TEST_ASSERT_NULL(A.body, "a riding affliction has no body")
	detached = dq_part_signal_count
	TEST_ASSERT(detached >= 2, "one detach signal per part (arm and hand), got [detached]")
	dq_assert_body_tree(H, "after a clean sever")
	dq_assert_detached(arm, "the severed arm")

	// The recipient loses its own arm first; then the severed one goes on.
	var/obj/item/organ/external/old_arm = recipient.get_organ(BP_L_ARM)
	old_arm.droplimb(TRUE, DROPLIMB_EDGE)
	qdel(old_arm)
	dq_part_signal_count = 0
	TEST_ASSERT(arm.replaced(recipient), "the severed arm should attach")
	attached = dq_part_signal_count
	TEST_ASSERT(attached >= 2, "one attach signal per part (arm and hand), got [attached]")
	TEST_ASSERT_EQUAL(arm.owner, recipient, "the arm belongs to the recipient")
	TEST_ASSERT_EQUAL(hand.owner, recipient, "the hand below it belongs to the recipient")
	TEST_ASSERT_EQUAL(recipient.get_organ(BP_L_HAND), hand, "the recipient's cache has the hand")
	TEST_ASSERT_EQUAL(A.owner, recipient, "the hand's affliction joined the recipient's body")
	TEST_ASSERT(!LAZYLEN(hand.detached_afflictions), "nothing rides the hand any more")
	dq_assert_body_tree(recipient, "after reattaching to another human")
	dq_assert_body_tree(H, "the donor after reattachment elsewhere")

/datum/unit_test/var/dq_part_signal_count = 0

/datum/unit_test/proc/dq_count_detached(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	dq_part_signal_count++

/datum/unit_test/proc/dq_count_attached(datum/act/notice/N)
	SHOULD_NOT_SLEEP(TRUE)
	dq_part_signal_count++

/// A blunt sever destroys the limb; what was inside it is flung out through
/// forced slot removals, detached, and never lost to nullspace.
/datum/unit_test/dq_part_sever_blunt_spills

/datum/unit_test/dq_part_sever_blunt_spills/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	arm.droplimb(FALSE, DROPLIMB_BLUNT)
	own(hand) // flung onto the floor
	own_turf_contents(get_turf(H)) // the blunt sever leaves gibs
	TEST_ASSERT(QDELETED(arm), "a blunt sever destroys the limb")
	TEST_ASSERT(!QDELETED(hand), "the hand inside is flung out, not destroyed")
	TEST_ASSERT(isturf(hand.loc), "the flung hand lands on a turf, not [hand.loc]")
	TEST_ASSERT_NULL(hand.owner, "the flung hand has no owner")
	TEST_ASSERT_NULL(hand.parent, "the flung hand has no parent")
	var/obj/item/organ/external/stump = H.get_organ(BP_L_ARM)
	TEST_ASSERT(stump?.is_stump(), "a stump takes the arm's place")
	dq_assert_body_tree(H, "after a blunt sever")
	dq_assert_detached(hand, "the flung hand")

/// A burn sever destroys the limb and the parts inside it.
/datum/unit_test/dq_part_sever_burn_destroys

/datum/unit_test/dq_part_sever_burn_destroys/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	arm.droplimb(FALSE, DROPLIMB_BURN)
	own_turf_contents(get_turf(H)) // the burn sever leaves ash
	TEST_ASSERT(QDELETED(arm), "a burn sever destroys the limb")
	TEST_ASSERT(QDELETED(hand), "and the hand inside it")
	TEST_ASSERT_NULL(H.organs_by_name[BP_L_HAND], "the cache dropped the hand")
	dq_assert_body_tree(H, "after a burn sever")

/// Removing and replacing an internal organ are ledger moves out of and into
/// its limb's organ slot.
/datum/unit_test/dq_part_organ_remove_replace

/datum/unit_test/dq_part_organ_remove_replace/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	var/obj/item/organ/external/host = liver.parent_part()
	TEST_ASSERT_NOTNULL(host, "the liver sits in a limb")
	TEST_ASSERT(liver.removed(), "removal succeeds")
	TEST_ASSERT(isturf(liver.loc), "the liver lands under the patient")
	TEST_ASSERT_NULL(liver.owner, "a removed liver has no owner")
	TEST_ASSERT(!(liver in host.held_organs()), "the limb's organ slot dropped the liver")
	TEST_ASSERT_NULL(H.organ_in(O_LIVER), "organ_in() no longer finds the liver")
	dq_assert_body_tree(H, "after removing the liver")
	dq_assert_detached(liver, "the removed liver")
	TEST_ASSERT(liver.replaced(H, host), "replacement succeeds")
	TEST_ASSERT_EQUAL(liver.loc, host, "the liver is back in its limb")
	TEST_ASSERT_EQUAL(liver.owner, H, "the liver belongs to the patient again")
	dq_assert_body_tree(H, "after replacing the liver")

/// A keyed organ slot refuses a second organ with the same tag.
/datum/unit_test/dq_part_keyed_slot_refuses_duplicates

/datum/unit_test/dq_part_keyed_slot_refuses_duplicates/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart = H.organ_in(O_HEART)
	var/obj/item/organ/external/host = heart.parent_part()
	var/obj/item/organ/internal/heart/spare = allocate(/obj/item/organ/internal/heart)
	TEST_ASSERT(dq_ledger_refusal(spare, host, SLOT_ID_PART_ORGANS), "a second heart is refused by the limb")
	TEST_ASSERT(!spare.replaced(H, host), "replaced() reports the refusal")
	TEST_ASSERT_NULL(spare.owner, "the refused heart stays unowned")
	TEST_ASSERT_EQUAL(H.organ_in(O_HEART), heart, "the cache keeps the real heart")
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	TEST_ASSERT(dq_ledger_refusal(hand, H.get_organ(BP_R_ARM), SLOT_ID_PART_CHILD), "a left hand doesn't join onto a right arm")
	dq_assert_body_tree(H, "after refused placements")

/// Deleting a part detaches it; deleting a limb deletes its subtree.
/datum/unit_test/dq_part_qdel_detaches

/datum/unit_test/dq_part_qdel_detaches/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	var/obj/item/organ/external/hand = H.get_organ(BP_R_HAND)
	qdel(hand)
	TEST_ASSERT_NULL(H.organs_by_name[BP_R_HAND], "the cache dropped the deleted hand")
	TEST_ASSERT(!(hand in arm.children), "the arm's tree cache dropped it")
	dq_assert_body_tree(H, "after deleting a hand")

	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	var/obj/item/organ/external/foot = H.get_organ(BP_L_FOOT)
	qdel(leg)
	TEST_ASSERT(QDELETED(foot), "deleting a leg deletes the foot in it")
	TEST_ASSERT_NULL(H.organs_by_name[BP_L_FOOT], "the cache dropped the foot")
	TEST_ASSERT_NULL(foot.owner, "the deleted foot has no owner")
	dq_assert_body_tree(H, "after deleting a leg")

/// remove_rejuv() (amputation by preference) deletes the subtree.
/datum/unit_test/dq_part_remove_rejuv

/datum/unit_test/dq_part_remove_rejuv/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/leg = H.get_organ(BP_R_LEG)
	var/obj/item/organ/external/foot = H.get_organ(BP_R_FOOT)
	leg.remove_rejuv()
	TEST_ASSERT(QDELETED(foot), "amputating a leg takes the foot")
	dq_assert_body_tree(H, "after remove_rejuv")

/// A species change rebuilds the tree through the same hooks.
/datum/unit_test/dq_part_species_change

/datum/unit_test/dq_part_species_change/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/old_hand = H.get_organ(BP_L_HAND)
	H.set_species(SPECIES_TAJARAN)
	TEST_ASSERT(QDELETED(old_hand), "the old tree is deleted")
	TEST_ASSERT_NOTNULL(H.get_organ(BP_L_HAND), "the new tree has a left hand")
	TEST_ASSERT(H.stat != DEAD, "rebuilding the tree doesn't kill")
	dq_assert_body_tree(H, "after a species change")

/// Moving an organ between two limbs of the same body is a reparent: no loss,
/// no death, still owned.
/datum/unit_test/dq_part_reparent_within_body

/datum/unit_test/dq_part_reparent_within_body/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.organ_in(O_BRAIN)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	brain.parent_organ = BP_TORSO
	TEST_ASSERT(brain.place_into(torso, SLOT_ID_PART_ORGANS), "the brain moves to the torso")
	TEST_ASSERT_EQUAL(brain.loc, torso, "the brain sits in the torso")
	TEST_ASSERT_EQUAL(brain.owner, H, "the brain is still owned")
	TEST_ASSERT(H.stat != DEAD, "a reparented vital organ doesn't kill")
	TEST_ASSERT(!(brain.status & ORGAN_CUT_AWAY), "a reparent is not a removal")
	dq_assert_body_tree(H, "after moving the brain to the torso")

/// Robotizing a limb keeps the tree sound.
/datum/unit_test/dq_part_robotize_limb

/datum/unit_test/dq_part_robotize_limb/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.robotize()
	TEST_ASSERT(arm.is_robotic(), "the arm is robotic")
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	TEST_ASSERT_EQUAL(hand.robotic, arm.robotic, "the hand in it too")
	dq_assert_body_tree(H, "after robotizing an arm")

/// A mob with no part tree keeps its organs loose in its interior, owned.
/datum/unit_test/dq_part_loose_organs_on_simple_mob

/datum/unit_test/dq_part_loose_organs_on_simple_mob/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	M.spawn_butchery_organs()
	TEST_ASSERT(length(INTERNAL_ORGANS(M)), "the mouse has butchery organs")
	for(var/obj/item/organ/O as anything in M.internal_organ_list())
		TEST_ASSERT_EQUAL(O.owner, M, "[O] belongs to the mouse")
	dq_assert_body_tree(M, "a butchery animal")
	var/obj/item/organ/heart = M.organ_in(O_HEART)
	TEST_ASSERT(heart.removed(), "a loose organ can be removed")
	own(heart)
	TEST_ASSERT_NULL(heart.owner, "and has no owner after")
	TEST_ASSERT_NULL(M.organ_in(O_HEART), "the cache dropped it")
	dq_assert_body_tree(M, "a butchery animal after removal")

/// Severing a hand drops the gloves the mob wore on it.
/datum/unit_test/dq_part_sever_drops_worn

/datum/unit_test/dq_part_sever_drops_worn/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/gloves/G = allocate(/obj/item/clothing/gloves/black)
	TEST_ASSERT(H.equip_to_slot_or_del(G, SLOT_ID_GLOVES), "the gloves go on")
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.droplimb(TRUE, DROPLIMB_EDGE)
	own(arm) // the severed arm lands on the floor
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_GLOVES) != G, "severing an arm drops the gloves on its hand")

/// Deleting a human leaves no part owned.
/datum/unit_test/dq_part_mob_delete

/datum/unit_test/dq_part_mob_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/parts = H.organs + H.internal_organ_list()
	qdel(H)
	for(var/obj/item/organ/O as anything in parts)
		TEST_ASSERT(QDELETED(O), "[O] ([O.type]) is deleted with its mob")
		TEST_ASSERT_NULL(O.owner, "[O] ([O.type]) keeps no owner after its mob is deleted")

