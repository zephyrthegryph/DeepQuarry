// Unit tests for body continuity: what happens to afflictions, lesions,
// wounds, organs and the /datum/body itself across resleeving, cryo despawn,
// admin rejuvenate, species change, transformation and defibrillation.
//
// Design intent (doc/body_architecture.md):
// - A resleeve gives a fresh body; nothing but memory is lost. Afflictions
//   belong to the body, not the mind, so they never follow the mind.
// - Brain death (brain at 100% damage) cannot be defibrillated; it needs a
//   resleeve.
// - Every affliction on a body points at that body and its owner, and a
//   located affliction sits on a part the body still has.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Test helper: the first continuity fault on `L`'s body, or null when the
/// body is consistent. Checks body.owner, every affliction's body/owner, and
/// that located afflictions sit on live parts the mob still has.
/proc/dq_test_body_continuity_fault(mob/living/L)
	if(!L.body)
		return "[L] has no body"
	if(QDELETED(L.body))
		return "[L]'s body is deleted"
	if(L.body.owner != L)
		return "[L]'s body is owned by [L.body.owner]"
	var/list/parts
	if(ishuman(L))
		var/mob/living/carbon/human/H = L
		parts = H.organs | H.internal_organs
	for(var/datum/affliction/A as anything in L.body.afflictions)
		if(QDELETED(A))
			return "[A.type] is deleted but still listed"
		if(A.body != L.body)
			return "[A.type] points at another body"
		if(A.owner != L)
			return "[A.type] points at owner [A.owner]"
		if(!A.location)
			continue
		if(isdatum(A.location) && QDELETED(A.location))
			return "[A.type] sits on a deleted part"
		if(parts && istype(A.location, /obj/item/organ) && !(A.location in parts))
			return "[A.type] sits on [A.location], which [L] no longer has"
	return null

/// Test helper: give `H` a limb wound, a located organ lesion and a systemic
/// affliction. Returns them as a list (wound, lesion, systemic).
/proc/dq_test_injure_everywhere(mob/living/carbon/human/H)
	H.injure(INJURY_CUT, 20, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	H.injure(INJURY_BLUNT, 20, liver, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.body.afflict(/datum/affliction/toxic_poisoning, null, 40)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/list/wounds = arm.afflictions_here()
	var/list/lesions = liver.afflictions_here()
	return list(length(wounds) ? wounds[1] : null, length(lesions) ? lesions[1] : null, H.body.find_affliction(/datum/affliction/toxic_poisoning))


// --- Rejuvenate / fully_heal ----------------------------------------------------------

/// fully_heal() clears every affliction (located and systemic), deletes them
/// and leaves the body intact and owned.
/datum/unit_test/dq_continuity_fully_heal

/datum/unit_test/dq_continuity_fully_heal/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/body/B = H.body
	var/list/harm = dq_test_injure_everywhere(H)
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT_NOTNULL(A, "setup should create a wound, a lesion and a systemic affliction")

	H.fully_heal()
	TEST_ASSERT_EQUAL(H.body, B, "fully_heal should keep the same body")
	TEST_ASSERT_EQUAL(length(B.afflictions), 0, "fully_heal should clear every affliction")
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT(QDELETED(A), "[A.type] should be deleted by fully_heal")
		TEST_ASSERT_NULL(A.body, "[A.type] should not point at the body after fully_heal")
		TEST_ASSERT_NULL(A.owner, "[A.type] should not point at the mob after fully_heal")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after fully_heal: [fault]")

/// Admin rejuvenate revives a dead human with a clean, owned body.
/datum/unit_test/dq_continuity_rejuvenate_dead

/datum/unit_test/dq_continuity_rejuvenate_dead/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/harm = dq_test_injure_everywhere(H)
	H.death()
	TEST_ASSERT_EQUAL(H.stat, DEAD, "setup: the patient should be dead")

	H.rejuvenate()
	TEST_ASSERT(H.stat != DEAD, "rejuvenate should revive")
	TEST_ASSERT_EQUAL(length(H.body.afflictions), 0, "rejuvenate should leave no afflictions")
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT(QDELETED(A), "[A.type] should be deleted by rejuvenate")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after rejuvenate: [fault]")

/// revive() rebuilds the organs (species.create_organs): afflictions on the
/// replaced organs die with them and nothing points at the old organs.
/datum/unit_test/dq_continuity_revive_rebuilds_organs

/datum/unit_test/dq_continuity_revive_rebuilds_organs/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/list/harm = dq_test_injure_everywhere(H)
	var/obj/item/organ/old_liver = H.internal_organs_by_name[O_LIVER]
	var/obj/item/organ/old_arm = H.get_organ(BP_L_ARM)
	H.death()

	H.revive()
	TEST_ASSERT(QDELETED(old_liver), "revive should replace the liver")
	TEST_ASSERT(QDELETED(old_arm), "revive should replace the arm")
	TEST_ASSERT_EQUAL(length(H.body.afflictions), 0, "revive should leave no afflictions")
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT(QDELETED(A), "[A.type] should be deleted by revive")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after revive: [fault]")

/// Robot rejuvenate clears every located load and rebuilds destroyed parts.
/datum/unit_test/dq_continuity_robot_rejuvenate

/datum/unit_test/dq_continuity_robot_rejuvenate/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)
	var/datum/body/B = R.body
	R.injure(INJURY_BLUNT, 40, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	R.injure(INJURY_BURN, 40, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/list/harm = B.afflictions?.Copy()
	TEST_ASSERT(length(harm), "setup: injuring a cyborg should create afflictions")

	R.rejuvenate()
	TEST_ASSERT_EQUAL(R.body, B, "rejuvenate should keep the robot's body")
	TEST_ASSERT_EQUAL(length(B.afflictions), 0, "robot rejuvenate should clear every affliction")
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT(QDELETED(A), "[A.type] should be deleted by robot rejuvenate")
	for(var/slot in R.components)
		var/datum/robot_component/C = LAZYACCESS(R.components, slot)
		TEST_ASSERT_EQUAL(length(B.afflictions_at(C)), 0, "component [slot] should carry nothing after rejuvenate")
	var/fault = dq_test_body_continuity_fault(R)
	TEST_ASSERT_NULL(fault, "robot body after rejuvenate: [fault]")


// --- Resleeving ------------------------------------------------------------------------

/// A body printed from a record of an injured person is a fresh body: new
/// body datum, owned by the new mob, with none of the original's afflictions.
/datum/unit_test/dq_continuity_resleeve_printed_body_is_fresh

/datum/unit_test/dq_continuity_resleeve_printed_body_is_fresh/Run()
	var/mob/living/carbon/human/original = allocate(/mob/living/carbon/human)
	var/list/harm = dq_test_injure_everywhere(original)
	var/datum/transhuman/body_record/BR = new(original)

	var/mob/living/carbon/human/sleeve = BR.produce_human_mob(run_loc_floor_bottom_left, FALSE, TRUE, "sleeve")
	TEST_ASSERT_NOTNULL(sleeve, "the record should print a body")
	TEST_ASSERT(sleeve.body != original.body, "a printed body gets its own body datum")
	TEST_ASSERT_EQUAL(length(sleeve.body.afflictions), 0, "a printed body carries none of the original's afflictions")
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT_EQUAL(A.owner, original, "[A.type] should stay with the original body")
	var/fault = dq_test_body_continuity_fault(sleeve)
	TEST_ASSERT_NULL(fault, "printed body: [fault]")
	fault = dq_test_body_continuity_fault(original)
	TEST_ASSERT_NULL(fault, "original body after printing: [fault]")

	qdel(sleeve)
	qdel(BR)

/// A printed protean sleeve gets the nanoform body plan.
/datum/unit_test/dq_continuity_resleeve_protean_plan

/datum/unit_test/dq_continuity_resleeve_protean_plan/Run()
	var/mob/living/carbon/human/original = allocate(/mob/living/carbon/human/protean)
	var/datum/transhuman/body_record/BR = new(original)
	var/mob/living/carbon/human/sleeve = BR.produce_human_mob(run_loc_floor_bottom_left, TRUE, TRUE, "sleeve")
	TEST_ASSERT(istype(sleeve.body, /datum/body/humanoid/nanoform), "a printed protean should have the nanoform body plan, got [sleeve.body?.type]")
	var/fault = dq_test_body_continuity_fault(sleeve)
	TEST_ASSERT_NULL(fault, "printed protean body: [fault]")
	qdel(sleeve)
	qdel(BR)

/// Re-growing a body in place from its record (the xenochimera revive path)
/// rebuilds the organs with a clean slate: nothing points at the old organs.
/datum/unit_test/dq_continuity_resleeve_regrow_in_place

/datum/unit_test/dq_continuity_resleeve_regrow_in_place/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/transhuman/body_record/BR = new(H)
	var/list/harm = dq_test_injure_everywhere(H)
	var/obj/item/organ/old_liver = H.internal_organs_by_name[O_LIVER]
	H.death()

	BR.revive_xenochimera(H, TRUE, FALSE)
	TEST_ASSERT(H.stat != DEAD, "regrowing from the record should revive")
	TEST_ASSERT(QDELETED(old_liver), "regrowing should replace the organs")
	TEST_ASSERT_EQUAL(length(H.body.afflictions), 0, "regrowing should leave no afflictions")
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT(QDELETED(A), "[A.type] should be deleted by regrowing")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "regrown body: [fault]")
	qdel(BR)


// --- Cryo -------------------------------------------------------------------------------

/// Cryo despawn deletes the mob, its body and every affliction, and nothing
/// is left pointing at the deleted mob.
/datum/unit_test/dq_continuity_cryo_despawn

/datum/unit_test/dq_continuity_cryo_despawn/Run()
	var/obj/machinery/cryopod/pod = allocate(/obj/machinery/cryopod)
	var/mob/living/carbon/human/H = new(pod)
	var/datum/body/B = H.body
	var/list/harm = dq_test_injure_everywhere(H)
	var/obj/item/organ/liver = H.internal_organs_by_name[O_LIVER]
	pod.set_occupant(H)

	pod.despawn_occupant(H)
	TEST_ASSERT(QDELETED(H), "despawn should delete the occupant")
	TEST_ASSERT(QDELETED(B), "despawn should delete the occupant's body")
	TEST_ASSERT_NULL(B.owner, "the deleted body should not point at the mob")
	TEST_ASSERT_EQUAL(length(B.afflictions), 0, "the deleted body should hold no afflictions")
	TEST_ASSERT(QDELETED(liver), "despawn should delete the organs")
	for(var/datum/affliction/A as anything in harm)
		TEST_ASSERT(QDELETED(A), "[A.type] should be deleted with the body")
		TEST_ASSERT_NULL(A.body, "[A.type] should not point at the deleted body")
		TEST_ASSERT_NULL(A.owner, "[A.type] should not point at the deleted mob")
		TEST_ASSERT_NULL(A.location, "[A.type] should not point at a deleted part")


// --- Species change ---------------------------------------------------------------------

/// set_species replaces the organs: located afflictions die with the old
/// organs; the body datum and its systemic afflictions stay with the mob.
/datum/unit_test/dq_continuity_set_species

/datum/unit_test/dq_continuity_set_species/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/body/B = H.body
	var/list/harm = dq_test_injure_everywhere(H)
	var/datum/affliction/wound = harm[1]
	var/datum/affliction/lesion = harm[2]
	var/datum/affliction/systemic = harm[3]

	H.set_species(SPECIES_UNATHI)
	TEST_ASSERT_EQUAL(H.body, B, "a species change within one body plan keeps the body")
	TEST_ASSERT(QDELETED(wound), "a wound on a replaced limb should be deleted")
	TEST_ASSERT(QDELETED(lesion), "a lesion on a replaced organ should be deleted")
	TEST_ASSERT(!QDELETED(systemic) && systemic.body == B, "a systemic affliction belongs to the body and stays")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after set_species: [fault]")

/// Becoming a protean swaps to the nanoform body plan; leaving swaps back.
/// Needs the body-plan swap in set_species (see the lead's core change list).
/datum/unit_test/dq_continuity_set_species_swaps_plan

/datum/unit_test/dq_continuity_set_species_swaps_plan/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/body/old_body = H.body
	H.body.afflict(/datum/affliction/toxic_poisoning, null, 40)

	H.set_species(SPECIES_PROTEAN)
	TEST_ASSERT(istype(H.body, /datum/body/humanoid/nanoform), "becoming a protean should give the nanoform plan, got [H.body?.type]")
	TEST_ASSERT(QDELETED(old_body), "the replaced body should be deleted")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after becoming a protean: [fault]")

	H.set_species(SPECIES_HUMAN)
	TEST_ASSERT_EQUAL(H.body.type, /datum/body/humanoid, "leaving the protean species should restore the humanoid plan")
	fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after leaving the protean species: [fault]")


// --- Transformation ---------------------------------------------------------------------

/// transform_into_other_human copies appearance only: the target's
/// afflictions don't come along and the transformer keeps its own.
/datum/unit_test/dq_continuity_transform_into_other_human

/datum/unit_test/dq_continuity_transform_into_other_human/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/datum/body/B = H.body
	var/datum/affliction/mine = H.body.afflict(/datum/affliction/toxic_poisoning, null, 20)
	dq_test_injure_everywhere(victim)
	var/victim_count = length(victim.body.afflictions)

	H.transform_into_other_human(victim, FALSE)
	TEST_ASSERT_EQUAL(H.body, B, "transforming keeps the transformer's body")
	TEST_ASSERT_EQUAL(length(H.body.afflictions), 1, "transforming should not copy the target's afflictions")
	TEST_ASSERT(!QDELETED(mine) && mine.owner == H, "the transformer keeps its own afflictions")
	TEST_ASSERT_EQUAL(length(victim.body.afflictions), victim_count, "the target keeps its afflictions")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "transformer body: [fault]")
	fault = dq_test_body_continuity_fault(victim)
	TEST_ASSERT_NULL(fault, "target body: [fault]")

/// Converting a limb to a prosthetic (the protean copy-form path) must not
/// leave organic wounds on a now-synthetic limb.
/// Needs organ robotize() to shed biology-mismatched afflictions (core change).
/datum/unit_test/dq_continuity_robotize_sheds_organic_afflictions

/datum/unit_test/dq_continuity_robotize_sheds_organic_afflictions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_CUT, 20, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT(length(arm.afflictions_here()), "setup: the arm should be wounded")

	arm.robotize()
	for(var/datum/affliction/A as anything in arm.afflictions_here())
		TEST_ASSERT(A.biology & H.body.biology_of(arm), "[A.type] (biology [A.biology]) should not survive on a limb of biology [H.body.biology_of(arm)]")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after robotize: [fault]")


// --- Defibrillation ---------------------------------------------------------------------

/// Defibrillation revives the same body: nothing is healed away, and every
/// affliction still points at the same body and owner.
/datum/unit_test/dq_continuity_defib_keeps_body

/datum/unit_test/dq_continuity_defib_keeps_body/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/shockpaddles/paddles = allocate(/obj/item/shockpaddles)
	var/datum/body/B = H.body
	var/datum/affliction/systemic = H.body.afflict(/datum/affliction/toxic_poisoning, null, 20)
	H.death()

	paddles.make_alive(H)
	TEST_ASSERT(H.stat != DEAD, "make_alive should revive")
	TEST_ASSERT_EQUAL(H.body, B, "defibrillation keeps the same body")
	TEST_ASSERT(!QDELETED(systemic) && systemic.body == B, "defibrillation does not heal afflictions")
	var/fault = dq_test_body_continuity_fault(H)
	TEST_ASSERT_NULL(fault, "body after defibrillation: [fault]")

/// A brain at 100% damage is brain death: the defibrillator refuses, and only
/// a resleeve brings the person back.
/datum/unit_test/dq_continuity_brain_death_blocks_defib

/datum/unit_test/dq_continuity_brain_death_blocks_defib/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/shockpaddles/paddles = allocate(/obj/item/shockpaddles)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT_NOTNULL(brain, "no brain")
	brain.defib_timer = (CONFIG_GET(number/defib_timer) MINUTES) / 2 // freshly dead
	H.death()
	TEST_ASSERT_NULL(paddles.can_revive(H), "setup: an undamaged, freshly dead patient should be revivable")

	dq_test_set_organ_damage(brain, brain.max_damage)
	TEST_ASSERT_NOTNULL(paddles.can_revive(H), "a brain at 100% damage should block defibrillation")

#endif
