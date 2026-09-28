// Wave 5 loose ends: the protean cluster's explosions and every rig's power
// ledger, Total Reassembly through mend(), hypoxic cardiac irritability,
// breathing in bellies, the post-revival grace, fractures as afflictions and
// the cardiac rhythm vital.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// --- Protean -----------------------------------------------------------------------------

/// An explosion on the cluster lands on the protean through injure(); the
/// cluster's own integrity never moves.
/datum/unit_test/dq_protean_rig_explosion_injures_protean

/datum/unit_test/dq_protean_rig_explosion_injures_protean/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/forms/protean/F = H.get_protean_forms()
	var/obj/item/rig/protean/R = F.rig
	TEST_ASSERT_NOTNULL(R, "the protean should own its rig")
	var/load_before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	var/integrity_before = R.get_integrity()
	R.ex_act(2)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_PHYSICAL) > load_before, "an explosion on the cluster should injure the protean")
	TEST_ASSERT_EQUAL(R.get_integrity(), integrity_before, "the cluster's own integrity must not move")

/// Every rig's cell moves through draw_power()/add_power(), not just the protean's.
/datum/unit_test/dq_rig_power_ledger_all_rigs

/datum/unit_test/dq_rig_power_ledger_all_rigs/Run()
	var/obj/item/rig/light/R = allocate(/obj/item/rig/light)
	TEST_ASSERT_NOTNULL(R.cell, "a light rig should come with a cell")
	R.cell.charge = R.cell.maxcharge / 2
	var/before = R.cell.charge
	TEST_ASSERT(R.draw_power(ROBOT_CELL_JOULES(50), src), "a half cell should cover a small draw")
	TEST_ASSERT(R.cell.charge < before, "the draw should come out of the cell")
	TEST_ASSERT(!R.draw_power(ROBOT_CELL_JOULES(R.cell.maxcharge * 2), src), "an all-or-nothing draw can't overdraw")
	TEST_ASSERT(R.draw_power(ROBOT_CELL_JOULES(R.cell.maxcharge * 2), src, partial = TRUE), "a partial draw takes what is there")
	TEST_ASSERT(R.cell.charge <= 0, "a partial overdraw should empty the cell ([R.cell.charge])")
	var/stored = R.add_power(ROBOT_CELL_JOULES(100), src)
	TEST_ASSERT(stored > 0, "add_power should charge the cell")
	TEST_ASSERT(R.cell.charge > 0, "the charge should show in the cell")

/// Total Reassembly rebuilds structure and cohesion and repairs through mend()
/// tags funded by its steel; afflictions it doesn't reach stay.
/datum/unit_test/dq_protean_total_reassembly_mends

/datum/unit_test/dq_protean_total_reassembly_mends/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/body/humanoid/nanoform/B = H.body
	TEST_ASSERT(istype(B), "a protean should have a nanoform body")
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	var/datum/affliction/contamination = B.afflict(/datum/affliction/nanite/contamination, refactory, 40)
	TEST_ASSERT_NOTNULL(contamination, "contamination should take hold")
	B.afflict(/datum/affliction/nanite/cohesion_loss, null, 30)
	H.injure(INJURY_BLUNT, 20, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/trauma_before = arm.get_trauma()
	TEST_ASSERT(trauma_before > 0, "the arm should be hurt")

	var/repaired = B.total_reassembly(4000)
	TEST_ASSERT(repaired > 0, "the steel should fund repair")
	TEST_ASSERT(arm.get_trauma() < trauma_before, "plating repair should reach the arm")
	TEST_ASSERT_NULL(B.find_affliction(/datum/affliction/nanite/cohesion_loss), "reassembly rebuilds cohesion")
	TEST_ASSERT(contamination in B.afflictions, "reassembly is not a full heal: contamination stays")

	// No steel, no repair beyond the structure.
	H.injure(INJURY_BLUNT, 20, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	trauma_before = arm.get_trauma()
	TEST_ASSERT_EQUAL(B.total_reassembly(0), 0, "unfunded reassembly repairs nothing")
	TEST_ASSERT_EQUAL(arm.get_trauma(), trauma_before, "unfunded reassembly leaves the arm")


// --- Physiology --------------------------------------------------------------------------

/// A deep oxygen debt makes the heart irritable (a factor), and an irritable
/// heart's unstable rhythm deteriorates faster.
/datum/unit_test/dq_physiology_hypoxia_irritates_heart

/datum/unit_test/dq_physiology_hypoxia_irritates_heart/Run()
	var/mob/living/carbon/human/hypoxic = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/control = allocate(/mob/living/carbon/human)
	control.add_oxygen_debt(PHYSIOLOGY_HYPOXIA_ARRHYTHMIA_THRESHOLD / 2, "unit test")
	TEST_ASSERT(dq_near(control.factor(BF_CARDIAC_IRRITABILITY), 1), "a shallow debt shouldn't irritate the heart ([control.factor(BF_CARDIAC_IRRITABILITY)])")
	hypoxic.add_oxygen_debt(95, "unit test")
	TEST_ASSERT(hypoxic.factor(BF_CARDIAC_IRRITABILITY) > 1.5, "a deep debt should irritate the heart ([hypoxic.factor(BF_CARDIAC_IRRITABILITY)])")

	var/datum/affliction/cardiac_arrhythmia/hot = hypoxic.induce_arrhythmia(CARDIAC_RHYTHM_TACHY)
	var/datum/affliction/cardiac_arrhythmia/calm = control.induce_arrhythmia(CARDIAC_RHYTHM_TACHY)
	TEST_ASSERT(hot && calm, "both hearts should take a tachyarrhythmia")
	hot.tick()
	calm.tick()
	TEST_ASSERT(hot.progression_rate > calm.progression_rate, "the hypoxic heart's rhythm should deteriorate faster ([hot.progression_rate] vs [calm.progression_rate])")

/// Breathing in a digesting belly: stale air lowers breath quality, and the
/// physiology turns that into debt. No direct debt is added.
/datum/unit_test/dq_physiology_belly_air

/datum/unit_test/dq_physiology_belly_air/Run()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human)
	var/obj/belly/B = allocate(/obj/belly, pred)
	prey.digestable = TRUE
	prey.forceMove(B)
	B.digest_mode = DM_HOLD
	B.digest_oxy = BELLY_AIR_STALE_AT
	TEST_ASSERT_EQUAL(B.breath_quality_for(prey), 1, "a holding belly's air is fine")
	B.digest_mode = DM_DIGEST
	B.digest_oxy = BELLY_AIR_STALE_AT / 2
	TEST_ASSERT(dq_near(B.breath_quality_for(prey), 0.5), "half-stale air should be half a breath ([B.breath_quality_for(prey)])")
	prey.body.set_breath_quality(1)
	TEST_ASSERT(dq_near(prey.body.physiology.breath_quality, 0.5), "the belly's air should reach breath quality ([prey.body.physiology.breath_quality])")
	B.digest_oxy = BELLY_AIR_STALE_AT
	prey.body.set_breath_quality(1)
	TEST_ASSERT_EQUAL(prey.body.physiology.breath_quality, 0, "stale air is no breath at all")
	physiology_test_run(prey, 5)
	TEST_ASSERT(prey.oxygen_debt() > 0, "breathing stale belly air should build oxygen debt")

	prey.digestable = FALSE
	TEST_ASSERT_EQUAL(B.breath_quality_for(prey), 1, "prey that refuse digestion breathe normally")

/// After circulation is restored, the debt is repaid faster and grows no new
/// ischemic lesions while it is repaid.
/datum/unit_test/dq_physiology_revival_grace

/datum/unit_test/dq_physiology_revival_grace/Run()
	var/mob/living/carbon/human/revived = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/control = allocate(/mob/living/carbon/human)
	revived.add_oxygen_debt(70, "unit test")
	control.add_oxygen_debt(70, "unit test")

	var/datum/affliction/cardiac_arrhythmia/A = revived.induce_arrhythmia(CARDIAC_RHYTHM_VF)
	TEST_ASSERT_NOTNULL(A, "VF should be inducible")
	TEST_ASSERT(revived.defibrillate_heart(), "a shock should convert VF")
	TEST_ASSERT(revived.body.physiology.in_revival_grace(), "cardioversion should start the post-revival grace")
	TEST_ASSERT(!control.body.physiology.in_revival_grace(), "no grace without a revival")

	physiology_test_run(revived, 3)
	physiology_test_run(control, 3)
	TEST_ASSERT(revived.oxygen_debt() < control.oxygen_debt(), "the grace should repay the debt faster ([revived.oxygen_debt()] vs [control.oxygen_debt()])")
	var/obj/item/organ/internal/brain/revived_brain = revived.organ_in(O_BRAIN)
	var/obj/item/organ/internal/brain/control_brain = control.organ_in(O_BRAIN)
	TEST_ASSERT_NULL(revived_brain.find_lesion(/datum/affliction/lesion/ischemic_injury), "a debt being repaid in the grace grows no ischemic lesion")
	TEST_ASSERT_NOTNULL(control_brain.find_lesion(/datum/affliction/lesion/ischemic_injury), "outside the grace the repaying debt still harms the brain")


// --- Fractures ---------------------------------------------------------------------------

/// The fracture affliction IS the fracture: fracture() afflicts, set-bone mends
/// it through TREAT_BONE_SETTING, and the limb reads broken only while it's there.
/datum/unit_test/dq_fracture_is_an_affliction

/datum/unit_test/dq_fracture_is_an_affliction/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT(!arm.is_fractured(), "a fresh arm isn't broken")
	TEST_ASSERT(arm.fracture(), "the arm should break")
	TEST_ASSERT(arm.is_fractured(), "a broken arm reads fractured")
	var/datum/affliction/untreated_fracture/F = H.body.find_affliction(/datum/affliction/untreated_fracture, arm)
	TEST_ASSERT_NOTNULL(F, "the fracture should be an affliction on the arm")
	F.cure()
	TEST_ASSERT(!arm.is_fractured(), "curing the affliction mends the bone")

	TEST_ASSERT(arm.fracture(), "the arm should break again")
	arm.open_surgical_site(arm.surgical_full_access(), 100)
	var/datum/surgical_step/S = surgical_step(/datum/surgical_step/set_bone)
	TEST_ASSERT(S.can_use(surgeon, H, BP_L_ARM, null), "set-bone should offer itself for a fracture")
	_surgery_perform(/datum/surgical_step/set_bone, surgeon, H, BP_L_ARM)
	TEST_ASSERT(!arm.is_fractured(), "setting the bone should mend the fracture")

	TEST_ASSERT(arm.fracture(), "the arm should break a third time")
	TEST_ASSERT(arm.mend_fracture(), "a bone heal should knit an unloaded fracture")
	TEST_ASSERT(!arm.is_fractured(), "mend_fracture cures the affliction")


// --- Diagnosis ---------------------------------------------------------------------------

/// Cardiac rhythm is a diagnosis vital, rendered for chat and TGUI.
/datum/unit_test/dq_diagnosis_heart_rhythm_vital

/datum/unit_test/dq_diagnosis_heart_rhythm_vital/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.body.heart_rhythm(), RHYTHM_SINUS, "a healthy heart is in sinus rhythm")
	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/vitals_monitor)
	TEST_ASSERT_EQUAL(D.heart_rhythm, RHYTHM_SINUS, "the vitals monitor reads the rhythm")
	qdel(D)

	H.induce_arrhythmia(CARDIAC_RHYTHM_VF)
	TEST_ASSERT_EQUAL(H.body.heart_rhythm(), RHYTHM_VFIB, "VF reads as VF")
	D = H.diagnose(/datum/diagnostic_profile/vitals_monitor)
	TEST_ASSERT_EQUAL(D.heart_rhythm, RHYTHM_VFIB, "the monitor shows VF")
	var/list/data = D.report_data()
	var/list/vitals = data["vitals"]
	TEST_ASSERT_EQUAL(vitals["heartRhythm"], RHYTHM_VFIB, "TGUI data carries the rhythm")
	TEST_ASSERT(findtext(D.render_vitals_text(), "ventricular fibrillation"), "the chat vitals line names the rhythm")
	qdel(D)

	D = H.diagnose(/datum/diagnostic_profile/health_analyzer)
	TEST_ASSERT_NULL(D.heart_rhythm, "a basic analyzer has no ECG")
	qdel(D)

	var/datum/affliction/cardiac_arrhythmia/A = H.cardiac_arrhythmia()
	A.set_rhythm(CARDIAC_RHYTHM_ASYSTOLE)
	TEST_ASSERT_EQUAL(H.body.heart_rhythm(), RHYTHM_ASYSTOLE, "asystole reads as asystole")
	A.set_rhythm(CARDIAC_RHYTHM_SINUS)
	TEST_ASSERT_EQUAL(H.body.heart_rhythm(), RHYTHM_POST_ARREST, "a converted rhythm reads post-arrest")

#endif
