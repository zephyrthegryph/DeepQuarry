// Unit tests for proteans: the control cluster (rig) as the protean's body,
// dormancy, revival, the cluster's power ledger and the nanite afflictions.
// See doc/mob_life_architecture.md §6.2.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A protean with its own control cluster, standing on a test floor.
/datum/unit_test/proc/make_protean_with_rig()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean, test_floor())
	allocate(/obj/item/rig/protean, test_floor(), H)
	return H

/// A protean that chose to fold into its cluster and then takes lethal damage
/// goes dormant, on the immediate path (a hit) and on the tick path.
/datum/unit_test/dq_protean_folded_lethal_goes_dormant

/datum/unit_test/dq_protean_folded_lethal_goes_dormant/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	var/obj/item/rig/protean/R = F.rig
	TEST_ASSERT_NOTNULL(R, "the protean should own its rig")
	TEST_ASSERT(F.enter_rig(), "folding voluntarily should succeed")
	TEST_ASSERT_EQUAL(H.loc, R, "the protean should sit inside its rig")
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/core_dormancy), "a voluntary fold is not dormancy")

	// Immediate path: a lethal hit on the folded cluster.
	R.take_damage(1000, BRUTE, MELEE, FALSE)
	var/datum/affliction/core_dormancy/D = H.body.find_affliction(/datum/affliction/core_dormancy)
	TEST_ASSERT_NOTNULL(D, "lethal damage while folded should go dormant")
	TEST_ASSERT(H.stat != DEAD, "a folded protean must not die")
	TEST_ASSERT(H.body.is_unconscious(), "a dormant core is unconscious through the consciousness model")

	// Tick path: the body is still lethally damaged when dormancy is lifted.
	D.cure()
	TEST_ASSERT(H.body.is_dead(), "the body should still be lethally damaged")
	H.body.evaluate_status()
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/core_dormancy), "the tick path should go dormant too")
	TEST_ASSERT(H.stat != DEAD, "the tick path must not kill a folded protean")

/// A dormant protean's cluster is inert: no armour, unsealed, no modules and a
/// heavy slowdown. It shields its wearer from nothing.
/datum/unit_test/dq_protean_dormant_rig_is_inert

/datum/unit_test/dq_protean_dormant_rig_is_inert/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	var/obj/item/rig/protean/R = F.rig
	R.armor["melee"] = 40
	R.chest.armor["melee"] = 40
	H.injure(INJURY_BLUNT, 1000, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_NOTNULL(H.body.find_affliction(/datum/affliction/core_dormancy), "the protean should be dormant")
	TEST_ASSERT(R.inert, "a dormant protean's cluster should be inert")
	for(var/key in R.armor)
		TEST_ASSERT_EQUAL(R.armor[key], 0, "a dormant cluster has no [key] armour")
	for(var/obj/item/piece in list(R.helmet, R.gloves, R.boots, R.chest))
		for(var/key in piece.armor)
			TEST_ASSERT_EQUAL(piece.armor[key], 0, "a dormant cluster's [piece.name] has no [key] armour")
	TEST_ASSERT(R.canremove, "a dormant cluster is unsealed")
	for(var/obj/item/rig_module/module in R.installed_modules)
		TEST_ASSERT(!module.active, "a dormant cluster runs no modules ([module])")
	TEST_ASSERT_EQUAL(R.slowdown, PROTEAN_RIG_INERT_SLOWDOWN, "a dormant cluster is a heavy dead weight")

	// Worn by someone, it soaks nothing for them.
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, test_floor())
	if(ismob(R.loc))
		var/mob/M = R.loc
		M.drop_from_inventory(R, test_floor())
	TEST_ASSERT(wearer.equip_to_slot_if_possible(R, slot_back, 0, 1), "the wearer should put the cluster on")
	var/before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	wearer.injure(INJURY_BLUNT, 20, BP_TORSO, flags = INJURE_ARMORED | INJURE_SILENT)
	TEST_ASSERT_EQUAL(H.injury_load(INJURY_CATEGORY_PHYSICAL), before, "a dormant cluster must not soak hits for its wearer")

/// Hits on the cluster are the protean's injuries: on the cluster itself and,
/// worn by someone else, what its armour stops.
/datum/unit_test/dq_protean_rig_hits_land_on_body

/datum/unit_test/dq_protean_rig_hits_land_on_body/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	var/obj/item/rig/protean/R = F.rig
	var/integrity_before = R.get_integrity()

	var/load_before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	R.take_damage(20, BRUTE, MELEE, FALSE)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_PHYSICAL) > load_before, "a hit on the cluster should injure the protean ([load_before] -> [H.injury_load(INJURY_CATEGORY_PHYSICAL)])")
	TEST_ASSERT_EQUAL(R.get_integrity(), integrity_before, "the cluster has no damage pool of its own")

	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, test_floor())
	if(ismob(R.loc))
		var/mob/M = R.loc
		M.drop_from_inventory(R, test_floor())
	TEST_ASSERT(wearer.equip_to_slot_if_possible(R, slot_back, 0, 1), "the wearer should put the cluster on")
	R.chest.forceMove(wearer)
	TEST_ASSERT(wearer.equip_to_slot_if_possible(R.chest, slot_wear_suit, 0, 1), "the chest piece should deploy onto the wearer")
	R.chest.armor["melee"] = 50
	R.chest.worn_protection_changed()
	load_before = H.injury_load(INJURY_CATEGORY_PHYSICAL)
	wearer.injure(INJURY_BLUNT, 20, BP_TORSO, flags = INJURE_ARMORED | INJURE_SILENT)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_PHYSICAL) > load_before, "what the cluster's armour stops should land on the protean")

/// The cluster's cell moves only through its power ledger; the swarm pays for
/// recharging with nutrition.
/datum/unit_test/dq_protean_rig_power_ledger

/datum/unit_test/dq_protean_rig_power_ledger/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	var/obj/item/rig/protean/R = F.rig
	TEST_ASSERT_NOTNULL(R.cell, "the cluster should have a cell")
	var/charge_before = R.cell.charge
	TEST_ASSERT(R.draw_power(ROBOT_CELL_JOULES(100), src), "a full cell should cover a small draw")
	// The cell loses a little to its material delivery efficiency on top of the draw.
	TEST_ASSERT(abs((charge_before - R.cell.charge) - 100) < 1, "the draw should take its units from the cell ([charge_before - R.cell.charge])")
	TEST_ASSERT(!R.draw_power(ROBOT_CELL_JOULES(R.cell.maxcharge * 2), src), "an all-or-nothing draw can't overdraw")
	H.nutrition = 1000
	var/stored = R.recharge_from(H)
	TEST_ASSERT(stored > 0, "the swarm should recharge its cluster")
	TEST_ASSERT(H.nutrition < 1000, "recharging should cost nutrition")

/// Revival rebuilds cohesion and what the revival steps repaired; afflictions
/// it didn't touch stay.
/datum/unit_test/dq_protean_revival_keeps_unrelated_afflictions

/datum/unit_test/dq_protean_revival_keeps_unrelated_afflictions/Run()
	var/mob/living/carbon/human/H = make_protean_with_rig()
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	var/datum/affliction/contamination = H.body.afflict(/datum/affliction/nanite/contamination, refactory, 40)
	TEST_ASSERT_NOTNULL(contamination, "contamination should take hold on a nanoform refactory")
	H.injure(INJURY_BLUNT, 10, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT(arm.get_trauma() > 0, "the arm should be hurt")

	H.injure(INJURY_BLUNT, 1000, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/affliction/core_dormancy/D = H.body.find_affliction(/datum/affliction/core_dormancy)
	TEST_ASSERT_NOTNULL(D, "the protean should be dormant")
	D.open_panel()
	H.mend(TREAT_CALIBRATION, 1)
	H.mend(TREAT_PLATING_REPAIR, 1)
	H.mend(TREAT_DEFIBRILLATION, 1)
	TEST_ASSERT_EQUAL(D.revival_step, DORMANCY_REBOOTING, "the revival steps should start the reboot")
	D.complete_revival()

	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/core_dormancy), "revival should end dormancy")
	TEST_ASSERT(!H.body.is_dead(), "revival should rebuild the vital parts")
	TEST_ASSERT(H.stat != DEAD, "a revived protean is alive")
	TEST_ASSERT_NULL(H.body.find_affliction(/datum/affliction/nanite/cohesion_loss), "revival rebuilds cohesion")
	TEST_ASSERT(contamination in H.body.afflictions, "revival must not clear contamination")
	TEST_ASSERT(arm.get_trauma() > 0, "revival must not repair a limb it didn't rebuild")
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	TEST_ASSERT(!F.rig.inert, "the cluster wakes with its protean")

/// Nanite biology answers only to the nanite mechanisms.
/datum/unit_test/dq_nanoform_treatment_is_limited

/datum/unit_test/dq_nanoform_treatment_is_limited/Run()
	for(var/tag in list(TREAT_PLATING_REPAIR, TREAT_WIRING_REPAIR, TREAT_CALIBRATION, TREAT_REGENERATION, TREAT_FEEDSTOCK))
		TEST_ASSERT(treatment_tag_biology(tag) & BIOLOGY_NANOFORM, "[tag] should reach nanites")
	for(var/tag in list(TREAT_TISSUE_REPAIR, TREAT_BURN_CARE, TREAT_ANTITOXIN, TREAT_OXYGENATION, TREAT_SYSTEM_RESTORE, TREAT_COOLANT))
		TEST_ASSERT(!(treatment_tag_biology(tag) & BIOLOGY_NANOFORM), "[tag] must not reach nanites")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean)
	for(var/organ_tag in list(O_ORCH, O_FACT))
		var/obj/item/organ/internal/O = H.internal_organs_by_name[organ_tag]
		TEST_ASSERT_EQUAL(O.robotic, ORGAN_NANOFORM, "the [organ_tag] is a nanite organ")
	var/datum/affliction/strain = H.body.afflict(/datum/affliction/nanite/form_strain, null, 30)
	TEST_ASSERT_EQUAL(H.mend(TREAT_TISSUE_REPAIR, 100), 0, "tissue repair must not treat nanites")
	TEST_ASSERT_EQUAL(strain.severity, 30, "form strain should be untouched by a biological treatment")

/// Cohesion loss: heavy hits trigger it; plating repair treats it.
/datum/unit_test/dq_nanite_cohesion_loss

/datum/unit_test/dq_nanite_cohesion_loss/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean)
	H.injure(INJURY_BLUNT, 10, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/affliction/A = H.body.find_affliction(/datum/affliction/nanite/cohesion_loss)
	TEST_ASSERT_NOTNULL(A, "a heavy hit should cost the swarm cohesion")
	H.mend(TREAT_PLATING_REPAIR, 200)
	TEST_ASSERT(QDELETED(A) || !A.body, "plating repair should rebuild cohesion")

/// Refactory depletion: needing repair with no steel triggers it; steel
/// feedstock treats it.
/datum/unit_test/dq_nanite_refactory_depletion

/datum/unit_test/dq_nanite_refactory_depletion/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean)
	var/datum/body/humanoid/nanoform/B = H.body
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	var/obj/item/organ/internal/nano/refactory/R = H.nano_get_refactory()
	R.consume_stored_material(MAT_STEEL, R.get_stored_material(MAT_STEEL))
	F.set_form(/datum/form/protean_blob)
	H.injure(INJURY_BLUNT, 10, BP_L_ARM, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	B.regenerate()
	var/datum/affliction/A = H.body.find_affliction(/datum/affliction/nanite/refactory_depletion, R)
	TEST_ASSERT_NOTNULL(A, "a swarm needing repair with an empty refactory should deplete it")
	R.add_stored_material(MAT_STEEL, SHEET_MATERIAL_AMOUNT)
	TEST_ASSERT(QDELETED(A) || !A.body, "steel feedstock should end the depletion")

/// Orchestrator damage: hits on the orchestrator trigger it; calibration
/// treats it.
/datum/unit_test/dq_nanite_orchestrator_damage

/datum/unit_test/dq_nanite_orchestrator_damage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean)
	var/obj/item/organ/internal/nano/orchestrator/O = H.internal_organs_by_name[O_ORCH]
	H.injure(INJURY_BLUNT, 5, O, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/affliction/A = H.body.find_affliction(/datum/affliction/nanite/orchestrator_damage, O)
	TEST_ASSERT_NOTNULL(A, "a hit on the orchestrator should damage the swarm's control")
	H.mend(TREAT_CALIBRATION, 100, O)
	TEST_ASSERT(QDELETED(A) || !A.body, "calibration should restore control")

/// Contamination: foreign reagents in the swarm trigger it; the refactory's
/// filtering (regeneration) treats it.
/datum/unit_test/dq_nanite_contamination

/datum/unit_test/dq_nanite_contamination/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean)
	var/datum/body/humanoid/nanoform/B = H.body
	H.bloodstr.add_reagent(REAGENT_ID_TRICORDRAZINE, 10)
	TEST_ASSERT(B.foreign_reagent_volume() > 0, "tricordrazine is foreign to the swarm")
	B.state_triggers()
	var/datum/affliction/A = H.body.find_affliction(/datum/affliction/nanite/contamination, H.nano_get_refactory())
	TEST_ASSERT_NOTNULL(A, "foreign reagents should contaminate the swarm")
	H.bloodstr.clear_reagents()
	H.mend(TREAT_REGENERATION, 100)
	TEST_ASSERT(QDELETED(A) || !A.body, "regeneration should filter the contamination out")

/// Form strain: switching shape too fast triggers it; calibration treats it.
/datum/unit_test/dq_nanite_form_strain

/datum/unit_test/dq_nanite_form_strain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human/protean, test_floor())
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	TEST_ASSERT(F.set_form(/datum/form/protean_blob), "the first switch should succeed")
	TEST_ASSERT(F.set_form(/datum/form/human), "the second switch should succeed")
	var/datum/affliction/A = H.body.find_affliction(/datum/affliction/nanite/form_strain)
	TEST_ASSERT_NOTNULL(A, "switching back at once should strain the swarm")
	H.mend(TREAT_CALIBRATION, 100)
	TEST_ASSERT(QDELETED(A) || !A.body, "calibration should ease form strain")

#endif
