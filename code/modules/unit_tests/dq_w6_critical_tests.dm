// Unit tests for the wave 6 critical patches: the sleeper's chemical list,
// amputation and cavity implant gating, protean dormancy without a cluster or
// inside a container, species component cleanup, MMI tissue loss, cyborg
// destruction without a turf and the syndicate cyborg HUD.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The sleeper injects only what it lists; a crafted chemical id is refused.
/datum/unit_test/dq_sleeper_rejects_unlisted_chemical

/datum/unit_test/dq_sleeper_rejects_unlisted_chemical/Run()
	var/obj/machinery/sleeper/S = allocate(/obj/machinery/sleeper, test_floor())
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, test_floor())
	S.stat = 0
	om_link(patient, S, /datum/om/relation/occupant_of)
	TEST_ASSERT(!LAZYACCESS(S.available_chemicals, REAGENT_ID_TOXIN), "the sleeper must not list toxin")
	S.inject_chemical(user, REAGENT_ID_TOXIN, 5)
	TEST_ASSERT_EQUAL(patient.reagents.get_reagent_amount(REAGENT_ID_TOXIN), 0, "an unlisted chemical must not be injected")
	S.inject_chemical(user, REAGENT_ID_INAPROVALINE, 5)
	TEST_ASSERT_EQUAL(patient.reagents.get_reagent_amount(REAGENT_ID_INAPROVALINE), 5, "a listed chemical is injected")
	om_unlink(patient, S, /datum/om/relation/occupant_of)

/// Amputation is only offered on a limb opened to at least retracted flesh.
/datum/unit_test/dq_amputation_needs_open_limb

/datum/unit_test/dq_amputation_needs_open_limb/Run()
	var/mob/living/carbon/human/surgeon = allocate(/mob/living/carbon/human, test_floor())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/surgical/circular_saw/saw = allocate(/obj/item/surgical/circular_saw)
	var/datum/surgical_step/S = surgical_step(/datum/surgical_step/amputate)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT(S.can_use(surgeon, H, BP_L_ARM, saw) != TRUE, "amputation must not be offered on a closed limb")
	arm.open_surgical_site(INCISION_MADE)
	TEST_ASSERT(S.can_use(surgeon, H, BP_L_ARM, saw) != TRUE, "a skin incision is not enough to amputate")
	arm.open_surgical_site(FLESH_RETRACTED)
	TEST_ASSERT_EQUAL(S.can_use(surgeon, H, BP_L_ARM, saw), TRUE, "amputation is offered on a retracted limb")

/// Cavity implanting is opt-in: instruments, containers and tools are never swallowed.
/datum/unit_test/dq_cavity_implant_is_opt_in

/datum/unit_test/dq_cavity_implant_is_opt_in/Run()
	var/datum/surgical_step/S = surgical_step(/datum/surgical_step/place_item)
	for(var/path in list(/obj/item/reagent_containers/syringe, /obj/item/healthanalyzer, /obj/item/decompression_needle, /obj/item/airway_kit, /obj/item/bag_valve_mask, /obj/item/tourniquet, /obj/item/surgical/scalpel, /obj/item/tool/screwdriver))
		var/obj/item/I = allocate(path)
		TEST_ASSERT(!I.cavity_implantable, "[path] must not be cavity implantable")
		TEST_ASSERT_EQUAL(S.tool_quality(I), 0, "[path] must not be a cavity implant tool")
	var/obj/item/coin/C = allocate(/obj/item/coin)
	TEST_ASSERT(C.cavity_implantable, "a coin is a generic small item")
	TEST_ASSERT(S.tool_quality(C) > 0, "a coin can be placed in a cavity")

/// A dormant protean with no control cluster is repaired on its body; a
/// destroyed cluster hands the core back to the body.
/datum/unit_test/dq_protean_dormancy_without_rig

/datum/unit_test/dq_protean_dormancy_without_rig/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	TEST_ASSERT(F.enter_rig(), "the protean should fold into its cluster")
	H.injure(INJURY_BLUNT, 1000, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/affliction/core_dormancy/D = H.body.find_affliction(/datum/affliction/core_dormancy)
	TEST_ASSERT_NOTNULL(D, "the protean should be dormant")
	TEST_ASSERT(!D.repaired_on_body(), "a folded core is repaired through its cluster")
	qdel(F.rig)
	TEST_ASSERT_NULL(F.rig, "the cluster is gone")
	TEST_ASSERT(isturf(H.loc), "the core spills out of a destroyed cluster")
	TEST_ASSERT(D.repaired_on_body(), "with no cluster the core is repaired on the body")
	var/obj/item/tool/screwdriver/driver = allocate(/obj/item/tool/screwdriver)
	TEST_ASSERT(D.is_repair_item(driver), "a screwdriver opens the sealed core")
	D.open_panel()
	var/obj/item/stack/nanopaste/paste = allocate(/obj/item/stack/nanopaste)
	TEST_ASSERT(!D.is_repair_item(paste), "nanopaste isn't the next step after opening")
	H.mend(TREAT_CALIBRATION, 1)
	TEST_ASSERT(D.is_repair_item(paste), "nanopaste follows calibration")

/// Going dormant inside a container keeps the protean in it.
/datum/unit_test/dq_protean_dormancy_stays_contained

/datum/unit_test/dq_protean_dormancy_stays_contained/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	var/obj/structure/closet/closet = allocate(/obj/structure/closet, test_floor())
	H.forceMove(closet)
	var/atom/rig_loc = F.rig.loc
	H.injure(INJURY_BLUNT, 1000, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/core_dormancy), "the protean should be dormant")
	TEST_ASSERT_EQUAL(H.loc, closet, "a protean going dormant in a closet stays in it")
	TEST_ASSERT_EQUAL(F.rig.loc, rig_loc, "the cluster isn't dropped outside")
	TEST_ASSERT(!F.enter_rig(), "folding up inside a container is refused")

/// A species change removes the old species' components; a folded protean unfolds first.
/datum/unit_test/dq_set_species_removes_components

/datum/unit_test/dq_set_species_removes_components/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	TEST_ASSERT(F.enter_rig(), "the protean should fold into its cluster")
	H.set_species(SPECIES_HUMAN)
	TEST_ASSERT(isturf(H.loc), "the protean unfolds before its species changes")
	TEST_ASSERT_NULL(H.GetComponent(/datum/component/forms/protean), "a human keeps no protean forms component")

/// Losing brain tissue kills an MMI's view; an empty view doesn't block a new brain.
/datum/unit_test/dq_mmi_tissue_loss_kills_view

/datum/unit_test/dq_mmi_tissue_loss_kills_view/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	dq_test_give_mind(H, "Tissue Subject")
	var/obj/item/organ/internal/brain/brain = dq_test_remove_brain(H)
	var/obj/item/mmi/mmi = allocate(/obj/item/mmi)
	mmi.insert_brain(brain, "unit test")
	var/mob/living/carbon/brain/view = mmi.get_occupant()
	TEST_ASSERT_NOTNULL(view, "the MMI holds the view")
	TEST_ASSERT(view.stat != DEAD, "a healthy brain's view is alive")
	qdel(mmi.brainobj)
	TEST_ASSERT_EQUAL(view.stat, DEAD, "a view whose brain tissue is destroyed is dead")

	// Digital hosts are tissue-less and stay up.
	var/obj/item/mmi/digital/posibrain/posi = allocate(/obj/item/mmi/digital/posibrain)
	TEST_ASSERT(posi.get_occupant().stat != DEAD, "a posibrain view needs no tissue")

	// An empty view left behind doesn't block a new brain.
	var/obj/item/mmi/empty = allocate(/obj/item/mmi)
	var/datum/component/mind_host/host = get_mind_host(empty)
	host.receive_mind(null, "unit test empty view")
	TEST_ASSERT_NOTNULL(empty.get_occupant(), "the MMI has an empty view")
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human)
	var/datum/mind/M2 = dq_test_give_mind(H2, "Second Subject")
	var/obj/item/organ/internal/brain/brain2 = dq_test_remove_brain(H2)
	empty.insert_brain(brain2, "unit test")
	TEST_ASSERT_EQUAL(empty.get_occupant()?.mind, M2, "the new brain's mind is seated despite the empty view")
	TEST_ASSERT(empty.get_occupant().stat != DEAD, "the new brain's view is alive")

/// A destroyed cyborg's mind goes to its MMI on a real turf, or to a ghost
/// when there is no location; never into an MMI inside the deleting mob.
/datum/unit_test/dq_borg_destroyed_mind_placement

/datum/unit_test/dq_borg_destroyed_mind_placement/Run()
	var/mob/living/silicon/robot/R = new /mob/living/silicon/robot(test_floor())
	if(!R.mmi)
		R.mmi = new /obj/item/mmi(R)
	var/obj/item/mmi/mmi = R.mmi
	var/datum/mind/M = dq_test_give_mind(R, "Borg On Floor")
	qdel(R)
	TEST_ASSERT(!QDELETED(mmi), "the MMI survives its cyborg")
	TEST_ASSERT_EQUAL(mmi.loc, test_floor(), "the MMI lands on the cyborg's turf")
	TEST_ASSERT_EQUAL(M.current, mmi.get_occupant(), "the mind is in the MMI's view")
	qdel(mmi)

	var/mob/living/silicon/robot/lost = new /mob/living/silicon/robot(test_floor())
	if(!lost.mmi)
		lost.mmi = new /obj/item/mmi(lost)
	var/obj/item/mmi/lost_mmi = lost.mmi
	var/datum/mind/M2 = dq_test_give_mind(lost, "Borg In Nullspace")
	lost.moveToNullspace()
	qdel(lost)
	TEST_ASSERT(QDELETED(lost_mmi), "an MMI with nowhere to go is deleted with the cyborg")
	TEST_ASSERT(!istype(M2.current, /mob/living/carbon/brain), "the mind must not be left in an MMI view")

/// The syndicate HUD is built on state changes, not per tick.
/datum/unit_test/dq_syndicate_borg_state

/datum/unit_test/dq_syndicate_borg_state/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/datum/mind/M = dq_test_give_mind(R, "Syndie Borg")
	R.set_syndicate(TRUE)
	TEST_ASSERT(R.syndicate, "the cyborg is syndicate")
	TEST_ASSERT_EQUAL(M.special_role, "traitor", "a syndicate cyborg's mind is marked")
	TEST_ASSERT_NULL(R.connected_ai, "a syndicate cyborg has no AI link")
	TEST_ASSERT_NULL(R.traitor_hud_images, "no client, no HUD images")
	R.set_syndicate(FALSE)
	TEST_ASSERT(!R.syndicate, "the cyborg is no longer syndicate")
	TEST_ASSERT_NULL(R.traitor_hud_client, "unsetting clears the HUD")
	LAZYREMOVE(GLOB.traitors.current_antagonists, M)
	M.special_role = null

#endif
