// Chain tests for the physiology (code/modules/body/physiology.dm): a
// mechanism changes a factor, breath or blood; the physiology turns lost
// delivery into oxygen debt; the debt grows hypoxia and brain lesions.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Run `ticks` physiology steps of two seconds each.
/proc/physiology_test_run(mob/living/L, ticks)
	for(var/i in 1 to ticks)
		L.body.physiology_tick(2)

/// A healthy patient is settled: full ventilation and perfusion, no debt.
/datum/unit_test/dq_physiology_healthy_baseline

/datum/unit_test/dq_physiology_healthy_baseline/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.body.ventilation(), 1, "a healthy patient should ventilate fully")
	TEST_ASSERT(H.body.oxygenation() >= 95, "a healthy patient should saturate ([H.body.oxygenation()])")
	TEST_ASSERT_EQUAL(H.body.perfusion(), 1, "a healthy patient should perfuse fully")
	physiology_test_run(H, 5)
	TEST_ASSERT_EQUAL(H.oxygen_debt(), 0, "a healthy patient should build no oxygen debt")
	TEST_ASSERT(H.body.heart_rate() > 0, "a healthy heart should beat")
	var/list/bp = H.body.blood_pressure()
	TEST_ASSERT(length(bp) == 2 && bp[1] > bp[2], "blood pressure should read systolic over diastolic")
	TEST_ASSERT(H.body.respiratory_rate() > 0, "a healthy patient should breathe")

/// Occluded airway -> no ventilation -> oxygen debt -> tissue hypoxia ->
/// ischemic brain lesions.
/datum/unit_test/dq_physiology_occluded_airway_to_brain_lesion

/datum/unit_test/dq_physiology_occluded_airway_to_brain_lesion/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT_NOTNULL(B, "the patient needs a brain")
	var/datum/affliction/airway_obstruction/A = H.body.afflict(/datum/affliction/airway_obstruction)
	TEST_ASSERT(A?.blocks_airway(), "a fresh obstruction should close the airway")
	TEST_ASSERT(H.body.ventilation() < PHYSIOLOGY_APNEA_VENTILATION, "a closed airway should stop ventilation ([H.body.ventilation()])")
	TEST_ASSERT_EQUAL(H.body.respiratory_rate(), 0, "a closed airway should have no respiratory rate")

	physiology_test_run(H, 60)
	TEST_ASSERT(H.oxygen_debt() > DQ_HYPOXIA_BRAIN_DAMAGE, "two minutes with a closed airway should build a deep oxygen debt ([H.oxygen_debt()])")
	var/datum/affliction/tissue_hypoxia/T = H.body.find_affliction(/datum/affliction/tissue_hypoxia)
	TEST_ASSERT_NOTNULL(T, "the oxygen debt should show as tissue hypoxia")
	TEST_ASSERT(B.damage > 0, "the debt should injure the brain")
	TEST_ASSERT_NOTNULL(B.find_lesion(/datum/affliction/lesion/ischemic_injury), "hypoxic brain injury should be an ischemic lesion")

/// Respiratory arrest builds debt; a bag-valve mask's drive support prevents it.
/datum/unit_test/dq_physiology_bvm_support_prevents_debt

/datum/unit_test/dq_physiology_bvm_support_prevents_debt/Run()
	var/mob/living/carbon/human/bagged = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/apneic = allocate(/mob/living/carbon/human)
	TEST_ASSERT(bagged.body.afflict(/datum/affliction/respiratory_arrest) && apneic.body.afflict(/datum/affliction/respiratory_arrest), "respiratory arrest should be afflictable")

	var/obj/item/bag_valve_mask/bvm = allocate(/obj/item/bag_valve_mask)
	TEST_ASSERT(bvm.apply_ventilation(bagged), "the mask should ventilate an open airway")
	TEST_ASSERT(bagged.body.ventilation() >= SUPPORT_BVM_DRIVE, "the mask should hold ventilation at its floor ([bagged.body.ventilation()])")
	physiology_test_run(bagged, 5)
	physiology_test_run(apneic, 5)
	TEST_ASSERT_EQUAL(bagged.oxygen_debt(), 0, "a bagged patient should build no oxygen debt ([bagged.oxygen_debt()])")
	TEST_ASSERT(apneic.oxygen_debt() > 0, "an unbagged apneic patient should build oxygen debt")

	// The mask supports the drive, so it can't push past a closed airway.
	bagged.body.afflict(/datum/affliction/airway_obstruction)
	bvm.apply_ventilation(bagged)
	TEST_ASSERT(bagged.body.ventilation() < PHYSIOLOGY_APNEA_VENTILATION, "a mask can't ventilate through a closed airway")

/// A cyanide-like poison: the breath is good and saturation normal, yet the
/// tissues can't use the oxygen, so the debt climbs.
/datum/unit_test/dq_physiology_cyanide_debt_despite_good_breath

/datum/unit_test/dq_physiology_cyanide_debt_despite_good_breath/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_CYANIDE, 10)
	TEST_ASSERT(H.factor(BF_TISSUE_UPTAKE) < 0.5, "cyanide should block tissue oxygen uptake ([H.factor(BF_TISSUE_UPTAKE)])")
	TEST_ASSERT_EQUAL(H.body.ventilation(), 1, "cyanide shouldn't touch ventilation")
	TEST_ASSERT(H.body.oxygenation() >= 95, "cyanide leaves saturation normal ([H.body.oxygenation()])")
	physiology_test_run(H, 10)
	TEST_ASSERT(H.oxygen_debt() > 0, "cyanide should build oxygen debt despite good breathing")

/// Losing blood lowers perfusion (and quickens the heart).
/datum/unit_test/dq_physiology_blood_loss_lowers_perfusion

/datum/unit_test/dq_physiology_blood_loss_lowers_perfusion/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H.vessel, "the patient needs blood")
	var/perfusion_before = H.body.perfusion()
	var/rate_before = H.body.heart_rate()
	H.vessel.remove_reagent(REAGENT_ID_BLOOD, H.species.blood_volume * 0.6)
	H.run_life_system(/datum/life_system/blood)
	TEST_ASSERT(H.body.perfusion() < perfusion_before, "losing blood should lower perfusion ([perfusion_before] -> [H.body.perfusion()])")
	TEST_ASSERT(H.body.heart_rate() > rate_before, "the heart should race to compensate ([rate_before] -> [H.body.heart_rate()])")
	physiology_test_run(H, 5)
	TEST_ASSERT(H.oxygen_debt() > 0, "losing 60% of the blood should starve the tissues")

/// Dexalin raises oxygen carriage and pays the debt down faster than
/// breathing alone.
/datum/unit_test/dq_physiology_dexalin_recovers

/datum/unit_test/dq_physiology_dexalin_recovers/Run()
	var/mob/living/carbon/human/treated = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/control = allocate(/mob/living/carbon/human)
	treated.add_oxygen_debt(40, "unit test")
	control.add_oxygen_debt(40, "unit test")
	treated.bloodstr.add_reagent(REAGENT_ID_DEXALIN, 20)
	TEST_ASSERT(treated.factor(BF_O2_CARRIAGE) > 1, "dexalin should raise oxygen carriage")
	for(var/i in 1 to 5)
		treated.body.physiology_tick(2)
		control.body.physiology_tick(2)
		treated.body.life_tick()
		control.body.life_tick()
	TEST_ASSERT(control.oxygen_debt() < 40, "a breathing patient should repay the debt on their own")
	TEST_ASSERT(treated.oxygen_debt() < control.oxygen_debt(), "dexalin should repay the debt faster ([treated.oxygen_debt()] vs [control.oxygen_debt()])")

/// Simple creatures carry oxygen debt as load and have no respiratory model.
/datum/unit_test/dq_physiology_simple_plan

/datum/unit_test/dq_physiology_simple_plan/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT_NULL(M.body.ventilation(), "a simple body has no ventilation model")
	TEST_ASSERT(M.add_oxygen_debt(5, "unit test") > 0, "a simple body should take oxygen debt")
	TEST_ASSERT(M.oxygen_debt() > 0, "the debt should read back")
	TEST_ASSERT(M.body.find_affliction(/datum/affliction/load/hypoxia), "a simple body carries the debt as load")

#endif
