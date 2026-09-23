// Unit tests for the DQ medical condition system.
//
// The framework spins up a test world, allocates per-test objects, runs
// Run() on each /datum/unit_test, and reports pass/fail to clean_run.lk.
//
// Why use it: tick-driven medical conditions are otherwise testable only
// by attaching to a live server with admin verbs. The unit-test loop
// lets me invoke tick() directly N times in a controlled
// scenario and assert severity behavior without waiting on the SS clock.

// --- spawn + tick smoke test ----------------------------------------------

/datum/unit_test/dq_medical_dirty_domains_wake_exactly

/datum/unit_test/dq_medical_dirty_domains_wake_exactly/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.body.dirty &= ~BODY_DIRTY_CONDITIONS
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_NOTNULL(heart, "test human has no heart")
	H.injure(INJURY_BLUNT, 1, heart, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_ORGANS, "organ damage did not invalidate organ conditions")
	H.body.dirty &= ~BODY_DIRTY_CONDITIONS
	H.bloodstr.add_reagent(REAGENT_ID_INAPROVALINE, 1)
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_CHEMS, "bloodstream mutation did not invalidate chem conditions")
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_TREATMENT, "bloodstream mutation did not invalidate the treatment snapshot")
	H.body.dirty &= ~BODY_DIRTY_CONDITIONS
	H.dq_last_bodytemperature = -1
	H.dq_refresh_metric_dirty_state()
	TEST_ASSERT(H.body.dirty & BODY_DIRTY_METRICS, "metric signature change did not invalidate metric conditions")
	H.dq_process_dirty_medical_conditions()
	TEST_ASSERT(!(H.body.dirty & BODY_DIRTY_CONDITIONS), "processing should consume the condition domains")

/datum/unit_test/dq_medical_condition_spawn

/datum/unit_test/dq_medical_condition_spawn/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H, "couldn't allocate test human")

	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(chest, "test human has no torso organ")

	// Spawn a condition directly (skips cascade RNG).
	var/datum/affliction/internal_hemorrhage/C = H.body.afflict(/datum/affliction/internal_hemorrhage, chest)
	TEST_ASSERT_NOTNULL(C, "internal_hemorrhage could not be afflicted")

	var/list/found = H.get_afflictions()
	TEST_ASSERT_EQUAL(length(found), 1, "expected exactly one condition after spawn")
	TEST_ASSERT_EQUAL(found[1], C, "get_afflictions did not return the spawned condition")

// --- tick raises severity --------------------------------------

/datum/unit_test/dq_medical_condition_tick_raises_severity

/datum/unit_test/dq_medical_condition_tick_raises_severity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(chest, "test human has no torso organ")

	var/datum/affliction/internal_hemorrhage/C = H.body.afflict(/datum/affliction/internal_hemorrhage, chest)
	TEST_ASSERT_NOTNULL(C, "internal_hemorrhage could not be afflicted")

	var/start = C.severity
	C.tick()
	var/after_one = C.severity
	TEST_ASSERT(after_one > start, "first tick did not raise severity ([start] -> [after_one])")

	C.tick()
	var/after_two = C.severity
	TEST_ASSERT(after_two > after_one, "second tick did not raise severity ([after_one] -> [after_two])")

	// Ten more ticks: severity should keep climbing as long as no cure
	// is in body and reagent vars haven't been touched.
	for(var/i in 1 to 10)
		C.tick()
	TEST_ASSERT(C.severity > after_two, "ten ticks did not raise severity further")
	TEST_ASSERT(C.severity <= 100, "severity exceeded terminal cap")

// --- the body's Life tick actually ticks afflictions ---------------------
// Afflictions live in the body, not on organs: body.life_tick() is the one
// place they progress. Catches a body that stops dispatching to afflictions
// located on attached limbs.

/datum/unit_test/dq_medical_external_process_ticks_conditions

/datum/unit_test/dq_medical_external_process_ticks_conditions/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(chest, "no torso")
	TEST_ASSERT_EQUAL(chest.owner, H, "torso should have owner set")

	var/datum/affliction/internal_hemorrhage/C = H.body.afflict(/datum/affliction/internal_hemorrhage, chest)
	TEST_ASSERT_NOTNULL(C, "internal_hemorrhage could not be afflicted")

	var/start = C.severity
	H.body.life_tick()
	TEST_ASSERT(C.severity > start, "body.life_tick() should tick afflictions located on attached limbs ([start] -> [C.severity])")

// --- afflictions find their location through the body ---------------------

/datum/unit_test/dq_medical_afflict_locates_on_organ

/datum/unit_test/dq_medical_afflict_locates_on_organ/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)

	var/datum/affliction/internal_hemorrhage/C = H.body.afflict(/datum/affliction/internal_hemorrhage, chest)
	TEST_ASSERT_NOTNULL(C, "internal_hemorrhage could not be afflicted")

	TEST_ASSERT_EQUAL(C.location, chest, "afflict() should locate the affliction on the chosen organ")
	TEST_ASSERT_EQUAL(H.body.find_affliction(/datum/affliction/internal_hemorrhage, chest), C, "find_affliction should resolve the affliction at its location")
	TEST_ASSERT(C in chest.afflictions_here(), "afflictions_here() should list afflictions located on the organ")
	TEST_ASSERT_EQUAL(H.body.afflict(/datum/affliction/internal_hemorrhage, chest), C, "afflict() must be idempotent per (type, location)")
	TEST_ASSERT_EQUAL(length(H.body.afflictions_of(/datum/affliction/internal_hemorrhage)), 1, "a repeated afflict() must not stack a second copy")

// --- cure_by reagent reduces severity ------------------------------------

/datum/unit_test/dq_medical_condition_cure_reagent_lowers_severity

/datum/unit_test/dq_medical_condition_cure_reagent_lowers_severity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)

	var/datum/affliction/internal_hemorrhage/C = H.body.afflict(/datum/affliction/internal_hemorrhage, chest)
	TEST_ASSERT_NOTNULL(C, "internal_hemorrhage could not be afflicted")

	// Bring severity up first.
	for(var/i in 1 to 10)
		C.tick()
	var/before_cure = C.severity
	TEST_ASSERT(before_cure > 0, "severity must rise above 0 before testing cure")

	// Inject a strong dose of cure reagent into the bloodstream and tick.
	// bicaridaze cures internal_hemorrhage at 1.4/tick — more than the
	// 0.25/tick passive rise. Severity should fall.
	H.bloodstr.add_reagent(REAGENT_ID_BICARIDAZE, 50)
	for(var/i in 1 to 5)
		C.tick()
	TEST_ASSERT(C.severity < before_cure, "cure reagent did not lower severity ([before_cure] -> [C.severity])")


// Ingested cures (pills / drinks) need to lower severity the same as
// injections. This regression-tests the bug where conditions only
// checked bloodstr — ingested chems transfer to bloodstr and get
// consumed within the same Life tick, so by the time tick
// ran, bloodstr was empty even though the patient had a full stomach
// of medicine. Fix: dq_reagent_present() checks ingested as well.

/datum/unit_test/dq_medical_condition_cure_ingested_lowers_severity

/datum/unit_test/dq_medical_condition_cure_ingested_lowers_severity/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/internal_hemorrhage/C = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/internal_hemorrhage)
	TEST_ASSERT_NOTNULL(C, "spawn failed")

	for(var/i in 1 to 10)
		C.tick()
	var/before_cure = C.severity
	TEST_ASSERT(before_cure > 0, "severity must rise above 0 before testing cure")

	// Put the chem in the gut — that's where it lands when a player
	// swallows a pill. Bloodstr is empty.
	H.ingested.add_reagent(REAGENT_ID_BICARIDAZE, 50)
	TEST_ASSERT(!H.bloodstr.has_reagent(REAGENT_ID_BICARIDAZE), "bloodstr should be empty pre-tick (chem is in gut)")
	for(var/i in 1 to 5)
		C.tick()
	TEST_ASSERT(C.severity < before_cure, "swallowed cure should lower severity ([before_cure] -> [C.severity])")

// --- injury triggers from limb damage cascades ----------------------------

/datum/unit_test/dq_medical_cascade_via_limb_damage

/datum/unit_test/dq_medical_cascade_via_limb_damage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)

	// Hit with sharp brute 50 — internal_hemorrhage rule is `sharp && damage >= 5`,
	// 40% prob. Run many times to confirm at least one spawn.
	var/sawit = FALSE
	for(var/i in 1 to 40)
		chest.dq_check_damage_cascades(CUT, 50)
		for(var/datum/affliction/c in chest.afflictions_here())
			if(istype(c, /datum/affliction/internal_hemorrhage))
				sawit = TRUE
				break
		if(sawit)
			break
	TEST_ASSERT(sawit, "no internal_hemorrhage spawned across 40 cascade rolls")

// --- organ damage at high severity --------------------------------------

/datum/unit_test/dq_medical_high_severity_damages_organ

/datum/unit_test/dq_medical_high_severity_damages_organ/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	var/obj/item/organ/internal/heart/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_NOTNULL(heart, "test human has no heart")

	var/datum/affliction/heart_damage/C = H.body.afflict(/datum/affliction/heart_damage, chest)
	TEST_ASSERT_NOTNULL(C, "heart_damage could not be afflicted")
	C.severity = 90

	var/heart_dmg_before = heart.damage
	_dq_tick_n(C, 5)
	TEST_ASSERT(heart.damage > heart_dmg_before, "heart_damage at severity 90 should damage the heart ([heart_dmg_before] -> [heart.damage])")

// --- high-severity hypovolemic_shock starves the tissues ------------------

/datum/unit_test/dq_medical_high_severity_oxy_damage

/datum/unit_test/dq_medical_high_severity_oxy_damage/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)

	var/datum/affliction/hypovolemic_shock/C = H.body.afflict(/datum/affliction/hypovolemic_shock, chest)
	TEST_ASSERT_NOTNULL(C, "hypovolemic_shock could not be afflicted")
	C.severity = 90

	var/oxy_before = H.oxygen_debt()
	_dq_tick_n(C, 5)
	for(var/i in 1 to 5)
		H.body.physiology_tick(2)
	TEST_ASSERT(H.oxygen_debt() > oxy_before, "hypovolemic_shock at severity 90 should cause oxygen debt ([oxy_before] -> [H.oxygen_debt()])")

// --- shared helpers ------------------------------------------------------

/datum/unit_test/proc/_spawn_affliction_on(mob/living/carbon/human/H, organ_tag, condition_type)
	var/obj/item/organ/O = H.get_organ(organ_tag)
	if(!O)
		// Internal-organ tags (O_HEART, O_LUNGS, O_BRAIN, O_EYES, etc.)
		// aren't returned by get_organ() — that one resolves external
		// limbs only. Fall back to internal_organs_by_name.
		O = H.internal_organs_by_name[organ_tag]
	if(!O)
		return null
	return H.body.afflict(condition_type, O)

/datum/unit_test/proc/_dq_tick_n(datum/affliction/C, n)
	for(var/i in 1 to n)
		C.tick()

// --- ischemic multi-organ damage -----------------------------------------

/datum/unit_test/dq_medical_ischemia_damages_organs

/datum/unit_test/dq_medical_ischemia_damages_organs/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	var/obj/item/organ/internal/kidneys = H.internal_organs_by_name[O_KIDNEYS]
	TEST_ASSERT_NOTNULL(liver, "no liver")
	TEST_ASSERT_NOTNULL(kidneys, "no kidneys")

	// Push the oxygen debt above the ischemia threshold.
	H.add_oxygen_debt(50, "unit test")
	TEST_ASSERT(H.oxygen_debt() >= 50, "explicit oxygen debt did not land")
	var/liver_before = liver.damage
	var/kidney_before = kidneys.damage
	for(var/i in 1 to 30)  // probabilistic per tick, run several
		H.dq_check_ischemic_damage()
	TEST_ASSERT(liver.damage > liver_before, "sustained hypoxia should damage the liver ([liver_before] -> [liver.damage])")
	TEST_ASSERT(kidneys.damage > kidney_before, "sustained hypoxia should damage the kidneys ([kidney_before] -> [kidneys.damage])")

// --- emergent organ-failure conditions -----------------------------------

/datum/unit_test/dq_medical_organ_failure_emergent

/datum/unit_test/dq_medical_organ_failure_emergent/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.internal_organs_by_name[O_LIVER]
	var/obj/item/organ/internal/kidneys = H.internal_organs_by_name[O_KIDNEYS]

	dq_test_set_organ_damage(liver, liver.max_damage * 0.75)
	dq_test_set_organ_damage(kidneys, kidneys.max_damage * 0.75)
	H.dq_check_emergent_conditions()

	var/saw_hep = FALSE
	for(var/datum/affliction/c in liver.afflictions_here())
		if(istype(c, /datum/affliction/hepatic_failure))
			saw_hep = TRUE
			break
	TEST_ASSERT(saw_hep, "75% liver damage should spawn hepatic_failure")

	var/saw_ren = FALSE
	for(var/datum/affliction/c in kidneys.afflictions_here())
		if(istype(c, /datum/affliction/renal_failure))
			saw_ren = TRUE
			break
	TEST_ASSERT(saw_ren, "75% kidney damage should spawn renal_failure")

// --- chain: infection ----------------------------------------------------

/datum/unit_test/dq_medical_chain_infection

/datum/unit_test/dq_medical_chain_infection/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	TEST_ASSERT_NOTNULL(chest, "no chest organ")

	// Spawn wound_infection and tick until severity crosses cascade_at (70).
	// Force severity directly so the test doesn't have to wait through
	// the natural progression curve.
	var/datum/affliction/wound_infection/wi = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/wound_infection)
	TEST_ASSERT_NOTNULL(wi, "wound_infection didn't spawn")
	wi.severity = 70.0
	// Cascade rolls at 60% per tick once severity ≥ cascade_at. Force
	// a few ticks; cellulitis should appear.
	var/saw_cellulitis = FALSE
	for(var/i in 1 to 30)
		wi.tick()
		for(var/datum/affliction/c in chest.afflictions_here())
			if(istype(c, /datum/affliction/cellulitis))
				saw_cellulitis = TRUE
				break
		if(saw_cellulitis)
			break
	TEST_ASSERT(saw_cellulitis, "wound_infection did not cascade to cellulitis after 30 ticks at threshold")

	// Force cellulitis severity high, tick until sepsis spawns.
	for(var/datum/affliction/cellulitis/c in chest.afflictions_here())
		c.severity = 80
	var/saw_sepsis = FALSE
	for(var/i in 1 to 30)
		for(var/datum/affliction/cellulitis/c in chest.afflictions_here())
			c.tick()
		for(var/datum/affliction/c in chest.afflictions_here())
			if(istype(c, /datum/affliction/sepsis))
				saw_sepsis = TRUE
				break
		if(saw_sepsis)
			break
	TEST_ASSERT(saw_sepsis, "cellulitis did not cascade to sepsis")

	// And sepsis → septic_shock.
	for(var/datum/affliction/sepsis/c in chest.afflictions_here())
		c.severity = 75
	var/saw_shock = FALSE
	for(var/i in 1 to 30)
		for(var/datum/affliction/sepsis/c in chest.afflictions_here())
			c.tick()
		for(var/datum/affliction/c in chest.afflictions_here())
			if(istype(c, /datum/affliction/septic_shock))
				saw_shock = TRUE
				break
		if(saw_shock)
			break
	TEST_ASSERT(saw_shock, "sepsis did not cascade to septic_shock")

// --- chain: brain ---------------------------------------------------------

/datum/unit_test/dq_medical_chain_brain

/datum/unit_test/dq_medical_chain_brain/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/head = H.get_organ(BP_HEAD)
	TEST_ASSERT_NOTNULL(head, "no head organ")

	// First head hit: should spawn concussion. Force prob via many tries.
	var/saw_concussion = FALSE
	for(var/i in 1 to 40)
		head.dq_check_damage_cascades(BRUISE, 10)
		for(var/datum/affliction/c in head.afflictions_here())
			if(istype(c, /datum/affliction/concussion))
				saw_concussion = TRUE
				break
		if(saw_concussion)
			break
	TEST_ASSERT(saw_concussion, "first head hit didn't spawn concussion")

	// Second head hit while concussion active: should spawn subdural_hematoma.
	var/saw_subdural = FALSE
	for(var/i in 1 to 40)
		head.dq_check_damage_cascades(BRUISE, 10)
		for(var/datum/affliction/c in head.afflictions_here())
			if(istype(c, /datum/affliction/subdural_hematoma))
				saw_subdural = TRUE
				break
		if(saw_subdural)
			break
	TEST_ASSERT(saw_subdural, "second head hit didn't spawn subdural_hematoma")

	// brain_damage Critical stage is damage-emergent at >80% brain damage.
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	TEST_ASSERT_NOTNULL(brain, "no brain organ")
	dq_test_set_organ_damage(brain, brain.max_damage * 0.85)
	H.dq_check_emergent_conditions()
	var/datum/affliction/brain_damage/bd
	for(var/datum/affliction/c in brain.afflictions_here())
		if(istype(c, /datum/affliction/brain_damage))
			bd = c
			break
	TEST_ASSERT_NOTNULL(bd, "85% brain damage should spawn brain_damage via emergent system")
	TEST_ASSERT_EQUAL(bd.stage, "Critical", "85% brain damage should advance brain_damage to Critical stage (got [bd.stage])")

// --- chain: respiratory --------------------------------------------------

/datum/unit_test/dq_medical_chain_respiratory

/datum/unit_test/dq_medical_chain_respiratory/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)

	// pulmonary_contusion spawns on blunt chest ≥10 @ 40%
	var/saw_pc = FALSE
	for(var/i in 1 to 40)
		chest.dq_check_damage_cascades(BRUISE, 15)
		for(var/datum/affliction/c in chest.afflictions_here())
			if(istype(c, /datum/affliction/pulmonary_contusion))
				saw_pc = TRUE
				break
		if(saw_pc)
			break
	TEST_ASSERT(saw_pc, "blunt chest didn't spawn pulmonary_contusion")

	// respiratory_failure is damage-emergent: drive lung damage past
	// 70% and the emergent system should spawn it.
	var/obj/item/organ/internal/lungs = H.internal_organs_by_name[O_LUNGS]
	TEST_ASSERT_NOTNULL(lungs, "no lungs organ")
	dq_test_set_organ_damage(lungs, lungs.max_damage * 0.75)
	H.dq_check_emergent_conditions()
	var/saw_rf = FALSE
	for(var/datum/affliction/c in lungs.afflictions_here())
		if(istype(c, /datum/affliction/respiratory_failure))
			saw_rf = TRUE
			break
	TEST_ASSERT(saw_rf, "75% lung damage should spawn respiratory_failure via emergent system")

	// Confirm respiratory_failure causes hypoxia while present.
	var/datum/affliction/respiratory_failure/rf = H.body.find_affliction(/datum/affliction/respiratory_failure, lungs)
	if(rf)
		// Established failure: mild failure alone still oxygenates above the critical ratio.
		rf.set_severity(100)
		var/oxy_before = H.oxygen_debt()
		for(var/i in 1 to 5)
			rf.tick()
			H.body.physiology_tick(2)
		TEST_ASSERT(H.oxygen_debt() > oxy_before, "respiratory_failure should cause oxygen debt ([oxy_before] -> [H.oxygen_debt()])")

	// And when lungs heal back below threshold, the condition auto-cures.
	dq_test_set_organ_damage(lungs, lungs.max_damage * 0.5)
	H.dq_check_emergent_conditions()
	var/still_present = FALSE
	for(var/datum/affliction/c in lungs.afflictions_here())
		if(istype(c, /datum/affliction/respiratory_failure))
			still_present = TRUE
			break
	TEST_ASSERT(!still_present, "respiratory_failure should auto-cure when lung damage drops below threshold")

// --- limb: tendon_severed (mechanical: blocks affected arm) --------------

/datum/unit_test/dq_medical_limb_tendon_severed_arm

/datum/unit_test/dq_medical_limb_tendon_severed_arm/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/tendon_severed/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/tendon_severed)
	TEST_ASSERT_NOTNULL(C, "tendon_severed didn't spawn")
	C.tick()
	TEST_ASSERT(H.action_blocked(ACTION_BLOCK_HOLD_LEFT), "tendon_severed on left arm should disable that hand")
	TEST_ASSERT(!H.action_blocked(ACTION_BLOCK_HOLD_RIGHT), "tendon_severed on left arm should NOT disable the right hand")

// --- limb: tendon_severed leg (mechanical: heavy slowdown) ---------------

/datum/unit_test/dq_medical_limb_tendon_severed_leg

/datum/unit_test/dq_medical_limb_tendon_severed_leg/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/tendon_severed/C = _spawn_affliction_on(H, BP_L_LEG, /datum/affliction/tendon_severed)
	TEST_ASSERT_NOTNULL(C, "tendon_severed didn't spawn")
	C.tick()
	TEST_ASSERT(H.factor(BF_SLOWDOWN) > 1.0, "tendon_severed on leg should slow movement ([H.factor(BF_SLOWDOWN)])")

// --- mechanical: slowdown aggregates across conditions ------------------

/datum/unit_test/dq_medical_mechanical_slowdown_aggregates

/datum/unit_test/dq_medical_mechanical_slowdown_aggregates/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/base = H.factor(BF_SLOWDOWN)
	TEST_ASSERT(abs(base - H.species.baseline_factor(BF_SLOWDOWN)) < 0.001, "fresh mob should have only its species slowdown")

	// Affliction factors are authored at severity 100 and scale with it.
	var/datum/affliction/cellulitis = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/cellulitis)  // slowdown 0.3
	cellulitis.set_severity(100)
	TEST_ASSERT(abs(H.factor(BF_SLOWDOWN) - base - 0.3) < 0.01, "single cellulitis at full severity should give 0.3 slowdown (got [H.factor(BF_SLOWDOWN) - base])")

	var/datum/affliction/sepsis = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/sepsis)      // slowdown 0.6
	sepsis.set_severity(100)
	TEST_ASSERT(abs(H.factor(BF_SLOWDOWN) - base - 0.9) < 0.01, "cellulitis + sepsis should give 0.9 slowdown (got [H.factor(BF_SLOWDOWN) - base])")

	sepsis.set_severity(50)
	TEST_ASSERT(abs(H.factor(BF_SLOWDOWN) - base - 0.6) < 0.01, "sepsis at half severity should give half its slowdown (got [H.factor(BF_SLOWDOWN) - base])")

// --- mechanical: verb-block ----------------------------------------------

/datum/unit_test/dq_medical_mechanical_verb_block

/datum/unit_test/dq_medical_mechanical_verb_block/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT(!H.action_blocked(ACTION_BLOCK_SURGERY), "fresh mob shouldn't have blocked actions")
	var/datum/affliction/hematoma = _spawn_affliction_on(H, BP_HEAD, /datum/affliction/subdural_hematoma)
	hematoma.set_severity(40)
	TEST_ASSERT(H.action_blocked(ACTION_BLOCK_SURGERY), "subdural_hematoma should block surgery")

// --- burn_shock staging --------------------------------------------------

/datum/unit_test/dq_medical_burn_shock_stages

/datum/unit_test/dq_medical_burn_shock_stages/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/burn_shock/C = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/burn_shock)
	TEST_ASSERT_NOTNULL(C, "burn_shock didn't spawn")

	// Stage 1: no burns. After one tick, stage should resolve to 1.
	C.tick()
	TEST_ASSERT_EQUAL(C.stage, "Stage 1", "fresh patient should be Stage 1 burn_shock (got [C.stage])")

	// Burn the four limbs (~80 total) to push to stage 2. Spread over
	// several limbs so no single part is destroyed.
	var/list/limb_zones = list(BP_L_ARM, BP_R_ARM, BP_L_LEG, BP_R_LEG)
	for(var/zone in limb_zones)
		H.injure(INJURY_BURN, 20, zone, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/total_burn = H.injury_load(INJURY_CATEGORY_THERMAL)
	TEST_ASSERT(total_burn >= 60 && total_burn < 120, "limb burns should total stage-2 range (got [total_burn])")
	C.tick()
	TEST_ASSERT_EQUAL(C.stage, "Stage 2", "[total_burn] total burn should be Stage 2 (got [C.stage])")

	// Burn the groin and torso too (~150 total) to push to stage 3.
	H.injure(INJURY_BURN, 35, BP_GROIN, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	H.injure(INJURY_BURN, 35, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	total_burn = H.injury_load(INJURY_CATEGORY_THERMAL)
	TEST_ASSERT(total_burn >= 120, "whole-body burns should total stage-3 range (got [total_burn])")
	C.tick()
	TEST_ASSERT_EQUAL(C.stage, "Stage 3", "[total_burn] total burn should be Stage 3 (got [C.stage])")

	// Stage 3's factor table slows the patient heavily.
	var/stage_slowdown = H.factor(BF_SLOWDOWN) - H.species.baseline_factor(BF_SLOWDOWN)
	TEST_ASSERT(stage_slowdown > 1.0, "stage 3 slowdown should be >1.0 (got [stage_slowdown])")

	// Treat every burned part except the torso (where burn_shock itself
	// sits, so zone-limited burn care leaves it alone) — back below 60.
	for(var/zone in limb_zones + BP_GROIN)
		H.mend(TREAT_BURN_CARE, 100, zone)
	total_burn = H.injury_load(INJURY_CATEGORY_THERMAL)
	TEST_ASSERT(total_burn < 60, "burn care should bring total burns under 60 (got [total_burn])")
	TEST_ASSERT(!QDELETED(C), "zone-limited burn care should not have touched the torso's burn_shock")
	C.tick()
	TEST_ASSERT_EQUAL(C.stage, "Stage 1", "after healing burns back to [total_burn], should be Stage 1 (got [C.stage])")

// --- bleed conditions drain blood ---------------------------------------

/datum/unit_test/dq_medical_bleed_drains_blood

/datum/unit_test/dq_medical_bleed_drains_blood/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H.vessel, "test human has no blood vessel")
	var/start_blood = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	TEST_ASSERT(start_blood > 0, "test human should start with blood")

	// Active internal_hemorrhage at severity 50 should drain blood per
	// tick. Spawn, force severity, tick a handful of times, verify drop.
	var/datum/affliction/internal_hemorrhage/C = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/internal_hemorrhage)
	TEST_ASSERT_NOTNULL(C, "internal_hemorrhage didn't spawn")
	C.severity = 50
	_dq_tick_n(C, 10)
	var/blood_after = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	TEST_ASSERT(blood_after < start_blood, "internal_hemorrhage should have drained blood ([start_blood] -> [blood_after])")

// --- concussion self-heals ----------------------------------------------

/datum/unit_test/dq_medical_concussion_self_heals

/datum/unit_test/dq_medical_concussion_self_heals/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/concussion/C = _spawn_affliction_on(H, BP_HEAD, /datum/affliction/concussion)
	TEST_ASSERT_NOTNULL(C, "concussion didn't spawn")
	var/start = C.severity
	TEST_ASSERT(start > 0, "concussion should start with positive severity (New override)")
	// progression_rate = -0.15 → severity drifts down without
	// intervention. After many ticks the condition should be cured.
	for(var/i in 1 to 1000)
		if(QDELETED(C) || !(C in H.get_afflictions()))
			break
		C.tick()
	var/still_present = FALSE
	for(var/datum/affliction/c in H.get_afflictions())
		if(istype(c, /datum/affliction/concussion))
			still_present = TRUE
			break
	TEST_ASSERT(!still_present, "concussion should have self-cleared after 1000 ticks of negative progression")

// --- examine surface ----------------------------------------------------

/datum/unit_test/dq_medical_examine_lists_visible_symptoms

/datum/unit_test/dq_medical_examine_lists_visible_symptoms/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Without conditions, the glance diagnosis has no examine lines.
	var/list/empty = H.diagnose(/datum/diagnostic_profile/glance).examine_lines()
	TEST_ASSERT_EQUAL(length(empty), 0, "no conditions = no visible-symptom lines (got [length(empty)])")

	// Spawn lacerated_artery and force-roll bleeding_visible into the
	// active symptom set so examine should report it.
	var/datum/affliction/lacerated_artery/C = _spawn_affliction_on(H, BP_L_ARM, /datum/affliction/lacerated_artery)
	C.severity = 80
	C.tick()  // rolls symptoms
	// Force bleeding_visible if RNG didn't pick it (typepaths: singletons).
	if(!(/datum/affliction_symptom/bleeding_visible in C.active_symptoms))
		LAZYADD(C.active_symptoms, /datum/affliction_symptom/bleeding_visible)
	var/list/lines = H.diagnose(/datum/diagnostic_profile/glance).examine_lines()
	TEST_ASSERT(length(lines) > 0, "examine helper should return at least one visible-symptom line")
	var/found_bleeding = FALSE
	for(var/line in lines)
		if(findtext(line, "bleeding"))
			found_bleeding = TRUE
			break
	TEST_ASSERT(found_bleeding, "examine helper should report bleeding when bleeding_visible is active")


// --- vital reading jitter ----------------------------------------------

/datum/unit_test/dq_medical_vital_readings_jitter

/datum/unit_test/dq_medical_vital_readings_jitter/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Take many pulse readings; expect not every value to be identical.
	var/list/readings = list()
	for(var/i in 1 to 30)
		readings += H.get_pulse_reading_bpm()
	var/seen_difference = FALSE
	for(var/i in 2 to length(readings))
		if(readings[i] != readings[1])
			seen_difference = TRUE
			break
	TEST_ASSERT(seen_difference, "pulse readings should vary across 30 calls due to jitter (all returned [readings[1]])")


// --- severity-scaled mechanical effects --------------------------------

/datum/unit_test/dq_medical_hypovolemic_shock_severity_bands

/datum/unit_test/dq_medical_hypovolemic_shock_severity_bands/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/hypovolemic_shock/C = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/hypovolemic_shock)
	TEST_ASSERT_NOTNULL(C, "hypovolemic_shock didn't spawn")

	// Stage 1 (mild): severity 20 → small slowdown.
	C.severity = 20
	C.tick()
	var/slow_mild = H.factor(BF_SLOWDOWN)
	// Stage 2 (moderate): severity 40 → bigger slowdown.
	C.severity = 40
	C.tick()
	var/slow_moderate = H.factor(BF_SLOWDOWN)
	// Stage 3 (severe): severity 80 → heavy slowdown.
	C.severity = 80
	C.tick()
	var/slow_severe = H.factor(BF_SLOWDOWN)

	TEST_ASSERT(slow_mild < slow_moderate, "mild slowdown ([slow_mild]) should be less than moderate ([slow_moderate])")
	TEST_ASSERT(slow_moderate < slow_severe, "moderate slowdown ([slow_moderate]) should be less than severe ([slow_severe])")


// --- fever push (real body temperature) --------------------------------

/datum/unit_test/dq_medical_cellulitis_pushes_temperature

/datum/unit_test/dq_medical_cellulitis_pushes_temperature/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/cellulitis/C = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/cellulitis)
	TEST_ASSERT_NOTNULL(C, "cellulitis didn't spawn")
	C.severity = 80

	var/temp_before = H.bodytemperature
	for(var/i in 1 to 10)
		C.tick()
	TEST_ASSERT(H.bodytemperature > temp_before, "cellulitis at high severity should raise body temperature ([temp_before] -> [H.bodytemperature])")


// --- contraindicated reagent worsens severity --------------------------

/datum/unit_test/dq_medical_contraindicated_reagent_worsens

/datum/unit_test/dq_medical_contraindicated_reagent_worsens/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/datum/affliction/internal_hemorrhage/C = _spawn_affliction_on(H, BP_TORSO, /datum/affliction/internal_hemorrhage)
	C.severity = 30
	// Baseline progression: tick a few times without hyperzine, record severity rise.
	_dq_tick_n(C, 3)
	var/no_hyper = C.severity
	// Reset, add hyperzine, tick again, compare.
	C.severity = 30
	H.bloodstr.add_reagent(REAGENT_ID_HYPERZINE, 30)
	_dq_tick_n(C, 3)
	var/with_hyper = C.severity
	TEST_ASSERT(with_hyper > no_hyper, "hyperzine should worsen internal_hemorrhage progression (no=[no_hyper], with=[with_hyper])")


// --- emergent auto-cure round-trip --------------------------------------

/datum/unit_test/dq_medical_emergent_auto_cures_when_organ_heals

/datum/unit_test/dq_medical_emergent_auto_cures_when_organ_heals/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/lungs = H.internal_organs_by_name[O_LUNGS]
	// Spawn respiratory_failure by damaging lungs past 70%.
	dq_test_set_organ_damage(lungs, lungs.max_damage * 0.8)
	H.dq_check_emergent_conditions()
	var/saw_rf = FALSE
	for(var/datum/affliction/c in lungs.afflictions_here())
		if(istype(c, /datum/affliction/respiratory_failure))
			saw_rf = TRUE
			break
	TEST_ASSERT(saw_rf, "respiratory_failure should appear at 80% lung damage")

	// Heal lungs back below threshold and re-check — it should auto-cure.
	dq_test_set_organ_damage(lungs, lungs.max_damage * 0.3)
	H.dq_check_emergent_conditions()
	var/still = FALSE
	for(var/datum/affliction/c in lungs.afflictions_here())
		if(istype(c, /datum/affliction/respiratory_failure))
			still = TRUE
			break
	TEST_ASSERT(!still, "respiratory_failure should auto-cure when lung damage drops below threshold")


// --- cause registry: every emergent condition has a producing cause ----

/datum/unit_test/dq_medical_cause_registry_covers_emergents

/datum/unit_test/dq_medical_cause_registry_covers_emergents/Run()
	affliction_triggers_registry()
	for(var/T in list(
		/datum/affliction/respiratory_failure,
		/datum/affliction/heart_damage,
		/datum/affliction/brain_damage,
		/datum/affliction/hepatic_failure,
		/datum/affliction/renal_failure,
		/datum/affliction/ischemic_vision_loss,
		/datum/affliction/acute_radiation,
	))
		var/list/producers = affliction_triggers_producing(T)
		TEST_ASSERT(length(producers) > 0, "[T] should have at least one cause producing it")


// --- categories: every condition declares one --------------------------

/datum/unit_test/dq_medical_all_conditions_categorized

/datum/unit_test/dq_medical_all_conditions_categorized/Run()
	for(var/T in dq_catalogued_affliction_types())
		var/datum/affliction/proto = dq_proto(T)
		TEST_ASSERT(proto.category, "[T] missing category")
		TEST_ASSERT(proto.clinical_description, "[T] missing clinical_description")


// --- gut translocation: ischemia raises intestine germ_level -----------

/datum/unit_test/dq_medical_gut_translocation_during_ischemia

/datum/unit_test/dq_medical_gut_translocation_during_ischemia/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/intestine = H.internal_organs_by_name[O_INTESTINE]
	TEST_ASSERT_NOTNULL(intestine, "no intestine")
	var/germ_before = intestine.germ_level
	// Push the oxygen debt well past the ischemia threshold.
	H.add_oxygen_debt(60, "unit test")
	for(var/i in 1 to 10)
		H.dq_check_ischemic_damage()
	TEST_ASSERT(intestine.germ_level > germ_before, "sustained ischemia should raise intestine germ_level ([germ_before] -> [intestine.germ_level])")


// --- scenarios: every scenario applies cleanly -------------------------

/datum/unit_test/dq_medical_scenarios_apply_cleanly

/datum/unit_test/dq_medical_scenarios_apply_cleanly/Run()
	for(var/T in subtypesof(/datum/dq_medical_scenario))
		var/datum/dq_medical_scenario/S = new T()
		var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
		S.apply(H)
		// A scenario should leave at least one condition on the patient.
		var/list/conds = H.get_afflictions()
		TEST_ASSERT(length(conds) > 0, "[T] applied no conditions")
		qdel(S)


// --- metric-driven conditions: radiation ------------------------------

/datum/unit_test/dq_medical_metric_radiation_spawns

/datum/unit_test/dq_medical_metric_radiation_spawns/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Push radiation past the moderate threshold (100). The collapsed
	// condition should appear at the highest matching tier — Moderate
	// at rad 150, since rad 300+ would be Severe.
	H.radiation = 150
	H.dq_check_metric_conditions()
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_NOTNULL(heart, "no heart")
	var/datum/affliction/acute_radiation/ar
	for(var/datum/affliction/c in heart.afflictions_here())
		if(istype(c, /datum/affliction/acute_radiation))
			ar = c
			break
	TEST_ASSERT_NOTNULL(ar, "radiation 150 should spawn acute_radiation")
	TEST_ASSERT_EQUAL(ar.stage, "Moderate", "radiation 150 should select the Moderate stage (got [ar.stage])")

	// Drop back to safe, re-dispatch — should auto-cure.
	H.radiation = 0
	H.dq_check_metric_conditions()
	var/still = FALSE
	for(var/datum/affliction/c in heart.afflictions_here())
		if(istype(c, /datum/affliction/acute_radiation))
			still = TRUE
			break
	TEST_ASSERT(!still, "acute_radiation should auto-cure when rad drops to 0")


// --- metric-driven conditions: temperature ----------------------------

/datum/unit_test/dq_medical_metric_temperature_extremes

/datum/unit_test/dq_medical_metric_temperature_extremes/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	// Drop body temperature way below normal.
	H.bodytemperature = BODYTEMP_NORMAL - 25  // 25K below 37°C
	H.dq_check_metric_conditions()
	var/obj/item/organ/external/torso = H.get_organ(BP_TORSO)
	var/saw_hypo = FALSE
	for(var/datum/affliction/c in torso.afflictions_here())
		if(istype(c, /datum/affliction/hypothermia))
			saw_hypo = TRUE
			break
	TEST_ASSERT(saw_hypo, "cold body temperature should spawn hypothermia")

	// Now spike to overheated.
	H.bodytemperature = BODYTEMP_NORMAL + 10
	H.dq_check_metric_conditions()
	var/saw_heat = FALSE
	for(var/datum/affliction/c in torso.afflictions_here())
		if(istype(c, /datum/affliction/heatstroke))
			saw_heat = TRUE
			break
	TEST_ASSERT(saw_heat, "hot body temperature should spawn heatstroke")
