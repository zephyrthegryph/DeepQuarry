// MED-7: regression tests for the EXPO / NEW:HEAT rows of doc/medical_audit_findings.md.
// One test per row, named by row id.

/// B1: a topical on the skin (the touch holder) provides its treatment tags.
/datum/unit_test/dq_med7_b1_topicals_on_skin

/datum/unit_test/dq_med7_b1_topicals_on_skin/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H.touching, "setup: a human has a touch holder")
	H.touching.add_reagent(REAGENT_ID_BICARIDAZE, 10)
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	TEST_ASSERT(H.body.reagent_volume(REAGENT_ID_BICARIDAZE) > 0, "the skin holder's volume is counted")
	TEST_ASSERT(H.body.treatment_levels()?[TREAT_HEMOSTATIC] > 0, "a salve on the skin treats")

/// B2: a medical allergy (and death) gates a reagent's tags and factors like on_mob_life.
/datum/unit_test/dq_med7_b2_tag_gates

/datum/unit_test/dq_med7_b2_tag_gates/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/reagent/proto = SSchemistry.ready().chemical_reagents[REAGENT_ID_BICARIDINE]
	TEST_ASSERT(proto.acts_on_body(H), "setup: bicaridine acts on a healthy human")
	H.bloodstr.add_reagent(REAGENT_ID_BICARIDINE, 10)
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	TEST_ASSERT(H.body.treatment_levels()?[TREAT_TISSUE_REPAIR] > 0, "setup: bicaridine repairs tissue")
	var/old_allergens = H.species.medallergens
	rel_private(H, nameof(H.species)) // write on the mob's private species copy, never the registered one
	H.species.medallergens |= proto.medallergen_type
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	var/allergic_level = H.body.treatment_levels()?[TREAT_TISSUE_REPAIR] || 0
	var/allergic_gate = proto.acts_on_body(H)
	H.species.medallergens = old_allergens
	TEST_ASSERT(!allergic_gate, "an allergic patient gets no benefit from the reagent")
	TEST_ASSERT_EQUAL(allergic_level, 0, "an allergic patient's snapshot carries none of its tags")
	if(!proto.affects_dead)
		H.death()
		TEST_ASSERT(!proto.acts_on_body(H), "a reagent that doesn't affect the dead gives a corpse no tags")

/// B6: the species overdose multiplier is applied per call, never compounded onto the reagent.
/datum/unit_test/dq_med7_b6_overdose_mod_stable

/datum/unit_test/dq_med7_b6_overdose_mod_stable/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_BICARIDINE, 60)
	var/datum/reagent/R = H.bloodstr.get_reagent(REAGENT_ID_BICARIDINE)
	TEST_ASSERT_NOTNULL(R, "setup: bicaridine in the blood")
	var/before = R.overdose_mod
	for(var/i in 1 to 5)
		R.overdose(H, null, REM)
	TEST_ASSERT_EQUAL(R.overdose_mod, before, "overdose() must not rewrite overdose_mod")

/// B13: a reagent knits a fracture through mend(TREAT_BONE_SETTING).
/datum/unit_test/dq_med7_b13_knit_through_mend

/datum/unit_test/dq_med7_b13_knit_through_mend/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.fracture()
	TEST_ASSERT(arm.is_fractured(), "setup: the arm is broken")
	TEST_ASSERT(dq_reagent_knit_fracture(arm) > 0, "the knit is delivered through mend()")
	TEST_ASSERT(!arm.is_fractured(), "the fracture is gone")
	TEST_ASSERT_EQUAL(dq_reagent_knit_fracture(arm), 0, "an unbroken limb has nothing to knit")

/// B14 / P2-S12: anti-radiation drugs don't write radiation themselves; the purge goes
/// through purge_radiation(), driven by the TREAT_ANTIRADIATION tag.
/datum/unit_test/dq_med7_b14_radiation_through_tag

/datum/unit_test/dq_med7_b14_radiation_through_tag/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.apply_effect(200, IRRADIATE, 0)
	var/rads = H.radiation
	TEST_ASSERT(rads > 0, "setup: the human is irradiated")
	H.bloodstr.add_reagent(REAGENT_ID_HYRONALIN, 10)
	var/datum/reagent/R = H.bloodstr.get_reagent(REAGENT_ID_HYRONALIN)
	R.affect_blood(H, null, REM)
	TEST_ASSERT_EQUAL(H.radiation, rads, "hyronalin's affect_blood no longer writes radiation")
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	TEST_ASSERT(H.body.treatment_levels()?[TREAT_ANTIRADIATION] > 0, "hyronalin provides anti-radiation")
	var/removed = H.purge_radiation(10)
	TEST_ASSERT_EQUAL(removed, min(10, rads), "purge_radiation removes what it is asked to")
	H.purge_radiation(INFINITY)
	TEST_ASSERT_EQUAL(H.radiation, 0, "no radiation left")

/// B15: reagent heat is scaled by the amount metabolised and a drive never overshoots.
/datum/unit_test/dq_med7_b15_reagent_heat_scaled

/datum/unit_test/dq_med7_b15_reagent_heat_scaled/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/reagent/R = SSchemistry.ready().chemical_reagents[REAGENT_ID_CAPSAICIN]
	H.set_bodytemperature(BODYTEMP_NORMAL)
	TEST_ASSERT(abs(R.warm_body(H, 10, REM) - 10) < 0.01, "REM units give the full shift")
	TEST_ASSERT(abs(R.warm_body(H, 10, REM / 2) - 5) < 0.01, "half the metabolism gives half the shift")
	H.set_bodytemperature(BODYTEMP_NORMAL + 3)
	R.drive_body_temperature(H, BODYTEMP_NORMAL, 10, REM)
	TEST_ASSERT(abs(H.body_temperature() - BODYTEMP_NORMAL) < 0.01, "a drive stops at its target")
	var/datum/reagent/lepo = SSchemistry.ready().chemical_reagents[REAGENT_ID_LEPORAZINE]
	H.set_bodytemperature(BODYTEMP_NORMAL - 20)
	lepo.affect_blood(H, null, REM)
	TEST_ASSERT_EQUAL(H.body_temperature(), BODYTEMP_NORMAL - 20, "leporazine has no direct write on top of its tag")

/// C16: a fever is a raised set point (BF_TEMPERATURE), not a per-tick temperature write.
/datum/unit_test/dq_med7_c16_fever_is_setpoint

/datum/unit_test/dq_med7_c16_fever_is_setpoint/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/base = H.thermal_setpoint()
	TEST_ASSERT_EQUAL(base, H.species.body_temperature, "setup: no fever, the set point is the species norm")
	var/datum/affliction/A = H.body.afflict(/datum/affliction/sepsis, null, 100)
	TEST_ASSERT_NOTNULL(A, "setup: sepsis placed")
	H.set_bodytemperature(BODYTEMP_NORMAL)
	var/temp_before = H.body_temperature()
	A.tick()
	TEST_ASSERT_EQUAL(H.body_temperature(), temp_before, "the affliction's tick does not write body temperature")
	H.body.invalidate(BODY_DIRTY_FACTORS)
	TEST_ASSERT(H.thermal_setpoint() > base + 1, "sepsis raises the thermoregulation set point")

/// B25: alcohol withdrawal races the heart through a forced pulse factor.
/datum/unit_test/dq_med7_b25_withdrawal_pulse_factor

/datum/unit_test/dq_med7_b25_withdrawal_pulse_factor/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.apply_body_effect(/datum/body_effect/withdrawal_tachycardia, 10 SECONDS)
	TEST_ASSERT_EQUAL(H.factor(BF_PULSE_SET), PULSE_2FAST, "withdrawal forces a racing pulse")

/// D18a: the internal-bleed arrest reads mechanisms; myelamine is a strong hemostatic.
/datum/unit_test/dq_med7_d18a_ib_reads_tags

/datum/unit_test/dq_med7_d18a_ib_reads_tags/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_MYELAMINE, 10)
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	TEST_ASSERT(H.body.treatment_levels()?[TREAT_HEMOSTATIC] >= DQ_IB_STRONG_HEMOSTATIC, "10u myelamine is a strong hemostatic")

/// P2-D6 / P2-K6: the -daxon family is data; a partner reagent switches to the clash effect.
/datum/unit_test/dq_med7_p2d6_daxon_data

/datum/unit_test/dq_med7_p2d6_daxon_data/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/reagent/respiro = SSchemistry.ready().chemical_reagents[REAGENT_ID_RESPIRODAXON]
	TEST_ASSERT(O_LUNGS in TYPE_TABLE_GET(respiro, daxon_organs), "respirodaxon targets the lungs")
	TEST_ASSERT(REAGENT_ID_GASTIRODAXON in TYPE_TABLE_GET(respiro, daxon_partners), "gastirodaxon is its partner")
	H.losebreath = 8
	respiro.affect_blood(H, null, REM)
	TEST_ASSERT_EQUAL(H.losebreath, 4, "alone, respirodaxon eases breathing")
	H.bloodstr.add_reagent(REAGENT_ID_GASTIRODAXON, 5)
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	H.losebreath = 0
	respiro.affect_blood(H, null, REM)
	TEST_ASSERT_EQUAL(H.losebreath, 3, "with its partner present, respirodaxon clashes")

/// P2-S9: can_inject takes the delivery method; a hypo still asks the same question.
/datum/unit_test/dq_med7_p2s9_one_can_inject

/datum/unit_test/dq_med7_p2s9_one_can_inject/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(H.can_inject(null, FALSE, BP_TORSO, TRUE, INJECT_METHOD_NEEDLE), "bare skin takes a needle")
	TEST_ASSERT(H.can_inject(null, FALSE, BP_TORSO, TRUE, INJECT_METHOD_HYPO), "bare skin takes a hypo")
	TEST_ASSERT(!H.can_inject(null, FALSE, "no_such_zone", TRUE, INJECT_METHOD_HYPO), "a hypo is refused where there is no limb")

/// P2-S12: radiation goes in and out through one set of writers that clamp and move the
/// acute dose into the accumulated dose.
/datum/unit_test/dq_med7_p2s12_radiation_writers

/datum/unit_test/dq_med7_p2s12_radiation_writers/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.add_radiation(-5), 0, "a negative dose adds nothing")
	H.add_radiation(RADIATION_CAP * 2)
	TEST_ASSERT_EQUAL(H.radiation, RADIATION_CAP, "the acute dose is capped")
	H.decay_radiation(100, 40)
	TEST_ASSERT_EQUAL(H.radiation, RADIATION_CAP - 100, "decay lowers the acute dose")
	TEST_ASSERT_EQUAL(H.accumulated_rads, 40, "decay settles into the accumulated dose")
	H.purge_radiation(RADIATION_CAP)
	TEST_ASSERT_EQUAL(H.radiation, 0, "a purge never goes below zero")
	TEST_ASSERT_EQUAL(H.accumulated_rads, 0, "a purge clears the accumulated dose too")
	H.add_radiation(50)
	H.decay_radiation(0, 10)
	H.clear_radiation()
	TEST_ASSERT(!H.radiation && !H.accumulated_rads, "clear_radiation empties both doses")
