// Abilities (roadmap P5, doc/rewrite/rules.md §5): the shadekin phase shift
// port. General interaction well-formedness (id, name, category, compiling
// requirements) is already covered by dq_interaction_definitions
// (dq_interaction_tests.dm); this file checks the ability-specific behaviour:
// requirements-then-commit ordering (doc/rewrite/fixes.md B13) and the
// resource cost.

/datum/unit_test/proc/dq_phase_ability()
	return ABILITY_BY_ID(ABILITY_ID_SHADEKIN_PHASE_SHIFT)

/// A shadekin human on an open turf, with full energy.
/datum/unit_test/proc/dq_phase_test_human()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/component/shadekin/SK = H.AddComponent(/datum/component/shadekin/full)
	SK.dark_energy = SK.max_dark_energy
	return H

/// B13: a requirement failure must not spend energy. Being mid-phase already
/// (dq_pred_not_phasing) is the cheapest requirement to force deterministically.
/datum/unit_test/dq_ability_phase_shift_blocked_spends_nothing

/datum/unit_test/dq_ability_phase_shift_blocked_spends_nothing/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	var/datum/interaction/ability/A = dq_phase_ability()
	TEST_ASSERT_NOTNULL(A, "shadekin_phase_shift is registered")

	SK.doing_phase = TRUE
	var/before = SK.shadekin_get_energy()
	TEST_ASSERT_EQUAL(A.why_not(H, H, null), "you are already trying to phase", "blocked with the right reason")
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_BLOCKED, "attempt() reports blocked")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before, "energy is untouched when a requirement fails")
	TEST_ASSERT_EQUAL(H.dq_phase_shift_pending_cost, 0, "no cost was cached for a requirement that never reached the resource check")

/// B13, the other half of the ordering fix: an area that blocks phase shift
/// must refuse (and not spend) even though every other requirement passes.
/datum/unit_test/dq_ability_phase_shift_area_blocks

/datum/unit_test/dq_ability_phase_shift_area_blocks/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	var/datum/interaction/ability/A = dq_phase_ability()
	var/turf/T = get_turf(H)
	var/area/original = get_area(T)
	var/area/dq_test_phase_block/blocked_area = new()
	ChangeArea(T, blocked_area)

	var/before = SK.shadekin_get_energy()
	TEST_ASSERT_EQUAL(A.why_not(H, H, null), "you can't do that here", "the area's block is the failing reason")
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_BLOCKED, "attempt() reports blocked")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before, "a blocked shift never spends energy, however late the block is found")
	TEST_ASSERT(!SK.in_phase, "a blocked shift never runs its effect")

	ChangeArea(T, original)
	qdel(blocked_area)

/// A successful shift commits exactly the cost that was checked, and runs the effect.
/datum/unit_test/dq_ability_phase_shift_commits

/datum/unit_test/dq_ability_phase_shift_commits/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	var/datum/interaction/ability/A = dq_phase_ability()

	TEST_ASSERT_NULL(A.why_not(H, H, null), "an unblocked shadekin can phase shift")
	var/before = SK.shadekin_get_energy()
	var/expected_cost = H.dq_phase_shift_afford(H, H, null) && H.dq_phase_shift_pending_cost
	TEST_ASSERT(expected_cost > 0, "phasing out has a real cost")
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_RAN, "the shift runs")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - expected_cost, "exactly the checked cost was spent")
	TEST_ASSERT(SK.doing_phase, "the effect started a phase transition")
	TEST_ASSERT_EQUAL(H.dq_phase_shift_pending_cost, 0, "the cached cost is consumed once spent")

/// Phasing back in (in_phase already TRUE) is free, regardless of watchers.
/datum/unit_test/dq_ability_phase_shift_returning_is_free

/datum/unit_test/dq_ability_phase_shift_returning_is_free/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	SK.in_phase = TRUE
	var/before = SK.shadekin_get_energy()
	var/datum/interaction/ability/A = dq_phase_ability()
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_RAN, "phasing back in runs")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before, "returning to realspace costs nothing")
	TEST_ASSERT(!SK.in_phase, "the effect completed the return")

/// A watcher raises the cost by exactly 15, computed once (fixes.md B13's second half).
/datum/unit_test/dq_ability_phase_shift_watcher_cost

/datum/unit_test/dq_ability_phase_shift_watcher_cost/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/turf/T = get_turf(H)
	var/base_cost = (H.dq_phase_shift_afford(H, H, null) && H.dq_phase_shift_pending_cost) || H.dq_phase_shift_pending_cost

	var/mob/living/carbon/human/watcher = allocate(/mob/living/carbon/human, get_step(T, NORTH))
	var/with_watcher_cost = (H.dq_phase_shift_afford(H, H, null) && H.dq_phase_shift_pending_cost) || H.dq_phase_shift_pending_cost
	TEST_ASSERT_EQUAL(with_watcher_cost - base_cost, 15, "one watcher adds exactly 15 energy to the cost")
	qdel(watcher)

/// Without the shadekin component's grant, phase shift refuses everyone -
/// requirements are never even consulted.
/datum/unit_test/dq_ability_phase_shift_needs_grant

/datum/unit_test/dq_ability_phase_shift_needs_grant/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/interaction/ability/A = dq_phase_ability()
	TEST_ASSERT(!H.has_ability(ABILITY_ID_SHADEKIN_PHASE_SHIFT), "an ordinary human has no grant")
	TEST_ASSERT_EQUAL(A.why_not(H, H, null), "you don't have that ability", "refused before any requirement runs")

/// Two sources granting the same ability: it survives either one alone being revoked.
/datum/unit_test/dq_ability_grant_survives_while_any_source_remains

/datum/unit_test/dq_ability_grant_survives_while_any_source_remains/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source_a = new /datum()
	var/datum/source_b = new /datum()
	H.grant_ability("dq_test_ability", source_a)
	TEST_ASSERT(H.has_ability("dq_test_ability"), "granted by one source")
	H.grant_ability("dq_test_ability", source_b)
	TEST_ASSERT_EQUAL(length(H.ability_sources("dq_test_ability")), 2, "both sources are tracked")
	H.revoke_ability("dq_test_ability", source_a)
	TEST_ASSERT(H.has_ability("dq_test_ability"), "still granted through source_b")
	H.revoke_ability("dq_test_ability", source_b)
	TEST_ASSERT(!H.has_ability("dq_test_ability"), "gone once every source has revoked")
	TEST_ASSERT_NULL(H.ability_sources("dq_test_ability"), "no leftover empty source list")
	qdel(source_a)
	qdel(source_b)

// ---- Dark respite ----

/datum/unit_test/proc/dq_respite_ability()
	return ABILITY_BY_ID(ABILITY_ID_SHADEKIN_DARK_RESPITE)

/// A shadekin human in a /area/shadekin (Dark Respite's required area). Uses a
/// turf next to (not test_floor() itself), so mutating its area doesn't leak
/// into every other test sharing the canonical test floor.
/datum/unit_test/proc/dq_respite_test_human()
	var/turf/dark_turf = get_step(test_floor(), SOUTH)
	if(get_area(dark_turf).type != /area/shadekin)
		ChangeArea(dark_turf, new /area/shadekin())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, dark_turf)
	var/datum/component/shadekin/SK = H.AddComponent(/datum/component/shadekin/full)
	SK.dark_energy = SK.max_dark_energy
	return H

/// Only the full variant grants dark respite; phase_only does not.
/datum/unit_test/dq_ability_dark_respite_needs_full_variant

/datum/unit_test/dq_ability_dark_respite_needs_full_variant/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.AddComponent(/datum/component/shadekin/phase_only)
	TEST_ASSERT(H.has_ability(ABILITY_ID_SHADEKIN_PHASE_SHIFT), "phase_only still grants phase shift")
	TEST_ASSERT(!H.has_ability(ABILITY_ID_SHADEKIN_DARK_RESPITE), "phase_only does not grant dark respite")

/// Toggling starts and stops a Dark Respite modifier.
/datum/unit_test/dq_ability_dark_respite_toggles

/datum/unit_test/dq_ability_dark_respite_toggles/Run()
	var/mob/living/carbon/human/H = dq_respite_test_human()
	var/datum/interaction/ability/A = dq_respite_ability()
	TEST_ASSERT_NULL(A.why_not(H, H, null), "an unblocked shadekin can start Dark Respite")
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_RAN, "starting it runs")
	TEST_ASSERT(H.has_modifier_of_type(/datum/modifier/dark_respite), "the modifier is applied")
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_RAN, "triggering it again runs")
	TEST_ASSERT(!H.has_modifier_of_type(/datum/modifier/dark_respite), "the second use ends it")

/// The fix found while porting: a Dark Respite an emergency warp started can't
/// be manually ended (the legacy verb warned about this but didn't enforce it).
/datum/unit_test/dq_ability_dark_respite_warp_triggered_cannot_be_manually_ended

/datum/unit_test/dq_ability_dark_respite_warp_triggered_cannot_be_manually_ended/Run()
	var/mob/living/carbon/human/H = dq_respite_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	H.add_modifier(/datum/modifier/dark_respite) // as an emergency warp would, not through the ability
	SK.manual_respite = FALSE
	var/datum/interaction/ability/A = dq_respite_ability()
	TEST_ASSERT_EQUAL(A.why_not(H, H, null), "you cannot manually end a Dark Respite triggered by an emergency warp", "blocked with the documented reason")
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_BLOCKED, "attempt() actually refuses, unlike the legacy verb")
	TEST_ASSERT(H.has_modifier_of_type(/datum/modifier/dark_respite), "the emergency-warp respite is still running")

/// Dark Respite only works in the Dark.
/datum/unit_test/dq_ability_dark_respite_needs_dark_area

/datum/unit_test/dq_ability_dark_respite_needs_dark_area/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human() // not moved into /area/shadekin
	var/datum/interaction/ability/A = dq_respite_ability()
	TEST_ASSERT_EQUAL(A.why_not(H, H, null), "you can only trigger Dark Respite in the Dark", "blocked outside the Dark")

// ---- Regenerate other (a targeted ability, not a self one) ----

/datum/unit_test/dq_ability_regenerate_other_heals_a_neighbour

/datum/unit_test/dq_ability_regenerate_other_heals_a_neighbour/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	var/turf/T = get_turf(H)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, get_step(T, NORTH))
	var/datum/interaction/ability/A = ABILITY_BY_ID(ABILITY_ID_SHADEKIN_REGENERATE_OTHER)
	TEST_ASSERT_NOTNULL(A, "shadekin_regenerate_other is registered")

	TEST_ASSERT_EQUAL(A.why_not(H, H, null), "can't be done to yourself", "can't target yourself (REQ_NOT_SELF)")
	TEST_ASSERT_NULL(A.why_not(H, patient, null), "an adjacent shadekin can heal a neighbour")
	var/before = SK.shadekin_get_energy()
	TEST_ASSERT_EQUAL(A.attempt(H, patient, null), INTERACTION_TRY_RAN, "healing runs")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - 50, "the flat 50-energy cost was spent")
	TEST_ASSERT(patient.has_modifier_of_type(/datum/modifier/shadekin/heal_boop), "the patient is healing")

/datum/unit_test/dq_ability_regenerate_other_needs_energy

/datum/unit_test/dq_ability_regenerate_other_needs_energy/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	SK.dark_energy = 10
	var/turf/T = get_turf(H)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, get_step(T, NORTH))
	var/datum/interaction/ability/A = ABILITY_BY_ID(ABILITY_ID_SHADEKIN_REGENERATE_OTHER)
	TEST_ASSERT_EQUAL(A.why_not(H, patient, null), "not enough energy for that ability", "blocked with too little energy")

// ---- Create shade ----

/datum/unit_test/dq_ability_create_shade_applies_the_modifier

/datum/unit_test/dq_ability_create_shade_applies_the_modifier/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	var/datum/interaction/ability/A = ABILITY_BY_ID(ABILITY_ID_SHADEKIN_CREATE_SHADE)
	TEST_ASSERT_NOTNULL(A, "shadekin_create_shade is registered")
	TEST_ASSERT_NULL(A.why_not(H, H, null), "an unblocked shadekin can create a shade")
	var/before = SK.shadekin_get_energy()
	TEST_ASSERT_EQUAL(A.attempt(H, H, null), INTERACTION_TRY_RAN, "it runs")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - 25, "the flat 25-energy cost was spent")
	TEST_ASSERT(H.has_modifier_of_type(/datum/modifier/shadekin/create_shade), "the shade modifier is applied")

// ---- Dark maw ----
// (dark_maw's darkness requirement reads the turf's live get_lumcount(), which
// depends on the lighting subsystem's own tick - not exercised here to avoid
// a flaky dependency on lighting timing; the requirement itself is simple
// enough that dq_pred_dark_maw_dark_enough's logic is covered by inspection.)

/datum/unit_test/dq_ability_dark_maw_deploys_and_dispels

/datum/unit_test/dq_ability_dark_maw_deploys_and_dispels/Run()
	// Runs the effect directly rather than through attempt(): the test map's
	// default turf is lit, and both dark_maw's own darkness requirement
	// (dq_pred_dark_maw_dark_enough) and the spawned trap object's own
	// Initialize() light check would refuse/self-delete it there - a
	// live-lighting dependency this test avoids rather than fights. What's
	// under test is the ability's own logic: it spends its cost and defers to
	// the (unchanged) trap object, and clearing an empty trap list is safe.
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	var/before = SK.shadekin_get_energy()
	TEST_ASSERT(H.dq_do_dark_maw(H, null, null), "it deploys")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - 20, "the flat 20-energy cost was spent")

	TEST_ASSERT(H.dq_do_clear_dark_maws(H, null, null), "dispelling is safe with no traps registered")

// ---- Dark tunneling ----

/datum/unit_test/dq_ability_dark_tunneling_needs_energy

/datum/unit_test/dq_ability_dark_tunneling_needs_energy/Run()
	// Checks dq_pred_dark_tunnel_afford() directly rather than through why_not():
	// the test map's default turf isn't a valid shelter-deploy site, so the
	// (unrelated) site-readiness clause would fail first there and this test
	// would never reach the energy clause it's meant to exercise.
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	SK.dark_energy = 10
	var/datum/interaction/ability/A = ABILITY_BY_ID(ABILITY_ID_SHADEKIN_DARK_TUNNELING)
	TEST_ASSERT_NOTNULL(A, "shadekin_dark_tunneling is registered")
	TEST_ASSERT_EQUAL(H.dq_pred_dark_tunnel_afford(H, H, null), "not enough energy for that ability", "blocked with too little energy")

/datum/unit_test/dq_ability_dark_tunneling_once_only

/datum/unit_test/dq_ability_dark_tunneling_once_only/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/component/shadekin/SK = H.get_shadekin_component()
	SK.created_dark_tunnel = TRUE
	var/datum/interaction/ability/A = ABILITY_BY_ID(ABILITY_ID_SHADEKIN_DARK_TUNNELING)
	TEST_ASSERT_EQUAL(A.why_not(H, H, null), "you have already made a tunnel to the Dark", "blocked after one use")

// ---- Borg abilities ----

/datum/unit_test/dq_ability_robot_toggle_lights

/datum/unit_test/dq_ability_robot_toggle_lights/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	var/datum/interaction/ability/A = ABILITY_BY_ID(ABILITY_ID_ROBOT_TOGGLE_LIGHTS)
	TEST_ASSERT_NOTNULL(A, "robot_toggle_lights is registered")
	TEST_ASSERT(R.has_ability(ABILITY_ID_ROBOT_TOGGLE_LIGHTS), "every robot is granted this on spawn")
	var/before = R.lights_on
	TEST_ASSERT_EQUAL(A.attempt(R, R, null), INTERACTION_TRY_RAN, "toggling runs")
	TEST_ASSERT_NOTEQUAL(R.lights_on, before, "the light state flipped")
	qdel(R)

/// Test-only area that blocks phase shift.
/area/dq_test_phase_block
	name = "phase-block test area"
	flags = AREA_BLOCK_PHASE_SHIFT
