// One smoke test per ported creature (code/modules/combat_ai/ports/): it spawns with a brain, engages a target when the brain is driven by hand, and uses
// a tactic of its own (a port's special, not the generic melee/ranged/approach kit) at least once. Cooldowns and the click cooldown are reset each round, a
// target stands next to it and two tiles off in turn, and the brain is stopped as soon as it has done what the test asks.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The generic tactics (code/modules/combat_ai/behaviors/): everything else a creature lists is its own.
/proc/dq_ai_generic_tactic(btype)
	var/static/list/generic = list(
		/datum/ai_behavior/melee_attack, /datum/ai_behavior/ranged_attack, /datum/ai_behavior/approach_threat, /datum/ai_behavior/maul_unconscious,
		/datum/ai_behavior/idle_wander, /datum/ai_behavior/idle_speak, /datum/ai_behavior/threaten, /datum/ai_behavior/call_for_help,
		/datum/ai_behavior/retaliate_to_attacker, /datum/ai_behavior/flee_low_hp, /datum/ai_behavior/pack_retreat, /datum/ai_behavior/evasive_juke,
		/datum/ai_behavior/kite_away, /datum/ai_behavior/hit_and_run, /datum/ai_behavior/return_home, /datum/ai_behavior/follow_leader,
		/datum/ai_behavior/walk_to_destination, /datum/ai_behavior/charge_slam, /datum/ai_behavior/scavenge_weapon, /datum/ai_behavior/throw_grenade,
		/datum/ai_behavior/aimed_shot)
	return btype in generic

/// A human whose health reads as half: a patient for the creatures that heal allies.
/mob/living/carbon/human/dq_ai_test_wounded

/mob/living/carbon/human/dq_ai_test_wounded/vitality()
	return 0.5

/// Scenarios that give a creature's own tactic something to act on (a patient, a cable to be anchored to).
#define SMOKE_HEAL "heal"
#define SMOKE_ANCHORED "anchored"
#define SMOKE_MACHINE "machine"
#define SMOKE_INERT "inert"

/// Drives `S`'s brain by hand for up to `rounds` rounds, with `H` as its target when `engage`. Returns the tactics it started (type => times).
/datum/unit_test/proc/drive_port_creature(mob/living/simple_mob/S, mob/living/H, rounds = 30, engage = TRUE)
	var/datum/ai_brain/B = S.ai_brain
	if(engage)
		B.give_target(H, TRUE)
	for(var/round in 1 to rounds)
		S.next_click = 0
		B.behavior_state = null // no cooldown holds the next tactic back
		B.rebuild_behaviors()
		B.pack?.perceive(TRUE)
		B.pick_and_run()
		B.tactical_tick()
		if(B.active_behavior_type)
			B.stop_active(DQ_BEHAVIOR_STOP_COMPLETED)
	return B.started_counts

/// Takes the test's block back: what a creature shot, spawned or splattered while it was driven is the test's to clean up.
/datum/unit_test/proc/clean_port_arena()
	for(var/obj/item/grenade/G in range(14, ai_floor(0)))
		qdel(G) // a primed grenade would go off after the test and leave its smoke and gibs behind
	for(var/turf/T in range(14, ai_floor(0)))
		own_turf_contents(T)

/// The smoke check of one creature type: it has a brain, engages a target, and uses a tactic of its own (a scenario gives the special something to act on).
/datum/unit_test/proc/smoke_port_creature(mob_type, scenario = null)
	var/mob/living/simple_mob/S = allocate(mob_type, ai_floor(0))
	TEST_ASSERT_NOTNULL(S.ai_brain, "[mob_type] has no brain")
	var/datum/ai_brain/B = S.ai_brain
	B.rebuild_behaviors()
	var/list/own = list()
	for(var/btype in B.effective_behaviors)
		if(!dq_ai_generic_tactic(btype))
			own += btype
	if(scenario == SMOKE_INERT)
		TEST_ASSERT_EQUAL(length(TYPE_TABLE_GET(S, get_ai_behaviors)), 0, "[mob_type] is controlled from outside and should declare no tactic")
		TEST_ASSERT(B.pack, "[mob_type] is in no pack")
		return
	if(scenario == SMOKE_MACHINE)
		var/obj/machinery/M = allocate(/obj/machinery, ai_floor(2))
		M.idle_power_usage = 10
		TEST_ASSERT_NOTNULL(dq_ai_test_eval(B, /datum/ai_behavior/larva_infest_machine), "[mob_type] does not go for a powered machine")
		clean_port_arena()
		return
	var/mob/living/H
	if(scenario == SMOKE_HEAL)
		H = allocate(/mob/living/carbon/human/dq_ai_test_wounded, ai_floor(1))
		B.admin_standing(H, DQ_DISPOSITION_FRIENDLY)
		var/list/started_heal = drive_port_creature(S, H, 20, FALSE)
		clean_port_arena()
		TEST_ASSERT(length(started_heal), "[mob_type] never started a tactic with a wounded ally beside it")
		TEST_ASSERT(started_heal[/datum/ai_behavior/healbelly_heal_ally], "[mob_type] did not go to heal a wounded ally (started: [jointext(started_heal, ", ")])")
		return
	H = allocate(/mob/living/carbon/human, ai_floor(1))
	if(scenario == SMOKE_ANCHORED)
		S.set_anchored(TRUE)
	var/list/started = drive_port_creature(S, H, 20)
	H.forceMove(ai_floor(3))
	started = drive_port_creature(S, H, 20)
	S.set_stat(DEAD) // already dead when it goes: some creatures burst (gibs, a grenade's smoke) when they die by being deleted
	qdel(S)
	qdel(H)
	clean_port_arena()
	TEST_ASSERT(length(started), "[mob_type] never started a tactic against a target")
	if(length(own))
		var/used = FALSE
		for(var/btype in own)
			if(started[btype])
				used = TRUE
		TEST_ASSERT(used, "[mob_type] never used one of its own tactics ([length(own)] declared; started: [jointext(started, ", ")])")


/datum/unit_test/dq_ai_port_alchemistbee

/datum/unit_test/dq_ai_port_alchemistbee/Run()
	smoke_port_creature(/mob/living/simple_mob/vr/alchemistbee)

/datum/unit_test/dq_ai_port_armadillo

/datum/unit_test/dq_ai_port_armadillo/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/passive/armadillo)

/datum/unit_test/dq_ai_port_bigdragon

/datum/unit_test/dq_ai_port_bigdragon/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/bigdragon)

/datum/unit_test/dq_ai_port_blaidd

/datum/unit_test/dq_ai_port_blaidd/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/blaidd)

/datum/unit_test/dq_ai_port_broodmother

/datum/unit_test/dq_ai_port_broodmother/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/giant_spider/broodmother)

/datum/unit_test/dq_ai_port_ddraig

/datum/unit_test/dq_ai_port_ddraig/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/ddraig)

/datum/unit_test/dq_ai_port_fluffball

/datum/unit_test/dq_ai_port_fluffball/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/fluffball)

/datum/unit_test/dq_ai_port_glitch_boss

/datum/unit_test/dq_ai_port_glitch_boss/Run()
	smoke_port_creature(/mob/living/simple_mob/glitch_boss)

/datum/unit_test/dq_ai_port_glitch_boss_fake

/datum/unit_test/dq_ai_port_glitch_boss_fake/Run()
	smoke_port_creature(/mob/living/simple_mob/glitch_boss_fake)

/datum/unit_test/dq_ai_port_gryphon

/datum/unit_test/dq_ai_port_gryphon/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/gryphon)

/datum/unit_test/dq_ai_port_leopardmander

/datum/unit_test/dq_ai_port_leopardmander/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/leopardmander, SMOKE_HEAL)

/datum/unit_test/dq_ai_port_bigdragon_friendly

/datum/unit_test/dq_ai_port_bigdragon_friendly/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/bigdragon/friendly, SMOKE_HEAL)

/datum/unit_test/dq_ai_port_illusion

/datum/unit_test/dq_ai_port_illusion/Run()
	smoke_port_creature(/mob/living/simple_mob/illusion, SMOKE_INERT)

/datum/unit_test/dq_ai_port_juvenile_metroid

/datum/unit_test/dq_ai_port_juvenile_metroid/Run()
	smoke_port_creature(/mob/living/simple_mob/metroid/juvenile)

/datum/unit_test/dq_ai_port_kururak

/datum/unit_test/dq_ai_port_kururak/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/sif/kururak)

/datum/unit_test/dq_ai_port_leech

/datum/unit_test/dq_ai_port_leech/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/sif/leech)

/datum/unit_test/dq_ai_port_possessed

/datum/unit_test/dq_ai_port_possessed/Run()
	smoke_port_creature(/mob/living/simple_mob/humanoid/possessed)

/datum/unit_test/dq_ai_port_opossum

/datum/unit_test/dq_ai_port_opossum/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/passive/opossum)

/datum/unit_test/dq_ai_port_sakimm

/datum/unit_test/dq_ai_port_sakimm/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/sif/sakimm)

/datum/unit_test/dq_ai_port_scrubble

/datum/unit_test/dq_ai_port_scrubble/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/scrubble)

/datum/unit_test/dq_ai_port_siffet

/datum/unit_test/dq_ai_port_siffet/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/sif/siffet)

/datum/unit_test/dq_ai_port_slime

/datum/unit_test/dq_ai_port_slime/Run()
	smoke_port_creature(/mob/living/simple_mob/slime)

/datum/unit_test/dq_ai_port_solargrub

/datum/unit_test/dq_ai_port_solargrub/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/solargrub, SMOKE_ANCHORED)

/datum/unit_test/dq_ai_port_solargrub_larva

/datum/unit_test/dq_ai_port_solargrub_larva/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/solargrub_larva, SMOKE_MACHINE)

/datum/unit_test/dq_ai_port_spore

/datum/unit_test/dq_ai_port_spore/Run()
	smoke_port_creature(/mob/living/simple_mob/hostile/blob/spore)

/datum/unit_test/dq_ai_port_swoopie

/datum/unit_test/dq_ai_port_swoopie/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/aggressive/corrupthound/swoopie)

/datum/unit_test/dq_ai_port_eclipse_mecha

/datum/unit_test/dq_ai_port_eclipse_mecha/Run()
	smoke_port_creature(/mob/living/simple_mob/mechanical/mecha/eclipse)

/datum/unit_test/dq_ai_port_viscerator

/datum/unit_test/dq_ai_port_viscerator/Run()
	smoke_port_creature(/mob/living/simple_mob/mechanical/viscerator)

/datum/unit_test/dq_ai_port_ysbryd

/datum/unit_test/dq_ai_port_ysbryd/Run()
	smoke_port_creature(/mob/living/simple_mob/ysbryd)

/datum/unit_test/dq_ai_port_poppy

/datum/unit_test/dq_ai_port_poppy/Run()
	smoke_port_creature(/mob/living/simple_mob/animal/passive/opossum/poppy)

/datum/unit_test/dq_ai_port_teppi

/datum/unit_test/dq_ai_port_teppi/Run()
	smoke_port_creature(/mob/living/simple_mob/vore/alienanimals/teppi)

#endif
