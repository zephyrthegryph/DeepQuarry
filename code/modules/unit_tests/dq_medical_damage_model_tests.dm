// Unit tests for the body model: injure() / mend() / vitality /
// consciousness, treatment by mechanism, symptom singletons, the three
// body plans' death rules, biology gating, and afflictions travelling with
// detached organs. See doc/body_architecture.md.
//
// These tests use only the public body API (injure, mend, fully_heal,
// vitality, injury_load, body.afflict / find_affliction) and limb
// get_trauma() / get_burn() — never wound internals.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Exact-amount injury for tests: no species/modifier scaling, no pain flash.
#define DQ_TEST_INJURE (INJURE_IGNORE_RESISTANCE | INJURE_SILENT)

// --- treatment tags ------------------------------------------------------

/// A generic (many weak tags) treats several unrelated afflictions at once —
/// the point of mechanism-based treatment.
/datum/unit_test/dq_medical_generic_treats_by_tag

/datum/unit_test/dq_medical_generic_treats_by_tag/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/bleed = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/internal_hemorrhage)
	var/datum/affliction/poison = H.body.afflict(/datum/affliction/toxic_poisoning)
	TEST_ASSERT_NOTNULL(bleed, "bleed spawn failed")
	TEST_ASSERT_NOTNULL(poison, "poison spawn failed")
	bleed.set_severity(40)
	poison.set_severity(40)
	H.bloodstr.add_reagent(REAGENT_ID_TRICORDRAZINE, 20)
	_dq_tick_n(bleed, 3)
	_dq_tick_n(poison, 3)
	TEST_ASSERT(bleed.severity < 40, "tricordrazine (hemostatic tag) should lower internal_hemorrhage (40 -> [bleed.severity])")
	TEST_ASSERT(poison.severity < 40, "tricordrazine (antitoxin tag) should lower toxic_poisoning (40 -> [poison.severity])")

/// The book's effective cure table resolves tags to concrete reagents.
/datum/unit_test/dq_medical_effective_cures_resolve_tags

/datum/unit_test/dq_medical_effective_cures_resolve_tags/Run()
	var/datum/affliction/internal_hemorrhage/proto = dq_proto(/datum/affliction/internal_hemorrhage)
	var/list/cures = proto.effective_cures()
	TEST_ASSERT(cures[REAGENT_ID_BICARIDAZE] > 0, "bicaridaze should cure internal_hemorrhage via the hemostatic tag")
	TEST_ASSERT(cures[REAGENT_ID_TRICORDRAZINE] > 0, "tricordrazine should cure internal_hemorrhage via the hemostatic tag")
	TEST_ASSERT(cures[REAGENT_ID_BICARIDAZE] > cures[REAGENT_ID_TRICORDRAZINE], "the specialist should outperform the generic")
	var/list/worsens = proto.effective_worsens()
	TEST_ASSERT(worsens[REAGENT_ID_HYPERZINE] > 0, "hyperzine should worsen internal_hemorrhage via the stimulant tag")

// --- symptoms ------------------------------------------------------------------

/datum/unit_test/dq_affliction_symptoms_accumulate

/datum/unit_test/dq_affliction_symptoms_accumulate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/C = H.body.afflict(/datum/affliction/toxic_poisoning)
	TEST_ASSERT_NOTNULL(C, "toxic_poisoning could not be afflicted")
	C.roll_symptoms(1)
	TEST_ASSERT(length(C.active_symptoms) >= C.min_symptoms, "first presentation should meet min_symptoms")
	var/list/first = C.active_symptoms.Copy()
	// Worsening must never drop a symptom the doctor already saw.
	for(var/i in 1 to 5)
		C.roll_symptoms(1)
		for(var/symptom_type in first)
			TEST_ASSERT(symptom_type in C.active_symptoms, "symptom [symptom_type] vanished while the affliction worsened")
	TEST_ASSERT(length(C.active_symptoms) <= C.max_symptoms, "accumulation exceeded max_symptoms")
	// Recovery sheds symptoms down to the floor, not below.
	C.roll_symptoms(-10)
	TEST_ASSERT_EQUAL(length(C.active_symptoms), C.min_symptoms, "recovery should shed symptoms down to min_symptoms")

/// Symptoms are stateless flyweights: one instance per type, shared by every
/// affliction presenting it; afflictions hold typepaths only.
/datum/unit_test/dq_affliction_symptoms_are_singletons

/datum/unit_test/dq_affliction_symptoms_are_singletons/Run()
	var/datum/affliction_symptom/first = affliction_symptom(/datum/affliction_symptom/nausea)
	TEST_ASSERT_NOTNULL(first, "affliction_symptom() returned nothing")
	TEST_ASSERT(istype(first, /datum/affliction_symptom/nausea), "affliction_symptom() returned the wrong type")
	TEST_ASSERT_EQUAL(affliction_symptom(/datum/affliction_symptom/nausea), first, "affliction_symptom() must return the same singleton every call")

	var/mob/living/carbon/human/A = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/B = allocate(/mob/living/carbon/human)
	var/datum/affliction/poison_a = A.body.afflict(/datum/affliction/toxic_poisoning)
	var/datum/affliction/poison_b = B.body.afflict(/datum/affliction/toxic_poisoning)
	poison_a.active_symptoms = list(/datum/affliction_symptom/nausea)
	poison_b.active_symptoms = list(/datum/affliction_symptom/nausea)
	var/list/syms_a = affliction_symptoms_of(poison_a)
	var/list/syms_b = affliction_symptoms_of(poison_b)
	TEST_ASSERT_EQUAL(length(syms_a), 1, "affliction_symptoms_of() should resolve each presenting typepath")
	TEST_ASSERT_EQUAL(syms_a[1], first, "affliction A should present the shared singleton")
	TEST_ASSERT_EQUAL(syms_b[1], first, "affliction B should present the same shared singleton")

	// Rolling stores typepaths, never instances.
	poison_a.active_symptoms = null
	poison_a.roll_symptoms(1)
	for(var/symptom_type in poison_a.active_symptoms)
		TEST_ASSERT(ispath(symptom_type, /datum/affliction_symptom), "roll_symptoms() stored [symptom_type], not a typepath")

// --- injure() / mend() on a humanoid ------------------------------------------------

/// Systemic injuries become systemic afflictions whose severity IS the load.
/datum/unit_test/dq_medical_tox_pool_is_a_condition

/datum/unit_test/dq_medical_tox_pool_is_a_condition/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_TOXIC), 0, "fresh human should have no toxin load")
	TEST_ASSERT(!H.is_injured(), "fresh human should not be injured")
	var/applied = H.injure(INJURY_TOXIN, 40, flags = DQ_TEST_INJURE)
	TEST_ASSERT_EQUAL(applied, 40, "injure() should return the amount applied")
	var/datum/affliction/C = H.find_affliction(/datum/affliction/toxic_poisoning)
	TEST_ASSERT_NOTNULL(C, "INJURY_TOXIN should create a systemic toxic_poisoning affliction")
	TEST_ASSERT_NULL(C.location, "toxic_poisoning should be systemic (no location)")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_TOXIC), C.severity, "the toxic load must read the affliction's severity")
	TEST_ASSERT(H.is_injured(), "a poisoned human should read as injured")
	// Repeat injuries merge into the same affliction.
	H.injure(INJURY_TOXIN, 10, flags = DQ_TEST_INJURE)
	TEST_ASSERT_EQUAL(length(H.body.afflictions_of(/datum/affliction/toxic_poisoning)), 1, "repeat toxin injuries should merge, not stack copies")
	// Treatment by mechanism clears it.
	H.mend(TREAT_ANTITOXIN, 1000)
	TEST_ASSERT_NULL(H.find_affliction(/datum/affliction/toxic_poisoning), "mend(TREAT_ANTITOXIN) should cure toxic_poisoning")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_TOXIC), 0, "toxic load should clear on cure")

/// Located harm lands on the limb; the right mechanism mends it, the wrong
/// one does not.
/datum/unit_test/dq_medical_injure_and_mend_limb

/datum/unit_test/dq_medical_injure_and_mend_limb/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	TEST_ASSERT_NOTNULL(arm, "no right arm")
	H.injure(INJURY_BLUNT, 15, BP_R_ARM, flags = DQ_TEST_INJURE)
	H.injure(INJURY_BURN, 10, BP_R_ARM, flags = DQ_TEST_INJURE)
	TEST_ASSERT(arm.get_trauma() > 0, "blunt injury should raise the arm's trauma")
	TEST_ASSERT(arm.get_burn() > 0, "burn injury should raise the arm's burn")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_PHYSICAL), arm.get_trauma(), "physical load should be the limbs' trauma")
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_THERMAL), arm.get_burn(), "thermal load should be the limbs' burns")
	TEST_ASSERT(H.vitality() < 1, "an injured human should not read full vitality")

	var/burn_before = arm.get_burn()
	H.mend(TREAT_TISSUE_REPAIR, 100, BP_R_ARM)
	TEST_ASSERT_EQUAL(arm.get_trauma(), 0, "tissue repair should mend the arm's trauma")
	TEST_ASSERT_EQUAL(arm.get_burn(), burn_before, "tissue repair must not treat burns")
	H.mend(TREAT_BURN_CARE, 100, BP_R_ARM)
	TEST_ASSERT_EQUAL(arm.get_burn(), 0, "burn care should mend the arm's burns")

/// fully_heal() clears every affliction and restores full vitality.
/datum/unit_test/dq_medical_fully_heal_clears_everything

/datum/unit_test/dq_medical_fully_heal_clears_everything/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_BLUNT, 20, BP_L_LEG, flags = DQ_TEST_INJURE)
	H.injure(INJURY_TOXIN, 30, flags = DQ_TEST_INJURE)
	H.add_oxygen_debt(20, "unit test")
	_spawn_affliction_on(H, BP_TORSO, /datum/affliction/internal_hemorrhage)
	TEST_ASSERT(LAZYLEN(H.body.afflictions), "setup should have produced afflictions")
	H.fully_heal()
	TEST_ASSERT(!LAZYLEN(H.body.afflictions), "fully_heal() should clear every affliction")
	TEST_ASSERT_EQUAL(H.oxygen_debt(), 0, "fully_heal() should clear the oxygen debt")
	TEST_ASSERT(!H.is_injured(), "a fully healed human should not be injured")
	TEST_ASSERT_EQUAL(H.vitality(), 1, "a fully healed human should read full vitality")

/// Continuous treatment (reagent tags applied by the tick) pays down the
/// oxygen debt through tissue hypoxia.
/datum/unit_test/dq_medical_treatment_lowers_pool

/datum/unit_test/dq_medical_treatment_lowers_pool/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.add_oxygen_debt(40, "unit test")
	var/before = H.oxygen_debt()
	var/datum/affliction/C = H.find_affliction(/datum/affliction/tissue_hypoxia)
	TEST_ASSERT_NOTNULL(C, "oxygen debt should show as tissue_hypoxia")
	TEST_ASSERT_EQUAL(C.severity, before, "tissue hypoxia severity should mirror the debt")
	H.bloodstr.add_reagent(REAGENT_ID_DEXALINP, 20)
	_dq_tick_n(C, 3)
	TEST_ASSERT(H.oxygen_debt() < before, "dexalin plus (oxygenation tag) should pay down the debt ([before] -> [H.oxygen_debt()])")

// --- consciousness & death: humanoid -------------------------------------------------

/// No health-number death: toxins far past the old lethal level do not kill
/// by themselves. Death must come through organ failure.
/datum/unit_test/dq_medical_no_health_death

/datum/unit_test/dq_medical_no_health_death/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_TOXIN, 200, flags = DQ_TEST_INJURE)
	H.body.on_status_changed()
	TEST_ASSERT(H.stat != DEAD, "maxed toxic poisoning alone must not kill — death is organ death")

/// tissue_hypoxia's consciousness_at_max (200) knocks a patient out at an
/// oxygen debt of 50, not before.
/datum/unit_test/dq_medical_hypoxia_causes_crit

/datum/unit_test/dq_medical_hypoxia_causes_crit/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.body.recompute_vitals()
	TEST_ASSERT(!H.body.is_unconscious(), "a healthy human should be conscious")
	H.add_oxygen_debt(40, "unit test")
	H.body.recompute_vitals()
	TEST_ASSERT(!H.body.is_unconscious(), "hypoxia 40 should not knock the patient out (consciousness [H.body.consciousness])")
	H.add_oxygen_debt(15, "unit test")
	H.body.recompute_vitals()
	TEST_ASSERT(H.body.is_unconscious(), "hypoxia past 50 should knock the patient out (consciousness [H.body.consciousness])")
	TEST_ASSERT(H.vitality() < 1, "an unconscious patient should not read full vitality")

/// Suffocation kills through the brain: a severe oxygen debt grows ischemic
/// brain lesions each physiology tick.
/datum/unit_test/dq_medical_hypoxia_damages_brain

/datum/unit_test/dq_medical_hypoxia_damages_brain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.add_oxygen_debt(90, "unit test")
	var/datum/affliction/C = H.find_affliction(/datum/affliction/tissue_hypoxia)
	TEST_ASSERT_NOTNULL(C, "oxygen debt should show as tissue_hypoxia")
	var/before = H.injury_load(INJURY_CATEGORY_NEURAL)
	for(var/i in 1 to 5)
		H.body.physiology_tick(2)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_NEURAL) > before, "severe hypoxia should damage the brain ([before] -> [H.injury_load(INJURY_CATEGORY_NEURAL)])")

/// A vital body part kills at DQ_VITAL_PART_LETHAL_MULT × its rated integrity,
/// and not before.
/datum/unit_test/dq_medical_vital_limb_destroyed_kills

/datum/unit_test/dq_medical_vital_limb_destroyed_kills/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(chest, "no chest")
	TEST_ASSERT(chest.vital, "the chest should be a vital part")
	// Heavy hits can spill half their brute into an organ the chest holds (at
	// random below integrity, always above it), which makes the chest's own share
	// nondeterministic. This test is about the part itself, so hold no organs in it.
	var/list/held_organs = chest.internal_organs
	chest.internal_organs = null
	H.injure(INJURY_BLUNT, chest.max_damage * (DQ_VITAL_PART_LETHAL_MULT - 0.5), BP_TORSO, flags = DQ_TEST_INJURE)
	var/fraction = (chest.get_trauma() + chest.get_burn()) / chest.max_damage
	TEST_ASSERT(fraction >= DQ_VITAL_PART_LETHAL_MULT - 0.6, "the chest should hold damage past its rated integrity (got [fraction]x)")
	TEST_ASSERT(H.stat != DEAD, "a badly damaged but intact chest should not kill ([fraction]x integrity)")
	H.injure(INJURY_BLUNT, chest.max_damage, BP_TORSO, flags = DQ_TEST_INJURE)
	fraction = (chest.get_trauma() + chest.get_burn()) / chest.max_damage
	chest.internal_organs = held_organs
	TEST_ASSERT(fraction >= DQ_VITAL_PART_LETHAL_MULT, "the chest should reach its lethal multiple (got [fraction]x)")
	TEST_ASSERT_EQUAL(H.stat, DEAD, "a destroyed vital body part should kill ([fraction]x integrity)")

// --- simple body plan ------------------------------------------------------------------

/// Simple creatures carry whole-body load and die at their endurance.
/datum/unit_test/dq_medical_simple_body_dies_at_endurance

/datum/unit_test/dq_medical_simple_body_dies_at_endurance/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	TEST_ASSERT(istype(M.body, /datum/body/simple), "a mouse should have a simple body")
	var/endurance = M.get_endurance()
	TEST_ASSERT(endurance > 1, "the mouse needs endurance for this test (got [endurance])")
	TEST_ASSERT_EQUAL(M.vitality(), 1, "a fresh mouse should read full vitality")
	M.injure(INJURY_BLUNT, endurance / 2, flags = DQ_TEST_INJURE)
	TEST_ASSERT(abs(M.vitality() - 0.5) < 0.01, "half its endurance in load should read half vitality (got [M.vitality()])")
	TEST_ASSERT_EQUAL(M.injury_load(INJURY_CATEGORY_PHYSICAL), endurance / 2, "blunt injury should become trauma load")
	TEST_ASSERT(M.stat != DEAD, "a mouse below its endurance should live")
	// Simple creatures fight through pain.
	TEST_ASSERT_EQUAL(M.injure(INJURY_PAIN, 50, flags = DQ_TEST_INJURE), 0, "pain should not load a simple body")
	M.mend(TREAT_TISSUE_REPAIR, endurance / 4)
	TEST_ASSERT(M.injury_load(INJURY_CATEGORY_PHYSICAL) < endurance / 2, "tissue repair should mend trauma load")
	M.injure(INJURY_BURN, endurance, flags = DQ_TEST_INJURE)
	TEST_ASSERT_EQUAL(M.stat, DEAD, "total load at endurance should kill a simple body")

// --- machine body plan -------------------------------------------------------------------

/// Cyborgs are synthetic machine bodies: immune to biological harm, repaired
/// by plating/wiring mechanisms, destroyed at DQ_MACHINE_LETHAL_MULT × endurance.
/datum/unit_test/dq_medical_robot_machine_body

/datum/unit_test/dq_medical_robot_machine_body/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	TEST_ASSERT(istype(R.body, /datum/body/simple/machine/robot), "a cyborg should have a robot machine body")
	TEST_ASSERT(R.biology & BIOLOGY_SYNTHETIC, "a cyborg should be synthetic")
	TEST_ASSERT_EQUAL(R.injure(INJURY_TOXIN, 50, flags = DQ_TEST_INJURE), 0, "toxins should not harm a cyborg")
	TEST_ASSERT_EQUAL(R.add_oxygen_debt(50, "unit test"), 0, "a cyborg doesn't breathe: no oxygen debt")
	TEST_ASSERT_NULL(R.body.oxygen_debt(), "a cyborg has no oxygen debt to report")
	TEST_ASSERT_NULL(R.body.ventilation(), "a cyborg has no ventilation to report")

	var/endurance = R.get_endurance()
	R.injure(INJURY_BLUNT, 20, flags = DQ_TEST_INJURE)
	var/load = R.injury_load(INJURY_CATEGORY_PHYSICAL)
	TEST_ASSERT(load > 0, "blunt injury should load the chassis")
	R.mend(TREAT_TISSUE_REPAIR, 100)
	TEST_ASSERT_EQUAL(R.injury_load(INJURY_CATEGORY_PHYSICAL), load, "biological tissue repair must not repair a machine")
	R.mend(TREAT_PLATING_REPAIR, 100)
	TEST_ASSERT_EQUAL(R.injury_load(INJURY_CATEGORY_PHYSICAL), 0, "plating repair should repair a machine")

	// Machines keep working well past their endurance...
	R.injure(INJURY_BLUNT, endurance * (DQ_MACHINE_LETHAL_MULT - 0.5), flags = DQ_TEST_INJURE)
	TEST_ASSERT(R.stat != DEAD, "a cyborg below its lethal multiple should survive")
	// ...and are destroyed at the lethal multiple.
	R.injure(INJURY_BURN, endurance, flags = DQ_TEST_INJURE)
	TEST_ASSERT_EQUAL(R.stat, DEAD, "a cyborg at [DQ_MACHINE_LETHAL_MULT]x its endurance should be destroyed")

// --- biology gating ----------------------------------------------------------------------

/// Instant mending is gated by the part's biology: tissue repair doesn't fix
/// a prosthetic, plating repair doesn't fix flesh.
/datum/unit_test/dq_medical_mend_respects_biology

/datum/unit_test/dq_medical_mend_respects_biology/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/prosthetic = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/flesh = H.get_organ(BP_R_ARM)
	TEST_ASSERT_NOTNULL(prosthetic, "no left arm")
	TEST_ASSERT_NOTNULL(flesh, "no right arm")
	prosthetic.robotize()
	TEST_ASSERT_EQUAL(H.body.biology_of(prosthetic), BIOLOGY_SYNTHETIC, "a robotized arm should be synthetic")
	TEST_ASSERT_EQUAL(H.body.biology_of(flesh), BIOLOGY_ORGANIC, "a natural arm should be organic")

	H.injure(INJURY_BLUNT, 15, BP_L_ARM, flags = DQ_TEST_INJURE)
	H.injure(INJURY_BLUNT, 15, BP_R_ARM, flags = DQ_TEST_INJURE)
	var/prosthetic_before = prosthetic.get_trauma()
	var/flesh_before = flesh.get_trauma()
	TEST_ASSERT(prosthetic_before > 0, "the prosthetic should take blunt damage")
	TEST_ASSERT(flesh_before > 0, "the arm should take blunt damage")

	H.mend(TREAT_TISSUE_REPAIR, 100, BP_L_ARM)
	TEST_ASSERT_EQUAL(prosthetic.get_trauma(), prosthetic_before, "tissue repair must not treat a synthetic part")
	H.mend(TREAT_PLATING_REPAIR, 100, BP_R_ARM)
	TEST_ASSERT_EQUAL(flesh.get_trauma(), flesh_before, "plating repair must not treat an organic part")
	H.mend(TREAT_PLATING_REPAIR, 100, BP_L_ARM)
	TEST_ASSERT(prosthetic.get_trauma() < prosthetic_before, "plating repair should treat the prosthetic")
	H.mend(TREAT_TISSUE_REPAIR, 100, BP_R_ARM)
	TEST_ASSERT(flesh.get_trauma() < flesh_before, "tissue repair should treat the arm")

/// Continuous reagent treatment is gated the same way: a drug in the blood
/// treats the affliction on flesh, not the identical one on a prosthetic.
/datum/unit_test/dq_medical_reagent_tags_skip_synthetic_parts

/datum/unit_test/dq_medical_reagent_tags_skip_synthetic_parts/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/prosthetic = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/flesh = H.get_organ(BP_R_ARM)
	prosthetic.robotize()
	// Custom afflictions exist on any biology and never progress on their
	// own, so the only thing that can move them is treatment.
	var/datum/affliction/custom/on_prosthetic = H.body.afflict(/datum/affliction/custom, prosthetic, 50)
	var/datum/affliction/custom/on_flesh = H.body.afflict(/datum/affliction/custom, flesh, 50)
	TEST_ASSERT_NOTNULL(on_prosthetic, "custom affliction could not sit on the prosthetic")
	TEST_ASSERT_NOTNULL(on_flesh, "custom affliction could not sit on the arm")
	on_prosthetic.treated_by = list(TREAT_ANALGESIC = 5)
	on_flesh.treated_by = list(TREAT_ANALGESIC = 5)
	H.bloodstr.add_reagent(REAGENT_ID_PARACETAMOL, 20)
	for(var/i in 1 to 3)
		on_prosthetic.tick()
		on_flesh.tick()
	TEST_ASSERT_EQUAL(on_prosthetic.severity, 50, "a reagent treatment tag must not treat an affliction on a synthetic part (got [on_prosthetic.severity])")
	TEST_ASSERT(QDELETED(on_flesh) || on_flesh.severity < 50, "the same reagent should treat the affliction on flesh")

// --- detached organs carry their afflictions ----------------------------------------------

/// Removing an organ takes its afflictions with it (out of the body, riding
/// the organ); putting it back re-adopts them.
/datum/unit_test/dq_medical_organ_detach_reattach_carries_afflictions

/datum/unit_test/dq_medical_organ_detach_reattach_carries_afflictions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	TEST_ASSERT_NOTNULL(liver, "no liver")
	var/obj/item/organ/external/host_limb = H.get_organ(liver.parent_organ)
	TEST_ASSERT_NOTNULL(host_limb, "no limb to hold the liver")
	var/datum/affliction/custom/A = H.body.afflict(/datum/affliction/custom, liver, 60)
	TEST_ASSERT_NOTNULL(A, "custom affliction could not be afflicted")
	var/datum/affliction/systemic = H.body.afflict(/datum/affliction/toxic_poisoning, null, 30)

	liver.removed()
	TEST_ASSERT(!(A in H.body.afflictions), "a removed organ's affliction should leave the body")
	TEST_ASSERT(!H.body.find_affliction(/datum/affliction/custom), "the body's type index should drop the removed organ's affliction")
	TEST_ASSERT(A in liver.detached_afflictions, "the affliction should ride the detached organ")
	TEST_ASSERT(A in liver.afflictions_here(), "afflictions_here() should list the detached organ's afflictions")
	TEST_ASSERT_NULL(A.owner, "a detached affliction should have no owner")
	TEST_ASSERT_EQUAL(A.location, liver, "a detached affliction should stay located on its organ")
	TEST_ASSERT_EQUAL(A.severity, 60, "detaching should not change severity")
	TEST_ASSERT(systemic in H.body.afflictions, "systemic afflictions should stay with the body")

	liver.replaced(H, host_limb)
	TEST_ASSERT(A in H.body.afflictions, "reattaching the organ should bring its affliction back into the body")
	TEST_ASSERT_EQUAL(A.owner, H, "a reattached affliction should belong to the patient again")
	TEST_ASSERT_EQUAL(H.body.find_affliction(/datum/affliction/custom, liver), A, "the type index should find the reattached affliction")
	TEST_ASSERT(!LAZYLEN(liver.detached_afflictions), "the organ should no longer carry detached afflictions")

// --- GM custom afflictions ------------------------------------------------------------------

/// A configured custom affliction harms through injure(), is cured by its
/// reagent, and is excluded from the reference catalogue.
/datum/unit_test/dq_medical_custom_affliction_runtime_config

/datum/unit_test/dq_medical_custom_affliction_runtime_config/Run()
	TEST_ASSERT(!(/datum/affliction/custom in dq_catalogued_affliction_types()), "runtime-configured custom afflictions must not appear in the book")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/lungs = H.internal_organs_by_name[O_LUNGS]
	var/datum/affliction/custom/A = H.body.afflict(/datum/affliction/custom, lungs, AFFLICTION_SEVERITY_TERMINAL)
	TEST_ASSERT_NOTNULL(A, "custom affliction could not be afflicted")
	A.name = "coughing sickness"
	A.damage_kind = INJURY_TOXIN
	A.damage_strength = 2
	A.damage_max = 300
	A.cured_by = list()
	A.cured_by[REAGENT_ID_ANTITOXIN] = DQ_CUSTOM_CURE_RATE

	A.tick()
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_TOXIC) > 0, "a harmful custom affliction should injure its host")
	TEST_ASSERT_EQUAL(A.severity, AFFLICTION_SEVERITY_TERMINAL, "a custom affliction should not change without treatment")
	H.bloodstr.add_reagent(REAGENT_ID_ANTITOXIN, 40)
	for(var/i in 1 to 20)
		if(QDELETED(A))
			break
		A.tick()
	TEST_ASSERT(QDELETED(A) || !H.body.find_affliction(/datum/affliction/custom, lungs), "the cure reagent should resolve the custom affliction")

// --- body core: one pipeline, one snapshot, one heal path ------------------------------------

/// Counts signals for the body-core tests.
/datum/dq_test_signal_counter
	var/severity_changes = 0
	var/last_old_severity
	var/removals = 0

/datum/dq_test_signal_counter/proc/on_severity_changed(datum/source, datum/affliction/A, old_severity)
	SIGNAL_HANDLER
	severity_changes++
	last_old_severity = old_severity

/datum/dq_test_signal_counter/proc/on_afflictions_changed(datum/source, datum/affliction/A, added)
	SIGNAL_HANDLER
	if(!added)
		removals++

/// The treatment snapshot is built once and reused until reagents change;
/// drug interference is folded into the same build.
/datum/unit_test/dq_body_treatment_snapshot

/datum/unit_test/dq_body_treatment_snapshot/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_BICARIDINE, 10)
	var/list/first = H.body.treatment_levels()
	TEST_ASSERT(first?[TREAT_TISSUE_REPAIR] > 0, "bicaridine should provide tissue repair")
	TEST_ASSERT(H.body.treatment_levels() == first, "the snapshot should be reused while nothing changes")
	var/full_level = first[TREAT_TISSUE_REPAIR]

	H.bloodstr.add_reagent(REAGENT_ID_KELOTANE, 10)
	var/list/second = H.body.treatment_levels()
	TEST_ASSERT(second != first, "a reagent change should rebuild the snapshot")
	TEST_ASSERT(second[TREAT_BURN_CARE] > 0, "the rebuilt snapshot should see the new reagent")

	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	var/datum/affliction/custom/marker = H.body.afflict(/datum/affliction/custom, liver, 50)
	TEST_ASSERT_NOTNULL(marker, "could not place an interference marker")
	marker.interferes_with = list()
	marker.interferes_with[REAGENT_ID_BICARIDINE] = 0.5
	H.body.invalidate(BODY_DIRTY_TREATMENT)
	TEST_ASSERT_EQUAL(H.body.reagent_cure_modifier(REAGENT_ID_BICARIDINE), 0.5, "interference should be folded into the snapshot")
	TEST_ASSERT_EQUAL(H.body.treatment_levels()[TREAT_TISSUE_REPAIR], full_level * 0.5, "interference should scale the reagent's levels")

/// Natural regeneration is a treatment source: species x nutrition x sleep.
/datum/unit_test/dq_body_regeneration_level

/datum/unit_test/dq_body_regeneration_level/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/awake = H.body.regeneration_level()
	TEST_ASSERT(awake > 0, "a fed, living human should regenerate")
	H.sleeping = 5
	TEST_ASSERT_EQUAL(H.body.regeneration_level(), awake * REGENERATION_SLEEP_MULT, "sleep should speed natural regeneration")
	H.sleeping = 0
	H.nutrition = REGENERATION_STARVING_NUTRITION - 1
	TEST_ASSERT_EQUAL(H.body.regeneration_level(), 0, "a starving body should not regenerate")

/// Afflictions are indexed by location, and the index follows their lifecycle.
/datum/unit_test/dq_body_location_index

/datum/unit_test/dq_body_location_index/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	H.injure(INJURY_CUT, 10, arm, flags = DQ_TEST_INJURE)
	var/list/here = H.body.afflictions_by_location?[arm]
	TEST_ASSERT(length(here), "a wound on the arm should be indexed under the arm")
	for(var/datum/affliction/A as anything in here)
		TEST_ASSERT_EQUAL(A.location, arm, "the index must only hold afflictions located on the arm")
	TEST_ASSERT_EQUAL(length(H.body.afflictions_at(arm)), length(here), "afflictions_at() should read the index")
	H.fully_heal()
	TEST_ASSERT(!length(H.body.afflictions_by_location?[arm]), "cured afflictions should leave the index")

/// Severity changes are published as COMSIG_AFFLICTION_SEVERITY_CHANGED.
/datum/unit_test/dq_body_severity_signal

/datum/unit_test/dq_body_severity_signal/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/dq_test_signal_counter/counter = new
	counter.RegisterSignal(H, COMSIG_AFFLICTION_SEVERITY_CHANGED, TYPE_PROC_REF(/datum/dq_test_signal_counter, on_severity_changed))
	var/datum/affliction/A = H.body.afflict(/datum/affliction/toxic_poisoning, null, 40)
	TEST_ASSERT(counter.severity_changes >= 1, "setting severity should signal")
	A.adjust_severity(-10)
	TEST_ASSERT_EQUAL(counter.last_old_severity, 40, "the signal should carry the old severity")
	qdel(counter)

/// Destroying a body removes its afflictions through remove_affliction(), so
/// their removal hooks and signals run.
/datum/unit_test/dq_body_destroy_removes_afflictions

/datum/unit_test/dq_body_destroy_removes_afflictions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/toxic_poisoning, null, 30)
	var/datum/dq_test_signal_counter/counter = new
	counter.RegisterSignal(H, COMSIG_BODY_AFFLICTIONS_CHANGED, TYPE_PROC_REF(/datum/dq_test_signal_counter, on_afflictions_changed))
	var/datum/body/B = H.body
	H.body = null
	qdel(B)
	TEST_ASSERT_EQUAL(counter.removals, 1, "body.Destroy should remove the affliction through remove_affliction()")
	TEST_ASSERT(QDELETED(A), "the removed affliction should be deleted")
	TEST_ASSERT_NULL(A.body, "the removed affliction should not point at the dead body")
	qdel(counter)

/// injure() only marks the vitals dirty; the next query recomputes them.
/datum/unit_test/dq_body_injure_marks_dirty

/datum/unit_test/dq_body_injure_marks_dirty/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.body.recompute_vitals()
	H.injure(INJURY_BLUNT, 10, BP_TORSO, flags = DQ_TEST_INJURE)
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_VITALS, "injure() should leave the vitals dirty instead of recomputing them")
	TEST_ASSERT(H.vitality() < 1, "a vitals query should recompute")
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_VITALS), "the query should clear the dirty flag")

/// A limb's brute_mod is the part multiplier inside injury_multiplier().
/datum/unit_test/dq_body_part_multiplier

/datum/unit_test/dq_body_part_multiplier/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/left = H.get_organ(BP_L_ARM)
	var/obj/item/organ/external/right = H.get_organ(BP_R_ARM)
	left.brute_mod = 2
	H.injure(INJURY_BLUNT, 5, BP_L_ARM)
	H.injure(INJURY_BLUNT, 5, BP_R_ARM)
	TEST_ASSERT(right.get_trauma() > 0, "the right arm should be hurt")
	TEST_ASSERT_EQUAL(left.get_trauma(), 2 * right.get_trauma(), "brute_mod 2 should double the limb's physical injury")

/// An instant mend heals N points across a limb's wounds, not N per wound,
/// through the one shared mend pass (no limb loop).
/datum/unit_test/dq_body_wound_mend_budget

/datum/unit_test/dq_body_wound_mend_budget/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	H.injure(INJURY_CUT, 12, BP_R_ARM, flags = DQ_TEST_INJURE)
	H.injure(INJURY_BLUNT, 12, BP_R_ARM, flags = DQ_TEST_INJURE)
	var/before = arm.get_trauma()
	TEST_ASSERT(before >= 10, "setup should leave at least 10 trauma")
	var/treated = H.mend(TREAT_TISSUE_REPAIR, 6, BP_R_ARM)
	TEST_ASSERT(treated >= 6, "the mend should report what it healed (got [treated])")
	TEST_ASSERT_EQUAL(arm.get_trauma(), before - 6, "a 6-point mend should heal 6 points across the limb")

/// Continuous treatment heals wound damage through the shared tick pipeline.
/datum/unit_test/dq_body_wound_continuous_treatment

/datum/unit_test/dq_body_wound_continuous_treatment/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	H.injure(INJURY_BLUNT, 15, BP_R_ARM, flags = DQ_TEST_INJURE)
	var/before = arm.get_trauma()
	H.bloodstr.add_reagent(REAGENT_ID_BICARIDINE, 10)
	for(var/datum/affliction/wound/W as anything in arm.get_wounds())
		W.tick()
	TEST_ASSERT(arm.get_trauma() < before, "bicaridine in the blood should heal the arm's wounds ([before] -> [arm.get_trauma()])")

/// TREAT_RESTORATION heals every wound, internal bleeding included.
/datum/unit_test/dq_body_restoration_heals_internal_wounds

/datum/unit_test/dq_body_restoration_heals_internal_wounds/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/datum/affliction/wound/internal_bleeding/W = new(torso, 10)
	torso.add_wound(W)
	H.mend(TREAT_TISSUE_REPAIR, 100, torso)
	TEST_ASSERT_EQUAL(W.damage, 10, "tissue repair must not close an arterial bleed")
	H.mend(TREAT_RESTORATION, 100, torso)
	TEST_ASSERT_EQUAL(W.damage, 0, "restoration should close an arterial bleed")

#undef DQ_TEST_INJURE

#endif
