// Unit tests for the DQ combat AI framework.
//
// Coverage:
//   - static audits of behaviors (flyweight, well-formed, player verbs)
//   - faction registry
//   - runtime brain spawn on simple_mob Initialize
//   - target / threat promotion (give_target, damage notify, forget)
//   - faction vs. personal disposition resolution
//   - item-granted behavior declaration
//
// This file is #included from code/modules/unit_tests/_unit_tests.dm so the
// TEST_ASSERT* macros are in scope. The combat_ai defines header is re-included
// here (DM dedupes identical includes) because the test block compiles before
// the combat_ai framework includes later in the DME.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#include "../combat_ai/_defines.dm"

// --- static: behaviors are flyweights ----------------------------------
// dq_get_behavior(T) must return the same singleton across calls — the
// flyweight contract is what makes per-mob state on brain.behavior_state /
// source items work. A bug that returned a fresh instance per call would
// break cooldowns silently.

/datum/unit_test/dq_combat_ai_behaviors_are_flyweight

/datum/unit_test/dq_combat_ai_behaviors_are_flyweight/Run()
	for(var/T in subtypesof(/datum/ai_behavior))
		var/datum/ai_behavior/A = dq_get_behavior(T)
		var/datum/ai_behavior/B = dq_get_behavior(T)
		TEST_ASSERT(A == B, "dq_get_behavior([T]) returned two different instances")
		TEST_ASSERT(istype(A, T), "dq_get_behavior([T]) returned wrong type [A.type]")


// --- static: every behavior has a non-default name and a valid priority --
// Behaviors with name = "abstract behavior" leak into the player verb
// dropdown as garbage. priority_class outside the defined enum will sort
// strangely against innate vs override picks.

/datum/unit_test/dq_combat_ai_behaviors_well_formed

/datum/unit_test/dq_combat_ai_behaviors_well_formed/Run()
	var/list/failures = list()
	for(var/T in subtypesof(/datum/ai_behavior))
		var/datum/ai_behavior/B = dq_get_behavior(T)
		if(B.name == "abstract behavior")
			failures += "[T] has default name"
		if(B.priority_class < DQ_BEHAVIOR_PRIORITY_BACKGROUND || B.priority_class > DQ_BEHAVIOR_PRIORITY_INTERRUPT)
			failures += "[T] has invalid priority_class [B.priority_class]"
		if(B.target_kind != DQ_TARGET_NONE && B.target_kind != DQ_TARGET_MOB && B.target_kind != DQ_TARGET_TURF && B.target_kind != DQ_TARGET_ITEM && B.target_kind != DQ_TARGET_SELF)
			failures += "[T] has invalid target_kind [B.target_kind]"
	if(length(failures))
		TEST_FAIL("behaviors malformed: [jointext(failures, "; ")]")


// --- static: item-granted behaviors must not declare brain-managed cooldowns ---
// brain.set_cooldown short-circuits when source != null (the source item owns
// its own cooldown). A behavior with requires_held_source = TRUE and
// cooldown != 0 would silently never cool down — its cooldown field is a lie.
// Behaviors that need a real cooldown must gate via the source item's state
// (e.g. gun.next_fire_time, grenade.active).

/datum/unit_test/dq_combat_ai_item_granted_behaviors_have_no_brain_cooldown

/datum/unit_test/dq_combat_ai_item_granted_behaviors_have_no_brain_cooldown/Run()
	var/list/failures = list()
	for(var/T in subtypesof(/datum/ai_behavior))
		var/datum/ai_behavior/B = dq_get_behavior(T)
		if(B.requires_held_source && B.cooldown != 0)
			failures += "[T] sets cooldown = [B.cooldown] but requires_held_source = TRUE; brain.set_cooldown will silently no-op"
	if(length(failures))
		TEST_FAIL("item-granted behaviors with brain cooldowns: [jointext(failures, "; ")]")


// --- static: every player-castable behavior returns a complete info list -
// The Use-Combat-Move dispatcher reads info["name"] / "auto_target" /
// "category". A missing key would show a blank entry or break target
// resolution. We don't enforce "desc" because verb tooltips degrade
// gracefully.

/datum/unit_test/dq_combat_ai_player_verbs_well_formed

/datum/unit_test/dq_combat_ai_player_verbs_well_formed/Run()
	var/list/failures = list()
	for(var/T in subtypesof(/datum/ai_behavior))
		var/datum/ai_behavior/B = dq_get_behavior(T)
		var/list/info = B.get_player_verb_info()
		if(!info)
			continue
		if(!info["name"])
			failures += "[T].get_player_verb_info missing 'name'"
		if(!("auto_target" in info))
			failures += "[T].get_player_verb_info missing 'auto_target'"
	if(length(failures))
		TEST_FAIL("player verbs malformed: [jointext(failures, "; ")]")


// --- static: faction registry builds with every faction_key -----------
// dq_build_faction_registry runs at world init. If a /datum/faction_data
// subtype has a faction_key but isn't registered, lookups fall through to
// the default datum and the relationships are silently ignored.

/datum/unit_test/dq_combat_ai_faction_registry_populates

/datum/unit_test/dq_combat_ai_faction_registry_populates/Run()
	dq_build_faction_registry()
	var/list/expected_keys = list()
	for(var/T in typesof(/datum/faction_data))
		var/datum/faction_data/template = T
		var/key = initial(template.faction_key)
		if(key)
			expected_keys += key
	for(var/key in expected_keys)
		TEST_ASSERT(GLOB.dq_faction_data[key], "faction [key] not registered in dq_faction_data")
		var/datum/faction_data/got = GLOB.dq_faction_data[key]
		TEST_ASSERT(istype(got), "faction [key] entry [got] is not a /datum/faction_data")


// --- runtime: brain spawns on simple_mob Initialize -------------------
// The /mob/living re-open at the bottom of mob_living.dm calls
// initialize_ai_brain after the parent chain. simple_mob.use_modern_ai is
// TRUE by default, so any vanilla simple_mob should come up with a brain.

/datum/unit_test/dq_combat_ai_brain_spawns_on_simple_mob

/datum/unit_test/dq_combat_ai_brain_spawns_on_simple_mob/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	TEST_ASSERT_NOTNULL(S.ai_brain, "quarry_stalker spawned without an ai_brain")
	TEST_ASSERT(S.ai_brain.holder == S, "brain.holder doesn't point back to the mob")
	TEST_ASSERT_NOTNULL(S.ai_brain.model, "brain.model wasn't created")
	TEST_ASSERT(length(S.ai_brain.target_selector_chain), "brain has no target_selector_chain")


// --- runtime: give_target sets primary_threat and a personal HOSTILE ---
// Public API for telling a brain "fight this thing." Used by capture
// crystal, taming pacifiers, vore mob anger triggers, etc.

/datum/unit_test/dq_combat_ai_give_target_sets_threat

/datum/unit_test/dq_combat_ai_give_target_sets_threat/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	S.ai_brain.give_target(H)
	TEST_ASSERT_EQUAL(S.ai_brain.primary_threat, H, "give_target didn't set primary_threat")
	// Personal entry should exist and mark them HOSTILE.
	TEST_ASSERT(S.ai_brain.check_attacker(H), "give_target didn't add a personal HOSTILE entry")


// --- runtime: forget_everything wipes targets and personal ------------
// Used by technomancer control / release, by tame potions, by despawn
// cleanups.

/datum/unit_test/dq_combat_ai_forget_clears_state

/datum/unit_test/dq_combat_ai_forget_clears_state/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	S.ai_brain.give_target(H)
	S.ai_brain.forget_everything()
	TEST_ASSERT_NULL(S.ai_brain.primary_threat, "forget_everything left a primary_threat")
	TEST_ASSERT(!S.ai_brain.check_attacker(H), "forget_everything left a personal entry")


// --- runtime: damage routes through brain and promotes attacker -------
// attack_generic is the simple_mob<->simple_mob fight path; damage_hooks.dm
// re-opens it to call dq_notify_damage. The brain should add a personal
// HOSTILE entry for the attacker even if it isn't already a threat.

/datum/unit_test/dq_combat_ai_damage_promotes_attacker

/datum/unit_test/dq_combat_ai_damage_promotes_attacker/Run()
	var/mob/living/simple_mob/quarry_stalker/victim = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/simple_mob/quarry_stalker/aggressor = allocate(/mob/living/simple_mob/quarry_stalker)
	// Direct notify (the hook does the same after attack_generic).
	victim.ai_brain.notify_damage(10, BRUTE, aggressor)
	TEST_ASSERT(victim.ai_brain.check_attacker(aggressor), "notify_damage didn't promote attacker to HOSTILE")


// --- runtime: personal disposition wins over faction default ----------
// Faction-mate would normally be ALLY. add_personal(HOSTILE) overrides
// that, which is what makes "your buddy got drugged into attacking you"
// work.

/datum/unit_test/dq_combat_ai_personal_overrides_faction

/datum/unit_test/dq_combat_ai_personal_overrides_faction/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/simple_mob/quarry_stalker/mate = allocate(/mob/living/simple_mob/quarry_stalker)
	// Same faction → ALLY by default.
	TEST_ASSERT_EQUAL(S.ai_brain.disposition_to(mate), DQ_DISPOSITION_ALLY, "same-faction default should be ALLY")
	S.ai_brain.add_personal(mate, DQ_DISPOSITION_HOSTILE, 60 SECONDS, "test")
	TEST_ASSERT_EQUAL(S.ai_brain.disposition_to(mate), DQ_DISPOSITION_HOSTILE, "personal HOSTILE should override faction ALLY")


// --- runtime: grenade declares throw_grenade as a granted behavior -----
// The grant declarations are the contract the brain.rebuild_behaviors loop
// reads. A broken declaration would silently strip the item-granted moves.

/datum/unit_test/dq_combat_ai_grenade_grants_throw_behavior

/datum/unit_test/dq_combat_ai_grenade_grants_throw_behavior/Run()
	var/obj/item/grenade/G = allocate(/obj/item/grenade)
	var/list/granted = G.get_dq_granted_behaviors()
	TEST_ASSERT_NOTNULL(granted, "grenade returned null from get_dq_granted_behaviors")
	TEST_ASSERT(/datum/ai_behavior/throw_grenade in granted, "grenade doesn't grant /datum/ai_behavior/throw_grenade")


// --- runtime: gun declares aimed_shot as a granted behavior -----------

/datum/unit_test/dq_combat_ai_gun_grants_aimed_shot_behavior

/datum/unit_test/dq_combat_ai_gun_grants_aimed_shot_behavior/Run()
	var/obj/item/gun/G = allocate(/obj/item/gun)
	var/list/granted = G.get_dq_granted_behaviors()
	TEST_ASSERT_NOTNULL(granted, "gun returned null from get_dq_granted_behaviors")
	TEST_ASSERT(/datum/ai_behavior/aimed_shot in granted, "gun doesn't grant /datum/ai_behavior/aimed_shot")


// --- runtime: brain.rebuild_behaviors actually merges held-item grants -
// The grant declaration is meaningless unless the brain's per-tick rebuild
// rolls the held items into effective_behaviors. This test exercises the
// full path with a human (has hands) opted into the modern brain.

/datum/unit_test/dq_combat_ai_rebuild_merges_held_grants

/datum/unit_test/dq_combat_ai_rebuild_merges_held_grants/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	H.use_modern_ai = TRUE
	H.initialize_ai_brain()
	TEST_ASSERT_NOTNULL(H.ai_brain, "brain wasn't created after opt-in re-init")
	var/obj/item/grenade/G = allocate(/obj/item/grenade)
	H.put_in_hands(G)
	H.ai_brain.rebuild_behaviors()
	TEST_ASSERT(/datum/ai_behavior/throw_grenade in H.ai_brain.effective_behaviors, "rebuild_behaviors didn't merge held grenade's granted behavior into effective_behaviors")
	TEST_ASSERT_EQUAL(H.ai_brain.effective_behaviors[/datum/ai_behavior/throw_grenade], G, "throw_grenade's source isn't the grenade itself")


// --- runtime: give_destination + tick walks the mob ------------------
// give_destination plus a few ticks of walk_to_destination should at
// least change the mob's position OR set the destination on the brain.

/datum/unit_test/dq_combat_ai_give_destination_records_target

/datum/unit_test/dq_combat_ai_give_destination_records_target/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	// The DQ test map doesn't ship the unit-test landmarks (see the comment
	// in dq_quarry_persistence_tests.dm). Grab any simulated floor on z=1
	// as a workable destination — give_destination just stores it.
	var/turf/dest = null
	for(var/turf/simulated/T in block(locate(1, 1, 1), locate(world.maxx, world.maxy, 1)))
		dest = T
		break
	TEST_ASSERT_NOTNULL(dest, "no simulated floor available on z=1 for destination")
	S.ai_brain.give_destination(dest)
	TEST_ASSERT_EQUAL(S.ai_brain.destination, dest, "give_destination didn't record the turf on the brain")


// --- runtime: stop_active clears busy and marks selection dirty -------
// Regression guard. The defensive busy=FALSE / selection_dirty=TRUE in
// stop_active is what unsticks the brain if a behavior's start() runtimes
// before clearing its own busy flag. Removing those lines would re-introduce
// the freeze that the audit pass caught.

/datum/unit_test/dq_combat_ai_stop_active_clears_busy

/datum/unit_test/dq_combat_ai_stop_active_clears_busy/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	// Simulate a blocks_reselection behavior in flight.
	S.ai_brain.busy = TRUE
	S.ai_brain.selection_dirty = FALSE
	S.ai_brain.active_behavior_type = /datum/ai_behavior/charge_slam
	S.ai_brain.stop_active(DQ_BEHAVIOR_STOP_INTERRUPTED)
	TEST_ASSERT_EQUAL(S.ai_brain.busy, FALSE, "stop_active didn't clear busy")
	TEST_ASSERT_EQUAL(S.ai_brain.selection_dirty, TRUE, "stop_active didn't set selection_dirty")
	TEST_ASSERT_NULL(S.ai_brain.active_behavior_type, "stop_active didn't clear active_behavior_type")


// --- runtime: on_holder_login adds the player dispatcher verb --------
// The Use-Combat-Move verb is added lazily when a client takes over the mob
// (via COMSIG_MOB_LOGIN). Test the handler directly — calling it adds the
// verb. If the wiring breaks, possessed mobs silently lose their moves.

/datum/unit_test/dq_combat_ai_login_adds_player_verb

/datum/unit_test/dq_combat_ai_login_adds_player_verb/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	// AI-only mob: verb must NOT be present yet (would bloat verbs list of
	// every wild critter).
	TEST_ASSERT(!(/mob/living/proc/dq_use_combat_move in S.verbs), "verb was added before client login")
	// Simulate the login signal handler firing.
	S.ai_brain.on_holder_login(S)
	TEST_ASSERT(/mob/living/proc/dq_use_combat_move in S.verbs, "on_holder_login didn't add the dispatcher verb")


// --- runtime: set_hostile flips ai_attack_on_sight -------------------
// Legacy callers (technomancer control, xenoarch effects, vore mobs)
// write set_hostile(FALSE) to suppress aggression.

/datum/unit_test/dq_combat_ai_set_hostile_flips_attack_on_sight

/datum/unit_test/dq_combat_ai_set_hostile_flips_attack_on_sight/Run()
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker)
	S.ai_attack_on_sight = TRUE
	S.ai_brain.set_hostile(FALSE)
	TEST_ASSERT_EQUAL(S.ai_attack_on_sight, FALSE, "set_hostile(FALSE) didn't flip ai_attack_on_sight")
	S.ai_brain.set_hostile(TRUE)
	TEST_ASSERT_EQUAL(S.ai_attack_on_sight, TRUE, "set_hostile(TRUE) didn't flip ai_attack_on_sight")

#endif
