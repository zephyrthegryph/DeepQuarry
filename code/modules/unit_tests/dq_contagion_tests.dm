// Unit tests for contagions: diseases as afflictions
// (code/modules/medical/contagion). Infection, progression, spread and
// treatment, plus the outcomes other than "inject the cure".

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The attached flu on `H`, or null.
/datum/unit_test/proc/contagion_of(mob/living/carbon/human/H, path)
	for(var/datum/affliction/contagion/D as anything in H.get_contagions())
		if(istype(D, path))
			return D
	return null

/// Infection puts a copy of the strain into the body as a systemic affliction.
/datum/unit_test/dq_contagion_infection

/datum/unit_test/dq_contagion_infection/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/flu/template = new
	TEST_ASSERT(H.can_contract_contagion(template), "a healthy human should be able to catch the flu")
	TEST_ASSERT(H.force_contagion(template), "force_contagion() should infect")
	TEST_ASSERT(H.has_contagion(/datum/affliction/contagion/flu), "has_contagion() should find the flu")
	var/datum/affliction/contagion/flu/D = contagion_of(H, /datum/affliction/contagion/flu)
	TEST_ASSERT_NOTNULL(D, "the flu should be an affliction on the body")
	TEST_ASSERT(D != template, "the body should hold a copy, not the template")
	TEST_ASSERT_NULL(template.body, "the template should stay detached")
	TEST_ASSERT_EQUAL(D.body, H.body, "the contagion should be owned by the body")
	TEST_ASSERT_EQUAL(D.host, H, "the contagion's host should be the mob")
	TEST_ASSERT_NULL(D.location, "contagions are systemic")
	TEST_ASSERT_EQUAL(D.stage, 1, "a fresh infection starts at stage 1")
	TEST_ASSERT_EQUAL(D.severity, round(100 / D.max_stages), "severity should mirror the stage")
	TEST_ASSERT(!H.force_contagion(template), "the same strain should not infect twice")
	qdel(template)

/// Contagions are organic, humanoid afflictions: a simple mob can't catch one.
/datum/unit_test/dq_contagion_biology

/datum/unit_test/dq_contagion_biology/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/datum/affliction/contagion/flu/template = new
	TEST_ASSERT(!M.can_contract_contagion(template), "a simple mob should not catch a humanoid contagion")
	TEST_ASSERT(!M.force_contagion(template), "force_contagion() should refuse a non-viable host")
	qdel(template)

/// Untreated, a disease advances through its stages and severity follows.
/datum/unit_test/dq_contagion_progression

/datum/unit_test/dq_contagion_progression/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/flu/template = new
	H.force_contagion(template)
	qdel(template)
	var/datum/affliction/contagion/flu/D = contagion_of(H, /datum/affliction/contagion/flu)
	TEST_ASSERT_NOTNULL(D, "the flu should have taken")
	D.stage_prob = 100
	D.cure_chance = 0
	for(var/i in 1 to D.max_stages)
		D.progress()
	TEST_ASSERT_EQUAL(D.stage, D.max_stages, "a certain stage roll should advance to the last stage")
	TEST_ASSERT_EQUAL(D.severity, 100, "severity should be 100 at the last stage")
	TEST_ASSERT(global_flag_check(D.virus_modifiers, DISCOVERED), "passing the discovery threshold should mark it discovered")

/// A cure reagent in the blood drives the disease back and ends it, leaving
/// lasting immunity.
/datum/unit_test/dq_contagion_reagent_cure

/datum/unit_test/dq_contagion_reagent_cure/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/flu/template = new
	H.force_contagion(template)
	var/datum/affliction/contagion/flu/D = contagion_of(H, /datum/affliction/contagion/flu)
	TEST_ASSERT_NOTNULL(D, "the flu should have taken")
	D.stage_prob = 0
	D.cure_chance = 100
	H.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 10)
	TEST_ASSERT(D.has_cure(), "spaceacillin should count as the flu's cure")
	D.progress()
	TEST_ASSERT(QDELETED(D) || !D.body, "a certain cure roll should end the disease")
	TEST_ASSERT(!H.has_contagion(/datum/affliction/contagion/flu), "the flu should be gone")
	TEST_ASSERT(H.has_contagion_immunity(/datum/affliction/contagion/flu), "beating the flu should leave immunity")
	TEST_ASSERT(!H.can_contract_contagion(template), "an immune host should not catch it again")
	qdel(template)

/// Without any cure, the host's immune response takes control, drives the
/// disease back and clears it. Rest feeds the response.
/datum/unit_test/dq_contagion_immune_clearance

/datum/unit_test/dq_contagion_immune_clearance/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/cold/template = new
	H.force_contagion(template)
	qdel(template)
	var/datum/affliction/contagion/cold/D = contagion_of(H, /datum/affliction/contagion/cold)
	TEST_ASSERT_NOTNULL(D, "the cold should have taken")

	// Continuous regeneration feeds the immune response.
	var/before = D.immunity
	D.receive_tagged_treatment(TREAT_REGENERATION, 5, TRUE)
	D.stage_prob = 0
	D.cure_chance = 0
	D.progress()
	TEST_ASSERT(D.immunity > before, "rest should build the immune response ([before] -> [D.immunity])")

	// A controlled disease stops advancing.
	D.immunity = CONTAGION_IMMUNITY_CONTROL
	D.stage_prob = 100
	var/stage_before = D.stage
	D.progress()
	TEST_ASSERT(D.stage <= stage_before, "a controlled disease should not advance")

	// Full immunity at the first stage clears it.
	D.set_stage(1)
	D.immunity = CONTAGION_IMMUNITY_CLEAR
	D.progress()
	TEST_ASSERT(QDELETED(D) || !D.body, "full immunity should clear a curable disease")
	TEST_ASSERT(H.has_contagion_immunity(/datum/affliction/contagion/cold), "clearing it should leave immunity")

/// A pathogen the body can't fight (immunogenicity 0) never clears on its own.
/datum/unit_test/dq_contagion_no_self_clearance

/datum/unit_test/dq_contagion_no_self_clearance/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/fleshy_spread/template = new
	H.force_contagion(template)
	qdel(template)
	var/datum/affliction/contagion/fleshy_spread/D = contagion_of(H, /datum/affliction/contagion/fleshy_spread)
	TEST_ASSERT_NOTNULL(D, "the infestation should have taken")
	D.stage_prob = 0
	D.receive_tagged_treatment(TREAT_REGENERATION, 50, TRUE)
	D.progress()
	TEST_ASSERT_EQUAL(D.immunity, 0, "an immunogenicity-0 pathogen should provoke no immune response")

/// A carrier hosts the pathogen without suffering it: no progression.
/datum/unit_test/dq_contagion_carrier

/datum/unit_test/dq_contagion_carrier/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/flu/template = new
	H.force_contagion(template)
	qdel(template)
	var/datum/affliction/contagion/flu/D = contagion_of(H, /datum/affliction/contagion/flu)
	TEST_ASSERT_NOTNULL(D, "the flu should have taken")
	D.set_virus_modifiers(D.virus_modifiers | CARRIER)
	D.stage_prob = 100
	D.progress()
	TEST_ASSERT_EQUAL(D.stage, 1, "a carrier's disease should not advance")
	TEST_ASSERT(H.is_infective(), "a carrier should still be infective")

/// Appendicitis ends when the appendix does (surgery), not with a reagent.
/datum/unit_test/dq_contagion_required_organ

/datum/unit_test/dq_contagion_required_organ/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(H.appendicitis(), "a human with an appendix should develop appendicitis")
	var/datum/affliction/contagion/appendicitis/D = contagion_of(H, /datum/affliction/contagion/appendicitis)
	TEST_ASSERT_NOTNULL(D, "appendicitis should be an affliction")
	TEST_ASSERT(!D.has_cure(), "appendicitis has no reagent cure")
	var/obj/item/organ/internal/appendix/A = H.organ_in(O_APPENDIX)
	TEST_ASSERT_NOTNULL(A, "the test human should have an appendix")
	A.removed()
	qdel(A)
	D.stage_prob = 0
	D.progress()
	TEST_ASSERT(QDELETED(D) || !D.body, "removing the appendix should end appendicitis")
	TEST_ASSERT(!H.has_contagion_immunity(/datum/affliction/contagion/appendicitis), "an appendectomy leaves no immunity")

/// Airborne spread: a carrier sheds to a nearby host; the spread lane runs
/// only while the strain can shed.
/datum/unit_test/dq_contagion_airborne_spread

/datum/unit_test/dq_contagion_airborne_spread/Run()
	var/mob/living/carbon/human/source = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/target = allocate(/mob/living/carbon/human, get_step(run_loc_floor_bottom_left, NORTH))
	var/datum/affliction/contagion/flu/template = new
	source.force_contagion(template)
	qdel(template)
	var/datum/affliction/contagion/flu/D = contagion_of(source, /datum/affliction/contagion/flu)
	TEST_ASSERT_NOTNULL(D, "the flu should have taken")
	TEST_ASSERT(D.spread_lane_wanted(), "an airborne strain in a body wants its spread lane (the every() gate)")
	D.permeability_mod = 10 // past every roll
	TEST_ASSERT(D.spread() >= 1, "shedding should expose the adjacent host")
	TEST_ASSERT(target.has_contagion(/datum/affliction/contagion/flu), "the adjacent host should catch the flu")

	// A non-airborne strain has no lane.
	D.set_spread_flags(DISEASE_SPREAD_CONTACT)
	TEST_ASSERT(!D.spread_lane_wanted(), "a contact-only strain's spread lane gate is closed")

/// Protection on the contact route: impermeable clothing blocks, blood
/// routes bypass it.
/datum/unit_test/dq_contagion_protection

/datum/unit_test/dq_contagion_protection/Run()
	var/datum/affliction_trigger/contagion/trigger = contagion_trigger()
	var/obj/item/clothing/gloves/G = allocate(/obj/item/clothing/gloves)
	G.permeability_coefficient = 0
	TEST_ASSERT(!trigger.clothing_passes(G), "impermeable gloves should block contact exposure")
	G.permeability_coefficient = 2
	TEST_ASSERT(trigger.clothing_passes(G), "fully permeable clothing should let exposure through")
	TEST_ASSERT(trigger.clothing_passes(null), "no clothing is no protection")

	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/flu/template = new
	TEST_ASSERT(trigger.passes_protection(H, template, CONTAGION_ROUTE_BLOOD), "the blood route should bypass protection")
	TEST_ASSERT(trigger.expose(H, template, CONTAGION_ROUTE_BLOOD), "blood exposure should infect")
	TEST_ASSERT(H.has_contagion(/datum/affliction/contagion/flu), "the exposed host should carry the flu")
	qdel(template)

/// Diagnosis: an undiscovered disease shows only on lab instruments, a hidden
/// strain on none, and restoration cures outright.
/datum/unit_test/dq_contagion_diagnosis_and_restoration

/datum/unit_test/dq_contagion_diagnosis_and_restoration/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/flu/template = new
	H.force_contagion(template)
	qdel(template)
	var/datum/affliction/contagion/flu/D = contagion_of(H, /datum/affliction/contagion/flu)
	TEST_ASSERT_NOTNULL(D, "the flu should have taken")

	var/datum/diagnostic_profile/P = new
	P.senses = PRESENT_INTERNAL
	P.biology = BIOLOGY_ALL
	TEST_ASSERT(!D.perceived_by(P), "an undiscovered disease should not show on an internal analyzer")
	P.senses = PRESENT_INTERNAL | PRESENT_LAB
	TEST_ASSERT(D.perceived_by(P), "a lab instrument should find an undiscovered disease")
	D.visibility_flags |= HIDDEN_SCANNER
	TEST_ASSERT(!D.perceived_by(P), "a hidden strain should show on no scanner")
	D.visibility_flags &= ~HIDDEN_SCANNER
	qdel(P)

	H.mend(TREAT_RESTORATION, 100)
	TEST_ASSERT(!H.has_contagion(/datum/affliction/contagion/flu), "restoration should cure the disease")

/// Engineered strains are contagions too: their composition is the strain id.
/datum/unit_test/dq_contagion_engineered

/datum/unit_test/dq_contagion_engineered/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/contagion/engineered/cold/template = new
	TEST_ASSERT(length(template.symptoms), "the engineered cold should carry a trait")
	TEST_ASSERT(length(template.GetDiseaseID()), "an engineered strain should have an id")
	TEST_ASSERT(H.force_contagion(template), "an engineered strain should infect")
	TEST_ASSERT(H.has_contagion(template), "the host should carry the same strain")
	var/datum/affliction/contagion/engineered/D = contagion_of(H, /datum/affliction/contagion/engineered)
	TEST_ASSERT_NOTNULL(D, "the strain should be an affliction")
	TEST_ASSERT_EQUAL(D.GetDiseaseID(), template.GetDiseaseID(), "the copy should keep the strain id")
	D.cure()
	TEST_ASSERT(H.has_contagion_immunity(template.GetDiseaseID()), "curing a strain should leave immunity to that strain")
	qdel(template)

#endif
