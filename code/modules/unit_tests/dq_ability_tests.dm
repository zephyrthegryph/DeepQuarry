// Abilities: ops with a menu() binding that a capability brings to its holder (shadekin powers, robot abilities). This file checks the
// ability-specific behaviour: requirements-then-commit ordering (doc/rewrite/fixes.md B13), the resource cost, and grants held by a source.

/// Runs the ability op `key` for `actor` the way a key press does. Returns the /datum/op_result.
/datum/unit_test/proc/dq_use_ability_op(mob/actor, key)
	return perform_op(actor, actor, key, null, ORIGIN_HOTKEY)

/// A shadekin human on an open turf, with full energy.
/datum/unit_test/proc/dq_phase_test_human()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/shadekin/SK = H.add_shadekin(/datum/shadekin/full)
	SK.dark_energy = SK.max_dark_energy
	return H

/// B13: a requirement failure must not spend energy. Being mid-phase already (ability_not_phasing) is the cheapest requirement to force
/// deterministically.
/datum/unit_test/dq_ability_phase_shift_blocked_spends_nothing

/datum/unit_test/dq_ability_phase_shift_blocked_spends_nothing/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	TEST_ASSERT(granted(H, shadekin_phase()), "shadekin_phase is granted")

	SK.doing_phase = TRUE
	var/before = SK.shadekin_get_energy()
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_PHASE_SHIFT)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the shift is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/shadekin_ability/already_phasing, "blocked with the right reason")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before, "energy is untouched when a requirement fails")

/// B13, the other half of the ordering fix: an area that blocks phase shift must refuse (and not spend) even though every other requirement
/// passes.
/datum/unit_test/dq_ability_phase_shift_area_blocks

/datum/unit_test/dq_ability_phase_shift_area_blocks/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	var/turf/T = get_turf(H)
	var/area/original = get_area(T)
	var/area/dq_test_phase_block/blocked_area = new()
	ChangeArea(T, blocked_area)

	var/before = SK.shadekin_get_energy()
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_PHASE_SHIFT)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the shift is refused")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/shadekin_ability/phase_area, "the area's block is the failing reason")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before, "a blocked shift never spends energy, however late the block is found")
	TEST_ASSERT(!SK.in_phase, "a blocked shift never runs its effect")

	ChangeArea(T, original)
	qdel(blocked_area)

/// A successful shift commits exactly the cost that was checked, and runs the effect.
/datum/unit_test/dq_ability_phase_shift_commits

/datum/unit_test/dq_ability_phase_shift_commits/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()

	var/before = SK.shadekin_get_energy()
	var/expected_cost = H.phase_shift_cost(SK)
	TEST_ASSERT(expected_cost > 0, "phasing out has a real cost")
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_PHASE_SHIFT)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "the shift runs")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - expected_cost, "exactly the checked cost was spent")
	TEST_ASSERT(SK.doing_phase, "the effect started a phase transition")
	for(var/obj/effect/temp_visual/V in get_turf(H))
		own(V)

/// Phasing back in (in_phase already TRUE) is free, regardless of watchers.
/datum/unit_test/dq_ability_phase_shift_returning_is_free

/datum/unit_test/dq_ability_phase_shift_returning_is_free/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	SK.in_phase = TRUE
	var/before = SK.shadekin_get_energy()
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_PHASE_SHIFT)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "phasing back in runs")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before, "returning to realspace costs nothing")
	TEST_ASSERT(!SK.in_phase, "the effect completed the return")
	for(var/obj/effect/temp_visual/V in get_turf(H))
		own(V)

/// A watcher raises the cost by exactly 15, computed once (fixes.md B13's second half).
/datum/unit_test/dq_ability_phase_shift_watcher_cost

/datum/unit_test/dq_ability_phase_shift_watcher_cost/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	var/turf/T = get_turf(H)
	var/base_cost = H.phase_shift_cost(SK)

	var/mob/living/carbon/human/watcher = allocate(/mob/living/carbon/human, get_step(T, NORTH))
	var/with_watcher_cost = H.phase_shift_cost(SK)
	TEST_ASSERT_EQUAL(with_watcher_cost - base_cost, 15, "one watcher adds exactly 15 energy to the cost")
	qdel(watcher)

/// Without the shadekin state's grant, phase shift refuses everyone: the op does not exist for the mob.
/datum/unit_test/dq_ability_phase_shift_needs_grant

/datum/unit_test/dq_ability_phase_shift_needs_grant/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	TEST_ASSERT(!granted(H, shadekin_phase()), "an ordinary human has no grant")
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_PHASE_SHIFT)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "refused before any requirement runs")

/// An ability is a capability held by its source: deleting the source ends the activation and takes the ability away, with no Destroy()
/// bookkeeping of its own.
/datum/unit_test/dq_ability_grant_dies_with_source

/datum/unit_test/dq_ability_grant_dies_with_source/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source = new /datum()
	grant(H, shadekin_phase(), source)
	TEST_ASSERT(granted(H, shadekin_phase()), "granted")
	qdel(source)
	TEST_ASSERT(!granted(H, shadekin_phase()), "deleting the source revokes its grant")

/// Two sources granting the same ability: it survives either one alone being revoked.
/datum/unit_test/dq_ability_grant_survives_while_any_source_remains

/datum/unit_test/dq_ability_grant_survives_while_any_source_remains/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/datum/source_a = new /datum()
	var/datum/source_b = new /datum()
	grant(H, shadekin_phase(), source_a)
	TEST_ASSERT(granted(H, shadekin_phase()), "granted by one source")
	grant(H, shadekin_phase(), source_b)
	revoke(H, shadekin_phase(), source_a)
	TEST_ASSERT(granted(H, shadekin_phase()), "still granted through source_b")
	revoke(H, shadekin_phase(), source_b)
	TEST_ASSERT(!granted(H, shadekin_phase()), "gone once every source has revoked")
	qdel(source_a)
	qdel(source_b)

// ---- Dark respite ----

/// A shadekin human in a /area/shadekin (Dark Respite's required area). Uses a turf next to (not test_floor() itself), so mutating its area
/// doesn't leak into every other test sharing the canonical test floor.
/datum/unit_test/proc/dq_respite_test_human()
	var/turf/dark_turf = get_step(test_floor(), SOUTH) || test_floor()
	var/area/current = get_area(dark_turf)
	if(!current || current.type != /area/shadekin)
		ChangeArea(dark_turf, new /area/shadekin())
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, dark_turf)
	var/datum/shadekin/SK = H.add_shadekin(/datum/shadekin/full)
	SK.dark_energy = SK.max_dark_energy
	return H

/// Only the full variant grants dark respite; phase_only does not.
/datum/unit_test/dq_ability_dark_respite_needs_full_variant

/datum/unit_test/dq_ability_dark_respite_needs_full_variant/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	H.add_shadekin(/datum/shadekin/phase_only)
	TEST_ASSERT(granted(H, shadekin_phase()), "phase_only still grants phase shift")
	TEST_ASSERT(!granted(H, shadekin_dark()), "phase_only does not grant dark respite")

/// Toggling starts and stops a Dark Respite modifier.
/datum/unit_test/dq_ability_dark_respite_toggles

/datum/unit_test/dq_ability_dark_respite_toggles/Run()
	var/mob/living/carbon/human/H = dq_respite_test_human()
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_DARK_RESPITE)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "starting it runs")
	TEST_ASSERT(H.has_body_effect(/datum/body_effect/dark_respite), "the modifier is applied")
	result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_DARK_RESPITE)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "triggering it again runs")
	TEST_ASSERT(!H.has_body_effect(/datum/body_effect/dark_respite), "the second use ends it")

/// The fix found while porting: a Dark Respite an emergency warp started can't be manually ended (the legacy verb warned about this but didn't
/// enforce it).
/datum/unit_test/dq_ability_dark_respite_warp_triggered_cannot_be_manually_ended

/datum/unit_test/dq_ability_dark_respite_warp_triggered_cannot_be_manually_ended/Run()
	var/mob/living/carbon/human/H = dq_respite_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	H.apply_body_effect(/datum/body_effect/dark_respite) // as an emergency warp would, not through the ability
	SK.manual_respite = FALSE
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_DARK_RESPITE)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "the op actually refuses, unlike the legacy verb")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/shadekin_ability/respite_forced, "blocked with the documented reason")
	TEST_ASSERT(H.has_body_effect(/datum/body_effect/dark_respite), "the emergency-warp respite is still running")

/// Dark Respite only works in the Dark.
/datum/unit_test/dq_ability_dark_respite_needs_dark_area

/datum/unit_test/dq_ability_dark_respite_needs_dark_area/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/turf/T = get_turf(H)
	// Explicitly not /area/shadekin: in the full suite, some other test earlier in the run may have left an /area/shadekin (or another area
	// entirely) on whatever turf test_floor() resolves to - this test is about the requirement, not about what state the shared test floor
	// happens to be in.
	if(istype(get_area(T), /area/shadekin))
		ChangeArea(T, new /area())
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_DARK_RESPITE)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "refused outside the Dark")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/shadekin_ability/not_dark, "blocked outside the Dark")

// ---- Regenerate other (a targeted ability: it asks which neighbour) ----

/datum/unit_test/dq_ability_regenerate_other_heals_a_neighbour

/datum/unit_test/dq_ability_regenerate_other_heals_a_neighbour/Run()
	test_driver_begin()
	exercise()
	test_driver_end()

/datum/unit_test/dq_ability_regenerate_other_heals_a_neighbour/proc/exercise()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	var/turf/T = get_turf(H)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human, get_step(T, NORTH))
	TEST_ASSERT(!(H in H.regenerate_candidates()), "you can't regenerate yourself")
	TEST_ASSERT(patient in H.regenerate_candidates(), "an adjacent mob is a candidate")
	var/before = SK.shadekin_get_energy()
	dq_use_ability_op(H, ABILITY_ID_SHADEKIN_REGENERATE_OTHER)
	var/datum/prompt/P = SSrequests.open_for(H)
	TEST_ASSERT_NOTNULL(P, "the ability asks which neighbour")
	test_answer(H, patient)
	test_drain()
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - 50, "the flat 50-energy cost was spent")
	TEST_ASSERT(patient.has_body_effect(/datum/body_effect/shadekin/heal_boop), "the patient is healing")

/datum/unit_test/dq_ability_regenerate_other_needs_energy

/datum/unit_test/dq_ability_regenerate_other_needs_energy/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	SK.dark_energy = 10
	var/turf/T = get_turf(H)
	allocate(/mob/living/carbon/human, get_step(T, NORTH))
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_REGENERATE_OTHER)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_REFUSED, "refused with too little energy")
	TEST_ASSERT_EQUAL(result?.reason, /datum/msg/shadekin_ability/low_energy, "blocked with too little energy")

// ---- Create shade ----

/datum/unit_test/dq_ability_create_shade_applies_the_modifier

/datum/unit_test/dq_ability_create_shade_applies_the_modifier/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	var/before = SK.shadekin_get_energy()
	var/datum/op_result/result = dq_use_ability_op(H, ABILITY_ID_SHADEKIN_CREATE_SHADE)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "it runs")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - 25, "the flat 25-energy cost was spent")
	TEST_ASSERT(H.has_body_effect(/datum/body_effect/shadekin/create_shade), "the shade modifier is applied")

// ---- Dark maw ----
// (dark_maw's darkness requirement reads the turf's live get_lumcount(), which depends on the lighting subsystem's own tick - not exercised
// here to avoid a flaky dependency on lighting timing.)

/datum/unit_test/dq_ability_dark_maw_deploys_and_dispels

/datum/unit_test/dq_ability_dark_maw_deploys_and_dispels/Run()
	// Runs the effect directly rather than through the op: the test map's default turf is lit, and both dark_maw's own darkness requirement and
	// the spawned trap object's own Initialize() light check would refuse/self-delete it there - a live-lighting dependency this test avoids
	// rather than fights. What's under test is the ability's own logic: it spends its cost and defers to the (unchanged) trap object, and
	// clearing an empty trap list is safe.
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	var/before = SK.shadekin_get_energy()
	TEST_ASSERT_EQUAL(H.ability_dark_maw(null), OP_OK, "it deploys")
	TEST_ASSERT_EQUAL(SK.shadekin_get_energy(), before - 20, "the flat 20-energy cost was spent")

	TEST_ASSERT_EQUAL(H.ability_clear_dark_maws(null), OP_OK, "dispelling is safe with no traps registered")

// ---- Dark tunneling ----

/datum/unit_test/dq_ability_dark_tunneling_needs_energy

/datum/unit_test/dq_ability_dark_tunneling_needs_energy/Run()
	// Checks the energy requirement directly rather than through the op: the test map's default turf isn't a valid shelter-deploy site, so the
	// (unrelated) site-readiness requirement would fail first there and this test would never reach the energy one it's meant to exercise.
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	TEST_ASSERT(H.ability_can_afford_dark_tunnel(null), "full energy affords the tunnel")
	SK.dark_energy = 10
	TEST_ASSERT(!H.ability_can_afford_dark_tunnel(null), "blocked with too little energy")

/datum/unit_test/dq_ability_dark_tunneling_once_only

/datum/unit_test/dq_ability_dark_tunneling_once_only/Run()
	var/mob/living/carbon/human/H = dq_phase_test_human()
	var/datum/shadekin/SK = H.get_shadekin_state()
	TEST_ASSERT(H.ability_no_dark_tunnel_yet(null), "no tunnel yet")
	SK.created_dark_tunnel = TRUE
	TEST_ASSERT(!H.ability_no_dark_tunnel_yet(null), "blocked after one use")

// ---- Borg abilities ----

/datum/unit_test/dq_ability_robot_toggle_lights

/datum/unit_test/dq_ability_robot_toggle_lights/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	TEST_ASSERT(granted(R, robot_utility()), "every robot is granted this on spawn")
	var/before = R.lights_on
	var/datum/op_result/result = dq_use_ability_op(R, ABILITY_ID_ROBOT_TOGGLE_LIGHTS)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "toggling runs")
	TEST_ASSERT_NOTEQUAL(R.lights_on, before, "the light state flipped")
	qdel(R)

// ---- Targeted, picked abilities ----
// The question itself needs a live client and isn't exercised here; what's tested is the data the candidates are built from and, for
// robot_mount, the branch that never reaches a question at all (dismounting).

/datum/unit_test/dq_ability_robot_nom_candidates

/datum/unit_test/dq_ability_robot_nom_candidates/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/living/carbon/human/nearby = allocate(/mob/living/carbon/human, get_step(T, NORTH))
	TEST_ASSERT(granted(R, robot_utility()), "every robot is granted this on spawn")
	var/list/candidates = R.nom_candidates()
	TEST_ASSERT(nearby in candidates, "a nearby mob is a candidate")
	TEST_ASSERT(!(R in candidates), "the robot itself never is")

/datum/unit_test/dq_ability_robot_mount_candidates

/datum/unit_test/dq_ability_robot_mount_candidates/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/living/carbon/human/adjacent = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/far = allocate(/mob/living/carbon/human, get_step(get_step(T, NORTH), NORTH))
	var/list/candidates = R.mount_candidates()
	TEST_ASSERT(adjacent in candidates, "an adjacent, unbuckled mob is a candidate")
	TEST_ASSERT(!(far in candidates), "a distant mob is not")
	TEST_ASSERT(!(R in candidates), "the robot itself never is")

/datum/unit_test/dq_ability_robot_mount_dismounts_without_picking

/datum/unit_test/dq_ability_robot_mount_dismounts_without_picking/Run()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, T)
	var/mob/living/carbon/human/rider = allocate(/mob/living/carbon/human, T)
	R.can_buckle = TRUE // whether a chassis carries riders depends on the sprite it was given at random
	TEST_ASSERT(R.buckle_link(rider), "the rider should buckle to the robot")
	// With a rider already buckled the op asks nothing and dismounts directly, so this is safe to run from a headless test.
	var/datum/op_result/result = dq_use_ability_op(R, ABILITY_ID_ROBOT_MOUNT)
	TEST_ASSERT_EQUAL(result?.outcome, ACT_COMMITTED, "dismounting runs without a question")
	TEST_ASSERT(!LAZYLEN(R.buckled_mob_list()), "the rider is dismounted")

/datum/unit_test/dq_ability_robot_toggle_module

/datum/unit_test/dq_ability_robot_toggle_module/Run()
	var/mob/living/silicon/robot/R = allocate(/mob/living/silicon/robot, test_floor())
	TEST_ASSERT(granted(R, robot_live()), "granted while alive")
	R.remove_robot_verbs()
	TEST_ASSERT(!granted(R, robot_live()), "revoked with the rest of robot_verbs_default on death")

/// Test-only area that blocks phase shift.
/area/dq_test_phase_block
	name = "phase-block test area"
	flags = AREA_BLOCK_PHASE_SHIFT
