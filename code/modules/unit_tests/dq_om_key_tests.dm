// Change-channel wake tests: machines sleeping on watched channels and the AI brain's
// chunk hibernation. Held steady, each must stay asleep; after its input changes, it must
// wake. Each also checks sleep_violation() while asleep.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/datum/unit_test/dq_om_keys_wake_turret

/datum/unit_test/dq_om_keys_wake_turret/Run()
	var/turf/T = locate(1, 1, 1)
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret, T)
	dq_machine_clear(turret)
	turret.set_enabled(FALSE)
	TEST_ASSERT(!turret.armed, "a switched-off turret is not armed (its scan parks)")
	turret.set_enabled(TRUE)
	TEST_ASSERT(turret.armed, "switching it on arms it again (its scan wakes)")

/datum/unit_test/dq_om_keys_wake_calm_brain

/datum/unit_test/dq_om_keys_wake_calm_brain/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/mob/living/simple_mob/M = allocate(/mob/living/simple_mob, T)
	var/datum/ai_brain/B = M.ai_brain
	TEST_ASSERT_NOTNULL(B, "simple mob did not receive an AI brain")
	rel_clear(B, nameof(B.primary_threat))
	B.active_behavior_type = null
	var/mob/living/visitor = allocate(/mob/living, locate(world.maxx, world.maxy, T.z))
	TEST_ASSERT(B.park_calm(), "calm brain refused to park")
	TEST_ASSERT_NULL(B.sleep_violation(), "a calm parked brain reported a violation")
	visitor.forceMove(T)
	B.pack.perceive(TRUE) // the pack, which watches the chunks around its members, perceives the visitor
	TEST_ASSERT(B.loop_running(DQAI_PROCESSING), "woken brain did not rejoin the loop (wakes [B.wakes] parked [B.parked] passes [B.pack?.perceptions] friendlies [length(B.model.visible_friendlies)] visitor at [AREACOORD(visitor)] brain at [AREACOORD(M)])")
	// The audit catches a brain asleep with a threat.
	B.park_calm()
	rel_set(B, nameof(B.primary_threat), visitor)
	TEST_ASSERT(B.sleep_violation(), "the audit missed a hibernating brain with a threat")
	rel_clear(B, nameof(B.primary_threat))

/// One mob chunk key, two mask bits: a mob without a client wakes any-mob subscribers only.
/datum/unit_test/dq_om_keys_mob_chunk_masks

/datum/unit_test/dq_om_keys_mob_chunk_masks/Run()
	var/turf/T = run_loc_floor_bottom_left || locate(1, 1, 1)
	var/datum/om_wake_test_subscriber/players = allocate(/datum/om_wake_test_subscriber)
	var/datum/om_wake_test_subscriber/anyone = allocate(/datum/om_wake_test_subscriber)
	var/list/player_tokens = watch_mob_chunks(players, mob_chunks_around(T, 0), CHANGE_CHUNK_PLAYER, TYPE_PROC_REF(/datum/om_wake_test_subscriber, chunk_woke))
	var/list/any_tokens = watch_mob_chunks(anyone, list(mob_chunk(mob_chunk_id(T))), CHANGE_CHUNK_ANY_MOB, TYPE_PROC_REF(/datum/om_wake_test_subscriber, chunk_woke))
	var/mob/living/npc = allocate(/mob/living, locate(world.maxx, world.maxy, T.z))
	npc.forceMove(T)
	TEST_ASSERT(length(anyone.wakes), "a mob moving into the chunk did not wake an any-mob subscriber")
	TEST_ASSERT(!length(players.wakes), "a mob without a client woke a player-chunk subscriber")
	unwatch_mob_chunks(players, player_tokens, CHANGE_CHUNK_PLAYER)
	unwatch_mob_chunks(anyone, any_tokens, CHANGE_CHUNK_ANY_MOB)

#endif

