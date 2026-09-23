// Unit tests for the vital-system afflictions: airway, breathing and
// circulation (code/modules/medical/conditions/vital_systems.dm).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A complete airway obstruction stops gas exchange; clearing it restores it.
/datum/unit_test/dq_vital_obstruction_blocks_breathing

/datum/unit_test/dq_vital_obstruction_blocks_breathing/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!H.breath_blocked(), "a healthy patient's breathing should not be blocked")

	var/datum/affliction/airway_obstruction/A = H.body.afflict(/datum/affliction/airway_obstruction)
	TEST_ASSERT_NOTNULL(A, "an airway obstruction should be afflictable")
	TEST_ASSERT(A.blocks_airway(), "a fresh obstruction should close the airway (severity [A.severity])")
	TEST_ASSERT(H.breath_blocked(), "a closed airway should block breathing")
	TEST_ASSERT(H.airway_obstructed(), "airway_obstructed() should report the obstruction")

	H.failed_last_breath = 0
	H.losebreath = 0
	var/debt_before = H.oxygen_debt()
	life_test_breathe(H)
	TEST_ASSERT(H.failed_last_breath, "breathing through a closed airway should fail")
	H.body.physiology_tick(2)
	TEST_ASSERT(H.oxygen_debt() > debt_before, "a closed airway should build oxygen debt")
	TEST_ASSERT_EQUAL(H.get_respiratory_rate(), 0, "a choking patient should have no respiratory rate")

	// Abdominal thrusts / an airway kit.
	var/obj/item/airway_kit/kit = allocate(/obj/item/airway_kit)
	TEST_ASSERT(kit.clear_airway(H), "the airway kit should treat the obstruction")
	TEST_ASSERT(QDELETED(A) || !A.blocks_airway(), "the obstruction should be cleared")
	TEST_ASSERT(!H.breath_blocked(), "a cleared airway should no longer block breathing")

/// Respiratory arrest stops breathing; a bag-valve mask breathes for the
/// patient, but not past a closed airway.
/datum/unit_test/dq_vital_respiratory_arrest_bvm

/datum/unit_test/dq_vital_respiratory_arrest_bvm/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/respiratory_arrest/R = H.body.afflict(/datum/affliction/respiratory_arrest)
	TEST_ASSERT_NOTNULL(R, "respiratory arrest should be afflictable")
	TEST_ASSERT(R.is_apneic(), "fresh respiratory arrest should be apneic (severity [R.severity])")
	TEST_ASSERT(H.breath_blocked(), "an apneic patient should not breathe on their own")

	var/obj/item/bag_valve_mask/bvm = allocate(/obj/item/bag_valve_mask)
	TEST_ASSERT(bvm.apply_ventilation(H), "the bag-valve mask should ventilate an open airway")
	TEST_ASSERT(H.body.is_supported(BF_RESP_DRIVE), "bagging should support the breathing drive")
	TEST_ASSERT(!H.breath_blocked(), "a bagged patient should get breaths")
	TEST_ASSERT(!QDELETED(R) && R.is_apneic(), "ventilation breathes for the patient; it doesn't cure the arrest")

	// Rescue breaths ventilate too; a closed airway defeats both.
	H.body.remove_supports(bvm)
	H.body.afflict(/datum/affliction/airway_obstruction)
	TEST_ASSERT(!bvm.apply_ventilation(H), "the bag should not empty into a blocked airway")
	TEST_ASSERT(H.breath_blocked(), "an obstructed, apneic patient should not breathe")

/// VF is shockable: the defibrillator's rhythm analysis accepts it and the
/// shock restores a perfusing rhythm.
/datum/unit_test/dq_vital_vf_defib_converts

/datum/unit_test/dq_vital_vf_defib_converts/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/cardiac_arrhythmia/A = H.induce_arrhythmia(CARDIAC_RHYTHM_VF)
	TEST_ASSERT_NOTNULL(A, "the heart should be able to fibrillate")
	TEST_ASSERT_EQUAL(A.rhythm, CARDIAC_RHYTHM_VF, "the rhythm should be VF")
	TEST_ASSERT(!H.has_cardiac_output(), "VF should have no cardiac output")
	TEST_ASSERT(A.consciousness_penalty() >= 100, "a patient in VF should be knocked out")
	TEST_ASSERT_EQUAL(H.get_pulse_reading_bpm(), 0, "VF should have no measurable pulse")

	var/obj/item/shockpaddles/paddles = allocate(/obj/item/shockpaddles)
	TEST_ASSERT_NULL(paddles.can_defib(H), "the defibrillator should accept a living patient in VF")
	TEST_ASSERT(H.defibrillate_heart(), "a shock should convert VF")
	TEST_ASSERT_EQUAL(A.rhythm, CARDIAC_RHYTHM_SINUS, "VF should convert to a sinus rhythm")
	TEST_ASSERT(H.has_cardiac_output(), "a converted heart should perfuse")
	TEST_ASSERT_NOTNULL(paddles.can_defib(H), "the defibrillator should refuse a perfusing patient")

/// Asystole is not shockable; CPR with a vasopressor coarsens it into VF.
/datum/unit_test/dq_vital_asystole_defib_fails

/datum/unit_test/dq_vital_asystole_defib_fails/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/cardiac_arrhythmia/A = H.induce_arrhythmia(CARDIAC_RHYTHM_ASYSTOLE)
	TEST_ASSERT_NOTNULL(A, "the heart should be able to flatline")
	TEST_ASSERT(!H.has_cardiac_output(), "asystole should have no cardiac output")

	var/obj/item/shockpaddles/paddles = allocate(/obj/item/shockpaddles)
	TEST_ASSERT_NOTNULL(paddles.can_defib(H), "the defibrillator should refuse to shock asystole")
	TEST_ASSERT(!H.defibrillate_heart(), "a shock should not convert asystole")
	TEST_ASSERT_EQUAL(A.rhythm, CARDIAC_RHYTHM_ASYSTOLE, "asystole should survive a shock")

	// Adrenaline on board + compressions: the flatline coarsens into VF.
	H.bloodstr.add_reagent(REAGENT_ID_ADRENALINE, 10)
	for(var/i in 1 to 80)
		H.mend(TREAT_CHEST_COMPRESSION, 1)
		if(A.rhythm != CARDIAC_RHYTHM_ASYSTOLE)
			break
	TEST_ASSERT_EQUAL(A.rhythm, CARDIAC_RHYTHM_VF, "CPR with a vasopressor should coarsen asystole into VF")
	TEST_ASSERT(H.defibrillate_heart(), "the resulting VF should be shockable")

/// No cardiac output builds oxygen debt that kills the brain; CPR (a cardiac
/// output support) slows it.
/datum/unit_test/dq_vital_cpr_slows_ischemia

/datum/unit_test/dq_vital_cpr_slows_ischemia/Run()
	var/mob/living/carbon/human/without_cpr = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/with_cpr = allocate(/mob/living/carbon/human)
	var/datum/affliction/cardiac_arrhythmia/A1 = without_cpr.induce_arrhythmia(CARDIAC_RHYTHM_VF)
	var/datum/affliction/cardiac_arrhythmia/A2 = with_cpr.induce_arrhythmia(CARDIAC_RHYTHM_VF)
	TEST_ASSERT(A1 && A2, "both hearts should fibrillate")
	var/obj/item/organ/internal/brain/B1 = without_cpr.internal_organs_by_name[O_BRAIN]
	var/obj/item/organ/internal/brain/B2 = with_cpr.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT(B1 && B2, "both patients need brains")

	var/obj/item/rescuer = allocate(/obj/item/bag_valve_mask)
	for(var/i in 1 to 60)
		with_cpr.body.add_support(rescuer, BF_PUMP, SUPPORT_CPR_PUMP, CPR_COMPRESSION_WINDOW)
		without_cpr.body.physiology_tick(2)
		with_cpr.body.physiology_tick(2)

	TEST_ASSERT(without_cpr.body.perfusion() <= 0, "VF should not perfuse ([without_cpr.body.perfusion()])")
	TEST_ASSERT(with_cpr.body.perfusion() > 0, "CPR should hold perfusion above nothing")
	TEST_ASSERT(B1.damage > 0, "a stopped heart should injure the brain")
	TEST_ASSERT_NOTNULL(B1.find_lesion(/datum/affliction/lesion/ischemic_injury), "arrest brain injury should be an ischemic lesion")
	TEST_ASSERT(B2.damage < B1.damage, "CPR should slow brain ischemia ([B2.damage] vs [B1.damage])")
	TEST_ASSERT(with_cpr.oxygen_debt() > 0, "CPR only gives partial perfusion")
	TEST_ASSERT(with_cpr.oxygen_debt() < without_cpr.oxygen_debt(), "CPR should slow the oxygen debt ([with_cpr.oxygen_debt()] vs [without_cpr.oxygen_debt()])")

/// A decompression needle vents a tension pneumothorax.
/datum/unit_test/dq_vital_pneumothorax_decompression

/datum/unit_test/dq_vital_pneumothorax_decompression/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/pneumothorax/P = H.body.afflict(/datum/affliction/pneumothorax, H.get_organ(BP_TORSO), 80)
	TEST_ASSERT_NOTNULL(P, "a pneumothorax should be afflictable on the chest")
	P.recompute_stage_from_severity()
	TEST_ASSERT_EQUAL(P.stage, "Tension", "a severe pneumothorax should be under tension")

	var/obj/item/decompression_needle/needle = allocate(/obj/item/decompression_needle)
	TEST_ASSERT(needle.decompress(H), "the needle should decompress the chest")
	TEST_ASSERT(QDELETED(P) || P.severity < 60, "decompression should relieve the tension")
	TEST_ASSERT(QDELETED(P) || P.decompressed, "the pneumothorax should remember it was vented")

#endif
