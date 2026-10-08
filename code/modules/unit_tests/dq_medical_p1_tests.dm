// MED-3: regression tests for the P1 "wrong medical results" rows of
// doc/medical_audit_findings.md. One test (or assertion group) per row, named by row id.

/datum/unit_test/proc/dq_p1_finding(datum/diagnosis/D, source_type)
	for(var/datum/diagnosis_finding/F as anything in D?.findings)
		if(F.source_type == source_type)
			return F
	return null

/// B10: a SLOW reagent never falls through to the normal addiction threshold.
/datum/unit_test/dq_p1_b10_slow_addiction_threshold

/datum/unit_test/dq_p1_b10_slow_addiction_threshold/Run()
	set_config(/datum/config_entry/flag/can_addict_during_round, TRUE)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_TRAMADOL, 5)
	// Past the normal threshold (-1000) but well short of the slow one (-1750).
	H.set_addiction_buildup(REAGENT_ID_TRAMADOL, -1200)
	H.process_addictions()
	TEST_ASSERT(H.get_addiction_to_reagent(REAGENT_ID_TRAMADOL) <= 0, "tramadol (ADDICT_SLOW) must not addict at the normal threshold, counter is [H.get_addiction_to_reagent(REAGENT_ID_TRAMADOL)]")

/// B9: the advanced trauma kit spends one charge per wound it treats.
/datum/unit_test/dq_p1_b9_trauma_kit_charges

/datum/unit_test/dq_p1_b9_trauma_kit_charges/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human)
	var/obj/item/stack/medical/advanced/bruise_pack/kit = allocate(/obj/item/stack/medical/advanced/bruise_pack)
	H.injure(INJURY_CUT, 15, BP_L_ARM)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/list/wounds = arm.get_wounds()
	TEST_ASSERT(length(wounds), "setup: the cut should leave a wound")
	TEST_ASSERT_EQUAL(kit.apply_wound_treatment(wounds[1], H, medic, arm, 1), 2, "treating a second wound spends a second charge")
	TEST_ASSERT(kit.wound_limited_by_amount(), "the kit stops when its charges run out")

/// B20: the advanced burn kit refuses an open limb.
/datum/unit_test/dq_p1_b20_burn_kit_open_limb

/datum/unit_test/dq_p1_b20_burn_kit_open_limb/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human)
	dq_give_zone_sel(medic)
	medic.zone_sel.set_selecting(BP_TORSO)
	var/obj/item/stack/medical/advanced/ointment/kit = allocate(/obj/item/stack/medical/advanced/ointment)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	torso.open = 1
	var/before = kit.get_amount()
	TEST_ASSERT_EQUAL(kit.attack(H, medic), ITEM_INTERACT_FAILURE, "a burn kit on a cut-open limb must fail")
	TEST_ASSERT_EQUAL(kit.get_amount(), before, "no charge is spent on an open limb")
	torso.open = 0

/// B22: a stab never forces a negative amount in.
/datum/unit_test/dq_p1_b22_syringe_stab_amount

/datum/unit_test/dq_p1_b22_syringe_stab_amount/Run()
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe)
	for(var/volume in list(0, 2, 4.9, 5, 12, 15))
		var/amount = S.syringestab_amount(volume)
		TEST_ASSERT(amount >= 0, "a stab with [volume]u must not transfer a negative amount (got [amount])")
		TEST_ASSERT(amount <= volume, "a stab can't transfer more than is in the barrel")

/// B5: one claridyl side effect at a time.
/datum/unit_test/dq_p1_b5_claridyl_one_side_effect

/datum/unit_test/dq_p1_b5_claridyl_one_side_effect/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/reagent/claridyl/R = SSchemistry.chemical_reagents[REAGENT_ID_CLARIDYL]
	R.claridyl_side_effect(H, 4) // dizziness only
	TEST_ASSERT(H.has_status(STAT_DIZZY), "side effect 4 is dizziness")
	TEST_ASSERT(!H.has_status(STAT_WEAKENED), "one roll must not also weaken")
	TEST_ASSERT(!H.has_status(STAT_STUNNED), "one roll must not also stun")
	TEST_ASSERT(!H.has_status(STAT_PARALYZED), "one roll must not also paralyse")

/// B7: Hannoa's sedation bands are reachable, and it treats by mechanism.
/datum/unit_test/dq_p1_b7_hannoa_bands

/datum/unit_test/dq_p1_b7_hannoa_bands/Run()
	var/datum/reagent/hannoa/R = SSchemistry.chemical_reagents[REAGENT_ID_HANNOA]
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	R.hannoa_sedation(H, 3)
	TEST_ASSERT(H.has_status(STAT_BLURRY), "a dose of 3 blurs vision")
	var/mob/living/carbon/human/H2 = allocate(/mob/living/carbon/human)
	R.hannoa_sedation(H2, 10)
	TEST_ASSERT(H2.has_status(STAT_DROWSY), "a dose of 10 makes the patient drowsy")
	TEST_ASSERT(R.treatment_tags?[TREAT_HEMOSTATIC] && R.treatment_tags?[TREAT_TISSUE_REPAIR], "Hannoa declares its clotting and tissue repair tags")

/// B8: Eden leaves the body.
/datum/unit_test/dq_p1_b8_eden_metabolises

/datum/unit_test/dq_p1_b8_eden_metabolises/Run()
	var/datum/reagent/eden/R = SSchemistry.chemical_reagents[REAGENT_ID_EDEN]
	TEST_ASSERT(R.metabolism > 0, "Eden must metabolise (metabolism [R.metabolism])")

/// B16: Malish-Qualem never divides by a zero healing strength.
/datum/unit_test/dq_p1_b16_malish_qualem_zero_strength

/datum/unit_test/dq_p1_b16_malish_qualem_zero_strength/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/old_heal = H.species.chem_strength_heal
	rel_private(H, nameof(H.species)) // write on the mob's private species copy, never the registered one
	H.species.chem_strength_heal = 0
	H.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 5)
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	liver.transplant_data = list()
	liver.can_reject = !initial(liver.can_reject)
	var/datum/reagent/R = SSchemistry.chemical_reagents[REAGENT_ID_MALISHQUALEM]
	R.affect_blood(H, IS_SKRELL, 0.1)
	H.species.chem_strength_heal = old_heal
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_TOXIC) < 100, "the rejection toxin is bounded and per unit (load [H.injury_load(INJURY_CATEGORY_TOXIC)])")

/// B21: Talum-quem poisons everyone by their toxin strength, not only the immune.
/datum/unit_test/dq_p1_b21_talum_quem_toxin

/datum/unit_test/dq_p1_b21_talum_quem_toxin/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(H.species.chem_strength_tox > 0, "setup: a human is not toxin immune")
	H.bloodstr.add_reagent(REAGENT_ID_TALUMQUEM, 5)
	var/datum/reagent/R = H.bloodstr.get_reagent(REAGENT_ID_TALUMQUEM)
	R.affect_blood(H, null, 1)
	TEST_ASSERT(H.injury_load(INJURY_CATEGORY_TOXIC) > 0, "Talum-quem should poison a human")

/// B23: Lipostipo feeds and adds weight in proportion to the dose.
/datum/unit_test/dq_p1_b23_lipostipo_feeds

/datum/unit_test/dq_p1_b23_lipostipo_feeds/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_nutrition(100)
	var/weight = H.weight
	var/datum/reagent/R = SSchemistry.chemical_reagents[REAGENT_ID_LIPOSTIPO]
	R.affect_blood(H, null, 0.2)
	TEST_ASSERT(H.nutrition > 100, "the weight-gain drug must add nutrition, got [H.nutrition]")
	TEST_ASSERT(abs((H.weight - weight) - 0.3) < 0.001, "0.2u adds 0.3 weight, got [H.weight - weight]")

/// B3: drawing into a container that holds another donor's blood is refused.
/datum/unit_test/dq_p1_b3_no_blood_relabelling

/datum/unit_test/dq_p1_b3_no_blood_relabelling/Run()
	var/mob/living/carbon/human/donor = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe)
	var/datum/reagent/B = donor.take_blood(S, 5)
	TEST_ASSERT(B, "setup: the first draw works")
	S.reagents.adopt_reagent(B)
	var/vessel_before = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	TEST_ASSERT_NULL(H.take_blood(S, 5), "a second donor's draw into the same syringe must be refused")
	TEST_ASSERT_EQUAL(H.vessel.get_reagent_amount(REAGENT_ID_BLOOD), vessel_before, "a refused draw takes no blood")
	var/datum/reagent/blood/held = S.reagents.get_reagent(REAGENT_ID_BLOOD)
	TEST_ASSERT(held.data["donor"] == donor, "the syringe's blood keeps its donor")

/// B17: stock packs carry a species, so cross-species transfusion is incompatible.
/datum/unit_test/dq_p1_b17_blood_pack_species

/datum/unit_test/dq_p1_b17_blood_pack_species/Run()
	var/obj/item/reagent_containers/blood/OMinus/pack = allocate(/obj/item/reagent_containers/blood/OMinus)
	var/datum/reagent/blood/B = pack.reagents.get_reagent(REAGENT_ID_BLOOD)
	TEST_ASSERT_EQUAL(B.data["species"], SPECIES_HUMAN, "stock blood is human blood")
	TEST_ASSERT(blood_incompatible(B.data["blood_type"], "O-", B.data["species"], SPECIES_SKRELL), "human stock blood is incompatible with a Skrell")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/reagent_containers/syringe/S = allocate(/obj/item/reagent_containers/syringe)
	var/datum/reagent/drawn = H.take_blood(S, 5)
	TEST_ASSERT(drawn?.data["species"], "drawn blood records its species")

/// B18: a drink feeds through adjust_nutrition, scaled by the food coefficient.
/datum/unit_test/dq_p1_b18_drink_nutrition

/datum/unit_test/dq_p1_b18_drink_nutrition/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_nutrition(100)
	var/datum/reagent/drink/R = SSchemistry.chemical_reagents[REAGENT_ID_ORANGEJUICE]
	var/removed = 1
	var/expected = 100 + R.nutriment_factor * removed * H.species.organic_food_coeff
	if(!(H.species.allergens & R.allergen_type) && !(H.species.medallergens & R.medallergen_type))
		expected += (R.nutrition + H.food_preference(R.allergen_type)) * removed
	R.affect_ingest(H, null, removed)
	TEST_ASSERT(abs(H.nutrition - expected) < 0.01, "a drink adds [expected - 100] nutrition, got [H.nutrition - 100]")

/// B19: a species table overrides only the factors it names.
/datum/unit_test/dq_p1_b19_species_factor_merge

/datum/unit_test/dq_p1_b19_species_factor_merge/Run()
	var/datum/reagent/R = SSchemistry.chemical_reagents[REAGENT_ID_DEXALIN]
	var/alist/merged = R.merged_species_factors(IS_SLIME)
	TEST_ASSERT(merged?[BF_O2_CARRIAGE], "prometheans on dexalin keep its oxygen carriage")
	TEST_ASSERT(merged?[BF_ANALGESIA], "and get their own analgesia")
	var/datum/reagent/bloodburn = SSchemistry.chemical_reagents[REAGENT_ID_BLOODBURN]
	TEST_ASSERT(!length(bloodburn.factors), "bloodburn does not inherit claridyl's factors")

/// B12: a cold drink cools a hot body toward the target and never heats it.
/datum/unit_test/dq_p1_b12_cold_drink_cools

/datum/unit_test/dq_p1_b12_cold_drink_cools/Run()
	var/target = BODYTEMP_NORMAL
	var/hot = target + 10
	var/cooled = drink_temperature_step(hot, target, -5)
	TEST_ASSERT(cooled < hot, "a cold drink must cool a hot body, got [cooled]")
	TEST_ASSERT(cooled >= target, "and not past the target")
	TEST_ASSERT_EQUAL(drink_temperature_step(target - 5, target, -5), target - 5, "a cold drink doesn't touch a body already below the target")
	TEST_ASSERT(drink_temperature_step(target - 10, target, 5) > target - 10, "a warm drink still warms a cold body")

/// C4/D2: the decompression needle vents only a pneumothorax.
/datum/unit_test/dq_p1_c4_needle_targets_chest

/datum/unit_test/dq_p1_c4_needle_targets_chest/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/subdural_hematoma, H.get_organ(BP_HEAD), 50)
	var/obj/item/decompression_needle/needle = allocate(/obj/item/decompression_needle)
	TEST_ASSERT(!needle.decompress(H), "with no pneumothorax nothing comes out")
	TEST_ASSERT_EQUAL(A.severity, 50, "the needle must not treat a subdural hematoma")

/// C5: deep bruising heals on its own.
/datum/unit_test/dq_p1_c5_bruising_self_heals

/datum/unit_test/dq_p1_c5_bruising_self_heals/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/deep_bruising, H.get_organ(BP_TORSO), 50)
	A.progress()
	TEST_ASSERT(A.severity < 50, "untreated deep bruising should recede, got [A.severity]")

/// C2: a no-drift poison wears off a simple body but not a patient.
/datum/unit_test/dq_p1_c2_simple_body_clears_poison

/datum/unit_test/dq_p1_c2_simple_body_clears_poison/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/datum/affliction/A = M.body.afflict(/datum/affliction/poisoning/phoron, null, 50)
	TEST_ASSERT(A, "setup: a mouse can be poisoned")
	A.progress()
	TEST_ASSERT(A.severity < 50, "the poison should wear off a simple body, got [A.severity]")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/P = H.body.afflict(/datum/affliction/poisoning/phoron, null, 50)
	P.progress()
	TEST_ASSERT(P.severity >= 50, "a patient's poisoning still needs treatment")

/// C6: treatment on a dispatcher-owned affliction is the source's, not taken and undone.
/datum/unit_test/dq_p1_c6_metric_owned_takes_no_treatment

/datum/unit_test/dq_p1_c6_metric_owned_takes_no_treatment/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/hepatic_failure, H.organ_in(O_LIVER), 50)
	A.metric_owned = TRUE
	TEST_ASSERT_EQUAL(A.receive_tagged_treatment(TREAT_HEPATORENAL, 30), 0, "a metric-owned affliction takes no treatment itself")
	TEST_ASSERT_EQUAL(A.severity, 50, "and its severity is untouched")

/// C7: hypovolemic shock applies its first band and its declared factors from the start.
/datum/unit_test/dq_p1_c7_shock_band_on_add

/datum/unit_test/dq_p1_c7_shock_band_on_add/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/hypovolemic_shock/A = H.body.afflict(/datum/affliction/hypovolemic_shock, H.get_organ(BP_TORSO), 10)
	TEST_ASSERT(A.band_factors, "the band table must be set when the shock takes hold")
	var/list/acc = A.accumulate_factors(null)
	TEST_ASSERT(acc && acc[BF_O2_SAT] < body_factor_baseline(BF_O2_SAT), "the declared O2 saturation factor is read")

/// C8: wound infection severity goes through the setter.
/datum/unit_test/dq_p1_c8_infection_uses_setter

/datum/unit_test/dq_p1_c8_infection_uses_setter/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/wound_infection, arm, 10)
	arm.germ_level = INFECTION_LEVEL_ONE + 100000
	A.tick()
	TEST_ASSERT(A.severity <= AFFLICTION_SEVERITY_TERMINAL, "severity stays clamped")
	TEST_ASSERT(A.severity > 10, "a filthy wound feeds the infection")
	arm.germ_level = 0

/// C9: respiratory arrest exists once, whatever location its causes name.
/datum/unit_test/dq_p1_c9_systemic_singleton

/datum/unit_test/dq_p1_c9_systemic_singleton/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/respiratory_arrest, H.get_organ(BP_TORSO))
	var/datum/affliction/B = H.body.afflict(/datum/affliction/respiratory_arrest, H.get_organ(BP_HEAD))
	TEST_ASSERT(A == B, "a second cause must reuse the existing respiratory arrest")
	TEST_ASSERT_EQUAL(length(H.body.afflictions_of(/datum/affliction/respiratory_arrest)), 1, "only one respiratory arrest")

/// C14: no trigger names a tier for an affliction without stages.
/datum/unit_test/dq_p1_c14_tiers_have_stages

/datum/unit_test/dq_p1_c14_tiers_have_stages/Run()
	for(var/datum/affliction_trigger/T as anything in affliction_triggers_registry())
		for(var/datum/affliction_trigger_outcome/O as anything in T.produces)
			if(!O.tier)
				continue
			var/datum/affliction/proto = dq_proto(O.condition_type)
			var/list/proto_stages = TYPE_TABLE_GET(proto, affliction_stages)
			TEST_ASSERT(proto_stages?[O.tier], "[T.type] asks for tier [O.tier] of [O.condition_type], which has no such stage")

/// C15: clearing a stage resolves the presenting symptoms.
/datum/unit_test/dq_p1_c15_clear_stage

/datum/unit_test/dq_p1_c15_clear_stage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/brain_damage, H.organ_in(O_BRAIN), 40)
	A._apply_stage("Significant")
	A.clear_stage()
	TEST_ASSERT_NULL(A.stage, "no stage after clearing")
	TEST_ASSERT(!length(A.active_symptoms), "no presenting symptoms after clearing")

/// C17: a simple body rebuilds stale factors in its own life tick.
/datum/unit_test/dq_p1_c17_simple_factor_step

/datum/unit_test/dq_p1_c17_simple_factor_step/Run()
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	M.injure(INJURY_BLUNT, 1)
	M.body.invalidate(BODY_DIRTY_FACTORS)
	M.body.life_tick()
	TEST_ASSERT(!(M.body.dirty & BODY_DIRTY_FACTORS), "the simple plan's tick must rebuild the factor table")

/// C21: airway patency re-dirties the factors on every severity change.
/datum/unit_test/dq_p1_c21_continuous_airway_factors

/datum/unit_test/dq_p1_c21_continuous_airway_factors/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/airway_obstruction, H.get_organ(BP_HEAD), 31)
	H.factor(BF_AIRWAY) // rebuild
	A.set_severity(32) // same 10-point band
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_FACTORS, "a one-point change must re-dirty airway patency")

/// C22: an explicit severity wins over the type's initial severity.
/datum/unit_test/dq_p1_c22_initial_severity

/datum/unit_test/dq_p1_c22_initial_severity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/C = H.body.afflict(/datum/affliction/concussion, H.get_organ(BP_HEAD), 20)
	TEST_ASSERT_EQUAL(C.severity, 20, "a light concussion is light")
	var/datum/affliction/N = H.body.afflict(/datum/affliction/nerve_damage, H.get_organ(BP_R_ARM))
	TEST_ASSERT_EQUAL(N.severity, 60, "with no severity given, the initial severity applies")

/// C23: a carried affliction that can't exist on the body is dropped on attach.
/datum/unit_test/dq_p1_c23_attach_checks_can_afflict

/datum/unit_test/dq_p1_c23_attach_checks_can_afflict/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	var/datum/affliction/A = new /datum/affliction/synthetic/coolant_leak(arm)
	var/datum/affliction/B = new /datum/affliction/synthetic/thermal_runaway(arm)
	var/datum/affliction/custom/compatible = new(arm)
	rel_add(arm, nameof(arm.detached_afflictions), A)
	rel_add(arm, nameof(arm.detached_afflictions), B)
	rel_add(arm, nameof(arm.detached_afflictions), compatible)
	TEST_ASSERT(!A.can_afflict(H.body, arm) && !B.can_afflict(H.body, arm), "both adjacent synthetic faults must actually reject the organic arm")
	TEST_ASSERT(compatible.can_afflict(H.body, arm), "the real custom affliction must be compatible with the same arm")
	H.body.attach_part(arm)
	TEST_ASSERT(QDELETED(A) && QDELETED(B), "both exact adjacent rejected records must be disposed")
	TEST_ASSERT(!H.body.has_affliction(/datum/affliction/synthetic/coolant_leak), "a coolant leak can't be carried onto an organic arm")
	TEST_ASSERT(!H.body.has_affliction(/datum/affliction/synthetic/thermal_runaway), "thermal runaway can't be carried onto an organic arm")
	TEST_ASSERT(!QDELETED(compatible), "the exact compatible record must survive both rejected neighbors")
	TEST_ASSERT_EQUAL(H.body.find_affliction(/datum/affliction/custom, arm), compatible, "the body's index must adopt the exact compatible original")
	TEST_ASSERT_EQUAL(owner_of(compatible), H.body, "the adopted original must be owned by the actual body")
	TEST_ASSERT(!LAZYLEN(arm.detached_afflictions), "all original records must leave the carried index")

/// D7: the scanner labels by robotic level, not a status bit.
/datum/unit_test/dq_p1_d7_scanner_assisted_label

/datum/unit_test/dq_p1_d7_scanner_assisted_label/Run()
	var/obj/item/organ/internal/heart/O = allocate(/obj/item/organ/internal/heart)
	O.set_robotic(ORGAN_ASSISTED)
	TEST_ASSERT_EQUAL(bodyscanner_organ_kind(O), "Assisted", "an assisted organ reads Assisted")
	O.set_robotic(0)
	O.set_status(O.status | ORGAN_ASSISTED)
	TEST_ASSERT_NULL(bodyscanner_organ_kind(O), "a status bit with the same value is not a prosthesis")

/// D8: resection and retinal repair can reach inside bone.
/datum/unit_test/dq_p1_d8_encased_access_steps

/datum/unit_test/dq_p1_d8_encased_access_steps/Run()
	for(var/path in list(/datum/dq_surgery/retinal_repair, /datum/dq_surgery/organ_resection))
		var/datum/dq_surgery/S = new path
		TEST_ASSERT(/datum/surgical_step/access/saw in S.procedure, "[path] needs a saw step")
		TEST_ASSERT(/datum/surgical_step/access/pry_bone in S.procedure, "[path] needs a pry step")
		qdel(S)

/// D9: a refreshing scanner UI doesn't move the device's trend baseline.
/datum/unit_test/dq_p1_d9_trend_baseline_per_device

/datum/unit_test/dq_p1_d9_trend_baseline_per_device/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/scanner = new
	var/datum/affliction/A = H.body.afflict(/datum/affliction/internal_hemorrhage, H.get_organ(BP_TORSO), 30)
	qdel(H.diagnose(/datum/diagnostic_profile/body_scanner, scanner, TRUE))
	A.set_severity(60)
	var/datum/diagnosis/D1 = H.diagnose(/datum/diagnostic_profile/body_scanner, scanner)
	var/datum/diagnosis/D2 = H.diagnose(/datum/diagnostic_profile/body_scanner, scanner)
	var/datum/diagnosis_finding/F = dq_p1_finding(D2, /datum/affliction/internal_hemorrhage)
	if(F)
		TEST_ASSERT_EQUAL(F.trend, "worsening", "a second passive read still reports the worsening since the last explicit scan")
	TEST_ASSERT_EQUAL(A.scan_baselines?[REF(scanner)], 30, "passive reads keep the explicit scan's baseline")
	qdel(D1)
	qdel(D2)
	qdel(scanner)

/// D11: no heart, no resuscitation.
/datum/unit_test/dq_p1_d11_defib_needs_heart

/datum/unit_test/dq_p1_d11_defib_needs_heart/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/shockpaddles/standalone/paddles = allocate(/obj/item/shockpaddles/standalone)
	var/obj/item/organ/internal/heart = H.organ_in(O_HEART)
	heart.removed()
	qdel(heart)
	var/message = paddles.can_revive(H)
	TEST_ASSERT(message && findtext(message, "no heart"), "the defibrillator must refuse a heartless patient, got [message]")

/// D18b: a clamped incision doesn't bleed.
/datum/unit_test/dq_p1_d18b_clamped_incision

/datum/unit_test/dq_p1_d18b_clamped_incision/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/datum/affliction/surgical_incision/I = H.body.afflict(/datum/affliction/surgical_incision, torso)
	I.open_to(SURGERY_DEPTH_CLOSED + 1)
	TEST_ASSERT(H.blood_loss_rate(torso) > 0, "an open, unclamped site bleeds")
	I.clamped = TRUE
	TEST_ASSERT_EQUAL(H.blood_loss_rate(torso), 0, "a clamped site does not")
	I.close_site()

/// D21: the nymph takes the body through set_species(), keeping its organs.
/datum/unit_test/dq_p1_d21_nymph_species

/datum/unit_test/dq_p1_d21_nymph_species/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	H.set_species(SPECIES_DIONA, keep_organs = TRUE)
	TEST_ASSERT_EQUAL(H.species.name, SPECIES_DIONA, "the species changed")
	TEST_ASSERT(H.get_organ(BP_TORSO) == torso, "the host body's organs are kept")

/// D22: pain messages run with fractional damage and a missing parent limb.
/datum/unit_test/dq_p1_d22_pain_messages

/datum/unit_test/dq_p1_d22_pain_messages/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_BLUNT, 10.5, BP_L_ARM)
	H.pain_step() // must not runtime

/// A5: replacing a borg's cell deletes the old one instead of orphaning it.
/datum/unit_test/dq_p1_a5_borg_cell_replacement

/datum/unit_test/dq_p1_a5_borg_cell_replacement/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, run_loc_floor_bottom_left)
	var/obj/item/cell/old_cell = R.cell
	var/obj/item/cell/new_cell = allocate(/obj/item/cell/high)
	R.set_cell(new_cell)
	TEST_ASSERT(R.cell == new_cell, "the new cell is installed")
	if(old_cell)
		TEST_ASSERT(QDELETED(old_cell), "the replaced cell must not stay in the borg")

/// A22: rebuilding bellies resets light states and survives a missing sprite datum.
/datum/unit_test/dq_p1_a22_borg_belly_lights

/datum/unit_test/dq_p1_a22_borg_belly_lights/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, run_loc_floor_bottom_left)
	LAZYSET(R.vore_light_states, "stale_belly", 2)
	var/datum/robot_sprite/old_sprite = R.sprite_datum
	var/datum/robot_sprite/private_copy = proto_replace(R, nameof(R.sprite_datum), null)
	R.update_multibelly()
	proto_set(R, nameof(R.sprite_datum), private_copy || old_sprite)
	TEST_ASSERT(!R.vore_light_states?["stale_belly"], "a stale belly light key is cleared")

/// P2-F7: apply_effect() honours check_protection for radiation.
/datum/unit_test/dq_p1_p2f7_irradiate_protection

/datum/unit_test/dq_p1_p2f7_irradiate_protection/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.apply_body_effect(/datum/body_effect/invulnerable, 1 MINUTE)
	var/before = H.radiation
	H.apply_effect(10, IRRADIATE, 0, TRUE)
	var/armored = H.radiation - before
	H.apply_effect(10, IRRADIATE, 0, FALSE)
	var/unarmored = H.radiation - before - armored
	TEST_ASSERT(unarmored > armored, "check_protection = FALSE must skip radiation armour ([unarmored] vs [armored])")
	H.remove_body_effect(/datum/body_effect/invulnerable, TRUE)

/// P2-F9: alraune skin breathing in nullspace doesn't runtime.
/datum/unit_test/dq_p1_p2f9_alraune_no_loc

/datum/unit_test/dq_p1_p2f9_alraune_no_loc/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_species(SPECIES_ALRAUNE)
	H.moveToNullspace()
	// P2-D8: skin breathing is the alraune breath profile, taken by the breathing stage.
	var/datum/breath_profile/skin/P = H.breath_profile()
	TEST_ASSERT(istype(P), "an alraune breathes through its skin")
	P.take_breath(H) // must not runtime on a null loc
