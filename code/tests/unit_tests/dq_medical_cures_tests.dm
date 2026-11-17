// Unit tests for the missing medical cures: mid-tier organ repair, the opioid antidote, ear and eye surgery, second providers, the disease cures and
// the growths. Content: code/content/reagents/reagents/content/medicine/{naloxone,cochlexine,anthelmin}.dm, code/content/surgery/special_senses.dm.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A human with `reagent_id` in the blood.
/datum/unit_test/proc/_cure_dose(mob/living/carbon/human/H, reagent_id, amount = 10)
	H.bloodstr.add_reagent(reagent_id, amount)
	var/datum/reagent/R = H.bloodstr.get_reagent(reagent_id)
	TEST_ASSERT_NOTNULL(R, "setup: [reagent_id] is in the blood")
	return R

/// Makes `H` a human whose head is open far enough to operate on, and returns the head.
/datum/unit_test/proc/_cure_head(mob/living/carbon/human/H)
	var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
	TEST_ASSERT_NOTNULL(head, "setup: a head")
	return head


// --- Mid-tier organ repair ------------------------------------------------------------------------------

/// Tricordrazine (tier 2) repairs the heart, lungs and eyes, at a lower rate than the specialist drugs.
/datum/unit_test/dq_cures_tricordrazine_repairs_organs

/datum/unit_test/dq_cures_tricordrazine_repairs_organs/Run()
	TEST_ASSERT_EQUAL(chem_tier_of(REAGENT_ID_TRICORDRAZINE), CHEM_TIER_STANDARD, "tricordrazine is a mid-tier drug")
	var/list/pairs = list(
		list(/datum/affliction/heart_damage, REAGENT_ID_CORDRADAXON),
		list(/datum/affliction/pulmonary_contusion, REAGENT_ID_RESPIRODAXON),
		list(/datum/affliction/respiratory_failure, REAGENT_ID_RESPIRODAXON),
		list(/datum/affliction/ischemic_vision_loss, REAGENT_ID_IMIDAZOLINE),
	)
	for(var/list/pair in pairs)
		var/datum/affliction/proto = dq_proto(pair[1])
		var/list/cures = proto.effective_cures()
		TEST_ASSERT(cures[REAGENT_ID_TRICORDRAZINE] > 0, "tricordrazine treats [proto.name]")
		TEST_ASSERT(cures[REAGENT_ID_TRICORDRAZINE] < cures[pair[2]], "[pair[2]] treats [proto.name] faster than tricordrazine")

// --- Opioid antidote ------------------------------------------------------------------------------------

/// Naloxone is made by the generated routes from the starting chemicals, in a few steps and without the exotic inputs.
/datum/unit_test/dq_cures_new_drugs_are_makeable_from_the_stock

/datum/unit_test/dq_cures_new_drugs_are_makeable_from_the_stock/Run()
	var/list/depth = dq_fam_depths(FALSE, FALSE)
	for(var/id in list(REAGENT_ID_NALOXONE, REAGENT_ID_COCHLEXINE, REAGENT_ID_ANTHELMIN))
		TEST_ASSERT_NOTNULL(chem_structure_of(id), "[id] has a structure")
		TEST_ASSERT_NOTNULL(chem_tier_of(id), "[id] has a tier")
		TEST_ASSERT(!isnull(depth[id]), "[id] is reachable from the starting chemicals")
		TEST_ASSERT(length(dq_fam_makers(id)), "a generated route makes [id]")
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[id]
		TEST_ASSERT_NOTNULL(R, "[id] is a reagent")
		TEST_ASSERT(length(R.description) > 40, "[id] has a description")
	TEST_ASSERT_NOTNULL(dq_fam_route(REAGENT_ID_NALOXONE, list(REAGENT_ID_OXYCODONE, REAGENT_ID_HYDROGEN)), "naloxone is a reduction of oxycodone")
	TEST_ASSERT_NOTNULL(dq_fam_route(REAGENT_ID_COCHLEXINE, list(REAGENT_ID_SYNAPTIZINE)), "cochlexine is a nitrated synaptizine")
	TEST_ASSERT_NOTNULL(dq_fam_route(REAGENT_ID_ANTHELMIN, list(REAGENT_ID_ADRANOL)), "anthelmin is a halogenated adranol")

/// Naloxone strips the opioids out of the blood and ends the opioid overdose.
/datum/unit_test/dq_cures_naloxone_reverses_opioid_overdose

/datum/unit_test/dq_cures_naloxone_reverses_opioid_overdose/Run()
	var/datum/affliction/overdose/oxycodone/proto = dq_proto(/datum/affliction/overdose/oxycodone)
	TEST_ASSERT(proto.treated_by[TREAT_OPIOID_ANTAGONIST] > 0, "the opioid overdose is treated by the antagonist mechanism")
	TEST_ASSERT(proto.effective_cures()[REAGENT_ID_NALOXONE] > 0, "the book lists naloxone for the opioid overdose")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	_cure_dose(H, REAGENT_ID_OXYCODONE, 30)
	_cure_dose(H, REAGENT_ID_TRAMADOL, 20)
	var/datum/reagent/naloxone = _cure_dose(H, REAGENT_ID_NALOXONE, 10)
	for(var/i in 1 to 10)
		naloxone.affect_blood(H, null, 0.2)
	TEST_ASSERT(H.bloodstr.get_reagent_amount(REAGENT_ID_OXYCODONE) < 1, "naloxone strips the oxycodone out of the blood")
	TEST_ASSERT(H.bloodstr.get_reagent_amount(REAGENT_ID_TRAMADOL) < 1, "and the tramadol")


// --- Ear damage ------------------------------------------------------------------------------------

/// Cochlexine heals ear damage and clears the deafness it caused; it leaves a destroyed eardrum alone.
/datum/unit_test/dq_cures_cochlexine_heals_ears

/datum/unit_test/dq_cures_cochlexine_heals_ears/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_ear_damage(30)
	H.set_sdisabilities(H.sdisabilities | DEAF)
	var/datum/reagent/R = _cure_dose(H, REAGENT_ID_COCHLEXINE, 20)
	for(var/i in 1 to 20)
		R.affect_blood(H, null, 0.2)
	TEST_ASSERT(H.ear_damage < EAR_DAMAGE_IMPAIRED, "cochlexine heals the ear damage, [H.ear_damage] left")
	TEST_ASSERT(!(H.sdisabilities & DEAF), "and clears the deafness it caused")
	var/mob/living/carbon/human/ruined = allocate(/mob/living/carbon/human)
	ruined.set_ear_damage(EAR_DAMAGE_PERMANENT)
	var/datum/reagent/R2 = _cure_dose(ruined, REAGENT_ID_COCHLEXINE, 20)
	R2.affect_blood(ruined, null, 0.2)
	TEST_ASSERT_EQUAL(ruined.ear_damage, EAR_DAMAGE_PERMANENT, "a destroyed eardrum is beyond the drug")

/// The Repair Eardrum surgery answers to ear damage past the permanent line, and leaves the ear healable.
/datum/unit_test/dq_cures_eardrum_surgery_repairs_permanent_damage

/datum/unit_test/dq_cures_eardrum_surgery_repairs_permanent_damage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/head = _cure_head(H)
	var/datum/surgical_step/repair_eardrum/step = surgical_step(/datum/surgical_step/repair_eardrum)
	TEST_ASSERT_NOTNULL(step, "the step is registered")
	TEST_ASSERT(!step.is_needed(surgeon, H, head, null), "healthy ears need no surgery")
	H.set_ear_damage(EAR_DAMAGE_PERMANENT + 20)
	TEST_ASSERT(step.is_needed(surgeon, H, head, null), "destroyed ears need it")
	TEST_ASSERT(length(step.findings(H, head, TRUE)), "it is a finding of the opened head")
	step.perform(surgeon, H, head, null, null)
	TEST_ASSERT(H.ear_damage < EAR_DAMAGE_PERMANENT, "the repaired drum is no longer destroyed, [H.ear_damage] left")
	TEST_ASSERT(H.ear_damage > 0, "and the rest of the damage is left for the drug")
	var/datum/reagent/R = _cure_dose(H, REAGENT_ID_COCHLEXINE, 20)
	R.affect_blood(H, null, 0.2)
	TEST_ASSERT(H.ear_damage < EAR_DAMAGE_AFTER_REPAIR, "cochlexine now heals it")


// --- Cataracts -------------------------------------------------------------------------------------

/// Remove Cataracts clears the blindness flag of a patient with organic eyes.
/datum/unit_test/dq_cures_cataract_surgery_restores_sight

/datum/unit_test/dq_cures_cataract_surgery_restores_sight/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/head = _cure_head(H)
	var/datum/surgical_step/remove_cataracts/step = surgical_step(/datum/surgical_step/remove_cataracts)
	TEST_ASSERT_NOTNULL(step, "the step is registered")
	TEST_ASSERT(!step.is_needed(surgeon, H, head, null), "sighted eyes need no surgery")
	H.set_sdisabilities(H.sdisabilities | BLIND)
	TEST_ASSERT(step.is_needed(surgeon, H, head, null), "cataracts need it")
	TEST_ASSERT(length(step.findings(H, head, TRUE)), "it is a finding of the opened head")
	step.perform(surgeon, H, head, null, null)
	TEST_ASSERT(!(H.sdisabilities & BLIND), "the cataracts are cleared")


// --- Second providers ------------------------------------------------------------------------------

/// Seizures, nausea and deep burns each have a second provider beside the first.
/datum/unit_test/dq_cures_second_providers

/datum/unit_test/dq_cures_second_providers/Run()
	var/list/checks = list(
		list(/datum/affliction/seizure, REAGENT_ID_ANTICONVULSANT, REAGENT_ID_ADRANOL),
		list(/datum/affliction/nausea, REAGENT_ID_CALCIUMCARBONATE, REAGENT_ID_MENTHOL),
		list(/datum/affliction/wound/burn/deep, REAGENT_ID_DERMALINE, REAGENT_ID_BULLVALENE),
	)
	for(var/list/check in checks)
		var/datum/affliction/proto = dq_proto(check[1])
		var/list/cures = proto.effective_cures()
		TEST_ASSERT(cures[check[2]] > 0, "[proto.name]: the first provider works")
		TEST_ASSERT(cures[check[3]] > 0, "[proto.name] has a second provider, [check[3]]")
		TEST_ASSERT(cures[check[3]] < cures[check[2]], "[proto.name]: the second provider is the slower")


// --- Diseases ----------------------------------------------------------------------------------------

/// No disease lists chicken soup or holy water as a treatment, and each of the diseases that did has an obtainable cure.
/datum/unit_test/dq_cures_no_soup_or_holy_water_cures

/datum/unit_test/dq_cures_no_soup_or_holy_water_cures/Run()
	var/list/banned = list(REAGENT_ID_CHICKENSOUP, REAGENT_ID_CHICKENNOODLESOUP, REAGENT_ID_HOLYWATER)
	for(var/type in subtypesof(/datum/affliction/contagion))
		var/datum/affliction/contagion/D = dq_proto(type)
		if(!D)
			continue
		for(var/id in banned)
			TEST_ASSERT(!(id in D.cures), "[type] lists [id] as a cure")
			TEST_ASSERT(!findtext(D.cure_text, id), "[type] names [id] in its cure text")
	for(var/list/pool in GLOB.advance_cures)
		for(var/id in banned)
			TEST_ASSERT(!(id in pool), "the engineered cure pool lists [id]")
	var/list/cured = list(
		/datum/affliction/contagion/cold,
		/datum/affliction/contagion/flu,
		/datum/affliction/contagion/food_poisoning,
		/datum/affliction/contagion/fleshy_spread,
		/datum/affliction/contagion/revblight,
	)
	for(var/type in cured)
		var/datum/affliction/contagion/D = dq_proto(type)
		TEST_ASSERT(length(D.cures), "[type] still has a reagent cure")
		for(var/id in D.cures)
			TEST_ASSERT_NOTNULL(SSchemistry.ready().chemical_reagents[id], "[type]: the cure [id] is a real reagent")


// --- Tumours and parasites ---------------------------------------------------------------------------

/// A tumour is cut out by the resection step, a parasite by resection or by anthelmin; the engineered glands are not growths.
/datum/unit_test/dq_cures_growths_are_treatable

/datum/unit_test/dq_cures_growths_are_treatable/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	TEST_ASSERT(H.malignant_organ_spawn(/obj/item/organ/internal/malignant/tumor/cancer), "setup: a tumour grows")
	var/obj/item/organ/internal/malignant/tumor/tumor
	for(var/obj/item/organ/internal/malignant/tumor/T in H.internal_organ_list())
		tumor = T
	TEST_ASSERT_NOTNULL(tumor, "setup: the tumour is in the body")
	var/obj/item/organ/external/part = H.get_organ(tumor.parent_organ)
	var/datum/surgical_step/treat/organ/resection/step = surgical_step(/datum/surgical_step/treat/organ/resection)
	TEST_ASSERT_NOTNULL(step, "the resection step is registered")
	TEST_ASSERT(step.location_needs_treatment(H, tumor), "resection answers to the tumour")
	TEST_ASSERT(length(step.findings(H, part, TRUE)), "it is a finding of the opened limb")
	step.perform(surgeon, H, part, null, tumor)
	TEST_ASSERT(QDELETED(tumor) || tumor.owner != H, "the tumour is gone")

/datum/unit_test/dq_cures_anthelmin_kills_parasites

/datum/unit_test/dq_cures_anthelmin_kills_parasites/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(H.malignant_organ_spawn(/obj/item/organ/internal/malignant/parasite/painleech), "setup: a parasite settles")
	var/datum/reagent/R = _cure_dose(H, REAGENT_ID_ANTHELMIN, 20)
	for(var/i in 1 to 200)
		R.affect_blood(H, null, 0.2)
	var/remaining = 0
	for(var/obj/item/organ/internal/malignant/parasite/P in H.internal_organ_list())
		remaining++
	TEST_ASSERT_EQUAL(remaining, 0, "anthelmin kills the parasite")

/// The book has an entry for each of the conditions that are not afflictions.
/datum/unit_test/dq_cures_book_lists_the_new_conditions

/datum/unit_test/dq_cures_book_lists_the_new_conditions/Run()
	var/list/ids = list()
	for(var/list/entry in _dq_book_body_state_conditions())
		ids += entry["id"]
	for(var/id in list("body_state/ear_damage", "body_state/destroyed_eardrum", "body_state/cataracts", "body_state/abnormal_tissue_mass", "body_state/parasitic_organism"))
		TEST_ASSERT(id in ids, "the book has an entry for [id]")

/// The analyzer guidance names each new drug.
/datum/unit_test/dq_cures_guidance_names_the_new_drugs

/datum/unit_test/dq_cures_guidance_names_the_new_drugs/Run()
	TEST_ASSERT(findtext(analyzer_guidance_line(TREAT_OPIOID_ANTAGONIST), "Naloxone"), "the opioid overdose guidance names naloxone")
	TEST_ASSERT(findtext(analyzer_guidance_line(TREAT_CARDIAC), "Tricordrazine"), "the heart guidance names the mid-tier drug")

// --- Electrolyte drink: the cold's fluids cure ---------------------------------------------------------

/// The electrolyte drink is made from water, salt and sugar, and is the strongest provider of the rehydration tag; iron saline provides it more slowly.
/datum/unit_test/dq_cures_electrolyte_is_the_rehydration_provider

/datum/unit_test/dq_cures_electrolyte_is_the_rehydration_provider/Run()
	var/datum/reagent/drink = SSchemistry.ready().chemical_reagents[REAGENT_ID_ELECTROLYTE]
	TEST_ASSERT_NOTNULL(drink, "the electrolyte drink is a real reagent")
	TEST_ASSERT(istype(drink, /datum/reagent/drink), "and a drink")
	var/datum/reagent/saline = SSchemistry.ready().chemical_reagents[REAGENT_ID_IRONSALINE]
	TEST_ASSERT(drink.treatment_tags[TREAT_HYDRATION] > saline.treatment_tags[TREAT_HYDRATION], "the drink rehydrates faster than iron saline")
	TEST_ASSERT(saline.treatment_tags[TREAT_HYDRATION] > 0, "iron saline still provides the tag")
	var/datum/xform/X = xform_of(/transformation/chem/instant/electrolyte)
	TEST_ASSERT_NOTNULL(X, "the recipe compiled")
	for(var/id in list(REAGENT_ID_WATER, REAGENT_ID_SODIUMCHLORIDE, REAGENT_ID_SUGAR))
		TEST_ASSERT(id in X.reagent_takes, "the recipe takes [id]")

/// The cold names the electrolyte drink, is treated by the rehydration tag, and no longer lists iron saline as a reagent cure.
/datum/unit_test/dq_cures_cold_fluids_are_electrolyte

/datum/unit_test/dq_cures_cold_fluids_are_electrolyte/Run()
	var/datum/affliction/contagion/cold/proto = dq_proto(/datum/affliction/contagion/cold)
	TEST_ASSERT(proto.treated_by[TREAT_HYDRATION] > 0, "the cold is treated by rehydration")
	TEST_ASSERT(!(REAGENT_ID_IRONSALINE in proto.cures), "iron saline is no longer a listed cold cure")
	TEST_ASSERT(findtext(proto.cure_text, REAGENT_ELECTROLYTE), "the cure text names the electrolyte drink")
	TEST_ASSERT(!findtext(proto.cure_text, REAGENT_IRONSALINE), "and not iron saline")
	var/list/cures = proto.effective_cures()
	TEST_ASSERT(cures[REAGENT_ID_ELECTROLYTE] > cures[REAGENT_ID_IRONSALINE], "the drink is the faster provider")
	TEST_ASSERT(cures[REAGENT_ID_IRONSALINE] > 0, "iron saline still helps, by the tag")
	TEST_ASSERT(findtext(analyzer_guidance_line(TREAT_HYDRATION), "Electrolyte"), "the analyzer guidance names the drink")

/// A host who has the drink in the blood builds immunity to a cold faster than one who has not.
/datum/unit_test/dq_cures_electrolyte_speeds_cold_recovery

/datum/unit_test/dq_cures_electrolyte_speeds_cold_recovery/Run()
	var/mob/living/carbon/human/treated = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/control = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/cold/template = new
	treated.force_contagion(template)
	control.force_contagion(template)
	qdel(template)
	var/datum/affliction/contagion/cold/a = contagion_of(treated, /datum/affliction/contagion/cold)
	var/datum/affliction/contagion/cold/b = contagion_of(control, /datum/affliction/contagion/cold)
	TEST_ASSERT_NOTNULL(a, "setup: the treated host has a cold")
	TEST_ASSERT_NOTNULL(b, "setup: the control has a cold")
	treated.bloodstr.add_reagent(REAGENT_ID_ELECTROLYTE, 10)
	treated.body.invalidate(BODY_DIRTY_TREATMENT)
	TEST_ASSERT(treated.body.treatment_levels()?[TREAT_HYDRATION] > 0, "the drink provides rehydration")
	for(var/datum/affliction/contagion/cold/D in list(a, b))
		D.stage_prob = 0
		D.cure_chance = 0
	var/before_a = a.immunity
	var/before_b = b.immunity
	a.tick()
	b.tick()
	TEST_ASSERT((a.immunity - before_a) > (b.immunity - before_b), "the cold clears faster with the drink: [a.immunity - before_a] against [b.immunity - before_b]")

/// Halogenating frees real hydrochloric acid and the separate trace contaminant is gone.
/datum/unit_test/dq_chem_hcl_trace_is_merged

/datum/unit_test/dq_chem_hcl_trace_is_merged/Run()
	TEST_ASSERT_NULL(SSchemistry.ready().chemical_reagents["contaminant_hydrochloric"], "the hydrogen chloride trace is no longer a reagent")
	TEST_ASSERT_NOTNULL(SSchemistry.ready().chemical_reagents[REAGENT_ID_HYDROCHLORIC], "hydrochloric acid is a real reagent")
	TEST_ASSERT_EQUAL(melt_trace_of(REAGENT_ID_HYDROCHLORIC)?[1], "hydrogen", "real hydrochloric acid takes up in a melt as the trace the contaminant used to")

#endif
