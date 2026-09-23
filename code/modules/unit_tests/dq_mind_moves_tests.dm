// Unit tests for the follow-ups to the brain/mind refactor:
//  - a brain-dead brain (is_brain_dead()) can't be repaired by surgery, mend(),
//    treatment tags or drugs; brain damage short of that still can;
//  - dominate prey / dominate predator and mob transforms move players through
//    their minds, and the mind's identity comes back intact;
//  - a sleeve printed from a body record gets the character (flavour text,
//    languages, persistent traits) from the mind that fills it, never from
//    the record.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

// --- Brain death is not repairable -----------------------------------------------------

/// A brain at 100% damage refuses every repair path: mend(), continuous drug
/// treatment, operative repair and the organ repair surgical step.
/datum/unit_test/dq_mind_dead_brain_refuses_repair

/datum/unit_test/dq_mind_dead_brain_refuses_repair/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	dq_test_injure_organ(H, brain, brain.max_damage, /datum/affliction/lesion/contusion)
	TEST_ASSERT(brain.is_brain_dead(), "setup: a brain at 100% is brain dead")
	var/datum/affliction/lesion/L = brain.find_lesion(/datum/affliction/lesion/contusion)
	TEST_ASSERT_NOTNULL(L, "setup: the brain carries a contusion")

	TEST_ASSERT_EQUAL(H.mend(TREAT_NEURAL_REPAIR, 50, brain), 0, "neural repair can't mend a dead brain")
	TEST_ASSERT_EQUAL(L.receive_tagged_treatment(TREAT_NEURAL_REPAIR, 50, TRUE), 0, "a neural repair drug (alkysine) can't treat a dead brain")
	TEST_ASSERT_EQUAL(H.surgically_repair_organ(brain), 0, "operative repair can't repair a dead brain")
	TEST_ASSERT_EQUAL(brain.damage, brain.max_damage, "the dead brain keeps its damage")

	_surgery_perform(/datum/surgical_step/treat/organ/suture, surgeon, H, BP_HEAD, null, brain)
	TEST_ASSERT(brain.is_brain_dead(), "organ repair surgery doesn't revive a dead brain")
	TEST_ASSERT_EQUAL(brain.damage, brain.max_damage, "organ repair surgery doesn't repair a dead brain")

/// A dead brain organ (ORGAN_DEAD) below 100% damage is brain dead too: its
/// status can't be cleared and its lesions can't be repaired.
/datum/unit_test/dq_mind_dead_brain_organ_stays_dead

/datum/unit_test/dq_mind_dead_brain_organ_stays_dead/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	dq_test_injure_organ(H, brain, 30, /datum/affliction/lesion/contusion)
	brain.status |= ORGAN_DEAD
	TEST_ASSERT(brain.is_brain_dead(), "setup: a dead brain organ is brain dead")

	TEST_ASSERT(!brain.restore_status(), "a dead brain's status can't be restored")
	TEST_ASSERT(brain.status & ORGAN_DEAD, "the brain stays dead")
	TEST_ASSERT_EQUAL(H.mend(TREAT_NEURAL_REPAIR, 50, brain), 0, "a dead brain organ can't be mended")

	_surgery_perform(/datum/surgical_step/treat/organ/suture, surgeon, H, BP_HEAD, null, brain)
	TEST_ASSERT(brain.status & ORGAN_DEAD, "surgery doesn't clear a dead brain's status")
	TEST_ASSERT_EQUAL(brain.damage, 30, "surgery doesn't repair a dead brain organ")

/// Brain damage short of brain death stays repairable: neural repair and the
/// organ repair surgical step both still work.
/datum/unit_test/dq_mind_damaged_brain_still_repairable

/datum/unit_test/dq_mind_damaged_brain_still_repairable/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	dq_test_injure_organ(H, brain, brain.max_damage - 1, /datum/affliction/lesion/contusion)
	TEST_ASSERT(!brain.is_brain_dead(), "setup: a brain at 99% is not brain dead")

	TEST_ASSERT(H.mend(TREAT_NEURAL_REPAIR, 5, brain) > 0, "neural repair mends a living brain")
	TEST_ASSERT(brain.damage < brain.max_damage - 1, "the living brain heals")

	var/before = brain.damage
	_surgery_perform(/datum/surgical_step/treat/organ/suture, surgeon, H, BP_HEAD, null, brain)
	TEST_ASSERT(brain.damage < before, "organ repair surgery repairs a living brain")


// --- Dominate prey / predator: minds move, identities come back ------------------------

/// Dominate prey: the prey's mind moves into a back seat inside the predator
/// and keeps its own identity; returning puts it back in its body.
/datum/unit_test/dq_mind_dominate_prey_roundtrip

/datum/unit_test/dq_mind_dominate_prey_roundtrip/Run()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human)
	var/datum/mind/pred_mind = dq_test_give_mind(pred, "Dominating Pred")
	var/datum/mind/prey_mind = dq_test_give_mind(prey, "Gathered Prey")
	var/datum/character_identity/pred_identity = pred_mind.identity
	var/datum/character_identity/prey_identity = prey_mind.identity
	var/prey_name = prey_identity.real_name

	var/mob/living/dominated_brain/seat = pred.gather_prey_mind(prey)
	TEST_ASSERT_NOTNULL(seat, "dominate prey makes a back seat")
	TEST_ASSERT_EQUAL(seat.mind, prey_mind, "the prey's mind is in the back seat")
	TEST_ASSERT_NULL(prey.mind, "the prey's body no longer holds the mind")
	TEST_ASSERT_EQUAL(prey_mind.identity, prey_identity, "the prey's mind keeps its identity")
	TEST_ASSERT_EQUAL(seat.identity, prey_identity, "the back seat wears the prey's identity")
	TEST_ASSERT_EQUAL(prey_identity.dna, prey.dna, "the prey's identity still references its own body's DNA")
	TEST_ASSERT_EQUAL(pred.mind, pred_mind, "the predator keeps its mind")
	TEST_ASSERT_EQUAL(pred.identity, pred_identity, "the predator keeps its identity")

	seat.return_to_body()
	TEST_ASSERT_EQUAL(prey.mind, prey_mind, "the prey's mind is back in its body")
	TEST_ASSERT_EQUAL(prey.identity, prey_identity, "the prey's body reads its identity again")
	TEST_ASSERT_EQUAL(prey_identity.real_name, prey_name, "the prey's name survived")
	TEST_ASSERT_EQUAL(prey_identity.ooc_notes, "notes of Gathered Prey", "the prey's OOC notes survived")
	TEST_ASSERT(QDELETED(seat), "the empty back seat is deleted")

/// Dominate predator: the prey's mind takes the predator's body wearing its
/// own identity, the predator's mind waits in a back seat; restoring control
/// puts both minds back and each body binds its own character again.
/datum/unit_test/dq_mind_dominate_predator_roundtrip

/datum/unit_test/dq_mind_dominate_predator_roundtrip/Run()
	var/mob/living/carbon/human/pred = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/prey = allocate(/mob/living/carbon/human)
	var/obj/item/holder = allocate(/obj/item)
	var/datum/mind/pred_mind = dq_test_give_mind(pred, "Dominated Pred")
	var/datum/mind/prey_mind = dq_test_give_mind(prey, "Dominant Prey")
	var/datum/character_identity/pred_identity = pred_mind.identity
	var/datum/character_identity/prey_identity = prey_mind.identity
	var/list/pred_languages = pred.languages
	holder.forceMove(pred)
	prey.forceMove(holder) // "inside" the predator, as in a belly

	var/mob/living/dominated_brain/seat = take_over_predator(prey, pred, "unit test")
	TEST_ASSERT_EQUAL(pred.mind, prey_mind, "the prey's mind controls the predator's body")
	TEST_ASSERT_EQUAL(pred.identity, prey_identity, "the predator's body wears the prey's identity")
	TEST_ASSERT_EQUAL(seat.mind, pred_mind, "the predator's mind waits in the back seat")
	TEST_ASSERT_EQUAL(seat.identity, pred_identity, "the back seat wears the predator's identity")
	TEST_ASSERT_EQUAL(prey_identity.dna, prey.dna, "sharing doesn't point the prey's identity at the predator's DNA")
	TEST_ASSERT_EQUAL(pred_identity.dna, pred.dna, "the predator's identity still references its own DNA")
	TEST_ASSERT_EQUAL(pred.languages, pred_languages, "the controlled body keeps its own language list")
	TEST_ASSERT(pred.prey_controlled, "the predator is marked as controlled")

	seat.restore_control(FALSE)
	TEST_ASSERT_EQUAL(pred.mind, pred_mind, "the predator's mind is back in its body")
	TEST_ASSERT_EQUAL(pred.identity, pred_identity, "the predator reads its own identity again")
	TEST_ASSERT_EQUAL(prey.mind, prey_mind, "the prey's mind is back in its body")
	TEST_ASSERT_EQUAL(prey.identity, prey_identity, "the prey reads its own identity again")
	TEST_ASSERT_EQUAL(prey_identity.ooc_notes, "notes of Dominant Prey", "the prey's OOC notes survived")
	TEST_ASSERT(!pred.prey_controlled, "the predator is no longer controlled")
	TEST_ASSERT(QDELETED(seat), "the back seat is deleted")


// --- Mob transforms: the mind wears the form, then goes home ----------------------------

/// A player transformed into a simple mob moves by mind, wears their own
/// identity in the form, and reverting puts the mind back in the body.
/datum/unit_test/dq_mind_mob_transform_roundtrip

/datum/unit_test/dq_mind_mob_transform_roundtrip/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/mind/M = dq_test_give_mind(H, "Shapeshifter")
	var/datum/character_identity/I = M.identity
	var/name_before = I.real_name
	var/list/languages_before = I.languages
	// The form appears (and reverts) on a turf; the test map may lack the run landmark.
	H.forceMove(run_loc_floor_bottom_left || locate(round(world.maxx / 2), round(world.maxy / 2), 1))

	var/mob/living/form = H.transform_into_mob(/mob/living/simple_mob/animal/passive/mouse, TRUE)
	TEST_ASSERT_NOTNULL(form, "the transform should produce a form")
	TEST_ASSERT_EQUAL(form.mind, M, "the mind moved into the form")
	TEST_ASSERT_NULL(H.mind, "the body no longer holds the mind")
	TEST_ASSERT_EQUAL(form.identity, I, "the form wears the character's identity")
	TEST_ASSERT_EQUAL(M.identity, I, "the mind keeps its identity")
	TEST_ASSERT_EQUAL(I.dna, H.dna, "the identity still references the original body's DNA")
	TEST_ASSERT_EQUAL(form.tf_mob_holder, H, "the form holds the original body")

	form.revert_mob_tf()
	TEST_ASSERT_EQUAL(H.mind, M, "reverting puts the mind back in the body")
	TEST_ASSERT_EQUAL(H.identity, I, "the body reads the character's identity again")
	TEST_ASSERT_EQUAL(I.real_name, name_before, "the character's name survived")
	TEST_ASSERT_EQUAL(I.languages, languages_before, "the character's languages survived")
	TEST_ASSERT_EQUAL(I.ooc_notes, "notes of Shapeshifter", "the character's OOC notes survived")
	TEST_ASSERT(QDELETED(form), "the form is deleted after reverting")


// --- A printed sleeve gets the character from the mind ----------------------------------

/// A body record carries only the body. A sleeve printed from someone else's
/// record and then filled with a mind speaks the mind's languages, shows the
/// mind's flavour text and carries the mind's persistent traits.
/datum/unit_test/dq_mind_sleeve_character_from_mind

/datum/unit_test/dq_mind_sleeve_character_from_mind/Run()
	var/mob/living/carbon/human/donor = allocate(/mob/living/carbon/human)
	dq_test_give_mind(donor, "Body Donor")
	donor.flavor_texts["general"] = "donor flavour"

	var/mob/living/carbon/human/traveller = allocate(/mob/living/carbon/human)
	var/datum/mind/M = dq_test_give_mind(traveller, "Traveller")
	var/datum/character_identity/I = M.identity
	I.flavor_texts["general"] = "traveller flavour"
	traveller.add_language(LANGUAGE_SIGN)
	traveller.add_modifier(/datum/modifier/no_borg)
	TEST_ASSERT(I.has_genetic_modifier(/datum/modifier/no_borg), "setup: the persistent trait is the character's")
	var/name_before = I.real_name

	var/datum/transhuman/body_record/BR = new(donor)
	var/mob/living/carbon/human/sleeve = BR.produce_human_mob(run_loc_floor_bottom_left, FALSE, TRUE, "sleeve")
	TEST_ASSERT_NOTEQUAL(LAZYACCESS(sleeve.flavor_texts, "general"), "donor flavour", "the body record carries no flavour text")
	TEST_ASSERT(!sleeve.has_modifier_of_type(/datum/modifier/no_borg), "an empty sleeve has no persistent traits")

	TEST_ASSERT(transfer_mind(M, sleeve, "unit test resleeve"), "the mind should move into the sleeve")
	TEST_ASSERT_EQUAL(sleeve.identity, I, "the sleeve reads the mind's identity")
	TEST_ASSERT_EQUAL(sleeve.flavor_texts, I.flavor_texts, "the sleeve shows the character's flavour text list")
	TEST_ASSERT_EQUAL(LAZYACCESS(sleeve.flavor_texts, "general"), "traveller flavour", "the flavour text is the mind's")
	TEST_ASSERT_EQUAL(sleeve.languages, I.languages, "the sleeve speaks the character's language list")
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_SIGN] in sleeve.languages, "the sleeve speaks the mind's languages")
	TEST_ASSERT(sleeve.has_modifier_of_type(/datum/modifier/no_borg), "the mind's persistent trait reaches the sleeve")
	TEST_ASSERT_EQUAL(I.real_name, name_before, "the character keeps its name")
	TEST_ASSERT_EQUAL(sleeve.identity.ooc_notes, "notes of Traveller", "OOC notes follow the mind")
	qdel(sleeve)
	qdel(BR)

#endif
