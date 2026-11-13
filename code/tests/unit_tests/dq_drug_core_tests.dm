// Unit tests for the drug-rework core: drug masking of instrument readings (hides), organ strains, seizures, nausea,
// crooked bones (malunion) and the N2O anaesthetic. Content: code/content/medical/diagnosis/diagnose.dm,
// code/content/reagents/drug_profile.dm, code/content/medical/conditions/{seizure,nausea,fracture_knit}.dm.
//
// A drug's `hides` and `strains` are per-type tables; the tests put them on the instance in the blood (a new list assigned to the instance's var), so
// no test-only reagent type is registered.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A human with `reagent_id` in the blood, and the reagent instance (for the tests that give it a profile).
/datum/unit_test/proc/_drug_core_dose(mob/living/carbon/human/H, reagent_id, amount = 5)
	H.bloodstr.add_reagent(reagent_id, amount)
	var/datum/reagent/R = H.bloodstr.get_reagent(reagent_id)
	TEST_ASSERT_NOTNULL(R, "setup: [reagent_id] is in the blood")
	return R


// --- Hides: the diagnosis masks the readings, the body keeps them -----------------------------------------------

/datum/unit_test/dq_drug_hides_fever_on_instrument

/datum/unit_test/dq_drug_hides_fever_on_instrument/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_bodytemperature(T0C + 40)
	var/datum/diagnosis/plain = H.diagnose(/datum/diagnostic_profile/vitals_monitor)
	TEST_ASSERT_NOTNULL(plain, "a vitals monitor produced no diagnosis")
	TEST_ASSERT(plain.temperature > 39, "without the drug the monitor reads the fever, got [plain.temperature]")
	TEST_ASSERT_NULL(plain.masked, "nothing is masked without a masking drug")

	var/datum/reagent/R = _drug_core_dose(H, REAGENT_ID_INAPROVALINE)
	R.hides = list(HIDE_FEVER)
	TEST_ASSERT(H.reading_hidden(HIDE_FEVER), "the drug in the blood masks the fever reading")
	var/datum/diagnosis/masked = H.diagnose(/datum/diagnostic_profile/vitals_monitor)
	TEST_ASSERT(masked.temperature < 38, "the masked monitor reads a normal temperature, got [masked.temperature]")
	TEST_ASSERT(H.body_temperature() > T0C + 39, "the patient is still feverish: only the report changed")
	var/datum/diagnosis/admin = H.diagnose(/datum/diagnostic_profile/admin)
	TEST_ASSERT(admin.temperature > 39, "an admin scan reads through the mask, got [admin.temperature]")
	qdel(plain)
	qdel(masked)
	qdel(admin)

	R.hides = null
	var/datum/diagnosis/after = H.diagnose(/datum/diagnostic_profile/vitals_monitor)
	TEST_ASSERT(after.temperature > 39, "the fever reads again once the drug no longer masks it, got [after.temperature]")
	qdel(after)

/// HIDE_PAIN drops the pain sign findings from an instrument; HIDE_PAIN_LOCATION keeps them without where it hurts. The fracture is still there.
/datum/unit_test/dq_drug_hides_pain_on_instrument

/datum/unit_test/dq_drug_hides_pain_on_instrument/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.fracture()
	var/datum/affliction/untreated_fracture/F = H.body.find_affliction(/datum/affliction/untreated_fracture, arm)
	TEST_ASSERT_NOTNULL(F, "setup: the arm is fractured")
	F.add_active_symptoms(/datum/affliction_symptom/sharp_pain)
	var/datum/affliction_symptom/sharp = affliction_symptom(/datum/affliction_symptom/sharp_pain)
	var/sign_name = sharp.examine_line || sharp.name

	var/datum/diagnosis/plain = H.diagnose(/datum/diagnostic_profile/body_scanner)
	var/datum/diagnosis_finding/seen = _drug_core_find_sign(plain, sign_name)
	TEST_ASSERT_NOTNULL(seen, "without the drug the scanner reports the pain sign")
	TEST_ASSERT(length(seen.location), "the pain sign is located")
	qdel(plain)

	var/datum/reagent/R = _drug_core_dose(H, REAGENT_ID_INAPROVALINE)
	R.hides = list(HIDE_PAIN_LOCATION)
	var/datum/diagnosis/unlocated = H.diagnose(/datum/diagnostic_profile/body_scanner)
	var/datum/diagnosis_finding/vague = _drug_core_find_sign(unlocated, sign_name)
	TEST_ASSERT_NOTNULL(vague, "hiding only the location still reports the pain")
	TEST_ASSERT(!length(vague.location), "the pain no longer says where it hurts")
	qdel(unlocated)

	R.hides = list(HIDE_PAIN)
	var/datum/diagnosis/hidden = H.diagnose(/datum/diagnostic_profile/body_scanner)
	TEST_ASSERT_NULL(_drug_core_find_sign(hidden, sign_name), "the pain sign is gone from the masked report")
	TEST_ASSERT(hidden.has_finding_for(/datum/affliction/untreated_fracture), "the fracture itself is still reported")
	TEST_ASSERT(arm.is_fractured(), "the fracture is still on the body")
	qdel(hidden)

/datum/unit_test/proc/_drug_core_find_sign(datum/diagnosis/D, sign_name)
	for(var/datum/diagnosis_finding/F as anything in D.findings)
		if(F.kind == DIAG_FINDING_SIGN && F.name == sign_name)
			return F
	return null


// --- Strains: organ damage a healthy organ heals, a damaged one does not ----------------------------------------

/datum/unit_test/dq_drug_strain_heals_when_healthy

/datum/unit_test/dq_drug_strain_heals_when_healthy/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	TEST_ASSERT_NOTNULL(liver, "no liver")
	var/datum/reagent/R = _drug_core_dose(H, REAGENT_ID_INAPROVALINE)
	R.strains = alist(O_LIVER = DRUG_STRAIN_MODERATE)
	for(var/i in 1 to 20)
		R.apply_strains(H, 1)
	TEST_ASSERT(liver.damage > 0, "the strain damages the liver")
	TEST_ASSERT(liver.damage < liver.natural_heal_ceiling(), "a standard run of doses keeps a healthy liver under the natural heal ceiling, got [liver.damage]")
	var/before = liver.damage
	TEST_ASSERT(H.mend(TREAT_REGENERATION, 100, liver) > 0, "natural regeneration still works on the strained liver")
	TEST_ASSERT(liver.damage < before, "regeneration heals the strain back, from [before] to [liver.damage]")

/datum/unit_test/dq_drug_strain_accumulates_when_damaged

/datum/unit_test/dq_drug_strain_accumulates_when_damaged/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	dq_test_set_organ_damage(liver, liver.natural_heal_ceiling() + 5)
	var/start = liver.damage
	TEST_ASSERT(start >= liver.natural_heal_ceiling(), "setup: the liver is past the natural heal ceiling")
	var/datum/reagent/R = _drug_core_dose(H, REAGENT_ID_INAPROVALINE)
	R.strains = alist(O_LIVER = DRUG_STRAIN_MODERATE)
	for(var/i in 1 to 20)
		R.apply_strains(H, 1)
	TEST_ASSERT(liver.damage > start, "the strain adds to an organ already past the ceiling, [start] -> [liver.damage]")
	var/strained = liver.damage
	TEST_ASSERT_EQUAL(H.mend(TREAT_REGENERATION, 100, liver), 0, "an organ past the ceiling no longer regenerates by itself")
	TEST_ASSERT_EQUAL(liver.damage, strained, "so the strain stays")


// --- Seizures ------------------------------------------------------------------------------------------------

/datum/unit_test/dq_drug_seizure_needs_proneness

/datum/unit_test/dq_drug_seizure_needs_proneness/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.seizure_proneness, 0, "nobody is seizure-prone by default")
	TEST_ASSERT_EQUAL(H.seizure_threshold(), SEIZURE_BASE_THRESHOLD, "the threshold is the base one at zero proneness")
	for(var/i in 1 to 20)
		TEST_ASSERT(!H.seizure_from_shock(500), "no proneness, no seizure from any shock")
	H.injure(INJURY_ELECTRIC, 25, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT(!H.body.has_affliction(/datum/affliction/seizure), "an electric injury does not seize a body with no proneness")

	var/datum/proneness_source = new
	hold(H, STAT_SEIZURE_PRONENESS, 3, proneness_source)
	TEST_ASSERT_EQUAL(H.seizure_proneness, 3, "the proneness stat takes the hold")
	TEST_ASSERT_EQUAL(H.seizure_threshold(), SEIZURE_BASE_THRESHOLD - 3 * SEIZURE_PRONENESS_SCALE, "proneness lowers the threshold")
	TEST_ASSERT(!H.seizure_from_shock(25), "a shock under the threshold does not seize a mildly prone body")
	TEST_ASSERT(!H.body.has_affliction(/datum/affliction/seizure), "no seizure from a weak shock")

	release(H, STAT_SEIZURE_PRONENESS, proneness_source)
	hold(H, STAT_SEIZURE_PRONENESS, 10, proneness_source)
	TEST_ASSERT_EQUAL(H.seizure_threshold(), 0, "a strongly prone body seizes from any shock")
	H.injure(INJURY_ELECTRIC, 25, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/affliction/seizure/S = H.body.find_affliction(/datum/affliction/seizure, null)
	TEST_ASSERT_NOTNULL(S, "an electric injury seizes a strongly prone body")
	TEST_ASSERT(S.severity > 0, "the seizure starts at a severity")

	// It clears: an anticonvulsant ends it, and left alone it drains away on its own.
	H.mend(TREAT_ANTICONVULSANT, 100)
	TEST_ASSERT(!H.body.has_affliction(/datum/affliction/seizure), "an anticonvulsant ends the seizure")

	TEST_ASSERT(H.seizure_from_shock(25), "the prone body seizes again")
	S = H.body.find_affliction(/datum/affliction/seizure, null)
	TEST_ASSERT_NOTNULL(S, "setup: the second seizure")
	TEST_ASSERT(S.progression_rate < 0, "a seizure resolves on its own")
	var/before = S.severity
	S.tick()
	TEST_ASSERT(QDELETED(S) || S.severity < before, "a tick lowers the severity")
	qdel(proneness_source)

/datum/unit_test/dq_drug_seizure_is_not_chem_caused

/datum/unit_test/dq_drug_seizure_is_not_chem_caused/Run()
	var/datum/affliction/seizure/proto = dq_proto(/datum/affliction/seizure)
	TEST_ASSERT(!length(proto.caused_by_chems), "the base seizure is spawned by shocks, never by a chem dispatcher")
	TEST_ASSERT(proto.treated_by[TREAT_ANTICONVULSANT] > 0, "anticonvulsants treat it")
	var/datum/affliction/nausea/nausea = dq_proto(/datum/affliction/nausea)
	TEST_ASSERT(!length(nausea.caused_by_chems), "the base nausea is not chem-caused; drug subtypes add caused_by_chems")


// --- Nausea --------------------------------------------------------------------------------------------------

/datum/unit_test/dq_drug_nausea_treated_by_calcium_carbonate

/datum/unit_test/dq_drug_nausea_treated_by_calcium_carbonate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/control = allocate(/mob/living/carbon/human)
	// Under the vomiting threshold, so the ticks below only measure the treatment.
	var/datum/affliction/nausea/N = H.body.afflict(/datum/affliction/nausea, H.organ_in(O_STOMACH), NAUSEA_VOMIT_MIN_SEVERITY - 1)
	var/datum/affliction/nausea/C = control.body.afflict(/datum/affliction/nausea, control.organ_in(O_STOMACH), NAUSEA_VOMIT_MIN_SEVERITY - 1)
	TEST_ASSERT_NOTNULL(N, "nausea can be put on the stomach")
	TEST_ASSERT_NOTNULL(C, "setup: the control's nausea")
	TEST_ASSERT(N.treated_by[TREAT_ANTIEMETIC] > 0, "nausea is treated by the antiemetic mechanism")

	H.bloodstr.add_reagent(REAGENT_ID_CALCIUMCARBONATE, 10)
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	var/list/levels = H.body.treatment_levels()
	TEST_ASSERT(levels?[TREAT_ANTIEMETIC] > 0, "calcium carbonate provides the antiemetic mechanism")
	control.body.invalidate(BODY_DIRTY_TREATMENT)
	var/list/control_levels = control.body.treatment_levels()
	TEST_ASSERT(!control_levels?[TREAT_ANTIEMETIC], "nothing provides it without the drug")

	N.tick()
	C.tick()
	TEST_ASSERT(N.severity < C.severity, "calcium carbonate settles the nausea faster than leaving it, [N.severity] against [C.severity]")

	TEST_ASSERT(H.mend(TREAT_ANTIEMETIC, 100, H.organ_in(O_STOMACH)) > 0, "an instant antiemetic treats it too")
	TEST_ASSERT(!H.body.has_affliction(/datum/affliction/nausea), "and it is gone")


// --- Crooked bones -------------------------------------------------------------------------------------------

/// Bone repair on an unset fracture knits it crooked: a malunion replaces the fracture, and it costs the limb.
/datum/unit_test/dq_drug_osteodaxon_unset_fracture_goes_crooked

/datum/unit_test/dq_drug_osteodaxon_unset_fracture_goes_crooked/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	leg.fracture()
	TEST_ASSERT(leg.is_fractured(), "setup: the leg is broken")
	TEST_ASSERT(dq_reagent_knit_fracture(leg, TREAT_BONE_REPAIR) > 0, "osteodaxon's knit is delivered")
	TEST_ASSERT(!leg.is_fractured(), "the fracture is gone")
	var/datum/affliction/malunion/M = H.body.find_affliction(/datum/affliction/malunion, leg)
	TEST_ASSERT_NOTNULL(M, "an unset fracture heals crooked")
	TEST_ASSERT_EQUAL(M.progression_rate, 0, "a malunion never heals on its own")
	TEST_ASSERT_EQUAL(H.mend(TREAT_BONE_REPAIR, 100, leg), 0, "more bone repair does nothing to a crooked bone")
	TEST_ASSERT_EQUAL(H.mend(TREAT_BONE_SETTING, 100, leg), 0, "setting does not fix a bone that has already healed crooked")
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/malunion, leg), "the malunion stays")

/// A bone that was SET (the fracture is gone) has nothing for osteodaxon to knit: no malunion.
/datum/unit_test/dq_drug_osteodaxon_set_bone_stays_straight

/datum/unit_test/dq_drug_osteodaxon_set_bone_stays_straight/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.fracture()
	TEST_ASSERT(H.mend(TREAT_BONE_SETTING, 100, arm) > 0, "setting the bone cures the fracture")
	TEST_ASSERT(!arm.is_fractured(), "the bone is set")
	TEST_ASSERT_EQUAL(dq_reagent_knit_fracture(arm, TREAT_BONE_REPAIR), 0, "a set bone has nothing to knit")
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/malunion, arm), "osteodaxon on a set bone does not make a malunion")

/// A weak continuous bone-repair level (a trace) does not knit an unset fracture at all.
/datum/unit_test/dq_drug_weak_bone_repair_leaves_fracture

/datum/unit_test/dq_drug_weak_bone_repair_leaves_fracture/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.fracture()
	var/datum/affliction/untreated_fracture/F = H.body.find_affliction(/datum/affliction/untreated_fracture, arm)
	TEST_ASSERT_NOTNULL(F, "setup: the arm is fractured")
	TEST_ASSERT_EQUAL(F.receive_tagged_treatment(TREAT_BONE_REPAIR, FRACTURE_KNIT_MIN_LEVEL / 2, TRUE), 0, "a trace of bone repair does nothing")
	TEST_ASSERT(arm.is_fractured(), "the fracture stays")
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/malunion, arm), "and nothing healed crooked")

/datum/unit_test/dq_drug_osteodaxon_ache_is_a_side_effect

/datum/unit_test/dq_drug_osteodaxon_ache_is_a_side_effect/Run()
	var/datum/affliction/chem_side_effect/osteodaxon_ache/proto = dq_proto(/datum/affliction/chem_side_effect/osteodaxon_ache)
	TEST_ASSERT(proto.caused_by_chems[REAGENT_ID_OSTEODAXON] > 0, "osteodaxon causes the ache")
	TEST_ASSERT(/datum/affliction_symptom/bone_ache in proto.symptom_pool, "it presents as bone ache")


// --- N2O anaesthesia -----------------------------------------------------------------------------------------

/// Breathing the sleeping gas gives the analgesia the surgery flow reads, through the stat (no surgery special case).
/datum/unit_test/dq_drug_n2o_covers_surgical_pain

/datum/unit_test/dq_drug_n2o_covers_surgical_pain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.analgesia, 0, "setup: no analgesia")
	var/datum/gas_mixture/breath = new /datum/gas_mixture(2)
	breath.adjust_gas(GAS_N2O, 1)
	H.breathe_sleeping_gas(breath, 1, 100)
	TEST_ASSERT(H.has_body_effect(/datum/body_effect/n2o_anesthesia), "breathing N2O holds the anaesthetic effect")
	var/datum/surgical_step/set_bone = surgical_step(/datum/surgical_step/set_bone)
	TEST_ASSERT(H.analgesia + H.sedation >= set_bone.pain, "the patient's analgesia and sedation cover a bone-setting step's pain, got [H.analgesia] and [H.sedation] against [set_bone.pain]")
	H.remove_body_effect(/datum/body_effect/n2o_anesthesia)
	TEST_ASSERT_EQUAL(H.analgesia, 0, "the cover ends with the effect")
	qdel(breath)

#endif
