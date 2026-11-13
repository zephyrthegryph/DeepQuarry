// Unit tests for drug set C: the painkillers (paracetamol, tramadol, oxycodone), the anaesthetic (the existing sleeping gas, no Sevoflurane) and
// the companions (calcium carbonate, adranol, ethylredoxrazine, iron saline, tercozolam, anticonvulsant). Content: code/content/reagents/reagents/content/medicine/,
// code/content/medical/conditions/pharmacology/{analgesics,neurostimulants,interactions}.dm.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A human with `reagent_id` in the blood, and the reagent instance (its per-type tables are the drug declaration).
/datum/unit_test/proc/_set_c_dose(mob/living/carbon/human/H, reagent_id, amount = 5)
	H.bloodstr.add_reagent(reagent_id, amount)
	var/datum/reagent/R = H.bloodstr.get_reagent(reagent_id)
	TEST_ASSERT_NOTNULL(R, "setup: [reagent_id] is in the blood")
	return R

/// The prototype of condition `type`, asserting that `reagent_id` is one of the chems that cause it.
/datum/unit_test/proc/_set_c_caused_by(type, reagent_id)
	var/datum/affliction/proto = dq_proto(type)
	TEST_ASSERT_NOTNULL(proto, "[type] has a prototype")
	TEST_ASSERT(!isnull(proto.caused_by_chems?[reagent_id]), "[type] is caused by [reagent_id]")
	return proto


// --- Pain and anaesthesia -------------------------------------------------------------------------------------

/datum/unit_test/dq_drug_c_painkillers_declared

/datum/unit_test/dq_drug_c_painkillers_declared/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/reagent/para = _set_c_dose(H, REAGENT_ID_PARACETAMOL)
	var/datum/reagent/tram = _set_c_dose(H, REAGENT_ID_TRAMADOL)
	var/datum/reagent/oxy = _set_c_dose(H, REAGENT_ID_OXYCODONE)

	TEST_ASSERT(para.treatment_tags[TREAT_ANALGESIC] > 0, "paracetamol is an analgesic")
	TEST_ASSERT(tram.treatment_tags[TREAT_ANALGESIC] > para.treatment_tags[TREAT_ANALGESIC], "tramadol is the stronger analgesic")
	TEST_ASSERT(oxy.treatment_tags[TREAT_ANALGESIC] > tram.treatment_tags[TREAT_ANALGESIC], "oxycodone is stronger still")
	TEST_ASSERT(oxy.factors[STAT_ANALGESIA] > tram.factors[STAT_ANALGESIA] && tram.factors[STAT_ANALGESIA] > para.factors[STAT_ANALGESIA], "the analgesia stat climbs paracetamol, tramadol, oxycodone")

	TEST_ASSERT(tram.factors[STAT_SEIZURE_PRONENESS] > 0, "tramadol lowers the seizure threshold")
	TEST_ASSERT(oxy.factors[STAT_RESP_RATE] < 0, "oxycodone slows the breathing")
	TEST_ASSERT(oxy.hides && (HIDE_PAIN in oxy.hides), "oxycodone hides pain from instruments")
	TEST_ASSERT(!para.hides && !tram.hides, "the milder painkillers hide nothing")

	TEST_ASSERT(REAGENT_ID_TRAMADOL in GLOB.reagent_addictive_slow, "tramadol is slightly addictive")
	TEST_ASSERT(!(REAGENT_ID_TRAMADOL in GLOB.reagent_addictive_fast), "tramadol is not very addictive")
	TEST_ASSERT(REAGENT_ID_OXYCODONE in GLOB.reagent_addictive_fast, "oxycodone is very addictive")
	TEST_ASSERT(!(REAGENT_ID_OXYCODONE in GLOB.reagent_addictive_slow), "oxycodone is not on the slow list")

	var/datum/affliction/nausea/tram_nausea = _set_c_caused_by(/datum/affliction/nausea/tramadol, REAGENT_ID_TRAMADOL)
	TEST_ASSERT(istype(tram_nausea), "tramadol nausea is a real nausea condition")
	TEST_ASSERT_EQUAL(tram_nausea.progression_rate, 0, "it is held by the chem")
	TEST_ASSERT(tram_nausea.treated_by[TREAT_ANTIEMETIC] > 0, "calcium carbonate treats it")
	var/datum/affliction/liver_tox = _set_c_caused_by(/datum/affliction/chem_side_effect/paracetamol_hepatotoxicity, REAGENT_ID_PARACETAMOL)
	TEST_ASSERT(liver_tox.caused_by_chems[REAGENT_ID_PARACETAMOL] < para.overdose, "paracetamol hepatotoxicity starts below the overdose line")
	TEST_ASSERT(liver_tox.organ_damage_per_tick > 0 && (O_LIVER in liver_tox.organ_damage_targets), "and it damages the liver")

/// The anaesthetic is the sleeping gas; there is no Sevoflurane and no mood effect on any drug.
/datum/unit_test/dq_drug_c_no_sevoflurane_or_mood

/datum/unit_test/dq_drug_c_no_sevoflurane_or_mood/Run()
	for(var/type in subtypesof(/datum/reagent))
		var/datum/reagent/R = type
		var/rid = lowertext("[initial(R.id)]")
		TEST_ASSERT(!findtext(rid, "sevoflurane"), "[type] is a Sevoflurane reagent")
	for(var/type in subtypesof(/datum/affliction))
		var/datum/affliction/A = type
		var/aname = lowertext("[initial(A.name)]")
		TEST_ASSERT(!findtext(aname, "sevoflurane"), "[type] names Sevoflurane")
		TEST_ASSERT(!findtext(aname, "dysphoria") && !findtext(aname, "euphoria") && !findtext(aname, "mood"), "[type] is a mood effect ([aname])")

/// Instruments do not show the pain of a patient on oxycodone.
/datum/unit_test/dq_drug_c_oxycodone_hides_pain

/datum/unit_test/dq_drug_c_oxycodone_hides_pain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.fracture()
	var/datum/affliction/untreated_fracture/F = H.body.find_affliction(/datum/affliction/untreated_fracture, arm)
	TEST_ASSERT_NOTNULL(F, "setup: the arm is fractured")
	F.add_active_symptoms(/datum/affliction_symptom/sharp_pain)
	var/datum/affliction_symptom/sharp = affliction_symptom(/datum/affliction_symptom/sharp_pain)
	var/sign_name = sharp.examine_line || sharp.name

	var/datum/diagnosis/plain = H.diagnose(/datum/diagnostic_profile/body_scanner)
	TEST_ASSERT_NOTNULL(_drug_core_find_sign(plain, sign_name), "without the drug the scanner reports the pain sign")
	qdel(plain)

	_set_c_dose(H, REAGENT_ID_OXYCODONE)
	TEST_ASSERT(H.reading_hidden(HIDE_PAIN), "oxycodone in the blood masks the pain reading")
	var/datum/diagnosis/hidden = H.diagnose(/datum/diagnostic_profile/body_scanner)
	TEST_ASSERT_NULL(_drug_core_find_sign(hidden, sign_name), "the pain sign is gone from the report")
	TEST_ASSERT(hidden.has_finding_for(/datum/affliction/untreated_fracture), "the fracture itself is still reported")
	TEST_ASSERT(arm.is_fractured(), "and the bone is still broken")
	qdel(hidden)


// --- Companions ---------------------------------------------------------------------------------------------

/datum/unit_test/dq_drug_c_companions_declared

/datum/unit_test/dq_drug_c_companions_declared/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/reagent/ethyl = _set_c_dose(H, REAGENT_ID_ETHYLREDOXRAZINE)
	var/datum/reagent/anticonvulsant = _set_c_dose(H, REAGENT_ID_ANTICONVULSANT)
	var/datum/reagent/saline = _set_c_dose(H, REAGENT_ID_IRONSALINE)
	var/datum/reagent/calcium = _set_c_dose(H, REAGENT_ID_CALCIUMCARBONATE)

	TEST_ASSERT(calcium.treatment_tags[TREAT_ANTIEMETIC] > 0, "calcium carbonate stays the antiemetic")
	TEST_ASSERT(ethyl.strains?[O_LIVER] > 0, "ethylredoxrazine strains the liver")
	TEST_ASSERT(anticonvulsant.treatment_tags[TREAT_ANTICONVULSANT] >= 1, "the anticonvulsant treats seizures")
	TEST_ASSERT(anticonvulsant.factors[STAT_SEIZURE_PRONENESS] < 0, "and lowers the proneness to them")
	TEST_ASSERT(saline.treatment_tags[TREAT_BLOOD_RESTORE] > 0, "iron saline restores blood")

	// Side effects: what each drug adds.
	var/datum/affliction/jitter = _set_c_caused_by(/datum/affliction/chem_side_effect/adranol_jitter, REAGENT_ID_ADRANOL)
	TEST_ASSERT(jitter.symptom_pool[/datum/affliction_symptom/jittery], "adranol adds jitter")
	var/datum/affliction/adranol_drowsy = _set_c_caused_by(/datum/affliction/chem_side_effect/adranol_drowsy, REAGENT_ID_ADRANOL)
	TEST_ASSERT(adranol_drowsy.symptom_pool[/datum/affliction_symptom/drowsy], "adranol is mildly drowsy")
	var/datum/affliction/disorientation = _set_c_caused_by(/datum/affliction/chem_side_effect/ethylredoxrazine_disorientation, REAGENT_ID_ETHYLREDOXRAZINE)
	TEST_ASSERT(disorientation.symptom_pool[/datum/affliction_symptom/confusion], "ethylredoxrazine adds confusion")
	TEST_ASSERT(disorientation.symptom_pool[/datum/affliction_symptom/dizziness], "ethylredoxrazine adds dizziness")
	TEST_ASSERT(disorientation.symptom_pool[/datum/affliction_symptom/slurred_speech], "ethylredoxrazine adds slurring")
	var/datum/affliction/tercozolam_drowsy = _set_c_caused_by(/datum/affliction/chem_side_effect/tercozolam_drowsy, REAGENT_ID_TERCOZOLAM)
	TEST_ASSERT(tercozolam_drowsy.symptom_pool[/datum/affliction_symptom/drowsy], "tercozolam drawback is mild drowsiness")
	_set_c_caused_by(/datum/affliction/chem_side_effect/anticonvulsant_drowsy, REAGENT_ID_ANTICONVULSANT)

	// Interactions.
	var/datum/affliction/calcium_dylovene = _set_c_caused_by(/datum/affliction/chem_interaction/calcium_antitoxin_binding, REAGENT_ID_CALCIUMCARBONATE)
	TEST_ASSERT(!isnull(calcium_dylovene.caused_by_chems[REAGENT_ID_ANTITOXIN]), "the calcium interaction needs Dylovene too")
	TEST_ASSERT(calcium_dylovene.interferes_with[REAGENT_ID_ANTITOXIN] < 1, "calcium carbonate weakens Dylovene")
	var/datum/affliction/carth = _set_c_caused_by(/datum/affliction/chem_interaction/carthatoline_iron_binding, REAGENT_ID_IRONSALINE)
	TEST_ASSERT(!isnull(carth.caused_by_chems[REAGENT_ID_CARTHATOLINE]), "the iron interaction needs carthatoline too")
	TEST_ASSERT(carth.interferes_with[REAGENT_ID_IRONSALINE] < 1, "carthatoline weakens iron saline")
	var/datum/affliction/stacked = _set_c_caused_by(/datum/affliction/chem_interaction/adranol_anticonvulsant_sedation, REAGENT_ID_ADRANOL)
	TEST_ASSERT(!isnull(stacked.caused_by_chems[REAGENT_ID_ANTICONVULSANT]), "the sedation interaction needs the anticonvulsant too")
	TEST_ASSERT(stacked.symptom_pool[/datum/affliction_symptom/drowsy], "adranol with an anticonvulsant stacks drowsiness")

/// Both new reagents have a recipe in the transformation registry, and the painkillers need pharma-grade stock.
/datum/unit_test/dq_drug_c_new_reagents_craftable

/datum/unit_test/dq_drug_c_new_reagents_craftable/Run()
	var/list/recipes = list(
		REAGENT_ID_IRONSALINE = /transformation/chem/instant/ironsaline,
		REAGENT_ID_ANTICONVULSANT = /transformation/chem/instant/anticonvulsant,
	)
	for(var/reagent_id in recipes)
		var/datum/xform/X = xform_of(recipes[reagent_id])
		TEST_ASSERT_NOTNULL(X, "the recipe for [reagent_id] compiled")
		var/makes_it = FALSE
		for(var/list/row in X.makes)
			if(row[2] == reagent_id)
				makes_it = TRUE
		TEST_ASSERT(makes_it, "the recipe makes [reagent_id]")
		TEST_ASSERT(length(X.reagent_takes) >= 2, "[reagent_id] needs ingredients")
	var/datum/xform/tram = xform_of(/transformation/chem/instant/tramadol)
	TEST_ASSERT_EQUAL(tram.needs_grade[REAGENT_ID_PARACETAMOL], GRADE_PHARMA, "tramadol needs pharma-grade paracetamol")
	var/datum/xform/oxy = xform_of(/transformation/chem/instant/oxycodone)
	TEST_ASSERT_EQUAL(oxy.needs_grade[REAGENT_ID_TRAMADOL], GRADE_PHARMA, "oxycodone needs pharma-grade tramadol")


// --- Runtime ------------------------------------------------------------------------------------------------

/// The anticonvulsant ends a seizure faster than leaving it.
/datum/unit_test/dq_drug_c_anticonvulsant_cures_seizure

/datum/unit_test/dq_drug_c_anticonvulsant_cures_seizure/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/control = allocate(/mob/living/carbon/human)
	var/datum/affliction/seizure/S = H.body.afflict(/datum/affliction/seizure)
	var/datum/affliction/seizure/C = control.body.afflict(/datum/affliction/seizure)
	TEST_ASSERT_NOTNULL(S, "setup: the patient seizes")
	TEST_ASSERT_NOTNULL(C, "setup: the control seizes")
	_set_c_dose(H, REAGENT_ID_ANTICONVULSANT, 10)
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	TEST_ASSERT(H.body.treatment_levels()?[TREAT_ANTICONVULSANT] > 0, "the anticonvulsant provides the mechanism")
	S.tick()
	C.tick()
	TEST_ASSERT(QDELETED(S) || S.severity < C.severity, "the anticonvulsant settles the seizure faster than leaving it")

/// Ethylredoxrazine strain lands on the liver as a toxic lesion.
/datum/unit_test/dq_drug_c_ethylredoxrazine_strains_liver

/datum/unit_test/dq_drug_c_ethylredoxrazine_strains_liver/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	TEST_ASSERT_NOTNULL(liver, "setup: a liver")
	var/datum/reagent/R = _set_c_dose(H, REAGENT_ID_ETHYLREDOXRAZINE, 20)
	R.apply_strains(H, 10)
	TEST_ASSERT(liver.damage > 0, "the strain damages the liver")
	TEST_ASSERT_NOTNULL(liver.find_lesion(/datum/affliction/lesion/toxic_injury), "as a toxic lesion")

/// Iron saline adds blood to a bled patient, and carthatoline halves it.
/datum/unit_test/dq_drug_c_iron_saline_restores_blood

/datum/unit_test/dq_drug_c_iron_saline_restores_blood/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/slowed = allocate(/mob/living/carbon/human)
	H.vessel.remove_reagent(REAGENT_ID_BLOOD, 100)
	slowed.vessel.remove_reagent(REAGENT_ID_BLOOD, 100)
	var/before = H.vessel.total_volume
	var/slowed_before = slowed.vessel.total_volume
	var/datum/reagent/R = _set_c_dose(H, REAGENT_ID_IRONSALINE, 10)
	var/datum/reagent/R2 = _set_c_dose(slowed, REAGENT_ID_IRONSALINE, 10)
	R.affect_blood(H, 0, 5)
	TEST_ASSERT(H.vessel.total_volume > before, "iron saline adds blood volume, [H.vessel.total_volume] over [before]")
	var/gained = H.vessel.total_volume - before

	slowed.body.afflict(/datum/affliction/chem_interaction/carthatoline_iron_binding, slowed.organ_in(O_LIVER))
	slowed.body.invalidate(BODY_DIRTY_TREATMENT)
	R2.affect_blood(slowed, 0, 5)
	var/slowed_gain = slowed.vessel.total_volume - slowed_before
	TEST_ASSERT(slowed_gain < gained, "carthatoline weakens it, [slowed_gain] against [gained]")

#endif
