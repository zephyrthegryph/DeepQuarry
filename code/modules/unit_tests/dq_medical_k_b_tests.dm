// MED-9 group B regression tests: biology predicates, organ construction
// predicates, nutrition writers, reagent species gates as data, overdose stage
// data, reagent factor bands and reagent effect producers
// (doc/medical_audit_findings.md rows C10, C12, D25, P2-S1, P2-S2, P2-S11,
// P2-S13, P2-K5, P2-D5).

/// A human that metabolises as a diona, for the species-gate tests.
/mob/living/carbon/human/dq_test_diona_tag

/mob/living/carbon/human/dq_test_diona_tag/reagent_tag()
	return IS_DIONA

/// C10 / P2-S1: systemic biology is read from the body (the torso), not the
/// `synthetic` chassis record, and simple mobs answer from one `biology` var.
/datum/unit_test/dq_k_b_c10_systemic_biology_from_body

/datum/unit_test/dq_k_b_c10_systemic_biology_from_body/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.biology(), BIOLOGY_ORGANIC, "an unmodified human is organic")
	TEST_ASSERT(!HAS_SYNTHETIC_BIOLOGY(H), "an unmodified human has no synthetic biology")
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(torso, "setup: the human has a torso")
	torso.robotize()
	H.synthetic = null // the chassis record is cosmetic data, not the biology
	TEST_ASSERT_EQUAL(H.biology(), BIOLOGY_SYNTHETIC, "a robotic torso makes the body synthetic")
	TEST_ASSERT(HAS_SYNTHETIC_BIOLOGY(H), "HAS_SYNTHETIC_BIOLOGY reads the body")
	TEST_ASSERT_NULL(H.robolimb_model(), "robolimb_model() is the chassis record only")

	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(!HAS_SYNTHETIC_BIOLOGY(S), "a mouse is organic")
	S.biology = BIOLOGY_SYNTHETIC
	TEST_ASSERT(HAS_SYNTHETIC_BIOLOGY(S), "a simple mob's biology var is the one source of truth")

/// P2-S1: a brain housed in an MMI is synthetic by its housing.
/datum/unit_test/dq_k_b_s1_brain_in_mmi

/datum/unit_test/dq_k_b_s1_brain_in_mmi/Run()
	var/obj/item/mmi/M = allocate(/obj/item/mmi)
	var/mob/living/carbon/brain/B = allocate(/mob/living/carbon/brain)
	TEST_ASSERT(!HAS_SYNTHETIC_BIOLOGY(B), "a loose brain is organic")
	B.forceMove(M)
	TEST_ASSERT(HAS_SYNTHETIC_BIOLOGY(B), "a brain in an MMI is synthetic")

/// P2-S2: one vocabulary for part construction.
/datum/unit_test/dq_k_b_s2_organ_predicates

/datum/unit_test/dq_k_b_s2_organ_predicates/Run()
	var/obj/item/organ/internal/heart/O = allocate(/obj/item/organ/internal/heart)
	O.set_robotic(ORGAN_FLESH)
	TEST_ASSERT(O.is_organic() && !O.is_assisted() && !O.is_robotic(), "flesh is organic")
	TEST_ASSERT_EQUAL(O.biology(), BIOLOGY_ORGANIC, "flesh has organic biology")
	O.set_robotic(ORGAN_ASSISTED)
	TEST_ASSERT(O.is_assisted() && !O.is_robotic() && !O.is_organic(), "assisted is assisted, not robotic")
	TEST_ASSERT_EQUAL(O.biology(), BIOLOGY_ORGANIC, "assisted tissue is still organic")
	O.set_robotic(ORGAN_LIFELIKE)
	TEST_ASSERT(O.is_robotic() && O.is_assisted(), "lifelike is robotic")
	TEST_ASSERT_EQUAL(O.biology(), BIOLOGY_SYNTHETIC, "lifelike has synthetic biology")
	O.set_robotic(ORGAN_NANOFORM)
	TEST_ASSERT(O.is_nanoform() && O.is_robotic(), "nanoform is robotic and nanoform")
	TEST_ASSERT_EQUAL(O.biology(), BIOLOGY_NANOFORM, "nanoform has nanoform biology")

/// D25: an organ's meat comes from its own biology, not its owner's.
/datum/unit_test/dq_k_b_d25_organ_meat_from_organ

/datum/unit_test/dq_k_b_d25_organ_meat_from_organ/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart/O = H.organ_in(O_HEART)
	TEST_ASSERT_NOTNULL(O, "setup: the human has a heart")
	O.set_robotic(ORGAN_ROBOT)
	O.meat_type = null
	O.set_initial_meat()
	TEST_ASSERT_EQUAL(O.meat_type, /obj/item/stack/material/steel, "a robotic organ in an organic body yields steel")

/// D25: replicant crew organs are data variants, not copied procs.
/datum/unit_test/dq_k_b_d25_replicant_crew_data

/datum/unit_test/dq_k_b_d25_replicant_crew_data/Run()
	var/obj/item/organ/internal/heart/replicant/rage/base = allocate(/obj/item/organ/internal/heart/replicant/rage)
	var/obj/item/organ/internal/heart/replicant/rage/crew/C = allocate(/obj/item/organ/internal/heart/replicant/rage/crew)
	TEST_ASSERT_EQUAL(base.activation_cooldown, 60 SECONDS, "the replicant heart surges every minute")
	TEST_ASSERT_EQUAL(C.activation_cooldown, 60 MINUTES, "the crew heart surges every hour")
	TEST_ASSERT_EQUAL(C.berserk_duration, 40 SECONDS, "the crew heart surges longer")
	var/obj/item/organ/internal/lungs/replicant/mending/crew/L = allocate(/obj/item/organ/internal/lungs/replicant/mending/crew)
	TEST_ASSERT_EQUAL(L.repair_rate, 0.01, "the crew lungs mend slowly")
	var/obj/item/organ/internal/xenos/plasmavessel/replicant/crew/P = allocate(/obj/item/organ/internal/xenos/plasmavessel/replicant/crew)
	TEST_ASSERT_EQUAL(P.passive_plasma, 2, "the crew vessel makes 2 plasma a tick")

/// D25: chassis waste heat has one writer (the power cell); the machine stomach adds none.
/datum/unit_test/dq_k_b_d25_single_heat_writer

/datum/unit_test/dq_k_b_d25_single_heat_writer/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/stomach/machine/S = allocate(/obj/item/organ/internal/stomach/machine)
	S.owner = H
	H.robobody_count = 3
	var/before = H.bodytemperature
	S.handle_organ_proc_special()
	TEST_ASSERT_EQUAL(H.bodytemperature, before, "the machine stomach writes no chassis heat")
	S.owner = null

/// P2-S11: nutrition writers clamp.
/datum/unit_test/dq_k_b_s11_nutrition_writers_clamp

/datum/unit_test/dq_k_b_s11_nutrition_writers_clamp/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_nutrition(100)
	TEST_ASSERT_EQUAL(H.nutrition, 100, "set_nutrition sets")
	H.adjust_nutrition(-500)
	TEST_ASSERT_EQUAL(H.nutrition, 0, "adjust_nutrition never goes below zero")
	H.set_nutrition(H.max_nutrition + 1000)
	TEST_ASSERT_EQUAL(H.nutrition, H.max_nutrition, "set_nutrition never exceeds max_nutrition")

/// P2-S13: the species gate is data on the reagent, applied through effective_dose().
/datum/unit_test/dq_k_b_s13_species_gate_data

/datum/unit_test/dq_k_b_s13_species_gate_data/Run()
	var/datum/reagent/R = chemistry_service().chemical_reagents[REAGENT_ID_ETHYLREDOXRAZINE]
	TEST_ASSERT_NOTNULL(R, "setup: ethylredoxrazine exists")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/dq_test_diona_tag/D = allocate(/mob/living/carbon/human/dq_test_diona_tag)
	TEST_ASSERT_EQUAL(R.effective_dose(H, 5, CHEM_BLOOD), 5, "a human gets the full dose")
	TEST_ASSERT_EQUAL(R.effective_dose(D, 5, CHEM_BLOOD), 0, "a diona ignores it in the blood")
	TEST_ASSERT_EQUAL(R.effective_dose(D, 5, CHEM_INGEST), 0, "a diona ignores it when ingested")
	TEST_ASSERT(R.species_immune(D, CHEM_BLOOD), "species_immune() reads immune_species_blood")
	var/datum/reagent/C = chemistry_service().chemical_reagents[REAGENT_ID_CALCIUMCARBONATE]
	TEST_ASSERT(C.species_immune(D, CHEM_BLOOD), "calcium carbonate's blood gate is data")
	TEST_ASSERT(!C.species_immune(D, CHEM_INGEST), "calcium carbonate's ingest route is not gated")

/// P2-D5: overdose stage tables come from data through one builder.
/datum/unit_test/dq_k_b_d5_overdose_stage_data

/datum/unit_test/dq_k_b_d5_overdose_stage_data/Run()
	var/datum/affliction/overdose/bicaridine/B = new
	var/list/stages = TYPE_TABLE_GET(B, affliction_stages)
	TEST_ASSERT_NOTNULL(stages, "the bicaridine overdose has a stage table")
	TEST_ASSERT_EQUAL(length(stages), 3, "three stages")
	var/list/critical = stages["Critical"]
	TEST_ASSERT_NOTNULL(critical, "a Critical stage")
	TEST_ASSERT_EQUAL(critical["max_symptoms"], 3, "the stage numbers come from the data")
	TEST_ASSERT((/datum/affliction/internal_hemorrhage in critical["always_spawns"]), "extra stage keys survive")
	TEST_ASSERT(stages == TYPE_TABLE_GET(B, affliction_stages), "the table is built once per type")
	qdel(B)
	for(var/path in subtypesof(/datum/affliction/overdose))
		var/datum/affliction/overdose/O = path
		if(initial(O.abstract_type) == path)
			continue
		var/datum/affliction/overdose/inst = new path
		if(length(inst.overdose_stage_data))
			TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(inst, affliction_stages)), 3, "[path] builds three stages from its data")
		qdel(inst)

/// C12: reagent changes dirty the factors only on a band crossing or when a
/// factor reagent appears or leaves.
/datum/unit_test/dq_k_b_c12_factor_bands

/datum/unit_test/dq_k_b_c12_factor_bands/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.factor(BF_ANTIEMETIC) // settle
	TEST_ASSERT(!H.body.factors_stale(), "setup: factors are clean")
	H.bloodstr.add_reagent(REAGENT_ID_WATER, 5)
	TEST_ASSERT(!H.body.factors_stale(), "a reagent without factors does not dirty the factors")
	H.ingested.add_reagent(REAGENT_ID_CALCIUMCARBONATE, 5)
	TEST_ASSERT(H.body.factors_stale(), "a factor reagent appearing dirties the factors")
	TEST_ASSERT(H.factor(BF_ANTIEMETIC) > body_factor_baseline(BF_ANTIEMETIC), "the new factor applies")
	H.ingested.add_reagent(REAGENT_ID_CALCIUMCARBONATE, 0.05)
	TEST_ASSERT(!H.body.factors_stale(), "a change inside one dose band does not recompute")
	H.ingested.add_reagent(REAGENT_ID_CALCIUMCARBONATE, 5)
	TEST_ASSERT(H.body.factors_stale(), "crossing a dose band dirties the factors")
	H.factor(BF_ANTIEMETIC)
	H.ingested.remove_reagent(REAGENT_ID_CALCIUMCARBONATE, 100)
	TEST_ASSERT(H.body.factors_stale(), "a factor reagent leaving dirties the factors")
	TEST_ASSERT_EQUAL(H.factor(BF_ANTIEMETIC), body_factor_baseline(BF_ANTIEMETIC), "the factor is gone with the reagent")

/// P2-K5: reagents clean through adjust_germ_level(), which clamps at zero.
/datum/unit_test/dq_k_b_k5_germ_writer

/datum/unit_test/dq_k_b_k5_germ_writer/Run()
	var/obj/item/I = allocate(/obj/item)
	I.germ_level = 10
	var/datum/reagent/R = chemistry_service().chemical_reagents[REAGENT_ID_STERILIZINE]
	TEST_ASSERT_NOTNULL(R, "setup: sterilizine exists")
	var/old_volume = R.volume
	R.volume = 1
	R.touch_obj(I)
	R.volume = old_volume
	TEST_ASSERT_EQUAL(I.germ_level, 0, "sterilizine cleans an object to zero, never below")
	var/obj/item/organ/internal/heart/O = allocate(/obj/item/organ/internal/heart)
	O.germ_level = 0
	O.adjust_germ_level(INFECTION_LEVEL_MAX * 2)
	TEST_ASSERT_EQUAL(O.germ_level, INFECTION_LEVEL_MAX, "organs keep their infection clamp")

/// A human that metabolises as a Promethean, for the species-table tests.
/mob/living/carbon/human/dq_test_slime_tag

/mob/living/carbon/human/dq_test_slime_tag/reagent_tag()
	return IS_SLIME

/// Species reagent effects as data: species_strength, inert_species and species_injuries_*.
/datum/unit_test/dq_k_b_species_effect_tables

/datum/unit_test/dq_k_b_species_effect_tables/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/dq_test_slime_tag/S = allocate(/mob/living/carbon/human/dq_test_slime_tag)
	var/mob/living/carbon/human/dq_test_diona_tag/D = allocate(/mob/living/carbon/human/dq_test_diona_tag)
	var/datum/reagent/mind = chemistry_service().chemical_reagents[REAGENT_ID_MINDBREAKER]
	TEST_ASSERT_EQUAL(mind.species_mult(H), 1, "an unlisted species gets full strength")
	TEST_ASSERT_EQUAL(mind.species_mult(S), 0.15, "a Promethean feels mindbreaker at ~1/6")
	TEST_ASSERT(mind.inert_for(D), "diona are inert to a reagent's extras by default")
	TEST_ASSERT(!mind.inert_for(H), "humans are not inert")
	var/datum/reagent/kelo = chemistry_service().chemical_reagents[REAGENT_ID_KELOTANE]
	kelo.apply_species_injuries(H, kelo.species_injuries_blood, 5)
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_PHYSICAL), 0, "kelotane's species reaction spares humans")
	kelo.apply_species_injuries(S, kelo.species_injuries_blood, 5)
	TEST_ASSERT(S.injury_load(INJURY_CATEGORY_PHYSICAL) > 0, "kelotane bruises a Promethean's skeletal structure")
