// Unit tests for the DQ surgery framework — registry, cure hook,
// zone-routing, well-formedness.
//
// Sibling test files in this directory cover bodyscanner and the
// cross-cutting audit. They share helper procs declared on the base
// unit_test type in /home/ethan/projects/CHOMPStation2/code/modules/unit_tests/dq_medical_tests.dm.
//
// All three sibling files are #included from
// code/modules/unit_tests/_unit_tests.dm (via DQAdd) so the TEST_ASSERT*
// macros are still in scope. The medical defines header is re-included
// once here because the upstream test block compiles before the
// medical includes.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#include "../modules/medical/_defines.dm"

// --- surgery: registry has entries -------------------------------------

/datum/unit_test/dq_surgery_registry_populates

/datum/unit_test/dq_surgery_registry_populates/Run()
	// Force a fresh build of the registry.
	GLOB.dq_surgery_by_step = list()
	var/list/registry = dq_surgeries_registry()
	TEST_ASSERT(length(registry) > 0, "surgery registry should contain at least one entry")
	for(var/step_path in registry)
		TEST_ASSERT(ispath(step_path, /datum/surgery_step), "registry key [step_path] is not a /datum/surgery_step")
		var/list/datum/dq_surgery/surgeries = registry[step_path]
		TEST_ASSERT(length(surgeries) > 0, "registry value for [step_path] is empty")
		for(var/datum/dq_surgery/sg as anything in surgeries)
			TEST_ASSERT(istype(sg), "registry value for [step_path] contains non-/datum/dq_surgery [sg]")
			TEST_ASSERT_EQUAL(sg.completion_step, step_path, "surgery [sg.type] indexed under wrong step ([step_path] vs its completion_step [sg.completion_step])")


// --- surgery: every authored surgery references real types -------------

/datum/unit_test/dq_surgery_records_well_formed

/datum/unit_test/dq_surgery_records_well_formed/Run()
	for(var/T in subtypesof(/datum/dq_surgery))
		var/datum/dq_surgery/sg = new T()
		TEST_ASSERT(sg.name, "[T] has no name")
		TEST_ASSERT(sg.description, "[T] has no description")
		TEST_ASSERT(sg.category, "[T] has no category")
		TEST_ASSERT(length(sg.steps) > 0, "[T] has no procedural steps documented")
		TEST_ASSERT(length(sg.treats) > 0, "[T] declares no treatable conditions")
		for(var/cond_path in sg.treats)
			TEST_ASSERT(ispath(cond_path, /datum/medical_issue/condition), "[T].treats contains non-condition path [cond_path]")
		if(sg.completion_step)
			TEST_ASSERT(ispath(sg.completion_step, /datum/surgery_step), "[T].completion_step [sg.completion_step] is not a /datum/surgery_step subtype")
		qdel(sg)


// --- surgery: cure hook actually clears matching conditions ------------

/datum/unit_test/dq_surgery_cures_matching_condition

/datum/unit_test/dq_surgery_cures_matching_condition/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/untreated_fracture/C = _dq_spawn_condition_on(H, BP_L_ARM, /datum/medical_issue/condition/untreated_fracture)
	TEST_ASSERT_NOTNULL(C, "untreated_fracture didn't spawn")

	var/datum/surgery_step/bones/finish_bone/step = new()
	dq_apply_surgery_cures(step, H, BP_L_ARM)
	qdel(step)

	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/untreated_fracture))
			TEST_FAIL("untreated_fracture should have been cured by fracture_setting")


// --- surgery: tendon repair via its own dedicated step ---------------

/datum/unit_test/dq_surgery_tendon_repair_step_cures

/datum/unit_test/dq_surgery_tendon_repair_step_cures/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/tendon_severed/C = _dq_spawn_condition_on(H, BP_L_LEG, /datum/medical_issue/condition/tendon_severed)
	TEST_ASSERT_NOTNULL(C, "tendon_severed didn't spawn")

	var/datum/surgery_step/fix_tendon/step = new()
	dq_apply_surgery_cures(step, H, BP_L_LEG)
	qdel(step)

	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/tendon_severed))
			TEST_FAIL("tendon_severed should have been cured by fix_tendon")


// --- surgery: cure hook ignores non-matching conditions ----------------

/datum/unit_test/dq_surgery_does_not_cure_unrelated

/datum/unit_test/dq_surgery_does_not_cure_unrelated/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/cellulitis/C = _dq_spawn_condition_on(H, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	TEST_ASSERT_NOTNULL(C, "cellulitis didn't spawn")

	var/datum/surgery_step/bones/finish_bone/step = new()
	dq_apply_surgery_cures(step, H, BP_TORSO)
	qdel(step)

	var/still_present = FALSE
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/cellulitis))
			still_present = TRUE
			break
	TEST_ASSERT(still_present, "cellulitis should not be cured by an unrelated surgery (fracture_setting)")


// --- surgery: shared step routed by zone ------------------------------
// /datum/surgery_step/internal/fix_organ is reused by craniotomy (head,
// treats subdural_hematoma) and lung_repair (torso, treats
// respiratory_failure). The cure hook should only fire the surgery
// whose body_region matches the target zone.

/datum/unit_test/dq_surgery_zone_routing

/datum/unit_test/dq_surgery_zone_routing/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	_dq_spawn_condition_on(H, BP_HEAD, /datum/medical_issue/condition/subdural_hematoma)
	_dq_spawn_condition_on(H, O_LUNGS, /datum/medical_issue/condition/respiratory_failure)

	// Apply fix_organ on the HEAD zone. Should only cure subdural_hematoma.
	var/datum/surgery_step/internal/fix_organ/step = new()
	dq_apply_surgery_cures(step, H, BP_HEAD)

	var/sh_present = FALSE
	var/rf_present = FALSE
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/subdural_hematoma))
			sh_present = TRUE
		else if(istype(c, /datum/medical_issue/condition/respiratory_failure))
			rf_present = TRUE
	TEST_ASSERT(!sh_present, "head-zone fix_organ (craniotomy) should have cured subdural_hematoma")
	TEST_ASSERT(rf_present, "head-zone fix_organ should NOT have cured respiratory_failure (torso)")

	// Now apply fix_organ on the TORSO zone. Should cure respiratory_failure.
	dq_apply_surgery_cures(step, H, BP_TORSO)
	qdel(step)
	rf_present = FALSE
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/respiratory_failure))
			rf_present = TRUE
			break
	TEST_ASSERT(!rf_present, "torso-zone fix_organ should have cured respiratory_failure")


// --- mechanical effects: aggregates cap per key ----------------------

/datum/unit_test/dq_mechanical_value_respects_cap

/datum/unit_test/dq_mechanical_value_respects_cap/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Three distinct conditions on the same organ, each contributing
	// slowdown = 1.0. Sum is 3.0, cap is 2.5.
	var/list/types = list(
		/datum/medical_issue/condition/cellulitis,
		/datum/medical_issue/condition/sepsis,
		/datum/medical_issue/condition/wound_infection,
	)
	for(var/T in types)
		var/datum/medical_issue/condition/C = _dq_spawn_condition_on(H, BP_TORSO, T)
		TEST_ASSERT_NOTNULL(C, "spawn failed for [T]")
		C.mechanical_effects = list("slowdown" = 1.0)

	var/total = H.dq_mechanical_value("slowdown")
	TEST_ASSERT_EQUAL(total, 2.5, "three conditions × 1.0 slowdown should be capped at 2.5 (got [total])")


// --- mechanical effects: uncapped key passes through unchanged ------

/datum/unit_test/dq_mechanical_value_uncapped_key_passes

/datum/unit_test/dq_mechanical_value_uncapped_key_passes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/cellulitis/C = _dq_spawn_condition_on(H, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	// "spontaneous_emote_prob" isn't in the cap table — should pass
	// through whatever value the condition author set.
	C.mechanical_effects = list("spontaneous_emote_prob" = 999)
	TEST_ASSERT_EQUAL(H.dq_mechanical_value("spontaneous_emote_prob"), 999, "uncapped key should pass through unchanged")


// --- chem presence: single-chem side effect spawns and clears --------

/datum/unit_test/dq_chem_presence_side_effect_spawns

/datum/unit_test/dq_chem_presence_side_effect_spawns/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	// No alkysine yet — no side condition.
	H.dq_check_chem_conditions()
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/alkysine_confusion))
			TEST_FAIL("alkysine_confusion should not exist without the chem")

	// Dose past the 5u threshold — condition should spawn.
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 10)
	H.dq_check_chem_conditions()
	var/found = FALSE
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/alkysine_confusion))
			found = TRUE
			break
	TEST_ASSERT(found, "alkysine_confusion should spawn when alkysine ≥ 5u")

	// Drain the chem — the condition should clear.
	H.bloodstr.remove_reagent(REAGENT_ID_ALKYSINE, 10)
	H.dq_check_chem_conditions()
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/alkysine_confusion))
			TEST_FAIL("alkysine_confusion should clear when the chem is gone")


// --- chem presence: interaction needs BOTH chems above threshold ----

/datum/unit_test/dq_chem_presence_interaction_requires_both

/datum/unit_test/dq_chem_presence_interaction_requires_both/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	// Only inaprovaline — no interaction.
	H.bloodstr.add_reagent(REAGENT_ID_INAPROVALINE, 10)
	H.dq_check_chem_conditions()
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/tachycardia_chem))
			TEST_FAIL("tachycardia interaction should NOT fire with only one chem present")

	// Add hyperzine — both present, interaction fires.
	H.bloodstr.add_reagent(REAGENT_ID_HYPERZINE, 10)
	H.dq_check_chem_conditions()
	var/found = FALSE
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/tachycardia_chem))
			found = TRUE
			break
	TEST_ASSERT(found, "tachycardia interaction should fire when both chems present")

	// Remove one — interaction clears.
	H.bloodstr.remove_reagent(REAGENT_ID_INAPROVALINE, 10)
	H.dq_check_chem_conditions()
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/tachycardia_chem))
			TEST_FAIL("tachycardia interaction should clear when one chem leaves")


// --- interference: interferes_with reduces cure rate on other conds --

/datum/unit_test/dq_interference_reduces_cure_rate

/datum/unit_test/dq_interference_reduces_cure_rate/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Spawn an infection that's cured by spaceacillin.
	var/datum/medical_issue/condition/cellulitis/C = _dq_spawn_condition_on(H, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	TEST_ASSERT_NOTNULL(C, "cellulitis spawn failed")
	C.severity = 50

	// Drop spaceacillin in the bloodstream — without the interaction
	// marker, cellulitis should heal at full rate.
	H.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 100)
	var/sev_before = C.severity
	C.tick_condition()
	var/normal_delta = sev_before - C.severity
	TEST_ASSERT(normal_delta > 0, "spaceacillin should drop cellulitis severity (no interaction)")

	// Reset, add the interference marker, tick again — delta should
	// be smaller.
	C.severity = 50
	var/datum/medical_issue/condition/bicaridine_antibiotic_interference/M = _dq_spawn_condition_on(H, O_LIVER, /datum/medical_issue/condition/bicaridine_antibiotic_interference)
	TEST_ASSERT_NOTNULL(M, "interference marker spawn failed")
	C.tick_condition()
	var/blocked_delta = 50 - C.severity
	TEST_ASSERT(blocked_delta < normal_delta, "interference should reduce cure delta (no_int=[normal_delta], with_int=[blocked_delta])")


// --- Bicaridine OD drains subdural hematoma ---------------------------

/datum/unit_test/dq_bicaridine_od_drains_hematoma

/datum/unit_test/dq_bicaridine_od_drains_hematoma/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/subdural_hematoma/sh = _dq_spawn_condition_on(H, BP_HEAD, /datum/medical_issue/condition/subdural_hematoma)
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
	var/datum/medical_issue/condition/heart_damage/hd = _dq_spawn_condition_on(H, O_HEART, /datum/medical_issue/condition/heart_damage)
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
	// Baseline slowdown is 0 with no conditions.
	TEST_ASSERT_EQUAL(H.dq_condition_slowdown(), 0, "baseline slowdown should be 0")

	H.bloodstr.add_reagent(REAGENT_ID_HYPERZINE, 40)  // 10 over OD threshold of 30
	for(var/i in 1 to 50)
		H.dq_check_chem_conditions()
	// At peak severity, hyperzine OD contributes -1.0 speed via od_boost.
	var/slow = H.dq_condition_slowdown()
	TEST_ASSERT(slow < 0, "hyperzine OD should produce negative slowdown (boost): got [slow]")


// --- Synaptizine OD + alkysine rescues brain in salvage band ----------

/datum/unit_test/dq_synaptizine_od_rescues_brain_with_alkysine

/datum/unit_test/dq_synaptizine_od_rescues_brain_with_alkysine/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]

	// 70% damage — in the salvage band, above 60% decay floor.
	B.damage = B.max_damage * 0.7
	var/start = B.damage

	// Stack synaptizine OD AND alkysine. Combo should heal slowly.
	H.bloodstr.add_reagent(REAGENT_ID_SYNAPTIZINE, 40)  // 10 over OD threshold
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 10)
	// Ramp the OD condition to max severity so its boost is at full.
	for(var/i in 1 to 50)
		H.dq_check_chem_conditions()
	var/datum/medical_issue/condition/synaptizine_overdose/od
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/synaptizine_overdose))
			od = c
			break
	TEST_ASSERT_NOTNULL(od, "synaptizine OD should be spawned")
	TEST_ASSERT_EQUAL(od.severity, 100, "OD should ramp to max severity")

	// Now tick the brain a few times — damage should drop.
	for(var/i in 1 to 30)
		B.dq_brain_decay_tick()
	TEST_ASSERT(B.damage < start, "brain in salvage band should heal with synaptizine OD + alkysine ([start] -> [B.damage])")


// --- Synaptizine OD without alkysine cannot save salvage-band brain ---

/datum/unit_test/dq_synaptizine_od_alone_cannot_save_brain

/datum/unit_test/dq_synaptizine_od_alone_cannot_save_brain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	B.damage = B.max_damage * 0.7
	var/start = B.damage

	// Synaptizine OD without alkysine: decay outpaces repair.
	H.bloodstr.add_reagent(REAGENT_ID_SYNAPTIZINE, 40)
	for(var/i in 1 to 50)
		H.dq_check_chem_conditions()
	for(var/i in 1 to 30)
		B.dq_brain_decay_tick()
	TEST_ASSERT(B.damage >= start, "without alkysine, brain damage should not net heal ([start] -> [B.damage])")


// --- Past 90% is terminal regardless of chems -------------------------

/datum/unit_test/dq_brain_terminal_zone_is_unsavable

/datum/unit_test/dq_brain_terminal_zone_is_unsavable/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	B.damage = B.max_damage * 0.92  // past terminal floor
	var/start = B.damage

	// Full chem combo. Should still progress to max damage.
	H.bloodstr.add_reagent(REAGENT_ID_SYNAPTIZINE, 60)
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 30)
	for(var/i in 1 to 50)
		H.dq_check_chem_conditions()
	for(var/i in 1 to 10)
		B.dq_brain_decay_tick()

	TEST_ASSERT(B.damage > start, "past 90% should keep climbing despite full chem combo ([start] -> [B.damage])")


// --- OD boost aggregator scales with severity ------------------------

/datum/unit_test/dq_od_boost_scales_with_severity

/datum/unit_test/dq_od_boost_scales_with_severity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)

	// Attach a synthetic OD condition with a known boost. Use peridaxon
	// OD since we already have it authored; override od_boost on the
	// instance to test the aggregator without depending on authored
	// values.
	var/datum/medical_issue/condition/peridaxon_overdose/od = new()
	od.owner = H
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	od.affectedorgan = B
	LAZYADD(B.medical_issues, od)
	od.od_boost = list("speed" = 1.0, "pain_resist" = 0.5)

	// At severity 0, no boost.
	od.severity = 0
	TEST_ASSERT_EQUAL(H.dq_od_boost_value("speed"), 0, "severity 0 yields no boost")

	// At severity 50, half the authored strength.
	od.severity = 50
	TEST_ASSERT_EQUAL(H.dq_od_boost_value("speed"), 0.5, "severity 50 yields half-strength")
	TEST_ASSERT_EQUAL(H.dq_od_boost_value("pain_resist"), 0.25, "pain_resist scales too")

	// At severity 100, full strength.
	od.severity = 100
	TEST_ASSERT_EQUAL(H.dq_od_boost_value("speed"), 1.0, "severity 100 yields full strength")


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
		var/datum/medical_issue/condition/peridaxon_overdose/od
		for(var/datum/medical_issue/condition/c in H.get_all_conditions())
			if(istype(c, /datum/medical_issue/condition/peridaxon_overdose))
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

	var/datum/medical_issue/condition/peridaxon_overdose/low_OD
	var/datum/medical_issue/condition/peridaxon_overdose/high_OD
	for(var/datum/medical_issue/condition/c in H_low.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/peridaxon_overdose))
			low_OD = c
			break
	for(var/datum/medical_issue/condition/c in H_high.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/peridaxon_overdose))
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
	var/datum/medical_issue/condition/peridaxon_overdose/od
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/peridaxon_overdose))
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

	var/datum/medical_issue/condition/alkysine_confusion/cc
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/alkysine_confusion))
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

	var/datum/medical_issue/condition/cellulitis/C1 = _dq_spawn_condition_on(H1, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	var/datum/medical_issue/condition/cellulitis/C2 = _dq_spawn_condition_on(H2, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	var/datum/medical_issue/condition/cellulitis/C3 = _dq_spawn_condition_on(H3, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	C1.severity = 50
	C2.severity = 50
	C3.severity = 50

	H1.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 1)   // sub-dose
	H2.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 10)  // standard dose
	H3.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 50)  // capped above 30

	C1.tick_condition()
	C2.tick_condition()
	C3.tick_condition()

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
	var/datum/medical_issue/condition/cellulitis/CA = _dq_spawn_condition_on(HA, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	var/datum/medical_issue/condition/cellulitis/CB = _dq_spawn_condition_on(HB, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	CA.severity = 50
	CB.severity = 50
	HA.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 40)  // at cap
	HB.bloodstr.add_reagent(REAGENT_ID_SPACEACILLIN, 100) // way over cap

	CA.tick_condition()
	CB.tick_condition()

	var/dA = 50 - CA.severity
	var/dB = 50 - CB.severity
	TEST_ASSERT_EQUAL(dA, dB, "40u and 100u should heal equally (cap engaged) — got [dA] vs [dB]")


// --- cascade scaling: 2× threshold guarantees spawn -----------------

/datum/unit_test/dq_cascade_chance_scales_with_damage

/datum/unit_test/dq_cascade_chance_scales_with_damage/Run()
	var/datum/dq_cause_outcome/o = new()
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


// --- organ decay: brain past salvage threshold rises despite alkysine -

/datum/unit_test/dq_brain_decay_past_threshold

/datum/unit_test/dq_brain_decay_past_threshold/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT_NOTNULL(B, "no brain organ")

	// Push the brain to 70% damage (above DQ_BRAIN_SALVAGE_THRESHOLD=60%).
	B.damage = B.max_damage * 0.7
	var/before = B.damage

	// No alkysine: damage should rise.
	for(var/i in 1 to 5)
		B.dq_brain_decay_tick()
	TEST_ASSERT(B.damage > before, "above-threshold brain should decay without alkysine ([before] -> [B.damage])")
	var/no_chem_growth = B.damage - before

	// Reset and try again with alkysine — should still rise, but slower.
	B.damage = B.max_damage * 0.7
	H.bloodstr.add_reagent(REAGENT_ID_ALKYSINE, 30)
	for(var/i in 1 to 5)
		B.dq_brain_decay_tick()
	var/with_chem_growth = B.damage - (B.max_damage * 0.7)
	TEST_ASSERT(with_chem_growth > 0, "alkysine should NOT reverse decay above threshold (growth=[with_chem_growth])")
	TEST_ASSERT(with_chem_growth < no_chem_growth, "alkysine should slow decay (no_chem=[no_chem_growth], with_chem=[with_chem_growth])")


// --- organ decay: brain below threshold doesn't decay -----------------

/datum/unit_test/dq_brain_stable_mid_range

/datum/unit_test/dq_brain_stable_mid_range/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]

	// 40% damage — in the stable band (20-60%), no auto-heal and no decay.
	B.damage = B.max_damage * 0.4
	var/before = B.damage

	for(var/i in 1 to 10)
		B.dq_brain_decay_tick()
	TEST_ASSERT_EQUAL(B.damage, before, "mid-range brain (20-60%) should not decay or auto-heal")


// --- organ decay: brain below 20% heals naturally --------------------

/datum/unit_test/dq_brain_natural_heal_below_floor

/datum/unit_test/dq_brain_natural_heal_below_floor/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]

	// 15% damage — below the 20% natural-heal ceiling.
	B.damage = B.max_damage * 0.15
	var/before = B.damage

	for(var/i in 1 to 10)
		B.dq_brain_decay_tick()
	TEST_ASSERT(B.damage < before, "below-20% brain should heal naturally ([before] -> [B.damage])")


// --- organ decay: natural heal stops at 0 (no negative damage) -------

/datum/unit_test/dq_brain_natural_heal_floors_at_zero

/datum/unit_test/dq_brain_natural_heal_floors_at_zero/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/brain/B = H.internal_organs_by_name[O_BRAIN]
	B.damage = 0.5  // tiny damage, less than one heal tick

	for(var/i in 1 to 10)
		B.dq_brain_decay_tick()
	TEST_ASSERT(B.damage >= 0, "natural heal should floor at 0, not go negative (got [B.damage])")


// --- organ lifecycle: amputating a limb detaches conditions ----------
// The condition stays attached to the limb object (so it can return on
// reattach) but its `owner` is nulled so the now-detached patient stops
// processing it.

/datum/unit_test/dq_organ_lifecycle_amputation_detaches_conditions

/datum/unit_test/dq_organ_lifecycle_amputation_detaches_conditions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/tendon_severed/C = _dq_spawn_condition_on(H, BP_L_ARM, /datum/medical_issue/condition/tendon_severed)
	TEST_ASSERT_NOTNULL(C, "tendon_severed didn't spawn")

	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	TEST_ASSERT_NOTNULL(arm, "no left arm")
	arm.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)

	// The patient no longer has this condition (we walk the patient's
	// remaining organs; the severed arm isn't one of them).
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/tendon_severed))
			TEST_FAIL("tendon_severed should detach from patient when limb is severed")

	// The condition still exists on the severed limb with no owner.
	TEST_ASSERT(!QDELETED(C), "condition should NOT be qdeleted — it rides along with the limb")
	TEST_ASSERT_NULL(C.owner, "condition owner should be nulled after sever")
	TEST_ASSERT_EQUAL(C.affectedorgan, arm, "condition should still be attached to the severed arm")


// --- organ lifecycle: reattaching a limb reseats conditions ----------

/datum/unit_test/dq_organ_lifecycle_reattach_restores_conditions

/datum/unit_test/dq_organ_lifecycle_reattach_restores_conditions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/tendon_severed/C = _dq_spawn_condition_on(H, BP_L_ARM, /datum/medical_issue/condition/tendon_severed)
	TEST_ASSERT_NOTNULL(C, "tendon_severed didn't spawn")

	var/obj/item/organ/external/arm = H.get_organ(BP_L_ARM)
	arm.droplimb(clean = TRUE, disintegrate = DROPLIMB_EDGE)
	TEST_ASSERT_NULL(C.owner, "after sever, condition owner should be null")

	// Reattach: replaced() should re-anchor the condition to the patient.
	arm.replaced(H)
	TEST_ASSERT_EQUAL(C.owner, H, "after reattach, condition owner should be the patient again")

	// And the patient should once again see this condition in their roster.
	var/found = FALSE
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/tendon_severed))
			found = TRUE
			break
	TEST_ASSERT(found, "reattached limb should restore its condition to the patient")


// --- organ lifecycle: deleting an organ doesn't leak medical_issues ---

/datum/unit_test/dq_organ_lifecycle_destroy_qdels_conditions

/datum/unit_test/dq_organ_lifecycle_destroy_qdels_conditions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/compartment_syndrome/C = _dq_spawn_condition_on(H, BP_L_LEG, /datum/medical_issue/condition/compartment_syndrome)
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
		if(/datum/medical_issue/condition/brain_damage in sg.treats)
			TEST_FAIL("[T] declares it treats brain_damage; that condition is intentionally terminal — no surgery can repair established brain tissue damage")
		qdel(sg)


// --- surgery: undocumented step is a no-op ----------------------------

/datum/unit_test/dq_surgery_undocumented_step_noop

/datum/unit_test/dq_surgery_undocumented_step_noop/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	_dq_spawn_condition_on(H, BP_TORSO, /datum/medical_issue/condition/cellulitis)
	var/before = length(H.get_all_conditions())

	// /datum/surgery_step/face/mend_vocal isn't referenced by any
	// dq_surgery record. It's a real surgery_step subtype but undocumented
	// in our framework — should be a no-op.
	var/datum/surgery_step/face/mend_vocal/step = new()
	dq_apply_surgery_cures(step, H, BP_TORSO)
	qdel(step)

	var/after = length(H.get_all_conditions())
	TEST_ASSERT_EQUAL(before, after, "undocumented surgery step should not cure anything")


// --- surgery: every authored surgery is wired up ---------------------
// Stricter than dq_surgery_completion_step_coverage: every authored
// /datum/dq_surgery must have a real completion_step. Documentation-only
// entries were acceptable while the framework was being built; now they
// represent unreachable cures and a player-visible lie in the
// encyclopedia. Fails loudly if any record is unwired.

/datum/unit_test/dq_surgery_all_wired

/datum/unit_test/dq_surgery_all_wired/Run()
	var/list/unwired = list()
	for(var/T in subtypesof(/datum/dq_surgery))
		var/datum/dq_surgery/sg = new T()
		if(!sg.completion_step)
			unwired += "[T]"
		qdel(sg)
	if(length(unwired))
		TEST_FAIL("documentation-only surgeries with no completion_step: [jointext(unwired, ", ")]")


// --- surgery: cure_severity reduces severity, doesn't always cure ----

/datum/unit_test/dq_surgery_graduated_cure

/datum/unit_test/dq_surgery_graduated_cure/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/heart_damage/hd = _dq_spawn_condition_on(H, O_HEART, /datum/medical_issue/condition/heart_damage)
	TEST_ASSERT_NOTNULL(hd, "heart_damage didn't spawn")
	hd.severity = 90  // critical-arrest territory

	var/datum/surgery_step/cardiac_repair/step = new()
	dq_apply_surgery_cures(step, H, BP_TORSO)
	qdel(step)

	// cardiac_repair has cure_severity = 60, so severity 90 → 30.
	// The condition should still be present but much less severe.
	var/datum/medical_issue/condition/heart_damage/after
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/heart_damage))
			after = c
			break
	TEST_ASSERT_NOTNULL(after, "graduated cure should NOT have removed heart_damage entirely from severity 90")
	TEST_ASSERT(after.severity < 90, "severity should have dropped from 90 ([after.severity])")
	TEST_ASSERT(after.severity <= 30, "cure_severity=60 should drop severity 90 to ~30 (got [after.severity])")


// --- surgery: cure_severity >= severity does cure fully --------------

/datum/unit_test/dq_surgery_graduated_cure_full_when_low

/datum/unit_test/dq_surgery_graduated_cure_full_when_low/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/heart_damage/hd = _dq_spawn_condition_on(H, O_HEART, /datum/medical_issue/condition/heart_damage)
	hd.severity = 40  // below cardiac_repair's cure_severity (60)

	var/datum/surgery_step/cardiac_repair/step = new()
	dq_apply_surgery_cures(step, H, BP_TORSO)
	qdel(step)

	// 40 ≤ 60, so the condition should be fully removed.
	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/heart_damage))
			TEST_FAIL("cure_severity 60 should fully clear heart_damage at severity 40 (drop >= severity = full cure)")


// --- surgery: fasciotomy cures compartment syndrome ------------------

/datum/unit_test/dq_surgery_fasciotomy_cures

/datum/unit_test/dq_surgery_fasciotomy_cures/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/compartment_syndrome/C = _dq_spawn_condition_on(H, BP_L_LEG, /datum/medical_issue/condition/compartment_syndrome)
	TEST_ASSERT_NOTNULL(C, "compartment_syndrome didn't spawn")

	var/datum/surgery_step/fasciotomy/step = new()
	dq_apply_surgery_cures(step, H, BP_L_LEG)
	qdel(step)

	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/compartment_syndrome))
			TEST_FAIL("compartment_syndrome should be cured by fasciotomy")


// --- surgery: chest tube cures tension pneumothorax ------------------

/datum/unit_test/dq_surgery_chest_tube_cures

/datum/unit_test/dq_surgery_chest_tube_cures/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/tension_pneumothorax/C = _dq_spawn_condition_on(H, BP_TORSO, /datum/medical_issue/condition/tension_pneumothorax)
	TEST_ASSERT_NOTNULL(C, "tension_pneumothorax didn't spawn")

	var/datum/surgery_step/chest_tube/step = new()
	dq_apply_surgery_cures(step, H, BP_TORSO)
	qdel(step)

	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/tension_pneumothorax))
			TEST_FAIL("tension_pneumothorax should be cured by chest tube placement")


// --- surgery: exploratory laparotomy cures internal bleeding --------

/datum/unit_test/dq_surgery_laparotomy_cures

/datum/unit_test/dq_surgery_laparotomy_cures/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/medical_issue/condition/internal_hemorrhage/C = _dq_spawn_condition_on(H, BP_TORSO, /datum/medical_issue/condition/internal_hemorrhage)
	TEST_ASSERT_NOTNULL(C, "internal_hemorrhage didn't spawn")

	var/datum/surgery_step/exploratory_laparotomy/step = new()
	dq_apply_surgery_cures(step, H, BP_TORSO)
	qdel(step)

	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/internal_hemorrhage))
			TEST_FAIL("internal_hemorrhage should be cured by exploratory laparotomy")


// --- surgery: retinal repair cures vision loss ----------------------

/datum/unit_test/dq_surgery_retinal_repair_cures

/datum/unit_test/dq_surgery_retinal_repair_cures/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	_dq_spawn_condition_on(H, O_EYES, /datum/medical_issue/condition/ischemic_vision_loss)

	var/datum/surgery_step/retinal_repair/step = new()
	dq_apply_surgery_cures(step, H, BP_HEAD)
	qdel(step)

	for(var/datum/medical_issue/condition/c in H.get_all_conditions())
		if(istype(c, /datum/medical_issue/condition/ischemic_vision_loss))
			TEST_FAIL("ischemic_vision_loss should be cured by retinal repair")


// --- surgery zone matcher: keyword table behaves --------------------

/datum/unit_test/dq_surgery_zone_matcher

/datum/unit_test/dq_surgery_zone_matcher/Run()
	// "Affected limb or torso" matches both limb and torso zones.
	var/datum/dq_surgery/proto = new()
	proto.body_region = "Affected limb or torso"
	TEST_ASSERT(_dq_surgery_matches_zone(proto, BP_L_ARM), "limb-or-torso surgery should match arm")
	TEST_ASSERT(_dq_surgery_matches_zone(proto, BP_TORSO), "limb-or-torso surgery should match torso")
	TEST_ASSERT(!_dq_surgery_matches_zone(proto, BP_HEAD), "limb-or-torso surgery should NOT match head")

	// "Head" matches the head, eyes, mouth zones.
	proto.body_region = "Head"
	TEST_ASSERT(_dq_surgery_matches_zone(proto, BP_HEAD), "head surgery should match BP_HEAD")
	TEST_ASSERT(_dq_surgery_matches_zone(proto, O_EYES), "head surgery should match O_EYES (eye zone)")
	TEST_ASSERT(!_dq_surgery_matches_zone(proto, BP_L_LEG), "head surgery should NOT match limb")

	// Empty body_region matches everything.
	proto.body_region = ""
	TEST_ASSERT(_dq_surgery_matches_zone(proto, BP_HEAD), "empty body_region should match head")
	TEST_ASSERT(_dq_surgery_matches_zone(proto, BP_TORSO), "empty body_region should match torso")
	qdel(proto)

#endif
