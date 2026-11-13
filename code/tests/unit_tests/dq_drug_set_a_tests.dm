// Unit tests for drug set A: the generics (tricordrazine, peridaxon, inaprovaline, panacillin, rezadone), the trauma drugs (bicaridine, myelamine,
// osteodaxon, kelotane, dermaline) and the toxin and radiation drugs (dylovene, carthatoline, arithrazine, hyronalin). Content:
// code/content/reagents/reagents/content/medicine/, code/content/medical/conditions/pharmacology/.
//
// The data audits read the declaration (the reagent prototype, the affliction prototype, the compiled recipe); the runtime tests put the real
// reagent in the blood.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The prototype of a reagent id.
/datum/unit_test/proc/_set_a_reagent(reagent_id)
	var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reagent_id]
	TEST_ASSERT_NOTNULL(R, "[reagent_id] is a registered reagent")
	return R

/// Does the reagent prototype provide the treatment tag?
/datum/unit_test/proc/_set_a_tags(datum/reagent/R, list/tags)
	for(var/tag in tags)
		TEST_ASSERT(R.treatment_tags?[tag] > 0, "[R.id] provides [tag]")

// --- The generics ---------------------------------------------------------------------------------------------------

/datum/unit_test/dq_set_a_generics_profile

/datum/unit_test/dq_set_a_generics_profile/Run()
	var/datum/reagent/R = _set_a_reagent(REAGENT_ID_TRICORDRAZINE)
	_set_a_tags(R, list(TREAT_TISSUE_REPAIR, TREAT_BURN_CARE, TREAT_ANTITOXIN, TREAT_OXYGENATION))
	TEST_ASSERT(R.strains?[O_LIVER] > 0, "tricordrazine strains the liver")
	TEST_ASSERT(REAGENT_ID_TRICORDRAZINE in GLOB.reagent_addictive_slow, "tricordrazine stays mildly addictive")
	var/datum/xform/X = xform_of(/transformation/chem/instant/tricordrazine)
	TEST_ASSERT_NOTNULL(X, "the tricordrazine recipe compiled")
	TEST_ASSERT_EQUAL(X.needs_grade?[REAGENT_ID_ANTITOXIN], GRADE_PHARMA, "tricordrazine needs a pharma-grade antitoxin")
	TEST_ASSERT_EQUAL(X.needs_grade?[REAGENT_ID_INAPROVALINE], GRADE_PHARMA, "tricordrazine needs a pharma-grade inaprovaline")

	R = _set_a_reagent(REAGENT_ID_PERIDAXON)
	_set_a_tags(R, list(TREAT_OCULAR, TREAT_RESPIRATORY, TREAT_HEPATORENAL, TREAT_CARDIAC, TREAT_DIGESTIVE, TREAT_NEURAL_REPAIR))
	TEST_ASSERT(HIDE_ORGAN_MILD in R.hides, "peridaxon hides mild organ damage")
	TEST_ASSERT_NOTNULL(dq_proto(/datum/affliction/chem_side_effect/peridaxon_confusion), "peridaxon adds confusion")

	R = _set_a_reagent(REAGENT_ID_INAPROVALINE)
	TEST_ASSERT(HIDE_PAIN_LOCATION in R.hides, "inaprovaline hides where it hurts")
	TEST_ASSERT(HIDE_SYMPTOM_SUPPRESSION in R.hides, "inaprovaline hides the withdrawal it suppresses")
	TEST_ASSERT(R.factors?[STAT_WITHDRAWAL] < 0, "inaprovaline suppresses withdrawal")
	TEST_ASSERT(R.factors?[STAT_STABILIZATION] > 0, "inaprovaline slows dying")
	TEST_ASSERT(R.factors?[STAT_ANALGESIA] > 0, "inaprovaline dampens pain")

/datum/unit_test/dq_set_a_panacillin_craftable_and_interacts

/datum/unit_test/dq_set_a_panacillin_craftable_and_interacts/Run()
	var/datum/reagent/R = _set_a_reagent(REAGENT_ID_PANACILLIN)
	_set_a_tags(R, list(TREAT_ANTIMICROBIAL, TREAT_ANTITOXIN))
	TEST_ASSERT(R.strains?[O_KIDNEYS] > 0, "panacillin strains the kidneys")
	var/datum/xform/X = xform_of(/transformation/chem/instant/panacillin)
	TEST_ASSERT_NOTNULL(X, "the panacillin recipe compiled")
	TEST_ASSERT_EQUAL(X.needs_grade?[REAGENT_ID_SPACEACILLIN], GRADE_PHARMA, "panacillin needs a pharma-grade spaceacillin")
	var/datum/affliction/chem_interaction/clash = dq_proto(/datum/affliction/chem_interaction/panacillin_corophizine)
	TEST_ASSERT(clash.interferes_with?[REAGENT_ID_COROPHIZINE] < 1, "panacillin weakens corophizine")
	var/datum/affliction/nausea/panacillin/nausea = dq_proto(/datum/affliction/nausea/panacillin)
	TEST_ASSERT(nausea.chem_scaling, "the panacillin nausea builds with the course and lingers")
	TEST_ASSERT_EQUAL(nausea.progression_rate, 0, "the chem holds the panacillin nausea")
	TEST_ASSERT(length(TYPE_TABLE_GET(nausea, affliction_stages)), "the lingering nausea has its stage table")

/datum/unit_test/dq_set_a_rezadone_profile

/datum/unit_test/dq_set_a_rezadone_profile/Run()
	var/datum/reagent/R = _set_a_reagent(REAGENT_ID_REZADONE)
	_set_a_tags(R, list(TREAT_GENETIC_REPAIR, TREAT_TISSUE_REPAIR, TREAT_BURN_CARE, TREAT_ANTITOXIN))
	TEST_ASSERT_EQUAL(R.strains?[O_LIVER], DRUG_STRAIN_HEAVY, "rezadone strains the liver heavily")
	var/datum/xform/X = xform_of(/transformation/chem/instant/rezadone)
	TEST_ASSERT_NOTNULL(X, "the rezadone recipe compiled")
	TEST_ASSERT(length(X.needs_grade), "rezadone's recipe asks for graded ingredients")
	for(var/reagent_id in X.needs_grade)
		TEST_ASSERT_EQUAL(X.needs_grade[reagent_id], GRADE_REAGENT, "rezadone needs reagent-grade [reagent_id]")
	var/datum/affliction/chem_interaction/cancel = dq_proto(/datum/affliction/chem_interaction/rezadone_arithrazine_cancel)
	TEST_ASSERT_EQUAL(cancel.interferes_with?[REAGENT_ID_ARITHRAZINE], 0, "rezadone cancels arithrazine")

// --- Trauma -----------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_set_a_trauma_profile

/datum/unit_test/dq_set_a_trauma_profile/Run()
	var/datum/reagent/R = _set_a_reagent(REAGENT_ID_BICARIDINE)
	_set_a_tags(R, list(TREAT_TISSUE_REPAIR))
	TEST_ASSERT(R.factors?[STAT_METABOLISM_MULT] > 1, "bicaridine raises the metabolism")

	R = _set_a_reagent(REAGENT_ID_MYELAMINE)
	_set_a_tags(R, list(TREAT_HEMOSTATIC))
	TEST_ASSERT(HIDE_INTERNAL_BLEEDING in R.hides, "myelamine hides internal bleeding")
	TEST_ASSERT(R.strains?[O_HEART] > 0, "myelamine strains the heart")
	var/datum/affliction/chem_interaction/conflict = dq_proto(/datum/affliction/chem_interaction/myelamine_cordradaxon_conflict)
	TEST_ASSERT(conflict.interferes_with?[REAGENT_ID_MYELAMINE] < 1, "cordradaxon weakens myelamine")
	TEST_ASSERT(conflict.interferes_with?[REAGENT_ID_CORDRADAXON] < 1, "myelamine weakens cordradaxon")

	R = _set_a_reagent(REAGENT_ID_OSTEODAXON)
	_set_a_tags(R, list(TREAT_BONE_REPAIR))
	TEST_ASSERT_NOTNULL(dq_proto(/datum/affliction/chem_side_effect/osteodaxon_ache), "osteodaxon adds bone ache")

	R = _set_a_reagent(REAGENT_ID_KELOTANE)
	_set_a_tags(R, list(TREAT_BURN_CARE))
	TEST_ASSERT(!R.treatment_tags?[TREAT_BURN_DEEP], "kelotane has no deep burn care")
	TEST_ASSERT(R.slows_other?[TREAT_BURN_CARE] < 1, "kelotane slows the healing of other wounds where it treats burns")

	R = _set_a_reagent(REAGENT_ID_DERMALINE)
	_set_a_tags(R, list(TREAT_BURN_DEEP, TREAT_ANTIEDEMA))
	TEST_ASSERT(R.strains?[O_KIDNEYS] > 0, "dermaline strains the kidneys")

/// The burn degrees: kelotane's burn care reaches degrees 1 to 3, deep burn care (dermaline) degrees 4 and 5.
/datum/unit_test/dq_set_a_burn_degrees

/datum/unit_test/dq_set_a_burn_degrees/Run()
	for(var/type in list(/datum/affliction/wound/burn/moderate, /datum/affliction/wound/burn/large, /datum/affliction/wound/burn/severe))
		var/datum/affliction/wound/burn/shallow = dq_proto(type)
		TEST_ASSERT(shallow.treated_by[TREAT_BURN_CARE] > 0, "[type] answers to burn care")
		TEST_ASSERT(!shallow.treated_by[TREAT_BURN_DEEP], "[type] does not need deep burn care")
	for(var/type in list(/datum/affliction/wound/burn/deep, /datum/affliction/wound/burn/carbonised))
		var/datum/affliction/wound/burn/deep = dq_proto(type)
		TEST_ASSERT(deep.treated_by[TREAT_BURN_DEEP] > deep.treated_by[TREAT_BURN_CARE], "[type] is mainly treated by deep burn care")

/// Bicaridine in the blood speeds the metabolism.
/datum/unit_test/dq_set_a_bicaridine_raises_metabolism

/datum/unit_test/dq_set_a_bicaridine_raises_metabolism/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/before = H.metabolism_mult
	H.bloodstr.add_reagent(REAGENT_ID_BICARIDINE, DQ_CHEM_STANDARD_DOSE)
	TEST_ASSERT(H.metabolism_mult > before, "bicaridine raises the metabolism, [before] -> [H.metabolism_mult]")
	var/nutrition = nutrition_of(H)
	var/datum/reagent/R = H.bloodstr.get_reagent(REAGENT_ID_BICARIDINE)
	R.affect_blood(H, null, 1)
	TEST_ASSERT(nutrition_of(H) < nutrition, "bicaridine burns nutrition as it is metabolised")
	H.bloodstr.clear_reagents()
	TEST_ASSERT_EQUAL(H.metabolism_mult, before, "the metabolism returns to normal once it clears")

/// Myelamine in the blood hides internal bleeding from the scanner; an admin scan reads through it.
/datum/unit_test/dq_set_a_myelamine_hides_internal_bleeding

/datum/unit_test/dq_set_a_myelamine_hides_internal_bleeding/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/bleed = H.body.afflict(/datum/affliction/internal_hemorrhage, H.get_organ(BP_TORSO), 30)
	TEST_ASSERT_NOTNULL(bleed, "setup: an internal hemorrhage")
	var/datum/diagnosis/plain = H.diagnose(/datum/diagnostic_profile/body_scanner)
	TEST_ASSERT(plain.has_finding_for(/datum/affliction/internal_hemorrhage), "without the drug the scanner reports the hemorrhage")
	qdel(plain)
	H.bloodstr.add_reagent(REAGENT_ID_MYELAMINE, 5)
	TEST_ASSERT(H.reading_hidden(HIDE_INTERNAL_BLEEDING), "myelamine in the blood masks internal bleeding")
	var/datum/diagnosis/masked = H.diagnose(/datum/diagnostic_profile/body_scanner)
	TEST_ASSERT(!masked.has_finding_for(/datum/affliction/internal_hemorrhage), "the masked scan no longer reports it")
	var/datum/diagnosis/admin = H.diagnose(/datum/diagnostic_profile/admin)
	TEST_ASSERT(admin.has_finding_for(/datum/affliction/internal_hemorrhage), "an admin scan reads through the mask")
	TEST_ASSERT(bleed in H.body.afflictions, "the hemorrhage is still on the body")
	qdel(masked)
	qdel(admin)

// --- Toxins and radiation ----------------------------------------------------------------------------------------------

/datum/unit_test/dq_set_a_toxin_radiation_profile

/datum/unit_test/dq_set_a_toxin_radiation_profile/Run()
	var/datum/reagent/R = _set_a_reagent(REAGENT_ID_ANTITOXIN)
	_set_a_tags(R, list(TREAT_ANTITOXIN))
	TEST_ASSERT(R.factors?[STAT_INGEST_ABSORPTION] < 1, "dylovene weakens the oral drugs taken with it")
	TEST_ASSERT_NOTNULL(dq_proto(/datum/affliction/nausea/antitoxin), "dylovene adds nausea")

	R = _set_a_reagent(REAGENT_ID_CARTHATOLINE)
	_set_a_tags(R, list(TREAT_ANTITOXIN, TREAT_HEPATORENAL))
	TEST_ASSERT(R.factors?[STAT_BLOOD_REGEN] < 0, "carthatoline slows blood regeneration")

	R = _set_a_reagent(REAGENT_ID_ARITHRAZINE)
	_set_a_tags(R, list(TREAT_ANTIRADIATION))
	TEST_ASSERT(R.factors?[STAT_HEALING_RECEIVED] < 1, "arithrazine slows wound healing")
	TEST_ASSERT(R.strains?[O_STOMACH] > 0, "arithrazine strains the stomach")

	var/datum/reagent/hyronalin = _set_a_reagent(REAGENT_ID_HYRONALIN)
	_set_a_tags(hyronalin, list(TREAT_ANTIRADIATION))
	TEST_ASSERT(hyronalin.treatment_tags[TREAT_ANTIRADIATION] < R.treatment_tags[TREAT_ANTIRADIATION], "hyronalin is the weaker radiation drug")
	TEST_ASSERT(hyronalin.metabolism < R.metabolism, "hyronalin is slow")

/// Dylovene in the blood lowers the share of swallowed drugs that is absorbed.
/datum/unit_test/dq_set_a_dylovene_lowers_oral_absorption

/datum/unit_test/dq_set_a_dylovene_lowers_oral_absorption/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.ingest_absorption, 1, "a bare patient absorbs oral drugs in full")
	H.bloodstr.add_reagent(REAGENT_ID_ANTITOXIN, DQ_CHEM_STANDARD_DOSE)
	TEST_ASSERT(H.ingest_absorption < 1, "dylovene in the blood lowers oral absorption, got [H.ingest_absorption]")
	H.bloodstr.clear_reagents()
	TEST_ASSERT_EQUAL(H.ingest_absorption, 1, "absorption returns to normal once it clears")

/// Carthatoline empties the stomach of everything but itself.
/datum/unit_test/dq_set_a_carthatoline_purges_stomach

/datum/unit_test/dq_set_a_carthatoline_purges_stomach/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.ingested.add_reagent(REAGENT_ID_TRAMADOL, 10)
	H.ingested.add_reagent(REAGENT_ID_CARTHATOLINE, 5)
	H.bloodstr.add_reagent(REAGENT_ID_CARTHATOLINE, 5)
	var/datum/reagent/R = H.bloodstr.get_reagent(REAGENT_ID_CARTHATOLINE)
	R.affect_blood(H, null, 0.2)
	TEST_ASSERT_EQUAL(H.ingested.get_reagent_amount(REAGENT_ID_TRAMADOL), 0, "carthatoline flushed the swallowed tramadol")
	TEST_ASSERT(H.ingested.get_reagent_amount(REAGENT_ID_CARTHATOLINE) > 0, "but not the carthatoline still on its way in")

#endif
