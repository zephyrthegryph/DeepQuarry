// Unit tests for the brain/mind architecture: character identity owned by the
// mind, one mind-hosting interface (brain organ, MMI, posibrain, borg), the
// brain view mob as a thin view on its host organ, and the single brain-death
// decision (/obj/item/organ/internal/brain/proc/is_brain_dead()).
//
// "Without copies" is asserted by reference equality: every holder of the
// character reads the SAME /datum/character_identity, the view reads the same
// DNA datum and language list, and no field is duplicated anywhere.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Test helper: give `L` a fresh mind named `name` with some OOC notes.
/proc/dq_test_give_mind(mob/living/L, name)
	var/datum/mind/M = new /datum/mind("dq_mind_test_[name]")
	M.name = name
	M.transfer_to(L)
	M.identity.ooc_notes = "notes of [name]"
	M.identity.ooc_notes_likes = "likes of [name]"
	return M

/// Test helper: take `H`'s brain out. Returns the organ.
/proc/dq_test_remove_brain(mob/living/carbon/human/H)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	brain.removed()
	return brain

/// Test helper: a human with an empty brain slot, ready for a transplant.
/proc/dq_test_brainless_recipient(datum/unit_test/test)
	var/mob/living/carbon/human/H = test.allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/old = H.internal_organs_by_name[O_BRAIN]
	old.removed()
	qdel(old)
	return H

/// Test helper: the first stale-reference fault after a mind move, or null.
/// `M` must be in `holder`; the view (if any) must be the only other mob that
/// ever held it and must not claim it.
/proc/dq_test_mind_fault(datum/mind/M, mob/living/holder, datum/character_identity/I, mob/living/old_holder = null)
	if(M.current != holder)
		return "mind.current is [M.current], expected [holder]"
	if(holder.mind != M)
		return "[holder] does not hold the mind"
	if(M.identity != I)
		return "the mind's identity changed"
	if(holder.identity != I)
		return "[holder] reads another identity"
	if(old_holder && old_holder.mind == M)
		return "[old_holder] still claims the mind"
	for(var/mob/living/carbon/brain/view in world)
		if(view != holder && view.mind == M)
			return "stray view [view] claims the mind"
	return null


// --- Identity follows the mind, by reference -------------------------------------------

/// Brain removal moves the mind into the organ's view; the view reads the
/// character (name, DNA, languages, OOC notes) by reference. Implanting the
/// brain moves the mind into the new body and discards the view.
/datum/unit_test/dq_mind_identity_survives_brain_removal

/datum/unit_test/dq_mind_identity_survives_brain_removal/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/mind/M = dq_test_give_mind(H, "Brain Donor")
	var/datum/character_identity/I = M.identity
	TEST_ASSERT_NOTNULL(I, "a mind entering a body should adopt an identity")
	TEST_ASSERT_EQUAL(H.identity, I, "the body reads the mind's identity")
	TEST_ASSERT_EQUAL(I.dna, H.dna, "the identity references the body's DNA")
	TEST_ASSERT_EQUAL(I.languages, H.languages, "the identity references the body's language list")

	var/obj/item/organ/internal/brain/brain = dq_test_remove_brain(H)
	var/mob/living/carbon/brain/view = brain.hosted_view()
	TEST_ASSERT_NOTNULL(view, "a removed brain with a mind should host a view")
	var/fault = dq_test_mind_fault(M, view, I, H)
	TEST_ASSERT_NULL(fault, "after brain removal: [fault]")
	TEST_ASSERT_EQUAL(view.real_name, I.real_name, "the view shows the character's name")
	TEST_ASSERT_EQUAL(view.dna, I.dna, "the view reads the character's DNA datum, not a clone")
	TEST_ASSERT_EQUAL(view.languages, I.languages, "the view reads the character's language list, not a copy")
	TEST_ASSERT_EQUAL(view.identity.ooc_notes, "notes of Brain Donor", "OOC notes are read through the identity")
	TEST_ASSERT_EQUAL(view.container, brain, "the view lives in its host organ")

	var/mob/living/carbon/human/recipient = dq_test_brainless_recipient(src)
	brain.replaced(recipient, recipient.get_organ(brain.parent_organ))
	fault = dq_test_mind_fault(M, recipient, I, view)
	TEST_ASSERT_NULL(fault, "after implanting: [fault]")
	TEST_ASSERT_NULL(brain.hosted_view(), "an implanted brain hosts no view")
	TEST_ASSERT(QDELETED(view), "the emptied view should be deleted")
	TEST_ASSERT_EQUAL(recipient.languages, I.languages, "the new body speaks the character's languages")
	TEST_ASSERT_EQUAL(recipient.identity.ooc_notes_likes, "likes of Brain Donor", "OOC notes follow the mind")

/// Brain -> MMI -> brain: the same view object (and mind) moves host to host;
/// nothing is recreated or copied, and no host keeps a stale occupant.
/datum/unit_test/dq_mind_identity_survives_mmi

/datum/unit_test/dq_mind_identity_survives_mmi/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/mind/M = dq_test_give_mind(H, "MMI Subject")
	var/datum/character_identity/I = M.identity
	var/obj/item/organ/internal/brain/brain = dq_test_remove_brain(H)
	var/mob/living/carbon/brain/view = brain.hosted_view()
	var/obj/item/mmi/mmi = allocate(/obj/item/mmi)

	mmi.insert_brain(brain, "unit test")
	TEST_ASSERT_EQUAL(mmi.get_occupant(), view, "the MMI adopts the brain's view; no new mob")
	TEST_ASSERT_NULL(brain.hosted_view(), "the brain host no longer holds the view")
	TEST_ASSERT_EQUAL(mmi.brainobj, brain, "the MMI keeps the organ")
	TEST_ASSERT_EQUAL(view.loc, mmi, "the view lives in the MMI")
	TEST_ASSERT_EQUAL(view.container, mmi, "the view's container is the MMI")
	TEST_ASSERT_EQUAL(view.host_tissue(), brain, "the view reads the brain in the MMI")
	TEST_ASSERT(view.stat != DEAD, "a healthy brain in an MMI is up")
	var/fault = dq_test_mind_fault(M, view, I, H)
	TEST_ASSERT_NULL(fault, "in the MMI: [fault]")

	var/obj/item/organ/internal/brain/ejected = mmi.eject_brain(run_loc_floor_bottom_left, "unit test")
	TEST_ASSERT_EQUAL(ejected, brain, "ejecting returns the same organ")
	TEST_ASSERT_NULL(mmi.get_occupant(), "the emptied MMI holds no view")
	TEST_ASSERT_NULL(mmi.brainobj, "the emptied MMI holds no organ")
	TEST_ASSERT_EQUAL(brain.hosted_view(), view, "the view moves back to the organ")
	TEST_ASSERT_EQUAL(view.loc, brain, "the view lives in the organ again")
	fault = dq_test_mind_fault(M, view, I, H)
	TEST_ASSERT_NULL(fault, "after ejection: [fault]")

/// A posibrain takes a character by reference (mind included).
/datum/unit_test/dq_mind_identity_survives_posibrain

/datum/unit_test/dq_mind_identity_survives_posibrain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/mind/M = dq_test_give_mind(H, "Posi Subject")
	var/datum/character_identity/I = M.identity
	var/obj/item/mmi/digital/posibrain/posi = allocate(/obj/item/mmi/digital/posibrain)
	var/mob/living/carbon/brain/view = posi.get_occupant()
	TEST_ASSERT_NOTNULL(view, "a posibrain boots with an empty view")
	TEST_ASSERT_NULL(view.host_tissue(), "a posibrain has no brain tissue")

	var/mob/living/carbon/brain/taken = posi.take_identity(H, TRUE)
	TEST_ASSERT_EQUAL(taken, view, "the posibrain's own view receives the mind")
	var/fault = dq_test_mind_fault(M, view, I, H)
	TEST_ASSERT_NULL(fault, "in the posibrain: [fault]")
	TEST_ASSERT_EQUAL(view.real_name, I.real_name, "the posibrain view shows the character")
	TEST_ASSERT_EQUAL(view.identity.ooc_notes, "notes of Posi Subject", "OOC notes are read through the identity")

/// Borging: the mind leaves the MMI for the cyborg through the host API; the
/// cyborg reads the same identity, and the MMI's view no longer claims it.
/datum/unit_test/dq_mind_identity_survives_borging

/datum/unit_test/dq_mind_identity_survives_borging/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/mind/M = dq_test_give_mind(H, "Borg Subject")
	var/datum/character_identity/I = M.identity
	var/obj/item/organ/internal/brain/brain = dq_test_remove_brain(H)
	var/obj/item/mmi/mmi = allocate(/obj/item/mmi)
	mmi.insert_brain(brain, "unit test")
	var/mob/living/carbon/brain/view = mmi.get_occupant()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot)

	var/datum/component/mind_host/host = get_mind_host(mmi)
	TEST_ASSERT(host.release_mind(R, "unit test borging"), "the MMI should release the mind into the cyborg")
	var/fault = dq_test_mind_fault(M, R, I, view)
	TEST_ASSERT_NULL(fault, "after borging: [fault]")
	TEST_ASSERT_EQUAL(R.identity.ooc_notes, "notes of Borg Subject", "the cyborg reads the character's OOC notes")
	TEST_ASSERT_NULL(view.mind, "the MMI view no longer holds a mind")

	// The borg is destroyed: the mind goes back into its MMI.
	var/mob/living/carbon/brain/returned = host.receive_mind(R.mind, "unit test unborging")
	TEST_ASSERT_EQUAL(returned, view, "the MMI reuses its view")
	fault = dq_test_mind_fault(M, view, I, R)
	TEST_ASSERT_NULL(fault, "back in the MMI: [fault]")

/// Resleeving: the mind moves into a printed sleeve and brings its identity;
/// the sleeve speaks its languages and the identity now references the
/// sleeve's DNA.
/datum/unit_test/dq_mind_identity_survives_resleeve

/datum/unit_test/dq_mind_identity_survives_resleeve/Run()
	var/mob/living/carbon/human/original = allocate(/mob/living/carbon/human)
	var/datum/mind/M = dq_test_give_mind(original, "Sleeve Subject")
	var/datum/character_identity/I = M.identity
	var/list/langs = I.languages
	var/datum/transhuman/body_record/BR = new(original)
	var/mob/living/carbon/human/sleeve = BR.produce_human_mob(run_loc_floor_bottom_left, FALSE, TRUE, "sleeve")

	TEST_ASSERT(transfer_mind(M, sleeve, "unit test resleeve"), "the mind should move into the sleeve")
	var/fault = dq_test_mind_fault(M, sleeve, I, original)
	TEST_ASSERT_NULL(fault, "after resleeving: [fault]")
	TEST_ASSERT_EQUAL(sleeve.languages, langs, "the sleeve speaks the character's language list")
	TEST_ASSERT_EQUAL(I.dna, sleeve.dna, "the identity references the sleeve's DNA")
	TEST_ASSERT_EQUAL(sleeve.identity.ooc_notes, "notes of Sleeve Subject", "OOC notes follow the mind")
	qdel(sleeve)
	qdel(BR)


// --- The view is a thin view on its organ ---------------------------------------------

/// Damage and treatment carry on across body -> view -> MMI -> body: the same
/// lesion datum rides the organ, harm to the view lands on the organ, and the
/// view's questions are answered from it.
/datum/unit_test/dq_mind_mmi_brain_damage_continuity

/datum/unit_test/dq_mind_mmi_brain_damage_continuity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	dq_test_give_mind(H, "Damaged Brain")
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	dq_test_injure_organ(H, brain, 30, /datum/affliction/lesion/contusion)
	var/datum/affliction/lesion/L = brain.find_lesion(/datum/affliction/lesion/contusion)
	TEST_ASSERT_NOTNULL(L, "setup: the brain should carry a contusion")
	TEST_ASSERT_EQUAL(brain.damage, 30, "setup: brain damage")

	dq_test_remove_brain(H)
	var/obj/item/mmi/mmi = allocate(/obj/item/mmi)
	mmi.insert_brain(brain, "unit test")
	var/mob/living/carbon/brain/view = mmi.get_occupant()
	TEST_ASSERT(L in brain.detached_afflictions, "the same lesion rides the brain into the MMI")
	TEST_ASSERT_EQUAL(brain.damage, 30, "the MMI'd brain keeps its damage")
	TEST_ASSERT_EQUAL(view.injury_load(INJURY_CATEGORY_NEURAL), 30, "the view reads its neural load from the organ")
	TEST_ASSERT_EQUAL(view.vitality(), 1 - 30 / brain.max_damage, "the view's vitality is the organ's")

	view.injure(INJURY_BLUNT, 10, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_EQUAL(brain.damage, 40, "harm to the view lands on the organ")
	TEST_ASSERT_EQUAL(L.damage, 40, "harm merges into the same lesion")
	TEST_ASSERT_EQUAL(length(view.body?.afflictions), 0, "the view keeps no health of its own")

	view.mend(TREAT_NEURAL_REPAIR, 5)
	TEST_ASSERT_EQUAL(brain.damage, 35, "treating the view repairs the organ")

	var/mob/living/carbon/human/recipient = dq_test_brainless_recipient(src)
	mmi.eject_brain(run_loc_floor_bottom_left, "unit test")
	brain.replaced(recipient, recipient.get_organ(brain.parent_organ))
	TEST_ASSERT(L in recipient.body.afflictions, "the lesion joins the new body")
	TEST_ASSERT_EQUAL(brain.damage, 35, "the implanted brain keeps its damage")
	TEST_ASSERT_EQUAL(recipient.injury_load(INJURY_CATEGORY_NEURAL), 35, "the new body reads the same brain damage")


// --- Brain death: one decision ----------------------------------------------------------

/// is_brain_dead() is THE decision (100% damage or a dead organ), and the
/// defibrillator, the humanoid body plan, the MMI and the view all agree.
/datum/unit_test/dq_mind_brain_death_gating

/datum/unit_test/dq_mind_brain_death_gating/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/shockpaddles/paddles = allocate(/obj/item/shockpaddles)
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	brain.defib_timer = (CONFIG_GET(number/defib_timer) MINUTES) / 2

	dq_test_set_organ_damage(brain, brain.max_damage - 1)
	TEST_ASSERT(!brain.is_brain_dead(), "a brain at 99% is not brain dead")
	TEST_ASSERT(!H.is_brain_dead(), "the body agrees below 100%")
	TEST_ASSERT(!H.body.is_dead(), "the body plan agrees below 100%")

	dq_test_set_organ_damage(brain, brain.max_damage)
	TEST_ASSERT(brain.is_brain_dead(), "a brain at 100% is brain dead")
	TEST_ASSERT(H.is_brain_dead(), "the body reads brain death from the organ")
	TEST_ASSERT(H.body.is_dead(), "the humanoid plan counts brain death as death")
	H.death()
	TEST_ASSERT_NOTNULL(paddles.can_revive(H), "the defibrillator refuses brain death")
	TEST_ASSERT(H.check_vital_organs(), "the vital organ check agrees")

	dq_test_set_organ_damage(brain, 0)
	brain.status |= ORGAN_DEAD
	TEST_ASSERT(brain.is_brain_dead(), "a dead brain organ is brain dead at any damage")
	TEST_ASSERT_NOTNULL(paddles.can_revive(H), "the defibrillator refuses a dead brain organ")

/// The view dies exactly when its tissue is brain dead, and an MMI refuses a
/// brain-dead brain.
/datum/unit_test/dq_mind_view_status_follows_tissue

/datum/unit_test/dq_mind_view_status_follows_tissue/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	dq_test_give_mind(H, "Fading Brain")
	var/obj/item/organ/internal/brain/brain = dq_test_remove_brain(H)
	var/mob/living/carbon/brain/view = brain.hosted_view()
	TEST_ASSERT(view.stat != DEAD, "a removed healthy brain's view is up")

	dq_test_set_organ_damage(brain, brain.max_damage)
	view.refresh_host_status()
	TEST_ASSERT_EQUAL(view.stat, DEAD, "the view dies when its tissue is brain dead")

	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/item/mmi/mmi = allocate(/obj/item/mmi)
	mmi.attackby(brain, user)
	TEST_ASSERT_NULL(mmi.get_occupant(), "an MMI refuses a brain-dead brain")
	TEST_ASSERT_NULL(mmi.brainobj, "the refused brain stays out of the MMI")

	dq_test_set_organ_damage(brain, 20)
	view.refresh_host_status()
	TEST_ASSERT(view.stat != DEAD, "the view recovers with its tissue when the organ never died")

#endif
