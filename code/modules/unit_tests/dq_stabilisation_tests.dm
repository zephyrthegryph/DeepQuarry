// Field stabilisation: tourniquets, stasis, hemostatic gauze and splints
// (code/modules/medical/stabilisation/).

/// A test-only affliction that grows steadily, for measuring progression.
/datum/affliction/dq_test_progressor
	name = "test progressor"
	catalogued = FALSE
	progression_rate = 1

/// A fresh bleeding cut on `limb` (deep cut, 20 damage).
/datum/unit_test/proc/dq_stab_bleeding_cut(obj/item/organ/external/limb)
	var/datum/affliction/wound/cut/deep/W = new(limb, 20)
	limb.add_wound(W)
	return W

/// Run `cycles` Life() cycles of the body pipeline: the stasis clock, then the
/// affliction tick. Returns how many cycles stasis paused.
/datum/unit_test/proc/dq_stab_run_cycles(mob/living/carbon/human/H, cycles)
	. = 0
	for(var/i in 1 to cycles)
		if(H.body.advance_stasis())
			.++
		H.body.life_tick()


/// A tourniquet stops the bleed on its limb and every limb below it, without
/// touching the wounds; ischemia grows while it's on; loosening it restores
/// the flow and the bleed.
/datum/unit_test/dq_stab_tourniquet_stops_bleed_and_causes_ischemia

/datum/unit_test/dq_stab_tourniquet_stops_bleed_and_causes_ischemia/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	TEST_ASSERT_NOTNULL(arm, "no left arm")
	TEST_ASSERT_NOTNULL(hand, "no left hand")
	var/datum/affliction/wound/arm_cut = dq_stab_bleeding_cut(arm)
	var/datum/affliction/wound/hand_cut = dq_stab_bleeding_cut(hand)
	TEST_ASSERT(arm_cut.bleeding(), "a fresh deep cut should bleed")
	TEST_ASSERT(hand_cut.bleeding(), "a fresh deep cut on the hand should bleed")

	var/obj/item/tourniquet/T = allocate(/obj/item/tourniquet)
	TEST_ASSERT(arm.apply_tourniquet(T), "the tourniquet should go on the arm")
	TEST_ASSERT(arm.flow_occluded(), "the tourniquetted arm should have no flow")
	TEST_ASSERT(hand.flow_occluded(), "the hand below the tourniquet should have no flow")
	var/obj/item/organ/external/other_arm = H.get_organ(BP_R_ARM)
	TEST_ASSERT(!other_arm.flow_occluded(), "the other arm should keep its flow")
	TEST_ASSERT(!arm_cut.bleeding(), "the cut under the tourniquet should stop bleeding")
	TEST_ASSERT(!hand_cut.bleeding(), "a cut below the tourniquet should stop bleeding")
	TEST_ASSERT(!QDELETED(arm_cut) && arm_cut.damage > 0, "the tourniquet must not remove the wound")
	TEST_ASSERT(!(arm.status & ORGAN_BLEEDING), "the arm should no longer be flagged as bleeding")

	var/datum/affliction/limb_ischemia/I = H.body.find_affliction(/datum/affliction/limb_ischemia, arm)
	TEST_ASSERT_NOTNULL(I, "a tourniquet should start limb ischemia on its limb")
	var/last = I.severity
	for(var/i in 1 to 20)
		I.tick()
		TEST_ASSERT(I.severity > last, "ischemia should keep growing while the flow is cut (tick [i]: [last] -> [I.severity])")
		last = I.severity

	TEST_ASSERT_EQUAL(arm.remove_tourniquet(), T, "loosening should hand back the tourniquet")
	TEST_ASSERT(!arm.flow_occluded(), "loosening the tourniquet should restore flow")
	TEST_ASSERT(arm_cut.bleeding(), "the cut should bleed again once flow returns")
	var/before = I.severity
	I.tick()
	TEST_ASSERT(QDELETED(I) || I.severity < before, "ischemia should recede once flow returns ([before] -> [I.severity])")


/// Stasis slows affliction progression by the factor; leaving the stasis bag
/// restores normal progression.
/datum/unit_test/dq_stab_stasis_slows_progression

/datum/unit_test/dq_stab_stasis_slows_progression/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/dq_test_progressor, chest, 10)
	TEST_ASSERT_NOTNULL(A, "the test affliction could not be afflicted")

	TEST_ASSERT_EQUAL(dq_stab_run_cycles(H, 10), 0, "no cycle should pause without stasis")
	var/base_gain = A.severity - 10
	TEST_ASSERT(base_gain > 0, "the test affliction should progress")

	TEST_ASSERT(life_test_place(H), "no floor to place the test human on")
	var/turf/outside = H.loc
	var/obj/structure/closet/body_bag/cryobag/bag = allocate(/obj/structure/closet/body_bag/cryobag)
	A.set_severity(10)
	H.forceMove(bag)
	TEST_ASSERT(dq_near(H.factor(BF_STASIS), 0.9), "a stasis bag should hold BF_STASIS at 0.9, got [H.factor(BF_STASIS)]")
	var/paused = dq_stab_run_cycles(H, 10)
	TEST_ASSERT(paused >= 8, "deep stasis should pause about 9 of 10 cycles, paused [paused]")
	var/stasis_gain = A.severity - 10
	TEST_ASSERT(stasis_gain <= base_gain * 0.25, "stasis at 0.9 should cut progression to about a tenth ([stasis_gain] vs [base_gain])")

	paused = dq_stab_run_cycles(H, 100)
	TEST_ASSERT(paused >= 85 && paused <= 95, "deep stasis should pause about 90 of 100 cycles, paused [paused]")

	H.forceMove(outside)
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0, "leaving the stasis bag should end stasis")
	TEST_ASSERT(!H.get_modifier_of_type(/datum/modifier/stasis), "leaving the stasis bag should remove its stasis modifier")
	A.set_severity(10)
	TEST_ASSERT_EQUAL(dq_stab_run_cycles(H, 10), 0, "no cycle should pause after leaving stasis")
	TEST_ASSERT(dq_near(A.severity - 10, base_gain), "progression should be back to normal after stasis ([A.severity - 10] vs [base_gain])")


/// Two stasis sources on one mob: the deepest wins, and releasing one leaves
/// the other in place.
/datum/unit_test/dq_stab_stasis_sources

/datum/unit_test/dq_stab_stasis_sources/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/source_a = allocate(/obj/item/tourniquet)
	var/obj/item/source_b = allocate(/obj/item/tourniquet)
	H.set_stasis(/datum/modifier/stasis/light, source_a)
	H.set_stasis(/datum/modifier/stasis/total, source_b)
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 1, "the deepest stasis source should win")
	H.set_stasis(null, source_b)
	TEST_ASSERT(dq_near(H.factor(BF_STASIS), 0.5), "releasing one source should leave the other's stasis")
	H.set_stasis(null, source_a)
	TEST_ASSERT_EQUAL(H.factor(BF_STASIS), 0, "releasing every source should end stasis")


/// Hemostatic gauze runs down the bleed on the wound it's packed into.
/datum/unit_test/dq_stab_gauze_stops_wound_bleed

/datum/unit_test/dq_stab_gauze_stops_wound_bleed/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	var/datum/affliction/wound/W = dq_stab_bleeding_cut(arm)
	var/bleed_before = W.bleed_timer
	TEST_ASSERT(W.bleeding(), "a fresh deep cut should bleed")
	TEST_ASSERT(bleed_before > 0, "a fresh cut should have bleed time left")

	var/obj/item/stack/medical/field/hemostatic_gauze/G = allocate(/obj/item/stack/medical/field/hemostatic_gauze)
	TEST_ASSERT(G.apply_to_limb(H, arm, null) > 0, "the gauze should treat something")
	TEST_ASSERT(W.bleed_timer < bleed_before, "hemostatic gauze should run down the wound's bleed ([bleed_before] -> [W.bleed_timer])")
	TEST_ASSERT(!W.bleeding(), "a packed wound should stop bleeding")
	TEST_ASSERT(W.damage > 0, "gauze stops the bleed; it doesn't close the wound")


/// A splint cuts the slowdown and pain of a broken leg; taking it off brings
/// them back.
/datum/unit_test/dq_stab_splint_reduces_fracture_slowdown

/datum/unit_test/dq_stab_splint_reduces_fracture_slowdown/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	var/baseline_slowdown = H.factor(BF_SLOWDOWN)
	var/datum/affliction/untreated_fracture/F = H.body.afflict(/datum/affliction/untreated_fracture, leg)
	TEST_ASSERT_NOTNULL(F, "the fracture could not be afflicted")
	var/unset_slowdown = H.factor(BF_SLOWDOWN)
	var/unset_pain = H.factor(BF_PAIN)
	TEST_ASSERT(unset_slowdown > baseline_slowdown, "an unset broken leg should slow the patient ([baseline_slowdown] -> [unset_slowdown])")

	var/obj/item/stack/medical/splint/S = allocate(/obj/item/stack/medical/splint)
	TEST_ASSERT(leg.apply_splint(S), "the splint should go on")
	var/splinted_slowdown = H.factor(BF_SLOWDOWN)
	TEST_ASSERT(splinted_slowdown < unset_slowdown, "a splint should reduce fracture slowdown ([unset_slowdown] -> [splinted_slowdown])")
	TEST_ASSERT(H.factor(BF_PAIN) < unset_pain, "a splint should reduce fracture pain")

	TEST_ASSERT(leg.remove_splint(), "the splint should come off")
	TEST_ASSERT(dq_near(H.factor(BF_SLOWDOWN), unset_slowdown), "removing the splint should restore the fracture's slowdown")
