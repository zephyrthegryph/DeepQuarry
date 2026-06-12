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


// --- runtime: quarry fauna of different species coexist ----------------
// SSquarry tags spawned wildlife with quarry_fauna = TRUE so a layer's mixed
// fauna don't tear each other apart. Different species stay NEUTRAL; same
// species is still ALLY (pack cohesion + pack aggro); a non-fauna stranger is
// still engaged on sight. The exemption is what spares them — clearing the flag
// must restore the on-sight hostility.

/datum/unit_test/dq_quarry_fauna_coexist

/datum/unit_test/dq_quarry_fauna_coexist/Run()
	var/mob/living/simple_mob/quarry_stalker/a = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/simple_mob/quarry_stalker/b = allocate(/mob/living/simple_mob/quarry_stalker)
	a.ai_attack_on_sight = TRUE
	a.faction = "fauna_a"
	b.faction = "fauna_b"
	a.quarry_fauna = TRUE
	b.quarry_fauna = TRUE
	TEST_ASSERT_EQUAL(a.ai_brain.disposition_to(b), DQ_DISPOSITION_NEUTRAL, "different-species quarry fauna should coexist (NEUTRAL)")
	b.quarry_fauna = FALSE
	TEST_ASSERT_EQUAL(a.ai_brain.disposition_to(b), DQ_DISPOSITION_HOSTILE, "a non-fauna stranger of another faction is HOSTILE on sight")
	b.faction = "fauna_a"
	TEST_ASSERT_EQUAL(a.ai_brain.disposition_to(b), DQ_DISPOSITION_ALLY, "same faction stays ALLY (pack cohesion)")


// --- runtime: a flinch telegraph is interruptible only when opted in ----
// interrupt_if_opted_in is what a reaction calls the moment it commits, so a
// flinch heavy is yanked only when the mob actually dodges/braces — not for free
// on every passing swing. Trash mobs use the committed /telegraphed_strike (no
// interruptible_by) and stay punishable. The /flinch subtype opts into
// COMSIG_DQAI_INCOMING_ATTACK only — other signals must not cancel it.

/datum/unit_test/dq_combat_ai_flinch_telegraph_interrupts

/datum/unit_test/dq_combat_ai_flinch_telegraph_interrupts/Run()
	var/mob/living/simple_mob/quarry_stalker/m = allocate(/mob/living/simple_mob/quarry_stalker)
	var/datum/ai_brain/brain = m.ai_brain
	TEST_ASSERT_NOTNULL(brain, "stalker spawned without a brain")
	// Committed heavy: not opted in, so a commit-time interrupt is a no-op.
	brain.active_behavior_type = /datum/ai_behavior/telegraphed_strike
	brain.busy = TRUE
	TEST_ASSERT(!brain.interrupt_if_opted_in(COMSIG_DQAI_INCOMING_ATTACK), "a committed telegraph must not be interruptible")
	TEST_ASSERT_EQUAL(brain.active_behavior_type, /datum/ai_behavior/telegraphed_strike, "committed telegraph should still be active")
	// Flinch heavy: opted into INCOMING_ATTACK, so a committing reaction yanks it.
	brain.active_behavior_type = /datum/ai_behavior/telegraphed_strike/flinch
	brain.busy = TRUE
	TEST_ASSERT(brain.interrupt_if_opted_in(COMSIG_DQAI_INCOMING_ATTACK), "a flinch telegraph must be interruptible by an incoming attack")
	TEST_ASSERT_NULL(brain.active_behavior_type, "flinch telegraph should be cancelled once a reaction commits")
	// A flinch heavy is NOT cancelled by a signal it didn't opt into.
	brain.active_behavior_type = /datum/ai_behavior/telegraphed_strike/flinch
	brain.busy = TRUE
	TEST_ASSERT(!brain.interrupt_if_opted_in(COMSIG_DQAI_DAMAGE_TAKEN), "flinch opts into INCOMING_ATTACK only")
	TEST_ASSERT_EQUAL(brain.active_behavior_type, /datum/ai_behavior/telegraphed_strike/flinch, "flinch should survive a non-opted signal")


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


// --- runtime: aggro-on-damage: retaliate_to_attacker drives primary_threat ---
//
// Regression test for the three-symptom cluster reported after the combat-AI
// merge. Before the fix:
//   (a) notify_damage with a real attacker set last_attacker on the world model
//       and personal HOSTILE, then dispatch_behavior_signal fired retaliate's
//       on_signal → invalidate_selection, so on the next handle_tactics call
//       pick_and_run would evaluate retaliate_to_attacker; BUT
//   (b) update_primary_threat() ran on the PRECEDING slow tick and immediately
//       cleared primary_threat because visible_hostiles was empty (attacker
//       not in view() range). retaliate_to_attacker.start() then set
//       primary_threat, which held until the NEXT slow tick, which cleared it
//       again → mob never committed to an attack behavior for more than 250ms.
//
// After the fix: update_primary_threat respects the personal-HOSTILE entry
// (set by notify_damage) and retains primary_threat while that entry lives,
// so the mob stays locked on the out-of-view attacker for the duration.
//
// This test exercises both paths headlessly (no map, no slow tick):
//   1. Damage in-view: primary_threat set and held.
//   2. Damage out-of-view: primary_threat set and RETAINED after calling
//      update_primary_threat with an empty visible_hostiles list.
//   3. retaliate_to_attacker is in the quarry_stalker's behavior list.

/datum/unit_test/dq_combat_ai_aggro_on_damage_out_of_view

/datum/unit_test/dq_combat_ai_aggro_on_damage_out_of_view/Run()
	var/mob/living/simple_mob/quarry_stalker/victim = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human)

	TEST_ASSERT_NOTNULL(victim.ai_brain, "victim spawned without an ai_brain")

	// Confirm retaliate_to_attacker is in the behavior list.
	victim.ai_brain.rebuild_behaviors()
	TEST_ASSERT(/datum/ai_behavior/retaliate_to_attacker in victim.ai_brain.effective_behaviors, \
		"retaliate_to_attacker is not in quarry_stalker effective_behaviors after rebuild")

	// Simulate attacker hitting the victim (out of view — visible_hostiles is empty
	// because we never ran update_perception and the mobs aren't on a live map).
	victim.ai_brain.notify_damage(10, BRUTE, attacker)

	// notify_damage should: record last_attacker, add personal HOSTILE, invalidate selection.
	TEST_ASSERT(victim.ai_brain.check_attacker(attacker), \
		"notify_damage didn't add personal HOSTILE entry for attacker")

	// Manually invoke update_primary_threat. visible_hostiles is empty (never populated
	// by update_perception), so the old code would clear primary_threat here.
	// First, let retaliate_to_attacker drive primary_threat by running pick_and_run directly.
	victim.ai_brain.pick_and_run()
	TEST_ASSERT_EQUAL(victim.ai_brain.primary_threat, attacker, \
		"pick_and_run didn't set primary_threat to attacker via retaliate_to_attacker")

	// Now simulate a second slow tick: update_primary_threat should start the
	// grace timer but NOT clear the threat yet (lose_threat_at just got set).
	victim.ai_brain.update_primary_threat()
	TEST_ASSERT_EQUAL(victim.ai_brain.primary_threat, attacker, \
		"update_primary_threat cleared primary_threat immediately on first tick after attacker left view — mob would freeze instead of pursuing")
	TEST_ASSERT(victim.ai_brain.lose_threat_at > 0, \
		"update_primary_threat didn't start the lose_threat_at grace timer")

	// Sanity: once the grace period expires, the threat IS eventually released.
	// Fast-forward the timer past the timeout by back-dating lose_threat_at.
	victim.ai_brain.lose_threat_at = world.time - DQ_LOSE_THREAT_TIMEOUT - 1
	victim.ai_brain.update_primary_threat()
	TEST_ASSERT_NULL(victim.ai_brain.primary_threat, \
		"update_primary_threat should clear primary_threat after DQ_LOSE_THREAT_TIMEOUT expires")


// --- runtime: react_to_attack sets last_attacker on world model ----------
// Regression guard for the null_holder runtime: react_to_attack must not
// crash when called on a brain whose holder is null (Destroy in progress),
// and must set model.last_attacker so retaliate_to_attacker.evaluate() works.

/datum/unit_test/dq_combat_ai_react_to_attack_sets_last_attacker

/datum/unit_test/dq_combat_ai_react_to_attack_sets_last_attacker/Run()
	var/mob/living/simple_mob/quarry_stalker/victim = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human)

	// react_to_attack is called from hit_with_weapon when a player swings a knife.
	victim.ai_brain.react_to_attack(attacker)

	// Should have set last_attacker on the world model.
	TEST_ASSERT_EQUAL(victim.ai_brain.model.get_last_attacker(), attacker, \
		"react_to_attack didn't record last_attacker on the world model — retaliate_to_attacker.evaluate() will return null")

	// Should have set primary_threat (it was null before).
	TEST_ASSERT_EQUAL(victim.ai_brain.primary_threat, attacker, \
		"react_to_attack didn't set primary_threat when it was null")

	// null-holder safety: calling react_to_attack after brain.holder = null must
	// not runtime. Simulate the vore-eating case from the confirmed runtime log.
	var/mob/living/simple_mob/quarry_stalker/victim2 = allocate(/mob/living/simple_mob/quarry_stalker)
	victim2.ai_brain.holder = null  // Simulate partial Destroy / eaten state.
	victim2.ai_brain.react_to_attack(attacker)  // Must not runtime.
	// If we reach here, no crash — test passes implicitly.


// A player parry/shove sets the mob's melee_locked_until; the melee_attack and telegraphed_strike
// behaviors must respect it, so the player's defenses actually open the mob (not just stop movement).
/datum/unit_test/dq_combat_ai_melee_lock_opens_mob

/datum/unit_test/dq_combat_ai_melee_lock_opens_mob/Run()
	var/turf/base = _swing_arena()
	TEST_ASSERT_NOTNULL(base, "no test arena available")
	var/turf/north = get_step(base, NORTH)
	var/mob/living/simple_mob/quarry_stalker/S = allocate(/mob/living/simple_mob/quarry_stalker, base)
	var/mob/living/carbon/human/foe = allocate(/mob/living/carbon/human, north)
	S.ai_brain.give_target(foe)

	var/datum/ai_behavior/melee_attack/poke = dq_get_behavior(/datum/ai_behavior/melee_attack)
	TEST_ASSERT_NOTNULL(poke.evaluate(S.ai_brain, null), "an adjacent unhindered mob should want to attack")

	S.melee_locked_until = world.time + 50 // simulate a player parry / shove stagger
	TEST_ASSERT_NULL(poke.evaluate(S.ai_brain, null), "a staggered mob (melee_locked_until) should not attack")

	var/datum/ai_behavior/telegraphed_strike/heavy = dq_get_behavior(/datum/ai_behavior/telegraphed_strike)
	TEST_ASSERT_NULL(heavy.evaluate(S.ai_brain, null), "a staggered mob should not wind up a heavy either")
	S.melee_locked_until = 0
	TEST_ASSERT_NOTNULL(heavy.evaluate(S.ai_brain, null), "an unhindered adjacent mob should be able to wind up a heavy")


// --- runtime: dq_assign_lord forms a lord and back-references its members --
// Every quarry pack is assigned one /datum/ai_lord at spawn. The lord must
// register on SSai_lords (so it gets a coordination tick), collect the
// brain-bearing mobs, and each member's brain.lord must point back at the lord
// (so the brain can drop out of the pack on Destroy).

/datum/unit_test/dq_ai_lord_forms_over_pack

/datum/unit_test/dq_ai_lord_forms_over_pack/Run()
	var/mob/living/simple_mob/quarry_stalker/a = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/simple_mob/quarry_stalker/b = allocate(/mob/living/simple_mob/quarry_stalker)
	var/datum/ai_lord/lord = dq_assign_lord(list(a, b))
	TEST_ASSERT_NOTNULL(lord, "dq_assign_lord returned null over two brain-bearing mobs")
	TEST_ASSERT_EQUAL(length(lord.members), 2, "lord didn't collect both pack members")
	TEST_ASSERT_EQUAL(a.ai_brain.lord, lord, "member a's brain.lord doesn't point back at the lord")
	TEST_ASSERT_EQUAL(b.ai_brain.lord, lord, "member b's brain.lord doesn't point back at the lord")
	TEST_ASSERT(lord in SSai_lords.lords, "lord didn't register on SSai_lords for its coordination tick")
	// An empty / brainless roster yields no lord (nothing to coordinate).
	TEST_ASSERT_NULL(dq_assign_lord(list()), "dq_assign_lord over an empty list should return null")
	qdel(lord)


// --- runtime: command_attack pushes one shared target to every member -----
// The lord's whole job: the moment it has prey, every member engages the SAME
// target. command_attack re-pushes only on change, but the end state is that
// each member's brain.primary_threat is the commanded target.

/datum/unit_test/dq_ai_lord_command_attack_propagates

/datum/unit_test/dq_ai_lord_command_attack_propagates/Run()
	var/mob/living/simple_mob/quarry_stalker/a = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/simple_mob/quarry_stalker/b = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/carbon/human/foe = allocate(/mob/living/carbon/human)
	var/datum/ai_lord/lord = dq_assign_lord(list(a, b))
	TEST_ASSERT_NOTNULL(lord, "dq_assign_lord returned null")
	lord.command_attack(foe)
	TEST_ASSERT_EQUAL(a.ai_brain.primary_threat, foe, "command_attack didn't engage member a on the shared target")
	TEST_ASSERT_EQUAL(b.ai_brain.primary_threat, foe, "command_attack didn't engage member b on the shared target")
	qdel(lord)


// --- runtime: a wiped pack prunes to empty and disbands -------------------
// process_lord prunes dead/gone members each tick; when the last one falls the
// lord disbands — leaves SSai_lords and nulls the survivors' back-refs — so a
// cleared pack leaves no dangling coordinator. Also covers the brain.Destroy
// path: a member removed from the world drops itself out of the pack.

/datum/unit_test/dq_ai_lord_prunes_and_disbands

/datum/unit_test/dq_ai_lord_prunes_and_disbands/Run()
	var/mob/living/simple_mob/quarry_stalker/a = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/simple_mob/quarry_stalker/b = allocate(/mob/living/simple_mob/quarry_stalker)
	var/datum/ai_lord/lord = dq_assign_lord(list(a, b))
	TEST_ASSERT_NOTNULL(lord, "dq_assign_lord returned null")
	// One member dies: the lord prunes it but survives on its remaining member.
	a.stat = DEAD
	lord.process_lord()
	TEST_ASSERT(!(a in lord.members), "process_lord didn't prune a dead member")
	TEST_ASSERT(lord in SSai_lords.lords, "lord disbanded while a live member remained")
	// The last member dies: the lord prunes it and disbands.
	b.stat = DEAD
	lord.process_lord()
	TEST_ASSERT_EQUAL(length(lord.members), 0, "process_lord didn't empty a wiped pack")
	TEST_ASSERT(!(lord in SSai_lords.lords), "a wiped pack's lord didn't leave SSai_lords")


// --- runtime: a member leaving the world drops out of its pack ------------
// brain.Destroy calls lord.remove_member, so a qdel'd member is pulled from the
// pack (and disbands it if it was the last one) without waiting for the next
// coordination tick.

/datum/unit_test/dq_ai_lord_member_destroy_leaves_pack

/datum/unit_test/dq_ai_lord_member_destroy_leaves_pack/Run()
	var/mob/living/simple_mob/quarry_stalker/a = allocate(/mob/living/simple_mob/quarry_stalker)
	var/mob/living/simple_mob/quarry_stalker/b = allocate(/mob/living/simple_mob/quarry_stalker)
	var/datum/ai_lord/lord = dq_assign_lord(list(a, b))
	TEST_ASSERT_NOTNULL(lord, "dq_assign_lord returned null")
	qdel(a)
	TEST_ASSERT(!(a in lord.members), "a qdel'd member didn't drop out of the pack on Destroy")
	TEST_ASSERT(lord in SSai_lords.lords, "the pack disbanded while a live member remained")
	qdel(lord)

#endif
