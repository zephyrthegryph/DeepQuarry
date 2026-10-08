// Behaviour-preservation tests for pills and patches (phase 2, reagent containers, step 4): swallowing one, forcing it on somebody else, dissolving it in a
// container, cutting it up, and a patch's limb checks. They use the base and the click helpers of dq_p2_reagent_behaviour.dm.

// ---------------------------------------------------------------------------------------------------------------------
// Adapters
// ---------------------------------------------------------------------------------------------------------------------

/// The units on the person's skin (what a patch puts on).
/proc/rc_touch_units(mob/living/carbon/L)
	return round(L.touching.total_volume, 0.01)

/// A pill of `type` (a stocked one holds its own reagent).
/datum/unit_test/dq_p2_reagents/proc/rc_pill(type = /obj/item/reagent_containers/pill/antitox, turf/T)
	return allocate(type, T || run_loc_floor_bottom_left)

/// The powder items on the floor of the test turf.
/datum/unit_test/dq_p2_reagents/proc/rc_powders()
	. = list()
	for(var/obj/item/reagent_containers/powder/P in range(3, run_loc_floor_bottom_left))
		. += P

// ---------------------------------------------------------------------------------------------------------------------
// What they are
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_p2_reagents/pills_start_as_declared

/datum/unit_test/dq_p2_reagents/pills_start_as_declared/run_gate()
	var/obj/item/reagent_containers/pill/antitox/P = rc_pill()
	TEST_ASSERT_EQUAL(rc_capacity(P), 60, "a pill holds 60 units")
	TEST_ASSERT_EQUAL(rc_units(P), 30, "an anti-toxin pill holds its 30")
	TEST_ASSERT(!rc_open(P), "a pill is not an open container")
	var/obj/item/reagent_containers/pill/patch/patch = rc_pill(/obj/item/reagent_containers/pill/patch)
	TEST_ASSERT_EQUAL(rc_capacity(patch), 60, "a patch holds 60 units")
	TEST_ASSERT_EQUAL(rc_units(patch), 0, "and starts empty")
	TEST_ASSERT(!rc_open(patch), "a patch is not an open container")

// ---------------------------------------------------------------------------------------------------------------------
// Swallowing
// ---------------------------------------------------------------------------------------------------------------------

/// A pill clicked on yourself is swallowed at once: all of it goes to the stomach, and the pill is used up.
/datum/unit_test/dq_p2_reagents/pill_is_swallowed

/datum/unit_test/dq_p2_reagents/pill_is_swallowed/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/pill/P = rc_pill()
	var/before = rc_stomach_units(H)
	rc_click(H, H, P, I_HELP, FALSE)
	TEST_ASSERT(QDELETED(P), "the pill is used up at once")
	TEST_ASSERT(rc_stomach_units(H) - before > 20, "its contents are in the stomach")

/// In every stance (the pill does no harm).
/datum/unit_test/dq_p2_reagents/pill_is_swallowed_in_every_stance

/datum/unit_test/dq_p2_reagents/pill_is_swallowed_in_every_stance/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	for(var/stance in list(I_HELP, I_DISARM, I_GRAB, I_HURT))
		var/obj/item/reagent_containers/pill/P = rc_pill()
		rc_click(H, H, P, stance, FALSE)
		TEST_ASSERT(QDELETED(P), "swallowed in the [stance] stance")

/// A mask over the mouth stops it.
/datum/unit_test/dq_p2_reagents/pill_is_stopped_by_a_mask

/datum/unit_test/dq_p2_reagents/pill_is_stopped_by_a_mask/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas)
	TEST_ASSERT(H.equip_to_slot_if_possible(mask, SLOT_ID_MASK), "a mask is worn")
	var/obj/item/reagent_containers/pill/P = rc_pill()
	var/before = rc_stomach_units(H)
	rc_click(H, H, P)
	TEST_ASSERT(!QDELETED(P), "the pill is kept")
	TEST_ASSERT_EQUAL(rc_stomach_units(H), before, "and nothing is swallowed")
	var/mob/living/carbon/human/other = rc_actor()
	var/obj/item/reagent_containers/pill/Q = rc_pill()
	TEST_ASSERT(other.equip_to_slot_if_possible(allocate(/obj/item/clothing/mask/gas), SLOT_ID_MASK), "the other wears a mask")
	rc_click(H, other, Q)
	TEST_ASSERT(!QDELETED(Q), "nor is it forced on somebody wearing one")

/// Forcing a pill on somebody else takes three seconds, and all of it goes to their stomach.
/datum/unit_test/dq_p2_reagents/pill_is_forced_on_another_after_a_wait

/datum/unit_test/dq_p2_reagents/pill_is_forced_on_another_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/pill/P = rc_pill()
	var/before = rc_stomach_units(patient)
	rc_click(H, patient, P, I_HELP, FALSE)
	TEST_ASSERT(!QDELETED(P), "the pill is still there")
	test_time(1 SECONDS)
	TEST_ASSERT_EQUAL(rc_stomach_units(patient), before, "after a second nothing is swallowed")
	rc_settle()
	TEST_ASSERT(QDELETED(P), "after the wait the pill is used up")
	TEST_ASSERT(rc_stomach_units(patient) - before > 20, "and it is all in the patient's stomach")

/// The one who is fed must stay where they were.
/datum/unit_test/dq_p2_reagents/forced_pill_stops_when_the_patient_leaves

/datum/unit_test/dq_p2_reagents/forced_pill_stops_when_the_patient_leaves/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/pill/P = rc_pill()
	var/before = rc_stomach_units(patient)
	rc_click(H, patient, P, I_HELP, FALSE)
	test_time(1 SECONDS)
	patient.forceMove(run_loc_floor_top_right)
	rc_settle()
	TEST_ASSERT_EQUAL(rc_stomach_units(patient), before, "nothing is swallowed")

// ---------------------------------------------------------------------------------------------------------------------
// Dissolving
// ---------------------------------------------------------------------------------------------------------------------

/// A pill clicked on an open container with something in it dissolves in it: everything goes in, the pill is used up. An empty one refuses.
/datum/unit_test/dq_p2_reagents/pill_dissolves_in_a_container

/datum/unit_test/dq_p2_reagents/pill_dissolves_in_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	var/obj/item/reagent_containers/pill/P = rc_pill()
	rc_click(H, B, P)
	TEST_ASSERT(QDELETED(P), "the pill is used up")
	TEST_ASSERT_EQUAL(rc_units(B), 40, "its 30 units are in the beaker")
	var/obj/item/reagent_containers/glass/beaker/empty = rc_filled(/obj/item/reagent_containers/glass/beaker, 0)
	var/obj/item/reagent_containers/pill/Q = rc_pill()
	rc_click(H, empty, Q)
	TEST_ASSERT(!QDELETED(Q), "an empty beaker is no place to dissolve it")
	TEST_ASSERT_EQUAL(rc_units(empty), 0, "and it got nothing")
	var/obj/item/reagent_containers/glass/beaker/shut = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	cap_key_set(shut, REAGENT_CONTAINER_LID_OPEN, FALSE)
	var/obj/item/reagent_containers/pill/R = rc_pill()
	rc_click(H, shut, R)
	TEST_ASSERT(!QDELETED(R), "a closed container does not take it")
	TEST_ASSERT_EQUAL(rc_units(shut), 10, "and keeps what it had")

// ---------------------------------------------------------------------------------------------------------------------
// Cutting up
// ---------------------------------------------------------------------------------------------------------------------

/// A sharp thing used on a pill cuts it into a powder with the same contents; an ID card does too; anything else does nothing.
/datum/unit_test/dq_p2_reagents/pill_is_cut_up

/datum/unit_test/dq_p2_reagents/pill_is_cut_up/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/pill/P = rc_pill()
	var/obj/item/surgical/scalpel/knife = allocate(/obj/item/surgical/scalpel)
	rc_click(H, P, knife)
	TEST_ASSERT(QDELETED(P), "the pill is cut up")
	var/list/powders = rc_powders()
	TEST_ASSERT_EQUAL(length(powders), 1, "into a powder")
	var/obj/item/reagent_containers/powder/powder = powders[1]
	TEST_ASSERT_EQUAL(rc_units(powder), 30, "that holds what the pill held")
	var/obj/item/reagent_containers/pill/Q = rc_pill()
	var/obj/item/card/id/card = allocate(/obj/item/card/id)
	rc_click(H, Q, card)
	TEST_ASSERT(QDELETED(Q), "an ID card cuts it up too, clumsily")
	TEST_ASSERT_EQUAL(length(rc_powders()), 2, "into another powder")
	var/obj/item/reagent_containers/pill/R = rc_pill()
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	rc_click(H, R, pen)
	TEST_ASSERT(!QDELETED(R), "a pen does nothing to it")

// ---------------------------------------------------------------------------------------------------------------------
// Patches
// ---------------------------------------------------------------------------------------------------------------------

/// A patch on yourself goes on the limb aimed at: its contents are on the skin, the patch is used up.
/datum/unit_test/dq_p2_reagents/patch_is_put_on_yourself

/datum/unit_test/dq_p2_reagents/patch_is_put_on_yourself/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	H.zone_sel.set_selecting(BP_L_ARM)
	var/obj/item/reagent_containers/pill/patch/P = rc_pill(/obj/item/reagent_containers/pill/patch)
	P.reagents.add_reagent(REAGENT_ID_WATER, 20)
	var/before = rc_touch_units(H)
	rc_click(H, H, P, I_HELP, FALSE)
	TEST_ASSERT(QDELETED(P), "the patch is used up at once")
	TEST_ASSERT(rc_touch_units(H) - before > 10, "what it held is on the skin")
	H.zone_sel.set_selecting(BP_TORSO)

/// A patch on somebody else waits three seconds.
/datum/unit_test/dq_p2_reagents/patch_is_put_on_another_after_a_wait

/datum/unit_test/dq_p2_reagents/patch_is_put_on_another_after_a_wait/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/pill/patch/P = rc_pill(/obj/item/reagent_containers/pill/patch)
	P.reagents.add_reagent(REAGENT_ID_WATER, 20)
	var/before = rc_touch_units(patient)
	rc_click(H, patient, P, I_HELP, FALSE)
	test_time(1 SECONDS)
	TEST_ASSERT(!QDELETED(P), "after a second the patch is still in hand")
	TEST_ASSERT_EQUAL(rc_touch_units(patient), before, "and the patient has nothing on")
	rc_settle()
	TEST_ASSERT(QDELETED(P), "after the wait it is used up")
	TEST_ASSERT(rc_touch_units(patient) - before > 10, "and its contents are on the patient")

/// A robotic limb, a missing limb and thick material are refused.
/datum/unit_test/dq_p2_reagents/patch_is_refused_by_robotic_missing_and_thick

/datum/unit_test/dq_p2_reagents/patch_is_refused_by_robotic_missing_and_thick/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/mob/living/carbon/human/patient = rc_actor()
	var/obj/item/reagent_containers/pill/patch/P = rc_pill(/obj/item/reagent_containers/pill/patch)
	P.reagents.add_reagent(REAGENT_ID_WATER, 20)
	H.zone_sel.set_selecting(BP_L_ARM)
	var/obj/item/organ/external/arm = patient.get_organ(BP_L_ARM)
	arm.robotize()
	rc_click(H, patient, P)
	TEST_ASSERT(!QDELETED(P), "a robotic limb is refused")
	arm.droplimb(TRUE, DROPLIMB_EDGE)
	rc_click(H, patient, P)
	TEST_ASSERT(!QDELETED(P), "a missing limb is refused")
	H.zone_sel.set_selecting(BP_TORSO)
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	TEST_ASSERT(patient.equip_to_slot_if_possible(vest, SLOT_ID_SUIT), "the patient wears an armoured vest")
	rc_click(H, patient, P)
	TEST_ASSERT(!QDELETED(P), "thick material over the torso is refused")
	var/before = rc_touch_units(patient)
	rc_click(H, H, P, I_HELP, FALSE)
	TEST_ASSERT(QDELETED(P), "the same patch goes on yourself when the torso is bare")
	TEST_ASSERT(rc_touch_units(H) >= 0 && rc_touch_units(patient) == before, "and the patient got none")

/// A patch dissolves in a container as any pill does.
/datum/unit_test/dq_p2_reagents/patch_dissolves_in_a_container

/datum/unit_test/dq_p2_reagents/patch_dissolves_in_a_container/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 10)
	var/obj/item/reagent_containers/pill/patch/P = rc_pill(/obj/item/reagent_containers/pill/patch)
	P.reagents.add_reagent(REAGENT_ID_WATER, 20)
	rc_click(H, B, P)
	TEST_ASSERT(QDELETED(P), "the patch is used up")
	TEST_ASSERT_EQUAL(rc_units(B), 30, "and it is in the beaker")

/// A pill dissolved in a container that has room for only part of it: what fits goes in and the pill is used up all the same.
/datum/unit_test/dq_p2_reagents/pill_dissolves_what_fits

/datum/unit_test/dq_p2_reagents/pill_dissolves_what_fits/run_gate()
	var/mob/living/carbon/human/H = rc_actor()
	var/obj/item/reagent_containers/glass/beaker/B = rc_filled(/obj/item/reagent_containers/glass/beaker, 50)
	var/obj/item/reagent_containers/pill/P = rc_pill()
	rc_click(H, B, P)
	TEST_ASSERT(QDELETED(P), "the pill is used up")
	TEST_ASSERT_EQUAL(rc_units(B), 60, "the beaker took what fitted")
