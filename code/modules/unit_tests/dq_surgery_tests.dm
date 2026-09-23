// Unit tests for the surgery framework (code/modules/surgery/): the
// incision state, treatment-tag steps, complications, synthetic repair,
// organ removal and insertion, outcome conditions and the procedure records.
//
// Steps are driven directly (perform() / complicate()) so the tests don't
// depend on do_after timing or dice.
//
// Sibling test files in this directory cover bodyscanner and the
// cross-cutting audit. They share helper procs declared on the base
// unit_test type in code/modules/unit_tests/dq_medical_tests.dm.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#include "../medical/_defines.dm"

/// Perform `step_type` on `H` at `zone` as `surgeon`, on `work_target`
/// (default: the limb).
/datum/unit_test/proc/_surgery_perform(step_type, mob/living/carbon/human/surgeon, mob/living/carbon/human/H, zone, obj/item/tool = null, atom/work_target = null)
	var/datum/surgical_step/S = surgical_step(step_type)
	var/obj/item/organ/external/part = H.get_organ(zone)
	S.perform(surgeon, H, part, tool, work_target || part)

/// Make `step_type` fail on `H` at `zone` (its complication).
/datum/unit_test/proc/_surgery_fail(step_type, mob/living/carbon/human/surgeon, mob/living/carbon/human/H, zone, obj/item/tool = null, atom/work_target = null)
	var/datum/surgical_step/S = surgical_step(step_type)
	var/obj/item/organ/external/part = H.get_organ(zone)
	S.complicate(surgeon, H, part, tool, work_target || part)

/datum/unit_test/proc/_has_affliction_type(mob/living/carbon/human/H, affliction_type)
	for(var/datum/affliction/A in H.get_afflictions())
		if(istype(A, affliction_type))
			return TRUE
	return FALSE


// --- registry ------------------------------------------------------------------

/datum/unit_test/dq_surgery_registry_populates

/datum/unit_test/dq_surgery_registry_populates/Run()
	var/list/steps = surgical_steps()
	TEST_ASSERT(length(steps) > 0, "the surgical step registry is empty")
	for(var/datum/surgical_step/S as anything in steps)
		TEST_ASSERT(S.abstract_type != S.type, "abstract step [S.type] was registered")
		TEST_ASSERT(S.name && S.name != "surgical step", "[S.type] has no name")
		TEST_ASSERT(S.part_biology, "[S.type] works on no biology")
		for(var/tag in S.treatments)
			TEST_ASSERT(dq_treatment_tag_names()[tag], "[S.type] delivers unknown treatment tag [tag]")

/// Every procedure record names real steps, and every condition it treats
/// responds to a mechanism those steps deliver (or the record repairs organs).
/datum/unit_test/dq_surgery_records_well_formed

/datum/unit_test/dq_surgery_records_well_formed/Run()
	for(var/T in subtypesof(/datum/dq_surgery))
		var/datum/dq_surgery/sg = new T()
		TEST_ASSERT(sg.name, "[T] has no name")
		TEST_ASSERT(length(sg.steps), "[T] has no prose steps")
		TEST_ASSERT(length(sg.procedure), "[T] names no surgical steps")
		for(var/step_type in sg.procedure)
			TEST_ASSERT(surgical_step(step_type), "[T] names unregistered step [step_type]")
		var/list/delivered = sg.delivered_tags()
		for(var/cond in sg.treats)
			TEST_ASSERT(ispath(cond, /datum/affliction), "[T] treats non-affliction [cond]")
			if(length(sg.repairs_organs))
				continue
			var/datum/affliction/proto = dq_proto(cond)
			var/linked = FALSE
			for(var/tag in delivered)
				if(proto.treatment_rate(tag))
					linked = TRUE
					break
			TEST_ASSERT(linked, "[T] claims to treat [cond], but none of its steps deliver a mechanism it responds to")
		qdel(sg)


// --- incision state ---------------------------------------------------------------

/datum/unit_test/dq_surgery_incision_opens_and_closes

/datum/unit_test/dq_surgery_incision_opens_and_closes/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT_NULL(arm.get_incision(), "a fresh arm has no incision")

	_surgery_perform(/datum/surgical_step/access/incise, surgeon, H, BP_L_ARM)
	var/datum/affliction/surgical_incision/I = arm.get_incision()
	TEST_ASSERT_NOTNULL(I, "an incision should create the incision affliction")
	TEST_ASSERT_EQUAL(arm.surgical_depth(), INCISION_MADE, "the incision is at skin depth")
	TEST_ASSERT_EQUAL(arm.open, INCISION_MADE, "the limb's open cache follows the incision")
	TEST_ASSERT(_has_affliction_type(H, /datum/affliction/surgical_incision), "the incision is on the patient's body")

	_surgery_perform(/datum/surgical_step/access/retract, surgeon, H, BP_L_ARM)
	TEST_ASSERT_EQUAL(arm.surgical_depth(), FLESH_RETRACTED, "retracting deepens the site")

	var/datum/surgical_step/cauterize = surgical_step(/datum/surgical_step/cauterize)
	TEST_ASSERT(cauterize.can_use(surgeon, H, BP_L_ARM, null), "an open site can be cauterized")
	_surgery_perform(/datum/surgical_step/cauterize, surgeon, H, BP_L_ARM)
	TEST_ASSERT_NULL(arm.get_incision(), "closing should clear the incision")
	TEST_ASSERT_EQUAL(arm.open, SURGERY_DEPTH_CLOSED, "the limb's open cache is cleared on close")
	TEST_ASSERT(!_has_affliction_type(H, /datum/affliction/surgical_incision), "no incision left on the body")
	TEST_ASSERT(!cauterize.can_use(surgeon, H, BP_L_ARM, null), "a closed limb has nothing to cauterize")

/// The bone layer has to be set before the skin closes.
/datum/unit_test/dq_surgery_bone_layer_closes_first

/datum/unit_test/dq_surgery_bone_layer_closes_first/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	TEST_ASSERT_EQUAL(chest.surgical_full_access(), BONE_RETRACTED, "the torso is encased")
	_surgery_perform(/datum/surgical_step/access/incise, surgeon, H, BP_TORSO)
	_surgery_perform(/datum/surgical_step/access/retract, surgeon, H, BP_TORSO)
	_surgery_perform(/datum/surgical_step/access/saw, surgeon, H, BP_TORSO)
	_surgery_perform(/datum/surgical_step/access/pry_bone, surgeon, H, BP_TORSO)
	TEST_ASSERT_EQUAL(chest.surgical_depth(), BONE_RETRACTED, "the ribcage is open")

	_surgery_perform(/datum/surgical_step/cauterize, surgeon, H, BP_TORSO)
	TEST_ASSERT_EQUAL(chest.surgical_depth(), BONE_RETRACTED, "the skin can't close over an open ribcage")

	_surgery_perform(/datum/surgical_step/set_bone, surgeon, H, BP_TORSO)
	TEST_ASSERT_EQUAL(chest.surgical_depth(), FLESH_RETRACTED, "setting the bone closes the bone layer")
	_surgery_perform(/datum/surgical_step/cauterize, surgeon, H, BP_TORSO)
	TEST_ASSERT_NULL(chest.get_incision(), "then the skin closes")

/// An open site bleeds until clamped and gathers germs by its sterility.
/datum/unit_test/dq_surgery_incision_bleeds_and_infects

/datum/unit_test/dq_surgery_incision_bleeds_and_infects/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	var/datum/affliction/surgical_incision/I = leg.open_surgical_site(INCISION_MADE, 0)
	TEST_ASSERT(I.is_bleeding(), "an unclamped incision bleeds")
	leg.update_damages()
	TEST_ASSERT(leg.status & ORGAN_BLEEDING, "the limb reports the incision's bleeding")

	var/germs_before = leg.germ_level
	I.progress()
	TEST_ASSERT(leg.germ_level > germs_before, "a site opened on a dirty surface gathers germs")

	_surgery_perform(/datum/surgical_step/clamp_bleeders, surgeon, H, BP_L_LEG)
	TEST_ASSERT(!I.is_bleeding(), "clamping stops the incision bleeding")

	var/obj/item/organ/external/right_leg = H.get_organ(BP_R_LEG)
	var/datum/affliction/surgical_incision/clean = right_leg.open_surgical_site(INCISION_MADE, 100)
	var/clean_germs = right_leg.germ_level
	clean.progress()
	TEST_ASSERT_EQUAL(right_leg.germ_level, clean_germs, "a site opened on a sterile surface stays clean")


// --- organ repair: each step cures only its own lesions -----------------------------------

/datum/unit_test/dq_surgery_organ_steps_match_lesions

/datum/unit_test/dq_surgery_organ_steps_match_lesions/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	TEST_ASSERT_NOTNULL(liver, "no liver")
	H.injure(INJURY_CUT, 10, liver, affliction = /datum/affliction/lesion/laceration, flags = INJURE_IGNORE_RESISTANCE)
	H.injure(INJURY_CUT, 10, liver, affliction = /datum/affliction/lesion/necrosis, flags = INJURE_IGNORE_RESISTANCE)
	TEST_ASSERT_NOTNULL(liver.find_lesion(/datum/affliction/lesion/laceration), "laceration didn't form")
	TEST_ASSERT_NOTNULL(liver.find_lesion(/datum/affliction/lesion/necrosis), "necrosis didn't form")

	_surgery_perform(/datum/surgical_step/treat/organ/suture, surgeon, H, BP_GROIN, null, liver)
	TEST_ASSERT_NULL(liver.find_lesion(/datum/affliction/lesion/laceration), "suturing closes the laceration")
	TEST_ASSERT_NOTNULL(liver.find_lesion(/datum/affliction/lesion/necrosis), "suturing doesn't touch necrosis")

	_surgery_perform(/datum/surgical_step/treat/organ/resection, surgeon, H, BP_GROIN, null, liver)
	TEST_ASSERT_NULL(liver.find_lesion(/datum/affliction/lesion/necrosis), "resection removes the necrosis")

/// Only the chosen organ is repaired.
/datum/unit_test/dq_surgery_organ_repair_is_targeted

/datum/unit_test/dq_surgery_organ_repair_is_targeted/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	var/obj/item/organ/internal/lungs = H.internal_organs_by_name[O_LUNGS]
	H.injure(INJURY_BLUNT, 10, heart, affliction = /datum/affliction/lesion/contusion, flags = INJURE_IGNORE_RESISTANCE)
	H.injure(INJURY_BLUNT, 10, lungs, affliction = /datum/affliction/lesion/contusion, flags = INJURE_IGNORE_RESISTANCE)
	_surgery_perform(/datum/surgical_step/treat/organ/suture, surgeon, H, BP_TORSO, null, heart)
	TEST_ASSERT_NULL(heart.find_lesion(/datum/affliction/lesion/contusion), "the heart was repaired")
	TEST_ASSERT_NOTNULL(lungs.find_lesion(/datum/affliction/lesion/contusion), "the lungs weren't operated on")

/// An organ past saving still takes the step, and nothing heals.
/datum/unit_test/dq_surgery_organ_beyond_repair_heals_nothing

/datum/unit_test/dq_surgery_organ_beyond_repair_heals_nothing/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT_NOTNULL(brain, "no brain")
	H.injure(INJURY_CUT, 10, brain, affliction = /datum/affliction/lesion/laceration, flags = INJURE_IGNORE_RESISTANCE)
	brain.status |= ORGAN_DEAD
	TEST_ASSERT(brain.is_beyond_repair(), "a dead brain is beyond repair")
	var/datum/surgical_step/treat/organ/suture = surgical_step(/datum/surgical_step/treat/organ/suture)
	TEST_ASSERT(suture.location_needs_treatment(H, brain), "the surgeon can still work on it")
	_surgery_perform(/datum/surgical_step/treat/organ/suture, surgeon, H, BP_HEAD, null, brain)
	TEST_ASSERT_NOTNULL(brain.find_lesion(/datum/affliction/lesion/laceration), "nothing heals in an organ beyond repair")


// --- conditions that need surgery -----------------------------------------------------------

/datum/unit_test/dq_surgery_steps_cure_their_conditions

/datum/unit_test/dq_surgery_steps_cure_their_conditions/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	// condition, zone, step
	var/list/cases = list(
		list(/datum/affliction/untreated_fracture, BP_L_ARM, /datum/surgical_step/set_bone),
		list(/datum/affliction/tendon_severed, BP_L_LEG, /datum/surgical_step/treat/tendon_repair),
		list(/datum/affliction/compartment_syndrome, BP_R_LEG, /datum/surgical_step/treat/decompression),
		list(/datum/affliction/pneumothorax, BP_TORSO, /datum/surgical_step/treat/decompression),
		list(/datum/affliction/internal_hemorrhage, BP_TORSO, /datum/surgical_step/treat/vessel_repair),
		list(/datum/affliction/lacerated_artery, BP_R_ARM, /datum/surgical_step/treat/vessel_repair),
		list(/datum/affliction/tissue_necrosis, BP_R_ARM, /datum/surgical_step/treat/debridement),
		list(/datum/affliction/subdural_hematoma, BP_HEAD, /datum/surgical_step/treat/decompression),
	)
	for(var/list/c in cases)
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
		var/cond = c[1]
		var/zone = c[2]
		var/step_type = c[3]
		var/datum/affliction/A = _spawn_affliction_on(H, zone, cond)
		TEST_ASSERT_NOTNULL(A, "[cond] didn't spawn on [zone]")
		var/obj/item/organ/external/part = H.get_organ(zone)
		part.open_surgical_site(part.surgical_full_access(), 100)
		var/datum/surgical_step/S = surgical_step(step_type)
		TEST_ASSERT(S.can_use(surgeon, H, zone, null), "[step_type] should offer itself for [cond]")
		_surgery_perform(step_type, surgeon, H, zone)
		TEST_ASSERT(!_has_affliction_type(H, cond), "[step_type] should cure [cond]")

/datum/unit_test/dq_surgery_does_not_cure_unrelated

/datum/unit_test/dq_surgery_does_not_cure_unrelated/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	_spawn_affliction_on(H, BP_TORSO, /datum/affliction/cellulitis)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	chest.open_surgical_site(BONE_RETRACTED, 100)
	var/datum/surgical_step/vessels = surgical_step(/datum/surgical_step/treat/vessel_repair)
	TEST_ASSERT(!vessels.can_use(surgeon, H, BP_TORSO, null), "vessel repair has nothing to do for cellulitis")
	_surgery_perform(/datum/surgical_step/treat/vessel_repair, surgeon, H, BP_TORSO)
	TEST_ASSERT(_has_affliction_type(H, /datum/affliction/cellulitis), "cellulitis isn't cured by vessel repair")


// --- failure creates a complication ------------------------------------------------------------

/datum/unit_test/dq_surgery_failure_complicates

/datum/unit_test/dq_surgery_failure_complicates/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	// A nicked organ is a lesion.
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_NULL(heart.find_lesion(/datum/affliction/lesion/laceration), "the heart starts whole")
	_surgery_fail(/datum/surgical_step/treat/organ/suture, surgeon, H, BP_TORSO, null, heart)
	TEST_ASSERT_NOTNULL(heart.find_lesion(/datum/affliction/lesion/laceration), "a slipped suture lacerates the organ")

	// A cut vessel is a bleed.
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	_surgery_fail(/datum/surgical_step/treat/vessel_repair, surgeon, H, BP_L_ARM)
	var/bleeding = FALSE
	for(var/datum/affliction/wound/internal_bleeding/W in arm.afflictions_here())
		bleeding = TRUE
	TEST_ASSERT(bleeding, "a slipped vessel repair tears an artery")

	// A slipped scalpel cuts.
	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	var/trauma_before = leg.get_trauma()
	_surgery_fail(/datum/surgical_step/access/incise, surgeon, H, BP_L_LEG)
	TEST_ASSERT(leg.get_trauma() > trauma_before, "a slipped incision wounds the limb")


// --- synthetic limbs ---------------------------------------------------------------------------

/datum/unit_test/dq_surgery_robotic_limb_repair_tags

/datum/unit_test/dq_surgery_robotic_limb_repair_tags/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	arm.robotize()
	TEST_ASSERT(arm.robotic >= ORGAN_ROBOT, "the arm is prosthetic")

	var/datum/surgical_step/incise = surgical_step(/datum/surgical_step/access/incise)
	var/datum/surgical_step/unscrew = surgical_step(/datum/surgical_step/access/unscrew_panel)
	TEST_ASSERT(!incise.can_use(surgeon, H, BP_R_ARM, null), "a scalpel incision doesn't apply to plating")
	TEST_ASSERT(unscrew.can_use(surgeon, H, BP_R_ARM, null), "a prosthetic opens by its panel")

	H.injure(INJURY_BLUNT, 20, arm, flags = INJURE_IGNORE_RESISTANCE)
	var/dented = arm.get_trauma()
	TEST_ASSERT(dented > 0, "the plating took damage")

	_surgery_perform(/datum/surgical_step/access/unscrew_panel, surgeon, H, BP_R_ARM)
	_surgery_perform(/datum/surgical_step/access/open_hatch, surgeon, H, BP_R_ARM)
	TEST_ASSERT_EQUAL(arm.surgical_depth(), FLESH_RETRACTED, "the hatch is open")

	// Organic tissue repair does nothing to plating; the plating repair tag does.
	var/datum/surgical_step/flesh = surgical_step(/datum/surgical_step/treat/repair_flesh)
	TEST_ASSERT(!flesh.can_use(surgeon, H, BP_R_ARM, null), "flesh repair doesn't apply to a prosthetic")
	var/datum/surgical_step/weld = surgical_step(/datum/surgical_step/treat/repair_plating)
	TEST_ASSERT(weld.can_use(surgeon, H, BP_R_ARM, null), "plating repair offers itself for dented plating")
	TEST_ASSERT(TREAT_PLATING_REPAIR in weld.treatments, "plating repair works through TREAT_PLATING_REPAIR")
	_surgery_perform(/datum/surgical_step/treat/repair_plating, surgeon, H, BP_R_ARM)
	TEST_ASSERT(arm.get_trauma() < dented, "welding repairs the plating")

	// Surgical closure (organic) doesn't close a panel; panel closure does.
	H.mend(TREAT_SURGICAL_CLOSURE, 100, arm)
	TEST_ASSERT_NOTNULL(arm.get_incision(), "organic closure doesn't close a panel")
	_surgery_perform(/datum/surgical_step/close_panel, surgeon, H, BP_R_ARM)
	TEST_ASSERT_NULL(arm.get_incision(), "the panel closes")


// --- organ removal and insertion ------------------------------------------------------------------

/datum/unit_test/dq_surgery_organ_reinsertion_keeps_afflictions

/datum/unit_test/dq_surgery_organ_reinsertion_keeps_afflictions/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	H.injure(INJURY_CUT, 10, liver, affliction = /datum/affliction/lesion/laceration, flags = INJURE_IGNORE_RESISTANCE)
	var/datum/affliction/lesion/laceration/L = liver.find_lesion(/datum/affliction/lesion/laceration)
	TEST_ASSERT_NOTNULL(L, "laceration didn't form")
	var/damage = liver.damage

	var/zone = liver.parent_organ
	_surgery_perform(/datum/surgical_step/organ/extract, surgeon, H, zone, null, liver)
	TEST_ASSERT_NULL(liver.owner, "the liver is out")
	TEST_ASSERT_NULL(H.internal_organs_by_name[O_LIVER], "the patient has no liver")
	TEST_ASSERT(!(L in H.get_afflictions()), "the lesion left the body with the liver")
	TEST_ASSERT(!QDELETED(L), "the lesion travels with the liver")
	TEST_ASSERT_EQUAL(L.location, liver, "the lesion is still on the liver")
	TEST_ASSERT_EQUAL(liver.damage, damage, "the loose liver keeps its damage")

	_surgery_perform(/datum/surgical_step/organ/insert, surgeon, H, zone, liver)
	TEST_ASSERT_EQUAL(liver.owner, H, "the liver is back in")
	TEST_ASSERT_EQUAL(H.internal_organs_by_name[O_LIVER], liver, "the patient has their liver again")
	TEST_ASSERT(L in H.get_afflictions(), "the lesion came back with the liver")
	TEST_ASSERT_EQUAL(L.owner, H, "the lesion belongs to the patient again")


// --- outcome conditions -------------------------------------------------------------------------

/datum/unit_test/dq_surgery_success_conditions

/datum/unit_test/dq_surgery_success_conditions/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/surgical/scalpel/scalpel = allocate(/obj/item/surgical/scalpel)
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/surgical_step/S = surgical_step(/datum/surgical_step/access/incise)

	var/on_table = S.success_chance(surgeon, H, arm, scalpel, 100)
	var/on_floor = S.success_chance(surgeon, H, arm, scalpel, 0)
	TEST_ASSERT(on_floor < on_table, "the floor ([on_floor]) is worse than an operating table ([on_table])")
	var/improvised = S.success_chance(surgeon, H, arm, knife, 100)
	TEST_ASSERT(improvised < on_table, "a knife ([improvised]) is worse than a scalpel ([on_table])")

	// A conscious patient with no pain relief flinches; an unconscious one doesn't.
	TEST_ASSERT(S.patient_mult(H, arm) < 1, "a conscious, unmedicated patient is a risk")
	H.stat = UNCONSCIOUS
	TEST_ASSERT_EQUAL(S.patient_mult(H, arm), 1, "an anaesthetised patient holds still")
	H.stat = CONSCIOUS

	// Operating on yourself is harder.
	var/self = S.success_chance(H, H, arm, scalpel, 100)
	TEST_ASSERT(self < S.success_chance(surgeon, H, arm, scalpel, 100), "self-surgery is harder")

// --- chem presence: single-chem side effect spawns and clears --------

/datum/unit_test/dq_chem_presence_side_effect_spawns

/datum/unit_test/dq_chem_presence_side_effect_spawns/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	// No alkysine yet — no side condition.
	H.dq_check_chem_conditions()
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/chem_side_effect/alkysine_confusion))
			TEST_FAIL("alkysine_confusion should not exist without the chem")

	// Dose past the 5u threshold — condition should spawn.
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 10)
	H.dq_check_chem_conditions()
	var/found = FALSE
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/chem_side_effect/alkysine_confusion))
			found = TRUE
			break
	TEST_ASSERT(found, "alkysine_confusion should spawn when alkysine ≥ 5u")

	// Drain the chem — the condition should clear.
	H.bloodstr.remove_reagent(REAGENT_ID_ALKYSINE, 10)
	H.dq_check_chem_conditions()
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/chem_side_effect/alkysine_confusion))
			TEST_FAIL("alkysine_confusion should clear when the chem is gone")


// --- chem presence: interaction needs BOTH chems above threshold ----

/datum/unit_test/dq_chem_presence_interaction_requires_both

/datum/unit_test/dq_chem_presence_interaction_requires_both/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	// Only inaprovaline — no interaction.
	H.bloodstr.add_reagent(REAGENT_ID_INAPROVALINE, 10)
	H.dq_check_chem_conditions()
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/chem_interaction/tachycardia_chem))
			TEST_FAIL("tachycardia interaction should NOT fire with only one chem present")

	// Add hyperzine — both present, interaction fires.
	H.bloodstr.add_reagent(REAGENT_ID_HYPERZINE, 10)
	H.dq_check_chem_conditions()
	var/found = FALSE
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/chem_interaction/tachycardia_chem))
			found = TRUE
			break
	TEST_ASSERT(found, "tachycardia interaction should fire when both chems present")

	// Remove one — interaction clears.
	H.bloodstr.remove_reagent(REAGENT_ID_INAPROVALINE, 10)
	H.dq_check_chem_conditions()
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/chem_interaction/tachycardia_chem))
			TEST_FAIL("tachycardia interaction should clear when one chem leaves")


// --- interference: interferes_with reduces cure rate on other conds --

/datum/unit_test/dq_interference_reduces_cure_rate

/datum/unit_test/dq_interference_reduces_cure_rate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Spawn an infection that's cured by spaceacillin.
	var/datum/affliction/cellulitis/C = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/cellulitis)
	TEST_ASSERT_NOTNULL(C, "cellulitis spawn failed")
	C.severity = 50

	// Drop spaceacillin in the bloodstream — without the interaction
	// marker, cellulitis should heal at full rate.
	H.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 100)
	var/sev_before = C.severity
	C.tick()
	var/normal_delta = sev_before - C.severity
	TEST_ASSERT(normal_delta > 0, "spaceacillin should drop cellulitis severity (no interaction)")

	// Reset, add the interference marker, tick again — delta should
	// be smaller.
	C.severity = 50
	var/datum/affliction/chem_interaction/bicaridine_antibiotic_interference/M = _spawn_affliction_on(H, O_LIVER, /datum/affliction/chem_interaction/bicaridine_antibiotic_interference)
	TEST_ASSERT_NOTNULL(M, "interference marker spawn failed")
	C.tick()
	var/blocked_delta = 50 - C.severity
	TEST_ASSERT(blocked_delta < normal_delta, "interference should reduce cure delta (no_int=[normal_delta], with_int=[blocked_delta])")


// --- Bicaridine OD drains subdural hematoma ---------------------------

/datum/unit_test/dq_bicaridine_od_drains_hematoma

/datum/unit_test/dq_bicaridine_od_drains_hematoma/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/subdural_hematoma/sh = _spawn_affliction_on(H, BP_HEAD, /datum/affliction/subdural_hematoma)
	TEST_ASSERT_NOTNULL(sh, "hematoma should spawn")
	sh.severity = 60
	var/start = sh.severity

	// Bicaridine OD: 40u total, 10u over threshold of 30. Each call
	// to dq_check_chem_conditions ramps the OD severity AND applies
	// od_cures_externally to the hematoma.
	H.bloodstr.add_reagent(REAGENT_ID_BICARIDINE, 40)
	for(var/i in 1 to 80)
		H.dq_check_chem_conditions()
	TEST_ASSERT(sh.severity < start, "bicaridine OD should drain hematoma severity ([start] -> [sh.severity])")


// --- Cordradaxon OD drains heart_damage -------------------------------

/datum/unit_test/dq_cordradaxon_od_drains_heart_damage

/datum/unit_test/dq_cordradaxon_od_drains_heart_damage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/heart_damage/hd = _spawn_affliction_on(H, O_HEART, /datum/affliction/heart_damage)
	TEST_ASSERT_NOTNULL(hd, "heart_damage should spawn")
	hd.severity = 80
	var/start = hd.severity

	H.bloodstr.add_reagent(REAGENT_ID_CORDRADAXON, 25)  // 15 over threshold 10
	for(var/i in 1 to 80)
		H.dq_check_chem_conditions()
	TEST_ASSERT(hd.severity < start, "cordradaxon OD should drain heart_damage ([start] -> [hd.severity])")


// --- Hyperzine OD speeds movement ---------------------------------------

/datum/unit_test/dq_hyperzine_od_speeds_movement

/datum/unit_test/dq_hyperzine_od_speeds_movement/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/base = H.factor(BF_SLOWDOWN)

	H.bloodstr.add_reagent(REAGENT_ID_HYPERZINE, 40)  // 10 over OD threshold of 30
	for(var/i in 1 to 50)
		H.dq_check_chem_conditions()
	TEST_ASSERT(H.has_affliction(/datum/affliction/overdose/hyperzine), "40u of hyperzine should overdose")
	// The stimulant and its overdose stage both speed the patient up.
	var/slow = H.factor(BF_SLOWDOWN) - base
	TEST_ASSERT(slow < 0, "hyperzine OD should produce negative slowdown (boost): got [slow]")


// --- Brain swelling (lesion drift): OD upside + neural repair rescue the salvage band ---
// The old organ_decay/brain.dm bands now live in the brain's lesions
// (lesions.dm secondary_injury()); these tests tick the brain's lesions
// through the shared affliction pipeline.

/datum/unit_test/dq_synaptizine_od_rescues_brain_with_alkysine

/datum/unit_test/dq_synaptizine_od_rescues_brain_with_alkysine/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]

	// 70% damage: in the salvage band, above the 60% swelling floor.
	dq_test_set_organ_damage(B, B.max_damage * 0.7)
	var/start = B.damage

	// Stack synaptizine OD AND alkysine. The combo should heal slowly.
	H.bloodstr.add_reagent(REAGENT_ID_SYNAPTIZINE, 40)  // 10 over OD threshold
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 10)
	// Ramp the OD condition to max severity so its boost is at full.
	for(var/i in 1 to 50)
		H.dq_check_chem_conditions()
	var/datum/affliction/overdose/synaptizine/od
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/overdose/synaptizine))
			od = c
			break
	TEST_ASSERT_NOTNULL(od, "synaptizine OD should be spawned")
	TEST_ASSERT_EQUAL(od.severity, 100, "OD should ramp to max severity")

	for(var/i in 1 to 30)
		dq_test_tick_organ(B)
	TEST_ASSERT(B.damage < start, "brain in salvage band should heal with synaptizine OD + alkysine ([start] -> [B.damage])")


// --- A standard dose of neural repair can't keep up with a swollen brain --

/datum/unit_test/dq_brain_swelling_blunts_treatment

/datum/unit_test/dq_brain_swelling_blunts_treatment/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	dq_test_set_organ_damage(B, B.max_damage * 0.7)
	var/start = B.damage

	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 10)
	for(var/i in 1 to 30)
		dq_test_tick_organ(B)
	TEST_ASSERT(B.damage >= start, "a standard neural-repair dose should not net heal a swollen brain ([start] -> [B.damage])")


// --- Past 90% is terminal regardless of chems -------------------------

/datum/unit_test/dq_brain_terminal_zone_is_unsavable

/datum/unit_test/dq_brain_terminal_zone_is_unsavable/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	dq_test_set_organ_damage(B, B.max_damage * 0.92)  // past terminal floor
	var/start = B.damage

	// Full chem combo. Should still progress to max damage.
	H.bloodstr.add_reagent(REAGENT_ID_SYNAPTIZINE, 60)
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 30)
	for(var/i in 1 to 50)
		H.dq_check_chem_conditions()
	for(var/i in 1 to 10)
		dq_test_tick_organ(B)

	TEST_ASSERT(B.damage > start, "past 90% should keep climbing despite full chem combo ([start] -> [B.damage])")
	TEST_ASSERT_NOTNULL(B.find_lesion(/datum/affliction/lesion/ischemic_injury), "the swelling should be carried by an ischemic lesion")


// --- OD stages: severity drives stage label --------------------------

/datum/unit_test/dq_overdose_stages_assigned_by_severity

/datum/unit_test/dq_overdose_stages_assigned_by_severity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// peridaxon OD threshold = 10u, climb 0.3 per unit-over per tick.
	// Dose 12u (2 over) gives 0.6 climb/tick — slow build, easy to
	// check stage transitions across many ticks.
	H.bloodstr.add_reagent(REAGENT_ID_PERIDAXON, 12)
	for(var/i in 1 to 200)
		H.dq_check_chem_conditions()
		var/datum/affliction/overdose/peridaxon/od
		for(var/datum/affliction/c in H.get_afflictions())
			if(istype(c, /datum/affliction/overdose/peridaxon))
				od = c
				break
		if(!od)
			continue
		// Check the stage matches the severity band at each step.
		var/expected
		if(od.severity >= 90)
			expected = "Critical"
		else if(od.severity >= 60)
			expected = "Severe"
		else if(od.severity >= 25)
			expected = "Mild"
		else
			expected = null
		TEST_ASSERT_EQUAL(od.stage, expected, "severity [od.severity] should be stage [expected || "null"] (got [od.stage || "null"])")


// --- OD severity scales with how-far-over -----------------------------

/datum/unit_test/dq_overdose_severity_climbs_with_overage

/datum/unit_test/dq_overdose_severity_climbs_with_overage/Run()
	// At 1u over the OD threshold, severity should climb slowly. At
	// 30u over it should climb much faster. Tick once at each level
	// and compare.
	var/mob/living/carbon/human/H_low = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H_high = allocate(/mob/living/carbon/human)

	// peridaxon OD threshold is 10u — author dose 11u (1 over) and 40u (30 over).
	H_low.bloodstr.add_reagent(REAGENT_ID_PERIDAXON, 11)
	H_high.bloodstr.add_reagent(REAGENT_ID_PERIDAXON, 40)

	H_low.dq_check_chem_conditions()
	H_high.dq_check_chem_conditions()

	var/datum/affliction/overdose/peridaxon/low_OD
	var/datum/affliction/overdose/peridaxon/high_OD
	for(var/datum/affliction/c in H_low.get_afflictions())
		if(istype(c, /datum/affliction/overdose/peridaxon))
			low_OD = c
			break
	for(var/datum/affliction/c in H_high.get_afflictions())
		if(istype(c, /datum/affliction/overdose/peridaxon))
			high_OD = c
			break
	TEST_ASSERT_NOTNULL(low_OD, "peridaxon at 11u should spawn OD condition")
	TEST_ASSERT_NOTNULL(high_OD, "peridaxon at 40u should spawn OD condition")
	TEST_ASSERT(high_OD.severity > low_OD.severity, "30u-over should climb faster than 1u-over (low=[low_OD.severity], high=[high_OD.severity])")


// --- OD severity decays after the chem clears ------------------------

/datum/unit_test/dq_overdose_severity_decays_after_chem_clears

/datum/unit_test/dq_overdose_severity_decays_after_chem_clears/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_PERIDAXON, 40)
	// Pump severity up to peak.
	for(var/i in 1 to 30)
		H.dq_check_chem_conditions()
	var/datum/affliction/overdose/peridaxon/od
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/overdose/peridaxon))
			od = c
			break
	TEST_ASSERT_NOTNULL(od, "peridaxon OD should be spawned")
	var/peak = od.severity
	TEST_ASSERT(peak > 50, "peak severity should be high (got [peak])")

	// Drain the chem and tick — severity should decay but not vanish.
	H.bloodstr.remove_reagent(REAGENT_ID_PERIDAXON, 100)
	for(var/i in 1 to 3)
		H.dq_check_chem_conditions()
	TEST_ASSERT(!QDELETED(od), "OD should not be immediately cured when chem clears (lingers)")
	TEST_ASSERT(od.severity < peak, "severity should be decaying (was [peak], now [od.severity])")

	// Keep ticking until it clears.
	for(var/i in 1 to 100)
		H.dq_check_chem_conditions()
		if(QDELETED(od))
			break
	TEST_ASSERT(QDELETED(od), "OD should eventually clear via decay")


// --- side-effect conditions stay binary (not scaling) ----------------

/datum/unit_test/dq_side_effect_stays_binary

/datum/unit_test/dq_side_effect_stays_binary/Run()
	// alkysine_confusion has no chem_scaling — should spawn at severity
	// 50 regardless of dose magnitude, and clear instantly on chem drop.
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 5)  // exactly threshold

	for(var/i in 1 to 5)
		H.dq_check_chem_conditions()

	var/datum/affliction/chem_side_effect/alkysine_confusion/cc
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/chem_side_effect/alkysine_confusion))
			cc = c
			break
	TEST_ASSERT_NOTNULL(cc, "alkysine_confusion should spawn at threshold dose")
	TEST_ASSERT_EQUAL(cc.severity, 50, "side effect should stay at severity 50 (got [cc.severity])")


// --- cure rate scales with chem volume ------------------------------

/datum/unit_test/dq_cure_rate_scales_with_volume

/datum/unit_test/dq_cure_rate_scales_with_volume/Run()
	// Tick a freshly-cellulitis patient with a sub-standard dose vs a
	// standard dose vs a cap dose. Healing should be ordered:
	//   trace (1u)  < standard (10u)  < cap (30u+)
	var/mob/living/carbon/human/H1 = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H3 = allocate(/mob/living/carbon/human)

	var/datum/affliction/cellulitis/C1 = _spawn_affliction_on(H1, BP_TORSO, /datum/affliction/cellulitis)
	var/datum/affliction/cellulitis/C2 = _spawn_affliction_on(H2, BP_TORSO, /datum/affliction/cellulitis)
	var/datum/affliction/cellulitis/C3 = _spawn_affliction_on(H3, BP_TORSO, /datum/affliction/cellulitis)
	C1.severity = 50
	C2.severity = 50
	C3.severity = 50

	H1.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 1)   // sub-dose
	H2.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 10)  // standard dose
	H3.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 50)  // capped above 30

	C1.tick()
	C2.tick()
	C3.tick()

	var/d1 = 50 - C1.severity
	var/d2 = 50 - C2.severity
	var/d3 = 50 - C3.severity

	TEST_ASSERT(d1 < d2, "1u dose should heal slower than 10u (got [d1] vs [d2])")
	TEST_ASSERT(d2 < d3, "10u dose should heal slower than 30u (got [d2] vs [d3])")


/datum/unit_test/dq_cure_rate_caps_at_dose_cap

/datum/unit_test/dq_cure_rate_caps_at_dose_cap/Run()
	// 40u and 100u should produce the same cure delta — past the cap,
	// extra chem doesn't help (and would only raise OD risk).
	var/mob/living/carbon/human/HA = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/HB = allocate(/mob/living/carbon/human)
	var/datum/affliction/cellulitis/CA = _spawn_affliction_on(HA, BP_TORSO, /datum/affliction/cellulitis)
	var/datum/affliction/cellulitis/CB = _spawn_affliction_on(HB, BP_TORSO, /datum/affliction/cellulitis)
	CA.severity = 50
	CB.severity = 50
	HA.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 40)  // at cap
	HB.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 100) // way over cap

	CA.tick()
	CB.tick()

	var/dA = 50 - CA.severity
	var/dB = 50 - CB.severity
	TEST_ASSERT_EQUAL(dA, dB, "40u and 100u should heal equally (cap engaged) — got [dA] vs [dB]")


// --- cascade scaling: 2× threshold guarantees spawn -----------------

/datum/unit_test/dq_cascade_chance_scales_with_damage

/datum/unit_test/dq_cascade_chance_scales_with_damage/Run()
	var/datum/affliction_trigger_outcome/o = new()
	o.chance = 40
	o.threshold = 10

	// At the threshold: authored chance.
	TEST_ASSERT_EQUAL(dq_scaled_cascade_chance(o, 10), 40, "damage = threshold should use base chance")
	// 1.5×: 60%.
	TEST_ASSERT_EQUAL(dq_scaled_cascade_chance(o, 15), 60, "1.5× threshold should scale linearly")
	// 2× and above: guaranteed.
	TEST_ASSERT_EQUAL(dq_scaled_cascade_chance(o, 20), 100, "2× threshold should guarantee the spawn")
	TEST_ASSERT_EQUAL(dq_scaled_cascade_chance(o, 100), 100, "10× threshold should also guarantee")
	// Below threshold: scales below base.
	TEST_ASSERT_EQUAL(dq_scaled_cascade_chance(o, 5), 20, "half-threshold should halve chance")
	// No threshold declared: pass-through.
	o.threshold = null
	TEST_ASSERT_EQUAL(dq_scaled_cascade_chance(o, 50), 40, "no threshold = use raw chance")
	qdel(o)


// --- Brain swelling: past the salvage threshold damage rises despite alkysine -

/datum/unit_test/dq_brain_decay_past_threshold

/datum/unit_test/dq_brain_decay_past_threshold/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT_NOTNULL(B, "no brain organ")

	// Push the brain to 70% damage (above the 60% salvage threshold).
	dq_test_set_organ_damage(B, B.max_damage * 0.7)
	var/before = B.damage

	// No neural repair: damage should rise.
	for(var/i in 1 to 5)
		dq_test_tick_organ(B)
	TEST_ASSERT(B.damage > before, "above-threshold brain should swell without treatment ([before] -> [B.damage])")
	var/no_chem_growth = B.damage - before

	// Reset and try again with alkysine: should still rise, but slower.
	dq_test_set_organ_damage(B, B.max_damage * 0.7)
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 10)
	for(var/i in 1 to 5)
		dq_test_tick_organ(B)
	var/with_chem_growth = B.damage - (B.max_damage * 0.7)
	TEST_ASSERT(with_chem_growth > 0, "alkysine should NOT reverse swelling above threshold (growth=[with_chem_growth])")
	TEST_ASSERT(with_chem_growth < no_chem_growth, "alkysine should slow swelling (no_chem=[no_chem_growth], with_chem=[with_chem_growth])")


// --- Brain below the salvage threshold doesn't swell ------------------

/datum/unit_test/dq_brain_stable_mid_range

/datum/unit_test/dq_brain_stable_mid_range/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]

	// 40% damage: above natural regeneration, below swelling.
	dq_test_set_organ_damage(B, B.max_damage * 0.4)
	var/before = B.damage

	for(var/i in 1 to 10)
		dq_test_tick_organ(B)
	TEST_ASSERT(B.damage <= before, "mid-range brain (20-60%) should not swell ([before] -> [B.damage])")
	TEST_ASSERT_NULL(B.find_lesion(/datum/affliction/lesion/ischemic_injury), "mid-range brain should not grow secondary injury")


// --- Brain below 20% heals naturally (TREAT_REGENERATION) -------------

/datum/unit_test/dq_brain_natural_heal_below_floor

/datum/unit_test/dq_brain_natural_heal_below_floor/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]

	// 15% damage: below the 20% natural-heal ceiling.
	dq_test_set_organ_damage(B, B.max_damage * 0.15)
	var/before = B.damage
	TEST_ASSERT(H.body.treatment_levels()?[TREAT_REGENERATION], "a fed, living human should regenerate")

	for(var/i in 1 to 10)
		dq_test_tick_organ(B)
	TEST_ASSERT(B.damage < before, "below-20% brain should heal naturally ([before] -> [B.damage])")


// --- Natural heal stops at 0 (no negative damage) --------------------

/datum/unit_test/dq_brain_natural_heal_floors_at_zero

/datum/unit_test/dq_brain_natural_heal_floors_at_zero/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	dq_test_set_organ_damage(B, 0.5)  // tiny damage, less than one heal tick

	for(var/i in 1 to 10)
		dq_test_tick_organ(B)
	TEST_ASSERT(B.damage >= 0, "natural heal should floor at 0, not go negative (got [B.damage])")


// --- organ lifecycle: amputating a limb detaches conditions ----------
// The condition stays attached to the limb object (so it can return on
// reattach) but its `owner` is nulled so the now-detached patient stops
// processing it.

/datum/unit_test/dq_organ_lifecycle_amputation_detaches_conditions

/datum/unit_test/dq_organ_lifecycle_amputation_detaches_conditions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/tendon_severed/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/tendon_severed)
	TEST_ASSERT_NOTNULL(C, "tendon_severed didn't spawn")

	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT_NOTNULL(arm, "no left arm")
	arm.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)

	// The patient no longer has this condition (we walk the patient's
	// remaining organs; the severed arm isn't one of them).
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/tendon_severed))
			TEST_FAIL("tendon_severed should detach from patient when limb is severed")

	// The condition still exists on the severed limb with no owner.
	TEST_ASSERT(!QDELETED(C), "condition should NOT be qdeleted — it rides along with the limb")
	TEST_ASSERT_NULL(C.owner, "condition owner should be nulled after sever")
	TEST_ASSERT_EQUAL(C.location, arm, "condition should still be attached to the severed arm")


// --- organ lifecycle: reattaching a limb reseats conditions ----------

/datum/unit_test/dq_organ_lifecycle_reattach_restores_conditions

/datum/unit_test/dq_organ_lifecycle_reattach_restores_conditions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/tendon_severed/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/tendon_severed)
	TEST_ASSERT_NOTNULL(C, "tendon_severed didn't spawn")

	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
	TEST_ASSERT_NULL(C.owner, "after sever, condition owner should be null")

	// Reattach: replaced() should re-anchor the condition to the patient.
	arm.replaced(H)
	TEST_ASSERT_EQUAL(C.owner, H, "after reattach, condition owner should be the patient again")

	// And the patient should once again see this condition in their roster.
	var/found = FALSE
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/tendon_severed))
			found = TRUE
			break
	TEST_ASSERT(found, "reattached limb should restore its condition to the patient")


// --- organ lifecycle: deleting an organ doesn't leak its afflictions ---

/datum/unit_test/dq_organ_lifecycle_destroy_qdels_conditions

/datum/unit_test/dq_organ_lifecycle_destroy_qdels_conditions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/compartment_syndrome/C = _spawn_affliction_on(H, BP_L_LEG, /datum/affliction/compartment_syndrome)
	TEST_ASSERT_NOTNULL(C, "compartment_syndrome didn't spawn")

	var/obj/item/organ/external/leg = H.get_organ(BP_L_LEG)
	qdel(leg)

	TEST_ASSERT(QDELETED(C), "condition should be qdeleted when its host organ is destroyed")


// --- audit: established brain_damage has NO surgical cure ------------
// The whole point of the brain-damage-as-terminal design — if anyone
// adds brain_damage to a surgery's `treats` list this test catches it.

/datum/unit_test/dq_brain_damage_has_no_surgery

/datum/unit_test/dq_brain_damage_has_no_surgery/Run()
	for(var/T in subtypesof(/datum/dq_surgery))
		var/datum/dq_surgery/sg = new T()
		if(/datum/affliction/brain_damage in sg.treats)
			TEST_FAIL("[T] declares it treats brain_damage; that condition is intentionally terminal — no surgery can repair established brain tissue damage")
		qdel(sg)

#endif
