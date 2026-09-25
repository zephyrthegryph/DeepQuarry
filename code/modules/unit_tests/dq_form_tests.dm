// Unit tests for forms (one character mob, many shapes), the nanoform body
// plan and core dormancy. See doc/mob_life_architecture.md §6 and §9.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Switching form keeps the character's afflictions, reagents and statuses
/// ticking: the mob stays in the world and its Life frames keep running (bug 10).
/datum/unit_test/dq_form_switch_keeps_body_ticking

/datum/unit_test/dq_form_switch_keeps_body_ticking/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/promethean, test_floor())
	TEST_ASSERT(isturf(H.loc), "the test character must start on a floor")
	var/datum/component/forms/F = H.get_forms()
	TEST_ASSERT_NOTNULL(F, "a promethean should have the forms component")
	TEST_ASSERT(istype(F.current, /datum/form/human), "a promethean should start in human form")

	var/datum/affliction/pain = H.body.afflict(/datum/affliction/acute_pain, null, 60)
	TEST_ASSERT_NOTNULL(pain, "acute pain could not be afflicted")
	H.bloodstr.add_reagent(REAGENT_ID_TRICORDRAZINE, 10)
	H.status_at_least(EFFECT_WEAKENED, 10)

	TEST_ASSERT(F.set_form(/datum/form/promethean_blob), "switching to the blob form should succeed")
	TEST_ASSERT(istype(F.current, /datum/form/promethean_blob), "the blob form should be current")
	TEST_ASSERT(isturf(H.loc), "the character must stay in the world while blobbed, not in nullspace")
	TEST_ASSERT(HAS_TRAIT(H, TRAIT_FORM_HIDES_BODY), "the blob form draws itself instead of the body")
	TEST_ASSERT(pain in H.body.afflictions, "afflictions must survive a form switch")

	var/severity_before = pain.severity
	var/volume_before = H.bloodstr.get_reagent_amount(REAGENT_ID_TRICORDRAZINE)
	om_run_frame_now(H, /datum/om/pipeline/life)
	TEST_ASSERT(QDELETED(pain) || pain.severity < severity_before, "afflictions should keep progressing in blob form ([severity_before] -> [QDELETED(pain) ? 0 : pain.severity])")
	TEST_ASSERT(H.bloodstr.get_reagent_amount(REAGENT_ID_TRICORDRAZINE) < volume_before, "reagents should keep metabolising in blob form")
	TEST_ASSERT(H.has_status(EFFECT_WEAKENED), "statuses survive a form switch (they wear off in real time, doc/rewrite/life_on_om.md §7)")
	TEST_ASSERT(life_test_started(H, /datum/om/pipeline/life), "the blobbed character keeps its life pipeline")

	TEST_ASSERT(F.set_form(/datum/form/human), "switching back should succeed")
	TEST_ASSERT(!HAS_TRAIT(H, TRAIT_FORM_HIDES_BODY), "the human form draws the body again")

/// The slime form takes ×0.75 physical and ×2 thermal injury through the
/// character's own body.
/datum/unit_test/dq_form_injury_multipliers

/datum/unit_test/dq_form_injury_multipliers/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/promethean)
	var/datum/component/forms/F = H.get_forms()
	TEST_ASSERT_NOTNULL(F, "a promethean should have the forms component")
	var/human_blunt = H.injure(INJURY_BLUNT, 4, BP_TORSO, flags = INJURE_SILENT)
	var/human_burn = H.injure(INJURY_BURN, 2, BP_TORSO, flags = INJURE_SILENT)
	F.set_form(/datum/form/promethean_blob)
	var/blob_blunt = H.injure(INJURY_BLUNT, 4, BP_TORSO, flags = INJURE_SILENT)
	var/blob_burn = H.injure(INJURY_BURN, 2, BP_TORSO, flags = INJURE_SILENT)
	TEST_ASSERT(human_blunt > 0 && human_burn > 0, "injury should land in human form")
	TEST_ASSERT(abs(blob_blunt - human_blunt * 0.75) < 0.01, "blob form should take ×0.75 physical ([human_blunt] -> [blob_blunt])")
	TEST_ASSERT(abs(blob_burn - human_burn * 2) < 0.01, "blob form should take ×2 thermal ([human_burn] -> [blob_burn])")

/// Deleting a character leaves nothing pointing at it: the forms component,
/// its forms and the protean rig all let go (bug 16).
/datum/unit_test/dq_form_no_refs_on_delete

/datum/unit_test/dq_form_no_refs_on_delete/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean, test_floor())
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	TEST_ASSERT_NOTNULL(F, "a protean should have the protean forms component")
	var/obj/item/rig/protean/R = allocate(/obj/item/rig/protean, null, H)
	TEST_ASSERT_EQUAL(F.rig, R, "the rig should register on the character's forms component")
	TEST_ASSERT_EQUAL(R.myprotean, H, "the rig should know its protean")

	TEST_ASSERT(F.set_form(/datum/form/protean_blob), "switching to the protean blob should succeed")
	TEST_ASSERT(F.enter_rig(), "folding into the rig should succeed")
	TEST_ASSERT_EQUAL(H.loc, R, "the character should sit inside its rig with a real loc")

	var/datum/form/protean_blob/B = F.blob_form()
	qdel(H)
	TEST_ASSERT(QDELETED(F), "the forms component should go with the character")
	TEST_ASSERT(QDELETED(B), "form instances should go with the character")
	TEST_ASSERT_NULL(F.current, "the component should drop its current form")
	TEST_ASSERT_NULL(F.forms, "the component should drop its forms")
	TEST_ASSERT_NULL(F.rig, "the component should drop its rig")
	TEST_ASSERT_NULL(R.myprotean, "the rig should drop the deleted character")

/// A nanoform body that would die goes dormant instead, and is revived by
/// calibration, plating repair and defibrillation, in that order.
/datum/unit_test/dq_nanoform_dormancy_and_revival

/datum/unit_test/dq_nanoform_dormancy_and_revival/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean, test_floor())
	TEST_ASSERT(istype(H.body, /datum/body/humanoid/nanoform), "a protean should have the nanoform body plan")
	var/obj/item/rig/protean/R = allocate(/obj/item/rig/protean, null, H)

	H.injure(INJURY_BLUNT, 1000, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/affliction/core_dormancy/D = H.body.find_affliction(/datum/affliction/core_dormancy)
	TEST_ASSERT_NOTNULL(D, "a destroyed nanoform body should go dormant")
	TEST_ASSERT(H.stat != DEAD, "a dormant protean is not dead")
	TEST_ASSERT(H in GLOB.living_mob_list, "a dormant protean stays on the living list")
	TEST_ASSERT_EQUAL(H.loc, R, "going dormant should fold the protean into its rig")

	H.mend(TREAT_CALIBRATION, 1)
	TEST_ASSERT_EQUAL(D.revival_step, DORMANCY_SEALED, "nothing advances until the panel is open")
	D.open_panel()
	H.mend(TREAT_PLATING_REPAIR, 1)
	TEST_ASSERT_EQUAL(D.revival_step, DORMANCY_OPEN, "steps must come in order")
	H.mend(TREAT_CALIBRATION, 1)
	H.mend(TREAT_PLATING_REPAIR, 1)
	H.mend(TREAT_DEFIBRILLATION, 1)
	TEST_ASSERT_EQUAL(D.revival_step, DORMANCY_REBOOTING, "calibration, plating repair and defibrillation should start the reboot")

	D.complete_revival()
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/core_dormancy), "revival should end dormancy")
	TEST_ASSERT(!H.body.is_dead(), "revival should rebuild the body")

/// Regeneration is funded by refactory steel, charged by what mend() repaired,
/// only in forms that regenerate, and it never revives a dead organ (bug 11).
/datum/unit_test/dq_nanoform_regeneration_costs_steel

/datum/unit_test/dq_nanoform_regeneration_costs_steel/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean)
	var/datum/body/humanoid/nanoform/B = H.body
	TEST_ASSERT(istype(B), "a protean should have the nanoform body plan")
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	var/obj/item/organ/internal/nano/refactory/R = H.nano_get_refactory()
	TEST_ASSERT_NOTNULL(R, "a protean should have a refactory")
	R.add_stored_material(MAT_STEEL, 1000)
	var/obj/item/organ/internal/orchestrator = H.internal_organs_by_name[O_ORCH]
	orchestrator.status |= ORGAN_DEAD

	H.injure(INJURY_BLUNT, 10, BP_L_ARM, flags = INJURE_SILENT)
	TEST_ASSERT_EQUAL(B.regenerate(), 0, "the human form doesn't regenerate")

	F.set_form(/datum/form/protean_blob)
	var/steel_before = R.get_stored_material(MAT_STEEL)
	var/healed = B.regenerate()
	TEST_ASSERT(healed > 0, "the blob form should regenerate")
	TEST_ASSERT_EQUAL(steel_before - R.get_stored_material(MAT_STEEL), CEILING(healed * NANOFORM_STEEL_PER_POINT, 1), "steel should be charged from what mend() repaired")
	TEST_ASSERT(orchestrator.status & ORGAN_DEAD, "regeneration must not revive a dead organ")

#endif
