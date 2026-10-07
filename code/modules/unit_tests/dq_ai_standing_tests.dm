// AI standings (code/modules/combat_ai/standings/standings.dm, doc/rewrite/ai_packs.md B5): disposition_to() is standing_toward() of rows that providers place.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// The disposition rule the brain used before standings: the faction table, player_disposition for a client, and a simple mob that attacks on sight
/// turning a NEUTRAL stranger HOSTILE.
/proc/dq_old_disposition(datum/ai_brain/B, mob/other)
	var/datum/faction_data/data = dq_faction_data_for(B.get_owner().faction)
	var/result
	if(other.client)
		result = data.player_disposition
	else
		result = data.disposition_to_faction(other.faction)
	if(result == DQ_DISPOSITION_NEUTRAL && istype(B.get_owner(), /mob/living/simple_mob))
		var/mob/living/simple_mob/SM = B.get_owner()
		if(SM.ai_attack_on_sight && B.get_owner().faction != other.faction)
			result = DQ_DISPOSITION_HOSTILE
	return result

/// The faction rows give exactly what the old per-call lookups gave, for every pair of the registered factions (and an unregistered one), with and
/// without attack-on-sight.
/datum/unit_test/dq_ai_standing_faction_parity

/datum/unit_test/dq_ai_standing_faction_parity/Run()
	var/list/factions = list(FACTION_NEUTRAL, FACTION_STATION, FACTION_SYNDICATE, FACTION_HIVEBOT, FACTION_ECLIPSE, FACTION_WILD_ANIMAL, FACTION_CREATURE, FACTION_CULT, "unregistered_faction")
	var/list/mobs = list()
	for(var/faction in factions)
		var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0))
		S.faction = faction
		mobs += S
	var/checked = 0
	for(var/aggro in list(TRUE, FALSE))
		for(var/mob/living/simple_mob/A as anything in mobs)
			A.ai_attack_on_sight = aggro
		for(var/mob/living/simple_mob/A as anything in mobs)
			for(var/mob/living/simple_mob/B as anything in mobs)
				if(A == B)
					continue
				var/want = dq_old_disposition(A.ai_brain, B)
				var/got = A.ai_brain.disposition_to(B)
				checked++
				TEST_ASSERT_EQUAL(got, want, "[A.faction] toward [B.faction] (attack on sight [aggro]): standings gave [got], the old rule [want]")
	TEST_ASSERT(checked > 100, "the parity matrix did not run")

/// Grudges (60) beat the pack and the faction, effects (80) beat grudges, admin rows (100) beat effects; a row goes with its source.
/datum/unit_test/dq_ai_standing_provider_priorities

/datum/unit_test/dq_ai_standing_provider_priorities/Run()
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(1)
	var/datum/ai_brain/brain = A.ai_brain
	TEST_ASSERT_EQUAL(brain.disposition_to(B), DQ_DISPOSITION_ALLY, "a packmate is not an ally")
	TEST_ASSERT_EQUAL(standing_decided_by(A, B), A.ai_brain.pack, "the pack_member row does not decide a packmate's standing")
	brain.add_personal(B, DQ_DISPOSITION_HOSTILE, DQ_GRUDGE_DURATION, "test grudge")
	TEST_ASSERT_EQUAL(brain.disposition_to(B), DQ_DISPOSITION_HOSTILE, "a grudge did not override the pack_member row")
	TEST_ASSERT_EQUAL(standing_decided_by(A, B), brain, "the grudge row is not the decider")
	var/datum/effect = allocate(/datum)
	TEST_ASSERT(brain.place_effect_standing(effect, B, DQ_DISPOSITION_FRIENDLY), "the effect standing was refused")
	TEST_ASSERT_EQUAL(brain.disposition_to(B), DQ_DISPOSITION_FRIENDLY, "an effect did not override the grudge")
	TEST_ASSERT(brain.admin_standing(B, DQ_DISPOSITION_HOSTILE), "the admin standing was refused")
	TEST_ASSERT_EQUAL(brain.disposition_to(B), DQ_DISPOSITION_HOSTILE, "an admin row did not override the effect")
	unstanding(A, B, SRC_AI_ADMIN)
	TEST_ASSERT_EQUAL(brain.disposition_to(B), DQ_DISPOSITION_FRIENDLY, "releasing the admin row did not bring the effect back")
	qdel(effect)
	TEST_ASSERT_EQUAL(brain.disposition_to(B), DQ_DISPOSITION_HOSTILE, "deleting the effect did not bring the grudge back")
	TEST_ASSERT(brain.check_attacker(B), "the grudge is not read as an attacker")
	brain.forget_everything()
	TEST_ASSERT_EQUAL(brain.disposition_to(B), DQ_DISPOSITION_ALLY, "forgetting everything left a grudge")
	// a grudge has a deadline
	brain.add_personal(B, DQ_DISPOSITION_HOSTILE, DQ_GRUDGE_DURATION, "deadline")
	var/list/row = stat_hold_find(A.rx.stats, HOLD_STANDING, brain, standing_key(B))
	TEST_ASSERT_NOTNULL(row, "the grudge is not a standing row")
	TEST_ASSERT(row[H_EXPIRES] > world.time, "the grudge has no deadline")

/// The pack_member row exists only while the pack has more than one member, and goes with the pack.
/datum/unit_test/dq_ai_standing_pack_member_row

/datum/unit_test/dq_ai_standing_pack_member_row/Run()
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(1)
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(B.ai_brain.pack, P, "the two mobs did not form a pack")
	TEST_ASSERT_EQUAL(standing_decided_by(B, A), P, "a packmate's standing is not decided by the pack")
	B.ai_brain.leave_pack("test")
	TEST_ASSERT(standing_decided_by(B, A) != P, "a member that left kept its pack_member row")
	A.ai_brain.disposition_to(B) // the faction rows are placed on the first read
	TEST_ASSERT_EQUAL(standing_decided_by(A, B), SRC_AI_FACTION, "a pack of one still has a pack_member row")

#endif
