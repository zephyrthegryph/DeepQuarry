// AI packs (code/modules/combat_ai/pack/, doc/rewrite/ai_packs.md B3): every brain is in a pack; a pack perceives once for its members, shares sightings
// after an alert delay, hands out targets by doctrine, and forms, splits and merges with hysteresis.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A faction that forms packs: a lone mob joins a leader within 1 tile, a member leaves beyond 3. No alert delay unless a test sets one.
/datum/faction_data/test_pack
	faction_key = "test_pack"
	player_disposition = DQ_DISPOSITION_HOSTILE
	pack_join_radius = 1
	pack_leave_radius = 3
	alert_delay = 0
	spread_cap = 2

/// The same, with the FOCUS doctrine.
/datum/faction_data/test_pack_focus
	faction_key = "test_pack_focus"
	player_disposition = DQ_DISPOSITION_HOSTILE
	pack_join_radius = 1
	pack_leave_radius = 3
	alert_delay = 0
	pack_doctrine = PACK_FOCUS

/mob/living/simple_mob/combat_ai_pack_subject
	name = "combat AI pack subject"
	icon = 'icons/mob/animal.dmi'
	icon_state = "tiger"
	icon_living = "tiger"
	icon_dead = "tiger-dead"
	faction = "test_pack"
	endurance = 90
	melee_damage_lower = 8
	melee_damage_upper = 14
	base_attack_cooldown = 1.2 SECONDS
	movement_cooldown = 2
	has_hands = FALSE
	can_pain_emote = FALSE
	use_modern_ai = TRUE

/mob/living/simple_mob/combat_ai_pack_subject/focus
	faction = "test_pack_focus"

/datum/unit_test/proc/pack_mob(dx, type = /mob/living/simple_mob/combat_ai_pack_subject)
	var/mob/living/simple_mob/S = allocate(type, ai_floor(dx))
	S.next_click = 0
	return S

/datum/unit_test/proc/pack_human(dx)
	return allocate(/mob/living/carbon/human, ai_floor(dx))

/// Every brain starts in a pack of one, led by itself; a faction that forms no packs has no upkeep timer.
/datum/unit_test/dq_ai_pack_of_one

/datum/unit_test/dq_ai_pack_of_one/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0))
	var/datum/ai_brain/B = S.ai_brain
	TEST_ASSERT_NOTNULL(B.pack, "a new brain has no pack")
	TEST_ASSERT_EQUAL(length(B.pack.members), 1, "a solo brain's pack is not a pack of one")
	TEST_ASSERT_EQUAL(B.pack.leader, B, "a pack of one is not led by its member")
	TEST_ASSERT(!B.pack.needs_upkeep, "a pack of a faction that forms no packs has an upkeep timer")
	var/datum/ai_pack/P = B.pack
	P.perceive(TRUE)
	TEST_ASSERT(!after_unique_pending(P, TYPE_PROC_REF(/datum/ai_pack, perceive_pending)), "a calm pack of one scheduled an alert timer")

/// A mob within the join radius of a leader joins its pack; one beyond does not.
/// Hysteresis: a member between the join and leave radii stays, one beyond the leave radius splits off, and packs whose leaders come within the join radius merge.
/datum/unit_test/dq_ai_pack_formation_and_hysteresis

/datum/unit_test/dq_ai_pack_formation_and_hysteresis/Run()
	set_global(nameof(GLOB.ai_pack_merges), GLOB.ai_pack_merges)
	set_global(nameof(GLOB.ai_pack_splits), GLOB.ai_pack_splits)
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(1)
	TEST_ASSERT_EQUAL(B.ai_brain.pack, A.ai_brain.pack, "a mob within the join radius of a leader did not join its pack")
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(length(P.members), 2, "the pack does not have both members")
	TEST_ASSERT(P.needs_upkeep, "a pack of a pack-forming faction has no upkeep")
	var/mob/living/simple_mob/C = pack_mob(3)
	TEST_ASSERT(C.ai_brain.pack != P, "a mob beyond the join radius joined the pack")
	// between the radii: stays
	B.forceMove(ai_floor(2))
	P.upkeep()
	TEST_ASSERT_EQUAL(B.ai_brain.pack, P, "a member between the join and leave radii left (no hysteresis)")
	// beyond the leave radius: splits
	var/splits = GLOB.ai_pack_splits
	B.forceMove(ai_floor(4))
	P.upkeep()
	TEST_ASSERT(B.ai_brain.pack != P, "a member beyond the leave radius stayed in the pack")
	TEST_ASSERT_EQUAL(length(P.members), 1, "the pack kept a member that split off")
	TEST_ASSERT_EQUAL(GLOB.ai_pack_splits, splits + 1, "the split was not counted")
	TEST_ASSERT_EQUAL(length(B.ai_brain.pack.members), 1, "the split member did not become a pack of one")
	// merge: the lone C comes within the join radius of A, the leader (C was at 3, B left it a pack of one at 4)
	var/merges = GLOB.ai_pack_merges
	C.forceMove(ai_floor(1))
	P.upkeep()
	TEST_ASSERT_EQUAL(C.ai_brain.pack, A.ai_brain.pack, "packs whose leaders came within the join radius did not merge")
	TEST_ASSERT_EQUAL(GLOB.ai_pack_merges, merges + 1, "the merge was not counted")
	var/datum/ai_pack/merged = A.ai_brain.pack
	TEST_ASSERT_EQUAL(length(merged.members), 2, "the merged pack has the wrong membership")

/// A leader that dies hands the pack to the next member; the last member's death deletes the pack.
/datum/unit_test/dq_ai_pack_leader_death_and_empty_pack

/datum/unit_test/dq_ai_pack_leader_death_and_empty_pack/Run()
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(1)
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(P.leader, A.ai_brain, "the first member is not the leader")
	A.set_stat(DEAD)
	TEST_ASSERT_NULL(A.ai_brain.pack, "a dead member kept its pack")
	TEST_ASSERT_EQUAL(P.leader, B.ai_brain, "the pack was not re-led after its leader died")
	TEST_ASSERT_EQUAL(length(P.members), 1, "the dead member is still in the pack")
	B.set_stat(DEAD)
	TEST_ASSERT(QDELETED(P), "a pack with no member left did not delete itself")

/// Sight is shared: the member nearest the hostile spots it and knows at once; the other members learn after the faction's alert delay.
/// One line-of-sight check is made per hostile, however many members the pack has.
/datum/unit_test/dq_ai_pack_shared_sight_and_alert_delay

/datum/unit_test/dq_ai_pack_shared_sight_and_alert_delay/Run()
	var/datum/faction_data/data = dq_faction_data_for("test_pack")
	var/old_delay = data.alert_delay
	data.alert_delay = 0.75 SECONDS
	var/mob/living/simple_mob/A = pack_mob(0)
	var/mob/living/simple_mob/B = pack_mob(1)
	var/mob/living/simple_mob/C = pack_mob(1)
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(length(P.members), 3, "three mobs did not form one pack")
	var/mob/living/carbon/human/H = pack_human(2)
	var/checks = GLOB.ai_pack_los_checks
	P.perceive(TRUE)
	TEST_ASSERT_EQUAL(GLOB.ai_pack_los_checks - checks, 1, "the pack made more than one line-of-sight check for one hostile")
	TEST_ASSERT(H in B.ai_brain.model.visible_hostiles, "the nearest member did not see the hostile at once")
	TEST_ASSERT(!(H in A.ai_brain.model.visible_hostiles), "a member far from the spotter knew the sighting before the alert delay")
	TEST_ASSERT(after_unique_pending(P, TYPE_PROC_REF(/datum/ai_pack, perceive_pending)), "no timer was left to deliver the delayed alert")
	for(var/key in P.sightings)
		P.sightings[key][SIGHT_FIRST_AT] = world.time - 2 SECONDS
	P.perceive(TRUE)
	TEST_ASSERT(H in A.ai_brain.model.visible_hostiles, "the alert did not reach a packmate after the delay")
	TEST_ASSERT(H in C.ai_brain.model.visible_hostiles, "the alert did not reach every packmate after the delay")
	data.alert_delay = old_delay

/// SPREAD (the default doctrine): no more than the cap of members on one target while another is open.
/datum/unit_test/dq_ai_pack_spread_targeting

/datum/unit_test/dq_ai_pack_spread_targeting/Run()
	var/mob/living/simple_mob/A = pack_mob(0)
	pack_mob(0)
	pack_mob(1)
	pack_mob(1)
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(length(P.members), 4, "four mobs did not form one pack")
	var/mob/living/carbon/human/H1 = pack_human(2)
	var/mob/living/carbon/human/H2 = pack_human(2)
	P.perceive(TRUE)
	var/list/load = list()
	for(var/datum/ai_brain/M as anything in P.members)
		TEST_ASSERT_NOTNULL(M.primary_threat, "a member of an engaged pack has no target")
		load[M.primary_threat] += 1
	TEST_ASSERT(load[H1] <= 2 && load[H2] <= 2, "SPREAD put more than the cap on one target (H1 [load[H1]], H2 [load[H2]])")
	TEST_ASSERT(load[H1] > 0 && load[H2] > 0, "SPREAD did not use both targets (H1 [load[H1]], H2 [load[H2]])")

/// FOCUS: members that know the leader's target take it.
/datum/unit_test/dq_ai_pack_focus_targeting

/datum/unit_test/dq_ai_pack_focus_targeting/Run()
	var/mob/living/simple_mob/A = pack_mob(0, /mob/living/simple_mob/combat_ai_pack_subject/focus)
	pack_mob(0, /mob/living/simple_mob/combat_ai_pack_subject/focus)
	pack_mob(1, /mob/living/simple_mob/combat_ai_pack_subject/focus)
	var/datum/ai_pack/P = A.ai_brain.pack
	TEST_ASSERT_EQUAL(length(P.members), 3, "three mobs did not form one pack")
	pack_human(2)
	pack_human(3)
	P.perceive(TRUE)
	var/mob/living/focus = P.leader.primary_threat
	TEST_ASSERT_NOTNULL(focus, "the leader has no target")
	for(var/datum/ai_brain/M as anything in P.members)
		TEST_ASSERT_EQUAL(M.primary_threat, focus, "a member did not follow the leader's target under FOCUS")

/// A pack of one sees exactly what the old per-brain pass saw through view(): invisible mobs, mobs behind an opaque object and the dead are not hostile sightings.
/datum/unit_test/dq_ai_pack_perception_parity

/datum/unit_test/dq_ai_pack_perception_parity/Run()
	var/mob/living/simple_mob/S = allocate(/mob/living/simple_mob/combat_ai_tactics_subject, ai_floor(0))
	var/datum/ai_brain/B = S.ai_brain
	var/mob/living/carbon/human/seen = pack_human(1)
	var/mob/living/carbon/human/invisible = pack_human(2)
	invisible.invisibility = INVISIBILITY_MAXIMUM
	var/obj/blocker = allocate(/obj, ai_floor(3))
	blocker.opacity = TRUE
	var/mob/living/carbon/human/behind = pack_human(4)
	var/mob/living/carbon/human/dead = pack_human(1)
	dead.set_stat(DEAD)
	var/list/expected = list()
	for(var/mob/living/M in view(B.vision_range, S))
		if(M == S || M.stat >= DEAD)
			continue
		if(B.disposition_to(M) <= DQ_DISPOSITION_HOSTILE)
			expected += M
	B.pack.perceive(TRUE)
	var/list/got = B.model.visible_hostiles
	for(var/mob/living/M as anything in expected)
		TEST_ASSERT(M in got, "pack perception missed [M] that view() showed the brain")
	for(var/mob/living/M as anything in got)
		TEST_ASSERT(M in expected, "pack perception saw [M] that view() did not show the brain")
	TEST_ASSERT(seen in got, "the plain fixture target was not seen")
	TEST_ASSERT(!(invisible in got), "an invisible mob was seen")
	TEST_ASSERT(!(behind in got), "a mob behind an opaque object was seen")
	TEST_ASSERT(!(dead in got), "a dead mob was seen")

#endif
