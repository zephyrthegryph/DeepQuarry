// MED-2: regression tests for the P0 rows of doc/medical_audit_findings.md.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// C1: a borg in thermal runaway recovers once its cooling loop circulates again. It has no
/// reagent holder, so before the fix nothing could treat it short of an admin heal.
/datum/unit_test/dq_p0_robot_thermal_runaway_recovers

/datum/unit_test/dq_p0_robot_thermal_runaway_recovers/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, run_loc_floor_bottom_left)
	var/datum/robot_component/cooling/loop = R.get_component(ROBOT_SLOT_COOLING)
	TEST_ASSERT(istype(loop), "a new borg should have a cooling loop")
	TEST_ASSERT(loop.circulation() >= ROBOT_CIRCULATION_OK, "a new borg's loop should circulate (got [loop.circulation()])")
	TEST_ASSERT_NOTNULL(R.body?.afflict(/datum/affliction/synthetic/thermal_runaway, null, AFFLICTION_SEVERITY_TERMINAL), "thermal runaway should afflict a borg")
	for(var/i in 1 to 20)
		R.process_heat()
		if(!R.body.has_affliction(/datum/affliction/synthetic/thermal_runaway))
			break
	TEST_ASSERT(!R.body.has_affliction(/datum/affliction/synthetic/thermal_runaway), "a circulating loop should bring a borg out of thermal runaway")

/// P2-F8: vodka and godka purge radiation instead of adding the drinker's dose back.
/datum/unit_test/dq_p0_vodka_purges_radiation

/datum/unit_test/dq_p0_vodka_purges_radiation/Run()
	for(var/reagent_type in list(/datum/reagent/ethanol/vodka, /datum/reagent/ethanol/godka))
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
		var/datum/reagent/drink = new reagent_type
		H.radiation = 100
		drink.affect_ingest(H, null, 2)
		TEST_ASSERT(H.radiation < 100, "[reagent_type] should lower radiation (100 -> [H.radiation])")
		TEST_ASSERT(H.radiation >= 0, "[reagent_type] must not drive radiation negative")
		qdel(drink)

/// P2-D4 / A8: a second death() call repeats no side effect (loot, links, signals).
/datum/unit_test/dq_p0_death_twice_no_repeat

/datum/unit_test/dq_p0_death_twice_no_repeat/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/datum/dq_vital_listener/listener = new
	listener.watch(M)
	TEST_ASSERT(M.death(), "the first death() should report the transition")
	TEST_ASSERT(!M.death(), "a second death() should report no transition")
	TEST_ASSERT_EQUAL(listener.deaths, 1, "mob_death is emitted once across two death() calls")
	TEST_ASSERT_EQUAL(listener.finals, 1, "the final hook runs once across two death() calls")
	qdel(listener)

/// A10: a mind created on a body adopts the body's identity instead of binding a blank one.
/datum/unit_test/dq_p0_mind_adopts_body_identity

/datum/unit_test/dq_p0_mind_adopts_body_identity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/character_identity/body_identity = H.identity()
	TEST_ASSERT_NOTNULL(body_identity, "a body always has an identity")
	H.record_genetic_effect(/datum/body_effect/no_clone, TRUE)
	TEST_ASSERT(body_identity.has_genetic_effect(/datum/body_effect/no_clone), "the body identity should carry no_clone")
	var/datum/mind/probe = new /datum/mind("dq_p0_probe")
	TEST_ASSERT_NULL(probe.identity, "a fresh mind has no identity until it enters a body")
	qdel(probe)
	H.mind_initialize()
	own(H.mind) // the mind owns the identity: the test deletes it rather than dropping it
	TEST_ASSERT_EQUAL(H.mind.get_identity(), body_identity, "the new mind should adopt the body's identity")
	TEST_ASSERT_EQUAL(H.identity(), body_identity, "the body should keep its identity")
	TEST_ASSERT(H.identity().has_genetic_effect(/datum/body_effect/no_clone), "no_clone must survive mind_initialize()")
	SSticker?.minds -= H.mind

/// A7: Notify Transcore from a brain with no mind or no record answers instead of runtiming.
/datum/unit_test/dq_p0_brain_backup_ping_no_record

/datum/unit_test/dq_p0_brain_backup_ping_no_record/Run()
	var/mob/living/carbon/brain/B = allocate(/mob/living/carbon/brain)
	TEST_ASSERT_NULL(B.mind, "a fresh brain mob has no mind")
	TEST_ASSERT(!B.backup_ping_resolve(), "no mind: no notification")
	rel_set(B, nameof(B.mind), own(new /datum/mind("dq_p0_no_backup"))) // the test deletes it (see dq_test_give_mind())
	B.mind.name = "dq p0 nobody"
	TEST_ASSERT(!B.backup_ping_resolve(), "no backup record: no notification")
	rel_clear(B, nameof(B.mind))

/// D13 / D14: rejuvenating or damaging a detached limb touches no owner.
/datum/unit_test/dq_p0_detached_limb_no_owner_runtime

/datum/unit_test/dq_p0_detached_limb_no_owner_runtime/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT_NOTNULL(arm, "the human should have a left arm")
	arm.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
	TEST_ASSERT(!QDELETED(arm), "a clean droplimb leaves the arm")
	TEST_ASSERT_NULL(arm.owner, "a dropped arm has no owner")
	arm.apply_wound_damage(0, 500) // ALLOW(check_grep): burn past the limb's cap: drives the body-internal spill-over path
	arm.apply_wound_damage(50, 0)  // ALLOW(check_grep): brute on a detached limb: drives the body-internal scream path
	arm.rejuvenate()               // D13
	TEST_ASSERT_NULL(arm.owner, "the arm should still be detached")
	qdel(arm)

/// D15b: a tourniquet starves every limb below it, so each one grows ischemia.
/datum/unit_test/dq_p0_tourniquet_ischemia_distal

/datum/unit_test/dq_p0_tourniquet_ischemia_distal/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/hand = H.get_organ(BP_L_HAND)
	var/obj/item/organ/external/other_hand = H.get_organ(BP_R_HAND)
	var/obj/item/tourniquet/T = allocate(/obj/item/tourniquet)
	TEST_ASSERT(arm.apply_tourniquet(T), "the tourniquet should go on the arm")
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/limb_ischemia, arm), "the cinched arm should be ischemic")
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/limb_ischemia, hand), "the hand below the tourniquet should be ischemic")
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/limb_ischemia, other_hand), "the other hand keeps its flow")
	arm.remove_tourniquet()

/// D16: an interrupted surgical step is abandoned: no complication, even with its target gone.
/datum/unit_test/dq_p0_surgery_interrupt_no_complication

/datum/unit_test/dq_p0_surgery_interrupt_no_complication/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/body/humanoid/B = H.body
	LAZYSET(B.surgery_records, REF(surgeon), list(BP_L_ARM, 100, REF(arm), 0))
	arm.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
	qdel(arm) // the work target is gone by the time the interruption lands
	var/list/current = H.get_afflictions()
	var/list/before = current.Copy()
	var/datum/act/op/A = new
	A.actor = surgeon
	A.key = surgery_op_key(/datum/surgical_step/treat/organ/suture)
	H.surgery_interrupted(A)
	TEST_ASSERT_NULL(H.surgery_record(surgeon), "the surgeon's record is dropped on interruption")
	for(var/datum/affliction/A2 as anything in H.get_afflictions())
		TEST_ASSERT(A2 in before, "an interruption must not complicate: new affliction [A2.type]")

#endif
