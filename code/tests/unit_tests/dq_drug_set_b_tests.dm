// Unit tests for the second drug set: the organ daxons, the brain and nerve drugs, the circulation drugs and the antimicrobials.
// Reagents: code/content/reagents/reagents/content/medicine/; their added symptoms and interactions:
// code/content/medical/conditions/pharmacology/drug_set_b.dm. The profile mechanics (strains, hides) are tested in dq_drug_core_tests.dm.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The reagent prototype of `reagent_id`.
/datum/unit_test/proc/_drug_b_reagent(reagent_id)
	var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
	TEST_ASSERT_NOTNULL(R, "reagent [reagent_id] is registered")
	return R


// --- Data audit: each drug declares the profile the design gives it ----------------------------------------------------------------

/datum/unit_test/dq_drug_set_b_organ_daxons

/datum/unit_test/dq_drug_set_b_organ_daxons/Run()
	var/datum/reagent/cord = _drug_b_reagent(REAGENT_ID_CORDRADAXON)
	TEST_ASSERT(cord.treatment_tags[TREAT_CARDIAC] > 0, "cordradaxon treats the heart")
	TEST_ASSERT(HIDE_PULSE_IRREGULAR in cord.hides, "cordradaxon hides an irregular pulse")
	TEST_ASSERT(cord.factors[STAT_BP_SYSTOLIC] < 0, "cordradaxon lowers the blood pressure")

	var/datum/reagent/resp = _drug_b_reagent(REAGENT_ID_RESPIRODAXON)
	TEST_ASSERT(resp.treatment_tags[TREAT_RESPIRATORY] > 0, "respirodaxon treats the lungs")
	var/datum/affliction/airway_effect = dq_proto(/datum/affliction/chem_side_effect/respirodaxon_airway_sensitivity)
	TEST_ASSERT(airway_effect.caused_by_chems[REAGENT_ID_RESPIRODAXON] > 0, "respirodaxon leaves the airway sensitive")
	TEST_ASSERT(airway_effect.factors[STAT_GAS_EXCHANGE] < 1, "the sensitive airway exchanges gas worse")

	var/datum/reagent/hep = _drug_b_reagent(REAGENT_ID_HEPANEPHRODAXON)
	TEST_ASSERT(hep.treatment_tags[TREAT_HEPATORENAL] > 0, "hepanephrodaxon treats the liver and kidneys")
	TEST_ASSERT(hep.factors[STAT_METABOLISM_MULT] < 1, "hepanephrodaxon slows how fast toxins clear")
	var/datum/affliction/nausea = dq_proto(/datum/affliction/nausea/hepanephrodaxon)
	TEST_ASSERT(nausea.caused_by_chems[REAGENT_ID_HEPANEPHRODAXON] > 0, "hepanephrodaxon adds nausea")

	var/datum/reagent/gas = _drug_b_reagent(REAGENT_ID_GASTIRODAXON)
	TEST_ASSERT(gas.treatment_tags[TREAT_DIGESTIVE] > 0, "gastirodaxon treats the gut")
	TEST_ASSERT(gas.factors[STAT_INGEST_ABSORPTION] < 1, "gastirodaxon slows oral absorption")
	var/datum/affliction/sepsis = dq_proto(/datum/affliction/appendiceal_sepsis)
	TEST_ASSERT(sepsis.treated_by[TREAT_DIGESTIVE] > 0, "digestive repair treats appendiceal sepsis")

	var/datum/reagent/imi = _drug_b_reagent(REAGENT_ID_IMIDAZOLINE)
	TEST_ASSERT(imi.treatment_tags[TREAT_OCULAR] > 0, "imidazoline treats the eyes")
	TEST_ASSERT(imi.factors[STAT_FLASH_VULNERABILITY] > 1, "imidazoline makes flashes blind for longer")

/datum/unit_test/dq_drug_set_b_brain_and_circulation

/datum/unit_test/dq_drug_set_b_brain_and_circulation/Run()
	var/datum/reagent/alk = _drug_b_reagent(REAGENT_ID_ALKYSINE)
	TEST_ASSERT(alk.treatment_tags[TREAT_NEURAL_REPAIR] > 0, "alkysine treats the brain")
	TEST_ASSERT(alk.factors[STAT_SEIZURE_PRONENESS] > 0, "alkysine lowers the seizure threshold")

	var/datum/reagent/syn = _drug_b_reagent(REAGENT_ID_SYNAPTIZINE)
	TEST_ASSERT(syn.factors[STAT_INCOMING_PAIN] > 1, "synaptizine raises pain sensitivity")
	TEST_ASSERT(syn.strains[O_HEART] > 0, "synaptizine strains the heart")

	var/datum/reagent/dex = _drug_b_reagent(REAGENT_ID_DEXALINP)
	TEST_ASSERT(dex.treatment_tags[TREAT_OXYGENATION] >= 1, "dexalin plus is a strong oxygenator")
	TEST_ASSERT(HIDE_LUNG_HEART in dex.hides, "dexalin plus hides lung and heart damage")
	TEST_ASSERT_NULL(text2path("/datum/affliction/chem_side_effect/dexalinp_dysphoria"), "dexalin plus has no mood side effect")

	var/datum/reagent/epi = _drug_b_reagent(REAGENT_ID_EPINEPHRINE)
	TEST_ASSERT(epi.treatment_tags[TREAT_VASOPRESSOR] > 0, "epinephrine is a vasopressor")
	TEST_ASSERT(epi.factors[STAT_BLEEDING] > 1, "epinephrine makes wounds bleed faster")
	TEST_ASSERT(epi.factors[STAT_ALLERGY] < 0, "epinephrine blunts an allergic reaction")
	TEST_ASSERT(epi.strains[O_HEART] > 0, "epinephrine strains the heart")

	var/datum/reagent/nor = _drug_b_reagent(REAGENT_ID_NOREPINEPHRINE)
	TEST_ASSERT(nor.factors[STAT_BP_SYSTOLIC] > 0, "norepinephrine raises the blood pressure")
	var/datum/affliction/numbness = dq_proto(/datum/affliction/chem_side_effect/norepinephrine_numbness)
	TEST_ASSERT(numbness.caused_by_chems[REAGENT_ID_NOREPINEPHRINE] > 0, "norepinephrine numbs the extremities")

	var/datum/reagent/lep = _drug_b_reagent(REAGENT_ID_LEPORAZINE)
	TEST_ASSERT(lep.treatment_tags[TREAT_THERMOREGULATION] > 0, "leporazine regulates temperature")

/datum/unit_test/dq_drug_set_b_antimicrobials

/datum/unit_test/dq_drug_set_b_antimicrobials/Run()
	var/datum/reagent/coro = _drug_b_reagent(REAGENT_ID_COROPHIZINE)
	TEST_ASSERT(HIDE_FEVER in coro.hides, "corophizine hides a fever")
	TEST_ASSERT(coro.strains[O_KIDNEYS] > 0, "corophizine strains the kidneys")
	TEST_ASSERT(coro.factors[STAT_BLEEDING] > 1, "corophizine interferes with clotting")

	var/datum/reagent/space = _drug_b_reagent(REAGENT_ID_SPACEACILLIN)
	TEST_ASSERT(space.treatment_tags[TREAT_ANTIMICROBIAL] < coro.treatment_tags[TREAT_ANTIMICROBIAL], "spaceacillin is the weaker antimicrobial")


// --- Recipes need graded ingredients -----------------------------------------------------------------------------------------------

/datum/unit_test/dq_drug_set_b_recipes_need_pharma
	boot_needs = list()

/datum/unit_test/dq_drug_set_b_recipes_need_pharma/Run()
	var/list/expected = list(
		/transformation/chem/instant/cordradaxon = REAGENT_ID_BICARIDINE,
		/transformation/chem/instant/respirodaxon = REAGENT_ID_DEXALINP,
		/transformation/chem/instant/hepanephrodaxon = REAGENT_ID_CARTHATOLINE,
		/transformation/chem/instant/gastirodaxon = REAGENT_ID_CARTHATOLINE,
		/transformation/chem/instant/dexalinp = REAGENT_ID_DEXALIN,
		/transformation/chem/instant/corophizine = REAGENT_ID_SPACEACILLIN,
	)
	for(var/rule_type in expected)
		var/datum/xform/X = xform_of(rule_type)
		TEST_ASSERT_NOTNULL(X, "[rule_type] compiled")
		TEST_ASSERT_EQUAL(X.needs_grade?[expected[rule_type]], GRADE_PHARMA, "[rule_type] needs Pharma grade [expected[rule_type]]")


// --- Interactions ----------------------------------------------------------------------------------------------------------------

/// Epinephrine together with synaptizine raises the adrenergic overload; either alone does not.
/datum/unit_test/dq_drug_set_b_epinephrine_synaptizine

/datum/unit_test/dq_drug_set_b_epinephrine_synaptizine/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_EPINEPHRINE, 5)
	H.dq_check_chem_conditions()
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/chem_interaction/epinephrine_synaptizine_tachycardia), "epinephrine alone raises no interaction")
	H.bloodstr.add_reagent(REAGENT_ID_SYNAPTIZINE, 5)
	H.dq_check_chem_conditions()
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/chem_interaction/epinephrine_synaptizine_tachycardia), "epinephrine with synaptizine raises the interaction")
	H.bloodstr.remove_reagent(REAGENT_ID_SYNAPTIZINE, 5)
	H.dq_check_chem_conditions()
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/chem_interaction/epinephrine_synaptizine_tachycardia), "the interaction clears with the synaptizine")

/// Dexalin plus with dylovene is the cyanide antidote: the interaction is raised only with both in the blood.
/datum/unit_test/dq_drug_set_b_cyanide_antidote

/datum/unit_test/dq_drug_set_b_cyanide_antidote/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_DEXALINP, 5)
	H.dq_check_chem_conditions()
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/chem_interaction/dexalinp_dylovene_cyanide), "dexalin plus alone is no antidote")
	H.bloodstr.add_reagent(REAGENT_ID_ANTITOXIN, 5)
	H.dq_check_chem_conditions()
	var/datum/affliction/antidote = H.body.find_affliction(/datum/affliction/chem_interaction/dexalinp_dylovene_cyanide)
	TEST_ASSERT_NOTNULL(antidote, "dexalin plus with dylovene raises the antidote interaction")
	TEST_ASSERT(antidote.od_cures_externally[/datum/affliction/poisoning/cyanide] > 0, "the antidote drains cyanide poisoning")


// --- Cordradaxon hides an irregular rhythm from the monitor -------------------------------------------------------------------------

/datum/unit_test/dq_drug_set_b_cordradaxon_hides_rhythm

/datum/unit_test/dq_drug_set_b_cordradaxon_hides_rhythm/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H.induce_arrhythmia(CARDIAC_RHYTHM_TACHY), "setup: the heart takes an arrhythmia")
	var/datum/diagnosis/plain = H.diagnose(/datum/diagnostic_profile/vitals_monitor)
	TEST_ASSERT(plain.heart_rhythm != RHYTHM_SINUS, "without the drug the monitor shows the irregular rhythm")
	qdel(plain)
	H.bloodstr.add_reagent(REAGENT_ID_CORDRADAXON, 5)
	var/datum/diagnosis/masked = H.diagnose(/datum/diagnostic_profile/vitals_monitor)
	TEST_ASSERT_EQUAL(masked.heart_rhythm, RHYTHM_SINUS, "with cordradaxon in the blood the monitor reads a regular rhythm")
	qdel(masked)
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/cardiac_arrhythmia), "the arrhythmia is still there: only the report changed")

#endif
