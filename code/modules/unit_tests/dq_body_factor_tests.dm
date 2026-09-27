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
	TEST_ASSERT_EQUAL(om_track_change(H.body, OM_BODY_CHANGE_EFFECTIVE_FACTORS), 0, "effective factor revision starts when observed")

	A.set_severity(50)
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_FACTORS, "crossing a severity band should mark the factors dirty")
	TEST_ASSERT_EQUAL(om_change_revision(H.body, OM_BODY_CHANGE_EFFECTIVE_FACTORS), 0, "source invalidation does not claim an effective value change")
	TEST_ASSERT(dq_near(H.factor(BF_HEART_RATE), 10), "edema at half severity should give half the heart rate, got [H.factor(BF_HEART_RATE)]")
	TEST_ASSERT_EQUAL(om_change_revision(H.body, OM_BODY_CHANGE_EFFECTIVE_FACTORS), 1, "recompute publishes one effective factor change")

	A.set_severity(52)
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_FACTORS), "a change inside the same band should not recompute")

	A.cure()
	TEST_ASSERT_EQUAL(H.factor(BF_HEART_RATE), 0, "curing should remove the contribution")

/datum/dq_test_factor_view_counter
	var/changes = 0
	var/last_old
	var/last_new

/datum/dq_test_factor_view_counter/proc/on_factor_view_changed(datum/source, old_value, new_value)
	SIGNAL_HANDLER
	changes++
	var/list/previous = old_value
	var/list/current = new_value
	last_old = previous?[BF_HEART_RATE] || 0
	last_new = current?[BF_HEART_RATE] || 0

/datum/unit_test/dq_body_factor_observed_view
	needs_test_block = FALSE

/datum/unit_test/dq_body_factor_observed_view/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/A = H.body.afflict(/datum/affliction/airway_edema)
	TEST_ASSERT_NOTNULL(A, "airway edema should afflict")
	A.set_severity(100)
	var/datum/dq_test_factor_view_counter/counter = new
	counter.RegisterSignal(H.body, COMSIG_BODY_FACTOR_VIEW_CHANGED, TYPE_PROC_REF(/datum/dq_test_factor_view_counter, on_factor_view_changed))
	var/datum/object_model/derived_watch/watch = H.body.observe_factor_view(counter)
	TEST_ASSERT_NOTNULL(watch, "factor view should be observed")
	var/list/first = H.body.factor_view()
	TEST_ASSERT(dq_near(first[BF_HEART_RATE], 20), "initial view should contain the effective factor")
	first[BF_HEART_RATE] = -999
	TEST_ASSERT(dq_near(H.body.factor_view()[BF_HEART_RATE], 20), "caller mutation changed the cached factor view")
	A.set_severity(50)
	var/list/second = H.body.factor_view()
	TEST_ASSERT(dq_near(second[BF_HEART_RATE], 10), "view should refresh on first read after affliction change")
	TEST_ASSERT_EQUAL(counter.changes, 1, "effective change should notify once")
	TEST_ASSERT(dq_near(counter.last_old, 20) && dq_near(counter.last_new, 10), "notification should carry old and new values")
	A.set_severity(52)
	H.body.factor_view()
	TEST_ASSERT_EQUAL(counter.changes, 1, "same factor band should not notify")
	var/datum/modifier/M = H.add_modifier(/datum/modifier/dq_test_healing)
	var/list/with_modifier = H.body.factor_view()
	TEST_ASSERT(dq_near(with_modifier[BF_HEALING_RECEIVED], 2), "modifier should appear on the next derived read")
	M.set_factors(alist(BF_HEALING_RECEIVED = 0.5))
	var/list/changed_modifier = H.body.factor_view()
	TEST_ASSERT(dq_near(changed_modifier[BF_HEALING_RECEIVED], 0.5), "modifier setter should refresh the view without a tick")
	qdel(counter)

/// An observed factor view should ignore severity writes that cannot change
/// the rounded contribution, while still refreshing on a band crossing.
/datum/unit_test/dq_body_factor_observed_band_gate
	needs_test_block = FALSE

/datum/unit_test/dq_body_factor_observed_band_gate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/airway_edema/A = H.body.afflict(/datum/affliction/airway_edema)
	TEST_ASSERT_NOTNULL(A, "airway edema should afflict")
	A.set_severity(98)
	var/datum/object_model/derived_watch/watch = H.body.observe_factor_view(src)
	TEST_ASSERT_NOTNULL(watch, "factor view should be observed")
	H.body.factor_view()
	var/datum/object_model/change_state/state = om_change_state_for(H.body)
	var/list/entry = state.views[/datum/object_model/behaviour/body_factor_view]
	TEST_ASSERT(!entry[OM_DERIVED_DIRTY], "initial factor view should be clean")
	A.set_severity(99)
	TEST_ASSERT(!entry[OM_DERIVED_DIRTY], "same-band severity should not dirty the factor view")
	TEST_ASSERT(dq_near(H.body.factor_view()[BF_HEART_RATE], 19.6), "same-band factor should retain its value")
	A.set_severity(50)
	TEST_ASSERT(entry[OM_DERIVED_DIRTY], "crossing a factor band should dirty the observed view")
	TEST_ASSERT_EQUAL(H.body.factor_view()[BF_HEART_RATE], 10, "cross-band factor should refresh on read")
	qdel(watch)


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
	boots.set_worn_factors(alist(BF_SLOWDOWN = 0.75))
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0.75, "a worn item's setter should refresh factors without caller invalidation")
	boots.set_worn_factors(null)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0, "clearing a worn item's factors should refresh the body")

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
	var/alist/extra = alist(BF_SLOWDOWN = 1)
	H.species.grant_factors(extra, H)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 1.5, "granting species factors should refresh the matching body's cache")
	H.species.revoke_factors(extra, H)
	TEST_ASSERT_EQUAL(H.factor(BF_SLOWDOWN), 0.5, "revoking species factors should refresh the matching body's cache")

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

/datum/unit_test/dq_body_factor_shield_signal_lifetime

/datum/unit_test/dq_body_factor_shield_signal_lifetime/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/baseline = H.factor(BF_SIEMENS)
	var/datum/modifier/shield_projection/bruteburn/S = H.add_modifier(/datum/modifier/shield_projection/bruteburn)
	TEST_ASSERT(S, "shield modifier could not be applied")
	TEST_ASSERT(om_has_link(S, /datum/object_model/relation/shield_projection_holder, H), "active shield has no holder relation")
	TEST_ASSERT(S._signal_procs?[H]?[COMSIG_LIVING_SHIELD_INJURY], "active shield has no injury listener")
	qdel(S)
	TEST_ASSERT(!H.has_modifier_of_type(/datum/modifier/shield_projection), "direct deletion left a dead shield in the modifier list")
	TEST_ASSERT(!H._listen_lookup?[COMSIG_LIVING_SHIELD_INJURY], "direct deletion left the injury listener")
	TEST_ASSERT(dq_near(H.factor(BF_SIEMENS), baseline), "direct deletion left the shield factor active")
	var/datum/modifier/shield_projection/bruteburn/replacement = H.add_modifier(/datum/modifier/shield_projection/bruteburn)
	TEST_ASSERT(replacement && om_has_link(replacement, /datum/object_model/relation/shield_projection_holder, H), "shield could not be reapplied after direct deletion")
	replacement.expire(TRUE)
	TEST_ASSERT(!H.has_modifier_of_type(/datum/modifier/shield_projection), "normal expiry left the shield in the modifier list")
	TEST_ASSERT(!H._listen_lookup?[COMSIG_LIVING_SHIELD_INJURY], "normal expiry left the injury listener")
	TEST_ASSERT(dq_near(H.factor(BF_SIEMENS), baseline), "normal expiry left the shield factor active")


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
