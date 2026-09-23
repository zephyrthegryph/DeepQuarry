// Body factors: the unified stat layer (code/modules/body/factors.dm).
// Combine math, lazy storage, dirty recompute on every source kind, and the
// consumers that read factors instead of walking modifier lists.

/// A test-only modifier touching many consumers at once.
/datum/modifier/dq_test_factors
	name = "test factors"
	factors = alist(BF_EVASION = 30, BF_ATTACK_SPEED = 0.5, BF_MELEE_DAMAGE = 1.5, BF_DISABLE_DURATION = 0.5, BF_INCOMING_PHYSICAL = 0.5, BF_ENDURANCE_FLAT = 10, BF_ARMOR(INJURY_BLUNT) = 25, BF_SIEMENS = 0.5, BF_ACCURACY = -40, BF_DISPERSION = 2)

/datum/modifier/dq_test_slowdown
	name = "test slowdown"
	stacks = MODIFIER_STACK_ALLOWED
	factors = alist(BF_SLOWDOWN = 2)

/datum/modifier/dq_test_haste
	name = "test haste"
	factors = alist(BF_HASTE = 1)

/datum/modifier/dq_test_healing
	name = "test healing"
	factors = alist(BF_HEALING_RECEIVED = 2)

/datum/modifier/dq_test_pain_block
	name = "test pain immunity"
	factors = alist(BF_PAIN_IMMUNITY = 1, BF_ACTION_BLOCKS = ACTION_BLOCK_HOLD_LEFT)

/datum/unit_test/proc/dq_near(a, b, epsilon = 0.001)
	return abs(a - b) < epsilon


/// The combine rules and the worked example from the design doc.
/datum/unit_test/dq_body_factor_combine_math

/datum/unit_test/dq_body_factor_combine_math/Run()
	// Multiplicative: f at scale s contributes 1 - (1 - f) * s.
	var/list/acc = body_factor_accumulate(null, alist(BF_AIRWAY = 0.1), 0.5)
	TEST_ASSERT(dq_near(acc[BF_AIRWAY], 0.55), "partial choking (0.1 at severity 50) should leave 0.55 airway, got [acc[BF_AIRWAY]]")
	acc = body_factor_accumulate(acc, alist(BF_AIRWAY = 0.2), 0.6)
	TEST_ASSERT(dq_near(acc[BF_AIRWAY], 0.55 * 0.52), "choking plus swelling should multiply to 0.286, got [acc[BF_AIRWAY]]")

	// Additive: f * s, summed.
	acc = body_factor_accumulate(null, alist(BF_ANALGESIA = 60), 0.5)
	acc = body_factor_accumulate(acc, alist(BF_ANALGESIA = 20), 1)
	TEST_ASSERT(dq_near(acc[BF_ANALGESIA], 50), "analgesia should sum 30 + 20, got [acc[BF_ANALGESIA]]")

	// Max: the highest contribution and the baseline win (forced pulse starts at -1).
	acc = body_factor_accumulate(null, alist(BF_PULSE_SET = 2), 1)
	acc = body_factor_accumulate(acc, alist(BF_PULSE_SET = 1), 1)
	TEST_ASSERT_EQUAL(acc[BF_PULSE_SET], 2, "max rule should keep the highest value")

	// Flags: OR of every contribution.
	acc = body_factor_accumulate(null, alist(BF_ACTION_BLOCKS = ACTION_BLOCK_SPEECH), 0.1)
	acc = body_factor_accumulate(acc, alist(BF_ACTION_BLOCKS = ACTION_BLOCK_SURGERY), 1)
	TEST_ASSERT_EQUAL(acc[BF_ACTION_BLOCKS], ACTION_BLOCK_SPEECH | ACTION_BLOCK_SURGERY, "flags should OR together")

	// A multiplier never goes negative, however large the dose.
	acc = body_factor_accumulate(null, alist(BF_AIRWAY = 0.2), 4)
	TEST_ASSERT_EQUAL(acc[BF_AIRWAY], 0, "an overscaled multiplier should floor at 0")

	// Bounds clamp at finalize; an all-baseline list becomes null.
	acc = body_factor_accumulate(null, alist(BF_SLOWDOWN = 50), 1)
	acc = body_factor_finalize(acc)
	TEST_ASSERT_EQUAL(acc[BF_SLOWDOWN], 20, "slowdown should clamp to its upper bound")
	acc = body_factor_accumulate(null, alist(BF_SLOWDOWN = 1), 1)
	acc = body_factor_accumulate(acc, alist(BF_SLOWDOWN = -1), 1)
	TEST_ASSERT_NULL(body_factor_finalize(acc), "contributions that cancel out should leave no list")

	// Every factor is registered.
	var/list/defs = body_factor_defs()
	for(var/id in 1 to BF_COUNT)
		TEST_ASSERT_NOTNULL(defs[id], "body factor [id] has no definition")


/// Healthy bodies keep no factor list; a source allocates one, removing it frees it.
/datum/unit_test/dq_body_factor_lazy_storage

/datum/unit_test/dq_body_factor_lazy_storage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.body.recompute_factors()
	TEST_ASSERT_NULL(H.body.factors, "a healthy human should keep no factor list")
	TEST_ASSERT_EQUAL(H.factor(BF_AIRWAY), 1, "an untouched multiplier reads its baseline")
	TEST_ASSERT_EQUAL(H.factor(BF_PULSE_SET), -1, "an untouched max factor reads its baseline")

	var/datum/modifier/M = H.add_modifier(/datum/modifier/dq_test_slowdown)
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_FACTORS, "adding a modifier with factors should mark the body dirty")
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 2, "the modifier's slowdown should apply")
	TEST_ASSERT_NOTNULL(H.body.factors, "a contributing source should allocate the list")

	H.remove_specific_modifier(M, TRUE)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0, "removing the modifier should restore the baseline")
	TEST_ASSERT_NULL(H.body.factors, "back at baseline, the list should be freed")


/// Modifiers stack at full value; reading does no work when nothing changed.
/datum/unit_test/dq_body_factor_modifier_recompute

/datum/unit_test/dq_body_factor_modifier_recompute/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.add_modifier(/datum/modifier/dq_test_slowdown)
	H.add_modifier(/datum/modifier/dq_test_slowdown)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 4, "two stacked modifiers should add")
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_FACTORS), "a read should leave the factors clean")
	H.remove_modifiers_of_type(/datum/modifier/dq_test_slowdown, TRUE)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0, "removing both should restore the baseline")

	// set_factors() swaps a running modifier's table.
	var/datum/modifier/M = H.add_modifier(/datum/modifier/dq_test_healing)
	TEST_ASSERT_EQUAL(H.factor(BF_HEALING_RECEIVED), 2, "healing modifier should apply")
	M.set_factors(alist(BF_HEALING_RECEIVED = 0.5))
	TEST_ASSERT_EQUAL(H.factor(BF_HEALING_RECEIVED), 0.5, "set_factors should recompute the holder")


/// Afflictions scale by severity and recompute only on a band crossing.
/datum/unit_test/dq_body_factor_affliction_bands

/datum/unit_test/dq_body_factor_affliction_bands/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/airway_edema)
	TEST_ASSERT_NOTNULL(A, "airway edema should afflict")
	A.set_severity(100)
	TEST_ASSERT(dq_near(H.factor(BF_HEART_RATE), 20), "edema at full severity should raise the heart rate by 20, got [H.factor(BF_HEART_RATE)]")
	TEST_ASSERT(dq_near(H.factor(BF_BP_SYSTOLIC), -15), "edema at full severity should drop systolic pressure by 15")

	A.set_severity(50)
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_FACTORS, "crossing a severity band should mark the factors dirty")
	TEST_ASSERT(dq_near(H.factor(BF_HEART_RATE), 10), "edema at half severity should give half the heart rate, got [H.factor(BF_HEART_RATE)]")

	A.set_severity(52)
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_FACTORS), "a change inside the same band should not recompute")

	A.cure()
	TEST_ASSERT_EQUAL(H.factor(BF_HEART_RATE), 0, "curing should remove the contribution")


/// Staged afflictions use the stage's table at full value.
/datum/unit_test/dq_body_factor_affliction_stages

/datum/unit_test/dq_body_factor_affliction_stages/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	var/datum/affliction/overdose/hyperzine/od = H.body.afflict(/datum/affliction/overdose/hyperzine, B)
	TEST_ASSERT_NOTNULL(od, "hyperzine overdose should afflict")
	var/list/stages = od.get_stages()
	var/last_stage = stages[length(stages)]
	od._apply_stage(last_stage)
	var/list/table = stages[last_stage]["factors"]
	TEST_ASSERT_NOTNULL(table, "the worst overdose stage should carry a factor table")
	TEST_ASSERT(dq_near(H.factor(BF_ACCURACY), table[BF_ACCURACY]), "the stage table should apply unscaled ([H.factor(BF_ACCURACY)] vs [table[BF_ACCURACY]])")


/// Reagents contribute at their dose scale and recompute when volumes change.
/datum/unit_test/dq_body_factor_reagent_dose

/datum/unit_test/dq_body_factor_reagent_dose/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.bloodstr.add_reagent(REAGENT_ID_INAPROVALINE, DQ_CHEM_STANDARD_DOSE)
	TEST_ASSERT(dq_near(H.factor(BF_STABILIZATION), 15), "a standard dose of inaprovaline should stabilise at 15, got [H.factor(BF_STABILIZATION)]")
	TEST_ASSERT(dq_near(H.factor(BF_ANALGESIA), 10 * H.species.chem_strength_pain), "inaprovaline's analgesia should scale by the species")

	H.bloodstr.add_reagent(REAGENT_ID_INAPROVALINE, DQ_CHEM_STANDARD_DOSE)
	TEST_ASSERT(dq_near(H.factor(BF_STABILIZATION), 30), "a double dose should double the contribution, got [H.factor(BF_STABILIZATION)]")

	H.bloodstr.clear_reagents()
	TEST_ASSERT_EQUAL(H.factor(BF_STABILIZATION), 0, "clearing the reagents should remove the contribution")

	// A stimulant speeds movement and cuts penalties.
	H.bloodstr.add_reagent(REAGENT_ID_HYPERZINE, DQ_CHEM_STANDARD_DOSE)
	TEST_ASSERT(dq_near(H.factor(BF_SLOWDOWN), -1), "hyperzine should give -1 slowdown, got [H.factor(BF_SLOWDOWN)]")
	TEST_ASSERT(dq_near(H.factor(BF_PENALTY_SCALE), 0.5), "hyperzine should halve movement penalties")


/// Worn equipment contributes while equipped outside the hands.
/datum/unit_test/dq_body_factor_worn_equipment

/datum/unit_test/dq_body_factor_worn_equipment/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/shoes/boots = allocate(/obj/item/clothing/shoes/black)
	boots.worn_factors = alist(BF_SLOWDOWN = 1.5)

	H.put_in_hands(boots)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0, "gear held in the hands should not contribute")

	H.drop_from_inventory(boots)
	TEST_ASSERT(H.equip_to_slot_if_possible(boots, slot_shoes, disable_warning = TRUE), "the boots should equip")
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 1.5, "worn boots should add their slowdown")

	H.drop_from_inventory(boots)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0, "taking the boots off should remove it")


/// Species baselines and traits.
/datum/unit_test/dq_body_factor_species_baseline

/datum/unit_test/dq_body_factor_species_baseline/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.set_species(SPECIES_UNATHI)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0.5, "unathi should move with their species slowdown")
	TEST_ASSERT(dq_near(H.factor(BF_METABOLISM), 0.85), "unathi should metabolise at their species rate")
	TEST_ASSERT_EQUAL(H.species.baseline_factor(BF_SLOWDOWN), 0.5, "the species baseline should read on its own")

	// Traits that change the same factor conflict, like traits changing the same var.
	var/datum/trait/slow = GLOB.all_traits[/datum/trait/negative/speed_slow]
	var/datum/trait/fast = GLOB.all_traits[/datum/trait/positive/speed_fast]
	TEST_ASSERT(check_trait_conflict(slow, fast), "two speed traits should conflict")


/// The consumers: evasion, attack speed, melee, stuns, incoming injury,
/// endurance, armour, conductivity, ranged accuracy, movement.
/datum/unit_test/dq_body_factor_consumers

/datum/unit_test/dq_body_factor_consumers/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	var/base_evasion = H.get_evasion()
	var/base_attack = H.get_attack_speed()
	var/base_endurance = H.get_endurance()
	var/base_armor = H.injury_armor(INJURY_BLUNT, chest)
	var/base_siemens = H.get_siemens_coefficient_organ(chest)
	var/base_blunt = H.injure(INJURY_BLUNT, 4, BP_TORSO, flags = INJURE_SILENT)

	H.add_modifier(/datum/modifier/dq_test_factors)
	TEST_ASSERT_EQUAL(H.get_evasion(), base_evasion + 30, "evasion should read BF_EVASION")
	TEST_ASSERT(dq_near(H.get_attack_speed(), base_attack * 0.5), "attack delay should read BF_ATTACK_SPEED")
	TEST_ASSERT_EQUAL(H.get_endurance(), base_endurance + 10, "endurance should read BF_ENDURANCE_FLAT")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, chest), base_armor + 25, "armour should read BF_ARMOR(INJURY_BLUNT)")
	TEST_ASSERT(dq_near(H.get_siemens_coefficient_organ(chest), base_siemens * 0.5), "conductivity should read BF_SIEMENS")
	var/blunt = H.injure(INJURY_BLUNT, 4, BP_TORSO, flags = INJURE_SILENT)
	TEST_ASSERT(dq_near(blunt, base_blunt * 0.5), "physical injury should read BF_INCOMING_PHYSICAL ([base_blunt] -> [blunt])")

	H.SetStunned(0)
	H.Stun(10)
	TEST_ASSERT_EQUAL(H.stunned, 5, "stuns should read BF_DISABLE_DURATION")

	// Simple mobs read the same factors for ranged combat.
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/animal/passive/mouse)
	var/base_accuracy = S.calculate_accuracy()
	var/base_dispersion = S.calculate_dispersion()
	S.add_modifier(/datum/modifier/dq_test_factors)
	TEST_ASSERT_EQUAL(S.calculate_accuracy(), base_accuracy - 40, "simple mob accuracy should read BF_ACCURACY")
	TEST_ASSERT_EQUAL(S.calculate_dispersion(), base_dispersion + 2, "simple mob dispersion should read BF_DISPERSION")


/// Movement delay reads BF_SLOWDOWN, BF_PENALTY_SCALE and BF_HASTE.
/datum/unit_test/dq_body_factor_movement

/datum/unit_test/dq_body_factor_movement/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/base = H.movement_delay()
	H.add_modifier(/datum/modifier/dq_test_slowdown)
	var/slowed = H.movement_delay()
	TEST_ASSERT(dq_near(slowed - base, 2), "a slowdown factor of 2 should add 2 delay ([base] -> [slowed])")

	H.add_modifier(/datum/modifier/dq_test_haste)
	TEST_ASSERT(H.movement_delay() < base, "haste should ignore slowdown")


/// mend() reads BF_HEALING_RECEIVED; pain immunity and blocked hands work.
/datum/unit_test/dq_body_factor_healing_and_blocks

/datum/unit_test/dq_body_factor_healing_and_blocks/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.injure(INJURY_BLUNT, 30, BP_TORSO, flags = INJURE_SILENT | INJURE_IGNORE_RESISTANCE)
	var/plain = H.mend(TREAT_TISSUE_REPAIR, 2, BP_TORSO)
	H.add_modifier(/datum/modifier/dq_test_healing)
	var/boosted = H.mend(TREAT_TISSUE_REPAIR, 2, BP_TORSO)
	TEST_ASSERT(plain > 0, "tissue repair should mend the bruised chest")
	TEST_ASSERT(dq_near(boosted, plain * 2, 0.01), "doubled healing received should mend twice as much ([plain] -> [boosted])")

	TEST_ASSERT(H.can_feel_pain(), "a human should feel pain")
	H.add_modifier(/datum/modifier/dq_test_pain_block)
	TEST_ASSERT(!H.can_feel_pain(), "pain immunity should read BF_PAIN_IMMUNITY")

	var/obj/item/tool/wrench/W = allocate(/obj/item/tool/wrench)
	H.put_in_l_hand(W)
	H.body.life_tick()
	TEST_ASSERT(H.get_equipped_item(SLOT_ID_HAND_L) != W, "a blocked left hand should drop what it holds")


/// Energy shields keep their charge-dependent resistance (injure() stage 2, COMSIG_LIVING_SHIELD_INJURY).
/datum/unit_test/dq_body_factor_energy_shield

/datum/unit_test/dq_body_factor_energy_shield/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/modifier/shield_projection/bruteburn/S = H.add_modifier(/datum/modifier/shield_projection/bruteburn)
	TEST_ASSERT_NOTNULL(S, "the shield modifier should apply")
	var/obj/item/cell/C = allocate(/obj/item/cell/high)
	S.energy_source = C
	S.damage_cost = 1
	TEST_ASSERT_EQUAL(H.injure(INJURY_BLUNT, 5, BP_TORSO, flags = INJURE_SILENT), 0, "a fully charged brute shield should absorb everything")
	TEST_ASSERT(C.charge < C.maxcharge, "absorbing should drain the cell")
	C.charge = 0
	TEST_ASSERT(H.injure(INJURY_BLUNT, 5, BP_TORSO, flags = INJURE_SILENT) > 0, "an empty shield should let the hit through")
	TEST_ASSERT(dq_near(H.factor(BF_SIEMENS), 2), "the shield's conductivity is an ordinary factor")


/// The reference book documents a source straight from its table.
/datum/unit_test/dq_body_factor_book_text

/datum/unit_test/dq_body_factor_book_text/Run()
	var/list/lines = body_factor_describe(alist(BF_AIRWAY = 0.2, BF_HEART_RATE = 15), " at full severity")
	TEST_ASSERT_EQUAL(length(lines), 2, "one line per factor")
	TEST_ASSERT_EQUAL(lines[1], "Airway: -80% at full severity", "multipliers print as a percent change")
	TEST_ASSERT_EQUAL(lines[2], "Heart rate: +15 bpm at full severity", "additive factors print with their unit")
	// Every authored reagent and affliction table only names real factors.
	for(var/id in SSchemistry.chemical_reagents)
		var/datum/reagent/R = SSchemistry.chemical_reagents[id]
		for(var/factor_id in R.factors)
			TEST_ASSERT(isnum(factor_id) && factor_id >= 1 && factor_id <= BF_COUNT, "[R.type] has an invalid factor id [factor_id]")
